ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Movement/ALifeDoorPolicy"

local Registry = ProjectALife.ModuleRegistry

local Breach = {
    settings = {
        slotOffset = 0.7,        
        slotSpacing = 1.0,       
        flowCrossDepth = 0.5,    
        promotionGraceMs = 2500, 
        stackTolerance = 0.8,    
        stackTimeoutMs = 8000,   
        holdFireMs = 1200,       
        suspenseMinMs = 400,
        suspenseMaxMs = 1100,
        flowSpacingMs = 350,
        flowDoneMs = 3000,       
        fanReach = 8,
        fallbackForward = 2,
        maxSlots = 8,            
        maxAttempts = 3,         
        proposalTtlMs = 15000,   

        doorCheckMs = 900,
        doorCheckDepth = 3,

        frameStepMs = 2500,

        doorRetryMs = 120000,

        walkTilesPerSecond = 1.1,
        legGraceMs = 2500,
        legMinMs = 3000,
        legsPerRoom = 4,         

        roomCheckBaseMs = 700,
        roomCheckPerSquareMs = 40,
        roomCheckMaxMs = 4500,
        roomClearedMs = 300000,  
        roomClaimMs = 45000,     
        roomScanLimit = 24,
        doorwayReach = 1.3,
        deepReach = 1.1,

        maxEntrances = 3,
        teamMin = 2,
        flankDetour = 6,
        flankGap = 3,
        flankPlanMs = 3000,
        flankGoReach = 1.5,
    },
    metrics = { proposals = 0, stacks = 0, breaches = 0, flows = 0, aborts = 0, fallbacks = 0, doorChecks = 0, sweeps = 0, looks = 0, roomsCleared = 0,
        flankPlans = 0, flankTeams = 0, flankCourtesy = 0 },

    roomClaims = {},
    groupCleared = {},
}
ProjectALife.ModuleBreach = Breach

