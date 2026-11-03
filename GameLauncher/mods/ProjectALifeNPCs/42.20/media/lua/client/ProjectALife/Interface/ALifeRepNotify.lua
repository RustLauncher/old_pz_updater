require "ISUI/ISPanel"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Records/ALifeRepLevels"
require "ProjectALife/Records/ALifeRepIcons"
require "ProjectALife/Audio/ALifeInteractionCues"

ProjectALife = ProjectALife or {}

local Levels = ProjectALife.RepLevels
local Icons = ProjectALife.RepIcons
local Notify = {
    quietMs = 600,
    maxMs = 1500,
    bannerMs = 6500,
    fadeInMs = 250,
    fadeOutMs = 900,
    logLimit = 24,
    soundGapMs = 4000,
    soundAt = nil,
    soundUp = nil,
    soundHandle = nil,
    baselineAt = nil,
    pending = nil,
    lastLevel = nil,
    banner = nil,
    state = nil,
    recent = {},
    metrics = { pushed = 0, shown = 0, banners = 0, suppressed = 0, sounded = 0, soundHeld = 0 },
}
ProjectALife.RepNotify = Notify

function Notify.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Notify.enabled()
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.repNotifyOn) == "function" then return prefs.repNotifyOn() == true end
    return true
end

function Notify.log(line)
    Notify.recent[#Notify.recent + 1] = line
    while #Notify.recent > Notify.logLimit do table.remove(Notify.recent, 1) end
    print("[ALIFE-REP] " .. line)
end

function Notify.reset()
    Notify.pending = nil
    Notify.lastLevel = nil
    Notify.state = nil
    Notify.soundAt, Notify.soundUp, Notify.soundHandle = nil, nil, nil
    if Notify.banner ~= nil and type(Notify.banner.setVisible) == "function" then Notify.banner:setVisible(false) end
end

function Notify.cue(up)
    if not Notify.enabled() then return false end
    local cues = ProjectALife.InteractionCues
    if cues == nil or type(cues.playUI) ~= "function" then return false end
    local now = Notify.nowMs()
    local at = Notify.soundAt
    if at ~= nil and now >= at and now - at < Notify.soundGapMs then
        if up == true or Notify.soundUp ~= true then
            Notify.metrics.soundHeld = Notify.metrics.soundHeld + 1
            return false
        end
        if Notify.soundHandle ~= nil and type(cues.stopUI) == "function" then cues.stopUI(Notify.soundHandle) end
    end
    local id = "PALRepDown"
    if up == true then id = "PALRepUp" end
    local ok, handle = cues.playUI(id)
    if ok ~= true then return false end
    Notify.soundAt, Notify.soundUp, Notify.soundHandle = now, up == true, handle
    Notify.metrics.sounded = Notify.metrics.sounded + 1
    return true
end

function Notify.store(payload)
    local store = ProjectALife.StatusStore
    if store == nil or Levels.indexOf(payload.level) == nil then return false end
    local copy = {}
    if type(store.reputation) == "table" then
        for key, value in pairs(store.reputation) do copy[key] = value end
    else
        copy.schema, copy.lastKnown, copy.relations = 1, true, {}
    end
    local personal = {}
    if type(copy.personal) == "table" then
        for key, value in pairs(copy.personal) do personal[key] = value end
    end
    personal.level = payload.level
    personal.band = Levels.band(payload.level)
    if payload.score ~= nil then personal.score = payload.score end
    if payload.reachedMin ~= nil then personal.reachedMin = payload.reachedMin end
    if payload.reachedMax ~= nil then personal.reachedMax = payload.reachedMax end
    if payload.humans ~= nil then copy.humans = payload.humans end
    copy.personal = personal
    store.reputation = copy
    return true
end

function Notify.observe(personal, from)
    if type(personal) ~= "table" or Levels.indexOf(personal.level) == nil then return false end
    local previous = Notify.lastLevel
    if previous == nil and Levels.indexOf(from) ~= nil then previous = from end
    Notify.lastLevel = personal.level
    if previous == nil or previous == personal.level then return false end
    local line = "level " .. tostring(Levels.name(previous)) .. " -> " .. tostring(Levels.name(personal.level))
    if tonumber(personal.score) ~= nil then
        line = line .. " score " .. tostring(personal.score) .. " (" .. Icons.signed(personal.score) .. ")"
    end
    Notify.log(line)
    if not Notify.enabled() then
        Notify.metrics.suppressed = Notify.metrics.suppressed + 1
        return true
    end
    Notify.showBanner(personal, previous)
    Notify.cue(Levels.indexOf(personal.level) > (Levels.indexOf(previous) or 0))
    return true
end

function Notify.requestBaseline()
    local store = ProjectALife.StatusStore
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if store == nil or type(store.request) ~= "function" or player == nil then return false end
    return pcall(store.request, player)
end

function Notify.baselineTick(now)
    if Notify.baselineAt == nil or now < Notify.baselineAt then return end
    Notify.baselineAt = nil
    if Notify.lastLevel == nil then Notify.requestBaseline() end
end

function Notify.onGameStart()
    Notify.reset()
    Notify.baselineAt = Notify.nowMs() + 3000
end

function Notify.push(delta, cause, player)
    local amount = tonumber(delta)
    if amount == nil or amount == 0 then return false end
    local now = Notify.nowMs()
    local pending = Notify.pending
    if pending == nil then
        pending = { first = now, last = now, delta = 0, causes = {}, order = {} }
        Notify.pending = pending
    end
    pending.last = now
    pending.delta = pending.delta + amount
    if player ~= nil then pending.player = player end
    local key = tostring(cause or "")
    if pending.causes[key] == nil then
        pending.causes[key] = 0
        pending.order[#pending.order + 1] = key
    end
    pending.causes[key] = pending.causes[key] + math.abs(amount)
    Notify.metrics.pushed = Notify.metrics.pushed + 1
    return true
end

function Notify.due(now)
    local pending = Notify.pending
    if pending == nil then return false end
    return now - pending.last >= Notify.quietMs or now - pending.first >= Notify.maxMs
end

function Notify.mainCause(pending)
    local best, bestWeight = "", -1
    for _, key in ipairs(pending.order) do
        if pending.causes[key] > bestWeight then best, bestWeight = key, pending.causes[key] end
    end
    return best
end

function Notify.colorGetter(helper, up)
    local getter
    if up then getter = helper.getGoodColor else getter = helper.getBadColor end
    if type(getter) ~= "function" then
        if up then getter = helper.getColorGreen else getter = helper.getColorRed end
    end
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    if ok then return value end
    return nil
end

function Notify.halo(player, text, up)
    if player == nil or type(text) ~= "string" then return false end
    local helper = HaloTextHelper
    if helper ~= nil then
        local color = Notify.colorGetter(helper, up)
        if color ~= nil and type(helper.addTextWithArrow) == "function" then
            if pcall(helper.addTextWithArrow, player, text, "[br/]", up == true, color) then return true end
        end
        local themed
        if up then themed = helper.addGoodText else themed = helper.addBadText end
        if type(themed) == "function" and pcall(themed, player, text) then return true end
        if color ~= nil and type(helper.addText) == "function" then
            if pcall(helper.addText, player, text, "[br/]", color) then return true end
        end
        if type(helper.addText) == "function" and pcall(helper.addText, player, text) then return true end
    end
    if type(player.setHaloNote) == "function" then
        if up then return pcall(player.setHaloNote, player, text, 120, 230, 120, 200) end
        return pcall(player.setHaloNote, player, text, 235, 70, 60, 200)
    end
    return false
end

function Notify.flush(player)
    local pending = Notify.pending
    Notify.pending = nil
    if pending == nil or pending.delta == 0 then return false end
    local target = player or pending.player
    if target == nil and type(getSpecificPlayer) == "function" then target = getSpecificPlayer(0) end
    local cause = Notify.mainCause(pending)
    local text = ProjectALife.Text.ui("{amount} Reputation", { amount = Icons.deltaText(pending.delta) })
    local reason = Icons.reasonOf(cause)
    if reason ~= nil then text = text .. " (" .. reason .. ")" end
    Notify.log("change " .. Icons.deltaText(pending.delta) .. " " .. cause)
    if not Notify.enabled() then
        Notify.metrics.suppressed = Notify.metrics.suppressed + 1
        return false
    end
    Notify.metrics.shown = Notify.metrics.shown + 1
    return Notify.halo(target, text, pending.delta > 0)
end

function Notify.tick()
    local now = Notify.nowMs()
    if Notify.baselineAt ~= nil then Notify.baselineTick(now) end
    if Notify.pending == nil then return end
    if Notify.due(now) then Notify.flush() end
end

function Notify.receive(payload, player)
    if type(payload) ~= "table" then return false end
    Notify.store(payload)
    Notify.observe(payload, payload.from)
    local delta = tonumber(payload.delta)
    if delta ~= nil then return Notify.push(delta, payload.cause, player) end
    if not Notify.enabled() then return false end
    local text
    if payload.gain == true then text = ProjectALife.Text.ui("Reputation up") else text = ProjectALife.Text.ui("Reputation down") end
    local reason = Icons.reasonOf(payload.cause)
    if reason ~= nil then text = text .. " (" .. reason .. ")" end
    return Notify.halo(player, text, payload.gain == true)
end

function Notify.bannerClass()
    if Notify.Banner ~= nil then return Notify.Banner end
    if type(ISPanel) ~= "table" or type(ISPanel.derive) ~= "function" then return nil end
    local Banner = ISPanel:derive("ALifeRepBanner")
    function Banner:render()
        Notify.drawBanner(self)
    end
    Notify.Banner = Banner
    return Banner
end

function Notify.subline(info)
    local old = Levels.name(info.previous)
    if tonumber(info.score) ~= nil then
        return ProjectALife.Text.ui("Reputation {score} (was {old})", { score = Icons.signed(info.score), old = old })
    end
    return ProjectALife.Text.ui("Was {old}", { old = old })
end

function Notify.bannerSize(info)
    local manager = getTextManager()
    info.title = ProjectALife.Text.ui("You are now known as {name}", { name = Levels.name(info.level) })
    info.sub = Notify.subline(info)
    local text = math.max(manager:MeasureStringX(UIFont.Medium, info.title), manager:MeasureStringX(UIFont.Small, info.sub))
    return math.max(300, 70 + text + 24), 64
end

function Notify.showBanner(personal, previous)
    local class = Notify.bannerClass()
    if class == nil or type(getCore) ~= "function" or type(getTextManager) ~= "function" then return false end
    local info = { level = personal.level, previous = previous, score = personal.score, startMs = Notify.nowMs() }
    local width, height = Notify.bannerSize(info)
    local x = math.floor((getCore():getScreenWidth() - width) / 2)
    local y = 110
    local banner = Notify.banner
    if banner == nil then
        banner = class:new(x, y, width, height)
        ProjectALife.TalkUi.passThrough(banner)
        banner:initialise()
        if type(banner.noBackground) == "function" then banner:noBackground() end
        banner:addToUIManager()
        if type(banner.setAlwaysOnTop) == "function" then banner:setAlwaysOnTop(true) end
        Notify.banner = banner
    else
        banner:setX(x)
        banner:setY(y)
        banner:setWidth(width)
        banner:setHeight(height)
    end
    Notify.state = info
    banner:setVisible(true)
    Notify.metrics.banners = Notify.metrics.banners + 1
    return true
end

function Notify.bannerAlpha(info, now)
    local age = now - info.startMs
    if age < 0 then return 0 end
    if age >= Notify.bannerMs then return nil end
    if age < Notify.fadeInMs then return age / Notify.fadeInMs end
    local left = Notify.bannerMs - age
    if left < Notify.fadeOutMs then return left / Notify.fadeOutMs end
    return 1
end

function Notify.drawBanner(panel)
    local info = Notify.state
    if info == nil then
        panel:setVisible(false)
        return
    end
    local alpha = Notify.bannerAlpha(info, Notify.nowMs())
    if alpha == nil then
        Notify.state = nil
        panel:setVisible(false)
        return
    end
    local width, height = panel:getWidth(), panel:getHeight()
    local tone = Icons.color(Levels.indexOf(info.level) or 1, alpha, 0.25)
    panel:drawRect(0, 0, width, height, 0.86 * alpha, 0.02, 0.025, 0.03)
    panel:drawRectBorder(0, 0, width, height, 0.9 * alpha, tone.r, tone.g, tone.b)
    panel:drawRect(0, 0, 5, height, alpha, tone.r, tone.g, tone.b)
    local texture = Icons.texture(info.level)
    if texture ~= nil then
        panel:drawTextureScaled(texture, 22, math.floor((height - 32) / 2), 32, 32, alpha, 1, 1, 1)
    end
    panel:drawText(info.title, 70, 10, tone.r, tone.g, tone.b, alpha, UIFont.Medium)
    panel:drawText(info.sub, 70, 10 + getTextManager():getFontHeight(UIFont.Medium) + 2, 0.78, 0.8, 0.78, alpha, UIFont.Small)
end

if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(Notify.tick)
end
if type(Events) == "table" and Events.OnPlayerDeath ~= nil and type(Events.OnPlayerDeath.Add) == "function" then
    Events.OnPlayerDeath.Add(Notify.reset)
end
if type(Events) == "table" and Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Notify.onGameStart)
end

return Notify
