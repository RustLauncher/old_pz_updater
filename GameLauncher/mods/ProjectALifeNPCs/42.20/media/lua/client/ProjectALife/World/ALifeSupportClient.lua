ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/World/ALifeHeliLight"

local Client = {
    seen = {},
    seenOrder = {},
    queue = {},
    heli = nil,
    spot = nil,
    settings = {

        audibleRange = 120, doorOpenMs = 5500, doorCloseMs = 8000,

        heliVolumeIn = 0.2, heliVolumeHold = 0.85, heliRampInMs = 3000, heliRampOutMs = 5000,

        heliHeardMs = 2500, heliIndoorShare = 0.35,
        heliCaptionMs = 14000,
        heliHoldS = 35, heliDuckVolume = 0,
        spotlightLife = 180, spotlightDrift = 1.5, syncWaitMs = 8000, syncTailS = 12,
        heliRopeMs = 18000,

        radioTalkMaxMs = 15000,
    },
    metrics = { received = 0, played = 0, dropped = 0, helis = 0, spotlights = 0, radioTalks = 0 },

    radioTalks = {},
}
ProjectALife.SupportClient = Client

ProjectALife.ArrivalFX = ProjectALife.ArrivalFX or {}

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function localPlayerPosition()
    local x, y
    pcall(function()
        local player = getSpecificPlayer and getSpecificPlayer(0) or nil
        if player ~= nil then x, y = player:getX(), player:getY() end
    end)
    return x, y
end

local function playAt(name, x, y, z)
    pcall(function()
        local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
        if square == nil then return end
        getSoundManager():PlayWorldSoundImpl(name, false,
            math.floor(x), math.floor(y), math.floor(z or 0), 0, 20, 1, false)
    end)
end

function Client.audible(payload, px, py, range)
    if type(payload) ~= "table" or px == nil or py == nil then return false end
    local dx, dy = (tonumber(payload.x) or 0) - px, (tonumber(payload.y) or 0) - py
    return dx * dx + dy * dy <= range * range
end

function Client.heliVolume(elapsedMs, holdS)
    local s = Client.settings
    local e = tonumber(elapsedMs) or 0
    local holdMs = math.max(0, tonumber(holdS) or s.heliHoldS) * 1000
    if e < 0 then return s.heliVolumeIn end
    if e < s.heliRampInMs then return s.heliVolumeIn + (s.heliVolumeHold - s.heliVolumeIn) * (e / s.heliRampInMs) end
    if e < s.heliRampInMs + holdMs then return s.heliVolumeHold end
    local out = e - s.heliRampInMs - holdMs
    if out < s.heliRampOutMs then return s.heliVolumeHold * (1 - out / s.heliRampOutMs) end
    return nil
end

function Client.spotlightPosition(ix, iy, tx, ty, elapsedMs, durationS)
    local total = math.max(1, (tonumber(durationS) or Client.settings.heliHoldS) * 1000)
    local f = math.max(0, math.min(1, ((tonumber(elapsedMs) or 0) / total) * Client.settings.spotlightDrift))
    return { x = math.floor(ix + (tx - ix) * f), y = math.floor(iy + (ty - iy) * f) }
end

local function removeSpotlight()
    local spot = Client.spot
    if spot == nil then return end
    spot.lightX, spot.lightY, spot.roofed = nil, nil, true
end

local function stopHeli()
    local heli = Client.heli
    if heli == nil then return end
    pcall(function()
        ProjectALife.AudioPolicy.stopNamed(heli.emitter, heli.sound, heli.soundName)
        ProjectALife.AudioPolicy.forgetLoop(heli.emitter, heli.soundName)
    end)
    Client.heli = nil
end

Client.stopHeli = stopHeli

function Client.spotlightAt(x, y, z, tx, ty, durationS, targetUsername, targetUid)
    removeSpotlight()
    local now = nowMs()
    Client.spot = { x = x, y = y, z = z or 0, tx = tx or x, ty = ty or y, startedAt = now,
        durationS = math.max(5, math.min(180, tonumber(durationS) or Client.settings.spotlightLife)),
        roofed = true, targetUsername = targetUsername, targetUid = targetUid }
    Client.metrics.spotlights = Client.metrics.spotlights + 1
    return true
end

