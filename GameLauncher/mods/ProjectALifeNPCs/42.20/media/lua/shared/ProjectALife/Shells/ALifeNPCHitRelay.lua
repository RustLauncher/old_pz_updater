ProjectALife = ProjectALife or {}
if ProjectALife.NPCHitRelay ~= nil then return ProjectALife.NPCHitRelay end
require "ProjectALife/Behaviours/ALifeVehicleRules"
require "ProjectALife/Talk/ALifeSpeech"

local Relay = { sequence = 0, attacks = setmetatable({}, { __mode = "k" }),
    selected = setmetatable({}, { __mode = "k" }),
    pending = setmetatable({}, { __mode = "k" }),
    metrics = { requested = 0, applied = 0, refused = 0, refusedBy = {}, lastRefusal = "", kitRepaired = 0 } }
ProjectALife.NPCHitRelay = Relay

local function nowMs()
    return type(getTimestampMs) == "function" and getTimestampMs() or math.floor(os.time() * 1000)
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Relay.identity(shell)
    if shell == nil then return nil end
    local uid, generation
    pcall(function()
        local data = shell:getModData()
        uid, generation = data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration)
        if (uid == nil or generation == nil) and shell.GetVariable ~= nil then
            uid, generation = shell:GetVariable("ALifeUID"), tonumber(shell:GetVariable("ALifeGeneration"))
        end
    end)
    if type(uid) == "string" and uid ~= "" and generation ~= nil then return uid, generation end
    return nil
end

function Relay.reset()
    Relay.sequence = 0
    Relay.attacks = setmetatable({}, { __mode = "k" })
    Relay.selected = setmetatable({}, { __mode = "k" })
    Relay.pending = setmetatable({}, { __mode = "k" })
    Relay.metrics = { requested = 0, applied = 0, refused = 0, refusedBy = {}, lastRefusal = "", kitRepaired = 0 }
end

function Relay.bindingMatches(binding, uid)
    if binding == nil then return false end
    local actualUid, generation = Relay.identity(binding.shell)
    return actualUid == uid and generation == binding.generation
end

function Relay.beginAttack(shell)

    Relay.sequence = math.max(Relay.sequence + 1, nowMs())
    Relay.attacks[shell] = Relay.sequence
end

function Relay.request(attacker, target, weapon)
    if type(sendClientCommand) ~= "function" then return false end
    local uid, generation = Relay.identity(attacker)
    local targetUid, targetGeneration = Relay.identity(target)
    if uid == nil or targetUid == nil or weapon == nil then return false end
    local fullType
    pcall(function() fullType = weapon:getFullType() end)
    if type(fullType) ~= "string" or #fullType > 128 then return false end
    if Relay.attacks[attacker] == nil then Relay.beginAttack(attacker) end
    local sent = pcall(sendClientCommand, "ProjectALife", "executorNPCHit", {
        uid = uid, generation = generation, targetUid = targetUid, targetGeneration = targetGeneration,
        attack = Relay.attacks[attacker], weapon = fullType,
    })
    if sent then Relay.metrics.requested = Relay.metrics.requested + 1 end
    return sent
end

local function sendAction(shell, weapon, op, target)
    if type(isClient) ~= "function" or not isClient() or type(sendClientCommand) ~= "function" then return false end
    local uid, generation = Relay.identity(shell)
    if uid == nil or weapon == nil then return false end
    local fullType = weapon:getFullType()
    if type(fullType) ~= "string" or #fullType > 128 then return false end
    local message = {
        uid = uid, generation = generation, weapon = fullType, op = op, attack = Relay.attacks[shell],
        slot = ProjectALife.Weapons.slot(weapon),
    }
    if op == "attack" and target ~= nil and type(instanceof) == "function"
            and instanceof(target, "IsoPlayer") and type(target.getOnlineID) == "function" then
        local online = tonumber(target:getOnlineID())
        if finite(online) and online >= 0 and online == math.floor(online) then message.online = online end
    end
    return pcall(sendClientCommand, "ProjectALife", "executorNPCAction", message)
end

