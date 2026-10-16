require "OfflineSurvivorV2/OS_Constants"
require "OfflineSurvivorV2/OS_BodyLifecycle"

local OS = OfflineSurvivorV2
local H = OS.BodyLifecycle
local records = {}
local recordsInitialized = false
local lootCooldowns = {}
local runtimeObjects = {}
local runtimePlayers = {}
local lootSessions = {}
local pendingZombieDeaths = {}
-- How long each offline body has been fed on, in real seconds. Runtime only: it
-- is rebuilt from the live corpses and never persisted.
local devourProgress = {}
local devourLastFedAt = {}
-- In multiplayer a zombie's eating state is simulated by its owning client.
-- These short-lived reports bridge that native state to the server-authoritative
-- offline-death timer without treating mere proximity as an attack.
local zombieFeedingReports = {}
-- Reconnects whose position still has to be forced back to where their body was
-- left. Runtime only; the authoritative coordinates live on the record.
local pendingRepositions = {}
local RECONNECT_REPOSITION_SECONDS = 8
-- A body that simply has not streamed in yet must never be treated as lost.
-- Declaring it lost on the first miss made the maintenance pass build a
-- replacement every cycle without removing the old one, which is how servers
-- ended up with stacks of dozens of corpses.
local MISSING_OBJECT_CONFIRM_TICKS = 5
-- Hard ceiling on how many times a single offline record may rebuild its body.
local MAX_CORPSE_REBUILDS = 3
-- Consecutive maintenance scans a player has been absent from getOnlinePlayers().
local missingTicks = {}
local bodyDragSessions = {}
-- The native body-drag action releases its temporary grapple surrogate only
-- after the client sends GrapplerLetGo.  Keep the final destination here for
-- one server maintenance pass, then make the server's protected corpse the
-- single authoritative object at that tile.
local pendingBodyMoves = {}
local nextMaintenance = 0
local nextCooldownPrune = 0
local nextSessionId = 1
local lastZombieFeedLog = {}

local function numberOr(value, fallback)
    local number = H.finite(value)
    if number == nil then return fallback end
    return number
end

local function nowSeconds()
    return numberOr(getTimestamp(), 0)
end

local function nowMs()
    if getTimestampMs then return numberOr(getTimestampMs(), 0) end
    return nowSeconds() * 1000
end

local function gridCoordinate(value)
    return math.floor(numberOr(value, 0))
end

local function sendTo(player, command, args)
    if not player then return end
    pcall(function()
        sendServerCommand(player, OS.MODULE, command, args or {})
    end)
end

local function getNativeObjectId(object)
    if not object then return nil end
    local objectId = nil
    pcall(function() objectId = object:getObjectIDAsLong() end)
    if objectId == nil then return nil end
    objectId = tostring(objectId)
    if objectId == "" or objectId == "-1" then return nil end
    return objectId
end

local function makeStaleBodyCleanupArgs(steamId, x, y, z, objectId, bodyEpoch, bodyRevision)
    if steamId == nil or x == nil or y == nil or z == nil then return nil end
    return {
        targetSteamId = tostring(steamId),
        x = numberOr(x, nil),
        y = numberOr(y, nil),
        z = numberOr(z, nil),
        objectId = objectId and tostring(objectId) or nil,
        bodyEpoch = bodyEpoch,
        bodyRevision = bodyRevision,
    }
end

local function makeStaleBodyCleanupArgsForObject(record, object)
    if not record or not object then return nil end
    local x, y, z = nil, nil, nil
    pcall(function()
        x = object:getX()
        y = object:getY()
        z = object:getZ()
    end)
    local data = object:getModData()
    return makeStaleBodyCleanupArgs(record.steamId, x, y, z, getNativeObjectId(object),
        data.bodyEpoch or 0, data.bodyRevision or 0)
end

local function makeRecordedStaleBodyCleanupArgs(record)
    if not record then return nil end
    return makeStaleBodyCleanupArgs(
        record.steamId,
        record.staleProxyX,
        record.staleProxyY,
        record.staleProxyZ,
        record.staleProxyObjectId,
        record.staleProxyEpoch,
        record.staleProxyRevision
    )
end

local function broadcastStaleBodyCleanup(args)
    if not args then return end
    local players = nil
    pcall(function() players = getOnlinePlayers() end)
    if not players then return end
    for index = 0, players:size() - 1 do
        sendTo(players:get(index), OS.COMMAND_CLEANUP_STALE_BODY, args)
    end
end

-- Global ModData is saved by the server.  It is deliberately not transmitted:
-- the target inventory snapshot must never be replicated to every client.
local function persistentDataChanged()
    pcall(function() ModData.add(OS.DATA_KEY, records) end)
    pcall(function() ModData.add(OS.LOOT_DATA_KEY, lootCooldowns) end)
end

local function getRecordSquare(record)
    local x = record.objectX or record.x
    local y = record.objectY or record.y
    local z = record.objectZ
    if z == nil then z = record.z end
    if x == nil or y == nil or z == nil then return nil end
    return getWorld():getCell():getGridSquare(gridCoordinate(x), gridCoordinate(y), gridCoordinate(z))
end

local function getObjectProperty(object, key)
    if not object or not key then return nil end
    local properties = nil
    local ok, sprite = pcall(function() return object:getSprite() end)
    if ok and sprite then
        ok, properties = pcall(function() return sprite:getProperties() end)
    end
    if not properties then
        ok, properties = pcall(function() return object:getProperties() end)
    end
    if not properties then return nil end
    local valueOk, value = pcall(function() return properties:get(key) end)
    return valueOk and value or nil
end

-- Chairs and sofas also use the engine's generic "bed" flag (it is used for
-- sleep quality).  Only a real bed may take priority over a sofa, otherwise a
-- nearby chair would incorrectly be chosen as a sleeping surface.
local function isActualBed(object)
    local customName = tostring(getObjectProperty(object, "CustomName") or ""):lower()
    if customName:find("bed", 1, true)
        or customName:find("mattress", 1, true)
        or customName:find("futon", 1, true)
        or customName:find("cot", 1, true) then
        return true
    end
    -- A mod may omit CustomName but preserve the standard quality value.
    local bedType = tostring(getObjectProperty(object, "BedType") or ""):lower()
    return bedType == "goodbed"
end

local function getBedOnSquare(square)
    if not square then return nil end

    local ok, bed = pcall(function() return square:getBed() end)
    if ok and bed and isActualBed(bed) then return bed end

    -- getBed() is the native B42 route.  This fallback also supports tiles
    -- whose bed marker is exposed only through the square/object properties.
    if IsoFlagType and IsoFlagType.bed then
        local hasBed = false
        ok, hasBed = pcall(function() return square:has(IsoFlagType.bed) end)
        if ok and hasBed then
            local objects = square:getObjects()
            for index = 0, objects:size() - 1 do
                local object = objects:get(index)
                local propertiesOk, properties = pcall(function() return object:getProperties() end)
                local objectIsBed = false
                if propertiesOk and properties then
                    local flagOk, flagged = pcall(function() return properties:has(IsoFlagType.bed) end)
                    objectIsBed = flagOk and flagged == true
                end
                if objectIsBed and isActualBed(object) then return object end
            end
        end
    end
    return nil
end

local function getBedFacing(bed)
    if not bed then return nil end
    local facing = getObjectProperty(bed, "Facing")
    if not facing then return nil end
    facing = tostring(facing):upper()
    if facing == "N" or facing == "S" or facing == "E" or facing == "W" then
        return facing
    end
    return nil
end

local function getSpriteGridSize(object)
    if not object then return nil, nil end
    local grid = nil
    local ok = false
    ok, grid = pcall(function() return object:getSpriteGrid() end)
    if (not ok or not grid) then
        local sprite = nil
        ok, sprite = pcall(function() return object:getSprite() end)
        if ok and sprite then
            ok, grid = pcall(function() return sprite:getSpriteGrid() end)
        end
    end
    if not grid then return nil end

    local widthOk, width = pcall(function() return grid:getWidth() end)
    local heightOk, height = pcall(function() return grid:getHeight() end)
    if not widthOk or not heightOk then return nil end
    width = numberOr(width, 0)
    height = numberOr(height, 0)
    return width, height
end

-- Sprite-grid dimensions identify the long side of rectangular furniture.
-- On square beds, Facing identifies the headboard/lateral side, so the body
-- must use the perpendicular axis of that value.
local function getFurnitureAxis(object)
    local width, height = getSpriteGridSize(object)
    if width and height then
        if width > height then return "x" end
        if height > width then return "y" end
    end

    -- Vanilla ISGetOnBedAction places the feet of a Facing="N" bed at y - 2,
    -- so that bed runs along Y. This mapping used to be inverted, which laid
    -- the body across an east/west bed and pushed it into the wall.
    local facing = getBedFacing(object)
    if facing == "N" or facing == "S" then return "y" end
    if facing == "E" or facing == "W" then return "x" end
    return nil
end

local function getBedAxis(bed)
    return getFurnitureAxis(bed)
end

local function getObjectSearchText(object)
    local values = {}
    local function add(value)
        if value and tostring(value) ~= "" then table.insert(values, tostring(value):lower()) end
    end

    pcall(function() add(object:getName()) end)
    local sprite = nil
    pcall(function() sprite = object:getSprite() end)
    if sprite then
        pcall(function() add(sprite:getName()) end)
        pcall(function() add(sprite.tilesetName) end)
    end

    local properties = nil
    pcall(function() properties = object:getProperties() end)
    if properties then
        pcall(function() add(properties:get("CustomName")) end)
        pcall(function() add(properties:get("GroupName")) end)
        pcall(function() add(properties:get("FurnitureType")) end)
        pcall(function() add(properties:get("Type")) end)
    end
    return table.concat(values, " ")
end

-- Restrict this to multi-tile seating (or explicitly named sofas) so normal
-- chairs are never selected. Vanilla large sofas use the furniture_seating
-- tileset and a multi-tile sprite grid; mod sofas normally expose Sofa/Couch
-- in their name or custom property.
local function isLargeSofa(object)
    if not object or isActualBed(object) then return false end
    local text = getObjectSearchText(object)
    local namedSofa = text:find("sofa", 1, true)
        or text:find("couch", 1, true)
        or text:find("loveseat", 1, true)
        or text:find("sectional", 1, true)
    local width, height = getSpriteGridSize(object)
    local multiTile = width and height and (width > 1 or height > 1)
    if namedSofa then return true end
    return multiTile and text:find("furniture_seating", 1, true) ~= nil
end

local function getLargeSofaOnSquare(square)
    if not square then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if isLargeSofa(object) then return object end
    end
    return nil
end

-- Surface offsets are stored in pixels by the tileset.  The engine converts
-- them to world Z with /96 when it places an item on furniture.  IsoDeadBody
-- does not perform that conversion itself, so a corpse otherwise remains on
-- the floor and is visually hidden by a bed.
local function getBedSurfaceOffset(bed)
    if not bed then return nil end
    local ok, offset = pcall(function() return bed:getSurfaceOffsetNoTable() end)
    if not ok or offset == nil then return nil end
    offset = numberOr(offset, 0)
    return offset > 0 and offset or nil
end

local function getFurnitureCenter(object, square)
    local defaultX = square:getX() + 0.5
    local defaultY = square:getY() + 0.5
    if not object then return defaultX, defaultY end

    local grid = nil
    local sprite = nil
    pcall(function() grid = object:getSpriteGrid() end)
    pcall(function() sprite = object:getSprite() end)
    if not grid or not sprite then return defaultX, defaultY end

    local okX, gridX = pcall(function() return grid:getSpriteGridPosX(sprite) end)
    local okY, gridY = pcall(function() return grid:getSpriteGridPosY(sprite) end)
    local okW, width = pcall(function() return grid:getWidth() end)
    local okH, height = pcall(function() return grid:getHeight() end)
    if not okX or not okY or not okW or not okH then return defaultX, defaultY end

    gridX = numberOr(gridX, -1)
    gridY = numberOr(gridY, -1)
    width = numberOr(width, 0)
    height = numberOr(height, 0)
    if gridX < 0 or gridY < 0 or width <= 0 or height <= 0 then return defaultX, defaultY end

    -- The selected bed object can be any tile of a multi-tile furniture grid.
    -- Convert it to the grid origin, then use the center of the full mattress.
    return square:getX() - gridX + (width / 2), square:getY() - gridY + (height / 2)
end

local function getCorpseRenderPosition(record, square)
    return numberOr(record.renderX, square:getX() + 0.5), numberOr(record.renderY, square:getY() + 0.5)
end

local function getCorpseRenderZ(record, square)
    if not square or (record.placement ~= "bed" and record.placement ~= "sofa") then
        return square and square:getZ() or 0
    end

    local isBed = record.placement == "bed"
    local surfaceOffset = numberOr(isBed and record.bedSurfaceOffset or record.sofaSurfaceOffset, nil)
    if surfaceOffset == nil then
        local furniture = isBed and getBedOnSquare(square) or getLargeSofaOnSquare(square)
        surfaceOffset = getBedSurfaceOffset(furniture)
    end

    -- Most vanilla beds expose Surface.  The fallback keeps beds from mods
    -- without that tile property at mattress height (roughly 32 pixels).
    if surfaceOffset == nil then surfaceOffset = 32 end
    return square:getZ() + (surfaceOffset + 1) / 96
end

local function isSamePlacementArea(origin, candidate)
    if not origin or not candidate or origin:getZ() ~= candidate:getZ() then return false end

    local outsideOk, originOutside = pcall(function() return origin:isOutside() end)
    local candidateOutsideOk, candidateOutside = pcall(function() return candidate:isOutside() end)
    if outsideOk and candidateOutsideOk and originOutside ~= candidateOutside then return false end

    local roomOk, originRoom = pcall(function() return origin:getRoom() end)
    local candidateRoomOk, candidateRoom = pcall(function() return candidate:getRoom() end)
    if roomOk and candidateRoomOk and originRoom ~= candidateRoom then return false end
    return true
end

local function setBedPlacement(record, square, bed)
    record.objectX = square:getX()
    record.objectY = square:getY()
    record.objectZ = square:getZ()
    record.renderX, record.renderY = getFurnitureCenter(bed, square)
    record.placement = "bed"
    record.bedFacing = getBedFacing(bed)
    record.bedAxis = getBedAxis(bed)
    record.bedSurfaceOffset = getBedSurfaceOffset(bed)
    record.sofaFacing = nil
    record.sofaAxis = nil
    record.sofaSurfaceOffset = nil
end

local function setSofaPlacement(record, square, sofa)
    record.objectX = square:getX()
    record.objectY = square:getY()
    record.objectZ = square:getZ()
    record.renderX, record.renderY = getFurnitureCenter(sofa, square)
    record.placement = "sofa"
    record.bedFacing = nil
    record.bedAxis = nil
    record.bedSurfaceOffset = nil
    record.sofaFacing = getBedFacing(sofa)
    record.sofaAxis = getFurnitureAxis(sofa)
    record.sofaSurfaceOffset = getBedSurfaceOffset(sofa)
end

local function chooseCorpsePlacement(record)
    local cell = getWorld():getCell()
    local originX = gridCoordinate(record.x)
    local originY = gridCoordinate(record.y)
    local originZ = gridCoordinate(record.z)
    local radius = math.max(0, math.floor(numberOr(OS.getOption("BedRadius", 1), 1)))
    local origin = cell:getGridSquare(originX, originY, originZ)

    -- A bed in the logout square always wins, regardless of where inside the
    -- square the player stood.
    local directBed = getBedOnSquare(origin)
    if directBed then
        setBedPlacement(record, origin, directBed)
        return
    end

    local bestSquare = nil
    local bestBed = nil
    local bestDistance = nil

    for offsetX = -radius, radius do
        for offsetY = -radius, radius do
            local square = cell:getGridSquare(originX + offsetX, originY + offsetY, originZ)
            local bed = isSamePlacementArea(origin, square) and getBedOnSquare(square) or nil
            if bed then
                local dx = (square:getX() + 0.5) - numberOr(record.x, originX)
                local dy = (square:getY() + 0.5) - numberOr(record.y, originY)
                local distance = (dx * dx) + (dy * dy)
                if distance <= (radius * radius) and (not bestDistance or distance < bestDistance) then
                    bestSquare = square
                    bestBed = bed
                    bestDistance = distance
                end
            end
        end
    end

    if bestSquare then
        setBedPlacement(record, bestSquare, bestBed)
        return
    end

    -- Sofas deliberately come after every nearby bed.  This keeps a player
    -- who logs out in a bedroom on the bed, while allowing a large couch to
    -- behave as a raised sleeping surface in a living room.
    local sofaRadius = math.max(0, math.floor(numberOr(OS.getOption("SofaRadius", 1), 1)))
    local directSofa = getLargeSofaOnSquare(origin)
    if directSofa then
        setSofaPlacement(record, origin, directSofa)
        return
    end

    local bestSofaSquare = nil
    local bestSofa = nil
    bestDistance = nil
    for offsetX = -sofaRadius, sofaRadius do
        for offsetY = -sofaRadius, sofaRadius do
            local square = cell:getGridSquare(originX + offsetX, originY + offsetY, originZ)
            local sofa = isSamePlacementArea(origin, square) and getLargeSofaOnSquare(square) or nil
            if sofa then
                local dx = (square:getX() + 0.5) - numberOr(record.x, originX)
                local dy = (square:getY() + 0.5) - numberOr(record.y, originY)
                local distance = (dx * dx) + (dy * dy)
                if distance <= (sofaRadius * sofaRadius) and (not bestDistance or distance < bestDistance) then
                    bestSofaSquare = square
                    bestSofa = sofa
                    bestDistance = distance
                end
            end
        end
    end

    if bestSofaSquare then
        setSofaPlacement(record, bestSofaSquare, bestSofa)
        return
    end

    record.objectX = originX
    record.objectY = originY
    record.objectZ = originZ
    record.renderX = originX + 0.5
    record.renderY = originY + 0.5
    record.placement = "floor"
    record.bedFacing = nil
    record.bedAxis = nil
    record.bedSurfaceOffset = nil
    record.sofaFacing = nil
    record.sofaAxis = nil
    record.sofaSurfaceOffset = nil
end

local function sameSteamId(left, right)
    return left ~= nil and right ~= nil and tostring(left) == tostring(right)
end

