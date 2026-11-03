require "ProjectALife/Combat/ALifeCombatCore"
require "ProjectALife/Combat/ALifeWeapons"
require "ProjectALife/Combat/ALifeLineOfFire"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Senses/ALifeZombieRetarget"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Weapons = ProjectALife.Weapons
local Magazines = ProjectALife.MagazineState
local LineOfFire = ProjectALife.LineOfFire
local TargetPolicy = ProjectALife.TargetPolicy
local Combat = ProjectALife.Combat
local Interop = ProjectALife.Interop

function Combat.readyPresetFor(shell, weapon, target)
    if weapon == nil then return "ready_melee" end

    local kneel = false
    pcall(function()
        local data = shell:getModData()
        if data.ProjectALifeWeaponHeld ~= true then return end
        local phase = tostring(data.ProjectALifeCombatPhase or "idle")
        if data.ProjectALifeConduct == "sniper" then
            kneel = phase == "idle" or phase == "" or phase == "cover" or phase == "aborted"
        elseif data.ProjectALifeConduct == "ambusher"
                and (phase == "idle" or phase == "" or phase == "cover")
                and tostring(Combat.variable(shell, "ALifeWeaponClass")) ~= "handgun"
                and type(shell.isMoving) == "function" and shell:isMoving() == false
                and (type(shell.isRunning) ~= "function" or shell:isRunning() ~= true)
                and type(shell.getX) == "function" and type(shell.getY) == "function"
                and target ~= nil and type(target.getX) == "function" and type(target.getY) == "function" then
            local now = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
            local heldUntil = tonumber(data.ProjectALifeHoldFireUntilMs) or 0
            local distanceSq = (target:getX() - shell:getX()) ^ 2 + (target:getY() - shell:getY()) ^ 2
            kneel = now ~= nil and now > 0 and heldUntil > now and distanceSq > 49
        end
    end)
    if kneel and Combat.isRanged(weapon) then return "ready_kneel" end
    if Combat.isRanged(weapon) then

        local handgun = tostring(Combat.variable(shell, "ALifeWeaponClass")) == "handgun"
        return handgun and "ready_handgun" or "ready_rifle"
    end

    local fullOk, fullType = pcall(function()
        return string.lower(tostring(weapon:getFullType())) end)
    if fullOk and string.find(fullType, "spear", 1, true) then
        return "ready_spear"
    end
    local twoHand = false
    pcall(function()
        twoHand = weapon:isRequiresEquippedBothHands() == true
            or weapon:isTwoHandWeapon() == true
    end)
    return twoHand and "ready_melee_2h" or "ready_melee"
end

function Combat.shotPresetFor(shell)
    return tostring(Combat.variable(shell, "ALifeWeaponClass")) == "handgun"
        and "combat_handgun" or "combat_rifle"
end

local function weaponReloadType(weapon)
    local ok, value = pcall(function() return weapon:getWeaponReloadType() end)
    return ok and string.lower(tostring(value or "")):gsub("[^a-z]", "") or ""
end

function Combat.loopReloadPresetFor(shell, weapon)
    local reload = weaponReloadType(weapon)
    if string.find(reload, "revolver", 1, true) then return "reload_revolver_loop" end

    if string.find(reload, "boltactionnomag", 1, true) then
        return "reload_shotgun_loop"
    end
    if string.find(reload, "shotgun", 1, true) then return "reload_shotgun_loop" end
    if string.find(reload, "boltaction", 1, true)
            or string.find(reload, "leveraction", 1, true) then
        return "reload_rifle_loop"
    end
    return nil
end

function Combat.nearestEnemyInLane(actor, shell, target)
    local found
    pcall(function()
        local body = LineOfFire.firstBodyOnLine(shell, target)
        if body == nil then return end
        local data = body:getModData()
        local owned = type(data) == "table" and data.ProjectALifeOwned == true

        if not Combat.hostileToActor(actor, body, shell) then return end
        if not owned and not TargetPolicy.canAttack(body) then return end
        found = body
    end)
    return found
end

