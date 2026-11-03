require "ProjectALife/Combat/ALifeCombatCore"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Movement/ALifeMovement"
require "ProjectALife/Movement/ALifeObstacleTraversal"

ProjectALife = ProjectALife or {}

local Animations = ProjectALife.Animations
local Movement = ProjectALife.Movement
local Traversal = ProjectALife.ObstacleTraversal
local Combat = ProjectALife.Combat

function Combat.repositionDuration(shell, destination, pace)
    local ok, outside, distance = pcall(function()
        return shell:isOutside(), math.sqrt((shell:getX() - destination.x)^2 + (shell:getY() - destination.y)^2)
    end)
    if not ok or outside ~= true then return 1100 end
    return math.max(1800, math.min(5000, distance * (pace == "run" and 350 or 650) + 500))
end

function Combat.repositionArrived(shell, point, radius)
    if point == nil then return false end
    local limit = tonumber(radius) or 0.8
    return (shell:getX() - point.x)^2 + (shell:getY() - point.y)^2 < limit * limit
        and math.abs(shell:getZ() - (point.z or 0)) < 0.4
end

function Combat.meleeBreakOffer(actor, shell, target, distance, now)
    local registry = ProjectALife.ModuleRegistry
    if registry == nil or type(registry.evaluate) ~= "function" then return nil end
    return (registry.evaluate("positioning", actor, shell,
        { now = now, target = target, ranged = false, distance = distance,
            acceptOffer = Combat.positionOfferAllowed }, "withdraw"))
end

function Combat.positionOfferAllowed(actor, shell, point, context)
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then
        return false
    end
    if type(context) == "table" and context.ranged == true then
        local target = context.target
        if target == nil or type(target.getX) ~= "function"
                or type(target.getY) ~= "function" then return false end
        local dx, dy = point.x - target:getX(), point.y - target:getY()
        local floor = Combat.desiredRange(context.weapon, shell) * 0.85
        if dx * dx + dy * dy < floor * floor then return false end
    end
    return Combat.leashOffer(actor, point) ~= nil
end

function Combat.retaliationSeen(shell, body)
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.visible) ~= "function" then return true end
    local ok, seen = pcall(perception.visible, shell, body)
    return not ok or seen == true
end

function Combat.breakingOut(aim, phase, now)
    return phase == "cover" and type(aim) == "table"
        and (tonumber(now) or 0) < (tonumber(aim.breakUntilMs) or 0)
end

function Combat.keepsTarget(aim, phase, shell, target, weapon, retaliation, retaliationKind)
    if phase == "windup" then return true end
    if weapon == nil or not Combat.isRanged(weapon) then return false end
    if retaliationKind ~= nil and retaliationKind ~= "zombie" then return false end
    if Combat.peekKind(retaliation) ~= "zombie" or Combat.peekKind(target) ~= "zombie" then
        return false
    end
    local reach = Combat.engagementReach(weapon, shell, target)
    if Combat.distanceSquared(shell, target) > reach * reach then return false end
    if type(aim) == "table" and aim.keptAgainst ~= retaliation then
        aim.keptAgainst = retaliation
        Combat.metrics.bitersKept = (Combat.metrics.bitersKept or 0) + 1
    end
    return true
end

function Combat.meleeFocus(shell, target, weapon, challenger)
    if weapon == nil or Combat.isRanged(weapon) or target == nil or challenger == nil then return false end
    if Combat.peekKind(target) ~= "zombie" or Combat.peekKind(challenger) ~= "zombie"
            or not Combat.targetAlive(target) then return false end
    local reach = Combat.meleeReachFor(weapon, target) + 0.25
    return Combat.distanceSquared(shell, target) <= reach * reach
end

function Combat.inClip(shell)
    if shell == nil then return false end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.inClip) ~= "function" then return false end
    return traversal.inClip(shell) == true
end

function Combat.squareAt(x, y, z)
    if type(getCell) ~= "function" or tonumber(x) == nil or tonumber(y) == nil then return nil end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(z) or 0))
end

function Combat.buildingAt(x, y, z)
    local square = Combat.squareAt(x, y, z)
    if square == nil or square.getBuilding == nil then return nil end
    return square:getBuilding()
end

function Combat.stableHash(value)
    local result = 17
    value = tostring(value or "")
    for index = 1, #value do result = (result * 31 + string.byte(value, index)) % 2147483647 end
    return result
end

function Combat.holdStill(shell)
    local data = Combat.dataOf(shell)
    if data ~= nil then data.ProjectALifeStuckSinceMs = nil end
end

function Combat.pathLive(shell)
    local data = Combat.dataOf(shell)
    return data ~= nil and data.ProjectALifePathActive == true
end

function Combat.endBurst(shell)
    local data = Combat.dataOf(shell)
    if data ~= nil and data.ProjectALifeSprintUntilMs ~= nil then
        data.ProjectALifeSprintUntilMs = nil
    end
end

function Combat.currentGrudge(actor)
    local perception = ProjectALife.Perception
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or perception == nil
            or type(perception.retaliationTarget) ~= "function" then return nil end
    local ok, grudge = pcall(perception.retaliationTarget, actor.uid)
    return ok and grudge or nil
end

function Combat.recoverUpper(actor, shell, target, aim, now)
    if aim.upperRecoveryAttempted == true
            and (aim.upperRecoveryUntilMs == nil or now >= aim.upperRecoveryUntilMs) then return false end
    if aim.upperRecoveryAttempted ~= true then
        aim.upperRecoveryAttempted = true
        aim.upperRecoveryUntilMs = now + 15000
        local breach = ProjectALife.ModuleBreach
        if breach ~= nil and type(breach.propose) == "function" then pcall(breach.propose, actor, shell, target, now) end
    end
    if aim.upperNextScanMs ~= nil and now < aim.upperNextScanMs then return aim.upperPoint ~= nil end
    aim.upperNextScanMs = now + 1000
    local posts = ProjectALife.UpperPosts
    local point, reason
    if posts ~= nil and type(posts.pursuitPoint) == "function" and aim.noClimb ~= true then point, reason = posts.pursuitPoint(shell, target) end
    reason = reason or "upper_post_holds"
    local stack = ProjectALife.ModuleBreach ~= nil
        and type(ProjectALife.ModuleBreach.approachOverride) == "function"
        and ProjectALife.ModuleBreach.approachOverride(actor, shell, now) or nil
    if stack ~= nil then point, reason = stack.destination, "upper_breach_approach" end
    if point ~= nil and not Combat.detourLeashed(shell, point) then point, reason = nil, "upper_leash_holds" end
    aim.upperPoint = point
    pcall(function() shell:getModData().ProjectALifeUpperPursuitReason = reason end)
    if point == nil then aim.upperRecoveryUntilMs = now; return false end
    Combat.metrics.upperRecoveries = (Combat.metrics.upperRecoveries or 0) + 1
    Combat.pathToward(shell, point, "walk", true)
    return true
end

function Combat.lowFenceProbe(here, there)
    if here:isWallTo(there) == true or there:isWallTo(here) == true then return false end
    if here:isHoppableTo(there) ~= true and there:isHoppableTo(here) ~= true then return false end
    if here.getWindowTo ~= nil and (here:getWindowTo(there) ~= nil or there:getWindowTo(here) ~= nil) then
        return false
    end
    if here.getDoorTo ~= nil and (here:getDoorTo(there) ~= nil or there:getDoorTo(here) ~= nil) then
        return false
    end
    return true
end

function Combat.lowFenceBetween(shell, target)
    local here = shell ~= nil and shell.getCurrentSquare ~= nil and shell:getCurrentSquare() or nil
    local there = target ~= nil and target.getCurrentSquare ~= nil and target:getCurrentSquare() or nil
    if here == nil or there == nil or here == there or here.isHoppableTo == nil
            or here.isWallTo == nil or here.getX == nil or there.getX == nil then return nil end
    if math.abs(here:getX() - there:getX()) + math.abs(here:getY() - there:getY()) ~= 1 then return nil end
    local ok, fence = pcall(Combat.lowFenceProbe, here, there)
    if not ok or fence ~= true then return nil end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.edgeKey) == "function" then
        return traversal.edgeKey(here, there) or "fence"
    end
    return "fence"
end

function Combat.fenceStandoff(shell, target, aim)
    if aim.fenceDetourAsked == nil then
        aim.fenceDetourAsked = true
        local traversal = ProjectALife.ObstacleTraversal
        if traversal ~= nil and type(traversal.detourFor) == "function" then
            local x, y, z = traversal.detourFor(shell, aim.fenceEdge)
            if tonumber(x) ~= nil and tonumber(y) ~= nil then
                local point = aim.fencePoint
                if point == nil then point = {}; aim.fencePoint = point end
                point.x, point.y, point.z = x, y, tonumber(z) or 0
                aim.fenceDetour = true
            end
        end
    end
    if aim.fenceDetour == true then
        local sx, sy = Combat.xyOf(shell)
        if sx ~= nil and (sx - aim.fencePoint.x) ^ 2 + (sy - aim.fencePoint.y) ^ 2 > 1.44 then
            Combat.pathToward(shell, aim.fencePoint, "walk", false)
            return "detour"
        end
        aim.fenceDetour = false
    end
    if Combat.pathRequests[shell] ~= nil or Combat.pathLive(shell) then
        Combat.cancelPath(shell)
        Combat.pathRequests[shell] = nil
    end
    Combat.faceTarget(shell, target)
    Combat.holdStill(shell)
    Combat.metrics.fenceHolds = (Combat.metrics.fenceHolds or 0) + 1
    return "hold"
end

function Combat.acrossEdge(shell, destination, edgeKey)
    if type(edgeKey) ~= "string" or type(destination) ~= "table" then return true end
    local x1, y1, x2, y2 = string.match(edgeKey, "^(%-?%d+):(%-?%d+)|(%-?%d+):(%-?%d+)")
    x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
    local sx, sy = Combat.xyOf(shell)
    local dx, dy = tonumber(destination.x), tonumber(destination.y)
    if x1 == nil or y2 == nil or sx == nil or dx == nil or dy == nil then return true end
    local ax, ay, bx, by = x1 + 0.5, y1 + 0.5, x2 + 0.5, y2 + 0.5
    local shellNearA = (sx - ax) ^ 2 + (sy - ay) ^ 2 <= (sx - bx) ^ 2 + (sy - by) ^ 2
    local goalNearA = (dx - ax) ^ 2 + (dy - ay) ^ 2 <= (dx - bx) ^ 2 + (dy - by) ^ 2
    return shellNearA ~= goalNearA
end

