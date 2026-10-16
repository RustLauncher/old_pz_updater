ProjectALife = ProjectALife or {}

local Actions = {
    list = {},
    index = {},
    maxFavourites = 8,
    maxResults = 40,
    metrics = { registered = 0, rejected = 0, searches = 0 },
}
ProjectALife.AdminActions = Actions

Actions.TABS = {
    { id = "spawn", title = "SPAWN", order = 10,
      tip = "Pick what to spawn, how many, where and when. Preview the result and undo a batch." },
    { id = "population", title = "POPULATION", order = 20,
      tip = "Live census of NPCs, squads, hydrate and hold counters, funnel stage and the nearest NPCs." },
    { id = "world", title = "WORLD", order = 30,
      tip = "Force raids, support calls, meta events, base visits and funnel stage previews." },
    { id = "reputation", title = "REPUTATION", order = 40,
      tip = "View and adjust your personal and per-faction reputation." },
    { id = "diagnostics", title = "DIAGNOSTICS", order = 50,
      tip = "Blackbox and QA dumps, flight recorder, module status, performance and the last errors." },
    { id = "settings", title = "SETTINGS", order = 60,
      tip = "Read-only browser of every A-Life sandbox option with its default and preset origin." },
    { id = "cleanup", title = "CLEANUP", order = 70,
      tip = "Scan and clean A-Life leftovers. Provided by the cleanup tool when it is installed." },
}

Actions.RISK = {
    safe = "Safe. Reads state or changes only your own screen.",
    caution = "Changes the live world. It can be undone or wears off by itself.",
    danger = "Destructive or hard to undo. Asks you to confirm first.",
}

Actions.RISK_ORDER = { safe = 1, caution = 2, danger = 3 }

Actions.SCOPES = {
    server = "Runs on the server. Needs a server admin in multiplayer; always allowed in single player.",
    client = "Runs on this computer only. Needs the Diagnostics option.",
}

local function ok(value) return type(value) == "string" and value ~= "" end

function Actions.tab(id)
    for _, row in ipairs(Actions.TABS) do
        if row.id == id then return row end
    end
    return nil
end

