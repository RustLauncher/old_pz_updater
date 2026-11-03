-- TrailerCargo_Stackable: which models pile like on like, with the layer
-- cap of a pile (caps set by the player by eye). Keys are model names as
-- Trunk.modelOf returns them: "Base.X" or, for a weapon with only a
-- WeaponSprite, the bare sprite name. build/check_stackable.py checks them.
---@class (partial) TrailerCargo
---@field Stackable table<string, integer>
---@field StackablePatterns { suffix: string|nil, prefix: string|nil, cap: integer }[]
---@field StackPitch table<string, number>
---@field FloorFirst table<string, boolean>
TrailerCargo = rawget(_G, "TrailerCargo") or {}

TrailerCargo.Stackable = {
  -- timber
  ["Base.Log"] = 2,
  ["Base.TwoLogsStack"] = 2,
  ["Base.RailroadTie"] = 4,          -- LargePlank
  ["Plank"] = 6,                     -- weapon sprite, no world static model
  ["Firewood"] = 3,                  -- weapon sprite
  -- bar stock (the player's call, 2026-09-27: all three to 8)
  ["SteelBarStock"] = 8,                    -- SteelBar, weapon sprite
  ["SteelBarStockHalf"] = 8,                -- SteelBarHalf, weapon sprite
  ["Base.SteelBarStockQuarter"] = 8,        -- SteelBarQuarter
  -- sheet stock
  ["Base.MetalSheet"] = 20,          -- SheetMetal
  ["Base.MetalSheetSmall"] = 20,     -- SmallSheetMetal
  ["Base.CopperSheet"] = 20,
  ["Base.SmallCopperSheet"] = 20,
  ["Base.ScrapMetal"] = 6,
  -- bar stock
  -- bare names: WeaponSprite only, so the scan returns no module
  ["LeadPipe"] = 8,                  -- MetalPipe
  ["SteelRod"] = 8,
  ["IronBarStock"] = 8,              -- IronBar
  ["Base.PlasticPipe"] = 6,          -- Pipe
  ["Base.IronIngot"] = 8,
  ["Base.SteelIngot"] = 8,
  ["Base.PiercedSteelIngot"] = 8,
  ["Base.CopperIngot"] = 8,
  ["Base.BrassIngot"] = 8,
  ["Base.GoldBar"] = 8,
  ["Base.SilverBar"] = 8,
  ["Base.GoldBarSmall"] = 8,
  ["Base.SilverBarSmall"] = 8,
  ["Base.SteelBlock"] = 8,
  ["Base.IronBlock"] = 8,
  ["Base.StoneBlock"] = 6,
  -- masonry
  ["Base.ClayBrick"] = 3,
  ["Base.ClayBrickUnfired"] = 3,
  -- no concrete or gravel bags: they stand on end
  -- bags
  ["Base.SandBag"] = 5,
  ["Base.SandBag_Ground"] = 5,       -- EmptySandbag
  ["Base.Fertilizer_Ground"] = 5,
  -- coils
  ["Base.Wire"] = 4,
  ["Base.BarbedWire"] = 4,
  -- no WireStack or BarbedWireStack: a bundle lies alone
  ["Base.Twine"] = 4,
  ["Base.Rope_Looped"] = 4,
  ["Base.RopeStack"] = 4,
  -- boxes and crates
  -- ammo cartons; Military_Medium is the 5.56 one
  ["Base.Parcel_Ammo_Medium"] = 4,
  ["Base.Parcel_Military_Medium"] = 4,
  ["Base.Parcel_Food_Medium"] = 3,   -- a case of cans; three, the player's cap
  ["Base.Parcel_Food_Small"] = 3,    -- a small case (sardines, tuna)
  ["Base.Parcel_Food_ExtraSmall"] = 6,
  ["Base.Parcel3"] = 6,
  ["Base.ProduceBox_ExtraSmall"] = 6,
  ["Base.BoxOfJars"] = 4,
  ["Base.EggCarton"] = 5,
  ["Base.MedicalParcel_Red"] = 4,
  ["Base.MedicalParcel_Green"] = 4,
  ["Base.RifleAmmoBox"] = 6,
  ["Base.HandGunAmmoBox"] = 6,
  ["Base.BoxOf38Special"] = 6,
  ["Base.BoxOf44Magnum"] = 6,
  ["Base.BoxOf45Auto"] = 6,
  -- from Item Arrange's list, at its caps (build/compare_arrange.py)
  -- produce boxes, parcels and presents, one mesh family per size
  ["Base.ProduceBox_ExtraLarge"] = 3,
  ["Base.ProduceBox_Large"] = 3,
  ["Base.ProduceBox_Medium"] = 3,
  ["Base.ProduceBox_Small"] = 4,
  ["Base.Parcel1"] = 3,              -- Parcel_ExtraLarge
  ["Base.Parcel2"] = 3,              -- Parcel_Large
  ["Base.Parcel4"] = 3,              -- Parcel_Medium
  ["Base.Parcel5"] = 4,              -- Parcel_Small
  ["Base.Present1"] = 3,
  ["Base.Present2"] = 3,
  ["Base.Present3"] = 6,
  ["Base.Present4"] = 3,
  ["Base.Present5"] = 4,
  -- cartons and cases
  ["Base.Parcel_Hardware_Large"] = 2, -- NailsCarton
  ["Base.Parcel_Liquor_Large"] = 2,  -- boxed wine
  ["Base.Garbagebag_box"] = 3,
  ["Base.CigaretteCarton"] = 5,
  ["Base.CigarBox"] = 6,
  ["Base.CigarettePack_Closed"] = 8,
  ["Base.BoxOfFishingHooks"] = 8,
  ["Base.BoxOfShotGunShells"] = 3,
  -- no AmmoBox_Ground: shared by the Ammunition Box and a grenade box
  -- cases: a shared model shares the cap (every Protective, Bulky or rifle case)
  ["Base.ProtectiveCase_Ground"] = 3,
  ["Base.ProtectiveCaseBulky_Ground"] = 2,
  ["Base.RifleCase_Ground"] = 3,
  -- every Cloth Gun Case, rifle and shotgun, camo too
  ["Base.RifleCaseCloth_Ground"] = 4,
  -- damnlib's (KI5) crates, open or shut
  ["Base.USMILCrate1WI"] = 3,        -- USMIL.Crate0, Crate0Open
  ["Base.USMILCrate1milWI"] = 3,     -- USMIL.Crate0military, Crate0militaryOpen
  ["Base.BeerCanSixpack"] = 3,
  ["Base.CarBattery"] = 2,           -- all three batteries
  -- timber
  ["Base.FourLogsStack"] = 2,
  ["Base.ThreeLogsStack"] = 2,
  -- no firewood bundle: it needs a pyramid, the packer piles straight up
  -- bags; the plaster bag lies flat
  ["Base.BagOfPlasterPowder"] = 5,
  ["Base.Rice"] = 4,
  ["Base.Sugar"] = 2,
  ["Base.SugarBrown_Ground"] = 2,
  ["Base.CocoaPowder_Ground"] = 2,
  ["Base.MilkPowder_Sack"] = 3,
  -- 6, not Item Arrange's 12: its layer height squashes the bag
  ["Base.DriedBlackBeans_Ground"] = 6,
  ["Base.DriedChickpeas_Ground"] = 6,
  ["Base.DriedKidneyBeans_Ground"] = 6,
  ["Base.DriedLentils_Ground"] = 6,
  ["Base.DriedSplitPeas_Ground"] = 6,
  ["Base.DriedWhiteBeans_Ground"] = 6,
  -- tins, jars, cartons of drink
  ["Base.CanClosed"] = 3,
  ["Base.CanClosedBolognese"] = 3,
  ["Base.CanClosedCarrots"] = 3,
  ["Base.CanClosedChilli"] = 3,
  ["Base.CanClosedCorn"] = 3,
  ["Base.CanClosedCornerBeef"] = 3,
  ["Base.CanClosedDogFood"] = 3,
  ["Base.CanClosedFruitBeverage_Ground"] = 3,
  ["Base.CanClosedFruitCocktail_Ground"] = 3,
  ["Base.CanClosedMilk"] = 3,
  ["Base.CanClosedMushroom"] = 3,
  ["Base.CanClosedPeaches_Ground"] = 3,
  ["Base.CanClosedPeas"] = 3,
  ["Base.CanClosedPineapple_Ground"] = 3,
  ["Base.CanClosedPotatoes"] = 3,
  ["Base.CanClosedSoup"] = 3,
  ["Base.CanClosedTomatoes"] = 3,
  ["Base.CannedSardines_Ground"] = 3,
  ["Base.TinnedTuna_Ground"] = 3,
  ["Base.BeerCan_Ground"] = 3,
  ["Base.PopCanDiet"] = 3,
  ["Base.PopCanFizz"] = 3,
  ["Base.PopCanGeneric"] = 3,
  ["Base.PopCanRed"] = 3,
  ["Base.JarGlass_Ground"] = 3,
  ["Base.JamFruit_Ground"] = 3,
  ["Base.JamMarmalade_Ground"] = 3,
  ["Base.JarFoodBellPeppers_Ground"] = 3,
  ["Base.JarFoodBroccoli_Ground"] = 3,
  ["Base.JarFoodCabbage_Ground"] = 3,
  ["Base.JarFoodCarrots_Ground"] = 3,
  ["Base.JarFoodEggplants_Ground"] = 3,
  ["Base.JarFoodLeeks_Ground"] = 3,
  ["Base.JarFoodPotatoes_Ground"] = 3,
  ["Base.JarFoodRadish_Ground"] = 3,
  ["Base.JarFoodTomatoes_Ground"] = 3,
  ["Base.JuiceBox_Apple"] = 3,
  ["Base.JuiceBox_FruitPunch"] = 3,
  ["Base.JuiceBox_Grape"] = 3,
  ["Base.JuiceBox_Orange"] = 3,
  ["Base.ScoutCookies"] = 2,
  ["Base.SlugRepellent"] = 2,
  ["Base.HairGel_Ground"] = 3,
  -- nested, see TrailerCargo.StackPitch
  ["Base.Bucket_Ground"] = 2,
  ["Base.BucketForged"] = 2,
  ["Base.CookingPotGround"] = 2,
  -- misc
  ["Base.Wheel"] = 3,                -- every vanilla tyre; three high, the player's cap
  ["Base.Tarp"] = 4,
  ["Base.ElectronicsScrap"] = 4,
  ["Base.MoneyBundle"] = 8,
}

-- Families too large to list one by one.
TrailerCargo.StackablePatterns = {
  { suffix = "SeedBag_Ground", cap = 20 },   -- 52 of them
  { prefix = "Base.PaintTin", cap = 4 },     -- one per colour
}

-- Layer pitch where the next one nests or rests below the model's top
-- (from Item Arrange's dz): buckets and pots sit inside, paint tins rest
-- on the rim under the handle. The top layer draws its full height.
TrailerCargo.StackPitch = {
  ["Base.Bucket_Ground"] = 0.05,
  ["Base.BucketForged"] = 0.05,
  ["Base.CookingPotGround"] = 0.10,
  -- rests on the lid, handle inside; set by hand in game
  ["Base.ProtectiveCaseBulky_Ground"] = 0.1216,
}
for _, colour in ipairs({ "Black", "Blue", "Brown", "Cyan", "Green", "Grey", "LightBlue", "LightBrown",
  "Orange", "Pink", "Purple", "Red", "Turquoise", "White", "Yellow", "Empty" }) do
  TrailerCargo.StackPitch["Base.PaintTin" .. colour .. "_Ground"] = 0.07
end

-- Models that cover the floor before they pile, all lying across the bed
-- with no jitter: rows of logs over the whole bed (the player's rule).
TrailerCargo.FloorFirst = {
  ["Base.Log"] = true,
  ["Base.TwoLogsStack"] = true,
  ["Base.ThreeLogsStack"] = true,
  ["Base.FourLogsStack"] = true,
}

---@param m string|nil  a model script name as modelOf returns it
---@return integer|nil  the layer cap, or nil when the model never stacks
function TrailerCargo.stackCap(m)
  if not m then return nil end
  local cap = TrailerCargo.Stackable[m]
  if cap then return cap end
  local pats = TrailerCargo.StackablePatterns
  for i = 1, #pats do
    local pat = pats[i]
    if pat.suffix and string.sub(m, -#pat.suffix) == pat.suffix then return pat.cap end
    if pat.prefix and string.sub(m, 1, #pat.prefix) == pat.prefix then return pat.cap end
  end
  return nil
end
