if isServer() and not isClient() then return end

require "ISUI/ISButton"
require "ISUI/ISContextMenu"
require "ISUI/ISPanel"
require "ISUI/ISToolTip"
require "XPR_UI_AdminMenu"

XPR_UI_Sidebar = XPR_UI_Sidebar or {}

local ICON_ON_PATH = "media/textures/xpr_icon_on.png"
local ICON_OFF_PATH = "media/textures/xpr_icon_off.png"
local ICON_SCALE_TICK = getTexture("media/textures/obnox_xpr_tick.png")
local ICON_SCALE_TICK_COLOUR = { r = 0, g = 1, b = 0 }
local ICON_SCALE_PRESETS = { 0.5, 1.0, 2.0 }

local createToolbarButton
local convertToDraggable
local convertToSidebar

local function canAccessAdminMenu()
	if XPR_UI_AdminMenu and XPR_UI_AdminMenu.hasAccess then
		return XPR_UI_AdminMenu.hasAccess()
	end
	if XPR_Env and XPR_Env.isTrueSinglePlayer() then return true end
	local player = getSpecificPlayer(0)
	local role = player and player.getRole and player:getRole()
	if role and role.hasAdminTool and role:hasAdminTool() == true then
		return true
	end
	return false
end

local function openAdminMenu()
	if not canAccessAdminMenu() then return end
	if XPR_UI_AdminMenu and XPR_UI_AdminMenu.open then XPR_UI_AdminMenu.open() end
end

local function normaliseIconScale(scale)
	scale = tonumber(scale) or 1.0
	for _, preset in ipairs(ICON_SCALE_PRESETS) do
		if math.abs(scale - preset) < 0.001 then return preset end
	end
	return 1.0
end

local function isDraggableEnabled()
	return XPR_ModOptions and XPR_ModOptions.isDraggableIconEnabled
		and XPR_ModOptions.isDraggableIconEnabled()
end

local function getIconScale()
	return normaliseIconScale(XPR_ModOptions and XPR_ModOptions.iconScale)
end

local function saveIconPresentation(x, y, scale)
	if not XPR_ModOptions then return end
	XPR_ModOptions.iconX = x
	XPR_ModOptions.iconY = y
	XPR_ModOptions.iconScale = normaliseIconScale(scale)
	if XPR_ModOptions.saveIconPresentation then
		XPR_ModOptions.saveIconPresentation(x, y, scale)
	end
end

local function loadTextures()
	if not XPR_UI_Sidebar.texOn then XPR_UI_Sidebar.texOn = getTexture(ICON_ON_PATH) end
	if not XPR_UI_Sidebar.texOff then XPR_UI_Sidebar.texOff = getTexture(ICON_OFF_PATH) end
end

local function getCurrentTexture()
	local active = XPR_UI_Leaderboard and XPR_UI_Leaderboard.instance ~= nil
	return active and XPR_UI_Sidebar.texOn or XPR_UI_Sidebar.texOff
end

local function getIconDimensions(sidebar, scale)
	local reference = sidebar and sidebar.invBtn
	local baseWidth = reference and reference:getWidth() or 48
	local baseHeight = reference and reference:getHeight() or 48
	scale = normaliseIconScale(scale)
	local width = math.max(1, math.floor(baseWidth * scale + 0.5))
	local height = math.max(1, math.floor(baseHeight * scale + 0.5))
	return width, height
end

local function clampIconPosition(x, y, width, height)
	local maxX = math.max(0, getPlayerScreenWidth(0) - width)
	local maxY = math.max(0, getPlayerScreenHeight(0) - height)
	return math.max(0, math.min(x or 200, maxX)),
		math.max(0, math.min(y or 100, maxY))
end

local function removeDraggableIcon()
	if not XPR_UI_Sidebar.draggableIcon then return end
	local tooltipUI = XPR_UI_Sidebar.draggableIcon.tooltipUI
	if tooltipUI and tooltipUI:getIsVisible() then
		tooltipUI:setVisible(false)
		tooltipUI:removeFromUIManager()
	end
	XPR_UI_Sidebar.draggableIcon:removeFromUIManager()
	XPR_UI_Sidebar.draggableIcon = nil
end

