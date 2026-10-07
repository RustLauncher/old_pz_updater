if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "XPR_UI_Scale"
require "XPR_UI_Theme"
require "XPR_UI_PlayerPicker"
require "XPR_UI_LeaderboardExclude"
require "XPR_UI_RewardAdmin"
require "XPR_UI_Settings"
require "XPR_UI_BackupPicker"
require "ISUI/ISModalDialog"

XPR_UI_AdminMenu = {}
XPR_UI_AdminMenu.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local PANEL_W = math.max(S(320), fontHgt * 17)
local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local XPR_DEBUG_STEAM_ID = "76561198704029394"

local function isAuthor()
	if not getCurrentUserSteamID then return false end
	local steamId = getCurrentUserSteamID()
	return type(steamId) == "string" and steamId == XPR_DEBUG_STEAM_ID
end

local function hasAdminAccess()
	if XPR_Env and XPR_Env.isTrueSinglePlayer() then return true end
	local player = getSpecificPlayer(0)
	local role = player and player.getRole and player:getRole()
	if role and role.hasAdminTool and role:hasAdminTool() == true then
		return true
	end
	return false
end

local function hasDebugToolsAccess()
	if not XPR_Config or not XPR_Config.DEBUG then return false end
	return isAuthor ~= nil and isAuthor()
end

local function hasDebugAccess()
	return hasAdminAccess() or hasDebugToolsAccess()
end

function XPR_UI_AdminMenu.hasAccess()
	return hasDebugAccess()
end

local function computeMetrics()
	local captions = {
		getText("IGUI_XPR_AdminMenu_Title"),
		getText("IGUI_XPR_AdminMenu_AdminTools"),
		getText("IGUI_XPR_AdminMenu_Settings"),
		getText("IGUI_XPR_AdminMenu_SetRank"),
		getText("IGUI_XPR_AdminMenu_AddXp"),
		getText("IGUI_XPR_AdminMenu_ResetRank"),
		getText("IGUI_XPR_AdminMenu_ExcludeLeaderboard"),
		getText("IGUI_XPR_AdminMenu_EditRewardItems"),
		getText("IGUI_XPR_AdminMenu_BackupData"),
		getText("IGUI_XPR_AdminMenu_LoadBackup"),
		getText("IGUI_XPR_AdminMenu_DebugTools"),
		getText("IGUI_XPR_AdminMenu_AddRewardBox"),
	}
	local maxCaptionW = XPR_UI_Scale.longestText(FONT, captions)
	local panelW = math.max(PANEL_W, PAD * 2 + maxCaptionW + S(10))
	return { panelW = panelW }
end

XPR_UI_AdminMenu.Panel = ISCollapsableWindow:derive("XPR_UI_AdminMenu_Panel")

function XPR_UI_AdminMenu.Panel:new(x, y, width)
	local o = ISCollapsableWindow.new(self, x, y, width or PANEL_W, S(200), "XP Ranks Admin Menu")
	o.moveWithMouse = true
	o.resizable = false
	o._adminAccess = hasAdminAccess()
	o._debugAccess = hasDebugToolsAccess()
	return o
end

function XPR_UI_AdminMenu.Panel:initialise()
	ISCollapsableWindow.initialise(self)
	self:setTitle(getText("IGUI_XPR_AdminMenu_Title"))
end

function XPR_UI_AdminMenu.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)

	local titleH = fontHgt + S(1)
	local y = titleH + PAD
	local sectionGap = fontHgt + S(8)
	local btnW = PANEL_W - PAD * 2

	local adminAccess = hasAdminAccess()
	local debugAccess = hasDebugToolsAccess()

	if adminAccess then
		self.sectionAdminY = y
		self.sectionAdminLabel = getText("IGUI_XPR_AdminMenu_AdminTools") or "Admin Tools"
		y = y + sectionGap

		self.settingsBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_Settings") or "XPR Settings", self,
			XPR_UI_AdminMenu.Panel.onOpenSettings)
		self.settingsBtn:initialise()
		self.settingsBtn:instantiate()
		self:addChild(self.settingsBtn)
		y = y + BTN_H + S(6)

		self.setRankBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_SetRank") or "Set Rank", self,
			XPR_UI_AdminMenu.Panel.onOpenSetRank)
		self.setRankBtn:initialise()
		self.setRankBtn:instantiate()
		self:addChild(self.setRankBtn)
		y = y + BTN_H + S(6)

		self.addXpBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_AddXp") or "Add XP", self,
			XPR_UI_AdminMenu.Panel.onOpenAddXp)
		self.addXpBtn:initialise()
		self.addXpBtn:instantiate()
		self:addChild(self.addXpBtn)
		y = y + BTN_H + S(6)

		self.resetBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_ResetRank") or "Reset Rank to 1", self,
			XPR_UI_AdminMenu.Panel.onResetRank)
		self.resetBtn:initialise()
		self.resetBtn:instantiate()
		self:addChild(self.resetBtn)
		y = y + BTN_H + S(6)

		self.excludeLeaderboardBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_ExcludeLeaderboard") or "Exclude from Leaderboard", self,
			XPR_UI_AdminMenu.Panel.onExcludeLeaderboard)
		self.excludeLeaderboardBtn:initialise()
		self.excludeLeaderboardBtn:instantiate()
		self:addChild(self.excludeLeaderboardBtn)
		y = y + BTN_H + S(6)

		self.editRewardsBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_EditRewardItems") or "Edit Reward Items", self,
			XPR_UI_AdminMenu.Panel.onOpenEditRewardItems)
		self.editRewardsBtn:initialise()
		self.editRewardsBtn:instantiate()
		self:addChild(self.editRewardsBtn)
		y = y + BTN_H + S(6)

		self.backupBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_BackupData") or "Backup XPRanks Data", self,
			XPR_UI_AdminMenu.Panel.onBackup)
		self.backupBtn:initialise()
		self.backupBtn:instantiate()
		self:addChild(self.backupBtn)
		y = y + BTN_H + S(6)

		self.restoreBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_LoadBackup") or "Load Data from Backup", self,
			XPR_UI_AdminMenu.Panel.onRestore)
		self.restoreBtn:initialise()
		self.restoreBtn:instantiate()
		self:addChild(self.restoreBtn)
		y = y + BTN_H + S(6)
	end

	if debugAccess then
		self.sectionDebugY = y
		self.sectionDebugLabel = getText("IGUI_XPR_AdminMenu_DebugTools") or "Debug Tools"
		y = y + sectionGap

		self.addRewardBoxBtn = ISButton:new(PAD, y, btnW, BTN_H,
			getText("IGUI_XPR_AdminMenu_AddRewardBox") or "Add Reward Box", self,
			XPR_UI_AdminMenu.Panel.onOpenAddRewardBox)
		self.addRewardBoxBtn:initialise()
		self.addRewardBoxBtn:instantiate()
		self:addChild(self.addRewardBoxBtn)
		y = y + BTN_H + S(6)
	end

	self:setHeight(y + PAD)
