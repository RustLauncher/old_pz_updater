require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"

ProjectALife = ProjectALife or {}

local Tab = {}
ProjectALife.AdminPopulationTab = Tab

function Tab.build(panel, window)
    local UI = ProjectALife.AdminUI
    panel.playerNum, panel.window = window.playerNum, window
    panel.layout, panel.onReply, panel.autoRefresh = Tab.layout, Tab.onReply, Tab.autoRefresh
    panel.grid = UI.actionGrid(window, panel, ProjectALife.AdminActions.forTab("population"), 1)
    panel.report = UI.Report:new(0, 0, 100, 100)
    panel.report:initialise()
    panel:addChild(panel.report)
    panel.nearest = UI.List:new(0, 0, 100, 100, { target = panel, drawRow = Tab.drawNearest,
        empty = "No NPC records yet. Press Refresh census." })
    panel.nearest:initialise()
    panel:addChild(panel.nearest)
    UI.addLabel(panel, "NEAREST NPCS", 0, 0, UI.colors.accent)
    UI.addLabel(panel, "CENSUS", 0, 0, UI.colors.accent)
    panel.labels[1].heading, panel.labels[2].heading = true, true
    Tab.fill(panel)
end

function Tab.onShow(panel, window)
    ProjectALife.AdminConsole.requestSnapshot(window.playerNum, "population", true)
    Tab.fill(panel)
end

function Tab.autoRefresh(panel)
    ProjectALife.AdminConsole.requestSnapshot(panel.playerNum, "population", false)
end

function Tab.onReply(panel, command, arguments)
    if command == "adminSnapshotResult" and arguments.ok == true and arguments.population ~= nil then Tab.fill(panel) end
end

local function joined(map, order)
    local parts = {}
    for _, key in ipairs(order) do
        if map[key] ~= nil then parts[#parts + 1] = tostring(key) .. " " .. tostring(map[key]) end
    end
    return table.concat(parts, "  |  ")
end

function Tab.sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if map[left] ~= map[right] then return map[left] > map[right] end
        return tostring(left) < tostring(right)
    end)
    return keys
end

function Tab.lines(snapshot)
    local UI = ProjectALife.AdminUI
    local lines = {}
    local population = snapshot ~= nil and snapshot.population or nil
    if population == nil then
        lines[1] = UI.line("No census yet. The server answers a few moments after the tab opens.", "muted")
        return lines
    end
    local life = population.lifecycle or {}
    lines[#lines + 1] = UI.line("NPC records " .. tostring(population.total) .. "   active " .. tostring(life.active or 0)
        .. "   dormant " .. tostring(life.dormant or 0) .. "   spawning " .. tostring(life.spawning or 0)
        .. "   dead " .. tostring(life.dead or 0) .. "   bodies " .. tostring(population.shells), "text")
    local states = population.byState or {}
    lines[#lines + 1] = UI.line("Squads " .. tostring(population.squads) .. " (solo " .. tostring(population.solo) .. ")   active "
        .. tostring(states.active or 0) .. "   dormant " .. tostring(states.dormant or 0), "text")
    local funnel = population.funnel
    if funnel ~= nil then
        lines[#lines + 1] = UI.line("Funnel stage " .. tostring(funnel.stage) .. " " .. tostring(funnel.name or "") .. "   day "
            .. tostring(funnel.day) .. " (real day " .. tostring(funnel.today) .. ", offset " .. tostring(funnel.offset) .. ")"
            .. (funnel.enabled and "" or "   FUNNEL OFF") .. (funnel.overridden and "   PREVIEW" or ""),
            funnel.overridden and "warn" or "text")
    end
    local classes = population.byClass or {}
    lines[#lines + 1] = UI.line("By class: " .. joined(classes, Tab.sortedKeys(classes)), "muted")
    local factions = {}
    for _, row in ipairs(population.byFaction or {}) do factions[#factions + 1] = tostring(row.id) .. " " .. tostring(row.squads) end
    lines[#lines + 1] = UI.line("Top factions: " .. table.concat(factions, "  |  "), "muted")
    local holds = population.holds or {}
    local why = joined(holds, Tab.sortedKeys(holds))
    if why == "" then why = "none (no dormant NPC is waiting)" end
    lines[#lines + 1] = UI.line("Why markers have no bodies (" .. tostring(population.holdCount) .. " dormant checked): " .. why,
        (life.dormant or 0) > 0 and "warn" or "muted")
    local counters = {}
    for _, row in ipairs(population.counters or {}) do
        if row[2] ~= 0 then counters[#counters + 1] = tostring(row[1]) .. "=" .. tostring(row[2]) end
    end
    lines[#lines + 1] = UI.line("Hydrate and hold counters: " .. (#counters > 0 and table.concat(counters, " ") or "all zero"), "muted")
    return lines
end

function Tab.fill(panel)
    local snapshot = ProjectALife.AdminConsole.snapshot
    panel.report:setLines(Tab.lines(snapshot))
    local rows = {}
    local population = snapshot ~= nil and snapshot.population or nil
    for _, row in ipairs(population ~= nil and population.nearest or {}) do
        rows[#rows + 1] = { label = tostring(row.name), row = row }
    end
    panel.nearest:setRows(rows, true)
end

function Tab.drawNearest(list, item, y)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local row = item.row
    local stateColor = row.lifecycle == "active" and colors.good or colors.muted
    list:drawText(UI.fit(item.label, list.width * 0.30), 8, y + 4, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
    list:drawText(UI.fit(tostring(row.factionId), list.width * 0.26), list.width * 0.32, y + 4, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    list:drawText(tostring(row.lifecycle) .. "/" .. tostring(row.activity), list.width * 0.60, y + 4, stateColor.r, stateColor.g, stateColor.b, 1, UIFont.Small)
    list:drawTextRight(tostring(row.distance) .. " tiles  " .. tostring(row.x) .. "," .. tostring(row.y), list.width - 10, y + 4,
        colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
end

function Tab.layout(panel, width, height)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local leftW = math.floor(width * 0.34)
    local gap = 8
    UI.placeGrid(panel.grid, 0, 0, leftW)
    local x = leftW + gap
    local w = width - x
    local reportH = math.floor(height * 0.46)
    panel.labels[2].x, panel.labels[2].y = x + 4, 2
    UI.setBounds(panel.report, x, metrics.fontH + 6, w, reportH - metrics.fontH - 6)
    panel.labels[1].x, panel.labels[1].y = x + 4, reportH + 2
    UI.setBounds(panel.nearest, x, reportH + metrics.fontH + 6, w, height - reportH - metrics.fontH - 6)
end

function Tab.register()
    local tab = ProjectALife.AdminActions.tab("population")
    ProjectALife.AdminConsole.addTab({ id = "population", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        build = Tab.build, onShow = Tab.onShow })
end

Tab.register()

return Tab
