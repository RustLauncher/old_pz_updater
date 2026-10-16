require "OfflineSurvivorV2/OS_Constants"
require "OfflineSurvivorV2/OS_BodyLifecycle"
require "OfflineSurvivorV2/OS_LootUI"

local OS = OfflineSurvivorV2
local H = OS.BodyLifecycle
local sealedVisualContainers = setmetatable({}, { __mode = "k" })
local sealScanTick = 0
local pendingBodyDrag = nil
local deferredDragCleanup = nil
local staleBodyCleanups = {}
local LOCAL_DRAG_TOKEN_KEY = "__OfflineSurvivorLocalDragToken"
local nextLocalDragToken = 0
local localZombieLures = setmetatable({}, { __mode = "k" })
local zombieFeedReportAt = {}

-- All player-facing client UI is resolved at display time. This is important
-- for a multiplayer mod because each client may use a different language.
function OS.translate(key, fallback, ...)
    local translationKey = "UI_OfflineSurvivor_" .. tostring(key or "")
    if getText then
        local ok, value = pcall(getText, translationKey, ...)
        if ok and value and value ~= translationKey then return value end
    end

    local result = tostring(fallback or translationKey)
    for index = 1, select("#", ...) do
        result = string.gsub(result, "%%" .. tostring(index), tostring(select(index, ...)))
    end
    return result
end

local serverMessageKeys = {
    ["Dragging sleeping survivors is disabled."] = "DragDisabled",
    ["That sleeping survivor is no longer available."] = "Unavailable",
    ["Move closer to the sleeping survivor."] = "MoveCloser",
    ["Another player is already dragging this survivor."] = "AlreadyDragging",
    ["The sleeping survivor is not ready to be dragged."] = "DragNotReady",
    ["This survivor cannot be moved after a server restart. It will be available again after its owner reconnects."] = "DragRestart",
    ["The dragging session has expired."] = "DragExpired",
    ["Dragging cancelled."] = "DragCancelled",
    ["The final body position is invalid."] = "DragPositionInvalid",
    ["The survivor must be beside you when you put it down."] = "DragPutDownNear",
    ["That sleeping survivor can no longer be moved."] = "DragNoLongerMovable",
    ["The sleeping survivor could not be moved safely."] = "DragMoveFailed",
    ["Sleeping survivor moved."] = "DragMoved",
    ["The native body-drag action is unavailable."] = "DragUnavailable",
    ["This sleeping survivor is being moved right now."] = "BeingMoved",
    ["This survivor is protected by Jaxe Revival while incapacitated."] = "JaxeRevivalProtected",
}

local function localizeServerMessage(message)
    local key = serverMessageKeys[tostring(message or "")]
    return key and OS.translate(key, message) or message
end

-- The native corpse stores visual clones in an ItemContainer so its HumanVisual
-- and worn items can be sent by the standard corpse packet. The V2 loot UI is
-- the only permitted route to the real offline inventory.
local function isOfflineVisualContainer(container)
    if not container then return false end
    local ok, parent = pcall(function() return container:getParent() end)
    if not ok or not parent then return false end
    local data = nil
    ok, data = pcall(function() return parent:getModData() end)
    return ok and data and data[OS.OFFLINE_MARKER] and data.renderer == OS.RENDERER
end

local function isOfflineVisualObject(object)
    if not object then return false end
    local ok, data = pcall(function() return object:getModData() end)
    return ok and data and data[OS.OFFLINE_MARKER] and data.renderer == OS.RENDERER
end

-- A native corpse's WornItems point at the temporary visual items in its own
-- ItemContainer.  Do not replace that container on a client: B42 validates
-- WornItems against it during a later clothing/model refresh and removes every
-- item it cannot find.  That was the source of bodies becoming naked after a
-- drag or a nearby world update.  The menu and transfer guards below protect
-- this renderer-only inventory without breaking the native mesh.
local function sealOfflineVisualCorpse(object)
    if not isOfflineVisualObject(object) or sealedVisualContainers[object] then return false end

    -- Compatibility with Immersive Looting B42. This ItemContainer only holds
    -- clothing/model clones; the real loot is served through our own
    -- server-authoritative Search UI. Marking both ILB42 modes complete stops
    -- ILB42 from hiding this visual inventory and making items flash then vanish.
    -- This client-side fallback also covers bodies created before the server
    -- sent the compatibility ModData in a newer mod version.
    local ok, data = pcall(function() return object:getModData() end)
    if ok and data then
        data.ILB42_containerSearched = true
        data.ILB42_itemContainerComplete = true
    end

    -- The weak-key sentinel prevents repeated work while allowing an unloaded
    -- corpse and all of its renderer-only item clones to be garbage-collected.
    sealedVisualContainers[object] = true
    return true
end

