ProjectALife = ProjectALife or {}
require "ProjectALife/Core/ALifeText"

local Compass = {}
Compass.state = {
    visible = false,
    entries = {},
    lastRequestMs = 0,
    playerNum = 0,

    flash = nil,
    retryStamp = nil,
    settings = {
        refreshMs = 4000,
        retryMs = 1500,
        flashMs = 6000,
        margin = 54,
        arrow = 15,

        cameraTurn = math.pi / 4,
        viewFlatten = 0.5,
    },
}
ProjectALife.EncounterCompass = Compass

local COLORS = {
    blockade = { r = 0.95, g = 0.55, b = 0.22 },
    garrison = { r = 0.42, g = 0.70, b = 0.98 },
    occupy_high = { r = 0.72, g = 0.45, b = 0.95 },
    defend = { r = 0.35, g = 0.85, b = 0.55 },
    route = { r = 0.95, g = 0.85, b = 0.35 },
    repair = { r = 0.90, g = 0.40, b = 0.55 },
    default = { r = 0.86, g = 0.32, b = 0.42 },
}

local texture

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function colorFor(entry)
    return COLORS[tostring(entry.stance or "")] or COLORS.default
end

function Compass.apply(payload)
    if type(payload) ~= "table" then return false end

    if payload.ok == false then
        Compass.refused(payload)
        return false
    end
    Compass.state.entries = type(payload.encounters) == "table" and payload.encounters or {}
    return true
end

function Compass.refused(payload)
    local state = Compass.state
    local prefs = ProjectALife.MenuPrefs

    if prefs ~= nil and type(prefs.allowed) == "function"
            and not prefs.allowed(getSpecificPlayer(state.playerNum or 0)) then
        state.visible, state.entries, state.flash = false, {}, nil
        return true
    end
    if payload.reason == "rate_limited" then return false end
    local Text = ProjectALife.Text
    local text = Text.ui("A-Life: arrows refused - {reason}", { reason = tostring(payload.reason or "unknown") })
    if payload.reason == "diagnostics_disabled" and prefs ~= nil
            and type(prefs.diagnosticsRefused) == "function" then
        local stamp = prefs.diagnosticsRefused(getSpecificPlayer(state.playerNum or 0), nowMs())
        text = Text.ui(prefs.disabledText)
        if stamp ~= nil then
            text = Text.ui(prefs.retryText)
            if stamp ~= state.retryStamp then
                state.retryStamp = stamp
                state.lastRequestMs = nowMs() - state.settings.refreshMs + state.settings.retryMs
            end
        end
    end
    state.flash = { text = tostring(text), untilMs = nowMs() + state.settings.flashMs }
    return true
end

function Compass.hide()
    local state = Compass.state
    state.visible, state.entries, state.flash, state.retryStamp = false, {}, nil, nil
    return true
end

function Compass.toggle(playerNum)
    Compass.state.visible = not Compass.state.visible
    Compass.state.playerNum = playerNum or 0
    local player = getSpecificPlayer(playerNum or 0)
    if player ~= nil then
        player:Say(Compass.state.visible and ProjectALife.Text.ui("A-Life: encounter arrows ON")
            or ProjectALife.Text.ui("A-Life: encounter arrows OFF"))
    end
    if Compass.state.visible then
        Compass.request(playerNum or 0)
    else
        Compass.state.entries = {}
    end
    return Compass.state.visible
end

function Compass.request(playerNum)
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil or type(sendClientCommand) ~= "function" then return false end
    Compass.state.lastRequestMs = nowMs()
    sendClientCommand(player, "ProjectALife", "debugEncounterMarks", {})
    return true
end

function Compass.placement(screenW, screenH, dx, dy)
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return nil end
    local view = Compass.state.settings
    local turnCos, turnSin = math.cos(view.cameraTurn), math.sin(view.cameraTurn)
    local sx = (dx * turnCos - dy * turnSin) / length
    local sy = (dx * turnSin + dy * turnCos) / length * view.viewFlatten
    local screenLength = math.sqrt(sx * sx + sy * sy)
    if screenLength < 0.001 then return nil end
    sx, sy = sx / screenLength, sy / screenLength
    local halfW, halfH = screenW * 0.5, screenH * 0.5
    local radius = math.min(halfW, halfH) - Compass.state.settings.margin
    return halfW + sx * radius, halfH + sy * radius, sx, sy
end

local function drawArrow(renderer, text, screenW, screenH, dx, dy, distance, label, color)
    local cx, cy, sx, sy = Compass.placement(screenW, screenH, dx, dy)
    if cx == nil then return end
    local size = Compass.state.settings.arrow
    local px, py = -sy, sx
    local tipX, tipY = cx + sx * size, cy + sy * size
    local leftX, leftY = cx - sx * size * 0.4 + px * size * 0.6,
        cy - sy * size * 0.4 + py * size * 0.6
    local rightX, rightY = cx - sx * size * 0.4 - px * size * 0.6,
        cy - sy * size * 0.4 - py * size * 0.6
    renderer:renderline(texture, tipX, tipY, leftX, leftY, color.r, color.g, color.b, 0.95)
    renderer:renderline(texture, tipX, tipY, rightX, rightY, color.r, color.g, color.b, 0.95)
    renderer:renderline(texture, leftX, leftY, rightX, rightY, color.r, color.g, color.b, 0.75)
    local caption = label .. "  " .. tostring(math.floor(distance)) .. "m"
    text:DrawString(UIFont.Small, cx - sx * size * 3 - 30, cy - sy * size * 3 - 6,
        caption, color.r, color.g, color.b, 0.95)
end

function Compass.draw()
    local state = Compass.state
    if not state.visible then return end
    local player = getSpecificPlayer(state.playerNum or 0)
    if player == nil then return end
    if nowMs() - state.lastRequestMs > state.settings.refreshMs then
        Compass.request(state.playerNum or 0)
    end
    local flash = state.flash
    if flash ~= nil and nowMs() < flash.untilMs then
        local screen = getTextManager()
        if screen ~= nil then
            screen:DrawStringCentre(UIFont.Small, getCore():getScreenWidth() * 0.5, 80,
                flash.text, 0.95, 0.75, 0.35, 0.95)
        end
    end
    if #state.entries == 0 then return end

    texture = texture or getTexture("media/textures/ProjectALifeLine.png")
    if texture == nil then return end
    local renderer, text = getRenderer(), getTextManager()
    if renderer == nil or text == nil then return end
    local px, py = player:getX(), player:getY()
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    for _, entry in ipairs(state.entries) do
        local dx, dy = (tonumber(entry.x) or 0) - px, (tonumber(entry.y) or 0) - py
        local distance = math.sqrt(dx * dx + dy * dy)
        drawArrow(renderer, text, screenW, screenH, dx, dy, distance,
            tostring(entry.label or entry.id or "?"), colorFor(entry))
    end
end

if type(Events) == "table" and Events.OnPreUIDraw ~= nil then
    Events.OnPreUIDraw.Add(Compass.draw)
end

return Compass
