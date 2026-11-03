require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"
require "ProjectALife/Admin/ALifeAdminSettingsData"
require "ProjectALife/Records/ALifePresetValues"

ProjectALife = ProjectALife or {}

local Tab = {
    worldNames = { "Deserted", "Sparse", "Normal", "Crowded", "Stress test" },
    difficultyNames = { "Light", "Standard", "Hard", "Brutal" },
    built = nil,
}
ProjectALife.AdminSettingsTab = Tab

function Tab.sandbox()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(vars) == "table" and vars or {}
end

function Tab.title(row)
    if type(getTextOrNull) == "function" then
        local ok, text = pcall(getTextOrNull, "Sandbox_" .. row.tr)
        if ok and type(text) == "string" and text ~= "" and string.sub(text, 1, 8) ~= "Sandbox_" then return text end
    end
    return row.key
end

function Tab.same(left, right)
    if type(left) == "boolean" or type(right) == "boolean" then return left == right end
    local a, b = tonumber(left), tonumber(right)
    if a == nil or b == nil then return left == right end
    return math.abs(a - b) < 1e-6
end

function Tab.format(row, value)
    if value == nil then return "-" end
    if type(value) == "boolean" then return value and "on" or "off" end
    if row.kind == "double" then return string.format("%g", tonumber(value) or 0) end
    return tostring(value)
end

function Tab.presetValues(source)
    local result = ProjectALife.PresetValues.resolve(source)
    result.worldTier = math.floor(tonumber(source.Preset_World) or 3)
    result.difficultyTier = math.floor(tonumber(source.Preset_Difficulty) or 2)
    return result
end

function Tab.evaluate(row, source, presets)
    local raw = source[row.key]
    local current = raw
    if current == nil then current = row.default end
    local origin, effective = "default", current
    if presets.difficulty[row.key] ~= nil then
        effective = presets.difficulty[row.key]
        origin = "Difficulty preset: " .. tostring(Tab.difficultyNames[presets.difficultyTier] or presets.difficultyTier)
    elseif presets.world[row.key] ~= nil then
        effective = presets.world[row.key]
        origin = "World preset: " .. tostring(Tab.worldNames[presets.worldTier] or presets.worldTier)
    elseif not Tab.same(current, row.default) then
        origin = "host-set"
    end
    local changed = origin ~= "default" and not Tab.same(effective, row.default)
    if origin == "host-set" then changed = true end
    return { current = current, effective = effective, origin = origin, changed = changed }
end

function Tab.build(panel, window)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local actions = ProjectALife.AdminActions
    panel.playerNum, panel.window = window.playerNum, window
    panel.layout, panel.onReply, panel.autoRefresh = Tab.layout, Tab.onReply, Tab.autoRefresh
    panel.query, panel.page, panel.changedOnly = "", 0, false
    panel.filter = UI.entry(panel, 0, 0, 100, metrics.buttonH, "", false, "Search options...")
    panel.filter.onTextChangeFunction = Tab.onFilter
    panel.filter.target = panel
    panel.pages = UI.combo(panel, 0, 0, 100, metrics.buttonH, panel, Tab.onPage)
    local rows = { { "All pages", 0 } }
    for index, page in ipairs(ProjectALife.AdminSettingsData.pages) do rows[#rows + 1] = { page.title, index } end
    UI.fillCombo(panel.pages, rows, 0)
    panel.changed = UI.tick(panel, 0, 0, 160, metrics.buttonH - 6, "Changed only", false, panel, Tab.onChanged)
    panel.grid = UI.actionGrid(window, panel, actions.forTab("settings"), 2)
    panel.list = UI.List:new(0, 0, 100, 100, { target = panel, drawRow = Tab.drawRow, onPick = Tab.onPick,
        empty = "No option matches." })
    panel.list:initialise()
    panel:addChild(panel.list)
    panel.report = UI.Report:new(0, 0, 100, 100)
    panel.report:initialise()
    panel:addChild(panel.report)
    UI.addLabel(panel, "", 0, 0, UI.colors.muted)
    panel.header = panel.labels[1]
    Tab.refresh(window)
end

function Tab.onShow(panel, window)
    Tab.refresh(window)
end

function Tab.onFilter(panel, entry)
    panel.query = entry:getText()
    Tab.fill(panel)
end

function Tab.onPage(panel, combo)
    panel.page = ProjectALife.AdminUI.comboData(combo) or 0
    Tab.fill(panel)
end

function Tab.onChanged(panel, index, selected)
    panel.changedOnly = selected == true
    Tab.fill(panel)
end

function Tab.setFilter(window, text)
    local panel = window.tabPanels.settings
    if panel == nil then return end
    panel.query = tostring(text or "")
    panel.filter:setText(panel.query)
    Tab.fill(panel)
end

function Tab.refresh(window)
    local panel = window.tabPanels.settings
    if panel == nil then return end
    local source = Tab.sandbox()
    local presets = Tab.presetValues(source)
    panel.presets = presets
    local rows = {}
    for index, row in ipairs(ProjectALife.AdminSettingsData.rows) do
        local verdict = Tab.evaluate(row, source, presets)
        local page = ProjectALife.AdminSettingsData.pages[row.page]
        rows[#rows + 1] = { row = row, verdict = verdict, title = Tab.title(row), pageTitle = page and page.title or "",
            pageIndex = row.page, key = row.key }
    end
    Tab.built = rows
    Tab.fill(panel)
end

function Tab.matches(item, query)
    local words = ProjectALife.AdminActions.words(query)
    if #words == 0 then return true end
    local text = string.lower(item.key .. " " .. item.title .. " " .. item.pageTitle .. " " .. item.verdict.origin)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) == nil then return false end
    end
    return true
