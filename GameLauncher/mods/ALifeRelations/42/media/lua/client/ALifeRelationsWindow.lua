require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ALifeRelations"

local M = ALifeRelations
local Window = ISCollapsableWindow:derive("ALifeRelationsWindow")
M.Window = Window

-- Looks like A-Life's conversation window (ALifeTalkMenu.lua). Sizes follow the font, so large UI fonts fit.
local MARGIN, GAP = 16, 20
local HEAD = { 0.81, 0.86, 0.67 } -- A-Life's NPC name
local TEXT = { 0.88, 0.88, 0.82 } -- A-Life's transcript text
local DIM = { 0.55, 0.61, 0.54 } -- A-Life's faction line

local function rgba(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Cuts text to fit width, ending in "...".
local function fit(text, font, width)
    local measure = getTextManager()
    if measure:MeasureStringX(font, text) <= width then return text end
    while #text > 1 and measure:MeasureStringX(font, text .. "...") > width do text = string.sub(text, 1, -2) end
    return text .. "..."
end

-- Cached per width, so resizing the window refits.
local function fitName(row, font, width)
    if row.fitWidth ~= width then row.shortName, row.fitWidth = fit(row.name, font, width), width end
    return row.shortName
end

local function nextOf(list, current)
    for i, value in ipairs(list) do
        if value == current then return list[i % #list + 1] end
    end
    return list[1]
end

-- Built at draw time so a provoked grudge's "5h left" keeps counting down.
local function statusText(row, now)
    if row.change then return row.change end -- a standing event: "+12"
    if row.points then return row.label .. string.format(" %+d", row.points) end
    local cause = M.causeText(row.cause, row.causeAt, now)
    return row.status .. (cause and (" (" .. tostring(cause) .. ")") or "")
end

-- Kills view: the count; history: when it changed; otherwise when we last saw the faction.
local function noteText(row, now)
    return row.kills and tostring(row.kills)
        or row.atHours and M.ago(now - row.atHours)
        or row.seenAt and ("seen " .. M.ago(now - row.seenAt))
end

-- Spreads a row of buttons evenly across the window, like A-Life's topic tabs.
local function spread(buttons, width)
    local shown = {}
    for _, button in ipairs(buttons) do
        if button:getIsVisible() then shown[#shown + 1] = button end
    end
    local each = (width - 2 * MARGIN) / math.max(2, #shown) -- a lone Show: button keeps its half width
    for i, button in ipairs(shown) do
        button:setX(MARGIN + (i - 1) * each)
        button:setWidth(each - 4)
    end
end

function Window:addButton(y, title, onClick)
    local button = ISButton:new(MARGIN, y, 10, self.rowHeight, title, self, onClick)
    button:initialise()
    button:instantiate()
    button.backgroundColor, button.borderColor = rgba(0.055, 0.068, 0.054, 0.95), rgba(0.22, 0.28, 0.2, 1)
    self:addChild(button)
    return button
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.backgroundColor, self.borderColor = rgba(0.035, 0.042, 0.038, 0.97), rgba(0.34, 0.39, 0.31, 1)
    local text = getTextManager()
    local small = text:getFontHeight(UIFont.Small)
    self.rowHeight = math.max(27, small + 12) -- A-Life's button height
    self.headingY = self:titleBarHeight() + 8
    self.countsY = self.headingY + text:getFontHeight(UIFont.Medium) + 4
    self.stepHeight, self.shift = small + 2, 0
    local tabsY = self.countsY + small + 10
    local toolsY = tabsY + self.rowHeight + 6
    self.tabsY, self.toolsY = tabsY, toolsY
    self.tabs = {}
    local modes = { "factions", "blocs", "history", "kills" }
    -- With Jeem Extension, its standing points come first (the window still opens on Factions).
    if M.hasStanding() then table.insert(modes, 1, "standing") end
    for _, mode in ipairs(modes) do
        local tab = self:addButton(tabsY, (mode:gsub("^%l", string.upper)), Window.onTab)
        tab.mode = mode
        self.tabs[#self.tabs + 1] = tab
    end
    -- Tags and map marks are switched in Options > Mods, not here.
    self.filterButton = self:addButton(toolsY, "Show: " .. self.filter, Window.onFilter)
    self.back = self:addButton(toolsY, "< Back", Window.onBack)
    self.tools = { self.filterButton, self.back }
    local top = toolsY + self.rowHeight + 8
    self.listTop = top
    self.list = ISScrollingListBox:new(MARGIN, top, self.width - 2 * MARGIN, self.height - top - MARGIN)
    self.list:initialise()
    self.list:instantiate()
    self.list:setFont("Small", 4)
    self.list.drawBorder = true
    self.list.backgroundColor, self.list.borderColor = rgba(0.015, 0.02, 0.017, 0.85), rgba(0.2, 0.25, 0.2, 1)
    self.list.selectionColor = rgba(0.34, 0.39, 0.31, 0.35)
    self.list.statusWidth, self.list.noteWidth = 0, 0
    self.list:setAnchorRight(true)
    self.list:setAnchorBottom(true)
    self.list.doDrawItem = Window.drawRow
    self.list:setOnMouseDownFunction(self, Window.onPick)
    self:addChild(self.list)
end

function Window:rebuild()
    self.dirty = false
    local player = getSpecificPlayer(self.playerNum)
    local now = getGameTime():getWorldAgeHours()
    local seen = M.seen(player)
    local rows
    self.why = nil
    if self.subject and self.mode ~= "blocs" and self.mode ~= "standing" then
        -- A faction's page: why it treats you so (under the heading), and how it treats the other factions.
        local status, cause, causeAt, steps = M.whyRows(self.subject, player, now, M.standing)
        self.why = { status = status, cause = cause, causeAt = causeAt, steps = steps }
        rows = M.rows(self.subject, player, now, seen)
    elseif self.mode == "blocs" then
        rows = M.blocRows(self.subject, player, now, seen)
    elseif self.mode == "history" then
        rows = M.historyRows(M.history(player))
    elseif self.mode == "kills" then
        rows = M.killRows(M.kills, player, now, seen)
    elseif self.mode == "standing" then
        rows = self.subject and M.standingEvents(self:standingEntry()) or M.standingRows(M.standing, seen)
    else
        rows = M.rows(self.subject, player, now, seen)
    end
    self.counts = {}
    self.list:clear()
    -- Status and note columns are as wide as their widest text; names get the rest.
    local measure, font = getTextManager(), self.list.font
    self.list.statusWidth, self.list.noteWidth = 0, 0
    for _, row in ipairs(rows) do
        local word = row.label or row.status -- standing rows count allied apart from friendly
        self.counts[word] = (self.counts[word] or 0) + 1
        if row.seenAt then self.counts.met = (self.counts.met or 0) + 1 end
        self.counts.kills = (self.counts.kills or 0) + (row.kills or 0)
        self.list.statusWidth = math.max(self.list.statusWidth, measure:MeasureStringX(font, statusText(row, now)))
        local note = noteText(row, now)
        if note then self.list.noteWidth = math.max(self.list.noteWidth, measure:MeasureStringX(font, note)) end
        -- Standing has no filter: the point is to see every faction you have points with, plus and minus.
        local shown = self.mode == "standing" or self.filter == "all" or self.filter == row.status
            or (self.filter == "met" and row.seenAt ~= nil)
        if shown then self.list:addItem(row.name, row) end
    end
    -- Standing rows draw a bar where the note goes.
    if self.mode == "standing" and self.subject == nil then self.list.noteWidth = measure:getFontHeight(font) * 10 end
    self.back:setVisible(self.subject ~= nil)
    self.filterButton:setVisible(self.mode ~= "standing")
    spread(self.tools, self.width)
    self:makeRoom(self.why and #self.why.steps or 0)
    for _, tab in ipairs(self.tabs) do
        local on = tab.mode == self.mode
        tab.backgroundColor = on and rgba(0.14, 0.17, 0.12, 1) or rgba(0.055, 0.068, 0.054, 0.95)
        tab.borderColor = on and rgba(0.34, 0.39, 0.31, 1) or rgba(0.22, 0.28, 0.2, 1)
        tab.textColor = on and rgba(HEAD[1], HEAD[2], HEAD[3], 1) or rgba(1, 1, 1, 1)
    end
end

local function drawStatus(list, text, status, x, y)
    local color = M.COLORS[status]
    list:drawText(text, x, y, color[1], color[2], color[3], 1, list.font)
end

-- Standing bar: Jeem's ladder from hostile (left) to allied (right), one coloured block per label, the current one
-- brighter. A notch above and below marks the faction's usual label; the white marker is where you are now.
local function drawBar(list, row, x, y, width, height)
    local each = width / #M.LADDER
    for i, label in ipairs(M.LADDER) do
        local color = M.COLORS[label]
        list:drawRect(x + (i - 1) * each + 1, y, each - 2, height, label == row.label and 0.85 or 0.25,
            color[1], color[2], color[3])
    end
    local usual = x + row.usualPos * width
    list:drawRect(usual - 1, y - 4, 3, 3, 1, HEAD[1], HEAD[2], HEAD[3])
    list:drawRect(usual - 1, y + height + 1, 3, 3, 1, HEAD[1], HEAD[2], HEAD[3])
    local at = x + row.pos * width
    list:drawRect(at - 2, y - 2, 5, height + 4, 1, 0, 0, 0)
    list:drawRect(at - 1, y - 1, 3, height + 2, 1, 1, 1, 1)
end

function Window.drawRow(list, y, item, alt)
    local height = list.itemheight
    if y + list:getYScroll() + height < 0 or y + list:getYScroll() >= list.height then return y + height end
    local row = item.item
    local textY = y + list.itemPadY
    if list.selected == item.index then list:drawSelection(0, y, list:getWidth(), height - 1) end
    local measure, right = getTextManager(), list:getWidth() - 20 -- clear of the scrollbar
    local now = getGameTime():getWorldAgeHours()
    local text = statusText(row, now)
    drawStatus(list, text, row.label or row.status, right - measure:MeasureStringX(list.font, text), textY)
    local noteRight = right - list.statusWidth - GAP
    local note = noteText(row, now)
    if row.points then
        local barHeight = math.floor(height / 3)
        drawBar(list, row, noteRight - list.noteWidth, y + (height - barHeight) / 2, list.noteWidth, barHeight)
    elseif note then
        list:drawText(note, noteRight - measure:MeasureStringX(list.font, note), textY,
            DIM[1], DIM[2], DIM[3], 1, list.font)
    end
    local nameRight = noteRight - list.noteWidth - GAP
    list:drawText(fitName(row, list.font, nameRight - 10), 10, textY, TEXT[1], TEXT[2], TEXT[3], 1, list.font)
    return y + height
end

-- A faction page's steps sit between the heading and the counts; the tabs, buttons and list move down to make room.
function Window:makeRoom(lines)
    local shift = lines * self.stepHeight
    if shift == self.shift then return end
    self.shift = shift
    for _, tab in ipairs(self.tabs) do tab:setY(self.tabsY + shift) end
    for _, tool in ipairs(self.tools) do tool:setY(self.toolsY + shift) end
    self.list:setY(self.listTop + shift)
    self.list:setHeight(self.height - self.listTop - shift - MARGIN)
end

-- A faction page's steps, one per line: what A-Life looks at, its answer and how it changes. The one that decides is
-- bright, the rest dim. Returns the y below them.
function Window:drawSteps(steps, y)
    local measure, x, nameWidth = getTextManager(), MARGIN + 8, 0
    for _, step in ipairs(steps) do nameWidth = math.max(nameWidth, measure:MeasureStringX(UIFont.Small, step.name)) end
    local valueX = x + nameWidth + GAP
    for _, step in ipairs(steps) do
        local name, value = step.dim and DIM or TEXT, step.dim and DIM or M.COLORS[step.label or step.status]
        self:drawText(step.name, x, y, name[1], name[2], name[3], 1, UIFont.Small)
        self:drawText(step.change, valueX, y, value[1], value[2], value[3], 1, UIFont.Small)
        if step.note then
            local noteX = valueX + measure:MeasureStringX(UIFont.Small, step.change) + 12
            self:drawText(fit(step.note, UIFont.Small, self.width - MARGIN - noteX), noteX, y,
                DIM[1], DIM[2], DIM[3], 1, UIFont.Small)
        end
        y = y + self.stepHeight
    end
    return y
end

-- The picked faction's entry in the latest standing snapshot (it's replaced on every refresh).
function Window:standingEntry()
    local factions = M.standing and M.standing.factions
    return factions and self.subject and factions[self.subject.id]
end

-- Under the heading of one faction's standing: what the bar doesn't say.
function Window:standingDetail()
    local entry = self:standingEntry()
    if entry == nil then return nil end
    local parts = { "usually " .. tostring(entry.default),
        entry.toNext and (math.ceil(entry.toNext) .. " points to the next step") or "as high as it goes" }
    local bonus = tonumber(entry.bonus) or 0
    if math.abs(bonus) >= 1 then parts[#parts + 1] = string.format("%+d from your faction", math.floor(bonus)) end
    if entry.waiting then parts[#parts + 1] = entry.waiting .. " not reported yet" end
    return table.concat(parts, "  |  ")
end

function Window:heading()
    if self.why then
        local cause = M.causeText(self.why.cause, self.why.causeAt, getGameTime():getWorldAgeHours())
        return M.nameOf(self.subject) .. ": " .. self.why.status .. (cause and (" (" .. cause .. ")") or "")
    end
    if self.mode == "standing" then
        local standing, entry = M.standing, self:standingEntry()
        if entry then return self.subject.name .. ": " .. entry.label .. string.format(" %+d", math.floor(entry.points)) end
        if standing == nil then return "Asking the server..." end
        if not standing.available then return "Jeem Extension's standing isn't running on the server" end
        if standing.enabled == false then return "Jeem Extension's standing is off on this server" end
        for _ in pairs(standing.factions or {}) do return "Your standing points with each faction" end
        return "No standing points yet" -- the game's Lua has no next function
    end
    if self.mode == "history" then return "Changes in how factions treat you, newest first" end
    if self.mode == "kills" then
        return M.kills == nil and "Asking the server..." or "Your kills by faction, most first"
    end
    if self.mode == "blocs" then
        return self.subject and (self.subject .. ": stance toward each bloc") or "How each bloc treats you"
    end
    return "How each faction treats you"
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    if self.width ~= self.laidOutWidth then
        self.laidOutWidth = self.width
        spread(self.tabs, self.width)
        spread(self.tools, self.width)
    end
    -- Reputation arrives asynchronously; rebuild when it changes.
    local store = ProjectALife.StatusStore
    local reputation = store and store.reputation
    if self.dirty or reputation ~= self.reputation then
        -- Jeem resyncs our reputation after every standing change, so that's when to ask for fresh points.
        if reputation ~= self.reputation and (self.mode == "standing" or self.why) and M.hasStanding() then
            M.request(self.playerNum, "standing")
        end
        self.reputation = reputation
        self:rebuild()
    end
    local measure, y = getTextManager(), self.countsY
    local heading = fit(self:heading(), UIFont.Medium, self.width - 2 * MARGIN)
    self:drawText(heading, MARGIN, self.headingY, HEAD[1], HEAD[2], HEAD[3], 1, UIFont.Medium)
    -- Your A-Life reputation level, at the right end of the heading, on the tabs whose stances it moves.
    local rep, repColor
    if (self.mode == "factions" or self.mode == "blocs") and self.subject == nil then
        rep, repColor = M.repSummary(M.myPersonal())
    end
    if rep then
        local repX = self.width - MARGIN - measure:MeasureStringX(UIFont.Small, rep)
        if repX >= MARGIN + measure:MeasureStringX(UIFont.Medium, heading) + GAP then
            local color = repColor or DIM
            local repY = self.headingY + measure:getFontHeight(UIFont.Medium) - measure:getFontHeight(UIFont.Small)
            self:drawText(rep, repX, repY, color[1], color[2], color[3], 1, UIFont.Small)
        end
    end
    local detail = self.mode == "standing" and self:standingDetail()
    if detail then
        self:drawText(detail, MARGIN, y, DIM[1], DIM[2], DIM[3], 1, UIFont.Small)
        return
    end
    local x = MARGIN
    if self.why then
        y = self:drawSteps(self.why.steps, y)
        local label = "Toward others:"
        self:drawText(label, x, y, DIM[1], DIM[2], DIM[3], 1, UIFont.Small)
        x = x + measure:MeasureStringX(UIFont.Small, label) + 12
    end
    -- On the Standing tab the counts run in the bar's order and colours, so they double as its legend.
    local words = self.mode == "standing" and M.LADDER or { "friendly", "neutral", "careful", "hostile" }
    for _, status in ipairs(words) do
        local text = status .. " " .. tostring(self.counts and self.counts[status] or 0)
        local color = M.COLORS[status]
        self:drawText(text, x, y, color[1], color[2], color[3], 1, UIFont.Small)
        x = x + measure:MeasureStringX(UIFont.Small, text) + 16
    end
    local met = self.mode == "kills" and ("total " .. tostring(self.counts and self.counts.kills or 0))
        or ("met " .. tostring(self.counts and self.counts.met or 0))
    self:drawText(met, x, y, DIM[1], DIM[2], DIM[3], 1, UIFont.Small)
    x = x + measure:MeasureStringX(UIFont.Small, met) + 24
    local hint = self.mode == "standing" and "White mark = you, notches = their usual. Click a row to see why."
        or self.mode == "blocs" and "Click a row to see its own view."
        or "Click a row to see why."
    if x + measure:MeasureStringX(UIFont.Small, hint) <= self.width - MARGIN then
        self:drawText(hint, x, y, DIM[1], DIM[2], DIM[3], 1, UIFont.Small)
    end
end

function Window:onPick(row)
    if self.mode == "standing" then
        if self.subject == nil then self.subject = row end -- event rows have nothing behind them
    elseif self.mode == "blocs" then
        self.subject = row.bloc
    elseif row.faction then
        self.subject = row.faction -- its page: why it treats you so, and how it treats the others
        if M.hasStanding() then M.request(self.playerNum, "standing") end
    end
    self.dirty = true
end

function Window:onBack()
    self.subject = nil
    self.dirty = true
end

-- Each tab keeps its own Show: until you quit (the window is made anew each time it opens). Factions starts at the
-- factions you've met, or all of them for a character who has met none; the other tabs start at all.
M.lastFilters = M.lastFilters or {}

function Window:filterFor(mode)
    return M.lastFilters[mode]
        or mode == "factions" and M.defaultFilter(M.seen(getSpecificPlayer(self.playerNum))) or "all"
end

function Window:setMode(mode)
    self.mode, self.filter = mode, self:filterFor(mode)
    if self.filterButton then self.filterButton:setTitle("Show: " .. self.filter) end
end

function Window:onTab(button)
    self:setMode(button.mode)
    self.subject = nil
    M.lastMode = self.mode
    if self.mode == "kills" or self.mode == "standing" then M.request(self.playerNum, self.mode) end
    self.dirty = true
end

function Window:onFilter()
    self.filter = nextOf(M.FILTERS, self.filter)
    M.lastFilters[self.mode] = self.filter
    self.filterButton:setTitle("Show: " .. self.filter)
    self.dirty = true
end

function Window:close()
    self:setVisible(false)
    self:removeFromUIManager()
    M.window = nil
end

function Window:new(playerNum)
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width, height = math.min(800, screenW - 40), math.min(760, screenH - 40)
    local x = math.max(20, (screenW - width) / 2)
    local y = math.max(20, (screenH - height) / 2)
    local window = ISCollapsableWindow.new(self, x, y, width, height)
    window.minimumWidth, window.minimumHeight = 620, 400
    window.playerNum = playerNum
    -- Opens on Factions, or the tab last picked this session.
    window:setMode((M.lastMode ~= "standing" or M.hasStanding()) and M.lastMode or "factions")
    window.dirty = true
    window.resizable = true
    window:setTitle("A-LIFE  /  FACTION RELATIONS")
    return window
end

function M.toggle(playerNum)
    if M.window then
        M.window:close()
        return
    end
    M.window = Window:new(playerNum)
    M.window:initialise()
    M.window:addToUIManager()
    if M.window.mode == "standing" or M.window.mode == "kills" then M.request(playerNum, M.window.mode) end
    -- Ask the server to resend our reputation (it rate-limits this itself).
    local store = ProjectALife.StatusStore
    if store and store.request then store.request(getSpecificPlayer(playerNum)) end
end

-- Same as typing /say or /yell, which A-Life already listens to. Single player has no chat;
-- there A-Life's own T box calls TalkInput.say, so we do too.
local function speak(text, loud)
    if isClient() then
        if loud then processShoutMessage(text) else processSayMessage(text) end
    else
        ProjectALife.TalkInput.say(text, loud)
    end
end

local function addTalkMenu(context, label, loud)
    local menu = context:getNew(context)
    context:addSubMenu(context:addOption(label), menu)
    for _, phrase in ipairs(M.PHRASES) do menu:addOption(phrase[1], phrase[1], speak, loud) end
    local towns = ProjectALife.TownRegions and ProjectALife.TownRegions.definitions
    if towns then
        local where = menu:getNew(menu)
        menu:addSubMenu(menu:addOption("Where is..."), where)
        for _, town in ipairs(towns) do where:addOption(town.label, "Where is " .. town.label .. "?", speak, loud) end
    end
end

-- Tiles to the nearest live A-Life NPC (their bodies carry ProjectALifeUID), or nil when none is loaded.
local function nearestNpc(player)
    local cell, best = getCell(), nil
    local zombies = cell and cell:getZombieList()
    if zombies == nil or player == nil then return nil end
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        local data = zombie:hasModData() and zombie:getModData() or nil
        if data and data.ProjectALifeUID and not zombie:isDead() then
            local tiles = zombie:DistTo(player)
            if best == nil or tiles < best then best = tiles end
        end
    end
    return best
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test or not M.available() then return end
    context:addOption("Faction Relations", playerNum, M.toggle)
    if ProjectALife.TalkInput then
        -- Only the lines an A-Life NPC can hear, unless the server shows them everywhere (sandbox TalkAnywhere).
        local anywhere = M.talkAnywhere()
        local nearest = not anywhere and nearestNpc(getSpecificPlayer(playerNum)) or nil
        if anywhere or (nearest and nearest <= M.SAY_TILES) then addTalkMenu(context, "Say", false) end
        if anywhere or (nearest and nearest <= M.SHOUT_TILES) then addTalkMenu(context, "Shout", true) end
    end
end)
