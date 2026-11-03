require "ProjectALife/Core/ALifePersistence"

require "ProjectALife/Records/ALifeFactionSpawnRules"
ProjectALife = ProjectALife or {}

ProjectALife.RaidClient = ProjectALife.RaidClient or {}

local RaidDirector = {
    settings = {
        enabled = true,
        minDay = 30,
        cooldownDays = 21,
        chancePerCheckPct = 0.01,
        checkEveryMinutes = 10,
        waves = 3,
        groupSize = 6,
        maxAttackers = 8,
        distanceTiles = 30,
        waveDelayMinutes = 5,
        heli = true,
        sirenAircraft = true,
        warningHours = 3,
        approachMinTiles = 40,
        approachMaxTiles = 50,
        houseClearanceTiles = 30,

        gunfireDelayMs = 30000,
        preludeSeconds = 10,
        introSeconds = 2.85,
        firstWaveReadyMs = 12850,
        firstWaveFallbackMs = 16000,
        clientGateTiles = 120,
        scoutBuildupHours = 6,
        scoutLifetimeHours = 48,
        scoutSize = 3,
        spawnTimeoutMs = 120000,
    },
    adapters = {},
    state = nil,
    nextCheckAtMs = 0,
    nextCheckHour = 0,
    scoutRequestId = nil,
    sequence = 0,
    fallbackStore = { lastHour = -1e9 },
    metrics = { checks = 0, started = 0, waves = 0, refused = 0, ended = 0, scouts = 0, scoutFailures = 0,
        warnings = 0, placementRefused = 0 },
}
ProjectALife.RaidDirector = RaidDirector

local function clamp(value, minimum, maximum, fallback)
    return math.max(minimum, math.min(maximum,
        math.floor(tonumber(value) or fallback)))
end

local function nowMs()
    if type(RaidDirector.adapters.nowMs) == "function" then
        return tonumber(RaidDirector.adapters.nowMs()) or 0
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function calendar()
    if type(RaidDirector.adapters.calendar) == "function" then
        local day, hours = RaidDirector.adapters.calendar()
        return math.floor(tonumber(day) or 0), tonumber(hours) or 0
    end
    local day, hours = 0, 0
    pcall(function()
        local gameTime = getGameTime()
        day = gameTime:getNightsSurvived()
        hours = gameTime:getWorldAgeHours()
    end)
    return math.floor(tonumber(day) or 0), tonumber(hours) or 0
end

local function random()
    if type(RaidDirector.adapters.random) == "function" then
        return math.max(0, math.min(0.999999,
            tonumber(RaidDirector.adapters.random()) or 0))
    end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    return math.random()
end

local function store()
    if type(RaidDirector.adapters.store) == "function" then
        local supplied = RaidDirector.adapters.store()
        if type(supplied) == "table" then return supplied end
    end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.bucket) == "function" then
        local value = persistence.bucket("raid", { lastHour = -1e9 })
        if type(value) == "table" then return value end
    end
    return RaidDirector.fallbackStore
end

local function dirty()
    if type(RaidDirector.adapters.dirty) == "function" then
        RaidDirector.adapters.dirty()
        return
    end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
end

function RaidDirector.configure(adapters)
    RaidDirector.adapters = type(adapters) == "table" and adapters or {}
    for key, bounds in pairs({ minDay = { 0, 3650 }, cooldownDays = { 0, 3650 },
            chancePerCheckPct = { 0, 100 }, checkEveryMinutes = { 1, 1440 },
            waves = { 1, 10 }, groupSize = { 1, 12 }, waveDelayMinutes = { 1, 60 },
            maxAttackers = { 1, 48 }, warningHours = { 0, 24 },
            scoutBuildupHours = { 0, 720 }, scoutLifetimeHours = { 1, 1440 }, scoutSize = { 1, 12 } }) do
        local value = tonumber(RaidDirector.adapters[key])
        if value ~= nil and value == value then
            RaidDirector.settings[key] = math.max(bounds[1], math.min(bounds[2], value))
        end
    end
    for _, key in ipairs({ "enabled", "heli", "sirenAircraft" }) do
        if RaidDirector.adapters[key] ~= nil then RaidDirector.settings[key] = RaidDirector.adapters[key] == true end
    end
    RaidDirector.nextCheckAtMs = 0
    RaidDirector.nextCheckHour = 0
    return true
end

