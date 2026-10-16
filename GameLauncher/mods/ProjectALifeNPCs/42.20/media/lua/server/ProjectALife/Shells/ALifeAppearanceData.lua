ProjectALife = ProjectALife or {}

local Data = {}
ProjectALife.AppearanceData = Data

Data.hair = {
    male = {
        uniformed = {
            plain = { { "CrewCut", 5 }, { "Short", 5 }, { "FlatTop", 3 }, { "Recede", 3 }, { "Baldspot", 2 }, { "Bald", 2 },
                { "LeftParting", 2 }, { "RightParting", 2 }, { "CentreParting", 1 }, { "Messy", 1 }, { "Picard", 1 } },
            textured = { { "CrewCut", 4 }, { "FlatTop", 4 }, { "ShortAfroCurly", 5 }, { "Fresh", 3 }, { "Bald", 3 }, { "MessyCurly", 1 } },
        },
        working = {
            plain = { { "Short", 5 }, { "Messy", 3 }, { "Recede", 3 }, { "LeftParting", 3 }, { "RightParting", 3 },
                { "CrewCut", 2 }, { "CentreParting", 2 }, { "Baldspot", 2 }, { "FlatTop", 2 }, { "Mullet", 2 },
                { "MessyCurly", 1 }, { "Bald", 1 }, { "GreasedBack", 1 }, { "PonyTail", 1 }, { "Picard", 1 } },
            textured = { { "ShortAfroCurly", 5 }, { "Fresh", 3 }, { "Cornrows", 2 }, { "Braids", 2 }, { "FlatTop", 2 },
                { "Bald", 2 }, { "MessyCurly", 2 }, { "CrewCut", 2 }, { "LongBraids", 1 } },
        },
        rough = {
            plain = { { "Mullet", 4 }, { "Messy", 3 }, { "GreasedBack", 3 }, { "Short", 2 }, { "Recede", 2 }, { "Bald", 2 },
                { "PonyTail", 2 }, { "Grungey", 2 }, { "CrewCut", 1 }, { "CentrePartingLong", 1 }, { "Spike", 1 },
                { "Metal", 1 }, { "MulletCurly", 1 } },
            textured = { { "Cornrows", 3 }, { "Braids", 3 }, { "ShortAfroCurly", 3 }, { "Bald", 3 }, { "LongBraids", 2 },
                { "Fresh", 2 }, { "MessyCurly", 2 }, { "FlatTop", 1 } },
        },
        elder = {
            plain = { { "Recede", 4 }, { "Short", 4 }, { "Bald", 3 }, { "Baldspot", 3 }, { "Picard", 2 }, { "CrewCut", 1 },
                { "LeftParting", 1 }, { "RightParting", 1 }, { "CentreParting", 1 } },
            textured = { { "Bald", 4 }, { "ShortAfroCurly", 4 }, { "Fresh", 1 }, { "FlatTop", 1 }, { "CrewCut", 1 } },
        },
    },
    female = {
        uniformed = {
            plain = { { "Bun", 5 }, { "PonyTail", 4 }, { "Back", 3 }, { "Bob", 3 }, { "Demi", 2 }, { "ShortCurly", 1 },
                { "BunCurly", 1 }, { "CentreParting", 1 } },
            textured = { { "BunCurly", 4 }, { "ShortCurly", 3 }, { "Cornrows", 2 }, { "Braids", 2 }, { "PonyTailBraids", 2 },
                { "TopCurls", 2 }, { "BobCurly", 1 }, { "Demi", 1 } },
        },
        working = {
            plain = { { "Bob", 4 }, { "PonyTail", 4 }, { "Bun", 3 }, { "Kate", 3 }, { "Rachel", 3 }, { "Back", 2 },
                { "Demi", 2 }, { "ShortCurly", 2 }, { "BobCurly", 2 }, { "CentreParting", 2 }, { "Long", 2 },
                { "LeftParting", 1 }, { "RightParting", 1 }, { "Long2", 1 }, { "OverEye", 1 }, { "CentrePartingLong", 1 },
                { "KateCurly", 1 }, { "RachelCurly", 1 } },
            textured = { { "BobCurly", 3 }, { "BunCurly", 3 }, { "ShortCurly", 3 }, { "Braids", 3 }, { "TopCurls", 3 },
                { "Cornrows", 2 }, { "PonyTailBraids", 2 }, { "LongBraids", 2 }, { "Longcurly", 1 }, { "KateCurly", 1 } },
        },
        rough = {
            plain = { { "PonyTail", 4 }, { "Long", 3 }, { "Grungey", 3 }, { "Long2", 2 }, { "Back", 2 }, { "Bob", 2 },
                { "Kate", 2 }, { "OverEye", 2 }, { "Bun", 1 }, { "GrungeyParted", 1 }, { "Spike", 1 } },
            textured = { { "Cornrows", 3 }, { "Braids", 3 }, { "LongBraids", 2 }, { "PonyTailBraids", 2 }, { "BobCurly", 2 },
                { "TopCurls", 2 }, { "Longcurly", 1 } },
        },
        elder = {
            plain = { { "Bun", 4 }, { "Back", 3 }, { "Bob", 3 }, { "ShortCurly", 3 }, { "Demi", 2 }, { "CentreParting", 1 } },
            textured = { { "BunCurly", 4 }, { "ShortCurly", 4 }, { "TopCurls", 2 }, { "Cornrows", 1 } },
        },
    },
}