local function installVisualCloneGuards()
    require "TimedActions/ISInventoryTransferAction"
    require "TimedActions/ISGrabCorpseAction"
    require "TimedActions/ISTimedActionQueue"
    require "TimedActions/ISBurnCorpseAction"
    require "ISUI/ISInventoryPane"
    require "ISUI/ISInventoryPage"
    require "TimedActions/ISInventoryTransferUtil"

    if ISInventoryTransferAction and not ISInventoryTransferAction.OfflineSurvivorV2Guard then
        local baseIsValid = ISInventoryTransferAction.isValid
        function ISInventoryTransferAction:isValid()
            if isOfflineVisualContainer(self.srcContainer) or isOfflineVisualContainer(self.destContainer) then
                return false
            end
            return baseIsValid(self)
        end
        ISInventoryTransferAction.OfflineSurvivorV2Guard = true
    end

    -- Some inventory actions create their transfer action through this helper.
    -- Keep an explicit guard here as well, including for UI paths added by
    -- other mods that don't call ISInventoryPane directly.
    if ISInventoryTransferUtil and not ISInventoryTransferUtil.OfflineSurvivorV2Guard then
        local baseNewTransferAction = ISInventoryTransferUtil.newInventoryTransferAction
        function ISInventoryTransferUtil.newInventoryTransferAction(character, item, srcContainer, destContainer, time)
            local action = baseNewTransferAction(character, item, srcContainer, destContainer, time)
            if action and (isOfflineVisualContainer(srcContainer) or isOfflineVisualContainer(destContainer)) then
                function action:isValid()
                    return false
                end
            end
            return action
        end
        ISInventoryTransferUtil.OfflineSurvivorV2Guard = true
    end

    if ISInventoryPane and not ISInventoryPane.OfflineSurvivorV2Guard then
        local baseRefreshContainer = ISInventoryPane.refreshContainer
        local baseLootAll = ISInventoryPane.lootAll
        local baseTransferAll = ISInventoryPane.transferAll
        local baseTransferItemsByWeight = ISInventoryPane.transferItemsByWeight
        local baseOnMouseDoubleClick = ISInventoryPane.onMouseDoubleClick

        function ISInventoryPane:refreshContainer()
            if isOfflineVisualContainer(self.inventory) then
                -- Never display the renderer-only items, even if another UI
                -- selected this container before the corpse was sealed.
                self.items = {}
                self.itemslist = {}
                self.itemindex = {}
                self.selected = {}
                return
            end
            return baseRefreshContainer(self)
        end

        function ISInventoryPane:lootAll()
            if isOfflineVisualContainer(self.inventory) then return end
            return baseLootAll(self)
        end

        function ISInventoryPane:transferAll()
            if isOfflineVisualContainer(self.inventory) then return end
            return baseTransferAll(self)
        end

        function ISInventoryPane:transferItemsByWeight(items, container)
            if isOfflineVisualContainer(self.inventory) or isOfflineVisualContainer(container) then return end
            for _, item in ipairs(items or {}) do
                local source = nil
                pcall(function() source = item:getContainer() end)
                if isOfflineVisualContainer(source) then return end
            end
            return baseTransferItemsByWeight(self, items, container)
        end

        function ISInventoryPane:onMouseDoubleClick(x, y)
            if isOfflineVisualContainer(self.inventory) then return end
            return baseOnMouseDoubleClick(self, x, y)
        end
        ISInventoryPane.OfflineSurvivorV2Guard = true
    end

    if ISInventoryPage and not ISInventoryPage.OfflineSurvivorV2Guard then
        local baseSetNewContainer = ISInventoryPage.setNewContainer
        function ISInventoryPage:setNewContainer(inventory)
            if isOfflineVisualContainer(inventory) then return end
            return baseSetNewContainer(self, inventory)
        end
        ISInventoryPage.OfflineSurvivorV2Guard = true
    end

    -- Keep burning disabled. Dragging is allowed only through the server-
    -- validated custom action below, which then starts B42's native animation.
    if ISGrabCorpseAction and not ISGrabCorpseAction.OfflineSurvivorV2Guard then
        local baseIsValid = ISGrabCorpseAction.isValid
        function ISGrabCorpseAction:isValid()
            -- B42 uses corpseBody, while a few compatibility paths still use
            -- corpse. The native action is permitted only while this Sandbox
            -- option is on; the server also authorizes each drag session.
            if isOfflineVisualObject(self.corpseBody) or isOfflineVisualObject(self.corpse) then
                return OS.getOption("AllowBodyDragging", true) ~= false
            end
            return baseIsValid(self)
        end
        ISGrabCorpseAction.OfflineSurvivorV2Guard = true
    end

    if ISBurnCorpseAction and not ISBurnCorpseAction.OfflineSurvivorV2Guard then
        local baseIsValid = ISBurnCorpseAction.isValid
        function ISBurnCorpseAction:isValid()
            if isOfflineVisualObject(self.corpse) then return false end
            return baseIsValid(self)
        end
        ISBurnCorpseAction.OfflineSurvivorV2Guard = true
    end
end

installVisualCloneGuards()

local function offlineData(object)
    if not object then return nil end
    local ok, data = pcall(function() return object:getModData() end)
    if ok and data and data[OS.OFFLINE_MARKER] and data.steamId then return data end
    return nil
end

local function findOfflineObject(worldObjects)
    for _, object in ipairs(worldObjects or {}) do
        local data = offlineData(object)
        if data then
            sealOfflineVisualCorpse(object)
            return object, data
        end
    end

    -- A corpse is in staticMovingObjects, not square.objects. World context
    -- callbacks do not always include it, so inspect its square explicitly.
    local firstObject = worldObjects and worldObjects[1]
    if not firstObject then return nil, nil end
    local ok, square = pcall(function() return firstObject:getSquare() end)
    if not ok or not square then return nil, nil end

    local function findOnSquare(list)
        if not list then return nil, nil end
        for index = 0, list:size() - 1 do
            local object = list:get(index)
            local data = offlineData(object)
            if data then
                sealOfflineVisualCorpse(object)
                return object, data
            end
        end
        return nil, nil
    end

    local object, data = findOnSquare(square:getStaticMovingObjects())
    if object then return object, data end
    return findOnSquare(square:getObjects())
end

local function optionReferencesObject(option, object)
    if not option or not object then return false end
    if option.target == object then return true end
    for index = 1, 10 do
        if option["param" .. index] == object then return true end
    end
    return false
end

local function removeMenuOption(menu, index)
    local option = menu.options[index]
    if option and menu.optionPool then table.insert(menu.optionPool, option) end
    table.remove(menu.options, index)
    menu.numOptions = #menu.options + 1
    for optionIndex, remaining in ipairs(menu.options) do
        remaining.id = optionIndex
    end
end

