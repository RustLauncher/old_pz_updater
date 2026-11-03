ProjectALife = ProjectALife or {}
if ProjectALife.ShellSimulation then return ProjectALife.ShellSimulation end

local Sim = { retirements = {}, retirementOrder = {}, metrics = { sent = 0, received = 0, paths = 0, stops = 0,
    retired = 0, failures = 0, driftRestored = 0, liftsStranded = 0, infected = 0 },
    applied = setmetatable({}, {__mode="k"}) }
ProjectALife.ShellSimulation = Sim

function Sim.grappledCorpse(shell)
    if shell == nil then return false end
    if shell.getModData ~= nil then
        local data = shell:getModData()
        if type(data) == "table" and data.ProjectALifeCorpseOf ~= nil then return true end
    end
    if type(shell.isReanimatedForGrappleOnly) ~= "function" then return false end
    return shell:isReanimatedForGrappleOnly() == true
end

local function nowMs()
    return type(getTimestampMs) == "function" and getTimestampMs() or math.floor(os.time() * 1000)
end
local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function Sim.markCorpse(shell)
    if shell == nil or shell.getModData == nil then return false end
    local data = shell:getModData()
    if type(data) ~= "table" then return false end
    local uid = data.ProjectALifeUID
    if type(uid) ~= "string" then return false end
    data.ProjectALifeCorpseOf = uid
    data.ProjectALifeCorpseAtMs = nowMs()
    data.ProjectALifeOwned = nil
    data.ProjectALifeActor = nil

    if shell.SetVariable ~= nil then shell:SetVariable("ALifeActor", "false") end
    Sim.clearPose(shell)
    return true
end

Sim.poseVariables = { "ALifeGesture", "ALifeAct", "ALifeWeaponHeld", "ALifeArms", "ALifeGrip",
    "ALifeAimWalk", "ALifeStrafe", "ALifeSneak", "ALifeLimp", "ALifeReadyCarry" }

function Sim.clearPose(shell)
    if shell == nil then return false end
    if type(shell.setBumpType) == "function" then shell:setBumpType("") end
    if type(shell.setBumpDone) == "function" then shell:setBumpDone(true) end
    if shell.SetVariable == nil then return false end
    shell:SetVariable("BumpAnimFinished", "true")
    for _, name in ipairs(Sim.poseVariables) do shell:SetVariable(name, "") end
    return true
end

Sim.serverHealthScale = 0.06

Sim.driftTolerance = 0.001

function Sim.multiplayer()
    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    return server or client
end

Sim.woundOdds = { laceration = 65, bite = 85, lacerationInfects = 25, scratchInfects = 7 }

function Sim.loreValue(key, fallback)
    local lore = type(SandboxVars) == "table" and SandboxVars.ZombieLore or nil
    local value = nil
    if type(lore) == "table" then value = tonumber(lore[key]) end
    if value == nil then return fallback end
    return value
end

function Sim.reanimationEnabled()
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current.npcsReanimate ~= nil then return current.npcsReanimate == true end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return not (type(vars) == "table" and vars.Behavior_NPCsReanimate == false)
end

function Sim.weaponKindOf(item)
    if item == nil or type(item.IsWeapon) ~= "function" or item:IsWeapon() ~= true then return nil end
    if type(item.isBroken) == "function" and item:isBroken() == true then return nil end
    if type(item.getFullType) == "function" and item:getFullType() == "Base.BareHands" then return nil end
    if type(item.isRanged) == "function" and item:isRanged() == true then
        local rounds = 1
        if type(item.getCurrentAmmoCount) == "function" then rounds = tonumber(item:getCurrentAmmoCount()) or 0 end
        if rounds > 0 then return "firearm" end
    end
    return "melee"
end

function Sim.putDownWeapon(player)
    if player == nil then return nil, nil end
    for _, name in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        if type(player[name]) == "function" then
            local held = player[name](player)
            local heldKind = Sim.weaponKindOf(held)
            if heldKind ~= nil then return held, heldKind end
        end
    end
    local inventory = nil
    if type(player.getInventory) == "function" then inventory = player:getInventory() end
    local items = nil
    if inventory ~= nil and type(inventory.getItems) == "function" then items = inventory:getItems() end
    if items == nil or type(items.size) ~= "function" or type(items.get) ~= "function" then return nil, nil end
    local spare, spareKind = nil, nil
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local kind = Sim.weaponKindOf(item)
        if kind == "melee" then return item, kind end
        if kind ~= nil and spare == nil then spare, spareKind = item, kind end
    end
    return spare, spareKind
