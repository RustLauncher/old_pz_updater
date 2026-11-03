ProjectALife = ProjectALife or {}

local Assignment = {

    pools = {},
    fallback = { male = {}, female = {} },
}

local OUTLAWS = { "pal_outlaw_1", "pal_outlaw_2", "pal_outlaw_3" }
local ANARCHISTS = { "pal_freedom_1", "pal_freedom_2", "pal_freedom_3" }
local MERCENARIES = { "pal_mercenary_1", "pal_mercenary_2", "pal_mercenary_3", "pal_mercenary_4",
    "pal_mercenary_5", "pal_mercenary_6", "pal_mercenary_7", "pal_mercenary_8" }
local EXPERIENCED = { "pal_csky_1", "pal_csky_2", "pal_csky_3" }
local PARAMILITARY = { "pal_dolg_1", "pal_dolg_2", "pal_dolg_3" }
local SCIENTISTS = { "pal_ecolog_1", "pal_ecolog_2", "pal_ecolog_3" }
local SOLDIERS = { "pal_military_1", "pal_military_2", "pal_military_3" }
local FOREIGN = { "pal_stalker_1", "pal_stalker_2", "pal_stalker_3" }
local LAW = { "pal_law_enforcement_team_lead", "pal_law_enforcement_operator_1", "pal_law_enforcement_operator_2",
    "pal_law_enforcement_operator_3", "pal_law_enforcement_operator_4" }
local AMERICANS = { "pal_american_survivor_1", "pal_american_survivor_2", "pal_american_survivor_3" }
local RUSSIANS = { "pal_russian_survivor_1", "pal_russian_survivor_2", "pal_russian_survivor_3" }
local WOMEN = { "pal_american_female_survivor", "pal_foreign_female_survivor" }

local function join(...)
    local result = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do result[#result + 1] = id end
    end
    return result
end

Assignment.pools = {
    alife_drifters = { male = join(OUTLAWS, ANARCHISTS), female = WOMEN },
    alife_blacktop = { male = join(OUTLAWS, { "pal_mercenary_1", "pal_mercenary_2", "pal_mercenary_3", "pal_mercenary_4" }), female = WOMEN },
    alife_ashguard = { male = MERCENARIES, female = WOMEN },

    alife_stillwater = { male = join(EXPERIENCED, FOREIGN), female = WOMEN },
    alife_kettle = { male = join(RUSSIANS, ANARCHISTS), female = WOMEN },
    alife_guard = { male = join(SOLDIERS, PARAMILITARY), female = WOMEN },
    alife_cordon = { male = SOLDIERS, female = WOMEN },
    alife_police = { male = LAW, female = WOMEN },
    alife_fire = { male = join(AMERICANS, EXPERIENCED), female = WOMEN },
    alife_riverside = { male = join(AMERICANS, EXPERIENCED, SCIENTISTS), female = WOMEN },

}
Assignment.fallback = {
    male = join(OUTLAWS, ANARCHISTS, MERCENARIES, EXPERIENCED, PARAMILITARY, SCIENTISTS, SOLDIERS, FOREIGN, LAW, AMERICANS, RUSSIANS),
    female = WOMEN,
}

function Assignment.stableIndex(seed, maximum)
    if type(maximum) ~= "number" or maximum < 1 then return 1 end
    local value = 7
    seed = tostring(seed or "")
    for index = 1, #seed do value = (value * 131 + string.byte(seed, index)) % 2147483647 end
    return (value % maximum) + 1
end

function Assignment.pool(factionId, female)
    local key = female == true and "female" or "male"
    local pool = Assignment.pools[tostring(factionId or "")]
    if type(pool) == "table" and type(pool[key]) == "table" and #pool[key] > 0 then return pool[key] end
    return Assignment.fallback[key] or {}
end

function Assignment.shipped(id, catalog)
    catalog = catalog or ProjectALife.VoiceCatalog
    if type(catalog) ~= "table" or type(catalog.profiles) ~= "table" then return false end
    local profile = catalog.profiles[id]
    return profile ~= nil and profile.shipEnabled ~= false
end

function Assignment.assign(requested, factionId, female, seed, catalog)
    local id = type(requested) == "string" and string.lower(requested) or ""
    if id ~= "" and id ~= "*" and id ~= "random" and Assignment.shipped(id, catalog) then return id, "requested" end
    local pool = Assignment.pool(factionId, female)
    if #pool == 0 then return id, "no_pool" end
    local index = Assignment.stableIndex(tostring(seed or "") .. "|" .. tostring(factionId or ""), #pool)
    return pool[index], "faction"
end

ProjectALife.VoiceAssignment = Assignment
return Assignment