function Client.playHeliArrival(x, y, z, tx, ty, durationS, targetUsername, insertion, targetUid)
    stopHeli()
    local now = nowMs()
    local heli = { x = x, y = y, z = z or 0, startedAt = now, dropped = insertion == false,
        insertion = insertion ~= false,
        durationS = math.max(5, math.min(180, tonumber(durationS) or Client.settings.heliHoldS)) }
    pcall(function()
        local emitter = getWorld():getFreeEmitter(x, y, z or 0)
        if emitter == nil then return end
        heli.emitter = emitter
        heli.sound, heli.soundName = ProjectALife.AudioPolicy.playLocal(emitter,
            "PALHelicopterLoop", insertion == false and 0 or Client.settings.heliVolumeIn)
    end)
    Client.heli = heli

    if heli.sound ~= nil then
        pcall(function()
            ProjectALife.AudioPolicy.watchLoop(heli.emitter, heli.sound, heli.soundName,
                now + Client.settings.heliRampInMs + heli.durationS * 1000
                    + Client.settings.heliRampOutMs + 5000, now)
        end)
    end
    Client.metrics.helis = Client.metrics.helis + 1
    if insertion == false then
        Client.spotlightAt(x, y, z, tx, ty, heli.durationS, targetUsername, targetUid)
    else
        removeSpotlight(); Client.spot = nil
    end
    return true
end

