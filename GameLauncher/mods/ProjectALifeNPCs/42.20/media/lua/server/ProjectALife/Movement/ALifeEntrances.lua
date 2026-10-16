require "ProjectALife/Movement/ALifeDoorPolicy"

ProjectALife = ProjectALife or {}

local Entrances = {

    claims = {},

    held = {},
    settings = {

        ttlMs = 20000,

        searchRadius = 14,

        maximumOpenings = 12,

        sharedCost = 10,
        busyEdgeCost = 6,

        keepBonus = 3,

        shareBand = 4,
    },

    cost = {
        openDoor = 0,
        closedDoor = 2,
        window = 6,
        glassyWindow = 14,
        lockedDoor = 14,
        thumpable = 18,
    },
    metrics = { claims = 0, shared = 0, releases = 0, switched = 0, busyCosted = 0, spread = 0 },
}
ProjectALife.Entrances = Entrances

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function keyOf(x, y, z)
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

local function standable(square)
    if square == nil then return false end
    local ok, free = pcall(function()

        return square:isFree(false) == true
            and square:TreatAsSolidFloor() == true
    end)
    return ok and free == true
end

function Entrances.residentOpening(actor, site, bounds)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" or memory.outpostId == nil or type(site) ~= "table" then return nil end
    if tostring(memory.outpostId) ~= tostring(site.id) then return nil end
    local main = site.mainEntrance
    if type(main) ~= "table" or type(bounds) ~= "table" then return nil end
    if main.x < bounds.x1 - 1 or main.x > bounds.x2 + 1
            or main.y < bounds.y1 - 1 or main.y > bounds.y2 + 1 then return nil end
    local ox, oy = 0, 1
    if main.side == "N" then ox, oy = 0, -1
    elseif main.side == "W" then ox, oy = -1, 0
    elseif main.side == "E" then ox, oy = 1, 0 end
    local x, y = main.x + ox, main.y + oy
    return { x = x + 0.5, y = y + 0.5, z = main.z or 0, key = keyOf(x, y, main.z or 0), main = true }
end

local function siteOf(actor, building)
    local site, bounds
    pcall(function()
        local registry = ProjectALife.OutpostRegistry
        local memory = type(actor) == "table" and actor.memory or nil
        if registry == nil or type(memory) ~= "table" or memory.outpostId == nil then return end
        local record = registry.read(memory.outpostId)
        if record == nil then return end
        local definition = building:getDef()
        if definition == nil then return end
        bounds = { x1 = definition:getX(), y1 = definition:getY(),
            x2 = definition:getX2(), y2 = definition:getY2() }
        site = record
    end)
    return site, bounds
end

function Entrances.doorLocked(door)
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.lockKind) == "function" then
        return policy.lockKind(door) ~= nil
    end
    return door ~= nil and door.isLocked ~= nil and door:isLocked() == true
end

function Entrances.edgeRefused(square, inside)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.edgeBanned) ~= "function" then return false end
    return policy.edgeBanned(square, inside, nowMs()) == true
end

