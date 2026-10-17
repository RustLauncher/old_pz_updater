-- HalloweenEvent costume registry -- B42.21
-- Automatic event spawning uses only natural=true profiles. Debug/gallery keeps
-- every profile available so approximations can still be inspected manually.

HalloweenEvent = HalloweenEvent or {}
local HWE = HalloweenEvent

-- Vanilla Knife in Back definitions include these models. Nearly broken
-- condition keeps the visible impalement from becoming valuable weapon loot.
HWE.SantaImpaledWeapons = {"Base.SteakKnife", "Base.Screwdriver", "Base.MasonsTrowel"}
HWE.SantaImpaledCondition = 1

HWE.CostumeCategoryOrder = {
    "Characters",
    "Professions",
    "Fantasy",
    "Theme / Party",
    "Sports Costumes",
    "Masks"
}

HWE.Costumes = {
    { id="SpiffoMascot",    name="Spiffo Mascot",           category="Characters",    build="native", approx=false, natural=true,  outfit="Spiffo",                 femaleOnly=false },
    { id="SantaClaus",      name="Santa Claus (Red)",       category="Characters",    build="native", approx=false, natural=true,  outfit="Santa",                  femaleOnly=false },
    { id="SantaClausGreen", name="Santa Claus (Green)",     category="Characters",    build="hwe",    approx=false, natural=true,  outfit="HWE_SantaGreen",         femaleOnly=false, visualMode="replace", visualItems={"Base.JacketLong_SantaGreen","Base.Trousers_SantaGreen","Base.Hat_SantaHatGreen","Base.Shoes_BlackBoots"} },
    { id="JasonSlasher",    name="Hockey Slasher (Jason)",  category="Characters",    build="hwe",    approx=false, natural=true,  outfit="HWE_JasonSlasher",       femaleOnly=false, visualMode="replace", visualItems={"Base.Boilersuit","Base.Shoes_BlackBoots","Base.Hat_HockeyMask"} },
    { id="JayChicken",      name="Jay's Chicken Mascot",    category="Characters",    build="hwe",    approx=false, natural=true,  outfit="HWE_JayChicken",         femaleOnly=false, visualMode="replace", visualItems={"Base.Tshirt_BusinessSpiffo","Base.Trousers_Denim","Base.Shoes_TrainerTINT","Base.Apron_Jay","Base.Hat_Jay"} },

    { id="Doctor",          name="Doctor / Surgeon",        category="Professions",   build="native", approx=false, natural=true,  outfit="Doctor",                 femaleOnly=false },
    { id="Nurse",           name="Medical Nurse",           category="Professions",   build="native", approx=false, natural=true,  outfit="Nurse",                  femaleOnly=true  },
    { id="Firefighter",     name="Firefighter",             category="Professions",   build="native", approx=false, natural=true,  outfit="Fireman",                femaleOnly=false },
    { id="Police",          name="Police Officer",          category="Professions",   build="native", approx=false, natural=true,  outfit="Police",                 femaleOnly=false },

    { id="Cultist",         name="Occult Cultist",          category="Fantasy",       build="native", approx=false, natural=true,  outfit="Cultist",                femaleOnly=false },
    { id="Witch", detectByOutfit=false,           name="Wicked Witch",            category="Fantasy",       build="native", approx=false,  natural=true, outfit="Goth",                   femaleOnly=true, visualMode="replace", visualItems={"Base.TightsFishnets","Base.Garter","Base.Corset_Black","Base.Skirt_Mini","Base.Gloves_LongWomenGloves","Base.Shoes_Strapped","Base.Hat_Witch"} },
    { id="Wizard",          name="High Wizard",             category="Fantasy",       build="hwe",    approx=false, natural=true,  outfit="HWE_Wizard",              femaleOnly=false, visualMode="replace", visualItems={"Base.Trousers_Suit","Base.LongCoat_Bathrobe","Base.Shoes_BlackBoots","Base.Hat_Wizard"} },
    { id="Pirate",          name="Pirate Captain",          category="Fantasy",       build="hwe",    approx=false, natural=true,  outfit="HWE_Pirate",              femaleOnly=false, visualMode="replace", visualItems={"Base.Shirt_FormalWhite","Base.Vest_Waistcoat","Base.Trousers_Suit","Base.Shoes_BlackBoots","Base.Glasses_Eyepatch_Left","Base.Hat_Pirate"} },
    { id="BurlapMummy",     name="Burlap Mummy",            category="Fantasy",       build="hwe",    approx=false, natural=true,  outfit="HWE_BurlapMummy",        femaleOnly=false, visualMode="replace", visualItems={"Base.Briefs_Burlap","Base.Bandeau_Burlap","Base.Shoes_BurlapWrap","Base.Gloves_BurlapWrap","Base.Hat_ShemaghFull_Burlap"}, verifyAnyTypes={"Base.Briefs_Burlap","Base.Bandeau_Burlap","Base.Shoes_BurlapWrap","Base.Gloves_BurlapWrap","Base.Hat_ShemaghFull_Burlap"} },

    { id="MaskDevil",       name="Devil Mask",              category="Masks",         build="native", approx=false,  natural=true, outfit="Cultist",                femaleOnly=false, isMask=true, visualMode="replace", visualItems={"Base.Shirt_Priest","Base.Trousers_Suit","Base.Shoes_BlackBoots","Base.Hat_HalloweenMaskDevil"} },
    { id="MaskMonster",     name="Monster Mask",            category="Masks",         build="native", approx=false,  natural=true, outfit="Punk",                   femaleOnly=false, isMask=true, visualMode="replace", visualItems={"Base.Tshirt_Punk","Base.Trousers_Denim_Punk","Base.Shoes_BlackBoots","Base.Hat_HalloweenMaskMonster"} },
    { id="MaskPumpkin",     name="Pumpkin Mask",            category="Masks",         build="native", approx=false,  natural=true, outfit="Party",                  femaleOnly=false, isMask=true, visualMode="replace", visualItems={"Base.Shirt_FormalWhite","Base.Trousers_Suit","Base.Shoes_Black","Base.Hat_HalloweenMaskPumpkin"} },
    { id="MaskSkeleton",    name="Skeleton Mask",           category="Masks",         build="native", approx=false,  natural=true, outfit="Goth",                   femaleOnly=false, isMask=true, visualMode="replace", visualItems={"Base.Tshirt_Rock","Base.Trousers_LeatherBlack","Base.Shoes_BlackBoots","Base.Hat_HalloweenMaskSkeleton"} },
    { id="MaskVampire",     name="Vampire",                 category="Masks",         build="native", approx=false,  natural=true, outfit="Classy",                 femaleOnly=false, isMask=true, visualMode="replace", visualItems={"Base.Shirt_FormalWhite","Base.Vest_Waistcoat","Base.Trousers_Suit","Base.Shoes_Black","Base.Hat_HalloweenMaskVampire"} },

    { id="MaskWitch", name="Witch Mask", category="Masks", build="native", approx=false, natural=true, outfit="Goth", femaleOnly=false, isMask=true, visualMode="replace", visualItems={"Base.Tshirt_Rock","Base.Trousers_LeatherBlack","Base.Shoes_BlackBoots","Base.Hat_HalloweenMaskWitch"} },

    { id="WildWestClown",   name="Carnival Clown",          category="Theme / Party", build="native", approx=false, natural=true,  outfit="CostumeWildWestClown",   femaleOnly=false },
    { id="CowboyStripper",  name="Cowboy/Cowgirl Stripper",         category="Theme / Party", build="native", approx=false, natural=true, outfit="CowboyStripper",          femaleOnly=false, visualMode="replace", visualItems={"Base.Shorts_ShortDenim","Base.Shoes_CowboyBoots","Base.Hat_Cowboy"} },
    { id="TieDyeHippie", detectByOutfit=false,    name="Tie-Dye Hippie",          category="Theme / Party", build="native", approx=false,  natural=true, outfit="Tourist",                 femaleOnly=false, visualMode="replace", visualItems={"Base.Tshirt_TieDye","Base.Trousers_Denim","Base.Shoes_TrainerTINT","Base.Necklace_YingYang"} },
    { id="EDP_BunnyBlack",  name="Black Bunny Stripper",    category="Theme / Party", build="hwe",    approx=false, natural=true,  outfit="HWE_BlackBunnyStripper", femaleOnly=true,  verifyAnyTypes={"Base.BunnySuitBlack"}, visualMode="replace", visualItems={"Base.BunnySuitBlack","Base.TightsFishnets","Base.Garter","Base.BunnyTail","Base.Shoes_Strapped","Base.Hat_BunnyEarsBlack"} },
    { id="EDP_BunnyPink",   name="Pink Bunny Stripper",     category="Theme / Party", build="hwe",    approx=false, natural=true,  outfit="HWE_PinkBunnyStripper",  femaleOnly=true,  verifyAnyTypes={"Base.BunnySuitPink"}, visualMode="replace", visualItems={"Base.BunnySuitPink","Base.TightsFishnets","Base.Garter","Base.BunnyTail","Base.Shoes_Strapped","Base.Hat_BunnyEarsWhite"} },
    { id="EDP_GlamDancer",  name="Glam Showgirl",           category="Theme / Party", build="hwe",    approx=false, natural=true,  outfit="HWE_GlamDancer",         femaleOnly=true,  verifyAnyTypes={"Base.Corset_Black"}, visualMode="replace", visualItems={"Base.Corset_Black","Base.Skirt_Mini","Base.TightsFishnets","Base.Shoes_Fancy","Base.Glasses_Aviators","Base.Earring_Dangly_Ruby"} }
}

