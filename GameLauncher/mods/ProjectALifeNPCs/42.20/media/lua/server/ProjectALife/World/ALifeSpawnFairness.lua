require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/Senses/ALifeSight"
require "ProjectALife/World/ALifeMapZones"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Fair = {
    adapters = {},
    defaults = { ring = 45, openExtra = 0, legacyRing = 70, grace = 10, despawn = 60, rural = 25, wild = 15, farm = 35, checkpoint = 150 },
    windowFallback = 76,
    diagonal = 1.3,
    edgeBand = 22,
    reachMargin = 8,
    reachFloor = 82,
    naturalFloor = 78,
    stagedReach = 30,
    bandWidth = 12,
    sightRange = 110,
    sightBudget = 80,
    sightWindowMs = 500,
    sightCacheMs = 4000,
    sightBlock = 3,
    sightCap = 400,
    coneHalfCos = 0.34,
    playerCacheMs = 200,
    trackMs = 300000,
    trackEveryMs = 5000,
    trackCap = 64,
    zoneCell = 16,
    zoneCap = 512,
    roadCell = 8,
    exitTiles = 200,
    exitMerge = 2,
    blockCells = 2,
    roadBudgetMs = 4,
    stageBucketHours = 6,
    logCap = 120,
    logGapMs = 20000,
    townTypes = { TownZone = true, TrailerPark = true },
    farmTypes = { Farm = true, FarmLand = true, Ranch = true, FarmForest = true },
    forestTypes = { Forest = true, DeepForest = true, PHForest = true, BirchForest = true,
        PRForest = true, OrganicForest = true },
    densityKeys = {
        farm = { "Spawn_FarmDensityPercent", 60 },
        forest = { "Spawn_WildernessDensityPercent", 30 },
        rural = { "Spawn_RuralDensityPercent", 50 },
    },
    guarded = { window_edge = true, render_out = true, outpost_expired = true },
    refusedAt = {},
    refusedCount = 0,
    ruralAllowed = {
        broken_car = true, car_crash = true, fishing_party = true, hunting_party = true,
        foraging_party = true, firewood_camp = true, camp_builders = true, water_run = true,
        outpost = true, safehouse_visit = true, raid = true, fullscale_raid = true,
        roamer = true,
    },
    densityExempt = { safehouse_visit = true },
    zones = {},
    zoneCount = 0,
    tracks = {},
    trackAtMs = {},
    sightCache = {},
    sightCount = 0,
    sightUsed = 0,
    sightWindowAt = -1e9,
    playerRows = nil,
    playerAtMs = -1e9,
    stageMemo = {},
    stageMemoCount = 0,
    logged = 0,
    logAt = {},
    roadSet = nil,
    roadBuild = nil,
    roadMissing = false,
    metrics = {
        spawnRefusedNearPlayer = 0, spawnDeferredSight = 0, hydratedAtRing = 0, hydratedInside = 0,
        hydratedNatural = 0, graceAllowed = 0, despawnRefusedSight = 0, despawnRefusedNear = 0,
        ruralRollsCut = 0, checkpointRefused = 0, minNaturalHydrate = -1, sightRays = 0, sightUnknown = 0,
    },
    reasons = {},
}
ProjectALife.SpawnFairness = Fair

function Fair.reset()
    Fair.zones, Fair.zoneCount = {}, 0
    Fair.tracks, Fair.trackAtMs = {}, {}
    Fair.sightCache, Fair.sightCount, Fair.sightUsed, Fair.sightWindowAt = {}, 0, 0, -1e9
    Fair.playerRows, Fair.playerAtMs = nil, -1e9
    Fair.stageMemo, Fair.stageMemoCount = {}, 0
    Fair.refusedAt, Fair.refusedCount = {}, 0
    Fair.logged, Fair.logAt = 0, {}
    Fair.metrics = {
        spawnRefusedNearPlayer = 0, spawnDeferredSight = 0, hydratedAtRing = 0, hydratedInside = 0,
        hydratedNatural = 0, graceAllowed = 0, despawnRefusedSight = 0, despawnRefusedNear = 0,
        ruralRollsCut = 0, checkpointRefused = 0, minNaturalHydrate = -1, sightRays = 0, sightUnknown = 0,
    }
    Fair.reasons = {}
    Fair.roadSet, Fair.roadBuild, Fair.roadMissing = nil, nil, false
end

function Fair.nowMs()
    if type(Fair.adapters.nowMs) == "function" then return tonumber(Fair.adapters.nowMs()) or 0 end
    return Gate.nowMs()
end

function Fair.enabled()
    return Gate.flag("Spawn_FairnessEnabled", true)
end

