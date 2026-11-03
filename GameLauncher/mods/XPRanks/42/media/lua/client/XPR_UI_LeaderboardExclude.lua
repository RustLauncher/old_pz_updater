if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISModalDialog"
require "XPR_UI_Scale"

XPR_UI_LeaderboardExclude = XPR_UI_LeaderboardExclude or {}
XPR_UI_LeaderboardExclude.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local FONT_H = XPR_UI_Scale.fontHgt
local PAD = S(10)
local BTN_H = FONT_H + S(13)
local ROW_H = FONT_H + S(10)
local PANEL_W = S(520)
local PANEL_H = S(430)
local CHECK_SIZE = S(16)
local COL_EXCLUDED = { r = 0.35, g = 0.02, b = 0.02, a = 0.75 }

local function computePanelW()
	local comboTexts = { getText("IGUI_XPR_LeaderboardExclude_AllOption") }
	local cats = XPR_Categories and XPR_Categories.getLeaderboardCategories
		and XPR_Categories.getLeaderboardCategories()
	for _, cat in ipairs(cats or {}) do
		comboTexts[#comboTexts + 1] = cat.display
	end
	local comboNeeded = XPR_UI_Scale.longestText(FONT, comboTexts) + S(30)
	local buttonNeeded = math.max(
			XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_LeaderboardExclude_Button")),
			XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_LeaderboardInclude_Button")),
			XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Common_Close"))) + S(24)
	local titleNeeded = XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_LeaderboardExclude_Title")) + BTN_H + PAD * 2
	return math.max(PANEL_W, PAD * 2 + comboNeeded, PAD * 2 + buttonNeeded, titleNeeded)
end

XPR_UI_LeaderboardExclude.Panel = ISCollapsableWindow:derive("XPR_UI_LeaderboardExclude_Panel")

function XPR_UI_LeaderboardExclude.Panel:new(x, y)
	local panelW = computePanelW()
	local instrLines = XPR_UI_Scale.wrapLines(FONT,
		getText("IGUI_XPR_LeaderboardExclude_Instruction"), panelW - PAD * 2)
	local extraLines = math.max(0, #instrLines - 1)
	local panelH = PANEL_H + extraLines * FONT_H

	local o = ISCollapsableWindow.new(self, x, y, panelW, panelH)
	o.moveWithMouse = true
	o.resizable = false
	o.selectedEntry = nil
	return o
end

function XPR_UI_LeaderboardExclude.Panel:initialise()
	ISCollapsableWindow.initialise(self)
	self:setTitle(getText("IGUI_XPR_LeaderboardExclude_Title") or "Exclude from Leaderboard")
end

function XPR_UI_LeaderboardExclude.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)
	local y = self:titleBarHeight() + PAD

	local instrLines = XPR_UI_Scale.wrapLines(FONT,
		getText("IGUI_XPR_LeaderboardExclude_Instruction"), self:getWidth() - PAD * 2)
	for _, line in ipairs(instrLines) do
		local lbl = ISLabel:new(PAD, y, FONT_H, line, 0.9, 0.9, 0.9, 1, FONT, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_H
	end
	y = y + PAD

	self.categoryCombo = ISComboBox:new(PAD, y, self.width - PAD * 2, BTN_H,
		self, XPR_UI_LeaderboardExclude.Panel.onCategoryChanged)
	self.categoryCombo:initialise()
	self.categoryCombo:instantiate()
	self.categoryCombo:addOptionWithData(
		getText("IGUI_XPR_LeaderboardExclude_AllOption"), "__ALL__")
	local categories = XPR_Categories.getLeaderboardCategories()
	for _, category in ipairs(categories) do
		self.categoryCombo:addOptionWithData(category.display, category.key)
	end
	self.categoryCombo.selected = 1
	self:addChild(self.categoryCombo)
	y = y + BTN_H + PAD

	local listH = self:getHeight() - y - BTN_H * 2 - PAD * 3
	self.entryList = ISScrollingListBox:new(PAD, y, self.width - PAD * 2, listH)
	self.entryList:initialise()
	self.entryList:instantiate()
	self.entryList.itemheight = ROW_H
	self.entryList.font = FONT
	self.entryList.selected = 0
	self.entryList:setOnMouseDownFunction(self, XPR_UI_LeaderboardExclude.Panel.onEntrySelected)
	self.entryList.drawBorder = true
	self.entryList.doDrawItem = function(listSelf, rowY, item, alt)
		local data = item.item
		if data and data.excluded then
			listSelf:drawRect(0, rowY, listSelf:getWidth(), listSelf.itemheight,
				COL_EXCLUDED.a, COL_EXCLUDED.r, COL_EXCLUDED.g, COL_EXCLUDED.b)
		end
		local textX = S(6)
		if data and not data.empty then
			local checkX = PAD
			local checkY = rowY + math.floor((listSelf.itemheight - CHECK_SIZE) / 2)
			listSelf:drawRectBorder(checkX, checkY, CHECK_SIZE, CHECK_SIZE,
				0.6, 0.6, 0.6, 0.6)
			if listSelf.selected == item.index then
				listSelf:drawRect(checkX + S(2), checkY + S(2),
					CHECK_SIZE - S(4), CHECK_SIZE - S(4), 1, 1, 1, 1)
			end
			textX = checkX + CHECK_SIZE + PAD
		end
		listSelf:drawText(item.text or item.name or "", textX,
			rowY + math.floor((listSelf.itemheight - FONT_H) / 2), 1, 1, 1, 1, FONT)
		return rowY + listSelf.itemheight
	end
	self:addChild(self.entryList)
	y = y + listH + PAD

	self.excludeBtn = ISButton:new(PAD, y, self.width - PAD * 2, BTN_H,
		getText("IGUI_XPR_LeaderboardExclude_Button"), self,
		XPR_UI_LeaderboardExclude.Panel.onExclude)
	self.excludeBtn:initialise()
	self.excludeBtn:instantiate()
	self.excludeBtn.enable = false
	self:addChild(self.excludeBtn)
	y = y + BTN_H + PAD

	self.closeBtn = ISButton:new(PAD, y, self.width - PAD * 2, BTN_H,
		getText("IGUI_XPR_Common_Close"), self, XPR_UI_LeaderboardExclude.Panel.close)
	self.closeBtn:initialise()
	self.closeBtn:instantiate()
	self:addChild(self.closeBtn)

	self:renderCurrentCategory()
	self:requestEntries()
end

function XPR_UI_LeaderboardExclude.Panel:currentCategory()
	return self.categoryCombo:getSelectedData() or "Overall"
end

function XPR_UI_LeaderboardExclude.Panel:requestEntries()
	local player = getSpecificPlayer(0)
	if player then
		sendClientCommand(player, "XPRanks", "requestLeaderboardCandidates", {})
	end
end

function XPR_UI_LeaderboardExclude.Panel:renderCurrentCategory()
	if not self.entryList then return end
	self.selectedEntry = nil
	self.entryList.selected = 0
	if self.excludeBtn then
		self.excludeBtn.enable = false
		self.excludeBtn:setTitle(getText("IGUI_XPR_LeaderboardExclude_Button"))
	end
	self.entryList:clear()
	if not self.categoriesCache then
		self.entryList:addItem("Loading...", { empty = true })
		return
	end
	local rows = self.categoriesCache[self:currentCategory()]
	for _, row in ipairs(rows or {}) do
		local text = "#" .. tostring(row.pos or "-") .. "  " .. tostring(row.username)
			.. "  |  Rank " .. tostring(row.rank) .. "  |  " .. tostring(row.xp) .. " XP"
		self.entryList:addItem(text, row)
	end
	if #(rows or {}) == 0 then
		self.entryList:addItem(getText("IGUI_XPR_LeaderboardExclude_None"), { empty = true })
	end
end

function XPR_UI_LeaderboardExclude.Panel:onCategoryChanged()
	self:renderCurrentCategory()
end

function XPR_UI_LeaderboardExclude.Panel:onEntrySelected(data)
	if not data or data.empty then return end
	self.selectedEntry = data
	self.excludeBtn.enable = true
	local key = "IGUI_XPR_LeaderboardExclude_Button"
	if data.excluded then key = "IGUI_XPR_LeaderboardInclude_Button" end
	self.excludeBtn:setTitle(getText(key))
end

function XPR_UI_LeaderboardExclude.Panel:applyData(categoriesData)
	self.categoriesCache = categoriesData
	self:renderCurrentCategory()
end

function XPR_UI_LeaderboardExclude.Panel:onExclude()
	if not self.selectedEntry then return end
	local isAll = self:currentCategory() == "__ALL__"
	local key
	if self.selectedEntry.excluded then
		key = isAll and "IGUI_XPR_LeaderboardInclude_ConfirmAll" or "IGUI_XPR_LeaderboardInclude_Confirm"
	else
		key = isAll and "IGUI_XPR_LeaderboardExclude_ConfirmAll" or "IGUI_XPR_LeaderboardExclude_Confirm"
	end
	local text = XPR_UI_Scale.wrapModalText(UIFont.Small, getText(key), S(350))
	local w, h = S(380), S(150)
	local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
	local modal = ISModalDialog:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2),
		w, h, text, true, self,
		XPR_UI_LeaderboardExclude.Panel.onExcludeConfirm)
	modal:initialise()
	modal:addToUIManager()
end

function XPR_UI_LeaderboardExclude.Panel:onExcludeConfirm(button)
	if not button or button.internal ~= "YES" or not self.selectedEntry then return end
	local player = getSpecificPlayer(0)
	if not player then return end
	sendClientCommand(player, "XPRanks", "setLeaderboardExclusion", {
		category = self:currentCategory(),
		entryId = self.selectedEntry.entryId,
		excluded = not self.selectedEntry.excluded,
	})
end

function XPR_UI_LeaderboardExclude.Panel:close()
	ISCollapsableWindow.close(self)
	XPR_UI_LeaderboardExclude.instance = nil
end

function XPR_UI_LeaderboardExclude.open()
	if XPR_UI_LeaderboardExclude.instance then return end
	local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
	local panel = XPR_UI_LeaderboardExclude.Panel:new(0, 0)
	panel:setX(math.floor((sw - panel:getWidth()) / 2))
	panel:setY(math.floor((sh - panel:getHeight()) / 2))
	XPR_UI_LeaderboardExclude.instance = panel
	panel:initialise()
	panel:addToUIManager()
end

function XPR_UI_LeaderboardExclude.onData(categoriesData)
	if XPR_UI_LeaderboardExclude.instance then
		XPR_UI_LeaderboardExclude.instance:applyData(categoriesData)
	end
end

function XPR_UI_LeaderboardExclude.onResult(success, category, excluded)
	local panel = XPR_UI_LeaderboardExclude.instance
	if not panel then return end
	local messageKey = "IGUI_XPR_LeaderboardExclude_Failed"
	if success then
		messageKey = excluded and "IGUI_XPR_LeaderboardExclude_Success"
			or "IGUI_XPR_LeaderboardInclude_Success"
	end
	if ObNoxToast and ObNoxToast.show then
		ObNoxToast.show(getText(messageKey), "debug", nil, "XPRanks")
	end
end

return XPR_UI_LeaderboardExclude
