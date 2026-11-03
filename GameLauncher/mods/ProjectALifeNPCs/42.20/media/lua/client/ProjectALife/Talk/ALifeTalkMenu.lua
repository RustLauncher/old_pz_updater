require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ProjectALife/Talk/ALifeTalkIntents"
require "ProjectALife/Talk/ALifeTalkSocialRows"
require "ProjectALife/Talk/ALifeTalkOrderRows"
require "ProjectALife/Talk/ALifeTalkWinterRows"
require "ProjectALife/Talk/ALifePartyRows"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Talk/ALifeVisitorDoLines"
require "ProjectALife/Records/ALifeNames"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local Menu = { instance = nil, visits = 0, topics = { "Personal", "World", "Supplies" }, stanceCache = {} }
ProjectALife.TalkMenu = Menu
Menu.utf16Units = pcall(string.char, 256)
local Window = ISCollapsableWindow:derive("ALifeConversationWindow")
Menu.Window = Window
local Text = ProjectALife.Text

Menu.attitudes = {
    friendly = { r = 0.55, g = 0.85, b = 0.50 }, neutral = { r = 0.82, g = 0.82, b = 0.72 },
    careful = { r = 0.92, g = 0.70, b = 0.32 }, hostile = { r = 0.95, g = 0.38, b = 0.32 },
}
Menu.themes = {
    classic = {
        back = { r = 0.035, g = 0.042, b = 0.038, a = 0.97 }, border = { r = 0.34, g = 0.39, b = 0.31, a = 1 },
        listBack = { r = 0.015, g = 0.02, b = 0.017, a = 0.85 }, listBorder = { r = 0.2, g = 0.25, b = 0.2, a = 1 },
        tabOn = { r = 0.24, g = 0.30, b = 0.20, a = 1 }, tabOff = { r = 0.07, g = 0.08, b = 0.07, a = 0.95 },
        row = { r = 0.055, g = 0.068, b = 0.054, a = 0.95 }, rowBorder = { r = 0.22, g = 0.28, b = 0.2, a = 1 },
        name = { r = 0.92, g = 0.94, b = 0.82 }, sub = { r = 0.58, g = 0.64, b = 0.56 }, status = { r = 0.5, g = 0.55, b = 0.5 },
        rich = { note = " <RGB:0.55,0.58,0.52> ", you = " <RGB:0.82,0.68,0.40> ", npc = " <RGB:0.62,0.84,0.58> ", text = " <RGB:0.88,0.88,0.82> " },
    },
    alife = {
        back = { r = 0.070, g = 0.086, b = 0.094, a = 0.97 }, border = { r = 0.24, g = 0.33, b = 0.36, a = 1 },
        listBack = { r = 0.050, g = 0.062, b = 0.068, a = 0.88 }, listBorder = { r = 0.20, g = 0.28, b = 0.31, a = 1 },
        tabOn = { r = 0.17, g = 0.25, b = 0.28, a = 1 }, tabOff = { r = 0.092, g = 0.114, b = 0.124, a = 0.95 },
        row = { r = 0.100, g = 0.122, b = 0.132, a = 0.95 }, rowBorder = { r = 0.24, g = 0.33, b = 0.36, a = 1 },
        name = { r = 0.96, g = 0.98, b = 0.97 }, sub = { r = 0.58, g = 0.65, b = 0.65 }, status = { r = 0.58, g = 0.65, b = 0.65 },
        rich = { note = " <RGB:0.58,0.66,0.66> ", you = " <RGB:0.52,0.74,0.79> ", npc = " <RGB:0.60,0.86,0.74> ", text = " <RGB:0.90,0.92,0.90> " },
    },
}
Menu.colors = Menu.themes.classic

function Menu.themeName()
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.talkTheme) == "function" and prefs.talkTheme() == "Classic" then return "classic" end
    return "alife"
end

function Menu.theme()
    return Menu.themes[Menu.themeName()] or Menu.themes.alife
end

function Menu.applyTheme()
    Menu.colors = Menu.theme()
    return Menu.colors
end

function Menu.mystery()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" and vars.Talk_MysteryMode == false then return false end
    return true
end

function Menu.holdText(shell)
    if shell == nil or type(shell.getPrimaryHandItem) ~= "function" then return nil end
    local ok, item = pcall(shell.getPrimaryHandItem, shell)
    if not ok or item == nil or type(item.getDisplayName) ~= "function" then return nil end
    local name = item:getDisplayName()
    if type(name) ~= "string" or name == "" then return nil end
    return Text.ui("Holding {item}", { item = name })
end