function Combat.reloadPresetFor(shell, weapon)
    local reload = weaponReloadType(weapon)
    if string.find(reload, "revolver", 1, true) then return "reload_revolver" end

    if string.find(reload, "boltactionnomag", 1, true) then
        return "reload_shotgun"
    end
    if string.find(reload, "shotgun", 1, true) then return "reload_shotgun" end
    if string.find(reload, "handgun", 1, true)
            or tostring(Combat.variable(shell, "ALifeWeaponClass")) == "handgun" then
        return "reload_handgun"
    end
    return "reload_rifle"
end

function Combat.jamPresetFor(shell)
    return tostring(Combat.variable(shell, "ALifeWeaponClass")) == "handgun"
        and "jam_handgun" or "jam_rifle"
end

function Combat.rackPresetFor(shell, weapon, context)
    local reload = weaponReloadType(weapon)

    if Weapons.isRevolver(weapon) then
        return context == "reload" and "rack_revolver" or nil
    end
    if context == "cycle" then
        if string.find(reload, "leveraction", 1, true) then
            return "cycle_lever_aim"
        end
        if string.find(reload, "boltaction", 1, true) then
            return "cycle_bolt_aim"
        end
        if string.find(reload, "shotgun", 1, true) then
            return "cycle_shotgun_aim"
        end
    end
    if string.find(reload, "shotgun", 1, true) then return "rack_shotgun" end
    if string.find(reload, "handgun", 1, true)
            or tostring(Combat.variable(shell, "ALifeWeaponClass")) == "handgun" then
        return "rack_handgun"
    end
    return "rack_rifle"
end

local function automaticWeapon(weapon)
    return Weapons.isAutomatic(weapon)
end

function Combat.burstLength(shell, weapon, distance, target)

    pcall(function()
        local weapons = ProjectALife.Weapons
        if weapons ~= nil and type(weapons.applyFiringDoctrine) == "function" then
            weapons.applyFiringDoctrine(shell, weapon)
        end
    end)
    local conduct, carry, sustained = "", "", false
    pcall(function()
        local data = shell:getModData()
        conduct = tostring(data.ProjectALifeConduct or "")
        carry = tostring(data.ProjectALifeWeaponClass or "")
        sustained = data.ProjectALifeConductSecondaryGunner == true
    end)
    if conduct == "sniper" then return 1 end
    local automatic = false
    pcall(function()
        local weapons = ProjectALife.Weapons
        if weapons ~= nil then
            automatic = weapons.racksAfterShot(weapon) ~= true
                and weapons.isAutomatic(weapon) == true
        end
    end)
    if not automatic then return 1 end
    if conduct == "gunner" or sustained then
        if target ~= nil and not Combat.targetIsHuman(target) then
            return tonumber((Combat.settings or {}).zombieBurstCap) or 3
        end
        return 999
    end
    return Combat.workingBurst(weapon, carry, target)
end

function Combat.workingBurst(weapon, carry, target)
    local s = Combat.settings or {}
    local low = tonumber(s.burstMinRounds) or 3
    local high = tonumber(s.burstMaxRounds) or 8
    if carry ~= "rifle" then
        high = tonumber(s.handgunBurstMax) or 3
        low = math.max(1, math.min(low, high) - 1)
    end
    local magazine = weapon ~= nil and weapon.getMaxAmmo ~= nil and tonumber(weapon:getMaxAmmo()) or nil
    if magazine ~= nil and magazine > 0 then
        high = math.min(high, math.floor(magazine / 5) + 1)
    end
    high = math.max(low, high)
    local rounds = low
    if type(ZombRand) == "function" then
        local span = high - low + 1
        rounds = low + math.floor((ZombRand(span) + ZombRand(span)) / 2)
    end
    if target ~= nil and not Combat.targetIsHuman(target) then
        rounds = math.min(rounds, tonumber(s.zombieBurstCap) or 3)
    end
    return rounds
end

