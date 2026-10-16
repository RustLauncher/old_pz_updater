-- ============================================================
-- Chair Barricade - Project Zomboid Build 42.20+
--
-- Places a real (invisible) IsoBarricade on an IsoDoor while
-- displaying a green wooden chair as the visual barricade.
--
-- Right-click the door -> Remove Chair Barricade to restore the
-- door and return the exact chair type originally used.
-- ============================================================

BarricadeTheDoor = BarricadeTheDoor or {}
BarricadeTheDoor.VERSION = "3.0-B42"

local BARRICADE_NAME = "BarricadeChair"
local MODDATA_KEY = "chairBarricaded"
local NATIVE_MARKER = "chairBarricadeNative"

local HEALTH_MULT_BY_ENUM = {
    [1] = 1.0,
    [2] = 3.0,
    [3] = 5.0,
    [4] = 10.0,
}

local function getHealthMultiplier()
    local enumVal = 4
    if SandboxVars and SandboxVars.BarricadeTheDoor and SandboxVars.BarricadeTheDoor.DoorHealthMultiplier then
        enumVal = SandboxVars.BarricadeTheDoor.DoorHealthMultiplier
    end
    return HEALTH_MULT_BY_ENUM[enumVal] or 10.0
end

local CHAIR_SPRITES = {
    south = "furniture_seating_indoor_01_59",
    east  = "furniture_seating_indoor_01_58",
    north = "furniture_seating_indoor_01_57",
    west  = "furniture_seating_indoor_01_56",
}

local CHAIR_TYPES = {
    ["Base.Mov_GreenChair"] = true,
    ["Base.Mov_WoodenChair"] = true,
    ["Base.Mov_WhiteWoodenChair"] = true,
    ["Base.Mov_DarkWoodenChair"] = true,
    ["Base.Mov_RedWoodenChair"] = true,
    ["Base.Mov_PurpleWoodenChair"] = true,
    ["Base.Mov_PlasticChair"] = true,
    ["Base.Mov_BluePlasticChair"] = true,
    ["Base.Mov_BeachChair"] = true,
    ["Base.Mov_FoldingChair"] = true,
    ["Base.Mov_OfficeChair"] = true,
    ["Base.Mov_GreyChair"] = true,
    ["Base.Mov_DarkBlueChair"] = true,
    ["Base.Mov_RedChair"] = true,
    ["Base.Mov_OrangeModernChair"] = true,
    ["Base.Mov_YellowModernChair"] = true,
    ["Base.Mov_WhiteSimpleChair"] = true,
    ["Base.Mov_FancyBlackChair"] = true,
    ["Base.Mov_FancyWhiteChair"] = true,
    ["Base.Mov_BlueRattanChair"] = true,
    ["Base.Mov_PurpleRattanChair"] = true,
    ["Base.Mov_PileOCrepeChair"] = true,
    ["Base.Mov_WoodenStool"] = true,
    ["Base.Mov_MetalStool"] = true,
}

local EXCLUDE_KEYWORDS = {
    "comfy", "armchair", "sofa", "couch", "futon", "bench", "loveseat", "settee"
}

local function isDoor(object)
    return object and instanceof(object, "IsoDoor")
end

local function getModData(object)
    if not object or not object.getModData then return nil end
    return object:getModData()
end

local function containsAny(str, keywords)
    for _, kw in ipairs(keywords) do
        if string.find(str, kw, 1, true) then return true end
    end
    return false
end

local function isChairItem(item)
    if not item then return false end

    local fullType = item.getFullType and tostring(item:getFullType() or "") or ""
    local name = item.getName and tostring(item:getName() or "") or ""
    local lowerType = string.lower(fullType)
    local lowerName = string.lower(name)

    if containsAny(lowerType, EXCLUDE_KEYWORDS) or containsAny(lowerName, EXCLUDE_KEYWORDS) then
        return false
    end

    if CHAIR_TYPES[fullType] then return true end

    return string.find(lowerType, "chair", 1, true) ~= nil
        or string.find(lowerType, "stool", 1, true) ~= nil
        or string.find(lowerName, "chair", 1, true) ~= nil
        or string.find(lowerName, "stool", 1, true) ~= nil
end

local function getChairFromInventory(player)
    if not player then return nil end
    local inv = player:getInventory()
    if not inv then return nil end
    local items = inv:getItems()
    if not items then return nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isChairItem(item) then return item end
    end
    return nil
end

