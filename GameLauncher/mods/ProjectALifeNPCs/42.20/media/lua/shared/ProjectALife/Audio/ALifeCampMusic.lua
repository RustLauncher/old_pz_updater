ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeAudioPolicy"

local Music = {

    settings = { staleMs = 4000, sweepMs = 500,
        near = 4, far = 26, hearFrom = 32 },

    playing = ProjectALife.CampMusic and ProjectALife.CampMusic.playing or {},
    metrics = { started = 0, stopped = 0 },
    nextSweepMs = 0,
}
ProjectALife.CampMusic = Music

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function keyOf(shell)
    local key
    pcall(function() key = shell:getModData().ProjectALifeUID end)
    if key == nil then return tostring(shell) end
    return tostring(key)
end

function Music.volumeAt(distance, near, far)
    local d = tonumber(distance)
    if d == nil then return 1 end
    near, far = tonumber(near) or 4, tonumber(far) or 26
    if d <= near then return 1 end
    if d >= far then return 0 end
    local t = 1 - (d - near) / math.max(0.01, far - near)
    return t * t
end

function Music.listenerDistance(x, y)
    local distance
    pcall(function()
        if type(getSpecificPlayer) ~= "function" then return end
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local dx, dy = player:getX() - x, player:getY() - y
        distance = math.sqrt(dx * dx + dy * dy)
    end)
    return distance
end

function Music.level(emitter, sound, distance, near, far)

    if emitter == nil then return end
    if emitter.set3D ~= nil then emitter:set3D(sound, false) end
    if distance == nil then return end
    pcall(function() emitter:setVolume(sound, Music.volumeAt(distance, near, far)) end)
end

local function stopEntry(key, entry)

    pcall(function()
        local emitter = entry.shell:getEmitter()
        if entry.name ~= nil then
            ProjectALife.AudioPolicy.stopOwned(emitter, entry.sound, entry.name)
        else
            ProjectALife.AudioPolicy.stopLeftover(emitter, entry.sound)
        end
    end)
    Music.playing[key] = nil
    Music.metrics.stopped = Music.metrics.stopped + 1
end

function Music.hold(shell, name)
    if shell == nil then return false end

    Music.stop(shell)
    return false
end

function Music.stop(shell)
    if shell == nil then return false end
    local key = keyOf(shell)
    local entry = Music.playing[key]
    if entry == nil then return false end
    stopEntry(key, entry)
    return true
end

function Music.sweep(now)
    for key, entry in pairs(Music.playing) do
        stopEntry(key, entry)
    end
end

local function tick()
    local now = nowMs()
    if now < Music.nextSweepMs then return end
    Music.nextSweepMs = now + Music.settings.sweepMs

    for _ in pairs(Music.playing) do
        Music.sweep(now)
        return
    end
end

Music.sweep(nowMs())
if type(Events) == "table" and Events.OnTick ~= nil then Events.OnTick.Add(tick) end

return Music
