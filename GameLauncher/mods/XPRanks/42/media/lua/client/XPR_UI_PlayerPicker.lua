if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
require "XPR_UI_Scale"
require "XPR_UI_Theme"

XPR_UI_PlayerPicker = {}
XPR_UI_PlayerPicker.instance = nil
XPR_UI_PlayerPicker.cachedPlayers = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local ROW_H = fontHgt + S(10)
local WIN_W = math.max(S(400), fontHgt * 22) + S(150)
local WIN_H = math.max(S(400), fontHgt * 22) + S(30) + BTN_H + S(8)
local PLAYER_DATA_TIMEOUT_TICKS = 90
local MAX_PLAYER_DATA_REQUESTS = 3

local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_ROW = { r = 0.05, g = 0.05, b = 0.05 }
local COL_ROW_ALT = { r = 0.11, g = 0.11, b = 0.11 }
local CHECK_SIZE = S(16)

local function rowData(entry)
	return "Rank " .. tostring(entry.rank) .. "  |  " .. tostring(entry.totalXp) .. " XP"
end

local MODE_CONFIG = {
	setRank = {
		title = "IGUI_XPR_PlayerPicker_SetRankTitle",
		instruction = "IGUI_XPR_PlayerPicker_SetRankInstr",
		applyBtnLabel = "IGUI_XPR_PlayerPicker_SetRankAction",
		confirmText = "IGUI_XPR_PlayerPicker_SetRankConfirm",
		command = "setRank",
		hasEntry = true,
		entryLabel = "IGUI_XPR_PlayerPicker_RankLabel",
		entryDefault = "1",
	},
	addXp = {
		title = "IGUI_XPR_PlayerPicker_AddXpTitle",
		instruction = "IGUI_XPR_PlayerPicker_AddXpInstr",
		applyBtnLabel = "IGUI_XPR_PlayerPicker_AddXpAction",
		confirmText = "IGUI_XPR_PlayerPicker_AddXpConfirm",
		command = "addXp",
		hasEntry = true,
		entryLabel = "IGUI_XPR_PlayerPicker_AmountLabel",
		entryDefault = "0",
	},
	addRewardBox = {
		title = "IGUI_XPR_PlayerPicker_AddRewardBoxTitle",
		instruction = "IGUI_XPR_PlayerPicker_AddRewardBoxInstr",
		applyBtnLabel = "IGUI_XPR_PlayerPicker_AddRewardBoxAction",
		confirmText = "IGUI_XPR_PlayerPicker_AddRewardBoxConfirm",
		command = "addRewardBox",
		hasEntry = true,
		singleTarget = true,
		entryLabel = "IGUI_XPR_PlayerPicker_RewardBoxRankLabel",
		entryDefault = "1",
	},
	resetRank = {
		title = "IGUI_XPR_PlayerPicker_ResetTitle",
		instruction = "IGUI_XPR_PlayerPicker_ResetInstr",
		applyBtnLabel = "IGUI_XPR_PlayerPicker_ResetAction",
		confirmText = "IGUI_XPR_PlayerPicker_ResetConfirm",
		command = "resetRank",
		hasEntry = false,
	},
}

local function cfgText(key, value)
	if value == nil then value = (XPR_Config and XPR_Config.MAX_XP_PER_AWARD) or 100000 end
	return getText(key, value)
end

local function getClampedXpAmount(entry)
	local amount = (entry and tonumber(entry:getText())) or 0
	if amount <= 0 then return nil end
	amount = math.floor(amount)
	local maximum = (XPR_Config and XPR_Config.MAX_XP_PER_AWARD) or 100000
	if amount > maximum then
		amount = maximum
		if entry then entry:setText(tostring(amount)) end
	end
	return amount
end

local function getClampedRewardBoxRank(entry)
	local rank = (entry and tonumber(entry:getText())) or 0
	if rank <= 0 then return nil end
	rank = math.floor(rank)
	local maximum = (XPR_RankCurve and XPR_RankCurve.MAX_RANK) or 999
	if rank > maximum then
		rank = maximum
		if entry then entry:setText(tostring(rank)) end
	end
	return rank
end

local function playerDataErrorText(code)
	if code == "rejectedSender" then
		local key = "IGUI_XPR_Toast_DebugRewardBoxRejected"
		local text = getText(key)
		if text and text ~= "" and text ~= key then return text end
		return "Player list request rejected by the server. Check the Debug Tools configuration."
	elseif code == "cooldown" then
		return "Player list request was rate-limited. Try again."
	elseif code == "notReady" or code == "timeout" then
		return "Player list is not available yet. Check the server connection and try again."
	end
	return "Unable to load Players from the server."
