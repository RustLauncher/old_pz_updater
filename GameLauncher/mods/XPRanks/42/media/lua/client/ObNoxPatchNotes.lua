if ObNoxPatchNotes then return end

if isServer() and not isClient() then return end

require "ISUI/ISPanelJoypad"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"

ObNoxPatchNotes = {}

local REFERENCE_PANEL_W = 1920 * 0.30
local PANEL_W_RATIO = 0.30
local PANEL_H_RATIO = 400 / 1080
local EDGE_PAD_PX = 38
local PANEL_W = 0
local PANEL_H = 0
local EDGE_PAD_X = EDGE_PAD_PX
local EDGE_PAD_Y = EDGE_PAD_PX

local function S(px)
	return math.floor(px * PANEL_W / REFERENCE_PANEL_W + 0.5)
end

local FONT = UIFont.Small
local FONT_LARGE = UIFont.Large

local ARROW_LEFT_PATH = "media/textures/obnox_patchnotes_scroll_left.png"
local ARROW_RIGHT_PATH = "media/textures/obnox_patchnotes_scroll_right.png"
local STEAM_TEXTURE_PATH = "media/textures/obnox_patchnotes_steam.png"
local AUTHOR_LOGO_PATH = "media/textures/obnox_patchnotes_logo.png"
local BUG_TEXTURE_PATH = "media/textures/obnox_patchnotes_bug.png"
local DISCORD_TEXTURE_PATH = "media/textures/obnox_patchnotes_discord.png"
local DOCS_TEXTURE_PATH = "media/textures/obnox_patchnotes_docs.png"
local KOFI_TEXTURE_PATH = "media/textures/obnox_patchnotes_kofi.png"
local LIKE_TEXTURE_PATH = "media/textures/obnox_patchnotes_like.png"
local OPEN_TEXTURE_PATH = "media/textures/obnox_patchnotes_open.png"
local OPT_IN_TEXTURE_PATH = "media/textures/obnox_patchnotes_opt_in.png"
local OPT_OUT_TEXTURE_PATH = "media/textures/obnox_patchnotes_opt_out.png"
local OPT_UPDATE_TEXTURE_PATH = "media/textures/obnox_patchnotes_opt_update.png"
local CLOSED_TEXTURE_PATH = "media/textures/obnox_patchnotes_closed.png"
local ALERT_TEXTURE_PATH = "media/textures/obnox_patchnotes_alert.png"
local ARROW_TEXTURE_SCALE = 0.6
local ARROW_HIT_SCALE = 0.6

local PAD = 0
local TEXT_PAD = 0
local SCROLL_W = 0
local LINE_H = 0
local ARROW_W = 0
local ROW_H = 0
local LINK_ICON_SIZE = 20
local LINK_BUTTON_WIDTH = 24
local AUTO_ICON_SIZE = 32

local function refreshLayoutMetrics(layoutW, layoutH, physicalW, physicalH)
	PANEL_W = math.floor(layoutW * PANEL_W_RATIO + 0.5)
	PANEL_H = math.floor(layoutH * PANEL_H_RATIO + 0.5)
	EDGE_PAD_X = EDGE_PAD_PX * layoutW / physicalW
	EDGE_PAD_Y = EDGE_PAD_PX * layoutH / physicalH
	PAD = PANEL_W * 0.05
	TEXT_PAD = S(10)
	SCROLL_W = S(30)
	LINE_H = getTextManager():getFontHeight(FONT) + S(2)
	ARROW_W = S(24)
	ROW_H = S(25)
	LINK_ICON_SIZE = 20 * layoutW / physicalW
	LINK_BUTTON_WIDTH = 24 * layoutW / physicalW
	AUTO_ICON_SIZE = 32 * layoutW / physicalW
end

refreshLayoutMetrics(
	getCore():getScreenWidth(),
	getCore():getScreenHeight(),
	getCore():getScreenWidth(),
	getCore():getScreenHeight()
)

local COL_ACCENT = { r = 52 / 255, g = 194 / 255, b = 0 / 255, a = 1 }
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90, a = 1 }
local COL_DIM = { r = 0.60, g = 0.60, b = 0.60, a = 1 }

local DEBUG = false
local function onpDprint(...)
	if DEBUG then print("[ObNoxPatchNotes]", ...) end
end

local SEEN_FILE = "ObNoxPatchNotes.txt"
local AUTO_SHOW_KEY = "AUTO_SHOW"
local LEGACY_OPT_OUT_KEY = "OPT_OUT"
local AUTO_SHOW_ON = "on"
local AUTO_SHOW_OFF = "off"
local AUTO_SHOW_AUTO = "auto"
local STEAM_CTA_TEXT = getText("IGUI_OBNOXPN_SteamCTA")
local STEAM_FALLBACK_TEXT = getText("IGUI_OBNOXPN_SteamFallback")
local CLOSE_PANEL_TOOLTIP = getText("IGUI_OBNOXPN_ClosePanel")
local OPEN_PANEL_TOOLTIP = getText("IGUI_OBNOXPN_OpenPanel")
local PATCH_NOTES_TITLE = getText("IGUI_OBNOXPN_Title")
local SHORT_LABEL_TEXT = getText("IGUI_OBNOXPN_ShortLabel")
local NOT_PUBLISHED_TEXT = getText("IGUI_OBNOXPN_NotPublished")
local UNAVAILABLE_TEXT = getText("IGUI_OBNOXPN_Unavailable")
local VISIBILITY_HEADING = getText("IGUI_OBNOXPN_VisibilityHeading")
local VISIBILITY_AUTO_TEXT = VISIBILITY_HEADING .. "\n" .. getText("IGUI_OBNOXPN_VisibilityAuto")
local VISIBILITY_ON_TEXT = VISIBILITY_HEADING .. "\n" .. getText("IGUI_OBNOXPN_VisibilityOn")
local VISIBILITY_OFF_TEXT = VISIBILITY_HEADING .. "\n" .. getText("IGUI_OBNOXPN_VisibilityOff")
local OPEN_LINK_LABEL = getText("IGUI_OBNOXPN_OpenLink")
local seenData = {}

local function loadSeenData()
	local data = {}
	local reader = getFileReader(SEEN_FILE, false)
	if not reader then return data end
	local line = reader:readLine()
	while line do
		local key, value = string.match(line, "^(%S+)%s*=%s*(%S+)$")
		if key and value then data[key] = value end
		line = reader:readLine()
	end
	reader:close()
	return data
end

local function saveSeenData(data)
	local writer = getFileWriter(SEEN_FILE, true, false)
	if not writer then return false end
	for key, value in pairs(data) do
		writer:writeln(key .. " = " .. value)
	end
	writer:close()
	return true
end

local function refreshSeenData()
	seenData = loadSeenData()
end

refreshSeenData()

