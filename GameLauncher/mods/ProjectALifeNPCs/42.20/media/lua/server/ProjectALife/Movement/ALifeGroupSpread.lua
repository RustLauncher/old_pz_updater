require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Spread = {
    settings = {
        indexMs = 700,
        minGap = 1.5,
        claimMs = 25000,
        calmMs = 20000,
        legMs = 45000,
        columnGap = 2.6,
        columnFile = 4,
        columnJitter = 0.55,
        rowForward = 2.4,
        rowSide = 2.1,
        legJitter = 0.6,
        ringBase = 3.4,
        ringStep = 0.5,
        stationRing = 5.0,
        corridorWidth = 3,
        corridorCacheMs = 20000,
        corridorLimit = 128,
        crowdedTiles = 1.4,
        staggerMs = 650,
        settleMs = 2500,
        settleReach = { 2.0, 2.8, 3.6 },
        walkGap = 1.0,
        gapCheckMs = 400,
        gapHoldMs = 550,
        gapWindowMs = 8000,
        gapMaxHolds = 2,
    },
    metrics = {
        spreadAdjustments = 0, sharedSquaresAvoided = 0, marchShaped = 0,
        followSlots = 0, stations = 0, settles = 0, staggers = 0, patrolShaped = 0, gapHolds = 0, slotsBlocked = 0,
    },
    gaps = {},
    adapters = {},
    index = { atMs = -1e12, groups = {} },
    claims = {},
    legs = {},
    corridors = {},
    corridorCount = 0,
    waited = {},
    reaches = {},
}
ProjectALife.GroupSpread = Spread

function Spread.nowMs()
    if type(Spread.adapters.nowMs) == "function" then return Spread.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Spread.enabled()
    return Gate.flag("GroupLife_Enabled", true)
end

function Spread.strength()
    return Gate.number("GroupLife_Spread", 100, 0, 150) / 100
end

function Spread.active()
    return Spread.enabled() and Spread.strength() > 0 and Gate.authority()
end

function Spread.reset()
    Spread.index = { atMs = -1e12, groups = {} }
    Spread.claims, Spread.legs, Spread.corridors, Spread.waited = {}, {}, {}, {}
    Spread.corridorCount = 0
    Spread.reaches, Spread.gaps = {}, {}
end

function Spread.hash(text)
    local value = 7
    text = tostring(text or "")
    for index = 1, #text do
        value = (value * 31 + string.byte(text, index) + (value % 13) * 7) % 2147483647
    end
    for _ = 1, 3 do value = (value * 48271 + 11) % 2147483647 end
    return value
end

function Spread.unit(text)
    return (Spread.hash(text) % 10000) / 10000
end

function Spread.signed(text)
    return Spread.unit(text) * 2 - 1
end

function Spread.bearing(dy, dx)
    if type(math.atan2) == "function" then return math.atan2(dy, dx) end
    return math.atan(dy, dx)
end

function Spread.positionOf(shell)
    return shell:getX(), shell:getY(), shell:getZ()
end

function Spread.squareAt(x, y, z)
    if type(Spread.adapters.squareAt) == "function" then return Spread.adapters.squareAt(x, y, z) end
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return nil end
    local ok, square = pcall(cell.getGridSquare, cell, math.floor(x), math.floor(y), math.floor(z))
    if ok then return square end
    return nil
end

function Spread.standable(square)
    if square == nil then return false end
    local ok, free = pcall(square.isFree, square, false)
    if not ok or free ~= true then return false end
    local solid
    ok, solid = pcall(square.TreatAsSolidFloor, square)
    return ok and solid == true
end

function Spread.walkable(x, y, z)
    if type(Spread.adapters.walkable) == "function" then return Spread.adapters.walkable(x, y, z) == true end
    return Spread.standable(Spread.squareAt(x, y, z))
end

function Spread.clamp(x, y, z, fromX, fromY)
    if Spread.walkable(x, y, z) then return x, y, false end
    for _, fraction in ipairs({ 0.75, 0.5, 0.25 }) do
        local cx, cy = fromX + (x - fromX) * fraction, fromY + (y - fromY) * fraction
        if Spread.walkable(cx, cy, z) then return cx, cy, true end
    end
    return fromX, fromY, true
end

function Spread.sorter(left, right)
    if left.key ~= right.key then return left.key < right.key end
    return left.uid < right.uid
end

function Spread.rankKey(entry)
    if entry.leader then return -1 end
    if entry.index ~= nil then return entry.index end
    return 1000 + Spread.hash(entry.uid) % 1000