local function getPlayerSideOfDoor(player, door)
    local doorSquare = door and door:getSquare()
    local playerSquare = player and player:getCurrentSquare()
    if not doorSquare or not playerSquare then return "south" end

    if door:getNorth() then
        return (playerSquare:getY() >= doorSquare:getY()) and "south" or "north"
    else
        return (playerSquare:getX() >= doorSquare:getX()) and "east" or "west"
    end
end

local function getChairSquare(door, player)
    local doorSquare = door and door:getSquare()
    if not doorSquare then return nil end

    local side = getPlayerSideOfDoor(player, door)

    if door:getNorth() then
        local y = doorSquare:getY()
        if side == "north" then y = y - 1 end
        return getCell():getGridSquare(doorSquare:getX(), y, doorSquare:getZ()), side
    else
        local x = doorSquare:getX()
        if side == "west" then x = x - 1 end
        return getCell():getGridSquare(x, doorSquare:getY(), doorSquare:getZ()), side
    end
end

local function getChairDirection(door, playerSide)
    if door:getNorth() then
        return playerSide == "south" and "north" or "south"
    else
        return playerSide == "east" and "west" or "east"
    end
end

local function isBarricadeChair(object)
    return object
        and instanceof(object, "IsoThumpable")
        and object.getName
        and object:getName() == BARRICADE_NAME
end

local function getObjectsOnSquare(square)
    if not square or not square.getObjects then return nil end
    return square:getObjects()
end

local function findBarricadeChair(door)
    if not door then return nil end
    local data = getModData(door)

    local function scanSquare(square)
        local objects = getObjectsOnSquare(square)
        if not objects then return nil end
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if isBarricadeChair(object) then return object end
        end
        return nil
    end

    if data and data.chairBarricadeSquareX then
        local square = getCell():getGridSquare(
            data.chairBarricadeSquareX,
            data.chairBarricadeSquareY,
            data.chairBarricadeSquareZ
        )
        local chair = scanSquare(square)
        if chair then return chair end
    end

    local doorSquare = door:getSquare()
    if not doorSquare then return nil end

    local squares = {
        doorSquare,
        getCell():getGridSquare(doorSquare:getX() + 1, doorSquare:getY(), doorSquare:getZ()),
        getCell():getGridSquare(doorSquare:getX() - 1, doorSquare:getY(), doorSquare:getZ()),
        getCell():getGridSquare(doorSquare:getX(), doorSquare:getY() + 1, doorSquare:getZ()),
        getCell():getGridSquare(doorSquare:getX(), doorSquare:getY() - 1, doorSquare:getZ()),
    }

    for _, square in ipairs(squares) do
        local chair = scanSquare(square)
        if chair then return chair end
    end

    return nil
end

-- The native barricade is what actually stops IsoDoor from opening.
-- Build 42 exposes AddBarricadeToObject for BarricadeAble objects.
local function getNativeChairBarricade(door)
    if not door then return nil end

    local same = door.getBarricadeOnSameSquare and door:getBarricadeOnSameSquare() or nil
    if same and getModData(same) and getModData(same)[NATIVE_MARKER] == true then
        return same
    end

    local opposite = door.getBarricadeOnOppositeSquare and door:getBarricadeOnOppositeSquare() or nil
    if opposite and getModData(opposite) and getModData(opposite)[NATIVE_MARKER] == true then
        return opposite
    end

    return nil
end

local function ensureNativeChairBarricade(door, player)
    local existing = getNativeChairBarricade(door)
    if existing then
        if existing.setDoRender then existing:setDoRender(false) end
        return existing
    end

    local barricade = nil

    -- Prefer the character overload because it places the barricade on
    -- the side the player is actually standing on.
    if IsoBarricade and IsoBarricade.AddBarricadeToObject then
        if player then
            barricade = IsoBarricade.AddBarricadeToObject(door, player)
        end
        if not barricade then
            barricade = IsoBarricade.AddBarricadeToObject(door, false)
        end
    end

    if barricade then
        local bd = getModData(barricade)
        if bd then
            bd[NATIVE_MARKER] = true
        end
        if barricade.setDoRender then barricade:setDoRender(false) end
        if barricade.setHealth then barricade:setHealth(1000000) end
    end

    return barricade
end

local function removeNativeChairBarricade(door)
    if not door then return false end

    local barricade = getNativeChairBarricade(door)
    if not barricade then return false end

    local square = barricade:getSquare()
    if square and square.RemoveTileObject then
        square:RemoveTileObject(barricade)
    elseif barricade.removeFromWorld then
        barricade:removeFromWorld()
    end

    return true