-- Item preferences only from the supplied EDP B42 reference. No EDP code or
-- dependency is loaded. Every required piece is preflighted before stripping.
-- Vanilla's registered long robe is LongCoat_Bathrobe; give the wizard a
-- deliberate violet robe instead of the old stovepipe / generic XML outfit.
for _, costume in ipairs(HWE.Costumes) do
    if costume.id == "Wizard" then
        costume.visualTints = {["Base.LongCoat_Bathrobe"]={0.25, 0.12, 0.48}}
    elseif costume.id == "Doctor" or costume.id == "Nurse" then
        -- Retain the working native outfit, then add one required face mask.
        costume.additionalItems = {"Base.Hat_SurgicalMask"}
        costume.optionalItems = {"Base.Hat_SurgicalCap", "Base.Hat_HeadMirrorUP"}
        costume.optionalChance = 40
        costume.recipeRevision = 11
        costume.menuGroup = "Medical"
    elseif costume.id == "Firefighter" then
        costume.naturalWeight = 25 -- Default family weight is 100.
    elseif costume.id == "Cultist" then
        costume.visualMode = "replace"
        costume.visualItems = {"Base.Shirt_Priest", "Base.Trousers_Suit", "Base.LongCoat_Bathrobe", "Base.Shoes_BlackBoots", "Base.Hat_HalloweenMaskSkeleton"}
        costume.visualTints = {["Base.LongCoat_Bathrobe"]={0.10, 0.06, 0.14}}
        costume.recipeRevision = 11
    elseif costume.id == "TieDyeHippie" then
        costume.optionalItems = {"Base.Hat_BandanaTiedTINT", "Base.Hat_BandanaTied", "Base.Hat_RagBandanaTied"}
        costume.optionalChance = 60
        costume.recipeRevision = 11
    elseif costume.id == "EDP_BunnyBlack" or costume.id == "EDP_BunnyPink" then
        costume.menuGroup = "Bunny Costumes"
    elseif costume.id == "SantaClaus" or costume.id == "SantaClausGreen" then
        costume.menuGroup = "Santa Costumes"
        costume.optionalItems = {"Base.Hat_HalloweenMaskDevil", "Base.Hat_HalloweenMaskMonster", "Base.Hat_HalloweenMaskPumpkin", "Base.Hat_HalloweenMaskSkeleton", "Base.Hat_HalloweenMaskVampire", "Base.Hat_HalloweenMaskWitch"}
        costume.optionalChance = 60
        costume.santaKnifeFallback = true
        costume.recipeRevision = 12
    elseif costume.id == "Police" then
        costume.noFirearms = true
    end
    if costume.id == "JayChicken" then
        costume.poolFamily, costume.menuGroup, costume.variantWeight = "JayChicken", "Chicken Costumes", 70
    elseif costume.id == "Witch" then
        costume.poolFamily, costume.menuGroup, costume.variantWeight = "Witch", "Wicked Witch", 70
    end
