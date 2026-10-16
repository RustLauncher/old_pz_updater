CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Remedios de ervas vindos do Mans Best Friend, mais os emplastros, a tala e a pinca do jogo base.
-- Carrega depois do Vet.lua (ordem por caminho em minusculas) e so acrescenta linhas nas tabelas dele.

CD.VET_ITEM_ALLERGY_BLEND = "Base.CompanionDogsAllergyBlend"
CD.VET_ITEM_ALLERGY_TEA = "Base.CompanionDogsAllergyTea"
CD.VET_ITEM_SKIN_WASH = "Base.CompanionDogsSkinWash"
CD.VET_ITEM_INSECT_REPELLENT = "Base.CompanionDogsInsectRepellent"
CD.VET_ITEM_SHAMPOO = "Base.CompanionDogsFleaTickShampoo"
CD.VET_ITEM_DETOX = "Base.CompanionDogsHerbalDetox"
CD.VET_ITEM_PARASITE_TINCTURE = "Base.CompanionDogsParasiteTincture"
CD.VET_ITEM_RESP_HERBS = "Base.CompanionDogsRespiratoryHerbs"
CD.VET_ITEM_CHAMOMILE = "Base.CompanionDogsChamomileTea"
CD.VET_ITEM_IMMUNE_TINCTURE = "Base.CompanionDogsImmuneTincture"
CD.VET_ITEM_IMMUNE_POWDER = "Base.CompanionDogsImmunePowder"
CD.VET_ITEM_IMMUNE_BALANCING = "Base.CompanionDogsImmuneBalancingPowder"
CD.VET_ITEM_SYSTEMIC = "Base.CompanionDogsSystemicTincture"
CD.VET_ITEM_OATMEAL = "Base.CompanionDogsOatmealBath"
CD.VET_ITEM_ALOE = "Base.CompanionDogsAloeVera"
CD.VET_ITEM_PLANTAIN = "Base.PlantainCataplasm"
CD.VET_ITEM_GARLIC = "Base.WildGarlicCataplasm"
CD.VET_ITEM_COMFREY = "Base.ComfreyCataplasm"
CD.VET_ITEM_SPLINT = "Base.Splint"
CD.VET_ITEM_TWEEZERS = "Base.Tweezers"

-- Curso e protecao dos remedios de ervas, em minutos de jogo. A locao e o antialergico mais trabalhoso
-- de fazer e por isso o mais forte.
CD.VET_HERB_ALG_BLEND_MIN = 480
CD.VET_HERB_ALG_BLEND_PREV_MIN = 3600
CD.VET_HERB_ALG_TEA_MIN = 540
CD.VET_HERB_ALG_TEA_PREV_MIN = 2160
CD.VET_HERB_SKIN_WASH_MIN = 240
CD.VET_HERB_SKIN_WASH_PREV_MIN = 4320
CD.VET_HERB_REPELLENT_MIN = 600
CD.VET_HERB_REPELLENT_PREV_MIN = 4320
CD.VET_HERB_SHAMPOO_PREV_MIN = 20160
CD.VET_HERB_DETOX_WORMS_MIN = 480
CD.VET_HERB_DETOX_HW_MIN = 480
CD.VET_HERB_DETOX_TOXIC_CUT_MIN = 480
CD.VET_HERB_TINCTURE_PREV_MIN = 14400
CD.VET_HERB_RESP_MIN = 1440
CD.VET_HERB_CHAMOMILE_GASTRO_CUT_MIN = 720
CD.VET_HERB_CHAMOMILE_STRESS = 0.15
CD.VET_HERB_CHAMOMILE_STRESS_MIN = 0.1
CD.VET_GARLIC_MIN = 1440

-- Imunidade de ervas: a mesma protecao da vacina, por menos tempo. A ordem de duracao segue a forca que
-- o MBF dava a cada um (tintura 25%, po 35%, po de equilibrio 45% de chance a menos).
CD.VET_HERB_IMMUNE_TINCTURE_MIN = 4320
CD.VET_HERB_IMMUNE_POWDER_MIN = 5760
CD.VET_HERB_IMMUNE_BALANCING_MIN = 8640

