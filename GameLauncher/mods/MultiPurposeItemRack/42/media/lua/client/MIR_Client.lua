require "MIR_Core"
require "MIR_WallPlacement"
require "MIR_PegRenderer"

local MIR = MultiPurposeItemRack
MIR.Client = MIR.Client or {}
local Client = MIR.Client

local extendedPlacementPatched = false
local normalDropPatched = false

local function markExtendedPlacement(ui)
    local object = ui and ui.worlditem
    local item = MIR.itemFromWorldObject(object)
    if not object or not item then return end
    object:setExtendedPlacement(true)
    item:getModData().MIRExtendedPlaced = true
    item:getModData().MIRPlacementMarker = 2
end

local function patchExtendedPlacementUI()
    if extendedPlacementPatched then return end
    if not ISExtendedPlacementUI then
        pcall(require, "ISUI/ISExtendedPlacementUI")
    end
    if not ISExtendedPlacementUI then return end

    local function wrap(method)
        local original = ISExtendedPlacementUI[method]
        if not original then return end
        ISExtendedPlacementUI[method] = function(self, ...)
            local result = original(self, ...)
            markExtendedPlacement(self)
            return result
        end
    end

    wrap("onAxisTextChange")
    wrap("onRotateGizmo")
    wrap("onTranslateGizmo")
    local originalClose = ISExtendedPlacementUI.close
    if originalClose then
        ISExtendedPlacementUI.close = function(self, ...)
            markExtendedPlacement(self)
            return originalClose(self, ...)
        end
    end
    extendedPlacementPatched = true
end

Events.OnGameStart.Add(patchExtendedPlacementUI)

local function patchNormalDropAction()
    if normalDropPatched then return end
    if not ISDropWorldItemAction then
        pcall(require, "TimedActions/ISDropWorldItemAction")
    end
    if not ISDropWorldItemAction or not ISDropWorldItemAction.perform then return end

    local original = ISDropWorldItemAction.perform
    ISDropWorldItemAction.perform = function(self, ...)
        local item = self and self.item or nil
        if item then
            local data = item:getModData()
            data.MIRExtendedPlaced = nil
            data.MIRPlacementMarker = nil
            data.MIRSlotId = nil
        end
        return original(self, ...)
    end
    normalDropPatched = true
end

Events.OnGameStart.Add(patchNormalDropAction)

local function tooltip(option, titleKey, descriptionKey)
    if not option then return end
    option.toolTip = ISToolTip:new()
    option.toolTip:initialise()
    option.toolTip:setVisible(false)
    option.toolTip:setName(getText(titleKey))
    option.toolTip.description = getText(descriptionKey)
end

local function rackArgs(rack)
    local square = rack:getSquare()
    return {
        rackX = square:getX(), rackY = square:getY(), rackZ = square:getZ(),
        rackItemId = MIR.worldItemId(rack),
    }
end

local function command(player, name, args)
    if isClient() then
        sendClientCommand(player, MIR.module, name, args)
    elseif MIR.Server and MIR.Server.handle then
        MIR.Server.handle(name, player, args)
    end
end

function Client.requestRackState(rack, player)
    if not rack or not rack:getSquare() then return end
    player = player or getPlayer()
    if player then command(player, "getRackState", rackArgs(rack)) end
end

local function findRack(worldObjects)
    local seen = {}
    for _, clicked in ipairs(worldObjects) do
        local square = clicked and clicked:getSquare()
        if square then
            local key = MIR.squareKey(square:getX(), square:getY(), square:getZ())
            if not seen[key] then
                seen[key] = true
                local found = nil
                MIR.eachWorldItem(square, function(object)
                    if not found and MIR.isRackWorldObject(object) then found = object end
                end)
                if found then return found end
            end
        end
    end
    return nil
end