function ObNoxPatchNotes.getAutoShowMode()
	local mode = seenData[AUTO_SHOW_KEY]
	if mode == AUTO_SHOW_ON or mode == AUTO_SHOW_OFF or mode == AUTO_SHOW_AUTO then
		return mode
	end
	local migratedMode = nil
	if mode == "in" then migratedMode = AUTO_SHOW_ON end
	if mode == "out" then migratedMode = AUTO_SHOW_OFF end
	if mode == "update" then migratedMode = AUTO_SHOW_AUTO end
	if migratedMode then
		ObNoxPatchNotes.setAutoShowMode(migratedMode)
		return migratedMode
	end
	if seenData[LEGACY_OPT_OUT_KEY] == "true" then
		ObNoxPatchNotes.setAutoShowMode(AUTO_SHOW_OFF)
		return AUTO_SHOW_OFF
	end
	return AUTO_SHOW_AUTO
end

function ObNoxPatchNotes.setAutoShowMode(mode)
	if mode ~= AUTO_SHOW_ON and mode ~= AUTO_SHOW_OFF and mode ~= AUTO_SHOW_AUTO then return end
	local data = loadSeenData()
	data[AUTO_SHOW_KEY] = mode
	data[LEGACY_OPT_OUT_KEY] = nil
	if saveSeenData(data) then seenData = data end
end

local function hasAutomaticDisplayAccess(player)
	if not isClient() then return true end
	if isCoopHost() then return true end
	if not player or not player.getRole then return false end
	local role = player:getRole()
	if role and role.hasAdminTool then return role:hasAdminTool() end
	return false
end

function ObNoxPatchNotes.canAdjustAutoShow()
	local screen = MainScreen and MainScreen.instance
	if not screen then return false end
	if screen.inGame then
		return hasAutomaticDisplayAccess(getSpecificPlayer(0))
	end
	for _, entry in ipairs(ObNoxPatchNotes.entries) do
		if entry.mainMenuOnly then return true end
	end
	return false
end

local function isEntrySeen(entry)
	if not entry or entry.isAuthor then return true end
	local recorded = seenData[entry.prefix]
	if not recorded then return true end
	return recorded == tostring(entry.currentVersion)
end

local function markEntrySeen(entry)
	if not entry or entry.isAuthor or isEntrySeen(entry) then return end
	local data = loadSeenData()
	data[entry.prefix] = tostring(entry.currentVersion)
	if saveSeenData(data) then seenData = data end
end

function ObNoxPatchNotes.hasUnseen()
	for _, entry in ipairs(ObNoxPatchNotes.entries) do
		if not isEntrySeen(entry) then return true end
	end
	return false
end

local function getFirstUnseenIndex(wantMainMenuOnly)
	for index, entry in ipairs(ObNoxPatchNotes.entries) do
		if not isEntrySeen(entry) and (entry.mainMenuOnly == true) == (wantMainMenuOnly == true) then
			return index
		end
	end
	return nil
end

