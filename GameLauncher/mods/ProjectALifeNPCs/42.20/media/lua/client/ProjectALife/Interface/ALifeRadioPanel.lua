require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Interface/ALifeMenuPrefs"
require "ProjectALife/Interface/ALifeFieldRadioWindow"
require "RadioCom/ISRadioWindow"

ProjectALife = ProjectALife or {}

local Panel = ProjectALife.RadioPanel or {}
ProjectALife.RadioPanel = Panel

function Panel.enabled()
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.radioPanelOn) ~= "function" then return false end
    return prefs.radioPanelOn() == true
end

function Panel.dataOf(thing)
    if thing == nil or type(thing.getDeviceData) ~= "function" then return nil end
    return thing:getDeviceData()
end

function Panel.read(data, method, default)
    local fn = data[method]
    if type(fn) ~= "function" then return default end
    local value = fn(data)
    if value == nil then return default end
    return value
end

Panel.info = {}

function Panel.readout(device)
    local data = Panel.dataOf(device)
    if data == nil then return nil end
    local channel = Panel.read(data, "getChannel", 0)
    local low = Panel.read(data, "getMinChannelRange", 0)
    local high = Panel.read(data, "getMaxChannelRange", 0)
    local info = Panel.info
    info.name = tostring(Panel.read(data, "getDeviceName", ""))
    info.on = Panel.read(data, "getIsTurnedOn", false) == true
    info.volume = math.max(0, math.min(1, Panel.read(data, "getDeviceVolume", 0)))
    if Panel.channelKey ~= channel then
        Panel.channelKey = channel
        Panel.channelText = tostring(math.floor(channel / 100 + 0.5) / 10) .. " MHz"
        Panel.stationText = nil
        if type(getZomboidRadio) == "function" then
            local radio = getZomboidRadio()
            if radio ~= nil and type(radio.getChannelName) == "function" then
                local station = radio:getChannelName(channel)
                if station ~= nil and station ~= "" then Panel.stationText = tostring(station) end
            end
        end
    end
    info.channelText = Panel.channelText
    info.station = Panel.stationText
    info.fraction = 0
    if high > low then info.fraction = math.max(0, math.min(1, (channel - low) / (high - low))) end
    info.power = nil
    if Panel.read(data, "getIsBatteryPowered", false) == true then
        info.power = math.max(0, math.min(1, Panel.read(data, "getPower", 0)))
    end
    return info
end

function Panel.resetWindow()
    local window = ALifeFieldRadioWindow.instance
    if window ~= nil then
        pcall(function()
            window:setVisible(false)
            window:removeFromUIManager()
        end)
    end
    ALifeFieldRadioWindow.instance = nil
    Panel.channelKey = nil
end

function Panel.open(playerNum, device)
    if not Panel.enabled() then
        Panel.apply()
        return false
    end
    return ALifeFieldRadioWindow.show(playerNum or 0, device)
end

function Panel.apply()
    if not Panel.enabled() and ALifeFieldRadioWindow.instance ~= nil then ALifeFieldRadioWindow.instance:close() end
    return true
end

