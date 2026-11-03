require "ProjectALife/Activities/ALifeActivityCatalog"
require "ProjectALife/Activities/ALifeActivityPlanner"
require "ProjectALife/Offline/ALifeSquadLedger"
require "ProjectALife/Activities/ALifeFishing"
require "ProjectALife/Activities/ALifeHunting"
require "ProjectALife/Activities/ALifeHavens"
require "ProjectALife/Activities/ALifeActivitySwitch"
require "ProjectALife/Activities/ALifeCampLife"
require "ProjectALife/Core/ALifePlayerLocator"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.ActivityCatalog
local Planner = ProjectALife.ActivityPlanner
local Ledger = ProjectALife.SquadLedger
local Fish = ProjectALife.ActivityFishing
local Hunt = ProjectALife.ActivityHunting

local Service = {
    settings = {
        intervalMs = 15000,
        scanMs = 3000,
        groupsPerCall = 2,
        sliceMs = 1,

        sceneReach = 4,

        adoptSupplies = 50,

        campReach = 150,
        campFireMinutes = 600,

        nextBias = 3,
    },
    state = { groups = {}, order = {}, cursor = 1, scanAtMs = nil, lastMs = {}, refusalSaid = {} },
    metrics = { scans = 0, groups = 0, serviced = 0, events = 0, staleEvents = 0, transitions = 0,
        holds = 0, adopted = 0, adoptRefused = 0, adoptRefusedBy = {}, healed = 0, carsReleased = 0,
        camps = 0, campRefused = 0, renewed = 0, busy = 0 },
    adapters = {},
    pending = nil,
}
ProjectALife.ActivityService = Service

Service.RINGS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

function Service.enabled()
    return Catalog.enabled()
end

function Service.registry()
    return Service.adapters.registry or ProjectALife.ActorRegistry
end

function Service.nowMs()
    if type(Service.adapters.nowMs) == "function" then return Service.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Service.worldHours()
    if type(Service.adapters.worldHours) == "function" then return Service.adapters.worldHours() end
    if type(getGameTime) ~= "function" then return 0 end
    local time = getGameTime()
    if time == nil or type(time.getWorldAgeHours) ~= "function" then return 0 end
    return tonumber(time:getWorldAgeHours()) or 0
end

function Service.isNight()
    if type(Service.adapters.isNight) == "function" then return Service.adapters.isNight() == true end
    local cycle = ProjectALife.DayCycle
    return cycle ~= nil and type(cycle.isNight) == "function" and cycle.isNight() == true
end

function Service.authoritative()
    return not (type(isClient) == "function" and isClient() == true)
end

function Service.copy(value, depth)
    depth = depth or 0
    if type(value) ~= "table" or depth > 6 then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Service.copy(item, depth + 1) end
    return result
end

function Service.emit(category, fields)
    local telemetry = ProjectALife.Telemetry
    if telemetry ~= nil and type(telemetry.emit) == "function" then pcall(telemetry.emit, category, fields) end
end

