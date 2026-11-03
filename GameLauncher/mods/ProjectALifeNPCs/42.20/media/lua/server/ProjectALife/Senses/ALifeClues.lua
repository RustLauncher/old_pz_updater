ProjectALife = ProjectALife or {}

local Clues = {
    zones = {},

    maximumZones = 24,
    enabled = true,
    weightMultiplier = 1,
    sources = { vehicles = true, barricades = true, playerBuilt = true, power = true },

    investigateThreshold = 3,
    zoneLifetimeMs = 240000,
    claimHoldMs = 30000,

    searchRadius = 22,
    lookIntervalMs = 500,
    vehicleIntervalMs = 2000,

    searchCooldownMs = 180000,

    maximumRooms = 6,
    metrics = { discovered = 0, zones = 0 },
}
ProjectALife.Clues = Clues

local EVIDENCE = {
    engine      = { weight = 8, cap = 8,  live = true,  source = "vehicles" },
    vehicle     = { weight = 3, cap = 6,  live = true,  source = "vehicles" },
    generator   = { weight = 5, cap = 5,  live = true,  source = "power" },
    barricade   = { weight = 3, cap = 6,  live = false, source = "barricades" },
    playerBuilt = { weight = 2, cap = 6,  live = false, source = "playerBuilt" },
}

local function partyKey(actor)
    local group = actor and actor.memory and actor.memory.groupId or nil
    if type(group) == "string" and group ~= "" then return "g:" .. group end
    return "a:" .. tostring(actor and actor.uid or "")
end

Clues.partyKey = partyKey

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Clues.configure(options)
    options = options or {}
    if options.enabled ~= nil then Clues.enabled = options.enabled ~= false end
    if options.weightMultiplier ~= nil then
        Clues.weightMultiplier = math.max(0, math.min(5,
            tonumber(options.weightMultiplier) or 1))
    end
    for key, value in pairs(options.sources or {}) do
        if Clues.sources[key] ~= nil then Clues.sources[key] = value ~= false end
    end
    return true
end

function Clues.reset()
    Clues.zones = {}
    Clues.metrics = { discovered = 0, zones = 0 }
end

local function zoneKeyFor(square, x, y, z)
    local key
    pcall(function()
        local building = square ~= nil and square:getBuilding() or nil
        if building ~= nil then key = "b:" .. tostring(building:getID()) end
    end)
    if key ~= nil then return key end
    return string.format("g:%d:%d:%d",
        math.floor(x / 10), math.floor(y / 10), math.floor(z or 0))
end

local function evictWeakest()
    local weakestKey, weakestScore
    for key, zone in pairs(Clues.zones) do
        if weakestScore == nil or zone.score < weakestScore then
            weakestKey, weakestScore = key, zone.score
        end
    end
    if weakestKey ~= nil then Clues.zones[weakestKey] = nil end
end

local function countZones()
    local count = 0
    for _ in pairs(Clues.zones) do count = count + 1 end
    return count
end

function Clues.record(kind, x, y, z, square)
    if not Clues.enabled then return false end
    local evidence = EVIDENCE[kind]
    if evidence == nil then return false end
    if Clues.sources[evidence.source] == false then return false end

    local key = zoneKeyFor(square, x, y, z)
    local zone = Clues.zones[key]
    if zone == nil then
        if countZones() >= Clues.maximumZones then evictWeakest() end
        zone = {
            key = key, x = x, y = y, z = z or 0,
            score = 0, kinds = {}, atMs = nowMs(),
            claimedBy = nil, claimedUntilMs = 0, searchedBy = {},
        }
        Clues.zones[key] = zone
        Clues.metrics.zones = Clues.metrics.zones + 1
    end

    local already = zone.kinds[kind] or 0
    if already >= evidence.cap then return false end
    local added = math.min(evidence.weight, evidence.cap - already)
    zone.kinds[kind] = already + added
    zone.score = zone.score + added
    zone.atMs = nowMs()
    if evidence.live then zone.liveAtMs = zone.atMs end

    if evidence.live then zone.x, zone.y, zone.z = x, y, z or 0 end
    Clues.metrics.discovered = Clues.metrics.discovered + 1
    return true
end