end

local function setBarricadeState(door, state, chair)
    local data = getModData(door)
    if not data then return end

    data[MODDATA_KEY] = state

    if state and chair then
        local square = chair:getSquare()
        if square then
            data.chairBarricadeSquareX = square:getX()
            data.chairBarricadeSquareY = square:getY()
            data.chairBarricadeSquareZ = square:getZ()
        end
    else
        data.chairBarricadeSquareX = nil
        data.chairBarricadeSquareY = nil
        data.chairBarricadeSquareZ = nil
        -- Do NOT clear chairItemType / chairWorldSprite here.
        -- Removal clears those only after the chair has been returned.
    end

    if door.transmitModData then door:transmitModData() end
end

-- True inventory item types only (never tile/sprite names)
local function isValidChairItemType(fullType)
    if not fullType or fullType == "" then return false end
    if string.find(fullType, "furniture_", 1, true) then return false end
    if string.find(fullType, "location_", 1, true) then return false end
    if string.find(fullType, "fixtures_", 1, true) then return false end
    if not string.find(fullType, ".", 1, true) then return false end
    return true
end

local function captureChairIdentity(chairItem)
    local fullType = "Base.Mov_GreenChair"
    local worldSprite = nil

    if chairItem then
        if chairItem.getFullType then
            local ft = chairItem:getFullType()
            if ft and isValidChairItemType(ft) then
                fullType = ft
            end
        end
        if chairItem.getWorldSprite then
            local ws = chairItem:getWorldSprite()
            if ws and ws ~= "" then
                worldSprite = ws
            end
        end
    end

    -- Generic Base.Moveable without a sprite is useless — force a real chair
    if fullType == "Base.Moveable" or fullType == "Moveable" then
        if not worldSprite then
            fullType = "Base.Mov_GreenChair"
        end
    end

    return fullType, worldSprite
end

local function createChairItem(fullType, worldSprite)
    fullType = fullType or "Base.Mov_GreenChair"
    if not isValidChairItemType(fullType) then
        fullType = "Base.Mov_GreenChair"
    end

    local item = nil

    -- Prefer factory / instanceItem so we get a real InventoryItem object
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        item = InventoryItemFactory.CreateItem(fullType)
    end
    if not item and instanceItem then
        item = instanceItem(fullType)
    end

    -- Last resort: known-good chair
    if not item and InventoryItemFactory and InventoryItemFactory.CreateItem then
        item = InventoryItemFactory.CreateItem("Base.Mov_GreenChair")
        fullType = "Base.Mov_GreenChair"
    end
    if not item and instanceItem then
        item = instanceItem("Base.Mov_GreenChair")
        fullType = "Base.Mov_GreenChair"
    end

    if item and worldSprite and item.setWorldSprite then
        pcall(function() item:setWorldSprite(worldSprite) end)
    end

    return item
end

local function giveChairToPlayer(player, fullType, worldSprite)
    if not player then return false end
    local inv = player:getInventory()
    if not inv then return false end

    local item = createChairItem(fullType, worldSprite)

    if item then
        inv:AddItem(item)
        -- MP / host sync when available
        if sendAddItemToContainer then
            pcall(function() sendAddItemToContainer(inv, item) end)
        end
        return inv:contains(item)
    end

    -- String overload as absolute fallback
    local fallbackType = "Base.Mov_GreenChair"
    if fullType and isValidChairItemType(fullType) and CHAIR_TYPES[fullType] then
        fallbackType = fullType
    end
    local added = inv:AddItem(fallbackType)
    return added ~= nil
end


local function isChairBarricaded(door)
    if not door then return false end

    local data = getModData(door)
    if data and data[MODDATA_KEY] == true then return true end

    -- Recovery path: if the native barricade survived but mod-data was
    -- lost/reloaded, identify it by its own marker.
    if getNativeChairBarricade(door) then return true end

    return false
end

-- ------------------------------------------------------------
-- Placement
-- ------------------------------------------------------------