function Panel.flatten(items)
    if type(items) ~= "table" then return {} end
    if type(ISInventoryPane) == "table" and type(ISInventoryPane.getActualItems) == "function" then
        return ISInventoryPane.getActualItems(items)
    end
    local list = {}
    for _, entry in ipairs(items) do
        if type(entry) == "table" and type(entry.items) == "table" then list[#list + 1] = entry.items[2] or entry.items[1]
        else list[#list + 1] = entry end
    end
    return list
end

function Panel.addEntry(context, playerNum, device)
    local option = context:addOption(ProjectALife.Text.ui("A-Life Radio"), playerNum, Panel.open, device)
    if option ~= nil and type(instanceof) == "function" and instanceof(device, "InventoryItem") then option.itemForTexture = device end
    return option
end

function Panel.onInventoryMenu(playerNum, context, items)
    if not Panel.enabled() or type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    local list = Panel.flatten(items)
    for index = 1, #list do
        if Panel.dataOf(list[index]) ~= nil then
            Panel.addEntry(context, playerNum, list[index])
            return
        end
    end
end

function Panel.worldDevice(worldObjects)
    if type(worldObjects) ~= "table" or type(instanceof) ~= "function" then return nil end
    for _, object in ipairs(worldObjects) do
        if instanceof(object, "IsoWaveSignal") and Panel.dataOf(object) ~= nil then return object end
        if instanceof(object, "IsoWorldInventoryObject") and type(object.getItem) == "function" then
            local item = object:getItem()
            if Panel.dataOf(item) ~= nil then return item end
        end
    end
    return nil
end

function Panel.onWorldMenu(playerNum, context, worldObjects, test)
    if not Panel.enabled() or type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    local device = Panel.worldDevice(worldObjects)
    if device == nil then return end
    if test then
        if type(ISWorldObjectContextMenu) == "table" and type(ISWorldObjectContextMenu.setTest) == "function" then
            return ISWorldObjectContextMenu.setTest()
        end
        return true
    end
    Panel.addEntry(context, playerNum, device)
end

function Panel.buttonClick(window)
    if type(window) ~= "table" then return false end
    return Panel.open(window.playerNum or 0, window.device)
end

function Panel.addButton(window)
    if type(ISButton) ~= "table" or window.alifeButton ~= nil then return end
    local theme = ALifeFieldRadioWindow ~= nil and ProjectALife.FieldRadio ~= nil and ProjectALife.FieldRadio.theme or nil
    local button = ISButton:new(4, 0, math.max(10, window.width - 8), 22, ProjectALife.Text.ui("A-Life Radio"), window, Panel.buttonClick)
    button:initialise()
    button:instantiate()
    if theme ~= nil then
        button.backgroundColor = { r = theme.tabOff[1], g = theme.tabOff[2], b = theme.tabOff[3], a = 1 }
        button.backgroundColorMouseOver = { r = theme.tabOn[1], g = theme.tabOn[2], b = theme.tabOn[3], a = 1 }
        button.borderColor = { r = theme.accent[1], g = theme.accent[2], b = theme.accent[3], a = 1 }
        button.textColor = { r = theme.lit[1], g = theme.lit[2], b = theme.lit[3], a = 1 }
    end
    button:setVisible(false)
    window:addChild(button)
    window.alifeButton = button
end

function Panel.placeButton(window)
    local button = window.alifeButton
    if button == nil then return end
    local show = Panel.enabled() and window.deviceData ~= nil and window.isCollapsed ~= true
    button:setVisible(show)
    if not show then return end
    local height = window:getHeight()
    button:setWidth(math.max(10, window:getWidth() - 8))
    button:setY(height + 2)
    window:setHeight(height + button:getHeight() + 6)
end

function Panel.hookVanilla()
    if Panel.hooked == true or type(ISRadioWindow) ~= "table" then return false end
    if type(ISRadioWindow.createChildren) ~= "function" or type(ISRadioWindow.prerender) ~= "function" then return false end
    Panel.hooked = true
    Panel.baseCreate = ISRadioWindow.createChildren
    Panel.basePrerender = ISRadioWindow.prerender
    ISRadioWindow.createChildren = function(window)
        Panel.baseCreate(window)
        Panel.addButton(window)
    end
    ISRadioWindow.prerender = function(window)
        Panel.basePrerender(window)
        Panel.placeButton(window)
    end
    return true
end

function Panel.onKeyPressed(key)
    local window = ALifeFieldRadioWindow.instance
    if window == nil or key == nil or type(Keyboard) ~= "table" then return false end
    if key == Keyboard.KEY_PRIOR then window:stepTab(-1) return true end
    if key == Keyboard.KEY_NEXT then window:stepTab(1) return true end
    return false
end

Panel.hookVanilla()

if type(Events) == "table" then
    if Events.OnFillInventoryObjectContextMenu ~= nil and type(Events.OnFillInventoryObjectContextMenu.Add) == "function" then
        Events.OnFillInventoryObjectContextMenu.Add(Panel.onInventoryMenu)
    end
    if Events.OnFillWorldObjectContextMenu ~= nil and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
        Events.OnFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(Panel.onWorldMenu))
    end
    if Events.OnKeyPressed ~= nil and type(Events.OnKeyPressed.Add) == "function" then
        Events.OnKeyPressed.Add(Panel.onKeyPressed)
    end
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(Panel.hookVanilla)
        Events.OnGameStart.Add(Panel.resetWindow)
    end
    if Events.OnMainMenuEnter ~= nil and type(Events.OnMainMenuEnter.Add) == "function" then
        Events.OnMainMenuEnter.Add(Panel.resetWindow)
    end
end

return Panel