function Actions.register(spec)
    if type(spec) ~= "table" or not ok(spec.id) or not ok(spec.label) or not ok(spec.tip)
            or Actions.tab(spec.tab) == nil or Actions.RISK[spec.risk] == nil
            or Actions.SCOPES[spec.scope] == nil then
        Actions.metrics.rejected = Actions.metrics.rejected + 1
        return false, "action_invalid"
    end
    if spec.scope == "server" and not ok(spec.command) then
        Actions.metrics.rejected = Actions.metrics.rejected + 1
        return false, "action_command_missing"
    end
    if spec.scope == "client" and not ok(spec.client) then
        Actions.metrics.rejected = Actions.metrics.rejected + 1
        return false, "action_handler_missing"
    end
    local existing = Actions.index[spec.id]
    if existing ~= nil then
        for position, row in ipairs(Actions.list) do
            if row == existing then Actions.list[position] = spec end
        end
    else
        Actions.list[#Actions.list + 1] = spec
        Actions.metrics.registered = Actions.metrics.registered + 1
    end
    Actions.index[spec.id] = spec
    return true
end

function Actions.get(id)
    return Actions.index[id]
end

function Actions.forTab(tabId)
    local rows = {}
    for _, spec in ipairs(Actions.list) do
        if spec.tab == tabId then rows[#rows + 1] = spec end
    end
    return rows
end

function Actions.words(query)
    local words = {}
    for word in string.gmatch(string.lower(tostring(query or "")), "[^%s]+") do
        words[#words + 1] = word
    end
    return words
end

function Actions.haystack(spec)
    local tab = Actions.tab(spec.tab)
    return string.lower(table.concat({ spec.id, spec.label, spec.tip, spec.keywords or "",
        tab and tab.title or "", spec.risk }, " "))
end

function Actions.match(spec, query)
    local words = Actions.words(query)
    if #words == 0 then return true end
    local text = Actions.haystack(spec)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) == nil then return false end
    end
    return true
end

function Actions.search(query, limit)
    Actions.metrics.searches = Actions.metrics.searches + 1
    local found = {}
    local cap = math.floor(tonumber(limit) or Actions.maxResults)
    for _, spec in ipairs(Actions.list) do
        if Actions.match(spec, query) then
            found[#found + 1] = spec
            if #found >= cap then break end
        end
    end
    return found
end

function Actions.access(context)
    context = type(context) == "table" and context or {}
    local client = context.isClient == true
    if not client then
        return { role = "SP", ok = true, text = "SP" }
    end
    if context.isAdmin == true then
        if context.isCoopHost == true then return { role = "HOST", ok = true, text = "HOST" } end
        return { role = "ADMIN", ok = true, text = "ADMIN" }
    end
    return { role = "NONE", ok = false, text = "NO ACCESS" }
end

function Actions.allowed(spec, context)
    local access = Actions.access(context)
    if not access.ok then return false, "admin_required" end
    if type(spec) == "table" and spec.scope == "client" and context ~= nil
            and context.diagnostics ~= true then
        return false, "diagnostics_disabled"
    end
    return true
end

function Actions.tooltip(spec, context)
    if type(spec) ~= "table" then return "" end
    local lines = { spec.label, spec.tip }
    lines[#lines + 1] = "Risk: " .. tostring(spec.riskNote or Actions.RISK[spec.risk])
    lines[#lines + 1] = tostring(Actions.SCOPES[spec.scope])
    if ok(spec.confirm) then lines[#lines + 1] = "Asks for confirmation." end
    if context ~= nil then
        local access = Actions.access(context)
        lines[#lines + 1] = "You are: " .. access.text
    end
    return table.concat(lines, "\n")
end

function Actions.normalizeFavourites(list)
    local result, seen = {}, {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if type(id) == "string" and Actions.index[id] ~= nil and not seen[id] then
            seen[id] = true
            result[#result + 1] = id
            if #result >= Actions.maxFavourites then break end
        end
    end
    return result
end

function Actions.isFavourite(list, id)
    for _, value in ipairs(type(list) == "table" and list or {}) do
        if value == id then return true end
    end
    return false
end

function Actions.toggleFavourite(list, id)
    if Actions.index[id] == nil then return list, false, "unknown_action" end
    local result, removed = {}, false
    for _, value in ipairs(type(list) == "table" and list or {}) do
        if value == id then removed = true else result[#result + 1] = value end
    end
    if removed then return result, true, "unpinned" end
    if #result >= Actions.maxFavourites then return result, false, "toolbar_full" end
    result[#result + 1] = id
    return result, true, "pinned"
end

function Actions.encodeFavourites(list)
    local lines = {}
    for _, id in ipairs(Actions.normalizeFavourites(list)) do lines[#lines + 1] = "fav = " .. id end
    return table.concat(lines, "\n")
end

function Actions.decodeFavourites(text)
    local ids = {}
    for line in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
        local id = string.match(line, "^%s*fav%s*=%s*([%w_%.%-:]+)%s*$")
        if id ~= nil then ids[#ids + 1] = id end
    end
    return Actions.normalizeFavourites(ids)
end

local function add(tab, id, label, tip, risk, scope, extra)
    local spec = { id = id, tab = tab, label = label, tip = tip, risk = risk, scope = scope }
    for key, value in pairs(extra or {}) do spec[key] = value end
    local registered, reason = Actions.register(spec)
    if not registered then error("admin action " .. tostring(id) .. ": " .. tostring(reason)) end
    return spec
end
Actions.add = add

add("spawn", "spawn.go", "Spawn now", "Sends the request built in the SPAWN tab to the server with the options shown there.",
    "caution", "client", { client = "spawnNow", keywords = "create npc squad deploy go",
        riskNote = "Adds NPCs or objects to the live world. Use Undo last batch to remove exactly what it made." })
add("spawn", "spawn.preview", "Preview spawn", "Asks the server which members would spawn and whether the square is free, without creating anything.",
    "safe", "client", { client = "spawnPreview", keywords = "check roster square refusal" })
add("spawn", "spawn.undoLast", "Undo last batch", "Removes exactly the NPCs, scene objects or outpost the most recent spawn batch created.",
    "caution", "client", { client = "spawnUndoLast", keywords = "despawn remove last batch",
        riskNote = "Removes only that batch. NPCs that were killed or already looted are gone either way." })
add("spawn", "spawn.undoAll", "Despawn all spawned by me", "Removes every batch you spawned in this session that is still alive.",
    "danger", "client", { client = "spawnUndoAll", confirm = "Remove every NPC and object you spawned from this console?",
        keywords = "despawn undo all mine clean" })
add("spawn", "spawn.preset.test_squad", "Preset: test squad of 3", "Fills the form with 3 hostile military 30 tiles ahead of you, roaming.",
    "safe", "client", { client = "spawnPreset:test_squad", keywords = "quick preset hostile military ahead" })
add("spawn", "spawn.preset.medic", "Preset: friendly medic here", "Fills the form with one friendly medic at your position.",
    "safe", "client", { client = "spawnPreset:medic", keywords = "quick preset friendly medic here" })
add("spawn", "spawn.preset.raid", "Preset: raid now", "Fills the form with a forced full-scale raid on you.",
    "safe", "client", { client = "spawnPreset:raid", keywords = "quick preset raid attack" })
add("spawn", "spawn.preset.visitor", "Preset: visitor now", "Fills the form with a base visitor at your safehouse.",
    "safe", "client", { client = "spawnPreset:visitor", keywords = "quick preset visitor knock door" })
add("spawn", "spawn.classic", "Classic spawn panel", "Opens the old debug spawner window with all its fields. Kept until the new panel is proven in game.",
    "safe", "client", { client = "openClassic", keywords = "old legacy debug panel" })

add("population", "pop.refresh", "Refresh census", "Asks the server for the current NPC census, squads, counters and funnel stage.",
    "safe", "server", { command = "adminSnapshot", args = { sections = "population" }, keywords = "census squads hydrate hold" })
add("population", "pop.report", "NPC report", "Lists the 64 NPCs nearest to you with state, behaviour, endurance and position.",
    "safe", "server", { command = "debugActors", args = {}, keywords = "nearest actors inspector endurance" })
add("population", "pop.map", "Squads on the map", "Opens the squad map overlay on the world map.",
    "safe", "client", { client = "openSquadMap", keywords = "markers world map squads" })
add("population", "pop.arrows", "Encounter arrows", "Toggles the on-screen arrows that point to live encounters.",
    "safe", "client", { client = "toggleArrows", keywords = "compass encounters markers" })
add("population", "pop.status", "Runtime status", "Opens the world status window with health, actor and shell counts.",
    "safe", "client", { client = "openStatus", keywords = "health runtime window" })
add("population", "pop.census", "Town census dump", "Writes the per-town survivor census to the server log.",
    "safe", "server", { command = "debugTownCensus", args = {}, keywords = "towns log dump" })
add("population", "pop.nospawn", "No-spawn area here", "Protects a 20 tile circle around you: natural spawns and admin spawns are refused inside it until cleared.",
    "caution", "server", { command = "debugAddNoSpawnZone", args = { radius = 20 }, keywords = "protect zone natural spawns",
        riskNote = "The circle is saved with the world and only Clear no-spawn areas removes it." })
add("population", "pop.nospawn.clear", "Clear no-spawn areas", "Removes every protected no-spawn circle.",
    "caution", "server", { command = "debugClearNoSpawnZones", args = {}, confirm = "Clear every protected no-spawn area?",
        keywords = "protect zone remove" })
add("population", "pop.remove15", "Remove NPCs within 15 tiles", "Despawns every A-Life NPC within 15 tiles of you.",
    "danger", "client", { client = "purgeRadius:15", confirm = "Remove every A-Life NPC within 15 tiles of you?",
        keywords = "purge despawn kill clean" })
add("population", "pop.remove40", "Remove NPCs within 40 tiles", "Despawns every A-Life NPC within 40 tiles of you.",
    "danger", "client", { client = "purgeRadius:40", confirm = "Remove every A-Life NPC within 40 tiles of you?",
        keywords = "purge despawn kill clean" })
add("population", "pop.remove100", "Remove NPCs within 100 tiles", "Despawns every A-Life NPC within 100 tiles of you.",
    "danger", "client", { client = "purgeRadius:100", confirm = "Remove every A-Life NPC within 100 tiles of you?",
        keywords = "purge despawn kill clean" })
add("population", "pop.removeAll", "Remove every NPC", "Despawns every A-Life NPC in the world, spawned or natural.",
    "danger", "server", { command = "debugPurgeActors", args = {}, confirm = "Remove EVERY A-Life NPC in the world? Saved squads are lost too.",
        riskNote = "Wipes the whole population including saved squads. Natural spawns refill it slowly.",
        keywords = "purge despawn everything wipe" })
add("population", "pop.removeSquads", "Remove every squad", "Deletes every squad and its members from the squad ledger.",
    "danger", "server", { command = "debugSquadDelete", args = { all = true }, confirm = "Delete EVERY squad on the map?",
        riskNote = "Wipes every offline and online squad. This cannot be undone.", keywords = "squads delete wipe ledger" })

add("world", "world.raid", "Force full raid", "Starts a full-scale raid on you with the default waves, bypassing day gates and cooldowns.",
    "caution", "server", { command = "raidStart", args = {}, keywords = "attack raid waves siege",
        riskNote = "Hostile crews will attack you and your base. Armed NPCs can kill you." })
add("world", "world.support", "Call support squad", "Makes the NPC nearest to you call for reinforcements.",
    "caution", "server", { command = "debugForceSupport", args = {}, keywords = "reinforcements backup radio",
        riskNote = "Reinforcements arrive by ground or helicopter and may be hostile." })
add("world", "world.meta.gunfire", "Meta: distant gunfire", "Plays distant gunfire near you and tells the server to fire the event.",
    "safe", "client", { client = "meta:gunfire", keywords = "ambient sound event" })
add("world", "world.meta.heli", "Meta: helicopter", "Plays a helicopter flyover and tells the server to fire the event.",
    "safe", "client", { client = "meta:heli", keywords = "ambient sound event aircraft" })
add("world", "world.meta.searchlight", "Meta: searchlight", "Starts a searchlight helicopter flight over the area.",
    "caution", "client", { client = "meta:searchlight", keywords = "helicopter flight light",
        riskNote = "A helicopter circles the area for a few minutes and attracts zombies." })
add("world", "world.meta.ambience", "Meta: ambience", "Plays a random siren, scream or radio ambience.",
    "safe", "client", { client = "meta:ambience", keywords = "ambient sound event" })
add("world", "world.meta.crash", "Meta: car crash", "Spawns a car crash scene near you with survivors.",
    "caution", "client", { client = "meta:crash", keywords = "vehicle accident scene event",
        riskNote = "Creates a crash scene with NPCs. Undo with Remove NPCs within 40 tiles." })
add("world", "world.meta.military", "Meta: military convoy", "Fires the military convoy ambient event.",
    "safe", "client", { client = "meta:military", keywords = "ambient convoy event" })
add("world", "world.silence", "Silence world audio", "Stops stuck helicopter, raid and meta sounds on this computer.",
    "safe", "client", { client = "silenceAudio", keywords = "stuck helicopter sound stop" })
add("world", "world.outpost.lights", "Relight nearest outpost", "Refuels the campfires, switches on the lamps and keeps the generators of the closest outpost within 120 tiles running.",
    "safe", "server", { command = "debugOutpostLights", args = { action = "relight" }, keywords = "fire lamp light generator camp checkpoint compound" })
add("world", "world.outpost.delete", "Delete nearest outpost", "Removes the closest outpost within 60 tiles and its crew.",
    "danger", "client", { client = "deleteOutpost", confirm = "Delete the nearest outpost and everyone staffing it?",
        keywords = "remove camp checkpoint compound" })
add("world", "world.visit.trigger", "Trigger base visit", "Forces the chosen safehouse event for your base, such as a visitor knock.",
    "caution", "client", { client = "visitTrigger", keywords = "safehouse visitor knock event base" })
add("world", "world.visit.mark", "Create test base here", "Marks the building you stand in as your test base for visits.",
    "caution", "server", { command = "debugSafehouse", args = { action = "mark" }, keywords = "safehouse base mark" })
add("world", "world.visit.state", "Show base state", "Prints the safehouse director state for your base.",
    "safe", "server", { command = "debugSafehouse", args = { action = "state" }, keywords = "safehouse base state" })
add("world", "world.visit.tick", "Force next director tick", "Runs one safehouse director check now, skipping quiet days and cooldowns.",
    "caution", "server", { command = "debugSafehouse", args = { action = "tick" }, keywords = "safehouse director pacing" })
add("world", "world.visit.diag", "Safehouse diagnostics", "Writes the safehouse diagnostics text to the log and a report file.",
    "safe", "server", { command = "debugSafehouse", args = { action = "diagnostics" }, keywords = "safehouse report dump" })
add("world", "world.visit.clear", "Clear test base", "Removes your test base mark.",
    "safe", "server", { command = "debugSafehouse", args = { action = "clear" }, keywords = "safehouse base unmark" })
add("world", "world.pickedover.mark", "Make building picked over", "Marks the building you are in as picked over at level 3 and applies it now: opened doors, broken windows, blood and corpses.",
    "caution", "server", { command = "debugPickedOver", args = { action = "mark", level = 3 }, keywords = "loot looted building",
        riskNote = "Doors, windows, blood and corpses already placed stay. Loot is thinned the next time containers are filled." })
add("world", "world.pickedover.info", "Picked-over state", "Shows the picked-over level of the building you are in.",
    "safe", "server", { command = "debugPickedOver", args = { action = "info" }, keywords = "loot looted building" })
add("world", "world.pickedover.clear", "Clear picked-over mark", "Removes the picked-over record of the building you are in. Objects already placed stay.",
    "caution", "server", { command = "debugPickedOver", args = { action = "clear" }, keywords = "loot looted building unmark" })
add("world", "world.funnel.reset", "Funnel: back to real day", "Clears the funnel day preview and returns to the real world day.",
    "safe", "server", { command = "adminFunnel", args = { reset = true }, keywords = "stage day time skip" })
for stage = 0, 7 do
    add("world", "world.funnel." .. tostring(stage), "Funnel stage " .. tostring(stage),
        "Previews funnel stage " .. tostring(stage) .. " for this session: spawn weights, gear tier and party sizes follow that stage. The game clock is not changed.",
        "caution", "server", { command = "adminFunnel", args = { stage = stage }, keywords = "time skip day stage preview funnel",
            riskNote = "Changes what natural spawns look like until you reset or reload. The game clock and saves are untouched." })
end

add("reputation", "rep.view", "Refresh reputation", "Reads your personal reputation and each faction's attitude from the server.",
    "safe", "server", { command = "adminRepView", args = {}, keywords = "score level standing factions" })
for _, delta in ipairs({ -50, -10, -5, -1, 1, 5, 10, 50 }) do
    local word = delta > 0 and "Reputation +" or "Reputation -"
    add("reputation", "rep.adjust." .. (delta > 0 and "p" or "m") .. tostring(math.abs(delta)),
        word .. tostring(math.abs(delta)), "Changes your personal reputation score by " .. tostring(delta)
            .. " and shows the reputation popup.", "caution", "server",
        { command = "debugRepAdjust", args = { delta = delta }, keywords = "score level standing karma",
            riskNote = "Changes how every NPC treats you. It is saved with the world." })
end

add("diagnostics", "diag.refresh", "Refresh diagnostics", "Reads module status, performance counters and recent errors from the server.",
    "safe", "server", { command = "adminSnapshot", args = { sections = "diagnostics" }, keywords = "modules perf errors" })
add("diagnostics", "diag.blackbox", "Black box dump", "Writes the flight recorder and a shell census to the log for a bug report.",
    "safe", "server", { command = "debugBlackbox", args = {}, keywords = "export bug report recorder log",
        riskNote = "Large log write. Do it once per bug report, not repeatedly." })
add("diagnostics", "diag.qa", "Module QA dump", "Writes the full QA report (module table, counters, shells) to the log and report file.",
    "safe", "server", { command = "debugModuleQA", args = {}, keywords = "export bug report modules counters log" })
add("diagnostics", "diag.footwork.on", "Force melee footwork on", "Makes every melee NPC run the footwork module (back-pedal, side-steps, facing kept), then writes the QA dump. For test factions; it ends with a restart.",
    "caution", "server", { command = "debugModuleQA", args = { footworkForce = "all" }, keywords = "melee footwork facing backpedal strafe force test faction" })
add("diagnostics", "diag.footwork.off", "Melee footwork: profile rules", "Ends the footwork force and lets each NPC profile decide again, then writes the QA dump.",
    "safe", "server", { command = "debugModuleQA", args = { footworkForce = "off" }, keywords = "melee footwork facing force off" })
add("diagnostics", "diag.health", "Run diagnostics", "Runs the server health check and lists active actors, errors and warnings.",
    "safe", "server", { command = "debugDiagnostics", args = {}, keywords = "health faults check" })
add("diagnostics", "diag.repair", "Repair runtime", "Fixes invalid runtime state found by the health check.",
    "danger", "server", { command = "debugRepair", args = {}, confirm = "Repair invalid runtime state now? Broken actors may be removed.",
        riskNote = "May remove actors whose records are inconsistent. Run the health check first.",
        keywords = "fix health repair state" })
add("diagnostics", "diag.aitrace.off", "AI trace log off", "Stops the server printing [ALIFE-AI] lines. They appear every few seconds while Diagnostics is on and can fill the log.",
    "safe", "server", { command = "adminLog", args = { aiTrace = false }, keywords = "log spam ai trace verbosity console server" })
add("diagnostics", "diag.aitrace.on", "AI trace log on", "Lets the server print [ALIFE-AI] decision lines for up to 16 NPCs every 5 seconds while Diagnostics is on.",
    "caution", "server", { command = "adminLog", args = { aiTrace = true }, keywords = "log ai trace verbosity console server",
        riskNote = "Large log output while NPCs are active. Turn it off when you are done." })
add("diagnostics", "diag.recorder", "Toggle flight recorder", "Switches the flight recorder on or off for this session and your saved preference.",
    "safe", "client", { client = "toggleRecorder", keywords = "blackbox recorder log" })
add("diagnostics", "diag.verbosity", "Cycle log verbosity", "Cycles the console log detail: quiet, normal, verbose. Affects what the admin console prints.",
    "safe", "client", { client = "cycleVerbosity", keywords = "logging log detail print" })
add("diagnostics", "diag.copy", "Copy last report", "Copies the text of the current tab to the clipboard.",
    "safe", "client", { client = "copyReport", keywords = "clipboard text export" })
add("diagnostics", "diag.off", "Turn Diagnostics off", "Turns the Diagnostics option off, which hides every admin tool and closes this console.",
    "caution", "client", { client = "diagnosticsOff", confirm = "Turn Diagnostics off? This console and the right-click tools will close.",
        keywords = "disable hide tools" })

add("settings", "settings.copy", "Copy changed settings", "Copies every option that differs from its default to the clipboard as text.",
    "safe", "client", { client = "copySettings", keywords = "clipboard export changed non default" })
add("settings", "settings.refresh", "Refresh settings", "Re-reads the live sandbox values and the active presets.",
    "safe", "client", { client = "refreshSettings", keywords = "sandbox options values preset" })

add("cleanup", "cleanup.open", "Open cleanup tool", "Opens the Cleanup A-Life window when the cleanup tool is installed.",
    "caution", "client", { client = "cleanupOpen", keywords = "clean leftovers scan orphan",
        riskNote = "The cleanup window can remove NPCs and objects. It asks before it deletes anything." })

return Actions
