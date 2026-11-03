ArcadiaRefillablePropane = ArcadiaRefillablePropane or {}

local Depot = ArcadiaRefillablePropane

Depot.NET_MODULE = "ArcadiaRefillablePropane"
Depot.DATA_VERSION = 7
Depot.SANDBOX_NAMESPACE = "ArcadiaRefillablePropaneTanks"
Depot.DEFAULT_CAPACITY = 2000.0
Depot.SMALL_PROPANE_TANK_CAPACITY = 500.0
-- Kept as a compatibility alias for integrations that read the original
-- constant. Runtime behavior uses getCapacity() so sandbox changes apply.
Depot.CAPACITY = Depot.DEFAULT_CAPACITY
Depot.STANDARD_TANK_UNITS = 100.0
Depot.DEFAULT_BLOWTORCH_PROPANE_AMOUNT = 70.0
Depot.DEFAULT_PROPANE_TANK_USES = 5000.0
Depot.DEFAULT_BLOWTORCH_USES = 10.0
Depot.DEFAULT_TW_LARGE_PROPANE_USES = 40.0
Depot.DEFAULT_TW_HUGE_PROPANE_USES = 400.0
Depot.TW_HUGE_USES_PER_STANDARD_TANK = 16.0
Depot.LANTERN_BOTTLE_UNITS = 5.0
Depot.MAX_DISTANCE_SQUARED = 6.25
Depot.MAX_VEHICLE_DEPOT_DISTANCE_SQUARED = 25.0
Depot.MIN_TRANSFER = 0.0001

Depot.FILIBUSTER_WORKSHOP_ID = "3683878228"
Depot.FILIBUSTER_MOD_ID = "B42FRUsedCarsAnimAlpha"
Depot.FILIBUSTER_PROPANE_VEHICLE_SCRIPT = "Base.fr_fo_f700_90_propane"
Depot.ARCADIA_PROPANE_MOD_ID = "RVs_HeavyDuty_Trailers"
Depot.ARCADIA_PROPANE_VEHICLE_SCRIPT = "Base.ArcadiaF700Propane"
Depot.FILIBUSTER_PROPANE_PART_ID = "FRPropaneTank"
Depot.FILIBUSTER_PROPANE_TANK_ONE_ID = "FRPropaneTank"
Depot.FILIBUSTER_PROPANE_TANK_TWO_ID = "FRPropaneTank2"
Depot.FILIBUSTER_PROPANE_PART_IDS = {
    [Depot.FILIBUSTER_PROPANE_TANK_ONE_ID] = true,
    [Depot.FILIBUSTER_PROPANE_TANK_TWO_ID] = true,
}
Depot.FILIBUSTER_PROPANE_CONTENT_TYPE = "Propane Storage"
Depot.FILIBUSTER_TANK_TWO_AMOUNT_KEY =
    "ArcadiaRefillablePropaneTankTwoAmount"
Depot.FILIBUSTER_TANK_TWO_INITIALIZED_KEY =
    "ArcadiaRefillablePropaneTankTwoInitialized"
Depot.ARCADIA_TANK_TWO_AMOUNT_KEY = "RVsHeavyDutyPropaneTankTwoAmount"
Depot.ARCADIA_TANK_TWO_INITIALIZED_KEY =
    "RVsHeavyDutyPropaneTankTwoInitialized"
-- Filibuster's FR_TakePropaneAction spends 80 vehicle-container units to fill
-- one Base.PropaneTank. The depot economy intentionally values that same tank
-- at 100 units, so every cross-system transfer must convert between scales.
Depot.FILIBUSTER_VEHICLE_UNITS_PER_STANDARD_TANK = 80.0

Depot.MODDATA_MARKER = "ArcadiaRefillablePropane"
Depot.MODDATA_VERSION = "ArcadiaRefillablePropaneVersion"
Depot.MODDATA_AMOUNT = "ArcadiaRefillablePropaneAmount"
Depot.MODDATA_REVISION = "ArcadiaRefillablePropaneRevision"