local function prioritiseUnseenEntries()
	local unseen = {}
	local seen = {}
	local author = {}
	for _, entry in ipairs(ObNoxPatchNotes.entries) do
		if entry.isAuthor then
			author[#author + 1] = entry
		elseif isEntrySeen(entry) then
			seen[#seen + 1] = entry
		else
			unseen[#unseen + 1] = entry
		end
	end

	local index = 1
	for _, entry in ipairs(unseen) do
		ObNoxPatchNotes.entries[index] = entry
		index = index + 1
	end
	for _, entry in ipairs(seen) do
		ObNoxPatchNotes.entries[index] = entry
		index = index + 1
	end
	for _, entry in ipairs(author) do
		ObNoxPatchNotes.entries[index] = entry
		index = index + 1
	end
	return #unseen
end

ObNoxPatchNotes.entries = {}
local entryByPrefix = {}
local AUTHOR_PREFIX = "__OBNOX_AUTHOR__"
local authorEntry = nil

local function ensureAuthorEntry()
	if authorEntry then return end
	authorEntry = {
		prefix = AUTHOR_PREFIX,
		modName = "ObnoxiouslyNoxious",
		currentVersion = "COGITO ERGO FOETEO",
		history = {},
		links = {
			{ header = getText("IGUI_OBNOXPN_AuthorBugHeader") },
			{ line = getText("IGUI_OBNOXPN_AuthorBugLine") },
			{ openUrl = "https://obnox.dev/#bug-reports", iconPath = BUG_TEXTURE_PATH,
				tooltipTitle = getText("IGUI_OBNOXPN_AuthorBugTooltip") },
			{ separator = true },
			{ header = getText("IGUI_OBNOXPN_AuthorDiscordHeader") },
			{ line = getText("IGUI_OBNOXPN_AuthorDiscordLine") },
			{ openUrl = "https://obnox.dev/discord", iconPath = DISCORD_TEXTURE_PATH,
				tooltipTitle = getText("IGUI_OBNOXPN_AuthorDiscordTooltip") },
			{ separator = true },
			{ header = getText("IGUI_OBNOXPN_AuthorModsHeader") },
			{ line = getText("IGUI_OBNOXPN_AuthorModsLine") },
			{ openUrl = "https://steamcommunity.com/id/ObnoxiouslyNoxious/myworkshopfiles/?p=1&numperpage=30",
				iconPath = STEAM_TEXTURE_PATH, tooltipTitle = getText("IGUI_OBNOXPN_AuthorModsTooltip") },
			{ separator = true },
			{ header = getText("IGUI_OBNOXPN_AuthorDocsHeader") },
			{ line = getText("IGUI_OBNOXPN_AuthorDocsLine") },
			{ openUrl = "https://obnox.dev/docs", iconPath = DOCS_TEXTURE_PATH,
				tooltipTitle = getText("IGUI_OBNOXPN_AuthorDocsTooltip") },
			{ separator = true },
			{ header = getText("IGUI_OBNOXPN_AuthorSupportHeader") },
			{ line = getText("IGUI_OBNOXPN_AuthorSupportLine") },
			{ openUrl = "https://obnox.dev/kofi", iconPath = KOFI_TEXTURE_PATH,
				tooltipTitle = getText("IGUI_OBNOXPN_AuthorSupportTooltip") },
		},
		modID = "",
		workshopID = "",
		iconPath = AUTHOR_LOGO_PATH,
		isAuthor = true,
	}
	entryByPrefix[AUTHOR_PREFIX] = authorEntry
	table.insert(ObNoxPatchNotes.entries, authorEntry)
end

function ObNoxPatchNotes.register(prefix, modName, currentVersion, history, links, modID, mainMenuOnly, explicitWorkshopID)
	if not prefix or entryByPrefix[prefix] then return end
	local iconPath = nil
	local workshopID = ""
	if modID and getModInfoByID then
		local modInfo = getModInfoByID(modID)
		if modInfo then
			local resolvedIcon = modInfo:getIcon()
			if resolvedIcon and resolvedIcon ~= "" then iconPath = resolvedIcon end
			local resolvedWorkshopID = modInfo:getWorkshopID()
			if resolvedWorkshopID and resolvedWorkshopID ~= "" then workshopID = tostring(resolvedWorkshopID) end
		end
	end
	if workshopID == "" and explicitWorkshopID then
		workshopID = tostring(explicitWorkshopID)
	end
	local entry = {
		prefix = prefix,
		modName = modName or prefix,
		currentVersion = currentVersion or "",
		history = history or {},
		links = links or {},
		modID = modID or "",
		workshopID = workshopID,
		iconPath = iconPath,
		mainMenuOnly = mainMenuOnly == true,
	}
	entryByPrefix[prefix] = entry
	if authorEntry then
		table.insert(ObNoxPatchNotes.entries, #ObNoxPatchNotes.entries, entry)
	else
		table.insert(ObNoxPatchNotes.entries, entry)
	end
	refreshSeenData()
	if not seenData[entry.prefix] then
		local baseline = loadSeenData()
		if baseline[entry.prefix] == nil then
			baseline[entry.prefix] = tostring(entry.currentVersion)
			if saveSeenData(baseline) then seenData = baseline end
		end
	end
	onpDprint("register:", prefix, "(" .. tostring(modName) .. "), total entries now", #ObNoxPatchNotes.entries)
end

local function newFlatButton(x, y, w, h, text, target, onclick, color)
	local btn = ISButton:new(x, y, w, h, text, target, onclick)
	btn:initialise()
	btn:instantiate()
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0.08 }
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.textColor = color or COL_TEXT
	return btn
end

local function newImageButton(x, y, w, h, texturePath, fallbackText, target, onclick)
	local texture = getTexture(texturePath)
	local btn = newFlatButton(x, y, w, h, texture and "" or fallbackText, target, onclick, COL_ACCENT)
	btn:setImage(texture)
	btn:setDisplayBackground(false)
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }

	function btn:render()
		local image = self.image
		if not image then
			ISButton.render(self)
			return
		end
		local alpha = self.enable and 1 or 0.35
		local drawW = math.min(self:getWidth(), ARROW_W * ARROW_TEXTURE_SCALE)
		local drawH = math.min(self:getHeight(), ROW_H * ARROW_TEXTURE_SCALE)
		local drawX = (self:getWidth() - drawW) / 2
		local drawY = (self:getHeight() - drawH) / 2
		self:drawTextureScaledAspect(image, drawX, drawY, drawW, drawH, alpha, 1, 1, 1)
	end

	return btn
end

local function newLinkImageButton(x, y, w, h, texturePath, fallbackText, target, onclick)
	local texture = getTexture(texturePath)
	local btn = newFlatButton(x, y, w, h, texture and "" or fallbackText, target, onclick, COL_TEXT)
	btn:setImage(texture)
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }

	function btn:render()
		if self.image then
			local imageSize = math.min(LINK_ICON_SIZE, self:getHeight())
			local imageY = (self:getHeight() - imageSize) / 2
			local alpha = self.enable and 1 or 0.35
			local steamX = (self:getWidth() - imageSize) / 2
			self:drawTextureScaledAspect(self.image, steamX, imageY, imageSize, imageSize, alpha, 1, 1, 1)
		else
			self:drawTextCentre(fallbackText, self:getWidth() / 2, S(4), 1, 1, 1, 1, FONT)
		end
	end

	return btn
end

ObNoxPatchNotes_Panel = ISPanelJoypad:derive("ObNoxPatchNotes_Panel")
ObNoxPatchNotes.instance = nil

local lastModIndex = 1

function ObNoxPatchNotes_Panel:new(x, y, w, h, autoMode)
	local o = ISPanelJoypad:new(x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	o.modIndex = math.max(1, math.min(lastModIndex, #ObNoxPatchNotes.entries))
	o.currentPage = 1
	o.autoMode = autoMode == true
	return o
end

function ObNoxPatchNotes_Panel:getCurrentEntry()
	return ObNoxPatchNotes.entries[self.modIndex]
end

function ObNoxPatchNotes_Panel:createChildren()
	ISPanelJoypad.createChildren(self)

	local winW = self:getWidth()
	local winH = self:getHeight()
	local y = S(8)
	local titleH = getTextManager():getFontHeight(FONT_LARGE)
	self.titleY = y

	local scrollW = winW * 0.65
	local scrollH = S(6)
	local scrollGap = 0
	local arrowButtonW = ARROW_W * ARROW_HIT_SCALE
	local arrowButtonH = ROW_H * ARROW_HIT_SCALE
	self.modScrollY = self.titleY + titleH + S(8)
	local arrowButtonY = self.modScrollY + (scrollH - arrowButtonH) / 2
	local selectorW = arrowButtonW * 2 + scrollGap * 2 + scrollW
	local selectorX = (winW - selectorW) / 2
	self.btnModPrev = newImageButton(selectorX, arrowButtonY, arrowButtonW, arrowButtonH, ARROW_LEFT_PATH, "<", self, ObNoxPatchNotes_Panel.onPrevMod)
	self:addChild(self.btnModPrev)

	self.modScrollX = selectorX + arrowButtonW + scrollGap
	self.modScrollW = scrollW
	self.modScrollH = scrollH

	self.btnModNext = newImageButton(self.modScrollX + scrollW + scrollGap, arrowButtonY, arrowButtonW, arrowButtonH, ARROW_RIGHT_PATH, ">", self, ObNoxPatchNotes_Panel.onNextMod)
	self:addChild(self.btnModNext)

	local smallFontH = getTextManager():getFontHeight(FONT)
	self.modCountY = self.modScrollY + scrollH + S(2)
	self.modIconSize = S(48)
	self.modIconY = self.modCountY + smallFontH + S(8)
	self.modNameY = self.modIconY + self.modIconSize + S(2)
	self.versionY = self.modNameY + titleH

	local pagH = ROW_H
	local pageFontH = getTextManager():getFontHeight(FONT)
	self.modIdentifiersY = winH - S(8) - pageFontH * 2
	self.modDetailsY = self.modNameY + S(4)
	local steamButtonW = LINK_BUTTON_WIDTH
	local steamButtonH = winH * (0.167 * 0.12) / PANEL_H_RATIO
	local contentY = self.versionY + smallFontH + S(4)
	local steamButtonY = contentY - S(4) - steamButtonH
	self.pageControlsBottom = contentY - S(4)
	local listH = self.modIdentifiersY - S(8) - contentY
	self.btnSteam = newLinkImageButton(winW - PAD - steamButtonW - S(2), steamButtonY, steamButtonW, steamButtonH,
		STEAM_TEXTURE_PATH, STEAM_FALLBACK_TEXT, self, ObNoxPatchNotes_Panel.onSteamWorkshop)
	self:addChild(self.btnSteam)

	if self.autoMode then
		local closeButtonSize = AUTO_ICON_SIZE
		self.btnAutoClose = newImageButton(winW - S(8) - closeButtonSize, S(8), closeButtonSize,
			closeButtonSize, OPEN_TEXTURE_PATH, "X", self, ObNoxPatchNotes_Panel.onAutoClose)
		self.btnAutoClose.tooltip = CLOSE_PANEL_TOOLTIP
		function self.btnAutoClose:render()
			if self.image then
				self:drawTextureScaledAspect(self.image, 0, 0, self:getWidth(), self:getHeight(), 1, 1, 1, 1)
			else
				ISButton.render(self)
			end
		end
		self:addChild(self.btnAutoClose)
	end

	self.contentPanel = ISPanel:new(PAD, contentY, winW - PAD * 2, listH)
	self.contentPanel:initialise()
	self.contentPanel:instantiate()
	self.contentPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
	self.contentPanel.borderColor = { r = 1, g = 1, b = 1, a = 0.6 }
	self:addChild(self.contentPanel)

	self.noteList = ISScrollingListBox:new(1, 1, self.contentPanel:getWidth() - 2, self.contentPanel:getHeight() - 2)
	self.noteList:initialise()
	self.noteList:instantiate()
	self.noteList.itemheight = LINE_H
	self.noteList.selected = 0
	self.noteList.font = FONT
	self.noteList.drawBorder = false
	self.noteList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.noteList.doDrawItem = ObNoxPatchNotes_Panel.drawNoteLine
	self.contentPanel:addChild(self.noteList)
	local pageArrowW = ARROW_W * ARROW_HIT_SCALE
	local pageArrowH = pagH * ARROW_HIT_SCALE
	self.pageArrowW = pageArrowW
	self.pageArrowH = pageArrowH
	self.btnPagePrev = newImageButton(0, 0, pageArrowW, pageArrowH, ARROW_LEFT_PATH, "<", self, ObNoxPatchNotes_Panel.onPrevPage)
	self:addChild(self.btnPagePrev)

	self.btnPageNext = newImageButton(0, 0, pageArrowW, pageArrowH, ARROW_RIGHT_PATH, ">", self, ObNoxPatchNotes_Panel.onNextPage)
	self:addChild(self.btnPageNext)

	self.pageEntry = ISTextEntryBox:new("1", 0, 0, S(12), pageFontH)
	self.pageEntry:initialise()
	self.pageEntry:instantiate()
	self.pageEntry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.pageEntry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	self.pageEntry:setOnlyNumbers(true)
	self.pageEntry.javaObject:setCentreVertically(true)
	self.pageEntry.javaObject:setTextColor(ColorInfo.new(COL_DIM.r, COL_DIM.g, COL_DIM.b, 1))
	self.pageEntry.onTextChange = function(box)
		local liveText = box:getInternalText()
		if string.len(liveText) > 3 then
			liveText = string.sub(liveText, 1, 3)
			box:setText(liveText)
		end
		self:layoutPageIndicator(liveText)
	end
	self.pageEntry.onCommandEntered = function(_)
		self:onPageInput()
	end
	self:addChild(self.pageEntry)

	if self.autoMode or ObNoxPatchNotes.canAdjustAutoShow() then
		local autoButtonSize = AUTO_ICON_SIZE
		self.btnAutoShow = newFlatButton(S(8), winH - S(8) - autoButtonSize, autoButtonSize, autoButtonSize,
			"", self, ObNoxPatchNotes_Panel.onAutoShowMode, COL_DIM)
		self.btnAutoShow.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
		self.btnAutoShow.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
		self.btnAutoShow.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		function self.btnAutoShow:render()
			if self.image then
				self:drawTextureScaledAspect(self.image, 0, 0, self:getWidth(), self:getHeight(), 1, 1, 1, 1)
			end
		end
		self:addChild(self.btnAutoShow)
		self:updateAutoShowButton()
	end

	self.pagePrefixText = ""
	self.pageSuffixText = "/ 1"

	self:showMod()
end

function ObNoxPatchNotes_Panel:layoutPageIndicator(liveEntryText)
	if not self.pageEntry then return end

	local tmgr = getTextManager()
	local arrowGap = S(4)
	local fieldTrailingGap = math.floor(tmgr:MeasureStringX(FONT, " ") * 0.5 + 0.5)
	local currentText = liveEntryText
	if currentText == nil then currentText = tostring(self.currentPage or 1) end
	if currentText == "" then currentText = "0" end
	if currentText == "1" then
		fieldTrailingGap = fieldTrailingGap + math.max(0, S(1) - 1) * 2
	end
	local entryInset = S(4)
	local entryW = tmgr:MeasureStringX(FONT, currentText) + entryInset
	local entryH = tmgr:getFontHeight(FONT)
	local suffixW = tmgr:MeasureStringX(FONT, self.pageSuffixText or "")
	local arrowW = self.pageArrowW or 0
	local arrowH = self.pageArrowH or 0
	local maximumNumberW = tmgr:MeasureStringX(FONT, "000 / 000") + S(8)
	local minimumControlW = maximumNumberW + arrowW * 2 + arrowGap * 2
	local totalW = minimumControlW
	local startX = PAD
	local arrowY = (self.pageControlsBottom or PAD) - arrowH
	local rowY = arrowY + (arrowH - entryH) / 2
	local numberGroupW = entryW + fieldTrailingGap + suffixW
	local numberGroupX = startX + (totalW - numberGroupW) / 2

	self.btnPagePrev:setX(startX)
	self.btnPagePrev:setY(arrowY)
	self.pageTextY = rowY
	self.pagePrefixX = numberGroupX
	self.pageEntry:setX(numberGroupX)
	self.pageEntry:setY(rowY - S(1))
	self.pageEntry:setWidth(entryW)
	self.pageEntry:setHeight(entryH)
	self.pageSuffixX = numberGroupX + entryW + fieldTrailingGap
	self.btnPageNext:setX(startX + totalW - arrowW)
	self.btnPageNext:setY(arrowY)
end

function ObNoxPatchNotes_Panel:showMod()
	local entry = self:getCurrentEntry()
	if not entry then return end
	markEntrySeen(entry)

	self.totalPages = math.max(1, #entry.history + (#entry.links > 0 and 1 or 0))
	self.currentPage = 1

	self.modCountText = string.format("%d / %d", self.modIndex, #ObNoxPatchNotes.entries)
	self.modNameText = entry.modName
	self.modIconTexture = entry.iconPath and getTexture(entry.iconPath) or nil
	self.versionText = entry.isAuthor and "" or getText("IGUI_OBNOXPN_VersionFormat", tostring(entry.currentVersion))
	self.authorMottoText = entry.isAuthor and ("'" .. tostring(entry.currentVersion) .. "'") or ""
	self.currentIsAuthor = entry.isAuthor == true
	self.workshopIDText = getText("IGUI_OBNOXPN_WorkshopIDFormat", entry.workshopID ~= "" and entry.workshopID or NOT_PUBLISHED_TEXT)
	self.modIDText = getText("IGUI_OBNOXPN_ModIDFormat", entry.modID ~= "" and entry.modID or UNAVAILABLE_TEXT)
	if self.btnSteam then
		self.btnSteam:setVisible(not self.currentIsAuthor)
		self.btnSteam.enable = not self.currentIsAuthor and entry.workshopID ~= ""
		local workshopUrl = NOT_PUBLISHED_TEXT
		if entry.workshopID ~= "" then
			workshopUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. entry.workshopID
		end
		self.btnSteam.tooltip = STEAM_CTA_TEXT .. " <IMAGE:" .. LIKE_TEXTURE_PATH .. ",20,20>\n" .. workshopUrl
	end
	if self.btnModPrev then self.btnModPrev.enable = #ObNoxPatchNotes.entries > 1 end
	if self.btnModNext then self.btnModNext.enable = #ObNoxPatchNotes.entries > 1 end

	self:showPage()
end

function ObNoxPatchNotes_Panel:showPage()
	local entry = self:getCurrentEntry()
	if not entry then return end

	for _, button in ipairs(self.openLinkButtons or {}) do
		button:setVisible(false)
		self.noteList:removeChild(button)
	end
	self.openLinkButtons = {}
	self.noteList:clear()
	local topPaddingItem = self.noteList:addItem("__top_padding__", { padding = true })
	topPaddingItem.height = S(2)
	local maxW = self.noteList:getWidth() - TEXT_PAD * 2 - SCROLL_W - S(4)
	local historyCount = #entry.history

	if self.currentPage <= historyCount then
		local versionEntry = entry.history[self.currentPage]
		if versionEntry then
			local versionHeader = self.noteList:addItem(versionEntry.version, {
				header = true,
				text = getText("IGUI_OBNOXPN_VersionFormat", tostring(versionEntry.version)),
				date = tostring(versionEntry.date),
			})
			versionHeader.height = getTextManager():getFontHeight(FONT_LARGE) + getTextManager():getFontHeight(FONT) + S(4)
			self.noteList:addItem("", { header = false, text = "" })
			self:addLines(versionEntry.notes or {}, maxW)
		end
	else
		self:addLines(entry.links, maxW, entry.isAuthor)
	end

	if not entry.isAuthor then
		self.noteList:addItem("", { header = false, text = "" })
	end

	if self.pageEntry then self.pageEntry:setText(tostring(self.currentPage)) end
	self.pageSuffixText = string.format("/ %d", self.totalPages)
	self:layoutPageIndicator()
	if self.btnPagePrev then self.btnPagePrev.enable = self.currentPage > 1 end
	if self.btnPageNext then self.btnPageNext.enable = self.currentPage < self.totalPages end
end

function ObNoxPatchNotes_Panel:addLines(entries, maxW, centered)
	for _, entry in ipairs(entries or {}) do
		if entry.spacer then
			self.noteList:addItem("", { header = false, text = "" })
		elseif entry.separator then
			local separatorItem = self.noteList:addItem("__separator__", { separator = true })
			separatorItem.height = S(13)
		elseif entry.header then
			local headerItem = self.noteList:addItem(entry.header, { header = true, text = entry.header, centered = centered })
			headerItem.height = getTextManager():getFontHeight(FONT_LARGE) + S(4)
		elseif entry.openUrl then
			local openData = {
				openBtnRow = true,
				openUrl = entry.openUrl,
				iconPath = entry.iconPath,
				tooltipTitle = entry.tooltipTitle,
				centered = centered,
			}
			local openItem = self.noteList:addItem("__openbtn__", openData)
			openItem.height = S(33)
			self:addOpenLinkButton(openData)
		elseif entry.line then
			local wrapped = self:wrapLine(entry.line, maxW)
			for _, wl in ipairs(wrapped) do
				self.noteList:addItem(wl, { header = false, text = wl, centered = centered })
			end
		end
	end
end

function ObNoxPatchNotes_Panel:addOpenLinkButton(data)
	local button = newFlatButton(0, 0, 1, 1, "", self, ObNoxPatchNotes_Panel.onOpenLinkButton, COL_TEXT)
	button.openUrl = data.openUrl
	button.tooltip = (data.tooltipTitle or OPEN_LINK_LABEL) .. "\n" .. data.openUrl
	button.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	button.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
	button.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	self.noteList:addChild(button)
	self.openLinkButtons[#self.openLinkButtons + 1] = button
	data.hoverButton = button
end

function ObNoxPatchNotes_Panel:wrapLine(line, maxW)
	if line == "" then return { "" } end
	local tmgr = getTextManager()
	if tmgr:MeasureStringX(FONT, line) <= maxW then
		return { line }
	end
	local wrapped = tmgr:WrapText(FONT, line, maxW, 10, "")
	local result = {}
	for segment in string.gmatch(wrapped, "[^\n]+") do
		result[#result + 1] = segment
	end
	return #result > 0 and result or { line }
end

local function getLinkButtonPadX()
	return S(10)
end

local function getLinkButtonHeight()
	return S(21)
end

function ObNoxPatchNotes_Panel:drawNoteLine(y, item, alt)
	local data = item.item or {}
	local w = self:getWidth()
	if data.padding then
		return y + (item.height or LINE_H)
	end
	if data.separator then
		local separatorY = y + (item.height or LINE_H) / 2
		self:drawRect(TEXT_PAD, separatorY, w - TEXT_PAD * 2, 1, 0.6, 1, 1, 1)
		return y + (item.height or LINE_H)
	end

	if data.openBtnRow then
		local btnH = getLinkButtonHeight()
		local label = OPEN_LINK_LABEL
		local btnW = self:getWidth() * 0.2
		local btnX = data.centered and ((w - btnW) / 2) or TEXT_PAD
		local btnY = y + S(6)
		data.btnW = btnW
		if data.hoverButton then
			data.hoverButton:setX(btnX)
			data.hoverButton:setY(btnY + self:getYScroll())
			data.hoverButton:setWidth(btnW)
			data.hoverButton:setHeight(btnH)
			data.hoverButton:setVisible(true)
		end
		self:drawRect(btnX, btnY, btnW, btnH, 0.9, 0, 0, 0)
		self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 1, 1, 1)
		local icon = data.iconPath and getTexture(data.iconPath) or nil
		if icon then
			local iconSize = LINK_ICON_SIZE
			self:drawTextureScaledAspect(icon, btnX + (btnW - iconSize) / 2, btnY + (btnH - iconSize) / 2,
				iconSize, iconSize, 1, 1, 1, 1)
		else
			self:drawTextCentre(label, btnX + btnW / 2, btnY + S(2), 1, 1, 1, 1, FONT)
		end
		return y + (item.height or LINE_H)
	end

	if data.header then
		local headerX = TEXT_PAD
		if data.centered then
			local headerW = getTextManager():MeasureStringX(FONT_LARGE, data.text)
			headerX = math.max(TEXT_PAD, (w - headerW) / 2)
		end
		self:drawText(data.text, headerX, y + S(2), 1, 1, 1, 1, FONT_LARGE)
		if data.date then
			local dateY = y + S(2) + getTextManager():getFontHeight(FONT_LARGE)
			self:drawText(data.date, TEXT_PAD, dateY, 1, 1, 1, 1, FONT)
		end
	elseif data.text ~= "" then
		local lineX = TEXT_PAD
		if data.centered then
			local lineW = getTextManager():MeasureStringX(FONT, data.text)
			lineX = math.max(TEXT_PAD, (w - lineW) / 2)
		end
		self:drawText(data.text, lineX, y + S(2), 1, 1, 1, 1, FONT)
	end
	return y + (item.height or LINE_H)
end

function ObNoxPatchNotes_Panel:onOpenLinkButton(button)
	if not button or not button.openUrl then return end
	openUrl("https://steamcommunity.com/linkfilter/?u=" .. button.openUrl)
end

function ObNoxPatchNotes_Panel:onPrevMod()
	if #ObNoxPatchNotes.entries <= 1 then return end
	self.modIndex = self.modIndex - 1
	if self.modIndex < 1 then self.modIndex = #ObNoxPatchNotes.entries end
	lastModIndex = self.modIndex
	self:showMod()
end

function ObNoxPatchNotes_Panel:onNextMod()
	if #ObNoxPatchNotes.entries <= 1 then return end
	self.modIndex = self.modIndex + 1
	if self.modIndex > #ObNoxPatchNotes.entries then self.modIndex = 1 end
	lastModIndex = self.modIndex
	self:showMod()
end

function ObNoxPatchNotes_Panel:onPrevPage()
	if self.currentPage > 1 then
		self.currentPage = self.currentPage - 1
		self:showPage()
	end
end

function ObNoxPatchNotes_Panel:onNextPage()
	if self.currentPage < self.totalPages then
		self.currentPage = self.currentPage + 1
		self:showPage()
	end
end

function ObNoxPatchNotes_Panel:onPageInput()
	local page = tonumber(self.pageEntry:getText()) or 1
	page = math.max(1, math.min(page, self.totalPages))
	self.currentPage = page
	self:showPage()
end

function ObNoxPatchNotes_Panel:onSteamWorkshop()
	local entry = self:getCurrentEntry()
	if not entry or not entry.workshopID or entry.workshopID == "" then return end

	local workshopUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. entry.workshopID
	openUrl("https://steamcommunity.com/linkfilter/?u=" .. workshopUrl)
end

function ObNoxPatchNotes_Panel:onAutoClose()
	self:close()
	ObNoxPatchNotes.setButtonOpen(false)
end

function ObNoxPatchNotes_Panel:updateAutoShowButton()
	if not self.btnAutoShow then return end
	local mode = ObNoxPatchNotes.getAutoShowMode()
	local texturePath = OPT_UPDATE_TEXTURE_PATH
	local tooltipText = VISIBILITY_AUTO_TEXT
	if mode == AUTO_SHOW_ON then
		texturePath = OPT_IN_TEXTURE_PATH
		tooltipText = VISIBILITY_ON_TEXT
	elseif mode == AUTO_SHOW_OFF then
		texturePath = OPT_OUT_TEXTURE_PATH
		tooltipText = VISIBILITY_OFF_TEXT
	end
	local texture = getTexture(texturePath)
	self.btnAutoShow:setImage(texture)
	self.btnAutoShow:setTitle(texture and "" or mode)
	self.btnAutoShow.tooltip = tooltipText
end

function ObNoxPatchNotes_Panel:onAutoShowMode()
	local mode = ObNoxPatchNotes.getAutoShowMode()
	if mode == AUTO_SHOW_AUTO then
		mode = AUTO_SHOW_ON
	elseif mode == AUTO_SHOW_ON then
		mode = AUTO_SHOW_OFF
	else
		mode = AUTO_SHOW_AUTO
	end
	ObNoxPatchNotes.setAutoShowMode(mode)
	self:updateAutoShowButton()
end

function ObNoxPatchNotes_Panel:close()
	if self.autoMode and self.previousGameSpeed ~= nil then
		setGameSpeed(self.previousGameSpeed)
		self.previousGameSpeed = nil
	end
	self:setVisible(false)
	if self.parent then
		self.parent:removeChild(self)
	else
		self:removeFromUIManager()
	end
	ObNoxPatchNotes.instance = nil
end

function ObNoxPatchNotes_Panel:prerender()
	if self.autoMode then
		local viewportW = self.parent and self.parent:getWidth() or getCore():getScreenWidth()
		local viewportH = self.parent and self.parent:getHeight() or getCore():getScreenHeight()
		local centredX = math.floor((viewportW - self:getWidth()) / 2 + 0.5)
		local centredY = math.floor((viewportH - self:getHeight()) / 2 + 0.5)
		if self:getX() ~= centredX then self:setX(centredX) end
		if self:getY() ~= centredY then self:setY(centredY) end
	end

	local w, h = self:getWidth(), self:getHeight()
	for _, button in ipairs(self.openLinkButtons or {}) do
		button:setVisible(false)
	end
	self:drawRect(0, 0, w, h, 0.9, 0, 0, 0)
	self:drawRectBorder(0, 0, w, h, 0.8, 1, 1, 1)

	local tmgr = getTextManager()
	local titleText = PATCH_NOTES_TITLE
	local titleW = tmgr:MeasureStringX(FONT_LARGE, titleText)
	self:drawText(titleText, (w - titleW) / 2, self.titleY or PAD, 1, 1, 1, 1, FONT_LARGE)

	if self.modScrollX and self.modScrollW then
		local totalMods = math.max(1, #ObNoxPatchNotes.entries)
		local thumbW = self.modScrollW / totalMods
		local thumbX = self.modScrollX + thumbW * math.max(0, self.modIndex - 1)
		self:drawRect(self.modScrollX, self.modScrollY, self.modScrollW, self.modScrollH, 0.9, 0.08, 0.08, 0.08)
		self:drawRect(thumbX, self.modScrollY, thumbW, self.modScrollH, 0.9, 1, 1, 1)
	end

	local countW = tmgr:MeasureStringX(FONT, self.modCountText or "")
	self:drawText(self.modCountText or "", (w - countW) / 2, self.modCountY or PAD, 1, 1, 1, 1, FONT)

	if self.modIconTexture and self.modIconSize then
		local iconX = (w - self.modIconSize) / 2
		self:drawTextureScaledAspect(self.modIconTexture, iconX, self.modIconY, self.modIconSize, self.modIconSize, 1, 1, 1, 1)
	end

	local modNameW = tmgr:MeasureStringX(FONT_LARGE, self.modNameText or "")
	self:drawText(self.modNameText or "", (w - modNameW) / 2, self.modNameY or PAD, 1, 1, 1, 1, FONT_LARGE)

	local versionW = tmgr:MeasureStringX(FONT, self.versionText or "")
	self:drawText(self.versionText or "", (w - versionW) / 2, self.versionY or PAD, 1, 1, 1, 1, FONT)

	if not self.currentIsAuthor then
		local workshopText = self.workshopIDText or getText("IGUI_OBNOXPN_WorkshopIDFormat", UNAVAILABLE_TEXT)
		local modIDText = self.modIDText or getText("IGUI_OBNOXPN_ModIDFormat", UNAVAILABLE_TEXT)
		local workshopW = tmgr:MeasureStringX(FONT, workshopText)
		local modIDW = tmgr:MeasureStringX(FONT, modIDText)
		self:drawText(workshopText, (w - workshopW) / 2, self.modIdentifiersY or PAD, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT)
		self:drawText(modIDText, (w - modIDW) / 2, (self.modIdentifiersY or PAD) + tmgr:getFontHeight(FONT), COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT)
	else
		local mottoText = self.authorMottoText or ""
		local mottoW = tmgr:MeasureStringX(FONT, mottoText)
		local mottoY = (self.modIdentifiersY or PAD) + tmgr:getFontHeight(FONT) / 2
		self:drawText(mottoText, (w - mottoW) / 2, mottoY, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT)
	end

	if self.pageTextY then
		self:drawText(self.pagePrefixText or "", self.pagePrefixX or 0, self.pageTextY, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT)
		self:drawText(self.pageSuffixText or "", self.pageSuffixX or 0, self.pageTextY, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT)
	end
end

function ObNoxPatchNotes.open(autoMode, mainMenuTrigger)
	onpDprint("open() called, entries =", #ObNoxPatchNotes.entries)
	if #ObNoxPatchNotes.entries == 0 then
		onpDprint("open() aborted: no entries registered yet")
		return
	end
	ensureAuthorEntry()
	refreshSeenData()
	local unseenCount = prioritiseUnseenEntries()
	if unseenCount > 0 then lastModIndex = 1 end
	if autoMode then
		local autoShowMode = ObNoxPatchNotes.getAutoShowMode()
		if autoShowMode == AUTO_SHOW_OFF then
			onpDprint("openAuto() aborted: automatic display mode is off")
			return
		end
		if mainMenuTrigger then
			local hasMainMenuOnlyEntry = false
			for _, entry in ipairs(ObNoxPatchNotes.entries) do
				if entry.mainMenuOnly then
					hasMainMenuOnlyEntry = true
					break
				end
			end
			if not hasMainMenuOnlyEntry then
				onpDprint("openAutoMainMenu() aborted: no mainMenuOnly mod registered")
				return
			end
		end
		local unseenIndex = getFirstUnseenIndex(mainMenuTrigger)
		if autoShowMode == AUTO_SHOW_AUTO and not unseenIndex then
			onpDprint("openAuto() aborted: auto mode has no unseen mods")
			return
		end
		if unseenIndex then lastModIndex = unseenIndex end
	end

	if ObNoxPatchNotes.instance then
		if autoMode then return end
		onpDprint("open(): closing existing instance first")
		ObNoxPatchNotes.instance:close()
	end

	local physicalW = getCore():getScreenWidth()
	local physicalH = getCore():getScreenHeight()
	local mainScreen = MainScreen.instance
	local screenW = mainScreen and mainScreen:getWidth() or physicalW
	local screenH = mainScreen and mainScreen:getHeight() or physicalH
	refreshLayoutMetrics(screenW, screenH, physicalW, physicalH)
	local w = math.min(PANEL_W, screenW - EDGE_PAD_X * 2)
	local h = math.min(PANEL_H, screenH - EDGE_PAD_Y * 2)
	local x = screenW - w - EDGE_PAD_X
	local y = EDGE_PAD_Y
	if autoMode then
		x = (screenW - w) / 2
		y = (screenH - h) / 2
	end

	local panel = ObNoxPatchNotes_Panel:new(x, y, w, h, autoMode)
	panel:setAnchorLeft(false)
	panel:setAnchorTop(true)
	panel:setAnchorRight(true)
	panel:setAnchorBottom(false)
	panel:initialise()
	panel:instantiate()

	local mainScreenIsPauseMenu = MainScreen.instance and MainScreen.instance.inGame
	if MainScreen.instance and not (autoMode and mainScreenIsPauseMenu) then
		onpDprint("open(): MainScreen.instance found, addChild path")
		MainScreen.instance:addChild(panel)
	else
		onpDprint("open(): top-level addToUIManager path (in-game auto popup or no MainScreen)")
		panel:addToUIManager()
	end

	ObNoxPatchNotes.instance = panel
	if autoMode and not mainMenuTrigger and not isClient() and not isServer() then
		panel.previousGameSpeed = getGameSpeed()
		setGameSpeed(0)
	end
	panel:setVisible(true)
	ObNoxPatchNotes.bringButtonToTop()
	onpDprint("open(): panel created and set visible, x=" .. tostring(x) .. " y=" .. tostring(y) .. " w=" .. tostring(w) .. " h=" .. tostring(h))
end

function ObNoxPatchNotes.openAuto()
	ObNoxPatchNotes.open(true)
end

function ObNoxPatchNotes.openAutoMainMenu()
	ObNoxPatchNotes.open(true, true)
end

local hasCheckedThisSession = false
local function isEligibleForAutoPopup(player)
	return hasAutomaticDisplayAccess(player)
end

local function onCreatePlayer(playerIndex, player)
	if playerIndex ~= 0 or hasCheckedThisSession then return end
	hasCheckedThisSession = true
	local ticksWaited = 0
	local function deferredAutoOpen()
		ticksWaited = ticksWaited + 1
		if ticksWaited < 10 then return end
		Events.OnTick.Remove(deferredAutoOpen)
		if isEligibleForAutoPopup(player or getSpecificPlayer(0)) then
			ObNoxPatchNotes.openAuto()
		end
	end
	Events.OnTick.Add(deferredAutoOpen)
end

if Events then Events.OnCreatePlayer.Add(onCreatePlayer) end

local hasCheckedMainMenuThisSession = false
local function onMainMenuEnter()
	if hasCheckedMainMenuThisSession then return end
	hasCheckedMainMenuThisSession = true
	local ticksWaited = 0
	local function deferredMainMenuAutoOpen()
		ticksWaited = ticksWaited + 1
		if ticksWaited < 10 then return end
		local screen = MainScreen and MainScreen.instance
		local isMainMenuRoot = screen and not screen.inGame
			and screen.bottomPanel and screen.bottomPanel:getIsVisible()
		if not isMainMenuRoot then return end
		Events.OnFETick.Remove(deferredMainMenuAutoOpen)
		ObNoxPatchNotes.openAutoMainMenu()
	end
	Events.OnFETick.Add(deferredMainMenuAutoOpen)
end

if Events then Events.OnMainMenuEnter.Add(onMainMenuEnter) end

local BTN_SIZE = 32
local PANEL_EDGE_PAD = 38
local BUTTON_PANEL_INSET = 8

local triggerButton = nil
local triggerButtonScreen = nil
local texClosed, texOpen, texAlert

local function onTriggerButtonClick()
	onpDprint("trigger button clicked")
	if ObNoxPatchNotes.instance then
		ObNoxPatchNotes.instance:close()
	else
		ObNoxPatchNotes.open()
	end
	ObNoxPatchNotes.setButtonOpen(ObNoxPatchNotes.instance ~= nil)
end

local function addTriggerButton(screen)
	local physicalW = getCore():getScreenWidth()
	local physicalH = getCore():getScreenHeight()
	local screenW = screen:getWidth()
	local screenH = screen:getHeight()
	local scaleX = screenW / physicalW
	local scaleY = screenH / physicalH
	local buttonSizeX = BTN_SIZE * scaleX
	local buttonSizeY = BTN_SIZE * scaleY
	local buttonX = math.floor(screenW - (PANEL_EDGE_PAD + BUTTON_PANEL_INSET) * scaleX - buttonSizeX + 0.5)
	local buttonY = math.floor((PANEL_EDGE_PAD + BUTTON_PANEL_INSET) * scaleY + 0.5)
	texClosed = getTexture(CLOSED_TEXTURE_PATH)
	texOpen = getTexture(OPEN_TEXTURE_PATH)
	texAlert = getTexture(ALERT_TEXTURE_PATH)
	local isOpen = ObNoxPatchNotes.instance ~= nil
	local texture = isOpen and texOpen or texClosed
	local btn = ISButton:new(buttonX, buttonY, buttonSizeX, buttonSizeY, texture and "" or SHORT_LABEL_TEXT, nil, onTriggerButtonClick)
	btn:initialise()
	btn:instantiate()
	btn:setImage(texture)
	btn:setDisplayBackground(false)
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.tooltip = isOpen and CLOSE_PANEL_TOOLTIP or OPEN_PANEL_TOOLTIP
	btn:setAnchorLeft(false)
	btn:setAnchorRight(true)
	btn:setAnchorTop(true)
	btn:setAnchorBottom(false)

	function btn:render()
		local image = self.image
		if not image then
			ISButton.render(self)
			return
		end
		local size = math.min(self:getWidth(), self:getHeight())
		local x = (self:getWidth() - size) / 2
		local y = (self:getHeight() - size) / 2
		self:drawTextureScaledAspect(image, x, y, size, size, 1, 1, 1, 1)
		if texAlert and ObNoxPatchNotes.hasUnseen and ObNoxPatchNotes.hasUnseen() then
			self:drawTextureScaledAspect(texAlert, x, y, size, size, 1, 1, 1, 1)
		end
	end

	screen:addChild(btn)
	triggerButton = btn
	triggerButtonScreen = screen
	onpDprint("trigger button added to MainScreen at x=" .. tostring(buttonX) .. " y=" .. tostring(buttonY))
end

local function ensureTriggerButton(screen)
	if triggerButton and triggerButtonScreen ~= screen then
		if triggerButton.parent then triggerButton.parent:removeChild(triggerButton) end
		triggerButton = nil
		triggerButtonScreen = nil
	end
	if not triggerButton then addTriggerButton(screen) end
end

function ObNoxPatchNotes.bringButtonToTop()
	if triggerButton and triggerButton.parent then triggerButton:bringToTop() end
end

function ObNoxPatchNotes.setButtonOpen(isOpen)
	if not triggerButton then return end
	local texture = isOpen and texOpen or texClosed
	triggerButton:setImage(texture)
	triggerButton:setTitle(texture and "" or SHORT_LABEL_TEXT)
	triggerButton.tooltip = isOpen and CLOSE_PANEL_TOOLTIP or OPEN_PANEL_TOOLTIP
end

local loggedNoScreen = false
local buttonTicksWaited = 0
local function onFETick()
	local screen = MainScreen and MainScreen.instance
	if not screen or screen.inGame then
		if not loggedNoScreen then
			onpDprint("onFETick: no MainScreen.instance yet (or in-game) -- waiting")
			loggedNoScreen = true
		end
		buttonTicksWaited = 0
		return
	end
	if not screen.bottomPanel or not screen.bottomPanel:getIsVisible() then
		buttonTicksWaited = 0
		return
	end
	if triggerButton and triggerButtonScreen == screen then return end
	buttonTicksWaited = buttonTicksWaited + 1
	if buttonTicksWaited < 10 then return end
	onpDprint("onFETick: MainScreen.instance found, adding button")
	ensureTriggerButton(screen)
end

local function syncMainMenuVisibility()
	local screen = MainScreen and MainScreen.instance
	if not screen or screen.inGame or not screen.bottomPanel then return end
	if not triggerButton or triggerButtonScreen ~= screen then return end

	local isMainMenuRoot = screen.bottomPanel:getIsVisible()
	triggerButton:setVisible(isMainMenuRoot)
	if not isMainMenuRoot and ObNoxPatchNotes.instance and ObNoxPatchNotes.instance.parent == screen then
		ObNoxPatchNotes.instance:close()
		ObNoxPatchNotes.setButtonOpen(false)
	end
end

local function updatePauseMenuButtonVisibility(screen)
	local isPauseMenuRoot = screen.bottomPanel and screen.bottomPanel:getIsVisible()
	if isPauseMenuRoot and screen.mainOptions and screen.mainOptions:isVisible() then isPauseMenuRoot = false end
	if isPauseMenuRoot and screen.scoreboard and screen.scoreboard:isVisible() then isPauseMenuRoot = false end
	if isPauseMenuRoot and screen.inviteFriends and screen.inviteFriends:isVisible() then isPauseMenuRoot = false end
	if triggerButton then triggerButton:setVisible(isPauseMenuRoot == true) end
	if not isPauseMenuRoot and ObNoxPatchNotes.instance and ObNoxPatchNotes.instance.parent == screen then
		ObNoxPatchNotes.instance:close()
		ObNoxPatchNotes.setButtonOpen(false)
	end
end

local function hookChildVisibility(child, screen)
	if not child or child._obnoxPatchNotesVisHooked then return end
	child._obnoxPatchNotesVisHooked = true
	local original = child.setVisible
	child.setVisible = function(self, ...)
		original(self, ...)
		updatePauseMenuButtonVisibility(screen)
	end
end

local function onTick()
	local screen = MainScreen and MainScreen.instance
	if not screen or not screen.inGame then return end
	ensureTriggerButton(screen)
	hookChildVisibility(screen.mainOptions, screen)
	hookChildVisibility(screen.scoreboard, screen)
	hookChildVisibility(screen.inviteFriends, screen)
	hookChildVisibility(screen.bottomPanel, screen)
	updatePauseMenuButtonVisibility(screen)
end

if Events then
	Events.OnFETick.Add(onFETick)
	Events.OnFETick.Add(syncMainMenuVisibility)
	Events.OnTick.Add(onTick)
end

return ObNoxPatchNotes
