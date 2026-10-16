require "ProjectALife/World/ALifeSupportClient"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Core/ALifeText"

ProjectALife = ProjectALife or {}

local RaidClient = {
    seenRaids = {},
    seenWaves = {},
    seenWarnings = {},
    title = nil,
    prelude = nil,
    rappel = nil,
    settings = {
        gateTiles = 120,
        gateFlat = 14400,
        titleMs = 2850,
        fadeInMs = 350,
        fadeOutMs = 700,
        groundDoorOpenS = 0.7,
        groundDoorCloseS = 1.8,
        rappelSeconds = 3.6,
        sting = "PALWorldEerie3",
        stingVolume = 1.0,
    },
    metrics = { starts = 0, waves = 0, dropped = 0, warnings = 0 },
}
ProjectALife.RaidClient = RaidClient

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function player()
    local value
    pcall(function() value = getSpecificPlayer(0) end)
    return value
end

local function nearby(payload)
    local subject = player()
    if subject == nil or type(payload) ~= "table" then return false end
    local x, y
    pcall(function() x, y = subject:getX(), subject:getY() end)
    if x == nil then return false end
    local dx = (tonumber(payload.x) or 0) - x
    local dy = (tonumber(payload.y) or 0) - y
    return dx * dx + dy * dy <= RaidClient.settings.gateFlat
end

local function worldSound(name, x, y, z, volume)
    local record
    pcall(function()
        local emitter = getWorld():getFreeEmitter(x, y, z or 0)
        if emitter == nil then return end

        local sound = ProjectALife.AudioPolicy.playLocal(emitter, name, volume)
        record = { emitter = emitter, sound = sound, name = name }
    end)
    return record
end

local function uiSound(name)
    local sound
    pcall(function() sound = getSoundManager():playUISound(name) end)
    return sound
end

local function stopUi(sound)
    if sound == nil then return end
    pcall(function() getSoundManager():stopUISound(sound) end)
end

local function streamerMode()
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.current) == "table"
            and settings.current.streamerMode == true then return true end
    local enabled = false
    pcall(function()
        enabled = SandboxVars ~= nil and SandboxVars.ALife ~= nil
            and SandboxVars.ALife.Streamer_Mode == true
    end)
    return enabled
end

function RaidClient.titleAlpha(elapsedMs)
    local settings = RaidClient.settings
    local elapsed = tonumber(elapsedMs) or 0
    if elapsed < 0 or elapsed >= settings.titleMs then return 0 end
    if elapsed < settings.fadeInMs then return elapsed / settings.fadeInMs end
    local fadeAt = settings.titleMs - settings.fadeOutMs
    if elapsed > fadeAt then return (settings.titleMs - elapsed) / settings.fadeOutMs end
    return 1
end

function RaidClient.playSting()
    local settings = RaidClient.settings
    if type(settings.sting) ~= "string" or settings.sting == "" then return nil end
    local subject = player()
    if subject == nil then return nil end
    local x, y, z
    pcall(function() x, y, z = subject:getX(), subject:getY(), subject:getZ() end)
    if x == nil then return nil end
    return worldSound(settings.sting, x, y, z, settings.stingVolume)
end

function RaidClient.onStart(payload)
    if type(payload) ~= "table" or payload.raidId == nil then return false end
    local id = tostring(payload.raidId)
    if RaidClient.seenRaids[id] or not nearby(payload) then
        RaidClient.metrics.dropped = RaidClient.metrics.dropped + 1
        return false
    end
    RaidClient.seenRaids[id] = true
    if RaidClient.intro ~= nil then
        pcall(function()
            ProjectALife.AudioPolicy.stopOwned(RaidClient.intro.emitter,
                RaidClient.intro.sound, RaidClient.intro.name)
        end)
    end
    stopUi(RaidClient.prelude and RaidClient.prelude.cry)
    local now = nowMs()
    local seconds = math.max(0, tonumber(payload.preludeSeconds) or 10)
    RaidClient.title = { raidId = id, startedAtMs = now }
    RaidClient.prelude = {
        raidId = id,
        confirmAtMs = now + RaidClient.settings.titleMs + seconds * 1000,
        confirmed = false,
        cry = nil,
    }
    RaidClient.intro = RaidClient.playSting()

    RaidClient.metrics.starts = RaidClient.metrics.starts + 1
    return true
end

function RaidClient.onWave(payload)
    if type(payload) ~= "table" or payload.raidId == nil
            or payload.waveNumber == nil then return false end
    local key = tostring(payload.raidId) .. ":" .. tostring(payload.waveNumber)
    if RaidClient.seenWaves[key] or not nearby(payload) then
        RaidClient.metrics.dropped = RaidClient.metrics.dropped + 1
        return false
    end
    RaidClient.seenWaves[key] = true
    local fx = ProjectALife.ArrivalFX
    if tostring(payload.delivery or "ground") == "heli" then
        if fx ~= nil and type(fx.playHeliArrival) == "function" then
            fx.playHeliArrival(payload.x, payload.y, payload.z,
                payload.tx, payload.ty, 35, payload.targetUsername)
        end

    elseif fx ~= nil and type(fx.playGroundArrival) == "function" then

        fx.playGroundArrival(payload.x, payload.y, payload.z)
    end
    RaidClient.metrics.waves = RaidClient.metrics.waves + 1
    return true
