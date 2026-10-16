require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/World/ALifeKeepOut"
require "ProjectALife/Outposts/ALifeOutpostBuilder"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local SpawnPolicy = {
    adapters = {},
    safehouseMargin = 8,
    searchRadius = 12,

    builtRadius = 10,

    installationMargin = 45,
    installationBuiltRadius = 40,

    enclosureReach = 40,
    enclosureHits = 3,

    playerKeepOut = 40,
    postKeepOut = 12,
    keepOutCone = 60,
    keepOutHalfCos = 0.5,
    keepOutSight = true,

    excludedRegions = {},

    claimReach = 16,
    claimCacheMs = 5000,
    claimCache = {},

    claimDetail = "-",
    reachMargin = 40,
    reachMarginMin = 16,
    reachSpan = 64,
    reachRayReach = 24,
    reachBudget = 3000,
    reachWindowMs = 100,
    reachWindowSquares = 4000,
    reachWindowUsed = 0,
    reachEdgeCap = 160,
    reachDoorCap = 6,
    reachDoorDepth = 3,
    reachCacheMs = 5000,
    reachCacheCap = 512,
    reachCache = {},
    reachCacheCount = 0,
    reachSteps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } },
    metrics = { floods = 0, rays = 0, cached = 0, deferred = 0, sealed = 0, unknown = 0, open = 0, plain = 0 },
    doomedSearches = 0,
    searchStats = { searches = 0, sliced = 0, resumed = 0, cheapRefused = 0, tested = 0, capped = 0, worstMs = 0 },
    searchClockEvery = 48,
    searchCheckWeight = 6,

    builtMemoMs = 10000,
    builtMemoCap = 50000,
    builtMemo = { cell = nil, atMs = 0, values = {}, count = 0 },
}
ProjectALife.SpawnPolicy = SpawnPolicy

function SpawnPolicy.excludedRegionAt(position)
    local x, y = tonumber(position and position.x), tonumber(position and position.y)
    if x == nil or y == nil then return nil end
    for _, region in ipairs(SpawnPolicy.excludedRegions) do
        if x >= region.x1 and x < region.x2 + 1 and y >= region.y1 and y < region.y2 + 1 then
            return region.id or "region"
        end
    end
    return nil
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function validPosition(position)
    return type(position) == "table" and finite(tonumber(position.x))
        and finite(tonumber(position.y)) and finite(tonumber(position.z))
end

