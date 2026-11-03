require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"

ProjectALife = ProjectALife or {}

local Tab = {}
ProjectALife.AdminWorldTab = Tab

Tab.custom = { ["world.visit.trigger"] = true }

function Tab.isFunnel(spec)
    return string.sub(spec.id, 1, 13) == "world.funnel."
end

function Tab.build(panel, window)
    local UI = ProjectALife.AdminUI
    local actions = ProjectALife.AdminActions
    panel.playerNum, panel.window = window.playerNum, window
    panel.layout, panel.onReply, panel.autoRefresh = Tab.layout, Tab.onReply, Tab.autoRefresh
    local general, funnel = {}, {}
    for _, spec in ipairs(actions.forTab("world")) do
        if Tab.isFunnel(spec) then funnel[#funnel + 1] = spec
        elseif not Tab.custom[spec.id] then general[#general + 1] = spec end
    end
    panel.grid = UI.actionGrid(window, panel, general, 2)
    panel.funnelGrid = UI.actionGrid(window, panel, funnel, 3)
    panel.visit = UI.actionGrid(window, panel, { actions.get("world.visit.trigger") }, 1)
    panel.report = UI.Report:new(0, 0, 100, 100)
    panel.report:initialise()
    panel:addChild(panel.report)
    UI.addLabel(panel, "WORLD STATE", 0, 0, UI.colors.accent).heading = true
    UI.addLabel(panel, "FORCE A BASE VISIT", 0, 0, UI.colors.accent).heading = true
    UI.addLabel(panel, "FUNNEL STAGE PREVIEW (session only, the game clock is not touched)", 0, 0, UI.colors.accent).heading = true
    panel.visitGroup = UI.combo(panel, 0, 0, 100, UI.metrics().buttonH, panel, Tab.onGroup)
    panel.visitEvent = UI.combo(panel, 0, 0, 100, UI.metrics().buttonH, panel, Tab.onEvent)
    Tab.fillVisit(panel)
    Tab.fill(panel)
end

function Tab.fillVisit(panel)
    local UI = ProjectALife.AdminUI
    local groups, order, byGroup = {}, {}, {}
    for _, entry in ipairs(ProjectALife.AdminConsole.visitEvents()) do
        if byGroup[entry.group] == nil then
            byGroup[entry.group] = {}
            order[#order + 1] = entry.group
        end
        byGroup[entry.group][#byGroup[entry.group] + 1] = { entry.label, entry.id }
    end
    panel.byGroup = byGroup
    for _, name in ipairs(order) do groups[#groups + 1] = { name .. " (" .. tostring(#byGroup[name]) .. ")", name } end
    if #groups == 0 then groups[1] = { "No visit types loaded", "" } end
    UI.fillCombo(panel.visitGroup, groups, nil)
    Tab.onGroup(panel, panel.visitGroup)
end

function Tab.onGroup(panel, combo)
    local UI = ProjectALife.AdminUI
    local name = UI.comboData(combo)
    local rows = panel.byGroup[name] or { { "-", "" } }
    UI.fillCombo(panel.visitEvent, rows, ProjectALife.AdminConsole.player(panel.playerNum).visitEvent)
    Tab.onEvent(panel, panel.visitEvent)
end

function Tab.onEvent(panel, combo)
    local id = ProjectALife.AdminUI.comboData(combo)
    if id ~= nil and id ~= "" then ProjectALife.AdminConsole.player(panel.playerNum).visitEvent = id end
end

function Tab.onShow(panel, window)
    ProjectALife.AdminConsole.requestSnapshot(window.playerNum, "world", true)
    Tab.fill(panel)
end

function Tab.autoRefresh(panel)
    ProjectALife.AdminConsole.requestSnapshot(panel.playerNum, "world", false)
end

function Tab.onReply(panel, command, arguments)
    if (command == "adminSnapshotResult" and arguments.world ~= nil) or command == "adminFunnelResult" then Tab.fill(panel) end
end

function Tab.lines()
    local UI = ProjectALife.AdminUI
    local console = ProjectALife.AdminConsole
    local snapshot = console.snapshot
    local world = snapshot ~= nil and snapshot.world or nil
    local lines = {}
    if world == nil then
        lines[1] = UI.line("No world state yet. The server answers a few moments after the tab opens.", "muted")
        return lines
    end
    lines[#lines + 1] = UI.line("World day " .. tostring(world.day) .. "   hour " .. tostring(world.hour)
        .. (world.date ~= nil and ("   date " .. tostring(world.date.month) .. "/" .. tostring(world.date.day)) or ""), "text")
    local weather = world.weather
    if weather ~= nil then
        lines[#lines + 1] = UI.line("Weather: " .. tostring(weather.temperature) .. " C   " .. (weather.raining and "raining" or "dry")
            .. " (rain " .. tostring(weather.rain) .. ")   daylight " .. tostring(weather.daylight), "muted")
    end
    local funnel = console.funnel or world.funnel
    if funnel ~= nil then
        lines[#lines + 1] = UI.line("Funnel stage " .. tostring(funnel.stage) .. " " .. tostring(funnel.name or "") .. "   day "
            .. tostring(funnel.day) .. "   offset " .. tostring(funnel.offset)
            .. (funnel.overridden and "   (PREVIEW ACTIVE: press Back to real day)" or "")
            .. (funnel.enabled == false and "   (funnel disabled in sandbox)" or ""), funnel.overridden and "warn" or "text")
    end
    local raid = world.raid
    if raid ~= nil then
        lines[#lines + 1] = UI.line(raid.active and ("RAID ACTIVE " .. tostring(raid.raidId) .. " wave " .. tostring(raid.wave) .. "/"
            .. tostring(raid.wavesTotal) .. " " .. tostring(raid.factionId)) or "No raid running", raid.active and "bad" or "muted")
    end
    local outposts = world.outposts
    if outposts ~= nil then
        lines[#lines + 1] = UI.line("Outposts: rolls " .. tostring(outposts.rolls) .. "  proposed " .. tostring(outposts.proposed)
            .. "  built " .. tostring(outposts.built) .. "  garrisoned " .. tostring(outposts.garrisoned)
            .. "  expired " .. tostring(outposts.expired) .. "  refused " .. tostring(outposts.refused), "text")
        local deferred = {}
        for _, row in ipairs(outposts.deferred or {}) do deferred[#deferred + 1] = tostring(row[1]) .. " x" .. tostring(row[2]) end
        if #deferred > 0 then lines[#lines + 1] = UI.line("Why crews wait or builds are refused: " .. table.concat(deferred, "  |  "), "warn") end
        for _, site in ipairs(outposts.sites or {}) do
            lines[#lines + 1] = UI.line("Site " .. tostring(site.id) .. "  " .. tostring(site.preset) .. "  " .. tostring(site.state)
                .. "  @" .. tostring(site.x) .. "," .. tostring(site.y) .. "  " .. tostring(site.factionId), "muted", 12)
        end
    end
    if world.meta ~= nil then
        lines[#lines + 1] = UI.line("Meta events fired " .. tostring(world.meta.events) .. (world.meta.pending and "   one is pending" or ""), "muted")
    end
    return lines
end

function Tab.fill(panel)
    panel.report:setLines(Tab.lines())
end

function Tab.layout(panel, width, height)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local leftW = math.floor(width * 0.44)
    local gap = 8
    local used = UI.placeGrid(panel.grid, 0, 0, leftW)
    local x = leftW + gap
    local w = width - x
    panel.labels[1].x, panel.labels[1].y = x + 4, 2
    local reportH = math.floor(height * 0.40)
    UI.setBounds(panel.report, x, metrics.fontH + 6, w, reportH)
    local y = metrics.fontH + 6 + reportH + 8
    panel.labels[2].x, panel.labels[2].y = x + 4, y
    y = y + metrics.fontH + 4
    local half = math.floor((w - gap) / 2)
    UI.setBounds(panel.visitGroup, x, y, half, metrics.buttonH)
    UI.setBounds(panel.visitEvent, x + half + gap, y, w - half - gap, metrics.buttonH)
    y = y + metrics.buttonH + 4
    UI.placeGrid(panel.visit, x, y, w)
    y = y + metrics.buttonH + 12
    panel.labels[3].x, panel.labels[3].y = x + 4, y
    y = y + metrics.fontH + 4
    UI.placeGrid(panel.funnelGrid, x, y, w)
    return used
end

function Tab.register()
    local tab = ProjectALife.AdminActions.tab("world")
    ProjectALife.AdminConsole.addTab({ id = "world", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        build = Tab.build, onShow = Tab.onShow })
end

Tab.register()

return Tab
