XPR_SettingsStore = XPR_SettingsStore or {}

local GLOBAL_KEY = "XPR_Global"

local CROSSMOD_XP_FIELD = {
	Efficiency = "efficiencyXp",
	CombatMastering = "combatMasteringXp",
	Toughness = "toughnessXp",
}

local SETTING_DEFAULT = {
	grantRewardBoxes = true,
	rewardBoxInterval = 5,
	killXpFirearms = 10,
	killXpMelee = 10,
	killXpVehicle = 10,
	timeSurvivedXp = 10,
	timeSurvivedIntervalHours = 6,
	travelWalkXp = 10,
	travelWalkTiles = 150,
	travelDriveXp = 10,
	travelDriveTiles = 500,
	pvpXpEnabled = false,
	killXpPvp = 50,
	pvpCooldownMinutes = 30,
	resetRankOnDeath = false,
	efficiencyXp = 1,
	combatMasteringXp = 2,
	toughnessXp = 5,
	categoryXp = {
		["Combat - Firearms"] = 1,
		["Combat - Melee"] = 2,
		["Crafting"] = 5,
		["Farming"] = 5,
		["Physical"] = 1,
		["Survival"] = 5,
	},
	rankCurveBaseXp = 40,
	rankCurveStep = 20,
	tier1MaxRank = 99,
	tier2MaxRank = 300,
	tierWeights = {
		[1] = { COMMON = 0.70, UNCOMMON = 0.25, RARE = 0.05 },
		[2] = { COMMON = 0.35, UNCOMMON = 0.45, RARE = 0.20 },
		[3] = { COMMON = 0.10, UNCOMMON = 0.30, RARE = 0.60 },
	},
}

