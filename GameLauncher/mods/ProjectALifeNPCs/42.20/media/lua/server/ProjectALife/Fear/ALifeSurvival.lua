require "ProjectALife/Behaviours/ALifeFireManeuver"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Shells/ALifeShellSimulation"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Endurance = ProjectALife.Endurance
local Survival = {
    adapters = {},

    retreat = false,
    reengageHealth = 0.45,
    retreatHealth = 0.35,

    flinchHealth = 0.6,
}
ProjectALife.Survival = Survival

Survival.squadLosses = {}
Survival.disengagements = {}
Survival.lossWindowMs = 15000
Survival.lossRadius = 30

function Survival.noteLoss(groupId, position, now)
    if groupId == nil then return end
    Survival.squadLosses[groupId] = { atMs = now, x = position and position.x, y = position and position.y }
end

function Survival.recentLoss(actor, shell, now)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    local loss = memory ~= nil and memory.groupId ~= nil and Survival.squadLosses[memory.groupId] or nil
    if loss == nil then return false end
    if (tonumber(now) or 0) - (tonumber(loss.atMs) or 0) > Survival.lossWindowMs then
        Survival.squadLosses[memory.groupId] = nil
        return false
    end
    if loss.x == nil then return true end
    local near = false
    pcall(function()
        local dx, dy = shell:getX() - loss.x, shell:getY() - loss.y
        near = dx * dx + dy * dy <= Survival.lossRadius * Survival.lossRadius
    end)
    return near
end

local function healthRatio(actor, shell)
    if type(Survival.adapters.healthRatio) == "function" then
        return tonumber(Survival.adapters.healthRatio(actor, shell)) or 1
    end
    local profile = Catalog.npc(actor.profileId)
    local general = profile and profile.general or nil

    local multiplier = 1
    local settings = ProjectALife.BehaviorSettings
    if type(settings) == "table" and type(settings.combat) == "table" then
        multiplier = tonumber(settings.combat.healthMultiplier) or 1
    end
    if multiplier <= 0 then multiplier = 1 end
    local standard = ProjectALife.CustomProfiles.startingHP()
    local base = tonumber(general and general.healthHP) or standard
    local tunedHealth = ProjectALife.NpcHealth
    if tunedHealth ~= nil and type(tunedHealth.authored) == "function" then
        base = tunedHealth.authored(general, standard)
    end
    local maximum = base * multiplier
    local data = shell ~= nil and shell.getModData ~= nil and shell:getModData() or nil
    if type(data) == "table" then
        maximum = tonumber(data.ProjectALifeMaximumHealth) or maximum
    end
    if shell == nil or shell.getHealth == nil then return 1 end
    local health = ProjectALife.ShellSimulation.trueHealth(shell)
    return math.max(0, math.min(1, health / math.max(0.1, maximum)))
end

function Survival.configure(adapters)
    Survival.adapters = adapters or {}
    Survival.retreat = Survival.adapters.retreat == true
    Survival.retreatHealth = math.max(0.05, math.min(0.8,
        tonumber(Survival.adapters.retreatHealth) or 0.35))
    Survival.reengageHealth = math.max(Survival.retreatHealth + 0.1, math.min(0.95,
        tonumber(Survival.adapters.reengageHealth) or 0.45))
    Survival.flinchHealth = math.max(Survival.retreatHealth, math.min(1,
        tonumber(Survival.adapters.flinchHealth) or 0.6))
end

Survival.healthRatio = function(actor, shell)
    return healthRatio(actor, shell)
end

function Survival.dry(shell, now)
    local data = shell ~= nil and shell.getModData ~= nil and shell:getModData() or nil
    local untilMs = type(data) == "table" and tonumber(data.ProjectALifeDryUntilMs) or nil
    local clock = tonumber(now)
    if clock == nil and type(getTimestampMs) == "function" then clock = getTimestampMs() end
    return untilMs ~= nil and (clock or 0) < untilMs
end

function Survival.hasFirearm(shell)
    if shell == nil or type(shell.getPrimaryHandItem) ~= "function" then return false end
    local weapon = shell:getPrimaryHandItem()
    if weapon == nil or type(weapon.isAimedFirearm) ~= "function"
            or type(weapon.getCurrentAmmoCount) ~= "function" then return false end
    return weapon:isAimedFirearm() == true
        and (tonumber(weapon:getCurrentAmmoCount()) or 0) > 0
end

function Survival.frightened(shell, suppliedNow, threat)
    local panic = ProjectALife.ModulePanic
    if panic == nil or type(panic.fearLive) ~= "function" then return false end
    if panic.fearLive(shell, suppliedNow) ~= true then return false end
    if threat == nil then return true end
    return type(panic.fearsThis) == "function" and panic.fearsThis(shell, threat) == true
end

