require "ProjectALife/Records/ALifeBehaviorSettings"

ProjectALife = ProjectALife or {}

local BehaviorSettings = ProjectALife.BehaviorSettings
local Gait = {
    metrics = {
        granted = 0, renewed = 0, sprinter = 0, jogger = 0,
        refusedDisabled = 0, refusedZombie = 0, refusedDistance = 0,
        refusedWinded = 0, refusedPacing = 0, downgradedSneak = 0, downgradedLimp = 0,
    },
}
ProjectALife.Gait = Gait

function Gait.settings()
    local behavior = BehaviorSettings or ProjectALife.BehaviorSettings
    local block = behavior ~= nil and behavior.gait or nil
    return type(block) == "table" and block or {}
end

function Gait.styleSettings(style)
    local block = Gait.settings()[style]
    return type(block) == "table" and block or {}
end

function Gait.hash(text)
    if type(text) ~= "string" or text == "" then return nil end
    local seed = 5381
    for index = 1, #text do
        seed = (seed * 33 + string.byte(text, index)) % 4294967291
    end
    for _ = 1, 3 do
        local reduced = seed % 67108859
        seed = (reduced * reduced + 40503) % 4294967291
    end
    return seed
end

function Gait.styleForUid(uid)
    local hash = Gait.hash(uid)
    if hash == nil then return "sprinter" end
    local percent = tonumber(Gait.settings().sprinterPercent)
    if percent == nil or percent ~= percent then percent = 50 end
    if percent < 0 then percent = 0 elseif percent > 100 then percent = 100 end
    return (hash % 100) < percent and "sprinter" or "jogger"
end

function Gait.styleOf(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return "sprinter" end
    local read, data = pcall(shell.getModData, shell)
    if not read or type(data) ~= "table" then return "sprinter" end
    local cached = data.ProjectALifeGait
    if cached == "sprinter" or cached == "jogger" then return cached end
    local uid = data.ProjectALifeUID
    if type(uid) ~= "string" or uid == "" then
        if type(shell.GetVariable) ~= "function" then return "sprinter" end
        local ok, value = pcall(shell.GetVariable, shell, "ALifeUID")
        uid = ok and value or nil
    end
    if type(uid) ~= "string" or uid == "" then return "sprinter" end
    local style = Gait.styleForUid(uid)
    data.ProjectALifeGait = style
    return style
end

function Gait.burstPace(shell)
    local style = Gait.styleOf(shell)
    local pace = Gait.styleSettings(style).pace
    if pace ~= "sprint" and pace ~= "run" then
        pace = style == "jogger" and "run" or "sprint"
    end
    if pace ~= "sprint" then return pace end
    local sneaking, limping = false, false
    if shell ~= nil and type(shell.getModData) == "function" then
        local read, data = pcall(shell.getModData, shell)
        if read and type(data) == "table" then
            sneaking = data.ProjectALifeSneakActive == true
            limping = data.ProjectALifeWoundLeg == true
        end
    end
    if limping then
        Gait.metrics.downgradedLimp = Gait.metrics.downgradedLimp + 1
        return "run"
    end
    if sneaking then
        Gait.metrics.downgradedSneak = Gait.metrics.downgradedSneak + 1
        return "run"
    end
    return "sprint"
end

local function positive(value)
    value = tonumber(value)
    if value == nil or value ~= value or value <= 0 or value == math.huge then return 1 end
    return value
end

function Gait.drainScale(uid)
    return positive(Gait.styleSettings(Gait.styleForUid(uid)).drainScale)
end

function Gait.recoveryScale(uid)
    return positive(Gait.styleSettings(Gait.styleForUid(uid)).recoveryScale)
end

function Gait.worthBurst(target)
    if target == nil then return true end
    local zombie = false
    pcall(function() zombie = target:isZombie() == true end)
    if not zombie then return true end
    local owned = false
    pcall(function()
        local data = target:getModData()
        owned = type(data) == "table" and (data.ProjectALifeOwned == true
            or data.ProjectALifeActor == true)
    end)
    return owned
end

function Gait.leaseMs()
    local value = tonumber(Gait.settings().leaseMs)
    if value == nil or value ~= value or value < 100 then return 1200 end
    return math.floor(value)
end

function Gait.grantBurst(actor, shell, target, now, distance, minimumDistance)
    if shell == nil or type(shell.getModData) ~= "function" then return false end
    local timestamp = tonumber(now)
    if timestamp == nil or timestamp ~= timestamp then return false end
    local movement = (BehaviorSettings or ProjectALife.BehaviorSettings or {}).movement
    if type(movement) == "table" and movement.sprintEnabled == false then
        Gait.metrics.refusedDisabled = Gait.metrics.refusedDisabled + 1
        return false
    end
    if not Gait.worthBurst(target) then
        Gait.metrics.refusedZombie = Gait.metrics.refusedZombie + 1
        return false
    end

    local gap, floor = tonumber(distance), tonumber(minimumDistance)
    if gap ~= nil and floor ~= nil and not (gap > floor) then
        Gait.metrics.refusedDistance = Gait.metrics.refusedDistance + 1
        return false
    end
    local Endurance = ProjectALife.Endurance
    if Endurance ~= nil and type(Endurance.canSprint) == "function"
            and not Endurance.canSprint(actor, shell, timestamp) then
        Gait.metrics.refusedWinded = Gait.metrics.refusedWinded + 1
        return false
    end
    local pacing = ProjectALife.Resistance
    if pacing ~= nil and type(pacing.mayBurst) == "function"
            and not pacing.mayBurst(actor, shell, target, gap, timestamp) then
        Gait.metrics.refusedPacing = Gait.metrics.refusedPacing + 1
        return false
    end

    local opened, renewed = false, false
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        renewed = timestamp < (tonumber(data.ProjectALifeSprintUntilMs) or 0)
        data.ProjectALifeSprintUntilMs = timestamp + Gait.leaseMs()
        opened = true
    end)
    if not opened then return false end
    if renewed then
        Gait.metrics.renewed = Gait.metrics.renewed + 1
    else
        Gait.metrics.granted = Gait.metrics.granted + 1
        local style = Gait.styleOf(shell)
        Gait.metrics[style] = (Gait.metrics[style] or 0) + 1
    end
    return true
end

function Gait.snapshot()
    local copy = {}
    for name, value in pairs(Gait.metrics) do copy[name] = value end
    return copy
end

return Gait
