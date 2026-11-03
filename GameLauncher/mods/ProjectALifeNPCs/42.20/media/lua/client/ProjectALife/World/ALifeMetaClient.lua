require "ProjectALife/World/ALifeMetaEvents"
require "ProjectALife/Audio/ALifeAudioPolicy"

ProjectALife = ProjectALife or {}

local MetaClient = {
    seen = {},
    active = {},
    metrics = { received = 0, played = 0, dropped = 0 },
}
ProjectALife.MetaClient = MetaClient

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function seeded(seed)
    local value = math.floor(tonumber(seed) or 1) % 2147483647
    if value == 0 then value = 1 end
    return function()
        value = (value * 48271) % 2147483647
        return value / 2147483647
    end
end

local function emitterAt(x, y, z)
    local emitter
    pcall(function() emitter = getWorld():getFreeEmitter(x, y, z or 0) end)
    return emitter
end

local function play(emitter, name, volume)
    if emitter == nil or not ProjectALife.MetaEvents.soundAllowed(name) then return nil end
    return ProjectALife.AudioPolicy.playLocal(emitter, name, volume)
end

local function stop(event)
    pcall(function()
        ProjectALife.AudioPolicy.stopNamed(event.emitter, event.loop, event.loopName)
        ProjectALife.AudioPolicy.forgetLoop(event.emitter, event.loopName)
        ProjectALife.AudioPolicy.stopOwned(event.emitter, event.voice, event.voiceName)
    end)
end

