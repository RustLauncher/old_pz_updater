ProjectALife = ProjectALife or {}

local Persistence = {
    TAG = "ProjectALife.World.v1",
    SCHEMA = 1,
    adapters = {},
    storage = nil,
    dirty = false,
    squadCap = 3,
    keepEncounters = false,
    hostileKinds = { raid = true, fullscale_raid = true, assassination = true,
        highway_ambush = true, rooftop_snipers = true },
    metrics = {},
    operationMemo = nil,
}
ProjectALife.Persistence = Persistence

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("persistence_cycle") end
    seen[value] = true
    local result = {}
    for key, entry in pairs(value) do result[copy(key, seen)] = copy(entry, seen) end
    seen[value] = nil
    return result
end

local function nowMs()
    if type(Persistence.adapters.nowMs) == "function" then return Persistence.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function storage()
    if Persistence.storage ~= nil then return Persistence.storage end
    local result
    if type(Persistence.adapters.getOrCreate) == "function" then
        result = Persistence.adapters.getOrCreate(Persistence.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        result = ModData.getOrCreate(Persistence.TAG)
    end
    if type(result) ~= "table" then return nil, "mod_data_unavailable" end
    Persistence.storage = result
    return result
end

function Persistence.configure(adapters)
    Persistence.adapters = adapters or {}
    Persistence.squadCap = math.max(0, math.min(500, math.floor(
        tonumber(Persistence.adapters.squadCap) or 3)))
    Persistence.keepEncounters = Persistence.adapters.keepEncounterNpcs == true
    Persistence.storage = nil
    Persistence.dirty = false
    Persistence.metrics = {}
    Persistence.operationMemo = nil
end

local function actorGroup(record)
    local m = type(record.memory) == "table" and record.memory or {}
    if m.sessionOnly == true or m.outpostSquadId ~= nil then return nil end

    if m.outpostId ~= nil then return "outpost:" .. tostring(m.outpostId) end
    if type(m.encounter) == "string" and string.sub(m.encounter, 1, 8) == "outpost:" then
        return m.encounter
    end
    if m.squadId ~= nil then return tostring(m.squadId) end
    if m.persistent == true or (type(m.admin) == "table" and m.admin.persistent == true) then
        return tostring(m.groupId or m.encounter or record.uid)
    end
end

function Persistence.encounterKey(record)
    local m = type(record.memory) == "table" and record.memory or nil
    if m == nil or m.natural ~= true or m.debugSpawn == true or m.sessionOnly == true then return nil end
    if m.outpostSquadId ~= nil or m.squadId ~= nil or m.admin ~= nil or m.support ~= nil
            or m.targetUsername ~= nil or record.lifecycle == "dead" then
        return nil
    end
    if Persistence.hostileKinds[tostring(m.encounterKind)] == true then return nil end
    local pressure = ProjectALife.WorldPressure
    if type(pressure) ~= "table" or type(pressure.censusHostile) ~= "function" then return nil end
    local ok, hostile = pcall(pressure.censusHostile, record.factionId, m)
    if not ok or hostile ~= false then return nil end
    return "encounter:" .. tostring(m.groupId or record.uid)
end

function Persistence.actorGroupCount()
    local groups, count = {}, 0
    local registry = ProjectALife.ActorRegistry
    if registry and type(registry.each) == "function" then registry.each(function(record)
        local m = record.memory or {}
        local id = actorGroup(record)
        if id and not m.squadId and record.lifecycle ~= "dead" and not groups[id] then
            groups[id], count = true, count + 1
        end
    end) end
    return count
end

function Persistence.residentGroups()
    local populate = ProjectALife.PopulateDirector
    if populate == nil or type(populate.groupIds) ~= "function" then return {} end
    local ok, groups = pcall(populate.groupIds)
    if ok and type(groups) == "table" then return groups end
    return {}
end

function Persistence.filteredOperations(snapshot, retained, owned)
    local memo = owned == true and Persistence.operationMemo or nil
    local reuse = memo ~= nil and memo.source == snapshot.operations
        and memo.sourceOrder == snapshot.operationOrder
    if reuse then
        for uid in pairs(retained) do if not memo.retained[uid] then reuse = false; break end end
        if reuse then
            for uid in pairs(memo.retained) do if not retained[uid] then reuse = false; break end end
        end
    end
    if reuse then return memo.operations, memo.order end
    local operations, order = {}, {}
    for id, operation in pairs(snapshot.operations or {}) do
        if retained[operation.uid] then operations[id] = operation end
    end
    for _, id in ipairs(snapshot.operationOrder or {}) do
        if operations[id] then order[#order + 1] = id end
    end
    if owned == true then
        Persistence.operationMemo = { source = snapshot.operations, sourceOrder = snapshot.operationOrder,
            retained = retained, operations = operations, order = order }
    end
    return operations, order
end

function Persistence.forSave(snapshot, owned)
    local allowed, count, ledger = {}, 0, ProjectALife.SquadLedger
    local squads, residents, placed = 0, 0, Persistence.residentGroups()
    if ledger and type(ledger.liveIds) == "function" then

        for _, id in ipairs(ledger.liveIds()) do allowed[id], squads = true, squads + 1 end
    elseif ledger and type(ledger.list) == "function" then
        for _, squad in ipairs(ledger.list()) do
            if squad.state ~= "wiped" then
                allowed[squad.id], squads = true, squads + 1
            end
        end
    end
    for _, record in ipairs(snapshot.records or {}) do
        local id = actorGroup(record)
        local m = record.memory or {}
        if id and not m.squadId and not allowed[id] and record.lifecycle ~= "dead" then
            if m.encounter == "outpost" and placed[id] == true then
                allowed[id], residents = true, residents + 1
            elseif count < Persistence.squadCap then
                allowed[id], count = true, count + 1
            end
        end
    end
    local encounters, kept = {}, 0
    if Persistence.keepEncounters == true then
        local keys, order, rows = {}, {}, snapshot.records or {}
        for index, record in ipairs(rows) do
            if actorGroup(record) == nil then
                local key = Persistence.encounterKey(record)
                if key ~= nil then
                    keys[index] = key
                    if encounters[key] == nil then
                        encounters[key] = false
                        order[#order + 1] = key
                    end
                end
            end
        end
        for index = #order, 1, -1 do
            if count >= Persistence.squadCap then break end
            encounters[order[index]], count, kept = true, count + 1, kept + 1
        end
        local chosen = {}
        for index, key in pairs(keys) do
            if encounters[key] == true then chosen[index] = key end
        end
        encounters = chosen
    end
    local result = {}
    for key, value in pairs(snapshot) do result[key] = value end
    result.records, result.operations, result.operationOrder = {}, {}, {}
    local retained = {}
    for index, record in ipairs(snapshot.records or {}) do
        if allowed[actorGroup(record)] or encounters[index] ~= nil then
            result.records[#result.records + 1] = record
            retained[record.uid] = true
        end
    end
    result.operations, result.operationOrder = Persistence.filteredOperations(snapshot, retained, owned)
    Persistence.metrics = { squadCap = Persistence.squadCap, retainedSquads = squads,
        retainedGroups = count, retainedEncounters = kept, retainedResidents = residents, retainedActors = #result.records,
        sessionActors = #(snapshot.records or {}) - #result.records }
    return result
end

function Persistence.load()
    local state, stateError = storage()
    if state == nil then return nil, stateError end
    if state.schema == nil then
        state.schema = Persistence.SCHEMA
        state.snapshot = { records = {}, operations = {}, sequence = 0 }
        state.savedAtMs = nowMs()
        Persistence.dirty = true
    elseif state.schema ~= Persistence.SCHEMA then
        return nil, "persistence_schema_unsupported:" .. tostring(state.schema)
    end
    if type(state.snapshot) ~= "table" then return nil, "persistence_snapshot_invalid" end
    local ok, result = pcall(function() return copy(Persistence.forSave(state.snapshot)) end)
    if not ok then return nil, "persistence_copy_failed:" .. tostring(result) end
    return result
end

function Persistence.save(snapshot, owned)
    if type(snapshot) ~= "table" or type(snapshot.records) ~= "table"
            or type(snapshot.operations) ~= "table" then
        return false
    end
    local state = storage()
    if state == nil then return false end
    local ok, result
    if owned == true then
        ok, result = pcall(Persistence.forSave, snapshot, true)
    else
        ok, result = pcall(function() return copy(Persistence.forSave(snapshot)) end)
    end
    if not ok then return false end
    state.schema = Persistence.SCHEMA
    state.snapshot = result
    state.savedAtMs = nowMs()
    Persistence.dirty = true
    return true
end

function Persistence.bucket(name, defaults)
    if type(name) ~= "string" or name == "" then return nil, "persistence_bucket_invalid" end
    local state, stateError = storage()
    if state == nil then return nil, stateError end
    state.stores = type(state.stores) == "table" and state.stores or {}
    if type(state.stores[name]) ~= "table" then
        state.stores[name] = type(defaults) == "table" and defaults or {}
        Persistence.dirty = true
    end
    return state.stores[name]
end

function Persistence.touch()
    local state = storage()
    if state == nil then return false end
    state.savedAtMs = nowMs()
    Persistence.dirty = true
    return true
end

function Persistence.flush()
    if not Persistence.dirty then return true, false end

    if type(Persistence.adapters.transmit) == "function" then
        local ok, result = pcall(Persistence.adapters.transmit, Persistence.TAG)
        if not ok or result == false then
            return false, "persistence_transmit_failed"
        end
    end
    Persistence.dirty = false
    return true, true
end

function Persistence.reset()
    Persistence.adapters = {}
    Persistence.squadCap = 3
    Persistence.keepEncounters = false
    Persistence.storage = nil
    Persistence.dirty = false
end

return Persistence