function Entrances.openings(building, fromX, fromY, fromZ, actor, doorsOnly)
    local found = {}
    if building == nil then return found end
    local memory = type(actor) == "table" and actor.memory or nil
    doorsOnly = doorsOnly == true or (type(memory) == "table" and memory.lootPhase ~= nil)

    if actor ~= nil then
        local site, bounds = siteOf(actor, building)
        local resident = site and Entrances.residentOpening(actor, site, bounds) or nil
        if resident ~= nil then return { resident } end
    end
    pcall(function()
        local definition = building:getDef()
        if definition == nil then return end
        local cell = getCell()
        if cell == nil then return end
        local radius = Entrances.settings.searchRadius
        local x1 = math.max(definition:getX() - 1, math.floor(fromX) - radius)
        local x2 = math.min(definition:getX2() + 1, math.floor(fromX) + radius)
        local y1 = math.max(definition:getY() - 1, math.floor(fromY) - radius)
        local y2 = math.min(definition:getY2() + 1, math.floor(fromY) + radius)
        local floor = math.floor(fromZ)
        for x = x1, x2 do
            for y = y1, y2 do
                if #found >= Entrances.settings.maximumOpenings then return end
                local square = cell:getGridSquare(x, y, floor)
                if square ~= nil and square:getBuilding() == nil then

                    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local inside = cell:getGridSquare(x + step[1], y + step[2], floor)
                        if inside ~= nil and inside:getBuilding() == building then
                            local opening = false

                            local cost = Entrances.cost.window
                            local obstructed, climb = false, false
                            pcall(function()
                                local door = square:getDoorTo(inside)
                                opening = door ~= nil

                                if door ~= nil and door:IsOpen() ~= true then
                                    pcall(function() obstructed = door:isObstructed() == true end)
                                    local policy = ProjectALife.DoorPolicy
                                    if not obstructed and policy ~= nil and type(policy.groupObstructed) == "function" then
                                        obstructed = policy.groupObstructed(door) == true
                                    end
                                end
                                if door ~= nil then
                                    if door:IsOpen() == true then
                                        cost = Entrances.cost.openDoor
                                    elseif Entrances.doorLocked(door) == true then
                                        cost = Entrances.cost.lockedDoor
                                    else
                                        cost = Entrances.cost.closedDoor
                                    end
                                end
                                if doorsOnly and door ~= nil then
                                    opening = not door:isBarricaded()
                                elseif not doorsOnly then
                                    if not opening and (square:getWindowTo(inside) ~= nil
                                            or square:getWindowFrameTo(inside) ~= nil) then
                                        cost = Entrances.windowCost(square:getWindowTo(inside))
                                        climb = true
                                    end
                                    opening = opening or square:getWindowTo(inside) ~= nil
                                        or square:getWindowFrameTo(inside) ~= nil
                                end
                            end)
                            if not opening and not doorsOnly then
                                pcall(function()
                                    opening = square:getWindowThumpableTo(inside) ~= nil
                                    if opening then cost, climb = Entrances.cost.thumpable, true end
                                end)
                            end
                            if obstructed then opening = false end
                            if opening and Entrances.edgeRefused(square, inside) then
                                opening = false
                            end

                            if opening and climb and Entrances.landingBlocked(inside) then
                                opening = false
                            end
                            if opening and standable(square) then
                                found[#found + 1] = {
                                    x = x + 0.5, y = y + 0.5, z = floor,
                                    key = keyOf(x, y, floor),
                                    cost = cost,

                                    ix = x + step[1] + 0.5, iy = y + step[2] + 0.5,
                                    edgeKey = Entrances.edgeKeyOf(square, inside),
                                }
                            end
                        end
                    end
                end
            end
        end
    end)
    return found
end

function Entrances.windowGlassy(window)
    local traversal = ProjectALife.ObstacleTraversal
    if window == nil or traversal == nil or type(traversal.windowGlassy) ~= "function" then return false end
    return traversal.windowGlassy(window) == true
end

function Entrances.windowCost(window)
    if Entrances.windowGlassy(window) then return Entrances.cost.glassyWindow end
    return Entrances.cost.window
end

function Entrances.landingBlocked(inside)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.landingStatic) ~= "function" then return false end
    return traversal.landingStatic(inside) == true
end

function Entrances.dropFailed(openings, shell)
    local traversal = ProjectALife.ObstacleTraversal
    if shell == nil or traversal == nil or type(traversal.openingFailed) ~= "function"
            or type(traversal.nowMs) ~= "function" then
        return openings
    end
    local now = traversal.nowMs()
    for index = #openings, 1, -1 do
        local key = openings[index].edgeKey
        if key ~= nil and traversal.openingFailed(shell, key, now) then table.remove(openings, index) end
    end
    return openings
end

local function claimIsLive(entry, now)
    return entry ~= nil and now - (tonumber(entry.atMs) or 0)
        < Entrances.settings.ttlMs