local function isNativeCorpse(object)
    if not object then return false end

    -- getStaticMovingObjectIndex() is a render-list index. In B42.20 it is
    -- -1 for valid server-side IsoDeadBody instances, even after addCorpse.
    -- Using that value made the maintenance loop classify every real corpse
    -- as invalid, recreate it every second and leave duplicated bodies.
    local ok, result = pcall(function() return instanceof(object, "IsoDeadBody") end)
    return ok and result == true
end

local function findOfflineObject(record)
    local object = runtimeObjects[record.steamId]
    if object then
        local square = object:getSquare()
        if square and getWorld():getCell():getGridSquare(square:getX(),square:getY(),square:getZ())==square
            and square:getStaticMovingObjects():contains(object) then return object end
        runtimeObjects[record.steamId] = nil
    end

    local square = getRecordSquare(record)
    if not square then return nil end

    local function findIn(list)
        if not list then return nil end
        for index = 0, list:size() - 1 do
            local candidate = list:get(index)
            local data = candidate and candidate:getModData()
            if data and data[OS.OFFLINE_MARKER] and sameSteamId(data.steamId, record.steamId) then
                runtimeObjects[record.steamId] = candidate
                return candidate
            end
        end
        return nil
    end

    -- IsoDeadBody lives in staticMovingObjects, unlike the V2's retired
    -- mannequin implementation which lived in square.objects.
    local found = findIn(square:getStaticMovingObjects()) or findIn(square:getObjects())
    if found then return found end

    -- The corpse can settle on a neighbouring tile after a drag or a bed/sofa
    -- placement. Without this sweep the body is reported missing and a second
    -- one is created, which is how duplicate corpses appeared.
    local cell = getWorld() and getWorld():getCell() or nil
    if not cell then return nil end

    local baseX, baseY = square:getX(), square:getY()
    local baseZ = square:getZ()
    for x = baseX - 1, baseX + 1 do
        for y = baseY - 1, baseY + 1 do
            if x ~= baseX or y ~= baseY then
                local neighbour = cell:getGridSquare(x, y, baseZ)
                if neighbour then
                    found = findIn(neighbour:getStaticMovingObjects()) or findIn(neighbour:getObjects())
                    if found then return found end
                end
            end
        end
    end
    return nil
end

local function setOfflineObjectData(object, record)
    local data = object:getModData()
    data[OS.OFFLINE_MARKER] = true
    data.steamId = record.steamId
    data.username = record.username
    data.offlineAt = record.offlineAt
    data.bodyEpoch = record.bodyEpoch or 0
    data.bodyRevision = record.bodyRevision or 0
    data.renderer = OS.RENDERER
    data.pose = OS.CORPSE_POSE
    data.placement = record.placement or "floor"
    data.testBody = record.testBody == true
    data.testDefeated = record.testDefeated == true
    data.deferredDeath = record.deferredDeath == true
    data.jaxeRevivalIncapacitated = record.jaxeRevivalIncapacitated == true
    data.corpseDirection = record.corpseDirection
    data.fallOnFront = record.fallOnFront == true
    data.bedFacing = record.bedFacing
    data.bedAxis = record.bedAxis
    data.sofaFacing = record.sofaFacing
    data.sofaAxis = record.sofaAxis

    -- Immersive Looting B42 must not take ownership of this renderer-only
    -- container. The real inventory remains server-authoritative and is
    -- exposed exclusively by this mod's Search action. These are the
    -- Immersive Looting public ModData flags; other installations ignore them.
    data.ILB42_containerSearched = true
    data.ILB42_itemContainerComplete = true
end

-- A restart removes the old disconnected IsoPlayer from memory, so a real
-- corpse cannot be created until its owner reconnects. Keep the protected
-- visual in place, mark it as unavailable, and let the reconnect pipeline
-- replace it with the player's true native corpse.
local function markOfflineProxyPendingDeath(record)
    local proxy = findOfflineObject(record)
    if not proxy then return false end
    setOfflineObjectData(proxy, record)
    pcall(function() proxy:transmitModData() end)
    return true
end

local function isCardinalDirection(directionName)
    return directionName == "N" or directionName == "E" or directionName == "S" or directionName == "W"
end

local function chooseRandomValue(values)
    local count = #values
    if count == 0 then return nil end

    local ok, randomIndex = pcall(function() return ZombRand(count) end)
    if ok and type(randomIndex) == "number" then
        return values[math.floor(randomIndex) + 1]
    end
    return values[math.random(1, count)]
end

local function getPoseAxis(record)
    if record.placement == "bed" then return record.bedAxis end
    if record.placement == "sofa" then return record.sofaAxis end
    return nil
end

-- A native corpse only supports its normal dead-body pose, but that pose has
-- two stable sides and four render directions. Pick and save a side/direction
-- once per logout so recreation, dragging and clients all show the same pose.
local function chooseCorpsePose(record)
    local axis = getPoseAxis(record)
    if axis == "x" then
        record.corpseDirection = chooseRandomValue({ "E", "W" })
    elseif axis == "y" then
        record.corpseDirection = chooseRandomValue({ "N", "S" })
    else
        record.corpseDirection = chooseRandomValue({ "N", "E", "S", "W" })
    end
    record.fallOnFront = chooseRandomValue({ false, true }) == true
end

local function ensureCorpsePose(record)
    local directionName = tostring(record.corpseDirection or ""):upper()
    local axis = getPoseAxis(record)
    local needsDirection = not isCardinalDirection(directionName)
        or (axis == "x" and directionName ~= "E" and directionName ~= "W")
        or (axis == "y" and directionName ~= "N" and directionName ~= "S")
    if needsDirection or type(record.fallOnFront) ~= "boolean" then
        chooseCorpsePose(record)
    end
end

local function getCorpseDirection(record)
    ensureCorpsePose(record)
    local directionName = tostring(record.corpseDirection or record.direction or ""):upper()
    -- The dead-body pose must use the long axis of the furniture. Facing is
    -- only used for head/foot selection when it agrees with that axis; on many
    -- beds Facing identifies a side of the mattress instead.
    if record.placement == "bed" or record.placement == "sofa" then
        local facing = record.placement == "bed" and record.bedFacing or record.sofaFacing
        local axis = record.placement == "bed" and record.bedAxis or record.sofaAxis
        if axis == "x" then
            directionName = (directionName == "E" or directionName == "W") and directionName or "E"
        elseif axis == "y" then
            directionName = (directionName == "N" or directionName == "S") and directionName or "S"
        elseif facing == "N" or facing == "E" or facing == "S" or facing == "W" then
            directionName = facing
        end
    end

    local ok, direction = pcall(function() return IsoDirections[directionName] end)
    if ok and direction then return direction end
    ok, direction = pcall(function() return IsoDirections.S end)
    return ok and direction or nil
end

local function applyCorpseDirection(corpse, direction)
    if not corpse or not direction then return end
    corpse:setForwardIsoDirection(direction)

    -- IsoDeadBody stores a separate render angle. Set it explicitly so the
    -- frozen player/deadbody animation follows the selected bed axis.
    local ok, angle = pcall(function() return direction:toAngle() end)
    if ok and angle then corpse:setForwardDirectionAngle(angle) end
end

local function markVisualClone(item, record)
    if not item then return end
    local data = item:getModData()
    data[OS.VISUAL_CLONE_MARKER] = true
    data.offlineSurvivorV2Owner = tostring(record.steamId)
end

local function cloneHandItem(source, record)
    if not source or not instanceItem then return nil end
    local ok, fullType = pcall(function() return source:getFullType() end)
    if not ok or not fullType or tostring(fullType) == "" then return nil end

    local clone = nil
    ok, clone = pcall(function() return instanceItem(tostring(fullType)) end)
    if not ok or not clone then return nil end
    markVisualClone(clone, record)
    return clone
end

local function createOfflineCorpse(record, square, visualSource)
    -- Always rebuild from the disconnected player when the server still holds
    -- it. A detached proxy works as a visual source, but rebuilding corpse from
    -- corpse degrades the outfit on every drag: IsoDeadBody.save writes each
    -- worn item as an index into its own container, so any item that fails to
    -- round-trip is simply dropped and the body arrives naked on the clients.
    -- The proxy is therefore only a fallback, used after a server restart.
    local player = runtimePlayers[record.steamId] or visualSource
    if not player then return nil, "last player visual is unavailable" end
    ensureCorpsePose(record)

    local createdProxy
    local ok, result = pcall(function()
        if not IsoPlayer or not IsoDeadBody or not ItemVisuals or not sendCorpse then
            error("IsoPlayer, IsoDeadBody, ItemVisuals or sendCorpse is unavailable")
        end

        -- The surrogate exists only long enough to use the engine's own
        -- IsoDeadBody conversion. It is never added to the player list and
        -- its inventory only contains rendering-only clones.
        local surrogate = IsoPlayer.new(getWorld():getCell())
        if not surrogate then error("failed to create the visual surrogate") end
        local x, y = getCorpseRenderPosition(record, square)
        local z = getCorpseRenderZ(record, square)
        surrogate:setX(x)
        surrogate:setY(y)
        surrogate:setZ(z)
        surrogate:setNextX(x)
        surrogate:setNextY(y)
        surrogate:setCurrentSquare(square)
        surrogate:setFemale(player:isFemale() == true)

        local direction = getCorpseDirection(record)
        if direction then surrogate:setForwardIsoDirection(direction) end
        surrogate:setFallOnFront(record.fallOnFront == true)
        -- A non-zombie player corpse with KilledByFall uses the native player
        -- "deadbody" pose, rather than the zombie on-ground animation.
        surrogate:setKilledByFall(true)

        local sourceVisuals = ItemVisuals.new()
        player:getItemVisuals(sourceVisuals)
        local worn = surrogate:getWornItems()
        local container = surrogate:getInventory()
        if not worn or not container then error("surrogate did not create a visual container") end

        worn:clear()
        container:clear()
        worn:setFromItemVisuals(sourceVisuals)
        worn:addItemsToItemContainer(container)
        for index = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(index)
            markVisualClone(item, record)
        end

        -- HumanVisual contains skin, hair, beard, blood, dirt and body
        -- details. Its native copyFrom is a deep visual copy.
        surrogate:getHumanVisual():copyFrom(player:getHumanVisual())

        -- Hand models are not part of ItemVisuals.  Use fresh item instances
        -- so neither the real player's item nor its inventory is touched.
        local sourcePrimary = player:getPrimaryHandItem()
        local sourceSecondary = player:getSecondaryHandItem()
        local primary = cloneHandItem(sourcePrimary, record)
        local secondary = sourceSecondary == sourcePrimary and primary or cloneHandItem(sourceSecondary, record)
        if primary then
            container:AddItem(primary)
            surrogate:setPrimaryHandItem(primary)
        end
        if secondary then
            if secondary ~= primary then container:AddItem(secondary) end
            surrogate:setSecondaryHandItem(secondary)
        end

        local corpse = IsoDeadBody.new(surrogate, true, false)
        createdProxy = corpse
        if not corpse then error("engine did not create the offline corpse") end
        applyCorpseDirection(corpse, direction)
        corpse:setFallOnFront(record.fallOnFront == true)
        corpse:setKilledByFall(true)
        if primary then corpse:setPrimaryHandItem(primary) end
        if secondary then corpse:setSecondaryHandItem(secondary) end

        setOfflineObjectData(corpse, record)
        H.freezeAge(corpse)
        corpse:setOutlineOnMouseover(true)
        square:addCorpse(corpse, false)
        -- This is the native server packet used by normal corpses. It sends
        -- HumanVisual, worn-item visuals, position and ModData to relevant
        -- clients immediately.
        sendCorpse(corpse)
        -- sendCorpse already serializes this corpse's ModData. Sending an
        -- additional ObjectChange packet here can race the corpse packet on
        -- multiplayer clients, so it must not be transmitted a second time.
        return corpse
    end)

    if not ok then
        if createdProxy then
            pcall(function()
                if square:getStaticMovingObjects():contains(createdProxy) then
                    square:removeCorpse(createdProxy, false)
                end
            end)
        end
        return nil, tostring(result)
    end
    return result, nil
end

-- Assigned further below. Declared here so the corpse builder can sweep stale
-- bodies before creating a new one, which it must do to prevent corpse stacks.
local removeTrackedObject

local function createOfflineCorpseObject(record, visualSource)
    if record.adminVisualRemoved or record.despawned then return nil end
    local existing = findOfflineObject(record)
    if existing then
        local data = existing:getModData()
        if isNativeCorpse(existing) and data and data.renderer == OS.RENDERER then
            H.freezeAge(existing)
            record.objectCreated = true
            return existing
        end

        -- Clean up a mannequin left by an older V2 build before replacing it.
        local oldSquare = existing:getSquare()
        if oldSquare then
            if isNativeCorpse(existing) then
                oldSquare:removeCorpse(existing, false)
            else
                oldSquare:transmitRemoveItemFromSquare(existing)
            end
        end
        runtimeObjects[record.steamId] = nil
    end

    local square = getRecordSquare(record)
    if not square then
        -- Reported once: this is retried every tick until the chunk streams in.
        if not record.squareWaitReported then
            record.squareWaitReported = true
            print("[OfflineSurvivor V2] Logout square is not loaded for " .. tostring(record.username) .. "; waiting for it to stream in")
        end
        return nil
    end
    record.squareWaitReported = nil

    -- Refuse to keep rebuilding forever. If a body cannot be kept stable, one
    -- unmanaged corpse is a far smaller problem than a growing pile of them.
    local rebuilds = numberOr(record.corpseRebuilds, 0) + 1
    record.corpseRebuilds = rebuilds
    if rebuilds > MAX_CORPSE_REBUILDS then
        record.corpseFailure = "the offline body could not be kept stable"
        if not record.corpseFailureReported then
            record.corpseFailureReported = true
            print("[OfflineSurvivor V2] Stopped rebuilding the offline body for " .. tostring(record.username)
                .. " after " .. tostring(MAX_CORPSE_REBUILDS) .. " attempts; no further copies will be created")
        end
        return nil
    end

    -- Sweep any marked body of this player that the lookup could not match.
    -- Without this a body the search cannot see is never removed either, and
    -- each rebuild stacks another corpse on top of the last.
    removeTrackedObject(record, square)

    record.bodyRevision = numberOr(record.bodyRevision, 0) + 1
    local corpse, corpseReason = createOfflineCorpse(record, square, visualSource)
    if not corpse then
        record.corpseFailure = tostring(corpseReason)
        if not record.corpseFailureReported then
            record.corpseFailureReported = true
            print("[OfflineSurvivor V2] Native corpse failed for " .. tostring(record.username) .. ": " .. record.corpseFailure)
        end
        return nil
    end

    record.corpseFailure = nil
    record.corpseFailureReported = nil
    record.objectCreated = true
    runtimeObjects[record.steamId] = corpse
    print("[OfflineSurvivor V2] Created native player corpse for " .. tostring(record.username) .. " on " .. tostring(record.placement or "floor"))
    return corpse
end

-- The B42 client turns a grabbed corpse into a client-local temporary zombie.
-- Once the client confirms that state, remove the authoritative source corpse
-- from every client and retain it only as a visual source for a fresh corpse
-- at the drop location. Keeping the source out of the world prevents it from
-- being recreated at its former tile while the drag animation is active.
local function detachBodyDragProxy(record)
    if not record or not record.steamId then return nil end
    local key = tostring(record.steamId)
    local session = bodyDragSessions[key]
    if not session then return nil end
    if session.sourceDetached then return session.proxy end

    local proxy = findOfflineObject(record)
    if not proxy or not isNativeCorpse(proxy) then return nil end
    local square = nil
    pcall(function() square = proxy:getSquare() end)
    if not square then return nil end
    local sourceObjectId = getNativeObjectId(proxy)

    -- removeCorpse(..., false) emits the normal RemoveCorpseFromMap packet on
    -- the dedicated server, so all clients lose the old proxy immediately.
    local removed = pcall(function() square:removeCorpse(proxy, false) end)
    if not removed then return nil end

    runtimeObjects[key] = nil
    record.objectCreated = nil
    -- Keep coordinates only, never an IsoGridSquare reference.  A late native
    -- release packet can otherwise recreate a marked proxy on this old square
    -- after the new destination corpse has been made.
    session.sourceX = square:getX()
    session.sourceY = square:getY()
    session.sourceZ = square:getZ()
    session.sourceObjectId = sourceObjectId
    session.sourceEpoch = proxy:getModData().bodyEpoch or 0
    session.sourceRevision = proxy:getModData().bodyRevision or 0
    record.dragSourceX,record.dragSourceY,record.dragSourceZ=session.sourceX,session.sourceY,session.sourceZ
    record.dragSourceObjectId=session.sourceObjectId
    record.dragSourceEpoch,record.dragSourceRevision=session.sourceEpoch,session.sourceRevision
    record.dragSourceCleanupUntil=nowSeconds()+OS.STALE_BODY_CLEANUP_SECONDS
    session.proxy = proxy
    session.sourceDetached = true
    return proxy
end

local function restoreDetachedBodyDragProxy(record, session)
    if not record or not session or not session.sourceDetached or record.adminVisualRemoved
        or record.despawned or (record.state ~= "offline" and record.state ~= "test_offline") then return nil end
    local visualSource = session.proxy
    record.corpseRebuilds = 0
    session.proxy = nil
    session.sourceDetached = nil
    runtimeObjects[tostring(record.steamId)] = nil
    record.objectCreated = nil
    record.corpseFailure = nil
    record.corpseFailureReported = nil
    local restored = createOfflineCorpseObject(record, visualSource)
    if not restored and visualSource and runtimePlayers[tostring(record.steamId)] then
        -- A removed corpse normally remains a valid visual source. If a
        -- third-party visual refuses that path, the retained disconnected
        -- player is the safe fallback and keeps the sleeper represented.
        record.corpseFailure = nil
        record.corpseFailureReported = nil
        restored = createOfflineCorpseObject(record)
    end
    return restored
end

