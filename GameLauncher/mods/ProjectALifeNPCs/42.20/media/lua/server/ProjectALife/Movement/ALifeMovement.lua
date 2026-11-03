require "ProjectALife/Movement/ALifeObstacleTraversal"
require "ProjectALife/Movement/ALifeEntrances"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Shells/ALifeGait"

ProjectALife = ProjectALife or {}

local Ledger = ProjectALife.ActionLedger
local Traversal = ProjectALife.ObstacleTraversal
local Animations = ProjectALife.Animations
local BehaviorSettings = ProjectALife.BehaviorSettings
local Gait = ProjectALife.Gait
local Movement = {
    adapters = {}, sequence = 0,

    allowRun = true,
    runWindows = setmetatable({}, { __mode = "k" }),
    metrics = { requested = 0, requestErrors = 0, stalls = 0,
        traversalFailures = 0, unreachableFailures = 0, flooded = 0, lastFailure = nil,
        replans = 0, goalsRefused = 0, climbSettleHolds = 0, frozenSteps = 0, frozenGiveUps = 0 },

    maximumReplans = 3,
    goalRefusalMs = 60000,

    climbSettleMs = 30000,

    replanRepeatMs = 3000,
    refusedGoals = {},
}
ProjectALife.Movement = Movement

local function requestedPace(value)

    if value == "sprint" then return "sprint" end

    if value == "guard" then return "guard" end
    return value == "run" and "run" or "walk"
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function validTarget(target)
    return type(target) == "table" and finite(target.x)
        and finite(target.y) and finite(target.z)
end

local function nowMs()
    if type(Movement.adapters.nowMs) == "function" then return Movement.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Movement.dataOf(shell)
    local kind = type(shell)
    if (kind ~= "table" and kind ~= "userdata") or shell.getModData == nil then return nil end
    local data = shell:getModData()
    if type(data) ~= "table" then return nil end
    return data
end

local function position(shell)
    if type(Movement.adapters.position) == "function" then
        return Movement.adapters.position(shell)
    end
    local kind = type(shell)
    if (kind ~= "table" and kind ~= "userdata") or shell.getX == nil
            or shell.getY == nil or shell.getZ == nil then
        return nil
    end
    return { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
end

function Movement.pathPhase(shell)
    if type(Movement.adapters.pathPhase) == "function" then
        local phase = Movement.adapters.pathPhase(shell)
        if phase == "started" or phase == "pending" or phase == "cancelled"
                or phase == "failed" then return phase end
        return "unknown"
    end

    if type(Movement.adapters.issuePath) == "function" then return "started" end
    if type(isServer) == "function" and isServer() then

        local data = Movement.dataOf(shell)
        local active = data ~= nil and data.ProjectALifePathActive == true
        return active and "pending" or "cancelled"
    end
    if shell == nil or shell.getPathFindBehavior2 == nil then return "unknown" end
    local behavior = shell:getPathFindBehavior2()
    local started, cancelled, pending = false, true, false
    if behavior ~= nil then
        if behavior.hasStartedMoving == nil or behavior.getIsCancelled == nil
                or shell.getVariableBoolean == nil then
            return "unknown"
        end
        started = behavior:hasStartedMoving() == true
        cancelled = behavior:getIsCancelled() == true
        pending = shell:getVariableBoolean("bPathfind") == true
    end
    if cancelled then return "cancelled" end

    if shell.getCurrentState ~= nil and ZombieIdleState ~= nil
            and shell:getCurrentState() == ZombieIdleState.instance() then return "failed" end
    if started then return "started" end
    if pending then return "pending" end
    return "failed"
end

function Movement.setPathActive(shell, active)
    if shell == nil then return false end
    return pcall(function()
        local data = shell:getModData()
        if type(data) == "table" then
            data.ProjectALifePathActive = active == true and true or nil
            data.ProjectALifePathRevision = (tonumber(data.ProjectALifePathRevision) or 0) + 1
        end
        if type(isServer) == "function" and isServer() then Animations.syncState(shell) end
    end)
end

function Movement.sprintActive(shell, suppliedNow)
    local data = Movement.dataOf(shell)
    if data == nil then return false end
    return (tonumber(suppliedNow) or nowMs())
        < (tonumber(data.ProjectALifeSprintUntilMs) or 0)
end

local function setVariable(shell, name, value)
    if shell == nil then return end
    if shell.SetVariable ~= nil then
        shell:SetVariable(name, tostring(value))
    elseif shell.setVariable ~= nil then
        shell:setVariable(name, tostring(value))
    end
end

local function resolvePace(shell, requested, timestamp)
    if not Movement.allowRun then return "walk" end

    local data = Movement.dataOf(shell)
    local flightUntil = data ~= nil and tonumber(data.ProjectALifeFlightUntilMs) or nil
    if flightUntil ~= nil and timestamp < flightUntil and data.ProjectALifeWoundLeg ~= true then
        if (tonumber(data.ProjectALifeEndurance) or 1) > 0.5 then
            return data.ProjectALifeFlightPace == "run" and "run" or "sprint"
        end
        return "walk"
    end
    if data ~= nil and data.ProjectALifeSweepSlow == true and requested ~= "sprint" then return "walk" end
    local hitRun = data ~= nil
        and timestamp < (tonumber(data.ProjectALifeHitRunUntilMs) or 0)
        and data.ProjectALifeWoundLeg ~= true and data.ProjectALifeDownedUntilMs == nil
        and data.ProjectALifeBleedOutAtMs == nil
        and (tonumber(data.ProjectALifeEndurance) or 100) > 15
    if hitRun and requested ~= "guard" then return "run" end
    if requested ~= "run" and requested ~= "sprint" then return "walk" end
    local settings = BehaviorSettings.movement or {}
    local activeMs = math.max(250, math.floor(tonumber(settings.runActiveMs) or 650))
    local cycleMs = math.max(activeMs, math.floor(tonumber(settings.runCycleMs) or 14000))

    local endurance = data ~= nil and tonumber(data.ProjectALifeEndurance) or nil
    local sprintUntil = data ~= nil and tonumber(data.ProjectALifeSprintUntilMs) or nil
    local minimum = tonumber((BehaviorSettings.endurance or {}).sprintMinimum) or 34

    local winded = endurance ~= nil and endurance < minimum

    if data ~= nil and data.ProjectALifeWoundLeg == true then return "walk" end

    if settings.sprintEnabled ~= false
            and not winded and sprintUntil ~= nil and timestamp < sprintUntil then

        if Gait == nil then return "sprint" end
        return Gait.burstPace(shell)
    end

    local posture = data ~= nil and data.ProjectALifeDangerPosture or nil
    if posture ~= nil and posture ~= "relaxed" then
        local jogMinimum = tonumber(
            (BehaviorSettings.endurance or {}).jogMinimum) or 15
        if endurance == nil or endurance > jogMinimum then return "run" end
        return "walk"
    end
    if winded then return "walk" end
    local state = Movement.runWindows[shell]
    if state == nil then
        state = { cycleStartedAtMs = timestamp }
        Movement.runWindows[shell] = state
    end
    local elapsed = math.max(0, timestamp - state.cycleStartedAtMs)
    if elapsed >= cycleMs then
        state.cycleStartedAtMs = state.cycleStartedAtMs
            + math.floor(elapsed / cycleMs) * cycleMs
        elapsed = timestamp - state.cycleStartedAtMs
    end
    return elapsed < activeMs and "run" or "walk"
end

function Movement.setPace(shell, pace)
    if shell == nil then return false end
    local requested = requestedPace(pace)
    local effective = resolvePace(shell, requested, nowMs())
    local changed = false
    setVariable(shell, "ALifePace", effective)

    local data = Movement.dataOf(shell)
    if data ~= nil then
        changed = data.ProjectALifePace ~= effective
        data.ProjectALifeRequestedPace = requested
        data.ProjectALifePace = effective
    end

    local runningOk = shell.setRunning ~= nil
    if runningOk then shell:setRunning(false) end
    local sprintingOk = shell.setSprinting ~= nil
    if sprintingOk then shell:setSprinting(false) end
    if changed then pcall(Animations.syncState, shell) end
    return runningOk and sprintingOk
end

function Movement.refreshPace(shell)
    if shell == nil then return false end
    local data = Movement.dataOf(shell)
    local requested = requestedPace(data ~= nil and data.ProjectALifeRequestedPace or nil)
    return Movement.setPace(shell, requested)
end

function Movement.safeDestination(actor, shell, target)
    local campfires = ProjectALife.Campfires
    if campfires == nil or type(campfires.safeStep) ~= "function" then return target end
    if actor == nil then
        local registry = ProjectALife.ActorRegistry
        local data = Movement.dataOf(shell)
        local uid = data ~= nil and data.ProjectALifeUID or nil
        if registry ~= nil and uid ~= nil then actor = (registry.peek or registry.read)(uid) end
    end
    if actor == nil then return target end
    local here = position(shell)
    if here == nil then return target end
    return campfires.safeStep(actor, here, target)
end

local function requestPath(shell, behavior, x, y, z)

    behavior:pathToLocationF(x, y, z)
end

local function retarget(shell, target, pace)
    if Movement.pathPhase(shell) ~= "started" then return false end
    if type(Movement.adapters.issuePath) == "function" then return false end

    if Animations.current[shell] ~= nil then return false end
    if shell.getCurrentState and ZombieIdleState ~= nil
            and shell:getCurrentState() == ZombieIdleState.instance() then return false end
    Movement.setPace(shell, pace)
    local ok = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior == nil then error("path_behavior_unavailable") end
        requestPath(shell, behavior, target.x, target.y, target.z)

        pcall(function() shell:setVariable("bPathfind", true) end)
        if PathFindState ~= nil then
            shell:changeState(PathFindState.instance())
        end
    end)
    if ok then
        Movement.metrics.requested = Movement.metrics.requested + 1
        Movement.setPathActive(shell, true)
    end
    return ok
