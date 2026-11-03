-- Mattnetic's Heart Health Meter
-- Project Zomboid Build 42.20+
-- v1.2.3: Minimal Sidebar compatibility - child alpha is authoritative.
-- The verified health renderer remains: dim vanilla heart + bottom-up vanilla fill.

require "ISUI/ISEquippedItem"
require "ISUI/ISContextMenu"
require "PZAPI/ModOptions"

local MOD_ID = "HeartHealthMeter"
local DISPLAY_NAME = "Mattnetic's Heart Health Meter"
local MOD_VERSION = "1.2.3"
local CONFIG_FILE = "HeartHealthMeter.cfg"
local CONFIG_SCHEMA = 2
local EMPTY_TINT = 0.25

local settings = { meterEnabled = true }
local recoveredStartupSetting = false
local modOptions = nil
local meterOption = nil
local attachedOwners = setmetatable({}, { __mode = "k" })

local function safeCall(defaultValue, fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return defaultValue
end

local function clamp01(value)
    value = tonumber(value) or 0.0
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function readSettingsFile(fileName)
    local reader = safeCall(nil, function() return getFileReader(fileName, false) end)
    if not reader then return nil, nil end

    local storedSchema, storedMeter = nil, nil
    pcall(function()
        local line = reader:readLine()
        while line do
            local key, value = string.match(line, "^([^=]+)=(.*)$")
            if key == "schema" then
                storedSchema = tonumber(value)
            elseif key == "meter" then
                storedMeter = value ~= "false"
            end
            line = reader:readLine()
        end
    end)
    pcall(function() reader:close() end)
    return storedSchema, storedMeter
end

local function saveSettings()
    local writer = safeCall(nil, function() return getFileWriter(CONFIG_FILE, true, false) end)
    if not writer then return end
    pcall(function()
        writer:write("schema=" .. tostring(CONFIG_SCHEMA) .. "\r\n")
        writer:write("meter=" .. tostring(settings.meterEnabled) .. "\r\n")
        writer:close()
    end)
end

local function loadSettings()
    local storedSchema, storedMeter = readSettingsFile(CONFIG_FILE)
    if storedSchema == CONFIG_SCHEMA and storedMeter ~= nil then
        settings.meterEnabled = storedMeter
    else
        settings.meterEnabled = true
        recoveredStartupSetting = true
    end
    saveSettings()
end

local function getHealth(character)
    if not character then return nil, nil end
    local bodyDamage = safeCall(nil, function() return character:getBodyDamage() end)
    if not bodyDamage then return nil, nil end
    local health = safeCall(nil, function() return bodyDamage:getHealth() end)
    if health == nil then return nil, nil end
    return health, clamp01(health / 100.0)
end

local function saveNativeModOptions()
    if not PZAPI or not PZAPI.ModOptions then return end
    pcall(function() PZAPI.ModOptions:save() end)
end

local function restoreButtonImage(owner)
    if not owner or not owner.healthBtn then return end
    local state = owner.healthBtn._HeartHealthMeterButtonState
    if state and state.texture and not owner.healthBtn.image then
        owner.healthBtn:setImage(state.texture)
    end
end

local function restoreAllOwners()
    for owner in pairs(attachedOwners) do restoreButtonImage(owner) end
end

local function setMeterEnabled(value, owner, source, saveNative)
    local enabled = value ~= false
    local changed = settings.meterEnabled ~= enabled
    settings.meterEnabled = enabled
    saveSettings()

    if meterOption and meterOption:getValue() ~= enabled then
        meterOption:setValue(enabled)
    end
    if saveNative then saveNativeModOptions() end
    if not enabled then
        if owner then restoreButtonImage(owner) end
        restoreAllOwners()
    end

    if changed then
        print("[HeartHealthMeter " .. MOD_VERSION .. "] Heart Health Meter="
            .. tostring(enabled) .. " via " .. tostring(source or "unknown"))
    end
end

local function registerModOptions()
    if not PZAPI or not PZAPI.ModOptions then return end
    modOptions = PZAPI.ModOptions:getOptions(MOD_ID)
    if not modOptions then modOptions = PZAPI.ModOptions:create(MOD_ID, DISPLAY_NAME) end

    meterOption = modOptions:getOption("meterEnabled")
    if not meterOption then
        meterOption = modOptions:addTickBox(
            "meterEnabled",
            "Enable Heart Health Meter",
            settings.meterEnabled,
            "Show current overall health by draining the vanilla top-left heart icon."
        )
    end
    meterOption:setValue(settings.meterEnabled)
    if recoveredStartupSetting then saveNativeModOptions() end

    modOptions.apply = function(self)
        local option = self:getOption("meterEnabled")
        if option then setMeterEnabled(option:getValue(), nil, "Options > Mods", false) end
    end
end

local function toggleMeter(owner)
    setMeterEnabled(not settings.meterEnabled, owner, "heart right-click", true)
end

local function onHealthButtonRightMouseUp(button, x, y)
    local owner = button._HeartHealthMeterOwner
    if not owner then return false end
    local playerNum = owner.playerNum
    if playerNum == nil and owner.chr then
        playerNum = safeCall(0, function() return owner.chr:getPlayerNum() end)
    end
    playerNum = playerNum or 0
    local menuX = button:getAbsoluteX() + (x or button:getWidth() / 2)
    local menuY = button:getAbsoluteY() + (y or button:getHeight() / 2)
    local context = ISContextMenu.get(playerNum, menuX, menuY)
    local option = context:addOption("Heart Health Meter", owner, toggleMeter)
    option.checkMark = settings.meterEnabled
    return true
end

local function getMinimalSidebarAlpha(button)
    -- Minimal Sidebar documents textureColor.a as the authoritative opacity for
    -- ISButton children. Respect it exactly. Do NOT force our own visibility.
    if button and button.textureColor and button.textureColor.a ~= nil then
        return clamp01(button.textureColor.a)
    end
    return 1.0
end

local function attachToOwner(owner)
    if not owner or not owner.healthBtn then return false end
    local button = owner.healthBtn
    attachedOwners[owner] = true
    button._HeartHealthMeterOwner = owner
    button.onRightMouseUp = onHealthButtonRightMouseUp

    local current = button._HeartHealthMeterButtonState
    if current and current.version == MOD_VERSION then return true end

    -- Unwrap our own previous button-local compatibility build on Lua reload.
    local baseRender = button.render
    if current and current.wrappedRender and baseRender == current.wrappedRender and current.baseRender then
        baseRender = current.baseRender
    end

    -- Also unwrap a v1.2.2 button-local renderer if it left a compatible state.
    local legacy = button._HHMButtonRenderState
    if legacy and legacy.wrappedRender and baseRender == legacy.wrappedRender and legacy.baseRender then
        baseRender = legacy.baseRender
    end

    local state = {
        version = MOD_VERSION,
        baseRender = baseRender,
        texture = button.image,
        owner = owner,
        lastAlphaBucket = nil,
    }

    local function wrappedRender(self)
        -- Keep the real vanilla image on the child at all times outside this call.
        -- Minimal Sidebar can therefore inspect/fade/pulse/shake it normally.
        local liveTexture = self.image or state.texture
        if self.image then state.texture = self.image end

        if not settings.meterEnabled or not liveTexture then
            return state.baseRender(self)
        end

        -- Suppress only the normal full-heart image for this one render call.
        -- The button itself, its hover/click behavior, position, size, and alpha
        -- remain fully owned by vanilla / Minimal Sidebar.
        local savedImage = self.image
        self.image = nil
        local ok, err = pcall(state.baseRender, self)
        self.image = savedImage
        if not ok then
            print("[HeartHealthMeter " .. MOD_VERSION .. "] Base heart-button render failed: " .. tostring(err))
            return
        end

        local alpha = getMinimalSidebarAlpha(self)
        if alpha <= 0.001 then
            -- Crucial compatibility rule: hidden Minimal Sidebar heart stays hidden.
            return
        end

        local character = state.owner and state.owner.chr
        local health, ratio = getHealth(character)
        if health == nil or ratio == nil then return end

        local w, h = self:getWidth(), self:getHeight()
        if not w or not h or w <= 0 or h <= 0 then return end

        -- Button-local coordinates preserve Minimal Sidebar shake/position changes.
        self:drawTextureScaled(liveTexture, 0, 0, w, h,
            alpha, EMPTY_TINT, EMPTY_TINT, EMPTY_TINT)

        if ratio > 0.0 and self.javaObject then
            self.javaObject:DrawTexturePercentageBottomUp(
                liveTexture, ratio, 0, 0, w, h, 1.0, 1.0, 1.0, alpha)
        end

        if not state.initialHealth then
            state.initialHealth = health
            print(string.format(
                "[HeartHealthMeter %s] Renderer active: health=%.3f ratio=%.5f button=%.0fx%.0f alpha=%.3f meter=%s",
                MOD_VERSION, health, ratio, w, h, alpha, tostring(settings.meterEnabled)))
        elseif not state.loggedHealthChange and math.abs(health - state.initialHealth) >= 0.25 then
            state.loggedHealthChange = true
            print(string.format(
                "[HeartHealthMeter %s] Health change observed and drawn: %.3f -> %.3f ratio=%.5f alpha=%.3f",
                MOD_VERSION, state.initialHealth, health, ratio, alpha))
        end

        -- One-shot evidence that Minimal Sidebar fade ownership is being honored.
        local bucket = alpha <= 0.01 and 0 or (alpha < 0.99 and 1 or 2)
        if state.lastAlphaBucket ~= bucket then
            state.lastAlphaBucket = bucket
            if bucket < 2 then
                print(string.format(
                    "[HeartHealthMeter %s] Minimal Sidebar alpha honored: %.3f",
                    MOD_VERSION, alpha))
            end
        end
    end

    state.wrappedRender = wrappedRender
    button.render = wrappedRender
    button._HeartHealthMeterButtonState = state

    if not owner._HeartHealthMeterAttachedLogged then
        owner._HeartHealthMeterAttachedLogged = true
        print("[HeartHealthMeter " .. MOD_VERSION
            .. "] Attached alpha-aware button-local renderer; parent ISEquippedItem render/prerender untouched.")
    end
    return true
end

local function getEquippedOwner(playerNum)
    local data = safeCall(nil, function() return getPlayerData(playerNum) end)
    if not data then return nil end
    return data.equipped or data.equippedItem or data.equippedUI
end

local function attachForPlayer(playerNum)
    playerNum = tonumber(playerNum) or 0
    local owner = getEquippedOwner(playerNum)
    if owner then return attachToOwner(owner) end
    return false
end

local function onCreatePlayer(playerNum, player)
    attachForPlayer(playerNum)
end

local function onGameStart()
    local count = safeCall(1, function() return getNumActivePlayers() end) or 1
    for playerNum = 0, math.max(0, count - 1) do
        attachForPlayer(playerNum)
    end
end

loadSettings()
registerModOptions()
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnGameStart.Add(onGameStart)

local activeMods = safeCall(nil, function() return getActivatedMods() end)
local minimalSidebar = activeMods and safeCall(false, function() return activeMods:contains("MinimalSidebar") end) or false
print("[HeartHealthMeter " .. MOD_VERSION
    .. "] Compatibility renderer installed; meter=" .. tostring(settings.meterEnabled)
    .. " MinimalSidebar=" .. tostring(minimalSidebar))