function RaidDirector.reset()
    RaidDirector.adapters = {}
    RaidDirector.state = nil
    RaidDirector.nextCheckAtMs = 0
    RaidDirector.nextCheckHour = 0
    RaidDirector.scoutRequestId = nil
    RaidDirector.sequence = 0
    RaidDirector.fallbackStore = { lastHour = -1e9 }
    RaidDirector.metrics = { checks = 0, started = 0, waves = 0, refused = 0, ended = 0, scouts = 0, scoutFailures = 0,
        warnings = 0, placementRefused = 0 }
end

function RaidDirector.allowed(enabled, day, hours, lastHour, rolledPct)
    local settings = RaidDirector.settings
    if enabled ~= true then return false, "disabled" end
    if (tonumber(day) or 0) < settings.minDay then return false, "minimum_day" end
    if (tonumber(hours) or 0) < (tonumber(lastHour) or -1e9)
            + settings.cooldownDays * 24 then
        return false, "cooldown"
    end
    if (tonumber(rolledPct) or 100) >= settings.chancePerCheckPct then
        return false, "roll"
    end
    return true
end

local function roster()
    if type(RaidDirector.adapters.players) == "function" then
        return RaidDirector.adapters.players()
    end
    local result = {}
    pcall(function()
        local online = getOnlinePlayers and getOnlinePlayers() or nil
        if online ~= nil then
            for index = 0, online:size() - 1 do result[#result + 1] = online:get(index) end
        end
    end)
    if #result == 0 then
        pcall(function()
            local solo = getSpecificPlayer and getSpecificPlayer(0) or nil
            if solo ~= nil then result[1] = solo end
        end)
    end
    return result
end

local function username(player)
    if type(RaidDirector.adapters.username) == "function" then
        return RaidDirector.adapters.username(player)
    end
    local value
    pcall(function() value = player:getUsername() end)
    return value ~= nil and tostring(value) or nil
end

local function position(player)
    local point
    pcall(function() point = { x = player:getX(), y = player:getY(), z = player:getZ() } end)
    return point
end

local function targetPlayer(name)
    if type(RaidDirector.adapters.findPlayer) == "function" then
        return RaidDirector.adapters.findPlayer(name)
    end
    for _, player in ipairs(roster()) do
        if username(player) == name then return player end
    end
    return nil
end

local function multiplayer()
    if type(RaidDirector.adapters.multiplayer) == "function" then
        return RaidDirector.adapters.multiplayer() == true
    end
    return type(isServer) == "function" and isServer() == true
end

local function sendRaidStart(player, payload)
    return pcall(sendServerCommand, player, "ProjectALife", "RaidStart", payload)
end

local function sendRaidWave(player, payload)
    return pcall(sendServerCommand, player, "ProjectALife", "RaidWave", payload)
end

function RaidDirector.sendWarning(player, payload)
    return pcall(sendServerCommand, player, "ProjectALife", "RaidWarning", payload)
end

local function broadcast(player, command, payload)
    if type(RaidDirector.adapters.broadcast) == "function" then
        return RaidDirector.adapters.broadcast(player, command, payload) ~= false
    end
    if multiplayer() and type(sendServerCommand) == "function" then
        if command == "RaidStart" then sendRaidStart(player, payload)
        elseif command == "RaidWave" then sendRaidWave(player, payload)
        elseif command == "RaidWarning" then RaidDirector.sendWarning(player, payload) end
        return true
    end
    pcall(function()
        local client = ProjectALife.RaidClient
        if client == nil then return end
        if command == "RaidStart" and type(client.onStart) == "function" then
            client.onStart(payload)
        elseif command == "RaidWave" and type(client.onWave) == "function" then
            client.onWave(payload)
        elseif command == "RaidWarning" and type(client.onWarning) == "function" then
            client.onWarning(payload)
        end
    end)
    return true
end

local function newId(hours)
    RaidDirector.sequence = RaidDirector.sequence + 1
    if type(RaidDirector.adapters.newId) == "function" then
        return tostring(RaidDirector.adapters.newId())
    end
    return "raid:" .. tostring(math.floor(hours * 3600)) .. ":"
        .. tostring(RaidDirector.sequence)
end

local function profileIds(count, seed, factionId)
    if type(RaidDirector.adapters.profiles) == "function" then
        return RaidDirector.adapters.profiles(count, seed, factionId)
    end
    local service = ProjectALife.DebugService
    if service == nil or type(service.hostileProfileIds) ~= "function" then return nil end
    if factionId == "*" or factionId == "" or factionId == "any" then factionId = nil end
    if factionId == nil then
        local first = service.hostileProfileIds(1, seed)
        local catalog = ProjectALife.Catalog
        local profile = first and catalog and catalog.npc and catalog.npc(first[1])
        factionId = profile and profile.general and profile.general.faction
        if factionId == nil then return nil end
    end
    return service.hostileProfileIds(count, seed, factionId, true), factionId
end

function RaidDirector.wavePlan(waves, groupSize, cap)
    waves = math.max(1, math.floor(tonumber(waves) or 1))
    groupSize = math.max(1, math.floor(tonumber(groupSize) or 1))
    local total = waves * groupSize
    local limit = math.floor(tonumber(cap) or total)
    if limit >= 1 and limit < total then total = limit end
    local count = math.min(waves, total)
    local sizes = {}
    for index = 1, count do
        local size = math.floor(total / count)
        if index <= total % count then size = size + 1 end
        sizes[index] = size
    end
    return sizes
end

function RaidDirector.waveSize(state, waveNumber)
    local sizes = type(state.waveSizes) == "table" and state.waveSizes or nil
    local size = sizes ~= nil and tonumber(sizes[waveNumber]) or nil
    if size == nil then return state.groupSize end
    return size
end

function RaidDirector.plannedTotal(state)
    if type(state.waveSizes) ~= "table" then return state.groupSize * state.wavesTotal end
    local total = 0
    for _, size in ipairs(state.waveSizes) do total = total + size end
    return total
end

function RaidDirector.facing(player)
    if type(RaidDirector.adapters.facing) == "function" then return RaidDirector.adapters.facing(player) end
    if player == nil or type(player.getForwardDirection) ~= "function" then return nil end
    local forward = player:getForwardDirection()
    if forward == nil or type(forward.getX) ~= "function" or type(forward.getY) ~= "function" then return nil end
    local fx, fy = tonumber(forward:getX()), tonumber(forward:getY())
    if fx == nil or fy == nil then return nil end
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.001 then return nil end
    return fx / length, fy / length
end

function RaidDirector.rectOf(item)
    if type(item) == "table" and tonumber(item.x1) ~= nil then
        return tonumber(item.x1), tonumber(item.y1), tonumber(item.x2), tonumber(item.y2)
    end
    if type(item) == "table" and tonumber(item.x) ~= nil then
        local x, y = tonumber(item.x), tonumber(item.y)
        return x, y, x + (tonumber(item.w) or 0), y + (tonumber(item.h) or 0)
    end
    if item == nil or type(item.getX) ~= "function" or type(item.getY) ~= "function"
            or type(item.getW) ~= "function" or type(item.getH) ~= "function" then return nil end
    local x, y = tonumber(item:getX()), tonumber(item:getY())
    if x == nil or y == nil then return nil end
    return x, y, x + (tonumber(item:getW()) or 0), y + (tonumber(item:getH()) or 0)
end

function RaidDirector.homes()
    if type(RaidDirector.adapters.homes) == "function" then return RaidDirector.adapters.homes() or {} end
    local rects = {}
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.context) ~= "function" then return rects end
    local ok, context = pcall(policy.context, {})
    if not ok or type(context) ~= "table" then return rects end
    for _, list in ipairs({ context.bases or {}, context.safehouses or {} }) do
        for _, item in ipairs(list) do
            local x1, y1, x2, y2 = RaidDirector.rectOf(item)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                rects[#rects + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
            end
        end
    end
    return rects
end

function RaidDirector.clearOfHomes(point, rects)
    local margin = math.max(0, tonumber(RaidDirector.settings.houseClearanceTiles) or 0)
    for _, rect in ipairs(rects or {}) do
        local x1, y1, x2, y2 = tonumber(rect.x1), tonumber(rect.y1), tonumber(rect.x2), tonumber(rect.y2)
        if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
            local dx = math.max(x1 - point.x, 0, point.x - x2)
            local dy = math.max(y1 - point.y, 0, point.y - y2)
            if dx * dx + dy * dy < margin * margin then return false end
        end
    end
    return true
end

function RaidDirector.approachPoint(player)
    local at = position(player)
    if at == nil then return nil end
    local settings = RaidDirector.settings
    local low = math.max(1, math.floor(tonumber(settings.approachMinTiles) or 40))
    local high = math.max(low, math.floor(tonumber(settings.approachMaxTiles) or low))
    local fairness = ProjectALife.SpawnFairness
    local tries = 8
    if fairness ~= nil and fairness.enabled() then
        low, high = fairness.band(at.x, at.y)
        tries = 16
    end
    local fx, fy = RaidDirector.facing(player)
    local homes = RaidDirector.homes()
    for _ = 1, tries do
        local dx, dy
        if fx ~= nil and fy ~= nil then
            local spread = (random() - 0.5) * math.pi
            dx = -fx * math.cos(spread) + fy * math.sin(spread)
            dy = -fx * math.sin(spread) - fy * math.cos(spread)
        else
            local angle = random() * math.pi * 2
            dx, dy = math.cos(angle), math.sin(angle)
        end
        local radius = low + math.floor(random() * (high - low + 1))
        local point = { x = math.floor(at.x + dx * radius), y = math.floor(at.y + dy * radius), z = 0 }
        if RaidDirector.clearOfHomes(point, homes)
                and (fairness == nil or fairness.windowOk(point.x, point.y)) then return point end
    end
    if fairness ~= nil and fairness.enabled() then
        local point = fairness.ringPoint(at.x, at.y, low, high)
        if point ~= nil and RaidDirector.clearOfHomes(point, homes) then return point end
    end
    RaidDirector.metrics.placementRefused = RaidDirector.metrics.placementRefused + 1
    return nil
end

function RaidDirector.factionLabel(factionId)
    local catalog = ProjectALife.Catalog
    if catalog == nil or type(catalog.faction) ~= "function" or factionId == nil then return nil end
    local faction = catalog.faction(factionId)
    local name = faction and faction.general and faction.general.name or nil
    if name == nil or tostring(name) == "" then return nil end
    return tostring(name)
end

function RaidDirector.warn(player, factionId, hours)
    local name, point = username(player), position(player)
    if name == nil or point == nil then return false, "target_unavailable" end
    RaidDirector.sequence = RaidDirector.sequence + 1
    local scout = { status = "warned", targetUsername = name, factionId = factionId, warnedHour = hours,
        warningId = "raid-warning:" .. tostring(math.floor((tonumber(hours) or 0) * 3600)) .. ":"
            .. tostring(RaidDirector.sequence) }
    store().scout = scout
    dirty()
    RaidDirector.metrics.warnings = RaidDirector.metrics.warnings + 1
    broadcast(player, "RaidWarning", { warningId = scout.warningId, x = point.x, y = point.y, z = point.z,
        faction = RaidDirector.factionLabel(factionId), leadHours = RaidDirector.settings.warningHours })
    if RaidDirector.settings.warningHours <= 0 then RaidDirector.followWarning(scout, hours) end
    return true, scout.warningId
end

function RaidDirector.followWarning(scout, hours)
    local settings = RaidDirector.settings
    local warnedHour = tonumber(scout.warnedHour) or hours
    if hours - warnedHour > math.max(settings.warningHours, settings.scoutLifetimeHours) then
        store().scout = nil
        dirty()
        return 0
    end
    if hours < warnedHour + settings.warningHours then return 0 end
    local target = targetPlayer(scout.targetUsername)
    if target == nil then return 0 end
    local sent = RaidDirector.sendScouts(target, { factionId = scout.factionId })
    if not sent then RaidDirector.metrics.refused = RaidDirector.metrics.refused + 1 end
    if sent then return 1 end
    return 0
end

function RaidDirector.scoutReady(scout, target, hours)
    if type(scout) ~= "table" or scout.status ~= "deployed"
            or scout.targetUsername ~= target then return false, "scout_required" end
    local age = (tonumber(hours) or 0) - (tonumber(scout.deployedHour) or 0)
    if age < RaidDirector.settings.scoutBuildupHours then return false, "scout_buildup" end
    if age > math.max(RaidDirector.settings.scoutBuildupHours,
            RaidDirector.settings.scoutLifetimeHours) then return false, "scout_expired" end
    return true
end

function RaidDirector.start(player, overrides, force)
    if player == nil then return false, "target_missing" end
    overrides = type(overrides) == "table" and overrides or {}
    if RaidDirector.state ~= nil then
        if force ~= true then return false, "raid_active" end
    end
    local day, hours = calendar()
    if force ~= true then
        local allowed, reason = RaidDirector.allowed(
            RaidDirector.settings.enabled, day, hours,
            math.max(tonumber(store().lastHour) or -1e9, tonumber(store().reservedHour) or -1e9),
            0)
        if not allowed then return false, reason end
        local ready, scoutReason = RaidDirector.scoutReady(store().scout, username(player), hours)
        if not ready then return false, scoutReason end
    end
    local name, point = username(player), position(player)
    if name == nil or point == nil then return false, "target_unavailable" end
    local settings = RaidDirector.settings
    local scout = force ~= true and store().scout or nil
    if force ~= true then
        local faction = ProjectALife.Catalog and ProjectALife.Catalog.faction(
            overrides.factionId or (scout and scout.factionId))
        local _, clock = ProjectALife.FactionSpawnRules.clock()
        if not ProjectALife.FactionSpawnRules.available(faction, hours / 24, clock, point, "fullscale_raid")
                or not ProjectALife.FactionSpawnRules.hostile(faction) then
            return false, "faction_raid_policy"
        end
    end
    local selected, factionId = profileIds(1, nowMs(), overrides.factionId or (scout and scout.factionId))
    if type(selected) ~= "table" or #selected == 0 then return false, "hostile_profiles_missing" end
    factionId = factionId or overrides.factionId or (scout and scout.factionId)
    local waves = force == true
        and clamp(overrides.waves, 1, 12, settings.waves)
        or clamp(overrides.waves, 1, 10, settings.waves)
    local groupSize = clamp(overrides.groupSize, 1, 12, settings.groupSize)
    local sizes = nil
    if force ~= true then
        sizes = RaidDirector.wavePlan(waves, groupSize, settings.maxAttackers)
        waves, groupSize = #sizes, sizes[1]
    end
    local heli = settings.heli == true and settings.sirenAircraft == true
    if overrides.heli ~= nil then heli = overrides.heli == true end
    local now = nowMs()
    RaidDirector.state = {
        raidId = newId(hours),
        targetUsername = name,
        factionId = factionId,
        objectiveX = point.x, objectiveY = point.y, objectiveZ = point.z,
        wavesTotal = waves,
        wavesRemaining = waves,
        waveNumber = 0,
        waveSpawned = 0,
        groupSize = groupSize,
        waveSizes = sizes,
        natural = force ~= true or nil,
        distance = clamp((tonumber(overrides.distance) or -1) >= 0 and overrides.distance or nil,
            22, 60, settings.distanceTiles),
        delayHours = clamp(overrides.waveDelayMinutes, 1, 60,
            settings.waveDelayMinutes) / 60,

        heli = heli,
        preludeConfirmed = not multiplayer(),
        firstWaveReadyAtMs = now + settings.firstWaveReadyMs,
        firstWaveFallbackAtMs = now + settings.firstWaveFallbackMs,
        nextWaveHour = hours,
        retryAtMs = 0,
        startedAtHour = hours,

        gunfireAtMs = now + settings.gunfireDelayMs,

        adminPick = force == true or nil,
    }
    local state = RaidDirector.state

    store().reservedHour, store().lastRaidId, store().scout = hours, state.raidId, nil
    dirty()
    broadcast(player, "RaidStart", {
        raidId = state.raidId,
        x = point.x, y = point.y, z = point.z,

        preludeSeconds = settings.preludeSeconds,
        introSeconds = settings.introSeconds,
    })
    pcall(function()
        local log = ProjectALife.EncounterLog
        if log ~= nil then log.record({ id = "fullscale_raid", label = "FULL SCALE RAID" },
            point, RaidDirector.plannedTotal(state), "raid_director") end
    end)
    RaidDirector.metrics.started = RaidDirector.metrics.started + 1
    return true, state.raidId
end

function RaidDirector.confirm(name, raidId)
    local state = RaidDirector.state
    if state == nil or tostring(name or "") ~= state.targetUsername
            or tostring(raidId or "") ~= state.raidId then
        return false, "prelude_mismatch"
    end
    state.preludeConfirmed = true
    return true
end

local function wavePoint(player, distance)
    local point = position(player)
    if point == nil then return nil end
    local radius = distance + math.floor(random() * 4)
    local angle = random() * math.pi * 2
    return {
        x = math.floor(point.x + math.cos(angle) * radius),
        y = math.floor(point.y + math.sin(angle) * radius),
        z = 0,
    }
end

local function spawn(player, args)
    if type(RaidDirector.adapters.spawn) == "function" then
        return RaidDirector.adapters.spawn(player, args)
    end
    local service = ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function" then
        return false, "spawn_service_unavailable"
    end
    return service.spawnEncounter(player, args)
end

function RaidDirector.sendScouts(player, overrides)
    if player == nil then return false, "target_missing" end
    overrides = type(overrides) == "table" and overrides or {}
    local point, name = position(player), username(player)
    local held = store().scout
    local warned = type(held) == "table" and held.status == "warned" and held.targetUsername == name
    if RaidDirector.state ~= nil or RaidDirector.scoutRequestId ~= nil
            or (held ~= nil and not warned) then return false, "buildup_active" end
    if point == nil or name == nil then return false, "target_unavailable" end
    local now = nowMs()
    local _, hours = calendar()

    local count = clamp(overrides.count, 1, 12, RaidDirector.settings.scoutSize)
    local profiles, factionId = profileIds(count, now, overrides.factionId)
    if type(profiles) ~= "table" or #profiles ~= count then return false, "hostile_profiles_missing" end
    local approach = RaidDirector.approachPoint(player)
    if approach == nil then return false, "approach_unavailable" end
    local requestId = newId(hours) .. ":scouts"
    local scout = { requestId = requestId, targetUsername = name,
        factionId = factionId or overrides.factionId, status = "pending", requestedHour = hours }
    if warned then scout.warnedHour = held.warnedHour end
    RaidDirector.scoutRequestId, store().scout = requestId, scout
    dirty()
    local ok, reason = spawn(player, {
        requestId = requestId, encounterId = "raid", mode = "assault", profile = "seek_destroy",
        factionId = scout.factionId, profileIds = profiles, count = count,
        x = approach.x, y = approach.y, z = 0, distance = 0, separation = 3, radius = 12,
        conducts = { "leader" }, objectiveX = point.x, objectiveY = point.y,
        targetUsername = name, supportPolicy = "disabled", atomicGroup = true,
        hostileOverride = true, directed = true,

        playerKeepOut = RaidDirector.settings.approachMinTiles,
    })
    local function settled(outcome)
        if store().scout ~= scout then return end
        RaidDirector.scoutRequestId = nil
        if type(outcome) == "table" and outcome.ok == true
                and tonumber(outcome.active) == count then
            local _, deployedHour = calendar()
            scout.status, scout.deployedHour = "deployed", deployedHour
            RaidDirector.metrics.scouts = RaidDirector.metrics.scouts + 1
        else
            store().scout = nil
            RaidDirector.metrics.scoutFailures = RaidDirector.metrics.scoutFailures + 1
        end
        dirty()
    end
    if not ok then settled(nil); return false, reason or "scout_spawn_failed" end
    if reason == "accepted_pending" then
        local service = ProjectALife.DebugService
        local watcher = RaidDirector.adapters.watchGroup or (service and service.watchGroup)
        if type(watcher) ~= "function" or watcher(requestId, settled) == false then
            settled(nil); return false, "group_outcome_unavailable"
        end
    else
        settled({ ok = true, active = count })
    end
    return true, requestId
end

local function watchGroup(requestId, listener)
    if type(RaidDirector.adapters.watchGroup) == "function" then
        return RaidDirector.adapters.watchGroup(requestId, listener)
    end
    local service = ProjectALife.DebugService
    if service == nil or type(service.watchGroup) ~= "function" then
        return false, "group_outcome_unavailable"
    end
    return service.watchGroup(requestId, listener)
end

local function heliNoise(point)
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.noteNoise) == "function" then
        pcall(first.noteNoise, point.x, point.y, point.z, 55, "heli")
    end
    if type(RaidDirector.adapters.addSound) == "function" then
        RaidDirector.adapters.addSound(point.x, point.y, point.z, 55, 70)
        return
    end
    pcall(function() addSound(nil, point.x, point.y, point.z, 55, 70) end)
