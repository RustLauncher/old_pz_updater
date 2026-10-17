require "ISUI/ISContextMenu"
require "HalloweenEvent/EVHalloween_Items"
require "TimedActions/ISEVHalloweenBatteryAction"

local Items = HalloweenEvent.Items
local HWE=HalloweenEvent

local function submenu(parent, name, debugOption)
    local option = parent:getOptionFromName(name)
    if option and option.subOption then return parent:getSubMenu(option.subOption) end
    option = option or (debugOption and parent:addDebugOption(name) or parent:addOption(name))
    local menu = ISContextMenu:getNew(parent)
    parent:addSubMenu(option, menu)
    return menu
end

local function allowed(player)
    if type(isClient) ~= "function" or not isClient() then return true end
    local level = tostring(player:getAccessLevel() or ""):lower()
    return level == "admin" or level == "moderator" or level == "overseer"
end

local function dispatch(playerNum, command, fullType, variant)
    local player = getSpecificPlayer(playerNum)
    if not player or not allowed(player) then return end
    local args = {fullType=fullType,variant=variant}
    if type(isClient) == "function" and isClient() then
        sendClientCommand(player, "EVHalloweenItems", command, args)
    else
        if not Items.DebugServer then require "HalloweenEvent/EVHalloween_ItemDebugServer" end
        if Items.DebugServer then Items.DebugServer.handle(player, command, args) end
    end
end

-- Lua debugger console, SP and MP: EVHalloweenSpawnGround()
function EVHalloweenSpawnGround(playerNum)
    dispatch(playerNum or 0, "GiveAllGround")
end

function EVHalloweenSpawnDoormats(playerNum) dispatch(playerNum or 0,"DoormatGround") end

local function worldMenu(playerNum, context, worldObjects, test)
    if test or not context or HalloweenEvent.readSandbox().EnableDebugMenu == false then return end
    local player = getSpecificPlayer(playerNum)
    if not player or not allowed(player) then return end
    local debugName = type(getText) == "function" and getText("ContextMenu_Debug") or "Debug"
    local debugMenu = submenu(context, debugName, true)
    local hwe = submenu(debugMenu, "HWE", true)
    local menu = submenu(hwe, HWE.text("ItemMenu"))
    if menu:getOptionFromName(HWE.text("GiveAll")) then return end
    menu:addOption(HWE.text("GiveAll"), playerNum, dispatch, "GiveAll")
    menu:addOption(HWE.text("GroundAll"), playerNum, dispatch, "GiveAllGround")
    menu:addOption(HWE.text("GroundMats"), playerNum, dispatch, "DoormatGround")
    menu:addOption(HWE.text("BucketComparison"), playerNum, dispatch, "BucketComparison")
    menu:addOption(HWE.text("AuditDefinitions"), playerNum, dispatch, "Audit")
    menu:addOption(HWE.text("AuditPlaced"), nil, function()
        if Items.Visuals then Items.Visuals.audit() end
    end)
    for _, group in ipairs({"Functional", "Decorations"}) do
        local choices = submenu(menu, HWE.groupName(group))
        for _, entry in ipairs(Items.catalog) do
            if entry.group == group then
                local short = entry.fullType:gsub("^HalloweenEvent%.", "")
                if entry.fullType=="HalloweenEvent.EVHalloween_Decor_TombstoneCracked" then
                    local mats=submenu(choices,HWE.choiceName(entry).." ["..short.."]")
                    for _,variant in ipairs(Items.doormatVariants) do mats:addOption(HWE.text(variant.index==0 and "HappyHalloween" or "TrickOrTreat"),playerNum,dispatch,"GiveOne",entry.fullType,variant.index) end
                else choices:addOption(HWE.choiceName(entry) .. " [" .. short .. "]", playerNum, dispatch, "GiveOne", entry.fullType) end
            end
        end
    end
end

local function replaceBattery(player, lantern, battery)
    if not lantern or not battery then return end
    ISTimedActionQueue.add(ISEVHalloweenBatteryAction:new(player, lantern, battery))
end

local function inventoryMenu(playerNum, context, selection)
    local player = getSpecificPlayer(playerNum)
    if not player or not context then return end
    local inventory = player:getInventory()
    for _, value in ipairs(selection or {}) do
        local item = type(value) == "table" and value.items and value.items[1] or value
        if item and item.getFullType and item:getFullType() == Items.lanternType
            and item:getContainer() == inventory then
            local battery, best = nil, 0
            local list = inventory:getItems()
            for i=0,list:size()-1 do
                local candidate = list:get(i)
                if candidate:getFullType() == "Base.Battery" then
                    local charge = candidate:getCurrentUsesFloat()
                    if charge > best then battery, best = candidate, charge end
                end
            end
            local option = context:addOption(HWE.text("ReplaceBattery"), player, replaceBattery, item, battery)
            option.notAvailable = not battery
            if not battery and Items.Visuals then Items.Visuals.tooltip(option,HWE.text("NeedBattery")) end
            return
        end
    end
end

if Events and Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(worldMenu) end
if Events and Events.OnFillInventoryObjectContextMenu then Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu) end
HalloweenEvent.log("ITEMS DEBUG_MENU_READY path=Debug/HWE/EVHalloween Items (25)")
if Events.OnServerCommand then Events.OnServerCommand.Add(function(module,command,args)
    if module=="EVHalloweenItems" and command=="DebugFeedback" then
        local player=getSpecificPlayer(0);if player then player:Say(args.key and HWE.text(args.key) or args.text) end
    end
end) end

require "HalloweenEvent/EVHalloween_PailGripTest"
return true
