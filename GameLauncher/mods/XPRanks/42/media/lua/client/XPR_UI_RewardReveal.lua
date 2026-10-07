if isServer() and not isClient() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "XPR_UI_Scale"

local S = XPR_UI_Scale.s

XPR_UI_RewardReveal = {}
XPR_UI_RewardReveal.instance = nil

local rng = newrandom()

local CELL_W = S(90)
local CELL_H = S(90)
local VISIBLE_CELLS = 7
local STRIP_LENGTH = 40
local RESULT_INDEX = 34
local SPIN_DURATION_MS = (XPR_RewardBox and XPR_RewardBox.SPIN_DURATION_MS) or 7000

local PANEL_W = CELL_W * VISIBLE_CELLS + S(40)
local PANEL_H = CELL_H + S(240)

local FONT_MED = UIFont.Medium
local FONT_LG = UIFont.Large

local texFadeCell = getTexture("media/textures/xpr_fade_cell.png")
local FADE_W = S(90)

local TITLE_Y = S(15)
local CLOSE_BOTTOM_MARGIN = S(45)
local RECEIVED_NAME_GAP = S(5)

local xpBonusIcon = getTexture("media/textures/xpr_icon_on.png")

local function getItemTexture(itemId)
	if XPR_RewardItems and XPR_RewardItems.isXpBonus(itemId) then
		return xpBonusIcon
	end

	if XPR_RewardItems and XPR_RewardItems.isSkillVhs(itemId) then
		local fullType = XPR_RewardItems.getSkillVhsFullType(itemId)
		return fullType and getItemTexture(fullType)
	end

	if XPR_RewardItems and XPR_RewardItems.isRecipeItem(itemId) then
		local fullType = XPR_RewardItems.getRecipeItemFullType(itemId)
		return fullType and getItemTexture(fullType)
	end

	local scriptItem = ScriptManager.instance and ScriptManager.instance:getItem(itemId)
	if not scriptItem then return nil end

	local tex = scriptItem.getNormalTexture and scriptItem:getNormalTexture()

	if scriptItem.getIconsForTexture then
		local variants = scriptItem:getIconsForTexture()
		if variants and not variants:isEmpty() then
			local variant = variants:get(0)
			if type(variant) == "string" then
				tex = getTexture("Item_" .. variant) or tex
			else
				tex = variant
			end
		end
	end

	return tex
end

local function getItemDisplayName(itemId)
	if XPR_RewardItems and XPR_RewardItems.isXpBonus(itemId) then
		return "+" .. tostring(XPR_RewardItems.getXpBonusAmount(itemId)) .. " XP"
	end

	if XPR_RewardItems and XPR_RewardItems.isSkillVhs(itemId) then
		return XPR_RewardItems.getSkillVhsDisplayName(itemId)
	end

	if XPR_RewardItems and XPR_RewardItems.isRecipeItem(itemId) then
		return XPR_RewardItems.getRecipeItemDisplayName(itemId)
	end

	local scriptItem = ScriptManager.instance and ScriptManager.instance:getItem(itemId)
	if not scriptItem then return itemId end
	local displayName = scriptItem:getDisplayName() or itemId
	if XPR_RewardItems and XPR_RewardItems.isRandomizedOnGrant(itemId) then
		displayName = displayName .. " (Random)"
	end
	return displayName
end

local function easeOutCubic(t)
	local inv = 1 - t
	return 1 - inv * inv * inv
end

