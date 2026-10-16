require "ProjectALife/Movement/ALifeEntrances"

ProjectALife = ProjectALife or {}

local Door = {
    settings = {
        scanBudget = 200,
        debugBudget = 6000,
        roadSnap = 20,
        gateReach = 12,
        fenceSteps = 40,
        streetTiles = 10,
        porchTiles = 2,
        mailboxTiles = 10,
        staleHours = 24,
        doorsKept = 32,
        windowsKept = 6,
        windowCost = 12,
        scatterRing = 4,
        scatterMaxRing = 7,
        scatterPerSquare = 2,
        traceCap = 24,
        traceDays = 10,
        standRing = 4,
        standSquares = 64,
        reachRetries = 3,
    },
    jobs = {},
    adapters = {},
    metrics = {},
}
ProjectALife.SafehouseDoor = Door

function Door.freshMetrics()
    return { evaluations = 0, placed = 0, refused = 0, readBackFailed = 0, windowsMapped = 0, windowSpots = 0,
        tracesPlaced = 0, traceSquares = 0, tracesRemoved = 0, traceRefused = 0 }
end
Door.metrics = Door.freshMetrics()

function Door.reset()
    Door.jobs = {}
    Door.adapters = {}
    Door.metrics = Door.freshMetrics()
end

function Door.ask(object, name, a, b)
    if object == nil then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end
    local ok, value
    if b ~= nil then
        ok, value = pcall(method, object, a, b)
    elseif a ~= nil then
        ok, value = pcall(method, object, a)
    else
        ok, value = pcall(method, object)
    end
    if not ok then return nil end
    return value
end

function Door.nowMs()
    if type(Door.adapters.nowMs) == "function" then return Door.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Door.cell()
    if type(Door.adapters.cell) == "function" then return Door.adapters.cell() end
    if type(getCell) ~= "function" then return nil end
    return getCell()
end

function Door.square(x, y, z)
    local cell = Door.cell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(z) or 0))
end

function Door.outside(square)
    return square ~= nil and Door.ask(square, "getRoom") == nil and Door.ask(square, "getBuilding") == nil
end

function Door.walkable(square)
    if square == nil then return false end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.detourWalkable) == "function" then
        return traversal.detourWalkable(square) == true
    end
    if type(square.isFree) == "function" then return square:isFree(false) == true end
    return Door.ask(square, "TreatAsSolidFloor") == true
end

function Door.inBox(house, x, y)
    return x >= house.x1 and x < house.x2 and y >= house.y1 and y < house.y2
end

function Door.reach(x, y, z)
    local spawn = ProjectALife.SpawnPolicy
    if spawn ~= nil and type(spawn.reachVerdict) == "function" then
        local ok, verdict, why = pcall(spawn.reachVerdict, { x = x, y = y, z = z })
        if ok and type(verdict) == "string" then
            if verdict == "unknown" and why == "large" and Door.outside(Door.square(x, y, z)) then return "open" end
            return verdict
        end
    end
    local square = Door.square(x, y, z)
    if square == nil then return "unknown" end
    if not Door.outside(square) or not Door.walkable(square) then return "sealed" end
    return "open"
end

function Door.reachable(verdict)
    return verdict == "open" or verdict == "plain"
end

function Door.enclosed(x, y, z, memo)
    if type(Door.adapters.enclosed) == "function" then return Door.adapters.enclosed(x, y, z) == true end
    local spawn = ProjectALife.SpawnPolicy
    if spawn == nil or type(spawn.enclosedByPlayerBuild) ~= "function" then return false end
    return spawn.enclosedByPlayerBuild({ x = x, y = y, z = z }, nil, memo) == true
end

function Door.blocker(square)
    if Door.ask(square, "isSolid") == true or Door.ask(square, "isSolidTrans") == true then return "solid_object" end
    if Door.ask(square, "HasStairs") == true then return "stairs" end
    if Door.ask(square, "TreatAsSolidFloor") ~= true then return "no_floor" end
    return "tree_or_obstacle"
end

function Door.occupants(square, radius)
    local players, others = 0, 0
    if square == nil then return players, others end
    local x, y, z = tonumber(Door.ask(square, "getX")), tonumber(Door.ask(square, "getY")), tonumber(Door.ask(square, "getZ")) or 0
    if x == nil or y == nil then return players, others end
    radius = math.max(0, math.floor(tonumber(radius) or 0))
    for dx = -radius, radius do
        for dy = -radius, radius do
            local near = Door.square(x + dx, y + dy, z)
            local objects = near ~= nil and Door.ask(near, "getMovingObjects") or nil
            local count = objects ~= nil and tonumber(Door.ask(objects, "size")) or 0
            for index = 0, math.min(count, 16) - 1 do
                local object = objects:get(index)
                if type(instanceof) == "function" and instanceof(object, "IsoPlayer") then
                    players = players + 1
                elseif type(instanceof) == "function" and instanceof(object, "IsoZombie") then
                    others = others + 1
                end
            end
        end
    end
    return players, others
end

function Door.verdict(square, options)
    if square == nil then return false, "square_unloaded" end
    if Door.ask(square, "getRoom") ~= nil then return false, "inside_a_room" end
    if Door.ask(square, "getBuilding") ~= nil then return false, "inside_a_building" end
    options = type(options) == "table" and options or {}
    local x = tonumber(Door.ask(square, "getX")) or tonumber(options.x)
    local y = tonumber(Door.ask(square, "getY")) or tonumber(options.y)
    if x == nil or y == nil then return false, "square_unloaded" end
    local z = tonumber(Door.ask(square, "getZ")) or 0
    if z ~= 0 then return false, "not_ground_level" end
    if type(square.isFree) == "function" and Door.ask(square, "isFree", false) ~= true then
        return false, Door.blocker(square)
    end
    if not Door.walkable(square) then return false, "water_or_solid" end
    if Door.ask(square, "getVehicleContainer") ~= nil then return false, "vehicle_on_square" end
    if options.occupied == true and type(square.isFree) == "function" and Door.ask(square, "isFree", true) ~= true then
        local players = Door.occupants(square, 0)
        if players > 0 then return false, "player_on_square" end
        return false, "occupied"
    end
    if Door.enclosed(x, y, z, options.memo) then return false, "inside_player_yard" end
    local reach = Door.reach(x, y, z)
    if reach == "sealed" then return false, "sealed_pocket" end
    if reach == "unknown" then return true, nil, "reach_unknown" end
    return true, nil, nil
