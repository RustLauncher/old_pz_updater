if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"
require "XPR_UI_Scale"
require "XPR_UI_Theme"
require "XPR_RewardCategoryResolver"
require "XPR_UI_RewardItemPicker"

XPR_UI_RewardAdmin = {}
XPR_UI_RewardAdmin.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local FONT_MD = XPR_UI_Scale.FONT_MD
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = S(10)
local PANEL_W = S(540)
local PANEL_H = S(650)
local ROW_H = S(80)
local ITEMS_PER_PAGE = 5
local BTN_H = fontHgt + S(9)
local COMBO_W = S(110)
local CHECK_SIZE = S(18)
local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_DIM = { r = 0.60, g = 0.60, b = 0.60 }
local COL_ROW_ALT = { r = 0.10, g = 0.10, b = 0.10 }

local TIER_OPTIONS = {
	{ text = "IGUI_XPR_Tier_Common", data = "COMMON" },
	{ text = "IGUI_XPR_Tier_Uncommon", data = "UNCOMMON" },
	{ text = "IGUI_XPR_Tier_Rare", data = "RARE" },
}

local TAB_ROW1 = { "All", "Tools", "Weapons", "Equipment", "Clothing" }
local TAB_ROW2 = { "Medical", "Food", "Literature", "Materials", "Other" }
local CAT_LABEL_KEY = {
	All = "IGUI_XPR_ItemCat_All", Tools = "IGUI_XPR_ItemCat_Tools",
	Weapons = "IGUI_XPR_ItemCat_Weapons", Equipment = "IGUI_XPR_ItemCat_Equipment",
	Clothing = "IGUI_XPR_ItemCat_Clothing", Medical = "IGUI_XPR_ItemCat_Medical",
	Food = "IGUI_XPR_ItemCat_Food", Literature = "IGUI_XPR_ItemCat_Literature",
	Materials = "IGUI_XPR_ItemCat_Materials", Other = "IGUI_XPR_ItemCat_Other",
}

local xpBonusIcon = getTexture("media/textures/xpr_icon_on.png")

local function getItemDisplayInfo(itemId)
	if XPR_RewardItems and XPR_RewardItems.isXpBonus(itemId) then
		return getText("IGUI_XPR_RewardItem_XpBonus", XPR_RewardItems.getXpBonusAmount(itemId)), xpBonusIcon, "Other"
	end
	if XPR_RewardItems and XPR_RewardItems.isSkillVhs(itemId) then
		local fullType = XPR_RewardItems.getSkillVhsFullType(itemId)
		local vsi = fullType and ScriptManager.instance and ScriptManager.instance:getItem(fullType)
		local vtex = vsi and vsi.getNormalTexture and vsi:getNormalTexture()
		if vsi and vsi.getIconsForTexture then
			local variants = vsi:getIconsForTexture()
			if variants and not variants:isEmpty() then
				local variant = variants:get(0)
				vtex = (type(variant) == "string") and (getTexture("Item_" .. variant) or vtex) or variant
			end
		end
		return XPR_RewardItems.getSkillVhsDisplayName(itemId), vtex, "Other"
	end
	if XPR_RewardItems and XPR_RewardItems.isRecipeItem(itemId) then
		local fullType = XPR_RewardItems.getRecipeItemFullType(itemId)
		local rsi = fullType and ScriptManager.instance and ScriptManager.instance:getItem(fullType)
		local rtex = rsi and rsi.getNormalTexture and rsi:getNormalTexture()
		if rsi and rsi.getIconsForTexture then
			local variants = rsi:getIconsForTexture()
			if variants and not variants:isEmpty() then
				local variant = variants:get(0)
				rtex = (type(variant) == "string") and (getTexture("Item_" .. variant) or rtex) or variant
			end
		end
		return XPR_RewardItems.getRecipeItemDisplayName(itemId), rtex, "Other"
	end
	local si = ScriptManager.instance and ScriptManager.instance:getItem(itemId)
	if not si then return itemId, nil, "Other" end
	local tex = si.getNormalTexture and si:getNormalTexture()
	if si.getIconsForTexture then
		local variants = si:getIconsForTexture()
		if variants and not variants:isEmpty() then
			local variant = variants:get(0)
			if type(variant) == "string" then
				tex = getTexture("Item_" .. variant) or tex
			else
				tex = variant
			end
		end
	end
	local category = XPR_RewardCategoryResolver.resolve(si, itemId) or "Other"
	local displayName = si:getDisplayName() or itemId
	if XPR_RewardItems and XPR_RewardItems.isRandomizedOnGrant(itemId) then
		displayName = displayName .. " (Random)"
	end
	return displayName, tex, category
