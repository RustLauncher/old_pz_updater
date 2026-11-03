require "ProjectALife/Audio/ALifeInteractionCues"

ProjectALife = ProjectALife or {}

local Policy = { npcAudioEnabled = false }
ProjectALife.AudioPolicy = Policy

function Policy.allowsNPC()
    return Policy.npcAudioEnabled == true
end

function Policy.allowsAnnouncer(name)
    return name == "PALAnnouncerCheckpoint"
end

function Policy.caption(text)
    if type(text) ~= "string" or text == "" then return nil end

    if string.match(text, "^%s*%[[^%]]+%]%s*$") then return nil end
    return text
end

function Policy.stillPlaying(emitter, name)
    if emitter == nil or type(name) ~= "string" or name == "" then return false end
    local playing = false
    pcall(function() playing = emitter:isPlaying(name) == true end)
    return playing
end

function Policy.stopOwned(emitter, handle, name, localOnly)
    if emitter == nil or handle == nil then return false end
    if not Policy.stillPlaying(emitter, name) then return false end
    local stopped = false
    pcall(function()
        if localOnly == true then emitter:stopSoundLocal(handle)
        else emitter:stopSound(handle) end
        stopped = true
    end)
    return stopped
end

function Policy.stopLeftover(emitter, handle, localOnly)
    if emitter == nil or handle == nil then return false end
    local stopped = false
    pcall(function()
        if localOnly == true then emitter:stopSoundLocal(handle)
        else emitter:stopSound(handle) end
        stopped = true
    end)
    return stopped
end

function Policy.playFrom(source, sound)
    if source == nil or type(sound) ~= "string" or sound == "" then return false end
    local dedicated = type(isServer) == "function" and isServer() == true
    if dedicated and type(sendPlaySound) == "function" then
        return pcall(sendPlaySound, sound, false, source) == true
    end
    if type(source.playSound) ~= "function" then return false end
    return pcall(source.playSound, source, sound) == true
end

function Policy.playLocal(emitter, name, volume)
    if emitter == nil or type(name) ~= "string" or name == "" then return nil, nil end
    local handle
    pcall(function()
        handle = emitter:playSoundImpl(name, false, nil)
        if handle ~= nil and handle ~= 0 and volume ~= nil then emitter:setVolume(handle, volume) end
    end)
    if handle == nil or handle == 0 then return nil, nil end
    return handle, name
end

Policy.nearRadius = 25
Policy.nearGapMs = 900
Policy.nearMinFactor = 0.1
Policy.nearGate = {}
Policy.nearGateCount = 0
Policy.nearGateMax = 96

function Policy.biteLoudness()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = type(vars) == "table" and tonumber(vars.Audio_BiteLoudness) or nil
    if value == nil then value = 40 end
    return math.max(0, math.min(100, value)) / 100
end

function Policy.nearestListener(x, y, z)
    local best
    local function take(player)
        if player == nil then return end
        local alive = true
        pcall(function() alive = player:isAlive() == true end)
        if not alive then return end
        local dx = player:getX() - x
        local dy = player:getY() - y
        local dz = (player:getZ() - z) * 3.0
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if best == nil or d < best then best = d end
    end
    local dedicated = type(isServer) == "function" and isServer() == true
    if dedicated and type(getOnlinePlayers) == "function" then
        pcall(function()
            local list = getOnlinePlayers()
            for index = 0, list:size() - 1 do take(list:get(index)) end
        end)
    elseif type(getSpecificPlayer) == "function" then
        pcall(function()
            local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
            for index = 0, math.max(1, tonumber(count) or 1) - 1 do take(getSpecificPlayer(index)) end
        end)
    end
    return best
end

function Policy.nearGateOpen(key, now, gapMs)
    local gate = Policy.nearGate
    if gate[key] ~= nil and now < gate[key] then return false end
    if gate[key] == nil then
        if Policy.nearGateCount >= Policy.nearGateMax then
            Policy.nearGate = {}
            Policy.nearGateCount = 0
            gate = Policy.nearGate
        end
        Policy.nearGateCount = Policy.nearGateCount + 1
    end
    gate[key] = now + gapMs
    return true
end

