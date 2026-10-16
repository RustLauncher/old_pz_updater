ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Senses/ALifeStealth"
require "ProjectALife/Combat/ALifeHealth"

local Registry = ProjectALife.ModuleRegistry
local Stealth = ProjectALife.Stealth
local Health = ProjectALife.Health

local Conducts = { metrics = { stalks = 0, sniperSteps = 0, heals = 0, ambushes = 0 } }
ProjectALife.ModuleConducts = Conducts

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

local function nowMsFallback()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function standable(square)
    if square == nil then return false end
    local ok, free = pcall(function()
        if square:isSolid() == true or square:isSolidTrans() == true then return false end
        return square:isFree(false) == true
    end)
    return ok and free == true
end

Registry.register({
    id = "stealth",

    kind = "doctrine",
    dispatch = "positioning",
    primary = true,
    label = "Stealth killer",
    summary = "Shadows a person from behind, sneaking, and opens with a backstab at double damage. Picks locks instead of breaching.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)

        if context == nil or context.target == nil then return nil end
        if not Registry.allows(actor, "stealth") then return nil end
        local distance = tonumber(context.distance) or 0
        if distance <= Stealth.settings.springDistance then return nil end
        local point
        pcall(function()
            local target = context.target
            local forward = target:getForwardDirection()
            local fx, fy = forward:getX(), forward:getY()
            local behind = Stealth.settings.stalkBehind
            local cx = target:getX() - fx * behind
            local cy = target:getY() - fy * behind
            local cell = getCell()
            local square = cell and cell:getGridSquare(math.floor(cx), math.floor(cy),
                math.floor(target:getZ()))
            if not standable(square) then return end
            point = { x = cx, y = cy, z = math.floor(target:getZ()),
                pace = "walk", reason = "stealth_stalk", holdMs = 900 }
        end)
        if point ~= nil then Conducts.metrics.stalks = Conducts.metrics.stalks + 1 end
        return point
    end,
})

local SNIPER_STANDOFF = 16
local SNIPER_STEP = 8
Registry.register({
    id = "sniper",

    kind = "doctrine",
    dispatch = "positioning",
    primary = true,
    label = "Sniper",
    summary = "Keeps distance, gives ground when the fight closes, and fires deliberate single shots.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if context == nil or context.target == nil or context.ranged ~= true then return nil end
        if not Registry.allows(actor, "sniper") then return nil end
        local distance = tonumber(context.distance) or 0
        if distance >= SNIPER_STANDOFF then return nil end
        local point
        pcall(function()
            local target = context.target
            local dx = shell:getX() - target:getX()
            local dy = shell:getY() - target:getY()
            local length = math.sqrt(dx * dx + dy * dy)
            if length < 0.001 then dx, dy, length = 1, 0, 1 end
            dx, dy = dx / length, dy / length
            local cx = shell:getX() + dx * SNIPER_STEP
            local cy = shell:getY() + dy * SNIPER_STEP
            local cell = getCell()
            local square = cell and cell:getGridSquare(math.floor(cx), math.floor(cy),
                math.floor(shell:getZ()))
            if not standable(square) then return end
            point = { x = cx, y = cy, z = math.floor(shell:getZ()),
                pace = "run", reason = "sniper_standoff",
                legMs = 2600, holdMs = 1200 }
        end)
        if point ~= nil then Conducts.metrics.sniperSteps = Conducts.metrics.sniperSteps + 1 end
        return point
    end,
})

local MEDIC_RANGE = 25

function Conducts.patientScore(flat, downed)
    return (tonumber(flat) or 0) - (downed and 1e9 or 0)
end

function Conducts.medicTopUp(bandages, wipes)
    return { bandages = math.max(0, 4 - (tonumber(bandages) or 0)), wipes = math.max(0, 2 - (tonumber(wipes) or 0)) }
end