function Combat.detourLeashed(shell, point)
    local aim = Combat.aimState[shell]
    local anchor = aim ~= nil and aim.leashAnchor or nil
    local leash = aim ~= nil and tonumber(aim.leashRange) or nil
    if type(anchor) ~= "table" or leash == nil then return true end
    if Combat.leashOutside(shell, anchor, leash) ~= nil then return true end
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    if ax == nil or ay == nil then return true end
    local reach = leash + (tonumber(Combat.settings.leashReturnSlack) or 1)
    return (point.x - ax) ^ 2 + (point.y - ay) ^ 2 <= reach * reach
end

function Combat.occupiedHoldMs(traversal)
    local settings = traversal ~= nil and traversal.settings or nil
    return tonumber(type(settings) == "table" and settings.occupiedHoldMs or nil) or 1000
end

function Combat.lockoutUntil(traversal, shell)
    local locks = traversal ~= nil and traversal.lockoutUntilMs or nil
    return type(locks) == "table" and shell ~= nil and tonumber(locks[shell]) or nil
end

function Combat.lockoutLive(traversal, shell, now)
    local untilMs = Combat.lockoutUntil(traversal, shell)
    return untilMs == nil or now < untilMs
end

function Combat.landedRecently(shell, now)
    local untilMs = Combat.lockoutUntil(ProjectALife.ObstacleTraversal, shell)
    return untilMs ~= nil and now >= untilMs - 1500
        and now < untilMs + (tonumber(Combat.settings.landingWindowMs) or 2500)
end

function Combat.refusalAnswer(shell, destination, now)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.lastRefusal) ~= "function" then return nil end
    local kind, atMs, edgeKey = traversal.lastRefusal(shell)
    atMs = tonumber(atMs)
    if kind == nil or atMs == nil then return nil end
    local aim = Combat.aimStateFor(shell)
    local age = now - atMs
    if age < 0 or age >= (tonumber(Combat.settings.climbHoldMs) or 8000)
            or not Combat.acrossEdge(shell, destination, edgeKey) then
        aim.edgeHoldSinceMs = nil
        return false
    end
    if kind == "queue" or kind == "occupied" then

        if kind == "queue" and type(traversal.leaseHeld) == "function"
                and not traversal.leaseHeld(shell, edgeKey, now) then return false end

        if kind == "occupied" and age >= Combat.occupiedHoldMs(traversal) then return false end
        if age < (tonumber(Combat.settings.climbQueueHoldMs) or 2000) then
            Combat.metrics.edgeQueueHolds = (Combat.metrics.edgeQueueHolds or 0) + 1
            return true
        end
        return false
    end
    if kind == "locked" then

        aim.edgeHoldSinceMs = nil
        if Combat.lockoutLive(traversal, shell, now)
                and age < (tonumber(Combat.settings.climbLockedHoldMs) or 1500) then
            Combat.metrics.edgeLockWaits = (Combat.metrics.edgeLockWaits or 0) + 1
            return true
        end
        return false
    end

    local refusedAgain = false
    if aim.detourDoneKey == edgeKey and aim.detourDoneAtMs ~= nil and now >= aim.detourDoneAtMs
            and now - aim.detourDoneAtMs < (tonumber(Combat.settings.climbHoldMs) or 8000) then
        if atMs <= aim.detourDoneAtMs then return false end
        refusedAgain = true
    end
    local point = aim.detourPoint
    if point == nil then
        point = {}
        aim.detourPoint = point
    end
    if refusedAgain then
        aim.refusalHasPoint = false
    elseif aim.refusalKey ~= edgeKey or aim.refusalAskedAtMs == nil or now < aim.refusalAskedAtMs
            or now - aim.refusalAskedAtMs >= 1500 then
        aim.refusalKey, aim.refusalAskedAtMs, aim.refusalHasPoint = edgeKey, now, false
        if type(traversal.detourFor) == "function" then
            local x, y, z = traversal.detourFor(shell, edgeKey, Combat.noClimbFor(shell))
            if tonumber(x) ~= nil and tonumber(y) ~= nil then
                point.x, point.y, point.z = x, y, tonumber(z) or destination.z
                aim.refusalHasPoint = true
            end
        end
        local entrances = ProjectALife.Entrances
        if not aim.refusalHasPoint and entrances ~= nil and type(entrances.claimFor) == "function" then
            local opening = entrances.claimFor(shell, destination.x, destination.y, destination.z,
                Combat.noClimbFor(shell) and Combat.DOORS_ONLY or nil)
            if type(opening) == "table" and tonumber(opening.x) ~= nil and tonumber(opening.y) ~= nil then
                point.x, point.y = opening.x, opening.y
                point.z = tonumber(opening.z) or destination.z
                aim.refusalHasPoint = true
            end
        end
        if aim.refusalHasPoint and kind == "posted" and not Combat.detourLeashed(shell, point) then
            aim.refusalHasPoint = false
        end
        if aim.refusalHasPoint then
            Combat.metrics.edgeDetours = (Combat.metrics.edgeDetours or 0) + 1
        end
    end
    if aim.refusalHasPoint then
        aim.edgeHoldSinceMs = nil
        local sx, sy = Combat.xyOf(shell)
        if sx ~= nil and (sx - point.x) ^ 2 + (sy - point.y) ^ 2 <= 1.44 then

            aim.detourDoneKey, aim.detourDoneAtMs = edgeKey, now
            return false
        end
        return point
    end
    aim.edgeHoldSinceMs = aim.edgeHoldSinceMs or now
    aim.edgeHoldSamples = (aim.edgeHoldSamples or 0) + 1
    Combat.metrics.edgeHolds = (Combat.metrics.edgeHolds or 0) + 1
    return true
end

function Combat.noteHoldLimit(shell, aim, kind, heldMs)
    if kind == "edge" then
        if type(Movement.pathWhy) == "function" then
            Movement.pathWhy(shell, "no_alternative")
        else
            local data = Combat.dataOf(shell)
            if data ~= nil then data.ProjectALifePathWhy = "no_alternative" end
        end
    end
    local box = ProjectALife.BlackBox
    if box ~= nil and box.enabled == true and type(box.note) == "function" then
        local samples = kind == "edge" and aim.edgeHoldSamples or aim.leashHoldSamples
        box.note(shell, "hold-cap", kind .. " samples=" .. tostring(samples or 0)
            .. " climbSamples=" .. tostring(aim.climbHoldSamples or 0)
            .. " heldMs=" .. tostring(heldMs))
    end
end

Combat.routeLegMs = 20000
Combat.routeWindowMs = 30000

Combat.routeDriftSq = 16

function Combat.routeLeg(shell, destination, now)
    local aim = Combat.aimStateFor(shell)
    local key = Movement.windowCheck(shell, now)
    if key ~= nil and not (aim.route ~= nil and aim.routeKey == key
            and now - (tonumber(aim.routePlannedAtMs) or 0) < Movement.replanRepeatMs) then
        local counted = tonumber(aim.routeCountAtMs)
        if counted == nil or now < counted or now - counted >= Combat.routeWindowMs then
            aim.routeCount, aim.routeCountAtMs = 0, now
        end
        aim.routeCount = aim.routeCount + 1
        local route = nil
        if aim.routeCount > Movement.maximumReplans then
            route = nil
        elseif type(Traversal.wayRound) == "function" then
            route = Traversal.wayRound(shell, key, destination, Combat.noClimbFor(shell))
        else
            route = Traversal.detourRoute(shell, key, Combat.noClimbFor(shell))
        end
        if type(route) ~= "table" or route[1] == nil then
            aim.route = nil
            aim.pathGiveUpAtMs = now
            Combat.metrics.pathGiveUps = (Combat.metrics.pathGiveUps or 0) + 1
            return true
        end
        aim.route, aim.routeAt, aim.routeIssuedAt, aim.routeKey = route, 1, nil, key
        aim.routePlannedAtMs, aim.routeGoalX, aim.routeGoalY = now, destination.x, destination.y
        Combat.metrics.edgeDetours = (Combat.metrics.edgeDetours or 0) + 1
    end
    local route = aim.route
    if route == nil then return nil end
    local sx, sy = Combat.xyOf(shell)
    local planned = tonumber(aim.routePlannedAtMs) or now
    if sx == nil or now < planned or now - planned >= Combat.routeLegMs
            or (destination.x - aim.routeGoalX) ^ 2 + (destination.y - aim.routeGoalY) ^ 2 > Combat.routeDriftSq then
        aim.route = nil
        return nil
    end
    local point = route[aim.routeAt]
    while point ~= nil and Movement.onSquare(shell, point) do
        aim.routeAt = aim.routeAt + 1
        point = route[aim.routeAt]
    end
    if point == nil then
        aim.route = nil
        return nil
    end
    local fresh = aim.routeIssuedAt ~= aim.routeAt
    aim.routeIssuedAt = aim.routeAt
    return point, fresh
end

function Combat.peekRecord(shell)
    local data = Movement.dataOf(shell)
    local uid = data ~= nil and data.ProjectALifeUID or nil
    local registry = ProjectALife.ActorRegistry
    if type(uid) ~= "string" or registry == nil or type(registry.peek) ~= "function" then
        return nil
    end
    local record = registry.peek(uid)
    return type(record) == "table" and record or nil
end

function Combat.recordAdmin(shell)
    local record = Combat.peekRecord(shell)
    if record == nil then return nil, false end
    local memory = record.memory
    local admin = type(memory) == "table" and memory.admin or nil
    return type(admin) == "table" and admin or nil, true
end

function Combat.adminBound(shell, destination)
    local admin, recorded = Combat.recordAdmin(shell)
    if recorded then
        if admin == nil then return destination end
        if admin.stationary == true then return nil end
        local leash = type(admin.leash) == "table" and admin.leash or nil
        local radius = leash ~= nil and math.max(0, math.min(100, tonumber(leash.radius) or 0)) or 0
        local lx, ly = leash ~= nil and tonumber(leash.x) or nil, leash ~= nil and tonumber(leash.y) or nil
        local tx, ty = tonumber(destination.x), tonumber(destination.y)
        if radius <= 0 or lx == nil or ly == nil or tx == nil or ty == nil then return destination end
        local dx, dy = tx - lx, ty - ly
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= radius or distance < 0.0001 then return destination end
        return { x = lx + dx / distance * radius, y = ly + dy / distance * radius, z = destination.z }
    end
    local data = Movement.dataOf(shell)
    if data == nil or data.ProjectALifeAdminManaged ~= true then return destination end
    local permitted, refusal = Movement.adminDestination(nil, shell, destination)
    if permitted ~= nil then return permitted end
    if refusal == "admin_stationary" then return nil end
    return destination
end

function Combat.homeBound(shell, destination)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.privateAt) ~= "function" or type(destination) ~= "table" then return destination end
    if policy.privateAt(destination.x, destination.y) == nil then return destination end
    local actor = policy.actorOf(shell)
    if actor ~= nil and policy.pathRefusal(actor, shell, destination, "combat") ~= nil then return nil end
    return destination
