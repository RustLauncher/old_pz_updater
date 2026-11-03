ProjectALife = ProjectALife or {}

local Stealth = {
    settings = {

        nightThreshold = 0.35,

        stalkBehind = 3.4,

        springDistance = 2.1,

        backstabScale = 2.2,

        behindDot = -0.35,

        paceScale = 0.85,

        pickMs = 4500,
    },
    metrics = { stalks = 0, backstabs = 0, picks = 0 },
}
ProjectALife.Stealth = Stealth

function Stealth.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Stealth.settings[key] ~= nil and tonumber(value) ~= nil then
            Stealth.settings[key] = tonumber(value)
        end
    end
    return true
end

function Stealth.night()
    local dark = false
    pcall(function()
        local climate = ClimateManager.getInstance()
        local light = math.min(climate:getDayLightStrength(), climate:getAmbient())
        dark = light < Stealth.settings.nightThreshold
    end)
    return dark
end

function Stealth.quietActive(data)
    if data.ProjectALifeSneakWant ~= true then return false end
    local profile = ProjectALife.SneakProfile
    if profile == nil or not profile.enabled() then return false end
    local untilMs = tonumber(data.ProjectALifeSneakUntilMs)
    if untilMs ~= nil and type(getTimestampMs) == "function" and getTimestampMs() > untilMs then
        data.ProjectALifeSneakWant = nil
        return false
    end
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    return phase == "idle" or phase == "" or phase == "aborted"
end

function Stealth.stanceActive(data)
    if type(data) ~= "table" then return false end
    if data.ProjectALifeConduct ~= "stealth" then return Stealth.quietActive(data) end
    local registry = ProjectALife.ModuleRegistry
    if registry ~= nil and not registry.isEnabled("stealth") then return false end

    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted"
            and phase ~= "approach" and phase ~= "cover" then
        return false
    end
    return true
end

function Stealth.backstabScaleFor(shell, target, data)
    if type(data) ~= "table" or data.ProjectALifeConduct ~= "stealth" then return 1 end
    if not Stealth.stanceActive(data) then return 1 end
    local scale = 1
    pcall(function()
        local forward = target:getForwardDirection()
        local fx, fy = forward:getX(), forward:getY()
        local dx, dy = shell:getX() - target:getX(), shell:getY() - target:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.001 then return end
        dx, dy = dx / length, dy / length

        if dx * fx + dy * fy < Stealth.settings.behindDot then
            scale = Stealth.settings.backstabScale
            Stealth.metrics.backstabs = Stealth.metrics.backstabs + 1
        end
    end)
    return scale
end

function Stealth.canPick(shell)
    return false
end

function Stealth.finishPick(shell, door)
    return false
end

return Stealth
