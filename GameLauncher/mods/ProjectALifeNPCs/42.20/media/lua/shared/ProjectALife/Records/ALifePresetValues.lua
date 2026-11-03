require "ProjectALife/Records/ALifeDifficultyPreset"

ProjectALife = ProjectALife or {}

local Preset = {}
local Difficulty = ProjectALife.DifficultyPreset
ProjectALife.PresetValues = Preset

Preset.worldRows = {

    { key = "Population_HostileCeiling", default = 32, legacy = 16, field = "maximumHostileActors",
      tiers = { 6, 9, 12, 32, 96 }, oldTiers = { 8, 12, 16, 32, 96 } },
    { key = "Population_RatePercent", default = 200, legacy = 75, field = "spawnMultiplier",
      divide = 100, tiers = { 75, 110, 150, 200, 300 }, oldTiers = { 40, 60, 75, 125, 200 },
      was = 60, wasTiers = { 30, 45, 60, 125, 200 } },

    { key = "Offline_SquadCap", default = 45, legacy = 18, field = "offlineSquadCap",
      tiers = { 30, 30, 30, 45, 90 }, oldTiers = { 18, 18, 18, 30, 60 },
      was = 12, wasTiers = { 12, 12, 12, 30, 60 } },
    { key = "Population_PersistentSquadCap", default = 60, legacy = 3, field = "persistentSquadCap",
      tiers = { 45, 45, 45, 60, 200 }, oldTiers = { 3, 3, 3, 40, 160 }, was = 20, wasTiers = { 20, 20, 20, 40, 160 } },

    { key = "Population_PartyPercent", default = 125, field = "groupMultiplier",
      divide = 100, tiers = { 75, 90, 100, 125, 160 } },
    { key = "Party_LoneWeight", default = 2, field = "partyLoneWeight",
      tiers = { 5, 4, 3, 2, 2 } },
    { key = "Party_GroupWeight", default = 2, field = "partyGroupWeight",
      tiers = { 1, 1, 1, 2, 4 } },

    { key = "Encounters_RollPercent", default = 40, legacy = 15, field = "encounterChance",
      divide = 100, tiers = { 6, 8, 10, 40, 50 }, oldTiers = { 8, 12, 15, 30, 50 } },
    { key = "Encounters_GapHours", default = 3, field = "encounterIntervalHours",
      tiers = { 16, 12, 8, 3, 2 } },
    { key = "Encounters_IntervalMinutes", default = 45, field = "encounterIntervalMinutes",
      tiers = { 240, 180, 120, 45, 30 } },

    { key = "Outposts_MaxSites", default = 9, field = "outpostsMaxSites", explicitMinimum = 0, explicitMaximum = 24,
      tiers = { 2, 4, 6, 9, 24 } },
    { key = "Outposts_PerCity", default = 2, field = "outpostsPerCity", explicitMinimum = 1, explicitMaximum = 4,
      tiers = { 1, 1, 1, 2, 4 } },
    { key = "Outposts_OutsideCity", default = 4, field = "outpostsOutsideCity", explicitMinimum = 0, explicitMaximum = 12,
      tiers = { 0, 1, 2, 4, 12 } },
    { key = "Outposts_Chance", default = 35, field = "outpostsChance",
      tiers = { 8, 14, 20, 35, 60 } },
    { key = "Outposts_IntervalMinutes", default = 20, field = "outpostsIntervalMinutes",
      tiers = { 60, 45, 30, 20, 10 } },

    { key = "Outposts_TaskSquadCap", default = 3, legacy = 1, field = "outpostTaskSquadCap",
      tiers = { 2, 2, 2, 3, 4 } },

    { key = "Raid_Chance", default = 0.025, field = "raidChance",
      tiers = { 0.0025, 0.005, 0.01, 0.025, 0.1 } },
    { key = "Raid_Waves", default = 4, field = "raidWaves",
      tiers = { 2, 2, 3, 4, 6 } },
    { key = "Raid_GroupSize", default = 8, field = "raidGroupSize",
      tiers = { 4, 5, 6, 8, 12 } },
    { key = "Raid_MaxAttackers", default = 12, field = "raidMaxAttackers",
      tiers = { 6, 8, 8, 12, 16 } },
    { key = "Raid_ScoutSize", default = 4, field = "raidScoutSize", explicitMinimum = 1, explicitMaximum = 8,
      tiers = { 2, 2, 3, 4, 8 } },
    { key = "Support_Chance", default = 35, field = "supportChance",
      tiers = { 8, 14, 20, 35, 60 } },
    { key = "Support_GroupSize", default = 4, field = "supportGroupSize",
      tiers = { 2, 2, 3, 4, 6 } },
    { key = "Support_MaxCalls", default = 2, field = "supportMaxCalls",
      tiers = { 1, 1, 1, 2, 3 } },

    { key = "Population_PopulateMax", default = 75, legacy = 30, field = "populateMaximum",
      tiers = { 45, 45, 45, 75, 180 } },
    { key = "Offline_FoundGapHours", default = 3, field = "offlineFoundGapHours",
      tiers = { 12, 9, 6, 3, 1.5 } },
    { key = "Raid_MinDay", default = 21, field = "raidMinDay",
      tiers = { 60, 45, 30, 21, 14 } },
    { key = "Raid_CooldownDays", default = 14, field = "raidCooldownDays",
      tiers = { 42, 28, 21, 14, 7 } },
    { key = "Support_CooldownHours", default = 1.5, field = "supportCooldownHours",
      tiers = { 6, 4, 3, 1.5, 0.75 } },
    { key = "Support_SpotlightChance", default = 20, field = "supportSpotlightChance",
      tiers = { 4, 8, 12, 20, 40 } },
    { key = "Census_Size", default = 360, field = "censusSize",
      tiers = { 60, 120, 200, 360, 1000 } },
}


