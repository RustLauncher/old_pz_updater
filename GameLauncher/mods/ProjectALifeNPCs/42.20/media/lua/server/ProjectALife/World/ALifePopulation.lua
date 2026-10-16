require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/World/ALifeSpawnService"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/Core/ALifeWatchdog"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local SpawnService = ProjectALife.SpawnService
local PlayerLocator = ProjectALife.PlayerLocator
local SpawnPolicy = ProjectALife.SpawnPolicy
local Watchdog = ProjectALife.Watchdog
local Population = {
    adapters = {},
    order = {},
    cursor = 0,
    lastSyncAtMs = -math.huge,
    lastTickAtMs = 0,
    syncIntervalMs = 2000,
    tickIntervalMs = 500,

    viewRetryMs = 2000,
    metrics = {},
    spawnDistance = 60,
    dehydrateDistance = 90,

    arrivalDistance = 30,

    postDistance = 12,
    warmUpMs = 60000,
    activationGraceMs = 3000,
    noPlayerGraceMs = 5000,
    activeSinceMs = {},
    noPlayerSinceMs = nil,
    retryAtMs = {},
    retryCount = {},

    requestLimit = 1,
    dehydrateLimit = 2,
    edgeParkLimit = 6,
    findLimit = 2,
    catchUpMs = 16,
    findsThisTick = 0,
    batchLeft = 0,
    searchBudgetMs = 4,
    tickSearchMs = 8,
    searchRefusedCap = 900,
    searchCursorTtlMs = 15000,
    negFindMs = 3000,
    searchSpentMs = 0,
    searchCursors = {},
    noFind = {},
    noFindCount = 0,

    edgeDehydrate = 10,
    edgeRespawn = 20,
    edgeLeadS = 1.5,
    edgeSpeedCap = 16,
    playerTrack = {},

    holdNearTiles = {},

    restoredInPlace = {},
    restoreScanned = false,
    restoredAtHours = nil,
    boundRows = { count = 0 },
}
ProjectALife.Population = Population

local function nowMs()
    if type(Population.adapters.nowMs) == "function" then return Population.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function players()
    return PlayerLocator.list(Population.adapters.players)
end

local function playerPosition(player)
    return PlayerLocator.position(player, Population.adapters.playerPosition)
end

