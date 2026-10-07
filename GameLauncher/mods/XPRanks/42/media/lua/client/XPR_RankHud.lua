if isServer() and not isClient() then return end

require "ISUI/ISPanel"
require "ObNoxToast"

local texBg = getTexture("media/textures/obnox_toast_bg.png")
local texShield = getTexture("media/textures/xpr_rank_shield.png")

local numTextures = {}
for i = 0, 9 do
	numTextures[i] = getTexture("media/textures/xpr_num_" .. i .. ".png")
end

local XP_FONT_NAMES = { [UIFont.Small] = "Small", [UIFont.Medium] = "Medium", [UIFont.Large] = "Large" }
local SCALE_FONT_MAP = {
	[0.5] = UIFont.Small,
	[1.0] = UIFont.Medium,
	[2.0] = UIFont.Large,
}

local function pickFont(scale)
	local font = SCALE_FONT_MAP[scale] or UIFont.Small
	local ratio = getTextManager():getFontHeight(font) / ObNoxToast.REFERENCE_FONT_HEIGHT
	return font, XP_FONT_NAMES[font], ratio
end

local COL_TEXT = { r=1, g=1, b=1 }
local COL_BAR_FG = { r=1, g=1, b=1 }

local function digitNudge(i, numDigits, spacing, spacing2)
	local sp = (numDigits == 2) and spacing2 or spacing
	return (i - (numDigits + 1) / 2) * sp
end

local function computeHudDims(scale)
	scale = scale or 1.0
	local font, fontName, ratio = pickFont(scale)
	return {
		panelW = 550 * ratio,
		panelH = 150 * ratio,
		shieldPadLeft = 30 * ratio,
		shieldSize = 96 * ratio,
		digitSpacing = 20 * ratio,
		digitSpacing2 = 24 * ratio,
		font = font,
		fontName = fontName,
		ratio = ratio,
	}
end

local POS_FILE = "XPRanks/XPR_HudPos.txt"
local DEFAULT_X = 200
local DEFAULT_Y = 100

local function loadPosition()
	local reader = getFileReader(POS_FILE, false)
	if not reader then return nil, nil end
	local line = reader:readLine()
	reader:close()
	if not line then return nil, nil end
	local x, y = string.match(line, "^(%-?%d+),(%-?%d+)$")
	return tonumber(x), tonumber(y)
end

local function savePosition(x, y)
	local writer = getFileWriter(POS_FILE, true, false)
	if not writer then return end
	writer:write(tostring(x) .. "," .. tostring(y))
	writer:close()
end

local function resetPosition()
	local writer = getFileWriter(POS_FILE, true, false)
	if writer then writer:close() end
end

local function isPauseMenuOpen()
	return MainScreen ~= nil and MainScreen.instance ~= nil
		and MainScreen.instance.inGame == true
		and MainScreen.instance:isReallyVisible()
end

XPR_RankHud = {}
XPR_RankHud.instance = nil
XPR_RankHud.playerDead = false

XPR_RankHud.Panel = ISPanel:derive("XPR_RankHud_Panel")

function XPR_RankHud.Panel:new(x, y, scale)
	scale = scale or (ObNoxToast and ObNoxToast.getScale and ObNoxToast.getScale()) or 1.0
	local dims = computeHudDims(scale)
	local o = ISPanel.new(self, x, y, dims.panelW, dims.panelH)
	o.scale = scale
	o.dims = dims
	o.moveWithMouse = true
	return o
end

function XPR_RankHud.Panel:initialise()
	ISPanel.initialise(self)
end

