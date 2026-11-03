require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Movement/ALifeEntrances"
require "ProjectALife/Core/ALifeDayCycle"
require "ProjectALife/Senses/ALifeAwareness"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Entrances = ProjectALife.Entrances
local Stances = {
    id = "stances",
    settings = {

        postTolerance = 1.4,
        visitTolerance = 0.9,

        climbSettleMs = 30000,

        postRotateMs = 22000,

        defendLeash = 14,

        blockadeSpread = 2.2,

        routeArrive = 2.0,
        routeProgressTiles = 0.3,
        routeStallMs = 6500,

        routeLane = 1.5,

        campRing = 3.5,
        campMealRing = 2.0,

        holdoutWarnRange = 8,
        holdoutWarnEveryMs = 12000,
        holdoutPatienceMs = 20000,

        holdoutGraceMs = 3000,

        holdoutTruceMs = 600000,

        holdoutProbeMs = 4000,

        holdoutAimDot = 0.85,

        routeDwellMinMs = 4000,
        routeDwellSpreadMs = 5000,

        repairBeatMs = 9000,

        repairJobMs = 150000,
    },
    metrics = { posts = 0, holds = 0, routes = 0, repairs = 0, searches = 0, camps = 0, walkHolds = 0 },
}
ProjectALife.ModuleStances = Stances

local function nowMsFallback()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function memoryOf(actor)
    return type(actor.memory) == "table" and actor.memory or {}
end

local function stanceOf(actor)
    local memory = memoryOf(actor)
    local stance = memory.stance
    if type(stance) ~= "string" or stance == "" then return nil end
    return stance
end

local function anchorOf(actor)
    local memory = memoryOf(actor)
    local anchor = memory.stanceAnchor
    if type(anchor) ~= "table" then anchor = memory.home end
    if type(anchor) ~= "table" then anchor = memory.spawnOrigin end
    if type(anchor) ~= "table" then return nil end
    local x, y = tonumber(anchor.x), tonumber(anchor.y)
    if x == nil or y == nil then return nil end
    return { x = x, y = y, z = tonumber(anchor.z) or 0 }
end