end

function Sim.woundKind(first, second)
    local odds = Sim.woundOdds
    if (tonumber(second) or 0) > odds.bite then return "bite" end
    if (tonumber(first) or 0) > odds.laceration then return "laceration" end
    return "scratch"
end

function Sim.woundInfects(kind, roll)
    local transmission = Sim.loreValue("Transmission", 1)
    if transmission == 4 or Sim.loreValue("Mortality", 5) == 7 then return false end
    if kind == "bite" or kind == "killed" then return true end
    if transmission == 2 then return false end
    local chance = Sim.woundOdds.scratchInfects
    if kind == "laceration" then chance = Sim.woundOdds.lacerationInfects end
    return (tonumber(roll) or 100) < chance
end

function Sim.mortalityHours(choice, fraction)
    local f = math.max(0, math.min(1, tonumber(fraction) or 0.5))
    if choice == 1 then return 0 end
    if choice == 2 then return f * 30 / 3600 end
    if choice == 3 then return (0.5 + f * 0.5) / 60 end
    if choice == 4 then return 3 + f * 9 end
    if choice == 5 then return (2 + f) * 24 end
    if choice == 6 then return (1 + f) * 168 end
    return nil
end

function Sim.worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local gameTime = getGameTime()
    if gameTime == nil or type(gameTime.getWorldAgeHours) ~= "function" then return nil end
    return tonumber(gameTime:getWorldAgeHours())
end

function Sim.infect(shell, source, fraction)
    if shell == nil or type(shell.getModData) ~= "function" then return false end
    local data = shell:getModData()
    if type(data) ~= "table" or data.ProjectALifeTurnAtHours ~= nil then return false end
    local now = Sim.worldHours()
    local hours = Sim.mortalityHours(Sim.loreValue("Mortality", 5), fraction)
    if now == nil or hours == nil then return false end
    data.ProjectALifeTurnAtHours = now + hours
    data.ProjectALifeInfectedBy = tostring(source or "bite")
    Sim.metrics.infected = (Sim.metrics.infected or 0) + 1
    Sim.rememberInfection(data)
    return true
end

function Sim.writeInfection(record)
    record.memory = type(record.memory) == "table" and record.memory or {}
    record.memory.infectedTurnAtHours = Sim.pendingTurnAt
end

function Sim.rememberInfection(data)
    local registry = ProjectALife.ActorRegistry
    local uid = data.ProjectALifeUID
    if registry == nil or type(uid) ~= "string" or type(registry.peek) ~= "function"
            or type(registry.updateTransient) ~= "function" then return false end
    local current = registry.peek(uid)
    if current == nil then return false end
    Sim.pendingTurnAt = data.ProjectALifeTurnAtHours
    local written = registry.updateTransient(current.uid, current.revision, Sim.writeInfection, true)
    Sim.pendingTurnAt = nil
    return written == true
end

function Sim.healthScale()
    if Sim.multiplayer() then return Sim.serverHealthScale end
    return 1
end

function Sim.standardHealth()
    local settings = ProjectALife.BehaviorSettings
    local combat = settings ~= nil and settings.combat or nil
    local authored = combat ~= nil and tonumber(combat.standardHealth) or nil
    return math.max(0.1, (authored or 50) * Sim.healthScale())
end

function Sim.maximumFor(shell)
    local kind = type(shell)
    if kind == "nil" or kind == "number" or kind == "string" or kind == "boolean"
            or kind == "function" or shell.getModData == nil then
        return Sim.standardHealth()
    end
    local data = shell:getModData()
    local value = type(data) == "table" and tonumber(data.ProjectALifeMaximumHealth) or nil
    if value == nil or value <= 0 then return Sim.standardHealth() end
    return value
end

function Sim.setHealth(shell, health)
    if health > 0 and shell.isDead ~= nil and shell:isDead() then return false end

    if Sim.bookShielded(shell, health) then return true end
    shell:setHealth(health)

    local data = shell:getModData()

    local pool = type(data) == "table" and tonumber(data.ProjectALifeMaximumHealth) or nil

    if pool ~= nil and pool > 0 and health > pool then return end
    if type(data) ~= "table" or data.ProjectALifeHealthCeiling == health then return end
    data.ProjectALifeHealthCeiling = health
    if type(isServer) == "function" and isServer() then
        data.ProjectALifeHealthRevision = (tonumber(data.ProjectALifeHealthRevision) or 0) + 1
        data.ProjectALifeHealthPendingUntilMs = nowMs() + 3000
        data.ProjectALifeHealthAck = nil
    end