function Relay.select(shell, weapon)
    if type(isClient) ~= "function" or not isClient() then return false end
    if weapon == nil then return false end
    local fullType = weapon:getFullType() .. ":" .. tostring(ProjectALife.Weapons.slot(weapon))
    if Relay.selected[shell] == fullType then return true end
    if not sendAction(shell, weapon, "select") then return false end
    Relay.selected[shell] = fullType
    return true
end

function Relay.prepareAttack(shell, weapon, target)
    if not Relay.select(shell, weapon) then return false end
    return sendAction(shell, weapon, "attack", target)
end

function Relay.reload(shell, weapon, committed)
    if not Relay.select(shell, weapon) then return false end
    return sendAction(shell, weapon, committed and "reload_commit" or "reload_begin")
end

local function refuse(reason)
    Relay.metrics.refused = Relay.metrics.refused + 1
    Relay.metrics.lastRefusal = reason
    Relay.metrics.refusedBy[reason] = (Relay.metrics.refusedBy[reason] or 0) + 1
    return false, reason
end

Relay.rehydratedAtMs = setmetatable({}, { __mode = "k" })
Relay.repairIntervalMs = 5000
function Relay.carriesFirearm(shell)
    local armed = false
    pcall(function()
        local inventory = shell:getInventory()
        local items = inventory ~= nil and inventory:getItems() or nil
        for index = 0, (items ~= nil and items:size() or 0) - 1 do
            local item = items:get(index)
            if item ~= nil and type(item.isAimedFirearm) == "function"
                and item:isAimedFirearm() == true then armed = true end
        end
    end)
    return armed
end
function Relay.repairKit(shell, actor)
    if shell == nil or type(actor) ~= "table" then return false end
    local now = nowMs()
    if now - (Relay.rehydratedAtMs[shell] or -math.huge) < Relay.repairIntervalMs then return false end
    Relay.rehydratedAtMs[shell] = now
    if Relay.carriesFirearm(shell) then return false end
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator == nil or type(hydrator.hydrate) ~= "function" then return false end
    local spent = Relay.spentRounds(shell, actor)
    local simulation = ProjectALife.ShellSimulation
    local health
    if simulation ~= nil and type(simulation.trueHealth) == "function" then health = simulation.trueHealth(shell) end
    local ok = pcall(hydrator.hydrate, shell, actor)
    if ok then
        Relay.metrics.kitRepaired = (Relay.metrics.kitRepaired or 0) + 1
        if spent ~= nil then pcall(Relay.keepSpentRounds, shell, spent) end

        if tonumber(health) ~= nil and health > 0
                and tonumber(simulation.trueHealth(shell)) ~= health then
            simulation.setHealth(shell, health)
        end
    end
    return ok == true
end

function Relay.spentRounds(shell, actor)
    local magazines = ProjectALife.MagazineState
    if magazines == nil or type(magazines.snapshot) ~= "function" then return nil end
    local ok, data = pcall(function() return shell:getModData() end)
    if not ok or type(data) ~= "table" or data.ProjectALifePrimaryAmmoUnits == nil then return nil end
    if type(actor) ~= "table" or data.ProjectALifeUID ~= actor.uid then return nil end
    return magazines.snapshot(shell)
end

function Relay.keepSpentRounds(shell, spent)
    local magazines = ProjectALife.MagazineState
    if magazines == nil or type(magazines.restore) ~= "function" then return false end
    spent.infinite = nil
    magazines.restore(shell, spent)
    local items = shell:getInventory():getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil and type(item.isAimedFirearm) == "function" and item:isAimedFirearm() == true
                and type(magazines.setLoaded) == "function" then
            magazines.setLoaded(item, 0)
        end
    end
    Relay.metrics.kitRoundsKept = (Relay.metrics.kitRoundsKept or 0) + 1
    return true
end

