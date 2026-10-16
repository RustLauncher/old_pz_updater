require "Items/ProceduralDistributions"

local distributions = {
    { "ArmySurplusBackpacks", 0.25, 1.00, 0.35 },
    { "CampingStoreBackpacks", 1.50, 0.15, 0.10 },
    { "Hiker", 1.20, 0.05, 0.05 },
    { "HuntingLockers", 0.60, 0.10, 0.03 },
    { "SurvivalGear", 1.00, 0.15, 0.05 },
    { "CampingLockers", 0.40, 0.05, 0.03 },
    { "CrateCamping", 0.35, 0.05, 0.03 },
    { "LockerArmyBedroom", 0.10, 0.50, 0.15 },
    { "Locker", 0.08, 0.02, 0.01 },
    { "ClosetShelfGeneric", 0.08, 0.02, 0.01 },
    { "WardrobeRedneck", 0.12, 0.02, 0.01 },
}

local huntingBackpacks = {
    "Base.Hunting_Backpack_Green",
    "Base.Hunting_Backpack_Green_Patch",
    "Base.Hunting_Backpack_Brown",
    "Base.Hunting_Backpack_Brown_Patch",
}

local assaultBackpacks = {
    "Base.Assault_Backpack_Black",
    "Base.Assault_Backpack_Green",
    "Base.Assault_Backpack_Camo",
    "Base.Assault_Backpack_Pidoras",
}

local sleepingBagBackpacks = {
    "Base.Assault_Backpack_Mattress_Black",
    "Base.Assault_Backpack_Mattress_Green",
    "Base.Assault_Backpack_Mattress_Camo",
    "Base.Assault_Backpack_Mattress_Pidoras",
}

local function insertItem(distribution, fullType, weight)
    if weight and weight > 0 then
        table.insert(distribution.items, fullType)
        table.insert(distribution.items, weight)
    end
end

local function insertColourVariants(distribution, variants, totalWeight)
    if not totalWeight or totalWeight <= 0 then
        return
    end

    local variantWeight = totalWeight / #variants
    for _, fullType in ipairs(variants) do
        insertItem(distribution, fullType, variantWeight)
    end
end

local function preDistributionMerge()
    for _, entry in ipairs(distributions) do
        local distribution = ProceduralDistributions.list[entry[1]]
        if distribution and distribution.items then
            insertColourVariants(distribution, huntingBackpacks, entry[2])
            insertColourVariants(distribution, assaultBackpacks, entry[3])
            insertColourVariants(distribution, sleepingBagBackpacks, entry[4])
        else
            print("[RealisticBackpacksB42] Skipped missing distribution: " .. tostring(entry[1]))
        end
    end
end

Events.OnPreDistributionMerge.Add(preDistributionMerge)
