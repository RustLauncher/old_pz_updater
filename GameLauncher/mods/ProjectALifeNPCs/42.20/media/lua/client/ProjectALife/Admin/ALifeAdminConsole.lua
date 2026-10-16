require "ISUI/ISModalDialog"
require "ProjectALife/Admin/ALifeAdminActions"
require "ProjectALife/Admin/ALifeSpawnPlan"
require "ProjectALife/Admin/ALifeAdminSettingsData"
require "ProjectALife/Admin/ALifeAdminPrefs"
require "ProjectALife/Interface/ALifeMenuPrefs"
require "ProjectALife/Admin/ALifeDebugSpawner"

ProjectALife = ProjectALife or {}

local Console = {
    windows = {}, players = {}, tabs = {}, replyHandlers = {},
    factions = { rows = {}, pages = {}, got = 0, parts = nil, stamp = 0, pending = false },
    members = {}, confirmations = {}, confirmSequence = 0, scheduled = {},
    snapshot = nil, funnel = nil, repView = nil, ledger = nil,
    metrics = { opens = 0, closes = 0, sent = 0, replies = 0, searches = 0, tabBuilds = 0, errors = 0,
        confirms = 0, scheduled = 0, previews = 0, spawns = 0, undos = 0, runs = 0, denied = 0 },
    snapshotGapMs = 3000, previewDebounceMs = 400, maxScheduled = 8,
}
ProjectALife.AdminConsole = Console

function Console.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Console.player(playerNum)
    playerNum = playerNum or 0
    local state = Console.players[playerNum]
    if state == nil then
        state = { spec = ProjectALife.SpawnPlan.defaultSpec(), history = ProjectALife.SpawnPlan.newHistory(),
            target = nil, markers = {}, preview = nil, previewId = nil, previewKey = nil, previewDueMs = nil,
            message = nil, messageSeverity = "info", log = {} }
        Console.players[playerNum] = state
    end
    return state
end