local function woundedGroupmate(actor, shell)
    local best, bestFlat, bestShell, bestScore
    pcall(function()
        local watchdog = ProjectALife.Watchdog
        local registry = ProjectALife.ActorRegistry
        if watchdog == nil or registry == nil then return end
        local group = actor.memory and actor.memory.groupId or nil
        if group == nil then return end
        local sx, sy = shell:getX(), shell:getY()
        for uid, binding in pairs(watchdog.bindings) do
            if uid ~= actor.uid and binding ~= nil and binding.shell ~= nil then
                local mate = registry.read(uid)
                if mate ~= nil and mate.lifecycle == "active"
                        and mate.memory ~= nil and mate.memory.groupId == group then
                    local mateShell = binding.shell
                    local data
                    pcall(function() data = mateShell:getModData() end)
                    if Health ~= nil and Health.wounded(data)
                            and data.ProjectALifeHealDoneAtMs == nil then
                        local flat
                        pcall(function()
                            local dx = mateShell:getX() - sx
                            local dy = mateShell:getY() - sy
                            flat = dx * dx + dy * dy
                        end)
                        local downed = Health ~= nil and type(Health.downedHolds) == "function"
                            and Health.downedHolds(data.ProjectALifeDownedUntilMs, nowMsFallback()) or false
                        local score = Conducts.patientScore(flat, downed)
                        if flat ~= nil and flat <= MEDIC_RANGE * MEDIC_RANGE
                                and (bestScore == nil or score < bestScore) then
                            best, bestFlat, bestShell, bestScore = mate, flat, mateShell, score
                        end
                    end
                end
            end
        end
    end)
    return best, bestShell, bestFlat
end

Registry.register({
    id = "medic",

    kind = "doctrine",
    dispatch = "decision",
    primary = true,
    label = "Medic",
    summary = "Finds the group's wounded after a fight, walks over, and dresses their wounds with its own bandages.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)

        if not Registry.allows(actor, "medic") then return nil end
        if Health == nil or Health.enabled ~= true then return nil end

        pcall(function()
            local data = shell:getModData()
            if data.ProjectALifeMedicKitIssued == true then return end
            data.ProjectALifeMedicKitIssued = true
            local inventory = shell:getInventory()
            if inventory == nil then return end
            local top = Conducts.medicTopUp(inventory:getCountTypeRecurse("Base.Bandage"), inventory:getCountTypeRecurse("Base.AlcoholWipes"))
            for _ = 1, top.bandages do inventory:AddItem("Base.Bandage") end
            for _ = 1, top.wipes do inventory:AddItem("Base.AlcoholWipes") end
        end)
        local mate, mateShell, flat = woundedGroupmate(actor, shell)
        if mateShell == nil then return nil end

        if flat > 2.25 then
            local destination
            pcall(function()
                destination = { x = mateShell:getX(), y = mateShell:getY(),
                    z = mateShell:getZ() }
            end)
            if destination == nil then return nil end
            return context.startMovement(actor, shell, destination, "medic", {
                pace = "run", timeoutMs = 12000,
            })
        end

        local bandage
        pcall(function()
            local inventory = shell:getInventory()
            if inventory ~= nil then
                bandage = inventory:getFirstTypeRecurse("Base.Bandage")
            end
        end)
        if bandage == nil then return nil end
        local duration = Health.settings.bandageMs
        pcall(function()
            mateShell:getModData().ProjectALifeHealDoneAtMs = context.now + duration
        end)
        pcall(function()
            local inventory = shell:getInventory()
            if inventory ~= nil then inventory:Remove(bandage) end
        end)
        pcall(function()
            local animations = ProjectALife.Animations
            if animations ~= nil then animations.apply(shell, "heal_bandage") end
        end)
        pcall(function() shell:setMoving(false) end)
        Conducts.metrics.heals = Conducts.metrics.heals + 1
        context.setActivity(actor, "idle", "treat_groupmate")
        return { kind = "idle", intent = "treat_groupmate",
            cooldownUntilMs = context.now + duration }
    end,
})