Depot.SPRITES = {
    industry_02_64 = true,
    industry_02_65 = true,
    industry_02_66 = true,
    industry_02_67 = true,
    industry_02_68 = true,
    industry_02_69 = true,
    industry_02_70 = true,
    industry_02_71 = true,
    industry_02_280 = true,
    industry_02_281 = true,
    industry_02_282 = true,
    industry_02_283 = true,
    industry_03_105 = true,
    industry_03_107 = true,
    industry_03_109 = true,
    industry_03_110 = true,
    industry_03_112 = true,
    industry_03_113 = true,
    industry_03_114 = true,
    industry_03_115 = true,
    location_shop_fossoil_01_80 = true,
    location_shop_fossoil_01_81 = true,
    location_shop_fossoil_01_82 = true,
    location_shop_fossoil_01_83 = true,
    location_shop_fossoil_01_84 = true,
    location_shop_fossoil_01_85 = true,
    location_shop_fossoil_01_86 = true,
    location_shop_fossoil_01_87 = true,
    location_shop_fossoil_01_88 = true,
    location_shop_fossoil_01_89 = true,
    location_shop_fossoil_01_90 = true,
    location_shop_fossoil_01_91 = true,
    location_shop_fossoil_01_92 = true,
    location_shop_fossoil_01_93 = true,
    location_shop_fossoil_01_94 = true,
    location_shop_fossoil_01_95 = true,
    location_shop_fossoil_01_96 = true,
    location_shop_fossoil_01_97 = true,
    location_shop_fossoil_01_98 = true,
    location_shop_fossoil_01_99 = true,
    location_shop_fossoil_01_100 = true,
    location_shop_fossoil_01_101 = true,
    location_shop_fossoil_01_102 = true,
    location_shop_fossoil_01_103 = true,
    location_shop_fossoil_01_104 = true,
    location_shop_fossoil_01_105 = true,
    location_shop_fossoil_01_106 = true,
    location_shop_fossoil_01_107 = true,
    location_shop_fossoil_01_108 = true,
    location_shop_fossoil_01_109 = true,
    location_shop_fossoil_01_110 = true,
    location_shop_fossoil_01_111 = true,
}

Depot.PERSISTENT_ANCHOR_SPRITES = {
    industry_02_64 = true,
    industry_02_66 = true,
    industry_02_281 = true,
    industry_03_105 = true,
    industry_03_107 = true,
    industry_03_109 = true,
    industry_03_110 = true,
    industry_03_112 = true,
    industry_03_113 = true,
    industry_03_114 = true,
    industry_03_115 = true,
    location_shop_fossoil_01_81 = true,
    location_shop_fossoil_01_89 = true,
    location_shop_fossoil_01_101 = true,
    location_shop_fossoil_01_109 = true,
}

Depot.SMALL_PROPANE_TANK_SPRITES = {
    industry_03_105 = true,
    industry_03_107 = true,
    industry_03_109 = true,
    industry_03_110 = true,
    industry_03_112 = true,
    industry_03_113 = true,
    industry_03_114 = true,
    industry_03_115 = true,
}

Depot.SHARED_TANK_ANCHORS = {
    industry_02_65 = "industry_02_64",
    industry_02_67 = "industry_02_66",
    industry_02_68 = "industry_02_64",
    industry_02_69 = "industry_02_64",
    industry_02_70 = "industry_02_66",
    industry_02_71 = "industry_02_66",
    industry_02_280 = "industry_02_281",
    industry_02_281 = "industry_02_281",
    industry_02_282 = "industry_02_281",
    industry_02_283 = "industry_02_281",
    location_shop_fossoil_01_80 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_81 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_82 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_83 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_84 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_85 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_86 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_87 = "location_shop_fossoil_01_81",
    location_shop_fossoil_01_88 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_89 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_90 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_91 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_92 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_93 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_94 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_95 = "location_shop_fossoil_01_89",
    location_shop_fossoil_01_96 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_97 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_98 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_99 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_100 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_101 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_102 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_103 = "location_shop_fossoil_01_101",
    location_shop_fossoil_01_104 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_105 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_106 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_107 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_108 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_109 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_110 = "location_shop_fossoil_01_109",
    location_shop_fossoil_01_111 = "location_shop_fossoil_01_109",
}

-- Gas2Go uses the same four eight-sprite bulk-tank layouts as Fossoil. Keep
-- the exact range constrained so unrelated signs, pumps, doors, and decor in
-- the Gas2Go tilesheet never become propane depots.
for index = 64, 95 do
    local spriteName = "location_shop_gas2go_01_" .. index
    Depot.SPRITES[spriteName] = true
    local groupStart = math.floor((index - 64) / 8) * 8 + 64
    local anchorOffset = groupStart < 80 and 1 or 5
    Depot.SHARED_TANK_ANCHORS[spriteName] =
        "location_shop_gas2go_01_" .. (groupStart + anchorOffset)
end
for _, index in ipairs({ 65, 73, 85, 93 }) do
    Depot.PERSISTENT_ANCHOR_SPRITES["location_shop_gas2go_01_" .. index] = true
end

Depot.SHARED_TANK_ANCHOR_RADIUS = 3