end

function Spread.build(rows)
    local groups = {}
    for _, row in ipairs(rows) do
        local group = groups[row.groupId]
        if group == nil then
            group = { id = row.groupId, list = {}, byUid = {}, size = 0 }
            groups[row.groupId] = group
        end
        row.key = Spread.rankKey(row)
        group.list[#group.list + 1] = row
    end
    for _, group in pairs(groups) do
        table.sort(group.list, Spread.sorter)
        for position, entry in ipairs(group.list) do
            entry.rank = position - 1
            group.byUid[entry.uid] = entry
        end
        group.size = #group.list
        group.leader = group.list[1].leader and group.list[1] or nil
    end
    return groups
end

function Spread.collect()
    local rows = {}
    local watchdog, registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    if watchdog == nil or registry == nil or type(watchdog.bindings) ~= "table" then return rows end
    for uid, binding in pairs(watchdog.bindings) do
        local shell = type(binding) == "table" and binding.shell or nil
        local record = shell ~= nil and registry.peek(uid) or nil
        local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
        if memory ~= nil and record.lifecycle == "active" and type(memory.groupId) == "string" then
            local ok, x, y, z = pcall(Spread.positionOf, shell)
            if ok and x ~= nil and y ~= nil then
                rows[#rows + 1] = {
                    uid = uid, groupId = memory.groupId, x = x, y = y, z = z or 0, shell = shell,
                    index = tonumber(memory.groupIndex),
                    leader = memory.groupRole == "leader" or memory.conduct == "leader",
                }
            end
        end
    end
    return rows
end

function Spread.refresh(now)
    now = tonumber(now) or Spread.nowMs()
    local index = Spread.index
    if math.abs(now - index.atMs) < Spread.settings.indexMs then return index.groups end
    index.atMs = now
    index.groups = Spread.build(Spread.collect())
    return index.groups
end

function Spread.groupOf(groupId, now)
    if type(groupId) ~= "string" then return nil end
    return Spread.refresh(now)[groupId]
end

function Spread.calm(groupId, now)
    now = tonumber(now) or Spread.nowMs()
    local tactics = ProjectALife.SquadTactics
    local held = tactics ~= nil and type(tactics.contacts) == "table" and tactics.contacts[groupId] or nil
    if type(held) == "table" and now - (tonumber(held.atMs) or -1e12) < Spread.settings.calmMs then return false end
    local leader = ProjectALife.ModuleLeader
    local record = leader ~= nil and type(leader.groups) == "table" and leader.groups[groupId] or nil
    if type(record) == "table" and (record.inContact == true or now < (tonumber(record.rallyUntilMs) or 0)) then
        return false
    end
    return true
end

function Spread.eligible(memory)
    if type(memory) ~= "table" or type(memory.groupId) ~= "string" then return false end
    if memory.stance ~= nil and memory.stance ~= "" and memory.stance ~= "route" then return false end
    return true
end

function Spread.frame(heading)
    local hx, hy = math.cos(heading), math.sin(heading)
    return hx, hy, -hy, hx
end

function Spread.freeWidth(x, y, z, px, py)
    local width = 1
    for side = -1, 1, 2 do
        for step = 1, 4 do
            if Spread.walkable(x + px * step * side, y + py * step * side, z) then
                width = width + 1
            else
                break
            end
        end
    end
    return width
end

function Spread.kindAt(x, y, z, hx, hy)
    local road = ProjectALife.Road
    if road ~= nil and type(road.isPavedSurface) == "function" then
        local square = Spread.squareAt(x, y, z)
        if square ~= nil then
            local ok, paved = pcall(road.isPavedSurface, square)
            if ok and paved == true then return "column" end
        end
    end
    local bucket = math.floor((Spread.bearing(hy, hx) + math.pi) / (math.pi / 4))
    local key = math.floor(x / 4) .. ":" .. math.floor(y / 4) .. ":" .. bucket
    local now = Spread.nowMs()
    local cached = Spread.corridors[key]
    if cached ~= nil and now - cached.atMs < Spread.settings.corridorCacheMs then return cached.kind end
    local kind = Spread.freeWidth(x, y, z, -hy, hx) <= Spread.settings.corridorWidth and "column" or "open"
    if Spread.corridorCount >= Spread.settings.corridorLimit then
        Spread.corridors, Spread.corridorCount = {}, 0
    end
    if Spread.corridors[key] == nil then Spread.corridorCount = Spread.corridorCount + 1 end
    Spread.corridors[key] = { kind = kind, atMs = now }
    return kind
end

function Spread.offset(kind, size, rank, uid, scale)
    if rank <= 0 or size < 2 then return 0, 0 end
    local s = Spread.settings
    local jitterForward = Spread.signed(tostring(uid) .. ":f") * s.columnJitter
    local jitterSide = Spread.signed(tostring(uid) .. ":l")
    local side = (rank % 2 == 1) and -1 or 1
    if kind == "column" then
        if rank > s.columnFile then
            local row = s.columnFile + math.ceil((rank - s.columnFile) / 2)
            return -(row * s.columnGap + jitterForward) * scale,
                side * (0.8 + 0.5 * math.abs(jitterSide)) * scale
        end
        return -(rank * s.columnGap + jitterForward) * scale,
            side * (0.4 + 0.5 * math.abs(jitterSide)) * scale
    end
    local row = math.ceil(rank / 2)
    local lane = ((row - 1) % 3) + 1
    local forward = -(row * s.rowForward + jitterForward) * scale
    local lateral = side * (lane * s.rowSide + jitterSide * 0.35) * scale
    if size >= 4 and rank <= 2 then
        lateral = lateral * 1.6
        forward = forward + 1.4 * scale
    end
    return forward, lateral
end

function Spread.reach(size)
    if not Spread.active() then return 0 end
    local scale = Spread.strength()
    local cacheKey = size .. ":" .. scale
    if Spread.reaches[cacheKey] ~= nil then return Spread.reaches[cacheKey] end
    local far = 0
    for rank = 1, math.max(1, size - 1) do
        for _, kind in ipairs({ "column", "open" }) do
            local forward, lateral = Spread.offset(kind, math.max(2, size), rank, "reach", scale)
            local length = math.sqrt(forward * forward + lateral * lateral)
            if length > far then far = length end
        end
    end
    local total = far + (Spread.settings.columnJitter + Spread.settings.legJitter) * scale + 1.5
    Spread.reaches[cacheKey] = total
    return total
end

function Spread.separate(points, gap)
    local gap2 = gap * gap
    local aim = gap * 1.04
    for _ = 1, 12 do
        local touched = false
        for i = 1, #points - 1 do
            local a = points[i]
            for j = i + 1, #points do
                local b = points[j]
                local dx, dy = b.x - a.x, b.y - a.y
                local d2 = dx * dx + dy * dy
                if d2 < gap2 then
                    local distance = math.sqrt(d2)
                    if distance < 0.001 then
                        local angle = Spread.unit(tostring(a.key) .. ":" .. tostring(b.key)) * math.pi * 2
                        dx, dy, distance = math.cos(angle), math.sin(angle), 1
                    end
                    local ux, uy = dx / distance, dy / distance
                    local need = aim - math.sqrt(d2)
                    if a.pinned and not b.pinned then
                        b.x, b.y = b.x + ux * need, b.y + uy * need
                        b.adjusted = true
                    elseif b.pinned and not a.pinned then
                        a.x, a.y = a.x - ux * need, a.y - uy * need
                        a.adjusted = true
                    else
                        a.x, a.y = a.x - ux * need / 2, a.y - uy * need / 2
                        b.x, b.y = b.x + ux * need / 2, b.y + uy * need / 2
                        a.adjusted, b.adjusted = true, true
                    end
                    touched = true
                end
            end
        end
        if not touched then break end
    end
    local moved = 0
    for _, point in ipairs(points) do
        if point.adjusted then moved = moved + 1 end
    end
    return moved
end

function Spread.legPlan(group, heading, leg, now)
    local lead = group.leader or group.list[1]
    local legs = Spread.legs[group.id]
    local slot = math.floor(now / Spread.settings.legMs)
    if legs ~= nil and legs.slot == slot and legs.size == group.size and legs.heading == heading then
        local dx, dy = lead.x - legs.baseX, lead.y - legs.baseY
        if dx * dx + dy * dy > 4.84 then return legs end
    end
    local hx, hy, px, py = Spread.frame(heading)
    local scale = Spread.strength()
    local serial = (legs ~= nil and legs.serial or 0) + 1
    local baseX, baseY = lead.x + hx * leg, lead.y + hy * leg
    local kind = Spread.kindAt(lead.x, lead.y, lead.z, hx, hy)
    local points = {}
    for _, entry in ipairs(group.list) do
        local forward, lateral = Spread.offset(kind, group.size, entry.rank, entry.uid, scale)
        if entry.rank > 0 then
            local jitter = Spread.settings.legJitter * scale
            forward = forward + Spread.signed(entry.uid .. ":a:" .. serial) * jitter
            lateral = lateral + Spread.signed(entry.uid .. ":b:" .. serial) * jitter
            if forward > -0.6 * scale then forward = -0.6 * scale end
        end
        points[#points + 1] = {
            key = entry.uid, uid = entry.uid, pinned = entry.rank == 0,
            x = baseX + hx * forward + px * lateral,
            y = baseY + hy * forward + py * lateral,
        }
    end
    local moved = Spread.separate(points, Spread.settings.minGap)
    Spread.metrics.spreadAdjustments = Spread.metrics.spreadAdjustments + moved
    local targets = {}
    for _, point in ipairs(points) do targets[point.uid] = point end
    legs = { slot = slot, serial = serial, size = group.size, heading = heading,
        baseX = baseX, baseY = baseY, kind = kind, targets = targets }
    Spread.legs[group.id] = legs
    return legs
end

function Spread.claimed(groupId, uid, x, y, z, now)
    local set = Spread.claims[groupId]
    if set == nil then
        set = {}
        Spread.claims[groupId] = set
    end
    local gap = Spread.settings.minGap
    local function clear(px, py)
        for other, claim in pairs(set) do
            if other ~= uid and now < claim.untilMs and math.abs(claim.z - z) < 0.5
                    and (claim.x - px) ^ 2 + (claim.y - py) ^ 2 < gap * gap then
                return false
            end
        end
        return true
    end
    local chosenX, chosenY = x, y
    if not clear(x, y) then
        local shared = false
        for other, claim in pairs(set) do
            if other ~= uid and now < claim.untilMs and math.floor(claim.x) == math.floor(x)
                    and math.floor(claim.y) == math.floor(y) then
                shared = true
            end
        end
        if shared then Spread.metrics.sharedSquaresAvoided = Spread.metrics.sharedSquaresAvoided + 1 end
        local start = Spread.unit(tostring(uid) .. ":claim") * math.pi * 2
        local found = false
        for _, radius in ipairs({ 1.6, 2.4, 3.2 }) do
            for step = 0, 7 do
                local angle = start + step * math.pi / 4
                local cx, cy = x + math.cos(angle) * radius, y + math.sin(angle) * radius
                if clear(cx, cy) and Spread.walkable(cx, cy, z) then
                    chosenX, chosenY, found = cx, cy, true
                    break
                end
            end
            if found then break end
        end
        if found then Spread.metrics.spreadAdjustments = Spread.metrics.spreadAdjustments + 1 end
    end
    set[uid] = { x = chosenX, y = chosenY, z = z, untilMs = now + Spread.settings.claimMs }
    return chosenX, chosenY
end

function Spread.release(groupId, uid)
    local set = Spread.claims[groupId]
    if set ~= nil then set[uid] = nil end
end

function Spread.nearestMate(group, me)
    local best = math.huge
    for _, entry in ipairs(group.list) do
        if entry ~= me and math.abs(entry.z - me.z) < 1.5 then
            local d2 = (entry.x - me.x) ^ 2 + (entry.y - me.y) ^ 2
            if d2 < best then best = d2 end
        end
    end
    return math.sqrt(best)
end

function Spread.contextFor(actor, now)
    if not Spread.active() then return nil end
    local memory = actor ~= nil and actor.memory or nil
    if not Spread.eligible(memory) then return nil end
    now = tonumber(now) or Spread.nowMs()
    local group = Spread.groupOf(memory.groupId, now)
    if group == nil or group.size < 2 then return nil end
    local me = group.byUid[actor.uid]
    if me == nil or not Spread.calm(group.id, now) then return nil end
    return group, me, now
end

function Spread.marchTarget(actor, shell, heading, leg, now)
    local group, me
    group, me, now = Spread.contextFor(actor, now)
    if group == nil then return nil end
    local plan = Spread.legPlan(group, heading, leg, now)
    local point = plan.targets[actor.uid]
    if point == nil then return nil end
    if me.rank > 0 and Spread.waited[actor.uid] ~= plan.serial then
        Spread.waited[actor.uid] = plan.serial
        if Spread.nearestMate(group, me) < Spread.settings.crowdedTiles then
            Spread.metrics.staggers = Spread.metrics.staggers + 1
            return { wait = Spread.settings.staggerMs * me.rank, serial = plan.serial }
        end
    end
    local x, y = Spread.clamp(point.x, point.y, me.z, me.x, me.y)
    x, y = Spread.claimed(group.id, actor.uid, x, y, me.z, now)
    Spread.metrics.marchShaped = Spread.metrics.marchShaped + 1
    return { x = x, y = y, z = me.z, serial = plan.serial, kind = plan.kind }
end

function Spread.ringSlot(actor, shell, center, radius, now)
    local group, me
    group, me, now = Spread.contextFor(actor, now)
    if group == nil or type(center) ~= "table" then return nil end
    local rank = math.max(1, me.rank)
    local count = math.max(1, group.size - 1)
    local angle = ((rank - 1) / count) * math.pi * 2 + Spread.unit(group.id .. ":ring") * math.pi * 2
    local reach = (radius + Spread.settings.ringStep * ((rank - 1) % 3)) * math.max(0.6, Spread.strength())
    local x, y, clamped = Spread.clamp(center.x + math.cos(angle) * reach, center.y + math.sin(angle) * reach,
        tonumber(center.z) or me.z, me.x, me.y)
    if clamped == true and x == me.x and y == me.y then
        Spread.metrics.slotsBlocked = (Spread.metrics.slotsBlocked or 0) + 1
        return nil
    end
    x, y = Spread.claimed(group.id, actor.uid, x, y, tonumber(center.z) or me.z, now)
    return { x = x, y = y, z = tonumber(center.z) or me.z }
end

function Spread.followSlot(actor, shell, leaderPosition, now)
    local slot = Spread.ringSlot(actor, shell, leaderPosition, Spread.settings.ringBase, now)
    if slot ~= nil then Spread.metrics.followSlots = Spread.metrics.followSlots + 1 end
    return slot
end

function Spread.stationPoint(actor, shell, leaderPosition, now)
    local slot = Spread.ringSlot(actor, shell, leaderPosition, Spread.settings.stationRing, now)
    if slot ~= nil then Spread.metrics.stations = Spread.metrics.stations + 1 end
    return slot
end

function Spread.patrolTarget(actor, anchor, angle, radius, now)
    local group, me
    group, me, now = Spread.contextFor(actor, now)
    if group == nil or type(anchor) ~= "table" then return nil end
    local hx, hy, px, py = Spread.frame(angle)
    local scale = Spread.strength()
    local phase = math.floor(now / 14000)
    local forward, lateral = Spread.offset("open", group.size, me.rank, actor.uid, scale)
    if me.rank > 0 then
        local jitter = Spread.settings.legJitter * scale
        forward = forward + Spread.signed(actor.uid .. ":pa:" .. phase) * jitter
        lateral = lateral + Spread.signed(actor.uid .. ":pb:" .. phase) * jitter
    end
    local z = tonumber(anchor.z) or me.z
    local x, y = Spread.clamp(anchor.x + hx * radius + hx * forward + px * lateral,
        anchor.y + hy * radius + hy * forward + py * lateral, z, me.x, me.y)
    x, y = Spread.claimed(group.id, actor.uid, x, y, z, now)
    Spread.metrics.patrolShaped = Spread.metrics.patrolShaped + 1
    return { x = x, y = y, z = z }
end

function Spread.settle(actor, shell, context, spacing)
    local group, me, now
    group, me, now = Spread.contextFor(actor, context ~= nil and context.now or nil)
    if group == nil or (context ~= nil and context.threat ~= nil) then return nil end
    local life = ProjectALife.GroupLife
    if life ~= nil and type(life.stateOf) == "function" and life.stateOf(group.id) ~= nil then return nil end
    local gap = math.max(Spread.settings.minGap, tonumber(spacing) or 0)
    local near, nearX, nearY, sharing = math.huge, nil, nil, false
    for _, entry in ipairs(group.list) do
        if entry ~= me and math.abs(entry.z - me.z) < 1.5 then
            local d2 = (entry.x - me.x) ^ 2 + (entry.y - me.y) ^ 2
            if d2 < near then near, nearX, nearY = d2, entry.x, entry.y end
            if math.floor(entry.x) == math.floor(me.x) and math.floor(entry.y) == math.floor(me.y) then sharing = true end
        end
    end
    if nearX == nil or near >= (gap * 0.75) ^ 2 then return nil end
    local data
    pcall(function() data = shell:getModData() end)
    if type(data) ~= "table" then return nil end
    if now < (tonumber(data.ProjectALifeSpreadNextAtMs) or 0) then return nil end
    data.ProjectALifeSpreadNextAtMs = now + Spread.settings.settleMs
    local away = Spread.bearing(me.y - nearY, me.x - nearX)
    local best
    for _, reach in ipairs(Spread.settings.settleReach) do
        for step = 0, 7 do
            local sign = (step % 2 == 0) and 1 or -1
            local angle = away + sign * math.ceil(step / 2) * math.pi / 4
            local x, y = me.x + math.cos(angle) * reach, me.y + math.sin(angle) * reach
            if Spread.walkable(x, y, me.z) then
                local clear = true
                for _, entry in ipairs(group.list) do
                    if entry ~= me and math.abs(entry.z - me.z) < 1.5
                            and (entry.x - x) ^ 2 + (entry.y - y) ^ 2 < (gap * 1.1) ^ 2 then
                        clear = false
                    end
                end
                if clear then
                    best = { x = x, y = y, z = me.z }
                    break
                end
            end
        end
        if best ~= nil then break end
    end
    if best == nil or type(context.startMovement) ~= "function" then return nil end
    if sharing then Spread.metrics.sharedSquaresAvoided = Spread.metrics.sharedSquaresAvoided + 1 end
    Spread.metrics.settles = Spread.metrics.settles + 1
    Spread.metrics.spreadAdjustments = Spread.metrics.spreadAdjustments + 1
    return context.startMovement(actor, shell, best, "spread", { pace = "walk", timeoutMs = 4000 })
end

function Spread.gapHold(actor, shell, state, now)
    if not Spread.active() or type(state) ~= "table" then return nil end
    local intent = state.intent
    if intent ~= "patrol" and intent ~= "regroup" and intent ~= "hold" then return nil end
    now = tonumber(now) or Spread.nowMs()
    local entry = Spread.gaps[actor.uid]
    if entry == nil then
        entry = { atMs = 0, windowAtMs = now, count = 0 }
        Spread.gaps[actor.uid] = entry
    end
    if now < entry.atMs then return nil end
    entry.atMs = now + Spread.settings.gapCheckMs
    local memory = actor.memory
    if not Spread.eligible(memory) then return nil end
    local group = Spread.groupOf(memory.groupId, now)
    if group == nil or group.size < 2 then return nil end
    local me = group.byUid[actor.uid]
    local target = type(state.action) == "table" and state.action.target or nil
    if me == nil or type(target) ~= "table" or not Spread.calm(group.id, now) then return nil end
    local ok, sx, sy, sz = pcall(Spread.positionOf, shell)
    if not ok or sx == nil then return nil end
    local dx, dy = target.x - sx, target.y - sy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 2 then return nil end
    dx, dy = dx / length, dy / length
    local limit2 = Spread.settings.walkGap * Spread.settings.walkGap
    for _, mate in ipairs(group.list) do
        if mate ~= me and math.abs(mate.z - sz) < 1.5 and (mate.x - sx) ^ 2 + (mate.y - sy) ^ 2 < 16 then
            local live, mx, my = pcall(Spread.positionOf, mate.shell)
            if live and mx ~= nil then
                local ox, oy = mx - sx, my - sy
                local ahead = ox * dx + oy * dy
                if ox * ox + oy * oy < limit2 and (ahead > 0.3 or (ahead > -0.3 and me.rank > mate.rank)) then
                    if now - entry.windowAtMs > Spread.settings.gapWindowMs then entry.windowAtMs, entry.count = now, 0 end
                    if entry.count >= Spread.settings.gapMaxHolds then return nil end
                    entry.count = entry.count + 1
                    Spread.metrics.gapHolds = Spread.metrics.gapHolds + 1
                    return { kind = "idle", intent = "gap_hold", cooldownUntilMs = now + Spread.settings.gapHoldMs }
                end
            end
        end
    end
    return nil
end

function Spread.sweep(now)
    now = tonumber(now) or Spread.nowMs()
    local groups = Spread.refresh(now)
    for groupId, set in pairs(Spread.claims) do
        if groups[groupId] == nil then
            Spread.claims[groupId] = nil
        else
            for uid, claim in pairs(set) do
                if now >= claim.untilMs then set[uid] = nil end
            end
        end
    end
    for groupId in pairs(Spread.legs) do
        if groups[groupId] == nil then Spread.legs[groupId] = nil end
    end
end

return Spread
