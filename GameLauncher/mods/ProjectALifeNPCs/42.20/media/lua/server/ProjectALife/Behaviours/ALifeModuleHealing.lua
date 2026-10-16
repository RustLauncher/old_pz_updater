ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Combat/ALifeHealth"
require "ProjectALife/Combat/ALifeInjury"

local Registry = ProjectALife.ModuleRegistry
local Health = ProjectALife.Health

local Healing = { id = "healing", metrics = { started = 0, downedRefused = 0 },
    settings = { dressUnderFireHealth = 0.75, dressClearTiles = 12, dressQuietMs = 5000 } }
ProjectALife.ModuleHealing = Healing

function Healing.dressingFor(hasBandage, hasSheets)
    if hasBandage then return "Base.Bandage" end
    if hasSheets then return "Base.RippedSheets" end
    return nil
end

function Healing.durationFor(itemType)
    if itemType == "Base.RippedSheets" then return Health.settings.sheetsMs or 5600 end
    return Health.settings.bandageMs
end

function Healing.fractionFor(itemType)
    if itemType == "Base.RippedSheets" then return Health.settings.sheetsHealToFraction or 0.5 end
    return Health.settings.healToFraction
end

Healing.partPoses = { arm_l = "heal_arm", arm_r = "heal_arm", leg_l = "heal_bandage", leg_r = "heal_bandage",
    head = "heal_head", torso = "heal_body" }

function Healing.poseFor(data)
    if data.ProjectALifeWoundLeg == true then return "heal_bandage" end
    local byPart = Healing.partPoses[tostring(data.ProjectALifeLastWoundPart or "")]
    if byPart ~= nil then return byPart end
    if data.ProjectALifeLastWoundZone == "head" then return "heal_head" end
    if data.ProjectALifeLastWoundZone == "torso" or data.ProjectALifeLastWoundZone == "body" then return "heal_body" end
    return "heal_arm"
end

function Healing.dressingOf(shell)
    local bandage, itemType
    pcall(function()
        local inventory = shell:getInventory()
        if inventory ~= nil then
            bandage = inventory:getFirstTypeRecurse("Base.Bandage")
            local sheets = inventory:getFirstTypeRecurse("Base.RippedSheets")
            itemType = Healing.dressingFor(bandage ~= nil, sheets ~= nil)
            if bandage == nil then bandage = sheets end
        end
    end)
    return bandage, itemType
end

function Healing.engaged(data, now)
    local quiet = Healing.settings.dressQuietMs
    local hold = tonumber(data.ProjectALifeDressHoldUntilMs)
    if hold ~= nil and now < hold then return true end
    local shotAt = tonumber(data.ProjectALifeLastShotAtMs)
    local hitAt = tonumber(data.ProjectALifeLastHitAtMs)
    return (shotAt ~= nil and now >= shotAt and now - shotAt < quiet)
        or (hitAt ~= nil and now >= hitAt and now - hitAt < quiet)
end

function Healing.canDress(shell, data, now)
    if Health == nil or Health.enabled ~= true then return false end
    if type(data) ~= "table" or not Health.wounded(data) then return false end
    if data.ProjectALifeHealDoneAtMs ~= nil then return false end
    if Healing.engaged(data, now) then return false end
    return not Health.downedHolds(data.ProjectALifeDownedUntilMs, now)
end

function Healing.bleeding(shell, data)
    if type(data) ~= "table" or Health == nil or not Health.wounded(data) then return false end
    if data.ProjectALifeWoundLeg == true then return true end
    local sim = ProjectALife.ShellSimulation
    if sim == nil or type(sim.trueHealth) ~= "function" or type(sim.maximumFor) ~= "function" then return false end
    local health = tonumber(sim.trueHealth(shell)) or 0
    local maximum = tonumber(sim.maximumFor(shell)) or 0
    return maximum > 0 and health / maximum <= Healing.settings.dressUnderFireHealth
end

function Healing.dressNow(actor, shell, context)
    if Health == nil or Health.enabled ~= true then return nil end
    local data
    pcall(function() data = shell:getModData() end)
    if type(data) ~= "table" or not Health.wounded(data) then return nil end

    if data.ProjectALifeHealDoneAtMs ~= nil then return nil end
    if Healing.engaged(data, context.now) then return nil end

    if Health.downedHolds(data.ProjectALifeDownedUntilMs, context.now) then
        Healing.metrics.downedRefused = (Healing.metrics.downedRefused or 0) + 1
        return nil
    end

    local bandage, itemType = Healing.dressingOf(shell)
    if bandage == nil or itemType == nil then return nil end
    local duration = Healing.durationFor(itemType)
    data.ProjectALifeHealToFraction = Healing.fractionFor(itemType)
    data.ProjectALifeHealDoneAtMs = context.now + duration
    Healing.metrics.started = Healing.metrics.started + 1

    pcall(function()
        local data = shell:getModData()
        data.ProjectALifeHandsBusyUntilMs = context.now
            + (tonumber(duration) or 4000) + 1000
    end)
    pcall(function() shell:setPrimaryHandItem(bandage) end)
    pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.apply(shell, Healing.poseFor(data)) end
    end)
    pcall(function() shell:setMoving(false) end)
    context.setActivity(actor, "idle", "dress_wounds")
    return { kind = "idle", intent = "dress_wounds",
        cooldownUntilMs = context.now + duration }
end

Registry.register({
    id = "healing",
    label = "Dress wounds",
    summary = "A wounded actor stops after the fight, bandages, and loses the limp and the bleeding.",
    kind = "upkeep",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        return Healing.dressNow(actor, shell, context)
    end,
})

return Healing