-- The original tank rotations keep one functional forward sprite each. The
-- longer B42 and Fossoil tanks may be clicked on any body section. Each
-- assembled four-section tank resolves to one nearby orientation-specific
-- anchor so decorative multi-tile artwork cannot multiply its capacity.

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function getScriptUses(fullType, fallback)
    if getScriptManager then
        local manager = getScriptManager()
        local scriptItem = manager and manager:FindItem(fullType) or nil
        local useDelta = scriptItem and tonumber(scriptItem:getUseDelta()) or nil
        if useDelta and useDelta > 0 then return 1.0 / useDelta end
    end
    return fallback
end

local function getSandboxOptions()
    return SandboxVars and SandboxVars[Depot.SANDBOX_NAMESPACE] or nil
end

local function sandboxOptionEnabled(name)
    local options = getSandboxOptions()
    return not options or options[name] ~= false
end

function Depot.isFossoilEnabled()
    return sandboxOptionEnabled("EnableFossoilDepots")
end

function Depot.isGas2GoEnabled()
    return sandboxOptionEnabled("EnableGas2GoDepots")
end

function Depot.areSmallPropaneTankDepotsEnabled()
    return sandboxOptionEnabled("EnableSmallPropaneTankDepots")
end

function Depot.areLanternBottlesEnabled()
    return sandboxOptionEnabled("EnableLanternBottles")
end

function Depot.areWorkshopContainersEnabled()
    return sandboxOptionEnabled("EnableWorkshopContainers")
end

function Depot.areCompatiblePropaneItemsEnabled()
    return sandboxOptionEnabled("EnableCompatiblePropaneItems")
end

function Depot.isFilibusterPropaneTruckEnabled()
    return sandboxOptionEnabled("EnableFilibusterPropaneTruck")
end

local function activatedModsContains(modId)
    if not getActivatedMods then return false end
    local mods = getActivatedMods()
    if not mods then return false end
    if mods.contains and mods:contains(modId) then return true end
    if mods.size and mods.get then
        for index = 0, mods:size() - 1 do
            if mods:get(index) == modId then return true end
        end
    end
    return false
end

function Depot.isFilibusterModActive()
    return activatedModsContains(Depot.FILIBUSTER_MOD_ID)
end

function Depot.isArcadiaPropaneVehicleModActive()
    return activatedModsContains(Depot.ARCADIA_PROPANE_MOD_ID)
end

local function isSpriteCategoryEnabled(spriteName)
    if not spriteName then return false end
    if string.sub(spriteName, 1, 25) == "location_shop_fossoil_01_" then
        return Depot.isFossoilEnabled()
    end
    if string.sub(spriteName, 1, 24) == "location_shop_gas2go_01_" then
        return Depot.isGas2GoEnabled()
    end
    if string.sub(spriteName, 1, 12) == "industry_03_" then
        return Depot.areSmallPropaneTankDepotsEnabled()
    end
    return true
end

function Depot.getCapacity(object)
    local spriteName = Depot.getSpriteName(object)
    if spriteName and Depot.SMALL_PROPANE_TANK_SPRITES[spriteName] then
        return Depot.SMALL_PROPANE_TANK_CAPACITY
    end
    local options = getSandboxOptions()
    return clamp(
        options and options.Capacity or Depot.DEFAULT_CAPACITY,
        100.0,
        100000.0
    )
end

function Depot.isInfinite()
    local options = getSandboxOptions()
    return options ~= nil and options.InfinitePropane == true
end

function Depot.getInitialFillRange()
    local options = getSandboxOptions()
    local minimum = clamp(options and options.InitialFillMin or 1.0, 0, 1)
    local maximum = clamp(options and options.InitialFillMax or 1.0, 0, 1)
    if minimum > maximum then minimum, maximum = maximum, minimum end
    return minimum, maximum
end

function Depot.getInitialEmptyChance()
    local options = getSandboxOptions()
    return clamp(options and options.InitialEmptyChance or 0, 0, 100)
end

-- The server supplies both rolls when first initializing a depot. Keeping the
-- calculation shared and pure makes the sandbox behavior testable without
-- allowing clients to create divergent persistent state.
function Depot.calculateInitialAmount(fillRoll, emptyRoll, object)
    local capacity = Depot.getCapacity(object)
    if Depot.isInfinite() then return capacity end

    local emptyChance = Depot.getInitialEmptyChance()
    if emptyChance >= 100 or
        clamp(emptyRoll, 0, 1) < (emptyChance / 100.0) then
        return 0
    end

    local minimum, maximum = Depot.getInitialFillRange()
    local fraction = minimum + ((maximum - minimum) * clamp(fillRoll, 0, 1))
    return capacity * fraction