Data.beards = {
    uniformed = { chance = 0.10, styles = { { "Moustache", 5 }, { "Chin", 2 }, { "Goatee", 1 }, { "Chops", 1 } } },
    working = { chance = 0.22, styles = { { "Moustache", 4 }, { "Chops", 3 }, { "BeardOnly", 3 }, { "Goatee", 2 },
        { "Chin", 2 }, { "Full", 2 }, { "PointyChin", 1 } } },
    rough = { chance = 0.40, styles = { { "Full", 4 }, { "BeardOnly", 4 }, { "Chops", 3 }, { "Moustache", 3 }, { "Goatee", 2 },
        { "Long", 1 }, { "LongScruffy", 1 }, { "Chin", 1 } } },
    elder = { chance = 0.30, styles = { { "Full", 3 }, { "BeardOnly", 3 }, { "Moustache", 3 }, { "Chops", 2 }, { "Long", 1 },
        { "Chin", 1 } } },
    young = { chance = 0.08, styles = { { "Moustache", 3 }, { "Chin", 3 }, { "Goatee", 2 }, { "Chops", 1 } } },
    authoredKeeps = 0.6,
}

Data.hairTints = {
    young = {
        { "0.07,0.06,0.06", 5 }, { "0.10,0.08,0.06", 5 }, { "0.20,0.13,0.09", 5 }, { "0.25,0.15,0.08", 5 },
        { "0.31,0.20,0.12", 4 }, { "0.40,0.26,0.14", 4 }, { "0.48,0.31,0.15", 4 }, { "0.55,0.40,0.22", 3 },
        { "0.38,0.16,0.08", 3 }, { "0.52,0.22,0.12", 2 }, { "0.68,0.33,0.16", 1 }, { "0.68,0.56,0.30", 4 },
        { "0.78,0.62,0.36", 3 }, { "0.60,0.46,0.27", 3 }, { "0.88,0.80,0.60", 1 },
    },
    adult = {
        { "0.07,0.06,0.06", 5 }, { "0.10,0.08,0.06", 5 }, { "0.16,0.11,0.08", 4 }, { "0.20,0.13,0.09", 4 },
        { "0.25,0.15,0.08", 5 }, { "0.31,0.20,0.12", 4 }, { "0.40,0.26,0.14", 4 }, { "0.48,0.31,0.15", 4 },
        { "0.55,0.40,0.22", 3 }, { "0.38,0.16,0.08", 3 }, { "0.45,0.20,0.10", 2 }, { "0.68,0.33,0.16", 1 },
        { "0.68,0.56,0.30", 3 }, { "0.78,0.62,0.36", 2 }, { "0.35,0.33,0.31", 2 }, { "0.52,0.50,0.46", 2 },
        { "0.42,0.41,0.40", 1 },
    },
    older = {
        { "0.52,0.50,0.46", 5 }, { "0.62,0.62,0.60", 4 }, { "0.74,0.74,0.72", 4 }, { "0.42,0.41,0.40", 3 },
        { "0.88,0.88,0.86", 3 }, { "0.93,0.93,0.92", 2 }, { "0.35,0.33,0.31", 2 }, { "0.30,0.28,0.26", 1 },
    },
    dark = {
        { "0.07,0.06,0.06", 8 }, { "0.10,0.08,0.06", 8 }, { "0.16,0.11,0.08", 5 }, { "0.20,0.13,0.09", 4 },
        { "0.25,0.15,0.08", 2 }, { "0.31,0.20,0.12", 1 },
    },
    darkOlder = {
        { "0.52,0.50,0.46", 4 }, { "0.42,0.41,0.40", 3 }, { "0.62,0.62,0.60", 3 }, { "0.35,0.33,0.31", 2 },
        { "0.10,0.08,0.06", 1 },
    },
}

