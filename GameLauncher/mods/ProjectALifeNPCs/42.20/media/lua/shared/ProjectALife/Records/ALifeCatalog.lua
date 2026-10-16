require "ProjectALife/Records/ALifeCatalogParser"
require "ProjectALife/Records/ALifeRosterBalance"
require "ProjectALife/Records/ALifeCustomFactions"
require "ProjectALife/Records/ALifeCustomProfiles"
require "ProjectALife/Records/ALifeMeleeFaction"

ProjectALife = ProjectALife or {}

local Parser = ProjectALife.CatalogParser
local Catalog = {
    MOD_ID = "ProjectALifeNPCs",
    BUILD_STAMP = "",
    current = nil,
    shipped = nil,
}
ProjectALife.Catalog = Catalog

local function readModText(paths)
    if type(getModFileReader) ~= "function" then return nil, "mod_file_reader_unavailable" end
    local failures = {}
    for _, relative in ipairs(paths) do
        local opened, reader = pcall(getModFileReader, Catalog.MOD_ID, relative, false)
        if opened and reader ~= nil then
            local lines = {}
            local readOk, readError = pcall(function()
                while true do
                    local line = reader:readLine()
                    if line == nil then break end
                    lines[#lines + 1] = tostring(line)
                end
            end)
            pcall(function() reader:close() end)
            if readOk then return table.concat(lines, "\n"), relative end
            failures[#failures + 1] = relative .. ":" .. tostring(readError)
        else
            failures[#failures + 1] = relative .. ":not_found"
        end
    end
    return nil, table.concat(failures, ";")
end

local function build(factionText, npcText)
    local factions, factionError = Parser.parseText(factionText, "faction_registry.alife", "faction")
    if factions == nil then return nil, factionError end
    local npcs, npcError = Parser.parseText(npcText, "npc_profiles.alife", "member")
    if npcs == nil then return nil, npcError end

    for _, faction in ipairs(factions.records) do
        if type(faction.general) ~= "table" or type(faction.general.name) ~= "string"
                or faction.general.name == "" then
            return nil, "faction_name_required:" .. faction.id
        end
    end

    local orphanedProfiles = {}
    local keptNpcRecords = {}
    for _, npc in ipairs(npcs.records) do
        local general = npc.general
        if type(general) ~= "table" or type(general.name) ~= "string" or general.name == "" then
            return nil, "npc_name_required:" .. npc.id
        end
        if type(general.faction) ~= "string" or factions.byId[general.faction] == nil then
            orphanedProfiles[npc.id] = tostring(general.faction)
            npcs.byId[npc.id] = nil
        else
            keptNpcRecords[#keptNpcRecords + 1] = npc
        end
    end
    npcs.records = keptNpcRecords

    local function uniqueOrder(records, byId)
        local order, seen = {}, {}
        for _, record in ipairs(records) do
            if not seen[record.id] then
                seen[record.id] = true
                order[#order + 1] = byId[record.id]
            end
        end
        return order
    end

    return {
        factions = factions.byId,
        factionOrder = uniqueOrder(factions.records, factions.byId),
        npcs = npcs.byId,
        npcOrder = uniqueOrder(npcs.records, npcs.byId),

        orphanedProfiles = orphanedProfiles,
    }
end

function Catalog.normalize(loaded)
    if type(loaded) ~= "table" then return 0 end
    local changed, seen = 0, {}
    local function force(faction)
        if type(faction) ~= "table" or seen[faction] then return end
        seen[faction] = true
        local spawn = faction.spawn
        if type(spawn) ~= "table" or spawn.visitorOnly ~= true then return end
        if spawn.natural ~= false or spawn.odds ~= 0 or spawn.hiddenFromSpawn ~= true then
            spawn.natural, spawn.odds, spawn.hiddenFromSpawn = false, 0, true
            changed = changed + 1
        end
    end
    if type(loaded.factions) == "table" then
        for _, faction in pairs(loaded.factions) do force(faction) end
    end
    if type(loaded.factionOrder) == "table" then
        for _, faction in ipairs(loaded.factionOrder) do force(faction) end
    end
    return changed
end

function Catalog.loadFromText(factionText, npcText)
    local loaded, reason = build(factionText, npcText)
    if loaded == nil then return nil, reason end
    Catalog.normalize(loaded)
    Catalog.current = loaded
    return loaded
end

local function copyRecords(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = copyRecords(item, seen) end
    return result
end

function Catalog.load(useShippedCache)
    local loaded, reason

    if useShippedCache ~= false and Catalog.shipped
            and (Catalog.shippedLegacy == nil or Catalog.shippedLegacy == ProjectALife.RosterBalance.legacy()) then
        loaded = copyRecords(Catalog.shipped)
    else
        local factionText, factionSource = readModText({
            "alife_runtime/catalog/faction_registry.alife",
        })
        if factionText == nil then return nil, "factions_read_failed:" .. tostring(factionSource) end
        local npcText, npcSource = readModText({
            "alife_runtime/catalog/npc_profiles.alife",
        })
        if npcText == nil then return nil, "npcs_read_failed:" .. tostring(npcSource) end
        loaded, reason = build(factionText, npcText)
        if loaded == nil then return nil, reason end

        ProjectALife.RosterBalance.apply(loaded)
        for _, profile in ipairs(loaded.npcOrder) do profile.shippedProgression = true end

        Catalog.shipped = copyRecords(loaded)
        Catalog.shippedLegacy = ProjectALife.RosterBalance.legacy()
    end

    local function overlay(order, byId, records)
        local positions = {}
        for index, record in ipairs(order) do positions[record.id] = index end
        for _, record in ipairs(records or {}) do
            local index = positions[record.id]
            if byId == loaded.factions and type(byId[record.id]) == "table" then
                local wardrobe = byId[record.id]
                if wardrobe ~= nil then
                    record = copyRecords(record)
                    for _, section in ipairs(ProjectALife.CustomFactions.wardrobeSections) do
                        if record[section] == nil then record[section] = copyRecords(wardrobe[section]) end
                    end
                end
            end
            byId[record.id] = record
            if index then
                order[index] = record
            else
                order[#order + 1] = record
                positions[record.id] = #order
            end
        end
    end

    pcall(function()
        overlay(loaded.factionOrder, loaded.factions,
            ProjectALife.CustomFactions.load())
    end)
    pcall(function()
        overlay(loaded.npcOrder, loaded.npcs,
            ProjectALife.CustomProfiles.load())
    end)
    pcall(ProjectALife.MeleeFaction.apply, loaded)
    local visibleFactions, deletedFactions = {}, {}
    for _, faction in ipairs(loaded.factionOrder) do
        if faction.general and faction.general.deleted == true then
            deletedFactions[faction.id] = true
            loaded.factions[faction.id] = nil
        else
            visibleFactions[#visibleFactions + 1] = faction
        end
    end
    loaded.factionOrder = visibleFactions
    local visible, deletedProfiles = {}, {}
    for id, deleted in pairs(ProjectALife.CustomProfiles.deleted or {}) do
        if deleted == true then deletedProfiles[id] = true end
    end
    for _, npc in ipairs(loaded.npcOrder) do
        if not ProjectALife.CustomProfiles.isDeleted(npc.id)
                and not deletedFactions[npc.general and npc.general.faction] then
            visible[#visible + 1] = npc
        else
            loaded.npcs[npc.id] = nil
            deletedProfiles[npc.id] = true
        end
    end
    local reachable = {}
    for _, npc in ipairs(visible) do
        local general = npc.general or {}
        if loaded.factions[general.faction] == nil then
            loaded.npcs[npc.id] = nil
            loaded.orphanedProfiles[npc.id] = tostring(general.faction)
        else
            reachable[#reachable + 1] = npc
        end
    end
    loaded.npcOrder = reachable
    loaded.deletedFactions, loaded.deletedProfiles = deletedFactions, deletedProfiles
    loaded.hasDeletions = false
    for _ in pairs(deletedFactions) do loaded.hasDeletions = true break end
    for _ in pairs(deletedProfiles) do loaded.hasDeletions = true break end
    Catalog.normalize(loaded)
    Catalog.current = loaded
    return loaded
end

function Catalog.deletedReason(factionId, profileId)
    local current = Catalog.current
    if current == nil then return nil end
    if current.deletedFactions and current.deletedFactions[factionId] then return "faction_deleted" end
    if current.deletedProfiles and current.deletedProfiles[profileId] then return "profile_deleted" end
    return nil
end

function Catalog.faction(id)
    if Catalog.network ~= nil and Catalog.network.factions[id] ~= nil then return Catalog.network.factions[id] end
    return Catalog.current and Catalog.current.factions[id] or nil
end

function Catalog.npc(id)
    if Catalog.network ~= nil and Catalog.network.npcs[id] ~= nil then return Catalog.network.npcs[id] end
    return Catalog.current and Catalog.current.npcs[id] or nil
end

function Catalog.randomFraction()
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000000) / 1000000 end
    return 0.5
end

function Catalog.weightedProfile(roster, fraction)
    local total, last = 0, nil
    for _, profile in ipairs(roster or {}) do
        total = total + math.max(0, tonumber(type(profile) == "table" and profile.general and profile.general.spawnWeight) or 1)
    end
    if total <= 0 then return nil end
    local needle = math.max(0, math.min(0.999999999, tonumber(fraction) or Catalog.randomFraction())) * total
    for _, profile in ipairs(roster or {}) do
        local weight = math.max(0, tonumber(type(profile) == "table" and profile.general and profile.general.spawnWeight) or 1)
        if weight > 0 then
            last = profile; needle = needle - weight
            if needle < 0 then return profile end
        end
    end
    return last
end

function Catalog.reset(clearShipped)
    Catalog.current = nil
    if clearShipped == true then Catalog.shipped = nil end
end

return Catalog
