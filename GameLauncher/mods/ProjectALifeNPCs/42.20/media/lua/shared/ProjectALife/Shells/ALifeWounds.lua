ProjectALife = ProjectALife or {}
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Records/ALifeDifficultyPreset"

local Wounds = {
    settings = { bleedPercent = 100, bluntFracturePercent = 4, legPercent = 55, maxInjuries = 8, npcDamagePercent = 72,
        extraWoundPercent = 0 },
    kinds = {
        scratch = { bleed = 0.0006, clotHours = 0.25, healHours = 48, label = "scratch" },
        laceration = { bleed = 0.0018, clotHours = 1.0, healHours = 120, label = "laceration", limp = true, arm = 0.15 },
        deep = { bleed = 0.0035, healHours = 216, label = "deep wound", limp = true, arm = 0.15 },
        bite = { bleed = 0.0025, clotHours = 1.5, healHours = 168, label = "bite", limp = true, arm = 0.15 },
        bullet = { bleed = 0.0040, healHours = 240, label = "bullet wound", limp = true, arm = 0.15 },
        bruise = { healHours = 72, label = "bruise" },
        fracture = { healHours = 960, label = "fracture", limp = true, arm = 0.4, always = true },
        burn = { healHours = 240, label = "burn" },
    },
    parts = { head = "head", torso = "torso", arm_l = "left arm", arm_r = "right arm", leg_l = "left leg", leg_r = "right leg" },
    explicit = { firearm = true, blade = true, blunt = true, fists = true, vehicle = true, zombie = true, fire = true, fall = true },
    bladeCategories = { "AXE", "LONG_BLADE", "SMALL_BLADE", "SPEAR" },
    bluntCategories = { "BLUNT", "SMALL_BLUNT" },
    limbParts = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
        [11] = true, [12] = true, [13] = true, [14] = true, [15] = true, [16] = true },
    words = {
        { kind = "firearm", list = { "[^%a]shot[^%a]", "[^%a]shots[^%a]", "[^%a]shoot", "[^%a]bullet", "gunshot",
            "taking fire", "under fire", "open fire", "opened fire", "[^%a]fired[^%a]", "your fire", "cease fire",
            "hold fire", "return fire", "friendly fire", "rounds on", "or i fire", "%. fire[^%a]", "hole in me", "took one[^%a]",
            "[^%a]plugged", "[^%a]guns?[^%a]", "[^%a]pistol", "[^%a]rifle", "[^%a]shotgun", "gunfire", "[^%a]muzzle",
            "[^%a]trigger", "[^%a]aiming at", "[^%a]bang[^%a]" } },
        { kind = "vehicle", list = { "run me over", "ran me over", "running me over", "run him over", "ran him over",
            "[^%a]your car", "[^%a]your truck", "[^%a]your van", "[^%a]the bumper", "[^%a]your bumper", "[^%a]hit by a car",
            "[^%a]hit by a truck", "[^%a]driving at", "[^%a]the windshield", "vehicle struck", "vehicle hit", "by a vehicle",
            "with a vehicle", "that vehicle", "stopping the vehicle", "ran over", "run over",
            "[^%a]driver", "that truck hit", "with that truck", "that truck at", "stop that truck", "that car hit",
            "with that car", "that car's coming", "that van" } },
        { kind = "blade", list = { "[^%a]stab", "[^%a]knifed", "[^%a]slash", "[^%a]sliced", "[^%a]cut me", "[^%a]cut him",
            "[^%a]cut her", "[^%a]shank", "[^%a]knife", "[^%a]blade", "[^%a]machete", "[^%a]axe[^%a]", "[^%a]hatchet",
            "[^%a]cleaver", "[^%a]gutted", "[^%a]carved" } },
        { kind = "blunt", list = { "[^%a]whack", "[^%a]bludgeon", "[^%a]clubbed", "[^%a]bashed", "[^%a]bat[^%a]",
            "[^%a]nightstick", "[^%a]crowbar", "[^%a]pipe[^%a]", "[^%a]hammer", "[^%a]wrench",
            "[^%a]shovel", "[^%a]frying pan", "[^%a]skull" } },
        { kind = "fists", list = { "[^%a]punch", "[^%a]slugged", "[^%a]fist", "[^%a]slapped", "[^%a]knuckles",
            "[^%a]in the jaw", "[^%a]in the face" } },
        { kind = "melee", list = { "[^%a]swing", "[^%a]swung" } },
    },
    meleeKinds = { blunt = true, blade = true, fists = true },
    textCache = {},
    textCacheCount = 0,
    metrics = { classified = 0, softened = 0, fractures = 0, playerHits = 0, traumaHits = 0, traumaPoints = 0,
        landedPoints = 0, damageApiFailures = 0, damageFallbackApplied = 0, damageFallbackFailed = 0,
        damageZeroFloored = 0 },
    damageFloors = { firearm = 0.6, blade = 0.4, blunt = 0.4, fists = 0.2 },
    weight = { [0] = 0.01, [1] = 0.01, [2] = 0.035, [3] = 0.035, [4] = 0.045, [5] = 0.045, [6] = 0.18, [7] = 0.12,
        [8] = 0.08, [9] = 0.02, [10] = 0.06, [11] = 0.09, [12] = 0.09, [13] = 0.07, [14] = 0.07, [15] = 0.02, [16] = 0.02 },
    zone = { [0] = 0.5, [1] = 0.5, [2] = 0.7, [3] = 0.7, [4] = 0.8, [5] = 0.8, [6] = 1.3, [7] = 1.1, [8] = 1.6,
        [9] = 1.4, [10] = 1.0, [11] = 0.8, [12] = 0.8, [13] = 0.7, [14] = 0.7, [15] = 0.5, [16] = 0.5 },
    traumaSettings = { perDamage = 8, meleeBoost = 1.3, maxHit = 25, spill = { 6, 7, 10, 11, 12 } },
}
ProjectALife.Wounds = Wounds