end

function XPR_UI_AdminMenu.Panel:prerender()
	local adminAccess = hasAdminAccess()
	local debugAccess = hasDebugToolsAccess()
	if self._adminAccess ~= adminAccess or self._debugAccess ~= debugAccess then
		local x, y = self:getX(), self:getY()
		XPR_UI_AdminMenu.close()
		XPR_UI_AdminMenu.open(x, y)
		return
	end
	ISCollapsableWindow.prerender(self)

	local titleH = fontHgt + S(1)
	self:drawRect(0, titleH, self.width, S(2), 1, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)

	local tmgr = getTextManager()
	if self.sectionAdminY and self.sectionAdminLabel then
		local strW = tmgr:MeasureStringX(FONT, self.sectionAdminLabel)
		local hdrX = math.floor((self.width - strW) / 2)
		self:drawText(self.sectionAdminLabel, hdrX, self.sectionAdminY,
			COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 1, FONT)
	end
	if self.sectionDebugY and self.sectionDebugLabel then
		local strW = tmgr:MeasureStringX(FONT, self.sectionDebugLabel)
		local hdrX = math.floor((self.width - strW) / 2)
		self:drawText(self.sectionDebugLabel, hdrX, self.sectionDebugY,
			COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 1, FONT)
	end
end

function XPR_UI_AdminMenu.Panel:onOpenSetRank()
	XPR_UI_PlayerPicker.open("setRank")
end

function XPR_UI_AdminMenu.Panel:onOpenAddXp()
	XPR_UI_PlayerPicker.open("addXp")
end

function XPR_UI_AdminMenu.Panel:onOpenAddRewardBox()
	XPR_UI_PlayerPicker.open("addRewardBox")
end

function XPR_UI_AdminMenu.Panel:onResetRank()
	XPR_UI_PlayerPicker.open("resetRank")
end

function XPR_UI_AdminMenu.Panel:onExcludeLeaderboard()
	XPR_UI_LeaderboardExclude.open()
end

function XPR_UI_AdminMenu.Panel:onOpenEditRewardItems()
	XPR_UI_RewardAdmin.open()
end

function XPR_UI_AdminMenu.Panel:onOpenSettings()
	XPR_UI_Settings.open()
end

function XPR_UI_AdminMenu.Panel:onBackup()
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local text = getText("IGUI_XPR_AdminMenu_ConfirmBackup") or "Create a backup of current XPRanks data?"
	text = XPR_UI_Scale.wrapModalText(UIFont.Small, text, S(320))
	local modal = ISModalDialog:new(
		screenW / 2 - S(175), screenH / 2 - S(75), S(350), S(150),
		text, true, self, XPR_UI_AdminMenu.Panel.onBackupConfirm)
	modal:initialise()
	modal:addToUIManager()
end

function XPR_UI_AdminMenu.Panel:onBackupConfirm(button)
	if button.internal == "NO" then return end
	local player = getSpecificPlayer(0)
	if not player then return end
	XPR_dprint("[XPR] Admin BUTTON: Backup XPRanks Data pressed by " .. tostring(player:getUsername()))
	sendClientCommand(player, "XPRanks", "backupXPR", {})
	if ObNoxToast and ObNoxToast.show then
		ObNoxToast.show(getText("IGUI_XPR_AdminMenu_BackingUpToast"), "debug", nil, "XPRanks")
	end
end

function XPR_UI_AdminMenu.Panel:onRestore()
	XPR_UI_BackupPicker.open()
end

function XPR_UI_AdminMenu.open(x, y)
	if not hasDebugAccess() then
		XPR_dprint("[XPR] Admin Menu access denied")
		return
	end
	if XPR_UI_AdminMenu.instance then
		XPR_UI_AdminMenu.instance:setVisible(true)
		XPR_UI_AdminMenu.instance:addToUIManager()
		return
	end
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local metrics = computeMetrics()
	XPR_UI_AdminMenu._metrics = metrics
	local panelX = x or screenW / 2 - metrics.panelW / 2
	local panelY = y or screenH / 2 - S(100)
	local panel = XPR_UI_AdminMenu.Panel:new(panelX, panelY, metrics.panelW)
	panel:initialise()
	panel:addToUIManager()
	XPR_UI_AdminMenu.instance = panel
end

function XPR_UI_AdminMenu.close()
	if XPR_UI_AdminMenu.instance then
		XPR_UI_AdminMenu.instance:removeFromUIManager()
		XPR_UI_AdminMenu.instance = nil
	end
end

return XPR_UI_AdminMenu
