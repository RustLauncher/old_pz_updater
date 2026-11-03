ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Shells/ALifeWounds"
if type(isServer) ~= "function" or isServer() ~= true then
    require "ProjectALife/Combat/ALifeHordeRelations"
end

local Registry = ProjectALife.ModuleRegistry

local Gunner = {
    id = "gunner",
    settings = {

        magdumpMs = 4000,

        rifleCadenceMs = 95,
        handgunCadenceMs = 140,

        reportIntervalMs = 300,

        spreadTiles = 1.6,

        damageScale = 0.6,

        dumpMagazineShare = 1 / 3,
        dumpFloorRounds = 2,

        cooldownMs = 12000,

        automaticCadenceScale = 1.35,
        singleFireCadenceMs = 450,

        trackingCadenceScale = 1.0,

        trackingWindowMs = 1500,

        trackingCooldownMs = 600,

        trackingBlindMs = 1200,
    },
    metrics = { orders = 0, rounds = 0, bodiesHit = 0,

        tracked = 0, endedTargetDown = 0, endedDry = 0, endedBlind = 0 },

    targets = setmetatable({}, { __mode = "v" }),
    adapters = {},
}
ProjectALife.ModuleGunner = Gunner

local function nowMsFallback()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

function Gunner.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Gunner.settings[key] ~= nil and tonumber(value) ~= nil then
            Gunner.settings[key] = tonumber(value)
        end
    end
    return true
end

function Gunner.enoughToDump(rounds, capacity)
    local s = Gunner.settings
    local need = math.max(s.dumpFloorRounds, math.ceil((tonumber(capacity) or 0) * s.dumpMagazineShare))
    return (tonumber(rounds) or 0) >= need
end

function Gunner.cadenceFor(automatic, intervalMs, tracked)
    if automatic == true then
        local scale = tracked == true and Gunner.settings.trackingCadenceScale
            or Gunner.settings.automaticCadenceScale
        return math.max(50, math.floor((tonumber(intervalMs) or 100) * scale))
    end
    return Gunner.settings.singleFireCadenceMs
end

local function weaponAutomatic(weapon)
    local automatic, interval = false, 100
    pcall(function()
        local weapons = ProjectALife.Weapons
        if weapons == nil then return end
        automatic = weapons.isAutomatic(weapon) == true
        interval = tonumber(weapons.fireIntervalMs(weapon)) or interval
    end)
    return automatic, interval
end

local function lineToPoint(shell, x, y, z)
    if type(Gunner.adapters.lineToPoint) == "function" then return Gunner.adapters.lineToPoint(shell, x, y, z) ~= false end
    local lineOfFire = ProjectALife.LineOfFire
    if lineOfFire == nil or type(lineOfFire.hasClearBoundary) ~= "function" then return true end
    local point = { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end }
    return lineOfFire.hasClearBoundary(shell, point) == true
end

function Gunner.targetAlive(body, stamp)
    if body == nil then return false end
    if not ProjectALife.TargetPolicy.canAttack(body, stamp) then return false end
    local alive = false
    pcall(function()
        if body.isDead ~= nil and body:isDead() == true then return end
        if body.getHealth ~= nil and (tonumber(body:getHealth()) or 0) <= 0 then return end
        alive = true
    end)
    return alive
end

function Gunner.beyondPlayerReach(shell, body)
    local combat = ProjectALife.Combat
    if combat == nil or type(combat.playerFireReach) ~= "function" then return false end
    local far = false
    pcall(function()
        local reach = combat.playerFireReach(shell, body)
        far = reach ~= nil
            and (shell:getX() - body:getX()) ^ 2 + (shell:getY() - body:getY()) ^ 2 > reach * reach
    end)
    return far
end

