require "ProjectALife/Records/ALifeCustomProfiles"
require "ProjectALife/Records/ALifeRecordMigration"
require "ProjectALife/Records/ALifeCreatorTransfer"
require "ProjectALife/Records/ALifeCustomFactionAuthority"

ProjectALife = ProjectALife or {}

local Authority = {
    TAG = "ProjectALife.CustomProfiles.v1",
    SCHEMA = 1,
    MAX_CHUNK_BYTES = 8000,

    STORE_CHUNK_CHARS = 8000,

    BACKUP_FILE = "alife_server_profiles.ini",
    STORE_LABEL = "The world's Creator profile store",
    MAX_TEXT_BYTES = 8000000,
    adapters = {},
    storage = nil,

    deferredMigration = nil,
    helloCooldownMs = 10000,
    helloAt = setmetatable({}, { __mode = "k" }),
}
ProjectALife.CustomProfileAuthority = Authority

local Custom = ProjectALife.CustomProfiles

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
        print("[A-Life] Creator profile edits wait until a backup slot in Zomboid/Lua can be written ("
            .. tostring(Migration.backupName(Authority.BACKUP_FILE)) .. " or .old.N.ini)")
    end
    return true
end

function Authority.validProfiles(text)
    return Custom.validate(text, nil, true)
end

function Authority.repair(record, reason)
    local text = Authority.textOf(record)
    if reason == nil and Authority.validProfiles(text) ~= nil then return false end
    local Salvage, Migration = ProjectALife.RecordSalvage, ProjectALife.RecordMigration
    if Salvage == nil or #text > Authority.MAX_TEXT_BYTES then return false, reason end
    local repaired, rejects = Salvage.repairText(text, "member", Custom.serializeProfiles, Authority.validProfiles)
    if repaired == nil then return false, reason or "invalid_profile_line" end
    local kept, keepReason, backup = Migration.keepOld(Authority.BACKUP_FILE, text, Migration.badName)
    Salvage.report("member", rejects, kept and backup or nil)
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
        repaired, rejects = Salvage.repairText(text, "member", Custom.serializeProfiles, Authority.validProfiles)
    end
    if repaired == nil or repaired == "" then
        print("[A-Life] creator profiles: local templates not seeded (" .. tostring(reason) .. ")")
        return nil
    end
    Salvage.report("member", rejects, nil)
    return repaired
end

function Authority.noticeFor(player, index)
    local Salvage = ProjectALife.RecordSalvage
    if index ~= 1 or Salvage == nil then return nil end
    return Salvage.noticeFor(player)
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
        return nil, "custom_profiles_schema_unsupported:" .. tostring(value.schema)
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
    print("[A-Life] Creator profile store replaced; the old one is kept in " .. tostring(backup))
    return record
end

local function send(player, payload)
    if player == nil then return false end
    if type(Authority.adapters.send) == "function" then
        local ok, result = pcall(Authority.adapters.send,
            player, "ProjectALife", "creatorProfileSync", payload)
        return ok and result ~= false
    end
    if type(sendServerCommand) ~= "function" then return false end
    local ok, result = pcall(sendServerCommand, player, "ProjectALife", "creatorProfileSync", payload)
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
            notice = Authority.noticeFor(player, index),
        }) and sent
    end

    if sent then return true, nil end
    return false, "profile_sync_send_failed"
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
    return false, "custom_profiles_persist_failed"
end

local function seedFromLocalStore(state)
    if state == nil or Authority.textOf(state) ~= "" or (tonumber(state.revision) or 0) ~= 0
            or Authority.deferredMigration ~= nil then
        return false
    end
    local text
    local read, readReason = pcall(function()

        local profiles = Custom.load()
        if Custom.loadFailed then error("custom_profiles_load_failed") end
        if type(profiles) ~= "table" then error("custom_profiles_load_failed") end
        local any = false
        for _ in pairs(profiles) do any = true break end
        if not any then return end
        text = Custom.serializeAll()
    end)

    if not read then
        print("[A-Life] creator profiles: local templates not seeded (" .. tostring(readReason) .. ")")
        return false
    end
    if type(text) ~= "string" or text == "" then return false end
    if #text > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local valid, validation = Custom.validate(text, nil, true)
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
    local seeded, seedReason = seedFromLocalStore(state)
    if seedReason ~= nil then return false, seedReason end
    if #Authority.textOf(state) > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local profiles, validation = Custom.validate(Authority.textOf(state), nil, true)

    if profiles == nil then state, validation = Authority.repairLoaded(state, validation) end
    if state == nil then return false, validation end
    return apply(state, reloadCatalog)
end

function Authority.current()
    return store()
end

