-- Expanded Storage
-- Build 42 container capacity overrides.

local ExpandedStorage = {}

-- Add future container sprites and capacities to this table.
local CAPACITY_BY_SPRITE = {
    -- Level 2 / Wooden Crate
    ["carpentry_01_16"] = 80,
    ["carpentry_01_17"] = 80,
    ["carpentry_01_18"] = 80,

    -- Level 1 / Shoddy Wooden Crate
    ["carpentry_01_19"] = 60,
    ["carpentry_01_20"] = 60,
    ["carpentry_01_21"] = 60,

    -- Military storage crates: two styles, both orientations and all stack heights
    ["location_military_generic_01_0"] = 100,
    ["location_military_generic_01_1"] = 100,
    ["location_military_generic_01_2"] = 100,
    ["location_military_generic_01_3"] = 100,
    ["location_military_generic_01_4"] = 100,
    ["location_military_generic_01_5"] = 100,
    ["location_military_generic_01_8"] = 100,
    ["location_military_generic_01_9"] = 100,
    ["location_military_generic_01_10"] = 100,
    ["location_military_generic_01_11"] = 100,
    ["location_military_generic_01_12"] = 100,
    ["location_military_generic_01_13"] = 100,

    -- Military locker: all four facings
    ["location_military_generic_01_22"] = 100,
    ["location_military_generic_01_23"] = 100,
    ["location_military_generic_01_30"] = 100,
    ["location_military_generic_01_31"] = 100,

    -- Green wall locker: all four facings
    ["furniture_storage_02_8"] = 60,
    ["furniture_storage_02_9"] = 60,
    ["furniture_storage_02_10"] = 60,
    ["furniture_storage_02_11"] = 60,

    -- Small chest: all four facings
    ["furniture_storage_02_28"] = 20,
    ["furniture_storage_02_29"] = 20,
    ["furniture_storage_02_30"] = 20,
    ["furniture_storage_02_31"] = 20,

    -- Large metal shelves: both tiles in both orientations
    ["furniture_shelving_01_24"] = 100,
    ["furniture_shelving_01_25"] = 100,
    ["furniture_shelving_01_26"] = 100,
    ["furniture_shelving_01_27"] = 100,

    -- Greene's small crate: base and stacked replacement
    ["location_shop_greenes_01_35"] = 50,
    ["location_shop_greenes_01_36"] = 50,

    -- Crude tall locker: all related facings/variants
    ["crafted_05_16"] = 80,
    ["crafted_05_17"] = 80,
    ["crafted_05_18"] = 80,
    ["crafted_05_19"] = 80,

    -- Metal locker: all four facings
    ["furniture_storage_02_0"] = 100,
    ["furniture_storage_02_1"] = 100,
    ["furniture_storage_02_2"] = 100,
    ["furniture_storage_02_3"] = 100,

    -- Crude wall locker: all four facings
    ["crafted_05_20"] = 50,
    ["crafted_05_21"] = 50,
    ["crafted_05_22"] = 50,
    ["crafted_05_23"] = 50,

    -- Oakwood shelves: all four facings
    ["furniture_shelving_01_40"] = 60,
    ["furniture_shelving_01_41"] = 60,
    ["furniture_shelving_01_42"] = 60,
    ["furniture_shelving_01_43"] = 60,

    -- White fancy shelves: all four facings
    ["furniture_shelving_01_44"] = 60,
    ["furniture_shelving_01_45"] = 60,
    ["furniture_shelving_01_46"] = 60,
    ["furniture_shelving_01_47"] = 60,

    -- Big wall shelves: regular facings
    ["furniture_shelving_01_9"] = 60,
    ["furniture_shelving_01_10"] = 60,
    ["furniture_shelving_01_11"] = 60,
    ["furniture_shelving_01_12"] = 60,

    -- Big wall corner shelves: corner facings only
    ["furniture_shelving_01_8"] = 100,
    ["furniture_shelving_01_13"] = 100,
    ["furniture_shelving_01_14"] = 100,
    ["furniture_shelving_01_15"] = 100,

    -- Crafted wooden shelves: all four facings
    ["carpentry_02_64"] = 40,
    ["carpentry_02_65"] = 40,
    ["carpentry_02_66"] = 40,
    ["carpentry_02_67"] = 40,

    -- Tall branch shelves: all four facings
    ["crafted_04_92"] = 30,
    ["crafted_04_93"] = 30,
    ["crafted_04_94"] = 30,
    ["crafted_04_95"] = 30,
}

local function applySpriteCapacities()
    local spriteManager = IsoSpriteManager.instance
    if not spriteManager then
        return
    end

    for spriteName, capacity in pairs(CAPACITY_BY_SPRITE) do
        local sprite = spriteManager:getSprite(spriteName)
        if sprite then
            local properties = sprite:getProperties()
            if properties then
                properties:set("ContainerCapacity", tostring(capacity))
            end
        end
    end
end

local function applyObjectCapacity(object)
    if not object then
        return
    end

    local sprite = object:getSprite()
    if not sprite then
        return
    end

    local capacity = CAPACITY_BY_SPRITE[sprite:getName()]
    if not capacity then
        return
    end

    local container = object:getContainer()
    if container and container:getCapacity() ~= capacity then
        container:setCapacity(capacity)
    end
end

local function applySquareCapacities(square)
    if not square then
        return
    end

    local objects = square:getObjects()
    if not objects then
        return
    end

    for index = 0, objects:size() - 1 do
        applyObjectCapacity(objects:get(index))
    end
end

local function initialize()
    applySpriteCapacities()
end

Events.OnGameStart.Add(initialize)
Events.OnServerStarted.Add(initialize)
Events.OnObjectAdded.Add(applyObjectCapacity)
Events.LoadGridsquare.Add(applySquareCapacities)