local function removeOfflineObjectsFromSquare(record, square)
    if not record or not square then return false end

    local removed = false
    local function removeFrom(list)
        if not list then return end
        -- Removing an entry changes Java's ArrayList indices.  Iterate
        -- backwards so every duplicate left by an interrupted native drag is
        -- removed, instead of preserving the next one in the list.
        for index = list:size() - 1, 0, -1 do
            local candidate = list:get(index)
            local data = candidate and candidate:getModData() or nil
            if data and data[OS.OFFLINE_MARKER] and sameSteamId(data.steamId, record.steamId) then
                if isNativeCorpse(candidate) then
                    square:removeCorpse(candidate, false)
                else
                    -- Compatibility cleanup for an object made by an older V2 build.
                    square:transmitRemoveItemFromSquare(candidate)
                end
                removed = true
            end
        end
    end

    removeFrom(square:getStaticMovingObjects())
    removeFrom(square:getObjects())

    -- In multiplayer B42 can replicate the native drag surrogate as an
    -- IsoZombie before it dies back into a corpse. It carries our ModData,
    -- but it lives in movingObjects rather than either corpse collection.
    -- Remove only that engine-marked, temporary zombie; never touch ordinary
    -- zombies or players on the square.
    local movingObjects = square:getMovingObjects()
    if movingObjects then
        for index = movingObjects:size() - 1, 0, -1 do
            local candidate = movingObjects:get(index)
            local data = candidate and candidate:getModData() or nil
            local isDragProxy = false
            if data and data[OS.OFFLINE_MARKER] and sameSteamId(data.steamId, record.steamId) then
                -- B42 can clear isReanimatedForGrappleOnly() before the client
                -- has removed its temporary drag zombie. The mod marker plus
                -- the owner's SteamID is the authoritative identity here.
                pcall(function() isDragProxy = instanceof(candidate, "IsoZombie") end)
            end
            if isDragProxy then
                pcall(function() candidate:removeFromWorld() end)
                pcall(function() candidate:removeFromSquare() end)
                removed = true
            end
        end
    end
    return removed
end

local function hasDuplicateOfflineObjects(record)
    if not record then return false end

    local count = 0
    local seenObjects = setmetatable({}, { __mode = "k" })
    local scannedSquares = {}
    local function countIn(list)
        if not list then return end
        for index = 0, list:size() - 1 do
            local candidate = list:get(index)
            local data = candidate and candidate:getModData() or nil
            if not seenObjects[candidate] and data and data[OS.OFFLINE_MARKER] and sameSteamId(data.steamId, record.steamId) then
                seenObjects[candidate] = true
                count = count + 1
                if count > 1 then return end
            end
        end
    end

    local function scan(square)
        if not square or count > 1 then return end
        local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
        if scannedSquares[key] then return end
        scannedSquares[key] = true
        countIn(square:getStaticMovingObjects())
        if count < 2 then countIn(square:getObjects()) end
        if count < 2 then countIn(square:getMovingObjects()) end
    end

    scan(getRecordSquare(record))
    local runtime = runtimeObjects[record.steamId]
    if runtime and count < 2 then
        local runtimeSquare = nil
        pcall(function() runtimeSquare = runtime:getSquare() end)
        scan(runtimeSquare)
    end

    -- A delayed AddCorpse after a successful drag can settle at the source
    -- tile. Count that tile too, otherwise the normal destination scan sees
    -- one body and leaves its stale twin behind.
    if count < 2 and record.dragSourceX ~= nil and record.dragSourceY ~= nil and record.dragSourceZ ~= nil then
        local cell = getWorld() and getWorld():getCell() or nil
        if cell then
            scan(cell:getGridSquare(gridCoordinate(record.dragSourceX), gridCoordinate(record.dragSourceY), gridCoordinate(record.dragSourceZ)))
        end
    end
    return count > 1
end

removeTrackedObject = function(record, extraSquare)
    local inspected = false
    local removed = false
    local scanned = {}

    local function scan(square)
        if not square then return end
        local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
        if scanned[key] then return end
        scanned[key] = true
        inspected = true
        if removeOfflineObjectsFromSquare(record, square) then removed = true end
    end

    -- Locate the body first. This also caches the tile it truly sits on, which
    -- after a drag or a bed/sofa placement is not always the recorded one.
    local located = nil
    pcall(function() located = findOfflineObject(record) end)

    local runtime = runtimeObjects[record.steamId]
    if runtime then
        local runtimeSquare = nil
        pcall(function() runtimeSquare = runtime:getSquare() end)
        scan(runtimeSquare)
    end

    local recordSquare = getRecordSquare(record)
    scan(recordSquare)
    scan(extraSquare)

    -- A drag leaves its old tile in the record for late client-packet cleanup.
    -- Sweep it on every destructive path as well, so a stale body can never
    -- survive a reconnect/rebuild merely because it is no longer near the
    -- recorded destination.
    local cell = getWorld() and getWorld():getCell() or nil
    if cell and record.dragSourceX ~= nil and record.dragSourceY ~= nil and record.dragSourceZ ~= nil then
        local sourceX = gridCoordinate(record.dragSourceX)
        local sourceY = gridCoordinate(record.dragSourceY)
        local sourceZ = gridCoordinate(record.dragSourceZ)
        for x = sourceX - 1, sourceX + 1 do
            for y = sourceY - 1, sourceY + 1 do
                scan(cell:getGridSquare(x, y, sourceZ))
            end
        end
    end

    -- Sweep the ring around the recorded tile as well. Removal has to cover
    -- exactly what findOfflineObject can find, otherwise a body that drifted
    -- one tile survives the reconnect and the player ends up standing on top
    -- of their own corpse.
    if cell and recordSquare then
        local baseX, baseY, baseZ = recordSquare:getX(), recordSquare:getY(), recordSquare:getZ()
        for x = baseX - 1, baseX + 1 do
            for y = baseY - 1, baseY + 1 do
                if x ~= baseX or y ~= baseY then scan(cell:getGridSquare(x, y, baseZ)) end
            end
        end
    end

    runtimeObjects[record.steamId] = nil

    -- A body was found but survived the sweep: report failure so the record
    -- keeps its coordinates and the maintenance pass retries, instead of
    -- abandoning a corpse in the world forever.
    if located and not removed then return false end

    -- A square can be unavailable after a restart.  Do not clear this record
    -- until at least one relevant square was inspected for real.
    return removed or inspected
end

local function removeOfflineObjectsNear(record, x, y, z)
    if not record or x == nil or y == nil or z == nil then return false end
    local cell = getWorld() and getWorld():getCell() or nil
    if not cell then return false end

    local removed = false
    local centerX = gridCoordinate(x)
    local centerY = gridCoordinate(y)
    local centerZ = gridCoordinate(z)
    for tileX = centerX - 1, centerX + 1 do
        for tileY = centerY - 1, centerY + 1 do
            local square = cell:getGridSquare(tileX, tileY, centerZ)
            if square and removeOfflineObjectsFromSquare(record, square) then
                removed = true
            end
        end
    end
    return removed
end

-- For a short period after a completed native drag, sweep the former square as
-- well as the new authoritative square. B42's local grappling conversion can
-- publish a stale marked corpse after the server has already processed the
-- drop. The SteamID marker means this cannot remove an ordinary corpse/zombie.
local function clearStaleBodyDragSource(record)
    if not record or record.dragSourceX == nil or record.dragSourceY == nil or record.dragSourceZ == nil then
        return false
    end

    local function clearCoordinates()
        record.dragSourceX, record.dragSourceY, record.dragSourceZ = nil, nil, nil
        record.dragSourceObjectId = nil
        record.dragSourceCleanupUntil = nil
    end

    if numberOr(record.objectX, -999999) == numberOr(record.dragSourceX, -999998)
        and numberOr(record.objectY, -999999) == numberOr(record.dragSourceY, -999998)
        and numberOr(record.objectZ, -999999) == numberOr(record.dragSourceZ, -999998) then
        clearCoordinates()
        return true
    end

    -- Keep the old source coordinates after the short server-side sweep ends.
    -- A reconnecting owner may receive a stale AddCorpse packet much later and
    -- needs those coordinates for a targeted client-local cleanup.
    if record.dragSourceCleanupUntil == nil then return false end
    if numberOr(record.dragSourceCleanupUntil, 0) <= nowSeconds() then
        record.dragSourceCleanupUntil = nil
        return true
    end

    return removeOfflineObjectsNear(record, record.dragSourceX, record.dragSourceY, record.dragSourceZ)
end

-- When B42 drags a corpse, it reanimates it as a temporary IsoZombie and
-- turns that zombie back into a new IsoDeadBody only after the release event
-- finishes.  The temporary and final objects retain our ModData.  Detect the
-- state at the reported destination so we never remove the temporary zombie
-- before the engine is done with it (which was creating a second corpse).
local function getNativeDragStateNear(record, x, y, z)
    local state = { surrogate = false, droppedCorpse = false }
    if not record or x == nil or y == nil or z == nil then return state end

    local cell = getWorld() and getWorld():getCell() or nil
    if not cell then return state end

    local centerX = math.floor(numberOr(x, 0))
    local centerY = math.floor(numberOr(y, 0))
    local centerZ = math.floor(numberOr(z, 0))

    local function matchesRecord(candidate)
        local data = candidate and candidate:getModData() or nil
        return data and data[OS.OFFLINE_MARKER] and sameSteamId(data.steamId, record.steamId)
    end

    for tileX = centerX - 2, centerX + 2 do
        for tileY = centerY - 2, centerY + 2 do
            local square = cell:getGridSquare(tileX, tileY, centerZ)
            if square then
                local corpses = square:getStaticMovingObjects()
                if corpses then
                    for index = 0, corpses:size() - 1 do
                        local candidate = corpses:get(index)
                        if matchesRecord(candidate) and isNativeCorpse(candidate) then
                            state.droppedCorpse = true
                        end
                    end
                end

                local movingObjects = square:getMovingObjects()
                if movingObjects then
                    for index = 0, movingObjects:size() - 1 do
                        local candidate = movingObjects:get(index)
                        if matchesRecord(candidate) then
                            local isZombie = false
                            pcall(function() isZombie = instanceof(candidate, "IsoZombie") end)
                            if isZombie then
                                local isSurrogate = false
                                pcall(function() isSurrogate = candidate:isReanimatedForGrappleOnly() == true end)
                                if isSurrogate then state.surrogate = true end
                            end
                        end
                    end
                end
            end
        end
    end
    return state
end

-- The client runs B42's native corpse-dragging action and reports only its
-- final tile. The client renews this short-lived lease while the native
-- dragging animation is running. A lease deliberately expires quickly when a
-- client cancels, disconnects, or fails to send its final tile, so it can
-- never leave a sleeping survivor permanently marked as "being moved".
-- survivor it did not first reach and prevents two players from dragging the
-- same sleeper at once.
-- A heartbeat arrives every five seconds while the native animation is alive.
-- Ten seconds clears a lost/cancelled client promptly without interrupting a
-- legitimate drag.
local BODY_DRAG_SESSION_SECONDS = 10

-- These helpers are assigned below. Their declarations must appear before the
-- pickup acknowledgement so it closes over these locals instead of globals.
local setFloorPlacement
local bodyDragResult
local isSleepingRecord

local function getBodyDragSession(record)
    if not record or not record.steamId then return nil end
    local key = tostring(record.steamId)
    local session = bodyDragSessions[key]
    if session and numberOr(session.expiresAt, 0) <= nowSeconds() then
        -- Do not leak a detached IsoDeadBody reference or leave its owner with
        -- no visual proxy when a client disconnects mid-drag.
        if session.sourceDetached then
            restoreDetachedBodyDragProxy(record, session)
            persistentDataChanged()
        end
        bodyDragSessions[key] = nil
        pendingBodyMoves[key] = nil
        return nil
    end
    return session
end

local function clearBodyDragSession(record)
    if record and record.steamId then
        local key = tostring(record.steamId)
        local session = bodyDragSessions[key]
        if session then session.proxy = nil end
        bodyDragSessions[key] = nil
        pendingBodyMoves[key] = nil
    end
end

local function clearExpiredBodyDragSessions()
    local current = nowSeconds()
    for targetSteamId, session in pairs(bodyDragSessions) do
        if not session or numberOr(session.expiresAt, 0) <= current then
            local record = records[targetSteamId]
            if record and session and session.sourceDetached then
                restoreDetachedBodyDragProxy(record, session)
                persistentDataChanged()
            end
            bodyDragSessions[targetSteamId] = nil
            pendingBodyMoves[targetSteamId] = nil
        end
    end
end

local function isBodyBeingDragged(record)
    return getBodyDragSession(record) ~= nil
end

local function refreshBodyDragSession(player, args)
    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    local record = targetSteamId and records[targetSteamId] or nil
    local session = record and getBodyDragSession(record) or nil
    if not session or args.sessionToken ~= session.token
        or not sameSteamId(session.moverSteamId, OS.getSteamId(player)) then return end

    session.expiresAt = nowSeconds() + BODY_DRAG_SESSION_SECONDS
    if session.sourceDetached and isSleepingRecord(record) and not record.adminVisualRemoved then
        local square=player:getSquare()
        if square then
            setFloorPlacement(record,square)
            persistentDataChanged()
        end
    end
end

local function confirmBodyDragPickup(player, args)
    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    local record = targetSteamId and records[targetSteamId] or nil
    local session = record and getBodyDragSession(record) or nil
    if not session or args.sessionToken ~= session.token
        or not sameSteamId(session.moverSteamId, OS.getSteamId(player)) then return end
    if session.sourceDetached then
        session.expiresAt = nowSeconds() + BODY_DRAG_SESSION_SECONDS
        return
    end

    local proxy = detachBodyDragProxy(record)
    if not proxy then
        clearBodyDragSession(record)
        bodyDragResult(player, "The sleeping survivor is no longer available.", false, targetSteamId)
        return
    end
    session.expiresAt = nowSeconds() + BODY_DRAG_SESSION_SECONDS
    persistentDataChanged()
end

local function queueBodyDragMove(player, record, square)
    if not player or not record or not record.steamId or not square then return false end

    local key = tostring(record.steamId)
    local session = bodyDragSessions[key]
    if not session then return false end

    -- The native dragging action is visual/client-side in multiplayer.  Its
    -- temporary zombie/corpse is not guaranteed to be replicated to the
    -- server, so waiting for it here can leave the authoritative proxy at the
    -- old location and produce two visible bodies.  Reconcile on the next
    -- server tick instead: the client has already completed its release event
    -- and this server remains the sole authority for the persistent corpse.
    session.finishing = true
    session.expiresAt = nowSeconds() + BODY_DRAG_SESSION_SECONDS
    pendingBodyMoves[key] = {
        player = player,
        moverSteamId = OS.getSteamId(player),
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        dueAt = nowSeconds(),
    }
    return true
end

local function processPendingBodyMoves()
    local current = nowSeconds()
    for targetSteamId, move in pairs(pendingBodyMoves) do
        if not move or numberOr(move.dueAt, 0) > current then
            -- The client has not yet finished the native release animation.
        else
            pendingBodyMoves[targetSteamId] = nil
            local record = records[targetSteamId]
            local player = move.player or runtimePlayers[tostring(move.moverSteamId or "")]
            local square = getWorld():getCell():getGridSquare(move.x, move.y, move.z)

            if not record or not isSleepingRecord(record) or record.despawned or not square then
                local session = record and bodyDragSessions[targetSteamId] or nil
                if record and session then restoreDetachedBodyDragProxy(record, session) end
                if record then clearBodyDragSession(record) end
                if record then persistentDataChanged() end
                if player then bodyDragResult(player, "That sleeping survivor can no longer be moved.", false, targetSteamId) end
            elseif removeTrackedObject(record, square) then
                local session = bodyDragSessions[targetSteamId]
                local visualSource = session and session.proxy or nil
                setFloorPlacement(record, square)
                record.objectCreated = nil
                record.corpseFailure = nil
                record.corpseFailureReported = nil
                -- A deliberate move is not a failed automatic rebuild.
                record.corpseRebuilds = 0
                local created = createOfflineCorpseObject(record, visualSource)
                if created then
                    if session then
                        local movedAwayFromSource = session.sourceX ~= nil
                            and (session.sourceX ~= record.objectX or session.sourceY ~= record.objectY or session.sourceZ ~= record.objectZ)
                        if movedAwayFromSource then
                            record.dragSourceX = session.sourceX
                            record.dragSourceY = session.sourceY
                            record.dragSourceZ = session.sourceZ
                            record.dragSourceObjectId = session.sourceObjectId
                            record.dragSourceEpoch = session.sourceEpoch
                            record.dragSourceRevision = session.sourceRevision
                            record.dragSourceCleanupUntil = nowSeconds() + 15
                        else
                            record.dragSourceX, record.dragSourceY, record.dragSourceZ = nil, nil, nil
                            record.dragSourceObjectId = nil
                            record.dragSourceCleanupUntil = nil
                        end
                        session.proxy = nil
                    end
                    clearBodyDragSession(record)
                else
                    -- Keep a disconnected player represented even if a modded
                    -- visual fails to rebuild at the final square.
                    restoreDetachedBodyDragProxy(record, session)
                    clearBodyDragSession(record)
                end
                persistentDataChanged()
                if player then
                    bodyDragResult(player, created and "Sleeping survivor moved." or "The sleeping survivor could not be moved safely.", created ~= nil, targetSteamId)
                end
            else
                local session = record and bodyDragSessions[targetSteamId] or nil
                if record and session then restoreDetachedBodyDragProxy(record, session) end
                if record then clearBodyDragSession(record) end
                if record then persistentDataChanged() end
                if player then bodyDragResult(player, "The sleeping survivor could not be moved safely.", false, targetSteamId) end
            end
        end
    end
end

setFloorPlacement = function(record, square)
    record.x = square:getX() + 0.5
    record.y = square:getY() + 0.5
    record.z = square:getZ()
    record.objectX = square:getX()
    record.objectY = square:getY()
    record.objectZ = square:getZ()
    record.renderX = record.x
    record.renderY = record.y
    record.placement = "floor"
    record.bedFacing, record.bedAxis, record.bedSurfaceOffset = nil, nil, nil
    record.sofaFacing, record.sofaAxis, record.sofaSurfaceOffset = nil, nil, nil
    record.reconnectX, record.reconnectY, record.reconnectZ = record.x, record.y, record.z
end

local function applyPlayerPosition(player, x, y, z)
    -- Ask the owning client to move itself. On a dedicated server the client is
    -- authoritative over its own position, so a server-only teleport is simply
    -- overwritten and the player wakes up where they logged out.
    sendTo(player, OS.COMMAND_TELEPORT_TO_BODY, { x = x, y = y, z = z })

    local square = getWorld():getCell():getGridSquare(gridCoordinate(x), gridCoordinate(y), gridCoordinate(z))
    if not square then return false end

    local moved = pcall(function() player:teleportTo(x, y, z) end)
    if not moved then
        moved = pcall(function()
            player:setX(x)
            player:setY(y)
            player:setZ(z)
            player:setNextX(x)
            player:setNextY(y)
            player:setCurrentSquare(square)
        end)
    end
    return moved == true
