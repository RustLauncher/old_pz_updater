if isServer() and not isClient() then return end

XPR_UI_Scale = {}

local tmgr = getTextManager()
local FONT_SM = UIFont.Small
local FONT_MD = UIFont.Medium
local fontHgt = tmgr:getFontHeight(FONT_SM)
local fontHgtMd = tmgr:getFontHeight(FONT_MD)

local BASE_SM = 19
local SCALE = fontHgt / BASE_SM

XPR_UI_Scale.FONT_SM = FONT_SM
XPR_UI_Scale.FONT_MD = FONT_MD
XPR_UI_Scale.fontHgt = fontHgt
XPR_UI_Scale.fontHgtMd = fontHgtMd
XPR_UI_Scale.SCALE = SCALE

function XPR_UI_Scale.s(px)
	return math.floor(px * SCALE + 0.5)
end

function XPR_UI_Scale.measureText(font, text)
	return getTextManager():MeasureStringX(font, text or "")
end

function XPR_UI_Scale.btnWidth(font, text, floorW, padX)
	return math.max(floorW or 0, XPR_UI_Scale.measureText(font, text) + (padX or 12))
end

function XPR_UI_Scale.longestText(font, texts)
	local max = 0
	for _, t in ipairs(texts or {}) do
		local w = XPR_UI_Scale.measureText(font, t)
		if w > max then max = w end
	end
	return max
end

function XPR_UI_Scale.wrapLines(font, text, maxWidthPx)
	text = text or ""
	local wrapped = tmgr:WrapText(font, text, maxWidthPx, 99, "")
	local lines = {}
	for line in string.gmatch(wrapped or "", "[^\n]+") do
		lines[#lines + 1] = line
	end
	if #lines == 0 then lines = { text } end
	return lines
end

function XPR_UI_Scale.wrapModalText(font, text, maxWidthPx)
	text = text or ""
	local outLines = {}
	for segment in (text .. "\n"):gmatch("([^\n]*)\n") do
		if segment == "" then
			outLines[#outLines + 1] = ""
		else
			for _, line in ipairs(XPR_UI_Scale.wrapLines(font, segment, maxWidthPx)) do
				outLines[#outLines + 1] = line
			end
		end
	end
	return table.concat(outLines, "\n")
end

return XPR_UI_Scale