function Combat.aimScaleFor(shell, target)
    local kind = nil
    pcall(function()
        if instanceof(target, "IsoPlayer") then kind = "player"
        elseif instanceof(target, "IsoZombie") then

            local data = target:getModData()
            kind = (type(data) == "table" and data.ProjectALifeActor == true)
                and "actor" or "zombie"
        end
    end)
    if kind ~= "player" and kind ~= "zombie" then return 1 end

    local own = nil
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        own = tonumber(kind == "player"
            and data.ProjectALifeAimPlayerPercent
            or data.ProjectALifeAimZombiePercent)
    end)
    local settings = ProjectALife.Settings
    local world = settings ~= nil and settings.current or nil
    local worldPercent = type(world) == "table"
        and tonumber(kind == "player" and world.aimPlayerPercent or world.aimZombiePercent) or nil

    local percent
    if kind == "player" then
        local global = type(world) == "table" and tonumber(world.aimPlayerGlobalPercent) or 100
        percent = (own or 100) * (worldPercent or 100) / 100 * global / 100
    else
        percent = own or worldPercent or 100
    end
    if percent < 1 then percent = 1 elseif percent > 300 then percent = 300 end
    return percent / 100
end

function Combat.aimRamp(shell, target, distance)
    local s = Combat.settings or {}
    local data = Combat.dataOf(shell)
    if data == nil then return 1 end
    local now = Combat.nowMs()
    local key = tostring(target)
    if type(target.getOnlineID) == "function" then key = "p" .. tostring(target:getOnlineID()) end
    local last = tonumber(data.ProjectALifeAimRampLastMs)
    if data.ProjectALifeAimRampKey ~= key or last == nil or now - last > (tonumber(s.aimRampGapMs) or 15000) then
        data.ProjectALifeAimRampKey = key
        data.ProjectALifeAimRampStartMs = now
    end
    data.ProjectALifeAimRampLastMs = now
    local floor = tonumber(s.aimRampFloor) or 0.5
    local span = math.max(1, tonumber(s.aimRampMs) or 5000)
    local age = math.max(0, now - (tonumber(data.ProjectALifeAimRampStartMs) or now))
    local scale = floor + (1 - floor) * math.min(1, age / span)
    local start = tonumber(s.aimFarStart) or 8
    local d = tonumber(distance) or 0
    if d > start then
        scale = scale * math.max(tonumber(s.aimFarFloor) or 0.65, 1 - (d - start) * (tonumber(s.aimFarStep) or 0.025))
    end
    local fast = type(target.isSprinting) == "function" and target:isSprinting() == true
        or type(target.isRunning) == "function" and target:isRunning() == true
    if fast then
        scale = scale * (tonumber(s.aimRunningScale) or 0.78)
    elseif type(target.isPlayerMoving) == "function" and target:isPlayerMoving() == true then
        scale = scale * (tonumber(s.aimMovingScale) or 0.9)
    end
    return scale
end

Combat.weaponSwapDwellMs = 2000

function Combat.swapHeld(shell, now)
    local data = Combat.dataOf(shell)
    return data ~= nil and now < (tonumber(data.ProjectALifeNextSwapAtMs) or 0)
end

function Combat.noteSwap(shell, now)
    local data = Combat.dataOf(shell)
    if data ~= nil then data.ProjectALifeNextSwapAtMs = now + Combat.weaponSwapDwellMs end
end

function Combat.drawsOnHuman(weapon, wanted, target)
    return weapon ~= nil and wanted ~= nil and wanted ~= weapon
        and not Combat.isRanged(weapon) and Combat.isRanged(wanted)
        and Combat.kindOf(target) ~= "zombie"
end