end

function Combat.serverSide()
    return type(isServer) == "function" and isServer() == true
end

function Combat.clipEcho(shell, now)
    local traversal = ProjectALife.ObstacleTraversal
    if shell == nil or traversal == nil or type(traversal.echoLive) ~= "function" then return false end
    return traversal.echoLive(shell, now) == true
end

function Combat.stepOffLeg(shell, now)
    local aim = Combat.aimState[shell]
    local untilMs = aim ~= nil and aim.stepOffUntilMs or nil
    local point = aim ~= nil and aim.stepOffPoint or nil
    if untilMs == nil or point == nil then return nil end
    local sx, sy = Combat.xyOf(shell)
    if sx == nil or now >= untilMs or now < untilMs - 10000
            or (sx - point.x) ^ 2 + (sy - point.y) ^ 2 <= 0.25 then
        aim.stepOffUntilMs = nil
        return nil
    end
    return point
end

function Combat.stepEdgeOpen(a, b)
    if a:isBlockedTo(b) == true or b:isBlockedTo(a) == true then return false end
    if a.isHoppableTo ~= nil and (a:isHoppableTo(b) == true or b:isHoppableTo(a) == true) then
        return false
    end
    return true
end

function Combat.stepOffBounds(shell)
    local record = Combat.peekRecord(shell)
    if record == nil then
        local data = Movement.dataOf(shell)
        return not (data ~= nil and data.ProjectALifeAdminManaged == true) and {} or false
    end
    local bounds = {}
    local flags = type(record.memory) == "table" and record.memory.admin or nil
    local leash = type(flags) == "table" and type(flags.leash) == "table" and flags.leash or nil
    local radius = leash ~= nil and tonumber(leash.radius) or nil
    if radius ~= nil and radius > 0 and tonumber(leash.x) ~= nil and tonumber(leash.y) ~= nil then
        bounds[1], bounds[2], bounds[3] = tonumber(leash.x), tonumber(leash.y), math.min(100, radius)
    end
    local anchor, reach = Combat.leashFor(record)
    reach = tonumber(reach)
    if type(anchor) == "table" and reach ~= nil and reach > 0
            and tonumber(anchor.x) ~= nil and tonumber(anchor.y) ~= nil then
        local n = #bounds
        bounds[n + 1], bounds[n + 2], bounds[n + 3] = tonumber(anchor.x), tonumber(anchor.y), reach
    end
    return bounds
end

function Combat.stepOffInBounds(bounds, sx, sy, x, y)
    if type(bounds) ~= "table" then return true end
    for index = 1, #bounds - 2, 3 do
        local cx, cy, r = bounds[index], bounds[index + 1], bounds[index + 2]
        local there = (x - cx) ^ 2 + (y - cy) ^ 2
        if there > r * r and there > (sx - cx) ^ 2 + (sy - cy) ^ 2 then return false end
    end
    return true
end

function Combat.stepOffProbe(cell, here, hx, hy, z, gx, gy, bounds, sx, sy)
    local bestX, bestY, bestScore
    for dx = -1, 1 do
        for dy = -1, 1 do
            local there = (dx ~= 0 or dy ~= 0) and cell:getGridSquare(hx + dx, hy + dy, z) or nil
            local open = there ~= nil and (there.isFree == nil or there:isFree(true) == true)
                and (there.TreatAsSolidFloor == nil or there:TreatAsSolidFloor() == true)
                and Combat.stepOffInBounds(bounds, sx, sy, hx + dx + 0.5, hy + dy + 0.5)
                and Combat.stepEdgeOpen(here, there)
            if open and dx ~= 0 and dy ~= 0 then
                local a, b = cell:getGridSquare(hx + dx, hy, z), cell:getGridSquare(hx, hy + dy, z)
                open = a ~= nil and b ~= nil and Combat.stepEdgeOpen(here, a) and Combat.stepEdgeOpen(a, there)
                    and Combat.stepEdgeOpen(here, b) and Combat.stepEdgeOpen(b, there)
            end
            if open then
                local score = (dx * gx + dy * gy) / math.sqrt(dx * dx + dy * dy)
                if bestScore == nil or score > bestScore then
                    bestX, bestY, bestScore = hx + dx, hy + dy, score
                end
            end
        end
    end
    if bestX == nil then return nil end
    return bestX + 0.5, bestY + 0.5
end

function Combat.stepOffSquare(shell, destination)
    if type(getCell) ~= "function" or type(destination) ~= "table" then return nil end
    local cell = getCell()
    local sx, sy, sz = Combat.xyzOf(shell)
    if cell == nil or cell.getGridSquare == nil or sx == nil then return nil end
    local z = math.floor(sz + 0.05)
    local hx, hy = math.floor(sx), math.floor(sy)
    local here = cell:getGridSquare(hx, hy, z)
    if here == nil or here.isBlockedTo == nil then return nil end
    local gx = (tonumber(destination.x) or sx) - sx
    local gy = (tonumber(destination.y) or sy) - sy
    local bounds = Combat.stepOffBounds(shell)
    if bounds == false then return nil end
    local ok, x, y = pcall(Combat.stepOffProbe, cell, here, hx, hy, z, gx, gy, bounds, sx, sy)
    if not ok or x == nil then return nil end
    return x, y, z
end

function Combat.clearUnstarted(aim)
    if aim ~= nil then aim.unstartedCount, aim.unstartedAtMs = nil, nil end
end

function Combat.noteUnstarted(shell, destination, now)
    local aim = Combat.aimStateFor(shell)
    local sx, sy = Combat.xyOf(shell)
    local last = aim.unstartedAtMs
    local radius = tonumber(Combat.settings.pathUnstartedRadius) or 2.5
    local same = last ~= nil and now >= last and sx ~= nil and aim.unstartedX ~= nil
        and now - last < (tonumber(Combat.settings.pathUnstartedWindowMs) or 30000)
        and (sx - aim.unstartedX) ^ 2 + (sy - aim.unstartedY) ^ 2 <= radius * radius
    local count = same and (aim.unstartedCount or 0) + 1 or 1
    local landed = Combat.landedRecently(shell, now)
    if count < 3 and landed then count = 3 end
    aim.unstartedCount, aim.unstartedAtMs = count, now

    if not same then aim.unstartedX, aim.unstartedY = sx, sy end
    Combat.metrics.pathUnstarted = (Combat.metrics.pathUnstarted or 0) + 1
    local verdict
    if count == 3 then
        local x, y, z = Combat.stepOffSquare(shell, destination)
        if x ~= nil then
            local point = aim.stepOffPoint
            if point == nil then
                point = {}
                aim.stepOffPoint = point
            end
            point.x, point.y, point.z = x, y, z
            aim.stepOffUntilMs = now + (tonumber(Combat.settings.stepOffMs) or 2000)
            Combat.metrics.stepOffs = (Combat.metrics.stepOffs or 0) + 1
            verdict = point
        end
    end
    if verdict == nil and count >= 3 then
        aim.pathGiveUpAtMs = now
        aim.stepOffUntilMs = nil
        Combat.metrics.pathGiveUps = (Combat.metrics.pathGiveUps or 0) + 1
        verdict = true
    end
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled == true and type(blackBox.note) == "function" then
        pcall(blackBox.note, shell, "path-unstarted", string.format("n=%d landed=%s dest=%.1f,%.1f do=%s",
            count, tostring(landed), tonumber(destination.x) or 0, tonumber(destination.y) or 0,
            verdict == true and "give_up" or (verdict ~= nil and "step_off" or "reissue")))
    end
    return verdict
end

local function cancelPath(shell)
    local ok = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior ~= nil then behavior:cancel() end

        pcall(function() shell:setPath2(nil) end)
        if ZombieIdleState ~= nil and PathFindState ~= nil
                and shell:getCurrentState() == PathFindState.instance() then
            shell:changeState(ZombieIdleState.instance())
        end
        shell:setMoving(false)
        pcall(function() shell:setVariable("bMoving", false) end)
        pcall(function() shell:setVariable("bPathfind", false) end)
    end)
    Movement.setPathActive(shell, false)
    Movement.setPace(shell, "walk")
    return ok
end

local function requestPath(shell, behavior, x, y, z)

    behavior:pathToLocationF(x, y, math.floor((tonumber(z) or 0) + 0.05))
end

function Combat.kitePoint(shell, target, step)
    local ok, sx, sy, sz, tx, ty = pcall(function()
        return shell:getX(), shell:getY(), shell:getZ(), target:getX(), target:getY()
    end)
    if not ok then return nil end
    local dx, dy = sx - tx, sy - ty
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then dx, dy, length = 1, 0, 1 end
    dx, dy = dx / length, dy / length
    for _, scale in ipairs({ 1, 0.5 }) do
        local x, y = sx + dx * step * scale, sy + dy * step * scale
        local free = false
        pcall(function()
            local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(sz))
            free = square ~= nil and square:isFree(true) == true
        end)
        if free then return { x = x, y = y, z = sz } end
    end
    return nil
end

function Combat.backStepPoint(shell, target, step)
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty = Combat.xyOf(target)
    if sx == nil or tx == nil then return nil end
    local dx, dy = sx - tx, sy - ty
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then return nil end
    local x, y = sx + dx / length * step, sy + dy / length * step
    if math.floor(x) ~= math.floor(sx) or math.floor(y) ~= math.floor(sy) then
        local here = Combat.squareAt(sx, sy, sz)
        local there = Combat.squareAt(x, y, sz)
        if here == nil or there == nil then return nil end
        if type(here.isBlockedTo) == "function" and here:isBlockedTo(there) == true then return nil end
        if type(there.isSolid) == "function" and there:isSolid() == true then return nil end
        if type(there.isSolidTrans) == "function" and there:isSolidTrans() == true then return nil end
    end
    return { x = x, y = y, z = sz }
end

function Combat.footZombies(shell, radius)
    local list = {}
    local sx, sy, sz = Combat.xyzOf(shell)
    if sx == nil or type(getCell) ~= "function" or type(instanceof) ~= "function" then return list end
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local span = math.ceil(radius)
        local fz = math.floor(sz)
        for x = math.floor(sx) - span, math.floor(sx) + span do
            for y = math.floor(sy) - span, math.floor(sy) + span do
                local square = cell:getGridSquare(x, y, fz)
                local moving = square ~= nil and square:getMovingObjects() or nil
                for index = 0, (moving ~= nil and moving:size() or 0) - 1 do
                    local body = moving:get(index)
                    if body ~= shell and instanceof(body, "IsoZombie") and body:isDead() ~= true
                            and not (body:hasModData() and body:getModData().ProjectALifeUID ~= nil)
                            and tostring(body:GetVariable("ALifeActor")) ~= "true" then
                        local dx, dy = sx - body:getX(), sy - body:getY()
                        local distance = math.sqrt(dx * dx + dy * dy)
                        if distance <= radius then
                            local forward = body:getForwardDirection()
                            local fx, fy = forward:getX(), forward:getY()
                            local length = math.sqrt(fx * fx + fy * fy)
                            local facing = distance > 0.01 and length > 0.01
                                and (fx * dx + fy * dy) / (length * distance) or 0
                            list[#list + 1] = { x = body:getX(), y = body:getY(), distance = distance,
                                facing = facing, body = body }
                        end
                    end
                end
            end
        end
    end)
    return list
