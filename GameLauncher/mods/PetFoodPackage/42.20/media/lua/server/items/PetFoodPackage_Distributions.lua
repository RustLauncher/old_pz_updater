local function abundanceMultiplier()
    local abundance = 5
    if SandboxVars and SandboxVars.PetFoodPackage then
        abundance = tonumber(SandboxVars.PetFoodPackage.Abundance) or 5
    end

    return ({
        [1] = 0.00,
        [2] = 0.50,
        [3] = 0.75,
        [4] = 0.90,
        [5] = 1.00,
        [6] = 1.50,
        [7] = 2.00,
        
    })[abundance] or 1.00
end

local function containsText(value, text)
    return value and string.find(string.lower(value), text, 1, true) ~= nil
end

local function isMarketContainer(roomType, containerType)
    local room = string.lower(roomType or "")
    return containsText(room, "grocery")
        or containsText(room, "gigamart")
        or containsText(room, "market")
end

local function isVehicleTrunk(containerType)
    local container = string.lower(containerType or "")
    return containsText(container, "trunk") or containsText(container, "truckbed")
end

local function isResidentialKitchen(roomType, containerType)
    local room = string.lower(roomType or "")
    local container = string.lower(containerType or "")
    return containsText(room, "kitchen")
        and (containsText(container, "counter")
            or containsText(container, "cabinet")
            or containsText(container, "fridge")
            or containsText(container, "shelf"))
end

local function addIndependentPetFoodBox(roomType, containerType, itemContainer)
    local multiplier = abundanceMultiplier()
    if multiplier <= 0 then
        return
    end

    local chance
    if isVehicleTrunk(containerType) then
        chance = 0.125
    elseif isMarketContainer(roomType, containerType) then
        chance = 0.25
    elseif isResidentialKitchen(roomType, containerType) then
        chance = 0.075
    else
        return
    end

    -- Independent roll after normal loot, matching the original mod logic.
    if ZombRandFloat(0.0, 1.0) > chance * multiplier then
        return
    end

    if not PetFoodPackageItems or #PetFoodPackageItems == 0 then
        return
    end

    local itemType = PetFoodPackageItems[ZombRand(#PetFoodPackageItems) + 1]
    itemContainer:AddItem(itemType)
end

Events.OnFillContainer.Add(addIndependentPetFoodBox)