local function positionOf(shell)
    local point
    pcall(function()
        point = { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
    end)
    return point
end

local function flatDistance(a, b)
    if a == nil or b == nil then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function standable(square)
    if square == nil then return false end
    local ok, free = pcall(function()

        return square:isFree(false) == true
            and square:TreatAsSolidFloor() == true
    end)
    return ok and free == true
end

local function slotOf(actor, span)
    local slot
    pcall(function() slot = tonumber(memoryOf(actor).groupIndex) end)
    if slot == nil then
        local seed, uid = 0, tostring(actor.uid or "")
        for index = 1, #uid do
            seed = (seed * 31 + string.byte(uid, index)) % 4093
        end
        slot = seed
    end
    slot = math.floor(slot)
    if slot < 0 then slot = -slot end
    return slot % math.max(1, span)
end

local function buildingAt(point)
    local building
    pcall(function()
        local square = getCell():getGridSquare(math.floor(point.x),
            math.floor(point.y), math.floor(point.z))
        building = square ~= nil and square:getBuilding() or nil
    end)
    return building
end

local function windowPosts(anchor, preferUpper)
    local posts = {}
    pcall(function()
        local building = buildingAt(anchor)
        if building == nil then return end
        local definition = building:getDef()
        if definition == nil then return end
        local cell = getCell()
        local levels = preferUpper and { 1, 2, 0 } or { 0, 1 }
        for _, level in ipairs(levels) do
            for x = definition:getX(), definition:getX2() do
                for y = definition:getY(), definition:getY2() do
                    if #posts >= 16 then return end
                    local square = cell:getGridSquare(x, y, level)
                    if square ~= nil and square:getBuilding() == building
                            and standable(square) then

                        local looksOut = false
                        for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                            local neighbour = cell:getGridSquare(
                                x + step[1], y + step[2], level)
                            if neighbour ~= nil then
                                pcall(function()
                                    if square:getWindowTo(neighbour) ~= nil
                                            or square:getWindowFrameTo(neighbour) ~= nil then
                                        looksOut = true
                                    end
                                end)
                            end
                        end
                        if looksOut then
                            posts[#posts + 1] = { x = x + 0.5, y = y + 0.5, z = level }
                        end
                    end
                end
            end

            if preferUpper and #posts > 0 then return end
        end
    end)
    return posts
end

local function postFor(actor, shell, anchor, preferUpper, now)
    local memory = memoryOf(actor)
    if type(memory.garrisonPost) == "table" then return memory.garrisonPost end
    local held = memory.stancePost
    local fresh = type(held) == "table"
        and now < (tonumber(memory.stancePostUntilMs) or 0)
    if fresh then return held end
    local posts = windowPosts(anchor, preferUpper)
    local chosen
    if #posts > 0 then
        chosen = posts[(slotOf(actor, #posts)) + 1]
    else

        local slot = slotOf(actor, 8)
        local angle = slot * (math.pi / 4)
        chosen = {
            x = anchor.x + math.cos(angle) * 2.0,
            y = anchor.y + math.sin(angle) * 2.0,
            z = anchor.z,
        }
    end
    Stances.metrics.posts = Stances.metrics.posts + 1
    return chosen, true
end

local handlers = {}

function Stances.walkTarget(key)
    local locator = ProjectALife.PlayerLocator
    local players = locator ~= nil and type(locator.list) == "function" and locator.list() or {}
    local reputation = ProjectALife.Reputation
    for index = 1, #players do
        local player = players[index]
        local name = reputation ~= nil and type(reputation.playerKey) == "function" and reputation.playerKey(player) or nil
        if name == key then return player end
    end
    return nil
end

handlers.walkWith = function(actor, shell, context, anchor)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.drivesBody) ~= "function" or not fence.drivesBody(shell) then return nil end
    local walk = memoryOf(actor).walkWith
    if type(walk) ~= "table" or type(getGameTime) ~= "function" or getGameTime() == nil then return nil end
    if getGameTime():getWorldAgeHours() > (tonumber(walk.untilHours) or -math.huge) then return nil end
    local player = Stances.walkTarget(walk.key)
    local here = positionOf(shell)
    if player == nil or here == nil or type(player.getX) ~= "function" then return true, anchor end
    local there = { x = player:getX(), y = player:getY(), z = player:getZ() }
    local distance = flatDistance(here, there)
    if distance <= 3 then return true, anchor end
    if distance > 60 then return nil end
    return { x = there.x - (there.x - here.x) / distance * 2, y = there.y - (there.y - here.y) / distance * 2, z = there.z }, anchor
end

handlers.visit = function(actor, shell, context, anchor)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.drivesBody) ~= "function" or not fence.drivesBody(shell) then return nil end
    local memory = memoryOf(actor)
    local visit = memory.visit
    if memory.natural ~= true or memory.debugSpawn == true or type(visit) ~= "table"
            or type(getGameTime) ~= "function" then return nil end
    if actor.lifecycle ~= "active" or visit.generation ~= actor.generation then return nil end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return nil end
    local hours = clock:getWorldAgeHours()
    if hours > (tonumber(visit.untilHours) or -math.huge)
            or hours > (tonumber(visit.renewedHours) or -math.huge) + 3 then return nil end
    local animations = ProjectALife.Animations
    if visit.weaponsDown == true and animations ~= nil and type(animations.refreshWeapon) == "function" then
        pcall(animations.refreshWeapon, shell, false)
    end
    local here = positionOf(shell)
    if here == nil then return nil end
    local life = ProjectALife.VisitorLife
    if type(memory.guest) == "table" and life ~= nil and type(life.owns) == "function" and life.owns(actor) == true then
        Stances.faceGuest(actor, shell)
        return true, anchor
    end
    local label = visit.leaving == true and "visit_leaving" or nil
    if flatDistance(here, anchor) <= Stances.settings.visitTolerance then
        if type(memory.guest) == "table" then Stances.faceGuest(actor, shell)
        else Stances.faceAt(shell, memory.stanceFace) end
        return true, anchor, false, nil, label
    end
    return anchor, anchor, false, nil, label
end

function Stances.faceGuest(actor, shell)
    local module = ProjectALife.ModuleVisitorLife
    if module == nil or type(module.nearest) ~= "function" then return false end
    local near = module.nearest(actor, shell)
    if near == nil then return false end
    if type(module.attending) == "function" and not module.attending(actor, "stance", module.nowMs()) then return false end
    return Stances.faceAt(shell, { x = near.x, y = near.y })
end

function Stances.visitHold(actor, shell, context)
    local memory = memoryOf(actor)
    local visit = memory.visit
    if type(visit) ~= "table" or visit.holdUntilMs == nil then return nil end
    if memory.natural ~= true or memory.debugSpawn == true then return nil end
    local untilMs = tonumber(visit.holdUntilMs)
    if untilMs == nil or actor.lifecycle ~= "active" or visit.generation ~= actor.generation then return nil end
    local now = tonumber(context.now) or nowMsFallback()
    if now >= untilMs then return nil end
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.drivesBody) ~= "function" or not fence.drivesBody(shell) then return nil end
    local anchor, here = anchorOf(actor), positionOf(shell)
    if anchor == nil or here == nil then return nil end
    Stances.metrics.visitHolds = (Stances.metrics.visitHolds or 0) + 1
    if flatDistance(here, anchor) > Stances.settings.visitTolerance then
        if Stances.walkRefused(actor, shell, anchor, now) then
            context.setActivity(actor, "idle", "visit_hold")
            return { kind = "idle", intent = "visit_hold", cooldownUntilMs = now + 1200 }
        end
        return context.startMovement(actor, shell, anchor, "stance", {
            pace = "walk", timeoutMs = 15000, doorsOnly = true, tolerance = 0.55,
        })
    end
    Stances.faceAt(shell, memory.stanceFace)
    context.setActivity(actor, "idle", "visit_hold")
    return { kind = "idle", intent = "visit_hold", cooldownUntilMs = math.min(untilMs, now + 600) }
end

Stances.rolePose = {
    sit = "sit_ground", rest = "sit_ground", guitar = "play_guitar",
    work = "board_up", mechanic = "search_low", farm = "farm_tend",
}

function Stances.sitPose(actor, shell, now)
    local life = ProjectALife.ModuleIdleLife
    if life == nil or type(life.sitPose) ~= "function" then return "sit_ground" end
    local pose = life.sitPose(actor, shell, now)
    if type(pose) ~= "string" then return "sit_ground" end
    return pose
end

function Stances.seatPost(actor, shell, post, now)
    local life = ProjectALife.ModuleIdleLife
    if life == nil or type(life.seatPost) ~= "function" then return nil end
    local seat = life.seatPost(actor, shell, post, now)
    if type(seat) ~= "table" then return nil end
    return { x = seat.x, y = seat.y, z = seat.z }
end

Stances.patrolRing = 5
Stances.patrolLegMs = 14000

function Stances.patrolPoint(post, slot, now)
    if type(post) ~= "table" or tonumber(post.x) == nil or tonumber(post.y) == nil then return nil end
    local legs = 4
    local step = math.floor((tonumber(now) or 0) / Stances.patrolLegMs) + (tonumber(slot) or 0)
    local angle = (step % legs) * (math.pi * 2 / legs)
    return {
        x = post.x + math.cos(angle) * Stances.patrolRing,
        y = post.y + math.sin(angle) * Stances.patrolRing,
        z = post.z,
    }
end

Stances.reachRadius = 8
Stances.reachNodes = 300
Stances.reachCacheMs = 60000
Stances.reachCache = {}

function Stances.edgeOpen(a, b)
    local open = false
    pcall(function()
        if a:getDoorTo(b) ~= nil then open = true return end
        if a:getWindowTo(b) ~= nil or a:getWindowFrameTo(b) ~= nil then return end
        if a:isHoppableTo(b) == true or a:isBlockedTo(b) == true then return end
        open = true
    end)
    return open
end

function Stances.reachableWithoutClimb(from, to, now)
    if type(from) ~= "table" or type(to) ~= "table" then return true end
    if type(Stances.adapters) == "table" and type(Stances.adapters.reachable) == "function" then
        return Stances.adapters.reachable(from, to) == true
    end
    local fx, fy, z = math.floor(from.x), math.floor(from.y), math.floor(from.z or 0)
    local tx, ty = math.floor(to.x), math.floor(to.y)
    if fx == tx and fy == ty then return true end
    local radius = Stances.reachRadius
    if math.abs(tx - fx) > radius or math.abs(ty - fy) > radius then return true end
    local key = fx .. "," .. fy .. ">" .. tx .. "," .. ty .. "," .. z
    now = tonumber(now) or 0
    local cached = Stances.reachCache[key]
    if cached ~= nil and now < cached.untilMs then return cached.ok end
    local cell
    pcall(function() cell = getCell() end)
    if cell == nil then return true end
    local function square(x, y)
        local found
        pcall(function() found = cell:getGridSquare(x, y, z) end)
        return found
    end
    local start = square(fx, fy)
    if start == nil or square(tx, ty) == nil then return true end
    local queue, head, seen, visited = { { fx, fy } }, 1, { [fx .. "," .. fy] = true }, 0
    local reached = false
    while head <= #queue and visited < Stances.reachNodes do
        local node = queue[head]
        head = head + 1
        visited = visited + 1
        local here = square(node[1], node[2])
        if here ~= nil then
            for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local nx, ny = node[1] + step[1], node[2] + step[2]
                local id = nx .. "," .. ny
                if not seen[id] and math.abs(nx - fx) <= radius and math.abs(ny - fy) <= radius then
                    local there = square(nx, ny)
                    if there ~= nil and Stances.edgeOpen(here, there) then
                        if nx == tx and ny == ty then reached = true break end
                        seen[id] = true
                        queue[#queue + 1] = { nx, ny }
                    end
                end
            end
        end
        if reached then break end
    end

    local ok = reached
    Stances.reachCacheSize = (Stances.reachCacheSize or 0) + 1
    if Stances.reachCacheSize > 2000 then Stances.reachCache, Stances.reachCacheSize = {}, 0 end
    Stances.reachCache[key] = { ok = ok, untilMs = now + Stances.reachCacheMs }
    return ok
end

function Stances.walkableLeg(here, post, leg, now)
    if Stances.reachableWithoutClimb(here, leg, now) then return leg end
    local dx, dy = leg.x - post.x, leg.y - post.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then return nil end
    for _, ring in ipairs({ 3, 2 }) do
        if ring < length then
            local closer = { x = post.x + dx / length * ring, y = post.y + dy / length * ring, z = leg.z }
            if Stances.reachableWithoutClimb(here, closer, now) then return closer end
        end
    end
    return nil
end

function Stances.walksHome(actor, shell, now)
    local combat, movement = ProjectALife.Combat, ProjectALife.Movement
    if combat == nil or type(combat.leashFor) ~= "function" or type(combat.leashOutside) ~= "function" then
        return false
    end
    local anchor, leash = combat.leashFor(actor)
    if anchor == nil or combat.leashOutside(shell, anchor, leash) == nil then return false end
    return movement == nil or type(movement.climbSettling) ~= "function" or not movement.climbSettling(shell, now)
end

function Stances.walkRefused(actor, shell, target, now)
    local movement = ProjectALife.Movement
    if movement == nil or type(target) ~= "table" then return false end
    if type(movement.goalRefused) == "function" and movement.goalRefused(actor.uid, target, now) then
        return true
    end
    return type(movement.climbSettling) == "function" and movement.climbSettling(shell, now) == true
end

function Stances.faceAt(shell, face)
    if type(face) ~= "table" or tonumber(face.x) == nil or tonumber(face.y) == nil then return false end
    local guest = ProjectALife.ModuleVisitorLife
    if guest ~= nil and type(guest.holdsPose) == "function" and guest.holdsPose(shell) then return false end
    local turned = false
    pcall(function()
        local dx, dy = face.x - shell:getX(), face.y - shell:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.05 then return end
        shell:setTargetAndCurrentDirection(dx / length, dy / length)
        turned = true
    end)
    return turned
end

handlers.garrison = function(actor, shell, context, anchor)
    local here = positionOf(shell)
    if here == nil then return nil end
    local post, rotated = postFor(actor, shell, anchor, false, context.now)
    if post == nil then return nil end

    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.climbRefusedRecently) == "function"
            and traversal.climbRefusedRecently(shell, context.now, Stances.settings.climbSettleMs)
            and not Stances.walksHome(actor, shell, context.now) then
        Stances.metrics.climbHolds = (Stances.metrics.climbHolds or 0) + 1
        return true, post, rotated
    end

    if memoryOf(actor).stanceRole == "patrol" then
        local leg = Stances.patrolPoint(post, slotOf(actor, 4), context.now)
        if leg ~= nil then leg = Stances.walkableLeg(here, post, leg, context.now) end
        if leg ~= nil then
            if flatDistance(here, leg) <= Stances.settings.postTolerance
                    and math.floor(here.z) == math.floor(leg.z) then
                return true, post, rotated
            end
            return leg, post, rotated
        end
    end

    if memoryOf(actor).stanceRole == "farm" and context.threat == nil then
        local row = math.floor(context.now / 22000 + slotOf(actor, 4)) % 3 - 1
        local patch = { x = post.x + row * 1.2, y = post.y, z = post.z }
        if flatDistance(here, patch) > 0.55 and Stances.reachableWithoutClimb(here, patch, context.now) then
            return patch, post, rotated
        end
    end
    local goal = post
    if memoryOf(actor).stanceRole == "sit" and context.threat == nil then
        goal = Stances.seatPost(actor, shell, post, context.now) or post
    end
    if flatDistance(here, goal) <= Stances.settings.postTolerance
            and math.floor(here.z) == math.floor(goal.z) then
        local memory = memoryOf(actor)
        local animations = ProjectALife.Animations

        Stances.faceAt(shell, memory.stanceFace)

        if context.threat ~= nil then

        elseif memory.stanceRole ~= nil then
            local pose = Stances.rolePose[memory.stanceRole]
            if pose == "sit_ground" then pose = Stances.sitPose(actor, shell, context.now) end
            if pose ~= nil and animations ~= nil then animations.apply(shell, pose) end

            if memory.stanceRole == "guitar" and ProjectALife.CampMusic ~= nil then
                pcall(ProjectALife.CampMusic.hold, shell)
            end
        elseif memory.garrisonRest == true then
            if animations ~= nil then animations.apply(shell, Stances.sitPose(actor, shell, context.now)) end
        end
        return true, post, rotated
    end
    return goal, post, rotated
end

handlers.occupy_high = function(actor, shell, context, anchor)
    local here = positionOf(shell)
    if here == nil then return nil end
    local post, rotated = postFor(actor, shell, anchor, true, context.now)
    if post == nil then return nil end
    if flatDistance(here, post) <= Stances.settings.postTolerance
            and math.floor(here.z) == math.floor(post.z) then
        return true, post, rotated
    end
    return post, post, rotated
end

handlers.blockade = function(actor, shell, context, anchor)
    local memory = memoryOf(actor)
    local heading = tonumber(memory.stanceHeading) or 0
    local px, py = -math.sin(heading), math.cos(heading)
    local slot = slotOf(actor, 8)
    local side = (slot % 2 == 0) and 1 or -1
    local rank = math.floor(slot / 2) + 1
    local spread = Stances.settings.blockadeSpread
    local post = {
        x = anchor.x + px * side * rank * spread,
        y = anchor.y + py * side * rank * spread,
        z = anchor.z,
    }
    local here = positionOf(shell)
    if here ~= nil and flatDistance(here, post) <= Stances.settings.postTolerance then
        return true, post
    end
    return post, post
end

handlers.shelter = function(actor, shell, context, anchor)
    local memory = memoryOf(actor)
    local untilHours = tonumber(memory.shelterUntilHours)
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    if (untilHours ~= nil and hours >= untilHours) or (untilHours == nil and Stances.dawnPassed()) then
        local fires = ProjectALife.Campfires
        if fires and fires.requestShelter then fires.requestShelter(shell, "leave", positionOf(shell)) end
        return nil, nil, false, { stance = "", stanceAnchor = nil,
            stanceAwareness = nil, stancePhase = nil, shelterBuildingId = nil }
    end
    local result, post, rotated = handlers.garrison(actor, shell, context, anchor)
    local patch
    local share = Stances.awarenessFor("houseNight", memory)
    if tonumber(memory.stanceAwareness) ~= share then patch = { stanceAwareness = share } end
    return result, post, rotated, patch, "shelter_night"
end

local HOLDOUT_LINES = {
    lowerGun = "Lower that weapon... slowly",
    stepBack = "Back off, give us some room",
    inside = "House is taken, turn around and walk",
    final = "Last chance- we WILL shoot",
    truce = "Alright, hands where we can see 'em",
    turn = "That's it! Get back!",
}

function Stances.holdoutStep(memory, now, nearest, inside, conduct)
    memory = type(memory) == "table" and memory or {}
    conduct = type(conduct) == "table" and conduct or {}
    now = tonumber(now) or 0
    local s = Stances.settings
    local patch = {}
    local first = tonumber(memory.holdoutFirstInsideMs)
    local warns = tonumber(memory.holdoutWarns) or 0
    local said = type(memory.holdoutCue) == "string" and memory.holdoutCue or nil

    if conduct.aiming == true or conduct.damaged == true then
        if said ~= "final" then
            patch.holdoutCue, patch.holdoutLastWarnMs, patch.holdoutWarns = "final", now, warns + 1
            return patch, "warn"
        end
        if now - (tonumber(memory.holdoutLastWarnMs) or now) >= s.holdoutGraceMs then
            patch.holdoutFirstInsideMs = false
            return patch, "flip"
        end
        return patch, nil
    end
    if conduct.friendly == true then
        if first ~= nil then patch.holdoutFirstInsideMs = false end
        if said ~= "truce" then
            patch.holdoutCue, patch.holdoutWarns = "truce", 0
            return patch, "truce"
        end
        return patch, nil
    end
    if inside then
        if first == nil then
            patch.holdoutFirstInsideMs = now
        elseif now - first >= s.holdoutPatienceMs then
            patch.holdoutFirstInsideMs = false
            return patch, "flip"
        end
    elseif conduct.armed ~= true then

        if first ~= nil then patch.holdoutFirstInsideMs = false end
        if (nearest == nil or nearest > s.holdoutWarnRange) and (warns ~= 0 or said ~= nil) then
            patch.holdoutWarns, patch.holdoutCue = 0, false
        end
    end
    if nearest ~= nil and nearest <= s.holdoutWarnRange
            and now - (tonumber(memory.holdoutLastWarnMs) or -1e12) >= s.holdoutWarnEveryMs then
        local cue = "stepBack"
        if inside then cue = "inside" end
        if conduct.armed == true then cue = "lowerGun" end
        if said == "final" then cue = "final" end
        patch.holdoutCue, patch.holdoutLastWarnMs, patch.holdoutWarns = cue, now, warns + 1
        return patch, "warn"
    end
    return patch, nil
end

function Stances.holdoutLine(cue)
    return HOLDOUT_LINES[cue] or HOLDOUT_LINES.stepBack
end

function Stances.holdoutSay(shell, text)
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.sayLine) == "function" then return speech.sayLine(shell, text, "directed") end
    shell:Say(text)
end

function Stances.holdoutVisitor(shell, anchor, bounds)
    local visitor
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        local here = positionOf(shell) or anchor
        for _, player in ipairs(locator.list()) do
            local p = locator.position(player)

            local careful = ProjectALife.ModuleCareful
            if p ~= nil and careful ~= nil and type(careful.visible) == "function"
                    and careful.visible(player) ~= true then
                p = nil
            end
            if p ~= nil then
                local inside
                if type(bounds) == "table" then
                    inside = p.x >= bounds.x1 and p.x <= bounds.x2 and p.y >= bounds.y1 and p.y <= bounds.y2
                else
                    inside = flatDistance(anchor, p) <= 4
                end
                local entry = { player = player, at = p, distance = flatDistance(here, p), inside = inside == true }
                if visitor == nil or (entry.inside and not visitor.inside)
                        or (entry.inside == visitor.inside and entry.distance < visitor.distance) then
                    visitor = entry
                end
            end
        end
    end)
    return visitor