end

function Sim.hitPending(shell)
    local guard = ProjectALife.AIFence
    if type(guard) ~= "table" then return false end
    if type(guard.pendingHit) == "table" and guard.pendingHit[shell] ~= nil then return true end
    if type(guard.fallShield) == "table" and guard.fallShield[shell] ~= nil then return true end
    return false
end

function Sim.trueHealth(shell)
    if shell == nil or shell.getHealth == nil then return 0 end
    local guard = ProjectALife.AIFence
    if type(guard) == "table" then
        local pending = type(guard.pendingHit) == "table" and guard.pendingHit[shell] or nil
        if pending ~= nil and tonumber(pending.target) ~= nil then return tonumber(pending.target) end
        local shield = type(guard.fallShield) == "table" and guard.fallShield[shell] or nil
        if shield ~= nil and tonumber(shield.health) ~= nil then return tonumber(shield.health) end
    end
    local health = tonumber(shell:getHealth()) or 0
    local data = shell.getModData ~= nil and shell:getModData() or nil
    local pool = type(data) == "table" and tonumber(data.ProjectALifeMaximumHealth) or nil
    local ceiling = type(data) == "table" and tonumber(data.ProjectALifeHealthCeiling) or nil
    if pool ~= nil and pool > 0 and health > pool and ceiling ~= nil then
        return math.min(ceiling, pool)
    end
    return health
end

function Sim.bookShielded(shell, health)
    local guard = ProjectALife.AIFence
    if type(guard) ~= "table" or type(guard.fallShield) ~= "table" then return false end
    local shield = guard.fallShield[shell]
    if shield == nil then return false end
    if not (tonumber(health) ~= nil and health > 0) then
        guard.fallShield[shell] = nil
        return false
    end
    local data = shell:getModData()
    local pool = type(data) == "table" and tonumber(data.ProjectALifeMaximumHealth) or nil
    local lift = type(guard.playerFire) == "table" and tonumber(guard.playerFire.lift) or 1000

    if (pool ~= nil and pool > 0 and health > pool) or health >= lift then return false end
    shield.health = health
    if type(data) == "table" and data.ProjectALifeHealthCeiling ~= health then
        data.ProjectALifeHealthCeiling = health
        if type(isServer) == "function" and isServer() then
            data.ProjectALifeHealthRevision = (tonumber(data.ProjectALifeHealthRevision) or 0) + 1
            data.ProjectALifeHealthPendingUntilMs = nowMs() + 3000
            data.ProjectALifeHealthAck = nil
        end
    end
    shell:setHealth(health + lift)
    return true
end

function Sim.reconcileHealth(shell)
    if shell.isDead ~= nil and shell:isDead() then return end
    local data = shell:getModData()
    local ceiling = tonumber(data.ProjectALifeHealthCeiling)
    if ceiling == nil then return end
    local health = tonumber(shell:getHealth())

    local pool = tonumber(data.ProjectALifeMaximumHealth)
    if pool ~= nil and pool > 0 then
        if health ~= nil and health > pool + Sim.driftTolerance and Sim.hitPending(shell) then return end
        if ceiling > pool then
            ceiling = pool
            data.ProjectALifeHealthCeiling = pool
        end
        if health ~= nil and health > pool + Sim.driftTolerance then
            shell:setHealth(ceiling)
            Sim.metrics.liftsStranded = (Sim.metrics.liftsStranded or 0) + 1
            return
        end
    end

    if nowMs() < (tonumber(data.ProjectALifeHealthPendingUntilMs) or 0)
            and data.ProjectALifeHealthAck ~= data.ProjectALifeHealthRevision then
        shell:setHealth(ceiling)
        return
    end

    local revision = tonumber(data.ProjectALifeHealthRevision)
    if revision ~= nil and tonumber(data.ProjectALifeHealthAck) == revision then
        if health ~= nil and health < ceiling then
            data.ProjectALifeHealthCeiling = health
        end
        return
    end
    if health == nil or health >= ceiling - Sim.driftTolerance then return end
    local guard = ProjectALife.AIFence
    if type(guard) == "table" and type(guard.adoptSilentHit) == "function" then
        local ok, taken = pcall(guard.adoptSilentHit, shell, health, ceiling)
        if ok and taken == true then return end
    end
    shell:setHealth(ceiling)
    Sim.metrics = Sim.metrics or {}
    Sim.metrics.driftRestored = (Sim.metrics.driftRestored or 0) + 1