local function commit(profiles)
    local state, reason = store()
    if state == nil then return false, reason end
    state, reason = Authority.settleMigration(state)
    if state == nil then return false, reason end
    local text = Custom.serializeProfiles(profiles)
    if #text > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local oldText, oldRevision = Authority.textOf(state), state.revision
    local catalog, oldCatalog = ProjectALife.Catalog, ProjectALife.Catalog and ProjectALife.Catalog.current
    Authority.writeText(state, text)
    state.revision = state.revision + 1
    local persisted = Authority.persistState(state)
    if not persisted then
        Authority.writeText(state, oldText)
        state.revision = oldRevision
        return false, "custom_profiles_persist_failed"
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
    if type(text) ~= "string" then return false, "profile_text_required" end
    if #text > Authority.MAX_TEXT_BYTES then return false, "creator_payload_too_large" end
    local profiles, reason = Custom.validate(text, nil, true)
    if profiles == nil then return false, reason end
    return commit(profiles)
end

function Authority.replaceCreator(profileText, factionText)
    local factionsAuthority = ProjectALife.CustomFactionAuthority
    if type(profileText) ~= "string" or #profileText > Authority.MAX_TEXT_BYTES then
        return false, "creator_profile_payload_invalid"
    end
    local profiles, reason = Custom.validate(profileText, nil, true)
    if profiles == nil then return false, reason end
    local factions, factionReason = factionsAuthority.validate(factionText)
    if factions == nil then return false, factionReason end
    local nextProfiles = Custom.serializeProfiles(profiles)
    local nextFactions = ProjectALife.CustomFactions.serializeFactions(factions)
    if #nextProfiles > Authority.MAX_TEXT_BYTES or #nextFactions > factionsAuthority.MAX_TEXT_BYTES then
        return false, "creator_payload_too_large"
    end
    local ps, profileStoreReason = store()
    if ps == nil then return false, profileStoreReason end
    local fs, factionStoreReason = factionsAuthority.current()
    if fs == nil then return false, factionStoreReason end
    ps, profileStoreReason = Authority.settleMigration(ps)
    if ps == nil then return false, profileStoreReason end
    fs, factionStoreReason = factionsAuthority.settleMigration(fs)
    if fs == nil then return false, factionStoreReason end
    local oldProfiles, oldFactions = Authority.textOf(ps), factionsAuthority.textOf(fs)
    local oldProfileRevision, oldFactionRevision = ps.revision, fs.revision
    local catalog, oldCatalog = ProjectALife.Catalog, ProjectALife.Catalog and ProjectALife.Catalog.current
    Authority.writeText(ps, nextProfiles)
    factionsAuthority.writeText(fs, nextFactions)
    ps.revision, fs.revision = ps.revision + 1, fs.revision + 1
    local protected, committed, commitReason = pcall(function()
        local ok, why = factionsAuthority.applyState(fs, false)
        if not ok then return false, why end
        ok, why = apply(ps, true)
        if not ok then return false, why end
        ok, why = factionsAuthority.persistState(fs)
        if not ok then return false, why end
        return Authority.persistState(ps)
    end)
    if not protected or not committed then
        Authority.writeText(ps, oldProfiles)
        factionsAuthority.writeText(fs, oldFactions)
        ps.revision, fs.revision = oldProfileRevision, oldFactionRevision
        pcall(factionsAuthority.applyState, fs, false)
        pcall(apply, ps, true)
        if catalog ~= nil then catalog.current = oldCatalog end
        factionsAuthority.persistState(fs)
        Authority.persistState(ps)
        return false, protected and commitReason or tostring(committed)
    end
    factionsAuthority.broadcast(fs)
    Authority.broadcast(ps)
    return true
end

function Authority.upsert(profileId, text)
    if not ProjectALife.CreatorTransfer.validId(profileId) then return false, "invalid_profile_id" end
    if type(text) ~= "string" or #text > Authority.MAX_TEXT_BYTES then
        return false, type(text) == "string" and "creator_payload_too_large"
            or "profile_text_required"
    end
    local incoming, reason = Custom.validate(text, profileId, false)
    if incoming == nil then return false, reason end
    local state, stateReason = store()
    if state == nil then return false, stateReason end
    local profiles, parseReason = Custom.validate(Authority.textOf(state), nil, true)
    if profiles == nil then return false, parseReason end
    local replaced = false
    for index, profile in ipairs(profiles) do
        if profile.id == profileId then
            profiles[index], replaced = incoming[1], true
            break
        end
    end
    if not replaced then profiles[#profiles + 1] = incoming[1] end
    return commit(profiles)
end

function Authority.delete(profileId)
    if type(profileId) ~= "string"
            or string.match(profileId, "^[%w_%-]+$") == nil then
        return false, "invalid_profile_id"
    end
    local state, stateReason = store()
    if state == nil then return false, stateReason end
    local profiles, parseReason = Custom.validate(Authority.textOf(state), nil, true)
    if profiles == nil then return false, parseReason end
    local found = false
    for index = #profiles, 1, -1 do
        if profiles[index].id == profileId then
            if profiles[index].general.deleted == true then return false, "profile_not_found" end
            table.remove(profiles, index)
            found = true
        end
    end
    if not found and not (ProjectALife.Catalog and ProjectALife.Catalog.npc
            and ProjectALife.Catalog.npc(profileId)) then return false, "profile_not_found" end
    profiles[#profiles + 1] = Custom.deletionRecord(profileId)
    return commit(profiles)
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