function XPR_SettingsStore.get()
	local gmd = ModData.getOrCreate(GLOBAL_KEY)
	if not gmd.settings then
		gmd.settings = {
			grantRewardBoxes = SETTING_DEFAULT.grantRewardBoxes,
			rewardBoxInterval = SETTING_DEFAULT.rewardBoxInterval,
			killXpFirearms = SETTING_DEFAULT.killXpFirearms,
			killXpMelee = SETTING_DEFAULT.killXpMelee,
			killXpVehicle = SETTING_DEFAULT.killXpVehicle,
			timeSurvivedXp = SETTING_DEFAULT.timeSurvivedXp,
			timeSurvivedIntervalHours = SETTING_DEFAULT.timeSurvivedIntervalHours,
			travelWalkXp = SETTING_DEFAULT.travelWalkXp,
			travelWalkTiles = SETTING_DEFAULT.travelWalkTiles,
			travelDriveXp = SETTING_DEFAULT.travelDriveXp,
			travelDriveTiles = SETTING_DEFAULT.travelDriveTiles,
			pvpXpEnabled = SETTING_DEFAULT.pvpXpEnabled,
			killXpPvp = SETTING_DEFAULT.killXpPvp,
			pvpCooldownMinutes = SETTING_DEFAULT.pvpCooldownMinutes,
			resetRankOnDeath = SETTING_DEFAULT.resetRankOnDeath,
			efficiencyXp = SETTING_DEFAULT.efficiencyXp,
			combatMasteringXp = SETTING_DEFAULT.combatMasteringXp,
			toughnessXp = SETTING_DEFAULT.toughnessXp,
			categoryXp = {},
			rankCurveBaseXp = SETTING_DEFAULT.rankCurveBaseXp,
			rankCurveStep = SETTING_DEFAULT.rankCurveStep,
			tier1MaxRank = SETTING_DEFAULT.tier1MaxRank,
			tier2MaxRank = SETTING_DEFAULT.tier2MaxRank,
			tierWeights = { [1] = {}, [2] = {}, [3] = {} },
		}
		for cat, xp in pairs(SETTING_DEFAULT.categoryXp) do
			gmd.settings.categoryXp[cat] = xp
		end
		for tierIdx, weights in pairs(SETTING_DEFAULT.tierWeights) do
			for band, w in pairs(weights) do
				gmd.settings.tierWeights[tierIdx][band] = w
			end
		end
		XPR_dprint("[XPR] XPR_SettingsStore: seeded persisted settings from defaults")
	end

	if gmd.settings.grantRewardBoxes == nil then
		gmd.settings.grantRewardBoxes = SETTING_DEFAULT.grantRewardBoxes
	end

	if gmd.settings.killXpFirearms == nil then
		local legacy = tonumber(gmd.settings.killXpAmount) or SETTING_DEFAULT.killXpFirearms
		gmd.settings.killXpFirearms = tonumber(gmd.settings.killXpFirearmsCombat) or legacy
		gmd.settings.killXpMelee = tonumber(gmd.settings.killXpMeleeCombat) or legacy
		gmd.settings.killXpVehicle = tonumber(gmd.settings.killXpVehicleZombieKill) or legacy
		XPR_dprint("[XPR] XPR_SettingsStore: migrated legacy kill-XP fields to killXpFirearms="
			.. tostring(gmd.settings.killXpFirearms) .. " killXpMelee=" .. tostring(gmd.settings.killXpMelee)
			.. " killXpVehicle=" .. tostring(gmd.settings.killXpVehicle))
	end

	if gmd.settings.timeSurvivedXp == nil then
		gmd.settings.timeSurvivedXp = SETTING_DEFAULT.timeSurvivedXp
		gmd.settings.timeSurvivedIntervalHours = SETTING_DEFAULT.timeSurvivedIntervalHours
		gmd.settings.travelWalkXp = SETTING_DEFAULT.travelWalkXp
		gmd.settings.travelWalkTiles = SETTING_DEFAULT.travelWalkTiles
		gmd.settings.travelDriveXp = SETTING_DEFAULT.travelDriveXp
		gmd.settings.travelDriveTiles = SETTING_DEFAULT.travelDriveTiles
	end

	if gmd.settings.pvpXpEnabled == nil then
		gmd.settings.pvpXpEnabled = SETTING_DEFAULT.pvpXpEnabled
		gmd.settings.killXpPvp = SETTING_DEFAULT.killXpPvp
		gmd.settings.pvpCooldownMinutes = SETTING_DEFAULT.pvpCooldownMinutes
	end

	if gmd.settings.resetRankOnDeath == nil then
		gmd.settings.resetRankOnDeath = SETTING_DEFAULT.resetRankOnDeath
	end

	if gmd.settings.efficiencyXp == nil then
		gmd.settings.efficiencyXp = SETTING_DEFAULT.efficiencyXp
		gmd.settings.combatMasteringXp = SETTING_DEFAULT.combatMasteringXp
		gmd.settings.toughnessXp = SETTING_DEFAULT.toughnessXp
	end

	return gmd.settings
end

function XPR_SettingsStore.getGrantRewardBoxes()
	local s = XPR_SettingsStore.get()
	if s.grantRewardBoxes == nil then return SETTING_DEFAULT.grantRewardBoxes end
	return s.grantRewardBoxes
end

function XPR_SettingsStore.getRewardBoxInterval()
	local s = XPR_SettingsStore.get()
	return s.rewardBoxInterval or SETTING_DEFAULT.rewardBoxInterval
end

function XPR_SettingsStore.getTimeSurvivedXp()
	local s = XPR_SettingsStore.get()
	return s.timeSurvivedXp or SETTING_DEFAULT.timeSurvivedXp
end

function XPR_SettingsStore.getTimeSurvivedIntervalHours()
	local s = XPR_SettingsStore.get()
	return s.timeSurvivedIntervalHours or SETTING_DEFAULT.timeSurvivedIntervalHours
end

function XPR_SettingsStore.getTravelWalkXp()
	local s = XPR_SettingsStore.get()
	return s.travelWalkXp or SETTING_DEFAULT.travelWalkXp
