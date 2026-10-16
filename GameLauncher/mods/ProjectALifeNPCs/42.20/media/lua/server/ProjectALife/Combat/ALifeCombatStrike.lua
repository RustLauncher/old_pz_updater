require "ProjectALife/Combat/ALifeCombatCore"
require "ProjectALife/Combat/ALifeWeapons"
require "ProjectALife/Combat/ALifeLineOfFire"
require "ProjectALife/Combat/ALifeGunDiscipline"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Movement/ALifeEndurance"
require "ProjectALife/Audio/ALifeVoice"
require "ProjectALife/Decisions/ALifeFairness"
require "ProjectALife/Shells/ALifeWounds"
require "ProjectALife/Compat/ALifeInterop"
require "ProjectALife/Shells/ALifeArmor"
require "ProjectALife/Talk/ALifeSpeech"

ProjectALife = ProjectALife or {}

local Weapons = ProjectALife.Weapons
local Animations = ProjectALife.Animations
local TargetPolicy = ProjectALife.TargetPolicy
local Endurance = ProjectALife.Endurance
local Voice = ProjectALife.Voice
local Combat = ProjectALife.Combat
local Interop = ProjectALife.Interop

Combat.MELEE_CLIP_REACTION = {
    combat_melee = "HeadLeft", combat_1h_d = "HeadTop", combat_1h_e = "Uppercut",
    combat_2h_a = "HeadLeft", combat_2h_c = "HeadTop", combat_2h_d = "Uppercut",
    combat_2h_heavy_a = "HeadLeft", combat_2h_heavy_b = "HeadTop",
    combat_knife = "Uppercut",
    combat_spear_b = "HeadRight", combat_spear_a = "HeadTop",
    combat_chainsaw = "Chainsaw",
    combat_punch_a = "HeadRight", combat_punch_b = "HeadLeft", combat_punch_c = "Uppercut",
}

Combat.MELEE_ROSTER = {
    oneHanded = { "combat_1h_d", "combat_melee", "combat_1h_e" },
    twoHanded = { "combat_2h_c", "combat_2h_a", "combat_2h_d" },
    heavy = { "combat_2h_heavy_b", "combat_2h_heavy_a" },
    knife = { "combat_knife" },
    spear = { "combat_spear_b", "combat_spear_a" },
    chainsaw = { "combat_chainsaw" },
    unarmed = { "combat_punch_b", "combat_punch_a", "combat_punch_c" },
}

Combat.FLOOR_SWING_CLASS = {
    combat_stomp = "stomp", combat_floor_knife = "floorStab", combat_floor_spear = "floorStab",
}

local function meleeClass(weapon)
    if Combat.isUnarmed(weapon) then return "unarmed" end

    local named
    pcall(function()
        local kind = WeaponType.getWeaponType(weapon)
        if kind == WeaponType.UNARMED then named = "unarmed"
        elseif kind == WeaponType.KNIFE then named = "knife"
        elseif kind == WeaponType.SPEAR then named = "spear"
        elseif kind == WeaponType.CHAINSAW then named = "chainsaw"
        elseif kind == WeaponType.TWO_HANDED then named = "twoHanded"
        elseif kind == WeaponType.ONE_HANDED then named = "oneHanded" end
    end)
    if named ~= nil then return named end
    local twoHanded = false
    pcall(function()
        twoHanded = weapon:isRequiresEquippedBothHands() == true
    end)
    return twoHanded and "twoHanded" or "oneHanded"
end

local function isHeavyMelee(weapon)
    local weight = 0
    pcall(function() weight = tonumber(weapon:getActualWeight()) or 0 end)
    return weight >= 3.0
end

