require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ProjectALife/Talk/ALifeTalkIntents"
require "ProjectALife/Talk/ALifeTalkOrderRows"
require "ProjectALife/Talk/ALifeTalkWinterRows"
require "ProjectALife/Talk/ALifePartyRows"
require "ProjectALife/Talk/ALifeTalkMenu"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local Menu = ProjectALife.TalkMenu
local Text = ProjectALife.Text
local Cinema = { disabled = false, cps = 70, chipCache = {}, chipWidth = {}, words = {}, opa = 1, compactRows = 9 }
ProjectALife.TalkCinema = Cinema
Cinema.utf16Units = pcall(string.char, 256)

if type(Menu) ~= "table" or Menu.Window == nil or type(Menu.open) ~= "function" then return Cinema end

local Base = Menu.Window
local W = Base:derive("ALifeCinemaWindow")
local Row = ISButton:derive("ALifeCinemaRow")
local Tab = ISButton:derive("ALifeCinemaTab")
local Hit = ISButton:derive("ALifeCinemaHit")
Cinema.Window, Cinema.Row, Cinema.Tab, Cinema.Hit = W, Row, Tab, Hit

Cinema.palettes = {
    classic = {
        back = { r = 0.026, g = 0.032, b = 0.028 },
        panel = { r = 0.048, g = 0.058, b = 0.05 },
        edge = { r = 0.30, g = 0.36, b = 0.25 },
        accent = { r = 0.88, g = 0.74, b = 0.36 },
        text = { r = 0.90, g = 0.90, b = 0.83 },
        bright = { r = 1.0, g = 0.98, b = 0.88 },
        dim = { r = 0.55, g = 0.60, b = 0.52 },
        rowA = { r = 0.058, g = 0.072, b = 0.058 },
        rowHot = { r = 0.13, g = 0.16, b = 0.10 },
        bar = { r = 0.02, g = 0.024, b = 0.02 },
        you = { r = 0.88, g = 0.74, b = 0.40 },
        npc = { r = 0.62, g = 0.84, b = 0.58 },
        leave = { r = 0.92, g = 0.62, b = 0.56 },
        rich = { note = " <RGB:0.55,0.58,0.52> ", you = " <RGB:0.88,0.74,0.40> ", npc = " <RGB:0.62,0.84,0.58> ", text = " <RGB:0.88,0.88,0.82> " },
    },
    alife = {
        back = { r = 0.070, g = 0.086, b = 0.094 },
        panel = { r = 0.100, g = 0.122, b = 0.132 },
        edge = { r = 0.24, g = 0.33, b = 0.36 },
        accent = { r = 0.46, g = 0.68, b = 0.74 },
        text = { r = 0.88, g = 0.90, b = 0.88 },
        bright = { r = 0.97, g = 0.99, b = 0.98 },
        dim = { r = 0.58, g = 0.65, b = 0.65 },
        rowA = { r = 0.092, g = 0.114, b = 0.124 },
        rowHot = { r = 0.17, g = 0.25, b = 0.28 },
        bar = { r = 0.050, g = 0.062, b = 0.068 },
        you = { r = 0.52, g = 0.74, b = 0.79 },
        npc = { r = 0.60, g = 0.86, b = 0.74 },
        leave = { r = 0.92, g = 0.62, b = 0.56 },
        rich = { note = " <RGB:0.58,0.66,0.66> ", you = " <RGB:0.52,0.74,0.79> ", npc = " <RGB:0.60,0.86,0.74> ", text = " <RGB:0.90,0.92,0.90> " },
    },
}

function Cinema.applyTheme()
    Cinema.pal = Cinema.palettes[Menu.themeName()] or Cinema.palettes.alife
    return Cinema.pal
end

Cinema.applyTheme()

Cinema.chipColors = {
    order = { r = 0.93, g = 0.46, b = 0.32 }, police = { r = 0.46, g = 0.64, b = 0.96 },
    medic = { r = 0.50, g = 0.86, b = 0.62 }, military = { r = 0.68, g = 0.74, b = 0.45 },
    rep = { r = 0.96, g = 0.80, b = 0.40 }, trade = { r = 0.50, g = 0.82, b = 0.82 },
    supply = { r = 0.52, g = 0.80, b = 0.70 }, leave = { r = 0.78, g = 0.52, b = 0.52 },
    weather = { r = 0.62, g = 0.76, b = 0.96 }, reply = { r = 0.72, g = 0.72, b = 0.68 },
    craft = { r = 0.86, g = 0.66, b = 0.42 }, door = { r = 0.70, g = 0.62, b = 0.86 },
}

Cinema.stanceValue = { friendly = 55, neutral = 0, careful = -35, hostile = -80 }
Cinema.jobOrder = { "law", "medical", "military", "trade", "rescue" }
Cinema.jobChip = {
    law = { "Police", "police" }, medical = { "Medic", "medic" }, military = { "Veteran", "military" },
    trade = { "Craft", "craft" }, rescue = { "Craft", "craft" },
}
Cinema.orderTips = {
    hands_up = "Make them raise their hands.", drop = "Make them drop their weapon.",
    surrender = "Make them drop the weapon and raise their hands.", rob = "Demand everything they are carrying.",
    out = "Tell them to get out of here.", leave = "Tell them and their group to clear out of the area.",
    follow = "Make them fall in behind you.", frisk_weapons = "Take the weapons from someone who has surrendered.",
    frisk_items = "Search the pockets of someone who has surrendered.", at_ease = "Let them lower their hands.",
}
Cinema.chrome = { "closeButton", "infoButton", "pinButton", "collapseButton", "resizeWidget", "resizeWidget2" }
Cinema.leaveIds = { WALK_STOP = true, GUEST_LEAVE = true, DOOR_LEAVE = true, DOOR_LEAVE_RUDE = true }
Cinema.barterIds = { DOOR_TRADE = true, DOOR_TRADE_CONFIRM = true, DOOR_TRADE_CANCEL = true, DOOR_GIVE = true,
    DOOR_PAY = true, DOOR_LEND = true }
Cinema.medicIds = { DOOR_TREAT = true, DOOR_TREAT_ME = true, ASK_MEDS = true }

function Cinema.fill(el, x, y, w, h, c, a)
    el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
end

function Cinema.back(el, x, y, w, h, c, a)
    el:drawRect(x, y, w, h, a * Cinema.opa, c.r, c.g, c.b)
end

function Cinema.frame(el, x, y, w, h, c, a)
    el:drawRectBorder(x, y, w, h, a, c.r, c.g, c.b)
end

function Cinema.say(el, str, x, y, c, a, font)
    el:drawText(str, x, y, c.r, c.g, c.b, a, font or UIFont.Small)
end

function Cinema.sayCentre(el, str, x, y, c, a, font)
    el:drawTextCentre(str, x, y, c.r, c.g, c.b, a, font or UIFont.Small)
end

function Cinema.sayRight(el, str, x, y, c, a, font)
    el:drawTextRight(str, x, y, c.r, c.g, c.b, a, font or UIFont.Small)
end

function Cinema.brackets(el, x, y, w, h, len, c, a)
    Cinema.fill(el, x, y, len, 1, c, a)
    Cinema.fill(el, x, y, 1, len, c, a)
    Cinema.fill(el, x + w - len, y, len, 1, c, a)
    Cinema.fill(el, x + w - 1, y, 1, len, c, a)
    Cinema.fill(el, x, y + h - 1, len, 1, c, a)
    Cinema.fill(el, x, y + h - len, 1, len, c, a)
    Cinema.fill(el, x + w - len, y + h - 1, len, 1, c, a)
    Cinema.fill(el, x + w - 1, y + h - len, 1, len, c, a)
