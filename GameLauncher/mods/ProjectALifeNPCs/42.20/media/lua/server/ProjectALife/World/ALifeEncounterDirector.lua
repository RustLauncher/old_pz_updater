require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/Records/ALifePartyPolicy"
ProjectALife = ProjectALife or {}

require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/World/ALifeRoads"
require "ProjectALife/World/ALifePOI"
require "ProjectALife/Movement/ALifeUpperPosts"
require "ProjectALife/World/ALifeEncounterLog"
require "ProjectALife/World/ALifeWreck"
require "ProjectALife/World/ALifeVehicleOdometer"
require "ProjectALife/World/ALifeWorldPressure"
require "ProjectALife/Activities/ALifeFishing"

local Director = {
    settings = {

        intervalMinutes = 60,
        chance = 0.25,

        minRadius = 55,
        maxRadius = 110,

        attempts = 8,

        earlyHours = 72,
        earlyChanceScale = 2.0,

        aheadCos = 0.35,

        streetRun = 3,

        warmMs = 60000,

        blockadeRoadRun = 20,
        blockadeRoadWidth = 18,
    },

    adapters = {},
    enabled = true,
    nextRollAtHours = 0,

    metrics = { rolls = 0, accepted = 0, spawned = 0, forfeits = 0 },

    refusals = {},

    placeRefusals = {},
    pending = {},
    lastOutcome = nil,
    lastRoll = {},

    seenAtMs = {},

    placing = {},
    printState = { lastMs = -1e9 },
}
ProjectALife.EncounterDirector = Director

local function nowMs()
    if type(Director.adapters.nowMs) == "function" then return Director.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    if type(Director.adapters.worldHours) == "function" then return Director.adapters.worldHours() end
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return tonumber(hours)
end

local function hourOfDay()
    if type(Director.adapters.hourOfDay) == "function" then return Director.adapters.hourOfDay() end
    local hour = 12
    pcall(function() hour = getGameTime():getHour() end)
    return hour
end

local function emit(category, fields)
    local telemetry = ProjectALife.Telemetry
    if telemetry ~= nil and type(telemetry.emit) == "function" then
        pcall(telemetry.emit, category, fields)
    end
end

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

function Director.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Director.settings[key] ~= nil and tonumber(value) ~= nil then
            Director.settings[key] = tonumber(value)
        end
    end
    if options.enabled ~= nil then Director.enabled = options.enabled ~= false end

    Director.settings.intervalMinutes = math.max(10, math.min(720,
        tonumber(Director.settings.intervalMinutes) or 60))
    return true
end

function Director.reset()
    Director.nextRollAtHours = 0
    Director.metrics = { rolls = 0, accepted = 0, spawned = 0, forfeits = 0 }
    Director.refusals = {}
    Director.placeRefusals = {}
    Director.pending = {}
    Director.rollPending = nil
    Director.lastOutcome = nil
    Director.lastRoll = {}
    Director.seenAtMs = {}
    Director.placing = {}
    Director.siteMetrics = { found = {}, none = {}, reads = 0 }
    Director.printState = { lastMs = -1e9 }
end

function Director.minimum(px, py)
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() then
        if px ~= nil and py ~= nil then return fairness.encounterMinimum(px, py) end
        return fairness.baseRing()
    end
    return tonumber(Director.settings.minRadius) or 55
end

function Director.attempts()
    local fairness = ProjectALife.SpawnFairness
    local base = tonumber(Director.settings.attempts) or 8
    if fairness ~= nil and fairness.enabled() then return math.max(base, 16) end
    return base
end

function Director.reach(px, py)
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() then
        if px ~= nil and py ~= nil then return fairness.encounterReach(px, py) end
        return fairness.baseRing() + fairness.bandWidth
    end
    local reach = tonumber(Director.settings.maxRadius) or 110
    local population = ProjectALife.Population
    local hydrate = population ~= nil and tonumber(population.spawnDistance) or nil
    if hydrate ~= nil then reach = math.min(reach, hydrate - 10) end
    return math.max(tonumber(Director.settings.minRadius) or 55, math.floor(reach))
end

function Director.capacityLeft()
    local population = ProjectALife.Population
    if population == nil or type(population.capacityUsed) ~= "function" then return 8 end
    local cap = ProjectALife.Settings and ProjectALife.Settings.current
        and tonumber(ProjectALife.Settings.current.maximumHostileActors) or 32
    local used = 0
    pcall(function() used = tonumber(population.capacityUsed(false)) or 0 end)
    return math.max(0, math.floor(cap - used))
end

function Director.partySize(faction, definition, unit)
    local policy = ProjectALife.PartyPolicy
    local low = math.max(1, math.floor(tonumber(definition and definition.minCount) or 1))
    local high = math.min(8, math.max(low, math.floor(tonumber(definition and definition.maxCount) or 8)))
    local count = policy ~= nil and type(policy.choose) == "function"
        and policy.choose(faction, unit, 1, high) or 0
    if count <= 0 then return 0 end
    count = math.max(low, math.min(high, math.floor(count)))
    if policy ~= nil and type(policy.funnelClamp) == "function" then
        count = math.max(1, math.floor(tonumber(policy.funnelClamp(faction, count)) or count))
    end
    return count
end

function Director.anyPlayer()
    local player
    pcall(function() player = getSpecificPlayer(0) end)
    pcall(function()
        if player == nil and getOnlinePlayers ~= nil then
            local online = getOnlinePlayers()
            if online ~= nil and online:size() > 0 then
                player = online:get(roll(online:size()))
            end
        end
    end)
    if player == nil then

        for _ in pairs(Director.seenAtMs) do
            Director.seenAtMs = {}
            break
        end
        return nil
    end
    if player.getCurrentSquare ~= nil and player:getCurrentSquare() == nil then return nil end
    if Director.warming(player, nowMs()) then return nil end
    return player
end

function Director.warming(player, now)
    local warm = tonumber(Director.settings.warmMs)
    if warm == nil or warm <= 0 or player == nil then return false end
    local name, id
    if player.getUsername ~= nil then name = player:getUsername() end
    if player.getOnlineID ~= nil then id = player:getOnlineID() end
    local key = tostring(name or "sp") .. "#" .. tostring(id or "-")
    local seen = Director.seenAtMs[key]
    if seen == nil then
        Director.seenAtMs[key] = now
        return true
    end
    return now - seen < warm
end

local function inTown(x, y)
    local town = false
    pcall(function()
        local zones = getWorld():getMetaGrid():getZonesAt(x, y, 0)
        if zones == nil then return end
        for index = 0, zones:size() - 1 do
            local kind = tostring(zones:get(index):getType())
            if kind == "TownZone" or kind == "TrailerPark" then
                town = true
                return
            end
        end
    end)
    return town
end