local function meleeSwing(weapon)
    local class = meleeClass(weapon)
    if class == "twoHanded" and isHeavyMelee(weapon) then class = "heavy" end
    local roster = Combat.MELEE_ROSTER[class] or Combat.MELEE_ROSTER.oneHanded
    local clip = roster[1]
    if #roster > 1 and type(ZombRand) == "function" then
        clip = roster[1 + ZombRand(#roster)] or clip
    end
    return clip, Combat.MELEE_CLIP_REACTION[clip] or "HeadLeft", class
end

function Combat.canShove(target)
    local player = false
    pcall(function() player = instanceof(target, "IsoPlayer") == true end)
    return not player
end

function Combat.shovePreset(shell, weapon)
    if Combat.isRanged(weapon) then
        return tostring(Combat.variable(shell, "ALifeWeaponClass")) == "handgun"
            and "shove_handgun" or "shove_rifle"
    end
    if Combat.isUnarmed(weapon) then return "combat_unarmed" end
    local class = meleeClass(weapon)
    if class == "twoHanded" then
        return isHeavyMelee(weapon) and "shove_heavy" or "shove_bat"
    end
    if class == "spear" then return "shove_bat" end
    return "shove_default"
end

function Combat.meleeSwingScale(weapon)
    if weapon == nil then return 1 end
    local ok, value = pcall(function() return weapon:getSwingTime() end)
    value = ok and tonumber(value) or nil
    if value == nil or value <= 0 then return 1 end

    return math.max(0.8, math.min(1.3, value / 2.0))
end

function Combat.tiredTempo(shell)
    local endurance = ProjectALife.Endurance
    if endurance == nil or type(endurance.tempoScale) ~= "function" then return 1 end
    return tonumber(endurance.tempoScale(shell)) or 1
end

function Combat.meleeTempo(shell, weapon)
    return Combat.meleeSwingScale(weapon) * Combat.tiredTempo(shell)
end

Combat.MELEE_TIMING = {
    oneHanded = { clipMs = 1000, blend = 0.8, delayMs = 400, lead = 0.25 },
    twoHanded = { clipMs = 1000, blend = 0.8, delayMs = 400, lead = 0.25 },
    knife = { clipMs = 1000, blend = 1, delayMs = 267, lead = 0.25 },
    spear = { clipMs = 1000, blend = 1, delayMs = 267, lead = 0.25 },
    heavy = { clipMs = 2500, blend = 1, delayMs = 400, lead = 0.25, speed = 1.2 },
    chainsaw = { clipMs = 1000, blend = 1, delayMs = 0, lead = 0.25 },
    unarmed = { clipMs = 1250, blend = 1, delayMs = 0, lead = 0.25, fixed = true },
    shove = { clipMs = 667, blend = 1, delayMs = 0, lead = 0.25, fixed = true },
    floor = { clipMs = 1000, blend = 1, delayMs = 0, lead = 0.35 },
}

Combat.MELEE_SPEED = { base = 0.8, roll = 1.15, minimum = 0.8, maximum = 1.6, staleMs = 6000 }

function Combat.vanillaMeleeClass(weapon)
    if weapon == nil or Combat.isUnarmed(weapon) then return "unarmed" end
    local anim = ""
    if type(weapon.getSwingAnim) == "function" then
        anim = string.lower(tostring(weapon:getSwingAnim() or ""))
    end
    if anim == "stab" then return "knife" end
    if anim == "heavy" then return "heavy" end
    if anim == "shove" then return "unarmed" end
    if type(weapon.isTwoHandWeapon) == "function" and weapon:isTwoHandWeapon() == true then
        if anim == "spear" then return "spear" end
        if type(weapon.getType) == "function" and tostring(weapon:getType()) == "Chainsaw" then
            return "chainsaw"
        end
        return "twoHanded"
    end
    return "oneHanded"
end

function Combat.meleeTiming(weapon, kind)
    local timing
    if kind ~= nil then timing = Combat.MELEE_TIMING[kind] end
    if timing == nil then
        timing = Combat.MELEE_TIMING[Combat.vanillaMeleeClass(weapon)] or Combat.MELEE_TIMING.oneHanded
    end
    local speed = 1
    if timing.fixed ~= true then
        local base = 1
        if weapon ~= nil and type(weapon.getBaseSpeed) == "function" then
            base = tonumber(weapon:getBaseSpeed()) or 1
        end
        if base <= 0 then base = 1 end
        local s = Combat.MELEE_SPEED
        speed = (s.base * base + (tonumber(Combat.settings.meleeSpeedBonus) or 0.16)) * s.roll
        speed = math.max(s.minimum, math.min(s.maximum, speed)) * (timing.speed or 1)
    end
    return timing, speed
end

function Combat.meleeCycleMs(shell, weapon, kind)
    local timing, speed = Combat.meleeTiming(weapon, kind)
    return math.floor((timing.clipMs / (speed * timing.blend) + timing.delayMs) * Combat.tiredTempo(shell))
end

function Combat.meleeLeadMs(shell, weapon, kind)
    local timing, speed = Combat.meleeTiming(weapon, kind)
    return math.floor(timing.clipMs * timing.lead / (speed * timing.blend) * Combat.tiredTempo(shell))
end

function Combat.meleeReadyAtMs(shell)
    local data = Combat.dataOf(shell)
    if data == nil then return nil end
    return tonumber(data.ProjectALifeMeleeReadyAtMs)
end

function Combat.meleeReady(shell, now)
    local readyAt = Combat.meleeReadyAtMs(shell)
    if readyAt == nil then return true end
    now = tonumber(now) or Combat.nowMs()
    return now >= readyAt or readyAt - now > Combat.MELEE_SPEED.staleMs
end

function Combat.noteMeleeStart(shell, weapon, now, kind)
    local data = Combat.dataOf(shell)
    if data == nil then return nil end
    local readyAt = (tonumber(now) or Combat.nowMs()) + Combat.meleeCycleMs(shell, weapon, kind)
    data.ProjectALifeMeleeReadyAtMs = readyAt
    return readyAt
end

function Combat.noteMeleeImpact(shell, weapon, now, kind)
    local data = Combat.dataOf(shell)
    if data == nil then return nil end
    local readyAt = (tonumber(now) or Combat.nowMs()) + Combat.meleeCycleMs(shell, weapon, kind)
        - Combat.meleeLeadMs(shell, weapon, kind)
    local held = tonumber(data.ProjectALifeMeleeReadyAtMs)
    if held == nil or readyAt > held then data.ProjectALifeMeleeReadyAtMs = readyAt end
    return data.ProjectALifeMeleeReadyAtMs
end

local function strengthScale(shell)
    local value
    if shell ~= nil and type(shell.getModData) == "function" then pcall(function()
        local data = shell:getModData()

        if type(data) == "table" then
            value = tonumber(data.ProjectALifeStrength)
        end
    end) end
    if value == nil then value = tonumber(Combat.variable(shell, "ALifeStrength")) end
    if value == nil then return 1 end
    return math.max(0.5, math.min(1.6, 0.6 + (value / 12.5)))
end

function Combat.meleeOutputScale(shell, maximumStrength)
    local fatigue = 1
    if shell ~= nil and type(shell.getModData) == "function" then
        local data = shell:getModData()
        if type(data) == "table" then
            local current = tonumber(data.ProjectALifeEndurance)
            local maximum = tonumber(data.ProjectALifeEnduranceMaximum)
            if current ~= nil and maximum ~= nil and maximum > 0 then
                fatigue = 0.5 + 0.5 * math.max(0, math.min(1, current / maximum))
            end
        end
    end
    local strength = strengthScale(shell)
    if tonumber(maximumStrength) ~= nil then strength = math.min(strength, maximumStrength) end
    return strength * fatigue
end

function Combat.playerWoundWeapon(shell, weapon)
    if shell == nil or weapon == nil or type(weapon.isAimedFirearm) ~= "function"
            or weapon:isAimedFirearm() or type(weapon.isRanged) ~= "function" or weapon:isRanged()
            or type(instanceItem) ~= "function"
            or type(weapon.getFullType) ~= "function" or type(weapon.getMinDamage) ~= "function"
            or type(weapon.getMaxDamage) ~= "function" then return weapon end
    local scale = Combat.meleeOutputScale(shell, 1)
    if math.abs(scale - 1) < 0.00001 then return weapon end
    local ok, view = pcall(function()
        if type(weapon.getUsingPlayer) ~= "function" or weapon:getUsingPlayer() ~= nil then return nil end
        local fullType = weapon:getFullType()
        if type(fullType) ~= "string" or fullType == "" then return nil end
        local item = instanceItem(fullType)
        if item == nil or item == weapon or type(item.getFullType) ~= "function"
                or item:getFullType() ~= fullType or type(item.setMinDamage) ~= "function"
                or type(item.setMaxDamage) ~= "function" or type(item.getMinDamage) ~= "function"
                or type(item.getMaxDamage) ~= "function" or type(item.getSharpnessMultiplier) ~= "function"
                or type(item.isAimedFirearm) ~= "function" or item:isAimedFirearm() then return nil end
        for _, method in ipairs({ "isRanged", "getSwingAnim", "getType", "isTwoHandWeapon" }) do
            if type(weapon[method]) == "function" and (type(item[method]) ~= "function"
                    or weapon[method](weapon) ~= item[method](item)) then return nil end
        end
        if WeaponCategory == nil or WeaponCategory.BLUNT == nil or WeaponCategory.SMALL_BLUNT == nil
                or type(weapon.isOfWeaponCategory) ~= "function"
                or type(item.isOfWeaponCategory) ~= "function" then return nil end
        for _, category in ipairs({ WeaponCategory.BLUNT, WeaponCategory.SMALL_BLUNT }) do
            if weapon:isOfWeaponCategory(category) ~= item:isOfWeaponCategory(category) then return nil end
        end
        local low, high = tonumber(weapon:getMinDamage()), tonumber(weapon:getMaxDamage())
        local multiplier = tonumber(item:getSharpnessMultiplier())
        if low == nil or high == nil or multiplier == nil or low ~= low or high ~= high
                or multiplier ~= multiplier or low < 0 or high < low or high > 1000
                or multiplier <= 0 or multiplier > 1 then return nil end
        low, high = low * scale, high * scale
        local view = item
        view:setMinDamage(low)
        view:setMaxDamage(low + (high - low) / multiplier)
        if math.abs(view:getMinDamage() - low) > 0.00001
                or math.abs(view:getMaxDamage() - high) > 0.00001 then return nil end
        return view
    end)
    if ok and view ~= nil then
        Combat.metrics.playerWoundViews = (Combat.metrics.playerWoundViews or 0) + 1
        return view
    end
    Combat.metrics.playerWoundViewsRefused = (Combat.metrics.playerWoundViewsRefused or 0) + 1
    return weapon
end

function Combat.woundAimScale(shell)
    local data = Combat.dataOf(shell)
    local scale = type(data) == "table" and tonumber(data.ProjectALifeArmAimScale) or nil
    local chill = type(data) == "table" and tonumber(data.ProjectALifeColdAim) or nil
    if scale == nil and chill == nil then return 1 end
    return math.max(0.4, math.min(1, (scale or 1) * (chill or 1)))
end

local HumanDamage = ProjectALife.HumanDamage or {}
ProjectALife.HumanDamage = HumanDamage
HumanDamage.metrics = HumanDamage.metrics or { blows = 0, kills = 0 }

function HumanDamage.isActor(target)
    if target == nil then return false end
    local ok, owned = pcall(function()
        local data = target:getModData()
        return type(data) == "table" and (data.ProjectALifeOwned == true
            or data.ProjectALifeActor == true)
    end)
    if ok and owned == true then return true end
    if target.GetVariable ~= nil then
        local marked, value = pcall(function() return target:GetVariable("ALifeActor") end)
        return marked and tostring(value) == "true"
    end
    return false
end

HumanDamage.ZONES = {
    { share = 7, zone = "head", scale = 3.6 },
    { share = 58, zone = "torso", scale = 1 },
    { share = 35, zone = "limb", scale = 0.6 },
}

function HumanDamage.zoneFor(roll)
    local rest = tonumber(roll) or 50
    for _, row in ipairs(HumanDamage.ZONES) do
        if rest < row.share then return row.zone, row.scale end
        rest = rest - row.share
    end
    return "torso", 1
end

HumanDamage.pointsPerDamage = 8

function HumanDamage.blowWeight(weapon)
    local top = 1
    pcall(function() top = math.max(0.1, tonumber(weapon:getMaxDamage()) or top) end)
    local draw = 0.5
    if type(ZombRand) == "function" then
        draw = (ZombRand(1001) + ZombRand(1001)) / 2000
    end
    return top * HumanDamage.pointsPerDamage * (0.75 + 0.5 * draw)
end

function HumanDamage.meleeWeight(weapon)
    local s = Combat.settings or {}
    local top = 1
    pcall(function() top = math.max(0.1, tonumber(weapon:getMaxDamage()) or top) end)
    local base = (tonumber(s.humanMeleeBase) or 9) * top ^ (tonumber(s.humanMeleeExponent) or 0.5)
    local cap = Combat.isHeavyMelee(weapon) and (tonumber(s.humanMeleeHeavyCap) or 20)
        or (tonumber(s.humanMeleeCap) or 10.5)
    local draw = 0.5
    if type(ZombRand) == "function" then
        draw = (ZombRand(1001) + ZombRand(1001)) / 2000
    end
    return math.min(base, cap) * (0.75 + 0.5 * draw)
end

function HumanDamage.meleeZoneFor(roll)
    local s = Combat.settings or {}
    if (tonumber(roll) or 100) < (tonumber(s.humanMeleeHeadPercent) or 10) then
        return "head", tonumber(s.humanMeleeHeadScale) or 1.8
    end
    return "body", 1
end

function HumanDamage.points(weapon, scale)
    local zone, zoneScale = "body", 1
    local points
    if Combat.isRanged(weapon) then
        zone, zoneScale = HumanDamage.zoneFor(type(ZombRand) == "function" and ZombRand(100) or 50)
        points = HumanDamage.blowWeight(weapon) * zoneScale
    else
        zone, zoneScale = HumanDamage.meleeZoneFor(type(ZombRand) == "function" and ZombRand(100) or 50)
        points = HumanDamage.meleeWeight(weapon) * zoneScale
    end

    points = points * math.max(0.5, math.min(1.6, tonumber(scale) or 1))
    return math.max(0.5, math.min(75, points)), zone
end

function HumanDamage.scaled(points, output, reduction)
    local value = (tonumber(points) or 0)
        * (math.max(1, math.min(500, tonumber(output) or 100)) / 100)
        * (1 - math.max(0, math.min(90, tonumber(reduction) or 0)) / 100)
    return math.max(0.5, math.min(75, value))
end

local function combatScalar(shell, key, fallback)
    local value
    pcall(function()
        local data = shell:getModData()
        value = type(data) == "table" and tonumber(data[key]) or nil
    end)
    return value or fallback
end

function HumanDamage.outputOf(shell)
    if shell == nil then return 100 end
    return combatScalar(shell, "ProjectALifeDamageOutput", 100)
end

function HumanDamage.reductionOf(shell)
    if shell == nil then return 0 end
    return combatScalar(shell, "ProjectALifeDamageReduction", 0)
end

function HumanDamage.shielded(target, zone, weapon)
    local armor = ProjectALife.Armor
    if armor == nil or type(armor.blocksWeapon) ~= "function" then return false end
    local ok, blocked = pcall(armor.blocksWeapon, target, zone, weapon)
    return ok and blocked == true
end

function HumanDamage.deflect(attacker, target, weapon, health, zone)
    HumanDamage.metrics.deflected = (HumanDamage.metrics.deflected or 0) + 1
    pcall(function()
        target:getModData().ProjectALifeLastHitAtMs = Combat.nowMs()
    end)
    pcall(function()
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and type(healthSystem.onDamage) == "function" then
            local maximum = ProjectALife.ShellSimulation.maximumFor(target)
            healthSystem.onDamage(attacker, target, zone, health, maximum, nil, nil, weapon, true)
        end
    end)
    return true, 0, zone, "blocked"
end

function HumanDamage.apply(attacker, target, weapon, scale)
    if not HumanDamage.isActor(target) then return false, "target_not_actor" end
    local healthSystem = ProjectALife.Health
    if healthSystem ~= nil and type(healthSystem.invulnerable) == "function"
            and healthSystem.invulnerable(target) then
        healthSystem.pin(target)
        return true, 0, "invulnerable"
    end

    local ok, health = pcall(function()
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil and type(simulation.trueHealth) == "function" then
            return simulation.trueHealth(target)
        end
        return target:getHealth()
    end)
    health = ok and tonumber(health) or nil
    if health == nil or health <= 0 then return false, "target_dead" end
    local damage, zone = HumanDamage.points(weapon, scale)
    damage = HumanDamage.scaled(damage,
        HumanDamage.outputOf(attacker), HumanDamage.reductionOf(target))

    if HumanDamage.shielded(target, zone, weapon) then
        return HumanDamage.deflect(attacker, target, weapon, health, zone)
    end

    local simulation = ProjectALife.ShellSimulation
    local healthScale = tonumber(target:getModData().ProjectALifeHealthScale)
    if healthScale == nil and simulation ~= nil and type(simulation.healthScale) == "function" then
        healthScale = tonumber(simulation.healthScale())
    end
    healthScale = healthScale or 1
    local taken = 1
    local tuned = ProjectALife.NpcHealth
    if tuned ~= nil and type(tuned.takenBy) == "function" then
        local ok, value = pcall(tuned.takenBy, Combat.isRanged(weapon))
        if ok and tonumber(value) ~= nil then taken = tonumber(value) end
    end
    local remaining = math.max(0, health - damage * healthScale * taken)

    HumanDamage.metrics = HumanDamage.metrics or {}
    HumanDamage.metrics.blows = (HumanDamage.metrics.blows or 0) + 1
    HumanDamage.metrics.lastDamage = damage
    HumanDamage.metrics.lastScale = healthScale
    HumanDamage.metrics.lastHealth = health
    HumanDamage.metrics.lastRemaining = remaining
    if remaining <= 0 then
        HumanDamage.metrics.kills = (HumanDamage.metrics.kills or 0) + 1
    end

    pcall(function()
        local relations, registry = ProjectALife.Relations, ProjectALife.ActorRegistry
        if relations == nil or registry == nil or attacker == nil then return end
        local shooter = registry.read(tostring(attacker:getModData().ProjectALifeUID or ""))
        local victim = registry.read(tostring(target:getModData().ProjectALifeUID or ""))
        if shooter == nil or victim == nil or relations.hostile(shooter, victim) == true then return end
        local voice = ProjectALife.Voice
        if voice ~= nil then voice.play(target, "FRIENDLY_FIRE") end
    end)
    if not pcall(function()
        if ProjectALife.ShellSimulation then ProjectALife.ShellSimulation.setHealth(target, remaining)
        else target:setHealth(remaining) end
    end) then
        return false, "health_write_failed"
    end
    pcall(function()
        local data = target:getModData()
        data.ProjectALifeLastHumanDamage = damage
        data.ProjectALifeLastHumanHitZone = zone
        data.ProjectALifeLastHealth = remaining

        data.ProjectALifeLastHitAtMs = Combat.nowMs()
    end)

    pcall(function()
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and remaining > 0 then
            local maximum = ProjectALife.ShellSimulation.maximumFor(target)
            healthSystem.onDamage(attacker, target, zone, remaining, maximum, nil, nil, weapon)
        end
    end)
    Interop.hit(target, attacker, health - remaining)
    if remaining <= 0 then pcall(function() target:Kill(attacker) end) end
    return true, damage, zone
end

function Combat.hitBand(damage, zone, headRoll)
    local s = Combat.settings
    damage = tonumber(damage) or 0
    if damage >= (tonumber(s.knockdownDamage) or 30) then return "knockdown" end
    if zone == "head" and (tonumber(headRoll) or 100) < (tonumber(s.headKnockdownPercent) or 35) then return "knockdown" end
    if damage >= (tonumber(s.staggerDamage) or 12) or zone == "limb" then return "stagger" end
    return "flinch"
end

function Combat.hitReactionPlan(band, data, now, rangedHit, flinchRoll, jitter)
    local s = Combat.settings
    data = type(data) == "table" and data or {}
    now = tonumber(now) or 0
    local stamps = {}
    if band == "knockdown" then
        if now < (tonumber(data.ProjectALifeNextKnockdownAtMs) or 0) then
            band = "stagger"
        else
            local rest = (tonumber(s.downedGetUpMinMs) or 1400)
                + math.floor((tonumber(s.downedGetUpJitterMs) or 800) * math.max(0, math.min(1, tonumber(jitter) or 0.5)))
            stamps.ProjectALifeDownedUntilMs = now + rest
            stamps.ProjectALifeNextKnockdownAtMs = now + (tonumber(s.knockdownCooldownMs) or 6000)
            stamps.ProjectALifeNextStaggerAtMs = now + (tonumber(s.staggerCooldownMs) or 2500)
            stamps.ProjectALifeStaggerUntilMs = now + rest
            return "knockdown", stamps
        end
    end
    if band == "stagger" then
        if now < (tonumber(data.ProjectALifeNextStaggerAtMs) or 0) then
            band = "flinch"
        else
            stamps.ProjectALifeNextStaggerAtMs = now + (tonumber(s.staggerCooldownMs) or 2500)
            stamps.ProjectALifeStaggerUntilMs = now + (tonumber(s.staggerMs) or 800)
            return "stagger", stamps
        end
    end
    if now < (tonumber(data.ProjectALifeNextHitReactionAtMs) or 0) then return nil, stamps end
    local percent = math.max(0, math.min(100, tonumber(s.hitReactionPercent) or 65))
    if percent <= 0 or (percent < 100 and (tonumber(flinchRoll) or 0) >= percent) then return nil, stamps end
    stamps.ProjectALifeNextHitReactionAtMs = now
        + (rangedHit and (tonumber(s.rangedHitReactionCooldownMs) or 1800) or (tonumber(s.hitReactionCooldownMs) or 900))
    stamps.ProjectALifeStaggerUntilMs = now + (tonumber(s.hitReactionMs) or 450)
    return "flinch", stamps
end

function Combat.presentHumanHit(target, attacker, damage, zone, rangedHit, now)
    if target == nil or Combat.targetIsDown(target) then return nil end
    if ProjectALife.PersonalRep ~= nil and type(ProjectALife.PersonalRep.noteEngaged) == "function" then
        pcall(ProjectALife.PersonalRep.noteEngaged, attacker, target)
    end
    local data
    pcall(function() data = target:getModData() end)
    if type(data) ~= "table" then return nil end
    local headRoll = type(ZombRand) == "function" and ZombRand(100) or 100
    local flinchRoll = type(ZombRand) == "function" and ZombRand(100) or 0
    local jitter = type(ZombRand) == "function" and (ZombRand(1000) / 1000) or 0.5
    local band = Combat.hitBand(damage, zone, headRoll)
    local action, stamps = Combat.hitReactionPlan(band, data, now, rangedHit, flinchRoll, jitter)
    for key, value in pairs(stamps) do data[key] = value end
    if action == nil then return nil end
    local behind = false
    pcall(function() behind = attacker ~= nil and attacker:isBehind(target) == true end)
    pcall(function() target:setHitFromBehind(behind) end)

    if action == "flinch" or action == "stagger" then
        local current = Animations.current[target]
        if current ~= "hit_react" then Animations.apply(target, "hit_react") end
    elseif action == "knockdown" then
        pcall(function()

            target:setKnockedDown(true)
            target:setFallOnFront(not behind)
        end)
    end

    local reactions = ProjectALife.HumanReactions
    if reactions ~= nil then
        local uid
        pcall(function() uid = data.ProjectALifeUID end)
        reactions.pain(target, uid or tostring(target), now)
    end
    return action
end

function Combat.secondInArc(shell, target, weapon)
    local found, best = nil, math.huge
    pcall(function()
        local reach = Combat.meleeReach(weapon) + 0.3
        local sx, sy, sz = shell:getX(), shell:getY(), math.floor(shell:getZ())
        local tx, ty = target:getX() - sx, target:getY() - sy
        local length = math.sqrt(tx * tx + ty * ty)
        if length < 0.001 then return end
        tx, ty = tx / length, ty / length
        local cell = getCell()
        if cell == nil then return end
        for dx = -2, 2 do
            for dy = -2, 2 do
                local square = cell:getGridSquare(math.floor(sx) + dx, math.floor(sy) + dy, sz)
                local moving = square ~= nil and square:getMovingObjects() or nil
                for index = 0, (moving ~= nil and moving:size() or 0) - 1 do
                    local body = moving:get(index)
                    if body ~= nil and body ~= shell and body ~= target and instanceof(body, "IsoZombie")
                            and type(body.isDead) == "function" and body:isDead() ~= true
                            and not TargetPolicy.grappledCorpse(body) then
                        local data = body:getModData()
                        local person = type(data) == "table" and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)

                        if not person and not Combat.comradeBody(shell, body) then
                            local bx, by = body:getX() - sx, body:getY() - sy
                            local d = math.sqrt(bx * bx + by * by)
                            if d <= reach and d > 0.001 and (bx * tx + by * ty) / d >= 0.342 and d < best then
                                found, best = body, d
                            end
                        end
                    end
                end
            end
        end
    end)
    return found
end

function Combat.penetrationSecond(shell, target)
    local lineOfFire = ProjectALife.LineOfFire
    local second = lineOfFire ~= nil and type(lineOfFire.bodyBeyond) == "function"
        and lineOfFire.bodyBeyond(shell, target, tonumber(Combat.settings.penetrationSquares) or 3) or nil
    if second ~= nil and Combat.comradeBody(shell, second) then
        Combat.metrics.friendlyRefused = (Combat.metrics.friendlyRefused or 0) + 1
        return nil
    end
    return second
end

function Combat.blowGeometry(attacker, victim)
    local behind, side = false, "L"
    pcall(function()
        local forward = victim:getForwardDirection()
        local fx, fy = forward:getX(), forward:getY()
        local dx, dy = attacker:getX() - victim:getX(), attacker:getY() - victim:getY()
        behind = fx * dx + fy * dy < 0
        if fx * dy - fy * dx > 0 then side = "R" end
    end)
    return behind, side
end

function Combat.shotReaction(shell, zombie, roll)
    local _, side = Combat.blowGeometry(shell, zombie)
    local r = tonumber(roll) or (type(ZombRand) == "function" and ZombRand(100) or 0)
    if r < 50 then return "ShotChest" .. side end
    if r < 80 then return "ShotShoulder" .. side end
    return "ShotLeg" .. side
end

Combat.zombieWoundScale = 0.8

Combat.MELEE_WOUND = {
    weaponBase = 0.3, levelStep = 0.1, received = 1.5, global = 0.15, split = 2,
    floor = 5, crit = 2, escalateFrom = 4, escalateStep = 1.5,
    offFront = 0.3, offFrontScale = 1.5, rangeFloor = 0.3, rangeCap = 2,
}

function Combat.woundRange(weapon)
    local low, high = 0.05, 1
    if weapon ~= nil then
        if type(weapon.getMaxDamage) == "function" then
            high = tonumber(weapon:getMaxDamage()) or high
        end
        if type(weapon.getMinDamage) == "function" then
            low = tonumber(weapon:getMinDamage()) or low
        end
    end
    high = math.max(0.05, high)
    low = math.max(0.05, math.min(high, low))
    return low, high
end

function Combat.woundRoll()
    local fraction = 0.5
    if type(ZombRandFloat) == "function" then
        fraction = tonumber(ZombRandFloat(0, 1)) or fraction
    elseif type(ZombRand) == "function" then
        fraction = (tonumber(ZombRand(10001)) or 5000) / 10000
    end
    return math.max(0, math.min(1, fraction))
end

function Combat.meleeLevel()
    return math.floor(math.max(0, math.min(10, tonumber(Combat.settings.meleeSkillLevel) or 2)))
end

function Combat.meleeStrength(shell)
    local data = Combat.dataOf(shell)
    local value
    if data ~= nil then value = tonumber(data.ProjectALifeStrength) end
    if value == nil then value = tonumber(Combat.variable(shell, "ALifeStrength")) end
    return value
end

function Combat.meleeHitting(shell)
    local strength = Combat.meleeStrength(shell)
    if strength == nil then return 1 end
    return 0.75 + 0.05 * math.floor(math.max(0, math.min(10, strength)))
end

function Combat.meleeFatigue(shell)
    local data = Combat.dataOf(shell)
    if data == nil then return 1 end
    local current = tonumber(data.ProjectALifeEndurance)
    local maximum = tonumber(data.ProjectALifeEnduranceMaximum)
    if current == nil or maximum == nil or maximum <= 0 then return 1 end
    return 0.5 + 0.5 * math.max(0, math.min(1, current / maximum))
end

function Combat.meleeSkillDamage(weapon, level)
    if level < 3 or weapon == nil or type(weapon.isOfWeaponCategory) ~= "function"
            or WeaponCategory == nil then return 1 end
    for _, category in ipairs({ WeaponCategory.BLUNT, WeaponCategory.AXE, WeaponCategory.SPEAR }) do
        if category ~= nil and weapon:isOfWeaponCategory(category) == true then
            return level >= 7 and 1.2 or 1.1
        end
    end
    return 1
end

function Combat.meleeCritChance(weapon, level)
    local chance = 20
    if weapon ~= nil and type(weapon.getCriticalChance) == "function" then
        chance = tonumber(weapon:getCriticalChance()) or chance
    end
    return math.max(10, math.min(90, chance - chance / 5 + level * 3))
end

function Combat.meleeCritScale(weapon)
    local scale = Combat.MELEE_WOUND.crit
    if weapon ~= nil and type(weapon.getCriticalDamageMultiplier) == "function" then
        scale = tonumber(weapon:getCriticalDamageMultiplier()) or scale
    end
    return math.max(Combat.MELEE_WOUND.crit, scale)
end

function Combat.meleeCritRoll(weapon, level)
    if type(ZombRand) ~= "function" then return false end
    return (tonumber(ZombRand(100)) or 0) >= 100 - Combat.meleeCritChance(weapon, level)
end

function Combat.meleeRangeScale(shell, zombie, weapon)
    local sx, sy = Combat.xyOf(shell)
    local tx, ty = Combat.xyOf(zombie)
    local reach = Combat.meleeReach(weapon)
    if sx == nil or tx == nil or reach == nil or reach <= 0 then return 1 end
    local scale = math.sqrt((sx - tx) ^ 2 + (sy - ty) ^ 2) / reach * 2
    if scale < Combat.MELEE_WOUND.rangeFloor then return 1 end
    return math.min(Combat.MELEE_WOUND.rangeCap, scale)
end

function Combat.offFront(attacker, victim)
    if victim == nil or type(victim.getForwardDirection) ~= "function" then return false end
    local ax, ay = Combat.xyOf(attacker)
    local vx, vy = Combat.xyOf(victim)
    local forward = victim:getForwardDirection()
    if ax == nil or vx == nil or forward == nil or type(forward.getX) ~= "function"
            or type(forward.getY) ~= "function" then return false end
    local fx, fy = tonumber(forward:getX()) or 0, tonumber(forward:getY()) or 0
    local dx, dy = ax - vx, ay - vy
    local length = math.sqrt(dx * dx + dy * dy) * math.sqrt(fx * fx + fy * fy)
    if length < 0.0001 then return false end
    return (fx * dx + fy * dy) / length < Combat.MELEE_WOUND.offFront
end

function Combat.zombieHitCount(zombie)
    if zombie == nil or type(zombie.getHitTime) ~= "function" then return 0 end
    return tonumber(zombie:getHitTime()) or 0
end

function Combat.meleeZombieWound(shell, zombie, weapon, share)
    local w = Combat.MELEE_WOUND
    local level = Combat.meleeLevel()
    local low, high = Combat.woundRange(weapon)
    local damage = (low + (high - low) * Combat.woundRoll()) * Combat.meleeHitting(shell)
        * Combat.meleeSkillDamage(weapon, level) * w.split * Combat.meleeRangeScale(shell, zombie, weapon)
    local count = Combat.zombieHitCount(zombie) + 1
    if count >= w.escalateFrom then damage = damage * (count - 2) * w.escalateStep end
    if Combat.offFront(shell, zombie) then damage = damage * w.offFrontScale end
    damage = damage * w.received * (w.weaponBase + w.levelStep * level)
    local critScale = Combat.meleeCritScale(weapon)
    if Combat.targetIsDown(zombie) then damage = damage * math.max(w.floor, critScale) end
    local crit = Combat.meleeCritRoll(weapon, level)
    if crit then damage = damage * critScale end
    return damage * w.global * Combat.meleeFatigue(shell) * (tonumber(share) or 1), crit
end

function Combat.zombieWound(shell, zombie, weapon, share)
    if not Combat.isRanged(weapon) then
        return Combat.meleeZombieWound(shell, zombie, weapon, share)
    end
    local low, high = Combat.woundRange(weapon)
    return (low + (high - low) * Combat.woundRoll()) * Combat.zombieWoundScale
        * Combat.downedBonus(zombie) * (tonumber(share) or 1)
end

function Combat.critKnockdown(zombie)
    if zombie == nil or Combat.targetIsDown(zombie) or Combat.peekKind(zombie) ~= "zombie"
            or type(zombie.setKnockedDown) ~= "function" then return false end
    zombie:setKnockedDown(true)
    Combat.metrics.critKnockdowns = (Combat.metrics.critKnockdowns or 0) + 1
    return true
end

function Combat.dressForDeath(zombie)
    if type(isClient) ~= "function" or not isClient() or zombie == nil then return false end
    if zombie.getWornItems == nil or zombie.getItemVisuals == nil then return false end
    local worn = zombie:getWornItems()
    local visuals = zombie:getItemVisuals()
    if worn == nil or visuals == nil or type(worn.setFromItemVisuals) ~= "function"
            or type(worn.size) ~= "function" or worn:size() > 0 then return false end
    return pcall(worn.setFromItemVisuals, worn, visuals)
end

function Combat.strikeZombie(shell, zombie, weapon, reaction, share)
    if TargetPolicy.grappledCorpse(zombie) then return false end
    if not Combat.isRanged(weapon) then
        local geometry = ProjectALife.LineOfFire
        if type(geometry) ~= "table" or type(geometry.hasClearBoundary) ~= "function" then return false end
        local checked, clear = pcall(geometry.hasClearBoundary, shell, zombie, "melee")
        if not checked or clear ~= true then return false end
    end
    local health
    pcall(function() health = tonumber(zombie:getHealth()) end)
    if health == nil or health <= 0 then return false end
    local behind = Combat.blowGeometry(shell, zombie)
    local wound, crit = Combat.zombieWound(shell, zombie, weapon, share)
    local remaining = health - wound
    if not pcall(function() zombie:setHealth(math.max(0, remaining)) end) then return false end
    if not Combat.isRanged(weapon) and type(zombie.setHitTime) == "function" then
        zombie:setHitTime(Combat.zombieHitCount(zombie) + 1)
    end
    if remaining <= 0 then
        Combat.dressForDeath(zombie)
        if not pcall(function() zombie:Kill(shell) end) then
            pcall(function() zombie:Kill(nil) end)
        end
        return true
    end
    if not Combat.isRanged(weapon) and not Combat.targetIsDown(zombie) then
        pcall(function()
            local horde = ProjectALife.HordeRelations
            if horde ~= nil and type(horde.stun) == "function" then horde.stun(zombie, shell) end
        end)
    end
    local clip = reaction
    if Combat.targetIsDown(zombie) then
        clip = type(clip) == "string" and clip ~= "" and "Floor" or nil
    elseif clip == "Floor" then
        clip = nil
    elseif clip == "Shot" then
        clip = Combat.shotReaction(shell, zombie)
    end
    if type(clip) == "string" and clip ~= "" then
        pcall(function() zombie:setHitFromBehind(behind) end)
        pcall(function() zombie:setHitReaction(clip) end)
    end
    if crit == true then Combat.critKnockdown(zombie) end
    return true
end

local function applyDamage(shell, target, weapon, reaction)
    if type(Combat.adapters.applyDamage) == "function" then
        return Combat.adapters.applyDamage(shell, target, weapon) == true
    end

    if HumanDamage.isActor(target) then

        if type(isClient) == "function" and isClient() then
            return ProjectALife.NPCHitRelay.request(shell, target, weapon)
        end

        local attackScale = (Combat.isRanged(weapon) and 1 or strengthScale(shell)) * Combat.downedBonus(target)
        pcall(function()
            local stealthSystem = ProjectALife.Stealth
            if stealthSystem ~= nil then
                attackScale = attackScale * stealthSystem.backstabScaleFor(
                    shell, target, shell:getModData())
            end
        end)
        local applied, damage, zone, outcome = HumanDamage.apply(shell, target, weapon, attackScale)
        if applied then
            Combat.metrics.actorHits = (Combat.metrics.actorHits or 0) + 1
            pcall(function()
                local data = target:getModData()
                local perception = ProjectALife.Perception
                if perception ~= nil and type(perception.noteAttacker) == "function"
                        and type(data.ProjectALifeUID) == "string" then
                    perception.noteAttacker(data.ProjectALifeUID, shell, 5000, "actor")
                end

                local deflected = outcome == "blocked"
                Combat.presentHumanHit(target, shell, damage, deflected and "body" or zone,
                    Combat.isRanged(weapon), Combat.nowMs())
                if not deflected then
                    Voice.play(target, "HURT", { urgent = true, textEnabled = false,
                        context = { attack = ProjectALife.Wounds.weaponKind(weapon) } })
                end
            end)
        end
        return applied == true
    end
    local isZombieBody = false
    pcall(function() isZombieBody = target:isZombie() == true end)
    if isZombieBody then

        pcall(function()
            local data = target:getModData()
            if type(data) == "table" and (data.ProjectALifeOwned == true
                    or data.ProjectALifeActor == true) then
                data.ProjectALifeBiteUntilMs = Combat.nowMs() + 400
                target:setZombiesDontAttack(false)
            end
        end)
        local struck = Combat.strikeZombie(shell, target, weapon, reaction, 1)
        Combat.metrics.zombieStrikes = (Combat.metrics.zombieStrikes or 0) + 1
        if not struck then return false end
        Combat.metrics.zombieStruck = (Combat.metrics.zombieStruck or 0) + 1

        if struck and Combat.settings.multiHit == true then
            local twoHanded = false
            pcall(function() twoHanded = weapon:isTwoHandWeapon() == true end)
            local second = twoHanded and Combat.secondInArc(shell, target, weapon) or nil
            if second ~= nil then
                Combat.multiHits = (Combat.multiHits or 0) + 1
                Combat.strikeZombie(shell, second, weapon, reaction, 0.5)
            end
        end

        pcall(function()
            local horde = ProjectALife.HordeRelations
            if horde ~= nil and type(horde.provoke) == "function" then
                horde.provoke(target, shell)
            end
        end)
        return true
    end

    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.relayPlayerHit) == "function"
            and type(executor.clientAuthority) == "function" and executor.clientAuthority() then
        local registry, uid = ProjectALife.ActorRegistry, nil
        pcall(function() uid = shell:getModData().ProjectALifeUID end)
        local actor = registry ~= nil and type(uid) == "string" and registry.read(uid) or nil

        if type(actor) ~= "table" then
            Combat.metrics.playerHitFailures = (Combat.metrics.playerHitFailures or 0) + 1
            Combat.metrics.lastPlayerHitError = "relay_no_record"
            return false
        end
        local weaponType
        pcall(function() weaponType = tostring(weapon:getFullType()) end)
        if executor.relayPlayerHit(actor, target, weaponType) then
            Combat.metrics.playerHits = (Combat.metrics.playerHits or 0) + 1

            return true
        end
        Combat.metrics.playerHitFailures = (Combat.metrics.playerHitFailures or 0) + 1
        Combat.metrics.lastPlayerHitError = "relay_unavailable"
        return false
    end
    local bodyOk, bodyDamage = pcall(function() return target:getBodyDamage() end)
    if bodyOk and bodyDamage ~= nil then

        local woundWeapon = Combat.playerWoundWeapon(shell, weapon)
        local part = Combat.hitPartIndex(math.sqrt(Combat.distanceSquared(shell, target)))
        local damaged, damageError = ProjectALife.Wounds.damagePlayer(bodyDamage, woundWeapon, part)
        if not damaged and type(bodyDamage.AddDamage) == "function"
                and type(woundWeapon.getMaxDamage) == "function" then
            damaged, damageError = pcall(function()
                local power = tonumber(woundWeapon:getMaxDamage()) or 1
                bodyDamage:AddDamage(BodyPartType.Torso_Upper, power * 8)
            end)
        end
        if damaged then
            local relations = ProjectALife.Relations
            if relations ~= nil and type(relations.noteAggression) == "function" then
                relations.noteAggression(shell, target)
            end
            Combat.metrics.playerHits = (Combat.metrics.playerHits or 0) + 1
        else
            Combat.metrics.playerHitFailures = (Combat.metrics.playerHitFailures or 0) + 1
            Combat.metrics.lastPlayerHitError = tostring(damageError)
        end
        if damaged then
            pcall(function()
                local female = target:isFemale() == true
                ProjectALife.AudioPolicy.playFrom(target, female and "VoiceFemalePainFromHitBlunt"
                    or "VoiceMalePainFromHitBlunt")
            end)
            if type(isServer) == "function" and isServer()
                    and type(sendDamage) == "function" then
                pcall(sendDamage, target)
            end
            return true
        end
    end
    return false