function Fair.baseRing()
    local ring = Gate.number("Spawn_PlayerKeepOutTiles", Fair.defaults.ring, 20, 150)
    if ring == Fair.defaults.legacyRing then return Fair.defaults.ring end
    return ring
end

function Fair.despawnMin()
    return Gate.number("Spawn_DespawnMinTiles", Fair.defaults.despawn, 0, 200)
end

function Fair.checkpointMin()
    return Gate.number("Spawn_CheckpointMinTiles", Fair.defaults.checkpoint, 0, 400)
end

function Fair.count(reason)
    reason = tostring(reason)
    Fair.reasons[reason] = (Fair.reasons[reason] or 0) + 1
end

function Fair.logOpen(kind)
    if Fair.logged >= Fair.logCap then return false end
    local last = Fair.logAt[kind]
    if last == nil then return true end
    local now = Fair.nowMs()
    return not (now >= last and now - last < Fair.logGapMs)
end

function Fair.log(kind, text)
    if Fair.logged >= Fair.logCap then return end
    local now = Fair.nowMs()
    local last = Fair.logAt[kind]
    if last ~= nil and now >= last and now - last < Fair.logGapMs then return end
    Fair.logAt[kind] = now
    Fair.logged = Fair.logged + 1
    print("[ALIFE-SPAWN] " .. tostring(kind) .. " " .. tostring(text))
end

