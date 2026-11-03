require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Talk/ALifeSpeechBubbleLayout"
require "ProjectALife/Talk/ALifeSpeechBubbles"

ProjectALife = ProjectALife or {}

local Chat = {
    settings = { windowMs = 10000, perSpeaker = 3, total = 6, duplicateMs = 4000, maxText = 240, holdMs = 16000,
        fadeMs = 2000, maxRows = 10, width = 480, left = 15, bottomGap = 270, tabId = 1, keyCap = 128 },
    recent = {}, recentCount = 0,
    speakers = {}, speakerCount = 0,
    total = { at = 0, count = 0 },
    rows = {}, rowCount = 0,
    panel = nil, class = nil, manager = nil, font = nil, faults = 0, failed = nil, shown = false,
    metrics = { mirrored = 0, chat = 0, panel = 0, duplicate = 0, limited = 0, ambient = 0, faults = 0 },
}
ProjectALife.NpcChat = Chat

Chat.messageMethods = {
    getTextWithPrefix = function(self) return self.line end,
    getAuthor = function(self) return nil end,
    setText = function(self, text) self.line = text end,
}
Chat.messageMeta = { __index = Chat.messageMethods }

function Chat.now()
    if type(getTimestampMs) ~= "function" then return nil end
    return getTimestampMs()
end

function Chat.player()
    local list = ProjectALife.Speech.localPlayers()
    return list[1]
end

function Chat.clean(text)
    local shown = string.gsub(string.gsub(text, "<", "("), ">", ")")
    if #shown > Chat.settings.maxText then shown = string.sub(shown, 1, Chat.settings.maxText - 3) .. "..." end
    return shown
end

function Chat.duplicate(key, text, now)
    local last = Chat.recent[key]
    if last ~= nil and last.text == text and now - last.at < Chat.settings.duplicateMs then return true end
    if last == nil then
        if Chat.recentCount >= Chat.settings.keyCap then
            Chat.recent, Chat.recentCount = {}, 0
        end
        last = {}
        Chat.recent[key] = last
        Chat.recentCount = Chat.recentCount + 1
    end
    last.text, last.at = text, now
    return false
end

function Chat.allow(key, now)
    local s = Chat.settings
    local bucket = Chat.speakers[key]
    if bucket == nil then
        if Chat.speakerCount >= s.keyCap then
            Chat.speakers, Chat.speakerCount = {}, 0
        end
        bucket = { at = now, count = 0 }
        Chat.speakers[key] = bucket
        Chat.speakerCount = Chat.speakerCount + 1
    end
    if now - bucket.at >= s.windowMs then bucket.at, bucket.count = now, 0 end
    local total = Chat.total
    if now - total.at >= s.windowMs then total.at, total.count = now, 0 end
    if bucket.count >= s.perSpeaker or total.count >= s.total then return false end
    bucket.count = bucket.count + 1
    total.count = total.count + 1
    return true
end

function Chat.number(value)
    return string.format("%.2f", value)
end

function Chat.richLine(name, text, r, g, b, tr, tg, tb)
    return " <RGB:" .. Chat.number(r) .. "," .. Chat.number(g) .. "," .. Chat.number(b) .. "> " .. name
        .. ": <SPACE> <RGB:" .. Chat.number(tr) .. "," .. Chat.number(tg) .. "," .. Chat.number(tb) .. "> " .. text
end

function Chat.vanillaTab()
    local chat = ISChat
    if type(chat) ~= "table" or type(chat.addLineInChat) ~= "function" then return nil end
    local instance = chat.instance
    if type(instance) ~= "table" or type(instance.tabs) ~= "table" then return nil end
    if instance.chatText == nil and instance.defaultTab == nil then return nil end
    for index = 1, #instance.tabs do
        local tab = instance.tabs[index]
        if type(tab) == "table" and tab.tabID == Chat.settings.tabId and type(tab.chatTextLines) == "table"
                and type(tab.chatMessages) == "table" then
            return tab
        end
    end
    return nil
end

function Chat.intoVanilla(line)
    if Chat.vanillaTab() == nil then return false end
    local message = setmetatable({ line = line }, Chat.messageMeta)
    return pcall(ISChat.addLineInChat, message, Chat.settings.tabId) == true
end

function Chat.measureCurrent(text)
    return Chat.manager:MeasureStringX(Chat.font, text)
end