end

local function finish(player, hours, reason)
    local values = store()
    values.lastHour = hours
    values.reservedHour = nil
    values.lastRaidId = RaidDirector.state and RaidDirector.state.raidId or nil
    values.lastReason = reason
    dirty()
    pcall(function()
        local heat = ProjectALife.BaseHeat
        if heat ~= nil and type(heat.markRaid) == "function" then heat.markRaid(player, hours) end
    end)
    local personal = ProjectALife.PersonalRep
    local state = RaidDirector.state
    if reason == "complete" and player ~= nil and state ~= nil and personal ~= nil and type(personal.onRaidSurvived) == "function" then
        pcall(personal.onRaidSurvived, player, { raidId = state.raidId, objectiveX = state.objectiveX, objectiveY = state.objectiveY })
    end
    RaidDirector.state = nil
    RaidDirector.metrics.ended = RaidDirector.metrics.ended + 1
end

local function finalizeWave(state, player, hours)
    local waveNumber = state.waveNumber + 1
    local firstPoint = state.waveFirstPoint
    if firstPoint == nil then return false, "wave_position_unavailable" end
    local delivery = waveNumber == 1 and state.heli and "heli" or "ground"
    broadcast(player, "RaidWave", {
        raidId = state.raidId,
        waveNumber = waveNumber,
        x = firstPoint.x, y = firstPoint.y, z = firstPoint.z,
        tx = state.objectiveX, ty = state.objectiveY,
        delivery = delivery,
        heli = delivery == "heli",
        targetUsername = state.targetUsername,
    })
    if delivery == "heli" then heliNoise(firstPoint) end
    state.waveNumber = waveNumber
    state.wavesRemaining = state.wavesRemaining - 1
    state.waveSpawned = 0
    state.waveFirstPoint = nil
    state.retryAtMs = 0
    state.failedSinceMs = nil
    state.nextWaveHour = hours + state.delayHours
    RaidDirector.metrics.waves = RaidDirector.metrics.waves + 1
    return true
