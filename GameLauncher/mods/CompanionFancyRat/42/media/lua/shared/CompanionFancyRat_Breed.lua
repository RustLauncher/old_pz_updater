local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 5) then return end

local API6 = (CD.API_VERSION or 0) >= 6
if API6 then
    CD.registerSpecies({
        key = "fr",
        nounKey = "IGUI_PD_SpeciesNoun_fr",
        youngKey = "IGUI_PD_Young_fr",
        labelKey = "IGUI_PD_SpeciesDisplay_fr",
    })
else
    CD.log("CompanionFancyRat: this base has no per-breed species yet; the fancy rat still won't " ..
           "breed with a dog or cat (canBreed stays false), it just isn't tagged as its own species " ..
           "until you update Companion Dogs to 0.7.1+.")
end

CD.FR_HOUSE_CHANCE = 3.0
CD.FR_FARM_CHANCE = 2.5
CD.FR_GRUBBY_CHANCE = 2.5

local function frSpawnMultiplier()
    local sv = SandboxVars and SandboxVars.CompanionFancyRat
    local m = sv and sv.FancyRatSpawnMultiplier
    if type(m) ~= "number" then return 1.0 end
    if m < 0 then return 0 end
    return m
end

local FR_GRUBBY_ROOM_KEYS = {
    "warehouse", "storage", "storeroom", "sewer", "kitchen", "diner", "restaurant",
    "dumpster", "trailer", "basement", "cellar", "junkyard", "garbage",
}
local function isFrGrubby(def)
    if not def then return false end
    local rooms = def:getRooms()
    if not rooms then return false end
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local nm = rd and rd:getName()
        if nm then
            nm = string.lower(nm)
            for _, k in ipairs(FR_GRUBBY_ROOM_KEYS) do
                if string.find(nm, k, 1, true) then return true end
            end
        end
    end
    return false
end
CD.registerBuildingClass("frgrubby", function(def)
    local ok, result = pcall(isFrGrubby, def)
    return ok and result or false
end, { skipUrbanGate = true })

CD.registerVoices({
    CDFRSqueak = "bark",
    CDFRChatter = "bark",
    CDFRSqueakAmbient = "ambient",
    CDFRPet = "fx",
}, nil, {
    CDFRSqueak = 22, CDFRSqueakAmbient = 22, CDFRChatter = 14, CDFRPet = 8,
})

local PROFILE = {
    typePrefix = "fr",
    species = "fr",
    descKey = "IGUI_PD_BreedDesc_fr",
    litter = { 3, 5 },
    puppySize = 0.5,
    xpMult = { scent = 2.0, combat = 1, obedience = 0.8, hunt = 1.0, herding = 1.0 },
    combatPower = 0.05,
    lethalityCurve = { min = 0.10, max = 0.20 },
    canKill = false,
    canKnockdown = false,
	combatStressMult = 0.75,
    panicThreshold = 0.90,
    skills = { combat = false, herding = false, hunt = false },
    canBreed = API6,
    sentinelMult = 1.6,
    barkNoiseMult = 0.3,
    loyaltyDecayMult = 1.0,
    bagMult = 0.5,
    idleAnimMs = 3800,
    geneRange = {
        strength       = { 0.00, 0.05 },
        aggressiveness = { 0.00, 0.05 },
        resistance     = { 0.00, 0.20 },
        stress         = { 0.65, 0.95 },
    },
}

PROFILE.diet = {
    replace = true,

    bad = {
        Coffee = true,
        Tea = true,
    },
    badParts = {
        licorice = true,
        poppyseed = true,
    },

    protein = {
        Meat = true, Beef = true, Poultry = true, Game = true, Sausage = true, Bacon = true,
        Fish = true, Seafood = true, Roe = true, Egg = true, Insect = true, Venison = true,
        DogFood = true, CatFood = true,
    },
    proteinParts = {
        meat = true, steak = true, chicken = true, fillet = true, jerky = true, bacon = true,
        ham = true, fish = true, sausage = true, egg = true, venison = true, mussel = true,
        burger = true, corndog = true,
    },
    nonProtein = {
        Bean = true, Berry = true, Bread = true, Candy = true, Cheese = true, Chocolate = true,
        Cocoa = true, Dressing = true, Fruits = true, Greens = true, Herb = true, HotPepper = true,
        Juice = true, Milk = true, Mushroom = true, NoExplicit = true, Nut = true, Oil = true,
        Pasta = true, Rice = true, Seed = true, Stock = true, Sugar = true, Thickener = true,
        Vegetable = true, Vegetables = true,
    },

    trough = {
        Vegetables = true, Fruits = true, DogFood = true, CatFood = true, Bread = true,
        Nut = true, Seed = true,
    },
    troughItems = {
        ["Base.DogfoodOpen"] = true, ["Base.DogFoodBag"] = true,
    },
}

local COATS = {
    { key = "frwhite",  engine = "fr_white",  tex = "FRWhite",  house = "|frw",  farm = "|ffw",  grubby = "|fgw"  },
    { key = "frgrey",   engine = "fr_grey",   tex = "FRGrey",   house = "|frg",  farm = "|ffg",  grubby = "|fgg"  },
    { key = "frhooded", engine = "fr_hooded", tex = "FRHooded", house = "|frh",  farm = "|ffh",  grubby = "|fgh"  },
    { key = "frnaked",  engine = "fr_naked",  tex = "FRNaked",  house = "|frn",  farm = "|ffn",  grubby = "|fgn"  },
    { key = "frbrown",  engine = "fr_brown",  tex = "FRBrown",  house = "|frbr", farm = "|ffbr", grubby = "|fgbr" },
    { key = "frblue",   engine = "fr_blue",   tex = "FRBlue",   house = "|frbl", farm = "|ffbl", grubby = "|fgbl" },
}

for _, c in ipairs(COATS) do
    local def = {}
    for k, v in pairs(PROFILE) do def[k] = v end
    def.key = c.key
    def.engineBreed = c.engine
    def.nameKey = "IGUI_PD_Breed_" .. c.key
	def.bandSkin = { base = c.tex, front = c.tex .. "_BandFront", back = c.tex .. "_BandBack",
                   cutFront = c.tex .. "_CutFront", cutBack = c.tex .. "_CutBack" }
    def.voices = { bark = "CDFRSqueak", growl = "CDFRChatter", idle = "CDFRSqueak",
                   wildbark = "CDFRSqueakAmbient", pet = "CDFRPet" }
    def.spawns = {
        { id = c.key .. "house", class = "house", suffix = c.house, breed = c.key, indoor = 90,
          chance = function() return CD.FR_HOUSE_CHANCE * frSpawnMultiplier() end },
        { id = c.key .. "farm", class = "farm", suffix = c.farm, breed = c.key, indoor = 60,
          chance = function() return CD.FR_FARM_CHANCE * frSpawnMultiplier() end },
        { id = c.key .. "grubby", class = "frgrubby", suffix = c.grubby, breed = c.key, indoor = 95,
          chance = function() return CD.FR_GRUBBY_CHANCE * frSpawnMultiplier() end },
    }
    CD.registerBreed(def)
end
