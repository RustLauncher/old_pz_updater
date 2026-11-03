require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Records/ALifeDifficultyPreset"
require "ProjectALife/Records/ALifePresetValues"
require "ProjectALife/Visitors/ALifeVisitorSchema"

ProjectALife = ProjectALife or {}

local Settings = { current = nil, live = { raw = {}, applied = 0, faults = 0 } }
ProjectALife.Settings = Settings
local behavior = ProjectALife.BehaviorSettings

local function copied(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function clamp(value, minimum, maximum, fallback)
    return math.max(minimum, math.min(maximum, tonumber(value) or fallback))
end

local function flag(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback
end

Settings.RATE_SCALES = { 0.5, 1, 1.5, 2.25, 3 }

Settings.AIM_DIFFICULTY = ProjectALife.PresetValues.aimValues
function Settings.aimDifficultyPercent(choice)
    return ProjectALife.PresetValues.aimDifficultyPercent(choice)
end
function Settings.rateScale(choice)
    local index = math.floor(tonumber(choice) or 2)
    return Settings.RATE_SCALES[index] or 1
end

Settings.survivorScale = 1
function Settings.factionWeightScale(faction, day)
    if type(faction) ~= "table" then return 1 end
    local relation = type(faction.relations) == "table" and faction.relations.player or nil
    local spawn = type(faction.spawn) == "table" and faction.spawn or {}
    local survivors = spawn.peaceable == true or relation == "friendly" or relation == "allied"
        or relation == "neutral" or relation == "careful"
    if survivors then return tonumber(Settings.survivorScale) or 1 end
    return Settings.hostileFactionScale(faction, day)
end

Settings.hostileWeight = 4
Settings.hostileWeightLate = 1.5
Settings.hostileFadeDays = 14

function Settings.hostileFactionScale(faction, day)
    local layers = ProjectALife.RelationLayers
    if layers == nil or type(layers.towardPlayer) ~= "function" then return 1 end
    local ok, word = pcall(layers.towardPlayer, faction, nil)
    if not (ok and word == "hostile") then return 1 end
    local balance = ProjectALife.RosterBalance
    if balance ~= nil and type(balance.legacy) == "function" and balance.legacy() then return 1 end
    local late = tonumber(Settings.hostileWeightLate) or 1
    local early = tonumber(Settings.hostileWeight) or late
    local age = tonumber(day)
    if age == nil then return late end
    local fade = math.max(0, 1 - math.max(0, age) / math.max(1, tonumber(Settings.hostileFadeDays) or 14))
    return late + (early - late) * fade
end

Settings.WORLD_PRESET_ROWS = ProjectALife.PresetValues.worldRows
Settings.hostChose = ProjectALife.PresetValues.hostChose
Settings.rowUntouched = ProjectALife.PresetValues.rowUntouched
Settings.legacyUntouched = ProjectALife.PresetValues.legacyUntouched
Settings.worldRowValue = ProjectALife.PresetValues.worldRowValue
Settings.DIFFICULTY_PRESET_ROWS = ProjectALife.DifficultyPreset.rows

function Settings.applyWorldPreset(current, source)
    return ProjectALife.PresetValues.applyWorld(current, source)
end

function Settings.applyDifficultyPreset(current, source)
    return ProjectALife.PresetValues.applyDifficulty(current, source)
end

Settings.PRESET_UPGRADE_FROM = 3
Settings.PRESET_UPGRADE_TO = 4

Settings.PRESET_UPGRADE_LIMIT = 3

function Settings.upgradeSavedPreset(vars, store, oldWorld)
    if type(vars) ~= "table" or type(store) ~= "table" then return false end
    if vars.Preset_ExplicitValues == true then return false end
    local from, to = Settings.PRESET_UPGRADE_FROM, Settings.PRESET_UPGRADE_TO
    local stored = tonumber(vars.Preset_World)
    if store.presetUpgradeSeen ~= true then
        store.presetUpgradeSeen = true
        if oldWorld ~= true or (stored ~= from and stored ~= nil) then return false end
        store.presetUpgradedFrom, store.presetUpgrades = from, 1
        vars.Preset_World = to
        return true
    end
    local done = tonumber(store.presetUpgrades) or 0
    if store.presetUpgradedFrom == from and stored == from and done < Settings.PRESET_UPGRADE_LIMIT then
        store.presetUpgrades = done + 1
        vars.Preset_World = to
        return true
    end
    return false
end

function Settings.applySavedPresetUpgrade()
    if type(SandboxVars) ~= "table" or type(ModData) ~= "table" or type(ModData.getOrCreate) ~= "function" then return false end
    if type(isServer) == "function" and isServer() then return false end
    if type(isClient) == "function" and isClient() then return false end
    SandboxVars.ALife = type(SandboxVars.ALife) == "table" and SandboxVars.ALife or {}
    local persistence = ProjectALife.Persistence
    local tag = type(persistence) == "table" and persistence.TAG or "ProjectALife.World.v1"
    local oldWorld = type(ModData.exists) == "function" and ModData.exists(tag) == true
    local ok, store = pcall(ModData.getOrCreate, "ProjectALifeSettings")
    if not ok or type(store) ~= "table" then return false end
    local changed = Settings.upgradeSavedPreset(SandboxVars.ALife, store, oldWorld)
    if changed and type(getSandboxOptions) == "function" then
        pcall(function()
            local options = getSandboxOptions()
            local option = options ~= nil and options:getOptionByName("ALife.Preset_World") or nil
            if option ~= nil then option:setValue(SandboxVars.ALife.Preset_World) end
        end)
    end
    return changed
end

function Settings.read(source, pure)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    source = source or {}
    local current = {

        enabled = true,
        hostileEnabled = flag(source.World_HostileEnabled, true),

        presetWorld = math.floor(clamp(source.Preset_World, 1, 5, 3)),
        presetDifficulty = math.floor(clamp(source.Preset_Difficulty, 1, 4, 2)),

        spawnMultiplier = clamp(source.Population_RatePercent, 25, 400, 200) / 100,
        groupMultiplier = clamp(source.Population_PartyPercent, 50, 200, 125) / 100,
        simulationRadius = math.floor(clamp(
            source.World_SimRadius, 40, 250, 90)),
        encounterChance = clamp(source.Encounters_RollPercent, 0, 100, 40) / 100,

        rateEncounters = Settings.rateScale(source.Rate_Encounters),
        rateGroups = Settings.rateScale(source.Rate_Groups),
        rateSurvivors = Settings.rateScale(source.Rate_Survivors),
        rateMetaEvents = Settings.rateScale(source.Rate_MetaEvents),
        encounterIntervalHours = clamp(source.Encounters_GapHours, 1, 24, 3),
        maximumHostileActors = math.floor(clamp(source.Population_HostileCeiling, 4, 160, 32)),
        safehouseMargin = math.floor(clamp(source.World_SafehouseClearance, 0, 50, 8)),
        warfare = flag(source.World_FactionWarfare, true),

        realisticOutbreak = flag(source.Realistic_Outbreak, true),
        retreat = flag(source.Behavior_Retreat, true),
        closeDoors = flag(source.Behavior_CloseDoors, true),
        npcsReanimate = flag(source.Behavior_NPCsReanimate, true),
        turningEnabled = flag(source.Turning_Enabled, true),
        turningDelayMinS = math.floor(clamp(source.Turning_DelaySecondsMin, 0, 600, 20)),
        turningDelayMaxS = math.floor(clamp(source.Turning_DelaySecondsMax, 0, 600, 90)),

        voiceEnabled = flag(source.Voice_Enabled, false),
        moduleCover = flag(source.Modules_Cover, true),
        moduleStrafe = flag(source.Modules_Strafe, true),
        moduleWithdraw = flag(source.Modules_Withdraw, true),
        moduleFear = flag(source.Modules_Fear, true),
        fearDays = math.floor(clamp(source.Fear_Days, 0, 30, 7)),
        fearLevel = math.floor(clamp(source.Fear_Level, 1, 3, 2)),
        fearLingering = math.floor(clamp(source.Fear_Lingering, 0, 100, 50)),
        gunFearPercent = math.floor(clamp(source.GunFear_Percent, 0, 100, 60)),
        gunFearRunDistance = math.floor(clamp(source.GunFear_RunDistance, 8, 80, 35)),
        gunFearRunSpeed = math.floor(clamp(source.GunFear_RunSpeed, 1, 2, 2)) == 1 and "run" or "sprint",
        gunFearReactDelayMs = math.floor(clamp(source.GunFear_ReactDelayMs, 0, 3000, 400)),
        moduleHealing = flag(source.Modules_Healing, true),
        sprintEnabled = flag(source.Modules_Sprint,
            behavior.movement.sprintEnabled ~= false),
        moduleGunner = flag(source.Modules_Gunner, true),
        behaviorsEnabled = flag(source.Modules_Behaviors, true),
        dormantTtlHours = tonumber(source.Population_DormantTtlHours) or 8,
        encountersEnabled = flag(source.Encounters_Enabled, true),

        encounterIntervalMinutes = clamp(source.Encounters_IntervalMinutes, 10, 720, 45),
        combatWounds = flag(source.Combat_Wounds, true),
        meleeFootwork = flag(source.Combat_MeleeFootwork, true),
        meleeKiteCrowd = math.floor(clamp(source.Combat_MeleeKiteCrowd, 0, 8, 2)),
        meleeKiteTiles = math.floor(clamp(source.Combat_MeleeKiteTiles, 1, 5, 2)),
        meleeKiteStep = clamp(source.Combat_MeleeStepBackTenths, 3, 30, 16) / 10,
        meleeStepIn = clamp(source.Combat_MeleeStepInTenths, 3, 25, 11) / 10,

        visibleTracers = flag(source.Combat_VisibleTracers, true),
        muzzleFlash = flag(source.Combat_MuzzleFlash, true),

        showAdminTools = flag(source.Debug_ShowAdminTools, true),
        cleanupRespawnAfter = flag(source.Cleanup_RespawnAfter, false),
        talkMystery = flag(source.Talk_MysteryMode, true),
        vehicleDamage = flag(source.Combat_VehicleDamage, true),
        nonPvpShield = flag(source.Combat_NonPvpZoneShield, false),
        aimPlayerPercent = Settings.aimDifficultyPercent(source.Combat_AimDifficulty),
        aimZombiePercent = clamp(source.Combat_AimZombiePercent, 10, 200, 100),
        aimPlayerGlobalPercent = clamp(source.Combat_AimPlayerPercent, 10, 200, 70),
        npcDamagePercent = clamp(source.Combat_DamagePercent, 0, 100, 72),
        npcHealthPercent = clamp(source.NpcHealth_Percent, 25, 300, 98),
        warningChancePercent = clamp(source.Warning_ChancePercent, 0, 100, 15),
        extraWoundPercent = clamp(source.Combat_ExtraWoundPercent, 0, 200, 0),
        roomSweep = flag(source.Combat_RoomSweep, true),
        searchEnabled = flag(source.Search_Enabled, true),
        searchShout = flag(source.Search_ShoutResponse, true),
        searchCallout = flag(source.Search_GroupCallout, true),
        cluesEnabled = flag(source.Clues_Enabled, true),
        cluesVehicles = flag(source.Clues_Vehicles, true),
        cluesBarricades = flag(source.Clues_Barricades, true),
        cluesPlayerBuilt = flag(source.Clues_PlayerBuilt, true),
        cluesPower = flag(source.Clues_Power, true),
        cluesWeight = clamp(source.Clues_WeightMultiplier, 0.25, 5, 1),
        weaponDrops = flag(source.Drops_WeaponsEnabled, true),

        dropWeaponChance = math.floor(clamp(source.Drops_WeaponChance, 1, 9, 1)),
        dropWeaponCondition = math.floor(clamp(source.Drops_WeaponCondition, 1, 12, 1)),
        weaponJamming = flag(source.Combat_EnableJamming, true),
        weaponJamChance = clamp(source.Combat_JamChance, 0, 25, 1),

        breachStrength = clamp(source.Breach_Strength, 25, 200, 100),

        multiHit = flag(source.Combat_MultiHit, false),
        bulletPenetration = flag(source.Combat_BulletPenetration, false),

        populateMode = ({ "off", "rare", "uncommon", "common" })[math.floor(clamp(source.Population_PopulateOnStart, 1, 4, 1))] or "off",
        populateMaximum = math.floor(clamp(source.Population_PopulateMax, 1, 200, 75)),
        townWelcomeEnabled = flag(source.TownWelcome_Enabled, true),
        townWelcomePerTown = math.floor(clamp(source.TownWelcome_GroupsPerTown, 1, 6, 4)),
        townWelcomeFirstDayOnly = flag(source.TownWelcome_FirstDayOnly, true),

        talkEnabled = flag(source.Talk_Enabled, true),
        talkSinglePlayerChat = flag(source.Talk_SinglePlayerChat, true),
        talkPresence = flag(source.Talk_Presence, true),
        talkRiskAssessment = flag(source.Talk_RiskAssessment, true),
        robberyEnabled = flag(source.Robbery_Enabled, true),
        robberyChance = math.floor(clamp(source.Robbery_Chance, 0, 200, 100)),
        ordersEnabled = flag(source.Orders_Enabled, true),
        ordersChance = math.floor(clamp(source.Orders_Chance, 0, 200, 100)),
        ordersZombieTiles = math.floor(clamp(source.Orders_ZombieTiles, 1, 8, 4)),
        ordersFightPercent = math.floor(clamp(source.Orders_FailFight, 0, 100, 100)),
        ordersSurrenderSeconds = math.floor(clamp(source.Orders_SurrenderSeconds, 10, 600, 90)),
        radioKnoxCounty = flag(source.Radio_KnoxCounty, true),
        theft = flag(source.Behavior_Scavenge, true),

        nightvision = (tonumber(source.Night_Sight) or 1) == 2,

        nightActivity = math.floor(clamp(source.Night_Activity, 1, 5, 3)),

        panicFirstDays = flag(source.Panic_FirstDays, true),
        panicStrength = math.floor(clamp(source.Panic_Strength, 0, 200, 100)),
        panicLengthDays = math.floor(clamp(source.Panic_LengthDays, 2, 60, 12)),
        panicContagion = flag(source.Panic_Contagion, true),

        offlineSquadCap = math.floor(clamp(source.Offline_SquadCap, 0, 500, 45)),

        persistentSquadCap = math.floor(clamp(source.Population_PersistentSquadCap, 0, 500, 60)),
        keepEncounterNpcs = flag(source.Population_KeepEncounterNpcs, false),
        outpostTaskSquadCap = math.floor(clamp(source.Outposts_TaskSquadCap, 0, 4, 3)),
        offlineTickSeconds = math.floor(clamp(source.Offline_TickSeconds, 10, 60, 20)),
        offlineTravelTilesPerHour = math.floor(clamp(source.Offline_TravelTilesPerHour, 20, 400, 150)),
        offlineRevenge = flag(source.Offline_RevengeEnabled, true),

        outpostsEnabled = flag(source.Outposts_Enabled, true),
        outpostsMaxSites = math.floor(clamp(source.Outposts_MaxSites, 0, 16, 9)),
        outpostsPerCity = math.floor(clamp(source.Outposts_PerCity, 1, 3, 2)),
        outpostsIntervalMinutes = math.floor(clamp(source.Outposts_IntervalMinutes, 5, 120, 20)),
        outpostsChance = math.floor(clamp(source.Outposts_Chance, 0, 100, 35)),
        outpostsBuildRadius = math.floor(clamp(source.Outposts_BuildRadius, 60, 200, 120)),
        outpostsStreamHoldSeconds = clamp(source.Outposts_StreamHoldSeconds, 5, 30, 5),
        outpostsBuildBudget = math.floor(clamp(source.Outposts_BuildBudget, 1, 2000, 100)),
        outpostsMaxCompounds = math.floor(clamp(source.Outposts_MaxCompounds, 0, 40, 1)),
        outpostsCompoundSpacing = clamp(source.Outposts_CompoundSpacing, 0, 5000, 500),
        outpostsLightsOn = flag(source.Outposts_LightsOn, true),
        outpostsSpawnRadius = math.floor(clamp(source.Outposts_SpawnRadius, 40, 150, 90)),
        outpostsStructureLoss = math.floor(clamp(source.Outposts_StructureLossPercent, 0, 100, 40)),
        supportEnabled = flag(source.Support_Enabled, true),

        worldMode = math.floor(clamp(source.World_Mode, 1, 2, 1)),

        outpostsOutsideCity = math.floor(clamp(source.Outposts_OutsideCity, 0, 8, 4)),

        patrolRestEnabled = flag(source.PatrolRest_Enabled, true),
        patrolRestMinMinutes = math.floor(clamp(source.PatrolRest_MinMinutes, 5, 180, 20)),
        patrolRestMaxMinutes = math.floor(clamp(source.PatrolRest_MaxMinutes, 10, 240, 45)),
        patrolRestEveryHours = clamp(source.PatrolRest_EveryHours, 0.5, 48, 3),
        partyLoneWeight = clamp(source.Party_LoneWeight, 0, 20, 2),
        partyGroupWeight = clamp(source.Party_GroupWeight, 0, 20, 2),
        funnelEnabled = flag(source.Funnel_Enabled, true),
        funnelDayOffset = math.floor(clamp(source.Funnel_DayOffset, -3650, 3650, 0)),
        funnelLoneMax = math.floor(clamp(source.Funnel_LoneSurvivorMax, 1, 2, 2)),
        funnelSkillPercent = math.floor(clamp(source.Funnel_SkillRampPercent, 0, 200, 100)),
        offlineFoundGapHours = clamp(source.Offline_FoundGapHours, 0.25, 48, 3),
        raidEnabled = flag(source.Raid_Enabled, true),
        raidMinDay = math.floor(clamp(source.Raid_MinDay, 0, 365, 21)),
        raidCooldownDays = clamp(source.Raid_CooldownDays, 0.25, 60, 14),
        raidChance = clamp(source.Raid_Chance, 0, 100, 0.025),
        raidCheckMinutes = math.floor(clamp(source.Raid_CheckMinutes, 1, 120, 10)),
        raidWaves = math.floor(clamp(source.Raid_Waves, 1, 10, 4)),
        raidGroupSize = math.floor(clamp(source.Raid_GroupSize, 1, 12, 8)),
        raidMaxAttackers = math.floor(clamp(source.Raid_MaxAttackers, 1, 48, 12)),
        raidWarningHours = clamp(source.Raid_WarningHours, 0, 24, 3),
        raidSirenAircraft = flag(source.Raid_SirenAircraftSounds, true),
        raidWaveDelayMinutes = math.floor(clamp(source.Raid_WaveDelayMinutes, 1, 120, 5)),
        raidHeli = flag(source.Raid_Helicopter, true),
        raidScoutBuildupHours = clamp(source.Raid_ScoutBuildupHours, 0, 72, 6),
        raidScoutLifetimeHours = clamp(source.Raid_ScoutLifetimeHours, 1, 168, 48),
        raidScoutSize = math.floor(clamp(source.Raid_ScoutSize, 1, 6, 4)),
        supportChance = math.floor(clamp(source.Support_Chance, 0, 100, 35)),
        supportCooldownHours = clamp(source.Support_CooldownHours, 0, 24, 1.5),
        supportGroupSize = math.floor(clamp(source.Support_GroupSize, 1, 8, 4)),
        supportMaxCalls = math.floor(clamp(source.Support_MaxCalls, 0, 10, 2)),
        supportSpotlightChance = math.floor(clamp(source.Support_SpotlightChance, 0, 100, 20)),
        supportSpotlightSeconds = math.floor(clamp(source.Support_SpotlightSeconds, 5, 180, 180)),
        supportHelicopterSeconds = math.floor(clamp(source.Support_HelicopterSeconds, 5, 180, 35)),
        heliSpotlight = flag(source.Helicopter_Spotlight, true),
        heliSpotlightSize = math.floor(clamp(source.Helicopter_SpotlightSize, 4, 20, 11)),
        heliSpotlightBrightness = math.floor(clamp(source.Helicopter_SpotlightBrightness, 20, 100, 100)),
        heliSpotlightGapMinutes = math.floor(clamp(source.Helicopter_SpotlightGapMinutes, 2, 240, 20)),
        residentCorpses = flag(source.Residents_ClearCorpses, true),
        scavengeBuildingRadius = math.floor(clamp(source.Scavenge_BuildingRadius, 10, 60, 27)),
        scavengeCarryLimit = math.floor(clamp(source.Scavenge_CarryLimit, 1, 24, 8)),
        scavengeReturnAfterBuildings = math.floor(clamp(source.Scavenge_ReturnAfterBuildings, 1, 8, 2)),

        ammoSpawnPercent = math.floor(clamp(source.Ammo_SpawnPercent, 0, 200, 100)),

        ammoReserveLoads = math.floor(clamp(source.Ammo_ReserveLoads, 0, 20, 2)),

        ammoBottomless = math.floor(clamp(source.Ammo_Bottomless, 1, 3, 1)),

        ammoHonestDrops = flag(source.Ammo_HonestDrops, true),
        seasonalDress = flag(source.Loadouts_SeasonalDress, true),
        appearanceVariation = flag(source.Appearance_Variation, true),
        appearanceKeepAuthored = math.floor(clamp(source.Appearance_KeepAuthoredPercent, 0, 100, 35)),
        appearanceLoadoutVariation = flag(source.Appearance_LoadoutVariation, true),
        coldEnabled = flag(source.Cold_Enabled, true),
        coldSeverity = math.floor(clamp(source.Cold_Severity, 0, 300, 100)),
        coldChance = clamp(source.Cold_ChancePercent, 0, 100, 6),
        coldSneezeNoise = flag(source.Cold_SneezeNoise, true),
        coldSeek = flag(source.Cold_SeekWarmth, true),
        campWarmHands = flag(source.Idle_CampWarmHands, true),
        benchSeat = flag(source.Idle_BenchSeat, true),
        uniformDecayDay = math.floor(clamp(source.Loadouts_UniformDecayDay, 0, 365, 10)),
        armingPace = math.floor(clamp(source.Loadouts_ArmingPace, 25, 400, 100)),
        armingShare = math.floor(clamp(source.Loadouts_ArmingShare, 0, 200, 100)),
        survivorOutposts = flag(source.Outposts_SurvivorHolds, true),
        earlyLootersPercent = math.floor(clamp(source.Encounters_EarlyLooters, 0, 300, 100)),
        censusSize = math.floor(clamp(source.Census_Size, 20, 5000, 360)),
        censusEarlyPerWeek = clamp(source.Census_ArrivalsEarly, 0, 100, 7),
        censusLatePerWeek = clamp(source.Census_ArrivalsLate, 0, 100, 1),
        censusFadeDays = clamp(source.Census_ArrivalsFadeDays, 1, 365, 28),
        censusClearedDays = clamp(source.Census_ClearedDays, 1, 365, 30),
        censusResettle = flag(source.Census_Resettle, true),
        fairTell = flag(source.Fair_TellBeforeStrike, true),
        fairGraceSeconds = clamp(source.Fair_FirstContactGrace, 0, 10, 2.5),
        fairWarningLeadSeconds = clamp(source.Fair_WarningLead, 0.5, 6, 1.5),
        fairEntryLeadSeconds = clamp(source.Fair_EntryLead, 0, 6, 1.5),
        fairWindowOpenSeconds = clamp(source.Fair_WindowOpenTime, 0.3, 4, 1.2),
        fairFightMemoryMinutes = math.floor(clamp(source.Fair_FightMemory, 10, 240, 60)),
        encounterStandoffs = flag(source.Encounter_Standoffs, true),
        encounterSurpriseSeconds = clamp(source.Encounter_SurpriseSeconds, 1, 10, 3),
        encounterAnswerSeconds = math.floor(clamp(source.Encounter_AnswerSeconds, 4, 30, 10)),
        encounterCalloutPercent = math.floor(clamp(source.Encounter_CalloutPercent, 0, 200, 100)),
        encounterCalloutSeconds = math.floor(clamp(source.Encounter_CalloutSeconds, 15, 180, 45)),
        encounterBetrayalPercent = math.floor(clamp(source.Encounter_BetrayalPercent, 0, 200, 100)),
        encounterSearchSeconds = math.floor(clamp(source.Encounter_SearchSeconds, 20, 600, 90)),
        encounterLostSightSeconds = clamp(source.Encounter_LostSightSeconds, 2, 30, 6),
        encounterFixBlurTiles = math.floor(clamp(source.Encounter_FixBlurTiles, 0, 60, 12)),
        revengeMaxWaves = math.floor(clamp(source.Revenge_MaxWaves, 1, 10, 2)),
        outplayStagger = flag(source.Outplay_Stagger, true),
        injuryBleedPercent = math.floor(clamp(source.Combat_InjuryBleed, 0, 300, 100)),
        bluntFracturePercent = math.floor(clamp(source.Combat_BluntFracture, 0, 50, 4)),
    }
    Settings.applyWorldPreset(current, source)
    Settings.applyDifficultyPreset(current, source)
    Settings.applyOutbreak(current, source)
    Settings.readActivities(current, source)
    if pure ~= true then
        Settings.current = current
        Settings.visitorBlock = Settings.readVisitors(source)
    end
    return current
end

function Settings.readReputation(source)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    source = source or {}
    local neutral = math.floor(clamp(source.Reputation_KillNeutral, 0, 500, 40))
    return {
        enabled = flag(source.Reputation_Tracking, true),
        showScore = flag(source.Reputation_ShowScore, true),
        showOthers = flag(source.Reputation_ShowOthers, false),
        radioNames = flag(source.Reputation_RadioNames, true),
        radioBadNews = flag(source.Reputation_RadioBadNews, true),
        npcFightIsHostile = flag(source.Reputation_NpcFightIsHostile, true),
        driftPerDay = math.floor(clamp(source.Reputation_DriftPerDay, 0, 50, 5)),
        killScale = math.floor(clamp(source.Reputation_KillScale, 0, 300, 100)),
        gainCapPerDay = math.floor(clamp(source.Reputation_GainCapPerDay, 0, 1000, 60)),
        overCapPercent = math.floor(clamp(source.Reputation_OverCapPercent, 0, 100, 25)),
        hysteresis = math.floor(clamp(source.Reputation_Hysteresis, 0, 100, 15)),
        kill = {
            hostile = math.floor(clamp(source.Reputation_KillHostile, 0, 200, 10)),
            crime = math.floor(clamp(source.Reputation_KillCrime, 0, 200, 15)),
            neutral = -neutral, careful = -neutral,
            friendly = -math.floor(clamp(source.Reputation_KillFriendly, 0, 500, 80)),
            surrendered = -math.floor(clamp(source.Reputation_KillSurrendered, 0, 500, 100)),
        },
    }
end

function Settings.applyProfessionRolls(source)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    source = source or {}
    local rules = ProjectALife.FactionSpawnRules
    if rules ~= nil then rules.professionRolls = flag(source.Reputation_ProfessionEncounters, true) end
    local personal = ProjectALife.PersonalRep
    if personal ~= nil then personal.recognizeOn = flag(source.Reputation_ProfessionRecognition, true) end
    return true
end

function Settings.readStanding(source)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    source = source or {}
    return { enabled = tonumber(source.Reputation_Mode) == 2,
        decayPercent = clamp(source.Reputation_DecayPercent, 0, 300, 100) }
end

function Settings.readSafehouse(source)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    source = source or {}
    return {
        frequency = math.floor(clamp(source.Safehouse_Events, 1, 4, 3)),
        betrayal = flag(source.Safehouse_Betrayal, true),
        attacks = flag(source.Safehouse_Attacks, true),
        entry = math.floor(clamp(source.Safehouse_Entry, 1, 2, 1)),
        quietDays = math.floor(clamp(source.Safehouse_QuietDays, 0, 14, 3)),
        dedicated = flag(source.Safehouse_Dedicated, true),
        chancePercent = math.floor(clamp(source.Safehouse_ChancePercent, 1, 100, 12)),
        checkHours = clamp(source.Safehouse_CheckHours, 1, 24, 2),
        gapDays = clamp(source.Safehouse_GapDays, 0.5, 14, 2),
        visitGapDays = clamp(source.Safehouse_VisitGapDays, 1, 30, 1),
        attackGapDays = clamp(source.Safehouse_AttackGapDays, 1, 60, 1),
        attackMinDay = math.floor(clamp(source.Safehouse_AttackMinDay, 0, 365, 14)),
        densityMid = math.floor(clamp(source.Safehouse_DensityMid, 0, 200, 10)),
        densityHigh = math.floor(clamp(source.Safehouse_DensityHigh, 0, 400, 30)),
        densityExtreme = math.floor(clamp(source.Safehouse_DensityExtreme, 0, 800, 60)),
        awayTiles = math.floor(clamp(source.Safehouse_AwayTiles, 10, 60, 40)),
        hiddenTiles = math.floor(clamp(source.Safehouse_HiddenTiles, 5, 60, 20)),
        dropDeadlineDays = math.floor(clamp(source.Safehouse_DropDeadlineDays, 1, 14, 3)),
        mailboxTiles = math.floor(clamp(source.Safehouse_MailboxTiles, 2, 20, 10)),
        baseFlag = flag(source.Safehouse_BaseFlag, true),
        inviteMinutes = math.floor(clamp(source.Safehouse_InviteMinutes, 2, 60, 10)),
        visitorHoldSeconds = math.floor(clamp(source.Safehouse_VisitorHoldSeconds, 0, 120, 30)),
        knockSounds = flag(source.Safehouse_KnockSounds, true),
        squatPercent = math.floor(clamp(source.Safehouse_SquatPercent, 0, 100, 15)),
        bittenPercent = math.floor(clamp(source.Safehouse_BittenPercent, 0, 100, 15)),
        ladderGapHours = math.floor(clamp(source.Safehouse_LadderGapHours, 12, 240, 48)),
        baseScore = math.floor(clamp(source.Safehouse_BaseScore, 20, 400, 100)),
        scriptedEffects = flag(source.Events_ScriptedEffects, true),
        traderVisits = flag(source.Safehouse_TraderVisits, false),
        radioActivate = flag(source.Events_RadioActivate, true),
        wallMarks = flag(source.Events_WallMarks, true),
    }
end

function Settings.readVisitors(source)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    source = source or {}
    local result = {
        persons = flag(source.Visitors_Persons, true),
        proactiveLevel = math.floor(clamp(source.Visitors_ProactiveEvents, 1, 4, 3)),
        eventMinGapSeconds = math.floor(clamp(source.Visitors_EventMinGapSeconds, 60, 1800, 240)),
        stayHours = math.floor(clamp(source.Visitors_StayHours, 1, 48, 1)),
        parties = flag(source.Visitors_Parties, true),
        returningChance = math.floor(clamp(source.Visitors_ReturningChance, 0, 50, 15)),
        life = flag(source.Visitors_Life, true),
        changeClothes = flag(source.Visitors_ChangeClothes, true),
        privacy = math.floor(clamp(source.Visitors_Privacy, 1, 2, 1)),
        flirtLevel = math.floor(clamp(source.Visitors_Flirt, 1, 2, 2)),
        books = flag(source.Visitors_Books, true),
        chatMirror = flag(source.Visitors_ChatMirror, true),
        debug = flag(source.Visitors_Debug, false),
    }
    result.proactive = result.proactiveLevel > 1
    local schema = ProjectALife.VisitorSchema
    if schema ~= nil and schema.PROACTIVE[result.proactiveLevel] ~= nil then
        result.eventGapScale = schema.PROACTIVE[result.proactiveLevel].gap
    end
    result.privacyStrict = result.privacy == 1
    result.flirt = result.flirtLevel == 2
    return result
end

function Settings.visitors()
    if type(Settings.visitorBlock) == "table" then return Settings.visitorBlock end
    return Settings.readVisitors(nil)
end

function Settings.applyOutbreak(current, source)
    return current
end

function Settings.readActivities(current, source)
    current.activitiesEnabled = flag(source.Activities_Enabled, true)
    current.activitiesSwitchChance = math.floor(clamp(source.Activities_SwitchChance, 0, 100, 70))
    current.activitiesNeedsDrainPercent = math.floor(clamp(source.Activities_NeedsDrainPercent, 25, 400, 100))
    current.activitiesAdoptCap = math.floor(clamp(source.Activities_AdoptCap, 0, 24, 6))
    current.activitiesFixedCarDrivable = flag(source.Activities_FixedCarDrivable, true)
    current.activitiesFixedCarFuelPercent = math.floor(clamp(source.Activities_FixedCarFuelPercent, 0, 100, 15))
    current.activitiesFishing = flag(source.Activities_Fishing, true)
    current.activitiesHunting = math.floor(clamp(source.Activities_Hunting, 1, 3, 3))
    current.activitiesSwitchHours = math.floor(clamp(source.Activities_SwitchHours, 1, 72, 10))
    current.activitiesSwitchClearTiles = math.floor(clamp(source.Activities_SwitchClearTiles, 20, 150, 60))
    current.activitiesBases = flag(source.Activities_Bases, true)
    current.activitiesMaxBases = math.floor(clamp(source.Activities_MaxBases, 0, 24, 6))
    current.activitiesBaseChance = math.floor(clamp(source.Activities_BaseChance, 0, 100, 25))
    current.activitiesPartyWeight = math.floor(clamp(source.Activities_PartyWeight, 0, 500, 100))
    current.activitiesBaseReturnHours = math.floor(clamp(source.Activities_BaseReturnHours, 2, 48, 8))
    current.activitiesBaseClearTiles = math.floor(clamp(source.Activities_BaseClearTiles, 20, 120, 45))
    current.activitiesHuntYieldPercent = math.floor(clamp(source.Activities_HuntYieldPercent, 0, 300, 100))
    current.activitiesFishYieldPercent = math.floor(clamp(source.Activities_FishYieldPercent, 0, 300, 100))
    current.activitiesFishingMinutes = math.floor(clamp(source.Activities_FishingMinutes, 10, 240, 65))
    current.activitiesForaging = flag(source.Activities_Foraging, true)
    current.activitiesForageYieldPercent = math.floor(clamp(source.Activities_ForageYieldPercent, 0, 300, 100))
    return current
end

function Settings.applyModuleSwitches(source, value)
    local registry = ProjectALife.ModuleRegistry
    if registry == nil then return false end
    source = source or (SandboxVars and SandboxVars.ALife) or {}
    local switches = {
        scavenge = source.Behavior_Scavenge,
        flee = source.Behavior_Retreat,
        investigate = source.Behavior_Investigate,
        regroup = source.Behavior_Regroup,
        groupMarch = source.Behavior_MarchTogether,
        cover = source.Modules_Cover,
        strafe = source.Modules_Strafe,
        withdraw = source.Modules_Withdraw,
        fear = source.Modules_Fear,
        gunFear = source.GunFear_Enabled,
        weave = source.Modules_Strafe,
        healing = source.Modules_Healing,
        gunner = source.Modules_Gunner,
        leader = source.Modules_Behaviors,
        sniper = source.Modules_Behaviors,
        medic = source.Modules_Behaviors,
        ambusher = source.Modules_Behaviors,
        stealth = source.Modules_Behaviors,
        stance = source.Modules_Behaviors,
        patrolRest = source.PatrolRest_Enabled,
    }
    for id, enabled in pairs(switches) do
        if enabled ~= nil then registry.setEnabled(id, enabled ~= false) end
    end
    pcall(function()
        local director = ProjectALife.EncounterDirector
        if director ~= nil then
            local read = type(value) == "table" and value or nil
            director.configure({
                enabled = source.Encounters_Enabled ~= false,

                intervalMinutes = read and tonumber(read.encounterIntervalMinutes)
                    or clamp(source.Encounters_IntervalMinutes, 10, 720, 45),
                chance = read and tonumber(read.encounterChance)
                    and math.min(1, read.encounterChance * (tonumber(read.rateEncounters) or 1))
                    or clamp(source.Encounters_RollPercent, 0, 100, 40) / 100,
            })
        end
    end)
    pcall(function()
        local population = ProjectALife.Population
        if population ~= nil and source.Population_DormantTtlHours ~= nil then
            population.configureTtl(source.Population_DormantTtlHours)
        end
    end)

    pcall(function()
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and source.Combat_Wounds ~= nil then
            healthSystem.configure({ enabled = source.Combat_Wounds ~= false })
        end
    end)
    return true
end

function Settings.applySearchOptions(value)
    pcall(function()
        local investigation = ProjectALife.Investigation
        if investigation ~= nil and type(investigation.configure) == "function" then
            investigation.configure({
                enabled = value.searchEnabled,
                shout = value.searchShout,
                contact = value.searchCallout,
            })
        end
    end)
    pcall(function()

        local tracer = ProjectALife.Tracer
        if tracer ~= nil and type(tracer.configure) == "function" then
            tracer.configure({ enabled = value.visibleTracers, flash = value.muzzleFlash })
        end
    end)
    pcall(function()
        local clues = ProjectALife.Clues
        if clues ~= nil and type(clues.configure) == "function" then
            clues.configure({
                enabled = value.cluesEnabled,
                weightMultiplier = value.cluesWeight,
                sources = {
                    vehicles = value.cluesVehicles,
                    barricades = value.cluesBarricades,
                    playerBuilt = value.cluesPlayerBuilt,
                    power = value.cluesPower,
                },
            })
        end
    end)
    return true
end

function Settings.runtimeOptions(source)
    local value = Settings.read(source)
    Settings.applySearchOptions(value)
    Settings.applyModuleSwitches(source, value)
    local scavenging = copied(behavior.scavenging)
    scavenging.enabled = value.theft
    local combat = copied(behavior.combat)
    combat.jammingEnabled = value.weaponJamming
    combat.jamChancePercent = value.weaponJamChance
    combat.multiHit = value.multiHit
    combat.bulletPenetration = value.bulletPenetration
    combat.meleeFootwork = value.meleeFootwork
    combat.meleeKiteCrowd = value.meleeKiteCrowd
    combat.meleeKiteTiles = value.meleeKiteTiles
    combat.meleeKiteStep = value.meleeKiteStep
    combat.meleeStepIn = value.meleeStepIn

    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.settings) == "table" then
        traversal.settings.breachStrengthPercent = value.breachStrength
        traversal.settings.closeDoors = value.closeDoors ~= false
    end
    local movement = copied(behavior.movement)
    movement.sprintEnabled = value.sprintEnabled
    behavior.movement.sprintEnabled = value.sprintEnabled
    Settings.survivorScale = value.rateSurvivors or 1
    local census = ProjectALife.WorldPressure
    if type(census) == "table" and type(census.configureCensus) == "function" then census.configureCensus(value) end
    local groupScale = value.rateGroups or 1
    return {
        enabled = value.enabled,
        personalReputationAdapters = Settings.readReputation(source),
        standingAdapters = Settings.readStanding(source),
        persistenceAdapters = { squadCap = value.persistentSquadCap,
            keepEncounterNpcs = value.keepEncounterNpcs },
        populationAdapters = {
            spawnDistance = value.simulationRadius,
            dehydrateDistance = value.simulationRadius + 30,
        },
        directorAdapters = {
            enabled = value.enabled,
            spawnMultiplier = math.max(0.25, math.min(4, value.spawnMultiplier * groupScale)),
            groupMultiplier = value.groupMultiplier,
            maximumLivingActors = value.maximumHostileActors,
            encounterIntervalHours = value.encounterIntervalHours,
            encounterChance = math.min(1, value.encounterChance * (value.rateEncounters or 1)),
        },
        spawnPolicyAdapters = { safehouseMargin = value.safehouseMargin },
        populateAdapters = { mode = value.populateMode, maximum = value.populateMaximum,
            spawnDistance = value.simulationRadius },
        welcomeAdapters = { enabled = value.townWelcomeEnabled, perTown = value.townWelcomePerTown,
            firstDayOnly = value.townWelcomeFirstDayOnly },
        talkAdapters = { enabled = value.talkEnabled, singlePlayerChat = value.talkSinglePlayerChat,
            presence = value.talkPresence, riskAssessment = value.talkRiskAssessment,
            robberyEnabled = value.robberyEnabled, robberyChance = value.robberyChance,
            ordersEnabled = value.ordersEnabled, ordersChance = value.ordersChance,
            ordersZombieTiles = value.ordersZombieTiles, ordersFightPercent = value.ordersFightPercent,
            ordersSurrenderSeconds = value.ordersSurrenderSeconds,
            radio = value.radioKnoxCounty },
        offlineAdapters = {
            enabled = value.enabled,

            squadCap = value.worldMode == 2 and 0
                or math.floor(value.offlineSquadCap * groupScale + 0.5),
            tickSeconds = value.offlineTickSeconds,
            travelTilesPerHour = value.offlineTravelTilesPerHour,
            revengeEnabled = value.offlineRevenge and value.hostileEnabled,
            foundGapHours = value.offlineFoundGapHours,
        },
        raidAdapters = {
            enabled = value.enabled and value.raidEnabled and value.hostileEnabled,
            minDay = value.raidMinDay, cooldownDays = value.raidCooldownDays,
            chancePerCheckPct = value.raidChance, checkEveryMinutes = value.raidCheckMinutes,
            waves = value.raidWaves, groupSize = value.raidGroupSize,
            maxAttackers = value.raidMaxAttackers, warningHours = value.raidWarningHours,
            waveDelayMinutes = value.raidWaveDelayMinutes,
            heli = value.raidHeli, sirenAircraft = value.raidSirenAircraft,
            scoutBuildupHours = value.raidScoutBuildupHours,
            scoutLifetimeHours = value.raidScoutLifetimeHours, scoutSize = value.raidScoutSize,
        },
        supportAdapters = {
            enabled = value.enabled and value.supportEnabled,
            cooldownHours = value.supportCooldownHours, successPercent = value.supportChance,
            defaultSize = value.supportGroupSize, maxCallsCap = value.supportMaxCalls,
            spotlightPercent = value.supportSpotlightChance,
            spotlightDurationS = value.supportSpotlightSeconds, heliDurationS = value.supportHelicopterSeconds,
            spotlightEnabled = value.heliSpotlight, spotlightRadius = value.heliSpotlightSize,
            spotlightBrightness = value.heliSpotlightBrightness, spotlightGapMinutes = value.heliSpotlightGapMinutes,
        },
        metaAdapters = { rateScale = value.rateMetaEvents or 1 },
        safehouseAdapters = Settings.readSafehouse(source),
        professionApplied = Settings.applyProfessionRolls(source),
        residentCorpseAdapters = { enabled = value.enabled and value.residentCorpses },
        outpostAdapters = {
            enabled = value.enabled and value.outpostsEnabled and value.hostileEnabled,
            squadsHardCap = value.outpostTaskSquadCap,
            maxOutsideCity = value.outpostsOutsideCity,
            maxSites = value.outpostsMaxSites,
            perCity = value.outpostsPerCity,
            intervalMinutes = value.outpostsIntervalMinutes,
            chancePercent = value.outpostsChance,
            buildRadius = value.outpostsBuildRadius,
            streamHoldSeconds = value.outpostsStreamHoldSeconds,
            buildBudget = value.outpostsBuildBudget == 250 and 100 or value.outpostsBuildBudget,
            maxCompounds = value.outpostsMaxCompounds,
            compoundSpacing = value.outpostsCompoundSpacing,
            lightsOn = value.outpostsLightsOn,
            spawnRadius = value.outpostsSpawnRadius,
            structureLossPercent = value.outpostsStructureLoss,
        },
        lifecycleAdapters = {
            deathDrops = { enabled = value.weaponDrops },
        },
        decisionAdapters = {
            scavengeRun = {
                buildingRadius = value.scavengeBuildingRadius,
                carryLimit = value.scavengeCarryLimit,
                returnAfterBuildings = value.scavengeReturnAfterBuildings,
            },
            patrolRest = {
                enabled = value.patrolRestEnabled,
                minMinutes = value.patrolRestMinMinutes,
                maxMinutes = value.patrolRestMaxMinutes,
                everyHours = value.patrolRestEveryHours,
            },
            movement = movement,
            combat = combat,
            endurance = copied(behavior.endurance),
            tactics = copied(behavior.combat),
            programs = copied(behavior.programs),
            scavenging = scavenging,
            perception = { relations = { warfare = value.warfare } },
            firstDays = { enabled = value.panicFirstDays, strengthPercent = value.panicStrength,
                lengthDays = value.panicLengthDays, contagion = value.panicContagion },
            survival = { retreat = value.retreat },
            fear = { days = value.fearDays, level = value.fearLevel, lingering = value.fearLingering },
            gunFear = { percent = value.gunFearPercent, runDistance = value.gunFearRunDistance,
                runSpeed = value.gunFearRunSpeed, reactDelayMs = value.gunFearReactDelayMs },

            voice = {
                enabled = true,
                textEnabled = true,
                audioEnabled = value.voiceEnabled,
                ambientEnabled = true,
                ambientMinimumMs = 35000,
                ambientMaximumMs = 70000,
            },
        },
    }
end

function Settings.helicoptersAllowed()
    local current = Settings.current
    return not (type(current) == "table" and current.raidHeli == false)
end

Settings.LIVE_KEYS = { "Offline_SquadCap", "Population_PersistentSquadCap", "Preset_World",
    "Rate_Groups", "World_Mode", "Preset_Difficulty" }

function Settings.engineValue(key)
    local options = getSandboxOptions()
    if options == nil or type(options.getOptionByName) ~= "function" then return nil end
    local option = options:getOptionByName("ALife." .. tostring(key))
    if option == nil or type(option.getValue) ~= "function" then return nil end
    return option:getValue()
end

function Settings.liveValue(key)
    if type(key) ~= "string" then return nil end
    if type(getSandboxOptions) == "function" then
        local ok, value = pcall(Settings.engineValue, key)
        if ok and value ~= nil then return value end
    end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return nil end
    return vars[key]
end

function Settings.capsFor(value)
    local founding = value.worldMode == 2 and 0
        or math.floor(value.offlineSquadCap * (value.rateGroups or 1) + 0.5)
    founding = math.max(0, math.min(500, founding))
    local saved = math.max(0, math.min(500, math.floor(tonumber(value.persistentSquadCap) or 60)))
    local maximum = founding > 0 and founding or saved
    return founding, maximum, saved
end

function Settings.refreshLive()
    local runtime = ProjectALife.Runtime
    if type(runtime) ~= "table" or runtime.started ~= true then return false end
    local live, keys, changed = Settings.live, Settings.LIVE_KEYS, false
    for index = 1, #keys do
        local key = keys[index]
        local value = Settings.liveValue(key)
        if value ~= live.raw[key] then
            live.raw[key] = value
            changed = true
        end
    end
    if not changed then return false end
    local ok, result = pcall(Settings.applyLiveCaps, live.raw)
    if ok then return result end

    live.faults = (tonumber(live.faults) or 0) + 1
    live.lastError = tostring(result)
    pcall(print, "[ALIFE-SETTINGS] live caps failed: " .. live.lastError)
    return false
end

function Settings.applyLiveCaps(raw)
    local founding, maximum, saved = Settings.capsFor(Settings.read(raw or {}, true))
    local offline, ledger = ProjectALife.OfflineDirector, ProjectALife.SquadLedger
    local persistence, live = ProjectALife.Persistence, Settings.live
    local oldFounding, oldMaximum, oldSaved
    if type(offline) == "table" and type(offline.settings) == "table" then
        oldFounding = offline.settings.squadCap
        offline.settings.squadCap = founding
        local adapters = type(offline.adapters) == "table" and offline.adapters or nil
        if adapters ~= nil then adapters.squadCap = founding end

        if founding > 0 and not (adapters ~= nil and adapters.enabled == false) then
            offline.enabled = true
        end
    end
    if type(ledger) == "table" and type(ledger.settings) == "table" then
        oldMaximum = ledger.settings.maximum
        ledger.settings.maximum = maximum
    end
    if type(persistence) == "table" then
        oldSaved = persistence.squadCap
        persistence.squadCap = saved
    end
    live.offlineSquadCap, live.ledgerMaximum, live.persistentSquadCap = founding, maximum, saved
    if oldFounding == founding and oldMaximum == maximum and oldSaved == saved then return false end
    live.applied = (tonumber(live.applied) or 0) + 1
    local line = "offline " .. tostring(oldFounding) .. "->" .. tostring(founding)
        .. " ledger " .. tostring(oldMaximum) .. "->" .. tostring(maximum)
        .. " saved " .. tostring(oldSaved) .. "->" .. tostring(saved)
    pcall(print, "[ALIFE-SETTINGS] live caps " .. line)
    local telemetry = ProjectALife.Telemetry
    if type(telemetry) == "table" and type(telemetry.emit) == "function" then
        pcall(telemetry.emit, "settings_live", { offline = founding, ledger = maximum, saved = saved, reason = line })
    end
    return true
end

return Settings