end

function XPR_SettingsStore.getTravelWalkTiles()
	local s = XPR_SettingsStore.get()
	return s.travelWalkTiles or SETTING_DEFAULT.travelWalkTiles
end

function XPR_SettingsStore.getTravelDriveXp()
	local s = XPR_SettingsStore.get()
	return s.travelDriveXp or SETTING_DEFAULT.travelDriveXp
end

function XPR_SettingsStore.getTravelDriveTiles()
	local s = XPR_SettingsStore.get()
	return s.travelDriveTiles or SETTING_DEFAULT.travelDriveTiles
end

function XPR_SettingsStore.getCrossModXp(perkName)
	local s = XPR_SettingsStore.get()
	local field = CROSSMOD_XP_FIELD[perkName]
	if not field then return nil end
	local v = s[field]
	if type(v) == "number" then return v end
	return SETTING_DEFAULT[field]
end

function XPR_SettingsStore.getPvpXpEnabled()
	local s = XPR_SettingsStore.get()
	if s.pvpXpEnabled == nil then return SETTING_DEFAULT.pvpXpEnabled end
	return s.pvpXpEnabled
end

function XPR_SettingsStore.getPvpXpAmount()
	local s = XPR_SettingsStore.get()
	return s.killXpPvp or SETTING_DEFAULT.killXpPvp
end

function XPR_SettingsStore.getPvpCooldownMinutes()
	local s = XPR_SettingsStore.get()
	return s.pvpCooldownMinutes or SETTING_DEFAULT.pvpCooldownMinutes
end

function XPR_SettingsStore.getResetRankOnDeath()
	local s = XPR_SettingsStore.get()
	if s.resetRankOnDeath == nil then return SETTING_DEFAULT.resetRankOnDeath end
	return s.resetRankOnDeath
end

local KILL_XP_FIELD = {
	firearms = "killXpFirearms",
	melee = "killXpMelee",
	vehicle = "killXpVehicle",
}

function XPR_SettingsStore.getKillXpAmount(kind)
	local field = KILL_XP_FIELD[kind]
	if not field then return 0 end
	local s = XPR_SettingsStore.get()
	return s[field] or SETTING_DEFAULT[field]
end

function XPR_SettingsStore.getKillXpTable()
	local s = XPR_SettingsStore.get()
	local out = {}
	for kind, field in pairs(KILL_XP_FIELD) do
		out[kind] = s[field] or SETTING_DEFAULT[field]
	end
	return out
end

function XPR_SettingsStore.getCategoryXp(category)
	local s = XPR_SettingsStore.get()
	local v = s.categoryXp and s.categoryXp[category]
	if type(v) == "number" then return v end
	return SETTING_DEFAULT.categoryXp[category] or 0
end

function XPR_SettingsStore.getCategoryXpTable()
	local s = XPR_SettingsStore.get()
	local out = {}
	for cat, default in pairs(SETTING_DEFAULT.categoryXp) do
		local v = s.categoryXp and s.categoryXp[cat]
		out[cat] = (type(v) == "number") and v or default
	end
	return out
end

function XPR_SettingsStore.getRankCurveBaseXp()
	local s = XPR_SettingsStore.get()
	return s.rankCurveBaseXp or SETTING_DEFAULT.rankCurveBaseXp
end

function XPR_SettingsStore.getRankCurveStep()
	local s = XPR_SettingsStore.get()
	return s.rankCurveStep or SETTING_DEFAULT.rankCurveStep
end

