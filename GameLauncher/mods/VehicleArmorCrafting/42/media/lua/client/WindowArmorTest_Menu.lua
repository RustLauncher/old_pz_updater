--[[
    Vehicle Armor Crafting - context menus.
      * right click on a vehicle (standing outside):
            "Window Armor (N/M)"  -> per window: "Install: Windshield" / "Remove: Windshield (73%)"
            "Body Armor (N/2)"    -> "Install: Hood" / "Remove: Trunk Lid (90%)"
            + "Install on all ..." / "Remove all ..."
      * right click on a kit/plate in the inventory -> same submenu for the nearest vehicle
      * an armored window cannot be smashed by hand.
]]
require "WindowArmorTest_Shared"
require "TimedActions/ISWindowArmorTestAction"
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/ISUI/ISVehiclePartMenu"

local WAT = WindowArmorTest

local function exitIfInside(playerObj)
    if playerObj:getVehicle() then
        ISVehicleMenu.onExit(playerObj)
    end
end

-- Queue it up: walk to the part and install/remove the armor
local function queueOne(playerObj, vehicle, partId, mode, item, kind)
    local part = vehicle:getPartById(partId)
    if not part then return false end
    if mode == "install" and item then
        ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    end
    local area = part:getArea()
    local script = vehicle:getScript()
    if area and script and script:getAreaById(area) then
        ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, area))
    else
        local dx, dy = playerObj:getX() - vehicle:getX(), playerObj:getY() - vehicle:getY()
        if dx * dx + dy * dy > 16 then
            WAT.halo(playerObj, WAT.text("IGUI_WAT_TooFar"), 255, 120, 120)
            return false
        end
    end
    ISTimedActionQueue.add(ISWindowArmorTestAction:new(playerObj, vehicle, partId, mode, item, kind))
    return true
end

function WAT.onInstall(playerObj, vehicle, partId, kind)
    kind = kind or "glass"
    local kit = playerObj:getInventory():getFirstTypeRecurse(WAT.KINDS[kind].item)
    if not kit then return end
    exitIfInside(playerObj)
    queueOne(playerObj, vehicle, partId, "install", kit, kind)
end

function WAT.onUninstall(playerObj, vehicle, partId)
    exitIfInside(playerObj)
    queueOne(playerObj, vehicle, partId, "uninstall", nil, WAT.entryKind(WAT.getPartArmor(vehicle, partId)))
end

function WAT.onInstallAll(playerObj, vehicle, kind)
    kind = kind or "glass"
    local kits = playerObj:getInventory():getAllTypeRecurse(WAT.KINDS[kind].item)
    local k = 0
    exitIfInside(playerObj)
    for _, partId in ipairs(WAT.getPartIds(vehicle, kind)) do
        if k >= kits:size() then break end
        if not WAT.getPartArmor(vehicle, partId) and WAT.canInstallOn(vehicle, partId, kind) then
            if queueOne(playerObj, vehicle, partId, "install", kits:get(k), kind) then
                k = k + 1
            end
        end
    end
end

function WAT.onUninstallAll(playerObj, vehicle, kind)
    exitIfInside(playerObj)
    for _, partId in ipairs(WAT.getPartIds(vehicle, kind or "glass")) do
        local entry = WAT.getPartArmor(vehicle, partId)
        if entry then
            queueOne(playerObj, vehicle, partId, "uninstall", nil, WAT.entryKind(entry))
        end
    end
end

local function setUnavailable(option, text)
    option.notAvailable = true
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip.description = text
    option.toolTip = tooltip
end

