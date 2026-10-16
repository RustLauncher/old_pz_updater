ProjectALife = ProjectALife or {}

local Telemetry = {
    capacity = 96,
    events = {},
    counters = {},
    sequence = 0,
    adapters = {},

    lifecycleCap = 500,
    lifecycleBurst = 40,
    lifecycleState = {},

    offlineBurst = 5,
    offlinePerMinute = 30,
    offlineState = {},
}
ProjectALife.Telemetry = Telemetry

Telemetry.lifecycleKeys = {
    "uid", "generation", "reason", "op", "shell", "fate", "cleanup", "at", "bodyAt", "jump",
    "nearest", "limit", "loaded", "ring", "edge", "win", "squareNil", "inList", "onlineId",
    "state", "ageMs", "seenMs", "goneMs", "chunkPlain", "mates3", "stale3", "anim3", "plain3",
    "nearestPlain", "lostAt", "fromLoss", "lossAgoS", "plainAtLoss", "outfit", "cellZeds",
    "cullAt", "side",
}

local function nowMs()
    if type(Telemetry.adapters.nowMs) == "function" then return Telemetry.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function safeValue(value)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" then return value end
    if kind == "string" then return string.sub(value, 1, 256) end
    return tostring(value)
end

function Telemetry.configure(adapters)
    Telemetry.adapters = adapters or {}
    Telemetry.capacity = math.max(16, math.min(256,
        math.floor(tonumber(Telemetry.adapters.capacity) or 96)))
end

function Telemetry.reset()
    Telemetry.events = {}
    Telemetry.counters = {}
    Telemetry.sequence = 0
    Telemetry.lifecycleState = {}
    Telemetry.offlineState = {}
end

