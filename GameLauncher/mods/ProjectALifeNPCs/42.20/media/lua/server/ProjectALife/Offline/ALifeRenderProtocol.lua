require "ProjectALife/World/ALifeRoadGraph"
require "ProjectALife/World/ALifeKeepOut"
require "ProjectALife/Offline/ALifeSquadLedger"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/World/ALifeWorldPressure"

ProjectALife = ProjectALife or {}

local Graph = ProjectALife.RoadGraph
local Ledger = ProjectALife.SquadLedger
local Telemetry = ProjectALife.Telemetry

local Render = {
    adapters = {},
    settings = {
        renderRadius = 80,
        releaseRadius = 120,
        stageIntervalMs = 1250,
        columnSpacing = 2.5,
        coneRange = 60,

        coneHalfCos = 0.5,

        slideStep = 6,
        slideTries = 8,

        noSpotRelocateTries = 6,
        routeRadius = 22,
        transitionsPerTick = 2,

        catchUpSlack = 16,

        hiddenMinimum = 8,
        hiddenTries = 6,
        hiddenStep = 3,
        sampleRadius = 52,
        ringTries = 12,
    },
    state = { lastStageMs = {}, cursor = 1, catalogChecked = {} },
    metrics = { staged = 0, rendered = 0, released = 0, casualties = 0, wiped = 0, refusedSpots = 0, relocated = 0,
        caughtUp = 0, retiredOutOfSeason = 0 },
}
ProjectALife.RenderProtocol = Render

local function nowMs()
    if type(Render.adapters.nowMs) == "function" then return Render.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    if type(Render.adapters.worldHours) == "function" then return Render.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function emit(category, fields)
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then
        pcall(Telemetry.emit, category, fields)
    end
end

local function players()
    if type(Render.adapters.players) == "function" then return Render.adapters.players() or {} end
    local result = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        for _, player in ipairs(locator.list()) do
            local position = locator.position(player)
            if position ~= nil then
                local fx, fy = 1, 0
                pcall(function()
                    local forward = player:getForwardDirection()
                    fx, fy = forward:getX(), forward:getY()
                end)

                local driving = false
                pcall(function() driving = player:getVehicle() ~= nil end)
                result[#result + 1] = { x = position.x, y = position.y, z = position.z, fx = fx, fy = fy, driving = driving }
            end
        end
    end)
    return result
end

local function registry()
    return Render.adapters.registry or ProjectALife.ActorRegistry
end

function Render.configure(adapters)
    Render.adapters = adapters or {}
    local population = ProjectALife.Population
    local spawnDistance = tonumber(Render.adapters.spawnDistance)
        or (population and tonumber(population.spawnDistance)) or 60
    Render.settings.renderRadius = spawnDistance
    Render.settings.releaseRadius = Render.settings.renderRadius + 40
    return true
end

function Render.reset()
    Render.state = { lastStageMs = {}, cursor = 1, catalogChecked = {} }
    return true
end

function Render.reach(list)
    local base = Render.settings.renderRadius
    local fairness = ProjectALife.SpawnFairness
    if fairness == nil or not fairness.enabled() then return base end
    return math.max(base, fairness.maxRing(list) + fairness.bandWidth, fairness.reachFloor or 0)
end

function Render.tickReach(list)
    local state = Render.state
    if state.tickList ~= list then return Render.reach(list) end
    local value = state.tickReach
    if value == nil then
        value = Render.reach(list)
        state.tickReach = value
    end
    return value
end

function Render.ringTiles(list)
    local base = ProjectALife.KeepOut.ringTiles
    local fairness = ProjectALife.SpawnFairness
    if fairness == nil or not fairness.enabled() then return base end
    return math.max(base, fairness.maxRing(list))
end

function Render.releaseRadius()
    local base = Render.settings.releaseRadius
    local fairness = ProjectALife.SpawnFairness
    if fairness == nil or not fairness.enabled() then return base end
    return math.max(base, fairness.baseRing() + fairness.defaults.openExtra + fairness.bandWidth + 20)
end

function Render.stageAllowed(squad, hours)
    local fairness = ProjectALife.SpawnFairness
    return fairness == nil or fairness.stageAllowed(squad, hours)
end

function Render.spotAllowed(x, y, list, minimumDistance, coneRange, halfCos)
    return ProjectALife.KeepOut.spotAllowed(x, y, list, minimumDistance, coneRange, halfCos)
end

function Render.columnPosition(headX, headY, dx, dy, index, spacing)
    local back = (index - 1) * spacing
    return headX - dx * back, headY - dy * back
end

local function legDirection(squad)
    local from = squad.legFrom and Graph.nodes[squad.legFrom] or nil
    local to = type(squad.route) == "table" and squad.route[1] and Graph.nodes[squad.route[1]] or nil
    if from == nil or to == nil then return 1, 0 end
    local dx, dy = to.x - from.x, to.y - from.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return 1, 0 end
    return dx / length, dy / length
end

