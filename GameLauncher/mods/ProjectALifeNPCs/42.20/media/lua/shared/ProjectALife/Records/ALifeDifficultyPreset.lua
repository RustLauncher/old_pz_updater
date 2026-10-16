ProjectALife = ProjectALife or {}

local Preset = { rows = {
    { key = "Raid_Chance", default = 0.025, field = "raidChance", tiers = { 0.0025, 0.01, 0.025, 0.1 } },
    { key = "Raid_MinDay", default = 21, field = "raidMinDay", tiers = { 60, 30, 21, 14 } },
    { key = "Raid_CooldownDays", default = 14, field = "raidCooldownDays", tiers = { 42, 21, 14, 7 } },
    { key = "Raid_Waves", default = 4, field = "raidWaves", tiers = { 2, 3, 4, 6 } },
    { key = "Raid_GroupSize", default = 8, field = "raidGroupSize", tiers = { 4, 6, 8, 12 } },
    { key = "Raid_MaxAttackers", default = 12, field = "raidMaxAttackers", tiers = { 6, 8, 12, 16 } },
    { key = "Support_Chance", default = 35, field = "supportChance", tiers = { 8, 20, 35, 60 } },
    { key = "Support_CooldownHours", default = 1.5, field = "supportCooldownHours", tiers = { 6, 3, 1.5, 0.75 } },
    { key = "Combat_DamagePercent", default = 72, field = "npcDamagePercent", tiers = { 50, 72, 85, 100 } },
    { key = "NpcHealth_Percent", default = 98, field = "npcHealthPercent", tiers = { 80, 98, 120, 150 } },
    { key = "Combat_AimDifficulty", default = 3, field = "aimPlayerPercent", aim = true, tiers = { 2, 3, 4, 5 } },
    { key = "Warning_ChancePercent", default = 15, field = "warningChancePercent", tiers = { 40, 15, 10, 5 } },
    { key = "Party_LoneWeight", default = 2, field = "partyLoneWeight", tiers = { 4, 3, 2, 2 } },
    { key = "Party_GroupWeight", default = 2, field = "partyGroupWeight", tiers = { 1, 1, 2, 4 } },
}, byKey = {} }
ProjectALife.DifficultyPreset = Preset

for _, row in ipairs(Preset.rows) do Preset.byKey[row.key] = row end

function Preset.source(source)
    if type(source) == "table" then return source end
    return type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" and SandboxVars.ALife or {}
end

function Preset.tier(source)
    source = Preset.source(source)
    local value = tonumber(source.Preset_Difficulty)
    if value == nil or value ~= value then return 2 end
    return math.max(1, math.min(4, math.floor(value)))
end

function Preset.untouched(row, raw)
    if raw == nil then return true end
    if math.abs(raw - row.default) < 1e-6 then return true end
    return row.tiers[2] ~= nil and math.abs(raw - row.tiers[2]) < 1e-6
end

function Preset.option(key, value, source)
    source = Preset.source(source)
    if source.Preset_ExplicitValues == true then return value end
    local row, tier = Preset.byKey[key], Preset.tier(source)
    if row == nil or tier == 2 then return value end
    if not Preset.untouched(row, tonumber(source[key])) then return value end
    return row.tiers[tier]
end

function Preset.hostileLimit(source)
    source = Preset.source(source)
    local tier, raw = Preset.tier(source), tonumber(source.Population_HostileCeiling)
    if tier == 2 or (raw ~= nil and math.abs(raw - 12) > 1e-6 and math.abs(raw - 32) > 1e-6) then return nil end
    if tier == 1 then return 6 end
    if tier == 3 then return 18 end
    return 30
end

return Preset