function Chat.layerClass()
    if Chat.class ~= nil then return Chat.class end
    if ISUIElement == nil or type(ISUIElement.derive) ~= "function" then return nil end
    local class = ISUIElement:derive("ALifeNpcChatPanel")
    function class:render()
        Chat.paint(self)
    end
    Chat.class = class
    return class
end

function Chat.panelFor()
    local panel = Chat.panel
    if panel ~= nil and panel.removed ~= true then return panel end
    local class = Chat.layerClass()
    if class == nil or type(getCore) ~= "function" then return nil end
    panel = class:new(Chat.settings.left, 0, Chat.settings.width, 10)
    ProjectALife.TalkUi.passThrough(panel)
    panel:initialise()
    panel:addToUIManager()
    panel:setVisible(false)
    Chat.panel = panel
    return panel
end

function Chat.place(panel)
    local s = Chat.settings
    local core = getCore()
    local lineH = Chat.manager:getFontHeight(Chat.font)
    local height = s.maxRows * lineH + 8
    local y = core:getScreenHeight() - s.bottomGap - height
    if y < 0 then y = 0 end
    panel:setX(s.left)
    panel:setY(y)
    panel:setWidth(s.width)
    panel:setHeight(height)
    panel.lineH, panel.screenH = lineH, core:getScreenHeight()
end

function Chat.prune(now)
    local s = Chat.settings
    while Chat.rowCount > 0 and now - Chat.rows[1].at > s.holdMs + s.fadeMs do
        table.remove(Chat.rows, 1)
        Chat.rowCount = Chat.rowCount - 1
    end
end

