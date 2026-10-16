require "ProjectALife/World/ALifeHeliSearch"

ProjectALife = ProjectALife or {}

local Heli = ProjectALife.HeliSearch

local Director = {
    adapters = {},
    tickMs = 250,
    syncMs = 500,
    sendRange = 260,
    playerRange = 130,
    spotHoldMs = 15000,
    staleGraceS = 30,
    noiseRadius = 55,
    noiseVolume = 70,
    nextAtMs = 0,
    lastAtMs = nil,
    nextSyncMs = 0,
    metrics = { started = 0, refused = 0, ticks = 0, sends = 0, spotted = 0, lost = 0, noises = 0, cues = 0 },
}
ProjectALife.HeliDirector = Director

function Director.nowMs()
    if type(Director.adapters.nowMs) == "function" then return Director.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Director.reset()
    Heli.reset()
    Director.nextAtMs, Director.lastAtMs, Director.nextSyncMs = 0, nil, 0
    Director.metrics = { started = 0, refused = 0, ticks = 0, sends = 0, spotted = 0, lost = 0, noises = 0, cues = 0 }
end

function Director.configure(adapters)
    Director.adapters = adapters or {}
    return true
end

function Director.allowed()
    if not Heli.enabled then return false end
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.helicoptersAllowed) == "function" and settings.helicoptersAllowed() ~= true then
        return false
    end
    return true
end

function Director.activeFlight(now)
    for id, flight in pairs(Heli.flights) do
        local stale = now ~= nil and now - (flight.startedMs or now) > (flight.durationS + Director.staleGraceS) * 1000
        if flight.done or stale then Heli.stop(id)
        else return flight end
    end
    return nil
end

function Director.players()
    if type(Director.adapters.players) == "table" then return Director.adapters.players end
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" then return locator.list() end
    return {}
end

function Director.isRoad(x, y)
    if type(Director.adapters.isRoad) == "function" then return Director.adapters.isRoad(x, y) end
    local result
    pcall(function()
        local road = ProjectALife.Road
        if road == nil or type(getCell) ~= "function" then return end
        local square = getCell():getGridSquare(math.floor(x), math.floor(y), 0)
        if square == nil then return end
        result = road.isRoadSquare(square) == true
    end)
    return result
end

function Director.targetOf(subject, key, isPlayer)
    if subject == nil or key == nil then return nil end
    local target
    pcall(function()
        if subject:isDead() then return end
        local square = subject:getSquare()
        local outdoors = square ~= nil and square:isOutside() == true
        local building = type(subject.getBuilding) == "function" and subject:getBuilding() or nil
        local vehicle = type(subject.getVehicle) == "function" and subject:getVehicle() or nil
        target = { key = key, x = subject:getX(), y = subject:getY(), z = subject:getZ(),
            outdoors = outdoors, covered = (not outdoors) or building ~= nil,
            sneaking = false, moving = true, running = false,
            canopy = square ~= nil and type(square.HasTree) == "function" and square:HasTree() == true }
        if isPlayer and vehicle == nil then
            target.sneaking = type(subject.isSneaking) == "function" and subject:isSneaking() == true
            target.running = (type(subject.isRunning) == "function" and subject:isRunning() == true)
                or (type(subject.isSprinting) == "function" and subject:isSprinting() == true)
            target.moving = type(subject.isPlayerMoving) == "function" and subject:isPlayerMoving() == true
        end
    end)
    return target
end

