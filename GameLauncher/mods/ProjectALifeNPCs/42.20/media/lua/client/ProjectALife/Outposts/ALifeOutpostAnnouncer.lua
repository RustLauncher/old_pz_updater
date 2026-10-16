ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeAudioPolicy"

local Announcer = {
    settings = { checkMs = 1000, firstDelayMs = 8000 },

    nextAt = {},

    last = {},

    playing = {},
    nextCheckMs = 0,
    metrics = { played = 0, stopped = 0 },
}
ProjectALife.OutpostAnnouncer = Announcer

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll()
    if type(ZombRand) == "function" then return ZombRand(10000) / 10000 end
    return 0.5
end

function Announcer.volumeAt(distance, near, radius)
    local d = tonumber(distance) or 0
    near, radius = tonumber(near) or 20, tonumber(radius) or 90
    if d <= near then return 1 end
    if d >= radius then return 0 end
    return 1 - (d - near) / math.max(0.01, radius - near)
end

function Announcer.interval(spec, value)
    local every = math.max(30, tonumber(spec and spec.everySeconds) or 240)
    local jitter = math.max(0, tonumber(spec and spec.jitterSeconds) or 0)
    return math.floor((every + ((tonumber(value) or 0.5) * 2 - 1) * jitter) * 1000)
end

function Announcer.pick(sounds, lastIndex, value)
    if type(sounds) ~= "table" or #sounds == 0 then return nil, nil end
    if #sounds == 1 then return sounds[1], 1 end
    local index = 1 + math.floor((tonumber(value) or 0) * (#sounds - 1)) % (#sounds - 1)
    if lastIndex ~= nil and index >= lastIndex then index = index + 1 end
    return sounds[index], index
end

local function stop(siteId)
    local entry = Announcer.playing[siteId]
    if entry == nil then return end
    ProjectALife.AudioPolicy.stopOwned(entry.emitter, entry.sound, entry.name, true)
    Announcer.playing[siteId] = nil
    Announcer.metrics.stopped = Announcer.metrics.stopped + 1
end

function Announcer.level(entry, px, py)
    local dx, dy = (tonumber(entry.x) or 0) - (tonumber(px) or 0), (tonumber(entry.y) or 0) - (tonumber(py) or 0)
    local volume = Announcer.volumeAt(math.sqrt(dx * dx + dy * dy), entry.near, entry.radius)
    pcall(function() entry.emitter:set3D(entry.sound, false) end)
    pcall(function() entry.emitter:setVolume(entry.sound, volume) end)
    return volume
end

function Announcer.update(rows, px, py, now)
    now = tonumber(now) or nowMs()
    local seen = {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local spec = type(row) == "table" and row.announcer or nil
        if type(spec) == "table" and row.disabled ~= true then
            local siteId = tostring(row.site)
            seen[siteId] = true
            local dx, dy = (tonumber(row.x) or 0) - (tonumber(px) or 0), (tonumber(row.y) or 0) - (tonumber(py) or 0)
            local radius = tonumber(spec.radius) or 90
            if dx * dx + dy * dy <= radius * radius then
                if Announcer.nextAt[siteId] == nil then

                    Announcer.nextAt[siteId] = now + Announcer.settings.firstDelayMs
                elseif now >= Announcer.nextAt[siteId] and Announcer.playing[siteId] == nil then
                    local name, index = Announcer.pick(spec.sounds, Announcer.last[siteId], roll())
                    local emitter, sound
                    if ProjectALife.AudioPolicy.allowsAnnouncer(name) then
                        pcall(function()
                            emitter = getWorld():getFreeEmitter(row.x + 0.5, row.y + 0.5, row.z or 0)

                            if emitter ~= nil then
                                sound = ProjectALife.AudioPolicy.playLocal(emitter, name)
                            end
                        end)
                    end
                    if emitter ~= nil and sound ~= nil and sound ~= 0 then
                        local entry = { emitter = emitter, sound = sound, name = name, x = row.x, y = row.y,
                            near = tonumber(spec.near) or 20, radius = radius, spec = spec }
                        Announcer.playing[siteId] = entry
                        Announcer.level(entry, px, py)
                        Announcer.last[siteId] = index
                        Announcer.metrics.played = Announcer.metrics.played + 1
                    end
                    Announcer.nextAt[siteId] = now + Announcer.interval(spec, roll())
                end
            else

                Announcer.nextAt[siteId] = nil
                stop(siteId)
            end
        end
    end
    for siteId, entry in pairs(Announcer.playing) do

        local alive = ProjectALife.AudioPolicy.stillPlaying(entry.emitter, entry.name)
        if not seen[siteId] or not alive or not ProjectALife.AudioPolicy.allowsAnnouncer(entry.name) then stop(siteId)
        else Announcer.level(entry, px, py) end
    end
end

function Announcer.reset()
    for siteId in pairs(Announcer.playing) do stop(siteId) end
    Announcer.nextAt, Announcer.last = {}, {}
    Announcer.nextCheckMs = 0
end

local function tick()
    local now = nowMs()
    if now < Announcer.nextCheckMs then return end
    Announcer.nextCheckMs = now + Announcer.settings.checkMs
    local menu = ProjectALife.OutpostRadioMenu
    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    if menu == nil or player == nil or player:isDead() then Announcer.reset(); return end
    local px, py = 0, 0
    pcall(function() px, py = player:getX(), player:getY() end)
    Announcer.update(menu.radios, px, py, now)
end

if type(Events) == "table" and Events.OnTick ~= nil then Events.OnTick.Add(tick) end

return Announcer