Data.tintable = {
    ["Base.Bag_BurglarBag"] = true, ["Base.Bag_DuffelBagTINT"] = true, ["Base.Bag_InmateEscapedBag"] = true,
    ["Base.Bag_MoneyBag"] = true, ["Base.Bag_WorkerBag"] = true, ["Base.Bikini_Pattern01"] = true,
    ["Base.Bikini_TINT"] = true, ["Base.Boilersuit"] = true, ["Base.BoobTube"] = true, ["Base.BoobTubeSmall"] = true,
    ["Base.Boxers_White"] = true, ["Base.Bra_Strapless_White"] = true, ["Base.Bra_Straps_White"] = true,
    ["Base.Bracelet_LeftFriendshipTINT"] = true, ["Base.Bracelet_RightFriendshipTINT"] = true,
    ["Base.Briefs_SmallTrunks_WhiteTINT"] = true, ["Base.Briefs_White"] = true, ["Base.Corset"] = true,
    ["Base.DressKnees_Straps"] = true, ["Base.Dress_Knees"] = true, ["Base.Dress_Long"] = true,
    ["Base.Dress_Normal"] = true, ["Base.Dress_SatinNegligee"] = true, ["Base.Dress_Short"] = true,
    ["Base.Dress_SmallStrapless"] = true, ["Base.Dress_SmallStraps"] = true, ["Base.Dress_Straps"] = true,
    ["Base.Dress_long_Straps"] = true, ["Base.ElbowPad_Left_TINT"] = true, ["Base.ElbowPad_Right_TINT"] = true,
    ["Base.Gloves_FingerlessGloves"] = true, ["Base.Gloves_WhiteTINT"] = true, ["Base.Hat_BalaclavaFace"] = true,
    ["Base.Hat_BalaclavaFull"] = true, ["Base.Hat_BandanaMaskTINT"] = true, ["Base.Hat_BandanaTINT"] = true,
    ["Base.Hat_BandanaTiedTINT"] = true, ["Base.Hat_BaseballCapTINT"] = true,
    ["Base.Hat_BaseballCapTINT_Reverse"] = true, ["Base.Hat_Beany"] = true, ["Base.Hat_Beret"] = true,
    ["Base.Hat_BicycleHelmet"] = true, ["Base.Hat_BucketHat"] = true, ["Base.Hat_CrashHelmet"] = true,
    ["Base.Hat_EarMuffs"] = true, ["Base.Hat_GolfHatTINT"] = true, ["Base.Hat_HockeyHelmet_TINT"] = true,
    ["Base.Hat_PartyHat_TINT"] = true, ["Base.Hat_Sweatband"] = true, ["Base.Hat_Visor_WhiteTINT"] = true,
    ["Base.Hat_WoolyHat"] = true, ["Base.HoodieDOWN_WhiteTINT"] = true, ["Base.HoodieUP_WhiteTINT"] = true,
    ["Base.Jacket_Padded"] = true, ["Base.Jacket_PaddedDOWN"] = true, ["Base.Jacket_Shellsuit_TINT"] = true,
    ["Base.Jacket_WhiteTINT"] = true, ["Base.Jumper_DiamondPatternTINT"] = true, ["Base.Jumper_PoloNeck"] = true,
    ["Base.Jumper_RoundNeck"] = true, ["Base.Jumper_TankTopDiamondTINT"] = true, ["Base.Jumper_TankTopTINT"] = true,
    ["Base.Jumper_VNeck"] = true, ["Base.Kneepad_Left_TINT"] = true, ["Base.Kneepad_Right_TINT"] = true,
    ["Base.LongCoat_Bathrobe"] = true, ["Base.LongCoat_Hide"] = true, ["Base.Scarf_White"] = true,
    ["Base.ShinKneeGuard_L_TINT"] = true, ["Base.ShinKneeGuard_R_TINT"] = true,
    ["Base.Shirt_CropTopNoArmTINT"] = true, ["Base.Shirt_CropTopTINT"] = true, ["Base.Shirt_FormalTINT"] = true,
    ["Base.Shirt_FormalWhite_ShortSleeveTINT"] = true, ["Base.Shirt_HawaiianTINT"] = true,
    ["Base.Shirt_Lumberjack_TINT"] = true, ["Base.Shoes_Fancy"] = true, ["Base.Shoes_FlipFlop"] = true,
    ["Base.Shoes_Slippers"] = true, ["Base.Shoes_TrainerTINT"] = true, ["Base.Shoes_Wellies"] = true,
    ["Base.Shorts_ShortFormal"] = true, ["Base.Skirt_Knees"] = true, ["Base.Skirt_Long"] = true,
    ["Base.Skirt_Mini"] = true, ["Base.Skirt_Normal"] = true, ["Base.Skirt_Short"] = true,
    ["Base.Socks_Ankle"] = true, ["Base.Socks_LegWarmers"] = true, ["Base.Socks_Long"] = true,
    ["Base.Suit_JacketTINT"] = true, ["Base.Swimsuit_TINT"] = true, ["Base.Trousers_DefaultTEXTURE_HUE"] = true,
    ["Base.Trousers_DefaultTEXTURE_TINT"] = true, ["Base.Trousers_Padded"] = true,
    ["Base.Trousers_Padded_HuntingCamo"] = true, ["Base.Trousers_Shellsuit_TINT"] = true,
    ["Base.Trousers_SuitWhite"] = true, ["Base.Trousers_WhiteTINT"] = true, ["Base.Tshirt_DefaultDECAL_TINT"] = true,
    ["Base.Tshirt_DefaultTEXTURE_TINT"] = true, ["Base.Tshirt_EMD"] = true, ["Base.Tshirt_HipHop"] = true,
    ["Base.Tshirt_IndieStoneDECAL"] = true, ["Base.Tshirt_PoloStripedTINT"] = true, ["Base.Tshirt_PoloTINT"] = true,
    ["Base.Tshirt_SpiffoDECAL"] = true, ["Base.Tshirt_TieDye"] = true, ["Base.Tshirt_WhiteLongSleeveTINT"] = true,
    ["Base.Tshirt_WhiteTINT"] = true, ["Base.Underpants_White"] = true, ["Base.Vest_DefaultTEXTURE_TINT"] = true,
    ["Base.Vest_WaistcoatTINT"] = true,
}