end

function Entrances.release(actorUid)
    local key = Entrances.held[actorUid]
    if key == nil then return false end
    Entrances.held[actorUid] = nil
    local entry = Entrances.claims[key]
    if entry ~= nil and entry.uid == actorUid then
        Entrances.claims[key] = nil
        Entrances.metrics.releases = Entrances.metrics.releases + 1
    end
    return true
end

function Entrances.edgeKeyOf(square, inside)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.edgeKey) ~= "function" then return nil end
    return traversal.edgeKey(square, inside)
end

function Entrances.edgeBusy(edgeKey, shell, now)
    local traversal = ProjectALife.ObstacleTraversal
    if edgeKey == nil or traversal == nil or type(traversal.reservations) ~= "table" then return false end
    local lease = traversal.reservations[edgeKey]
    return type(lease) == "table" and lease.owner ~= shell
        and (tonumber(now) or 0) < (tonumber(lease.untilMs) or 0)
end

function Entrances.hash(text)
    local value = 0
    text = tostring(text or "")
    for index = 1, #text do
        value = (value * 31 + string.byte(text, index)) % 2147483647
    end
    return value
end

function Entrances.effectiveCost(opening, uid, shell, sx, sy, now)
    local cost = math.sqrt((opening.x - sx) ^ 2 + (opening.y - sy) ^ 2)
        + (tonumber(opening.cost) or 0)
    local entry = Entrances.claims[opening.key]
    if entry ~= nil and entry.uid == uid then
        cost = cost - Entrances.settings.keepBonus
    elseif claimIsLive(entry, now) then
        cost = cost + Entrances.settings.sharedCost
    end
    if Entrances.edgeBusy(opening.edgeKey, shell, now) then
        cost = cost + Entrances.settings.busyEdgeCost
        Entrances.metrics.busyCosted = (Entrances.metrics.busyCosted or 0) + 1
    end
    return cost
end

function Entrances.claim(actor, shell, building, suppliedNow, doorsOnly)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then return nil end
    local now = tonumber(suppliedNow) or nowMs()
    local sx, sy, sz = 0, 0, 0
    local read = pcall(function()
        sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
    end)
    if not read then return nil end

    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.keptOutOf) == "function" and traversal.keptOutOf(shell, building) then
        return nil
    end
    local openings = Entrances.openings(building, sx, sy, sz, actor, doorsOnly)
    Entrances.dropFailed(openings, shell)
    if #openings == 0 then return nil end

    local costs = {}
    for index = 1, #openings do
        local opening = openings[index]
        costs[opening] = Entrances.effectiveCost(opening, actor.uid, shell, sx, sy, now)
    end
    table.sort(openings, function(left, right) return costs[left] < costs[right] end)

    local best = openings[1]
    local entry = Entrances.claims[best.key]
    if entry ~= nil and entry.uid == actor.uid then

        entry.atMs = now
        Entrances.held[actor.uid] = best.key
        return best, "held"
    end
    if not claimIsLive(entry, now) then
        local mine = Entrances.held[actor.uid]
        if mine ~= nil and mine ~= best.key then
            Entrances.release(actor.uid)
            Entrances.metrics.switched = (Entrances.metrics.switched or 0) + 1
        end
        Entrances.claims[best.key] = { uid = actor.uid, atMs = now }
        Entrances.held[actor.uid] = best.key
        Entrances.metrics.claims = Entrances.metrics.claims + 1
        return best, "claimed"
    end

    local band, own, free = 0, nil, nil
    for index = 1, #openings do
        local opening = openings[index]
        if costs[opening] > costs[best] + Entrances.settings.shareBand then break end
        band = index
        local claimed = Entrances.claims[opening.key]
        if claimed ~= nil and claimed.uid == actor.uid then
            own = own or opening
        elseif free == nil and not claimIsLive(claimed, now) then
            free = opening
        end
    end
    if own ~= nil then
        Entrances.claims[own.key].atMs = now
        Entrances.held[actor.uid] = own.key
        return own, "held"
    end
    if free ~= nil then
        if Entrances.held[actor.uid] ~= nil then
            Entrances.release(actor.uid)
            Entrances.metrics.switched = (Entrances.metrics.switched or 0) + 1
        end
        Entrances.claims[free.key] = { uid = actor.uid, atMs = now }
        Entrances.held[actor.uid] = free.key
        Entrances.metrics.claims = Entrances.metrics.claims + 1
        return free, "claimed"
    end
    Entrances.release(actor.uid)
    local pick = openings[(Entrances.hash(actor.uid) % math.max(1, band)) + 1]
    Entrances.metrics.shared = Entrances.metrics.shared + 1
    if pick ~= best then Entrances.metrics.spread = (Entrances.metrics.spread or 0) + 1 end
    return pick, "shared"
