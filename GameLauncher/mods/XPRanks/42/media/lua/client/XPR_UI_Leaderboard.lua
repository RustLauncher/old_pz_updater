if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "XPR_UI_Scale"

XPR_UI_Leaderboard = {}
XPR_UI_Leaderboard.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_MD
local FONT_H = XPR_UI_Scale.fontHgtMd
local PAD = S(10)
local ROW_H = FONT_H + S(10)
local LIST_ROW_H = ROW_H + S(2)
local PANEL_W = S(480 + 120 + 100)
local PANEL_H = S(440 + 120 + 20)
local MAX_ROWS = 10
local function LEADERBOARD_TITLE(isSP)
	return getText(isSP and "IGUI_XPR_Leaderboard_TitleHallOfFame" or "IGUI_XPR_Leaderboard_Title")
end
local POS_FILE = "XPRanks/XPR_LeaderboardPos.txt"

local REQUEST_RETRY_COOLDOWN_MS = 2100

local CACHE_FRESH_MS = 120000

local dataCache = nil
local cacheFetchedAtMs = nil

local nextAllowedSendMs = nil
local pendingRequest = false

local function sendRequestNow()
	local now = getTimestampMs and getTimestampMs() or 0
	pendingRequest = false
	nextAllowedSendMs = now + REQUEST_RETRY_COOLDOWN_MS
	local player = getSpecificPlayer(0)
	if not player then return end
	sendClientCommand(player, "XPRanks", "requestLeaderboard", {})
end

local function ensureFreshData()
	local now = getTimestampMs and getTimestampMs() or 0
	if dataCache and cacheFetchedAtMs and (now - cacheFetchedAtMs) < CACHE_FRESH_MS then
		return true
	end
	if nextAllowedSendMs and now < nextAllowedSendMs then
		pendingRequest = true
		return false
	end
	sendRequestNow()
	return false
end

local function retryPendingIfDue()
	if not pendingRequest then return end
	local now = getTimestampMs and getTimestampMs() or 0
	if not nextAllowedSendMs or now >= nextAllowedSendMs then
		sendRequestNow()
	end
end

local COL_GOLD = { r = 1.0, g = 0.85, b = 0.1 }
local COL_SILVER = { r = 0.75, g = 0.75, b = 0.78 }
local COL_BRONZE = { r = 0.80, g = 0.50, b = 0.20 }
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_DIM = { r = 0.60, g = 0.60, b = 0.60 }
local COL_SEPARATOR = { r = 0.4, g = 0.4, b = 0.4 }

local POS_OFFSET_X = S(-10)
local RANK_OFFSET_X = S(-30)
local PLAYER_OFFSET_X = S(-20)
local BASE_LIST_W = PANEL_W - PAD * 2

