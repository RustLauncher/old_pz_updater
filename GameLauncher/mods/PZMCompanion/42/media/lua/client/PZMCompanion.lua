local SITE = "https://projectzomboidmap.com/"

local ZOOM = 200
local MIN_FLOOR, MAX_FLOOR = -17, 29

local WRITE_MS = 250

local function log(msg)
    print("[PZMCompanion] " .. msg)
end

local optKey, optLive, optOpen

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create("pzmcompanion", "Map Companion")
    options:addDescription(
        "Pairs with projectzomboidmap.com. Press the map key to open the web map"
        .. " centered on your character. The live file lets the site follow your"
        .. " position in real time. Everything stays on your computer.")
    optKey = options:addKeyBind("open_map", "Open web map",
        Keyboard.KEY_HOME, "Hold Shift to copy the map link instead")
    optOpen = options:addComboBox("open_with", "Open the map with",
        "Auto tries the Steam overlay first, then the system browser")
    optOpen:addItem("Auto", true)
    optOpen:addItem("Steam overlay", false)
    optOpen:addItem("System browser", false)
    optOpen:addItem("Copy link", false)
    optLive = options:addTickBox("live_file", "Write live position file", true,
        "Updates Zomboid/Lua/pzm_live/live.txt about once per second")
end

local function readOption(opt, fallback)
    if not opt then return fallback end
    if opt.getValue then
        local ok, v = pcall(function() return opt:getValue() end)
        if ok and v ~= nil then return v end
    end
    if opt.value ~= nil then return opt.value end
    if opt.key ~= nil then return opt.key end
    return fallback
end

local function mapKey()
    return readOption(optKey, Keyboard.KEY_HOME)
end

local function liveEnabled()
    return readOption(optLive, true) == true
end

local function openMode()
    local v = readOption(optOpen, 1)
    return type(v) == "number" and v or 1
end

local function mapPath(p)
    local floor = math.floor(p:getZ() + 0.5)
    if floor < MIN_FLOOR then floor = MIN_FLOOR end
    if floor > MAX_FLOOR then floor = MAX_FLOOR end
    local s = string.format("%dx%dx%d",
        math.floor(p:getX()), math.floor(p:getY()), ZOOM)
    if floor ~= 0 then s = s .. "x" .. floor end
    return s
end

local function mapUrl(p)
    return SITE .. "#" .. mapPath(p)
end

