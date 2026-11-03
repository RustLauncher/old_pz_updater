require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeRepLevels"
require "ProjectALife/Records/ALifeRepIcons"

ProjectALife = ProjectALife or {}

local Levels = ProjectALife.RepLevels
local Icons = ProjectALife.RepIcons
local Tab = {
    wrapped = false,
    pad = 10,
    minWidth = 470,
    unknown = "???",
    requestGapMs = 4000,
    refreshMs = 45000,
    requestLastMs = -1000000,
    theme = {
        card = { 0.024, 0.030, 0.034 },
        panel = { 0.017, 0.022, 0.026 },
        line = { 0.14, 0.17, 0.18 },
        accent = { 0.34, 0.52, 0.57 },
        text = { 0.80, 0.82, 0.80 },
        dim = { 0.47, 0.52, 0.51 },
        locked = { 0.085, 0.095, 0.110 },
    },
    faultLimit = 3,
    metrics = { attached = 0, detached = 0, rebuilt = 0, refused = 0, faults = 0 },
}
ProjectALife.RepTab = Tab

function Tab.rgba(name, alpha)
    local source = Tab.theme[name] or Tab.theme.text
    return { r = source[1], g = source[2], b = source[3], a = alpha or 1 }
end

function Tab.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Tab.wanted()
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.repTabOn) == "function" then return prefs.repTabOn() == true end
    return true
end

function Tab.title()
    return ProjectALife.Text.ui("Reputation")
end

function Tab.fonts()
    local manager = getTextManager()
    return manager:getFontHeight(UIFont.Small), manager:getFontHeight(UIFont.Medium), manager
end

function Tab.contentHeight(playerNum)
    local screen = 768
    if type(getPlayerScreenHeight) == "function" and playerNum ~= nil then
        screen = getPlayerScreenHeight(playerNum)
    elseif type(getCore) == "function" then
        screen = getCore():getScreenHeight()
    end
    return math.max(430, math.min(540, (tonumber(screen) or 768) - 240))
end

function Tab.wrapText(text, width)
    local screen = ProjectALife.RepScreen
    local manager = getTextManager()
    if screen ~= nil and type(screen.lines) == "function" then
        return screen.lines(text, math.max(60, width), UIFont.Small, manager)
    end
    return { text }
end

function Tab.segments(x, width)
    local rows = Levels.rows
    local first, last = Levels.scoreMin, Levels.scoreMax + 1
    local span = last - first
    local list = {}
    for index = 1, #rows do
        local from = first
        if index > 1 then from = rows[index].min end
        local to = last
        if rows[index + 1] ~= nil then to = rows[index + 1].min end
        local left = x + math.floor((from - first) / span * width + 0.5)
        local right = x + math.floor((to - first) / span * width + 0.5)
        list[index] = { index = index, x = left, w = math.max(1, right - left) }
    end
    return list
end

function Tab.markerX(score, x, width)
    local value = Levels.clamp(score)
    return x + math.floor((value - Levels.scoreMin) / (Levels.scoreMax - Levels.scoreMin) * width + 0.5)
end

function Tab.levelCenter(index, x, width)
    local low, high = Levels.rangeOf(index)
    if low == nil then return x end
    return Tab.markerX((low + high) / 2, x, width)
end