end

Movement.issueLog = setmetatable({}, { __mode = "k" })
Movement.issueFloodPerSecond = 6
Movement.floodRetryMs = 1000
Movement.stallRefusalMs = 3000
function Movement.pathFlooded(shell, now)
    if shell == nil then return false end
    now = tonumber(now) or nowMs()
    local log = Movement.issueLog[shell]
    if log == nil or now - log.sinceMs >= 1000 then
        Movement.issueLog[shell] = { sinceMs = now, count = 1, noted = false }
        return false
    end
    log.count = log.count + 1
    if log.count <= Movement.issueFloodPerSecond then return false end
    if not log.noted then
        log.noted = true
        pcall(function()
            local blackBox = ProjectALife.BlackBox
            if blackBox ~= nil then
                blackBox.note(shell, "path-flood", tostring(log.count) .. " path issues in one second")
            end
        end)
    end
    return true
end

function Movement.legSafe(shell, target)
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.legHazard) ~= "function" then return true end
    local ok, hazard = pcall(caution.legHazard, shell, target)
    if not ok then return true end
    return hazard == nil, hazard
end

local function issue(shell, target, pace)
    if Animations.blocksLocomotion(shell) then return false end
    local safe, hazard = Movement.legSafe(shell, target)
    if not safe then return false, hazard end
    if retarget(shell, target, pace) then return true end
    if Movement.pathFlooded(shell, nowMs()) then
        Movement.metrics.flooded = (Movement.metrics.flooded or 0) + 1

        return false, "flooded"
    end
    Movement.metrics.requested = Movement.metrics.requested + 1
    Animations.cancelForLocomotion(shell)

    pcall(function() shell:setTarget(nil) end)
    pcall(function() shell:setUseless(true) end)
    Movement.setPace(shell, pace)
    if type(Movement.adapters.issuePath) == "function" then
        local accepted = Movement.adapters.issuePath(shell, target, pace) == true
        Movement.setPathActive(shell, accepted)
        if not accepted then
            Movement.metrics.requestErrors = Movement.metrics.requestErrors + 1
            pcall(function() shell:setUseless(true) end)
        end
        return accepted
    end

    local ok = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior == nil then error("path_behavior_unavailable") end
        behavior:cancel()
        pcall(function() behavior:reset() end)
        pcall(function() shell:setPath2(nil) end)
        pcall(function() shell:setTarget(nil) end)
        pcall(function() shell:clearAggroList() end)
        requestPath(shell, behavior, target.x, target.y, target.z)

        pcall(function() shell:setVariable("bPathfind", true) end)
        if PathFindState ~= nil then
            shell:changeState(PathFindState.instance())
        end
    end)
    if not ok then
        Movement.metrics.requestErrors = Movement.metrics.requestErrors + 1
        pcall(function() shell:setUseless(true) end)
        Movement.setPathActive(shell, false)
    else
        Movement.setPathActive(shell, true)
        ProjectALife.TraversalHands.prepare(shell)
    end
    return ok