end

-- The server rebuilds the character from players.db around the same time this
-- script sees the reconnect, and that load carries the original logout
-- position. A single teleport here is silently overwritten, which is why a
-- dragged survivor still woke up where they logged out. Keep reapplying the
-- destination until the player actually settles on it.
local function restoreMovedPlayerPosition(player, record)
    if not player or not record or record.reconnectX == nil or record.reconnectY == nil or record.reconnectZ == nil then return false end

    local x = numberOr(record.reconnectX, 0)
    local y = numberOr(record.reconnectY, 0)
    local z = numberOr(record.reconnectZ, 0)
    local moved = applyPlayerPosition(player, x, y, z)

    -- The coordinates stay on the record until the move is confirmed, so a
    -- failed or overwritten attempt is simply retried.
    pendingRepositions[tostring(record.steamId)] = {
        x = x,
        y = y,
        z = z,
        untilAt = nowSeconds() + RECONNECT_REPOSITION_SECONDS,
    }
    return moved
end

local function finishDragBeforeReconnect(record)
    local session=bodyDragSessions[tostring(record.steamId)]
    if session then
        local players=getOnlinePlayers()
        for i=0,players:size()-1 do
            local mover=players:get(i)
            if sameSteamId(OS.getSteamId(mover),session.moverSteamId) then
                if session.sourceDetached and mover:getSquare() then setFloorPlacement(record,mover:getSquare()) end
                sendTo(mover,"CancelRemovedBodyDrag",{targetSteamId=tostring(record.steamId)})
            end
        end
        if session.sourceDetached then
            record.dragSourceX,record.dragSourceY,record.dragSourceZ=session.sourceX,session.sourceY,session.sourceZ
            record.dragSourceObjectId=session.sourceObjectId
            record.dragSourceEpoch,record.dragSourceRevision=session.sourceEpoch,session.sourceRevision
            broadcastStaleBodyCleanup(makeStaleBodyCleanupArgs(record.steamId,
                record.reconnectX or record.x,record.reconnectY or record.y,record.reconnectZ or record.z,
                nil,record.bodyEpoch or 0,record.bodyRevision or 0))
        end
    end
    clearBodyDragSession(record)
end

local function processPendingRepositions(connected)
    local current = nowSeconds()
    for steamId, move in pairs(pendingRepositions) do
        local player = runtimePlayers[steamId]
        if not connected[steamId] or not player then
            pendingRepositions[steamId] = nil
        else
            local dx = numberOr(player:getX(), 0) - move.x
            local dy = numberOr(player:getY(), 0) - move.y
            local sameFloor = math.floor(numberOr(player:getZ(), -999)) == math.floor(move.z)
            local settled = sameFloor and (dx * dx) + (dy * dy) <= 0.75

            if settled then
                pendingRepositions[steamId] = nil
                local record = records[steamId]
                if record then
                    record.reconnectX, record.reconnectY, record.reconnectZ = nil, nil, nil
                    persistentDataChanged()
                end
            elseif current >= numberOr(move.untilAt, 0) then
                -- Give up rather than fight the player forever; the saved
                -- coordinates remain so a later reconnect can try again.
                pendingRepositions[steamId] = nil
                print("[Offline Survivor] Could not settle reconnect position for " .. tostring(steamId))
            else
                applyPlayerPosition(player, move.x, move.y, move.z)
            end
        end
    end
end

local function isCurrentOfflineCorpse(object)
    if not isNativeCorpse(object) then return false end
    local ok, data = pcall(function() return object:getModData() end)
    return ok and data and data[OS.OFFLINE_MARKER] and data.renderer == OS.RENDERER
end

-- Handles update migration as well as a corpse removed by external game
-- systems. A loaded square with no matching object is safe to recreate.
local function refreshTrackedObject(record)
    if not record.objectCreated then return false end
    local object = findOfflineObject(record)
    if object and isCurrentOfflineCorpse(object) then
        H.freezeAge(object)
        record.missingObjectTicks = nil
        return false
    end

    if object then
        if not removeTrackedObject(record) then return false end
    else
        if not getRecordSquare(record) then return false end

        -- The tile is loaded but the body was not matched. That is usually a
        -- transient miss, not a lost body, so require several consecutive
        -- failures before allowing a rebuild.
        local missing = numberOr(record.missingObjectTicks, 0) + 1
        record.missingObjectTicks = missing
        if missing < MISSING_OBJECT_CONFIRM_TICKS then return false end
    end

    record.missingObjectTicks = nil
    record.objectCreated = nil
    runtimeObjects[record.steamId] = nil
    return true
end

local function getInventory(player)
    if not player then return nil end
    local ok, inventory = pcall(function() return player:getInventory() end)
    if ok then return inventory end
    return nil
end

-- The real zombie-death corpse takes ownership of the disconnected player's
-- inventory. Clear the temporary reconnect copy before forcing its native
-- death, otherwise Project Zomboid can create a second corpse with duplicates.
local function clearPlayerItemsForForcedDeath(player)
    local inventory = getInventory(player)
    if inventory then pcall(function() inventory:clear() end) end
    pcall(function() player:clearWornItems() end)
    pcall(function() player:clearAttachedItems() end)
    pcall(function() player:setPrimaryHandItem(nil) end)
    pcall(function() player:setSecondaryHandItem(nil) end)
end

local function getContainerItems(container)
    if not container then return nil end
    local ok, items = pcall(function() return container:getItems() end)
    if ok then return items end
    return nil
end

local function isInventoryContainer(item)
    if not item then return false end
    local ok, result = pcall(function() return item:IsInventoryContainer() end)
    return ok and result == true
end

local function getInnerContainer(item)
    if not isInventoryContainer(item) then return nil end

    local ok, container = pcall(function() return item:getInventory() end)
    if ok and container then return container end

    ok, container = pcall(function() return item:getItemContainer() end)
    if ok and container then return container end
    return nil
end

local function isClothing(item)
    if not item then return false end
    local ok, result = pcall(function() return item:IsClothing() end)
    return ok and result == true
end

local function isWornItem(player, item)
    if not player or not item then return false end
    local ok, worn = pcall(function() return player:getWornItems() end)
    if not ok or not worn then return false end

    local containsOk, result = pcall(function() return worn:contains(item) end)
    return containsOk and result == true
end

local function itemName(item)
    local ok, name = pcall(function() return item:getName() end)
    if ok and name and tostring(name) ~= "" then return tostring(name) end

    ok, name = pcall(function() return item:getFullType() end)
    if ok and name then return tostring(name) end
    return "Item"
end

local function itemId(item)
    local ok, id = pcall(function() return item:getID() end)
    if not ok or id == nil then return nil end
    return tostring(id)
end

local function itemFullType(item)
    local ok, fullType = pcall(function() return item:getFullType() end)
    return ok and tostring(fullType or "") or ""
end

local function itemWeight(item)
    local ok, weight = pcall(function() return item:getActualWeight() end)
    if ok and weight ~= nil then return numberOr(weight, 0) end

    ok, weight = pcall(function() return item:getWeight() end)
    if ok and weight ~= nil then return numberOr(weight, 0) end
    return 0
end

local function itemCondition(item)
    local ok, condition = pcall(function() return item:getCondition() end)
    if ok and condition ~= nil then return numberOr(condition, 0) end
    return 0
end

local function isLootableItem(player, item)
    -- Bags themselves and every clothing item are protected.  Contents of a
    -- bag are scanned separately and remain eligible for theft.
    if isInventoryContainer(item) then return false end
    if isClothing(item) then return false end
    if isWornItem(player, item) then return false end
    return itemId(item) ~= nil
end

local function addLootInfo(result, item, path)
    local id = itemId(item)
    if not id then return end

    result[#result + 1] = {
        itemId = id,
        fullType = itemFullType(item),
        displayName = itemName(item),
        weight = itemWeight(item),
        condition = itemCondition(item),
        containerPath = path,
    }
end

local function buildLootSnapshot(player)
    local result = {}
    local root = getInventory(player)
    if not root then return result end

    local visited = {}
    local function scan(container, path, depth)
        if not container or visited[container] or depth > 8 then return end
        visited[container] = true

        local items = getContainerItems(container)
        if not items then return end

        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local inner = getInnerContainer(item)
            if inner then
                scan(inner, path .. " / " .. itemName(item), depth + 1)
            elseif isLootableItem(player, item) then
                addLootInfo(result, item, path)
            end
        end
    end

    scan(root, "Body", 0)
    table.sort(result, function(left, right)
        return tostring(left.displayName) < tostring(right.displayName)
    end)
    return result
end

local function isPendingTheft(record, wantedId)
    for _, entry in ipairs(record.pendingThefts or {}) do
        if sameSteamId(entry.itemId, wantedId) then return true end
    end
    return false
end

local function removeSnapshotItem(record, wantedId)
    local items = record.lootItems or {}
    for index = #items, 1, -1 do
        if sameSteamId(items[index].itemId, wantedId) then
            table.remove(items, index)
        end
    end
end

local function removePendingTheft(record, wantedId)
    local pending = record.pendingThefts or {}
    for index = #pending, 1, -1 do
        if sameSteamId(pending[index].itemId, wantedId) then
            table.remove(pending, index)
        end
    end
    if #pending == 0 then record.pendingThefts = nil end
end

local function addPendingTheft(record, wantedId, thiefSteamId)
    if isPendingTheft(record, wantedId) then return end
    record.pendingThefts = record.pendingThefts or {}
    record.pendingThefts[#record.pendingThefts + 1] = {
        itemId = tostring(wantedId),
        thiefSteamId = tostring(thiefSteamId),
        atMs = nowMs(),
    }
end

local function findItemInContainer(container, wantedId)
    if not container then return nil end
    local numericId = tonumber(wantedId)
    if not numericId then return nil end

    local ok, item = pcall(function() return container:getItemWithIDRecursiv(numericId) end)
    if ok and item then return item end
    return nil
end

local function playerHasEquippedItem(player, item)
    if not player or not item then return false end
    local ok, result = pcall(function() return player:isEquipped(item) end)
    return ok and result == true
end

local function markInventoryDirty(container)
    if not container then return end
    pcall(function() container:setDrawDirty(true) end)
end

local function removeItemFromPlayer(player, item)
    if not player or not item then return false end

    local ok, source = pcall(function() return item:getContainer() end)
    if not ok or not source then return false end

    local equipped = playerHasEquippedItem(player, item)
    if equipped then pcall(function() player:removeFromHands(item) end) end

    ok = pcall(function() source:Remove(item) end)
    if not ok then return false end

    pcall(sendRemoveItemFromContainer, source, item)
    if equipped then pcall(sendEquip, player) end
    markInventoryDirty(source)
    return true
end

-- The corpse needs cloned InventoryItems for the native renderer to keep
-- modded clothing/backpacks visible. They are never loot: normal clients are
-- blocked in OS_Client and this server-side sweep removes any clone that a
-- modified client somehow transferred into a real player's inventory.
local function isVisualClone(item)
    if not item then return false end
    local ok, data = pcall(function() return item:getModData() end)
    return ok and data and data[OS.VISUAL_CLONE_MARKER] == true
end

local function purgeVisualClones(player)
    local root = getInventory(player)
    if not root then return end

    local visited = {}
    local function scan(container, depth)
        if not container or visited[container] or depth > 8 then return end
        visited[container] = true
        local items = getContainerItems(container)
        if not items then return end

        for index = items:size() - 1, 0, -1 do
            local item = items:get(index)
            if isVisualClone(item) then
                removeItemFromPlayer(player, item)
            else
                scan(getInnerContainer(item), depth + 1)
            end
        end
    end
    scan(root, 0)
end

local function moveItemToRobber(target, robber, item)
    if not target or not robber or not item then return false end

    local destination = getInventory(robber)
    if not destination then return false end

    local ok, source = pcall(function() return item:getContainer() end)
    if not ok or not source then return false end

    local equipped = playerHasEquippedItem(target, item)
    if equipped then pcall(function() target:removeFromHands(item) end) end

    -- AddItem(InventoryItem) keeps the original instance, including modded
    -- item data, and detaches it from its old ItemContainer.
    local added
    ok, added = pcall(function() return destination:AddItem(item) end)
    if not ok or not added then return false end

    pcall(sendRemoveItemFromContainer, source, item)
    pcall(sendAddItemToContainer, destination, item)
    if equipped then pcall(sendEquip, target) end
    markInventoryDirty(source)
    markInventoryDirty(destination)
    return true
end

-- The exact InventoryItem instance is available while the disconnected
-- player remains in this server process.  After a server restart that Java
-- object no longer exists, but the persistent loot snapshot still does.  In
-- that case create one replacement item for the thief and record the source
-- item id for removal when its owner next reconnects.  This keeps the saved
-- player inventory authoritative without retaining IsoPlayer objects forever.
local function createSnapshotLootItem(info)
    if not info or not instanceItem then return nil end
    local fullType = tostring(info.fullType or "")
    if fullType == "" then return nil end

    local ok, item = pcall(function() return instanceItem(fullType) end)
    if not ok or not item then return nil end

    local condition = tonumber(info.condition)
    if condition ~= nil then
        pcall(function()
            local maxCondition = tonumber(item:getConditionMax()) or 0
            if maxCondition > 0 then
                item:setCondition(math.max(0, math.min(math.floor(condition), maxCondition)))
            end
        end)
    end
    return item
end

local function moveSnapshotItemToRobber(robber, info)
    local destination = getInventory(robber)
    local item = createSnapshotLootItem(info)
    if not destination or not item then return false end

    local ok, added = pcall(function() return destination:AddItem(item) end)
    if not ok or not added then return false end

    pcall(sendAddItemToContainer, destination, item)
    markInventoryDirty(destination)
    return true
end

local function reconcilePendingThefts(record, player)
    local pending = record.pendingThefts
    if not pending or #pending == 0 then return end

    local inventory = getInventory(player)
    if not inventory then return end

    for index = #pending, 1, -1 do
        local entry = pending[index]
        local item = findItemInContainer(inventory, entry.itemId)
        -- If it is absent, the save already reflects the transfer.  If it is
        -- present, remove the saved copy before this player can use it.
        if not item or removeItemFromPlayer(player, item) then
            table.remove(pending, index)
        end
    end
    if #pending == 0 then record.pendingThefts = nil end
end

local function discardPendingEntriesFromSnapshot(record)
    for _, entry in ipairs(record.pendingThefts or {}) do
        removeSnapshotItem(record, entry.itemId)
    end
end

-- B42 gives every connected player a role, and an ordinary one is "user" or
-- "priority" -- not "none". Treating anything other than "none" as staff marked
-- the whole server as administrators, so this matches the staff roles by name.
local STAFF_ROLES = {
    admin = true,
    moderator = true,
    overseer = true,
    gm = true,
    observer = true,
}

local function isStaffPlayer(player)
    if not player then return false end
    local ok, accessLevel = pcall(function() return player:getAccessLevel() end)
    if not ok or accessLevel == nil then return false end
    return STAFF_ROLES[tostring(accessLevel):lower()] == true
end

-- JaxeRevival keeps a connected IsoPlayer downed by storing this flag on the
-- player's ModData. Do not require or call JaxeRevival: that would make load
-- order matter. Offline Survivor owns only its disconnected proxy.
local function isJaxeRevivalActive()
    if not getActivatedMods then return false end
    local active = nil
    local ok = pcall(function() active = getActivatedMods() end)
    if not ok or not active then return false end

    local present = false
    pcall(function()
        present = active:contains("JaxeRevival[OG]") == true or active:contains("JaxeRevival") == true
    end)
    return present
end

local function captureJaxeRevivalState(record, player)
    if not record then return end
    record.jaxeRevivalIncapacitated = nil
    if not player or not isJaxeRevivalActive() then return end

    local data = nil
    local ok = pcall(function() data = player:getModData() end)
    if ok and data and data.JaxeRevival_Incapacitated == true then
        record.jaxeRevivalIncapacitated = true
    end
end

-- JaxeRevival owns the health state of a player who was already incapacitated
-- before disconnecting. The Offline Survivor proxy remains visible,
-- searchable and movable, but optional offline deaths do not overwrite that
-- revive workflow.
local function isJaxeRevivalProtected(record)
    return record and record.jaxeRevivalIncapacitated == true
        and isJaxeRevivalActive()
end

local function shouldBlockAdminOfflineBody(record)
    -- No body for someone who logged out inside a vehicle: there is no floor
    -- tile they legitimately occupy, so the corpse fell out onto the road.
    if record.inVehicle == true then return true end

    return OS.getOption("BlockAdminOfflineBodies", true) ~= false
        and record.adminBody == true
        and record.testBody ~= true
end

-- The administrator test body was removed. Any record left in that state by an
-- earlier build is cleaned up by the maintenance pass below.
local function isAdminTestBodyActive(player)
    return false
end

isSleepingRecord = function(record)
    return record and (record.state == "offline" or record.state == "test_offline")
        and record.testDefeated ~= true
end

local function markOffline(record)
    if record.state == "offline" then return end

    record.state = "offline"
    record.bodyEpoch = numberOr(record.bodyEpoch, 0) + 1
    record.bodyRevision = 0
    record.adminVisualRemoved = nil
    record.testBody = nil
    record.offlineAt = nowSeconds()
    chooseCorpsePlacement(record)
    chooseCorpsePose(record)
    record.despawned = nil
    record.corpseFailure = nil
    record.corpseFailureReported = nil
    -- A fresh logout starts its rebuild budget over.
    record.corpseRebuilds = nil
    record.missingObjectTicks = nil
    record.dragSourceX, record.dragSourceY, record.dragSourceZ = nil, nil, nil
    record.dragSourceObjectId = nil
    record.dragSourceCleanupUntil = nil

    local player = runtimePlayers[record.steamId]
    captureJaxeRevivalState(record, player)
    record.adminBody = isStaffPlayer(player) == true or nil
    record.lootItems = buildLootSnapshot(player)
    record.lootSnapshotAtMs = nowMs()
    record.lootSnapshotAvailable = player ~= nil
    discardPendingEntriesFromSnapshot(record)

    if shouldBlockAdminOfflineBody(record) then
        record.bodySuppressed = true
        record.objectCreated = nil
        print("[OfflineSurvivor V2] Offline body suppressed for administrator " .. tostring(record.username))
    else
        record.bodySuppressed = nil
        print("[OfflineSurvivor V2] Player disconnected: " .. tostring(record.username))
        createOfflineCorpseObject(record)
    end
    persistentDataChanged()
