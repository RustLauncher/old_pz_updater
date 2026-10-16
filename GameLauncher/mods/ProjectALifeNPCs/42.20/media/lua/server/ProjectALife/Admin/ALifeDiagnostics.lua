require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifeActionLedger"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/World/ALifeSpawnService"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/Audio/ALifeVoice"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Registry = ProjectALife.ActorRegistry
local Ledger = ProjectALife.ActionLedger
local Watchdog = ProjectALife.Watchdog
local SpawnService = ProjectALife.SpawnService
local Telemetry = ProjectALife.Telemetry
local Voice = ProjectALife.Voice
local Diagnostics = {}
ProjectALife.Diagnostics = Diagnostics

local function count(source, predicate)
    local total = 0
    for _, value in pairs(source or {}) do
        if predicate == nil or predicate(value) then total = total + 1 end
    end
    return total
end

local function add(issues, severity, code, detail)
    if #issues >= 64 then return end
    issues[#issues + 1] = {
        severity = severity,
        code = code,
        detail = string.sub(tostring(detail or ""), 1, 256),
    }
end

local function bindingValid(actor, binding)
    if binding == nil or binding.generation ~= actor.generation then return false end
    if type(Watchdog.adapters.shellAlive) ~= "function" then return binding.shell ~= nil end
    local ok, alive = pcall(Watchdog.adapters.shellAlive, binding.shell)
    if not ok or alive ~= true then return false end
    if type(Watchdog.adapters.shellIdentity) == "function" then
        local identityOk, uid, generation = pcall(
            Watchdog.adapters.shellIdentity, binding.shell)
        return identityOk and uid == actor.uid and generation == actor.generation
    end
    return true
end

local function shellHealth(shell)
    local loadoutErrors, stateErrors = 0, 0
    local weaponJamCount, weaponJammed = 0, false
    local dataOk, data = pcall(function() return shell:getModData() end)
    if dataOk and type(data) == "table" then
        loadoutErrors = math.max(0,
            math.floor(tonumber(data.ProjectALifeLoadoutErrors) or 0))
        stateErrors = math.max(0,
            math.floor(tonumber(data.ProjectALifeStateErrors) or 0))
        weaponJamCount = math.max(0,
            math.floor(tonumber(data.ProjectALifeWeaponJamCount) or 0))
        weaponJammed = data.ProjectALifeWeaponJammed == true
    end

    local inventoryOk, items = pcall(function()
        local inventory = shell:getInventory()
        return inventory and inventory:getItems() or nil
    end)
    if not inventoryOk or items == nil then
        return loadoutErrors, stateErrors, nil, weaponJamCount, weaponJammed
    end
    local countOk, itemCount = pcall(function() return items:size() end)
    if not countOk then
        return loadoutErrors, stateErrors, nil, weaponJamCount, weaponJammed
    end
    for index = 0, itemCount - 1 do
        local itemOk, item = pcall(function() return items:get(index) end)
        local weaponOk, weapon = pcall(function() return item and item:IsWeapon() end)
        if itemOk and weaponOk and weapon == true then
            return loadoutErrors, stateErrors, true, weaponJamCount, weaponJammed
        end
    end
    return loadoutErrors, stateErrors, false, weaponJamCount, weaponJammed
end

