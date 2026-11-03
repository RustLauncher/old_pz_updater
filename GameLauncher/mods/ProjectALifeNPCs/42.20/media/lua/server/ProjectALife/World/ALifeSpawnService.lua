require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Watchdog = ProjectALife.Watchdog
local Interop = ProjectALife.Interop
local SpawnService = {
    pending = {},
    pendingOrder = {},
    settled = {},
    settledOrder = {},
    maximumSettled = 256,
    adapters = {},
    clearRadius = 6,
    reloadRadius = 10,
    unloaded = {},
    unloadedCount = 0,
    metrics = { spawnZombieClears = 0, spawnZombieWatched = 0, spawnZombieScans = 0, reloadZombiesCleared = 0 },
}
ProjectALife.SpawnService = SpawnService

local function nowMs()
    if type(SpawnService.adapters.nowMs) == "function" then
        return SpawnService.adapters.nowMs()
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function emit(category, fields)
    if type(SpawnService.adapters.emit) == "function" then
        pcall(SpawnService.adapters.emit, category, fields or {})
    end
end

local function adminPersistent(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    local admin = type(memory) == "table" and memory.admin or nil
    return type(admin) == "table" and admin.persistent == true
end

local function forcedDehydrate(reason)
    return reason == "admin_purge" or reason == "scene_atomic_rollback"
end

local function removePending(operationId)
    SpawnService.pending[operationId] = nil
    for index, candidate in ipairs(SpawnService.pendingOrder) do
        if candidate == operationId then table.remove(SpawnService.pendingOrder, index); return end
    end
end

local function rollback(record, shell, reason)
    local current = Registry.read(record.uid)
    local transitioned = nil
    if current and current.generation == record.generation and current.lifecycle ~= "dead" then
        transitioned = Registry.makeDormant(
            current.uid, current.revision, current.generation, current.worldPosition)
        if transitioned == nil then
            transitioned = Registry.updateTransient(current.uid, current.revision, function(candidate)
                candidate.lifecycle = "dormant"
                candidate.activity = "idle"
                candidate.intent = "hold"
            end)
        end
    end
    if transitioned and type(SpawnService.adapters.onActorDormant) == "function" then
        pcall(SpawnService.adapters.onActorDormant, transitioned, reason or "spawn_rollback")
    end
    if shell ~= nil then
        local uid, generation = SpawnService.adapters.shellIdentity(shell)
        if uid == record.uid and generation == record.generation
                and SpawnService.adapters.shellAlive(shell) then
            SpawnService.adapters.cleanupShell(shell, reason)
        end
    end
    Watchdog.unbind(record.uid, record.generation, reason)
    emit("spawn_rollback", { uid = record.uid, generation = record.generation, reason = reason })
end

function SpawnService.configure(adapters)
    adapters = adapters or {}
    for _, name in ipairs({
        "createShell", "hydrateShell", "cleanupShell", "shellAlive",
        "shellIdentity", "recoverShell", "detachShell",
    }) do
        if type(adapters[name]) ~= "function" then
            return false, "spawn_adapter_missing:" .. name
        end
    end
    SpawnService.adapters = adapters
    Registry.configure({
        nowMs = adapters.nowMs,
        newUid = adapters.newUid,
        persist = adapters.persist,
        emit = adapters.emit,
    })
    return Watchdog.configure({
        nowMs = adapters.nowMs,
        emit = adapters.emit,
        getActor = Registry.read,
        peekActor = Registry.peek,
        shellAlive = adapters.shellAlive,
        shellIdentity = adapters.shellIdentity,
        shellPosition = adapters.shellPosition,
        recoverShell = adapters.recoverShell,
        detachShell = adapters.detachShell,
        onShellRecovered = adapters.onShellRecovered,
        onShellLost = function(actor, binding)
            if actor == nil or actor.lifecycle == "dead" then return true end
            local position = binding.lastPosition or actor.worldPosition
            if binding.ignoreShellPosition ~= true and Watchdog.matches(binding)
                    and type(adapters.shellPosition) == "function" then
                position = adapters.shellPosition(binding.shell) or position
            end
            local current = Registry.read(actor.uid)
            if current and current.lifecycle == "active"
                    and current.generation == binding.generation then
                local dormant = Registry.makeDormant(
                    current.uid, current.revision, current.generation, position)
                if dormant and type(adapters.onActorDormant) == "function" then
                    pcall(adapters.onActorDormant, dormant, "watchdog_exhausted")
                end
                return dormant ~= nil
            end
            return true
        end,
    })
end

function SpawnService.reset()
    SpawnService.pending = {}
    SpawnService.pendingOrder = {}
    SpawnService.settled = {}
    SpawnService.settledOrder = {}
    SpawnService.unloaded, SpawnService.unloadedCount = {}, 0
    SpawnService.checkpointCursor = 0
    Registry.reset()
    Watchdog.reset()
end

function SpawnService.request(uid, operationId, fingerprint, timeoutMs)
    if type(operationId) ~= "string" or #operationId < 1
        or type(fingerprint) ~= "string" or #fingerprint < 1 then
        return nil, "spawn_request_invalid"
    end
    local existing = SpawnService.pending[operationId] or SpawnService.settled[operationId]
    if existing then
        if existing.uid ~= uid or existing.fingerprint ~= fingerprint then
            return nil, "spawn_operation_conflict"
        end
        return existing, true
    end
    local actor = Registry.read(uid)
    if not actor then return nil, "actor_not_found" end
    local catalog = ProjectALife.Catalog
    local deleted = catalog and catalog.deletedReason and catalog.deletedReason(actor.factionId, actor.profileId)
    if deleted then return nil, deleted end
    if actor.lifecycle ~= "dormant" then return nil, "actor_not_dormant" end
    local binding = Watchdog.bindings[uid]
    if binding and binding.saveCleanupFailed == true then return nil, "shell_cleanup_deferred" end
    local spawning, spawnError = Registry.beginSpawn(actor.uid, actor.revision)
    if not spawning then return nil, spawnError end
    local createOk, shell, createError = pcall(SpawnService.adapters.createShell, spawning)
    if not createOk or shell == nil then
        rollback(spawning, nil, createOk and (createError or "shell_create_failed") or tostring(shell))
        emit("spawn_failed", { uid = uid, stage = "create", error = createError })
        return nil, "shell_create_failed"
    end
    local hydrateOk, hydrated, hydrateError = pcall(
        SpawnService.adapters.hydrateShell, shell, spawning)
    if not hydrateOk or hydrated ~= true then
        rollback(spawning, shell, hydrateOk and (hydrateError or "shell_hydration_failed")
            or tostring(hydrated))
        emit("spawn_failed", { uid = uid, stage = "hydrate", error = hydrateError })
        return nil, "shell_hydration_failed"
    end
    local startedAtMs = nowMs()
    local action, actionError = Watchdog.beginSpawn(spawning, shell, {
        operationId = operationId,
        fingerprint = fingerprint,
        startedAtMs = startedAtMs,
        deadlineAtMs = startedAtMs + math.max(250, math.floor(timeoutMs or 2000)),
        maximumRecoveries = 2,
        retryDelayMs = 500,
    })
    if not action then
        rollback(spawning, shell, actionError)
        emit("spawn_failed", { uid = uid, stage = "watchdog", error = actionError })
        return nil, actionError
    end
    pcall(SpawnService.clearZone, spawning, shell)
    pcall(SpawnService.noteHydrate, spawning, shell, operationId)
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil then pcall(plus.popIn, spawning, shell, operationId) end
    local request = {
        uid = uid,
        generation = spawning.generation,
        operationId = operationId,
        fingerprint = fingerprint,
        shell = shell,
        action = action,
        status = "spawning",
    }
    SpawnService.pending[operationId] = request
    SpawnService.pendingOrder[#SpawnService.pendingOrder + 1] = operationId
    return request, false
end

function SpawnService.retire(uid, reason)
    local actor = Registry.read(uid)
    if actor == nil then return true end
    reason = reason or "catalog_deleted"
    local binding = Watchdog.bindings[uid]
    if binding ~= nil then
        local plus = ProjectALife.BlackBoxPlus
        if plus ~= nil then pcall(plus.vanish, actor, reason, actor.worldPosition, binding.shell) end
        local ok, cleaned = pcall(SpawnService.adapters.detachShell, actor, binding, reason)
        if not ok or cleaned == false then return false, "shell_cleanup_deferred" end
        binding.shell = nil
        Watchdog.unbind(uid, binding.generation, reason)
    end
    for index = #SpawnService.pendingOrder, 1, -1 do
        local id = SpawnService.pendingOrder[index]
        local request = SpawnService.pending[id]
        if request and request.uid == uid then
            request.status, request.reason = "failed", reason
            removePending(id)
        end
    end
    if actor.lifecycle ~= "dormant" and actor.lifecycle ~= "dead" then
        local dormant, failure = Registry.makeDormant(uid, actor.revision, actor.generation, actor.worldPosition)
        if dormant == nil then return false, failure end
        actor = dormant
    end
    return Registry.remove(uid, actor.revision, reason)
end

local function settleRequest(request)
    local action = request.action
    if action.status == "running" then return false end

    local binding = Watchdog.bindings[request.uid]
    if binding and binding.generation == request.generation then request.shell = binding.shell end
    local actor = Registry.read(request.uid)
    local catalog = ProjectALife.Catalog
    local deleted = actor and catalog and catalog.deletedReason
        and catalog.deletedReason(actor.factionId, actor.profileId)
    if deleted then return SpawnService.retire(actor.uid, deleted) end
    if action.status == "complete" and actor
        and actor.lifecycle == "spawning" and actor.generation == request.generation then
        local active, activeError = Registry.activate(
            actor.uid, actor.revision, actor.generation,
            type(SpawnService.adapters.shellPosition) == "function"
                and SpawnService.adapters.shellPosition(request.shell) or nil)
        if active then
            request.status = "active"
            request.revision = active.revision
            Interop.spawned(request.shell, active.uid, active.generation)
        else
            request.status = "failed"
            request.reason = activeError
            rollback(actor, request.shell, activeError)
            emit("spawn_failed", {
                uid = request.uid, stage = "activate", error = activeError,
            })
        end
    else
        request.status = "failed"
        request.reason = action.result or action.status
        if actor then
            rollback(actor, request.shell, request.reason)
            local rolledBack = Registry.read(actor.uid)
        end
    end

    SpawnService.settled[request.operationId] = request
    SpawnService.settledOrder[#SpawnService.settledOrder + 1] = request.operationId
    while #SpawnService.settledOrder > SpawnService.maximumSettled do
        SpawnService.settled[table.remove(SpawnService.settledOrder, 1)] = nil
    end
    removePending(request.operationId)
    return true
end

function SpawnService.tick(requestBudget, actionBudget, shellBudget)
    local maximum = math.max(1, math.floor(tonumber(requestBudget) or 2))
    local watchdogProcessed = SpawnService.watchdogTick(
        tonumber(actionBudget) or maximum,
        tonumber(shellBudget) or maximum)
    return watchdogProcessed + SpawnService.settleTick(maximum)
end

function SpawnService.watchdogTick(actionBudget, shellBudget)
    return Watchdog.tick(tonumber(actionBudget) or 2, tonumber(shellBudget) or 2)
end

function SpawnService.settleTick(requestBudget)
    local maximum = math.max(1, math.floor(tonumber(requestBudget) or 2))
    local processed = 0
    local index = 1
    while processed < maximum and index <= #SpawnService.pendingOrder do
        local request = SpawnService.pending[SpawnService.pendingOrder[index]]
        if request and settleRequest(request) then
            processed = processed + 1
        else
            index = index + 1
            processed = processed + 1
        end
    end
    return processed
end

function SpawnService.dehydrate(uid, reason)
    local actor = Registry.read(uid)
    local binding = Watchdog.bindings[uid]
    local forced = forcedDehydrate(reason)
    local saving = reason == "world_save"
    if not actor or (actor.lifecycle ~= "active" and not (saving
            and (actor.lifecycle == "spawning" or (actor.lifecycle == "dormant" and binding ~= nil)))) then
        return false, "active_shell_not_found"
    end
    if adminPersistent(actor) and not forced and not saving then
        return false, "actor_persistent"
    end
    if not binding and not forced then return false, "active_shell_not_found" end
    if saving and binding.generation ~= actor.generation then return false, "shell_generation_changed" end
    if saving and binding.saveCleanupFailed then
        local identity, generation = SpawnService.adapters.shellIdentity(binding.shell)
        if type(identity) ~= "string" or #identity == 0 or generation == nil then
            local completed = SpawnService.adapters.saveCleanupComplete
            if type(completed) ~= "function" or completed(binding.shell, binding.uid, binding.generation) ~= true then
                return false, "save_cleanup_identity_lost"
            end
        end
    end
    pcall(function()
        actor.memory = type(actor.memory) == "table" and actor.memory or {}
        actor.memory.dormantSinceHours = getGameTime():getWorldAgeHours()
    end)
    local currentShell = Watchdog.matches(binding)
    local position = currentShell
        and type(SpawnService.adapters.shellPosition) == "function"
        and SpawnService.adapters.shellPosition(binding.shell)
        or (binding and binding.lastPosition) or actor.worldPosition
    if saving and actor.lifecycle == "dormant" then position = actor.worldPosition end
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and not forced and not saving and actor.lifecycle == "active"
            and type(fairness.dehydrateRefusal) == "function" then
        local refused = fairness.dehydrateRefusal(position, reason, uid)
        if refused ~= nil then return false, refused end
    end
    local shellState
    if saving and currentShell and actor.lifecycle ~= "dormant"
            and type(SpawnService.adapters.captureShellState) ~= "function" then
        return false, "shell_state_capture_failed"
    end
    if currentShell and not forced and actor.lifecycle ~= "dormant"
            and type(SpawnService.adapters.captureShellState) == "function" then
        local captureOk, captured = pcall(
            SpawnService.adapters.captureShellState, binding.shell)
        if not captureOk or type(captured) ~= "table" then
            return false, "shell_state_capture_failed"
        end
        shellState = captured
    end
    local current = Registry.read(uid)
    local dormant, dormantError = Registry.makeDormant(
        uid, current.revision, current.generation, position, shellState, saving)
    if dormant == nil then return false, dormantError end
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil and not saving then pcall(plus.vanish, dormant, reason, position, currentShell and binding.shell or nil) end
    if saving then
        ProjectALife.ActionLedger.failActor(uid, current.generation, reason)
        for index = #SpawnService.pendingOrder, 1, -1 do
            local id = SpawnService.pendingOrder[index]
            local request = SpawnService.pending[id]
            if request and request.uid == uid then
                request.status, request.reason = "failed", reason
                removePending(id)
            end
        end
    end
    local factsOk, facts = pcall(SpawnService.dehydrateFacts, dormant, reason, binding, position, currentShell)
    if not factsOk then facts = nil end
    if type(SpawnService.adapters.onActorDormant) == "function" then
        pcall(SpawnService.adapters.onActorDormant, dormant, reason or "dehydrated")
    end
    if binding == nil then pcall(SpawnService.noteDehydrate, facts, nil, true, true) end
    if binding == nil then return true, dormantError end
    local cleanupOk, cleaned
    if currentShell then
        cleanupOk, cleaned = pcall(
            SpawnService.adapters.cleanupShell, binding.shell, reason or "dehydrated")
    else
        cleanupOk, cleaned = pcall(
            SpawnService.adapters.detachShell, dormant, binding, reason or "dehydrated")
    end
    pcall(SpawnService.noteDehydrate, facts, binding.shell, cleanupOk, cleaned)
    if facts ~= nil and facts.fate == "engine" and not saving then
        pcall(SpawnService.noteUnloaded, dormant, position)
    end
    if saving and (not cleanupOk or cleaned ~= true) then
        binding.saveCleanupFailed = true
        emit("shell_cleanup_deferred", { uid = uid, generation = binding.generation,
            reason = reason, error = cleanupOk and "cleanup_returned_false" or tostring(cleaned) })
        return false, "shell_cleanup_deferred"
    end
    local unbound, unbindError = Watchdog.unbind(
        uid, binding.generation, reason or "dehydrated")
    if not unbound and unbindError ~= "shell_not_bound" then
        return false, "shell_unbind_failed:" .. tostring(unbindError)
    end
    if not cleanupOk or cleaned == false then
        emit("shell_cleanup_deferred", {
            uid = uid,
            generation = binding.generation,
            reason = reason or "dehydrated",
            error = cleanupOk and "cleanup_returned_false" or tostring(cleaned),
        })
        return true, "shell_cleanup_deferred"
    end
    return true, dormantError
end

function SpawnService.parkForSave()
    local uids = {}
    Registry.each(function(actor)
        if actor.lifecycle == "active" or actor.lifecycle == "spawning"
                or (actor.lifecycle == "dormant" and Watchdog.bindings[actor.uid] ~= nil) then
            uids[#uids + 1] = actor.uid
        end
    end)
    local parked, failed = 0, 0
    for _, uid in ipairs(uids) do
        local ok, result, reason = pcall(SpawnService.dehydrate, uid, "world_save")
        if ok and result == true then
            parked = parked + 1
        else
            failed = failed + 1
            emit("save_park_failed", { uid = uid, error = ok and reason or tostring(result) })
        end
    end
    return failed == 0, parked, failed
end

function SpawnService.clearZone(actor, shell)
    local adapter = ProjectALife.ShellAdapter
    local radius = tonumber(SpawnService.clearRadius) or 0
    if radius <= 0 or adapter == nil or type(adapter.clearZone) ~= "function"
            or type(adapter.shellPosition) ~= "function" then return 0 end
    local at = adapter.shellPosition(shell) or actor.worldPosition
    if type(at) ~= "table" then return 0 end
    local reloaded = SpawnService.takeUnloaded(actor.uid)
    if reloaded then radius = math.max(radius, tonumber(SpawnService.reloadRadius) or radius) end
    local result = adapter.clearZone(at, radius, shell)
    local metrics = SpawnService.metrics
    metrics.spawnZombieScans = metrics.spawnZombieScans + 1
    metrics.spawnZombieClears = metrics.spawnZombieClears + result.removed
    if reloaded then metrics.reloadZombiesCleared = (metrics.reloadZombiesCleared or 0) + result.removed end
    metrics.spawnZombieWatched = metrics.spawnZombieWatched + result.watched
    if result.removed > 0 or result.watched > 0 then
        emit("spawn_zone_cleared", { uid = actor.uid, removed = result.removed, watched = result.watched,
            radius = radius, at = Watchdog.where(at) })
    end
    return result.removed
end

function SpawnService.reloadOn()
    local read = Watchdog.reloadGuard
    return type(read) == "function" and read() == true
end

function SpawnService.noteUnloaded(actor, position)
    if type(actor) ~= "table" or not SpawnService.reloadOn() then return false end
    local now = nowMs()
    if SpawnService.unloaded[actor.uid] == nil then
        if SpawnService.unloadedCount >= 256 then SpawnService.unloaded, SpawnService.unloadedCount = {}, 0 end
        SpawnService.unloadedCount = SpawnService.unloadedCount + 1
    end
    SpawnService.unloaded[actor.uid] = now
    if type(Watchdog.rememberLoss) == "function" then
        Watchdog.rememberLoss(actor.uid, position or actor.worldPosition, "unloaded_body", now, true)
    end
    return true
end

function SpawnService.takeUnloaded(uid)
    local since = SpawnService.unloaded[uid]
    if since == nil then return false end
    SpawnService.unloaded[uid] = nil
    SpawnService.unloadedCount = math.max(0, SpawnService.unloadedCount - 1)
    return SpawnService.reloadOn() and nowMs() - since <= (tonumber(Watchdog.lostTtlMs) or 1800000)
end

function SpawnService.noteHydrate(actor, shell, operationId)
    if not Watchdog.probing() then return end
    local at = ProjectALife.ShellAdapter.shellPosition(shell) or actor.worldPosition
    local fields = Watchdog.describeLoss({ uid = actor.uid, generation = actor.generation,
        op = string.match(tostring(operationId), "^([^:]+)") }, shell, at)
    emit("lifecycle_hydrate", Watchdog.placeFields(Watchdog.nearFields(fields, actor.uid, shell, at, nowMs()), at))
end

function SpawnService.dehydrateFacts(actor, reason, binding, position, currentShell)
    if not Watchdog.probing() then return nil end
    local body = "none"
    if binding ~= nil then body = currentShell and "bound" or "stale" end
    local population = ProjectALife.Population
    local fields = Watchdog.describeLoss({ uid = actor.uid, generation = actor.generation,
        reason = reason or "dehydrated", shell = body,
        limit = population ~= nil and population.dehydrateDistance or nil },
        binding ~= nil and binding.shell or nil, position)

    local adapter = ProjectALife.ShellAdapter
    if body == "stale" and type(adapter.shellIdentity) == "function" then
        local uid, generation = adapter.shellIdentity(binding.shell)
        if uid ~= binding.uid or generation ~= binding.generation then fields.fate = "reused" end
    end
    return Watchdog.placeFields(fields, position)
end

function SpawnService.noteDehydrate(facts, shell, cleanupOk, cleaned)
    if facts == nil then return end
    if shell == nil then
        facts.fate = "none"
    elseif facts.shell == "stale" and facts.inList == false then
        facts.fate = "engine"
    elseif facts.fate == nil then
        facts.fate = ProjectALife.ShellAdapter.fate(shell)
    end
    if cleanupOk and cleaned ~= false then facts.cleanup = "ok" else facts.cleanup = "failed" end
    emit("lifecycle_dehydrate", facts)
end

function SpawnService.checkpointOne(uid, binding, updates)
    local actor = (Registry.peek or Registry.read)(uid)
    if actor and actor.lifecycle == "active" and actor.generation == binding.generation
            and Watchdog.matches(binding) then
        local position = type(SpawnService.adapters.shellPosition) == "function"
            and SpawnService.adapters.shellPosition(binding.shell) or nil
        local captureOk, shellState = pcall(
            SpawnService.adapters.captureShellState, binding.shell)
        if position and captureOk and type(shellState) == "table" then
            updates[#updates + 1] = {
                uid = uid,
                generation = binding.generation,
                worldPosition = position,
                shellState = shellState,
            }
            return true, 0
        end
        return true, 1
    end
    return false, 0
end

function SpawnService.checkpointAll(budget)
    if type(SpawnService.adapters.captureShellState) ~= "function" then
        return true, 0, 0
    end
    local updates, failed = {}, 0
    local limit = tonumber(budget)
    if limit == nil or limit < 1 then
        for uid, binding in pairs(Watchdog.bindings) do
            local _, missed = SpawnService.checkpointOne(uid, binding, updates)
            failed = failed + missed
        end
    else
        local order = Watchdog.order
        local count, cursor, visited, taken = #order, tonumber(SpawnService.checkpointCursor) or 0, 0, 0
        while visited < count and taken < limit do
            cursor = cursor % count + 1
            visited = visited + 1
            local uid = order[cursor]
            local binding = Watchdog.bindings[uid]
            if binding ~= nil then
                local attempted, missed = SpawnService.checkpointOne(uid, binding, updates)
                if attempted then taken = taken + 1 end
                failed = failed + missed
            end
        end
        SpawnService.checkpointCursor = cursor
    end
    local ok, value = Registry.checkpointActive(updates)
    if not ok then return false, value, failed end
    return failed == 0, value, failed
end

return SpawnService