end

function Stances.holdoutIntactCount(building)
    local count
    pcall(function()
        local builder = ProjectALife.OutpostBuilder
        local probe = builder and builder.probeBuilding(building) or nil
        if probe == nil then return end
        count = 0
        for _, opening in ipairs(probe.windows()) do
            local smashed = false
            pcall(function() smashed = opening.object:isSmashed() == true end)
            if not smashed then count = count + 1 end
            if opening.barricaded == true then count = count + 1 end
        end
        for _, opening in ipairs(probe.doors()) do
            count = count + 1
            if opening.barricaded == true then count = count + 1 end
        end
    end)
    return count
end

Stances.holdoutIntact = {}

function Stances.holdoutBroken(siteKey, shell, now)
    if siteKey == nil then return false end
    local last = Stances.holdoutIntact[siteKey]
    if last ~= nil and now - last.atMs < Stances.settings.holdoutProbeMs then return false end
    local square = shell ~= nil and shell.getCurrentSquare ~= nil and shell:getCurrentSquare() or nil
    local building = square ~= nil and square.getBuilding ~= nil and square:getBuilding() or nil
    if building == nil then return false end
    local count = Stances.holdoutIntactCount(building)
    if count == nil then return false end
    Stances.holdoutIntact[siteKey] = { count = count, atMs = now }
    return last ~= nil and count < last.count
