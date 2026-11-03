ProjectALife = ProjectALife or {}

local Ledger = {
    VERSION = 1,
    entries = {},
    order = {},
    activeByActor = {},
    cursor = 0,
    tickStamp = 0,
    maximumEntries = 256,

    priorityBudget = 16,
    priorityMs = 6,
    priorityMaxAge = 3,
    priorityCombatAge = 2,
    terminalRetentionMs = 30000,
    adapters = {},

    metrics = { begins = 0, refused = {} },
}
ProjectALife.ActionLedger = Ledger

local function nowMs()
    if type(Ledger.adapters.nowMs) == "function" then
        return Ledger.adapters.nowMs()
    end
    if type(getTimestampMs) == "function" then
        return getTimestampMs()
    end
    return math.floor(os.time() * 1000)
end

local function emit(category, fields)
    if type(Ledger.adapters.emit) == "function" then
        Ledger.adapters.emit(category, fields)
    end
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function integer(value)
    return finite(value) and value >= 0 and value == math.floor(value)
end

local function token(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
end

local function actorKey(uid, generation)
    return uid .. ":" .. tostring(generation)
end

local function remove(operationId)
    local action = Ledger.entries[operationId]
    if action then
        local key = actorKey(action.uid, action.generation)
        if Ledger.activeByActor[key] == operationId then
            Ledger.activeByActor[key] = nil
        end
    end
    Ledger.entries[operationId] = nil
    for index, candidate in ipairs(Ledger.order) do
        if candidate == operationId then
            table.remove(Ledger.order, index)
            if Ledger.cursor >= index then
                Ledger.cursor = math.max(0, Ledger.cursor - 1)
            end
            return
        end
    end
end

local function makeRoom()
    if #Ledger.order < Ledger.maximumEntries then return true end
    for _, operationId in ipairs(Ledger.order) do
        local action = Ledger.entries[operationId]
        if action and action.status ~= "running" then
            remove(operationId)
            return true
        end
    end
    return false
end

local function settle(action, status, result, now)
    if action.status ~= "running" then
        return action.status == status and action.result == result,
            action.status == status and "already_terminal" or "terminal_conflict"
    end
    action.status = status
    action.result = result
    action.finishedAtMs = now or nowMs()
    Ledger.activeByActor[actorKey(action.uid, action.generation)] = nil
    emit("action_settled", {
        uid = action.uid,
        generation = action.generation,
        operationId = action.operationId,
        status = status,
        result = result,
    })
    return true
end

local function call(action, name)
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog and watchdog.bindings[action.uid]
    if binding and action.kind ~= "spawn" and (binding.generation ~= action.generation
            or not watchdog.matches(binding)) then

        return true, false
    end

    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.clientAuthority) == "function" and executor.clientAuthority() then
        local entry = executor.executed[action.uid]
        if entry == nil or not executor.authorityFor(entry.shell) then return true, false end
    end
    local ok, result = pcall(action[name], action)
    if not ok then
        action.lastError = tostring(result)
        emit("action_handler_failed", {
            uid = action.uid,
            operationId = action.operationId,
            handler = name,
            error = action.lastError,
        })
    end
    return ok, result
end

function Ledger.configure(adapters)
    Ledger.adapters = adapters or {}
end

function Ledger.reset()
    Ledger.entries = {}
    Ledger.order = {}
    Ledger.activeByActor = {}
    Ledger.cursor = 0

    Ledger.priorityCursor = 0
end