function Wounds.setting(key)
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if key == "bleedPercent" and type(current) == "table" and tonumber(current.injuryBleedPercent) ~= nil then
        return tonumber(current.injuryBleedPercent)
    end
    if key == "bluntFracturePercent" and type(current) == "table" and tonumber(current.bluntFracturePercent) ~= nil then
        return tonumber(current.bluntFracturePercent)
    end
    if key == "npcDamagePercent" and type(current) == "table" and tonumber(current.npcDamagePercent) ~= nil then
        return tonumber(current.npcDamagePercent)
    end
    if key == "extraWoundPercent" and type(current) == "table" and tonumber(current.extraWoundPercent) ~= nil then
        return tonumber(current.extraWoundPercent)
    end
    if key == "npcDamagePercent" then
        local preset = ProjectALife.DifficultyPreset
        local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
        local value = type(vars) == "table" and tonumber(vars.Combat_DamagePercent) or nil
        value = value or Wounds.settings.npcDamagePercent
        if preset ~= nil and type(preset.option) == "function" then
            value = preset.option("Combat_DamagePercent", value, vars)
        end
        return math.max(0, math.min(100, value))
    end
    return Wounds.settings[key]
end

function Wounds.categoryOf(weapon, names)
    if WeaponCategory == nil or type(weapon.isOfWeaponCategory) ~= "function" then return false end
    for _, name in ipairs(names) do
        local category = WeaponCategory[name]
        if category ~= nil and weapon:isOfWeaponCategory(category) == true then return true end
    end
    return false
end

function Wounds.readWeaponKind(weapon)
    if type(weapon.getFullType) == "function" and weapon:getFullType() == "Base.BareHands" then return "fists" end
    if type(weapon.isAimedFirearm) == "function" and weapon:isAimedFirearm() == true then return "firearm" end
    if type(weapon.isRanged) == "function" and weapon:isRanged() == true then return "firearm" end
    if Wounds.categoryOf(weapon, Wounds.bladeCategories) then return "blade" end
    if Wounds.categoryOf(weapon, Wounds.bluntCategories) then return "blunt" end
    if Wounds.categoryOf(weapon, { "UNARMED" }) then return "fists" end
    if WeaponType ~= nil and type(WeaponType.getWeaponType) == "function" then
        local kind = WeaponType.getWeaponType(weapon)
        if kind == WeaponType.KNIFE or kind == WeaponType.SPEAR then return "blade" end
        if kind == WeaponType.UNARMED then return "fists" end
    end
    return "blunt"