-- Adds an "<Armor ...> (N/M)" entry with a submenu of vehicle parts
function WAT.fillArmorMenu(context, playerObj, vehicle, kind)
    local def = WAT.KINDS[kind]
    local ids = WAT.getPartIds(vehicle, kind)
    if #ids == 0 then return end

    local kitCount = playerObj:getInventory():getAllTypeRecurse(def.item):size()

    local armored = 0
    for _, id in ipairs(ids) do
        if WAT.getPartArmor(vehicle, id) then armored = armored + 1 end
    end

    local root = context:addOption(WAT.text(def.menuKey) .. " (" .. armored .. "/" .. #ids .. ")")
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)

    local freeCount = 0
    for _, id in ipairs(ids) do
        local name = WAT.partName(id)
        local entry = WAT.getPartArmor(vehicle, id)
        if entry then
            sub:addOption(WAT.text("ContextMenu_WAT_Remove") .. ": " .. name .. " (" .. WAT.percent(entry) .. "%)",
                playerObj, WAT.onUninstall, vehicle, id)
        else
            local opt = sub:addOption(WAT.text("ContextMenu_WAT_Install") .. ": " .. name,
                playerObj, WAT.onInstall, vehicle, id, kind)
            local ok, reason = WAT.canInstallOn(vehicle, id, kind)
            if not ok then
                setUnavailable(opt, reason)
            elseif kitCount == 0 then
                setUnavailable(opt, WAT.text(def.noKitKey))
            else
                freeCount = freeCount + 1
            end
        end
    end

    if kitCount > 0 and freeCount > 1 then
        sub:addOption(WAT.text(def.installAll) .. " (" .. math.min(kitCount, freeCount) .. ")",
            playerObj, WAT.onInstallAll, vehicle, kind)
    end
    if armored > 1 then
        sub:addOption(WAT.text(def.removeAll) .. " (" .. armored .. ")",
            playerObj, WAT.onUninstallAll, vehicle, kind)
    end
end

-- kept for compatibility with the old name
function WAT.fillWindowMenu(context, playerObj, vehicle)
    WAT.fillArmorMenu(context, playerObj, vehicle, "glass")
end

-- right click on a vehicle from outside
local original_FillMenuOutsideVehicle = ISVehicleMenu.FillMenuOutsideVehicle
ISVehicleMenu.FillMenuOutsideVehicle = function(player, context, vehicle, test)
    local result = original_FillMenuOutsideVehicle(player, context, vehicle, test)
    if not test and context and vehicle then
        local playerObj = getSpecificPlayer(player)
        for _, kind in ipairs(WAT.KIND_ORDER) do
            local ok, err = pcall(WAT.fillArmorMenu, context, playerObj, vehicle, kind)
            if not ok then WAT.log("menu error:", err) end
        end
    end
    return result
end

-- Block "Smash window" when that window is armored
local original_onSmashWindow = ISVehiclePartMenu.onSmashWindow
ISVehiclePartMenu.onSmashWindow = function(playerObj, part, open)
    local vehicle = part and part:getVehicle()
    if vehicle and WAT.getPartArmor(vehicle, part:getId()) then
        WAT.halo(playerObj, WAT.text("IGUI_WAT_SmashBlocked"), 255, 200, 60)
        return
    end
    return original_onSmashWindow(playerObj, part, open)
end

-- right click on a kit/plate in the inventory -> submenu for the nearest vehicle
local function onFillInventoryObjectContextMenu(player, context, items)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    local kind = nil
    for _, v in ipairs(items) do
        local it = v
        if type(v) == "table" and v.items then it = v.items[1] end
        if it and instanceof(it, "InventoryItem") then
            kind = WAT.kindOfItem(it:getFullType())
            if kind then break end
        end
    end
    if not kind then return end

    local vehicle = WAT.findNearestVehicle(playerObj, 4)
    if vehicle then
        local ok, err = pcall(WAT.fillArmorMenu, context, playerObj, vehicle, kind)
        if not ok then WAT.log("menu error:", err) end
    else
        local opt = context:addOption(WAT.text(WAT.KINDS[kind].menuKey))
        setUnavailable(opt, WAT.text("IGUI_WAT_NoVehicle"))
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
