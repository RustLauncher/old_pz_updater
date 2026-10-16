CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs
CD.Keybinds = CD.Keybinds or {}

---The next key press goes to cb instead of the bindings; Escape arrives as nil.
---@param cb fun(code: integer|nil)
function CD.Keybinds.beginCapture(cb)
    CD.Keybinds.captureCb = cb
end

---Names of the game bindings and of our other actions already on this key.
---@param code number|nil key code; nil or 0 finds nothing
---@param exceptId string|nil action id left out of the check
---@return string[]
---@nodiscard
function CD.Keybinds.findConflicts(code, exceptId)
    local names = {}
    if not code or code == 0 then return names end
    for _, e in ipairs(keyBinding) do
        local nm = e and e.value
        if nm and nm ~= "" then
            local cur = getCore():getKey(nm)
            if cur and cur ~= 0 and cur == code then
                names[#names + 1] = nm
            end
        end
    end
    local keys = CD.Settings.data and CD.Settings.data.keys
    if keys then
        for id, c in pairs(keys) do
            if id ~= exceptId and c ~= 0 and c == code then
                local a = CD.Settings.ACTION_BY_ID[id]
                names[#names + 1] = (a and getText(a.label)) or id
            end
        end
    end
    return names
end

local function isBlocked()
    if not (MainScreen.instance and MainScreen.instance.inGame) then return true end
    if MainScreen.instance:getIsVisible() then return true end
    if ISChat.instance and ISChat.instance.textEntry
        and ISChat.instance.textEntry.javaObject and ISChat.instance.textEntry:isFocused() then
        return true
    end
    return false
end

local function keyboardPlayer()
    local n = getNumActivePlayers() or 1
    if n <= 1 then return getPlayer() end
    for i = 0, n - 1 do
        local jp = getJoypadData(i)
        if jp == nil then
            local p = getSpecificPlayer(i)
            if p then return p end
        end
    end
    return getPlayer()
end

local function fire(id)
    local spec = CD.Settings.ACTION_BY_ID[id]
    if not spec then return end
    local player = keyboardPlayer()
    if not player then return end

    if spec.special == "status" then
        CD.openDogStatus(player)
        return
    end

    local dog = CD.getCompanionAnimal(player)
    if not dog then
        HaloTextHelper.addText(player, getText("IGUI_PD_NoCompanionNear"))
        return
    end

    if spec.trick then
        CD.startTrick(player, dog, spec.trick)
        return
    end

    if spec.special == "pet" then
        if CD.bondingEnabled() and CD.startPet then
            CD.startPet(player, dog)
        end
        return
    end

    if spec.gesture then
        player:playEmote(spec.gesture)
    end
    if spec.callout then
        player:Callout(false)
    end

    if spec.special == "protect" then
        local on = false
        if dog then
            on = CD.getAutoProtect(dog)
        end
        CD.request("setautoprotect", dog, { on = not on }, player)
        return
    end

    if spec.special == "hunt" then
        if not CD.huntEnabled() then return end
        if dog and not CD.breedCanHunt(dog) then return end
        local on = false
        if dog then
            on = CD.getHuntMode(dog)
        end
        CD.request("sethuntmode", dog, { on = not on }, player)
        return
    end

    local extra = nil
    if spec.args then
        extra = {}
        for k, v in pairs(spec.args) do extra[k] = v end
    end
    CD.request(spec.cmd, dog, extra, player)
    player:setJoypadIgnoreAimUntilCentered(true)
end

local function onKeyStartPressed(key)
    if CD.Keybinds.captureCb then
        local cb = CD.Keybinds.captureCb
        CD.Keybinds.captureCb = nil
        if key == Keyboard.KEY_ESCAPE then
            cb(nil)
        else
            cb(key)
        end
        return
    end
    if not key or key == 0 then return end
    if isBlocked() then return end
    local keys = CD.Settings.data and CD.Settings.data.keys
    if not keys then return end
    for _, spec in ipairs(CD.Settings.ACTIONS) do
        if keys[spec.id] == key then
            fire(spec.id)
            return
        end
    end
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnKeyStartPressed, onKeyStartPressed, "cli.keybind")
end