function Combat.preferredWeapon(shell, weapon, target, distance, facts, actor)
    if distance == nil then return nil end

    if Combat.swapHeld(shell, Combat.nowMs())
            and not Combat.drawsOnHuman(weapon, Weapons.bestReloadableRanged(shell), target) then return nil end
    local ranged = Combat.isRanged(weapon)
    local disciplined = type(facts) == "table" and facts.targetKind == "zombie"
        and ProjectALife.GunDiscipline ~= nil
        and ProjectALife.GunDiscipline.holds(actor, shell, target, facts) == true
    if type(facts) == "table" and facts.targetKind == "zombie"
            and (disciplined or ((ProjectALife.GunDiscipline == nil or ProjectALife.GunDiscipline.switchOn(actor))
            and facts.outnumbered ~= true
            and (facts.mission ~= "guard" or facts.inTerritory ~= true)
            and facts.mission ~= "rescue" and facts.mission ~= "combat")) then
        local melee = Weapons.bestMelee(shell)
        if melee ~= nil then
            if melee ~= weapon then return melee end
            return nil
        end
    end
    if ranged then

        if Magazines.current(weapon) > 0 then return nil end
        local reloadable = Magazines.canReload(shell, weapon)
        if reloadable then return nil end

        local other = Weapons.bestReloadableRanged(shell)
        if other ~= nil and other ~= weapon then return other end
        return Weapons.bestMelee(shell)
    end

    return Weapons.bestReloadableRanged(shell)
end

function Combat.rangeClass(weapon, shell)
    if weapon == nil then return "rifle" end
    if Weapons.firesPellets(weapon) then return "shotgun" end
    local reload = ""
    pcall(function() reload = string.lower(tostring(weapon:getWeaponReloadType() or "")) end)
    if string.find(reload, "handgun", 1, true) or string.find(reload, "revolver", 1, true) then
        return "handgun"
    end
    local marksman = false
    if shell ~= nil then
        pcall(function() marksman = shell:getModData().ProjectALifeConduct == "sniper" end)
    end
    if not marksman and weapon.getWeaponPart ~= nil then
        pcall(function() marksman = weapon:getWeaponPart("Scope") ~= nil end)
    end
    return marksman and "marksman" or "rifle"
end

function Combat.effectiveRange(weapon, shell)
    local s, class = Combat.settings, Combat.rangeClass(weapon, shell)
    if class == "handgun" then return tonumber(s.handgunEffectiveRange) or 12 end
    if class == "shotgun" then return tonumber(s.shotgunEffectiveRange) or 8 end
    if class == "marksman" then return tonumber(s.marksmanEffectiveRange) or 30 end
    return tonumber(s.rifleEffectiveRange) or 20
end

function Combat.rangeFalloff(weapon, shell, distance)
    local effective = math.max(1, Combat.effectiveRange(weapon, shell))
    local over = (tonumber(distance) or 0) - effective
    if over <= 0 then return 1 end
    return math.max(0, 1 - over / effective)
end

function Combat.baseHitChance(weapon, shell, distance)
    local d = tonumber(distance) or 0
    if d <= 5 then return 10000 end
    if d <= 7 then return 9800 end
    local effective = math.max(9, Combat.effectiveRange(weapon, shell))
    local chance = 9800 - (4000 / (effective - 7)) * (d - 7)
    pcall(function()
        if weapon == nil or weapon.getHitChance == nil then return end
        local printed = tonumber(weapon:getHitChance())
        if printed ~= nil then
            chance = chance + math.max(-600, math.min(600, (printed - 40) * 20))
        end
    end)
    return math.floor(math.max(1500, math.min(9800, chance)))
end

function Combat.shotDescriptor(shell, target, weapon)
    local shot = { pellets = 1, spreadDegrees = 0 }
    local sx, sy, sz = Combat.xyzOf(shell)
    if sx == nil then return shot end
    shot.fromX, shot.fromY, shot.fromZ = sx, sy, sz
    local data = Combat.dataOf(shell)
    if data ~= nil then
        local ax, ay = tonumber(data.ProjectALifeAimAtX), tonumber(data.ProjectALifeAimAtY)
        if ax ~= nil and ay ~= nil then shot.toX, shot.toY = ax, ay end
    end
    local tx, ty = Combat.xyOf(target)
    if tx ~= nil then
        if shot.toX == nil then shot.toX, shot.toY = tx, ty end
        if target.getZ ~= nil then shot.toZ = target:getZ() end
    end
    shot.toZ = shot.toZ or shot.fromZ
    if weapon ~= nil then
        if weapon.getProjectileCount ~= nil then
            shot.pellets = math.max(1, math.floor(tonumber(weapon:getProjectileCount()) or 1))
        end
        if weapon.getProjectileSpread ~= nil then
            shot.spreadDegrees = math.deg(tonumber(weapon:getProjectileSpread()) or 0)
        end
    end
    return shot