function XPR_UI_Sidebar.onClick()
	if not XPR_UI_Leaderboard then return end
	if XPR_UI_Leaderboard.instance then
		XPR_UI_Leaderboard.close()
	elseif XPR_UI_Leaderboard.open then
		XPR_UI_Leaderboard.open()
	end
end

XPRDraggableIcon = ISPanel:derive("XPRDraggableIcon")

function XPRDraggableIcon:new(x, y, width, height)
	local o = ISPanel.new(self, x, y, width, height)
	o.moveWithMouse = true
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	o.texture = getCurrentTexture()
	o.tooltip = getText("IGUI_XPR_Sidebar_Tooltip") or "XP Ranks Leaderboard"
	return o
end

function XPRDraggableIcon:updateTooltip()
	if self:isMouseOver() and self.tooltip then
		if not self.tooltipUI then
			self.tooltipUI = ISToolTip:new()
			self.tooltipUI:setOwner(self)
			self.tooltipUI:setVisible(false)
			self.tooltipUI:setAlwaysOnTop(true)
		end
		if not self.tooltipUI:getIsVisible() then
			self.tooltipUI.maxLineWidth = 300
			self.tooltipUI:addToUIManager()
			self.tooltipUI:setVisible(true)
		end
		self.tooltipUI.description = self.tooltip
		self.tooltipUI:setDesiredPosition(getMouseX(), self:getAbsoluteY() + self:getHeight() + 8)
	elseif self.tooltipUI and self.tooltipUI:getIsVisible() then
		self.tooltipUI:setVisible(false)
		self.tooltipUI:removeFromUIManager()
	end
end

function XPRDraggableIcon:prerender()
	ISPanel.prerender(self)
	if self.texture then
		local size = math.min(self:getWidth(), self:getHeight())
		local drawX = (self:getWidth() - size) / 2
		local drawY = (self:getHeight() - size) / 2
		self:drawTextureScaledAspect(self.texture, drawX, drawY, size, size, 1, 1, 1, 1)
	end
	self:updateTooltip()
end

function XPRDraggableIcon:onMouseDown(x, y)
	self.dragStartX = self:getX()
	self.dragStartY = self:getY()
	return ISPanel.onMouseDown(self, x, y)
end

function XPRDraggableIcon:onMouseUp(x, y)
	ISPanel.onMouseUp(self, x, y)
	local moved = self.dragStartX ~= self:getX() or self.dragStartY ~= self:getY()
	saveIconPresentation(self:getX(), self:getY(), getIconScale())
	if not moved then
		if not XPR_ModOptions or not XPR_ModOptions.areSoundsEnabled
				or XPR_ModOptions.areSoundsEnabled() then
			getSoundManager():playUISound("UIActivateButton")
		end
		XPR_UI_Sidebar.onClick()
	end
end

function XPRDraggableIcon:onRightMouseUp(x, y)
	local context = ISContextMenu.get(0, getMouseX(), getMouseY())
	local scaleOption = context:addOption(getText("IGUI_XPR_Sidebar_Scale") or "Scale", self, nil)
	scaleOption.tooltip = getText("IGUI_XPR_Sidebar_ScaleTooltip") or "Change the size of the XP Ranks icon"
	local scaleMenu = ISContextMenu:getNew(context)
	context:addSubMenu(scaleOption, scaleMenu)
	for _, scale in ipairs(ICON_SCALE_PRESETS) do
		local option = scaleMenu:addOption(string.format("%.2gx", scale), self, XPR_UI_Sidebar.setIconScale, scale)
		if ICON_SCALE_TICK and math.abs(scale - getIconScale()) < 0.001 then
			option.iconTexture = ICON_SCALE_TICK
			option.color = ICON_SCALE_TICK_COLOUR
		end
	end
	context:addOption(getText("IGUI_XPR_Sidebar_ConvertToSidebar") or "Convert to Sidebar Icon", nil, convertToSidebar)
	if canAccessAdminMenu() then
		context:addOption(getText("IGUI_XPR_Sidebar_AdminMenu") or "Admin Menu", nil, openAdminMenu)
	end
	return true
end

