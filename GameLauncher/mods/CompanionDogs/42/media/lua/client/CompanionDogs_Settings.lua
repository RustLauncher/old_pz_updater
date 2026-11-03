CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs
CD.Settings = CD.Settings or {}

CD.Settings.FILE = "CompanionDogs_settings.ini"

CD.Settings.ACTIONS = {
    { id = "cd_come",    label = "IGUI_PD_CmdCome",    cmd = "come",        gesture = "comehere" },
    { id = "cd_follow",  label = "IGUI_PD_CmdFollow",  cmd = "setstate",    gesture = "followme", args = { state = CD.STATE_FOLLOW } },
    { id = "cd_stay",    label = "IGUI_PD_CmdStay",    cmd = "setstate",    gesture = "stop",     args = { state = CD.STATE_STAY } },
    { id = "cd_guard",   label = "IGUI_PD_CmdGuard",   cmd = "setstate",    gesture = "stop",     args = { state = CD.STATE_GUARD } },
    { id = "cd_bring",   label = "IGUI_PD_CmdFetch",   cmd = "teleport",    gesture = "comehere", callout = true },
    { id = "cd_attack",  label = "IGUI_PD_CmdAttack",  cmd = "attack",      gesture = "signalfire" },
    { id = "cd_alert",   label = "IGUI_PD_AlertOn",    cmd = "setalertmode", args = { mode = "full" } },
    { id = "cd_quiet",   label = "IGUI_PD_AlertQuiet", cmd = "setalertmode", args = { mode = "quiet" } },
    { id = "cd_silent",  label = "IGUI_PD_AlertSilent",cmd = "setalertmode", args = { mode = "silent" } },
    { id = "cd_protect", label = "IGUI_PD_AutoProtect",special = "protect" },
    { id = "cd_hunt",    label = "IGUI_PD_HuntMode",   special = "hunt" },
    { id = "cd_status",  label = "IGUI_PD_Inspect",    special = "status" },
    { id = "cd_pet",     label = "IGUI_PD_Pet",        special = "pet" },
    { id = "cd_tk_goto",     label = "IGUI_PD_TrickGoto",     trick = "goto" },
    { id = "cd_tk_distract", label = "IGUI_PD_TrickDistract", trick = "distract" },
}

CD.Settings.ACTION_BY_ID = {}
for _, spec in ipairs(CD.Settings.ACTIONS) do CD.Settings.ACTION_BY_ID[spec.id] = spec end

CD.Settings.DEFAULTS = { volume = 1.0, mute = false, showTexts = true, showMoodles = true, showNames = true, keys = {} }
for _, spec in ipairs(CD.Settings.ACTIONS) do CD.Settings.DEFAULTS.keys[spec.id] = 0 end

local function freshData()
    local D = CD.Settings.DEFAULTS
    local d = { volume = D.volume, mute = D.mute, showTexts = D.showTexts, showMoodles = D.showMoodles,
                showNames = D.showNames, keys = {}, windows = {}, catVol = {}, catMute = {} }
    for k, v in pairs(D.keys) do d.keys[k] = v end
    for _, c in ipairs(CD.SOUND_CATEGORIES) do
        d.catVol[c] = 1.0
        d.catMute[c] = false
    end
    return d
end

CD.Settings.data = CD.Settings.data or freshData()

---@param cat string one of CD.SOUND_CATEGORIES
---@return number volume 0..1
---@nodiscard
function CD.Settings.getCatVolume(cat)
    local d = CD.Settings.data
    local v = d and d.catVol and d.catVol[cat]
    return type(v) == "number" and v or 1.0
end

---@param cat string one of CD.SOUND_CATEGORIES
---@return boolean
---@nodiscard
function CD.Settings.isCatMuted(cat)
    local d = CD.Settings.data
    return d and d.catMute and d.catMute[cat] == true or false
end