end

function Combat.footPoint(shell, dx, dy, step, target, reach)
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty = Combat.xyOf(target)
    local length = math.sqrt(dx * dx + dy * dy)
    if sx == nil or tx == nil or length < 0.01 then return nil end
    dx, dy = dx / length, dy / length
    for _, scale in ipairs({ 1, 0.6, 0.35 }) do
        local move = step * scale
        if move >= 0.25 then
            local x, y = sx + dx * move, sy + dy * move
            local gap = math.sqrt((x - tx) ^ 2 + (y - ty) ^ 2)
            local fits = reach == nil or gap <= reach - 0.1
            if fits and (math.floor(x) == math.floor(sx) and math.floor(y) == math.floor(sy)
                    or Combat.stepClear(sx, sy, x, y, sz))
                    and not Combat.footOccupied(shell, target, x, y, sz) then
                return { x = x, y = y, z = sz }
            end
        end
    end
    return nil
end

function Combat.stepClear(sx, sy, x, y, sz)
    local here = Combat.squareAt(sx, sy, sz)
    local there = Combat.squareAt(x, y, sz)
    if here == nil or there == nil then return false end
    if type(here.isBlockedTo) == "function" and here:isBlockedTo(there) == true then return false end
    if type(there.isSolid) == "function" and there:isSolid() == true then return false end
    if type(there.isSolidTrans) == "function" and there:isSolidTrans() == true then return false end
    return true
end

function Combat.footOccupied(shell, target, x, y, z)
    local ok, taken = pcall(function()
        for ox = -1, 1 do
            for oy = -1, 1 do
                local square = Combat.squareAt(x + ox, y + oy, z)
                local list = square ~= nil and type(square.getMovingObjects) == "function" and square:getMovingObjects() or nil
                for index = 0, (list ~= nil and list:size() or 0) - 1 do
                    local body = list:get(index)
                    if body ~= nil and body ~= shell and body ~= target and type(body.getX) == "function"
                            and not (type(body.isDead) == "function" and body:isDead() == true) then
                        local dx, dy = body:getX() - x, body:getY() - y
                        if dx * dx + dy * dy < 0.5625 then return true end
                    end
                end
            end
        end
        return false
    end)
    return ok and taken == true
end

function Combat.footDoorway(here)
    if here == nil or type(here.getObjects) ~= "function" or type(instanceof) ~= "function" then return false end
    local list = here:getObjects()
    for index = 0, (list ~= nil and list:size() or 0) - 1 do
        local object = list:get(index)
        if object ~= nil then
            if instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow") then return true end
            if instanceof(object, "IsoThumpable") and ((type(object.isDoor) == "function" and object:isDoor() == true)
                    or (type(object.isWindow) == "function" and object:isWindow() == true)) then
                return true
            end
        end
    end
    return false
end

function Combat.footEdgeBarrier(here, there)
    if here == nil or there == nil then return false end
    for _, name in ipairs({ "isBlockedTo", "isHoppableTo" }) do
        if type(here[name]) == "function" and here[name](here, there) == true then return true end
        if type(there[name]) == "function" and there[name](there, here) == true then return true end
    end
    for _, name in ipairs({ "getDoorTo", "getWindowTo" }) do
        if type(here[name]) == "function" and here[name](here, there) ~= nil then return true end
        if type(there[name]) == "function" and there[name](there, here) ~= nil then return true end
    end
    return false
end

function Combat.footworkHold(shell, target)
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty = Combat.xyOf(target)
    if sx == nil or tx == nil then return nil end
    if Combat.targetIsGunman(target) then return "gunman" end
    local ok, reason = pcall(function()
        local here = Combat.squareAt(sx, sy, sz)
        if here == nil then return nil end
        if Combat.footDoorway(here) then return "doorway" end
        local dx, dy = tx - sx, ty - sy
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.05 then return nil end
        local there = Combat.squareAt(sx + dx / length, sy + dy / length, sz)
        if there ~= nil and there ~= here and Combat.footEdgeBarrier(here, there) then return "barrier" end
        return nil
    end)
    if ok then return reason end
    return nil
end

function Combat.backpedalOver(reach)
    local selfReach = math.max(tonumber(Combat.settings.leashSelfDefenceReach) or 1.5, tonumber(reach) or 1)
    return math.max(0, math.min(tonumber(Combat.settings.meleeBackpedalOver) or 0, selfReach - (tonumber(reach) or 1)))
end

function Combat.noteFootBlocked(reason)
    local metrics = Combat.metrics
    metrics.footBlocked = (metrics.footBlocked or 0) + 1
    Combat.footBlockedBy = Combat.footBlockedBy or {}
    Combat.footBlockedBy[reason] = (Combat.footBlockedBy[reason] or 0) + 1
end

function Combat.footworkPace(aim)
    return type(aim) == "table" and aim.footworkKind ~= nil and "guard" or "walk"
end

function Combat.footworkBegin(shell, aim, now, kind)
    local s = Combat.settings
    local metrics = Combat.metrics
    metrics.footSteps = (metrics.footSteps or 0) + 1
    if kind == "crewSideSteps" then
        metrics.footSide = (metrics.footSide or 0) + 1
    elseif kind == "meleeBackSteps" or kind == "crewRetreats" or kind == "crewBackpedals" then
        metrics.footBack = (metrics.footBack or 0) + 1
    end
    if s.meleeFacing == false or type(aim) ~= "table" then return false end
    local data = Combat.dataOf(shell)
    if data == nil or data.ProjectALifeWoundLeg == true then return false end
    local carry = data.ProjectALifeWeaponClass
    if carry == "rifle" or carry == "handgun" then return false end
    data.ProjectALifeFootworkUntilMs = now + (tonumber(s.meleeFacingMs) or 1800)
    data.ProjectALifeFootworkTicks, data.ProjectALifeFootworkKept = 0, 0
    aim.footworkKind, aim.footworkAtMs = kind, now
    return true
end

function Combat.footworkEnd(shell, aim, target)
    if type(aim) ~= "table" or aim.footworkKind == nil then return false end
    local metrics = Combat.metrics
    local data = Combat.dataOf(shell)
    if data ~= nil then
        local ticks = tonumber(data.ProjectALifeFootworkTicks) or 0
        if ticks > 0 and (tonumber(data.ProjectALifeFootworkKept) or 0) >= ticks * 0.8 then
            metrics.footFacingKept = (metrics.footFacingKept or 0) + 1
        end
        data.ProjectALifeFootworkUntilMs = nil
        data.ProjectALifeFootworkTicks, data.ProjectALifeFootworkKept = nil, nil
    end
    aim.footworkKind, aim.footworkAtMs = nil, nil
    if target ~= nil then
        local sx, sy = Combat.xyzOf(shell)
        local tx, ty = Combat.xyOf(target)
        local weapon = Combat.weaponFor(shell)
        if sx ~= nil and tx ~= nil and weapon ~= nil
                and math.sqrt((sx - tx) ^ 2 + (sy - ty) ^ 2) <= Combat.meleeReachFor(weapon, target) then
            metrics.footReengaged = (metrics.footReengaged or 0) + 1
        end
    end
    return true
end

function Combat.meleeBackStep(actor, shell, target, aim, now, weapon)
    local s = Combat.settings
    if type(aim) ~= "table" or target == nil or Combat.meleeReady(shell, now)
            or now < (tonumber(aim.nextKiteAtMs) or 0) then return nil end
    local sx, sy = Combat.xyzOf(shell)
    local tx, ty = Combat.xyOf(target)
    if sx == nil or tx == nil then return nil end
    local crowd = math.floor(tonumber(s.meleeKiteCrowd) or 2)
    local forward = s.meleeFootwork ~= false
    if crowd <= 0 and not forward then return nil end
    local gap = math.sqrt((sx - tx) ^ 2 + (sy - ty) ^ 2)
    local reach = Combat.meleeReachFor(weapon, target)
    local tiles = tonumber(s.meleeKiteTiles) or 2
    local zombies = Combat.footZombies(shell, tiles + 0.5)
    local pressing, pushX, pushY = 0, 0, 0
    for _, other in ipairs(zombies) do
        if other.facing >= 0.3 or other.distance <= 1.0 then
            local weight = 1 / math.max(other.distance, 0.5)
            pressing = pressing + 1
            pushX = pushX + (sx - other.x) / math.max(other.distance, 0.1) * weight
            pushY = pushY + (sy - other.y) / math.max(other.distance, 0.1) * weight
        end
    end
    local lastGap = aim.footGap
    aim.footGap = gap
    local point, kind
    local hold = Combat.footworkHold(shell, target)
    local crew = ProjectALife.MeleeCrew
    if crew ~= nil and type(crew.footwork) == "function" then
        point, kind = crew.footwork(actor, shell, target, aim, now, { gap = gap, reach = reach,
            zombies = zombies, pressing = pressing, pushX = pushX, pushY = pushY, crowd = crowd, hold = hold,
            backTiles = tonumber(s.meleeBackpedal) or 0, backOver = Combat.backpedalOver(reach) })
    end
    if point == nil and kind ~= "hold" and crowd > 0 and pressing >= crowd then
        local step = math.min(tonumber(s.meleeKiteStep) or 1.6, reach - 0.15 - gap)
        if step >= 0.3 and hold ~= nil then
            Combat.noteFootBlocked(hold)
        elseif step >= 0.3 then
            point = Combat.footPoint(shell, pushX, pushY, step, target, reach)
            if point == nil then point = Combat.footPoint(shell, sx - tx, sy - ty, step, target, reach) end
            if point == nil then Combat.noteFootBlocked("wall") end
            kind = "meleeBackSteps"
        end
    elseif point == nil and kind ~= "hold" and forward and #zombies <= 1 then
        local ideal = math.min(1.1, reach * 0.6)
        local backing = lastGap ~= nil and gap - lastGap >= 0.35
        local lead = tonumber(s.meleeStepIn) or 1.1
        if backing then lead = lead * 1.5 end
        local step = math.min(lead, gap - ideal)
        if step >= 0.3 and (backing or gap > ideal + 0.3) and gap <= reach + lead then
            point = Combat.footPoint(shell, tx - sx, ty - sy, step, target, nil)
            kind = "meleeStepIns"
        end
    end
    point = Combat.leashOffer(actor, point)
    if point == nil then
        aim.nextKiteAtMs = now + 250
        return nil
    end
    aim.nextKiteAtMs = Combat.meleeReadyAtMs(shell) or now
    Combat.metrics[kind] = (Combat.metrics[kind] or 0) + 1
    Combat.footworkBegin(shell, aim, now, kind)
    return point