end

function Stances.holdoutConduct(memory, shell, visitor, now, actor)
    local conduct = { armed = false, aiming = false, damaged = false, friendly = false }
    local player = visitor.player
    pcall(function()
        local item = player:getPrimaryHandItem()
        conduct.armed = item ~= nil and type(instanceof) == "function" and instanceof(item, "HandWeapon") == true
    end)
    pcall(function()
        if player:isAiming() ~= true then return end
        local here = positionOf(shell)
        local forward = player:getForwardDirection()
        local dx, dy = here.x - visitor.at.x, here.y - visitor.at.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then conduct.aiming = true return end
        local dot = (forward:getX() * dx + forward:getY() * dy) / length
        conduct.aiming = dot >= Stances.settings.holdoutAimDot
    end)

    local watch = ProjectALife.ThreatWatch
    if conduct.aiming == true and actor ~= nil and watch ~= nil and type(watch.fightFiltered) == "function"
            and watch.fightFiltered(actor, player, now) == true then
        conduct.aiming = false
    end
    pcall(function()
        local speech = ProjectALife.Speech
        local key = speech and speech.playerKey(player) or nil
        conduct.key = key
        local tolerated = type(memory.tolerateUntil) == "table" and key ~= nil and tonumber(memory.tolerateUntil[key]) or nil
        conduct.friendly = tolerated ~= nil and now < tolerated
    end)
    conduct.damaged = Stances.holdoutBroken(memory.outpostId or memory.groupId, shell, now)
    return conduct
