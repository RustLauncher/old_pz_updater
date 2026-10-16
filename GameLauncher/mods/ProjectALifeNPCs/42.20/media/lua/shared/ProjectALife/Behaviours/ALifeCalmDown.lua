require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Calm = {
    id = "calm_down", defaultHours = 2, keepReleasedHours = 24, originalForget = nil,
    metrics = { stamped = 0, calmed = 0 },
}
ProjectALife.CalmDown = Calm

function Calm.active()
    return Gate.on(Calm.id, "CalmDown_Enabled", true)
end

function Calm.hours()
    return Gate.number("CalmDown_Hours", Calm.defaultHours, 0, 24)
end

function Calm.naturallyHostile(record)
    local reputation = ProjectALife.Reputation
    if type(record) ~= "table" or reputation == nil or type(reputation.escalationBaseline) ~= "function" then return false end
    local ok, baseline = pcall(reputation.escalationBaseline, record)
    return ok and baseline == "hostile"
end

function Calm.stamp(record, key)
    if type(record) ~= "table" or key == nil or not Calm.active() then return false end
    local memory = type(record.memory) == "table" and record.memory or nil
    if memory == nil then return false end
    local keys = memory.hostileToPlayerKeys
    if type(keys) == "table" and keys[key] == true then return false end
    if Calm.naturallyHostile(record) then return false end
    memory.calmProvoked = type(memory.calmProvoked) == "table" and memory.calmProvoked or {}
    memory.calmProvoked[key] = Gate.worldHours()
    if type(memory.calmReleased) == "table" then memory.calmReleased[key] = nil end
    Calm.metrics.stamped = Calm.metrics.stamped + 1
    return true
end

function Calm.release(own, theirs)
    local released = type(theirs) == "table" and theirs.calmReleased or nil
    local keys = type(own) == "table" and own.hostileToPlayerKeys or nil
    if type(released) ~= "table" or type(keys) ~= "table" then return 0 end
    local held = type(theirs.hostileToPlayerKeys) == "table" and theirs.hostileToPlayerKeys or {}
    local cleared = 0
    for key in pairs(released) do
        if keys[key] ~= nil and held[key] ~= true then
            keys[key] = nil
            cleared = cleared + 1
        end
    end
    return cleared
end

function Calm.settle(fresh, hours, limit)
    local memory = fresh.memory
    local keep = Calm.naturallyHostile(fresh)
    local calmed = 0
    for key, at in pairs(memory.calmProvoked or {}) do
        if keep then
            memory.calmProvoked[key] = nil
        elseif hours - (tonumber(at) or hours) >= limit then
            if type(memory.hostileToPlayerKeys) == "table" then memory.hostileToPlayerKeys[key] = nil end
            memory.calmReleased = type(memory.calmReleased) == "table" and memory.calmReleased or {}
            memory.calmReleased[key] = hours
            memory.calmProvoked[key] = nil
            calmed = calmed + 1
        end
    end
    local pending = false
    for _ in pairs(memory.calmProvoked or {}) do pending = true break end
    if not pending then memory.calmProvoked = nil end
    if type(memory.calmReleased) == "table" then
        for key, at in pairs(memory.calmReleased) do
            if hours - (tonumber(at) or hours) > Calm.keepReleasedHours then memory.calmReleased[key] = nil end
        end
        local kept = false
        for _ in pairs(memory.calmReleased) do kept = true break end
        if not kept then memory.calmReleased = nil end
    end
    return calmed
end

function Calm.sweep(hours)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" or type(registry.update) ~= "function" then return 0 end
    hours = tonumber(hours) or Gate.worldHours()
    local limit = Calm.hours()
    local due = {}
    registry.each(function(record)
        local memory = type(record) == "table" and record.memory or nil
        if type(memory) == "table" and (type(memory.calmProvoked) == "table" or type(memory.calmReleased) == "table") then
            due[#due + 1] = record.uid
        end
    end)
    local calmed = 0
    for _, uid in ipairs(due) do
        local record = registry.read(uid)
        if record ~= nil then
            registry.update(uid, record.revision, function(fresh)
                if type(fresh.memory) == "table" then calmed = calmed + Calm.settle(fresh, hours, limit) end
            end)
        end
    end
    if calmed > 0 then print("[A-Life] calm down: " .. calmed .. " provoked grudge(s) let go") end
    Calm.metrics.calmed = Calm.metrics.calmed + calmed
    return calmed
end

function Calm.applyForget()
    local reputation = ProjectALife.Reputation
    if reputation == nil then return false end
    if Calm.originalForget == nil then Calm.originalForget = reputation.provokedForgetHours end
    reputation.provokedForgetHours = Calm.active() and Calm.hours() or Calm.originalForget
    return true
end

function Calm.tick()
    Calm.applyForget()
    if Gate.worldReady() and Calm.active() then Calm.sweep(Gate.worldHours()) end
end

if type(Events) == "table" and Events.EveryTenMinutes ~= nil then
    Events.EveryTenMinutes.Add(function() pcall(Calm.tick) end)
end

return Calm