local function safehouses()
    if type(SpawnPolicy.adapters.safehouses) == "function" then
        local ok, result = pcall(SpawnPolicy.adapters.safehouses)
        if not ok then return nil, "safehouse_lookup_failed" end
        return result or {}
    end

    if SafeHouse == nil or SafeHouse.getSafehouseList == nil then return {} end
    local ok, list = pcall(SafeHouse.getSafehouseList)
    if not ok or list == nil then return nil, "safehouse_lookup_failed" end
    local result = {}
    local countOk, count = pcall(function() return list:size() end)
    if not countOk then return nil, "safehouse_lookup_failed" end
    for index = 0, count - 1 do
        local itemOk, item = pcall(function() return list:get(index) end)
        if not itemOk or item == nil then return nil, "safehouse_lookup_failed" end
        result[#result + 1] = item
    end
    return result
end

local function rectangle(item)
    if type(item) == "table" and item.x ~= nil then
        return tonumber(item.x), tonumber(item.y), tonumber(item.w), tonumber(item.h)
    end
    local kind = type(item)
    if (kind ~= "userdata" and kind ~= "table") or item.getX == nil or item.getY == nil
            or item.getW == nil or item.getH == nil then return nil end
    return tonumber(item:getX()), tonumber(item:getY()), tonumber(item:getW()), tonumber(item:getH())
end

local function inSafehouse(position, collection, margin)
    margin = tonumber(margin) or SpawnPolicy.safehouseMargin
    for _, safehouse in ipairs(collection or {}) do
        local x, y, w, h = rectangle(safehouse)
        if not finite(x) or not finite(y) or not finite(w) or not finite(h) then
            return true
        end
        if finite(x) and finite(y) and finite(w) and finite(h)
                and position.x >= x - margin and position.x <= x + w + margin
                and position.y >= y - margin and position.y <= y + h + margin then
            return true
        end
    end
    return false
end

local function inAdminZone(position, zones)
    for _, zone in ipairs(zones or {}) do
        if math.floor(position.z) == math.floor(zone.z) then
            local dx, dy = position.x - zone.x, position.y - zone.y
            if dx * dx + dy * dy <= zone.radius * zone.radius then return true end
        end
    end
    return false
end

local function squareAt(position)
    if type(SpawnPolicy.adapters.squareAt) == "function" then
        return SpawnPolicy.adapters.squareAt(position)
    end
    if type(getCell) ~= "function" then return true end
    local ok, cell = pcall(getCell)
    if not ok or cell == nil or cell.getGridSquare == nil then return nil end
    return cell:getGridSquare(
        math.floor(position.x), math.floor(position.y), math.floor(position.z)) or nil
end

local function squareFree(square)
    if square == true then return true end
    if square == nil then return false end
    if type(SpawnPolicy.adapters.squareFree) == "function" then
        return SpawnPolicy.adapters.squareFree(square) == true
    end
    local kind = type(square)
    if (kind ~= "userdata" and kind ~= "table") or square.isFree == nil then return false end
    return square:isFree(true) == true
end

function SpawnPolicy.squareIsWater(square)
    if square == nil or square == true then return false end
    if type(SpawnPolicy.adapters.squareIsWater) == "function" then
        return SpawnPolicy.adapters.squareIsWater(square) == true
    end
    local builder = ProjectALife.OutpostBuilder
    if builder == nil or type(builder.squareIsWater) ~= "function" then return false end
    return builder.squareIsWater(square)
end

function SpawnPolicy.configure(adapters)
    SpawnPolicy.adapters = adapters or {}
    SpawnPolicy.safehouseMargin = math.max(0, math.min(50,
        math.floor(tonumber(SpawnPolicy.adapters.safehouseMargin) or 8)))
    SpawnPolicy.searchRadius = math.max(1, math.min(30,
        math.floor(tonumber(SpawnPolicy.adapters.searchRadius) or 12)))
    SpawnPolicy.installationMargin = math.max(0, math.min(200,
        math.floor(tonumber(SpawnPolicy.adapters.installationMargin) or 45)))
    SpawnPolicy.installationBuiltRadius = math.max(0, math.min(200,
        math.floor(tonumber(SpawnPolicy.adapters.installationBuiltRadius) or 40)))

    SpawnPolicy.playerKeepOut = math.max(0, math.min(120,
        math.floor(tonumber(SpawnPolicy.adapters.playerKeepOut) or 40)))
    SpawnPolicy.keepOutSight = SpawnPolicy.adapters.keepOutSight ~= false
    SpawnPolicy.reachCache, SpawnPolicy.reachCacheCount = {}, 0
    SpawnPolicy.sharedReach = nil
    SpawnPolicy.reachWindow, SpawnPolicy.reachWindowUsed = nil, 0
    SpawnPolicy.metrics = { floods = 0, rays = 0, cached = 0, deferred = 0, sealed = 0, unknown = 0, open = 0, plain = 0 }
    SpawnPolicy.claimDetail = "-"
    SpawnPolicy.claimCache = {}
    SpawnPolicy.doomedSearches = 0
    SpawnPolicy.searchStats = { searches = 0, sliced = 0, resumed = 0, cheapRefused = 0, tested = 0, capped = 0, worstMs = 0 }
    SpawnPolicy.builtMemo = { cell = nil, atMs = 0, values = {}, count = 0 }
end

function SpawnPolicy.forwardOf(player)
    if player == nil or player.getForwardDirection == nil then return nil end
    local forward = player:getForwardDirection()
    if forward == nil or forward.getX == nil or forward.getY == nil then return nil end
    return { x = tonumber(forward:getX()), y = tonumber(forward:getY()) }
end

function SpawnPolicy.vehicleSpeed(player)
    if player == nil or player.getVehicle == nil then return nil end
    local vehicle = player:getVehicle()
    if vehicle == nil or vehicle.getCurrentSpeedKmHour == nil then return nil end
    return tonumber(vehicle:getCurrentSpeedKmHour())
end

function SpawnPolicy.playerPoints()
    if type(SpawnPolicy.adapters.playerPoints) == "function" then
        local ok, supplied = pcall(SpawnPolicy.adapters.playerPoints)
        return (ok and type(supplied) == "table") and supplied or {}
    end
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return {} end
    local listed = locator.list(SpawnPolicy.adapters.players)
    local result = {}
    for _, player in ipairs(type(listed) == "table" and listed or {}) do
        local at = locator.position(player, SpawnPolicy.adapters.playerPosition)
        if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
            local point = { x = tonumber(at.x), y = tonumber(at.y) }
            local ok, forward = pcall(SpawnPolicy.forwardOf, player)
            if ok and type(forward) == "table" and forward.x ~= nil and forward.y ~= nil then
                point.fx, point.fy = forward.x, forward.y
            end
            local speedOk, speed = pcall(SpawnPolicy.vehicleSpeed, player)
            if speedOk and finite(speed) and math.abs(speed) > 25 then
                point.drivingKeepOut = math.abs(speed) / 3.6 * 4
            end
            result[#result + 1] = point
        end
    end
    return result
end

local function contextFor(options)
    if options.allowProtected == true then return { safehouses = {}, zones = {}, built = {} } end
    local houses, houseError = safehouses()
    if houses == nil then return nil, houseError end
    local bases = SpawnPolicy.playerBases()
    return {
        safehouses = houses,
        zones = type(Registry.listNoSpawnZones) == "function"
            and Registry.listNoSpawnZones() or {},
        bases = bases,
        reachZones = SpawnPolicy.playerZones(bases),
        built = {},
    }
end

function SpawnPolicy.context(options)
    return contextFor(options or {})
end

function SpawnPolicy.insidePlayerBuild(position, suppliedRadius, memo)
    if type(SpawnPolicy.adapters.playerBuiltAt) == "function" then
        local ok, built = pcall(SpawnPolicy.adapters.playerBuiltAt, position, suppliedRadius)
        return ok and built == true
    end
    if type(getCell) ~= "function" or type(instanceof) ~= "function" then return false end
    local radius = math.max(0, math.floor(tonumber(suppliedRadius)
        or tonumber(SpawnPolicy.builtRadius) or 0))
    if radius == 0 then return false end
    local found = false
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local shared = SpawnPolicy.builtShared(cell)

        local step = math.max(2, math.min(6, math.floor(radius / 3)))
        local originX, originY = math.floor(position.x), math.floor(position.y)
        local z = math.floor(position.z)
        for dx = -radius, radius do
            local x = originX + dx
            local column = x % step == 0
            for dy = -radius, radius do
                local y = originY + dy
                if (column or y % step == 0)
                        and SpawnPolicy.builtAt(cell, x, y, z, memo, shared) == true then
                    found = true
                    return
                end
            end
        end
    end)
    return found
end

function SpawnPolicy.builtShared(cell)
    local memo = SpawnPolicy.builtMemo
    local now = SpawnPolicy.claimNowMs()
    if memo.cell ~= cell or now < memo.atMs or now - memo.atMs >= SpawnPolicy.builtMemoMs
            or memo.count >= SpawnPolicy.builtMemoCap then
        memo.cell, memo.atMs, memo.values, memo.count = cell, now, {}, 0
    end
    return memo
end

function SpawnPolicy.builtAt(cell, x, y, z, memo, shared)
    local key = (z * 65536 + x) * 65536 + y
    if memo ~= nil and memo[key] ~= nil then return memo[key] end
    if shared ~= nil and shared.values[key] ~= nil then
        local known = shared.values[key]
        if memo ~= nil then memo[key] = known end
        return known
    end
    local square = cell:getGridSquare(x, y, z)
    if square == nil then return nil end
    local built = false
    local objects = square:getObjects()
    for index = 0, (objects ~= nil and objects:size() or 0) - 1 do
        local object = objects:get(index)
        if object ~= nil and instanceof(object, "IsoThumpable")
                and object:isDismantable() == true then
            built = true
            break
        end
    end
    if memo ~= nil then memo[key] = built end
    if shared ~= nil then
        shared.values[key] = built
        shared.count = shared.count + 1
    end
    return built
end

function SpawnPolicy.enclosedByPlayerBuild(position, suppliedReach, memo)
    if type(SpawnPolicy.adapters.enclosedAt) == "function" then
        local ok, enclosed = pcall(SpawnPolicy.adapters.enclosedAt, position, suppliedReach)
        return ok and enclosed == true
    end
    if type(getCell) ~= "function" or type(instanceof) ~= "function" then return false end
    local reach = math.max(0, math.floor(tonumber(suppliedReach)
        or tonumber(SpawnPolicy.enclosureReach) or 0))
    if reach == 0 then return false end
    local hits = 0
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local shared = SpawnPolicy.builtShared(cell)
        local originX, originY = math.floor(position.x), math.floor(position.y)
        local z = math.floor(position.z)
        for _, ray in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            for distance = 1, reach do
                local built = SpawnPolicy.builtAt(cell, originX + ray[1] * distance,
                    originY + ray[2] * distance, z, memo, shared)
                if built ~= false then
                    if built == true then hits = hits + 1 end
                    break
                end
            end
        end
    end)
    return hits >= (tonumber(SpawnPolicy.enclosureHits) or 3)
end

function SpawnPolicy.playerBases()
    local source = SpawnPolicy.adapters.playerBases
    if type(source) ~= "function" then
        local heat = ProjectALife.BaseHeat
        source = heat ~= nil and (heat.homes or heat.bases) or nil
    end
    if type(source) ~= "function" then return {} end
    local ok, bases = pcall(source)
    return ok and type(bases) == "table" and bases or {}
end

function SpawnPolicy.inPlayerBase(position, margin, bases)
    return SpawnPolicy.baseAt(position, margin, bases) ~= nil
end

function SpawnPolicy.baseAt(position, margin, bases)
    margin = tonumber(margin) or SpawnPolicy.safehouseMargin
    for _, base in ipairs(type(bases) == "table" and bases or SpawnPolicy.playerBases()) do
        if type(base) == "table" then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil
                    and position.x >= x1 - margin and position.x <= x2 + margin
                    and position.y >= y1 - margin and position.y <= y2 + margin then
                return base
            end
        end
    end
    return nil
end

function SpawnPolicy.playerZones(bases)
    local source = SpawnPolicy.adapters.playerZones
    if type(source) ~= "function" then
        if type(SpawnPolicy.adapters.playerBases) == "function" then
            return type(bases) == "table" and bases or SpawnPolicy.playerBases()
        end
        local heat = ProjectALife.BaseHeat
        source = heat ~= nil and heat.zones or nil
    end
    if type(source) ~= "function" then return {} end
    local ok, zones = pcall(source)
    return ok and type(zones) == "table" and zones or {}
end

function SpawnPolicy.zoneMargin(side)
    return math.max(SpawnPolicy.reachMarginMin,
        math.min(SpawnPolicy.reachMargin, SpawnPolicy.reachSpan - math.ceil(side / 2)))
end