end

function Stances.holdoutWary(existing, key, now)
    local wary = {}
    for k, v in pairs(type(existing) == "table" and existing or {}) do wary[k] = v end
    if key ~= nil then wary[key] = now + Stances.settings.holdoutTruceMs end
    return wary
end

local function turnHouse(actor, anchor)
    local list = ProjectALife.ActorRegistry
    if list == nil then return 0 end
    local memory = memoryOf(actor)
    local siteId, groupId, turned = memory.outpostId, memory.groupId, 0
    for _, record in ipairs(list.list()) do
        local m = type(record.memory) == "table" and record.memory or {}
        local same = record.uid == actor.uid or (siteId ~= nil and m.outpostId == siteId)
            or (groupId ~= nil and m.groupId == groupId)
        if same and record.lifecycle ~= "dead" then
            list.update(record.uid, record.revision, function(fresh)
                fresh.memory = fresh.memory or {}
                fresh.memory.hostileOverride = true
            end)
            turned = turned + 1
        end
    end
    pcall(function()
        local registry = ProjectALife.OutpostRegistry
        local site = registry and siteId and registry.read(siteId) or nil
        if site ~= nil then registry.update(site.id, site.revision, function(s) s.hostileToPlayers = true end) end
    end)
    return turned
end

handlers.holdout = function(actor, shell, context, anchor)
    local memory = memoryOf(actor)
    if memory.hostileOverride ~= true then
        local bounds
        pcall(function()
            local registry = ProjectALife.OutpostRegistry
            local site = registry and memory.outpostId and registry.read(memory.outpostId) or nil
            bounds = site and site.bounds or nil
        end)
        local now = tonumber(context.now) or 0
        local visitor = Stances.holdoutVisitor(shell, anchor, bounds)
        local conduct
        if visitor ~= nil and (visitor.inside or visitor.distance <= Stances.settings.holdoutWarnRange) then
            conduct = Stances.holdoutConduct(memory, shell, visitor, now, actor)
        end
        local patch, action = Stances.holdoutStep(memory, now, visitor and visitor.distance or nil,
            visitor ~= nil and visitor.inside, conduct)
        if action == "warn" then
            pcall(function() Stances.holdoutSay(shell, Stances.holdoutLine(patch.holdoutCue)) end)
            Stances.metrics.warnings = (Stances.metrics.warnings or 0) + 1
        elseif action == "truce" then
            patch.carefulPlayerKeys = Stances.holdoutWary(memory.carefulPlayerKeys, conduct and conduct.key, now)
            pcall(function() Stances.holdoutSay(shell, Stances.holdoutLine("truce")) end)
            Stances.metrics.truces = (Stances.metrics.truces or 0) + 1
        elseif action == "flip" then
            patch.hostileOverride = true
            turnHouse(actor, anchor)
            pcall(function() Stances.holdoutSay(shell, Stances.holdoutLine("turn")) end)
            Stances.metrics.turned = (Stances.metrics.turned or 0) + 1
        end
        local result, post, rotated = handlers.garrison(actor, shell, context, anchor)
        local any = false
        for _ in pairs(patch) do any = true break end
        return result, post, rotated, any and patch or nil, "holdout"
    end
    local result, post, rotated = handlers.garrison(actor, shell, context, anchor)
    return result, post, rotated, nil, "holdout_armed"