function Chat.intoPanel(name, text, r, g, b, tr, tg, tb, now)
    local manager = type(getTextManager) == "function" and getTextManager() or nil
    if manager == nil or UIFont == nil then return false end
    local panel = Chat.panelFor()
    if panel == nil then return false end
    Chat.manager, Chat.font = manager, UIFont.Small
    Chat.place(panel)
    local s = Chat.settings
    local prefix = name .. ": "
    local lines = ProjectALife.SpeechBubbleLayout.wrap(prefix .. text, s.width - 16, Chat.measureCurrent)
    if #lines == 0 then return false end
    for index = 1, #lines do
        local row = { s = lines[index], r = tr, g = tg, b = tb, at = now }
        if index == 1 and string.sub(lines[1], 1, #prefix) == prefix then
            row.name, row.nameW, row.s = prefix, manager:MeasureStringX(Chat.font, prefix), string.sub(lines[1], #prefix + 1)
            row.nr, row.ng, row.nb = r, g, b
        end
        Chat.rows[#Chat.rows + 1] = row
        Chat.rowCount = Chat.rowCount + 1
    end
    while Chat.rowCount > s.maxRows do
        table.remove(Chat.rows, 1)
        Chat.rowCount = Chat.rowCount - 1
    end
    panel:setVisible(true)
    return true
end

function Chat.paint(panel)
    local ok, err = pcall(Chat.paintBody, panel)
    if not ok then Chat.fault(err) end
end

function Chat.paintBody(panel)
    local now = Chat.now()
    if now == nil then return end
    Chat.prune(now)
    if Chat.rowCount == 0 then
        panel:setVisible(false)
        return
    end
    local s = Chat.settings
    local core = getCore()
    if panel.screenH ~= core:getScreenHeight() then Chat.place(panel) end
    local lineH = panel.lineH
    local shade = ProjectALife.TalkUi.opacity()
    local newest = Chat.rows[Chat.rowCount]
    local lastAlpha = 1
    local newestAge = now - newest.at
    if newestAge > s.holdMs then lastAlpha = 1 - (newestAge - s.holdMs) / s.fadeMs end
    if lastAlpha > 0 then
        local top = panel.height - 4 - Chat.rowCount * lineH
        panel:drawRect(0, top - 2, panel.width, Chat.rowCount * lineH + 4, 0.42 * shade * lastAlpha, 0.03, 0.04, 0.05)
    end
    for index = 1, Chat.rowCount do
        local row = Chat.rows[index]
        local age = now - row.at
        local alpha = 1
        if age > s.holdMs then alpha = 1 - (age - s.holdMs) / s.fadeMs end
        if alpha > 0.02 then
            local y = panel.height - 4 - (Chat.rowCount - index + 1) * lineH
            local x = 8
            if row.name ~= nil then
                panel:drawText(row.name, x + 1, y + 1, 0, 0, 0, alpha * 0.8, UIFont.Small)
                panel:drawText(row.name, x, y, row.nr, row.ng, row.nb, alpha, UIFont.Small)
                x = x + row.nameW
            end
            panel:drawText(row.s, x + 1, y + 1, 0, 0, 0, alpha * 0.8, UIFont.Small)
            panel:drawText(row.s, x, y, row.r, row.g, row.b, alpha, UIFont.Small)
        end
    end
end

function Chat.fault(err)
    Chat.faults = Chat.faults + 1
    Chat.metrics.faults = Chat.faults
    if Chat.faults >= 3 and Chat.failed == nil then
        Chat.failed = tostring(err)
        print("[ALIFE-UI] npc chat log off for this session: " .. Chat.failed)
    end
end

function Chat.deliver(name, text, r, g, b, tr, tg, tb, now)
    local line = Chat.richLine(name, text, r, g, b, tr, tg, tb)
    if Chat.intoVanilla(line) then
        Chat.metrics.chat = Chat.metrics.chat + 1
        return true
    end
    if Chat.intoPanel(name, text, r, g, b, tr, tg, tb, now) then
        Chat.metrics.panel = Chat.metrics.panel + 1
        return true
    end
    return false
end

function Chat.run(shell, text, color, kind, uid)
    local mode = ProjectALife.TalkUi.chatMode()
    if type(text) ~= "string" or string.find(text, "%S") == nil then return false end
    if uid == nil or tostring(uid) == "" then uid = ProjectALife.Speech.variable(shell, "ALifeUID") end
    if mode == 0 then
        local visitors = ProjectALife.VisitorPanel
        if kind == "ambient" or visitors == nil or not visitors.mirrors(shell, uid) then return false end
        mode = 1
    end
    if kind == "ambient" and mode < 2 then
        Chat.metrics.ambient = Chat.metrics.ambient + 1
        return false
    end
    local now = Chat.now()
    if now == nil then return false end
    local key = tostring(uid or "")
    if Chat.duplicate(key, text, now) then
        Chat.metrics.duplicate = Chat.metrics.duplicate + 1
        return false
    end
    if not Chat.allow(key, now) then
        Chat.metrics.limited = Chat.metrics.limited + 1
        return false
    end
    local bubbles = ProjectALife.SpeechBubbles
    local name = bubbles.nameFor(uid, Chat.player())
    local r, g, b = bubbles.colorOf(color, uid)
    local tr, tg, tb = bubbles.textColor(r, g, b, color)
    if Chat.deliver(name, Chat.clean(text), r, g, b, tr, tg, tb, now) then
        Chat.metrics.mirrored = Chat.metrics.mirrored + 1
        return true
    end
    return false
end

function Chat.mirror(shell, text, color, kind, uid)
    if Chat.failed ~= nil then return false end
    local ok, result = pcall(Chat.run, shell, text, color, kind, uid)
    if not ok then
        Chat.fault(result)
        return false
    end
    return result == true
end

function Chat.qaLine()
    local m = Chat.metrics
    local mode = ProjectALife.TalkUi.chatMode()
    local state = "on"
    if Chat.failed ~= nil then state = "failed" elseif mode == 0 then state = "off" end
    return "[ALIFE-QA] NpcChat: mode=" .. tostring(mode) .. " mirrored=" .. tostring(m.mirrored) .. " chat=" .. tostring(m.chat)
        .. " panel=" .. tostring(m.panel) .. " duplicate=" .. tostring(m.duplicate) .. " limited=" .. tostring(m.limited)
        .. " ambient=" .. tostring(m.ambient) .. " faults=" .. tostring(m.faults) .. " state=" .. state
end

function Chat.reset()
    local panel = Chat.panel
    if panel ~= nil and type(panel.removeFromUIManager) == "function" then pcall(panel.removeFromUIManager, panel) end
    if panel ~= nil then panel.removed = true end
    Chat.panel, Chat.failed, Chat.faults = nil, nil, 0
    Chat.recent, Chat.recentCount, Chat.speakers, Chat.speakerCount = {}, 0, {}, 0
    Chat.total = { at = 0, count = 0 }
    Chat.rows, Chat.rowCount = {}, 0
    Chat.metrics = { mirrored = 0, chat = 0, panel = 0, duplicate = 0, limited = 0, ambient = 0, faults = 0 }
end

if type(Events) == "table" and Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Chat.reset)
end

return Chat