function MetaClient.plan(kind, seed, startedAt)
    local random = seeded(seed)
    local event = {
        kind = tostring(kind or ""),
        startedAt = tonumber(startedAt) or 0,
        nextAt = tonumber(startedAt) or 0,
        random = random,
        shots = 0,
    }

    local day
    pcall(function() day = getGameTime():getWorldAgeHours() / 24 end)
    if event.kind == "gunfire" then
        local custom = ProjectALife.MetaEvents.sounds.distantFire
        local share = tonumber(ProjectALife.MetaEvents.settings.customFireShare) or 0
        if type(custom) == "table" and #custom > 0 and random() < share then
            event.oneShot = custom[1 + math.floor(random() * #custom) % #custom]
            event.oneShotVolume = 1
            event.durationMs = 45000
        else
            event.remaining = 4 + math.floor(random() * 6)
            event.durationMs = 20000 + math.floor(random() * 20001)
        end
    elseif event.kind == "heli" then
        event.durationMs = 60000 + math.floor(random() * 30001)
        event.bearing = random() * math.pi * 2

        local passes = ProjectALife.MetaEvents.sounds.heliPass
        if type(passes) == "table" and #passes > 0 and random() < 0.66 then
            event.pass = passes[1 + math.floor(random() * #passes) % #passes]
        end
    elseif event.kind == "military" then
        event.durationMs = 60000 + math.floor(random() * 60001)
        event.remaining = 18 + math.floor(random() * 19)
        event.bearing = random() * math.pi * 2
    elseif event.kind == "crash" then

        event.oneShot = ProjectALife.MetaEvents.crashForRoll(random())

        event.oneShotVolume = 1
        event.followUp = ProjectALife.MetaEvents.sounds.crashAftermath
        event.followUpAt = (tonumber(startedAt) or 0) + 3000 + math.floor(random() * 3001)
        event.durationMs = 45000
    elseif event.kind == "ambience" then
        event.oneShot = ProjectALife.MetaEvents.ambienceForRoll(random(), day)
        event.oneShotVolume = 1
        event.durationMs = 45000

        if random() < 0.5 then
            local second = ProjectALife.MetaEvents.ambienceForRoll(random(), day)
            if second ~= nil and second ~= event.oneShot then
                event.followUps = { { at = (tonumber(startedAt) or 0)
                    + 3000 + math.floor(random() * 5001), name = second } }
            end
        end

        if type(event.oneShot) == "string" and string.sub(event.oneShot, 1, 13) == "PALWorldEerie" then
            local eerie = {}
            for _, name in ipairs(ProjectALife.MetaEvents.sounds.ambience) do
                if string.sub(name, 1, 13) == "PALWorldEerie" and name ~= event.oneShot then eerie[#eerie + 1] = name end
            end
            local count = 1 + math.floor(random() * 2)
            local at = tonumber(startedAt) or 0
            event.followUps = {}
            for step = 1, math.min(count, #eerie) do
                at = at + 4000 + math.floor(random() * 6001)
                event.followUps[#event.followUps + 1] = { at = at, name = table.remove(eerie, 1 + math.floor(random() * #eerie)) }
            end
        end
    else
        return nil
    end
    return event
end

function MetaClient.onEvent(payload)
    if type(payload) ~= "table" or payload.eventId == nil then return false end
    MetaClient.metrics.received = MetaClient.metrics.received + 1
    local id = tostring(payload.eventId)
    if MetaClient.seen[id] then
        MetaClient.metrics.dropped = MetaClient.metrics.dropped + 1
        return false
    end
    local now = nowMs()
    local event = MetaClient.plan(payload.kind, payload.seed, now)
    if event == nil then return false end
    event.id = id
    event.x, event.y, event.z = tonumber(payload.x) or 0,
        tonumber(payload.y) or 0, tonumber(payload.z) or 0
    event.emitter = emitterAt(event.x, event.y, event.z)
    if event.emitter == nil then return false end
    if event.kind == "heli" or event.kind == "military" then

        if event.pass ~= nil then
            event.voice, event.voiceName = play(event.emitter, event.pass, 1)
        else
            event.loop, event.loopName = play(event.emitter, ProjectALife.MetaEvents.sounds.heli, 0.5)
        end

        if event.loop ~= nil then
            pcall(function()
                ProjectALife.AudioPolicy.watchLoop(event.emitter, event.loop, event.loopName,
                    now + event.durationMs + 5000, now)
            end)
        end
    end
    if type(event.oneShot) == "string" and string.sub(event.oneShot, 1, 13) == "PALWorldEerie" then

        local until_ = tonumber(MetaClient.eerieCooldownUntilMs)
        if until_ ~= nil and now < until_ then
            event.followUps = nil
            event.oneShot = "PALWorldCarAlarm"
        else
            MetaClient.eerieCooldownUntilMs = now + MetaClient.eerieCooldownMs
        end
    end
    if event.oneShot ~= nil then
        event.voice, event.voiceName = play(event.emitter, event.oneShot, event.oneShotVolume or 0.9)
    end
    MetaClient.seen[id] = true
    MetaClient.active[#MetaClient.active + 1] = event
    MetaClient.metrics.played = MetaClient.metrics.played + 1
    return true
end

local function gunshot(event, now)
    if event.remaining == nil or event.remaining <= 0 or now < event.nextAt then return end
    local bank = ProjectALife.MetaEvents.sounds.gunfire
    local index = 1 + math.floor(event.random() * #bank) % #bank
    play(event.emitter, bank[index], event.kind == "military" and 0.65 or 0.45)
    event.remaining = event.remaining - 1
    event.shots = event.shots + 1
    local left = math.max(1, event.remaining)
    local untilDone = math.max(250, event.startedAt + event.durationMs - now)
    event.nextAt = now + math.max(250, math.floor(untilDone / left
        * (0.55 + event.random() * 0.9)))
end

local function moveHeli(event, now)
    if event.kind ~= "heli" and event.kind ~= "military" then return end

    local policy = ProjectALife.AudioPolicy
    if policy == nil or not policy.stillPlaying(event.emitter,
            event.loopName or event.voiceName) then return end
    local elapsedSeconds = math.max(0, now - event.startedAt) / 1000
    local x = event.x + math.cos(event.bearing) * elapsedSeconds * 8
    local y = event.y + math.sin(event.bearing) * elapsedSeconds * 8
    pcall(function() event.emitter:setPos(x, y, event.z) end)
end

function MetaClient.busy(event, now)
    if event.voice == nil then return false end
    now = tonumber(now) or nowMs()
    if event.voiceWaitSinceMs == nil then event.voiceWaitSinceMs = now end
    if now - event.voiceWaitSinceMs > 20000 then
        event.voiceWaitSinceMs = nil
        return false
    end

    local policy = ProjectALife.AudioPolicy
    local playing = policy ~= nil and policy.stillPlaying(event.emitter, event.voiceName)
    if not playing then event.voiceWaitSinceMs = nil end
    return playing
end

local function tick()
    local now, index = nowMs(), 1

    ProjectALife.AudioPolicy.sweepLoops(now)
    while index <= #MetaClient.active do
        local event = MetaClient.active[index]
        if now >= event.startedAt + event.durationMs then
            stop(event)
            table.remove(MetaClient.active, index)
        else
            if event.kind == "gunfire" or event.kind == "military" then gunshot(event, now) end
            if event.followUp ~= nil and event.followUpAt ~= nil and now >= event.followUpAt
                    and not MetaClient.busy(event, now) then
                event.voice, event.voiceName = play(event.emitter, event.followUp, 0.7)
                event.followUp = nil
            end
            if type(event.followUps) == "table" and event.followUps[1] ~= nil and now >= event.followUps[1].at
                    and not MetaClient.busy(event, now) then
                local next_ = table.remove(event.followUps, 1)
                event.voice, event.voiceName = play(event.emitter, next_.name, event.oneShotVolume or 0.75)
            end
            moveHeli(event, now)
            index = index + 1
        end
    end
end

MetaClient.eerieCooldownMs = 300000
function MetaClient.debugPlay(kind)
    local x, y, z = 0, 0, 0
    pcall(function()
        local player = getSpecificPlayer(0)
        x, y, z = player:getX() + 42, player:getY() - 42, player:getZ()
    end)
    MetaClient.debugSequence = (MetaClient.debugSequence or 0) + 1
    return MetaClient.onEvent({ eventId = "debug:" .. tostring(MetaClient.debugSequence),
        kind = tostring(kind or "ambience"), x = x, y = y, z = z,
        seed = math.floor(nowMs() % 2147483646) + 1 })
end

MetaClient.firstDay = {
    untilHours = 24,
    minGapMinutes = 90,
    maxGapMinutes = 180,
    chancePercent = 20,
    minDistance = 60,
    maxDistance = 150,
    sounds = { "PALWorldPoliceSiren", "PALWorldCarAlarm", "PALWorldDistress1",
        "PALWorldDistress2", "PALWorldScream" },
    nextAtHours = nil,
}

function MetaClient.firstDayNextHours(hours, roll)
    local settings = MetaClient.firstDay
    local span = settings.maxGapMinutes - settings.minGapMinutes
    return (tonumber(hours) or 0)
        + (settings.minGapMinutes + span * math.max(0, math.min(1, tonumber(roll) or 0))) / 60
end

function MetaClient.firstDayBeat(hours, roll, pick)
    local settings = MetaClient.firstDay
    hours = tonumber(hours)
    if hours == nil or hours > settings.untilHours then return nil end
    if settings.nextAtHours == nil then
        local memory = MetaClient.airRaidMemory()
        local saved = memory ~= nil and tonumber(memory.beatNext) or nil
        if saved ~= nil and saved > hours - 2 then
            settings.nextAtHours = saved
        else
            settings.nextAtHours = MetaClient.firstDayNextHours(hours, roll)
            if memory ~= nil then memory.beatNext = settings.nextAtHours end
        end
        return nil
    end
    if hours < settings.nextAtHours then return nil end
    settings.nextAtHours = MetaClient.firstDayNextHours(hours, roll)
    do
        local memory = MetaClient.airRaidMemory()
        if memory ~= nil then memory.beatNext = settings.nextAtHours end
    end
    if (tonumber(roll) or 0) * 100 >= settings.chancePercent then return nil end
    local bank = settings.sounds
    local index = 1 + math.floor((tonumber(pick) or 0) * #bank) % #bank
    return bank[index]
end

local function roll()
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    return math.random()
end

MetaClient.openingFired = {}

function MetaClient.openingDone(slot)
    local memory = MetaClient.airRaidMemory()
    return memory ~= nil and memory["opening:" .. tostring(slot)] == true
end

function MetaClient.markOpening(slot)
    local memory = MetaClient.airRaidMemory()
    if memory ~= nil then memory["opening:" .. tostring(slot)] = true end
end

function MetaClient.helicoptersAllowed()
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.helicoptersAllowed) == "function" then
        return settings.helicoptersAllowed() == true
    end
    local flag
    pcall(function() flag = SandboxVars.ALife.Raid_Helicopter end)
    return flag ~= false
end

function MetaClient.openingDue(elapsedMs, spent)
    local minutes = (tonumber(elapsedMs) or 0) / 60000
    for _, cue in ipairs(ProjectALife.MetaEvents.openingCues()) do
        if (spent == nil or spent[cue.slot] ~= true)
                and minutes >= (tonumber(cue.minutes) or 0) then
            return cue
        end
    end
    return nil
end

function MetaClient.openingBeat(now)
    local meta = ProjectALife.MetaEvents
    local opening = meta ~= nil and meta.opening or nil
    if opening == nil or opening.enabled ~= true then return false end
    if meta.settings.enabled ~= true then return false end
    now = tonumber(now) or nowMs()

    if MetaClient.openingStartedMs == nil then
        local present = false
        pcall(function() present = getSpecificPlayer(0) ~= nil end)
        if not present then return false end
        MetaClient.openingStartedMs = now
        return false
    end
    if now < (MetaClient.openingQuietUntilMs or -1e12) then return false end
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    hours = tonumber(hours) or 0
    if hours >= (tonumber(opening.untilHours) or 168) then return false end
    local cue = MetaClient.openingDue(now - MetaClient.openingStartedMs, MetaClient.openingFired)
    if cue == nil then return false end

    if MetaClient.openingDone(cue.slot)
            or (cue.heli == true and not MetaClient.helicoptersAllowed())
            or (cue.heli == true and not meta.sirenAircraftAllowed())
            or not meta.raidSoundAllowed(cue.name)
            or not meta.soundAllowed(cue.name)
            or not meta.soundAllowedOnDay(cue.name, hours / 24) then
        MetaClient.openingFired[cue.slot] = true
        return false
    end
    local played = false
    pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local angle = roll() * math.pi * 2
        local near = tonumber(cue.near) or 0
        local distance = near + math.max(0, (tonumber(cue.far) or near) - near) * roll()
        local emitter = emitterAt(math.floor(player:getX() + math.cos(angle) * distance),
            math.floor(player:getY() + math.sin(angle) * distance), player:getZ())
        if emitter ~= nil and play(emitter, cue.name, tonumber(opening.volume) or 1) ~= nil then
            played = true
        end
    end)
    if not played then

        local late = (now - MetaClient.openingStartedMs) / 60000
            - (tonumber(cue.minutes) or 0)
        if late > (tonumber(opening.graceMinutes) or 3) then
            MetaClient.openingFired[cue.slot] = true
        end
        return false
    end
    MetaClient.markOpening(cue.slot)
    MetaClient.openingFired[cue.slot] = true
    MetaClient.openingQuietUntilMs = now + (tonumber(opening.minGapMinutes) or 1) * 60000
    return true
end

function MetaClient.firstDayTick()
    if ProjectALife.MetaEvents.settings.enabled ~= true then return end

    local now = nowMs()
    local support = ProjectALife.SupportClient
    local flying = support ~= nil and support.heli ~= nil

    if #MetaClient.active == 0 and not flying and MetaClient.openingBeat(now) then
        MetaClient.firstDayQuietUntilMs = now + 600000
        return
    end
    if MetaClient.firstDay.untilHours <= 0 then return end
    if now < (MetaClient.firstDayQuietUntilMs or -1e12) or #MetaClient.active > 0 then return end
    if flying then return end

    if MetaClient.airRaidRepeats() then
        MetaClient.firstDayQuietUntilMs = now + 600000
        return
    end
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    local name = MetaClient.firstDayBeat(hours, roll(), roll())
    if name == nil then return end
    MetaClient.firstDayQuietUntilMs = now + 600000
    pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local settings = MetaClient.firstDay
        local angle = roll() * math.pi * 2
        local distance = settings.minDistance
            + (settings.maxDistance - settings.minDistance) * roll()
        local x = player:getX() + math.cos(angle) * distance
        local y = player:getY() + math.sin(angle) * distance
        local emitter = emitterAt(math.floor(x), math.floor(y), player:getZ())
        if emitter ~= nil then play(emitter, name, 0.85) end
    end)
end

function MetaClient.silence()
    for _, event in ipairs(MetaClient.active) do stop(event) end
    MetaClient.active = {}
    ProjectALife.AudioPolicy.stopAllLoops()
end

function MetaClient.reset()
    MetaClient.silence()
    MetaClient.seen = {}
    MetaClient.firstDay.nextAtHours, MetaClient.firstDayQuietUntilMs = nil, nil
    MetaClient.sessionAlarmPlayed = nil
    MetaClient.openingFired = {}
    MetaClient.openingStartedMs, MetaClient.openingQuietUntilMs = nil, nil
end

function MetaClient.worldFirstDay()
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return (tonumber(hours) or 0) < 24
end

MetaClient.airRaidFired = {}

function MetaClient.airRaidMemory()
    local memory
    pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local data = player:getModData()
        if data == nil then return end
        if type(data.ProjectALifeAirRaid) ~= "table" then data.ProjectALifeAirRaid = {} end
        memory = data.ProjectALifeAirRaid
    end)
    return memory
end

function MetaClient.airRaidDone(slot)
    local memory = MetaClient.airRaidMemory()
    return memory ~= nil and memory[tostring(slot)] == true
end

function MetaClient.markAirRaid(slot)
    local memory = MetaClient.airRaidMemory()
    if memory ~= nil then memory[tostring(slot)] = true end
end

function MetaClient.airRaidRepeats()
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    hours = tonumber(hours)
    if hours == nil or hours >= 24 then return false end
    local slot = hours >= 16 and 2 or hours >= 8 and 1 or nil
    if slot == nil or MetaClient.airRaidFired[slot] then return false end

    if MetaClient.airRaidDone(slot) then
        MetaClient.airRaidFired[slot] = true
        return false
    end
    MetaClient.airRaidFired[slot] = true
    local settings = ProjectALife.MetaEvents and ProjectALife.MetaEvents.settings or {}
    if settings.enabled == false then return false end
    if not ProjectALife.MetaEvents.soundAllowed("PALWorldAirRaidSiren") then return false end
    if not ProjectALife.MetaEvents.raidSoundAllowed("PALWorldAirRaidSiren") then return false end
    local played = false
    pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local emitter = emitterAt(player:getX() + 8, player:getY() - 8, player:getZ())
        if emitter ~= nil and play(emitter, "PALWorldAirRaidSiren", 0.45) ~= nil then played = true end
    end)
    if played then MetaClient.markAirRaid(slot) end
    return played
end

function MetaClient.sessionAlarm(force)
    if MetaClient.sessionAlarmPlayed == true then return false end
    MetaClient.sessionAlarmPlayed = true
    local settings = ProjectALife.MetaEvents and ProjectALife.MetaEvents.settings or {}
    if settings.enabled == false then return false end
    local name = ProjectALife.MetaEvents.sounds.sessionAlarm

    local firstDaySiren = MetaClient.worldFirstDay()
    if firstDaySiren then
        name = "PALWorldAirRaidSiren"

        if force ~= true and MetaClient.airRaidDone(0) then return false end
    elseif force ~= true then
        MetaClient.markAirRaid("over")
        return false
    end
    if not ProjectALife.MetaEvents.soundAllowed(name) then return false end
    if force ~= true and not ProjectALife.MetaEvents.raidSoundAllowed(name) then return false end

    local played = false
    pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local emitter = emitterAt(player:getX() + 8, player:getY() - 8, player:getZ())
        if emitter == nil then return end
        if play(emitter, name, name == "PALWorldAirRaidSiren" and 0.45 or 1) ~= nil then played = true end
    end)
    if not played then
        pcall(function()
            getSoundManager():playUISound(name)
            played = true
        end)
    end
    if played and firstDaySiren then MetaClient.markAirRaid(0) end
    return played
end

local function onServerCommand(module, command, payload)
    if module == "ProjectALife" and command == "MetaEvent" then
        MetaClient.onEvent(payload)
    end
end

if type(Events) == "table" then
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(onServerCommand) end
    if Events.EveryOneMinute ~= nil then Events.EveryOneMinute.Add(MetaClient.firstDayTick) end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(MetaClient.sessionAlarm) end
    if Events.OnTick ~= nil then Events.OnTick.Add(tick) end
    if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Add(MetaClient.reset) end

    if Events.OnPlayerDeath ~= nil then Events.OnPlayerDeath.Add(MetaClient.silence) end
    if Events.OnDisconnect ~= nil then Events.OnDisconnect.Add(MetaClient.silence) end
end

return MetaClient