function Diagnostics.snapshot()
    local issues = {}
    local actors = Registry.list()
    if Catalog.current == nil then add(issues, "error", "catalog_unloaded") end
    local runtime = ProjectALife.Runtime
    if runtime == nil or runtime.started ~= true then
        add(issues, "error", "runtime_not_started", runtime and runtime.lastError)
    elseif runtime.lastError ~= nil then
        add(issues, "error", "runtime_last_error", runtime.lastError)
    end

    local lifecycle = { dormant = 0, spawning = 0, active = 0, dead = 0 }
    local loadoutErrors, stateErrors, unarmedShells = 0, 0, 0
    local weaponJams, jammedShells = 0, 0
    for _, actor in ipairs(actors) do
        lifecycle[actor.lifecycle] = (lifecycle[actor.lifecycle] or 0) + 1
        local profile = Catalog.npc(actor.profileId)
        if profile == nil then
            add(issues, "error", "actor_profile_missing", actor.uid .. ":" .. actor.profileId)
        elseif Catalog.faction(actor.factionId) == nil
                or not profile.general or profile.general.faction ~= actor.factionId then
            add(issues, "error", "actor_faction_missing", actor.uid .. ":" .. actor.factionId)
        end
        local binding = Watchdog.bindings[actor.uid]
        local requiresShell = actor.lifecycle == "active" or actor.lifecycle == "spawning"
        local validBinding = not requiresShell or bindingValid(actor, binding)
        if requiresShell and not validBinding then
            add(issues, "error", "actor_missing_shell",
                actor.uid .. ":" .. actor.lifecycle .. ":" .. actor.generation)
        elseif (actor.lifecycle == "dormant" or actor.lifecycle == "dead")
                and binding ~= nil then
            add(issues, "error", "inactive_actor_has_shell", actor.uid)
        end
        if actor.lifecycle == "active" and validBinding then
            local actorLoadoutErrors, actorStateErrors, armed,
                actorWeaponJams, actorWeaponJammed = shellHealth(binding.shell)
            loadoutErrors = loadoutErrors + actorLoadoutErrors
            stateErrors = stateErrors + actorStateErrors
            weaponJams = weaponJams + actorWeaponJams
            if actorWeaponJammed then jammedShells = jammedShells + 1 end
            if actorLoadoutErrors > 0 then
                add(issues, "error", "shell_loadout_errors",
                    actor.uid .. ":" .. tostring(actorLoadoutErrors))
            end
            if actorStateErrors > 0 then
                add(issues, "error", "shell_state_restore_errors",
                    actor.uid .. ":" .. tostring(actorStateErrors))
            end
            if armed == false then
                unarmedShells = unarmedShells + 1
                add(issues, "error", "shell_unarmed", actor.uid)
            end
        end
    end
    for uid, binding in pairs(Watchdog.bindings) do
        local actor = Registry.read(uid)
        if actor == nil then
            add(issues, "error", "orphan_shell", uid)
        elseif actor.generation ~= binding.generation then
            add(issues, "error", "stale_shell_generation", uid)
        end
    end
    for operationId, request in pairs(SpawnService.pending) do
        local actor = Registry.read(request.uid)
        if actor == nil or actor.lifecycle ~= "spawning"
                or actor.generation ~= request.generation then
            add(issues, "error", "stale_spawn_request", operationId)
        end
    end
    for operationId, action in pairs(Ledger.entries) do
        if action.status == "running" then
            local actor = Registry.read(action.uid)
            local activeKey = action.uid .. ":" .. tostring(action.generation)
            if actor == nil then
                add(issues, "error", "orphan_action", operationId)
            elseif actor.generation ~= action.generation
                    or (actor.lifecycle ~= "active" and actor.lifecycle ~= "spawning") then
                add(issues, "error", "stale_action", operationId)
            elseif Ledger.activeByActor[activeKey] ~= operationId then
                add(issues, "error", "action_index_mismatch", operationId)
            elseif not bindingValid(actor, Watchdog.bindings[action.uid]) then
                add(issues, "error", "action_shell_mismatch", operationId)
            end
        end
    end

    local retrying = 0
    if ProjectALife.Population then
        retrying = count(ProjectALife.Population.retryAtMs)
        if retrying > 0 then add(issues, "warning", "population_spawn_backoff", retrying) end
    end

    local errors, warnings = 0, 0
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then errors = errors + 1 else warnings = warnings + 1 end
    end
    local telemetry = Telemetry.snapshot(12)
    return {
        ok = errors == 0,
        errors = errors,
        warnings = warnings,
        issues = issues,
        actors = #actors,
        dormant = lifecycle.dormant,
        spawning = lifecycle.spawning,
        active = lifecycle.active,
        dead = lifecycle.dead,
        shells = count(Watchdog.bindings),
        pendingSpawns = count(SpawnService.pending),
        runningActions = count(Ledger.entries, function(action)
            return action.status == "running"
        end),
        noSpawnZones = type(Registry.listNoSpawnZones) == "function"
            and #Registry.noSpawnZones or 0,
        catalogFactions = Catalog.current and #Catalog.current.factionOrder or 0,
        catalogProfiles = Catalog.current and #Catalog.current.npcOrder or 0,
        populationRetries = retrying,
        shellLoadoutErrors = loadoutErrors,
        shellStateErrors = stateErrors,
        unarmedShells = unarmedShells,
        weaponJams = weaponJams,
        jammedShells = jammedShells,
        directorDecision = ProjectALife.Director and ProjectALife.Director.lastDecision
            or "unavailable",
        queuedAdminSpawns = ProjectALife.DebugService and #ProjectALife.DebugService.queue or 0,
        runtimeFaults = telemetry.counters.runtime_fault or 0,
        lastHistoricalFault = runtime and runtime.metrics and runtime.metrics.lastFault or nil,
        orphanShellsRemoved = ProjectALife.OrphanGuard
            and ProjectALife.OrphanGuard.removed or 0,
        movement = ProjectALife.Movement and {
            pathRequested = ProjectALife.Movement.metrics.requested or 0,
            requestErrors = ProjectALife.Movement.metrics.requestErrors or 0,
            stalls = ProjectALife.Movement.metrics.stalls or 0,
            traversalFailures = ProjectALife.Movement.metrics.traversalFailures or 0,
            unreachableFailures = ProjectALife.Movement.metrics.unreachableFailures or 0,
            lastFailure = ProjectALife.Movement.metrics.lastFailure,
        } or nil,
        voice = Voice and Voice.snapshot() or nil,
        recentEvents = telemetry.events,
        capabilities = {
            shell = "zombie_proxy",
            supportedMode = "singleplayer",
            multiplayer = "experimental_unverified",
            firearm = "server_simulated",
            weaponJamming = "sandbox_configurable_non_revolver",
            gestures = "additive_nodes_with_client_sync",
            lowFenceWindow = "native_supported_state",
            tallFence = "unsupported_native_reroute",
            safehouseExclusion = true,
            persistentAdminZones = true,
        },
    }