function BarricadeTheDoor.onBarricade(worldobjects, playerNum, door, chairItem)
    local player = getSpecificPlayer(playerNum)
    if not player or not door or not chairItem or not isDoor(door) then return end
    if isChairBarricaded(door) then return end

    local inventory = player:getInventory()
    if not inventory or not inventory:contains(chairItem) then return end
    if door.IsOpen and door:IsOpen() then return end

    local chairSquare, playerSide = getChairSquare(door, player)
    if not chairSquare then return end

    local direction = getChairDirection(door, playerSide)
    local sprite = CHAIR_SPRITES[direction] or CHAIR_SPRITES.south
    local chairType, chairWorldSprite = captureChairIdentity(chairItem)

    inventory:Remove(chairItem)

    local chairObject = IsoThumpable.new(getCell(), chairSquare, sprite, false, nil)
    if not chairObject then
        inventory:AddItem(chairType)
        return
    end

    chairObject:setName(BARRICADE_NAME)
    if chairObject.setCanPassThrough then chairObject:setCanPassThrough(false) end
    if chairObject.setBlockAllTheSquare then chairObject:setBlockAllTheSquare(true) end
    if chairObject.setThumpDmg then chairObject:setThumpDmg(0) end
    if chairObject.setIsThumpable then chairObject:setIsThumpable(false) end
    if chairObject.setIsDismantable then chairObject:setIsDismantable(false) end

    chairSquare:AddTileObject(chairObject)
    if chairObject.transmitCompleteItemToServer then
        chairObject:transmitCompleteItemToServer()
    end

    local native = ensureNativeChairBarricade(door, player)
    if not native then
        -- Do not consume the chair if the real door barricade could not
        -- be created. Use an actual InventoryItem for the rollback too.
        chairSquare:RemoveTileObject(chairObject)
        giveChairToPlayer(player, chairType, chairWorldSprite)
        print("[BarricadeTheDoor] ERROR: Could not create native IsoBarricade.")
        return
    end

    local data = getModData(door)
    if data then
        data.chairItemType = chairType
        data.chairWorldSprite = chairWorldSprite
        if data.chairOriginalHealth == nil and door.getHealth then
            data.chairOriginalHealth = door:getHealth()
        end
        if data.chairOriginalHealth and door.setHealth then
            door:setHealth(math.floor(data.chairOriginalHealth * getHealthMultiplier()))
        end
    end

    setBarricadeState(door, true, chairObject)

    if door.setLocked then door:setLocked(true) end
    if door.setIsLocked then door:setIsLocked(true) end
    if door.setLockedByKey then door:setLockedByKey(false) end

    if door.transmitModData then door:transmitModData() end
end

-- ------------------------------------------------------------
-- Removal
-- ------------------------------------------------------------

function BarricadeTheDoor.onRemoveBarricade(worldobjects, playerNum, door)
    local player = getSpecificPlayer(playerNum)
    if not player or not door or not isDoor(door) then return end

    -- Safety guard: if an old menu entry or another mod causes the
    -- callback to fire twice, only the first call is allowed to run.
    if not isChairBarricaded(door) then return end

    local data = getModData(door)
    local chairObject = findBarricadeChair(door)

    -- Snapshot identity BEFORE clearing barricade state / mod data
    local chairType = "Base.Mov_GreenChair"
    local chairWorldSprite = nil
    if data then
        if data.chairItemType and isValidChairItemType(data.chairItemType) then
            chairType = data.chairItemType
        end
        if data.chairWorldSprite and data.chairWorldSprite ~= "" then
            chairWorldSprite = data.chairWorldSprite
        end
    end

    removeNativeChairBarricade(door)

    if chairObject then
        local square = chairObject:getSquare()
        if square and square.RemoveTileObject then
            square:RemoveTileObject(chairObject)
        elseif chairObject.removeFromWorld then
            chairObject:removeFromWorld()
        end
    end

    if data and data.chairOriginalHealth ~= nil and door.setHealth then
        door:setHealth(data.chairOriginalHealth)
        data.chairOriginalHealth = nil
    end

    if door.setLocked then door:setLocked(false) end
    if door.setIsLocked then door:setIsLocked(false) end
    if door.setLockedByKey then door:setLockedByKey(false) end

    -- Return the chair FIRST so a failed state clear cannot eat it
    local ok = giveChairToPlayer(player, chairType, chairWorldSprite)
    if not ok then
        -- Absolute last resort
        giveChairToPlayer(player, "Base.Mov_GreenChair", nil)
        print("[BarricadeTheDoor] WARNING: fell back to Base.Mov_GreenChair for return.")
    end

    if data then
        data.chairItemType = nil
        data.chairWorldSprite = nil
    end

    setBarricadeState(door, false, nil)

    if door.transmitModData then door:transmitModData() end
