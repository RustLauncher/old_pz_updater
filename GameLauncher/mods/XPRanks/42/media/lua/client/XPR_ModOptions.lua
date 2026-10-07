if isServer() and not isClient() then return end

XPR_ModOptions = XPR_ModOptions or {}

local OPT_FILE = "XPRanks/XPR_ModOptions.txt"
local TICKER_ALIGNMENTS = { "right", "centre", "left" }

local function normaliseTickerAlignment(alignment)
	if alignment == "centre" or alignment == "left" then return alignment end
	return "right"
end

local function normaliseIconScale(scale)
	scale = tonumber(scale) or 1.0
	if math.abs(scale - 0.5) < 0.001 then return 0.5 end
	if math.abs(scale - 1.0) < 0.001 then return 1.0 end
	if math.abs(scale - 2.0) < 0.001 then return 2.0 end
	return 1.0
end

local function loadOptions()
	local saved = {}
	local reader = getFileReader(OPT_FILE, false)
	if not reader then
		local writer = getFileWriter(OPT_FILE, true, false)
		if writer then
			writer:write("attachHudToRadial=false\n")
			writer:write("hideToasts=false\n")
			writer:write("hideTickerFeed=false\n")
			writer:write("enableSounds=true\n")
			writer:write("tickerFeedAlignment=right\n")
			writer:write("useDraggableIcon=false\n")
			writer:write("iconX=0\n")
			writer:write("iconY=0\n")
			writer:write("iconScale=1.0\n")
			writer:close()
		end
		return saved
	end
	local line = reader:readLine()
	while line do
		local key, value = string.match(line, "^([%a%d_]+)=(.+)")
		if key then
			if value == "true" or value == "false" then
				saved[key] = value == "true"
			else
				saved[key] = tonumber(value) or value
			end
		end
		line = reader:readLine()
	end
	reader:close()
	return saved
end

local function saveOptions()
	local writer = getFileWriter(OPT_FILE, true, false)
	if not writer then return end
	writer:write("attachHudToRadial=" .. tostring(XPR_ModOptions.attachHudToRadial == true) .. "\n")
	writer:write("hideToasts=" .. tostring(XPR_ModOptions.hideToasts == true) .. "\n")
	writer:write("hideTickerFeed=" .. tostring(XPR_ModOptions.hideTickerFeed == true) .. "\n")
	writer:write("enableSounds=" .. tostring(XPR_ModOptions.enableSounds ~= false) .. "\n")
	writer:write("tickerFeedAlignment=" .. normaliseTickerAlignment(XPR_ModOptions.tickerFeedAlignment) .. "\n")
	writer:write("useDraggableIcon=" .. tostring(XPR_ModOptions.useDraggableIcon == true) .. "\n")
	writer:write("iconX=" .. tostring(math.floor(XPR_ModOptions.iconX or 0)) .. "\n")
	writer:write("iconY=" .. tostring(math.floor(XPR_ModOptions.iconY or 0)) .. "\n")
	writer:write("iconScale=" .. tostring(normaliseIconScale(XPR_ModOptions.iconScale)) .. "\n")
	writer:close()
end

local saved = loadOptions()

if XPR_ModOptions.attachHudToRadial == nil then
	XPR_ModOptions.attachHudToRadial = (saved.attachHudToRadial == true)
end

function XPR_ModOptions.isHudAttachedToRadial()
	return XPR_ModOptions.attachHudToRadial == true
end

if XPR_ModOptions.hideTickerFeed == nil then
	XPR_ModOptions.hideTickerFeed = (saved.hideTickerFeed == true)
end

function XPR_ModOptions.isTickerFeedHidden()
	return XPR_ModOptions.hideTickerFeed == true
end

if XPR_ModOptions.enableSounds == nil then
	XPR_ModOptions.enableSounds = saved.enableSounds ~= false
end

function XPR_ModOptions.areSoundsEnabled()
	return XPR_ModOptions.enableSounds ~= false
end

if XPR_ModOptions.tickerFeedAlignment == nil then
	XPR_ModOptions.tickerFeedAlignment = normaliseTickerAlignment(saved.tickerFeedAlignment)
end

function XPR_ModOptions.getTickerFeedAlignment()
	return normaliseTickerAlignment(XPR_ModOptions.tickerFeedAlignment)
end

if XPR_ModOptions.hideToasts == nil then
	XPR_ModOptions.hideToasts = (saved.hideToasts == true)
end