end

-- Beta-only test body. It uses the same visual proxy and interaction routes as
-- a disconnected player, but its inventory and life are never changed.
local function markAdminTestOffline(record)
    -- trackOnlinePlayer() calls this repeatedly while the administrator is
    -- hidden/noclipping. Once a valid proxy exists, leave it alone. A new
    -- test (or a missing proxy) goes through the cleanup below instead.
    if record.state == "test_offline" and record.objectCreated and findOfflineObject(record) then return end

    clearBodyDragSession(record)
    -- The test body is a disposable proxy. Always remove every existing
    -- proxy for this record before creating it again; this also cleans up
    -- duplicate test bodies left by an interrupted earlier test.
    removeTrackedObject(record)
    runtimeObjects[record.steamId] = nil
    record.objectCreated = nil
    record.pendingRemoval = nil
    record.dragSourceX, record.dragSourceY, record.dragSourceZ = nil, nil, nil
    record.dragSourceObjectId = nil
    record.dragSourceCleanupUntil = nil
    record.state = "test_offline"
    record.testBody = true
    record.testDefeated = nil
    record.testDeathCause = nil
    record.testDeathAt = nil
    record.offlineAt = nowSeconds()
    chooseCorpsePlacement(record)
    chooseCorpsePose(record)
    record.despawned = nil
    record.corpseFailure = nil
    record.corpseFailureReported = nil
    record.adminBody = nil
    record.bodySuppressed = nil

    local player = runtimePlayers[record.steamId]
    record.lootItems = buildLootSnapshot(player)
    record.lootSnapshotAtMs = nowMs()
    record.lootSnapshotAvailable = player ~= nil
    discardPendingEntriesFromSnapshot(record)
    createOfflineCorpseObject(record)
    print("[OfflineSurvivor V2] Administrator test body created for " .. tostring(record.username))
    persistentDataChanged()
end

local function restoreRecord(record, player)
    local wasTestBody = record.testBody == true
    broadcastStaleBodyCleanup(makeStaleBodyCleanupArgs(record.steamId,
        record.objectX or record.reconnectX or record.x,
        record.objectY or record.reconnectY or record.y,
        record.objectZ or record.reconnectZ or record.z,
        nil, record.bodyEpoch or 0, record.bodyRevision or 0))
    local staleSourceCleanup = nil
    if record.dragSourceX ~= nil and record.dragSourceY ~= nil and record.dragSourceZ ~= nil then
        staleSourceCleanup = makeStaleBodyCleanupArgs(
            record.steamId,
            record.dragSourceX,
            record.dragSourceY,
            record.dragSourceZ,
            record.dragSourceObjectId,
            record.dragSourceEpoch,
            record.dragSourceRevision
        )
        -- The server normally removed this source within the initial 15-second
        -- drag window. Sweep it again at reconnect in case a late native drag
        -- object was published after that window.
        removeOfflineObjectsNear(record, record.dragSourceX, record.dragSourceY, record.dragSourceZ)
    end
    local removed = removeTrackedObject(record)
    record.pendingRemoval = not removed
    if removed then
        record.objectX, record.objectY, record.objectZ, record.objectCreated = nil, nil, nil, nil
        record.placement, record.bedFacing, record.bedAxis, record.bedSurfaceOffset = nil, nil, nil, nil
        record.sofaFacing, record.sofaAxis, record.sofaSurfaceOffset = nil, nil, nil
        record.corpseDirection, record.fallOnFront = nil, nil
    end
    record.state = "online"
    record.offlineAt = nil
    record.adminVisualRemoved = nil
    record.despawned = nil
    record.corpseFailure = nil
    record.corpseFailureReported = nil
    record.corpseRebuilds = nil
    record.missingObjectTicks = nil
    record.testBody = nil
    record.testDefeated = nil
    record.testDeathCause = nil
    record.testDeathAt = nil
    record.dragSourceX, record.dragSourceY, record.dragSourceZ = nil, nil, nil
    record.dragSourceObjectId = nil
    record.dragSourceCleanupUntil = nil
    record.adminBody = nil
    record.bodySuppressed = nil
    record.jaxeRevivalIncapacitated = nil
    if player and staleSourceCleanup then
        sendTo(player, OS.COMMAND_CLEANUP_STALE_BODY, staleSourceCleanup)
    end
    if wasTestBody then
        record.reconnectX, record.reconnectY, record.reconnectZ = nil, nil, nil
    end
end

-- The server creates a fresh player object from players.db before this script
-- sees a reconnect. Queue the death briefly so the saved state cannot overwrite
-- the zombie death and reintroduce the victim's inventory.
local function applyZombieDeathOnReconnect(record, player)
    local steamId = tostring(record.steamId)
    local pending = pendingZombieDeaths[steamId]
    if pending then
        local hadConnectedPlayer = pending.player ~= nil
        pending.player = player
        if pending.phase == "kill" and not hadConnectedPlayer then
            pending.dueAt = nowSeconds() + 2
        end
        return
    end

    reconcilePendingThefts(record, player)
    -- The victim was offline when the real corpse replaced its proxy, so it
    -- missed the broadcast cleanup sent to existing observers. Queue it now
    -- for this client as it finishes loading the map.
    sendTo(player, OS.COMMAND_CLEANUP_STALE_BODY, makeRecordedStaleBodyCleanupArgs(record))
    -- A death owns the body's position from here on. Drop any drag reposition
    -- so the two cannot fight over where this player stands.
    pendingRepositions[steamId] = nil
    pendingZombieDeaths[steamId] = {
        player = player,
        dueAt = nowSeconds() + 2,
        phase = "kill",
    }
    print("[Offline Survivor] Queued zombie death for reconnecting player " .. tostring(player:getUsername()))
end

local function trackOnlinePlayer(player)
    local steamId = OS.getSteamId(player)
    if not steamId then return end

    if not OS.isEnabled() then
        local zombieDeathRecord = records[steamId]
        if zombieDeathRecord and zombieDeathRecord.state == "zombie_killed" then
            runtimePlayers[steamId] = player
            applyZombieDeathOnReconnect(zombieDeathRecord, player)
            zombieDeathRecord.username = player:getUsername()
            zombieDeathRecord.lastSeen = nowSeconds()
            records[steamId] = zombieDeathRecord
            persistentDataChanged()
        end
        return
    end

    local hadRecord = records[steamId] ~= nil
    local record = records[steamId] or { steamId = steamId }
    local previousState = record.state
    runtimePlayers[steamId] = player
    local adminTestActive = isAdminTestBodyActive(player)

    -- A real reconnection must reconcile saved theft before control returns.
    if previousState == "offline" then
        finishDragBeforeReconnect(record)
        restoreMovedPlayerPosition(player, record)
        reconcilePendingThefts(record, player)
        restoreRecord(record, player)
    elseif previousState == "zombie_killed" then
        applyZombieDeathOnReconnect(record, player)
    elseif previousState == "test_offline" then
        if adminTestActive then
            records[steamId] = record
            return
        end
        clearBodyDragSession(record)
        restoreRecord(record, player)
    end

    record.username = player:getUsername()
    record.x = player:getX()
    record.y = player:getY()
    record.z = player:getZ()
    record.direction = tostring(player:getDir())
    record.lastSeen = nowSeconds()
    -- Someone who logs out inside a vehicle has no valid tile to lie on: the
    -- body ended up dumped on the road beside the car.
    record.inVehicle = nil
    pcall(function()
        if player:getVehicle() ~= nil then record.inVehicle = true end
    end)

    local playerIsDead = false
    pcall(function() playerIsDead = player:isDead() == true end)
    if playerIsDead then
        -- Do not create a second sleeping survivor while this player is on
        -- the native death/respawn screen.
        if pendingZombieDeaths[steamId] then
            records[steamId] = record
            return
        end
        record.state = "dead"
        records[steamId] = record
        return
    end

    if record.state == "zombie_killed" or pendingZombieDeaths[steamId] then
        records[steamId] = record
        return
    end

    if adminTestActive then
        markAdminTestOffline(record)
        records[steamId] = record
        return
    end

    record.state = "online"
    record.lootItems = nil
    record.lootSnapshotAtMs = nil
    record.lootSnapshotAvailable = nil
    records[steamId] = record

    if previousState == "offline" or previousState == "zombie_killed" or previousState == "test_offline" or not hadRecord then persistentDataChanged() end
end

local function scanOnlinePlayers()
    local connected = {}
    local players = getOnlinePlayers()
    for index = 0, players:size() - 1 do
        local player = players:get(index)
        local steamId = OS.getSteamId(player)
        if steamId then
            connected[steamId] = true
            purgeVisualClones(player)
            trackOnlinePlayer(player)
        end
    end
    return connected
end

local function getMaxLootItems()
    local value = math.floor(numberOr(OS.getOption("LootMaxItems", 3), 3))
    return math.max(1, math.min(value, 20))
end

local function cooldownRemainingMs(steamId)
    local hours = math.max(0, numberOr(OS.getOption("LootCooldownHours", 24), 24))
    if hours <= 0 then return 0 end

    local lastLoot = numberOr(lootCooldowns[steamId], 0)
    local remaining = (lastLoot + (hours * 60 * 60 * 1000)) - nowMs()
    return math.max(0, remaining)
end

local function cooldownMessage(remainingMs)
    local minutes = math.max(1, math.ceil(remainingMs / 60000))
    local hours = math.floor(minutes / 60)
    local rest = minutes % 60
    if hours > 0 then
        return "You can search again in " .. hours .. "h " .. rest .. "min."
    end
    return "You can search again in " .. minutes .. " minute(s)."
end

local function isNearRecord(player, record)
    if not player or record.objectX == nil or record.objectY == nil or record.objectZ == nil then return false end

    local targetX = numberOr(record.renderX, record.objectX + 0.5)
    local targetY = numberOr(record.renderY, record.objectY + 0.5)
    local targetZ = numberOr(record.objectZ, 0)

    -- Measure against the corpse the player can actually see. After a drag, a
    -- bed/sofa placement or a rebuild, the saved coordinates can lag behind the
    -- live object, which rejected players who were standing right next to it.
    pcall(function()
        local proxy = findOfflineObject(record)
        if not proxy then return end
        targetX = numberOr(proxy:getX(), targetX)
        targetY = numberOr(proxy:getY(), targetY)
        targetZ = numberOr(proxy:getZ(), targetZ)
    end)

    if math.floor(numberOr(player:getZ(), -999)) ~= math.floor(targetZ) then return false end

    local radius = math.max(1, numberOr(OS.getOption("LootDistance", 2), 2))
    local dx = player:getX() - targetX
    local dy = player:getY() - targetY
    return (dx * dx) + (dy * dy) <= (radius * radius)
end

local function hasValidOfflineObject(record)
    if record and (record.adminVisualRemoved or H.ownerConnected(record)) then return false end
    if not isSleepingRecord(record) or record.despawned then return false end
    local object = findOfflineObject(record)
    if not object then return false end
    local data = object:getModData()
    return data and data[OS.OFFLINE_MARKER] and sameSteamId(data.steamId, record.steamId)
end

bodyDragResult = function(player, message, completed, targetSteamId)
    sendTo(player, OS.COMMAND_BODY_DRAG_RESULT, {
        message = message,
        completed = completed == true,
        targetSteamId = targetSteamId and tostring(targetSteamId) or nil,
    })
end

local function requestBodyDrag(player, args)
    if not OS.isEnabled() or OS.getOption("AllowBodyDragging", true) == false then
        bodyDragResult(player, "Dragging sleeping survivors is disabled.")
        return
    end

    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    local moverSteamId = OS.getSteamId(player)
    local record = targetSteamId and records[targetSteamId] or nil
    if not targetSteamId or not moverSteamId or not isSleepingRecord(record) or record.despawned then
        bodyDragResult(player, "That sleeping survivor is no longer available.")
        return
    end
    if not isNearRecord(player, record) then
        bodyDragResult(player, "Move closer to the sleeping survivor.")
        return
    end
    if isBodyBeingDragged(record) then
        bodyDragResult(player, "Another player is already dragging this survivor.")
        return
    end
    if not hasValidOfflineObject(record) then
        bodyDragResult(player, "The sleeping survivor is not ready to be dragged.")
        return
    end
    if not runtimePlayers[targetSteamId] then
        bodyDragResult(player, "This survivor cannot be moved after a server restart. It will be available again after its owner reconnects.")
        return
    end

    bodyDragSessions[targetSteamId] = {
        moverSteamId = moverSteamId,
        token = tostring(nowMs()) .. ":" .. tostring(nextSessionId),
        expiresAt = nowSeconds() + BODY_DRAG_SESSION_SECONDS,
        sourceDetached = false,
    }
    nextSessionId=nextSessionId+1
    sendTo(player, OS.COMMAND_START_BODY_DRAG, { targetSteamId = targetSteamId,
        sessionToken = bodyDragSessions[targetSteamId].token })
end

local function finishBodyDrag(player, args)
    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    local record = targetSteamId and records[targetSteamId] or nil
    local session = record and getBodyDragSession(record) or nil
    if not targetSteamId or not record or not session or args.sessionToken ~= session.token
        or not sameSteamId(session.moverSteamId, OS.getSteamId(player)) then
        bodyDragResult(player, "The dragging session has expired.", false, targetSteamId)
        return
    end
    if args and args.cancel == true then
        if not session.sourceDetached then detachBodyDragProxy(record) end
        local restored = restoreDetachedBodyDragProxy(record, session)
        clearBodyDragSession(record)
        persistentDataChanged()
        bodyDragResult(player, restored and "Dragging cancelled." or "The sleeping survivor could not be restored.", false, targetSteamId)
        return
    end

    -- In normal operation this was done when the client first entered the
    -- native dragging state. Falling back here keeps the server consistent if
    -- a fast client sends FinishBodyDrag before its pickup packet is processed.
    if not session.sourceDetached and not detachBodyDragProxy(record) then
        clearBodyDragSession(record)
        bodyDragResult(player, "The sleeping survivor is no longer available.", false, targetSteamId)
        return
    end

    local x = numberOr(args and args.x, nil)
    local y = numberOr(args and args.y, nil)
    local z = numberOr(args and args.z, nil)
    if x == nil or y == nil or z == nil or math.floor(player:getZ()) ~= math.floor(z) then
        restoreDetachedBodyDragProxy(record, session)
        clearBodyDragSession(record)
        persistentDataChanged()
        bodyDragResult(player, "The final body position is invalid.", false, targetSteamId)
        return
    end

    local dx = player:getX() - x
    local dy = player:getY() - y
    if (dx * dx) + (dy * dy) > 6.25 then
        restoreDetachedBodyDragProxy(record, session)
        clearBodyDragSession(record)
        persistentDataChanged()
        bodyDragResult(player, "The survivor must be beside you when you put it down.", false, targetSteamId)
        return
    end

    local square = getWorld():getCell():getGridSquare(gridCoordinate(x), gridCoordinate(y), gridCoordinate(z))
    if not square or not isSleepingRecord(record) or record.despawned then
        restoreDetachedBodyDragProxy(record, session)
        clearBodyDragSession(record)
        persistentDataChanged()
        bodyDragResult(player, "That sleeping survivor can no longer be moved.", false, targetSteamId)
        return
    end
    if not queueBodyDragMove(player, record, square) then
        restoreDetachedBodyDragProxy(record, session)
        clearBodyDragSession(record)
        persistentDataChanged()
        bodyDragResult(player, "The sleeping survivor could not be moved safely.", false, targetSteamId)
    else
        -- FinishBodyDrag is sent only after the client's native release delay.
        -- Reconcile now instead of waiting for the next one-second maintenance
        -- pass, so the protected server corpse replaces the local proxy at once.
        processPendingBodyMoves()
    end
end

local function buildAvailableLoot(record)
    local result = {}
    for _, info in ipairs(record.lootItems or {}) do
        if info and info.itemId and not isPendingTheft(record, info.itemId) then
            result[#result + 1] = {
                itemId = tostring(info.itemId),
                fullType = tostring(info.fullType or ""),
                displayName = tostring(info.displayName or "Item"),
                weight = numberOr(info.weight, 0),
                condition = numberOr(info.condition, 0),
                containerPath = tostring(info.containerPath or "Body"),
            }
        end
    end
    return result
end

local function makeAvailableItemMap(record)
    local map = {}
    for _, info in ipairs(record.lootItems or {}) do
        if info and info.itemId and not isPendingTheft(record, info.itemId) then
            map[tostring(info.itemId)] = info
        end
    end
    return map
end

local function denyLoot(player, message)
    sendTo(player, OS.COMMAND_LOOT_NOTICE, { message = message })
end

local function clearLootSession(steamId, sessionId)
    local session = lootSessions[steamId]
    if not session then return nil end
    if sessionId and tonumber(session.id) ~= tonumber(sessionId) then return nil end
    lootSessions[steamId] = nil
    return session
end

local function clearLootSessionsForTarget(targetSteamId)
    for looterSteamId, session in pairs(lootSessions) do
        if session and sameSteamId(session.targetSteamId, targetSteamId) then
            lootSessions[looterSteamId] = nil
        end
    end
end

-- A despawned sleeper has no world object and can no longer be searched. Keep
-- its small persistent record so reconnect handling remains correct, but drop
-- every runtime reference (especially the disconnected IsoPlayer) and the
-- one-time loot snapshot it no longer needs.
local function releaseDespawnedRuntimeState(record)
    if not record or not record.steamId then return false end

    local steamId = tostring(record.steamId)
    runtimeObjects[steamId] = nil
    runtimePlayers[steamId] = nil
    bodyDragSessions[steamId] = nil
    pendingBodyMoves[steamId] = nil
    lootSessions[steamId] = nil
    clearLootSessionsForTarget(steamId)

    local changed = record.lootItems ~= nil
        or record.lootSnapshotAtMs ~= nil
        or record.lootSnapshotAvailable ~= nil
        or record.jaxeRevivalIncapacitated ~= nil
    record.lootItems = nil
    record.lootSnapshotAtMs = nil
    record.lootSnapshotAvailable = nil
    record.jaxeRevivalIncapacitated = nil
    return changed
end