end

local function settleWaveGroup(raidId, requestId, waveNumber, count, point, outcome)
    local state = RaidDirector.state
    if state == nil or state.raidId ~= raidId
            or state.pendingRequestId ~= requestId
            or state.waveNumber + 1 ~= waveNumber then return false end
    state.pendingRequestId = nil
    state.pendingCount = nil
    state.pendingAtMs = nil
    local successful = type(outcome) == "table" and outcome.ok == true
        and tonumber(outcome.active) == count
        and (tonumber(outcome.failed) or 0) == 0
        and (tonumber(outcome.rejected) or 0) == 0
    if successful then
        state.waveSpawned = state.waveSpawned + count
        state.waveFirstPoint = state.waveFirstPoint or point
        state.retryAtMs = 0
        state.failedSinceMs = nil
        return true
    end
    RaidDirector.metrics.refused = RaidDirector.metrics.refused + 1
    state.failedSinceMs = state.failedSinceMs or nowMs()
    local _, hours = calendar()
    if state.waveNumber == 0 then state.retryAtMs = nowMs() + 1000
    else state.nextWaveHour = hours + 0.01 end
    return false
end

local function spawnWave(state, player, now, hours)
    if state.pendingRequestId ~= nil then return true, "wave_pending" end
    local waveNumber = state.waveNumber + 1
    local size = RaidDirector.waveSize(state, waveNumber)
    local natural = state.natural == true
    while state.waveSpawned < size do
        local count = math.min(8, size - state.waveSpawned)
        local point
        if natural then point = RaidDirector.approachPoint(player)
        else point = wavePoint(player, state.distance) end
        if point == nil then return false, "wave_position_unavailable" end
        local profiles = profileIds(count, now + state.waveSpawned, state.factionId)
        if type(profiles) ~= "table" then return false, "hostile_profiles_missing" end
        state.spawnAttempt = (state.spawnAttempt or 0) + 1
        local requestId = state.raidId .. ":wave:" .. tostring(waveNumber)
            .. ":" .. tostring(state.waveSpawned) .. ":" .. tostring(state.spawnAttempt)
        local ok, reason, receipt = spawn(player, {
            requestId = requestId,
            encounterId = "fullscale_raid",
            mode = "full_raid",
            profile = "manhunt",
            profileIds = profiles,
            factionId = state.factionId,
            count = count,
            x = point.x, y = point.y, z = point.z,
            distance = 0, separation = 2, radius = 24,
            conducts = { "leader", "medic" },
            animation = "normal",
            objectiveX = state.objectiveX,
            objectiveY = state.objectiveY,
            targetUsername = state.targetUsername,
            atomicGroup = true,
            supportPolicy = "disabled",
            hostileOverride = true,
            directed = natural or nil,

            playerKeepOut = natural and RaidDirector.settings.approachMinTiles or 0,
            adminPick = state.adminPick,
        })
        if not ok then return false, reason or "wave_spawn_failed" end
        if reason == "accepted_pending" and type(receipt) == "table" then
            state.pendingRequestId = requestId
            state.pendingCount = count
            state.pendingAtMs = now
            local watched, watchReason = watchGroup(requestId, function(outcome)
                settleWaveGroup(state.raidId, requestId, waveNumber,
                    count, point, outcome)
            end)
            if not watched then
                state.pendingRequestId, state.pendingCount = nil, nil
                return false, watchReason or "group_outcome_unavailable"
            end
            return true, "wave_pending"
        end

        state.waveSpawned = state.waveSpawned + count
        state.waveFirstPoint = state.waveFirstPoint or point
    end
    return finalizeWave(state, player, hours)