function Gunner.order(actor, shell, target, now)
    if type(actor) ~= "table" or shell == nil or target == nil then return false end
    if not Registry.allows(actor, "gunner") then return false end
    now = tonumber(now) or nowMsFallback()

    local tx, ty, tz
    local body = nil
    pcall(function()
        if type(target) == "table" and target.getX == nil then
            tx, ty, tz = tonumber(target.x), tonumber(target.y), tonumber(target.z)
        else
            tx, ty, tz = target:getX(), target:getY(), target:getZ()
            body = target
        end
    end)
    if tx == nil or ty == nil then return false end

    if body ~= nil and not Gunner.targetAlive(body) then return false end

    if body ~= nil then
        if Gunner.zombieBody(body) then return false end
        local conduct
        pcall(function() conduct = shell:getModData().ProjectALifeConduct end)
        if tostring(conduct or "") ~= "gunner" then return false end
        if Gunner.beyondPlayerReach(shell, body) then return false end
    end
    local wrote = false
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        if now < (tonumber(data.ProjectALifeSuppressCooldownUntilMs) or 0) then return end
        local carry = tostring(data.ProjectALifeWeaponClass or "")

        if carry ~= "rifle" then return end
        local weapon = shell:getPrimaryHandItem()
        if weapon == nil then return end

        local racks = true
        pcall(function()
            local weapons = ProjectALife.Weapons
            if weapons ~= nil and type(weapons.racksAfterShot) == "function" then
                racks = weapons.racksAfterShot(weapon) == true
            end
        end)
        if racks then return end

        if data.ProjectALifeHealDoneAtMs ~= nil then return end

        if Gunner.heldTrigger(data, now) then return end
        local rounds, capacity = 0, 0
        pcall(function() rounds = weapon:getCurrentAmmoCount() or 0 end)
        pcall(function() capacity = weapon:getMaxAmmo() or 0 end)
        if not Gunner.enoughToDump(rounds, capacity) then return end
        if not lineToPoint(shell, tx, ty, tz) then return end
        local automatic, interval = weaponAutomatic(weapon)
        local cadence = Gunner.cadenceFor(automatic, interval, body ~= nil)
        data.ProjectALifeSuppressX = tx
        data.ProjectALifeSuppressY = ty
        data.ProjectALifeSuppressZ = tz or 0

        if body ~= nil then
            Gunner.targets[actor.uid] = body
            data.ProjectALifeSuppressTargetIdentity = ProjectALife.TargetPolicy.identity(body)
            data.ProjectALifeSuppressTracking = true
            data.ProjectALifeSuppressBlindSinceMs = nil
            data.ProjectALifeSuppressUntilMs = now + Gunner.settings.trackingWindowMs
            data.ProjectALifeSuppressCooldownUntilMs = now + Gunner.settings.trackingCooldownMs
            Gunner.metrics.tracked = Gunner.metrics.tracked + 1
        else
            Gunner.targets[actor.uid] = nil
            data.ProjectALifeSuppressTargetIdentity = nil
            data.ProjectALifeSuppressTracking = nil
            data.ProjectALifeSuppressUntilMs = now + (automatic and Gunner.settings.magdumpMs
                or (rounds * cadence + 500))
            data.ProjectALifeSuppressCooldownUntilMs = now + Gunner.settings.cooldownMs
        end
        data.ProjectALifeSuppressNextShotAtMs = now
        data.ProjectALifeSuppressCadenceMs = cadence
        data.ProjectALifeSuppressAutomatic = automatic or nil
        data.ProjectALifeSuppressOwnerUid = actor.uid

        data.ProjectALifeAimAtX = data.ProjectALifeSuppressX
        data.ProjectALifeAimAtY = data.ProjectALifeSuppressY
        data.ProjectALifeAimWalk = true

        pcall(function()
            local animations = ProjectALife.Animations
            if animations ~= nil then
                pcall(animations.setCombatHold, shell, true)
                animations.apply(shell, carry == "handgun"
                    and "ready_handgun" or "ready_rifle")
            end
        end)
        Gunner.metrics.orders = Gunner.metrics.orders + 1
        wrote = true
        pcall(function()
            local voice = ProjectALife.Voice
            if voice ~= nil then voice.play(shell, "SUPPRESS_FIRE") end
        end)
    end)
    return wrote
end

function Gunner.marked(data)
    return type(data) == "table" and (data.ProjectALifeOwned == true
        or data.ProjectALifeActor == true or type(data.ProjectALifeUID) == "string")
end

function Gunner.zombieBody(body)
    if body == nil or type(instanceof) ~= "function" or not instanceof(body, "IsoZombie") then return false end
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return true end
    if type(body.getModData) ~= "function" then return true end
    local ok, data = pcall(body.getModData, body)
    return not (ok and Gunner.marked(data))
end