-- The proxy is visual-only. Once a zombie reaches it, replace it with a real
-- native player corpse so its inventory, clothing and later interactions use
-- the normal game rules instead of the protected offline-survivor UI.
local function replaceOfflineProxyWithZombieCorpse(record, victim, zombie)
    if not victim then return nil, "the disconnected player is no longer in memory" end
    local square = getRecordSquare(record)
    local proxy = findOfflineObject(record)
    if not square or not proxy then return nil, "the offline body is no longer available" end
    local staleProxyCleanup = makeStaleBodyCleanupArgsForObject(record, proxy)
    if not removeTrackedObject(record) then return nil, "unable to remove the offline body" end

    local createdRealCorpse
    local ok, corpse = pcall(function()
        local x, y = getCorpseRenderPosition(record, square)
        victim:setX(x)
        victim:setY(y)
        victim:setZ(getCorpseRenderZ(record, square))
        victim:setNextX(x)
        victim:setNextY(y)
        victim:setCurrentSquare(square)

        local direction = getCorpseDirection(record)
        if direction then victim:setForwardIsoDirection(direction) end
        victim:setFallOnFront(record.fallOnFront == true)
        victim:setKilledByFall(true)
        -- B42's die() does not return a body. dieNetwork() is the native death
        -- path that both records the kill and gives us the linked IsoDeadBody.
        -- Creating a second body manually loses that link and is what allowed
        -- duplicate/empty corpses to remain after a sleeping-player death.
        local realCorpse = victim:dieNetwork(zombie, nil, true, nil)
        if not realCorpse then error("the engine did not create the real zombie-death corpse") end
        createdRealCorpse = realCorpse
        applyCorpseDirection(realCorpse, direction)
        realCorpse:setFallOnFront(record.fallOnFront == true)
        realCorpse:setKilledByFall(true)
        realCorpse:setOutlineOnMouseover(true)
        -- dieNetwork already adds its native corpse to the world. A second
        -- addCorpse increments the engine corpse/sickness counters again.
        if not square:getStaticMovingObjects():contains(realCorpse) then
            square:addCorpse(realCorpse, false)
        end
        sendCorpse(realCorpse)
        return realCorpse
    end)

    runtimeObjects[record.steamId] = nil
    record.objectCreated = nil
    if not ok and createdRealCorpse then
        -- Native death is irreversible. Cosmetic/network failures after it
        -- must not roll back the sentence or rebuild a living visual proxy.
        print("[Offline Survivor] Post-death presentation failed: " .. tostring(corpse))
        corpse = createdRealCorpse
        ok = true
    end
    if not ok then
        print("[Offline Survivor] Zombie death corpse conversion failed for " .. tostring(record.username) .. ": " .. tostring(corpse))
        createOfflineCorpseObject(record)
        return nil, tostring(corpse)
    end

    record.realCorpseX = corpse:getX()
    record.realCorpseY = corpse:getY()
    record.realCorpseZ = corpse:getZ()
    if staleProxyCleanup then
        record.staleProxyX = staleProxyCleanup.x
        record.staleProxyY = staleProxyCleanup.y
        record.staleProxyZ = staleProxyCleanup.z
        record.staleProxyObjectId = staleProxyCleanup.objectId
        record.staleProxyEpoch = staleProxyCleanup.bodyEpoch
        record.staleProxyRevision = staleProxyCleanup.bodyRevision
        -- RemoveCorpse and AddCorpse use separate packets. Queue a strictly
        -- identified local cleanup after the replacement is known-good, so an
        -- old AddCorpse packet cannot resurrect the visual proxy.
        broadcastStaleBodyCleanup(staleProxyCleanup)
    end
    return corpse, nil
end

-- IsoDeadBody inherits getEatingZombies() from IsoMovingObject. The engine adds
-- a zombie to that list when it enters ZombieEatBodyState and removes it on
-- exit, so this reports who is genuinely feeding on the body right now.
local function countEatingZombies(proxy)
    local count = 0
    pcall(function()
        local eating = proxy:getEatingZombies()
        if eating then count = eating:size() end
    end)
    return count
end

local function firstEatingZombie(proxy)
    local eater = nil
    pcall(function()
        local eating = proxy:getEatingZombies()
        if eating and eating:size() > 0 then eater = eating:get(0) end
    end)
    return eater
end

-- A zombie already handed this body recently must be left alone. Re-assigning
-- it every server tick restarts its path and its eating state, which is what
-- made zombies stand up and drop back onto the corpse over and over.
local function zombieLureCooldownActive(zombie)
    local blocked = false
    pcall(function()
        local data = zombie:getModData()
        local lastAt = data and tonumber(data.offlineSurvivorLuredAt) or nil
        if lastAt and nowSeconds() - lastAt < OS.ZOMBIE_LURE_COOLDOWN_SECONDS then blocked = true end
    end)
    return blocked
end

local function markZombieLured(zombie)
    pcall(function()
        local data = zombie:getModData()
        if data then data.offlineSurvivorLuredAt = nowSeconds() end
    end)
end

local function isUsableZombie(zombie)
    if not zombie then return false end

    local isZombie = false
    pcall(function() isZombie = instanceof(zombie, "IsoZombie") end)
    if not isZombie then return false end

    -- Mirror the engine's own filter: updateSearchForCorpse ignores crawlers,
    -- toothless zombies and the temporary grapple surrogate too.
    local blocked = true
    pcall(function()
        blocked = zombie:isDead() == true
            or zombie:isNoTeeth() == true
            or zombie:isCrawling() == true
            or zombie:isReanimatedForGrappleOnly() == true
    end)
    return not blocked
end

local function zombieDistanceSq(zombie, bodyX, bodyY, bodyZ)
    if math.floor(numberOr(zombie:getZ(), -999)) ~= bodyZ then return nil end
    local dx = numberOr(zombie:getX(), -999) - bodyX
    local dy = numberOr(zombie:getY(), -999) - bodyY
    return (dx * dx) + (dy * dy)
end

local function isLurableZombie(zombie, bodyX, bodyY, bodyZ, radiusSq)
    if not isUsableZombie(zombie) then return false end
    if zombieLureCooldownActive(zombie) then return false end

    -- A zombie busy chasing someone, or already eating, is not re-targeted.
    local busy = false
    pcall(function() busy = zombie:getTarget() ~= nil or zombie:getEatBodyTarget() ~= nil end)
    if busy then return false end

    local distanceSq = zombieDistanceSq(zombie, bodyX, bodyY, bodyZ)
    if distanceSq == nil or distanceSq > radiusSq then return false end

    -- Keep steering until the zombie is inside the engine's own eating range.
    -- Past that point it is left entirely to vanilla, which decides when it
    -- feeds and for how long; commanding it there made it loop.
    return distanceSq > OS.ZOMBIE_EAT_DISTANCE_SQ
end

-- B42 zombies already hunt corpses on their own, but IsoZombie only runs that
-- search once checkForCorpseTimer counts 10000 frames down -- about five real
-- minutes at 30fps -- and the timer is reset whenever the zombie acquires a
-- target or reacts to a sound. That is why a zombie spawned next to a sleeping
-- survivor looked like it was ignoring the body.
--
-- Assigning bodyToEat skips only that timer. The engine still owns everything
-- else: it paths the zombie to the corpse, switches it into ZombieEatBodyState
-- on arrival, plays the kneeling and feeding animation with blood, and
-- replicates all of it through the native EatBody packet.
--
-- One pass over the zombie list serves both jobs: handing the body to nearby
-- idle zombies and reporting whoever is currently feeding on it. Scanning that
-- list twice per body per second was pure overhead on a populated server.
--
-- getEatingZombies() is only filled where the zombie is simulated, which in
-- multiplayer may be a client, so a zombie physically standing on the body also
-- counts as feeding. Returns that zombie, or nil.
local function serviceZombiesAtBody(proxy)
    local cell = getWorld() and getWorld():getCell() or nil
    local zombies = cell and cell:getZombieList() or nil
    if not zombies then return nil end

    local bodyX, bodyY, bodyZ = nil, nil, nil
    pcall(function()
        bodyX = numberOr(proxy:getX(), nil)
        bodyY = numberOr(proxy:getY(), nil)
        bodyZ = numberOr(proxy:getZ(), nil)
    end)
    if bodyX == nil or bodyY == nil or bodyZ == nil then return nil end

    -- The engine drops a body once three zombies feed on it, so never queue
    -- more than it will accept.
    local slots = OS.ZOMBIE_MAX_EATERS - countEatingZombies(proxy)
    local floorZ = math.floor(bodyZ)
    local radiusSq = OS.ZOMBIE_LURE_RADIUS * OS.ZOMBIE_LURE_RADIUS
    local devourer = firstEatingZombie(proxy)

    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        if isUsableZombie(zombie) then
            local distanceSq = zombieDistanceSq(zombie, bodyX, bodyY, floorZ)
            if distanceSq then
                if not devourer and distanceSq <= OS.ZOMBIE_CONTACT_DISTANCE_SQ then
                    devourer = zombie
                end
                if slots > 0 and distanceSq <= radiusSq and isLurableZombie(zombie, bodyX, bodyY, floorZ, radiusSq) then
                    -- Only hand over the body. IsoZombie.updateSearchForCorpse
                    -- already paths a zombie that has a bodyToEat and switches
                    -- it into the eating state on arrival. Issuing our own path
                    -- competed with that and left zombies stuck mid-animation.
                    local assigned = pcall(function() zombie:setBodyToEat(proxy) end)
                    if assigned then
                        markZombieLured(zombie)
                        slots = slots - 1
                    end
                end
            end
        end
    end
    return devourer
end

local function killOfflineSurvivorByZombie(record, zombie)
    if record.adminVisualRemoved or record.despawned or H.ownerConnected(record) then return end
    if not hasValidOfflineObject(record) then return false end

    if record.testBody == true then
        local proxy = findOfflineObject(record)
        if not proxy then return false end
        record.testDefeated = true
        record.testDeathCause = "zombie"
        record.testDeathAt = nowSeconds()
        removeTrackedObject(record)
        record.objectCreated = nil
        local defeatedProxy = createOfflineCorpseObject(record)
        if defeatedProxy and zombie then pcall(function() zombie:setEatBodyTarget(defeatedProxy, true) end) end
        persistentDataChanged()
        print("[Offline Survivor] Zombie defeated administrator test body for " .. tostring(record.username))
        return true
    end

    local previousState = record.state
    record.state = "zombie_killed"
    record.zombieDeath = { at = nowSeconds() }
    record.realCorpseCreated = nil
    local victim = runtimePlayers[record.steamId]
    if not victim then
        -- After a restart the previous IsoPlayer cannot be loaded through the
        -- public mod API. Persist the death and turn the saved player into a
        -- real corpse at this position on their next reconnect.
        local square = getRecordSquare(record)
        if square then
            local x, y = getCorpseRenderPosition(record, square)
            record.realCorpseX = x
            record.realCorpseY = y
            record.realCorpseZ = getCorpseRenderZ(record, square)
        end
        record.deferredDeath = true
        markOfflineProxyPendingDeath(record)
        clearLootSessionsForTarget(record.steamId)
        persistentDataChanged()
        local proxy = findOfflineObject(record)
        if proxy and zombie then pcall(function() zombie:setEatBodyTarget(proxy, true) end) end
        print("[Offline Survivor] Deferred zombie death for " .. tostring(record.username) .. " until reconnect")
        return true
    end

    record.deferredDeath = nil
    persistentDataChanged()

    local realCorpse, corpseReason = replaceOfflineProxyWithZombieCorpse(record, victim, zombie)
    if not realCorpse then
        record.state = previousState
        record.zombieDeath = nil
        record.realCorpseCreated = nil
        record.deferredDeath = nil
        persistentDataChanged()
        return false
    end

    clearLootSessionsForTarget(record.steamId)
    record.realCorpseCreated = true
    record.realCorpseAt = nowSeconds()
    persistentDataChanged()
    if zombie then pcall(function() zombie:setEatBodyTarget(realCorpse, true) end) end
    print("[Offline Survivor] " .. tostring(record.username) .. " was killed by zombies while offline")
    return true
end

local function isNearZombieFeedingProxy(player, proxy)
    if not player or not proxy then return false end

    local near = false
    pcall(function()
        local bodyZ = math.floor(numberOr(proxy:getZ(), -999))
        if math.floor(numberOr(player:getZ(), -998)) ~= bodyZ then return end
        local dx = player:getX() - proxy:getX()
        local dy = player:getY() - proxy:getY()
        local radius = OS.ZOMBIE_LURE_RADIUS + 2
        near = (dx * dx) + (dy * dy) <= (radius * radius)
    end)
    return near
end

-- The owning client can see the native ZombieEatBodyState.  The dedicated
-- server cannot reliably resolve the client's locally simulated zombie by ID.
-- Accept short, rate-limited reports only from a player standing beside the
-- exact marked offline body; the client reports only native eating state.
local function reportZombieFeeding(player, args)
    if not OS.isEnabled() or OS.getOption("AllowZombieDeaths", false) == false then return end

    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    local zombieId = args and args.zombieId ~= nil and tostring(args.zombieId) or nil
    if not targetSteamId or targetSteamId == "" or not zombieId or zombieId == "" or tonumber(zombieId) == nil then return end

    local record = records[targetSteamId]
    if not record or not isSleepingRecord(record) or record.despawned
        or isBodyBeingDragged(record) or isJaxeRevivalProtected(record) then return end

    local proxy = findOfflineObject(record)
    if not proxy or not isNearZombieFeedingProxy(player, proxy) then return end

    local claimedX = numberOr(args and args.x, nil)
    local claimedY = numberOr(args and args.y, nil)
    local claimedZ = numberOr(args and args.z, nil)
    local matchesProxy = false
    pcall(function()
        matchesProxy = claimedX ~= nil and claimedY ~= nil and claimedZ ~= nil
            and math.floor(claimedX) == math.floor(proxy:getX())
            and math.floor(claimedY) == math.floor(proxy:getY())
            and math.floor(claimedZ) == math.floor(proxy:getZ())
    end)
    if not matchesProxy then return end

    local reporterSteamId = OS.getSteamId(player)
    if not reporterSteamId then return end

    local current = nowSeconds()
    local reports = zombieFeedingReports[targetSteamId] or {}
    zombieFeedingReports[targetSteamId] = reports
    local key = tostring(reporterSteamId) .. ":" .. zombieId
    local previous = reports[key]
    if previous and current - numberOr(previous.at, 0) < OS.ZOMBIE_FEED_REPORT_SECONDS then return end
    reports[key] = { at = current }

    -- One diagnostic every ten seconds makes a dedicated-server test auditable
    -- without filling the console with one message per client tick.
    local lastLogged = numberOr(lastZombieFeedLog[targetSteamId], 0)
    if current - lastLogged >= 10 then
        lastZombieFeedLog[targetSteamId] = current
        print("[Offline Survivor] Confirmed zombie feeding on " .. tostring(record.username))
    end
end

local function hasFreshZombieFeedingReport(steamId, current)
    local reports = zombieFeedingReports[steamId]
    if not reports then return false end

    local fresh = false
    for key, report in pairs(reports) do
        if current - numberOr(report and report.at, 0) <= OS.ZOMBIE_FEED_REPORT_TTL_SECONDS then
            fresh = true
        else
            reports[key] = nil
        end
    end
    if not fresh then zombieFeedingReports[steamId] = nil end
    return fresh
end

-- A dedicated server can itself own a zombie. In that case no client report is
-- expected, but the native eating state is available directly on the corpse.
-- Require the exact target and native eating state: merely standing by a body is never
-- enough to advance the offline-death timer.
local function findServerZombieEatingProxy(proxy)
    local feeder = nil
    pcall(function()
        local eaters = proxy:getEatingZombies()
        if not eaters then return end
        for index = 0, eaters:size() - 1 do
            local zombie = eaters:get(index)
            local stateName = tostring(zombie:getCurrentStateName() or "")
            if isUsableZombie(zombie)
                and zombie:getEatBodyTarget() == proxy
                and stateName:find("ZombieEatBody", 1, true) ~= nil then
                feeder = zombie
                return
            end
        end
    end)
    return feeder
end

local function requestLoot(player, args)
    if not OS.isEnabled() or OS.getOption("EnableLoot", true) == false then
        denyLoot(player, "Offline survivor looting is disabled.")
        return
    end

    local looterSteamId = OS.getSteamId(player)
    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    if not looterSteamId or not targetSteamId or targetSteamId == "" then
        denyLoot(player, "Invalid target.")
        return
    end

    local record = records[targetSteamId]
    if sameSteamId(looterSteamId, targetSteamId) and (not record or record.testBody ~= true) then
        denyLoot(player, "Invalid target.")
        return
    end
    if not record or not isSleepingRecord(record) or not hasValidOfflineObject(record) then
        denyLoot(player, "This offline survivor is no longer available.")
        return
    end
    if isBodyBeingDragged(record) then
        denyLoot(player, "This sleeping survivor is being moved right now.")
        return
    end
    if not isNearRecord(player, record) then
        denyLoot(player, "You are too far away to search this survivor.")
        return
    end
    -- record.lootItems is persisted when the player disconnects.  It remains
    -- usable after a dedicated-server restart even though the old IsoPlayer
    -- instance is no longer in runtimePlayers.

    local remaining = cooldownRemainingMs(looterSteamId)
    if remaining > 0 then
        denyLoot(player, cooldownMessage(remaining))
        return
    end

    local items = buildAvailableLoot(record)
    if #items == 0 then
        denyLoot(player, "There are no items available to steal here.")
        return
    end

    local sessionId = nextSessionId
    nextSessionId = nextSessionId + 1
    lootSessions[looterSteamId] = {
        id = sessionId,
        targetSteamId = targetSteamId,
        expiresAtMs = nowMs() + (OS.LOOT_SESSION_SECONDS * 1000),
        allowedItems = makeAvailableItemMap(record),
    }

    sendTo(player, OS.COMMAND_OPEN_LOOT, {
        sessionId = sessionId,
        targetName = tostring(record.username or "Player"),
        maxItems = getMaxLootItems(),
        items = items,
    })
end

local function collectRequestedIds(rawIds, limit)
    local ids = {}
    local seen = {}
    if type(rawIds) ~= "table" then return ids end

    for _, rawId in pairs(rawIds) do
        local id = tostring(rawId)
        if id ~= "" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
            if #ids > limit then return nil end
        end
    end
    return ids
end