end

function Cinema.measure(font, str)
    return getTextManager():MeasureStringX(font, str)
end

function Cinema.isContinuation(str, at)
    local byte = string.byte(str, at)
    if byte == nil then return false end
    if Cinema.utf16Units then return byte >= 56320 and byte <= 57343 end
    return byte >= 128 and byte < 192
end

function Cinema.cut(str, count)
    if count >= #str then return str end
    while count > 0 and Cinema.isContinuation(str, count + 1) do count = count - 1 end
    return string.sub(str, 1, count)
end

function Cinema.fit(font, str, maxWidth)
    if str == nil or str == "" then return "" end
    if Cinema.measure(font, str) <= maxWidth then return str end
    local count = #str
    while count > 1 and Cinema.measure(font, string.sub(str, 1, count) .. "...") > maxWidth do count = count - 1 end
    return Cinema.cut(str, count) .. "..."
end

function Cinema.wordPart(font, word, maxWidth)
    local low, high, best = 1, #word, ""
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local part = Cinema.cut(word, middle)
        if Cinema.measure(font, part) <= maxWidth then
            best, low = part, middle + 1
        else
            high = middle - 1
        end
    end
    return best
end

function Cinema.wrap(font, str, maxWidth)
    local lines = {}
    for paragraph in string.gmatch(str .. "\n", "(.-)\n") do
        local line = ""
        for word in string.gmatch(paragraph, "%S+") do
            local attempt = line == "" and word or (line .. " " .. word)
            if line ~= "" and Cinema.measure(font, attempt) > maxWidth then
                lines[#lines + 1] = line
                line = ""
            end
            while Cinema.measure(font, word) > maxWidth do
                local part = Cinema.wordPart(font, word, maxWidth)
                if part == "" then break end
                lines[#lines + 1] = part
                word = string.sub(word, #part + 1)
            end
            line = line == "" and word or (line .. " " .. word)
        end
        lines[#lines + 1] = line
    end
    return lines
end

function Cinema.hardWrap(str, columns)
    local lines, line = {}, ""
    for word in string.gmatch(str, "%S+") do
        local attempt = line == "" and word or (line .. " " .. word)
        if line ~= "" and #attempt > columns then
            lines[#lines + 1] = line
            line = word
        else
            line = attempt
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

function Cinema.word(id, en)
    local shown = Cinema.words[id]
    if shown == nil then
        shown = Text.ui(en)
        Cinema.words[id] = shown
    end
    return shown
end

function Cinema.stanceWord(stance)
    if stance == "friendly" then return Cinema.word("sf", "Friendly") end
    if stance == "neutral" then return Cinema.word("sn", "Neutral") end
    if stance == "careful" then return Cinema.word("sc", "Wary") end
    if stance == "hostile" then return Cinema.word("sh", "Hostile") end
    return Cinema.word("su", "Sizing you up")
end

function Cinema.opinionWord(value)
    if value <= -61 then return Cinema.word("o1", "Hates you") end
    if value <= -21 then return Cinema.word("o2", "Wary") end
    if value <= 20 then return Cinema.word("o3", "Neutral") end
    if value <= 60 then return Cinema.word("o4", "Trusts you") end
    return Cinema.word("o5", "Friend")
end

function Cinema.opinionColor(value)
    local t = math.max(-100, math.min(100, value)) / 100
    if t >= 0 then return 0.80 - 0.32 * t, 0.78 + 0.08 * t, 0.35 + 0.12 * t end
    return 0.80 - 0.10 * t, 0.78 + 0.52 * t, 0.35 + 0.15 * t
end

function Cinema.size(screenWidth, screenHeight, fontHeight)
    local width = math.max(820, math.floor(fontHeight * 70))
    local height = math.max(560, math.floor(fontHeight * 44))
    width = math.min(width, math.floor(screenWidth * 0.92) - 8)
    height = math.min(height, math.floor(screenHeight * 0.94) - 8)
    return math.max(640, width), math.max(480, height)
end

function Cinema.pushChip(list, label, kind)
    if #list >= 3 then return end
    list[#list + 1] = { label = Text.ui(label), kind = kind }
end

function Cinema.chipsFor(choice)
    local cached = Cinema.chipCache[choice.id]
    if cached ~= nil then return cached end
    local list = {}
    local Intents = ProjectALife.TalkIntents
    if choice.order ~= nil then Cinema.pushChip(list, "Order", "order") end
    if type(choice.jobs) == "table" then
        for _, key in ipairs(Cinema.jobOrder) do
            if choice.jobs[key] == true then
                local chip = Cinema.jobChip[key]
                Cinema.pushChip(list, chip[1], chip[2])
                break
            end
        end
    end
    if type(choice.classes) == "table" then
        if choice.classes.criminal == true then Cinema.pushChip(list, "Toll", "trade")
        elseif choice.classes.police == true or choice.classes.military == true then Cinema.pushChip(list, "Duty", "police")
        else Cinema.pushChip(list, "Shelter", "supply") end
    end
    if choice.friendly then Cinema.pushChip(list, "Reputation", "rep") end
    if Cinema.barterIds[choice.id] == true then Cinema.pushChip(list, "Trade", "trade")
    elseif Intents.groupOf(choice) == "Supplies" then Cinema.pushChip(list, "Supplies", "supply") end
    if Cinema.medicIds[choice.id] == true then Cinema.pushChip(list, "Medic", "medic") end
    local winter = ProjectALife.TalkWinterRows
    if winter ~= nil and type(winter.rules) == "table" and winter.rules[choice.id] ~= nil then
        Cinema.pushChip(list, "Weather", "weather")
    end
    if choice.answer or choice.event then Cinema.pushChip(list, "Reply", "reply") end
    if Cinema.leaveIds[choice.id] == true then Cinema.pushChip(list, "Leave", "leave") end
    if #list == 0 and choice.door then Cinema.pushChip(list, "Door", "door") end
    for _, chip in ipairs(list) do
        local width = Cinema.chipWidth[chip.label]
        if width == nil then
            width = Cinema.measure(UIFont.Small, chip.label) + 10
            Cinema.chipWidth[chip.label] = width
        end
        chip.w = width
    end
    Cinema.chipCache[choice.id] = list
    return list
end

function Cinema.markedChips(chips, mark)
    local list = {}
    for _, chip in ipairs(chips) do list[#list + 1] = chip end
    local label, kind = nil, nil
    if mark.asked then label, kind = "Asked", "reply"
    elseif mark.sug then label, kind = "Suggested", "supply"
    elseif mark.risky then label, kind = "Risky", "order"
    elseif mark.new then label, kind = "New", "rep"
    elseif mark.later then label, kind = "Later", "door" end
    if label ~= nil then
        local text = Text.ui(label)
        local width = Cinema.chipWidth[text]
        if width == nil then
            width = Cinema.measure(UIFont.Small, text) + 10
            Cinema.chipWidth[text] = width
        end
        list[#list + 1] = { label = text, kind = kind, w = width }
    end
    return list
end

function Cinema.tipFor(win, choice, label)
    local lines = { label, "" }
    if choice.info then
        lines = { choice.tip }
    elseif choice.order ~= nil then
        local tip = Cinema.orderTips[choice.order]
        if tip ~= nil then lines[#lines + 1] = Text.ui(tip) end
        lines[#lines + 1] = Text.ui("They can refuse. It depends on how armed you look, how scared they are and who stands with them.")
        local chance = nil
        if type(win.orderChances) == "table" then chance = tonumber(win.orderChances[choice.id]) end
        if chance == nil then chance = tonumber(win.orderChance) end
        if chance ~= nil then
            lines[#lines + 1] = Text.ui("Chance they comply: {n}%", { n = math.max(0, math.min(100, math.floor(chance + 0.5))) })
        end
    elseif choice.tip ~= nil then
        lines[#lines + 1] = Text.ui(choice.tip)
    elseif type(choice.jobs) == "table" then
        lines[#lines + 1] = Text.ui("Shown because of what you did for a living before all this.")
    elseif choice.friendly then
        lines[#lines + 1] = Text.ui("Ask to travel with their group; this does not recruit or command them.")
        lines[#lines + 1] = Text.ui("Needs them to be friendly toward you.")
    elseif choice.answer then
        lines[#lines + 1] = Text.ui("Your answer to what they just asked.")
    elseif ProjectALife.TalkIntents.groupOf(choice) == "Supplies" then
        lines[#lines + 1] = Text.ui("Ask for help. They decide what to share.")
    else
        lines[#lines + 1] = Text.ui("Say it out loud. They may remember how you talk to them.")
    end
    local out = {}
    for index, entry in ipairs(lines) do out[index] = Cinema.hardWrap(entry, 60) end
    return table.concat(out, "\n")
end

function Cinema.wanted()
    if Cinema.disabled then return false end
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.talkStyle) ~= "function" then return false end
    return prefs.talkStyle() == "Cinematic"
end

function Cinema.consumes(key)
    local keys = Keyboard
    if type(keys) ~= "table" or key == nil or keys.KEY_1 == nil or keys.KEY_9 == nil then return false end
    if key >= keys.KEY_1 and key <= keys.KEY_9 then return true end
    return key == keys.KEY_SPACE or key == keys.KEY_ESCAPE or key == keys.KEY_TAB or key == keys.KEY_UP
        or key == keys.KEY_DOWN or key == keys.KEY_LEFT or key == keys.KEY_RIGHT or key == keys.KEY_NEXT
        or key == keys.KEY_PRIOR
end

function Cinema.dots()
    local count = math.floor(getTimestampMs() / 320) % 4
    return string.rep(".", count)
end

function W:layoutMetrics(height)
    local manager = getTextManager()
    local u, med = manager:getFontHeight(UIFont.Small), manager:getFontHeight(UIFont.Medium)
    local w, h = self.width, height or self.height
    local pad = math.max(10, math.floor(u * 0.8))
    local row = math.max(28, u + 12)
    local gap = math.max(5, math.floor(u * 0.4))
    local m = { u = u, med = med, pad = pad, row = row, gap = gap, numW = math.max(26, u * 2) }
    m.lx = pad
    m.lw = math.max(220, math.min(math.floor(u * 16), math.floor(w * 0.3)))
    m.rx = pad * 2 + m.lw
    m.rw = w - m.rx - pad
    local groups = self.visitor ~= nil and ProjectALife.VisitorPanel.slots(self) or #Menu.groups(self)
    m.tabH = math.max(u + 10, row - 4)
    m.nameH, m.subH, m.badgeH = med + 4, u * 2 + 6, u + 8
    m.opH = u + 6 + math.max(10, math.floor(u * 0.7)) + 4 + u
    if self.mystery == true then m.subH, m.badgeH = u + 6, 0 end
    if self.visitor ~= nil then m.subH = u * 2 + 6 end
    m.doH = 0
    if self:wantsDoLine() then m.doH = u * 2 + 4 end
    m.fixed = m.nameH + m.subH + m.badgeH + m.opH + m.doH + groups * (m.tabH + 3) + row + gap * 6
    m.ph = math.max(math.floor(m.lw * 0.55), math.min(math.floor(m.lw * 1.15), h - pad * 2 - m.fixed))
    m.portraitY = pad
    m.nameY = m.portraitY + m.ph + gap
    m.subY = m.nameY + m.nameH
    m.badgeY = m.subY + m.subH
    m.opY = m.badgeY + m.badgeH + gap
    m.doY = m.opY + m.opH + gap
    m.tabsY = m.doY + m.doH + gap
    m.leaveY = h - pad - row
    m.nh = med * 3 + u + pad * 2
    m.nhMin = u + 10 + med + 6
    m.nhNow = 0
    m.bottomH = row
    m.bottomY = h - pad - row
    m.logMin = math.max(u * 7, 90)
    m.logY = pad
    local avail = h - pad * 2 - m.nh - m.bottomH - gap * 3 - m.logMin
    m.slots = math.max(1, math.min(9, math.floor(avail / (row + 2))))
    m.rowsShown = m.slots
    W.flow(self, m)
    return m
end

function W:flow(m)
    m.rowsH = m.rowsShown * (m.row + 2)
    m.rowsY = m.bottomY - m.gap - m.rowsH
    m.npcY = m.rowsY - m.gap - m.nhNow
    m.logH = m.npcY - m.logY
end

function W:neededHeight(rows)
    local m = self:layoutMetrics(self.height)
    local left = m.pad * 2 + math.floor(m.lw * 0.55) + m.fixed
    local right = m.pad * 2 + m.nh + m.bottomH + m.gap * 3 + m.logMin + rows * (m.row + 2)
    return math.max(left, right)
end

function W:desiredReply()
    if self.npcLine ~= nil then return self:prepareNpc().height end
    if self.waitingAt ~= nil then return self.m.nhMin end
    return 0
end

function W:relayout()
    local m = self.m
    W.flow(self, m)
    local log = self.transcript
    log:setHeight(math.max(20, m.logH - 12))
    if type(log.onResize) == "function" then log:onResize() end
    log:setYScroll(-math.max(0, log:getScrollHeight() - log.height))
    local reply = self.npcReply
    reply:setY(m.npcY + m.u + 8)
    reply:setHeight(math.max(1, m.nhNow - m.u - 14))
    if type(reply.onResize) == "function" then reply:onResize() end
    for index = 1, #self.rows do self.rows[index]:setY(m.rowsY + (index - 1) * (m.row + 2)) end
end

function W:syncReply()
    local want = self:desiredReply()
    if want ~= self.m.nhNow then
        self.m.nhNow = want
        self:relayout()
    end
end

function Cinema.makePortrait(win, x, y, w, h)
    local portrait = ISUI3DModel:new(x, y, w, h)
    portrait:initialise()
    win:addChild(portrait)
    win.portrait = portrait
    portrait:setCharacter(win.shell)
    portrait:setIsometric(false)
    portrait:setDirection(IsoDirections.S)
    portrait:setDoRandomExtAnimations(false)
    portrait:setState("idle")
    portrait:setZoom(10)
    portrait:setYOffset(-0.75)
    portrait.prerender = Cinema.portraitPrerender
end

function Cinema.portraitPrerender(model)
    if model.javaObject ~= nil then model.javaObject:setAnimate(false) end
end

function W:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(false)
    for _, name in ipairs(Cinema.chrome) do
        local element = self[name]
        if element ~= nil then element:setVisible(false) end
    end
    self.pin = true
    Cinema.applyTheme()
    self.backgroundColor = { r = Cinema.pal.back.r, g = Cinema.pal.back.g, b = Cinema.pal.back.b, a = 0.97 * ProjectALife.TalkUi.opacity() }
    self.borderColor = Menu.copyColor({ r = Cinema.pal.edge.r, g = Cinema.pal.edge.g, b = Cinema.pal.edge.b, a = 1 })
    self.logLines, self.tabs = {}, {}
    self.topic, self.turn = Menu.groups(self)[1].id, Menu.visits
    self.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    self.page, self.opShown = 1, 0
    self.s = {
        opinion = Text.ui("Opinion"), hintKeys = Text.ui("1-9 answer    Tab topic    Space skip    Esc leave"),
        hintPad = Text.ui("A choose    B leave    LB / RB topic    Y more"), skip = Text.ui("Space: skip"),
        none = Text.ui("Nothing yet."),
    }
    local m = self:layoutMetrics()
    self.m = m
    self.choiceSlots = m.slots
    self.transcript = ISRichTextPanel:new(m.rx + 6, m.logY + 6, m.rw - 12, m.logH - 12)
    self.transcript:initialise()
    self.transcript.autosetheight = false
    self.transcript.clip = true
    self.transcript.backgroundColor = { r = 0.015, g = 0.02, b = 0.017, a = 0.0 }
    self.transcript.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.transcript:addScrollBars()
    self:addChild(self.transcript)
    self.npcReply = ISRichTextPanel:new(m.rx + m.pad, m.npcY + m.u + 8, m.rw - m.pad * 2,
        m.nh - m.u - 14)
    self.npcReply:initialise()
    self.npcReply.autosetheight = false
    self.npcReply.clip = true
    self.npcReply.marginLeft, self.npcReply.marginTop = 0, 0
    self.npcReply.marginRight, self.npcReply.marginBottom = 14, 0
    self.npcReply.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.npcReply.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.npcReply:addScrollBars()
    self.npcReply:setOnMouseDownFunction(self, W.skipType)
    self.npcReply:setVisible(false)
    self:addChild(self.npcReply)
    local groups = Menu.groups(self)
    local slots = self.visitor ~= nil and ProjectALife.VisitorPanel.slots(self) or #groups
    for index = 1, slots do
        local group = groups[index] or groups[#groups]
        local tab = Tab:new(m.lx, m.tabsY + (index - 1) * (m.tabH + 3), m.lw, m.tabH, Menu.groupLabel(group), self, Base.selectTopic)
        tab:initialise()
        tab.topic, tab.owner, tab.kind, tab.count = group.id, self, "topic", 0
        self.tabs[#self.tabs + 1] = tab
        self:addChild(tab)
    end
    if self.visitor ~= nil then ProjectALife.VisitorPanel.syncTabs(self) end
    self.rows, self.buttons = {}, {}
    for index = 1, m.slots do
        local row = Row:new(m.rx, m.rowsY + (index - 1) * (m.row + 2), m.rw, m.row, "", self, Base.choose)
        row:initialise()
        row.owner, row.index = self, index
        self:addChild(row)
        self.rows[index] = row
        self.buttons[index] = row
    end
    self.more = Tab:new(m.rx + m.rw - m.u * 11, m.bottomY, m.u * 11, m.bottomH, Text.ui("More"), self, Base.nextPage)
    self.more:initialise()
    self.more.owner, self.more.kind = self, "more"
    self:addChild(self.more)
    self.leave = Tab:new(m.lx, m.leaveY, m.lw, m.row, Text.ui("Leave"), self, Base.close)
    self.leave:initialise()
    self.leave.owner, self.leave.kind, self.leave.badge = self, "leave", "Esc"
    self:addChild(self.leave)
    self.opinionHit = Hit:new(m.lx, m.opY, m.lw, m.opH, "", nil, nil)
    self.opinionHit:initialise()
    self:addChild(self.opinionHit)
    if self.mystery ~= true then
        self.badgeHit = Hit:new(m.lx, m.badgeY, m.lw, m.badgeH, "", nil, nil)
        self.badgeHit:initialise()
        self:addChild(self.badgeHit)
    end
    if self.shell ~= nil then
        local inset = 4
        local ok = pcall(Cinema.makePortrait, self, m.lx + inset, m.portraitY + inset, m.lw - inset * 2, m.ph - inset * 2)
        if not ok and self.portrait ~= nil then
            self:removeChild(self.portrait)
            self.portrait = nil
        end
    end
    self:refreshChoices()
    self:refreshTitle()
    self:refreshDoLine()
end

function Hit:prerender()
end

function Hit:render()
    if self.tooltip ~= nil then self:updateTooltip() end
end

function Row:prerender()
    local win = self.owner
    if win == nil or win.failed ~= nil then return end
    local ok, err = pcall(Cinema.drawRow, self)
    if not ok then win.failed = tostring(err) end
end

function Row:render()
    if self.choice ~= nil then self:updateTooltip() end
end

function Tab:prerender()
    local win = self.owner
    if win == nil or win.failed ~= nil then return end
    local ok, err = pcall(Cinema.drawTab, self)
    if not ok then win.failed = tostring(err) end
end

function Tab:render()
end

function Cinema.drawRow(row)
    local win, choice = row.owner, row.choice
    if choice == nil then return end
    local m, pal = win.m, Cinema.pal
    local w, h = row.width, row.height
    local enabled = row.enable == true
    local hot = enabled and (row.mouseOver == true or (win.cursorOn == true and win.cursor == row.index))
    local alpha = (enabled or choice.info) and 1 or 0.45
    if enabled and row.mark ~= nil and row.mark.asked then alpha = 0.6 end
    Cinema.back(row, 0, 0, w, h, hot and pal.rowHot or pal.rowA, 0.96)
    Cinema.frame(row, 0, 0, w, h, hot and pal.accent or pal.edge, hot and 0.95 or 0.55)
    if hot then Cinema.fill(row, 0, 0, 3, h, pal.accent, 1) end
    Cinema.fill(row, m.numW, 3, 1, h - 6, pal.edge, 0.6 * alpha)
    Cinema.sayCentre(row, tostring(row.index), math.floor(m.numW / 2) + 1, math.floor((h - m.u) / 2), pal.accent, alpha)
    Cinema.say(row, row.shown or "", m.numW + m.gap + 2, math.floor((h - m.u) / 2), hot and pal.bright or pal.text, alpha)
    local chips = row.chips
    if chips == nil then return end
    local chipH = m.u + 4
    local x = w - 6
    for index = #chips, 1, -1 do
        local chip = chips[index]
        local color = Cinema.chipColors[chip.kind] or pal.dim
        x = x - chip.w
        Cinema.fill(row, x, math.floor((h - chipH) / 2), chip.w, chipH, color, 0.16 * alpha)
        Cinema.frame(row, x, math.floor((h - chipH) / 2), chip.w, chipH, color, 0.75 * alpha)
        Cinema.sayCentre(row, chip.label, x + math.floor(chip.w / 2), math.floor((h - m.u) / 2), color, alpha)
        x = x - 4
    end
end

function Cinema.drawTab(tab)
    local win = tab.owner
    local m, pal = win.m, Cinema.pal
    local w, h = tab.width, tab.height
    local enabled = tab.enable == true
    local active = tab.kind == "topic" and tab.topic == win.topic and win.pending == nil
    local hot = enabled and tab.mouseOver == true
    local alpha = enabled and 1 or 0.5
    if tab.kind == "topic" and (tab.count or 0) == 0 and not active then alpha = alpha * 0.6 end
    local fillColor = pal.rowA
    if active then fillColor = pal.rowHot elseif hot then fillColor = pal.panel end
    Cinema.back(tab, 0, 0, w, h, fillColor, 0.96)
    Cinema.frame(tab, 0, 0, w, h, (active or hot) and pal.accent or pal.edge, (active or hot) and 0.95 or 0.55)
    if active then Cinema.fill(tab, 0, 0, 3, h, pal.accent, 1) end
    local y = math.floor((h - m.u) / 2)
    local title = tab.title or ""
    if tab.kind == "more" then
        Cinema.sayCentre(tab, title, math.floor(w / 2), y, hot and pal.bright or pal.accent, alpha)
        return
    end
    local color = pal.text
    if tab.kind == "leave" then color = pal.leave
    elseif active then color = pal.accent end
    Cinema.say(tab, title, 10, y, hot and pal.bright or color, alpha)
    local badge = tab.badge
    if tab.kind == "topic" and (tab.count or 0) > 0 and win.pending == nil then badge = tab.badgeText or tostring(tab.count) end
    if badge ~= nil then Cinema.sayRight(tab, badge, w - 8, y, pal.dim, alpha) end
end

function W:available(topic)
    if type(self.giftPicker) == "table" then
        local picked = {}
        if topic ~= self.topic then return picked end
        for _, row in ipairs(self.giftPicker.rows) do picked[#picked + 1] = Menu.pickerRow(row, self.giftPicker.intent) end
        picked[#picked + 1] = { id = "GIFT_CANCEL", text = Text.ui("Cancel"), localOnly = true }
        if topic == self.topic then self.marks = {} end
        return picked
    end
    local custom = ProjectALife.VisitorPanel
    if self.visitor ~= nil and custom.owns(self, topic) then
        if topic == self.topic then self.marks = custom.marks(self, topic) end
        return custom.rows(self, topic)
    end
    local Intents = ProjectALife.TalkIntents
    local view = self:view()
    view.topic = topic
    local list = {}
    for _, choice in ipairs(Intents.choices) do
        if not choice.hidden and not Intents.followHidden(choice) and (not choice.door or self.doorPeer == true)
                and (self.doorPeer ~= true or choice.door)
                and (not choice.door or type(self.doorChoices) ~= "table" or self.doorChoices[choice.id] == true)
                and ((self.pending ~= nil and choice.answer and Intents.answers(choice, self.pending))
                or (choice.answerTo ~= nil and Intents.answers(choice, self.pending))
                or (self.pending == nil and Intents.offered(choice, view))) then
            list[#list + 1] = choice
        end
    end
    local rows = ProjectALife.TalkSocialRows
    if rows ~= nil and type(rows.arrange) == "function" then
        local arranged, marks = rows.arrange(list, view)
        list = arranged
        if topic == self.topic then self.marks = marks or {} end
    end
    return list
end

function W:refreshInfo()
    if self.badgeHit ~= nil then self.badgeHit.tooltip = Cinema.hardWrap(Menu.stanceText(self.stance), 48) end
    if self.opinionHit == nil then return end
    if self.mystery == true and type(self.opinion) ~= "table" then
        self.opinionHit.tooltip = nil
        return
    end
    local label, reason = self:opinionState()
    local text = Cinema.hardWrap(label, 48)
    if reason ~= nil and reason ~= "" then text = text .. "\n\n" .. Cinema.hardWrap(reason, 48) end
    self.opinionHit.tooltip = text
end

function W:opinionState()
    local opinion = self.opinion
    if type(opinion) == "table" then
        local label = opinion.label
        if type(label) ~= "string" or label == "" then label = Cinema.opinionWord(opinion.value) else label = Text.ui(label) end
        local reason = opinion.reason
        if type(reason) ~= "string" or reason == "" then reason = nil else reason = Text.ui(reason) end
        return label, reason, opinion.value
    end
    local value = Cinema.stanceValue[self.stance or ""] or 0
    return Cinema.opinionWord(value), Text.ui("Read from how they act toward you right now."), value
end

function W:refreshChoices()
    if self.rows == nil then return end
    local Intents = ProjectALife.TalkIntents
    local choices = self:available(self.topic)
    local ready = self.waitingAt == nil and not self.interrupted
    self.pageCount = math.max(1, math.ceil(#choices / self.choiceSlots))
    self.page = math.min(self.page, self.pageCount)
    self.more:setVisible(self.pageCount > 1)
    self.more:setTitle(Text.ui("More  /  {page} of {count}", { page = self.page, count = self.pageCount }))
    self.more:setEnable(ready)
    local m = self.m
    local shown = 0
    for index, row in ipairs(self.rows) do
        local choice = choices[(self.page - 1) * self.choiceSlots + index]
        row.choice = choice
        if choice ~= nil then shown = shown + 1 end
        row:setVisible(choice ~= nil)
        row.tooltip = nil
        row.chips = nil
        row.mark = nil
        if choice ~= nil then
            local label = choice.visitor and choice.text or Text.ui(Intents.choiceLabel(choice, self.turn))
            if self.pending == "NPC_OPEN" then
                label = choice.id == "YES" and Text.ui("Yeah... I'm doing alright.") or Text.ui("No. Not really.")
            end
            row.spokenText = label
            local mark = self.marks ~= nil and self.marks[choice.id] or nil
            local chips = Cinema.chipsFor(choice)
            if mark ~= nil then chips = Cinema.markedChips(chips, mark) end
            local chipsWidth = 6
            for _, chip in ipairs(chips) do chipsWidth = chipsWidth + chip.w + 4 end
            row.chips = chips
            row.mark = mark
            row.shown = Cinema.fit(UIFont.Small, label, m.rw - m.numW - m.gap * 3 - chipsWidth - 4)
            row.tooltip = Cinema.tipFor(self, choice, label)
            if mark ~= nil and mark.asked then
                row.tooltip = row.tooltip .. "\n\n" .. Cinema.hardWrap(Text.ui("You asked this a moment ago. Asking again will annoy them."), 60)
            elseif mark ~= nil and mark.risky then
                row.tooltip = row.tooltip .. "\n\n" .. Cinema.hardWrap(Text.ui("They may not take this well from someone they hardly know."), 60)
            end
        end
        local emptyPick = choice ~= nil and self.giftEmpty == true and not choice.gift and Menu.pickIntents[choice.id] == true
        if emptyPick then
            row.tooltip = Cinema.hardWrap(Text.ui(Menu.messages[self.giftEmptyReason] or Menu.messages.no_safe_food), 60)
        end
        row:setEnable(ready and choice ~= nil and choice.info ~= true and not emptyPick)
    end
    if shown ~= m.rowsShown then
        m.rowsShown = shown
        self:relayout()
    end
    for _, tab in ipairs(self.tabs) do
        tab:setEnable(self.pending == nil and self.giftPicker == nil and ready)
        if self.visitor ~= nil then
            tab.count = tab.count or 0
        elseif self.pending == nil then
            tab.count = tab.topic == self.topic and #choices or #self:available(tab.topic)
        else
            tab.count = 0
        end
    end
    self:refreshInfo()
    self:clampCursor()
end

function W:clampCursor()
    local list = self:usableButtons()
    self.cursor = math.max(1, math.min(tonumber(self.cursor) or 1, math.max(1, #list)))
    if self.joypadData == nil then return end
    for index, button in ipairs(list) do
        if type(button.setJoypadFocused) == "function" then button:setJoypadFocused(index == self.cursor) end
    end
end

function W:addLog(kind, text, name)
    local line
    local rich = Cinema.pal.rich
    if kind == "note" then
        line = rich.note .. text
    elseif kind == "you" then
        line = rich.you .. Text.ui("You") .. ": <SPACE>" .. rich.text .. text
    else
        line = rich.npc .. string.gsub(tostring(name or self:shownName()), "[<>]", "") .. ": <SPACE>" .. rich.text .. text
    end
    self.logLines[#self.logLines + 1] = line
    while #self.logLines > 40 do table.remove(self.logLines, 1) end
    self.transcript.text = table.concat(self.logLines," <LINE> <LINE> ")
    self.transcript:paginate()
    self.transcript:setYScroll(-math.max(0, self.transcript:getScrollHeight() - self.transcript.height))
end

function W:archiveNpc()
    if self.npcLine ~= nil then
        self:addLog("npc", self.npcLine, self.npcSpeaker)
        self.npcLine, self.npcWrap, self.npcSpeaker = nil, nil, nil
    end
    if self.npcReply ~= nil then
        self.npcReply:setVisible(false)
        self.npcReply:setYScroll(0)
        self.npcReply.text = ""
    end
end

function W:append(text, speaker)
    if ProjectALife.AudioPolicy ~= nil and type(ProjectALife.AudioPolicy.caption) == "function" then
        text = ProjectALife.AudioPolicy.caption(text)
    end
    if text == nil then return end
    if ProjectALife.Speech ~= nil and type(ProjectALife.Speech.genderedFor) == "function" then
        text = ProjectALife.Speech.genderedFor(text, getSpecificPlayer(self.playerNum))
    end
    if text == self.lastText then return end
    self.lastText = text
    text = string.gsub(string.gsub(text, "<", "("), ">", ")")
    if speaker == "A-LIFE" then
        self:addLog("note", text)
    elseif speaker == "You" then
        self:archiveNpc()
        self:addLog("you", text)
    else
        self:archiveNpc()
        self.npcLine, self.npcSpeaker, self.npcWrap = text, speaker, nil
        self.typeAt, self.skip = getTimestampMs(), false
    end
end

function W:skipType()
    if self.npcLine ~= nil and self.skip ~= true then self.skip = true end
end

function W:takeExtras(args)
    local opinion = args.opinion
    if type(opinion) == "table" and tonumber(opinion.value) ~= nil then
        self.opinion = {
            value = math.max(-100, math.min(100, tonumber(opinion.value))),
            label = type(opinion.label) == "string" and opinion.label or nil,
            reason = type(opinion.reason) == "string" and opinion.reason or nil,
        }
        if self.opSeen ~= true then
            self.opSeen = true
            self.opShown = self.opinion.value
        end
    else
        self.opinion = nil
    end
    if type(args.orderChances) == "table" then self.orderChances = args.orderChances end
    if tonumber(args.orderChance) ~= nil then self.orderChance = tonumber(args.orderChance) end
    self:refreshDoLine()
    self:refreshChoices()
end

function W:prepareNpc()
    if self.npcWrap ~= nil then return self.npcWrap end
    local m = self.m
    local maxWidth = m.rw - m.pad * 2 - 14
    local top = m.u + 10
    local font = UIFont.Medium
    local lineH = m.med
    local lines = Cinema.wrap(font, self.npcLine, maxWidth)
    local cap = math.max(1, math.floor((m.nh - top - 6) / lineH))
    if #lines > cap then
        font, lineH = UIFont.Small, m.u + 1
        lines = Cinema.wrap(font, self.npcLine, maxWidth)
        cap = math.max(1, math.floor((m.nh - top - 6) / lineH))
    end
    local text = table.concat(lines, "\n")
    local total = #text
    local height = m.nh
    if #lines <= cap then height = math.max(m.nhMin, top + #lines * lineH + 6) end
    self.npcWrap = { lines = lines, text = text, font = font, lineH = lineH, total = total, scroll = #lines > cap,
        height = height }
    return self.npcWrap
end

function Cinema.drawNpcBox(win)
    local m, pal = win.m, Cinema.pal
    win:syncReply()
    local x, y, w, h = m.rx, m.npcY, m.rw, m.nhNow
    if h <= 0 then
        win.npcReply:setVisible(false)
        return
    end
    Cinema.back(win, x + 1, y, w - 2, h, pal.panel, 0.97)
    Cinema.fill(win, x + 1, y, w - 2, 1, pal.edge, 0.8)
    Cinema.fill(win, x, y, 3, h, pal.accent, 1)
    local speaker = win.npcSpeaker
    if speaker == nil or speaker == "" then speaker = win:shownName() end
    Cinema.say(win, speaker, x + m.pad, y + 4, pal.npc, 1)
    local top = y + m.u + 8
    if win.npcLine == nil then
        win.npcReply:setVisible(false)
        if win.waitingAt ~= nil then
            Cinema.say(win, Cinema.dots(), x + m.pad, top, pal.dim, 1, UIFont.Medium)
        end
        return
    end
    local wrapped = win:prepareNpc()
    local remaining
    if win.skip == true then
        remaining = wrapped.total
    else
        remaining = math.floor((getTimestampMs() - (win.typeAt or 0)) * Cinema.cps / 1000)
    end
    win.typing = remaining < wrapped.total
    win.npcReply:setVisible(wrapped.scroll)
    if wrapped.scroll then
        local shown = Cinema.cut(wrapped.text, math.max(0, remaining))
        local text = pal.rich.text .. shown
        if win.npcReply.text ~= text then
            win.npcReply.defaultFont = wrapped.font
            win.npcReply.text = text
            win.npcReply:paginate()
        end
    else
        for index, line in ipairs(wrapped.lines) do
            if remaining <= 0 then break end
            Cinema.say(win, Cinema.cut(line, remaining), x + m.pad, top + (index - 1) * wrapped.lineH, pal.text, 1, wrapped.font)
            remaining = remaining - #line - 1
        end
    end
    if win.typing then
        Cinema.sayRight(win, win.s.skip, x + w - m.pad, y + 4, pal.dim, 0.8)
    end
end

function Cinema.drawOpinion(win)
    local m, pal = win.m, Cinema.pal
    local label, _, value = win:opinionState()
    win.opShown = (win.opShown or 0) + (value - (win.opShown or 0)) * 0.12
    local x, y, w = m.lx, m.opY, m.lw
    Cinema.say(win, win.s.opinion, x, y, pal.dim, 1)
    local sign = value > 0 and "+" or ""
    local numberText = sign .. tostring(math.floor(value + 0.5))
    local change = win.opDelta
    if type(change) == "table" then
        local age = getTimestampMs() - change.at
        if age < 3000 then
            local fade = age < 2000 and 1 or (3000 - age) / 1000
            local text = (change.n > 0 and "+" or "") .. tostring(change.n)
            local good = change.n > 0
            local width = Cinema.measure(UIFont.Small, numberText) + 8
            win:drawTextRight(text, x + w - width, y, good and 0.55 or 0.95, good and 0.9 or 0.42, good and 0.5 or 0.36, fade,
                UIFont.Small)
        end
    end
    Cinema.sayRight(win, numberText, x + w, y, pal.dim, 1)
    local barY = y + m.u + 3
    local barH = math.max(10, math.floor(m.u * 0.7))
    Cinema.back(win, x, barY, w, barH, pal.bar, 1)
    Cinema.frame(win, x, barY, w, barH, pal.edge, 0.9)
    local half = math.floor((w - 2) / 2)
    local centre = x + 1 + half
    local size = math.floor(half * math.abs(win.opShown) / 100)
    local r, g, b = Cinema.opinionColor(win.opShown)
    if win.opShown >= 0 then
        win:drawRect(centre, barY + 2, size, barH - 4, 0.95, r, g, b)
    else
        win:drawRect(centre - size, barY + 2, size, barH - 4, 0.95, r, g, b)
    end
    Cinema.fill(win, centre, barY - 2, 1, barH + 4, pal.text, 0.8)
    win:drawTextCentre(label, x + math.floor(w / 2), barY + barH + 4, r, g, b, 1, UIFont.Small)
end

function Cinema.drawSilhouette(win)
    local m, pal = win.m, Cinema.pal
    local x, y, w, h = m.lx, m.portraitY, m.lw, m.ph
    local head = math.floor(w * 0.26)
    local cx = x + math.floor(w / 2)
    Cinema.fill(win, cx - math.floor(head / 2), y + math.floor(h * 0.18), head, math.floor(head * 1.15), pal.edge, 0.8)
    Cinema.fill(win, cx - math.floor(head * 0.2), y + math.floor(h * 0.18 + head * 1.15), math.floor(head * 0.4), math.floor(head * 0.3), pal.edge, 0.8)
    Cinema.fill(win, cx - math.floor(w * 0.3), y + math.floor(h * 0.18 + head * 1.45), math.floor(w * 0.6), math.floor(h * 0.4), pal.edge, 0.8)
end

function Cinema.wrapDoLine(win)
    local wrap = Cinema.wrap(UIFont.Small, win.doLine, win.m.lw)
    if #wrap > 2 then
        local rest = wrap[2]
        for index = 3, #wrap do rest = rest .. " " .. wrap[index] end
        wrap[2] = Cinema.fit(UIFont.Small, rest, win.m.lw)
        for index = #wrap, 3, -1 do wrap[index] = nil end
    end
    win.doWrap = wrap
    return wrap
end

function Cinema.drawDoLine(win)
    local m, pal = win.m, Cinema.pal
    if win.doLine == nil or m.doH <= 0 then return end
    local wrap = win.doWrap
    if wrap == nil then wrap = Cinema.wrapDoLine(win) end
    for index = 1, #wrap do Cinema.say(win, wrap[index], m.lx, m.doY + (index - 1) * (m.u + 1), pal.dim, 1) end
end

function Cinema.wrapDesc(win)
    local wrap = Cinema.wrap(UIFont.Small, win.visitor.header.desc or "", win.m.lw)
    if #wrap > 2 then
        local rest = wrap[2]
        for index = 3, #wrap do rest = rest .. " " .. wrap[index] end
        wrap[2] = Cinema.fit(UIFont.Small, rest, win.m.lw)
        for index = #wrap, 3, -1 do wrap[index] = nil end
    end
    win.descWrap = wrap
    return wrap
end

function Cinema.drawDesc(win)
    local m, pal = win.m, Cinema.pal
    local wrap = win.descWrap
    if wrap == nil then wrap = Cinema.wrapDesc(win) end
    for index = 1, #wrap do Cinema.say(win, wrap[index], m.lx, m.subY + (index - 1) * (m.u + 1), pal.dim, 1) end
end

function Cinema.drawIdentity(win)
    local m, pal = win.m, Cinema.pal
    if win.visitor ~= nil then
        Cinema.drawDesc(win)
        if type(win.opinion) == "table" then Cinema.drawOpinion(win) end
        Cinema.drawDoLine(win)
        return
    end
    if win.mystery == true then
        local held = win.holdLine
        if held ~= nil and held ~= "" then Cinema.say(win, Cinema.fit(UIFont.Small, held, m.lw), m.lx, m.subY, pal.dim, 1) end
        if type(win.opinion) == "table" then Cinema.drawOpinion(win) end
        Cinema.drawDoLine(win)
        return
    end
    local role, faction = win.roleName, win.factionName
    local y = m.subY
    if role ~= nil and role ~= "" then
        Cinema.say(win, Cinema.fit(UIFont.Small, role, m.lw), m.lx, y, pal.accent, 0.9)
        y = y + m.u + 2
    end
    if faction ~= nil and faction ~= "" then
        Cinema.say(win, Cinema.fit(UIFont.Small, faction, m.lw), m.lx, y, pal.dim, 1)
    end
    local r, g, b = Menu.attitudeColor(win.stance)
    local word = Cinema.stanceWord(win.stance)
    local badgeW = math.min(m.lw, Cinema.measure(UIFont.Small, word) + 22)
    win:drawRect(m.lx, m.badgeY, badgeW, m.badgeH, 0.16, r, g, b)
    win:drawRectBorder(m.lx, m.badgeY, badgeW, m.badgeH, 0.85, r, g, b)
    win:drawRect(m.lx, m.badgeY, 4, m.badgeH, 1, r, g, b)
    win:drawText(word, m.lx + 12, m.badgeY + 4, r, g, b, 1, UIFont.Small)
    Cinema.drawOpinion(win)
    Cinema.drawDoLine(win)
end

function Cinema.drawBody(win)
    local m, pal = win.m, Cinema.pal
    local w, h = win.width, win.height
    win:syncReply()
    Cinema.back(win, 0, 0, w, h, pal.back, 0.97)
    Cinema.frame(win, 0, 0, w, h, pal.edge, 1)
    Cinema.frame(win, 3, 3, w - 6, h - 6, pal.edge, 0.35)
    Cinema.brackets(win, 0, 0, w, h, m.pad, pal.accent, 0.9)
    Cinema.back(win, m.lx, m.portraitY, m.lw, m.ph, pal.panel, 1)
    if win.portrait == nil then Cinema.drawSilhouette(win) end
    Cinema.frame(win, m.lx, m.portraitY, m.lw, m.ph, pal.edge, 0.95)
    Cinema.brackets(win, m.lx, m.portraitY, m.lw, m.ph, math.floor(m.pad * 0.8), pal.accent, 0.9)
    Cinema.say(win, Cinema.fit(UIFont.Medium, win:shownName(), m.lw), m.lx, m.nameY, pal.bright, 1, UIFont.Medium)
    Cinema.drawIdentity(win)
    local joined = m.logH + m.nhNow
    Cinema.back(win, m.rx, m.logY, m.rw, joined, pal.bar, 0.9)
    Cinema.drawNpcBox(win)
    Cinema.frame(win, m.rx, m.logY, m.rw, joined, pal.edge, 0.8)
    local barText
    if win.waitingAt ~= nil or win.pending ~= nil or win.interrupted then
        barText = win:statusText()
    elseif win.joypadData ~= nil then
        barText = win.s.hintPad
    else
        barText = win.s.hintKeys
    end
    if barText ~= nil then
        Cinema.say(win, barText, m.rx + 4, m.bottomY + math.floor((m.bottomH - m.u) / 2), pal.dim, 1)
    end
end

function W:prerender()
    if self.failed ~= nil then return end
    Cinema.opa = ProjectALife.TalkUi.opacity()
    local ok, err = pcall(Cinema.drawBody, self)
    if not ok then self.failed = tostring(err) end
end

function W:render()
end

function W:onMouseDown(x, y)
    local m = self.m
    if m ~= nil and m.nhNow > 0 and x >= m.rx and x <= m.rx + m.rw and y >= m.npcY and y <= m.npcY + m.nhNow then
        self:skipType()
        return true
    end
    return Base.onMouseDown(self, x, y)
end

function W:pickIndex(index)
    local row = self.rows ~= nil and self.rows[index] or nil
    if row ~= nil and row.choice ~= nil and row.enable == true and row:isVisible() then self:choose(row) end
end

function W:isKeyConsumed(key)
    if self.failed ~= nil or not self:isVisible() then return false end
    return Cinema.consumes(key)
end

function W:onKeyPress(key)
    if self.failed ~= nil or not self:isVisible() or not Cinema.consumes(key) then return end
    local keys = Keyboard
    if key >= keys.KEY_1 and key <= keys.KEY_9 then
        self:pickIndex(key - keys.KEY_1 + 1)
    elseif key == keys.KEY_SPACE then
        if self.typing then self:skipType()
        elseif self.cursorOn then self:pickIndex(self.cursor or 1) end
    elseif key == keys.KEY_UP then
        self.cursorOn = true
        self:moveCursor(-1)
    elseif key == keys.KEY_DOWN then
        self.cursorOn = true
        self:moveCursor(1)
    elseif key == keys.KEY_LEFT then
        self:cycleTopic(-1)
    elseif key == keys.KEY_RIGHT or key == keys.KEY_TAB then
        self:cycleTopic(1)
    elseif key == keys.KEY_NEXT or key == keys.KEY_PRIOR then
        if self.more:isVisible() and self.more.enable then self:nextPage() end
    end
end

function W:onKeyRelease(key)
    if self.failed ~= nil or not self:isVisible() then return end
    if Keyboard ~= nil and key == Keyboard.KEY_ESCAPE then self:close() end
end

function W:update()
    Base.update(self)
    if self.failed == nil and self.joypadData ~= nil and self.joypadData.focus == self
            and self.npcReply ~= nil and self.npcReply:isVisible()
            and type(getJoypadAimingAxisY) == "function" and type(getJoypadAimingAxisX) == "function" then
        self.npcReply:doRightJoystickScrolling(self.joypadData, 0, 20)
    end
    if self.failed ~= nil then Cinema.fallback(self, self.failed) end
end

function Cinema.fallback(panel, reason)
    if panel.fellBack == true then return end
    panel.fellBack = true
    Cinema.disabled = true
    print("[A-Life] Cinematic talk window failed, using Classic: " .. string.sub(tostring(reason), 1, 160))
    local args = panel.openArgs
    pcall(panel.close, panel)
    if Menu.instance == panel then Menu.instance = nil end
    if args ~= nil then
        pcall(Menu.openClassic, args.playerNum, args.uid, args.shell, args.name, args.faction, args.role, args.known,
            args.doorChoice)
    end
end

function Cinema.discard()
    local panel = Cinema.building
    Cinema.building = nil
    if panel == nil then panel = Cinema.opened end
    Cinema.opened = nil
    if panel == nil then return end
    pcall(panel.removeFromUIManager, panel)
    if Menu.instance == panel then Menu.instance = nil end
end

function Cinema.open(playerNum, uid, shell, name, faction, role, known, doorChoice)
    local firstChoice = ProjectALife.TalkIntents.choices[1]
    if doorChoice ~= nil then
        firstChoice = nil
        for _, choice in ipairs(ProjectALife.TalkIntents.choices) do
            if choice.door == true and choice.id == doorChoice then firstChoice = choice; break end
        end
        if firstChoice == nil then return false end
    end
    if Menu.instance ~= nil then
        Menu.instance:close()
        Menu.instance:removeFromUIManager()
    end
    local core = getCore()
    local width, height = Cinema.size(core:getScreenWidth(), core:getScreenHeight(),
        getTextManager():getFontHeight(UIFont.Small))
    local panel = W:new(math.floor((core:getScreenWidth() - width) / 2), math.floor((core:getScreenHeight() - height) / 2),
        width, height)
    Cinema.building = panel
    panel:setWantKeyEvents(true)
    panel.isCinema = true
    panel.uid, panel.playerNum, panel.player = uid, playerNum, getSpecificPlayer(playerNum)
    panel.shell, panel.npcName, panel.factionName, panel.roleName = shell, name, faction, role
    panel.openArgs = { playerNum = playerNum, uid = uid, shell = shell, name = name, faction = faction, role = role,
        known = known, doorChoice = doorChoice }
    if known ~= nil then panel.known = known == true end
    Menu.maskIdentity(panel)
    Menu.prepareVisitor(panel, Menu.recordFor(uid))
    if panel.doorPeer == true then
        local need = panel:neededHeight(Cinema.compactRows)
        if need < height then
            height = math.max(need, 440)
            panel:setHeight(height)
            panel:setY(math.floor((core:getScreenHeight() - height) / 2))
        end
    end
    if JoypadState ~= nil and type(JoypadState.players) == "table" then
        panel.joypadData = JoypadState.players[(tonumber(playerNum) or 0) + 1]
    end
    Menu.visits = Menu.visits + 1
    panel.sessionId = tostring(getTimestampMs()) .. ":" .. tostring(Menu.visits)
    panel:initialise()
    panel:addToUIManager()
    Menu.instance = panel
    Cinema.building = nil
    Cinema.opened = panel
    if panel.joypadData ~= nil and type(setJoypadFocus) == "function" then setJoypadFocus(playerNum, panel) end
    panel:choose({ choice = firstChoice })
    Cinema.opened = nil
    return true
end

Menu.openClassic = Menu.open

function Menu.open(playerNum, uid, shell, name, faction, role, known, doorChoice)
    if Cinema.wanted() then
        local ok, result = pcall(Cinema.open, playerNum, uid, shell, name, faction, role, known, doorChoice)
        if ok then return result end
        Cinema.disabled = true
        print("[A-Life] Cinematic talk window failed to open, using Classic: " .. string.sub(tostring(result), 1, 160))
        Cinema.discard()
    end
    return Menu.openClassic(playerNum, uid, shell, name, faction, role, known, doorChoice)
end

function Cinema.onReply(module, command, args)
    if module ~= "ProjectALife" or command ~= "talkResult" or type(args) ~= "table" then return end
    local panel = Menu.instance
    if panel == nil or panel.isCinema ~= true or panel.failed ~= nil or not panel:isVisible()
            or tostring(args.uid) ~= panel.uid or args.sessionId ~= panel.sessionId then return end
    panel:takeExtras(args)
end

function Cinema.guardedReply(module, command, args)
    local ok, err = pcall(Cinema.onReply, module, command, args)
    if not ok then
        local panel = Menu.instance
        if panel ~= nil and panel.isCinema == true then panel.failed = tostring(err) end
    end
end

Cinema.baseReceive = Menu.receive

function Cinema.receive(module, command, args)
    Cinema.baseReceive(module, command, args)
    Cinema.guardedReply(module, command, args)
end

ProjectALife.TalkClientReceive = Cinema.receive

if type(Events) == "table" and Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(Cinema.guardedReply) end

return Cinema