local function nearbyItems(rack)
    local result, seen = {}, {}
    local origin = rack:getSquare()
    local radius = MIR.captureRange
    local rackSlots = {}
    for _, linkedRack in ipairs(MIR.collectAdjacentRacks(rack)) do
        local rackData = MIR.ensureRackData(linkedRack:getItem())
        for _, slot in ipairs(rackData and rackData.slots or {}) do
            rackSlots[tostring(slot.id)] = true
        end
    end
    for z = origin:getZ(), origin:getZ() do
        for x = origin:getX() - radius, origin:getX() + radius do
            for y = origin:getY() - radius, origin:getY() + radius do
                local square = getCell():getGridSquare(x, y, z)
                if square then
                    MIR.eachWorldItem(square, function(object, item)
                        local key = MIR.worldItemKey(object, item)
                        local remembered = item:getModData().MIRSlotId
                        if object ~= rack and MIR.isExtendedPlacedWorldItem(object) and not seen[key]
                            and not rackSlots[tostring(remembered)]
                            and not MIR.isRackItem(item) then
                            local rackPose, itemPose = MIR.pose(rack), MIR.pose(object)
                            if rackPose and itemPose then
                                local dx, dy = itemPose.x - rackPose.x, itemPose.y - rackPose.y
                                if dx * dx + dy * dy <= radius * radius then
                                    seen[key] = true
                                    result[#result + 1] = object
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
    table.sort(result, function(a, b)
        return MIR.itemName(a:getItem()) < MIR.itemName(b:getItem())
    end)
    return result
end

local function targetArgs(target)
    local args = {}
    local square = target:getSquare()
    args.targetX = square:getX()
    args.targetY = square:getY()
    args.targetZ = square:getZ()
    args.targetItemId = MIR.worldItemId(target)
    args.extendedPlaced = MIR.isExtendedPlacedWorldItem(target)
    local pose = MIR.pose(target)
    if pose then
        args.poseX, args.poseY, args.poseZ = pose.x, pose.y, pose.z
        args.targetRotX, args.targetRotY, args.targetRotZ = pose.rotX, pose.rotY, pose.rotZ
    end
    return args
end

local function capture(player, rack, target, rule)
    local args = rackArgs(rack)
    local target = targetArgs(target)
    for key, value in pairs(target) do args[key] = value end
    args.rule = rule
    command(player, "capture", args)
end

local function captureAll(player, rack, items)
    local args = rackArgs(rack)
    args.targets = {}
    for _, target in ipairs(items or {}) do
        args.targets[#args.targets + 1] = targetArgs(target)
    end
    command(player, "captureAll", args)
end

local function forget(player, rack, slotId)
    local args = rackArgs(rack)
    args.slotId = slotId
    command(player, "forget", args)
end

local function removeAll(player, rack)
    command(player, "removeAll", rackArgs(rack))
end

local function restock(player, rack)
    command(player, "restock", rackArgs(rack))
end

local function removeRack(player, rack)
    command(player, "removeRack", rackArgs(rack))
end

local applyBoardVisibility

local function setVisibility(player, rack, target, hidden)
    local args = rackArgs(rack)
    args.target = target
    args.hidden = hidden == true
    command(player, "setVisibility", args)
    if not isClient() and applyBoardVisibility then
        for _, linkedRack in ipairs(MIR.collectAdjacentRacks(rack)) do
            applyBoardVisibility(linkedRack)
        end
    end
end

applyBoardVisibility = function(rack)
    local item = MIR.itemFromWorldObject(rack)
    local data = item and MIR.ensureRackData(item) or nil
    if not rack or not data then return end
    -- The logical rack carrier is always hidden. MIR_PegRenderer draws the
    -- visible board independently and can therefore show/hide it immediately
    -- without swapping a cached world-item model.
    MIR.hideRackCarrier(item)
    for playerNumber = 0, getNumActivePlayers() - 1 do
        if rack.setAlpha then
            pcall(function() rack:setAlpha(playerNumber, 1) end)
        end
        if rack.setTargetAlpha then
            pcall(function() rack:setTargetAlpha(playerNumber, 1) end)
        end
    end
end

Client.applyBoardVisibility = applyBoardVisibility

local function addCaptureMenu(menu, player, rack)
    local items = nearbyItems(rack)
    if #items == 0 then
        local disabled = menu:addOption(getText("IGUI_MIR_NoItems"), nil, nil)
        disabled.notAvailable = true
        return
    end


    local allOption = menu:addOption(getText("IGUI_MIR_AllNearbyItems"), player,
        captureAll, rack, items)
    tooltip(allOption, "IGUI_MIR_AllNearbyItems", "IGUI_MIR_AllNearbyItemsTooltip")

    for _, target in ipairs(items) do
        local itemOption = menu:addOption(MIR.itemName(target:getItem()), nil, nil)
        ISWorldObjectContextMenu.initWorldItemHighlightOption(itemOption, target)
        local itemMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(itemOption, itemMenu)
        for _, rule in ipairs(MIR.availableRules(target:getItem())) do
            itemMenu:addOption(MIR.ruleName(rule), player, capture, rack, target, rule)
        end
    end
end

local function addForgetMenu(menu, player, rack)
    local slots = {}
    for _, linkedRack in ipairs(MIR.collectAdjacentRacks(rack)) do
        local data = MIR.ensureRackData(linkedRack:getItem())
        for _, slot in ipairs(data and data.slots or {}) do
            slots[#slots + 1] = slot
        end
    end
    table.sort(slots, function(a, b)
        local at, bt = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
        if at ~= bt then return at < bt end
        return tostring(a.id) < tostring(b.id)
    end)
    if #slots == 0 then
        local disabled = menu:addOption(getText("IGUI_MIR_NoSlots"), nil, nil)
        disabled.notAvailable = true
        return
    end

    local allOption = menu:addOption(getText("IGUI_MIR_RemoveAll"), player, removeAll, rack)
    tooltip(allOption, "IGUI_MIR_RemoveAll", "IGUI_MIR_RemoveAllTooltip")
    local totals, indexes = {}, {}
    for _, slot in ipairs(slots) do
        local label = MIR.slotLabel(slot)
        totals[label] = (totals[label] or 0) + 1
    end
    for _, slot in ipairs(slots) do
        local label = MIR.slotLabel(slot)
        if totals[label] > 1 then
            indexes[label] = (indexes[label] or 0) + 1
            label = label .. " (" .. tostring(indexes[label]) .. ")"
        end
        menu:addOption(label, player, forget, rack, slot.id)
    end
end

local function onContextMenu(playerNumber, context, worldObjects, test)
    local rack = findRack(worldObjects)
    if not rack then return end
    if test then return ISWorldObjectContextMenu.setTest() end

    local player = getSpecificPlayer(playerNumber)
    if not player then return end
    Client.requestRackState(rack, player)

    local rootOption = context:addOption(getText("IGUI_MIR_RackMenu"), nil, nil)
    local root = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, root)

    local restockOption = root:addOption(getText("IGUI_MIR_Restock"), player, restock, rack)
    tooltip(restockOption, "IGUI_MIR_Restock", "IGUI_MIR_RestockTooltip")

    local rememberOption = root:addOption(getText("IGUI_MIR_Remember"), nil, nil)
    local rememberMenu = ISContextMenu:getNew(root)
    root:addSubMenu(rememberOption, rememberMenu)
    addCaptureMenu(rememberMenu, player, rack)

    local forgetOption = root:addOption(getText("IGUI_MIR_Forget"), nil, nil)
    local forgetMenu = ISContextMenu:getNew(root)
    root:addSubMenu(forgetOption, forgetMenu)
    addForgetMenu(forgetMenu, player, rack)

    local data = MIR.ensureRackData(rack:getItem())
    local boardVisible = not (data and data.boardHidden == true)
    local boardOption = root:addOption(getText("IGUI_MIR_ShowBoard"), player,
        setVisibility, rack, "board", boardVisible)
    boardOption.checkMark = boardVisible
    tooltip(boardOption, "IGUI_MIR_ShowBoard", "IGUI_MIR_ShowBoardTooltip")

    local pegsVisible = not (data and data.pegsHidden == true)
    local pegsOption = root:addOption(getText("IGUI_MIR_ShowPegs"), player,
        setVisibility, rack, "pegs", pegsVisible)
    pegsOption.checkMark = pegsVisible
    tooltip(pegsOption, "IGUI_MIR_ShowPegs", "IGUI_MIR_ShowPegsTooltip")

    local removeOption = root:addOption(getText("IGUI_MIR_RemoveRack"), player, removeRack, rack)
    tooltip(removeOption, "IGUI_MIR_RemoveRack", "IGUI_MIR_RemoveRackTooltip")
end

local function unwrapInventoryItems(items)
    local result, seen = {}, {}
    for _, selected in ipairs(items or {}) do
        if instanceof(selected, "InventoryItem") then
            if not seen[selected] then result[#result + 1], seen[selected] = selected, true end
        elseif selected and selected.items then
            for _, item in ipairs(selected.items) do
                if not seen[item] then result[#result + 1], seen[item] = item, true end
            end
        end
    end
    return result
end

local function beginWallInstall(player, item)
    if not player or not item or not MIR.isRackItem(item) then return end
    local cursor = MIR.createWallRackCursor and MIR.createWallRackCursor(player, item) or nil
    if cursor then
        getCell():setDrag(cursor, player:getPlayerNum())
    else
        HaloTextHelper.addText(player, getText("IGUI_MIR_InstallUnavailable"))
    end
end

local function onInventoryContextMenu(playerNumber, context, items)
    local player = getSpecificPlayer(playerNumber)
    if not player then return end
    local rackSelected = false
    for _, item in ipairs(unwrapInventoryItems(items)) do
        if MIR.isRackItem(item) and item:getContainer() then
            rackSelected = true
            local option = context:addOption(getText("IGUI_MIR_Install"), player, beginWallInstall, item)
            tooltip(option, "IGUI_MIR_Install", "IGUI_MIR_InstallTooltip")
            break
        end
    end
    if not rackSelected then return end

    -- These are generic InventoryItem actions. Removing their menu rows only for
    -- the rack keeps installation focused without changing the underlying item
    -- methods or any base-game action used by other objects.
    local hiddenLabels = {
        [string.lower(getText("ContextMenu_Equip_Primary"))] = true,
        [string.lower(getText("ContextMenu_Equip_Secondary"))] = true,
        [string.lower(getText("ContextMenu_PlaceItem"))] = true,
        ["equip primary"] = true,
        ["equip secondary"] = true,
        ["place item"] = true,
    }
    for index = #(context.options or {}), 1, -1 do
        local option = context.options[index]
        local label = string.lower(tostring(option and option.name or ""))
        if hiddenLabels[label] then table.remove(context.options, index) end
    end
end

local function applyRackState(args)
    local rack = MIR.findWorldItem(args.rackX, args.rackY, args.rackZ, args.rackItemId)
    if not MIR.isRackWorldObject(rack) then return end
    local data = MIR.ensureRackData(rack:getItem())
    data.wallSide = args.wallSide
    data.boardHidden = args.boardHidden == true
    data.pegsHidden = args.pegsHidden == true
    data.slots = {}
    for _, slot in ipairs(args.slots or {}) do
        data.slots[#data.slots + 1] = {
            id = tostring(slot.id), rule = tostring(slot.rule),
            preferredFullType = tostring(slot.preferredFullType),
            preferredName = tostring(slot.preferredName),
            createdAt = tonumber(slot.createdAt) or 0,
            localX = tonumber(slot.localX) or 0,
            localY = tonumber(slot.localY) or 0,
            localZ = tonumber(slot.localZ) or 0,
            rotX = tonumber(slot.rotX) or 0,
            rotY = tonumber(slot.rotY) or 0,
            rotZ = tonumber(slot.rotZ) or 0,
            pegCount = MIR.slotPegCount(slot),
        }
    end
    applyBoardVisibility(rack)
end

local function clearInventoryRackData()
    for playerNumber = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNumber)
        local inventory = player and player:getInventory() or nil
        if inventory then
            local function scan(container)
                local contents = container:getItems()
                for index = 0, contents:size() - 1 do
                    local item = contents:get(index)
                    if MIR.isRackItem(item) then
                        -- Local cleanup only. syncItemFields on a freshly moved
                        -- world item produces a null-item packet in Build 42.
                        MIR.resetRackData(item)
                    end
                    local nested = item.getInventory and item:getInventory() or nil
                    if nested then scan(nested) end
                end
            end
            scan(inventory)
        end
    end
end

local function removeLocalRack(args)
    local rack = MIR.findWorldItem(args.rackX, args.rackY, args.rackZ, args.rackItemId)
    if not rack or not rack:getSquare() then return end
    local square = rack:getSquare()
    triggerEvent("OnObjectAboutToBeRemoved", rack)
    square:removeWorldObject(rack)
end

local function onServerCommand(module, commandName, args)
    if module ~= MIR.module then return end
    local player = getSpecificPlayer(tonumber(args.playerNumber) or 0)
    if commandName == "rackState" then
        applyRackState(args)
    elseif commandName == "rackRemoved" then
        removeLocalRack(args)
    elseif commandName == "feedback" and player and args.key then
        local text = args.value == nil and getText(tostring(args.key))
            or getText(tostring(args.key), tostring(args.value))
        HaloTextHelper.addText(player, text)
    end
end

local function hideInstalledRackFromGround(page, phase)
    if phase ~= "beforeFloor" or not page or page.onCharacter then return end
    local floor = ISInventoryPage.GetFloorContainer(page.player)
    if not floor then return end

    -- The floor container is rebuilt solely for the nearby-inventory window.
    -- Removing the installed rack from this temporary list does not move or
    -- modify its real world object. Uninstalled rack items remain visible.
    local items = floor:getItems()
    for index = items:size() - 1, 0, -1 do
        local item = items:get(index)
        if MIR.isRackItem(item) then
            local root = item:getModData()
            local data = root and root.MIR or nil
            if type(data) == "table" and data.wallSide ~= nil then
                floor:DoRemoveItem(item)
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onInventoryContextMenu)
Events.OnServerCommand.Add(onServerCommand)
Events.OnContainerUpdate.Add(clearInventoryRackData)
Events.OnRefreshInventoryWindowContainers.Add(hideInstalledRackFromGround)