local function examineSquare(square)
    if square == nil then return end
    local x, y, z
    local ok = pcall(function() x, y, z = square:getX(), square:getY(), square:getZ() end)
    if not ok then return end

    pcall(function()
        local objects = square:getObjects()
        if objects == nil then return end
        local count = math.min(objects:size(), 24)
        for index = 0, count - 1 do
            local object = objects:get(index)
            if object ~= nil then

                local thumpable = instanceof(object, "IsoThumpable")
                if Clues.sources.barricades
                        and (thumpable
                            or instanceof(object, "IsoWindow")
                            or instanceof(object, "IsoDoor")
                            or instanceof(object, "IsoWindowFrame")) then
                    local barricaded = false
                    pcall(function() barricaded = object:isBarricaded() == true end)
                    if barricaded then Clues.record("barricade", x, y, z, square) end
                end

                if Clues.sources.playerBuilt and thumpable then
                    Clues.record("playerBuilt", x, y, z, square)
                end

                if Clues.sources.power and instanceof(object, "IsoGenerator") then
                    local live = false
                    pcall(function() live = object:isActivated() == true end)
                    if live then Clues.record("generator", x, y, z, square) end
                end
            end
        end
    end)

end

local function lookAround(shell)
    local ok, cell, x, y, z = pcall(function()
        return getCell(), math.floor(shell:getX()), math.floor(shell:getY()),
            math.floor(shell:getZ())
    end)
    if not ok or cell == nil then return end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square
            pcall(function() square = cell:getGridSquare(x + dx, y + dy, z) end)
            examineSquare(square)
        end
    end
end

Clues.vehicleRange = 12
Clues.vehicleFallbackRadius = 5
Clues.maximumVehicles = 4

local function vehicleArray()
    local list
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local vehicles = cell:getVehicles()
        if vehicles == nil or vehicles.toArray == nil then return end
        list = vehicles:toArray()
    end)
    return list
end

local function scanVehicleSquares(shell, consider)
    local ok, cell, sx, sy, sz = pcall(function()
        return getCell(), math.floor(shell:getX()), math.floor(shell:getY()),
            math.floor(shell:getZ())
    end)
    if not ok or cell == nil then return end
    local radius = Clues.vehicleFallbackRadius
    for dx = -radius, radius do
        for dy = -radius, radius do
            local vehicle
            pcall(function()
                local square = cell:getGridSquare(sx + dx, sy + dy, sz)
                if square ~= nil then vehicle = square:getVehicleContainer() end
            end)
            if vehicle ~= nil and consider(vehicle) == false then return end
        end
    end
end

local function scanVehicles(shell)
    local ok, sx, sy = pcall(function() return shell:getX(), shell:getY() end)
    if not ok then return end

    local reach = Clues.vehicleRange * Clues.vehicleRange
    local seen, distinct = {}, 0

    local function consider(vehicle)
        local id
        pcall(function() id = vehicle:getId() end)
        id = id or tostring(vehicle)
        if seen[id] ~= nil then return true end
        seen[id] = true

        local vx, vy, vz, vsquare, running, hotwired
        pcall(function()
            vx, vy, vz = vehicle:getX(), vehicle:getY(), vehicle:getZ()
            vsquare = vehicle:getSquare()
            running = vehicle:isEngineRunning() == true
            hotwired = vehicle:isHotwired() == true
        end)
        if vx == nil then return true end
        local dx, dy = vx - sx, vy - sy

        if dx * dx + dy * dy > reach then return true end

        distinct = distinct + 1
        if running then
            Clues.record("engine", vx, vy, vz, vsquare)
        elseif hotwired then
            Clues.record("vehicle", vx, vy, vz, vsquare)
        end
        return distinct < Clues.maximumVehicles
    end

    local list = vehicleArray()
    if list == nil then
        scanVehicleSquares(shell, consider)
        return
    end
    for _, vehicle in pairs(list) do
        if vehicle ~= nil and consider(vehicle) == false then return end
    end
end

function Clues.observe(actor, shell, now)
    if not Clues.enabled then return false end
    local data
    local ok = pcall(function() data = shell:getModData() end)
    if not ok or type(data) ~= "table" then return false end

    if now >= (tonumber(data.ProjectALifeNextLookAtMs) or 0) then
        data.ProjectALifeNextLookAtMs = now + Clues.lookIntervalMs
        lookAround(shell)
    end
    if Clues.sources.vehicles
            and now >= (tonumber(data.ProjectALifeNextVehicleScanAtMs) or 0) then
        data.ProjectALifeNextVehicleScanAtMs = now + Clues.vehicleIntervalMs
        scanVehicles(shell)
    end
    return true
end