end

local enterOwnedIdle

local function cancelPathOnly(shell)
    if type(Traversal.holdsClimb) == "function" and Traversal.holdsClimb(shell) then
        Traversal.count("climbHeld")
        Movement.setPathActive(shell, false)
        return true
    end
    Traversal.cancel(shell, "movement_repath")
    Movement.setPathActive(shell, false)
    if type(Movement.adapters.cancelPath) == "function" then
        return Movement.adapters.cancelPath(shell) ~= false
    end
    return pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior ~= nil then behavior:cancel() end
        pcall(function() shell:setVariable("bPathfind", false) end)
    end)
end

Movement.cancelPathOnly = cancelPathOnly

local function cancel(shell)
    if type(Traversal.holdsClimb) == "function" and Traversal.holdsClimb(shell) then
        Traversal.count("climbHeld")
        Movement.setPathActive(shell, false)
        return true
    end
    Traversal.cancel(shell, "movement_stop")
    Movement.setPathActive(shell, false)
    if type(Movement.adapters.cancelPath) == "function" then
        local cancelled = Movement.adapters.cancelPath(shell) ~= false
        pcall(function() shell:setUseless(true) end)
        Movement.setPace(shell, "walk")
        enterOwnedIdle(shell)
        return cancelled
    end
    local ok = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior ~= nil then behavior:cancel() end
        shell:setMoving(false)
        pcall(function() shell:setVariable("bMoving", false) end)
        pcall(function() shell:setVariable("bPathfind", false) end)
    end)
    pcall(function() shell:setUseless(true) end)
    Movement.setPace(shell, "walk")
    enterOwnedIdle(shell)
    return ok
end

enterOwnedIdle = function(shell)

    Movement.setPathActive(shell, false)
    if Animations.blocksLocomotion(shell) then return end
    Animations.clear(shell)
    pcall(function() shell:setTarget(nil) end)
    pcall(function() shell:setUseless(true) end)
    if ZombieIdleState ~= nil then
        pcall(function() shell:changeState(ZombieIdleState.instance()) end)
    end
    pcall(function() shell:setMoving(false) end)
    pcall(function() shell:setVariable("bMoving", false) end)
    pcall(function() shell:setVariable("bPathfind", false) end)
end

function Movement.stop(shell)
    if shell == nil then return false end
    return cancel(shell)
end

local function arrived(shell, target, tolerance)
    local current = position(shell)
    if current == nil then return false end
    local dx, dy, dz = current.x - target.x, current.y - target.y, current.z - target.z
    return dx * dx + dy * dy + dz * dz <= tolerance * tolerance
end

local function adminPolicy(actor, shell)
    local memory = type(actor) == "table" and actor.memory or nil
    local admin = type(memory) == "table" and memory.admin or nil
    admin = type(admin) == "table" and admin or nil
    local data = Movement.dataOf(shell)
    if data == nil or data.ProjectALifeAdminManaged ~= true then return admin end
    admin = {
        stationary = data.ProjectALifeAdminStationary == true,
    }
    local radius = tonumber(data.ProjectALifeLeashRadius)
    if radius ~= nil and radius > 0 then
        admin.leash = {
            x = tonumber(data.ProjectALifeLeashX) or (shell.getX ~= nil and shell:getX() or nil),
            y = tonumber(data.ProjectALifeLeashY) or (shell.getY ~= nil and shell:getY() or nil),
            z = tonumber(data.ProjectALifeLeashZ) or (shell.getZ ~= nil and shell:getZ() or nil),
            radius = math.min(100, radius),
        }
    end
    return admin
end

function Movement.adminDestination(actor, shell, target)
    if not validTarget(target) then return nil, "movement_target_invalid" end
    local memory = type(actor) == "table" and actor.memory or nil
    local bounds = type(memory) == "table" and memory.garrisonBounds or nil
    if type(bounds) == "table" and memory.outpostSquadId == nil then
        local x1, y1, x2, y2 = tonumber(bounds.x1), tonumber(bounds.y1),
            tonumber(bounds.x2), tonumber(bounds.y2)
        if finite(x1) and finite(y1) and finite(x2) and finite(y2)
                and x2 > x1 + 2 and y2 > y1 + 2 then
            target = { x = math.max(x1 + 1.5, math.min(x2 - 0.5, target.x)),
                y = math.max(y1 + 1.5, math.min(y2 - 0.5, target.y)), z = target.z }
        end
    end
    local admin = adminPolicy(actor, shell)
    if type(admin) ~= "table" then
        return { x = target.x, y = target.y, z = target.z }
    end
    if admin.stationary == true then return nil, "admin_stationary" end
    local leash = type(admin.leash) == "table" and admin.leash or nil
    local radius = leash and math.max(0, math.min(100,
        tonumber(leash.radius) or 0)) or 0
    if radius <= 0 then return { x = target.x, y = target.y, z = target.z } end
    local x, y = tonumber(leash.x), tonumber(leash.y)
    if not finite(x) or not finite(y) then
        return { x = target.x, y = target.y, z = target.z }
    end
    local dx, dy = target.x - x, target.y - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= radius or distance < 0.0001 then
        return { x = target.x, y = target.y, z = target.z }
    end
    return {
        x = x + dx / distance * radius,
        y = y + dy / distance * radius,
        z = target.z,
    }, "admin_leash_clamped"
end

function Movement.configure(adapters)
    Movement.adapters = adapters or {}
    Movement.runWindows = setmetatable({}, { __mode = "k" })
    Movement.metrics = { requested = 0, requestErrors = 0, stalls = 0,
        traversalFailures = 0, unreachableFailures = 0, flooded = 0, lastFailure = nil,
        replans = 0, goalsRefused = 0, climbSettleHolds = 0, frozenSteps = 0, frozenGiveUps = 0 }
    Movement.refusedGoals = {}
    Traversal.configure(Movement.adapters.traversal)
