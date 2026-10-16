require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Behaviours/ALifeModuleFlanking"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Watchdog = ProjectALife.Watchdog
local TargetPolicy = ProjectALife.TargetPolicy
local Flanking = ProjectALife.ModuleFlanking
local defaults = ProjectALife.BehaviorSettings.combat
local Tactics = {
    assists = {}, adapters = {}, contacts = {}, patrolSteps = {},

    arcLatch = {},

    chaseTries = {},

    ringSlots = setmetatable({}, { __mode = "k" }),

    arcShrink = { 1, 0.6, 0.35 },
    settings = { assistRange = 20, assistMemoryMs = 8000 } }
ProjectALife.SquadTactics = Tactics

local function stableHash(value)
    local result = 17
    value = tostring(value or "")
    for index = 1, #value do result = (result * 31 + string.byte(value, index)) % 2147483647 end
    return result
end

local function nowMs()
    if type(Tactics.adapters.nowMs) == "function" then return Tactics.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function indexable(value)
    local kind = type(value)
    return kind == "table" or kind == "userdata"
end

local function position(value)
    if not indexable(value) or value.getX == nil or value.getY == nil or value.getZ == nil then
        return nil
    end
    return { x = value:getX(), y = value:getY(), z = value:getZ() }
end

local function groupId(actor)
    local memory = actor and actor.memory
    if type(memory) ~= "table" then return nil end
    if type(memory.groupId) == "string" then return memory.groupId end

    if memory.outpostId ~= nil then return "outpost:" .. tostring(memory.outpostId) end
    return nil
end

local function targetAlive(target)
    if not indexable(target) or target.isDead == nil then return false end
    return target:isDead() ~= true
end

local function roleIndex(actor)
    local memory = actor and actor.memory or {}
    local configured = math.floor(tonumber(memory.groupIndex) or 0)
    if configured > 0 then return (configured - 1) % 4 end
    return stableHash(actor and actor.uid) % 4
end

function Tactics.configure(adapters)
    Tactics.adapters = adapters or {}
    Tactics.settings = {

    assistRange = 20,
    assistMemoryMs = 8000,

    alarmRange = 40,}
    for name, value in pairs(defaults) do
        Tactics.settings[name] = tonumber(Tactics.adapters[name]) or value
    end

    if Flanking ~= nil and type(Flanking.configure) == "function" then
        pcall(Flanking.configure, {
            enabled = (tonumber(Tactics.settings.flankDistance) or 0) > 0,
            distance = Tactics.settings.flankDistance,
            minimumRange = Tactics.settings.flankMinimumDistance,
        })
    end
end

function Tactics.reset()
    Tactics.arcLatch = {}
    Tactics.chaseTries = {}
    Tactics.ringSlots = setmetatable({}, { __mode = "k" })
    Tactics.ringCount = 0
    Tactics.ringSweepAt = Tactics.ringFloor
    Tactics.assists = {}
    Tactics.contacts = {}
    Tactics.patrolSteps = {}
end

Tactics.ringCount = 0
Tactics.ringFloor = 128
Tactics.ringSweepAt = 128
Tactics.ringIdleMs = 10000

function Tactics.claimsFor(target, now)
    local claims = Tactics.ringSlots[target]
    if type(claims) ~= "table" then
        claims = {}
        Tactics.ringSlots[target] = claims
        Tactics.ringCount = (Tactics.ringCount or 0) + 1
        if Tactics.ringCount > (Tactics.ringSweepAt or Tactics.ringFloor) then Tactics.sweepRings(now) end
    end
    claims.touchedAtMs = now
    return claims
end

