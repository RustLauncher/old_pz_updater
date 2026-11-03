require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/World/ALifeSpawnService"
require "ProjectALife/World/ALifeWorldPressure"
require "ProjectALife/Decisions/ALifeReputation"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ActorRegistry
local Ledger = ProjectALife.ActionLedger
local Watchdog = ProjectALife.Watchdog
local SpawnService = ProjectALife.SpawnService
local StatusService = {
    adapters = {},
    lastRequestAtMs = {},
    minimumRequestIntervalMs = 1000,
    cached = nil,
    cachedAtMs = -math.huge,
    cacheIntervalMs = 500,
}
ProjectALife.StatusService = StatusService

local function count(source, predicate)
    local result = 0
    for _, value in pairs(source) do
        if predicate == nil or predicate(value) then result = result + 1 end
    end
    return result
end

local function nowMs()
    if type(StatusService.adapters.nowMs) == "function" then
        return StatusService.adapters.nowMs()
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function StatusService.configure(adapters)
    StatusService.adapters = adapters or {}
    StatusService.lastRequestAtMs = {}
    StatusService.cached = nil
    StatusService.cachedAtMs = -math.huge
end

function StatusService.snapshot()
    local currentTime = nowMs()
    if StatusService.cached ~= nil
            and currentTime - StatusService.cachedAtMs < StatusService.cacheIntervalMs then
        return StatusService.cached
    end
    local runtime = ProjectALife.Runtime
    local metrics = runtime and runtime.metrics or {}
    local pressure = ProjectALife.WorldPressure
    local pressureMetrics = type(pressure) == "table" and pressure.metrics or {}
    if type(pressureMetrics) ~= "table" then pressureMetrics = {} end
    local result = {
        version = runtime and runtime.VERSION or "1.3.15",
        total = 0,
        dormant = 0,
        spawning = 0,
        active = 0,
        dead = 0,
        shells = count(Watchdog.bindings),
        pendingSpawns = count(SpawnService.pending),
        runningActions = count(Ledger.entries, function(action)
            return action.status == "running"
        end),
        recoveries = 0,
        runtimeEnabled = runtime == nil or runtime.enabled ~= false,
        runtimeStarted = runtime ~= nil and runtime.started == true,
        tickCount = metrics.ticks or 0,
        lastTickMs = metrics.lastTickMs or 0,
        maximumTickMs = metrics.maximumTickMs or 0,
        tickBudget = runtime and runtime.tickBudget or 0,
        runtimeFaults = metrics.faults or 0,
        tickOverruns = metrics.overruns or 0,
        worldPressureCommitted = tonumber(pressureMetrics.committed) or 0,
        worldPressureRefused = tonumber(pressureMetrics.refused) or 0,
        worldPressureReason = tostring(pressureMetrics.lastRefusal or "none"),
        worldPressureRetryHours = tonumber(pressureMetrics.retryHours) or 0,
    }

    pcall(function()
        local ledger = ProjectALife.SquadLedger
        if ledger ~= nil and type(ledger.count) == "function" then
            result.offlineSquads = ledger.count()
        end
        local offline = ProjectALife.OfflineDirector
        if offline ~= nil then
            local m = offline.metrics or {}
            result.offlineTicks = m.ticks or 0
            result.offlineFounded = m.founded or 0

            result.offlineRefused = m.foundRefused or 0
            result.offlineRefusedWhy = offline.state and offline.state.lastFoundReason or nil
        end
    end)

    pcall(function()
        local director = ProjectALife.EncounterDirector
        if director == nil then return end
        result.encounterRolls = (director.metrics or {}).rolls or 0
        result.encounterPlaced = (director.metrics or {}).spawned or 0
        result.encounterAccepted = (director.metrics or {}).accepted or 0
    end)
    pcall(StatusService.addCensus, result)
    for _, actor in pairs(Registry.records) do
        result.total = result.total + 1
        if result[actor.lifecycle] ~= nil then
            result[actor.lifecycle] = result[actor.lifecycle] + 1
        end
    end
    for _, binding in pairs(Watchdog.bindings) do
        result.recoveries = result.recoveries + (binding.recoveries or 0)
    end
    local invariantErrors = 0
    for uid, actor in pairs(Registry.records) do
        local binding = Watchdog.bindings[uid]
        if (actor.lifecycle == "active" or actor.lifecycle == "spawning")
                and (binding == nil or binding.generation ~= actor.generation) then
            invariantErrors = invariantErrors + 1
        end
    end
    for uid, binding in pairs(Watchdog.bindings) do
        local actor = Registry.records[uid]
        if actor == nil or (actor.lifecycle ~= "active" and actor.lifecycle ~= "spawning")
                or actor.generation ~= binding.generation then
            invariantErrors = invariantErrors + 1
        end
    end
    for _, action in pairs(Ledger.entries) do
        local actor = Registry.records[action.uid]
        if action.status == "running" and (actor == nil
                or actor.generation ~= action.generation
                or (actor.lifecycle ~= "active" and actor.lifecycle ~= "spawning")) then
            invariantErrors = invariantErrors + 1
        end
    end
    local pendingDeaths = ProjectALife.Lifecycle
        and ProjectALife.Lifecycle.pendingCount() or 0
    result.healthErrors = invariantErrors
        + (result.runtimeStarted and runtime.lastError == nil and 0 or 1)
        + pendingDeaths
    result.healthWarnings = result.recoveries
    result.healthOk = result.healthErrors == 0
    result.pendingDeaths = pendingDeaths
    result.noSpawnZones = #Registry.noSpawnZones
    StatusService.cached = result
    StatusService.cachedAtMs = currentTime
    return result