end

function Depot.getSpriteName(object)
    local sprite = object and object:getSprite() or nil
    return sprite and sprite:getName() or nil
end

function Depot.isDepotObject(object)
    local spriteName = Depot.getSpriteName(object)
    return spriteName ~= nil and Depot.SPRITES[spriteName] == true and
        isSpriteCategoryEnabled(spriteName)
end

function Depot.isPersistentAnchorObject(object)
    local spriteName = Depot.getSpriteName(object)
    return spriteName ~= nil and
        Depot.PERSISTENT_ANCHOR_SPRITES[spriteName] == true and
        isSpriteCategoryEnabled(spriteName)
end

local function getSquareObjects(square)
    local objects = square and square:getObjects() or nil
    if not objects then return function() return nil end end
    local index = 0
    return function()
        if index >= objects:size() then return nil end
        local object = objects:get(index)
        index = index + 1
        return object
    end
end

-- Build 42's context-menu worldObjects list may contain only a floor or other
-- wrapper object from the clicked square. Scan the square's complete object
-- list as vanilla menus such as ISBBQMenu do, so large scenery tanks remain
-- discoverable even when their IsoObject is not passed directly.
function Depot.findDepotInWorldObjects(worldObjects)
    local visitedSquares = {}
    for _, worldObject in ipairs(worldObjects or {}) do
        if Depot.isDepotObject(worldObject) then return worldObject end
        local square = worldObject and worldObject:getSquare() or nil
        if square and not visitedSquares[square] then
            visitedSquares[square] = true
            for candidate in getSquareObjects(square) do
                if Depot.isDepotObject(candidate) then return candidate end
            end
        end
    end
    return nil
end

-- Multi-tile tank body sections are separate IsoObjects. Prefer the nearby
-- anchor for that exact orientation. A lone body section remains usable for
-- custom maps that place only one section.
function Depot.resolveDepotObject(object)
    if not Depot.isDepotObject(object) then return nil end
    local spriteName = Depot.getSpriteName(object)
    local anchorSprite = Depot.SHARED_TANK_ANCHORS[spriteName]
    if not anchorSprite or spriteName == anchorSprite then
        return object
    end

    local square = object:getSquare()
    if not square then return object end
    local cell = square.getCell and square:getCell() or nil
    if not cell and getCell then cell = getCell() end
    if not cell then return object end

    local originX, originY, z = square:getX(), square:getY(), square:getZ()
    local best, bestDistance, bestX, bestY = nil, math.huge, math.huge, math.huge
    local radius = Depot.SHARED_TANK_ANCHOR_RADIUS
    for x = originX - radius, originX + radius do
        for y = originY - radius, originY + radius do
            local distance = math.abs(x - originX) + math.abs(y - originY)
            if distance <= radius then
                local candidateSquare = cell:getGridSquare(x, y, z)
                for candidate in getSquareObjects(candidateSquare) do
                    if Depot.getSpriteName(candidate) == anchorSprite and
                        (distance < bestDistance or
                            (distance == bestDistance and
                                (x < bestX or (x == bestX and y < bestY)))) then
                        best = candidate
                        bestDistance, bestX, bestY = distance, x, y
                    end
                end
            end
        end
    end
    return best or object
end

function Depot.getData(object)
    return object and object:getModData() or nil
end

function Depot.getStoredAmount(object)
    local data = Depot.getData(object)
    if not data or data[Depot.MODDATA_AMOUNT] == nil then
        -- LoadGridsquare initializes the authoritative random amount before a
        -- player normally sees it. This fallback is only a temporary display.
        return Depot.calculateInitialAmount(0.5, 1.0, object)
    end
    if Depot.isInfinite() then return Depot.getCapacity(object) end
    return clamp(data[Depot.MODDATA_AMOUNT], 0, Depot.getCapacity(object))
end

function Depot.getDepotMissingUnits(object)
    return math.max(0, Depot.getCapacity(object) - Depot.getStoredAmount(object))
end

function Depot.getRevision(object)
    local data = Depot.getData(object)
    return data and math.max(0, tonumber(data[Depot.MODDATA_REVISION]) or 0) or 0
end

function Depot.isPlayerAdjacent(player, object)
    if not player or not object then return false end
    local square = object:getSquare()
    if not square or math.floor(player:getZ()) ~= square:getZ() then return false end
    local deltaX = player:getX() - (square:getX() + 0.5)
    local deltaY = player:getY() - (square:getY() + 0.5)
    return ((deltaX * deltaX) + (deltaY * deltaY)) <= Depot.MAX_DISTANCE_SQUARED
