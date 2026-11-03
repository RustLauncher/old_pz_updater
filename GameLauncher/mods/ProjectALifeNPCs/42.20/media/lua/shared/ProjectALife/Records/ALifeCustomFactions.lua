ProjectALife = ProjectALife or {}

require "ProjectALife/Records/ALifePartyPolicy"
require "ProjectALife/Records/ALifeRecordCodec"
require "ProjectALife/Records/ALifeRecordMigration"

local Custom = {
    fileName = "alife_custom_factions.ini",
    factions = {},

    revision = 0,
    serverManaged = false,
    loadFailed = false,
}
ProjectALife.CustomFactions = Custom

Custom.wardrobeSections = { "outfitA", "outfitB", "outfitC", "outfitD", "tintA", "tintB", "tintC", "tintD", "outfitSeason", "outfitNames" }

local GENERAL_ORDER = { "name", "category", "description", "memberTags" }
local SPAWN_ORDER = {

    "enabled", "natural", "peaceable", "encounterPool", "program", "programPool", "firstDay", "lastDay",
    "hourStart", "hourEnd", "odds", "fewest", "most",
    "partyMode", "loneMin", "loneMax", "partyGroupMin", "partyGroupMax",
    "loneWeight", "groupWeight",
    "spawnRangeMin", "spawnRangeMax",
    "locationMode", "towns", "townPool", "allTowns", "specificPlacePool", "includeWilderness",

    "seats",
    "backupMode",
    "visitorOnly",
}
local MODULE_ORDER = { "encounter", "raid", "relations", "director" }
local SUPPORT_ORDER = { "policy", "type", "size", "maxCalls", "heli", "answerers", "vehicle" }

local DEFAULT_GENERAL = {
    name = "New Faction",
    category = "Hostile NPCs",
    description = "Player-created Project A-Life faction.",
}
local DEFAULT_SPAWN = {
    enabled = true,
    peaceable = false,
    encounterPool = "roamer",
    program = "patrol",
    programPool = "patrol",
    hourStart = 0,
    hourEnd = 24,
    partyMode = "both",
    spawnRangeMin = 25,
    spawnRangeMax = 45,
    locationMode = "anywhere",
    towns = "",
    townPool = "",
    allTowns = false,
    specificPlacePool = "",
    includeWilderness = false,
    seats = "",
    backupMode = "none",
}
local DEFAULT_SUPPORT = {
    policy = "disabled", type = "ground", size = 4,
    maxCalls = 1, heli = "none", answerers = "same", vehicle = "",
}

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

function Custom.blankSpawn()
    local spawn = copy(DEFAULT_SPAWN)
    local policy = ProjectALife.PartyPolicy
    if policy ~= nil then
        local sizes = policy.config(nil)
        spawn.odds = policy.bounds.newFactionWeight
        spawn.loneMin, spawn.loneMax = sizes.loneMin, sizes.loneMax
        spawn.partyGroupMin, spawn.partyGroupMax = sizes.groupMin, sizes.groupMax
    end
    return spawn
end

function Custom.forceVisitorSpawn(spawn)
    if type(spawn) ~= "table" then return false end
    spawn.visitorOnly = true
    spawn.enabled, spawn.natural, spawn.odds, spawn.hiddenFromSpawn = false, false, 0, nil
    return true
end

function Custom.releaseVisitorSpawn(spawn, keepDisabled)
    if type(spawn) ~= "table" then return false end
    local blank = Custom.blankSpawn()
    spawn.visitorOnly = nil
    spawn.enabled, spawn.natural, spawn.odds, spawn.hiddenFromSpawn = blank.enabled, nil, blank.odds, nil
    if keepDisabled == true then spawn.enabled = false end
    return true
end

function Custom.blank(id)
    return {
        id = id or ("custom_faction_" .. tostring(os.time and os.time() or 0)),
        general = copy(DEFAULT_GENERAL),
        spawn = Custom.blankSpawn(),
        support = copy(DEFAULT_SUPPORT),
        modules = { encounter = "", raid = "", relations = "", director = "" },
        relations = { player = "hostile", unknown = "hostile" },

        memberModules = { flee = "off" },
    }
end

local function scalar(value)
    if value == "true" then return true end
    if value == "false" then return false end
    local number = tonumber(value)
    if number ~= nil then return number end
    return value
end

local function text(value)
    if type(value) == "boolean" then return value and "true" or "false" end
    return tostring(value or "")
end