end

-- New recipes use registered B42.21 item types from the supplied test log.
-- GUIDs supplied as outfit references are not item types or dependencies.
-- A sports family has one natural weight, regardless of its variant count.
local function addRecipe(id, name, category, items, family, tints, femaleOnly)
    HWE.Costumes[#HWE.Costumes + 1] = {
        id=id, name=name, category=category, build="hwe", approx=false,
        natural=true, outfit="HWE_" .. id, femaleOnly=femaleOnly == true,
        detectByOutfit=false, visualMode="replace", visualItems=items,
        poolFamily=family, menuGroup=family, visualTints=tints,
        auditGenderAssets=true, debugGenderChoices=femaleOnly ~= true
    }
end

addRecipe("Schoolgirl", "Schoolgirl", "Theme / Party",
    {"Base.Shirt_FormalWhite", "Base.Skirt_Short", "Base.Tie_Full", "Base.Socks_Long_White", "Base.Shoes_Black"}, nil,
    {["Base.Skirt_Short"]={0.08,0.12,0.25}, ["Base.Tie_Full"]={0.55,0.08,0.12}}, true)
addRecipe("Prisoner", "Prisoner (Orange)", "Professions",
    {"Base.Boilersuit_Prisoner", "Base.Shoes_Black"})
addRecipe("Priest", "Priest", "Professions",
    {"Base.Shirt_Priest", "Base.Trousers_Suit", "Base.Shoes_Black"}, nil,
    {["Base.Trousers_Suit"]={0.08,0.08,0.08}})