---Master volume times the category volume; sounds outside the FMOD bank also take the game sound volume.
---@param soundName string|nil
---@return number factor 0..1, 0 when muted
---@nodiscard
function CD.Settings.getVolumeFactor(soundName)
    local d = CD.Settings.data
    if not d then return 1.0 end
    if d.mute then return 0 end
    local f = d.volume or 1.0
    local cat = soundName and CD.SOUND_CATEGORY and CD.SOUND_CATEGORY[soundName]
    if cat then
        if CD.Settings.isCatMuted(cat) then return 0 end
        f = f * CD.Settings.getCatVolume(cat)
    end
    if soundName and CD.SOUND_NONBANK and CD.SOUND_NONBANK[soundName] then
        local game = math.max(0, math.min(10, getCore():getOptionSoundVolume())) / 10
        f = f * game
    end
    return f
end

---@return boolean
---@nodiscard
function CD.Settings.isMuted() return CD.Settings.data and CD.Settings.data.mute == true end
---@return boolean
---@nodiscard
function CD.Settings.getShowTexts() return not (CD.Settings.data and CD.Settings.data.showTexts == false) end
---@return boolean
---@nodiscard
function CD.Settings.getShowMoodles() return not (CD.Settings.data and CD.Settings.data.showMoodles == false) end
---@return boolean
---@nodiscard
function CD.Settings.getShowNames() return not (CD.Settings.data and CD.Settings.data.showNames == false) end
---@param id string action id from CD.Settings.ACTIONS
---@return integer code 0 when unbound
---@nodiscard
function CD.Settings.getKey(id) return (CD.Settings.data and CD.Settings.data.keys[id]) or 0 end

---Display name of a key code: the unbound label for 0, the engine key name when known, else #code.
---@param code number|nil
---@return string
---@nodiscard
function CD.Settings.keyName(code)
    code = math.floor(tonumber(code) or 0)
    if code == 0 then return getText("IGUI_PD_KeyUnbound") end
    if (code > 0 and code < 256) or code >= 10000 then
        local name = getKeyName(code)
        if name and name ~= "" then return name end
    end
    return "#" .. tostring(code)
end

---Writes every setting, key binding, last tab and window rectangle to disk.
function CD.Settings.save()
    local w = getFileWriter(CD.Settings.FILE, true, false)
    if not w then return end
    local d = CD.Settings.data
    w:write("volume=" .. tostring(d.volume) .. "\r\n")
    w:write("mute=" .. tostring(d.mute) .. "\r\n")
    w:write("showTexts=" .. tostring(d.showTexts) .. "\r\n")
    w:write("showMoodles=" .. tostring(d.showMoodles) .. "\r\n")
    w:write("showNames=" .. tostring(d.showNames) .. "\r\n")
    for k, v in pairs(d) do
        if type(k) == "string" and k:match("^dogwinTab") and type(v) == "string" and v ~= "" then
            w:write(k .. "=" .. v .. "\r\n")
        end
    end
    for id, code in pairs(d.keys) do
        w:write("key." .. id .. "=" .. tostring(code) .. "\r\n")
    end
    for _, c in ipairs(CD.SOUND_CATEGORIES) do
        w:write("catvol." .. c .. "=" .. tostring(d.catVol[c]) .. "\r\n")
        w:write("catmute." .. c .. "=" .. tostring(d.catMute[c]) .. "\r\n")
    end
    for name, r in pairs(d.windows or {}) do
        if r and r.x and r.y and r.w and r.h then
            w:write("win." .. name .. ".x=" .. tostring(math.floor(r.x)) .. "\r\n")
            w:write("win." .. name .. ".y=" .. tostring(math.floor(r.y)) .. "\r\n")
            w:write("win." .. name .. ".w=" .. tostring(math.floor(r.w)) .. "\r\n")
            w:write("win." .. name .. ".h=" .. tostring(math.floor(r.h)) .. "\r\n")
        end
    end
    w:close()
end