end

local function tickActive(now, hours)
    local state = RaidDirector.state
    if state == nil then return 0 end
    local player = targetPlayer(state.targetUsername)
    if player == nil then
        finish(nil, hours, "target_missing")
        return 0
    end
    local dead = false
    pcall(function() dead = player:isDead() end)
    if dead then finish(player, hours, "target_dead"); return 0 end

    if state.gunfireAtMs ~= nil and now >= state.gunfireAtMs then
        state.gunfireAtMs = nil
        pcall(function()
            local meta = ProjectALife.MetaDirector
            if meta ~= nil and type(meta.debugFire) == "function" then
                meta.debugFire("gunfire", player)
            end
        end)
    end
    local stalledAt = state.failedSinceMs or state.pendingAtMs
    if stalledAt ~= nil and now - stalledAt >= RaidDirector.settings.spawnTimeoutMs then
        finish(player, hours, "spawn_timeout"); return 0
    end
    if state.pendingRequestId ~= nil then return 0 end
    if state.waveNumber == 0 then
        if now < state.firstWaveReadyAtMs then return 0 end
        if not state.preludeConfirmed and now < state.firstWaveFallbackAtMs then return 0 end
        if now < (tonumber(state.retryAtMs) or 0) then return 0 end
    elseif hours < (tonumber(state.nextWaveHour) or 0) then
        return 0
    end
    local ok = spawnWave(state, player, now, hours)
    if not ok then
        state.failedSinceMs = state.failedSinceMs or now
        if state.waveNumber == 0 then state.retryAtMs = now + 1000
        else state.nextWaveHour = hours + 0.01 end
        return 0
    end
    if state.wavesRemaining <= 0 then finish(player, hours, "complete") end
    return 1