end

function Sim.isOwner(shell)
    if not (type(isClient) == "function" and isClient()) then return false end
    if shell == nil then return false end
    local ok, remote = pcall(shell.isRemoteZombie, shell)
    return ok and not remote
end

function Sim.capture(shell)
    if not (type(isServer) == "function" and isServer()) then return nil end

    if ProjectALife.Executor ~= nil and ProjectALife.Executor.serverDelegates() then return nil end
    local data = shell:getModData()
    local order = { active = data.ProjectALifePathActive == true,
        revision = tonumber(data.ProjectALifePathRevision) or 0,
        health = tonumber(data.ProjectALifeHealthCeiling), healthRevision = tonumber(data.ProjectALifeHealthRevision) or 0,
        maximumHealth = tonumber(data.ProjectALifeMaximumHealth),
        aimX = tonumber(data.ProjectALifeAimAtX), aimY = tonumber(data.ProjectALifeAimAtY) }
    if order.active then
        local path = shell:getPathFindBehavior2()
        order.x, order.y, order.z = path:getTargetX(), path:getTargetY(), path:getTargetZ()
    end
    return order
end

function Sim.valid(order)
    if type(order) ~= "table" or type(order.active) ~= "boolean"
            or not finite(order.revision) then return false end
    if order.active and not (finite(order.x) and finite(order.y) and finite(order.z)) then return false end
    if order.aimX ~= nil and not finite(order.aimX) then return false end
    if order.aimY ~= nil and not finite(order.aimY) then return false end

    if order.health ~= nil and (not finite(order.health) or order.health < 0
            or (order.health > 32 and (order.health < 1000 or order.health > 1032))) then return false end
    if order.healthRevision ~= nil and not finite(order.healthRevision) then return false end
    if order.maximumHealth ~= nil and (not finite(order.maximumHealth) or order.maximumHealth <= 0) then return false end
    return true
end

function Sim.receive(shell, order)
    if shell == nil or (shell.isDead ~= nil and shell:isDead()) then return false end
    if not Sim.valid(order) then return false end
    local data = shell:getModData()
    local old = data.ProjectALifeSimulation
    if old and old.revision > order.revision then return false end
    order.expiresAtMs = nowMs() + 3000
    data.ProjectALifeSimulation = order
    data.ProjectALifeCombatPulseMs = nowMs()
    data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = order.aimX, order.aimY
    if order.maximumHealth then data.ProjectALifeMaximumHealth = order.maximumHealth end
    if order.health ~= nil and order.healthRevision ~= nil then
        local revision = tonumber(data.ProjectALifeHealthRevision) or -1
        if order.healthRevision > revision then
            shell:setHealth(order.health)
            data.ProjectALifeHealthRevision = order.healthRevision
        elseif order.healthRevision == revision then
            shell:setHealth(math.min(shell:getHealth(), order.health))
        end
        if Sim.isOwner(shell) and type(sendClientCommand) == "function" then
            sendClientCommand("ProjectALife", "shellHealthAck", {
                uid = data.ProjectALifeUID, generation = data.ProjectALifeGeneration,
                revision = order.healthRevision })
        end
    end
    Sim.metrics.received = Sim.metrics.received + 1
    return true
end

function Sim.onClientCommand(module, command, player, message)
    if module ~= "ProjectALife" or command ~= "shellHealthAck" or type(message) ~= "table"
            or type(message.uid) ~= "string" or not finite(message.generation)
            or not finite(message.revision) then return end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog and watchdog.bindings[message.uid]
    if not binding or binding.generation ~= message.generation then return end
    local shell = binding.shell
    if shell:getOwnerPlayer() ~= player then return end
    local data = shell:getModData()
    if data.ProjectALifeUID ~= message.uid or tonumber(data.ProjectALifeGeneration) ~= message.generation then return end
    if data.ProjectALifeHealthRevision == message.revision then
        data.ProjectALifeHealthAck = message.revision
    end
end

