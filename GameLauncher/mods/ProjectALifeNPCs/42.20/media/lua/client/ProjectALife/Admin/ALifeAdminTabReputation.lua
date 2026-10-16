require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"

ProjectALife = ProjectALife or {}

local Tab = {}
ProjectALife.AdminReputationTab = Tab

function Tab.build(panel, window)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local actions = ProjectALife.AdminActions
    panel.playerNum, panel.window = window.playerNum, window
    panel.layout, panel.onReply, panel.autoRefresh = Tab.layout, Tab.onReply, Tab.autoRefresh
    panel.query = ""
    local adjust, refresh = {}, nil
    for _, spec in ipairs(actions.forTab("reputation")) do
        if spec.id == "rep.view" then refresh = spec else adjust[#adjust + 1] = spec end
    end
    panel.refreshGrid = UI.actionGrid(window, panel, { refresh }, 1)
    panel.adjustGrid = UI.actionGrid(window, panel, adjust, 4)
    panel.report = UI.Report:new(0, 0, 100, 100)
    panel.report:initialise()
    panel:addChild(panel.report)
    panel.filter = UI.entry(panel, 0, 0, 100, metrics.buttonH, "", false, "Find a faction...")
    panel.filter.onTextChangeFunction = Tab.onFilter
    panel.filter.target = panel
    panel.list = UI.List:new(0, 0, 100, 100, { target = panel, drawRow = Tab.drawRow, onPick = Tab.onPick,
        empty = "Loading factions..." })
    panel.list:initialise()
    panel:addChild(panel.list)
    panel.hostile = UI.button(panel, 0, 0, 100, metrics.buttonH, "Make hostile", panel, Tab.onHostile, true)
    panel.hostile.tooltip = "Risk: caution. Sets this faction to hostile toward you with the cause 'admin'. Reversible with Back to baseline."
    panel.baseline = UI.button(panel, 0, 0, 100, metrics.buttonH, "Back to baseline", panel, Tab.onBaseline, false)
    panel.baseline.tooltip = "Risk: safe. Removes the admin or earned override so the faction's own stance applies again."
    UI.addLabel(panel, "YOUR REPUTATION", 0, 0, UI.colors.accent).heading = true
    UI.addLabel(panel, "FACTIONS: pick one, then Make hostile or Back to baseline", 0, 0, UI.colors.accent).heading = true
    UI.addLabel(panel, "ADJUST YOUR SCORE", 0, 0, UI.colors.accent).heading = true
    Tab.fill(panel)
end

function Tab.onShow(panel, window)
    local console = ProjectALife.AdminConsole
    console.send(window.playerNum, "adminRepView", {})
    console.requestFactions(window.playerNum, false)
    Tab.fill(panel)
end

function Tab.autoRefresh(panel)
    ProjectALife.AdminConsole.send(panel.playerNum, "adminRepView", {})
end

function Tab.onReply(panel, command, arguments)
    if command == "adminRepViewResult" or command == "adminFactionIndexResult" or command == "debugRepAdjustResult" then
        if command == "debugRepAdjustResult" then ProjectALife.AdminConsole.send(panel.playerNum, "adminRepView", {}) end
        Tab.fill(panel)
    elseif command == "adminRepFactionResult" then
        ProjectALife.AdminConsole.send(panel.playerNum, "adminRepView", {})
        ProjectALife.AdminConsole.log(panel.playerNum, arguments.ok and ("Faction " .. tostring(arguments.factionId) .. " set to " .. tostring(arguments.status))
            or ("Reputation change refused: " .. tostring(arguments.text or arguments.reason)), arguments.ok and "info" or "error")
    end
end

function Tab.statusMap(view)
    local map = {}
    for _, row in ipairs(view ~= nil and view.relations or {}) do map[row.factionId] = row end
    return map
end

function Tab.onFilter(panel, entry)
    panel.query = entry:getText()
    Tab.fill(panel)
end

function Tab.fill(panel)
    local UI = ProjectALife.AdminUI
    local console = ProjectALife.AdminConsole
    local view = console.repView
    local lines = {}
    if view == nil then
        lines[1] = UI.line("No reputation data yet.", "muted")
    else
        local personal = view.personal
        if personal ~= nil then
            lines[#lines + 1] = UI.line("Personal score " .. tostring(personal.score) .. "   level " .. tostring(personal.level)
                .. "   band " .. tostring(personal.band) .. "   life " .. tostring(personal.life), "text")
        else
            lines[#lines + 1] = UI.line("Personal reputation is switched off in the sandbox settings.", "warn")
        end
        lines[#lines + 1] = UI.line("Profession " .. tostring(view.profession ~= "" and view.profession or "-")
            .. "   faction overrides " .. tostring(#(view.relations or {})), "muted")
    end
    panel.report:setLines(lines)
    local status = Tab.statusMap(view)
    local rows = {}
    for _, faction in ipairs(console.factions.rows) do
        if ProjectALife.SpawnerBrowser.matches(faction, panel.query or "") then
            local override = status[faction.id]
            rows[#rows + 1] = { id = faction.id, label = faction.name, baseline = faction.relation,
                status = override and override.status or nil, cause = override and override.cause or nil }
        end
    end
    panel.list:setRows(rows, true)
    panel.list.empty = #console.factions.rows == 0 and "Loading factions..." or "No faction matches."
end

function Tab.drawRow(list, row, y)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    list:drawText(UI.fit(row.label, list.width * 0.42), 8, y + 4, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
    list:drawText("default " .. tostring(row.baseline or "?"), list.width * 0.44, y + 4, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    if row.status ~= nil then
        local color = row.status == "hostile" and colors.bad or colors.warn
        list:drawTextRight(tostring(row.status) .. " (" .. tostring(row.cause) .. ")", list.width - 10, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
    end
end

function Tab.onPick(panel, row)
    panel.picked = row.id
end

function Tab.send(panel, status)
    local console = ProjectALife.AdminConsole
    if panel.picked == nil then
        console.log(panel.playerNum, "Pick a faction in the list first.", "warning")
        return
    end
    console.send(panel.playerNum, "adminRepFaction", { factionId = panel.picked, status = status })
end

function Tab.onHostile(panel)
    Tab.send(panel, "hostile")
end

function Tab.onBaseline(panel)
    Tab.send(panel, "baseline")
end

function Tab.layout(panel, width, height)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local gap = 8
    local halfW = math.floor(width * 0.5)
    panel.labels[1].x, panel.labels[1].y = 4, 2
    UI.setBounds(panel.report, 0, metrics.fontH + 6, halfW - gap, metrics.rowH * 3)
    local y = metrics.fontH + 6 + metrics.rowH * 3 + 8
    panel.labels[3].x, panel.labels[3].y = 4, y
    y = y + metrics.fontH + 4
    UI.placeGrid(panel.adjustGrid, 0, y, halfW - gap)
    local used = y + (metrics.buttonH + 4) * 2 + 6
    UI.placeGrid(panel.refreshGrid, 0, used, halfW - gap)
    local x = halfW
    local w = width - x
    panel.labels[2].x, panel.labels[2].y = x + 4, 2
    UI.setBounds(panel.filter, x, metrics.fontH + 6, w, metrics.buttonH)
    local listY = metrics.fontH + 6 + metrics.buttonH + 4
    local listH = height - listY - metrics.buttonH - 8
    UI.setBounds(panel.list, x, listY, w, listH)
    UI.setBounds(panel.hostile, x, listY + listH + 4, math.floor(w / 2) - 2, metrics.buttonH)
    UI.setBounds(panel.baseline, x + math.floor(w / 2) + 2, listY + listH + 4, w - math.floor(w / 2) - 2, metrics.buttonH)
end

function Tab.register()
    local tab = ProjectALife.AdminActions.tab("reputation")
    ProjectALife.AdminConsole.addTab({ id = "reputation", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        build = Tab.build, onShow = Tab.onShow })
end

Tab.register()

return Tab