local function listText(value, maximum)
    if type(value) ~= "table" then return text(value) end
    local items = {}
    for index = 1, math.min(tonumber(maximum) or #value, #value) do
        local item = tostring(value[index] or "")
        if item ~= "" then items[#items + 1] = item end
    end
    return table.concat(items, "|")
end

local SPAWN_POOLS = {
    encounterPool = true, programPool = true, towns = true, townPool = true,
    specificPlacePool = true,
}

local function serialize(faction)
    local Codec = ProjectALife.RecordCodec
    local block = Codec.begin("faction", faction.id)
    if faction.general.deleted == true then

        Codec.put(block, "general", "deleted", true)
    end
    for _, key in ipairs(GENERAL_ORDER) do
        Codec.put(block, "general", key, text(faction.general[key] or DEFAULT_GENERAL[key]))
    end
    for _, key in ipairs(SPAWN_ORDER) do
        local value = faction.spawn[key]
        if value == nil then value = DEFAULT_SPAWN[key] end

        if value ~= nil then
            Codec.put(block, "spawn", key, SPAWN_POOLS[key] and listText(value) or text(value))
        end
    end
    for _, key in ipairs(SUPPORT_ORDER) do
        local value = faction.support and faction.support[key]
        if value == nil then value = DEFAULT_SUPPORT[key] end
        Codec.put(block, "support", key, key == "answerers" and listText(value, 3) or text(value))
    end
    for _, key in ipairs(MODULE_ORDER) do
        Codec.put(block, "modules", key, text(faction.modules and faction.modules[key] or ""))
    end
    for _, section in ipairs({ "relations", "memberModules" }) do
        local keys = {}
        for key in pairs(faction[section] or {}) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            Codec.put(block, section, key, text(faction[section][key]))
        end
    end
    for _, section in ipairs(Custom.wardrobeSections) do
        local values = faction[section]
        if type(values) == "table" then
            local keys = {}
            for key in pairs(values) do keys[#keys + 1] = key end
            table.sort(keys)
            if #keys == 0 then Codec.put(block, section, "_empty", true) end
            for _, key in ipairs(keys) do Codec.put(block, section, key, text(values[key])) end
        end
    end
    return Codec.finish(block)
end

Custom.serializeFaction = serialize

function Custom.serializeFactions(factions)
    local records = {}
    for _, faction in ipairs(factions or {}) do records[#records + 1] = serialize(faction) end
    return table.concat(records, "\n\n")
end

function Custom.serializeAll()
    return Custom.serializeFactions(Custom.factions)
end

function Custom.applySync(text, revision, persistCache)
    local factions = Custom.parse(text)
    Custom.factions = factions
    Custom.revision = math.max(0, math.floor(tonumber(revision) or 0))
    Custom.serverManaged = true
    if persistCache == true and not Custom.persist() then
        print("[A-Life] Faction cache could not be saved; server data is active")
        return true, "faction_cache_write_failed"
    end
    return true
end

Custom.poolUpgrades = {
    wanderer = "roamer",
    scavenge = "scavenger_crew", defend = "poi_defenders|rooftop_snipers",
    roadblock = "blockade|highway_ambush|broken_car|car_crash",
    assault = "raid|assassination", full_raid = "fullscale_raid",
    fortified_base = "outpost", patrol_line = "patrol|town_patrol",
}

Custom.rideUpgrades = { van = "workvan", seats = "workvan" }

Custom.rideUpgrades = { van = "workvan", seats = "workvan" }
function Custom.upgradePool(pool)
    if type(pool) ~= "string" then return pool, false end
    local result, seen, changed = {}, {}, false
    for entry in string.gmatch(pool .. "|", "(.-)|") do
        entry = string.match(entry, "^%s*(.-)%s*$")
        local id, opens = string.match(entry, "^(.-)(@%d+)$")
        if id == nil then id, opens = entry, "" end
        local mapped = Custom.poolUpgrades[id]
        if mapped ~= nil then changed = true else mapped = id end
        for canonical in string.gmatch(mapped .. "|", "(.-)|") do
            if canonical ~= "" and not seen[canonical .. opens] then
                seen[canonical .. opens] = true
                result[#result + 1] = canonical .. opens
            end
        end
    end
    if not changed then return pool, false end
    return table.concat(result, "|"), true
end

Custom.typedSections = { general = true, spawn = true, support = true }
Custom.textSections = { modules = true, relations = true, memberModules = true }
for _, section in ipairs(Custom.wardrobeSections) do Custom.textSections[section] = true end

function Custom.fromRecords(records)
    local factions = {}
    for _, record in ipairs(records or {}) do
        local faction = Custom.blank(record.id)
        for section, values in pairs(record) do
            local typed = Custom.typedSections[section]
            if type(values) == "table" and (typed or Custom.textSections[section]) then
                faction[section] = faction[section] or {}
                for key, value in pairs(values) do
                    if typed then faction[section][key] = scalar(value)
                    elseif key ~= "_empty" then faction[section][key] = value end
                end
            end
        end
        factions[#factions + 1] = faction
    end
    local upgraded = false
    for _, faction in ipairs(factions) do
        local pool, changed = Custom.upgradePool(faction.spawn.encounterPool)
        if changed then
            faction.spawn.encounterPool = pool
            upgraded = true
        end
        local ride = Custom.rideUpgrades[tostring(faction.support.vehicle or "")]
        if ride ~= nil then
            faction.support.vehicle = ride
            upgraded = true
        end
        local ride = Custom.rideUpgrades[string.lower(tostring(faction.support.vehicle or ""))]
        if ride ~= nil then
            faction.support.vehicle = ride
            upgraded = true
        end
    end
    return factions, upgraded
end

function Custom.parse(source)
    local parsed = ProjectALife.RecordCodec.decode(tostring(source or ""),
        { source = Custom.fileName, kind = "faction", text = true, lenient = true })
    return Custom.fromRecords(parsed and parsed.records)
end

function Custom.load()
    if Custom.serverManaged then return Custom.factions end
    if type(getFileReader) ~= "function" then return Custom.factions end
    local ok, loaded = pcall(function()
        local body, origin, raw = ProjectALife.RecordMigration.readSaved(Custom.fileName, "faction")

        if origin == "retired" then
            if not ProjectALife.RecordMigration.setAside(Custom.fileName, raw) then return false end
            body = ""
        end

        if body == nil then return ProjectALife.RecordSalvage.restoreLocal(Custom, "faction") end
        local factions, upgraded = Custom.parse(body)
        Custom.factions = factions
        Custom.loadFailed = false
        if origin == "backup" then print("[A-Life] Recovered factions from backup") end

        if upgraded and body == raw then Custom.persist() end
        return true
    end)
    Custom.loadFailed = not (ok and loaded)
    if Custom.loadFailed then print("[A-Life] Faction file unreadable; saving blocked to preserve it") end
    return Custom.factions
end

function Custom.persist()
    if Custom.loadFailed and not Custom.serverManaged then return false end
    local name = Custom.serverManaged and "alife_server_factions.ini" or Custom.fileName
    local ok, written = pcall(function()
        return ProjectALife.RecordMigration.persistSaved(name, Custom.serializeAll(), "faction")
    end)
    return ok and written == true
end

function Custom.get(id)
    for _, faction in ipairs(Custom.factions) do
        if faction.id == id then
            if faction.general.deleted == true then return nil end
            return faction
        end
    end
    return nil
end

local function upsertLocal(faction)
    for index, existing in ipairs(Custom.factions) do
        if existing.id == faction.id then
            Custom.factions[index] = faction
            return true
        end
    end
    Custom.factions[#Custom.factions + 1] = faction
    return true
end

local function multiplayerClient()
    local ok, value = pcall(function()
        return type(isClient) == "function" and isClient()
    end)
    return ok and value == true
end

function Custom.save(faction)
    if type(faction) ~= "table" or type(faction.id) ~= "string" then return false end
    if multiplayerClient() then
        local client = ProjectALife.CustomFactionClient
        if client == nil or type(client.upsert) ~= "function"
                or not client.upsert(faction) then return false end
        return upsertLocal(faction)
    end
    return Custom.saveMany({ faction })
end

function Custom.saveMany(factions)
    if type(factions) ~= "table" then return false end
    for _, faction in ipairs(factions) do
        if type(faction) ~= "table" or type(faction.id) ~= "string" then return false end
    end
    local remote = multiplayerClient()
    local previous = Custom.factions
    Custom.factions = copy(previous)
    for index, faction in ipairs(factions) do
        if remote then
            local client = ProjectALife.CustomFactionClient
            if client == nil or type(client.upsert) ~= "function"
                    or not client.upsert(faction) then
                Custom.factions = previous
                if client and type(client.hello) == "function" then
                    client.awaitingEdit = true
                    client.hello(-1)
                end
                return false, index - 1
            end
        end
        upsertLocal(faction)
    end
    if remote or Custom.persist() then return true end
    Custom.factions = previous
    return false, 0
end

function Custom.deletionRecord(id)
    local record = Custom.blank(id)
    record.general.deleted = true
    record.spawn.enabled, record.spawn.natural = false, false
    return record
end

function Custom.delete(id)
    if type(id) ~= "string" or string.match(id, "^[%w_%-]+$") == nil then return false end
    local previous, updated = Custom.factions, {}
    for _, faction in ipairs(previous) do
        if faction.id ~= id then updated[#updated + 1] = faction end
    end
    updated[#updated + 1] = Custom.deletionRecord(id)
    if multiplayerClient() then
        local client = ProjectALife.CustomFactionClient
        if client == nil or type(client.delete) ~= "function"
                or not client.delete(id) then return false end
        Custom.factions = updated
        return true
    end
    Custom.factions = updated
    if Custom.persist() then return true end
    Custom.factions = previous
    return false
end

function Custom.withoutShipped(factions, shipped)
    local kept = {}
    for _, faction in ipairs(factions or {}) do
        if type(faction) == "table" and type(faction.id) == "string"
                and shipped[faction.id] == nil then
            kept[#kept + 1] = faction
        end
    end
    return kept
end

function Custom.resetToShipped(shipped)
    if type(shipped) ~= "table" then return false end
    local previous = Custom.factions
    local kept = Custom.withoutShipped(previous, shipped)
    if multiplayerClient() then
        local client = ProjectALife.CustomFactionClient
        if client == nil or type(client.reset) ~= "function" or not client.reset() then return false end
        Custom.factions = kept
        return true
    end
    Custom.factions = kept
    if Custom.persist() then return true end
    Custom.factions = previous
    return false
end

function Custom.catalogText()
    if not Custom.serverManaged then Custom.load() end
    return Custom.serializeAll()
end

return Custom
