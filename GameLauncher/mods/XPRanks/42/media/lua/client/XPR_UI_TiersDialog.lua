if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "XPR_UI_Scale"
require "XPR_UI_Theme"

XPR_UI_TiersDialog = {}
XPR_UI_TiersDialog.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local FIELD_H = fontHgt + S(5)
local ROW_GAP = S(8)
local SECTION_GAP = S(14)
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local DLG_W = S(360)
local FIELD_W = S(70)
local WEIGHT_LABEL_KEYS = { "IGUI_XPR_Tiers_WeightCommon", "IGUI_XPR_Tiers_WeightUncommon", "IGUI_XPR_Tiers_WeightRare" }
local WEIGHT_KEYS = { "COMMON", "UNCOMMON", "RARE" }

XPR_TiersDialog_Window = ISCollapsableWindow:derive("XPR_TiersDialog_Window")

function XPR_TiersDialog_Window:new(x, y, w, h, currentTiers, callback)
	local o = ISCollapsableWindow.new(self, x, y, w, h)
	o.moveWithMouse = true
	o.resizable = false
	o.currentTiers = currentTiers
	o.callback = callback
	o.maxRankEntries = {}
	o.weightEntries = {}
	o.tierHeaderY = {}
	return o
end

function XPR_TiersDialog_Window:createChildren()
	ISCollapsableWindow.createChildren(self)

	local titleH = fontHgt + S(1)
	local y = titleH + PAD
	local sectionGap = fontHgt + S(6)

	for tierIdx = 1, 3 do
		self.tierHeaderY[tierIdx] = y
		y = y + sectionGap

		if tierIdx < 3 then
			local lbl = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Tiers_MaxRank"),
				COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
			lbl:initialise()
			self:addChild(lbl)

			local current = self.currentTiers[tierIdx].maxRank or (tierIdx == 1 and 99 or 300)
			local entry = ISTextEntryBox:new(tostring(current), self.width - PAD - FIELD_W, y, FIELD_W, FIELD_H)
			entry:initialise()
			entry:instantiate()
			entry:setOnlyNumbers(true)
			self:addChild(entry)
			self.maxRankEntries[tierIdx] = entry

			y = y + FIELD_H + ROW_GAP
		end

		self.weightEntries[tierIdx] = {}
		for i, key in ipairs(WEIGHT_KEYS) do
			local lbl = ISLabel:new(PAD, y + S(3), fontHgt, getText(WEIGHT_LABEL_KEYS[i]),
				COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
			lbl:initialise()
			self:addChild(lbl)

			local fraction = (self.currentTiers[tierIdx].weights and self.currentTiers[tierIdx].weights[key]) or 0
			local pct = math.floor(fraction * 100 + 0.5)
			local entry = ISTextEntryBox:new(tostring(pct), self.width - PAD - FIELD_W, y, FIELD_W, FIELD_H)
			entry:initialise()
			entry:instantiate()
			entry:setOnlyNumbers(true)
			self:addChild(entry)
			self.weightEntries[tierIdx][key] = entry

			y = y + FIELD_H + ROW_GAP
		end

		y = y + SECTION_GAP - ROW_GAP
	end

	y = y + S(4)

	local btnPad = S(12)
	local saveW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Save"), S(100), btnPad)
	local cancelW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_Cancel"), S(100), btnPad)
	self.btnSave = ISButton:new(PAD, y, saveW, BTN_H, getText("IGUI_XPR_Common_Save"), self, XPR_TiersDialog_Window.onSave)
	self.btnSave:initialise()
	self.btnSave:instantiate()
	self.btnSave:enableAcceptColor()
	self:addChild(self.btnSave)

	self.btnCancel = ISButton:new(self.width - PAD - cancelW, y, cancelW, BTN_H,
		getText("IGUI_XPR_ValueDialog_Cancel"), self, XPR_TiersDialog_Window.close)
	self.btnCancel:initialise()
	self.btnCancel:instantiate()
	self.btnCancel:enableCancelColor()
	self:addChild(self.btnCancel)

	self:setHeight(y + BTN_H + PAD)
end

function XPR_TiersDialog_Window:initialise()
	ISCollapsableWindow.initialise(self)
end

function XPR_TiersDialog_Window:prerender()
	ISCollapsableWindow.prerender(self)
	local tmgr = getTextManager()
	local maxRank = (XPR_RankCurve and XPR_RankCurve.MAX_RANK) or 999
	local labels = {
		getText("IGUI_XPR_Tiers_Tier1Header"),
		getText("IGUI_XPR_Tiers_Tier2Header"),
		getText("IGUI_XPR_Tiers_Tier3Header", maxRank),
	}
	for tierIdx = 1, 3 do
		local text = labels[tierIdx]
		local strW = tmgr:MeasureStringX(FONT, text)
		local hdrX = math.floor((self.width - strW) / 2)
		self:drawText(text, hdrX, self.tierHeaderY[tierIdx],
			COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 1, FONT)
	end
end

function XPR_TiersDialog_Window:onSave()
	local t1Max = math.max(1, math.floor(tonumber(self.maxRankEntries[1]:getText()) or 99))
	local t2Max = math.max(t1Max + 1, math.floor(tonumber(self.maxRankEntries[2]:getText()) or 300))

	local tierWeights = {}
	for tierIdx = 1, 3 do
		local common = math.max(0, tonumber(self.weightEntries[tierIdx].COMMON:getText()) or 0)
		local uncommon = math.max(0, tonumber(self.weightEntries[tierIdx].UNCOMMON:getText()) or 0)
		local rare = math.max(0, tonumber(self.weightEntries[tierIdx].RARE:getText()) or 0)
		local total = common + uncommon + rare
		if total <= 0 then
			local existing = self.currentTiers[tierIdx].weights or {}
			tierWeights[tierIdx] = {
				COMMON = existing.COMMON or 0,
				UNCOMMON = existing.UNCOMMON or 0,
				RARE = existing.RARE or 0,
			}
		else
			tierWeights[tierIdx] = {
				COMMON = common / total,
				UNCOMMON = uncommon / total,
				RARE = rare / total,
			}
		end
	end

	if self.callback then
		self.callback({ tier1MaxRank = t1Max, tier2MaxRank = t2Max, tierWeights = tierWeights })
	end
	self:close()
end

function XPR_TiersDialog_Window:close()
	self:setVisible(false)
	self:removeFromUIManager()
	XPR_UI_TiersDialog.instance = nil
end

function XPR_UI_TiersDialog.open(currentTiers, callback)
	if XPR_UI_TiersDialog.instance then
		XPR_UI_TiersDialog.instance:close()
	end
	local screenW = getPlayerScreenWidth(0)
	local screenH = getPlayerScreenHeight(0)
	local btnPad = S(12)
	local saveW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Save"), S(100), btnPad)
	local cancelW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_Cancel"), S(100), btnPad)
	local labelW = XPR_UI_Scale.longestText(FONT, {
		getText("IGUI_XPR_Tiers_MaxRank"),
		getText("IGUI_XPR_Tiers_WeightCommon"),
		getText("IGUI_XPR_Tiers_WeightUncommon"),
		getText("IGUI_XPR_Tiers_WeightRare"),
	})
	local maxRank = (XPR_RankCurve and XPR_RankCurve.MAX_RANK) or 999
	local headerW = XPR_UI_Scale.longestText(FONT, {
		getText("IGUI_XPR_Tiers_Tier1Header"),
		getText("IGUI_XPR_Tiers_Tier2Header"),
		getText("IGUI_XPR_Tiers_Tier3Header", maxRank),
	})
	local needed = math.max(
		PAD * 2 + labelW + S(10) + FIELD_W,
		PAD * 2 + headerW,
		PAD * 2 + saveW + S(10) + cancelW,
		XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Tiers_Title")) + BTN_H + PAD * 2)
	local dlgW = math.max(DLG_W, needed)
	local dlgH = S(560)
	local x = math.floor((screenW - dlgW) / 2)
	local y = math.floor((screenH - dlgH) / 2)

	local win = XPR_TiersDialog_Window:new(x, y, dlgW, dlgH, currentTiers, callback)
	win:initialise()
	win:instantiate()
	win:addToUIManager()
	win:setTitle(getText("IGUI_XPR_Tiers_Title"))
	XPR_UI_TiersDialog.instance = win
	win:setVisible(true)
end

return XPR_UI_TiersDialog