local function finishLoot(player, looterSteamId, sessionId, success, message, count)
    clearLootSession(looterSteamId, sessionId)
    sendTo(player, OS.COMMAND_LOOT_RESULT, {
        sessionId = sessionId,
        success = success == true,
        count = count or 0,
        message = message,
    })
end

local function commitLoot(player, args)
    local looterSteamId = OS.getSteamId(player)
    local requestedSessionId = args and args.sessionId
    local session = looterSteamId and lootSessions[looterSteamId] or nil
    if not session or tonumber(session.id) ~= tonumber(requestedSessionId) then
        denyLoot(player, "The search session expired. Open the list again.")
        return
    end

    if nowMs() > session.expiresAtMs then
        finishLoot(player, looterSteamId, session.id, false, "The search session expired.", 0)
        return
    end
    if not OS.isEnabled() or OS.getOption("EnableLoot", true) == false then
        finishLoot(player, looterSteamId, session.id, false, "Offline survivor looting is disabled.", 0)
        return
    end

    local record = records[session.targetSteamId]
    local target = runtimePlayers[session.targetSteamId]
    if not record or not isSleepingRecord(record) or not hasValidOfflineObject(record) then
        finishLoot(player, looterSteamId, session.id, false, "This offline survivor is no longer available.", 0)
        return
    end
    if not isNearRecord(player, record) then
        finishLoot(player, looterSteamId, session.id, false, "You moved too far away from the survivor.", 0)
        return
    end

    local remaining = cooldownRemainingMs(looterSteamId)
    if remaining > 0 then
        finishLoot(player, looterSteamId, session.id, false, cooldownMessage(remaining), 0)
        return
    end

    local limit = getMaxLootItems()
    local requestedIds = collectRequestedIds(args and args.itemIds, limit)
    if not requestedIds or #requestedIds == 0 then
        finishLoot(player, looterSteamId, session.id, false, "Select at least one valid item.", 0)
        return
    end

    if record.testBody == true then
        local currentItems = makeAvailableItemMap(record)
        local tested = 0
        for _, wantedId in ipairs(requestedIds) do
            if session.allowedItems[wantedId] and currentItems[wantedId] then tested = tested + 1 end
        end
        if tested <= 0 then
            finishLoot(player, looterSteamId, session.id, false, "None of the selected test items were available.", 0)
        else
            finishLoot(player, looterSteamId, session.id, true, "Test search completed. No real items were moved.", tested)
        end
        return
    end

    local currentItems = makeAvailableItemMap(record)
    local targetInventory = target and getInventory(target) or nil
    if target and not targetInventory then
        finishLoot(player, looterSteamId, session.id, false, "The survivor's inventory is not available right now.", 0)
        return
    end

    local taken = 0
    for _, wantedId in ipairs(requestedIds) do
        local snapshotInfo = session.allowedItems[wantedId]
        local currentInfo = currentItems[wantedId]
        if snapshotInfo and currentInfo then
            local item = targetInventory and findItemInContainer(targetInventory, wantedId) or nil
            local canTake = targetInventory == nil or (item and isLootableItem(target, item))
            if canTake then
                -- Register the pending deletion first.  If the victim's saved
                -- inventory still contains this item on reconnect, it is removed
                -- before control returns to the victim.
                addPendingTheft(record, wantedId, looterSteamId)
                persistentDataChanged()

                local moved = false
                if targetInventory then
                    moved = moveItemToRobber(target, player, item)
                else
                    moved = moveSnapshotItemToRobber(player, currentInfo)
                end

                if moved then
                    removeSnapshotItem(record, wantedId)
                    taken = taken + 1
                else
                    removePendingTheft(record, wantedId)
                    persistentDataChanged()
                end
            end
        end
    end

    if taken <= 0 then
        finishLoot(player, looterSteamId, session.id, false, "None of the selected items were still available.", 0)
        return
    end

    -- One cooldown is global to the looter, as requested: after a successful
    -- search they cannot search another offline survivor until it expires.
    lootCooldowns[looterSteamId] = nowMs()
    persistentDataChanged()
    finishLoot(player, looterSteamId, session.id, true, "Stole " .. taken .. " item(s).", taken)
end

local function cancelLoot(player, args)
    local looterSteamId = OS.getSteamId(player)
    if looterSteamId then clearLootSession(looterSteamId, args and args.sessionId) end
end

local function expireLootSessions()
    local current = nowMs()
    for steamId, session in pairs(lootSessions) do
        if current > session.expiresAtMs then
            lootSessions[steamId] = nil
        end
    end
end

-- Cooldown entries are persisted by player id. Remove them once their active
-- period has elapsed so long-running servers do not accumulate stale ids.
local function pruneExpiredLootCooldowns()
    local hours = math.max(0, numberOr(OS.getOption("LootCooldownHours", 24), 24))
    local durationMs = hours * 60 * 60 * 1000
    local current = nowMs()
    local changed = false

    for steamId, lastLoot in pairs(lootCooldowns) do
        local timestamp = tonumber(lastLoot)
        if timestamp == nil or durationMs <= 0 or current - timestamp >= durationMs then
            lootCooldowns[steamId] = nil
            changed = true
        end
    end
    return changed
end

local function finishZombieDeathRecord(record)
    local proxy = findOfflineObject(record)
    if proxy then removeTrackedObject(record) end
    record.pendingRemoval = nil
    record.objectX, record.objectY, record.objectZ, record.objectCreated = nil, nil, nil, nil
    record.placement, record.bedFacing, record.bedAxis, record.bedSurfaceOffset = nil, nil, nil, nil
    record.sofaFacing, record.sofaAxis, record.sofaSurfaceOffset = nil, nil, nil
    record.state = "dead"
    record.offlineAt = nil
    record.despawned = nil
    record.corpseFailure = nil
    record.corpseFailureReported = nil
    record.lootItems = nil
    record.lootSnapshotAtMs = nil
    record.lootSnapshotAvailable = nil
    record.zombieDeath = nil
    record.realCorpseCreated = nil
    record.realCorpseAt = nil
    record.realCorpseX = nil
    record.realCorpseY = nil
    record.realCorpseZ = nil
    record.temporaryDeathBodyId = nil
    record.temporaryDeathBodyX, record.temporaryDeathBodyY, record.temporaryDeathBodyZ = nil, nil, nil
    record.deferredDeath = nil
    record.dragSourceX, record.dragSourceY, record.dragSourceZ = nil, nil, nil
    record.dragSourceObjectId = nil
    record.dragSourceCleanupUntil = nil
    record.staleProxyX, record.staleProxyY, record.staleProxyZ = nil, nil, nil
    record.staleProxyObjectId = nil
    -- A death replaces any pending drag destination, so these must not survive
    -- into the next life as a stale teleport target.
    record.reconnectX, record.reconnectY, record.reconnectZ = nil, nil, nil
    pendingRepositions[tostring(record.steamId)] = nil
end

-- Wait until the reconnect has finished loading, then make the native player
-- death occur and remove only the temporary empty corpse it creates. The real
-- corpse left by the zombie remains in the world and owns the actual items.
local ZOMBIE_DEATH_MAX_ATTEMPTS = 15
local TEMPORARY_BODY_MAX_ATTEMPTS = 10
-- Seconds to wait for the engine to report a death before issuing it again.
local DEATH_CONFIRM_SECONDS = 5

-- On a listen server die() forwards the death to the client and returns nothing,
-- so isDead() only flips a moment later. isOnDeathDone() covers that window.
local function isDeathApplied(player)
    local applied = false
    pcall(function()
        applied = player:isDead() == true or player:isOnDeathDone() == true
    end)
    return applied
end

