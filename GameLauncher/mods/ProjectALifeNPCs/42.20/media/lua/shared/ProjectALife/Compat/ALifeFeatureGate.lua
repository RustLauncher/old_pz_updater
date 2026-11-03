require "ProjectALife/Compat/ALifeModCompat"
require "ProjectALife/Records/ALifeDifficultyPreset"

ProjectALife = ProjectALife or {}

local Gate = {
    addonId = "ProjectALifeJimmy",
    native = { picked_over = true, war_dead = true, staged_boarding = true, discretion = true, calm_down = true,
        blame = true, breach_policy = true, zombie_focus = true },
    metrics = { addonOwned = 0 },
}
ProjectALife.FeatureGate = Gate
ProjectALife.NativeFeatures = Gate.native

function Gate.option(name, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = default
    if type(vars) == "table" and vars[name] ~= nil then value = vars[name] end
    local preset = ProjectALife.DifficultyPreset
    if preset ~= nil and type(preset.option) == "function" then value = preset.option(name, value, vars) end
    return value
end

function Gate.flag(name, default)
    return Gate.option(name, default) == true
end

function Gate.number(name, default, minimum, maximum)
    local value = tonumber(Gate.option(name, default)) or default
    if minimum ~= nil and value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

function Gate.addonActive()
    local compat = ProjectALife.ModCompat
    return compat ~= nil and type(compat.isActive) == "function" and compat.isActive(Gate.addonId) == true
end

function Gate.addonOwns(id)
    if not Gate.addonActive() then return false end
    local addon = rawget(_G, Gate.addonId)
    if type(addon) ~= "table" or type(addon.features) ~= "table" then return false end
    local def = addon.features[id]
    if type(def) ~= "table" then return false end
    if type(def.upstream) == "function" then return false end
    Gate.metrics.addonOwned = Gate.metrics.addonOwned + 1
    return true
end

function Gate.on(id, option, default)
    if option ~= nil and not Gate.flag(option, default ~= false) then return false end
    return not Gate.addonOwns(id)
end

function Gate.authority()
    return type(isClient) ~= "function" or not isClient()
end

function Gate.dedicated()
    return type(isServer) == "function" and isServer() == true
end

function Gate.worldReady()
    local runtime = ProjectALife.Runtime
    return Gate.authority() and type(runtime) == "table" and runtime.started == true
end

function Gate.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Gate.worldHours()
    if type(getGameTime) ~= "function" then return 0 end
    local time = getGameTime()
    if time == nil then return 0 end
    return tonumber(time:getWorldAgeHours()) or 0
end

function Gate.hash01(text)
    local h = 5381
    text = tostring(text)
    for i = 1, #text do h = (h * 33 + string.byte(text, i)) % 2147483647 end
    for _ = 1, 3 do h = (h * 48271) % 2147483647 end
    return (h % 100000) / 100000
end

function Gate.roll(count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return 0 end
    if type(ZombRand) == "function" then return ZombRand(count) end
    return 0
end

function Gate.chance(share)
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) < share end
    if type(ZombRand) == "function" then return ZombRand(10000) < share * 10000 end
    return false
end

function Gate.players()
    local out = {}
    local online = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    if online ~= nil and online:size() > 0 then
        for i = 0, online:size() - 1 do
            local player = online:get(i)
            if player ~= nil then out[#out + 1] = player end
        end
        return out
    end
    if type(getSpecificPlayer) ~= "function" then return out end
    for i = 0, 3 do
        local player = getSpecificPlayer(i)
        if player ~= nil then out[#out + 1] = player end
    end
    return out
end

function Gate.playerPoints()
    local out = {}
    for _, player in ipairs(Gate.players()) do
        if player:isDead() ~= true then out[#out + 1] = { x = player:getX(), y = player:getY() } end
    end
    return out
end

function Gate.nearestPlayer(x, y, points)
    local best = math.huge
    for _, p in ipairs(points or Gate.playerPoints()) do
        local d = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
        if d < best then best = d end
    end
    return best
end

function Gate.uidOf(shell)
    if shell == nil then return nil end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.variable) == "function" then
        local value = speech.variable(shell, "ALifeUID")
        if value ~= nil and value ~= "" then return tostring(value) end
    end
    if type(shell.hasModData) == "function" and shell:hasModData() ~= true then return nil end
    if type(shell.getModData) ~= "function" then return nil end
    local data = shell:getModData()
    return type(data) == "table" and data.ProjectALifeUID or nil
end

function Gate.recordOf(uid)
    if uid == nil then return nil end
    local executor = ProjectALife.Executor
    local mirror = executor ~= nil and type(executor.mirror) == "table" and executor.mirror.records or nil
    local record = type(mirror) == "table" and mirror[uid] or nil
    if record ~= nil then return record end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return nil end
    if type(registry.peek) == "function" then return registry.peek(uid) end
    if type(registry.read) == "function" then return registry.read(uid) end
    return nil
end

function Gate.aiUids()
    if type(isClient) == "function" and isClient() then
        local executor = ProjectALife.Executor
        return executor ~= nil and type(executor.order) == "table" and executor.order or {}
    end
    if Gate.dedicated() then return {} end
    local out, watchdog = {}, ProjectALife.Watchdog
    for uid in pairs(watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings or {}) do out[#out + 1] = uid end
    table.sort(out)
    return out
end

function Gate.shellOf(uid)
    if uid == nil then return nil end
    local executor = ProjectALife.Executor
    local entry = executor ~= nil and type(executor.executed) == "table" and executor.executed[uid] or nil
    if type(entry) == "table" and entry.shell ~= nil then return entry.shell end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    return type(binding) == "table" and binding.shell or nil
end

return Gate
