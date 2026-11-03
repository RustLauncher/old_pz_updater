require "ProjectALife/Core/ALifeActionLedger"

ProjectALife = ProjectALife or {}

local Ledger = ProjectALife.ActionLedger
local Watchdog = {
    bindings = {},
    order = {},
    cursor = 0,
    adapters = {},
    lossGraceMs = 2000,
    recheckMs = 250,
    maximumMisses = 3,
    maximumRecoveries = 2,

    maximumStep = 20,

    recoveryStabilityMs = 10000,

    settleAfterMs = 5000,
    lostTtlMs = 1800000,
    lostRadius = 3,
    lostCap = 64,
    lostAt = {},
    lostSquares = {},
    lostCount = 0,
}
ProjectALife.Watchdog = Watchdog

local function nowMs()
    if type(Watchdog.adapters.nowMs) == "function" then
        return Watchdog.adapters.nowMs()
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function emit(category, fields)
    if type(Watchdog.adapters.emit) == "function" then
        Watchdog.adapters.emit(category, fields)
    end
end

local function validUid(value)
    return type(value) == "string" and #value > 0 and #value <= 64
end

local function validGeneration(value)
    return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function remove(uid)
    Watchdog.bindings[uid] = nil
    for index, candidate in ipairs(Watchdog.order) do
        if candidate == uid then
            table.remove(Watchdog.order, index)
            if Watchdog.cursor >= index then
                Watchdog.cursor = math.max(0, Watchdog.cursor - 1)
            end
            return
        end
    end
end

local function identityMatches(binding)
    if type(Watchdog.adapters.shellAlive) ~= "function"
        or Watchdog.adapters.shellAlive(binding.shell) ~= true then
        return false, "shell_missing"
    end
    if type(Watchdog.adapters.shellIdentity) ~= "function" then
        return false, "shell_identity_unavailable"
    end
    local uid, generation = Watchdog.adapters.shellIdentity(binding.shell)
    if uid ~= binding.uid or generation ~= binding.generation then
        return false, "shell_identity_mismatch"
    end
    return true
end

function Watchdog.matches(binding)
    return binding ~= nil and identityMatches(binding) == true
end

function Watchdog.configure(adapters)
    adapters = adapters or {}
    for _, name in ipairs({
        "getActor", "shellAlive", "shellIdentity", "recoverShell", "detachShell",
    }) do
        if type(adapters[name]) ~= "function" then
            return false, "watchdog_adapter_missing:" .. name
        end
    end
    Watchdog.adapters = adapters
    Ledger.configure({ nowMs = adapters.nowMs, emit = adapters.emit })
    return true
end

function Watchdog.reset()
    Watchdog.bindings = {}
    Watchdog.order = {}
    Watchdog.cursor = 0
    Watchdog.lostAt, Watchdog.lostSquares, Watchdog.lostCount = {}, {}, 0
    Ledger.reset()
end

