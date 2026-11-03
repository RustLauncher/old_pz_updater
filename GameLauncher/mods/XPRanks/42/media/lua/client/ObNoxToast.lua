if ObNoxToast then return end

if isServer() and not isClient() then return end

require "ISUI/ISContextMenu"

ObNoxToast = {}

local function S(px)
	local font = UIFont.Small
	local baseline = 19
	local current = getTextManager():getFontHeight(font)
	return math.floor(px * current / baseline + 0.5)
end

local toast_bg = getTexture("media/textures/obnox_toast_bg.png")
local toast_frame_dcs = getTexture("media/textures/obnox_dcs_toast_frame.png")
local toast_glyphs = {
	debug = getTexture("media/textures/obnox_toast_glyph_debug.png"),
	complete = getTexture("media/textures/obnox_toast_glyph_complete.png"),
	new = getTexture("media/textures/obnox_toast_glyph_new.png"),
	reward = getTexture("media/textures/obnox_toast_glyph_reward.png"),
}

local texScaleTick = getTexture("media/textures/obnox_xpr_tick.png")
local SCALE_TICK_COLOR = { r = 0, g = 1, b = 0 }

local texShield = getTexture("media/textures/xpr_rank_shield.png")

local TOAST_FAMILY = {
	dcs = { frameTex = toast_frame_dcs, tint = { r = 1, g = 1, b = 1 }, glyphOffsetY = 0 },
	xpr = { frameTex = texShield, tint = { r = 0, g = 0, b = 0 }, glyphOffsetY = -20 },
}

local function toastFamily(sourceId)
	if sourceId == "XPRanks" then return "xpr" end
	return "dcs"
end

local numTextures = {}
for i = 0, 9 do
	numTextures[i] = getTexture("media/textures/xpr_num_" .. i .. ".png")
end
local RANK_ICON_BASE_SIZE = 96
local RANK_DIGIT_SPACING = 20
local RANK_DIGIT_SPACING_2 = 24
local function rankDigitNudge(i, numDigits)
	local spacing = (numDigits == 2) and RANK_DIGIT_SPACING_2 or RANK_DIGIT_SPACING
	return (i - (numDigits + 1) / 2) * spacing
end

local TOAST_LIFETIME = 80
local TOAST_FADE_IN = 20
local TOAST_FADE_OUT = 20

ObNoxToast.REFERENCE_FONT_HEIGHT = 33

local TOAST_FONT_NAMES = { [UIFont.Small] = "Small", [UIFont.Medium] = "Medium", [UIFont.Large] = "Large" }

ObNoxToast.SCALE_PRESETS = { 0.5, 1.0, 2.0 }
ObNoxToast.SCALE_FONT_MAP = {
	[0.5] = UIFont.Small,
	[1.0] = UIFont.Medium,
	[2.0] = UIFont.Large,
}

local function pickToastFont(scale)
	local font = ObNoxToast.SCALE_FONT_MAP[scale] or UIFont.Small
	local ratio = getTextManager():getFontHeight(font) / ObNoxToast.REFERENCE_FONT_HEIGHT
	return font, TOAST_FONT_NAMES[font], ratio
end

local function computeToastDims(scale)
	scale = scale or 1.0
	local font, fontName, ratio = pickToastFont(scale)
	local w = 550 * ratio
	local iconSize = 100 * ratio
	local iconX = 30 * ratio
	local iconPad = 12 * ratio
	return {
		w = w,
		h = 150 * ratio,
		iconSize = iconSize,
		iconX = iconX,
		iconPad = iconPad,
		textMax = w - 30 * ratio - iconSize - iconPad - 30 * ratio,
		font = font,
		fontName = fontName,
		ratio = ratio,
	}
end

