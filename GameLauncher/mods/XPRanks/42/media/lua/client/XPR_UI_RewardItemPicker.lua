if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "XPR_UI_Scale"
require "XPR_UI_Theme"
require "XPR_RewardCategoryResolver"

XPR_UI_RewardItemPicker = {}
XPR_UI_RewardItemPicker.instance = nil

local FONT_SM = XPR_UI_Scale.FONT_SM
local S = XPR_UI_Scale.s
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = S(10)
local PICKER_W = S(440)
local PICKER_H = S(760)
local ROW_H = S(40)
local BTN_H = fontHgt + S(9)
local ITEMS_PER_PAGE = 20

local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_DIM = { r = 0.60, g = 0.60, b = 0.60 }
local COL_ROW_ALT = { r = 0.10, g = 0.10, b = 0.10 }

local TAB_ROW1 = { "All", "Tools", "Weapons", "Equipment", "Clothing" }
local TAB_ROW2 = { "Medical", "Food", "Literature", "Materials", "Other" }
local CAT_LABEL_KEY = {
	All = "IGUI_XPR_ItemCat_All", Tools = "IGUI_XPR_ItemCat_Tools",
	Weapons = "IGUI_XPR_ItemCat_Weapons", Equipment = "IGUI_XPR_ItemCat_Equipment",
	Clothing = "IGUI_XPR_ItemCat_Clothing", Medical = "IGUI_XPR_ItemCat_Medical",
	Food = "IGUI_XPR_ItemCat_Food", Literature = "IGUI_XPR_ItemCat_Literature",
	Materials = "IGUI_XPR_ItemCat_Materials", Other = "IGUI_XPR_ItemCat_Other",
}

local EXCLUDED_ITEM_TYPES = {
	["Base.FISH_DEV_ITEM"] = true,
	["Base.RubberDucky2"] = true,
	["Base.Mov_FlagAdmin"] = true,
	["Base.WaterDrop"] = true,
	["Base.MysteryCan_Open"] = true,
	["Base.Stairs"] = true,
	["Base.DebugFluid"] = true,
	["Base.TestDebugWater"] = true,
	["Base.TestWaterMug"] = true,
	["Base.TestMug"] = true,
	["Base.TestHotDrink"] = true,
	["Base.Hat_SantaHatDebug"] = true,
	["Base.DentedCan_Open"] = true,
	["Base.YardstickDEBUG"] = true,
	["Base.Animal_Item_Dummy"] = true,
	["Base.WaterRationCan_Open"] = true,
	["Base.BucketWaterDebug"] = true,

	["XPRanks.XPR_RewardBox1"] = true,
	["XPRanks.XPR_RewardBox2"] = true,
	["XPRanks.XPR_RewardBox3"] = true,
	["XPRanks.XPR_RewardBox4"] = true,
	["XPRanks.XPR_RewardBox5"] = true,
}

local xpBonusIcon = getTexture("media/textures/xpr_icon_on.png")
local XP_BONUS_IDS = { "XPR_BONUS_XP:50", "XPR_BONUS_XP:100", "XPR_BONUS_XP:200" }