local function ensureDraggableIcon(sidebar)
	loadTextures()
	local width, height = getIconDimensions(sidebar, getIconScale())
	local panel = XPR_UI_Sidebar.draggableIcon
	if panel then
		if panel:getWidth() ~= width or panel:getHeight() ~= height then
			local centreX = panel:getX() + panel:getWidth() / 2
			local centreY = panel:getY() + panel:getHeight() / 2
			local newX, newY = clampIconPosition(centreX - width / 2, centreY - height / 2, width, height)
			panel:setWidth(width)
			panel:setHeight(height)
			panel:setX(newX)
			panel:setY(newY)
			saveIconPresentation(newX, newY, getIconScale())
		end
		panel.texture = getCurrentTexture()
		return
	end
	local iconX = XPR_ModOptions and XPR_ModOptions.iconX
	local iconY = XPR_ModOptions and XPR_ModOptions.iconY
	iconX, iconY = clampIconPosition(iconX, iconY, width, height)
	XPR_dprint("[XPR Sidebar] ensureDraggableIcon: creating at x=" .. tostring(iconX) .. " y=" .. tostring(iconY)
		.. " w=" .. tostring(width) .. " h=" .. tostring(height))
	panel = XPRDraggableIcon:new(iconX, iconY, width, height)
	panel:initialise()
	panel:instantiate()
	panel:addToUIManager()
	panel:setAlwaysOnTop(true)
	XPR_UI_Sidebar.draggableIcon = panel
	saveIconPresentation(iconX, iconY, getIconScale())
end

function XPR_UI_Sidebar.setIconScale(panel, scale)
	if not panel then return end
	scale = normaliseIconScale(scale)
	local centreX = panel:getX() + panel:getWidth() / 2
	local centreY = panel:getY() + panel:getHeight() / 2
	local width, height = getIconDimensions(ISEquippedItem and ISEquippedItem.instance, scale)
	local iconX, iconY = clampIconPosition(centreX - width / 2, centreY - height / 2, width, height)
	panel:setWidth(width)
	panel:setHeight(height)
	panel:setX(iconX)
	panel:setY(iconY)
	saveIconPresentation(iconX, iconY, scale)
end

convertToDraggable = function()
	local button = XPR_UI_Sidebar.toolbarBtn
	XPR_dprint("[XPR Sidebar] convertToDraggable: sidebarBtn id=" .. tostring(button and button.ID)
		.. " y=" .. tostring(button and button:getY()))
	local iconX = XPR_ModOptions and XPR_ModOptions.iconX
	local iconY = XPR_ModOptions and XPR_ModOptions.iconY
	if button then
		iconX = button:getAbsoluteX()
		iconY = button:getAbsoluteY()
		button:setVisible(false)
	end
	if XPR_ModOptions then XPR_ModOptions.useDraggableIcon = true end
	saveIconPresentation(iconX, iconY, getIconScale())
	ensureDraggableIcon(ISEquippedItem and ISEquippedItem.instance)
end

convertToSidebar = function()
	local panel = XPR_UI_Sidebar.draggableIcon
	XPR_dprint("[XPR Sidebar] convertToSidebar: draggableIcon=" .. tostring(panel))
	if panel then saveIconPresentation(panel:getX(), panel:getY(), getIconScale()) end
	if XPR_ModOptions then XPR_ModOptions.useDraggableIcon = false end
	removeDraggableIcon()
	local button = XPR_UI_Sidebar.toolbarBtn
	if button then
		button:setVisible(true)
	end
	if XPR_ModOptions and XPR_ModOptions.saveIconPresentation then
		XPR_ModOptions.saveIconPresentation(XPR_ModOptions.iconX, XPR_ModOptions.iconY, getIconScale())
	end
end

function XPR_UI_Sidebar.setDraggableEnabled(enabled)
	if enabled then
		convertToDraggable()
	else
		convertToSidebar()
	end
end

local function applyIconMode(inst)
	local button = XPR_UI_Sidebar.toolbarBtn
	if not button then return end
	button:setImage(getCurrentTexture())
	button.tooltip = getText("IGUI_XPR_Sidebar_Tooltip") or "XP Ranks Leaderboard"
	if isDraggableEnabled() then
		button:setVisible(false)
		ensureDraggableIcon(inst)
	else
		removeDraggableIcon()
	end
end