end

function Door.passable(from, to)
    if from == nil or to == nil then return false end
    if Door.ask(from, "isBlockedTo", to) == true then return false end
    return true
end

function Door.reasonText(reasons)
    local names = {}
    for name in pairs(type(reasons) == "table" and reasons or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if reasons[a] ~= reasons[b] then return reasons[a] > reasons[b] end
        return a < b
    end)
    local parts = {}
    for index = 1, math.min(#names, 4) do parts[#parts + 1] = reasons[names[index]] .. "x " .. names[index] end
    if #parts == 0 then return "nothing to try" end
    return table.concat(parts, ", ")
end

function Door.isGarage(door)
    if door == nil or IsoDoor == nil then return false end
    local policy = ProjectALife.DoorPolicy
    local fn = IsoDoor.getGarageDoorIndex
    if policy == nil or type(policy.callStatic) ~= "function" then return false end
    local index = tonumber(policy.callStatic(fn, door))
    return index ~= nil and index >= 0
end

function Door.entryDoor(entry)
    local outside = Door.square(entry.sx, entry.sy, entry.z)
    local inside = Door.square(entry.ix, entry.iy, entry.z)
    if outside == nil or inside == nil then return nil end
    return Door.ask(outside, "getDoorTo", inside)
end

function Door.roadDistance(x, y)
    local cap = Door.settings.roadSnap
    if type(Door.adapters.roadDistance) == "function" then return math.min(cap, Door.adapters.roadDistance(x, y)) end
    local graph = ProjectALife.RoadGraph
    if graph == nil or type(graph.snapToRoad) ~= "function" then return cap end
    local ok, first, second = pcall(graph.snapToRoad, x, y, cap)
    if not ok then return cap end
    local rx, ry = tonumber(first), tonumber(second)
    if type(first) == "table" then rx, ry = tonumber(first.x), tonumber(first.y) end
    if rx == nil or ry == nil then return cap end
    return math.min(cap, math.sqrt((rx - x) * (rx - x) + (ry - y) * (ry - y)))
end

function Door.isRoad(square)
    if type(Door.adapters.isRoad) == "function" then return Door.adapters.isRoad(square) == true end
    local roads = ProjectALife.Road
    if roads == nil or type(roads.isRoadSquare) ~= "function" then return false end
    local ok, road = pcall(roads.isRoadSquare, square)
    return ok and road == true
end

function Door.rank(house, site)
    local ranked = {}
    local passes = type(house.passes) == "table" and house.passes or {}
    local entrances = ProjectALife.Entrances
    for edgeKey, entry in pairs(site.entries or {}) do
        if entry.kind == "door" and not Door.isGarage(Door.entryDoor(entry)) then
            local parts = {
                base = 100,
                passes = math.min(40, 2 * (tonumber(passes[edgeKey]) or 0)),
                road = math.max(0, math.floor(20 - Door.roadDistance(entry.sx, entry.sy))),
                state = 0,
            }
            if entry.state == "barricaded" then parts.state = -60 elseif entry.state == "obstructed" then parts.state = -40 end
            local ring = 0
            if entrances ~= nil and type(entrances.ringPos) == "function" then ring = entrances.ringPos(site, entry.sx, entry.sy) end
            ranked[#ranked + 1] = { edgeKey = edgeKey, entry = entry, parts = parts,
                score = parts.base + parts.passes + parts.road + parts.state,
                verdict = Door.reach(entry.sx, entry.sy, entry.z), ring = ring }
        end
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.ring ~= b.ring then return a.ring < b.ring end
        return a.edgeKey < b.edgeKey
    end)
    return ranked
end

function Door.buildingOf(house)
    if type(Door.adapters.buildingOf) == "function" then return Door.adapters.buildingOf(house) end
    local z = math.floor(tonumber(house.z) or 0)
    local points = { { house.cx, house.cy }, { (house.x1 + house.x2) / 2, (house.y1 + house.y2) / 2 } }
    for index = 1, #points do
        local x, y = tonumber(points[index][1]), tonumber(points[index][2])
        if x ~= nil and y ~= nil then
            local building = Door.ask(Door.square(x, y, z), "getBuilding")
            if building ~= nil then return building end
        end
    end
    local first, reads = nil, 0
    for x = math.floor(house.x1), math.floor(house.x2) - 1, 2 do
        for y = math.floor(house.y1), math.floor(house.y2) - 1, 2 do
            reads = reads + 1
            if reads > 900 then return first end
            local building = Door.ask(Door.square(x, y, z), "getBuilding")
            if building ~= nil then
                local def = Door.ask(building, "getDef")
                if def ~= nil and tonumber(Door.ask(def, "getX")) == house.x1 and tonumber(Door.ask(def, "getY")) == house.y1
                        and tonumber(Door.ask(def, "getX2")) == house.x2 and tonumber(Door.ask(def, "getY2")) == house.y2 then
                    return building
                end
                first = first or building
            end
        end
    end
    return first
end

function Door.stale(house, now)
    local door = type(house) == "table" and house.door or nil
    if type(door) ~= "table" then return true, "never_evaluated" end
    if door.stale == true then return true, "marked_stale" end
    if now < (tonumber(door.atHours) or 0) or now - (tonumber(door.atHours) or 0) >= Door.settings.staleHours then
        return true, "older_than_" .. Door.settings.staleHours .. "h"
    end
    local heat = ProjectALife.BaseHeat
    if heat ~= nil and heat.homesVersion ~= nil and door.sig ~= tostring(heat.homesVersion) then
        return true, "anchors_changed"
    end
    return false, nil
end

function Door.job(house)
    return Door.jobs[house.key]
end