local function onlinePositions(online)
    local result = {}
    for _, player in ipairs(online) do
        local candidate = playerPosition(player)
        if candidate ~= nil then result[#result + 1] = candidate end
    end
    return result
end

local function nearestDistanceSquared(position, positions)
    local nearest = math.huge
    for _, candidate in ipairs(positions) do
        local dx, dy, dz = position.x - candidate.x,
            position.y - candidate.y, position.z - candidate.z
        nearest = math.min(nearest, dx * dx + dy * dy + dz * dz)
    end
    return nearest
end

local function actorPosition(actor)
    if actor.lifecycle == "active" then
        local binding = Watchdog.bindings[actor.uid]
        local shell = binding and binding.generation == actor.generation and binding.shell or nil
        local kind = type(shell)
        if (kind == "userdata" or kind == "table") and shell.getX ~= nil
                and shell.getY ~= nil and shell.getZ ~= nil then
            return { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
        end
    end
    return actor.worldPosition
end

local function handoffPending(actor)
    local squadId = actor.memory and actor.memory.squadId
    local ledger = ProjectALife.SquadLedger
    local squad = squadId and ledger and ledger.read(squadId)
    return squad ~= nil and (squad.releasePending ~= nil or squad.stagePending ~= nil)
end

function Population.capacityUsed(includeNearby)
    local located = includeNearby and onlinePositions(players()) or {}
    local count = 0
    Registry.each(function(actor)
        if actor.lifecycle == "active" or actor.lifecycle == "spawning"
                or (includeNearby and actor.lifecycle == "dormant"
                    and nearestDistanceSquared(actor.worldPosition, located)
                        <= Population.spawnDistance * Population.spawnDistance) then
            count = count + 1
        end
    end)
    return count
end

local function worldHours()
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return tonumber(hours)
end

local function expendable(actor)
    local memory = actor.memory
    if type(memory) ~= "table" then return true end
    local admin = type(memory.admin) == "table" and memory.admin or nil
    return memory.persistent ~= true
        and not (admin ~= nil and admin.persistent == true)
        and memory.adminAnchor ~= true
        and memory.encounter == nil
end

local function sync(now)
    if now - Population.lastSyncAtMs < Population.syncIntervalMs then return end
    if not Population.restoreScanned then Population.scanRestored() end
    Population.order = {}

    local live = {}
    Registry.each(function(actor)
        if actor.lifecycle ~= "dead" then
            Population.order[#Population.order + 1] = actor.uid
            live[actor.uid] = true
        end
    end)
    for uid in pairs(Population.holds) do
        if live[uid] ~= true then Population.holds[uid] = nil end
    end
    for uid in pairs(Population.reachSince) do
        if live[uid] ~= true then Population.reachSince[uid] = nil end
    end
    for uid in pairs(Population.wantedSince) do
        if live[uid] ~= true then Population.wantedSince[uid] = nil end
    end
    for uid in pairs(Population.searchCursors) do
        if live[uid] ~= true then Population.searchCursors[uid] = nil end
    end
    Population.cursor = math.min(Population.cursor, #Population.order)
    Population.lastSyncAtMs = now
end

function Population.configure(adapters)
    Population.adapters = adapters or {}
    Population.spawnDistance = tonumber(Population.adapters.spawnDistance) or 60
    Population.dehydrateDistance = math.max(
        Population.spawnDistance + 10,
        tonumber(Population.adapters.dehydrateDistance) or 90)
    Population.activationGraceMs = math.max(0,
        tonumber(Population.adapters.activationGraceMs) or 3000)
    Population.noPlayerGraceMs = math.max(0,
        tonumber(Population.adapters.noPlayerGraceMs) or 5000)
end

function Population.reset()
    Population.order = {}
    Population.cursor = 0
    Population.lastSyncAtMs = -math.huge
    Population.lastTickAtMs = 0
    Population.retryAtMs = {}
    Population.retryCount = {}
    Population.activeSinceMs = {}
    Population.noPlayerSinceMs = nil
    Population.warmUntilMs = nil
    Population.requestLimit = 1
    Population.dehydrateLimit = 2
    Population.edgeParkLimit = 6
    Population.playerTrack = {}
    Population.findLimit = 2
    Population.findsThisTick = 0
    Population.batchLeft = 0
    Population.searchSpentMs = 0
    Population.searchCursors, Population.noFind, Population.noFindCount = {}, {}, 0
    Population.holdNearTiles = {}
    Population.reachHolds = {}
    Population.edgeHolds = {}
    Population.holds = {}
    Population.reachSince = {}
    Population.wantedSince = {}
    Population.restoredInPlace = {}
    Population.restoreScanned = false
    Population.restoredAtHours = nil
    Population.bounds, Population.boundsAtMs = nil, nil
    Population.drivenAtMs, Population.drivingAtMs, Population.drivingNow = nil, nil, nil
end

Population.dormantTtlHours = 8

function Population.configureTtl(hours)
    Population.dormantTtlHours = math.max(0, math.floor(tonumber(hours) or 8))
end

local function inPlayerView(position)
    if type(isServer) == "function" and isServer() then return false end
    if type(position) ~= "table" then return false end
    local seen = false
    pcall(function()
        local square = getCell():getGridSquare(math.floor(position.x),
            math.floor(position.y), math.floor(position.z or 0))
        if square == nil then return end
        for index = 0, 3 do
            local player = getSpecificPlayer(index)
            if player ~= nil and square:isCanSee(index) == true then
                seen = true
                return
            end
        end
    end)
    return seen
end
Population.inPlayerView = inPlayerView

Population.chunkTiles = 8
Population.widthMin = 12
Population.widthMax = 20
Population.keepFallback = 64
Population.keepSlack = 8
Population.keeps = setmetatable({}, { __mode = "k" })

function Population.keepFromWidth(width)
    local chunks = tonumber(width)
    if chunks == nil or chunks - chunks ~= 0 then return nil end
    chunks = math.max(Population.widthMin, math.min(Population.widthMax, math.floor(chunks)))
    return (math.floor(chunks / 2) + 2) * Population.chunkTiles
end

function Population.noteWidth(player, width)
    local keep = Population.keepFromWidth(width)
    if player == nil or keep == nil then return false end
    Population.keeps[player] = keep
    return true
end

function Population.keepFor(player)
    return Population.keeps[player] or Population.keepFallback
end

function Population.handleClientCommand(module, command, player, arguments)
    if module ~= "ProjectALife" or command ~= "windowWidth" or player == nil then return false end
    if type(isServer) == "function" and not isServer() then return false end
    return Population.noteWidth(player, type(arguments) == "table" and arguments.width or nil)
end

local function serverRows(rows)
    local count = 0
    for _, player in ipairs(players()) do
        local at = playerPosition(player)
        local x, y = at and tonumber(at.x), at and tonumber(at.y)
        if x ~= nil and y ~= nil then
            local reach = Population.keepFor(player) - Population.keepSlack
            count = count + 1
            local row = rows[count] or {}
            rows[count] = row
            row[1], row[2] = math.floor(x - reach), math.floor(y - reach)
            row[3], row[4] = math.floor(x + reach), math.floor(y + reach)
        end
    end
    return count
end

function Population.windowBoundsAt(now)
    if Population.boundsAtMs == now then return Population.bounds end
    Population.boundsAtMs = now
    Population.bounds = nil
    local rows = Population.boundRows
    if type(isServer) == "function" and isServer() then
        rows.count = serverRows(rows)
        if rows.count > 0 then Population.bounds = rows end
        return Population.bounds
    end
    if type(getCell) ~= "function" or type(getSpecificPlayer) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or cell.getChunkMap == nil then return nil end

    local count = 0
    for index = 0, 3 do
        if getSpecificPlayer(index) ~= nil then
            local map = cell:getChunkMap(index)
            if map ~= nil and map.getWorldXMinTiles ~= nil and map.getWorldXMaxTiles ~= nil
                    and map.getWorldYMinTiles ~= nil and map.getWorldYMaxTiles ~= nil then
                count = count + 1
                local row = rows[count] or {}
                rows[count] = row
                row[1], row[2] = map:getWorldXMinTiles(), map:getWorldYMinTiles()
                row[3], row[4] = map:getWorldXMaxTiles() - 1, map:getWorldYMaxTiles() - 1
            end
        end
    end
    rows.count = count
    if count > 0 then Population.bounds = rows end
    return Population.bounds
end

function Population.windowEdge(position, now)
    local bounds = Population.windowBoundsAt(now or nowMs())
    if bounds == nil or type(position) ~= "table" then return nil end
    local x, y = tonumber(position.x), tonumber(position.y)
    if x == nil or y == nil then return nil end
    x, y = math.floor(x), math.floor(y)
    local best
    for index = 1, bounds.count do
        local w = bounds[index]
        local edge = math.min(x - w[1], w[3] - x, y - w[2], w[4] - y)
        if best == nil or edge > best then best = edge end
    end
    return best
end

function Population.adminHeld(actor)
    local memory = type(actor.memory) == "table" and actor.memory or nil
    return memory ~= nil and type(memory.admin) == "table" and memory.admin.persistent == true
end

function Population.nearWindowEdge(position, now, tiles)
    local edge = Population.leadEdge(position, now)
    return edge ~= nil and edge < tiles
end

function Population.leadEdge(position, now)
    local bounds = Population.windowBoundsAt(now or nowMs())
    if bounds == nil or type(position) ~= "table" then return nil end
    local x, y = tonumber(position.x), tonumber(position.y)
    if x == nil or y == nil then return nil end
    x, y = math.floor(x), math.floor(y)
    local lx, ly = Population.leadOf(x, y)
    local best
    for index = 1, bounds.count do
        local w = bounds[index]
        local west, east, north, south = x - w[1], w[3] - x, y - w[2], w[4] - y
        if lx > 0 then west = west - lx elseif lx < 0 then east = east + lx end
        if ly > 0 then north = north - ly elseif ly < 0 then south = south + ly end
        local edge = math.min(west, east, north, south)
        if best == nil or edge > best then best = edge end
    end
    return best
end

function Population.trackPlayers(located, now)
    local track = Population.playerTrack
    for index, at in ipairs(located) do
        local row = track[index]
        if row == nil then
            row = { vx = 0, vy = 0 }
            track[index] = row
        end
        local seconds = row.atMs ~= nil and (now - row.atMs) / 1000 or 0
        if seconds > 0 and seconds < 5 then
            row.vx, row.vy = (at.x - row.x) / seconds, (at.y - row.y) / seconds
        elseif seconds >= 5 or seconds < 0 then
            row.vx, row.vy = 0, 0
        end
        row.x, row.y, row.atMs = at.x, at.y, now
    end
    track.count = #located
end

function Population.leadOf(x, y)
    local track = Population.playerTrack
    local count = tonumber(track.count) or 0
    if count == 0 then return 0, 0 end
    local nearest, best = nil, math.huge
    for index = 1, count do
        local row = track[index]
        if row ~= nil and row.x ~= nil then
            local d = (x - row.x) ^ 2 + (y - row.y) ^ 2
            if d < best then nearest, best = row, d end
        end
    end
    if nearest == nil then return 0, 0 end
    local vx, vy = nearest.vx, nearest.vy
    if vx * vx + vy * vy < 1 then return 0, 0 end
    local cap, lead = Population.edgeSpeedCap, Population.edgeLeadS
    return math.max(-cap, math.min(cap, vx * lead)), math.max(-cap, math.min(cap, vy * lead))
end

Population.youngMs = 15000
Population.edgeFloor = 8
Population.driveKmh = 15
Population.driveHoldMs = 8000
Population.driveDehydrate = 40
Population.driveRespawn = 48
Population.sweepUids = {}

function Population.engaged(actor)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.inCombat) == "function" then return talk.inCombat(actor) == true end
    return actor.activity == "combat"
end

function Population.driving(now)
    if Population.drivingAtMs == now then return Population.drivingNow end
    Population.drivingAtMs = now
    if type(getSpecificPlayer) == "function" then
        for index = 0, 3 do
            local player = getSpecificPlayer(index)
            local ok, speed = pcall(SpawnPolicy.vehicleSpeed, player)
            if ok and speed ~= nil and math.abs(speed) >= Population.driveKmh then
                Population.drivenAtMs = now
            end
        end
    end
    local driven = Population.drivenAtMs
    Population.drivingNow = driven ~= nil and now >= driven and now - driven < Population.driveHoldMs
    return Population.drivingNow
end

function Population.edgeBands(now)
    now = now or nowMs()
    if Population.driving(now) then
        return math.max(Population.edgeDehydrate, Population.driveDehydrate),
            math.max(Population.edgeRespawn, Population.driveRespawn)
    end
    return Population.edgeDehydrate, Population.edgeRespawn
end

function Population.edgeParks(actor, now)
    local edge = Population.leadEdge(actorPosition(actor), now)
    if edge == nil then return false end
    if edge < Population.edgeFloor then return true end
    if edge >= (Population.edgeBands(now)) then return false end
    local binding = Watchdog.bindings[actor.uid]
    local since = Population.activeSinceMs[actor.uid] or (binding and tonumber(binding.boundAtMs))
    if (since ~= nil and now - since < Population.youngMs) or Population.engaged(actor) then
        Population.metrics.edgeSpared = (Population.metrics.edgeSpared or 0) + 1
        return false
    end
    return true
end

local function forgetActivation(uid)
    Population.retryAtMs[uid] = nil
    Population.retryCount[uid] = nil
    Population.holdNearTiles[uid] = nil
    Population.restoredInPlace[uid] = nil
    Population.holds[uid], Population.reachSince[uid] = nil, nil
    Population.wantedSince[uid] = nil
end

function Population.edgeSweep(now)
    now = now or nowMs()
    local bounds = Population.windowBoundsAt(now)
    local abandoned = bounds == nil and type(isServer) == "function" and isServer() and #players() == 0
    if bounds == nil and not abandoned then return 0 end
    local order, uids = Watchdog.order, Population.sweepUids
    local count = #order
    for index = 1, count do uids[index] = order[index] end
    for index = #uids, count + 1, -1 do uids[index] = nil end
    local parked = 0
    for index = 1, count do
        local actor = (Registry.peek or Registry.read)(uids[index])
        local reason
        if actor ~= nil and actor.lifecycle == "active" then
            if abandoned then
                reason = "no_players_online"
            elseif not Population.adminHeld(actor) and Population.edgeParks(actor, now) then
                reason = "window_edge"
            end
        end
        if reason ~= nil and SpawnService.dehydrate(actor.uid, reason) == true then
            if not abandoned then
                Population.metrics.edgeDehydrated = (Population.metrics.edgeDehydrated or 0) + 1
            end
            forgetActivation(actor.uid)
            Population.activeSinceMs[actor.uid] = nil
            parked = parked + 1
        end
    end
    return parked
end

function Population.holdNear(uid, tiles)
    if type(uid) ~= "string" then return false end
    Population.holdNearTiles[uid] = tonumber(tiles)
    return true
end

function Population.nearEnough(uid, distanceSquared)
    local tiles = Population.holdNearTiles[uid]
    return tiles == nil or distanceSquared <= tiles * tiles
end

function Population.worldHoursNow()
    if type(getGameTime) ~= "function" then return nil end
    local clock = getGameTime()
    if clock == nil or clock.getWorldAgeHours == nil then return nil end
    return tonumber(clock:getWorldAgeHours())
end

function Population.scanRestored()
    Population.restoreScanned = true
    Population.restoredAtHours = Population.worldHoursNow()
    local guard = ProjectALife.OrphanGuard
    local count = 0
    Registry.each(function(actor)
        if actor.lifecycle == "dormant" and (tonumber(actor.generation) or 0) > 0
                and ((actor.memory and actor.memory.restoreAfterSave == true)
                    or (guard and type(guard.savedAt) == "function" and guard.savedAt(actor.worldPosition))) then
            Population.restoredInPlace[actor.uid] = true
            count = count + 1
        end
    end)
    Population.metrics.restoredInPlace = count
    return count
end

function Population.restoresInPlace(actor, now)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.visit) == "table" or type(memory.guest) == "table" then return false end
    if memory.restoreAfterSave == true then return true end
    if Population.restoredInPlace[actor.uid] ~= true or now >= (Population.warmUntilMs or math.huge) then return false end
    if Population.exempt(actor) or memory.natural ~= true or SpawnPolicy == nil or type(SpawnPolicy.inPlayerBase) ~= "function"
            or type(actor.worldPosition) ~= "table" then
        return true
    end
    return not SpawnPolicy.inPlayerBase(actor.worldPosition, 0)
end

Population.ghostWaitMs = 10000
Population.ghostRetryMs = 1000

function Population.ghostCleared(actor, now)
    local guard = ProjectALife.OrphanGuard
    if guard == nil or type(guard.savedAt) ~= "function" or not guard.savedAt(actor.worldPosition) then
        return true
    end
    local warm = Population.warmUntilMs
    return warm ~= nil and now >= warm - Population.warmUpMs + Population.ghostWaitMs
end

function Population.dormantSince(actor)
    local since = tonumber(actor.memory and actor.memory.dormantSinceHours) or 0
    if Population.restoredInPlace[actor.uid] ~= true then return since end
    local restored = tonumber(Population.restoredAtHours)
    if restored ~= nil and restored > since then return restored end
    return since
end

local function scheduleRetry(uid, now, failed)
    if not failed then
        Population.retryAtMs[uid], Population.retryCount[uid] = nil, nil
        return
    end
    local attempts = math.min(6, (Population.retryCount[uid] or 0) + 1)
    Population.retryCount[uid] = attempts
    Population.retryAtMs[uid] = now + math.min(60000, 1000 * (2 ^ attempts))
end

local function scheduleAttempt(uid, now)
    local attempts = math.min(6, (Population.retryCount[uid] or 0) + 1)
    Population.retryCount[uid] = attempts
    Population.retryAtMs[uid] = now
        + math.max(8000, math.min(60000, 1000 * (2 ^ attempts)))
end

function Population.stationed(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
    return memory.adminAnchor == true or memory.garrisonPost ~= nil or memory.holdPost == true
        or (memory.outpostId ~= nil and memory.outpostSquadId == nil)
        or (memory.stance ~= nil and memory.stance ~= "" and memory.stance ~= "route")
end

function Population.exempt(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
    return type(memory.admin) == "table" or memory.adminAnchor == true
        or memory.outpostId ~= nil or memory.garrisonPost ~= nil or memory.holdPost == true
end

function Population.hydrateReach(actor)
    local fairness = ProjectALife.SpawnFairness
    if fairness == nil or type(fairness.hydrateReach) ~= "function" then return Population.spawnDistance end
    return fairness.hydrateReach(actor, Population.spawnDistance, Population.exempt(actor),
        Population.stationed(actor), actorPosition(actor))
end

Population.settledRetryMs = 1500
Population.settledForceMs = 15000
Population.settledStaleMs = 60000
Population.settledUnseenTries = 6
Population.settledBiasTries = 10
Population.settledTries = 16
Population.settledRadius = 52
Population.wantedSince = {}

function Population.settled(actor, mode)
    if mode ~= "stationed" then return false end
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory == nil then return false end
    if memory.revengeKey ~= nil or memory.targetUsername ~= nil or memory.knowledgeFix ~= nil then return false end
    return memory.persistent == true or memory.outpostId ~= nil or memory.garrisonPost ~= nil
        or memory.holdPost == true
end

function Population.settledSpot(actor, options, now)
    local row = Population.wantedSince[actor.uid]
    if row == nil or row.lastMs > now or now - row.lastMs > Population.settledStaleMs then
        row = { sinceMs = now }
        Population.wantedSince[actor.uid] = row
    end
    row.lastMs = now
    local since = row.sinceMs
    local spot = SpawnPolicy.findSampled(actor.worldPosition, options, Population.settledRadius)
    if spot ~= nil then
        Population.metrics.settledSampled = (Population.metrics.settledSampled or 0) + 1
        return spot
    end
    if now - since < Population.settledForceMs then return nil end
    local fairness = ProjectALife.SpawnFairness
    local located = onlinePositions(players())
    if fairness == nil or type(fairness.ringPoint) ~= "function" or #located == 0 then return nil end
    local home = actor.worldPosition
    local at, nearestSq = located[1], math.huge
    for _, candidate in ipairs(located) do
        local gx, gy = candidate.x - home.x, candidate.y - home.y
        if gx * gx + gy * gy < nearestSq then at, nearestSq = candidate, gx * gx + gy * gy end
    end
    local low, high = fairness.band(at.x, at.y)
    for attempt = 1, Population.settledTries do
        local toward = attempt <= Population.settledBiasTries
        local point = fairness.ringPoint(at.x, at.y, low, high, toward and home.x or nil, toward and home.y or nil)
        if point ~= nil then
            point.z = 0
            local rule = { playerKeepOut = low, validator = options.validator }
            if attempt <= Population.settledUnseenTries then rule.stationed = true else rule.fairness = false end
            local ok, _, result = SpawnPolicy.check(point, rule)
            if ok == true then
                Population.metrics.settledFallback = (Population.metrics.settledFallback or 0) + 1
                return result
            end
        end
    end
    return nil
end

Population.healRetryMs = 10000
Population.reachHoldMaxMs = 30000
Population.reachHolds = {}
Population.edgeHolds = {}
Population.holds = {}
Population.reachSince = {}
Population.stuckAfterMs = 30000
Population.stuckRetryMs = 4000
Population.moveReleaseTiles = 8
Population.moveReleaseGapMs = 1000

function Population.guardOn()
    local read = Watchdog.reloadGuard
    return type(read) == "function" and read() == true
end

function Population.fixedPost(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
    return memory.adminAnchor == true or memory.garrisonPost ~= nil or memory.holdPost == true
end

function Population.noteHold(uid, why, now, located, release)
    local row = Population.holds[uid]
    if row == nil then
        row = {}
        Population.holds[uid] = row
    end
    row.why, row.atMs, row.release = why, now, release == true
    local at = located ~= nil and located[1] or nil
    if at ~= nil then row.px, row.py = at.x, at.y else row.px, row.py = nil, nil end
end

function Population.holdInfo(uid, now)
    local row = Population.holds[uid]
    local retry = tonumber(Population.retryAtMs[uid])
    local info = { why = row ~= nil and row.why or nil, retryS = 0, ageS = 0 }
    if retry ~= nil and now ~= nil and retry > now then info.retryS = math.ceil((retry - now) / 1000) end
    if row ~= nil and row.atMs ~= nil and now ~= nil then info.ageS = math.max(0, math.floor((now - row.atMs) / 1000)) end
    return info
end

function Population.releaseOnMove(uid, now, located)
    local row = Population.holds[uid]
    local retry = Population.retryAtMs[uid]
    if row == nil or row.px == nil or row.release ~= true or retry == nil or retry <= now then return false end
    if now - (row.atMs or now) < Population.moveReleaseGapMs or not Population.guardOn() then return false end
    local tiles = Population.moveReleaseTiles
    for _, at in ipairs(located) do
        local dx, dy = at.x - row.px, at.y - row.py
        if dx * dx + dy * dy >= tiles * tiles then
            Population.retryAtMs[uid] = nil
            row.px, row.py = nil, nil
            Population.metrics.heldReleased = (Population.metrics.heldReleased or 0) + 1
            return true
        end
    end
    return false
end

function Population.nearestTiles(position, located)
    if type(position) ~= "table" or located == nil or #located == 0 then return nil end
    local best = nearestDistanceSquared(position, located)
    if best == math.huge then return nil end
    return math.floor(math.sqrt(best) + 0.5)
end

function Population.keptOut(actor, now, exempt)
    if exempt or type(SpawnPolicy.homeRefusal) ~= "function" then return nil end
    local context = type(SpawnPolicy.context) == "function" and SpawnPolicy.context({}) or nil
    local why = SpawnPolicy.homeRefusal(actor.worldPosition, context)
    if why == "reach_unknown" then
        local holds = math.min(8, (Population.reachHolds[actor.uid] or 0) + 1)
        Population.reachHolds[actor.uid] = holds
        Population.metrics.heldForReach = (Population.metrics.heldForReach or 0) + 1
        return math.min(Population.reachHoldMaxMs, Population.viewRetryMs * 2 ^ (holds - 1))
    end
    Population.reachHolds[actor.uid] = nil
    if why == nil then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local fairness = ProjectALife.SpawnFairness
    local mayRetire = fairness == nil or type(fairness.mayRemove) ~= "function"
        or fairness.mayRemove(actor.worldPosition)
    if why == "inside_player_base" and memory.encounter ~= nil and memory.squadId == nil and mayRetire then
        Registry.remove(actor.uid, actor.revision, why)
        Population.metrics.retiredInBase = (Population.metrics.retiredInBase or 0) + 1
        return Population.viewRetryMs
    end
    local outside = type(SpawnPolicy.findOutside) == "function"
        and SpawnPolicy.findOutside(actor.worldPosition, { playerKeepOut = 0 }, context) or nil
    if outside == nil then return Population.healRetryMs end
    Registry.update(actor.uid, actor.revision, function(record) record.worldPosition = outside end)
    Population.metrics.movedOutOfBase = (Population.metrics.movedOutOfBase or 0) + 1
    return 0
end

function Population.squareLoaded(x, y, z)
    if type(Population.adapters.squareLoaded) == "function" then
        return Population.adapters.squareLoaded(x, y, z) == true
    end
    if type(getCell) ~= "function" then return true end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) ~= nil
end

Population.widenRadius = 30
Population.widenAfter = 2

function Population.widens(actor)
    if not Population.guardOn() or Population.fixedPost(actor) then return false end
    return (Population.retryCount[actor.uid] or 0) >= Population.widenAfter
end

function Population.stuck(uid, now)
    local since = Population.reachSince[uid]
    if since == nil then
        Population.reachSince[uid] = now
        return false
    end
    return now >= since and now - since >= Population.stuckAfterMs and Population.guardOn()
end

function Population.searchState(actor, now)
    local at = actor.worldPosition
    local ox, oy = math.floor(at.x), math.floor(at.y)
    local state = Population.searchCursors[actor.uid]
    if state == nil or state.ox ~= ox or state.oy ~= oy or now < state.atMs
            or now - state.atMs > Population.searchCursorTtlMs then
        state = { cursor = {}, ox = ox, oy = oy, atMs = now }
        Population.searchCursors[actor.uid] = state
    end
    return state
end

function Population.searchLeft()
    return math.max(0, Population.tickSearchMs - Population.searchSpentMs)
end

function Population.noteSearch(ms)
    ms = tonumber(ms) or 0
    Population.searchSpentMs = Population.searchSpentMs + ms
    if ms > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then runtime.noteDetail("population:find", ms) end
    end
end

function Population.negKey(actor, reach, located, closest, flags)
    local at, player = actor.worldPosition, located[1]
    return math.floor(at.x) .. ":" .. math.floor(at.y) .. ":" .. tostring(reach) .. ":" .. tostring(closest) .. ":"
        .. flags .. ":" .. (player ~= nil and (math.floor(player.x / 8) .. ":" .. math.floor(player.y / 8)) or "-")
end

function Population.negHit(key, now)
    local at = Population.noFind[key]
    if at ~= nil and now >= at and now - at < Population.negFindMs then
        Population.metrics.searchNegHits = (Population.metrics.searchNegHits or 0) + 1
        return true
    end
    return false
end

function Population.negStore(key, now)
    if Population.noFindCount >= 64 then Population.noFind, Population.noFindCount = {}, 0 end
    if Population.noFind[key] == nil then Population.noFindCount = Population.noFindCount + 1 end
    Population.noFind[key] = now
end

function Population.qaLine()
    local stats = type(SpawnPolicy.searchStats) == "table" and SpawnPolicy.searchStats or {}
    local metrics = Population.metrics
    return "[ALIFE-QA] PopulationSearch: searches=" .. tostring(stats.searches or 0)
        .. " sliced=" .. tostring(stats.sliced or 0)
        .. " resumed=" .. tostring(stats.resumed or 0)
        .. " backoffs=" .. tostring(metrics.searchBackoffs or 0)
        .. " negCacheHits=" .. tostring(metrics.searchNegHits or 0)
        .. " worstMs=" .. tostring(stats.worstMs or 0)
        .. " cheapRefused=" .. tostring(stats.cheapRefused or 0)
        .. " tested=" .. tostring(stats.tested or 0)
        .. " capped=" .. tostring(stats.capped or 0)
        .. " tickBudgetSkips=" .. tostring(metrics.searchTickSkips or 0)
end

function Population.limitHit(requested, dehydrated, edgeParked)
    return requested >= (tonumber(Population.requestLimit) or 1)
        or dehydrated >= (tonumber(Population.dehydrateLimit) or 2)
        or edgeParked >= (tonumber(Population.edgeParkLimit) or 6)
        or Population.findsThisTick >= (tonumber(Population.findLimit) or 2)
end

function Population.noteBurst(began, requested)
    local spent = nowMs() - began
    if spent > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then
            runtime.noteDetail("population:tick:r" .. tostring(requested), spent)
        end
    end
end

function Population.tick(budget)
    local now = nowMs()
    Population.searchSpentMs = 0

    local carried = #Population.order > 0 and math.max(0, tonumber(Population.batchLeft) or 0) or 0
    local due = now - Population.lastTickAtMs >= Population.tickIntervalMs
    if carried <= 0 and not due then return 0 end
    Population.batchLeft = 0

    local overdue = due and carried or 0
    local maximum = carried
    if due then maximum = carried + math.max(1, math.floor(tonumber(budget) or 1)) end
    if due and overdue == 0 then
        Population.lastTickAtMs = now
        sync(now)
    end
    local online = players()
    local located = onlinePositions(online)
    local _, respawnBand = Population.edgeBands(now)

    if due and #located > 0 then
        Population.noPlayerSinceMs = nil

        Population.warmUntilMs = Population.warmUntilMs or (now + Population.warmUpMs)
        Population.trackPlayers(located, now)
        local fairness = ProjectALife.SpawnFairness
        if fairness ~= nil and type(fairness.noteTick) == "function" then fairness.noteTick(located, now) end
    elseif due and #online == 0 then
        Population.noPlayerSinceMs = Population.noPlayerSinceMs or now
        Population.warmUntilMs = nil
    elseif due then

        Population.noPlayerSinceMs = nil
    end
    local processed, requested, dehydrated, edgeParked = 0, 0, 0, 0
    local processed, requested, dehydrated = 0, 0, 0
    Population.findsThisTick = 0
    while processed < maximum and #Population.order > 0 do
        Population.cursor = (Population.cursor % #Population.order) + 1

        local actor = (Registry.peek or Registry.read)(Population.order[Population.cursor])
        local catalog = ProjectALife.Catalog
        local deleted = actor and catalog and catalog.deletedReason
            and catalog.deletedReason(actor.factionId, actor.profileId)
        if deleted then
            SpawnService.retire(actor.uid, deleted)
            actor = nil
        end
        if actor and actor.lifecycle ~= "dead" then
            if actor.lifecycle == "active" and Population.activeSinceMs[actor.uid] == nil then
                Population.activeSinceMs[actor.uid] = now

                Population.retryAtMs[actor.uid] = nil
                Population.retryCount[actor.uid] = nil
                Population.holdNearTiles[actor.uid] = nil
                Population.edgeHolds[actor.uid] = nil
                Population.restoredInPlace[actor.uid] = nil
                Population.holds[actor.uid], Population.reachSince[actor.uid] = nil, nil
            elseif actor.lifecycle ~= "active" then
                Population.activeSinceMs[actor.uid] = nil
            end
            local distance = #located > 0
                and nearestDistanceSquared(actorPosition(actor), located) or math.huge
            if actor.lifecycle == "dormant" and (Population.holds[actor.uid] ~= nil
                    or Population.reachSince[actor.uid] ~= nil) then
                if Population.holds[actor.uid] ~= nil and Population.holds[actor.uid].why == "unloaded"
                        and Population.squareLoaded(actor.worldPosition.x, actor.worldPosition.y, actor.worldPosition.z) then
                    Population.retryAtMs[actor.uid] = nil
                    Population.holds[actor.uid] = nil
                    Population.metrics.heldReleased = (Population.metrics.heldReleased or 0) + 1
                end
                Population.releaseOnMove(actor.uid, now, located)
                if Population.reachSince[actor.uid] ~= nil
                        and distance > Population.hydrateReach(actor) ^ 2 then
                    Population.reachSince[actor.uid] = nil
                end
            end
            local activationSettled = now - (Population.activeSinceMs[actor.uid] or now)
                >= Population.activationGraceMs
            local noPlayersSettled = #online == 0 and Population.noPlayerSinceMs ~= nil
                and now - Population.noPlayerSinceMs >= Population.noPlayerGraceMs
            if noPlayersSettled and actor.lifecycle == "active" and activationSettled then
                SpawnService.dehydrate(actor.uid, "no_players_online")
                dehydrated = dehydrated + 1
            elseif #located > 0 and actor.lifecycle == "dormant"
                    and Population.dormantTtlHours > 0
                    and expendable(actor)
                    and distance > Population.spawnDistance * Population.spawnDistance
                    and tonumber(actor.memory and actor.memory.dormantSinceHours) ~= nil
                    and (worldHours() or 0) - Population.dormantSince(actor)
                        >= Population.dormantTtlHours then

                Registry.remove(actor.uid, actor.revision, "dormant_ttl")
            elseif #located > 0 and actor.lifecycle == "dormant"
                    and not handoffPending(actor)
                    and distance <= Population.hydrateReach(actor) ^ 2
                    and not Population.squareLoaded(actor.worldPosition.x, actor.worldPosition.y, actor.worldPosition.z) then
                Population.retryAtMs[actor.uid] = now + Population.ghostRetryMs
                Population.noteHold(actor.uid, "unloaded", now, located)
                Population.metrics.heldForUnloaded = (Population.metrics.heldForUnloaded or 0) + 1
            elseif #located > 0 and actor.lifecycle == "dormant"
                    and not handoffPending(actor)
                    and distance <= Population.hydrateReach(actor) ^ 2
                    and not Population.nearEnough(actor.uid, distance) then
                local hold = Population.holds[actor.uid]
                if hold ~= nil and hold.release == true then
                    hold.why = "owner_window"
                else
                    Population.noteHold(actor.uid, "owner_window", now, located)
                end
            elseif #located > 0 and actor.lifecycle == "dormant"
                    and not handoffPending(actor)
                    and distance <= Population.hydrateReach(actor) ^ 2
                    and Population.nearEnough(actor.uid, distance)
                    and now >= (Population.retryAtMs[actor.uid] or 0) then
                local allowProtected = actor.memory and actor.memory.adminAnchor == true

                local exempt = Population.exempt(actor)
                local fairness = ProjectALife.SpawnFairness
                local fairMode = fairness ~= nil and type(fairness.actorMode) == "function"
                    and fairness.actorMode(actor, exempt, Population.stationed(actor)) or "off"
                local settled = Population.settled(actor, fairMode)
                local arriving = not settled and ((tonumber(actor.generation) or 0) == 0
                    or (now >= (Population.warmUntilMs or math.huge)
                        and not Population.stationed(actor)))
                local closest = arriving and Population.arrivalDistance
                    or (tonumber(SpawnPolicy.postKeepOut) or Population.postDistance)
                local inPlace = Population.restoresInPlace(actor, now)
                local fairOff
                if fairMode == "off" then fairOff = false end
                local kept = Population.keptOut(actor, now, exempt)
                local stuck = exempt and Population.stuck(actor.uid, now)
                local spawnPosition
                local sliced = false
                if inPlace and not Population.ghostCleared(actor, now) then
                    spawnPosition = false
                elseif kept ~= nil then
                    spawnPosition = false
                elseif inPlace then
                    Population.findsThisTick = Population.findsThisTick + 1
                    spawnPosition = SpawnPolicy.find(actor.worldPosition, { allowProtected = true,
                        adminPlaced = true, searchRadius = 2, playerKeepOut = 0 })
                else
                    local reach = allowProtected and 4 or 12
                    local options = {
                        allowProtected = allowProtected,
                        adminPlaced = exempt or nil,
                        searchRadius = reach,

                        playerKeepOut = allowProtected and 0 or closest,
                        fairness = fairOff,
                        stationed = fairMode == "stationed" or nil,

                        validator = function(candidate)
                            return (stuck or not inPlayerView(candidate))
                                and (allowProtected or nearestDistanceSquared(candidate, located) >= closest * closest)
                        end,
                    }
                    local state = Population.searchState(actor, now)
                    local first = state.attempt or 1
                    if first == 2 then reach = state.reach or Population.widenRadius end
                    for attempt = first, 2 do
                        if Population.searchLeft() <= 0 then
                            sliced = true
                            state.attempt, state.reach = attempt, reach
                            Population.metrics.searchTickSkips = (Population.metrics.searchTickSkips or 0) + 1
                            break
                        end
                        local negKey = Population.negKey(actor, reach, located, closest,
                            (allowProtected and "p" or "-") .. (exempt and "x" or "-") .. (stuck and "s" or "-") .. fairMode)
                        local why
                        if Population.negHit(negKey, now) then
                            spawnPosition = nil
                        else
                            Population.findsThisTick = Population.findsThisTick + 1
                            SpawnPolicy.lastSearchMs = 0
                            spawnPosition, why = SpawnPolicy.find(actor.worldPosition, {
                                allowProtected = allowProtected,
                                adminPlaced = exempt or nil,
                                searchRadius = reach,

                                playerKeepOut = allowProtected and 0 or closest,
                                fairness = fairOff,
                                stationed = fairMode == "stationed" or nil,
                                cursor = state.cursor,
                                budgetMs = math.min(Population.searchBudgetMs, Population.searchLeft()),
                                refusedCap = Population.searchRefusedCap,

                                validator = options.validator,
                            })
                            Population.noteSearch(SpawnPolicy.lastSearchMs)
                            if why == "sliced" then
                                sliced = true
                                state.attempt, state.reach = attempt, reach
                                break
                            end
                            if spawnPosition == nil then Population.negStore(negKey, now) end
                        end
                        if spawnPosition ~= nil then
                            if attempt == 2 then
                                Population.metrics.widenedHydrate = (Population.metrics.widenedHydrate or 0) + 1
                            end
                            if stuck and inPlayerView(spawnPosition) then
                                Population.metrics.stuckForced = (Population.metrics.stuckForced or 0) + 1
                            end
                            break
                        end
                        if allowProtected or not (settled or Population.widens(actor)) then break end
                        reach = Population.widenRadius
                    end
                    if spawnPosition == nil and settled and not allowProtected then
                        Population.findsThisTick = Population.findsThisTick + 1
                        spawnPosition = Population.settledSpot(actor, options, now)
                        if spawnPosition ~= nil then sliced = false end
                    end
                    if not sliced then Population.searchCursors[actor.uid] = nil end
                end
                if sliced then
                    Population.metrics.searchPending = (Population.metrics.searchPending or 0) + 1
                elseif spawnPosition == false and kept ~= nil then
                    Population.retryAtMs[actor.uid] = now + kept
                    Population.noteHold(actor.uid, "kept_out", now, located)
                    Population.metrics.heldForKept = (Population.metrics.heldForKept or 0) + 1
                elseif spawnPosition == false then
                    Population.retryAtMs[actor.uid] = now + Population.ghostRetryMs
                    Population.noteHold(actor.uid, "ghost", now, located)
                    Population.metrics.heldForGhost = (Population.metrics.heldForGhost or 0) + 1
                elseif spawnPosition == nil then
                    local seen = inPlayerView(actor.worldPosition)
                    if seen then
                        Population.metrics.heldForView = (Population.metrics.heldForView or 0) + 1
                    else
                        Population.metrics.heldForNoSquare = (Population.metrics.heldForNoSquare or 0) + 1
                    end
                    scheduleRetry(actor.uid, now, true)
                    Population.metrics.searchBackoffs = (Population.metrics.searchBackoffs or 0) + 1
                    if stuck then
                        Population.retryAtMs[actor.uid] = math.min(Population.retryAtMs[actor.uid],
                            now + Population.stuckRetryMs)
                    end
                    if settled then
                        Population.retryAtMs[actor.uid] = math.min(Population.retryAtMs[actor.uid],
                            now + Population.settledRetryMs)
                    end
                    Population.noteHold(actor.uid, seen and "view" or "no_square", now, located, exempt)
                elseif not inPlace and Population.nearWindowEdge(spawnPosition, now, respawnBand) then

                    local edgeHolds = math.min(4, (Population.edgeHolds[actor.uid] or 0) + 1)
                    Population.edgeHolds[actor.uid] = edgeHolds
                    Population.retryAtMs[actor.uid] = now + Population.viewRetryMs * 2 ^ (edgeHolds - 1)
                    if settled then
                        Population.retryAtMs[actor.uid] = math.min(Population.retryAtMs[actor.uid],
                            now + Population.settledRetryMs)
                    end
                    Population.metrics.heldForEdge = (Population.metrics.heldForEdge or 0) + 1
                    Population.noteHold(actor.uid, "edge", now, located, true)
                elseif Population.capacityUsed(false) >= (ProjectALife.Settings
                        and ProjectALife.Settings.current
                        and tonumber(ProjectALife.Settings.current.maximumHostileActors) or 32)
                        and not stuck then
                    Population.retryAtMs[actor.uid] = now + Population.viewRetryMs
                    Population.metrics.heldForCapacity = (Population.metrics.heldForCapacity or 0) + 1
                    Population.noteHold(actor.uid, "capacity", now, located)
                else
                    if stuck and Population.capacityUsed(false) >= (ProjectALife.Settings
                            and ProjectALife.Settings.current
                            and tonumber(ProjectALife.Settings.current.maximumHostileActors) or 32) then
                        Population.metrics.stuckCapacity = (Population.metrics.stuckCapacity or 0) + 1
                    end
                    if spawnPosition.x ~= actor.worldPosition.x
                            or spawnPosition.y ~= actor.worldPosition.y
                            or spawnPosition.z ~= actor.worldPosition.z then
                        local relocated = Registry.update(actor.uid, actor.revision, function(record)
                            record.worldPosition = spawnPosition
                        end)
                        if relocated == nil then
                            scheduleRetry(actor.uid, now, true)
                            actor = nil
                        else
                            actor = relocated
                        end
                    end
                    if actor ~= nil then
                        local nextGeneration = actor.generation + 1
                        local request = SpawnService.request(
                            actor.uid,
                            "proximity:spawn:" .. actor.uid .. ":" .. nextGeneration,
                            actor.uid .. ":" .. nextGeneration .. ":"
                                .. tostring(spawnPosition.x) .. ":" .. tostring(spawnPosition.y),
                            2500)
                        requested = requested + 1
                        if request == nil then
                            scheduleRetry(actor.uid, now, true)
                        else

                            scheduleAttempt(actor.uid, now)
                            Population.holds[actor.uid] = nil
                            Population.wantedSince[actor.uid] = nil
                            if fairness ~= nil and type(fairness.noteHydrate) == "function" then
                                fairness.noteHydrate(actor, spawnPosition, fairMode)
                            end
                        end
                    end
                end
            elseif #located > 0 and actor.lifecycle == "dormant" and handoffPending(actor)
                    and distance <= Population.spawnDistance * Population.spawnDistance then
                Population.noteHold(actor.uid, "handoff", now, located)
                Population.metrics.heldForHandoff = (Population.metrics.heldForHandoff or 0) + 1
            elseif #located > 0 and actor.lifecycle == "active" and activationSettled
                    and distance >= Population.dehydrateDistance * Population.dehydrateDistance then
                SpawnService.dehydrate(actor.uid, "outside_simulation_radius")
                dehydrated = dehydrated + 1
            elseif #located > 0 and actor.lifecycle == "active" and activationSettled
                    and not Population.adminHeld(actor)
                    and Population.edgeParks(actor, now) then
                if SpawnService.dehydrate(actor.uid, "window_edge") == true then
                    Population.metrics.edgeDehydrated = (Population.metrics.edgeDehydrated or 0) + 1
                    edgeParked = edgeParked + 1
                end
            end
        end
        processed = processed + 1
        local limited = Population.limitHit(requested, dehydrated, edgeParked)
        local late = limited and nowMs() - now >= Population.catchUpMs
        if processed == overdue then

            Population.lastTickAtMs = now
            sync(now)
            requested, dehydrated = 0, 0
            edgeParked = 0
            Population.findsThisTick = 0
            if late and processed < maximum then
                Population.batchLeft = maximum - processed
                break
            end
        elseif limited and processed < maximum and (processed > overdue or late) then
            Population.batchLeft = (processed < overdue and overdue or maximum) - processed
            break
        end
    end
    Population.noteBurst(now, requested)
    return processed
end

if type(Events) == "table" and Events.OnClientCommand ~= nil
        and type(Events.OnClientCommand.Add) == "function" then
    Events.OnClientCommand.Add(Population.handleClientCommand)
end

return Population
