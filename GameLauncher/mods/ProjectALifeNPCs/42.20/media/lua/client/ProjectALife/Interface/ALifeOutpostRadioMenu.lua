require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local Menu = { settings = { reach = 2 }, radios = {}, askedAtMs = 0 }
ProjectALife.OutpostRadioMenu = Menu
local Text = ProjectALife.Text

function Menu.radioSiteOf(worldobjects)
    for _, object in ipairs(type(worldobjects) == "table" and worldobjects or {}) do
        local id
        pcall(function()
            local data = object:getModData()
            id = data and data.ProjectALifeRadioSite or nil
        end)
        if id ~= nil and tostring(id) ~= "" then
            local x, y, z = 0, 0, 0
            pcall(function() x, y, z = object:getX(), object:getY(), object:getZ() end)
            return tostring(id), { x = x, y = y, z = z }
        end
    end
    return nil
end

function Menu.acceptRadios(rows)
    if type(rows) ~= "table" then return false end
    Menu.radios = rows
    return true
end

function Menu.radioNear(rows, px, py, pz, reach)
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if Menu.withinReach(px, py, pz, row.x, row.y, row.z, reach) then
            return tostring(row.site), { x = row.x, y = row.y, z = row.z }
        end
    end
    return nil
end

function Menu.withinReach(px, py, pz, ox, oy, oz, reach)
    if math.floor(tonumber(pz) or 0) ~= math.floor(tonumber(oz) or 0) then return false end
    local dx = (tonumber(px) or 0) - (tonumber(ox) or 0)
    local dy = (tonumber(py) or 0) - (tonumber(oy) or 0)
    local r = tonumber(reach) or 0
    return dx * dx + dy * dy <= r * r
end

local function send(playerNum, command, siteId)
    local player = getSpecificPlayer(playerNum)
    if player == nil or type(sendClientCommand) ~= "function" then return end
    sendClientCommand(player, "ProjectALife", command, { site = siteId })
end

local function fill(playerNum, context, worldobjects, test)
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.rightClickOn) ~= "function" or not prefs.rightClickOn() then return end

    if test == true or type(context) ~= "table" or type(context.addOption) ~= "function"
            or type(context.getNew) ~= "function" or type(context.addSubMenu) ~= "function" then
        return
    end
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    local px, py, pz = 0, 0, 0
    pcall(function() px, py, pz = player:getX(), player:getY(), player:getZ() end)
    local siteId, at = Menu.radioSiteOf(worldobjects)
    if siteId ~= nil and not Menu.withinReach(px, py, pz, at.x, at.y, at.z, Menu.settings.reach) then
        siteId = nil
    end
    if siteId == nil then

        siteId, at = Menu.radioNear(Menu.radios, px, py, pz, Menu.settings.reach + 1)
    end
    if siteId == nil then
        Menu.ask(playerNum)
        return
    end
    local root = context:addOption(Text.ui("[A-LIFE] Outpost radio"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(Text.ui("Disable communications in this outpost"), playerNum, send, "outpostRadioDisable", siteId)
    menu:addOption(Text.ui("Use the radio: call the outpost's faction"), playerNum, send, "outpostRadioUse", siteId)
end

Menu.cutLines = { "I just cut off all communications for that outpost, go to hell.", "Come and get me." }
Menu.secondLineDelayMs = 2600

Menu.friendlyCutLine = "That was their radio. They won't forget who cut it."

local FEEDBACK = {
    comms_disabled = Menu.cutLines[1],
    help_called = "They're sending people. Hold on.",
    bait = "Static... then a voice asking where exactly you are.",
    too_far = "Get closer to the radio.",
    already_disabled = "This radio is already dead.",
    comms_down = "Dead air. Someone already killed this radio.",
    radio_busy = "The channel is busy. Try again later.",
    site_not_active = "Nobody is listening on this frequency.",
    no_site = "Nobody is listening on this frequency.",
    rate_limited = "Slow down.",
}

function Menu.ask(playerNum)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    if now < (Menu.askedAtMs or 0) then return false end
    Menu.askedAtMs = now + 60000
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil or type(sendClientCommand) ~= "function" then return false end
    return pcall(sendClientCommand, player, "ProjectALife", "outpostRadioList", {}) == true
end

local function onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" then return end
    if command == "outpostRadioListResult" then
        if type(arguments) == "table" then Menu.acceptRadios(arguments.radios) end
        return
    end
    if command ~= "outpostRadioDisableResult" and command ~= "outpostRadioUseResult" then return end
    local player = getSpecificPlayer(0)
    if player == nil then return end
    local reason = type(arguments) == "table" and tostring(arguments.reason or "") or ""

    local text, vars = FEEDBACK[reason], nil
    if text == nil then
        if type(arguments) == "table" and arguments.ok == true then text = "Done."
        else text, vars = "Nothing happens ({reason}).", { reason = reason } end
    end

    if reason == "comms_disabled" and type(arguments) == "table" and arguments.wasFriendly == true then
        text = Menu.friendlyCutLine
    end
    local shown = Text.ui(text, vars)
    pcall(function() player:Say(shown) end)
    if reason == "comms_disabled" and not (type(arguments) == "table" and arguments.wasFriendly == true) then
        local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
        Menu.pendingLine = { text = Menu.cutLines[2], atMs = now + Menu.secondLineDelayMs }
    end
end

Menu.receive = onServerCommand

function Menu.tick(now)
    local line = Menu.pendingLine
    if line == nil then return false end
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs() or 0)
    if now < line.atMs then return false end
    Menu.pendingLine = nil
    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    local shown = Text.ui(line.text)
    if player ~= nil then pcall(function() player:Say(shown) end) end
    return true
end
if type(Events) == "table" and Events.OnTick ~= nil then Events.OnTick.Add(function() Menu.tick() end) end

if type(Events) == "table" and Events.OnPreFillWorldObjectContextMenu ~= nil then
    Events.OnPreFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(fill))
end
if type(Events) == "table" and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(onServerCommand)
end

if type(Events) == "table" then
    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(function() Menu.ask(0) end) end
    if Events.OnConnected ~= nil then Events.OnConnected.Add(function() Menu.ask(0) end) end
end

return Menu
