if isServer() and not isClient() then return end

require "ISUI/ISPanel"
require "ObNoxToast"

XPR_TickerFeed = {}
XPR_TickerFeed.instance = nil

local POS_FILE = "XPRanks/XPR_TickerPos.txt"
local DEFAULT_SCALE = 2.0

local function loadPosAndScale()
	local reader = getFileReader(POS_FILE, false)
	if not reader then return nil, nil, nil end
	local line = reader:readLine()
	reader:close()
	if not line then return nil, nil, nil end
	local xs, ys, scale = string.match(line, "^([^,]+),([^,]+),([%d%.]+)$")
	if not xs or not ys or not scale then return nil, nil, nil end
	return tonumber(xs), tonumber(ys), ObNoxToast.clampScale(scale)
end

local function savePosAndScale(x, y, scale)
	local writer = getFileWriter(POS_FILE, true, false)
	if not writer then return end
	writer:write(tostring(x) .. "," .. tostring(y) .. "," .. tostring(scale))
	writer:close()
end

function XPR_TickerFeed.getScale()
	local _, _, savedScale = loadPosAndScale()
	return savedScale or DEFAULT_SCALE
end

function XPR_TickerFeed.setScale(scale)
	scale = ObNoxToast.clampScale(scale)
	local x, y = loadPosAndScale()
	savePosAndScale(x, y, scale)
end

local function savePosition(x, y)
	local _, _, currentScale = loadPosAndScale()
	savePosAndScale(x, y, currentScale or DEFAULT_SCALE)
end

function XPR_TickerFeed.resetPosition()
	local _, _, currentScale = loadPosAndScale()
	savePosAndScale("default", "default", currentScale or DEFAULT_SCALE)
end

local function computeTickerDims(scale)
	scale = scale or DEFAULT_SCALE
	local font = ObNoxToast.SCALE_FONT_MAP[scale] or UIFont.Small
	local ratio = getTextManager():getFontHeight(font) / ObNoxToast.REFERENCE_FONT_HEIGHT
	return {
		font = font,
		ratio = ratio,
		w = 260 * ratio,
		h = getTextManager():getFontHeight(font) + 16 * ratio,
		padRight = 45 * ratio,
		iconGap = 4 * ratio,
		risePx = 30 * ratio,
		shadowOffset = math.max(1, math.floor(1 * ratio)),
	}
end

local TICKER_LIFETIME = 45
local TICKER_FADE_OUT = 15
local TICKER_RISE_TICKS = 10

local xpIcon = getTexture("media/textures/obnox_xpr_feed_xp.png")

local DCS_TOAST_TOP_BASELINE = 550
local TICKER_GAP_ABOVE_TOAST = 50

local COL_TEXT = { r=1, g=1, b=1 }
local COL_SHADOW = { r=0, g=0, b=0 }

local spawnTicker

local tickerQueue = {}
local tickerShowing = false

local function findLastPlainText(text, needle)
	if not text or not needle or needle == "" then return nil end
	local lastStart
	local searchStart = 1
	while true do
		local startPos = string.find(text, needle, searchStart, true)
		if not startPos then break end
		lastStart = startPos
		searchStart = startPos + #needle
	end
	return lastStart
end