function Service.scanRecord(record)
    local scanning = Service.state.scanning
    local memory = record.memory
    if record.lifecycle == "dead" or type(memory) ~= "table" or memory.groupId == nil then return end
    local id = tostring(memory.groupId)
    local group = scanning.byId[id]
    if group == nil then
        group = { id = id, uids = {} }
        scanning.byId[id] = group
    end
    group.uids[#group.uids + 1] = record.uid
    local switch = ProjectALife.ActivitySwitch
    if switch ~= nil and switch.rules[memory.encounterKind] ~= nil then group.switchable = true end
    if memory.activityId == "hold" then
        group.held = (group.held or 0) + 1
    elseif type(memory.activityEvent) == "table" or type(memory.activityId) == "string" then
        group.wanted = true
    end
end

function Service.scan()
    local registry = Service.registry()
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    Service.state.scanning = { byId = {} }
    registry.each(Service.scanRecord)
    local found = Service.state.scanning.byId
    Service.state.scanning = nil
    local groups, order, last = {}, {}, {}
    for id, group in pairs(found) do
        if (group.wanted == true or (group.held or 0) > 0)
                and ((group.held or 0) < #group.uids or group.switchable == true) then
            groups[id] = group
            order[#order + 1] = id
        end
    end
    table.sort(order)
    for _, id in ipairs(order) do last[id] = Service.state.lastMs[id] end
    Service.state.groups, Service.state.order, Service.state.lastMs = groups, order, last
    for id in pairs(Service.state.shore or {}) do
        if groups[id] == nil then Service.state.shore[id] = nil end
    end
    Service.metrics.scans = Service.metrics.scans + 1
    Service.metrics.groups = #order
    return #order
end

function Service.tick(now)
    if not Service.enabled() or not Service.authoritative() then return 0 end
    now = tonumber(now) or Service.nowMs()
    local state, settings = Service.state, Service.settings
    if state.scanAtMs == nil or now >= state.scanAtMs then
        state.scanAtMs = now + settings.scanMs
        Service.scan()
    end
    local count = #state.order
    local started, done, work = Service.nowMs(), 0, ProjectALife.Havens.tick()
    if count == 0 then return work end
    for _ = 1, count do
        if state.cursor > count then state.cursor = 1 end
        local id = state.order[state.cursor]
        state.cursor = state.cursor + 1
        local last = state.lastMs[id]
        if last == nil or now - last >= settings.intervalMs then
            state.lastMs[id] = now
            work = work + Service.serviceGroup(id, now)
            done = done + 1
            if done >= settings.groupsPerCall or Service.nowMs() - started >= settings.sliceMs then break end
        end
    end
    return work
end

function Service.byIndex(a, b)
    local left = tonumber(a.memory.groupIndex) or 99
    local right = tonumber(b.memory.groupIndex) or 99
    if left ~= right then return left < right end
    return tostring(a.uid) < tostring(b.uid)
end

function Service.membersOf(group)
    local registry, members = Service.registry(), {}
    for _, uid in ipairs(group.uids) do
        local record = registry.read(uid)
        if record ~= nil and record.lifecycle ~= "dead" and type(record.memory) == "table"
                and tostring(record.memory.groupId) == group.id then
            members[#members + 1] = record
        end
    end
    table.sort(members, Service.byIndex)
    return members
end

function Service.squadOf(groupId, members)
    local squadId = members[1].memory.squadId
    if squadId ~= nil then
        local squad = Ledger.peek(squadId)
        if squad ~= nil and squad.state ~= "wiped" and (squad.adoptedFrom ~= nil
                or (type(squad.activity) == "table" and (squad.activity.id == "fish" or squad.activity.id == "hunt"))) then return squad, false end
        return nil, false
    end
    local found = nil
    Service.state.healFor = groupId
    Ledger.eachLive(function(candidate)
        if candidate.adoptedGroupId == Service.state.healFor and candidate.state == "rendered" then
            found = candidate
            return false
        end
        return true
    end)
    return found, found ~= nil
end

function Service.squadOwns(squad, id, members)
    if squad.state ~= "rendered" or tostring(squad.adoptedGroupId or squad.id) ~= id then return false end
    local owned = {}
    for _, uid in ipairs(squad.renderedUids or {}) do owned[tostring(uid)] = true end
    for _, record in ipairs(members) do
        if owned[tostring(record.uid)] ~= true then return false end
    end
    return true
end

function Service.currentOf(squad, leader)
    if squad ~= nil and type(squad.activity) == "table" then return squad.activity end
    local memory = leader.memory
    if type(memory.activityState) == "table" and type(memory.activityState.activity) == "table" then
        return memory.activityState.activity
    end
    local encounters = ProjectALife.Encounters
    local definition = encounters ~= nil and encounters.get(memory.encounterKind) or nil
    if definition == nil or type(definition.activity) ~= "string" then return nil end
    return { id = definition.activity, seq = tonumber(memory.activitySeq) or 0 }
end

function Service.eventOf(members, current)
    local seq = tonumber(current.seq) or 0
    for _, record in ipairs(members) do
        local event = record.memory.activityEvent
        if type(event) == "table" and type(event.kind) == "string" then
            if tonumber(event.seq) == seq then return event.kind end
            Service.metrics.staleEvents = Service.metrics.staleEvents + 1
        end
    end
    return nil
end

function Service.calm(members)
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.groupAlarmed) == "function" and first.groupAlarmed(members) == true then
        return false
    end
    for _, record in ipairs(members) do
        local activity = record.activity
        if record.lifecycle ~= "active" or activity == "combat" or activity == "attacking"
                or activity == "fleeing" or activity == "warning" then
            return false
        end
    end
    return true
end

function Service.camping(members)
    for _, record in ipairs(members) do
        if record.memory.nightCamp == true then return true end
    end
    return false
end

function Service.health(members)
    local rows = {}
    for index, record in ipairs(members) do
        local state = record.memory.shellState
        local health = 100
        if type(state) == "table" and tonumber(state.health) ~= nil then
            health = tonumber(state.health) * 100 / math.max(1, tonumber(state.maximumHealth) or 100)
        end
        rows[index] = { health = health }
    end
    return Planner.averageHealth(rows)
end

function Service.serviceGroup(id, now)
    local group = Service.state.groups[id]
    if group == nil then return 0 end
    local members = Service.membersOf(group)
    if #members == 0 then return 0 end
    Service.metrics.serviced = Service.metrics.serviced + 1
    for _, record in ipairs(members) do
        if record.memory.activityId == "hold" then
            if not Service.calm(members) then return 0 end
            local held = { id = "hold", seq = record.memory.activitySeq }
            local switch = ProjectALife.ActivitySwitch
            if switch ~= nil and switch.due(id, members, Service.worldHours()) then
                local moved = Service.leaveEntry(id, members, held, switch.plan(members))
                if moved == 1 then return 1 end
            end
            return Service.stampHold(members, held) and 1 or 0
        end
    end
    ProjectALife.Havens.consider(id, members)
    local squad, heal = Service.squadOf(id, members)
    if squad ~= nil and not Service.squadOwns(squad, id, members) then return 0 end
    if squad == nil and members[1].memory.squadId ~= nil then return 0 end
    local current = Service.currentOf(squad, members[1])
    if current == nil or current.id == "hold" then return 0 end
    if current.id == "hunt" and current.hunting == nil then return Service.startHunting(id, members, squad, current) end
    if current.id == "hunt" and Hunt.finished(current.hunting, members, Service.worldHours()) then
        return Service.keep(id, members, squad, current, "done")
    end
    if current.id == "fish" and current.fishing == nil then return Service.startFishing(id, members, squad, current) end
    if current.id == "fish" then
        local stop = Fish.finished(current.fishing, members, Service.worldHours())
        if not stop then
            for _, record in ipairs(members) do
                if current.fishing.work[tostring(record.uid)] == nil then stop = true; break end
            end
        end
        if stop then return Service.keep(id, members, squad, current, "done") end
    end
    local chorus = Catalog.activities[current.id]
    if chorus ~= nil and chorus.chore ~= nil then
        if current.chore == nil then return Service.startChore(id, members, squad, current) end
        if Service.worldHours() >= (tonumber(current.untilHours) or math.huge) then
            return Service.leaveEntry(id, members, current)
        end
    end
    if squad ~= nil or type(members[1].memory.activityState) == "table" then
        for _, record in ipairs(members) do
            if not Service.memberSynced(record, current, squad) then heal = true end
        end
    end
    if heal then
        if not Service.calm(members) then return 0 end
        local hours = Service.worldHours()
        local needs = Service.needsNow(squad, members[1], hours, #members)
        if not Service.writeMembers(members, current, squad, needs, false, true, hours) then return 0 end
        Service.metrics.healed = Service.metrics.healed + 1
        if current.id == "camp" and Service.isNight() then Service.makeCamp(members, current) end
        return 1
    end
    local event = Service.eventOf(members, current)
    if event ~= nil then Service.metrics.events = Service.metrics.events + 1 end
    if event == "done" and current.id == "return_base" then ProjectALife.Havens.visited(members) end
    local row = Catalog.activities[current.id]
    if row ~= nil and row.entry == true then
        if event ~= "done" or row.hold == true then return 0 end
        return Service.leaveEntry(id, members, current)
    end
    if row == nil then return 0 end
    return Service.keep(id, members, squad, current, event)
end

function Service.nextOf(memory)
    local encounters = ProjectALife.Encounters
    local definition = encounters ~= nil and encounters.get(memory.encounterKind) or nil
    if definition == nil or type(definition.activityNext) ~= "string" then return nil, definition end
    return definition.activityNext, definition
end

function Service.entryDepot(leader, definition)
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.sceneNear) ~= "function" or type(kit.repairCar) ~= "function" then return nil end
    if definition == nil or definition.scene ~= "brokenCar" then return nil end
    local anchor = leader.memory.stanceAnchor
    if type(anchor) ~= "table" then anchor = leader.memory.spawnOrigin end
    if type(anchor) ~= "table" or tonumber(anchor.x) == nil or tonumber(anchor.y) == nil then return nil end
    local key = kit.sceneNear("brokenCar", tonumber(anchor.x), tonumber(anchor.y), Service.settings.sceneReach)
    if key == nil then return nil end
    local ok, _, depot = kit.repairCar(key, {
        drivable = Catalog.setting("FixedCarDrivable", true) == true,
        fuelPercent = tonumber(Catalog.setting("FixedCarFuelPercent", 15)) or 15,
    })
    if not ok then return nil end
    Service.metrics.carsReleased = Service.metrics.carsReleased + 1
    return depot
end

function Service.stampHold(members, current)
    local seq = tonumber(current.seq) or 0
    if current.id ~= "hold" then seq = seq + 1 end
    Service.pending = { hold = true, seq = seq }
    local registry = Service.registry()
    local complete = true
    for _, record in ipairs(members) do
        if record.memory.activityId ~= "hold" or record.memory.activitySeq ~= seq then
            if registry.update(record.uid, record.revision, Service.holdMutation) == nil then complete = false end
        end
    end
    Service.pending = nil
    if complete then Service.metrics.holds = Service.metrics.holds + 1 end
    return complete
end

function Service.holdMutation(fresh)
    local memory = fresh.memory or {}
    fresh.memory = memory
    memory.activityId, memory.activitySeq, memory.activityEvent = "hold", Service.pending.seq, nil
    local hold = memory.activityHold
    if type(hold) ~= "table" or hold.seq ~= Service.pending.seq then
        memory.activityHold = { seq = Service.pending.seq, since = Service.worldHours() }
    end
end

function Service.leaveEntry(id, members, current, forced)
    if not Service.calm(members) then
        Service.metrics.busy = Service.metrics.busy + 1
        return 0
    end
    local leader = members[1]
    local nextId, definition = Service.nextOf(leader.memory)
    if forced ~= nil then nextId, definition = forced.to, nil end
    local chance = tonumber(Catalog.setting("SwitchChance", 70)) or 70
    if forced == nil and (nextId == nil or Planner.stableRoll(id .. ":switch") * 100 >= chance) then
        return Service.stampHold(members, current) and 1 or 0
    end
    local hours = Service.worldHours()
    local night = Service.isNight()
    local needs = Planner.needsOf({ supplies = Service.settings.adoptSupplies })
    local ctx = Service.loadedContext(id, members, current, needs, hours, night, "done")
    ctx.bias = { [nextId] = Service.settings.nextBias }
    local first = Planner.decide(ctx) or nextId
    local depot = forced == nil and Service.entryDepot(leader, definition) or nil
    local activity = Service.newActivity(first, current, hours, "done", depot)
    local squad = Service.adopt(id, members, activity, needs, hours)
    if not Service.writeMembers(members, activity, squad, needs, true, nil, hours) then return 0 end
    if forced ~= nil and type(forced.after) == "function" then forced.after() end
    Service.metrics.transitions = Service.metrics.transitions + 1
    Service.emit("activity_started", { group = id, activity = first, from = current.id,
        squad = squad ~= nil and squad.id or "none" })
    if first == "camp" then Service.makeCamp(members, activity) end
    return 1
end

function Service.newActivity(id, previous, hours, reason, depot)
    local row = Catalog.activities[id] or {}
    local span = type(row.duration) == "table" and row.duration or { 1, 2 }
    local seq = (tonumber(previous and previous.seq) or 0) + 1
    local length = span[1] + (span[2] - span[1]) * Planner.stableRoll(id .. ":" .. seq .. ":" .. tostring(hours))
    local from = nil
    if type(previous) == "table" then from = previous.id end
    return {
        id = id, phase = "work", seq = seq, startedHours = hours, untilHours = hours + length,
        progress = 0, yields = { food = 0, water = 0, ammo = 0, meds = 0 },
        from = from, reason = reason, depot = Service.copy(depot),
    }
end

function Service.adoptedCount()
    local count = 0
    Ledger.eachLive(function(squad)
        if squad.adoptedFrom ~= nil then count = count + 1 end
        return true
    end)
    return count
end

function Service.refuse(reason)
    local metrics = Service.metrics
    metrics.adoptRefused = metrics.adoptRefused + 1
    metrics.adoptRefusedBy[reason] = (metrics.adoptRefusedBy[reason] or 0) + 1
    if Service.state.refusalSaid[reason] ~= true then
        Service.state.refusalSaid[reason] = true
        Service.emit("activity_adopt_refused", { reason = reason })
    end
    return nil
end

function Service.memberRow(index, record, groupId)
    local memory = record.memory
    local state = type(memory.shellState) == "table" and Service.copy(memory.shellState) or nil
    local health = 100
    if state ~= nil and tonumber(state.health) ~= nil then
        health = tonumber(state.health) * 100 / math.max(1, tonumber(state.maximumHealth) or 100)
    end
    return { profileId = tostring(record.profileId or "?"), health = health,
        identitySeed = memory.identitySeed or record.uid or (groupId .. ":member:" .. index),
        shellState = state, name = memory.name }
end

function Service.adopt(groupId, members, activity, needs, hours)
    local cap = math.floor(tonumber(Catalog.setting("AdoptCap", 6)) or 6)
    if Service.adoptedCount() >= cap then return Service.refuse("adopt_cap") end
    if #members > Ledger.settings.membersMaximum then return Service.refuse("too_many") end
    local leader = members[1]
    local rows, uids = {}, {}
    for index, record in ipairs(members) do
        rows[index] = Service.memberRow(index, record, groupId)
        uids[index] = record.uid
    end
    local at = type(leader.worldPosition) == "table" and leader.worldPosition or { x = 0, y = 0 }
    local graph = ProjectALife.RoadGraph
    local node = nil
    if graph ~= nil and graph.built == true and type(graph.nearest) == "function" then node = graph.nearest(at.x, at.y) end
    local squad, reason = Ledger.adopt({
        name = Service.squadName(leader), factionId = leader.factionId,
        x = tonumber(at.x) or 0, y = tonumber(at.y) or 0, nodeId = node, homeNodeId = node,
        members = rows, task = Service.taskFor(activity, node, hours),
        supplies = math.min(needs.food, needs.water), foundedHours = hours,
        decisionDueHours = activity.untilHours, activity = activity, needs = needs,
        adoptedFrom = leader.memory.encounterKind, adoptedGroupId = groupId, lastSimulatedHours = hours,
    }, uids)
    if squad == nil then
        if reason == "squad_cap_reached" then return Service.refuse("ledger_full") end
        return Service.refuse(tostring(reason))
    end
    Service.metrics.adopted = Service.metrics.adopted + 1
    return squad
end

function Service.squadName(leader)
    local catalog = ProjectALife.Catalog
    local faction = nil
    if catalog ~= nil and type(catalog.faction) == "function" then faction = catalog.faction(leader.factionId) end
    local name = type(faction) == "table" and type(faction.general) == "table" and faction.general.name or nil
    if type(name) ~= "string" or name == "" then name = tostring(leader.factionId or "Crew") end
    return name .. " " .. Ledger.nextSuffix()
end

function Service.taskFor(activity, node, hours)
    local row = Catalog.activities[activity.id] or {}
    return { kind = row.task or "rest", label = activity.id, dest = node, activityId = activity.id,
        activityRendered = true,
        assignedHours = hours, untilHours = activity.untilHours }
end

function Service.partyMemory(memory, activity, area)
    memory.behavior, memory.adminMode, memory.behaviorProfile = "scavenge", "scavenge", "scavenger"
    local overrides = {}
    if type(memory.moduleOverrides) == "table" then
        for key, value in pairs(memory.moduleOverrides) do overrides[key] = value end
    end
    overrides.scavenge = true
    memory.moduleOverrides = overrides
    memory.stance, memory.stanceRole, memory.stanceAnchor, memory.stanceHeading = nil, nil, nil, nil
    memory.stancePost, memory.stancePhase, memory.stancePostUntilMs, memory.stanceAwareness = nil, nil, nil, nil
    memory.holdPost = nil
    memory.scavengeArea = Service.copy(area)
    memory.supplyDepot = Service.copy(activity.depot)
    memory.lootPhase, memory.lootRestUntilMs, memory.lootBuildings = nil, nil, nil
end

function Service.memberMutation(fresh)
    local job = Service.pending
    local memory = fresh.memory or {}
    fresh.memory = memory
    memory.activityId, memory.activitySeq, memory.activityEvent = job.activity.id, job.activity.seq, nil
    if job.squad ~= nil then
        memory.squadId, memory.persistent, memory.activityState = job.squad.id, true, nil
    elseif job.state ~= nil then
        memory.activityState = Service.copy(job.state)
    end
    if job.activity.id == "fish" or job.activity.id == "hunt" then
        memory.activityState = { activity = Service.copy(job.activity), needs = Service.copy(job.needs), needsHours = job.hours }
    end
    if job.rebase then Service.partyMemory(memory, job.activity, job.area) end
end

function Service.areaNear(leader)
    local graph = ProjectALife.RoadGraph
    local at = leader.worldPosition
    if graph == nil or graph.built ~= true or type(graph.nearest) ~= "function" or type(at) ~= "table" then return nil end
    local id = graph.nearest(at.x, at.y, "town")
    local node = id ~= nil and type(graph.nodes) == "table" and graph.nodes[id] or nil
    if node == nil then return nil end
    return { x = node.x, y = node.y, z = 0 }
end

function Service.memberSynced(record, activity, squad)
    local memory = record.memory
    if memory.activityId ~= activity.id or memory.activitySeq ~= activity.seq then return false end
    if activity.id == "fish" then
        local state = type(memory.activityState) == "table" and memory.activityState.activity or nil
        if type(state) ~= "table" or state.seq ~= activity.seq or type(state.fishing) ~= "table"
                or type(state.fishing.work) ~= "table" or state.fishing.work[tostring(record.uid)] == nil then return false end
    end
    if activity.id == "hunt" then
        local state = type(memory.activityState) == "table" and memory.activityState.activity or nil
        if type(state) ~= "table" or state.seq ~= activity.seq or type(state.hunting) ~= "table"
                or type(state.hunting.work) ~= "table" or state.hunting.work[tostring(record.uid)] == nil then return false end
    end
    if squad ~= nil then return memory.squadId == squad.id end
    local state = memory.activityState
    return type(state) == "table" and type(state.activity) == "table"
        and state.activity.id == activity.id and state.activity.seq == activity.seq
end

function Service.writeMembers(members, activity, squad, needs, rebase, healing, hours)
    local state = nil
    if squad == nil then
        state = { activity = Service.copy(activity), needs = Service.copy(needs), needsHours = tonumber(hours) or Service.worldHours() }
    end
    Service.pending = { activity = activity, squad = squad, state = state, rebase = rebase == true,
        needs = needs, hours = hours,
        area = rebase == true and Service.areaNear(members[1]) or nil }
    local registry = Service.registry()
    local complete = true
    for _, record in ipairs(members) do
        if healing ~= true or not Service.memberSynced(record, activity, squad) then
            if healing == true then
                local previous = Service.currentOf(nil, record)
                local row = previous ~= nil and Catalog.activities[previous.id] or nil
                Service.pending.rebase = activity.id == "scavenge" or (row ~= nil and row.entry == true)
                Service.pending.area = Service.pending.rebase and Service.areaNear(members[1]) or nil
            end
            if registry.update(record.uid, record.revision, Service.memberMutation) == nil then complete = false end
        end
    end
    Service.pending = nil
    return complete
end

function Service.hourOfDay()
    if type(Service.adapters.hourOfDay) == "function" then return Service.adapters.hourOfDay() end
    return Planner.hourOfDay()
end

function Service.nightActive(id, hours)
    local offline = ProjectALife.OfflineDirector
    if offline == nil or type(offline.restsTonight) ~= "function" then return false end
    return offline.restsTonight({ id = id }, hours, 23) ~= true
end

function Service.loadedContext(id, members, current, needs, hours, night, event)
    local context = {
        loaded = true, needs = needs, hour = Service.hourOfDay(), night = night,
        nightActive = night and Service.nightActive(id, hours), weather = Planner.weather(),
        health = Service.health(members), hours = hours, current = current.id,
        currentSince = current.startedHours, event = event, day = math.floor(hours / 24), seed = id,
    }
    if Fish.enabled() and needs.food < 40 and not night then
        Service.state.shore = Service.state.shore or {}
        local posts, _, search = Fish.scanShore(Service.state.shore[id], members[1].worldPosition, hours)
        Service.state.shore[id] = search
        if #posts > 0 then context.shore, context.habitat = posts, { water = 0 } end
    end
    local home = ProjectALife.Havens.contextFor(members, hours)
    if home ~= nil then
        context.havenId, context.away, context.returnHours, context.atHome = home.havenId, home.away, home.returnHours, home.atHome
        context.homeCovers = home.homeCovers
    end
    if Hunt.liveEnabled() and needs.food < 40 and not night then
        local graph, point = ProjectALife.RoadGraph, members[1].worldPosition
        if graph ~= nil and graph.built == true and type(graph.nearest) == "function" and type(point) == "table" then
            local nodeId = graph.nearest(point.x, point.y)
            local node = nodeId ~= nil and graph.nodes[nodeId] or nil
            if node ~= nil and Hunt.habitatScale(node.habitat) > 0 then
                context.huntHabitat = node.habitat
                context.hunters = #Hunt.loadedHunters(members)
            end
        end
    end
    return context
end

function Service.needsNow(squad, leader, hours, count)
    if squad ~= nil then return Planner.needsOf(squad) end
    local state = leader.memory.activityState
    if type(state) ~= "table" then return Planner.needsOf(nil) end
    local since = tonumber(state.needsHours) or hours
    return Planner.drain(state.needs, count, math.max(0, hours - since), Planner.drainPercent())
end

function Service.keep(id, members, squad, current, event)
    local hours = Service.worldHours()
    local night = Service.isNight()
    local camping = Service.camping(members)
    local row = Catalog.activities[current.id]
    local needs = Service.needsNow(squad, members[1], hours, #members)
    local critical = Planner.critical(needs)
    if current.id == "hunt" then
        for _, need in ipairs(Catalog.NEEDS) do
            if need ~= "food" and needs[need] < Planner.settings.criticalBelow then critical = need; break end
        end
        if critical ~= nil and critical ~= "food" then
            event = "need_critical:" .. critical
        elseif event == "done" or event == "failed" or Hunt.finished(current.hunting, members, hours, needs.food) then
            event = "done"
        else
            return 0
        end
    end
    if current.id == "fish" then
        for _, need in ipairs(Catalog.NEEDS) do
            if need ~= "food" and needs[need] < Planner.settings.criticalBelow then critical = need; break end
        end
        if critical ~= nil and critical ~= "food" then
            event = "need_critical:" .. critical
        elseif event == "done" or event == "failed" or not Fish.enabled() or Fish.finished(current.fishing, members, hours) then
            event = "done"
        elseif Service.calm(members) then
            return Service.fishing(members, squad, current, hours)
        else
            local paused, changed = Service.copy(current), false
            for _, work in pairs(paused.fishing.work) do
                if work.nextHours ~= nil then work.nextHours = nil; changed = true end
            end
            if changed then return Service.commit(members, squad, paused, needs, hours, false) and 1 or 0 end
            return 0
        end
    end
    if event == nil then
        if night and row.night ~= true then
            event = "night"
        elseif not night and row.night == true and not camping then
            event = "dawn"
        elseif hours >= (tonumber(current.untilHours) or math.huge) then
            event = "timeout"
        end
    end
    if event == nil and critical ~= nil then event = "need_critical:" .. critical end
    if not Service.calm(members) then
        Service.metrics.busy = Service.metrics.busy + 1
        return 0
    end
    local context = Service.loadedContext(id, members, current, needs, hours, night, event)
    if current.id == "fish" then context.off = { fish = true } end
    if current.id == "hunt" then context.off = { hunt = true } end
    local chosen = Planner.decide(context)
    if chosen == nil or chosen == current.id then
        if current.id == "camp" and night and not camping then
            Service.makeCamp(members, current)
            return 1
        end
        if event == "timeout" then return Service.renew(members, squad, current, needs, hours) end
        return 0
    end
    local activity = Service.newActivity(chosen, current, hours, event, current.depot)
    if chosen == "hunt" then
        activity.hunting = Hunt.start(members, hours, activity.untilHours)
        if activity.hunting == nil then return 0 end
        activity.untilHours = activity.hunting.untilHours
    end
    if chosen == "fish" then
        activity.fishing = Fish.start(members, context.shore or {}, hours)
        if activity.fishing == nil then return 0 end
        activity.untilHours = activity.fishing.untilHours
    end
    if not Service.commit(members, squad, activity, needs, hours, chosen == "scavenge") then return 0 end
    Service.metrics.transitions = Service.metrics.transitions + 1
    if chosen == "camp" then Service.makeCamp(members, activity) end
    return 1
end

function Service.squadMutation(q)
    local job = Service.pending
    q.activity = Service.copy(job.activity)
    q.task = Service.taskFor(job.activity, q.nodeId, job.hours)
    q.decisionDueHours = job.activity.untilHours
    if job.needs ~= nil then q.needs = Service.copy(job.needs); Planner.writeSupplies(q) end
end

function Service.commit(members, squad, activity, needs, hours, rebase)
    local stored = squad
    if squad ~= nil then
        Service.pending = { activity = activity, hours = hours, needs = needs }
        stored = Ledger.update(squad.id, squad.revision, Service.squadMutation)
        Service.pending = nil
        if stored == nil then return false end
    end
    return Service.writeMembers(members, activity, stored, needs, rebase, nil, hours), stored
end

function Service.fishing(members, squad, current, hours)
    local activity = Service.copy(current)
    local needs = Service.needsNow(squad, members[1], hours, #members)
    local registry, failed, total = Service.registry(), false, 0
    local function reserve()
        local ok, stored = Service.commit(members, squad, activity, needs, hours, false)
        if not ok then failed = true; return false end
        squad = stored
        for index, record in ipairs(members) do
            local fresh = registry.read(record.uid)
            if fresh == nil or fresh.lifecycle ~= "active" then failed = true; return false end
            members[index] = fresh
        end
        return true
    end
    for _, record in ipairs(members) do
        local work = activity.fishing.work[tostring(record.uid)]
        if work ~= nil then total = total + Fish.catchTick(work, record, hours, reserve) end
        if failed then return 0 end
    end
    needs.food = math.min(100, needs.food + total * 5)
    activity.yields = activity.yields or {}
    activity.yields.food = (tonumber(activity.yields.food) or 0) + total * 5
    local ok = Service.commit(members, squad, activity, needs, hours, false)
    if not ok then
        Service.emit("activity_fishing_commit_refused", { uid = members[1].uid, catches = total, seq = activity.seq })
        return 0
    end
    return 1
end

function Service.startHunting(id, members, squad, current)
    if not Service.calm(members) then return 0 end
    local hours = Service.worldHours()
    local activity = Service.copy(current)
    activity.hunting = Hunt.start(members, hours, activity.untilHours)
    if activity.hunting == nil then return Service.keep(id, members, squad, current, "failed") end
    activity.untilHours = activity.hunting.untilHours
    local needs = Service.needsNow(squad, members[1], hours, #members)
    return Service.commit(members, squad, activity, needs, hours, false) and 1 or 0
end

function Service.huntingShot(player, message, localAnimal)
    if not Service.authoritative() or not Hunt.liveEnabled() or type(message) ~= "table"
            or type(message.uid) ~= "string" or #message.uid > 128
            or type(message.weapon) ~= "string" or #message.weapon > 128 then return false end
    for _, key in ipairs({ "generation", "seq", "attack", "animal" }) do
        local value = message[key]
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or value ~= math.floor(value) then return false end
    end
    local registry, watchdog, relay = Service.registry(), ProjectALife.Watchdog, ProjectALife.NPCHitRelay
    if registry == nil or watchdog == nil or relay == nil then return false end
    local record = registry.read(message.uid)
    local binding = type(watchdog.bindings) == "table" and watchdog.bindings[message.uid] or nil
    if record == nil or record.lifecycle ~= "active" or record.generation ~= message.generation
            or binding == nil or binding.generation ~= message.generation
            or not relay.bindingMatches(binding, message.uid) then return false end
    local shell = binding.shell
    if shell == nil or type(shell.isDead) ~= "function" or shell:isDead() then return false end
    local server = type(isServer) == "function" and isServer()
    if server and (player == nil or type(shell.getOwnerPlayer) ~= "function" or shell:getOwnerPlayer() ~= player) then return false end
    if not server and player ~= nil then return false end
    local paid, timestamp = binding.npcHitAttack, Service.nowMs()
    if paid == nil or paid.owner ~= player or paid.id ~= message.attack or paid.weapon ~= message.weapon
            or paid.hunt == true or paid.count ~= 0 or type(paid.atMs) ~= "number"
            or timestamp < paid.atMs or timestamp - paid.atMs > 1500 then return false end
    local groupId = type(record.memory) == "table" and tostring(record.memory.groupId) or nil
    local group = groupId ~= nil and Service.state.groups[groupId] or nil
    if group == nil then return false end
    local members = Service.membersOf(group)
    if #members == 0 or not Service.calm(members) then return false end
    local belongs = false
    for _, member in ipairs(members) do if member.uid == message.uid then belongs = true; break end end
    if not belongs then return false end
    local squad = Service.squadOf(groupId, members)
    if squad == nil and record.memory.squadId ~= nil then return false end
    if squad ~= nil and not Service.squadOwns(squad, groupId, members) then return false end
    local current = Service.currentOf(squad, members[1])
    if current == nil or current.id ~= "hunt" or current.seq ~= message.seq
            or not Service.memberSynced(record, current, squad) then return false end
    local hours, now = Service.worldHours(), Service.nowMs()
    local needs = Service.needsNow(squad, members[1], hours, #members)
    if Hunt.finished(current.hunting, members, hours, needs.food) then return false end
    for _, need in ipairs(Catalog.NEEDS) do
        if need ~= "food" and needs[need] < Planner.settings.criticalBelow then return false end
    end
    local work = current.hunting.work[message.uid]
    if work == nil or work.watch == true or work.generation ~= message.generation or work.weapon ~= message.weapon then return false end
    local lastKill = tonumber(current.hunting.lastKillMs)
    if lastKill ~= nil and now - lastKill < 60000 then return false end
    local ticket = binding.npcHitAttack
    local weapon = ticket ~= nil and ticket.item or nil
    local weapons, locator, combat = ProjectALife.Weapons, ProjectALife.PlayerLocator, ProjectALife.Combat
    if ticket == nil or ticket.owner ~= player or ticket.id ~= message.attack or ticket.weapon ~= message.weapon
            or weapons == nil or type(weapons.current) ~= "function" or weapons.current(shell) ~= weapon
            or weapon == nil or type(weapon.getMaxRange) ~= "function" or not Hunt.firearm(message.weapon)
            or locator == nil or type(locator.list) ~= "function" or combat == nil
            or type(combat.baseHitChance) ~= "function" or type(ZombRand) ~= "function" then return false end
    local animal
    if server then
        animal = Hunt.resolve(message.animal)
    elseif localAnimal ~= nil and type(localAnimal.getOnlineID) == "function" and localAnimal:getOnlineID() == message.animal then
        animal = localAnimal
    end
    local reach = math.min(25, tonumber(weapon:getMaxRange()) or 0)
    if not Hunt.safeTarget(shell, animal, Hunt.players(), reach) then return false end
    local at, anchor = Hunt.point(shell), current.hunting.anchor
    if at == nil or type(anchor) ~= "table" or (at.x - anchor.x) ^ 2 + (at.y - anchor.y) ^ 2 > 1600 then return false end
    local activity = Service.copy(current)
    if not Hunt.reserveShot(ticket, activity.hunting, message.uid, message.animal, now) then return false end
    local ok, stored = Service.commit(members, squad, activity, needs, hours, false)
    if not ok then return false end
    squad = stored
    for index, member in ipairs(members) do
        local fresh = registry.read(member.uid)
        if fresh == nil or fresh.lifecycle ~= "active" then return false end
        members[index] = fresh
    end
    local target = Hunt.point(animal)
    local distance = math.sqrt((at.x - target.x) ^ 2 + (at.y - target.y) ^ 2)
    if ZombRand(10000) >= combat.baseHitChance(weapon, shell, distance) * 0.8 then
        Hunt.spook(animal, shell)
        return true
    end
    local kind = animal:getAnimalType()
    if not Hunt.kill(animal) then return false end
    activity.hunting.kills = (tonumber(activity.hunting.kills) or 0) + 1
    activity.hunting.lastKillMs, activity.hunting.lastGameHours = now, hours
    local food = (kind == "doe" or kind == "buck") and 24 or 6
    food = food * math.max(0, math.min(300, tonumber(Catalog.sandbox("Activities_HuntYieldPercent")) or 100)) / 100
    needs.food = math.min(100, needs.food + food)
    activity.yields = activity.yields or {}
    activity.yields.food = (tonumber(activity.yields.food) or 0) + food
    if not Service.commit(members, squad, activity, needs, hours, false) then
        Service.emit("activity_hunting_commit_refused", { uid = message.uid, seq = message.seq })
    end
    return true
end

function Service.startFishing(id, members, squad, current)
    if not Service.calm(members) then return 0 end
    local hours = Service.worldHours()
    local needs = Service.needsNow(squad, members[1], hours, #members)
    Service.state.shore = Service.state.shore or {}
    local posts, done, search = Fish.scanShore(Service.state.shore[id], members[1].worldPosition, hours)
    Service.state.shore[id] = search
    if not Fish.enabled() or (#posts == 0 and done) then return Service.keep(id, members, squad, current, "failed") end
    if #posts == 0 then return 0 end
    local activity = Service.copy(current)
    activity.fishing = Fish.start(members, posts, hours)
    if activity.fishing == nil then return Service.keep(id, members, squad, current, "failed") end
    activity.untilHours = activity.fishing.untilHours
    return Service.commit(members, squad, activity, needs, hours, false) and 1 or 0
end

function Service.choreSpot(id, members, kind, hours)
    local at = members[1].worldPosition
    if type(at) ~= "table" then return nil, true end
    local spot = { x = math.floor(tonumber(at.x) or 0) + 0.5, y = math.floor(tonumber(at.y) or 0) + 0.5, z = 0 }
    if kind ~= "water" then return spot, true end
    Service.state.shore = Service.state.shore or {}
    local posts, done, search = Fish.scanShore(Service.state.shore[id], at, hours)
    Service.state.shore[id] = search
    if #posts > 0 then return { x = posts[1].x, y = posts[1].y, z = 0 }, true end
    if done then return spot, true end
    return nil, false
end

function Service.startChore(id, members, squad, current)
    if not Service.calm(members) then return 0 end
    local row = Catalog.activities[current.id]
    local hours = Service.worldHours()
    local spot, ready = Service.choreSpot(id, members, row.chore, hours)
    if not ready then return 0 end
    if spot == nil then return Service.leaveEntry(id, members, current) end
    local needs = Service.needsNow(squad, members[1], hours, #members)
    local span = type(row.duration) == "table" and row.duration or { 1, 2 }
    local activity = Service.copy(current)
    activity.untilHours = hours + span[1] + (span[2] - span[1]) * Planner.stableRoll(id .. ":chore:" .. current.id)
    activity.chore = { kind = row.chore, spot = spot }
    return Service.commit(members, squad, activity, needs, hours, false) and 1 or 0
end

function Service.renew(members, squad, current, needs, hours)
    local activity = Service.newActivity(current.id, current, hours, "timeout", current.depot)
    activity.seq = current.seq
    local committed = Service.commit(members, squad, activity, needs, hours, false)
    if committed then Service.metrics.renewed = Service.metrics.renewed + 1 end
    return committed and 1 or 0
end

function Service.campable(square, road)
    if square == nil then return false end
    if type(square.isOutside) ~= "function" or square:isOutside() ~= true then return false end
    if type(square.getBuilding) == "function" and square:getBuilding() ~= nil then return false end
    if type(square.isFree) ~= "function" or square:isFree(true) ~= true then return false end
    if road ~= nil and type(road.isRoadSquare) == "function" and road.isRoadSquare(square) then return false end
    return true
end

function Service.campSpot(point)
    if type(point) ~= "table" or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local road = ProjectALife.Road
    local z = math.floor(tonumber(point.z) or 0)
    for step = 3, 6, 3 do
        for _, ring in ipairs(Service.RINGS) do
            local x = math.floor((tonumber(point.x) or 0) + ring[1] * step)
            local y = math.floor((tonumber(point.y) or 0) + ring[2] * step)
            if Service.campable(cell:getGridSquare(x, y, z), road) then return { x = x + 0.5, y = y + 0.5, z = z } end
        end
    end
    return nil
end

function Service.makeCamp(members, activity)
    local fires = ProjectALife.Campfires
    if fires == nil or type(fires.light) ~= "function" or type(fires.setGroupCamp) ~= "function" then return false end
    local leader = members[1]
    local here = leader.worldPosition
    local depot = activity.depot
    local near = here
    if type(depot) == "table" and type(here) == "table" then
        local dx, dy = (tonumber(depot.x) or 0) - (tonumber(here.x) or 0), (tonumber(depot.y) or 0) - (tonumber(here.y) or 0)
        local reach = Service.settings.campReach
        if dx * dx + dy * dy <= reach * reach then near = depot end
    end
    local spot = Service.campSpot(near)
    if spot == nil then
        Service.metrics.campRefused = Service.metrics.campRefused + 1
        return false
    end
    local key = "camp:" .. tostring(leader.memory.groupId or leader.uid)
    fires.light(key, spot.x, spot.y, spot.z, Service.settings.campFireMinutes, leader)
    fires.setGroupCamp(leader, spot, key, true)
    Service.metrics.camps = Service.metrics.camps + 1
    return true
end

function Service.reset()
    Service.state = { groups = {}, order = {}, cursor = 1, scanAtMs = nil, lastMs = {}, refusalSaid = {} }
    Service.metrics = { scans = 0, groups = 0, serviced = 0, events = 0, staleEvents = 0, transitions = 0,
        holds = 0, adopted = 0, adoptRefused = 0, adoptRefusedBy = {}, healed = 0, carsReleased = 0,
        camps = 0, campRefused = 0, renewed = 0, busy = 0 }
    Service.pending = nil
    return true
end

return Service