end

function Combat.hitPartIndex(distance, roll)
    local r = tonumber(roll)
    if r == nil then
        if type(ZombRand) ~= "function" then return -1 end
        r = ZombRand(10000)
    end
    local d = math.max(0, tonumber(distance) or 0)
    local share = 1176 - math.floor(976 * math.min(1, math.max(0, (d - 6) / 24)))
    if r < share then return (r % 2 == 0) and 8 or 9 end
    local index = math.floor((r - share) * 15 / (10000 - share))
    if index >= 8 then index = index + 2 end
    return math.min(16, index)
end

function Combat.shotSounds(weapon)
    if weapon == nil then return nil, nil end
    local report, brass
    pcall(function()
        local swing = weapon:getSwingSound()
        if type(swing) == "string" and swing ~= "" then report = swing end
    end)
    pcall(function()
        if weapon:isManuallyRemoveSpentRounds() then return end
        local shell = weapon:getShellFallSound()
        if type(shell) == "string" and shell ~= "" then brass = shell end
    end)
    return report, brass
end

Combat.shotLight = {
    reportToRadius = 0.04,
    minimumRadius = 3,
    maximumRadius = 8,
    keylessReport = 35,
}

Combat.flashKinds = {
    { match = "cap_gun", flash = 3, muzzle = 0.5 },
    { match = "sawed_off", flash = 17, muzzle = 0.7 },
    { match = "shotgun", flash = 15, muzzle = 0.95 },
    { match = "assault_rifle", flash = 12, muzzle = 0.95 },
    { match = "hunting_rifle", flash = 12, muzzle = 1.0 },
    { match = "varmint", flash = 11, muzzle = 0.95 },
    { match = "sniper", flash = 13, muzzle = 1.1 },
    { match = "m14", flash = 12, muzzle = 0.95 },
    { match = "revolver_long", flash = 10, muzzle = 0.7 },
    { match = "revolver_short", flash = 8, muzzle = 0.5 },
    { match = "revolver", flash = 9, muzzle = 0.55 },
    { match = "handgun", flash = 9, muzzle = 0.55 },
    { match = "smg", flash = 11, muzzle = 0.8 },
    { match = "rifle", flash = 12, muzzle = 0.95 },
}
Combat.suppressorWords = { "silenc", "suppress", "muffl" }
Combat.suppressedRadius = 25
Combat.flashProfileTtlMs = 2000
Combat.flashProfiles = setmetatable({}, { __mode = "k" })

Combat.missSound = "BulletImpact"

function Combat.flashKey(weapon)
    local key = ""
    pcall(function()
        local model = weapon:getMuzzleFlashModelKey()
        if model == nil then return end
        local text
        if type(model.id) == "function" then text = model:id() end
        if type(text) ~= "string" then text = tostring(model) end
        key = string.lower(text)
    end)
    return key
end

function Combat.isSuppressed(weapon, key)
    if string.find(key, "cap_gun", 1, true) then return false end
    local suppressed = false
    pcall(function()
        local parts = weapon:getAllWeaponParts()
        if parts == nil then return end
        for index = 0, parts:size() - 1 do
            local name = string.lower(tostring(parts:get(index):getFullType()))
            for _, word in ipairs(Combat.suppressorWords) do
                if string.find(name, word, 1, true) then suppressed = true end
            end
        end
    end)
    if suppressed then return true end
    pcall(function()
        local current = tonumber(weapon:getSoundRadius())
        if current == nil then return end
        local base = tonumber(weapon:getScriptItem():getSoundRadius())
        if base ~= nil and base > 0 and current <= base * 0.5 then
            suppressed = true
        elseif current <= Combat.suppressedRadius then
            suppressed = true
        end
    end)
    return suppressed
end

