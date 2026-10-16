ProjectALife = ProjectALife or {}
require "ProjectALife/World/ALifeMapZones"
require "ProjectALife/World/ALifeRoadGraphShipped"

local Graph = {

    SCHEMA = 5,
    adapters = {},
    nodes = {},
    edges = {},
    towns = {},
    adjacency = {},
    built = false,

    build = nil,
    settings = {

        clusterRadius = 160,

        neighbours = 3,

        maximumEdge = 3500,

        sampleStep = 32,

        sliceBudgetMs = 6,
        worldSize = 30000,
        gatherCell = 3000,
        gatherBatch = 64,
        nodeBatch = 64,
        samplerBatch = 256,
        connectBatch = 32,
        bucketSize = 256,

        roadSnapRadius = 48,

        dataClusterRadius = 450,
        dataNameRadius = 1500,

        anchorNamedPlaces = true,

        nameRadius = 900,
        townNames = {
            { name = "Muldraugh", x = 11181, y = 9725 },
            { name = "West Point", x = 11581, y = 6916 },
            { name = "Rosewood", x = 8446, y = 11556 },
            { name = "Riverside", x = 6300, y = 5668 },
            { name = "March Ridge", x = 9921, y = 12603 },
            { name = "Valley Station", x = 13056, y = 6031 },
            { name = "Fallas Lake", x = 7348, y = 8371 },
            { name = "Echo Creek", x = 4235, y = 11069 },
            { name = "Brandenburg", x = 2314, y = 6253 },
            { name = "Ekron", x = 1020, y = 9838 },
            { name = "Irvington", x = 2729, y = 13797 },
            { name = "Louisville", x = 12600, y = 1800 },
        },
    },
    metrics = { towns = 0, edges = 0, rejectedWater = 0, slices = 0, gatherCells = 0, restored = false,
        seeded = 0, bridged = 0, isolated = 0, partial = false, fromData = false, snapped = 0, unsnapped = 0 },

    roadIndex = nil,

    expectedTowns = 0,

    epoch = 0,
    treeCache = { epoch = -1, trees = {} },
}
ProjectALife.RoadGraph = Graph

local function distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function clearGraph()
    Graph.nodes, Graph.edges, Graph.towns, Graph.adjacency = {}, {}, {}, {}
    Graph.built = false
    Graph.epoch = Graph.epoch + 1
end

function Graph.reset()
    clearGraph()
    Graph.build = nil
    Graph.expectedTowns = 0
    Graph.treeCache = { epoch = -1, trees = {} }
end

function Graph.namedTownCount()
    local count = 0
    for _, id in ipairs(Graph.towns) do
        local name = tostring(Graph.nodes[id] and Graph.nodes[id].name or "")
        if not string.match(name, "^Town %d+$") then count = count + 1 end
    end
    return count
end

Graph.outskirtsRange = 600