end

function Movement.noClimb(actor)
    local scripted = ProjectALife.ScriptedEncounter
    if scripted == nil or type(scripted.value) ~= "function" then return false end
    return scripted.value(actor, "noClimb", false) == true
end

function Movement.pathWhy(shell, why)
    if type(why) ~= "string" then return end
    Movement.metrics.pathWhy = why
    local data = Movement.dataOf(shell)
    if data == nil or data.ProjectALifePathWhy == why then return end
    data.ProjectALifePathWhy = why
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled and type(blackBox.note) == "function" then
        blackBox.note(shell, "path-why", why)
    end
end

function Movement.climbSettling(shell, now)
    if type(Traversal.stampedRefusal) ~= "function" then return false end
    local record = Traversal.stampedRefusal(shell)
    if record == nil or record.stampKind ~= "posted" then return false end
    if record.stampKind == "posted" and record.stampEdgeKey ~= nil then return false end
    local at = tonumber(record.stampAtMs)
    now = tonumber(now) or 0
    return at ~= nil and now >= at and now - at < Movement.climbSettleMs
end

function Movement.refuseGoal(uid, goal, now, forMs)
    if type(uid) ~= "string" or not validTarget(goal) then return end
    Movement.refusedGoals[uid] = { x = goal.x, y = goal.y, z = goal.z,
        untilMs = (tonumber(now) or nowMs()) + (tonumber(forMs) or Movement.goalRefusalMs) }
end

function Movement.goalRefused(uid, goal, now)
    local refused = type(uid) == "string" and Movement.refusedGoals[uid] or nil
    if refused == nil or not validTarget(goal) then return false end
    if (tonumber(now) or nowMs()) >= refused.untilMs then
        Movement.refusedGoals[uid] = nil
        return false
    end
    local dx, dy = goal.x - refused.x, goal.y - refused.y
    return math.abs(goal.z - refused.z) < 0.5 and dx * dx + dy * dy <= 2.25
end

function Movement.patrolBlocked(shell, goal, now)
    if shell == nil or not validTarget(goal) then return false end
    now = tonumber(now) or nowMs()
    local sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
    if math.abs(sz - goal.z) >= 0.4 then return false end
    local dx, dy = goal.x - sx, goal.y - sy
    for key, untilMs in pairs(Traversal.edgeBans) do
        if untilMs > now then
            local x1, y1, x2, y2, z = Traversal.edgeEnds(key)
            if x1 ~= nil and math.abs(z - sz) < 0.4 then
                local mx, my = (x1 + x2 + 1) / 2, (y1 + y2 + 1) / 2
                local t, cross
                if x1 ~= x2 and math.abs(dx) > 0.001 then
                    t = (mx - sx) / dx
                    cross = math.abs(sy + dy * t - my) <= 0.5
                elseif y1 ~= y2 and math.abs(dy) > 0.001 then
                    t = (my - sy) / dy
                    cross = math.abs(sx + dx * t - mx) <= 0.5
                end
                if cross and t >= 0 and t <= 1 then return true, key end
            end
        end
    end
    return false
end

function Movement.windowCheck(shell, now)
    if type(Traversal.takeReplan) ~= "function" then return nil end
    local key = Traversal.takeReplan(shell, now)
    if key == nil and type(Traversal.windowDwelled) == "function" then
        key = Traversal.windowDwelled(shell, now)
    end
    return key
end

function Movement.entranceAround(actor, shell, goal, edgeKey, now, doorsOnly)
    local entrances = ProjectALife.Entrances
    if entrances == nil or type(entrances.claim) ~= "function" or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local square = cell:getGridSquare(math.floor(goal.x), math.floor(goal.y), math.floor(goal.z))
    local building = square ~= nil and square:getBuilding() or nil
    if building == nil then return nil end
    local here = shell:getCurrentSquare()
    if here ~= nil and here:getBuilding() == building then return nil end
    local opening = entrances.claim(actor, shell, building, now, doorsOnly == true)
    if opening == nil or opening.edgeKey == edgeKey then return nil end
    local dx, dy = opening.x - shell:getX(), opening.y - shell:getY()
    if dx * dx + dy * dy > 2.25 then return { x = opening.x, y = opening.y, z = opening.z } end
    if tonumber(opening.ix) ~= nil then return { x = opening.ix, y = opening.iy, z = opening.z } end
    return nil
end

function Movement.onSquare(shell, point)
    local here = position(shell)
    return here ~= nil and math.floor(here.x) == math.floor(point.x)
        and math.floor(here.y) == math.floor(point.y)
end

function Movement.replanAround(walk, actor, shell, goal, edgeKey, now, doorsOnly)
    if walk.route ~= nil and walk.replanKey == edgeKey
            and now - (tonumber(walk.replanAtMs) or 0) < Movement.replanRepeatMs then
        return walk.route, walk.at
    end
    local priorKey, priorAtMs = walk.replanKey, walk.replanAtMs
    walk.replans = (walk.replans or 0) + 1
    if walk.replans > Movement.maximumReplans then return nil end
    walk.replanKey, walk.replanAtMs = edgeKey, now

    local route, deferred
    if type(Traversal.wayRound) == "function" then
        route, deferred = Traversal.wayRound(shell, edgeKey, goal, doorsOnly == true, true)
    elseif type(Traversal.detourRoute) == "function" then
        route, deferred = Traversal.detourRoute(shell, edgeKey, doorsOnly == true, true)
    end
    if deferred == "deferred" then
        walk.replans, walk.replanKey, walk.replanAtMs = walk.replans - 1, priorKey, priorAtMs
        return nil, "deferred"
    end
    if type(route) == "table" and route[1] ~= nil then return route end
    local ok, point = pcall(Movement.entranceAround, actor, shell, goal, edgeKey, now, doorsOnly)
    if ok and point ~= nil then return { point } end
    return nil
end

Movement.frozenMs = 2000
Movement.frozenEpsilon = 0.02
Movement.frozenGapMs = 1000
Movement.maximumFrozenSteps = 2
Movement.frozenRefusalMs = 15000
Movement.frozenRadius = 4
Movement.frozenRouteSquares = 3

function Movement.bodyWalking(shell)
    if shell == nil or type(shell.isMoving) ~= "function" then return nil end
    return shell:isMoving() == true
