require "Items/ProceduralDistributions"

local ITEMS = {
    "RandomSneakers.Shoes_AirLow",
    "RandomSneakers.Shoes_BabyBlue",
    "RandomSneakers.Shoes_BlackBrown",
    "RandomSneakers.Shoes_BlackRed",
    "RandomSneakers.Shoes_BrownLaced",
    "RandomSneakers.Shoes_CourtMid",
    "RandomSneakers.Shoes_FlowerPink",
    "RandomSneakers.Shoes_RacerMid",
    "RandomSneakers.Shoes_RacerMidBlackBrown",
    "RandomSneakers.Shoes_RacerMidGrey",
    "RandomSneakers.Shoes_RacerMidGreenOrange",
    "RandomSneakers.Shoes_RacerMidRed",
    "RandomSneakers.Shoes_RedHigh",
    "RandomSneakers.Shoes_RetroMid",
    "RandomSneakers.Shoes_ScoobHigh",
    "RandomSneakers.Shoes_SplatterHigh",
    "RandomSneakers.Shoes_StrapHigh",
    "RandomSneakers.Shoes_WedgeBlackGrey",
    "RandomSneakers.Shoes_WedgeBlue",
    "RandomSneakers.Shoes_WedgeBrownLight",
    "RandomSneakers.Shoes_WedgeCremeBrown",
    "RandomSneakers.Shoes_WedgeJeans",
    "RandomSneakers.Shoes_WedgeOffWhite",
    "RandomSneakers.Shoes_WedgeRed",
    "RandomSneakers.Shoes_WedgeRedWhiteBlue",
    "RandomSneakers.Shoes_WedgeTanBrown",
    "RandomSneakers.Shoes_WedgeVelvetRed",
    "RandomSneakers.Shoes_WedgeWornBrown",
    "RandomSneakers.Shoes_WedgeZebra",
}

local LISTS = {
    { "BedroomDresser", 0.08 },
    { "BedroomDresserClassy", 0.11 },
    { "BedroomDresserRedneck", 0.08 },
    { "BandPracticeClothing", 0.4 },
    { "ClothingStorageFootwear", 1.44 },
    { "ClothingStoresShoes", 2.08 },
    { "PoliceOutfit", 0.4 },
    { "PoliceStateOutfit", 0.4 },
    { "RangerOutfit", 0.4 },
    { "SportStoreSneakers", 2.4 },
    { "BaseballLockers", 0.32 },
    { "BowlingAlleyLockers", 0.32 },
    { "CrateFootwearRandom", 0.64 },
    { "FactoryLockers", 0.32 },
    { "MechanicOutfit", 0.32 },
    { "NurseOutfit", 0.32 },
    { "PoliceLockers", 0.32 },
    { "PrisonGuardLockers", 0.32 },
    { "RangerLockers", 0.32 },
    { "PrisonIntakeLockers", 0.16 },
    { "BaseballStoreShelves", 0.08 },
    { "BurglarTools", 0.08 },
    { "ClosetInstruments", 0.08 },
    { "ClosetShelfGeneric", 0.08 },
    { "ClosetSportsEquipment", 0.08 },
    { "CultistClothing", 0.08 },
    { "FitnessTrainer", 0.08 },
    { "GymLockers", 0.08 },
    { "HospitalLockers", 0.08 },
    { "JockeyLockers", 0.08 },
    { "LaboratoryLockers", 0.08 },
    { "Locker", 0.08 },
    { "LockerClassy", 0.08 },
    { "MusicSchoolLocker", 0.08 },
    { "SchoolLockers", 0.08 },
    { "SchoolLockersBad", 0.08 },
    { "SeasonalWorkerLockers", 0.08 },
    { "WardrobeRedneck", 0.08 },
    { "BedroomDresserChild", 0.12 },
    { "UniversityWardrobe", 0.05 },
    { "WardrobeChild", 0.11 },
    { "WardrobeClassy", 0.11 },
    { "CrateRandomJunk", 0.032 },
    { "BackstageCounter", 0.02 },
    { "BackstageLockers", 0.02 },
    { "CrateClothesRandom", 0.02 },
    { "WardrobeGeneric", 0.06 },
}

local added, missing = 0, {}
for _,entry in ipairs(LISTS) do
    local dist = ProceduralDistributions.list[entry[1]]
    if dist and dist.items then
        for _,item in ipairs(ITEMS) do
            table.insert(dist.items, item)
            table.insert(dist.items, entry[2])
            added = added + 1
        end
    else
        table.insert(missing, entry[1])
    end
end
print("[RandomSneakers] loot: " .. added .. " entries added" ..
      (#missing > 0 and ("; unknown lists: " .. table.concat(missing, ", ")) or ""))
