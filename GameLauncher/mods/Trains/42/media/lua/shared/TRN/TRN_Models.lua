--[[ Trains -- the pieces of the models. GENERATED: python tools/gen_train_models.py

    The engine swaps a model's texture for a smaller copy when it is bigger
    than the player's Max texture size, and that option goes down to 256
    pixels (DEV_GUIDE.md, *A model's texture is no bigger than a player's
    display option*). So a model painted on a bigger sheet is cut into
    pieces of a 256 sheet each, and all of them are drawn at the one place
    (TRN_Body.lua). A model that is not here is drawn as itself.
]]

TRN = TRN or {}

TRN.Pages = {
    TrnBoxcarBlue = { "TrnBoxcarBlueP1", "TrnBoxcarBlueP2", "TrnBoxcarBlueP3", "TrnBoxcarBlueP4", "TrnBoxcarBlueP5", "TrnBoxcarBlueP6", "TrnBoxcarBlueP7" },
    TrnBoxcarBlueTag = { "TrnBoxcarBlueTagP1", "TrnBoxcarBlueTagP2", "TrnBoxcarBlueTagP3", "TrnBoxcarBlueTagP4", "TrnBoxcarBlueTagP5", "TrnBoxcarBlueTagP6", "TrnBoxcarBlueTagP7" },
    TrnBoxcarBrown = { "TrnBoxcarBrownP1", "TrnBoxcarBrownP2", "TrnBoxcarBrownP3", "TrnBoxcarBrownP4", "TrnBoxcarBrownP5", "TrnBoxcarBrownP6", "TrnBoxcarBrownP7" },
    TrnBoxcarBrownTag = { "TrnBoxcarBrownTagP1", "TrnBoxcarBrownTagP2", "TrnBoxcarBrownTagP3", "TrnBoxcarBrownTagP4", "TrnBoxcarBrownTagP5", "TrnBoxcarBrownTagP6", "TrnBoxcarBrownTagP7" },
    TrnBoxcarRed = { "TrnBoxcarRedP1", "TrnBoxcarRedP2", "TrnBoxcarRedP3", "TrnBoxcarRedP4", "TrnBoxcarRedP5", "TrnBoxcarRedP6", "TrnBoxcarRedP7" },
    TrnBoxcarRedTag = { "TrnBoxcarRedTagP1", "TrnBoxcarRedTagP2", "TrnBoxcarRedTagP3", "TrnBoxcarRedTagP4", "TrnBoxcarRedTagP5", "TrnBoxcarRedTagP6", "TrnBoxcarRedTagP7" },
    TrnBoxcarWhite = { "TrnBoxcarWhiteP1", "TrnBoxcarWhiteP2", "TrnBoxcarWhiteP3", "TrnBoxcarWhiteP4", "TrnBoxcarWhiteP5", "TrnBoxcarWhiteP6", "TrnBoxcarWhiteP7" },
    TrnBoxcarYellow = { "TrnBoxcarYellowP1", "TrnBoxcarYellowP2", "TrnBoxcarYellowP3", "TrnBoxcarYellowP4", "TrnBoxcarYellowP5", "TrnBoxcarYellowP6", "TrnBoxcarYellowP7" },
    TrnBoxcarYellowTag = { "TrnBoxcarYellowTagP1", "TrnBoxcarYellowTagP2", "TrnBoxcarYellowTagP3", "TrnBoxcarYellowTagP4", "TrnBoxcarYellowTagP5", "TrnBoxcarYellowTagP6", "TrnBoxcarYellowTagP7" },
    TrnCaboose = { "TrnCabooseP1", "TrnCabooseP2", "TrnCabooseP3", "TrnCabooseP4", "TrnCabooseP5" },
    TrnCoachGreen = { "TrnCoachGreenP1", "TrnCoachGreenP2", "TrnCoachGreenP3", "TrnCoachGreenP4", "TrnCoachGreenP5" },
    TrnCoachMed = { "TrnCoachMedP1", "TrnCoachMedP2", "TrnCoachMedP3", "TrnCoachMedP4", "TrnCoachMedP5" },
    TrnCoachNew = { "TrnCoachNewP1", "TrnCoachNewP2", "TrnCoachNewP3", "TrnCoachNewP4", "TrnCoachNewP5" },
    TrnCoachRed = { "TrnCoachRedP1", "TrnCoachRedP2", "TrnCoachRedP3", "TrnCoachRedP4", "TrnCoachRedP5" },
    TrnCoachWorn = { "TrnCoachWornP1", "TrnCoachWornP2", "TrnCoachWornP3", "TrnCoachWornP4", "TrnCoachWornP5" },
    TrnFlatcar = { "TrnFlatcarP1", "TrnFlatcarP2", "TrnFlatcarP3", "TrnFlatcarP4", "TrnFlatcarP5" },
    TrnGondolaGreen = { "TrnGondolaGreenP1", "TrnGondolaGreenP2", "TrnGondolaGreenP3", "TrnGondolaGreenP4", "TrnGondolaGreenP5", "TrnGondolaGreenP6", "TrnGondolaGreenP7" },
    TrnGondolaRust = { "TrnGondolaRustP1", "TrnGondolaRustP2", "TrnGondolaRustP3", "TrnGondolaRustP4", "TrnGondolaRustP5", "TrnGondolaRustP6", "TrnGondolaRustP7" },
    TrnLocoBlack = { "TrnLocoBlackP1", "TrnLocoBlackP2", "TrnLocoBlackP3", "TrnLocoBlackP4" },
    TrnLocoBlue = { "TrnLocoBlueP1", "TrnLocoBlueP2", "TrnLocoBlueP3", "TrnLocoBlueP4" },
    TrnLocoGreen = { "TrnLocoGreenP1", "TrnLocoGreenP2", "TrnLocoGreenP3", "TrnLocoGreenP4" },
    TrnSignArr = { "TrnSignArrP1", "TrnSignArrP2" },
    TrnSignDep = { "TrnSignDepP1", "TrnSignDepP2" },
    TrnTankBlack = { "TrnTankBlackP1", "TrnTankBlackP2", "TrnTankBlackP3", "TrnTankBlackP4", "TrnTankBlackP5", "TrnTankBlackP6" },
    TrnTankRust = { "TrnTankRustP1", "TrnTankRustP2", "TrnTankRustP3", "TrnTankRustP4", "TrnTankRustP5", "TrnTankRustP6" },
    TrnTankWhite = { "TrnTankWhiteP1", "TrnTankWhiteP2", "TrnTankWhiteP3", "TrnTankWhiteP4", "TrnTankWhiteP5", "TrnTankWhiteP6" },
}

return TRN.Pages
