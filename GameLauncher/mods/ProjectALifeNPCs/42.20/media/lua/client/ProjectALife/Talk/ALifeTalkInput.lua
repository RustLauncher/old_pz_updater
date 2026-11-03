require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "ProjectALife/Core/ALifeText"

ProjectALife = ProjectALife or {}

local Input = {
    settings = { enabled = true, singlePlayerChat = true, helpedIntervalMs = 4000, stateIntervalMs = 500, width = 460, height = 30 },
    box = nil,
    lastHelpedAt = 0,
    watchUntil = 0,
    lastStateAt = 0,
    lastArmed = false,
    lastAiming = false,
    keyPressTicks = 0,
    metrics = { said = 0, sent = 0, emotes = 0, helped = 0, states = 0 },
}
ProjectALife.TalkInput = Input

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function multiplayer()
    return type(isClient) == "function" and isClient()
end

Input.local_ = {
    talkSay = function(talk, player, args)
        return type(talk.onPlayerText) == "function" and pcall(talk.onPlayerText, player, args.text, args.loud == true) == true
    end,
    talkEmote = function(talk, player, args)
        return type(talk.onPlayerEmote) == "function" and pcall(talk.onPlayerEmote, player, args.emote) == true
    end,
    talkHelped = function(talk, player, args)
        return type(talk.onHelped) == "function" and pcall(talk.onHelped, player, args.x, args.y) == true
    end,
    talkState = function(talk, player, args)
        local robbery = ProjectALife.ModuleRobbery

        return robbery ~= nil and type(robbery.onPlayerState) == "function" and pcall(robbery.onPlayerState, player, args) == true
    end,
}

function Input.send(player, kind, args)
    if type(sendClientCommand) ~= "function" then return false end
    Input.metrics.sent = Input.metrics.sent + 1
    if kind == "talkSay" then return pcall(sendClientCommand, player, "ProjectALife", "talkSay", args) == true end
    if kind == "talkEmote" then return pcall(sendClientCommand, player, "ProjectALife", "talkEmote", args) == true end
    if kind == "talkHelped" then return pcall(sendClientCommand, player, "ProjectALife", "talkHelped", args) == true end
    if kind == "talkState" then return pcall(sendClientCommand, player, "ProjectALife", "talkState", args) == true end
    return false
end

function Input.deliver(kind, args)
    local player = getSpecificPlayer(0)
    if player == nil or Input.local_[kind] == nil then return false end
    if multiplayer() then return Input.send(player, kind, args) end
    local talk = ProjectALife.Talk
    if talk == nil then return false end
    return Input.local_[kind](talk, player, args) == true
end

function Input.say(text, loud)
    text = tostring(text or "")
    text = string.gsub(text, "[%c]", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then return false end
    if string.sub(text, 1, 1) == "!" then
        loud = true
        text = string.gsub(string.sub(text, 2), "^%s+", "")
        if text == "" then return false end
    end
    if #text > 200 then text = string.sub(text, 1, 200) end
    Input.metrics.said = Input.metrics.said + 1
    local player = getSpecificPlayer(0)
    if player ~= nil and not multiplayer() then
        pcall(function()
            if loud then player:SayShout(text) else player:Say(text) end
        end)
    end
    return Input.deliver("talkSay", { text = text, loud = loud == true })
end

local Box = ISPanel:derive("ALifeTalkBox")
Input.Box = Box

function Box:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.72 }
    o.borderColor = { r = 0.55, g = 0.55, b = 0.55, a = 0.9 }
    o.moveWithMouse = false
    return o
end

function Box:createChildren()
    ISPanel.createChildren(self)
    self.entry = ISTextEntryBox:new("", 6, 4, self.width - 12, self.height - 8)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.onCommandEntered = function(entry)
        local text = entry:getText()
        Input.close()
        Input.say(text, false)
    end
    self.entry.onOtherKey = function(entry, key)
        if key == Keyboard.KEY_ESCAPE then Input.close() end
    end
    self.entry:setMaxTextLength(200)
    if type(self.entry.setPlaceholderText) == "function" and ProjectALife.Text ~= nil then
        self.entry:setPlaceholderText(ProjectALife.Text.ui("Say something to people nearby. Start with ! to shout."))
    end
    self:addChild(self.entry)
