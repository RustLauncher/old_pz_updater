require "ISUI/ISCollapsableWindow"
require "ISUI/ISModalDialog"
require "ProjectALife/Admin/ALifeAdminUI"
require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminClientActions"

ProjectALife = ProjectALife or {}

local Window = ISCollapsableWindow:derive("ALifeAdminConsoleWindow")
local Factory = { class = Window }
ProjectALife.AdminWindow = Factory

Window.toolbarSlots = 8

function Factory.screenBounds(playerNum)
    local core = getCore()
    local left, top, width, height = 0, 0, core:getScreenWidth(), core:getScreenHeight()
    if type(getPlayerScreenLeft) == "function" and type(getPlayerScreenWidth) == "function" then
        local w = getPlayerScreenWidth(playerNum)
        local h = getPlayerScreenHeight(playerNum)
        if tonumber(w) ~= nil and tonumber(h) ~= nil and w > 0 and h > 0 then
            left, top, width, height = getPlayerScreenLeft(playerNum), getPlayerScreenTop(playerNum), w, h
        end
    end
    return left, top, width, height
end

function Factory.create(playerNum)
    local metrics = ProjectALife.AdminUI.metrics()
    local left, top, screenW, screenH = Factory.screenBounds(playerNum)
    local width = math.max(820, math.min(screenW - 24, metrics.charW * 118))
    local height = math.max(600, math.min(screenH - 24, metrics.rowH * 27 + 120))
    width, height = math.min(width, screenW), math.min(height, screenH)
    local window = Window:new(left + math.floor((screenW - width) / 2), top + math.floor((screenH - height) / 2), width, height)
    window.playerNum = playerNum
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:finishOpen()
    return window
end

function Window:new(x, y, width, height)
    local window = ISCollapsableWindow.new(self, x, y, width, height)
    local UI = ProjectALife.AdminUI
    window.resizable = true
    window.minimumWidth = 820
    window.minimumHeight = 600
    window.backgroundColor = UI.copy(UI.colors.panel)
    window.borderColor = UI.copy(UI.colors.accent)
    window.tabPanels, window.tabButtons, window.actionButtons, window.toolbar = {}, {}, {}, {}
    window.activeTab = nil
    window.query = ""
    window.statusText, window.statusSeverity = "", "info"
    window.laidWidth, window.laidHeight = nil, nil
    window.lastRefreshMs = 0
    window:setTitle("Project A-Life  -  Admin Console")
    return window
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    self.searchEntry = UI.entry(self, 0, 0, 200, metrics.buttonH, "", false, "Search every control...")
    self.searchEntry.onTextChangeFunction = Window.onSearchChanged
    self.searchEntry.target = self
    if type(self.searchEntry.setTooltip) == "function" then
        self.searchEntry:setTooltip("Type to find a control in any tab: spawn, census, raid, reputation, dump, option. Click a result to run it.")
    end
    for slot = 1, Window.toolbarSlots do
        local button = UI.button(self, 0, 0, 80, metrics.buttonH, "", self, UI.onAction, false)
        button:setVisible(false)
        self.toolbar[slot] = button
    end
    self.classicButton = UI.button(self, 0, 0, 90, metrics.buttonH, "Classic", self, Window.onClassic, false)
    self.classicButton.tooltip = "Opens the old debug spawner window. It stays available until this console is proven in game."
    self.results = UI.List:new(0, 0, 100, 100, { target = self, onPick = Window.onResultPicked, empty = "No control matches." })
    self.results:initialise()
    self.results:setVisible(false)
    self:addChild(self.results)
    self:buildTabButtons()
    self:refreshToolbar()
end