-- Equilibrio geral: por tres dias de cao no mundo, doenca que passa sozinha e ferida andam 1,5x.
CD.VET_BALANCE_MIN = 4320
CD.VET_BALANCE_RATE = 1.5

-- A pinca tira os bichos na hora; eles voltam quando o prazo acaba, se o cao nao estiver protegido.
CD.VET_TWEEZERS_MIN = 360

-- Banho vet: produto, agua num recipiente e um pano. Nem a banheira nem o pente do MBF.
CD.VET_BATH_WATER_L = 1.0
CD.VET_BATH_TICKS = 330
CD.VET_OATMEAL_STRESS = 0.2
CD.VET_OATMEAL_STRESS_MIN = 0.1
CD.VET_BATH_CLOTHS = {
    ["Base.RippedSheets"] = true,
    ["Base.RippedSheetsDirty"] = true,
    ["Base.BathTowel"] = true,
    ["Base.DishCloth"] = true,
    ["Base.Sponge"] = true,
}
CD.VET_BATHS = {
    [CD.VET_ITEM_SHAMPOO] = {
        id = "shampoo", key = "vetinfestcured", infest = true,
        prevent = { field = "vetFleaPrevUntilMin", min = CD.VET_HERB_SHAMPOO_PREV_MIN },
    },
    [CD.VET_ITEM_OATMEAL] = {
        id = "oatmeal", key = "vetbathed", allergyCure = true,
        stress = { relief = CD.VET_OATMEAL_STRESS, min = CD.VET_OATMEAL_STRESS_MIN },
    },
}
CD.VET_BATH_ALIASES = {
    ["MansBestFriend.Med_FleaTickShampoo"] = CD.VET_ITEM_SHAMPOO,
    ["MansBestFriend.Med_SoothingOatmealBath"] = CD.VET_ITEM_OATMEAL,
}

-- Ajuda de ferida: fica no cao enquanto dura (`min` em minutos de jogo) e so vale no tipo de lesao
-- dela. A tala nao tem prazo: sai quando a fratura sara. O equilibrio geral vale para qualquer lesao.
CD.VET_AID_PLANTAIN = { field = "vetAidPlantain", item = CD.VET_ITEM_PLANTAIN, min = 1440, heal = 1.5, on = "cut" }
CD.VET_AID_ALOE = {
    field = "vetAidAloe", item = CD.VET_ITEM_ALOE, min = 1440, heal = 1.25, infect = 0.5, on = "cut",
}
CD.VET_AID_COMFREY = { field = "vetAidComfrey", item = CD.VET_ITEM_COMFREY, min = 1440, heal = 1.5, on = "bone" }
CD.VET_AID_SPLINT = { field = "vetSplint", item = CD.VET_ITEM_SPLINT, heal = 1.5, on = "fracture" }
CD.VET_AID_BALANCE = { field = "vetBalanceMin", heal = CD.VET_BALANCE_RATE, on = "any" }
CD.VET_AIDS = { CD.VET_AID_PLANTAIN, CD.VET_AID_ALOE, CD.VET_AID_COMFREY, CD.VET_AID_SPLINT, CD.VET_AID_BALANCE }

-- O que a aba Saude mostra como "Em uso": as ajudas de ferida e o equilibrio. O alho cura, entao aparece
-- como tratamento da infeccao; o alivio da febre vem com o curso do composto, tratamento da gripe.
CD.VET_AID_ROWS = {
    { field = "vetAidPlantain", item = CD.VET_ITEM_PLANTAIN, timed = true },
    { field = "vetAidAloe", item = CD.VET_ITEM_ALOE, timed = true },
    { field = "vetAidComfrey", item = CD.VET_ITEM_COMFREY, timed = true },
    { field = "vetSplint", item = CD.VET_ITEM_SPLINT },
    { field = "vetBalanceMin", item = CD.VET_ITEM_SYSTEMIC, timed = true },
}

-- Contam para baixo na passada do vet enquanto o cao esta no mundo.
CD.VET_AID_TIMERS = {
    "vetAidPlantain", "vetAidAloe", "vetAidComfrey", "vetFluReliefMin", "vetBalanceMin",
}

local ALG = { "vetAlgMin" }
local INFEST = { "vetFleas", "vetTicks" }