end

function Wounds.weaponKind(weapon)
    if weapon == nil then return "fists" end
    if type(weapon) == "string" then
        if Wounds.explicit[weapon] then return weapon end
        return "unknown"
    end
    local ok, kind = pcall(Wounds.readWeaponKind, weapon)
    if ok and type(kind) == "string" then return kind end
    return "blunt"
end

function Wounds.isNpcShell(body)
    if body == nil or type(body.hasModData) ~= "function" or type(body.getModData) ~= "function" then return false end
    if body:hasModData() ~= true then return false end
    local data = body:getModData()
    return type(data) == "table" and (type(data.ProjectALifeUID) == "string" or data.ProjectALifeActor == true)
end

function Wounds.attackKind(attacker, weapon)
    if weapon ~= nil then return Wounds.weaponKind(weapon) end
    if attacker == nil then return "unknown" end
    local kind = type(attacker)
    if kind == "string" then return Wounds.weaponKind(attacker) end
    if kind ~= "userdata" and kind ~= "table" then return "unknown" end
    if type(instanceof) == "function" then
        if instanceof(attacker, "BaseVehicle") then return "vehicle" end
        if instanceof(attacker, "IsoZombie") then
            local okNpc, npc = pcall(Wounds.isNpcShell, attacker)
            if not (okNpc and npc) then return "zombie" end
        end
    end
    if type(attacker.getPrimaryHandItem) ~= "function" then return "unknown" end
    local ok, item = pcall(attacker.getPrimaryHandItem, attacker)
    if not ok then return "unknown" end
    return Wounds.weaponKind(item)
end

function Wounds.textAttack(text)
    if type(text) ~= "string" or text == "" then return nil end
    local cached = Wounds.textCache[text]
    if cached ~= nil then return cached or nil end
    local lowered = " " .. string.lower(text) .. " "
    local found = false
    for _, group in ipairs(Wounds.words) do
        for _, pattern in ipairs(group.list) do
            if string.find(lowered, pattern) ~= nil then found = group.kind; break end
        end
        if found then break end
    end
    if Wounds.textCacheCount >= 4096 then Wounds.textCache, Wounds.textCacheCount = {}, 0 end
    Wounds.textCacheCount = Wounds.textCacheCount + 1
    Wounds.textCache[text] = found
    return found or nil
end

function Wounds.lineFits(lineKind, attack)
    if lineKind == nil or attack == nil then return true end
    if lineKind == "melee" then return Wounds.meleeKinds[attack] == true end
    return lineKind == attack
end

function Wounds.textFits(text, attack)
    if attack == nil then return true end
    return Wounds.lineFits(Wounds.textAttack(text), attack)
end

function Wounds.side(rollValue)
    return (tonumber(rollValue) or 0) < 50 and "_l" or "_r"
end

function Wounds.partFor(zone, first, second)
    if zone == "head" then return "head" end
    if zone == "limb" then
        local leg = (tonumber(first) or 0) < (tonumber(Wounds.setting("legPercent")) or 55)
        return (leg and "leg" or "arm") .. Wounds.side(second)
    end
    return "torso"
end

