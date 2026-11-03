require "ProjectALife/Records/ALifeCustomFactions"
require "ProjectALife/Records/ALifeRecordMigration"
require "ProjectALife/Records/ALifeCreatorTransfer"

ProjectALife = ProjectALife or {}

local Authority = {
    TAG = "ProjectALife.CustomFactions.v1",
    SCHEMA = 1,
    MAX_CHUNK_BYTES = 8000,

    STORE_CHUNK_CHARS = 8000,

    BACKUP_FILE = "alife_server_factions.ini",
    STORE_LABEL = "The world's Creator faction store",
    MAX_TEXT_BYTES = 2000000,
    adapters = {},
    storage = nil,

    deferredMigration = nil,
    helloCooldownMs = 10000,
    helloAt = setmetatable({}, { __mode = "k" }),
}
ProjectALife.CustomFactionAuthority = Authority

local Custom = ProjectALife.CustomFactions

function Authority.textOf(record)
    if type(record) ~= "table" then return "" end
    if type(record.textChunks) == "table" then
        local parts = {}
        for index = 1, #record.textChunks do parts[index] = tostring(record.textChunks[index] or "") end
        return table.concat(parts)
    end
    return type(record.text) == "string" and record.text or ""
end

function Authority.writeText(record, text)
    text = type(text) == "string" and text or ""
    record.textChunks = ProjectALife.CreatorTransfer.split(text)
    record.text = nil
end

function Authority.setAsideRetired(record)
    local Migration = ProjectALife.RecordMigration
    local text = Authority.textOf(record)
    if Migration.isCurrent(text) then return false end
    if not Migration.setAside(Authority.BACKUP_FILE, text, Authority.STORE_LABEL) then
        print("[A-Life] Creator faction edits wait until a backup slot in Zomboid/Lua can be written ("
            .. tostring(Migration.backupName(Authority.BACKUP_FILE)) .. " or .old.N.ini)")
    end
    return true
end

function Authority.repair(record, reason)
    local text = Authority.textOf(record)
    if reason == nil and Authority.validate(text) ~= nil then return false end
    local Salvage, Migration = ProjectALife.RecordSalvage, ProjectALife.RecordMigration
    if Salvage == nil or #text > Authority.MAX_TEXT_BYTES then return false, reason end
    local repaired, rejects = Salvage.repairText(text, "faction", Custom.serializeFactions, Authority.validate)
    if repaired == nil then return false, reason or "faction_text_invalid" end
    local kept, keepReason, backup = Migration.keepOld(Authority.BACKUP_FILE, text, Migration.badName)
    Salvage.report("faction", rejects, kept and backup or nil)
    if not kept then return false, keepReason, repaired, Migration.badName end
    Authority.writeText(record, repaired)
    record.revision = math.max(0, math.floor(tonumber(record.revision) or 0)) + 1
    return true
end

function Authority.repairLoaded(state, reason)
    local repaired, why, text, namer = Authority.repair(state, reason)
    if repaired then return state end
    if text == nil then return nil, why or reason end
    Authority.deferredMigration = { record = state, text = Authority.textOf(state), namer = namer }
    local detached = { schema = state.schema, revision = state.revision }
    Authority.writeText(detached, text)
    Authority.storage = detached
    return detached
end

function Authority.salvageSeed(text, reason)
    local Salvage = ProjectALife.RecordSalvage
    local repaired, rejects
    if Salvage ~= nil then
        repaired, rejects = Salvage.repairText(text, "faction", Custom.serializeFactions, Authority.validate)
    end
    if repaired == nil or repaired == "" then
        print("[A-Life] creator factions: local factions not seeded (" .. tostring(reason) .. ")")
        return nil
    end
    Salvage.report("faction", rejects, nil)
    return repaired
end

