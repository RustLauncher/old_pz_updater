if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "XPR_UI_Scale"
require "XPR_UI_Theme"

XPR_UI_BackupPicker = {}
XPR_UI_BackupPicker.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local BPICKER_W = S(480)
local BPICKER_H = S(420)

local function truncateText(text, font, maxWidth)
	if not text or not font then return text or "" end
	local tmgr = getTextManager()
	if tmgr:MeasureStringX(font, text) <= maxWidth then return text end
	while #text > 0 and tmgr:MeasureStringX(font, text .. "...") > maxWidth do
		text = string.sub(text, 1, #text - 1)
	end
	return text .. "..."
end

XPR_BackupPicker_Window = ISCollapsableWindow:derive("XPR_BackupPicker_Window")

function XPR_BackupPicker_Window:new(x, y)
	local panelW = math.max(BPICKER_W,
		PAD * 2 + XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Common_Load")) + S(24),
		PAD * 2 + XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_BackupPicker_Title")) + BTN_H + PAD * 2)
	local promptLines = XPR_UI_Scale.wrapLines(FONT,
		getText("IGUI_XPR_BackupPicker_SelectPrompt"), panelW - PAD * 2)
	local extraLines = math.max(0, #promptLines - 1)
	local panelH = BPICKER_H + extraLines * fontHgt

	local o = ISCollapsableWindow.new(self, x, y, panelW, panelH)
	o.moveWithMouse = true
	o.resizable = false
	o.promptLines = promptLines
	return o
end

function XPR_BackupPicker_Window:createChildren()
	ISCollapsableWindow.createChildren(self)

	local titleH = fontHgt + S(1)
	local y = titleH + PAD

	for _, line in ipairs(self.promptLines) do
		local lbl = ISLabel:new(PAD, y, S(20), line, COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + fontHgt
	end
	y = y + S(5)

	local listH = self:getHeight() - y - S(24) - BTN_H - PAD - S(20)
	self.fileList = ISScrollingListBox:new(PAD, y, self.width - PAD * 2, listH)
	self.fileList:initialise()
	self.fileList:instantiate()
	self.fileList.itemheight = fontHgt + S(9)
	self.fileList.doDrawItem = XPR_BackupPicker_Window.drawFileItem
	self.fileList:setOnMouseDownFunction(self, XPR_BackupPicker_Window.onFileSelected)
	self:addChild(self.fileList)
	y = y + listH + S(8)

	self.lblPreview = ISLabel:new(PAD, y, S(20), getText("IGUI_XPR_BackupPicker_NoneSelected"), COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	self.lblPreview:initialise()
	self:addChild(self.lblPreview)
	y = y + S(24)

	self.btnLoad = ISButton:new(PAD, y, self.width - PAD * 2, BTN_H, getText("IGUI_XPR_Common_Load"), self, XPR_BackupPicker_Window.onLoad)
	self.btnLoad:initialise()
	self.btnLoad:instantiate()
	self.btnLoad.enable = false
	self:addChild(self.btnLoad)

	self.selectedFile = nil
	self:refreshList()
end

function XPR_BackupPicker_Window:initialise()
	ISCollapsableWindow.initialise(self)
end

function XPR_BackupPicker_Window:refreshList()
	self.fileList:clear()
	self.selectedFile = nil
	if self.btnLoad then self.btnLoad.enable = false end
	if self.lblPreview then self.lblPreview:setName(getText("IGUI_XPR_BackupPicker_NoneSelected")) end
	local player = getSpecificPlayer(0)
	if player then
		sendClientCommand(player, "XPRanks", "getBackupList", {})
	end
end

function XPR_BackupPicker_Window:populateList(backups)
	self.fileList:clear()
	self.selectedFile = nil
	if self.btnLoad then self.btnLoad.enable = false end
	if self.lblPreview then self.lblPreview:setName(getText("IGUI_XPR_BackupPicker_NoneSelected")) end

	if not backups or #backups == 0 then
		if self.lblPreview then self.lblPreview:setName(getText("IGUI_XPR_BackupPicker_NoneFound")) end
		return
	end
	if self.lblPreview then self.lblPreview:setName(getText("IGUI_XPR_BackupPicker_SelectPrompt")) end

	local autoSave = nil
	local manual = {}
	for _, entry in ipairs(backups) do
		if entry.filename:find("auto_backup") then
			autoSave = entry
		else
			manual[#manual + 1] = entry
		end
	end

	if autoSave then
		self.fileList:addItem(getText("IGUI_XPR_BackupPicker_AutoSave"), { filename = autoSave.filename, timestamp = autoSave.timestamp, isAuto = true })
	end
	for _, entry in ipairs(manual) do
		self.fileList:addItem(entry.filename, { filename = entry.filename, timestamp = entry.timestamp })
	end
end

function XPR_BackupPicker_Window:drawFileItem(y, item, alt)
	local data = item.item
	if not data then return y + fontHgt + S(9) end
	local isAuto = data.isAuto
	local label = isAuto and getText("IGUI_XPR_BackupPicker_AutoSave") or (item.name or data.filename or "?")
	local h = self.itemheight or (fontHgt + S(9))
	local w = self:getWidth()

	self:drawRect(0, y, w, h, 1, 0.08, 0.08, 0.08)
	if self.selected == item.index then
		self:drawRect(0, y, w, h, 0.3, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
	end

	label = truncateText(label, UIFont.Small, w - S(16))
	if isAuto then
		self:drawText(label, S(8), y + S(6), COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 1, UIFont.Small)
	else
		self:drawText(label, S(8), y + S(6), 1, 1, 1, 1, UIFont.Small)
	end

	return y + h
end

function XPR_BackupPicker_Window.onFileSelected(target, data)
	if not data or not data.filename then return end
	target.selectedFile = data.filename
	if target.btnLoad then target.btnLoad.enable = true end
	if target.lblPreview then target.lblPreview:setName(data.filename) end
end

function XPR_BackupPicker_Window.onLoad(target)
	if not target.selectedFile then return end
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local text = XPR_UI_Scale.wrapModalText(UIFont.Small,
		getText("IGUI_XPR_BackupPicker_LoadConfirm"), S(320))
	local modal = ISModalDialog:new(
		screenW / 2 - S(175), screenH / 2 - S(75), S(350), S(150),
		text, true, target, XPR_BackupPicker_Window.onLoadConfirm)
	modal:initialise()
	modal:addToUIManager()
end

function XPR_BackupPicker_Window.onLoadConfirm(target, button)
	if button.internal == "NO" then return end
	if not target.selectedFile then return end
	local player = getSpecificPlayer(0)
	if not player then return end
	XPR_dprint("[XPR] Admin: Load XPRanks Data from Backup: " .. target.selectedFile)
	sendClientCommand(player, "XPRanks", "restoreXPR", { filename = target.selectedFile })
	if ObNoxToast and ObNoxToast.show then
		ObNoxToast.show(getText("IGUI_XPR_BackupPicker_RestoringToast"), "debug", nil, "XPRanks")
	end
	target:close()
end

function XPR_BackupPicker_Window:prerender()
	ISCollapsableWindow.prerender(self)
end

function XPR_BackupPicker_Window:close()
	ISCollapsableWindow.close(self)
	if XPR_UI_AdminMenu and XPR_UI_AdminMenu.instance then
		XPR_UI_AdminMenu.instance:setVisible(true)
	end
end

function XPR_UI_BackupPicker.open()
	local player = getSpecificPlayer(0)
	if not player then return end

	if XPR_UI_BackupPicker.instance then
		XPR_UI_BackupPicker.instance:setVisible(true)
		XPR_UI_BackupPicker.instance:refreshList()
		return
	end

	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local x = math.floor((screenW - BPICKER_W) / 2)
	local y = math.floor((screenH - BPICKER_H) / 2)

	local win = XPR_BackupPicker_Window:new(x, y)
	win:initialise()
	win:setX(math.floor((screenW - win:getWidth()) / 2))
	win:setY(math.floor((screenH - win:getHeight()) / 2))
	win:instantiate()
	win:setTitle(getText("IGUI_XPR_BackupPicker_Title"))
	win:addToUIManager()
	win:setVisible(true)

	XPR_UI_BackupPicker.instance = win
end

function XPR_UI_BackupPicker.close()
	if XPR_UI_BackupPicker.instance then
		XPR_UI_BackupPicker.instance:close()
	end
end

function XPR_UI_BackupPicker.onBackupList(backups)
	if XPR_UI_BackupPicker.instance then
		XPR_UI_BackupPicker.instance:populateList(backups)
	end
end

return XPR_UI_BackupPicker