function Watchdog.bind(uid, generation, shell)
    if not validUid(uid) or not validGeneration(generation) or shell == nil then
        return false, "shell_binding_invalid"
    end
    local existing = Watchdog.bindings[uid]
    if existing and existing.generation > generation then
        return false, "shell_generation_stale"
    end
    if existing and existing.generation == generation and existing.shell ~= shell then
        local alive = identityMatches(existing)
        if alive then return false, "shell_binding_conflict" end
    end
    local now = nowMs()
    if not existing then Watchdog.order[#Watchdog.order + 1] = uid end
    Watchdog.bindings[uid] = {
        uid = uid,
        generation = generation,
        shell = shell,
        boundAtMs = now,
        lastSeenAtMs = now,
        lastCheckAtMs = 0,
        missingAtMs = nil,
        misses = 0,
        recoveries = 0,
        settleAtMs = now + Watchdog.settleAfterMs,
    }
    local binding = Watchdog.bindings[uid]
    if Watchdog.matches(binding) and type(Watchdog.adapters.shellPosition) == "function" then
        binding.lastPosition = Watchdog.adapters.shellPosition(shell)
    end
    emit("shell_bound", { uid = uid, generation = generation })
    return true
end

function Watchdog.unbind(uid, generation, reason, details)
    local binding = Watchdog.bindings[uid]
    if not binding then return false, "shell_not_bound" end
    if generation ~= nil and binding.generation ~= generation then
        return false, "shell_generation_changed"
    end
    Ledger.cancelActor(uid, binding.generation, reason or "shell_unbound")
    remove(uid)
    local injury = ProjectALife.Injury
    if injury ~= nil and type(injury.onUnbind) == "function" then pcall(injury.onUnbind, uid) end
    local fields = type(details) == "table" and details or {}
    fields.uid = uid
    fields.generation = binding.generation
    fields.reason = reason or "shell_unbound"
    emit("shell_unbound", fields)
    return true
end

function Watchdog.describeLoss(fields, shell, position)
    local adapter = ProjectALife.ShellAdapter
    local probe = adapter ~= nil and adapter.probeShell or nil
    if type(probe) ~= "function" then return fields end
    local ok, found = pcall(probe, shell, position)
    if ok and type(found) == "table" then
        for key, value in pairs(found) do
            if fields[key] == nil then fields[key] = value end
        end
    end
    return fields
end

function Watchdog.probing()
    local adapter = ProjectALife.ShellAdapter
    return adapter ~= nil and type(adapter.placeFacts) == "function"
        and type(adapter.countZombies) == "function" and type(adapter.shellPosition) == "function"
end

function Watchdog.where(position)
    local x = type(position) == "table" and tonumber(position.x) or nil
    local y = type(position) == "table" and tonumber(position.y) or nil
    if x == nil or y == nil then return nil end
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(tonumber(position.z) or 0)
end

function Watchdog.distance(a, b)
    return math.floor(math.sqrt(((tonumber(a.x) or 0) - (tonumber(b.x) or 0)) ^ 2
        + ((tonumber(a.y) or 0) - (tonumber(b.y) or 0)) ^ 2) * 10 + 0.5) / 10
end

function Watchdog.pruneLost(now, uid)
    local list = Watchdog.lostSquares
    for index = #list, 1, -1 do
        local entry = list[index]
        if entry.uid == uid or now - entry.atMs > Watchdog.lostTtlMs then table.remove(list, index) end
    end
    Watchdog.lostCount = #list
end

function Watchdog.rememberLoss(uid, position, reason, now, sweep)
    local x = type(position) == "table" and tonumber(position.x) or nil
    local y = type(position) == "table" and tonumber(position.y) or nil
    if x == nil or y == nil then return false end
    x, y = math.floor(x), math.floor(y)
    local z = math.floor(tonumber(position.z) or 0)
    for _, entry in ipairs(Watchdog.lostSquares) do
        if entry.uid == uid and entry.x == x and entry.y == y and entry.z == z then
            if sweep == true then entry.sweep = true end
            return false
        end
    end
    Watchdog.pruneLost(now, uid)
    local list = Watchdog.lostSquares
    if #list >= Watchdog.lostCap then table.remove(list, 1) end
    list[#list + 1] = { uid = uid, x = x, y = y, z = z, atMs = now, reason = reason, sweep = sweep == true or nil }
    Watchdog.lostCount = #list
    return true
end

function Watchdog.forgetLoss(uid, now)
    Watchdog.lostAt[uid] = nil
    Watchdog.pruneLost(now, uid)
end

function Watchdog.placeFields(fields, position)
    for key, value in pairs(ProjectALife.ShellAdapter.placeFacts(position)) do
        if fields[key] == nil then fields[key] = value end
    end
    return fields
end

function Watchdog.nearFields(fields, uid, shell, at, now)
    local adapter = ProjectALife.ShellAdapter
    fields.at = fields.at or Watchdog.where(at)
    local near = adapter.countZombies(at, 3, shell, false)
    fields.mates3, fields.stale3, fields.anim3, fields.plain3 = near.mates, near.stale, near.anim, near.plain
    fields.nearestPlain = near.nearestPlain
    local lost = Watchdog.lostAt[uid]
    if lost ~= nil and type(at) == "table" then
        fields.lostAt = Watchdog.where(lost)
        fields.fromLoss = Watchdog.distance(at, lost)
        fields.lossAgoS = math.floor((now - lost.atMs) / 1000)
        fields.plainAtLoss = adapter.countZombies(lost, 1, shell, false).plain
    end
    return fields
end

function Watchdog.noteLoss(binding, reason, now, current)
    if not Watchdog.probing() then return end
    binding.firstMissAtMs = now
    local adapter = ProjectALife.ShellAdapter
    local position = binding.lastPosition
    local fields = Watchdog.describeLoss({ uid = binding.uid, generation = binding.generation,
        reason = reason, ageMs = now - (tonumber(binding.boundAtMs) or now),
        seenMs = now - (tonumber(binding.lastSeenAtMs) or now) }, binding.shell, position)
    Watchdog.placeFields(fields, position)
    fields.chunkPlain = adapter.countZombies(position, 0, binding.shell, true).plain
    if binding.lastState ~= nil then
        local text = Watchdog.stateText(binding.lastState)
        fields.state = string.match(text, "([%w_]+)@") or text
    end
    if type(current) == "table" and type(position) == "table" then
        fields.jump = Watchdog.distance(current, position)
    end
    local x = type(position) == "table" and tonumber(position.x) or nil
    local y = type(position) == "table" and tonumber(position.y) or nil
    if x ~= nil and y ~= nil then
        Watchdog.lostAt[binding.uid] = { x = x, y = y, z = tonumber(position.z) or 0, atMs = now }
    end
    if fields.loaded == false then
        Watchdog.rememberLoss(binding.uid, position, reason, now, Watchdog.reloadGuard())
    end
    emit("lifecycle_lost", fields)
end

function Watchdog.noteBack(binding, now)
    if not Watchdog.probing() then return end
    local since = tonumber(binding.firstMissAtMs) or tonumber(binding.missingAtMs) or now
    binding.firstMissAtMs = nil
    Watchdog.forgetLoss(binding.uid, now)
    emit("lifecycle_back", { uid = binding.uid, generation = binding.generation,
        goneMs = now - since, at = Watchdog.where(binding.lastPosition) })
end

function Watchdog.noteSettled(binding, now)
    if not Watchdog.probing() then return end
    local at = ProjectALife.ShellAdapter.shellPosition(binding.shell)
    local fields = Watchdog.nearFields({ uid = binding.uid, generation = binding.generation,
        ageMs = now - (tonumber(binding.boundAtMs) or now) }, binding.uid, binding.shell, at, now)
    Watchdog.lostAt[binding.uid] = nil
    Watchdog.pruneLost(now, nil)
    emit("lifecycle_settled", fields)
end

function Watchdog.noteExhausted(binding, reason, now)
    if not Watchdog.probing() then return end
    Watchdog.rememberLoss(binding.uid, binding.lastPosition, reason, now)
end

function Watchdog.reloadGuard()
    local gate = ProjectALife.FeatureGate
    if gate ~= nil and type(gate.flag) == "function" then return gate.flag("Lifecycle_ReloadGuard", true) == true end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return not (type(vars) == "table" and vars.Lifecycle_ReloadGuard == false)
end

function Watchdog.noteGhost(zombie, skipSwept)
    local list = Watchdog.lostSquares
    local kind = type(zombie)
    if #list == 0 or (kind ~= "userdata" and kind ~= "table")
            or zombie.getX == nil or zombie.getY == nil or zombie.getZ == nil then return false end
    local x, y, z = tonumber(zombie:getX()), tonumber(zombie:getY()), tonumber(zombie:getZ())
    if x == nil or y == nil then return false end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local radius = Watchdog.lostRadius
    for index = #list, 1, -1 do
        local entry = list[index]
        if entry.z == z and math.abs(entry.x - x) <= radius and math.abs(entry.y - y) <= radius
                and not (skipSwept == true and entry.sweep == true) then
            table.remove(list, index)
            Watchdog.lostCount = #list
            local now = nowMs()
            if now - entry.atMs <= Watchdog.lostTtlMs then
                pcall(Watchdog.emitGhost, entry, zombie, x, y, z, now)
                return true
            end
        end
    end
    return false
end

function Watchdog.emitGhost(entry, zombie, x, y, z, now)
    local here = { x = x + 0.5, y = y + 0.5, z = z }
    local near = Watchdog.probing() and ProjectALife.ShellAdapter.countZombies(here, 3, zombie, false) or nil
    emit("lifecycle_ghost", { uid = entry.uid, reason = entry.reason, at = Watchdog.where(here),
        lostAt = Watchdog.where(entry),
        fromLoss = Watchdog.distance(here, { x = entry.x + 0.5, y = entry.y + 0.5 }),
        lossAgoS = math.floor((now - entry.atMs) / 1000),
        outfit = zombie.getPersistentOutfitID ~= nil and zombie:getPersistentOutfitID() or nil,
        mates3 = near ~= nil and near.mates or nil })
end

function Watchdog.observe(uid, generation, shell)
    local binding = Watchdog.bindings[uid]
    if not binding or binding.generation ~= generation or binding.shell ~= shell then
        return false, "shell_observation_stale"
    end
    local valid, reason = identityMatches(binding)
    if not valid then return false, reason end
    binding.lastSeenAtMs = nowMs()
    binding.missingAtMs = nil
    binding.misses = 0
    binding.recoveries = 0
    return true
end

function Watchdog.beginSpawn(actor, shell, specification)
    if type(actor) ~= "table" or not validUid(actor.uid)
        or not validGeneration(actor.generation) then
        return nil, "spawn_actor_invalid"
    end
    specification = specification or {}
    local bound, bindError = Watchdog.bind(actor.uid, actor.generation, shell)
    if not bound then return nil, bindError end
    local startedAtMs = specification.startedAtMs or nowMs()
    return Ledger.begin({
        operationId = specification.operationId,
        uid = actor.uid,
        generation = actor.generation,
        kind = "spawn",
        fingerprint = specification.fingerprint,
        startedAtMs = startedAtMs,
        deadlineAtMs = specification.deadlineAtMs,
        maximumRecoveries = specification.maximumRecoveries or 2,
        retryDelayMs = specification.retryDelayMs or 500,
        fallback = "safe_dormant",
        isComplete = function()
            local binding = Watchdog.bindings[actor.uid]
            return binding ~= nil and identityMatches(binding) == true
        end,
        cancel = function()
            return Watchdog.adapters.detachShell(actor, Watchdog.bindings[actor.uid], "spawn_cancelled")
        end,
        recover = function()
            local binding = Watchdog.bindings[actor.uid]
            local recovered = Watchdog.adapters.recoverShell(actor, binding, "spawn_timeout")
            if type(recovered) == "table" or type(recovered) == "userdata" then
                return Watchdog.bind(actor.uid, actor.generation, recovered)
            end
            return recovered == true
        end,
    })
end

local function auditBinding(binding, now)
    if now - binding.lastCheckAtMs < Watchdog.recheckMs then return end
    binding.lastCheckAtMs = now

    local peek = Watchdog.adapters.peekActor
    local actor = (type(peek) == "function" and peek or Watchdog.adapters.getActor)(binding.uid)
    if actor and actor.generation == binding.generation and actor.lifecycle == "dormant"
            and binding.saveCleanupFailed == true then return end
    if not actor or actor.generation ~= binding.generation
        or (actor.lifecycle ~= "spawning" and actor.lifecycle ~= "active") then
        Watchdog.unbind(binding.uid, binding.generation, "actor_detached")
        return
    end
    local valid, reason = identityMatches(binding)
    if valid then
        if type(Watchdog.adapters.shellPosition) == "function" then
            local current = Watchdog.adapters.shellPosition(binding.shell)
            local previous = binding.lastPosition
            if type(current) == "table" and type(previous) == "table"
                    and ((tonumber(current.x) or 0) - (tonumber(previous.x) or 0)) ^ 2
                        + ((tonumber(current.y) or 0) - (tonumber(previous.y) or 0)) ^ 2
                            > Watchdog.maximumStep ^ 2 then
                binding.ignoreShellPosition = true
                pcall(Watchdog.noteLoss, binding, "shell_displaced", now, current)
                actor = Watchdog.adapters.getActor(binding.uid) or actor
                local transitioned = type(Watchdog.adapters.onShellLost) ~= "function"
                    or Watchdog.adapters.onShellLost(actor, binding, "shell_displaced") == true
                if transitioned then
                    Watchdog.adapters.detachShell(actor, binding, "shell_displaced")
                    Watchdog.unbind(binding.uid, binding.generation, "shell_displaced")
                    emit("shell_displaced", { uid = binding.uid, generation = binding.generation })
                end
                return
            end
            binding.lastPosition = current or binding.lastPosition
            local body, kind = binding.shell, type(binding.shell)
            local owned = Watchdog.ownerState(body)
            if owned ~= nil then
                binding.lastState = owned
            elseif (kind == "userdata" or kind == "table") and body.getCurrentState ~= nil then
                binding.lastState = body:getCurrentState()
            end
        end
        if binding.missingAtMs ~= nil then pcall(Watchdog.noteBack, binding, now) end
        if binding.settleAtMs ~= nil and now >= binding.settleAtMs then
            binding.settleAtMs = nil
            pcall(Watchdog.noteSettled, binding, now)
        end
        binding.lastSeenAtMs = now
        binding.missingAtMs = nil
        binding.misses = 0
        if binding.recoveries > 0
                and now - (tonumber(binding.boundAtMs) or now)
                    >= Watchdog.recoveryStabilityMs then
            binding.recoveries = 0
        end
        return
    end

    local shell = binding.shell
    local kind = type(shell)
    if (kind == "userdata" or kind == "table") and shell.isDead ~= nil and shell:isDead() == true then
        local uid, generation = Watchdog.adapters.shellIdentity(binding.shell)
        if uid == binding.uid and generation == binding.generation then
            local lifecycle = ProjectALife.Lifecycle
            if lifecycle and type(lifecycle.onShellDeath) == "function" then
                pcall(lifecycle.onShellDeath, binding.shell)
            end
            return
        end
    end
    if binding.missingAtMs == nil then pcall(Watchdog.noteLoss, binding, reason, now) end
    binding.missingAtMs = binding.missingAtMs or now
    if now - binding.missingAtMs < Watchdog.lossGraceMs then return end
    binding.misses = binding.misses + 1
    if binding.misses < Watchdog.maximumMisses then return end
    binding.misses = 0
    binding.missingAtMs = now
    actor = Watchdog.adapters.getActor(binding.uid) or actor

    if binding.recoveries < Watchdog.maximumRecoveries and Watchdog.unloadedLoss(binding) then
        binding.recoveries = Watchdog.maximumRecoveries
        binding.recoveryError = "square_unloaded"
    end

    if binding.recoveries < Watchdog.maximumRecoveries and Watchdog.culledLoss(binding) then
        binding.recoveries = Watchdog.maximumRecoveries
        binding.recoveryError = "engine_cull"
        Watchdog.enginePark = (Watchdog.enginePark or 0) + 1
    end
    if binding.recoveries >= Watchdog.maximumRecoveries then
        if type(Watchdog.adapters.onShellLost) == "function" then
            local transitionOk, transitioned = pcall(
                Watchdog.adapters.onShellLost, actor, binding, reason)
            if not transitionOk or transitioned ~= true then
                emit("shell_loss_transition_failed", {
                    uid = binding.uid,
                    generation = binding.generation,
                    reason = transitionOk and "persistence_failed" or tostring(transitioned),
                })
                return
            end
        end
        pcall(Watchdog.noteExhausted, binding, reason, now)

        local details = Watchdog.describeLoss({ attempt = binding.recoveries,
            error = binding.recoveryError }, binding.shell, binding.lastPosition)
        Watchdog.adapters.detachShell(actor, binding, reason)
        Watchdog.unbind(binding.uid, binding.generation, "watchdog_exhausted:" .. reason, details)
        return
    end
    binding.recoveries = binding.recoveries + 1
    local attempt = binding.recoveries
    if actor.lifecycle == "active" then
        Ledger.cancelActor(binding.uid, binding.generation, "shell_recovery")
    end
    local fields = Watchdog.describeLoss({ uid = binding.uid, generation = binding.generation,
        attempt = attempt, reason = reason }, binding.shell, binding.lastPosition)
    local recovered, recoverError = Watchdog.adapters.recoverShell(actor, binding, reason)
    if type(recovered) == "table" or type(recovered) == "userdata" then
        Watchdog.bind(binding.uid, binding.generation, recovered)
        local rebound = Watchdog.bindings[binding.uid]
        if rebound ~= nil then rebound.recoveries = attempt end
        if actor.lifecycle == "active"
                and type(Watchdog.adapters.onShellRecovered) == "function" then
            pcall(Watchdog.adapters.onShellRecovered, actor, recovered, reason)
        end
        fields.newOnlineId = Watchdog.describeLoss({}, recovered).onlineId
    elseif recovered == true then
        binding.missingAtMs = nil
        binding.misses = 0
    else
        binding.recoveryError = recoverError
    end
    fields.recovered = recovered ~= false and recovered ~= nil
    fields.error = recoverError
    emit("shell_recovery", fields)
end

function Watchdog.ownerState(shell)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.serverDelegates) ~= "function" or not executor.serverDelegates() then
        return nil
    end
    local animations = ProjectALife.Animations
    local pose = animations ~= nil and type(animations.ownerPose) == "table" and animations.ownerPose[shell] or nil
    if pose == nil then return "owner:none" end

    return pose
end

function Watchdog.stateText(state)
    if type(state) == "table" then
        return "owner:" .. tostring(state.animation) .. "/" .. tostring(state.combatPhase)
    end
    return tostring(state)
end

function Watchdog.unloadedLoss(binding)
    local shell, position = binding.shell, binding.lastPosition
    local kind = type(shell)
    if (kind ~= "userdata" and kind ~= "table") or shell.getCurrentSquare == nil
            or shell:getCurrentSquare() ~= nil or type(position) ~= "table" then return false end
    local x, y = tonumber(position.x), tonumber(position.y)
    if x == nil or y == nil or type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return false end
    if cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(position.z) or 0)) == nil then
        return true
    end
    local population = ProjectALife.Population
    if population ~= nil and type(population.windowEdge) == "function" then
        local edge = population.windowEdge(position)
        if edge ~= nil and edge < 4 then return true end
    end
    return false