function Telemetry.emit(category, fields)
    category = type(category) == "string" and category or "unknown"
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil and type(fields) == "table" and fields.error ~= nil then
        pcall(plus.luaError, category, fields.error, false, fields.subsystem)
    end
    Telemetry.sequence = Telemetry.sequence + 1
    Telemetry.counters[category] = (Telemetry.counters[category] or 0) + 1
    local event = { sequence = Telemetry.sequence, atMs = nowMs(), category = category }
    for key, value in pairs(fields or {}) do
        if type(key) == "string" then event[key] = safeValue(value) end
    end

    local lifecycle = string.sub(category, 1, 10) == "lifecycle_"
    local offline = string.sub(category, 1, 8) == "offline_"
    local shown = true
    if offline then shown = Telemetry.offlineAdmit(event) end
    if not lifecycle then
        if shown then Telemetry.events[#Telemetry.events + 1] = event end
        while #Telemetry.events > Telemetry.capacity do table.remove(Telemetry.events, 1) end
    end
    if type(Telemetry.adapters.log) == "function" then
        pcall(Telemetry.adapters.log, event)
    elseif category == "runtime_fault" or category == "runtime_start_failed" then
        pcall(print, "[Project A-Life] " .. category .. ": " .. tostring(event.error or "unknown"))
    elseif category == "runtime_slow_tick" then
        pcall(print, "[ALIFE-PERF] tick=" .. tostring(event.elapsedMs) .. "ms slowest="
            .. tostring(event.subsystem) .. ":" .. tostring(event.subsystemMs) .. "ms")
    elseif category == "runtime_hitch_summary" then

        pcall(print, "[ALIFE-PERF] " .. tostring(event.windowS) .. "s hitches="
            .. tostring(event.count) .. " " .. tostring(event.hitches))
    elseif category == "shell_recovery" or category == "spawn_rollback"
            or category == "action_handler_failed" or category == "orphan_shell_removed"
            or (category == "shell_unbound"
                and string.sub(tostring(event.reason), 1, 18) == "watchdog_exhausted") then
        local line = "[ALIFE-LIFECYCLE] " .. category .. " uid=" .. tostring(event.uid)
            .. " generation=" .. tostring(event.generation) .. " reason="
            .. tostring(event.reason or event.error) .. " attempt=" .. tostring(event.attempt)
        if category == "shell_recovery" or category == "shell_unbound" then

            line = line .. " recovered=" .. tostring(event.recovered)
                .. " error=" .. tostring(event.error)
                .. " squareNil=" .. tostring(event.squareNil)
                .. " inList=" .. tostring(event.inList)
                .. " onlineId=" .. tostring(event.onlineId)
                .. " newOnlineId=" .. tostring(event.newOnlineId)
                .. " loaded=" .. tostring(event.loaded)
                .. " nearest=" .. tostring(event.nearest)
                .. " at=" .. tostring(event.at)
                .. " bodyAt=" .. tostring(event.bodyAt)
        end
        pcall(print, line)
    elseif lifecycle then
        Telemetry.printLifecycle(event)
    elseif category == "admin_spawn_failed" or category == "spawn_failed" then

        pcall(print, "[ALIFE-SPAWN] " .. category
            .. " request=" .. tostring(event.requestId or event.uid or "?")
            .. " mode=" .. tostring(event.mode or "?")
            .. " error=" .. tostring(event.error or "unknown"))
    elseif string.sub(category, 1, 8) == "support_" then
        pcall(print, "[ALIFE-SUPPORT] " .. category
            .. " group=" .. tostring(event.squad or "?")
            .. " faction=" .. tostring(event.factionId or "-")
            .. " callerFaction=" .. tostring(event.callerFactionId or "-")
            .. " delivery=" .. tostring(event.delivery or "-")
            .. " " .. tostring(event.task or "") .. " count=" .. tostring(event.count or "-"))
    elseif string.sub(category, 1, 8) == "outpost_" then
        pcall(print, "[ALIFE-OUTPOST] " .. category
            .. " site=" .. tostring(event.site or "?")
            .. " " .. tostring(event.preset or event.reason or event.count or "")
            .. Telemetry.outpostTail(event))
    elseif offline then

        if shown then
            local line = "[ALIFE-OFFLINE] " .. category
                .. " squad=" .. tostring(event.squad or "?")
                .. " " .. tostring(event.task or event.name or event.town or event.reason or "")
            if event.town ~= nil and (event.task ~= nil or event.name ~= nil) then
                line = line .. " " .. Telemetry.townText(event)
            end
            pcall(print, line)
        end
    elseif string.sub(category, 1, 9) == "populate_" then
        pcall(print, "[ALIFE-POPULATE] " .. category
            .. " town=" .. tostring(event.town or "-") .. " key=" .. tostring(event.key or "-")
            .. " faction=" .. tostring(event.faction or "-") .. " category=" .. tostring(event.category or "-")
            .. " places=" .. tostring(event.places or event.count or "-")
            .. " distance=" .. tostring(event.distance or "-") .. " reason=" .. tostring(event.reason or "-"))
    elseif category == "admin_spawn" or category == "admin_spawn_started"
            or category == "director_spawn" then
        pcall(print, "[ALIFE-SPAWN] " .. category
            .. " request=" .. tostring(event.requestId or "?")
            .. " mode=" .. tostring(event.mode or "?")
            .. " accepted=" .. tostring(event.accepted or "-")
            .. " failed=" .. tostring(event.failed or event.error or "-"))
    end
    return event
end

function Telemetry.outpostTail(event)
    local tail = ""
    for _, key in ipairs(Telemetry.outpostKeys) do
        if event[key] ~= nil then tail = tail .. " " .. key .. "=" .. tostring(event[key]) end
    end
    return tail
end
Telemetry.outpostKeys = { "removed", "left", "x", "y", "z", "sprite" }

function Telemetry.townText(event)
    local graph = ProjectALife.RoadGraph
    local node = graph ~= nil and type(graph.nodes) == "table" and graph.nodes[event.town] or nil
    if type(node) ~= "table" then node = {} end
    local name = event.townName or event.where or node.name
    local x = tonumber(event.x) or tonumber(node.x)
    local y = tonumber(event.y) or tonumber(node.y)
    local region = "-"
    local regions = ProjectALife.TownRegions
    if x ~= nil and y ~= nil and regions ~= nil and type(regions.distanceToTown) == "function" then
        local ok, distance, town = pcall(regions.distanceToTown, { x = x, y = y })
        if ok and type(town) == "table" and tonumber(distance) ~= nil then
            region = tostring(town.label or town.id)
            if distance > 0 then region = region .. "+" .. math.floor(distance) end
        end
    end
    return "town=" .. tostring(event.town) .. (name ~= nil and (" \"" .. tostring(name) .. "\"") or "")
        .. " region=" .. region
        .. (x ~= nil and y ~= nil and (" at=" .. math.floor(x) .. "," .. math.floor(y)) or "")
end

function Telemetry.offlineAdmit(event)
    local category, at = event.category, tonumber(event.atMs) or 0
    local state = Telemetry.offlineState[category]
    if state == nil then
        state = { minuteAtMs = at, printed = 0, dropped = 0, secondAtMs = at, secondCount = 0 }
        Telemetry.offlineState[category] = state
    end
    if at < state.minuteAtMs or at - state.minuteAtMs >= 60000 then Telemetry.offlineSummary(category, state, at) end
    if at < state.secondAtMs or at - state.secondAtMs >= 1000 then
        state.secondAtMs, state.secondCount = at, 0
    end
    if state.printed >= Telemetry.offlinePerMinute or state.secondCount >= Telemetry.offlineBurst then
        state.dropped = state.dropped + 1
        return false
    end
    state.printed, state.secondCount = state.printed + 1, state.secondCount + 1
    return true
end

function Telemetry.offlineSummary(category, state, at)
    if state.dropped > 0 then
        pcall(print, "[ALIFE-OFFLINE] offline_summary squad=- " .. tostring(category)
            .. " printed=" .. tostring(state.printed) .. " dropped=" .. tostring(state.dropped)
            .. " windowS=" .. tostring(math.floor(math.max(0, at - state.minuteAtMs) / 1000)))
    end
    state.minuteAtMs, state.printed, state.dropped = at, 0, 0
end

function Telemetry.flushOffline()
    local at = nowMs()
    for category, state in pairs(Telemetry.offlineState) do
        if at < state.minuteAtMs or at - state.minuteAtMs >= 60000 then Telemetry.offlineSummary(category, state, at) end
    end
end

function Telemetry.printLifecycle(event)
    local category = event.category
    local state = Telemetry.lifecycleState[category]
    if state == nil then
        state = { printed = 0, dropped = 0, windowAtMs = event.atMs, windowCount = 0 }
        Telemetry.lifecycleState[category] = state
    end
    if event.atMs < state.windowAtMs or event.atMs - state.windowAtMs >= 1000 then
        state.windowAtMs, state.windowCount = event.atMs, 0
    end
    if state.printed >= Telemetry.lifecycleCap then
        state.dropped = state.dropped + 1
        if state.capped ~= true then
            state.capped = true
            pcall(print, "[ALIFE-LIFECYCLE] capped name=" .. string.sub(category, 11)
                .. " cap=" .. tostring(Telemetry.lifecycleCap))
        end
        return false
    end
    if state.windowCount >= Telemetry.lifecycleBurst then
        state.dropped = state.dropped + 1
        return false
    end
    state.printed, state.windowCount = state.printed + 1, state.windowCount + 1
    local parts = { "[ALIFE-LIFECYCLE]", string.sub(category, 11) }
    for _, key in ipairs(Telemetry.lifecycleKeys) do
        local value = event[key]
        if value ~= nil then parts[#parts + 1] = key .. "=" .. tostring(value) end
    end
    if state.dropped > 0 then
        parts[#parts + 1] = "dropped=" .. tostring(state.dropped)
        state.dropped = 0
    end
    pcall(print, table.concat(parts, " "))
    return true
end

function Telemetry.count(category)
    return Telemetry.counters[category] or 0
end

function Telemetry.snapshot(limit)
    local maximum = math.max(0, math.min(Telemetry.capacity,
        math.floor(tonumber(limit) or 20)))
    local events = {}
    local first = math.max(1, #Telemetry.events - maximum + 1)
    for index = first, #Telemetry.events do
        local copy = {}
        for key, value in pairs(Telemetry.events[index]) do copy[key] = value end
        events[#events + 1] = copy
    end
    local counters = {}
    for key, value in pairs(Telemetry.counters) do counters[key] = value end
    return { sequence = Telemetry.sequence, counters = counters, events = events }
end

return Telemetry
