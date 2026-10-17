require "Items/ProceduralDistributions"

local WEIGHT = 0.2

local ITEMS = {
    "PantsCollection.Pants_OliveCargoWorn",
    "PantsCollection.Pants_BlackBlueLegging",
    "PantsCollection.Pants_FlowerTealLegging",
    "PantsCollection.Pants_FlowerTurquoiseLegging",
    "PantsCollection.Pants_NavySportLegging",
    "PantsCollection.Pants_FlowerPinkLegging",
    "PantsCollection.Pants_WhiteKnitLegging",
    "PantsCollection.Pants_NavyStrokeLegging",
    "PantsCollection.Pants_BlueMarbleLegging",
    "PantsCollection.Pants_LightBlueJeans",
    "PantsCollection.Pants_BlackRippedJeans",
    "PantsCollection.Pants_GreyStripeLegging",
    "PantsCollection.Pants_FlowerBrightLegging",
    "PantsCollection.Pants_FlowerWhiteLegging",
    "PantsCollection.Pants_MissouriCargoKhaki",
    "PantsCollection.Pants_MissouriCargoNavy",
    "PantsCollection.Pants_MissouriCargoOlive",
    "PantsCollection.Pants_MissouriCargoCharcoal",
    "PantsCollection.Pants_MissouriCargoStoneGrey",
    "PantsCollection.Pants_NeonBlackLegging",
    "PantsCollection.Pants_IceBlueLegging",
    "PantsCollection.Pants_NeonTealLegging",
    "PantsCollection.Pants_FlowerWhitePinkLegging",
    "PantsCollection.Pants_BabyBlueStripeLegging",
    "PantsCollection.Pants_GreyPinkStripe2Legging",
    "PantsCollection.Pants_SalmonStripeLegging",
    "PantsCollection.Pants_SoftPinkStripeLegging",
    "PantsCollection.Pants_SafariPants",
    "PantsCollection.Pants_RippedSkinnyJeans",
    "PantsCollection.Pants_WornCargoStoneGrey",
    "PantsCollection.Pants_WornCargoCharcoal",
    "PantsCollection.Pants_WornCargoNavy",
    "PantsCollection.Pants_WornCargoTan",
}

local CONTAINERS = {
    "BedroomDresser", "BedroomDresserChild", "BedroomDresserClassy",
    "BedroomDresserRedneck", "ClosetShelfGeneric", "ClothingPoor",
    "ClothingRack", "ClothingStorageLegwear", "CrateClothesRandom",
    "DresserGeneric", "WardrobeChild", "WardrobeClassy",
    "WardrobeGeneric", "WardrobeRedneck",
}

local added, missing = 0, {}
for _,loc in ipairs(CONTAINERS) do
    local dist = ProceduralDistributions.list[loc]
    if dist and dist.items then
        for _,item in ipairs(ITEMS) do
            table.insert(dist.items, item)
            table.insert(dist.items, WEIGHT)
            added = added + 1
        end
    else
        table.insert(missing, loc)
    end
end
print("[PantsCollection] spawns: " .. added .. " entries added" ..
      (#missing > 0 and ("; unknown containers: " .. table.concat(missing, ", ")) or ""))