function Combat.flashProfile(weapon)
    local cached = Combat.flashProfiles[weapon]
    local now = Combat.nowMs()
    if cached ~= nil and now < cached.untilMs then return cached end
    local key = Combat.flashKey(weapon)
    local report = 0
    pcall(function() report = tonumber(weapon:getSoundRadius()) or 0 end)
    local look = Combat.shotLight
    local profile = { flash = 0, light = 0, muzzle = 60, suppressed = false,
        untilMs = now + Combat.flashProfileTtlMs }
    if key ~= "" or report >= look.keylessReport then
        local flash, muzzle = math.max(6, math.min(16, math.floor(report / 12 + 0.5))), 0.7
        for _, kind in ipairs(Combat.flashKinds) do
            if string.find(key, kind.match, 1, true) then
                flash, muzzle = kind.flash, kind.muzzle
                break
            end
        end
        profile.suppressed = Combat.isSuppressed(weapon, key)
        if not profile.suppressed then
            local radius = math.max(look.minimumRadius,
                math.min(look.maximumRadius, report * look.reportToRadius))
            profile.flash = flash
            profile.muzzle = math.floor(muzzle * 100 + 0.5)
            profile.light = math.floor(math.min(look.maximumRadius + 1, radius * (0.6 + 0.04 * flash)) + 0.5)
        end
    end
    Combat.flashProfiles[weapon] = profile
    return profile
end

function Combat.hundredths(value)
    return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

function Combat.shotEvent(shell, weapon, aim, withSound)
    local shot = Combat.shotDescriptor(shell, aim, weapon)
    if shot.fromX == nil or shot.toX == nil then return nil end
    local look = Combat.flashProfile(weapon)
    local event = {
        x = Combat.hundredths(shot.fromX), y = Combat.hundredths(shot.fromY),
        z = math.floor(tonumber(shot.fromZ) or 0),
        ax = Combat.hundredths(shot.toX), ay = Combat.hundredths(shot.toY),
        pel = shot.pellets, fl = look.flash, lr = look.light, mz = look.muzzle,
        sp = look.suppressed and 1 or 0,
        gn = tonumber(Combat.settings.gunshotGain) or 1,
        owner = Interop.uidOf(shell),
    }
    if weapon ~= nil and type(weapon.getFullType) == "function" then
        local ok, value = pcall(weapon.getFullType, weapon)
        if ok and type(value) == "string" then event.weapon = value end
    end
    if withSound == true then event.sw, event.br = Combat.shotSounds(weapon) end
    return event
end

function Combat.routeShotFx(shell, event)
    local server = type(isServer) == "function" and isServer() == true
    local fx = ProjectALife.Tracer
    if not server and fx ~= nil and type(fx.show) == "function" then
        pcall(fx.show, event, false)
    end
    local executor = ProjectALife.Executor
    if executor == nil then return false end
    if executor.executorSide() then
        return pcall(executor.relayShotFx, shell, event) == true
    end
    if server then
        event.sw, event.br = nil, nil
        local message = executor.shotFxPayload(event)
        if message ~= nil then executor.broadcastShotFx(message, nil) end
        return message ~= nil
    end
    return false
end

function Combat.presentShot(shell, weapon, aim, withSound)
    if shell == nil or weapon == nil then return false end
    local event = Combat.shotEvent(shell, weapon, aim, withSound)
    if event == nil then return false end
    Combat.routeShotFx(shell, event)
    return true
end

function Combat.missCue(target)
    if target == nil then return false end
    return pcall(function()
        if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
            sendPlaySound(Combat.missSound, false, target)
            return
        end
        local square = target:getSquare()
        if square ~= nil then square:playSound(Combat.missSound) end
    end) == true
end

local function closestListenerDistance(shell)
    local best
    pcall(function()

        local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
        for index = 0, math.max(1, tonumber(count) or 1) - 1 do
            local player = getSpecificPlayer(index)
            if player ~= nil and player:isAlive()
                    and player:getCurrentSquare() ~= nil then
                local dx = player:getX() - shell:getX()
                local dy = player:getY() - shell:getY()

                local dz = (player:getZ() - shell:getZ()) * 3.0
                local flat = math.sqrt(dx * dx + dy * dy + dz * dz)
                if best == nil or flat < best then best = flat end
            end
        end
    end)
    return best
end

