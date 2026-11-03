require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeRepLevels"
require "ProjectALife/Interface/ALifeStatusStore"
require "ProjectALife/Interface/ALifeRepScreen"
require "ProjectALife/Interface/ALifeSafehouseClient"
require "ProjectALife/Interface/ALifeFieldRadioData"

ProjectALife = ProjectALife or {}

local FieldRadio = ProjectALife.FieldRadio or {}
ProjectALife.FieldRadio = FieldRadio

ALifeFieldRadioWindow = ISCollapsableWindow:derive("ALifeFieldRadioWindow")
ALifeFieldRadioWindow.instance = nil

FieldRadio.theme = {
    bg = { 0.010, 0.013, 0.015, 0.97 },
    panel = { 0.017, 0.022, 0.024, 0.96 },
    line = { 0.115, 0.145, 0.152, 1 },
    accent = { 0.34, 0.52, 0.57, 1 },
    lit = { 0.52, 0.74, 0.79, 1 },
    text = { 0.79, 0.81, 0.79, 1 },
    dim = { 0.43, 0.48, 0.47, 1 },
    select = { 0.34, 0.52, 0.57, 0.24 },
    tabOff = { 0.022, 0.032, 0.036, 1 },
    tabOn = { 0.075, 0.125, 0.14, 1 },
    hostile = { 0.86, 0.28, 0.22, 1 },
    careful = { 0.92, 0.62, 0.20, 1 },
    neutral = { 0.62, 0.68, 0.68, 1 },
    friendly = { 0.38, 0.82, 0.48, 1 },
}

FieldRadio.tabs = {
    { id = "rep", label = "Standing" },
    { id = "contacts", label = "Contacts" },
    { id = "radio", label = "Heard" },
    { id = "notes", label = "Notes" },
}

FieldRadio.blocs = {
    { id = "law", label = "Law and police" },
    { id = "military", label = "Military" },
    { id = "civilian", label = "Civilians and workers" },
    { id = "family", label = "Families" },
    { id = "crime", label = "Gangs and criminals" },
    { id = "raider", label = "Raiders" },
}

FieldRadio.stanceWords = { hostile = "Hostile", careful = "Careful", neutral = "Neutral", friendly = "Friendly" }
FieldRadio.stanceValues = { hostile = -1, careful = -0.5, neutral = 0, friendly = 1 }

FieldRadio.reasons = {
    map_closed = "Open the world map once, then try again.",
    not_found = "That marker is not on your map any more.",
    unsupported = "This build cannot edit map markers.",
    no_contact = "Select a contact first.",
}

function FieldRadio.rgba(name, alpha)
    local source = FieldRadio.theme[name] or FieldRadio.theme.text
    return { r = source[1], g = source[2], b = source[3], a = alpha or source[4] }
end

function FieldRadio.ui(text, vars)
    return ProjectALife.Text.ui(text, vars)
end

function FieldRadio.fontHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

function FieldRadio.utf16Strings()
    local ok, unit = pcall(string.char, 256)
    return ok and type(unit) == "string" and #unit == 1 and string.byte(unit, 1) == 256
end

FieldRadio.utf16 = FieldRadio.utf16Strings()

function FieldRadio.cut(text, count)
    if count >= #text then return text end
    local byte = string.byte(text, count + 1)
    while not FieldRadio.utf16 and count > 0 and byte ~= nil and byte >= 128 and byte < 192 do
        count = count - 1
        byte = string.byte(text, count + 1)
    end
    if byte ~= nil and byte >= 56320 and byte <= 57343 then count = count - 1 end
    return string.sub(text, 1, math.max(0, count))
end

function FieldRadio.wordPart(text, width)
    local low, high, best = 1, #text, ""
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local part = FieldRadio.cut(text, middle)
        if FieldRadio.measure(part) <= width then
            best, low = part, middle + 1
        else
            high = middle - 1
        end
    end
    return best
end