end

local function getVehicleScriptName(vehicle)
    if not vehicle then return nil end
    if vehicle.getScriptName then
        local scriptName = vehicle:getScriptName()
        if scriptName and scriptName ~= "" then return scriptName end
    end
    local script = vehicle.getScript and vehicle:getScript() or nil
    if not script then return nil end
    if script.getFullName then return script:getFullName() end
    if script.getName then return script:getName() end
    return nil
end

-- Optional compatibility for the original Filibuster B42 propane truck and
-- the independently packaged Arcadia F700. Exact script and part identities
-- prevent unrelated vehicle containers from becoming propane reservoirs.
function Depot.getPropaneVehicleProfile(vehicle)
    if not Depot.isFilibusterPropaneTruckEnabled() then return nil end
    local scriptName = getVehicleScriptName(vehicle)
    if scriptName == Depot.FILIBUSTER_PROPANE_VEHICLE_SCRIPT and
        Depot.isFilibusterModActive() then
        return {
            kind = "filibuster",
            tankTwoAmountKey = Depot.FILIBUSTER_TANK_TWO_AMOUNT_KEY,
            tankTwoInitializedKey =
                Depot.FILIBUSTER_TANK_TWO_INITIALIZED_KEY,
            labelKey = "UI_RPT_FilibusterTruck",
            usesFilibusterSync = true,
        }
    end
    if scriptName == Depot.ARCADIA_PROPANE_VEHICLE_SCRIPT and
        Depot.isArcadiaPropaneVehicleModActive() then
        return {
            kind = "arcadia",
            tankTwoAmountKey = Depot.ARCADIA_TANK_TWO_AMOUNT_KEY,
            tankTwoInitializedKey = Depot.ARCADIA_TANK_TWO_INITIALIZED_KEY,
            labelKey = "UI_RPT_ArcadiaTruck",
            usesFilibusterSync = false,
        }
    end
    return nil
end

function Depot.isFilibusterPropaneVehicle(vehicle)
    return Depot.getPropaneVehicleProfile(vehicle) ~= nil
end

-- Generic alias for integrations written after Arcadia F700 support.
function Depot.isSupportedPropaneVehicle(vehicle)
    return Depot.isFilibusterPropaneVehicle(vehicle)
end

function Depot.getPropaneVehicleLabel(vehicle)
    local profile = Depot.getPropaneVehicleProfile(vehicle)
    return getText(profile and profile.labelKey or "UI_RPT_PropaneTruck")
end

function Depot.shouldOwnVehicleContextMenu(vehicle)
    local profile = Depot.getPropaneVehicleProfile(vehicle)
    -- The Arcadia F700 package already owns its direct truck menu. The depot
    -- integration handles world-tank transfers without creating duplicates.
    return profile ~= nil and profile.kind ~= "arcadia"
end

function Depot.isFilibusterPropanePart(part)
    if not part or not part.isContainer or not part:isContainer() then
        return false
    end
    if not part.getId or not Depot.FILIBUSTER_PROPANE_PART_IDS[part:getId()] then
        return false
    end
    local contentType = part.getContainerContentType and
        part:getContainerContentType() or nil
    return contentType == Depot.FILIBUSTER_PROPANE_CONTENT_TYPE
end

function Depot.isVirtualFilibusterTankTwo(part)
    return type(part) == "table" and
        part.ArcadiaVirtualFilibusterTankTwo == true
end

function Depot.getVirtualFilibusterTankBackingPart(part)
    if not Depot.isVirtualFilibusterTankTwo(part) then return nil end
    return part.ArcadiaBackingPart
end

local function makeVirtualFilibusterTankTwo(vehicle, backingPart)
    if not vehicle or not backingPart or not backingPart.getModData then
        return nil
    end
    local part = {
        ArcadiaVirtualFilibusterTankTwo = true,
        ArcadiaBackingPart = backingPart,
    }
    function part:isContainer() return true end
    function part:getId() return Depot.FILIBUSTER_PROPANE_TANK_TWO_ID end
    function part:getContainerContentType()
        return Depot.FILIBUSTER_PROPANE_CONTENT_TYPE
    end
    function part:getContainerCapacity()
        return math.max(
            0,
            tonumber(backingPart:getContainerCapacity()) or 0
        )
    end
    function part:getContainerContentAmount()
        local data = backingPart:getModData()
        local profile = Depot.getPropaneVehicleProfile(vehicle)
        local amountKey = profile and profile.tankTwoAmountKey or
            Depot.FILIBUSTER_TANK_TWO_AMOUNT_KEY
        return clamp(
            data[amountKey],
            0,
            self:getContainerCapacity()
        )
    end
    function part:setContainerContentAmount(amount)
        local data = backingPart:getModData()
        local profile = Depot.getPropaneVehicleProfile(vehicle)
        local amountKey = profile and profile.tankTwoAmountKey or
            Depot.FILIBUSTER_TANK_TWO_AMOUNT_KEY
        local initializedKey = profile and profile.tankTwoInitializedKey or
            Depot.FILIBUSTER_TANK_TWO_INITIALIZED_KEY
        data[amountKey] = clamp(
            amount,
            0,
            self:getContainerCapacity()
        )
        data[initializedKey] = true
    end
    function part:getArea()
        return backingPart.getArea and backingPart:getArea() or "FuelStorage"
    end
    function part:getVehicle() return vehicle end
    function part:getModData() return backingPart:getModData() end
    return part