function Wounds.pick(rollValue, rows)
    local total = 0
    for _, row in ipairs(rows) do total = total + row[2] end
    local at = (tonumber(rollValue) or 0) * total / 100
    for _, row in ipairs(rows) do
        at = at - row[2]
        if at < 0 then return row[1] end
    end
    return rows[#rows][1]
end

function Wounds.isLimb(part)
    local head = string.sub(tostring(part or ""), 1, 3)
    return head == "arm" or head == "leg"
end

function Wounds.classify(cause, part, first, second, zombieKind)
    local limb = Wounds.isLimb(part)
    local kind, low, high
    if cause == "firearm" then
        kind, low, high = "bullet", 45, 85
    elseif cause == "blade" then
        kind = Wounds.pick(first, { { "laceration", 70 }, { "deep", 30 } })
        low, high = kind == "deep" and 45 or 25, kind == "deep" and 75 or 55
    elseif cause == "zombie" then
        kind = zombieKind
        if kind ~= "scratch" and kind ~= "laceration" and kind ~= "bite" then
            kind = Wounds.pick(first, { { "scratch", 55 }, { "laceration", 30 }, { "bite", 15 } })
        end
        low, high = kind == "scratch" and 10 or 30, kind == "scratch" and 30 or 60
    elseif cause == "vehicle" or cause == "fall" then
        kind = limb and Wounds.pick(first, { { "fracture", 40 }, { "bruise", 60 } }) or "bruise"
        low, high = 40, 80
    elseif cause == "fire" then
        kind, low, high = "burn", 15, 25
    elseif cause == "blunt" then
        kind = limb and Wounds.pick(first, { { "bruise", 70 }, { "scratch", 10 }, { "fracture", 20 } })
            or Wounds.pick(first, { { "bruise", 85 }, { "scratch", 15 } })
        low, high = 25, 60
    else
        kind, low, high = "bruise", 10, 30
    end
    local severity = low + math.floor((high - low) * math.max(0, math.min(99, tonumber(second) or 50)) / 99)
    Wounds.metrics.classified = Wounds.metrics.classified + 1
    return kind, severity
end

function Wounds.bleeding(injury, hours)
    local kind = type(injury) == "table" and Wounds.kinds[injury.k] or nil
    if kind == nil or kind.bleed == nil or injury.b == true then return false end
    if kind.clotHours ~= nil and (tonumber(hours) or 0) >= (tonumber(injury.h) or 0) + kind.clotHours then return false end
    return true
end

function Wounds.healedAt(injury)
    local kind = Wounds.kinds[injury.k] or Wounds.kinds.bruise
    local base = kind.healHours * (0.5 + (tonumber(injury.s) or 50) / 100)
    if injury.b ~= true and kind.bleed ~= nil then base = base * 1.25 end
    if injury.k == "fracture" and injury.sp ~= true then base = base * 4 end
    return (tonumber(injury.h) or 0) + base
end

function Wounds.add(list, part, kind, severity, hours)
    for _, injury in ipairs(list) do
        if injury.p == part and injury.k == kind and injury.b ~= true then
            injury.s = math.min(100, math.max(injury.s, severity) + math.floor(math.min(injury.s, severity) / 2))
            injury.h = hours
            return injury
        end
    end
    local injury = { p = part, k = kind, s = severity, h = hours }
    list[#list + 1] = injury
    local cap = tonumber(Wounds.settings.maxInjuries) or 8
    while #list > cap do
        local least = 1
        for index, other in ipairs(list) do
            if (tonumber(other.s) or 0) < (tonumber(list[least].s) or 0) then least = index end
        end
        table.remove(list, least)
    end
    return injury
end

Wounds.tunedMinuteSeconds = 2.5

function Wounds.readMinutesPerDay()
    local time = getGameTime()
    return tonumber(time:getMinutesPerDay())
end

function Wounds.clotScale()
    if type(getGameTime) ~= "function" then return 1 end
    local ok, minutes = pcall(Wounds.readMinutesPerDay)
    if not ok or minutes == nil or minutes <= 0 then return 1 end
    return math.min(1, Wounds.tunedMinuteSeconds / (minutes * 60 / 1440))
end

function Wounds.effects(list, hours)
    local limp, arms, bleed = false, 1, 0
    local rate = math.max(0, tonumber(Wounds.setting("bleedPercent")) or 100) / 100
    local clot = nil
    for _, injury in ipairs(type(list) == "table" and list or {}) do
        local kind = Wounds.kinds[injury.k]
        if kind ~= nil then
            local part = string.sub(tostring(injury.p or ""), 1, 3)
            local severity = tonumber(injury.s) or 0
            local splinted = injury.sp == true
            if part == "leg" and kind.limp == true and not splinted
                    and (kind.always == true or (severity >= 40 and injury.b ~= true)) then
                limp = true
            end
            if part == "arm" and kind.arm ~= nil then arms = arms - (splinted and 0.15 or kind.arm) end
            if Wounds.bleeding(injury, hours) then
                local scale = 1
                if kind.clotHours ~= nil then
                    clot = clot or Wounds.clotScale()
                    scale = clot
                end
                bleed = bleed + kind.bleed * severity / 100 * rate * scale
            end
        end
    end
    return limp, math.max(0.4, arms), bleed
end

function Wounds.prune(list, hours)
    if type(list) ~= "table" then return list, 0 end
    local kept, healed = {}, 0
    for _, injury in ipairs(list) do
        if not Wounds.bleeding(injury, hours) and (tonumber(hours) or 0) >= Wounds.healedAt(injury) then
            healed = healed + 1
        else
            kept[#kept + 1] = injury
        end
    end
    return kept, healed
end

function Wounds.bandage(list)
    local covered = 0
    for _, injury in ipairs(type(list) == "table" and list or {}) do
        local kind = Wounds.kinds[injury.k]
        if kind ~= nil and kind.bleed ~= nil and injury.b ~= true then
            injury.b = true
            covered = covered + 1
        end
    end
    return covered
end

function Wounds.splint(list)
    local set = 0
    for _, injury in ipairs(type(list) == "table" and list or {}) do
        if injury.k == "fracture" and injury.sp ~= true then
            injury.sp = true
            set = set + 1
        end
    end
    return set
end

function Wounds.copy(list)
    local out = {}
    for _, injury in ipairs(type(list) == "table" and list or {}) do
        if type(injury) == "table" and Wounds.kinds[injury.k] ~= nil and Wounds.parts[injury.p] ~= nil then
            out[#out + 1] = { p = injury.p, k = injury.k, s = tonumber(injury.s) or 30, h = tonumber(injury.h) or 0,
                b = injury.b == true or nil, sp = injury.sp == true or nil }
        end
    end
    return out
end

function Wounds.merge(own, other)
    local merged, index = {}, {}
    for _, list in ipairs({ type(own) == "table" and own or {}, type(other) == "table" and other or {} }) do
        for _, injury in ipairs(list) do
            if type(injury) == "table" then
                local key = tostring(injury.p) .. "|" .. tostring(injury.k)
                local at = index[key]
                if at == nil then
                    merged[#merged + 1] = injury
                    index[key] = #merged
                else
                    local held = merged[at]
                    local hours, heldHours = tonumber(injury.h) or 0, tonumber(held.h) or 0
                    local covered = (injury.b == true or injury.sp == true) and not (held.b == true or held.sp == true)
                    if hours > heldHours or (hours == heldHours and (covered
                            or (injury.s or 0) > (held.s or 0))) then
                        merged[at] = injury
                    end
                end
            end
        end
    end
    local cap = tonumber(Wounds.settings.maxInjuries) or 8
    while #merged > cap do
        local least = 1
        for position, other in ipairs(merged) do
            if (tonumber(other.s) or 0) < (tonumber(merged[least].s) or 0) then least = position end
        end
        table.remove(merged, least)
    end
    return Wounds.copy(merged)
end

function Wounds.label(kind)
    local row = Wounds.kinds[kind]
    local english = row and row.label or tostring(kind)
    local text = ProjectALife.Text
    if text ~= nil and type(text.ui) == "function" then return text.ui(english) end
    return english
end

function Wounds.partLabel(part)
    local english = Wounds.parts[part] or tostring(part)
    local text = ProjectALife.Text
    if text ~= nil and type(text.ui) == "function" then return text.ui(english) end
    return english
end

function Wounds.describe(list, hours, limit)
    local sorted = {}
    for _, injury in ipairs(type(list) == "table" and list or {}) do sorted[#sorted + 1] = injury end
    table.sort(sorted, function(a, b)
        local ab, bb = Wounds.bleeding(a, hours), Wounds.bleeding(b, hours)
        if ab ~= bb then return ab end
        return (tonumber(a.s) or 0) > (tonumber(b.s) or 0)
    end)
    local words = {}
    for index = 1, math.min(tonumber(limit) or 3, #sorted) do
        local injury = sorted[index]
        local text = Wounds.label(injury.k) .. " (" .. Wounds.partLabel(injury.p) .. ")"
        if Wounds.bleeding(injury, hours) then text = text .. ", " .. Wounds.label("bleeding")
        elseif injury.b == true then text = text .. ", " .. Wounds.label("bandaged") end
        if injury.sp == true then text = text .. ", " .. Wounds.label("splinted") end
        words[#words + 1] = text
    end
    return table.concat(words, "; "), #sorted
end

function Wounds.applyWeapon(bodyDamage, weapon, part)
    bodyDamage:DamageFromWeapon(weapon, part)
    return true
end

function Wounds.applyWeaponAnywhere(bodyDamage, weapon)
    bodyDamage:DamageFromWeapon(weapon)
    return true
end

function Wounds.partAt(bodyDamage, index)
    if BodyPartType == nil or type(BodyPartType.FromIndex) ~= "function" then return nil end
    local partType = BodyPartType.FromIndex(index)
    if partType == nil then return nil end
    return bodyDamage:getBodyPart(partType)
end

function Wounds.cutsOf(bodyDamage)
    local cuts = {}
    for index = 0, 16 do
        local part = Wounds.partAt(bodyDamage, index)
        if part ~= nil and type(part.isCut) == "function" and type(part.isDeepWounded) == "function" then
            cuts[index] = { cut = part:isCut() == true, deep = part:isDeepWounded() == true }
        end
    end
    return cuts
end

function Wounds.heavyBlunt(weapon)
    if weapon == nil or type(weapon) == "string" then return false end
    local ok, heavy = pcall(Wounds.categoryOf, weapon, { "BLUNT" })
    return ok and heavy == true
end

function Wounds.soften(bodyDamage, before, weapon, aimed)
    local softened = 0
    for index = 0, 16 do
        local part = Wounds.partAt(bodyDamage, index)
        local was = before[index]
        if part ~= nil and type(was) == "table" then
            local opened = false
            if was.cut ~= true and part:isCut() == true then
                part:setCut(false)
                if type(part.setCutTime) == "function" then part:setCutTime(0) end
                opened = true
            end
            if was.deep ~= true and part:isDeepWounded() == true then
                part:setDeepWounded(false)
                if type(part.setDeepWoundTime) == "function" then part:setDeepWoundTime(0) end
                part:setBleeding(false)
                opened = true
            end
            if opened then
                part:setScratched(true, true)
                softened = softened + 1
            end
        end
    end
    Wounds.metrics.softened = Wounds.metrics.softened + softened
    local chance = tonumber(Wounds.setting("bluntFracturePercent")) or 0
    local index = tonumber(aimed) or -1
    if chance > 0 and Wounds.limbParts[index] and Wounds.heavyBlunt(weapon) and type(ZombRand) == "function"
            and ZombRand(100) < chance then
        local part = Wounds.partAt(bodyDamage, index)
        if part ~= nil and type(part.generateFractureNew) == "function"
                and (tonumber(part:getFractureTime()) or 0) <= 0 then
            part:generateFractureNew(40 + ZombRand(30))
            Wounds.metrics.fractures = Wounds.metrics.fractures + 1
        end
    end
    return softened
end

function Wounds.partHealths(bodyDamage)
    local out = {}
    for index = 0, 16 do
        local part = Wounds.partAt(bodyDamage, index)
        if part ~= nil and type(part.getHealth) == "function" and type(part.SetHealth) == "function" then
            out[index] = tonumber(part:getHealth())
        end
    end
    return out
end

function Wounds.scaleDamage(bodyDamage, before, scale)
    local refunded = 0
    for index, was in pairs(before) do
        local part = Wounds.partAt(bodyDamage, index)
        local now = part ~= nil and tonumber(part:getHealth()) or nil
        if was ~= nil and now ~= nil and now < was then
            part:SetHealth(was - (was - now) * scale)
            refunded = refunded + (was - now) * (1 - scale)
        end
    end
    Wounds.metrics.damageRefunded = (Wounds.metrics.damageRefunded or 0) + refunded
    return refunded
end

function Wounds.weaponRoll(weapon)
    local low, high = 0.5, 1
    if type(weapon) == "userdata" or type(weapon) == "table" then
        if type(weapon.getMinDamage) == "function" then low = tonumber(weapon:getMinDamage()) or low end
        if type(weapon.getMaxDamage) == "function" then high = tonumber(weapon:getMaxDamage()) or high end
    end
    if high < low then high = low end
    local fraction = 0.5
    if type(ZombRand) == "function" then fraction = ZombRand(1001) / 1000 end
    local roll = low + (high - low) * fraction
    if roll > 0 then return roll end
    Wounds.metrics.damageZeroFloored = (Wounds.metrics.damageZeroFloored or 0) + 1
    return Wounds.damageFloors[Wounds.weaponKind(weapon)] or Wounds.damageFloors.blunt
end

function Wounds.declaresNoDamage(weapon)
    if type(weapon) ~= "userdata" and type(weapon) ~= "table" then return false end
    if type(weapon.getMaxDamage) ~= "function" then return false end
    local ok, high = pcall(weapon.getMaxDamage, weapon)
    return ok and (tonumber(high) or 0) <= 0
end

function Wounds.humanVisualMissing(bodyDamage)
    if type(bodyDamage.getParentChar) ~= "function" then return false end
    local ok, parent = pcall(bodyDamage.getParentChar, bodyDamage)
    if not ok or parent == nil then return true end
    if type(parent.getHumanVisual) ~= "function" then return false end
    local seen, visual = pcall(parent.getHumanVisual, parent)
    return not seen or visual == nil
end

function Wounds.healthLoss(before, after)
    local total, hit, most = 0, nil, 0
    for index, was in pairs(before) do
        local now = after[index]
        local weight = Wounds.weight[index]
        if was ~= nil and now ~= nil and weight ~= nil and now < was then
            local lost = (was - now) * weight
            total = total + lost
            if lost > most then hit, most = index, lost end
        end
    end
    return total, hit
end

function Wounds.applyTrauma(bodyDamage, weapon, before, scale)
    local settings = Wounds.traumaSettings
    local landed, hit = Wounds.healthLoss(before, Wounds.partHealths(bodyDamage))
    if hit == nil then return 0 end
    local wanted = Wounds.weaponRoll(weapon) * settings.perDamage * scale * (Wounds.zone[hit] or 1)
    if type(weapon.isRanged) == "function" and weapon:isRanged() ~= true then wanted = wanted * settings.meleeBoost end
    wanted = math.min(wanted, settings.maxHit * scale)
    local owed = wanted - landed
    Wounds.metrics.landedPoints = Wounds.metrics.landedPoints + landed
    if owed <= 0 then return 0 end
    local order = { hit }
    for _, index in ipairs(settings.spill) do
        if index ~= hit then order[#order + 1] = index end
    end
    local applied = 0
    for _, index in ipairs(order) do
        if owed - applied <= 0.01 then break end
        local part = Wounds.partAt(bodyDamage, index)
        local weight = Wounds.weight[index]
        if part ~= nil and weight ~= nil and type(part.getHealth) == "function" and type(part.AddDamage) == "function" then
            local room = (tonumber(part:getHealth()) or 0) * weight
            local take = math.min(owed - applied, room)
            if take > 0 then
                part:AddDamage(take / weight)
                applied = applied + take
            end
        end
    end
    Wounds.metrics.traumaHits = Wounds.metrics.traumaHits + 1
    Wounds.metrics.traumaPoints = Wounds.metrics.traumaPoints + applied
    return applied
end

function Wounds.partIndexOf(name, fallback)
    local kinds = BodyPartType
    if kinds ~= nil and kinds[name] ~= nil and type(kinds.ToIndex) == "function" then
        local ok, index = pcall(kinds.ToIndex, kinds[name])
        if ok and tonumber(index) ~= nil then return tonumber(index) end
    end
    return fallback
end

function Wounds.randomPart()
    if type(ZombRand) == "function" then return ZombRand(17) end
    return 6
end

function Wounds.applyDirect(bodyDamage, weapon, index, scale, kind)
    if bodyDamage == nil or type(bodyDamage.getBodyPart) ~= "function" then return false end
    index = tonumber(index) or -1
    if index < 0 or index > 16 then index = Wounds.randomPart() end
    local part = Wounds.partAt(bodyDamage, index)
    if part == nil or type(part.ReduceHealth) ~= "function" then return false end
    local damage = Wounds.weaponRoll(weapon) * 15
    if index == Wounds.partIndexOf("Head", 8) or index == Wounds.partIndexOf("Neck", 9) then
        damage = damage * 4
    elseif index == Wounds.partIndexOf("Torso_Upper", 6) then
        damage = damage * 2
    end
    part:ReduceHealth(damage * (tonumber(scale) or 1))
    local roll = type(ZombRand) == "function" and ZombRand(6) or 5
    if kind == "firearm" then
        if type(part.setHaveBullet) == "function" then part:setHaveBullet(true, 0) end
    elseif kind == "blade" then
        if roll == 0 and type(part.generateDeepWound) == "function" then part:generateDeepWound()
        elseif roll <= 2 and type(part.setCut) == "function" then part:setCut(true)
        elseif type(part.setScratched) == "function" then part:setScratched(true, true) end
    else
        if roll == 0 and type(part.setCut) == "function" then part:setCut(true)
        elseif type(part.setScratched) == "function" then part:setScratched(true, true) end
    end
    return true
end

function Wounds.damagePlayer(bodyDamage, weapon, part)
    if bodyDamage == nil or weapon == nil or type(bodyDamage.DamageFromWeapon) ~= "function" then
        return false, "native_wound_unavailable"
    end
    local scale = math.max(0, math.min(1, (tonumber(Wounds.setting("npcDamagePercent")) or 100) / 100))
    local extra = math.max(0, math.min(2, (tonumber(Wounds.setting("extraWoundPercent")) or 0) / 100))
    local healths = nil
    local okHealth, read = pcall(Wounds.partHealths, bodyDamage)
    if okHealth then healths = read end
    local kind = Wounds.weaponKind(weapon)
    local before = nil
    if kind == "blunt" or kind == "fists" then
        local okCuts, cuts = pcall(Wounds.cutsOf, bodyDamage)
        if okCuts then before = cuts end
    end
    local index = tonumber(part) or -1
    local ok, err
    if Wounds.humanVisualMissing(bodyDamage) then
        Wounds.metrics.humanVisualMissing = (Wounds.metrics.humanVisualMissing or 0) + 1
        ok, err = false, "human_visual_missing"
    else
        ok, err = pcall(Wounds.applyWeapon, bodyDamage, weapon, index)
        if not ok then ok, err = pcall(Wounds.applyWeaponAnywhere, bodyDamage, weapon) end
    end
    local direct = false
    if ok and healths ~= nil and Wounds.declaresNoDamage(weapon) then
        local readOk, now = pcall(Wounds.partHealths, bodyDamage)
        if readOk and Wounds.healthLoss(healths, now) <= 0 then
            local floorOk, floored = pcall(Wounds.applyDirect, bodyDamage, weapon, index, scale, kind)
            if floorOk and floored == true then direct = true end
        end
    end
    if not ok then
        Wounds.metrics.damageApiFailures = Wounds.metrics.damageApiFailures + 1
        Wounds.metrics.lastDamageApiError = string.sub(tostring(err), 1, 120)
        local fallbackOk, applied = pcall(Wounds.applyDirect, bodyDamage, weapon, index, scale, kind)
        if fallbackOk and applied == true then
            ok, err, direct = true, nil, true
            Wounds.metrics.damageFallbackApplied = Wounds.metrics.damageFallbackApplied + 1
        else
            Wounds.metrics.damageFallbackFailed = Wounds.metrics.damageFallbackFailed + 1
        end
    end
    if direct then
        Wounds.metrics.playerHits = Wounds.metrics.playerHits + 1
        return true, nil
    end
    if ok and before ~= nil then pcall(Wounds.soften, bodyDamage, before, weapon, index) end
    if ok and healths ~= nil and scale < 1 then pcall(Wounds.scaleDamage, bodyDamage, healths, scale) end
    if ok and healths ~= nil and extra > 0 then pcall(Wounds.applyTrauma, bodyDamage, weapon, healths, extra) end
    if ok then Wounds.metrics.playerHits = Wounds.metrics.playerHits + 1 end
    return ok, err
end

return Wounds