local function longestCategoryDisplayW()
	local cats = XPR_Categories and XPR_Categories.getLeaderboardCategories
		and XPR_Categories.getLeaderboardCategories()
	local texts = {}
	for _, cat in ipairs(cats or {}) do
		texts[#texts + 1] = cat.display
	end
	return XPR_UI_Scale.longestText(FONT, texts) + S(30)
end

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
	writer:write(tostring(math.floor(x)) .. "," .. tostring(math.floor(y)))
	writer:close()
end

local function drawTextCentered(ui, tm, text, centerX, y, color, font)
	font = font or FONT
	local textW = tm:MeasureStringX(font, text)
	ui:drawText(text, math.floor(centerX - textW / 2), y, color.r, color.g, color.b, 1, font)
end

local texRankShield = getTexture("media/textures/xpr_ldr_shield.png")
local COL_RANK_TEXT = { r = 0, g = 0, b = 0 }
local MAX_RANK_TEXT = tostring((XPR_RankCurve and XPR_RankCurve.MAX_RANK) or 999)
local RANK_SHIELD_PAD_X = S(18)
local RANK_TEXT_OFFSET_Y = S(3)

local function getRankShieldWidth(tm, iconSize)
	local maximumTextW = tm:MeasureStringX(FONT, MAX_RANK_TEXT)
	return math.max(iconSize, maximumTextW + RANK_SHIELD_PAD_X)
end

local function buildColumns(rows, isSP)
	local tm = getTextManager()
	local posCenter = BASE_LIST_W * 0.125 + POS_OFFSET_X
	local rankCenter = BASE_LIST_W * 0.375 + RANK_OFFSET_X
	local basePlayerCenter = BASE_LIST_W * 0.625 + PLAYER_OFFSET_X
	local baseXpCenter = BASE_LIST_W * 0.875
	local identityHeader = getText(isSP and "IGUI_XPR_Leaderboard_ColCharacter" or "IGUI_XPR_Leaderboard_ColPlayer")
	local rankW = math.max(tm:MeasureStringX(FONT, getText("IGUI_XPR_Leaderboard_ColRank")),
		getRankShieldWidth(tm, LIST_ROW_H - S(4) - 2))
	local headerPlayerW = tm:MeasureStringX(FONT, identityHeader)
	local headerXpW = tm:MeasureStringX(FONT, getText("IGUI_XPR_Leaderboard_ColXp"))
	local playerW = headerPlayerW
	local xpW = headerXpW

	for i, row in ipairs(rows or {}) do
		if i > MAX_ROWS then break end
		playerW = math.max(playerW, tm:MeasureStringX(FONT, tostring(row.username or "")))
		xpW = math.max(xpW, tm:MeasureStringX(FONT, tostring(row.xp or 0)))
	end

	local rankPlayerGap = basePlayerCenter - rankCenter - rankW / 2 - headerPlayerW / 2
	local playerXpGap = baseXpCenter - basePlayerCenter - headerPlayerW / 2 - headerXpW / 2
	local rightGap = BASE_LIST_W - baseXpCenter - headerXpW / 2
	local playerCenter = rankCenter + rankW / 2 + rankPlayerGap + playerW / 2
	local xpCenter = playerCenter + playerW / 2 + playerXpGap + xpW / 2

	return {
		posCenter = posCenter,
		rankCenter = rankCenter,
		playerCenter = playerCenter,
		xpCenter = xpCenter,
		requiredListW = xpCenter + xpW / 2 + rightGap,
	}
end

local function drawRankShield(ui, tm, rank, centerX, centerY, iconSize)
	local rankText = tostring(rank)
	if not texRankShield then
		drawTextCentered(ui, tm, rankText, centerX, centerY - FONT_H / 2 - RANK_TEXT_OFFSET_Y, COL_TEXT)
		return
	end

	local iconW = getRankShieldWidth(tm, iconSize)
	local iconX = centerX - iconW / 2
	local iconY = centerY - iconSize / 2
	ui:drawTextureScaled(texRankShield, iconX, iconY, iconW, iconSize, 1, 1, 1, 1)

	drawTextCentered(ui, tm, rankText, centerX, centerY - FONT_H / 2 - RANK_TEXT_OFFSET_Y, COL_RANK_TEXT, FONT)
end

local TROPHY_TEX = {
	getTexture("media/textures/TrophyGold.png"),
	getTexture("media/textures/TrophySilver.png"),
	getTexture("media/textures/TrophyBronze.png"),
}

local function drawLeaderboardItem(panel, listSelf, rowY, item)
	local data = item.item
	local ww = listSelf:getWidth()
	if data.pos % 2 == 0 then
		listSelf:drawRect(0, rowY, ww, listSelf.itemheight, 0.1, 0.302, 0.302, 0.302)
	end

	local tc = COL_TEXT
	if data.pos == 1 then tc = COL_GOLD
	elseif data.pos == 2 then tc = COL_SILVER
	elseif data.pos == 3 then tc = COL_BRONZE end

	local textY = rowY + math.floor((listSelf.itemheight - FONT_H) / 2)
	local tm = getTextManager()
	local columns = panel.columns
	if data.pos <= 3 and TROPHY_TEX[data.pos] then
		local trophySize = listSelf.itemheight - S(4) - 2
		listSelf:drawTextureScaledAspect(TROPHY_TEX[data.pos],
			math.floor(columns.posCenter - trophySize / 2),
			rowY + math.floor((listSelf.itemheight - trophySize) / 2),
			trophySize, trophySize, 1, 1, 1, 1)
	else
		drawTextCentered(listSelf, tm, "#" .. tostring(data.pos), columns.posCenter, textY, tc)
	end

	local rankIconSize = listSelf.itemheight - S(4) - 2
	drawRankShield(listSelf, tm, data.rank, columns.rankCenter,
		rowY + listSelf.itemheight / 2, rankIconSize)
	drawTextCentered(listSelf, tm, tostring(data.username), columns.playerCenter, textY, tc)
	drawTextCentered(listSelf, tm, tostring(data.xp), columns.xpCenter, textY, tc)
	return rowY + listSelf.itemheight
end

XPR_UI_Leaderboard.Panel = ISCollapsableWindow:derive("XPR_UI_Leaderboard_Panel")

function XPR_UI_Leaderboard.Panel:new(x, y, hasSavedPosition)
	local isSP = XPR_Env and XPR_Env.isSP()
	local o = ISCollapsableWindow.new(self, x, y, PANEL_W, PANEL_H, LEADERBOARD_TITLE(isSP))
	o.resizable = false
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
	o.isSPHallOfFame = isSP == true
	o.columns = buildColumns({}, o.isSPHallOfFame)
	o.hasSavedPosition = hasSavedPosition == true
	o.layoutInitialized = false
	return o
end

function XPR_UI_Leaderboard.Panel:resizeForContent(rows)
	self.columns = buildColumns(rows, self.isSPHallOfFame)
	local comboNeeded = longestCategoryDisplayW()
	local targetW = math.max(PANEL_W, self.columns.requiredListW + PAD * 2, PAD * 2 + comboNeeded * 2)
	local screenW = getCore():getScreenWidth()
	targetW = math.min(targetW, math.max(PANEL_W, screenW - S(40)))
	self:setWidth(targetW)
	if not self.layoutInitialized and not self.hasSavedPosition then
		self:setX(math.floor((screenW - targetW) / 2))
	else
		self:setX(math.max(0, math.min(self:getX(), screenW - targetW)))
	end
	self.layoutInitialized = true
	self:recalcSize()

	if self.combo then
		local comboW = math.max(math.floor((targetW - PAD * 2) * 0.5), comboNeeded)
		self.combo:setWidth(comboW)
		self.combo:setX(math.floor((targetW - comboW) / 2))
	end
	if self.listBox then
		self.listBox:setWidth(targetW - PAD * 2)
	end
	if self.playerListBox then
		self.playerListBox:setWidth(targetW - PAD * 2)
	end
end

function XPR_UI_Leaderboard.Panel:initialise()
	ISCollapsableWindow.initialise(self)
	self:setTitle(LEADERBOARD_TITLE(self.isSPHallOfFame))
end

function XPR_UI_Leaderboard.Panel:close()
	savePosition(self:getX(), self:getY())
	ISCollapsableWindow.close(self)
	XPR_UI_Leaderboard.instance = nil
	if XPR_UI_Sidebar and XPR_UI_Sidebar.setActive then
		XPR_UI_Sidebar.setActive(false)
	end
end

function XPR_UI_Leaderboard.Panel:onMouseUp(x, y)
	ISCollapsableWindow.onMouseUp(self, x, y)
	savePosition(self:getX(), self:getY())
end

function XPR_UI_Leaderboard.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)

	local y = self:titleBarHeight() + PAD

	local comboW = math.max(math.floor((self.width - PAD * 2) * 0.5), longestCategoryDisplayW())
	local comboX = math.floor((self.width - comboW) / 2)
	self.combo = ISComboBox:new(comboX, y, comboW, ROW_H, self, XPR_UI_Leaderboard.Panel.onComboChanged)
	self.combo:initialise()
	self.combo:instantiate()
	local categories = (XPR_Categories and XPR_Categories.getLeaderboardCategories
		and XPR_Categories.getLeaderboardCategories()) or { { key = "Overall", display = "Overall" } }
	for _, cat in ipairs(categories) do
		self.combo:addOptionWithData(cat.display, cat.key)
	end
	self.combo.selected = 1
	self:addChild(self.combo)
	y = y + ROW_H + PAD

	self.headerY = y
	local headerBottomY = y + ROW_H
	self.headerBottomY = headerBottomY
	y = headerBottomY + S(4)

	self.statusText = getText("IGUI_XPR_Leaderboard_Loading")

	self.listBox = ISScrollingListBox:new(PAD, y, self.width - PAD * 2,
		LIST_ROW_H * MAX_ROWS)
	self.listBox:initialise()
	self.listBox:instantiate()
	self.listBox.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.listBox.itemheight = LIST_ROW_H
	self.listBox.selected = 0
	self.listBox.drawBorder = true
	self:addChild(self.listBox)

	self.listBox.doDrawItem = function(listSelf, rowY, item, alt)
		return drawLeaderboardItem(self, listSelf, rowY, item)
	end

	local playerY = y + LIST_ROW_H * MAX_ROWS + S(12)
	self.playerListBox = ISScrollingListBox:new(PAD, playerY,
		self.width - PAD * 2, LIST_ROW_H)
	self.playerListBox:initialise()
	self.playerListBox:instantiate()
	self.playerListBox.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.playerListBox.itemheight = LIST_ROW_H
	self.playerListBox.selected = 0
	self.playerListBox.drawBorder = true
	self.playerListBox:setVisible(false)
	self:addChild(self.playerListBox)
	self.playerListBox.doDrawItem = function(listSelf, rowY, item, alt)
		return drawLeaderboardItem(self, listSelf, rowY, item)
	end

	self.compactHeight = y + LIST_ROW_H * MAX_ROWS + PAD
	self.expandedHeight = playerY + LIST_ROW_H + PAD
	self:setHeight(self.compactHeight)
	if not self.hasSavedPosition then
		self:setY(math.floor((getCore():getScreenHeight() - self.compactHeight) / 2))
	else
		self:setY(math.max(0, math.min(self:getY(),
			getCore():getScreenHeight() - self.compactHeight)))
	end
	self:recalcSize()

	self:requestCurrentCategory()