end

function Input.open()
    if Input.box == nil then
        local height = Input.settings.height
        local y = getCore():getScreenHeight() - 260
        Input.box = Box:new(15, y, Input.settings.width, height)
        Input.box:initialise()
        Input.box:addToUIManager()
    end
    Input.box:setVisible(true)
    Input.box:bringToTop()
    Input.box.entry:setText("")
    Input.box.entry:setEditable(true)
    Input.box.entry:focus()
    Input.box.entry:ignoreFirstInput()
end

function Input.close()
    if Input.box == nil then return end
    pcall(function()
        Input.box.entry:unfocus()
        Input.box.entry:setText("")
        Input.box:setVisible(false)
    end)

    if type(doKeyPress) == "function" then
        doKeyPress(false)
        Input.keyPressTicks = 20
    end
end

function Input.chatKey(key)
    local core = getCore()
    if core == nil then return false end
    if type(KeybindId) == "table" then
        if KeybindId.TOGGLE_CHAT ~= nil and core:isKey(KeybindId.TOGGLE_CHAT, key) then return true end
        if KeybindId.ALT_TOGGLE_CHAT ~= nil and core:isKey(KeybindId.ALT_TOGGLE_CHAT, key) then return true end
        return false
    end
    return core:isKey("Toggle chat", key) == true
end

function Input.onKeyPressed(key)
    if Input.settings.enabled ~= true or Input.settings.singlePlayerChat ~= true then return end
    if multiplayer() or ISChat ~= nil and ISChat.instance ~= nil then return end
    if not Input.chatKey(key) then return end
    if Input.box ~= nil and Input.box:isVisible() then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end
    Input.open()
end

function Input.wrapChat()

    if Input.chatWrapped or type(processSayMessage) ~= "function" or type(processShoutMessage) ~= "function" then return end
    local say, shout = processSayMessage, processShoutMessage
    processSayMessage = function(text, ...)
        local result = say(text, ...)
        if Input.settings.enabled == true then pcall(Input.say, text, false) end
        return result
    end
    processShoutMessage = function(text, ...)
        local result = shout(text, ...)
        if Input.settings.enabled == true then pcall(Input.say, text, true) end
        return result
    end
    Input.chatWrapped = true
end

function Input.wrapEmotes()
    if ISEmoteRadialMenu == nil or ISEmoteRadialMenu.alifeTalkWrapped == true or type(ISEmoteRadialMenu.emote) ~= "function" then return end
    local original = ISEmoteRadialMenu.emote
    ISEmoteRadialMenu.emote = function(self, emote, ...)
        pcall(function()
            if emote == "surrender" or emote == "stop" or emote == "wavehi" or emote == "insult" then
                Input.metrics.emotes = Input.metrics.emotes + 1
                Input.deliver("talkEmote", { emote = emote })
            end
        end)
        return original(self, emote, ...)
    end
    ISEmoteRadialMenu.alifeTalkWrapped = true
end

function Input.onZombieDead(zombie)
    if Input.settings.enabled ~= true or zombie == nil then return end
    pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then return end
        local attacker = zombie:getAttackedBy()
        if attacker ~= player then return end
        local now = nowMs()
        if now - Input.lastHelpedAt < Input.settings.helpedIntervalMs then return end
        Input.lastHelpedAt = now
        Input.metrics.helped = Input.metrics.helped + 1
        Input.deliver("talkHelped", { x = zombie:getX(), y = zombie:getY() })
    end)
end

function Input.showTimer(seconds, text)
    seconds = math.max(0, math.min(600, tonumber(seconds) or 0))
    if seconds <= 0 then
        Input.timer = nil
        return false
    end
    local now = nowMs()
    Input.timer = { untilMs = now + seconds * 1000, text = tostring(text or ""), nextAtMs = now }
    Input.watchUntil = math.max(Input.watchUntil, now + seconds * 1000)
    return true
end

