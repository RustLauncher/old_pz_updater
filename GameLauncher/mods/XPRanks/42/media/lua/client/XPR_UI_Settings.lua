if isServer() and not isClient() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "XPR_UI_Scale"
require "XPR_UI_Theme"
require "XPR_UI_MultiValueDialog"
require "XPR_UI_TiersDialog"

XPR_UI_Settings = {}
XPR_UI_Settings.instance = nil

local S = XPR_UI_Scale.s
local FONT = XPR_UI_Scale.FONT_SM
local fontHgt = XPR_UI_Scale.fontHgt
local PAD = math.floor(fontHgt * 0.75)
local BTN_H = fontHgt + S(13)
local EDIT_BTN_W = S(80)
local ROW_GAP = S(10)
local COL_TEXT = { r = 0.90, g = 0.90, b = 0.90 }
local COL_ACCENT = XPR_UI_Theme.COL_ACCENT
local PANEL_W = math.max(S(340), fontHgt * 18)

local CATEGORY_ORDER = {
	"Combat - Firearms", "Combat - Melee", "Crafting", "Farming", "Physical", "Survival",
}

local CATEGORY_LABEL_KEY = {
	["Combat - Firearms"] = "IGUI_XPR_SettingsCat_CombatFirearms",
	["Combat - Melee"] = "IGUI_XPR_SettingsCat_CombatMelee",
	["Crafting"] = "IGUI_XPR_SettingsCat_Crafting",
	["Farming"] = "IGUI_XPR_SettingsCat_Farming",
	["Physical"] = "IGUI_XPR_SettingsCat_Physical",
	["Survival"] = "IGUI_XPR_SettingsCat_Survival",
}

local synced = nil

function XPR_UI_Settings.applySyncedSettings(payload)
	synced = payload
	if XPR_UI_Settings.instance then
		XPR_UI_Settings.instance:reloadFromCurrent()
	end
end

local function currentGrantRewardBoxes()
	if synced and type(synced.grantRewardBoxes) == "boolean" then return synced.grantRewardBoxes end
	if XPR_RewardConfig and XPR_RewardConfig.getGrantRewardBoxes then
		return XPR_RewardConfig.getGrantRewardBoxes()
	end
	return true
end

local function currentInterval()
	if synced and type(synced.rewardBoxInterval) == "number" then return synced.rewardBoxInterval end
	return (XPR_RewardConfig and XPR_RewardConfig.getBoxInterval and XPR_RewardConfig.getBoxInterval())
		or (XPR_RewardConfig and XPR_RewardConfig.DEFAULT_BOX_INTERVAL) or 5
end

local KILL_XP_KINDS = { "firearms", "melee", "vehicle" }
local KILL_XP_FIELD = {
	firearms = "killXpFirearms",
	melee = "killXpMelee",
	vehicle = "killXpVehicle",
}
local KILL_XP_LABEL_KEY = {
	firearms = "IGUI_XPR_SettingsKill_Firearms",
	melee = "IGUI_XPR_SettingsKill_Melee",
	vehicle = "IGUI_XPR_SettingsKill_Vehicle",
}

local function currentKillXp(kind)
	local field = KILL_XP_FIELD[kind]
	if synced and type(synced[field]) == "number" then return synced[field] end
	return (XPR_Categories and XPR_Categories.getKillXpAmount and XPR_Categories.getKillXpAmount(kind)) or 10
end

local function currentCategoryXp()
	if synced and type(synced.categoryXp) == "table" then return synced.categoryXp end
	local out = {}
	for _, cat in ipairs(CATEGORY_ORDER) do
		out[cat] = (XPR_Categories and XPR_Categories.getCategoryXp and XPR_Categories.getCategoryXp(cat))
			or (XPR_CATEGORY_XP and XPR_CATEGORY_XP[cat]) or 0
	end
	return out
end

local function currentTimeSurvivedXp()
	if synced and type(synced.timeSurvivedXp) == "number" then return synced.timeSurvivedXp end
	return (XPR_Categories and XPR_Categories.getTimeSurvivedXp and XPR_Categories.getTimeSurvivedXp()) or 10
end