function Sim.drive(shell)
    if not Sim.isOwner(shell) then Sim.applied[shell] = nil; return false end
    local data = shell:getModData()
    if type(data.ProjectALifeUID) ~= "string" then return false end
    if shell:isDead() then Sim.applied[shell] = nil; return false end
    local animations = ProjectALife.Animations
    if animations and animations.blocksLocomotion and animations.blocksLocomotion(shell) then

        if Sim.applied[shell] ~= "ground" then
            local ok = pcall(function()
                local behavior = shell:getPathFindBehavior2()
                if behavior then behavior:cancel() end
                shell:setPath2(nil)
                shell:setMoving(false)
                shell:setVariable("bMoving", false)
                shell:setVariable("bPathfind", false)
                data.ProjectALifePathActive = nil
            end)
            if ok then Sim.applied[shell] = "ground" end
        end
        return false
    end
    local order = data.ProjectALifeSimulation
    local active = order and order.active and nowMs() < order.expiresAtMs
    local token = active and tostring(order.revision) .. ":" .. tostring(order.x)
        .. ":" .. tostring(order.y) .. ":" .. tostring(order.z) or "stop"
    if Sim.applied[shell] == token then return true end
    local ok, reason = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior == nil then error("path_behavior_unavailable") end
        shell:setUseless(true)
        shell:setTarget(nil)
        behavior:cancel()
        shell:setPath2(nil)
        if active then
            behavior:reset()
            behavior:pathToLocationF(order.x, order.y, math.floor(order.z))
            shell:setVariable("bPathfind", true)
            shell:changeState(PathFindState.instance())
            Sim.metrics.paths = Sim.metrics.paths + 1
        else
            shell:setVariable("bPathfind", false)
            shell:setVariable("bMoving", false)
            shell:setMoving(false)

            local animations = ProjectALife.Animations
            if not (animations and animations.current[shell]) then
                shell:changeState(ZombieIdleState.instance())
            end
            Sim.metrics.stops = Sim.metrics.stops + 1
        end
        data.ProjectALifePathActive = active == true and true or nil
    end)
    if ok then Sim.applied[shell] = token else
        Sim.metrics.failures = Sim.metrics.failures + 1
        Sim.metrics.lastError = tostring(reason)
    end
    return ok
end

function Sim.retire(shell)
    if not (type(isServer) == "function" and isServer()) then return true end
    local data = shell:getModData()
    local id = shell:getOnlineID()

    if id == nil or id == -1 then return true end

    local x, y, z
    if shell.getX ~= nil and shell.getY ~= nil and shell.getZ ~= nil then x, y, z = shell:getX(), shell:getY(), shell:getZ() end
    local ok = pcall(sendServerCommand, "ProjectALife", "retireShell", {
        onlineId = id, uid = data.ProjectALifeUID, generation = data.ProjectALifeGeneration, x = x, y = y, z = z })
    if ok then Sim.metrics.sent = Sim.metrics.sent + 1 end
    return ok
end

function Sim.healthAttacker(message)
    if type(message.attackerUid) == "string" and tonumber(message.attackerGeneration) ~= nil then
        local registry = ProjectALife.ActorRegistry
        local actor = registry ~= nil and (registry.peek or registry.read)(message.attackerUid) or nil
        if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= message.attackerGeneration then return nil end
        local relay = ProjectALife.NPCHitRelay
        if relay == nil or type(getCell) ~= "function" then return nil end
        local cell = getCell()
        local zombies = cell ~= nil and cell:getZombieList() or nil
        for index = 0, (zombies ~= nil and zombies:size() or 0) - 1 do
            local shell = zombies:get(index)
            local uid, generation = relay.identity(shell)
            if uid == actor.uid and generation == actor.generation then return shell end
        end
        return nil
    end
    local executor = ProjectALife.Executor
    if tonumber(message.attackerOnline) ~= nil and executor ~= nil then
        return executor.playerByOnlineId(message.attackerOnline)
    end
    return nil
end

