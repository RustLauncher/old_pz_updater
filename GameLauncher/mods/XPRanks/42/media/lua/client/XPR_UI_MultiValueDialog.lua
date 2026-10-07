if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "XPR_UI_Scale"
require "XPR_UI_Theme"

XPR_UI_MultiValueDialog = {}
XPR_UI_MultiValueDialog.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local FIELD_H = fontHgt + S(5)
local ROW_GAP = S(10)
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local PANEL_W_MIN = S(320)
local FIELD_W = S(70)

local DIVIDER_H = fontHgt + S(10) + 3

local function rowHeight(f)
	if f.divider then return DIVIDER_H end
	return FIELD_H + ROW_GAP
end

local function computeDialogSize(fields)
	local tmgr = getTextManager()
	local maxLabelW = 0
	local rowsH = 0
	for _, f in ipairs(fields) do
		local w = tmgr:MeasureStringX(FONT, f.label)
		if w > maxLabelW then maxLabelW = w end
		rowsH = rowsH + rowHeight(f)
	end
	local btnPad = S(12)
	local saveW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Save"), S(100), btnPad)
	local cancelW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_Cancel"), S(100), btnPad)
	local dlgW = math.max(
		PANEL_W_MIN,
		PAD * 3 + maxLabelW + FIELD_W,
		PAD * 2 + saveW + S(10) + cancelW)
	local titleH = fontHgt + S(1)
	local dlgH = titleH + PAD + rowsH + S(4) + BTN_H + PAD
	return dlgW, dlgH
end

XPR_MultiValueDialog_Window = ISCollapsableWindow:derive("XPR_MultiValueDialog_Window")

function XPR_MultiValueDialog_Window:new(x, y, w, h, fields, currentValues, callback)
	local o = ISCollapsableWindow.new(self, x, y, w, h)
	o.moveWithMouse = true
	o.resizable = false
	o.fieldsDef = fields
	o.currentValues = currentValues or {}
	o.callback = callback
	o.entries = {}
	return o
end

function XPR_MultiValueDialog_Window:createChildren()
	ISCollapsableWindow.createChildren(self)

	local titleH = fontHgt + S(1)
	local y = titleH + PAD

	self.dividerLineYs = {}

	for _, f in ipairs(self.fieldsDef) do
		if f.divider then
			self.dividerLineYs[#self.dividerLineYs + 1] = y + S(2) + 3

			local dividerLblW = getTextManager():MeasureStringX(FONT, f.label)
			local dividerLbl = ISLabel:new((self.width - dividerLblW) / 2, y + S(5) + 3, fontHgt, f.label,
				COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 1, FONT, true)
			dividerLbl:initialise()
			self:addChild(dividerLbl)
		else
			local lbl = ISLabel:new(PAD, y + S(3), fontHgt, f.label,
				COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
			lbl:initialise()
			self:addChild(lbl)

			local val = self.currentValues[f.key]
			if type(val) ~= "number" then val = f.default end
			local entry = ISTextEntryBox:new(tostring(val), self.width - PAD - FIELD_W, y, FIELD_W, FIELD_H)
			entry:initialise()
			entry:instantiate()
			entry:setOnlyNumbers(true)
			entry.tooltip = getText("IGUI_XPR_ValueDialog_MinMaxDefault", f.min, f.max, f.default)
			self:addChild(entry)
			self.entries[f.key] = entry
		end

		y = y + rowHeight(f)
	end
	y = y + S(4)

	local btnPad = S(12)
	local saveW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Save"), S(100), btnPad)
	local cancelW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_Cancel"), S(100), btnPad)
	self.btnSave = ISButton:new(PAD, y, saveW, BTN_H,
		getText("IGUI_XPR_Common_Save"), self, XPR_MultiValueDialog_Window.onSave)
	self.btnSave:initialise()
	self.btnSave:instantiate()
	self.btnSave:enableAcceptColor()
	self:addChild(self.btnSave)

	self.btnCancel = ISButton:new(self.width - PAD - cancelW, y, cancelW, BTN_H,
		getText("IGUI_XPR_ValueDialog_Cancel"), self, XPR_MultiValueDialog_Window.close)
	self.btnCancel:initialise()
	self.btnCancel:instantiate()
	self.btnCancel:enableCancelColor()
	self:addChild(self.btnCancel)
end

function XPR_MultiValueDialog_Window:initialise()
	ISCollapsableWindow.initialise(self)
end

function XPR_MultiValueDialog_Window:prerender()
	ISCollapsableWindow.prerender(self)
	if not self.dividerLineYs then return end
	for _, lineY in ipairs(self.dividerLineYs) do
		self:drawRect(S(5), lineY, self.width - S(10), S(1),
			1, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
	end
end

function XPR_MultiValueDialog_Window:onSave()
	local values = {}
	for _, f in ipairs(self.fieldsDef) do
		if not f.divider then
			local entry = self.entries[f.key]
			local val = tonumber(entry:getText()) or f.default
			val = math.max(f.min, math.min(f.max, math.floor(val)))
			values[f.key] = val
		end
	end
	if self.callback then self.callback(values) end
	self:close()
end

function XPR_MultiValueDialog_Window:close()
	self:setVisible(false)
	self:removeFromUIManager()
	XPR_UI_MultiValueDialog.instance = nil
end

function XPR_UI_MultiValueDialog.open(title, fields, currentValues, callback)
	if XPR_UI_MultiValueDialog.instance then
		XPR_UI_MultiValueDialog.instance:close()
	end
	local screenW = getPlayerScreenWidth(0)
	local screenH = getPlayerScreenHeight(0)
	local w, h = computeDialogSize(fields)
	local x = math.floor((screenW - w) / 2)
	local y = math.floor((screenH - h) / 2)

	local win = XPR_MultiValueDialog_Window:new(x, y, w, h, fields, currentValues, callback)
	win:initialise()
	win:instantiate()
	win:addToUIManager()
	win:setTitle(title)
	XPR_UI_MultiValueDialog.instance = win
	win:setVisible(true)
end

return XPR_UI_MultiValueDialog