end

local function truncateText(text, font, maxWidth)
	if not text or not font then return text or "" end
	local tmgr = getTextManager()
	if tmgr:MeasureStringX(font, text) <= maxWidth then return text end
	while #text > 0 and tmgr:MeasureStringX(font, text .. "...") > maxWidth do
		text = string.sub(text, 1, #text - 1)
	end
	return text .. "..."
end

XPR_UI_RewardAdmin.Panel = ISCollapsableWindow:derive("XPR_UI_RewardAdmin_Panel")

function XPR_UI_RewardAdmin.Panel:new(x, y)
	local btnPad = S(12)
	local tabCaptions = {}
	for _, name in ipairs(TAB_ROW1) do tabCaptions[#tabCaptions + 1] = getText(CAT_LABEL_KEY[name] or name) end
	for _, name in ipairs(TAB_ROW2) do tabCaptions[#tabCaptions + 1] = getText(CAT_LABEL_KEY[name] or name) end
	local tabNeeded = XPR_UI_Scale.longestText(FONT, tabCaptions) + S(14)
	local tabRowNeeded = PAD * 2 + 5 * tabNeeded
	local prevW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Prev"), S(60), btnPad)
	local nextW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Next"), S(60), btnPad)
	local pageLabelW = XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Common_PageOf", 88, 88))
	local pagNeeded = PAD * 2 + prevW + S(4) + S(40) + S(8) + pageLabelW + S(8) + nextW
	local tierNeeded = 0
	for _, opt in ipairs(TIER_OPTIONS) do
		tierNeeded = math.max(tierNeeded, XPR_UI_Scale.measureText(FONT, getText(opt.text)) + S(30))
	end
	local comboNeeded = PAD * 2 + tierNeeded + CHECK_SIZE + S(26)
	local saveCancelNeeded = PAD * 2 + math.max(
		XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Common_Save")),
		XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_ValueDialog_Cancel"))) + btnPad * 2
	local titleNeeded = XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_AdminMenu_EditRewardItems")) + BTN_H + PAD * 2
	local panelW = math.max(PANEL_W, tabRowNeeded, pagNeeded, comboNeeded, saveCancelNeeded, titleNeeded)
	local o = ISCollapsableWindow.new(self, x, y, panelW, PANEL_H)
	o.moveWithMouse = true
	o.resizable = false
	o.pendingItems = {}
	o.activeCategory = "All"
	o.hasUnsavedChanges = false
	o._panelW = panelW
	o._prevW = prevW
	o._nextW = nextW
	o._pageLabelW = pageLabelW
	o._tabNeeded = tabNeeded
	o._comboNeeded = tierNeeded
	return o
end

function XPR_UI_RewardAdmin.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)

	local panelW = self._panelW or PANEL_W
	local titleH = fontHgt + S(1)
	local y = titleH + PAD

	self.searchEntry = ISTextEntryBox:new("", PAD, y, panelW - PAD * 2, fontHgt + S(5))
	self.searchEntry:initialise()
	self.searchEntry:instantiate()
	self.searchEntry:setPlaceholderText(getText("IGUI_XPR_Common_SearchItems"))
	self.lastSearchText = ""
	self:addChild(self.searchEntry)
	y = y + S(30)

	self.lblInfo = ISLabel:new(PAD, y, S(16), "",
		COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT, true)
	self.lblInfo:initialise()
	self:addChild(self.lblInfo)
	y = y + S(18)

	local totalTabW = panelW - PAD * 2
	local tabW = math.floor(math.max(totalTabW / 5, (self._tabNeeded or 0)))
	local tabH = S(20)
	self.catTabs = {}

	local function makeTab(name, col, r)
		local tab = ISButton:new(PAD + (col - 1) * tabW, y + (r - 1) * (tabH + S(2)), tabW, tabH,
			getText(CAT_LABEL_KEY[name] or name), self, XPR_UI_RewardAdmin.Panel.onCategoryTab)
		tab:initialise()
		tab:instantiate()
		tab.category = name
		tab.background = true
		tab.isBaseBackgroundVisible = true
		tab.borderColor = { r = 0.30, g = 0.30, b = 0.30, a = 1.0 }
		self:addChild(tab)
		self.catTabs[name] = tab
	end

	for i, name in ipairs(TAB_ROW1) do makeTab(name, i, 1) end
	for i, name in ipairs(TAB_ROW2) do makeTab(name, i, 2) end
	self:updateTabColors()
	y = y + (tabH + S(2)) * 2 + S(4)

	self.listTop = y
	self.rowCombos = {}
	self.rowCheckButtons = {}
	for i = 1, ITEMS_PER_PAGE do
		local rowY = self.listTop + (i - 1) * ROW_H
		local checkX = (panelW - PAD) - CHECK_SIZE - S(16)
		local checkY = rowY + math.floor((ROW_H - CHECK_SIZE) / 2)
		local comboH = fontHgt + S(6)
		local comboX = checkX - S(10) - math.max(COMBO_W, self._comboNeeded or 0)
		local comboY = rowY + math.floor((ROW_H - comboH) / 2)

		local combo = ISComboBox:new(comboX, comboY, math.max(COMBO_W, self._comboNeeded or 0), comboH,
			self, XPR_UI_RewardAdmin.Panel.onTierChanged, i)
		combo:initialise()
		combo:instantiate()
		for _, opt in ipairs(TIER_OPTIONS) do
			combo:addOptionWithData(getText(opt.text), opt.data)
		end
		combo:setVisible(false)
		self:addChild(combo)
		self.rowCombos[i] = combo

		local checkBtn = ISButton:new(checkX, checkY, CHECK_SIZE, CHECK_SIZE, "", self, nil)
		checkBtn:initialise()
		checkBtn:instantiate()
		checkBtn:setOnClick(XPR_UI_RewardAdmin.Panel.onToggleActive, i)
		checkBtn:setBackgroundRGBA(0, 0, 0, 0)
		checkBtn:setBackgroundColorMouseOverRGBA(1, 1, 1, 0.15)
		checkBtn:setBorderRGBA(0, 0, 0, 0)
		checkBtn:setVisible(false)
		self:addChild(checkBtn)
		self.rowCheckButtons[i] = checkBtn
	end
	y = self.listTop + ITEMS_PER_PAGE * ROW_H + S(8)

	local pagY = y
	local prevW = self._prevW or S(60)
	local nextW = self._nextW or S(60)

	self.btnPrev = ISButton:new(PAD, pagY, prevW, BTN_H, getText("IGUI_XPR_Common_Prev"), self, XPR_UI_RewardAdmin.Panel.onPrevPage)
	self.btnPrev:initialise()
	self.btnPrev:instantiate()
	self:addChild(self.btnPrev)

	self.pageEntry = ISTextEntryBox:new("1", PAD + prevW + S(4), pagY, S(40), BTN_H)
	self.pageEntry:initialise()
	self.pageEntry:instantiate()
	self.pageEntry:setOnlyNumbers(true)
	self.pageEntry.onCommandEntered = function(_) self:onPageEntry() end
	self:addChild(self.pageEntry)

	self.pageLabel = ISLabel:new(PAD + prevW + S(4) + S(40) + S(8), pagY + S(4), S(16), getText("IGUI_XPR_Common_PageOf", 1, 1),
		COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT, true)
	self.pageLabel:initialise()
	self:addChild(self.pageLabel)

	self.btnNext = ISButton:new(panelW - PAD - nextW, pagY, nextW, BTN_H, getText("IGUI_XPR_Common_Next"), self, XPR_UI_RewardAdmin.Panel.onNextPage)
	self.btnNext:initialise()
	self.btnNext:instantiate()
	self:addChild(self.btnNext)

	local selY = pagY + BTN_H + S(6)
	local selBtnW = S(90)

	self.btnUnselectAll = ISButton:new(PAD, selY, selBtnW, BTN_H, getText("IGUI_XPR_Common_UnselectAll"), self, XPR_UI_RewardAdmin.Panel.onUnselectAll)
	self.btnUnselectAll:initialise()
	self.btnUnselectAll:instantiate()
	self:addChild(self.btnUnselectAll)

	self.btnChoose = ISButton:new(0, selY, S(100), BTN_H, getText("IGUI_XPR_RewardPicker_Title"), self, XPR_UI_RewardAdmin.Panel.onChooseItems)
	self.btnChoose:initialise()
	self.btnChoose:instantiate()
	self:addChild(self.btnChoose)

	self.btnSelectAll = ISButton:new(panelW - PAD - selBtnW, selY, selBtnW, BTN_H, getText("IGUI_XPR_Common_SelectAll"), self, XPR_UI_RewardAdmin.Panel.onSelectAll)
	self.btnSelectAll:initialise()
	self.btnSelectAll:instantiate()
	self:addChild(self.btnSelectAll)

	local tmgr = getTextManager()
	local function fitWidth(b, minW)
		local w = math.max(minW, tmgr:MeasureStringX(b.font or FONT, b.title or "") + S(20))
		b:setWidth(w)
		return w
	end
	local chooseW = fitWidth(self.btnChoose, S(100))
	self.btnChoose:setX(math.floor((panelW - chooseW) / 2))
	fitWidth(self.btnUnselectAll, selBtnW)
	local selectAllW = fitWidth(self.btnSelectAll, selBtnW)
	self.btnSelectAll:setX(panelW - PAD - selectAllW)

	local yBtn = selY + BTN_H + S(8)

	self.btnSave = ISButton:new(PAD, yBtn, S(80), BTN_H, getText("IGUI_XPR_Common_Save"), self, XPR_UI_RewardAdmin.Panel.onSave)
	self.btnSave:initialise()
	self.btnSave:instantiate()
	self.btnSave:enableAcceptColor()
	self:addChild(self.btnSave)

	self.btnCancel = ISButton:new(0, yBtn, S(80), BTN_H, getText("IGUI_XPR_ValueDialog_Cancel"), self, XPR_UI_RewardAdmin.Panel.onCancel)
	self.btnCancel:initialise()
	self.btnCancel:instantiate()
	self.btnCancel:enableCancelColor()
	self:addChild(self.btnCancel)

	local saveW = fitWidth(self.btnSave, S(80))
	local cancelW = fitWidth(self.btnCancel, S(80))
	self.btnSave:setX(PAD)
	self.btnCancel:setX(panelW - PAD - cancelW)

	self:setHeight(yBtn + BTN_H + S(8))

	self.currentPage = 1
	self.totalPages = 1
	self.allItems = {}
	self.filteredItems = {}
	self.pageRows = {}

	self:loadConfig()
	self:rebuildItems()
end

function XPR_UI_RewardAdmin.Panel:initialise()
	ISCollapsableWindow.initialise(self)
end

function XPR_UI_RewardAdmin.Panel:prerender()
	ISCollapsableWindow.prerender(self)
	local titleH = fontHgt + S(1)
	self:drawRect(0, titleH, self.width, S(2), 1, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)

	local listH = ITEMS_PER_PAGE * ROW_H
	self:drawRect(PAD, self.listTop, self.width - PAD * 2, listH, 0.8, 0, 0, 0)

	for i = 1, ITEMS_PER_PAGE do
		local data = self.pageRows[i]
		local rowY = self.listTop + (i - 1) * ROW_H
		if data then
			if i % 2 == 0 then
				self:drawRect(0, rowY, self.width, ROW_H - S(1), 0.25, COL_ROW_ALT.r, COL_ROW_ALT.g, COL_ROW_ALT.b)
			end

			local iconSize = S(32)
			local iconX = PAD + S(14)
			local iconY = rowY + math.floor((ROW_H - iconSize) / 2)
			if data.icon then
				self:drawTextureScaled(data.icon, iconX, iconY, iconSize, iconSize, 1)
			else
				self:drawRect(iconX, iconY, iconSize, iconSize, 0.5, 0.3, 0.3, 0.3)
				self:drawRectBorder(iconX, iconY, iconSize, iconSize, 0.5, 0.5, 0.5, 0.5)
			end

			local textX = iconX + S(44)
			local checkX = (self.width - PAD) - CHECK_SIZE - S(16)
			local maxTextW = (checkX - S(10) - COMBO_W - S(8)) - textX
			local nameCol = (data.active ~= false) and COL_TEXT or COL_DIM

			local LINE_GAP = S(28)
			local blockH = LINE_GAP + fontHgt
			local nameY = rowY + math.floor((ROW_H - blockH) / 2)
			local idY = nameY + LINE_GAP
			self:drawText(truncateText(data.displayName, FONT_MD, maxTextW), textX, nameY,
				nameCol.r, nameCol.g, nameCol.b, 0.90, FONT_MD)
			self:drawText(truncateText(data.itemId, FONT, maxTextW), textX, idY,
				COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.70, FONT)

			local checkY = rowY + math.floor((ROW_H - CHECK_SIZE) / 2)
			self:drawRectBorder(checkX, checkY, CHECK_SIZE, CHECK_SIZE, 0.6, 0.6, 0.6, 0.6)
			if data.active ~= false then
				self:drawRect(checkX + S(3), checkY + S(3), CHECK_SIZE - S(6), CHECK_SIZE - S(6), 1,
					COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
			end
		end
	end

	self:drawRectBorder(PAD, self.listTop, self.width - PAD * 2, listH, 0.9, 0.4, 0.4, 0.4)

	if self.searchEntry then
		local currentText = self.searchEntry:getText() or ""
		if currentText ~= (self.lastSearchText or "") then
			self.lastSearchText = currentText
			self.currentPage = 1
			self:filterAndShowPage()
		end
	end

	if self.pageEntry and not self.pageEntry:isFocused() then
		local pageText = self.pageEntry:getText() or ""
		local page = tonumber(pageText) or 1
		if page ~= self.currentPage then
			self.currentPage = math.max(1, math.min(page, self.totalPages))
			self:showPage()
		end
	end
end

function XPR_UI_RewardAdmin.Panel:loadConfig()
	self.pendingItems = {}
	self.hasUnsavedChanges = false
	local map = XPR_RewardItems and XPR_RewardItems.getEffectiveItemsMap and XPR_RewardItems.getEffectiveItemsMap()
	for itemId, entry in pairs(map or {}) do
		self.pendingItems[itemId] = { tier = entry.tier, active = entry.active ~= false }
	end

	if not (XPR_Env and XPR_Env.isTrueSinglePlayer()) then
		local player = getSpecificPlayer(0)
		if player then
			sendClientCommand(player, "XPRanks", "getRewardConfig", {})
		end
	end
end

function XPR_UI_RewardAdmin.Panel:applySyncedConfig(itemsMap)
	if self.hasUnsavedChanges then return end
	self.pendingItems = {}
	for itemId, entry in pairs(itemsMap or {}) do
		self.pendingItems[itemId] = { tier = entry.tier, active = entry.active ~= false }
	end
	self:rebuildItems()
end

function XPR_UI_RewardAdmin.Panel:rebuildItems()
	self.allItems = {}
	for itemId, entry in pairs(self.pendingItems) do
		local displayName, icon, category = getItemDisplayInfo(itemId)
		entry.itemId = itemId
		entry.displayName = displayName
		entry.icon = icon
		entry.category = category
		self.allItems[#self.allItems + 1] = entry
	end
	table.sort(self.allItems, function(a, b) return a.displayName < b.displayName end)
	self:filterAndShowPage()
end

function XPR_UI_RewardAdmin.Panel:filterAndShowPage()
	self.filteredItems = {}
	local searchText = string.lower(self.searchEntry and self.searchEntry:getText() or "")
	for _, item in ipairs(self.allItems) do
		local matchCat = self.activeCategory == "All" or item.category == self.activeCategory
		local matchSearch = searchText == ""
			or string.find(string.lower(item.displayName or ""), searchText, 1, true)
			or string.find(string.lower(item.itemId or ""), searchText, 1, true)
		if matchCat and matchSearch then
			self.filteredItems[#self.filteredItems + 1] = item
		end
	end
	self.totalPages = math.max(1, math.ceil(#self.filteredItems / ITEMS_PER_PAGE))
	self.currentPage = math.min(self.currentPage, self.totalPages)
	if self.lblInfo then
		self.lblInfo:setName(getText("IGUI_XPR_RewardAdmin_PoolCount", #self.filteredItems))
	end
	self:showPage()
end

function XPR_UI_RewardAdmin.Panel:getEmptyBands()
	local counts = { COMMON = 0, UNCOMMON = 0, RARE = 0 }
	for _, entry in pairs(self.pendingItems or {}) do
		if entry.active ~= false and counts[entry.tier] ~= nil then
			counts[entry.tier] = counts[entry.tier] + 1
		end
	end

	local empty = {}
	for _, band in ipairs({ "COMMON", "UNCOMMON", "RARE" }) do
		if counts[band] == 0 then
			empty[#empty + 1] = band
		end
	end
	return empty
end

function XPR_UI_RewardAdmin.Panel:showPage()
	self.pageRows = {}
	local startIdx = (self.currentPage - 1) * ITEMS_PER_PAGE + 1
	for i = 1, ITEMS_PER_PAGE do
		local item = self.filteredItems[startIdx + i - 1]
		local combo = self.rowCombos[i]
		local checkBtn = self.rowCheckButtons[i]
		if item then
			self.pageRows[i] = item
			combo:setVisible(true)
			combo:setSelectedData(item.tier)
			checkBtn:setVisible(true)
		else
			combo:setVisible(false)
			checkBtn:setVisible(false)
		end
	end
	if self.pageEntry then self.pageEntry:setText(tostring(self.currentPage)) end
	if self.pageLabel then self.pageLabel:setName(getText("IGUI_XPR_Common_PageOf", self.currentPage, self.totalPages)) end
	if self.btnPrev then self.btnPrev.enable = self.currentPage > 1 end
	if self.btnNext then self.btnNext.enable = self.currentPage < self.totalPages end
end

function XPR_UI_RewardAdmin.Panel:updateTabColors()
	for name, tab in pairs(self.catTabs) do
		if name == self.activeCategory then
			tab.textColor = { r = COL_ACCENT.r, g = COL_ACCENT.g, b = COL_ACCENT.b, a = 1 }
		else
			tab.textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1 }
		end
	end
end

function XPR_UI_RewardAdmin.Panel:onCategoryTab(btn)
	self.activeCategory = (btn and btn.category) or "All"
	self.currentPage = 1
	self:updateTabColors()
	self:filterAndShowPage()
end

function XPR_UI_RewardAdmin.Panel:onPrevPage()
	if self.currentPage > 1 then
		self.currentPage = self.currentPage - 1
		self:showPage()
	end
end

function XPR_UI_RewardAdmin.Panel:onNextPage()
	if self.currentPage < self.totalPages then
		self.currentPage = self.currentPage + 1
		self:showPage()
	end
end

function XPR_UI_RewardAdmin.Panel:onPageEntry()
	local page = tonumber(self.pageEntry:getText()) or 1
	page = math.max(1, math.min(page, self.totalPages))
	self.currentPage = page
	self:showPage()
end

function XPR_UI_RewardAdmin.Panel.onTierChanged(target, combo, rowIdx)
	local self = target
	local data = self.pageRows[rowIdx]
	if not data then return end
	data.tier = combo:getSelectedData()
	self.hasUnsavedChanges = true
end

function XPR_UI_RewardAdmin.Panel.onToggleActive(target, btn, rowIdx)
	local self = target
	local data = self.pageRows[rowIdx]
	if not data then return end
	data.active = not (data.active ~= false)
	self.hasUnsavedChanges = true
end

function XPR_UI_RewardAdmin.Panel:onSelectAll()
	for _, item in ipairs(self.filteredItems or {}) do
		item.active = true
	end
	self.hasUnsavedChanges = true
end

function XPR_UI_RewardAdmin.Panel:onUnselectAll()
	for _, item in ipairs(self.filteredItems or {}) do
		item.active = false
	end
	self.hasUnsavedChanges = true
end

function XPR_UI_RewardAdmin.Panel:onChooseItems()
	XPR_UI_RewardItemPicker.open(self)
end

function XPR_UI_RewardAdmin.Panel:showEmptyBandsDialog(emptyBands)
	local text = getText("IGUI_XPR_RewardAdmin_EmptyBands", table.concat(emptyBands, ", "))
	text = XPR_UI_Scale.wrapModalText(UIFont.Small, text, S(310))
	local w, h = S(340), S(180)
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local modal = ISModalDialog:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2),
		w, h, text, false, self, nil)
	modal:initialise()
	modal:addToUIManager()
end

function XPR_UI_RewardAdmin.Panel:onSave()
	local emptyBands = self:getEmptyBands()
	if #emptyBands > 0 then
		self:showEmptyBandsDialog(emptyBands)
		return
	end

	local player = getSpecificPlayer(0)
	if not player then return end
	local payload = {}
	for itemId, entry in pairs(self.pendingItems) do
		payload[itemId] = { tier = entry.tier, active = entry.active ~= false }
	end
	sendClientCommand(player, "XPRanks", "rewardAdminApply", { items = payload })
	if ObNoxToast and ObNoxToast.show then
		ObNoxToast.show(getText("IGUI_XPR_RewardAdmin_PoolUpdatedToast"), "complete", nil, "XPRanks")
	end
	self:close()
end

function XPR_UI_RewardAdmin.Panel:onCancel()
	self:close()
end

function XPR_UI_RewardAdmin.Panel:close()
	self:setVisible(false)
	self:removeFromUIManager()
	XPR_UI_RewardAdmin.instance = nil
end

function XPR_UI_RewardAdmin.open()
	if XPR_UI_RewardAdmin.instance then
		XPR_UI_RewardAdmin.instance:setVisible(true)
		XPR_UI_RewardAdmin.instance:addToUIManager()
		return
	end
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local panel = XPR_UI_RewardAdmin.Panel:new(0, 0)
	panel:setX(math.floor((screenW - panel:getWidth()) / 2))
	panel:setY(math.floor((screenH - PANEL_H) / 2))
	XPR_UI_RewardAdmin.instance = panel
	panel:initialise()
	panel:addToUIManager()
	panel:setTitle(getText("IGUI_XPR_AdminMenu_EditRewardItems"))
end

function XPR_UI_RewardAdmin.close()
	if XPR_UI_RewardAdmin.instance then
		XPR_UI_RewardAdmin.instance:close()
	end
end

return XPR_UI_RewardAdmin