function Combat.shotParameters(distance, inRoom, sameRoom, roomArea)

    if tonumber(distance) == nil then return nil end
    local inside = 0
    if inRoom == true then inside = sameRoom == true and 1 or -1 end
    return {
        FirearmDistance = math.max(0, math.min(1000, tonumber(distance) or 1000)),
        FirearmInside = inside,
        FirearmRoomSize = math.max(0, math.min(1000, tonumber(roomArea) or 0)),

        LocalPlayer = 0,
    }
end

local function playAt(shell, sound)
    if type(sound) ~= "string" or sound == "" then return false end
    local dedicated = type(isServer) == "function" and isServer()
    if dedicated and type(sendPlaySound) == "function" then
        return pcall(sendPlaySound, sound, false, shell) == true
    end
    local handle, emitter
    local played = pcall(function()
        emitter = shell:getEmitter()
        handle = emitter:playSound(sound)
    end)
    if not played then return false end

    pcall(function()
        local gain = tonumber(Combat.settings.gunshotGain) or 1
        if gain ~= 1 and handle ~= nil then emitter:setVolume(handle, gain) end
    end)
    pcall(function()
        local square = shell:getSquare()
        local room = square ~= nil and square:getRoom() or nil
        local area, same = 0, false
        if room ~= nil then
            local definition = room:getRoomDef()
            if definition ~= nil then area = definition:getArea() end

            local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
            for index = 0, math.max(1, tonumber(count) or 1) - 1 do
                local player = getSpecificPlayer(index)
                local here = player ~= nil and player:getCurrentSquare() or nil
                if here ~= nil and here:getRoom() == room then same = true end
            end
        end
        local parameters = Combat.shotParameters(
            closestListenerDistance(shell), room ~= nil, same, area)
        if parameters == nil then return end
        for name, value in pairs(parameters) do
            emitter:setParameterValueByName(handle, name, value)
        end
    end)
    return true
end

function Combat.worldNoise(shell, radius, volume, kind)
    if shell == nil or type(addSound) ~= "function" then return false end
    if kind == "shot" then
        local policy = ProjectALife.ZombieRetarget
        if policy ~= nil and policy.noiseVerdict(shell, Combat.nowMs()) ~= "emit" then
            Combat.metrics = Combat.metrics or {}
            Combat.metrics.noiseCoalesced = (Combat.metrics.noiseCoalesced or 0) + 1
            return true
        end
    end
    radius = math.max(0, math.floor(tonumber(radius) or 12))
    volume = math.max(0, math.floor(tonumber(volume) or 20))
    local multiplier = 1
    pcall(function()
        local option = getSandboxOptions():getOptionByName("FirearmNoiseMultiplier")
        if option ~= nil then multiplier = tonumber(option:getValue()) or 1 end
    end)
    local outside = true
    pcall(function() outside = shell:isOutside() ~= false end)
    local scale = 100
    local gate = ProjectALife.FeatureGate
    if kind == "shot" and gate ~= nil and type(gate.number) == "function" then
        scale = gate.number("Combat_NpcShotNoisePercent", 100, 10, 100)
    end
    radius = math.floor(radius * multiplier * scale / 100 * (outside and 1 or 0.5))
    local x, y, z = 0, 0, 0
    local positioned = pcall(function() x, y, z = math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ()) end)
    if not positioned then return false end

    local heard = false
    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.executorSide) == "function" and executor.executorSide() then
        if type(executor.relayNoise) == "function" then
            local relayed, sent = pcall(executor.relayNoise, shell, x, y, z, radius, volume)
            heard = relayed and sent == true
        end
    else
        heard = pcall(addSound, nil, x, y, z, radius, volume)
    end
    Combat.metrics = Combat.metrics or {}
    if heard then
        Combat.metrics.worldNoise = (Combat.metrics.worldNoise or 0) + 1
    else
        Combat.metrics.noiseRefused = (Combat.metrics.noiseRefused or 0) + 1
    end
    return true
end

