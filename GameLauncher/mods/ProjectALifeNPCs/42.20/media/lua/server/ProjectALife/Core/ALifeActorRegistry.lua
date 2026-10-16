ProjectALife = ProjectALife or {}
require "ProjectALife/Records/ALifeNames"

local Registry = {
    records = {},
    order = {},
    operations = {},
    operationOrder = {},
    maximumOperations = 2048,
    maximumDeadRecords = 256,
    noSpawnZones = {},
    worldState = {},
    zoneSequence = 0,
    sequence = 0,
    adapters = {},

    persistMemo = {},
    operationEpoch = 0,
    operationMemo = nil,
    metrics = { persistCopies = 0 },
}
ProjectALife.ActorRegistry = Registry

local LIFECYCLES = {
    dormant = true,
    spawning = true,
    active = true,
    dead = true,
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("actor_record_cycle") end
    seen[value] = true
    local result = {}

    for key, entry in pairs(value) do
        if type(key) == "table" then key = copy(key, seen) end
        if type(entry) == "table" then entry = copy(entry, seen) end
        result[key] = entry
    end
    seen[value] = nil
    return result
end

local function adminPersistent(record)
    local memory = type(record) == "table" and record.memory or nil
    local admin = type(memory) == "table" and memory.admin or nil
    return type(admin) == "table" and admin.persistent == true
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function validPosition(position)
    return type(position) == "table" and finite(position.x)
        and finite(position.y) and finite(position.z)
end

local function validRecord(record)
    return type(record) == "table" and type(record.uid) == "string"
        and #record.uid > 0 and #record.uid <= 64
        and type(record.revision) == "number" and record.revision >= 1
        and record.revision == math.floor(record.revision)
        and type(record.generation) == "number" and record.generation >= 0
        and record.generation == math.floor(record.generation)
        and LIFECYCLES[record.lifecycle] == true
        and type(record.profileId) == "string" and #record.profileId > 0
        and type(record.factionId) == "string" and #record.factionId > 0
        and validPosition(record.worldPosition)
end

local function snapshot()
    local records = {}
    for _, uid in ipairs(Registry.order) do records[#records + 1] = copy(Registry.records[uid]) end
    return {
        records = records,
        operations = copy(Registry.operations),
        operationOrder = copy(Registry.operationOrder),
        noSpawnZones = copy(Registry.noSpawnZones),
        worldState = copy(Registry.worldState),
        zoneSequence = Registry.zoneSequence,
        sequence = Registry.sequence,
    }
end

function Registry.persistSnapshot()
    local previous = Registry.persistMemo or {}
    local memo, records, copies = {}, {}, 0
    for _, uid in ipairs(Registry.order) do
        local live = Registry.records[uid]
        local saved = live
        if type(live) == "table" then
            saved = previous[live]
            if saved == nil then
                saved = copy(live)
                copies = copies + 1
            end
            memo[live] = saved
        end
        records[#records + 1] = saved
    end
    local history = Registry.operationMemo
    if history == nil or history.epoch ~= Registry.operationEpoch
            or history.source ~= Registry.operations or history.sourceOrder ~= Registry.operationOrder then
        local oldMemo = history and history.memo or {}
        history = { epoch = Registry.operationEpoch, source = Registry.operations,
            sourceOrder = Registry.operationOrder, operations = {}, order = copy(Registry.operationOrder), memo = {} }
        for operationId, operation in pairs(Registry.operations) do
            local saved = operation
            if type(operation) == "table" then
                saved = oldMemo[operation]
                if saved == nil then
                    saved = copy(operation)
                    copies = copies + 1
                end
                history.memo[operation] = saved
            end
            if type(operationId) == "table" then operationId = copy(operationId) end
            history.operations[operationId] = saved
        end
        Registry.operationMemo = history
    end
    local result = {
        records = records,
        operations = history.operations,
        operationOrder = history.order,
        noSpawnZones = copy(Registry.noSpawnZones),
        worldState = copy(Registry.worldState),
        zoneSequence = Registry.zoneSequence,
        sequence = Registry.sequence,
    }
    Registry.persistMemo = memo
    if type(Registry.metrics) ~= "table" then Registry.metrics = {} end
    Registry.metrics.persistCopies = copies
    return result
end

local function persist()
    if type(Registry.adapters.persist) ~= "function" then return true end
    local ok, result = pcall(Registry.adapters.persist, Registry.persistSnapshot(), true)
    return ok and result == true
end

local function emit(category, fields)
    if type(Registry.adapters.emit) == "function" then Registry.adapters.emit(category, fields) end
end

local function newUid()
    Registry.sequence = Registry.sequence + 1
    if type(Registry.adapters.newUid) == "function" then
        return Registry.adapters.newUid(Registry.sequence)
    end
    local now = type(Registry.adapters.nowMs) == "function" and Registry.adapters.nowMs()
        or (type(getTimestampMs) == "function" and getTimestampMs())
        or math.floor(os.time() * 1000)
    return "palife:" .. tostring(now) .. ":" .. tostring(Registry.sequence)
end

function Registry.configure(adapters)
    Registry.adapters = adapters or {}
end

function Registry.reset()
    Registry.records = {}
    Registry.order = {}
    Registry.operations = {}
    Registry.operationOrder = {}
    Registry.noSpawnZones = {}
    Registry.worldState = {}
    Registry.zoneSequence = 0
    Registry.sequence = 0
    Registry.persistMemo = {}
    Registry.operationEpoch = 0
    Registry.operationMemo = nil
    Registry.metrics = { persistCopies = 0 }
end

function Registry.snapshot()
    return snapshot()
end

Registry.retiredModeIds = { roadblock = "blockade" }
Registry.retiredModeFields = { "stance", "adminMode", "behavior", "program", "encounter" }

function Registry.renameRetiredModes(record)
    local memory = type(record) == "table" and record.memory or nil
    if type(memory) ~= "table" then return false end
    local renamed = false
    for _, field in ipairs(Registry.retiredModeFields) do
        local value = memory[field]
        local current = type(value) == "string" and Registry.retiredModeIds[value] or nil
        if current ~= nil then
            memory[field] = current
            renamed = true
        end
    end
    local camp = type(memory.nightCampRestore) == "table" and memory.nightCampRestore or nil
    local kept = camp ~= nil and type(camp.stance) == "string" and Registry.retiredModeIds[camp.stance] or nil
    if kept ~= nil then
        camp.stance = kept
        renamed = true
    end
    return renamed
end

function Registry.nameRecord(record)
    local names = ProjectALife.Names
    if names == nil or type(names.assign) ~= "function" then return nil end
    local ok, name = pcall(names.assign, record, Registry.records)
    return ok and name or nil
end

function Registry.lookRecord(record)
    local look = ProjectALife.Appearance
    if look == nil or type(look.stamp) ~= "function" then return false end
    local ok, stamped = pcall(look.stamp, record)
    return ok and stamped == true
end

function Registry.nameUnnamed()
    local names = ProjectALife.Names
    if names == nil or type(names.backfill) ~= "function" then return 0 end
    local ok, count = pcall(names.backfill, Registry.order, Registry.records)
    return ok and count or 0
end

function Registry.restore(saved, validateActor)
    if saved == nil then
        Registry.reset()
        return true, 0
    end
    if type(saved) ~= "table" or type(saved.records) ~= "table"
            or type(saved.operations) ~= "table" then
        return false, "actor_snapshot_invalid"
    end

    local records, order = {}, {}
    local normalized, unknownActors = 0, 0
    for index, stored in ipairs(saved.records) do
        if not validRecord(stored) then
            return false, "actor_snapshot_record_invalid:" .. tostring(index)
        end
        local record = copy(stored)
        Registry.renameRetiredModes(record)
        if record.lifecycle == "active" or record.lifecycle == "spawning" then
            record.lifecycle = "dormant"
            record.activity = "idle"
            record.intent = "hold"
            record.revision = record.revision + 1
            normalized = normalized + 1
        end
        if not validRecord(record) or records[record.uid] ~= nil then
            return false, "actor_snapshot_record_invalid:" .. tostring(index)
        end
        local accepted = true
        if type(validateActor) == "function" then
            local ok, result = pcall(validateActor, record)
            accepted = ok and result == true
        end
        if accepted then
            records[record.uid] = record
            order[#order + 1] = record.uid
        else
            normalized = normalized + 1
            unknownActors = unknownActors + 1
        end
    end

    local deadCount = 0
    for _, uid in ipairs(order) do
        if records[uid].lifecycle == "dead" then deadCount = deadCount + 1 end
    end
    local deadExcess = math.max(0, deadCount - Registry.maximumDeadRecords)
    if deadExcess > 0 then
        local retained = {}
        for _, uid in ipairs(order) do
            if deadExcess > 0 and records[uid].lifecycle == "dead"
                    and not adminPersistent(records[uid]) then
                records[uid] = nil
                deadExcess = deadExcess - 1
                normalized = normalized + 1
            else
                retained[#retained + 1] = uid
            end
        end
        order = retained
    end

    local operations, operationOrder = {}, {}
    for operationId, operation in pairs(saved.operations) do
        if type(operationId) ~= "string" or #operationId < 1
                or type(operation) ~= "table" or type(operation.fingerprint) ~= "string"
                or type(operation.uid) ~= "string" then
            return false, "actor_snapshot_operation_invalid:" .. tostring(operationId)
        end
        if records[operation.uid] ~= nil then
            operations[operationId] = copy(operation)
        else
            normalized = normalized + 1
        end
    end

    if type(saved.operationOrder) == "table" then
        for _, operationId in ipairs(saved.operationOrder) do
            if operations[operationId] ~= nil then operationOrder[#operationOrder + 1] = operationId end
        end
    end
    if #operationOrder == 0 then
        for operationId in pairs(operations) do operationOrder[#operationOrder + 1] = operationId end
        table.sort(operationOrder)
    end
    while #operationOrder > Registry.maximumOperations do
        operations[table.remove(operationOrder, 1)] = nil
        normalized = normalized + 1
    end

    local noSpawnZones = {}
    for index, stored in ipairs(type(saved.noSpawnZones) == "table" and saved.noSpawnZones or {}) do
        local zone = copy(stored)
        if type(zone) ~= "table" or type(zone.id) ~= "string" or not finite(tonumber(zone.x))
                or not finite(tonumber(zone.y)) or not finite(tonumber(zone.z))
                or not finite(tonumber(zone.radius)) or tonumber(zone.radius) < 1 then
            return false, "actor_snapshot_zone_invalid:" .. tostring(index)
        end
        zone.x, zone.y, zone.z = tonumber(zone.x), tonumber(zone.y), tonumber(zone.z)
        zone.radius = math.min(200, tonumber(zone.radius))
        noSpawnZones[#noSpawnZones + 1] = zone
    end

    local sequence = tonumber(saved.sequence) or 0
    if sequence < 0 or sequence ~= math.floor(sequence) then
        return false, "actor_snapshot_sequence_invalid"
    end
    Registry.records = records
    Registry.order = order
    Registry.operations = operations
    Registry.operationOrder = operationOrder
    Registry.noSpawnZones = noSpawnZones
    Registry.worldState = type(saved.worldState) == "table" and copy(saved.worldState) or {}
    Registry.zoneSequence = math.max(0, math.floor(tonumber(saved.zoneSequence) or 0))
    Registry.sequence = sequence
    Registry.nameUnnamed()
    return true, normalized, { unknownActors = unknownActors }
end

local function removeOperation(operationId)
    Registry.operationEpoch = Registry.operationEpoch + 1
    Registry.operations[operationId] = nil
    for index, candidate in ipairs(Registry.operationOrder) do
        if candidate == operationId then table.remove(Registry.operationOrder, index); break end
    end
end

local function recordOperation(operationId, operation)
    Registry.operationEpoch = Registry.operationEpoch + 1
    Registry.operations[operationId] = operation
    Registry.operationOrder[#Registry.operationOrder + 1] = operationId
    while #Registry.operationOrder > Registry.maximumOperations do
        Registry.operations[table.remove(Registry.operationOrder, 1)] = nil
    end
end

function Registry.pruneDead(maximumToKeep)
    local maximum = math.max(0, math.floor(
        tonumber(maximumToKeep) or Registry.maximumDeadRecords))
    local deadCount = 0
    for _, uid in ipairs(Registry.order) do
        if Registry.records[uid].lifecycle == "dead" then deadCount = deadCount + 1 end
    end
    local excess = deadCount - maximum
    if excess <= 0 then return true, 0 end

    local removed, newOrder, removedCount = {}, {}, 0
    for _, uid in ipairs(Registry.order) do
        if excess > 0 and Registry.records[uid].lifecycle == "dead"
                and not adminPersistent(Registry.records[uid]) then
            removed[uid] = true
            excess = excess - 1
            removedCount = removedCount + 1
        else
            newOrder[#newOrder + 1] = uid
        end
    end
    local newRecords = {}
    for uid, record in pairs(Registry.records) do
        if not removed[uid] then newRecords[uid] = record end
    end
    local newOperations, newOperationOrder = {}, {}
    for _, operationId in ipairs(Registry.operationOrder) do
        local operation = Registry.operations[operationId]
        if operation and not removed[operation.uid] then
            newOperations[operationId] = operation
            newOperationOrder[#newOperationOrder + 1] = operationId
        end
    end
    local oldRecords, oldOrder = Registry.records, Registry.order
    local oldOperations, oldOperationOrder = Registry.operations, Registry.operationOrder
    Registry.records, Registry.order = newRecords, newOrder
    Registry.operations, Registry.operationOrder = newOperations, newOperationOrder
    if not persist() then
        Registry.records, Registry.order = oldRecords, oldOrder
        Registry.operations, Registry.operationOrder = oldOperations, oldOperationOrder
        return false, "dead_prune_persistence_failed"
    end
    emit("dead_actors_pruned", { count = removedCount })
    return true, removedCount
end

function Registry.create(specification)
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("actor_record") then return nil, "cleanup_locked" end
    if type(specification) ~= "table" or type(specification.operationId) ~= "string"
        or #specification.operationId < 1 or #specification.operationId > 128
        or type(specification.fingerprint) ~= "string" or #specification.fingerprint < 1
        or type(specification.profileId) ~= "string" or #specification.profileId < 1
        or type(specification.factionId) ~= "string" or #specification.factionId < 1
        or not validPosition(specification.worldPosition) then
        return nil, "actor_specification_invalid"
    end
    local prior = Registry.operations[specification.operationId]
    if prior then
        if prior.fingerprint ~= specification.fingerprint then
            return nil, "operation_conflict"
        end
        return copy(Registry.records[prior.uid]), true
    end
    local uid = specification.uid or newUid()
    if type(uid) ~= "string" or #uid < 1 or #uid > 64 or Registry.records[uid] then
        return nil, "uid_invalid"
    end
    local record = {
        uid = uid,
        revision = 1,
        generation = 0,
        lifecycle = "dormant",
        profileId = specification.profileId,
        factionId = specification.factionId,
        worldPosition = copy(specification.worldPosition),
        activity = specification.activity or "idle",
        intent = specification.intent or "hold",
        memory = copy(specification.memory or {}),
    }
    if record.memory.loadoutDay == nil and type(getGameTime) == "function" then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and finite(hours) then record.memory.loadoutDay = math.max(0, math.floor(hours / 24)) end
    end

    if record.memory.loadoutMonth == nil and type(getGameTime) == "function" then
        local ok, month = pcall(function() return getGameTime():getMonth() end)
        if ok and finite(month) then record.memory.loadoutMonth = math.floor(month) end
    end
    Registry.nameRecord(record)
    Registry.lookRecord(record)
    if not validRecord(record) then return nil, "actor_record_invalid" end
    Registry.records[uid] = record
    Registry.order[#Registry.order + 1] = uid
    recordOperation(specification.operationId, {
        fingerprint = specification.fingerprint,
        uid = uid,
    })
    if not persist() then
        Registry.records[uid] = nil
        removeOperation(specification.operationId)
        table.remove(Registry.order)
        return nil, "actor_persistence_failed"
    end
    emit("actor_created", { uid = uid, revision = 1, generation = 0 })
    return copy(record), false
end

function Registry.read(uid)
    local record = Registry.records[uid]
    return record and copy(record) or nil
end

Registry.copyingRead = Registry.read
function Registry.peek(uid)

    if Registry.read ~= Registry.copyingRead then return Registry.read(uid) end
    return Registry.records[uid]
end

function Registry.list()
    local result = {}
    for _, uid in ipairs(Registry.order) do result[#result + 1] = copy(Registry.records[uid]) end
    return result
end

function Registry.each(callback)
    if type(callback) ~= "function" then return 0 end
    local visited = 0
    for _, uid in ipairs(Registry.order) do
        local record = Registry.records[uid]
        if record ~= nil then
            visited = visited + 1
            if callback(record) == true then break end
        end
    end
    return visited
end

function Registry.update(uid, expectedRevision, mutation)
    local current = Registry.records[uid]
    if not current then return nil, "actor_not_found" end
    if current.revision ~= expectedRevision then return nil, "actor_revision_conflict" end
    if type(mutation) ~= "function" then return nil, "actor_mutation_invalid" end
    local candidate = copy(current)
    local ok, mutationError = pcall(mutation, candidate)
    if not ok then return nil, "actor_mutation_failed:" .. tostring(mutationError) end
    candidate.revision = current.revision + 1
    if not validRecord(candidate) then return nil, "actor_record_invalid" end
    Registry.records[uid] = candidate
    if not persist() then
        Registry.records[uid] = current
        return nil, "actor_persistence_failed"
    end
    if current.lifecycle ~= "dead" and candidate.lifecycle == "dead" then Registry.noteDeath(candidate) end
    emit("actor_updated", {
        uid = uid,
        revision = candidate.revision,
        generation = candidate.generation,
        lifecycle = candidate.lifecycle,
    })
    return copy(candidate)
end

function Registry.updateTransient(uid, expectedRevision, mutation, noResult)
    local current = Registry.records[uid]
    if not current then return nil, "actor_not_found" end
    if current.revision ~= expectedRevision then return nil, "actor_revision_conflict" end
    if type(mutation) ~= "function" then return nil, "actor_mutation_invalid" end
    local candidate = copy(current)
    local ok, mutationError = pcall(mutation, candidate)
    if not ok then return nil, "actor_mutation_failed:" .. tostring(mutationError) end
    candidate.revision = current.revision + 1
    if not validRecord(candidate) then return nil, "actor_record_invalid" end
    Registry.records[uid] = candidate
    if current.lifecycle ~= "dead" and candidate.lifecycle == "dead" then Registry.noteDeath(candidate) end
    if noResult == true then return true end
    return copy(candidate)
end

function Registry.noteDeath(record)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusDeath) ~= "function" then return false end
    local ok, counted = pcall(census.censusDeath, record)
    return ok and counted == true
end

function Registry.updateMany(uids, mutation)
    if type(uids) ~= "table" or type(mutation) ~= "function" then
        return nil, "actor_mutation_invalid"
    end
    local previous, written = {}, {}
    for _, uid in ipairs(uids) do
        local current = Registry.records[uid]
        if current ~= nil and previous[uid] == nil then
            local candidate = copy(current)
            local ok, result = pcall(mutation, candidate)
            if ok and result ~= false then
                candidate.revision = current.revision + 1
                if validRecord(candidate) then
                    previous[uid] = current
                    written[#written + 1] = { uid = uid, record = candidate }
                end
            end
        end
    end
    if #written == 0 then return 0 end
    for _, entry in ipairs(written) do Registry.records[entry.uid] = entry.record end
    if not persist() then
        for uid, record in pairs(previous) do Registry.records[uid] = record end
        return nil, "actor_persistence_failed"
    end
    for _, entry in ipairs(written) do
        if previous[entry.uid].lifecycle ~= "dead" and entry.record.lifecycle == "dead" then
            Registry.noteDeath(entry.record)
        end
        emit("actor_updated", {
            uid = entry.uid,
            revision = entry.record.revision,
            generation = entry.record.generation,
            lifecycle = entry.record.lifecycle,
        })
    end
    return #written
end

function Registry.setActivity(uid, expectedRevision, activity, intent, noResult)
    return Registry.updateTransient(uid, expectedRevision, function(record)
        record.activity = type(activity) == "string" and activity or "idle"
        record.intent = type(intent) == "string" and intent or "hold"
    end, noResult)
end

function Registry.checkpointActive(updates)
    if type(updates) ~= "table" then return false, "checkpoint_invalid" end
    if #updates == 0 then return true, 0 end
    local previous, replacements, seen = {}, {}, {}
    for index, update in ipairs(updates) do
        if type(update) ~= "table" or type(update.uid) ~= "string"
                or seen[update.uid] or not validPosition(update.worldPosition)
                or type(update.shellState) ~= "table" then
            return false, "checkpoint_invalid:" .. tostring(index)
        end
        seen[update.uid] = true
        local current = Registry.records[update.uid]
        if current == nil or current.lifecycle ~= "active"
                or current.generation ~= update.generation then
            return false, "checkpoint_actor_stale:" .. update.uid
        end
        local candidate = copy(current)
        candidate.revision = current.revision + 1
        candidate.worldPosition = copy(update.worldPosition)
        candidate.memory = type(candidate.memory) == "table" and candidate.memory or {}
        candidate.memory.shellState = copy(update.shellState)
        if not validRecord(candidate) then return false, "checkpoint_record_invalid" end
        previous[update.uid] = current
        replacements[update.uid] = candidate
    end
    for uid, record in pairs(replacements) do Registry.records[uid] = record end
    if not persist() then
        for uid, record in pairs(previous) do Registry.records[uid] = record end
        return false, "checkpoint_persistence_failed"
    end
    emit("actors_checkpointed", { count = #updates })
    return true, #updates
end

function Registry.listNoSpawnZones()
    return copy(Registry.noSpawnZones)
end

function Registry.getWorldValue(key)
    return type(key) == "string" and copy(Registry.worldState[key]) or nil
end

function Registry.setWorldValue(key, value)
    if type(key) ~= "string" or #key < 1 or #key > 64 then
        return false, "world_state_key_invalid"
    end
    local previous = Registry.worldState[key]
    Registry.worldState[key] = copy(value)
    if not persist() then
        Registry.worldState[key] = previous
        return false, "world_state_persistence_failed"
    end
    return true
end

function Registry.addNoSpawnZone(specification)
    if type(specification) ~= "table" or not finite(tonumber(specification.x))
            or not finite(tonumber(specification.y)) or not finite(tonumber(specification.z))
            or not finite(tonumber(specification.radius)) then
        return nil, "no_spawn_zone_invalid"
    end
    local radius = math.max(1, math.min(200, tonumber(specification.radius)))
    Registry.zoneSequence = Registry.zoneSequence + 1
    local zone = {
        id = "alife-zone:" .. tostring(Registry.zoneSequence),
        name = string.sub(tostring(specification.name or "Protected area"), 1, 64),
        x = tonumber(specification.x), y = tonumber(specification.y),
        z = tonumber(specification.z), radius = radius,
        createdBy = string.sub(tostring(specification.createdBy or "admin"), 1, 64),
    }
    Registry.noSpawnZones[#Registry.noSpawnZones + 1] = zone
    if not persist() then
        table.remove(Registry.noSpawnZones)
        Registry.zoneSequence = Registry.zoneSequence - 1
        return nil, "no_spawn_zone_persistence_failed"
    end
    emit("no_spawn_zone_added", { id = zone.id, radius = zone.radius })
    return copy(zone)
end

function Registry.clearNoSpawnZones()
    local previous = Registry.noSpawnZones
    Registry.noSpawnZones = {}
    if not persist() then
        Registry.noSpawnZones = previous
        return false, "no_spawn_zone_persistence_failed"
    end
    emit("no_spawn_zones_cleared", { count = #previous })
    return true, #previous
end

function Registry.remove(uid, expectedRevision, reason)
    local current = Registry.records[uid]
    if current == nil then return false, "actor_not_found" end
    if current.revision ~= expectedRevision then return false, "actor_revision_conflict" end
    if current.lifecycle ~= "dormant" and current.lifecycle ~= "dead" then
        return false, "actor_remove_requires_inactive"
    end
    local index
    for candidateIndex, candidate in ipairs(Registry.order) do
        if candidate == uid then index = candidateIndex; break end
    end
    Registry.records[uid] = nil
    if index then table.remove(Registry.order, index) end
    local removedOperations = {}
    for operationId, operation in pairs(Registry.operations) do
        if operation.uid == uid then
            removedOperations[#removedOperations + 1] = {
                id = operationId, value = operation,
            }
            removeOperation(operationId)
        end
    end
    if not persist() then
        Registry.records[uid] = current
        if index then table.insert(Registry.order, index, uid) end
        for _, operation in ipairs(removedOperations) do
            recordOperation(operation.id, operation.value)
        end
        return false, "actor_persistence_failed"
    end
    emit("actor_removed", { uid = uid, reason = reason or "removed" })
    return true
end

function Registry.beginSpawn(uid, expectedRevision)
    return Registry.update(uid, expectedRevision, function(record)
        if record.lifecycle ~= "dormant" then error("actor_not_dormant") end
        record.generation = record.generation + 1
        record.lifecycle = "spawning"
    end)
end

function Registry.activate(uid, expectedRevision, generation, position)
    return Registry.update(uid, expectedRevision, function(record)
        if record.lifecycle ~= "spawning" or record.generation ~= generation then
            error("spawn_generation_changed")
        end
        if position ~= nil then
            if not validPosition(position) then error("spawn_position_invalid") end
            record.worldPosition = copy(position)
        end
        record.lifecycle = "active"
        if type(record.memory) == "table" then record.memory.restoreAfterSave = nil end
    end)
end

function Registry.makeDormant(uid, expectedRevision, generation, position, shellState, restoreAfterSave)
    return Registry.update(uid, expectedRevision, function(record)
        if record.generation ~= generation or record.lifecycle == "dead" then
            error("actor_generation_changed")
        end
        if position ~= nil then
            if not validPosition(position) then error("dormant_position_invalid") end
            record.worldPosition = copy(position)
        end
        if shellState ~= nil then
            record.memory = type(record.memory) == "table" and record.memory or {}
            record.memory.shellState = copy(shellState)
        end
        if restoreAfterSave ~= nil then
            record.memory = type(record.memory) == "table" and record.memory or {}
            record.memory.restoreAfterSave = restoreAfterSave == true or nil
        end
        record.lifecycle = "dormant"
        record.activity = "idle"
        record.intent = "hold"
    end)
end

function Registry.markDead(uid, expectedRevision, generation, position)
    local dead, reason = Registry.update(uid, expectedRevision, function(record)
        if record.generation ~= generation then error("actor_generation_changed") end
        if position ~= nil then
            if not validPosition(position) then error("death_position_invalid") end
            record.worldPosition = copy(position)
        end
        record.lifecycle = "dead"
        record.activity = "dead"
        record.intent = "none"
    end)
    if dead ~= nil then Registry.pruneDead(Registry.maximumDeadRecords) end
    return dead, reason
end

return Registry