function Relay.requestEquipment(shell, retry)
    if type(isClient) ~= "function" or not isClient() or type(sendClientCommand) ~= "function" then return false end
    local uid, generation = Relay.identity(shell)
    if uid == nil then return false end
    local pending = retry and Relay.pending[shell] or nil
    if pending == nil then
        Relay.sequence = Relay.sequence + 1
        pending = { id = Relay.sequence }
        Relay.pending[shell] = pending
    end
    pending.atMs = nowMs()
    Relay.selected[shell] = nil
    return pcall(sendClientCommand, "ProjectALife", "executorNPCAction", {
        uid = uid, generation = generation, op = "sync", sync = pending.id,
    })
end

function Relay.ready(shell)
    local pending = Relay.pending[shell]
    if pending == nil then return true end
    if nowMs() - pending.atMs >= 1000 then Relay.requestEquipment(shell, true) end
    return false
end

function Relay.sendEquipment(player, message)
    if type(isServer) ~= "function" or not isServer() or type(message) ~= "table"
            or type(message.uid) ~= "string" or #message.uid > 128
            or not finite(message.generation) or not finite(message.sync) then return refuse("bad_sync") end
    local actor = ProjectALife.ActorRegistry and ProjectALife.ActorRegistry.read(message.uid)
    local binding = ProjectALife.Watchdog and ProjectALife.Watchdog.bindings[message.uid]
    if not Relay.bindingMatches(binding, message.uid) then return false end
    if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= message.generation
            or binding == nil or binding.generation ~= message.generation or binding.shell == nil then return refuse("stale_actor") end
    local shell = binding.shell
    local ok, owner = pcall(function() return shell:getOwnerPlayer() end)
    if not ok or owner == nil or owner ~= player then return refuse("not_owner") end
    local now = nowMs()
    if binding.npcEquipmentOwner == owner and binding.npcEquipmentAtMs ~= nil
            and now - binding.npcEquipmentAtMs < 500 then return refuse("sync_rate") end
    binding.npcEquipmentOwner, binding.npcEquipmentAtMs = owner, now
    local weapons, magazines = ProjectALife.Weapons, ProjectALife.MagazineState
    if weapons == nil or magazines == nil or type(sendServerCommand) ~= "function" then return refuse("unavailable") end
    local current, entries = weapons.current(shell), {}
    local inventory = shell:getInventory()
    local items = inventory ~= nil and inventory:getItems() or nil
    for index = 0, (items ~= nil and items:size() or 0) - 1 do
        local item = items:get(index)
        if item ~= nil and type(item.isAimedFirearm) == "function" then
            entries[#entries + 1] = { weapon = item:getFullType(), slot = weapons.slot(item),
                selected = item == current, condition = item:getCondition(), loaded = magazines.current(item) }
        end
    end
    local traderStock
    if actor.memory and actor.memory.traderStock ~= nil then
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator == nil or type(hydrator.traderSnapshot) ~= "function" then return refuse("trader_stock_unavailable") end
        traderStock = hydrator.traderSnapshot(actor)
        if traderStock == nil then return refuse("trader_stock_unavailable") end
    end
    return pcall(sendServerCommand, owner, "ProjectALife", "executorNPCEquipment", {
        uid = message.uid, generation = message.generation, sync = message.sync,
        weapons = entries, ammo = magazines.snapshot(shell), traderStock = traderStock,
    })
end

