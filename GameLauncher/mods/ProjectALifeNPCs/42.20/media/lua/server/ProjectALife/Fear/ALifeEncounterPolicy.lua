require "ProjectALife/Senses/ALifePerception"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Fear/ALifeThreatWatch"

ProjectALife = ProjectALife or {}

local Perception = ProjectALife.Perception
local Animations = ProjectALife.Animations

local function voiceSilent() return false end
local Voice = setmetatable({}, {
    __index = function(_, key)
        local real = ProjectALife.Voice
        local value = type(real) == "table" and real[key] or nil
        if type(value) == "function" then return value end
        return voiceSilent
    end,
})

local EncounterPolicy = { adapters = {}, aimRange = 16, aimSlackDegrees = 6 }
ProjectALife.EncounterPolicy = EncounterPolicy

function EncounterPolicy.configure(adapters)
    EncounterPolicy.adapters = adapters or {}
end

function EncounterPolicy.reactToAim(actor, shell, now)
    local data = shell:getModData()
    if now < (tonumber(data.ProjectALifeAimCheckAtMs) or 0) then return false end
    data.ProjectALifeAimCheckAtMs = now + 500
    local locator, watch = ProjectALife.PlayerLocator, ProjectALife.ThreatWatch
    if locator == nil or watch == nil then return false end

    local careful = ProjectALife.ModuleCareful
    local visible = careful ~= nil and type(careful.visible) == "function" and careful.visible or nil
    for _, player in ipairs(locator.list()) do
        local ok, aimed = pcall(function()
            if visible ~= nil and not visible(player) then return false end
            if player:isDead() or not player:isAiming() then return false end
            local weapon = player:getPrimaryHandItem()

            if weapon == nil or weapon.isRanged == nil or not weapon:isRanged() then return false end
            return watch.aimedAt(player, shell, EncounterPolicy.aimRange,
                EncounterPolicy.aimSlackDegrees, 0)
        end)

        if ok and aimed and type(watch.fightFiltered) == "function"
                and watch.fightFiltered(actor, player, now) == true then
            aimed = false
        end
        if ok and aimed then return Voice.play(shell, "AIMED_AT") end
    end
    return false
end