end

local function playSoundFrom(source, sound)
    if type(sound) ~= "string" or sound == "" then return end
    local dedicated = type(isServer) == "function" and isServer()
    if dedicated and type(sendPlaySound) == "function" then
        pcall(sendPlaySound, sound, false, source)
    else
        pcall(function() source:playSound(sound) end)
    end
end

Combat.MELEE_GRUNT = {
    oneHanded = "MeleeAttack", twoHanded = "MeleeAttack", spear = "MeleeAttack",
    unarmed = "MeleeAttack", heavy = "MeleeAttackHeavy", knife = "MeleeStab",
    stomp = "MeleeStomp", floorStab = "MeleeStabOnGround",
}

function Combat.meleeAudio(moment, shell, target, weapon, class)
    if weapon == nil then return end
    if moment == "swing" then
        local ok, swing = pcall(function() return weapon:getSwingSound() end)
        if ok then playSoundFrom(shell, swing) end
        local grunt = class ~= nil and Combat.MELEE_GRUNT[class] or nil
        if grunt == nil or not ProjectALife.AudioPolicy.allowsNPC() then return end
        local female = false
        pcall(function() female = shell:isFemale() == true end)
        playSoundFrom(shell, (female and "VoiceFemale" or "VoiceMale") .. grunt)
        return
    end
    if target == nil then return end
    local zombieBody = false
    pcall(function() zombieBody = target:isZombie() == true end)
    local impact
    if not zombieBody then
        local female = false
        pcall(function() female = target:isFemale() == true end)
        local pain = female and "VoiceFemalePainFromHitBlunt" or "VoiceMalePainFromHitBlunt"
        local isPlayer = false
        pcall(function() isPlayer = instanceof(target, "IsoPlayer") == true end)
        if isPlayer then
            playSoundFrom(target, pain)
        else
            pcall(ProjectALife.AudioPolicy.nearSound, target, pain, { key = target })
        end
    end

    if type(weapon.getZombieHitSound) == "function" then
        local ok, sound = pcall(weapon.getZombieHitSound, weapon)
        if ok then impact = sound end
    end
    playSoundFrom(target, impact)