end

function XPR_UI_Leaderboard.Panel:prerender()
	ISCollapsableWindow.prerender(self)

	local tm = getTextManager()
	local listW = self.listBox:getWidth()
	local columns = self.columns
	local textY = self.headerY + math.floor((ROW_H - FONT_H) / 2)

	drawTextCentered(self, tm, getText("IGUI_XPR_Leaderboard_ColPos"), PAD + columns.posCenter, textY, COL_DIM)
	drawTextCentered(self, tm, getText("IGUI_XPR_Leaderboard_ColRank"), PAD + columns.rankCenter, textY, COL_DIM)
	local identityHeader = getText(self.isSPHallOfFame and "IGUI_XPR_Leaderboard_ColCharacter" or "IGUI_XPR_Leaderboard_ColPlayer")
	drawTextCentered(self, tm, identityHeader, PAD + columns.playerCenter, textY, COL_DIM)
	drawTextCentered(self, tm, getText("IGUI_XPR_Leaderboard_ColXp"), PAD + columns.xpCenter, textY, COL_DIM)

	self:drawRect(PAD, self.headerBottomY - 1, listW, 1, 1,
		COL_SEPARATOR.r, COL_SEPARATOR.g, COL_SEPARATOR.b)

	if #self.listBox.items == 0 and self.statusText then
		local textW = tm:MeasureStringX(FONT, self.statusText)
		local x = math.floor((self.width - textW) / 2)
		local y = self.headerBottomY + math.floor((self.listBox:getHeight()) / 2)
		self:drawText(self.statusText, x, y, COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT)
	end