end

function Combat.restampPace(shell, previous, pace, now)
    if previous.pace == "walk" and pace == "run"
            and not Movement.sprintActive(shell, now)
            and now - (previous.paceChangedAtMs or previous.atMs) < 1500 then
        return "walk"
    end
    Movement.setPace(shell, pace)
    previous.pace = pace
    previous.paceChangedAtMs = now
    return pace
end

local function pathToward(shell, destination, pace, force)
    if type(destination) ~= "table" then return false end

    if Combat.inClip(shell) then
        Combat.metrics.clipDeferred = (Combat.metrics.clipDeferred or 0) + 1
        return true
    end
    destination = Combat.adminBound(shell, destination)
    if destination ~= nil then destination = Combat.homeBound(shell, destination) end
    if destination == nil then
        if Combat.pathRequests[shell] ~= nil then
            Combat.pathRequests[shell] = nil
            Movement.stop(shell)
        end
        return true
    end
    destination = Movement.safeDestination(nil, shell, destination)
    local previous = Combat.pathRequests[shell]
    local now = Combat.nowMs()

    if Combat.clipEcho(shell, now) then
        Combat.metrics.clipDeferred = (Combat.metrics.clipDeferred or 0) + 1
        return true
    end

    local leg, legFresh = Combat.routeLeg(shell, destination, now)
    if leg == true then
        if Combat.pathRequests[shell] ~= nil then
            Combat.pathRequests[shell] = nil
            Movement.stop(shell)
        end
        Combat.holdStill(shell)
        return true
    elseif leg ~= nil then
        destination = leg
    end

    local stepOff = Combat.stepOffLeg(shell, now)
    if stepOff ~= nil then destination = stepOff end

    if not Traversal.isBusy(shell) and Traversal.openDoorAhead(shell, destination) then
        previous = nil
        Combat.pathRequests[shell] = nil
        force = true
    end

    local answer = Combat.refusalAnswer(shell, destination, now)
    if answer == true then
        if Combat.pathRequests[shell] ~= nil then
            Combat.pathRequests[shell] = nil
            Movement.stop(shell)
        end
        Combat.holdStill(shell)
        local holdAim = Combat.aimStateFor(shell)
        holdAim.climbHoldSamples = (holdAim.climbHoldSamples or 0) + 1
        Combat.metrics.climbHolds = (Combat.metrics.climbHolds or 0) + 1
        return true
    elseif type(answer) == "table" then
        destination = answer
    elseif not force and Traversal.climbRefusedRecently(shell, now,
            answer == nil and (tonumber(Combat.settings.climbHoldMs) or 8000) or 0) then
        if Combat.pathRequests[shell] ~= nil then
            Combat.pathRequests[shell] = nil
            Movement.stop(shell)
        end
        local holdAim = Combat.aimStateFor(shell)
        holdAim.climbHoldSamples = (holdAim.climbHoldSamples or 0) + 1
        Combat.metrics.climbHolds = (Combat.metrics.climbHolds or 0) + 1
        return true
    end
    local repathMs = tonumber(Combat.settings.pursuitRepathMs) or 1100
    local threshold = tonumber(Combat.settings.combatRepathDistance) or 1.5
    local pathStallMs = tonumber(Combat.settings.pathStallMs) or 3500
    local pathStartupGraceMs = tonumber(Combat.settings.pathStartupGraceMs) or 6000
    local positionOk, currentX, currentY, currentZ = pcall(function()
        return shell:getX(), shell:getY(), shell:getZ()
    end)
    local stalled = false

    if not force and legFresh ~= true and previous ~= nil then
        local dx, dy, dz = destination.x - previous.x,
            destination.y - previous.y, destination.z - previous.z
        if positionOk and previous.lastX ~= nil then
            local movedX, movedY, movedZ = currentX - previous.lastX,
                currentY - previous.lastY, currentZ - previous.lastZ
            if movedX * movedX + movedY * movedY + movedZ * movedZ >= 0.04 then
                previous.lastX, previous.lastY, previous.lastZ =
                    currentX, currentY, currentZ
                previous.lastProgressAtMs = now
                previous.started = true

                if previous.stepOff ~= true then
                    previous.moved = true
                    Combat.clearUnstarted(Combat.aimState[shell])
                end
            end
        end
        local pathPhase = Movement.pathPhase(shell)
        if not previous.started and pathPhase == "started" then
            previous.started = true
        end
        local sameDestination = dx * dx + dy * dy + dz * dz
            < threshold * threshold
        local pending = not previous.started and pathPhase == "pending"

        if pathPhase == "failed" or pathPhase == "cancelled" then stalled = true end
        stalled = stalled or now - (previous.lastProgressAtMs or previous.atMs)
            >= (pending and math.max(pathStallMs, pathStartupGraceMs) or pathStallMs)

        if not stalled and (previous.stepOff == true or Combat.landedRecently(shell, now))
                and not Combat.serverSide()
                and now - (previous.lastProgressAtMs or previous.atMs)
                    >= (tonumber(Combat.settings.pathNoStartMs) or 1000) then
            stalled = true
        end
        if sameDestination and previous.pace ~= pace and not stalled then

            pace = Combat.restampPace(shell, previous, pace, now)
        end

        local arrived = false
        if positionOk then
            local ax, ay = currentX - destination.x, currentY - destination.y
            arrived = ax * ax + ay * ay <= threshold * threshold
        end
        local drifted = dx * dx + dy * dy + dz * dz > 0.1225
        local destinationStable = sameDestination and not (arrived and drifted)

        if not sameDestination and previous.pace ~= pace and not stalled
                and (pending or now - previous.atMs < repathMs) then
            Combat.restampPace(shell, previous, pace, now)
        end
        if pending and not stalled then return true end
        if destinationStable and not stalled then return true end
        if not stalled and now - previous.atMs < repathMs then return true end
    end

    if stalled then
        if Traversal.isBusy(shell) then return true end
        Traversal.consumeResult(shell)

        if Traversal.try(shell, destination, Combat.noClimbFor(shell), true) then
            Combat.pathRequests[shell] = nil
            return true
        end

        local idleMs = now - (previous.lastProgressAtMs or previous.atMs)
        if positionOk and previous.counted ~= true and not Combat.serverSide()
                and previous.moved ~= true
                and idleMs >= math.min(pathStallMs, tonumber(Combat.settings.pathNoStartMs) or 1000)
                and (previous.stepOff == true
                    or (currentX - destination.x) ^ 2 + (currentY - destination.y) ^ 2 > threshold * threshold) then
            previous.counted = true
            local verdict = Combat.noteUnstarted(shell, destination, now)
            if verdict == true then
                Combat.pathRequests[shell] = nil
                Movement.stop(shell)
                return true
            elseif type(verdict) == "table" then
                destination, stepOff = verdict, verdict
            end
        end
    end

    if not force and not stalled and Movement.pathPhase(shell) == "started" then

        local request = Combat.pathRequests[shell]
        if request ~= nil and request.pace ~= nil and request.pace ~= pace then

            if request.pace == "walk" and pace == "run"
                    and not Movement.sprintActive(shell, now)
                    and now - (request.paceChangedAtMs or 0) < 1500 then
                pace = request.pace
            else
                request.paceChangedAtMs = now
            end
        end
        Movement.setPace(shell, pace)
        local aimed = pcall(function()
            local behavior = shell:getPathFindBehavior2()
            if behavior == nil then error("path_behavior_unavailable") end
            requestPath(shell, behavior, destination.x, destination.y, destination.z)
        end)
        if aimed then
            Movement.setPathActive(shell, true)
            local request = Combat.pathRequests[shell]
            if request ~= nil then

                if request.stepOff == true and stepOff == nil and positionOk then
                    request.lastX, request.lastY, request.lastZ = currentX, currentY, currentZ
                    request.lastProgressAtMs = now
                end
                request.x, request.y, request.z =
                    destination.x, destination.y, destination.z
                request.pace, request.atMs = pace, now
                request.stepOff = stepOff ~= nil or nil
            end
            return true
        end
    end

    local aimState = Combat.aimStateFor(shell)
    local rebuiltAt = aimState.rebuiltAtMs
    if rebuiltAt ~= nil and now >= rebuiltAt
            and now - rebuiltAt < (tonumber(Combat.settings.rebuildMinimumMs) or 600) then
        Combat.metrics.rebuildsDeferred = (Combat.metrics.rebuildsDeferred or 0) + 1
        Movement.setPace(shell, pace)
        return true
    end
    pcall(function() shell:setUseless(true) end)
    local clearOk = pcall(function() shell:setTarget(nil) end)
    Animations.cancelForLocomotion(shell)
    Movement.setPace(shell, pace)
    local pathOk = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior == nil then error("path_behavior_unavailable") end
        behavior:cancel()
        if type(behavior.reset) == "function" then behavior:reset() end
        if type(shell.setPath2) == "function" then shell:setPath2(nil) end
        if type(shell.setTarget) == "function" then shell:setTarget(nil) end
        if type(shell.clearAggroList) == "function" then shell:clearAggroList() end
        requestPath(shell, behavior, destination.x, destination.y, destination.z)

        if type(shell.setVariable) == "function" then shell:setVariable("bPathfind", true) end
        if PathFindState ~= nil then
            shell:changeState(PathFindState.instance())
        end
    end)
    if pathOk then
        aimState.rebuiltAtMs = now
        Movement.setPathActive(shell, true)
        local pathPhase = Movement.pathPhase(shell)
        Combat.pathRequests[shell] = {
            x = destination.x, y = destination.y, z = destination.z,
            pace = pace, atMs = now,
            lastX = positionOk and currentX or nil,
            lastY = positionOk and currentY or nil,
            lastZ = positionOk and currentZ or nil,
            lastProgressAtMs = previous ~= nil and positionOk and previous.lastX ~= nil
                and (currentX - previous.lastX) ^ 2 + (currentY - previous.lastY) ^ 2
                    + (currentZ - previous.lastZ) ^ 2 < 0.04
                and previous.lastProgressAtMs or now,
            started = pathPhase == "started",
            stepOff = stepOff ~= nil or nil,
        }
    end
    return clearOk and pathOk
end