function Fair.zoneTypes(x, y)
    if type(Fair.adapters.zoneTypes) == "function" then return Fair.adapters.zoneTypes(x, y) or {} end
    local list = {}
    if type(getWorld) ~= "function" then return list end
    pcall(function()
        local world = getWorld()
        local grid = world ~= nil and world.getMetaGrid ~= nil and world:getMetaGrid() or nil
        if grid == nil or grid.getZonesAt == nil then return end
        local zones = grid:getZonesAt(math.floor(x), math.floor(y), 0)
        if zones == nil or zones.size == nil or zones.get == nil then return end
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            if zone ~= nil and zone.getType ~= nil then list[#list + 1] = tostring(zone:getType()) end
        end
    end)
    return list
end

function Fair.classify(types)
    local town, farm, forest = false, false, false
    for _, name in ipairs(types) do
        if Fair.townTypes[name] then town = true
        elseif Fair.farmTypes[name] then farm = true
        elseif Fair.forestTypes[name] then forest = true end
    end
    if town then return "town" end
    if farm then return "farm" end
    if forest then return "forest" end
    return "rural"
end

function Fair.kindAt(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return "town" end
    local size = Fair.zoneCell
    local key = math.floor(x / size) .. ":" .. math.floor(y / size)
    local kind = Fair.zones[key]
    if kind ~= nil then return kind end
    kind = Fair.classify(Fair.zoneTypes(x, y))
    if Fair.zoneCount >= Fair.zoneCap then Fair.zones, Fair.zoneCount = {}, 0 end
    Fair.zones[key] = kind
    Fair.zoneCount = Fair.zoneCount + 1
    return kind
end

function Fair.density(x, y)
    if not Fair.enabled() then return 1 end
    local kind = Fair.kindAt(x, y)
    if kind == "town" then return 1 end
    local row = Fair.densityKeys[kind] or Fair.densityKeys.rural
    return Gate.number(row[1], row[2], 0, 100) / 100
end

function Fair.encounterFactor(id, x, y)
    if Fair.densityExempt[tostring(id)] == true then return 1 end
    return Fair.density(x, y)
end

function Fair.typeAllowed(id, kind)
    if not Fair.enabled() or kind == "town" or kind == nil then return true end
    return Fair.ruralAllowed[tostring(id)] == true
end

function Fair.noteCut(reason)
    Fair.metrics.ruralRollsCut = Fair.metrics.ruralRollsCut + 1
    Fair.count(reason)
end

function Fair.densityPass(x, y, roll)
    local factor = Fair.density(x, y)
    if factor >= 1 then return true end
    if (tonumber(roll) or 0) < factor then return true end
    Fair.noteCut("rural_density")
    return false
end

function Fair.forwardOf(player)
    if player == nil or type(player.getForwardDirection) ~= "function" then return nil, nil end
    local forward = player:getForwardDirection()
    if forward == nil or forward.getX == nil or forward.getY == nil then return nil, nil end
    local fx, fy = tonumber(forward:getX()), tonumber(forward:getY())
    if fx == nil or fy == nil or fx * fx + fy * fy < 0.000001 then return nil, nil end
    return fx, fy
end

function Fair.players()
    if type(Fair.adapters.players) == "function" then return Fair.adapters.players() or {} end
    local now = Fair.nowMs()
    if Fair.playerRows ~= nil and now >= Fair.playerAtMs and now - Fair.playerAtMs < Fair.playerCacheMs then
        return Fair.playerRows
    end
    local rows = {}
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil then
        for index, player in ipairs(locator.list() or {}) do
            local at = locator.position(player)
            if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
                local row = { x = tonumber(at.x), y = tonumber(at.y), z = tonumber(at.z) or 0,
                    player = player, index = index }
                local ok, fx, fy = pcall(Fair.forwardOf, player)
                if ok then row.fx, row.fy = fx, fy end
                if type(player.getVehicle) == "function" then row.driving = player:getVehicle() ~= nil end
                rows[#rows + 1] = row
            end
        end
    end
    Fair.playerRows, Fair.playerAtMs = rows, now
    return rows
end

function Fair.nearest(x, y)
    local best, row = math.huge, nil
    for _, p in ipairs(Fair.players()) do
        local dx, dy = x - p.x, y - p.y
        local d = dx * dx + dy * dy
        if d < best then best, row = d, p end
    end
    return row, math.sqrt(best)
end

function Fair.minutesSurvived(p)
    if type(Fair.adapters.minutesSurvived) == "function" then return Fair.adapters.minutesSurvived(p) end
    local player = type(p) == "table" and p.player or nil
    if player ~= nil and type(player.getHoursSurvived) == "function" then
        local hours = tonumber(player:getHoursSurvived())
        if hours ~= nil then return hours * 60 end
    end
    return nil
end

function Fair.graceActive(points)
    local minutes = Gate.number("Spawn_StartGraceMinutes", Fair.defaults.grace, 0, 240)
    if minutes <= 0 then return false end
    for _, p in ipairs(points or Fair.players()) do
        local survived = Fair.minutesSurvived(p)
        if survived ~= nil and survived < minutes then return true end
    end
    return false
end

function Fair.windowUsable(p, now)
    local population = ProjectALife.Population
    local band = (population ~= nil and tonumber(population.edgeRespawn) or 20) + 2
    local fallback = Fair.windowFallback - band
    if population == nil or type(population.windowBoundsAt) ~= "function" then return fallback end
    local ok, bounds = pcall(population.windowBoundsAt, now or Fair.nowMs())
    if not ok or type(bounds) ~= "table" or (tonumber(bounds.count) or 0) <= 0 then return fallback end
    local best
    for index = 1, bounds.count do
        local w = bounds[index]
        if p.x >= w[1] and p.x <= w[3] and p.y >= w[2] and p.y <= w[4] then
            local usable = math.min(p.x - w[1], w[3] - p.x, p.y - w[2], w[4] - p.y) - band
            if best == nil or usable > best then best = usable end
        end
    end
    if best == nil then return fallback end
    return math.max(10, best)
end

function Fair.windowCap(p, now)
    if type(Fair.adapters.windowCap) == "function" then return Fair.adapters.windowCap(p) end
    return math.max(40, math.floor(Fair.windowUsable(p, now) * Fair.diagonal))
end

function Fair.roll(limit)
    if type(Fair.adapters.roll) == "function" then return Fair.adapters.roll(limit) end
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

function Fair.bearing(fromX, fromY, toX, toY)
    local dx, dy = toX - fromX, toY - fromY
    if dx == 0 and dy == 0 then return nil end
    if type(math.atan2) == "function" then return math.atan2(dy, dx) end
    return math.atan(dy, dx)
end

function Fair.ringPoint(px, py, minimum, maximum, towardX, towardY)
    local p = Fair.nearest(px, py) or { x = px, y = py }
    local usable = Fair.windowUsable(p, Fair.nowMs())
    local base = towardX ~= nil and towardY ~= nil and Fair.bearing(px, py, towardX, towardY) or nil
    for attempt = 1, 32 do
        local angle = Fair.roll(6283) / 1000
        if base ~= nil and attempt <= 20 then angle = base + (Fair.roll(2001) / 1000 - 1) * 1.05 end
        local c, s = math.cos(angle), math.sin(angle)
        local limit = usable / math.max(math.abs(c), math.abs(s))
        local high = math.min(maximum, limit)
        if high >= minimum + 2 then
            local radius = minimum + 2 + Fair.roll(math.max(1, math.floor(high - minimum - 2) + 1))
            return { x = math.floor(px + c * radius), y = math.floor(py + s * radius), z = 0 }
        end
    end
    return nil
end

function Fair.ringAt(x, y)
    local ring = Fair.baseRing()
    if Fair.kindAt(x, y) ~= "town" then ring = ring + Fair.defaults.openExtra end
    return ring
end

function Fair.ringFor(p, now)
    now = now or Fair.nowMs()
    if p.ring ~= nil and p.ringX == p.x and p.ringY == p.y and p.ringAt ~= nil
            and now >= p.ringAt and now - p.ringAt < Fair.playerCacheMs then
        return p.ring
    end
    local ring = Fair.ringAt(p.x, p.y)
    local cap = Fair.windowCap(p, now)
    if ring > cap then ring = cap end
    p.ring, p.ringX, p.ringY, p.ringAt = ring, p.x, p.y, now
    return ring
end

function Fair.maxRing(list)
    local best = 0
    local now = Fair.nowMs()
    for _, p in ipairs(list or Fair.players()) do
        local ring = Fair.ringFor(p, now)
        if ring > best then best = ring end
    end
    if best <= 0 then best = Fair.baseRing() end
    return best
end

function Fair.band(x, y)
    local p = Fair.nearest(x, y)
    local ring = p ~= nil and Fair.ringFor(p, Fair.nowMs()) or Fair.baseRing()
    return ring, ring + Fair.bandWidth
end

function Fair.encounterMinimum(px, py)
    local low = Fair.band(px, py)
    return low
end

function Fair.encounterReach(px, py)
    local _, high = Fair.band(px, py)
    return high
end

function Fair.windowOk(x, y)
    if not Fair.enabled() then return true end
    local population = ProjectALife.Population
    if population == nil or type(population.windowEdge) ~= "function" then return true end
    local ok, edge = pcall(population.windowEdge, { x = x, y = y }, Fair.nowMs())
    if not ok or edge == nil then return true end
    return edge >= (tonumber(population.edgeRespawn) or 20)
end

function Fair.localSeen(x, y, z)
    if type(Fair.adapters.localSeen) == "function" then return Fair.adapters.localSeen(x, y, z) == true end
    if type(isServer) == "function" and isServer() then return false end
    if type(getCell) ~= "function" or type(getSpecificPlayer) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return false end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if square == nil or square.isCanSee == nil then return false end
    for index = 0, 3 do
        if getSpecificPlayer(index) ~= nil and square:isCanSee(index) == true then return true end
    end
    return false
end

function Fair.boxInsideRing(cx, cy, radius, options)
    if not Fair.enabled() then return false end
    options = options or {}
    local points = Fair.players()
    if #points == 0 then return false end
    if options.startGroup == true and Fair.graceActive(points) then return false end
    local now = Fair.nowMs()
    for _, p in ipairs(points) do
        local ring = Fair.ringFor(p, now)
        local inside = true
        for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
            local dx, dy = cx + corner[1] * radius + 0.5 - p.x, cy + corner[2] * radius + 0.5 - p.y
            if dx * dx + dy * dy >= ring * ring then inside = false end
        end
        if inside then return true end
    end
    return false
end

function Fair.inCone(p, x, y)
    if p.fx == nil or p.fy == nil then return true end
    local keep = ProjectALife.KeepOut
    if keep == nil or type(keep.inCone) ~= "function" then return true end
    return keep.inCone(p.x, p.y, p.fx, p.fy, x, y, Fair.coneHalfCos, Fair.sightRange)
end

function Fair.rayClear(x, y, z, p, wide)
    local now = Fair.nowMs()
    local block = Fair.sightBlock
    local key = tostring(p.index or 0) .. ":" .. math.floor(x / block) .. ":" .. math.floor(y / block)
        .. ":" .. math.floor(z)
    local cached = Fair.sightCache[key]
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Fair.sightCacheMs then
        return cached.seen, false
    end
    if now < Fair.sightWindowAt or now - Fair.sightWindowAt >= Fair.sightWindowMs then
        Fair.sightWindowAt, Fair.sightUsed = now, 0
    end
    if Fair.sightUsed >= Fair.sightBudget then return true, true end
    Fair.sightUsed = Fair.sightUsed + 1
    Fair.metrics.sightRays = Fair.metrics.sightRays + 1
    local answer
    if type(Fair.adapters.ray) == "function" then
        answer = Fair.adapters.ray(p, x, y, z)
    else
        local sight = ProjectALife.Sight
        if sight ~= nil and type(sight.between) == "function" then
            answer = sight.between(p.x, p.y, p.z or 0, x, y, z)
        end
    end
    local seen = false
    if answer == nil then
        Fair.metrics.sightUnknown = Fair.metrics.sightUnknown + 1
    else
        seen = answer ~= "blocked" and answer ~= "door"
    end
    if Fair.sightCount >= Fair.sightCap then Fair.sightCache, Fair.sightCount = {}, 0 end
    Fair.sightCache[key] = { seen = seen, atMs = now }
    Fair.sightCount = Fair.sightCount + 1
    return seen, false
end

function Fair.seenBy(x, y, z, p, wide)
    local dx, dy = x - p.x, y - p.y
    local limit = Fair.sightRange
    if dx * dx + dy * dy > limit * limit then return false, false end
    if not wide and not Fair.inCone(p, x, y) then return false, false end
    return Fair.rayClear(x, y, z, p, wide)
end

function Fair.engineSight()
    if type(Fair.adapters.ray) == "function" then return false end
    if type(isServer) == "function" and isServer() then return false end
    if type(isClient) == "function" and isClient() then return false end
    return type(getCell) == "function" and type(getSpecificPlayer) == "function"
end

function Fair.seen(x, y, z, points, wide, placing)
    if Fair.localSeen(x, y, z) then return true, false end
    if Fair.engineSight() then return false, false end
    for _, p in ipairs(points or Fair.players()) do
        local any = wide == true and not (placing == true and p.fx ~= nil and p.fy ~= nil)
        local seen, deferred = Fair.seenBy(x, y, z, p, any)
        if seen then return true, deferred end
    end
    return false, false
end

function Fair.ringRows(options)
    options = options or {}
    if not Fair.enabled() or options.fairness == false or options.stationed == true then return nil end
    local points = Fair.players()
    if #points == 0 then return nil end
    if options.startGroup == true and Fair.graceActive(points) then return nil end
    local now = Fair.nowMs()
    local rows = {}
    for index, p in ipairs(points) do
        local ring = Fair.ringFor(p, now)
        rows[index] = { x = p.x, y = p.y, r2 = ring * ring }
    end
    return rows
end

function Fair.refusal(position, options)
    options = options or {}
    if not Fair.enabled() or options.fairness == false then return nil end
    local points = Fair.players()
    if #points == 0 then return nil end
    if options.startGroup == true and Fair.graceActive(points) then
        Fair.metrics.graceAllowed = Fair.metrics.graceAllowed + 1
        return nil
    end
    local x, y, z = tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.z) or 0
    local stationed = options.stationed == true
    if not stationed then
        local now = Fair.nowMs()
        for _, p in ipairs(points) do
            local dx, dy = x - p.x, y - p.y
            local ring = Fair.ringFor(p, now)
            if dx * dx + dy * dy < ring * ring then
                Fair.metrics.spawnRefusedNearPlayer = Fair.metrics.spawnRefusedNearPlayer + 1
                Fair.count("fair_ring")
                if Fair.logOpen("spawn_refused") then
                    Fair.log("spawn_refused", "reason=fair_ring x=" .. tostring(math.floor(x)) .. " y=" .. tostring(math.floor(y))
                        .. " d=" .. tostring(math.floor(math.sqrt(dx * dx + dy * dy))) .. " ring=" .. tostring(ring))
                end
                return "fair_ring"
            end
        end
    end
    local seen, deferred = Fair.seen(x, y, z, points, not stationed, true)
    if seen then
        Fair.metrics.spawnDeferredSight = Fair.metrics.spawnDeferredSight + 1
        local why = deferred and "fair_budget" or "fair_sight"
        Fair.count(why)
        if Fair.logOpen("spawn_deferred") then
            Fair.log("spawn_deferred", "reason=" .. why .. " x=" .. tostring(math.floor(x)) .. " y=" .. tostring(math.floor(y)))
        end
        return why
    end
    return nil
end

function Fair.actorMode(actor, exempt, stationed)
    if not Fair.enabled() then return "off" end
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory ~= nil then
        if memory.debugSpawn == true or memory.adminAnchor == true or type(memory.admin) == "table"
                or type(memory.visit) == "table" or type(memory.guest) == "table"
                or memory.supportRole == "backup" or memory.role == "backup"
                or memory.supportForGroupId ~= nil then
            return "off"
        end
        local ordered = memory.orderedTo
        if type(ordered) == "table" and ordered.kind == "follow" then return "off" end
        if memory.startGroup == true and Fair.graceActive(Fair.players()) then return "off" end
        if memory.encounter ~= nil or memory.persistent == true then return "stationed" end
    end
    if exempt == true or stationed == true then return "stationed" end
    return "natural"
end

function Fair.stagedMember(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    return memory ~= nil and memory.squadId ~= nil and memory.stageOperationId ~= nil
end

function Fair.hydrateReach(actor, base, exempt, stationed, position)
    local mode = Fair.actorMode(actor, exempt, stationed)
    local staged = mode == "stationed" and exempt ~= true and Fair.stagedMember(actor)
    if mode ~= "natural" and not staged then return base end
    local at = position or (type(actor) == "table" and actor.worldPosition) or nil
    if type(at) ~= "table" then return base end
    local p = Fair.nearest(tonumber(at.x) or 0, tonumber(at.y) or 0)
    if p == nil then return base end
    local ring = Fair.ringFor(p, Fair.nowMs())
    return math.max(base, ring + (staged and Fair.stagedReach or Fair.reachMargin), staged and 0 or Fair.naturalFloor)
end

function Fair.noteHydrate(actor, position, mode)
    if mode ~= "natural" or type(position) ~= "table" then return end
    local p, distance = Fair.nearest(tonumber(position.x) or 0, tonumber(position.y) or 0)
    if p == nil then return end
    local m = Fair.metrics
    m.hydratedNatural = m.hydratedNatural + 1
    if m.minNaturalHydrate < 0 or distance < m.minNaturalHydrate then m.minNaturalHydrate = distance end
    local ring = Fair.ringFor(p, Fair.nowMs())
    if distance + 0.5 >= ring then
        m.hydratedAtRing = m.hydratedAtRing + 1
    else
        m.hydratedInside = m.hydratedInside + 1
    end
    if Fair.logOpen("hydrate") then
        Fair.log("hydrate", "uid=" .. tostring(actor and actor.uid) .. " d=" .. tostring(math.floor(distance))
            .. " ring=" .. tostring(ring) .. " kind=" .. Fair.kindAt(position.x, position.y))
    end
end

function Fair.protected(position)
    local points = Fair.players()
    if #points == 0 then return nil end
    local x, y, z = tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.z) or 0
    local minimum = Fair.despawnMin()
    for _, p in ipairs(points) do
        local dx, dy = x - p.x, y - p.y
        if dx * dx + dy * dy < minimum * minimum then return "near" end
    end
    local seen = Fair.seen(x, y, z, points, true)
    if seen then return "sight" end
    return nil
end

function Fair.engineEdge(position)
    local population = ProjectALife.Population
    if population == nil or type(population.windowEdge) ~= "function" then return nil end
    local ok, edge = pcall(population.windowEdge, position, Fair.nowMs())
    if not ok then return nil end
    return edge
end

function Fair.dehydrateRefusal(position, reason, uid)
    if not Fair.enabled() or Fair.guarded[tostring(reason)] ~= true or type(position) ~= "table" then return nil end
    local why = Fair.protected(position)
    if why == nil then return nil end
    if reason == "window_edge" then
        local population = ProjectALife.Population
        local floor = population ~= nil and tonumber(population.edgeFloor) or 8
        local edge = Fair.engineEdge(position)
        if edge ~= nil and edge < floor then return nil end
    end
    local now = Fair.nowMs()
    local last = Fair.refusedAt[tostring(uid)]
    Fair.refusedAt[tostring(uid)] = now
    if Fair.refusedCount >= 256 then Fair.refusedAt, Fair.refusedCount = {}, 0 end
    if last == nil then Fair.refusedCount = Fair.refusedCount + 1 end
    if last == nil or now < last or now - last > 5000 then
        local m = Fair.metrics
        if why == "near" then m.despawnRefusedNear = m.despawnRefusedNear + 1
        else m.despawnRefusedSight = m.despawnRefusedSight + 1 end
        Fair.count("despawn_" .. why)
        if Fair.logOpen("despawn_refused") then
            Fair.log("despawn_refused", "uid=" .. tostring(uid) .. " reason=" .. tostring(reason) .. " why=" .. why)
        end
    end
    return "despawn_refused_" .. why
end

function Fair.mayRemove(position)
    if not Fair.enabled() or type(position) ~= "table" then return true end
    local why = Fair.protected(position)
    if why == nil then return true end
    local m = Fair.metrics
    if why == "near" then m.despawnRefusedNear = m.despawnRefusedNear + 1
    else m.despawnRefusedSight = m.despawnRefusedSight + 1 end
    Fair.count("remove_" .. why)
    return false
end

function Fair.stageAllowed(squad, hours)
    return true
end

function Fair.noteTick(located, now)
    now = tonumber(now) or Fair.nowMs()
    if type(located) == "table" then
        for index, at in ipairs(located) do
            local last = Fair.trackAtMs[index]
            if last == nil or now < last or now - last >= Fair.trackEveryMs then
                Fair.trackAtMs[index] = now
                local list = Fair.tracks[index]
                if list == nil then list = {}; Fair.tracks[index] = list end
                list[#list + 1] = { x = tonumber(at.x) or 0, y = tonumber(at.y) or 0, atMs = now }
                while #list > Fair.trackCap do table.remove(list, 1) end
            end
        end
    end
    if Fair.roadSet == nil and not Fair.roadMissing then Fair.buildRoads(Fair.roadBudgetMs) end
end

function Fair.recentTrack(index)
    return Fair.tracks[index] or {}
end

function Fair.buildRoads(budgetMs)
    if Fair.roadSet ~= nil and Fair.roadBuild == nil then return true end
    local zones = ProjectALife.MapZones
    local chunks = zones ~= nil and type(zones.roads) == "table" and zones.roads or nil
    if chunks == nil then
        Fair.roadSet, Fair.roadMissing = {}, true
        return true
    end
    local build = Fair.roadBuild
    if build == nil then
        build = { chunk = 1, set = {} }
        Fair.roadBuild = build
    end
    local size = Fair.roadCell
    local started = Fair.nowMs()
    while build.chunk <= #chunks do
        for x, y, w, h in string.gmatch(chunks[build.chunk], "(%-?%d+),(%-?%d+),(%d+),(%d+)") do
            x, y, w, h = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
            local cx1, cx2 = math.floor(x / size), math.floor((x + w - 1) / size)
            local cy1, cy2 = math.floor(y / size), math.floor((y + h - 1) / size)
            for cx = cx1, cx2 do
                for cy = cy1, cy2 do build.set[Fair.cellKey(cx, cy)] = true end
            end
        end
        build.chunk = build.chunk + 1
        if Fair.nowMs() - started >= (tonumber(budgetMs) or 4) then
            if build.chunk <= #chunks then return false end
        end
    end
    Fair.roadSet, Fair.roadBuild = build.set, nil
    return true
end

function Fair.cellKey(cx, cy)
    return (cx + 1024) * 16384 + (cy + 1024)
end

function Fair.roadExits(x, y)
    if type(Fair.adapters.roadExits) == "function" then return Fair.adapters.roadExits(x, y) end
    if Fair.roadSet == nil or Fair.roadBuild ~= nil then return nil, "road_index_pending" end
    if Fair.roadMissing then return nil, "road_data_missing" end
    local set, size = Fair.roadSet, Fair.roadCell
    local cx, cy = math.floor(x / size), math.floor(y / size)
    local found = false
    for dx = -2, 2 do
        for dy = -2, 2 do
            if set[Fair.cellKey(cx + dx, cy + dy)] then found = true end
        end
    end
    if not found then return nil, "off_road_data" end
    local cut = Fair.blockCells
    local limit = math.ceil(Fair.exitTiles / size)
    local starts = {}
    for dx = -cut - 1, cut + 1 do
        for dy = -cut - 1, cut + 1 do
            if math.max(math.abs(dx), math.abs(dy)) == cut + 1 and set[Fair.cellKey(cx + dx, cy + dy)] then
                local touches = false
                for ox = -1, 1 do
                    for oy = -1, 1 do
                        local ix, iy = dx + ox, dy + oy
                        if math.max(math.abs(ix), math.abs(iy)) <= cut and set[Fair.cellKey(cx + ix, cy + iy)] then
                            touches = true
                        end
                    end
                end
                if touches then starts[#starts + 1] = { cx + dx, cy + dy } end
            end
        end
    end
    local label, closed, opened = {}, 0, 0
    local components = {}
    for _, cell in ipairs(starts) do
        local key = Fair.cellKey(cell[1], cell[2])
        if label[key] == nil then
            local id = #components + 1
            local component = { open = false }
            components[id] = component
            label[key] = id
            local queueX, queueY, head = { cell[1] }, { cell[2] }, 1
            while head <= #queueX do
                local qx, qy = queueX[head], queueY[head]
                head = head + 1
                if math.max(math.abs(qx - cx), math.abs(qy - cy)) >= limit then
                    component.open = true
                else
                    for dx = -1, 1 do
                        for dy = -1, 1 do
                            if dx ~= 0 or dy ~= 0 then
                                local nx, ny = qx + dx, qy + dy
                                local nkey = Fair.cellKey(nx, ny)
                                if set[nkey] and label[nkey] == nil
                                        and math.max(math.abs(nx - cx), math.abs(ny - cy)) > cut then
                                    label[nkey] = id
                                    queueX[#queueX + 1], queueY[#queueY + 1] = nx, ny
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, component in ipairs(components) do
        if component.open then opened = opened + 1 else closed = closed + 1 end
    end
    local crossings, used = 0, {}
    for index = 1, #starts do
        if not used[index] then
            crossings = crossings + 1
            used[index] = true
            local stack = { index }
            while #stack > 0 do
                local current = table.remove(stack)
                for other = 1, #starts do
                    if not used[other]
                            and math.abs(starts[other][1] - starts[current][1]) <= Fair.exitMerge
                            and math.abs(starts[other][2] - starts[current][2]) <= Fair.exitMerge then
                        used[other] = true
                        stack[#stack + 1] = other
                    end
                end
            end
        end
    end
    return crossings, closed
end

function Fair.checkpointRefusal(point, options)
    options = options or {}
    if not Fair.enabled() or options.fairness == false or type(point) ~= "table" then return nil end
    local x, y = tonumber(point.x) or 0, tonumber(point.y) or 0
    local minimum = Fair.checkpointMin()
    local why
    if minimum > 0 then
        for _, p in ipairs(Fair.players()) do
            local dx, dy = x - p.x, y - p.y
            if dx * dx + dy * dy < minimum * minimum then why = "cp_near_player" break end
        end
        if why == nil then
            local now = Fair.nowMs()
            for index, list in pairs(Fair.tracks) do
                for _, sample in ipairs(list) do
                    if now >= sample.atMs and now - sample.atMs <= Fair.trackMs then
                        local dx, dy = x - sample.x, y - sample.y
                        if dx * dx + dy * dy < minimum * minimum then why = "cp_player_track" break end
                    end
                end
                if why ~= nil then break end
            end
        end
        if why == nil then
            local policy = ProjectALife.SpawnPolicy
            if policy ~= nil and type(policy.inPlayerBase) == "function"
                    and policy.inPlayerBase({ x = x, y = y, z = 0 }, minimum) then
                why = "cp_near_base"
            end
        end
    end
    if why == nil then
        local exits, closed = Fair.roadExits(x, y)
        if exits == nil then why = "cp_" .. tostring(closed)
        elseif exits < 2 then why = exits == 0 and "cp_dead_end" or "cp_single_exit"
        elseif (tonumber(closed) or 0) > 0 then why = "cp_pocket" end
    end
    if why ~= nil then
        Fair.metrics.checkpointRefused = Fair.metrics.checkpointRefused + 1
        Fair.count(why)
        if Fair.logOpen("checkpoint_refused") then
            Fair.log("checkpoint_refused", "x=" .. tostring(math.floor(x)) .. " y=" .. tostring(math.floor(y)) .. " why=" .. why)
        end
    end
    return why
end

function Fair.siteMayExpire(x, y, z)
    if not Fair.enabled() then return true end
    return Fair.mayRemove({ x = x, y = y, z = z or 0 })
end

function Fair.topReasons(limit)
    local keys = {}
    for key in pairs(Fair.reasons) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if Fair.reasons[a] ~= Fair.reasons[b] then return Fair.reasons[a] > Fair.reasons[b] end
        return a < b
    end)
    local parts = {}
    for index = 1, math.min(#keys, limit or 8) do parts[#parts + 1] = keys[index] .. ":" .. Fair.reasons[keys[index]] end
    if #parts == 0 then return "-" end
    return table.concat(parts, ",")
end

function Fair.qaLine()
    local m = Fair.metrics
    return "[ALIFE-QA] spawnFairness on=" .. tostring(Fair.enabled() and 1 or 0)
        .. " ring=" .. tostring(Fair.baseRing()) .. " rural=" .. tostring(Gate.number("Spawn_RuralDensityPercent", Fair.defaults.rural, 0, 100))
        .. " wild=" .. tostring(Gate.number("Spawn_WildernessDensityPercent", Fair.defaults.wild, 0, 100))
        .. " farm=" .. tostring(Gate.number("Spawn_FarmDensityPercent", Fair.defaults.farm, 0, 100))
        .. " despawnMin=" .. tostring(Fair.despawnMin()) .. " checkpointMin=" .. tostring(Fair.checkpointMin())
        .. " graceMin=" .. tostring(Gate.number("Spawn_StartGraceMinutes", Fair.defaults.grace, 0, 240))
        .. " spawnRefusedNearPlayer=" .. tostring(m.spawnRefusedNearPlayer)
        .. " spawnDeferredSight=" .. tostring(m.spawnDeferredSight)
        .. " hydratedAtRing=" .. tostring(m.hydratedAtRing)
        .. " hydratedInside=" .. tostring(m.hydratedInside)
        .. " minNaturalHydrate=" .. tostring(math.floor(m.minNaturalHydrate))
        .. " graceAllowed=" .. tostring(m.graceAllowed)
        .. " despawnRefusedSight=" .. tostring(m.despawnRefusedSight)
        .. " despawnRefusedNear=" .. tostring(m.despawnRefusedNear)
        .. " ruralRollsCut=" .. tostring(m.ruralRollsCut)
        .. " checkpointRefused=" .. tostring(m.checkpointRefused)
        .. " rays=" .. tostring(m.sightRays)
        .. " reasons=" .. Fair.topReasons(8)
end

return Fair