end

function XPR_UI_Leaderboard.Panel:currentCategory()
	if not self.combo or self.combo.selected == 0 then return "Overall" end
	return self.combo:getSelectedData() or "Overall"
end

local function allRowsForSizing()
	local rows = {}
	if dataCache then
		for _, entry in pairs(dataCache.categories) do
			for _, row in ipairs(entry.rows) do rows[#rows + 1] = row end
			if entry.playerRow then rows[#rows + 1] = entry.playerRow end
		end
	end
	return rows
end

function XPR_UI_Leaderboard.Panel:renderCurrentCategory()
	if not dataCache then return end
	local entry = dataCache.categories[self:currentCategory()]
	if not entry then return end

	self.isSPHallOfFame = dataCache.isSP == true
	self:setTitle(LEADERBOARD_TITLE(self.isSPHallOfFame))
	self:resizeForContent(allRowsForSizing())
	self.listBox:clear()
	for i, row in ipairs(entry.rows or {}) do
		if i > MAX_ROWS then break end
		self.listBox:addItem(row.username, {
			pos = i,
			username = row.username,
			rank = row.rank,
			xp = row.xp,
		})
	end
	self.playerListBox:clear()
	if entry.playerRow then
		self.playerListBox:addItem(entry.playerRow.username, entry.playerRow)
		self.playerListBox:setVisible(true)
		self:setHeight(self.expandedHeight)
	else
		self.playerListBox:setVisible(false)
		self:setHeight(self.compactHeight)
	end
	self:setY(math.max(0, math.min(self:getY(), getCore():getScreenHeight() - self:getHeight())))
	self:recalcSize()

	self.statusText = (#(entry.rows or {}) == 0) and getText("IGUI_XPR_Leaderboard_NoData") or nil
end

function XPR_UI_Leaderboard.Panel:requestCurrentCategory()
	if ensureFreshData() then
		self:renderCurrentCategory()
		return
	end
	self.statusText = getText("IGUI_XPR_Leaderboard_Loading")
	self.listBox:clear()
	self.playerListBox:clear()
	self.playerListBox:setVisible(false)
end

function XPR_UI_Leaderboard.Panel:update()
	ISCollapsableWindow.update(self)
	retryPendingIfDue()
end

function XPR_UI_Leaderboard.Panel:onComboChanged()
	if dataCache then
		self:renderCurrentCategory()
	else
		self:requestCurrentCategory()
	end
end

function XPR_UI_Leaderboard.open()
	if XPR_UI_Leaderboard.instance then
		XPR_UI_Leaderboard.instance:setVisible(true)
		XPR_UI_Leaderboard.instance:addToUIManager()
		XPR_UI_Leaderboard.instance:requestCurrentCategory()
	else
		local screenW = getCore():getScreenWidth()
		local screenH = getCore():getScreenHeight()
		local savedX, savedY = loadPosition()
		local hasSavedPosition = savedX ~= nil and savedY ~= nil
		local x = savedX or (screenW / 2 - PANEL_W / 2)
		local y = savedY or (screenH / 2 - PANEL_H / 2)
		x = math.max(0, math.min(x, screenW - PANEL_W))
		y = math.max(0, y)
		local panel = XPR_UI_Leaderboard.Panel:new(x, y, hasSavedPosition)
		panel:initialise()
		panel:addToUIManager()
		XPR_UI_Leaderboard.instance = panel
	end

	if XPR_UI_Sidebar and XPR_UI_Sidebar.setActive then
		XPR_UI_Sidebar.setActive(true)
	end
end

function XPR_UI_Leaderboard.close()
	if XPR_UI_Leaderboard.instance then
		XPR_UI_Leaderboard.instance:close()
	end
end

function XPR_UI_Leaderboard.onData(categoriesData, isSP)
	if not categoriesData then return end
	dataCache = { categories = categoriesData, isSP = isSP == true }
	cacheFetchedAtMs = getTimestampMs and getTimestampMs() or 0
	if XPR_UI_Leaderboard.instance then
		XPR_UI_Leaderboard.instance:renderCurrentCategory()
	end
end

return XPR_UI_Leaderboard