function Preset.hostChose(source, key, declared)
    local raw = tonumber(source[key])
    if raw == nil then return false end
    return math.abs(raw - declared) > 1e-6
end

function Preset.rowUntouched(source, row)
    local raw = tonumber(source[row.key])
    if raw == nil then return true end
    return math.abs(raw - row.default) < 1e-6 or math.abs(raw - row.tiers[3]) < 1e-6
end

function Preset.legacyUntouched(source, row, value)
    if row.legacy == nil or value <= row.tiers[3] then return false end
    local raw = tonumber(source[row.key])
    return raw ~= nil and math.abs(raw - row.legacy) < 1e-6
end

function Preset.worldRowValue(source, row, tier)
    local raw = tonumber(source[row.key])
    if raw ~= nil and row.oldTiers ~= nil and row.legacy ~= nil and math.abs(raw - row.legacy) < 1e-6 then
        return row.oldTiers[tier]
    end
    if raw ~= nil and row.wasTiers ~= nil and row.was ~= nil and math.abs(raw - row.was) < 1e-6 then
        return row.wasTiers[tier]
    end
    local value = row.tiers[tier]
    if Preset.rowUntouched(source, row) or Preset.legacyUntouched(source, row, value) then
        return value
    end
    return nil
end

function Preset.resolve(source, world, difficulty)
    source = source or {}
    world = math.floor(tonumber(world) or tonumber(source.Preset_World) or 3)
    difficulty = math.floor(tonumber(difficulty) or Difficulty.tier(source))
    local result = { values = {}, world = {}, difficulty = {} }
    for _, row in ipairs(Preset.worldRows) do
        result.values[row.key] = tonumber(source[row.key]) or row.default
        if source.Preset_ExplicitValues ~= true and world >= 1 and world <= 5 then
            local value = Preset.worldRowValue(source, row, world)
            if value ~= nil then result.world[row.key], result.values[row.key] = value, value end
        end
    end
    for _, row in ipairs(Difficulty.rows) do
        if result.values[row.key] == nil then result.values[row.key] = tonumber(source[row.key]) or row.default end
        if source.Preset_ExplicitValues ~= true and difficulty ~= 2 then
            if Difficulty.untouched(row, tonumber(source[row.key])) then
                result.difficulty[row.key] = Difficulty.option(row.key, row.default, source)
            end
        end
    end
    for key, value in pairs(result.difficulty) do result.values[key] = value end
    return result
end

Preset.aimValues = { 40, 65, 100, 125, 150, 180 }

function Preset.aimDifficultyPercent(choice)
    return Preset.aimValues[math.floor(tonumber(choice) or 3)] or 100
end

function Preset.applyWorld(current, source)
    source = source or {}
    local values = Preset.resolve(source, current.presetWorld, current.presetDifficulty).world
    for _, row in ipairs(Preset.worldRows) do
        local value = values[row.key]
        if source.Preset_ExplicitValues == true then
            local raw = tonumber(source[row.key])
            if raw ~= nil and row.explicitMaximum ~= nil then
                value = math.floor(math.max(row.explicitMinimum, math.min(row.explicitMaximum, raw)))
            end
        end
        if value ~= nil then current[row.field] = value / (row.divide or 1) end
    end
    return current
end

function Preset.applyDifficulty(current, source)
    local values = Preset.resolve(source, current.presetWorld, current.presetDifficulty).difficulty
    for _, row in ipairs(Difficulty.rows) do
        local value = values[row.key]
        if value ~= nil then
            if row.aim == true then value = Preset.aimDifficultyPercent(value) end
            current[row.field] = value
        end
    end
    return current
end

function Preset.reapply(source, key, tier)
    local chosen = {}
    for name, value in pairs(source or {}) do chosen[name] = value end
    local values = Preset.resolve(chosen).values
    chosen[key] = tier
    chosen.Preset_ExplicitValues = false
    local rows = key == "Preset_World" and Preset.worldRows or Difficulty.rows
    for _, row in ipairs(rows) do chosen[row.key] = row.default end
    local applied = Preset.resolve(chosen).values
    for _, row in ipairs(rows) do values[row.key] = applied[row.key] end
    values.Preset_ExplicitValues = true
    return values
end

return Preset

