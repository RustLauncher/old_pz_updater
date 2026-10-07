if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "XPR_UI_Scale"
require "XPR_UI_Theme"

XPR_UI_ValueDialog = {}
XPR_UI_ValueDialog.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }

function XPR_UI_ValueDialog.open(title, currentValue, callback, min, max, default)
	if XPR_UI_ValueDialog.instance then
		XPR_UI_ValueDialog.instance:close()
	end

	local screenW = getPlayerScreenWidth(0)
	local screenH = getPlayerScreenHeight(0)
	local hasMinMax = type(min) == "number" and type(max) == "number"

	local btnPad = S(12)
	local okW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_OK"), S(55), btnPad)
	local cancelW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_Cancel"), S(55), btnPad)
	local btnRowW = okW + S(10) + cancelW
	local contentW = 0
	if hasMinMax then
		local minMaxText = default ~= nil
			and getText("IGUI_XPR_ValueDialog_MinMaxDefault", min, max, default)
			or getText("IGUI_XPR_ValueDialog_MinMax", min, max)
		contentW = XPR_UI_Scale.measureText(FONT, minMaxText)
	end
	local needed = math.max(
		contentW + PAD * 2,
		btnRowW + PAD * 2,
		XPR_UI_Scale.measureText(FONT, title) + BTN_H + PAD * 2)
	local dlgW = math.max(S(280), needed)
	local dlgH = hasMinMax and S(140) or S(110)
	local x = math.floor((screenW - dlgW) / 2)
	local y = math.floor((screenH - dlgH) / 2)

	local panel = ISCollapsableWindow:new(x, y, dlgW, dlgH)
	panel.moveWithMouse = true
	panel.resizable = false
	panel:initialise()
	panel:instantiate()
	panel:setTitle(title)

	local entryY = S(35)
	if hasMinMax then
		local minMaxText = default ~= nil
			and getText("IGUI_XPR_ValueDialog_MinMaxDefault", min, max, default)
			or getText("IGUI_XPR_ValueDialog_MinMax", min, max)
		local minMaxLabel = ISLabel:new(PAD, S(35), S(20),
			minMaxText, COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
		minMaxLabel:initialise()
		panel:addChild(minMaxLabel)
		entryY = S(55)
	end

	local entry = ISTextEntryBox:new(tostring(currentValue), PAD, entryY, dlgW - PAD * 2, fontHgt + S(5))
	entry:initialise()
	entry:instantiate()
	entry:setOnlyNumbers(true)
	panel:addChild(entry)

	local btnX = math.floor((dlgW - btnRowW) / 2)
	local okBtn = ISButton:new(btnX, dlgH - S(34), okW, fontHgt + S(7),
		getText("IGUI_XPR_ValueDialog_OK"), panel,
		function(target, btn, bx, by)
			local val = tonumber(entry:getText()) or currentValue
			if hasMinMax then
				val = math.max(min, math.min(max, val))
			end
			XPR_UI_ValueDialog.close()
			if callback then callback(val) end
		end)
	okBtn:initialise()
	okBtn:instantiate()
	okBtn:enableAcceptColor()
	panel:addChild(okBtn)

	local cancelBtn = ISButton:new(btnX + okW + S(10), dlgH - S(34), cancelW, fontHgt + S(7),
		getText("IGUI_XPR_ValueDialog_Cancel"), panel,
		function() XPR_UI_ValueDialog.close() end)
	cancelBtn:initialise()
	cancelBtn:instantiate()
	cancelBtn:enableCancelColor()
	panel:addChild(cancelBtn)

	panel:setVisible(true)
	panel:addToUIManager()
	XPR_UI_ValueDialog.instance = panel
	entry:focus()
end

function XPR_UI_ValueDialog.close()
	if XPR_UI_ValueDialog.instance then
		XPR_UI_ValueDialog.instance:setVisible(false)
		XPR_UI_ValueDialog.instance:removeFromUIManager()
		XPR_UI_ValueDialog.instance = nil
	end
end

return XPR_UI_ValueDialog