local function townPoint(px, py)
    local point
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() then
        for _ = 1, 12 do
            local candidate = fairness.ringPoint(px, py, Director.minimum(px, py), Director.reach(px, py))
            if candidate ~= nil and inTown(candidate.x, candidate.y) then return candidate end
        end
        return nil
    end
    pcall(function()
        local reach = Director.reach(px, py)
        local zones = getWorld():getMetaGrid():getZonesIntersecting(
            math.floor(px - reach), math.floor(py - reach), 0,
            math.floor(reach * 2), math.floor(reach * 2))
        if zones == nil or zones:size() == 0 then return end
        local towns = {}
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            local kind = tostring(zone:getType())
            if kind == "TownZone" or kind == "TrailerPark" then
                towns[#towns + 1] = zone
            end
        end
        if #towns == 0 then return end
        local zone = towns[roll(#towns) + 1]
        local square = zone:getRandomSquareInZone()
        if square == nil then return end
        point = { x = square:getX(), y = square:getY(), z = 0 }
    end)
    return point
end

function Director.townNear(px, py)
    local near = false
    pcall(function()
        local reach = Director.reach(px, py)
        local inner = Director.minimum(px, py)
        local outer = reach + 20
        local zones = getWorld():getMetaGrid():getZonesIntersecting(
            math.floor(px - reach), math.floor(py - reach), 0,
            math.floor(reach * 2), math.floor(reach * 2))
        if zones == nil then return end
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            local kind = tostring(zone:getType())
            if kind == "TownZone" or kind == "TrailerPark" then
                if zone.getX == nil or zone.getY == nil
                        or zone.getWidth == nil or zone.getHeight == nil then
                    near = true
                    return
                end
                local x1, y1 = zone:getX(), zone:getY()
                local x2, y2 = x1 + zone:getWidth(), y1 + zone:getHeight()
                local nx = math.max(x1, math.min(px, x2)) - px
                local ny = math.max(y1, math.min(py, y2)) - py
                local fx = math.max(math.abs(x1 - px), math.abs(x2 - px))
                local fy = math.max(math.abs(y1 - py), math.abs(y2 - py))
                if nx * nx + ny * ny <= outer * outer
                        and fx * fx + fy * fy >= inner * inner then
                    near = true
                    return
                end
            end
        end
    end)
    return near
end

function Director.needsTown(definition)
    if type(definition) ~= "table" then return false end
    local placement = tostring(definition.placement or "town")
    if placement == "upper_building" then return true end
    if placement == "road" or placement == "poi" or placement == "building"
            or placement == "clearing" or placement == "shore" then
        return false
    end
    local classes = definition.locations
    if type(classes) ~= "table" or #classes == 0 then return false end
    for _, class in ipairs(classes) do
        if class ~= "city" then return false end
    end
    return true
end

local function ringPoint(px, py, minimum, maximum)
    local settings = Director.settings
    local low = math.floor(tonumber(minimum) or Director.minimum(px, py))
    local high = math.max(low, math.floor(tonumber(maximum) or Director.reach(px, py)))
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() then return fairness.ringPoint(px, py, low, high) end
    local radius = low + roll(math.max(1, high - low + 1))
    local angle = roll(6283) / 1000
    return { x = math.floor(px + math.cos(angle) * radius),
             y = math.floor(py + math.sin(angle) * radius), z = 0 }
end

local function insideRing(px, py, point)
    local dx, dy = point.x - px, point.y - py
    local flat = dx * dx + dy * dy
    local settings = Director.settings
    local outer = Director.reach(px, py) + 20
    local inner = Director.minimum(px, py)
    return flat >= inner * inner
        and flat <= outer * outer
end

Director.navMemoMs = 1500

function Director.navRoads(px, py, low, high)
    local now = nowMs()
    local key = math.floor(px) .. ":" .. math.floor(py) .. ":" .. low .. ":" .. high
    local memo = Director.navMemo
    if memo ~= nil and memo.key == key and now >= memo.atMs and now - memo.atMs < Director.navMemoMs then
        Director.metrics.navMemoHits = (Director.metrics.navMemoHits or 0) + 1
        return memo.roads
    end
    local roads = {}
    local zones = getWorld():getMetaGrid():getZonesIntersecting(
        math.floor(px - high), math.floor(py - high), 0,
        math.floor(high * 2), math.floor(high * 2))
    if zones ~= nil then
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            if tostring(zone:getType()) == "Nav" then roads[#roads + 1] = zone end
        end
    end
    Director.navMemo = { key = key, atMs = now, roads = roads }
    return roads
end

function Director.navPoint(px, py, minimum, maximum)
    local point
    pcall(function()
        local settings = Director.settings
        local low = math.floor(tonumber(minimum) or Director.minimum(px, py))
        local high = math.max(low, math.floor(tonumber(maximum) or Director.reach(px, py)))
        local roads = Director.navRoads(px, py, low, high)
        if #roads == 0 then return end
        for _ = 1, 12 do
            local zone = roads[roll(#roads) + 1]
            local w, h = math.max(1, math.floor(zone:getWidth())), math.max(1, math.floor(zone:getHeight()))
            local x, y = math.floor(zone:getX()) + roll(w), math.floor(zone:getY()) + roll(h)
            local dx, dy = x - px, y - py
            local flat = dx * dx + dy * dy
            if flat >= low * low and flat <= high * high then
                point = { x = x, y = y, z = 0 }
                return
            end
        end
    end)
    return point
end

function Director.streetFallback(road, square, cell, nav)
    if nav ~= nil or type(road.isStreetSquare) ~= "function" then return false end
    if not road.isStreetSquare(square, cell, Director.settings.streetRun) then return false end
    Director.metrics.roadStreet = (Director.metrics.roadStreet or 0) + 1
    return true
end

local function roadPoint(px, py, minimum, maximum, fx, fy)
    local point, fallback
    local aimed = tonumber(fx) ~= nil and tonumber(fy) ~= nil and (fx * fx + fy * fy) > 0.01
    pcall(function()
        local road = ProjectALife.Road
        if road == nil then return end
        local cell = getCell()
        if cell == nil then return end
        local metrics = Director.metrics
        for _ = 1, 24 do

            local nav = Director.navPoint(px, py, minimum, maximum)
            local candidate = nav or ringPoint(px, py, minimum, maximum)
            if candidate ~= nil then
                local square = cell:getGridSquare(
                    math.floor(candidate.x), math.floor(candidate.y), 0)

                if square == nil then
                    metrics.roadUnloaded = (metrics.roadUnloaded or 0) + 1
                elseif not road.isRoadSquare(square) and not Director.streetFallback(road, square, cell, nav) then
                    metrics.roadNotRoad = (metrics.roadNotRoad or 0) + 1
                else
                    local found = { x = candidate.x, y = candidate.y, z = 0 }
                    if not aimed then point = found return end
                    local dx, dy = candidate.x - px, candidate.y - py
                    local length = math.sqrt(dx * dx + dy * dy)
                    local ahead = length > 0.01 and ((dx * fx + dy * fy) / length)
                        >= (tonumber(Director.settings.aheadCos) or 0.35)
                    if ahead then point = found return end
                    fallback = fallback or found
                end
            end
        end
    end)
    if point == nil and fallback ~= nil then
        Director.metrics.roadBehind = (Director.metrics.roadBehind or 0) + 1
        return fallback
    end
    if point ~= nil and aimed then Director.metrics.roadAhead = (Director.metrics.roadAhead or 0) + 1 end
    return point
end

local function shorePoint(px, py)
    local zones = ProjectALife.MapZones
    if zones == nil or type(zones.each) ~= "function" then return nil end
    local low = Director.minimum(px, py)
    local high = Director.reach(px, py)
    local pick, seen = nil, 0
    zones.each("water", function(rect)
        local nx = math.max(rect.x, math.min(px, rect.x + rect.w))
        local ny = math.max(rect.y, math.min(py, rect.y + rect.h))
        local dx, dy = px - nx, py - ny
        local flat = math.sqrt(dx * dx + dy * dy)
        if flat >= low and flat <= high and rect.w * rect.h >= 64 then
            seen = seen + 1
            if roll(seen) == 0 then pick = { x = nx, y = ny, dx = dx / flat, dy = dy / flat } end
        end
    end)
    if pick == nil then return nil end
    return { x = math.floor(pick.x + pick.dx * 2), y = math.floor(pick.y + pick.dy * 2), z = 0 }
end

Director.siteReach = 36
Director.siteMetrics = { found = {}, none = {}, reads = 0 }

function Director.siteCount(kind, found)
    local bucket = found and Director.siteMetrics.found or Director.siteMetrics.none
    bucket[kind] = (bucket[kind] or 0) + 1
end

function Director.shoreSites(point, options)
    local fish = ProjectALife.ActivityFishing
    if fish == nil or type(fish.shoreSites) ~= "function" or type(getCell) ~= "function" then
        return nil, "no_shore_near"
    end
    local cell = getCell()
    if cell == nil then return nil, "no_shore_near" end
    options = type(options) == "table" and options or {}
    local ok, posts, reads = pcall(fish.shoreSites, cell, point.x, point.y, {
        count = options.count, fx = options.fx, fy = options.fy, z = math.floor(tonumber(point.z) or 0) })
    Director.siteMetrics.reads = Director.siteMetrics.reads + (tonumber(reads) or 0)
    if not ok or type(posts) ~= "table" or #posts == 0 then return nil, "no_shore_near" end
    return posts
end

function Director.openGround(cell, road, x, y, z)
    local square = cell:getGridSquare(x, y, z)
    if square == nil or square:isOutside() ~= true or square:getBuilding() ~= nil
            or square:isFree(true) ~= true then return false end
    if road ~= nil and road.isRoadSquare(square) then return false end
    for _, probe in ipairs({ { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 } }) do
        local near = cell:getGridSquare(x + probe[1], y + probe[2], z)
        if near ~= nil and near:getBuilding() ~= nil then return false end
    end
    return true
end

function Director.nearbySquares(point, limit, step, visit)
    local cell = getCell()
    if cell == nil then return nil end
    local cx, cy, z = math.floor(point.x), math.floor(point.y), math.floor(tonumber(point.z) or 0)
    for radius = 0, limit do
        local dense = radius <= 6
        if dense or radius % step == 0 then
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if math.max(math.abs(dx), math.abs(dy)) == radius and (dense or (dx + dy) % step == 0) then
                        local found = visit(cell, cx + dx, cy + dy, z)
                        if found ~= nil then return found end
                    end
                end
            end
        end
    end
    return nil
end

function Director.clearingVisit(cell, x, y, z)
    if Director.openGround(cell, ProjectALife.Road, x, y, z) then return { x = x + 0.5, y = y + 0.5, z = z } end
    return nil
end

function Director.roadVisit(cell, x, y, z)
    local road = ProjectALife.Road
    if road == nil or type(road.isRoadSquare) ~= "function" then return nil end
    local square = cell:getGridSquare(x, y, z)
    if square == nil or not road.isRoadSquare(square) then return nil end
    local point = { x = x + 0.5, y = y + 0.5, z = z }
    if Director.placing.sceneProbe == "blockade" and Director.blockadeRefusal(point) ~= nil then return nil end
    return point
end

function Director.buildingVisit(cell, x, y, z)
    local square = cell:getGridSquare(x, y, z)
    if square ~= nil and square:getBuilding() ~= nil then return { x = x + 0.5, y = y + 0.5, z = z } end
    return nil
end

function Director.upperVisit(cell, x, y, z)
    local square = cell:getGridSquare(x, y, z)
    if square == nil or square:getBuilding() == nil then return nil end
    local posts = ProjectALife.UpperPosts
    if posts == nil or type(posts.findUpperFloorPosts) ~= "function" then return nil end
    local found = posts.findUpperFloorPosts(x, y, 0, 4)
    if type(found) == "table" and #found > 0 then return { x = found[1].x, y = found[1].y, z = found[1].z } end
    return nil
end

function Director.townVisit(cell, x, y, z)
    if inTown(x, y) then return { x = x + 0.5, y = y + 0.5, z = z } end
    return nil
end

Director.siteVisits = {
    clearing = { visit = "clearingVisit", step = 2, none = "no_clearing_near" },
    road = { visit = "roadVisit", step = 2, none = "no_road_near" },
    building = { visit = "buildingVisit", step = 2, none = "no_building_near" },
    upper_building = { visit = "upperVisit", step = 2, none = "no_upper_floor_near" },
    town = { visit = "townVisit", step = 3, none = "no_town_near" },
}

function Director.siteSearch(definition, anchor, options)
    local placement = tostring(definition.placement or "town")
    options = type(options) == "table" and options or {}
    local reach = tonumber(options.reach) or Director.siteReach
    if placement == "shore" then
        local posts, why = Director.shoreSites(anchor, { count = options.count or 3, fx = options.fx, fy = options.fy })
        if posts == nil then return nil, why end
        return { x = posts[1].x, y = posts[1].y, z = posts[1].z, kind = placement, slots = posts }
    end
    if placement == "poi" then
        local poi = ProjectALife.POI
        if poi == nil or type(poi.search) ~= "function" then return nil, "no_poi_near" end
        local found = poi.search(anchor.x, anchor.y, reach * 2, definition.poi)
        if type(found) ~= "table" or #found == 0 then return nil, "no_poi_near" end
        local best, bestFlat
        for _, room in ipairs(found) do
            local flat = (room.x - anchor.x) ^ 2 + (room.y - anchor.y) ^ 2
            if bestFlat == nil or flat < bestFlat then best, bestFlat = room, flat end
        end
        return { x = best.x, y = best.y, z = best.z or 0, kind = placement }
    end
    local row = Director.siteVisits[placement]
    if row == nil then return nil, "no_site_rule" end
    Director.placing.sceneProbe = definition.scene
    local point = Director.nearbySquares(anchor, reach, row.step, Director[row.visit])
    Director.placing.sceneProbe = nil
    if point == nil then return nil, row.none end
    point.kind = placement
    return point
end

function Director.siteFor(definition, anchor, options)
    if type(definition) ~= "table" or type(anchor) ~= "table" then return nil, "no_site_rule" end
    local ok, site, why = pcall(Director.siteSearch, definition, anchor, options)
    local kind = tostring(definition.placement or "town")
    if not ok then
        Director.placing.sceneProbe = nil
        Director.siteCount(kind, false)
        return nil, "site_error"
    end
    Director.siteCount(kind, site ~= nil)
    return site, why
end

local function clearingPoint(px, py)
    local point
    pcall(function()
        local road = ProjectALife.Road
        local cell = getCell()
        if cell == nil then return end
        for _ = 1, 24 do
            local candidate = ringPoint(px, py)
            if candidate ~= nil and not inTown(candidate.x, candidate.y) then
                local square = cell:getGridSquare(
                    math.floor(candidate.x), math.floor(candidate.y), 0)
                local ok = square ~= nil and square:isOutside()
                    and square:getBuilding() == nil
                    and square:isFree(true)
                    and not (road ~= nil and road.isRoadSquare(square))
                if ok then

                    for _, probe in ipairs({ { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 } }) do
                        local near = cell:getGridSquare(
                            math.floor(candidate.x + probe[1]),
                            math.floor(candidate.y + probe[2]), 0)
                        if near ~= nil and near:getBuilding() ~= nil then
                            ok = false
                            break
                        end
                    end
                end
                if ok then
                    point = { x = candidate.x, y = candidate.y, z = 0 }
                    return
                end
            end
        end
    end)
    return point
end

local function upperPoint(px, py)
    local point
    pcall(function()
        local posts = ProjectALife.UpperPosts
        if posts == nil or type(posts.findUpperFloorPosts) ~= "function" then return end
        for _ = 1, 12 do
            local candidate = townPoint(px, py)

            if candidate ~= nil and insideRing(px, py, candidate) then
                local found = posts.findUpperFloorPosts(candidate.x, candidate.y, 0, 4)
                if type(found) == "table" and #found > 0 and insideRing(px, py, found[1]) then
                    point = { x = found[1].x, y = found[1].y, z = found[1].z }
                    return
                end
            end
        end
    end)
    return point
end

local function poiPoint(definition, px, py)
    local point
    pcall(function()
        local poi = ProjectALife.POI
        if poi == nil or type(poi.search) ~= "function" then return end
        local found = poi.search(px, py, Director.reach(px, py), definition.poi)
        if type(found) ~= "table" or #found == 0 then return end

        local ringed = {}
        for _, room in ipairs(found) do
            if insideRing(px, py, room) then ringed[#ringed + 1] = room end
        end
        if #ringed == 0 then return end
        local chosen = ringed[roll(math.min(#ringed, 4)) + 1] or ringed[1]
        point = { x = chosen.x, y = chosen.y, z = chosen.z or 0 }
    end)
    return point
end

Director.buildingTries = 16

function Director.buildingTry(px, py, cell)
    local candidate = townPoint(px, py) or ringPoint(px, py)
    if candidate ~= nil and insideRing(px, py, candidate) then
        local square = cell:getGridSquare(
            math.floor(candidate.x), math.floor(candidate.y), 0)
        if square ~= nil and square:getBuilding() ~= nil then
            return { x = candidate.x, y = candidate.y, z = 0 }
        end
    end
    return nil
end

local function buildingPoint(px, py)
    local gotCell, cell = pcall(getCell)
    if not gotCell or cell == nil then return nil end
    for _ = 1, Director.buildingTries do
        local ok, point = pcall(Director.buildingTry, px, py, cell)
        if not ok then return nil end
        if point ~= nil then return point end
    end
    return nil
end

function Director.refusePlacement(reason)
    reason = tostring(reason or "unknown")
    if Director.rollPending == nil then Director.lastRoll.refused = reason end
    Director.placeRefusals[reason] = (Director.placeRefusals[reason] or 0) + 1
end

Director.installations = {
    blockade = true, highway_ambush = true, rooftop_snipers = true,
    camp = true, outpost = true,
}

function Director.isInstallation(definition)
    return type(definition) == "table"
        and Director.installations[tostring(definition.id)] == true
end

local function validated(point, installation)

    local locks = ProjectALife.RegionLocks
    if locks ~= nil and type(locks.refuse) == "function" and locks.refuse(point.x, point.y) then
        Director.refusePlacement("region_locked")
        return nil
    end
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() and type(fairness.windowOk) == "function"
            and not fairness.windowOk(point.x, point.y) then
        Director.refusePlacement("fair_window")
        return nil
    end
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.check) ~= "function" then return point end
    local ok, reason = policy.check(point, { installation = installation == true })
    if ok then return point end
    if reason == "square_blocked" and type(policy.find) == "function" then
        local slid = policy.find(point, { searchRadius = 6, installation = installation == true })
        if slid ~= nil then return { x = slid.x, y = slid.y, z = slid.z } end
    end
    Director.refusePlacement(reason)
    return nil
end

function Director.parkingAt(x, y)
    if type(getVehicleZoneAt) ~= "function" then return false end
    local parking = false
    pcall(function()
        local zone = getVehicleZoneAt(x, y, 0)
        if zone == nil then return end
        local name = ""
        if type(zone.getName) == "function" then name = string.lower(tostring(zone:getName() or "")) end
        parking = name == "" or string.find(name, "parking", 1, true) ~= nil
    end)
    return parking
end

function Director.roadSegment(point)
    local road = ProjectALife.Road
    local cell = type(getCell) == "function" and getCell() or nil
    if road == nil or cell == nil or type(road.pavedRun) ~= "function" then return false, "blockade_no_road" end
    local x, y = math.floor(point.x), math.floor(point.y)
    local square = cell:getGridSquare(x, y, 0)
    if square == nil then return false, "blockade_unloaded" end
    if not road.isPavedSurface(square) then return false, "blockade_off_road" end
    local settings = Director.settings
    local runMin = math.max(2, math.floor(tonumber(settings.blockadeRoadRun) or 20))
    local widthMax = math.max(2, math.floor(tonumber(settings.blockadeRoadWidth) or 18))
    local span = math.max(runMin, widthMax + 1)
    local runX = road.pavedRun(cell, x, y, 0, 1, 0, span)
    local runY = road.pavedRun(cell, x, y, 0, 0, 1, span)
    local ax, ay
    if type(road.axisAt) == "function" then ax, ay = road.axisAt(square) end
    if ax == nil then
        if runX > runY then ax, ay = 1, 0
        elseif runY > runX then ax, ay = 0, 1
        else return false, "blockade_no_axis" end
    end
    local along, across = runY, runX
    if ax ~= 0 then along, across = runX, runY end
    if along < runMin then return false, "blockade_short_road" end
    if across > widthMax then return false, "blockade_wide_road" end
    for step = -7, 7 do
        if Director.parkingAt(x + ay * step, y + ax * step) then return false, "blockade_parking" end
    end
    for _, offset in ipairs({ -5, 5 }) do
        local qx, qy = x + ax * offset, y + ay * offset
        local probe = cell:getGridSquare(qx, qy, 0)
        if probe == nil or not road.isPavedSurface(probe) then return false, "blockade_short_road" end
        if road.pavedRun(cell, qx, qy, 0, ay, ax, widthMax + 1) > widthMax then
            return false, "blockade_wide_road"
        end
    end
    return true, ax, ay
end

function Director.blockadeRefusal(point)
    local kit = ProjectALife.SceneKit
    if kit ~= nil and type(kit.siteRefusal) == "function" then
        local refusal = kit.siteRefusal("blockade", point)
        if refusal ~= nil then return refusal end
    end
    local ok, reason = Director.roadSegment(point)
    if not ok then return reason end
    return nil
end

function Director.blockadeCapped(px, py)
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.capReached) ~= "function" then return false end
    return kit.capReached("blockade", px, py) == true
end

function Director.bindScene(spawnResult)
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.bind) ~= "function" or type(spawnResult) ~= "table" then return false end
    local plan = spawnResult.plan
    if type(plan) ~= "table" or plan.key == nil or spawnResult.groupId == nil then return false end
    return kit.bind(plan.key, spawnResult.groupId) == true
end

function Director.sceneUpkeep(now)
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.tick) ~= "function" then return 0 end
    local ok, removed = pcall(kit.tick, now)
    return ok and (tonumber(removed) or 0) or 0
end

Director.claimsBuilding = { building = true, poi = true, upper_building = true }

function Director.claimed(point)
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.claimBuilding) ~= "function" then return point end
    local ok, reason = policy.claimBuilding({ x = point.x, y = point.y, z = point.z or 0 })
    if ok == true then return point end
    Director.refusePlacement(reason or "building_claim")
    return nil
end

function Director.placeOpen(definition, px, py, fx, fy, early, claim)
    local classes = definition.locations
    if type(classes) ~= "table" or #classes == 0 then classes = { "anywhere" } end

    local townHere = Director.placing.townHere
    Director.placing.townHere = nil
    if townHere == false then
        local kept = {}
        for _, class in ipairs(classes) do
            if class ~= "city" then kept[#kept + 1] = class end
        end
        classes = #kept > 0 and kept or { "outside_city" }
    end
    local wanted = classes[roll(#classes) + 1]

    if early and wanted ~= "city" then
        for _, class in ipairs(classes) do
            if class == "city" then wanted = "city" break end
        end
    end

    local placement = tostring(definition.placement or "town")
    return { definition = definition, px = px, py = py, fx = fx, fy = fy, claim = claim,
        wanted = wanted, placement = placement, label = placement ~= "town" and placement or wanted,
        attempts = Director.attempts(), attempt = 0, inner = 0, units = 0 }
end

function Director.placeAttemptPoint(job)
    local placement, px, py = job.placement, job.px, job.py
    local definition, wanted = job.definition, job.wanted
    local point
    if placement == "road" then
        point = roadPoint(px, py, nil, nil, job.fx, job.fy)
    elseif placement == "upper_building" then
        point = upperPoint(px, py)
    elseif placement == "poi" then
        point = poiPoint(definition, px, py)
    elseif placement == "building" then
        point = buildingPoint(px, py)
    elseif placement == "clearing" then
        point = clearingPoint(px, py)
    elseif placement == "shore" then
        point = shorePoint(px, py)
    elseif wanted == "city" then
        point = townPoint(px, py)
        if point ~= nil and not insideRing(px, py, point) then point = nil end
    else
        point = ringPoint(px, py)
        if wanted == "outside_city" and point ~= nil
                and inTown(point.x, point.y) then
            point = nil
        end
    end
    return point
end

function Director.placeAttemptEnd(job, point)
    local definition, placement, claim = job.definition, job.placement, job.claim
    if point ~= nil then point = validated(point, Director.isInstallation(definition)) end
    if point ~= nil and definition.scene == "blockade" then
        local refusal = Director.blockadeRefusal(point)
        if refusal ~= nil then
            Director.refusePlacement(refusal)
            point = nil
        end
    end
    if point ~= nil and definition.stance == "blockade" then
        local fairness = ProjectALife.SpawnFairness
        local why = fairness ~= nil and type(fairness.checkpointRefusal) == "function"
            and fairness.checkpointRefusal(point) or nil
        if why ~= nil then
            Director.refusePlacement(why)
            point = nil
        end
    end
    if point ~= nil and Director.claimsBuilding[placement] == true then point = Director.claimed(point) end
    local faction
    if point ~= nil and type(claim) == "function" then
        faction = claim(point)
        if faction == nil then
            Director.refusePlacement("no_faction_here")
            point = nil
        end
    end
    if point ~= nil then
        job.point, job.faction, job.done = point, faction, true
    end
end

function Director.placeStep(job, budgetMs, clock)
    local began = budgetMs ~= nil and clock ~= nil and clock() or 0
    while job.done ~= true do
        if job.open ~= true then
            if job.attempt >= job.attempts then
                job.done = true
            else
                job.attempt = job.attempt + 1
                job.inner = 0
                job.open = true
            end
        end
        if job.done ~= true then
            local point
            local finished = true
            job.units = job.units + 1
            if job.placement == "building" then
                job.inner = job.inner + 1
                local gotCell, cell = pcall(getCell)
                if gotCell and cell ~= nil then
                    local fine, found = pcall(Director.buildingTry, job.px, job.py, cell)
                    if fine then point = found end
                    finished = not fine or point ~= nil or job.inner >= Director.buildingTries
                end
            else
                point = Director.placeAttemptPoint(job)
            end
            if finished then
                job.open = false
                Director.placeAttemptEnd(job, point)
            end
            if job.done ~= true and job.maxUnits ~= nil and job.units >= job.maxUnits then job.done = true end
            if job.done ~= true and budgetMs ~= nil and clock() - began >= budgetMs then return false end
        end
    end
    return true
end

function Director.placeRun(job)
    Director.placeStep(job, nil, nil)
    return job
end

local function place(definition, px, py, fx, fy, early, claim)
    local job = Director.placeRun(Director.placeOpen(definition, px, py, fx, fy, early, claim))
    if job.point ~= nil then return job.point, job.label, job.faction end
    return nil, job.label
end

Director.roadWatch = { nextAtMs = 0, armedUntilMs = 0 }
Director.roadSettings = { tiles = 220, kmh = 22, cooldownMs = 240000 }

function Director.watchRoads(now)
    local odometer = ProjectALife.Odometer
    local encounters = ProjectALife.Encounters
    local service = ProjectALife.DebugService
    if odometer == nil or encounters == nil or service == nil then return 0 end
    if now < (tonumber(Director.roadWatch.nextAtMs) or 0) then return 0 end
    Director.roadWatch.nextAtMs = now + 500
    local placed = 0
    pcall(function()

        local roster = {}
        pcall(function()
            local players = getOnlinePlayers and getOnlinePlayers() or nil
            if players ~= nil then
                for index = 0, players:size() - 1 do
                    roster[#roster + 1] = players:get(index)
                end
            end
        end)
        if #roster == 0 then
            pcall(function()
                local solo = getPlayer and getPlayer() or nil
                if solo ~= nil then roster[1] = solo end
            end)
        end
        for _, player in ipairs(roster) do

            local read = player ~= nil and odometer.sample(player, now) or nil
            if read ~= nil then

                local key = tostring(read.id)
                Director.roadWatch.armed = Director.roadWatch.armed or {}
                local armedUntil = tonumber(Director.roadWatch.armed[key]) or 0
                if now >= armedUntil
                        and odometer.armed(read, Director.roadSettings.tiles,
                            Director.roadSettings.kmh) then

                    local definition = nil
                    for _, candidate in ipairs(encounters.definitions or {}) do

                        local live = encounters.onlyId == nil
                            or candidate.id == encounters.onlyId
                        if live and candidate.trigger == "vehicle_distance" then
                            definition = candidate
                            break
                        end
                    end
                    if definition ~= nil then

                        local lead = 34
                        local point = {
                            x = math.floor(read.x + read.hx * lead),
                            y = math.floor(read.y + read.hy * lead),
                            z = 0,
                        }

                        point = validated(point, true)
                        local fairness = ProjectALife.SpawnFairness
                        if point ~= nil and fairness ~= nil and not fairness.typeAllowed(definition.id,
                                fairness.kindAt(point.x, point.y)) then
                            fairness.noteCut("rural_type")
                            point = nil
                        end
                        local catalog = ProjectALife.Catalog and ProjectALife.Catalog.current or nil
                        local faction = point ~= nil and ProjectALife.FactionSpawnRules.pick(
                            catalog, point, definition.id, roll(1000) / 1000, true) or nil
                        local wanted = faction and Director.partySize(faction, definition, roll(1000) / 1000) or 0
                        wanted = math.min(wanted, Director.capacityLeft())
                        local ok, _, spawnResult = false, nil, nil
                        if faction and wanted > 0 then
                        ok, _, spawnResult = ProjectALife.WorldPressure.spawn(service, player, {
                            requestId = "ambush:" .. tostring(now),
                            origin = "director",
                            count = wanted,

                            profileIds = service.hostileProfileIds(wanted, now, faction.id, true),
                            factionId = faction.id,
                            x = point.x, y = point.y, z = 0,
                            distance = 0, separation = 2, radius = 20,
                            mode = definition.mode or "guard",
                            profile = definition.profile,
                            conducts = definition.conducts,
                            animation = "normal",
                            encounterId = definition.id,
                            stance = definition.stance,
                            heading = Director.headingFor(definition, point),
                        }, worldHours() or 0)
                        end

                        Director.roadWatch.armed[key] = now
                            + (ok and Director.roadSettings.cooldownMs or 20000)
                        if ok then
                            placed = placed + 1
                            odometer.forget(read.id)
                            pcall(function()
                                local log = ProjectALife.EncounterLog
                                if log ~= nil then
                                    log.record(definition, point,
                                        definition.minCount or 3, "road",
                                        spawnResult and spawnResult.groupId)
                                end
                            end)
                        end
                    end
                end
            end
        end
    end)
    return placed
end

local function hostileOnlyFor(definition)
    return definition.id == "raid" or definition.id == "fullscale_raid"
        or definition.id == "assassination"
end

Director.chaosHours = 72
Director.chaosScale = 1.5
function Director.outbreakChaos(age)
    local settings = ProjectALife.Settings
    local current = settings ~= nil and settings.current or nil
    if type(current) ~= "table" or current.realisticOutbreak ~= true then return 1 end
    if (tonumber(age) or 0) >= Director.chaosHours then return 1 end
    return Director.chaosScale
end

local function settlePending(service, now)
    local outcomes = type(service) == "table" and service.groupOutcomes or nil
    for requestId, since in pairs(Director.pending) do
        local outcome = type(outcomes) == "table" and outcomes[requestId] or nil
        if outcome ~= nil then
            Director.pending[requestId] = nil
            if (tonumber(outcome.active) or 0) > 0 then
                Director.metrics.spawned = Director.metrics.spawned + 1
            else
                Director.refusals.place_failed = (Director.refusals.place_failed or 0) + 1
            end
            emit("encounter_placed", { requestId = requestId,
                active = outcome.active, failed = outcome.failed })
        elseif now - (tonumber(since) or now) > 300000 then

            Director.pending[requestId] = nil
            Director.refusals.never_settled = (Director.refusals.never_settled or 0) + 1
        end
    end
end

local function report(now)
    local last, outcome = Director.lastRoll, tostring(Director.lastOutcome)
    local landed = string.sub(outcome, 1, 8) == "spawned:"
    if not landed then
        Director.refusals[outcome] = (Director.refusals[outcome] or 0) + 1
    end
    emit("encounter_roll", { roll = Director.metrics.rolls, outcome = outcome,
        definition = last.definition, faction = last.faction, count = last.count,
        x = last.x, y = last.y, hours = last.hours, refused = last.refused })
    local state = Director.printState
    if landed or now - (tonumber(state.lastMs) or 0) >= 2000 then
        state.lastMs = now
        local line = "[ALIFE-ENCOUNTER] roll=" .. tostring(Director.metrics.rolls)
            .. " outcome=" .. outcome
            .. " def=" .. tostring(last.definition or "-")
            .. " faction=" .. tostring(last.faction or "-")
            .. " count=" .. tostring(last.count or 0)

            .. (last.refused ~= nil and (" refused=" .. tostring(last.refused)) or "")

            .. (last.px ~= nil and (" at=" .. tostring(last.px) .. "," .. tostring(last.py)) or "")
            .. Director.spawnText(last)
        if type(Director.adapters.print) == "function" then
            pcall(Director.adapters.print, line)
        else
            pcall(print, line)
        end
    end
end

function Director.spawnText(last)
    if type(last) ~= "table" or tonumber(last.x) == nil or tonumber(last.px) == nil then return "" end
    local dx, dy = tonumber(last.x) - last.px, (tonumber(last.y) or 0) - (tonumber(last.py) or 0)
    local d = math.sqrt(dx * dx + dy * dy)
    local text = " spawn=" .. tostring(math.floor(tonumber(last.x))) .. "," .. tostring(math.floor(tonumber(last.y) or 0))
        .. " dist=" .. tostring(math.floor(d + 0.5))
    local fx, fy = tonumber(last.fx), tonumber(last.fy)
    if fx ~= nil and fy ~= nil and d > 0.001 and fx * fx + fy * fy > 0.000001 then
        local angle = (math.atan2 or math.atan)(math.abs(dx * fy - dy * fx), dx * fx + dy * fy)
        text = text .. " off=" .. tostring(math.floor(math.deg(angle) + 0.5))
    end
    return text
end

function Director.qaLine()
    local metrics = Director.metrics
    local keys = {}
    for key in pairs(Director.refusals) do keys[#keys + 1] = key end
    table.sort(keys)
    local refused = ""
    for _, key in ipairs(keys) do
        refused = refused .. (refused == "" and "" or ",") .. key .. "=" .. tostring(Director.refusals[key])
    end

    local placeKeys = {}
    for key in pairs(Director.placeRefusals or {}) do placeKeys[#placeKeys + 1] = key end
    table.sort(placeKeys)
    local placed = ""
    for _, key in ipairs(placeKeys) do
        placed = placed .. (placed == "" and "" or ",") .. key .. "=" .. tostring(Director.placeRefusals[key])
    end
    local siteText = ""
    for _, bucket in ipairs({ "found", "none" }) do
        local names = {}
        for key in pairs(Director.siteMetrics[bucket]) do names[#names + 1] = key end
        table.sort(names)
        for _, key in ipairs(names) do
            siteText = siteText .. (siteText == "" and "" or ",") .. bucket .. ":" .. key .. "="
                .. tostring(Director.siteMetrics[bucket][key])
        end
    end
    return "EncounterDirector: rolls=" .. tostring(metrics.rolls)
        .. " accepted=" .. tostring(metrics.accepted)
        .. " spawned=" .. tostring(metrics.spawned)
        .. " forfeits=" .. tostring(metrics.forfeits)
        .. " next=" .. tostring(Director.nextRollAtHours)
        .. " reach=" .. tostring(Director.reach())
        .. " last=" .. tostring(Director.lastOutcome)
        .. " refused=" .. (refused == "" and "-" or refused)
        .. " place=" .. (placed == "" and "-" or placed)
        .. " sites=" .. (siteText == "" and "-" or siteText) .. "/reads:" .. tostring(Director.siteMetrics.reads)
        .. " road=" .. tostring(metrics.roadAhead or 0) .. "/" .. tostring(metrics.roadBehind or 0)
        .. "/unloaded:" .. tostring(metrics.roadUnloaded or 0)
        .. "/notroad:" .. tostring(metrics.roadNotRoad or 0)
        .. "/street:" .. tostring(metrics.roadStreet or 0)
        .. " placing=" .. tostring(metrics.placeParked or 0) .. "/" .. tostring(metrics.placeSlices or 0)
        .. "/" .. tostring(metrics.placeDropped or 0)
end

function Director.tick()
    local now = nowMs()

    Director.sceneUpkeep(now)
    if not Director.enabled then
        if Director.rollPending ~= nil then
            Director.rollPending = nil
            Director.lastOutcome = "placing_dropped:disabled"
        end
        return 0
    end

    pcall(function()
        local locks = ProjectALife.RegionLocks
        local locator = ProjectALife.PlayerLocator
        if locks == nil or locator == nil then return end
        local positions = {}
        for _, player in ipairs(locator.list() or {}) do
            local p = locator.position(player)
            if p ~= nil then positions[#positions + 1] = p end
        end
        locks.tick(positions)
    end)

    local roadPlaced = Director.watchRoads(now)
    settlePending(ProjectALife.DebugService, now)

    if Director.rollPending ~= nil then
        local rules = ProjectALife.FactionSpawnRules
        rules.professionContext = Director.rollPending.profession
        local resumed, finished = pcall(Director.rollResume, now)
        rules.professionContext = nil
        if not resumed then error(finished, 0) end
        if Director.rollPending == nil then report(now) end
        return finished + roadPlaced
    end

    local hours = worldHours()
    if hours == nil or hours < Director.nextRollAtHours then return roadPlaced end

    local player = Director.anyPlayer()
    if player == nil then return roadPlaced end
    Director.nextRollAtHours = hours
        + math.max(10, Director.settings.intervalMinutes) / 60
    Director.metrics.rolls = Director.metrics.rolls + 1
    Director.lastRoll = { hours = hours }
    local rules = ProjectALife.FactionSpawnRules
    rules.professionContext = Director.professionOf(player)
    local rolled, placed = pcall(Director.rollOnce, now, hours, player, Director.placeBudgetMs)
    rules.professionContext = nil
    if not rolled then error(placed, 0) end
    if Director.rollPending == nil then report(now) end
    return placed + roadPlaced
end

function Director.professionOf(player)
    local layers = ProjectALife.RelationLayers
    if layers == nil or type(layers.professionOf) ~= "function" then return nil end
    local ok, profession = pcall(layers.professionOf, player)
    return ok and profession or nil
end

function Director.pacing(owners, definition, day, hour)
    local rules, pressure = ProjectALife.FactionSpawnRules, ProjectALife.WorldPressure
    local scale = 1
    if type(owners) == "table" and type(definition) == "table"
            and type(rules) == "table" and type(rules.presence) == "function" then
        local hostile = hostileOnlyFor(definition)
        local weights = owners.any
        if hostile then weights = owners.hostile end
        local reference
        if type(rules.reference) == "function" then reference = rules.reference(definition.id, day, hour, hostile) end
        scale = rules.presence(type(weights) == "table" and weights[definition.id] or 0, reference)
    end
    if type(pressure) == "table" and type(pressure.censusVitality) == "function" then
        scale = scale * pressure.censusVitality()
    end
    return scale
end

function Director.ownerAt(rules, catalog, encounterId, hostile, candidate, claims)
    local unit = roll(1000) / 1000
    if type(rules.pickList) ~= "function" or type(rules.pickAt) ~= "function" then
        return rules.pick(catalog, candidate, encounterId, unit, hostile)
    end
    if claims.rows == nil then claims.rows = rules.pickList(catalog, encounterId, hostile) end
    return rules.pickAt(claims.rows, candidate, unit)
end

Director.placeBudgetMs = 6
Director.placeMaxAgeMs = 60000
Director.placeDriftTiles = 32

function Director.sliceClock(budgetMs)
    if tonumber(budgetMs) == nil or tonumber(budgetMs) <= 0 then return nil end
    if type(Director.adapters.nowMs) == "function" then return Director.adapters.nowMs end
    if type(getTimestampMs) == "function" then return getTimestampMs end
    return nil
end

function Director.rollOnce(now, hours, chosenPlayer, budgetMs)
    local encounters = ProjectALife.Encounters
    local service = ProjectALife.DebugService
    if encounters == nil or service == nil
            or type(service.spawnEncounter) ~= "function" then
        Director.lastOutcome = "unavailable"
        return 0
    end

    local player = chosenPlayer or Director.anyPlayer()
    if player == nil then
        Director.lastOutcome = "no_players"
        return 0
    end
    local px, py = 0, 0
    local positioned = pcall(function() px, py = player:getX(), player:getY() end)
    if not positioned then
        Director.lastOutcome = "no_position"
        return 0
    end

    Director.lastRoll.px = math.floor(tonumber(px) or 0)
    Director.lastRoll.py = math.floor(tonumber(py) or 0)

    local hour = hourOfDay()

    local catalog = ProjectALife.Catalog and ProjectALife.Catalog.current or nil
    local rules = ProjectALife.FactionSpawnRules
    local day = (tonumber(hours) or 0) / 24

    local owners = rules.encounterOwners(catalog, day, hour)

    local townHere = Director.townNear(px, py)
    local capped = Director.blockadeCapped(px, py)
    local fairness = ProjectALife.SpawnFairness
    local playerKind = "town"
    if fairness ~= nil and fairness.enabled() then playerKind = fairness.kindAt(px, py) end
    local function eligible(candidate)
        if capped and candidate.scene == "blockade" then return false end
        if fairness ~= nil and not fairness.typeAllowed(candidate.id, playerKind) then return false end
        local weights = hostileOnlyFor(candidate) and owners.hostile or owners.any
        if not townHere and Director.needsTown(candidate) then return false end
        return (weights[candidate.id] or 0) > 0
    end
    local definition = encounters.pick(hour, roll(100000), eligible)
    if definition == nil then
        Director.lastOutcome = "no_legal_encounter"
        return 0
    end
    Director.lastRoll.definition = definition.id

    local raidClass = definition.id == "raid" or definition.id == "fullscale_raid"
    if raidClass and ProjectALife.RaidDirector ~= nil
            and ProjectALife.RaidDirector.state ~= nil then
        Director.lastOutcome = "fullscale_raid_active"
        return 0
    end
    local heat = raidClass and ProjectALife.BaseHeat ~= nil
        and ProjectALife.BaseHeat.target(player) or nil
    if heat ~= nil and heat.cooling then
        Director.lastOutcome = "base_heat_grace"
        return 0
    end

    local pressure = ProjectALife.WorldPressure
    local age = worldHours() or 0

    local early = age < (tonumber(Director.settings.earlyHours) or 0)
    local chance = Director.settings.chance * (heat and heat.mult or 1) * (pressure ~= nil and pressure.at(age) or 1)
        * (early and (tonumber(Director.settings.earlyChanceScale) or 1) or 1)
        * Director.outbreakChaos(age) * Director.pacing(owners, definition, day, hour)
    local factor = 1
    if fairness ~= nil then factor = fairness.encounterFactor(definition.id, px, py) end
    local unit = roll(1000)
    if unit >= math.floor(math.min(1, chance * factor) * 1000) then
        if factor < 1 and unit < math.floor(math.min(1, chance) * 1000) then fairness.noteCut("rural_density") end
        Director.lastOutcome = "quiet"
        return 0
    end

    if not raidClass and pressure ~= nil and pressure.crowded(px, py, age) then
        Director.lastOutcome = "crowded"
        return 0
    end
    if heat ~= nil and heat.anchor then px, py = heat.x, heat.y end

    local fx, fy
    pcall(function()
        local forward = player:getForwardDirection()
        if forward ~= nil then fx, fy = forward:getX(), forward:getY() end
    end)
    Director.lastRoll.fx, Director.lastRoll.fy = fx, fy

    local hostile = raidClass or definition.id == "assassination"
    local claims = {}
    local function ownerAt(candidate)
        return Director.ownerAt(rules, catalog, definition.id, hostile, candidate, claims)
    end
    Director.placing.townHere = townHere
    local ctx = { now = now, hours = hours, player = player, definition = definition,
        age = age, raidClass = raidClass }
    local handled, started = Director.rollBegin(ctx, budgetMs, px, py, fx, fy, early, ownerAt)
    if handled then return started end
    local point, wanted, faction = place(definition, px, py, fx, fy, early, ownerAt)
    return Director.rollFinish(ctx, point, wanted, faction)
end

function Director.rollFinish(ctx, point, wanted, faction)
    local definition, player, now, age = ctx.definition, ctx.player, ctx.now, ctx.age
    age = math.max(tonumber(age) or 0, worldHours() or 0)
    local raidClass = ctx.raidClass
    local fairness = ProjectALife.SpawnFairness
    local pressure = ProjectALife.WorldPressure
    local service = ProjectALife.DebugService
    if point == nil then
        Director.metrics.forfeits = Director.metrics.forfeits + 1
        Director.lastOutcome = "no_placement:" .. tostring(wanted)
        return 0
    end
    if faction == nil then Director.lastOutcome = "no_eligible_faction:" .. definition.id; return 0 end
    if fairness ~= nil and not fairness.typeAllowed(definition.id, fairness.kindAt(point.x, point.y)) then
        fairness.noteCut("rural_type")
        Director.lastOutcome = "rural_type:" .. definition.id
        return 0
    end
    Director.lastRoll.faction = faction.id
    local count = Director.partySize(faction, definition, roll(1000) / 1000)
    if count == 0 then Director.lastOutcome = "party_disabled"; return 0 end

    local room = Director.capacityLeft()
    if room < math.max(1, math.floor(tonumber(definition.minCount) or 1)) then
        Director.lastOutcome = "capacity_full"
        return 0
    end
    count = math.min(count, room)
    Director.lastRoll.count, Director.lastRoll.x, Director.lastRoll.y = count, point.x, point.y
    local requestId = "encounter:" .. definition.id .. ":" .. tostring(now)
    local ok, reason, spawnResult = pressure.spawn(service, player, {
        requestId = requestId,

        origin = "director",
        count = count,
        x = point.x, y = point.y, z = point.z,
        distance = 0, separation = 2, radius = 24,
        mode = definition.mode or "roam",
        profile = definition.profile,

        profileIds = service.hostileProfileIds(count, now, faction.id, true),
        factionId = faction.id,
        conducts = definition.conducts,
        animation = "normal",
        anchor = definition.persistent == true,
        encounterId = definition.id,
        encounterPersistent = definition.persistent == true,

        stance = definition.stance,
        roles = definition.roles,
        upper = wanted == "upper_building" or nil,
        route = Director.routeFor(definition, point),
        heading = Director.headingFor(definition, point),

        moduleOverrides = type(definition.modules) == "table" and definition.modules or nil,
    }, age)
    if ok then
        if type(spawnResult) == "table" and type(spawnResult.origin) == "table" then
            point = spawnResult.origin
        end
        Director.bindScene(spawnResult)

        pcall(function()
            local log = ProjectALife.EncounterLog
            if log ~= nil then
                log.record(definition, point, count, wanted,
                    spawnResult and spawnResult.groupId)
            end
        end)
        Director.metrics.accepted = Director.metrics.accepted + 1
        Director.pending[requestId] = now
        if raidClass and ProjectALife.BaseHeat ~= nil
                and type(ProjectALife.BaseHeat.markRaid) == "function" then
            ProjectALife.BaseHeat.markRaid(player)
        end
        Director.lastOutcome = "spawned:" .. definition.id .. ":" .. tostring(count)
            .. "@" .. tostring(wanted)
    else
        Director.lastOutcome = "spawn_failed:" .. tostring(reason)
    end
    return ok and 1 or 0
end

function Director.rollBegin(ctx, budgetMs, px, py, fx, fy, early, claim)
    local clock = Director.sliceClock(budgetMs)
    if clock == nil then return false end
    local job = Director.placeOpen(ctx.definition, px, py, fx, fy, early, claim)
    local metrics = Director.metrics
    metrics.placeSlices = (metrics.placeSlices or 0) + 1
    if Director.placeStep(job, budgetMs, clock) == true then
        return true, Director.rollFinish(ctx, job.point, job.label, job.faction)
    end
    local rules = ProjectALife.FactionSpawnRules
    if rules ~= nil then ctx.profession = rules.professionContext end
    ctx.job, ctx.startMs = job, ctx.now
    ctx.startX, ctx.startY = Director.lastRoll.px, Director.lastRoll.py
    metrics.placeParked = (metrics.placeParked or 0) + 1
    Director.rollPending = ctx
    Director.lastOutcome = "placing"
    return true, 0
end

function Director.playerLive(player)
    if player == nil then return false end
    local solo = type(getSpecificPlayer) == "function"
    local online = type(getOnlinePlayers) == "function"
    if not solo and not online then return true end
    local live = false
    pcall(function()
        if solo and getSpecificPlayer(0) == player then
            live = true
            return
        end
        if not online then return end
        local list = getOnlinePlayers()
        if list == nil then return end
        for index = 0, list:size() - 1 do
            if list:get(index) == player then
                live = true
                return
            end
        end
    end)
    return live
end

function Director.rollStale(ctx, now)
    local age = now - ctx.startMs
    if age < 0 or age > Director.placeMaxAgeMs then return "age" end
    if not Director.playerLive(ctx.player) then return "player" end
    local hours, started = worldHours(), tonumber(ctx.hours)
    if started ~= nil and (hours == nil or hours < started) then return "world" end
    local reach = tonumber(Director.placeDriftTiles) or 0
    local sx, sy = tonumber(ctx.startX), tonumber(ctx.startY)
    if reach > 0 and sx ~= nil and sy ~= nil then
        local px, py
        local located = pcall(function() px, py = ctx.player:getX(), ctx.player:getY() end)
        px, py = tonumber(px), tonumber(py)
        if not located or px == nil or py == nil then return "player" end
        local dx, dy = px - sx, py - sy
        if dx * dx + dy * dy > reach * reach then return "moved" end
    end
    return nil
end

function Director.rollResume(now)
    local ctx = Director.rollPending
    Director.rollPending = nil
    if ctx == nil then return 0 end
    local why = Director.rollStale(ctx, now)
    local metrics = Director.metrics
    if why ~= nil then
        metrics.forfeits = metrics.forfeits + 1
        metrics.placeDropped = (metrics.placeDropped or 0) + 1
        Director.lastOutcome = "placing_dropped:" .. why
        return 0
    end
    local budgetMs = Director.placeBudgetMs
    local clock = Director.sliceClock(budgetMs)
    if clock == nil then budgetMs = nil end
    metrics.placeSlices = (metrics.placeSlices or 0) + 1
    Director.lastOutcome = "placing_error"
    if Director.placeStep(ctx.job, budgetMs, clock) ~= true then
        Director.lastOutcome = "placing"
        Director.rollPending = ctx
        return 0
    end
    local job = ctx.job
    return Director.rollFinish(ctx, job.point, job.label, job.faction)
end

function Director.roadPointNear(px, py, minimum, maximum, fx, fy)
    return roadPoint(px, py, minimum, maximum, fx, fy)
end

function Director.placeFor(definition, player)
    if type(definition) ~= "table" or player == nil then return nil end
    local point
    pcall(function()
        local px, py = player:getX(), player:getY()
        point = place(definition, px, py)
    end)
    return point
end

function Director.placeBegin(definition, player)
    if type(definition) ~= "table" or player == nil then return nil end
    local job
    pcall(function()
        local px, py = player:getX(), player:getY()
        job = Director.placeOpen(definition, px, py)
    end)
    return job
end

function Director.routeFor(definition, point)
    if type(definition) ~= "table" or definition.stance ~= "route" then return nil end
    local radius = math.max(8, tonumber(definition.routeRadius) or 24)
    local route = {}
    for index = 0, 3 do
        local angle = index * (math.pi / 2) + math.pi / 4
        route[#route + 1] = {
            x = point.x + math.cos(angle) * radius,
            y = point.y + math.sin(angle) * radius,
            z = point.z,
        }
    end
    return route
end

function Director.headingFor(definition, point)
    if type(definition) ~= "table" or definition.stance == nil then return nil end

    local heading
    pcall(function()
        local road = ProjectALife.Road
        local cell = getCell()
        if road == nil or cell == nil or type(road.axisAt) ~= "function" then return end
        local square = cell:getGridSquare(math.floor(point.x), math.floor(point.y), 0)
        if square == nil then return end
        local ax, ay = road.axisAt(square)
        if ax == nil then return end

        heading = math.atan2 ~= nil and math.atan2(ay, ax)
            or (ay >= 0 and (ax >= 0 and 0 or math.pi)
                or (ax >= 0 and 0 or math.pi))
    end)
    if heading ~= nil then return heading end

    if definition.stance == "blockade" then
        local ok, ax = Director.roadSegment(point)
        if ok then return ax ~= 0 and 0 or math.pi / 2 end
    end
    local seed = math.floor(math.abs(point.x) + math.abs(point.y) * 7)
    local quarter = seed % 4
    return quarter * (math.pi / 2)
end

return Director