local function disengage(shell)
    if ProjectALife.FireManeuver then ProjectALife.FireManeuver.clear(shell,"disengage") end
    if type(Combat.adapters.disengage) == "function" then
        return Combat.adapters.disengage(shell) ~= false
    end
    pcall(function() shell:setUseless(true); shell:setTarget(nil) end)

    if Combat.postureUntilMs[shell] == nil then
        Combat.setAimWalk(shell, false, "disengaged")
    end

    if Combat.inClip(shell) then
        Combat.metrics.clipDeferred = (Combat.metrics.clipDeferred or 0) + 1
        Combat.aimStateFor(shell).cancelAfterClip = Combat.pathRequests[shell] or true
    else
        cancelPath(shell)
        local held = Combat.aimState[shell]
        if held ~= nil then held.cancelAfterClip = nil end
    end
    Combat.pathRequests[shell] = nil
    Combat.footworkEnd(shell, Combat.aimState[shell], nil)

    pcall(function()
        shell:getModData().ProjectALifeCombatLullUntilMs = Combat.nowMs() + 3500
    end)

    pcall(function()
        local data = shell:getModData()
        local uid = type(data) == "table" and data.ProjectALifeUID or nil
        if type(uid) ~= "string" or uid == "" then return end
        local talk = ProjectALife.Talk
        if talk == nil or type(talk.writeMemory) ~= "function" then return end
        local window = tonumber(Combat.settings.searchWindowMs) or 45000
        talk.writeMemory(uid, function(memory)

            memory.searchBodiesLeft = math.max(tonumber(memory.searchBodiesLeft) or 0, 2)
            memory.searchUntilMs = Combat.nowMs() + window
        end)
    end)

    local state = Combat.aimState[shell]
    if state ~= nil and state.leg ~= nil then state.leg.active = false end
    local warm = state ~= nil and Combat.nowMs() < (state.warmUntilMs or 0)

    if not warm then
        pcall(function()
            local data = shell:getModData()
            warm = tostring(data.ProjectALifeDangerPosture or "relaxed") ~= "relaxed"
                or (Combat.postureUntilMs[shell] or 0) > Combat.nowMs()
        end)
    end
    if state ~= nil then state.readyAtMs = nil end
    if not warm then
        pcall(Animations.setCombatHold, shell, false)
        Animations.clear(shell)
    else

        local current = Animations.current and Animations.current[shell]
        if type(current) == "string" and string.find(current, "reload", 1, true) then
            Animations.clear(shell)
        end
    end
    pcall(function() shell:getModData().ProjectALifeSprintUntilMs = nil end)
    Combat.setPhase(shell, "idle", "none", nil)
    return true
end

Combat.stanceLeash = {
    garrison = 6,
    holdout = 5,
    occupy_high = 5,
    shelter = 6,
    camp = 10,
    blockade = 8,
    defend = 14,
}

function Combat.leashedPoint(anchor, destination, leash)
    if type(anchor) ~= "table" or type(destination) ~= "table" then return destination end
    leash = tonumber(leash)
    if leash == nil or leash <= 0 then return destination end
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    local dx = (tonumber(destination.x) or 0) - (ax or 0)
    local dy = (tonumber(destination.y) or 0) - (ay or 0)
    if ax == nil or ay == nil then return destination end
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat <= leash or flat < 0.001 then return destination end
    local scale = leash / flat
    return { x = ax + dx * scale, y = ay + dy * scale,
        z = destination.z or anchor.z or 0 }
end

function Combat.leashFor(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table"
        and actor.memory or nil
    if memory == nil then return nil, nil end
    local stance = type(memory.stance) == "string" and memory.stance or nil
    if stance == nil then return nil, nil end
    if stance == "blockade" and memory.encounterKind == "highway_ambush"
            and memory.holdPost ~= true and memory.garrisonPost == nil then return nil, nil end
    local leash = Combat.stanceLeash[stance]
    if leash == nil then return nil, nil end

    local post = memory.garrisonPost
    if type(post) == "table" and tonumber(post.x) ~= nil and tonumber(post.y) ~= nil then
        if memory.holdPost == true then return post, Combat.settings.holdPostLeash or 1 end
        return post, leash
    end
    local anchor = memory.stanceAnchor
    if type(anchor) ~= "table" then return nil, nil end
    return anchor, leash
end

function Combat.blockedLineTimeout(shell)
    local data = Combat.dataOf(shell)
    if data ~= nil and data.ProjectALifeConduct == "gunner" then return 700 end
    return Combat.settings.blockedLineTimeoutMs
end

function Combat.leashEdgeHold(shell, anchor, clamped, leash, target)
    if type(anchor) ~= "table" or type(clamped) ~= "table" then return false end
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(target)
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    leash = tonumber(leash)
    if sx == nil or tx == nil or ax == nil or ay == nil or leash == nil then return false end
    local band = tonumber(Combat.settings.combatRepathDistance) or 1.5
    local fromAnchor = math.sqrt((sx - ax) ^ 2 + (sy - ay) ^ 2)
    if fromAnchor < leash - band then return false end

    if fromAnchor > leash + (tonumber(Combat.settings.leashReturnSlack) or 1) then
        Combat.metrics.leashReturns = (Combat.metrics.leashReturns or 0) + 1
        return false
    end
    local here = math.sqrt((sx - tx) ^ 2 + (sy - ty) ^ 2)
    local there = math.sqrt((clamped.x - tx) ^ 2 + (clamped.y - ty) ^ 2)
    return there > here - 1
end

function Combat.selfDefence(shell, target)
    local reach = tonumber(Combat.settings.leashSelfDefenceReach) or 1.5
    local weapon = Combat.weaponFor(shell)
    if weapon ~= nil and not Combat.isRanged(weapon) then
        reach = math.max(reach, Combat.meleeReachFor(weapon, target))
    end
    return Combat.distanceSquared(shell, target) <= reach * reach
end

function Combat.grudgeSortie(actor, shell, target, now)
    local perception = ProjectALife.Perception
    if target == nil or shell == nil or type(actor) ~= "table" or type(actor.uid) ~= "string"
            or perception == nil or type(perception.attackers) ~= "table" then return nil end
    if type(actor.memory) == "table" and actor.memory.holdPost == true then return nil end
    local grudge = perception.attackers[actor.uid]
    if type(grudge) ~= "table" or grudge.attacker ~= target or grudge.kind == "zombie" then return nil end
    now = tonumber(now) or Combat.nowMs()
    if now >= (tonumber(grudge.untilMs) or 0) then return nil end
    local blowAt = tonumber(grudge.atMs)
    if blowAt == nil or now - blowAt > (tonumber(Combat.settings.leashGrudgeMs) or 10000) then return nil end
    local weapon = Combat.weaponFor(shell)
    if weapon == nil or Combat.isRanged(weapon) then return nil end
    return tonumber(Combat.settings.leashSortie) or 4
end

function Combat.combatLeash(actor, shell, target)
    local anchor, leash = Combat.leashFor(actor)
    if anchor == nil or Combat.selfDefence(shell, target) then return nil, nil end
    local sortie = Combat.grudgeSortie(actor, shell, target)
    if sortie ~= nil and tonumber(leash) ~= nil then
        Combat.metrics.sortieTicks = (Combat.metrics.sortieTicks or 0) + 1
        return anchor, leash + sortie
    end
    return anchor, leash
end

function Combat.leashOutside(shell, anchor, leash)
    local sx, sy = Combat.xyOf(shell)
    leash = tonumber(leash)
    if sx == nil or type(anchor) ~= "table" or leash == nil or leash <= 0 then return nil end
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    if ax == nil or ay == nil then return nil end
    local fromAnchor = math.sqrt((sx - ax) ^ 2 + (sy - ay) ^ 2)
    if fromAnchor <= leash + (tonumber(Combat.settings.leashReturnSlack) or 1) then return nil end
    return fromAnchor
end

function Combat.leashReturnPoint(shell, anchor, leash)
    if Combat.leashOutside(shell, anchor, leash) == nil then return nil end
    local sx, sy, sz = Combat.xyzOf(shell)
    if sx == nil then return nil end
    Combat.metrics.leashReturns = (Combat.metrics.leashReturns or 0) + 1
    return Combat.leashedPoint(anchor, { x = sx, y = sy, z = sz }, leash)
end

function Combat.refuseOffLeash(actor, shell, now)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then return end
    Combat.leashRefusals[actor.uid] = {
        untilMs = now + (tonumber(Combat.settings.leashRefuseMs) or 10000), shell = shell }
end

function Combat.leashGiveUp(actor, shell, target, weapon, now)
    local anchor, leash = Combat.leashFor(actor)
    if anchor == nil or Combat.leashOutside(shell, anchor, leash) == nil then return false end
    Combat.refuseOffLeash(actor, shell, now)
    Combat.watchFromPost(actor, shell, target, weapon)
    return true
end

function Combat.leashTargetClosing(aim, distance)
    local baseline, now = tonumber(aim.leashHoldDistance), tonumber(distance)
    if baseline == nil or now == nil then return false end
    return now <= baseline - (tonumber(Combat.settings.leashClosingTiles) or 0.8)
end

function Combat.holdOnLeash(shell, aim, heldSince, now)
    Combat.holdStill(shell)
    Combat.metrics.leashHolds = (Combat.metrics.leashHolds or 0) + 1
    aim.leashHoldSinceMs = heldSince or now
    aim.leashHoldSamples = (aim.leashHoldSamples or 0) + 1
    return nil
end

Combat.homeFrom = { x = 0, y = 0, z = 0 }
function Combat.homeNeedsClimb(shell, anchor, leash, destination, now)
    if type(destination) ~= "table" or Combat.leashOutside(shell, anchor, leash) == nil then return false end
    local stances = ProjectALife.ModuleStances
    if stances == nil or type(stances.reachableWithoutClimb) ~= "function" then return false end
    local x, y, z = Combat.xyzOf(shell)
    if x == nil then return false end
    local from = Combat.homeFrom
    from.x, from.y, from.z = x, y, z
    return stances.reachableWithoutClimb(from, destination, now) ~= true
end

function Combat.offLeashRefused(actor, target, now)
    local uid = type(actor) == "table" and actor.uid or nil
    local refusal = uid ~= nil and Combat.leashRefusals[uid] or nil
    if refusal == nil then return false end
    if now >= refusal.untilMs then
        Combat.leashRefusals[uid] = nil
        return false
    end
    if Combat.targetBeyondLeash(actor, refusal.shell, target, now) then
        Combat.metrics.leashRefused = (Combat.metrics.leashRefused or 0) + 1
        return true, refusal.untilMs
    end
    return false
end

function Combat.postTargetRefused(actor, shell, target, now)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if shell == nil or memory == nil or memory.holdPost ~= true or Combat.kindOf(target) ~= "zombie"
            or Combat.retaliating(actor, target, now) then return false end
    return Combat.targetBeyondLeash(actor, shell, target, now)
end

function Combat.targetBeyondLeash(actor, shell, target, now)
    local anchor, leash = Combat.leashFor(actor)
    local tx, ty = Combat.xyOf(target)
    local ax = anchor ~= nil and tonumber(anchor.x) or nil
    local ay = anchor ~= nil and tonumber(anchor.y) or nil
    leash = tonumber(leash)
    if ax == nil or ay == nil or leash == nil or tx == nil then return false end
    local reach = leash + (tonumber(Combat.settings.leashRefuseMargin) or 1)
        + (Combat.grudgeSortie(actor, shell, target, now) or 0)
    if (tx - ax) ^ 2 + (ty - ay) ^ 2 <= reach * reach then return false end
    if shell ~= nil then
        if Combat.selfDefence(shell, target) then return false end
        local weapon = Combat.weaponFor(shell)
        if weapon ~= nil and Combat.isRanged(weapon) then
            local range = Combat.engagementReach(weapon, shell, target)
            if Combat.distanceSquared(shell, target) <= range * range then return false end
        end
    end
    return true
end

function Combat.leashOffer(actor, point)
    if type(point) ~= "table" then return point end
    local anchor, leash = Combat.leashFor(actor)
    leash = tonumber(leash)
    if type(anchor) ~= "table" or leash == nil then return point end
    local px, py = tonumber(point.x), tonumber(point.y)
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    if px == nil or py == nil or ax == nil or ay == nil then return point end
    if (px - ax) ^ 2 + (py - ay) ^ 2 <= leash * leash then return point end
    Combat.metrics.offersLeashed = (Combat.metrics.offersLeashed or 0) + 1
    return nil
end

Combat.DOORS_ONLY = { doorsOnly = true }

function Combat.noClimbFor(shell)
    local aim = shell ~= nil and Combat.aimState[shell] or nil
    return aim ~= nil and aim.noClimb == true
end

function Combat.cutClimb(shell)
    if not Combat.noClimbFor(shell) then return false end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.refuseNative) ~= "function" then return false end
    if traversal.refuseNative(shell) ~= true then return false end
    local walking = Combat.pathRequests[shell] ~= nil or Combat.pathLive(shell)
    Combat.cancelPath(shell)
    Combat.pathRequests[shell] = nil
    Combat.holdStill(shell)
    if walking then Combat.metrics.climbsCut = (Combat.metrics.climbsCut or 0) + 1 end
    return true
