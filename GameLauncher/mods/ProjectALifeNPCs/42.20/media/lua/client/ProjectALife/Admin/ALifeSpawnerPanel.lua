require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"
require "ProjectALife/Admin/ALifeSpawnerBrowser"

ProjectALife = ProjectALife or {}

local Panel = {}
ProjectALife.SpawnerPanel = Panel

function Panel.state(panel)
    return ProjectALife.AdminConsole.player(panel.playerNum)
end

function Panel.spec(panel)
    return Panel.state(panel).spec
end

function Panel.planRows(list)
    local rows = {}
    for _, row in ipairs(list) do rows[#rows + 1] = { row.label, row.id, row.tip } end
    return rows
end

function Panel.addLabel(panel, name, text)
    local UI = ProjectALife.AdminUI
    local label = UI.addLabel(panel, text, 0, 0, UI.colors.muted)
    for _, key in ipairs({ "what", "how", "where", "preview", "history" }) do
        if key == name then label.heading = true end
    end
    panel.L[name] = label
    return label
end

function Panel.combo(panel, name, field, rows)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local combo = UI.combo(panel, 0, 0, 100, metrics.buttonH, panel, Panel.onCombo)
    combo.field = field
    UI.fillCombo(combo, rows, nil)
    panel.w[name] = combo
    return combo
end

function Panel.entry(panel, name, field, numbers, placeholder)
    local UI = ProjectALife.AdminUI
    local entry = UI.entry(panel, 0, 0, 80, UI.metrics().buttonH, "", numbers, placeholder)
    entry.field = field
    entry.onTextChangeFunction = Panel.onEntry
    entry.target = panel
    panel.w[name] = entry
    return entry
end

function Panel.button(panel, name, label, callback, tip, accent)
    local UI = ProjectALife.AdminUI
    local button = UI.button(panel, 0, 0, 80, UI.metrics().buttonH, label, panel, callback, accent)
    button.tooltip = tip
    panel.w[name] = button
    return button
end

function Panel.tick(panel, name, label, callback, tip)
    local UI = ProjectALife.AdminUI
    local box = UI.tick(panel, 0, 0, 200, UI.metrics().buttonH - 6, label, false, panel, callback)
    box.tooltipText = tip
    panel.w[name] = box
    return box
end

function Panel.build(panel, window)
    local UI = ProjectALife.AdminUI
    local plan = ProjectALife.SpawnPlan
    panel.playerNum = window.playerNum
    panel.window = window
    panel.w, panel.L, panel.adv = {}, {}, {}
    panel.layout, panel.refresh, panel.onReply = Panel.layout, Panel.refresh, Panel.onReply
    panel.catalogChanged, panel.autoRefresh = Panel.catalogChanged, Panel.autoRefresh
    Panel.addLabel(panel, "what", "1  WHAT")
    Panel.addLabel(panel, "how", "2  HOW")
    Panel.addLabel(panel, "where", "3  WHERE AND WHEN")
    Panel.addLabel(panel, "count", "Count")
    Panel.addLabel(panel, "stance", "Stance")
    Panel.addLabel(panel, "mode", "Mode")
    Panel.addLabel(panel, "seed", "Seed")
    Panel.addLabel(panel, "wheremode", "Place")
    Panel.addLabel(panel, "distance", "Distance")
    Panel.addLabel(panel, "heading", "Heading")
    Panel.addLabel(panel, "coords", "X Y Z")
    Panel.addLabel(panel, "marker", "Marker")
    Panel.addLabel(panel, "delay", "Delay (s)")
    Panel.addLabel(panel, "preview", "PREVIEW (checked by the server)")
    Panel.addLabel(panel, "history", "HISTORY (newest first)")
    Panel.addLabel(panel, "summary", "")
    Panel.addLabel(panel, "target", "")
    Panel.addLabel(panel, "roster", "")
    Panel.addLabel(panel, "hint", "")

    local kind = Panel.combo(panel, "kind", "kind", Panel.planRows(plan.KINDS))
    kind.tooltip = "What to spawn. The list below changes with the type."
    panel.w.filter = UI.entry(panel, 0, 0, 100, UI.metrics().buttonH, "", false, "Search...")
    panel.w.filter.onTextChangeFunction = Panel.onFilter
    panel.w.filter.target = panel
    panel.w.pick = UI.List:new(0, 0, 100, 100, { target = panel, onPick = Panel.onPick, drawRow = ProjectALife.SpawnerBrowser.drawRow,
        empty = "Loading the catalog..." })
    panel.w.pick:initialise()
    panel:addChild(panel.w.pick)
    panel.w.member = UI.List:new(0, 0, 100, 100, { target = panel, onPick = Panel.onMember, drawRow = ProjectALife.SpawnerBrowser.drawRow,
        empty = "Pick a faction to list its members." })
    panel.w.member:initialise()
    panel:addChild(panel.w.member)
    Panel.button(panel, "clearRoster", "Clear roster", Panel.onClearRoster, "Empties the custom roster.")

    Panel.entry(panel, "count", "count", true)
    Panel.combo(panel, "stance", "stance", Panel.planRows(plan.STANCES))
    Panel.combo(panel, "mode", "mode", Panel.planRows(plan.MODES))
    Panel.entry(panel, "seed", "seed", true, "random")
    Panel.button(panel, "roll", "Roll", Panel.onRoll, "Picks a seed so the same roster can be spawned again later.")
    Panel.tick(panel, "dormant", "Spawn dormant", Panel.onDormant,
        "The squad exists as a map marker without bodies and gets bodies when a player comes near. Needs squads, members or rosters.")
    Panel.tick(panel, "gates", "Ignore funnel and day gating", Panel.onGates,
        "On: admin spawn, no gating. Off: refuse factions that are outside their day window or the funnel stage, like natural spawns.")
    Panel.button(panel, "advanced", "Advanced...", Panel.onAdvanced, "All the old debug spawner fields: doctrine, role, health, support, loot, raid waves.")

    Panel.combo(panel, "where", "where", Panel.planRows(plan.WHERE))
    Panel.entry(panel, "distance", "distance", true)
    local headings = {}
    for _, row in ipairs(plan.HEADINGS) do headings[#headings + 1] = { row.label, row.id } end
    local heading = UI.combo(panel, 0, 0, 100, UI.metrics().buttonH, panel, Panel.onCombo)
    heading.field = "heading"
    UI.fillCombo(heading, headings, nil)
    panel.w.heading = heading
    Panel.entry(panel, "x", "x", true)
    Panel.entry(panel, "y", "y", true)
    Panel.entry(panel, "z", "z", true)
    Panel.button(panel, "here", "My position", Panel.onHere, "Fills X, Y, Z with where you stand.")
    local marker = UI.combo(panel, 0, 0, 100, UI.metrics().buttonH, panel, Panel.onCombo)
    marker.field = "markerId"
    panel.w.marker = marker
    Panel.button(panel, "markers", "Refresh", Panel.onMarkers, "Reloads the live encounters, outposts and your last spawn spots.")
    Panel.entry(panel, "delay", "delaySec", true)

    panel.w.report = UI.Report:new(0, 0, 100, 100)
    panel.w.report:initialise()
    panel:addChild(panel.w.report)
    panel.report = panel.w.report
    panel.w.history = UI.List:new(0, 0, 100, 100, { target = panel, onPick = Panel.onHistory, drawRow = Panel.drawHistory,
        empty = "Nothing spawned from this console yet." })
    panel.w.history:initialise()
    panel:addChild(panel.w.history)
    Panel.button(panel, "previewBtn", "Preview", Panel.onPreview, "Asks the server for the roster, the square check and the gating verdict.")
    Panel.button(panel, "spawnBtn", "SPAWN", Panel.onSpawn, "Sends the request. The preview roster is the roster that spawns.", true)
    Panel.button(panel, "undoSel", "Undo selected", Panel.onUndoSelected, "Removes exactly what the selected batch created.")
    Panel.button(panel, "undoLast", "Undo last", Panel.onUndoLast, "Removes exactly what the newest batch created.")
    Panel.button(panel, "undoAll", "Despawn all mine", Panel.onUndoAll, "Removes everything you spawned from this console. Asks first.")
    Panel.button(panel, "clearList", "Clear list", Panel.onClearList, "Forgets finished batches in this list. Nothing is removed from the world.")
    panel.quick = {}
    for index, id in ipairs({ "spawn.preset.test_squad", "spawn.preset.medic", "spawn.preset.raid", "spawn.preset.visitor" }) do
        local spec = ProjectALife.AdminActions.get(id)
        local button = UI.button(panel, 0, 0, 80, UI.metrics().buttonH, spec.label, window, UI.onAction, false)
        button.actionId = id
        button.tooltip = ProjectALife.AdminActions.tooltip(spec, ProjectALife.AdminConsole.context(window.playerNum))
        panel.quick[index] = button
    end
    panel.w.presetName = UI.entry(panel, 0, 0, 100, UI.metrics().buttonH, "", false, "preset name")
    Panel.button(panel, "presetSave", "Save", Panel.onPresetSave, "Saves the whole form under this name on this computer.")
    panel.w.presetCombo = UI.combo(panel, 0, 0, 100, UI.metrics().buttonH, panel, Panel.onNoop)
    Panel.button(panel, "presetLoad", "Load", Panel.onPresetLoad, "Loads the chosen saved preset into the form.")
    Panel.button(panel, "presetDelete", "Delete", Panel.onPresetDelete, "Deletes the chosen saved preset.")
    Panel.buildAdvanced(panel)
    panel.filterText = ""
    Panel.fillPresets(panel)
    Panel.refresh(panel)
end

function Panel.onNoop() end

function Panel.onShow(panel, window)
    local console = ProjectALife.AdminConsole
    console.requestFactions(window.playerNum, false)
    console.requestCatalog(window.playerNum)
    Panel.refresh(panel)
end

function Panel.setFilter(window, text)
    local panel = window.tabPanels.spawn
    if panel == nil then return end
    panel.filterText = tostring(text or "")
    panel.w.filter:setText(panel.filterText)
    Panel.refreshLists(panel)
end

function Panel.onFilter(panel, entry)
    panel.filterText = entry:getText()
    Panel.refreshLists(panel)
end

function Panel.setField(panel, key, value)
    local spec = Panel.spec(panel)
    spec[key] = value
    ProjectALife.AdminConsole.markDirty(panel.playerNum)
    Panel.updateVisibility(panel)
    Panel.refreshSummary(panel)
end

function Panel.onCombo(panel, combo)
    local value = ProjectALife.AdminUI.comboData(combo)
    local key = combo.field
    Panel.setField(panel, key, value)
    if key == "kind" then
        panel.filterText = ""
        panel.w.filter:setText("")
        Panel.refreshLists(panel)
        local spec = Panel.spec(panel)
        if spec.kind == "visitor" and spec.event == nil then
            local ids = ProjectALife.AdminConsole.visitorIds()
            spec.event = ids[1]
        end
        Panel.refreshLists(panel)
    elseif key == "where" then
        if value == "marker" then Panel.collectMarkers(panel) end
    end
end

function Panel.onEntry(panel, entry)
    local key = entry.field
    local text = entry:getText()
    local number = tonumber(text)
    if key == "seed" then
        Panel.setField(panel, key, text ~= "" and number or nil)
        return
    end
    if number == nil then
        if text == "" and (key == "distance" or key == "delaySec") then number = 0 else return end
    end
    Panel.setField(panel, key, number)
end

function Panel.onDormant(panel, index, selected)
    Panel.setField(panel, "dormant", selected == true)
end

function Panel.onGates(panel, index, selected)
    Panel.setField(panel, "ignoreGates", selected == true)
end

function Panel.onRoll(panel)
    local console = ProjectALife.AdminConsole
    local seed = math.floor(console.nowMs() % 1000003) + 1
    panel.w.seed:setText(tostring(seed))
    Panel.setField(panel, "seed", seed)
end

function Panel.onHere(panel)
    local origin = ProjectALife.AdminConsole.playerOrigin(panel.playerNum)
    if origin == nil then return end
    local spec = Panel.spec(panel)
    spec.x, spec.y, spec.z = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z)
    Panel.refresh(panel)
    ProjectALife.AdminConsole.markDirty(panel.playerNum)
end

function Panel.collectMarkers(panel)
    local console = ProjectALife.AdminConsole
    local state = Panel.state(panel)
    local markers, rows = {}, {}
    local function add(id, label, at)
        if at ~= nil and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil and #rows < 40 then
            markers[id] = { x = at.x, y = at.y, z = tonumber(at.z) or 0, label = label }
            rows[#rows + 1] = { label, id }
        end
    end
    for index = #state.history.entries, 1, -1 do
        local entry = state.history.entries[index]
        add("spawn:" .. entry.requestId, "Spawn: " .. tostring(entry.summary), entry.origin)
    end
    local snapshot = console.snapshot
    local sites = snapshot ~= nil and snapshot.world ~= nil and snapshot.world.outposts ~= nil and snapshot.world.outposts.sites or {}
    for _, site in ipairs(sites) do add("site:" .. tostring(site.id), "Outpost: " .. tostring(site.preset), site) end
    for _, mark in ipairs(type(console.encounterMarks) == "table" and console.encounterMarks or {}) do
        add("mark:" .. tostring(mark.id) .. tostring(mark.x), "Encounter: " .. tostring(mark.label or mark.id), mark)
    end
    state.markers = markers
    if #rows == 0 then rows[1] = { "No markers yet", "" } end
    local spec = Panel.spec(panel)
    ProjectALife.AdminUI.fillCombo(panel.w.marker, rows, spec.markerId)
    if spec.markerId == nil then spec.markerId = ProjectALife.AdminUI.comboData(panel.w.marker) end
end

function Panel.onMarkers(panel)
    local console = ProjectALife.AdminConsole
    console.send(panel.playerNum, "debugEncounterMarks", {})
    console.requestSnapshot(panel.playerNum, "world", true)
    Panel.collectMarkers(panel)
end

function Panel.onPick(panel, row)
    local console = ProjectALife.AdminConsole
    local spec = Panel.spec(panel)
    local kind = row.kind
    if kind == "folder" then
        local browser = ProjectALife.SpawnerBrowser
        browser.collapsed[row.id] = not browser.collapsed[row.id]
        Panel.refreshLists(panel)
        return
    end
    if kind == "faction" then
        spec.factionId = row.id
        spec.memberId = nil
        console.requestMembers(panel.playerNum, row.id)
    elseif kind == "automatic" then
        spec.factionId = nil
    elseif kind == "encounter" then
        spec.encounterId = row.id
    elseif kind == "preset" then
        spec.presetId = row.id
    elseif kind == "visit" then
        spec.event = row.id
        console.player(panel.playerNum).visitEvent = row.id
    end
    console.markDirty(panel.playerNum)
    Panel.refreshLists(panel)
    Panel.refreshSummary(panel)
end

function Panel.onMember(panel, row)
    local console = ProjectALife.AdminConsole
    local spec = Panel.spec(panel)
    if row.kind ~= "member" then return end
    if spec.kind == "roster" then
        local total = 0
        for _, entry in ipairs(spec.roster) do total = total + entry.count end
        if total >= ProjectALife.SpawnPlan.LIMITS.roster then
            console.log(panel.playerNum, "A roster holds at most " .. tostring(ProjectALife.SpawnPlan.LIMITS.roster) .. " members.", "warning")
            return
        end
        local found = false
        for _, entry in ipairs(spec.roster) do
            if entry.id == row.id then entry.count = entry.count + 1; found = true end
        end
        if not found then spec.roster[#spec.roster + 1] = { id = row.id, count = 1 } end
    else
        spec.memberId = row.id
    end
    console.markDirty(panel.playerNum)
    Panel.refreshSummary(panel)
end

function Panel.onClearRoster(panel)
    Panel.spec(panel).roster = {}
    ProjectALife.AdminConsole.markDirty(panel.playerNum)
    Panel.refreshSummary(panel)
end

function Panel.onPreview(panel)
    ProjectALife.AdminConsole.preview(panel.playerNum)
end

function Panel.onSpawn(panel)
    ProjectALife.AdminConsole.spawn(panel.playerNum)
end

function Panel.onHistory(panel, row)
    Panel.state(panel).historySelected = row.requestId
end

function Panel.onUndoSelected(panel)
    local state = Panel.state(panel)
    local entry = state.historySelected ~= nil and state.history.byRequest[state.historySelected] or nil
    if entry == nil then
        ProjectALife.AdminConsole.log(panel.playerNum, "Select a batch in the history first.", "warning")
        return
    end
    ProjectALife.AdminConsole.undo(panel.playerNum, entry)
end

function Panel.onUndoLast(panel)
    ProjectALife.AdminConsole.undo(panel.playerNum)
end

function Panel.onUndoAll(panel)
    ProjectALife.AdminConsole.run("spawn.undoAll", panel.playerNum, panel.window)
end

function Panel.onClearList(panel)
    local state = Panel.state(panel)
    local keep = ProjectALife.SpawnPlan.newHistory()
    for _, entry in ipairs(state.history.entries) do
        if ProjectALife.SpawnPlan.undoable(entry) or entry.state == "sent" or entry.state == "scheduled" then
            ProjectALife.SpawnPlan.historyAdd(keep, entry)
        end
    end
    state.history = keep
    Panel.refreshHistory(panel)
end

function Panel.fillPresets(panel)
    local prefs = ProjectALife.AdminPrefs
    local _, order = prefs.loadPresets()
    local rows = {}
    for _, name in ipairs(order) do rows[#rows + 1] = { name, name } end
    if #rows == 0 then rows[1] = { "No saved presets", "" } end
    ProjectALife.AdminUI.fillCombo(panel.w.presetCombo, rows, ProjectALife.AdminUI.comboData(panel.w.presetCombo))
end

function Panel.onPresetSave(panel)
    local console = ProjectALife.AdminConsole
    local ok, why = ProjectALife.AdminPrefs.savePreset(panel.w.presetName:getText(), Panel.spec(panel))
    if not ok then
        console.log(panel.playerNum, "Preset not saved: " .. tostring(why), "error")
        return
    end
    Panel.fillPresets(panel)
    console.log(panel.playerNum, "Preset saved.")
end

function Panel.onPresetLoad(panel)
    local console = ProjectALife.AdminConsole
    local name = ProjectALife.AdminUI.comboData(panel.w.presetCombo)
    local spec = name ~= nil and name ~= "" and ProjectALife.AdminPrefs.getPreset(name) or nil
    if spec == nil then
        console.log(panel.playerNum, "No preset chosen.", "warning")
        return
    end
    local state = Panel.state(panel)
    state.spec = ProjectALife.SpawnPlan.normalize(spec)
    state.preview = nil
    console.markDirty(panel.playerNum)
    Panel.refresh(panel)
    console.log(panel.playerNum, "Preset loaded: " .. name)
end

function Panel.onPresetDelete(panel)
    local name = ProjectALife.AdminUI.comboData(panel.w.presetCombo)
    if name == nil or name == "" then return end
    ProjectALife.AdminPrefs.deletePreset(name)
    Panel.fillPresets(panel)
end

function Panel.onAdvanced(panel)
    local advanced = panel.advanced
    advanced:setVisible(not advanced:getIsVisible())
    Panel.refreshAdvanced(panel)
end

function Panel.buildAdvanced(panel)
    local UI = ProjectALife.AdminUI
    local plan = ProjectALife.SpawnPlan
    local metrics = UI.metrics()
    local advanced = UI.panel(panel, 0, 0, 100, 100, true)
    advanced:setScrollChildren(true)
    advanced:addScrollBars()
    advanced.owner = panel
    advanced.prerender = Panel.advancedPrerender
    advanced.render = Panel.advancedRender
    advanced.onMouseWheel = Panel.advancedWheel
    advanced.rowsInfo = {}
    advanced:setVisible(false)
    panel.advanced = advanced
    panel.adv = {}
    for index, row in ipairs(plan.ADVANCED) do
        local widget
        if row.kind == "bool" then
            widget = UI.tick(advanced, 0, 0, 200, metrics.buttonH - 6, row.label, false, advanced, Panel.onAdvBool)
            widget.advKey = row.key
        elseif row.kind == "number" then
            widget = UI.entry(advanced, 0, 0, 100, metrics.buttonH, "", true, "profile")
            widget.field = row.key
            widget.onTextChangeFunction = Panel.onAdvEntry
            widget.target = panel
        else
            widget = UI.combo(advanced, 0, 0, 100, metrics.buttonH, panel, Panel.onAdvCombo)
            widget.field = row.key
            Panel.fillAdvancedCombo(widget, row)
        end
        widget.advRow = row
        panel.adv[row.key] = widget
        advanced.rowsInfo[index] = row
    end
    Panel.layoutAdvanced(panel)
end

function Panel.dropChoices(row)
    local policy = ProjectALife.DropPolicy
    local choices = { { "Use profile", "profile" } }
    if type(policy) ~= "table" then return choices end
    if row.key == "weaponChance" then
        for _, item in ipairs(type(policy.presets) == "table" and policy.presets or {}) do choices[#choices + 1] = { item[1], item[2] } end
    else
        for _, item in ipairs(type(policy.conditions) == "table" and policy.conditions or {}) do
            choices[#choices + 1] = { item[1], tostring(item[2]) }
        end
    end
    return choices
end

function Panel.fillAdvancedCombo(combo, row)
    local rows = row.choices
    if row.kind == "drop" then rows = Panel.dropChoices(row) end
    if row.key == "animation" then
        local catalog = ProjectALife.AdminConsole.catalog()
        local list = {}
        for _, preset in ipairs(catalog ~= nil and type(catalog.animations) == "table" and catalog.animations or {}) do
            if type(preset) == "table" and preset.id ~= nil then list[#list + 1] = { tostring(preset.label or preset.id), preset.id } end
        end
        if #list > 0 then rows = list end
    end
    ProjectALife.AdminUI.fillCombo(combo, rows, nil)
end

function Panel.onAdvCombo(panel, combo)
    local spec = Panel.spec(panel)
    spec.adv[combo.field] = ProjectALife.AdminUI.comboData(combo)
    ProjectALife.AdminConsole.markDirty(panel.playerNum)
end

function Panel.onAdvEntry(panel, entry)
    local spec = Panel.spec(panel)
    local text = entry:getText()
    spec.adv[entry.field] = text ~= "" and tonumber(text) or nil
    ProjectALife.AdminConsole.markDirty(panel.playerNum)
end

function Panel.onAdvBool(advanced, index, selected, a, b, box)
    local panel = advanced.owner
    local key = box ~= nil and box.advKey or nil
    if key == nil then return end
    Panel.spec(panel).adv[key] = selected == true
    ProjectALife.AdminConsole.markDirty(panel.playerNum)
end

function Panel.advancedPrerender(advanced)
    local UI = ProjectALife.AdminUI
    ISPanel.prerender(advanced)
    advanced:setStencilRect(1, 1, advanced.width - 2, advanced.height - 2)
    local colors = UI.colors
    advanced:drawText("ADVANCED: blank or 'Use profile' keeps each member's own setting", 10, 8, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
    for _, entry in ipairs(advanced.labelRefs or {}) do
        advanced:drawText(entry.text, entry.x, entry.y, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    end
end

function Panel.advancedRender(advanced)
    advanced:clearStencilRect()
end

function Panel.advancedWheel(advanced, delta)
    local metrics = ProjectALife.AdminUI.metrics()
    advanced:setYScroll(advanced:getYScroll() - delta * metrics.rowH * 2)
    return true
end

function Panel.layoutAdvanced(panel)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local advanced = panel.advanced
    local pad = 12
    local columns = advanced.width > 640 and 3 or 2
    local colW = math.floor((advanced.width - pad * 2 - 14 * (columns - 1)) / columns)
    local labelW = math.floor(colW * 0.46)
    local controlW = colW - labelW - 4
    local rowH = metrics.rowH + 4
    advanced.labelRefs = {}
    local perColumn = math.ceil(#ProjectALife.SpawnPlan.ADVANCED / columns)
    for index, row in ipairs(ProjectALife.SpawnPlan.ADVANCED) do
        local column = math.floor((index - 1) / perColumn)
        local line = (index - 1) % perColumn
        local x = pad + column * (colW + 14)
        local y = 32 + line * rowH
        local widget = panel.adv[row.key]
        if row.kind == "bool" then
            UI.setBounds(widget, x, y + 2, colW, metrics.buttonH - 6)
        else
            advanced.labelRefs[#advanced.labelRefs + 1] = { text = UI.fit(row.label, labelW), x = x, y = y + 5 }
            UI.setBounds(widget, x + labelW + 4, y, controlW, metrics.buttonH)
        end
        widget.tooltip = row.tip
    end
    advanced:setScrollHeight(32 + perColumn * rowH + 12)
end

function Panel.refreshAdvanced(panel)
    local spec = Panel.spec(panel)
    for key, widget in pairs(panel.adv) do
        local row = widget.advRow
        local value = spec.adv[key]
        if row.kind == "bool" then
            widget:setSelected(1, value == true)
        elseif row.kind == "number" then
            if not (type(widget.isFocused) == "function" and widget:isFocused()) then
                widget:setText(value ~= nil and tostring(value) or "")
            end
        else
            local chosen = 1
            for index = 1, widget:getOptionCount() do
                if widget:getOptionData(index) == value then chosen = index end
            end
            widget.selected = chosen
        end
    end
end

function Panel.catalogChanged(panel)
    Panel.refreshLists(panel)
    local animation = panel.adv ~= nil and panel.adv.animation or nil
    if animation ~= nil then
        Panel.fillAdvancedCombo(animation, animation.advRow)
        Panel.refreshAdvanced(panel)
    end
end

function Panel.autoRefresh(panel)
    Panel.refreshHistory(panel)
    Panel.refreshPreview(panel)
end

function Panel.onReply(panel, command, arguments)
    if command == "adminFactionIndexResult" or command == "adminFactionMembersResult" or command == "debugCatalogResult" then
        Panel.refreshLists(panel)
    elseif command == "adminSpawnPreviewResult" then
        Panel.refreshPreview(panel)
    elseif command == "adminSpawnResult" or command == "adminSpawnBatchResult" or command == "adminSpawnUndoResult" then
        Panel.refreshHistory(panel)
    elseif command == "debugEncounterMarksResult" then
        ProjectALife.AdminConsole.encounterMarks = type(arguments.encounters) == "table" and arguments.encounters or {}
        Panel.collectMarkers(panel)
    end
end

function Panel.refreshLists(panel)
    local browser = ProjectALife.SpawnerBrowser
    local spec = Panel.spec(panel)
    local kind = spec.kind
    local query = panel.filterText or ""
    local pick, member = panel.w.pick, panel.w.member
    local pickRows, memberRows, hint = {}, {}, nil
    if kind == "squad" or kind == "member" or kind == "roster" then
        pickRows = browser.factionRows(query, false)
        memberRows, hint = browser.memberRows(spec.factionId, "")
    elseif kind == "encounter" then
        pickRows = browser.encounterRows(query)
        memberRows = browser.factionRows("", true)
    elseif kind == "outpost" then
        pickRows = browser.presetRows(query)
        memberRows = browser.factionRows("", true)
    elseif kind == "visitor" then
        pickRows = browser.visitRows(query)
    elseif kind == "raid" then
        pickRows = browser.factionRows(query, true)
    end
    pick:setRows(pickRows, true)
    member:setRows(memberRows, true)
    member.empty = hint or "Nothing to list."
    pick.empty = (#ProjectALife.AdminConsole.factions.rows == 0 and (kind == "squad" or kind == "member" or kind == "roster" or kind == "raid"))
        and "Loading factions from the server..." or "Nothing matches."
    Panel.markSelection(panel)
end

function Panel.markSelection(panel)
    local spec = Panel.spec(panel)
    local pick, member = panel.w.pick, panel.w.member
    local function find(list, id)
        for index, row in ipairs(list.rows) do
            if row.id == id and row.kind ~= "folder" then return index end
        end
        return nil
    end
    local kind = spec.kind
    local pickId, memberId = nil, nil
    if kind == "squad" or kind == "member" or kind == "roster" or kind == "raid" then pickId = spec.factionId
    elseif kind == "encounter" then pickId, memberId = spec.encounterId, spec.factionId
    elseif kind == "outpost" then pickId, memberId = spec.presetId, spec.factionId
    elseif kind == "visitor" then pickId = spec.event end
    pick.selected = find(pick, pickId)
    if kind == "member" then member.selected = find(member, spec.memberId)
    elseif kind == "encounter" or kind == "outpost" then member.selected = find(member, memberId) or (memberId == nil and 1 or nil)
    else member.selected = nil end
    if kind == "raid" and spec.factionId == nil then pick.selected = 1 end
end

function Panel.rosterText(panel)
    local spec = Panel.spec(panel)
    if spec.kind ~= "roster" then return "" end
    local console = ProjectALife.AdminConsole
    local names = {}
    for _, entry in ipairs(spec.roster) do
        local label = entry.id
        for _, stored in pairs(console.members) do
            for _, member in ipairs(stored.rows or {}) do
                if member.id == entry.id then label = member.name end
            end
        end
        names[#names + 1] = tostring(label) .. " x" .. tostring(entry.count)
    end
    if #names == 0 then return "Roster: click members to add them" end
    return "Roster: " .. table.concat(names, ", ")
end

function Panel.refreshSummary(panel)
    local UI = ProjectALife.AdminUI
    local plan = ProjectALife.SpawnPlan
    local console = ProjectALife.AdminConsole
    local state = Panel.state(panel)
    local spec = plan.normalize(state.spec)
    local ok, why = plan.validate(spec)
    local position, positionWhy = plan.position(spec, console.planContext(panel.playerNum, state))
    if ok and positionWhy ~= nil then ok, why = false, positionWhy end
    if ok then
        panel.L.summary.text = "Ready: " .. plan.summary(spec, position)
        panel.L.summary.color = UI.colors.good
    else
        panel.L.summary.text = "Not ready: " .. plan.refusalText(why)
        panel.L.summary.color = UI.colors.warn
    end
    local target = state.target
    panel.L.target.text = target ~= nil and ("Clicked target: " .. tostring(target.x) .. ", " .. tostring(target.y) .. ", " .. tostring(target.z))
        or "No clicked target. Right-click the ground and choose Use as A-Life spawn target."
    panel.L.roster.text = Panel.rosterText(panel)
    panel.L.hint.text = Panel.kindHint(spec)
end

function Panel.kindHint(spec)
    local kind = spec.kind
    if kind == "squad" then return "Pick a faction. The server chooses the members unless you roll a seed." end
    if kind == "member" then return "Pick a faction, then one member. It is copied Count times." end
    if kind == "roster" then return "Pick a faction, then click members to build the roster." end
    if kind == "encounter" then return "Pick an encounter, then the faction that casts it (or Automatic)." end
    if kind == "outpost" then return "Pick an outpost preset, then the crew faction (or Automatic)." end
    if kind == "visitor" then return "Pick a visit type. A test base is created at the spot when you have none." end
    if kind == "raid" then return "Forced raid with waves (see Advanced). Pick a faction or Automatic." end
    return "The NPC nearest to you calls for reinforcements."
end

function Panel.refreshPreview(panel)
    local plan = ProjectALife.SpawnPlan
    local state = Panel.state(panel)
    local lines = {}
    local preview = state.preview
    if preview == nil then
        lines[1] = ProjectALife.AdminUI.line("Change the form and the server previews it, or press Preview.", "muted")
    else
        local stale = state.previewKey ~= ProjectALife.AdminConsole.specKey(state.spec)
        for _, text in ipairs(plan.previewLines(preview)) do
            local color = string.find(text, "refused", 1, true) ~= nil and "bad" or (string.find(text, "Gate:", 1, true) ~= nil and "warn" or "text")
            lines[#lines + 1] = ProjectALife.AdminUI.line(text, stale and "muted" or color)
        end
        if stale then lines[#lines + 1] = ProjectALife.AdminUI.line("(the form changed since this preview)", "muted") end
    end
    panel.w.report:setLines(lines)
end

function Panel.historyRows(panel)
    local rows = {}
    for _, entry in ipairs(ProjectALife.SpawnPlan.historyMine(Panel.state(panel).history)) do
        rows[#rows + 1] = { requestId = entry.requestId, entry = entry, label = ProjectALife.SpawnPlan.historyLine(entry) }
    end
    return rows
end

function Panel.drawHistory(list, row, y, selected)
    local UI = ProjectALife.AdminUI
    local entry = row.entry
    local color = UI.colors.text
    if entry.state == "refused" or entry.state == "failed" then color = UI.colors.bad
    elseif entry.state == "undone" then color = UI.colors.muted
    elseif entry.state == "partial" or entry.state == "scheduled" then color = UI.colors.warn
    elseif entry.state == "settled" then color = UI.colors.good end
    list:drawText(UI.fit(row.label, list.width - 14), 8, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
end

function Panel.refreshHistory(panel)
    panel.w.history:setRows(Panel.historyRows(panel), true)
end

function Panel.updateVisibility(panel)
    local spec = Panel.spec(panel)
    local w = panel.w
    local where = spec.where
    local kind = spec.kind
    w.distance:setVisible(where == "player")
    w.heading:setVisible(where == "player")
    for _, name in ipairs({ "x", "y", "z", "here" }) do w[name]:setVisible(where == "coords") end
    w.marker:setVisible(where == "marker")
    w.markers:setVisible(where == "marker")
    local fixedRoster = kind == "squad" or kind == "member" or kind == "roster"
    w.dormant:setVisible(fixedRoster or kind == "encounter")
    w.mode:setVisible(fixedRoster)
    w.stance:setVisible(kind ~= "visitor" and kind ~= "support")
    w.count:setVisible(kind ~= "visitor" and kind ~= "support" and kind ~= "roster")
    w.seed:setVisible(fixedRoster)
    w.roll:setVisible(fixedRoster)
    w.clearRoster:setVisible(kind == "roster")
    w.member:setVisible(kind ~= "visitor" and kind ~= "support" and kind ~= "raid")
    w.pick:setVisible(kind ~= "support")
    w.filter:setVisible(kind ~= "support")
    panel.L.distance.hidden, panel.L.heading.hidden = where ~= "player", where ~= "player"
    panel.L.coords.hidden = where ~= "coords"
    panel.L.marker.hidden = where ~= "marker"
    panel.L.mode.hidden = not fixedRoster
    panel.L.stance.hidden = kind == "visitor" or kind == "support"
    panel.L.count.hidden = kind == "visitor" or kind == "support" or kind == "roster"
    panel.L.seed.hidden = not fixedRoster
    panel.L.target.hidden = where ~= "target"
    panel.L.roster.hidden = kind ~= "roster"
end

function Panel.selectCombo(combo, value)
    local chosen = 1
    for index = 1, combo:getOptionCount() do
        if combo:getOptionData(index) == value then chosen = index end
    end
    combo.selected = chosen
end

function Panel.setText(entry, text)
    if type(entry.isFocused) == "function" and entry:isFocused() then return end
    entry:setText(text)
end

function Panel.refresh(panel)
    local spec = ProjectALife.SpawnPlan.normalize(Panel.spec(panel))
    local state = Panel.state(panel)
    state.spec = spec
    local w = panel.w
    Panel.selectCombo(w.kind, spec.kind)
    Panel.selectCombo(w.stance, spec.stance)
    Panel.selectCombo(w.mode, spec.mode)
    Panel.selectCombo(w.where, spec.where)
    Panel.selectCombo(w.heading, spec.heading)
    Panel.setText(w.count, tostring(spec.count))
    Panel.setText(w.distance, tostring(spec.distance))
    Panel.setText(w.delay, tostring(spec.delaySec))
    Panel.setText(w.seed, spec.seed ~= nil and tostring(spec.seed) or "")
    Panel.setText(w.x, spec.x ~= nil and tostring(spec.x) or "")
    Panel.setText(w.y, spec.y ~= nil and tostring(spec.y) or "")
    Panel.setText(w.z, tostring(spec.z or 0))
    w.dormant:setSelected(1, spec.dormant == true)
    w.gates:setSelected(1, spec.ignoreGates == true)
    Panel.updateVisibility(panel)
    Panel.refreshLists(panel)
    Panel.refreshSummary(panel)
    Panel.refreshPreview(panel)
    Panel.refreshHistory(panel)
    Panel.refreshAdvanced(panel)
    if spec.where == "marker" then Panel.collectMarkers(panel) end
end

function Panel.layout(panel, width, height)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local w, L = panel.w, panel.L
    local rowH, buttonH, fontH = metrics.rowH, metrics.buttonH, metrics.fontH
    local gap = 8
    local listH = rowH * 5
    local bottomH = fontH + 2 + listH + 4 + (buttonH + 4) * 2 + buttonH + 6
    local topH = height - bottomH - gap
    local c1 = math.floor(width * 0.38)
    local c2 = math.floor(width * 0.27)
    local c3 = width - c1 - c2 - gap * 2
    local x1, x2, x3 = 0, c1 + gap, c1 + c2 + gap * 2
    local function at(label, x, y) label.x, label.y = x, y end
    local titleY = 4
    at(L.what, x1 + 4, titleY)
    at(L.how, x2 + 4, titleY)
    at(L.where, x3 + 4, titleY)
    local y = titleY + fontH + 4
    UI.setBounds(w.kind, x1, y, c1, buttonH)
    y = y + buttonH + 4
    UI.setBounds(w.filter, x1, y, c1, buttonH)
    y = y + buttonH + 4
    local listsTop = y
    local avail = topH - listsTop - fontH * 2 - 10
    local pickH = math.floor(avail * 0.52)
    local memberY = listsTop + pickH + 4
    local memberH = avail - pickH - 4
    UI.setBounds(w.pick, x1, listsTop, c1, pickH)
    UI.setBounds(w.member, x1, memberY, c1, memberH)
    UI.setBounds(w.clearRoster, x1 + c1 - 110, memberY + memberH + 2, 110, buttonH - 4)
    at(L.roster, x1 + 4, memberY + memberH + 4)
    at(L.hint, x1 + 4, topH - fontH)
    local labelW = math.floor(c2 * 0.34)
    local fieldW = c2 - labelW - 4
    local rowY = titleY + fontH + 4
    local function line(labelName, widget, extra)
        at(L[labelName], x2 + 4, rowY + 5)
        UI.setBounds(widget, x2 + labelW, rowY, extra and (fieldW - extra - 4) or fieldW, buttonH)
        rowY = rowY + buttonH + 4
    end
    line("count", w.count)
    line("stance", w.stance)
    line("mode", w.mode)
    at(L.seed, x2 + 4, rowY + 5)
    UI.setBounds(w.seed, x2 + labelW, rowY, fieldW - 64, buttonH)
    UI.setBounds(w.roll, x2 + labelW + fieldW - 60, rowY, 60, buttonH)
    rowY = rowY + buttonH + 6
    UI.setBounds(w.dormant, x2 + 4, rowY, c2 - 8, buttonH - 6)
    rowY = rowY + buttonH
    UI.setBounds(w.gates, x2 + 4, rowY, c2 - 8, buttonH - 6)
    rowY = rowY + buttonH + 2
    UI.setBounds(w.advanced, x2, rowY, c2, buttonH)
    local lw3 = math.floor(c3 * 0.28)
    local fw3 = c3 - lw3 - 4
    rowY = titleY + fontH + 4
    at(L.wheremode, x3 + 4, rowY + 5)
    UI.setBounds(w.where, x3 + lw3, rowY, fw3, buttonH)
    rowY = rowY + buttonH + 4
    local slotY = rowY
    at(L.distance, x3 + 4, slotY + 5)
    UI.setBounds(w.distance, x3 + lw3, slotY, fw3, buttonH)
    at(L.heading, x3 + 4, slotY + buttonH + 9)
    UI.setBounds(w.heading, x3 + lw3, slotY + buttonH + 4, fw3, buttonH)
    at(L.coords, x3 + 4, slotY + 5)
    local third = math.floor((fw3 - 8) / 3)
    UI.setBounds(w.x, x3 + lw3, slotY, third, buttonH)
    UI.setBounds(w.y, x3 + lw3 + third + 4, slotY, third, buttonH)
    UI.setBounds(w.z, x3 + lw3 + (third + 4) * 2, slotY, third, buttonH)
    UI.setBounds(w.here, x3 + lw3, slotY + buttonH + 4, fw3, buttonH)
    at(L.marker, x3 + 4, slotY + 5)
    UI.setBounds(w.marker, x3 + lw3, slotY, fw3, buttonH)
    UI.setBounds(w.markers, x3 + lw3, slotY + buttonH + 4, fw3, buttonH)
    at(L.target, x3 + 4, slotY + 5)
    rowY = slotY + (buttonH + 4) * 2 + 6
    at(L.delay, x3 + 4, rowY + 5)
    UI.setBounds(w.delay, x3 + lw3, rowY, fw3, buttonH)
    local bottomY = topH + gap
    local halfW = math.floor(width * 0.52)
    at(L.preview, 4, bottomY)
    at(L.history, halfW + gap + 4, bottomY)
    UI.setBounds(w.report, 0, bottomY + fontH + 2, halfW, listH)
    UI.setBounds(w.history, halfW + gap, bottomY + fontH + 2, width - halfW - gap, listH)
    local buttonsY = bottomY + fontH + 2 + listH + 4
    local bw = math.floor((halfW - 8) / 2)
    UI.setBounds(w.previewBtn, 0, buttonsY, bw, buttonH)
    UI.setBounds(w.spawnBtn, bw + 8, buttonsY, halfW - bw - 8, buttonH)
    at(L.summary, 4, buttonsY + buttonH + 4 + 4)
    local hx = halfW + gap
    local hw = math.floor((width - hx - 12) / 4)
    UI.setBounds(w.undoSel, hx, buttonsY, hw, buttonH)
    UI.setBounds(w.undoLast, hx + hw + 4, buttonsY, hw, buttonH)
    UI.setBounds(w.undoAll, hx + (hw + 4) * 2, buttonsY, hw, buttonH)
    UI.setBounds(w.clearList, hx + (hw + 4) * 3, buttonsY, width - hx - (hw + 4) * 3, buttonH)
    local row2 = buttonsY + buttonH + 4
    local row3 = row2 + buttonH + 4
    local quickW = math.floor((halfW - 12) / 4)
    for index, button in ipairs(panel.quick) do
        UI.setBounds(button, (index - 1) * (quickW + 4), row3, quickW, buttonH)
    end
    local px = hx
    local pw = width - hx
    UI.setBounds(w.presetName, px, row2, math.floor(pw * 0.40), buttonH)
    UI.setBounds(w.presetSave, px + math.floor(pw * 0.40) + 4, row2, math.floor(pw * 0.18), buttonH)
    UI.setBounds(w.presetCombo, px, row3, math.floor(pw * 0.50), buttonH)
    UI.setBounds(w.presetLoad, px + math.floor(pw * 0.50) + 4, row3, math.floor(pw * 0.22), buttonH)
    UI.setBounds(w.presetDelete, px + math.floor(pw * 0.72) + 8, row3, pw - math.floor(pw * 0.72) - 8, buttonH)
    UI.setBounds(panel.advanced, 0, 0, width, height)
    Panel.layoutAdvanced(panel)
    Panel.updateVisibility(panel)
end

function Panel.register()
    local console = ProjectALife.AdminConsole
    local tab = ProjectALife.AdminActions.tab("spawn")
    console.addTab({ id = "spawn", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        build = Panel.build, onShow = Panel.onShow,
        controls = {
            { id = "spawn.kind", label = "Spawn type", tip = "Faction squad, member, roster, encounter, outpost, visitor, raid, support.", keywords = "what kind faction encounter outpost visitor raid", run = Panel.focusKind },
            { id = "spawn.count", label = "Spawn count", tip = "How many NPCs to spawn, 1 to 8.", keywords = "how many number size", run = Panel.focusKind },
            { id = "spawn.stance", label = "Stance toward players", tip = "Friendly, neutral, careful or hostile.", keywords = "relation hostile friendly neutral careful", run = Panel.focusKind },
            { id = "spawn.where", label = "Where to spawn", tip = "Near you, clicked target, coordinates, marker or the encounter rule.", keywords = "location position coordinates marker target distance heading", run = Panel.focusKind },
            { id = "spawn.dormant", label = "Spawn dormant", tip = "Create the squad as a map marker without bodies.", keywords = "marker hydrate bodies", run = Panel.focusKind },
            { id = "spawn.gating", label = "Ignore funnel and day gating", tip = "Admin spawn without the natural day-window checks.", keywords = "funnel day window season", run = Panel.focusKind },
            { id = "spawn.seed", label = "Seed", tip = "Reproducible roster.", keywords = "random reproducible", run = Panel.focusKind },
            { id = "spawn.history", label = "Spawn history and undo", tip = "List of batches with per-batch undo.", keywords = "despawn remove batch", run = Panel.focusKind },
            { id = "spawn.presets", label = "Saved spawn presets", tip = "Save and load the whole form by name.", keywords = "save load preset", run = Panel.focusKind },
        } })
end

function Panel.focusKind(playerNum, window)
    if window ~= nil then
        window:clearSearch()
        window:showTab("spawn")
    end
end

Panel.register()

return Panel