---Resets to the defaults, then applies every saved line it recognizes.
function CD.Settings.load()
    CD.Settings.data = freshData()
    local r = getFileReader(CD.Settings.FILE, false)
    if not r then return end
    local line = r:readLine()
    while line ~= nil do
        local k, v = line:match("^%s*([^=]-)%s*=%s*(.-)%s*$")
        if k and v then
            if k == "volume" then
                local n = tonumber(v)
                if n then
                    CD.Settings.data.volume = math.max(0, math.min(1, n))
                end
            elseif k == "mute" then
                CD.Settings.data.mute = (v == "true")
            elseif k == "showTexts" then
                CD.Settings.data.showTexts = (v ~= "false")
            elseif k == "showMoodles" then
                CD.Settings.data.showMoodles = (v ~= "false")
            elseif k == "showNames" then
                CD.Settings.data.showNames = (v ~= "false")
            elseif k:match("^dogwinTab@?%d*$") then
                if v ~= "" then
                    CD.Settings.data[k] = v
                end
            elseif k:match("^catvol%.(.+)$") then
                local c = k:match("^catvol%.(.+)$")
                local n = tonumber(v)
                if c and n and CD.Settings.data.catVol[c] ~= nil then
                    CD.Settings.data.catVol[c] = math.max(0, math.min(1, n))
                end
            elseif k:match("^catmute%.(.+)$") then
                local c = k:match("^catmute%.(.+)$")
                if c and CD.Settings.data.catMute[c] ~= nil then
                    CD.Settings.data.catMute[c] = (v == "true")
                end
            else
                local id = k:match("^key%.(.+)$")
                local wname, wfield = k:match("^win%.(.+)%.([xywh])$")
                if id and CD.Settings.data.keys[id] ~= nil then
                    local n = tonumber(v)
                    if n then
                        CD.Settings.data.keys[id] = math.floor(n)
                    end
                elseif wname and wfield then
                    local n = tonumber(v)
                    if n then
                        local rec = CD.Settings.data.windows[wname] or {}
                        rec[wfield] = math.floor(n)
                        CD.Settings.data.windows[wname] = rec
                    end
                end
            end
        end
        line = r:readLine()
    end
    r:close()
end

---@param v number master volume, clamped to 0..1
function CD.Settings.setVolume(v)
    if type(v) ~= "number" then return end
    CD.Settings.data.volume = math.max(0, math.min(1, v))
    CD.Settings.save()
    CD.refreshSoundVolumes()
end

---@param b boolean
function CD.Settings.setMute(b)
    CD.Settings.data.mute = (b == true)
    CD.Settings.save()
    CD.refreshSoundVolumes()
end

---@param cat string one of CD.SOUND_CATEGORIES; others are ignored
---@param v number clamped to 0..1
function CD.Settings.setCatVolume(cat, v)
    if type(v) ~= "number" or CD.Settings.data.catVol[cat] == nil then return end
    CD.Settings.data.catVol[cat] = math.max(0, math.min(1, v))
    CD.Settings.save()
    CD.refreshSoundVolumes()
end

---@param cat string one of CD.SOUND_CATEGORIES; others are ignored
---@param b boolean
function CD.Settings.setCatMute(cat, b)
    if CD.Settings.data.catMute[cat] == nil then return end
    CD.Settings.data.catMute[cat] = (b == true)
    CD.Settings.save()
    CD.refreshSoundVolumes()
end

---@param b boolean
function CD.Settings.setShowTexts(b)
    CD.Settings.data.showTexts = (b ~= false)
    CD.Settings.save()
end

---@param b boolean
function CD.Settings.setShowMoodles(b)
    CD.Settings.data.showMoodles = (b ~= false)
    CD.Settings.save()
end

---@param b boolean
function CD.Settings.setShowNames(b)
    CD.Settings.data.showNames = (b ~= false)
    CD.Settings.save()
end

---@param id string action id; unknown ids are ignored
---@param code number|nil key code; 0 or nil unbinds
function CD.Settings.setKey(id, code)
    if CD.Settings.data.keys[id] == nil then return end
    CD.Settings.data.keys[id] = math.floor(tonumber(code) or 0)
    CD.Settings.save()
end

local function perPlayerKey(base, playerNum)
    local pn = tonumber(playerNum) or 0
    if pn > 0 then return base .. "@" .. pn end
    return base
end

---@param playerNum integer|nil local player index, 0 when nil
---@return string|nil tabId nil when none was saved
---@nodiscard
function CD.Settings.getLastTab(playerNum)
    return CD.Settings.data and CD.Settings.data[perPlayerKey("dogwinTab", playerNum)]
end

---@param name string tab id; an empty one is ignored
---@param playerNum integer|nil local player index, 0 when nil
function CD.Settings.setLastTab(name, playerNum)
    if type(name) ~= "string" or name == "" then return end
    local key = perPlayerKey("dogwinTab", playerNum)
    if CD.Settings.data[key] == name then return end
    CD.Settings.data[key] = name
    CD.Settings.save()