function Tactics.sweepRings(now)
    now = tonumber(now) or nowMs()
    local stale, live = {}, 0
    for body, claims in pairs(Tactics.ringSlots) do
        if type(claims) ~= "table" or not targetAlive(body)
                or now - (tonumber(claims.touchedAtMs) or 0) > Tactics.ringIdleMs then
            stale[#stale + 1] = body
        else
            live = live + 1
        end
    end
    for index = 1, #stale do Tactics.ringSlots[stale[index]] = nil end
    Tactics.ringCount = live
    Tactics.ringSweepAt = math.max(Tactics.ringFloor, live * 2)
    return #stale
end

function Tactics.advancePatrol(actor)
    if actor == nil or type(actor.uid) ~= "string" then return 0 end
    local step = (Tactics.patrolSteps[actor.uid] or 0) + 1
    Tactics.patrolSteps[actor.uid] = step
    return step
end

function Tactics.reportThreat(actor, target, kind, suppliedNow)
    if not targetAlive(target) then return false end
    local targetPosition = position(target)
    if targetPosition == nil then return false end
    local now = tonumber(suppliedNow) or nowMs()

    if type(actor) == "table" and type(actor.uid) == "string" then
        Tactics.assists[actor.uid] = {
            target = target,
            kind = kind,
            position = targetPosition,
            factionId = actor.factionId,
            atMs = now,
        }
    end
    local id = groupId(actor)
    if id == nil then return true end
    Tactics.contacts[id] = {
        target = target,
        kind = kind,
        position = targetPosition,
        reportedBy = actor.uid,
        atMs = now,
    }
    return true
end

function Tactics.assistTarget(actor, shell, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local ownFaction = type(actor) == "table" and actor.factionId or nil
    if not indexable(shell) or shell.getX == nil or shell.getY == nil then return nil, nil end
    local x, y = shell:getX(), shell:getY()
    local best, bestKind, bestFlat, bestEntry
    for uid, entry in pairs(Tactics.assists) do
        if now - entry.atMs > (Tactics.settings.assistMemoryMs or 8000) then
            Tactics.assists[uid] = nil
        elseif uid ~= (actor and actor.uid) and targetAlive(entry.target)
                and (ownFaction == nil or entry.factionId == nil
                    or entry.factionId == ownFaction) then
            local dx = entry.position.x - x
            local dy = entry.position.y - y
            local flat = dx * dx + dy * dy
            if flat <= (Tactics.settings.assistRange or 20) ^ 2
                    and (bestFlat == nil or flat < bestFlat) then
                local allowed = TargetPolicy.canAttack(entry.target)
                if allowed then
                    best, bestKind, bestFlat, bestEntry = entry.target, entry.kind, flat, entry
                end
            end
        end
    end
    return best, bestKind, bestEntry
end

function Tactics.acquireThreat(actor, directTarget, directKind, suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    if directTarget ~= nil then
        Tactics.reportThreat(actor, directTarget, directKind, now)
        return directTarget, directKind
    end
    local id = groupId(actor)
    local contact = id and Tactics.contacts[id] or nil
    if contact == nil or now - contact.atMs > Tactics.settings.targetMemoryMs
            or not targetAlive(contact.target) then
        if id ~= nil then Tactics.contacts[id] = nil end
        return nil, nil
    end
    local allowed = TargetPolicy.canAttack(contact.target)
    return allowed and contact.target or nil, allowed and (contact.kind or "shared") or nil,
        allowed and contact or nil
end

function Tactics.role(actor)
    return ({ "assault", "flank_left", "flank_right", "support" })[roleIndex(actor) + 1]
end

Tactics.bands = { holdFloor = 0.85, holdCeiling = 1.55, arcLatchMs = 2600 }

local function lineBlocked(shell)
    local data = indexable(shell) and shell.getModData ~= nil and shell:getModData() or nil
    return type(data) == "table" and data.ProjectALifeLastLineClear == false
end

local function firingArc(actor, target, targetPosition, awayX, awayY,
        radius, now, side, skipCenter)
    local sectors = 12
    local sectorAngle = (math.pi * 2) / sectors
    local nearest, nearestDot = 0, -2
    for index = 0, sectors - 1 do
        local dot = math.cos(index * sectorAngle) * awayX
            + math.sin(index * sectorAngle) * awayY
        if dot > nearestDot then nearestDot, nearest = dot, index end
    end
    local claims = Tactics.claimsFor(target, now)

    local cell = type(getCell) == "function" and getCell() or nil
    if cell ~= nil and cell.getGridSquare == nil then cell = nil end
    local order = side < 0
        and { 0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, 6 }
        or { 0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6 }

    for _, scale in ipairs(Tactics.arcShrink) do
    for rank = 0, 1 do
        for _, step in ipairs(order) do

            local index = nearest + step
            while index < 0 do index = index + sectors end
            while index >= sectors do index = index - sectors end

            local key = 100 + rank * sectors + index
            local held = claims[key]
            if (not skipCenter or step ~= 0)
                    and (type(held) ~= "table" or held.uid == actor.uid
                    or now - (tonumber(held.atMs) or 0) > 3000) then
                local angle = index * sectorAngle
                local out = math.max(0.8, (radius + rank * 1.8) * scale)
                local x = targetPosition.x + math.cos(angle) * out
                local y = targetPosition.y + math.sin(angle) * out

                local square = cell ~= nil and cell:getGridSquare(
                    math.floor(x), math.floor(y),
                    math.floor(targetPosition.z or 0)) or nil
                local blocked = square ~= nil and square.isFree ~= nil
                    and square:isFree(false) ~= true
                if not blocked then
                    claims[key] = { uid = actor.uid, atMs = now }
                    return x, y
                end
            end
        end
    end
    end
    return nil
end

local function holdArcSlot(actor, target, awayX, awayY, now)
    local sectors = 12
    local sectorAngle = (math.pi * 2) / sectors
    local nearest, nearestDot = 0, -2
    for index = 0, sectors - 1 do
        local dot = math.cos(index * sectorAngle) * awayX
            + math.sin(index * sectorAngle) * awayY
        if dot > nearestDot then nearestDot, nearest = dot, index end
    end
    local claims = Tactics.claimsFor(target, now)
    for rank = 0, 1 do
        local key = 100 + rank * sectors + nearest
        local held = claims[key]
        if type(held) ~= "table" or held.uid == actor.uid
                or now - (tonumber(held.atMs) or 0) > 3000 then
            claims[key] = { uid = actor.uid, atMs = now }
            return
        end
    end
end

function Tactics.tierFor(hasGroup, livingNear, indoors)
    if indoors == true then return "cqb" end
    if hasGroup and (tonumber(livingNear) or 0) >= 2 then return "fireteam" end
    return "individual"
end

function Tactics.livingMembers(groupId, exceptUid, x, y, radius)
    local list, count = {}, 0
    if groupId == nil then return count, list end
    local limit = (tonumber(radius) or 25) ^ 2
    local watchdog = ProjectALife.Watchdog
    local registry = ProjectALife.ActorRegistry
    if watchdog == nil or registry == nil or type(watchdog.bindings) ~= "table" then
        return count, list
    end

    local look = registry.peek or registry.read
    for uid, binding in pairs(watchdog.bindings) do
        local shell = binding ~= nil and binding.shell or nil
        if uid ~= exceptUid and shell ~= nil and shell.getX ~= nil and shell.getY ~= nil then
            local mate = look(uid)
            if mate ~= nil and mate.lifecycle == "active"
                    and mate.memory ~= nil and mate.memory.groupId == groupId then
                local dx, dy = shell:getX() - (tonumber(x) or 0), shell:getY() - (tonumber(y) or 0)
                if dx * dx + dy * dy <= limit then
                    count = count + 1
                    list[count] = { uid = uid, actor = mate, shell = shell }
                end
            end
        end
    end
    return count, list
end

function Tactics.behaviorTier(actor, shell, threat)
    local indoors = indexable(shell) and shell.getBuilding ~= nil and shell:getBuilding() ~= nil
    local groupId = type(actor) == "table" and type(actor.memory) == "table" and actor.memory.groupId or nil
    local living = 0
    if groupId ~= nil and not indoors then
        local sx, sy = 0, 0
        if indexable(shell) and shell.getX ~= nil and shell.getY ~= nil then
            sx, sy = shell:getX(), shell:getY()
        end
        living = Tactics.livingMembers(groupId, actor.uid, sx, sy, 25)
    end
    return Tactics.tierFor(groupId ~= nil, living, indoors)
end

function Tactics.tierOf(shell, actor)
    local data = shell ~= nil and shell.getModData ~= nil and shell:getModData() or nil
    local tier = type(data) == "table" and data.ProjectALifeBehaviorTier or nil
    if type(tier) == "string" and tier ~= "" then return tier end
    local grouped = type(actor) == "table" and type(actor.memory) == "table" and actor.memory.groupId ~= nil
    return grouped and "fireteam" or "individual"
end

Tactics.ringOrderRight = { 0, 1, -1, 2, -2, 3 }
Tactics.ringOrderLeft = { 0, -1, 1, -2, 2, 3 }

function Tactics.ringOrder(nearest, sectorAngle, awayX, awayY)
    local angle = nearest * sectorAngle
    local cross = math.cos(angle) * awayY - math.sin(angle) * awayX
    return cross < -0.0001 and Tactics.ringOrderLeft or Tactics.ringOrderRight
end

function Tactics.ringShared(claims, uid, now)
    for key = 0, 23 do
        local held = claims[key]
        if type(held) == "table" and held.uid ~= uid
                and now - (tonumber(held.atMs) or 0) <= 3000 then
            return true
        end
    end
    return false
end

function Tactics.combatDestination(actor, shell, target, desiredRange, canRun, suppliedNow, ranged, reach)
    local origin, targetPosition = position(shell), position(target)
    if origin == nil or targetPosition == nil then return nil, "walk", "direct" end

    local now = tonumber(suppliedNow) or nowMs()
    local dx, dy = origin.x - targetPosition.x, origin.y - targetPosition.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.01 then dx, dy, distance = 1, 0, 1 end
    local awayX, awayY = dx / distance, dy / distance
    local standoff = math.max(0, tonumber(desiredRange) or 1.2)

    local dz = math.abs((origin.z or 0) - (targetPosition.z or 0))
    if dz >= 0.4 then
        return {
            x = targetPosition.x, y = targetPosition.y, z = targetPosition.z,
        }, canRun and "run" or "walk", "cross_floor"
    end

    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.covering) == "function" and fair.covering(actor, target, now) then
        return nil, "walk", "hold"
    end

    if ranged then
        local bands = Tactics.bands
        local floor = standoff * bands.holdFloor

        local ceiling = math.max(standoff * bands.holdCeiling,
            tonumber(reach) or 0)

        local flank = Flanking ~= nil and Flanking.active(actor)
        local lane = flank and Flanking.offset(actor, distance) or 0
        local side = lane < 0 and -1
            or (lane > 0 and 1
                or ((stableHash(actor.uid) % 2 == 0) and 1 or -1))

        if distance < floor then
            local out = standoff * 1.05
            return {
                x = targetPosition.x + awayX * out,
                y = targetPosition.y + awayY * out,
                z = targetPosition.z,
            }, "walk", "fall_back"
        end

        if distance <= ceiling and not lineBlocked(shell) then
            Tactics.chaseTries[actor.uid] = nil
            holdArcSlot(actor, target, awayX, awayY, now)
            return nil, "walk", "hold"
        end

        if distance <= ceiling then
            local latch = Tactics.arcLatch[actor.uid]
            if type(latch) == "table" and now < (tonumber(latch.untilMs) or 0) then
                side = tonumber(latch.side) or side
            else
                Tactics.arcLatch[actor.uid] =
                    { side = side, untilMs = now + bands.arcLatchMs }
            end
            local x, y = firingArc(actor, target, targetPosition, awayX, awayY,
                math.max(standoff, distance), now, side, true)
            if x == nil then return nil, "walk", "hold" end
            return { x = x, y = y, z = targetPosition.z }, "walk", "arc"
        end

        local approach = standoff
        if ceiling > standoff then
            approach = math.max(standoff, ceiling * 0.85)
        end
        local x, y

        x, y = firingArc(actor, target, targetPosition, awayX, awayY,
            approach, now, side)
        if x == nil then
            x = targetPosition.x + awayX * approach
            y = targetPosition.y + awayY * approach
        end
        local gapX, gapY = origin.x - x, origin.y - y
        local gap = math.sqrt(gapX * gapX + gapY * gapY)
        if gap <= 0.6 then return nil, "walk", "hold" end
        return { x = x, y = y, z = targetPosition.z },
            (canRun and gap > 3) and "run" or "walk", "advance"
    end

    local crew = ProjectALife.MeleeCrew
    if crew ~= nil and type(crew.melee) == "function" then
        local ok, point, pace, kind = pcall(crew.melee, actor, shell, target, origin, targetPosition,
            distance, standoff, canRun, now)
        if ok and kind ~= nil then return point, pace, kind end
    end

    local running = indexable(target) and target.isRunning ~= nil and (target:isRunning() == true
        or (target.isSprinting ~= nil and target:isSprinting() == true))
    local chase = Tactics.chaseTries[actor.uid]
    if running and distance <= 24 then
        if type(chase) ~= "table" or now - (tonumber(chase.atMs) or 0) > 1800 then
            chase = { x = targetPosition.x, y = targetPosition.y,
                distance = distance, atMs = now }
        else
            local travelX = targetPosition.x - (tonumber(chase.x) or targetPosition.x)
            local travelY = targetPosition.y - (tonumber(chase.y) or targetPosition.y)
            local awayTravel = travelX * -awayX + travelY * -awayY
            local escaping = awayTravel > 0.05
                or distance > (tonumber(chase.distance) or distance) + 0.05
            if escaping then
                chase.sinceMs = tonumber(chase.sinceMs) or tonumber(chase.atMs) or now
            else
                chase.sinceMs = nil
            end
            chase.x, chase.y, chase.distance, chase.atMs =
                targetPosition.x, targetPosition.y, distance, now
        end
        Tactics.chaseTries[actor.uid] = chase
        if chase.sinceMs ~= nil and now - chase.sinceMs >= 6000 then
            Tactics.arcLatch[actor.uid] = nil
            local chaseReach = math.max(0.95, standoff)
            return {
                x = targetPosition.x + awayX * chaseReach,
                y = targetPosition.y + awayY * chaseReach,
                z = targetPosition.z,
            }, canRun and "run" or "walk", "direct"
        end
    elseif chase ~= nil then
        Tactics.chaseTries[actor.uid] = nil
    end

    local claims = Tactics.claimsFor(target, now)
    local sectors = 6
    local sectorAngle = (math.pi * 2) / sectors
    local nearest, nearestDot = 0, -2
    for index = 0, sectors - 1 do
        local dot = math.cos(index * sectorAngle) * awayX
            + math.sin(index * sectorAngle) * awayY
        if dot > nearestDot then nearestDot, nearest = dot, index end
    end
    local chosen, chosenRank

    local seats = claims.seats
    if type(seats) ~= "table" then
        seats = {}
        claims.seats = seats
    end
    local seatKey = seats[actor.uid]
    local seatHeld = seatKey ~= nil and claims[seatKey] or nil
    if type(seatHeld) ~= "table" or seatHeld.uid ~= actor.uid then seatKey, seatHeld = nil, nil end
    local shared = Tactics.ringShared(claims, actor.uid, now)
    if seatHeld ~= nil and shared then
        local seatIndex = seatKey % sectors

        local seatAngle = seatIndex * sectorAngle + math.floor(seatKey / sectors) * (sectorAngle / 2)
        local seatDot = math.cos(seatAngle) * awayX + math.sin(seatAngle) * awayY
        if seatDot > 0.5 then
            chosen, chosenRank = seatIndex, math.floor(seatKey / sectors)
            seatHeld.atMs = now
        end
    end

    if chosen == nil then
        local order = Tactics.ringOrder(nearest, sectorAngle, awayX, awayY)
        for rank = 0, 3 do
            for _, step in ipairs(order) do
                local index = nearest + step
                while index < 0 do index = index + sectors end
                while index >= sectors do index = index - sectors end
                local key = rank * sectors + index
                local held = claims[key]
                if type(held) ~= "table" or held.uid == actor.uid
                        or now - (tonumber(held.atMs) or 0) > 3000 then
                    chosen, chosenRank = index, rank
                    if seatKey ~= nil and seatKey ~= key then claims[seatKey] = nil end
                    if type(held) == "table" then
                        held.uid, held.atMs = actor.uid, now
                    else
                        claims[key] = { uid = actor.uid, atMs = now }
                    end
                    seats[actor.uid] = key
                    break
                end
            end
            if chosen ~= nil then break end
        end
    end

    if chosen ~= nil and not shared then
        local destination = {
            x = targetPosition.x + awayX * standoff,
            y = targetPosition.y + awayY * standoff,
            z = targetPosition.z,
        }
        local loneDx, loneDy = origin.x - destination.x, origin.y - destination.y
        if loneDx * loneDx + loneDy * loneDy <= 0.36 then
            return nil, "walk", "spacing"
        end
        local runUp = ProjectALife.BehaviorSettings
            and ProjectALife.BehaviorSettings.combat
            and tonumber(ProjectALife.BehaviorSettings.combat.runUpDistance) or 2.5
        return destination, canRun and distance > standoff + math.max(0.5, runUp) and "run" or "walk",
            "spacing"
    end
    if chosen == nil then

        local spread = stableHash(actor.uid) % sectors
        chosen = nearest + spread
        while chosen >= sectors do chosen = chosen - sectors end
        chosenRank = 4 + (stableHash(actor.uid .. ":rank") % 2)
    end

    local angle = chosen * sectorAngle + chosenRank * (sectorAngle / 2)
    awayX, awayY = math.cos(angle), math.sin(angle)

    standoff = standoff + chosenRank * 1.85
    local destination = {
        x = targetPosition.x + awayX * standoff,
        y = targetPosition.y + awayY * standoff,
        z = targetPosition.z,
    }
    local destinationDx, destinationDy = origin.x - destination.x,
        origin.y - destination.y
    if destinationDx * destinationDx + destinationDy * destinationDy <= 0.36 then
        return nil, "walk", "spacing"
    end

    local runUpDistance = ProjectALife.BehaviorSettings
        and ProjectALife.BehaviorSettings.combat
        and tonumber(ProjectALife.BehaviorSettings.combat.runUpDistance)
        or 2.5
    local far = standoff + math.max(0.5, runUpDistance)
    local pace = canRun and distance > far and "run" or "walk"
    return destination, pace, "spacing"
end

function Tactics.patrolDestination(actor, anchor, suppliedNow, configuredRadius)
    if type(anchor) ~= "table" then return nil end
    local now = tonumber(suppliedNow) or nowMs()
    local id = groupId(actor) or actor.uid
    local phase = math.floor(now / 14000) + (Tactics.patrolSteps[actor.uid] or 0)
    local angle = math.rad((stableHash(id) + phase * 137) % 360)
    local maximum = math.max(6, math.min(40, tonumber(configuredRadius) or 22))
    local radius = math.max(3, math.min(maximum,
        maximum * (0.55 + (stableHash(id .. ":radius") % 40) / 100)))
    local spread = ProjectALife.GroupSpread
    if spread ~= nil and type(spread.patrolTarget) == "function" then
        local shaped = spread.patrolTarget(actor, anchor, angle, radius, now)
        if shaped ~= nil then return shaped end
    end
    local role = roleIndex(actor)
    local side = role == 1 and -1 or role == 2 and 1 or 0
    local rear = role == 3 and -2 or 0
    return {
        x = anchor.x + math.cos(angle) * (radius + rear) - math.sin(angle) * side * 1.5,
        y = anchor.y + math.sin(angle) * (radius + rear) + math.cos(angle) * side * 1.5,
        z = anchor.z,
    }
end

function Tactics.groupHasLeader(groupId)
    if type(groupId) ~= "string" then return false end
    local leader = ProjectALife.ModuleLeader
    local groups = leader ~= nil and leader.groups or nil
    return type(groups) == "table" and groups[groupId] ~= nil
end

function Tactics.regroupDestination(actor, shell, maximumDistance)
    local id = groupId(actor)
    if id == nil then return nil end
    if not Tactics.groupHasLeader(id) then return nil end
    local leader, leaderPosition

    Registry.each(function(candidate)
        if candidate.lifecycle == "active" and groupId(candidate) == id
                and (leader == nil or candidate.uid < leader.uid) then
            local binding = Watchdog.bindings[candidate.uid]
            local candidatePosition = binding and position(binding.shell) or nil
            if candidatePosition ~= nil then leader, leaderPosition = candidate, candidatePosition end
        end
    end)
    if leader == nil or leader.uid == actor.uid then return nil end
    local origin = position(shell)
    if origin == nil then return nil end
    local dx, dy = origin.x - leaderPosition.x, origin.y - leaderPosition.y
    local distanceLimit = math.max(6, tonumber(maximumDistance) or 14)
    if dx * dx + dy * dy <= distanceLimit * distanceLimit then return nil end
    local spread = ProjectALife.GroupSpread
    if spread ~= nil and type(spread.followSlot) == "function" then
        local slot = spread.followSlot(actor, shell, leaderPosition)
        if slot ~= nil then return slot end
    end
    local offset = roleIndex(actor) - 1.5
    return {
        x = leaderPosition.x + offset,
        y = leaderPosition.y - math.abs(offset),
        z = leaderPosition.z,
    }
end

function Tactics.forget(actor)
    for _,pair in pairs(Tactics.maneuvers) do
        if actor and (actor.uid==pair.uid or actor.uid==pair.pinUid) then Tactics.clearManeuver(pair.pin,"forget") end
    end
    local id = groupId(actor)
    local contact = id and Tactics.contacts[id] or nil
    if contact ~= nil and contact.reportedBy == actor.uid then contact.reportedBy = nil end
    if actor ~= nil then
        Tactics.patrolSteps[actor.uid] = nil
        Tactics.arcLatch[actor.uid] = nil
        Tactics.assists[actor.uid] = nil
        pcall(function()
            if Flanking ~= nil and type(Flanking.clearWing) == "function" then
                Flanking.clearWing(actor.uid)
            end
        end)
    end
end


Tactics.maneuvers = {}
Tactics.maneuverNext = {}
Tactics.maneuverMetrics = { pairs=0, ended=0 }

function Tactics.clearManeuver(shell,reason)
    for key,pair in pairs(Tactics.maneuvers) do
        if shell==pair.pin or shell==pair.advance then
            Tactics.maneuvers[key]=nil
            Tactics.maneuverMetrics.ended=Tactics.maneuverMetrics.ended+1
            ProjectALife.FireManeuver.clear(pair.advance,reason)
            local data=pair.pin:getModData()
            data.ProjectALifeManeuverPin=nil
            local driven=pair.pin
            if ProjectALife.AIFence.drivesBody(driven)~=true then driven=nil end
            if ProjectALife.ModuleGunner then ProjectALife.ModuleGunner.stop(data,driven) end
        end
    end
end

function Tactics.maneuverValid(pair,now)
    if not ProjectALife.FireManeuver.enabled() or now>=pair.untilMs then return false end
    for _,row in ipairs({{pair.pin,pair.pinUid,pair.pinGeneration},{pair.advance,pair.uid,pair.generation}}) do
        local actor=Registry.read(row[2])
        if actor==nil or actor.generation~=row[3] or groupId(actor)~=pair.group
                or not targetAlive(row[1]) or Watchdog.bindings[row[2]]==nil
                or Watchdog.bindings[row[2]].shell~=row[1] or ProjectALife.AIFence.drivesBody(row[1])~=true
                or not TargetPolicy.canAttack(pair.target,pair.identity,actor)
                or not ProjectALife.Combat.hostileToActor(actor,pair.target,row[1])
                or ProjectALife.Survival.evaluate(actor,row[1],pair.target,now)~="fight" then return false end
    end
    if ProjectALife.Combat.currentAmmo(ProjectALife.Combat.weaponFor(pair.pin))<=0 then return false end
    return true
end

function Tactics.pinSafe(pair,shell,target)
    local combat=ProjectALife.Combat
    if not ProjectALife.ModuleGunner.canReach(shell,target) then return false end
    local body=ProjectALife.LineOfFire.firstBodyOnLine(shell,target)
    local actor=Registry.read(pair.pinUid)
    if body~=nil and body~=target and not combat.hostileToActor(actor,body,shell) then return false end
    local dx,dy=target:getX()-shell:getX(),target:getY()-shell:getY()
    local squared=dx*dx+dy*dy
    if squared<1 then return false end
    local points={{x=pair.advance:getX(),y=pair.advance:getY()},pair.point,pair.point.peek or pair.point}
    for leg=1,2 do
        for index=0,16 do
            local x=points[leg].x+(points[leg+1].x-points[leg].x)*index/16
            local y=points[leg].y+(points[leg+1].y-points[leg].y)*index/16
            local t=((x-shell:getX())*dx+(y-shell:getY())*dy)/squared
            if t>0 and t<1 and (x-shell:getX()-dx*t)^2+(y-shell:getY()-dy*t)^2<4 then return false end
        end
    end
    return true
end

function Tactics.sameManeuverPoint(a,b)
    if a==nil or b==nil then return a==b end
    return a.x==b.x and a.y==b.y and a.z==b.z and Tactics.sameManeuverPoint(a.peek,b.peek)
end

function Tactics.maneuverReady(actor,shell,target,point,now)
    local id=groupId(actor)
    if id==nil then return true end
    local existing=Tactics.maneuvers[id]
    if existing~=nil then
        if not Tactics.maneuverValid(existing,now) or existing.target~=target then
            Tactics.clearManeuver(existing.pin,"invalid")
            return false
        end
        if existing.uid~=actor.uid then return false end
        if not Tactics.sameManeuverPoint(existing.point,point) then
            Tactics.clearManeuver(existing.pin,"plan_changed")
            return false
        end
        if not Tactics.pinSafe(existing,existing.pin,target) then
            Tactics.clearManeuver(existing.pin,"lane")
            return false
        end
        return existing.fired==true,"pending"
    end
    if now<(Tactics.maneuverNext[id] or 0) then return false end
    local members={}
    for uid,binding in pairs(Watchdog.bindings) do
        local peer=Registry.read(uid)
        if peer~=nil and uid~=actor.uid and groupId(peer)==id and binding.shell~=nil
                and math.abs(binding.shell:getZ()-shell:getZ())<0.4
                and (binding.shell:getX()-shell:getX())^2+(binding.shell:getY()-shell:getY())^2<=144 then
            if peer.uid<actor.uid and peer.memory.conduct~="gunner"
                    and targetAlive(binding.shell) and ProjectALife.AIFence.drivesBody(binding.shell)==true
                    and ProjectALife.Combat.currentAmmo(ProjectALife.Combat.weaponFor(binding.shell))>0
                    and ProjectALife.ModuleRegistry.allows(peer,"cover")
                    and ProjectALife.Combat.isRanged(ProjectALife.Combat.weaponFor(binding.shell))
                    and ProjectALife.Survival.evaluate(peer,binding.shell,target,now)=="fight" then return false end
            members[#members+1]={actor=peer,shell=binding.shell}
        end
    end
    if #members==0 then return true end
    table.sort(members,function(a,b) return a.actor.uid<b.actor.uid end)
    for _,member in ipairs(members) do
        local pair={group=id,uid=actor.uid,generation=actor.generation,advance=shell,pin=member.shell,
            pinUid=member.actor.uid,pinGeneration=member.actor.generation,target=target,identity=TargetPolicy.identity(target),
            point=point,untilMs=now+ProjectALife.FireManeuver.number("Combat_PinWindowMs",4000,2000,6000)}
        local aim=ProjectALife.Combat.aimState[member.shell]
        if aim~=nil and aim.maneuverShotTarget==target and now-(aim.maneuverShotAt or 0)<=2000
                and TargetPolicy.sameIdentity(target,aim.maneuverShotIdentity)
                and Tactics.maneuverValid(pair,now) and Tactics.pinSafe(pair,member.shell,target)
                and ProjectALife.ModuleGunner.order(member.actor,member.shell,target,now) then
            Tactics.maneuvers[id]=pair
            Tactics.maneuverMetrics.pairs=Tactics.maneuverMetrics.pairs+1
            Tactics.maneuverNext[id]=now+8000
            member.shell:getModData().ProjectALifeManeuverPin=id
            return false,"pending"
        end
    end
    return false
end

Tactics.configure()

return Tactics