end

function Entrances.claimFor(shell, tx, ty, tz, opts)
    opts = type(opts) == "table" and opts or {}
    if shell == nil or tonumber(tx) == nil or tonumber(ty) == nil then return nil end
    local ok, sx, sy, sz = pcall(Entrances.positionOf, shell)
    if not ok or sx == nil then return nil end
    tz = tonumber(tz) or sz
    if math.abs(sz - tz) >= 0.4 then return nil end
    local actor = opts.actor
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then
        local policy = ProjectALife.DoorPolicy
        actor = policy ~= nil and type(policy.actorOf) == "function" and policy.actorOf(shell) or nil
        if (type(actor) ~= "table" or type(actor.uid) ~= "string") and type(opts.uid) == "string" then
            actor = { uid = opts.uid }
        end
    end
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then return nil end
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return nil end
    local here = cell:getGridSquare(math.floor(sx), math.floor(sy), math.floor(sz))
    local there = cell:getGridSquare(math.floor(tx), math.floor(ty), math.floor(tz))
    if here == nil or there == nil then return nil end
    local fromBuilding, toBuilding = here:getBuilding(), there:getBuilding()
    if fromBuilding == toBuilding then return nil end
    local exit = toBuilding == nil
    local building = exit and fromBuilding or toBuilding
    local opening, status = Entrances.claim(actor, shell, building, opts.now, opts.doorsOnly == true)
    if opening == nil then return nil end
    local leg = { z = opening.z, edgeKey = opening.edgeKey, key = opening.key,
        cost = opening.cost, status = status, exit = exit }
    if exit and opening.ix ~= nil then
        leg.x, leg.y, leg.crossX, leg.crossY = opening.ix, opening.iy, opening.x, opening.y
    else
        leg.x, leg.y, leg.crossX, leg.crossY = opening.x, opening.y, opening.ix, opening.iy
    end
    return leg
end

function Entrances.positionOf(shell)
    return shell:getX(), shell:getY(), shell:getZ()
end

function Entrances.tick(suppliedNow)
    local now = tonumber(suppliedNow) or nowMs()
    local dropped = 0
    for key, entry in pairs(Entrances.claims) do
        if not claimIsLive(entry, now) then
            Entrances.claims[key] = nil
            if entry ~= nil and Entrances.held[entry.uid] == key then
                Entrances.held[entry.uid] = nil
            end
            dropped = dropped + 1
        end
    end
    Entrances.mapTick(now, Entrances.mapSettings.sliceSquares)
    return dropped
end

function Entrances.reset()
    Entrances.claims = {}
    Entrances.held = {}
    Entrances.mapSites, Entrances.mapCount = {}, 0
end

Entrances.mapSites, Entrances.mapCount = {}, 0
Entrances.mapSettings = {
    siteCap = 64,
    querySquares = 256,
    sliceSquares = 64,
    siteMs = 120000,
    entryMs = 3000,

    entryCap = 32,
    entryScanCap = 256,
}

Entrances.mapCost = { open = 0, shut = 2, window = 6, frame = 6, glassy = 14, thumpable = 18 }