end

XPR_UI_PlayerPicker.Panel = ISCollapsableWindow:derive("XPR_UI_PlayerPicker_Panel")

function XPR_UI_PlayerPicker.Panel:new(x, y, mode)
	local modeUsed = mode or "resetRank"

	local cfg = MODE_CONFIG[modeUsed]
	local btnPad = S(12)
	local halfFloor = math.floor((WIN_W - PAD * 2 - S(8)) / 2)
	local selectW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_SelectAll"), halfFloor, btnPad)
	local unselectW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_UnselectAll"), halfFloor, btnPad)
	local entryRowW = 0
	local entryLabelW = 0
	if cfg.hasEntry then
		entryLabelW = XPR_UI_Scale.measureText(FONT, cfgText(cfg.entryLabel))
		entryRowW = entryLabelW + S(8) + S(100)
	end
	local applyW = math.max(S(150), XPR_UI_Scale.measureText(FONT, cfgText(cfg.applyBtnLabel)) + S(20))
	local closeW = XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Common_Close")) + btnPad
	local titleW = XPR_UI_Scale.measureText(FONT, cfgText(cfg.title)) + BTN_H + PAD * 2
	local panelW = math.max(WIN_W,
		PAD * 2 + selectW + S(8) + unselectW,
		PAD * 2 + entryRowW,
		PAD * 2 + applyW,
		PAD * 2 + closeW,
		titleW)

	local o = ISCollapsableWindow.new(self, x, y, panelW, WIN_H)
	o.moveWithMouse = true
	o.resizable = false
	o.mode = modeUsed
	o.allPlayerEntries = {}
	o.playerEntries = {}
	o.lastSearchText = ""
	o.selectedCount = 0
	o.requestTicks = 0
	o.requestAttempts = 0
	o.requestErrorCode = nil
	o._panelW = panelW
	o._selectW = selectW
	o._unselectW = unselectW
	o._entryLabelW = entryLabelW
	o._applyW = applyW
	return o
end