function Sim.applyExecutorHealth(message)
    if type(message) ~= "table" or type(message.uid) ~= "string" then return false, "invalid" end
    local executor = ProjectALife.Executor

    if message.death == true and executor ~= nil and type(executor.noteServerDeath) == "function" then
        executor.noteServerDeath(message.uid, tonumber(message.generation), tonumber(message.onlineId),
            tonumber(message.x), tonumber(message.y), tonumber(message.z))
    end
    local entry = executor ~= nil and type(executor.executed) == "table" and executor.executed[message.uid] or nil
    if entry == nil or entry.shell == nil then return false, "not_executed" end
    if type(executor.entryMatches) ~= "function" or not executor.entryMatches(entry.shell, message.uid, entry) then
        return false, "shell_identity_changed"
    end
    if type(executor.authorityFor) ~= "function" or executor.authorityFor(entry.shell) ~= true then
        return false, "not_owner"
    end
    if tonumber(message.generation) ~= nil and entry.generation ~= tonumber(message.generation) then
        return false, "generation_mismatch"
    end
    local health = tonumber(message.health)
    if not finite(health) or health < 0 then return false, "bad_health" end
    local shell = entry.shell
    local wasDead = shell:isDead()

    if wasDead then return false, "shell_dead" end
    local revision = tonumber(message.revision)
    local previous = tonumber(shell:getModData().ProjectALifeHealthAckLocal)
    if revision ~= nil and previous ~= nil and revision <= previous then return false, "stale_health" end

    entry.freshHealth = nil
    local attacker = Sim.healthAttacker(message)
    pcall(function()

        if not Sim.bookShielded(shell, health) then shell:setHealth(health) end
        local data = shell:getModData()
        data.ProjectALifeExecutorHealth = health

        local wound = message.wound
        if type(wound) == "table" then
            local treated = wound.treated == true
            if type(wound.injuries) == "table" and ProjectALife.Wounds ~= nil then
                if treated then
                    data.ProjectALifeInjuries = ProjectALife.Wounds.copy(wound.injuries)
                else
                    local health = ProjectALife.Health
                    local own = data.ProjectALifeInjuries
                    if health ~= nil and type(health.injuriesOf) == "function" then
                        own = health.injuriesOf(shell, data) or own
                    end
                    local joined = ProjectALife.Wounds.merge(own, wound.injuries)
                    local kept = ProjectALife.Wounds.prune(joined, Sim.worldHours() or 0)
                    data.ProjectALifeInjuries = kept
                end
                data.ProjectALifeInjuriesRead = true
                data.ProjectALifeInjuryTickMs = nil
            end
            if wound.zone == "head" or wound.zone == "torso" or wound.zone == "body" or wound.zone == "limb" then
                data.ProjectALifeLastWoundZone = wound.zone
            end
            if wound.leg ~= nil then data.ProjectALifeWoundLeg = wound.leg == true or nil end
            local seen = tonumber(data.ProjectALifeWounds) or 0
            local count = tonumber(wound.count) or 0
            if type(wound.injuries) == "table" and treated then data.ProjectALifeWounds = count
            else data.ProjectALifeWounds = math.max(seen, count) end

            if count > seen then
                local health = ProjectALife.Health
                if health ~= nil and type(health.stain) == "function" then
                    pcall(health.stain, shell, wound.zone)
                end
            end
            local now = nowMs()
            for field, key in pairs({ runMs = "ProjectALifeHitRunUntilMs", bleedMs = "ProjectALifeBleedOutAtMs", downMs = "ProjectALifeDownedUntilMs" }) do
                local duration = tonumber(wound[field])
                if finite(duration) and duration > 0 then
                    data[key] = now + math.min(duration, field == "runMs" and 8000 or 180000)
                elseif duration == 0 and treated then
                    data[key] = nil
                end
            end
            if type(wound.injuries) == "table" then
                local health = ProjectALife.Health
                if health ~= nil and type(health.applyInjuries) == "function" then
                    health.applyInjuries(data, data.ProjectALifeInjuries, Sim.worldHours() or 0)
                end
                if health ~= nil and type(health.persistInjuries) == "function" then health.persistInjuries(data) end
            end
        end
        if tonumber(message.revision) ~= nil then data.ProjectALifeHealthAckLocal = tonumber(message.revision) end
    end)
    local injury = ProjectALife.Injury
    if message.injury ~= nil and injury ~= nil and type(injury.receiveState) == "function" then
        injury.receiveState(shell, shell:getModData(), message.injury, nowMs())
    end

    if health <= 0 then
        pcall(function()
            if wasDead then return end
            local killer = attacker or shell
            shell:Kill(killer)
        end)
    end

    if attacker ~= nil and message.forgiven ~= true then
        pcall(function()
            local perception = ProjectALife.Perception
            if attacker ~= nil and perception ~= nil and type(perception.noteAttacker) == "function" then
                perception.noteAttacker(message.uid, attacker, 12000, message.kind or "player")
            end
            if message.kind == "actor" and tonumber(message.damage) ~= nil
                    and health > 0 and ProjectALife.Combat ~= nil then
                ProjectALife.Combat.presentHumanHit(shell, attacker, message.damage,
                    message.zone, message.ranged == true, nowMs())
            end
        end)
    end
    if executor ~= nil and executor.metrics ~= nil then
        executor.metrics.healthApplied = (executor.metrics.healthApplied or 0) + 1
    end
    return true, "applied"