function Door.evaluate(house, now, budget, restart)
    local job = Door.jobs[house.key]
    if job == nil or restart == true then
        job = { phase = "site", startedHours = now, cursor = 0 }
        Door.jobs[house.key] = job
    end
    budget = math.max(1, math.floor(tonumber(budget) or Door.settings.scanBudget))
    job.budget = budget
    local spent, guard = 0, 0
    while job.phase ~= "done" and spent < budget and guard < 24 do
        guard = guard + 1
        local used, stop = Door.step(house, job, now, budget - spent)
        spent = spent + math.max(1, used or 0)
        if stop then break end
    end
    if job.phase == "done" then
        Door.jobs[house.key] = nil
        Door.metrics.evaluations = Door.metrics.evaluations + 1
        return true, "done"
    end
    return false, job.status or job.phase
end

function Door.step(house, job, now, budget)
    if job.phase == "site" then return Door.stepSite(house, job, now, budget) end
    if job.phase == "gate" then return Door.stepGate(house, job, budget) end
    if job.phase == "fence" then return Door.stepFence(house, job) end
    if job.phase == "street" then return Door.stepStreet(house, job, budget) end
    if job.phase == "mailbox" then return Door.stepMailbox(house, job, budget) end
    if job.phase == "windows" then return Door.stepWindows(house, job, budget) end
    if job.phase == "finish" then Door.finish(house, job, now); return 1, false end
    return 1, true
end

function Door.windowItem(house, entry, stand, memo)
    local square = Door.square(entry.sx, entry.sy, entry.z)
    local ok = Door.verdict(square, { memo = memo, x = entry.sx, y = entry.sy })
    if not ok then return nil end
    local near = 0
    if stand ~= nil then near = math.sqrt((entry.sx - stand.x) ^ 2 + (entry.sy - stand.y) ^ 2) end
    local score = 100 + math.max(0, math.floor(20 - Door.roadDistance(entry.sx, entry.sy))) - math.min(30, math.floor(near))
    if entry.state == "barricaded" then score = score - 10 end
    return { edge = entry.edgeKey, x = entry.sx, y = entry.sy, z = entry.z, ix = entry.ix, iy = entry.iy,
        state = entry.state, score = score }
end