function Console.log(playerNum, message, severity)
    local state = Console.player(playerNum)
    severity = severity or "info"
    state.message, state.messageSeverity = tostring(message), severity
    state.log[#state.log + 1] = { text = tostring(message), severity = severity }
    while #state.log > 60 do table.remove(state.log, 1) end
    local verbosity = ProjectALife.AdminPrefs.get("verbosity")
    if verbosity == "verbose" or (verbosity == "normal" and severity ~= "info") then
        print("[ALIFE-ADMIN] " .. tostring(message))
    end
    local window = Console.windows[playerNum or 0]
    if window ~= nil and type(window.setStatus) == "function" then window:setStatus(message, severity) end
end

function Console.context(playerNum)
    local prefs = ProjectALife.MenuPrefs
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
    local client = type(isClient) == "function" and isClient() == true
    local host = false
    if client and type(isCoopHost) == "function" then host = isCoopHost() == true end
    return {
        isClient = client,
        isAdmin = prefs ~= nil and type(prefs.serverAdmin) == "function" and prefs.serverAdmin(player) == true,
        isCoopHost = host,
        diagnostics = prefs ~= nil and type(prefs.diagnostics) == "function" and prefs.diagnostics() == true,
    }
end

function Console.access(playerNum)
    return ProjectALife.AdminActions.access(Console.context(playerNum))
end

function Console.allowed(playerNum)
    local prefs = ProjectALife.MenuPrefs
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
    if prefs == nil or type(prefs.allowed) ~= "function" then return false end
    return prefs.allowed(player) == true
end

function Console.send(playerNum, command, args)
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
    if player == nil or type(sendClientCommand) ~= "function" then return false end
    sendClientCommand(player, "ProjectALife", command, args or {})
    Console.metrics.sent = Console.metrics.sent + 1
    if ProjectALife.AdminPrefs.get("verbosity") == "verbose" then
        print("[ALIFE-ADMIN] send " .. tostring(command))
    end
    return true
end

function Console.copyTable(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do result[key] = value end
    return result
end

function Console.squarePosition(square)
    if square == nil then return nil end
    if type(square) == "table" and tonumber(square.x) ~= nil and tonumber(square.y) ~= nil then
        return { x = math.floor(tonumber(square.x)), y = math.floor(tonumber(square.y)),
            z = math.floor(tonumber(square.z) or 0) }
    end
    if type(square.getX) ~= "function" or type(square.getY) ~= "function" then return nil end
    local ok, x, y, z = pcall(function()
        return square:getX(), square:getY(), type(square.getZ) == "function" and square:getZ() or 0
    end)
    if not ok or type(x) ~= "number" then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
end

function Console.playerOrigin(playerNum)
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
    if player == nil then return nil end
    local origin = { x = player:getX(), y = player:getY(), z = player:getZ() }
    if type(player.getForwardDirection) == "function" then
        local forward = player:getForwardDirection()
        if forward ~= nil and type(forward.getX) == "function" and type(forward.getY) == "function" then
            origin.fx, origin.fy = forward:getX(), forward:getY()
        end
    end
    return origin
end

function Console.setSpot(playerNum, square)
    local position = Console.squarePosition(square)
    local state = Console.player(playerNum)
    state.target = position
    if position ~= nil then
        state.spec.where = "target"
        Console.log(playerNum, "Spawn target set to " .. tostring(position.x) .. "," .. tostring(position.y) .. "," .. tostring(position.z))
    end
    local window = Console.windows[playerNum or 0]
    if window ~= nil and type(window.refreshSpawn) == "function" then window:refreshSpawn() end
    return position ~= nil
end

function Console.visitEvents()
    local client = ProjectALife.SafehouseClient
    local rows = {}
    if client == nil or type(client.events) ~= "table" then return rows end
    for _, entry in ipairs(client.events) do
        rows[#rows + 1] = { id = entry[1], label = entry[2], group = client.groupOf and client.groupOf[entry[1]] or "Other" }
    end
    return rows
end

function Console.visitorIds()
    local ids = {}
    for _, row in ipairs(Console.visitEvents()) do
        if row.group == "Visitors" then ids[#ids + 1] = row.id end
    end
    return ids
end

function Console.factionIds()
    local known = {}
    for _, row in ipairs(Console.factions.rows) do known[row.id] = true end
    return known
end

function Console.planContext(playerNum, state)
    state = state or Console.player(playerNum)
    return {
        playerNum = playerNum or 0, now = Console.nowMs(), origin = Console.playerOrigin(playerNum),
        target = state.target, markers = state.markers, visitEvents = Console.visitorIds(),
        factionIds = Console.factionIds(),
    }
end

function Console.specKey(spec)
    return ProjectALife.SpawnPlan.encodeSpec(ProjectALife.SpawnPlan.normalize(spec))
end

function Console.markDirty(playerNum)
    Console.player(playerNum).previewDueMs = Console.nowMs() + Console.previewDebounceMs
end

function Console.preview(playerNum)
    local state = Console.player(playerNum)
    state.previewDueMs = nil
    local plan = ProjectALife.SpawnPlan
    local built = plan.previewArguments(state.spec, Console.planContext(playerNum, state))
    if not built.ok then
        state.preview = { ok = false, reason = built.reason, text = built.text }
        state.previewKey = Console.specKey(state.spec)
        return built
    end
    plan.metrics.previews = plan.metrics.previews + 1
    Console.metrics.previews = Console.metrics.previews + 1
    state.previewId = built.args.requestId
    state.previewPending = Console.specKey(state.spec)
    Console.send(playerNum, built.command, built.args)
    return built
end

function Console.rosterFor(state)
    local preview = state.preview
    if type(preview) ~= "table" or preview.ok ~= true or state.previewKey ~= Console.specKey(state.spec) then return nil end
    local ids = {}
    for _, row in ipairs(type(preview.roster) == "table" and preview.roster or {}) do ids[#ids + 1] = row.id end
    if #ids == 0 then return nil end
    return ids, preview.seed
end

function Console.spawn(playerNum, spec)
    local plan = ProjectALife.SpawnPlan
    local state = Console.player(playerNum)
    spec = spec or state.spec
    local context = Console.planContext(playerNum, state)
    local ids, seed = Console.rosterFor(state)
    if spec.kind == "squad" then
        context.rosterIds = ids
        if spec.seed == nil and seed ~= nil and ids ~= nil then spec = plan.copySpec(spec); spec.seed = seed end
    end
    local built = plan.build(spec, context)
    if not built.ok then
        Console.log(playerNum, "Cannot spawn: " .. tostring(built.text), "error")
        return built
    end
    local entry = plan.historyAdd(state.history, { requestId = built.requestId, kind = built.kind,
        summary = built.summary, atMs = Console.nowMs(), undoable = built.undoable })
    built.args.summary = built.summary
    Console.metrics.spawns = Console.metrics.spawns + 1
    if built.clientDelayMs > 0 then
        local queued = Console.schedule(playerNum, built)
        if not queued then
            entry.state, entry.reason, entry.text = "refused", "spawn_history_full", plan.refusalText("spawn_history_full")
            Console.log(playerNum, "Too many delayed spawns are waiting.", "error")
            return { ok = false, reason = "spawn_history_full" }
        end
        entry.state = "scheduled"
        Console.log(playerNum, "Scheduled in " .. tostring(math.floor(built.clientDelayMs / 1000)) .. "s: " .. built.summary)
    else
        if not Console.send(playerNum, built.command, built.args) then
            entry.state, entry.reason, entry.text = "refused", "send_failed", "The request could not be sent."
            Console.log(playerNum, "The request could not be sent.", "error")
            return { ok = false, reason = "send_failed" }
        end
        Console.log(playerNum, "Spawning: " .. built.summary)
    end
    local window = Console.windows[playerNum or 0]
    if window ~= nil and type(window.refreshSpawn) == "function" then window:refreshSpawn() end
    return built
end

function Console.schedule(playerNum, built)
    if #Console.scheduled >= Console.maxScheduled then return false end
    Console.scheduled[#Console.scheduled + 1] = { playerNum = playerNum, dueMs = Console.nowMs() + built.clientDelayMs,
        command = built.command, args = built.args, requestId = built.requestId }
    Console.metrics.scheduled = Console.metrics.scheduled + 1
    if not Console.ticking and type(Events) == "table" and Events.OnTick ~= nil then
        Events.OnTick.Add(Console.tick)
        Console.ticking = true
    end
    return true
end

function Console.tick()
    local now = Console.nowMs()
    for index = #Console.scheduled, 1, -1 do
        local job = Console.scheduled[index]
        if now >= job.dueMs then
            table.remove(Console.scheduled, index)
            local entry = Console.player(job.playerNum).history.byRequest[job.requestId]
            if entry ~= nil and entry.state == "scheduled" then entry.state = "sent" end
            Console.send(job.playerNum, job.command, job.args)
        end
    end
    if #Console.scheduled == 0 and Console.ticking then
        Console.ticking = false
        if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Remove) == "function" then
            Events.OnTick.Remove(Console.tick)
        end
    end
end

function Console.cancelScheduled(playerNum)
    local removed = 0
    for index = #Console.scheduled, 1, -1 do
        local job = Console.scheduled[index]
        if job.playerNum == playerNum then
            table.remove(Console.scheduled, index)
            local entry = Console.player(playerNum).history.byRequest[job.requestId]
            if entry ~= nil then entry.state, entry.undone = "undone", true end
            removed = removed + 1
        end
    end
    return removed
end

function Console.undo(playerNum, entry)
    local plan = ProjectALife.SpawnPlan
    local state = Console.player(playerNum)
    entry = entry or plan.historyLast(state.history, true)
    if entry == nil then
        Console.log(playerNum, "Nothing to undo.", "warning")
        return false, "undo_nothing"
    end
    if entry.state == "scheduled" then
        Console.cancelScheduled(playerNum)
        Console.log(playerNum, "Cancelled the delayed spawn.")
        return true
    end
    Console.metrics.undos = Console.metrics.undos + 1
    Console.send(playerNum, "adminSpawnUndo", { requestId = entry.requestId, groupId = entry.groupId,
        siteId = entry.siteId, sceneKey = entry.sceneKey, actorUids = entry.uids })
    Console.log(playerNum, "Removing: " .. tostring(entry.summary))
    return true
end

function Console.undoAll(playerNum)
    Console.cancelScheduled(playerNum)
    Console.metrics.undos = Console.metrics.undos + 1
    Console.send(playerNum, "adminSpawnUndo", { all = true })
    Console.log(playerNum, "Removing everything you spawned from this console...")
    return true
end

function Console.requestFactions(playerNum, force)
    local factions = Console.factions
    if factions.pending and not force then return false end
    if #factions.rows > 0 and not force then return false end
    factions.pending, factions.got, factions.parts, factions.pages = true, 0, nil, {}
    return Console.send(playerNum, "adminFactionIndex", {})
end

function Console.requestMembers(playerNum, factionId)
    if type(factionId) ~= "string" or factionId == "" then return false end
    local entry = Console.members[factionId]
    if entry ~= nil and (entry.complete or entry.pending) then return false end
    Console.members[factionId] = { pending = true, pages = {}, got = 0, rows = {}, complete = false }
    return Console.send(playerNum, "adminFactionMembers", { factionId = factionId })
end

function Console.requestSnapshot(playerNum, sections, force)
    local now = Console.nowMs()
    if not force and Console.snapshotAt ~= nil and now - Console.snapshotAt < Console.snapshotGapMs
            and Console.snapshotSections == sections then return false end
    Console.snapshotAt, Console.snapshotSections = now, sections
    return Console.send(playerNum, "adminSnapshot", { sections = sections })
end

function Console.catalog()
    local spawner = ALifeDebugSpawnerWindow
    if type(spawner) == "table" and type(spawner.catalog) == "table" then return spawner.catalog end
    return nil
end

function Console.requestCatalog(playerNum)
    local spawner = ALifeDebugSpawnerWindow
    if type(spawner) == "table" and type(spawner.requestCatalog) == "function" then
        return spawner.requestCatalog(playerNum or 0, nil, false)
    end
    return nil
end

function Console.addTab(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or string.find(spec.id, "^[%w_]+$") == nil
            or #spec.id > 24 or type(spec.title) ~= "string" or spec.title == "" or #spec.title > 18 then
        Console.metrics.errors = Console.metrics.errors + 1
        return false, "tab_invalid"
    end
    for _, key in ipairs({ "build", "onShow", "onHide", "onReply", "launcher" }) do
        if spec[key] ~= nil and type(spec[key]) ~= "function" then
            Console.metrics.errors = Console.metrics.errors + 1
            return false, "tab_callback_invalid:" .. key
        end
    end
    local tab = {
        id = spec.id, title = spec.title, order = tonumber(spec.order) or 100, tip = tostring(spec.tip or ""),
        build = spec.build, onShow = spec.onShow, onHide = spec.onHide, onReply = spec.onReply,
        launcher = spec.launcher, controls = type(spec.controls) == "table" and spec.controls or {},
        description = type(spec.description) == "string" and spec.description or nil,
        builtin = spec.builtin == true,
    }
    local replaced = false
    for index, existing in ipairs(Console.tabs) do
        if existing.id == tab.id then Console.tabs[index] = tab; replaced = true end
    end
    if not replaced then Console.tabs[#Console.tabs + 1] = tab end
    table.sort(Console.tabs, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        return left.id < right.id
    end)
    for _, window in pairs(Console.windows) do
        if type(window.tabsChanged) == "function" then window:tabsChanged(tab.id) end
    end
    return true
end

function Console.tab(id)
    for _, tab in ipairs(Console.tabs) do
        if tab.id == id then return tab end
    end
    return nil
end

function Console.onReply(command, handler)
    if type(command) ~= "string" or type(handler) ~= "function" then return false end
    Console.replyHandlers[command] = Console.replyHandlers[command] or {}
    local list = Console.replyHandlers[command]
    list[#list + 1] = handler
    return true
end

function Console.ingestPaged(store, arguments, key)
    if arguments.ok ~= true then
        store.pending = false
        return false
    end
    local parts = math.floor(tonumber(arguments.parts) or 1)
    local part = math.floor(tonumber(arguments.part) or 1)
    if part < 1 or part > parts or parts > 64 then return false end
    if store.parts ~= parts then store.parts, store.pages, store.got = parts, {}, 0 end
    if store.pages[part] == nil then
        store.pages[part] = type(arguments[key]) == "table" and arguments[key] or {}
        store.got = store.got + 1
    end
    if store.got < parts then return false end
    local rows = {}
    for index = 1, parts do
        for _, row in ipairs(store.pages[index] or {}) do rows[#rows + 1] = row end
    end
    store.rows, store.pages, store.pending, store.complete = rows, {}, false, true
    store.stamp = (store.stamp or 0) + 1
    return true
end

function Console.tap(command, arguments)
    Console.metrics.replies = Console.metrics.replies + 1
    local plan = ProjectALife.SpawnPlan
    if command == "adminSpawnResult" or command == "adminSpawnBatchResult" or command == "adminSpawnUndoResult" then
        for playerNum, state in pairs(Console.players) do
            local entry = plan.ingest(state.history, command, arguments)
            if entry ~= nil then
                local text = plan.historyLine(entry)
                local severity = (entry.state == "refused" or entry.state == "failed") and "error"
                    or (entry.state == "partial") and "warning" or "info"
                if command == "adminSpawnUndoResult" and arguments.ok ~= true then
                    text = "Undo: " .. tostring(arguments.text or plan.refusalText(arguments.reason))
                    severity = "error"
                end
                Console.log(playerNum, text, severity)
                if type(arguments.roster) == "table" and command == "adminSpawnResult" then entry.roster = arguments.roster end
            elseif command == "adminSpawnUndoResult" and arguments.requestId == "*" then
                for _, other in ipairs(state.history.entries) do
                    if plan.undoable(other) then other.undone, other.state = true, "undone" end
                end
                Console.log(playerNum, "Undo all: removed " .. tostring(arguments.removed or 0) .. " NPC(s).",
                    arguments.ok == true and "info" or "error")
            end
        end
    elseif command == "adminSpawnPreviewResult" then
        for playerNum, state in pairs(Console.players) do
            if state.previewId ~= nil and tostring(arguments.requestId) == tostring(state.previewId) then
                state.preview = arguments
                state.previewKey = state.previewPending
                state.previewId = nil
            end
        end
    elseif command == "adminFactionIndexResult" then
        if Console.ingestPaged(Console.factions, arguments, "factions") then
            table.sort(Console.factions.rows, function(left, right)
                return string.lower(tostring(left.name)) < string.lower(tostring(right.name))
            end)
        end
    elseif command == "adminFactionMembersResult" then
        local entry = Console.members[tostring(arguments.factionId)]
        if entry ~= nil then Console.ingestPaged(entry, arguments, "members") end
    elseif command == "adminSnapshotResult" then
        if arguments.ok == true then Console.snapshot = arguments end
    elseif command == "adminFunnelResult" then
        if arguments.ok == true then Console.funnel = arguments end
    elseif command == "adminRepViewResult" then
        if arguments.ok == true then Console.repView = arguments end
    elseif command == "adminSpawnLedgerResult" then
        Console.ledger = arguments
    elseif command == "debugCatalogResult" then
        Console.catalogSeen = (Console.catalogSeen or 0) + 1
    elseif command == "debugMetaEventResult" then
        local client = ProjectALife.AdminClientActions
        if client ~= nil then client.metaFallback(arguments) end
    end
    for _, handler in ipairs(Console.replyHandlers[command] or {}) do
        local ok, failure = pcall(handler, arguments, command)
        if not ok then
            Console.metrics.errors = Console.metrics.errors + 1
            print("[ALIFE-ADMIN] reply handler failed for " .. tostring(command) .. ": " .. tostring(failure))
        end
    end
    for _, window in pairs(Console.windows) do
        if type(window.onReply) == "function" then
            local ok, failure = pcall(window.onReply, window, command, arguments)
            if not ok then
                Console.metrics.errors = Console.metrics.errors + 1
                print("[ALIFE-ADMIN] window reply failed for " .. tostring(command) .. ": " .. tostring(failure))
            end
        end
    end
end

function Console.search(query)
    Console.metrics.searches = Console.metrics.searches + 1
    local actions = ProjectALife.AdminActions
    local rows = {}
    for _, spec in ipairs(actions.search(query, actions.maxResults)) do
        rows[#rows + 1] = { kind = "action", id = spec.id, label = spec.label, tab = spec.tab,
            tip = spec.tip, risk = spec.risk }
    end
    for _, tab in ipairs(Console.tabs) do
        for _, control in ipairs(tab.controls) do
            local text = string.lower(tostring(control.label) .. " " .. tostring(control.tip) .. " " .. tostring(control.keywords))
            local match = true
            for _, word in ipairs(actions.words(query)) do
                if string.find(text, word, 1, true) == nil then match = false end
            end
            if match and #rows < actions.maxResults * 2 then
                rows[#rows + 1] = { kind = "control", id = control.id, label = control.label, tab = tab.id,
                    tip = control.tip, risk = control.risk or "safe", run = control.run }
            end
        end
    end
    local data = ProjectALife.AdminSettingsData
    if data ~= nil and #actions.words(query) > 0 then
        local hits = 0
        for _, row in ipairs(data.rows) do
            if actions.match({ id = row.key, label = row.key, tip = "", keywords = row.tr, tab = "settings", risk = "safe" }, query) then
                hits = hits + 1
            end
        end
        if hits > 0 then
            rows[#rows + 1] = { kind = "settings", id = "settings", label = tostring(hits) .. " sandbox option(s) match: open SETTINGS",
                tab = "settings", tip = "Opens the read-only settings browser with this search.", risk = "safe" }
        end
    end
    local factionHits = 0
    local words = actions.words(query)
    if #words > 0 then
        for _, row in ipairs(Console.factions.rows) do
            local text = string.lower(tostring(row.name) .. " " .. tostring(row.id))
            local match = true
            for _, word in ipairs(words) do
                if string.find(text, word, 1, true) == nil then match = false end
            end
            if match then factionHits = factionHits + 1 end
        end
    end
    if factionHits > 0 then
        rows[#rows + 1] = { kind = "factions", id = "factions", label = tostring(factionHits) .. " faction(s) match: open SPAWN",
            tab = "spawn", tip = "Opens the spawn tab with this search in the faction browser.", risk = "safe" }
    end
    return rows
end

function Console.onConfirm(target, button, token)
    local pending = Console.confirmations[token]
    Console.confirmations[token] = nil
    if pending == nil or button == nil or button.internal ~= "YES" then return end
    pending()
end

function Console.confirm(playerNum, text, onYes)
    Console.metrics.confirms = Console.metrics.confirms + 1
    Console.confirmSequence = Console.confirmSequence + 1
    local token = Console.confirmSequence
    if type(ISModalDialog) ~= "table" or type(getCore) ~= "function" then
        Console.log(playerNum, "No confirmation dialog is available; the action was not run.", "error")
        return false
    end
    Console.confirmations[token] = onYes
    local modal = ISModalDialog:new(0, 0, 360, 140, tostring(text), true, Console, Console.onConfirm, playerNum or 0, token)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    return true
end

function Console.execute(spec, playerNum, window)
    Console.metrics.runs = Console.metrics.runs + 1
    if spec.scope == "server" then
        local args = Console.copyTable(spec.args)
        if spec.command == "debugSafehouse" or spec.command == "debugPickedOver" then
            local state = Console.player(playerNum)
            local at = state.target or Console.playerOrigin(playerNum)
            if spec.command == "debugSafehouse" and at ~= nil then args.at = { x = at.x, y = at.y, z = at.z } end
        end
        if not Console.send(playerNum, spec.command, args) then
            Console.log(playerNum, "The request could not be sent.", "error")
            return false
        end
        Console.log(playerNum, spec.label .. " sent.")
        return true
    end
    local handlers = ProjectALife.AdminClientActions
    if handlers == nil or type(handlers.run) ~= "function" then
        Console.log(playerNum, "Client actions are not loaded.", "error")
        return false
    end
    return handlers.run(spec, playerNum, window)
end

function Console.run(actionId, playerNum, window)
    local spec = ProjectALife.AdminActions.get(actionId)
    if spec == nil then
        Console.log(playerNum, "Unknown action " .. tostring(actionId), "error")
        return false
    end
    local context = Console.context(playerNum)
    local allowed, why = ProjectALife.AdminActions.allowed(spec, context)
    if allowed and not Console.allowed(playerNum) then allowed, why = false, "diagnostics_disabled" end
    if not allowed then
        Console.metrics.denied = Console.metrics.denied + 1
        Console.log(playerNum, spec.label .. ": " .. ProjectALife.SpawnPlan.refusalText(why), "error")
        return false
    end
    if type(spec.confirm) == "string" and spec.confirm ~= "" then
        return Console.confirm(playerNum, spec.confirm, function() Console.execute(spec, playerNum, window) end)
    end
    return Console.execute(spec, playerNum, window)
end

function Console.pin(actionId, window)
    local changed, reason = ProjectALife.AdminPrefs.toggleFavourite(actionId)
    local playerNum = window ~= nil and window.playerNum or 0
    if not changed and reason == "toolbar_full" then
        Console.log(playerNum, "The toolbar holds " .. tostring(ProjectALife.AdminActions.maxFavourites)
            .. " pins. Unpin one first.", "warning")
    end
    for _, open in pairs(Console.windows) do
        if type(open.refreshToolbar) == "function" then open:refreshToolbar() end
    end
    return changed
end

function Console.favourites()
    return ProjectALife.AdminPrefs.favouriteList()
end

function Console.current(playerNum)
    return Console.windows[playerNum or 0]
end

function Console.open(playerNum, options)
    playerNum = playerNum or 0
    options = options or {}
    if not Console.allowed(playerNum) then return nil, "not_allowed" end
    local window = Console.windows[playerNum]
    if window == nil then
        local factory = ProjectALife.AdminWindow
        if factory == nil or type(factory.create) ~= "function" then return nil, "window_unavailable" end
        local ok, created = pcall(factory.create, playerNum)
        if not ok or created == nil then
            Console.metrics.errors = Console.metrics.errors + 1
            print("[ALIFE-ADMIN] the console window failed to open: " .. tostring(created))
            return nil, "window_failed"
        end
        window = created
        Console.windows[playerNum] = window
        Console.metrics.opens = Console.metrics.opens + 1
    else
        window:setVisible(true)
        if type(window.bringToTop) == "function" then window:bringToTop() end
    end
    if not Console.spNoticed and Console.access(playerNum).role == "SP" then
        Console.spNoticed = true
        Console.log(playerNum, "Single player: every action here changes your own save. Destructive actions ask first. Back up the save before big tests.", "warning")
    end
    if options.square ~= nil then Console.setSpot(playerNum, options.square) end
    if options.tab ~= nil and type(window.showTab) == "function" then window:showTab(options.tab) end
    if options.encounter ~= nil or options.faction ~= nil then Console.preselect(playerNum, options.encounter, options.faction) end
    if type(window.afterOpen) == "function" then window:afterOpen() end
    return window
end

function Console.preselect(playerNum, encounterId, factionId)
    local state = Console.player(playerNum)
    local spec = state.spec
    local plan = ProjectALife.SpawnPlan
    local presetId = type(encounterId) == "string" and string.match(encounterId, "^outpost:(.+)$") or nil
    if presetId ~= nil then
        spec.kind, spec.presetId = "outpost", presetId
    elseif type(encounterId) == "string" and encounterId ~= "" then
        spec.kind, spec.encounterId = "encounter", encounterId
        if encounterId == "fullscale_raid" then spec.kind = "raid" end
    elseif factionId ~= nil then
        spec.kind = "squad"
    end
    if type(factionId) == "string" and factionId ~= "" then spec.factionId = factionId end
    spec.where = state.target ~= nil and "target" or spec.where
    Console.markDirty(playerNum)
    local window = Console.windows[playerNum or 0]
    if window ~= nil then
        if type(window.showTab) == "function" then window:showTab("spawn") end
        if type(window.refreshSpawn) == "function" then window:refreshSpawn() end
    end
    return spec
end

function Console.openFromClassic(playerNum, square, encounterId, factionId)
    if ProjectALife.AdminPrefs.get("classic") == true then return nil end
    local window = Console.open(playerNum, { square = square, encounter = encounterId, faction = factionId, tab = "spawn" })
    return window
end

function Console.toggle(playerNum)
    playerNum = playerNum or 0
    local window = Console.windows[playerNum]
    if window ~= nil then
        Console.close(playerNum)
        return nil
    end
    return Console.open(playerNum, {})
end

function Console.close(playerNum)
    playerNum = playerNum or 0
    local window = Console.windows[playerNum]
    if window == nil then return false end
    Console.windows[playerNum] = nil
    Console.metrics.closes = Console.metrics.closes + 1
    if type(window.shutdown) == "function" then window:shutdown() end
    return true
end

function Console.closeAll()
    local closed = 0
    for playerNum in pairs(Console.copyTable(Console.windows)) do
        if Console.close(playerNum) then closed = closed + 1 end
    end
    return closed
end

function Console.openClassic(playerNum, square, encounterId, factionId)
    local spawner = ALifeDebugSpawnerWindow
    if type(spawner) ~= "table" or type(spawner.openClassic) ~= "function" then return nil end
    return spawner.openClassic(playerNum or 0, square, encounterId, factionId)
end

if type(ALifeDebugSpawnerWindow) == "table" and type(ALifeDebugSpawnerWindow.clientQANames) == "table" then
    table.insert(ALifeDebugSpawnerWindow.clientQANames, "AdminConsole")
    table.insert(ALifeDebugSpawnerWindow.clientQANames, "SpawnPlan")
end

return Console