end

function RaidClient.warningText(payload)
    local faction = type(payload) == "table" and payload.faction or nil
    if type(faction) == "string" and faction ~= "" then
        return ProjectALife.Text.ui("You pick up radio chatter: {faction} are getting ready to hit a place near here - hours, not days",
            { faction = faction })
    end
    return ProjectALife.Text.ui("Radio chatter: some crew's gearing up to hit a place close by, hours not days")
end

function RaidClient.onWarning(payload)
    if type(payload) ~= "table" or payload.warningId == nil then return false end
    local id = tostring(payload.warningId)
    if RaidClient.seenWarnings[id] then
        RaidClient.metrics.dropped = RaidClient.metrics.dropped + 1
        return false
    end
    local subject = player()
    if subject == nil or type(subject.Say) ~= "function" then return false end
    RaidClient.seenWarnings[id] = true
    pcall(subject.Say, subject, RaidClient.warningText(payload))
    RaidClient.metrics.warnings = RaidClient.metrics.warnings + 1
    return true
end

local function confirmPrelude(now)
    local prelude = RaidClient.prelude
    if prelude == nil or prelude.confirmed or now < prelude.confirmAtMs then return end
    prelude.confirmed = true
    stopUi(prelude.cry)
    local subject = player()
    if subject ~= nil and type(sendClientCommand) == "function" then
        sendClientCommand(subject, "ProjectALife", "RaidPreludeFinished",
            { raidId = prelude.raidId })
    else
        pcall(function()
            local director = ProjectALife.RaidDirector
            local name = subject and subject:getUsername() or nil
            if director ~= nil then director.confirm(name, prelude.raidId) end
        end)
    end
end

local function tick()
    local now = nowMs()
    confirmPrelude(now)
    if RaidClient.title ~= nil
            and now >= RaidClient.title.startedAtMs + RaidClient.settings.titleMs then
        RaidClient.title = nil
        if RaidClient.intro ~= nil then
            pcall(function()
                ProjectALife.AudioPolicy.stopOwned(RaidClient.intro.emitter,
                    RaidClient.intro.sound, RaidClient.intro.name)
            end)
            RaidClient.intro = nil
        end
    end
    if RaidClient.rappel ~= nil and now >= RaidClient.rappel.stopAtMs then
        pcall(function()
            ProjectALife.AudioPolicy.stopOwned(RaidClient.rappel.emitter,
                RaidClient.rappel.sound, RaidClient.rappel.name)
        end)
        RaidClient.rappel = nil
    end
end

function RaidClient.reset()
    stopUi(RaidClient.prelude and RaidClient.prelude.cry)
    if RaidClient.intro ~= nil then
        pcall(function()
            ProjectALife.AudioPolicy.stopOwned(RaidClient.intro.emitter,
                RaidClient.intro.sound, RaidClient.intro.name)
        end)
    end

    if RaidClient.rappel ~= nil then
        pcall(function()
            ProjectALife.AudioPolicy.stopNamed(RaidClient.rappel.emitter,
                RaidClient.rappel.sound, RaidClient.rappel.name)
        end)
        RaidClient.rappel = nil
    end
    RaidClient.seenRaids, RaidClient.seenWaves, RaidClient.seenWarnings = {}, {}, {}
    RaidClient.title, RaidClient.prelude, RaidClient.intro = nil, nil, nil
end
RaidClient.tick = tick

local function drawTitle()
    local title = RaidClient.title
    if title == nil then return end
    local alpha = RaidClient.titleAlpha(nowMs() - title.startedAtMs)
    if alpha <= 0 then return end
    pcall(function()
        local text = getTextManager()
        local x = getCore():getScreenWidth() * 0.5
        local y = getCore():getScreenHeight() * 0.32

        local died = ProjectALife.Text.ui("THIS IS HOW YOU DIED")
        local stand = ProjectALife.Text.ui("YOUR LAST STAND BEGINS")
        text:DrawStringCentre(UIFont.Cred1, x + 2, y + 2, died, 0, 0, 0, alpha)
        text:DrawStringCentre(UIFont.Cred1, x, y, died, 0.92, 0.10, 0.08, alpha)
        text:DrawStringCentre(UIFont.Large, x + 1, y + 73, stand, 0, 0, 0, alpha)
        text:DrawStringCentre(UIFont.Large, x, y + 72, stand, 0.95, 0.88, 0.78, alpha)
    end)
end

local function onServerCommand(module, command, payload)
    if module ~= "ProjectALife" then return end
    if command == "RaidStart" then
        RaidClient.onStart(payload)
    elseif command == "RaidWave" then
        RaidClient.onWave(payload)
    elseif command == "RaidWarning" then
        RaidClient.onWarning(payload)
    end
end

if type(Events) == "table" then
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(onServerCommand) end
    if Events.OnTick ~= nil then Events.OnTick.Add(tick) end
    if Events.OnPostUIDraw ~= nil then Events.OnPostUIDraw.Add(drawTitle) end
    if Events.OnMainMenuEnter ~= nil then Events.OnMainMenuEnter.Add(RaidClient.reset) end
end

return RaidClient
