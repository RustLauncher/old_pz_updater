if isServer() then return end

require "MIR_Core"

local MIR = MultiPurposeItemRack
local racks = {}
local requestedState = {}
local pegItem = nil
local boardItems = {}
local boardVariants = {}
local reportedBoardFailure = {}
local renderRadius = 32

local function reportBoardFailure(part, message)
    if reportedBoardFailure[part] then return end
    reportedBoardFailure[part] = true
    print("[MIR][Client] board " .. tostring(part) .. " failed: "
        .. tostring(message))
end

local pegWallRotation = {
    north = 0,
    south = 180,
    west = 270,
    east = 90,
}

local pegWallNormal = {
    north = { x = 0, y = 1 },
    south = { x = 0, y = -1 },
    west = { x = 1, y = 0 },
    east = { x = -1, y = 0 },
}

local function cacheObject(object)
    if MIR.isRackWorldObject(object) then
        local id = tostring(MIR.worldItemId(object))
        racks[id] = object
        -- A newly loaded or installed section can change whether either end of
        -- a neighbouring board meets a corner wall.
        boardVariants = {}
        if not requestedState[id] and MIR.Client and MIR.Client.requestRackState then
            requestedState[id] = true
            MIR.Client.requestRackState(object)
        end
        if MIR.Client and MIR.Client.applyBoardVisibility then
            MIR.Client.applyBoardVisibility(object)
        end
    end
end

local function cacheSquare(square)
    if not square then return end
    -- The square may contain a perpendicular wall even when it contains no
    -- rack. Refresh cached corner variants as neighbouring squares stream in.
    boardVariants = {}
    MIR.eachWorldItem(square, function(object)
        cacheObject(object)
    end)
end

function MIR.cacheSinglePlayerRackSquare(square)
    if isClient() then return end
    cacheSquare(square)
end

local function removeObject(object)
    -- Player-built wall changes can alter whether a nearby rack needs a
    -- trimmed end even when the removed object itself is not a rack.
    boardVariants = {}
    if MIR.isRackWorldObject(object) then
        local id = tostring(MIR.worldItemId(object))
        racks[id] = nil
        requestedState[id] = nil
        boardVariants = {}
    end
end

local function objectAdded(object)
    boardVariants = {}
    cacheObject(object)
end

local function forgetCachedRack(id)
    racks[id] = nil
    requestedState[id] = nil
    boardVariants = {}
end

local function liveRackFor(id, square)
    if not square then return nil end
    local liveSquare = getCell():getGridSquare(
        square:getX(), square:getY(), square:getZ())
    if not liveSquare then return nil end

    local found = nil
    MIR.eachWorldItem(liveSquare, function(object)
        if not found and MIR.isRackWorldObject(object)
                and tostring(MIR.worldItemId(object)) == tostring(id) then
            found = object
        end
    end)
    return found
end

local function rackIsRelevant(square)
    if not square then return false end
    for playerNumber = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNumber)
        local playerSquare = player and player:getSquare() or nil
        if playerSquare
                and math.abs(square:getX() - playerSquare:getX()) <= renderRadius
                and math.abs(square:getY() - playerSquare:getY()) <= renderRadius
                and square:getZ() <= playerSquare:getZ()
                and square:getZ() >= playerSquare:getZ() - 1 then
            return true
        end
    end
    return false
end

local function scanAroundPlayers(radius)
    radius = type(radius) == "number" and radius or 24
    for playerNumber = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNumber)
        local origin = player and player:getSquare()
        if origin then
            -- Cache the current floor and exactly one floor below it. PZ can
            -- expose that lower storey through stairwells, balconies and
            -- cutaway walls, while other storeys must remain hidden.
            for z = origin:getZ() - 1, origin:getZ() do
                for x = origin:getX() - radius, origin:getX() + radius do
                    for y = origin:getY() - radius, origin:getY() + radius do
                        cacheSquare(getCell():getGridSquare(x, y, z))
                    end
                end
            end
        end
    end
end

local nextSinglePlayerRecoveryAt = 0
local singlePlayerRecoveryAttempts = 0

local function recoverSinglePlayerRacks()
    local now = getTimestampMs()
    if now < nextSinglePlayerRecoveryAt then return end
    nextSinglePlayerRecoveryAt = now + 1000

    -- In single player, LoadGridsquare can run before its world-inventory
    -- objects are available. Retry only during the first seconds after load,
    -- then remove this callback. New installations are cached directly by the
    -- placement cursor, so there is no permanent polling loop.
    scanAroundPlayers(8)
    singlePlayerRecoveryAttempts = singlePlayerRecoveryAttempts + 1
    if singlePlayerRecoveryAttempts >= 3 then
        Events.OnTick.Remove(recoverSinglePlayerRacks)
    end
end