function Door.windowBetter(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.edge < b.edge
end

function Door.stepWindows(house, job, budget)
    local settings = Door.settings
    if job.windowQueue == nil then
        local queue = {}
        for _, entry in pairs(job.site and job.site.entries or {}) do
            if entry.kind == "window" then queue[#queue + 1] = entry end
        end
        local stand = job.stand
        table.sort(queue, function(a, b)
            local da, db = 0, 0
            if stand ~= nil then
                da = (a.sx - stand.x) ^ 2 + (a.sy - stand.y) ^ 2
                db = (b.sx - stand.x) ^ 2 + (b.sy - stand.y) ^ 2
            end
            if da ~= db then return da < db end
            return a.edgeKey < b.edgeKey
        end)
        job.windowQueue, job.windowAt, job.windows, job.windowMemo = queue, 0, {}, {}
    end
    local used, enough = 0, settings.windowsKept * 2
    while job.windowAt < #job.windowQueue and used < budget and #job.windows < enough do
        job.windowAt = job.windowAt + 1
        local item = Door.windowItem(house, job.windowQueue[job.windowAt], job.stand, job.windowMemo)
        if item ~= nil then job.windows[#job.windows + 1] = item end
        used = used + settings.windowCost
    end
    if job.windowAt >= #job.windowQueue or #job.windows >= enough then
        table.sort(job.windows, Door.windowBetter)
        while #job.windows > settings.windowsKept do table.remove(job.windows) end
        job.phase = "finish"
    end
    return math.max(used, 1), false
end

function Door.stepSite(house, job, now, budget)
    local building = Door.buildingOf(house)
    if building == nil then job.status = "house_unloaded"; return 1, true end
    local entrances = ProjectALife.Entrances
    if entrances == nil or type(entrances.mapSite) ~= "function" then job.status = "entrances_missing"; return 1, true end
    local site = entrances.mapSite(building, 0, Door.nowMs(), budget, house.cx, house.cy)
    if site == nil then job.status = "no_site"; return 1, true end
    if not site.done then job.status = "mapping"; return budget, true end
    job.site = site

    local read = 0
    for _, entry in pairs(site.entries or {}) do
        if entry.kind == "door" and type(entrances.rereadEntry) == "function" then
            entrances.rereadEntry(entry, Door.nowMs())
            read = read + 2
        end
    end
    job.ranked = Door.rank(house, site)
    job.chosen = nil
    local unsure = false
    for index = 1, #job.ranked do
        if Door.reachable(job.ranked[index].verdict) then job.chosen = job.ranked[index]; break end
        if job.ranked[index].verdict == "unknown" then unsure = true end
    end
    if job.chosen == nil and unsure and (tonumber(job.budget) or 0) <= Door.settings.scanBudget
            and (tonumber(job.reachTries) or 0) < Door.settings.reachRetries then
        job.reachTries = (tonumber(job.reachTries) or 0) + 1
        job.status = "reach_unknown"
        return 1 + read, true
    end
    job.cursor = 0
    if job.chosen == nil then
        job.mode, job.phase = "street", "street"
    else
        local entry = job.chosen.entry
        if Door.enclosed(entry.sx, entry.sy, entry.z) then
            job.mode, job.phase = "gate", "gate"
        else
            job.mode, job.phase = "door", "mailbox"
            job.stand = { x = entry.sx, y = entry.sy, z = entry.z }
        end
    end
    return 32 + read, false
end

function Door.boxSquares(house, job, grow, budget, visit)
    local x1, y1 = house.x1 - grow, house.y1 - grow
    local width, height = (house.x2 + grow) - x1, (house.y2 + grow) - y1
    local total = width * height
    local read = 0
    while job.cursor < total and read < budget do
        local x = x1 + job.cursor % width
        local y = y1 + math.floor(job.cursor / width)
        job.cursor, read = job.cursor + 1, read + 1
        visit(x, y)
    end
    return read, job.cursor >= total
end

function Door.gateOn(square)
    if square == nil or not Door.outside(square) then return nil end
    local objects = Door.ask(square, "getObjects")
    local count = objects ~= nil and tonumber(Door.ask(objects, "size")) or 0
    for index = 0, math.min(count, 32) - 1 do
        local object = objects:get(index)
        if type(instanceof) == "function" and (instanceof(object, "IsoDoor")
                or (instanceof(object, "IsoThumpable") and Door.ask(object, "isDoor") == true)) then
            return object
        end
    end
    return nil
end

function Door.stepGate(house, job, budget)
    local entry = job.chosen.entry
    local cx, cy = (house.x1 + house.x2) / 2, (house.y1 + house.y2) / 2
    local read, done = Door.boxSquares(house, job, Door.settings.gateReach, budget, function(x, y)
        local square = Door.square(x, y, entry.z)
        local gate = Door.gateOn(square)
        if gate == nil then return end
        local other = Door.ask(gate, "getOppositeSquare")

        if other == nil or Door.ask(other, "getBuilding") ~= nil then return end
        local far = square
        local d1 = (square:getX() - cx) ^ 2 + (square:getY() - cy) ^ 2
        local d2 = (other:getX() - cx) ^ 2 + (other:getY() - cy) ^ 2
        if d2 > d1 then far = other end
        if Door.enclosed(far:getX(), far:getY(), entry.z) or not Door.walkable(far) then return end
        local distance = (far:getX() - entry.sx) ^ 2 + (far:getY() - entry.sy) ^ 2
        if job.gate == nil or distance < job.gate.distance then
            job.gate = { x = far:getX(), y = far:getY(), z = entry.z, distance = distance }
        end
    end)
    if done then
        job.cursor = 0
        if job.gate ~= nil then
            job.stand = { x = job.gate.x, y = job.gate.y, z = job.gate.z }
            job.phase = "mailbox"
        else
            job.mode, job.phase, job.fenceStep = "fence", "fence", 0
        end
    end
    return read, false
end

function Door.stepFence(house, job)
    local entry = job.chosen.entry
    local dx, dy = entry.sx - entry.ix, entry.sy - entry.iy
    local memo = {}
    for _ = 1, 3 do
        job.fenceStep = (job.fenceStep or 0) + 1
        if job.fenceStep > Door.settings.fenceSteps then
            job.mode, job.phase, job.cursor = "street", "street", 0
            return 3, false
        end
        local x, y = entry.sx + dx * job.fenceStep, entry.sy + dy * job.fenceStep
        local square = Door.square(x, y, entry.z)
        if square ~= nil and Door.outside(square) and Door.walkable(square)
                and not Door.enclosed(x, y, entry.z, memo) then
            job.stand = { x = x, y = y, z = entry.z }
            job.phase, job.cursor = "mailbox", 0
            return 3, false
        end
    end
    return 3, false
end

function Door.stepStreet(house, job, budget)
    local grow, z = Door.settings.streetTiles, 0
    local read, done = Door.boxSquares(house, job, grow, budget, function(x, y)
        if Door.inBox(house, x, y) then return end
        local square = Door.square(x, y, z)
        if square == nil or not Door.outside(square) or not Door.walkable(square) then return end
        if not Door.isRoad(square) then return end
        local d = math.max(house.x1 - x, 0, x - house.x2 + 1) + math.max(house.y1 - y, 0, y - house.y2 + 1)
        if job.road == nil or d < job.road.d then job.road = { x = x, y = y, z = z, d = d } end
    end)
    if done then
        job.cursor = 0
        local stand = job.road
        if stand == nil and job.site ~= nil then
            for _, entry in pairs(job.site.entries or {}) do
                if entry.kind ~= "door" and Door.reachable(Door.reach(entry.sx, entry.sy, entry.z))
                        and not Door.enclosed(entry.sx, entry.sy, entry.z) then
                    stand = { x = entry.sx, y = entry.sy, z = entry.z }
                    break
                end
            end
        end
        if stand == nil then
            job.mode, job.phase, job.stand = "none", "finish", nil
        else
            job.stand = { x = stand.x, y = stand.y, z = stand.z }
            job.phase = "mailbox"
        end
    end
    return read, false
end

function Door.mailboxOn(square)
    if square == nil then return nil end
    local objects = Door.ask(square, "getObjects")
    local count = objects ~= nil and tonumber(Door.ask(objects, "size")) or 0
    for index = 0, math.min(count, 32) - 1 do
        local container = Door.ask(objects:get(index), "getContainer")
        if container ~= nil and Door.ask(container, "getType") == "postbox" then return container end
    end
    return nil
end

function Door.stepMailbox(house, job, budget)
    local stand = job.stand
    local r = Door.settings.mailboxTiles
    local width = 2 * r + 1
    local total = width * width
    local read = 0
    while job.cursor < total and read < budget do
        local x = stand.x - r + job.cursor % width
        local y = stand.y - r + math.floor(job.cursor / width)
        job.cursor, read = job.cursor + 1, read + 1
        local square = Door.square(x, y, stand.z)
        if Door.mailboxOn(square) ~= nil and Door.outside(square) and not Door.enclosed(x, y, stand.z) then
            local d = (x - stand.x) ^ 2 + (y - stand.y) ^ 2
            if job.mailbox == nil or d < job.mailbox.d then job.mailbox = { x = x, y = y, z = stand.z, d = d } end
        end
    end
    if job.cursor >= total then job.phase = "windows" end
    return read, false
end

function Door.regionAt(x, y)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" then return "unknown", nil end
    local ok, distance, town = pcall(regions.distanceToTown, { x = x, y = y })
    if not ok or tonumber(distance) == nil then return "unknown", nil end
    local name = type(town) == "table" and (town.name or town.id) or nil
    if distance <= 0 then return "town", name end
    if distance <= 300 then return "edge", name end
    return "country", name
end

function Door.finish(house, job, now)
    local heat = ProjectALife.BaseHeat
    local door = { mode = job.mode or "none", atHours = now, stale = false, keys = {}, ranked = {},
        sig = heat ~= nil and heat.homesVersion ~= nil and tostring(heat.homesVersion) or nil }
    if job.chosen ~= nil then
        local entry = job.chosen.entry
        door.edgeKey, door.sx, door.sy, door.ix, door.iy, door.z = job.chosen.edgeKey, entry.sx, entry.sy, entry.ix, entry.iy, entry.z
        door.state = entry.state
    end
    if job.stand ~= nil then door.stand = { x = job.stand.x, y = job.stand.y, z = job.stand.z } end
    if job.mailbox ~= nil then door.mailbox = { x = job.mailbox.x, y = job.mailbox.y, z = job.mailbox.z } end
    door.windows = job.windows or {}
    Door.metrics.windowsMapped = Door.metrics.windowsMapped + #door.windows
    for index = 1, math.min(#(job.ranked or {}), 4) do
        local item = job.ranked[index]
        door.ranked[index] = { edgeKey = item.edgeKey, score = item.score, verdict = item.verdict,
            state = item.entry.state, base = item.parts.base, passes = item.parts.passes,
            road = item.parts.road, penalty = item.parts.state }
    end
    local kept = 0
    for _, entry in pairs(job.site and job.site.entries or {}) do
        if entry.kind == "door" and kept < Door.settings.doorsKept then
            door.keys[entry.sx .. "," .. entry.sy] = entry.edgeKey
            door.keys[entry.ix .. "," .. entry.iy] = entry.edgeKey
            kept = kept + 1
        end
    end
    if door.stand ~= nil then door.region, door.town = Door.regionAt(door.stand.x, door.stand.y) end
    house.door = door
    job.phase = "done"
end

function Door.dropSafe(house, square)
    if square == nil then return false, "square_unloaded" end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    if Door.ask(square, "getRoom") ~= nil then return false, "inside_a_room" end
    if Door.ask(square, "getBuilding") ~= nil then return false, "inside_a_building" end
    if Door.inBox(house, x, y) then return false, "inside_the_house" end
    local spawn = ProjectALife.SpawnPolicy
    if spawn ~= nil and type(spawn.excludedRegionAt) == "function" and spawn.excludedRegionAt({ x = x, y = y }) ~= nil then
        return false, "excluded_region"
    end
    if Door.enclosed(x, y, z) then return false, "inside_the_yard" end
    local verdict = Door.reach(x, y, z)
    if not Door.reachable(verdict) then return false, "unreachable_" .. tostring(verdict) end
    return true, nil
end

function Door.itemSquare(square)
    return Door.ask(square, "isFree", false) ~= false and Door.ask(square, "getVehicleContainer") == nil
end

function Door.porchSquares(house)
    local stand = house.door and house.door.stand or nil
    if stand == nil then return {} end
    local result = {}
    local first = Door.square(stand.x, stand.y, stand.z)
    if first ~= nil and Door.ask(first, "TreatAsSolidFloor") ~= false and Door.walkable(first) and Door.itemSquare(first) then
        result[1] = first
    end
    local r = Door.settings.porchTiles
    for d = 1, r do
        for dx = -d, d do
            for dy = -d, d do
                if math.max(math.abs(dx), math.abs(dy)) == d then
                    local square = Door.square(stand.x + dx, stand.y + dy, stand.z)
                    if square ~= nil and Door.walkable(square) and not Door.isRoad(square) and Door.itemSquare(square) then
                        result[#result + 1] = square
                    end
                end
            end
        end
    end
    return result
end

function Door.inContainer(container, item)
    if type(container.contains) == "function" then
        local ok, present = pcall(container.contains, container, item)
        if ok and type(present) == "boolean" then return present end
        return nil
    end
    if type(container.containsID) == "function" and type(item.getID) == "function" then
        local idOk, id = pcall(item.getID, item)
        if not idOk then return nil end
        local ok, present = pcall(container.containsID, container, id)
        if ok and type(present) == "boolean" then return present end
    end
    return nil
end

function Door.worldObjects(square)
    if type(square.getWorldObjects) ~= "function" then return nil end
    local ok, objects = pcall(square.getWorldObjects, square)
    if not ok or objects == nil or type(objects.size) ~= "function" or type(objects.get) ~= "function" then return nil end
    local sized, count = pcall(objects.size, objects)
    if not sized or tonumber(count) == nil then return nil end
    return objects, tonumber(count)
end

function Door.onSquare(square, item)
    local objects, count = Door.worldObjects(square)
    if objects == nil then return nil end
    for index = 0, count - 1 do
        local got, object = pcall(objects.get, objects, index)
        if not got or object == nil or type(object.getItem) ~= "function" then return nil end
        local read, found = pcall(object.getItem, object)
        if not read then return nil end
        if found == item then return true end
    end
    return false
end

function Door.putInContainer(container, items)
    for index = 1, #items do
        local ok = type(container.AddItem) == "function" and pcall(container.AddItem, container, items[index])
        if not ok or not Door.inContainer(container, items[index]) then
            return false, Door.rollbackContainer(container, items)
        end
    end
    for index = 1, #items do
        if type(isServer) == "function" and isServer() and type(sendAddItemToContainer) == "function" then
            pcall(sendAddItemToContainer, container, items[index])
        end
    end
    for index = 1, #items do
        if not Door.inContainer(container, items[index]) then return false, Door.rollbackContainer(container, items) end
    end
    return true
end

function Door.putOnSquare(square, items, spread)
    if type(square.AddWorldInventoryItem) ~= "function" then return false end
    for index = 1, #items do
        local xoff, yoff = 0.3 + 0.2 * index, 0.5
        if type(spread) == "table" and type(spread[index]) == "table" then xoff, yoff = spread[index][1], spread[index][2] end
        local ok = pcall(square.AddWorldInventoryItem, square, items[index], xoff, yoff, 0)
        if not ok or not Door.onSquare(square, items[index]) then
            return false, Door.rollbackSquare(square, items)
        end
    end
    for index = 1, #items do
        if not Door.onSquare(square, items[index]) then return false, Door.rollbackSquare(square, items) end
    end
    return true
end

function Door.rollbackContainer(container, items)
    for _, item in ipairs(items) do
        local present = Door.inContainer(container, item)
        if present == nil then return false end
        if present then
            if type(container.Remove) == "function" then pcall(container.Remove, container, item) end
            if Door.inContainer(container, item) ~= false then return false end
            if type(isServer) == "function" and isServer() and type(sendRemoveItemFromContainer) == "function" then
                pcall(sendRemoveItemFromContainer, container, item)
            end
        end
    end
    return true
end

function Door.rollbackSquare(square, items)
    local objects, count = Door.worldObjects(square)
    if objects == nil then return false end
    for index = count - 1, 0, -1 do
        local got, object = pcall(objects.get, objects, index)
        if not got or object == nil or type(object.getItem) ~= "function" then return false end
        local read, found = pcall(object.getItem, object)
        if not read then return false end
        for _, item in ipairs(items) do
            if found == item and type(square.transmitRemoveItemFromSquare) == "function" then
                pcall(square.transmitRemoveItemFromSquare, square, object)
                break
            end
        end
    end
    for _, item in ipairs(items) do if Door.onSquare(square, item) ~= false then return false end end
    return true
end

function Door.recheck(house)
    local door = house.door
    local entrances = ProjectALife.Entrances
    if door.edgeKey == nil or entrances == nil or type(entrances.rereadEntry) ~= "function" then return false end
    local entry = { edgeKey = door.edgeKey, sx = door.sx, sy = door.sy, ix = door.ix, iy = door.iy, z = door.z }
    if not entrances.rereadEntry(entry, Door.nowMs()) then return false end
    if entry.state ~= door.state then
        door.stale = true
        return true
    end
    return false
end

function Door.place(house, items, dry)
    local refusals = {}
    local door = house.door
    if type(door) ~= "table" or door.stand == nil then return nil, "no_stand_square" end
    if dry ~= true then Door.recheck(house) end
    if door.mailbox ~= nil then
        local square = Door.square(door.mailbox.x, door.mailbox.y, door.mailbox.z)
        local ok, why = Door.dropSafe(house, square)
        local container = ok and Door.mailboxOn(square) or nil
        if container ~= nil then
            if dry == true then return { rank = "mailbox", x = square:getX(), y = square:getY(), z = square:getZ(), dry = true } end
            local added, clean = Door.putInContainer(container, items)
            if added then
                Door.metrics.placed = Door.metrics.placed + 1
                return { rank = "mailbox", x = square:getX(), y = square:getY(), z = square:getZ() }
            end
            if clean == false then return nil, "mailbox partial insertion; rollback failed", true end
        end
        if ok and container ~= nil then Door.metrics.readBackFailed = Door.metrics.readBackFailed + 1 end
        refusals[#refusals + 1] = "mailbox " .. tostring(why or (container == nil and "gone" or "read_back_failed"))
    end
    local squares = Door.porchSquares(house)
    for index = 1, #squares do
        local square = squares[index]
        local ok, why = Door.dropSafe(house, square)
        if not ok and why == "inside_the_house" then ok, why = Door.courtyardSafe(house, square) end
        if ok then
            if dry == true then return { rank = "porch", x = square:getX(), y = square:getY(), z = square:getZ(), dry = true } end
            local added, clean = Door.putOnSquare(square, items)
            if added then
                Door.metrics.placed = Door.metrics.placed + 1
                return { rank = "porch", x = square:getX(), y = square:getY(), z = square:getZ() }
            end
            if clean == false then return nil, "porch partial insertion; rollback failed", true end
            Door.metrics.readBackFailed = Door.metrics.readBackFailed + 1
            refusals[#refusals + 1] = "porch " .. square:getX() .. "," .. square:getY() .. " read_back_failed"
        elseif index <= 3 then
            refusals[#refusals + 1] = "porch " .. square:getX() .. "," .. square:getY() .. " " .. tostring(why)
        end
    end
    if #squares == 0 then refusals[#refusals + 1] = "no porch square loaded" end
    if dry ~= true then Door.metrics.refused = Door.metrics.refused + 1 end
    return nil, table.concat(refusals, "; ")
end

function Door.facing(house, door)
    if type(door) == "table" and tonumber(door.ix) ~= nil and tonumber(door.iy) ~= nil then
        return door.ix + 0.5, door.iy + 0.5
    end
    return tonumber(house.cx) or 0, tonumber(house.cy) or 0
end

Door.neighbours = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Door.outward(door, stand)
    if type(door) ~= "table" or door.mode ~= "door" or tonumber(door.ix) == nil or tonumber(door.iy) == nil then return 0, 0 end
    local dx, dy = stand.x - door.ix, stand.y - door.iy
    if dx > 0 then dx = 1 elseif dx < 0 then dx = -1 end
    if dy > 0 then dy = 1 elseif dy < 0 then dy = -1 end
    return dx, dy
end

function Door.stepOrder(ox, oy)
    local steps = {}
    if ox ~= 0 or oy ~= 0 then
        steps[1] = { ox, oy }
        steps[2] = { oy, ox }
        steps[3] = { 0 - oy, 0 - ox }
        steps[4] = { 0 - ox, 0 - oy }
        return steps
    end
    for index = 1, #Door.neighbours do steps[index] = Door.neighbours[index] end
    return steps
end

function Door.standSearch(house, door, stand, reject)
    local settings = Door.settings
    local z = math.floor(tonumber(stand.z) or 0)
    local ox, oy = Door.outward(door, stand)
    local steps = Door.stepOrder(ox, oy)
    local queue, seen, reasons, memo = { { x = stand.x, y = stand.y, d = 0 } }, {}, {}, {}
    seen[stand.x .. "," .. stand.y] = true
    local head = 1
    while head <= #queue and head <= settings.standSquares do
        local node = queue[head]
        head = head + 1
        local square = Door.square(node.x, node.y, z)
        local key = node.x .. "," .. node.y
        local ok, why, unsure = Door.verdict(square, { occupied = true, memo = memo, x = node.x, y = node.y })
        if ok and not Door.waitingClear(door, node) then ok, why = false, "doorway_clearance" end
        if ok and type(reject) == "table" and reject[key] == true then ok, why = false, "refused_by_spawn_policy" end
        if ok then return { x = node.x, y = node.y, z = z, shifted = node.d, unsure = unsure }, reasons end
        reasons[why or "rejected"] = (reasons[why or "rejected"] or 0) + 1
        if node.d < settings.standRing and square ~= nil then
            for index = 1, #steps do
                local nx, ny = node.x + steps[index][1], node.y + steps[index][2]
                local nkey = nx .. "," .. ny
                if not seen[nkey] then
                    local other = Door.square(nx, ny, z)
                    if other ~= nil and Door.outside(other) and Door.walkable(other)
                            and Door.ask(other, "isFree", false) ~= false and Door.passable(square, other) then
                        seen[nkey] = true
                        queue[#queue + 1] = { x = nx, y = ny, d = node.d + 1 }
                    end
                end
            end
        end
    end
    return nil, reasons
end

function Door.waitingClear(door, point)
    if type(door) ~= "table" or door.mode ~= "door" then return true end
    local origin = door.stand
    if type(origin) ~= "table" then return false end
    local ox, oy = Door.outward(door, origin)
    if ox == 0 and oy == 0 then return false end
    local dx, dy = point.x - origin.x, point.y - origin.y
    return dx * ox + dy * oy >= 1 or math.abs(dx * oy - dy * ox) >= 2
end

function Door.standSpot(house, reject)
    local door = house.door
    local stand = type(door) == "table" and door.stand or nil
    if stand == nil then return nil, "no_stand_square" end
    local fx, fy = Door.facing(house, door)
    local found, reasons = Door.standSearch(house, door, stand, reject)
    local kind = tostring(door.mode or "door")
    if found == nil then return nil, "no free square at the " .. kind .. " (" .. Door.reasonText(reasons) .. ")" end
    found.kind, found.ix, found.iy, found.edge, found.state = kind, door.ix, door.iy, door.edgeKey, door.state
    found.fx, found.fy = fx, fy
    found.base = { x = stand.x, y = stand.y, z = stand.z or 0 }
    local note = nil
    if found.shifted > 0 then
        if found.shifted == 1 and reasons.doorway_clearance == 1 then
            note = "waiting one tile beyond the " .. kind .. " threshold to keep the entrance clear"
        else
            note = "the square at the " .. kind .. " is not free (" .. Door.reasonText(reasons) .. "): "
                .. found.shifted .. " tile(s) away instead"
        end
    end
    return found, note
end

function Door.windowSpot(house, skip, offset, reject, dry)
    local door = house.door
    local list = type(door) == "table" and door.windows or nil
    if type(list) ~= "table" or #list == 0 then return nil, "no_window_mapped" end
    local entrances = ProjectALife.Entrances
    local count = #list
    local first = math.max(0, math.floor(tonumber(offset) or 0)) % count
    local reasons, memo = {}, {}
    for step = 0, count - 1 do
        local item = list[1 + (first + step) % count]
        if type(skip) ~= "table" or skip[item.edge] ~= true then
            local entry = { edgeKey = item.edge, sx = item.x, sy = item.y, ix = item.ix, iy = item.iy, z = item.z }
            local read = entrances ~= nil and type(entrances.rereadEntry) == "function" and entrances.rereadEntry(entry, Door.nowMs())
            local square = Door.square(item.x, item.y, item.z)
            local ok, why, unsure = Door.verdict(square, { occupied = true, memo = memo, x = item.x, y = item.y })
            if read ~= true then
                ok, why = false, "square_unloaded"
            elseif entry.kind ~= "window" then
                ok, why = false, "no_longer_a_window"
            elseif ok and type(reject) == "table" and reject[item.x .. "," .. item.y] == true then
                ok, why = false, "refused_by_spawn_policy"
            end
            if ok then
                if dry ~= true then Door.metrics.windowSpots = Door.metrics.windowSpots + 1 end
                return { kind = "window", x = item.x, y = item.y, z = item.z, ix = item.ix, iy = item.iy,
                    edge = item.edge, state = entry.state, fx = item.ix + 0.5, fy = item.iy + 0.5, unsure = unsure }
            end
            reasons[why or "rejected"] = (reasons[why or "rejected"] or 0) + 1
        end
    end
    return nil, "no_free_window: " .. Door.reasonText(reasons)
end

function Door.visitSpot(house, wanted, offset, skip, reject, dry)
    local note = nil
    if wanted == "window" then
        local spot, why = Door.windowSpot(house, skip, offset, reject, dry)
        if spot ~= nil then return spot, nil end
        note = "no free window (" .. tostring(why) .. ")"
    end
    local spot, why = Door.standSpot(house, reject)
    if spot == nil then
        if note ~= nil then return nil, note .. "; " .. tostring(why) end
        return nil, why
    end
    if note ~= nil and why ~= nil then return spot, note .. "; " .. tostring(why) end
    return spot, note or why
end

function Door.survey(house)
    local report = { stand = nil, standWhy = nil, windows = {}, doors = {} }
    report.stand, report.standWhy = Door.standSpot(house)
    local door = type(house.door) == "table" and house.door or nil
    report.base = door ~= nil and door.stand or nil
    local building = Door.buildingOf(house)
    local entrances = ProjectALife.Entrances
    if building == nil or entrances == nil or type(entrances.mapSite) ~= "function" then return report end
    local site = entrances.mapSite(building, 0, Door.nowMs(), 6000, house.cx, house.cy)
    if site == nil then return report end
    local cached = {}
    for _, item in ipairs(door ~= nil and type(door.windows) == "table" and door.windows or {}) do cached[item.edge] = true end
    local memo = {}
    for edgeKey, entry in pairs(site.entries or {}) do
        if entry.kind == "window" or entry.kind == "door" then
            local square = Door.square(entry.sx, entry.sy, entry.z)
            local ok, why, unsure = Door.verdict(square, { occupied = true, memo = memo, x = entry.sx, y = entry.sy })
            local garage = entry.kind == "door" and Door.isGarage(Door.entryDoor(entry))
            local row = { kind = garage and "garage" or entry.kind, x = entry.sx, y = entry.sy, z = entry.z, ix = entry.ix, iy = entry.iy,
                edge = edgeKey, state = entry.state, ok = ok == true and not garage, why = garage and "garage_door" or why,
                unsure = unsure, fx = entry.ix + 0.5, fy = entry.iy + 0.5, cached = cached[edgeKey] == true }
            if entry.kind == "window" then report.windows[#report.windows + 1] = row else report.doors[#report.doors + 1] = row end
        end
    end
    table.sort(report.windows, function(a, b) return a.edge < b.edge end)
    table.sort(report.doors, function(a, b) return a.edge < b.edge end)
    return report
end

function Door.shuffle(list, rand)
    for index = #list, 2, -1 do
        local pick = 1 + rand(index)
        list[index], list[pick] = list[pick], list[index]
    end
    return list
end

function Door.courtyardSafe(house, square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local spawn = ProjectALife.SpawnPolicy
    if spawn ~= nil and type(spawn.excludedRegionAt) == "function" and spawn.excludedRegionAt({ x = x, y = y }) ~= nil then
        return false, "excluded_region"
    end
    local fenced = Door.enclosed(x, y, z)
    if fenced then return false, "inside_the_yard" end
    local verdict = Door.reach(x, y, z)
    if Door.reachable(verdict) then return true, nil end
    return false, "unreachable_" .. tostring(verdict)
end

function Door.traceSafe(house, square)
    local ok, why = Door.dropSafe(house, square)
    if ok then return true end
    if why ~= "inside_the_house" then return false end
    return Door.courtyardSafe(house, square) == true
end

function Door.scatterPool(house, anchor, want)
    local pool = {}
    local settings = Door.settings
    local ring = 1
    while ring <= settings.scatterMaxRing do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local square = Door.square(anchor.x + dx, anchor.y + dy, anchor.z or 0)
                    if square ~= nil and Door.walkable(square) and Door.itemSquare(square) and not Door.isRoad(square)
                            and Door.traceSafe(house, square) then
                        pool[#pool + 1] = { square = square, ring = ring, count = 0, dx = dx, dy = dy }
                    end
                end
            end
        end
        if ring >= settings.scatterRing and #pool >= want then break end
        ring = ring + 1
    end
    return pool
end

function Door.scatterRing(rand)
    local roll = rand(10)
    if roll < 3 then return 1 end
    if roll < 6 then return 2 end
    if roll < 8 then return 3 end
    return 4
end

function Door.scatterEntry(pool, wanted, rand)
    local best, bestGap, ties = nil, math.huge, 0
    for index = 1, #pool do
        local entry = pool[index]
        if entry.count < Door.settings.scatterPerSquare then
            local gap = math.abs(entry.ring - wanted)
            if gap < bestGap then
                best, bestGap, ties = entry, gap, 1
            elseif gap == bestGap then
                ties = ties + 1
                if rand(ties) == 0 then best = entry end
            end
        end
    end
    return best
end

function Door.scatterOne(entry, piece, rand, report)
    local spread = { { 0.15 + rand(70) / 100, 0.15 + rand(70) / 100 } }
    local added, clean = Door.putOnSquare(entry.square, { piece.item }, spread)
    if added then
        entry.count = entry.count + 1
        report.placed = report.placed + 1
        local id = Door.ask(piece.item, "getID")
        report.spots[#report.spots + 1] = { x = entry.square:getX(), y = entry.square:getY(), z = entry.square:getZ(),
            t = piece.fullType, id = id, ring = entry.ring }
        return true
    end
    Door.metrics.traceRefused = Door.metrics.traceRefused + 1
    entry.count = Door.settings.scatterPerSquare
    if clean == false then report.partial = true end
    return false
end

function Door.scatterFire(pool, fire, rand, report)
    local centers = {}
    for index = 1, #pool do
        if pool[index].ring >= 2 and pool[index].ring <= 3 and pool[index].count == 0 then centers[#centers + 1] = pool[index] end
    end
    if #centers == 0 then return end
    local center = centers[1 + rand(#centers)]
    local rim = {}
    for index = 1, #pool do
        local entry = pool[index]
        if entry ~= center and math.abs(entry.dx - center.dx) <= 1 and math.abs(entry.dy - center.dy) <= 1 then rim[#rim + 1] = entry end
    end
    local stones = 0
    for index = 1, #fire do
        local piece = fire[index]
        local target = center
        if piece.stone == true then
            if #rim > 0 then target = rim[1 + stones % #rim] end
            stones = stones + 1
        end
        if report.partial ~= true then
            target.count = 0
            Door.scatterOne(target, piece, rand, report)
        end
    end
    report.fire = { x = center.square:getX(), y = center.square:getY() }
    center.count = Door.settings.scatterPerSquare
end

function Door.scatter(house, anchor, plan, dry)
    local rand = type(plan.rand) == "function" and plan.rand or function() return 0 end
    local litter, fire = plan.litter or {}, plan.fire or {}
    local pool = Door.scatterPool(house, anchor, math.min(3, #litter + #fire))
    if #pool == 0 then
        if dry ~= true then Door.metrics.traceRefused = Door.metrics.traceRefused + 1 end
        return nil, "no_free_square_near_the_front"
    end
    if dry == true then
        local far = 0
        for index = 1, #pool do far = math.max(far, pool[index].ring) end
        return { dry = true, placed = 0, squares = #pool, far = far, spots = {} }
    end
    Door.shuffle(pool, rand)
    local report = { placed = 0, spots = {}, partial = false }
    if #fire > 0 then Door.scatterFire(pool, fire, rand, report) end
    for index = 1, #litter do
        if report.partial then break end
        local entry = Door.scatterEntry(pool, Door.scatterRing(rand), rand)
        if entry == nil then break end
        Door.scatterOne(entry, litter[index], rand, report)
    end
    local used, seen = 0, {}
    for index = 1, #report.spots do
        local key = report.spots[index].x .. "," .. report.spots[index].y
        if not seen[key] then seen[key] = true; used = used + 1 end
    end
    report.squares = used
    Door.metrics.tracesPlaced = Door.metrics.tracesPlaced + report.placed
    Door.metrics.traceSquares = Door.metrics.traceSquares + used
    if report.placed == 0 then return nil, "every_item_was_refused", report.partial end
    return report
end

function Door.removeTrace(entry)
    local square = Door.square(entry.x, entry.y, entry.z)
    if square == nil then return nil end
    local objects, count = Door.worldObjects(square)
    if objects == nil then return nil end
    for index = count - 1, 0, -1 do
        local got, object = pcall(objects.get, objects, index)
        if got and object ~= nil and type(object.getItem) == "function" then
            local read, item = pcall(object.getItem, object)
            local id = nil
            if read and item ~= nil then id = Door.ask(item, "getID") end
            if id ~= nil and entry.id ~= nil and id == entry.id then
                if type(square.transmitRemoveItemFromSquare) == "function" then
                    pcall(square.transmitRemoveItemFromSquare, square, object)
                    Door.metrics.tracesRemoved = Door.metrics.tracesRemoved + 1
                end
                return true
            end
        end
    end
    return false
end

return Door