local function nowMsFallback()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function distance(ax, ay, bx, by)
    local dx, dy = (tonumber(ax) or 0) - (tonumber(bx) or 0), (tonumber(ay) or 0) - (tonumber(by) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function Breach.frame(door)
    local inX, inY = (tonumber(door.ix) or 0) - (tonumber(door.ox) or 0), (tonumber(door.iy) or 0) - (tonumber(door.oy) or 0)
    local len = math.sqrt(inX * inX + inY * inY)
    if len < 0.01 then inX, inY, len = 0, 1, 1 end
    inX, inY = inX / len, inY / len
    return { inX = inX, inY = inY, latX = -inY, latY = inX }
end

function Breach.stackAxis(door)
    local f = Breach.frame(door)
    local inX, inY = f.inX, f.inY
    if math.abs(inX) >= math.abs(inY) then inX, inY = (inX >= 0) and 1 or -1, 0
    else inX, inY = 0, (inY >= 0) and 1 or -1 end
    return { inX = inX, inY = inY, outX = -inX, outY = -inY, latX = -inY, latY = inX }
end

function Breach.crossed(door, x, y, s)
    s = s or Breach.settings
    local a = Breach.stackAxis(door)
    local dx = (tonumber(x) or 0) - (tonumber(door.ox) or 0)
    local dy = (tonumber(y) or 0) - (tonumber(door.oy) or 0)
    return dx * a.inX + dy * a.inY >= (tonumber(s.flowCrossDepth) or 0.5)
end

function Breach.assignOrder(members, door, maxSlots)
    local list = {}
    for _, m in ipairs(type(members) == "table" and members or {}) do list[#list + 1] = m end
    table.sort(list, function(a, b)
        if (a.ranged == true) ~= (b.ranged == true) then return a.ranged == true end
        local da = distance(a.x, a.y, door and door.ox, door and door.oy)
        local db = distance(b.x, b.y, door and door.ox, door and door.oy)
        if da ~= db then return da < db end
        return tostring(a.uid) < tostring(b.uid)
    end)
    local out = {}
    for index = 1, math.min(tonumber(maxSlots) or 4, #list) do out[index] = list[index].uid end
    return out
end

function Breach.reline(order, members, maxSlots)
    local present, changed = {}, false
    for _, m in ipairs(type(members) == "table" and members or {}) do
        if m.uid ~= nil then present[m.uid] = true end
    end
    local out = {}
    for _, uid in ipairs(type(order) == "table" and order or {}) do
        if present[uid] == true then out[#out + 1] = uid else changed = true end
        present[uid] = nil
    end
    local late = {}
    for _, m in ipairs(type(members) == "table" and members or {}) do
        if m.uid ~= nil and present[m.uid] == true then
            late[#late + 1] = m.uid
            present[m.uid] = nil
        end
    end
    table.sort(late, function(a, b) return tostring(a) < tostring(b) end)
    for _, uid in ipairs(late) do
        if #out >= (tonumber(maxSlots) or 4) then break end
        out[#out + 1] = uid
        changed = true
    end
    return out, changed
end

function Breach.slotsFor(door, order, s)
    s = s or Breach.settings
    local a = Breach.stackAxis(door)
    local ox, oy, oz = tonumber(door.ox) or 0, tonumber(door.oy) or 0, tonumber(door.oz) or 0
    local slots = {}
    for index, uid in ipairs(order) do
        local slot = index - 1
        local back = s.slotSpacing * slot
        slots[uid] = { slot = slot,
            x = ox + a.outX * back + a.latX * s.slotOffset,
            y = oy + a.outY * back + a.latY * s.slotOffset,
            z = oz }
    end
    return slots
end

function Breach.fanFor(door, squares, slot, s)
    s = s or Breach.settings
    local f = Breach.frame(door)
    local ix, iy, iz = tonumber(door.ix) or 0, tonumber(door.iy) or 0, tonumber(door.oz) or 0
    local fallback = { x = ix + f.inX * s.fallbackForward, y = iy + f.inY * s.fallbackForward, z = iz }
    if type(squares) ~= "table" or #squares == 0 then return fallback end
    if slot == 0 then
        local best, bestD = nil, -1
        for _, sq in ipairs(squares) do
            local d = distance(sq.x, sq.y, ix, iy)
            if d <= s.fanReach and d > bestD then best, bestD = sq, d end
        end
        return best and { x = best.x, y = best.y, z = iz } or fallback
    elseif slot == 1 then
        local best, bestSide = nil, 0
        for _, sq in ipairs(squares) do
            local d = distance(sq.x, sq.y, ix, iy)
            if d >= 1.0 and d <= 3.5 then
                local side = (sq.x - ix) * f.latX + (sq.y - iy) * f.latY

                if -side > bestSide then best, bestSide = sq, -side end
            end
        end
        return best and { x = best.x, y = best.y, z = iz } or fallback
    end

    local depth = 1.0 + s.slotSpacing * math.min(math.max((tonumber(slot) or 2) - 2, 0), 3)
    return { x = ix + f.inX * depth, y = iy + f.inY * depth, z = iz }
end

function Breach.pointmanArmed(carry, rounds)
    return (carry == "rifle" or carry == "handgun") and (tonumber(rounds) or 0) > 0
end

function Breach.step(machine, facts, now, s)
    s = s or Breach.settings
    machine = type(machine) == "table" and machine or { state = "detect" }
    facts = type(facts) == "table" and facts or {}
    now = tonumber(now) or 0
    local actions = {}
    local state = machine.state or "detect"
    if state == "detect" then
        machine.attempts = (tonumber(machine.attempts) or 0) + 1
        if facts.door == nil or machine.attempts > s.maxAttempts then
            machine.state = "none"
            actions.fallback = true
            return machine, actions
        end
        machine.door = facts.door
        machine.order = Breach.assignOrder(facts.members, facts.door, s.maxSlots)
        if #machine.order == 0 then
            machine.state = "none"
            actions.fallback = true
            return machine, actions
        end
        machine.slots = Breach.slotsFor(facts.door, machine.order, s)
        machine.startedAtMs = now
        machine.state = "stack"
        actions.stamps = machine.slots
        actions.holdFire = true
        actions.claim = facts.door.key
        return machine, actions
    end
    if state == "stack" then

        local head = (machine.order or {})[1]
        local relined, changed = Breach.reline(machine.order, facts.members, s.maxSlots)
        machine.order = relined
        if #relined == 0 then
            machine.state = "none"
            actions.fallback, actions.release, actions.clearStamps = true, true, true
            return machine, actions
        end
        if changed and machine.door ~= nil then
            machine.slots = Breach.slotsFor(machine.door, relined, s)
            actions.stamps = machine.slots
            if relined[1] ~= head then
                machine.startedAtMs = now - s.stackTimeoutMs + s.promotionGraceMs
                machine.promoted = (tonumber(machine.promoted) or 0) + 1
            end
        end
        local ready, present = 0, 0
        for _, m in ipairs(facts.members or {}) do
            local slot = machine.slots and machine.slots[m.uid] or nil
            if slot ~= nil then
                present = present + 1
                if distance(m.x, m.y, slot.x, slot.y) <= s.stackTolerance then
                    slot.readyAtMs = slot.readyAtMs or now
                    ready = ready + 1
                end
            end
        end
        actions.holdFire = true
        local pointmanReady = false
        for uid, slot in pairs(machine.slots or {}) do
            if slot.slot == 0 and slot.readyAtMs ~= nil then pointmanReady = true end
        end
        local timedOut = now - (tonumber(machine.startedAtMs) or now) >= s.stackTimeoutMs
        local assigned = #(machine.order or {})

        if (assigned > 0 and ready == assigned and facts.flanksReady ~= false) or (timedOut and pointmanReady) then
            machine.state = "breach"
            machine.readyAtMs = now
            machine.breachAtMs = now + s.suspenseMinMs + (s.suspenseMaxMs - s.suspenseMinMs) * math.max(0, math.min(1, tonumber(facts.roll) or 0.5))
            actions.ready = true
            actions.face = true
        elseif timedOut then

            machine.state = "none"
            actions.fallback = true
            actions.release = true
        end
        return machine, actions
    end
    if state == "breach" then

        local head = (machine.order or {})[1]
        local relined, changed = Breach.reline(machine.order, facts.members, s.maxSlots)
        machine.order = relined
        if #relined == 0 then
            machine.state = "none"
            actions.fallback, actions.release, actions.clearStamps = true, true, true
            return machine, actions
        end
        if changed and machine.door ~= nil then
            machine.slots = Breach.slotsFor(machine.door, relined, s)
            actions.stamps = machine.slots
            if relined[1] ~= head then

                machine.openAttemptedAtMs, facts.opened = nil, nil
                machine.promoted = (tonumber(machine.promoted) or 0) + 1
            end
        end
        actions.holdFire = true
        actions.face = true
        if now < (tonumber(machine.breachAtMs) or 0) then return machine, actions end
        if facts.opened == nil and facts.locked ~= true then
            actions.open = true
            return machine, actions
        end
        if facts.opened == true then

            machine.state = "flow"
            machine.openedAtMs = now
            machine.checkUntilMs = now + s.doorCheckMs
            machine.goAtMs = {}
            for index, uid in ipairs(machine.order or {}) do machine.goAtMs[uid] = machine.checkUntilMs + (index - 1) * s.flowSpacingMs end
            machine.lastGoAtMs = machine.checkUntilMs + (#(machine.order or {}) - 1) * s.flowSpacingMs

            machine.flowIndex = 1
            actions.check = true
            actions.fan = {}
            local first = (machine.order or {})[1]
            if first ~= nil then actions.fan[first] = machine.goAtMs[first] end
            actions.holdFire = false
            return machine, actions
        end

        if facts.locked == true and machine.thumped ~= true then
            machine.thumped = true
            actions.thump = true
            return machine, actions
        end

        machine.doorRetryAt = machine.doorRetryAt or {}
        if machine.door ~= nil and machine.door.key ~= nil then machine.doorRetryAt[machine.door.key] = now + s.doorRetryMs end
        machine.state = "detect"
        machine.thumped = nil
        machine.door, machine.slots, machine.order = nil, nil, nil
        actions.release = true
        actions.clearStamps = true
        return machine, actions
    end
    if state == "flow" then
        if now >= (tonumber(machine.lastGoAtMs) or now) + s.flowDoneMs then
            machine.state = "done"
            machine.doneAtMs = now
            actions.release = true
            actions.clearStamps = true
            return machine, actions
        end

        local order = machine.order or {}
        local where = {}
        for _, m in ipairs(facts.members or {}) do
            if m.uid ~= nil then where[m.uid] = m end
        end
        local index = math.max(1, math.min(tonumber(machine.flowIndex) or 1, #order))
        while index < #order do
            local ahead = where[order[index]]
            local grace = (tonumber((machine.goAtMs or {})[order[index]]) or now) + s.flowSpacingMs
            local through = ahead == nil or now >= grace
                or (machine.door ~= nil and Breach.crossed(machine.door, ahead.x, ahead.y, s))
            if not through then break end
            index = index + 1
        end
        machine.flowIndex = index
        actions.fan = {}
        for position = 1, index do
            local uid = order[position]
            if uid ~= nil then actions.fan[uid] = (machine.goAtMs or {})[uid] or now end
        end
        return machine, actions
    end
    return machine, actions
end

function Breach.apart(option, used, gap)
    for _, other in ipairs(used) do
        if distance(option.ox, option.oy, other.ox, other.oy) < (tonumber(gap) or 0) then return false end
    end
    return true
end

function Breach.planFlanks(primary, options, members, keep, s)
    s = s or Breach.settings
    local teams = {}
    members = type(members) == "table" and members or {}
    keep = type(keep) == "table" and keep or {}
    local teamMin = math.max(1, tonumber(s.teamMin) or 2)
    local ways = math.min(tonumber(s.maxEntrances) or 1, math.floor(#members / teamMin))
    if primary == nil or ways < 2 or type(options) ~= "table" then return teams end
    local size = math.floor(#members / ways)
    local taken, used = {}, { primary }
    for _ = 2, ways do
        local best, bestScore, bestFits
        for _, option in ipairs(options) do
            if option.key ~= primary.key and Breach.apart(option, used, s.flankGap) then
                local fits = {}
                for _, m in ipairs(members) do
                    local costs = type(m.costs) == "table" and m.costs or {}
                    local here, home = tonumber(costs[option.key]), tonumber(costs[primary.key])
                    if here ~= nil and keep[m.uid] ~= true and taken[m.uid] ~= true
                            and (home == nil or here <= home + s.flankDetour) then
                        fits[#fits + 1] = { m = m, extra = here - (home or here) }
                    end
                end
                if #fits >= teamMin then
                    table.sort(fits, function(a, b)
                        if a.extra ~= b.extra then return a.extra < b.extra end
                        return tostring(a.m.uid) < tostring(b.m.uid)
                    end)
                    local score, count = 0, math.min(size, #fits)
                    for index = 1, count do score = score + fits[index].extra end
                    score = score / count
                    if bestScore == nil or score < bestScore
                            or (score == bestScore and tostring(option.key) < tostring(best.key)) then
                        best, bestScore, bestFits = option, score, fits
                    end
                end
            end
        end
        if best == nil then break end
        local chosen = {}
        for index = 1, math.min(size, #bestFits) do
            chosen[index] = bestFits[index].m
            taken[bestFits[index].m.uid] = true
        end
        used[#used + 1] = best
        teams[#teams + 1] = { entry = best, uids = Breach.assignOrder(chosen, best, #chosen) }
    end
    return teams
end

function Breach.primaryMembers(members, flank)
    if type(flank) ~= "table" then return members end
    local out = {}
    for _, m in ipairs(members or {}) do
        if flank[m.uid] == nil then out[#out + 1] = m end
    end
    return out
end

function Breach.flanksReady(machine, members, s)
    s = s or Breach.settings
    local posts = type(machine) == "table" and machine.flankSlots or nil
    if type(posts) ~= "table" then return nil end
    for _, m in ipairs(members or {}) do
        local post = posts[m.uid]
        if post ~= nil and distance(m.x, m.y, post.x, post.y) > s.stackTolerance then return false end
    end
    return true
end

function Breach.flankGo(machine, s)
    s = s or Breach.settings
    local go = {}
    local base = tonumber(machine.checkUntilMs) or 0
    for _, team in ipairs(machine.entries or {}) do
        for index, uid in ipairs(team.uids or {}) do
            go[uid] = base + (index - 1) * s.flowSpacingMs
            if go[uid] > (tonumber(machine.lastGoAtMs) or 0) then machine.lastGoAtMs = go[uid] end
        end
    end
    machine.flankGoAtMs = go
    return go
end

function Breach.doorSkipped(retryAt, key, now)
    if type(retryAt) ~= "table" or key == nil then return false end
    local untilMs = tonumber(retryAt[key])
    return untilMs ~= nil and (tonumber(now) or 0) < untilMs
end

function Breach.roomFresh(cleared, key, now, s)
    s = s or Breach.settings
    local at = type(cleared) == "table" and tonumber(cleared[tostring(key)]) or nil
    return at ~= nil and (tonumber(now) or 0) - at < s.roomClearedMs
end

function Breach.openRooms(rooms, here, cleared, shared, now, s)
    s = s or Breach.settings
    local list = {}
    local floorZ = math.floor(tonumber(here and here.z) or 0)
    for _, room in ipairs(type(rooms) == "table" and rooms or {}) do
        if math.floor(tonumber(room.z) or 0) == floorZ and room.key ~= (here and here.roomKey)
                and not Breach.roomFresh(cleared, room.key, now, s)
                and not Breach.roomFresh(shared, room.key, now, s) then
            list[#list + 1] = { room = room, d = distance(here and here.x, here and here.y, room.cx, room.cy) }
        end
    end
    table.sort(list, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return tostring(a.room.key) < tostring(b.room.key)
    end)
    local out = {}
    for index, entry in ipairs(list) do out[index] = entry.room end
    return out
end

function Breach.pickRoom(open, claims, uid, now)
    now = tonumber(now) or 0
    for _, room in ipairs(type(open) == "table" and open or {}) do
        local claim = type(claims) == "table" and claims[room.key] or nil
        if claim == nil or claim.uid == uid or now >= (tonumber(claim.untilMs) or 0) then return room end
    end
    return nil
end

function Breach.roomCheckMs(size, s)
    s = s or Breach.settings
    local hold = s.roomCheckBaseMs + s.roomCheckPerSquareMs * math.max(0, tonumber(size) or 0)
    return math.floor(math.max(s.roomCheckBaseMs, math.min(s.roomCheckMaxMs, hold)))
end

function Breach.deepestSquare(squares, doorway)
    local best, bestD
    for _, sq in ipairs(type(squares) == "table" and squares or {}) do
        local d = distance(sq.x, sq.y, doorway and doorway.x, doorway and doorway.y)
        if bestD == nil or d > bestD then best, bestD = sq, d end
    end
    return best
end

function Breach.legTimeoutMs(from, to, s)
    s = s or Breach.settings
    local length = distance(from and from.x, from and from.y, to and to.x, to and to.y)
    local walk = length / math.max(0.2, s.walkTilesPerSecond) * 1000
    return math.floor(math.max(s.legMinMs, walk * 2 + s.legGraceMs))
end

local function registry() return ProjectALife.ActorRegistry end

local function persistBreach(leaderUid, machine)
    pcall(function()
        local list = registry()
        local current = list and list.read(leaderUid) or nil
        if current == nil then return end
        list.updateTransient(current.uid, current.revision, function(record)
            record.memory = record.memory or {}
            record.memory.breach = machine
        end)
    end)
end

local function squareAt(x, y, z)
    local square
    pcall(function() square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end)
    return square
end

local function buildingAt(x, y, z)
    local building
    pcall(function()
        local square = squareAt(x, y, z)
        building = square and square:getBuilding() or nil
    end)
    return building
end

function Breach.findDoor(building, fromX, fromY, fromZ, skipped, now)
    local entrances = ProjectALife.Entrances
    if entrances == nil or building == nil then return nil end
    local openings = entrances.openings(building, fromX, fromY, fromZ)
    local best, bestD
    for _, opening in ipairs(openings or {}) do
        if not Breach.doorSkipped(skipped, opening.key, now) then
            local door
            pcall(function()
                local cell = getCell()
                local outside = cell:getGridSquare(math.floor(opening.x), math.floor(opening.y), math.floor(opening.z))
                if outside == nil then return end
                for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                    local inside = cell:getGridSquare(math.floor(opening.x) + step[1], math.floor(opening.y) + step[2], math.floor(opening.z))
                    if inside ~= nil and inside:getBuilding() == building and outside:getDoorTo(inside) ~= nil then
                        door = { key = opening.key, ox = opening.x, oy = opening.y, oz = opening.z,
                            ix = math.floor(opening.x) + step[1] + 0.5, iy = math.floor(opening.y) + step[2] + 0.5,
                            cost = tonumber(opening.cost) or 0 }
                        return
                    end
                end
            end)
            if door ~= nil then

                local d = distance(fromX, fromY, door.ox, door.oy) + (tonumber(opening.cost) or 0)
                if bestD == nil or d < bestD then best, bestD = door, d end
            end
        end
    end
    return best
end

local function doorObject(door)
    local object
    pcall(function()
        local outside = squareAt(door.ox, door.oy, door.oz)
        local inside = squareAt(door.ix, door.iy, door.oz)
        if outside ~= nil and inside ~= nil then object = outside:getDoorTo(inside) end
    end)
    return object
end

local function doorLocked(door)
    local locked = false
    pcall(function()
        local object = doorObject(door)
        if object == nil then return end

        local policy = ProjectALife.DoorPolicy
        if policy ~= nil and type(policy.lockKind) == "function" then
            locked = policy.lockKind(object) ~= nil or object:isBarricaded() == true
        else
            locked = object:isLocked() == true or object:isBarricaded() == true
        end
    end)
    return locked
end

function Breach.doorOpen(door)
    local object = doorObject(door)
    return object ~= nil and object.IsOpen ~= nil and object:IsOpen() == true
end

local function roomSquares(door)
    local list = {}
    pcall(function()
        local inside = squareAt(door.ix, door.iy, door.oz)
        local room = inside and inside:getRoom() or nil
        if room == nil then return end
        local squares = room:getSquares()
        for index = 0, squares:size() - 1 do
            local sq = squares:get(index)
            if sq ~= nil and sq:isFree(false) then list[#list + 1] = { x = sq:getX() + 0.5, y = sq:getY() + 0.5 } end
        end
    end)
    return list
end

function Breach.keptOut(actor, x, y, baseOnly)
    local policy = ProjectALife.DoorPolicy
    if type(actor) ~= "table" or policy == nil or type(policy.keepsOut) ~= "function"
            or tonumber(x) == nil or tonumber(y) == nil then
        return false
    end
    if policy.keepsOut(actor, tonumber(x), tonumber(y), baseOnly == true) == true then return true end
    return type(policy.homeRefusal) == "function" and policy.homeRefusal(actor, tonumber(x), tonumber(y)) ~= nil
end

function Breach.walkCost(site, x, y, ox, oy)
    local entrances = ProjectALife.Entrances
    local cx = math.max(site.x1, math.min(site.x2, x))
    local cy = math.max(site.y1, math.min(site.y2, y))
    local from, length = entrances.ringPos(site, x, y)
    local around = math.abs(entrances.ringPos(site, ox, oy) - from)
    return distance(x, y, cx, cy) + math.min(around, length - around)
end

function Breach.flankOptions(site, now)
    local entrances, traversal = ProjectALife.Entrances, ProjectALife.ObstacleTraversal
    local bans = traversal ~= nil and type(traversal.edgeBans) == "table" and traversal.edgeBans or {}
    local list = {}
    for edgeKey, entry in pairs(site.entries or {}) do
        local readAt = tonumber(entry.readAtMs) or 0
        if now < readAt or now - readAt >= entrances.mapSettings.entryMs then entrances.rereadEntry(entry, now) end
        local cost = entrances.entryCost(entry, entry.state, true)
        if cost ~= nil and (tonumber(bans[edgeKey]) or 0) <= now then
            list[#list + 1] = { key = entry.sx .. "," .. entry.sy .. "," .. entry.z, edgeKey = edgeKey,
                ox = entry.sx + 0.5, oy = entry.sy + 0.5, oz = entry.z,
                ix = entry.ix + 0.5, iy = entry.iy + 0.5, kind = entry.kind, cost = cost }
        end
    end
    table.sort(list, function(a, b) return tostring(a.edgeKey) < tostring(b.edgeKey) end)
    return list
end

function Breach.memberCosts(site, m, options, primary, building, now)
    local traversal = ProjectALife.ObstacleTraversal
    local costs = {}
    if m.shell == nil or buildingAt(m.x, m.y, primary.oz) == building then return costs end
    costs[primary.key] = Breach.walkCost(site, m.x, m.y, primary.ox, primary.oy) + (tonumber(primary.cost) or 0)
    if traversal == nil or type(traversal.keptOutOf) ~= "function" or type(traversal.shellBanned) ~= "function" then
        return costs
    end
    if traversal.keptOutOf(m.shell, building, now) then return costs end
    local climbs = not traversal.climbOverBudget(m.shell, now)
    for _, option in ipairs(options) do
        if (option.kind == "door" or climbs) and not traversal.openingFailed(m.shell, option.edgeKey, now)
                and not traversal.shellBanned(m.shell, option.edgeKey, now) then
            costs[option.key] = Breach.walkCost(site, m.x, m.y, option.ox, option.oy) + option.cost
        end
    end
    return costs
end

function Breach.planEntries(actor, machine, primary, members, building, now)
    local s = Breach.settings
    local entrances = ProjectALife.Entrances
    if primary == nil or building == nil or entrances == nil or type(entrances.mapSite) ~= "function" then return false end
    local site = entrances.mapSite(building, tonumber(primary.oz) or 0, now, nil, primary.ox, primary.oy)
    if site == nil or site.done ~= true then return false end
    machine.flankPlanned = true
    Breach.metrics.flankPlans = Breach.metrics.flankPlans + 1
    local options = {}
    for _, option in ipairs(Breach.flankOptions(site, now)) do
        if Breach.keptOut(actor, option.ix, option.iy) then
            Breach.metrics.flankCourtesy = Breach.metrics.flankCourtesy + 1
        else
            options[#options + 1] = option
        end
    end
    local keep = { [actor.uid] = true }
    local order = machine.order or Breach.assignOrder(members, primary, s.maxSlots)
    if order[1] ~= nil then keep[order[1]] = true end
    local planned = {}
    for _, m in ipairs(members) do
        planned[#planned + 1] = { uid = m.uid, x = m.x, y = m.y, ranged = m.ranged,
            costs = Breach.memberCosts(site, m, options, primary, building, now) }
    end
    local teams = Breach.planFlanks(primary, options, planned, keep, s)
    if #teams == 0 then return true end
    machine.entries, machine.flank, machine.flankSlots = {}, {}, {}
    for index, team in ipairs(teams) do
        local entry = team.entry
        machine.entries[index] = { key = entry.key, edgeKey = entry.edgeKey, kind = entry.kind,
            ox = entry.ox, oy = entry.oy, oz = entry.oz, ix = entry.ix, iy = entry.iy, uids = team.uids }
        for uid, slot in pairs(Breach.slotsFor(entry, team.uids, s)) do
            slot.entry = index
            machine.flank[uid] = index
            machine.flankSlots[uid] = slot
        end
        entrances.claims[entry.key] = { uid = team.uids[1], atMs = now }
        Breach.metrics.flankTeams = Breach.metrics.flankTeams + 1
    end
    return true
end

function Breach.stampFlanks(members, machine, actions, now)
    local s = Breach.settings
    local posts = machine.flankSlots
    if type(posts) ~= "table" or actions.clearStamps == true then return end
    local state = machine.state
    if state == "flow" and machine.flankGoAtMs == nil then Breach.flankGo(machine, s) end
    local rooms = {}
    for _, m in ipairs(members) do
        local post = posts[m.uid]
        local team = post ~= nil and (machine.entries or {})[post.entry] or nil
        if team ~= nil then
            local fan
            if state == "flow" then
                rooms[post.entry] = rooms[post.entry] or roomSquares(team)
                fan = Breach.fanFor(team, rooms[post.entry], post.slot)
            end
            pcall(function()
                local data = m.shell:getModData()
                data.ProjectALifeStackX, data.ProjectALifeStackY, data.ProjectALifeStackZ = post.x, post.y, post.z
                data.ProjectALifeStackSlot, data.ProjectALifeStackEntry = post.slot, post.entry
                if state == "stack" or state == "breach" then
                    data.ProjectALifeStackUntilMs = now + s.stackTimeoutMs
                    data.ProjectALifeHoldFireUntilMs = now + s.holdFireMs
                elseif fan ~= nil then
                    local goAt = tonumber(machine.flankGoAtMs[m.uid]) or now
                    data.ProjectALifeFanX, data.ProjectALifeFanY, data.ProjectALifeFanZ = fan.x, fan.y, fan.z
                    data.ProjectALifeStackGoAtMs = goAt
                    data.ProjectALifeStackUntilMs = goAt + s.flowDoneMs
                    data.ProjectALifeHoldFireUntilMs = nil
                end
            end)
        end
    end
end

function Breach.doorwayCheck(shell, door, now)
    local s = Breach.settings
    local armed = false
    pcall(function()
        local data = shell:getModData()
        local weapon = shell:getPrimaryHandItem()
        local rounds = weapon ~= nil and (tonumber(weapon:getCurrentAmmoCount()) or 0) or 0
        armed = Breach.pointmanArmed(tostring(data.ProjectALifeWeaponClass), rounds)
        if not armed then return end
        local f = Breach.frame(door)
        local ax, ay = door.ix + f.inX * s.doorCheckDepth, door.iy + f.inY * s.doorCheckDepth
        data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = ax, ay
        data.ProjectALifeHoldFireUntilMs = nil
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then guard.faceAimPoint(shell, ax, ay, now) end
    end)
    return armed
end

local function pointmanEngaged(uid)
    local perception = ProjectALife.Perception
    return perception ~= nil and type(perception.engagements) == "table"
        and perception.engagements[uid] ~= nil
end

Breach.lines = {
    STACK_UP = { trained = "Stack up on the door!", plain = "Everybody on the wall by the door, quiet",
        rough = "Get on the wall by the door and shut up" },
    ENTRY_HOT = { trained = "Look out! Help our friend!", plain = "Help them! Keep your eyes open!",
        rough = "Back them up, don't just stand there!" },
}

function Breach.callout(actor, key)
    local roles = ProjectALife.DialogueRoles
    local style = "plain"
    if roles ~= nil and type(roles.callStyle) == "function" then style = roles.callStyle(actor, nil) end
    local set = Breach.lines[key]
    return set[style] or set.plain
end

local function say(shell, event, text)
    pcall(function()
        local voice = ProjectALife.Voice
        if voice ~= nil then voice.play(shell, event, { urgent = true }) end
    end)
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.sayLine) == "function" then
        speech.sayLine(shell, text, "directed")
        return
    end
    pcall(function() shell:Say(text) end)
end

local function livingLeader(groupId)
    local found
    pcall(function()
        local list = registry()
        if list == nil then return end
        for _, record in ipairs(list.list()) do
            local memory = type(record.memory) == "table" and record.memory or {}
            if memory.groupId == groupId and memory.conduct == "leader" and record.lifecycle == "active" then found = record return end
        end
    end)
    return found
end

Breach.holdingStances = {
    garrison = true, holdout = true, occupy_high = true, shelter = true,
    camp = true, defend = true, blockade = true,
}

function Breach.propose(actor, shell, target, now)
    if type(actor) ~= "table" or not Registry.allows(actor, "doorstack") then return false, "module_off" end
    local holding = type(actor.memory) == "table" and actor.memory.stance or nil
    if holding ~= nil and Breach.holdingStances[holding] == true then
        return false, "garrison_holds"
    end
    local tactics = ProjectALife.SquadTactics
    if tactics == nil or tactics.tierOf(shell, actor) ~= "fireteam" then return false, "not_a_fireteam" end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.groupId == nil then return false, "no_group" end
    local tx, ty, tz = 0, 0, 0
    pcall(function() tx, ty, tz = target:getX(), target:getY(), target:getZ() end)
    local targetBuilding = buildingAt(tx, ty, tz)
    if targetBuilding == nil then return false, "target_outside" end
    local ownBuilding
    pcall(function() ownBuilding = shell:getBuilding() end)
    if ownBuilding == targetBuilding then return false, "same_building" end

    if Breach.keptOut(actor, tx, ty, true) then return false, "courtesy" end

    if type(actor.memory) == "table" and actor.memory.outpostId ~= nil then
        local ownSite
        pcall(function()
            local registry = ProjectALife.OutpostRegistry
            local site = registry and registry.read(tostring(actor.memory.outpostId)) or nil
            if site ~= nil and type(site.bounds) == "table" then
                ownSite = tx >= site.bounds.x1 - 1 and tx <= site.bounds.x2 + 1
                    and ty >= site.bounds.y1 - 1 and ty <= site.bounds.y2 + 1
            end
        end)
        if ownSite == true then return false, "own_outpost" end
    end
    local leader = livingLeader(memory.groupId)
    if leader == nil then return false, "no_leader" end
    now = tonumber(now) or nowMsFallback()
    local live = type(leader.memory.breach) == "table" and leader.memory.breach or nil
    if live ~= nil and live.state ~= "none" and live.state ~= "done" and now - (tonumber(live.proposedAtMs) or 0) < Breach.settings.proposalTtlMs * 4 then
        return false, "already_running"
    end
    if live ~= nil and (live.state == "done" or live.state == "none") and now - (tonumber(live.doneAtMs) or tonumber(live.proposedAtMs) or 0) < Breach.settings.proposalTtlMs then
        return false, "cooling"
    end
    persistBreach(leader.uid, { state = "detect", proposedAtMs = now, targetX = tx, targetY = ty, targetZ = tz, attempts = 0 })
    Breach.metrics.proposals = Breach.metrics.proposals + 1
    return true, "proposed"
end

local function memberFacts(members)
    local out = {}
    for _, m in ipairs(members or {}) do
        local x, y, ranged = 0, 0, false
        pcall(function() x, y = m.shell:getX(), m.shell:getY() end)
        pcall(function()
            local kind = tostring(m.shell:getModData().ProjectALifeWeaponClass or "")
            ranged = kind == "rifle" or kind == "handgun"
        end)
        out[#out + 1] = { uid = m.uid, ranged = ranged, x = x, y = y, shell = m.shell }
    end
    return out
end

local function stampMembers(members, machine, actions, now)
    local s = Breach.settings

    local room = (actions.fan ~= nil and machine.door ~= nil) and roomSquares(machine.door) or nil
    for _, m in ipairs(members) do
        pcall(function()
            local data = m.shell:getModData()
            local slot = machine.slots and machine.slots[m.uid] or nil
            if actions.clearStamps then
                data.ProjectALifeStackX, data.ProjectALifeStackY, data.ProjectALifeStackZ = nil, nil, nil
                data.ProjectALifeStackSlot, data.ProjectALifeStackUntilMs, data.ProjectALifeStackGoAtMs = nil, nil, nil
                data.ProjectALifeFanX, data.ProjectALifeFanY, data.ProjectALifeFanZ = nil, nil, nil
                data.ProjectALifeStackEntry = nil
                return
            end
            if slot ~= nil and actions.stamps ~= nil then
                data.ProjectALifeStackX, data.ProjectALifeStackY, data.ProjectALifeStackZ = slot.x, slot.y, slot.z
                data.ProjectALifeStackSlot = slot.slot
            end
            if slot ~= nil and (machine.state == "stack" or machine.state == "breach") then
                data.ProjectALifeStackUntilMs = now + s.stackTimeoutMs
            end
            if actions.holdFire == true and slot ~= nil then
                data.ProjectALifeHoldFireUntilMs = now + s.holdFireMs
            end
            if actions.fan ~= nil and slot ~= nil then
                local fan = Breach.fanFor(machine.door, room, slot.slot)
                data.ProjectALifeFanX, data.ProjectALifeFanY, data.ProjectALifeFanZ = fan.x, fan.y, fan.z
                data.ProjectALifeStackGoAtMs = actions.fan[m.uid]
                data.ProjectALifeStackUntilMs = (actions.fan[m.uid] or now) + s.flowDoneMs
                data.ProjectALifeHoldFireUntilMs = nil
            end
        end)
    end
end

function Breach.leaderBeat(actor, shell, groupId, members, now)
    if type(actor) ~= "table" or type(actor.memory) ~= "table" then return false end
    local machine = actor.memory.breach
    if type(machine) ~= "table" or machine.state == "none" or machine.state == "done" then return false end
    now = tonumber(now) or nowMsFallback()
    local s = Breach.settings
    local facts = { members = memberFacts(members), roll = (type(ZombRand) == "function" and ZombRand(1000) / 1000 or 0.5) }

    local lx, ly, lz = 0, 0, 0
    pcall(function() lx, ly, lz = shell:getX(), shell:getY(), shell:getZ() end)
    local leaderRanged = false
    pcall(function()
        local kind = tostring(shell:getModData().ProjectALifeWeaponClass or "")
        leaderRanged = kind == "rifle" or kind == "handgun"
    end)
    facts.members[#facts.members + 1] = { uid = actor.uid, ranged = leaderRanged, x = lx, y = ly, shell = shell }
    local all = facts.members
    if machine.state == "detect" then
        local building = buildingAt(machine.targetX or lx, machine.targetY or ly, machine.targetZ or lz)
        facts.door = Breach.findDoor(building, lx, ly, lz, machine.doorRetryAt, now)
        machine.entries, machine.flank, machine.flankSlots, machine.flankGoAtMs, machine.flankPlanned = nil, nil, nil, nil, nil
        if facts.door ~= nil and Breach.keptOut(actor, machine.targetX, machine.targetY, true) then
            facts.door = nil
            Breach.metrics.flankCourtesy = Breach.metrics.flankCourtesy + 1
        end
        if facts.door ~= nil then Breach.planEntries(actor, machine, facts.door, all, building, now) end
    elseif machine.state == "stack" and machine.flankPlanned ~= true
            and now - (tonumber(machine.startedAtMs) or now) < s.flankPlanMs then
        local building = buildingAt(machine.targetX or lx, machine.targetY or ly, machine.targetZ or lz)
        Breach.planEntries(actor, machine, machine.door, all, building, now)
    elseif machine.state == "breach" then
        if machine.door ~= nil then
            facts.locked = doorLocked(machine.door)
            if machine.openAttemptedAtMs ~= nil then facts.opened = Breach.doorOpen(machine.door) end
        end
    end

    facts.members = Breach.primaryMembers(all, machine.flank)
    facts.flanksReady = Breach.flanksReady(machine, all, s)
    local previous = machine.state
    local actions
    machine, actions = Breach.step(machine, facts, now, s)
    local pointman
    for _, m in ipairs(facts.members) do
        local slot = machine.slots and machine.slots[m.uid] or nil
        if slot ~= nil and slot.slot == 0 then pointman = m end
    end
    if actions.claim ~= nil then
        pcall(function()
            local entrances = ProjectALife.Entrances
            if entrances ~= nil then entrances.claims[actions.claim] = { uid = actor.uid, atMs = now } end
        end)
    end
    if previous ~= "stack" and machine.state == "stack" then
        Breach.metrics.stacks = Breach.metrics.stacks + 1
        say(shell, "STACK_UP", Breach.callout(actor, "STACK_UP"))
    end
    if actions.face == true and pointman ~= nil and machine.door ~= nil then
        pcall(function()
            local data = pointman.shell:getModData()
            data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = machine.door.ix, machine.door.iy
        end)
    end
    if actions.ready == true then say(shell, "BREACH", "Everybody set? Opening it") end

    if (actions.open == true or actions.thump == true) and pointman ~= nil and machine.door ~= nil
            and not Breach.onFrame(pointman, machine.door)
            and now - (tonumber(machine.breachAtMs) or now) < s.frameStepMs then
        Breach.stepToFrame(pointman, machine.door)
        if actions.thump == true then machine.thumped = nil end
        actions.open, actions.thump = nil, nil
    end
    if actions.open == true and pointman ~= nil and machine.door ~= nil then
        machine.openAttemptedAtMs = now
        pcall(function()
            local traversal = ProjectALife.ObstacleTraversal
            if traversal ~= nil then traversal.openDoorAhead(pointman.shell, { x = machine.door.ix, y = machine.door.iy, z = machine.door.oz }) end
        end)

        if Breach.doorOpen(machine.door) then
            machine, actions = Breach.step(machine, { members = facts.members, opened = true, roll = facts.roll }, now, s)
        end
    end
    if actions.thump == true and pointman ~= nil and machine.door ~= nil then
        pcall(function()
            local traversal = ProjectALife.ObstacleTraversal
            if traversal ~= nil then traversal.try(pointman.shell, { x = machine.door.ix, y = machine.door.iy, z = machine.door.oz }) end
        end)
    end
    if actions.check == true and machine.door ~= nil then
        Breach.metrics.breaches = Breach.metrics.breaches + 1
        Breach.metrics.doorChecks = Breach.metrics.doorChecks + 1
    end

    if machine.state == "flow" and pointman ~= nil and machine.door ~= nil
            and now < (tonumber(machine.checkUntilMs) or 0) then
        Breach.doorwayCheck(pointman.shell, machine.door, now)
    end

    if machine.state == "flow" and machine.entryCalled ~= true and machine.checkUntilMs ~= nil
            and now >= (tonumber(machine.checkUntilMs) or now) then
        machine.entryCalled = true
        if pointman ~= nil and pointmanEngaged(pointman.uid) then
            say(shell, "BREACH", Breach.callout(actor, "ENTRY_HOT"))
        else
            say(shell, "BREACH", "Looks empty, in we go")
        end
    end
    if actions.fan ~= nil and previous == "breach" then Breach.metrics.flows = Breach.metrics.flows + 1 end
    if actions.fallback == true then Breach.metrics.fallbacks = Breach.metrics.fallbacks + 1 end
    if actions.release == true then
        pcall(function()
            local entrances = ProjectALife.Entrances
            if entrances == nil then return end
            if machine.door ~= nil and machine.door.key ~= nil then entrances.claims[machine.door.key] = nil end
            for _, team in ipairs(machine.entries or {}) do
                local claim = entrances.claims[team.key]
                if claim ~= nil and claim.uid == (team.uids or {})[1] then entrances.claims[team.key] = nil end
            end
        end)
    end
    stampMembers(all, machine, actions, now)
    Breach.stampFlanks(all, machine, actions, now)
    persistBreach(actor.uid, machine)
    return true, machine.state
end

function Breach.onFrame(member, door)
    return math.floor(tonumber(member.x) or 0) == math.floor(tonumber(door.ox) or 0)
        and math.floor(tonumber(member.y) or 0) == math.floor(tonumber(door.oy) or 0)
end

function Breach.stepToFrame(member, door)
    pcall(function()
        local data = member.shell:getModData()
        data.ProjectALifeStackX, data.ProjectALifeStackY, data.ProjectALifeStackZ = door.ox, door.oy, door.oz
    end)
end

function Breach.approachOverride(actor, shell, now)
    local data
    pcall(function() data = shell:getModData() end)
    if type(data) ~= "table" then return nil end
    now = tonumber(now) or nowMsFallback()
    local untilMs = tonumber(data.ProjectALifeStackUntilMs)
    if untilMs == nil or now >= untilMs then return nil end
    local goAt = tonumber(data.ProjectALifeStackGoAtMs)
    if goAt ~= nil and now >= goAt and data.ProjectALifeFanX ~= nil then

        local post = Breach.flankPost(shell, data)
        local reach = Breach.settings.flankGoReach
            + Breach.settings.slotSpacing * (tonumber(data.ProjectALifeStackSlot) or 0)
        if post ~= nil and post.away > reach and not post.inside then
            return { destination = post.point, pace = "run", tactic = "flank" }
        end
        return { destination = { x = data.ProjectALifeFanX, y = data.ProjectALifeFanY, z = data.ProjectALifeFanZ or 0 }, pace = "run", tactic = "flow" }
    end
    if data.ProjectALifeStackX ~= nil then
        return { destination = { x = data.ProjectALifeStackX, y = data.ProjectALifeStackY, z = data.ProjectALifeStackZ or 0 }, pace = "walk", tactic = "stack" }
    end
    return nil
end

function Breach.flankPost(shell, data)
    if data.ProjectALifeStackEntry == nil or tonumber(data.ProjectALifeStackX) == nil then return nil end
    local x, y, z
    pcall(function() x, y, z = shell:getX(), shell:getY(), shell:getZ() end)
    if tonumber(x) == nil or tonumber(y) == nil then return nil end
    local point = { x = data.ProjectALifeStackX, y = data.ProjectALifeStackY, z = data.ProjectALifeStackZ or 0 }
    return { point = point, away = distance(x, y, point.x, point.y), inside = buildingAt(x, y, z or 0) ~= nil }
end

Registry.register({
    id = "doorstack",
    kind = "craft",
    priority = 60,
    label = "Door-stack",
    summary = "A fireteam stacks on a door, holds fire on the wall, opens it, checks the doorway, and flows in to fanned corners.",
    defaultEnabled = true,
    evaluate = function() return nil end,
})

local function roomKeyOf(definition, fallbackSquare)
    local key
    pcall(function() key = tostring(definition:getID()) end)
    if key == nil and fallbackSquare ~= nil then
        pcall(function() key = fallbackSquare:getX() .. "," .. fallbackSquare:getY() .. "," .. fallbackSquare:getZ() end)
    end
    return key
end

function Breach.readRooms(shell)
    local rooms, hereKey = {}, nil
    pcall(function()
        local square = shell:getCurrentSquare()
        if square == nil then return end
        local building = square:getBuilding()
        if building == nil then return end
        local definition = building:getDef()
        if definition == nil or definition.getRooms == nil then return end
        local list = definition:getRooms()
        if list == nil then return end
        local floorZ = math.floor(shell:getZ())
        pcall(function()
            local mine = square:getRoom()
            if mine ~= nil then hereKey = roomKeyOf(mine:getRoomDef(), nil) end
        end)
        for index = 0, math.min(list:size(), Breach.settings.roomScanLimit) - 1 do
            local definitionRoom = list:get(index)
            pcall(function()
                if definitionRoom == nil or math.floor(definitionRoom:getZ()) ~= floorZ then return end
                local iso = definitionRoom:getIsoRoom()
                local squares = iso and iso:getSquares() or nil
                if squares == nil or squares:size() == 0 then return end
                local entry = { z = floorZ, squares = {}, size = squares:size() }
                local sumX, sumY = 0, 0
                for at = 0, squares:size() - 1 do
                    local sq = squares:get(at)
                    if sq ~= nil then
                        sumX, sumY = sumX + sq:getX(), sumY + sq:getY()
                        if sq:isFree(false) then entry.squares[#entry.squares + 1] = { x = sq:getX() + 0.5, y = sq:getY() + 0.5, sq = sq } end
                    end
                end
                entry.cx, entry.cy = sumX / entry.size + 0.5, sumY / entry.size + 0.5
                entry.key = roomKeyOf(definitionRoom, squares:get(0))
                if entry.key ~= nil and #entry.squares > 0 then rooms[#rooms + 1] = entry end
            end)
        end
    end)
    return rooms, hereKey
end

function Breach.doorwayInto(room, here, hereKey)
    local outside, inside, bestD
    for _, entry in ipairs(room.squares or {}) do
        pcall(function()
            local sq = entry.sq
            for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local near = getCell():getGridSquare(sq:getX() + step[1], sq:getY() + step[2], sq:getZ())
                local nearRoom = near and near:getRoom() or nil
                local nearKey = nearRoom and roomKeyOf(nearRoom:getRoomDef(), nil) or nil
                if near ~= nil and nearKey ~= room.key and (hereKey == nil or nearKey == hereKey)
                        and (sq:getDoorTo(near) ~= nil or not sq:isBlockedTo(near)) then
                    local d = distance(here.x, here.y, near:getX() + 0.5, near:getY() + 0.5)
                    if bestD == nil or d < bestD then
                        bestD = d
                        outside = { x = near:getX() + 0.5, y = near:getY() + 0.5, z = room.z }
                        inside = { x = entry.x, y = entry.y, z = room.z }
                    end
                end
            end
        end)
    end
    if inside == nil then
        for _, entry in ipairs(room.squares or {}) do
            local d = distance(here.x, here.y, entry.x, entry.y)
            if bestD == nil or d < bestD then bestD, inside = d, { x = entry.x, y = entry.y, z = room.z } end
        end
        outside = inside
    end
    return outside, inside
end

local function clearRoom(actor, context, plan, now)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local cleared = type(memory.cqbCleared) == "table" and memory.cqbCleared or {}
    cleared[tostring(plan.key)] = now
    for key, at in pairs(cleared) do
        if now - (tonumber(at) or 0) >= Breach.settings.roomClearedMs then cleared[key] = nil end
    end
    context.persistMemory(actor, "cqbCleared", cleared)
    context.persistMemory(actor, "cqbPlan", nil)
    local group = memory.groupId or actor.uid
    Breach.groupCleared[group] = Breach.groupCleared[group] or {}
    Breach.groupCleared[group][tostring(plan.key)] = now
    Breach.roomClaims[plan.key] = nil
    Breach.metrics.roomsCleared = Breach.metrics.roomsCleared + 1
end

local function sweepLeg(actor, shell, context, plan, here, target, now)
    plan.legs = (tonumber(plan.legs) or 0) + 1
    context.persistMemory(actor, "cqbPlan", plan)
    pcall(function()
        local traversal = ProjectALife.ObstacleTraversal
        if traversal ~= nil then traversal.openDoorAhead(shell, target) end
    end)
    Breach.metrics.sweeps = Breach.metrics.sweeps + 1
    return context.startMovement(actor, shell, { x = target.x, y = target.y, z = target.z }, "cqb_sweep",
        { pace = "walk", timeoutMs = Breach.legTimeoutMs(here, target) })
end

function Breach.sweepStep(actor, shell, context)
    local s = Breach.settings
    local now = tonumber(context.now) or nowMsFallback()
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local here = { x = 0, y = 0, z = 0 }
    pcall(function() here.x, here.y, here.z = shell:getX(), shell:getY(), shell:getZ() end)
    local plan = type(memory.cqbPlan) == "table" and memory.cqbPlan or nil
    if plan ~= nil and plan.stage == "check" then
        if now < (tonumber(plan.untilMs) or 0) then
            return { kind = "idle", intent = "cqb_look", cooldownUntilMs = math.min(tonumber(plan.untilMs) or now, now + 1000) }
        end
        clearRoom(actor, context, plan, now)
        plan = nil
    end
    if plan ~= nil and (tonumber(plan.legs) or 0) >= s.legsPerRoom then
        clearRoom(actor, context, plan, now)
        plan = nil
    end
    if plan == nil then
        local rooms, hereKey = Breach.readRooms(shell)
        here.roomKey = hereKey
        local group = memory.groupId or actor.uid
        local open = Breach.openRooms(rooms, here, memory.cqbCleared, Breach.groupCleared[group], now, s)
        local room = Breach.pickRoom(open, Breach.roomClaims, actor.uid, now)
        if room == nil then return nil end
        local doorway, entry = Breach.doorwayInto(room, here, hereKey)
        local deep = Breach.deepestSquare(room.squares, doorway) or entry
        if doorway == nil or deep == nil then return nil end
        Breach.roomClaims[room.key] = { uid = actor.uid, untilMs = now + s.roomClaimMs }
        plan = { key = room.key, stage = "doorway", legs = 0,
            doorway = doorway, deep = { x = deep.x, y = deep.y, z = room.z },
            checkMs = Breach.roomCheckMs(room.size, s) }
    end
    if plan.stage == "doorway" then
        if distance(here.x, here.y, plan.doorway.x, plan.doorway.y) > s.doorwayReach then
            return sweepLeg(actor, shell, context, plan, here, plan.doorway, now)
        end
        plan.stage, plan.legs = "deep", 0
    end
    if distance(here.x, here.y, plan.deep.x, plan.deep.y) > s.deepReach then
        return sweepLeg(actor, shell, context, plan, here, plan.deep, now)
    end

    plan.stage, plan.untilMs = "check", now + (tonumber(plan.checkMs) or s.roomCheckBaseMs)
    context.persistMemory(actor, "cqbPlan", plan)
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then
            guard.faceAimPoint(shell, plan.doorway.x, plan.doorway.y, now)
        end
    end)
    Breach.metrics.looks = Breach.metrics.looks + 1
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "cqb_look") end
    return { kind = "idle", intent = "cqb_look", cooldownUntilMs = math.min(plan.untilMs, now + 1000) }
end

Registry.register({
    id = "cqbsweep",
    kind = "craft",
    dispatch = "decision",
    priority = 92,
    label = "CQB sweep",
    summary = "Indoors with nothing in sight the squad clears the floor room by room: doorway, the far side of the room, a look round, and never two men in one room.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if context == nil or not Registry.allows(actor, "cqbsweep") then return nil end
        if context.threat ~= nil then return nil end
        if type(context.persistMemory) ~= "function" or type(context.startMovement) ~= "function" then return nil end
        local tactics = ProjectALife.SquadTactics
        if tactics == nil or tactics.tierOf(shell, actor) ~= "cqb" then return nil end
        return Breach.sweepStep(actor, shell, context)
    end,
})

return Breach
