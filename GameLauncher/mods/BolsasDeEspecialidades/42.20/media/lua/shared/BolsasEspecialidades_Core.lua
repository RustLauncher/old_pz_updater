-- Shared recipe callback and loot configuration. Full item IDs only.
BolsasEspecialidades = BolsasEspecialidades or {}
local BE = BolsasEspecialidades
BE.stateKey = "BolsasEspecialidades_InitialContents_v1"
BE.contentChance = 80 -- percent per newly spawned world bag
BE.minTypes = 2
BE.maxTypes = 4
-- {fullType, relative selection weight, minimum quantity, maximum quantity, optional exclusive group}
BE.pools = {
    ["BolsasEspecialidades.Bag_Mecanica"] = {
        {"Base.Wrench", 15, 1, 1},
        {"Base.Screwdriver", 20, 1, 1},
        {"Base.LugWrench", 10, 1, 1},
        {"Base.TirePump", 8, 1, 1},
        {"Base.Jack", 3, 1, 1},
        {"Base.DuctTape", 12, 1, 1},
        {"Base.NutsBolts", 25, 2, 5},
        {"Base.Pliers", 12, 1, 1},
    },
    ["BolsasEspecialidades.Bag_Pesca"] = {
        {"Base.FishingHook", 25, 2, 5},
        {"Base.FishingLine", 20, 1, 1},
        {"Base.Bobber", 18, 1, 2},
        {"Base.JigLure", 15, 1, 2},
        {"Base.FishingRod", 4, 1, 1},
        {"Base.KnifeFillet", 8, 1, 1},
        {"Base.BookFishing1", 5, 1, 1},
    },
    ["BolsasEspecialidades.Bag_Caca"] = {
        {"Base.HuntingKnife", 10, 1, 1},
        {"Base.Rope", 18, 1, 1},
        {"Base.Twine", 20, 1, 1},
        {"Base.CompassDirectional", 6, 1, 1},
        {"Base.HuntingMag1", 5, 1, 1},
        {"Base.Hat_BonnieHat_CamoGreen", 8, 1, 1},
        {"Base.Lighter", 15, 1, 1},
    },
    ["BolsasEspecialidades.Bag_Firearms"] = {
        {"Base.9mmClip", 20, 1, 1},
        {"Base.HolsterSimple", 15, 1, 1},
        {"Base.GunLight", 8, 1, 1},
        {"Base.x2Scope", 4, 1, 1},
        {"Base.Bullets9mmBox", 10, 1, 1, "ammo"},
        {"Base.ShotgunShellsBox", 8, 1, 1, "ammo"},
        {"Base.308Box", 5, 1, 1, "ammo"},
        {"Base.Glasses_Shooting", 12, 1, 1},
    },
    ["BolsasEspecialidades.Bag_Carpintaria"] = {
        {"Base.Hammer", 15, 1, 1},
        {"Base.GardenSaw", 10, 1, 1},
        {"Base.Nails", 25, 5, 15},
        {"Base.Screws", 20, 5, 10},
        {"Base.Woodglue", 8, 1, 1},
        {"Base.MeasuringTape", 12, 1, 1},
        {"Base.CarpentryChisel", 8, 1, 1},
        {"Base.Screwdriver", 15, 1, 1},
    },
}

-- B42 craftRecipe callback: called for the actual output of each of our recipes.
-- Mark, but never delete anything: crafted bags begin empty naturally.
function BolsasEspecialidades.OnCrafted(craftRecipeData, character)
    local results = craftRecipeData:getAllCreatedItems()
    for i = 0, results:size() - 1 do
        local item = results:get(i)
        if BE.pools[item:getFullType()] and instanceof(item, "InventoryContainer") then
            item:getModData()[BE.stateKey] = "crafted"
            item:getInventory():setExplored(true)
        end
    end
end