-- OnFillWorldObjectContextMenu runs after the base game has added its corpse
-- entries. Remove only options whose arguments reference this exact offline
-- body, leaving normal ground items and real corpses on the same square alone.
local function removeNativeCorpseOptions(menu, corpse)
    if not menu or not menu.options then return false end
    local changed = false
    for index = #menu.options, 1, -1 do
        local option = menu.options[index]
        local subMenu = option and option.subOption and menu:getSubMenu(option.subOption) or nil
        if subMenu and removeNativeCorpseOptions(subMenu, corpse) then changed = true end
        if optionReferencesObject(option, corpse) or (subMenu and #subMenu.options == 0) then
            removeMenuOption(menu, index)
            changed = true
        end
    end
    if changed then
        menu:calcHeight()
        menu:setWidth(menu:calcWidth())
    end
    return changed
end

local function notify(message)
    message = tostring(localizeServerMessage(message) or "")
    if message == "" then return end

    local player = getSpecificPlayer(0)
    if player and HaloTextHelper and HaloTextHelper.addText then
        local ok = pcall(function() HaloTextHelper.addText(player, message) end)
        if ok then return end
    end
    if player and player.Say then
        pcall(function() player:Say(message) end)
    else
        print("[OfflineSurvivor V2] " .. message)
    end
end

function OS.requestLoot(_, playerIndex, targetSteamId)
    if not targetSteamId then return end
    local player = getSpecificPlayer(playerIndex or 0)
    if not player then return end

    sendClientCommand(player, OS.MODULE, OS.COMMAND_REQUEST_LOOT, {
        targetSteamId = tostring(targetSteamId),
    })
end

function OS.requestBodyDrag(_, playerIndex, targetSteamId, object)
    if not targetSteamId or OS.getOption("AllowBodyDragging", true) == false then return end
    -- One client-side native release cleanup is active at a time. Starting a
    -- second drag before the first server confirmation would overwrite its
    -- captured Java references and can leave a visual remnant behind.
    if pendingBodyDrag or deferredDragCleanup then return end
    local player = getSpecificPlayer(playerIndex or 0)
    if not player or not object or not isOfflineVisualObject(object) then return end

    pendingBodyDrag = {
        playerIndex = playerIndex or 0,
        targetSteamId = tostring(targetSteamId),
        object = object,
        requestedAt = tonumber(getTimestamp()) or 0,
    }
    nextLocalDragToken = nextLocalDragToken + 1
    pendingBodyDrag.localDragToken = tostring(pendingBodyDrag.requestedAt)
        .. ":" .. tostring(nextLocalDragToken) .. ":" .. pendingBodyDrag.targetSteamId
    pcall(function()
        pendingBodyDrag.sourceX = object:getX()
        pendingBodyDrag.sourceY = object:getY()
        pendingBodyDrag.sourceZ = object:getZ()
        object:getModData()[LOCAL_DRAG_TOKEN_KEY] = pendingBodyDrag.localDragToken
    end)
    sendClientCommand(player, OS.MODULE, OS.COMMAND_REQUEST_BODY_DRAG, {
        targetSteamId = pendingBodyDrag.targetSteamId,
    })
end

local function cancelPendingBodyDrag(pending)
    local player = pending and getSpecificPlayer(pending.playerIndex) or nil
    if not player then return end
    sendClientCommand(player, OS.MODULE, OS.COMMAND_FINISH_BODY_DRAG, {
        targetSteamId = pending.targetSteamId,
        sessionToken = pending.sessionToken,
        cancel = true,
    })
end

-- B42 turns an IsoDeadBody into a temporary, client-local IsoZombie while the
-- native dragging animation is playing.  Keep that exact object (rather than
-- looking it up only after the animation ends) so it cannot be left behind as
-- an ordinary, lootable corpse when the server recreates the protected proxy.
local function captureDraggedProxy(pending, player)
    if not pending or not player then return false end

    local target = nil
    pcall(function() target = player:getGrapplingTarget() end)
    -- GrapplerLetGo happens before B42 clears its target, but the two-tick
    -- release delay happens afterwards. Use the exact temporary zombie saved
    -- while dragging when getGrapplingTarget() has already become nil.
    if not target then target = pending.dragProxy end
    -- Do not overwrite a captured temporary zombie with the original
    -- IsoDeadBody. The native action can expose both at different animation
    -- frames; only the temporary zombie must be removed at release. A native
    -- reanimation can briefly expose the zombie before its ModData is copied
    -- on a multiplayer client. The pending action was created from our marked
    -- corpse, therefore that exact temporary IsoZombie is still safe to claim.
    local isTemporaryZombie = false
    pcall(function() isTemporaryZombie = instanceof(target, "IsoZombie") end)
    if isTemporaryZombie then
        -- The native release path creates a brand-new IsoDeadBody from this
        -- zombie. Its ModData is copied by the engine, so this client-only
        -- token survives the conversion and lets the cleanup distinguish that
        -- temporary body from the protected body later sent by the server.
        pcall(function() target:getModData()[LOCAL_DRAG_TOKEN_KEY] = pending.localDragToken end)
        pending.dragProxy = target
    else
        local data = offlineData(target)
        if not data or tostring(data.steamId) ~= pending.targetSteamId then return false end
    end

    local positionObject = pending.dragProxy or target
    pcall(function()
        pending.dragX = positionObject:getX()
        pending.dragY = positionObject:getY()
        pending.dragZ = positionObject:getZ()
    end)
    return pending.dragX ~= nil and pending.dragY ~= nil and pending.dragZ ~= nil
end

-- The server must remove the authoritative proxy only after B42 has actually
-- lifted it. The native action is client-side, so this acknowledgement is the
-- one point where both sides agree that the old square is no longer occupied.
local function confirmNativeBodyDragPickup(pending, player)
    if not pending or not player or pending.pickupSent then return end
    captureDraggedProxy(pending, player)
    pending.pickupSent = true
    sendClientCommand(player, OS.MODULE, OS.COMMAND_BODY_DRAG_PICKED_UP, {
        targetSteamId = pending.targetSteamId,
        sessionToken = pending.sessionToken,
    })
end

local function getNativeObjectId(object)
    if not object then return nil end

    -- B42 exposes getObjectIDAsLong() on IsoDeadBody, not every IsoObject.
    -- This helper also examines movingObjects and square.objects, so calling
    -- the method before this type check makes Kahlua abort the OnTick handler
    -- when it reaches an ordinary object or a drag-surrogate zombie.
    local isCorpse = false
    pcall(function() isCorpse = instanceof(object, "IsoDeadBody") end)
    if not isCorpse then return nil end

    local objectId = nil
    pcall(function() objectId = object:getObjectIDAsLong() end)
    return objectId
end

local function removeLocalDragRemnant(object)
    if not object then return end
    -- These are only client-local native drag remnants. Never use
    -- IsoGridSquare:removeCorpse(..., false) here because that would send a
    -- second invalid multiplayer remove packet. `true` is the local/remote
    -- removal path and also refreshes the corpse inventory UI correctly.
    local isCorpse = false
    pcall(function() isCorpse = instanceof(object, "IsoDeadBody") end)
    if isCorpse then
        local square = nil
        pcall(function() square = object:getSquare() end)
        if square then
            pcall(function() square:removeCorpse(object, true) end)
        else
            pcall(function() object:removeFromWorld() end)
            pcall(function() object:removeFromSquare() end)
        end
    else
        pcall(function() object:removeFromWorld() end)
        pcall(function() object:removeFromSquare() end)
    end
    sealedVisualContainers[object] = nil
end

local function queueStaleBodyCleanup(args)
    local targetSteamId = args and args.targetSteamId and tostring(args.targetSteamId) or nil
    local x = tonumber(args and args.x)
    local y = tonumber(args and args.y)
    local z = tonumber(args and args.z)
    if not targetSteamId or x == nil or y == nil or z == nil then return end

    local objectId = args and args.objectId and tostring(args.objectId) or nil
    local key = targetSteamId .. ":" .. tostring(math.floor(x)) .. ":"
        .. tostring(math.floor(y)) .. ":" .. tostring(math.floor(z)) .. ":" .. tostring(objectId or "")
        .. ":" .. tostring(args.bodyEpoch or "") .. ":" .. tostring(args.bodyRevision or "")
    staleBodyCleanups[key] = {
        targetSteamId = targetSteamId,
        x = x,
        y = y,
        z = z,
        objectId = objectId,
        bodyEpoch = args.bodyEpoch,
        bodyRevision = args.bodyRevision,
        expiresAt = (tonumber(getTimestamp()) or 0) + OS.STALE_BODY_CLEANUP_SECONDS,
    }
end

local function isStaleOfflineBodyRemnant(object, cleanup)
    if not object or not cleanup then return false end

    local data = offlineData(object)
    if H.cleanupMatches(data, cleanup) then
        return true
    end

    -- A late AddCorpse packet may have lost ModData. An exact native object id
    -- is still safe; never use an unassigned (-1) id as a broad match.
    if not cleanup.objectId or cleanup.objectId == "" or cleanup.objectId == "-1" then return false end
    local candidateId = getNativeObjectId(object)
    return candidateId ~= nil and tostring(candidateId) == cleanup.objectId
end

local function processStaleBodyCleanups()
    local hasCleanups = false
    for _ in pairs(staleBodyCleanups) do
        hasCleanups = true
        break
    end
    if not hasCleanups then return end
    local cell = getCell()
    if not cell then return end

    local current = tonumber(getTimestamp()) or 0
    for key, cleanup in pairs(staleBodyCleanups) do
        if current >= (cleanup.expiresAt or 0) then
            staleBodyCleanups[key] = nil
        else
            local centerX = math.floor(cleanup.x)
            local centerY = math.floor(cleanup.y)
            local centerZ = math.floor(cleanup.z)
            for tileX = centerX - 1, centerX + 1 do
                for tileY = centerY - 1, centerY + 1 do
                    local square = cell:getGridSquare(tileX, tileY, centerZ)
                    if square then
                        local function sweep(list)
                            if not list then return end
                            for index = list:size() - 1, 0, -1 do
                                local candidate = list:get(index)
                                if isStaleOfflineBodyRemnant(candidate, cleanup) then
                                    removeLocalDragRemnant(candidate)
                                end
                            end
                        end
                        sweep(square:getStaticMovingObjects())
                        sweep(square:getMovingObjects())
                        sweep(square:getObjects())
                    end
                end
            end
        end
    end
end

local function hasLocalDragToken(object, cleanup)
    if not object or not cleanup or not cleanup.localDragToken then return false end
    local data = nil
    pcall(function() data = object:getModData() end)
    return data and tostring(data[LOCAL_DRAG_TOKEN_KEY] or "") == tostring(cleanup.localDragToken)
end

local function clearLocalDragToken(object)
    if not object then return end
    pcall(function() object:getModData()[LOCAL_DRAG_TOKEN_KEY] = nil end)
end

local function isReleasedSourceRemnant(object, cleanup)
    if not object or not cleanup then return false end
    if object == cleanup.sourceObject then return true end
    if hasLocalDragToken(object, cleanup) then return true end

    local data = offlineData(object)
    if H.cleanupMatches(data, cleanup) then return true end

    -- A late AddCorpse packet can recreate the original source with an empty
    -- ModData table. Its original network object id still identifies it, but
    -- -1 is a local/unassigned id and must never be used as a broad match.
    local sourceId = tonumber(cleanup.sourceObjectId)
    if sourceId == nil or sourceId == -1 then return false end
    local candidateId = tonumber(getNativeObjectId(object))
    return candidateId ~= nil and candidateId == sourceId
end

local function sweepReleasedDragRemnants(cleanup)
    local cell = getCell()
    if not cell then return end

    local function isDeadBodyOrZombie(object)
        local result = false
        pcall(function()
            result = instanceof(object, "IsoDeadBody") or instanceof(object, "IsoZombie")
        end)
        return result
    end

    local function sweepSource()
        if not cleanup.sweepSource then return end
        local square = cell:getGridSquare(math.floor(cleanup.sourceX), math.floor(cleanup.sourceY), math.floor(cleanup.sourceZ))
        if not square then return end
        local function sweepList(list)
            if not list then return end
            for index = list:size() - 1, 0, -1 do
                local candidate = list:get(index)
                if isDeadBodyOrZombie(candidate) and isReleasedSourceRemnant(candidate, cleanup) then
                    removeLocalDragRemnant(candidate)
                end
            end
        end
        sweepList(square:getStaticMovingObjects())
        sweepList(square:getMovingObjects())
    end

    local function sweepDestinationRemnants()
        if cleanup.finalX == nil or cleanup.finalY == nil or cleanup.finalZ == nil then return end
        -- The release animation can place the temporary corpse one tile behind
        -- the player. Search a tiny area, but remove *only* objects stamped by
        -- this local drag token. The server-created protected corpse has the
        -- Offline Survivor marker but never this client-only token.
        local centerX = math.floor(cleanup.finalX)
        local centerY = math.floor(cleanup.finalY)
        local centerZ = math.floor(cleanup.finalZ)
        for tileX = centerX - 1, centerX + 1 do
            for tileY = centerY - 1, centerY + 1 do
                local square = cell:getGridSquare(tileX, tileY, centerZ)
                if square then
                    local function sweepList(list)
                        if not list then return end
                        for index = list:size() - 1, 0, -1 do
                            local candidate = list:get(index)
                            if isDeadBodyOrZombie(candidate) and hasLocalDragToken(candidate, cleanup) then
                                removeLocalDragRemnant(candidate)
                            end
                        end
                    end
                    -- Before the engine completes the release the surrogate is
                    -- in movingObjects; afterwards it is a new IsoDeadBody in
                    -- staticMovingObjects. Both carry the same local token.
                    sweepList(square:getMovingObjects())
                    sweepList(square:getStaticMovingObjects())
                end
            end
        end
    end

    sweepSource()
    sweepDestinationRemnants()
end

local function queueDraggedProxyCleanup(pending)
    if not pending or (not pending.dragProxy and not pending.object) then return end
    -- B42 leaves a client-local reanimated IsoZombie on release. It is never a
    -- synchronized corpse, so remove it after the native release is complete;
    -- the final coordinate has already been sent to the server, which creates
    -- the protected proxy at that square. Keep the original IsoDeadBody too:
    -- reanimate() can leave that now-empty local object visible at the source.
    deferredDragCleanup = {
        object = pending.dragProxy,
        sourceObject = pending.object,
        targetSteamId = pending.targetSteamId,
        sessionToken = pending.sessionToken,
        playerIndex = pending.playerIndex,
        waitingForRelease = true,
        ticks = 2,
        expiresAt = (tonumber(getTimestamp()) or 0) + 15,
        sourceX = pending.sourceX,
        sourceY = pending.sourceY,
        sourceZ = pending.sourceZ,
        finalX = pending.finalX,
        finalY = pending.finalY,
        finalZ = pending.finalZ,
        sourceObjectId = getNativeObjectId(pending.object),
        bodyEpoch = pending.object and pending.object:getModData().bodyEpoch,
        bodyRevision = pending.object and pending.object:getModData().bodyRevision,
        localDragToken = pending.localDragToken,
        sweepSource = pending.sourceX ~= nil and pending.sourceY ~= nil and pending.sourceZ ~= nil
            and pending.finalX ~= nil and pending.finalY ~= nil and pending.finalZ ~= nil
            and (math.floor(pending.sourceX) ~= math.floor(pending.finalX)
                or math.floor(pending.sourceY) ~= math.floor(pending.finalY)
                or math.floor(pending.sourceZ) ~= math.floor(pending.finalZ)),
    }
end

local function cleanDeferredDraggedProxy()
    local cleanup = deferredDragCleanup
    if not cleanup then return end

    if cleanup.waitingForRelease then
        local player = getSpecificPlayer(cleanup.playerIndex or 0)
        local dragging = false
        pcall(function() dragging = player and player:isDraggingCorpse() == true end)
        if dragging then return end
        cleanup.waitingForRelease = false
        cleanup.ticks = 2
        return
    end
    if cleanup.ticks and cleanup.ticks > 0 then
        cleanup.ticks = cleanup.ticks - 1
        return
    end

    if not cleanup.temporaryRemoved then
        cleanup.temporaryRemoved = true
        local proxy = cleanup.object
        local isTemporaryZombie = false
        pcall(function() isTemporaryZombie = instanceof(proxy, "IsoZombie") end)
        -- This is the exact object that was verified while grappling. Do not
        -- require its ModData here: B42 may clear/replace data while converting
        -- the temporary zombie into a lootable corpse after release.
        if isTemporaryZombie then
            pcall(function() proxy:removeFromWorld() end)
            pcall(function() proxy:removeFromSquare() end)
        end
        cleanup.object = nil
    end

    if cleanup.completed == true then
        local source = cleanup.sourceObject
        local isSourceCorpse = false
        pcall(function() isSourceCorpse = instanceof(source, "IsoDeadBody") end)
        -- Only after the server confirms a successful move, remove the exact
        -- original client corpse. This prevents the empty/naked source remnant
        -- while keeping a source body intact if the server rejects the drop.
        if isSourceCorpse then
            removeLocalDragRemnant(source)
        end
        sweepReleasedDragRemnants(cleanup)
        -- Removal and the native release packet may cross on the client. Keep
        -- the verified source reference briefly and repeat this local cleanup
        -- if B42 re-adds that same empty corpse after network delivery.
        cleanup.sourceTicks = (cleanup.sourceTicks or 120) - 1
        if cleanup.sourceTicks <= 0 then deferredDragCleanup = nil end
        return
    end

    if cleanup.failed == true or (tonumber(getTimestamp()) or 0) >= (cleanup.expiresAt or 0) then
        -- Never retain detached Java objects if the result packet was lost.
        clearLocalDragToken(cleanup.sourceObject)
        clearLocalDragToken(cleanup.object)
        deferredDragCleanup = nil
    else
        -- The server's authoritative replacement is created on its next scan,
        -- which can be up to one second later. Hide only the source/destination
        -- remnants identified by this exact local drag meanwhile.
        sweepReleasedDragRemnants(cleanup)
    end
end

local function startNativeBodyDrag(args)
    local pending = pendingBodyDrag
    if not pending or tostring(args.targetSteamId or "") ~= pending.targetSteamId then return end
    pending.sessionToken = args.sessionToken

    local player = getSpecificPlayer(pending.playerIndex)
    local data = offlineData(pending.object)
    if not player or not data or tostring(data.steamId) ~= pending.targetSteamId then
        pendingBodyDrag = nil
        cancelPendingBodyDrag(pending)
        notify("The sleeping survivor is no longer available.")
        return
    end

    local ok, action = pcall(function()
        return ISGrabCorpseAction:new(player, pending.object)
    end)
    if not ok or not action then
        pendingBodyDrag = nil
        cancelPendingBodyDrag(pending)
        notify("The native body-drag action is unavailable.")
        return
    end
    -- Capture the engine-created grappling zombie in the same call that picks
    -- the corpse up. Waiting for OnTick can be too late: B42 may have already
    -- converted it to an ordinary dead body by then.
    local nativeComplete = action.complete
    function action:complete()
        local completed = nativeComplete(self)
        if completed == true then
            captureDraggedProxy(pending, self.character)
            confirmNativeBodyDragPickup(pending, self.character)
        end
        return completed
    end
    local queued = pcall(function() ISTimedActionQueue.add(action) end)
    if not queued then
        pendingBodyDrag = nil
        cancelPendingBodyDrag(pending)
        notify("The native body-drag action is unavailable.")
    else
        pending.startedAt = tonumber(getTimestamp()) or 0
    end
end

local function finishNativeBodyDrag(pending, player, result)
    if pendingBodyDrag ~= pending then return end
    captureDraggedProxy(pending, player)
    local x, y, z = pending.dragX, pending.dragY, pending.dragZ

    -- A few B42 paths leave the temporary proxy's coordinates at its pickup
    -- tile for a frame. If the player has genuinely carried it away, use the
    -- player's current square rather than telling the server to recreate the
    -- protected body at the old location.
    local playerX, playerY, playerZ = nil, nil, nil
    pcall(function()
        playerX = player:getX()
        playerY = player:getY()
        playerZ = player:getZ()
    end)
    local proxyStillAtSource = x ~= nil and y ~= nil and z ~= nil
        and pending.sourceX ~= nil and pending.sourceY ~= nil and pending.sourceZ ~= nil
        and math.floor(x) == math.floor(pending.sourceX)
        and math.floor(y) == math.floor(pending.sourceY)
        and math.floor(z) == math.floor(pending.sourceZ)
    if proxyStillAtSource and playerX ~= nil and playerY ~= nil and playerZ ~= nil then
        local carriedX = playerX - pending.sourceX
        local carriedY = playerY - pending.sourceY
        if (carriedX * carriedX) + (carriedY * carriedY) > 1.0 then
            x, y, z = playerX, playerY, playerZ
        end
    end
    pending.finalX, pending.finalY, pending.finalZ = x, y, z
    queueDraggedProxyCleanup(pending)
    pendingBodyDrag = nil

    if tostring(result or ""):lower() == "aborted" then
        cancelPendingBodyDrag(pending)
        return
    end
    if x == nil or y == nil or z == nil then
        cancelPendingBodyDrag(pending)
        return
    end

    sendClientCommand(player, OS.MODULE, OS.COMMAND_FINISH_BODY_DRAG, {
        targetSteamId = pending.targetSteamId,
        sessionToken = pending.sessionToken,
        x = x,
        y = y,
        z = z,
    })
end

-- Keep the server-side drag lease alive only while B42's native corpse-drag
-- action is actually active. If this client loses the action or disconnects,
-- the server lease expires within a few seconds instead of blocking all
-- interactions with that sleeping survivor.
local function refreshNativeBodyDragLease(pending, player)
    if not pending or not player then return end

    local current = tonumber(getTimestamp()) or 0
    if pending.nextHeartbeatAt and current < pending.nextHeartbeatAt then return end

    pending.nextHeartbeatAt = current + 5
    sendClientCommand(player, OS.MODULE, OS.COMMAND_BODY_DRAG_HEARTBEAT, {
        targetSteamId = pending.targetSteamId,
        sessionToken = pending.sessionToken,
    })
end

local function onGrapplerLetGo(character, result)
    local pending = pendingBodyDrag
    if not pending then return end

    local player = getSpecificPlayer(pending.playerIndex)
    if character ~= player then return end

    -- This event fires before LetGoOfGrappled completes. Keep the target and
    -- wait two ticks; otherwise B42 can report the origin instead of the tile
    -- where the corpse was really dropped.
    local captured = captureDraggedProxy(pending, player)
    if captured or pending.wasDragging then
        -- Fallback for multiplayer clients that do not report
        -- isDraggingCorpse() during the first animation tick.
        confirmNativeBodyDragPickup(pending, player)
    end
    pending.releasePending = true
    pending.releaseResult = result or "Dropped"
    pending.releaseTicks = 2
end

local function addOfflineContext(playerIndex, context, worldObjects, test)
    if test or not OS.isEnabled() then return end

    local object, data = findOfflineObject(worldObjects)
    if not data then return end

    sealOfflineVisualCorpse(object)
    removeNativeCorpseOptions(context, object)

    if data.deferredDeath == true then
        local label = context:addOption(OS.translate("DeathPending", "This survivor has already died."), nil, nil)
        label.notAvailable = true
        return
    end

    if data.testDefeated == true then
        local label = context:addOption(OS.translate("TestBodyDefeated", "Administrator test body was defeated."), nil, nil)
        label.notAvailable = true
        return
    end

    local displayName = (data.testBody == true and OS.translate("TestPrefix", "[TEST] ") or "")
        .. (data.username or OS.translate("Player", "Player"))
    local label = context:addOption(OS.translate("Resting", "%1 is resting.", displayName), nil, nil)
    label.notAvailable = true

    local option = context:addOption(OS.translate("Search", "Search"), OS, OS.requestLoot, playerIndex, data.steamId)
    if OS.getOption("EnableLoot", true) == false then option.notAvailable = true end

    if OS.getOption("AllowBodyDragging", true) ~= false then
        context:addOption(OS.translate("Drag", "Drag Sleeping Survivor"), OS, OS.requestBodyDrag, playerIndex, data.steamId, object)
    end
end

local function isUsableZombie(zombie)
    if not zombie then return false end

    local usable = false
    pcall(function()
        usable = instanceof(zombie, "IsoZombie")
            and zombie:isDead() ~= true
            and zombie:isNoTeeth() ~= true
            and zombie:isCrawling() ~= true
            and zombie:isReanimatedForGrappleOnly() ~= true
    end)
    return usable
end

local function isUsableLocalZombie(zombie)
    if not isUsableZombie(zombie) then return false end

    local localZombie = false
    pcall(function() localZombie = zombie:isLocal() == true end)
    return localZombie
end

local function isZombieEatingProxy(zombie, proxy)
    local eating = false
    pcall(function()
        -- getEatingZombies() is populated by ZombieEatBodyState itself.  It is
        -- more reliable than sampling the short state-name/target transition
        -- between native eating animation cycles.
        if zombie:getEatBodyTarget() == proxy then
            eating = true
            return
        end
        local eaters = proxy:getEatingZombies()
        if not eaters then return end
        for index = 0, eaters:size() - 1 do
            if eaters:get(index) == zombie then
                eating = true
                return
            end
        end
    end)
    return eating
end

local function reportLocalZombieFeeding(player, zombie, proxy, data, current)
    local zombieId = nil
    local x, y, z = nil, nil, nil
    pcall(function()
        zombieId = tostring(zombie:getOnlineID())
        x = proxy:getX()
        y = proxy:getY()
        z = proxy:getZ()
    end)
    if not zombieId or not x or not y or not z then return end

    local key = tostring(data.steamId) .. ":" .. zombieId
    local previous = tonumber(zombieFeedReportAt[key])
    if previous and current - previous < OS.ZOMBIE_FEED_REPORT_SECONDS then return end

    zombieFeedReportAt[key] = current
    sendClientCommand(player, OS.MODULE, OS.COMMAND_ZOMBIE_FEEDING, {
        targetSteamId = tostring(data.steamId),
        zombieId = zombieId,
        x = x,
        y = y,
        z = z,
    })
end

-- In multiplayer the client that owns a zombie runs its eating state. Calling
-- setBodyToEat() from the server only sets a field, so feed the local zombie
-- here and let the server decide whether the observed feeding kills the body.
local function lureLocalZombiesToOfflineBodies()
    local player = getSpecificPlayer(0)
    local cell = getCell()
    if not player or not cell then return end

    local playerX, playerY, playerZ = nil, nil, nil
    pcall(function()
        playerX = math.floor(player:getX())
        playerY = math.floor(player:getY())
        playerZ = math.floor(player:getZ())
    end)
    if playerX == nil or playerY == nil or playerZ == nil then return end

    local bodies = {}
    local radius = OS.ZOMBIE_LURE_RADIUS
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = cell:getGridSquare(playerX + dx, playerY + dy, playerZ)
            local objects = square and square:getStaticMovingObjects() or nil
            if objects then
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    local data = offlineData(object)
                    local isCorpse = false
                    pcall(function() isCorpse = instanceof(object, "IsoDeadBody") end)
                    if isCorpse and data and data[OS.OFFLINE_MARKER]
                        and data.renderer == OS.RENDERER and data.deferredDeath ~= true
                        and data.testDefeated ~= true then
                        table.insert(bodies, { object = object, data = data })
                    end
                end
            end
        end
    end
    if #bodies == 0 then return end

    local zombies = cell:getZombieList()
    if not zombies then return end
    local current = tonumber(getTimestamp()) or 0
    local radiusSq = radius * radius

    for _, body in ipairs(bodies) do
        local proxy, data = body.object, body.data
        local bodyX, bodyY, bodyZ = nil, nil, nil
        pcall(function()
            bodyX = proxy:getX()
            bodyY = proxy:getY()
            bodyZ = math.floor(proxy:getZ())
        end)
        if bodyX ~= nil and bodyY ~= nil and bodyZ ~= nil then
            local assigned = 0
            for index = 0, zombies:size() - 1 do
                if assigned >= OS.ZOMBIE_MAX_EATERS then break end
                local zombie = zombies:get(index)
                if isUsableZombie(zombie) then
                    local inRange = false
                    local target = nil
                    local eatTarget = nil
                    pcall(function()
                        local dx = zombie:getX() - bodyX
                        local dy = zombie:getY() - bodyY
                        inRange = math.floor(zombie:getZ()) == bodyZ and (dx * dx) + (dy * dy) <= radiusSq
                        target = zombie:getTarget()
                        eatTarget = zombie:getEatBodyTarget()
                    end)
                    if inRange and isZombieEatingProxy(zombie, proxy) then
                        assigned = assigned + 1
                        reportLocalZombieFeeding(player, zombie, proxy, data, current)
                    elseif isUsableLocalZombie(zombie) and inRange and not target and not eatTarget then
                        local lure = localZombieLures[zombie]
                        if not lure or current >= (lure.expiresAt or 0) then
                            local assignedTarget = pcall(function() zombie:setBodyToEat(proxy) end)
                            if assignedTarget then
                                localZombieLures[zombie] = {
                                    expiresAt = current + OS.ZOMBIE_CLIENT_LURE_COOLDOWN_SECONDS,
                                }
                                assigned = assigned + 1
                            end
                        end
                    end
                end
            end
        end
    end

    for key, reportedAt in pairs(zombieFeedReportAt) do
        if current - tonumber(reportedAt) > OS.ZOMBIE_FEED_REPORT_TTL_SECONDS * 3 then
            zombieFeedReportAt[key] = nil
        end
    end
end

local function sealNearbyOfflineCorpses()
    sealScanTick = sealScanTick + 1
    processStaleBodyCleanups()
    cleanDeferredDraggedProxy()
    local pending = pendingBodyDrag
    if pending then
        local dragPlayer = getSpecificPlayer(pending.playerIndex)
        captureDraggedProxy(pending, dragPlayer)
        local dragging = false
        pcall(function() dragging = dragPlayer and dragPlayer:isDraggingCorpse() == true end)
        if dragging then
            pending.wasDragging = true
            pending.releasePending = nil
            pending.releaseTicks = nil
            confirmNativeBodyDragPickup(pending, dragPlayer)
            refreshNativeBodyDragLease(pending, dragPlayer)
        elseif pending.wasDragging then
            -- B42.20 does not expose GrapplerLetGo on every multiplayer
            -- client. Poll the native dragging state as a fallback, but still
            -- wait for the release animation to publish the final coordinates.
            if not pending.releasePending then
                pending.releasePending = true
                pending.releaseResult = "Dropped"
                pending.releaseTicks = 2
            end
            pending.releaseTicks = (pending.releaseTicks or 2) - 1
            if pending.releaseTicks <= 0 then
                finishNativeBodyDrag(pending, dragPlayer, pending.releaseResult)
                pending = nil
            end
        elseif not pending.startedAt and (tonumber(getTimestamp()) or 0) - (pending.requestedAt or 0) >= 10 then
            -- Do not retain an object reference forever if StartBodyDrag never
            -- reaches this client (for example while changing map cells).
            queueDraggedProxyCleanup(pending)
            pendingBodyDrag = nil
            cancelPendingBodyDrag(pending)
            pending = nil
        end
    end
    if pending and pending.startedAt and (tonumber(getTimestamp()) or 0) - pending.startedAt >= 30 then
        local player = getSpecificPlayer(pending.playerIndex)
        local dragging = false
        pcall(function() dragging = player and player:isDraggingCorpse() == true end)
        if not dragging then
            queueDraggedProxyCleanup(pending)
            pendingBodyDrag = nil
            cancelPendingBodyDrag(pending)
        end
    end
    if sealScanTick % OS.ZOMBIE_CLIENT_SCAN_TICKS == 0 then
        lureLocalZombiesToOfflineBodies()
    end
    if sealScanTick % 60 ~= 0 then return end

    local player = getSpecificPlayer(0)
    if not player then return end
    local cell = getCell()
    if not cell then return end

    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    local z = math.floor(player:getZ())
    for dx = -4, 4 do
        for dy = -4, 4 do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            local objects = square and square:getStaticMovingObjects() or nil
            if objects then
                for index = 0, objects:size() - 1 do
                    sealOfflineVisualCorpse(objects:get(index))
                end
            end
        end
    end
end

local function onServerCommand(module, command, args)
    if module ~= OS.MODULE then return end
    args = args or {}

    if command == OS.COMMAND_OPEN_LOOT then
        OS.openLootUI(args)
    elseif command == OS.COMMAND_LOOT_RESULT then
        if OS.ActiveLootUI and tonumber(OS.ActiveLootUI.sessionId) == tonumber(args.sessionId) then
            OS.ActiveLootUI:finish()
        end
        notify(args.message)
    elseif command == OS.COMMAND_TELEPORT_TO_BODY then
        -- The server cannot move a remote player itself, so it asks us to.
        -- This is what puts a dragged survivor back where their body was left.
        local player = getSpecificPlayer(0)
        local x, y, z = tonumber(args and args.x), tonumber(args and args.y), tonumber(args and args.z)
        if player and x and y and z then
            -- The destination chunk is often not loaded yet because the player
            -- is still standing at their logout position.  Do not require a
            -- local IsoGridSquare before using the native client teleport: that
            -- circular check was what left dragged survivors at the old tile.
            local teleported = pcall(function() player:teleportTo(x, y, z) end)
            pcall(function()
                if not teleported then
                    player:setX(x)
                    player:setY(y)
                    player:setZ(z)
                    player:setNextX(x)
                    player:setNextY(y)
                    player:setLx(x)
                    player:setLy(y)
                end

                -- This makes a loaded destination settle immediately, but it is
                -- deliberately optional: teleportTo() streams an unloaded one.
                local cell = getCell()
                local square = cell and cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z)) or nil
                if square then player:setCurrentSquare(square) end
            end)
        end
    elseif command == OS.COMMAND_LOOT_NOTICE then
        notify(args.message)
    elseif command == OS.COMMAND_START_BODY_DRAG then
        startNativeBodyDrag(args)
    elseif command == OS.COMMAND_BODY_DRAG_RESULT then
        if deferredDragCleanup
            and args.targetSteamId
            and tostring(args.targetSteamId) == tostring(deferredDragCleanup.targetSteamId) then
            if args.completed == true then
                deferredDragCleanup.completed = true
            else
                deferredDragCleanup.failed = true
            end
        end
        pendingBodyDrag = nil
        notify(args.message)
    elseif command == "CancelRemovedBodyDrag" then
        if pendingBodyDrag and tostring(pendingBodyDrag.targetSteamId)==tostring(args.targetSteamId) then
            local player=getSpecificPlayer(pendingBodyDrag.playerIndex)
            queueDraggedProxyCleanup(pendingBodyDrag)
            pendingBodyDrag=nil
            if player then pcall(function() player:LetGoOfGrappled("Dropped") end) end
            if deferredDragCleanup then deferredDragCleanup.completed=true end
        end
    elseif command == OS.COMMAND_CLEANUP_STALE_BODY then
        queueStaleBodyCleanup(args)
    end
end

Events.OnFillWorldObjectContextMenu.Add(addOfflineContext)
Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(sealNearbyOfflineCorpses)
if Events.GrapplerLetGo and Events.GrapplerLetGo.Add then
    Events.GrapplerLetGo.Add(onGrapplerLetGo)
end