end

---Player 0 keeps the bare name; split screen player n gets name@n.
---@param name string window layout name
---@param playerNum integer|nil local player index, 0 when nil
---@return string
---@nodiscard
function CD.Settings.windowRectKey(name, playerNum)
    return perPlayerKey(name, playerNum)
end

---@param name string key from windowRectKey
---@return table|nil rect a copy of { x, y, w, h }; nil when none is saved
---@nodiscard
function CD.Settings.getWindowRect(name)
    local r = CD.Settings.data and CD.Settings.data.windows and CD.Settings.data.windows[name]
    if r and r.x and r.y and r.w and r.h then
        return { x = r.x, y = r.y, w = r.w, h = r.h }
    end
    return nil
end

---@param name string key from windowRectKey
---@param x number
---@param y number
---@param w number
---@param h number
function CD.Settings.setWindowRect(name, x, y, w, h)
    if not name then return end
    if not (x and y and w and h) then return end
    CD.Settings.data.windows = CD.Settings.data.windows or {}
    CD.Settings.data.windows[name] = { x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }
    CD.Settings.save()
end

---Hunger or thirst level at which this player's dogs go to a trough on their own.
---@param player IsoPlayer|nil first local player when nil
---@return number
---@nodiscard
function CD.Settings.getFeedTrigger(player)
    local p = player or getSpecificPlayer(0)
    local md = p and p:getModData()
    local v = md and md.cdFeedTrigger
    if type(v) == "number" then return v end
    return CD.troughFeedTrigger()
end

---@param v number clamped to 0.1..1
---@param player IsoPlayer|nil first local player when nil
function CD.Settings.setFeedTrigger(v, player)
    if type(v) ~= "number" then return end
    v = math.max(0.1, math.min(1.0, v))
    local p = player or getSpecificPlayer(0)
    if not p then return end
    local md = p:getModData()
    if md.cdFeedTrigger == v then return end
    md.cdFeedTrigger = v
    CD.request("feedtrigger", nil, { value = v }, p)
end

---Wander radius, in tiles, of this player's passive dogs.
---@param player IsoPlayer|nil first local player when nil
---@return number
---@nodiscard
function CD.Settings.getLoiterRadius(player)
    local p = player or getSpecificPlayer(0)
    local md = p and p:getModData()
    local v = md and md.cdLoiterRadius
    if type(v) == "number" then return v end
    return CD.LOITER_RADIUS or 6
end

---@param v number tiles, rounded and clamped to LOITER_RADIUS_MIN..LOITER_RADIUS_MAX
---@param player IsoPlayer|nil first local player when nil
function CD.Settings.setLoiterRadius(v, player)
    if type(v) ~= "number" then return end
    v = math.floor(math.max(CD.LOITER_RADIUS_MIN, math.min(CD.LOITER_RADIUS_MAX, v)) + 0.5)
    local p = player or getSpecificPlayer(0)
    if not p then return end
    local md = p:getModData()
    if md.cdLoiterRadius == v then return end
    md.cdLoiterRadius = v
    CD.request("loiterradius", nil, { value = v }, p)
end

if isClient() or not isServer() then
    CD.Settings.load()
    Events.OnGameStart.Add(CD.Settings.load)
end

CD.UI = CD.UI or {}

CD.UI.SCROLLBAR_W = 17
CD.UI.WHEEL_STEP = 40
CD.UI.SCREEN_FRAC = 0.90

---@param v number
---@param lo number
---@param hi number
---@return number
---@nodiscard
function CD.UI.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

---Instantiates a scrolling view: vertical scrollbar only, children scroll along.
---@param view ISPanel
function CD.UI.viewInstantiate(view)
    ISPanel.instantiate(view)
    view:addScrollBars(false)
    view:setScrollChildren(true)
end

---Scrolls WHEEL_STEP pixels per wheel step.
---@param view ISPanel
---@param del number wheel delta
---@return boolean consumed always true
function CD.UI.viewMouseWheel(view, del)
    view:setYScroll(view:getYScroll() - del * CD.UI.WHEEL_STEP)
    return true
end

---@param view ISPanel
---@return number width usable width, the scrollbar taken out
---@nodiscard
function CD.UI.viewContentW(view)
    return view.width - CD.UI.SCROLLBAR_W