end

function Movement.frozenHeld(shell, now)
    if Traversal.active[shell] ~= nil then return true end
    if type(Traversal.refusalWait) == "function" then
        if Traversal.refusalWait(shell, now, true) == "wait" then return true end
    end
    local touch = nil
    if Traversal.windowTouch ~= nil then touch = Traversal.windowTouch[shell] end
    return touch ~= nil and touch.key ~= nil
        and now - (tonumber(touch.lastMs) or 0) <= Traversal.settings.windowDwellMs
end

function Movement.furnitureAhead(here, target)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local x, y, z = math.floor(here.x), math.floor(here.y), math.floor(here.z)
    local square = cell:getGridSquare(x, y, z)
    if square == nil then return nil end
    local dx, dy = target.x - here.x, target.y - here.y
    local sx, sy = 0, 0
    if dx > 0.05 then sx = 1 elseif dx < -0.05 then sx = -1 end
    if dy > 0.05 then sy = 1 elseif dy < -0.05 then sy = -1 end
    local ax, ay = sx, 0
    if math.abs(dy) > math.abs(dx) then ax, ay = 0, sy end
    if ax == 0 and ay == 0 then return nil end
    local ahead = cell:getGridSquare(x + ax, y + ay, z)
    if ahead ~= nil and not Traversal.detourWalkable(ahead) then return ahead end
    local diagonal = cell:getGridSquare(x + sx, y + sy, z)
    if diagonal ~= nil and not Traversal.detourWalkable(diagonal) then return diagonal end
    if not Traversal.detourWalkable(square) then return square end
    return nil
end