function Window:buildTabButtons()
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    for id, button in pairs(self.tabButtons) do
        self:removeChild(button)
        self.tabButtons[id] = nil
    end
    self.tabOrder = {}
    for _, tab in ipairs(ProjectALife.AdminConsole.tabs) do
        local button = UI.button(self, 0, 0, UI.measure(tab.title) + 24, metrics.buttonH, tab.title, self, Window.onTabButton, false)
        button.tabId = tab.id
        button.tooltip = tab.tip ~= "" and tab.tip or nil
        self.tabButtons[tab.id] = button
        self.tabOrder[#self.tabOrder + 1] = tab.id
    end
end

function Window.onTabButton(window, button)
    window:showTab(button.tabId)
end

function Window.onClassic(window, button)
    ProjectALife.AdminConsole.run("spawn.classic", window.playerNum, window)
end

function Window.onSearchChanged(window, entry)
    window:setQuery(entry:getText())
end

function Window.onResultPicked(window, row)
    window:pickResult(row)
end

function Window:pickResult(row)
    local console = ProjectALife.AdminConsole
    if row.kind == "action" then
        console.run(row.id, self.playerNum, self)
    elseif row.kind == "control" and type(row.run) == "function" then
        row.run(self.playerNum, self)
    else
        self:clearSearch()
        self:showTab(row.tab)
        if row.kind == "settings" and ProjectALife.AdminSettingsTab ~= nil then
            ProjectALife.AdminSettingsTab.setFilter(self, self.lastQuery or "")
        elseif row.kind == "factions" and ProjectALife.SpawnerPanel ~= nil then
            ProjectALife.SpawnerPanel.setFilter(self, self.lastQuery or "")
        end
    end
end

function Window:clearSearch()
    self.query = ""
    if self.searchEntry ~= nil then self.searchEntry:setText("") end
    self.results:setVisible(false)
    if self.activeTab ~= nil and self.tabPanels[self.activeTab] ~= nil then self.tabPanels[self.activeTab]:setVisible(true) end
end

function Window:setQuery(text)
    local console = ProjectALife.AdminConsole
    text = tostring(text or "")
    if text == self.query then return end
    self.query = text
    if string.find(text, "%S") == nil then
        self.results:setVisible(false)
        if self.activeTab ~= nil and self.tabPanels[self.activeTab] ~= nil then self.tabPanels[self.activeTab]:setVisible(true) end
        return
    end
    self.lastQuery = text
    local rows = console.search(text)
    local UI = ProjectALife.AdminUI
    for _, row in ipairs(rows) do
        local tab = ProjectALife.AdminActions.tab(row.tab) or console.tab(row.tab)
        row.tabTitle = tab ~= nil and (tab.title or row.tab) or row.tab
    end
    self.results.drawRowFn = Window.drawResult
    self.results:setRows(rows)
    self.results:setVisible(true)
    if self.activeTab ~= nil and self.tabPanels[self.activeTab] ~= nil then self.tabPanels[self.activeTab]:setVisible(false) end
    return UI ~= nil
end

function Window.drawResult(list, row, y, selected)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local risk = colors[UI.riskColors[row.risk] or "good"]
    list:drawRect(6, y + 5, 6, list.rowH - 10, 0.95, risk.r, risk.g, risk.b)
    list:drawText(UI.fit(row.label, list.width * 0.5), 18, y + 4, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
    list:drawText(UI.fit(row.tip or "", list.width * 0.36), list.width * 0.52, y + 4, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    list:drawTextRight(tostring(row.tabTitle), list.width - 12, y + 4, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
end

function Window:refreshToolbar()
    local console = ProjectALife.AdminConsole
    local favourites = console.favourites()
    local actions = ProjectALife.AdminActions
    local context = console.context(self.playerNum)
    for slot = 1, Window.toolbarSlots do
        local button = self.toolbar[slot]
        local spec = favourites[slot] ~= nil and actions.get(favourites[slot]) or nil
        if spec ~= nil then
            button.actionId = spec.id
            button:setTitle(ProjectALife.AdminUI.fit(spec.label, math.max(40, button.width - 10)))
            button.tooltip = actions.tooltip(spec, context) .. "\nPinned: click the star in a tab to unpin."
            button:setVisible(true)
        else
            button.actionId = nil
            button:setVisible(false)
        end
    end
    ProjectALife.AdminUI.refreshPins(self)
end

function Window:layoutAll()
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local pad = metrics.pad
    local titleH = self:titleBarHeight()
    local y1 = titleH + 6
    local searchW = math.floor(self.width * 0.27)
    UI.setBounds(self.searchEntry, pad, y1, searchW, metrics.buttonH)
    local classicW = 90
    UI.setBounds(self.classicButton, self.width - pad - classicW, y1, classicW, metrics.buttonH)
    local slotsLeft = pad + searchW + 8
    local slotsRight = self.width - pad - classicW - 8
    local gap = 4
    local slotW = math.floor((slotsRight - slotsLeft - gap * (Window.toolbarSlots - 1)) / Window.toolbarSlots)
    for slot = 1, Window.toolbarSlots do
        UI.setBounds(self.toolbar[slot], slotsLeft + (slot - 1) * (slotW + gap), y1, slotW, metrics.buttonH)
    end
    local y2 = y1 + metrics.buttonH + 6
    local x = pad
    for _, id in ipairs(self.tabOrder or {}) do
        local button = self.tabButtons[id]
        local width = UI.measure(button.title) + 24
        UI.setBounds(button, x, y2, width, metrics.buttonH)
        x = x + width + 4
    end
    self.contentX, self.contentY = pad, y2 + metrics.buttonH + 6
    self.footerH = metrics.fontH + 10
    local resizeH = type(self.resizeWidgetHeight) == "function" and self:resizeWidgetHeight() or 10
    self.contentW = self.width - pad * 2
    self.contentH = self.height - self.contentY - self.footerH - resizeH - 4
    UI.setBounds(self.results, self.contentX, self.contentY, self.contentW, self.contentH)
    for id, panel in pairs(self.tabPanels) do
        UI.setBounds(panel, self.contentX, self.contentY, self.contentW, self.contentH)
        local tab = ProjectALife.AdminConsole.tab(id)
        if tab ~= nil and type(panel.layout) == "function" then panel:layout(self.contentW, self.contentH) end
    end
    self:refreshToolbar()
    self:highlightTab()
    self.laidWidth, self.laidHeight = self.width, self.height
end

function Window:highlightTab()
    local UI = ProjectALife.AdminUI
    for id, button in pairs(self.tabButtons) do
        local active = id == self.activeTab
        button.backgroundColor = UI.copy(active and UI.colors.accentDark or UI.colors.control)
        button.borderColor = UI.copy(active and UI.colors.accent or UI.colors.border)
        button.textColor = UI.copy(active and { r = 1, g = 0.9, b = 0.7, a = 1 } or UI.colors.text)
    end
end

function Window:finishOpen()
    self:layoutAll()
    local prefs = ProjectALife.AdminPrefs
    local wanted = prefs.get("tab")
    if ProjectALife.AdminConsole.tab(wanted) == nil then wanted = "spawn" end
    self:showTab(wanted)
    ProjectALife.AdminConsole.requestFactions(self.playerNum, false)
    ProjectALife.AdminConsole.requestCatalog(self.playerNum)
end

function Window:afterOpen()
    self:layoutAll()
end

function Window:tabsChanged(id)
    local panel = self.tabPanels[id]
    if panel ~= nil then
        self:removeChild(panel)
        self.tabPanels[id] = nil
    end
    local active = self.activeTab
    self:buildTabButtons()
    self:layoutAll()
    if active == id or active == nil then
        self.activeTab = nil
        self:showTab(id)
    end
end

function Window:showTab(id)
    local console = ProjectALife.AdminConsole
    local tab = console.tab(id)
    if tab == nil then return false end
    if self.activeTab ~= nil and self.activeTab ~= id then
        local previous = console.tab(self.activeTab)
        local panel = self.tabPanels[self.activeTab]
        if panel ~= nil then
            panel:setVisible(false)
            if previous ~= nil and type(previous.onHide) == "function" then pcall(previous.onHide, panel, self) end
        end
    end
    self.activeTab = id
    local panel = self.tabPanels[id]
    if panel == nil then
        panel = self:buildTab(tab)
        self.tabPanels[id] = panel
    end
    self.results:setVisible(false)
    panel:setVisible(string.find(self.query, "%S") == nil)
    if string.find(self.query, "%S") ~= nil then self:clearSearch() end
    self:highlightTab()
    ProjectALife.AdminPrefs.set("tab", id)
    if type(tab.onShow) == "function" then
        local ok, failure = pcall(tab.onShow, panel, self)
        if not ok then self:tabFailed(tab, panel, failure) end
    end
    return true
end

function Window:buildTab(tab)
    local UI = ProjectALife.AdminUI
    local console = ProjectALife.AdminConsole
    local panel = UI.panel(self, self.contentX, self.contentY, self.contentW, self.contentH, false)
    panel.prerender = Window.panelPrerender
    panel.tabId = tab.id
    console.metrics.tabBuilds = console.metrics.tabBuilds + 1
    if type(tab.build) == "function" then
        local ok, failure = pcall(tab.build, panel, self)
        if not ok then self:tabFailed(tab, panel, failure) end
    else
        Window.buildLauncherTab(panel, self, tab)
    end
    if type(panel.layout) == "function" then panel:layout(self.contentW, self.contentH) end
    return panel
end

function Window.panelPrerender(panel)
    ISPanel.prerender(panel)
    ProjectALife.AdminUI.drawLabels(panel)
end

function Window:tabFailed(tab, panel, failure)
    local console = ProjectALife.AdminConsole
    console.metrics.errors = console.metrics.errors + 1
    print("[ALIFE-ADMIN] tab " .. tostring(tab.id) .. " failed: " .. tostring(failure))
    local UI = ProjectALife.AdminUI
    UI.addLabel(panel, "This tab failed to build: " .. tostring(failure), 12, 12, UI.colors.bad)
    UI.addLabel(panel, "Use Classic for the old panel and report the line in console.txt.", 12, 12 + UI.metrics().rowH, UI.colors.muted)
    self:setStatus("Tab " .. tostring(tab.title) .. " failed: " .. tostring(failure), "error")
end

function Window.buildLauncherTab(panel, window, tab)
    local UI = ProjectALife.AdminUI
    local metrics = UI.metrics()
    local text = tab.description or tab.tip or ""
    local lines = UI.wrap(text, math.max(200, panel.width - 40))
    for index, line in ipairs(lines) do UI.addLabel(panel, line, 16, 14 + (index - 1) * metrics.rowH, UI.colors.text) end
    local launcher = tab.launcher
    local button = UI.button(panel, 16, 24 + #lines * metrics.rowH, 260, metrics.buttonH * 1.4,
        launcher ~= nil and ("Open " .. tab.title .. " window") or "Not installed in this build", window, Window.onLauncher, launcher ~= nil)
    button.tabId = tab.id
    button:setEnable(launcher ~= nil)
    button.tooltip = launcher ~= nil and tab.tip or "The tool that provides this tab is not part of this build."
    panel.launchButton = button
end

function Window.onLauncher(window, button)
    local tab = ProjectALife.AdminConsole.tab(button.tabId)
    if tab == nil or type(tab.launcher) ~= "function" then return end
    local ok, failure = pcall(tab.launcher, window.playerNum, window)
    if not ok then window:setStatus("Launcher failed: " .. tostring(failure), "error") end
end

function Window:setStatus(text, severity)
    self.statusText, self.statusSeverity = tostring(text or ""), severity or "info"
end

function Window:reportText()
    local panel = self.tabPanels[self.activeTab]
    if panel == nil or panel.report == nil then return "" end
    return panel.report:text()
end

function Window:refreshSpawn()
    local panel = self.tabPanels.spawn
    if panel ~= nil and type(panel.refresh) == "function" then panel:refresh() end
end

function Window:onReply(command, arguments)
    local console = ProjectALife.AdminConsole
    for id, panel in pairs(self.tabPanels) do
        local tab = console.tab(id)
        if tab ~= nil and type(tab.onReply) == "function" then
            local ok, failure = pcall(tab.onReply, command, arguments, self, panel)
            if not ok then
                console.metrics.errors = console.metrics.errors + 1
                print("[ALIFE-ADMIN] tab " .. tostring(id) .. " reply failed: " .. tostring(failure))
            end
        end
        if type(panel.onReply) == "function" then pcall(panel.onReply, panel, command, arguments) end
    end
end

function Window:onResize()
    self:layoutAll()
end

function Window:update()
    if ISCollapsableWindow.update ~= nil then ISCollapsableWindow.update(self) end
    if self.laidWidth ~= self.width or self.laidHeight ~= self.height then self:layoutAll() end
    local console = ProjectALife.AdminConsole
    local state = console.player(self.playerNum)
    local now = console.nowMs()
    if state.previewDueMs ~= nil and now >= state.previewDueMs and self.activeTab == "spawn" then
        console.preview(self.playerNum)
    end
    if ProjectALife.AdminPrefs.get("autoRefresh") ~= false and now - self.lastRefreshMs >= 3000 then
        self.lastRefreshMs = now
        local panel = self.tabPanels[self.activeTab]
        if panel ~= nil and type(panel.autoRefresh) == "function" then panel:autoRefresh() end
    end
    local catalog = console.catalog()
    if catalog ~= self.seenCatalog then
        self.seenCatalog = catalog
        local spawn = self.tabPanels.spawn
        if spawn ~= nil and type(spawn.catalogChanged) == "function" then spawn:catalogChanged() end
    end
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local access = ProjectALife.AdminConsole.access(self.playerNum)
    local badge = access.ok and colors.good or colors.bad
    local text = access.text
    local width = UI.measure(text) + 14
    local x = self.width - width - 54
    self:drawRect(x, 3, width, self:titleBarHeight() - 6, 0.9, badge.r * 0.35, badge.g * 0.35, badge.b * 0.35)
    self:drawRectBorder(x, 3, width, self:titleBarHeight() - 6, 1, badge.r, badge.g, badge.b)
    self:drawText(text, x + 7, 4, badge.r, badge.g, badge.b, 1, UIFont.Small)
end

function Window:render()
    ISCollapsableWindow.render(self)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local color = colors.muted
    if self.statusSeverity == "error" then color = colors.bad elseif self.statusSeverity == "warning" then color = colors.warn end
    local y = self.height - (self.footerH or 20) - 12
    self:drawText(UI.fit(self.statusText, self.width - 30), 10, y, color.r, color.g, color.b, 1, UIFont.Small)
end

function Window:close()
    ProjectALife.AdminConsole.close(self.playerNum)
end

function Window:shutdown()
    self:setVisible(false)
    self:removeFromUIManager()
end

return Factory
