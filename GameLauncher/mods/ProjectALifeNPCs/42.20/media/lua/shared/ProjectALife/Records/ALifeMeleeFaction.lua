ProjectALife = ProjectALife or {}

local Faction = {
    id = "alife_sawmill_hands",
    options = {
        enabled = "Melee_FactionEnabled",
        footwork = "Melee_Footwork",
        flank = "Melee_Flank",
        breach = "Melee_Breach",
        intimidate = "Melee_Intimidate",
        caution = "Melee_Caution",
    },
    modules = {
        footwork = "meleeFootwork",
        flank = "meleeFlank",
        breach = "meleeBreach",
        intimidate = "meleeIntimidate",
        caution = "meleeCaution",
    },
}
ProjectALife.MeleeFaction = Faction

function Faction.read(key, fallback)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return fallback end
    local value = vars[key]
    if value == nil then return fallback end
    return value
end

function Faction.enabled()
    return Faction.read(Faction.options.enabled, true) ~= false
end

function Faction.moduleOn(name)
    if not Faction.enabled() then return false end
    return Faction.read(Faction.options[name], true) ~= false
end

function Faction.cautionCrowd()
    local value = tonumber(Faction.read("Melee_CautionCrowd", 3)) or 3
    return math.max(2, math.min(8, math.floor(value)))
end

function Faction.apply(catalog)
    if type(catalog) ~= "table" or Faction.enabled() then return false end
    local factions = type(catalog.factions) == "table" and catalog.factions or nil
    local record = factions ~= nil and factions[Faction.id] or nil
    if type(record) ~= "table" then return false end
    record.general = type(record.general) == "table" and record.general or {}
    record.general.deleted = true
    return true
end

return Faction