function Gunner.hitZombie(shell, weapon, body)
    local guard = ProjectALife.AIFence
    if guard == nil or type(guard.drivesBody) ~= "function"
            or guard.drivesBody(shell) ~= true then return false end
    if body == nil or shell == nil or type(body.Hit) ~= "function"
            or type(body.getTarget) ~= "function" or type(body.setTarget) ~= "function"
            or type(body.isRemoteZombie) ~= "function"
            or type(shell.getVariableString) ~= "function" or type(shell.setVariable) ~= "function" then
        return false
    end
    if type(isClient) == "function" and isClient()
            and body:isRemoteZombie() == true then return false end
    local horde = ProjectALife.HordeRelations
    if horde == nil or type(horde.clearNativeActorTarget) ~= "function"
            or type(horde.isPlayer) ~= "function" then return false end
    local previous = body:getTarget()
    local reaction = shell:getVariableString("ZombieHitReaction")
    local lowered = string.lower(tostring(reaction or ""))
    if lowered == "shot" then shell:setVariable("ZombieHitReaction", "") end
    local ok, result = pcall(body.Hit, body, weapon, shell, 0.55, false, 1, false)
    if lowered == "shot" then shell:setVariable("ZombieHitReaction", reaction) end
    horde.clearNativeActorTarget(body)
    if previous ~= nil and horde.isPlayer(previous) and body:getTarget() == nil then
        body:setTarget(previous)
    end
    return ok, result
end

local function strikeBody(shell, weapon, body, ownerUid)
    Gunner.metrics.bodiesHit = Gunner.metrics.bodiesHit + 1
    local isPlayer = false
    pcall(function() isPlayer = instanceof(body, "IsoPlayer") == true end)
    if isPlayer then
        Gunner.grazePlayer(shell, weapon, body)
        return
    end
    local owned = false
    pcall(function()
        owned = Gunner.marked(body:getModData())
    end)
    if owned then
        if type(isClient) == "function" and isClient() then
            return ProjectALife.NPCHitRelay.request(shell, body, weapon)
        end
        pcall(function()
            local damage = ProjectALife.HumanDamage
            if damage ~= nil then
                damage.apply(shell, body, weapon, Gunner.settings.damageScale)
            end
            local perception = ProjectALife.Perception
            local victimUid = body:getModData().ProjectALifeUID
            if perception ~= nil and type(perception.noteAttacker) == "function"
                    and type(victimUid) == "string" then
                perception.noteAttacker(victimUid, shell, 5000, "actor")
            end
        end)
    else
        pcall(function()
            Gunner.hitZombie(shell, weapon, body)
        end)
    end
end

function Gunner.whizz(body)
    if body == nil then return false end
    local meta = ProjectALife.MetaEvents
    local name = meta and meta.sounds and meta.sounds.roundWhizz
    if type(name) ~= "string" then return false end
    local played = false
    pcall(function()
        if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
            sendPlaySound(name, false, body)
        else
            body:playSound(name)
        end
        played = true
    end)
    return played
end

function Gunner.voice(shell, sound)
    if type(sound) ~= "string" or sound == "" then return false end
    local dedicated = type(isServer) == "function" and isServer()
    if dedicated and type(sendPlaySound) == "function" then
        return pcall(sendPlaySound, sound, false, shell) == true
    end
    return pcall(function() shell:playSound(sound) end) == true
end

function Gunner.grazePlayer(shell, weapon, body)
    if body == nil or weapon == nil then return false end
    Gunner.whizz(body)

    if Gunner.beyondPlayerReach(shell, body) then return false end
    local grazed = type(ZombRand) ~= "function" or ZombRand(5) == 0
    if not grazed then return false end

    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.relayPlayerHit) == "function"
            and type(executor.clientAuthority) == "function" and executor.clientAuthority() then
        local registry, uid = ProjectALife.ActorRegistry, nil
        pcall(function() uid = shell:getModData().ProjectALifeUID end)
        local actor = registry ~= nil and type(uid) == "string" and registry.read(uid) or nil
        if type(actor) ~= "table" then return false end
        local weaponType
        pcall(function() weaponType = tostring(weapon:getFullType()) end)
        return executor.relayPlayerHit(actor, body, weaponType) == true
    end
    local applied = false
    pcall(function()
        local bodyDamage = body:getBodyDamage()
        if bodyDamage == nil then return end
        local part, combat = -1, ProjectALife.Combat
        if combat ~= nil and type(combat.hitPartIndex) == "function" then
            part = combat.hitPartIndex(math.sqrt((shell:getX() - body:getX()) ^ 2
                + (shell:getY() - body:getY()) ^ 2))
        end
        applied = ProjectALife.Wounds.damagePlayer(bodyDamage, weapon, part) == true
        if not applied then return end

        if type(isServer) == "function" and isServer()
                and type(sendDamage) == "function" then
            sendDamage(body)
        end
    end)
    return applied