function SpawnPolicy.reachZone(position, zones)
    for _, zone in ipairs(type(zones) == "table" and zones or {}) do
        if type(zone) == "table" then
            local x1, y1 = tonumber(zone.x1), tonumber(zone.y1)
            local x2, y2 = tonumber(zone.x2), tonumber(zone.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                local mx, my = SpawnPolicy.zoneMargin(x2 - x1 + 1), SpawnPolicy.zoneMargin(y2 - y1 + 1)
                if position.x >= x1 - mx and position.x < x2 + mx + 1
                        and position.y >= y1 - my and position.y < y2 + my + 1 then
                    return { x1 = x1 - mx, y1 = y1 - my, x2 = x2 + mx, y2 = y2 + my,
                        core = zone.hint ~= true and zone or nil }
                end
            end
        end
    end
    return nil
end

function SpawnPolicy.squareKey(x, y, z)
    return (z * 65536 + x) * 65536 + y
end

function SpawnPolicy.squareXY(x, y, z)
    if type(SpawnPolicy.adapters.squareAt) == "function" then
        return SpawnPolicy.adapters.squareAt({ x = x + 0.5, y = y + 0.5, z = z })
    end
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return nil end
    return cell:getGridSquare(x, y, z)
end

function SpawnPolicy.crossable(a, b)
    if type(SpawnPolicy.adapters.crossable) == "function" then
        return SpawnPolicy.adapters.crossable(a, b) == true
    end
    if a.isBlockedTo == nil or a:isBlockedTo(b) ~= true then return true end
    return a.isHoppableTo ~= nil and (a:isHoppableTo(b) == true or b:isHoppableTo(a) == true)
end

function SpawnPolicy.walkable(square)
    if type(SpawnPolicy.adapters.walkable) == "function" then
        return SpawnPolicy.adapters.walkable(square) == true
    end
    if square.isSolid ~= nil and square:isSolid() == true then return false end
    if square.isSolidTrans ~= nil and square:isSolidTrans() == true then return false end
    return not SpawnPolicy.squareIsWater(square)
end

function SpawnPolicy.floodable(square)
    local kind = type(square)
    return (kind == "userdata" or kind == "table") and square.isBlockedTo ~= nil
end

function SpawnPolicy.flood(x, y, z, box, budget, target, facts)
    local seed = SpawnPolicy.squareXY(x, y, z)
    if not SpawnPolicy.floodable(seed) then return nil end
    local seen, fetched = {}, {}
    local qx, qy, qs = { x }, { y }, { seed }
    facts.qx, facts.qy, facts.count, facts.seen, facts.read = qx, qy, 1, seen, 0
    facts.unloaded, facts.outdoors, facts.anchored = false, false, false
    facts.ea, facts.eb, facts.edges = {}, {}, 0
    seen[SpawnPolicy.squareKey(x, y, z)] = true
    local core, steps, head, tail = facts.core, SpawnPolicy.reachSteps, 1, 1
    local edgeCap = SpawnPolicy.reachEdgeCap
    while head <= tail do
        if head > budget then
            facts.count = tail
            return "budget"
        end
        local cx, cy, square = qx[head], qy[head], qs[head]
        facts.read = head
        head = head + 1
        if not facts.outdoors and square.isOutside ~= nil and square:isOutside() == true then facts.outdoors = true end
        if core ~= nil and not facts.anchored and cx >= core.x1 and cx <= core.x2
                and cy >= core.y1 and cy <= core.y2 then facts.anchored = true end
        for index = 1, 4 do
            local nx, ny = cx + steps[index][1], cy + steps[index][2]
            local key = SpawnPolicy.squareKey(nx, ny, z)
            local outside = nx < box.x1 or nx > box.x2 or ny < box.y1 or ny > box.y2
            if seen[key] == nil and outside and facts.walled then
                seen[key] = false
            elseif seen[key] == nil then
                local other = fetched[key]
                if other == nil then
                    other = SpawnPolicy.squareXY(nx, ny, z) or false
                    fetched[key] = other
                end
                if other == false or not SpawnPolicy.floodable(other) then
                    facts.unloaded = true
                    seen[key] = false
                elseif not SpawnPolicy.walkable(other) then
                    seen[key] = false
                elseif SpawnPolicy.crossable(square, other) then
                    if outside then
                        facts.count = tail
                        return "escaped"
                    end
                    seen[key] = true
                    tail = tail + 1
                    qx[tail], qy[tail], qs[tail] = nx, ny, other
                    if key == target then
                        facts.count = tail
                        return "found"
                    end
                elseif facts.edges < edgeCap then
                    facts.edges = facts.edges + 1
                    facts.ea[facts.edges], facts.eb[facts.edges] = square, other
                end
            end
        end
    end
    facts.count, facts.read = tail, head - 1
    return "exhausted"
end

function SpawnPolicy.rayOut(x, y, z, box, facts)
    local seed = SpawnPolicy.squareXY(x, y, z)
    if not SpawnPolicy.floodable(seed) then return nil end
    facts.read = 0
    local west, east, north, south = x - box.x1, box.x2 - x, y - box.y1, box.y2 - y
    local reach = math.min(west, east, north, south)
    if reach > SpawnPolicy.reachRayReach then return false end
    local dx, dy = 0, 0
    if reach == west then dx = -1 elseif reach == east then dx = 1 elseif reach == north then dy = -1 else dy = 1 end
    local cx, cy, square = x, y, seed
    local qx, qy = { x }, { y }
    for step = 1, reach + 1 do
        local nx, ny = cx + dx, cy + dy
        local other = SpawnPolicy.squareXY(nx, ny, z)
        facts.read = step
        if not SpawnPolicy.floodable(other) or not SpawnPolicy.walkable(other)
                or not SpawnPolicy.crossable(square, other) then return false end
        if nx < box.x1 or nx > box.x2 or ny < box.y1 or ny > box.y2 then
            facts.qx, facts.qy, facts.count = qx, qy, #qx
            return true
        end
        qx[#qx + 1], qy[#qy + 1] = nx, ny
        cx, cy, square = nx, ny, other
    end
    return false
end

function SpawnPolicy.reachLeft(now)
    local window = math.floor(now / SpawnPolicy.reachWindowMs)
    if window ~= SpawnPolicy.reachWindow then SpawnPolicy.reachWindow, SpawnPolicy.reachWindowUsed = window, 0 end
    return SpawnPolicy.reachWindowSquares - SpawnPolicy.reachWindowUsed
end

function SpawnPolicy.reachSpend(now, squares)
    SpawnPolicy.reachLeft(now)
    SpawnPolicy.reachWindowUsed = SpawnPolicy.reachWindowUsed + (tonumber(squares) or 0)
end

function SpawnPolicy.deferReach(context)
    SpawnPolicy.metrics.deferred = SpawnPolicy.metrics.deferred + 1
    context.reachDefers = (context.reachDefers or 0) + 1
    return "unknown", "deferred"
end

SpawnPolicy.edgeOpenings = { "getDoorTo", "getWindowTo", "getWindowThumpableTo" }
SpawnPolicy.barricadeSides = { "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }

function SpawnPolicy.edgeEvidence(a, b, memo)
    if type(instanceof) == "function" and type(getCell) == "function" and a.getX ~= nil and b.getX ~= nil then
        local cell = getCell()
        if cell ~= nil and (SpawnPolicy.builtAt(cell, a:getX(), a:getY(), a:getZ(), memo) == true
                or SpawnPolicy.builtAt(cell, b:getX(), b:getY(), b:getZ(), memo) == true) then
            return true
        end
    end
    local heat = ProjectALife.BaseHeat
    for _, name in ipairs(SpawnPolicy.edgeOpenings) do
        local opening = a[name] ~= nil and a[name](a, b) or nil
        if opening ~= nil and opening.isBarricaded ~= nil and opening:isBarricaded() == true then
            for _, side in ipairs(SpawnPolicy.barricadeSides) do
                local barricade = opening[side] ~= nil and opening[side](opening) or nil
                if barricade ~= nil and (heat == nil or type(heat.npcBarricade) ~= "function"
                        or not heat.npcBarricade(barricade)) then
                    return true
                end
            end
        end
    end
    return false
end

function SpawnPolicy.reachCached(x, y, z, now)
    local chunk = SpawnPolicy.reachCache[(z * 4096 + math.floor(x / 8)) * 4096 + math.floor(y / 8)]
    if chunk == nil or now < chunk.atMs or now - chunk.atMs >= SpawnPolicy.reachCacheMs then return nil end
    return chunk.v[SpawnPolicy.squareKey(x, y, z)]
end

function SpawnPolicy.reachStore(facts, z, verdict, now)
    local cache = SpawnPolicy.reachCache
    if SpawnPolicy.reachCacheCount > SpawnPolicy.reachCacheCap then
        local kept = 0
        for key, chunk in pairs(cache) do
            if now < chunk.atMs or now - chunk.atMs >= SpawnPolicy.reachCacheMs then cache[key] = nil
            else kept = kept + 1 end
        end
        SpawnPolicy.reachCacheCount = kept
    end
    for index = 1, facts.count do
        local x, y = facts.qx[index], facts.qy[index]
        local key = (z * 4096 + math.floor(x / 8)) * 4096 + math.floor(y / 8)
        local chunk = cache[key]
        if chunk == nil or now < chunk.atMs or now - chunk.atMs >= SpawnPolicy.reachCacheMs then
            if chunk == nil then SpawnPolicy.reachCacheCount = SpawnPolicy.reachCacheCount + 1 end
            chunk = { atMs = now, v = {} }
            cache[key] = chunk
        end
        chunk.v[SpawnPolicy.squareKey(x, y, z)] = verdict
    end
end

function SpawnPolicy.reachContext()
    local now = SpawnPolicy.claimNowMs()
    local shared = SpawnPolicy.sharedReach
    if shared ~= nil and now >= shared.atMs and now - shared.atMs < 1500 then return shared.context end
    local bases = SpawnPolicy.playerBases()
    local context = { bases = bases, reachZones = SpawnPolicy.playerZones(bases) }
    SpawnPolicy.sharedReach = { atMs = now, context = context }
    return context
end

function SpawnPolicy.reachVerdict(position, context)
    if type(context) ~= "table" then context = SpawnPolicy.reachContext() end
    local zones = context.reachZones
    if zones == nil then
        zones = SpawnPolicy.playerZones(context.bases)
        context.reachZones = zones
    end
    local zone = SpawnPolicy.reachZone(position, zones)
    if zone == nil then return nil end
    local x, y, z = math.floor(position.x), math.floor(position.y), math.floor(position.z or 0)
    local now = SpawnPolicy.claimNowMs()
    local cached = SpawnPolicy.reachCached(x, y, z, now)
    local metrics = SpawnPolicy.metrics
    if cached ~= nil then
        metrics.cached = metrics.cached + 1
        if cached == "large" then return "unknown", "large" end
        return cached
    end
    local left = SpawnPolicy.reachLeft(now)
    if left <= 0 then return SpawnPolicy.deferReach(context) end
    local facts = { core = zone.core }
    local outcome = SpawnPolicy.rayOut(x, y, z, zone, facts)
    if outcome == nil then return nil end
    SpawnPolicy.reachSpend(now, facts.read)
    if facts.read > 0 then metrics.rays = metrics.rays + 1 end
    if outcome == true then
        outcome = "escaped"
    else
        local budget = math.min(SpawnPolicy.reachBudget, left - facts.read)
        if budget <= 0 then return SpawnPolicy.deferReach(context) end
        facts = { core = zone.core }
        outcome = SpawnPolicy.flood(x, y, z, zone, budget, nil, facts)
        if outcome == nil then return nil end
        SpawnPolicy.reachSpend(now, facts.read)
        metrics.floods = metrics.floods + 1
        if outcome == "budget" and budget < SpawnPolicy.reachBudget then return SpawnPolicy.deferReach(context) end
    end
    local defers = context.reachDefers or 0
    local verdict = SpawnPolicy.regionVerdict(outcome, facts, z, context)
    if (context.reachDefers or 0) > defers then return "unknown", "deferred" end
    metrics[verdict] = (metrics[verdict] or 0) + 1
    if verdict == "unknown" and (outcome == "budget" or facts.unloaded == true) then
        SpawnPolicy.reachStore(facts, z, "large", now)
        return "unknown", "large"
    end
    SpawnPolicy.reachStore(facts, z, verdict, now)
    return verdict
end

function SpawnPolicy.regionVerdict(outcome, facts, z, context)
    if outcome == "escaped" then return "open" end
    if outcome == "budget" or facts.unloaded then return "unknown" end
    if facts.outdoors or facts.anchored then return "sealed" end
    context.built = context.built or {}
    for index = 1, facts.edges do
        if SpawnPolicy.edgeEvidence(facts.ea[index], facts.eb[index], context.built) then return "sealed" end
    end
    return SpawnPolicy.beyondDoors(facts, z, context)
end

function SpawnPolicy.beyondDoors(facts, z, context)
    local depth = context.reachDepth or 0
    if depth >= SpawnPolicy.reachDoorDepth then return "plain" end
    local stack = context.reachStack or {}
    context.reachStack = stack
    stack[#stack + 1] = facts.seen
    context.reachDepth = depth + 1
    local verdict, asked = "plain", 0
    for index = 1, facts.edges do
        if asked >= SpawnPolicy.reachDoorCap then break end
        local a, b = facts.ea[index], facts.eb[index]
        if a.getDoorTo ~= nil and b.getX ~= nil and a:getDoorTo(b) ~= nil then
            local bx, by = b:getX(), b:getY()
            local key, inside = SpawnPolicy.squareKey(bx, by, z), false
            for level = 1, #stack do
                if stack[level][key] == true then inside = true end
            end
            if not inside then
                asked = asked + 1
                local far = SpawnPolicy.reachVerdict({ x = bx + 0.5, y = by + 0.5, z = z }, context)
                if far == "unknown" then verdict = "unknown" end
                if far == "sealed" then
                    verdict = "sealed"
                    break
                end
            end
        end
    end
    stack[#stack] = nil
    context.reachDepth = depth
    return verdict
end

function SpawnPolicy.reachableFrom(origin, radius)
    local x, y, z = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z or 0)
    local facts = { walled = true }
    local box = { x1 = x - radius, y1 = y - radius, x2 = x + radius, y2 = y + radius }
    local outcome = SpawnPolicy.flood(x, y, z, box, (2 * radius + 1) * (2 * radius + 1), nil, facts)
    if outcome == nil then return nil end
    SpawnPolicy.reachSpend(SpawnPolicy.claimNowMs(), facts.read)
    local set = {}
    for index = 1, facts.count do set[SpawnPolicy.squareKey(facts.qx[index], facts.qy[index], z)] = true end
    return set
end

function SpawnPolicy.reachProbe(origin, radius)
    local x, y, z = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z or 0)
    local seed = SpawnPolicy.squareXY(x, y, z)
    if not SpawnPolicy.floodable(seed) then return nil end
    local seen = {}
    seen[SpawnPolicy.squareKey(x, y, z)] = true
    return { z = z, seen = seen, fetched = {}, qx = { x }, qy = { y }, qs = { seed }, head = 1, tail = 1,
        x1 = x - radius, y1 = y - radius, x2 = x + radius, y2 = y + radius, spent = 0 }
end

function SpawnPolicy.probeStep(probe)
    local head = probe.head
    local cx, cy, square = probe.qx[head], probe.qy[head], probe.qs[head]
    probe.head = head + 1
    local seen, fetched, z, steps = probe.seen, probe.fetched, probe.z, SpawnPolicy.reachSteps
    for index = 1, 4 do
        local nx, ny = cx + steps[index][1], cy + steps[index][2]
        local key = SpawnPolicy.squareKey(nx, ny, z)
        if seen[key] == nil then
            if nx < probe.x1 or nx > probe.x2 or ny < probe.y1 or ny > probe.y2 then
                seen[key] = false
            else
                local other = fetched[key]
                if other == nil then
                    other = SpawnPolicy.squareXY(nx, ny, z) or false
                    fetched[key] = other
                end
                if other == false or not SpawnPolicy.floodable(other) then
                    seen[key] = false
                elseif not SpawnPolicy.walkable(other) then
                    seen[key] = false
                elseif SpawnPolicy.crossable(square, other) then
                    seen[key] = true
                    local tail = probe.tail + 1
                    probe.tail = tail
                    probe.qx[tail], probe.qy[tail], probe.qs[tail] = nx, ny, other
                end
            end
        end
    end
end

function SpawnPolicy.reaches(probe, key)
    local seen = probe.seen
    while seen[key] == nil and probe.head <= probe.tail do
        SpawnPolicy.probeStep(probe)
    end
    return seen[key] == true
end

function SpawnPolicy.reachesWithin(probe, key, began, budget)
    local seen, steps = probe.seen, 0
    while seen[key] == nil and probe.head <= probe.tail do
        SpawnPolicy.probeStep(probe)
        steps = steps + 1
        if steps % 16 == 0 and seen[key] == nil and SpawnPolicy.claimNowMs() - began >= budget then return nil end
    end
    return seen[key] == true
end

function SpawnPolicy.probeCharge(probe)
    if probe == nil then return end
    local read = probe.head - 1
    if read > probe.spent then
        SpawnPolicy.reachSpend(SpawnPolicy.claimNowMs(), read - probe.spent)
        probe.spent = read
    end
end

function SpawnPolicy.linked(a, b, pad)
    local ax, ay, z = math.floor(a.x), math.floor(a.y), math.floor(a.z or 0)
    local bx, by = math.floor(b.x), math.floor(b.y)
    if ax == bx and ay == by then return true end
    if not SpawnPolicy.floodable(SpawnPolicy.squareXY(bx, by, z)) then return nil end
    pad = tonumber(pad) or 8
    local box = { x1 = math.min(ax, bx) - pad, y1 = math.min(ay, by) - pad,
        x2 = math.max(ax, bx) + pad, y2 = math.max(ay, by) + pad }
    local facts = { walled = true }
    local budget = math.min(SpawnPolicy.reachBudget, (box.x2 - box.x1 + 1) * (box.y2 - box.y1 + 1))
    local outcome = SpawnPolicy.flood(ax, ay, z, box, budget, SpawnPolicy.squareKey(bx, by, z), facts)
    if outcome ~= nil then SpawnPolicy.reachSpend(SpawnPolicy.claimNowMs(), facts.read) end
    if outcome == "found" then return true end
    if outcome == "exhausted" and not facts.unloaded then return false end
    return nil
end

function SpawnPolicy.openingsVerdict(probe, ownBoards)
    if type(probe) ~= "table" then return false, "building_unloaded" end
    if probe.complete ~= true then return false, "building_unloaded" end
    if ownBoards == true then return true end
    for _, kind in ipairs({ "doors", "windows" }) do
        if type(probe[kind]) ~= "function" then return false, "building_unloaded" end
        local ok, openings = pcall(probe[kind])
        if not ok or type(openings) ~= "table" then return false, "building_unloaded" end
        for _, opening in ipairs(openings) do
            if opening.barricaded == true then return false, "building_barricaded" end
        end
    end
    return true
end

function SpawnPolicy.windowLoaded(building, x, y)
    if building == nil or building.getDef == nil or type(getCell) ~= "function" then return false end
    local def, cell = building:getDef(), getCell()
    if def == nil or cell == nil then return false end
    local reach = SpawnPolicy.claimReach
    local x1, y1 = math.max(def:getX(), x - reach), math.max(def:getY(), y - reach)
    local x2, y2 = math.min(def:getX2() - 1, x + reach), math.min(def:getY2() - 1, y + reach)
    for sx = x1, x2 do
        for sy = y1, y2 do
            local square = cell:getGridSquare(sx, sy, 0)
            if square == nil then return false end
            if (sx == x1 or sx == x2 or sy == y1 or sy == y2) and square:getBuilding() == building
                    and ((sy == y1 and cell:getGridSquare(sx, sy - 1, 0) == nil)
                    or (sy == y2 and cell:getGridSquare(sx, sy + 1, 0) == nil)
                    or (sx == x1 and cell:getGridSquare(sx - 1, sy, 0) == nil)
                    or (sx == x2 and cell:getGridSquare(sx + 1, sy, 0) == nil)) then
                return false
            end
        end
    end
    return true
end

function SpawnPolicy.cornersLoaded(building, x, y)
    if building == nil or building.getDef == nil or type(getCell) ~= "function" then return false end
    local def, cell = building:getDef(), getCell()
    if def == nil or cell == nil then return false end
    local reach = SpawnPolicy.claimReach
    local x1, x2 = math.max(def:getX(), x - reach), math.min(def:getX2(), x + reach + 1) - 1
    local y1, y2 = math.max(def:getY(), y - reach), math.min(def:getY2(), y + reach + 1) - 1
    return cell:getGridSquare(x1, y1, 0) ~= nil and cell:getGridSquare(x2, y1, 0) ~= nil
        and cell:getGridSquare(x1, y2, 0) ~= nil and cell:getGridSquare(x2, y2, 0) ~= nil
end

function SpawnPolicy.loadedBuilding(position)
    local square = squareAt(position)
    if square == nil or square == true or type(square.getBuilding) ~= "function" then return nil, "place_unloaded" end
    local ok, building = pcall(square.getBuilding, square)
    if not ok then return nil, "probe_failed" end
    if building == nil then return nil, nil end
    local loaded
    ok, loaded = pcall(SpawnPolicy.cornersLoaded, building, math.floor(position.x), math.floor(position.y))
    if not ok or loaded ~= true then return nil, "window_edge" end
    ok, loaded = pcall(SpawnPolicy.windowLoaded, building, math.floor(position.x), math.floor(position.y))
    if not ok or loaded ~= true then return nil, "window_incomplete" end
    return building, nil
end

function SpawnPolicy.openingsNear(position)
    local building, deferred = SpawnPolicy.loadedBuilding(position)
    if deferred ~= nil then
        SpawnPolicy.claimDetail = deferred
        return false, "building_unloaded"
    end
    return SpawnPolicy.openingsOf(building)
end

function SpawnPolicy.openingsOf(building)
    if building == nil then return false, "no_building" end
    local ok
    local builder = ProjectALife.OutpostBuilder
    SpawnPolicy.claimDetail = "probe_failed"
    if builder == nil or type(builder.probeBuilding) ~= "function" then return false, "building_unloaded" end
    local probe
    ok, probe = pcall(builder.probeBuilding, building)
    if not ok or type(probe) ~= "table" then return false, "building_unloaded" end

    probe.complete = true
    return SpawnPolicy.openingsVerdict(probe)
end

SpawnPolicy.rimMargin = 8

function SpawnPolicy.rimNeed(population, now)
    local band, respawn = tonumber(population.edgeDehydrate) or 10, 0
    if type(population.edgeBands) == "function" then
        local first, second = population.edgeBands(now)
        band, respawn = tonumber(first) or band, tonumber(second) or 0
    end
    band = math.max(band, tonumber(population.edgeFloor) or 0)
    return math.max(band + SpawnPolicy.rimMargin, respawn)
end

function SpawnPolicy.clearOfRim(position, now)
    local population = ProjectALife.Population
    if population == nil or type(population.windowEdge) ~= "function" then return true end
    local edge = population.windowEdge(position, now)
    return edge == nil or edge >= SpawnPolicy.rimNeed(population, now)
end

function SpawnPolicy.claimNowMs()
    if type(SpawnPolicy.adapters.nowMs) == "function" then return tonumber(SpawnPolicy.adapters.nowMs()) or 0 end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function SpawnPolicy.claimBuilding(position, probe, options)
    if not validPosition(position) then return false, "position_invalid" end
    if SpawnPolicy.excludedRegionAt(position) ~= nil then return false, "inside_excluded_region" end
    local key, now, building
    if probe == nil then

        if squareAt(position) == nil then
            SpawnPolicy.claimDetail = "place_unloaded"
            return false, "building_unloaded"
        end
        key = math.floor(position.x) .. ":" .. math.floor(position.y) .. ":" .. math.floor(position.z)
        now = SpawnPolicy.claimNowMs()
        local cached = SpawnPolicy.claimCache[key]
        if cached ~= nil and now >= cached and now - cached < SpawnPolicy.claimCacheMs then
            SpawnPolicy.claimDetail = "cached"
            return false, "building_unloaded"
        end
        local deferred
        building, deferred = SpawnPolicy.loadedBuilding(position)
        if deferred ~= nil then
            SpawnPolicy.claimDetail = deferred
            if deferred == "window_edge" then SpawnPolicy.claimCache[key] = nil else SpawnPolicy.claimCache[key] = now end
            return false, "building_unloaded"
        end
    end
    local context, reason = contextFor({})
    if context == nil then return false, reason end
    if inSafehouse(position, context.safehouses) then return false, "inside_safehouse" end
    if inAdminZone(position, context.zones) then return false, "inside_no_spawn_zone" end
    if SpawnPolicy.inPlayerBase(position, nil, context.bases) then return false, "inside_player_base" end
    if SpawnPolicy.insidePlayerBuild(position, nil, context.built) then return false, "inside_player_build" end
    if SpawnPolicy.enclosedByPlayerBuild(position, nil, context.built) then return false, "inside_player_enclosure" end
    if probe ~= nil then
        return SpawnPolicy.openingsVerdict(probe, type(options) == "table" and options.ownBoards == true)
    end
    local reach = SpawnPolicy.reachVerdict(position, context)
    if reach == "sealed" then return false, "inside_sealed_base" end
    if reach == "unknown" then
        SpawnPolicy.claimDetail = "reach_unknown"
        return false, "building_unloaded"
    end
    local claimed
    claimed, reason = SpawnPolicy.openingsOf(building)
    if reason == "building_unloaded" then SpawnPolicy.claimCache[key] = now else SpawnPolicy.claimCache[key] = nil end
    if reason == "building_unloaded" and SpawnPolicy.claimDetail == "window_edge" then SpawnPolicy.claimCache[key] = nil end
    return claimed, reason
end

function SpawnPolicy.check(position, options, context)
    options = options or {}
    if not validPosition(position) then return false, "position_invalid" end
    local contextError
    if context == nil then context, contextError = contextFor(options) end
    if context == nil then return false, contextError or "spawn_policy_unavailable" end
    local normalized = {
        x = math.floor(tonumber(position.x)) + 0.5,
        y = math.floor(tonumber(position.y)) + 0.5,
        z = math.floor(tonumber(position.z)),
    }
    if SpawnPolicy.excludedRegionAt(normalized) ~= nil then return false, "inside_excluded_region" end

    local margin = options.installation == true
        and SpawnPolicy.installationMargin or nil
    local builtRadius = options.installation == true
        and SpawnPolicy.installationBuiltRadius or nil
    if options.allowProtected ~= true then
        if inSafehouse(normalized, context.safehouses, margin) then
            return false, "inside_safehouse"
        end
        if inAdminZone(normalized, context.zones) then
            return false, "inside_no_spawn_zone"
        end

        if options.adminPlaced ~= true
                and SpawnPolicy.inPlayerBase(normalized, margin, context.bases) then
            return false, "inside_player_base"
        end
    end
    local square = squareAt(normalized)
    if square == nil then return false, "square_unloaded" end
    if not squareFree(square) then return false, "square_blocked" end

    if SpawnPolicy.squareIsWater(square) then return false, "square_water" end

    local keepOut = tonumber(options.playerKeepOut) or SpawnPolicy.playerKeepOut
    local ring = ProjectALife.KeepOut
    if keepOut > 0 or options.drivingKeepOut == true then
        if context.players == nil then context.players = SpawnPolicy.playerPoints() end
        for _, point in ipairs(context.players) do
            local distance = tonumber(point.drivingKeepOut) or 0
            local dx, dy = normalized.x - point.x, normalized.y - point.y
            if dx * dx + dy * dy < distance * distance then
                return false, "moving_vehicle_approach"
            end
        end
    end
    if keepOut > 0 and ring ~= nil and type(ring.spotAllowed) == "function" then
        if context.players == nil then context.players = SpawnPolicy.playerPoints() end
        local cone = SpawnPolicy.keepOutSight == true and options.occluded ~= true and SpawnPolicy.keepOutCone or 0
        local clear, why = ring.spotAllowed(normalized.x, normalized.y, context.players,
            keepOut, cone, SpawnPolicy.keepOutHalfCos)
        if clear ~= true then
            if why == "in_cone" then return false, "in_player_view" end
            return false, "too_close_to_player"
        end
    end
    if keepOut > 0 and options.allowProtected ~= true and options.fairness ~= false then
        local fairness = ProjectALife.SpawnFairness
        if fairness ~= nil and type(fairness.refusal) == "function" then
            local why = fairness.refusal(normalized, options)
            if why ~= nil then return false, why end
        end
    end

    if options.allowProtected ~= true and not (options.adminPlaced == true and keepOut == 0) then
        context.rimAtMs = context.rimAtMs or SpawnPolicy.claimNowMs()
        if not SpawnPolicy.clearOfRim(normalized, context.rimAtMs) then return false, "window_rim" end
    end
    if type(options.validator) == "function" then
        local accepted, result = pcall(options.validator, normalized, square)
        if not accepted or result ~= true then return false, "candidate_filtered" end
    end

    if options.allowProtected ~= true
            and SpawnPolicy.insidePlayerBuild(normalized, builtRadius, context.built) then
        return false, "inside_player_build"
    end
    if options.allowProtected ~= true and options.adminPlaced ~= true
            and SpawnPolicy.enclosedByPlayerBuild(normalized, nil, context.built) then
        return false, "inside_player_enclosure"
    end
    if options.allowProtected ~= true and options.adminPlaced ~= true then
        local reach = SpawnPolicy.reachVerdict(normalized, context)
        if reach == "sealed" then return false, "inside_sealed_base" end
        if reach == "unknown" then return false, "reach_unknown" end
    end
    return true, nil, normalized, square
end

function SpawnPolicy.exactOptions()
    return { allowProtected = true, playerKeepOut = 0, drivingKeepOut = true }
end

function SpawnPolicy.probeExact(x, y, z)
    local allowed, reason = SpawnPolicy.check({ x = x + 0.5, y = y + 0.5, z = z }, SpawnPolicy.exactOptions())
    return allowed == true, reason
end

function SpawnPolicy.doomed(origin, options, context, radius)
    local cx, cy = math.floor(origin.x), math.floor(origin.y)
    local keepOut = tonumber(options.playerKeepOut) or SpawnPolicy.playerKeepOut
    local ring = ProjectALife.KeepOut
    if keepOut > 0 and ring ~= nil and type(ring.inCone) == "function" then
        if context.players == nil then context.players = SpawnPolicy.playerPoints() end
        local cone = 0
        if SpawnPolicy.keepOutSight == true and options.occluded ~= true then cone = SpawnPolicy.keepOutCone end
        local corners = { { cx - radius + 0.5, cy - radius + 0.5 }, { cx + radius + 0.5, cy - radius + 0.5 },
            { cx - radius + 0.5, cy + radius + 0.5 }, { cx + radius + 0.5, cy + radius + 0.5 } }
        for _, point in ipairs(context.players) do
            local close, seen = true, cone > 0 and (point.fx ~= nil or point.fy ~= nil)
            for _, corner in ipairs(corners) do
                local dx, dy = corner[1] - point.x, corner[2] - point.y
                if dx * dx + dy * dy >= keepOut * keepOut then close = false end
                if seen and not ring.inCone(point.x, point.y, point.fx or 0, point.fy or 0,
                        corner[1], corner[2], SpawnPolicy.keepOutHalfCos, cone) then
                    seen = false
                end
            end
            if close or seen then return true end
        end
    end
    if keepOut > 0 and options.allowProtected ~= true and options.fairness ~= false and options.stationed ~= true then
        local fairness = ProjectALife.SpawnFairness
        if fairness ~= nil and type(fairness.boxInsideRing) == "function"
                and fairness.boxInsideRing(cx, cy, radius, options) then
            return true
        end
    end
    if options.allowProtected == true or (options.adminPlaced == true and keepOut == 0) then return false end
    local population = ProjectALife.Population
    if population == nil or type(population.windowBoundsAt) ~= "function" then return false end
    context.rimAtMs = context.rimAtMs or SpawnPolicy.claimNowMs()
    local bounds = population.windowBoundsAt(context.rimAtMs)
    if bounds == nil or (tonumber(bounds.count) or 0) <= 0 then return false end
    local margin = SpawnPolicy.rimNeed(population, context.rimAtMs)
    local rings = keepOut > 0 and SpawnPolicy.ringRows(options) or nil
    for index = 1, bounds.count do
        local w = bounds[index]
        if cx - radius <= w[3] - margin and cx + radius >= w[1] + margin
                and cy - radius <= w[4] - margin and cy + radius >= w[2] + margin
                and not SpawnPolicy.insideRings(rings, math.max(cx - radius, w[1] + margin),
                    math.max(cy - radius, w[2] + margin), math.min(cx + radius, w[3] - margin),
                    math.min(cy + radius, w[4] - margin)) then
            return false
        end
    end
    return true
end

function SpawnPolicy.ringRows(options)
    local fairness = ProjectALife.SpawnFairness
    if fairness == nil or type(fairness.ringRows) ~= "function" then return nil end
    return fairness.ringRows(options)
end

function SpawnPolicy.insideRings(rows, x1, y1, x2, y2)
    if rows == nil then return false end
    for index = 1, #rows do
        local row = rows[index]
        local dx = math.max(math.abs(x1 + 0.5 - row.x), math.abs(x2 + 0.5 - row.x))
        local dy = math.max(math.abs(y1 + 0.5 - row.y), math.abs(y2 + 0.5 - row.y))
        if dx * dx + dy * dy < row.r2 then return true end
    end
    return false
end

function SpawnPolicy.cheapFilter(options)
    local keepOut = tonumber(options.playerKeepOut) or SpawnPolicy.playerKeepOut
    if options.allowProtected == true then return nil end
    local filter
    if keepOut > 0 then
        local rows = SpawnPolicy.ringRows(options)
        if rows ~= nil then filter = { rings = rows } end
    end
    local population = ProjectALife.Population
    if not (options.adminPlaced == true and keepOut == 0) and population ~= nil
            and type(population.windowEdge) == "function" then
        local now = SpawnPolicy.claimNowMs()
        filter = filter or {}
        filter.rimEdge, filter.rimNow, filter.rimNeed = population.windowEdge, now, SpawnPolicy.rimNeed(population, now)
        filter.at = { x = 0, y = 0 }
    end
    return filter
end

function SpawnPolicy.cheapRefused(filter, x, y)
    local rows = filter.rings
    if rows ~= nil then
        for index = 1, #rows do
            local row = rows[index]
            local dx, dy = x - row.x, y - row.y
            if dx * dx + dy * dy < row.r2 then return true end
        end
    end
    local edgeOf = filter.rimEdge
    if edgeOf ~= nil then
        local at = filter.at
        at.x, at.y = x, y
        local edge = edgeOf(at, filter.rimNow)
        if edge ~= nil and edge < filter.rimNeed then return true end
    end
    return false
end

function SpawnPolicy.searchDone(began, cursor)
    local spent = SpawnPolicy.claimNowMs() - began
    if spent < 0 then spent = 0 end
    SpawnPolicy.lastSearchMs = spent
    local stats = SpawnPolicy.searchStats
    if spent > stats.worstMs then stats.worstMs = spent end
    if cursor ~= nil then cursor.ring = nil end
end

function SpawnPolicy.searchPark(cursor, began, probe, reason, tested, radius, ring, offset, side)
    side = side + 1
    if side > 4 then
        side, offset = 1, offset + 1
        if offset > ring then ring, offset = ring + 1, -(ring + 1) end
    end
    if ring > radius then return false end
    cursor.ring, cursor.offset, cursor.side = ring, offset, side
    cursor.probe, cursor.reason, cursor.tested, cursor.radius = probe, reason, tested, radius
    SpawnPolicy.searchStats.sliced = SpawnPolicy.searchStats.sliced + 1
    local spent = SpawnPolicy.claimNowMs() - began
    SpawnPolicy.lastSearchMs = spent > 0 and spent or 0
    if SpawnPolicy.lastSearchMs > SpawnPolicy.searchStats.worstMs then
        SpawnPolicy.searchStats.worstMs = SpawnPolicy.lastSearchMs
    end
    return true
end

function SpawnPolicy.find(origin, options)
    options = options or {}
    if not validPosition(origin) then return nil, "position_invalid" end
    local context, contextError = contextFor(options)
    if context == nil then return nil, contextError or "spawn_policy_unavailable" end
    local began = SpawnPolicy.claimNowMs()
    local stats = SpawnPolicy.searchStats
    local cursor = type(options.cursor) == "table" and options.cursor or nil
    local resumed = cursor ~= nil and cursor.ring ~= nil
    local reason, radius, probe
    local ring0, offset0, side0, tested = 1, nil, 1, 0
    if resumed then
        reason, radius, probe = cursor.reason, cursor.radius, cursor.probe
        ring0, offset0, side0, tested = cursor.ring, cursor.offset, cursor.side, cursor.tested or 0
        stats.resumed = stats.resumed + 1
    else
        local allowed, why, normalized = SpawnPolicy.check(origin, options, context)
        if allowed then return normalized end
        if why == "moving_vehicle_approach" then return nil, why end
        reason = why
        radius = math.max(0, math.min(30,
            math.floor(tonumber(options.searchRadius) or SpawnPolicy.searchRadius)))
        if radius > 0 and SpawnPolicy.doomed(origin, options, context, radius) then
            SpawnPolicy.doomedSearches = SpawnPolicy.doomedSearches + 1
            return nil, reason or "no_valid_spawn_square"
        end
        probe = radius > 0 and SpawnPolicy.reachProbe(origin, radius) or nil
        stats.searches = stats.searches + 1
    end
    local filter = radius > 0 and SpawnPolicy.cheapFilter(options) or nil
    local budget, cap = tonumber(options.budgetMs), tonumber(options.refusedCap)
    local ox, oy, z = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z)
    local units, head, every, weight = 0, probe ~= nil and probe.head or 0, SpawnPolicy.searchClockEvery,
        SpawnPolicy.searchCheckWeight
    for ring = ring0, radius do
        for offset = (ring == ring0 and offset0 or -ring), ring do
            for side = ((ring == ring0 and offset == offset0) and side0 or 1), 4 do
                local dx, dy
                if side == 1 then dx, dy = offset, -ring
                elseif side == 2 then dx, dy = offset, ring
                elseif side == 3 then dx, dy = -ring, offset
                else dx, dy = ring, offset end
                local px, py = ox + dx + 0.5, oy + dy + 0.5
                units = units + 1
                local reached = true
                if filter ~= nil and SpawnPolicy.cheapRefused(filter, px, py) then
                    reached = false
                    stats.cheapRefused = stats.cheapRefused + 1
                elseif probe ~= nil then
                    local key = SpawnPolicy.squareKey(ox + dx, oy + dy, z)
                    if budget ~= nil and cursor ~= nil then
                        reached = SpawnPolicy.reachesWithin(probe, key, began, budget)
                        if reached == nil then
                            SpawnPolicy.probeCharge(probe)
                            SpawnPolicy.searchPark(cursor, began, probe, reason, tested, radius, ring, offset, side - 1)
                            return nil, "sliced"
                        end
                    else
                        reached = SpawnPolicy.reaches(probe, key)
                    end
                end
                if reached then
                    SpawnPolicy.probeCharge(probe)
                    tested = tested + 1
                    stats.tested = stats.tested + 1
                    units = units + weight
                    local ok, _, result = SpawnPolicy.check({ x = px, y = py, z = z }, options, context)
                    if ok then
                        SpawnPolicy.searchDone(began, cursor)
                        return result
                    end
                    if cap ~= nil and tested >= cap then
                        stats.capped = stats.capped + 1
                        SpawnPolicy.probeCharge(probe)
                        SpawnPolicy.searchDone(began, cursor)
                        return nil, "refused_cap"
                    end
                end
                if probe ~= nil then
                    units = units + (probe.head - head)
                    head = probe.head
                end
                if budget ~= nil and cursor ~= nil and units >= every then
                    units = 0
                    if SpawnPolicy.claimNowMs() - began >= budget then
                        SpawnPolicy.probeCharge(probe)
                        if SpawnPolicy.searchPark(cursor, began, probe, reason, tested, radius,
                                ring, offset, side) then
                            return nil, "sliced"
                        end
                    end
                end
            end
        end
    end
    SpawnPolicy.probeCharge(probe)
    SpawnPolicy.searchDone(began, cursor)
    return nil, reason or "no_valid_spawn_square"
end

function SpawnPolicy.hidden(position)
    local population = ProjectALife.Population
    if population ~= nil and type(population.inPlayerView) == "function" and population.inPlayerView(position) then
        return false
    end
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and type(fairness.enabled) == "function" and fairness.enabled()
            and type(fairness.seen) == "function"
            and fairness.seen(tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.z) or 0, nil, true, true) then
        return false
    end
    return true
end

SpawnPolicy.sampleRadii = { 14, 20, 28, 40, 52 }
SpawnPolicy.sampleSteps = 12
SpawnPolicy.sampleLinks = 4
SpawnPolicy.sampleTurn = 0

function SpawnPolicy.candidate(origin, dx, dy)
    return {
        x = math.floor(origin.x) + dx + 0.5,
        y = math.floor(origin.y) + dy + 0.5,
        z = math.floor(origin.z),
    }
end

function SpawnPolicy.findSampled(origin, options, maxRadius)
    options = options or {}
    if not validPosition(origin) then return nil, "position_invalid" end
    local context, contextError = contextFor(options)
    if context == nil then return nil, contextError or "spawn_policy_unavailable" end
    local limit = math.max(1, math.min(80, math.floor(tonumber(maxRadius) or 52)))
    local steps = SpawnPolicy.sampleSteps
    SpawnPolicy.sampleTurn = SpawnPolicy.sampleTurn + 1
    local phase = (SpawnPolicy.sampleTurn * 5) % steps
    local links = 0
    for _, radius in ipairs(SpawnPolicy.sampleRadii) do
        if radius <= limit then
            for index = 0, steps - 1 do
                local angle = ((index + phase) % steps) * (2 * math.pi / steps)
                local point = SpawnPolicy.candidate(origin, math.floor(math.cos(angle) * radius + 0.5),
                    math.floor(math.sin(angle) * radius + 0.5))
                local ok, _, result = SpawnPolicy.check(point, options, context)
                if ok then
                    local linked = SpawnPolicy.linked(origin, result)
                    links = links + 1
                    if linked ~= false then return result end
                    if links >= SpawnPolicy.sampleLinks then return nil, "sample_unlinked" end
                end
            end
        end
    end
    return nil, "no_valid_spawn_square"
end

function SpawnPolicy.homeRefusal(position, context)
    if not validPosition(position) then return nil end
    if context == nil then context = contextFor({}) end
    if context == nil then return nil end
    if SpawnPolicy.inPlayerBase(position, nil, context.bases) then return "inside_player_base" end
    local reach = SpawnPolicy.reachVerdict(position, context)
    if reach == "sealed" then return "inside_sealed_base" end
    if reach == "unknown" then return "reach_unknown" end
    return nil
end

function SpawnPolicy.findOutside(position, options, context)
    options = options or {}
    if not validPosition(position) then return nil, "position_invalid" end
    local contextError
    if context == nil then context, contextError = contextFor(options) end
    if context == nil then return nil, contextError or "spawn_policy_unavailable" end
    local boxes = {}
    local base = SpawnPolicy.baseAt(position, nil, context.bases)
    if base ~= nil then
        local pad = SpawnPolicy.safehouseMargin + 2
        boxes[#boxes + 1] = { x1 = base.x1 - pad, y1 = base.y1 - pad, x2 = base.x2 + pad, y2 = base.y2 + pad }
    end
    local zone = SpawnPolicy.reachZone(position, context.reachZones)
    if zone ~= nil then
        boxes[#boxes + 1] = { x1 = zone.x1 - 1, y1 = zone.y1 - 1, x2 = zone.x2 + 1, y2 = zone.y2 + 1 }
    end
    local z = math.floor(position.z)
    for _, box in ipairs(boxes) do
        local points = {}
        for x = math.floor(box.x1), math.floor(box.x2), 2 do
            points[#points + 1] = { x = x + 0.5, y = math.floor(box.y1) + 0.5, z = z }
            points[#points + 1] = { x = x + 0.5, y = math.floor(box.y2) + 0.5, z = z }
        end
        for y = math.floor(box.y1) + 2, math.floor(box.y2) - 1, 2 do
            points[#points + 1] = { x = math.floor(box.x1) + 0.5, y = y + 0.5, z = z }
            points[#points + 1] = { x = math.floor(box.x2) + 0.5, y = y + 0.5, z = z }
        end
        for _, point in ipairs(points) do
            point.d = (point.x - position.x) ^ 2 + (point.y - position.y) ^ 2
        end
        table.sort(points, SpawnPolicy.nearerFirst)
        for index = 1, math.min(#points, 160) do
            local ok, _, result = SpawnPolicy.check(points[index], options, context)
            if ok then return result end
        end
    end
    return nil, "no_square_outside"
end

function SpawnPolicy.nearerFirst(a, b) return a.d < b.d end

return SpawnPolicy