end

function Combat.watchFromPost(actor, shell, target, weapon)
    Combat.pendingWatch = nil
    local sx, sy, sz = Combat.xyzOf(shell)
    if sx == nil or weapon == nil or type(actor) ~= "table" then return nil end
    local ranged = Combat.isRanged(weapon)
    local reach = ranged and Combat.engagementReach(weapon, shell, target)
        or Combat.meleeReachFor(weapon, target)
    Combat.pendingWatch = { uid = actor.uid, target = target, x = sx, y = sy, z = sz,
        reach = reach, melee = not ranged }
    return Combat.pendingWatch
end

function Combat.guardBand(weapon, target)
    local band = tonumber(Combat.settings.readyGuardRange) or 4
    if Combat.targetIsGunman(target) then
        band = tonumber(Combat.settings.readyGuardRangeVersusGun) or 1.6
    end

    local strikeReach = Combat.meleeReachFor(weapon, target)
    return math.max(band, strikeReach + 0.3)
end

function Combat.burstFloor(weapon, target, standoff)
    if weapon == nil or Combat.isRanged(weapon) then return standoff end
    return math.max(standoff, Combat.guardBand(weapon, target))
end

function Combat.meleePressing(aim, shell, target, now)
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(target)
    if aim == nil or sx == nil or tx == nil then return false end
    if aim.pressTarget ~= target or aim.pressAtMs == nil or now < aim.pressAtMs
            or now - aim.pressAtMs > 1500 then
        aim.pressTarget, aim.pressAtMs = target, now
        aim.pressX, aim.pressY, aim.pressOpening, aim.pressing = tx, ty, 0, false
        aim.pressVX, aim.pressVY = 0, 0
        return false
    end
    local dt = (now - aim.pressAtMs) / 1000
    if dt >= 0.2 then
        local ux, uy = tx - sx, ty - sy
        local length = math.sqrt(ux * ux + uy * uy)
        if length > 0.01 then
            local opening = ((tx - aim.pressX) * ux + (ty - aim.pressY) * uy) / length / dt
            aim.pressOpening = 0.5 * (aim.pressOpening or 0) + 0.5 * opening
        end
        aim.pressVX, aim.pressVY = (tx - aim.pressX) / dt, (ty - aim.pressY) / dt
        aim.pressX, aim.pressY, aim.pressAtMs = tx, ty, now
    end

    local opening = aim.pressOpening or 0
    if aim.pressing == true then
        aim.pressing = opening > (tonumber(Combat.settings.meleePressRelease) or 0.25)
    else
        aim.pressing = opening > (tonumber(Combat.settings.meleePressOpening) or 0.5)
    end
    return aim.pressing
end

function Combat.pressWalker(aim, target)
    if aim == nil or aim.pressing ~= true or aim.pressTarget ~= target or target == nil then return false end
    local ok, runs = pcall(function()
        return (target.isRunning ~= nil and target:isRunning() == true)
            or (target.isSprinting ~= nil and target:isSprinting() == true)
    end)
    return not (ok and runs == true)
end

function Combat.pressStrikeReach(aim, weapon, target)
    local reach = Combat.meleeReachFor(weapon, target)
    if not Combat.pressWalker(aim, target) then return reach end
    local opening = math.max(0, tonumber(aim.pressOpening) or 0)
    local windupMs = (tonumber(Combat.settings.meleeWindupMs) or 150) * (tonumber(Combat.meleeSwingScale(weapon)) or 1)
    local tickMs = tonumber(Combat.settings.pressTickMs) or 100
    local start = reach - opening * (windupMs + 2 * tickMs) / 1000
    return math.max(math.min(reach, tonumber(Combat.settings.pressStrikeFloor) or 0.62), start)
end

function Combat.pressClosing(aim, weapon, target, distance)
    if distance == nil or distance <= (tonumber(Combat.settings.meleeContactRange) or 0.85) then return false end
    return distance > Combat.pressStrikeReach(aim, weapon, target)
end

function Combat.pressLeadPoint(aim, target, inReach)
    local tx, ty, tz = Combat.xyzOf(target)
    if tx == nil then return nil end
    if inReach == true then return { x = tx, y = ty, z = tz } end
    local lead = (tonumber(Combat.settings.pressLeadMs) or 500) / 1000
    return { x = tx + (tonumber(aim.pressVX) or 0) * lead, y = ty + (tonumber(aim.pressVY) or 0) * lead, z = tz }
end

function Combat.walkableSquare(shell, x, y, z)
    if type(getCell) ~= "function" or getCell() == nil then return true end
    local square = Combat.squareAt(x, y, z)
    if square == nil then return false end
    if square.isFree ~= nil and square:isFree(false) ~= true then return false end
    if square.TreatAsSolidFloor ~= nil and square:TreatAsSolidFloor() ~= true then return false end
    local here = shell ~= nil and shell.getCurrentSquare ~= nil and shell:getCurrentSquare() or nil
    if here ~= nil and here.isOutside ~= nil and square.isOutside ~= nil
            and here:isOutside() ~= square:isOutside() then return false end
    return true
end

function Combat.walkEdgeStop(fromX, fromY, toX, toY)
    local cell, z = Combat.walkCell, Combat.walkZ
    local a, b = cell:getGridSquare(fromX, fromY, z), cell:getGridSquare(toX, toY, z)
    if a == nil or b == nil then return nil end
    if a.isBlockedTo ~= nil and (a:isBlockedTo(b) == true or b:isBlockedTo(a) == true) then return true end
    if a.isHoppableTo ~= nil and (a:isHoppableTo(b) == true or b:isHoppableTo(a) == true) then return true end
    return nil
end

function Combat.walkLegClear(x0, y0, x1, y1, z)
    local lineOfFire = ProjectALife.LineOfFire
    if type(getCell) ~= "function" or lineOfFire == nil or type(lineOfFire.cells) ~= "function" then
        return true
    end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return true end
    Combat.walkCell, Combat.walkZ = cell, math.floor((tonumber(z) or 0) + 0.05)
    local ok, outcome = pcall(lineOfFire.cells, x0, y0, x1, y1, 64, Combat.walkEdgeStop)
    Combat.walkCell = nil
    return ok and outcome ~= "stopped"
end

function Combat.approachStyle(actor, shell, target, destination, startedAtMs)
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(target)
    if sx ~= nil and tx ~= nil and type(destination) == "table" then
        local fx, fy = tx - sx, ty - sy
        local length = math.sqrt(fx * fx + fy * fy)
        if length > 0.01 then
            local lateral = (fx * (destination.y - sy) - fy * (destination.x - sx)) / length
            if lateral >= 0.75 then return 1 end
            if lateral <= -0.75 then return -1 end
        end
    end
    local data = Combat.dataOf(target)
    local key = data ~= nil and data.ProjectALifeUID or tostring(target)
    local roll = Combat.stableHash(tostring(actor and actor.uid) .. "|" .. tostring(key)
        .. "|" .. tostring(math.floor((tonumber(startedAtMs) or 0) / 10000))) % 100
    local straight = tonumber(Combat.settings.approachStraightPercent) or 40
    if roll < straight then return 0 end
    if roll < straight + (tonumber(Combat.settings.approachLeftPercent) or 30) then return 1 end
    return -1
end

