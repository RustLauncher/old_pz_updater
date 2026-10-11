require "MIR_Core"

local MIR = MultiPurposeItemRack
MIR.Server = MIR.Server or {}
local Server = MIR.Server

local rates = {}

local function playerId(player)
    if not player then return nil end
    local id = tonumber(player:getOnlineID())
    if id and id >= 0 then return tostring(id) end
    return tostring(player:getUsername() or player)
end

local function rateAllowed(player)
    local id = playerId(player)
    if not id then return false end
    local now = getTimestampMs()
    local state = rates[id]
    if not state or now - state.startedAt > 1000 then
        rates[id] = { startedAt = now, count = 1 }
        return true
    end
    state.count = state.count + 1
    return state.count <= 5
end

local function feedback(player, key, value)
    if isServer() then
        sendServerCommand(player, MIR.module, "feedback", {
            playerNumber = player:getPlayerNum(), key = key, value = value,
        })
    else
        local text = value == nil and getText(key) or getText(key, tostring(value))
        HaloTextHelper.addText(player, text)
    end
end

local function syncWorldItem(worldObject)
    if not worldObject then return end
    if worldObject.transmitCompleteItemToClients then
        pcall(function() worldObject:transmitCompleteItemToClients() end)
    end
end

local function placeWorldItem(player, item, pose, slotId, isRack, wallSide)
    if not player or not item or not pose then return false end
    local x, y, z = tonumber(pose.x), tonumber(pose.y), tonumber(pose.z)
    if not x or not y or not z then return false end
    local squareX, squareY, squareZ = math.floor(x), math.floor(y), math.floor(z)
    local square = getCell():getGridSquare(squareX, squareY, squareZ)
    local container = item:getContainer()
    if not square or not container then return false end

    if isRack == true then
        MIR.resetRackData(item)
        MIR.ensureRackData(item).wallSide = tostring(wallSide or "north")
        MIR.hideRackCarrier(item)
    end
    local itemData = item:getModData()
    itemData.MIRSlotId = slotId
    itemData.MIRExtendedPlaced = true

    -- The server owns the complete transfer. Clients never create, delete or
    -- rotate a world item for automatic placement, so its ID is immediately
    -- valid for normal multiplayer pickup.
    container:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(container, item) end
    local placedItem = square:AddWorldInventoryItem(item,
        x - squareX, y - squareY, z - squareZ, false)
    local worldObject = placedItem and placedItem:getWorldItem() or nil
    if not placedItem or not worldObject then
        container:AddItem(item)
        if isServer() then sendAddItemToContainer(container, item) end
        return false
    end

    placedItem:setWorldXRotation(tonumber(pose.rotX) or 0)
    placedItem:setWorldYRotation(tonumber(pose.rotY) or 0)
    placedItem:setWorldZRotation(tonumber(pose.rotZ) or 0)
    worldObject:setExtendedPlacement(true)
    syncWorldItem(worldObject)
    return true
end

local function broadcast(command, args)
    if not isServer() then return end
    local players = getOnlinePlayers()
    for index = 0, players:size() - 1 do
        sendServerCommand(players:get(index), MIR.module, command, args)
    end
end