local function reportSound(shell, weapon)
    local report, brass = Combat.shotSounds(weapon)
    playAt(shell, report)

    local fx = ProjectALife.Tracer
    local clientFx = type(isServer) ~= "function" or isServer() ~= true
    if not (clientFx and fx ~= nil and type(fx.show) == "function") then playAt(shell, brass) end
    local radiusOk, radius = pcall(function() return weapon:getSoundRadius() end)
    local volumeOk, volume = pcall(function() return weapon:getSoundVolume() end)
    Combat.worldNoise(shell, radiusOk and radius or 12, volumeOk and volume or 20, "shot")
end

Combat.vehicleCoverRadius = 2.0   
Combat.vehicleReach = 8           

Combat.vehicleCache, Combat.vehicleCacheUntilMs = nil, 0
Combat.vehicleCacheMs = 500

function Combat.vehicleList()
    local now = Combat.nowMs()
    if Combat.vehicleCache ~= nil and now < Combat.vehicleCacheUntilMs then
        return Combat.vehicleCache
    end
    local list = {}
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local vehicles = cell:getVehicles()
        if vehicles == nil or vehicles.toArray == nil then return end
        for _, vehicle in pairs(vehicles:toArray()) do
            local ok, vx, vy = pcall(function() return vehicle:getX(), vehicle:getY() end)
            if ok and tonumber(vx) ~= nil and tonumber(vy) ~= nil then
                list[#list + 1] = { x = vx, y = vy, vehicle = vehicle }
            end
        end
    end)
    Combat.vehicleCache, Combat.vehicleCacheUntilMs = list, now + Combat.vehicleCacheMs
    return list
end

function Combat.pointOnSegment(points, ax, ay, bx, by, radius)
    local dx, dy = bx - ax, by - ay
    local length = dx * dx + dy * dy
    if length < 0.01 then return false end
    for _, point in ipairs(points or {}) do
        local along = ((point.x - ax) * dx + (point.y - ay) * dy) / length
        if along > 0 and along < 1 then
            local px, py = ax + dx * along, ay + dy * along
            if (point.x - px) ^ 2 + (point.y - py) ^ 2 <= radius * radius then return true end
        end
    end
    return false
end

function Combat.nearSegment(point, ax, ay, bx, by, radius)
    local dx, dy = bx - ax, by - ay
    local length = dx * dx + dy * dy
    local along = 0
    if length > 0 then
        along = math.max(0, math.min(1, ((point.x - ax) * dx + (point.y - ay) * dy) / length))
    end
    local px, py = ax + dx * along, ay + dy * along
    return (point.x - px) ^ 2 + (point.y - py) ^ 2 <= radius * radius
end

function Combat.vehicleOnLine(shell, target)
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(target)
    if sx == nil or tx == nil then return false end
    return Combat.vehicleBlocks(sx, sy, sz, tx, ty, tz)
end

function Combat.vehicleBlocks(sx, sy, sz, tx, ty, tz)
    if math.floor(sz or 0) ~= 0 or math.floor(tz or 0) ~= 0 then return false end
    local list = Combat.vehicleList()
    if #list == 0 then return false end
    for _, entry in ipairs(list) do
        local vehicle = entry.vehicle
        local crossed = false
        if Combat.nearSegment(entry, sx, sy, tx, ty, Combat.vehicleReach) then
            if vehicle ~= nil and vehicle.intersectLineWithPoly ~= nil and Vector2f ~= nil then
                Combat.vehicleIntersection = Combat.vehicleIntersection or Vector2f.new()
                local checked, hit = pcall(function()
                    if math.floor(vehicle:getZ()) ~= math.floor(sz) then return false end
                    return vehicle:intersectLineWithPoly(sx, sy, tx, ty, Combat.vehicleIntersection)
                end)
                crossed = checked and hit == true
            else
                crossed = Combat.pointOnSegment({ entry }, sx, sy, tx, ty, Combat.vehicleCoverRadius)
            end
        end

        if crossed and not (ProjectALife.VehicleRules ~= nil
                and type(ProjectALife.VehicleRules.passesFire) == "function"
                and ProjectALife.VehicleRules.passesFire(vehicle, sx, sy, sz, tx, ty, tz) == true) then
            return true
        end
    end
    return false
end

Combat.reportSound = reportSound

return Combat