end

function StatusService.addCensus(result)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusBrief) ~= "function" then return result end
    local brief = census.censusBrief()
    if type(brief) ~= "table" then return result end
    result.censusTotal, result.censusLiving, result.censusAlive = brief.total, brief.living, brief.alive
    result.censusKilled, result.censusArrivals = brief.dead, brief.arrived
    result.censusRoom, result.censusSpent = brief.room, brief.spent
    local catalog, parts = ProjectALife.Catalog, {}
    for index = 1, math.min(3, #brief.factions) do
        local row = brief.factions[index]
        local faction = type(catalog) == "table" and type(catalog.faction) == "function" and catalog.faction(row.id) or nil
        local name = type(faction) == "table" and type(faction.general) == "table" and faction.general.name or row.id
        parts[#parts + 1] = tostring(name) .. " " .. tostring(row.alive) .. "/" .. tostring(row.dead)
            .. "/" .. tostring(row.arrived)
    end
    result.censusFactions = table.concat(parts, ", ")
    return result
end

local function playerKey(player)
    local ok, username = pcall(function() return player:getUsername() end)
    return ok and tostring(username) or tostring(player)
end

local function send(player, payload)
    if type(StatusService.adapters.send) == "function" then
        return StatusService.adapters.send(player, "ProjectALife", "status", payload) ~= false
    end
    local dedicated = type(isServer) == "function" and isServer()
    if not dedicated and ProjectALife.StatusStore
            and type(ProjectALife.StatusStore.receive) == "function" then
        ProjectALife.StatusStore.receive("ProjectALife", "status", payload)
        return true
    end
    if type(sendServerCommand) ~= "function" then return false end
    sendServerCommand(player, "ProjectALife", "status", payload)
    return true
end

function StatusService.handle(module, command, player)
    if module ~= "ProjectALife" or command ~= "requestStatus" or player == nil then
        return false
    end
    local key, now = playerKey(player), nowMs()
    if now - (StatusService.lastRequestAtMs[key] or -math.huge)
            < StatusService.minimumRequestIntervalMs then
        return false
    end
    StatusService.lastRequestAtMs[key] = now
    local sent = send(player, StatusService.snapshot())
    if ProjectALife.Reputation ~= nil then
        ProjectALife.Reputation.sync(player)
    end
    return sent
end

function StatusService.register()
    if StatusService.registered or type(Events) ~= "table"
            or Events.OnClientCommand == nil then return false end
    StatusService.registered = true
    Events.OnClientCommand.Add(StatusService.handle)
    return true
end

return StatusService
