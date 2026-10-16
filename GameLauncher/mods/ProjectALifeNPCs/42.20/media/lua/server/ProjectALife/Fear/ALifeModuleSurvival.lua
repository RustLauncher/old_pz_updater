require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Fear/ALifeSurvival"
require "ProjectALife/Fear/ALifeEncounterPolicy"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Survival = ProjectALife.Survival
local EncounterPolicy = ProjectALife.EncounterPolicy

local function threatIsPerson(threatKind, threat)
    if threatKind == "player" then return true end
    if threatKind == "actor" then return true end
    if threat == nil then return false end
    local owned = false
    pcall(function()
        local data = threat:getModData()
        owned = type(data) == "table" and (data.ProjectALifeOwned == true
            or data.ProjectALifeActor == true)
    end)
    return owned
end

local function hasFirearm(shell)
    return Survival.hasFirearm(shell)
end

Registry.register({
    id = "flee",
    label = "Flee",
    summary = "The badly wounded break off and a shaken gunman may rout; fear of guns belongs to the gun fear module.",
    kind = "reaction",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)

        if hasFirearm(shell) and threatIsPerson(context.threatKind, context.threat) then
            local ratio = Survival.healthRatio(actor, shell)
            local shaken = Survival.recentLoss(actor, shell, context.now)
            if ratio > (Survival.retreatHealth or 0.35) and not shaken then return nil end
            local memory = type(actor.memory) == "table" and actor.memory or {}
            actor.memory = memory
            if (tonumber(memory.routRolledAtMs) or 0) + 30000 > context.now then
                return nil 
            end
            if type(context.persistMemory) == "function" then
                context.persistMemory(actor, "routRolledAtMs", context.now)
            else
                memory.routRolledAtMs = context.now
            end
            local routs = type(ZombRand) ~= "function" or ZombRand(100) < 50
            if not routs then return nil end
            return context.startRetreat(actor, shell, context.threat,
                context.threatKind, context.now, "rout")
        end
        local function sprintAway()
            pcall(function()

                shell:getModData().ProjectALifeSprintUntilMs = context.now + 14000
            end)
            pcall(function()
                local combat = ProjectALife.Combat
                if combat ~= nil and type(combat.postureUntilMs) == "table" then

                    combat.postureUntilMs[shell] = context.now + 15000
                end
            end)
        end

        if threatIsPerson(context.threatKind, context.threat) then
            local gunFear = ProjectALife.ModuleGunFear
            if gunFear ~= nil and type(gunFear.evaluate) == "function" then
                local state = gunFear.evaluate(actor, shell, context)
                if state ~= nil then return state end
            end
        end
        local ratio = Survival.healthRatio(actor, shell)
        if ratio > (Survival.retreatHealth or 0.35) then return nil end
        sprintAway()
        return context.startRetreat(actor, shell, context.threat,
            context.threatKind, context.now, "low_health")
    end,
})

return true