function XPR_SettingsStore.getTiers()
	local s = XPR_SettingsStore.get()
	local t1Max = s.tier1MaxRank or SETTING_DEFAULT.tier1MaxRank
	local t2Max = s.tier2MaxRank or SETTING_DEFAULT.tier2MaxRank
	local weights = s.tierWeights or SETTING_DEFAULT.tierWeights
	local function w(idx)
		local src = weights[idx] or SETTING_DEFAULT.tierWeights[idx]
		return {
			COMMON = src.COMMON or 0,
			UNCOMMON = src.UNCOMMON or 0,
			RARE = src.RARE or 0,
		}
	end
	return {
		{ name = "Tier 1", minRank = 1, maxRank = t1Max, weights = w(1) },
		{ name = "Tier 2", minRank = t1Max + 1, maxRank = t2Max, weights = w(2) },
		{ name = "Tier 3", minRank = t2Max + 1, maxRank = math.huge, weights = w(3) },
	}
end

function XPR_SettingsStore.broadcast(targetPlayer)
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	if not XPR_Env then return end

	local s = XPR_SettingsStore.get()
	local payload = {
		grantRewardBoxes = s.grantRewardBoxes,
		rewardBoxInterval = s.rewardBoxInterval,
		killXpFirearms = s.killXpFirearms,
		killXpMelee = s.killXpMelee,
		killXpVehicle = s.killXpVehicle,
		timeSurvivedXp = s.timeSurvivedXp,
		timeSurvivedIntervalHours = s.timeSurvivedIntervalHours,
		travelWalkXp = s.travelWalkXp,
		travelWalkTiles = s.travelWalkTiles,
		travelDriveXp = s.travelDriveXp,
		travelDriveTiles = s.travelDriveTiles,
		pvpXpEnabled = s.pvpXpEnabled,
		killXpPvp = s.killXpPvp,
		pvpCooldownMinutes = s.pvpCooldownMinutes,
		resetRankOnDeath = s.resetRankOnDeath,
		efficiencyXp = s.efficiencyXp,
		combatMasteringXp = s.combatMasteringXp,
		toughnessXp = s.toughnessXp,
		categoryXp = XPR_SettingsStore.getCategoryXpTable(),
		rankCurveBaseXp = s.rankCurveBaseXp,
		rankCurveStep = s.rankCurveStep,
		tier1MaxRank = s.tier1MaxRank,
		tier2MaxRank = s.tier2MaxRank,
		tierWeights = s.tierWeights,
	}

	if targetPlayer then
		XPR_Env.sendToClient(targetPlayer, "XPRanks", "settingsSync", payload)
		return
	end

	XPR_Env.sendToAllClients("XPRanks", "settingsSync", payload)
end