Data.dyeClass = {
    Top = "tops", Tshirt = "tops", TankTop = "tops", Sweater = "tops", Shirt = "tops", Dress = "tops",
    Pants = "legs", Skirt = "legs",
    Jacket = "outer", Vest = "outer",
    Hat = "head", Scarf = "head", Mask = "head", Ears = "head",
    Shoes = "foot", Socks = "foot", Hands = "foot", Fingers = "foot",
}

Data.dye = {
    tops = {
        { "0.93,0.93,0.91", 2 }, { "0.89,0.85,0.72", 1 }, { "0.68,0.68,0.68", 2 }, { "0.30,0.30,0.32", 2 },
        { "0.14,0.14,0.15", 1 }, { "0.17,0.21,0.38", 2 }, { "0.34,0.46,0.64", 2 }, { "0.58,0.72,0.84", 1 },
        { "0.20,0.36,0.24", 1 }, { "0.42,0.44,0.26", 2 }, { "0.66,0.60,0.42", 1 }, { "0.40,0.28,0.19", 1 },
        { "0.46,0.17,0.20", 1 }, { "0.60,0.26,0.22", 1 }, { "0.74,0.60,0.24", 1 }, { "0.34,0.50,0.50", 1 },
    },
    legs = {
        { "0.28,0.38,0.56", 5 }, { "0.18,0.23,0.36", 4 }, { "0.13,0.13,0.14", 3 }, { "0.28,0.28,0.30", 3 },
        { "0.66,0.58,0.40", 3 }, { "0.36,0.38,0.24", 2 }, { "0.34,0.25,0.17", 2 }, { "0.50,0.50,0.50", 2 },
        { "0.74,0.66,0.50", 1 }, { "0.15,0.19,0.32", 2 },
    },
    outer = {
        { "0.13,0.13,0.14", 3 }, { "0.30,0.30,0.31", 2 }, { "0.16,0.20,0.34", 3 }, { "0.36,0.25,0.16", 3 },
        { "0.62,0.50,0.34", 2 }, { "0.34,0.37,0.22", 3 }, { "0.18,0.30,0.20", 2 }, { "0.38,0.14,0.17", 1 },
        { "0.52,0.52,0.53", 2 }, { "0.30,0.40,0.56", 2 }, { "0.62,0.48,0.18", 1 },
    },
    head = {
        { "0.14,0.14,0.15", 3 }, { "0.32,0.32,0.33", 2 }, { "0.16,0.20,0.34", 3 }, { "0.36,0.25,0.16", 2 },
        { "0.20,0.34,0.22", 2 }, { "0.40,0.14,0.18", 2 }, { "0.55,0.55,0.55", 2 }, { "0.66,0.60,0.42", 2 },
        { "0.38,0.40,0.24", 2 }, { "0.70,0.60,0.44", 1 }, { "0.86,0.82,0.70", 1 }, { "0.62,0.20,0.20", 1 },
    },
    foot = {
        { "0.90,0.90,0.88", 3 }, { "0.14,0.14,0.15", 4 }, { "0.55,0.55,0.55", 2 }, { "0.16,0.20,0.34", 2 },
        { "0.34,0.24,0.16", 2 }, { "0.58,0.20,0.18", 1 }, { "0.64,0.54,0.38", 1 }, { "0.20,0.36,0.24", 1 },
    },
}

Data.uniformedBlocs = { law = true, military = true, elite = true, rescue = true, prison = true }
Data.roughBlocs = { raider = true, gang = true, club = true, crime = true }

return Data