end

Watchdog.parkEngineCulls = true
Watchdog.cullSightTiles = 70

function Watchdog.culledLoss(binding)
    if Watchdog.parkEngineCulls ~= true then return false end
    if not (type(isServer) == "function" and isServer() == true) then return false end
    local shell, position = binding.shell, binding.lastPosition
    local kind = type(shell)
    if (kind ~= "userdata" and kind ~= "table") or shell.getCurrentSquare == nil
            or shell:getCurrentSquare() ~= nil or type(position) ~= "table" then return false end
    if shell.isDead ~= nil and shell:isDead() == true then return false end
    local x, y = tonumber(position.x), tonumber(position.y)
    if x == nil or y == nil or type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or cell.getGridSquare == nil then return false end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(position.z) or 0))
    if square == nil or square.isInARoom == nil or square.haveRoofFull == nil then return false end
    if square:isInARoom() == true or square:haveRoofFull() == true then return false end
    local population = ProjectALife.Population
    local reach = math.max(tonumber(Watchdog.cullSightTiles) or 70,
        population ~= nil and tonumber(population.spawnDistance) or 0)
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function"
            or type(locator.position) ~= "function" then return false end
    for _, player in ipairs(locator.list() or {}) do
        local at = locator.position(player)
        local px = type(at) == "table" and tonumber(at.x) or nil
        local py = type(at) == "table" and tonumber(at.y) or nil
        if px == nil or py == nil or (px - x) ^ 2 + (py - y) ^ 2 <= reach * reach then return false end
    end
    return true