local M = CD.VET_MEDICINES
M[CD.VET_ITEM_ALLERGY_BLEND] = {
    id = "allergyblend", key = "vetmedicated",
    courses = { { field = "vetCourseAlg", min = CD.VET_HERB_ALG_BLEND_MIN, needs = ALG } },
    prevent = { field = "vetAlgPrevUntilMin", min = CD.VET_HERB_ALG_BLEND_PREV_MIN },
}
M[CD.VET_ITEM_ALLERGY_TEA] = {
    id = "allergytea", key = "vetmedicated",
    courses = { { field = "vetCourseAlg", min = CD.VET_HERB_ALG_TEA_MIN, needs = ALG } },
    prevent = { field = "vetAlgPrevUntilMin", min = CD.VET_HERB_ALG_TEA_PREV_MIN },
}
M[CD.VET_ITEM_SKIN_WASH] = {
    id = "skinwash", key = "vetmedicated",
    courses = { { field = "vetCourseAlg", min = CD.VET_HERB_SKIN_WASH_MIN, needs = ALG } },
    prevent = { field = "vetAlgPrevUntilMin", min = CD.VET_HERB_SKIN_WASH_PREV_MIN },
}
M[CD.VET_ITEM_INSECT_REPELLENT] = {
    id = "repellent", key = "vetmedicated", prophylactic = true,
    courses = { { field = "vetCourseFlea", min = CD.VET_HERB_REPELLENT_MIN, needs = INFEST } },
    prevent = { field = "vetFleaPrevUntilMin", min = CD.VET_HERB_REPELLENT_PREV_MIN },
}
M[CD.VET_ITEM_DETOX] = {
    id = "detox", key = "vetmedicated",
    courses = {
        { field = "vetCourseWorms", min = CD.VET_HERB_DETOX_WORMS_MIN, needs = { "vetWorms" }, unless = "vetDewormMin" },
        { field = "vetCourseHw", min = CD.VET_HERB_DETOX_HW_MIN, needs = { "vetHwMin" } },
    },
    cuts = { toxic = CD.VET_HERB_DETOX_TOXIC_CUT_MIN },
}
M[CD.VET_ITEM_PARASITE_TINCTURE] = {
    id = "parasitetincture", key = "vetmedicated", prophylactic = true,
    prevent = { field = "vetDewormPrevUntilMin", min = CD.VET_HERB_TINCTURE_PREV_MIN },
}
M[CD.VET_ITEM_RESP_HERBS] = {
    id = "respherbs", key = "vetmedicated",
    courses = { { field = "vetCourseFlu", min = CD.VET_HERB_RESP_MIN, needs = { "vetFluMin" } } },
    relief = { field = "vetFluReliefMin", min = CD.VET_HERB_RESP_MIN },
}
M[CD.VET_ITEM_CHAMOMILE] = {
    id = "chamomile", key = "vetmedicated",
    cuts = { gastro = CD.VET_HERB_CHAMOMILE_GASTRO_CUT_MIN },
    stress = { relief = CD.VET_HERB_CHAMOMILE_STRESS, min = CD.VET_HERB_CHAMOMILE_STRESS_MIN },
}
-- Imunidade de ervas nao entra em cao vacinado: a vacina ja cobre o mesmo e por mais tempo.
M[CD.VET_ITEM_IMMUNE_TINCTURE] = {
    id = "immunetincture", key = "vetmedicated", prophylactic = true,
    prevent = { field = "vetBoostUntilMin", min = CD.VET_HERB_IMMUNE_TINCTURE_MIN, covered = "vetImmuneUntilMin" },
}
M[CD.VET_ITEM_IMMUNE_POWDER] = {
    id = "immunepowder", key = "vetmedicated", prophylactic = true,
    prevent = { field = "vetBoostUntilMin", min = CD.VET_HERB_IMMUNE_POWDER_MIN, covered = "vetImmuneUntilMin" },
}
M[CD.VET_ITEM_IMMUNE_BALANCING] = {
    id = "immunebalancing", key = "vetmedicated", prophylactic = true,
    prevent = { field = "vetBoostUntilMin", min = CD.VET_HERB_IMMUNE_BALANCING_MIN, covered = "vetImmuneUntilMin" },
}
M[CD.VET_ITEM_SYSTEMIC] = {
    id = "systemic", key = "vetmedicated",
    balance = { field = "vetBalanceMin", min = CD.VET_BALANCE_MIN },
}
M[CD.VET_ITEM_ALOE] = { id = "aloe", key = "vetmedicated", aid = CD.VET_AID_ALOE }
M[CD.VET_ITEM_PLANTAIN] = { id = "plantain", key = "vetmedicated", aid = CD.VET_AID_PLANTAIN }
M[CD.VET_ITEM_COMFREY] = { id = "comfrey", key = "vetmedicated", aid = CD.VET_AID_COMFREY }
M[CD.VET_ITEM_SPLINT] = { id = "splint", key = "vetmedicated", aid = CD.VET_AID_SPLINT }
M[CD.VET_ITEM_GARLIC] = { id = "garlic", key = "vetmedicated" }
M[CD.VET_ITEM_TWEEZERS] = { id = "tweezers", key = "vettweezers", keep = true, menuKey = "IGUI_PD_VetTweezers" }