function Input.tickTimer(now)
    local timer = Input.timer
    if timer == nil or now < timer.nextAtMs then return false end
    if now >= timer.untilMs then
        Input.timer = nil
        return false
    end
    timer.nextAtMs = now + 5000
    local player = getSpecificPlayer(0)
    if player == nil or HaloTextHelper == nil or type(HaloTextHelper.addText) ~= "function" then return false end
    local text = ProjectALife.Text ~= nil and ProjectALife.Text.ui(timer.text) or timer.text
    HaloTextHelper.addText(player, text .. " (" .. tostring(math.ceil((timer.untilMs - now) / 1000)) .. "s)")
    return true
end

function Input.showNotice(text)
    local player = getSpecificPlayer(0)
    if player == nil or type(text) ~= "string" or text == "" then return false end
    local shown = ProjectALife.Text ~= nil and ProjectALife.Text.ui(text) or text
    if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then HaloTextHelper.addText(player, shown) end
    return true
end

function Input.onServerCommand(module, command, arguments)
    if module == "ProjectALife" and command == "standoffNotice" then
        Input.showNotice(type(arguments) == "table" and tostring(arguments.text or "") or "")
        return
    end
    if module == "ProjectALife" and command == "standoffTimer" then
        Input.showTimer(type(arguments) == "table" and arguments.seconds or 0, type(arguments) == "table" and arguments.text or "")
        return
    end
    if module ~= "ProjectALife" or command ~= "robberyWatch" then return end
    local seconds = type(arguments) == "table" and tonumber(arguments.seconds) or 0
    Input.watchUntil = nowMs() + math.max(0, math.min(120, seconds or 0)) * 1000
end

function Input.armed(player)
    local armed = false
    pcall(function()

        local hands = { player:getPrimaryHandItem(), player:getSecondaryHandItem() }
        for index = 1, 2 do
            local item = hands[index]
            if item ~= nil and instanceof(item, "HandWeapon") and item:getFullType() ~= "Base.BareHands" then armed = true end
        end
    end)
    return armed
end

function Input.aiming(player)
    local aiming = false
    pcall(function() aiming = player:isAiming() == true end)
    return aiming
end

function Input.onTick()
    if Input.keyPressTicks > 0 then
        Input.keyPressTicks = Input.keyPressTicks - 1
        if Input.keyPressTicks == 0 and type(doKeyPress) == "function" then doKeyPress(true) end
    end
    local now = nowMs()
    if Input.timer ~= nil then pcall(Input.tickTimer, now) end
    if not multiplayer() then return end
    if now - Input.lastStateAt < Input.settings.stateIntervalMs then return end
    local player = getSpecificPlayer(0)
    if player == nil then return end
    local armed, aiming = Input.armed(player), Input.aiming(player)

    local watched = now <= Input.watchUntil
    local changed = armed ~= Input.lastArmed or aiming ~= Input.lastAiming
    if not watched and not changed then return end
    Input.lastStateAt = now
    Input.lastArmed, Input.lastAiming = armed, aiming
    Input.metrics.states = Input.metrics.states + 1
    Input.deliver("talkState", { armed = armed, aiming = aiming })
end

function Input.onGameStart()
    Input.wrapChat()
    Input.wrapEmotes()
    local sandbox = SandboxVars and SandboxVars.ALife or nil
    if type(sandbox) == "table" then
        if sandbox.Talk_Enabled ~= nil then Input.settings.enabled = sandbox.Talk_Enabled ~= false end
        if sandbox.Talk_SinglePlayerChat ~= nil then Input.settings.singlePlayerChat = sandbox.Talk_SinglePlayerChat ~= false end
    end
end

if type(Events) == "table" then
    if Events.OnKeyPressed ~= nil then Events.OnKeyPressed.Add(Input.onKeyPressed) end
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(Input.onGameStart) end
    if Events.OnZombieDead ~= nil then Events.OnZombieDead.Add(Input.onZombieDead) end
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(Input.onServerCommand) end
    if Events.OnTick ~= nil then Events.OnTick.Add(Input.onTick) end
end

return Input