local function wrapText(text, font, maxWidth)
	local result = {}
	local tmgr = getTextManager()

	for segment in string.gmatch(text, "[^\n]+") do
		local current = nil
		for word in string.gmatch(segment, "%S+") do
			local candidate = current and (current .. " " .. word) or word
			if tmgr:MeasureStringX(font, candidate) <= maxWidth then
				current = candidate
			else
				if current then
					result[#result + 1] = current
					current = nil
				end
				if tmgr:MeasureStringX(font, word) <= maxWidth then
					current = word
				else
					local chunk = ""
					for i = 1, #word do
						local ch = word:sub(i, i)
						if tmgr:MeasureStringX(font, chunk .. ch) <= maxWidth then
							chunk = chunk .. ch
						else
							if chunk ~= "" then result[#result + 1] = chunk end
							chunk = ch
						end
					end
					if chunk ~= "" then current = chunk end
				end
			end
		end
		if current then result[#result + 1] = current end
	end

	return #result > 0 and result or { text }
end

local TOAST_COLORS = {
	debug = { r = 1.0, g = 1.0, b = 1.0 },
	complete = { r = 1.0, g = 1.0, b = 1.0 },
	new = { r = 1.0, g = 1.0, b = 1.0 },
	reward = { r = 1.0, g = 1.0, b = 1.0 },
	rankup = { r = 1.0, g = 1.0, b = 1.0 },
	boxReward = { r = 1.0, g = 1.0, b = 1.0 },
}

local toastQueue = {}
local toastShowing = false

local hiddenSources = {}

function ObNoxToast.setSourceHidden(sourceId, hidden)
	if not sourceId then return end
	hiddenSources[sourceId] = hidden == true
end

function ObNoxToast.playSound(soundName, sourceId, volume)
	if not soundName then return end
	if sourceId and hiddenSources[sourceId] then return end
	if not getSoundManager then return end
	getSoundManager():PlaySound(soundName, false, volume or 0.7)
end

local POS_FILE = "ObNoxToastPos.txt"
local LEGACY_POS_FILE = "ON_ToastPos.txt"

local MIN_SCALE = 0.5
local MAX_SCALE = 2.0
local DEFAULT_SCALE = 1.0

local function clampScale(scale)
	scale = tonumber(scale)
	if not scale then return DEFAULT_SCALE end
	return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

local function loadPosAndScale()
	local reader = getFileReader(POS_FILE, true)
	if reader then
		local line = reader:readLine()
		reader:close()
		if line then
			local xs, ys, scale = string.match(line, "^([^,]+),([^,]+),([%d%.]+)$")
			if xs and ys and scale then
				return tonumber(xs), tonumber(ys), clampScale(scale)
			end
		end
	end

	local legacyReader = getFileReader(LEGACY_POS_FILE, true)
	if not legacyReader then return nil, nil, nil end
	local legacyLine = legacyReader:readLine()
	legacyReader:close()
	if not legacyLine then return nil, nil, nil end
	local x, y = string.match(legacyLine, "^(%-?%d+),(%-?%d+)$")
	if not x or not y then return nil, nil, nil end
	return tonumber(x), tonumber(y), DEFAULT_SCALE
end

local function savePosAndScale(x, y, scale)
	local writer = getFileWriter(POS_FILE, true, false)
	if not writer then return end
	writer:write(tostring(x) .. "," .. tostring(y) .. "," .. tostring(scale))
	writer:close()
end

local function getDefaultPosition(dims)
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local x = screenW - dims.w - S(20)
	local y = screenH - dims.h - S(400)
	return x, y
end

function ObNoxToast.getPosition()
	local savedX, savedY, savedScale = loadPosAndScale()
	local scale = clampScale(savedScale)
	local dims = computeToastDims(scale)

	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local defaultX, defaultY = getDefaultPosition(dims)
	local x = savedX or defaultX
	local y = savedY or defaultY
	x = math.max(0, math.min(x, screenW - dims.w))
	y = math.max(0, math.min(y, screenH - dims.h))
	return x, y, dims
end

function ObNoxToast.savePosition(x, y)
	local _, _, currentScale = loadPosAndScale()
	savePosAndScale(x, y, clampScale(currentScale))
end

function ObNoxToast.resetPosition()
	local _, _, currentScale = loadPosAndScale()
	savePosAndScale("default", "default", clampScale(currentScale))
end

function ObNoxToast.getScale()
	local _, _, savedScale = loadPosAndScale()
	return clampScale(savedScale)
end

function ObNoxToast.setScale(scale)
	scale = clampScale(scale)
	local x, y = loadPosAndScale()
	if not x then
		x, y = getDefaultPosition(computeToastDims(1.0))
	end
	savePosAndScale(x, y, scale)

	if XPR_RankHud and XPR_RankHud.instance and XPR_RankHud.instance.applyScale
			and XPR_RankHud.instance.scale ~= scale then
		XPR_RankHud.instance:applyScale(scale, false)
	end
end

ObNoxToast.clampScale = clampScale
ObNoxToast.MIN_SCALE = MIN_SCALE
ObNoxToast.MAX_SCALE = MAX_SCALE

function ObNoxToast.openScaleMenu(playerIndex, x, y, target, onSelect, currentScale, context)
	context = context or ISContextMenu.get(playerIndex, x, y)
	if not context then return nil end

	local scaleOption = context:addOption(getText("IGUI_OBNOX_ToastContext_Scale"), target, nil)
	scaleOption.tooltip = getText("IGUI_OBNOX_ToastContext_ScaleTooltip")
	local scaleMenu = ISContextMenu:getNew(context)
	context:addSubMenu(scaleOption, scaleMenu)

	currentScale = currentScale or ObNoxToast.getScale()
	for _, preset in ipairs(ObNoxToast.SCALE_PRESETS) do
		local label = string.format("%.2gx", preset)
		local option = scaleMenu:addOption(label, target, onSelect, preset)
		if texScaleTick and math.abs(preset - currentScale) < 0.001 then
			option.iconTexture = texScaleTick
			option.color = SCALE_TICK_COLOR
		end
	end

	return context
end

function ObNoxToast.openPositionMenu(playerIndex, x, y, target, onReset, context)
	context = context or ISContextMenu.get(playerIndex, x, y)
	if not context then return nil end

	local posOption = context:addOption(getText("IGUI_OBNOX_ToastContext_Position"), target, nil)
	posOption.tooltip = getText("IGUI_OBNOX_ToastContext_PositionTooltip")
	local posMenu = ISContextMenu:getNew(context)
	context:addSubMenu(posOption, posMenu)
	posMenu:addOption(getText("IGUI_OBNOX_ToastContext_ResetToDefault"), target, onReset)

	return context
end

local spawnToast

ObNoxToast.Panel = ISPanel:derive("ObNoxToast_Panel")

function ObNoxToast.Panel:new(x, y, message, toastType, font, rank, dims, sourceId)
	dims = dims or computeToastDims(1.0)
	local o = ISPanel.new(self, x, y, dims.w, dims.h)
	o.message = message or ""
	o.toastType = toastType or "debug"
	o.font = font or dims.font or UIFont.Medium
	o.rank = rank
	o.dims = dims
	o.sourceId = sourceId
	o.ticks = 0
	o.alpha = 0
	o.moveWithMouse = true
	return o
end

function ObNoxToast.Panel:initialise()
	ISPanel.initialise(self)
end

function ObNoxToast.Panel:onMouseDown(x, y)
	ISPanel.onMouseDown(self, x, y)
	self._dragging = true
end

function ObNoxToast.Panel:onMouseUp(x, y)
	ISPanel.onMouseUp(self, x, y)
	self._dragging = false
	ObNoxToast.savePosition(self:getX(), self:getY())
end

function ObNoxToast.Panel:onSelectScale(scale)
	ObNoxToast.setScale(scale)
end

function ObNoxToast.Panel:onResetPosition()
	ObNoxToast.resetPosition()
end

function ObNoxToast.Panel:onRightMouseUp(x, y)
	local context = ObNoxToast.openScaleMenu(0, getMouseX(), getMouseY(), self, self.onSelectScale)
	ObNoxToast.openPositionMenu(0, getMouseX(), getMouseY(), self, self.onResetPosition, context)
	self.scaleMenu = context
	return true
end

function ObNoxToast.Panel:update()
	ISPanel.update(self)
	if self._dragging then return end
	if self.scaleMenu and self.scaleMenu:isVisible() then return end
	self.ticks = self.ticks + 1

	if self.ticks <= TOAST_FADE_IN then
		local t = self.ticks / TOAST_FADE_IN
		self.alpha = t * t * t * (t * (t * 6 - 15) + 10)
	elseif self.ticks <= (TOAST_LIFETIME - TOAST_FADE_OUT) then
		self.alpha = 1.0
	elseif self.ticks <= TOAST_LIFETIME then
		local t = (TOAST_LIFETIME - self.ticks) / TOAST_FADE_OUT
		self.alpha = t * t * t * (t * (t * 6 - 15) + 10)
	else
		self:removeFromUIManager()
		toastShowing = false
		if #toastQueue > 0 then
			local nextToast = table.remove(toastQueue, 1)
			spawnToast(nextToast.message, nextToast.toastType, nextToast.font, nextToast.rank,
				nextToast.sourceId, nextToast.soundName)
		end
	end
end

function ObNoxToast.Panel:prerender()
	local col = TOAST_COLORS[self.toastType] or TOAST_COLORS.debug
	local a = self.alpha
	local dims = self.dims

	if toast_bg then
		self:drawTextureScaled(toast_bg, 0, 0, self.width, self.height, a)
	end

	if self.toastType == "rankup" then
		local iconY = (self.height - dims.iconSize) / 2 - 3 * dims.ratio

		if texShield then
			self:drawTextureScaled(texShield, dims.iconX, iconY, dims.iconSize, dims.iconSize, a)
		end

		local rank = self.rank
		if not rank then
			local state = XPR_ClientSync and XPR_ClientSync.getState(getSpecificPlayer(0))
			rank = (state and state.rank) or 1
		end
		local rankStr = tostring(rank)
		local numDigits = #rankStr
		local nudgeScale = dims.iconSize / RANK_ICON_BASE_SIZE
		for i = 1, numDigits do
			local digit = tonumber(string.sub(rankStr, i, i))
			local tex = digit and numTextures[digit]
			if tex then
				local nudge = rankDigitNudge(i, numDigits) * nudgeScale
				self:drawTextureScaled(tex, dims.iconX + nudge, iconY, dims.iconSize, dims.iconSize, a)
			end
		end
	else
		local family = TOAST_FAMILY[toastFamily(self.sourceId)]
		local glyphKey = (self.toastType == "boxReward") and "reward" or self.toastType
		local glyph = toast_glyphs[glyphKey]
		local iconY = (self.height - dims.iconSize) / 2 - 3 * dims.ratio
		if family.frameTex then
			self:drawTextureScaled(family.frameTex, dims.iconX, iconY, dims.iconSize, dims.iconSize, a)
		end
		if glyph then
			local glyphY = iconY + family.glyphOffsetY * dims.ratio
			self:drawTextureScaled(glyph, dims.iconX, glyphY, dims.iconSize, dims.iconSize, a,
				family.tint.r, family.tint.g, family.tint.b)
		end
	end

	local textX = dims.iconX + dims.iconSize + dims.iconPad
	local lines = wrapText(self.message, self.font, dims.textMax)
	if #lines > 4 then
		local truncated = {}
		for i = 1, 4 do
			truncated[i] = lines[i]
		end
		truncated[4] = truncated[4] .. "..."
		lines = truncated
	end
	local fontH = getTextManager():getFontHeight(self.font)
	local totalTextH = #lines * fontH
	local textY = (self.height - totalTextH) / 2

	for i, line in ipairs(lines) do
		self:drawText(line, textX, textY + (i - 1) * fontH,
			col.r, col.g, col.b, a, self.font)
	end
end

spawnToast = function(message, toastType, font, rank, sourceId, soundName)
	toastShowing = true
	local x, y, dims = ObNoxToast.getPosition()
	local panel = ObNoxToast.Panel:new(x, y, message, toastType, font, rank, dims, sourceId)
	panel:initialise()
	panel:instantiate()
	panel:addToUIManager()
	if soundName then
		ObNoxToast.playSound(soundName, sourceId)
	end
end

function ObNoxToast.show(message, toastType, font, sourceId, rank, soundName)
	if not message then return end

	if sourceId and hiddenSources[sourceId] then return end

	toastType = toastType or "debug"

	if toastShowing then
		toastQueue[#toastQueue + 1] = {
			message = message,
			toastType = toastType,
			font = font,
			rank = rank,
			sourceId = sourceId,
			soundName = soundName,
		}
	else
		spawnToast(message, toastType, font, rank, sourceId, soundName)
	end
end

return ObNoxToast