function XPR_RankHud.Panel:applyScale(scale, persist, anchorX, anchorY)
	scale = tonumber(scale)
	if not scale then return end
	local rawScale = scale
	if ObNoxToast and ObNoxToast.clampScale then
		scale = ObNoxToast.clampScale(scale)
	end
	local clamped = (rawScale ~= scale)

	anchorX = anchorX or (self:getX() + self:getWidth() / 2)
	anchorY = anchorY or (self:getY() + self:getHeight() / 2)

	local dims = computeHudDims(scale)
	self.scale = scale
	self.dims = dims
	self:setWidth(dims.panelW)
	self:setHeight(dims.panelH)
	self:setX(anchorX - dims.panelW / 2)
	self:setY(anchorY - dims.panelH / 2)

	XPR_dprint("[XPR] RankHud scale=" .. string.format("%.3f", scale)
		.. " panelPx=" .. math.floor(dims.panelW) .. "x" .. math.floor(dims.panelH)
		.. " fontRatio=" .. string.format("%.3f", dims.ratio)
		.. " xpFont=" .. tostring(dims.fontName)
		.. (clamped and " [AT MIN/MAX CLAMP -- ObNoxToast.MIN_SCALE/MAX_SCALE]" or ""))

	if persist and ObNoxToast and ObNoxToast.setScale then
		ObNoxToast.setScale(scale)
	end
end

function XPR_RankHud.Panel:update()
	ISPanel.update(self)
	local attached = not XPR_ModOptions or XPR_ModOptions.isHudAttachedToRadial()
	if XPR_RankHud.playerDead and not attached then
		if self:isReallyVisible() then self:setVisible(false) end
		return
	end

	if isPauseMenuOpen() then
		if self:isReallyVisible() then
			self:setVisible(false)
		end
		return
	end

	if self.scaleMenu and self.scaleMenu:isVisible() then
		if not self:isReallyVisible() then
			self:setVisible(true)
		end
		return
	end

	if not attached then
		if not self:isReallyVisible() then
			self:setVisible(true)
		end
		return
	end

	local radialMenu = getPlayerRadialMenu(0)
	local shouldBeVisible = radialMenu and radialMenu:isReallyVisible()
	if shouldBeVisible and not self:isReallyVisible() then
		self:setVisible(true)
	elseif not shouldBeVisible and self:isReallyVisible() then
		savePosition(self:getX(), self:getY())
		self:setVisible(false)
	end
end

function XPR_RankHud.Panel:onMouseUp(x, y)
	ISPanel.onMouseUp(self, x, y)
	savePosition(self:getX(), self:getY())
end

function XPR_RankHud.Panel:onSelectScale(scale)
	local anchorX = self:getX() + self:getWidth() / 2
	local anchorY = self:getY() + self:getHeight() / 2
	self:applyScale(scale, true, anchorX, anchorY)
end

function XPR_RankHud.Panel:onResetPosition()
	self:setX(DEFAULT_X)
	self:setY(DEFAULT_Y)
	resetPosition()
end

function XPR_RankHud.Panel:onRightMouseUp(x, y)
	local context = ObNoxToast.openScaleMenu(0, getMouseX(), getMouseY(), self, self.onSelectScale)
	ObNoxToast.openPositionMenu(0, getMouseX(), getMouseY(), self, self.onResetPosition, context)
	self.scaleMenu = context
	return true
end