end

function Combat.attackRefused(reason)
    local ledger = Combat.metrics.attackRefusedBy
    if type(ledger) ~= "table" then
        ledger = {}
        Combat.metrics.attackRefusedBy = ledger
    end
    ledger[reason] = (ledger[reason] or 0) + 1
    return false
end

function Combat.strikeRefusal(actor, shell, target, now)
    local fair = ProjectALife.Fairness
    if fair == nil or type(fair.strikeRefusal) ~= "function" then return nil end
    return fair.strikeRefusal(actor, shell, target, now or Combat.nowMs())
end

function Combat.strikeHeld(actor, shell, target, now)
    return Combat.strikeRefusal(actor, shell, target, now) ~= nil
end

function Combat.offLimits(actor, target)
    local fair = ProjectALife.Fairness
    return fair ~= nil and type(fair.offLimits) == "function" and fair.offLimits(actor, target, Combat.nowMs()) == true
end

function Combat.noteSighting(actor, shell, target)
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.noteSight) == "function" then fair.noteSight(actor, shell, target, Combat.nowMs()) end
end

function Combat.noteThreatShot(chance, hit)
    local metrics = Combat.metrics
    metrics.playerShots = (metrics.playerShots or 0) + 1
    metrics.playerShotChance = (metrics.playerShotChance or 0) + math.floor(chance / 100)
    if hit == true then metrics.playerShotsRolledHit = (metrics.playerShotsRolledHit or 0) + 1 end
