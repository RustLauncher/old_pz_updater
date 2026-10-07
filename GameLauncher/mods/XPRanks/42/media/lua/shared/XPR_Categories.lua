XPR_Categories = XPR_Categories or {}

local KILL_XP_FALLBACK = {
	firearms = 10,
	melee = 10,
	vehicle = 10,
}

function XPR_Categories.getKillXpAmount(kind)
	if XPR_SettingsStore and XPR_SettingsStore.getKillXpAmount then
		return XPR_SettingsStore.getKillXpAmount(kind)
	end
	return KILL_XP_FALLBACK[kind] or 10
end

local CROSSMOD_XP_FALLBACK = {
	Efficiency = 1,
	CombatMastering = 2,
	Toughness = 5,
}

function XPR_Categories.getCrossModXp(perkName)
	local fallback = CROSSMOD_XP_FALLBACK[perkName]
	if not fallback then return nil end
	if XPR_SettingsStore and XPR_SettingsStore.getCrossModXp then
		return XPR_SettingsStore.getCrossModXp(perkName)
	end
	return fallback
end

XPR_CATEGORY_XP = {
	["Combat - Firearms"] = 1,
	["Combat - Melee"] = 2,
	["Crafting"] = 5,
	["Farming"] = 5,
	["Physical"] = 1,
	["Survival"] = 5,
}

function XPR_Categories.getCategoryXp(category)
	if XPR_SettingsStore and XPR_SettingsStore.getCategoryXp then
		return XPR_SettingsStore.getCategoryXp(category)
	end
	return XPR_CATEGORY_XP[category] or 0
end

XPR_PERK_TO_CATEGORY = {
	Reloading = "Combat - Firearms",

	Maintenance = "Combat - Melee",

	Woodwork = "Crafting",
	Carving = "Crafting",
	Cooking = "Crafting",
	Electricity = "Crafting",
	Glassmaking = "Crafting",
	FlintKnapping = "Crafting",
	Masonry = "Crafting",
	Blacksmith = "Crafting",
	Melting = "Crafting",
	Mechanics = "Crafting",
	Pottery = "Crafting",
	Tailoring = "Crafting",
	MetalWelding = "Crafting",

	Farming = "Farming",
	Husbandry = "Farming",
	Butchering = "Farming",

	Fitness = "Physical",
	Strength = "Physical",
	Sprinting = "Physical",
	Nimble = "Physical",
	Lightfoot = "Physical",
	Sneak = "Physical",

	Doctor = "Survival",
	Fishing = "Survival",
	PlantScavenging = "Survival",
	Tracking = "Survival",
	Trapping = "Survival",

	Efficiency = "Crafting",
	CombatMastering = "Combat - Melee",
	Toughness = "Survival",
}

XPR_KILL_PERK_CATEGORY = {
	Axe = "Combat - Melee",
	Blunt = "Combat - Melee",
	SmallBlunt = "Combat - Melee",
	LongBlade = "Combat - Melee",
	SmallBlade = "Combat - Melee",
	Spear = "Combat - Melee",
	Aiming = "Combat - Firearms",
	BareHands = "Combat - Melee",
}

XPR_ZOMBIE_KILL_CATEGORY = "Zombie Kill"

XPR_TIME_SURVIVED_CATEGORY = "Time Survived"

XPR_PVP_KILL_CATEGORY = "PVP Kill"

local PVP_XP_FALLBACK = 50

function XPR_Categories.getPvpXpAmount()
	if XPR_SettingsStore and XPR_SettingsStore.getPvpXpAmount then
		return XPR_SettingsStore.getPvpXpAmount()
	end
	return PVP_XP_FALLBACK
end

local pvpKillXpClientActive = false

function XPR_Categories.setPvpKillXpActive(active)
	pvpKillXpClientActive = active == true
end

function XPR_Categories.isPvpKillXpActive()
	if XPR_Env and XPR_Env.isSP() then return false end

	local featureOn
	if XPR_Env and XPR_Env.runsServerLogic() then
		if not (XPR_SettingsStore and XPR_SettingsStore.getPvpXpEnabled) then return false end
		featureOn = XPR_SettingsStore.getPvpXpEnabled() == true
	else
		featureOn = pvpKillXpClientActive
	end
	if not featureOn then return false end

	if not getServerOptions then return false end
	local opts = getServerOptions()
	if not opts or not opts.getBoolean then return false end
	return opts:getBoolean("PVP") == true
end

local TIME_SURVIVED_XP_FALLBACK = 10
local TIME_SURVIVED_INTERVAL_HOURS_FALLBACK = 6

function XPR_Categories.getTimeSurvivedXp()
	if XPR_SettingsStore and XPR_SettingsStore.getTimeSurvivedXp then
		return XPR_SettingsStore.getTimeSurvivedXp()
	end
	return TIME_SURVIVED_XP_FALLBACK
end

function XPR_Categories.getTimeSurvivedIntervalHours()
	if XPR_SettingsStore and XPR_SettingsStore.getTimeSurvivedIntervalHours then
		return XPR_SettingsStore.getTimeSurvivedIntervalHours()
	end
	return TIME_SURVIVED_INTERVAL_HOURS_FALLBACK
end

XPR_TRAVEL_WALK_CATEGORY = "Travel (On-Foot)"
XPR_TRAVEL_DRIVE_CATEGORY = "Travel (Driving)"

local TRAVEL_WALK_XP_FALLBACK = 10
local TRAVEL_WALK_TILES_FALLBACK = 150
local TRAVEL_DRIVE_XP_FALLBACK = 10
local TRAVEL_DRIVE_TILES_FALLBACK = 500