function Survival.evaluate(actor, shell, threat, suppliedNow)
    if threat == nil then return "fight", 1 end
    local ratio = healthRatio(actor, shell)

    if Survival.dry(shell, suppliedNow) then return "retreat", ratio, "out_of_ammo" end

    if Survival.frightened(shell, suppliedNow, threat) then return "retreat", ratio, "gun_fear" end

    local profiles = ProjectALife.BehaviorProfiles
    local modules = ProjectALife.ModuleRegistry
    if modules ~= nil and type(actor) == "table" and type(modules.modules) == "table"
            and type(modules.allows) == "function" and modules.modules.withdraw ~= nil then
        if not modules.allows(actor, "withdraw") then
            return "fight", ratio, "profile_no_withdraw"
        end
    elseif profiles ~= nil then
        if not profiles.allows(actor, "withdraw") then
            return "fight", ratio, "profile_no_withdraw"
        end
    end
    local resistance = ProjectALife.Resistance
    local kind = resistance ~= nil and resistance.kindOf(threat) or nil
    local limit = Survival.retreatHealth
    if kind ~= nil and resistance.person(kind) then
        limit = resistance.retreatHealthFor(actor, shell, suppliedNow, limit)
    end
    if Survival.retreat and ratio <= limit then
        return "retreat", ratio, "low_health"
    end

    if Survival.retreat then
        local tired = Endurance.value(actor, shell, suppliedNow) <= Endurance.settings.retreatThreshold
        local flinch = ratio <= Survival.flinchHealth and Endurance.shouldRetreat(actor, shell, suppliedNow)
        if kind ~= nil and resistance.person(kind) then
            tired = resistance.tired(actor, shell, threat, kind, suppliedNow, tired)
            flinch = flinch and resistance.mayFlinch(actor, suppliedNow)
        end
        if tired or flinch then return "retreat", ratio, "endurance_or_recent_damage" end
    end
    return "fight", ratio, "ready"
end

function Survival.canReengage(actor, shell, suppliedNow)
    if Survival.dry(shell, suppliedNow) then return false end

    if Survival.frightened(shell, suppliedNow) then return false end
    return healthRatio(actor, shell) > math.max(Survival.reengageHealth, Survival.retreatHealth)
        and Endurance.canReengage(actor, shell, suppliedNow)
end

function Survival.beginDisengage(actor, shell, threat, suppliedNow, durationMs)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or threat == nil then return nil end
    local now = tonumber(suppliedNow)
    if now == nil then now = type(getTimestampMs) == "function" and getTimestampMs() or 0 end
    local untilMs = Endurance.beginRetreat(actor, shell, now)
    local lease = { generation = actor.generation, threat = threat, atMs = now,
        untilMs = math.max(untilMs, now + math.max(0, tonumber(durationMs) or 0)) }
    if type(threat.getX) == "function" and type(threat.getY) == "function"
            and type(threat.getZ) == "function" then
        lease.x, lease.y, lease.z = threat:getX(), threat:getY(), threat:getZ()
    end
    Survival.disengagements[actor.uid] = lease
    return lease.untilMs
end

function Survival.avoidsTarget(actor, threat, suppliedNow, contact)
    if contact == true or type(actor) ~= "table" or threat == nil then return false end
    local lease = Survival.disengagements[actor.uid]
    if lease == nil then return false end
    local now = tonumber(suppliedNow)
    if now == nil then now = type(getTimestampMs) == "function" and getTimestampMs() or 0 end
    if lease.generation ~= actor.generation or now < lease.atMs or now >= lease.untilMs then
        Survival.disengagements[actor.uid] = nil
        return false
    end
    if lease.threat == threat then return true end
    if lease.x == nil or type(threat.getX) ~= "function" or type(threat.getY) ~= "function"
            or type(threat.getZ) ~= "function" then return false end
    local withdraw = ProjectALife.ModuleWithdraw
    local radius = withdraw ~= nil and tonumber(withdraw.settings.crowdTiles) or 4
    return math.abs(threat:getZ() - lease.z) < 0.4
        and (threat:getX() - lease.x) ^ 2 + (threat:getY() - lease.y) ^ 2 <= radius * radius
end

function Survival.forget(uid, generation)
    local lease = Survival.disengagements[uid]
    if lease == nil or generation ~= nil and generation ~= lease.generation then return false end
    Survival.disengagements[uid] = nil
    return true
end

function Survival.retreatTarget(shell, threat, distance)
    if type(Survival.adapters.retreatTarget) == "function" then
        return Survival.adapters.retreatTarget(shell, threat, distance)
    end
    local cover = ProjectALife.FireManeuver.find(shell,threat,{mode="retreat",distance=distance})
    if cover ~= nil then return cover end
    local ok, sx, sy, sz, tx, ty = pcall(function()
        return shell:getX(), shell:getY(), shell:getZ(), threat:getX(), threat:getY()
    end)
    if not ok then return nil end
    local dx, dy = sx - tx, sy - ty
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.1 then dx, dy, length = 1, 0, 1 end
    local range = math.max(6, tonumber(distance) or 12)

    local side = (math.floor(math.abs(sx * 17 + sy * 31)) % 2 == 0) and 1 or -1
    local awayX, awayY = dx / length, dy / length
    return {
        x = sx + awayX * range - awayY * side * math.min(3, range * 0.25),
        y = sy + awayY * range + awayX * side * math.min(3, range * 0.25),
        z = sz,
    }
end

return Survival
