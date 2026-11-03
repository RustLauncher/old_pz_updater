require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Records/ALifeFactionSpawnRules"

ProjectALife = ProjectALife or {}

local Visitors = {
    cache = nil,
    warned = {},
    metrics = { lookups = 0, resolved = 0, missing = 0 },
}
ProjectALife.VisitorFactions = Visitors

function Visitors.is(subject)
    local faction = subject
    if type(subject) == "string" then
        local catalog = ProjectALife.Catalog
        faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(subject) or nil
    end
    return ProjectALife.FactionSpawnRules.visitorOnly(faction)
end

function Visitors.list()
    local catalog = ProjectALife.Catalog
    local current = catalog ~= nil and catalog.current or nil
    local ids = {}
    if type(current) ~= "table" or type(current.factionOrder) ~= "table" then return ids end
    for _, faction in ipairs(current.factionOrder) do
        if type(faction) == "table" and type(faction.id) == "string"
                and ProjectALife.FactionSpawnRules.visitorOnly(faction) then
            ids[#ids + 1] = faction.id
        end
    end
    return ids
end

function Visitors.index()
    local catalog = ProjectALife.Catalog
    local current = catalog ~= nil and catalog.current or nil
    if type(current) ~= "table" or type(current.npcOrder) ~= "table" then return nil end
    local cache = Visitors.cache
    if cache ~= nil and cache.source == current and cache.size == #current.npcOrder then return cache end
    cache = { source = current, size = #current.npcOrder, byFaction = {} }
    for _, profile in ipairs(current.npcOrder) do
        local general = type(profile) == "table" and profile.general or nil
        local factionId = type(general) == "table" and general.faction or nil
        if type(factionId) == "string" then
            local list = cache.byFaction[factionId]
            if list == nil then
                list = {}
                cache.byFaction[factionId] = list
            end
            list[#list + 1] = profile
        end
    end
    Visitors.cache = cache
    return cache
end

function Visitors.members(factionId)
    local cache = Visitors.index()
    if cache == nil then return {} end
    return cache.byFaction[factionId] or {}
end

function Visitors.note(key)
    if Visitors.warned[key] then return end
    Visitors.warned[key] = true
    print("[ALIFE-QA] VisitorFactions carrier unavailable: " .. tostring(key))
end

function Visitors.matches(profile, sex, band)
    local general = profile.general or {}
    local female = general.female == true
    if sex == "f" and not female then return false end
    if sex == "m" and female then return false end
    if band ~= nil and band ~= "" then
        local tags = "," .. string.gsub(tostring(general.tags or ""), "%s+", "") .. ","
        if string.find(tags, "," .. band .. ",", 1, true) == nil then return false end
    end
    return true
end

function Visitors.bandOf(card)
    local band = type(card.band) == "string" and card.band or nil
    if band == "teen" or band == nil then band = "adult" end
    return band
end

function Visitors.pick(list, card, seed)
    local sex = card.sex
    local chosen = {}
    local band = Visitors.bandOf(card)
    for _, profile in ipairs(list) do
        if Visitors.matches(profile, sex, band) then chosen[#chosen + 1] = profile end
    end
    if #chosen == 0 then
        for _, profile in ipairs(list) do
            if Visitors.matches(profile, sex, nil) then chosen[#chosen + 1] = profile end
        end
    end
    if #chosen == 0 then return nil, "no_carrier_for_sex" end
    local value = math.abs(tonumber(seed) or 0) % 2147483647
    if value ~= value then value = 0 end
    local index = (value * 48271 + 11) % 2147483647 % #chosen + 1
    return chosen[index].id
end

function Visitors.carrierFor(card)
    Visitors.metrics.lookups = Visitors.metrics.lookups + 1
    if type(card) ~= "table" then return nil, "card_required" end
    local catalog = ProjectALife.Catalog
    local exact, pool = card.carrier, card.carrierPool
    if exact == nil and pool == nil and type(card.arch) == "string" then
        local people = ProjectALife.VisitorPeople
        local index = people ~= nil and type(people.index) == "function" and people.index() or nil
        local entry = type(index) == "table" and type(index.archetypes) == "table" and index.archetypes[card.arch] or nil
        if type(entry) == "table" then exact, pool = entry.carrier, entry.carrierPool end
    end
    local why = nil
    if type(exact) == "string" and exact ~= "" then
        local profile = catalog ~= nil and type(catalog.npc) == "function" and catalog.npc(exact) or nil
        if profile ~= nil then
            Visitors.metrics.resolved = Visitors.metrics.resolved + 1
            return exact, "exact"
        end
        Visitors.note("profile:" .. exact)
        why = "carrier_missing"
    end
    if type(pool) == "string" and pool ~= "" then
        local list = Visitors.members(pool)
        if #list == 0 then
            Visitors.note("faction:" .. pool)
            Visitors.metrics.missing = Visitors.metrics.missing + 1
            return nil, "pool_empty"
        end
        local id, reason = Visitors.pick(list, card, card.seed)
        if id == nil then
            Visitors.metrics.missing = Visitors.metrics.missing + 1
            return nil, reason
        end
        Visitors.metrics.resolved = Visitors.metrics.resolved + 1
        return id, "pool"
    end
    Visitors.metrics.missing = Visitors.metrics.missing + 1
    return nil, why or "no_carrier"
end

function Visitors.qaLine()
    local m = Visitors.metrics
    return "[ALIFE-QA] VisitorFactions lookups=" .. tostring(m.lookups) .. " resolved=" .. tostring(m.resolved)
        .. " missing=" .. tostring(m.missing) .. " factions=" .. tostring(#Visitors.list())
end

return Visitors