function Tab.rowFor(entry, textWidth, fontS, fontM)
    local row = { entry = entry, index = entry.index, id = entry.id, unlocked = entry.unlocked, current = entry.current }
    if entry.unlocked then
        local blurb = Levels.blurb(entry.id)
        row.title = Levels.name(entry.id)
        row.range = Icons.rangeText(entry.index)
        row.lines = {}
        if blurb ~= nil then row.lines = Tab.wrapText(ProjectALife.Text.ui(blurb), textWidth) end
        row.height = math.max(50, 10 + fontM + 3 + #row.lines * fontS + 9)
        if row.current then row.height = row.height + fontS + 3 end
        row.tone = Icons.color(entry.index, 1, 0.25)
    else
        row.title, row.range, row.lines = Tab.unknown, Tab.unknown, {}
        row.height = 44
        row.tone = nil
    end
    return row
end

function Tab.snapshot(view)
    local store = ProjectALife.StatusStore
    local reputation = nil
    if store ~= nil then reputation = store.reputation end
    if view.data ~= nil and view.seenReputation == reputation and view.seenWidth == view.width then return view.data end
    view.seenReputation, view.seenWidth = reputation, view.width
    local data = { reputation = reputation }
    local personal = nil
    if type(reputation) == "table" then personal = reputation.personal end
    if type(reputation) ~= "table" then
        data.status = "waiting"
    elseif type(personal) ~= "table" or Levels.indexOf(personal.level) == nil then
        data.status = "off"
    else
        data.status = "ok"
        data.level = personal.level
        data.index = Levels.indexOf(personal.level)
        data.score = tonumber(personal.score)
        data.entries, data.lo, data.hi = Icons.entries(personal)
        data.humans = tonumber(reputation.humans)
        data.tones = {}
        for index = 1, #data.entries do data.tones[index] = Icons.color(index, 1, 0.12) end
    end
    view.data = data
    Tab.fill(view, data)
    Tab.metrics.rebuilt = Tab.metrics.rebuilt + 1
    return data
end

function Tab.fill(view, data)
    local list = view.list
    if list == nil then return false end
    list:clear()
    Tab.fitList(view, Tab.layout(view))
    if data.status ~= "ok" then return true end
    local fontS, fontM = Tab.fonts()
    local textWidth = list:getWidth() - 54 - 14 - 22
    for _, entry in ipairs(data.entries) do
        local row = Tab.rowFor(entry, textWidth, fontS, fontM)
        local item = list:addItem(row.title, row)
        item.height = row.height
    end
    return true
end

function Tab.localHumans(view)
    local player = nil
    if type(getSpecificPlayer) == "function" then player = getSpecificPlayer(tonumber(view.playerNum) or 0) end
    if player == nil or type(player.hasModData) ~= "function" or player:hasModData() ~= true then return 0 end
    local data = player:getModData()
    if type(data) ~= "table" then return 0 end
    return math.max(0, math.floor(tonumber(data.palHumansKilled) or 0))
end

function Tab.counts(view, data)
    local humans = data.humans
    if humans == nil then humans = Tab.localHumans(view) end
    local zombies = 0
    local player = nil
    if type(getSpecificPlayer) == "function" then player = getSpecificPlayer(tonumber(view.playerNum) or 0) end
    if player ~= nil and type(player.getZombieKills) == "function" then zombies = tonumber(player:getZombieKills()) or 0 end
    return humans, zombies
end

function Tab.layout(view)
    local fontS, fontM = Tab.fonts()
    local key = tostring(view.width) .. ":" .. tostring(view.contentH) .. ":" .. tostring(fontS) .. ":" .. tostring(fontM)
    local geo = view.geo
    if geo ~= nil and geo.key == key then return geo end
    local pad = Tab.pad
    local width = view.width
    geo = { fontS = fontS, fontM = fontM }
    geo.hx, geo.hy, geo.hw, geo.hh = pad, pad, width - pad * 2, math.max(50, fontM + fontS + 16)
    local y = geo.hy + geo.hh + 8
    geo.bx, geo.by, geo.bw = pad, y, width - pad * 2
    geo.flagH = fontS + 4
    geo.barX, geo.barW = pad + 12, width - pad * 2 - 24
    geo.barY = y + geo.flagH + 9
    geo.barH = 16
    geo.tickY = geo.barY + geo.barH + 4
    geo.bh = geo.tickY + fontS + 6 - y
    geo.segments = Tab.segments(geo.barX, geo.barW)
    y = y + geo.bh + 8
    geo.sy, geo.sh = y, fontS + 14
    y = y + geo.sh + 8
    geo.noteY = y
    geo.noteLines = Tab.wrapText(ProjectALife.Text.ui("Your name travels. People react to what they have heard about you."), width - pad * 2 - 4)
    y = y + #geo.noteLines * fontS + 4
    geo.noteExtraY = y
    y = y + fontS + 8
    geo.ly = y
    if view.contentH < y + 90 + pad then view.contentH = y + 90 + pad end
    geo.lh = view.contentH - y - pad
    geo.key = tostring(view.width) .. ":" .. tostring(view.contentH) .. ":" .. tostring(fontS) .. ":" .. tostring(fontM)
    view.geo = geo
    return geo
end

function Tab.fitList(view, geo)
    local list = view.list
    if list == nil then return false end
    local width = view.width - Tab.pad * 2
    if list:getX() ~= Tab.pad or list:getY() ~= geo.ly or list:getWidth() ~= width or list:getHeight() ~= geo.lh then
        list:setX(Tab.pad)
        list:setY(geo.ly)
        list:setWidth(width)
        list:setHeight(geo.lh)
    end
    return true
end

function Tab.drawHeader(view, geo, data)
    local theme = Tab.theme
    local card, line, dim = theme.card, theme.line, theme.dim
    view:drawRect(geo.hx, geo.hy, geo.hw, geo.hh, 0.96, card[1], card[2], card[3])
    view:drawRectBorder(geo.hx, geo.hy, geo.hw, geo.hh, 1, line[1], line[2], line[3])
    if data.status ~= "ok" then
        local message = ProjectALife.Text.ui("Waiting for the server...")
        if data.status == "off" then
            message = ProjectALife.Text.ui("Reputation tracking is off. Turn on Track personal reputation in the sandbox options.")
        end
        local lines = Tab.wrapText(message, geo.hw - 24)
        for index, row in ipairs(lines) do
            view:drawText(row, geo.hx + 12, geo.hy + 8 + (index - 1) * geo.fontS, dim[1], dim[2], dim[3], 1, UIFont.Small)
        end
        return
    end
    local tone = data.tones[data.index]
    view:drawRect(geo.hx, geo.hy, 4, geo.hh, 1, tone.r, tone.g, tone.b)
    local texture = Icons.texture(data.level)
    local iconY = geo.hy + math.floor((geo.hh - 32) / 2)
    if texture ~= nil then
        view:drawTextureScaled(texture, geo.hx + 14, iconY, 32, 32, 1, 1, 1, 1)
    else
        view:drawRect(geo.hx + 14, iconY, 32, 32, 1, tone.r, tone.g, tone.b)
    end
    local x = geo.hx + 56
    view:drawText(ProjectALife.Text.ui("Your reputation"), x, geo.hy + 5, dim[1], dim[2], dim[3], 1, UIFont.Small)
    view:drawText(Levels.name(data.level), x, geo.hy + 5 + geo.fontS, tone.r, tone.g, tone.b, 1, UIFont.Medium)
    if data.score ~= nil then
        local number = Icons.signed(data.score)
        view:drawTextRight(number, geo.hx + geo.hw - 14, geo.hy + 5, tone.r, tone.g, tone.b, 1, UIFont.Medium)
        view:drawTextRight(ProjectALife.Text.ui("on a scale from -100 to +100"), geo.hx + geo.hw - 14, geo.hy + 5 + geo.fontM, dim[1], dim[2], dim[3], 1, UIFont.Small)
    end
end

function Tab.drawBar(view, geo, data)
    local theme = Tab.theme
    local card, line, locked, dim = theme.card, theme.line, theme.locked, theme.dim
    view:drawRect(geo.bx, geo.by, geo.bw, geo.bh, 0.96, card[1], card[2], card[3])
    view:drawRectBorder(geo.bx, geo.by, geo.bw, geo.bh, 1, line[1], line[2], line[3])
    local ok = data.status == "ok"
    for index, segment in ipairs(geo.segments) do
        local entry = ok and data.entries[index] or nil
        local width = math.max(1, segment.w - 1)
        if entry ~= nil and entry.unlocked then
            local tone = data.tones[index]
            local alpha = 0.85
            if entry.current then alpha = 1 end
            view:drawRect(segment.x, geo.barY, width, geo.barH, alpha, tone.r, tone.g, tone.b)
        else
            view:drawRect(segment.x, geo.barY, width, geo.barH, 1, locked[1], locked[2], locked[3])
            if width >= 12 then
                view:drawTextCentre(Tab.unknown, segment.x + width / 2, geo.barY + math.floor((geo.barH - geo.fontS) / 2), dim[1], dim[2], dim[3], 0.8, UIFont.Small)
            end
        end
    end
    view:drawText(Tab.signedTick(-1), geo.barX, geo.tickY, dim[1], dim[2], dim[3], 1, UIFont.Small)
    view:drawTextRight(Tab.signedTick(1), geo.barX + geo.barW, geo.tickY, dim[1], dim[2], dim[3], 1, UIFont.Small)
    local zeroX = Tab.markerX(0, geo.barX, geo.barW)
    view:drawTextCentre("0", zeroX, geo.tickY, dim[1], dim[2], dim[3], 1, UIFont.Small)
    view:drawRect(zeroX, geo.barY + geo.barH, 1, 3, 1, dim[1], dim[2], dim[3])
    if not ok then return end
    local tone = data.tones[data.index]
    local markerX = Tab.levelCenter(data.index, geo.barX, geo.barW)
    local label = nil
    if data.score ~= nil then
        markerX = Tab.markerX(data.score, geo.barX, geo.barW)
        label = Icons.signed(data.score)
    end
    local current = geo.segments[data.index]
    view:drawRectBorder(current.x - 1, geo.barY - 1, math.max(1, current.w - 1) + 2, geo.barH + 2, 1, 1, 1, 1)
    view:drawRect(markerX, geo.barY - 3, 2, geo.barH + 6, 1, 1, 1, 1)
    if label ~= nil then
        local manager = getTextManager()
        local flagW = manager:MeasureStringX(UIFont.Small, label) + 12
        local flagX = math.min(math.max(markerX - math.floor(flagW / 2), geo.barX), geo.barX + geo.barW - flagW)
        local flagY = geo.barY - geo.flagH - 6
        view:drawRect(flagX, flagY, flagW, geo.flagH, 1, tone.r * 0.55, tone.g * 0.55, tone.b * 0.55)
        view:drawRectBorder(flagX, flagY, flagW, geo.flagH, 1, tone.r, tone.g, tone.b)
        view:drawTextCentre(label, flagX + flagW / 2, flagY + 2, 1, 1, 1, 1, UIFont.Small)
        for step = 0, 3 do
            view:drawRect(markerX - (3 - step) + 1, flagY + geo.flagH + step, (3 - step) * 2, 1, 1, tone.r, tone.g, tone.b)
        end
    end
end

function Tab.signedTick(side)
    if side < 0 then return Icons.signed(Levels.scoreMin) end
    return Icons.signed(Levels.scoreMax)
end

function Tab.drawStats(view, geo, data)
    local theme = Tab.theme
    local card, line, text, dim = theme.card, theme.line, theme.text, theme.dim
    local humans, zombies = Tab.counts(view, data)
    local gap = 8
    local cell = math.floor((geo.hw - gap) / 2)
    local cells = {
        { label = ProjectALife.Text.ui("Humans killed"), value = tostring(humans) },
        { label = ProjectALife.Text.ui("Zombies killed"), value = tostring(zombies) },
    }
    for index, entry in ipairs(cells) do
        local x = geo.hx + (index - 1) * (cell + gap)
        view:drawRect(x, geo.sy, cell, geo.sh, 0.96, card[1], card[2], card[3])
        view:drawRectBorder(x, geo.sy, cell, geo.sh, 1, line[1], line[2], line[3])
        view:drawText(entry.label, x + 10, geo.sy + 7, dim[1], dim[2], dim[3], 1, UIFont.Small)
        view:drawTextRight(entry.value, x + cell - 10, geo.sy + 7, text[1], text[2], text[3], 1, UIFont.Small)
    end
end

function Tab.drawNote(view, geo, data)
    local dim = Tab.theme.dim
    for index, row in ipairs(geo.noteLines) do
        view:drawText(row, geo.hx + 2, geo.noteY + (index - 1) * geo.fontS, dim[1], dim[2], dim[3], 1, UIFont.Small)
    end
    if data.status == "ok" then
        local known = data.hi - data.lo + 1
        local extra = ProjectALife.Text.ui("Levels you have not reached stay hidden. Known: {known} of {total}.",
            { known = tostring(known), total = tostring(Levels.count()) })
        view:drawText(extra, geo.hx + 2, geo.noteExtraY, dim[1], dim[2], dim[3], 0.85, UIFont.Small)
    end
end

function Tab.drawRow(list, y, item, alt)
    local row = item.item
    if type(row) ~= "table" then return y + (item.height or list.itemheight) end
    local height = row.height
    local scroll = list:getYScroll()
    if y + scroll + height < 0 or y + scroll >= list.height then return y + height end
    local theme = Tab.theme
    local line, text, dim, locked = theme.line, theme.text, theme.dim, theme.locked
    local width = list:getWidth()
    local right = width - 22
    local hover = list.mouseoverselected == item.index and list:isMouseOver()
    if hover and type(list.isMouseOverScrollBar) == "function" and list:isMouseOverScrollBar() then hover = false end
    local tone = row.tone
    if row.current and tone ~= nil then
        list:drawRect(0, y, width, height - 1, 0.16, tone.r, tone.g, tone.b)
    elseif hover then
        list:drawRect(0, y, width, height - 1, 0.07, 1, 1, 1)
    end
    if tone ~= nil then
        local alpha = 0.5
        if row.current then alpha = 1 end
        list:drawRect(0, y, 3, height - 1, alpha, tone.r, tone.g, tone.b)
    else
        list:drawRect(0, y, 3, height - 1, 0.6, line[1], line[2], line[3])
    end
    local texture = Icons.texture(row.unlocked and row.id or nil)
    local iconY = y + math.floor((height - 32) / 2)
    if texture ~= nil then
        list:drawTextureScaled(texture, 12, iconY, 32, 32, 1, 1, 1, 1)
    else
        list:drawRect(12, iconY, 32, 32, 1, locked[1] + 0.1, locked[2] + 0.1, locked[3] + 0.1)
    end
    local fontM = list.fontM
    if row.unlocked then
        list:drawText(row.title, 54, y + 6, tone.r, tone.g, tone.b, 1, UIFont.Medium)
        list:drawTextRight(row.range, right, y + 7, dim[1], dim[2], dim[3], 1, UIFont.Small)
        if row.current then
            list:drawTextRight(ProjectALife.Text.ui("You are here"), right, y + height - list.fontS - 8, tone.r, tone.g, tone.b, 1, UIFont.Small)
        end
        for index, rowLine in ipairs(row.lines) do
            list:drawText(rowLine, 54, y + 6 + fontM + 3 + (index - 1) * list.fontS, text[1], text[2], text[3], 0.92, UIFont.Small)
        end
    else
        list:drawText(row.title, 54, y + math.floor((height - fontM) / 2), dim[1], dim[2], dim[3], 0.9, UIFont.Medium)
        list:drawTextRight(row.range, right, y + math.floor((height - list.fontS) / 2), dim[1], dim[2], dim[3], 0.7, UIFont.Small)
    end
    list:drawRect(10, y + height - 1, width - 20, 1, 0.5, line[1], line[2], line[3])
    return y + height
end

function Tab.build(view)
    local fontS, fontM = Tab.fonts()
    local pad = Tab.pad
    local geo = Tab.layout(view)
    local list = ISScrollingListBox:new(pad, geo.ly, view.width - pad * 2, geo.lh)
    list:initialise()
    list:instantiate()
    list.fontS, list.fontM = fontS, fontM
    list.font = UIFont.Small
    list.itemheight = 44
    list.drawBorder = true
    list.backgroundColor = Tab.rgba("panel", 0.96)
    list.borderColor = Tab.rgba("line", 1)
    list.selectionColor = Tab.rgba("accent", 0.0)
    list.mouseOverHighlightColor = Tab.rgba("text", 0.0)
    list.doDrawItem = Tab.drawRow
    list.selected = -1
    view:addChild(list)
    view.list = list
    return list
end

function Tab.ask(view, now, force)
    local store = ProjectALife.StatusStore
    if store == nil or type(store.request) ~= "function" then return false end
    if force ~= true and now - Tab.requestLastMs < Tab.requestGapMs then return false end
    if now - Tab.requestLastMs < 1500 then return false end
    local player = nil
    if type(getSpecificPlayer) == "function" then player = getSpecificPlayer(tonumber(view.playerNum) or 0) end
    if player == nil then return false end
    Tab.requestLastMs = now
    local ok = pcall(store.request, player)
    return ok
end

function Tab.opened(view, now)
    view.scrollPending = true
    view.askedAt = now
    Tab.ask(view, now, true)
end

function Tab.scrollToCurrent(view, data)
    local list = view.list
    if list == nil or data.status ~= "ok" or #list.items == 0 then return false end
    if type(list.topOfItem) ~= "function" or type(list.setYScroll) ~= "function" then return false end
    local top = list:topOfItem(data.index)
    local item = list.items[data.index]
    if top < 0 or item == nil then return false end
    local maxScroll = math.max(0, list:getScrollHeight() - list:getHeight())
    local target = math.min(maxScroll, math.max(0, top - math.floor((list:getHeight() - item.height) / 2)))
    list:setYScroll(-target)
    return true
end

function Tab.prerender(view)
    local now = Tab.nowMs()
    local fresh = view.lastFrameMs == nil or now - view.lastFrameMs > 400
    view.lastFrameMs = now
    if fresh then Tab.opened(view, now) end
    local data = Tab.snapshot(view)
    if data.status ~= "ok" then
        Tab.ask(view, now, false)
    elseif now - (view.askedAt or now) >= Tab.refreshMs then
        view.askedAt = now
        Tab.ask(view, now, false)
    end
end

function Tab.render(view)
    local geo = Tab.layout(view)
    local data = Tab.snapshot(view)
    Tab.fitList(view, geo)
    Tab.drawHeader(view, geo, data)
    Tab.drawBar(view, geo, data)
    Tab.drawStats(view, geo, data)
    Tab.drawNote(view, geo, data)
    if view.scrollPending == true and view.list ~= nil and view.list:getScrollHeight() > 0 then
        view.scrollPending = false
        Tab.scrollToCurrent(view, data)
    end
    Tab.size(view)
end

function Tab.size(view)
    if type(view.setWidthAndParentWidth) == "function" then view:setWidthAndParentWidth(view.width) end
    if type(view.setHeightAndParentHeight) == "function" then view:setHeightAndParentHeight(view.contentH) end
end

function Tab.fault(view, failure)
    view.faults = (view.faults or 0) + 1
    Tab.metrics.faults = Tab.metrics.faults + 1
    print("[ALIFE-REP] reputation tab fault " .. tostring(view.faults) .. ": " .. tostring(failure))
    if view.faults >= Tab.faultLimit then view.disabled = true end
end

function Tab.viewClass()
    if Tab.View ~= nil then return Tab.View end
    if type(ISPanel) ~= "table" or type(ISPanel.derive) ~= "function" then return nil end
    local View = ISPanel:derive("ALifeRepTab")
    function View:new(x, y, width, height, playerNum)
        local o = ISPanel.new(self, x, y, width, height)
        o.playerNum = playerNum or 0
        o.contentH = height
        o.background = false
        return o
    end
    function View:createChildren()
        Tab.build(self)
    end
    function View:prerender()
        if self.disabled == true then return end
        local ok, failure = pcall(Tab.prerender, self)
        if not ok then Tab.fault(self, failure) end
    end
    function View:render()
        if self.disabled == true then
            Tab.size(self)
            return
        end
        local ok, failure = pcall(Tab.render, self)
        if not ok then Tab.fault(self, failure) end
    end
    Tab.View = View
    return View
end

function Tab.widen(window, need)
    local panel = window.panel
    for _, entry in ipairs(panel.viewList) do
        local view = entry.view
        if type(view) == "table" then
            if type(view.setWidth) == "function" and (tonumber(view.width) or 0) < need then view:setWidth(need) end
            if tonumber(view.tabtotalwidth) ~= nil and view.tabtotalwidth < need then view.tabtotalwidth = need end
        end
    end
    if type(panel.setWidth) == "function" and (tonumber(panel.width) or 0) < need then panel:setWidth(need) end
    if type(window.setWidth) == "function" and (tonumber(window.width) or 0) < need then window:setWidth(need) end
end

function Tab.attach(window)
    if type(window) ~= "table" or window.alifeRepView ~= nil then return false end
    local panel = window.panel
    if type(panel) ~= "table" or type(panel.addView) ~= "function" or type(panel.viewList) ~= "table" then
        Tab.metrics.refused = Tab.metrics.refused + 1
        return false
    end
    if not Tab.wanted() then return false end
    local class = Tab.viewClass()
    if class == nil then
        Tab.metrics.refused = Tab.metrics.refused + 1
        return false
    end
    local width = math.max(Tab.minWidth, tonumber(panel.width) or 0)
    local view = class:new(0, 0, width, Tab.contentHeight(window.playerNum), window.playerNum)
    view:initialise()
    panel:addView(Tab.title(), view)
    window.alifeRepView = view
    if type(panel.getWidthOfAllTabs) == "function" then
        local need = panel:getWidthOfAllTabs() + 2
        Tab.widen(window, need)
        if need > view.width then view:setWidth(need) end
    end
    Tab.metrics.attached = Tab.metrics.attached + 1
    return true
end

function Tab.detach(window)
    local view = type(window) == "table" and window.alifeRepView or nil
    if view == nil then return false end
    local panel = window.panel
    if type(panel) ~= "table" or type(panel.removeView) ~= "function" then return false end
    local first = type(panel.viewList) == "table" and panel.viewList[1] or nil
    if type(panel.getActiveView) == "function" and panel:getActiveView() == view
            and first ~= nil and type(panel.activateView) == "function" then
        panel:activateView(first.name)
    end
    panel:removeView(view)
    window.alifeRepView = nil
    Tab.metrics.detached = Tab.metrics.detached + 1
    return true
end

function Tab.windows()
    local list = {}
    if type(getPlayerInfoPanel) ~= "function" then return list end
    local count = 1
    if type(getNumActivePlayers) == "function" then count = math.max(1, getNumActivePlayers()) end
    for index = 0, count - 1 do
        local ok, window = pcall(getPlayerInfoPanel, index)
        if ok and window ~= nil then list[#list + 1] = window end
    end
    return list
end

function Tab.apply()
    local changed = 0
    local wanted = Tab.wanted()
    for _, window in ipairs(Tab.windows()) do
        local done
        if wanted then done = Tab.attach(window) else done = Tab.detach(window) end
        if done then changed = changed + 1 end
    end
    return changed
end

function Tab.wrap()
    if Tab.wrapped then return true end
    local class = ISCharacterInfoWindow
    if type(class) ~= "table" or type(class.createChildren) ~= "function" then return false end
    local original = class.createChildren
    class.createChildren = function(self, ...)
        original(self, ...)
        pcall(Tab.attach, self)
    end
    Tab.wrapped = true
    return true
end

function Tab.install()
    Tab.wrap()
    return Tab.apply()
end

Tab.wrap()
if type(Events) == "table" and Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Tab.install)
end
if type(Events) == "table" and Events.OnCreatePlayer ~= nil and type(Events.OnCreatePlayer.Add) == "function" then
    Events.OnCreatePlayer.Add(Tab.install)
end

return Tab