local function buildStrip(resultItemId)
	local pool = {}
	if XPR_RewardItems and XPR_RewardItems.getEffectivePool then
		for _, id in ipairs(XPR_RewardItems.getEffectivePool("COMMON")) do pool[#pool + 1] = id end
		for _, id in ipairs(XPR_RewardItems.getEffectivePool("UNCOMMON")) do pool[#pool + 1] = id end
		for _, id in ipairs(XPR_RewardItems.getEffectivePool("RARE")) do pool[#pool + 1] = id end
	end
	if #pool == 0 then pool = { resultItemId } end

	local strip = {}
	for i = 1, STRIP_LENGTH do
		if i == RESULT_INDEX then
			strip[i] = resultItemId
		else
			strip[i] = pool[rng:random(1, #pool)]
		end
	end
	return strip
end

XPR_UI_RewardReveal.Panel = ISPanel:derive("XPR_UI_RewardReveal_Panel")

function XPR_UI_RewardReveal.Panel:new(x, y, resultItemId, rank, panelW)
	local o = ISPanel.new(self, x, y, panelW or PANEL_W, PANEL_H)
	o.backgroundColor.r = 0
	o.backgroundColor.g = 0
	o.backgroundColor.b = 0
	o.backgroundColor.a = 0.9
	o.resultItemId = resultItemId
	o.rank = rank
	o.strip = buildStrip(resultItemId)
	o.startMs = getTimestampMs and getTimestampMs() or 0
	o.spinning = true
	o.moveWithMouse = true
	o.offset = 0
	o.lastCellIndex = nil
	o._panelW = panelW or PANEL_W
	return o
end

function XPR_UI_RewardReveal.Panel:initialise()
	ISPanel.initialise(self)
end

function XPR_UI_RewardReveal.Panel:createChildren()
	ISPanel.createChildren(self)

	self.closeButton = ISButton:new((self._panelW or PANEL_W) / 2 - S(50), PANEL_H - CLOSE_BOTTOM_MARGIN, S(100), S(30),
		getText("UI_Close") or "Close", self, XPR_UI_RewardReveal.Panel.onClose)
	self.closeButton:initialise()
	self.closeButton:instantiate()
	self.closeButton.visible = false
	self:addChild(self.closeButton)
end

function XPR_UI_RewardReveal.Panel:onClose()
	XPR_UI_RewardReveal.close()
end

function XPR_UI_RewardReveal.Panel:getTargetOffset()
	local viewportCenter = (self._panelW or PANEL_W) / 2
	return (RESULT_INDEX - 1) * CELL_W + CELL_W / 2 - viewportCenter
end

function XPR_UI_RewardReveal.Panel:update()
	ISPanel.update(self)

	local targetOffset = self:getTargetOffset()

	if not self.spinning then
		self.offset = targetOffset
		return
	end

	local now = getTimestampMs and getTimestampMs() or 0
	local elapsed = now - self.startMs
	if elapsed >= SPIN_DURATION_MS then
		self.spinning = false
		self.offset = targetOffset
		if self.closeButton then self.closeButton.visible = true end
		return
	end

	local t = elapsed / SPIN_DURATION_MS
	self.offset = easeOutCubic(t) * targetOffset

	local viewportCenter = (self._panelW or PANEL_W) / 2
	local centeredIndex = math.floor((self.offset + viewportCenter) / CELL_W) + 1
	if centeredIndex ~= self.lastCellIndex then
		self.lastCellIndex = centeredIndex
		if not XPR_ModOptions or not XPR_ModOptions.areSoundsEnabled
				or XPR_ModOptions.areSoundsEnabled() then
			getSoundManager():playUISound("UIActivateButton")
		end
	end
end

function XPR_UI_RewardReveal.Panel:prerender()
	ISPanel.prerender(self)

	local offset = self.offset
	local viewportCenter = (self._panelW or PANEL_W) / 2

	local tm = getTextManager()

	local fontHgtMed = tm:getFontHeight(FONT_MED)
	local fontHgtLg = tm:getFontHeight(FONT_LG)

	local closeY = PANEL_H - CLOSE_BOTTOM_MARGIN
	local nameY = (closeY - RECEIVED_NAME_GAP) - fontHgtLg
	local receivedY = nameY - RECEIVED_NAME_GAP - fontHgtMed

	local stripTop = (TITLE_Y + receivedY) / 2 - CELL_H / 2

	local titleDrawY = TITLE_Y + S(5)
	stripTop = stripTop + S(20)
	receivedY = receivedY - S(10)
	nameY = nameY - S(10)

	local boxName = XPR_RewardBox and XPR_RewardBox.buildDisplayName(self.rank)
		or getText("IGUI_XPR_RewardBox_Name", self.rank)
	local boxNameW = tm:MeasureStringX(FONT_LG, boxName)
	self:drawText(boxName, ((self._panelW or PANEL_W) - boxNameW) / 2, titleDrawY, 1, 1, 1, 1, FONT_LG)

	self:drawRect(0, stripTop - S(16), self._panelW or PANEL_W, CELL_H + S(32), 0.5, 0, 0, 0)

	self:setStencilRect(0, stripTop, self._panelW or PANEL_W, CELL_H)
	for i, itemId in ipairs(self.strip) do
		local cellCenterX = (i - 1) * CELL_W + CELL_W / 2 - offset
		local drawX = cellCenterX - CELL_W / 2
		if drawX > -CELL_W and drawX < (self._panelW or PANEL_W) then
			local tex = getItemTexture(itemId)
			self:drawRect(drawX + S(4), stripTop + S(4), CELL_W - S(8), CELL_H - S(8), 0, 0.1, 0.1, 0.1)
			if tex then
				local iw, ih
				if tex.getWidthOrig and tex.getHeightOrig then
					iw, ih = tex:getWidthOrig(), tex:getHeightOrig()
				else
					iw, ih = CELL_W - S(16), CELL_H - S(16)
				end
				local scale = math.min((CELL_W - S(16)) / iw, (CELL_H - S(16)) / ih)
				local dw, dh = iw * scale, ih * scale
				self:drawTextureScaled(tex, drawX + (CELL_W - dw) / 2, stripTop + (CELL_H - dh) / 2,
					dw, dh, 1, 1, 1, 1)
			end
		end
	end

	if texFadeCell then
		self:drawTextureScaled(texFadeCell, 0, stripTop, FADE_W, CELL_H, 1, 1, 1, 1)
		self:drawTextureScaled(texFadeCell, self._panelW or PANEL_W, stripTop, -FADE_W, CELL_H, 1, 1, 1, 1)
	end

	self:clearStencilRect()

	local markerX = viewportCenter - CELL_W / 2
	self:drawRectBorder(markerX, stripTop, CELL_W, CELL_H, 1, 1, 0.85, 0.1)
	self:drawRectBorder(markerX + S(1), stripTop + S(1), CELL_W - S(2), CELL_H - S(2), 1, 1, 0.85, 0.1)

	if not self.spinning then
		local name = getItemDisplayName(self.resultItemId)

		local receivedText = getText("IGUI_XPR_RewardBox_YouReceived") or "You Received:"
		local receivedW = tm:MeasureStringX(FONT_MED, receivedText)
		self:drawText(receivedText, ((self._panelW or PANEL_W) - receivedW) / 2, receivedY,
			1, 1, 1, 1, FONT_MED)

		local nameW = tm:MeasureStringX(FONT_LG, name)
		self:drawText(name, ((self._panelW or PANEL_W) - nameW) / 2, nameY,
			1, 1, 1, 1, FONT_LG)
	else
		local title = getText("IGUI_XPR_RewardBox_Opening") or "Opening Reward Box..."
		local titleW = tm:MeasureStringX(FONT_MED, title)
		self:drawText(title, ((self._panelW or PANEL_W) - titleW) / 2, receivedY, 1, 1, 1, 1, FONT_MED)
	end

	self:drawRectBorder(0, 0, self.width, self.height, 1, 1, 1, 1)
end

local WINDOW_POS_KEY = "XPR_ClientPrefs"

local function getSavedPos(defX, defY)
	local prefs = ModData.getOrCreate(WINDOW_POS_KEY)
	if prefs.rewardRevealX and prefs.rewardRevealY then
		return prefs.rewardRevealX, prefs.rewardRevealY
	end
	return defX, defY
end

local function savePos(x, y)
	local prefs = ModData.getOrCreate(WINDOW_POS_KEY)
	prefs.rewardRevealX = x
	prefs.rewardRevealY = y
end

function XPR_UI_RewardReveal.open(resultItemId, rank)
	if XPR_UI_RewardReveal.instance then
		XPR_UI_RewardReveal.close()
	end

	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local receivedW = XPR_UI_Scale.measureText(FONT_MED, getText("IGUI_XPR_RewardBox_YouReceived"))
	local openingW = XPR_UI_Scale.measureText(FONT_MED, getText("IGUI_XPR_RewardBox_Opening"))
	local nameW = XPR_UI_Scale.measureText(FONT_LG, getItemDisplayName(resultItemId))
	local panelW = math.max(PANEL_W, receivedW + S(40), openingW + S(40), nameW + S(40))
	panelW = math.min(panelW, screenW - S(40))
	local defX = (screenW - panelW) / 2
	local defY = (screenH - PANEL_H) / 2
	local x, y = getSavedPos(defX, defY)
	x = math.max(0, math.min(x, screenW - panelW))
	y = math.max(0, math.min(y, screenH - PANEL_H))

	local panel = XPR_UI_RewardReveal.Panel:new(x, y, resultItemId, rank, panelW)
	panel:initialise()
	panel:instantiate()
	panel:addToUIManager()
	panel:setVisible(true)
	XPR_UI_RewardReveal.instance = panel
end

function XPR_UI_RewardReveal.close()
	if XPR_UI_RewardReveal.instance then
		savePos(XPR_UI_RewardReveal.instance:getX(), XPR_UI_RewardReveal.instance:getY())
		XPR_UI_RewardReveal.instance:removeFromUIManager()
		XPR_UI_RewardReveal.instance = nil
	end
end

return XPR_UI_RewardReveal