local function urlEncode(s)
    return (tostring(s):gsub("[^%w%-_.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function mapOpenUrl(p)
    local direct = SITE .. "?" .. mapPath(p)
    if isIndieStoneUrl then
        local ok, allowed = pcall(isIndieStoneUrl, direct)
        if ok and allowed then return direct end
    end
    return "https://steamcommunity.com/linkfilter/?u=" .. urlEncode(direct)
end

local function halo(p, text)
    if not HaloTextHelper then return end
    pcall(function()
        if HaloTextHelper.addGoodText then
            HaloTextHelper.addGoodText(p, text)
        elseif HaloTextHelper.addText then
            HaloTextHelper.addText(p, text)
        end
    end)
end

local openBrowser = openUrl or openURl

local function tryOverlay(p, url)
    if not (getSteamModeActive() and isSteamOverlayEnabled()) then
        log("steam overlay not available (steam mode "
            .. tostring(getSteamModeActive()) .. ", overlay enabled "
            .. tostring(isSteamOverlayEnabled()) .. ")")
        return false
    end
    local ok = pcall(activateSteamOverlayToWebPage, url)
    if ok then

        log("opened via Steam overlay: " .. url)
        log("if no overlay appeared, set Open the map with to System browser in Options > Mods")
        halo(p, "Opening map in Steam overlay")
    else
        log("steam overlay call failed")
    end
    return ok
end

local function tryBrowser(p, url)
    if not openBrowser then
        log("no system browser opener exposed")
        return false
    end
    local ok = pcall(openBrowser, url)
    if ok then
        log("opened via system browser: " .. url)
        halo(p, "Map opened in browser")
    else
        log("system browser call failed")
    end
    return ok
end

local function tryClipboard(p, url)
    if not (Clipboard and Clipboard.setClipboard) then
        log("clipboard not exposed")
        return false
    end
    local ok = pcall(function() Clipboard.setClipboard(url) end)
    if ok then
        log("copied link: " .. url)
        halo(p, "Map link copied")
    else
        log("clipboard call failed")
    end
    return ok
end

local function openMap(p)
    local mode = openMode()
    local target = mapOpenUrl(p)
    if mode == 2 then
        if tryOverlay(p, target) then return end
    elseif mode == 3 then
        if tryBrowser(p, target) then return end
    elseif mode == 4 then
        if tryClipboard(p, mapUrl(p)) then return end
        return
    else
        if tryOverlay(p, target) then return end
    end

    if tryBrowser(p, target) then return end
    if tryClipboard(p, mapUrl(p)) then return end
    log("could not open or copy the map link")
end

local unmatchedLogs = 0
local lastFire = 0

local function handleKey(key, source)

    if ISChat and ISChat.focused then return end
    local bound = mapKey()
    if key ~= bound then
        if unmatchedLogs < 3 then
            unmatchedLogs = unmatchedLogs + 1
            log(source .. ": key " .. tostring(key)
                .. " pressed (map key is " .. tostring(bound) .. ")")
        end
        return
    end
    local now = getTimestampMs()
    if now - lastFire < 400 then return end
    lastFire = now
    local p = getPlayer()
    if not p then
        log(source .. ": map key pressed but no player yet")
        return
    end
    log(source .. ": map key pressed, mode " .. tostring(openMode()))
    if isShiftKeyDown and isShiftKeyDown() then
        if not tryClipboard(p, mapUrl(p)) then openMap(p) end
        return
    end
    openMap(p)
end

if Events.OnKeyStartPressed then
    Events.OnKeyStartPressed.Add(function(key) handleKey(key, "OnKeyStartPressed") end)
else
    Events.OnKeyPressed.Add(function(key) handleKey(key, "OnKeyPressed") end)
end

log("loaded: v1.5, map key " .. tostring(mapKey())
    .. ", browser opener " .. tostring(openBrowser ~= nil)
    .. ", OnKeyStartPressed " .. tostring(Events.OnKeyStartPressed ~= nil))

if isClient and isClient() then
    local okName, serverName = pcall(function() return getServerName() end)
    if not (okName and serverName) then serverName = "unknown server" end
    log("multiplayer client: " .. tostring(serverName))
end

local session = ""
local last = 0
local wroteDeath = false

local function esc(s)
    s = tostring(s):gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("[\1-\31\127]", " ")
    return s
end

local OTHERS_TTL_MS = 10000
local OTHERS_MAX = 64
local others, othersAt = nil, 0
local othersTtl = OTHERS_TTL_MS
local loggedOthers = false

local function ttlFor(everyMs)
    local every = tonumber(everyMs) or 1000
    return math.max(OTHERS_TTL_MS, 2 * every + 2000)
end

local function localUsername()
    local ok, u = pcall(function()
        local p = getPlayer()
        if p then return p:getUsername() end
        return nil
    end)
    if ok and u ~= nil then return tostring(u) end
    return nil
end

local function copyEntry(v)
    if type(v) ~= "table" then return nil end
    local x, y = tonumber(v.x), tonumber(v.y)
    if not x or not y then return nil end
    local name = v.name
    if name == nil or name == "" then name = v.user end
    if name == nil then name = "Survivor" end
    local e = {
        name = tostring(name),
        user = tostring(v.user or ""),
        x = x,
        y = y,
        z = math.floor((tonumber(v.z) or 0) + 0.5),
        dead = v.dead == true,
    }
    local fx, fy = tonumber(v.fx), tonumber(v.fy)
    if fx and fy then
        e.fx = fx
        e.fy = fy
    end
    return e
end

local function byName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.user < b.user
end

local function onPositions(module, command, args)
    if module ~= "PZMCompanion" or command ~= "positions" then return end
    if type(args) ~= "table" or type(args.list) ~= "table" then return end
    local me = localUsername()
    local list = {}
    for _, v in pairs(args.list) do
        local e = copyEntry(v)
        if e and not (me and e.user == me) then
            list[#list + 1] = e
        end
    end
    table.sort(list, byName)
    if #list > OTHERS_MAX then
        local capped = {}
        for i = 1, OTHERS_MAX do capped[i] = list[i] end
        list = capped
    end
    others = list
    othersAt = getTimestampMs()
    othersTtl = ttlFor(args.every)
    if not loggedOthers then
        loggedOthers = true
        log("receiving " .. #list .. " other player positions")
    end
end

if Events.OnServerCommand then
    Events.OnServerCommand.Add(onPositions)
end

local function othersPart(now)
    if not others then return "" end
    if now - othersAt >= othersTtl then

        others = nil
        return ""
    end
    if #others == 0 then return "" end
    local parts = {}
    for i = 1, #others do
        local o = others[i]
        local dirPart = ""
        if o.fx and o.fy then
            dirPart = string.format(',"fx":%.2f,"fy":%.2f', o.fx, o.fy)
        end
        parts[i] = string.format('{"name":"%s","x":%.1f,"y":%.1f,"z":%d%s%s}',
            esc(o.name), o.x, o.y, o.z, dirPart, o.dead and ',"dead":true' or "")
    end
    return ',"others":[' .. table.concat(parts, ",") .. "]"
end

Events.OnGameStart.Add(function()
    session = string.format("%d-%d", getTimestampMs(), math.floor(ZombRand(1000000)))
    last = 0
    wroteDeath = false
    log("game start, live session " .. session)
end)

local function writeTick()
    local now = getTimestampMs()
    if now - last < WRITE_MS then return end
    last = now
    if isGamePaused and isGamePaused() then return end
    if not liveEnabled() then return end
    local p = getSpecificPlayer(0)
    if not p then return end
    if p:isDead() then

        if wroteDeath then return end
        wroteDeath = true
    else
        wroteDeath = false
    end
    local w = getFileWriter("pzm_live/live.txt", true, false)
    if not w then return end
    local name = "Survivor"
    local desc = p.getDescriptor and p:getDescriptor()
    if desc and desc.getForename then name = desc:getForename() end

    local dirPart = ""
    local okFwd, fwd = pcall(function() return p:getForwardDirection() end)
    if okFwd and fwd then
        local okXY, fx, fy = pcall(function() return fwd:getX(), fwd:getY() end)
        if okXY and fx and fy then
            dirPart = string.format(',"fx":%.2f,"fy":%.2f', fx, fy)
        end
    end

    w:write(string.format(
        '{"v":1,"session":"%s","t":%d,"name":"%s","x":%.1f,"y":%.1f,"z":%d%s%s%s}',
        session, now, esc(name), p:getX(), p:getY(),
        math.floor(p:getZ() + 0.5), dirPart, p:isDead() and ',"dead":true' or "",
        othersPart(now)))
    w:close()
end

Events.OnTick.Add(writeTick)
