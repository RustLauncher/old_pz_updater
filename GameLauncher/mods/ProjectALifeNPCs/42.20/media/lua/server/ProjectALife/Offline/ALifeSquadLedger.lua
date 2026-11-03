ProjectALife = ProjectALife or {}

local Ledger = {
    TAG = "ProjectALife.Squads.v1",
    SCHEMA = 1,
    adapters = {},
    storage = nil,
    dirty = false,
    settings = {
        maximum = 24,
        logMaximum = 40,
        membersMaximum = 8,
    },
    sequence = 0,
    metrics = { created = 0, removed = 0, rejected = 0 },
}
ProjectALife.SquadLedger = Ledger

local function nowMs()
    if type(Ledger.adapters.nowMs) == "function" then return Ledger.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function copy(value, depth)
    depth = depth or 0
    if type(value) ~= "table" or depth > 8 then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item, depth + 1) end
    return result
end

local function storage()
    if Ledger.storage ~= nil then return Ledger.storage end
    local result
    if type(Ledger.adapters.getOrCreate) == "function" then
        result = Ledger.adapters.getOrCreate(Ledger.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        result = ModData.getOrCreate(Ledger.TAG)
    end
    if type(result) ~= "table" then return nil, "mod_data_unavailable" end
    if result.schema == nil then
        result.schema = Ledger.SCHEMA
        result.squads = {}
        result.order = {}
        result.log = {}
        result.reinforcements = {}
        result.sequence = 0
        Ledger.dirty = true
    elseif result.schema ~= Ledger.SCHEMA then
        return nil, "ledger_schema_unsupported:" .. tostring(result.schema)
    end
    result.squads = result.squads or {}
    result.order = result.order or {}
    result.log = result.log or {}
    result.reinforcements = result.reinforcements or {}

    if Ledger.adapters.maximum ~= nil then
        local kept, count = {}, 0
        local restoreMaximum = math.max(0, math.min(Ledger.settings.maximum,
            math.floor(tonumber(Ledger.adapters.restoreMaximum) or Ledger.settings.maximum)))
        local retained = {}
        for index = #result.order, 1, -1 do
            local id = result.order[index]
            local squad = result.squads[id]
            if squad and squad.state ~= "wiped" and count < restoreMaximum then
                retained[id], count = true, count + 1
            else result.squads[id] = nil; Ledger.dirty = true end
        end
        for _, id in ipairs(result.order) do
            if retained[id] then kept[#kept + 1] = id end
        end
        result.order = kept
    end
    Ledger.storage = result
    return result
end

function Ledger.configure(adapters)
    Ledger.adapters = adapters or {}
    if Ledger.adapters.maximum ~= nil then
        Ledger.settings.maximum = math.max(0, math.min(500, math.floor(tonumber(Ledger.adapters.maximum) or 3)))
    end
    Ledger.storage = nil
    Ledger.dirty = false
    return true
end

function Ledger.reset()
    local state = storage()
    if state == nil then return false end
    state.squads, state.order, state.log, state.reinforcements = {}, {}, {}, {}
    state.sequence = 0
    state.townSeeds = nil
    Ledger.dirty = true
    return true
end

function Ledger.townSeedCount(townId, increment)
    local state = storage()
    if state == nil then return nil end
    if type(state.townSeeds) ~= "table" then
        state.townSeeds = {}
        for _, squad in pairs(state.squads) do
            local home = squad.homeNodeId
            if home ~= nil then state.townSeeds[home] = (state.townSeeds[home] or 0) + 1 end
        end
        Ledger.dirty = true
    end
    local count = tonumber(state.townSeeds[townId]) or 0
    if increment then
        count = count + 1
        state.townSeeds[townId] = count
        Ledger.dirty = true
    end
    return count
end

function Ledger.record(kind, fields)
    local state = storage()
    if state == nil then return false end
    local entry = { kind = tostring(kind), atMs = nowMs() }
    for key, value in pairs(fields or {}) do entry[key] = copy(value) end
    table.insert(state.log, 1, entry)
    while #state.log > Ledger.settings.logMaximum do table.remove(state.log) end
    Ledger.dirty = true
    return true
end

function Ledger.log()
    local state = storage()
    return state and copy(state.log) or {}
end

function Ledger.count()
    local state = storage()
    if state == nil then return 0 end
    local count = 0
    for _, id in ipairs(state.order) do
        local squad = state.squads[id]
        if squad ~= nil and squad.state ~= "wiped" then count = count + 1 end
    end
    return count
end

function Ledger.create(fields)
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("squad_record") then return nil, "cleanup_locked" end
    local state, stateError = storage()
    if state == nil then return nil, stateError end
    if type(fields) ~= "table" then return nil, "squad_fields_invalid" end

    local maximum = Ledger.settings.maximum
    if Ledger.count() >= maximum then
        Ledger.metrics.rejected = Ledger.metrics.rejected + 1
        return nil, "squad_cap_reached"
    end
    state.sequence = (state.sequence or 0) + 1
    local id = "squad:" .. tostring(state.sequence)
    local members = {}
    for index, member in ipairs(fields.members or {}) do
        if index > Ledger.settings.membersMaximum then break end
        members[#members + 1] = { profileId = tostring(member.profileId or "?"),
            health = tonumber(member.health) or 100, identitySeed = member.identitySeed,
            shellState = member.shellState and copy(member.shellState),
            gear = member.gear and copy(member.gear), name = member.name }
    end
    local squad = {
        id = id,
        revision = 1,
        name = tostring(fields.name or id),
        factionId = fields.factionId,
        partyKind = fields.partyKind,
        homeOutpostId = fields.homeOutpostId,
        state = "offline",
        x = tonumber(fields.x) or 0,
        y = tonumber(fields.y) or 0,
        nodeId = fields.nodeId,
        homeNodeId = fields.homeNodeId,
        route = {},
        task = fields.task and copy(fields.task) or { kind = "idle", label = "idle" },
        members = members,
        supplies = tonumber(fields.supplies) or 35,
        morale = tonumber(fields.morale) or 0.65,
        foundedHours = tonumber(fields.foundedHours) or 0,
        decisionDueHours = tonumber(fields.decisionDueHours) or 0,
    }
    state.squads[id] = squad
    state.order[#state.order + 1] = id
    Ledger.dirty = true
    Ledger.metrics.created = Ledger.metrics.created + 1
    Ledger.record("founded", { squad = id, name = squad.name, x = squad.x, y = squad.y })
    return copy(squad)
end

function Ledger.adopt(fields, uids)
    if type(fields) ~= "table" or type(uids) ~= "table" or #uids == 0 then return nil, "adopt_invalid" end
    if type(fields.members) ~= "table" or #fields.members ~= #uids then return nil, "adopt_members_mismatch" end
    if #uids > Ledger.settings.membersMaximum then return nil, "adopt_too_many" end
    local created, createError = Ledger.create(fields)
    if created == nil then return nil, createError end
    local state = storage()
    local squad = state.squads[created.id]
    squad.state = "rendered"
    squad.renderedUids = {}
    for index, uid in ipairs(uids) do squad.renderedUids[index] = tostring(uid) end
    squad.adoptedFrom = fields.adoptedFrom
    squad.adoptedGroupId = fields.adoptedGroupId
    squad.activity = fields.activity and copy(fields.activity) or nil
    squad.needs = fields.needs and copy(fields.needs) or nil
    squad.lastSimulatedHours = tonumber(fields.lastSimulatedHours)
    Ledger.record("adopted", { squad = squad.id, from = fields.adoptedFrom, group = fields.adoptedGroupId })
    return copy(squad)
end

function Ledger.read(id)
    local state = storage()
    if state == nil then return nil end
    local squad = state.squads[id]
    return squad and copy(squad) or nil
end

function Ledger.list(simulationOnly)
    local state = storage()
    if state == nil then return {} end
    local result = {}
    for _, id in ipairs(state.order) do
        local squad = state.squads[id]
        if squad ~= nil then
            if simulationOnly then
                local brief = {}
                for key, value in pairs(squad) do
                    if key ~= "members" then brief[key] = copy(value) end
                end
                brief.members = {}
                for _, member in ipairs(squad.members or {}) do
                    brief.members[#brief.members + 1] = { profileId = member.profileId, health = member.health }
                end
                result[#result + 1] = brief
            else result[#result + 1] = copy(squad) end
        end
    end
    return result
end

function Ledger.eachLive(visit)
    local state = storage()
    if state == nil or type(visit) ~= "function" then return 0 end
    local order, squads, visited = state.order, state.squads, 0
    for index = 1, #order do
        local squad = squads[order[index]]
        if squad ~= nil and squad.state ~= "wiped" then
            visited = visited + 1
            if visit(squad) == false then break end
        end
    end
    return visited
end

function Ledger.peek(id)
    local state = storage()
    if state == nil or id == nil then return nil end
    return state.squads[id]
end

function Ledger.suffixFor(sequence)
    local n = math.max(1, math.floor(tonumber(sequence) or 1)) - 1
    local letter = string.char(65 + n % 26)
    local round = math.floor(n / 26)
    if round == 0 then return letter end
    return letter .. tostring(round + 1)
end

function Ledger.nextSuffix()
    local state = storage()
    return Ledger.suffixFor((state and tonumber(state.sequence) or 0) + 1)
end

function Ledger.ids()
    local state = storage()
    local result = {}
    if state ~= nil then
        for _, id in ipairs(state.order) do
            if state.squads[id] ~= nil then result[#result + 1] = id end
        end
    end
    return result
end

function Ledger.liveIds()
    local state = storage()
    local result = {}
    if state ~= nil then
        for _, id in ipairs(state.order) do
            local squad = state.squads[id]
            if squad ~= nil and squad.state ~= "wiped" then result[#result + 1] = squad.id end
        end
    end
    return result
end

function Ledger.briefs()
    local state, result = storage(), {}
    if state == nil then return result end
    for _, id in ipairs(state.order) do
        local q = state.squads[id]
        if q ~= nil then
            local profiles = {}
            for _, member in ipairs(q.members or {}) do profiles[#profiles + 1] = member.profileId end
            result[#result + 1] = { id = id, revision = q.revision, name = q.name,
                factionId = q.factionId, profileIds = profiles,
                x = q.x, y = q.y, state = q.state, memberCount = #(q.members or {}),
                moving = type(q.route) == "table" and #q.route > 0 or nil,
                legStartedHours = q.legStartedHours, lastSimulatedHours = q.lastSimulatedHours,
                renderedUids = copy(q.renderedUids),
                stagePending = q.stagePending ~= nil and true or nil,
                releasePending = q.releasePending ~= nil and true or nil }
        end
    end
    return result
end

function Ledger.update(id, expectedRevision, mutation, noResult)
    local state = storage()
    if state == nil then return nil, "mod_data_unavailable" end
    local squad = state.squads[id]
    if squad == nil then return nil, "squad_not_found" end
    if squad.revision ~= expectedRevision then
        Ledger.metrics.rejected = Ledger.metrics.rejected + 1
        return nil, "squad_revision_conflict"
    end
    local nextSquad = copy(squad)
    local ok, err = pcall(mutation, nextSquad)
    if not ok then return nil, "squad_mutation_failed:" .. tostring(err) end
    nextSquad.revision = squad.revision + 1
    state.squads[id] = nextSquad
    Ledger.dirty = true
    if noResult == true then return true end
    return copy(nextSquad)
end

function Ledger.remove(id, expectedRevision, reason)
    local state = storage()
    if state == nil then return false, "mod_data_unavailable" end
    local squad = state.squads[id]
    if squad == nil then return false, "squad_not_found" end
    if squad.revision ~= expectedRevision then
        Ledger.metrics.rejected = Ledger.metrics.rejected + 1
        return false, "squad_revision_conflict"
    end
    state.squads[id] = nil
    for index, held in ipairs(state.order) do
        if held == id then table.remove(state.order, index) break end
    end
    Ledger.dirty = true
    Ledger.metrics.removed = Ledger.metrics.removed + 1
    Ledger.record("removed", { squad = id, reason = reason })
    return true
end

function Ledger.requestReinforcement(outpostId, nodeId, priority, factionId)
    local state = storage()
    if state == nil then return false end
    state.reinforcements[#state.reinforcements + 1] = {
        outpostId = tostring(outpostId), nodeId = tostring(nodeId),
        priority = tonumber(priority) or 1, atMs = nowMs(), factionId = factionId }
    Ledger.dirty = true
    return true
end

function Ledger.takeReinforcement(eligible)
    local state = storage()
    if state == nil or #state.reinforcements == 0 then return nil end
    local bestIndex, best
    for index, request in ipairs(state.reinforcements) do
        if (best == nil or request.priority > best.priority)
                and (eligible == nil or eligible(request)) then
            bestIndex, best = index, request
        end
    end
    if bestIndex == nil then return nil end
    table.remove(state.reinforcements, bestIndex)
    Ledger.dirty = true
    return best
end

function Ledger.pendingReinforcements()
    local state = storage()
    return state and #state.reinforcements or 0
end

function Ledger.flush()
    if not Ledger.dirty then return true, false end
    if type(Ledger.adapters.transmit) == "function" then
        local ok, result = pcall(Ledger.adapters.transmit, Ledger.TAG)
        if not ok or result == false then return false, "ledger_transmit_failed" end
    end
    Ledger.dirty = false
    return true, true
end

return Ledger