Entrances.passable = { open = true, shut = true, window = true }
Entrances.steps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Entrances.mapSite(building, z, now, budget, fx, fy)
    if building == nil or type(building.getDef) ~= "function" then return nil end
    local definition = building:getDef()
    if definition == nil then return nil end
    z = math.floor(tonumber(z) or 0)
    local x1, y1 = definition:getX(), definition:getY()
    local x2, y2 = definition:getX2(), definition:getY2()
    local key = x1 .. ":" .. y1 .. ":" .. x2 .. ":" .. y2 .. ":" .. z
    local settings = Entrances.mapSettings
    local site = Entrances.mapSites[key]
    if site == nil then
        if Entrances.mapCount >= settings.siteCap then Entrances.dropSite() end
        site = { key = key, x1 = x1 - 1, y1 = y1 - 1, x2 = x2 + 1, y2 = y2 + 1, z = z,
            cursor = 0, done = false, entries = {}, count = 0, scannedAtMs = now }
        Entrances.mapSites[key] = site
        Entrances.mapCount = Entrances.mapCount + 1
    elseif site.done and (now < site.scannedAtMs or now - site.scannedAtMs >= settings.siteMs) then
        site.done, site.cursor = false, 0
    end
    site.building, site.lastUseMs = building, now
    if tonumber(fx) ~= nil and tonumber(fy) ~= nil then site.fx, site.fy = fx, fy end
    if not site.done then Entrances.scanSite(site, tonumber(budget) or settings.querySquares, now) end
    return site
end

function Entrances.dropSite()
    local oldest, oldestMs = nil, nil
    for key, site in pairs(Entrances.mapSites) do
        if oldestMs == nil or (site.lastUseMs or 0) < oldestMs then oldest, oldestMs = key, site.lastUseMs or 0 end
    end
    if oldest ~= nil then
        Entrances.mapSites[oldest] = nil
        Entrances.mapCount = Entrances.mapCount - 1
    end
end

function Entrances.scanSite(site, budget, now)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or site.building == nil then return 0 end
    local width = site.x2 - site.x1 + 1
    local total = width * (site.y2 - site.y1 + 1)
    if site.cursor == 0 then site.passMs, site.partial = now, false end
    local read, steps = 0, Entrances.steps
    while site.cursor < total and read < budget do
        local x = site.x1 + site.cursor % width
        local y = site.y1 + math.floor(site.cursor / width)
        site.cursor, read = site.cursor + 1, read + 1
        local square = cell:getGridSquare(x, y, site.z)
        if square == nil then
            site.partial = true
        elseif square:getBuilding() ~= site.building then
            for index = 1, 4 do
                local tx, ty = x + steps[index][1], y + steps[index][2]
                if tx > site.x1 and tx < site.x2 and ty > site.y1 and ty < site.y2 then
                    local inside = cell:getGridSquare(tx, ty, site.z)
                    if inside ~= nil and inside:getBuilding() == site.building then
                        Entrances.noteEntry(site, square, inside, now)
                    end
                end
            end
        end
    end
    if site.cursor >= total then
        site.done, site.scannedAtMs = true, now
        for edgeKey, entry in pairs(site.entries) do
            if (entry.scanMs or 0) < site.passMs then
                site.entries[edgeKey] = nil
                site.count = site.count - 1
            end
        end
        Entrances.capSite(site)
    end
    return read
end