local function routeAround(x, y, radius)
    local route = {}
    for index = 0, 3 do
        local angle = index * (math.pi / 2) + math.pi / 4
        route[#route + 1] = { x = x + math.cos(angle) * radius, y = y + math.sin(angle) * radius, z = 0 }
    end
    return route
end

function Render.memoryFor(squad, index, x, y, health, commonHead)
    local task = type(squad.task) == "table" and squad.task or {}
    local head = commonHead or squad.stageHead or { x = squad.x, y = squad.y }
    local memory = {
        squadId = squad.id,
        persistent = true,
        groupId = squad.id,
        groupSize = type(squad.members) == "table" and #squad.members or 1,
        groupIndex = index,
        groupRole = index == 1 and "leader" or "member",
        behavior = "patrol",
        adminMode = "patrol",
        behaviorProfile = "patrol",
        home = { x = head.x, y = head.y, z = 0 },
        spawnOrigin = { x = head.x, y = head.y, z = 0 },
        offlineTask = { kind = task.kind, dest = task.dest,
            assignedHours = task.assignedHours, untilHours = task.untilHours },
        identitySeed = squad.id .. ":member:" .. tostring(index),

        shellState = { version = 1, health = tonumber(health) or 100, maximumHealth = 100 },
    }
    local member = squad.members and squad.members[index]
    if member ~= nil then
        memory.identitySeed = member.identitySeed or memory.identitySeed
        if member.shellState ~= nil then
            memory.shellState = member.shellState
            memory.shellState.health = (tonumber(health) or 100)
                * (tonumber(memory.shellState.maximumHealth) or 100) / 100
        end
        local catalog, director = ProjectALife.Catalog, ProjectALife.Director
        local profile = catalog and type(catalog.npc) == "function" and catalog.npc(member.profileId)
        local faction = catalog and type(catalog.faction) == "function" and catalog.faction(squad.factionId)
        if profile and faction and director then
            memory.conduct = director.conductFor(profile, faction, index, memory.groupSize)

            memory.groupRole = index == 1 and "leader" or "member"
            memory.moduleOverrides = director.moduleOverridesFor(faction, profile, memory.conduct)
            memory.memberPolicyVersion = 2
        end
    end
    memory.partyKind = squad.partyKind
    if task.kind == "scavenge" then
        memory.behavior, memory.adminMode, memory.behaviorProfile = "scavenge", "scavenge", "scavenger"
        memory.moduleOverrides = memory.moduleOverrides or {}
        memory.moduleOverrides.scavenge = true
        local dest = task.dest and Graph.nodes[task.dest]
        if dest then memory.scavengeArea = { x = dest.x, y = dest.y, z = 0 } end
    elseif task.kind == "revenge" then

        memory.behavior, memory.adminMode, memory.behaviorProfile = "manhunt", "manhunt", "manhunt"
        memory.targetUsername, memory.revengeKey = task.playerKey, task.playerKey
        if type(task.fix) == "table" and tonumber(task.fix.x) ~= nil then
            memory.knowledgeFix = { key = task.playerKey, x = task.fix.x, y = task.fix.y, z = task.fix.z or 0,
                source = task.fix.source or "dispatch", searches = 0 }
        end
    elseif task.kind == "patrol" then
        memory.stance = "route"
        memory.stanceAnchor = { x = head.x, y = head.y, z = 0 }
        memory.stanceRoute = routeAround(head.x, head.y, Render.settings.routeRadius)
        memory.stanceRouteIndex = 1
    elseif task.kind == "travel" or task.kind == "reinforce" then
        memory.stance = "route"
        memory.stanceAnchor = { x = head.x, y = head.y, z = 0 }
        memory.stanceRoute = {}
        for _, id in ipairs(squad.route or {}) do
            local node = Graph.nodes[id]
            if node then memory.stanceRoute[#memory.stanceRoute + 1] = { x = node.x, y = node.y, z = 0 } end
        end
        memory.stanceRouteIndex = 1
        memory.stanceRouteOneWay = true
    elseif task.kind == "fortify" or task.kind == "rest" then
        memory.moduleOverrides = memory.moduleOverrides or {}
        memory.moduleOverrides.idleLife = true
    end
    Render.activityMemory(memory, squad, head)
    return memory
end

Render.settings.depotReach = 200
Render.activityFields = { "activityId", "activitySeq", "supplyDepot" }

function Render.activityMemory(memory, squad, head)
    local activity = squad.activity
    if type(activity) ~= "table" or type(activity.id) ~= "string" then return memory end
    memory.activityId, memory.activitySeq = activity.id, tonumber(activity.seq) or 0
    local depot = activity.depot
    if type(depot) == "table" and tonumber(depot.x) ~= nil and tonumber(depot.y) ~= nil then
        local dx, dy = depot.x - (tonumber(head.x) or 0), depot.y - (tonumber(head.y) or 0)
        local reach = Render.settings.depotReach
        if dx * dx + dy * dy <= reach * reach then
            memory.supplyDepot = { vehicleSceneKey = depot.vehicleSceneKey, x = depot.x, y = depot.y,
                z = tonumber(depot.z) or 0 }
        end
    end
    return memory
end

function Render.canRetask(squad)
    if squad.task and squad.task.kind == "revenge" then return false end
    local groupPlans = ProjectALife.GroupPlan
    if groupPlans ~= nil and type(groupPlans.holds) == "function" then
        local held, planHeld = pcall(groupPlans.holds, squad)
        if held and planHeld == true then return false end
    end
    for _, uid in ipairs(squad.renderedUids or {}) do
        local record = registry().read(uid)
        local memory = record and record.memory or {}
        if record and record.lifecycle ~= "dead" and (record.lifecycle ~= "active"
                or record.activity == "combat" or record.activity == "attacking"
                or record.activity == "fleeing" or record.activity == "warning" or memory.lootPhase ~= nil
                or memory.shelterPhase ~= nil or memory.nightCamp == true) then return false end
    end
    return true
end

function Render.rebase(squad)
    for _, uid in ipairs(squad.renderedUids or {}) do
        local record = registry().read(uid)
        if record and record.lifecycle == "active" and record.worldPosition then
            return Ledger.update(squad.id, squad.revision, function(q)
                q.x, q.y = record.worldPosition.x, record.worldPosition.y
                q.nodeId = Graph.nearest(q.x, q.y)
            end) or squad
        end
    end
    return squad
end

function Render.refreshTask(squad)
    if squad == nil then return false end
    local reg, head = registry(), nil
    for _, uid in ipairs(squad.renderedUids or {}) do
        local record = reg.read(uid)
        if record and record.lifecycle == "active" and record.worldPosition then head = record.worldPosition; break end
    end
    if head == nil then return false end
    for index, uid in ipairs(squad.renderedUids or {}) do
        local record = reg.read(uid)
        if record and record.lifecycle == "active" then
            local nextMemory = Render.memoryFor(squad, index, head.x, head.y, 100, head)
            reg.update(uid, record.revision, function(fresh)
                fresh.memory = fresh.memory or {}
                for _, field in ipairs({ "behavior", "adminMode", "behaviorProfile", "home", "spawnOrigin",
                        "offlineTask", "stance", "stanceAnchor", "stanceRoute", "stanceRouteIndex", "stanceRouteOneWay",
                        "moduleOverrides", "scavengeArea", "targetUsername", "revengeKey", "knowledgeFix" }) do
                    fresh.memory[field] = nextMemory[field]
                end
                for _, field in ipairs(Render.activityFields) do fresh.memory[field] = nextMemory[field] end
                fresh.memory.stancePost, fresh.memory.stancePhase = nil, nil
                fresh.memory.groupMarch, fresh.memory.travelLeg = nil, nil
                fresh.memory.shelterUntilHours, fresh.memory.shelterBuildingId = nil, nil
                fresh.memory.shelterManagedByLife = nil
                fresh.memory.lootRestUntilMs, fresh.memory.lootPhase = nil, nil
            end)
        end
    end
    return true
end

function Render.slideDirections(headX, headY, list)
    local nx, ny, best = 1, 0, math.huge
    for _, p in ipairs(list) do
        local dx, dy = headX - p.x, headY - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < best and d > 0.001 then nx, ny, best = dx / d, dy / d, d end
    end
    return { { nx, ny }, { -ny, nx }, { ny, -nx },
        { -0.5 * nx - 0.866 * ny, -0.5 * ny + 0.866 * nx },
        { -0.5 * nx + 0.866 * ny, -0.5 * ny - 0.866 * nx } }
end

local function finishStage(squad)
    local pending = squad.stagePending
    local reg, record, err = registry()

    if type(reg.each) == "function" then
        reg.each(function(candidate)
            if candidate.memory and candidate.memory.stageOperationId == pending.specification.operationId then
                record = candidate
            end
        end)
    end
    if record == nil then record, err = reg.create(pending.specification) end
    if record == nil then return false, err end
    local updated = Ledger.update(squad.id, squad.revision, function(q)
        q.renderedUids = q.renderedUids or {}
        q.renderedUids[#q.renderedUids + 1] = record.uid
        if type(q.task) == "table" then q.task.activityRendered = true end
        q.stageHead = q.stageHead or pending.head
        q.stagePending = nil
    end)

    if updated == nil then return false, "ledger_conflict" end
    Render.metrics.staged = Render.metrics.staged + 1
    return true, updated
end

function Render.nearestOf(x, y, list)
    local best = math.huge
    for _, p in ipairs(list or {}) do
        local dx, dy = x - p.x, y - p.y
        local d = dx * dx + dy * dy
        if d < best then best = d end
    end
    return math.sqrt(best)
end

function Render.columnsClear(policy, x, y, dx, dy, count, keep)
    for member = 2, tonumber(count) or 1 do
        local cx, cy = Render.columnPosition(x, y, dx, dy, member, Render.settings.columnSpacing)
        if policy.check({ x = cx, y = cy, z = 0 }, { playerKeepOut = keep, stationed = true }) ~= true then
            return false
        end
    end
    return true
end

function Render.fallbackSpot(index, list, headX, headY, dx, dy, count, hiddenOnly)
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.check) ~= "function" or #list == 0 then return nil end
    local settings = Render.settings
    if index > 1 or Render.nearestOf(headX, headY, list) < Render.ringTiles(list) then
        local keep = tonumber(policy.postKeepOut) or settings.hiddenMinimum
        for try = 0, settings.hiddenTries do
            for _, direction in ipairs(Render.slideDirections(headX, headY, list)) do
                local hx = headX + direction[1] * settings.hiddenStep * try
                local hy = headY + direction[2] * settings.hiddenStep * try
                local cx, cy = Render.columnPosition(hx, hy, dx, dy, index, settings.columnSpacing)
                local ok = policy.check({ x = cx, y = cy, z = 0 },
                    { playerKeepOut = keep, stationed = true })
                if ok == true and index == 1 and count ~= nil
                        and not Render.columnsClear(policy, hx, hy, dx, dy, count, keep) then
                    ok = false
                end
                if ok == true then return cx, cy, hx, hy, "hidden" end
                if try == 0 then break end
            end
        end
        if index == 1 and count ~= nil and type(policy.findSampled) == "function" then
            local options = { playerKeepOut = keep, stationed = true }
            options.validator = function(candidate)
                return Render.columnsClear(policy, candidate.x, candidate.y, dx, dy, count, keep)
            end
            local point = policy.findSampled({ x = headX, y = headY, z = 0 }, options, settings.sampleRadius)
            if point ~= nil then return point.x, point.y, point.x, point.y, "hidden" end
        end
    end
    if hiddenOnly == true then return nil end
    local fairness = ProjectALife.SpawnFairness
    if count ~= nil and fairness ~= nil and type(fairness.enabled) == "function" and fairness.enabled()
            and type(fairness.ringPoint) == "function" and type(fairness.band) == "function" then
        local p, nearestSq = list[1], math.huge
        for _, candidate in ipairs(list) do
            local gx, gy = candidate.x - headX, candidate.y - headY
            if gx * gx + gy * gy < nearestSq then p, nearestSq = candidate, gx * gx + gy * gy end
        end
        local low, high = fairness.band(p.x, p.y)
        local locks = ProjectALife.RegionLocks
        for _ = 1, settings.ringTries do
            local point = fairness.ringPoint(p.x, p.y, low, high, headX, headY)
            if point ~= nil then
                local ok = policy.check({ x = point.x, y = point.y, z = 0 })
                if ok == true and locks ~= nil and type(locks.refuse) == "function" and locks.refuse(point.x, point.y) then ok = false end
                for member = 2, ok == true and count or 1 do
                    local cx, cy = Render.columnPosition(point.x, point.y, dx, dy, member, settings.columnSpacing)
                    ok = policy.check({ x = cx, y = cy, z = 0 })
                    if ok ~= true then break end
                end
                if ok == true then return point.x, point.y, point.x, point.y, "ring" end
            end
        end
    end
    return nil
end

function Render.refuseSpot(why)
    Render.metrics.refusedSpots = (Render.metrics.refusedSpots or 0) + 1
    Render.metrics.refusedBy = Render.metrics.refusedBy or {}
    why = tostring(why or "unknown")
    Render.metrics.refusedBy[why] = (Render.metrics.refusedBy[why] or 0) + 1
end

function Render.floorHeld(x, y, list)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.floorRefusal) ~= "function" then return false end
    local best, z = math.huge, nil
    for _, p in ipairs(list or {}) do
        local dx, dy = x - p.x, y - p.y
        if dx * dx + dy * dy < best then best, z = dx * dx + dy * dy, p.z end
    end
    return z ~= nil and census.floorRefusal(z, 0) ~= nil
end

function Render.driverNearest(x, y, list)
    local best, driving = math.huge, false
    for _, p in ipairs(list or {}) do
        local dx, dy = x - p.x, y - p.y
        local d = dx * dx + dy * dy
        if d < best then best, driving = d, p.driving == true end
    end
    return driving
end

local function stageOne(squad, list, now)
    local staged = type(squad.renderedUids) == "table" and squad.renderedUids or {}
    local index = #staged + 1
    local member = squad.members[index]
    if member == nil then return false, "all_staged" end
    local reg = registry()
    local cap = ProjectALife.Settings and ProjectALife.Settings.current
        and tonumber(ProjectALife.Settings.current.maximumHostileActors) or 32
    local living = 0
    if type(reg.each) == "function" then
        reg.each(function(record) if record.lifecycle ~= "dead" then living = living + 1 end end)
    end
    if Render.adapters.registry == nil and ProjectALife.Population
            and ProjectALife.Population.capacityUsed then
        living = ProjectALife.Population.capacityUsed(true)
    end
    if living >= cap then
        Render.metrics.heldForCapacity = (Render.metrics.heldForCapacity or 0) + 1
        return false, "population_cap"
    end
    local dx, dy = legDirection(squad)

    local headX, headY = squad.x, squad.y
    if type(squad.stageHead) == "table" then headX, headY = squad.stageHead.x, squad.stageHead.y end
    local settings = Render.settings
    local x, y, chosenHeadX, chosenHeadY
    local directions = Render.slideDirections(headX, headY, list)
    local reach, ring = Render.reach(list), Render.ringTiles(list)
    if type(squad.stageHead) == "table" and Render.nearestOf(headX, headY, list) < ring then
        x, y, chosenHeadX, chosenHeadY = Render.fallbackSpot(index, list, headX, headY, dx, dy, nil)
    elseif type(squad.stageHead) ~= "table" and Render.nearestOf(headX, headY, list) < ring then
        local how
        x, y, chosenHeadX, chosenHeadY, how = Render.fallbackSpot(index, list, headX, headY, dx, dy, #squad.members, true)
        if x ~= nil then
            Render.metrics.fallbackSpots = (Render.metrics.fallbackSpots or 0) + 1
            Render.metrics.fallbackBy = Render.metrics.fallbackBy or {}
            Render.metrics.fallbackBy[how] = (Render.metrics.fallbackBy[how] or 0) + 1
        end
    end
    for try = 0, x == nil and settings.slideTries or -1 do
        for _, direction in ipairs(directions) do
            local hx = headX + direction[1] * settings.slideStep * try
            local hy = headY + direction[2] * settings.slideStep * try
            local cx, cy = Render.columnPosition(hx, hy, dx, dy, index, settings.columnSpacing)
            local withinRange = false
            for _, p in ipairs(list) do
                if (cx - p.x)^2 + (cy - p.y)^2 <= reach^2 then withinRange = true break end
            end

            local cone = settings.coneRange
            if try == 0 and type(squad.stageHead) == "table" then cone = 0 end

            local why
            if not withinRange then
                why = "range"
            elseif not Render.spotAllowed(cx, cy, list, ring,
                    cone, settings.coneHalfCos) then
                why = "cone"
            else

                local locks = ProjectALife.RegionLocks
                if locks ~= nil and type(locks.refuse) == "function" and locks.refuse(cx, cy) then
                    why = "region_locked"
                end
            end

            local policy = ProjectALife.SpawnPolicy
            if why == nil and policy ~= nil and type(policy.check) == "function" then
                local ok, reason = policy.check({ x = cx, y = cy, z = 0 })
                if ok ~= true then why = "policy:" .. tostring(reason or "refused") end
            end
            if why == nil and try > 0 and policy ~= nil and type(policy.linked) == "function"
                    and policy.linked({ x = headX, y = headY, z = 0 }, { x = cx, y = cy, z = 0 }) == false then
                why = "policy:slid_unreachable"
            end
            if why == nil then
                x, y, chosenHeadX, chosenHeadY = cx, cy, hx, hy
                break
            end
            Render.refuseSpot(why)
            if try == 0 then break end
        end
        if x ~= nil then break end
    end
    if x == nil then
        local how
        x, y, chosenHeadX, chosenHeadY, how = Render.fallbackSpot(index, list, headX, headY, dx, dy,
            type(squad.stageHead) ~= "table" and #squad.members or nil)
        if x ~= nil then
            Render.metrics.fallbackSpots = (Render.metrics.fallbackSpots or 0) + 1
            Render.metrics.fallbackBy = Render.metrics.fallbackBy or {}
            Render.metrics.fallbackBy[how] = (Render.metrics.fallbackBy[how] or 0) + 1
        end
    end
    if x == nil then return false, "no_spot" end
    local operationId = "offline:" .. squad.id .. ":" .. index .. ":" .. tostring(squad.revision)
    local specification = {
        operationId = operationId,
        fingerprint = operationId,
        profileId = tostring(member.profileId or "?"),
        factionId = tostring(squad.factionId or "?"),
        worldPosition = { x = x, y = y, z = 0 },
        activity = "idle",
        intent = "hold",
        memory = Render.memoryFor(squad, index, x, y, member.health,
            squad.stageHead or { x = chosenHeadX, y = chosenHeadY }),
    }
    specification.memory.stageOperationId = operationId
    local prepared = Ledger.update(squad.id, squad.revision, function(q)
        q.stagePending = { specification = specification,
            head = { x = chosenHeadX, y = chosenHeadY } }
        q.state = "staging"
    end)
    if prepared == nil then return false, "ledger_conflict" end
    return finishStage(prepared)
end

local function release(squad, hours)
    local reg = registry()
    local survivors, sx, sy, count = {}, 0, 0, 0
    local casualties = 0

    if squad.releasePending == nil and #(squad.renderedUids or {}) > 0 then
        local present = false
        for _, uid in ipairs(squad.renderedUids) do
            if (reg.peek or reg.read)(uid) ~= nil then present = true; break end
        end
        if not present then
            Render.state.lastStageMs[squad.id] = nil
            emit("offline_render_stale", { squad = squad.id, name = squad.name,
                members = #(squad.members or {}) })
            return Ledger.update(squad.id, squad.revision, function(q)
                q.renderedUids, q.stageHead = nil, nil
                q.state = "offline"
                q.decisionDueHours = hours
                q.lastSimulatedHours = hours
            end)
        end
    end

    for _, uid in ipairs(squad.renderedUids or {}) do
        local record = reg.read(uid)
        if record ~= nil and record.lifecycle == "spawning" then return nil end
        if record ~= nil and record.lifecycle == "active" then
            local dehydrate = Render.adapters.dehydrate
                or (ProjectALife.SpawnService and ProjectALife.SpawnService.dehydrate)
            if type(dehydrate) ~= "function" then return nil end
            local ok, done = pcall(dehydrate, uid, "render_out")
            if not ok or done ~= true then return nil end
        end
    end
    if squad.releasePending == nil then
        for index, member in ipairs(squad.members or {}) do
            local uid = (squad.renderedUids or {})[index]
            local record = uid and reg.read(uid) or nil
            if uid ~= nil and (record == nil or record.lifecycle == "dead") then
                casualties = casualties + 1
            else
                local fresh = record or {}
                local state = fresh.memory and fresh.memory.shellState or member.shellState
                local health = state and tonumber(state.health) or member.health or 100
                if state ~= nil and tonumber(state.maximumHealth) and state.maximumHealth > 0 then
                    health = health * 100 / state.maximumHealth
                end
                local position = fresh.worldPosition or { x = squad.x, y = squad.y }
                survivors[#survivors + 1] = { profileId = member.profileId, health = health,
                    identitySeed = fresh.memory and fresh.memory.identitySeed or member.identitySeed
                        or squad.id .. ":member:" .. tostring(index),
                    shellState = state, gear = member.gear, name = member.name }
                sx, sy, count = sx + position.x, sy + position.y, count + 1
            end
        end

        local prepared = Ledger.update(squad.id, squad.revision, function(q)
            q.releasePending = { members = survivors, x = count > 0 and sx / count or squad.x,
                y = count > 0 and sy / count or squad.y, casualties = casualties, hours = hours }
        end)
        if prepared == nil then return nil end
        squad = prepared
    end
    local pending = squad.releasePending
    survivors, casualties = pending.members, pending.casualties
    count, hours = #survivors, pending.hours
    for _, uid in ipairs(squad.renderedUids or {}) do
        local record = reg.read(uid)
        if record ~= nil then
            if record.lifecycle ~= "dormant" and record.lifecycle ~= "dead" then return nil end
            local ok, removed = pcall(reg.remove, uid, record.revision, "render_out")
            if not ok or removed ~= true then return nil end
        end
    end
    local updated = Ledger.update(squad.id, squad.revision, function(q)
        q.renderedUids = nil
        q.stageHead = nil
        q.releasePending = nil
        q.members = survivors
        if count > 0 then
            q.x, q.y = pending.x, pending.y
            q.nodeId = Graph.nearest(q.x, q.y)
            q.route = {}
            q.legFrom, q.legHours = nil, nil
            q.decisionDueHours = hours
            q.state = "offline"
            q.lastSimulatedHours = hours
        else
            q.state = "wiped"
            q.wipedHours = hours
        end
    end)
    if updated ~= nil then
        Render.metrics.casualties = Render.metrics.casualties + casualties
        Render.state.lastStageMs[squad.id] = nil
        Render.metrics.released = Render.metrics.released + 1
        if updated.state == "wiped" then Render.metrics.wiped = Render.metrics.wiped + 1 end

        pcall(function()
            local revenge = ProjectALife.Revenge
            if revenge ~= nil then revenge.onReleased(updated, #survivors, hours) end
        end)
        emit("offline_released", { squad = squad.id, name = squad.name,
            survivors = #survivors, casualties = casualties, task = updated.state })
    end
    return updated
end

local function nearestPlayer(x, y, list)
    local best = math.huge
    for _, p in ipairs(list) do
        local dx, dy = x - p.x, y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < best then best = d end
    end
    return best
end

Render.settings.emptyListReleaseMs = 3000
function Render.shouldRelease(playerCount, distance, aliveRendered, renderedCount, emptyForMs)

    if (tonumber(renderedCount) or 0) > 0 and (tonumber(aliveRendered) or 0) <= 0 then return true end
    if (tonumber(playerCount) or 0) <= 0 then

        return (tonumber(emptyForMs) or 0) >= Render.settings.emptyListReleaseMs
    end
    return (tonumber(distance) or math.huge) > Render.releaseRadius()
end

function Render.pruneDeleted(brief)
    local catalog = ProjectALife.Catalog
    local current = catalog and catalog.current
    if not current or not current.hasDeletions then return false end
    if Render.state.catalogSnapshot ~= current then
        Render.state.catalogSnapshot, Render.state.catalogChecked = current, {}
    end
    local seen = Render.state.catalogChecked[brief.id]
    if seen == brief.revision then return false end
    if brief.profileIds ~= nil then
        local deleted = false
        for _, profile in ipairs(brief.profileIds) do
            if catalog.deletedReason(brief.factionId, profile) then deleted = true; break end
        end
        if not deleted then Render.state.catalogChecked[brief.id] = brief.revision; return false end
    end
    local squad = Ledger.read(brief.id)
    if squad == nil then return false end
    local members, uids, changed = {}, {}, false
    for index, member in ipairs(squad.members or {}) do
        local uid = (squad.renderedUids or {})[index]
        local reason = catalog.deletedReason(squad.factionId, member.profileId)
        if reason then
            changed = true
            local service = ProjectALife.SpawnService
            if uid and registry().read(uid) and (service == nil or not service.retire(uid, reason)) then
                return true 
            end
        else
            members[#members + 1] = member
            if uid then uids[#uids + 1] = uid end
        end
    end
    if changed then
        if #members == 0 then
            Ledger.remove(squad.id, squad.revision, "catalog_deleted")
        else
            Ledger.update(squad.id, squad.revision, function(q)
                q.members, q.renderedUids = members, uids
                local spec = q.stagePending and q.stagePending.specification
                if spec and catalog.deletedReason(spec.factionId, spec.profileId) then q.stagePending = nil end
                if q.releasePending then
                    local survivors = {}
                    for _, member in ipairs(q.releasePending.members or {}) do
                        if not catalog.deletedReason(q.factionId, member.profileId) then survivors[#survivors + 1] = member end
                    end
                    q.releasePending.members = survivors
                end
            end)
        end
        return true
    end
    Render.state.catalogChecked[brief.id] = brief.revision
    return false
end

function Render.retireOutOfSeason(brief, hours)
    if brief.state ~= "offline" or brief.stagePending or brief.releasePending then return false end
    local rules, catalog = ProjectALife.FactionSpawnRules, ProjectALife.Catalog
    if rules == nil or type(rules.inSeason) ~= "function" or catalog == nil
            or type(catalog.faction) ~= "function" then return false end
    local memo, factionId = Render.state.seasonMemo, brief.factionId
    local keep
    if memo ~= nil and factionId ~= nil then keep = memo[factionId] end
    if keep == nil then
        local faction = catalog.faction(factionId)
        keep = faction == nil or rules.inSeason(faction, (tonumber(hours) or worldHours()) / 24)
        if memo ~= nil and factionId ~= nil then memo[factionId] = keep end
    end
    if keep then return false end
    local squad = Ledger.read(brief.id)
    if squad == nil or squad.state ~= "offline"
            or not Ledger.remove(squad.id, squad.revision, "out_of_season") then return false end
    Render.metrics.retiredOutOfSeason = (Render.metrics.retiredOutOfSeason or 0) + 1
    emit("offline_retired", { squad = squad.id, name = squad.name, reason = "out_of_season" })
    return true
end

function Render.relocate(squad, list)
    if squad == nil or type(list) ~= "table" or #list == 0 then return false end
    local px, py, best = nil, nil, math.huge
    for _, player in ipairs(list) do
        local distance = (player.x - squad.x) ^ 2 + (player.y - squad.y) ^ 2
        if distance < best then best, px, py = distance, player.x, player.y end
    end
    if px == nil then return false end
    local dx, dy = squad.x - px, squad.y - py
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then dx, dy, length = 1, 0, 1 end
    local reach = Render.settings.releaseRadius + 10
    local moved = Ledger.update(squad.id, squad.revision, function(q)
        q.x = px + dx / length * reach
        q.y = py + dy / length * reach
        q.stageHead = nil
        q.route = nil
        q.decisionDueHours = 0
        q.relocatedForSpot = (tonumber(q.relocatedForSpot) or 0) + 1
    end)
    if moved == nil then return false end
    Render.metrics.relocated = (Render.metrics.relocated or 0) + 1
    emit("offline_relocated", { squad = squad.id, name = squad.name, reason = "no_spot" })
    return true
end

function Render.travelTilesPerHour()
    local director = ProjectALife.OfflineDirector
    local settings = director ~= nil and director.settings or nil
    return tonumber(settings and settings.travelTilesPerHour) or 150
end

function Render.legWalk(squad, hours, tilesPerHour)
    local route = squad.route
    if type(route) ~= "table" or #route == 0 then return nil end
    local from, started = squad.legFrom, tonumber(squad.legStartedHours)
    if from == nil or Graph.nodes[from] == nil or started == nil then return nil end
    local legHours, popped = tonumber(squad.legHours), 0
    for _ = 1, 8 do
        local to = route[popped + 1]
        local len = (Graph.adjacency[from] or {})[to]
        if len == nil then return nil end
        if legHours == nil then legHours = math.max(0.1, len / math.max(1, tilesPerHour)) end
        local t = (hours - started) / legHours
        if t < 1 or popped + 1 >= #route then
            return { from = from, to = to, t = t, popped = popped, started = started, legHours = legHours }
        end
        popped, from, started, legHours = popped + 1, to, started + legHours, nil
    end
    return { from = from, to = route[popped + 1], t = 0, popped = popped, started = started, atNode = true }
end

function Render.applyWalk(q, walk)
    for _ = 1, walk.popped do table.remove(q.route, 1) end
    q.legFrom, q.legStartedHours, q.legHours = walk.from, walk.started, walk.legHours
    if walk.atNode then
        local node = Graph.nodes[walk.from]
        q.x, q.y, q.nodeId = node.x, node.y, walk.from
    elseif walk.t >= 1 then
        local node = Graph.nodes[walk.to]
        q.x, q.y, q.nodeId = node.x, node.y, nil
    else
        local p = Graph.interpolate(walk.from, walk.to, walk.t)
        if p ~= nil then q.x, q.y = p.x, p.y end
        q.nodeId = nil
    end
end

function Render.catchUp(brief, list, hours)
    if brief.state ~= "offline" or brief.moving ~= true or hours == nil or #list == 0 then return false end
    local radius = Render.tickReach(list)
    local here = nearestPlayer(brief.x, brief.y, list)
    if here <= radius then return false end
    local since = math.max(tonumber(brief.lastSimulatedHours) or -1e9, tonumber(brief.legStartedHours) or -1e9)
    if since <= -1e9 then return false end
    local tilesPerHour = Render.travelTilesPerHour()
    local reach = (hours - since) * tilesPerHour + Render.settings.catchUpSlack
    if here - reach > radius then return false end
    local squad = Ledger.peek(brief.id)
    if squad == nil or squad.revision ~= brief.revision then return false end
    local walk = Render.legWalk(squad, hours, tilesPerHour)
    if walk == nil then return false end
    local a, b = Graph.nodes[walk.from], Graph.nodes[walk.to]
    local t = walk.atNode and 0 or math.max(0, math.min(1, walk.t))
    if nearestPlayer(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, list) > radius then return false end
    local director = ProjectALife.OfflineDirector
    if director ~= nil and type(director.restsTonight) == "function" and director.restsTonight(squad, hours) then
        return false
    end
    local updated = Ledger.update(brief.id, brief.revision, function(q) Render.applyWalk(q, walk) end)
    if updated == nil then return false end
    brief.x, brief.y, brief.revision = updated.x, updated.y, updated.revision
    Render.metrics.caughtUp = (Render.metrics.caughtUp or 0) + 1
    return true
end

function Render.hold(squad, reason, list)
    local metrics = Render.metrics
    metrics.holdBy = metrics.holdBy or {}
    metrics.holdBy[reason] = (metrics.holdBy[reason] or 0) + 1
    metrics.lastHold = tostring(squad.id) .. ":" .. reason .. ":d" .. tostring(math.floor(Render.nearestOf(squad.x, squad.y, list)))
    return false
end

function Render.stageGate(squad, list, hours)
    if not Render.stageAllowed(squad, hours) then return Render.hold(squad, "stage_density", list) end
    if Render.driverNearest(squad.x, squad.y, list) then return Render.hold(squad, "player_driving", list) end
    if Render.floorHeld(squad.x, squad.y, list) then return Render.hold(squad, "floor_held", list) end
    local pressure = ProjectALife.WorldPressure
    if pressure ~= nil and pressure.crowded(squad.x, squad.y, hours, { squad = squad.id }) then
        return Render.hold(squad, "crowded", list)
    end
    return true
end

function Render.tick(hours)
    local list = players()
    local now = nowMs()

    local combat = ProjectALife.OfflineCombat
    if combat ~= nil and type(combat.drain) == "function" and type(combat.pending) == "table"
            and combat.pending[combat.pendingHead or 1] ~= nil then
        pcall(combat.drain, hours or worldHours(), list)
    end

    if #list > 0 then
        Render.state.emptySinceMs = nil
    elseif Render.state.emptySinceMs == nil then
        Render.state.emptySinceMs = now
    end
    local emptyForMs = Render.state.emptySinceMs ~= nil and (now - Render.state.emptySinceMs) or 0
    local work, attempts = 0, 0
    local state = Render.state
    state.tickList, state.tickReach, state.seasonMemo = list, nil, {}
    local brief = Ledger.briefs()
    local liveIds = {}
    for _, squad in ipairs(brief) do liveIds[squad.id] = true end
    for id in pairs(Render.state.catalogChecked) do
        if not liveIds[id] then Render.state.catalogChecked[id] = nil end
    end
    for _ = 1, #brief do
        if Render.state.cursor > #brief then Render.state.cursor = 1 end
        local squad = brief[Render.state.cursor]
        Render.state.cursor = Render.state.cursor + 1
        if squad.moving and Render.catchUp(squad, list, hours) then attempts = attempts + 1 end
        local distance = nearestPlayer(squad.x, squad.y, list)

        local aliveRendered = 0
        for _, uid in ipairs(squad.renderedUids or {}) do
            local record = (registry().peek or registry().read)(uid)
            if record ~= nil and record.lifecycle ~= "dead" then
                aliveRendered = aliveRendered + 1
                local p = record.worldPosition
                if p then distance = math.min(distance, nearestPlayer(p.x, p.y, list)) end
            end
        end
        if Render.pruneDeleted(squad) or Render.retireOutOfSeason(squad, hours) then
            attempts, work = attempts + 1, work + 1
        elseif squad.stagePending ~= nil then
            attempts = attempts + 1
            if finishStage(Ledger.read(squad.id)) then
                Render.state.lastStageMs[squad.id] = now
                work = work + 1
            end
        elseif squad.releasePending ~= nil then
            attempts = attempts + 1
            if release(Ledger.read(squad.id), hours or worldHours()) ~= nil then work = work + 1 end
        elseif (squad.state == "rendered" or squad.state == "staging")
                and Render.shouldRelease(#list, distance, aliveRendered, #(squad.renderedUids or {}), emptyForMs) then
            attempts = attempts + 1
            if release(Ledger.read(squad.id), hours or worldHours()) ~= nil then work = work + 1 end
        elseif squad.state == "offline" and #list > 0
                and nearestPlayer(squad.x, squad.y, list) <= Render.tickReach(list)
                and squad.memberCount > 0
                and Render.stageGate(squad, list, hours or worldHours()) then
            attempts = attempts + 1
            local ok, reason = stageOne(Ledger.read(squad.id), list, now)
            Render.state.noSpot = Render.state.noSpot or {}
            if not ok then Render.hold(squad, "stage:" .. tostring(reason), list) end
            if ok then
                Render.state.lastStageMs[squad.id] = now
                Render.state.noSpot[squad.id] = nil
                work = work + 1
                emit("offline_staging", { squad = squad.id, name = squad.name })
            elseif reason == "no_spot" then

                local misses = (Render.state.noSpot[squad.id] or 0) + 1
                Render.state.noSpot[squad.id] = misses
                if misses >= Render.settings.noSpotRelocateTries then
                    Render.state.noSpot[squad.id] = nil
                    if Render.relocate(Ledger.read(squad.id), list) then work = work + 1 end
                end
            end
        elseif squad.state == "staging" then
            local last = Render.state.lastStageMs[squad.id] or 0
            if now - last >= Render.settings.stageIntervalMs then
                attempts = attempts + 1
                local ok, result = stageOne(Ledger.read(squad.id), list, now)
                if ok then
                    Render.state.lastStageMs[squad.id] = now
                    work = work + 1
                elseif result == "all_staged" then
                    Ledger.update(squad.id, squad.revision, function(q) q.state = "rendered" end, true)
                    Render.metrics.rendered = Render.metrics.rendered + 1
                    emit("offline_rendered", { squad = squad.id, name = squad.name })
                    work = work + 1
                end
            end
        end

        if attempts >= Render.settings.transitionsPerTick then break end
    end
    state.tickList, state.tickReach, state.seasonMemo = nil, nil, nil
    return work
end

return Render