function XPR_RankHud.Panel:prerender()
	if not self:isReallyVisible() then return end

	local dims = self.dims
	local shieldPadLeft = dims.shieldPadLeft
	local shieldSize = dims.shieldSize

	if texBg then
		self:drawTextureScaled(texBg, 0, 0, self.width, self.height, 1, 1, 1, 1)
	end

	if texShield then
		local shieldX = shieldPadLeft
		local shieldY = (self.height - shieldSize) / 2
		self:drawTextureScaled(texShield, shieldX, shieldY, shieldSize, shieldSize, 1, 1, 1, 1)
	end

	local state = XPR_ClientSync and XPR_ClientSync.getState(getSpecificPlayer(0))
	local rank = (state and state.rank) or 1
	local totalXp = (state and state.totalXp) or 0

	local rankStr = tostring(rank)
	local numDigits = #rankStr
	local shieldCenterX = shieldPadLeft + shieldSize / 2
	local shieldCenterY = (self.height - shieldSize) / 2 + shieldSize / 2

	for i = 1, numDigits do
		local digit = tonumber(string.sub(rankStr, i, i))
		local tex = numTextures[digit]
		if tex then
			local nudge = digitNudge(i, numDigits, dims.digitSpacing, dims.digitSpacing2)
			local dx = shieldCenterX - shieldSize / 2 + nudge
			local dy = shieldCenterY - shieldSize / 2
			self:drawTextureScaled(tex, dx, dy, shieldSize, shieldSize, 1, 1, 1, 1)
		end
	end

	local tmgr = getTextManager()
	local fontRatio = dims.ratio
	local textX = shieldPadLeft + shieldSize + 15 * fontRatio

	local barH = 14 * fontRatio
	local barW = (dims.panelW - (shieldPadLeft + shieldSize + 15 * fontRatio) - 20 * fontRatio) * 0.8 + 30 * fontRatio
	local barX = textX + 10 * fontRatio
	local barY = self.height - 20 * fontRatio - barH - 20 * fontRatio - 10 * fontRatio

	if self._cvRank ~= rank or self._cvTotalXp ~= totalXp then
		self._cvRank = rank
		self._cvTotalXp = totalXp
		self._cvNeed = XPR_RankCurve.requiredXp(rank + 1)
		self._cvBase = XPR_RankCurve.cumulativeXpForRank(rank)
	end
	local xpNeededForNextRank = self._cvNeed
	local rankBaseXp = self._cvBase
	local xpIntoRank = totalXp - rankBaseXp
	if xpIntoRank < 0 then xpIntoRank = 0 end

	local fontXp = dims.font
	local xpY = barY - tmgr:getFontHeight(fontXp) - 15 * fontRatio
	local xpStr = tostring(xpIntoRank) .. " / " .. tostring(xpNeededForNextRank) .. " XP"
	self:drawText(xpStr, barX, xpY, COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 0.9, fontXp)

	local ratio = 0
	if xpNeededForNextRank > 0 then
		ratio = xpIntoRank / xpNeededForNextRank
		ratio = math.max(0, math.min(1, ratio))
	end

	self:drawRect(barX, barY, barW, barH, 0.3, 0.12, 0.12, 0.12)
	if ratio > 0 then
		self:drawRect(barX, barY, math.max(0, barW * ratio), barH,
			0.9, COL_BAR_FG.r, COL_BAR_FG.g, COL_BAR_FG.b)
	end
end

function XPR_RankHud.open()
	if XPR_RankHud.instance then return end

	local savedX, savedY = loadPosition()
	local scale = (ObNoxToast and ObNoxToast.getScale and ObNoxToast.getScale()) or 1.0
	local dims = computeHudDims(scale)
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local x = savedX or DEFAULT_X
	local y = savedY or DEFAULT_Y
	x = math.max(0, math.min(x, screenW - dims.panelW))
	y = math.max(0, math.min(y, screenH - dims.panelH))

	local panel = XPR_RankHud.Panel:new(x, y, scale)
	panel:initialise()
	panel:instantiate()
	panel:addToUIManager()
	panel:setVisible(false)
	XPR_RankHud.instance = panel
end

function XPR_RankHud.close()
	if XPR_RankHud.instance then
		XPR_RankHud.instance:removeFromUIManager()
		XPR_RankHud.instance = nil
	end
end

Events.OnCreatePlayer.Add(function(playerNum)
	if playerNum ~= 0 then return end
	XPR_RankHud.playerDead = false
	XPR_RankHud.open()
end)

Events.OnPlayerDeath.Add(function(player)
	if player ~= getSpecificPlayer(0) then return end
	if not XPR_ModOptions or not XPR_ModOptions.isHudAttachedToRadial() then
		XPR_RankHud.playerDead = true
		if XPR_RankHud.instance then XPR_RankHud.instance:setVisible(false) end
	end
	if XPR_UI_Leaderboard and XPR_UI_Leaderboard.close then
		XPR_UI_Leaderboard.close()
	end
end)

return XPR_RankHud