function Director.world(flight)
    local targets = {}
    local limit = Director.playerRange * Director.playerRange
    for _, player in ipairs(Director.players()) do
        local key
        pcall(function() key = player:getUsername() end)
        local target = Director.targetOf(player, key, true)
        if target ~= nil then
            local dx, dy = target.x - flight.x, target.y - flight.y
            if dx * dx + dy * dy <= limit or key == flight.lockKey then targets[#targets + 1] = target end
        end
    end
    local uid = flight.targetUid
    local watchdog = ProjectALife.Watchdog
    if uid ~= nil and watchdog ~= nil and type(watchdog.bindings) == "table" then
        local binding = watchdog.bindings[uid]
        local target = Director.targetOf(binding ~= nil and binding.shell or nil, uid, false)
        if target ~= nil then targets[#targets + 1] = target end
    end
    return { targets = targets, isRoad = Director.isRoad }
end

function Director.sites(flight)
    local registry = ProjectALife.OutpostRegistry
    if registry == nil or type(registry.list) ~= "function" then return end
    pcall(function()
        for _, site in ipairs(registry.list()) do
            if site.state == "garrisoned" and tonumber(site.x) ~= nil and tonumber(site.y) ~= nil then
                flight.sites[#flight.sites + 1] = { id = tostring(site.id), x = site.x, y = site.y }
            end
        end
    end)
end

function Director.send(command, payload)
    Director.metrics.sends = Director.metrics.sends + 1
    if type(Director.adapters.send) == "function" then return Director.adapters.send(command, payload) end
    pcall(function()
        if type(isServer) ~= "function" or not isServer() then return end
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players == nil then return end
        local limit = Director.sendRange * Director.sendRange
        for index = 0, players:size() - 1 do
            local player = players:get(index)
            if player ~= nil then
                local dx, dy = player:getX() - (tonumber(payload.x) or 0), player:getY() - (tonumber(payload.y) or 0)
                if dx * dx + dy * dy <= limit or command == "supportHeliEnd" then
                    sendServerCommand(player, "ProjectALife", command, payload)
                end
            end
        end
    end)
    pcall(function()
        local fx = ProjectALife.SupportClient
        if fx ~= nil and type(fx.onHeliCommand) == "function" then fx.onHeliCommand(command, payload) end
    end)
end

function Director.start(spec)
    if type(spec) ~= "table" or spec.id == nil then return nil, "bad_spec" end
    if not Director.allowed() then
        Director.metrics.refused = Director.metrics.refused + 1
        return nil, "spotlight_off"
    end
    local now = tonumber(spec.nowMs) or Director.nowMs()
    local busy = Director.activeFlight(now)
    if busy ~= nil and busy.id ~= tostring(spec.id) then
        Director.metrics.refused = Director.metrics.refused + 1
        return nil, "aircraft_busy"
    end
    local flight = Heli.start(spec)
    if flight == nil then return nil, "bad_spec" end
    flight.targetUid = spec.targetUid
    flight.startedMs = now
    Director.sites(flight)
    Director.metrics.started = Director.metrics.started + 1
    print("[ALIFE-HELI] start id=" .. flight.id .. " from=" .. math.floor(flight.x) .. "," .. math.floor(flight.y)
        .. " anchor=" .. math.floor(flight.anchorX) .. "," .. math.floor(flight.anchorY)
        .. " duration=" .. tostring(flight.durationS) .. " radius=" .. tostring(flight.radius)
        .. " sites=" .. #flight.sites)
    Director.send("supportHeliSync", Heli.snapshot(flight))
    return flight
end

function Director.debugStart(player)
    if player == nil then return false, "no_player" end
    local x, y, z, key = 0, 0, 0, nil
    pcall(function()
        x, y, z, key = player:getX(), player:getY(), player:getZ(), player:getUsername()
    end)
    local flight, why = Director.start({ id = "debug-light:" .. tostring(math.floor(Director.nowMs())),
        startX = x + 55, startY = y - 55, anchorX = x, anchorY = y, durationS = 150,
        seed = math.floor(Director.nowMs()), targetKey = key, groupId = "debug-light",
        radius = Heli.settings.radius, brightness = Heli.settings.brightness })
    if flight == nil then return false, why end
    return true, "started"
end

function Director.noise(x, y, z)
    Director.metrics.noises = Director.metrics.noises + 1
    local support = ProjectALife.Support
    if support ~= nil and type(support.worldNoise) == "function" then
        return support.worldNoise(x, y, z or 0, Director.noiseRadius, Director.noiseVolume)
    end
    pcall(function()
        if type(addSound) == "function" then
            addSound(nil, math.floor(x), math.floor(y), math.floor(z or 0), Director.noiseRadius, Director.noiseVolume)
        end
    end)
end

function Director.holdSpot(flight, now)
    local support = ProjectALife.Support
    local track = support ~= nil and type(support.intel) == "table" and support.intel[flight.id] or nil
    if track ~= nil then track.spottedUntilMs = now + Director.spotHoldMs end
end

function Director.handle(flight, event, now)
    if event.kind == "spotted" then
        Director.metrics.spotted = Director.metrics.spotted + 1
        print("[ALIFE-HELI] spotted id=" .. flight.id .. " key=" .. tostring(event.key)
            .. " at=" .. math.floor(event.x) .. "," .. math.floor(event.y) .. " t=" .. math.floor(flight.t))
        Director.holdSpot(flight, now)
        Director.noise(event.x, event.y, event.z)
        flight.nextNoiseT = flight.t + Heli.settings.noiseEveryS
    elseif event.kind == "lost" then
        Director.metrics.lost = Director.metrics.lost + 1
        print("[ALIFE-HELI] lost id=" .. flight.id .. " key=" .. tostring(event.key) .. " why=" .. tostring(event.reason)
            .. " last=" .. math.floor(event.x) .. "," .. math.floor(event.y))
    elseif event.kind == "cue" then
        Director.metrics.cues = Director.metrics.cues + 1
        print("[ALIFE-HELI] converge id=" .. flight.id .. " cue=" .. tostring(event.cue)
            .. " at=" .. math.floor(event.x) .. "," .. math.floor(event.y))
    elseif event.kind == "phase" then
        print("[ALIFE-HELI] phase id=" .. flight.id .. " " .. tostring(event.phase) .. " t=" .. math.floor(flight.t))
    elseif event.kind == "ended" then
        print("[ALIFE-HELI] end id=" .. flight.id .. " spotted=" .. tostring(flight.spotted)
            .. " duration=" .. math.floor(flight.t))
    end
end

function Director.noteMarks(flight, now)
    local investigation = ProjectALife.Investigation
    local marks = investigation ~= nil and investigation.marks or nil
    if type(marks) ~= "table" then return end
    for index = #marks, 1, -1 do
        local mark = marks[index]
        local at = tonumber(mark.atMs)
        if at ~= nil and now - at <= Director.tickMs * 2 and mark.group ~= flight.groupId
                and (flight.cueMarkAt or -1) < at then
            flight.cueMarkAt = at
            Heli.cue(flight, mark.x, mark.y, mark.kind == "noise" and "gunfire" or tostring(mark.kind))
            return
        end
    end
end

function Director.tick()
    local now = Director.nowMs()
    if now < Director.nextAtMs then return end
    Director.nextAtMs = now + Director.tickMs
    local last = Director.lastAtMs
    Director.lastAtMs = now
    local flight = Director.activeFlight()
    if flight == nil then return end
    local dt = last ~= nil and math.min(0.5, math.max(0, (now - last) / 1000)) or Director.tickMs / 1000
    Director.metrics.ticks = Director.metrics.ticks + 1
    Director.noteMarks(flight, now)
    local events = Heli.advance(flight, dt, Director.world(flight))
    local pushed = false
    for index = 1, #events do
        Director.handle(flight, events[index], now)
        if events[index].kind ~= "ended" then pushed = true end
    end
    if flight.lockKey ~= nil and flight.lostFor == 0 then
        Director.holdSpot(flight, now)
        if flight.t >= flight.nextNoiseT then
            flight.nextNoiseT = flight.t + Heli.settings.noiseEveryS
            Director.noise(flight.lastX, flight.lastY, flight.z)
        end
    end
    if flight.done then
        Director.send("supportHeliEnd", { id = flight.id, x = flight.x, y = flight.y })
        Heli.stop(flight.id)
        return
    end
    if pushed or now >= Director.nextSyncMs then
        Director.nextSyncMs = now + Director.syncMs
        Heli.metrics.syncs = Heli.metrics.syncs + 1
        Director.send("supportHeliSync", Heli.snapshot(flight))
    end
end

if type(Events) == "table" and Events.OnTick then Events.OnTick.Add(Director.tick) end

return Director