if XPR_ModOptions.useDraggableIcon == nil then
	XPR_ModOptions.useDraggableIcon = saved.useDraggableIcon == true
end

if XPR_ModOptions.iconX == nil then XPR_ModOptions.iconX = saved.iconX end
if XPR_ModOptions.iconY == nil then XPR_ModOptions.iconY = saved.iconY end
if XPR_ModOptions.iconScale == nil then
	XPR_ModOptions.iconScale = normaliseIconScale(saved.iconScale)
end

function XPR_ModOptions.isDraggableIconEnabled()
	return XPR_ModOptions.useDraggableIcon == true
end

function XPR_ModOptions.saveIconPresentation(x, y, scale)
	XPR_ModOptions.iconX = x
	XPR_ModOptions.iconY = y
	XPR_ModOptions.iconScale = normaliseIconScale(scale)
	saveOptions()
end

if ObNoxToast and ObNoxToast.setSourceHidden then
	ObNoxToast.setSourceHidden("XPRanks", XPR_ModOptions.hideToasts)
end

local function initModOptions()
	local options = PZAPI.ModOptions:create("XPRanks",
		getText("IGUI_XPR_ModOptions_Title") or "XP Ranks")

	local attachOption = options:addTickBox("attachHudToRadial",
		getText("IGUI_XPR_ModOptions_AttachHudName") or "Attach XP HUD to Radial Menu",
		XPR_ModOptions.attachHudToRadial,
		getText("IGUI_XPR_ModOptions_AttachHudDesc")
			or "When enabled, the XP Ranks HUD only shows while the radial menu is open. When disabled, it's always visible.")

	local hideToastsOption = options:addTickBox("hideToasts",
		getText("IGUI_XPR_ModOptions_HideToastsName") or "Hide Notifications",
		XPR_ModOptions.hideToasts,
		getText("IGUI_XPR_ModOptions_HideToastsDesc")
			or "Suppress XP Ranks' own toast notifications (Rank Up). Does not affect notifications from other mods.")

	local hideTickerOption = options:addTickBox("hideTickerFeed",
		getText("IGUI_XPR_ModOptions_HideTickerName") or "Hide XP Ticker Feed",
		XPR_ModOptions.hideTickerFeed,
		getText("IGUI_XPR_ModOptions_HideTickerDesc")
			or "Suppress the right-side XP ticker feed. Does not affect the Rank Up notification.")

	local enableSoundsOption = options:addTickBox("enableSounds",
		getText("IGUI_XPR_ModOptions_EnableSoundsName") or "Enable Sounds",
		XPR_ModOptions.enableSounds,
		getText("IGUI_XPR_ModOptions_EnableSoundsDesc")
			or "Play XP Ranks notification and interface sounds.")

	local tickerAlignmentOption = options:addComboBox("tickerFeedAlignment",
		getText("IGUI_XPR_ModOptions_TickerAlignmentName") or "XP Ticker Feed Alignment",
		getText("IGUI_XPR_ModOptions_TickerAlignmentDesc")
			or "Changes the horizontal alignment of XP Ticker Feed messages.")
	local selectedAlignment = XPR_ModOptions.getTickerFeedAlignment()
	tickerAlignmentOption:addItem(getText("IGUI_XPR_ModOptions_AlignmentRight") or "Right",
		selectedAlignment == "right")
	tickerAlignmentOption:addItem(getText("IGUI_XPR_ModOptions_AlignmentCentre") or "Centre",
		selectedAlignment == "centre")
	tickerAlignmentOption:addItem(getText("IGUI_XPR_ModOptions_AlignmentLeft") or "Left",
		selectedAlignment == "left")

	options.apply = function(self)
		XPR_ModOptions.attachHudToRadial = attachOption:getValue() == true
		XPR_ModOptions.hideTickerFeed = hideTickerOption:getValue() == true
		XPR_ModOptions.enableSounds = enableSoundsOption:getValue() == true
		XPR_ModOptions.tickerFeedAlignment = TICKER_ALIGNMENTS[tickerAlignmentOption:getValue()] or "right"
		XPR_ModOptions.hideToasts = hideToastsOption:getValue() == true
		saveOptions()
		if ObNoxToast and ObNoxToast.setSourceHidden then
			ObNoxToast.setSourceHidden("XPRanks", XPR_ModOptions.hideToasts)
		end
	end
end

Events.OnCreateUI.Add(initModOptions)

return XPR_ModOptions