end

function Tab.fill(panel)
    local rows = {}
    local changedCount = 0
    for _, item in ipairs(Tab.built or {}) do
        if item.verdict.changed then changedCount = changedCount + 1 end
        local pageOk = panel.page == 0 or item.pageIndex == panel.page
        if pageOk and (not panel.changedOnly or item.verdict.changed) and Tab.matches(item, panel.query) then
            rows[#rows + 1] = { label = item.title, item = item }
        end
    end
    panel.list:setRows(rows)
    local presets = panel.presets or { world = {}, difficulty = {} }
    local source = Tab.sandbox()
    local worldTier = math.floor(tonumber(source.Preset_World) or 3)
    local difficultyTier = math.floor(tonumber(source.Preset_Difficulty) or 2)
    panel.header.text = tostring(#rows) .. " of " .. tostring(#(Tab.built or {})) .. " options shown, "
        .. tostring(changedCount) .. " changed. World preset " .. tostring(Tab.worldNames[worldTier] or worldTier)
        .. ", difficulty " .. tostring(Tab.difficultyNames[difficultyTier] or difficultyTier)
        .. ". Read only: change options in the sandbox menu or the server file."
    if panel.picked ~= nil then Tab.showDetail(panel, panel.picked) end
end

function Tab.drawRow(list, row, y)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local item = row.item
    local verdict = item.verdict
    local color = verdict.changed and colors.accent or colors.text
    list:drawText(UI.fit(item.title, list.width * 0.42), 8, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
    local value = Tab.format(item.row, verdict.effective)
    list:drawText(UI.fit(value, list.width * 0.12), list.width * 0.44, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
    list:drawText("def " .. UI.fit(Tab.format(item.row, item.row.default), list.width * 0.10), list.width * 0.57, y + 4,
        colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    local origin = verdict.origin
    if origin ~= "default" then
        local tint = origin == "host-set" and colors.warn or colors.good
        list:drawTextRight(UI.fit(origin, list.width * 0.30), list.width - 10, y + 4, tint.r, tint.g, tint.b, 1, UIFont.Small)
    end
end

function Tab.onPick(panel, row)
    panel.picked = row.item
    Tab.showDetail(panel, row.item)
end

function Tab.showDetail(panel, item)
    local UI = ProjectALife.AdminUI
    local lines = {}
    local verdict = item.verdict
    lines[#lines + 1] = UI.line(item.title .. "   [" .. item.key .. "]", "text")
    lines[#lines + 1] = UI.line("Page: " .. item.pageTitle, "muted")
    lines[#lines + 1] = UI.line("Saved value " .. Tab.format(item.row, verdict.current) .. "   effective " .. Tab.format(item.row, verdict.effective)
        .. "   default " .. Tab.format(item.row, item.row.default) .. "   origin " .. verdict.origin,
        verdict.changed and "warn" or "text")
    local range = ""
    if item.row.min ~= nil then range = "Range " .. tostring(item.row.min) .. " to " .. tostring(item.row.max) .. ".  " end
    lines[#lines + 1] = UI.line(range .. "Type " .. tostring(item.row.kind) .. ".", "muted")
    local tip = type(getTextOrNull) == "function" and getTextOrNull("Sandbox_" .. item.row.tr .. "_tooltip") or nil
    if type(tip) == "string" and tip ~= "" then
        for _, text in ipairs(UI.wrap(string.gsub(tip, "\n", " "), math.max(200, panel.report.width - 24))) do
            lines[#lines + 1] = UI.line(text, "muted")
        end
    end
    panel.report:setLines(lines)
end

function Tab.changedText(playerNum)
    local lines = {}
    for _, item in ipairs(Tab.built or {}) do
        if item.verdict.changed then
            lines[#lines + 1] = item.key .. " = " .. Tab.format(item.row, item.verdict.effective) .. "  (default "
                .. Tab.format(item.row, item.row.default) .. ", " .. item.verdict.origin .. ")"
        end
    end
    if #lines == 0 then return "All A-Life sandbox options are at their defaults." end
    return table.concat(lines, "\n")
end

function Tab.onReply() end
function Tab.autoRefresh() end

function Tab.layout(panel, width, height)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local gap = 6
    local filterW = math.floor(width * 0.26)
    UI.setBounds(panel.filter, 0, 0, filterW, metrics.buttonH)
    local pagesW = math.floor(width * 0.30)
    UI.setBounds(panel.pages, filterW + gap, 0, pagesW, metrics.buttonH)
    UI.setBounds(panel.changed, filterW + pagesW + gap * 2, 3, 140, metrics.buttonH - 6)
    local gridX = filterW + pagesW + 150 + gap * 3
    UI.placeGrid(panel.grid, gridX, 0, width - gridX)
    panel.header.x, panel.header.y = 4, metrics.buttonH + 6
    local listY = metrics.buttonH + metrics.fontH + 12
    local detailH = metrics.fontH * 6 + 16
    UI.setBounds(panel.list, 0, listY, width, height - listY - detailH - gap)
    UI.setBounds(panel.report, 0, height - detailH, width, detailH)
end

function Tab.register()
    local tab = ProjectALife.AdminActions.tab("settings")
    ProjectALife.AdminConsole.addTab({ id = "settings", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        build = Tab.build, onShow = Tab.onShow,
        controls = {
            { id = "settings.browser", label = "Sandbox options browser", tip = "Every A-Life option with its value, default and preset origin.",
                keywords = "sandbox options values defaults preset origin changed", run = Tab.openFromSearch },
        } })
end

function Tab.openFromSearch(playerNum, window)
    if window == nil then return end
    window:clearSearch()
    window:showTab("settings")
end

Tab.register()

return Tab