createToolbarButton = function(inst)
	if not inst then return end
	local existing = inst.xprLeaderboardBtn
	if existing then
		XPR_UI_Sidebar.toolbarBtn = existing
		applyIconMode(inst)
		return
	end
	loadTextures()
	local reference = inst.invBtn
	local baseX = reference and reference:getX() or 1
	local iconW, iconH = getIconDimensions(inst, 1.0)

	local y = inst:getHeight() + 15
	local texture = getCurrentTexture()
	local button = ISButton:new(baseX, y, iconW, iconH,
		texture and "" or "XP", nil, XPR_UI_Sidebar.onClick)
	button:initialise()
	button:instantiate()
	button.Type = "ISButton"
	button.internal = "XPR_LeaderboardBtn"
	button:setImage(texture)
	button:setDisplayBackground(false)
	button.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	button.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
	button.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	button.tooltip = getText("IGUI_XPR_Sidebar_Tooltip") or "XP Ranks Leaderboard"
	function button:render()
		local textureToDraw = self.image
		if not textureToDraw then
			ISButton.render(self)
			return
		end
		local size = math.min(self:getWidth(), self:getHeight())
		local drawX = (self:getWidth() - size) / 2
		local drawY = (self:getHeight() - size) / 2
		local colour = self.textureColor or { r = 1, g = 1, b = 1, a = 1 }
		self:drawTextureScaledAspect(textureToDraw, drawX, drawY, size, size,
			colour.a or 1, colour.r or 1, colour.g or 1, colour.b or 1)
	end
	function button:onRightMouseUp(x, y)
		local context = ISContextMenu.get(0, getMouseX(), getMouseY())
		context:addOption(getText("IGUI_XPR_Sidebar_ConvertToDraggable") or "Convert to Draggable Icon", nil, convertToDraggable)
		if canAccessAdminMenu() then
			context:addOption(getText("IGUI_XPR_Sidebar_AdminMenu") or "Admin Menu", nil, openAdminMenu)
		end
		return true
	end
	inst:addChild(button)
	inst.xprLeaderboardBtn = button
	if inst:getHeight() < button:getBottom() then
		inst:setHeight(button:getBottom())
	end
	XPR_UI_Sidebar.toolbarBtn = button
	XPR_dprint("[XPR Sidebar] createToolbarButton: created id=" .. tostring(button.ID)
		.. " internal=" .. tostring(button.internal) .. " startY=" .. tostring(button:getY()))
	applyIconMode(inst)
end

function XPR_UI_Sidebar.setActive(active)
	local texture = active and XPR_UI_Sidebar.texOn or XPR_UI_Sidebar.texOff
	if XPR_UI_Sidebar.toolbarBtn then XPR_UI_Sidebar.toolbarBtn:setImage(texture) end
	if XPR_UI_Sidebar.draggableIcon then XPR_UI_Sidebar.draggableIcon.texture = texture end
end

local function installRebuildWrapper()
	if XPR_UI_Sidebar._sidebarInstalled or not ISEquippedItem then return end
	XPR_UI_Sidebar._sidebarInstalled = true
	local originalInitialise = ISEquippedItem.initialise
	function ISEquippedItem:initialise()
		if originalInitialise then originalInitialise(self) end
		if self.playerNum == 0 then
			createToolbarButton(self)
		end
	end
end

local function installCheckToolTipGuard()
	if not ISEquippedItem or ISEquippedItem.__obnoxCheckToolTipGuard then return end
	ISEquippedItem.__obnoxCheckToolTipGuard = true
	local originalCheckToolTip = ISEquippedItem.checkToolTip
	function ISEquippedItem:checkToolTip()
		if not getPlayerContextMenu(self.playerNum) then return end
		return originalCheckToolTip(self)
	end
end

local _xprCreateIconPending = false
local function xprOnTickCreateIcon()
	if not _xprCreateIconPending then return end
	_xprCreateIconPending = false
	Events.OnTick.Remove(xprOnTickCreateIcon)
	if not ISEquippedItem or not ISEquippedItem.instance then return end
	createToolbarButton(ISEquippedItem.instance)
	installRebuildWrapper()
	installCheckToolTipGuard()
end

local function onCreatePlayer(playerIndex, player)
	if playerIndex ~= 0 then return end
	_xprCreateIconPending = true
	if Events then Events.OnTick.Add(xprOnTickCreateIcon) end
end

if Events then
	Events.OnCreatePlayer.Add(onCreatePlayer)
end

return XPR_UI_Sidebar