function Relay.receiveEquipment(message)
    if type(message) ~= "table" or type(message.weapons) ~= "table" then return false end
    local executor = ProjectALife.Executor
    local entry = executor and executor.executed and executor.executed[message.uid]
    local shell = entry and entry.shell
    local pending = shell and Relay.pending[shell]
    if pending == nil or pending.id ~= message.sync or entry.generation ~= message.generation then return false end
    local uid, generation = Relay.identity(shell)
    if uid ~= message.uid or generation ~= message.generation then return false end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and not sim.isOwner(shell) then return false end
    if message.traderStock ~= nil then
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator == nil or type(hydrator.restoreTraderStock) ~= "function" then return false end
        local restored = hydrator.restoreTraderStock(shell, { uid = uid, generation = generation }, message.traderStock)
        if restored ~= true then return false end
    end
    local weapons, magazines = ProjectALife.Weapons, ProjectALife.MagazineState
    local items = shell:getInventory():getItems()
    local selected
    for _, state in ipairs(message.weapons) do
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if item ~= nil and type(item.isAimedFirearm) == "function" and item:getFullType() == state.weapon
                    and weapons.slot(item) == state.slot then
                local restored = state.condition
                if ProjectALife.DropPolicy ~= nil and type(ProjectALife.DropPolicy.breakSafe) == "function" then
                    restored = ProjectALife.DropPolicy.breakSafe(item, restored)
                end
                item:setCondition(restored)
                if item:isAimedFirearm() then
                    item:setCurrentAmmoCount(state.loaded)
                    local data = item:getModData()
                    data.ProjectALifeLoadedRounds, data.ProjectALifeEngineLoadedRounds = state.loaded, state.loaded
                end
                if state.selected then selected = item end
                break
            end
        end
    end
    magazines.restore(shell, message.ammo)
    if selected ~= nil then weapons.select(shell, selected, weapons.slot(selected)) end
    Relay.pending[shell], Relay.selected[shell] = nil, nil
    return true
end

function Relay.action(player, message)
    if type(isServer) ~= "function" or not isServer() then return refuse("not_server") end
    if type(message) == "table" and message.op == "sync" then return Relay.sendEquipment(player, message) end
    if type(message) ~= "table" or type(message.uid) ~= "string" or #message.uid > 128
            or not finite(message.generation) or type(message.weapon) ~= "string" or #message.weapon > 128
            or not ({ select = true, attack = true, reload_begin = true, reload_commit = true })[message.op] then
        return refuse("bad_action")
    end
    if message.online ~= nil and (message.op ~= "attack" or not finite(message.online)
            or message.online < 0 or message.online ~= math.floor(message.online)) then return refuse("bad_target") end
    local registry, watchdog, weapons, magazines = ProjectALife.ActorRegistry, ProjectALife.Watchdog,
        ProjectALife.Weapons, ProjectALife.MagazineState
    if registry == nil or watchdog == nil or weapons == nil or magazines == nil then return refuse("unavailable") end
    local actor, binding = registry.read(message.uid), watchdog.bindings[message.uid]
    if not Relay.bindingMatches(binding, message.uid) then return refuse("stale_actor") end
    if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= message.generation
            or binding == nil or binding.generation ~= message.generation or binding.shell == nil then
        return refuse("stale_actor")
    end
    local shell = binding.shell
    local ok, owner = pcall(function() return shell:getOwnerPlayer() end)
    if not ok or owner == nil or owner ~= player then return refuse("not_owner") end
    if shell:isDead() then return refuse("dead") end
    local function issuedForAction()
        local found
        local inventory = shell:getInventory()
        local items = inventory ~= nil and inventory:getItems() or nil
        for index = 0, (items ~= nil and items:size() or 0) - 1 do
            local item = items:get(index)
            if item ~= nil and item:getFullType() == message.weapon and type(item.isAimedFirearm) == "function"
                    and (message.slot == nil or weapons.slot(item) == message.slot) then
                found = item; break
            end
        end
        local selected = weapons.current(shell)
        if selected ~= nil and selected:getFullType() == message.weapon
                and (message.slot == nil or weapons.slot(selected) == message.slot) then found = selected end
        return found
    end
    local weapon = issuedForAction()

    if weapon == nil and Relay.repairKit(shell, actor) then weapon = issuedForAction() end
    if weapon == nil then return refuse("unissued_weapon") end

    if binding.npcActionOwner ~= owner then
        binding.npcActionOwner, binding.npcHitAttack, binding.npcReload = owner, nil, nil
    end
    local now = nowMs()
    if message.op == "select" then
        if weapons.current(shell) == weapon then return true end
        binding.npcReload = nil
        return weapons.select(shell, weapon, weapons.slot(weapon)) == true
    end
    if weapons.current(shell) ~= weapon then return refuse("stowed_weapon") end
    local ranged = weapon:isAimedFirearm() == true
    if message.op == "reload_begin" then
        if not ranged then return refuse("not_firearm") end
        local pending = binding.npcReload
        if pending ~= nil and now > pending.expiresAt then binding.npcReload, pending = nil, nil end
        if pending ~= nil and pending.weapon == weapon then return refuse("reload_pending") end
        local transaction = magazines.beginReload(shell, weapon)
        if transaction == nil then return refuse("reload_empty_or_full") end
        local settings = ProjectALife.Combat and ProjectALife.Combat.settings or {}
        local duration = transaction.internal and (settings.internalReloadMs or 650) or (settings.reloadMs or 2500)
        if transaction.internal then
            duration = duration + math.max(0, transaction.rounds - 1) * (settings.internalReloadPerRoundMs or 950)
        end

        local insert = duration * (transaction.internal and 0.82 or 0.55)
        binding.npcReload = { weapon = weapon, transaction = transaction,
            readyAt = now + math.max(100, insert - 150), expiresAt = now + duration + 10000 }
        return true
    elseif message.op == "reload_commit" then
        local pending = binding.npcReload
        if pending == nil or pending.weapon ~= weapon then return refuse("no_reload") end
        if now < pending.readyAt then

            pending.commitRequested = true
            return refuse("early_reload")
        end
        binding.npcReload = nil
        if now > pending.expiresAt then return refuse("expired_reload") end
        return magazines.commitReload(pending.transaction) == true
    end

    if not finite(message.attack) or message.attack < 1 or message.attack ~= math.floor(message.attack) then return refuse("bad_attack") end
    local pending = binding.npcReload
    if pending ~= nil and pending.commitRequested and pending.weapon == weapon
            and now >= pending.readyAt and now <= pending.expiresAt then
        binding.npcReload = nil
        if not magazines.commitReload(pending.transaction) then return refuse("reload_failed") end
    end
    local last = binding.npcHitAttack
    local cadence = ranged and weapons.fireIntervalMs(weapon) or 450
    if last ~= nil and (message.attack <= last.id or now - last.atMs < math.max(60, cadence * 0.75)) then
        return refuse("attack_cadence")
    end
    if ranged and not magazines.consumeRound(shell, weapon) then return refuse("empty_weapon") end
    binding.npcHitAttack = { id = message.attack, owner = owner, weapon = message.weapon,
        item = weapon, atMs = now, count = 0, victims = {} }
    ProjectALife.Speech.combatBark(shell, "COMBAT_ATTACK", nil, now)
    local executor = ProjectALife.Executor
    if message.online ~= nil and executor ~= nil and type(executor.applyPlayerHit) == "function" then
        executor.applyPlayerHit(player, message, true)
    end
    return true
