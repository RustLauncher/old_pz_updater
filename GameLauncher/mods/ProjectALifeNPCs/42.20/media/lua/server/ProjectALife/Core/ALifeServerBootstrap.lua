require "ProjectALife/Core/ALifeRuntime"
require "ProjectALife/Core/ALifeLifecycle"
require "ProjectALife/Core/ALifeSettings"
require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Interface/ALifeStatusService"
require "ProjectALife/Admin/ALifeDebugService"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Decisions/ALifeCharacterReset"
require "ProjectALife/Core/ALifeExecutor"

ProjectALife = ProjectALife or {}

if not ProjectALife.ServerBootstrapRegistered and type(Events) == "table" then
    ProjectALife.ServerBootstrapRegistered = true
    local Runtime = ProjectALife.Runtime

    local function add(name, callback)
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
    end

    local function start()
        pcall(ProjectALife.Settings.applySavedPresetUpgrade)
        Runtime.safeStart(ProjectALife.Settings.runtimeOptions())

        local graph, offline = ProjectALife.RoadGraph, ProjectALife.OfflineDirector
        if Runtime.started and offline ~= nil and offline.enabled == true and graph ~= nil
                and graph.roadIndex == nil and type(graph.buildRoadIndex) == "function" then
            pcall(graph.buildRoadIndex)
        end
    end
    add("OnGameStart", start)
    add("OnServerStarted", start)
    add("OnTick", function()
        local ok, reason = pcall(Runtime.tick)
        if not ok then
            Runtime.lastError = "bootstrap_tick:" .. tostring(reason)
            ProjectALife.Telemetry.emit("runtime_fault", {
                subsystem = "bootstrap", error = reason,
            })
        end
    end)

    local function edgeSweep()
        if type(isServer) ~= "function" or not isServer() or not Runtime.started or not Runtime.enabled then return end
        local ok, reason = pcall(Runtime.timeHook, "hook_edge", ProjectALife.Population.edgeSweep)
        if not ok then
            Runtime.lastError = "edge_sweep:" .. tostring(reason)
            ProjectALife.Telemetry.emit("runtime_fault", { subsystem = "edge_sweep", error = reason })
        end
    end
    add("OnTickEvenPaused", edgeSweep)

    add("EveryOneMinute", function()
        Runtime.timeHook("hook_flush", Runtime.flush)

        local settings = ProjectALife.Settings
        if settings ~= nil and type(settings.refreshLive) == "function" then pcall(settings.refreshLive) end
        pcall(ProjectALife.CharacterReset.checkAll)
    end)
    add("OnSave", function()
        Runtime.timeHook("hook_flush", Runtime.save)
    end)
    add("OnZombieDead", function(shell)
        Runtime.timeHook("hook_death", ProjectALife.Lifecycle.onShellDeath, shell)
    end)
    add("OnCreatePlayer", function(first, second)
        pcall(ProjectALife.CharacterReset.check, second or first)
        ProjectALife.Reputation.sync(second or first)
    end)
    add("OnPlayerDeath", function(player)
        pcall(ProjectALife.CharacterReset.onPlayerDied, player)
        ProjectALife.Reputation.onPlayerDied(player)
        if ProjectALife.PersonalRep ~= nil then pcall(ProjectALife.PersonalRep.onPlayerDied, player) end
        if ProjectALife.RepTrack ~= nil then pcall(ProjectALife.RepTrack.onPlayerDied, player) end
    end)
    add("OnCharacterDeath", function(character)
        ProjectALife.Reputation.onPlayerDied(character)
        if ProjectALife.PersonalRep ~= nil then pcall(ProjectALife.PersonalRep.onPlayerDied, character) end
        if ProjectALife.RepTrack ~= nil then pcall(ProjectALife.RepTrack.onPlayerDied, character) end
    end)
    ProjectALife.AIFence.register()
    ProjectALife.StatusService.register()
    ProjectALife.DebugService.register()
    ProjectALife.Executor.register()
end