end

-- ------------------------------------------------------------
-- World-object detection
-- ------------------------------------------------------------

local function findDoorInWorldObjects(worldobjects)
    if not worldobjects then return nil end

    local clickedSquare = nil
    local chair = nil

    for _, object in ipairs(worldobjects) do
        if object and object.getSquare and not clickedSquare then
            clickedSquare = object:getSquare()
        end
        if isDoor(object) then return object end
        if isBarricadeChair(object) then chair = object end
    end

    -- B42 worldobjects can be inconsistent about which object is first,
    -- so scan the clicked square and its four neighbours.
    if clickedSquare then
        local squares = {
            clickedSquare,
            getCell():getGridSquare(clickedSquare:getX() + 1, clickedSquare:getY(), clickedSquare:getZ()),
            getCell():getGridSquare(clickedSquare:getX() - 1, clickedSquare:getY(), clickedSquare:getZ()),
            getCell():getGridSquare(clickedSquare:getX(), clickedSquare:getY() + 1, clickedSquare:getZ()),
            getCell():getGridSquare(clickedSquare:getX(), clickedSquare:getY() - 1, clickedSquare:getZ()),
        }

        for _, square in ipairs(squares) do
            local objects = getObjectsOnSquare(square)
            if objects then
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    if isDoor(object) then
                        return object
                    end
                end
            end
        end
    end

    -- If the chair itself was clicked, find the associated door from
    -- the chair's stored coordinates / surrounding squares.
    if chair then
        local chairSquare = chair:getSquare()
        if chairSquare then
            local squares = {
                chairSquare,
                getCell():getGridSquare(chairSquare:getX() + 1, chairSquare:getY(), chairSquare:getZ()),
                getCell():getGridSquare(chairSquare:getX() - 1, chairSquare:getY(), chairSquare:getZ()),
                getCell():getGridSquare(chairSquare:getX(), chairSquare:getY() + 1, chairSquare:getZ()),
                getCell():getGridSquare(chairSquare:getX(), chairSquare:getY() - 1, chairSquare:getZ()),
            }
            for _, square in ipairs(squares) do
                local objects = getObjectsOnSquare(square)
                if objects then
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        if isDoor(object) and isChairBarricaded(object) then
                            return object
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- ------------------------------------------------------------
-- Context menu
-- ------------------------------------------------------------

function BarricadeTheDoor.onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    if not context or not worldobjects then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local door = findDoorInWorldObjects(worldobjects)
    if not door then return end

    if isChairBarricaded(door) then
        -- If an old save has the chair flag but lost its native
        -- barricade, recreate it immediately so the door remains secure.
        ensureNativeChairBarricade(door, player)

        -- This is the ONLY place where the removal option is added.
        -- The old version also added it from onFillChairContextMenu,
        -- which caused two identical options to appear and could execute
        -- the removal callback twice.
        context:addOption(
            "Remove Chair Barricade",
            worldobjects,
            BarricadeTheDoor.onRemoveBarricade,
            playerNum,
            door
        )
        return
    end

    local chairItem = getChairFromInventory(player)
    if not chairItem then return end

    context:addOption(
        "Lock with Chair",
        worldobjects,
        BarricadeTheDoor.onBarricade,
        playerNum,
        door,
        chairItem
    )
end

-- ------------------------------------------------------------
-- Prevent the decorative chair's normal pickup from leaving the
-- door locked. If the chair is clicked, expose our removal action.
-- ------------------------------------------------------------

function BarricadeTheDoor.onFillChairContextMenu(playerNum, context, worldobjects, test)
    -- Intentionally disabled. The door handler above adds the single
    -- removal option. Keeping a second handler here caused duplicate
    -- "Remove Chair Barricade" entries and could run the removal twice.
end

local function initialise()
    -- OnPreFill is deliberately used for B42. The Java world-menu
    -- builder can short-circuit OnFill for objects it claims itself.
    if Events and Events.OnPreFillWorldObjectContextMenu then
        Events.OnPreFillWorldObjectContextMenu.Add(BarricadeTheDoor.onFillWorldObjectContextMenu)
        Events.OnPreFillWorldObjectContextMenu.Add(BarricadeTheDoor.onFillChairContextMenu)
    end
    print("[BarricadeTheDoor] v" .. BarricadeTheDoor.VERSION .. " ready.")
end

Events.OnGameStart.Add(initialise)