function Menu.copyColor(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

function Menu.fade(color)
    return { r = color.r, g = color.g, b = color.b, a = (color.a or 1) * ProjectALife.TalkUi.opacity() }
end

Menu.noChoices = {}

function Menu.markSuffix(mark)
    if mark == nil then return nil end
    if mark.asked then return Text.ui("(asked)") end
    if mark.new then return Text.ui("(new)") end
    if mark.later then return Text.ui("(later)") end
    return nil
end

Menu.refusals = { refused = true, trade_refused_opinion = true, talk_refused = true, visitor_hostile = true,
    transfer_refused = true }
Menu.waiting = { rate_limited = true, visit_tell_busy = true, conversation_clock_unavailable = true,
    trade_clock_unavailable = true }
Menu.giveIntents = { DOOR_GIVE = true, DOOR_TREAT = true, DOOR_LEND = true, DOOR_TREAT_ME = true }
Menu.pickIntents = { DOOR_GIVE = true, DOOR_TREAT = true, DOOR_LEND = true }
Menu.leaveIntents = { DOOR_LEAVE = true, DOOR_LEAVE_RUDE = true, GUEST_LEAVE = true }

function Menu.visitorRecord(panel)
    if panel == nil or panel.uid == nil then return nil end
    local record = Menu.recordFor(panel.uid)
    if record == nil then return nil end
    if ProjectALife.TalkUi.visitStamp(record) ~= nil or panel.doorPeer == true or panel.visitor ~= nil then return record end
    return nil
end

function Menu.pickPrompt(intent)
    if intent == "DOOR_LEND" then return "gift_pick_tool" end
    return intent == "DOOR_TREAT" and "gift_pick_meds" or "gift_pick_food"
end

function Menu.pickerRow(row, intent)
    local shown = row.name .. " x" .. tostring(row.count)
    if row.wanted == true then shown = shown .. "  " .. Text.ui("(asked for)") end
    return { id = intent, text = shown, itemId = row.itemId, gift = true }
end

function Menu.outcomeOf(intent, args)
    if args.ok ~= true then
        local reason = tostring(args.reason)
        if Menu.refusals[reason] then return "refused" end
        if Menu.waiting[reason] then return "waiting" end
        return nil
    end
    if Menu.giveIntents[intent] then
        if args.giftPicker ~= nil or args.giftPrompt ~= nil then return nil end
        if args.wantDeclined == true then return "answered" end
        return "gave"
    end
    if intent == "DOOR_WEAPONS_DOWN" then return "disarmed" end
    if intent == "DOOR_SEARCH" then return "searched" end
    if intent == "DOOR_INVITE" then return "invited" end
    if Menu.leaveIntents[intent] then return "sent_away" end
    return "answered"
end

function Menu.canTalk(shell, record)
    if type(ProjectALife.Speech.talkable) == "function" then
        return ProjectALife.Speech.talkable(shell, record)
    end
    return type(record) == "table" and record.lifecycle == "active"
        and shell ~= nil and type(shell.isDead) == "function" and not shell:isDead()
end

function Menu.stanceText(stance)
    local id = stance or ""
    local shown = Menu.stanceCache[id]
    if shown == nil then
        if id == "friendly" then shown = Text.ui("Friendly - glad to talk to you")
        elseif id == "neutral" then shown = Text.ui("Neutral - will hear you out")
        elseif id == "careful" then shown = Text.ui("Wary - wants you to keep your distance")
        elseif id == "hostile" then shown = Text.ui("Hostile - not in a talking mood")
        else shown = Text.ui("Sizing you up...") end
        Menu.stanceCache[id] = shown
    end
    return shown
end

function Menu.attitudeColor(stance)
    local attitude = Menu.attitudes[stance or ""]
    if attitude == nil then return 0.62, 0.64, 0.6 end
    return attitude.r, attitude.g, attitude.b
end

function Menu.layout(height, fontHeight)
    local row = math.max(26, fontHeight + 10)
    local header = math.max(fontHeight * 4 + 60, height >= 600 and 122 or 80)
    local reading = math.max(60, fontHeight * 4 + 12)
    local slots = math.max(1, math.min(9, math.floor((height - header - reading - 3 * row - 42) / (row + 2))))
    return row, header, slots, math.max(30, height - header - slots * (row + 2) - 3 * row - 42)
end

function Menu.size(screenWidth, screenHeight, fontHeight)
    local width = math.max(520, math.min(fontHeight * 36, 900))
    local height = math.max(560, math.min(fontHeight * 46, 1500))
    return math.min(width, screenWidth - 24), math.min(height, screenHeight - 24)
end

function Menu.groups(panel)
    local custom = ProjectALife.VisitorPanel
    if panel ~= nil and panel.visitor ~= nil and custom ~= nil then return custom.groups(panel) end
    if panel ~= nil and panel.doorPeer == true then return { { id = "Personal", label = "Visit", visitor = true } } end
    local groups = ProjectALife.TalkIntents.groups
    if type(groups) == "table" and #groups > 0 then return groups end
    local fallback = {}
    for _, topic in ipairs(Menu.topics) do fallback[#fallback + 1] = { id = topic, label = topic } end
    return fallback
end

function Menu.groupLabel(group)
    if group.visitor then return Text.ui("Visit") end
    if group.id == "Personal" then return Text.ui("Talk") end
    if group.id == "World" then return Text.ui("Ask") end
    if group.id == "Supplies" then return Text.ui("Supplies") end
    return Text.ui(tostring(group.label or group.id))
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(false)
    local theme = Menu.applyTheme()
    self.theme = theme
    self.backgroundColor = Menu.fade(theme.back)
    self.borderColor = Menu.copyColor(theme.border)
    self.lines, self.buttons, self.tabs = {}, {}, {}
    self.topic, self.turn = Menu.groups(self)[1].id, Menu.visits
    self.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local transcriptHeight
    self.rowHeight, self.headerHeight, self.choiceSlots, transcriptHeight = Menu.layout(self.height, self.fontHeight)
    self.page = 1
    self.titleTop = type(self.titleBarHeight) == "function" and self:titleBarHeight() or 16
    self.transcript = ISRichTextPanel:new(16, self.headerHeight, self.width - 32, transcriptHeight)
    self.transcript:initialise()
    self.transcript.autosetheight = false
    self.transcript.clip = true
    self.transcript.backgroundColor = Menu.fade(theme.listBack)
    self.transcript.borderColor = Menu.copyColor(theme.listBorder)
    self.transcript:addScrollBars()
    self:addChild(self.transcript)
    self.choiceTop = self.transcript.y + self.transcript.height + 12
    local groups = Menu.groups(self)
    local slots = self.visitor ~= nil and ProjectALife.VisitorPanel.slots(self) or #groups
    local tabWidth = (self.width - 32) / #groups
    for index = 1, slots do
        local group = groups[index] or groups[#groups]
        local topic = group.id
        local button = ISButton:new(16 + (index - 1) * tabWidth, self.choiceTop, tabWidth - 4, self.rowHeight,
            Menu.groupLabel(group), self, Window.selectTopic)
        button:initialise()
        button.topic = topic
        button.backgroundColor = Menu.fade(Menu.colors.tabOff)
        self.tabs[#self.tabs + 1] = button
        self:addChild(button)
    end
    if self.visitor ~= nil then ProjectALife.VisitorPanel.syncTabs(self) end
    for index = 1, self.choiceSlots do
        local button = ISButton:new(16, self.choiceTop + self.rowHeight + 6 + (index - 1) * (self.rowHeight + 2),
            self.width - 32, self.rowHeight, "", self, Window.choose)
        button:initialise()
        button.backgroundColor = Menu.fade(Menu.colors.row)
        button.borderColor = Menu.copyColor(Menu.colors.rowBorder)
        self:addChild(button)
        self.buttons[#self.buttons + 1] = button
    end
    self.statusY = self.height - self.rowHeight * 2 - 18
    self.more = ISButton:new(16, self.statusY, self.width - 32, self.rowHeight, Text.ui("More"), self, Window.nextPage)
    self.more:initialise()
    self:addChild(self.more)
    self.leave = ISButton:new(16, self.height - self.rowHeight - 12, self.width - 32, self.rowHeight,
        Text.ui("Leave"), self, Window.close)
    self.leave:initialise()
    self:addChild(self.leave)
    self:refreshChoices()
    if self.shell ~= nil and self.headerHeight > 100 then
        local size = math.max(60, math.min(96, self.headerHeight - self.titleTop - 12))
        local portrait = ISUI3DModel:new(16, self.titleTop + 6, size - 2, size)
        portrait:initialise()
        self:addChild(portrait)
        portrait:setCharacter(self.shell)
        portrait:setIsometric(false)
        portrait:setDirection(IsoDirections.S)
        portrait:setDoRandomExtAnimations(false)
        portrait:setState("idle")
        portrait:setZoom(10)
        portrait:setYOffset(-0.75)

        portrait.prerender = function(model) model.javaObject:setAnimate(false) end
        self.portrait = portrait
    end
    self:refreshTitle()
    self:refreshDoLine()
end

function Window:shownName()
    if self.known == true and self.npcName ~= nil then return self.npcName end
    if self.known == false then return Text.ui("Stranger") end
    return self.npcName or Text.ui("Stranger")
end

function Window:refreshTitle()
    local title
    if self.known == true and self.npcName ~= nil then
        title = Text.ui("Talking to {name}", { name = self.npcName })
    else
        title = Text.ui("Talking to a stranger")
    end
    if title ~= self.shownTitle then
        self.shownTitle = title
        self:setTitle(title)
    end
end

function Window:subtitle(width)
    if self.visitor ~= nil and ProjectALife.VisitorPanel ~= nil then return ProjectALife.VisitorPanel.subtitle(self, width or 300) end
    if self.mystery == true then return self.holdLine or "" end
    local role, faction = self.roleName, self.factionName
    if role ~= nil and role ~= "" and faction ~= nil and faction ~= "" then return role .. "  /  " .. faction end
    if role ~= nil and role ~= "" then return role end
    return faction or ""
end

function Window:statusText()
    if self.interrupted then return nil end
    if self.waitingAt ~= nil then return Text.ui("Waiting for an answer...") end
    if self.pending ~= nil then return Text.ui("They asked you something. Pick an answer.") end
    return Text.ui("Press the chat key to say anything else out loud.")
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    local x = self.portrait ~= nil and (self.portrait.x + self.portrait.width + 12) or 16
    local y = (self.titleTop or 16) + 6
    local medium = getTextManager():getFontHeight(UIFont.Medium)
    local theme = self.theme or Menu.themes.classic
    self:drawText(self:shownName(), x, y, theme.name.r, theme.name.g, theme.name.b, 1, UIFont.Medium)
    y = y + medium + 2
    local subtitle = self:subtitle(self.width - x - 16)
    if subtitle ~= "" then
        self:drawText(subtitle, x, y, theme.sub.r, theme.sub.g, theme.sub.b, 1, UIFont.Small)
        y = y + (self.fontHeight or 14) + 4
    end
    if self.mystery ~= true then
        local r, g, b = Menu.attitudeColor(self.stance)
        self:drawText(Menu.stanceText(self.stance), x, y, r, g, b, 1, UIFont.Small)
        y = y + (self.fontHeight or 14) + 2
    end
    local opinion = self.opinion
    if type(opinion) == "table" and type(opinion.label) == "string" then
        local value = tonumber(opinion.value) or 0
        local or_, og, ob = 0.78, 0.78, 0.7
        if value <= -16 then or_, og, ob = 0.92, 0.5, 0.42 elseif value >= 16 then or_, og, ob = 0.6, 0.85, 0.55 end
        local shown = Text.ui(opinion.label)
        local change = self.opDelta
        if type(change) == "table" and getTimestampMs() - change.at < 3500 then
            shown = shown .. (change.n > 0 and "  (+" or "  (") .. tostring(change.n) .. ")"
        end
        self:drawText(shown, x, y, or_, og, ob, 1, UIFont.Small)
        y = y + (self.fontHeight or 14) + 2
    end
    if self.doLine ~= nil then
        if self.doShownFor ~= self.doLine then
            self.doShownFor = self.doLine
            self.doShown = Menu.clip(self.doLine, self.width - x - 16)
        end
        self:drawText(self.doShown, x, y, theme.sub.r, theme.sub.g, theme.sub.b, 1, UIFont.Small)
    end
    if self.more ~= nil and type(self.more.isVisible) == "function" and not self.more:isVisible() then
        local status = self:statusText()
        if status ~= nil then
            self:drawText(status, 18, (self.statusY or 0) + math.floor(((self.rowHeight or 26) - (self.fontHeight or 14)) / 2),
                theme.status.r, theme.status.g, theme.status.b, 1, UIFont.Small)
        end
    end
end

function Menu.clip(text, width)
    local manager = getTextManager()
    if manager:MeasureStringX(UIFont.Small, text) <= width then return text end
    local count = #text
    while count > 1 and manager:MeasureStringX(UIFont.Small, string.sub(text, 1, count) .. "...") > width do
        count = count - 1
    end
    return string.sub(text, 1, count) .. "..."
end

function Window:wantsDoLine()
    return Menu.visitorRecord(self) ~= nil
end

function Window:refreshDoLine()
    local lines = ProjectALife.VisitorDoLines
    local record = Menu.visitorRecord(self)
    if lines == nil or type(lines.pick) ~= "function" or record == nil then
        if self.doLine ~= nil then
            self.doLine, self.doKey, self.doRaw, self.doState, self.doWrap, self.doShown, self.doShownFor =
                nil, nil, nil, nil, nil, nil, nil
        end
        return false
    end
    local trust = type(self.opinion) == "table" and tonumber(self.opinion.value) or nil
    local key = tostring(self.doTurns or 0) .. ":" .. lines.band(trust) .. ":" .. tostring(self.lastIntent)
        .. ":" .. tostring(self.lastOutcome)
    if key == self.doKey and self.doLine ~= nil then return true end
    local ok, text, state, raw = true, nil, nil, nil
    if self.visitor ~= nil then text, state, raw = ProjectALife.VisitorPanel.doLine(self, record, trust) end
    if text == nil then
        ok, text, state, raw = pcall(lines.pick, record, { trust = trust, intent = self.lastIntent,
            outcome = self.lastOutcome, turn = self.doTurns or 0, shell = self.shell, previousRaw = self.doRaw,
            visitor = self.doorPeer == true })
    end
    self.doKey = key
    if not ok or type(text) ~= "string" then return false end
    self.doLine, self.doState, self.doRaw, self.doWrap, self.doShown, self.doShownFor = text, state, raw, nil, nil, nil
    return true
end

function Window:noteReply(args)
    self.doTurns = (self.doTurns or 0) + 1
    self.lastOutcome = Menu.outcomeOf(self.lastIntent, args)
    self:refreshDoLine()
end

function Window:selectTopic(button)
    self.topic, self.page = button.topic, 1
    if self.visitor ~= nil then ProjectALife.VisitorPanel.onTab(self) end
    self:refreshChoices()
end

function Window:nextPage()
    self.page = self.page % math.max(1, self.pageCount or 1) + 1
    self:refreshChoices()
end

function Window:view()
    return { topic = self.topic, stance = self.stance, known = self.known == true, pending = self.pending,
        uid = self.uid, turn = self.turn, record = Menu.recordFor(self.uid), player = self.player,
        surrendered = self.surrendered == true, party = self.party == true, partyTask = self.partyTask == true,
        social = self.social }
end

function Window:arranged(choices)
    local rows = ProjectALife.TalkSocialRows
    if rows == nil or type(rows.arrange) ~= "function" then return choices, {} end
    local list, marks = rows.arrange(choices, self:view())
    return list, marks or {}
end

function Menu.guestInside(panel)
    local record = Menu.recordFor(panel.uid)
    local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
    local guest = memory ~= nil and memory.guest or nil
    return type(guest) == "table"
end

function Menu.cleanLabels(source)
    local labels = {}
    if type(source) ~= "table" then return labels end
    for id, text in pairs(source) do
        if type(id) == "string" and #id <= 32 and type(text) == "string" and #text <= 80 and string.find(text, "[<>]") == nil then
            labels[id] = text
        end
    end
    return labels
end

function Menu.guestLabel(id)
    if id == "DOOR_WHO" then return Text.ui("How are you settling in?") end
    if id == "DOOR_STAY" then return Text.ui("How long are you staying?") end
    if id == "DOOR_COMPANY" then return Text.ui("Is anyone else with you?") end
    if id == "DOOR_HEALTH" then return Text.ui("Are you hurt? Any bites?") end
    return nil
end

function Window:refreshChoices()
    local choices, Intents = {}, ProjectALife.TalkIntents
    local view = self:view()
    local custom = self.visitor ~= nil and ProjectALife.VisitorPanel.owns(self, self.topic)
    for _, choice in ipairs(custom and Menu.noChoices or Intents.choices) do
        if not choice.hidden and not Intents.followHidden(choice) and (not choice.door or self.doorPeer == true)
                and (self.doorPeer ~= true or choice.door)
                and (not choice.door or type(self.doorChoices) ~= "table" or self.doorChoices[choice.id] == true)
                and ((self.pending ~= nil and choice.answer and Intents.answers(choice, self.pending))
                or (choice.answerTo ~= nil and Intents.answers(choice, self.pending))
                or (self.pending == nil and Intents.offered(choice, view))) then
            choices[#choices + 1] = choice
        end
    end
    local marks
    choices, marks = self:arranged(choices)
    if custom then
        choices, marks = ProjectALife.VisitorPanel.rows(self, self.topic), ProjectALife.VisitorPanel.marks(self, self.topic)
    end
    if type(self.giftPicker) == "table" then
        choices, marks = {}, {}
        for _, row in ipairs(self.giftPicker.rows) do
            choices[#choices + 1] = Menu.pickerRow(row, self.giftPicker.intent)
        end
        choices[#choices + 1] = { id = "GIFT_CANCEL", text = Text.ui("Cancel"), localOnly = true }
    end
    self.marks = marks
    self.pageCount = math.max(1, math.ceil(#choices / self.choiceSlots))
    self.page = math.min(self.page, self.pageCount)
    self.more:setVisible(self.pageCount > 1)
    self.more:setTitle(Text.ui("More  /  {page} of {count}", { page = self.page, count = self.pageCount }))
    self.more:setEnable(self.waitingAt == nil and not self.interrupted)
    local ready = self.waitingAt == nil and not self.interrupted
    for index, button in ipairs(self.buttons) do
        local choice = choices[(self.page - 1) * self.choiceSlots + index]
        button.choice = choice
        button:setVisible(choice ~= nil)
        if choice ~= nil then
            local label = choice.visitor and choice.text or Text.ui(Intents.choiceLabel(choice, self.turn))
            if self.doorPeer == true and not choice.visitor and Menu.guestInside(self) then
                label = Menu.guestLabel(choice.id) or label
            end
            if self.doorPeer == true and not choice.visitor and type(self.doorLabels) == "table"
                    and self.doorLabels[choice.id] ~= nil and not Menu.guestInside(self) then
                label = Text.ui(self.doorLabels[choice.id])
            end
            if self.pending == "NPC_OPEN" then
                label = choice.id == "YES" and Text.ui("Yeah... I'm doing alright.") or Text.ui("No. Not really.")
            end
            button.spokenText = label
            local mark = marks[choice.id]
            local shown = label
            local suffix = Menu.markSuffix(mark)
            if suffix ~= nil then shown = label .. "  " .. suffix end
            button:setTitle(getTextManager():MeasureStringX(UIFont.Small, shown) <= self.width - 60
                and shown or string.sub(shown, 1, math.max(12, math.floor((self.width - 70) / 9))) .. "...")
            button.tooltip = nil
            if choice.friendly then button.tooltip = Text.ui("Ask to travel with their group; this does not recruit or command them.") end
            if choice.tip ~= nil then button.tooltip = Text.ui(choice.tip) end
            if mark ~= nil and mark.asked then
                button.tooltip = Text.ui("You asked this a moment ago. Asking again will annoy them.")
            elseif mark ~= nil and mark.risky then
                button.tooltip = Text.ui("They may not take this well from someone they hardly know.")
            end
            if self.giftEmpty == true and Menu.pickIntents[choice.id] == true and not choice.gift then
                button.tooltip = Text.ui(Menu.messages[self.giftEmptyReason] or Menu.messages.no_safe_food)
            end
            button.backgroundColor = Menu.fade(mark ~= nil and mark.asked and Menu.colors.tabOff or Menu.colors.row)
        end
        button:setEnable(ready and choice ~= nil and choice.info ~= true and not (self.giftEmpty == true and not choice.gift
            and choice ~= nil and Menu.pickIntents[choice.id] == true))
    end
    for _, tab in ipairs(self.tabs) do
        tab:setEnable(self.pending == nil and self.giftPicker == nil and ready)
        local on = tab.topic == self.topic and self.pending == nil
        tab.backgroundColor = Menu.fade(on and Menu.colors.tabOn or Menu.colors.tabOff)
    end
    self:clampCursor()
end

function Menu.richText(text, panel)
    local font = panel.defaultFont
    local width = panel.maxLineWidth or (panel.width - panel.marginLeft - panel.marginRight)
    return string.gsub(text, "%S+", function(word)
        if getTextManager():MeasureStringX(font, word) <= width then return word end
        local parts, first, index = {}, 1, 1
        while index <= #word do
            local last = index
            while last < #word and ((not Menu.utf16Units and string.byte(word, last + 1) >= 128 and string.byte(word, last + 1) < 192)
                    or (Menu.utf16Units and string.byte(word, last + 1) >= 56320 and string.byte(word, last + 1) <= 57343)) do
                last = last + 1
            end
            if index > first and getTextManager():MeasureStringX(font, string.sub(word, first, last)) > width then
                parts[#parts + 1] = string.sub(word, first, index - 1)
                first = index
            end
            index = last + 1
        end
        parts[#parts + 1] = string.sub(word, first)
        return table.concat(parts, " <LINE> ")
    end)
end

function Window:append(text, speaker)
    text = ProjectALife.AudioPolicy.caption(text)
    if text == nil then return end
    if ProjectALife.Speech ~= nil and type(ProjectALife.Speech.genderedFor) == "function" then
        text = ProjectALife.Speech.genderedFor(text, getSpecificPlayer(self.playerNum))
    end
    if text == self.lastText then return end
    self.lastText = text

    text = string.gsub(string.gsub(text, "<", "("), ">", ")")
    text = Menu.richText(text, self.transcript)

    local line
    local rich = (self.theme or Menu.themes.classic).rich
    if speaker == "A-LIFE" then
        line = rich.note .. text
    else
        local color = speaker == "You" and rich.you or rich.npc
        local shown = speaker
        if speaker == "You" then shown = Text.ui("You") end
        local name = tostring(shown or self:shownName()):gsub("[<>]", "")
        line = color .. name .. ": <SPACE>" .. rich.text .. text
    end
    self.lines[#self.lines + 1] = line
    while #self.lines > 24 do table.remove(self.lines, 1) end
    self.transcript.text = table.concat(self.lines, " <LINE> <LINE> ")
    self.transcript:paginate()
    self.transcript:setYScroll(-math.max(0, self.transcript:getScrollHeight() - self.transcript.height))
end

function Window:choose(button)
    if button.choice == nil or self.waitingAt ~= nil or self.interrupted then return end
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then return end
    if button.choice.localOnly then self.giftPicker = nil; self.page = 1; self:refreshChoices(); return end
    local args = { uid = self.uid, choice = button.choice.id }
    if button.choice.gift then
        if type(self.giftPicker) ~= "table" then return end
        args.gift = { token = self.giftPicker.token, itemId = button.choice.itemId }
    end
    if button.choice.id == "DOOR_TRADE_CONFIRM" then
        if type(self.tradeQuote) ~= "table" or type(self.tradeQuote.token) ~= "string" then return end
        args.quote = self.tradeQuote.token
    end
    if self.visitor ~= nil then ProjectALife.VisitorPanel.decorate(self, args, button.choice) end
    self.lastIntent = button.choice.id
    if not button.choice.hidden then self:append(button.spokenText or button.choice.text, "You") end
    self.waitingAt = getTimestampMs()
    self:refreshChoices()
    self:send("talkChoose", args)
end

function Window:send(command, args)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then return end
    args.sessionId = self.sessionId
    if type(isClient) == "function" and isClient() then
        sendClientCommand(player, "ProjectALife", command, args)
    elseif ProjectALife.Talk ~= nil then
        ProjectALife.Talk.handleClientCommand("ProjectALife", command, player, args)
    else
        self:append(Text.ui("The conversation system is not loaded. Restart after updating the mod."), "A-LIFE")
    end
end

function Window:update()
    ISCollapsableWindow.update(self)
    if not self:isVisible() then return end
    local now = getTimestampMs()
    if self.closeAt ~= nil and now >= self.closeAt then
        self.closeAt = nil
        self:close()
        return
    end
    if self.waitingAt ~= nil and now - self.waitingAt > 5000 then
        self.waitingAt = nil
        self:append(Text.ui("No reply yet. You can try again."), "A-LIFE")
        self:refreshChoices()
    end
    if self.visitor ~= nil then ProjectALife.VisitorPanel.poll(self, now) end
    if self.joypadData ~= nil and self.joypadData.focus == nil and type(setJoypadFocus) == "function" then
        setJoypadFocus(self.playerNum, self)
    end
    if now < (self.nextSessionAt or 0) then return end
    self.nextSessionAt = now + 2000
    local player = getSpecificPlayer(self.playerNum)

    if player == nil or player:isDead() or (self.shell ~= nil
            and (not Menu.canTalk(self.shell, Menu.recordFor(self.uid))
            or math.floor(self.shell:getZ()) ~= math.floor(player:getZ())
            or (self.shell:getX() - player:getX()) ^ 2 + (self.shell:getY() - player:getY()) ^ 2 > 36)
            and not ProjectALife.Speech.orderOkFor(self.uid, player, self.shell, now)) then
        self:close()
        return
    end
    if self.sessionOpen then self:send("talkSession", { uid = self.uid }) end
end

function Window:close()
    if self.sessionOpen then self:send("talkSession", { uid = self.uid, close = true }) end
    self.sessionOpen = nil
    if self.joypadData ~= nil and type(setJoypadFocus) == "function" then
        self.joypadData = nil
        setJoypadFocus(self.playerNum, nil)
    end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end

function Window:usableButtons()
    local list = {}
    for _, button in ipairs(self.buttons or {}) do
        if button.choice ~= nil and button:isVisible() then list[#list + 1] = button end
    end
    return list
end

function Window:clampCursor()
    if self.joypadData == nil then return end
    local list = self:usableButtons()
    self.cursor = math.max(1, math.min(tonumber(self.cursor) or 1, math.max(1, #list)))
    for index, button in ipairs(list) do
        if type(button.setJoypadFocused) == "function" then button:setJoypadFocused(index == self.cursor) end
    end
end

function Window:moveCursor(delta)
    self.cursor = (tonumber(self.cursor) or 1) + delta
    self:clampCursor()
end

function Window:cycleTopic(delta)
    if self.pending ~= nil or #self.tabs == 0 then return end
    local at = 1
    for index, tab in ipairs(self.tabs) do if tab.topic == self.topic then at = index end end
    for _ = 1, #self.tabs do
        at = (at - 1 + delta + #self.tabs) % #self.tabs + 1
        if self.tabs[at].topic ~= nil then break end
    end
    self.cursor = 1
    self:selectTopic(self.tabs[at])
end

function Window:onJoypadDirUp() self:moveCursor(-1) end
function Window:onJoypadDirDown() self:moveCursor(1) end
function Window:onJoypadDirLeft() self:cycleTopic(-1) end
function Window:onJoypadDirRight() self:cycleTopic(1) end

function Window:onJoypadDown(button)
    if Joypad == nil then return end
    if button == Joypad.AButton then
        local target = self:usableButtons()[tonumber(self.cursor) or 1]
        if target ~= nil then self:choose(target) end
    elseif button == Joypad.BButton then
        self:close()
    elseif button == Joypad.LBumper then
        self:cycleTopic(-1)
    elseif button == Joypad.RBumper then
        self:cycleTopic(1)
    elseif button == Joypad.YButton and self.more:isVisible() then
        self:nextPage()
    end
end

function Menu.prepareVisitor(panel, record)
    local stamp = record ~= nil and type(record.memory) == "table" and record.memory.visit or nil
    if type(stamp) == "table" and stamp.generation == record.generation then
        panel.doorPeer, panel.doorChoices, panel.topic = true, {}, "Personal"
    end
    if ProjectALife.VisitorPanel ~= nil then ProjectALife.VisitorPanel.attach(panel, nil, record) end
end

function Menu.open(playerNum, uid, shell, name, faction, role, known, doorChoice)
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
    local width, height = Menu.size(core:getScreenWidth(), core:getScreenHeight(),
        getTextManager():getFontHeight(UIFont.Small))
    local panel = Window:new((core:getScreenWidth() - width) / 2, (core:getScreenHeight() - height) / 2, width, height)
    panel.uid, panel.playerNum, panel.player = uid, playerNum, getSpecificPlayer(playerNum)
    panel.shell, panel.npcName, panel.factionName, panel.roleName = shell, name, faction, role
    if known ~= nil then panel.known = known == true end
    Menu.maskIdentity(panel)
    Menu.prepareVisitor(panel, Menu.recordFor(uid))
    if JoypadState ~= nil and type(JoypadState.players) == "table" then
        panel.joypadData = JoypadState.players[(tonumber(playerNum) or 0) + 1]
    end
    Menu.visits = Menu.visits + 1
    panel.sessionId = tostring(getTimestampMs()) .. ":" .. tostring(Menu.visits)
    panel:initialise()
    panel:addToUIManager()
    Menu.instance = panel
    if panel.joypadData ~= nil and type(setJoypadFocus) == "function" then setJoypadFocus(playerNum, panel) end
    panel:choose({ choice = firstChoice })
end

function Menu.shownLabel(label, plain)
    if Menu.mystery() and type(plain) == "string" then return plain end
    return label
end

function Menu.maskIdentity(panel)
    panel.mystery = Menu.mystery()
    if panel.mystery ~= true then return false end
    panel.factionName, panel.roleName = nil, nil
    if panel.known ~= true then panel.npcName = nil end
    panel.holdLine = Menu.holdText(panel.shell)
    return true
end

Menu.messages = {
    too_far = "Get within six tiles, on the same floor.", blocked = "Get on the same side of the wall first.",
    hostile = "They're hostile. This isn't a good time to chat.", busy = "They're fighting. Try again when it's safe.",
    not_friendly = "They don't trust you enough to travel together.", no_question = "They haven't asked you a yes-or-no question.",
    rate_limited = "Give them a second.", no_reply = "They have nothing to add right now.",
    disabled = "NPC conversations are disabled on this server.", unavailable = "That person is no longer available.",
    session_ended = "The conversation has ended.", surrender_ended = "They lowered their hands.",
    talk_ended = "They ended the conversation.", talk_refused = "They don't want to talk right now.",
    not_door_peer = "They aren't at your door or window right now. Step closer.",
    not_adjacent = "Step closer to them first, about three tiles.", door_not_adjacent = "Stand at the door first.",
    door_closed = "Open the door first.", door_unreachable = "They can't get to the door right now.",
    no_safe_food = "You have no food they would take: nothing rotten, nothing raw.",
    no_safe_meds = "You have no bandage or disinfectant to spare.",
    gift_selection_required = "That list expired. Choose what to give again.",
    gift_item_changed = "That item is no longer available. Choose what to give again.",
    gift_identity_unavailable = "Cannot open the item list right now.",
    gift_pick_food = "Choose one food item to give",
    gift_pick_meds = "Choose one medical supply to give",
    gift_pick_tool = "Choose which tool to lend",
    food_not_requested = "They did not ask for food.", already_treated = "They are already patched up.",
    trade_unavailable = "They have nothing to trade right now.", trader_stock_unavailable = "They have nothing to trade right now.",
    trade_stock_insufficient = "They don't have enough of that.", trade_refused_opinion = "They don't trust you enough to trade.",
    trade_pending = "Finish the offer on the table first.", trade_quote_required = "Ask what they have first.",
    visit_search_busy = "They are still being searched.", visit_tell_busy = "Give them a second.",
    visit_search_done = "You already asked to search them.", inventory_api_unavailable = "Their inventory could not be checked. Try again.",
    resident_away = "Nobody is home to answer.", invalid_choice = "That is not on offer right now.",
    inventory_unavailable = "Something is wrong with the inventory. Try again.",
    fallback = "They aren't answering right now.",
    actor_write_refused = "They couldn't do that just now, try again",
    answered = "They have nothing to add right now", unknown = "They didn't catch that",
    base_round2_required = "Nobody comes by this place yet", house_missing = "They don't seem to know this house",
    runtime_off = "Nobody is coming to the door right now", events_off = "Nobody is coming to the door right now",
    dedicated_server_off = "Nobody is coming to the door right now",
    client_authority = "Only the host can settle that", server_authority_required = "Only the host can settle that",
    bluff_unavailable = "There is nothing to bluff about here", callsign_unavailable = "They don't carry a callsign",
    census_question_required = "They haven't asked you that yet", conversation_clock_unavailable = "Give them a second",
    door_choice_required = "Pick one of the door options to talk to them",
    door_state_unavailable = "You can't tell if the door is open or shut",
    guns_unavailable = "Nobody asked for your guns", invalid_session = "That conversation expired, start a new one",
    invite_unavailable = "They aren't asking to come in", item_persistence_unavailable = "That item can't be handed over right now",
    job_unavailable = "They have no job for you right now", lend_unavailable = "They aren't asking to borrow anything",
    no_fair_trade_cost = "You have nothing they would take in a fair swap", no_tool_to_lend = "You have no spare tool to lend",
    not_enough_items = "You don't have enough items for that", racket_not_enough = "You don't have enough to pay what they want",
    not_walking = "They aren't walking with you", walk_off = "They won't walk with you here",
    payment_not_requested = "They didn't ask for anything", player_unavailable = "You can't do that right now",
    refused = "They said no", transfer_refused = "The hand-over fell through",
    trade_clock_unavailable = "Give them a second", trade_quotes_busy = "They're busy with another offer, give them a second",
    rollback_failed = "The hand-over went wrong, check your bag",
    trade_inventory_changed = "Your bag changed, ask what they have again",
    trade_quote_identity_unavailable = "That offer fell through, ask again", trade_scam_unavailable = "They backed out of the swap",
    trade_service_unavailable = "The swap can't be done right now", trade_transfer_uncertain = "That swap went wrong, check your bag",
    trader_stock_write_failed = "That swap went wrong, check your bag",
    trader_stock_pending = "They're still sorting their stock, give them a second",
    treatment_unavailable = "Nothing to treat right now", visit_plan_unsupported = "They don't know what to say to that",
    visit_relation_unavailable = "They aren't ready to talk", visitor_hostile = "They aren't friendly anymore",
    visit_script_missing = "They have nothing to say right now",
    visitor_row_stale = "That isn't something to ask right now", adult_only = "That isn't something to bring up here",
    not_visitor = "They aren't a guest here", loading = "They are thinking it over, try again in a moment",
    no_player_key = "They can't tell who you are right now", unknown_question = "They don't know what you mean",
    offer_unavailable = "They can't take that from you right now", offer_refused = "They turned your offer down",
    write_failed = "They lost the thread, try that again", unknown_event = "That moment has passed",
}

function Menu.refusalText(reason)
    local key = tostring(reason)
    local text = Menu.messages[key]
    if text == nil then text = Menu.messages[string.match(key, "^[%w_]+") or ""] end
    return text
end

function Menu.learnName(panel, args)
    if type(args.name) == "string" and args.name ~= "" then
        panel.npcName = string.gsub(args.name, "[<>]", "")
    end
    if args.known ~= nil then panel.known = args.known == true end
    if type(args.opinion) == "table" then
        panel.opinion = args.opinion
        local change = tonumber(args.opinion.delta)
        if change ~= nil and change ~= 0 then panel.opDelta = { n = change, at = getTimestampMs() } end
    elseif args.ok ~= nil then
        panel.opinion = nil
    end
    if type(args.social) == "table" then panel.social = args.social end
    if panel.mystery == true then panel.holdLine = Menu.holdText(panel.shell) end
    panel:refreshTitle()
end

function Menu.receive(module, command, args)
    if module ~= "ProjectALife" or type(args) ~= "table" then return end
    local panel = Menu.instance
    if panel == nil or not panel:isVisible() or tostring(args.uid) ~= panel.uid then return end
    if command == "speech" then
        panel:append(args.text)
    elseif command == "visitorMenu" and panel.visitor ~= nil then
        ProjectALife.VisitorPanel.attach(panel, args)
        panel:refreshChoices()
    elseif command == "talkResult" then
        local player = getSpecificPlayer(panel.playerNum)
        if player == nil or player ~= panel.player or type(ProjectALife.Speech.playerKey) ~= "function"
                or args.playerKey ~= ProjectALife.Speech.playerKey(player) or args.sessionId ~= panel.sessionId then return end
        if args.tabOnly == true and panel.visitor ~= nil then
            ProjectALife.VisitorPanel.attach(panel, args)
            panel:refreshChoices()
            return
        end
        panel.waitingAt = nil
        if args.interrupted == true then
            local message = Text.ui(Menu.refusalText(args.reason) or Menu.messages.session_ended)
            panel.interrupted, panel.sessionOpen = true, nil
            panel:append(message, "A-LIFE")
            panel:refreshChoices()
            panel:close()
            if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then HaloTextHelper.addText(player, message) end
            return
        end
        if args.ok ~= true and args.reason == "rate_limited" then
            print("[ALIFE-UI] talk refused reason=rate_limited why=" .. tostring(args.why))
            panel:append(Text.ui(Menu.messages.rate_limited), "A-LIFE")
            panel:refreshChoices()
            return
        end
        Menu.learnName(panel, args)
        if args.doorPeer ~= nil or args.ok == true then panel.doorPeer = args.doorPeer == true end
        panel.doorChoices, panel.doorLabels = nil, nil
        if panel.doorPeer then panel.doorChoices = type(args.doorChoices) == "table" and args.doorChoices or {} end
        if panel.doorPeer then panel.doorLabels = Menu.cleanLabels(args.doorLabels) end
        local quote = args.tradeQuote
        panel.tradeQuote = panel.doorPeer and type(quote) == "table" and type(quote.token) == "string"
            and type(quote.give) == "string" and type(quote.receive) == "string" and quote or nil
        panel.giftPicker = nil
        panel.giftEmpty, panel.giftEmptyReason = args.giftEmpty == true, args.giftEmptyReason
        local gift = args.giftPicker
        if args.ok == true and panel.doorPeer and type(gift) == "table" and type(gift.token) == "string"
                and #gift.token <= 256 and type(gift.rows) == "table"
                and (gift.intent == "DOOR_GIVE" or gift.intent == "DOOR_TREAT" or gift.intent == "DOOR_LEND") then
            local rows = {}
            for index, row in ipairs(gift.rows) do
                if index > 256 then break end
                if type(row) == "table" and type(row.name) == "string" and #row.name <= 160
                        and type(row.count) == "number" and row.count > 0 and row.count <= 256
                        and type(row.itemId) == "number" and row.itemId == row.itemId and row.itemId % 1 == 0 then
                    rows[#rows + 1] = { name = row.name, count = row.count, itemId = row.itemId, wanted = row.wanted == true }
                end
            end
            if #rows > 0 then panel.giftPicker = { token = gift.token, rows = rows, intent = gift.intent } end
        end
        if panel.doorPeer and panel.visitor == nil then panel.topic = "Personal" end
        if args.giftPrompt ~= nil and panel.giftPicker ~= nil then
            panel:append(Text.ui(Menu.messages[Menu.pickPrompt(panel.giftPicker.intent)]), "A-LIFE")
        end
        if args.text ~= nil then panel:append(args.text)
        elseif args.ok ~= true then print("[ALIFE-UI] talk refused reason=" .. tostring(args.reason) .. " why=" .. tostring(args.why)); panel:append(Text.ui(Menu.refusalText(args.reason) or Menu.messages.fallback), "A-LIFE") end
        if args.ok == true and type(args.searchItems) == "table" then
            local items = {}
            for index, item in ipairs(args.searchItems) do
                if index > 32 then break end
                if type(item) == "table" and type(item.name) == "string" and type(item.count) == "number" and item.count > 0 then
                    items[#items + 1] = item.name .. " x" .. tostring(item.count)
                end
            end
            panel:append(#items > 0 and Text.ui("They are carrying:") .. " " .. table.concat(items, ", ")
                or Text.ui("They are not carrying any items."), "A-LIFE")
        end
        if args.stance ~= nil then panel.stance = args.stance end
        if args.surrendered ~= nil then panel.surrendered = args.surrendered == true end
        if args.party ~= nil then panel.party = args.party == true end
        if args.partyTask ~= nil then panel.partyTask = args.partyTask == true end
        if args.ok then panel.pending = args.pending; panel.sessionOpen = true; panel.turn = panel.turn + 1; panel.page = 1 end
        if args.ended == true then
            panel.interrupted, panel.sessionOpen, panel.pending = true, nil, nil
            panel.closeAt = getTimestampMs() + 3600
            if args.reason == "talk_ended" or args.reason == "talk_refused" then
                panel:append(Text.ui(Menu.messages[args.reason]), "A-LIFE")
            end
        end
        if (panel.visitor ~= nil or type(args.visitorMenu) == "table") and ProjectALife.VisitorPanel ~= nil then
            ProjectALife.VisitorPanel.attach(panel, args, Menu.recordFor(panel.uid))
        end
        if type(panel.noteReply) == "function" then panel:noteReply(args) end
        panel:refreshChoices()
    end
end
ProjectALife.TalkClientReceive = Menu.receive

function Menu.recordFor(uid)
    local executor, registry = ProjectALife.Executor, ProjectALife.ActorRegistry
    local mirror = executor ~= nil and executor.mirror or nil
    local record = type(mirror) == "table" and type(mirror.records) == "table" and mirror.records[uid] or nil
    if record == nil and registry ~= nil and type(registry.read) == "function" then record = registry.read(uid) end
    return record
end

function Menu.describe(record, playerKey, index)
    local catalog, names = ProjectALife.Catalog, ProjectALife.Names
    local profile = record and catalog and type(catalog.npc) == "function" and catalog.npc(record.profileId) or nil
    local preset = profile and profile.general and profile.general.name
    local faction = record and catalog and type(catalog.faction) == "function" and catalog.faction(record.factionId) or nil
    local role = nil
    if preset ~= nil and names ~= nil then role = names.role(Text.ui(tostring(preset))) end
    local name, known = nil, false
    if names ~= nil and record ~= nil then name, known = names.shown(record, playerKey) end
    local label, plain
    if known and name ~= nil then label = name
    elseif names ~= nil and record ~= nil and names.of(record) ~= nil then label = Text.ui("Stranger")
    elseif preset ~= nil then label, plain = Text.ui(tostring(preset)), Text.ui("Stranger")
    else label = Text.ui("Survivor {n}", { n = index }) end
    plain = plain or label
    if role ~= nil then label = label .. "  (" .. role .. ")" end
    local factionName = Text.ui(faction and faction.general and faction.general.name or "")
    if known and name ~= nil then return label, name, factionName, role, true, plain end
    if names ~= nil and record ~= nil and names.of(record) ~= nil then return label, nil, factionName, role, false, plain end
    return label, label, factionName, nil, nil, plain
end

function Menu.fill(playerNum, context, worldobjects, test)
    if test == true or type(context) ~= "table" or type(context.addOption) ~= "function"
            or type(context.getNew) ~= "function" or type(context.addSubMenu) ~= "function" then
        return
    end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then return end

    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or type(cell.getZombieList) ~= "function" then return end
    local list = cell:getZombieList()
    if list == nil or type(list.size) ~= "function" or type(list.get) ~= "function" then return end
    local nearby = {}
    local ordered = ProjectALife.Speech.orderLive(getTimestampMs())
    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and type(shell.isDead) == "function" and type(shell.getZ) == "function"
                and type(shell.getX) == "function" and type(shell.getY) == "function"
                and not shell:isDead() then
            local close = math.floor(shell:getZ()) == math.floor(player:getZ())
                and (shell:getX() - player:getX()) ^ 2 + (shell:getY() - player:getY()) ^ 2 <= 36
            local uid, record
            if close or ordered then
                uid = ProjectALife.Speech.variable(shell, "ALifeUID")
                record = uid ~= nil and uid ~= "" and Menu.recordFor(tostring(uid)) or nil
                if not close and record ~= nil then
                    close = ProjectALife.Speech.orderOkFor(tostring(uid), player, shell, getTimestampMs())
                end
            end
            if close and record ~= nil and Menu.canTalk(shell, record) then
                nearby[#nearby + 1] = { uid = tostring(uid), shell = shell, record = record }
            end
        end
    end
    if #nearby == 0 then return end
    local root = context:addOption(Text.ui("[A-LIFE] Talk to someone nearby"))
    local submenu = context:getNew(context)
    context:addSubMenu(root, submenu)
    local playerKey = nil
    if type(ProjectALife.Speech.playerKey) == "function" then playerKey = ProjectALife.Speech.playerKey(player) end
    local taken = {}
    for index, row in ipairs(nearby) do
        if index > 12 then break end
        local label, name, faction, role, known, plain = Menu.describe(row.record, playerKey, index)
        local shown = Menu.shownLabel(label, plain)
        local stamp = ProjectALife.TalkUi.visitStamp(row.record)
        if stamp ~= nil then
            shown = Text.ui("Visitor: {name}", { name = shown })
        end
        if taken[shown] ~= nil then shown = shown .. " " .. tostring(index) end
        taken[shown] = true
        submenu:addOption(shown, playerNum, Menu.open, row.uid, row.shell, name, faction, role, known)
    end
end

if type(Events) == "table" then
    if Events.OnPreFillWorldObjectContextMenu ~= nil then
        Events.OnPreFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(Menu.fill))
    end
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(Menu.receive) end
end
return Menu