local function stripTickerSuffixAfterAmount(message, amountText)
	local amountStart = findLastPlainText(message, amountText)
	if not amountStart then return message end
	return string.sub(message, 1, amountStart + #amountText - 1)
end

local function normaliseTickerPayload(message, showXpIcon)
	if type(message) == "table" then
		return {
			message = tostring(message.message or ""),
			showXpIcon = message.showXpIcon == true,
			stripXpSuffix = message.stripXpSuffix == true,
			xpAmountText = message.xpAmountText and tostring(message.xpAmountText) or nil,
		}
	end
	return {
		message = tostring(message or ""),
		showXpIcon = showXpIcon == true,
		stripXpSuffix = false,
		xpAmountText = nil,
	}
end

XPR_TickerFeed.Panel = ISPanel:derive("XPR_TickerFeed_Panel")

function XPR_TickerFeed.Panel:new(x, y, payload, dims)
	dims = dims or computeTickerDims(DEFAULT_SCALE)
	local o = ISPanel.new(self, x, y, dims.w, dims.h)
	payload = payload or {}
	local message = payload.message or ""

	if payload.stripXpSuffix == true and payload.xpAmountText then
		o.message = stripTickerSuffixAfterAmount(message, payload.xpAmountText)
	else
		o.message = message
	end
	o.showXpIcon = payload.showXpIcon == true

	o.dims = dims
	o.ticks = 0
	o.alpha = 0
	o.baseY = y
	o.moveWithMouse = true
	return o
end

function XPR_TickerFeed.Panel:initialise()
	ISPanel.initialise(self)
end

function XPR_TickerFeed.Panel:onMouseDown(x, y)
	ISPanel.onMouseDown(self, x, y)
	self._dragging = true
end

function XPR_TickerFeed.Panel:onMouseUp(x, y)
	ISPanel.onMouseUp(self, x, y)
	self._dragging = false
	self.baseY = self:getY()
	savePosition(self:getX(), self:getY())
end

function XPR_TickerFeed.Panel:onSelectScale(scale)
	XPR_TickerFeed.setScale(scale)
end

function XPR_TickerFeed.Panel:onResetPosition()
	XPR_TickerFeed.resetPosition()
end

function XPR_TickerFeed.Panel:onRightMouseUp(x, y)
	local context = ObNoxToast.openScaleMenu(0, getMouseX(), getMouseY(), self,
		self.onSelectScale, XPR_TickerFeed.getScale())
	ObNoxToast.openPositionMenu(0, getMouseX(), getMouseY(), self, self.onResetPosition, context)
	self.scaleMenu = context
	return true
end

function XPR_TickerFeed.Panel:update()
	ISPanel.update(self)
	if self._dragging then return end
	if self.scaleMenu and self.scaleMenu:isVisible() then return end

	self.ticks = self.ticks + 1

	if self.ticks <= TICKER_RISE_TICKS then
		local t = self.ticks / TICKER_RISE_TICKS
		local eased = t * t * t * (t * (t * 6 - 15) + 10)
		self.alpha = eased
		self:setY(self.baseY + (1 - eased) * self.dims.risePx)
	elseif self.ticks <= (TICKER_LIFETIME - TICKER_FADE_OUT) then
		self.alpha = 1.0
		self:setY(self.baseY)
	elseif self.ticks <= TICKER_LIFETIME then
		local t = (TICKER_LIFETIME - self.ticks) / TICKER_FADE_OUT
		self.alpha = t * t * t * (t * (t * 6 - 15) + 10)
		self:setY(self.baseY)
	else
		self:removeFromUIManager()
		tickerShowing = false
		if #tickerQueue > 0 then
			local next = table.remove(tickerQueue, 1)
			spawnTicker(next)
		end
	end
end

function XPR_TickerFeed.Panel:prerender()
	if self.alpha <= 0 then return end

	local a = self.alpha
	local font = self.dims.font
	local fontH = getTextManager():getFontHeight(font)
	local textY = (self.height - fontH) / 2

	local textW = getTextManager():MeasureStringX(font, self.message)
	local iconSize = self.showXpIcon and (fontH * 0.7) or 0
	local iconGap = self.showXpIcon and self.dims.iconGap or 0
	local totalW = textW + iconGap + iconSize
	local alignment = "right"
	if XPR_ModOptions and XPR_ModOptions.getTickerFeedAlignment then
		alignment = XPR_ModOptions.getTickerFeedAlignment()
	end
	local textX
	if alignment == "left" then
		textX = 10 * self.dims.ratio
	elseif alignment == "centre" then
		textX = (self.width - totalW) / 2
	else
		textX = self.width - totalW - (10 * self.dims.ratio)
	end

	self:drawText(self.message, textX - self.dims.shadowOffset, textY + self.dims.shadowOffset,
		COL_SHADOW.r, COL_SHADOW.g, COL_SHADOW.b, a, font)
	self:drawText(self.message, textX, textY,
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a, font)

	if self.showXpIcon then
		local iconX = textX + textW + iconGap + (2 * self.dims.ratio)
		local iconY = (self.height - iconSize) / 2 + iconSize * 0.14 - 1
		self:drawTextureScaled(xpIcon, iconX, iconY, iconSize, iconSize, a, 1, 1, 1)
	end
end

local function getPosition()
	local savedX, savedY, savedScale = loadPosAndScale()
	local scale = savedScale or DEFAULT_SCALE
	local dims = computeTickerDims(scale)

	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local defaultX = screenW - dims.w - dims.padRight
	local defaultY = screenH - DCS_TOAST_TOP_BASELINE - TICKER_GAP_ABOVE_TOAST - dims.h

	local x = savedX or defaultX
	local y = savedY or defaultY
	x = math.max(0, math.min(x, screenW - dims.w))
	y = math.max(0, math.min(y, screenH - dims.h))
	return x, y, dims
end

spawnTicker = function(message)
	tickerShowing = true
	if not XPR_ModOptions or not XPR_ModOptions.areSoundsEnabled
			or XPR_ModOptions.areSoundsEnabled() then
		getSoundManager():PlaySound("XPR_ticker", false, 0.7)
	end
	local x, y, dims = getPosition()
	local panel = XPR_TickerFeed.Panel:new(x, y, message, dims)
	panel:initialise()
	panel:instantiate()
	panel:addToUIManager()
	XPR_TickerFeed.instance = panel
end

function XPR_TickerFeed.show(message, showXpIcon)
	if XPR_ModOptions and XPR_ModOptions.isTickerFeedHidden and XPR_ModOptions.isTickerFeedHidden() then
		return
	end

	local payload = normaliseTickerPayload(message, showXpIcon)
	if tickerShowing then
		tickerQueue[#tickerQueue + 1] = payload
	else
		spawnTicker(payload)
	end
end

function XPR_TickerFeed.addXpGain(category, amount, labelOverride)
	if not category or not amount or amount <= 0 then return end
	local label = labelOverride
		or (XPR_Categories and XPR_Categories.getTickerLabel
			and XPR_Categories.getTickerLabel(category))
		or category
	local line = getText("IGUI_XPR_Ticker_XpLine", label, amount)
	if not line or line == "" or line == "IGUI_XPR_Ticker_XpLine" then
		line = label .. " +" .. amount .. " XP"
	end
	XPR_TickerFeed.show({
		message = line,
		showXpIcon = true,
		stripXpSuffix = true,
		xpAmountText = tostring(amount),
	})
end

return XPR_TickerFeed