end

local function mayStrike(body, ownerUid)
    local protected = false
    pcall(function()
        local data = body:getModData()
        if not Gunner.marked(data) then return end

        protected = true
        local registry = ProjectALife.ActorRegistry
        local relations = ProjectALife.Relations
        if registry == nil or relations == nil then return end
        local owner = registry.read(tostring(ownerUid or ""))
        local victim = registry.read(tostring(data.ProjectALifeUID or ""))
        if owner == nil or victim == nil then return end
        protected = relations.hostile(owner, victim) ~= true
    end)
    return not protected
end

local function fireOne(shell, data, now)
    local weapon
    pcall(function() weapon = shell:getPrimaryHandItem() end)
    if weapon == nil then return false end
    local rounds = 0
    pcall(function() rounds = weapon:getCurrentAmmoCount() or 0 end)
    if rounds <= 0 then return false end
    local magazines = ProjectALife.MagazineState
    if magazines ~= nil and type(magazines.consumeRound) == "function" then
        if magazines.consumeRound(shell, weapon) ~= true then return false end
    end
    local relay = ProjectALife.NPCHitRelay
    if relay ~= nil then
        relay.beginAttack(shell)
        relay.prepareAttack(shell, weapon)
    end
    Gunner.metrics.rounds = Gunner.metrics.rounds + 1

    local spread = data.ProjectALifeManeuverPin ~= nil and 0 or Gunner.settings.spreadTiles
    local jitterX = (roll(2001) - 1000) / 1000 * spread
    local jitterY = (roll(2001) - 1000) / 1000 * spread
    local ghost = {
        x = (tonumber(data.ProjectALifeSuppressX) or 0) + jitterX,
        y = (tonumber(data.ProjectALifeSuppressY) or 0) + jitterY,
        z = tonumber(data.ProjectALifeSuppressZ) or 0,
    }
    function ghost.getX() return ghost.x end
    function ghost.getY() return ghost.y end
    function ghost.getZ() return ghost.z end

    data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = ghost.x, ghost.y
    local faced = false
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then
            faced = guard.faceAimPoint(shell, ghost.x, ghost.y, now) == true
        end
    end)
    if not faced then pcall(function() shell:faceLocationF(ghost.x, ghost.y) end) end

    if data.ProjectALifeSuppressPosed ~= true or data.ProjectALifeSuppressAutomatic ~= true then
        data.ProjectALifeSuppressPosed = true
        pcall(function()
            local animations = ProjectALife.Animations
            local combat = ProjectALife.Combat
            if animations == nil or combat == nil then return end

            pcall(animations.setCombatHold, shell, true)
            animations.apply(shell, combat.shotPresetFor(shell))
        end)
    end

    local combat = ProjectALife.Combat
    local reported = false
    if Gunner.reportDue(data, now) then
        data.ProjectALifeSuppressReportMs = now
        reported = true
        local report, brass
        if combat ~= nil and type(combat.shotSounds) == "function" then
            report, brass = combat.shotSounds(weapon)
        end
        Gunner.voice(shell, report)
        local clientFx = type(isServer) ~= "function" or isServer() ~= true
        if not (clientFx and ProjectALife.Tracer ~= nil) then Gunner.voice(shell, brass) end
    end
    pcall(function()

        if combat == nil or type(combat.worldNoise) ~= "function" then return end
        combat.worldNoise(shell, tonumber(weapon:getSoundRadius()) or 12, tonumber(weapon:getSoundVolume()) or 20, "shot")
    end)

    if combat ~= nil and type(combat.presentShot) == "function" then
        pcall(combat.presentShot, shell, weapon, ghost, reported)
    end

    if data.ProjectALifeSuppressReported ~= true then
        data.ProjectALifeSuppressReported = true
        pcall(function()
            local horde = ProjectALife.HordeRelations
            if horde ~= nil and type(horde.noteGunfire) == "function" then
                horde.noteGunfire(shell, tonumber(weapon:getSoundRadius()) or 20,
                    now + 7000)
            end
        end)
    end

    pcall(function()
        local lineOfFire = ProjectALife.LineOfFire
        if lineOfFire == nil then return end
        local ownerUid = data.ProjectALifeSuppressOwnerUid
        lineOfFire.resolve(shell, ghost, weapon,
            function(body) strikeBody(shell, weapon, body, ownerUid) end,
            function(body) return mayStrike(body, ownerUid) end)

        pcall(function()
            local panic = ProjectALife.ModulePanic
            local watchdog = ProjectALife.Watchdog
            if panic == nil or watchdog == nil then return end
            for uid, binding in pairs(watchdog.bindings) do
                local body = binding and binding.shell or nil
                if body ~= nil and uid ~= ownerUid then
                    local dx, dy = body:getX() - ghost.x, body:getY() - ghost.y
                    if dx * dx + dy * dy <= 4
                            and Gunner.sameStorey(body:getZ(), ghost.z)
                            and mayStrike(body, ownerUid) then panic.pin(body, now) end
                end
            end
        end)

        pcall(function()
            local cell = getCell()
            if cell == nil then return end
            local players = IsoPlayer.getPlayers()
            if players == nil then return end
            for index = 0, players:size() - 1 do
                local candidate = players:get(index)
                if candidate ~= nil and not candidate:isDead() then
                    local dx = candidate:getX() - ghost.x
                    local dy = candidate:getY() - ghost.y
                    if dx * dx + dy * dy <= 2.25
                            and Gunner.sameStorey(candidate:getZ(), ghost.z)
                            and Gunner.canReach(shell, candidate) then
                        Gunner.grazePlayer(shell, weapon, candidate)
                    end
                end
            end
        end)
    end)
    return true