end

function Sim.applyExecutorGrudge(message)
    if type(message) ~= "table" or type(message.uid) ~= "string" then return false, "invalid" end
    local executor = ProjectALife.Executor
    local entry = executor ~= nil and type(executor.executed) == "table" and executor.executed[message.uid] or nil
    if entry == nil or entry.shell == nil then return false, "not_executed" end
    if tonumber(message.generation) ~= nil and entry.generation ~= tonumber(message.generation) then
        return false, "generation_mismatch"
    end
    local holdMs = tonumber(message.holdMs)
    if holdMs == nil or holdMs <= 0 then return false, "expired" end
    local attacker = Sim.healthAttacker(message)
    if attacker == nil then return false, "attacker_unknown" end
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.noteAttacker) ~= "function" then return false, "no_perception" end
    perception.noteAttacker(message.uid, attacker, math.min(holdMs, 60000),
        type(message.kind) == "string" and message.kind or "player")
    if executor.metrics ~= nil then
        executor.metrics.grudgesTaken = (executor.metrics.grudgesTaken or 0) + 1
    end
    return true, "taken"
end

function Sim.onServerCommand(module, command, message)
    if module == "ProjectALife" and command == "executorNPCEquipment" then
        ProjectALife.NPCHitRelay.receiveEquipment(message)
        return
    end
    if module == "ProjectALife" and command == "executorHealth" then
        Sim.applyExecutorHealth(message)
        return
    end
    if module == "ProjectALife" and command == "executorGrudge" then
        Sim.applyExecutorGrudge(message)
        return
    end
    if module == "ProjectALife" and command == "simulationQA" then
        local owned, spectators = 0, 0
        local zombies = getCell():getZombieList()
        for index = 0, zombies:size() - 1 do
            local shell = zombies:get(index)
            if type(shell:getModData().ProjectALifeUID) == "string" then
                if Sim.isOwner(shell) then owned = owned + 1 else spectators = spectators + 1 end
            end
        end
        local client = ProjectALife.AnimationClient
        local pending = client and client.order and #client.order or 0

        local remoteApi = "unknown"
        for index = 0, zombies:size() - 1 do
            local ok, remote = pcall(function() return zombies:get(index):isRemoteZombie() end)
            remoteApi = ok and tostring(remote) or ("missing:" .. tostring(remote))
            break
        end
        local extra = client and type(client.diagnostics) == "function" and client.diagnostics() or ""

        local localCount, remoteCount, byId = 0, 0, {}
        for index = 0, zombies:size() - 1 do
            local shell = zombies:get(index)
            local ok, remote = pcall(function() return shell:isRemoteZombie() end)
            if ok and remote == true then remoteCount = remoteCount + 1 else localCount = localCount + 1 end
            local idOk, onlineId = pcall(function() return shell:getOnlineID() end)
            if idOk and onlineId ~= nil then byId[onlineId] = shell end
        end
        local observed = client and client.observed or {}
        local seen, missing, seenIds, missingIds = 0, 0, {}, {}
        for _, entry in ipairs(type(message) == "table" and type(message.shells) == "table" and message.shells or {}) do
            local onlineId = tonumber(entry.onlineId)
            local shell = onlineId and (byId[onlineId] or observed[onlineId]) or nil
            if shell ~= nil then
                seen = seen + 1
                local ok, remote = pcall(function() return shell:isRemoteZombie() end)
                seenIds[#seenIds + 1] = tostring(onlineId) .. (ok and remote == true and "r" or "L")
            else
                missing = missing + 1
                missingIds[#missingIds + 1] = tostring(onlineId)
            end
        end
        local executorLine = ProjectALife.Executor and ProjectALife.Executor.qaLine() or ""
        print("[ALIFE-MP] " .. executorLine)
        pcall(function()
            local executor = ProjectALife.Executor
            if executor ~= nil and type(executor.dumpExecuted) == "function" then executor.dumpExecuted() end
        end)
        print("[ALIFE-MP] owner=" .. owned .. " spectator=" .. spectators
            .. " received=" .. Sim.metrics.received .. " paths=" .. Sim.metrics.paths
            .. " stops=" .. Sim.metrics.stops .. " retired=" .. Sim.metrics.retired
            .. " failures=" .. Sim.metrics.failures .. " pending=" .. pending
            .. " remoteApi=" .. remoteApi .. " zombiesLocal=" .. localCount .. " zombiesRemote=" .. remoteCount
            .. " serverShells=" .. tostring(seen + missing) .. " seen=" .. seen .. " missing=" .. missing
            .. " seenIds=" .. table.concat(seenIds, ",") .. " missingIds=" .. table.concat(missingIds, ",")
            .. " " .. extra .. " error=" .. tostring(Sim.metrics.lastError))
        return
    end
    if module ~= "ProjectALife" or command ~= "retireShell"
            or type(message) ~= "table" or not finite(message.onlineId)
            or message.onlineId == -1 or type(message.uid) ~= "string"
            or not finite(message.generation) then return end
    message.expiresAtMs = nowMs() + 5000

    if Sim.retireUntilMs == nil or message.expiresAtMs > Sim.retireUntilMs then
        Sim.retireUntilMs = message.expiresAtMs
    end
    if Sim.retirements[message.onlineId] == nil then
        Sim.retirementOrder[#Sim.retirementOrder + 1] = message.onlineId
        if #Sim.retirementOrder > 256 then Sim.retirements[table.remove(Sim.retirementOrder, 1)] = nil end
    end
    Sim.retirements[message.onlineId] = message
    local zombies = getCell():getZombieList()
    for index = zombies:size() - 1, 0, -1 do
        local shell = zombies:get(index)
        if shell:getOnlineID() == message.onlineId then Sim.removeRetired(shell); return end
    end
end

Sim.retireMatchTiles = 3

function Sim.retireMatches(shell, message)
    local executor = ProjectALife.Executor
    local driven = executor ~= nil and type(executor.byShell) == "table" and executor.byShell[shell] or nil
    if driven ~= nil then
        local entry = executor.executed and executor.executed[driven]
        return driven == message.uid and entry ~= nil and entry.generation == message.generation
            and type(executor.entryMatches) == "function"
            and executor.entryMatches(shell, driven, entry) == true
    end
    if type(shell.GetVariable) == "function" then
        local uid = shell:GetVariable("ALifeUID")
        if type(uid) == "string" and uid ~= "" then
            if uid ~= message.uid then return false end
            local generation = tonumber(shell:GetVariable("ALifeGeneration"))
            return generation == message.generation
        end
    end
    return false
end

function Sim.removeRetired(shell)
    local horizon = Sim.retireUntilMs
    if horizon == nil then return false end
    if not (type(isClient) == "function" and isClient()) then return false end
    if nowMs() >= horizon then

        Sim.retirements, Sim.retirementOrder, Sim.retireUntilMs = {}, {}, nil
        return false
    end
    local id = shell:getOnlineID()
    local message = Sim.retirements[id]
    if not message then return false end
    if nowMs() >= message.expiresAtMs then Sim.retirements[id] = nil; return false end

    if Sim.grappledCorpse(shell) then return false end
    local data = shell:getModData()

    if data.ProjectALifeUID ~= nil and (data.ProjectALifeUID ~= message.uid
            or tonumber(data.ProjectALifeGeneration) ~= message.generation) then return false end

    if data.ProjectALifeUID == nil and not Sim.retireMatches(shell, message) then
        Sim.metrics.retireRefused = (Sim.metrics.retireRefused or 0) + 1
        return false
    end
    if ProjectALife.AIFence then ProjectALife.AIFence.untrack(shell) end
    if ProjectALife.Animations then ProjectALife.Animations.forget(shell) end
    Sim.applied[shell] = nil

    pcall(function()
        local executor = ProjectALife.Executor
        if executor ~= nil and executor.executes(shell) then
            executor.release(executor.byShell[shell], "retired")
        end
    end)
    shell:removeFromWorld()
    shell:removeFromSquare()
    Sim.metrics.retired = Sim.metrics.retired + 1
    return true
end

if type(isClient) == "function" and isClient() and Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(Sim.onServerCommand)
end
if type(isServer) == "function" and isServer() and Events and Events.OnClientCommand then
    Events.OnClientCommand.Add(Sim.onClientCommand)
end
return Sim