function Ledger.begin(specification)
    if type(specification) ~= "table" then return nil, "action_required" end
    if not token(specification.operationId, 128) then return nil, "operation_id_invalid" end
    if not token(specification.uid, 64) then return nil, "uid_invalid" end
    if not integer(specification.generation) then return nil, "generation_invalid" end
    if not token(specification.fingerprint, 256) then return nil, "fingerprint_invalid" end
    if not finite(specification.startedAtMs) or not finite(specification.deadlineAtMs)
        or specification.deadlineAtMs <= specification.startedAtMs then
        return nil, "deadline_invalid"
    end
    if type(specification.isComplete) ~= "function"
        or type(specification.cancel) ~= "function"
        or type(specification.recover) ~= "function" then
        return nil, "handlers_invalid"
    end
    local existing = Ledger.entries[specification.operationId]
    if existing then
        if existing.uid == specification.uid
            and existing.generation == specification.generation
            and existing.fingerprint == specification.fingerprint then
            return existing, "already_registered"
        end
        return nil, "operation_id_conflict"
    end
    local key = actorKey(specification.uid, specification.generation)
    if Ledger.activeByActor[key] then return nil, "actor_action_conflict" end
    if not makeRoom() then return nil, "ledger_capacity_reached" end
    local maximumRecoveries = specification.maximumRecoveries or 0
    local retryDelayMs = specification.retryDelayMs or 0
    if not integer(maximumRecoveries) or not finite(retryDelayMs) or retryDelayMs < 0 then
        return nil, "recovery_policy_invalid"
    end
    local action = {
        operationId = specification.operationId,
        uid = specification.uid,
        generation = specification.generation,
        kind = specification.kind or "unknown",
        fingerprint = specification.fingerprint,
        startedAtMs = specification.startedAtMs,
        deadlineAtMs = specification.deadlineAtMs,
        timeoutMs = specification.deadlineAtMs - specification.startedAtMs,
        isComplete = specification.isComplete,
        cancel = specification.cancel,
        recover = specification.recover,
        maximumRecoveries = maximumRecoveries,
        recoveryAttempts = 0,
        retryDelayMs = retryDelayMs,
        fallback = specification.fallback or "safe_dormant",
        status = "running",
    }
    Ledger.entries[action.operationId] = action
    Ledger.order[#Ledger.order + 1] = action.operationId
    Ledger.activeByActor[key] = action.operationId
    return action
end

local beginInternal = Ledger.begin
function Ledger.begin(specification)
    local action, reason = beginInternal(specification)
    Ledger.metrics.begins = Ledger.metrics.begins + 1
    if action == nil then
        local key = tostring(reason)
        Ledger.metrics.refused[key] = (Ledger.metrics.refused[key] or 0) + 1
    end
    return action, reason
end

function Ledger.complete(operationId, result)
    local action = Ledger.entries[operationId]
    if not action then return false, "action_not_found" end
    return settle(action, "complete", result or "complete")
end

function Ledger.fail(operationId, result)
    local action = Ledger.entries[operationId]
    if not action then return false, "action_not_found" end
    return settle(action, "failed", result or "failed")
end

function Ledger.cancelActor(uid, generation, reason)
    local operationId = Ledger.activeByActor[actorKey(uid, generation)]
    local action = operationId and Ledger.entries[operationId] or nil
    if not action then return 0 end
    call(action, "cancel")
    settle(action, "cancelled", reason or "actor_cancelled")
    return 1
end

function Ledger.failActor(uid, generation, reason)
    local operationId = Ledger.activeByActor[actorKey(uid, generation)]
    if not operationId then return 0 end
    Ledger.fail(operationId, reason or "actor_failed")
    return 1
end

function Ledger.get(operationId)
    return Ledger.entries[operationId]
end

local function inspect(action, now)
    if action.status ~= "running" then
        if action.finishedAtMs and now - action.finishedAtMs >= Ledger.terminalRetentionMs then
            remove(action.operationId)
        end
        return
    end
    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.clientAuthority) == "function" and executor.clientAuthority() then
        local entry = executor.executed[action.uid]
        if entry == nil or not executor.authorityFor(entry.shell) then return end
    end
    local completeOk, completed = call(action, "isComplete")
    if action.status ~= "running" then return end
    if completeOk and completed == true then
        settle(action, "complete", "predicate_satisfied", now)
        return
    end

    if not completeOk then
        action.callbackErrors = (action.callbackErrors or 0) + 1
        if action.callbackErrors >= 3 then
            call(action, "cancel")
            settle(action, "expired", "callback_error", now)
            return
        end
    else
        action.callbackErrors = nil
    end
    if now < action.deadlineAtMs then return end
    call(action, "cancel")
    if action.recoveryAttempts >= action.maximumRecoveries then
        settle(action, "expired", action.fallback, now)
        return
    end
    action.recoveryAttempts = action.recoveryAttempts + 1
    local recoveryOk, recovered = call(action, "recover")
    if not recoveryOk or recovered ~= true then
        settle(action, "expired", "recovery_failed", now)
        return
    end
    action.startedAtMs = now
    action.deadlineAtMs = now + math.max(action.timeoutMs, action.retryDelayMs)