end

handlers.defend = function(actor, shell, context, anchor)
    local here = positionOf(shell)
    if here == nil then return nil end
    local leash = Stances.settings.defendLeash
    if flatDistance(here, anchor) > leash then
        return anchor, anchor
    end
    local post, rotated = postFor(actor, shell, anchor, false, context.now)
    if post == nil then return true end
    if flatDistance(here, post) <= Stances.settings.postTolerance then
        return true, post, rotated
    end
    return post, post, rotated
end

handlers.guard = handlers.defend

local function laneOffset(groupIndex, lane)
    local index = math.max(0, math.floor(tonumber(groupIndex) or 1) - 1)
    return ((index % 4) - 1.5) * (tonumber(lane) or 1.5)
end

local function routeAround(x, y, z, radius)
    local route = {}
    for index = 0, 3 do
        local angle = index * (math.pi / 2) + math.pi / 4
        route[#route + 1] = {
            x = x + math.cos(angle) * radius,
            y = y + math.sin(angle) * radius,
            z = z,
        }
    end
    return route
end

local function routeRadiusOf(route)
    if type(route) ~= "table" or #route == 0 then return 8 end
    local cx, cy = 0, 0
    for _, waypoint in ipairs(route) do
        cx, cy = cx + (tonumber(waypoint.x) or 0), cy + (tonumber(waypoint.y) or 0)
    end
    cx, cy = cx / #route, cy / #route
    local total = 0
    for _, waypoint in ipairs(route) do
        local dx, dy = (tonumber(waypoint.x) or 0) - cx, (tonumber(waypoint.y) or 0) - cy
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    return math.max(8, total / #route)
end

local function dwellFor(actor, minimumMs, spreadMs)
    local seed = 0
    for i = 1, #tostring(actor.uid or "") do
        seed = (seed * 31 + string.byte(tostring(actor.uid), i)) % 100003
    end
    return minimumMs + (seed % math.max(1, spreadMs))
end

handlers.route = function(actor, shell, context, anchor)
    local memory = memoryOf(actor)
    local route = memory.stanceRoute
    if type(route) ~= "table" or #route == 0 then return nil end
    local settings = Stances.settings
    local now = tonumber(context.now) or 0

    local dwellUntil = tonumber(memory.stanceRouteDwellUntilMs) or 0
    if now < dwellUntil then return true, nil, false, nil, "patrol_corner" end
    local index = math.floor(tonumber(memory.stanceRouteIndex) or 1)
    if memory.stanceRouteOneWay == true and index > #route then
        return true, nil, false, nil, "await_squad_directive"
    end
    if index < 1 or index > #route then index = 1 end
    local waypoint = route[index]
    if type(waypoint) ~= "table" then return nil end
    local target = { x = tonumber(waypoint.x) or anchor.x,
        y = tonumber(waypoint.y) or anchor.y,
        z = tonumber(waypoint.z) or anchor.z }

    local previous = route[index > 1 and index - 1 or #route]
    if type(previous) == "table" then
        local lx, ly = target.x - (tonumber(previous.x) or target.x),
            target.y - (tonumber(previous.y) or target.y)
        local length = math.sqrt(lx * lx + ly * ly)
        if length > 0.01 then
            local lane = laneOffset(memory.groupIndex, settings.routeLane)
            target.x = target.x + (-ly / length) * lane
            target.y = target.y + (lx / length) * lane
        end
    end
    local here = positionOf(shell)
    if here == nil then return target, nil, false end
    local distance = flatDistance(here, target)
    if distance <= (settings.routeArrive or 2.0) then

        local nextIndex = index + 1
        if nextIndex > #route and memory.stanceRouteOneWay ~= true then nextIndex = 1 end
        Stances.metrics.routes = Stances.metrics.routes + 1
        return true, nil, false, {
            stanceRouteIndex = nextIndex,
            stanceRouteLastDist = nil,
            stanceRouteProgressMs = nil,
            stanceRouteDwellUntilMs = now + dwellFor(actor,
                settings.routeDwellMinMs or 4000, settings.routeDwellSpreadMs or 5000),
        }, "patrol_corner"
    end

    if memory.stanceRouteOneWay == true and distance > 32 then
        target = { x = here.x + (target.x - here.x) * 32 / distance,
            y = here.y + (target.y - here.y) * 32 / distance, z = target.z }
    end

    local lastDist = tonumber(memory.stanceRouteLastDist)
    local progressMs = tonumber(memory.stanceRouteProgressMs)
    if lastDist == nil or progressMs == nil
            or distance < lastDist - (settings.routeProgressTiles or 0.3) then
        return target, nil, false, {
            stanceRouteLastDist = distance, stanceRouteProgressMs = now }
    end
    if now - progressMs <= (settings.routeStallMs or 6500) then
        return target, nil, false
    end
    if memory.stanceRouteOneWay == true then

        return true, nil, false, { stanceRouteProgressMs = now,
            stanceRouteDwellUntilMs = now + 1500 }, "travel_route_blocked"
    end

    local fails = math.floor(tonumber(memory.stanceRouteFails) or 0) + 1
    Stances.metrics.routeSkips = (Stances.metrics.routeSkips or 0) + 1
    if fails >= #route then
        Stances.metrics.routeRebuilds = (Stances.metrics.routeRebuilds or 0) + 1
        return nil, nil, false, {
            stanceRoute = routeAround(here.x, here.y, here.z or anchor.z, routeRadiusOf(route)),
            stanceRouteIndex = 1, stanceRouteFails = 0,
            stanceRouteLastDist = nil, stanceRouteProgressMs = nil,
        }
    end
    local nextIndex = index + 1
    if nextIndex > #route then nextIndex = 1 end
    return nil, nil, false, {
        stanceRouteIndex = nextIndex, stanceRouteFails = fails,
        stanceRouteLastDist = nil, stanceRouteProgressMs = nil,
    }
end

function Stances.awarenessFor(kind, memory)
    local awareness = ProjectALife.Awareness
    if awareness == nil then return nil end
    return awareness.forRole(kind, memory)
end

function Stances.dawnPassed()
    local cycle = ProjectALife.DayCycle
    return cycle == nil or cycle.dawnPassed() == true
end

Stances.phaseRole = { sleep = "asleep", meal = "resting", guard = "watch" }

Stances.routines = {}

function Stances.seedOf(key)
    local text, seed = tostring(key or ""), 7
    for index = 1, #text do seed = (seed * 33 + string.byte(text, index)) % 2147483647 end
    return seed
end

function Stances.routine(seed)
    local state = math.floor(math.abs(tonumber(seed) or 1)) % 2147483646 + 1
    local function draw(low, high)
        state = (state * 16807) % 2147483647
        return low + (high - low) * ((state % 10000) / 9999)
    end
    local sleepAt = draw(22, 25)
    local wake = sleepAt + draw(5.5, 7.5)
    local breakfast = wake + draw(0.5, 1.0)
    local lunch = draw(11.5, 13.5)
    local supper = sleepAt - draw(1.5, 2.5)
    local function row(from, length, phase)
        return { fromHour = from % 24, toHour = (from + length) % 24, phase = phase }
    end
    return {
        row(sleepAt, wake - sleepAt, "sleep"),
        row(breakfast, draw(40, 70) / 60, "meal"),
        row(lunch, draw(40, 70) / 60, "meal"),
        row(supper, draw(40, 70) / 60, "meal"),
    }
end

function Stances.routineFor(schedule, key)
    if type(schedule) ~= "table" then return nil end
    local seed = tonumber(schedule.seed) or Stances.seedOf(key)
    local routine = Stances.routines[seed]
    if routine == nil then
        routine = Stances.routine(seed)
        Stances.routines[seed] = routine
    end
    return routine
end

local function phaseAt(schedule, hour)
    hour = tonumber(hour) or 12
    if type(schedule) == "table" then
        for _, row in ipairs(schedule) do
            local from, to = tonumber(row.fromHour), tonumber(row.toHour)
            if from ~= nil and to ~= nil then
                local inside
                if from <= to then inside = hour >= from and hour < to
                else inside = hour >= from or hour < to end
                if inside then
                    local phase = tostring(row.phase or "guard")
                    return phase, Stances.awarenessFor(Stances.phaseRole[phase] or "watch")
                end
            end
        end
    end
    return "guard", Stances.awarenessFor("watch")
end
Stances.phaseAt = phaseAt

local function hourOfDay()
    local hour = 12
    pcall(function()
        local time = getGameTime()
        if time.getTimeOfDay ~= nil then hour = time:getTimeOfDay() else hour = time:getHour() end
    end)
    return tonumber(hour) or 12
end

handlers.camp = function(actor, shell, context, anchor)
    local memory = memoryOf(actor)
    local here = positionOf(shell)
    if here == nil then return nil end

    if memory.nightCamp == true and Stances.dawnPassed() then
        local life = ProjectALife.ModuleIdleLife
        if life and type(life.breakCamp) == "function" then life.breakCamp(actor) end
        local animations = ProjectALife.Animations
        if animations and type(animations.clear) == "function" then animations.clear(shell) end
        return nil
    end
    local routine = Stances.routineFor(memory.stanceSchedule, memory.outpostId or memory.groupId or actor.uid)
    local phase = phaseAt(routine, hourOfDay())
    if memory.nightCamp == true then phase = "sleep" end

    local awareness = Stances.awarenessFor(Stances.phaseRole[phase] or "watch", memory)
    local patch
    if tonumber(memory.stanceAwareness) ~= awareness or memory.stancePhase ~= phase then
        patch = { stanceAwareness = awareness, stancePhase = phase }
    end
    local settings = Stances.settings
    local ring = settings.campRing or 3.5
    local slot = slotOf(actor, 8)
    local angle = slot * (math.pi / 4)
    local post = memory.stancePost
    if type(post) ~= "table" or flatDistance(post, anchor) < 2.5
            or flatDistance(post, anchor) > 6 then
        post = nil
        for _, turn in ipairs({ 0, 0.18, -0.18 }) do
            local candidate = { x = anchor.x + math.cos(angle + turn) * ring,
                y = anchor.y + math.sin(angle + turn) * ring, z = anchor.z }
            local valid = type(getCell) ~= "function"
            if not valid then pcall(function()
                local square = getCell():getGridSquare(math.floor(candidate.x), math.floor(candidate.y), candidate.z)
                valid = standable(square)
            end) end
            if valid then post = candidate; break end
        end
        if post == nil then return true, nil, false, patch, "camp_no_safe_seat" end
        patch = patch or {}
        patch.stancePost = post
    end
    if flatDistance(here, post) > 0.65 then
        local fires = ProjectALife.Campfires
        local step = fires and fires.safeStep and fires.safeStep(actor, here, post) or post
        return step, post, false, patch
    end
    if context.threat == nil and (phase == "sleep" or phase == "meal" or slot > 1) then

        pcall(function()
            local animations = ProjectALife.Animations
            if animations ~= nil then animations.apply(shell, Stances.sitPose(actor, shell, context.now)) end
        end)
        Stances.faceAt(shell, anchor)
    end
    Stances.metrics.camps = (Stances.metrics.camps or 0) + 1
    return true, post, false, patch, "camp_" .. phase
end

function Stances.repairDone(memory, now)
    local started = tonumber(type(memory) == "table" and memory.repairStartedMs or nil)
    if started == nil then return false end
    return (tonumber(now) or 0) - started >= Stances.settings.repairJobMs
end

function Stances.repairEvent(memory, now)
    if memory.stanceRole ~= "mechanic" or memory.activityId ~= nil or not Stances.repairDone(memory, now) then return nil end
    local catalog = ProjectALife.ActivityCatalog
    if catalog == nil or not catalog.enabled() then return nil end
    local seq = tonumber(memory.activitySeq) or 0
    local event = memory.activityEvent
    if type(event) == "table" and event.kind == "done" and tonumber(event.seq) == seq then return nil end
    return { activityEvent = { kind = "done", seq = seq } }
end

handlers.repair = function(actor, shell, context, anchor)
    local memory = memoryOf(actor)
    local here = positionOf(shell)
    if here == nil then return nil end
    local mechanic = memory.stanceRole == "mechanic"
        and not Stances.repairDone(memory, context.now)
    if not mechanic then
        local done = Stances.repairEvent(memory, context.now)

        local slot = slotOf(actor, 5)
        local heading = tonumber(memory.stanceHeading)
        local angle
        if heading ~= nil then
            angle = heading + ((slot + 1) / 6 - 0.5) * math.pi
        else
            angle = slot * (math.pi / 3)
        end
        local post = {
            x = anchor.x + math.cos(angle) * 3.2,
            y = anchor.y + math.sin(angle) * 3.2,
            z = anchor.z,
        }
        if flatDistance(here, post) <= Stances.settings.postTolerance then
            return true, post, false, done
        end
        return post, post, false, done
    end
    if flatDistance(here, anchor) > 1.6 then return anchor, anchor end

    local patch = nil
    if tonumber(memory.repairStartedMs) == nil then
        patch = { repairStartedMs = tonumber(context.now) or 0 }
    end
    pcall(function()
        local heading = tonumber(memory.stanceHeading)

        if heading then
            shell:setTargetAndCurrentDirection(-math.cos(heading), -math.sin(heading))
        else
            shell:faceLocationF(anchor.x, anchor.y)
        end
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.apply(shell, "search_low") end
    end)
    Stances.metrics.repairs = Stances.metrics.repairs + 1
    return true, anchor, false, patch, "repair_vehicle"
end

Registry.register({
    id = "stance",
    kind = "orders",
    label = "Encounter stance",
    summary = "Holds the post an encounter was spawned for: garrisons, roadblocks, routes, upper floors, a broken car.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        local stance = stanceOf(actor)
        if stance == nil then return nil end
        if not Registry.allows(actor, "stance") then return nil end
        local handler = handlers[stance]
        if handler == nil then return nil end
        local anchor = anchorOf(actor)
        if anchor == nil then return nil end
        local now = tonumber(context.now) or nowMsFallback()
        context = { now = now, startMovement = context.startMovement,
            setActivity = context.setActivity,
            persistMemory = context.persistMemory,
            threat = context.threat }

        local result, post, rotated, memoryPatch, intent = handler(actor, shell, context, anchor)
        if type(memoryPatch) == "table" and type(context.persistMemory) == "function" then
            for key, value in pairs(memoryPatch) do
                context.persistMemory(actor, key, value)
            end
        end
        if post ~= nil and rotated and type(context.persistMemory) == "function" then
            context.persistMemory(actor, "stancePost", post)
            context.persistMemory(actor, "stancePostUntilMs",
                now + Stances.settings.postRotateMs)
        end
        if result == nil then return nil end
        if result == true then

            local life = ProjectALife.ModuleIdleLife
            if life and life.postBeat and stance ~= "camp" and stance ~= "visit"
                    and (memoryOf(actor).stanceRole ~= "mechanic"
                        or Stances.repairDone(memoryOf(actor), now))
                    and memoryOf(actor).stanceRole ~= "guitar"

                    and memoryOf(actor).stanceRole ~= "work"
                    and memoryOf(actor).stanceRole ~= "farm"
                    and (tonumber(memoryOf(actor).groupIndex) or 2) ~= 1 then
                local rest = life.postBeat(actor, shell, context)
                if rest ~= nil then return rest end
            end

            Stances.metrics.holds = Stances.metrics.holds + 1
            context.setActivity(actor, "idle", intent or ("hold_" .. stance))
            return { kind = "idle", intent = intent or ("hold_" .. stance),
                cooldownUntilMs = now + 1200 }
        end

        if Stances.walkRefused(actor, shell, result, now) then
            Stances.metrics.walkHolds = (Stances.metrics.walkHolds or 0) + 1
            if type(context.setActivity) == "function" then
                context.setActivity(actor, "idle", intent or ("hold_" .. stance))
            end
            return { kind = "idle", intent = intent or ("hold_" .. stance),
                cooldownUntilMs = now + 1200 }
        end

        return context.startMovement(actor, shell, result, "stance", {
            pace = "walk", timeoutMs = 15000, doorsOnly = true,
            tolerance = stance == "camp" and 0.55 or nil,
        })
    end,
})

function Stances.apply(memory, definition, index, anchor, heading)
    if type(memory) ~= "table" or type(definition) ~= "table" then return false end
    if type(definition.stance) ~= "string" then return false end
    memory.stance = definition.stance
    if type(anchor) == "table" then
        memory.stanceAnchor = { x = anchor.x, y = anchor.y, z = anchor.z or 0 }
    end
    if heading ~= nil then memory.stanceHeading = tonumber(heading) or 0 end
    if type(definition.roles) == "table" then
        memory.stanceRole = definition.roles[index]
    end
    if type(definition.route) == "table" then
        memory.stanceRoute = definition.route
        memory.stanceRouteIndex = 1
    end
    return true
end

return Stances