end

function Relay.apply(player, message)
    if type(isServer) ~= "function" or not isServer() then return refuse("not_server") end
    if type(message) ~= "table" or type(message.uid) ~= "string" or #message.uid > 128
            or type(message.targetUid) ~= "string" or #message.targetUid > 128
            or type(message.weapon) ~= "string" or #message.weapon > 128
            or not finite(message.generation) or not finite(message.targetGeneration)
            or not finite(message.attack) or message.attack < 1 or message.attack ~= math.floor(message.attack) then
        return refuse("bad_message")
    end
    local registry, watchdog = ProjectALife.ActorRegistry, ProjectALife.Watchdog
    if registry == nil or watchdog == nil then return refuse("unavailable") end
    local attacker, victim = registry.read(message.uid), registry.read(message.targetUid)
    local source, destination = watchdog.bindings[message.uid], watchdog.bindings[message.targetUid]
    if not Relay.bindingMatches(source, message.uid) or not Relay.bindingMatches(destination, message.targetUid) then
        return refuse("stale_actor")
    end
    if attacker == nil or victim == nil or attacker.lifecycle ~= "active" or victim.lifecycle ~= "active"
            or attacker.uid == victim.uid or source == nil or destination == nil
            or attacker.generation ~= message.generation or victim.generation ~= message.targetGeneration
            or source.generation ~= message.generation or destination.generation ~= message.targetGeneration then
        return refuse("stale_actor")
    end
    local shell, target = source.shell, destination.shell
    local owned, owner = pcall(function() return shell:getOwnerPlayer() end)
    if not owned or owner == nil or owner ~= player then return refuse("not_owner") end
    if shell:isDead() or target:isDead() then return refuse("dead") end
    local relations = ProjectALife.Relations
    if relations == nil or not (relations.hostile(attacker, victim) or relations.hostile(victim, attacker)
            or (type(relations.isSelfDefence) == "function" and relations.isSelfDefence(attacker, victim))) then
        return refuse("not_hostile")
    end
    local policy = ProjectALife.TargetPolicy
    if policy == nil or not policy.canAttack(target) then return refuse("protected_target") end

    local function issuedForHit()
        local found
        local inventory = shell:getInventory()
        local items = inventory ~= nil and inventory:getItems() or nil
        for index = 0, (items ~= nil and items:size() or 0) - 1 do
            local item = items:get(index)
            if item ~= nil and item:getFullType() == message.weapon
                    and type(item.isAimedFirearm) == "function" then found = item; break end
        end
        return found
    end
    local weapon = issuedForHit()

    if weapon == nil and Relay.repairKit(shell, attacker) then weapon = issuedForHit() end
    if weapon == nil then return refuse("unissued_weapon") end
    local selected = ProjectALife.Weapons.current(shell)
    if selected ~= nil and selected:getFullType() == message.weapon then weapon = selected end
    if selected ~= weapon then return refuse("stowed_weapon") end

    local ranged = weapon:isAimedFirearm() == true
    local reach = tonumber(weapon:getMaxRange()) or 1
    if ranged then
        reach = math.max(2, math.min(40, reach))
        if shell:getModData().ProjectALifeConduct == "sniper" then reach = reach * 1.5 end
    else reach = math.max(0.7, math.min(3, reach)) end
    local dx, dy, dz = shell:getX() - target:getX(), shell:getY() - target:getY(), shell:getZ() - target:getZ()

    if dx * dx + dy * dy > (reach + 0.5) ^ 2 or math.abs(dz) > (ranged and 3 or 0.5) then
        return refuse("out_of_range")
    end
    local line = ProjectALife.LineOfFire
    if line == nil or type(line.hasClearBoundary) ~= "function" then return refuse("blocked") end
    local mode
    if not ranged then mode = "melee" end
    local checked, clear = pcall(line.hasClearBoundary, shell, target, mode)
    if not checked or clear ~= true then return refuse("blocked") end
    if not ranged then
        local vehicles = ProjectALife.VehicleRules
        if vehicles == nil or type(vehicles.meleeBlocked) ~= "function" then
            return refuse("vehicle_rules_unavailable")
        end
        local checkedVehicle, blocked = pcall(vehicles.meleeBlocked, target)
        if not checkedVehicle or blocked ~= false then return refuse("vehicle") end
    end
    local now = nowMs()
    local last = source.npcHitAttack
    local maximumVictims = ranged and ProjectALife.Weapons.firesPellets(weapon) and 8 or 1
    if last == nil or last.owner ~= owner or last.id ~= message.attack or last.item ~= weapon
            or last.weapon ~= message.weapon or now - last.atMs > 1500 then return refuse("unpaid_attack") end
    if last.hunt == true or last.victims[message.targetUid] or last.count >= maximumVictims then return refuse("duplicate_attack") end
    last.victims[message.targetUid] = true
    last.count = last.count + 1
    local damage = ProjectALife.HumanDamage
    if damage == nil then return refuse("damage_unavailable") end
    local applied, points, zone = damage.apply(shell, target, weapon, 1)
    if not applied then return refuse("damage_failed") end
    target:getModData().ProjectALifeLastHumanHitRanged = ranged
    relations.provoke(victim, attacker)
    if ProjectALife.Perception ~= nil then
        ProjectALife.Perception.noteAttacker(victim.uid, shell, 60000, "actor")
    end

    ProjectALife.Executor.pushHealth(target, victim.uid, victim.generation, shell, "actor")
    Relay.metrics.applied = Relay.metrics.applied + 1
    return true, points, zone
end

return Relay