function Client.playGroundArrival(x, y, z, vehicle)
    local now = nowMs()

    pcall(function()
        local emitter = getWorld():getFreeEmitter(x, y, z or 0)
        if emitter == nil then return end
        local sound = ProjectALife.AudioPolicy.playLocal(emitter, "PALReinforcementCarArrival")
        Client.queue[#Client.queue + 1] = { at = now + 19000, emitter = emitter,
            stopSound = sound, stopName = "PALReinforcementCarArrival" }
    end)
    Client.queue[#Client.queue + 1] = { at = now + Client.settings.doorOpenMs, sound = "VehicleDoorOpen", x = x, y = y, z = z }
    Client.queue[#Client.queue + 1] = { at = now + Client.settings.doorCloseMs, sound = "VehicleDoorClose", x = x, y = y, z = z }
    return true
end

ProjectALife.ArrivalFX.playGroundArrival = Client.playGroundArrival
ProjectALife.ArrivalFX.playHeliArrival = Client.playHeliArrival
ProjectALife.ArrivalFX.spotlight = Client.spotlightAt

local function accept(payload)
    if type(payload) ~= "table" or payload.supportId == nil then return false end
    Client.metrics.received = Client.metrics.received + 1
    if Client.seen[payload.supportId] then
        Client.metrics.dropped = Client.metrics.dropped + 1
        return false
    end
    Client.seen[payload.supportId] = true
    Client.seenOrder[#Client.seenOrder + 1] = payload.supportId
    if #Client.seenOrder > 256 then Client.seen[table.remove(Client.seenOrder, 1)] = nil end
    local px, py = localPlayerPosition()
    if not Client.audible(payload, px, py, Client.settings.audibleRange) then
        Client.metrics.dropped = Client.metrics.dropped + 1
        return false
    end
    return true
end

function Client.onArrival(payload)
    if not accept(payload) then return false end
    local delivery = tostring(payload.delivery or "foot")

    print("[ALIFE-SUPPORT] arrival delivery=" .. delivery .. " at=" .. tostring(payload.x) .. ","
        .. tostring(payload.y) .. " duration=" .. tostring(payload.duration))
    if delivery == "ground" then
        Client.playGroundArrival(payload.x, payload.y, payload.z, payload.vehicle)
    elseif delivery == "heli" then
        Client.playHeliArrival(payload.x, payload.y, payload.z, payload.tx, payload.ty,
            payload.duration, payload.targetUsername)
        if payload.spotlight == true then
            Client.spotlightAt(payload.x, payload.y, payload.z, payload.tx, payload.ty,
                payload.duration, payload.targetUsername, payload.targetUid)
        end
    end
    local fx = ProjectALife.ArrivalFX[delivery]
    if type(fx) == "function" then pcall(fx, payload) end
    Client.metrics.played = Client.metrics.played + 1
    return true
end

function Client.onSpotlight(payload)
    if not accept(payload) then return false end
    Client.playHeliArrival(payload.ix or payload.x, payload.iy or payload.y, payload.z,
        payload.tx or payload.x, payload.ty or payload.y, payload.duration, payload.targetUsername, false, payload.targetUid)
    Client.metrics.played = Client.metrics.played + 1
    return true
end

function Client.onRadioTalk(payload)
    if type(payload) ~= "table" then return false end
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z) or 0
    if x == nil or y == nil then return false end
    local key = math.floor(x) .. ":" .. math.floor(y) .. ":" .. math.floor(z)
    local policy = ProjectALife.AudioPolicy
    local now = nowMs()
    local drop = {}
    for other, entry in pairs(Client.radioTalks) do
        if other == key or now >= entry.deadlineMs then drop[#drop + 1] = other end
    end
    for _, other in ipairs(drop) do
        local entry = Client.radioTalks[other]
        Client.radioTalks[other] = nil
        if other == key and policy ~= nil then
            policy.stopNamed(entry.emitter, entry.handle, "RadioTalk")
            policy.forgetLoop(entry.emitter, "RadioTalk")
        end
    end
    local untilMs = math.min(tonumber(payload.untilMs) or 0, Client.settings.radioTalkMaxMs)
    if untilMs <= 0 or policy == nil then return true end
    local emitter = nil
    pcall(function() emitter = getWorld():getFreeEmitter(x, y, z) end)
    local handle, name = policy.playLocal(emitter, "RadioTalk")
    if handle == nil then return false end
    policy.watchLoop(emitter, handle, name, now + untilMs, now)
    Client.radioTalks[key] = { emitter = emitter, handle = handle, deadlineMs = now + untilMs }
    Client.metrics.radioTalks = Client.metrics.radioTalks + 1
    return true
end

function Client.onHeliCommand(command, payload)
    if type(payload) ~= "table" then return false end
    local light = ProjectALife.HeliLight
    if light == nil then return false end
    if command == "supportHeliSync" then return light.apply(payload) end
    if command == "supportHeliEnd" then return light.finish(payload.id) end
    return false
end

local function onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" then return end
    if command == "supportArrival" then
        Client.onArrival(arguments)
    elseif command == "supportSpotlight" then
        Client.onSpotlight(arguments)
    elseif command == "supportHeliSync" or command == "supportHeliEnd" then
        Client.onHeliCommand(command, arguments)
    elseif command == "radioTalk" then
        Client.onRadioTalk(arguments)
    end
end

local function tickSpotlight(now)
    local spot = Client.spot
    if spot == nil then return end
    local settings = Client.settings
    if now >= spot.startedAt + (spot.durationS + settings.syncTailS) * 1000 then
        removeSpotlight()
        Client.spot = nil
        return
    end
    local light = ProjectALife.HeliLight
    local state = light ~= nil and light.state or nil
    if state ~= nil and state.dx ~= nil then
        spot.lightX, spot.lightY = math.floor(state.dx), math.floor(state.dy)
        spot.roofed = state.roofed ~= false
        spot.synced = true
    elseif not spot.synced and now - spot.startedAt > settings.syncWaitMs then
        removeSpotlight()
        Client.spot = nil
    else
        spot.roofed = true
    end
end

local function tickHeli(now)
    local heli = Client.heli
    if heli == nil then return end
    local elapsed = now - heli.startedAt
    local volume = Client.heliVolume(elapsed, heli.durationS)
    if volume == nil then
        stopHeli()
        return
    end

    if not heli.dropped and elapsed >= (Client.settings.heliRopeMs or 18000) then

        heli.dropped = true
        playAt("PALReinforcementRappel", heli.x, heli.y, heli.z)
    end

    if not heli.heard and elapsed >= Client.settings.heliHeardMs then
        heli.heard = true
        pcall(function()
            local player = getSpecificPlayer and getSpecificPlayer(0) or nil
            if player ~= nil then
                player:addLineChatElement(ProjectALife.Text.ui("Is that a helicopter?"), 0.72, 0.78, 0.86)
            end
        end)
    end

    if heli.insertion and not heli.captioned and elapsed >= Client.settings.heliCaptionMs then
        heli.captioned = true
        pcall(function()
            local player = getSpecificPlayer and getSpecificPlayer(0) or nil
            if player ~= nil then
                player:addLineChatElement(
                    ProjectALife.Text.ui("You can see a helicopter rappeling people"), 0.78, 0.86, 1.0)
            end
        end)
    end
    if heli.insertion == false then
        local listenerOutside = false
        pcall(function()
            local player = getSpecificPlayer(0)
            local square = player and player:getSquare()
            listenerOutside = square ~= nil and square:isOutside() and player:getBuilding() == nil
        end)
        if Client.spot == nil then volume = 0
        elseif not listenerOutside then volume = volume * Client.settings.heliIndoorShare end
    end

    local policy = ProjectALife.AudioPolicy
    if policy == nil or not policy.stillPlaying(heli.emitter, heli.soundName) then return end
    pcall(function()
        if heli.emitter ~= nil and heli.sound ~= nil then
            if heli.lastVolume ~= volume then heli.emitter:setVolume(heli.sound, volume) end
            heli.lastVolume = volume
            if Client.spot ~= nil and Client.spot.lightX ~= nil then
                heli.emitter:setPos(Client.spot.lightX, Client.spot.lightY, heli.z)
            end
        end
    end)
end

local function onTick()
    local now = nowMs()
    if Client.spot ~= nil then tickSpotlight(now) end
    if Client.heli ~= nil then tickHeli(now) end

    ProjectALife.AudioPolicy.sweepLoops(now)
    if #Client.queue == 0 then return end
    local index = 1
    while index <= #Client.queue do
        local beat = Client.queue[index]
        if now >= beat.at then
            if beat.emitter then
                pcall(function()
                    ProjectALife.AudioPolicy.stopOwned(beat.emitter, beat.stopSound, beat.stopName)
                end)
            else playAt(beat.sound, beat.x, beat.y, beat.z) end
            table.remove(Client.queue, index)
        else
            index = index + 1
        end
    end
end
Client.tick = onTick

function Client.ropeSpan(elapsedMs)
    local drop = tonumber(Client.settings.heliRopeMs) or 18000
    local t = (tonumber(elapsedMs) or 0) - (drop - 1500)
    if t < 0 or t >= 11000 then return nil end
    local lowered = math.min(1, t / 2000)
    if t > 9000 then lowered = (11000 - t) / 2000 end
    return 3.5, 3.5 * (1 - lowered)
end

Client.ropeStrands = {
    { shift = -1, colour = { 0.20, 0.17, 0.12 } },
    { shift = 0, colour = { 0.62, 0.51, 0.32 } },
    { shift = 1, colour = { 0.20, 0.17, 0.12 } },
}

function Client.renderRope()
    local heli = Client.heli
    if not heli or heli.insertion == false then return end
    local top, bottom = Client.ropeSpan(nowMs() - heli.startedAt)
    if not top then return end

    local tracer = ProjectALife.Tracer
    if tracer == nil then return end
    pcall(function()
        local square = getCell():getGridSquare(math.floor(heli.x), math.floor(heli.y), math.floor(heli.z))

        if not square or not square:isOutside() then return end
        local tile = tracer.whiteTile()
        if tile == nil then return end
        local zoom = tracer.viewZoom()
        local x, y = heli.x + 0.5, heli.y + 0.5
        local topX, topY = tracer.screenPoint(x, y, heli.z + top, zoom)
        local footX, footY = tracer.screenPoint(x, y, heli.z + bottom, zoom)
        for _, strand in ipairs(Client.ropeStrands) do
            local c = strand.colour
            getRenderer():renderline(tile, topX + strand.shift, topY, footX + strand.shift, footY,
                c[1], c[2], c[3], 0.95)
        end
    end)
end

function Client.silence()
    stopHeli()
    removeSpotlight()
    Client.spot = nil
    if ProjectALife.HeliLight ~= nil then ProjectALife.HeliLight.stop() end
    ProjectALife.AudioPolicy.stopAllLoops()
    Client.radioTalks = {}
end

function Client.reset()
    for _, beat in ipairs(Client.queue) do
        if beat.emitter then
            pcall(function()
                ProjectALife.AudioPolicy.stopOwned(beat.emitter, beat.stopSound, beat.stopName)
            end)
        end
    end
    Client.silence()
    Client.queue, Client.seen, Client.seenOrder = {}, {}, {}
end

if type(Events) == "table" then
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(onServerCommand) end
    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
    if Events.OnPreUIDraw ~= nil then Events.OnPreUIDraw.Add(Client.renderRope) end
    if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Add(Client.reset) end
    if Events.OnPlayerDeath ~= nil then Events.OnPlayerDeath.Add(Client.silence) end
    if Events.OnDisconnect ~= nil then Events.OnDisconnect.Add(Client.silence) end
end

return Client