end

function Watchdog.forceRecovery(uid, reason)
    local binding = Watchdog.bindings[uid]
    if binding == nil or type(Watchdog.adapters.recoverShell) ~= "function"
            or type(Watchdog.adapters.getActor) ~= "function" then return false, "not_bound" end
    local actor = Watchdog.adapters.getActor(uid)
    if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= binding.generation then
        return false, "not_active"
    end
    Ledger.cancelActor(uid, binding.generation, "shell_recovery")
    local fields = Watchdog.describeLoss({ uid = uid, generation = binding.generation,
        attempt = 0, reason = reason }, binding.shell, binding.lastPosition)
    local recovered, recoverError = Watchdog.adapters.recoverShell(actor, binding, reason)
    local rebuilt = type(recovered) == "table" or type(recovered) == "userdata"
    if rebuilt then
        Watchdog.bind(uid, binding.generation, recovered)
        if type(Watchdog.adapters.onShellRecovered) == "function" then
            pcall(Watchdog.adapters.onShellRecovered, actor, recovered, reason)
        end
        fields.newOnlineId = Watchdog.describeLoss({}, recovered).onlineId
    end
    fields.recovered = rebuilt
    fields.error = recoverError
    emit("shell_recovery", fields)
    return rebuilt, recoverError
end

