require "ProjectALife/Admin/ALifeAdminConsole"

ProjectALife = ProjectALife or {}

local Client = { handlers = {}, metaLocal = { gunfire = true, heli = true, ambience = true, military = true } }
ProjectALife.AdminClientActions = Client

function Client.say(playerNum, text)
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
    if player ~= nil and type(player.Say) == "function" then player:Say(text) end
end

function Client.position(playerNum)
    local state = ProjectALife.AdminConsole.player(playerNum)
    if state.target ~= nil then return state.target end
    return ProjectALife.AdminConsole.playerOrigin(playerNum)
end

function Client.run(spec, playerNum, window)
    local console = ProjectALife.AdminConsole
    local name, argument = string.match(tostring(spec.client), "^([%w_]+):?(.*)$")
    local handler = name ~= nil and Client.handlers[name] or nil
    if handler == nil then
        console.log(playerNum, "No client handler for " .. tostring(spec.client), "error")
        return false
    end
    local ok, result = pcall(handler, playerNum, window, argument, spec)
    if not ok then
        console.metrics.errors = console.metrics.errors + 1
        console.log(playerNum, spec.label .. " failed: " .. tostring(result), "error")
        return false
    end
    return result ~= false
end

function Client.metaFallback(arguments)
    if type(arguments) ~= "table" or arguments.ok == true then return false end
    local kind = arguments.kind
    if Client.metaLocal[kind] ~= true then return false end
    local meta = ProjectALife.MetaClient
    if meta == nil or type(meta.debugPlay) ~= "function" then return false end
    return meta.debugPlay(kind) == true
end

Client.handlers.spawnNow = function(playerNum)
    ProjectALife.AdminConsole.spawn(playerNum)
end

Client.handlers.spawnPreview = function(playerNum)
    ProjectALife.AdminConsole.preview(playerNum)
end

Client.handlers.spawnUndoLast = function(playerNum)
    ProjectALife.AdminConsole.undo(playerNum)
end

Client.handlers.spawnUndoAll = function(playerNum)
    ProjectALife.AdminConsole.undoAll(playerNum)
end

Client.handlers.spawnPreset = function(playerNum, window, argument)
    local console = ProjectALife.AdminConsole
    local state = console.player(playerNum)
    local spec = ProjectALife.SpawnPlan.quick(argument, state.spec, console.planContext(playerNum, state))
    if spec == nil then
        console.log(playerNum, "Unknown preset " .. tostring(argument), "error")
        return false
    end
    state.spec = spec
    state.preview = nil
    console.markDirty(playerNum)
    if window ~= nil and type(window.showTab) == "function" then window:showTab("spawn") end
    if window ~= nil and type(window.refreshSpawn) == "function" then window:refreshSpawn() end
    console.log(playerNum, "Preset loaded: " .. ProjectALife.SpawnPlan.summary(spec, nil))
    return true
end

Client.handlers.openClassic = function(playerNum)
    local console = ProjectALife.AdminConsole
    local state = console.player(playerNum)
    console.openClassic(playerNum, state.target, nil, nil)
end

Client.handlers.openSquadMap = function(playerNum)
    local squadMap = ProjectALife.SquadMap
    if squadMap ~= nil and type(squadMap.show) == "function" then squadMap.show(playerNum) end
end

Client.handlers.toggleArrows = function(playerNum)
    local compass = ProjectALife.EncounterCompass
    if compass ~= nil and type(compass.toggle) == "function" then compass.toggle(playerNum) end
end

Client.handlers.openStatus = function(playerNum)
    if type(ALifeStatusWindow) == "table" and type(ALifeStatusWindow.toggle) == "function" then
        ALifeStatusWindow.toggle(playerNum)
    end
end

Client.handlers.meta = function(playerNum, window, kind)
    ProjectALife.AdminConsole.send(playerNum, "debugMetaEvent", { kind = kind })
    ProjectALife.AdminConsole.log(playerNum, "Meta event " .. tostring(kind) .. " requested.")
end

Client.handlers.silenceAudio = function(playerNum)
    local stopped = 0
    local meta = ProjectALife.MetaClient
    if meta ~= nil and type(meta.reset) == "function" then
        stopped = stopped + #(meta.active or {})
        meta.reset()
    end
    local support = ProjectALife.SupportClient
    if support ~= nil then
        if support.heli ~= nil then stopped = stopped + 1 end
        if type(support.reset) == "function" then support.reset()
        elseif type(support.stopHeli) == "function" then support.stopHeli() end
    end
    local raid = ProjectALife.RaidClient
    if raid ~= nil and type(raid.reset) == "function" then raid.reset() end
    ProjectALife.AdminConsole.log(playerNum, "World audio silenced (" .. tostring(stopped) .. ").")