function XPR_UI_PlayerPicker.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)

	local cfg = MODE_CONFIG[self.mode]
	local titleH = fontHgt + S(1)
	local y = titleH + PAD

	local instructionValue = nil
	if self.mode == "addRewardBox" then
		instructionValue = (XPR_RankCurve and XPR_RankCurve.MAX_RANK) or 999
	end
	local instrLines = XPR_UI_Scale.wrapLines(FONT, cfgText(cfg.instruction, instructionValue), self._panelW - PAD * 3)
	for i = 1, #instrLines do
		local lbl = ISLabel:new(PAD, y, S(20), instrLines[i],
			COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + fontHgt
	end
	y = y + S(5)

	self.searchEntry = ISTextEntryBox:new("", PAD, y, self._panelW - PAD * 2, fontHgt + S(5))
	self.searchEntry:initialise()
	self.searchEntry:instantiate()
	self.searchEntry:setPlaceholderText(getText("IGUI_XPR_PlayerPicker_SearchPlaceholder"))
	self:addChild(self.searchEntry)
	y = y + S(30)

	local halfW = math.floor((self._panelW - PAD * 2 - S(8)) / 2)
	self.btnSelectAllVisible = ISButton:new(PAD, y, self._selectW, BTN_H,
		getText("IGUI_XPR_Common_SelectAll"), self, XPR_UI_PlayerPicker.Panel.onSelectAllVisible)
	self.btnSelectAllVisible:initialise()
	self.btnSelectAllVisible:instantiate()
	self:addChild(self.btnSelectAllVisible)

	self.btnUnselectAllVisible = ISButton:new(PAD + self._selectW + S(8), y, self._unselectW, BTN_H,
		getText("IGUI_XPR_Common_UnselectAll"), self, XPR_UI_PlayerPicker.Panel.onUnselectAllVisible)
	self.btnUnselectAllVisible:initialise()
	self.btnUnselectAllVisible:instantiate()
	self:addChild(self.btnUnselectAllVisible)
	if cfg.singleTarget then
		self.btnSelectAllVisible.enable = false
		self.btnUnselectAllVisible.enable = false
	end
	y = y + BTN_H + S(8)

	local listH = WIN_H - titleH - PAD - S(24) - S(30) - (BTN_H + S(8)) - BTN_H - PAD - S(30)
	if cfg.hasEntry then listH = listH - S(30) end
	if listH < S(80) then listH = S(80) end
	self.playerList = ISScrollingListBox:new(PAD, y, self._panelW - PAD * 2, listH)
	self.playerList:initialise()
	self.playerList:instantiate()
	self.playerList.itemheight = ROW_H
	self.playerList.font = FONT
	self.playerList.doDrawItem = XPR_UI_PlayerPicker.Panel.drawPlayerItem
	self.playerList:setOnMouseDownFunction(self, XPR_UI_PlayerPicker.Panel.onPlayerClicked)
	self.playerList.drawBorder = true
	self:addChild(self.playerList)
	y = y + listH + S(8)

	self:requestAndBuild()

	if cfg.hasEntry then
		self.lblValue = ISLabel:new(PAD, y, S(20), cfgText(cfg.entryLabel),
			COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
		self.lblValue:initialise()
		self:addChild(self.lblValue)

		self.valueEntry = ISTextEntryBox:new(cfg.entryDefault, PAD + self._entryLabelW + S(8), y, S(100), fontHgt + S(5))
		self.valueEntry:initialise()
		self.valueEntry:instantiate()
		self.valueEntry:setOnlyNumbers(true)
		self:addChild(self.valueEntry)
		y = y + S(30)
	end

	self.lblSelected = ISLabel:new(PAD, y, S(20), getText("IGUI_XPR_PlayerPicker_SelectedCount", 0),
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	self.lblSelected:initialise()
	self:addChild(self.lblSelected)
	y = y + S(24)

	local applyLabel = cfgText(cfg.applyBtnLabel)
	local applyW = math.max(S(150), getTextManager():MeasureStringX(FONT, applyLabel) + S(20))
	self.btnApply = ISButton:new(math.floor((self._panelW - applyW) / 2), y, applyW, BTN_H,
		applyLabel, self, XPR_UI_PlayerPicker.Panel.onApply)
	self.btnApply:initialise()
	self.btnApply:instantiate()
	self.btnApply.enable = false
	self:addChild(self.btnApply)
	y = y + BTN_H + S(8)

	self.btnClose = ISButton:new(PAD, y, self._panelW - PAD * 2, BTN_H,
		getText("IGUI_XPR_Common_Close"), self, XPR_UI_PlayerPicker.Panel.onClose)
	self.btnClose:initialise()
	self.btnClose:instantiate()
	self:addChild(self.btnClose)

	self:setHeight(y + BTN_H + PAD)
end

function XPR_UI_PlayerPicker.Panel:initialise()
	ISCollapsableWindow.initialise(self)
end

function XPR_UI_PlayerPicker.Panel:prerender()
	ISCollapsableWindow.prerender(self)
	local titleH = fontHgt + S(1)
	self:drawRect(0, titleH, self.width, S(2), 1, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)

	if XPR_UI_PlayerPicker.cachedPlayers == nil and not self.requestErrorCode
			and self.requestTicks > 0 then
		self.requestTicks = self.requestTicks - 1
		if self.requestTicks <= 0 then
			if self.requestAttempts < MAX_PLAYER_DATA_REQUESTS then
				self:requestAndBuild(false)
			else
				XPR_UI_PlayerPicker.onPlayersDataError("timeout")
			end
		end
	end

	if self.searchEntry then
		local currentText = self.searchEntry:getText() or ""
		if currentText ~= (self.lastSearchText or "") then
			self.lastSearchText = currentText
			self:filterPlayers()
		end
	end
end

function XPR_UI_PlayerPicker.Panel:requestAndBuild(resetAttempts)
	if resetAttempts ~= false then self.requestAttempts = 0 end
	self.requestAttempts = self.requestAttempts + 1
	self.requestTicks = PLAYER_DATA_TIMEOUT_TICKS
	self.requestErrorCode = nil
	local player = getSpecificPlayer(0)
	if player then
		local command = (self.mode == "addRewardBox" and "getDebugPlayersData") or "getPlayersData"
		XPR_dprint("[XPR] PlayerPicker request: mode=" .. tostring(self.mode)
			.. " attempt=" .. tostring(self.requestAttempts)
			.. " command=" .. command)
		sendClientCommand(player, "XPRanks", command, {})
	end
	if XPR_Env and XPR_Env.isTrueSinglePlayer() and XPR_RankData then
		XPR_UI_PlayerPicker.cachedPlayers = XPR_RankData.getAllPlayers()
	end
	self:buildPlayerList()
end

function XPR_UI_PlayerPicker.Panel:buildPlayerList()
	self.allPlayerEntries = {}

	if XPR_UI_PlayerPicker.cachedPlayers == nil then
		self.playerEntries = {}
		self.playerList:clear()
		self.playerList:addItem("Loading players...", { empty = true })
		self:updateApplyState()
		return
	end
	if self.requestErrorCode then
		self.playerEntries = {}
		self.playerList:clear()
		self.playerList:addItem(playerDataErrorText(self.requestErrorCode), { empty = true, error = true })
		self:updateApplyState()
		return
	end

	local onlineNames = {}
	if XPR_Env then
		for _, p in ipairs(XPR_Env.players()) do
			if p then onlineNames[p:getUsername()] = true end
		end
	end

	local players = {}
	for _, entry in ipairs(XPR_UI_PlayerPicker.cachedPlayers) do
		players[#players + 1] = {
			username = entry.username,
			rank = entry.rank,
			totalXp = entry.totalXp,
			online = onlineNames[entry.username] == true,
			checked = false,
		}
	end
	table.sort(players, function(a, b) return a.username < b.username end)
	self.allPlayerEntries = players

	self:filterPlayers()
end

function XPR_UI_PlayerPicker.Panel:filterPlayers()
	self.playerList:clear()
	self.playerEntries = {}

	local searchText = string.lower(self.lastSearchText or "")
	for _, entry in ipairs(self.allPlayerEntries) do
		if searchText == "" or string.find(string.lower(entry.username), searchText, 1, true) then
			local suffix = entry.online and "" or "  (Offline)"
			self.playerList:addItem(entry.username .. " - " .. rowData(entry) .. suffix, entry)
			self.playerEntries[#self.playerEntries + 1] = entry
		end
	end

	if #self.playerEntries == 0 then
		self.playerList:addItem(getText("IGUI_XPR_PlayerPicker_NoneFound"), { empty = true })
	end
	self:updateApplyState()
end

function XPR_UI_PlayerPicker.Panel:drawPlayerItem(y, item, alt)
	local data = item.item
	local w = self:getWidth()
	if data.empty then
		self:drawRect(0, y, w, ROW_H, 0.15, 0.12, 0.12, 0.12)
		local textY = y + math.floor((ROW_H - fontHgt) / 2)
		self:drawText("  " .. item.text, S(8), textY, 0.5, 0.5, 0.5, 0.6, FONT)
		return y + ROW_H
	end

	if alt then
		self:drawRect(0, y, w, ROW_H, 1, COL_ROW_ALT.r, COL_ROW_ALT.g, COL_ROW_ALT.b)
	else
		self:drawRect(0, y, w, ROW_H, 1, COL_ROW.r, COL_ROW.g, COL_ROW.b)
	end

	local checkX = PAD
	local checkY = y + math.floor((ROW_H - CHECK_SIZE) / 2)
	self:drawRectBorder(checkX, checkY, CHECK_SIZE, CHECK_SIZE, 0.6, 0.6, 0.6, 0.6)
	if data.checked then
		self:drawRect(checkX + S(2), checkY + S(2), CHECK_SIZE - S(4), CHECK_SIZE - S(4), 1,
			COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
	end

	local textY = y + math.floor((ROW_H - fontHgt) / 2)
	self:drawText(item.text, checkX + CHECK_SIZE + PAD, textY,
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 0.8, FONT)

	return y + ROW_H
end

function XPR_UI_PlayerPicker.Panel.onPlayerClicked(target, data)
	if not data or data.empty then return end
	local checked = not data.checked
	if checked and target.mode == "addRewardBox" then
		for _, entry in ipairs(target.allPlayerEntries) do entry.checked = false end
	end
	data.checked = checked
	target:updateApplyState()
end

function XPR_UI_PlayerPicker.Panel:updateApplyState()
	local count = 0
	for _, entry in ipairs(self.allPlayerEntries) do
		if entry.checked then count = count + 1 end
	end
	self.selectedCount = count
	if self.lblSelected then
		self.lblSelected:setName(getText("IGUI_XPR_PlayerPicker_SelectedCount", count))
	end
	if self.btnApply then
		self.btnApply.enable = count > 0
	end
end

function XPR_UI_PlayerPicker.Panel:onSelectAllVisible()
	for _, entry in ipairs(self.playerEntries) do entry.checked = true end
	self:updateApplyState()
end

function XPR_UI_PlayerPicker.Panel:onUnselectAllVisible()
	for _, entry in ipairs(self.playerEntries) do entry.checked = false end
	self:updateApplyState()
end

function XPR_UI_PlayerPicker.Panel:confirmThen(bodyText, fn)
	self._pendingConfirm = fn
	bodyText = XPR_UI_Scale.wrapModalText(UIFont.Small, bodyText, S(320))
	local w, h = S(350), S(150)
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local modal = ISModalDialog:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2),
		w, h, bodyText, true, self, XPR_UI_PlayerPicker.Panel.onConfirmResult)
	modal:initialise()
	modal:addToUIManager()
end

function XPR_UI_PlayerPicker.Panel.onConfirmResult(self, button)
	local fn = self._pendingConfirm
	self._pendingConfirm = nil
	if button and button.internal == "YES" and fn then fn(self) end
end

function XPR_UI_PlayerPicker.Panel:onApply()
	if not self.selectedCount or self.selectedCount <= 0 then return end
	local cfg = MODE_CONFIG[self.mode]
	self:confirmThen(getText(cfg.confirmText, self.selectedCount), XPR_UI_PlayerPicker.Panel.onApply_do)
end

function XPR_UI_PlayerPicker.Panel:onApply_do()
	local player = getSpecificPlayer(0)
	if not player then return end

	local targetUsernames = {}
	for _, entry in ipairs(self.allPlayerEntries) do
		if entry.checked then targetUsernames[#targetUsernames + 1] = entry.username end
	end
	if #targetUsernames == 0 then return end

	local cfg = MODE_CONFIG[self.mode]
	local args = { targetUsernames = targetUsernames }
	if self.mode == "addRewardBox" then
		if #targetUsernames ~= 1 then return end
		local rank = getClampedRewardBoxRank(self.valueEntry)
		if not rank then return end
		args = { targetUsername = targetUsernames[1], rank = rank }
	elseif self.mode == "setRank" then
		args.rank = (self.valueEntry and tonumber(self.valueEntry:getText())) or 1
	elseif self.mode == "addXp" then
		local amount = getClampedXpAmount(self.valueEntry)
		if not amount then return end
		args.amount = amount
	end
	sendClientCommand(player, "XPRanks", cfg.command, args)

	XPR_dprint("[XPR] PlayerPicker: " .. self.mode .. " applied to " .. #targetUsernames .. " selected players")

	XPR_UI_PlayerPicker.cachedPlayers = nil
	self:requestAndBuild()
end

function XPR_UI_PlayerPicker.Panel:onClose()
	self:setVisible(false)
	self:removeFromUIManager()
	XPR_UI_PlayerPicker.instance = nil
end

function XPR_UI_PlayerPicker.onPlayersData(players)
	XPR_UI_PlayerPicker.cachedPlayers = players or {}
	if XPR_UI_PlayerPicker.instance then
		XPR_UI_PlayerPicker.instance.requestTicks = 0
		XPR_UI_PlayerPicker.instance.requestErrorCode = nil
		XPR_UI_PlayerPicker.instance:buildPlayerList()
	end
end

function XPR_UI_PlayerPicker.onPlayersDataError(code)
	XPR_UI_PlayerPicker.cachedPlayers = {}
	if XPR_UI_PlayerPicker.instance then
		XPR_UI_PlayerPicker.instance.requestTicks = 0
		XPR_UI_PlayerPicker.instance.requestErrorCode = code or "unknown"
		XPR_UI_PlayerPicker.instance:buildPlayerList()
	end
end

function XPR_UI_PlayerPicker.open(mode)
	if XPR_UI_PlayerPicker.instance then
		if XPR_UI_PlayerPicker.instance.mode == mode then
			XPR_UI_PlayerPicker.instance:setVisible(true)
			return
		else
			XPR_UI_PlayerPicker.instance:onClose()
		end
	end

	XPR_UI_PlayerPicker.cachedPlayers = nil

	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local x = math.floor((screenW - WIN_W) / 2)
	local y = math.floor((screenH - WIN_H) / 2)

	local cfg = MODE_CONFIG[mode] or MODE_CONFIG.resetRank
	local win = XPR_UI_PlayerPicker.Panel:new(x, y, mode)
	win:setX(math.floor((screenW - win:getWidth()) / 2))
	XPR_UI_PlayerPicker.instance = win
	win:initialise()
	win:setY(math.floor((screenH - win:getHeight()) / 2))
	win:addToUIManager()
	win:setTitle(getText("IGUI_XPR_PlayerPicker_WinTitle", cfgText(cfg.title)))
end

function XPR_UI_PlayerPicker.close()
	if XPR_UI_PlayerPicker.instance then
		XPR_UI_PlayerPicker.instance:onClose()
	end
end

return XPR_UI_PlayerPicker