end

function Gunner.sameStorey(a, b)
    return math.floor(tonumber(a) or 0) == math.floor(tonumber(b) or 0)
end

function Gunner.canReach(shell, candidate)
    local lineOfFire = ProjectALife.LineOfFire
    if lineOfFire == nil or type(lineOfFire.hasClearBoundary) ~= "function" then
        return false
    end
    local ok, clear = pcall(lineOfFire.hasClearBoundary, shell, candidate)
    if not ok or clear ~= true then return false end

    local combat = ProjectALife.Combat
    if combat == nil or type(combat.vehicleOnLine) ~= "function" then return false end
    local checked, blocked = pcall(combat.vehicleOnLine, shell, candidate)
    return checked and blocked ~= true
end

function Gunner.heldTrigger(data, now)
    local holdUntil = tonumber(data.ProjectALifeHoldFireUntilMs)
    if holdUntil == nil or now >= holdUntil then return false end
    local hitAt = tonumber(data.ProjectALifeLastHitAtMs)
    if hitAt ~= nil and now - hitAt <= 4000 then
        data.ProjectALifeHoldFireUntilMs = nil
        return false
    end
    return true
end

function Gunner.reportDue(data, now)
    local last = tonumber(data.ProjectALifeSuppressReportMs)
    if last == nil then return true end
    return (tonumber(now) or 0) - last >= Gunner.settings.reportIntervalMs
end

function Gunner.maneuverPair(data)
    local tactics=ProjectALife.SquadTactics
    if type(data.ProjectALifeManeuverPin)~="string" then return nil end
    local pair=tactics and tactics.maneuvers and tactics.maneuvers[data.ProjectALifeManeuverPin]
    if pair==nil or pair.pinUid~=data.ProjectALifeUID or pair.pinGeneration~=data.ProjectALifeGeneration then return nil end
    return pair
end