local function truncateText(text, font, maxWidth)
	if not text or not font then return text or "" end
	local tmgr = getTextManager()
	if tmgr:MeasureStringX(font, text) <= maxWidth then return text end
	while #text > 0 and tmgr:MeasureStringX(font, text .. "...") > maxWidth do
		text = string.sub(text, 1, #text - 1)
	end
	return text .. "..."
end

local function getItemIcon(scriptItem)
	local tex = scriptItem.getNormalTexture and scriptItem:getNormalTexture()
	if scriptItem.getIconsForTexture then
		local variants = scriptItem:getIconsForTexture()
		if variants and not variants:isEmpty() then
			local variant = variants:get(0)
			if type(variant) == "string" then
				tex = getTexture("Item_" .. variant) or tex
			else
				tex = variant
			end
		end
	end
	return tex
end

XPR_UI_RewardItemPicker.Panel = ISCollapsableWindow:derive("XPR_UI_RewardItemPicker_Panel")

function XPR_UI_RewardItemPicker.Panel:new(x, y, adminWindow)
	local btnPad = S(12)
	local tabCaptions = {}
	for _, name in ipairs(TAB_ROW1) do tabCaptions[#tabCaptions + 1] = getText(CAT_LABEL_KEY[name] or name) end
	for _, name in ipairs(TAB_ROW2) do tabCaptions[#tabCaptions + 1] = getText(CAT_LABEL_KEY[name] or name) end
	local tabNeeded = XPR_UI_Scale.longestText(FONT_SM, tabCaptions) + S(14)
	local tabRowNeeded = PAD * 2 + 5 * tabNeeded
	local prevW = XPR_UI_Scale.btnWidth(FONT_SM, getText("IGUI_XPR_Common_Prev"), S(70), btnPad)
	local nextW = XPR_UI_Scale.btnWidth(FONT_SM, getText("IGUI_XPR_Common_Next"), S(70), btnPad)
	local pageLabelW = XPR_UI_Scale.measureText(FONT_SM, getText("IGUI_XPR_Common_PageOf", 88, 88))
	local pagNeeded = PAD * 2 + prevW + S(6) + S(40) + S(12) + pageLabelW + S(8) + nextW
	local selBtnW = S(90)
	local selRowNeeded = math.max(
		XPR_UI_Scale.measureText(FONT_SM, getText("IGUI_XPR_Common_UnselectAll")),
		XPR_UI_Scale.measureText(FONT_SM, getText("IGUI_XPR_Common_SelectAll")),
		XPR_UI_Scale.measureText(FONT_SM, getText("IGUI_XPR_RewardPicker_UnloadDefaults")),
		XPR_UI_Scale.measureText(FONT_SM, getText("IGUI_XPR_RewardPicker_LoadDefaults"))) + selBtnW
	local titleNeeded = XPR_UI_Scale.measureText(FONT_SM, getText("IGUI_XPR_RewardPicker_Title")) + BTN_H + PAD * 2
	local panelW = math.max(PICKER_W, tabRowNeeded, pagNeeded, selRowNeeded, titleNeeded)
	local o = ISCollapsableWindow.new(self, x, y, panelW, PICKER_H)
	o.moveWithMouse = true
	o.resizable = false
	o.adminWindow = adminWindow
	o.activeCategory = "All"
	o._panelW = panelW
	o._tabNeeded = tabNeeded
	o._prevW = prevW
	o._nextW = nextW
	return o
end

function XPR_UI_RewardItemPicker.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)

	local panelW = self._panelW or PICKER_W
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
		COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT_SM, true)
	self.lblInfo:initialise()
	self:addChild(self.lblInfo)
	y = y + S(18)

	local totalTabW = panelW - PAD * 2
	local tabW = math.floor(math.max(totalTabW / 5, (self._tabNeeded or 0)))
	local tabH = S(20)
	self.catTabs = {}

	local function makeTab(name, col, r)
		local tab = ISButton:new(PAD + (col - 1) * tabW, y + (r - 1) * (tabH + S(2)), tabW, tabH,
			getText(CAT_LABEL_KEY[name] or name), self, XPR_UI_RewardItemPicker.Panel.onCategoryTab)
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

	local listH = ITEMS_PER_PAGE * ROW_H
	self.itemList = ISScrollingListBox:new(PAD, y, panelW - PAD * 2, listH)
	self.itemList:initialise()
	self.itemList:instantiate()
	self.itemList.itemheight = ROW_H
	self.itemList.selected = 0
	self.itemList.font = FONT_SM
	self.itemList.doDrawItem = XPR_UI_RewardItemPicker.Panel.drawItemRow
	self.itemList.drawBorder = true
	self.itemList:setOnMouseDownFunction(self, XPR_UI_RewardItemPicker.Panel.onItemClicked)
	if self.itemList.vscroll then self.itemList.vscroll:setVisible(false) end
	self:addChild(self.itemList)
	y = y + listH + S(8)

	local pagH = fontHgt + S(5)
	local prevW = self._prevW or S(70)
	local nextW = self._nextW or S(70)

	self.btnPrev = ISButton:new(PAD, y, prevW, pagH, getText("IGUI_XPR_Common_Prev"), self, XPR_UI_RewardItemPicker.Panel.onPrevPage)
	self.btnPrev:initialise()
	self.btnPrev:instantiate()
	self:addChild(self.btnPrev)

	self.pageEntry = ISTextEntryBox:new("1", PAD + prevW + S(6), y, S(40), pagH)
	self.pageEntry:initialise()
	self.pageEntry:instantiate()
	self.pageEntry:setOnlyNumbers(true)
	self.pageEntry.onCommandEntered = function(_) self:onPageInput() end
	self:addChild(self.pageEntry)

	self.pageLabel = ISLabel:new(PAD + prevW + S(6) + S(40) + S(6), y + S(4), S(16), getText("IGUI_XPR_Common_PageOf", 1, 1),
		COL_DIM.r, COL_DIM.g, COL_DIM.b, 1, FONT_SM, true)
	self.pageLabel:initialise()
	self:addChild(self.pageLabel)

	self.btnNext = ISButton:new(panelW - PAD - nextW, y, nextW, pagH, getText("IGUI_XPR_Common_Next"), self, XPR_UI_RewardItemPicker.Panel.onNextPage)
	self.btnNext:initialise()
	self.btnNext:instantiate()
	self:addChild(self.btnNext)
	y = y + pagH + S(6)

	local selBtnW = S(90)
	self.btnUnselectAll = ISButton:new(PAD, y, selBtnW, BTN_H, getText("IGUI_XPR_Common_UnselectAll"), self, XPR_UI_RewardItemPicker.Panel.onUnselectAll)
	self.btnUnselectAll:initialise()
	self.btnUnselectAll:instantiate()
	self:addChild(self.btnUnselectAll)

	self.btnSelectAll = ISButton:new(panelW - PAD - selBtnW, y, selBtnW, BTN_H, getText("IGUI_XPR_Common_SelectAll"), self, XPR_UI_RewardItemPicker.Panel.onSelectAll)
	self.btnSelectAll:initialise()
	self.btnSelectAll:instantiate()
	self:addChild(self.btnSelectAll)

	do
		local tmgr2 = getTextManager()
		local function fitSelBtn(b, minW)
			return math.max(minW, tmgr2:MeasureStringX(b.font or FONT, b.title or "") + S(20))
		end
		local unselW = fitSelBtn(self.btnUnselectAll, selBtnW)
		self.btnUnselectAll:setWidth(unselW)
		local selW = fitSelBtn(self.btnSelectAll, selBtnW)
		self.btnSelectAll:setWidth(selW)
		self.btnSelectAll:setX(panelW - PAD - selW)
	end

	local defaultIds = {}
	for _, id in ipairs(XPR_RewardItems.COMMON or {}) do defaultIds[id] = true end
	for _, id in ipairs(XPR_RewardItems.UNCOMMON or {}) do defaultIds[id] = true end
	for _, id in ipairs(XPR_RewardItems.RARE or {}) do defaultIds[id] = true end
	local pendingItems = (self.adminWindow and self.adminWindow.pendingItems) or {}
	local allDefaultsLoaded = true
	for id in pairs(defaultIds) do
		if pendingItems[id] == nil then allDefaultsLoaded = false; break end
	end
	self.defaultsLoaded = allDefaultsLoaded

	self.btnToggleDefaults = ISButton:new(0, y, S(180), BTN_H,
		allDefaultsLoaded and getText("IGUI_XPR_RewardPicker_UnloadDefaults") or getText("IGUI_XPR_RewardPicker_LoadDefaults"),
		self, XPR_UI_RewardItemPicker.Panel.onToggleDefaults)
	self.btnToggleDefaults:initialise()
	self.btnToggleDefaults:instantiate()
	self:addChild(self.btnToggleDefaults)

	local tmgr = getTextManager()
	local toggleW = math.max(S(180), tmgr:MeasureStringX(self.btnToggleDefaults.font or FONT_SM,
		self.btnToggleDefaults.title or "") + S(20))
	self.btnToggleDefaults:setWidth(toggleW)
	self.btnToggleDefaults:setX(math.floor((panelW - toggleW) / 2))
	y = y + BTN_H + S(6)

	local saveW = XPR_UI_Scale.btnWidth(FONT_SM, getText("IGUI_XPR_Common_Save"), S(80), S(20))
	local cancelW = XPR_UI_Scale.btnWidth(FONT_SM, getText("IGUI_XPR_ValueDialog_Cancel"), S(80), S(20))
	self.btnSave = ISButton:new(PAD, y, saveW, BTN_H, getText("IGUI_XPR_Common_Save"), self, XPR_UI_RewardItemPicker.Panel.onAdd)
	self.btnSave:initialise()
	self.btnSave:instantiate()
	self.btnSave:enableAcceptColor()
	self:addChild(self.btnSave)

	self.btnCancel = ISButton:new(panelW - PAD - cancelW, y, cancelW, BTN_H, getText("IGUI_XPR_ValueDialog_Cancel"), self, XPR_UI_RewardItemPicker.Panel.onCancel)
	self.btnCancel:initialise()
	self.btnCancel:instantiate()
	self.btnCancel:enableCancelColor()
	self:addChild(self.btnCancel)

	self:setHeight(y + BTN_H + S(8))

	self.currentPage = 1
	self.filteredItems = {}
	self.totalPages = 1
	self.allItems = {}
	self._itemByType = {}
	self:loadAllItems()
	self:filterItems()

	self.itemList.pickerPanel = self
end

function XPR_UI_RewardItemPicker.Panel:initialise()
	ISCollapsableWindow.initialise(self)
end

function XPR_UI_RewardItemPicker.Panel:prerender()
	ISCollapsableWindow.prerender(self)
	self:drawRect(0, fontHgt + S(1), self.width, S(2), 1, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
	if self.searchEntry then
		local currentText = self.searchEntry:getText() or ""
		if currentText ~= (self.lastSearchText or "") then
			self.lastSearchText = currentText
			self.currentPage = 1
			self:filterItems()
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

function XPR_UI_RewardItemPicker.Panel:updateTabColors()
	for name, tab in pairs(self.catTabs) do
		if name == self.activeCategory then
			tab.textColor = { r = COL_ACCENT.r, g = COL_ACCENT.g, b = COL_ACCENT.b, a = 1 }
		else
			tab.textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1 }
		end
	end
end

function XPR_UI_RewardItemPicker.Panel:onCategoryTab(btn)
	self.activeCategory = (btn and btn.category) or "All"
	self.currentPage = 1
	self:updateTabColors()
	self:filterItems()
end

local _allItemsCache = nil
local _allItemsCacheTime = 0

function XPR_UI_RewardItemPicker.Panel:loadAllItems()
	if _allItemsCache and (os.time() - _allItemsCacheTime) < 60 then
		self.allItems = _allItemsCache
	else
		self.allItems = {}
		local sm = getScriptManager and getScriptManager()
		if sm then
			local allScriptItems = sm:getAllItems()
			if allScriptItems then
				for i = 0, allScriptItems:size() - 1 do
					local si = allScriptItems:get(i)
					if si then
						local ft = si:getFullName()
						local dn = si:getDisplayName()
						if ft and EXCLUDED_ITEM_TYPES[ft] then
						elseif dn and string.find(string.lower(dn), "debug", 1, true) then
						elseif ft and string.find(string.lower(ft), "debug", 1, true) then
						elseif ft and dn and dn ~= "" and not si:getObsolete() and not si:isHidden() then
							local cat = XPR_RewardCategoryResolver.resolve(si, ft)
							if cat then
								if XPR_RewardItems.isRandomizedOnGrant(ft) then
									dn = dn .. " (Random)"
								end
								self.allItems[#self.allItems + 1] = {
									fullType = ft, displayName = dn,
									category = cat, checked = false,
									icon = getItemIcon(si) or false,
								}
							end
						end
					end
				end
			end
		end

		for _, id in ipairs(XP_BONUS_IDS) do
			self.allItems[#self.allItems + 1] = {
				fullType = id,
				displayName = "+" .. tostring(XPR_RewardItems.getXpBonusAmount(id)) .. " XP",
				category = "Other", checked = false, icon = xpBonusIcon,
			}
		end

		local vhsIconCache = {}
		for _, entry in ipairs(XPR_RewardItems.getSkillVhsEntries()) do
			local skillId = XPR_RewardItems.buildSkillVhsId(entry)
			local fullType = XPR_RewardItems.getSkillVhsFullType(skillId)
			if fullType then
				if vhsIconCache[fullType] == nil then
					local si = ScriptManager.instance and ScriptManager.instance:getItem(fullType)
					vhsIconCache[fullType] = (si and getItemIcon(si)) or false
				end
				self.allItems[#self.allItems + 1] = {
					fullType = skillId,
					displayName = entry.title,
					category = "Other", checked = false, icon = vhsIconCache[fullType],
				}
			end
		end

		local recipeIconCache = {}
		for _, entry in ipairs(XPR_RewardItems.getRecipeItemEntries()) do
			if recipeIconCache[entry.fullType] == nil then
				local si = ScriptManager.instance and ScriptManager.instance:getItem(entry.fullType)
				recipeIconCache[entry.fullType] = (si and getItemIcon(si)) or false
			end
			self.allItems[#self.allItems + 1] = {
				fullType = entry.id,
				displayName = XPR_RewardItems.getRecipeItemDisplayName(entry.id),
				category = "Other", checked = false, icon = recipeIconCache[entry.fullType],
			}
		end

		table.sort(self.allItems, function(a, b) return a.displayName < b.displayName end)
		_allItemsCache = self.allItems
		_allItemsCacheTime = os.time()
	end

	self._itemByType = {}
	local pendingItems = (self.adminWindow and self.adminWindow.pendingItems) or {}
	for _, item in ipairs(self.allItems) do
		item.checked = pendingItems[item.fullType] ~= nil
		self._itemByType[item.fullType] = item
	end
end

function XPR_UI_RewardItemPicker.Panel:filterItems()
	self.filteredItems = {}
	local searchText = ""
	if self.searchEntry then searchText = string.lower(self.searchEntry:getText() or "") end

	if searchText ~= "" and #searchText < 2 then
		self.lblInfo:setName(getText("IGUI_XPR_RewardPicker_TypeToSearch"))
		self.totalPages = 1
		self.currentPage = 1
		self:showPage()
		return
	end

	for _, item in ipairs(self.allItems) do
		local matchCat = self.activeCategory == "All" or item.category == self.activeCategory
		local matchSearch = searchText == ""
			or string.find(string.lower(item.displayName), searchText, 1, true)
			or string.find(string.lower(item.fullType), searchText, 1, true)
		if matchCat and matchSearch then
			self.filteredItems[#self.filteredItems + 1] = item
		end
	end

	self.totalPages = math.max(1, math.ceil(#self.filteredItems / ITEMS_PER_PAGE))
	self.currentPage = math.min(self.currentPage, self.totalPages)
	self:showPage()
end

function XPR_UI_RewardItemPicker.Panel:showPage()
	self.itemList:clear()
	local startIdx = (self.currentPage - 1) * ITEMS_PER_PAGE + 1
	local endIdx = math.min(startIdx + ITEMS_PER_PAGE - 1, #self.filteredItems)
	for i = startIdx, endIdx do
		local item = self.filteredItems[i]
		local entry = self.itemList:addItem(item.displayName, item)
		entry.height = ROW_H
	end

	if #self.filteredItems > 0 then
		self.lblInfo:setName(#self.filteredItems .. " items")
	else
		self.lblInfo:setName(getText("IGUI_XPR_RewardPicker_NoItems"))
	end

	if self.pageEntry then self.pageEntry:setText(tostring(self.currentPage)) end
	if self.pageLabel then self.pageLabel:setName(getText("IGUI_XPR_Common_PageOf", self.currentPage, self.totalPages)) end
	if self.btnPrev then self.btnPrev.enable = self.currentPage > 1 end
	if self.btnNext then self.btnNext.enable = self.currentPage < self.totalPages end
end

function XPR_UI_RewardItemPicker.Panel:onPrevPage()
	if self.currentPage > 1 then
		self.currentPage = self.currentPage - 1
		self:showPage()
	end
end

function XPR_UI_RewardItemPicker.Panel:onNextPage()
	if self.currentPage < self.totalPages then
		self.currentPage = self.currentPage + 1
		self:showPage()
	end
end

function XPR_UI_RewardItemPicker.Panel:onPageInput()
	local page = tonumber(self.pageEntry:getText()) or 1
	page = math.max(1, math.min(page, self.totalPages))
	self.currentPage = page
	self:showPage()
end

function XPR_UI_RewardItemPicker.Panel:onSelectAll()
	for _, item in ipairs(self.filteredItems or {}) do
		item.checked = true
		if self._itemByType[item.fullType] then self._itemByType[item.fullType].checked = true end
	end
	if self.activeCategory == "All" then
		self.defaultsLoaded = true
		if self.btnToggleDefaults then
			self.btnToggleDefaults:setTitle(getText("IGUI_XPR_RewardPicker_UnloadDefaults"))
		end
	end
	self:showPage()
end

function XPR_UI_RewardItemPicker.Panel:onUnselectAll()
	for _, item in ipairs(self.filteredItems or {}) do
		item.checked = false
		if self._itemByType[item.fullType] then self._itemByType[item.fullType].checked = false end
	end
	if self.activeCategory == "All" then
		self.defaultsLoaded = false
		if self.btnToggleDefaults then
			self.btnToggleDefaults:setTitle(getText("IGUI_XPR_RewardPicker_LoadDefaults"))
		end
	end
	self:showPage()
end

function XPR_UI_RewardItemPicker.Panel:onToggleDefaults()
	local enable = not self.defaultsLoaded

	local defaultIds = {}
	for _, id in ipairs(XPR_RewardItems.COMMON or {}) do defaultIds[id] = true end
	for _, id in ipairs(XPR_RewardItems.UNCOMMON or {}) do defaultIds[id] = true end
	for _, id in ipairs(XPR_RewardItems.RARE or {}) do defaultIds[id] = true end
	for _, id in ipairs(XPR_RewardItems.getDefaultSkillVhsIds and XPR_RewardItems.getDefaultSkillVhsIds() or {}) do
		defaultIds[id] = true
	end

	for _, item in ipairs(self.allItems or {}) do
		if defaultIds[item.fullType] then
			item.checked = enable
			if self._itemByType[item.fullType] then self._itemByType[item.fullType].checked = enable end
		end
	end

	self.defaultsLoaded = enable
	if self.btnToggleDefaults then
		self.btnToggleDefaults:setTitle(enable and getText("IGUI_XPR_RewardPicker_UnloadDefaults") or getText("IGUI_XPR_RewardPicker_LoadDefaults"))
		local tmgr = getTextManager()
		local toggleW = math.max(S(180), tmgr:MeasureStringX(self.btnToggleDefaults.font or FONT_SM,
			self.btnToggleDefaults.title or "") + S(20))
		self.btnToggleDefaults:setWidth(toggleW)
		self.btnToggleDefaults:setX(math.floor(((self._panelW or PICKER_W) - toggleW) / 2))
	end

	self:filterItems()
end

function XPR_UI_RewardItemPicker.Panel:drawItemRow(y, entry, alt)
	local data = entry.item
	local w = self:getWidth()
	if alt then self:drawRect(0, y, w, ROW_H - S(1), 0.25, COL_ROW_ALT.r, COL_ROW_ALT.g, COL_ROW_ALT.b) end

	local checkSize = S(16)
	local checkX = S(14)
	local checkY = y + math.floor((ROW_H - checkSize) / 2)

	local iconX = checkX + checkSize + S(10)
	local iconY = y + S(6)
	local icon = data.icon
	if icon == false then icon = nil end
	if icon then
		self:drawTextureScaled(icon, iconX, iconY, S(28), S(28), 1)
	else
		self:drawRect(iconX, iconY, S(28), S(28), 0.5, 0.3, 0.3, 0.3)
		self:drawRectBorder(iconX, iconY, S(28), S(28), 0.5, 0.5, 0.5, 0.5)
	end

	local textX = iconX + S(36)

	local maxTextW = w - textX - S(8) - getTextManager():MeasureStringX(FONT_SM, "MMM")
	self:drawText(truncateText(data.displayName, FONT_SM, maxTextW), textX, y + S(1),
		0.90, 0.90, 0.90, 0.90, FONT_SM)
	self:drawText(truncateText(data.fullType, FONT_SM, maxTextW), textX, y + S(18),
		COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.60, FONT_SM)

	self:drawRectBorder(checkX, checkY, checkSize, checkSize, 0.6, 0.6, 0.6, 0.6)
	if data.checked then
		self:drawRect(checkX + S(2), checkY + S(2), checkSize - S(4), checkSize - S(4), 1,
			COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
	end
	return y + ROW_H
end

function XPR_UI_RewardItemPicker.Panel.onItemClicked(target, data)
	if not data or not data.fullType then return end
	data.checked = not data.checked
	local panel = target.pickerPanel
	if panel and panel._itemByType and panel._itemByType[data.fullType] then
		panel._itemByType[data.fullType].checked = data.checked
	end
end

function XPR_UI_RewardItemPicker.Panel:onAdd()
	if not self.adminWindow then self:close(); return end
	local added, removed = 0, 0
	local pendingItems = self.adminWindow.pendingItems

	for _, item in ipairs(self.allItems) do
		local inPool = pendingItems[item.fullType] ~= nil
		if item.checked and not inPool then
			local tier = (XPR_RewardItems.getDefaultSkillVhsTier and XPR_RewardItems.getDefaultSkillVhsTier(item.fullType)) or "COMMON"
			pendingItems[item.fullType] = { tier = tier, active = true }
			added = added + 1
		elseif not item.checked and inPool then
			pendingItems[item.fullType] = nil
			removed = removed + 1
		end
	end

	if added > 0 or removed > 0 then
		self.adminWindow.hasUnsavedChanges = true
		self.adminWindow:rebuildItems()
	end
	self:close()
end

function XPR_UI_RewardItemPicker.Panel:onCancel()
	self:close()
end

function XPR_UI_RewardItemPicker.Panel:close()
	self:setVisible(false)
	self:removeFromUIManager()
	XPR_UI_RewardItemPicker.instance = nil
end

function XPR_UI_RewardItemPicker.open(adminWindow)
	if XPR_UI_RewardItemPicker.instance then XPR_UI_RewardItemPicker.instance:close() end
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local winH = math.min(PICKER_H, screenH - 20)
	local x = math.floor((screenW - PICKER_W) / 2)
	local y = math.max(10, math.floor((screenH - winH) / 2))
	local win = XPR_UI_RewardItemPicker.Panel:new(x, y, adminWindow)
	win:setX(math.floor((screenW - win:getWidth()) / 2))
	win:setHeight(winH)
	win:initialise()
	win:addToUIManager()
	win:setTitle(getText("IGUI_XPR_RewardPicker_Title"))
	XPR_UI_RewardItemPicker.instance = win
end

return XPR_UI_RewardItemPicker