end

local function resolveAttack(actor, shell, target, shove, reaction, shoveFloor)
    Combat.metrics.attackTries = (Combat.metrics.attackTries or 0) + 1
    if not ProjectALife.NPCHitRelay.ready(shell) then return Combat.attackRefused("relay") end
    ProjectALife.NPCHitRelay.beginAttack(shell)
    if type(Combat.adapters.attack) == "function" then
        local hit = Combat.adapters.attack(shell, target) == true
        if hit then Endurance.consumeAttack(actor, shell, Combat.nowMs()) end
        return hit
    end
    if not TargetPolicy.canAttack(target) then return Combat.attackRefused("policy") end
    local unfair = Combat.strikeRefusal(actor, shell, target, Combat.nowMs())
    if unfair ~= nil then return Combat.attackRefused(unfair) end

    if Combat.attackIncapacitated(shell) then return Combat.attackRefused("incapacitated") end

    local suppressing = false
    if type(shell.getModData) == "function" then
        pcall(function()
            local data = shell:getModData()
            suppressing = type(data) == "table" and data.ProjectALifeSuppressTracking == true
                and (tonumber(data.ProjectALifeSuppressUntilMs) or 0) > Combat.nowMs()
        end)
    end
    if suppressing then return Combat.attackRefused("gunner") end
    local weapon = Combat.weaponFor(shell)
    if weapon == nil then return Combat.attackRefused("no_weapon") end

    if (shove == true or not Combat.isRanged(weapon))
            and ProjectALife.VehicleRules ~= nil
            and ProjectALife.VehicleRules.meleeBlocked(target) then
        return Combat.attackRefused("vehicle")
    end

    if Combat.isRanged(weapon) and shove ~= true
            and not Combat.muzzleOnTarget(shell, target) then
        Combat.faceTarget(shell, target)
        return Combat.attackRefused("muzzle")
    end

    local paced = true
    pcall(function()
        local data = shell:getModData()
        if type(data) == "table" then
            local nextAt = tonumber(data.ProjectALifeNextStrikeAtMs) or 0
            paced = Combat.nowMs() >= nextAt
            if paced then
                local interval = Weapons.isAutomatic(weapon)
                    and Weapons.fireIntervalMs(weapon) or 450

                if data.ProjectALifeConduct == "sniper" then
                    interval = interval * 2.4
                end
                data.ProjectALifeNextStrikeAtMs = Combat.nowMs() + interval
            end
        end
    end)
    if not paced then return Combat.attackRefused("cadence") end
    local ranged = Combat.isRanged(weapon)

    local maximum = (ranged and shove ~= true) and Combat.maximumRange(weapon, shell)
        or Combat.meleeReachFor(weapon, target)

    if ranged and shove ~= true then
        pcall(function()
            local at = tonumber(shell:getModData().ProjectALifeInRangeAtMs)
            if at ~= nil and Combat.nowMs() - at < 2000 then maximum = maximum * 1.3 end
        end)

        maximum = Combat.capForPlayer(maximum, shell, target)
    end
    if Combat.distanceSquared(shell, target) > maximum * maximum
            or not Combat.clearAttackLine(shell, target, weapon, shove == true) then
        return Combat.attackRefused("reach")
    end

    if ranged and shove ~= true then
        local held = false

        local disciplineEnabled = false
        pcall(function()
            local data = shell:getModData()

            local pinnedUntil = tonumber(data.ProjectALifePinnedUntilMs)
            if pinnedUntil ~= nil then
                if Combat.nowMs() < pinnedUntil then held = true return end
                data.ProjectALifePinnedUntilMs = nil
            end
            if not disciplineEnabled then return end

            if data.ProjectALifeHealDoneAtMs ~= nil then held = true return end
            local holdUntil = tonumber(data.ProjectALifeHoldFireUntilMs)

            if holdUntil ~= nil and Combat.kindOf(target) == "zombie" then
                holdUntil = nil
            end
            if holdUntil ~= nil and Combat.nowMs() < holdUntil then

                local hitAt = tonumber(data.ProjectALifeLastHitAtMs)
                held = hitAt == nil or Combat.nowMs() - hitAt > 4000
                if not held then data.ProjectALifeHoldFireUntilMs = nil end
            end
        end)
        if held then return Combat.attackRefused("held") end
    end

    if ranged and shove ~= true and ProjectALife.GunDiscipline ~= nil
            and ProjectALife.GunDiscipline.refuses(actor, shell, target) then
        return Combat.attackRefused("gun_discipline")
    end

    if ranged and shove ~= true and ProjectALife.FireControl ~= nil
            and not ProjectALife.FireControl.admit(actor, shell, Combat.nowMs()) then
        return Combat.attackRefused("squad_cadence")
    end

    if ranged and shove ~= true and not Combat.consumeRound(shell, weapon) then
        return Combat.attackRefused("no_round")
    end
    if ranged and shove ~= true and ProjectALife.FireControl ~= nil then
        ProjectALife.FireControl.noteShot(Combat.nowMs())
    end
    if shove ~= true then
        ProjectALife.NPCHitRelay.prepareAttack(shell, weapon, target)
        local relations = ProjectALife.Relations
        if type(instanceof) == "function" and instanceof(target, "IsoPlayer")
                and relations ~= nil and type(relations.hostileToPlayer) == "function"
                and type(relations.noteAggression) == "function" and relations.hostileToPlayer(actor, target) then
            relations.noteAggression(actor, target, Combat.nowMs())
        end
    end
    if shove == true then
        Combat.metrics.shoves = (Combat.metrics.shoves or 0) + 1
    elseif ranged then
        Combat.metrics.shots = (Combat.metrics.shots or 0) + 1
    else
        Combat.metrics.swings = (Combat.metrics.swings or 0) + 1
    end

    if ranged and shove ~= true then
        pcall(function()
            shell:getModData().ProjectALifeLastShotAtMs = Combat.nowMs()
        end)
    end

    local rangedHit, burstIndex = true, 1
    if ranged then
        local dist = math.sqrt(Combat.distanceSquared(shell, target))
        local chance = Combat.baseHitChance(weapon, shell, dist)

        local aiming = 5
        pcall(function()
            local data = shell:getModData()
            aiming = tonumber(data.ProjectALifeAiming) or aiming
            burstIndex = tonumber(data.ProjectALifeBurstIndex) or burstIndex
        end)

        local rangePenaltyScale = math.max(0, math.min(1, (dist - 5) / 8))
        local burstPenalty = math.max(0, burstIndex - 1) * 900
            * rangePenaltyScale
        chance = math.max(800, math.min(10000,
            chance + math.floor((aiming - 5) * 220) - math.floor(burstPenalty)))

        chance = math.floor(chance * Combat.aimScaleFor(shell, target) * Combat.woundAimScale(shell))
        if Combat.kindOf(target) == "player" then
            chance = math.floor(chance * Combat.aimRamp(shell, target, dist))
        end
        chance = math.max(400, math.min(10000, chance))

        chance = math.floor(chance * Combat.rangeFalloff(weapon, shell, dist))
        if type(ZombRand) == "function" then
            rangedHit = ZombRand(10000) < chance
        end
        if Combat.kindOf(target) == "player" then Combat.noteThreatShot(chance, rangedHit) end
    end

    if ranged and shove ~= true and rangedHit ~= true then
        pcall(function()
            local gunner = ProjectALife.ModuleGunner
            local memory = type(actor) == "table" and actor.memory or nil
            local sniper = type(memory) == "table" and memory.conduct == "sniper"
            if sniper and gunner ~= nil and type(gunner.whizz) == "function"
                    and Combat.kindOf(target) ~= "zombie" then
                gunner.whizz(target)
            end
        end)
    end
    if ranged and shove ~= true then
        Combat.reportSound(shell, weapon)
        if burstIndex == 1 then
            pcall(function()
                local horde = ProjectALife.HordeRelations
                if horde ~= nil and type(horde.noteGunfire) == "function" then
                    local radius = tonumber(weapon:getSoundRadius()) or 20
                    horde.noteGunfire(shell, radius, Combat.nowMs() + 7000)
                end
            end)
        end

        if burstIndex == 1 then
            pcall(function()
                local investigation = ProjectALife.Investigation
                if investigation ~= nil and type(investigation.note) == "function" then
                    investigation.note(shell:getX(), shell:getY(), shell:getZ(),
                        tonumber(weapon:getSoundRadius()) or 40, 15000,
                        actor and actor.memory and actor.memory.groupId
                            or (actor and actor.uid) or nil)
                end
            end)
        end

        Combat.presentShot(shell, weapon, target, true)
    end
    if not ranged then
        pcall(function()
            local horde = ProjectALife.HordeRelations
            if horde ~= nil and type(horde.noteMelee) == "function" then
                horde.noteMelee(shell, Combat.nowMs() + 4000)
            end
        end)
    end
    local damaged = false
    if shove == true then

        damaged = true

        local staggerOk = true
        pcall(function()
            if instanceof(target, "IsoPlayer") then staggerOk = false end
        end)
        if staggerOk then
            pcall(function()
                local data = target:getModData()
                if type(data) == "table" then
                    local nextAt = tonumber(data.ProjectALifeNextStaggerAtMs) or 0
                    staggerOk = Combat.nowMs() >= nextAt
                    if staggerOk then
                        data.ProjectALifeNextStaggerAtMs = Combat.nowMs() + 2500
                    end
                end
            end)
        end

        local targetOwned = false
        pcall(function()
            local data = target:getModData()
            targetOwned = type(data) == "table" and (data.ProjectALifeOwned == true
                or data.ProjectALifeActor == true)
        end)
        local knock = staggerOk and not targetOwned
            and (type(ZombRand) ~= "function" or ZombRand(2) == 0)
        if staggerOk then
            pcall(function()
                if Combat.targetIsDown(target) then return end

                if HumanDamage.isActor(target) then
                    knock = false
                    if Animations.current[target] ~= "hit_react" then
                        Animations.apply(target, "hit_react")
                    end
                    return
                end

                local bump = tostring(target:getBumpType() or "")
                local ours = bump == "" or string.sub(bump, 1, 5) == "ALife"
                if string.lower(tostring(target:getActionStateName() or "")) == "bumped" then

                    knock = false
                    if not ours then return end
                elseif knock then

                    if bump ~= "" then target:setBumpType("") end
                    return
                elseif not ours then
                    return
                end
                local behind, side = Combat.blowGeometry(shell, target)
                target:setHitFromBehind(behind)

                target:setBumpFall(false)
                target:setVariable("BumpAnimFinished", false)
                target:setBumpType(side == "R" and "right" or "left")
            end)
        end
        if knock then

            pcall(function()
                target:setKnockedDown(true)
                target:setFallOnFront(shell:isBehind(target) ~= true)
            end)
        end
        pcall(function() shell:playSound("BodyHitGround") end)
    elseif not ranged then

        if Combat.friendlyBody(actor, shell, target) then
            Combat.metrics.friendlyRefused = (Combat.metrics.friendlyRefused or 0) + 1
        else
            damaged = applyDamage(shell, target, weapon, reaction)
        end
    elseif rangedHit then

        local clear = false
        local lineOfFire = ProjectALife.LineOfFire
        if type(lineOfFire) == "table" and type(lineOfFire.resolve) == "function" then
            local checked, result = pcall(lineOfFire.resolve, shell, target, weapon, function(body)
                pcall(applyDamage, shell, body, weapon)
            end, function(body)
                return Combat.hostileToActor(actor, body, shell)
            end)
            clear = checked and result == true
        end

        if clear and Combat.vehicleOnLine(shell, target) then
            clear = false
            Combat.vehicleCoverStops = (Combat.vehicleCoverStops or 0) + 1
        end
        if clear and Combat.friendlyBody(actor, shell, target) then
            clear = false
            Combat.metrics.friendlyRefused = (Combat.metrics.friendlyRefused or 0) + 1
        end
        if clear then damaged = applyDamage(shell, target, weapon, "Shot") end

        if clear and damaged and Combat.settings.bulletPenetration == true then
            local second = Combat.penetrationSecond(shell, target)
            if second ~= nil then
                Combat.penetrations = (Combat.penetrations or 0) + 1
                pcall(applyDamage, shell, second, weapon, "Shot")
            end
        end
    end
    if not ranged and shove ~= true and damaged then
        Combat.meleeAudio("impact", shell, target, weapon)
    end

    if ranged and not rangedHit then
        if shove ~= true then Combat.metrics.misses = (Combat.metrics.misses or 0) + 1 end

        pcall(function()
            local perception = ProjectALife.Perception

            if perception == nil or type(perception.noteAttacker) ~= "function"
                    or target.getModData == nil then return end
            local data = target:getModData()
            if type(data) == "table" and type(data.ProjectALifeUID) == "string" then
                perception.noteAttacker(data.ProjectALifeUID, shell, 5000, "actor")
            end
        end)

        pcall(function()
            local panic = ProjectALife.ModulePanic
            if panic ~= nil then panic.pin(target, Combat.nowMs()) end
        end)

        Combat.missCue(target)
        damaged = true
    end
    if damaged then
        Endurance.consumeAttack(actor, shell, Combat.nowMs())
        if shove ~= true then ProjectALife.Speech.combatBark(shell, "COMBAT_ATTACK", nil, Combat.nowMs()) end
    end
    return damaged
end

Combat.isHeavyMelee = isHeavyMelee
Combat.meleeClass = meleeClass
Combat.meleeSwing = meleeSwing
Combat.resolveAttack = resolveAttack

return Combat