function Combat.approachWaypoint(actor, shell, target, destination, now)
    if type(destination) ~= "table" or type(actor) ~= "table" then return destination end
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(target)
    if sx == nil or tx == nil then return destination end
    local s = Combat.settings
    local aim = Combat.aimStateFor(shell)
    local plan = aim.arcPlan
    if plan == nil then
        plan = { point = {} }
        aim.arcPlan = plan
    end
    if plan.target ~= target or plan.usedAtMs == nil or now < plan.usedAtMs
            or now - plan.usedAtMs > 4000 then
        plan.target, plan.startedAtMs, plan.style = target, now, nil
        plan.active, plan.passed = false, false
    end
    plan.usedAtMs = now
    local fx, fy = tx - sx, ty - sy
    local toTarget = math.sqrt(fx * fx + fy * fy)
    if math.abs(sz - tz) >= 0.4
            or toTarget <= (tonumber(s.approachStraightDistance) or 4) then
        plan.passed = true
        return destination
    end
    if plan.style == nil then
        plan.style = Combat.approachStyle(actor, shell, target, destination, plan.startedAtMs)
        plan.fraction = 0.4 + (Combat.stableHash(tostring(actor.uid) .. ":" .. tostring(plan.startedAtMs)) % 21) / 100
        if plan.style == 0 then
            Combat.metrics.approachStraight = (Combat.metrics.approachStraight or 0) + 1
        end
    end
    if plan.style == 0 or plan.passed then return destination end
    if plan.active then
        local mx, my = tx - plan.anchorX, ty - plan.anchorY
        local limit = tonumber(s.approachReplanDistance) or 2.5
        if mx * mx + my * my > limit * limit
                and now - plan.plannedAtMs >= (tonumber(s.approachReplanMs) or 1500) then
            plan.active = false
        end
    end
    if not plan.active then
        local dx, dy = destination.x - sx, destination.y - sy
        local leg = math.sqrt(dx * dx + dy * dy)
        if leg < (tonumber(s.approachArcMinimumDistance) or 5) then
            plan.passed = true
            return destination
        end
        local ux, uy = dx / leg, dy / leg
        local offset = math.max(tonumber(s.approachArcMinimumOffset) or 1.5,
            math.min(tonumber(s.approachArcMaximumOffset) or 4,
                leg * (tonumber(s.approachArcOffsetScale) or 0.3)))
        local along = leg * plan.fraction
        local placed = false
        for attempt = 1, 2 do
            local lateral = offset * plan.style * (attempt == 1 and 1 or 0.6)
            local wx, wy = sx + ux * along - uy * lateral, sy + uy * along + ux * lateral

            if Combat.walkableSquare(shell, wx, wy, sz)
                    and Combat.walkLegClear(sx, sy, wx, wy, sz)
                    and Combat.walkLegClear(wx, wy, destination.x, destination.y, sz) then
                plan.point.x, plan.point.y, plan.point.z = wx, wy, destination.z or sz
                placed = true
                break
            end
        end
        if not placed then
            plan.passed = true
            return destination
        end
        plan.active, plan.anchorX, plan.anchorY, plan.plannedAtMs = true, tx, ty, now
        Combat.metrics.approachArcs = (Combat.metrics.approachArcs or 0) + 1
    end

    local px, py = plan.point.x, plan.point.y
    local wx, wy = tx - px, ty - py
    if (sx - px) ^ 2 + (sy - py) ^ 2 <= 1.5625 or fx * fx + fy * fy < wx * wx + wy * wy then
        plan.passed = true
        return destination
    end
    return plan.point
end

function Combat.openingWithin(cell, sx, sy, z, building, radius)
    local limit = radius * radius
    for x = math.floor(sx - radius), math.floor(sx + radius) do
        for y = math.floor(sy - radius), math.floor(sy + radius) do
            for step = 1, 2 do
                local nx, ny = x + (step == 1 and 1 or 0), y + (step == 2 and 1 or 0)
                local mx, my = step == 1 and x + 1 or x + 0.5, step == 2 and y + 1 or y + 0.5
                if (mx - sx) ^ 2 + (my - sy) ^ 2 <= limit then
                    local a, b = cell:getGridSquare(x, y, z), cell:getGridSquare(nx, ny, z)
                    if a ~= nil and b ~= nil and a.getBuilding ~= nil
                            and (a:getBuilding() == building) ~= (b:getBuilding() == building) then
                        if (a.getDoorTo ~= nil and a:getDoorTo(b) ~= nil)
                                or (a.getWindowTo ~= nil and a:getWindowTo(b) ~= nil)
                                or (a.getWindowFrameTo ~= nil and a:getWindowFrameTo(b) ~= nil) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function Combat.nearOpening(sx, sy, sz, building, radius)
    if building == nil or type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return false end
    local ok, near = pcall(Combat.openingWithin, cell, sx, sy, math.floor(sz + 0.05), building, radius)
    return ok and near == true
end

function Combat.entranceLeg(actor, shell, target, destination, now, distance)
    if type(destination) ~= "table" then return destination end
    local entrances = ProjectALife.Entrances
    if entrances == nil or type(entrances.claimFor) ~= "function" then return destination end
    local aim = Combat.aimStateFor(shell)
    local leg = aim.leg
    if distance ~= nil and distance <= (tonumber(Combat.settings.entranceSkipDistance) or 3) then
        if leg ~= nil then leg.active = false end
        return destination
    end
    local sx, sy, sz = Combat.xyzOf(shell)
    if sx == nil or math.abs(sz - (tonumber(destination.z) or sz)) >= 0.4 then return destination end
    if leg == nil then
        leg = { point = {} }
        aim.leg = leg
    end
    local here = Combat.buildingAt(sx, sy, sz)
    if leg.active and (here ~= leg.fromBuilding or now < leg.atMs or now - leg.atMs > 8000) then
        leg.active = false
        leg.checkedAtMs = now
        return destination
    end
    if leg.active and leg.stage == "wait" and now - leg.atMs >= (tonumber(Combat.settings.entranceLegMs) or 1500) then
        leg.active = false
    end
    if not leg.active then
        if leg.checkedAtMs ~= nil and now >= leg.checkedAtMs
                and now - leg.checkedAtMs < (tonumber(Combat.settings.entranceLegMs) or 1500) then
            return destination
        end
        leg.checkedAtMs = now
        local there = Combat.buildingAt(destination.x, destination.y, destination.z)
        if here == there then return destination end

        if Combat.nearOpening(sx, sy, sz, there or here,
                tonumber(Combat.settings.entranceNearOpening) or 1.5) then
            Combat.metrics.entranceLegsSkipped = (Combat.metrics.entranceLegsSkipped or 0) + 1
            return destination
        end
        local opts = leg.opts
        if opts == nil then
            opts = {}
            leg.opts = opts
        end
        opts.actor, opts.now = actor, now
        local opening = entrances.claimFor(shell, destination.x, destination.y, destination.z, opts)
        opts.actor = nil
        if type(opening) ~= "table" or tonumber(opening.x) == nil or tonumber(opening.y) == nil then
            return destination
        end

        local ax, ay = opening.x, opening.y
        local bx, by = tonumber(opening.crossX), tonumber(opening.crossY)
        if bx == nil or by == nil then bx, by = destination.x, destination.y end
        leg.nearX, leg.nearY, leg.farX, leg.farY = ax, ay, bx, by
        leg.z = tonumber(opening.z) or destination.z
        local cross = leg.cross
        if cross == nil then
            cross = {}
            leg.cross = cross
        end
        cross.x, cross.y, cross.z = bx, by, leg.z
        leg.active, leg.atMs, leg.fromBuilding = true, now, here
        leg.stage = (sx - ax) ^ 2 + (sy - ay) ^ 2 <= 2.25 and "crossing" or "approach"
        if leg.stage == "approach" and (opening.shared == true or opening.status == "shared") then
            leg.stage = "wait"
        end
        Combat.metrics.entranceLegs = (Combat.metrics.entranceLegs or 0) + 1
    end
    local point = leg.point
    if leg.stage == "wait" then

        local nx, ny = leg.nearX - leg.farX, leg.nearY - leg.farY
        local length = math.sqrt(nx * nx + ny * ny)
        if length < 0.01 then nx, ny, length = 1, 0, 1 end
        nx, ny = nx / length, ny / length
        local side = Combat.sideOf(actor, aim)
        local wx, wy = leg.nearX + nx * 1.5 - ny * side, leg.nearY + ny * 1.5 + nx * side
        if not Combat.walkableSquare(shell, wx, wy, sz) then
            wx, wy = leg.nearX + nx * 1.5 + ny * side, leg.nearY + ny * 1.5 - nx * side
            if not Combat.walkableSquare(shell, wx, wy, sz) then wx, wy = leg.nearX, leg.nearY end
        end
        if (sx - wx) ^ 2 + (sy - wy) ^ 2 <= 0.49 then
            Combat.holdStill(shell)
            return nil
        end
        point.x, point.y, point.z = wx, wy, leg.z
        return point
    end
    if leg.stage == "approach" then
        if (sx - leg.nearX) ^ 2 + (sy - leg.nearY) ^ 2 <= 1.44 then
            leg.stage = "crossing"
        else
            point.x, point.y, point.z = leg.nearX, leg.nearY, leg.z
            return point
        end
    end
    point.x, point.y, point.z = leg.farX, leg.farY, leg.z
    return point
end

function Combat.legGoal(shell)
    local aim = Combat.aimState[shell]
    local leg = aim ~= nil and aim.leg or nil
    if leg == nil or leg.active ~= true or leg.stage ~= "crossing" then return nil end
    return leg.cross
end

function Combat.breachSeat(actor, shell, target, goal)
    local sx, sy = Combat.xyOf(shell)
    if sx == nil or type(goal) ~= "table" then return nil end
    local bx, by = sx - goal.x, sy - goal.y
    local length = math.sqrt(bx * bx + by * by)
    if length < 0.01 then return nil end
    bx, by = bx / length, by / length
    local aim = Combat.aimStateFor(shell)
    local side = Combat.sideOf(actor, aim)
    local tactics = ProjectALife.SquadTactics
    local claims = tactics ~= nil and tactics.ringSlots ~= nil and tactics.ringSlots[target] or nil
    local seat = type(claims) == "table" and type(claims.seats) == "table"
        and claims.seats[actor and actor.uid] or nil
    if tonumber(seat) ~= nil then

        local angle = (seat % 6) * (math.pi / 3) + math.floor(seat / 6) * (math.pi / 6)
        local cross = bx * math.sin(angle) - by * math.cos(angle)
        if cross < 0 then side = -1 elseif cross > 0 then side = 1 end
    end
    local from = Combat.squareAt(goal.x, goal.y, goal.z)
    for attempt = 1, 2 do
        local x, y = goal.x - by * 0.8 * side, goal.y + bx * 0.8 * side
        local square = Combat.squareAt(x, y, goal.z)
        local open = from == nil or square == nil or (square.isFree == nil or square:isFree(false) == true)
        if open and from ~= nil and square ~= nil and from.isBlockedTo ~= nil
                and from:isBlockedTo(square) == true then open = false end
        if open and (from == nil or square ~= nil) then

            local point = aim.breachPoint
            if point == nil then
                point = {}
                aim.breachPoint = point
            end
            point.x, point.y, point.z = x, y, goal.z
            return point
        end
        side = -side
    end
    return nil
end

function Combat.sideOf(actor, aim)
    local uid = actor and actor.uid
    if aim.hashSide == nil or aim.hashSideUid ~= uid then
        aim.hashSideUid, aim.hashSide = uid, Combat.stableHash(uid) % 2 == 0 and 1 or -1
    end
    return aim.hashSide
end

local function breachDestination(actor, shell, target)

    local goal = Combat.position(target)
    return Combat.breachSeat(actor, shell, target, goal) or goal
end

Combat.breachDestination = breachDestination
Combat.cancelPath = cancelPath
Combat.disengage = disengage
Combat.pathToward = pathToward

return Combat