for _, team in ipairs({"KY", "Rangers", "Z"}) do
    addRecipe("Baseball_" .. team, "Baseball Player (" .. team .. ")", "Sports Costumes",
        {"Base.Shirt_Baseball_" .. team, "Base.Trousers_WhiteTINT", "Base.Socks_Long_Black", "Base.Shoes_TrainerTINT", "Base.Hat_BaseballHelmet_" .. team}, "Baseball",
        {["Base.Trousers_WhiteTINT"]={0.92,0.92,0.90}, ["Base.Shoes_TrainerTINT"]={0.12,0.12,0.12}})
end

for _, color in ipairs({"Red", "Blue"}) do
    local tint = color == "Red" and {0.70,0.08,0.10} or {0.08,0.18,0.65}
    addRecipe("Boxing_" .. color, "Boxer (" .. color .. ")", "Sports Costumes",
        {"Base.Vest_DefaultTEXTURE_TINT", "Base.Shorts_Boxing" .. color, "Base.Gloves_Boxing" .. color, "Base.Hat_Boxing" .. color, "Base.Shoes_TrainerTINT"}, "Boxing",
        {["Base.Vest_DefaultTEXTURE_TINT"]=tint, ["Base.Shoes_TrainerTINT"]={0.12,0.12,0.12}})
end

for _, variant in ipairs({
    {"Red", "Black", {0.70,0.08,0.10}},
    {"Blue", "White", {0.08,0.18,0.65}},
    {"White", "Gold", {0.90,0.90,0.86}}
}) do
    local color, pants, tint = variant[1], variant[2], variant[3]
    addRecipe("Football_" .. color, "Football Player (" .. color .. ")", "Sports Costumes",
        {"Base.Tshirt_Sport", "Base.Shorts_FootballPants_" .. pants, "Base.Socks_Long_White", "Base.Shoes_TrainerTINT", "Base.Hat_FootballHelmet_" .. color}, "Football",
        {["Base.Tshirt_Sport"]=tint, ["Base.Shoes_TrainerTINT"]={0.12,0.12,0.12}})
end

for _, variant in ipairs({
    {"Black", "Black", "Black", {0.10,0.10,0.12}},
    {"Blue", "UniBlue", "Blue", {0.08,0.18,0.65}},
    {"Red", "Red", "Black", {0.70,0.08,0.10}},
    {"White", "White", "White", {0.90,0.90,0.86}},
    {"Green", "Black", "Black", {0.08,0.40,0.18}},
    {"Gold", "Black", "Black", {0.80,0.55,0.10}},
    {"Purple", "Black", "White", {0.40,0.12,0.60}},
    {"Orange", "Black", "White", {0.90,0.30,0.05}}
}) do
    local color, pants, gloves, tint = variant[1], variant[2], variant[3], variant[4]
    addRecipe("Hockey_" .. color, "Hockey Player (" .. color .. ")", "Sports Costumes",
        {"Base.Tshirt_Sport", "Base.Shorts_HockeyPants_" .. pants, "Base.Gloves_IceHockeyGloves_" .. gloves, "Base.Socks_Long_White", "Base.Shoes_TrainerTINT", "Base.Hat_HockeyHelmet_TINT"}, "Hockey",
        {["Base.Tshirt_Sport"]=tint, ["Base.Hat_HockeyHelmet_TINT"]=tint, ["Base.Shoes_TrainerTINT"]={0.12,0.12,0.12}})