end

function RaidDirector.tick()
    if type(isClient) == "function" and isClient() then return 0 end
    local now = nowMs()
    local day, hours = calendar()
    if RaidDirector.state ~= nil then return tickActive(now, hours) end

    if now < RaidDirector.nextCheckAtMs or hours < RaidDirector.nextCheckHour then return 0 end
    RaidDirector.nextCheckAtMs = now + 1000
    RaidDirector.nextCheckHour = hours + math.max(1, RaidDirector.settings.checkEveryMinutes) / 60
    RaidDirector.metrics.checks = RaidDirector.metrics.checks + 1
    local scout = store().scout
    if type(scout) == "table" then
        if scout.status == "warned" then return RaidDirector.followWarning(scout, hours) end
        if scout.status == "pending" and RaidDirector.scoutRequestId ~= scout.requestId then
            store().scout = nil; dirty(); return 0
        end
        if scout.status == "pending" then return 0 end
        local target = targetPlayer(scout.targetUsername)
        local ready, reason = RaidDirector.scoutReady(scout, scout.targetUsername, hours)
        if reason == "scout_expired" then store().scout = nil; dirty(); return 0 end
        if not ready or target == nil then return 0 end
        return RaidDirector.start(target, { factionId = scout.factionId }, false) and 1 or 0
    end
    local players = roster()
    if #players == 0 then return 0 end
    if not RaidDirector.allowed(RaidDirector.settings.enabled, day, hours,
            math.max(tonumber(store().lastHour) or -1e9, tonumber(store().reservedHour) or -1e9),
            random() * 100) then return 0 end
    local player = players[1 + math.floor(random() * #players) % #players]
    local rules = ProjectALife.FactionSpawnRules
    local faction = rules.pick(ProjectALife.Catalog and ProjectALife.Catalog.current,
        position(player), "raid", random(), true, nil, nil, "fullscale_raid")
    if faction == nil then return 0 end
    local started = RaidDirector.warn(player, faction.id, hours)
    if not started then RaidDirector.metrics.refused = RaidDirector.metrics.refused + 1 end
    return started and 1 or 0
end

return RaidDirector