function Watchdog.audit(budget)
    local maximum = math.min(#Watchdog.order, math.max(1, math.floor(tonumber(budget) or 1)))
    local processed = 0
    while processed < maximum and #Watchdog.order > 0 do
        Watchdog.cursor = (Watchdog.cursor % #Watchdog.order) + 1
        local binding = Watchdog.bindings[Watchdog.order[Watchdog.cursor]]
        if binding then auditBinding(binding, nowMs()) end
        processed = processed + 1
    end
    return processed
end

function Watchdog.tick(actionBudget, shellBudget)
    if shellBudget == nil then
        local maximum = math.max(2, math.floor(tonumber(actionBudget) or 2))
        actionBudget = math.max(1, math.floor(maximum / 2))
        shellBudget = math.max(1, maximum - actionBudget)
    else
        actionBudget = math.max(1, math.floor(tonumber(actionBudget) or 1))
        shellBudget = math.max(1, math.floor(tonumber(shellBudget) or 1))
    end
    local started = nowMs()
    local actionCount = Ledger.tick(actionBudget)
    local middle = nowMs()
    local shellCount = Watchdog.audit(shellBudget)
    if middle - started > 16 or nowMs() - middle > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then
            runtime.noteDetail("watchdog:ledger", middle - started)
            runtime.noteDetail("watchdog:audit", nowMs() - middle)
        end
    end
    return actionCount + shellCount
end

return Watchdog