function XPR_Categories.getTravelWalkXp()
	if XPR_SettingsStore and XPR_SettingsStore.getTravelWalkXp then
		return XPR_SettingsStore.getTravelWalkXp()
	end
	return TRAVEL_WALK_XP_FALLBACK
end

function XPR_Categories.getTravelWalkTiles()
	if XPR_SettingsStore and XPR_SettingsStore.getTravelWalkTiles then
		return XPR_SettingsStore.getTravelWalkTiles()
	end
	return TRAVEL_WALK_TILES_FALLBACK
end

function XPR_Categories.getTravelDriveXp()
	if XPR_SettingsStore and XPR_SettingsStore.getTravelDriveXp then
		return XPR_SettingsStore.getTravelDriveXp()
	end
	return TRAVEL_DRIVE_XP_FALLBACK
end

function XPR_Categories.getTravelDriveTiles()
	if XPR_SettingsStore and XPR_SettingsStore.getTravelDriveTiles then
		return XPR_SettingsStore.getTravelDriveTiles()
	end
	return TRAVEL_DRIVE_TILES_FALLBACK
end

XPR_LEADERBOARD_CATEGORIES = {
	"Combat - Firearms",
	"Combat - Melee",
	"Crafting",
	"Farming",
	"Physical",
	"Survival",
	"Time Survived",
}

XPR_TRAVEL_LEADERBOARD_KEY = "Travel"
XPR_TRAVEL_LEADERBOARD_DISPLAY = "Travel"
XPR_TRAVEL_LEADERBOARD_SOURCES = { XPR_TRAVEL_WALK_CATEGORY, XPR_TRAVEL_DRIVE_CATEGORY }

function XPR_Categories.getLeaderboardSourceKeys(category)
	if category == XPR_TRAVEL_LEADERBOARD_KEY then
		return XPR_TRAVEL_LEADERBOARD_SOURCES
	end
	return { category }
end

XPR_DCS_CATEGORY_KEY = "DynamicChallenges"
XPR_DCS_CATEGORY_DISPLAY = "Dynamic Challenges"

local LB_DISPLAY_KEY = {
	["Overall"] = "IGUI_XPR_LbCat_Overall",
	["Combat - Firearms"] = "IGUI_XPR_LbCat_CombatFirearms",
	["Combat - Melee"] = "IGUI_XPR_LbCat_CombatMelee",
	["Crafting"] = "IGUI_XPR_LbCat_Crafting",
	["Farming"] = "IGUI_XPR_LbCat_Farming",
	["Physical"] = "IGUI_XPR_LbCat_Physical",
	["Survival"] = "IGUI_XPR_LbCat_Survival",
	["Time Survived"] = "IGUI_XPR_LbCat_TimeSurvived",
	[XPR_PVP_KILL_CATEGORY] = "IGUI_XPR_LbCat_PvpKills",
}

local TICKER_LABEL_KEY = {
	["Overall"] = "IGUI_XPR_LbCat_Overall",
	["Combat - Firearms"] = "IGUI_XPR_LbCat_CombatFirearms",
	["Combat - Melee"] = "IGUI_XPR_LbCat_CombatMelee",
	["Crafting"] = "IGUI_XPR_LbCat_Crafting",
	["Farming"] = "IGUI_XPR_LbCat_Farming",
	["Physical"] = "IGUI_XPR_LbCat_Physical",
	["Survival"] = "IGUI_XPR_LbCat_Survival",
	["Time Survived"] = "IGUI_XPR_LbCat_TimeSurvived",
	[XPR_ZOMBIE_KILL_CATEGORY] = "IGUI_XPR_TickerCat_ZombieKill",
	[XPR_PVP_KILL_CATEGORY] = "IGUI_XPR_TickerCat_PvpKill",
	[XPR_TRAVEL_WALK_CATEGORY] = "IGUI_XPR_TickerCat_TravelOnFoot",
	[XPR_TRAVEL_DRIVE_CATEGORY] = "IGUI_XPR_TickerCat_TravelDriving",
}

function XPR_Categories.getTickerLabel(category)
	if not category then return "" end
	local key = TICKER_LABEL_KEY[category]
	if not key then return category end
	local text = getText(key)
	if not text or text == "" or text == key then return category end
	return text
end

function XPR_Categories.getLeaderboardCategories(skipDisplay)
	local function label(key, textKey)
		if skipDisplay then return key end
		return getText(textKey)
	end
	local list = {
		{ key = "Overall", display = label("Overall", "IGUI_XPR_LbCat_Overall") },
		{ key = XPR_ZOMBIE_KILL_CATEGORY, display = label(XPR_ZOMBIE_KILL_CATEGORY, "IGUI_XPR_LbCat_ZombieKills") },
	}
	if XPR_Categories.isPvpKillXpActive() then
		list[#list + 1] = { key = XPR_PVP_KILL_CATEGORY, display = label(XPR_PVP_KILL_CATEGORY, "IGUI_XPR_LbCat_PvpKills") }
	end
	for _, name in ipairs(XPR_LEADERBOARD_CATEGORIES) do
		list[#list + 1] = { key = name, display = label(name, LB_DISPLAY_KEY[name] or name) }
	end
	list[#list + 1] = { key = XPR_TRAVEL_LEADERBOARD_KEY, display = label(XPR_TRAVEL_LEADERBOARD_KEY, "IGUI_XPR_LbCat_Travel") }
	if XPR_Env and XPR_Env.isDCSActive and XPR_Env.isDCSActive() then
		list[#list + 1] = { key = XPR_DCS_CATEGORY_KEY, display = label(XPR_DCS_CATEGORY_KEY, "IGUI_XPR_LbCat_DynamicChallenges") }
	end
	return list
end

return XPR_Categories