end

function Depot.getFilibusterPropanePart(vehicle, requestedPartId)
    if not Depot.isFilibusterPropaneVehicle(vehicle) then return nil end
    local partId = requestedPartId or Depot.FILIBUSTER_PROPANE_TANK_ONE_ID
    if not Depot.FILIBUSTER_PROPANE_PART_IDS[partId] or
        not vehicle.getPartById then
        return nil
    end
    local part = vehicle:getPartById(partId)
    if not part and partId == Depot.FILIBUSTER_PROPANE_TANK_TWO_ID then
        local backingPart = vehicle:getPartById(
            Depot.FILIBUSTER_PROPANE_TANK_ONE_ID
        )
        if Depot.isFilibusterPropanePart(backingPart) then
            part = makeVirtualFilibusterTankTwo(vehicle, backingPart)
        end
    end
    if not Depot.isFilibusterPropanePart(part) then return nil end
    return part
end

function Depot.getFilibusterPropaneParts(vehicle)
    if not Depot.isFilibusterPropaneVehicle(vehicle) then return {} end
    local parts = {}
    for _, partId in ipairs({
        Depot.FILIBUSTER_PROPANE_TANK_ONE_ID,
        Depot.FILIBUSTER_PROPANE_TANK_TWO_ID,
    }) do
        local part = Depot.getFilibusterPropanePart(vehicle, partId)
        if part then parts[#parts + 1] = part end
    end
    return parts
end

function Depot.getFilibusterTankLabel(part)
    if part and part.getId and
        part:getId() == Depot.FILIBUSTER_PROPANE_TANK_TWO_ID then
        return getText("UI_RPT_FilibusterTankTwo")
    end
    return getText("UI_RPT_FilibusterTankOne")
end

function Depot.getVehiclePropaneCapacity(part)
    if not Depot.isFilibusterPropanePart(part) then return 0 end
    return math.max(0, tonumber(part:getContainerCapacity()) or 0)
end

function Depot.getVehiclePropaneAmount(part)
    local capacity = Depot.getVehiclePropaneCapacity(part)
    if capacity <= 0 then return 0 end
    return clamp(part:getContainerContentAmount(), 0, capacity)
end

function Depot.getVehiclePropaneMissingUnits(part)
    return math.max(
        0,
        Depot.getVehiclePropaneCapacity(part) -
            Depot.getVehiclePropaneAmount(part)
    )
end

function Depot.vehiclePropaneToDepotUnits(vehicleUnits)
    local units = math.max(0, tonumber(vehicleUnits) or 0)
    return units * (
        Depot.STANDARD_TANK_UNITS /
        Depot.FILIBUSTER_VEHICLE_UNITS_PER_STANDARD_TANK
    )
end

function Depot.depotPropaneToVehicleUnits(depotUnits)
    local units = math.max(0, tonumber(depotUnits) or 0)
    return units * (
        Depot.FILIBUSTER_VEHICLE_UNITS_PER_STANDARD_TANK /
        Depot.STANDARD_TANK_UNITS
    )
end

function Depot.isPlayerAdjacentToVehiclePart(player, part)
    if not player or not Depot.isFilibusterPropanePart(part) then return false end
    local vehicle = part.getVehicle and part:getVehicle() or nil
    if not vehicle then return false end
    if math.floor(player:getZ()) ~= math.floor(vehicle:getZ()) then return false end

    local area = part.getArea and part:getArea() or nil
    if area and vehicle.getAreaDist then
        return vehicle:getAreaDist(area, player) <= 2.5
    end

    local deltaX = player:getX() - vehicle:getX()
    local deltaY = player:getY() - vehicle:getY()
    return ((deltaX * deltaX) + (deltaY * deltaY)) <= 9.0
end

function Depot.isVehicleNearDepot(vehicle, object)
    local square = object and object:getSquare() or nil
    if not vehicle or not square then return false end
    if math.floor(vehicle:getZ()) ~= square:getZ() then return false end
    local deltaX = vehicle:getX() - (square:getX() + 0.5)
    local deltaY = vehicle:getY() - (square:getY() + 0.5)
    return ((deltaX * deltaX) + (deltaY * deltaY)) <=
        Depot.MAX_VEHICLE_DEPOT_DISTANCE_SQUARED
end

Depot.REGISTERED_PROPANE_TARGETS = Depot.REGISTERED_PROPANE_TARGETS or {}

-- Compatibility API for other mods. fullCost is expressed in this mod's
-- depot units (a standard Base.PropaneTank is 100). Registration does not add
-- a hard dependency and remains governed by EnableCompatiblePropaneItems.
function Depot.registerPropaneTarget(fullType, fullCost, kind, canSupply)
    if type(fullType) ~= "string" or fullType == "" then return false end
    fullCost = tonumber(fullCost)
    if not fullCost or fullCost <= 0 then return false end
    Depot.REGISTERED_PROPANE_TARGETS[fullType] = {
        fullCost = fullCost,
        kind = kind or "compatible_propane",
        canSupply = canSupply ~= false,
    }
    return true
end

local function getItemIdentityText(item)
    local fullType = item and item.getFullType and item:getFullType() or ""
    local displayName = item and item.getDisplayName and
        item:getDisplayName() or ""
    return string.lower(tostring(fullType) .. " " .. tostring(displayName))
end

function Depot.getTargetKind(item)
    if not item or not instanceof(item, "DrainableComboItem") then return nil end
    local fullType = item:getFullType()
    if fullType == "Base.PropaneTank" then return "tank" end
    if fullType == "Base.BlowTorch" then return "torch" end
    if Depot.areLanternBottlesEnabled() then
        if fullType == "Base.Propane_Refill" then return "lantern_bottle" end
        if fullType == "Base.Lantern_Propane" then return "propane_lantern" end
    end
    if Depot.areWorkshopContainersEnabled() then
        if fullType == "TW.LargePropaneTank" then return "tw_large_tank" end
        if fullType == "TW.HugePropaneTank" then return "tw_huge_tank" end
    end
    if Depot.areCompatiblePropaneItemsEnabled() then
        local registered = Depot.REGISTERED_PROPANE_TARGETS[fullType]
        if registered then return registered.kind end
        -- A conservative fallback catches drainable mod items explicitly
        -- named for propane. Authors can register differently named tools.
        if string.find(getItemIdentityText(item), "propane", 1, true) then
            return "compatible_propane"
        end
    end
    return nil
end

function Depot.getTargetFraction(item)
    if not Depot.getTargetKind(item) then return 0 end
    return clamp(item:getCurrentUsesFloat(), 0, 1)
end

-- The depot's visible unit scale intentionally treats one full standard
-- propane tank as 100 units. A B42 blowtorch uses the same fuel ratio as the
-- vanilla RefillBlowTorch recipe (10 torch uses x 70 propane uses), which is
-- 14 depot units against a 5,000-use propane tank.
function Depot.getTargetFullCost(item)
    local kind = Depot.getTargetKind(item)
    if kind == "tank" then return Depot.STANDARD_TANK_UNITS end
    if kind == "lantern_bottle" or kind == "propane_lantern" then
        return Depot.LANTERN_BOTTLE_UNITS
    end
    if kind == "tw_large_tank" then
        return Depot.STANDARD_TANK_UNITS * getScriptUses(
            "TW.LargePropaneTank",
            Depot.DEFAULT_TW_LARGE_PROPANE_USES
        ) / Depot.TW_HUGE_USES_PER_STANDARD_TANK
    end
    if kind == "tw_huge_tank" then
        return Depot.STANDARD_TANK_UNITS * getScriptUses(
            "TW.HugePropaneTank",
            Depot.DEFAULT_TW_HUGE_PROPANE_USES
        ) / Depot.TW_HUGE_USES_PER_STANDARD_TANK
    end
    local fullType = item and item:getFullType() or nil
    local registered = fullType and Depot.REGISTERED_PROPANE_TARGETS[fullType] or nil
    if registered then return registered.fullCost end
    if kind == "compatible_propane" then
        local standardUses = getScriptUses(
            "Base.PropaneTank",
            Depot.DEFAULT_PROPANE_TANK_USES
        )
        local targetUses = getScriptUses(fullType, standardUses)
        return Depot.STANDARD_TANK_UNITS * (targetUses / standardUses)
    end
    if kind ~= "torch" then return nil end

    local propaneUses = getScriptUses(
        "Base.PropaneTank",
        Depot.DEFAULT_PROPANE_TANK_USES
    )
    local torchUses = getScriptUses(
        "Base.BlowTorch",
        Depot.DEFAULT_BLOWTORCH_USES
    )
    local refillRatio = Depot.DEFAULT_BLOWTORCH_PROPANE_AMOUNT
    if ZomboidGlobals and ZomboidGlobals.refillBlowtorchPropaneAmount then
        refillRatio = tonumber(ZomboidGlobals.refillBlowtorchPropaneAmount) or refillRatio
    end
    if propaneUses <= 0 then return 14.0 end
    return Depot.STANDARD_TANK_UNITS * ((torchUses * refillRatio) / propaneUses)
end

function Depot.getMissingUnits(item)
    local fullCost = Depot.getTargetFullCost(item)
    if not fullCost then return 0 end
    return math.max(0, (1.0 - Depot.getTargetFraction(item)) * fullCost)
end

function Depot.getItemStoredUnits(item)
    local fullCost = Depot.getTargetFullCost(item)
    if not fullCost then return 0 end
    return Depot.getTargetFraction(item) * fullCost
end

-- Refillable tools are valid destinations, but torches are deliberately not
-- fuel sources. This also catches compatible Workshop torches registered
-- under a custom kind or module name containing "torch".
function Depot.isPropaneSourceItem(item)
    local kind = Depot.getTargetKind(item)
    if not kind then return false end
    local fullType = item and item.getFullType and item:getFullType() or ""
    local registered = Depot.REGISTERED_PROPANE_TARGETS[fullType]
    if registered and registered.canSupply == false then return false end
    if kind == "torch" or
        string.find(getItemIdentityText(item), "torch", 1, true) then
        return false
    end
    return Depot.getItemStoredUnits(item) > Depot.MIN_TRANSFER
end

function Depot.makeTransferPlan(item, storedAmount)
    local fullCost = Depot.getTargetFullCost(item)
    if not fullCost then return nil end

    local currentFraction = Depot.getTargetFraction(item)
    local missingUnits = math.max(0, (1.0 - currentFraction) * fullCost)
    local availableUnits = clamp(storedAmount, 0, Depot.getCapacity())
    local transferredUnits = math.min(missingUnits, availableUnits)
    local targetFraction = currentFraction
    if fullCost > 0 then
        targetFraction = clamp(currentFraction + (transferredUnits / fullCost), 0, 1)
    end
    if targetFraction > 0.999999 then targetFraction = 1.0 end

    return {
        currentFraction = currentFraction,
        targetFraction = targetFraction,
        missingUnits = missingUnits,
        transferredUnits = transferredUnits,
        remainingUnits = math.max(0, availableUnits - transferredUnits),
        fullCost = fullCost,
    }
end

-- Plan the inverse of makeTransferPlan: remove propane from a supported
-- carried item and add it to a finite world depot. Keeping this calculation
-- shared lets the client preview the exact server-authoritative result.
function Depot.makeDepositPlan(item, storedAmount, capacity)
    if not Depot.isPropaneSourceItem(item) then return nil end
    local fullCost = Depot.getTargetFullCost(item)
    if not fullCost then return nil end

    capacity = math.max(0, tonumber(capacity) or 0)
    local currentStored = clamp(storedAmount, 0, capacity)
    local currentFraction = Depot.getTargetFraction(item)
    local availableUnits = currentFraction * fullCost
    local missingUnits = math.max(0, capacity - currentStored)
    local transferredUnits = math.min(availableUnits, missingUnits)
    local targetFraction = currentFraction
    if fullCost > 0 then
        targetFraction = clamp(
            (availableUnits - transferredUnits) / fullCost,
            0,
            1
        )
    end
    if targetFraction < 0.000001 then targetFraction = 0 end

    return {
        currentFraction = currentFraction,
        targetFraction = targetFraction,
        availableUnits = availableUnits,
        missingUnits = missingUnits,
        transferredUnits = transferredUnits,
        storedUnits = math.min(capacity, currentStored + transferredUnits),
        fullCost = fullCost,
    }
end

function Depot.formatAmount(value)
    value = math.max(0, tonumber(value) or 0)
    local roundedInteger = math.floor(value + 0.5)
    if math.abs(value - roundedInteger) <= 0.050001 then
        return tostring(roundedInteger)
    end
    return string.format("%.1f", value)
end

function Depot.formatPercent(item)
    return tostring(math.floor((Depot.getTargetFraction(item) * 100) + 0.5))
end

return Depot