function FieldRadio.wrap(list, text)
    local width = math.max(1, list:getWidth() - list.pad * 2 - 18)
    local lines = {}
    for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
        local line = ""
        for word in string.gmatch(paragraph, "%S+") do
            local attempt = line == "" and word or (line .. " " .. word)
            if line ~= "" and FieldRadio.measure(attempt) > width then
                lines[#lines + 1] = line
                line = ""
            end
            while FieldRadio.measure(word) > width do
                local part = FieldRadio.wordPart(word, width)
                if part == "" then break end
                lines[#lines + 1] = part
                word = string.sub(word, #part + 1)
            end
            if word ~= "" then line = line == "" and word or (line .. " " .. word) end
        end
        if line ~= "" or paragraph == "" then lines[#lines + 1] = line end
    end
    return lines
end

function FieldRadio.add(list, row)
    row.lines = row.lines or {}
    return list:addItem(row.title or "", row)
end

function FieldRadio.head(list, text)
    FieldRadio.add(list, { kind = "head", title = FieldRadio.ui(text) })
end

function FieldRadio.note(list, text)
    FieldRadio.add(list, { kind = "text", lines = FieldRadio.wrap(list, FieldRadio.ui(text)) })
end

function FieldRadio.empty(list, text)
    FieldRadio.add(list, { kind = "empty", lines = FieldRadio.wrap(list, FieldRadio.ui(text)) })
end

function FieldRadio.stanceRow(list, label, status, hint)
    local word = FieldRadio.stanceWords[status] or FieldRadio.stanceWords.neutral
    local title = label
    if hint ~= nil and hint ~= "" then title = label .. " (" .. hint .. ")" end
    FieldRadio.add(list, {
        kind = "bar",
        title = title,
        word = FieldRadio.ui(word),
        status = FieldRadio.stanceWords[status] ~= nil and status or "neutral",
        value = FieldRadio.stanceValues[status] or 0,
    })
end

function FieldRadio.fillReputation(window, list)
    local levelName = ProjectALife.RepScreen.levelName()
    local store = ProjectALife.StatusStore
    local reputation = store ~= nil and store.reputation or nil
    local personal = type(reputation) == "table" and reputation.personal or nil
    FieldRadio.head(list, "Your reputation")
    if levelName == nil or type(personal) ~= "table" then
        FieldRadio.empty(list, "Nothing yet. Press Refresh to ask the server.")
    else
        FieldRadio.add(list, { kind = "level", title = levelName, icon = personal.level, lines = {} })
        local blurb = ProjectALife.RepScreen.blurb()
        if blurb ~= nil then FieldRadio.add(list, { kind = "text", lines = FieldRadio.wrap(list, blurb) }) end
        FieldRadio.head(list, "How the blocs see you")
        local levels = ProjectALife.RepLevels
        for _, bloc in ipairs(FieldRadio.blocs) do
            local cell = levels ~= nil and type(levels.cell) == "function" and levels.cell(personal.level, bloc.id) or nil
            local status = "neutral"
            if type(cell) == "table" and cell.stance ~= nil then status = cell.stance end
            FieldRadio.stanceRow(list, FieldRadio.ui(bloc.label), status, nil)
        end
    end
    FieldRadio.note(list, "Last known standing, as the server told you. It can be out of date until you press Refresh.")
end

function FieldRadio.fillContacts(window, list)
    local contacts = ProjectALife.FieldRadioData.contacts
    local party = ProjectALife.FieldRadioData.party
    if party ~= nil then
        FieldRadio.head(list, "Your group")
        local lines = FieldRadio.wrap(list, FieldRadio.ui("{group}, led by {leader}. {count} with you.", { group = party.group,
            leader = party.leader, count = party.members }))
        if party.task ~= nil and party.task ~= "" then
            lines[#lines + 1] = FieldRadio.ui("Job:") .. " " .. party.task
            if party.progress ~= nil and party.progress ~= "" then lines[#lines + 1] = party.progress end
        else
            lines[#lines + 1] = FieldRadio.ui("No job right now. Ask: What should I do?")
        end
        FieldRadio.add(list, { kind = "entry", title = FieldRadio.ui("Party"), meta = "", lines = lines })
    end
    FieldRadio.head(list, "People who told you where they live")
    if #contacts == 0 then
        FieldRadio.empty(list, "Nothing yet. Ask someone friendly: Where do you live?")
        return
    end
    for _, contact in ipairs(contacts) do
        local who = contact.npc
        if who == nil or who == "" then who = FieldRadio.ui("Someone") end
        local detail = contact.place
        if contact.faction ~= nil and contact.faction ~= "" then detail = contact.faction .. " - " .. contact.place end
        local lines = FieldRadio.wrap(list, detail)
        local state = FieldRadio.ui("Marker on your map")
        if contact.marked ~= true then state = FieldRadio.ui("No marker on your map") end
        lines[#lines + 1] = state .. "  (" .. tostring(contact.x) .. ", " .. tostring(contact.y) .. ")"
        FieldRadio.add(list, {
            kind = "entry",
            title = who,
            meta = FieldRadio.ui("Last seen: {when}", { ["when"] = ProjectALife.FieldRadioData.when(contact) }),
            lines = lines,
            pick = true,
            contact = contact,
        })
    end
end

function FieldRadio.fillRadio(window, list)
    local entries = ProjectALife.FieldRadioData.radio
    FieldRadio.head(list, "Heard on the air")
    if #entries == 0 then
        FieldRadio.empty(list, "Nothing yet. Tune a radio to hear Knox County Radio.")
        return
    end
    for _, entry in ipairs(entries) do
        local title = entry.station
        if title == nil then
            if entry.kind == "meta" then title = FieldRadio.ui("Outside") else title = FieldRadio.ui("Radio") end
        end
        FieldRadio.add(list, {
            kind = "entry",
            title = FieldRadio.ui(title),
            meta = ProjectALife.FieldRadioData.when(entry),
            lines = FieldRadio.wrap(list, entry.text),
        })
    end
end

function FieldRadio.noteTitle(note)
    local client = ProjectALife.SafehouseClient
    if note.mark ~= nil and client ~= nil and type(client.events) == "table" then
        for _, row in ipairs(client.events) do
            if row[1] == note.mark then return FieldRadio.ui(row[2]) end
        end
    end
    if note.mark ~= nil then return FieldRadio.ui("Mark") end
    return FieldRadio.ui("News from your base")
end

function FieldRadio.fillNotes(window, list)
    local notes = ProjectALife.FieldRadioData.notes
    FieldRadio.head(list, "Letters, signs and news from your base")
    if #notes == 0 then
        FieldRadio.empty(list, "Nothing yet. Notes appear when something happens at your base.")
        return
    end
    for _, note in ipairs(notes) do
        FieldRadio.add(list, {
            kind = "entry",
            title = FieldRadio.noteTitle(note),
            meta = ProjectALife.FieldRadioData.when(note),
            lines = FieldRadio.wrap(list, note.text),
            pick = true,
            unread = note.read ~= true,
            noteRef = note,
        })
    end
    FieldRadio.note(list, "Letters themselves are items in your inventory. This list only tells you that something was left.")
end

function FieldRadio.fill(window)
    local list = window.list
    if list == nil then return end
    local keep = list.selected
    list:clear()
    list.selected = -1
    local tab = FieldRadio.tabs[window.tab]
    if tab == nil then return end
    if tab.id == "rep" then FieldRadio.fillReputation(window, list)
    elseif tab.id == "contacts" then FieldRadio.fillContacts(window, list)
    elseif tab.id == "radio" then FieldRadio.fillRadio(window, list)
    else FieldRadio.fillNotes(window, list) end
    if window.keepTab == window.tab and type(keep) == "number" and keep > 0 and list.items[keep] ~= nil
            and list.items[keep].item ~= nil and list.items[keep].item.pick == true then
        list.selected = keep
    end
    window.keepTab = window.tab
    window.seenRevision = ProjectALife.FieldRadioData.revision
    window.seenReputation = ProjectALife.StatusStore.reputation
    FieldRadio.retitle(window)
end

function FieldRadio.retitle(window)
    local data = ProjectALife.FieldRadioData
    for index, tab in ipairs(FieldRadio.tabs) do
        local button = window.tabButtons[index]
        local label = FieldRadio.ui(tab.label)
        if tab.id == "contacts" and #data.contacts > 0 then label = label .. " (" .. tostring(#data.contacts) .. ")" end
        if tab.id == "notes" and data.unreadNotes() > 0 then label = label .. " (" .. tostring(data.unreadNotes()) .. ")" end
        button:setTitle(label)
        local active = index == window.tab
        button.backgroundColor = FieldRadio.rgba(active and "tabOn" or "tabOff")
        button.backgroundColorMouseOver = FieldRadio.rgba("tabOn")
        button.borderColor = FieldRadio.rgba(active and "accent" or "line", 1)
        button.textColor = FieldRadio.rgba(active and "lit" or "dim", 1)
    end
end

function FieldRadio.drawRow(list, y, entry, alt)
    local row = entry.item
    local fontH, pad, width, theme = list.fontH, list.pad, list:getWidth(), FieldRadio.theme
    if type(row) ~= "table" then return y + fontH end
    local kind, font = row.kind, UIFont.Small
    local height
    if kind == "head" then height = fontH + 16
    elseif kind == "text" or kind == "empty" then height = #row.lines * fontH + 10
    elseif kind == "bar" then height = fontH * 2 + 16
    elseif kind == "level" then height = fontH + 12
    else height = fontH * (1 + #row.lines) + 16 end
    if row.pick == true and list.selected == entry.index then
        local s = theme.select
        list:drawRect(0, y, width, height - 1, s[4], s[1], s[2], s[3])
    end
    local inner = width - pad * 2 - 14
    if kind == "head" then
        local c = theme.accent
        list:drawText(row.title, pad, y + 8, c[1], c[2], c[3], 1, font)
        local l = theme.line
        list:drawRect(pad, y + fontH + 11, inner, 1, 0.7, l[1], l[2], l[3])
    elseif kind == "level" then
        local c = theme.text
        local icons = ProjectALife.RepIcons
        local texture = row.icon ~= nil and icons ~= nil and icons.texture(row.icon) or nil
        local textX = pad
        if texture ~= nil then
            list:drawTextureScaled(texture, pad, y + 3, 22, 22, 1, 1, 1, 1)
            textX = pad + 28
        end
        list:drawText(row.title, textX, y + 6, c[1], c[2], c[3], 1, UIFont.Medium)
    elseif kind == "text" or kind == "empty" then
        local c = kind == "empty" and theme.dim or theme.text
        for index, line in ipairs(row.lines) do
            list:drawText(line, pad, y + 5 + (index - 1) * fontH, c[1], c[2], c[3], 1, font)
        end
    elseif kind == "bar" then
        local c, tone = theme.text, theme[row.status] or theme.neutral
        list:drawText(row.title, pad, y + 6, c[1], c[2], c[3], 1, font)
        list:drawTextRight(row.word, pad + inner, y + 6, tone[1], tone[2], tone[3], 1, font)
        local barY = y + fontH + 12
        list:drawRect(pad, barY, inner, 5, 0.9, 0.09, 0.1, 0.11)
        local middle = pad + inner / 2
        local half = inner / 2
        local fill = math.floor(math.abs(row.value) * half)
        if row.value < 0 then list:drawRect(middle - fill, barY, fill, 5, 1, tone[1], tone[2], tone[3])
        elseif row.value > 0 then list:drawRect(middle, barY, fill, 5, 1, tone[1], tone[2], tone[3]) end
        list:drawRect(math.floor(middle), barY - 2, 1, 9, 1, 0.75, 0.8, 0.8)
    else
        local c, dim, tone = theme.text, theme.dim, theme.accent
        local x = pad
        if row.unread == true then
            list:drawRect(pad, y + 8, 6, 6, 1, tone[1], tone[2], tone[3])
            x = pad + 12
        end
        local titleTone = row.unread == true and tone or c
        list:drawText(row.title, x, y + 5, titleTone[1], titleTone[2], titleTone[3], 1, font)
        if row.meta ~= nil then list:drawTextRight(row.meta, pad + inner, y + 5, dim[1], dim[2], dim[3], 1, font) end
        for index, line in ipairs(row.lines) do
            list:drawText(line, pad, y + 7 + index * fontH, c[1], c[2], c[3], 1, font)
        end
        local l = theme.line
        list:drawRect(pad, y + height - 2, inner, 1, 0.35, l[1], l[2], l[3])
    end
    return y + height
end

function FieldRadio.scrollLong(list, delta)
    if list == nil or list.parent == nil then return false end
    local tab = FieldRadio.tabs[list.parent.tab]
    if tab == nil or tab.id ~= "radio" then return false end
    for _, entry in ipairs(list.items) do
        if (entry.height or 0) > list:getHeight() then
            local target = math.max(math.min(0, list:getHeight() - list:getScrollHeight()),
                math.min(0, list:getYScroll() - delta * list.fontH * 3))
            list.smoothScrollTargetY, list.smoothScrollY = nil, nil
            list:setYScroll(target)
            return true
        end
    end
    return false
end

function FieldRadio.onMouseWheel(list, delta)
    if FieldRadio.scrollLong(list, delta) then return true end
    return ISScrollingListBox.onMouseWheel(list, delta)
end

function ALifeFieldRadioWindow:selectedRow()
    local list = self.list
    if list == nil or type(list.selected) ~= "number" or list.selected < 1 then return nil end
    local entry = list.items[list.selected]
    if entry == nil or type(entry.item) ~= "table" or entry.item.pick ~= true then return nil end
    return entry.item
end

function ALifeFieldRadioWindow:say(text)
    self.message = text
    self.messageUntil = (type(getTimestampMs) == "function" and getTimestampMs() or 0) + 7000
end

function ALifeFieldRadioWindow:setTab(index)
    if FieldRadio.tabs[index] == nil then return end
    self.tab = index
    self.message = nil
    FieldRadio.fill(self)
end

function ALifeFieldRadioWindow:stepTab(delta)
    local count = #FieldRadio.tabs
    local nextIndex = self.tab + delta
    if nextIndex < 1 then nextIndex = count end
    if nextIndex > count then nextIndex = 1 end
    self:setTab(nextIndex)
end

function ALifeFieldRadioWindow:onTab(button)
    self:setTab(button.tabIndex)
end

function ALifeFieldRadioWindow:onRefresh()
    local id = FieldRadio.tabs[self.tab].id
    if id == "rep" then
        ProjectALife.StatusStore.request(getSpecificPlayer(self.playerNum))
        self:say(FieldRadio.ui("Asked the server for your standing."))
    end
    FieldRadio.fill(self)
end

function ALifeFieldRadioWindow:onShowMap()
    local row = self:selectedRow()
    if row == nil or row.contact == nil then
        self:say(FieldRadio.ui(FieldRadio.reasons.no_contact))
        return
    end
    if not ProjectALife.FieldRadioData.showOnMap(row.contact, self.playerNum) then
        self:say(FieldRadio.ui("The world map is not available right now."))
    end
end

function ALifeFieldRadioWindow:onRemoveMarker()
    local row = self:selectedRow()
    if row == nil or row.contact == nil then
        self:say(FieldRadio.ui(FieldRadio.reasons.no_contact))
        return
    end
    local ok, reason = ProjectALife.FieldRadioData.removeMarker(row.contact)
    if ok then
        self:say(FieldRadio.ui("Marker removed from your map."))
        FieldRadio.fill(self)
    else
        self:say(FieldRadio.ui(FieldRadio.reasons[reason] or "That did not work."))
    end
end

function ALifeFieldRadioWindow:onMarkRead()
    local row = self:selectedRow()
    if row == nil or row.noteRef == nil then
        self:say(FieldRadio.ui("Select a note first."))
        return
    end
    ProjectALife.FieldRadioData.markRead(row.noteRef)
    FieldRadio.fill(self)
end

function ALifeFieldRadioWindow:onMarkAll()
    ProjectALife.FieldRadioData.markAllRead()
    FieldRadio.fill(self)
end

function ALifeFieldRadioWindow:activate()
    local id = FieldRadio.tabs[self.tab].id
    if id == "contacts" then self:onShowMap()
    elseif id == "notes" then self:onMarkRead()
    else self:onRefresh() end
end

function FieldRadio.button(window, title, handler)
    local button = ISButton:new(0, 0, 10, 10, title, window, handler)
    button:initialise()
    button:instantiate()
    button.backgroundColor = FieldRadio.rgba("tabOff")
    button.backgroundColorMouseOver = FieldRadio.rgba("tabOn")
    button.borderColor = FieldRadio.rgba("accent", 0.7)
    button.textColor = FieldRadio.rgba("text", 1)
    window:addChild(button)
    return button
end

function ALifeFieldRadioWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local fontH = self.fontH
    local pad = math.max(8, math.floor(fontH * 0.6))
    local rowH = fontH + 10
    local th = self:titleBarHeight()
    self.pad, self.rowH = pad, rowH
    self.tabButtons = {}
    local gap = 4
    local tabW = math.floor((self.width - pad * 2 - gap * (#FieldRadio.tabs - 1)) / #FieldRadio.tabs)
    self.headerY = th + pad
    self.headerH = getTextManager():getFontHeight(UIFont.Large) + fontH + 22
    self.tabY = self.headerY + self.headerH + pad
    for index, tab in ipairs(FieldRadio.tabs) do
        local button = FieldRadio.button(self, FieldRadio.ui(tab.label), ALifeFieldRadioWindow.onTab)
        button:setX(pad + (index - 1) * (tabW + gap))
        button:setY(self.tabY)
        button:setWidth(tabW)
        button:setHeight(rowH)
        button.tabIndex = index
        self.tabButtons[index] = button
    end
    self.footY = self.height - pad - rowH
    self.messageY = self.footY - fontH - 6
    local listY = self.tabY + rowH + 10
    local list = ISScrollingListBox:new(pad, listY, self.width - pad * 2, self.messageY - listY - 2)
    list:initialise()
    list:instantiate()
    list.fontH, list.pad = fontH, pad
    list.font = UIFont.Small
    list.itemheight = fontH + 12
    list.drawBorder = true
    list.backgroundColor = FieldRadio.rgba("panel")
    list.borderColor = FieldRadio.rgba("line", 0.7)
    list.doDrawItem = FieldRadio.drawRow
    list.onMouseWheel = FieldRadio.onMouseWheel
    self:addChild(list)
    self.list = list
    local buttonW = math.max(96, fontH * 7)
    local x = pad
    self.refresh = FieldRadio.button(self, FieldRadio.ui("Refresh"), ALifeFieldRadioWindow.onRefresh)
    self.actions = { FieldRadio.button(self, "", ALifeFieldRadioWindow.onShowMap), FieldRadio.button(self, "", ALifeFieldRadioWindow.onRemoveMarker) }
    for _, button in ipairs({ self.refresh, self.actions[1], self.actions[2] }) do
        button:setX(x)
        button:setY(self.footY)
        button:setWidth(buttonW)
        button:setHeight(rowH)
        x = x + buttonW + 6
    end
    for _, button in ipairs({ self.refresh, self.actions[1], self.actions[2] }) do
        button.anchorTop = false
        button.anchorBottom = true
    end
    list.anchorBottom = true
    list.anchorRight = true
    self.tab = self.tab or 1
    FieldRadio.fill(self)
end

function FieldRadio.syncActions(window)
    local id = FieldRadio.tabs[window.tab].id
    local first, second = window.actions[1], window.actions[2]
    local picked = window:selectedRow() ~= nil
    first:setVisible(id == "contacts" or id == "notes")
    second:setVisible(id == "contacts" or id == "notes")
    if id == "contacts" then
        first:setTitle(FieldRadio.ui("Show on map"))
        second:setTitle(FieldRadio.ui("Remove marker"))
        second.onclick = ALifeFieldRadioWindow.onRemoveMarker
        first.onclick = ALifeFieldRadioWindow.onShowMap
    elseif id == "notes" then
        first:setTitle(FieldRadio.ui("Mark read"))
        second:setTitle(FieldRadio.ui("Mark all read"))
        first.onclick = ALifeFieldRadioWindow.onMarkRead
        second.onclick = ALifeFieldRadioWindow.onMarkAll
    end
    first:setEnable(picked)
    second:setEnable(id == "notes" or picked)
end

function FieldRadio.segments(window, x, y, count, filled, tone)
    local line = FieldRadio.theme.line
    for index = 1, count do
        local c = index <= filled and tone or line
        window:drawRect(x + (index - 1) * 7, y, 5, 8, 1, c[1], c[2], c[3])
    end
    return x + count * 7
end

function FieldRadio.measure(text)
    return getTextManager():MeasureStringX(UIFont.Small, text)
end

function FieldRadio.drawHeader(window)
    local theme, pad, fontH = FieldRadio.theme, window.pad, window.fontH
    local x, y, w, h = pad, window.headerY, window.width - pad * 2, window.headerH
    local panel, line, rose, lit = theme.panel, theme.line, theme.accent, theme.lit
    local text, dim = theme.text, theme.dim
    window:drawRect(x, y, w, h, 1, panel[1], panel[2], panel[3])
    window:drawRectBorder(x, y, w, h, 1, line[1], line[2], line[3])
    window:drawRect(x, y, 3, h, 1, rose[1], rose[2], rose[3])
    local panelModule = ProjectALife.RadioPanel
    local info = panelModule ~= nil and panelModule.readout(window.device) or nil
    local name = info ~= nil and info.name or ""
    if name == "" then name = FieldRadio.ui("Field Radio") end
    window:drawText(name, x + 14, y + 6, text[1], text[2], text[3], 1, UIFont.Medium)
    local logLabel = FieldRadio.ui("Field Radio Log")
    local rowY = y + getTextManager():getFontHeight(UIFont.Large) + 6
    window:drawText(logLabel, x + 14, rowY, rose[1], rose[2], rose[3], 1, UIFont.Small)
    local scaleY = y + h - 15
    local frac = 0
    if info ~= nil then
        local tone = info.on and lit or dim
        local freq = info.channelText
        if not info.on then freq = freq .. "  " .. FieldRadio.ui("OFF") end
        window:drawTextRight(freq, x + w - 10, y + 4, tone[1], tone[2], tone[3], 1, UIFont.Large)
        local right = x + w - 10
        if info.power ~= nil then
            right = right - 35
            FieldRadio.segments(window, right, rowY + 2, 5, math.ceil(info.power * 5), info.power > 0.2 and lit or theme.hostile)
            local label = FieldRadio.ui("BAT")
            right = right - FieldRadio.measure(label) - 6
            window:drawText(label, right, rowY, dim[1], dim[2], dim[3], 1, UIFont.Small)
            right = right - 16
        end
        right = right - 56
        FieldRadio.segments(window, right, rowY + 2, 8, math.ceil(info.volume * 8 - 0.01), tone)
        local label = FieldRadio.ui("VOL")
        right = right - FieldRadio.measure(label) - 6
        window:drawText(label, right, rowY, dim[1], dim[2], dim[3], 1, UIFont.Small)
        if info.station ~= nil then
            window:drawText(info.station, x + 14 + FieldRadio.measure(logLabel) + 12, rowY, dim[1], dim[2], dim[3], 1, UIFont.Small)
        end
        frac = info.fraction
    end
    local left, span = x + 14, w - 28
    for tick = 0, 40 do
        local tall = tick % 5 == 0
        window:drawRect(left + math.floor(span * tick / 40), scaleY + (tall and 0 or 4), 1, tall and 10 or 6, 1, dim[1], dim[2], dim[3])
    end
    local needle = left + math.floor(span * frac)
    window:drawRect(needle - 1, scaleY - 3, 2, 16, 1, lit[1], lit[2], lit[3])
end

function FieldRadio.checkReach(window)
    local device = window.device
    if device == nil or type(instanceof) ~= "function" or not instanceof(device, "IsoWaveSignal") then return end
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(window.playerNum) or nil
    if player == nil or type(device.getX) ~= "function" then return end
    if math.abs(player:getX() - device:getX()) > 10 or math.abs(player:getY() - device:getY()) > 10 then window:close() end
end

function ALifeFieldRadioWindow:prerender()
    ISCollapsableWindow.prerender(self)
    FieldRadio.checkReach(self)
    local data, store = ProjectALife.FieldRadioData, ProjectALife.StatusStore
    if self.seenRevision ~= data.revision or self.seenReputation ~= store.reputation then FieldRadio.fill(self) end
    FieldRadio.syncActions(self)
end

function ALifeFieldRadioWindow:render()
    ISCollapsableWindow.render(self)
    local l, pad = FieldRadio.theme.line, self.pad
    FieldRadio.drawHeader(self)
    local a = FieldRadio.theme.accent
    local button = self.tabButtons[self.tab]
    if button ~= nil then self:drawRect(button:getX(), self.tabY + self.rowH + 4, button:getWidth(), 2, 1, a[1], a[2], a[3]) end
    self:drawRect(pad, self.tabY + self.rowH + 5, self.width - pad * 2, 1, 0.9, l[1], l[2], l[3])
    self:drawRect(pad, self.footY - 5, self.width - pad * 2, 1, 0.5, l[1], l[2], l[3])
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    if self.message ~= nil and now < (self.messageUntil or 0) then
        local c = FieldRadio.theme.accent
        self:drawText(self.message, pad, self.messageY, c[1], c[2], c[3], 1, UIFont.Small)
    end
end

function ALifeFieldRadioWindow:onGainJoypadFocus(joypadData)
    self.joypadData = joypadData
end

function ALifeFieldRadioWindow:onLoseJoypadFocus(joypadData)
    self.joypadData = nil
end

function ALifeFieldRadioWindow:onJoypadDown(button, joypadData)
    if type(Joypad) ~= "table" then return end
    if button == Joypad.BButton then self:close()
    elseif button == Joypad.LBumper then self:stepTab(-1)
    elseif button == Joypad.RBumper then self:stepTab(1)
    elseif button == Joypad.AButton then self:activate()
    elseif button == Joypad.XButton and FieldRadio.tabs[self.tab].id == "contacts" then self:onRemoveMarker()
    elseif button == Joypad.YButton then self:onRefresh() end
end

function ALifeFieldRadioWindow:onJoypadDirUp()
    if FieldRadio.scrollLong(self.list, -1) then return end
    if self.list ~= nil and type(self.list.onJoypadDirUp) == "function" then self.list:onJoypadDirUp() end
end

function ALifeFieldRadioWindow:onJoypadDirDown()
    if FieldRadio.scrollLong(self.list, 1) then return end
    if self.list ~= nil and type(self.list.onJoypadDirDown) == "function" then self.list:onJoypadDirDown() end
end

function ALifeFieldRadioWindow:onJoypadDirLeft()
    self:stepTab(-1)
end

function ALifeFieldRadioWindow:onJoypadDirRight()
    self:stepTab(1)
end

function ALifeFieldRadioWindow:close()
    if self.joypadData ~= nil and type(setJoypadFocus) == "function" then setJoypadFocus(self.playerNum, nil) end
    self:setVisible(false)
    self:removeFromUIManager()
    ALifeFieldRadioWindow.instance = nil
end

function ALifeFieldRadioWindow:new(playerNum)
    local core = getCore()
    local fontH = FieldRadio.fontHeight()
    local width = math.min(core:getScreenWidth() - 40, math.max(580, fontH * 42))
    local height = math.min(core:getScreenHeight() - 40, math.max(500, fontH * 38))
    local x = math.max(20, math.floor((core:getScreenWidth() - width) / 2))
    local y = math.max(20, math.floor((core:getScreenHeight() - height) / 2))
    local window = ISCollapsableWindow.new(self, x, y, width, height)
    window.playerNum = playerNum
    window.fontH = fontH
    window.resizable = false
    window.tab = 1
    window.backgroundColor = FieldRadio.rgba("bg")
    window.borderColor = FieldRadio.rgba("line")
    window:setTitle(FieldRadio.ui("A-Life Radio"))
    return window
end

function ALifeFieldRadioWindow.show(playerNum, device)
    playerNum = playerNum or 0
    local current = ALifeFieldRadioWindow.instance
    if current ~= nil then
        if current.device == device then
            current:close()
            return false
        end
        current.device = device
        return true
    end
    if type(getSpecificPlayer) ~= "function" or getSpecificPlayer(playerNum) == nil then return false end
    local window = ALifeFieldRadioWindow:new(playerNum)
    window.device = device
    window:initialise()
    window:addToUIManager()
    ALifeFieldRadioWindow.instance = window
    local state = type(JoypadState) == "table" and type(JoypadState.players) == "table" and JoypadState.players[playerNum + 1] or nil
    if state ~= nil and type(setJoypadFocus) == "function" then setJoypadFocus(playerNum, window) end
    ProjectALife.StatusStore.request(getSpecificPlayer(playerNum))
    return true
end

return ALifeFieldRadioWindow