end

Client.handlers.deleteOutpost = function(playerNum)
    local at = Client.position(playerNum)
    if at == nil then return false end
    ProjectALife.AdminConsole.send(playerNum, "debugOutpostDelete", { x = at.x, y = at.y, reach = 60 })
    ProjectALife.AdminConsole.log(playerNum, "Deleting the nearest outpost...")
end

Client.handlers.purgeRadius = function(playerNum, window, argument)
    local at = Client.position(playerNum)
    local radius = tonumber(argument)
    if at == nil or radius == nil then return false end
    ProjectALife.AdminConsole.send(playerNum, "debugPurgeActors", { radius = radius, x = at.x, y = at.y })
    ProjectALife.AdminConsole.log(playerNum, "Removing NPCs within " .. tostring(radius) .. " tiles...")
end

Client.handlers.visitTrigger = function(playerNum)
    local console = ProjectALife.AdminConsole
    local state = console.player(playerNum)
    if type(state.visitEvent) ~= "string" then
        console.log(playerNum, "Pick a visit type in the WORLD tab first.", "warning")
        return false
    end
    local at = Client.position(playerNum)
    console.send(playerNum, "debugSafehouse", { action = "trigger", event = state.visitEvent,
        at = at ~= nil and { x = at.x, y = at.y, z = at.z } or nil })
    console.log(playerNum, "Triggering " .. state.visitEvent .. "...")
end

Client.handlers.toggleRecorder = function(playerNum)
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil then return false end
    local on = prefs.toggleRecorder()
    local rules = ProjectALife.MenuRules
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum) or nil
    if rules ~= nil and type(rules.apply) == "function" then rules.apply(player) end
    ProjectALife.AdminConsole.log(playerNum, "Flight recorder " .. (on and "on" or "off") .. ".")
end

Client.handlers.cycleVerbosity = function(playerNum)
    local name = ProjectALife.AdminPrefs.cycleVerbosity()
    ProjectALife.AdminConsole.log(playerNum, "Log verbosity: " .. name)
end

Client.handlers.copyReport = function(playerNum, window)
    local text = window ~= nil and type(window.reportText) == "function" and window:reportText() or ""
    if text == "" then
        ProjectALife.AdminConsole.log(playerNum, "This tab has no report to copy.", "warning")
        return false
    end
    if type(Clipboard) ~= "table" or type(Clipboard.setClipboard) ~= "function" then
        ProjectALife.AdminConsole.log(playerNum, "The clipboard is not available.", "error")
        return false
    end
    Clipboard.setClipboard(text)
    ProjectALife.AdminConsole.log(playerNum, "Copied " .. tostring(#text) .. " characters.")
end

Client.handlers.diagnosticsOff = function(playerNum)
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil then return false end
    prefs.setDiagnostics(false)
    local rules = ProjectALife.MenuRules
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum) or nil
    if rules ~= nil and type(rules.apply) == "function" then rules.apply(player) end
    ProjectALife.AdminConsole.closeAll()
end

Client.handlers.copySettings = function(playerNum, window)
    local tab = ProjectALife.AdminSettingsTab
    if tab == nil or type(tab.changedText) ~= "function" then return false end
    local text = tab.changedText(playerNum)
    if type(Clipboard) ~= "table" or type(Clipboard.setClipboard) ~= "function" then
        ProjectALife.AdminConsole.log(playerNum, "The clipboard is not available.", "error")
        return false
    end
    Clipboard.setClipboard(text)
    ProjectALife.AdminConsole.log(playerNum, "Copied the changed settings (" .. tostring(#text) .. " characters).")
end

Client.handlers.refreshSettings = function(playerNum, window)
    local tab = ProjectALife.AdminSettingsTab
    if tab ~= nil and type(tab.refresh) == "function" then tab.refresh(window) end
end

Client.handlers.cleanupOpen = function(playerNum, window)
    local console = ProjectALife.AdminConsole
    local tab = console.tab("cleanup")
    if tab == nil or type(tab.launcher) ~= "function" then
        console.log(playerNum, "The cleanup tool is not installed in this build.", "warning")
        return false
    end
    tab.launcher(playerNum, window)
end

return Client
