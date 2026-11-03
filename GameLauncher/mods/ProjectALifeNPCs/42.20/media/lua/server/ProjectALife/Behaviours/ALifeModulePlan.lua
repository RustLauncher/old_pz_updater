require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/World/ALifePlanData"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Data = ProjectALife.PlanData

local Plan = {
    id = "plan",
    adapters = {},
    board = {}, claims = {}, rosters = {}, scans = {}, backoff = {}, voiced = {}, after = {},
    waits = {},
    store = nil, sequence = 0, nextSweepMs = 0,
    chatterNames = { "GroupChatter", "ChatterDirector" },
    metrics = {
        plansMade = 0, plansKept = 0, plansAbandoned = 0, plansCompleted = 0, idleReplacedByPlan = 0,
        abandonReasons = {}, madeByKind = {}, offlineMade = 0, offlineCompleted = 0,
        scans = 0, scanRooms = 0, noTarget = 0, talks = 0, scenes = 0, barks = 0, handoffs = 0, waitCapped = 0,
    },
}
ProjectALife.GroupPlan = Plan

function Plan.configure(adapters)
    Plan.adapters = type(adapters) == "table" and adapters or {}
    return true
end

function Plan.reset()
    Plan.board, Plan.claims, Plan.rosters, Plan.scans = {}, {}, {}, {}
    Plan.backoff, Plan.voiced, Plan.after = {}, {}, {}
    Plan.waits = {}
    Plan.store, Plan.sequence, Plan.nextSweepMs = nil, 0, 0
    Plan.metrics = {
        plansMade = 0, plansKept = 0, plansAbandoned = 0, plansCompleted = 0, idleReplacedByPlan = 0,
        abandonReasons = {}, madeByKind = {}, offlineMade = 0, offlineCompleted = 0,
        scans = 0, scanRooms = 0, noTarget = 0, talks = 0, scenes = 0, barks = 0, handoffs = 0, waitCapped = 0,
    }
    return true
end

function Plan.option(name, default)
    local forced = Plan.adapters.options
    if type(forced) == "table" and forced[name] ~= nil then return forced[name] end
    local vars = nil
    if type(SandboxVars) == "table" then vars = SandboxVars.ALife end
    local value = nil
    if type(vars) == "table" then value = vars[name] end
    if value == nil then return default end
    return value
end