local function currentTimeSurvivedIntervalHours()
	if synced and type(synced.timeSurvivedIntervalHours) == "number" then return synced.timeSurvivedIntervalHours end
	return (XPR_Categories and XPR_Categories.getTimeSurvivedIntervalHours and XPR_Categories.getTimeSurvivedIntervalHours()) or 6
end

local function currentTravelWalkXp()
	if synced and type(synced.travelWalkXp) == "number" then return synced.travelWalkXp end
	return (XPR_Categories and XPR_Categories.getTravelWalkXp and XPR_Categories.getTravelWalkXp()) or 10
end

local function currentTravelWalkTiles()
	if synced and type(synced.travelWalkTiles) == "number" then return synced.travelWalkTiles end
	return (XPR_Categories and XPR_Categories.getTravelWalkTiles and XPR_Categories.getTravelWalkTiles()) or 150
end

local function currentTravelDriveXp()
	if synced and type(synced.travelDriveXp) == "number" then return synced.travelDriveXp end
	return (XPR_Categories and XPR_Categories.getTravelDriveXp and XPR_Categories.getTravelDriveXp()) or 10
end

local function currentTravelDriveTiles()
	if synced and type(synced.travelDriveTiles) == "number" then return synced.travelDriveTiles end
	return (XPR_Categories and XPR_Categories.getTravelDriveTiles and XPR_Categories.getTravelDriveTiles()) or 500
end

local function currentPvpXpEnabled()
	if synced and type(synced.pvpXpEnabled) == "boolean" then return synced.pvpXpEnabled end
	return false
end

local function currentPvpXp()
	if synced and type(synced.killXpPvp) == "number" then return synced.killXpPvp end
	return (XPR_Categories and XPR_Categories.getPvpXpAmount and XPR_Categories.getPvpXpAmount()) or 50
end

local function currentPvpCooldownMinutes()
	if synced and type(synced.pvpCooldownMinutes) == "number" then return synced.pvpCooldownMinutes end
	return 30
end

local CROSSMOD_PERK_FALLBACK = {
	Efficiency = { field = "efficiencyXp", default = 1 },
	CombatMastering = { field = "combatMasteringXp", default = 2 },
	Toughness = { field = "toughnessXp", default = 5 },
}

local CROSSMOD_SECTION = {
	{ perk = "Efficiency", dividerKey = "IGUI_XPR_Settings_SectionEfficiency", fieldKey = "IGUI_XPR_Settings_FieldEfficiencyXp" },
	{ perk = "CombatMastering", dividerKey = "IGUI_XPR_Settings_SectionCombatMastering", fieldKey = "IGUI_XPR_Settings_FieldCombatMasteringXp" },
	{ perk = "Toughness", dividerKey = "IGUI_XPR_Settings_SectionToughness", fieldKey = "IGUI_XPR_Settings_FieldToughnessXp" },
}

local function currentCrossModXp(perkName)
	local fallback = CROSSMOD_PERK_FALLBACK[perkName]
	if not fallback then return nil end
	if synced and type(synced[fallback.field]) == "number" then return synced[fallback.field] end
	return (XPR_Categories and XPR_Categories.getCrossModXp and XPR_Categories.getCrossModXp(perkName)) or fallback.default
end

local function isCrossModPerkLoaded(perkName)
	return Perks ~= nil and Perks[perkName] ~= nil
end

local function currentResetRankOnDeath()
	if synced and type(synced.resetRankOnDeath) == "boolean" then return synced.resetRankOnDeath end
	return false
end

local function isServerPvp()
	if XPR_Env and XPR_Env.isSP() then return false end
	if not getServerOptions then return false end
	local opts = getServerOptions()
	if not opts or not opts.getBoolean then return false end
	return opts:getBoolean("PVP") == true
end