function XPR_SettingsStore.apply(newSettings)
	if not newSettings then return end
	local s = XPR_SettingsStore.get()

	if type(newSettings.grantRewardBoxes) == "boolean" then
		s.grantRewardBoxes = newSettings.grantRewardBoxes
	end

	if type(newSettings.pvpXpEnabled) == "boolean" then
		s.pvpXpEnabled = newSettings.pvpXpEnabled
	end

	if type(newSettings.resetRankOnDeath) == "boolean" then
		s.resetRankOnDeath = newSettings.resetRankOnDeath
	end

	if newSettings.rewardBoxInterval ~= nil then
		s.rewardBoxInterval = math.max(1, math.min(999,
			math.floor(tonumber(newSettings.rewardBoxInterval) or s.rewardBoxInterval)))
	end

	for _, field in ipairs({ "killXpFirearms", "killXpMelee", "killXpVehicle",
			"timeSurvivedXp", "travelWalkXp", "travelDriveXp", "killXpPvp",
			"efficiencyXp", "combatMasteringXp", "toughnessXp" }) do
		if newSettings[field] ~= nil then
			s[field] = math.max(0, math.min(1000,
				math.floor(tonumber(newSettings[field]) or s[field])))
		end
	end

	if newSettings.pvpCooldownMinutes ~= nil then
		s.pvpCooldownMinutes = math.max(0, math.min(10080,
			math.floor(tonumber(newSettings.pvpCooldownMinutes) or s.pvpCooldownMinutes)))
	end

	if newSettings.timeSurvivedIntervalHours ~= nil then
		s.timeSurvivedIntervalHours = math.max(1, math.min(100000,
			math.floor(tonumber(newSettings.timeSurvivedIntervalHours) or s.timeSurvivedIntervalHours)))
	end
	for _, field in ipairs({ "travelWalkTiles", "travelDriveTiles" }) do
		if newSettings[field] ~= nil then
			s[field] = math.max(1, math.min(100000,
				math.floor(tonumber(newSettings[field]) or s[field])))
		end
	end

	if type(newSettings.categoryXp) == "table" then
		s.categoryXp = s.categoryXp or {}
		for cat in pairs(SETTING_DEFAULT.categoryXp) do
			local v = newSettings.categoryXp[cat]
			if v ~= nil then
				s.categoryXp[cat] = math.max(0, math.min(1000,
					math.floor(tonumber(v) or s.categoryXp[cat] or SETTING_DEFAULT.categoryXp[cat])))
			end
		end
	end

	if newSettings.rankCurveBaseXp ~= nil then
		s.rankCurveBaseXp = math.max(1, math.min(1000000,
			math.floor(tonumber(newSettings.rankCurveBaseXp) or s.rankCurveBaseXp)))
	end
	if newSettings.rankCurveStep ~= nil then
		s.rankCurveStep = math.max(0, math.min(1000000,
			math.floor(tonumber(newSettings.rankCurveStep) or s.rankCurveStep)))
	end

	if newSettings.tier1MaxRank ~= nil then
		s.tier1MaxRank = math.max(1, math.floor(tonumber(newSettings.tier1MaxRank) or s.tier1MaxRank))
	end
	if newSettings.tier2MaxRank ~= nil then
		s.tier2MaxRank = math.max(s.tier1MaxRank + 1,
			math.floor(tonumber(newSettings.tier2MaxRank) or s.tier2MaxRank))
	end
	if s.tier1MaxRank >= s.tier2MaxRank then
		s.tier1MaxRank = s.tier2MaxRank - 1
	end

	if type(newSettings.tierWeights) == "table" then
		s.tierWeights = s.tierWeights or { [1] = {}, [2] = {}, [3] = {} }
		for tierIdx = 1, 3 do
			local incoming = newSettings.tierWeights[tierIdx]
			if type(incoming) == "table" then
				s.tierWeights[tierIdx] = s.tierWeights[tierIdx] or {}
				local common = math.max(0, tonumber(incoming.COMMON) or 0)
				local uncommon = math.max(0, tonumber(incoming.UNCOMMON) or 0)
				local rare = math.max(0, tonumber(incoming.RARE) or 0)
				local total = common + uncommon + rare
				if total <= 0 then
				else
					s.tierWeights[tierIdx].COMMON = common / total
					s.tierWeights[tierIdx].UNCOMMON = uncommon / total
					s.tierWeights[tierIdx].RARE = rare / total
				end
			end
		end
	end

	ModData.transmit(GLOBAL_KEY)
	XPR_SettingsStore.broadcast()
	XPR_dprint("[XPR] XPR_SettingsStore.apply: settings updated and broadcast")
end

local GET_SETTINGS_COOLDOWN_MS = 1000

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end
	if command == "getSettings" then
		if not player then return end
		if XPR_Env and not XPR_Env.checkCooldown("getSettings", player, GET_SETTINGS_COOLDOWN_MS) then return end
		XPR_SettingsStore.broadcast(player)
	elseif command == "settingsApply" then
		if not player then return end
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then
			XPR_dprint("[XPR] onClientCommand REJECTED (not admin): command=settingsApply player="
				.. tostring(player:getUsername()))
			return
		end
		if not args then return end
		XPR_SettingsStore.apply(args)
		XPR_dprint("[XPR] Admin applied XPR Settings changes ("
			.. tostring(player:getUsername()) .. ")")
	end
end

Events.OnClientCommand.Add(onClientCommand)

return XPR_SettingsStore