function Entrances.capSite(site)
    local cap = Entrances.mapSettings.entryCap
    if site.count <= cap then return end
    local fx, fy = site.fx, site.fy
    if fx == nil or fy == nil then fx, fy = (site.x1 + site.x2) / 2, (site.y1 + site.y2) / 2 end
    local ranked = {}
    for _, entry in pairs(site.entries) do
        local climb = 0
        if entry.glassy == true then
            climb = Entrances.mapCost.glassy
        elseif entry.kind ~= "door" then
            climb = Entrances.mapCost.window
        end
        entry.rank = math.sqrt((entry.sx + 0.5 - fx) ^ 2 + (entry.sy + 0.5 - fy) ^ 2) + climb
        ranked[#ranked + 1] = entry
    end
    table.sort(ranked, function(a, b) return a.rank < b.rank end)
    for index = cap + 1, #ranked do site.entries[ranked[index].edgeKey] = nil end
    site.count = cap
end

function Entrances.noteEntry(site, outside, inside, now)
    local edgeKey = Entrances.edgeKeyOf(outside, inside)
    if edgeKey == nil then return nil end
    local entry = site.entries[edgeKey]
    local fresh = entry == nil
    if fresh then
        if site.count >= Entrances.mapSettings.entryScanCap then return nil end
        entry = { edgeKey = edgeKey, sx = outside:getX(), sy = outside:getY(),
            ix = inside:getX(), iy = inside:getY(), z = site.z }
    end
    if not Entrances.readEntry(entry, outside, inside, now) then
        if not fresh then
            site.entries[edgeKey] = nil
            site.count = site.count - 1
        end
        return nil
    end
    entry.scanMs = now
    if fresh then
        site.entries[edgeKey] = entry
        site.count = site.count + 1
    end
    return entry
end

function Entrances.readEntry(entry, outside, inside, now)
    local policy = ProjectALife.DoorPolicy
    local traversal = ProjectALife.ObstacleTraversal
    local kind, state, stateIn, glassy
    local door
    if type(outside.getDoorTo) == "function" then door = outside:getDoorTo(inside) end
    if door ~= nil then
        kind = "door"
        if policy.ask(door, "IsOpen") == true then
            state = "open"
        elseif policy.ask(door, "isObstructed") == true then
            state = "obstructed"
        elseif policy.ask(door, "isBarricaded") == true then
            state = "barricaded"
        else
            state = "shut"
            if policy.lockKind(door, outside) ~= nil or policy.groupLocked(door, outside) then state = "locked" end
            stateIn = "shut"
            if policy.lockKind(door, inside) ~= nil or policy.groupLocked(door, inside) then stateIn = "locked" end
        end
    else
        local window
        if type(outside.getWindowTo) == "function" then window = outside:getWindowTo(inside) end
        if window ~= nil then
            kind = "window"
        elseif type(outside.getWindowFrameTo) == "function" and outside:getWindowFrameTo(inside) ~= nil then
            kind = "frame"
        elseif type(outside.getWindowThumpableTo) == "function" then
            window = outside:getWindowThumpableTo(inside)
            if window ~= nil then kind = "thumpable" end
        end
        if kind == nil then return false end
        state = "window"
        if window ~= nil and policy.ask(window, "isBarricaded") == true then
            state = "barricaded"
        elseif window ~= nil and traversal ~= nil and traversal.windowInvincible(window) then
            state = "invincible"
        elseif kind == "window" then
            glassy = Entrances.windowGlassy(window) or nil
        end
    end
    stateIn = stateIn or state
    entry.glassy = glassy

    if traversal ~= nil then
        if Entrances.passable[state] and not traversal.detourWalkable(inside) then state = "landing_blocked" end
        if Entrances.passable[stateIn] and not traversal.detourWalkable(outside) then stateIn = "landing_blocked" end
    end
    entry.kind, entry.state, entry.stateIn, entry.readAtMs = kind, state, stateIn, now
    return true
end

function Entrances.rereadEntry(entry, now)
    local cell = type(getCell) == "function" and getCell() or nil
    local outside = cell ~= nil and cell:getGridSquare(entry.sx, entry.sy, entry.z) or nil
    local inside = cell ~= nil and cell:getGridSquare(entry.ix, entry.iy, entry.z) or nil
    if outside == nil or inside == nil then
        entry.state, entry.stateIn, entry.readAtMs = "stale", "stale", 0
        return false
    end
    if Entrances.readEntry(entry, outside, inside, now) then return true end
    entry.kind, entry.state, entry.readAtMs = "door", "none", now
    if type(outside.isBlockedTo) == "function" and outside:isBlockedTo(inside) ~= true then entry.state = "open" end
    entry.stateIn = entry.state
    return true
end

function Entrances.entryCost(entry, state, climbs)
    if entry.kind == "door" then
        if state == "open" or state == "shut" then return Entrances.mapCost[state] end
        return nil
    end
    if state ~= "window" or climbs ~= true then return nil end
    if entry.glassy == true then return Entrances.mapCost.glassy end
    return Entrances.mapCost[entry.kind]
end

function Entrances.ringPos(site, x, y)
    local w, h = site.x2 - site.x1, site.y2 - site.y1
    x = math.max(site.x1, math.min(site.x2, math.floor(x)))
    y = math.max(site.y1, math.min(site.y2, math.floor(y)))
    local north, south, west, east = y - site.y1, site.y2 - y, x - site.x1, site.x2 - x
    local nearest = math.min(north, south, west, east)
    local at
    if nearest == north then
        at = x - site.x1
    elseif nearest == east then
        at = w + (y - site.y1)
    elseif nearest == south then
        at = w + h + (site.x2 - x)
    else
        at = 2 * w + h + (site.y2 - y)
    end
    return at, 2 * (w + h)
end

function Entrances.ringRoute(site, sx, sy, tx, ty)
    local route = {}
    local from, length = Entrances.ringPos(site, sx, sy)
    local to = Entrances.ringPos(site, tx, ty)
    if length <= 0 or from == to then return route end
    local w, h = site.x2 - site.x1, site.y2 - site.y1

    local clockwise = ((to - from) % length + length) % length
    local forward = clockwise <= length - clockwise
    local span = clockwise
    if not forward then span = length - clockwise end
    local marks = { 0, w, w + h, 2 * w + h }
    local cx = { site.x1, site.x2, site.x2, site.x1 }
    local cy = { site.y1, site.y1, site.y2, site.y2 }
    local ox, oy = { -1, 1, 1, -1 }, { -1, -1, 1, 1 }
    local picks = {}
    for index = 1, 4 do
        local along = ((marks[index] - from) % length + length) % length
        if not forward then along = ((from - marks[index]) % length + length) % length end
        if along > 0 and along < span then picks[#picks + 1] = { along = along, index = index } end
    end
    table.sort(picks, function(a, b) return a.along < b.along end)
    for _, pick in ipairs(picks) do
        local index = pick.index
        local x, y = Entrances.ringCorner(site, cx[index], cy[index], ox[index], oy[index])
        if x ~= nil then route[#route + 1] = { x = x + 0.5, y = y + 0.5, z = site.z } end
    end
    return route
end

function Entrances.ringCorner(site, x, y, ox, oy)
    local cell = type(getCell) == "function" and getCell() or nil
    local traversal = ProjectALife.ObstacleTraversal
    if cell == nil or traversal == nil then return nil end
    for step = 0, 1 do
        local square = cell:getGridSquare(x + ox * step, y + oy * step, site.z)
        if square ~= nil and square:getBuilding() == nil and traversal.detourWalkable(square) then
            return x + ox * step, y + oy * step
        end
    end
    return nil
end

function Entrances.bestEntry(site, shell, refusedKey, doorsOnly, leaving, sx, sy, now)
    local traversal = ProjectALife.ObstacleTraversal
    local climbs = doorsOnly ~= true and not traversal.climbOverBudget(shell, now)
    local from, length = Entrances.ringPos(site, sx, sy)
    local best, bestCost
    for edgeKey, entry in pairs(site.entries) do
        if edgeKey ~= refusedKey and (tonumber(traversal.edgeBans[edgeKey]) or 0) <= now
                and not traversal.openingFailed(shell, edgeKey, now)
                and not traversal.shellBanned(shell, edgeKey, now) then
            if now < (entry.readAtMs or 0) or now - (entry.readAtMs or 0) >= Entrances.mapSettings.entryMs then
                Entrances.rereadEntry(entry, now)
            end
            local state = entry.state
            if leaving then state = entry.stateIn end
            local cost = Entrances.entryCost(entry, state, climbs)
            if cost ~= nil then
                if leaving then
                    cost = cost + math.sqrt((entry.ix + 0.5 - sx) ^ 2 + (entry.iy + 0.5 - sy) ^ 2)
                else
                    local around = math.abs(Entrances.ringPos(site, entry.sx, entry.sy) - from)
                    cost = cost + math.min(around, length - around)
                end
                if bestCost == nil or cost < bestCost then best, bestCost = entry, cost end
            end
        end
    end
    return best
end

function Entrances.wayRound(shell, edgeKey, goal, doorsOnly, now)
    local traversal = ProjectALife.ObstacleTraversal
    if shell == nil or traversal == nil or type(getCell) ~= "function" then return nil end
    local x1, y1, x2, y2, z = traversal.edgeEnds(edgeKey)
    local cell = getCell()
    if x1 == nil or cell == nil then return nil end
    now = tonumber(now) or nowMs()
    local near, far = cell:getGridSquare(x1, y1, z), cell:getGridSquare(x2, y2, z)
    if near == nil or far == nil then return nil end
    local sx, sy = shell:getX(), shell:getY()
    if (sx - x2 - 0.5) ^ 2 + (sy - y2 - 0.5) ^ 2 < (sx - x1 - 0.5) ^ 2 + (sy - y1 - 0.5) ^ 2 then
        near, far = far, near
    end
    local building, leaving = far:getBuilding(), false
    if building == near:getBuilding() then return nil end
    if building == nil then building, leaving = near:getBuilding(), true end
    local site = Entrances.mapSite(building, z, now, nil, sx, sy)
    if site == nil then return nil end
    local gx, gy
    if type(goal) == "table" then gx, gy = tonumber(goal.x), tonumber(goal.y) end
    local goalIn = false
    if gx ~= nil and gy ~= nil then
        local square = cell:getGridSquare(math.floor(gx), math.floor(gy), z)
        goalIn = square ~= nil and square:getBuilding() == building
    end
    if not leaving and not goalIn then
        if gx == nil or gy == nil then return nil end
        local round = Entrances.ringRoute(site, sx, sy, gx, gy)
        if round[1] == nil then return nil end
        Entrances.metrics.mapRounds = (Entrances.metrics.mapRounds or 0) + 1
        return round
    end
    if leaving and goalIn then return nil end

    if not leaving and traversal.keptOutOf(shell, building, now) then return nil, true end
    local detour = traversal.detourRoute(shell, edgeKey, doorsOnly == true)
    if detour ~= nil then return detour, true end
    local entry = Entrances.bestEntry(site, shell, edgeKey, doorsOnly, leaving, sx, sy, now)
    if entry == nil then
        Entrances.metrics.mapMisses = (Entrances.metrics.mapMisses or 0) + 1
        return nil, true
    end
    Entrances.metrics.mapWays = (Entrances.metrics.mapWays or 0) + 1
    local outside = { x = entry.sx + 0.5, y = entry.sy + 0.5, z = z }
    local inside = { x = entry.ix + 0.5, y = entry.iy + 0.5, z = z }
    if leaving then return { inside, outside }, true end
    local route = Entrances.ringRoute(site, sx, sy, outside.x, outside.y)
    route[#route + 1] = outside
    route[#route + 1] = inside
    if traversal.detourWalkable(far) then
        route[#route + 1] = { x = far:getX() + 0.5, y = far:getY() + 0.5, z = z }
    end
    return route, true
end

function Entrances.mapTick(now, budget)
    for _, site in pairs(Entrances.mapSites) do
        if not site.done then return Entrances.scanSite(site, budget, now) end
    end
    return 0
end

return Entrances