function Policy.nearSound(source, name, opts)
    if source == nil or type(name) ~= "string" or name == "" then return nil end
    opts = opts or {}
    local loud = tonumber(opts.loudness) or Policy.biteLoudness()
    if loud <= 0 then return nil end
    local radius = tonumber(opts.radius) or Policy.nearRadius
    local x, y, z = 0, 0, 0
    local located = pcall(function() x, y, z = source:getX(), source:getY(), source:getZ() end)
    if not located then return nil end
    local distance = Policy.nearestListener(x, y, z)
    if distance == nil or distance > radius then return nil end
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local key = opts.key or source
    if not Policy.nearGateOpen(key, now, tonumber(opts.gapMs) or Policy.nearGapMs) then return nil end
    local ratio = distance / radius
    local volume = loud * math.max(Policy.nearMinFactor, 1 - ratio * ratio)
    local dedicated = type(isServer) == "function" and isServer() == true
    if dedicated and type(sendPlaySound) == "function" then
        pcall(sendPlaySound, name, false, source)
        return nil
    end
    local emitter, handle
    pcall(function()
        if type(source.getEmitter) == "function" then
            emitter = source:getEmitter()
        elseif type(getWorld) == "function" then
            emitter = getWorld():getFreeEmitter(x, y, z)
        end
        if emitter ~= nil then
            handle = emitter:playSound(name)
            if handle ~= nil and handle ~= 0 then emitter:setVolume(handle, volume) end
        end
    end)
    if handle == nil or handle == 0 then return nil end
    local maxMs = tonumber(opts.maxMs)
    if maxMs ~= nil then Policy.watchLoop(emitter, handle, name, now + maxMs, now) end
    return handle, emitter
end

function Policy.stopNamed(emitter, handle, name, localOnly)
    if emitter == nil or type(name) ~= "string" or name == "" then return true end
    Policy.stopOwned(emitter, handle, name, localOnly)
    if not Policy.stillPlaying(emitter, name) then return true end
    pcall(function() emitter:stopSoundByName(name) end)
    return not Policy.stillPlaying(emitter, name)
end

Policy.loops = {}
Policy.loopCeilingMs = 240000
Policy.loopRetryMs = 1000
Policy.loopsMax = 64

function Policy.watchLoop(emitter, handle, name, deadlineMs, now)
    if emitter == nil or type(name) ~= "string" or name == "" then return false end
    now = tonumber(now) or 0
    local ceiling = now + Policy.loopCeilingMs
    deadlineMs = tonumber(deadlineMs) or ceiling
    if deadlineMs > ceiling then deadlineMs = ceiling end
    while #Policy.loops >= Policy.loopsMax do
        local oldest = Policy.loops[1]
        pcall(function() Policy.stopNamed(oldest.emitter, oldest.handle, oldest.name) end)
        table.remove(Policy.loops, 1)
    end
    Policy.loops[#Policy.loops + 1] = { emitter = emitter, handle = handle,
        name = name, deadlineMs = deadlineMs, ceilingMs = ceiling }
    return true
end

function Policy.forgetLoop(emitter, name)
    for index = #Policy.loops, 1, -1 do
        local entry = Policy.loops[index]
        if entry.emitter == emitter and entry.name == name then table.remove(Policy.loops, index) end
    end
end

function Policy.sweepLoops(now)
    now = tonumber(now)
    if now == nil then return 0 end
    local swept, index = 0, 1
    while index <= #Policy.loops do
        local entry = Policy.loops[index]
        if now >= entry.deadlineMs then
            local cleared = false
            pcall(function()
                cleared = Policy.stopNamed(entry.emitter, entry.handle, entry.name) == true
            end)
            if cleared or now >= entry.ceilingMs then
                table.remove(Policy.loops, index)
                swept = swept + 1
            else

                entry.deadlineMs = now + Policy.loopRetryMs
                index = index + 1
            end
        else
            index = index + 1
        end
    end
    return swept
end

function Policy.stopAllLoops()
    local stopped = 0
    for index = #Policy.loops, 1, -1 do
        local entry = Policy.loops[index]
        pcall(function() Policy.stopNamed(entry.emitter, entry.handle, entry.name) end)
        table.remove(Policy.loops, index)
        stopped = stopped + 1
    end
    return stopped
end

return Policy