local AMBUSH_SPRING = 7
Registry.register({
    id = "ambusher",

    kind = "doctrine",
    dispatch = "positioning",
    primary = true,
    label = "Ambusher",
    summary = "Takes a hidden position, holds fire, and springs when the target walks in close.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if context == nil or context.target == nil then return nil end
        if not Registry.allows(actor, "ambusher") then return nil end
        local now = tonumber(context.now) or nowMsFallback()
        local distance = tonumber(context.distance) or 0

        if distance <= AMBUSH_SPRING then
            pcall(function()
                shell:getModData().ProjectALifeHoldFireUntilMs = nil
            end)
            return nil
        end

        pcall(function()
            shell:getModData().ProjectALifeHoldFireUntilMs = now + 2000
        end)

        local cover = ProjectALife.ModuleCover
        if cover ~= nil and now >= (tonumber(context.coverUntilMs) or 0) then
            local point = cover.find(shell, context.target, {})
            if point ~= nil then
                point.reason = "ambush_position"
                point.holdMs = 4000
                point.pace = "walk"
                Conducts.metrics.ambushes = Conducts.metrics.ambushes + 1
                return point
            end
        end
        return nil
    end,
})

local WEAVE_MINIMUM, WEAVE_MAXIMUM = 3.5, 34
Registry.register({
    id = "weave",
    kind = "craft",
    dispatch = "positioning",
    label = "Combat strafing (weave)",
    summary = "Shooters sidestep left and right while trading fire with people.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if context == nil or context.ranged ~= true or context.target == nil then return nil end
        if not Registry.allows(actor, "weave") then return nil end

        local person = false
        pcall(function()
            local combat = ProjectALife.Combat
            person = combat ~= nil and combat.kindOf(context.target) ~= "zombie"
        end)
        if not person then return nil end
        local distance = tonumber(context.distance) or 0
        if distance < WEAVE_MINIMUM or distance > WEAVE_MAXIMUM then return nil end
        local now = tonumber(context.now) or nowMsFallback()
        local data
        pcall(function() data = shell:getModData() end)
        if type(data) ~= "table" then return nil end

        local lastShot = tonumber(data.ProjectALifeLastShotAtMs)

        local weaveWindowMs = 900
        pcall(function()
            local weapons = ProjectALife.Weapons
            if weapons == nil or context.weapon == nil then return end
            local interval = tonumber(weapons.fireIntervalMs(context.weapon))
            if interval ~= nil and interval > weaveWindowMs then
                weaveWindowMs = interval
            end
        end)
        if lastShot == nil or now - lastShot > weaveWindowMs then return nil end
        if now < (tonumber(data.ProjectALifeWeaveNextAtMs) or 0) then return nil end
        data.ProjectALifeWeaveNextAtMs = now + 3000 + roll(1500)

        local side = data.ProjectALifeWeaveSide == 1 and -1 or 1
        data.ProjectALifeWeaveSide = side
        local point
        pcall(function()
            local target = context.target
            local dx = target:getX() - shell:getX()
            local dy = target:getY() - shell:getY()
            local length = math.sqrt(dx * dx + dy * dy)
            if length < 0.001 then return end
            dx, dy = dx / length, dy / length

            local cx = shell:getX() + (-dy) * side * 1.6
            local cy = shell:getY() + dx * side * 1.6
            local cell = getCell()
            local square = cell and cell:getGridSquare(math.floor(cx),
                math.floor(cy), math.floor(shell:getZ()))
            if not standable(square) then return end
            point = { x = cx, y = cy, z = math.floor(shell:getZ()),
                pace = "walk", reason = "weave", holdMs = 1500, legMs = 900 }
        end)
        return point
    end,
})

local SPREAD_SPACING = 2.0
Registry.register({
    id = "spread",
    kind = "upkeep",
    label = "Spread out",
    summary = "Squad members keep a couple of tiles of air between each other.",
    evaluate = function(actor, shell, context)
        if not Registry.allows(actor, "spread") then return nil end
        local spread = ProjectALife.GroupSpread
        if spread == nil or type(spread.settle) ~= "function" then return nil end
        return spread.settle(actor, shell, context, SPREAD_SPACING)
    end,
})

return Conducts
