require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"

ProjectALife = ProjectALife or {}

local Tab = {}
ProjectALife.AdminDiagnosticsTab = Tab

function Tab.build(panel, window)
    local UI = ProjectALife.AdminUI
    panel.playerNum, panel.window = window.playerNum, window
    panel.layout, panel.onReply, panel.autoRefresh = Tab.layout, Tab.onReply, Tab.autoRefresh
    panel.grid = UI.actionGrid(window, panel, ProjectALife.AdminActions.forTab("diagnostics"), 1)
    panel.report = UI.Report:new(0, 0, 100, 100)
    panel.report:initialise()
    panel:addChild(panel.report)
    panel.modules = UI.List:new(0, 0, 100, 100, { target = panel, drawRow = Tab.drawModule,
        empty = "No module table yet. Press Refresh diagnostics." })
    panel.modules:initialise()
    panel:addChild(panel.modules)
    UI.addLabel(panel, "STATE", 0, 0, UI.colors.accent).heading = true
    UI.addLabel(panel, "MODULES (enabled / primary)", 0, 0, UI.colors.accent).heading = true
    UI.addLabel(panel, "", 0, 0, UI.colors.muted)
    panel.status = panel.labels[3]
    Tab.fill(panel)
end

function Tab.onShow(panel, window)
    ProjectALife.AdminConsole.requestSnapshot(window.playerNum, "diagnostics", true)
    Tab.fill(panel)
end

function Tab.autoRefresh(panel)
    ProjectALife.AdminConsole.requestSnapshot(panel.playerNum, "diagnostics", false)
end

function Tab.onReply(panel, command, arguments)
    if command == "adminSnapshotResult" and arguments.diagnostics ~= nil then Tab.fill(panel) end
end

function Tab.lines(snapshot)
    local UI = ProjectALife.AdminUI
    local prefs = ProjectALife.MenuPrefs
    local lines = {}
    lines[#lines + 1] = UI.line("Client: diagnostics " .. tostring(prefs ~= nil and prefs.diagnostics() or false)
        .. "   flight recorder " .. tostring(prefs ~= nil and prefs.recorder() or false)
        .. "   console log " .. tostring(ProjectALife.AdminPrefs.get("verbosity")), "text")
    local data = snapshot ~= nil and snapshot.diagnostics or nil
    if data == nil then
        lines[#lines + 1] = UI.line("No server diagnostics yet. Press Refresh diagnostics.", "muted")
        return lines
    end
    lines[#lines + 1] = UI.line("Build " .. tostring(snapshot.build or "unknown") .. "   server recorder " .. tostring(data.recorder)
        .. "   server AI trace log " .. (data.aiTrace == false and "off" or "on"), "text")
    local runtime = data.runtime or {}
    lines[#lines + 1] = UI.line("Runtime ticks " .. tostring(runtime.ticks) .. "  overruns " .. tostring(runtime.overruns)
        .. "  worst tick " .. tostring(runtime.worstTickMs) .. " ms  last tick " .. tostring(runtime.lastTickMs)
        .. " ms  faults " .. tostring(runtime.faults) .. "  last fault " .. tostring(runtime.lastFault or "-"),
        (tonumber(runtime.faults) or 0) > 0 and "bad" or "text")
    if data.lastError ~= nil then lines[#lines + 1] = UI.line("Module registry lastError: " .. tostring(data.lastError), "bad") end
    lines[#lines + 1] = UI.line("PERFORMANCE (slowest subsystems, ms: last / max / avg / calls)", "warn")
    for _, row in ipairs(data.timings or {}) do
        lines[#lines + 1] = UI.line(tostring(row.name) .. "  " .. tostring(row.lastMs) .. " / " .. tostring(row.maxMs) .. " / "
            .. tostring(row.avgMs) .. " / " .. tostring(row.calls), "text", 12)
    end
    lines[#lines + 1] = UI.line("LAST ERRORS (" .. tostring(#(data.errors or {})) .. ")", (#(data.errors or {}) > 0) and "bad" or "muted")
    for _, row in ipairs(data.errors or {}) do
        lines[#lines + 1] = UI.line(tostring(row.category) .. ": " .. tostring(row.error or "-") .. " " .. tostring(row.uid or ""), "bad", 12)
    end
    local spawn = data.adminSpawn
    if spawn ~= nil then
        lines[#lines + 1] = UI.line("Admin spawns: requests " .. tostring(spawn.requests) .. "  accepted " .. tostring(spawn.accepted)
            .. "  failed " .. tostring(spawn.failed) .. "  undone " .. tostring(spawn.undone) .. "  previews " .. tostring(spawn.previews), "muted")
    end
    return lines
end

function Tab.fill(panel)
    local snapshot = ProjectALife.AdminConsole.snapshot
    panel.report:setLines(Tab.lines(snapshot))
    local rows = {}
    local data = snapshot ~= nil and snapshot.diagnostics or nil
    for _, module in ipairs(data ~= nil and data.modules or {}) do
        rows[#rows + 1] = { label = tostring(module.id), module = module }
    end
    panel.modules:setRows(rows, true)
    panel.status.text = "Module table: " .. tostring(#rows) .. " modules"
end

function Tab.drawModule(list, item, y)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local module = item.module
    local color = module.enabled and colors.text or colors.muted
    list:drawText(UI.fit(item.label, list.width * 0.40), 8, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
    list:drawText(UI.fit(tostring(module.kind), list.width * 0.22), list.width * 0.42, y + 4, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    local stateColor = module.enabled and colors.good or colors.bad
    list:drawText(module.enabled and "enabled" or "OFF", list.width * 0.66, y + 4, stateColor.r, stateColor.g, stateColor.b, 1, UIFont.Small)
    if module.primary then list:drawText("primary", list.width * 0.82, y + 4, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small) end
end

function Tab.layout(panel, width, height)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local leftW = math.floor(width * 0.30)
    local gap = 8
    UI.placeGrid(panel.grid, 0, 0, leftW)
    local x = leftW + gap
    local w = width - x
    panel.labels[1].x, panel.labels[1].y = x + 4, 2
    local reportH = math.floor(height * 0.55)
    UI.setBounds(panel.report, x, metrics.fontH + 6, w, reportH)
    panel.labels[2].x, panel.labels[2].y = x + 4, reportH + metrics.fontH + 10
    panel.status.x, panel.status.y = x + w - 220, reportH + metrics.fontH + 10
    local listY = reportH + metrics.fontH * 2 + 14
    UI.setBounds(panel.modules, x, listY, w, height - listY)
end

function Tab.register()
    local tab = ProjectALife.AdminActions.tab("diagnostics")
    ProjectALife.AdminConsole.addTab({ id = "diagnostics", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        build = Tab.build, onShow = Tab.onShow })
end

Tab.register()

return Tab