local function computeMetrics()
	local btnPad = S(12)
	local btnRightW = math.max(
		XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Edit"), EDIT_BTN_W, btnPad),
		XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Settings_On"), EDIT_BTN_W, btnPad),
		XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Settings_Off"), EDIT_BTN_W, btnPad))
	local btnSaveW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_Common_Save"), S(100), btnPad)
	local btnCancelW = XPR_UI_Scale.btnWidth(FONT, getText("IGUI_XPR_ValueDialog_Cancel"), S(100), btnPad)
	local labelKeys = {
		"IGUI_XPR_Settings_GrantRewardBoxes",
		"IGUI_XPR_Settings_RewardBoxInterval",
		"IGUI_XPR_Settings_ActivityXpYield",
		"IGUI_XPR_Settings_RankCurve",
		"IGUI_XPR_Settings_RewardTiers",
	}
	if isServerPvp() then
		labelKeys[#labelKeys + 1] = "IGUI_XPR_Settings_PvpKillXp"
	end
	if not (XPR_Env and XPR_Env.isSP()) then
		labelKeys[#labelKeys + 1] = "IGUI_XPR_Settings_ResetRankOnDeath"
	end
	local maxLabelW = XPR_UI_Scale.longestText(FONT, labelKeys) + S(8)
	local LABEL_BTN_GAP = S(24)
	local rowNeeded = PAD * 2 + maxLabelW + LABEL_BTN_GAP + btnRightW
	local buttonsNeeded = PAD * 2 + btnSaveW + ROW_GAP + btnCancelW
	local titleNeeded = XPR_UI_Scale.measureText(FONT, getText("IGUI_XPR_Settings_Title")) + BTN_H + PAD * 2
	local panelW = math.max(PANEL_W, rowNeeded, buttonsNeeded, titleNeeded)
	return {
		panelW = panelW,
	btnEditW = btnRightW,
	btnToggleW = btnRightW,
		btnSaveW = btnSaveW,
		btnCancelW = btnCancelW,
	}
end

local function currentBaseXp()
	if synced and type(synced.rankCurveBaseXp) == "number" then return synced.rankCurveBaseXp end
	return (XPR_RankCurve and XPR_RankCurve.getBaseXp and XPR_RankCurve.getBaseXp())
		or (XPR_RankCurve and XPR_RankCurve.BASE_XP) or 40
end

local function currentStep()
	if synced and type(synced.rankCurveStep) == "number" then return synced.rankCurveStep end
	return (XPR_RankCurve and XPR_RankCurve.getStep and XPR_RankCurve.getStep())
		or (XPR_RankCurve and XPR_RankCurve.STEP) or 20
end

local function currentTiersForDialog()
	if synced and type(synced.tier1MaxRank) == "number" and type(synced.tierWeights) == "table" then
		return {
			{ maxRank = synced.tier1MaxRank, weights = synced.tierWeights[1] },
			{ maxRank = synced.tier2MaxRank, weights = synced.tierWeights[2] },
			{ maxRank = nil, weights = synced.tierWeights[3] },
		}
	end
	local tiers = (XPR_RewardConfig and XPR_RewardConfig.getTiers and XPR_RewardConfig.getTiers())
		or (XPR_RewardConfig and XPR_RewardConfig.TIERS)
	if not tiers then return { {weights={}}, {weights={}}, {weights={}} } end
	return {
		{ maxRank = tiers[1].maxRank, weights = tiers[1].weights },
		{ maxRank = tiers[2].maxRank, weights = tiers[2].weights },
		{ maxRank = nil, weights = tiers[3].weights },
	}
end

XPR_UI_Settings.Panel = ISCollapsableWindow:derive("XPR_UI_Settings_Panel")

function XPR_UI_Settings.Panel:new(x, y, width)
	local o = ISCollapsableWindow.new(self, x, y, width or PANEL_W, S(260))
	o.moveWithMouse = true
	o.resizable = false
	return o
end

function XPR_UI_Settings.Panel:initialise()
	ISCollapsableWindow.initialise(self)
	self:setTitle(getText("IGUI_XPR_Settings_Title"))
end

function XPR_UI_Settings.Panel:reloadFromCurrent()
	self._grantRewardBoxes = currentGrantRewardBoxes()
	if self.btnGrantRewardBoxes then
		self:updateGrantRewardBoxesButton()
	end
	self._rewardBoxInterval = currentInterval()
	if self.entryRewardBoxInterval then
		self.entryRewardBoxInterval:setText(tostring(self._rewardBoxInterval or 5))
	end
	self._killXp = {}
	for _, kind in ipairs(KILL_XP_KINDS) do
		self._killXp[kind] = currentKillXp(kind)
	end
	self._categoryXp = currentCategoryXp()
	self._crossModXp = {}
	for _, section in ipairs(CROSSMOD_SECTION) do
		self._crossModXp[section.perk] = currentCrossModXp(section.perk)
	end
	self._timeSurvivedXp = currentTimeSurvivedXp()
	self._timeSurvivedIntervalHours = currentTimeSurvivedIntervalHours()
	self._travelWalkXp = currentTravelWalkXp()
	self._travelWalkTiles = currentTravelWalkTiles()
	self._travelDriveXp = currentTravelDriveXp()
	self._travelDriveTiles = currentTravelDriveTiles()
	self._pvpXpEnabled = currentPvpXpEnabled()
	if self.btnPvpKillXp then
		self:updatePvpKillXpButton()
	end
	self._killXpPvp = currentPvpXp()
	self._pvpCooldownMinutes = currentPvpCooldownMinutes()
	self._resetRankOnDeath = currentResetRankOnDeath()
	if self.btnResetRankOnDeath then
		self:updateResetRankOnDeathButton()
	end
	self._rankCurveBaseXp = currentBaseXp()
	self._rankCurveStep = currentStep()
	local tiers = currentTiersForDialog()
	self._tier1MaxRank = tiers[1].maxRank
	self._tier2MaxRank = tiers[2].maxRank
	self._tierWeights = {
		[1] = tiers[1].weights,
		[2] = tiers[2].weights,
		[3] = tiers[3].weights,
	}
end

function XPR_UI_Settings.Panel:createChildren()
	ISCollapsableWindow.createChildren(self)

	local m = XPR_UI_Settings._metrics or {
		panelW = PANEL_W,
		btnEditW = EDIT_BTN_W,
		btnToggleW = EDIT_BTN_W,
		btnSaveW = S(100),
		btnCancelW = S(100),
	}

	self:reloadFromCurrent()

	local titleH = fontHgt + S(1)
	local y = titleH + PAD
	local rowW = self.width - PAD * 2

	local lbl0 = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_GrantRewardBoxes"),
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	lbl0:initialise()
	self:addChild(lbl0)

	self.btnGrantRewardBoxes = ISButton:new(self.width - PAD - m.btnToggleW, y, m.btnToggleW, BTN_H,
		"", self, XPR_UI_Settings.Panel.onToggleGrantRewardBoxes)
	self.btnGrantRewardBoxes:initialise()
	self.btnGrantRewardBoxes:instantiate()
	self.btnGrantRewardBoxes.tooltip = getText("IGUI_XPR_Settings_GrantRewardBoxesTooltip")
	self:addChild(self.btnGrantRewardBoxes)
	self:updateGrantRewardBoxesButton()
	y = y + BTN_H + ROW_GAP

	if isServerPvp() then
		local lblPvp = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_PvpKillXp"),
			COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
		lblPvp:initialise()
		self:addChild(lblPvp)

		self.btnPvpKillXp = ISButton:new(self.width - PAD - m.btnToggleW, y, m.btnToggleW, BTN_H,
			"", self, XPR_UI_Settings.Panel.onTogglePvpKillXp)
		self.btnPvpKillXp:initialise()
		self.btnPvpKillXp:instantiate()
		self.btnPvpKillXp.tooltip = getText("IGUI_XPR_Settings_PvpKillXpTooltip")
		self:addChild(self.btnPvpKillXp)
		self:updatePvpKillXpButton()
		y = y + BTN_H + ROW_GAP
	end

	if not (XPR_Env and XPR_Env.isSP()) then
		local lblReset = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_ResetRankOnDeath"),
			COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
		lblReset:initialise()
		self:addChild(lblReset)

		self.btnResetRankOnDeath = ISButton:new(self.width - PAD - m.btnToggleW, y, m.btnToggleW, BTN_H,
			"", self, XPR_UI_Settings.Panel.onToggleResetRankOnDeath)
		self.btnResetRankOnDeath:initialise()
		self.btnResetRankOnDeath:instantiate()
		self.btnResetRankOnDeath.tooltip = getText("IGUI_XPR_Settings_ResetRankOnDeathTooltip")
		self:addChild(self.btnResetRankOnDeath)
		self:updateResetRankOnDeathButton()
		y = y + BTN_H + ROW_GAP
	end

	local lbl1 = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_RewardBoxInterval"),
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	lbl1:initialise()
	self:addChild(lbl1)

	self.entryRewardBoxInterval = ISTextEntryBox:new(tostring(self._rewardBoxInterval or 5),
		self.width - PAD - m.btnEditW, y, m.btnEditW, BTN_H)
	self.entryRewardBoxInterval:initialise()
	self.entryRewardBoxInterval:instantiate()
	self.entryRewardBoxInterval:setOnlyNumbers(true)
	self.entryRewardBoxInterval.tooltip = getText("IGUI_XPR_Settings_IntervalTooltip")
	self:addChild(self.entryRewardBoxInterval)
	y = y + BTN_H + ROW_GAP

	local lbl2 = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_ActivityXpYield"),
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	lbl2:initialise()
	self:addChild(lbl2)

	self.btnEditActivityXp = ISButton:new(self.width - PAD - m.btnEditW, y, m.btnEditW, BTN_H,
		getText("IGUI_XPR_Common_Edit"), self, XPR_UI_Settings.Panel.onEditActivityXp)
	self.btnEditActivityXp:initialise()
	self.btnEditActivityXp:instantiate()
	self.btnEditActivityXp.tooltip = getText("IGUI_XPR_Settings_ActivityXpTooltip")
	self:addChild(self.btnEditActivityXp)
	y = y + BTN_H + ROW_GAP

	local lbl3 = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_RankCurve"),
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	lbl3:initialise()
	self:addChild(lbl3)

	self.btnEditCurve = ISButton:new(self.width - PAD - m.btnEditW, y, m.btnEditW, BTN_H,
		getText("IGUI_XPR_Common_Edit"), self, XPR_UI_Settings.Panel.onEditCurve)
	self.btnEditCurve:initialise()
	self.btnEditCurve:instantiate()
	self.btnEditCurve.tooltip = getText("IGUI_XPR_Settings_CurveTooltip")
	self:addChild(self.btnEditCurve)
	y = y + BTN_H + ROW_GAP

	local lbl4 = ISLabel:new(PAD, y + S(3), fontHgt, getText("IGUI_XPR_Settings_RewardTiers"),
		COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 1, FONT, true)
	lbl4:initialise()
	self:addChild(lbl4)

	self.btnEditTiers = ISButton:new(self.width - PAD - m.btnEditW, y, m.btnEditW, BTN_H,
		getText("IGUI_XPR_Common_Edit"), self, XPR_UI_Settings.Panel.onEditTiers)
	self.btnEditTiers:initialise()
	self.btnEditTiers:instantiate()
	self.btnEditTiers.tooltip = getText("IGUI_XPR_Settings_TiersTooltip")
	self:addChild(self.btnEditTiers)
	y = y + BTN_H + ROW_GAP + S(4)

	self.btnSave = ISButton:new(PAD, y, m.btnSaveW, BTN_H, getText("IGUI_XPR_Common_Save"), self, XPR_UI_Settings.Panel.onSave)
	self.btnSave:initialise()
	self.btnSave:instantiate()
	self.btnSave:enableAcceptColor()
	self:addChild(self.btnSave)

	self.btnCancel = ISButton:new(self.width - PAD - m.btnCancelW, y, m.btnCancelW, BTN_H,
		getText("IGUI_XPR_ValueDialog_Cancel"), self, XPR_UI_Settings.Panel.close)
	self.btnCancel:initialise()
	self.btnCancel:instantiate()
	self.btnCancel:enableCancelColor()
	self:addChild(self.btnCancel)

	self:setHeight(y + BTN_H + PAD)

	if not (XPR_Env and XPR_Env.isTrueSinglePlayer()) then
		local player = getSpecificPlayer(0)
		if player then
			sendClientCommand(player, "XPRanks", "getSettings", {})
		end
	end
end

function XPR_UI_Settings.Panel:prerender()
	ISCollapsableWindow.prerender(self)
	local titleH = fontHgt + S(1)
	self:drawRect(0, titleH, self.width, S(2), 1, COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b)
end

function XPR_UI_Settings.Panel:updateGrantRewardBoxesButton()
	local on = self._grantRewardBoxes
	self.btnGrantRewardBoxes:setTitle(on and getText("IGUI_XPR_Settings_On") or getText("IGUI_XPR_Settings_Off"))
	if on then
		self.btnGrantRewardBoxes:enableAcceptColor()
	else
		self.btnGrantRewardBoxes:enableCancelColor()
	end
end

function XPR_UI_Settings.Panel:onToggleGrantRewardBoxes()
	self._grantRewardBoxes = not self._grantRewardBoxes
	self:updateGrantRewardBoxesButton()
end

function XPR_UI_Settings.Panel:updatePvpKillXpButton()
	local on = self._pvpXpEnabled
	self.btnPvpKillXp:setTitle(on and getText("IGUI_XPR_Settings_On") or getText("IGUI_XPR_Settings_Off"))
	if on then
		self.btnPvpKillXp:enableAcceptColor()
	else
		self.btnPvpKillXp:enableCancelColor()
	end
end

function XPR_UI_Settings.Panel:onTogglePvpKillXp()
	self._pvpXpEnabled = not self._pvpXpEnabled
	self:updatePvpKillXpButton()
end

function XPR_UI_Settings.Panel:updateResetRankOnDeathButton()
	local on = self._resetRankOnDeath
	self.btnResetRankOnDeath:setTitle(on and getText("IGUI_XPR_Settings_On") or getText("IGUI_XPR_Settings_Off"))
	if on then
		self.btnResetRankOnDeath:enableAcceptColor()
	else
		self.btnResetRankOnDeath:enableCancelColor()
	end
end

function XPR_UI_Settings.Panel:onToggleResetRankOnDeath()
	self._resetRankOnDeath = not self._resetRankOnDeath
	self:updateResetRankOnDeathButton()
end

function XPR_UI_Settings.Panel:onEditActivityXp()
	local fields = {}
	for _, kind in ipairs(KILL_XP_KINDS) do
		fields[#fields + 1] = { key = kind, label = getText(KILL_XP_LABEL_KEY[kind]),
			min = 0, max = 1000, default = self._killXp[kind] or 0 }
	end
	for _, cat in ipairs(CATEGORY_ORDER) do
		local label = CATEGORY_LABEL_KEY[cat] and getText(CATEGORY_LABEL_KEY[cat]) or cat
		fields[#fields + 1] = { key = cat, label = label, min = 0, max = 1000, default = self._categoryXp[cat] or 0 }
	end

	for _, section in ipairs(CROSSMOD_SECTION) do
		if isCrossModPerkLoaded(section.perk) then
			fields[#fields + 1] = { divider = true, label = getText(section.dividerKey) }
			fields[#fields + 1] = { key = section.perk, label = getText(section.fieldKey), min = 0, max = 1000, default = CROSSMOD_PERK_FALLBACK[section.perk].default }
		end
	end

	fields[#fields + 1] = { divider = true, label = getText("IGUI_XPR_Settings_SectionTimeSurvived") }
	fields[#fields + 1] = { key = "xp", label = getText("IGUI_XPR_Settings_FieldXpAwarded"), min = 0, max = 1000, default = 10 }
	fields[#fields + 1] = { key = "hours", label = getText("IGUI_XPR_Settings_FieldIntervalHours"), min = 1, max = 100000, default = 6 }

	fields[#fields + 1] = { divider = true, label = getText("IGUI_XPR_Settings_SectionTravel") }
	fields[#fields + 1] = { key = "walkXp", label = getText("IGUI_XPR_Settings_FieldOnFootXp"), min = 0, max = 1000, default = 10 }
	fields[#fields + 1] = { key = "walkTiles", label = getText("IGUI_XPR_Settings_FieldOnFootTiles"), min = 1, max = 100000, default = 150 }
	fields[#fields + 1] = { key = "driveXp", label = getText("IGUI_XPR_Settings_FieldDrivingXp"), min = 0, max = 1000, default = 10 }
	fields[#fields + 1] = { key = "driveTiles", label = getText("IGUI_XPR_Settings_FieldDrivingTiles"), min = 1, max = 100000, default = 500 }

	if isServerPvp() then
		fields[#fields + 1] = { divider = true, label = getText("IGUI_XPR_Settings_SectionPvp") }
		fields[#fields + 1] = { key = "pvpXp", label = getText("IGUI_XPR_Settings_FieldPvpXp"), min = 0, max = 1000, default = 50 }
		fields[#fields + 1] = { key = "pvpCooldown", label = getText("IGUI_XPR_Settings_FieldPvpCooldown"), min = 0, max = 10080, default = 30 }
	end

	local values = {}
	for _, kind in ipairs(KILL_XP_KINDS) do values[kind] = self._killXp[kind] end
	for _, cat in ipairs(CATEGORY_ORDER) do values[cat] = self._categoryXp[cat] end
	for _, section in ipairs(CROSSMOD_SECTION) do
		values[section.perk] = self._crossModXp[section.perk]
	end
	values.xp = self._timeSurvivedXp
	values.hours = self._timeSurvivedIntervalHours
	values.walkXp = self._travelWalkXp
	values.walkTiles = self._travelWalkTiles
	values.driveXp = self._travelDriveXp
	values.driveTiles = self._travelDriveTiles
	values.pvpXp = self._killXpPvp
	values.pvpCooldown = self._pvpCooldownMinutes

	XPR_UI_MultiValueDialog.open(getText("IGUI_XPR_Settings_ActivityXpYield"), fields, values, function(newValues)
		for _, kind in ipairs(KILL_XP_KINDS) do
			self._killXp[kind] = newValues[kind]
		end
		for _, cat in ipairs(CATEGORY_ORDER) do
			self._categoryXp[cat] = newValues[cat]
		end
		for _, section in ipairs(CROSSMOD_SECTION) do
			if newValues[section.perk] ~= nil then
				self._crossModXp[section.perk] = newValues[section.perk]
			end
		end
		self._timeSurvivedXp = newValues.xp
		self._timeSurvivedIntervalHours = newValues.hours
		self._travelWalkXp = newValues.walkXp
		self._travelWalkTiles = newValues.walkTiles
		self._travelDriveXp = newValues.driveXp
		self._travelDriveTiles = newValues.driveTiles
		if newValues.pvpXp ~= nil then self._killXpPvp = newValues.pvpXp end
		if newValues.pvpCooldown ~= nil then self._pvpCooldownMinutes = newValues.pvpCooldown end
	end)
end

function XPR_UI_Settings.Panel:onEditCurve()
	local fields = {
		{ key = "baseXp", label = getText("IGUI_XPR_Settings_FieldBaseXp"), min = 1, max = 1000000, default = 40 },
		{ key = "step", label = getText("IGUI_XPR_Settings_FieldStep"), min = 0, max = 1000000, default = 20 },
	}
	XPR_UI_MultiValueDialog.open(getText("IGUI_XPR_Settings_RankCurveDialogTitle"), fields,
		{ baseXp = self._rankCurveBaseXp, step = self._rankCurveStep },
		function(newValues)
			self._rankCurveBaseXp = newValues.baseXp
			self._rankCurveStep = newValues.step
		end)
end

function XPR_UI_Settings.Panel:onEditTiers()
	local currentTiers = {
		{ maxRank = self._tier1MaxRank, weights = self._tierWeights[1] },
		{ maxRank = self._tier2MaxRank, weights = self._tierWeights[2] },
		{ maxRank = nil, weights = self._tierWeights[3] },
	}
	XPR_UI_TiersDialog.open(currentTiers, function(result)
		self._tier1MaxRank = result.tier1MaxRank
		self._tier2MaxRank = result.tier2MaxRank
		self._tierWeights = result.tierWeights
	end)
end

function XPR_UI_Settings.Panel:onSave()
	local player = getPlayer()
	if player then
		if self.entryRewardBoxInterval then
			local interval = tonumber(self.entryRewardBoxInterval:getText())
			if interval then
				self._rewardBoxInterval = math.max(1, math.min(999, math.floor(interval)))
			end
		end
		local payload = {
			grantRewardBoxes = self._grantRewardBoxes,
			rewardBoxInterval = self._rewardBoxInterval,
			categoryXp = self._categoryXp,
			timeSurvivedXp = self._timeSurvivedXp,
			timeSurvivedIntervalHours = self._timeSurvivedIntervalHours,
			travelWalkXp = self._travelWalkXp,
			travelWalkTiles = self._travelWalkTiles,
			travelDriveXp = self._travelDriveXp,
			travelDriveTiles = self._travelDriveTiles,
			pvpXpEnabled = self._pvpXpEnabled,
			killXpPvp = self._killXpPvp,
			pvpCooldownMinutes = self._pvpCooldownMinutes,
			resetRankOnDeath = self._resetRankOnDeath,
			rankCurveBaseXp = self._rankCurveBaseXp,
			rankCurveStep = self._rankCurveStep,
			tier1MaxRank = self._tier1MaxRank,
			tier2MaxRank = self._tier2MaxRank,
			tierWeights = self._tierWeights,
		}
		for _, kind in ipairs(KILL_XP_KINDS) do
			payload[KILL_XP_FIELD[kind]] = self._killXp[kind]
		end
		for _, section in ipairs(CROSSMOD_SECTION) do
			payload[CROSSMOD_PERK_FALLBACK[section.perk].field] = self._crossModXp[section.perk]
		end
		sendClientCommand(player, "XPRanks", "settingsApply", payload)
	end
	XPR_dprint("[XPR] XPR Settings save: grantRewardBoxes=" .. tostring(self._grantRewardBoxes)
		.. " interval=" .. tostring(self._rewardBoxInterval)
		.. " killXp.firearms=" .. tostring(self._killXp.firearms)
		.. " killXp.melee=" .. tostring(self._killXp.melee)
		.. " killXp.vehicle=" .. tostring(self._killXp.vehicle)
		.. " timeSurvivedXp=" .. tostring(self._timeSurvivedXp)
		.. " timeSurvivedIntervalHours=" .. tostring(self._timeSurvivedIntervalHours)
		.. " travelWalkXp=" .. tostring(self._travelWalkXp)
		.. " travelWalkTiles=" .. tostring(self._travelWalkTiles)
		.. " travelDriveXp=" .. tostring(self._travelDriveXp)
		.. " travelDriveTiles=" .. tostring(self._travelDriveTiles)
		.. " efficiencyXp=" .. tostring(self._crossModXp and self._crossModXp.Efficiency)
		.. " combatMasteringXp=" .. tostring(self._crossModXp and self._crossModXp.CombatMastering)
		.. " toughnessXp=" .. tostring(self._crossModXp and self._crossModXp.Toughness)
		.. " pvpXpEnabled=" .. tostring(self._pvpXpEnabled)
		.. " killXpPvp=" .. tostring(self._killXpPvp)
		.. " pvpCooldownMinutes=" .. tostring(self._pvpCooldownMinutes)
		.. " resetRankOnDeath=" .. tostring(self._resetRankOnDeath)
		.. " baseXp=" .. tostring(self._rankCurveBaseXp)
		.. " step=" .. tostring(self._rankCurveStep)
		.. " tier1Max=" .. tostring(self._tier1MaxRank)
		.. " tier2Max=" .. tostring(self._tier2MaxRank))
	if ObNoxToast and ObNoxToast.show then
		ObNoxToast.show(getText("IGUI_XPR_Settings_SavedToast"), "debug", nil, "XPRanks")
	end
	self:close()
end

function XPR_UI_Settings.Panel:close()
	self:setVisible(false)
	self:removeFromUIManager()
	XPR_UI_Settings.instance = nil
end

function XPR_UI_Settings.open()
	if XPR_UI_Settings.instance then
		XPR_UI_Settings.instance:setVisible(true)
		XPR_UI_Settings.instance:addToUIManager()
		return
	end
	local screenW = getCore():getScreenWidth()
	local screenH = getCore():getScreenHeight()
	local metrics = computeMetrics()
	XPR_UI_Settings._metrics = metrics
	local panel = XPR_UI_Settings.Panel:new(screenW / 2 - metrics.panelW / 2, screenH / 2 - S(130), metrics.panelW)
	panel:initialise()
	panel:addToUIManager()
	XPR_UI_Settings.instance = panel
end

function XPR_UI_Settings.close()
	if XPR_UI_Settings.instance then
		XPR_UI_Settings.instance:removeFromUIManager()
		XPR_UI_Settings.instance = nil
	end
end

return XPR_UI_Settings