local function standableNear(x, y, z)
    local floorX, floorY, floorZ = math.floor(x), math.floor(y), math.floor(z or 0)
    local free = false
    pcall(function()
        local square = getCell():getGridSquare(floorX, floorY, floorZ)
        free = square ~= nil and square:isFree(false) == true
    end)
    if free then return x, y, z end
    local bestX, bestY, bestFlat
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local candidate = false
                pcall(function()
                    local square = getCell():getGridSquare(
                        floorX + dx, floorY + dy, floorZ)
                    candidate = square ~= nil and square:isFree(false) == true
                end)
                if candidate then
                    local flat = dx * dx + dy * dy
                    if bestFlat == nil or flat < bestFlat then
                        bestX, bestY, bestFlat = floorX + dx, floorY + dy, flat
                    end
                end
            end
        end
    end
    if bestX == nil then return x, y, z end
    return bestX + 0.5, bestY + 0.5, z
end

function Clues.homeKept(actor, zone)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.homeRefusal) ~= "function" then return false end
    local kind = policy.homeRefusal(actor, zone.x, zone.y)
    if kind == nil then return false end
    policy.note("clue", kind)
    return true
end

function Clues.selectZone(actor, shell, now, maximumDistance)
    if not Clues.enabled then return nil end
    local ok, sx, sy = pcall(function() return shell:getX(), shell:getY() end)
    if not ok then return nil end

    local reach = (tonumber(maximumDistance) or 60) ^ 2
    local presence = ProjectALife.ModuleTalkPresence
    local refuses = presence ~= nil and type(presence.refusesLead) == "function" and presence.refusesLead or nil
    local threshold = Clues.investigateThreshold / math.max(0.1, Clues.weightMultiplier)
    local best, bestScore
    for key, zone in pairs(Clues.zones) do
        if now - zone.atMs > Clues.zoneLifetimeMs then
            Clues.zones[key] = nil
        elseif zone.score >= threshold
                and (zone.searchedBy[partyKey(actor)] or 0) <= now then
            local claimed = zone.claimedBy ~= nil
                and zone.claimedBy ~= actor.uid
                and now < zone.claimedUntilMs
            local dx, dy = zone.x - sx, zone.y - sy
            local flat = dx * dx + dy * dy
            if flat <= reach and Clues.homeKept(actor, zone) then flat = math.huge end
            if flat <= reach and (refuses == nil or not refuses(actor, shell, zone, now)) then

                local rating = zone.score / (1 + flat / 100)
                if claimed then rating = rating * 0.15 end
                if bestScore == nil or rating > bestScore then
                    best, bestScore = zone, rating
                end
            end
        end
    end
    if best == nil then return nil end
    best.claimedBy = actor.uid
    best.claimedUntilMs = now + Clues.claimHoldMs
    local x, y, z = standableNear(best.x, best.y, best.z)
    return { x = x, y = y, z = z, key = best.key, score = best.score }
end

function Clues.markSearched(actor, key, suppliedNow)
    local zone = Clues.zones[key]
    if zone == nil then return false end
    local now = tonumber(suppliedNow) or nowMs()
    zone.searchedBy[partyKey(actor)] = now + Clues.searchCooldownMs
    if zone.claimedBy == actor.uid then zone.claimedBy = nil end
    return true
end

function Clues.roomsToSearch(square, maximum)
    if square == nil then return nil end
    local rooms
    pcall(function()
        local building = square:getBuilding()
        if building == nil then return end
        local definition = building:getDef()
        if definition == nil or definition.getRooms == nil then return end
        local list = definition:getRooms()
        if list == nil then return end

        local here = 0
        pcall(function() here = math.floor(square:getZ()) end)
        local near, far = {}, {}
        local count = math.min(list:size(), 32)
        for index = 0, count - 1 do
            local room = list:get(index)
            if room ~= nil then
                local tile
                pcall(function() tile = getCell():getFreeTile(room) end)
                if tile ~= nil then
                    local point
                    pcall(function()
                        point = { x = tile:getX(), y = tile:getY(), z = tile:getZ() }
                    end)
                    if point ~= nil then
                        local bucket = (math.floor(point.z) == here) and near or far
                        bucket[#bucket + 1] = point
                    end
                end
            end
        end
        local limit = math.max(1, math.floor(tonumber(maximum) or Clues.maximumRooms))
        rooms = {}
        for _, point in ipairs(near) do
            if #rooms >= limit then break end
            rooms[#rooms + 1] = point
        end
        for _, point in ipairs(far) do
            if #rooms >= limit then break end
            rooms[#rooms + 1] = point
        end
        if #rooms == 0 then rooms = nil end
    end)
    return rooms
end

return Clues