local function copySlots(data)
    local result = {}
    for _, slot in ipairs(data and data.slots or {}) do
        result[#result + 1] = {
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
    return result
end

local function rackStateArgs(rack)
    local square = rack and rack:getSquare() or nil
    local item = MIR.itemFromWorldObject(rack)
    local data = item and MIR.ensureRackData(item) or nil
    if not square or not data then return nil end
    return {
        rackX = square:getX(), rackY = square:getY(), rackZ = square:getZ(),
        rackItemId = MIR.worldItemId(rack), wallSide = data.wallSide,
        boardHidden = data.boardHidden == true,
        pegsHidden = data.pegsHidden == true,
        slots = copySlots(data),
    }
end

local function sendRackState(player, rack)
    local args = rackStateArgs(rack)
    if not args then return end
    if isServer() then
        if player then sendServerCommand(player, MIR.module, "rackState", args)
        else broadcast("rackState", args) end
    end
end

local function resolveRack(args)
    if type(args) ~= "table" then return nil end
    local rack = MIR.findWorldItem(args.rackX, args.rackY, args.rackZ, args.rackItemId)
    return MIR.isRackWorldObject(rack) and rack or nil
end

local function findInventoryItem(container, wantedId)
    if not container then return nil end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if MIR.itemId(item) == tonumber(wantedId) then return item end
        local nested = item.getInventory and item:getInventory() or nil
        local found = nested and findInventoryItem(nested, wantedId) or nil
        if found then return found end
    end
    return nil
end

local function near(player, worldObject, maximum)
    return player and worldObject and worldObject:getSquare()
        and MIR.distanceSquared(player:getSquare(), worldObject:getSquare()) <= maximum * maximum
end

local function install(player, args)
    if type(args) ~= "table" then return end
    local square = getCell():getGridSquare(tonumber(args.x), tonumber(args.y), tonumber(args.z))
    local sideIndexes = { west = 1, north = 2, east = 3, south = 4 }
    local sideIndex = sideIndexes[tostring(args.side)]
    local side = sideIndex and MIR.wallSide(square, sideIndex) or nil
    local playerSquare = player and player:getSquare()
    if not square or side ~= args.side or not playerSquare
        or MIR.distanceSquared(playerSquare, square) > 16 then
        feedback(player, "IGUI_MIR_InstallFailed")
        return
    end

    local item = findInventoryItem(player:getInventory(), args.rackItemId)
    local container = item and item:getContainer() or nil
    local pose = MIR.wallPose(square, side)
    if not MIR.isRackItem(item) or not container or not pose then
        feedback(player, "IGUI_MIR_InstallFailed")
        return
    end


    -- A removed rack never carries its old slots into a new installation.
    MIR.resetRackData(item)
    MIR.ensureRackData(item).wallSide = side

    local occupied = false
    MIR.eachWorldItem(square, function(object)
        if MIR.isRackWorldObject(object) then
            local current = MIR.pose(object)
            if current then
                local dx, dy, dz = current.x - pose.x, current.y - pose.y, current.z - pose.z
                if dx * dx + dy * dy + dz * dz < 0.02 then occupied = true end
            end
        end
    end)
    if occupied then
        feedback(player, "IGUI_MIR_InstallFailed")
        return
    end

    if not placeWorldItem(player, item, pose, nil, true, side) then
        feedback(player, "IGUI_MIR_InstallFailed")
        return
    end

    local installed = MIR.findWorldItem(square:getX(), square:getY(), square:getZ(),
        MIR.itemId(item))
    if installed then
        local installedData = MIR.ensureRackData(installed:getItem())
        for _, linkedRack in ipairs(MIR.collectAdjacentRacks(installed)) do
            if linkedRack ~= installed then
                local linkedData = MIR.ensureRackData(linkedRack:getItem())
                installedData.boardHidden = linkedData.boardHidden == true
                installedData.pegsHidden = linkedData.pegsHidden == true
                break
            end
        end
        sendRackState(nil, installed)
    end
    feedback(player, "IGUI_MIR_Installed")
end

local function slotId(rack, target)
    return tostring(MIR.worldItemId(rack)) .. "-" .. tostring(getTimestampMs())
        .. "-" .. tostring(MIR.worldItemId(target))
end

local findOccupant

local function captureTarget(player, rack, args)
    local target = MIR.findWorldItem(args.targetX, args.targetY, args.targetZ, args.targetItemId)
    if not target or MIR.isRackWorldObject(target) or not MIR.validRule(args.rule) then return false end
    if rack:getSquare():getZ() ~= target:getSquare():getZ() then return false end
    if args.extendedPlaced ~= true then return false end
    local rackPose, targetPose = MIR.pose(rack), MIR.pose(target)
    if not rackPose or not targetPose then return false end
    local dx, dy = targetPose.x - rackPose.x, targetPose.y - rackPose.y
    if dx * dx + dy * dy > MIR.captureRange ^ 2 then return false end

    local serverPose = MIR.pose(target)
    local clientPose = {
        x = tonumber(args.poseX), y = tonumber(args.poseY), z = tonumber(args.poseZ),
        rotX = tonumber(args.targetRotX), rotY = tonumber(args.targetRotY),
        rotZ = tonumber(args.targetRotZ),
    }
    if not clientPose.x or not clientPose.y or not clientPose.z then clientPose = serverPose end
    if not clientPose or not serverPose then return false end
    local poseErrorX, poseErrorY = clientPose.x - serverPose.x, clientPose.y - serverPose.y
    if poseErrorX * poseErrorX + poseErrorY * poseErrorY > 1
        or math.abs(clientPose.z - serverPose.z) > 2 then return false end
    clientPose.rotX = clientPose.rotX or serverPose.rotX
    clientPose.rotY = clientPose.rotY or serverPose.rotY
    clientPose.rotZ = clientPose.rotZ or serverPose.rotZ

    -- Extended 3D rotation updates can be rejected by B42 before this command
    -- reaches the server. Capture the validated owning client's exact pose so
    -- restocking does not save the server's stale default rotation.
    local relative = MIR.captureRelativeValues(rack, clientPose)
    if not relative then return false end
    local item = target:getItem()
    local data = MIR.ensureRackData(rack:getItem())
    local remembered = item:getModData().MIRSlotId
    if remembered then
        for _, linkedRack in ipairs(MIR.collectAdjacentRacks(rack)) do
            local linkedData = MIR.ensureRackData(linkedRack:getItem())
            for _, existing in ipairs(linkedData.slots) do
                if tostring(existing.id) == tostring(remembered) then return false end
            end
        end
    end
    local id = slotId(rack, target)
    relative.id = id
    relative.rule = args.rule
    relative.preferredFullType = item:getFullType()
    relative.preferredName = MIR.itemName(item)
    relative.createdAt = getTimestampMs()
    relative.pegCount = MIR.isHandgun(item) and 1 or 2
    data.slots[#data.slots + 1] = relative
    item:getModData().MIRSlotId = id

    return true, MIR.itemName(item)
end

local function capture(player, args)
    local rack = resolveRack(args)
    if not rack or not near(player, rack, 4) then
        feedback(player, "IGUI_MIR_TooFar")
        return
    end
    local captured, name = captureTarget(player, rack, args)
    if not captured then return end

    sendRackState(nil, rack)
    feedback(player, "IGUI_MIR_Captured", name)
end

local function captureAll(player, args)
    local rack = resolveRack(args)
    if not rack or not near(player, rack, 4) then
        feedback(player, "IGUI_MIR_TooFar")
        return
    end
    local count, seen = 0, {}
    for _, target in ipairs(args.targets or {}) do
        local id = tostring(target.targetItemId)
        if not seen[id] and count < 100 then
            seen[id] = true
            target.rule = "exact"
            if captureTarget(player, rack, target) then count = count + 1 end
        end
    end
    if count > 0 then sendRackState(nil, rack) end
    feedback(player, "IGUI_MIR_CapturedAll", count)
end

local function forget(player, args)
    local rack = resolveRack(args)
    if not rack or not near(player, rack, 4) then return end
    for _, owner in ipairs(MIR.collectAdjacentRacks(rack)) do
        local data = MIR.ensureRackData(owner:getItem())
        for index = #data.slots, 1, -1 do
            if tostring(data.slots[index].id) == tostring(args.slotId) then
                local occupant = findOccupant and findOccupant(data.slots[index], owner) or nil
                local item = MIR.itemFromWorldObject(occupant)
                if item then
                    item:getModData().MIRSlotId = nil
                    syncWorldItem(occupant)
                end
                table.remove(data.slots, index)
                sendRackState(nil, owner)
                feedback(player, "IGUI_MIR_Removed")
                return
            end
        end
    end
end

local function getRackState(player, args)
    local rack = resolveRack(args)
    if rack and near(player, rack, 30) then
        for _, linkedRack in ipairs(MIR.collectAdjacentRacks(rack)) do
            sendRackState(player, linkedRack)
        end
    end
end

local visibilityFields = {
    board = "boardHidden",
    pegs = "pegsHidden",
}

local function setVisibility(player, args)
    local rack = resolveRack(args)
    if not rack or not near(player, rack, 4) then
        feedback(player, "IGUI_MIR_TooFar")
        return
    end

    local field = visibilityFields[tostring(args.target or "")]
    if not field then return end
    for _, linkedRack in ipairs(MIR.collectAdjacentRacks(rack)) do
        local item = linkedRack:getItem()
        local data = MIR.ensureRackData(item)
        data[field] = args.hidden == true

        -- Keep every authoritative carrier hidden. Clients render the board as
        -- a separate visual and receive one compact state update per section.
        if field == "boardHidden" then MIR.hideRackCarrier(item) end
        sendRackState(nil, linkedRack)
    end
end

local function removeRack(player, args)
    local rack = resolveRack(args)
    if not rack or not near(player, rack, 4) then
        feedback(player, "IGUI_MIR_TooFar")
        return
    end

    local square = rack:getSquare()
    local inventory = player:getInventory()
    local replacement = instanceItem(MIR.rackType)
    if not square or not inventory or not replacement then
        feedback(player, "IGUI_MIR_RemoveFailed")
        return
    end

    -- Return a clean inventory item rather than transferring the wall object.
    -- This prevents stale world IDs and guarantees that only this rack's slots
    -- are reset; linked racks are separate items and remain untouched.
    MIR.resetRackData(replacement)
    inventory:AddItem(replacement)
    sendAddItemToContainer(inventory, replacement)
    triggerEvent("OnObjectAboutToBeRemoved", rack)
    square:transmitRemoveItemFromSquare(rack)
    square:removeWorldObject(rack)
    broadcast("rackRemoved", {
        rackX = args.rackX, rackY = args.rackY, rackZ = args.rackZ,
        rackItemId = args.rackItemId,
    })
    feedback(player, "IGUI_MIR_RackRemoved")
end

local function allInventoryItems(container, result, seen)
    if not container then return end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local id = tostring(MIR.itemId(item))
        if not seen[id] then
            seen[id] = true
            result[#result + 1] = item
            local nested = item.getInventory and item:getInventory() or nil
            if nested then allInventoryItems(nested, result, seen) end
        end
    end
end

findOccupant = function(slot, rackWorld)
    local pose = MIR.restorePose(rackWorld, slot)
    if not pose then return nil end
    local baseX, baseY, baseZ = math.floor(pose.x), math.floor(pose.y), math.floor(pose.z)
    -- Basements use negative Z levels. Clamping this search to zero makes
    -- every basement slot appear empty and lets restock overlap an occupant.
    for z = baseZ - 1, baseZ + 1 do
        for x = baseX - 1, baseX + 1 do
            for y = baseY - 1, baseY + 1 do
                local square = getCell():getGridSquare(x, y, z)
                if square then
                    local occupant = nil
                    MIR.eachWorldItem(square, function(object, item)
                        if occupant then return end
                        if item and item:getModData().MIRSlotId == slot.id then
                            occupant = object
                            return
                        end
                        if item and MIR.matches(item, slot) then
                            local current = MIR.pose(object)
                            local dx, dy, dz = current.x - pose.x, current.y - pose.y, current.z - pose.z
                            if dx * dx + dy * dy + dz * dz < 0.01 then occupant = object end
                        end
                    end)
                    if occupant then return occupant end
                end
            end
        end
    end
    return nil
end

local function occupied(slot, rackWorld)
    return findOccupant(slot, rackWorld) ~= nil
end

local function takeDisplayedItem(player, worldObject)
    local item = MIR.itemFromWorldObject(worldObject)
    local square = worldObject and worldObject:getSquare() or nil
    local inventory = player and player:getInventory() or nil
    if not item or not square or not inventory then return false end

    item:getModData().MIRSlotId = nil
    triggerEvent("OnObjectAboutToBeRemoved", worldObject)
    square:transmitRemoveItemFromSquare(worldObject)
    square:removeWorldObject(worldObject)
    if item.setWorldItem then item:setWorldItem(nil) end
    inventory:AddItem(item)
    if isServer() then sendAddItemToContainer(inventory, item) end
    return true
end

local function removeAll(player, args)
    local rack = resolveRack(args)
    if not rack or not near(player, rack, 4) then
        feedback(player, "IGUI_MIR_TooFar")
        return
    end

    local count, seen = 0, {}
    local linkedRacks = MIR.collectAdjacentRacks(rack)
    for _, owner in ipairs(linkedRacks) do
        local data = MIR.ensureRackData(owner:getItem())
        for _, slot in ipairs(data.slots) do
            local occupant = findOccupant(slot, owner)
            local id = occupant and tostring(MIR.worldItemId(occupant)) or nil
            if occupant and not seen[id] then
                seen[id] = true
                if takeDisplayedItem(player, occupant) then count = count + 1 end
            end
        end
    end
    for _, owner in ipairs(linkedRacks) do
        MIR.ensureRackData(owner:getItem()).slots = {}
        sendRackState(nil, owner)
    end
    feedback(player, "IGUI_MIR_RemovedAll", count)
end

local function usable(player, item)
    if not item or MIR.isRackItem(item) then return false end
    if item:isFavorite() then return false end
    if player.isEquipped and player:isEquipped(item) then return false end
    return item:getContainer() ~= nil
end

local function chooseItem(player, inventoryItems, used, slot)
    local preferred, category = nil, nil
    for _, item in ipairs(inventoryItems) do
        local id = tostring(MIR.itemId(item))
        if not used[id] and usable(player, item) and MIR.matches(item, slot) then
            if item:getFullType() == slot.preferredFullType then
                preferred = item
                break
            elseif not category then
                category = item
            end
        end
    end
    return preferred or category
end

local function placeItem(player, item, rackWorld, slot)
    local pose = MIR.restorePose(rackWorld, slot)
    if not pose then return false end
    local squareX, squareY, squareZ = math.floor(pose.x), math.floor(pose.y), math.floor(pose.z)
    local square = getCell():getGridSquare(squareX, squareY, squareZ)
    local container = item:getContainer()
    if not square or not container then return false end

    return placeWorldItem(player, item, pose, slot.id, false)
end

local function restock(player, args)
    local selected = resolveRack(args)
    if not selected or not near(player, selected, 4) then
        feedback(player, "IGUI_MIR_TooFar")
        return
    end

    local racks = MIR.collectAdjacentRacks(selected)
    local slots = {}
    for _, rack in ipairs(racks) do
        local data = MIR.ensureRackData(rack:getItem())
        for _, slot in ipairs(data.slots) do
            slots[#slots + 1] = { rack = rack, slot = slot }
        end
    end
    table.sort(slots, function(a, b)
        local ar, br = MIR.ruleRank(a.slot.rule), MIR.ruleRank(b.slot.rule)
        if ar ~= br then return ar < br end
        return (a.slot.createdAt or 0) < (b.slot.createdAt or 0)
    end)

    local inventoryItems = {}
    allInventoryItems(player:getInventory(), inventoryItems, {})
    local used, count = {}, 0
    for _, entry in ipairs(slots) do
        if not occupied(entry.slot, entry.rack) then
            local item = chooseItem(player, inventoryItems, used, entry.slot)
            if item then
                local id = tostring(MIR.itemId(item))
                if placeItem(player, item, entry.rack, entry.slot) then
                    used[id] = true
                    count = count + 1
                end
            end
        end
    end
    feedback(player, "IGUI_MIR_Restocked", count)
end

function Server.handle(command, player, args)
    if not player then return end
    if command ~= "getRackState" and not rateAllowed(player) then return end
    if command == "install" then install(player, args)
    elseif command == "capture" then capture(player, args)
    elseif command == "captureAll" then captureAll(player, args)
    elseif command == "forget" then forget(player, args)
    elseif command == "removeAll" then removeAll(player, args)
    elseif command == "getRackState" then getRackState(player, args)
    elseif command == "setVisibility" then setVisibility(player, args)
    elseif command == "removeRack" then removeRack(player, args)
    elseif command == "restock" then restock(player, args)
    end
end

local function onClientCommand(module, command, player, args)
    if module == MIR.module then Server.handle(command, player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
