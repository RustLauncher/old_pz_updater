require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"

ProjectALife = ProjectALife or {}

local UI = {
    colors = {
        accent = { r = 0.72, g = 0.55, b = 0.32, a = 1 },
        accentDark = { r = 0.13, g = 0.10, b = 0.065, a = 0.96 },
        panel = { r = 0.055, g = 0.060, b = 0.064, a = 0.97 },
        card = { r = 0.070, g = 0.075, b = 0.078, a = 0.98 },
        control = { r = 0.095, g = 0.100, b = 0.105, a = 0.96 },
        controlOver = { r = 0.16, g = 0.15, b = 0.12, a = 1 },
        border = { r = 0.30, g = 0.32, b = 0.33, a = 1 },
        text = { r = 0.92, g = 0.91, b = 0.88, a = 1 },
        muted = { r = 0.68, g = 0.69, b = 0.68, a = 1 },
        bad = { r = 0.82, g = 0.36, b = 0.34, a = 1 },
        good = { r = 0.35, g = 0.85, b = 0.55, a = 1 },
        warn = { r = 0.94, g = 0.68, b = 0.30, a = 1 },
        row = { r = 0.085, g = 0.090, b = 0.095, a = 0.90 },
        rowOn = { r = 0.17, g = 0.135, b = 0.09, a = 0.95 },
        rowHover = { r = 0.12, g = 0.12, b = 0.11, a = 0.95 },
    },
    riskColors = { safe = "good", caution = "warn", danger = "bad" },
    metricsCache = nil,
}
ProjectALife.AdminUI = UI