function Movement.frozenRoute(here, target, tried, shell, now)
    if type(getCell) ~= "function" or type(Traversal.detourStep) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local sx, sy, z = math.floor(here.x), math.floor(here.y), math.floor(here.z)
    local start = cell:getGridSquare(sx, sy, z)
    if start == nil then return nil end
    local radius, steps = Movement.frozenRadius, Traversal.detourSteps
    local qx, qy, qp, squares = { sx }, { sy }, { 0 }, { start }
    local seen = { [sx .. ":" .. sy] = true }
    local best, bestScore, head = nil, nil, 1
    while head <= #qx do
        for index = 1, 4 do
            local tx, ty = qx[head] + steps[index][1], qy[head] + steps[index][2]
            local key = tx .. ":" .. ty
            if seen[key] == nil and math.abs(tx - sx) <= radius and math.abs(ty - sy) <= radius
                    and not (head == 1 and tried[key] == true) then
                local there = cell:getGridSquare(tx, ty, z)
                local step = nil
                if there ~= nil and Traversal.detourWalkable(there) then
                    step = Traversal.detourStep(squares[head], there, nil, false, shell, now)
                end
                if step ~= nil then
                    seen[key] = true
                    local n = #qx + 1
                    qx[n], qy[n], qp[n], squares[n] = tx, ty, head, there
                    local ox, oy = tx + 0.5 - target.x, ty + 0.5 - target.y
                    local score = ox * ox + oy * oy
                    if bestScore == nil or score < bestScore then best, bestScore = n, score end
                end
            end
        end
        head = head + 1
    end
    if best == nil then return nil end
    local chain, at = {}, best
    while at > 1 do
        chain[#chain + 1] = at
        at = qp[at]
    end
    local route = {}
    for index = #chain, math.max(1, #chain - Movement.frozenRouteSquares + 1), -1 do
        local node = chain[index]
        route[#route + 1] = { x = qx[node] + 0.5, y = qy[node] + 0.5, z = z }
    end
    local first = chain[#chain]
    return route, qx[first] .. ":" .. qy[first]
end

function Movement.furnitureText(square)
    local text = tostring(square:getX()) .. "," .. tostring(square:getY())
    local flags = IsoFlagType
    if flags == nil or flags.solidtrans == nil or type(square.getObjects) ~= "function" then return text end
    local objects = square:getObjects()
    if objects == nil or type(objects.size) ~= "function" then return text end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local sprite, props = nil, nil
        if object ~= nil and type(object.getSprite) == "function" then sprite = object:getSprite() end
        if sprite ~= nil and type(sprite.getProperties) == "function" then props = sprite:getProperties() end
        if props ~= nil and type(props.has) == "function" and (props:has(flags.solidtrans)
                or (flags.solid ~= nil and props:has(flags.solid))) then
            return text .. ":" .. tostring(sprite:getName())
        end
    end
    return text
end

function Movement.noteFrozen(shell, what, here, goal, walking, furniture, via)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or blackBox.enabled ~= true or type(blackBox.note) ~= "function" then return end
    local text = string.format("%s at=%.1f,%.1f goal=%.1f,%.1f moving=%s", what, here.x, here.y,
        goal.x, goal.y, tostring(walking))
    if furniture ~= nil then text = text .. " furniture=" .. Movement.furnitureText(furniture) end
    if via ~= nil then text = text .. string.format(" via=%.1f,%.1f", via.x, via.y) end
    pcall(blackBox.note, shell, "walk-frozen", text)
end

function Movement.frozenCheck(walk, actor, shell, target, now)
    local here = position(shell)
    if here == nil or not validTarget(target) then return nil end
    local frozen = walk.frozen
    if frozen == nil then
        walk.frozen = { x = here.x, y = here.y, atMs = now, steps = 0, tried = {} }
        return nil
    end

    local gap = now - (tonumber(frozen.seenAtMs) or now)
    frozen.seenAtMs = now
    local dx, dy = here.x - frozen.x, here.y - frozen.y
    if dx * dx + dy * dy > Movement.frozenEpsilon or gap > Movement.frozenGapMs
            or Movement.frozenHeld(shell, now) then
        frozen.x, frozen.y, frozen.atMs = here.x, here.y, now
        return nil
    end
    if now - frozen.atMs < (tonumber(walk.frozenMs) or Movement.frozenMs) then return nil end
    frozen.atMs = now
    local walking = Movement.bodyWalking(shell)
    if walking ~= false then return nil end

    local furniture = Movement.furnitureAhead(here, target)
    local goal = walk.goal or target
    local route, first = nil, nil
    if frozen.steps < Movement.maximumFrozenSteps then
        route, first = Movement.frozenRoute(here, goal, frozen.tried, shell, now)
    end
    if route ~= nil then
        frozen.steps = frozen.steps + 1
        frozen.tried[first] = true
        walk.goal, walk.route, walk.at, walk.replanKey = goal, route, 1, nil
        Movement.metrics.frozenSteps = (Movement.metrics.frozenSteps or 0) + 1
        Movement.noteFrozen(shell, "step " .. frozen.steps, here, goal, walking, furniture, route[1])
        return "step", route[1]
    end
    Movement.metrics.frozenGiveUps = (Movement.metrics.frozenGiveUps or 0) + 1
    Movement.metrics.lastFailure = "movement_frozen"
    Movement.refuseGoal(actor.uid, walk.requested, now, Movement.frozenRefusalMs)
    Movement.noteFrozen(shell, "give_up after " .. frozen.steps, here, goal, walking, furniture, nil)
    return "give_up"
end

function Movement.doorDecision(reason)
    return type(reason) == "string" and (string.find(reason, "door", 1, true) ~= nil
        or string.find(reason, "breach", 1, true) ~= nil)
end

local function softTraversalRefusal(reason)
    return reason ~= nil
        and (string.sub(reason, -8) == "_reroute"
            or reason == "traversal_lockout"
            or reason == "traversal_contact_blocked"
            or reason == "climb_landing_occupied"
            or reason == "fence_start_rejected"
            or reason == "window_start_rejected"
            or reason == "window_climb_unavailable"
            or reason == "window_frame_climb_unavailable"
            or reason == "window_locked"
            or reason == "fence_on_stairs"
            or reason == "breach_claimed"
            or reason == "door_locked_search"
            or reason == "posted_no_climb")
end

function Movement.begin(actor, shell, target, options)
    options = options or {}
    if type(actor) ~= "table" or type(actor.uid) ~= "string"
            or type(actor.generation) ~= "number" or shell == nil
            or not validTarget(target) then
        return nil, "movement_specification_invalid"
    end
    if Animations.blocksLocomotion(shell) then return nil, "movement_ground_recovery" end
    if Movement.goalRefused(actor.uid, target, nowMs()) then
        Movement.metrics.goalsRefused = (Movement.metrics.goalsRefused or 0) + 1
        return nil, "movement_goal_refused"
    end

    if options.doorsOnly ~= true and Movement.noClimb(actor) then
        options.doorsOnly = true
    end

    if options.doorsOnly == true and Movement.climbSettling(shell, nowMs()) then
        Movement.metrics.climbSettleHolds = (Movement.metrics.climbSettleHolds or 0) + 1
        return nil, "movement_climb_settle"
    end

    local requested = { x = target.x, y = target.y, z = target.z }
    local restricted, restriction = Movement.adminDestination(actor, shell, target)
    if restricted == nil then
        Movement.stop(shell)
        return nil, restriction
    end
    target = restricted

    if options.entranceClaim ~= false then
        pcall(function()
            local entrances = ProjectALife.Entrances
            if entrances == nil then return end
            local cell = getCell()
            if cell == nil then return end
            local destination = cell:getGridSquare(math.floor(target.x),
                math.floor(target.y), math.floor(target.z))
            local building = destination ~= nil and destination:getBuilding() or nil
            if building == nil then return end
            local here = shell:getCurrentSquare()

            if here ~= nil and here:getBuilding() == building then
                entrances.release(actor.uid)
                return
            end
            local opening = entrances.claim(actor, shell, building, nil, options.doorsOnly)
            if opening == nil then return end

            local dx = opening.x - shell:getX()
            local dy = opening.y - shell:getY()
            if dx * dx + dy * dy > 2.25 then
                target = { x = opening.x, y = opening.y, z = opening.z }
            end
        end)
    end

    restricted, restriction = Movement.adminDestination(actor, shell, target)
    if restricted == nil then
        Movement.stop(shell)
        return nil, restriction
    end
    target = restricted
    local pace = requestedPace(options.pace)
    target = Movement.safeDestination(actor, shell, target)

    if type(Traversal.settleRefusal) == "function" then Traversal.settleRefusal(shell) end
    if not issue(shell, target, pace) then
        Movement.metrics.lastFailure = "movement_path_rejected"
        cancel(shell)
        return nil, "movement_path_rejected"
    end

    Movement.sequence = Movement.sequence + 1
    local operationId = options.operationId
        or ("move:" .. actor.uid .. ":" .. actor.generation .. ":" .. Movement.sequence)
    local fingerprint = options.fingerprint
        or (actor.uid .. ":" .. actor.generation .. ":"
            .. tostring(target.x) .. ":" .. tostring(target.y) .. ":" .. tostring(target.z))
    local startedAt = nowMs()
    local tolerance = math.max(0.25, tonumber(options.tolerance) or 0.8)
    local lastPosition = position(shell)
    local lastProgressAtMs = startedAt
    local lastRepathAtMs = startedAt
    local stallMs = math.max(500, math.floor(tonumber(options.stallMs) or 3000))
    local pathStartupGraceMs = math.max(stallMs,
        math.floor(tonumber(options.pathStartupGraceMs) or 6000))
    local maximumRepathMs = math.max(stallMs,
        math.floor(tonumber(options.maximumRepathMs) or 8000))
    local maximumConsecutiveStalls = math.max(1,
        math.floor(tonumber(options.maximumConsecutiveStalls) or 3))
    local maximumTraversalFailures = math.max(1,
        math.floor(tonumber(options.maximumTraversalFailures) or 2))
    local repathIntervalMs = stallMs

    local jitterStallMs = math.max(stallMs * 2,
        math.floor(tonumber(options.jitterStallMs) or 6000))
    local anchorPosition, anchorAtMs = position(shell), startedAt
    local pathStarted = Movement.pathPhase(shell) == "started"
    local consecutiveStalls, consecutiveTraversalFailures = 0, 0
    local function recordPathIssue(issuedAt, resetBackoff)
        lastPosition = position(shell)
        lastProgressAtMs = issuedAt
        lastRepathAtMs = issuedAt
        anchorPosition, anchorAtMs = lastPosition, issuedAt
        pathStarted = Movement.pathPhase(shell) == "started"
        if resetBackoff then repathIntervalMs = stallMs end
    end

    local walk = { replans = 0, requested = requested,
        frozenMs = math.max(Movement.frozenMs, stallMs + 1000) }
    local function windowStep(atWaypoint, cutKey, force)
        local now = nowMs()
        if atWaypoint then
            if walk.goal == nil or not Movement.onSquare(shell, target) then return false end
            walk.at = walk.at + 1
            target = walk.route[walk.at] or walk.goal
            if walk.route[walk.at] == nil then walk.goal, walk.route = nil, nil end
        else
            local edgeKey = Movement.windowCheck(shell, now)
            if edgeKey == nil then edgeKey = cutKey end
            if edgeKey == nil and force ~= true then return false end
            if force ~= true then Movement.pathWhy(shell, "edge_banned") end
            local goal = Movement.adminDestination(actor, shell, walk.goal or requested)
            local route, at
            if goal ~= nil then
                route, at = Movement.replanAround(walk, actor, shell, goal, edgeKey, now, options.doorsOnly)
            end
            if route == nil and at == "deferred" then
                if type(Traversal.askReplan) == "function" then Traversal.askReplan(shell, edgeKey, now) end
                return true
            end
            if route == nil then
                Movement.pathWhy(shell, "no_alternative")
                Movement.refuseGoal(actor.uid, requested, now)
                Movement.metrics.lastFailure = "movement_opening_impassable"
                cancel(shell)
                Ledger.fail(operationId, "movement_opening_impassable")
                return true
            end
            if at == nil then Movement.metrics.replans = (Movement.metrics.replans or 0) + 1 end
            walk.goal, walk.route, walk.at = goal, route, at or 1
            target = route[walk.at]
        end

        consecutiveStalls = 0
        target = Movement.adminDestination(actor, shell, target)
        if target ~= nil and issue(shell, target, pace) then
            if walk.action ~= nil then
                walk.action.target = { x = target.x, y = target.y, z = target.z }
            end
            recordPathIssue(now, true)
        else
            Movement.metrics.lastFailure = "movement_path_rejected"
            cancel(shell)
            Ledger.fail(operationId, "movement_path_rejected")
        end
        return true
    end

    local function goalReached()
        return walk.goal == nil and arrived(shell, target, tolerance)
    end
    local function completionCheck()
        if Animations.blocksLocomotion(shell) then return false end
        local enforced = Movement.adminDestination(actor, shell, target)
        if enforced == nil then
            cancel(shell)
            return true
        end
        if enforced.x ~= target.x or enforced.y ~= target.y or enforced.z ~= target.z then
            target = enforced
            if issue(shell, target, pace) then
                recordPathIssue(nowMs(), true)
            else
                Movement.metrics.lastFailure = "movement_path_rejected"
                cancel(shell)
                Ledger.fail(operationId, "movement_path_rejected")
                return false
            end
        end
        Movement.refreshPace(shell)

        if options.doorsOnly == true then
            local refused, cutKey = false, nil
            if type(Traversal.refuseNative) == "function" then refused, cutKey = Traversal.refuseNative(shell) end
            if refused then
                Movement.metrics.climbRefused = (Movement.metrics.climbRefused or 0) + 1
                Movement.pathWhy(shell, "climb_refused_doorsOnly")
                windowStep(false, cutKey, true)
                return false
            end
        else
            Traversal.adoptNative(shell)
        end
        Traversal.tickShell(shell)
        if windowStep(true) then return false end
        if goalReached() then
            cancel(shell)
            return true
        end

        local fence = ProjectALife.AIFence
        if fence ~= nil and type(fence.crowdArrived) == "function" and fence.crowdArrived(shell, target) then
            cancel(shell)
            return true
        end
        if Traversal.isBusy(shell) then return false end

        local frozen, point = Movement.frozenCheck(walk, actor, shell, target, nowMs())
        if frozen == "step" then
            target = point
            consecutiveStalls = 0
            if issue(shell, target, pace) then
                recordPathIssue(nowMs(), true)
            else
                Movement.metrics.lastFailure = "movement_path_rejected"
                cancel(shell)
                Ledger.fail(operationId, "movement_path_rejected")
            end
            return false
        elseif frozen == "give_up" then
            cancel(shell)
            Ledger.fail(operationId, "movement_frozen")
            return false
        end

        local refusalWait = type(Traversal.refusalWait) == "function"
            and Traversal.refusalWait(shell, nowMs()) or nil
        if refusalWait == "wait" then

            if windowStep(false) then return false end
            lastProgressAtMs = nowMs()
            return false
        elseif refusalWait == "resume" then
            if issue(shell, target, pace) then
                recordPathIssue(nowMs(), false)
            else
                Movement.metrics.lastFailure = "movement_path_rejected"
                cancel(shell)
                Ledger.fail(operationId, "movement_path_rejected")
            end
            return false
        end

        if options.doorsOnly ~= true and Traversal.openWindowAhead(shell, target) then
            local now = nowMs()
            consecutiveStalls, consecutiveTraversalFailures = 0, 0
            if issue(shell, target, pace) then
                recordPathIssue(now, true)
            else
                Movement.metrics.lastFailure = "movement_path_rejected"
                cancel(shell)
                Ledger.fail(operationId, "movement_path_rejected")
            end
            return false
        end
        local doorOpened, doorReason = Traversal.openDoorAhead(shell, target)
        if doorOpened then
            local now = nowMs()
            consecutiveStalls, consecutiveTraversalFailures = 0, 0
            if issue(shell, target, pace) then
                recordPathIssue(now, true)
            else
                Movement.metrics.lastFailure = "movement_path_rejected"
                cancel(shell)
                Ledger.fail(operationId, "movement_path_rejected")
            end
            return false
        elseif doorReason == "door_open_failed" or doorReason == "door_probe_failed" then
            Movement.metrics.traversalFailures = Movement.metrics.traversalFailures + 1
            Movement.metrics.lastFailure = doorReason
        end
        local traversalResult = Traversal.consumeResult(shell)
        if traversalResult ~= nil then
            local now = nowMs()
            if traversalResult.success then
                consecutiveStalls, consecutiveTraversalFailures = 0, 0
                if issue(shell, target, pace) then
                    recordPathIssue(now, true)
                else
                    Movement.metrics.lastFailure = "movement_path_rejected"
                    cancel(shell)
                    Ledger.fail(operationId, "movement_path_rejected")
                end
            else
                consecutiveTraversalFailures = consecutiveTraversalFailures + 1
                Movement.metrics.traversalFailures =
                    Movement.metrics.traversalFailures + 1
                Movement.metrics.lastFailure = traversalResult.reason or "traversal_failed"
                if consecutiveTraversalFailures >= maximumTraversalFailures then
                    Movement.refuseGoal(actor.uid, requested, now)
                    cancel(shell)
                    Ledger.fail(operationId, Movement.metrics.lastFailure)
                elseif windowStep(false) then

                    return false
                elseif issue(shell, target, pace) then
                    recordPathIssue(now, false)
                else
                    Movement.metrics.lastFailure = "movement_path_rejected"
                    cancel(shell)
                    Ledger.fail(operationId, "movement_path_rejected")
                end
            end
            return false
        end

        if windowStep(false) then return false end
        local current, now = position(shell), nowMs()
        if current ~= nil and lastPosition ~= nil then

            if anchorPosition == nil then
                anchorPosition, anchorAtMs = current, now
            else
                local ax, ay = current.x - anchorPosition.x, current.y - anchorPosition.y
                if ax * ax + ay * ay >= 1 then anchorPosition, anchorAtMs = current, now end
            end
            local jittering = now - anchorAtMs >= jitterStallMs
            local dx, dy, dz = current.x - lastPosition.x,
                current.y - lastPosition.y, current.z - lastPosition.z
            if dx * dx + dy * dy + dz * dz >= 0.04 and not jittering then
                lastPosition, lastProgressAtMs = current, now
                pathStarted = true
                consecutiveStalls = 0
                repathIntervalMs = stallMs
            else
                local phase = Movement.pathPhase(shell)
                if not pathStarted and phase == "started" then
                    pathStarted = true
                    lastPosition, lastProgressAtMs = current, now
                    return false
                end
                local requiredInterval = repathIntervalMs
                if not pathStarted and phase == "pending" then
                    requiredInterval = math.max(requiredInterval, pathStartupGraceMs)
                end
                if now - lastProgressAtMs >= requiredInterval
                        and now - lastRepathAtMs >= requiredInterval then
                    Movement.metrics.stalls = Movement.metrics.stalls + 1
                    consecutiveStalls = consecutiveStalls + 1
                    lastRepathAtMs = now

                    local traversing, traversalReason = Traversal.try(shell, target, options.doorsOnly, true)
                    if not traversing then

                        Movement.cancelPathOnly(shell)
                        if windowStep(false) then return false end

                        local soft = softTraversalRefusal(traversalReason)
                        if soft and Movement.doorDecision(traversalReason) then walk.doorDecision = true end
                        if traversalReason ~= nil and not soft then
                            Movement.metrics.traversalFailures =
                            Movement.metrics.traversalFailures + 1
                            Movement.metrics.lastFailure = traversalReason
                            Movement.refuseGoal(actor.uid, requested, now)
                            cancel(shell)
                            Ledger.fail(operationId, traversalReason)
                            return false
                        end
                        if consecutiveStalls >= maximumConsecutiveStalls then
                            Movement.metrics.unreachableFailures =
                            Movement.metrics.unreachableFailures + 1
                            Movement.metrics.lastFailure = "movement_target_unreachable"
                            if walk.doorDecision ~= true then
                                Movement.refuseGoal(actor.uid, requested, now, Movement.stallRefusalMs)
                            end
                            cancel(shell)
                            Ledger.fail(operationId, "movement_target_unreachable")
                            return false
                        end
                        local issued, issueReason = issue(shell, target, pace)
                        if issued then
                            recordPathIssue(now, false)
                        elseif issueReason == "flooded" then
                            consecutiveStalls = consecutiveStalls - 1
                            lastRepathAtMs = now - requiredInterval + Movement.floodRetryMs
                            return false
                        else
                            Movement.metrics.lastFailure = "movement_path_rejected"
                            Movement.refuseGoal(actor.uid, requested, now)
                            cancel(shell)
                            Ledger.fail(operationId, "movement_path_rejected")
                            return false
                        end
                    end
                    repathIntervalMs = math.min(maximumRepathMs,
                        math.floor(repathIntervalMs * 1.6))
                end
            end
        end
        return false
    end
    local action, actionError = Ledger.begin({
        operationId = operationId,
        uid = actor.uid,
        generation = actor.generation,
        kind = "movement",
        fingerprint = fingerprint,
        startedAtMs = startedAt,
        deadlineAtMs = startedAt + math.max(1000, math.floor(options.timeoutMs or 12000)),
        maximumRecoveries = math.max(0, math.floor(options.maximumRecoveries or 2)),
        retryDelayMs = math.max(100, math.floor(options.retryDelayMs or 500)),
        fallback = "safe_idle",
        isComplete = completionCheck,
        cancel = function() return cancel(shell) end,
        recover = function()
            if Animations.blocksLocomotion(shell) then return true end

            cancelPathOnly(shell)
            local traversing, traversalReason = Traversal.try(shell, target, options.doorsOnly, true)
            local now = nowMs()
            if traversing then
                lastPosition, lastProgressAtMs, lastRepathAtMs = position(shell), now, now
                pathStarted = false
                return true
            end
            if traversalReason ~= nil then
                if not softTraversalRefusal(traversalReason) then
                    Movement.refuseGoal(actor.uid, requested, now)
                end
                return false
            end
            local issued, issueReason = issue(shell, target, pace)
            if issued then
                recordPathIssue(now, false)
            elseif issueReason == "flooded" then
                lastRepathAtMs = now - repathIntervalMs + Movement.floodRetryMs
                return true
            else
                Movement.refuseGoal(actor.uid, requested, now)
            end
            return issued
        end,
    })
    if action == nil then
        cancel(shell)
        return nil, actionError
    end
    Movement.pathWhy(shell, "none")
    action.target = { x = target.x, y = target.y, z = target.z }
    walk.action = action
    action.pace = pace
    action.setPace = function(_, nextPace)
        pace = requestedPace(nextPace)
        action.pace = pace
        return Movement.setPace(shell, pace)
    end
    return action
end

function Movement.tick(budget)
    return Traversal.tick(budget)
end

return Movement