end

-- Sports is ONE weighted entry. Equal sport selection happens before the team
-- selection, so eight hockey colors neither boost Sports nor crowd out Boxing.
for _, costume in ipairs(HWE.Costumes) do
    if costume.category == "Sports Costumes" then
        costume.poolGroup, costume.poolFamily = costume.menuGroup, "Sports"
    end
end

addRecipe("Chicken_CorsetWhite", "Chicken Showgirl (White Skirt)", "Characters",
    {"Base.Corset", "Base.Skirt_Short", "Base.Socks_Long_White", "Base.Shoes_Strapped", "Base.Hat_Jay"}, "JayChicken",
    {["Base.Corset"]={0.95,0.95,0.92}, ["Base.Skirt_Short"]={0.95,0.95,0.92}}, true)
addRecipe("Chicken_CorsetBlack", "Chicken Showgirl (Black Skirt)", "Characters",
    {"Base.Corset", "Base.Skirt_Short", "Base.Socks_Long_White", "Base.Shoes_Strapped", "Base.Hat_Jay"}, "JayChicken",
    {["Base.Corset"]={0.95,0.95,0.92}, ["Base.Skirt_Short"]={0.08,0.08,0.10}}, true)
addRecipe("Chicken_ShirtlessShorts", "Chicken Showman (White Shorts)", "Characters",
    {"Base.Shorts_ShortSport", "Base.Shoes_TrainerTINT", "Base.Hat_Jay"}, "JayChicken",
    {["Base.Shorts_ShortSport"]={0.95,0.95,0.92}})
addRecipe("Chicken_ShirtlessBoxers", "Chicken Showman (White Underwear)", "Characters",
    {"Base.Boxers_White", "Base.Shoes_TrainerTINT", "Base.Hat_Jay"}, "JayChicken")
addRecipe("Witch_StraplessDress", "Wicked Witch (Strapless Dress)", "Fantasy",
    {"Base.TightsFishnets", "Base.Garter", "Base.Dress_SmallStrapless", "Base.Gloves_LongWomenGloves", "Base.Shoes_Strapped", "Base.Hat_Witch"}, "Witch", nil, true)
for _, costume in ipairs(HWE.Costumes) do
    if costume.id:find("^Chicken_") then
        costume.menuGroup, costume.variantWeight = "Chicken Costumes", 15
        if not costume.femaleOnly then costume.maleOnly, costume.debugGenderChoices = true, false end
    elseif costume.id == "Witch_StraplessDress" then
        costume.menuGroup, costume.variantWeight = "Wicked Witch", 30
        -- The tintable vanilla dress shares the strapless shape. Keep one profile.
        costume.visualTintChoices = {["Base.Dress_SmallStrapless"]={
            {0.08,0.08,0.08}, {0.42,0.18,0.55}, {0.16,0.42,0.25}
        }}
    end
end

-- Neckwear uses the existing server optional-accessory path. Gallery mirrors it.
for _, costume in ipairs(HWE.Costumes) do
    if costume.id == "CowboyStripper" then
        costume.optionalItems = {"Base.Tie_BowTieWorn", "Base.Necklace_Choker"}
        costume.optionalChance = 67
        costume.recipeRevision = 37
    elseif costume.id == "EDP_BunnyBlack" or costume.id == "EDP_BunnyPink" then
        costume.optionalItems = {"Base.Necklace_Crucifix", "Base.Necklace_Choker"}
        costume.optionalChance = 100
        costume.recipeRevision = 37
    elseif costume.id == "Witch" or costume.id == "Witch_StraplessDress" then
        costume.recipeRevision = 37
    end
end

function HWE.getCostumeByID(id)
    if not id then return nil end
    for _, costume in ipairs(HWE.Costumes or {}) do
        if costume.id == id then return costume end
    end
    return nil
end

return HWE