-- die() is void in B42. A hosted server can publish the temporary corpse a
-- little later through the client death path, so retain a square snapshot and
-- then bind cleanup to the resulting native corpse ID.
local function listSquareCorpses(square)
    local corpses = {}
    pcall(function()
        local list = square:getStaticMovingObjects()
        if not list then return end
        for index = 0, list:size() - 1 do
            local candidate = list:get(index)
            if isNativeCorpse(candidate) then corpses[#corpses + 1] = candidate end
        end
    end)
    return corpses
end

local function getPlayerOnlineId(player)
    local onlineId = nil
    pcall(function() onlineId = player:getOnlineID() end)
    if onlineId == nil then return nil end
    onlineId = tostring(onlineId)
    if onlineId == "" or onlineId == "-1" then return nil end
    return onlineId
end

local function getCorpseCharacterOnlineId(corpse)
    local onlineId = nil
    pcall(function() onlineId = corpse:getCharacterOnlineID() end)
    if onlineId == nil then return nil end
    onlineId = tostring(onlineId)
    if onlineId == "" or onlineId == "-1" then return nil end
    return onlineId
end

local function findCorpseAddedSince(square, before, expectedCharacterOnlineId)
    local found = nil
    pcall(function()
        local list = square:getStaticMovingObjects()
        if not list then return end
        for index = list:size() - 1, 0, -1 do
            local candidate = list:get(index)
            if isNativeCorpse(candidate) then
                local known = false
                for i = 1, #before do
                    if before[i] == candidate then
                        known = true
                        break
                    end
                end
                if not known and (not expectedCharacterOnlineId
                    or getCorpseCharacterOnlineId(candidate) == expectedCharacterOnlineId) then
                    found = candidate
                    return
                end
            end
        end
    end)
    return found
end

local function rememberTemporaryDeathBody(record, pending, body)
    if not record or not pending or not body or not isNativeCorpse(body) then return nil end

    local objectId = getNativeObjectId(body)
    if not objectId then return nil end

    local x, y, z = nil, nil, nil
    pcall(function()
        x = body:getX()
        y = body:getY()
        z = body:getZ()
    end)

    pending.deathBody = body
    pending.temporaryBody = body
    pending.temporaryBodyId = objectId
    record.temporaryDeathBodyId = objectId
    record.temporaryDeathBodyX = x
    record.temporaryDeathBodyY = y
    record.temporaryDeathBodyZ = z
    return body
end

local function findCorpseByObjectId(square, objectId)
    if not square or not objectId then return nil end

    local found = nil
    pcall(function()
        local list = square:getStaticMovingObjects()
        if not list then return end
        for index = 0, list:size() - 1 do
            local candidate = list:get(index)
            if isNativeCorpse(candidate) and getNativeObjectId(candidate) == tostring(objectId) then
                found = candidate
                return
            end
        end
    end)
    return found
end

local function findPendingTemporaryDeathBody(record, pending)
    if not record or not pending then return nil end
    local objectId = pending.temporaryBodyId or record.temporaryDeathBodyId
    if pending.deathBody and (not objectId or getNativeObjectId(pending.deathBody) == tostring(objectId)) then
        return pending.deathBody
    end
    local x = numberOr(record.temporaryDeathBodyX, record.realCorpseX or record.objectX or record.x)
    local y = numberOr(record.temporaryDeathBodyY, record.realCorpseY or record.objectY or record.y)
    local z = numberOr(record.temporaryDeathBodyZ, record.realCorpseZ or record.objectZ or record.z)
    local square = getWorld():getCell():getGridSquare(gridCoordinate(x), gridCoordinate(y), gridCoordinate(z))
    if not square then return nil end

    if objectId then
        local body = findCorpseByObjectId(square, objectId)
        if body then pending.deathBody = body end
        return body
    end

    if not pending.deathCorpsesBefore then return nil end
    local body = findCorpseAddedSince(square, pending.deathCorpsesBefore, pending.deathCharacterOnlineId)
    return rememberTemporaryDeathBody(record, pending, body)
end

-- A server restart can happen in the short window between player death and the
-- scheduled temporary-body removal. The ID is persisted so that recovery still
-- removes only that exact empty body, never the real corpse containing loot.
local function cleanupRecordedTemporaryDeathBody(record)
    local objectId = record and record.temporaryDeathBodyId
    if not objectId then return false, false end

    local x = numberOr(record.temporaryDeathBodyX, record.realCorpseX or record.objectX or record.x)
    local y = numberOr(record.temporaryDeathBodyY, record.realCorpseY or record.objectY or record.y)
    local z = numberOr(record.temporaryDeathBodyZ, record.realCorpseZ or record.objectZ or record.z)
    local square = getWorld():getCell():getGridSquare(gridCoordinate(x), gridCoordinate(y), gridCoordinate(z))
    if not square then return false, false end

    local body = findCorpseByObjectId(square, objectId)
    if body then
        local removed = false
        pcall(function()
            square:removeCorpse(body, false)
            removed = true
        end)
        if not removed then return false, false end
    end

    record.temporaryDeathBodyId = nil
    record.temporaryDeathBodyX, record.temporaryDeathBodyY, record.temporaryDeathBodyZ = nil, nil, nil
    return true, body ~= nil
end

-- Real seconds of feeding before the offline survivor dies, from the Sandbox
-- option. Read live so a server owner can retune it without a restart.
local function getZombieKillSeconds()
    local minutes = numberOr(OS.getOption("ZombieKillMinutes", 5), 5)
    return math.max(1, minutes * 60)
end

local function processPendingZombieDeaths(connected)
    local current = nowSeconds()
    for steamId, pending in pairs(pendingZombieDeaths) do
        local record = records[steamId]
        if not record then
            pendingZombieDeaths[steamId] = nil
        elseif record.state ~= "zombie_killed" and pending.phase ~= "removeTemporaryBody" then
            pendingZombieDeaths[steamId] = nil
        elseif not connected[steamId] and pending.phase ~= "removeTemporaryBody" then
            pending.player = nil
        elseif pending.phase == "kill" and current >= numberOr(pending.dueAt, current) then
            local player = pending.player
            local x = numberOr(record.realCorpseX, record.objectX or record.x)
            local y = numberOr(record.realCorpseY, record.objectY or record.y)
            local z = numberOr(record.realCorpseZ, record.objectZ or record.z)
            local square = getWorld():getCell():getGridSquare(gridCoordinate(x), gridCoordinate(y), gridCoordinate(z))

            if not player or not square then
                pending.attempts = numberOr(pending.attempts, 0) + 1
                pending.dueAt = current + 1
            elseif pending.killIssued and not isDeathApplied(player) then
                -- The kill was already issued. Wait for the engine to report it
                -- rather than issuing it again; a second die() spawns a second
                -- corpse. Re-issue only after a long silence.
                if current - numberOr(pending.killedAt, current) >= DEATH_CONFIRM_SECONDS then
                    pending.killIssued = nil
                    pending.attempts = numberOr(pending.attempts, 0) + 1
                end
                pending.dueAt = current + 1
            elseif pending.killIssued then
                -- Issued and now confirmed dead: finish through the normal path.
                record.state = "dead"
                record.zombieDeath = nil
                record.deferredDeath = nil
                pending.phase = "removeTemporaryBody"
                pending.temporaryBody = record.realCorpseCreated == true
                    and findPendingTemporaryDeathBody(record, pending) or nil
                pending.removeAt = current + 2
                persistentDataChanged()
                print("[Offline Survivor] Applied zombie death to reconnecting player " .. tostring(record.username))
            else
                -- The real lootable corpse only exists when the attack could be
                -- carried out while the victim was still in memory. Otherwise
                -- the corpse that die() creates below IS the real one and must
                -- keep the player's items.
                local hasRealCorpse = record.realCorpseCreated == true
                local ok, temporaryBody = pcall(function()
                    -- The sleeping proxy always goes first: leaving it behind is
                    -- what produced a lootable corpse plus a searchable body.
                    local staleProxyCleanup = makeStaleBodyCleanupArgsForObject(record, findOfflineObject(record))
                    removeTrackedObject(record)
                    record.objectCreated = nil
                    sendTo(player, OS.COMMAND_CLEANUP_STALE_BODY, staleProxyCleanup)
                    if hasRealCorpse then clearPlayerItemsForForcedDeath(player) end
                    player:setX(x)
                    player:setY(y)
                    player:setZ(z)
                    player:setNextX(x)
                    player:setNextY(y)
                    player:setCurrentSquare(square)
                    local direction = getCorpseDirection(record)
                    if direction then player:setForwardIsoDirection(direction) end
                    player:setFallOnFront(record.fallOnFront == true)
                    player:setKilledByFall(true)
                    player:Kill(nil)

                    -- die() marks OnDeathDone, which is required for the normal
                    -- respawn flow. Capture the exact temporary corpse by native
                    -- ID so cleanup can never select the real lootable corpse.
                    local before = listSquareCorpses(square)
                    pending.deathBody = nil
                    pending.temporaryBody = nil
                    pending.temporaryBodyId = nil
                    pending.deathCharacterOnlineId = getPlayerOnlineId(player)
                    pending.deathCorpsesBefore = before
                    local deathBody = player:die()
                    local created = deathBody or findCorpseAddedSince(square, before, pending.deathCharacterOnlineId)
                    if hasRealCorpse then return rememberTemporaryDeathBody(record, pending, created) end
                    return created
                end)

                pending.killIssued = true
                pending.killedAt = current
                if ok then pending.deathBody = temporaryBody end

                -- Only trust the outcome the engine actually produced. Assuming
                -- success let a player walk away alive from their own death.
                local reallyDead = isDeathApplied(player)

                if not reallyDead then
                    -- On a listen server die() hands the death to the client and
                    -- returns nothing, so the result arrives a moment later. Wait
                    -- for it instead of calling die() again: every extra call can
                    -- spawn another corpse, which is where duplicates came from.
                    pending.dueAt = current + 1
                    if not ok then
                        print("[Offline Survivor] Could not force zombie death for " .. tostring(record.username) .. ": " .. tostring(temporaryBody))
                    end
                else
                    -- Consume the death only now that it is confirmed. Leaving
                    -- the record as "zombie_killed" afterwards would kill every
                    -- new character this player created, forever.
                    record.state = "dead"
                    record.zombieDeath = nil
                    record.deferredDeath = nil
                    persistentDataChanged()
                    pending.phase = "removeTemporaryBody"
                    -- Only a duplicate is removed. When no real corpse existed,
                    -- the body die() just made carries the loot and must stay.
                    pending.temporaryBody = hasRealCorpse
                        and findPendingTemporaryDeathBody(record, pending) or nil
                    pending.removeAt = current + 2
                    print("[Offline Survivor] Applied zombie death to reconnecting player " .. tostring(player:getUsername()))
                end
            end

            -- A failed load or an unloaded square must never erase a zombie
            -- death sentence. Keep it pending and retry after a short pause so
            -- the player cannot reconnect alive because one attempt raced the
            -- loading screen.
            if pending.phase == "kill" and numberOr(pending.attempts, 0) >= ZOMBIE_DEATH_MAX_ATTEMPTS then
                if not pending.retryWarningShown then
                    pending.retryWarningShown = true
                    print("[Offline Survivor] Keeping the offline zombie death pending for "
                        .. tostring(record.username) .. " until the engine confirms it")
                end
                pending.attempts = 0
                pending.killIssued = nil
                pending.dueAt = current + DEATH_CONFIRM_SECONDS
            end
        elseif pending.phase == "removeTemporaryBody" and current >= numberOr(pending.removeAt, current) then
            -- player:die() leaves an empty corpse next to the real one. Its
            -- square is not always resolvable on the first pass, so retry for a
            -- few seconds instead of abandoning a second body on the ground.
            -- Set only when a real lootable corpse already exists, so this can
            -- never remove the body that holds the player's items.
            local expectedBodyId = pending.temporaryBodyId or record.temporaryDeathBodyId
            local body = pending.temporaryBody
            if body and expectedBodyId and getNativeObjectId(body) ~= tostring(expectedBodyId) then body = nil end
            if not body and record.realCorpseCreated == true then
                body = findPendingTemporaryDeathBody(record, pending)
                pending.temporaryBody = body
            end
            if not body and expectedBodyId then
                -- It may already have been removed by the native world update.
                -- A loaded square without this exact ID means cleanup succeeded;
                -- an unloaded square remains pending for a later retry.
                local resolved = cleanupRecordedTemporaryDeathBody(record)
                if resolved then pending.temporaryBodyId = nil end
            end
            expectedBodyId = pending.temporaryBodyId or record.temporaryDeathBodyId
            local mustRemove = body ~= nil and expectedBodyId ~= nil
                and getNativeObjectId(body) == tostring(expectedBodyId)
            local waitingForBody = not mustRemove and record.realCorpseCreated == true
                and (expectedBodyId ~= nil or pending.deathCorpsesBefore ~= nil)
            local cleared = not mustRemove and not waitingForBody

            if mustRemove then
                pcall(function()
                    local square = body:getSquare()
                    if square then
                        square:removeCorpse(body, false)
                        cleared = true
                    end
                end)
            end

            local waited = numberOr(pending.removeAttempts, 0) + 1
            pending.removeAttempts = waited
            if cleared then
                finishZombieDeathRecord(record)
                pendingZombieDeaths[steamId] = nil
                persistentDataChanged()
            elseif expectedBodyId and waited >= TEMPORARY_BODY_MAX_ATTEMPTS then
                -- The target is known but its chunk is temporarily unavailable.
                -- Do not abandon the cleanup and leave a permanent duplicate.
                pending.removeAttempts = 0
                pending.removeAt = current + 1
                print("[Offline Survivor] Waiting to remove temporary death body for " .. tostring(record.username))
            elseif waited >= TEMPORARY_BODY_MAX_ATTEMPTS then
                if not cleared then
                    print("[Offline Survivor] No temporary death body was published for " .. tostring(record.username))
                end
                finishZombieDeathRecord(record)
                pendingZombieDeaths[steamId] = nil
                persistentDataChanged()
            else
                pending.removeAt = current + 1
            end
        end
    end
end

local function processZombieDeaths()
    -- Everything below only runs while the Sandbox option is on. With it off the
    -- mod never touches a zombie, so vanilla behaviour is untouched.
    if not OS.isEnabled() or OS.getOption("AllowZombieDeaths", false) == false then
        -- Kahlua has no global next(); clear by iteration instead.
        for steamId in pairs(devourProgress) do devourProgress[steamId] = nil end
        for steamId in pairs(devourLastFedAt) do devourLastFedAt[steamId] = nil end
        for steamId in pairs(zombieFeedingReports) do zombieFeedingReports[steamId] = nil end
        return
    end

    local current = nowSeconds()
    local active = {}
    for steamId, record in pairs(records) do
        if isSleepingRecord(record) and not record.despawned and not isBodyBeingDragged(record)
            and not isJaxeRevivalProtected(record) then
            local proxy = findOfflineObject(record)
            -- Client-owned zombies report their native eating state. Server-owned
            -- zombies are verified directly from the native corpse state. Neither
            -- route treats mere proximity as an attack.
            local reportedFeeding = proxy and hasFreshZombieFeedingReport(steamId, current)
            local serverFeeder = proxy and findServerZombieEatingProxy(proxy) or nil
            if proxy and (reportedFeeding or serverFeeder) then
                active[steamId] = true
                local elapsed = numberOr(devourProgress[steamId], 0) + OS.SERVER_SCAN_SECONDS
                devourProgress[steamId] = elapsed
                devourLastFedAt[steamId] = current
                local required = getZombieKillSeconds()
                if elapsed <= OS.SERVER_SCAN_SECONDS or math.floor(elapsed) % 10 == 0 then
                    local source = serverFeeder and "server" or "client"
                    print("[Offline Survivor] Zombie progress for " .. tostring(record.username)
                        .. ": " .. tostring(math.floor(elapsed)) .. "/" .. tostring(math.floor(required))
                        .. "s (" .. source .. ")")
                end
                if elapsed >= required then
                    devourProgress[steamId] = nil
                    devourLastFedAt[steamId] = nil
                    zombieFeedingReports[steamId] = nil
                    active[steamId] = nil
                    killOfflineSurvivorByZombie(record, serverFeeder)
                end
            end
        end
    end

    -- Progress is runtime-only: it is never written to ModData and cannot
    -- outlive the body it belongs to.
    for steamId in pairs(devourProgress) do
        if not active[steamId]
            and current - numberOr(devourLastFedAt[steamId], 0) > OS.ZOMBIE_FEED_PROGRESS_GRACE_SECONDS then
            devourProgress[steamId] = nil
            devourLastFedAt[steamId] = nil
        end
    end
    for steamId in pairs(zombieFeedingReports) do
        if not active[steamId] then hasFreshZombieFeedingReport(steamId, current) end
    end
end

local function maintainOfflineRecords(connected)
    local changed = false

    -- EnableMod is read live. Disabling it removes existing V2 corpses;
    -- enabling it later recreates eligible offline records without restart.
    if not OS.isEnabled() then
        for _, record in pairs(records) do
            if record.objectCreated and removeTrackedObject(record) then
                record.objectCreated = nil
                changed = true
            end
        end
        if changed then persistentDataChanged() end
        return
    end

    local despawnMinutes = math.max(0, numberOr(OS.getOption("DespawnHours", 0), 0))

    for steamId, record in pairs(records) do
        -- Recover a known empty reconnect corpse after a server restart. A live
        -- pending cleanup owns the short packet-order delay, so it is left alone.
        if record.state == "dead" and record.temporaryDeathBodyId and not pendingZombieDeaths[steamId] then
            local resolved, removed = cleanupRecordedTemporaryDeathBody(record)
            if resolved then
                changed = true
                if removed then
                    print("[Offline Survivor] Removed recovered temporary death body for " .. tostring(record.username))
                end
            end
        end
        if connected[steamId] then missingTicks[steamId] = nil end

        if record.state == "online" and not connected[steamId] then
            -- Require the player to stay missing for several consecutive scans.
            -- A single dropped entry is streaming lag, not a logout.
            local missed = numberOr(missingTicks[steamId], 0) + 1
            missingTicks[steamId] = missed
            if missed >= OS.OFFLINE_CONFIRM_TICKS then
                missingTicks[steamId] = nil
                markOffline(record)
            end
        elseif record.state == "dead" and not connected[steamId] then
            -- A dead, disconnected character has no remaining offline-body
            -- workflow. Release the last strong IsoPlayer reference rather
            -- than retaining it until the server restarts.
            runtimeObjects[steamId] = nil
            runtimePlayers[steamId] = nil
            bodyDragSessions[steamId] = nil
            pendingBodyMoves[steamId] = nil
            clearLootSessionsForTarget(steamId)
        elseif record.state == "test_offline" and not connected[steamId] then
            if record.objectCreated and removeTrackedObject(record) then changed = true end
            record.objectCreated = nil
            record.testBody = nil
            record.testDefeated = nil
            record.state = "online"
            markOffline(record)
            changed = true
        elseif record.state == "test_offline" and record.testDefeated then
            -- Keep the defeated test body visible until the administrator ends
            -- the test, without applying a real death to that player.
        elseif record.state == "offline" or record.state == "test_offline" then
            local dragging = isBodyBeingDragged(record)
            if not dragging and clearStaleBodyDragSource(record) then
                changed = true
            end
            if not dragging and hasDuplicateOfflineObjects(record) then
                -- Cleanup for any duplicates created by the previous beta
                -- build. Remove every marked proxy on the authoritative tile
                -- and recreate exactly one native corpse.
                if removeTrackedObject(record) then
                    record.objectCreated = nil
                    record.corpseFailure = nil
                    record.corpseFailureReported = nil
                    createOfflineCorpseObject(record)
                    changed = true
                end
            elseif not dragging and refreshTrackedObject(record) then
                changed = true
            end
            local expired = false
            if not dragging and not record.despawned and despawnMinutes > 0 then
                local offlineAt = numberOr(record.offlineAt, nowSeconds())
                expired = nowSeconds() - offlineAt >= despawnMinutes * 60
            end

            if not dragging and expired then
                if removeTrackedObject(record) then changed = true end
                record.objectCreated = nil
                record.despawned = true
                releaseDespawnedRuntimeState(record)
                changed = true
            -- This setting is evaluated every second, so turning it on removes
            -- an existing administrator body and turning it off can create it.
            elseif not dragging and shouldBlockAdminOfflineBody(record) then
                if record.objectCreated and removeTrackedObject(record) then
                    record.objectCreated = nil
                    changed = true
                end
                record.bodySuppressed = true
            elseif not dragging and record.bodySuppressed then
                record.bodySuppressed = nil
                changed = true
                if not record.corpseFailure and createOfflineCorpseObject(record) then changed = true end
            elseif not dragging and not record.despawned and not record.objectCreated and not record.corpseFailure then
                if createOfflineCorpseObject(record) then changed = true end
            end
        end

        if record.pendingRemoval and removeTrackedObject(record) then
            record.pendingRemoval = nil
            record.objectX, record.objectY, record.objectZ, record.objectCreated = nil, nil, nil, nil
            record.placement, record.bedFacing, record.bedAxis, record.bedSurfaceOffset = nil, nil, nil, nil
            record.sofaFacing, record.sofaAxis, record.sofaSurfaceOffset = nil, nil, nil
            changed = true
        end

        -- Also clean state left by a server restart or an older beta build that
        -- had already marked the record as despawned.
        if record.despawned and record.testBody ~= true and releaseDespawnedRuntimeState(record) then
            changed = true
        end
    end

    if changed then persistentDataChanged() end
end

-- Every maintenance step is isolated. A failure in one of them used to abort
-- the whole tick, which silently stopped reconnect cleanup and left bodies
-- lying around after their owner had already logged back in.
local function runStep(name, step, argument)
    local ok, err = pcall(step, argument)
    if not ok then print("[Offline Survivor] " .. name .. " failed: " .. tostring(err)) end
    return ok
end

local function onTick()
    if nowSeconds() < nextMaintenance then return end
    nextMaintenance = nowSeconds() + OS.SERVER_SCAN_SECONDS
    runStep("expireLootSessions", expireLootSessions)
    if nowSeconds() >= nextCooldownPrune then
        nextCooldownPrune = nowSeconds() + 60
        runStep("pruneExpiredLootCooldowns", function()
            if pruneExpiredLootCooldowns() then persistentDataChanged() end
        end)
    end
    runStep("clearExpiredBodyDragSessions", clearExpiredBodyDragSessions)

    local connected = {}
    if not runStep("scanOnlinePlayers", function() connected = scanOnlinePlayers() end) then return end

    runStep("processPendingRepositions", processPendingRepositions, connected)
    runStep("processPendingBodyMoves", processPendingBodyMoves)
    runStep("processPendingZombieDeaths", processPendingZombieDeaths, connected)
    runStep("processZombieDeaths", processZombieDeaths)
    runStep("maintainOfflineRecords", maintainOfflineRecords, connected)
end

local function onInitGlobalModData()
    records = ModData.getOrCreate(OS.DATA_KEY)
    recordsInitialized = true
    lootCooldowns = ModData.getOrCreate(OS.LOOT_DATA_KEY)
    runtimeObjects = {}
    runtimePlayers = {}
    lootSessions = {}
    pendingZombieDeaths = {}
    devourProgress = {}
    devourLastFedAt = {}
    zombieFeedingReports = {}
    pendingRepositions = {}
    missingTicks = {}
    bodyDragSessions = {}
    pendingBodyMoves = {}
    nextCooldownPrune = 0
    lastZombieFeedLog = {}
    local sandboxPage = SandboxVars and SandboxVars[OS.MODULE] or nil
    if not sandboxPage or sandboxPage.AllowZombieDeaths == nil then
        print("[OfflineSurvivor V2] Sandbox page '" .. OS.MODULE
            .. "' is missing. Install the complete 42.0 folder and start the server with this package's mod ID; zombie deaths remain disabled until its SandboxVars entry exists.")
    else
        print("[OfflineSurvivor V2] Zombies Can Kill Sleeping Survivors = "
            .. tostring(OS.getOption("AllowZombieDeaths", false)))
    end
    print("[OfflineSurvivor V2] SERVER script initialized.")
end

local function onClientCommand(module, command, player, args)
    if module ~= OS.MODULE then return end

    if command == OS.COMMAND_REQUEST_LOOT then
        requestLoot(player, args)
    elseif command == OS.COMMAND_COMMIT_LOOT then
        commitLoot(player, args)
    elseif command == OS.COMMAND_CANCEL_LOOT then
        cancelLoot(player, args)
    elseif command == OS.COMMAND_REQUEST_BODY_DRAG then
        requestBodyDrag(player, args)
    elseif command == OS.COMMAND_BODY_DRAG_PICKED_UP then
        confirmBodyDragPickup(player, args)
    elseif command == OS.COMMAND_BODY_DRAG_HEARTBEAT then
        refreshBodyDragSession(player, args)
    elseif command == OS.COMMAND_FINISH_BODY_DRAG then
        finishBodyDrag(player, args)
    elseif command == OS.COMMAND_ZOMBIE_FEEDING then
        reportZombieFeeding(player, args)
    end
end

-- Administrative removal is a visual despawn, never a death sentence. Keep
-- reconnect coordinates and pending thefts; never copy/clear the real inventory.
-- Separate function scope: Silent Death is close to Lua 5.1's 200-local limit.
local function installAdminSupport()
local function suppressAdminVisual(body, location)
    local data=body:getModData()
    local x,y,z=body:getX(),body:getY(),body:getZ()
    if location then x,y,z=location:getX(),location:getY(),location:getZ() end
    local key=tostring(data.steamId or "")
    local record=records[key]
    if record and (record.state=="offline" or record.state=="test_offline")
        and tostring(data.bodyEpoch or 0)==tostring(record.bodyEpoch or 0)
        and tostring(data.bodyRevision or 0)==tostring(record.bodyRevision or 0)
        and not record.adminVisualRemoved then
        record.reconnectX=x
        record.reconnectY=y
        record.reconnectZ=math.floor(z)
        record.adminVisualRemoved=true
        record.despawned=true
        record.objectCreated=nil
        record.pendingRemoval=true
        local session=bodyDragSessions[key]
        if session then
            local players=getOnlinePlayers()
            for i=0,players:size()-1 do
                local mover=players:get(i)
                if sameSteamId(OS.getSteamId(mover),session.moverSteamId) then
                    sendTo(mover,"CancelRemovedBodyDrag",{targetSteamId=key})
                end
            end
        end
        clearBodyDragSession(record)
        clearLootSessionsForTarget(key)
        devourProgress[key],devourLastFedAt[key],zombieFeedingReports[key]=nil,nil,nil
        runtimeObjects[key]=nil
        persistentDataChanged()
    end
    local cleanup=makeStaleBodyCleanupArgs(data.steamId,body:getX(),body:getY(),body:getZ(),
        getNativeObjectId(body),data.bodyEpoch or 0,data.bodyRevision or 0)
    broadcastStaleBodyCleanup(cleanup)
    if location then
        broadcastStaleBodyCleanup(makeStaleBodyCleanupArgs(data.steamId,x,y,z,
            nil,data.bodyEpoch or 0,data.bodyRevision or 0))
    end
end

local function suppressDraggedBodiesInArea(job)
    local targets={}
    local players=getOnlinePlayers()
    for _,session in pairs(bodyDragSessions) do
        if session.sourceDetached and session.proxy then
            for i=0,players:size()-1 do
                local mover=players:get(i)
                if sameSteamId(OS.getSteamId(mover),session.moverSteamId) then
                    local dx,dy=mover:getX()-job.x,mover:getY()-job.y
                    if math.floor(mover:getZ())==job.z and dx*dx+dy*dy<=job.radius*job.radius then
                        targets[#targets+1]={body=session.proxy,location=mover}
                    end
                end
            end
        end
    end
    for _,target in ipairs(targets) do suppressAdminVisual(target.body,target.location) end
    return #targets
end

-- Reconcile when old chunks return, not by scanning the entire loaded world.
-- This also removes stale bodies saved by older releases after a reconnect.
local function reconcileLoadedBodies(square)
    if not square then return end
    local list=square:getStaticMovingObjects()
    for i=list:size()-1,0,-1 do
        local body=list:get(i)
        if H.isProxy(body) and isNativeCorpse(body) then
            H.freezeAge(body)
            if recordsInitialized then
                local data=body:getModData()
                local record=records[tostring(data.steamId or "")]
                local valid=record and (record.state=="offline" or record.state=="test_offline"
                    or record.deferredDeath==true)
                    and not record.despawned and not record.adminVisualRemoved
                if valid and record.bodyEpoch~=nil then
                    valid=tostring(data.bodyEpoch or 0)==tostring(record.bodyEpoch)
                        and tostring(data.bodyRevision or 0)==tostring(record.bodyRevision or 0)
                end
                if not valid then
                    square:removeCorpse(body,false)
                end
            end
        end
    end
end
require "OfflineSurvivorV2/OS_AdminCleanup"
OS.AdminCleanup.install(suppressAdminVisual, suppressDraggedBodiesInArea)
if Events.LoadGridsquare then Events.LoadGridsquare.Add(reconcileLoadedBodies) end
end
installAdminSupport()

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
