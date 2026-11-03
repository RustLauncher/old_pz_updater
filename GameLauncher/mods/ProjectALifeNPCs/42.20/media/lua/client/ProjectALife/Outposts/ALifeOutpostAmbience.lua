ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeAudioPolicy"

local Ambience = {

    settings = { radius = 48, checkMs = 500, near = 6, far = 44 },

    playing = ProjectALife.OutpostAmbience and ProjectALife.OutpostAmbience.playing or {},
    nextCheckMs = 0,
    metrics = { started = 0, stopped = 0 },
}
ProjectALife.OutpostAmbience = Ambience

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function stop(siteId)
    local entry = Ambience.playing[siteId]
    if entry == nil then return end
    pcall(function()
        ProjectALife.AudioPolicy.stopOwned(entry.emitter, entry.sound, entry.name)
    end)
    Ambience.playing[siteId] = nil
    Ambience.metrics.stopped = Ambience.metrics.stopped + 1
end

function Ambience.wanted(rows, px, py, radius)
    local result = {}
    radius = tonumber(radius) or Ambience.settings.radius
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and type(row.ambience) == "string" and row.disabled ~= true then
            local dx, dy = (tonumber(row.x) or 0) - (tonumber(px) or 0), (tonumber(row.y) or 0) - (tonumber(py) or 0)
            if dx * dx + dy * dy <= radius * radius then result[tostring(row.site)] = row end
        end
    end
    return result
end

function Ambience.level(emitter, sound, x, y, px, py)
    local dx, dy = (tonumber(x) or 0) - (tonumber(px) or 0), (tonumber(y) or 0) - (tonumber(py) or 0)
    local distance = math.sqrt(dx * dx + dy * dy)
    local music = ProjectALife.CampMusic
    local volume = music ~= nil and music.volumeAt(distance, Ambience.settings.near, Ambience.settings.far) or 1
    pcall(function() emitter:set3D(sound, false) end)
    pcall(function() emitter:setVolume(sound, volume) end)
    return volume
end

function Ambience.update(rows, px, py)

    for siteId in pairs(Ambience.playing) do stop(siteId) end
end

local function tick()
    local now = nowMs()
    if now < Ambience.nextCheckMs then return end
    Ambience.nextCheckMs = now + Ambience.settings.checkMs

    Ambience.update()
end

Ambience.update()
if type(Events) == "table" and Events.OnTick ~= nil then Events.OnTick.Add(tick) end

return Ambience