local function boardItemFor(variant)
    variant = MIR.rackModels[variant] and variant or "full"
    local item = boardItems[variant]
    if not item then
        local itemType = MIR.boardRenderItemTypes[variant]
        local ok, created = pcall(function()
            return instanceItem(itemType)
        end)
        if not ok then
            reportBoardFailure("helper creation", created)
            return nil
        end
        item = created
        if not item then
            reportBoardFailure("helper creation", "instanceItem returned nil for "
                .. tostring(itemType))
            return nil
        end
        boardItems[variant] = item
    end

    -- Build 42 may retain a transient item's first cached model. Rebind the
    -- dedicated V5 model before every render, just as the proven peg renderer
    -- does, so reloads cannot silently fall back to the helper icon model.
    local ok, message = pcall(function()
        item:setWorldStaticModel(MIR.rackModels[variant])
        item:setStaticModel(MIR.rackModels[variant])
    end)
    if not ok then
        reportBoardFailure("model binding", message)
        return nil
    end
    return item
end

local function renderRackVisuals()
    if not pegItem then pegItem = instanceItem(MIR.pegRenderItemType) end
    if not pegItem then return end
    -- Script-defined WorldStaticModel values are not reliably rebound to a
    -- transient InventoryItem after a multiplayer Lua reload. Apply both model
    -- fields explicitly each time so reconnecting cannot restore the Plank model.
    pegItem:setWorldStaticModel(MIR.pegModel)
    pegItem:setStaticModel(MIR.pegModel)
    for id, rack in pairs(racks) do
        local square = rack and rack:getSquare()
        local item = MIR.itemFromWorldObject(rack)
        if not square or not item then
            forgetCachedRack(id)
        else
            local liveRack = liveRackFor(id, square)
            if not liveRack then
                -- LoadGridsquare adds transient rack references as the player
                -- travels. Once their original square unloads those references
                -- are no longer safe render anchors and must leave the cache.
                forgetCachedRack(id)
            else
                -- Always render from the live square's object, never a stale
                -- object retained from an earlier instance of that chunk.
                rack = liveRack
                racks[id] = liveRack
                square = liveRack:getSquare()
                item = MIR.itemFromWorldObject(liveRack)
            end
        end
        if square and item and racks[id] and rackIsRelevant(square) then
            -- Render only racks in the active player's loaded neighbourhood,
            -- on the current floor or exactly one floor below. A stale remote
            -- anchor can otherwise be projected into the current scene by
            -- Render3DItem and appear as a non-interactive roadside rack.
            local data = MIR.ensureRackData(item)
            if data and not data.boardHidden then
                local pose = MIR.pose(rack)
                local variant = boardVariants[id]
                if not variant then
                    local ok, result = pcall(function()
                        return MIR.rackCornerTrimVariant(rack)
                    end)
                    variant = ok and result or "full"
                    boardVariants[id] = variant
                    if not ok then reportBoardFailure("corner detection", result) end
                end
                local boardItem = pose and boardItemFor(variant) or nil
                if boardItem then
                    -- The cache-busted rack mesh is pre-oriented in PZ's Y-up
                    -- space. Only yaw changes between wall directions.
                    local ok, message = pcall(function()
                        Render3DItem(boardItem, square, pose.x, pose.y, pose.z,
                            MIR.rackYaw(rack))
                    end)
                    if not ok then reportBoardFailure("render", message) end
                end
            end
            for _, slot in ipairs(data and not data.pegsHidden and data.slots or {}) do
                local pose = MIR.restorePose(rack, slot)
                if pose then
                    local rackData = MIR.ensureRackData(item)
                    local wallRotation = pegWallRotation[rackData and rackData.wallSide] or 0
                    local wallNormal = pegWallNormal[rackData and rackData.wallSide]
                        or pegWallNormal.north
                    if rackData then
                        -- One small centred peg supports a handgun. Longer items
                        -- receive two separate pegs along the rack's horizontal axis.
                        local count = MIR.slotPegCount(slot)
                        local offsets = count == 1 and { 0 } or { -0.11, 0.11 }
                        local yaw = math.rad(MIR.rackYaw(rack))
                        for _, offset in ipairs(offsets) do
                            -- Begin just behind the displayed item, then let the
                            -- short cylinder project outward to meet it.
                            local pegX = pose.x + offset * math.cos(yaw) - wallNormal.x * 0.03
                            local pegY = pose.y + offset * math.sin(yaw) - wallNormal.y * 0.03
                            local targetSquare = getCell():getGridSquare(
                                math.floor(pegX), math.floor(pegY), math.floor(pose.z))
                            if targetSquare then
                                -- The peg mesh points along local +Y. Rotate that
                                -- axis to the inward wall normal so the peg projects
                                -- into the room instead of lying against the board.
                                pegItem:setWorldXRotation(0)
                                pegItem:setWorldYRotation(0)
                                pegItem:setWorldZRotation(wallRotation)
                                Render3DItem(pegItem, targetSquare, pegX, pegY,
                                    pose.z - 0.035, 0)
                            end
                        end
                    end
                end
            end
        end
    end
end

Events.OnGameStart.Add(scanAroundPlayers)
Events.LoadGridsquare.Add(cacheSquare)
Events.OnObjectAdded.Add(objectAdded)
Events.OnObjectAboutToBeRemoved.Add(removeObject)
Events.RenderOpaqueObjectsInWorld.Add(renderRackVisuals)
if not isClient() then
    Events.OnTick.Add(recoverSinglePlayerRacks)
end

return MIR