function Plan.clamp(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if number == nil then number = fallback end
    return math.max(minimum, math.min(maximum, number))
end

function Plan.enabled()
    return Plan.option("Plans_Enabled", true) ~= false
end

function Plan.talking()
    return Plan.option("Plans_Talk", true) ~= false
end

function Plan.radius()
    local d = Data.defaults
    return Plan.clamp(Plan.option("Plans_Radius", d.radius), d.minRadius, d.maxRadius, d.radius)
end

function Plan.lifespan()
    local d = Data.defaults
    return Plan.clamp(Plan.option("Plans_LifespanHours", d.lifespanHours), d.minLifespan, d.maxLifespan, d.lifespanHours)
end

function Plan.nowMs()
    if type(Plan.adapters.nowMs) == "function" then return Plan.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Plan.hours()
    if type(Plan.adapters.worldHours) == "function" then return Plan.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return tonumber(hours) or 0
end

function Plan.hourOfDay()
    if type(Plan.adapters.hourOfDay) == "function" then return Plan.adapters.hourOfDay() end
    local hour = 12
    pcall(function() hour = getGameTime():getHour() end)
    return tonumber(hour) or 12
end

function Plan.day()
    if type(Plan.adapters.day) == "function" then return Plan.adapters.day() end
    local day = 0
    pcall(function() day = getGameTime():getNightsSurvived() end)
    return tonumber(day) or 0
end

function Plan.isNight()
    if type(Plan.adapters.isNight) == "function" then return Plan.adapters.isNight() == true end
    local cycle = ProjectALife.DayCycle
    if cycle ~= nil and type(cycle.isNight) == "function" then return cycle.isNight() == true end
    return Data.isNightHour(Plan.hourOfDay())
end

function Plan.roll()
    if type(Plan.adapters.roll) == "function" then return Plan.adapters.roll() end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(10000) / 10000 end
    return 0.5
end

function Plan.copy(value, depth)
    depth = depth or 0
    if type(value) ~= "table" or depth > 4 then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Plan.copy(item, depth + 1) end
    return result
end

function Plan.xyz(body)
    if body == nil then return nil end
    if type(body) == "table" and tonumber(body.x) ~= nil and type(body.getX) ~= "function" then
        return { x = tonumber(body.x), y = tonumber(body.y), z = tonumber(body.z) or 0 }
    end
    local ok, x, y, z = pcall(function() return body:getX(), body:getY(), body:getZ() end)
    if not ok or x == nil then return nil end
    return { x = x, y = y, z = z or 0 }
end

function Plan.flat(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

function Plan.squareAt(x, y, z)
    if type(Plan.adapters.squareAt) == "function" then return Plan.adapters.squareAt(x, y, z) end
    local square
    pcall(function()
        local cell = getCell()
        if cell ~= nil then square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end
    end)
    return square
end

function Plan.loadedAt(x, y, z)
    local programs = ProjectALife.Programs
    if programs ~= nil and type(programs.loadedAt) == "function" then
        local ok, loaded = pcall(programs.loadedAt, x, y, z)
        return not ok or loaded == true
    end
    return true
end

function Plan.shellOf(uid)
    local watchdog = ProjectALife.Watchdog
    local bindings = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings or nil
    local binding = bindings ~= nil and bindings[uid] or nil
    return binding ~= nil and binding.shell or nil
end

function Plan.groupKey(actor)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.groupId) == "string" and memory.groupId ~= "" then return memory.groupId, true end
    if type(memory.squadId) == "string" and memory.squadId ~= "" then return memory.squadId, true end
    return "solo:" .. tostring(actor.uid), false
end

function Plan.roster(key, grouped, actor, now)
    local cached = Plan.rosters[key]
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Data.timing.rosterMs then return cached end
    local list = {}
    local registry = ProjectALife.ActorRegistry
    if grouped and registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record)
            local memory = type(record.memory) == "table" and record.memory or nil
            if record.lifecycle == "active" and memory ~= nil
                    and (memory.groupId == key or memory.squadId == key) then
                list[#list + 1] = { uid = record.uid, index = tonumber(memory.groupIndex) or 99,
                    leader = memory.groupRole == "leader" }
            end
        end)
    end
    if #list == 0 then
        local memory = type(actor.memory) == "table" and actor.memory or {}
        list[1] = { uid = actor.uid, index = tonumber(memory.groupIndex) or 1, leader = true }
    end
    table.sort(list, function(a, b)
        if a.leader ~= b.leader then return a.leader end
        if a.index ~= b.index then return a.index < b.index end
        return tostring(a.uid) < tostring(b.uid)
    end)
    local entry = { atMs = now, list = list, leaderUid = list[1].uid, size = #list, slot = {} }
    for position = 1, #list do entry.slot[list[position].uid] = position end
    Plan.rosters[key] = entry
    return entry
end

function Plan.leaderPoint(roster, actor, shell)
    if roster.leaderUid ~= actor.uid then
        local lead = Plan.shellOf(roster.leaderUid)
        local point = lead ~= nil and Plan.xyz(lead) or nil
        if point ~= nil then return point end
    end
    return Plan.xyz(shell)
end

function Plan.classOf(actor)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(actor.factionId) or nil
    local bloc = type(faction) == "table" and type(faction.relations) == "table" and faction.relations.bloc or nil
    local register
    if bloc == nil then
        local roles = ProjectALife.DialogueRoles
        if roles ~= nil and type(roles.describe) == "function" then
            local ok, described = pcall(roles.describe, actor, Plan.day())
            if ok and type(described) == "table" then register = described.register end
        end
    end
    return Data.classOf(bloc, register)
end

function Plan.groupHealth(roster)
    local survival = ProjectALife.Survival
    local registry = ProjectALife.ActorRegistry
    if survival == nil or type(survival.healthRatio) ~= "function" or registry == nil
            or type(registry.peek) ~= "function" then return 1 end
    local total, count = 0, 0
    for index = 1, #roster.list do
        local uid = roster.list[index].uid
        local shell, record = Plan.shellOf(uid), registry.peek(uid)
        if shell ~= nil and record ~= nil then
            local ok, ratio = pcall(survival.healthRatio, record, shell)
            if ok and tonumber(ratio) ~= nil then total, count = total + tonumber(ratio), count + 1 end
        end
    end
    if count == 0 then return 1 end
    return total / count
end

function Plan.needsOf(key)
    local ledger = ProjectALife.SquadLedger
    local planner = ProjectALife.ActivityPlanner
    if ledger == nil or planner == nil or type(ledger.peek) ~= "function" or type(planner.needsOf) ~= "function" then
        return nil
    end
    local squad = ledger.peek(key)
    if squad == nil then return nil end
    local ok, needs = pcall(planner.needsOf, squad)
    if ok and type(needs) == "table" then return needs end
    return nil
end

function Plan.cargoFull(shell)
    local scavenging, run = ProjectALife.Scavenging, ProjectALife.ScavengeRun
    if scavenging == nil or type(scavenging.cargo) ~= "function" or run == nil or type(run.settings) ~= "table" then
        return false
    end
    local ok, cargo = pcall(scavenging.cargo, shell)
    return ok and type(cargo) == "table" and #cargo >= (tonumber(run.settings.carryLimit) or 8)
end

function Plan.mayLoot(actor, shell)
    if type(Registry.isEnabled) == "function" and not Registry.isEnabled("scavenge") then return false end
    if Registry.override(actor, "scavenge") == "off" then return false end
    return not Plan.cargoFull(shell)
end

function Plan.working(actor)
    local plan = Plan.board[(Plan.groupKey(actor))]
    return plan ~= nil and plan.stage == "work"
end

function Plan.facts(actor, roster, key)
    return {
        class = Plan.classOf(actor), day = Plan.day(), hour = Plan.hourOfDay(), night = Plan.isNight(),
        size = roster.size, health = Plan.groupHealth(roster), needs = Plan.needsOf(key),
    }
end

function Plan.triedStore()
    if type(Plan.adapters.store) == "table" then return Plan.adapters.store end
    if Plan.store ~= nil then return Plan.store end
    if type(ModData) ~= "table" or type(ModData.getOrCreate) ~= "function" then return nil end
    local ok, data = pcall(ModData.getOrCreate, "ProjectALife.GroupPlans.v1")
    if not ok or type(data) ~= "table" then return nil end
    if type(data.tried) ~= "table" or type(data.order) ~= "table" then
        data.schema, data.tried, data.order = 1, {}, {}
    end
    Plan.store = data
    return data
end

function Plan.triedAt(key)
    local store = Plan.triedStore()
    return store ~= nil and key ~= nil and tonumber(store.tried[key]) or nil
end

function Plan.markTried(key, hours)
    local store = Plan.triedStore()
    if store == nil or key == nil then return false end
    if store.tried[key] == nil then store.order[#store.order + 1] = key end
    store.tried[key] = hours
    while #store.order > 300 do
        local old = table.remove(store.order, 1)
        store.tried[old] = nil
    end
    return true
end

function Plan.onInit()
    Plan.store = nil
end

function Plan.protected(candidate)
    if type(Plan.adapters.protected) == "function" then return Plan.adapters.protected(candidate) == true end
    local programs = ProjectALife.Programs
    if programs ~= nil and type(programs.baseRefuses) == "function" then
        local ok, refused = pcall(programs.baseRefuses, candidate.x, candidate.y)
        if ok and refused == true then return true end
    end
    local locks = ProjectALife.RegionLocks
    if locks ~= nil and type(locks.refuse) == "function" then
        local ok, refused = pcall(locks.refuse, candidate.x, candidate.y)
        if ok and refused == true then return true end
    end
    local heat = ProjectALife.BaseHeat
    if heat ~= nil and type(heat.anchorOverlaps) == "function" and candidate.x1 ~= nil then
        local ok, overlaps = pcall(heat.anchorOverlaps, candidate.x1, candidate.y1, candidate.x2, candidate.y2)
        if ok and overlaps == true then return true end
    end
    return false
end

function Plan.refused(candidate, key, now, hours)
    local claim = Plan.claims[candidate.key]
    if claim ~= nil and claim.key ~= key and now < claim.untilMs then return true end
    local tried = Plan.triedAt(candidate.key)
    if tried ~= nil and hours - tried < Data.timing.triedHours then return true end
    return Plan.protected(candidate)
end

function Plan.scan(here, radius)
    if type(Plan.adapters.scan) == "function" then return Plan.adapters.scan(here, radius) or {} end
    local list = {}
    Plan.metrics.scans = Plan.metrics.scans + 1
    pcall(function()
        local grid = getWorld():getMetaGrid()
        local cap = Data.timing.scanRoomCap
        local reach = radius
        local rooms, total
        for attempt = 1, 3 do
            rooms = ArrayList.new()
            grid:getRoomsIntersecting(math.floor(here.x) - reach, math.floor(here.y) - reach, reach * 2, reach * 2, rooms)
            total = rooms:size()
            if total <= cap or attempt == 3 then break end
            reach = math.max(30, math.floor(reach * math.sqrt(cap / total)))
        end
        local stride = math.max(1, math.ceil(total / cap))
        local byBuilding = {}
        for index = 0, total - 1, stride do
            local room = rooms:get(index)
            local definition = room ~= nil and room:getBuilding() or nil
            if definition ~= nil then
                Plan.metrics.scanRooms = Plan.metrics.scanRooms + 1
                local entry = byBuilding[definition]
                if entry == nil then
                    if #list >= Data.timing.scanCandidateCap then break end
                    local x1, y1, x2, y2 = definition:getX(), definition:getY(), definition:getX2(), definition:getY2()
                    entry = { key = tostring(x1) .. ":" .. tostring(y1) .. ":" .. tostring(x2) .. ":" .. tostring(y2),
                        x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = 0, rooms = 0, tags = {}, names = {} }
                    pcall(function() entry.visited = definition:isHasBeenVisited() == true end)
                    byBuilding[definition] = entry
                    list[#list + 1] = entry
                end
                entry.rooms = entry.rooms + 1
                local name = room:getName()
                if name ~= nil then
                    name = string.lower(tostring(name))
                    entry.names[name] = true
                    local tag = Data.tagOfRoom(name)
                    if tag ~= nil then entry.tags[tag] = (entry.tags[tag] or 0) + 1 end
                end
                if entry.x == nil and tonumber(room:getZ()) == 0 then
                    entry.x = room:getX() + math.floor((tonumber(room:getW()) or 2) / 2)
                    entry.y = room:getY() + math.floor((tonumber(room:getH()) or 2) / 2)
                end
            end
        end
    end)
    local usable = {}
    for index = 1, #list do
        local entry = list[index]
        if entry.x == nil then entry.x, entry.y = (entry.x1 + entry.x2) / 2, (entry.y1 + entry.y2) / 2 end
        usable[#usable + 1] = entry
    end
    return usable
end

function Plan.candidates(here, radius, now)
    local cell = Data.timing.scanCell
    local key = tostring(math.floor(here.x / cell)) .. ":" .. tostring(math.floor(here.y / cell)) .. ":" .. tostring(radius)
    local cached = Plan.scans[key]
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Data.timing.scanTtlMs then return cached.list end
    local list = Plan.scan(here, radius)
    Plan.scans[key] = { atMs = now, list = list }
    local count, oldest, oldestAt = 0, nil, math.huge
    for id, entry in pairs(Plan.scans) do
        count = count + 1
        if entry.atMs < oldestAt then oldest, oldestAt = id, entry.atMs end
    end
    if count > 24 and oldest ~= nil then Plan.scans[oldest] = nil end
    return list
end

function Plan.eventTarget(here, radius, key, now)
    local minimum, maximum = Data.windowFor("check_on", radius)
    local best, bestDistance
    local function consider(x, y, label, id)
        x, y = tonumber(x), tonumber(y)
        if x == nil or y == nil then return end
        local claim = Plan.claims[id]
        if claim ~= nil and claim.key ~= key and now < claim.untilMs then return end
        local distance = Plan.flat(here, { x = x, y = y })
        if distance >= minimum and distance <= maximum and (bestDistance == nil or distance < bestDistance) then
            best, bestDistance = { x = x, y = y, z = 0, key = id, tag = "event", name = label }, distance
        end
    end
    if type(Plan.adapters.events) == "function" then
        for _, event in ipairs(Plan.adapters.events(here, radius) or {}) do
            consider(event.x, event.y, event.name or "that noise", event.key or ("event:" .. tostring(event.x)))
        end
    else
        local fires = ProjectALife.Campfires
        if fires ~= nil and type(fires.active) == "table" then
            for id, entry in pairs(fires.active) do
                if type(entry) == "table" and id ~= ("camp:" .. tostring(key)) then
                    consider(entry.x, entry.y, "that smoke", "fire:" .. tostring(id))
                end
            end
        end
        local heli = ProjectALife.HeliSearch
        if heli ~= nil and type(heli.flights) == "table" then
            for id, flight in pairs(heli.flights) do
                if type(flight) == "table" then consider(flight.x, flight.y, "that chopper", "heli:" .. tostring(id)) end
            end
        end
    end
    if best == nil then return nil end
    best.distance = bestDistance
    return best, nil, {}
end

function Plan.targetFor(kind, facts, here, radius, key, now)
    if kind == "check_on" then return Plan.eventTarget(here, radius, key, now) end
    local candidates = Plan.candidates(here, radius, now)
    local want = Data.wantFor(kind, facts)
    local minimum, maximum = Data.windowFor(kind, radius)
    local hours = Plan.hours()
    local ranked = {}
    for index = 1, #candidates do
        local candidate = candidates[index]
        local distance = Plan.flat(here, candidate)
        if distance >= minimum and distance <= maximum and Plan.loadedAt(candidate.x, candidate.y, candidate.z or 0)
                and not Plan.refused(candidate, key, now, hours) then
            local score, tag = Data.scoreCandidate(kind, facts.class, want, candidate, distance, radius)
            if score ~= nil then
                ranked[#ranked + 1] = { candidate = candidate, score = score, tag = tag, key = candidate.key,
                    distance = distance }
            end
        end
    end
    if #ranked == 0 then return nil end
    Data.rankCandidates(ranked)
    local pick, position = Data.pickRanked(ranked, Plan.roll())
    local function describe(row)
        local c = row.candidate
        return { x = c.x, y = c.y, z = c.z or 0, key = c.key, tag = row.tag, rooms = c.rooms,
            name = Data.labelFor(row.tag, c.names), distance = row.distance }
    end
    local alternates = {}
    for index = 1, math.min(#ranked, 4) do
        if index ~= position and #alternates < Data.defaults.attempts then alternates[#alternates + 1] = describe(ranked[index]) end
    end
    return describe(pick), want, alternates
end

function Plan.persistFor(uid, plan)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or uid == nil or type(registry.peek) ~= "function"
            or type(registry.updateTransient) ~= "function" then return false end
    local current = registry.peek(uid)
    if current == nil then return false end
    local value = plan ~= nil and Plan.copy(plan) or nil
    return registry.updateTransient(current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        record.memory.groupPlan = value
    end, true) == true
end

function Plan.persist(roster, plan)
    if roster == nil then return false end
    return Plan.persistFor(roster.leaderUid, plan)
end

function Plan.persistClear(roster)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or roster == nil or type(registry.peek) ~= "function" then return 0 end
    local cleared = 0
    for index = 1, #roster.list do
        local record = registry.peek(roster.list[index].uid)
        if record ~= nil and type(record.memory) == "table" and record.memory.groupPlan ~= nil then
            if Plan.persistFor(record.uid, nil) then cleared = cleared + 1 end
        end
    end
    return cleared
end

function Plan.summary(plan)
    local target = type(plan.target) == "table" and plan.target or {}
    return { id = plan.id, kind = plan.kind, stage = plan.stage, targetName = plan.targetName,
        x = target.x, y = target.y, class = plan.class, createdHours = plan.createdHours,
        untilHours = plan.untilHours, source = plan.source or "loaded" }
end

function Plan.mirror(key, plan, gap)
    local ledger = ProjectALife.SquadLedger
    if ledger == nil or type(ledger.peek) ~= "function" or type(ledger.update) ~= "function" then return false end
    local squad = ledger.peek(key)
    if squad == nil then return false end
    local summary = nil
    if plan ~= nil then
        summary = Plan.summary(plan)
    elseif gap == true then
        summary = { source = "loaded", stage = "gap", untilHours = Plan.hours() + Data.timing.gapHours }
    end
    return ledger.update(squad.id, squad.revision, function(q) q.plan = summary end, true) == true
end

function Plan.validStored(stored)
    if type(stored) ~= "table" or type(stored.id) ~= "string" or Data.isKind[stored.kind] ~= true
            or type(stored.stage) ~= "string" or type(stored.target) ~= "table"
            or tonumber(stored.target.x) == nil or tonumber(stored.target.y) == nil
            or tonumber(stored.untilHours) == nil or type(stored.steps) ~= "table" then return false end
    return true
end

function Plan.read(key, roster, now)
    local plan = Plan.board[key]
    if plan ~= nil then return plan end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.peek) == "function" and registry.peek(roster.leaderUid) or nil
    local stored = record ~= nil and type(record.memory) == "table" and record.memory.groupPlan or nil
    if not Plan.validStored(stored) then return nil end
    plan = Plan.copy(stored)
    plan.stageMs, plan.createdMs, plan.seenMs = now, now, now
    plan.progress, plan.checkAtMs, plan.workStartMs, plan.workAtMs = nil, nil, nil, nil
    Plan.board[key] = plan
    return plan
end

function Plan.current(key)
    key = tostring(key or "")
    local plan = Plan.board[key]
    if plan == nil then
        local ledger = ProjectALife.SquadLedger
        local squad = ledger ~= nil and type(ledger.peek) == "function" and ledger.peek(key) or nil
        plan = squad ~= nil and squad.plan or nil
    end
    if type(plan) ~= "table" or plan.kind == nil then return nil end
    local target = type(plan.target) == "table" and plan.target or {}
    return {
        kind = plan.kind, targetName = plan.targetName, stage = plan.stage,
        targetX = target.x or plan.x, targetY = target.y or plan.y,
        id = plan.id, class = plan.class, source = plan.source or "loaded",
    }
end

function Plan.stopFor(actor)
    local key = Plan.groupKey(actor)
    local plan = Plan.board[key]
    if plan == nil or plan.stage ~= "stop" or type(plan.target) ~= "table" then return nil end
    return { kind = plan.kind, x = plan.target.x, y = plan.target.y, z = plan.target.z or 0,
        key = plan.target.key, untilHours = plan.stopUntilHours or nil, night = plan.stopUntilHours == false,
        name = plan.targetName }
end

function Plan.talkDue(key)
    local plan = Plan.board[tostring(key or "")]
    return plan ~= nil and plan.talkDue or nil
end

function Plan.noteTalked(key, phase)
    local plan = Plan.board[tostring(key or "")]
    if plan == nil then return false end
    if phase == nil or plan.talkDue == phase then plan.talkDue = nil end
    plan.talked = type(plan.talked) == "table" and plan.talked or {}
    plan.talked[tostring(phase or "any")] = Plan.nowMs()
    return true
end

function Plan.chatter()
    for index = 1, #Plan.chatterNames do
        if type(ProjectALife[Plan.chatterNames[index]]) == "table" then return true end
    end
    return false
end

function Plan.sceneReady()
    local data = ProjectALife.DialogueData
    if data == nil or type(data.load) ~= "function" then return false end
    pcall(data.load)
    local pool = type(data.scenesByTopic) == "table" and data.scenesByTopic.plan or nil
    return type(pool) == "table" and #pool > 0
end

function Plan.hash(text)
    local seed = 0
    for index = 1, #text do seed = (seed * 31 + string.byte(text, index)) % 2147483647 end
    return seed
end

function Plan.lineIndex(plan, phase)
    return Plan.hash(tostring(plan.id) .. ":" .. tostring(phase))
end

function Plan.nightShelters(key, day)
    local life = ProjectALife.ModuleIdleLife
    local percent = 65
    if type(Plan.adapters.shelterPercent) == "function" then
        percent = tonumber(Plan.adapters.shelterPercent()) or percent
    elseif life ~= nil and type(life.shelterPercent) == "function" then
        local ok, value = pcall(life.shelterPercent)
        if ok and tonumber(value) ~= nil then percent = tonumber(value) end
    end
    return (Plan.hash(tostring(key) .. ":" .. tostring(day)) % 100) < percent
end

function Plan.say(key, plan, phase, shell, roster, now, speakerSlot)
    if not Plan.talking() then return false end
    local last = Plan.voiced[key]
    if last ~= nil and now >= last and now - last < Data.timing.barkGapMs then return false end
    if Plan.chatter() then
        plan.talkDue = phase
        return false
    end
    if phase == "propose" and roster ~= nil and roster.size >= 2 and Plan.sceneReady() then
        local gossip = ProjectALife.Gossip
        if gossip ~= nil and type(gossip.tryStart) == "function" then
            local ok, started = pcall(gossip.tryStart, shell, { context = "ambient", groupId = key, topic = "plan",
                now = now, planKind = plan.kind, planTarget = plan.targetName })
            if ok and started == true then
                plan.scene = true
                Plan.voiced[key] = now
                Plan.metrics.scenes = Plan.metrics.scenes + 1
                return true
            end
        end
    end
    if plan.scene == true and (phase == "agree" or phase == "commit") then return false end
    local speaker = shell
    if speakerSlot ~= nil and roster ~= nil and roster.list[speakerSlot] ~= nil then
        speaker = Plan.shellOf(roster.list[speakerSlot].uid) or shell
    end
    local line = Data.line(plan.kind, phase, Plan.lineIndex(plan, phase))
    local speech = ProjectALife.Speech
    if line == nil or speaker == nil or speech == nil or type(speech.say) ~= "function" then return false end
    local text = Data.render(line, { target = plan.targetName })
    local ok, said = pcall(speech.say, speaker, text, { chat = true })
    if ok and said == true then
        Plan.voiced[key] = now
        Plan.metrics.talks = Plan.metrics.talks + 1
        Plan.metrics.barks = Plan.metrics.barks + 1
        return true
    end
    return false
end

function Plan.sayAbandon(key, plan, reason, shell, now)
    if not Plan.talking() or Plan.chatter() then return false end
    local line = Data.abandonLine(reason, Plan.lineIndex(plan, reason))
    local speech = ProjectALife.Speech
    if line == nil or shell == nil or speech == nil or type(speech.say) ~= "function" then return false end
    local ok, said = pcall(speech.say, shell, Data.render(line, { target = plan.targetName }), { chat = true })
    if ok and said == true then
        Plan.voiced[key] = now
        Plan.metrics.talks = Plan.metrics.talks + 1
    end
    return ok and said == true
end

function Plan.hold(actor, context, intent, now, ms)
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", intent) end
    return { kind = "idle", intent = intent, cooldownUntilMs = now + (tonumber(ms) or 1200) }
end

function Plan.release(key, plan, roster)
    Plan.board[key] = nil
    if type(plan.target) == "table" and plan.target.key ~= nil then
        local claim = Plan.claims[plan.target.key]
        if claim ~= nil and claim.key == key then Plan.claims[plan.target.key] = nil end
    end
    Plan.persistClear(roster)
    Plan.mirror(key, nil, true)
end

function Plan.abandon(key, plan, reason, roster, shell, now)
    local metrics = Plan.metrics
    metrics.plansAbandoned = metrics.plansAbandoned + 1
    metrics.abandonReasons[reason] = (metrics.abandonReasons[reason] or 0) + 1
    if reason == "blocked" or reason == "looted" or reason == "target_gone" then
        if type(plan.target) == "table" then Plan.markTried(plan.target.key, Plan.hours()) end
    end
    Plan.release(key, plan, roster)
    Plan.after[key] = { reason = reason, atMs = now, followUp = false }
    Plan.backoff[key] = nil
    if reason ~= "released" and reason ~= "disabled" then Plan.sayAbandon(key, plan, reason, shell, now) end
end

function Plan.complete(key, plan, roster, now)
    Plan.metrics.plansCompleted = Plan.metrics.plansCompleted + 1
    if Data.lootKinds[plan.kind] == true and type(plan.target) == "table" then
        Plan.markTried(plan.target.key, Plan.hours())
    end
    Plan.release(key, plan, roster)
    Plan.after[key] = { atMs = now, followUp = Data.followUp[plan.kind] == true, kind = plan.kind }
end

function Plan.advance(key, plan, roster, now)
    plan.stepIndex = (tonumber(plan.stepIndex) or 1) + 1
    plan.stage = plan.steps[plan.stepIndex] or "done"
    plan.stageMs = now
    plan.progress, plan.workStartMs, plan.workAtMs = nil, nil, nil
    Plan.persist(roster, plan)
    Plan.mirror(key, plan)
    return plan.stage
end

function Plan.create(actor, shell, context, key, roster, now)
    local here = Plan.leaderPoint(roster, actor, shell)
    if here == nil then return nil end
    local facts = Plan.facts(actor, roster, key)
    local hours = Plan.hours()
    local radius = Plan.radius()
    local blocked = {}
    if facts.night and not Plan.nightShelters(key, facts.day) then
        Plan.backoff[key] = now + Data.timing.nightBackoffMs
        return nil
    end
    if not Plan.mayLoot(actor, shell) then blocked.loot_building, blocked.supply_run = true, true end
    local after = Plan.after[key]
    local forced, trigger = nil, "free"
    local previous = actor.intent
    local activity = actor.activity
    if activity == "idle" or previous == "hold" or previous == "patrol" or previous == "scan_supplies" then trigger = "idle" end
    if after ~= nil and now - (tonumber(after.atMs) or 0) < 600000 then
        if after.reason == "injury" or after.reason == "danger" then
            forced = facts.night and "find_shelter" or "rest_at_shelter"
        elseif after.followUp == true and not facts.night then
            forced = "rest_at_shelter"
        end
    end
    local kind, target, want, alternates
    if forced ~= nil then
        target, want, alternates = Plan.targetFor(forced, facts, here, radius, key, now)
        if target ~= nil then kind = forced end
        if kind ~= nil and after ~= nil and after.followUp == true then trigger = "stop" end
    end
    if kind == nil then
        for _ = 1, 6 do
            local picked = Data.pickKind(facts, blocked, Plan.roll())
            if picked == nil then break end
            target, want, alternates = Plan.targetFor(picked, facts, here, radius, key, now)
            if target ~= nil then
                kind = picked
                break
            end
            blocked[picked] = true
        end
    end
    if after ~= nil then Plan.after[key] = nil end
    if kind == nil then
        Plan.metrics.noTarget = Plan.metrics.noTarget + 1
        return nil
    end
    Plan.sequence = Plan.sequence + 1
    local plan = {
        id = "plan:" .. tostring(Plan.sequence) .. ":" .. tostring(key), kind = kind,
        steps = Plan.copy(Data.steps[kind]), stepIndex = 1, stage = Data.steps[kind][1],
        createdHours = hours, untilHours = hours + Data.lifespanFor(kind, Plan.lifespan()),
        createdMs = now, stageMs = now, seenMs = now,
        target = target, targetName = target.name, alternates = alternates or {},
        class = facts.class, want = want, trigger = trigger, timeouts = 0, fights = 0,
        deaths = 0, attempts = 0, size = roster.size, source = "loaded",
        leaderUid = roster.leaderUid, contactSeenMs = now,
    }
    Plan.board[key] = plan
    Plan.claims[target.key] = { key = key, untilMs = now + Data.timing.claimMs }
    local metrics = Plan.metrics
    metrics.plansMade = metrics.plansMade + 1
    metrics.madeByKind[kind] = (metrics.madeByKind[kind] or 0) + 1
    Plan.persist(roster, plan)
    Plan.mirror(key, plan)
    return plan
end

function Plan.contactAt(key)
    local tactics = ProjectALife.SquadTactics
    local contacts = tactics ~= nil and type(tactics.contacts) == "table" and tactics.contacts or nil
    local held = contacts ~= nil and contacts[key] or nil
    if type(held) ~= "table" or held.kind == "zombie" then return nil end
    return tonumber(held.atMs)
end

function Plan.targetGone(plan)
    if type(plan.target) ~= "table" or plan.target.tag == "event" then return false end
    local target = plan.target
    local here = plan.lastHere
    if here == nil or Plan.flat(here, target) > Data.timing.nearTiles then return false end
    local square = Plan.squareAt(target.x, target.y, target.z)
    if square == nil then return false end
    local building, probed = nil, false
    pcall(function() building, probed = square:getBuilding(), true end)
    return probed and building == nil
end

function Plan.check(key, plan, actor, shell, context, now, roster)
    local hours = Plan.hours()
    if plan.abandonNow ~= nil then return plan.abandonNow end
    if plan.stage ~= "stop" and hours >= plan.untilHours then return "expired" end
    if plan.keptCounted ~= true and now - plan.createdMs >= Data.timing.keptMs then
        plan.keptCounted = true
        Plan.metrics.plansKept = Plan.metrics.plansKept + 1
    end
    if (tonumber(plan.timeouts) or 0) >= Data.defaults.timeoutsLimit then return "blocked" end
    if roster.leaderUid ~= actor.uid or now < (tonumber(plan.checkAtMs) or 0) then return nil end
    plan.checkAtMs = now + 5000
    plan.lastHere = Plan.xyz(shell)
    if plan.stage == "stop" then return nil end
    local contact = Plan.contactAt(key)
    if contact ~= nil and contact > (tonumber(plan.contactSeenMs) or 0) then
        local previous = tonumber(plan.contactSeenMs) or 0
        plan.contactSeenMs = contact
        if previous <= (tonumber(plan.createdMs) or 0) or contact - previous >= Data.timing.fightGapMs then
            plan.fights = (tonumber(plan.fights) or 0) + 1
        end
    end
    if roster.size < (tonumber(plan.size) or roster.size) then
        plan.deaths = (tonumber(plan.deaths) or 0) + (plan.size - roster.size)
        plan.size = roster.size
        return "danger"
    end
    if (tonumber(plan.fights) or 0) >= Data.defaults.dangerFights then return "danger" end
    if Plan.groupHealth(roster) < Data.defaults.injuryRatio and not Data.stopKinds[plan.kind] then return "injury" end
    if Plan.protected(plan.target) then return "protected" end
    if Plan.targetGone(plan) then return "target_gone" end
    return nil
end

function Plan.progress(plan, distance, now)
    local last = plan.progress
    if last == nil or distance < last.best - Data.timing.progressTiles then
        plan.progress = { best = distance, atMs = now }
        return false
    end
    if now - last.atMs >= Data.timing.progressMs then
        plan.timeouts = (tonumber(plan.timeouts) or 0) + 1
        plan.progress = { best = distance, atMs = now }
        return true
    end
    return false
end

function Plan.legFor(actor, plan, roster, here, lead, fan)
    local target = plan.target
    local base = lead or here
    local dx, dy = target.x - base.x, target.y - base.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local z = tonumber(target.z) or here.z or 0
    local slot = roster.slot[actor.uid] or 1
    local count = math.max(1, roster.size)
    if distance <= Data.timing.legTiles then
        if slot == 1 or count == 1 or fan == "exact" then return { x = target.x, y = target.y, z = z } end
        local angle = (slot - 1) * (2 * math.pi / count)
        local ring = Data.timing.ringRadius
        return { x = target.x + math.cos(angle) * ring, y = target.y + math.sin(angle) * ring, z = z }
    end
    local ux, uy = dx / distance, dy / distance
    local turn = (tonumber(fan) or 0) * math.pi / 180
    if turn ~= 0 then
        ux, uy = ux * math.cos(turn) - uy * math.sin(turn), ux * math.sin(turn) + uy * math.cos(turn)
    end
    local lateral = ((slot - 1) - (count - 1) / 2) * Data.timing.laneSpacing
    local back = -(slot - 1) * 0.6
    local reach = Data.timing.legTiles
    return { x = base.x + ux * (reach + back) - uy * lateral, y = base.y + uy * (reach + back) + ux * lateral, z = z }
end

function Plan.arrived(plan, lead, shell)
    local target = plan.target
    local limit = Data.stopKinds[plan.kind] == true and Data.timing.arriveShelterTiles or Data.timing.arriveTiles
    if Plan.flat(lead, target) <= limit then return true end
    if Data.stopKinds[plan.kind] == true then return false end
    local square = Plan.squareAt(target.x, target.y, target.z)
    if square == nil then return false end
    local inside = false
    pcall(function()
        local building = square:getBuilding()
        local mine = shell:getCurrentSquare()
        inside = building ~= nil and mine ~= nil and mine:getBuilding() == building
    end)
    return inside
end

function Plan.stageTalk(key, plan, actor, shell, context, now, roster)
    local planner = roster.leaderUid == actor.uid
    local elapsed = now - plan.stageMs
    local timing = Data.timing
    local goAt = timing.goMs
    if not Plan.talking() then goAt = timing.quietGoMs elseif roster.size <= 1 then goAt = timing.soloGoMs end
    plan.talk = type(plan.talk) == "table" and plan.talk or {}
    if planner then
        if plan.talk.propose == nil then
            plan.talk.propose = now
            Plan.say(key, plan, "propose", shell, roster, now, 1)
        end
        if roster.size > 1 and plan.talk.agree == nil and elapsed >= timing.agreeMs then
            plan.talk.agree = now
            Plan.say(key, plan, "agree", shell, roster, now, 2)
        end
        if roster.size > 1 and plan.talk.commit == nil and elapsed >= timing.commitMs then
            plan.talk.commit = now
            Plan.say(key, plan, "commit", shell, roster, now, 1)
        end
    end
    if elapsed >= goAt and (planner or elapsed >= timing.talkCapMs) then
        Plan.advance(key, plan, roster, now)
        return Plan.step(key, plan, actor, shell, context, now, roster)
    end
    return Plan.hold(actor, context, "plan_discuss", now, 1200)
end

function Plan.stageGo(key, plan, actor, shell, context, now, roster)
    local here = Plan.xyz(shell)
    if here == nil then return nil end
    local lead = Plan.leaderPoint(roster, actor, shell) or here
    local planner = roster.leaderUid == actor.uid
    if planner then
        plan.lastHere = here
        if Plan.arrived(plan, lead, shell) then
            Plan.say(key, plan, "arrive", shell, roster, now, 1)
            Plan.advance(key, plan, roster, now)
            return Plan.step(key, plan, actor, shell, context, now, roster)
        end
        Plan.progress(plan, Plan.flat(lead, plan.target), now)
        if (tonumber(plan.timeouts) or 0) >= Data.defaults.timeoutsLimit then return nil end
    end
    if Plan.waitParked(plan, actor, now) then return nil end
    local fans = Data.timing.fanDegrees
    local tries = planner and #fans or 2
    for index = 1, tries do
        local leg = Plan.legFor(actor, plan, roster, here, lead, fans[index])
        if Plan.loadedAt(leg.x, leg.y, leg.z) then
            local state = context.startMovement(actor, shell, leg, "travel", {
                pace = "walk", timeoutMs = Data.timing.legMs, doorsOnly = true, activity = "moving",
            })
            if state ~= nil then
                Plan.waits[actor.uid] = nil
                return state
            end
        end
    end
    local exact = { x = plan.target.x, y = plan.target.y, z = tonumber(plan.target.z) or here.z }
    if Plan.flat(here, exact) <= Data.timing.legTiles and Plan.loadedAt(exact.x, exact.y, exact.z) then
        local state = context.startMovement(actor, shell, exact, "travel", {
            pace = "walk", timeoutMs = Data.timing.legMs, doorsOnly = true, activity = "moving",
        })
        if state ~= nil then
            Plan.waits[actor.uid] = nil
            return state
        end
    end
    if planner then plan.stalls = (tonumber(plan.stalls) or 0) + 1 end
    return Plan.waitHold(plan, actor, context, now, planner, Data.timing.waitCapMs)
end

function Plan.waitHold(plan, actor, context, now, planner, capMs)
    local stage = tostring(plan.id) .. ":" .. tostring(plan.stage)
    local wait = Plan.waits[actor.uid]
    if wait == nil or wait.stage ~= stage then
        wait = { stage = stage, sinceMs = now }
        Plan.waits[actor.uid] = wait
    end
    if now - wait.sinceMs >= capMs then
        wait.retryMs = now + Data.timing.waitRetryMs
        Plan.metrics.waitCapped = Plan.metrics.waitCapped + 1
        if planner then plan.timeouts = Data.defaults.timeoutsLimit end
        return nil
    end
    return Plan.hold(actor, context, "plan_wait", now, 1500)
end

function Plan.waitParked(plan, actor, now)
    local wait = Plan.waits[actor.uid]
    return wait ~= nil and wait.retryMs ~= nil and now < wait.retryMs
        and wait.stage == tostring(plan.id) .. ":" .. tostring(plan.stage)
end

function Plan.siteSafe(shell, square)
    local run = ProjectALife.ScavengeRun
    if run == nil or type(run.siteSafe) ~= "function" or square == nil then return true end
    local ok, safe = pcall(run.siteSafe, shell, square)
    return not ok or safe ~= false
end

function Plan.buildingIdAt(plan)
    local target = plan.target
    local square = Plan.squareAt(target.x, target.y, target.z)
    if square == nil then return nil, nil end
    local id
    pcall(function()
        local building = square:getBuilding()
        if building ~= nil then id = tostring(building:getID()) end
    end)
    return id, square
end

function Plan.buildingFor(actor, done)
    local key = Plan.groupKey(actor)
    local plan = Plan.board[key]
    if plan == nil or plan.stage ~= "work" or Data.lootKinds[plan.kind] ~= true or type(plan.target) ~= "table" then
        return nil
    end
    local id, square = Plan.buildingIdAt(plan)
    if id == nil or (type(done) == "table" and done[id] == true) then return nil end
    plan.buildingId = id
    return id, square
end

function Plan.workFinished(plan, actor)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local done = type(memory.lootDone) == "table" and memory.lootDone or nil
    if plan.buildingId == nil or done == nil then return false end
    return done[plan.buildingId] == true and memory.lootPhase == nil
end

function Plan.workDone(key, plan, actor, shell, context, now, roster)
    if plan.kind == "find_radio" then
        local chance = Data.radioChance[plan.target.tag] or 0.15
        plan.attempts = (tonumber(plan.attempts) or 0) + 1
        if Plan.roll() < chance then
            plan.found = true
            Plan.say(key, plan, "found", shell, roster, now, 1)
        else
            Plan.say(key, plan, "empty", shell, roster, now, 1)
            local following = table.remove(plan.alternates, 1)
            if following ~= nil then
                plan.target, plan.targetName, plan.buildingId = following, following.name, nil
                plan.stepIndex, plan.stage, plan.stageMs = 2, "go", now
                plan.progress, plan.workStartMs, plan.workAtMs, plan.timeouts = nil, nil, nil, 0
                Plan.claims[following.key] = { key = key, untilMs = now + Data.timing.claimMs }
                Plan.persist(roster, plan)
                Plan.mirror(key, plan)
                return Plan.hold(actor, context, "plan_discuss", now, 1200)
            end
        end
    end
    Plan.say(key, plan, "done", shell, roster, now, 1)
    Plan.advance(key, plan, roster, now)
    return Plan.step(key, plan, actor, shell, context, now, roster)
end

function Plan.stageWork(key, plan, actor, shell, context, now, roster)
    local planner = roster.leaderUid == actor.uid
    plan.workStartMs = plan.workStartMs or now
    if plan.kind == "check_on" then
        local target = plan.target
        local fence = ProjectALife.AIFence
        if fence ~= nil and type(fence.faceAimPoint) == "function" then pcall(fence.faceAimPoint, shell, target.x, target.y, now) end
        if planner and now - plan.workStartMs >= Data.timing.observeMs then
            return Plan.workDone(key, plan, actor, shell, context, now, roster)
        end
        return Plan.hold(actor, context, "plan_observe", now, 1200)
    end
    if planner and plan.buildingId == nil then
        local id, square = Plan.buildingIdAt(plan)
        local lootDone = type(actor.memory) == "table" and actor.memory.lootDone or nil
        if id ~= nil then
            plan.buildingId = id
            if type(lootDone) == "table" and lootDone[id] == true then
                plan.abandonNow = "looted"
            elseif not Plan.siteSafe(shell, square) then
                plan.abandonNow = "danger"
            end
            if plan.abandonNow ~= nil then return Plan.hold(actor, context, "plan_wait", now, 600) end
        end
    end
    if planner and now >= (tonumber(plan.cargoCheckMs) or 0) then
        plan.cargoCheckMs = now + 4000
        plan.cargoFull = Plan.cargoFull(shell)
    end
    if planner and (plan.cargoFull == true or Plan.workFinished(plan, actor)
            or now - plan.workStartMs >= Data.timing.workCapMs) then
        return Plan.workDone(key, plan, actor, shell, context, now, roster)
    end
    if Plan.workFinished(plan, actor) then
        if Plan.waitParked(plan, actor, now) then return nil end
        return Plan.waitHold(plan, actor, context, now, planner, Data.timing.workWaitCapMs)
    end
    local module = Registry.get("scavenge")
    if module == nil or type(module.evaluate) ~= "function" then
        plan.timeouts = Data.defaults.timeoutsLimit
        return nil
    end
    local wanted = plan.want ~= nil and Data.scavengeWanted[plan.want] or nil
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if wanted ~= nil and memory.scavengeWanted ~= wanted then context.persistMemory(actor, "scavengeWanted", wanted) end
    local saved = context.mode
    context.mode = "scavenge"
    local ok, state = pcall(module.evaluate, actor, shell, context)
    context.mode = saved
    if ok and state ~= nil then
        plan.workAtMs = now
        return state
    end
    if planner then
        local since = tonumber(plan.workAtMs) or plan.workStartMs
        if now - since >= Data.timing.workStallMs then
            plan.timeouts = (tonumber(plan.timeouts) or 0) + 1
            plan.workAtMs = now
        end
        return Plan.hold(actor, context, "plan_wait", now, 1500)
    end
    if Plan.waitParked(plan, actor, now) then return nil end
    return Plan.waitHold(plan, actor, context, now, false, Data.timing.workWaitCapMs)
end

function Plan.handoff(actor, context, plan, hours)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.stance ~= nil and memory.stance ~= "" then return false end
    context.persistMemory(actor, "offlineTask", { kind = "fortify", assignedHours = hours,
        untilHours = plan.stopUntilHours or nil, planStop = true })
    context.persistMemory(actor, "planStop", { kind = plan.kind, key = plan.target.key,
        x = plan.target.x, y = plan.target.y, z = plan.target.z or 0, untilHours = plan.stopUntilHours or nil })
    Plan.metrics.handoffs = Plan.metrics.handoffs + 1
    return true
end

function Plan.stageStop(key, plan, actor, shell, context, now, roster)
    local hours = Plan.hours()
    local planner = roster.leaderUid == actor.uid
    if plan.stopStartHours == nil then
        if not planner and now - plan.stageMs < Data.timing.takeoverMs then
            return Plan.hold(actor, context, "plan_stop", now, 1500)
        end
        plan.stopStartHours = hours
        if plan.kind == "find_shelter" and Plan.isNight() then
            plan.stopUntilHours = false
        else
            local active = math.max(0, (hours - plan.createdHours) * 60)
            plan.stopUntilHours = hours + Data.stopMinutes(active, Plan.roll()) / 60
        end
        Plan.handoff(actor, context, plan, hours)
        Plan.persist(roster, plan)
        Plan.mirror(key, plan)
    end
    local limit = plan.stopUntilHours
    local over
    if limit == false then over = not Plan.isNight() else over = limit ~= nil and hours >= limit end
    if over then
        Plan.say(key, plan, "done", shell, roster, now, 1)
        Plan.complete(key, plan, roster, now)
        return nil
    end
    local taken = Registry.evaluate("decision", actor, shell, context, "idleLife")
    if taken ~= nil then return taken end
    return Plan.hold(actor, context, "plan_stop", now, 1500)
end

function Plan.step(key, plan, actor, shell, context, now, roster)
    local stage = plan.stage
    if stage == "talk" then return Plan.stageTalk(key, plan, actor, shell, context, now, roster) end
    if stage == "go" then return Plan.stageGo(key, plan, actor, shell, context, now, roster) end
    if stage == "work" then return Plan.stageWork(key, plan, actor, shell, context, now, roster) end
    if stage == "stop" then return Plan.stageStop(key, plan, actor, shell, context, now, roster) end
    if Plan.board[key] == plan then Plan.complete(key, plan, roster, now) end
    return nil
end

function Plan.orderHeld(actor, context)
    local orders = type(context.orders) == "table" and context.orders or nil
    local order = orders ~= nil and orders[actor.uid] or nil
    if type(order) ~= "table" or order.generation ~= actor.generation then return false end
    return order.untilMs == nil or (tonumber(context.now) or 0) < order.untilMs
end

function Plan.eligible(actor, shell, context, now)
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or shell == nil or context.threat ~= nil then return false end
    if Data.modes[tostring(context.mode)] ~= true then return false end
    if memory.stance ~= nil and memory.stance ~= "" then return false end
    if memory.outpostId ~= nil or memory.outpostSquadId ~= nil or memory.garrisonBounds ~= nil
            or memory.garrisonPost ~= nil or memory.activityId ~= nil or memory.nightCamp == true then return false end
    for _, field in ipairs(Data.stayFields) do
        local value = memory[field]
        if type(value) == "string" and Data.stayModes[string.lower(value)] == true then return false end
    end
    local activity = actor.activity
    if activity == "combat" or activity == "fleeing" or activity == "warning" or activity == "attacking" then
        return false
    end
    if Plan.orderHeld(actor, context) then return false end
    local life = ProjectALife.GroupLife
    if life ~= nil and type(life.governs) == "function" and life.governs(actor, shell, context) then return false end
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.lastKnownFor) == "function" then
        local ok, lead = pcall(perception.lastKnownFor, actor, now)
        if ok and lead ~= nil then return false end
    end
    return true
end

function Plan.sweep(now)
    Plan.nextSweepMs = now + Data.timing.sweepMs
    local enabled = Plan.enabled()
    for key, plan in pairs(Plan.board) do
        local stale = now - (tonumber(plan.seenMs) or 0) > Data.timing.staleMs
        if not enabled or stale then
            local metrics = Plan.metrics
            if enabled then
                metrics.plansAbandoned = metrics.plansAbandoned + 1
                metrics.abandonReasons.released = (metrics.abandonReasons.released or 0) + 1
            end
            Plan.board[key] = nil
            if type(plan.target) == "table" and plan.target.key ~= nil then Plan.claims[plan.target.key] = nil end
        end
    end
    for id, claim in pairs(Plan.claims) do
        if now >= claim.untilMs then Plan.claims[id] = nil end
    end
    for key, entry in pairs(Plan.rosters) do
        if now - entry.atMs > Data.timing.staleMs then Plan.rosters[key] = nil end
    end
    for key, at in pairs(Plan.backoff) do
        if now >= at then Plan.backoff[key] = nil end
    end
    for key, entry in pairs(Plan.after) do
        if now - (tonumber(entry.atMs) or 0) > 900000 then Plan.after[key] = nil end
    end
    for key, at in pairs(Plan.voiced) do
        if now - at > Data.timing.staleMs then Plan.voiced[key] = nil end
    end
    for uid, wait in pairs(Plan.waits) do
        if now - wait.sinceMs > Data.timing.staleMs then Plan.waits[uid] = nil end
    end
end

function Plan.evaluate(actor, shell, context)
    local now = tonumber(context.now) or Plan.nowMs()
    if now >= Plan.nextSweepMs then Plan.sweep(now) end
    if not Plan.enabled() then return nil end
    if type(isClient) == "function" and isClient() == true
            and not (ProjectALife.Executor ~= nil and type(ProjectALife.Executor.clientAuthority) == "function"
                and ProjectALife.Executor.clientAuthority()) then return nil end
    if not Plan.eligible(actor, shell, context, now) then return nil end
    local key, grouped = Plan.groupKey(actor)
    local roster = Plan.roster(key, grouped, actor, now)
    local plan = Plan.read(key, roster, now)
    if plan ~= nil then
        plan.seenMs = now
        local reason = Plan.check(key, plan, actor, shell, context, now, roster)
        if reason ~= nil then
            Plan.abandon(key, plan, reason, roster, shell, now)
            plan = nil
        end
    end
    if plan == nil then
        local wait = Plan.backoff[key]
        if wait ~= nil and now < wait then return nil end
        if roster.leaderUid ~= actor.uid then return nil end
        plan = Plan.create(actor, shell, context, key, roster, now)
        if plan == nil then
            local retry = now + Data.timing.backoffMs
            if Plan.backoff[key] == nil or Plan.backoff[key] < retry then Plan.backoff[key] = retry end
            return nil
        end
    end
    local intent = tostring(actor.intent or "")
    local wasIdle = actor.activity == "idle" and string.sub(intent, 1, 5) ~= "plan_"
    local state = Plan.step(key, plan, actor, shell, context, now, roster)
    if state ~= nil and wasIdle then Plan.metrics.idleReplacedByPlan = Plan.metrics.idleReplacedByPlan + 1 end
    return state
end

function Plan.holds(squad)
    local plan = type(squad) == "table" and squad.plan or nil
    if type(plan) ~= "table" or plan.source ~= "loaded" or plan.stage == "done" then return false end
    return Plan.hours() < (tonumber(plan.untilHours) or 0)
end

function Plan.neighbours(here)
    local graph = ProjectALife.RoadGraph
    local result = {}
    if graph == nil or type(graph.adjacency) ~= "table" then return result end
    local locks = ProjectALife.RegionLocks
    for other, length in pairs(graph.adjacency[here] or {}) do
        local node = graph.nodes[other]
        local closed = node == nil or node.seeded == true
            or (locks ~= nil and type(locks.refuse) == "function" and locks.refuse(node.x, node.y))
        if not closed then result[#result + 1] = { id = other, len = length } end
    end
    table.sort(result, function(a, b)
        if a.len ~= b.len then return a.len < b.len end
        return tostring(a.id) < tostring(b.id)
    end)
    return result
end

function Plan.farTown(here, tree)
    local graph = ProjectALife.RoadGraph
    if graph == nil or type(graph.towns) ~= "table" or tree == nil then return nil end
    for _, place in ipairs(Data.farPlaces) do
        for _, id in ipairs(graph.towns) do
            local node = graph.nodes[id]
            local reach = type(tree.distances) == "table" and tree.distances[id] or nil
            if node ~= nil and string.find(tostring(node.name or ""), place.name, 1, true) == 1
                    and id ~= here and node.seeded ~= true
                    and reach ~= nil and reach < math.huge then
                return id, place.name
            end
        end
    end
    return nil
end

function Plan.offlineBuild(kind, here, squad)
    local graph = ProjectALife.RoadGraph
    local director = ProjectALife.OfflineDirector
    if graph == nil or director == nil then return nil end
    local near = Plan.neighbours(here)
    local task, route, name
    if kind == "loot_building" or kind == "supply_run" then
        local target = near[1] ~= nil and near[1].id or here
        task = { kind = "scavenge", dest = target }
        route = target == here and { here } or graph.route(here, target)
        name = director.placeName ~= nil and graph.nodes[target] ~= nil and director.placeName(target, graph.nodes[target]) or tostring(target)
    elseif kind == "find_radio" or kind == "reach_safe_zone" then
        local tree = type(director.routeTree) == "function" and director.routeTree(here) or nil
        local target
        if kind == "reach_safe_zone" then target = Plan.farTown(here, tree) end
        if target == nil and type(director.travelTown) == "function" then target = director.travelTown(here, tree) end
        if target == nil then return nil end
        task = { kind = "travel", dest = target }
        route = graph.route(here, target, tree)
        name = director.placeName ~= nil and graph.nodes[target] ~= nil and director.placeName(target, graph.nodes[target]) or tostring(target)
    elseif kind == "find_shelter" or kind == "rest_at_shelter" then
        task = { kind = kind == "find_shelter" and "fortify" or "rest", dest = here }
        route = { here }
        name = "a roof"
    else
        return nil
    end
    if route == nil then return nil end
    local label = type(director.labelFor) == "function" and director.labelFor(task.kind, task.dest) or task.kind
    task.label = label
    return task, route, name
end

function Plan.offlineFacts(squad, hours, hour)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(squad.factionId) or nil
    local bloc = type(faction) == "table" and type(faction.relations) == "table" and faction.relations.bloc or nil
    local planner = ProjectALife.ActivityPlanner
    local needs
    if planner ~= nil and type(planner.needsOf) == "function" then
        local ok, value = pcall(planner.needsOf, squad)
        if ok and type(value) == "table" then needs = value end
    end
    local health = 1
    if planner ~= nil and type(planner.averageHealth) == "function" then
        local ok, value = pcall(planner.averageHealth, squad.members)
        if ok and tonumber(value) ~= nil then health = tonumber(value) / 100 end
    end
    return { class = Data.classOf(bloc, nil), day = math.floor((tonumber(hours) or 0) / 24), hour = hour,
        night = Data.isNightHour(hour), needs = needs, health = health, size = type(squad.members) == "table" and #squad.members or 1 }
end

function Plan.offlineTask(squad, hours, here, allowed, hour)
    if not Plan.enabled() or type(squad) ~= "table" or squad.state ~= "offline" then return nil end
    if Data.isNightHour(hour) then return nil end
    local activity = type(squad.activity) == "table" and squad.activity or nil
    if squad.adoptedFrom ~= nil or (activity ~= nil and (activity.id == "fish" or activity.id == "hunt")) then
        return nil
    end
    local graph = ProjectALife.RoadGraph
    if graph == nil or type(graph.nodes) ~= "table" or graph.nodes[here] == nil then return nil end
    local plan = squad.plan
    if type(plan) == "table" and plan.source ~= "offline" then
        squad.plan, plan = nil, nil
    end
    if type(plan) == "table" and hours >= (tonumber(plan.untilHours) or 0) and plan.stage ~= "stop" then
        local metrics = Plan.metrics
        metrics.plansAbandoned = metrics.plansAbandoned + 1
        metrics.abandonReasons.expired = (metrics.abandonReasons.expired or 0) + 1
        squad.plan, plan = nil, nil
    end
    if type(plan) == "table" and plan.stage == "stop" then
        if hours < (tonumber(plan.stopUntilHours) or 0) then
            return { kind = "rest", label = "rest at " .. tostring(plan.targetName), dest = here,
                planId = plan.id, planKind = plan.kind }, { here }
        end
        Plan.metrics.plansCompleted = Plan.metrics.plansCompleted + 1
        Plan.metrics.offlineCompleted = Plan.metrics.offlineCompleted + 1
        squad.plan, plan = nil, nil
    end
    if plan == nil then
        if Plan.roll() >= Data.defaults.offlineShare then return nil end
        local facts = Plan.offlineFacts(squad, hours, hour)
        local blocked = { check_on = true, find_shelter = true }
        local kind, task, route, name
        for _ = 1, 5 do
            kind = Data.pickKind(facts, blocked, Plan.roll())
            if kind == nil then break end
            task, route, name = Plan.offlineBuild(kind, here, squad)
            if task ~= nil then break end
            blocked[kind], kind = true, nil
        end
        if kind == nil or task == nil then return nil end
        Plan.sequence = Plan.sequence + 1
        plan = {
            id = "plan:" .. tostring(Plan.sequence) .. ":" .. tostring(squad.id), kind = kind, stage = "go",
            createdHours = hours, untilHours = hours + Data.lifespanFor(kind, Plan.lifespan()),
            targetName = name, target = { nodeId = task.dest, x = graph.nodes[task.dest] and graph.nodes[task.dest].x,
                y = graph.nodes[task.dest] and graph.nodes[task.dest].y },
            class = facts.class, source = "offline", steps = Plan.copy(Data.steps[kind]), stepIndex = 2,
        }
        squad.plan = plan
        local metrics = Plan.metrics
        metrics.plansMade, metrics.offlineMade = metrics.plansMade + 1, metrics.offlineMade + 1
        metrics.madeByKind[kind] = (metrics.madeByKind[kind] or 0) + 1
        task.planId, task.planKind = plan.id, plan.kind
        return task, route
    end
    return nil
end

function Plan.onArrive(q, task, hours)
    local plan = type(q) == "table" and q.plan or nil
    if type(plan) ~= "table" or type(task) ~= "table" or plan.id ~= task.planId then return false end
    local metrics = Plan.metrics
    if plan.stage == "go" and Data.followUp[plan.kind] == true then
        local active = math.max(0, ((tonumber(hours) or 0) - (tonumber(plan.createdHours) or 0)) * 60)
        plan.stage = "stop"
        plan.stopUntilHours = (tonumber(hours) or 0) + Data.stopMinutes(active, Plan.roll()) / 60
        return true
    end
    metrics.plansCompleted, metrics.offlineCompleted = metrics.plansCompleted + 1, metrics.offlineCompleted + 1
    q.plan = nil
    return true
end

function Plan.qaLine()
    local m = Plan.metrics
    local reasons, kinds = {}, {}
    for reason, count in pairs(m.abandonReasons) do reasons[#reasons + 1] = reason .. "=" .. tostring(count) end
    for kind, count in pairs(m.madeByKind) do kinds[#kinds + 1] = kind .. "=" .. tostring(count) end
    table.sort(reasons)
    table.sort(kinds)
    local active = 0
    for _ in pairs(Plan.board) do active = active + 1 end
    return "[ALIFE-QA] GroupPlan: enabled=" .. tostring(Plan.enabled()) .. " plansMade=" .. tostring(m.plansMade)
        .. " plansKept=" .. tostring(m.plansKept) .. " plansAbandoned=" .. tostring(m.plansAbandoned)
        .. " plansCompleted=" .. tostring(m.plansCompleted) .. " idleReplacedByPlan=" .. tostring(m.idleReplacedByPlan)
        .. " active=" .. tostring(active) .. " offlineMade=" .. tostring(m.offlineMade)
        .. " offlineCompleted=" .. tostring(m.offlineCompleted) .. " noTarget=" .. tostring(m.noTarget)
        .. " scans=" .. tostring(m.scans) .. " scene=" .. tostring(m.scenes) .. " barks=" .. tostring(m.barks)
        .. " handoffs=" .. tostring(m.handoffs) .. " waitCapped=" .. tostring(m.waitCapped)
        .. " why=" .. (#reasons > 0 and table.concat(reasons, ",") or "none")
        .. " kinds=" .. (#kinds > 0 and table.concat(kinds, ",") or "none")
end

Registry.register({
    id = "plan",
    label = "Group plan",
    summary = "A free group picks a goal, talks it over, walks there and sticks to it until it is done or too dangerous.",
    kind = "upkeep",
    priority = 125,
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        return Plan.evaluate(actor, shell, context)
    end,
})

if type(Events) == "table" and Events.OnInitGlobalModData ~= nil and type(Events.OnInitGlobalModData.Add) == "function" then
    Events.OnInitGlobalModData.Add(Plan.onInit)
end

return Plan