end

function Diagnostics.repair()
    local repaired, failed = 0, 0
    for _, actor in ipairs(Registry.list()) do
        local binding = Watchdog.bindings[actor.uid]
        if (actor.lifecycle == "active" or actor.lifecycle == "spawning")
                and not bindingValid(actor, binding) then
            local current = Registry.read(actor.uid)
            if current and current.lifecycle ~= "dead" then
                local dormant = Registry.makeDormant(
                    current.uid, current.revision, current.generation, current.worldPosition)
                if dormant then
                    if binding ~= nil then
                        pcall(Watchdog.adapters.detachShell, actor, binding, "diagnostic_repair")
                        Watchdog.unbind(actor.uid, binding.generation, "diagnostic_repair")
                    end
                    repaired = repaired + 1
                else
                    failed = failed + 1
                end
            end
        elseif (actor.lifecycle == "dormant" or actor.lifecycle == "dead")
                and binding ~= nil then
            pcall(Watchdog.adapters.detachShell, actor, binding, "diagnostic_repair")
            if Watchdog.unbind(actor.uid, binding.generation, "diagnostic_repair") then
                repaired = repaired + 1
            else
                failed = failed + 1
            end
        end
    end
    local orphanKeys = {}
    for uid in pairs(Watchdog.bindings) do
        if Registry.read(uid) == nil then orphanKeys[#orphanKeys + 1] = uid end
    end
    for _, uid in ipairs(orphanKeys) do
        local binding = Watchdog.bindings[uid]
        if binding ~= nil then
            pcall(Watchdog.adapters.detachShell, nil, binding, "diagnostic_repair")
            if Watchdog.unbind(uid, binding.generation, "diagnostic_repair") then
                repaired = repaired + 1
            else
                failed = failed + 1
            end
        end
    end
    Telemetry.emit("diagnostic_repair", { repaired = repaired, failed = failed })
    return failed == 0, repaired, failed, Diagnostics.snapshot()
end

return Diagnostics