local function store()
    if Authority.storage ~= nil then return Authority.storage end
    local value
    if type(Authority.adapters.getOrCreate) == "function" then
        value = Authority.adapters.getOrCreate(Authority.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        value = ModData.getOrCreate(Authority.TAG)
    end
    if type(value) ~= "table" then return nil, "mod_data_unavailable" end
    if value.schema ~= nil and value.schema ~= Authority.SCHEMA then
        return nil, "custom_factions_schema_unsupported:" .. tostring(value.schema)
    end
    if Authority.setAsideRetired(value) then
        Authority.deferredMigration = { record = value, text = Authority.textOf(value) }
        local detached = { schema = value.schema, revision = value.revision }
        Authority.writeText(detached, "")
        value = detached
    end
    if value.schema == nil then value.schema, value.revision = Authority.SCHEMA, 0 end
    value.revision = math.max(0, math.floor(tonumber(value.revision) or 0))

    if type(value.text) == "string" or type(value.textChunks) ~= "table" then
        Authority.writeText(value, Authority.textOf(value))
    end
    Authority.storage = value
    return value
end

function Authority.settleMigration(state)
    local deferred = Authority.deferredMigration
    if deferred == nil then return state end
    local Migration = ProjectALife.RecordMigration
    local kept, reason, backup
    if deferred.namer ~= nil then
        kept, reason, backup = Migration.keepOld(Authority.BACKUP_FILE, deferred.text, deferred.namer)
    else
        kept, reason, backup = Migration.setAside(Authority.BACKUP_FILE, deferred.text, Authority.STORE_LABEL)
    end
    if not kept then return nil, "migration_backup_pending:" .. tostring(reason) end
    local record = deferred.record
    record.schema, record.revision = state.schema, state.revision
    Authority.writeText(record, Authority.textOf(state))
    Authority.deferredMigration, Authority.storage = nil, record
    print("[A-Life] Creator faction store replaced; the old one is kept in " .. tostring(backup))
    return record
end

local function send(player, payload)
    if player == nil then return false end
    if type(Authority.adapters.send) == "function" then
        local ok, result = pcall(Authority.adapters.send,
            player, "ProjectALife", "creatorFactionSync", payload)
        return ok and result ~= false
    end
    if type(sendServerCommand) ~= "function" then return false end
    local ok, result = pcall(sendServerCommand, player, "ProjectALife", "creatorFactionSync", payload)
    return ok and result ~= false
end

local function players()
    if type(Authority.adapters.players) == "function" then
        return Authority.adapters.players() or {}
    end
    if type(getOnlinePlayers) ~= "function" then return {} end
    local ok, online = pcall(getOnlinePlayers)
    if not ok or online == nil then return {} end
    local result = {}
    if type(online) == "table" and type(online.size) ~= "function" then
        for _, player in ipairs(online) do result[#result + 1] = player end
    else
        local count = 0
        pcall(function() count = online:size() end)
        for index = 0, count - 1 do
            local player
            pcall(function() player = online:get(index) end)
            if player ~= nil then result[#result + 1] = player end
        end
    end
    return result
end

function Authority.configure(adapters)
    Authority.adapters = adapters or {}
    Authority.storage = nil
    Authority.deferredMigration = nil
    Authority.helloAt = setmetatable({}, { __mode = "k" })
end

function Authority.chunks(text)
    text = type(text) == "string" and text or ""
    if text == "" then return { "" } end
    return ProjectALife.CreatorTransfer.split(text)
end

function Authority.syncTo(player, supplied)
    local state, reason = supplied, nil
    if state == nil then state, reason = store() end
    if state == nil then return false, reason end
    local chunks = Authority.chunks(Authority.textOf(state))
    local sent = true
    for index, text in ipairs(chunks) do
        sent = send(player, {
            schema = Authority.SCHEMA,
            revision = state.revision,
            index = index,
            total = #chunks,
            text = text,
        }) and sent
    end

    if sent then return true, nil end
    return false, "faction_sync_send_failed"
end

function Authority.broadcast(supplied)
    local state, reason = supplied, nil
    if state == nil then state, reason = store() end
    if state == nil then return false, reason end
    local ok = true
    for _, player in ipairs(players()) do
        local sent = Authority.syncTo(player, state)
        ok = sent and ok
    end
    return ok
end

function Authority.validate(text, expectedId)
    if type(text) ~= "string" then return nil, "faction_text_required" end
    if #text > Authority.MAX_TEXT_BYTES then return nil, "creator_payload_too_large" end
    local decoded, decodeReason = ProjectALife.RecordCodec.decode(text, { kind = "faction", text = true })
    if decoded == nil then return nil, decodeReason end
    for _, record in ipairs(decoded.records) do
        for section, values in pairs(record) do
            if type(values) == "table" and not Custom.typedSections[section] and not Custom.textSections[section] then
                return nil, "faction_section_invalid:" .. tostring(section)
            end
        end
    end
    local factions = Custom.fromRecords(decoded.records)
    if expectedId ~= nil then
        if #factions ~= 1 then return nil, "faction_record_count" end
        if factions[1].id ~= expectedId then return nil, "faction_id_mismatch" end
    end
    for _, faction in ipairs(factions) do
        if type(faction.id) ~= "string" or string.match(faction.id, "^[%w_%-]+$") == nil then
            return nil, "invalid_faction_id"
        end
        if type(faction.general) ~= "table" or type(faction.spawn) ~= "table" then
            return nil, "faction_shape:" .. tostring(faction.id)
        end
    end
    return factions
end

local function apply(state, reloadCatalog)
    local ok, reason = Custom.applySync(Authority.textOf(state), state.revision, false)
    if not ok then return false, reason end
    if reloadCatalog ~= false and type(Authority.adapters.reload) == "function" then
        local loaded, loadReason = Authority.adapters.reload(Authority.textOf(state), state.revision)
        return loaded ~= false, loadReason
    end
    local catalog = ProjectALife.Catalog
    if reloadCatalog ~= false and catalog ~= nil and type(catalog.reset) == "function"
            and type(catalog.load) == "function" then
        catalog.reset()
        local loaded, loadReason = catalog.load()
        if loaded == nil then return false, loadReason or "catalog_reload_failed" end
    end
    return true
end

Authority.applyState = apply

function Authority.persistState(state)
    if type(Authority.adapters.persist) ~= "function" then return true end
    local ok, result = pcall(Authority.adapters.persist, Authority.TAG, state)
    if ok and result ~= false then return true end
    return false, "custom_factions_persist_failed"
end

function Authority.seedFromLocalStore(state)
    if state == nil or Authority.textOf(state) ~= "" or (tonumber(state.revision) or 0) ~= 0
            or Authority.deferredMigration ~= nil then
        return false
    end
    local text
    local read, readReason = pcall(function()

        local factions = Custom.load()
        if Custom.loadFailed then error("custom_factions_load_failed") end
        if type(factions) ~= "table" then error("custom_factions_load_failed") end
        if #factions == 0 then return end
        text = Custom.serializeFactions(factions)
    end)

    if not read then
        print("[A-Life] creator factions: local factions not seeded (" .. tostring(readReason) .. ")")
        return false
    end
    if type(text) ~= "string" or text == "" then return false end
    if #text > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local valid, validation = Authority.validate(text)
    if valid == nil then text = Authority.salvageSeed(text, validation) end
    if text == nil then return false end
    Authority.writeText(state, text)
    state.revision = 1
    local persisted, persistReason = Authority.persistState(state)
    if not persisted then
        Authority.writeText(state, "")
        state.revision = 0
        return false, persistReason
    end
    Authority.seededFromLocal = true
    return true
end

function Authority.load(reloadCatalog)
    local state, reason = store()
    if state == nil then return false, reason end
    local seeded, seedReason = Authority.seedFromLocalStore(state)
    if seedReason ~= nil then return false, seedReason end
    local factions, validation = Authority.validate(Authority.textOf(state))

    if factions == nil then state, validation = Authority.repairLoaded(state, validation) end
    if state == nil then return false, validation end
    return apply(state, reloadCatalog)
end

function Authority.current()
    return store()
end

local function commit(factions)
    local state, reason = store()
    if state == nil then return false, reason end
    state, reason = Authority.settleMigration(state)
    if state == nil then return false, reason end
    local text = Custom.serializeFactions(factions)
    if #text > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local oldText, oldRevision = Authority.textOf(state), state.revision
    local catalog, oldCatalog = ProjectALife.Catalog, ProjectALife.Catalog and ProjectALife.Catalog.current
    Authority.writeText(state, text)
    state.revision = state.revision + 1
    local persisted = Authority.persistState(state)
    if not persisted then
        Authority.writeText(state, oldText)
        state.revision = oldRevision
        return false, "custom_factions_persist_failed"
    end
    local protected, applied, applyReason = pcall(apply, state, true)
    if not protected or not applied then
        Authority.writeText(state, oldText)
        state.revision = oldRevision
        pcall(apply, state, true)
        if catalog ~= nil then catalog.current = oldCatalog end
        Authority.persistState(state)
        return false, protected and applyReason or tostring(applied)
    end
    Authority.broadcast(state)
    return true, nil, state.revision
end

function Authority.replace(text)
    if type(text) ~= "string" then return false, "faction_text_required" end
    if #text > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local factions, reason = Authority.validate(text)
    if factions == nil then return false, reason end
    return commit(factions)
end

function Authority.upsert(factionId, text)
    if not ProjectALife.CreatorTransfer.validId(factionId) then return false, "invalid_faction_id" end
    if type(text) ~= "string" or #text > Authority.MAX_TEXT_BYTES then
        return false, type(text) == "string" and "creator_payload_too_large"
            or "faction_text_required"
    end
    local incoming, reason = Authority.validate(text, factionId)
    if incoming == nil then return false, reason end
    local state, stateReason = store()
    if state == nil then return false, stateReason end
    local factions, parseReason = Authority.validate(Authority.textOf(state))
    if factions == nil then return false, parseReason end
    local replaced = false
    for index, faction in ipairs(factions) do
        if faction.id == factionId then
            factions[index], replaced = incoming[1], true
            break
        end
    end
    if not replaced then factions[#factions + 1] = incoming[1] end
    return commit(factions)
end

function Authority.delete(factionId)
    if type(factionId) ~= "string"
            or string.match(factionId, "^[%w_%-]+$") == nil then
        return false, "invalid_faction_id"
    end
    local state, stateReason = store()
    if state == nil then return false, stateReason end
    local factions, parseReason = Authority.validate(Authority.textOf(state))
    if factions == nil then return false, parseReason end
    local found = false
    for index = #factions, 1, -1 do
        if factions[index].id == factionId then
            if factions[index].general.deleted == true then return false, "faction_not_found" end
            table.remove(factions, index)
            found = true
        end
    end
    if not found and not (ProjectALife.Catalog and type(ProjectALife.Catalog.faction) == "function"
            and ProjectALife.Catalog.faction(factionId)) then
        return false, "faction_not_found"
    end
    factions[#factions + 1] = Custom.deletionRecord(factionId)
    return commit(factions)
end

function Authority.resetToShipped()
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and catalog.shipped == nil and type(catalog.load) == "function" then
        pcall(catalog.load)
    end
    local shipped = catalog ~= nil and catalog.shipped ~= nil and catalog.shipped.factions or nil
    if type(shipped) ~= "table" then return false, "shipped_catalog_unavailable" end
    local state, stateReason = store()
    if state == nil then return false, stateReason end
    local factions, parseReason = Authority.validate(Authority.textOf(state))
    if factions == nil then return false, parseReason end
    return commit(Custom.withoutShipped(factions, shipped))
end

function Authority.hello(player, revision)
    if player == nil then return false, "player_required" end
    local state, reason = store()
    if state == nil then return false, reason end
    revision = math.floor(tonumber(revision) or -1)
    if revision == state.revision then return true, "current", state.revision end
    local now = type(Authority.adapters.nowMs) == "function" and Authority.adapters.nowMs()
        or (type(getTimestampMs) == "function" and getTimestampMs() or 0)
    local previous = Authority.helloAt[player]
    if previous ~= nil and now >= previous and now - previous < Authority.helloCooldownMs then
        return false, "rate_limited", state.revision, Authority.helloCooldownMs - (now - previous)
    end
    Authority.helloAt[player] = now
    local sent, sendReason = Authority.syncTo(player, state)
    if not sent then return false, sendReason, state.revision, Authority.helloCooldownMs end
    return sent, sendReason, state.revision
end

return Authority