local A = CD.VET_MEDICINE_ALIASES
A["MansBestFriend.Med_DoggieAllergyBlend"] = CD.VET_ITEM_ALLERGY_BLEND
A["MansBestFriend.Med_AllergySupportTea"] = CD.VET_ITEM_ALLERGY_TEA
A["MansBestFriend.Med_SoothingSkinWash"] = CD.VET_ITEM_SKIN_WASH
A["MansBestFriend.Med_NaturalInsectRepellant"] = CD.VET_ITEM_INSECT_REPELLENT
A["MansBestFriend.Med_HerbalDetox"] = CD.VET_ITEM_DETOX
A["MansBestFriend.Med_HerbalParasitePreventionTincture"] = CD.VET_ITEM_PARASITE_TINCTURE
A["MansBestFriend.Med_HerbalRespiratorySupport"] = CD.VET_ITEM_RESP_HERBS
A["MansBestFriend.Med_RespiratorySupportSteam"] = CD.VET_ITEM_RESP_HERBS
A["MansBestFriend.Med_ChamomileTea"] = CD.VET_ITEM_CHAMOMILE
A["MansBestFriend.Med_ImmuneSupportTincture"] = CD.VET_ITEM_IMMUNE_TINCTURE
A["MansBestFriend.Med_ImmuneSupportPowder"] = CD.VET_ITEM_IMMUNE_POWDER
A["MansBestFriend.Med_ImmuneBalancingPowder"] = CD.VET_ITEM_IMMUNE_BALANCING
A["MansBestFriend.Med_SystemicBalanceTincture"] = CD.VET_ITEM_SYSTEMIC
A["MansBestFriend.Ingredient_AloeVera"] = CD.VET_ITEM_ALOE
A["Base.Tweezers_Forged"] = CD.VET_ITEM_TWEEZERS

-- O que a opcao de sandbox libera e a revista Home Vet ensina. Os emplastros do jogo ficam de fora da
-- liberacao: sao receita do vanilla, e so a revista os ensina junto.
CD.VET_RECIPES = {
    "MakeCompanionDogsAllergyBlend", "MakeCompanionDogsAllergyTea", "MakeCompanionDogsSkinWash",
    "MakeCompanionDogsInsectRepellent", "MakeCompanionDogsHerbalDetox", "MakeCompanionDogsParasiteTincture",
    "MakeCompanionDogsRespiratoryHerbs", "MakeCompanionDogsChamomileTea",
    "MakeCompanionDogsRoseGeraniumOil", "MakeCompanionDogsImmunePowder", "MakeCompanionDogsImmuneTincture",
    "MakeCompanionDogsTurkeyTailPowder", "MakeCompanionDogsAstragalusPowder",
    "MakeCompanionDogsImmuneBalancingPowder", "MakeCompanionDogsSystemicTincture", "MakeCompanionDogsOatmealBath",
    "MakeCompanionDogsAloeVeraJuice", "MakeCompanionDogsCalendulaTincture", "MakeCompanionDogsFleaTickShampoo",
}
