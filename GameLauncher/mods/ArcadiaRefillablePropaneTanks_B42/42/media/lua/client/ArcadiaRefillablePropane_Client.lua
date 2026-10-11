require "ArcadiaRefillablePropane_Shared"
require "TimedActions/ISArcadiaRefillPropaneAction"
require "TimedActions/ISArcadiaVehiclePropaneAction"
require "ISUI/ISContextMenu"
require "luautils"

ArcadiaRefillablePropaneClient = ArcadiaRefillablePropaneClient or {}

local Client = ArcadiaRefillablePropaneClient
local Depot = ArcadiaRefillablePropane

local function getTargets(player)
    local targets = player:getInventory():getAllEvalRecurse(function(item)
        return Depot.getTargetKind(item) ~= nil and
            Depot.getMissingUnits(item) > Depot.MIN_TRANSFER
    end)
    local result = {}
    for index = 0, targets:size() - 1 do
        result[#result + 1] = targets:get(index)
    end
    table.sort(result, function(left, right)
        local leftKind = Depot.getTargetKind(left)
        local rightKind = Depot.getTargetKind(right)
        if leftKind ~= rightKind then return leftKind == "tank" end
        return left:getID() < right:getID()
    end)
    return result
end

local function getPropaneSources(player)
    local sources = player:getInventory():getAllEvalRecurse(function(item)
        return Depot.isPropaneSourceItem(item)
    end)
    local result = {}
    for index = 0, sources:size() - 1 do
        result[#result + 1] = sources:get(index)
    end
    table.sort(result, function(left, right)
        return left:getID() < right:getID()
    end)
    return result
end

local function makeTooltip(text)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = text
    return tooltip
end

function Client.queueRefill(object, player, item, direction)
    if luautils.walkAdj(player, object:getSquare()) then
        ISTimedActionQueue.add(
            ISArcadiaRefillPropaneAction:new(player, object, item, direction)
        )
    end
end

local function queueVehicleTransfer(player, vehicle, part, direction, item, object)
    if direction == "depot_to_vehicle" or direction == "vehicle_to_depot" then
        if not object or not luautils.walkAdj(player, object:getSquare()) then
            return
        end
    else
        local area = part:getArea()
        if area then
            ISTimedActionQueue.add(
                ISPathFindAction:pathToVehicleArea(player, vehicle, area)
            )
        end
    end
    ISTimedActionQueue.add(ISArcadiaVehiclePropaneAction:new(
        player,
        vehicle,
        part,
        direction,
        item,
        object
    ))
end

local function findClickedVehicle(worldObjects)
    for _, worldObject in ipairs(worldObjects or {}) do
        if instanceof(worldObject, "BaseVehicle") then return worldObject end
        local square = worldObject and worldObject.getSquare and
            worldObject:getSquare() or nil
        local vehicle = square and square.getVehicleContainer and
            square:getVehicleContainer() or nil
        if vehicle and Depot.isFilibusterPropaneVehicle(vehicle) then
            return vehicle
        end
    end
    if IsoObjectPicker and IsoObjectPicker.Instance then
        return IsoObjectPicker.Instance:PickVehicle(
            getMouseXScaled(),
            getMouseYScaled()
        )
    end
    return nil
end

local function findNearbyVehicleParts(object, predicate)
    local result = {}
    local cell = getCell and getCell() or nil
    local vehicles = cell and cell:getVehicles() or nil
    if not vehicles then return result end
    -- B42 returns a java.util.Set here, not an indexed ArrayList.
    -- Iterate it directly so opening a stocked depot's context menu never
    -- attempts the nonexistent Set:get(index) call.
    local iterator = vehicles:iterator()
    while iterator:hasNext() do
        local vehicle = iterator:next()
        if Depot.isVehicleNearDepot(vehicle, object) then
            for _, part in ipairs(Depot.getFilibusterPropaneParts(vehicle)) do
                if not predicate or predicate(part) then
                    result[#result + 1] = { vehicle = vehicle, part = part }
                end
            end
        end
    end
    return result
end

local function getVehicleStorageLabel(part)
    return Depot.formatAmount(Depot.getVehiclePropaneAmount(part)) .. "/" ..
        Depot.formatAmount(Depot.getVehiclePropaneCapacity(part))
end

local function addVehicleMenu(context, player, vehicle, part)
    local stored = Depot.getVehiclePropaneAmount(part)
    local capacity = Depot.getVehiclePropaneCapacity(part)
    local rootLabel = Depot.getPropaneVehicleLabel(vehicle) .. " " ..
        Depot.getFilibusterTankLabel(part) .. " (" ..
        getVehicleStorageLabel(part) .. ")"
    local rootOption = context:addOptionOnTop(rootLabel, vehicle, nil)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, submenu)

    local status = submenu:addOption(
        getText("UI_RPT_Storage") .. ": " .. getVehicleStorageLabel(part),
        nil,
        nil
    )
    status.notAvailable = true

    local takeOption = submenu:addOption(
        getText("UI_RPT_RefillFromVehicle"),
        nil,
        nil
    )
    local takeMenu = ISContextMenu:getNew(submenu)
    submenu:addSubMenu(takeOption, takeMenu)
    if stored <= Depot.MIN_TRANSFER then
        takeOption.notAvailable = true
        takeOption.toolTip = makeTooltip(getText("UI_RPT_VehicleEmpty"))
    else
        local targets = getTargets(player)
        if #targets == 0 then
            takeOption.notAvailable = true
            takeOption.toolTip = makeTooltip(getText("UI_RPT_NoTargets"))
        else
            for _, item in ipairs(targets) do
                local transfer = math.min(
                    Depot.getMissingUnits(item),
                    Depot.vehiclePropaneToDepotUnits(stored)
                )
                local targetFraction = math.min(
                    1,
                    Depot.getTargetFraction(item) +
                        transfer / Depot.getTargetFullCost(item)
                )
                local label = item:getDisplayName() .. " (" ..
                    Depot.formatPercent(item) .. "% -> " ..
                    tostring(math.floor(targetFraction * 100 + 0.5)) .. "%)"
                local option = takeMenu:addOption(
                    label,
                    player,
                    queueVehicleTransfer,
                    vehicle,
                    part,
                    "vehicle_to_item",
                    item,
                    nil
                )
                option.toolTip = makeTooltip(
                    getText("UI_RPT_TransferAmount") .. ": " ..
                        Depot.formatAmount(transfer)
                )
            end
        end
    end

    local fillOption = submenu:addOption(
        getText("UI_RPT_FillVehicleFromItem"),
        nil,
        nil
    )
    local fillMenu = ISContextMenu:getNew(submenu)
    submenu:addSubMenu(fillOption, fillMenu)
    local missing = capacity - stored
    if missing <= Depot.MIN_TRANSFER then
        fillOption.notAvailable = true
        fillOption.toolTip = makeTooltip(getText("UI_RPT_VehicleAlreadyFull"))
    else
        local sources = getPropaneSources(player)
        if #sources == 0 then
            fillOption.notAvailable = true
            fillOption.toolTip = makeTooltip(getText("UI_RPT_NoVehicleSources"))
        else
            for _, item in ipairs(sources) do
                local transfer = math.min(
                    Depot.getItemStoredUnits(item),
                    Depot.vehiclePropaneToDepotUnits(missing)
                )
                local remaining = Depot.getItemStoredUnits(item) - transfer
                local itemPercent = math.floor(
                    (remaining / Depot.getTargetFullCost(item)) * 100 + 0.5
                )
                local label = item:getDisplayName() .. " (" ..
                    Depot.formatPercent(item) .. "% -> " ..
                    tostring(itemPercent) .. "%)"
                local option = fillMenu:addOption(
                    label,
                    player,
                    queueVehicleTransfer,
                    vehicle,
                    part,
                    "item_to_vehicle",
                    item,
                    nil
                )
                option.toolTip = makeTooltip(
                    getText("UI_RPT_TransferAmount") .. ": " ..
                        Depot.formatAmount(transfer)
                )
            end
        end
    end
end

local function addDepotMenu(context, worldObjects, player, object)
    local stored = Depot.getStoredAmount(object)
    local capacity = Depot.getCapacity(object)
    local missingDepot = math.max(0, capacity - stored)
    local storageLabel
    if Depot.isInfinite() then
        storageLabel = getText("UI_RPT_Infinite")
    else
        storageLabel = Depot.formatAmount(stored) .. "/" ..
            Depot.formatAmount(capacity)
    end
    local rootLabel = getText("UI_RPT_Title") .. " (" ..
        storageLabel .. ")"
    local rootOption = context:addOptionOnTop(rootLabel, worldObjects, nil)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, submenu)

    local status = submenu:addOption(
        getText("UI_RPT_Storage") .. ": " ..
            storageLabel,
        nil,
        nil
    )
    status.notAvailable = true

    local refillOption = submenu:addOption(getText("UI_RPT_Refill"), nil, nil)
    local refillMenu = ISContextMenu:getNew(submenu)
    submenu:addSubMenu(refillOption, refillMenu)

    if stored <= Depot.MIN_TRANSFER then
        refillOption.notAvailable = true
        refillOption.toolTip = makeTooltip(getText("UI_RPT_Empty"))
    else
        local targets = getTargets(player)
        if #targets == 0 then
            refillOption.notAvailable = true
            refillOption.toolTip = makeTooltip(getText("UI_RPT_NoTargets"))
        else
            for _, item in ipairs(targets) do
                local missing = Depot.getMissingUnits(item)
                local transfer = math.min(missing, stored)
                local label = item:getDisplayName() .. " (" ..
                    Depot.formatPercent(item) .. "% -> " ..
                    tostring(math.floor(math.min(
                        1,
                        Depot.getTargetFraction(item) +
                            (transfer / Depot.getTargetFullCost(item))
                    ) * 100 + 0.5)) .. "%)"
                local option = refillMenu:addOption(
                    label,
                    object,
                    Client.queueRefill,
                    player,
                    item
                )
                option.toolTip = makeTooltip(
                    getText("UI_RPT_TransferAmount") .. ": " ..
                        Depot.formatAmount(transfer)
                )
                local icon = item:getIcon()
                if icon then option.iconTexture = icon:splitIcon() end
            end
        end
    end

    local storeItemOption = submenu:addOption(
        getText("UI_RPT_StoreItemInDepot"),
        nil,
        nil
    )
    local storeItemMenu = ISContextMenu:getNew(submenu)
    submenu:addSubMenu(storeItemOption, storeItemMenu)
    if missingDepot <= Depot.MIN_TRANSFER then
        storeItemOption.notAvailable = true
        storeItemOption.toolTip = makeTooltip(
            getText("UI_RPT_DepotAlreadyFull")
        )
    else
        local sources = getPropaneSources(player)
        if #sources == 0 then
            storeItemOption.notAvailable = true
            storeItemOption.toolTip = makeTooltip(
                getText("UI_RPT_NoItemSources")
            )
        else
            for _, item in ipairs(sources) do
                local available = Depot.getItemStoredUnits(item)
                local transfer = math.min(available, missingDepot)
                local remaining = math.max(0, available - transfer)
                local itemPercent = math.floor(
                    (remaining / Depot.getTargetFullCost(item)) * 100 + 0.5
                )
                local label = item:getDisplayName() .. " (" ..
                    Depot.formatPercent(item) .. "% -> " ..
                    tostring(itemPercent) .. "%)"
                local option = storeItemMenu:addOption(
                    label,
                    object,
                    Client.queueRefill,
                    player,
                    item,
                    "item_to_depot"
                )
                option.toolTip = makeTooltip(
                    getText("UI_RPT_TransferAmount") .. ": " ..
                        Depot.formatAmount(transfer)
                )
                local icon = item:getIcon()
                if icon then option.iconTexture = icon:splitIcon() end
            end
        end
    end

    local vehicleOption = submenu:addOption(
        getText("UI_RPT_RefillVehicleFromDepot"),
        nil,
        nil
    )
    local vehicleMenu = ISContextMenu:getNew(submenu)
    submenu:addSubMenu(vehicleOption, vehicleMenu)
    if stored <= Depot.MIN_TRANSFER then
        vehicleOption.notAvailable = true
        vehicleOption.toolTip = makeTooltip(getText("UI_RPT_Empty"))
    else
        local nearbyParts = findNearbyVehicleParts(object, function(part)
            return Depot.getVehiclePropaneMissingUnits(part) > Depot.MIN_TRANSFER
        end)
        if #nearbyParts == 0 then
            vehicleOption.notAvailable = true
            vehicleOption.toolTip = makeTooltip(
                getText("UI_RPT_NoNearbyVehicle")
            )
        else
            for _, entry in ipairs(nearbyParts) do
                local transfer = math.min(
                    stored,
                    Depot.vehiclePropaneToDepotUnits(
                        Depot.getVehiclePropaneMissingUnits(entry.part)
                    )
                )
                local option = vehicleMenu:addOption(
                    Depot.getPropaneVehicleLabel(entry.vehicle) .. " " ..
                    Depot.getFilibusterTankLabel(entry.part) .. " (" ..
                        getVehicleStorageLabel(entry.part) .. ")",
                    player,
                    queueVehicleTransfer,
                    entry.vehicle,
                    entry.part,
                    "depot_to_vehicle",
                    nil,
                    object
                )
                option.toolTip = makeTooltip(
                    getText("UI_RPT_TransferAmount") .. ": " ..
                        Depot.formatAmount(transfer)
                )
            end
        end
    end

    local storeVehicleOption = submenu:addOption(
        getText("UI_RPT_StoreVehicleInDepot"),
        nil,
        nil
    )
    local storeVehicleMenu = ISContextMenu:getNew(submenu)
    submenu:addSubMenu(storeVehicleOption, storeVehicleMenu)
    if missingDepot <= Depot.MIN_TRANSFER then
        storeVehicleOption.notAvailable = true
        storeVehicleOption.toolTip = makeTooltip(
            getText("UI_RPT_DepotAlreadyFull")
        )
    else
        local nearbySources = findNearbyVehicleParts(object, function(part)
            return Depot.getVehiclePropaneAmount(part) > Depot.MIN_TRANSFER
        end)
        if #nearbySources == 0 then
            storeVehicleOption.notAvailable = true
            storeVehicleOption.toolTip = makeTooltip(
                getText("UI_RPT_NoNearbyVehicleSources")
            )
        else
            for _, entry in ipairs(nearbySources) do
                local transfer = math.min(
                    missingDepot,
                    Depot.vehiclePropaneToDepotUnits(
                        Depot.getVehiclePropaneAmount(entry.part)
                    )
                )
                local option = storeVehicleMenu:addOption(
                    Depot.getPropaneVehicleLabel(entry.vehicle) .. " " ..
                    Depot.getFilibusterTankLabel(entry.part) .. " (" ..
                        getVehicleStorageLabel(entry.part) .. ")",
                    player,
                    queueVehicleTransfer,
                    entry.vehicle,
                    entry.part,
                    "vehicle_to_depot",
                    nil,
                    object
                )
                option.toolTip = makeTooltip(
                    getText("UI_RPT_TransferAmount") .. ": " ..
                        Depot.formatAmount(transfer)
                )
            end
        end
    end
end

function Client.onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end

    local object = Depot.findDepotInWorldObjects(worldObjects)
    object = object and Depot.resolveDepotObject(object) or nil
    if object then
        if test then return ISWorldObjectContextMenu.setTest() end
        return addDepotMenu(context, worldObjects, player, object)
    end

    local vehicle = findClickedVehicle(worldObjects)
    local parts = Depot.getFilibusterPropaneParts(vehicle)
    if #parts == 0 or not Depot.shouldOwnVehicleContextMenu(vehicle) then
        return
    end
    if test then return ISWorldObjectContextMenu.setTest() end
    for _, part in ipairs(parts) do
        addVehicleMenu(context, player, vehicle, part)
    end
end

local function findCommandPlayer(args)
    local onlineId = args and tonumber(args.playerOnlineId) or nil
    local requestedPlayerNum = args and tonumber(args.playerNum) or nil
    if requestedPlayerNum and requestedPlayerNum >= 0 and
        requestedPlayerNum < getNumActivePlayers() then
        local requestedPlayer = getSpecificPlayer(requestedPlayerNum)
        if requestedPlayer and
            (onlineId == nil or onlineId < 0 or
                requestedPlayer:getOnlineID() == onlineId) then
            return requestedPlayer
        end
    end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player and (onlineId == nil or player:getOnlineID() == onlineId) then
            return player
        end
    end
    return nil
end

function Client.receiveCommand(command, args)
    local player = findCommandPlayer(args)
    if not player then return end
    if command == "error" and args and args.key then
        player:setHaloNote(getText(tostring(args.key)))
    elseif command == "refilled" and args then
        player:setHaloNote(
            getText("UI_RPT_Refilled") .. " " ..
            tostring(args.itemName or "") .. " - " ..
            Depot.formatAmount(args.stored) .. "/" ..
            Depot.formatAmount(args.capacity)
        )
    elseif command == "vehicleUpdated" and args then
        player:setHaloNote(
            getText("UI_RPT_VehicleUpdated") .. " - " ..
            Depot.formatAmount(args.stored) .. "/" ..
            Depot.formatAmount(args.capacity)
        )
    elseif command == "depotUpdated" and args then
        player:setHaloNote(
            getText("UI_RPT_DepotUpdated") .. " - " ..
            Depot.formatAmount(args.stored) .. "/" ..
            Depot.formatAmount(args.capacity)
        )
    end
end

function Client.onServerCommand(module, command, args)
    if module ~= Depot.NET_MODULE then return end
    Client.receiveCommand(command, args)
end

Events.OnFillWorldObjectContextMenu.Add(Client.onFillWorldObjectContextMenu)
Events.OnServerCommand.Add(Client.onServerCommand)

return Client