end

---Clips drawing to the view; pair it with viewEndRender.
---@param view ISPanel
function CD.UI.viewBeginRender(view)
    view:setStencilRect(0, 0, view.width, view.height)
end

---@param view ISPanel
function CD.UI.viewEndRender(view)
    view:clearStencilRect()
end

-- Um unico reflow: o ISResizeWidget chama setWidth e setHeight separados, e reflow em cada um
-- sobrescreve lastwidth, zera o delta de ancora e a scrollbar para de acompanhar.
---@param win ISCollapsableWindow window that implements reflow
---@param w number
---@param h number
function CD.UI.applyResize(win, w, h)
    ISCollapsableWindow.setWidth(win, w)
    ISCollapsableWindow.setHeight(win, h)
    win:reflow()
end

---Makes the window resizable down to minW by minH, with both resize grips going through applyResize.
---@param win ISCollapsableWindow window that implements reflow
---@param name string layout name the rectangle is saved under
---@param minW number
---@param minH number
function CD.UI.initResizable(win, name, minW, minH)
    win.cdLayoutName = name
    win.minimumWidth = minW
    win.minimumHeight = minH
    win:setResizable(true)
    local function rf(target, w, h) CD.UI.applyResize(target, w, h) end
    if win.resizeWidget then
        win.resizeWidget.resizeFunction = rf
    end
    if win.resizeWidget2 then
        win.resizeWidget2.resizeFunction = rf
    end
end

-- Viewport do jogador, nao a tela inteira: em tela dividida cada metade e uma tela.
-- O retangulo salvo e relativo a essa viewport, por isso o mesmo valor serve em solo e em split.
---@param win ISCollapsableWindow
---@return number left
---@return number top
---@return number width
---@return number height
---@return integer playerNum
---@nodiscard
function CD.UI.playerViewport(win)
    local pn = win.playerNum or 0
    local left, top = getPlayerScreenLeft(pn), getPlayerScreenTop(pn)
    local sw, sh = getPlayerScreenWidth(pn), getPlayerScreenHeight(pn)
    if not (sw and sw > 0 and sh and sh > 0) then
        local core = getCore()
        left, top, sw, sh = 0, 0, core:getScreenWidth(), core:getScreenHeight()
    end
    return left or 0, top or 0, sw, sh, pn
end

---Restores the saved rectangle clamped to the player viewport; without one, centers a defW by naturalH window.
---@param win ISCollapsableWindow window that implements reflow
---@param name string layout name
---@param defW number default width
---@param naturalH number height the content wants, capped at SCREEN_FRAC of the viewport
function CD.UI.applyOpenGeometry(win, name, defW, naturalH)
    local left, top, sw, sh, pn = CD.UI.playerViewport(win)
    local minW = win.minimumWidth or 120
    local minH = win.minimumHeight or 120
    local rect = CD.Settings.getWindowRect(CD.Settings.windowRectKey(name, pn))
    local w, h, x, y
    if rect then
        w = CD.UI.clamp(rect.w, minW, sw)
        h = CD.UI.clamp(rect.h, minH, sh)
        x = CD.UI.clamp(rect.x, 0, math.max(0, sw - w))
        y = CD.UI.clamp(rect.y, 0, math.max(0, sh - h))
    else
        w = math.max(minW, math.min(defW, sw))
        h = math.max(minH, math.min(naturalH, math.floor(sh * CD.UI.SCREEN_FRAC)))
        x = math.floor(sw / 2 - w / 2)
        y = math.floor(sh / 2 - h / 2)
        if x < 0 then
            x = 0
        end
        if y < 0 then
            y = 0
        end
    end
    CD.UI.applyResize(win, w, h)
    win:setX(left + x)
    win:setY(top + y)
end

---Saves the window rectangle, relative to the player viewport, under its layout name.
---@param win ISCollapsableWindow
function CD.UI.persist(win)
    if not win.cdLayoutName then return end
    local left, top, _, _, pn = CD.UI.playerViewport(win)
    CD.Settings.setWindowRect(CD.Settings.windowRectKey(win.cdLayoutName, pn),
        win:getX() - left, win:getY() - top, win:getWidth(), win:getHeight())
end