function UI.copy(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

function UI.color(name)
    return UI.copy(UI.colors[name] or UI.colors.text)
end

function UI.metrics()
    local manager = getTextManager()
    local font = UIFont.Small
    local height = manager:getFontHeight(font)
    local cached = UI.metricsCache
    if cached ~= nil and cached.fontH == height then return cached end
    cached = { fontH = height, rowH = height + 8, buttonH = height + 8, pad = 10,
        charW = manager:MeasureStringX(font, "M"), font = font }
    UI.metricsCache = cached
    return cached
end

function UI.measure(text)
    return getTextManager():MeasureStringX(UIFont.Small, tostring(text))
end

function UI.fit(text, width)
    text = tostring(text or "")
    if width <= 0 then return "" end
    if UI.measure(text) <= width then return text end
    local low, high = 0, #text
    while low < high do
        local middle = math.ceil((low + high) / 2)
        if UI.measure(string.sub(text, 1, middle) .. "...") <= width then low = middle else high = middle - 1 end
    end
    if low <= 0 then return "" end
    return string.sub(text, 1, low) .. "..."
end

function UI.wrap(text, width)
    local lines = {}
    for paragraph in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
        local line = ""
        for word in string.gmatch(paragraph, "[^%s]+") do
            local trial = line == "" and word or (line .. " " .. word)
            if line ~= "" and UI.measure(trial) > width then
                lines[#lines + 1] = line
                line = word
            else
                line = trial
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

function UI.styleButton(button, accent)
    button.backgroundColor = UI.copy(accent and UI.colors.accentDark or UI.colors.control)
    button.backgroundColorMouseOver = UI.copy(UI.colors.controlOver)
    button.borderColor = UI.copy(accent and UI.colors.accent or UI.colors.border)
    button.textColor = UI.copy(accent and { r = 1, g = 0.9, b = 0.7, a = 1 } or UI.colors.text)
    return button
end

function UI.button(parent, x, y, width, height, label, target, callback, accent)
    local button = ISButton:new(x, y, width, height, label, target, callback)
    button:initialise()
    button:instantiate()
    UI.styleButton(button, accent)
    parent:addChild(button)
    return button
end

function UI.tooltip(button, text)
    if button == nil then return end
    button.tooltip = text
end

function UI.entry(parent, x, y, width, height, text, numbers, placeholder)
    local entry = ISTextEntryBox:new(tostring(text or ""), x, y, width, height)
    entry:initialise()
    entry:instantiate()
    if numbers == true then entry:setOnlyNumbers(true) end
    if placeholder ~= nil and type(entry.setPlaceholderText) == "function" then entry:setPlaceholderText(placeholder) end
    entry.backgroundColor = UI.copy(UI.colors.control)
    entry.borderColor = UI.copy(UI.colors.border)
    parent:addChild(entry)
    return entry
end

function UI.combo(parent, x, y, width, height, target, onChange)
    local combo = ISComboBox:new(x, y, width, height, target, onChange)
    combo:initialise()
    combo:instantiate()
    combo.backgroundColor = UI.copy(UI.colors.control)
    combo.borderColor = UI.copy(UI.colors.border)
    parent:addChild(combo)
    return combo
end

function UI.fillCombo(combo, rows, selected)
    combo:clear()
    local chosen = 1
    for index, row in ipairs(rows) do
        combo:addOptionWithData(row[1], row[2], row[3])
        if row[2] == selected then chosen = index end
    end
    combo.selected = chosen
    return combo
end

function UI.comboData(combo)
    if combo == nil or combo.selected == nil then return nil end
    return combo:getOptionData(combo.selected)
end

function UI.tick(parent, x, y, width, height, label, selected, target, onChange)
    local box = ISTickBox:new(x, y, width, height, label, target, onChange)
    box:initialise()
    box:instantiate()
    box:addOption(label)
    box:setSelected(1, selected == true)
    parent:addChild(box)
    return box
end

function UI.panel(parent, x, y, width, height, card)
    local panel = ISPanel:new(x, y, width, height)
    panel:initialise()
    panel.backgroundColor = UI.copy(card and UI.colors.card or UI.colors.panel)
    panel.borderColor = UI.copy(UI.colors.border)
    if parent ~= nil then parent:addChild(panel) end
    return panel
end

function UI.setBounds(widget, x, y, width, height)
    widget:setX(x)
    widget:setY(y)
    if width ~= nil then widget:setWidth(width) end
    if height ~= nil then widget:setHeight(height) end
end

UI.List = ISPanel:derive("ALifeAdminList")

function UI.List:new(x, y, width, height, options)
    local panel = ISPanel.new(self, x, y, width, height)
    options = options or {}
    panel.rows = {}
    panel.selected = nil
    panel.scroll = 0
    panel.hover = nil
    panel.rowH = options.rowH or UI.metrics().rowH
    panel.onPick = options.onPick
    panel.target = options.target
    panel.drawRowFn = options.drawRow
    panel.empty = options.empty or "(nothing to show)"
    panel.backgroundColor = UI.copy(UI.colors.panel)
    panel.borderColor = UI.copy(UI.colors.border)
    return panel
end

function UI.List:visibleCount()
    return math.max(1, math.floor(self.height / self.rowH))
end

function UI.List:clampScroll()
    local maximum = math.max(0, #self.rows - self:visibleCount())
    self.scroll = math.max(0, math.min(maximum, self.scroll))
end

function UI.List:setRows(rows, keepSelection)
    local previous = keepSelection and self.selected or nil
    self.rows = type(rows) == "table" and rows or {}
    self.selected = nil
    if previous ~= nil and previous <= #self.rows then self.selected = previous end
    self:clampScroll()
end

function UI.List:selectedRow()
    if self.selected == nil then return nil end
    return self.rows[self.selected]
end

function UI.List:select(index, notify)
    if self.rows[index] == nil then return false end
    self.selected = index
    local top, bottom = self.scroll + 1, self.scroll + self:visibleCount()
    if index < top then self.scroll = index - 1 elseif index > bottom then self.scroll = index - self:visibleCount() end
    self:clampScroll()
    if notify and type(self.onPick) == "function" then self.onPick(self.target, self.rows[index], index, self) end
    return true
end

function UI.List:rowAt(y)
    local index = self.scroll + math.floor(y / self.rowH) + 1
    if y < 0 or self.rows[index] == nil then return nil end
    return index
end

function UI.List:onMouseWheel(delta)
    self.scroll = self.scroll + (delta > 0 and 1 or -1) * 2
    self:clampScroll()
    return true
end

function UI.List:onMouseMove(dx, dy)
    self.hover = self:rowAt(self:getMouseY())
end

function UI.List:onMouseMoveOutside(dx, dy)
    self.hover = nil
end

function UI.List:onMouseUp(x, y)
    local index = self:rowAt(y)
    if index == nil then return false end
    self.selected = index
    if type(self.onPick) == "function" then self.onPick(self.target, self.rows[index], index, self) end
    return true
end

function UI.List:hoverRow()
    if self.hover == nil then return nil end
    return self.rows[self.hover]
end

function UI.List:render()
    local colors = UI.colors
    self:drawRect(0, 0, self.width, self.height, colors.panel.a, colors.panel.r, colors.panel.g, colors.panel.b)
    self:drawRectBorder(0, 0, self.width, self.height, colors.border.a, colors.border.r, colors.border.g, colors.border.b)
    local count = self:visibleCount()
    for offset = 0, count - 1 do
        local index = self.scroll + offset + 1
        local row = self.rows[index]
        if row == nil then break end
        local y = offset * self.rowH
        local fill = colors.row
        if index == self.selected then fill = colors.rowOn elseif index == self.hover then fill = colors.rowHover end
        self:drawRect(2, y + 1, self.width - 4, self.rowH - 2, fill.a, fill.r, fill.g, fill.b)
        if index == self.selected then
            self:drawRectBorder(2, y + 1, self.width - 4, self.rowH - 2, colors.accent.a, colors.accent.r, colors.accent.g, colors.accent.b)
        end
        if type(self.drawRowFn) == "function" then
            self.drawRowFn(self, row, y, index == self.selected)
        else
            local color = row.color or colors.text
            self:drawText(UI.fit(row.label or "?", self.width - 16), 8, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
        end
    end
    if #self.rows == 0 then
        self:drawText(self.empty, 8, 4, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    elseif #self.rows > count then
        local barH = math.max(8, math.floor(self.height * count / #self.rows))
        local barY = math.floor((self.height - barH) * self.scroll / math.max(1, #self.rows - count))
        self:drawRect(self.width - 4, barY, 3, barH, 0.7, colors.accent.r, colors.accent.g, colors.accent.b)
    end
end

UI.Report = ISPanel:derive("ALifeAdminReport")

function UI.Report:new(x, y, width, height)
    local panel = ISPanel.new(self, x, y, width, height)
    panel.lines = {}
    panel.scroll = 0
    panel.lineH = UI.metrics().fontH + 2
    panel.backgroundColor = UI.copy(UI.colors.card)
    panel.borderColor = UI.copy(UI.colors.border)
    return panel
end

function UI.Report:setLines(lines)
    self.lines = type(lines) == "table" and lines or {}
    self:clampScroll()
end

function UI.Report:visibleCount()
    return math.max(1, math.floor((self.height - 8) / self.lineH))
end

function UI.Report:clampScroll()
    self.scroll = math.max(0, math.min(math.max(0, #self.lines - self:visibleCount()), self.scroll))
end

function UI.Report:onMouseWheel(delta)
    self.scroll = self.scroll + (delta > 0 and 1 or -1) * 3
    self:clampScroll()
    return true
end

function UI.Report:text()
    local parts = {}
    for _, line in ipairs(self.lines) do parts[#parts + 1] = type(line) == "table" and tostring(line.text) or tostring(line) end
    return table.concat(parts, "\n")
end

function UI.Report:render()
    local colors = UI.colors
    self:drawRect(0, 0, self.width, self.height, colors.card.a, colors.card.r, colors.card.g, colors.card.b)
    self:drawRectBorder(0, 0, self.width, self.height, colors.border.a, colors.border.r, colors.border.g, colors.border.b)
    local count = self:visibleCount()
    for offset = 0, count - 1 do
        local line = self.lines[self.scroll + offset + 1]
        if line == nil then break end
        local text, color, indent = line, colors.text, 0
        if type(line) == "table" then
            text, color, indent = line.text, line.color or colors.text, line.indent or 0
        end
        self:drawText(UI.fit(text, self.width - 16 - indent), 8 + indent, 4 + offset * self.lineH,
            color.r, color.g, color.b, 1, UIFont.Small)
    end
    if #self.lines > count then
        local barH = math.max(8, math.floor(self.height * count / #self.lines))
        local barY = math.floor((self.height - barH) * self.scroll / math.max(1, #self.lines - count))
        self:drawRect(self.width - 4, barY, 3, barH, 0.7, colors.accent.r, colors.accent.g, colors.accent.b)
    end
end

function UI.line(text, colorName, indent)
    return { text = tostring(text), color = UI.color(colorName or "text"), indent = indent or 0 }
end

function UI.drawLabels(panel)
    local colors = UI.colors
    for _, label in ipairs(panel.labels or {}) do
        if label.hidden ~= true and label.text ~= "" then
            local color = label.color or colors.muted
            if label.heading then color = colors.accent end
            panel:drawText(UI.fit(label.text, math.max(20, panel.width - label.x - 8)), label.x, label.y,
                color.r, color.g, color.b, 1, UIFont.Small)
        end
    end
end

function UI.addLabel(panel, text, x, y, color)
    panel.labels = panel.labels or {}
    local label = { text = tostring(text), x = x, y = y, color = color }
    panel.labels[#panel.labels + 1] = label
    return label
end

function UI.onAction(window, button)
    local console = ProjectALife.AdminConsole
    if console == nil or button == nil then return end
    console.run(button.actionId, window.playerNum, window)
end

function UI.onPin(window, button)
    local console = ProjectALife.AdminConsole
    if console == nil or button == nil then return end
    console.pin(button.actionId, window)
end

function UI.actionButton(window, panel, spec)
    local console = ProjectALife.AdminConsole
    local metrics = UI.metrics()
    local main = UI.button(panel, 0, 0, 100, metrics.buttonH, spec.label, window, UI.onAction, spec.risk == "danger")
    main.actionId = spec.id
    main.tooltip = ProjectALife.AdminActions.tooltip(spec, console.context(window.playerNum))
    main.riskName = spec.risk
    local pin = UI.button(panel, 0, 0, metrics.buttonH, metrics.buttonH, "*", window, UI.onPin, false)
    pin.actionId = spec.id
    pin.tooltip = "Pin to the toolbar (up to " .. tostring(ProjectALife.AdminActions.maxFavourites)
        .. "). Click again to unpin."
    local entry = { main = main, pin = pin, spec = spec, panel = panel }
    window.actionButtons = window.actionButtons or {}
    window.actionButtons[#window.actionButtons + 1] = entry
    return entry
end

function UI.actionGrid(window, panel, specs, columns)
    local grid = { entries = {}, columns = columns or 1 }
    for _, spec in ipairs(specs) do grid.entries[#grid.entries + 1] = UI.actionButton(window, panel, spec) end
    return grid
end

function UI.placeGrid(grid, x, y, width, gap)
    local metrics = UI.metrics()
    gap = gap or 4
    local columns = math.max(1, grid.columns)
    local cell = math.floor((width - gap * (columns - 1)) / columns)
    local rowH = metrics.buttonH
    local rows = 0
    for index, entry in ipairs(grid.entries) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local cx, cy = x + column * (cell + gap), y + row * (rowH + gap)
        local mainW = cell - rowH - 2
        UI.setBounds(entry.main, cx, cy, mainW, rowH)
        entry.main:setTitle(UI.fit(entry.spec.label, mainW - 10))
        UI.setBounds(entry.pin, cx + cell - rowH, cy, rowH, rowH)
        rows = row + 1
    end
    return rows * (rowH + gap)
end

function UI.refreshPins(window)
    local favourites = ProjectALife.AdminPrefs.favouriteList()
    for _, entry in ipairs(window.actionButtons or {}) do
        local pinned = ProjectALife.AdminActions.isFavourite(favourites, entry.spec.id)
        entry.pin:setTitle(pinned and "#" or "*")
        local color = pinned and UI.colors.accent or UI.colors.text
        entry.pin.textColor = UI.copy(color)
    end
end

return UI