end

local PRIORITY_KINDS = { combat = true, movement = true }

function Ledger.timedInspect(action, now)
    local started = nowMs()
    inspect(action, now)
    local spent = nowMs() - started
    if spent > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then
            runtime.noteDetail("ledger:" .. tostring(action.kind), spent)
        end
    end
    if spent > (Ledger.metrics.worstInspectMs or 0) then Ledger.metrics.worstInspectMs = spent end
end

function Ledger.tick(budget)
    local maximum = math.min(#Ledger.order, math.max(1, math.floor(tonumber(budget) or 1)))
    local now = nowMs()
    local processed = 0

    local stamp = (tonumber(Ledger.tickStamp) or 0) + 1
    Ledger.tickStamp = stamp

    local priorityBudget = math.max(1, math.min(Ledger.priorityBudget or 8, #Ledger.order))
    local capMs = tonumber(Ledger.priorityMs)
    local maxAge = tonumber(Ledger.priorityMaxAge) or 3
    local combatAge = tonumber(Ledger.priorityCombatAge) or 2
    local priorityCount, visited = 0, 0
    local commit = tonumber(Ledger.priorityCursor) or 0
    local scan = commit
    local frozen, sliced, forced, carried = false, false, 0, 0
    while priorityCount < priorityBudget and visited < #Ledger.order do
        scan = scan % #Ledger.order + 1
        visited = visited + 1
        local key = Ledger.order[scan]
        local action = Ledger.entries[key]
        local due = action ~= nil and action.servicedStamp ~= stamp and PRIORITY_KINDS[action.kind] == true
            and action.status == "running"
        local serve = due
        if due and capMs ~= nil and priorityCount >= 1 and nowMs() - now >= capMs then
            local age = stamp - (tonumber(action.servicedStamp) or (stamp - 1))
            if age >= (action.kind == "combat" and combatAge or maxAge) and forced < 1 then
                forced = forced + 1
            else
                serve = false
                sliced = true
                carried = carried + 1
                if not frozen then
                    frozen = true
                    commit = scan - 1
                    if commit < 1 then commit = #Ledger.order end
                end
            end
        end
        if serve then
            action.servicedStamp = stamp
            Ledger.timedInspect(action, now)
            priorityCount = priorityCount + 1
        end
        if not frozen then commit = scan end
    end
    Ledger.priorityCursor = commit
    if sliced then
        local metrics = Ledger.metrics
        metrics.prioritySliced = (metrics.prioritySliced or 0) + 1
        metrics.priorityCarried = (metrics.priorityCarried or 0) + carried
        if forced > 0 then metrics.priorityForced = (metrics.priorityForced or 0) + forced end
    end
    local spentMs = nowMs() - now
    if spentMs > (Ledger.metrics.priorityWorstMs or 0) then Ledger.metrics.priorityWorstMs = spentMs end

    while processed < maximum and #Ledger.order > 0 do
        Ledger.cursor = (Ledger.cursor % #Ledger.order) + 1
        local key = Ledger.order[Ledger.cursor]
        local action = Ledger.entries[key]
        if action and action.servicedStamp ~= stamp
                and not (sliced and PRIORITY_KINDS[action.kind] == true and action.status == "running") then
            action.servicedStamp = stamp
            Ledger.timedInspect(action, now)
        end
        processed = processed + 1
    end
    return processed + priorityCount
end

return Ledger