function Graph.compassWord(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    local ns = dy < 0 and "north" or "south"
    local ew = dx < 0 and "west" or "east"
    if ax <= ay * 0.5 then return ns end
    if ay <= ax * 0.5 then return ew end
    return ns .. "-" .. ew
end

function Graph.displayName(id, node)
    if type(node) ~= "table" then node = id ~= nil and Graph.nodes[id] or nil end
    if type(node) ~= "table" then return id ~= nil and tostring(id) or nil end
    local name = tostring(node.name or id)
    local place = string.match(name, "^(.-) %d+$")
    if place == nil or place == "" then return name end
    local regions = ProjectALife.TownRegions
    local x, y = tonumber(node.x), tonumber(node.y)
    local box
    if type(regions) == "table" and x ~= nil and y ~= nil then
        if place == "Town" then
            if type(regions.distanceToTown) == "function" then
                local _, nearest = regions.distanceToTown({ x = x, y = y })
                box = nearest
            end
        elseif type(regions.definitions) == "table" then
            for _, definition in ipairs(regions.definitions) do
                if definition.label == place then box = definition break end
            end
        end
    end
    if type(box) ~= "table" then return place == "Town" and name or place end
    local label = tostring(box.label or box.id or place)
    local minX, maxX, minY, maxY = tonumber(box.minX), tonumber(box.maxX), tonumber(box.minY), tonumber(box.maxY)
    if minX == nil or maxX == nil or minY == nil or maxY == nil then return label end
    local dx = x < minX and x - minX or (x > maxX and x - maxX or 0)
    local dy = y < minY and y - minY or (y > maxY and y - maxY or 0)
    if dx == 0 and dy == 0 then return label end
    local range = tonumber(Graph.outskirtsRange) or 600
    if dx * dx + dy * dy <= range * range then return "outskirts of " .. label end
    return Graph.compassWord(dx, dy) .. " of " .. label
end

function Graph.displayLabel(label, id, node)
    if label == nil then return nil end
    label = tostring(label)
    if type(node) ~= "table" then node = id ~= nil and Graph.nodes[id] or nil end
    if type(node) ~= "table" or node.name == nil then return label end
    local raw = tostring(node.name)
    if #raw == 0 or #label < #raw or string.sub(label, -#raw) ~= raw then return label end
    return string.sub(label, 1, #label - #raw) .. Graph.displayName(id, node)
end

function Graph.addNode(id, x, y, kind, name, seeded, habitat)
    if type(id) ~= "string" or Graph.nodes[id] ~= nil then return false end
    Graph.nodes[id] = { id = id, x = tonumber(x) or 0, y = tonumber(y) or 0,
        z = 0, kind = kind or "junction", name = name or id, seeded = seeded == true or nil,
        habitat = Graph.copyHabitat(habitat) }
    Graph.adjacency[id] = Graph.adjacency[id] or {}
    if kind == "town" then Graph.towns[#Graph.towns + 1] = id end
    Graph.epoch = Graph.epoch + 1
    return true
end

function Graph.addEdge(a, b, len, bridge)
    local na, nb = Graph.nodes[a], Graph.nodes[b]
    if na == nil or nb == nil or a == b then return false end
    local euclid = distance(na.x, na.y, nb.x, nb.y)
    len = math.max(euclid, tonumber(len) or euclid)

    if Graph.adjacency[a][b] ~= nil then return false end
    Graph.edges[#Graph.edges + 1] = { a = a, b = b, len = len, bridge = bridge == true }
    Graph.adjacency[a][b] = len
    Graph.adjacency[b][a] = len
    Graph.epoch = Graph.epoch + 1
    return true
end

function Graph.routesFrom(from, to)
    if Graph.nodes[from] == nil then return nil end
    local dist, previous, visited = {}, {}, {}
    for id in pairs(Graph.nodes) do dist[id] = math.huge end
    dist[from] = 0
    while true do
        local best, bestDist = nil, math.huge
        for id, d in pairs(dist) do
            if not visited[id] and d < bestDist then best, bestDist = id, d end
        end
        if best == nil then break end
        if best == to then break end
        visited[best] = true
        for neighbour, len in pairs(Graph.adjacency[best] or {}) do
            local candidate = bestDist + len

            local blind = neighbour ~= from and Graph.nodes[neighbour].seeded == true
            if not blind and candidate < dist[neighbour] then
                dist[neighbour] = candidate
                previous[neighbour] = best
            end
        end
    end
    return { from = from, distances = dist, previous = previous }
end

function Graph.treeFrom(from)
    local cache = Graph.treeCache
    if type(cache) ~= "table" or cache.epoch ~= Graph.epoch or cache.nodes ~= Graph.nodes
            or cache.adjacency ~= Graph.adjacency or type(cache.trees) ~= "table" then
        cache = { epoch = Graph.epoch, nodes = Graph.nodes, adjacency = Graph.adjacency, trees = {} }
        Graph.treeCache = cache
    end
    local tree = cache.trees[from]
    if tree == nil then
        tree = Graph.routesFrom(from)
        if tree ~= nil then cache.trees[from] = tree end
    end
    return tree
end

function Graph.route(from, to, tree)
    if Graph.nodes[from] == nil or Graph.nodes[to] == nil then return nil end
    if from == to then return { from } end
    if tree == nil or tree.from ~= from then tree = Graph.treeFrom(from) end
    if tree.distances[to] == nil or tree.distances[to] == math.huge then return nil end
    local chain, cursor = {}, to
    while cursor ~= nil do
        table.insert(chain, 1, cursor)
        cursor = tree.previous[cursor]
    end
    if chain[1] ~= from then return nil end
    return chain
end

function Graph.routeLength(chain)
    if type(chain) ~= "table" or #chain < 2 then return 0 end
    local total = 0
    for index = 1, #chain - 1 do
        total = total + (Graph.adjacency[chain[index]][chain[index + 1]] or 0)
    end
    return total
end

function Graph.nearest(x, y, kind)
    local best, bestDist = nil, math.huge
    for id, node in pairs(Graph.nodes) do
        if kind == nil or node.kind == kind then
            local d = distance(x, y, node.x, node.y)
            if d < bestDist then best, bestDist = id, d end
        end
    end
    return best, bestDist
end

function Graph.buildRectIndex(rects, bucketSize)
    bucketSize = math.max(32, math.floor(tonumber(bucketSize) or Graph.settings.bucketSize))
    local buckets, count = {}, 0
    local function file(rect)
        local x1, y1 = math.floor(rect.x / bucketSize), math.floor(rect.y / bucketSize)
        local x2, y2 = math.floor((rect.x + rect.w) / bucketSize), math.floor((rect.y + rect.h) / bucketSize)
        for bx = x1, x2 do
            for by = y1, y2 do
                local key = bx .. ":" .. by
                buckets[key] = buckets[key] or {}
                local list = buckets[key]
                list[#list + 1] = { x = rect.x, y = rect.y, x2 = rect.x + rect.w, y2 = rect.y + rect.h }
            end
        end
        count = count + 1
    end
    if type(rects) == "table" then
        for _, rect in ipairs(rects) do file(rect) end
    end
    return { buckets = buckets, size = bucketSize, count = count }
end

function Graph.buildRoadIndex(rects, bucketSize)
    if type(rects) ~= "table" then
        local zones = ProjectALife.MapZones
        rects = zones ~= nil and type(zones.list) == "function" and zones.list("roads") or {}
    end
    Graph.roadIndex = Graph.buildRectIndex(rects, bucketSize)
    return Graph.roadIndex
end

function Graph.nearestRect(x, y, radius, index)
    if index == nil or index.count == 0 then return nil end
    radius = math.max(0, tonumber(radius) or Graph.settings.roadSnapRadius)
    local size = index.size
    local bestX, bestY, bestD = nil, nil, radius * radius
    for bx = math.floor((x - radius) / size), math.floor((x + radius) / size) do
        for by = math.floor((y - radius) / size), math.floor((y + radius) / size) do
            local list = index.buckets[bx .. ":" .. by]
            if list ~= nil then
                for _, rect in ipairs(list) do
                    local cx = math.max(rect.x, math.min(rect.x2 - 1, x))
                    local cy = math.max(rect.y, math.min(rect.y2 - 1, y))
                    local d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
                    if d <= bestD then bestX, bestY, bestD = cx, cy, d end
                end
            end
        end
    end
    if bestX == nil then return nil end
    return { x = bestX, y = bestY, z = 0 }, math.sqrt(bestD)
end

function Graph.snapToRoad(x, y, radius)
    local point = Graph.nearestRect(x, y, radius, Graph.roadIndex or Graph.buildRoadIndex())
    return point
end

function Graph.copyHabitat(habitat)
    local out = {}
    for _, kind in ipairs({ "water", "forest" }) do
        local value = type(habitat) == "table" and tonumber(habitat[kind]) or nil
        if value ~= nil and value >= 0 and value <= 150 then out[kind] = value end
    end
    return out
end

function Graph.habitatAt(x, y, indices)
    local out = {}
    for _, kind in ipairs({ "water", "forest" }) do
        local _, tiles = Graph.nearestRect(x, y, 150, indices[kind])
        out[kind] = tiles
    end
    return out
end

function Graph.interpolate(fromId, toId, t)
    local a, b = Graph.nodes[fromId], Graph.nodes[toId]
    if a == nil or b == nil then return nil end
    t = math.max(0, math.min(1, tonumber(t) or 0))
    local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
    local snapped = Graph.snapToRoad(x, y)
    if snapped ~= nil then
        Graph.metrics.snapped = (Graph.metrics.snapped or 0) + 1
        return { x = snapped.x, y = snapped.y, z = 0 }
    end
    Graph.metrics.unsnapped = (Graph.metrics.unsnapped or 0) + 1
    return { x = x, y = y, z = 0 }
end

function Graph.reachable(from)
    local seen, queue, count = {}, { from }, 0
    if Graph.nodes[from] == nil then return seen, 0 end
    seen[from] = true
    while #queue > 0 do
        local id = table.remove(queue, 1)
        count = count + 1
        for neighbour in pairs(Graph.adjacency[id] or {}) do
            if not seen[neighbour] then
                seen[neighbour] = true
                queue[#queue + 1] = neighbour
            end
        end
    end
    return seen, count
end

function Graph.connected()
    if #Graph.towns == 0 then return true end

    local seen = Graph.reachable(Graph.towns[1])
    for _, id in ipairs(Graph.towns) do
        if not seen[id] then return false end
    end
    return true
end

function Graph.clusterTowns(rects, radius)
    local clusters, grid = {}, {}
    local size = math.max(1, tonumber(radius) or 1)
    for _, rect in ipairs(rects) do
        local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
        local gx, gy = math.floor(cx / size), math.floor(cy / size)
        local best = nil
        for bx = gx - 1, gx + 1 do
            for by = gy - 1, gy + 1 do
                local members = grid[bx .. ":" .. by]
                if members ~= nil then
                    for index in pairs(members) do
                        if (best == nil or index < best)
                                and distance(cx, cy, clusters[index].x, clusters[index].y) <= radius then
                            best = index
                        end
                    end
                end
            end
        end
        if best ~= nil then
            local cluster = clusters[best]
            local before = math.floor(cluster.x / size) .. ":" .. math.floor(cluster.y / size)
            cluster.count = cluster.count + 1
            cluster.x = cluster.x + (cx - cluster.x) / cluster.count
            cluster.y = cluster.y + (cy - cluster.y) / cluster.count
            local after = math.floor(cluster.x / size) .. ":" .. math.floor(cluster.y / size)
            if after ~= before then
                grid[before][best] = nil
                grid[after] = grid[after] or {}
                grid[after][best] = true
            end
        else
            clusters[#clusters + 1] = { x = cx, y = cy, count = 1 }
            local key = gx .. ":" .. gy
            grid[key] = grid[key] or {}
            grid[key][#clusters] = true
        end
    end
    return clusters
end

function Graph.dryPoint(x, y, sampler, step, rings)
    x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)
    if type(sampler) ~= "function" then return { x = x, y = y } end
    local water, road = sampler(x, y)
    if not water or road then return { x = x, y = y } end
    step = math.max(1, math.floor(tonumber(step) or 24))
    rings = math.max(1, math.floor(tonumber(rings) or 8))
    for ring = 1, rings do
        local distance = ring * step
        for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
            local cx = x + offset[1] * distance
            local cy = y + offset[2] * distance
            local wet, bridged = sampler(cx, cy)
            if not wet or bridged then return { x = cx, y = cy, moved = distance } end
        end
    end
    return { x = x, y = y }
end

function Graph.legSafe(ax, ay, bx, by, step, sampler)
    local length = distance(ax, ay, bx, by)
    local steps = math.max(1, math.floor(length / math.max(4, step)))
    local bridged = false
    for index = 0, steps do
        local t = index / steps
        local water, road = sampler(ax + (bx - ax) * t, ay + (by - ay) * t)
        if water and not road then return false, bridged end
        if water and road then bridged = true end
    end
    return true, bridged
end

local function clock()
    if type(Graph.adapters.nowMs) == "function" then return Graph.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.clock() * 1000)
end

function Graph.bucketInsert(buckets, rect, flag, bucketSize)
    local x1, y1 = math.floor(rect.x / bucketSize), math.floor(rect.y / bucketSize)
    local x2, y2 = math.floor((rect.x + rect.w) / bucketSize), math.floor((rect.y + rect.h) / bucketSize)
    for bx = x1, x2 do
        for by = y1, y2 do
            local key = bx .. ":" .. by
            local list = buckets[key]
            if list == nil then
                list = {}
                buckets[key] = list
            end
            list[#list + 1] = { x = rect.x, y = rect.y, x2 = rect.x + rect.w, y2 = rect.y + rect.h, flag = flag }
        end
    end
end

function Graph.rectSampler(water, roads, bucketSize)
    bucketSize = math.max(32, tonumber(bucketSize) or Graph.settings.bucketSize)
    local buckets = {}
    for _, rect in ipairs(water or {}) do Graph.bucketInsert(buckets, rect, "water", bucketSize) end
    for _, rect in ipairs(roads or {}) do Graph.bucketInsert(buckets, rect, "road", bucketSize) end
    return Graph.bucketSampler(buckets, bucketSize)
end

function Graph.samplerPhase(build)
    local size = math.max(32, tonumber(Graph.settings.bucketSize) or 256)
    local water, roads = build.water or {}, build.roads or {}
    local buckets = build.buckets or {}
    build.buckets = buckets
    local at, total = build.samplerAt or 1, #water + #roads
    local last = math.min(total, at + math.max(1, math.floor(tonumber(Graph.settings.samplerBatch) or 256)) - 1)
    for index = at, last do
        if index <= #water then Graph.bucketInsert(buckets, water[index], "water", size)
        else Graph.bucketInsert(buckets, roads[index - #water], "road", size) end
    end
    build.samplerAt = last + 1
    if build.samplerAt <= total then return end
    build.sampler = Graph.bucketSampler(buckets, size)
    build.buckets, build.samplerAt = nil, nil
    build.phase = "nodes"
end

function Graph.bucketSampler(buckets, bucketSize)
    return function(x, y)
        local list = buckets[math.floor(x / bucketSize) .. ":" .. math.floor(y / bucketSize)]
        if list == nil then return false, false end
        local isWater, isRoad = false, false
        for _, rect in ipairs(list) do
            if x >= rect.x and x < rect.x2 and y >= rect.y and y < rect.y2 then
                if rect.flag == "water" then isWater = true else isRoad = true end
            end
        end
        return isWater, isRoad
    end
end

function Graph.nameClusters(clusters, nameRadius)
    local names, claims = {}, {}
    for index, cluster in ipairs(clusters or {}) do
        local best, bestDistance = nil, tonumber(nameRadius) or Graph.settings.nameRadius
        for _, place in ipairs(Graph.settings.townNames or {}) do
            local d = distance(cluster.x, cluster.y, place.x, place.y)
            if d <= bestDistance then best, bestDistance = place.name, d end
        end
        if best ~= nil then
            claims[best] = claims[best] or {}
            local list = claims[best]
            list[#list + 1] = { index = index, d = bestDistance }
        end
    end
    for place, list in pairs(claims) do
        table.sort(list, function(a, b) return a.d < b.d end)
        for rank, claim in ipairs(list) do
            names[claim.index] = rank == 1 and place or (place .. " " .. tostring(rank))
        end
    end
    for index in ipairs(clusters or {}) do
        if names[index] == nil then names[index] = "Town " .. tostring(index) end
    end
    return names
end

function Graph.beginBuild(rects, sampler, habitat)
    habitat = type(habitat) == "table" and habitat or {}
    Graph.build = { phase = "cluster", rects = rects or {}, water = habitat.water or {}, roads = {}, forest = habitat.forest or {},
        sampler = sampler, cursor = 1, startedMs = clock() }
    return true
end

function Graph.seedsWithin(bounds)
    local result = {}
    if type(bounds) ~= "table" then return result end
    for _, place in ipairs(Graph.settings.townNames or {}) do
        if place.x >= bounds.x and place.x < bounds.x + bounds.w
                and place.y >= bounds.y and place.y < bounds.y + bounds.h then
            result[#result + 1] = place
        end
    end
    return result
end

function Graph.seedTowns(clusters, bounds)
    local added = 0
    for _, place in ipairs(Graph.seedsWithin(bounds)) do
        local claimed = false
        for _, cluster in ipairs(clusters) do
            if distance(cluster.x, cluster.y, place.x, place.y) <= Graph.settings.nameRadius then
                claimed = true
                break
            end
        end
        if not claimed then
            clusters[#clusters + 1] = { x = place.x, y = place.y, count = 1, seeded = true }
            added = added + 1
        end
    end
    return added
end

function Graph.anchorTowns(clusters, bounds)
    local added = 0
    local count = #clusters
    for _, place in ipairs(Graph.seedsWithin(bounds)) do
        local claimed = false
        for index = 1, count do
            local cluster = clusters[index]
            if distance(cluster.x, cluster.y, place.x, place.y) <= Graph.settings.nameRadius then
                claimed = true
                break
            end
        end
        if not claimed then
            clusters[#clusters + 1] = { x = place.x, y = place.y, count = 1, anchor = true }
            added = added + 1
        end
    end
    return added
end

function Graph.startWorldBuild(bounds, mapName)
    local b = bounds or { x = 0, y = 0, w = Graph.settings.worldSize, h = Graph.settings.worldSize }
    local cell = math.max(300, Graph.settings.gatherCell)
    Graph.expectedTowns = #Graph.seedsWithin(b)
    Graph.build = { phase = "gather", rects = {}, water = {}, roads = {}, forest = {}, sampler = nil,
        bounds = b, cell = cell, cx = 0, cy = 0,
        columns = math.max(1, math.ceil(b.w / cell)), rows = math.max(1, math.ceil(b.h / cell)),
        cursor = 1, startedMs = clock() }

    local zones = ProjectALife.MapZones
    if Graph.usesShippedZones(mapName) then
        local build = Graph.build
        local function within(rect)
            return rect.x + rect.w > b.x and rect.x < b.x + b.w and rect.y + rect.h > b.y and rect.y < b.y + b.h
        end
        zones.each("towns", function(rect) if within(rect) then build.rects[#build.rects + 1] = rect end end)
        zones.each("water", function(rect) if within(rect) then build.water[#build.water + 1] = rect end end)
        zones.each("roads", function(rect) if within(rect) then build.roads[#build.roads + 1] = rect end end)
        zones.each("forest", function(rect) if within(rect) then build.forest[#build.forest + 1] = rect end end)
        build.phase = "cluster"
        build.fromData = true
        Graph.metrics.fromData = true
    end
    return true
end

function Graph.usesShippedZones(mapName)
    if type(Graph.adapters.zones) == "function" then return false end
    local zones = ProjectALife.MapZones
    if zones == nil or type(zones.map) ~= "string" or type(zones.each) ~= "function" then return false end
    local name = mapName
    if name == nil then pcall(function() name = tostring(getWorld():getMap()) end) end
    return type(name) == "string" and string.find(name, zones.map, 1, true) ~= nil
end

function Graph.importShipped(mapName)
    local shipped = ProjectALife.RoadGraphShipped
    if type(shipped) ~= "table" or not Graph.usesShippedZones(mapName) then return false end
    local ok = Graph.import(shipped, shipped.signature)
    if ok then Graph.metrics.shipped = true end
    return ok == true
end

function Graph.metaZones(x, y, w, h)
    return getWorld():getMetaGrid():getZonesIntersecting(x, y, 0, w, h)
end

local function zonesIn(x, y, w, h)
    if type(Graph.adapters.zones) == "function" then return Graph.adapters.zones(x, y, w, h) or {} end
    local ok, zones = pcall(Graph.metaZones, x, y, w, h)
    if not ok or zones == nil then return {} end
    return zones
end

function Graph.zoneCount(list)
    if type(list) == "table" then return #list end
    return tonumber(list:size()) or 0
end

function Graph.zoneRow(list, index)
    if type(list) == "table" then return list[index] end
    local zone = list:get(index - 1)
    if zone == nil then return nil end
    return { type = tostring(zone:getType() or ""),
        x = zone:getX(), y = zone:getY(), w = zone:getWidth(), h = zone:getHeight() }
end

local function gatherOne(build)
    local b = build.bounds
    if build.pending == nil then
        build.cellX, build.cellY = b.x + build.cx * build.cell, b.y + build.cy * build.cell
        build.pending = zonesIn(build.cellX, build.cellY, build.cell, build.cell)
        build.pendingCount = Graph.zoneCount(build.pending)
        build.pendingAt = 1
        Graph.metrics.gatherCells = (Graph.metrics.gatherCells or 0) + 1
    end
    local x, y = build.cellX, build.cellY
    local batch = math.max(1, math.floor(tonumber(Graph.settings.gatherBatch) or 64))
    local last = math.min(build.pendingCount, build.pendingAt + batch - 1)
    for index = build.pendingAt, last do
        local read, zone = pcall(Graph.zoneRow, build.pending, index)
        if read and zone ~= nil then
            local rect = { x = tonumber(zone.x) or 0, y = tonumber(zone.y) or 0,
                w = tonumber(zone.w) or 0, h = tonumber(zone.h) or 0 }

            local owns = rect.x >= x and rect.x < x + build.cell and rect.y >= y and rect.y < y + build.cell
            if not owns and build.cx == 0 and build.cy == 0 and (rect.x < b.x or rect.y < b.y) then owns = true end
            if owns then
                local kind = zone.type
                if kind == "TownZone" then build.rects[#build.rects + 1] = rect
                elseif kind == "WaterFlow" or kind == "WaterZone" then build.water[#build.water + 1] = rect
                elseif kind == "Nav" then build.roads[#build.roads + 1] = rect
                elseif kind == "Forest" or kind == "DeepForest" or kind == "Vegitation" or kind == "FarmLand" then
                    build.forest[#build.forest + 1] = rect
                end
            end
        end
    end
    build.pendingAt = last + 1
    if build.pendingAt <= build.pendingCount then return end
    build.pending = nil
    build.cx = build.cx + 1
    if build.cx >= build.columns then
        build.cx = 0
        build.cy = build.cy + 1
        if build.cy >= build.rows then build.phase = "cluster" end
    end
end

local function clusterPhase(build)
    clearGraph()
    local settings = Graph.settings
    local fromData = build.fromData == true
    local clusters = Graph.clusterTowns(build.rects,
        fromData and settings.dataClusterRadius or settings.clusterRadius)

    Graph.metrics.seeded = (build.bounds ~= nil and not fromData)
        and Graph.seedTowns(clusters, build.bounds) or 0
    Graph.metrics.anchored = 0
    if fromData and build.bounds ~= nil and settings.anchorNamedPlaces ~= false then
        Graph.metrics.anchored = Graph.anchorTowns(clusters, build.bounds)
    end
    build.clusters = clusters
    build.names = Graph.nameClusters(clusters, fromData and settings.dataNameRadius or nil)
    build.habitat = { water = Graph.buildRectIndex(build.water), forest = Graph.buildRectIndex(build.forest) }
    build.anchors, build.anchorList = {}, {}
    build.nodeAt = 1
    build.phase = build.sampler ~= nil and "nodes" or "sampler"
end

local function nodesPhase(build)
    build.sampler = build.sampler or Graph.rectSampler(build.water, build.roads, Graph.settings.bucketSize)
    local clusters, names, habitat = build.clusters, build.names, build.habitat
    local last = math.min(#clusters, build.nodeAt + math.max(1, math.floor(tonumber(Graph.settings.nodeBatch) or 64)) - 1)
    for index = build.nodeAt, last do
        local cluster = clusters[index]
        local point = Graph.dryPoint(math.floor(cluster.x), math.floor(cluster.y), build.sampler)
        Graph.addNode("town" .. index, point.x, point.y, "town", names[index], cluster.seeded == true,
            Graph.habitatAt(point.x, point.y, habitat))
        if cluster.anchor == true then
            build.anchors["town" .. index] = true
            build.anchorList[#build.anchorList + 1] = "town" .. index
        end
    end
    build.nodeAt = last + 1
    if build.nodeAt <= #clusters then return end
    build.clusters, build.names, build.habitat = nil, nil, nil
    build.cursor = 1
    build.phase = "link"
end

function Graph.connectDone(build)
    if build.anchorsLinked ~= true and type(build.anchorList) == "table" and #build.anchorList > 0 then
        build.anchorsLinked = true
        build.cursor = 1
        build.phase = "anchor"
    else
        build.phase = "done"
    end
end

local function linkOne(build)
    local settings = Graph.settings
    local anchoring = build.phase == "anchor"
    local anchors = build.anchors or {}
    local id = anchoring and build.anchorList[build.cursor] or Graph.towns[build.cursor]
    local node = Graph.nodes[id]
    if not anchoring and anchors[id] == true then
        build.cursor = build.cursor + 1
        if build.cursor > #Graph.towns then build.phase = "connect" end
        return
    end
    if build.candidates == nil then
        local candidates = {}
        for _, other in ipairs(Graph.towns) do
            if other ~= id and anchors[other] ~= true then
                local d = distance(node.x, node.y, Graph.nodes[other].x, Graph.nodes[other].y)
                if d <= settings.maximumEdge then
                    candidates[#candidates + 1] = { id = other, d = d }
                end
            end
        end
        table.sort(candidates, function(a, b) return a.d < b.d end)
        build.candidates, build.candidateAt, build.linked = candidates, 1, 0
    end
    local candidate = build.candidates[build.candidateAt]
    if candidate ~= nil and build.linked < settings.neighbours then
        local other = Graph.nodes[candidate.id]
        local safe, bridged = Graph.legSafe(node.x, node.y, other.x, other.y,
            settings.sampleStep, build.sampler)
        if safe then
            if Graph.addEdge(id, candidate.id, candidate.d, bridged) then build.linked = build.linked + 1
            elseif Graph.adjacency[id][candidate.id] ~= nil then build.linked = build.linked + 1 end
        else
            Graph.metrics.rejectedWater = Graph.metrics.rejectedWater + 1
        end
        build.candidateAt = build.candidateAt + 1
        if build.candidateAt <= #build.candidates and build.linked < settings.neighbours then return end
    end
    build.candidates = nil
    build.cursor = build.cursor + 1
    if anchoring then
        if build.cursor > #build.anchorList then build.phase = "connect" end
    elseif build.cursor > #Graph.towns then
        build.phase = "connect"
    end
end

local function connectOne(build)
    local settings = Graph.settings
    if build.connectPairs == nil then
        local skip = build.anchorsLinked ~= true and build.anchors or {}
        local seen = Graph.reachable(Graph.towns[1])
        local unreached = {}
        for _, id in ipairs(Graph.towns) do
            if not seen[id] and skip[id] ~= true then unreached[#unreached + 1] = id end
        end
        if #unreached == 0 then
            Graph.connectDone(build)
            return
        end
        local pairsByLength = {}
        for _, a in ipairs(Graph.towns) do
            if seen[a] and skip[a] ~= true then
                for _, b in ipairs(unreached) do
                    pairsByLength[#pairsByLength + 1] = { a = a, b = b,
                        d = distance(Graph.nodes[a].x, Graph.nodes[a].y, Graph.nodes[b].x, Graph.nodes[b].y) }
                end
            end
        end
        table.sort(pairsByLength, function(l, r) return l.d < r.d end)
        build.connectPairs, build.connectAt, build.connectUnreached = pairsByLength, 1, #unreached
    end
    local pending = build.connectPairs
    local last = math.min(#pending, build.connectAt + math.max(1, math.floor(tonumber(settings.connectBatch) or 32)) - 1)
    for index = build.connectAt, last do
        local pair = pending[index]
        local na, nb = Graph.nodes[pair.a], Graph.nodes[pair.b]
        local safe, bridged = Graph.legSafe(na.x, na.y, nb.x, nb.y, settings.sampleStep, build.sampler)
        if safe and Graph.addEdge(pair.a, pair.b, pair.d, bridged) then
            Graph.metrics.bridged = (Graph.metrics.bridged or 0) + 1
            build.connectPairs = nil
            return
        end
    end
    build.connectAt = last + 1
    if build.connectAt <= #pending then return end
    Graph.metrics.isolated = build.connectUnreached
    build.connectPairs = nil
    Graph.connectDone(build)
end

function Graph.buildStep(budgetMs)
    if Graph.built then return true end
    local build = Graph.build
    if build == nil then return false end
    local start = clock()
    local budget = math.max(0, tonumber(budgetMs) or Graph.settings.sliceBudgetMs)
    Graph.metrics.slices = (Graph.metrics.slices or 0) + 1
    while true do
        if build.phase == "gather" then
            gatherOne(build)
        elseif build.phase == "cluster" then
            clusterPhase(build)
        elseif build.phase == "sampler" then
            Graph.samplerPhase(build)
        elseif build.phase == "nodes" then
            nodesPhase(build)
        elseif build.phase == "link" then
            if #Graph.towns == 0 then build.phase = "done" else linkOne(build) end
        elseif build.phase == "anchor" then
            linkOne(build)
        elseif build.phase == "connect" then
            connectOne(build)
        end
        if build.phase == "done" then
            Graph.metrics.towns, Graph.metrics.edges = #Graph.towns, #Graph.edges
            Graph.metrics.buildMs = clock() - (build.startedMs or start)
            Graph.built = true
            Graph.build = nil
            Graph.epoch = Graph.epoch + 1
            return true
        end
        if clock() - start >= budget then return false end
    end
end

function Graph.buildFromRects(rects, sampler)
    Graph.beginBuild(rects, sampler)
    for _ = 1, 1000000 do
        if Graph.buildStep(math.huge) then break end
    end
    return Graph.built, "built"
end

function Graph.buildFromWorld(bounds)
    if Graph.built then return true, "already_built" end
    Graph.startWorldBuild(bounds)
    for _ = 1, 1000000 do
        if Graph.buildStep(math.huge) then break end
    end
    if #Graph.towns == 0 then return false, "no_town_zones" end
    return true, "built"
end

function Graph.export(signature)
    local ids = {}
    for id in pairs(Graph.nodes) do ids[#ids + 1] = id end
    table.sort(ids)
    local nodes = {}
    for _, id in ipairs(ids) do
        local node = Graph.nodes[id]
        nodes[#nodes + 1] = { id = id, x = node.x, y = node.y, kind = node.kind, name = node.name,
            seeded = node.seeded == true or nil, habitat = Graph.copyHabitat(node.habitat) }
    end
    local edges = {}
    for _, edge in ipairs(Graph.edges) do
        edges[#edges + 1] = { a = edge.a, b = edge.b, len = edge.len, bridge = edge.bridge == true }
    end

    local expected = math.floor(tonumber(Graph.expectedTowns) or 0)
    local partial = expected > 0 and Graph.namedTownCount() < expected - 2
    Graph.metrics.partial = partial
    return { schema = Graph.SCHEMA, signature = tostring(signature or ""), nodes = nodes, edges = edges,
        expected = expected, partial = partial or nil }
end

function Graph.import(saved, signature)
    if type(saved) ~= "table" or saved.schema ~= Graph.SCHEMA then return false, "no_saved_graph" end
    if tostring(saved.signature or "") ~= tostring(signature or "") then return false, "signature_mismatch" end
    if saved.partial == true then return false, "partial_graph" end
    if type(saved.nodes) ~= "table" or #saved.nodes == 0 then return false, "empty_graph" end
    clearGraph()
    for _, node in ipairs(saved.nodes) do
        Graph.addNode(node.id, node.x, node.y, node.kind, node.name, node.seeded == true, node.habitat)
    end
    for _, edge in ipairs(saved.edges or {}) do Graph.addEdge(edge.a, edge.b, edge.len, edge.bridge) end
    Graph.metrics.towns, Graph.metrics.edges = #Graph.towns, #Graph.edges
    Graph.metrics.restored = true
    Graph.built = true
    Graph.build = nil
    Graph.epoch = Graph.epoch + 1
    return true, "restored"
end

return Graph