function Gunner.tick(shell, data, now)
    local guard = ProjectALife.AIFence
    if guard == nil or type(guard.drivesBody) ~= "function"
            or guard.drivesBody(shell) ~= true then
        if data.ProjectALifeManeuverPin~=nil then ProjectALife.SquadTactics.clearManeuver(shell,"ownership") end
        return
    end
    local pair=Gunner.maneuverPair(data)
    if pair~=nil and pair.pin~=shell then pair=nil end
    if data.ProjectALifeManeuverPin ~= nil and pair==nil then
        data.ProjectALifeManeuverPin=nil
        Gunner.stop(data,shell)
        return
    end
    if pair ~= nil then
        if not ProjectALife.SquadTactics.maneuverValid(pair,now)
                or not ProjectALife.SquadTactics.pinSafe(pair,shell,pair.target) then
            ProjectALife.SquadTactics.clearManeuver(shell,"pin_invalid")
            return
        end
    end
    local untilMs = tonumber(data.ProjectALifeSuppressUntilMs)
    if untilMs == nil then return end
    if now >= untilMs then
        Gunner.stop(data, shell)
        return
    end

    if Gunner.heldTrigger(data, now) then return end

    local tracking = data.ProjectALifeSuppressTracking == true
    if tracking then
        local body = Gunner.targets[tostring(data.ProjectALifeSuppressOwnerUid or "")]
        if not Gunner.targetAlive(body, data.ProjectALifeSuppressTargetIdentity) then
            Gunner.metrics.endedTargetDown = Gunner.metrics.endedTargetDown + 1
            Gunner.stop(data, shell)
            return
        end

        if Gunner.beyondPlayerReach(shell, body) then
            Gunner.stop(data, shell)
            return
        end
        pcall(function()
            data.ProjectALifeSuppressX = body:getX()
            data.ProjectALifeSuppressY = body:getY()
            data.ProjectALifeSuppressZ = body:getZ()
            data.ProjectALifeAimAtX = data.ProjectALifeSuppressX
            data.ProjectALifeAimAtY = data.ProjectALifeSuppressY
        end)
        data.ProjectALifeSuppressUntilMs = now + Gunner.settings.trackingWindowMs
    end

    if now < (tonumber(data.ProjectALifeSuppressNextShotAtMs) or 0) then return end

    if not lineToPoint(shell, tonumber(data.ProjectALifeSuppressX) or 0,
            tonumber(data.ProjectALifeSuppressY) or 0, tonumber(data.ProjectALifeSuppressZ) or 0) then
        if not tracking then
            Gunner.stop(data, shell)
            return
        end
        local blindSince = tonumber(data.ProjectALifeSuppressBlindSinceMs)
        if blindSince == nil then
            data.ProjectALifeSuppressBlindSinceMs = now
        elseif now - blindSince >= Gunner.settings.trackingBlindMs then
            Gunner.metrics.endedBlind = Gunner.metrics.endedBlind + 1
            Gunner.stop(data, shell)
            return
        end
    else
        data.ProjectALifeSuppressBlindSinceMs = nil
    end
    if not fireOne(shell, data, now) then

        if tracking then Gunner.metrics.endedDry = Gunner.metrics.endedDry + 1 end
        Gunner.stop(data, shell)
        return
    end
    if pair ~= nil and Gunner.maneuverPair(data)==pair then pair.fired=true end
    data.ProjectALifeSuppressNextShotAtMs = now + (tonumber(data.ProjectALifeSuppressCadenceMs)
        or Gunner.settings.singleFireCadenceMs)
end

function Gunner.stop(data, shell)
    if type(data) ~= "table" then return end
    local pair=Gunner.maneuverPair(data)
    data.ProjectALifeManeuverPin=nil
    if pair~=nil then ProjectALife.SquadTactics.clearManeuver(pair.pin,"gunner_stop")
    elseif shell~=nil and ProjectALife.SquadTactics~=nil then ProjectALife.SquadTactics.clearManeuver(shell,"gunner_stop") end

    local owner = tostring(data.ProjectALifeSuppressOwnerUid or "")
    if owner ~= "" then Gunner.targets[owner] = nil end
    data.ProjectALifeSuppressTracking = nil
    data.ProjectALifeSuppressTargetIdentity = nil
    data.ProjectALifeSuppressBlindSinceMs = nil
    data.ProjectALifeSuppressUntilMs = nil
    data.ProjectALifeSuppressReported = nil
    data.ProjectALifeSuppressPosed = nil
    data.ProjectALifeSuppressCadenceMs = nil
    data.ProjectALifeSuppressAutomatic = nil

    data.ProjectALifeAimWalk = nil
    if shell ~= nil then
        pcall(function()
            local animations = ProjectALife.Animations
            if animations ~= nil then
                pcall(animations.setCombatHold, shell, false)
            end
        end)
    end
    data.ProjectALifeSuppressReportMs = nil
end

Registry.register({
    id = "gunner",
    kind = "doctrine",
    label = "Gunner (suppression fire)",
    summary = "A shooter that loses its line dumps the magazine into the last known position, full auto, spraying left and right.",
    defaultEnabled = true,
    evaluate = function() return nil end,
})

return Gunner
