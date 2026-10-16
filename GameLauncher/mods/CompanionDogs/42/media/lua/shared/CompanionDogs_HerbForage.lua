require "Foraging/forageSystem"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- As ervas dos remedios caseiros entram no forrageio do jogo, nas categorias que ja existem, com peso
-- baixo para nao espremer as ervas do vanilla. O registro e no preAddItemDefs, que ja roda com o sandbox
-- do save carregado: com o vetcare desligado nenhuma erva vai para o mato.
local HERBS = {
    CompanionDogsLicoriceRoot = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 4, FarmLand = 4, Forest = 1 },
        months = { 8, 9, 10, 11 },
        bonusMonths = { 9, 10 },
    },
    CompanionDogsEyebright = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 4, FarmLand = 3, Forest = 2 },
        months = { 6, 7, 8, 9 },
    },
    CompanionDogsRedClover = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 5, FarmLand = 5 },
        months = { 5, 6, 7, 8, 9 },
    },
    CompanionDogsOregonGrapeRoot = {
        categories = { "MedicinalPlants" },
        zones = { Forest = 3, DeepForest = 4, PHForest = 3 },
    },
    CompanionDogsBlackWalnutHull = {
        categories = { "MedicinalPlants" },
        zones = { Forest = 4, DeepForest = 3, OrganicForest = 4 },
        months = { 9, 10, 11 },
    },
    CompanionDogsWormwood = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 4, FarmLand = 3 },
        months = { 7, 8, 9 },
    },
    CompanionDogsMullein = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 5, FarmLand = 4, Forest = 2 },
        months = { 5, 6, 7, 8, 9, 10 },
    },
    CompanionDogsAstragalus = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 3, FarmLand = 3 },
        months = { 8, 9, 10, 11 },
        bonusMonths = { 9, 10 },
    },
    CompanionDogsEchinacea = {
        categories = { "MedicinalPlants" },
        zones = { Vegitation = 4, FarmLand = 3, Forest = 2 },
        months = { 6, 7, 8, 9 },
    },
    CompanionDogsElderberry = {
        categories = { "Berries" },
        zones = { Forest = 3, Vegitation = 3, FarmLand = 2 },
        months = { 8, 9 },
    },
    CompanionDogsTurkeyTail = {
        categories = { "Mushrooms" },
        zones = { Forest = 3, DeepForest = 4, OrganicForest = 3, BirchForest = 3 },
        bonusMonths = { 9, 10, 11 },
    },
    CompanionDogsAloeVera = {
        categories = { "WildPlants" },
        zones = { TownZone = 3, TrailerPark = 3 },
    },
    CompanionDogsRoseGeranium = {
        categories = { "WildPlants" },
        zones = { TownZone = 3, TrailerPark = 2, FarmLand = 1 },
        months = { 5, 6, 7, 8, 9 },
    },
    CompanionDogsEucalyptus = {
        categories = { "WildPlants" },
        zones = { TownZone = 2, TrailerPark = 2 },
    },
}

-- Categoria so de foco da busca, como a Tracks do jogo: peso zero em todo terreno, entao nao muda
-- quanto nasce de erva. O sorteio de categoria multiplica o peso do terreno sem checar nil, por isso os
-- onze terrenos base vao explicitos; os mistos o jogo deriva deles.
local FOCUS_CATEGORY = "CompanionDogsHerbs"

local function addHerbFocusCategory()
    if not CD.vetCareEnabled() then return end
    forageSystem.addCatDef({
        name = FOCUS_CATEGORY,
        typeCategory = "Medicinal",
        identifyCategoryPerk = "PlantScavenging",
        identifyCategoryLevel = 0,
        categoryHidden = false,
        validFloors = { "ANY" },
        zones = {
            BirchForest = 0, DeepForest = 0, FarmLand = 0, ForagingNav = 0, Forest = 0, OrganicForest = 0,
            PHForest = 0, PRForest = 0, TownZone = 0, TrailerPark = 0, Vegitation = 0,
        },
        focusChanceMin = 10.0,
        focusChanceMax = 33.3,
    })
end

local function addHerbForageDefs()
    if not CD.vetCareEnabled() then return end
    for name, herb in pairs(HERBS) do
        -- A primeira categoria e a que o client le como principal do item: a natural fica na frente.
        local categories = {}
        for i = 1, #herb.categories do
            categories[i] = herb.categories[i]
        end
        categories[#categories + 1] = FOCUS_CATEGORY
        forageSystem.addForageDef(name, {
            type = "Base." .. name,
            minCount = 1,
            maxCount = 3,
            xp = 5,
            categories = categories,
            zones = herb.zones,
            months = herb.months,
            bonusMonths = herb.bonusMonths,
            altWorldTexture = forageSystem.worldSprites.wildPlants,
            itemSizeModifier = 1.0,
            isItemOverrideSize = true,
        })
    end
end

Events.preAddCatDefs.Add(addHerbFocusCategory)
Events.preAddItemDefs.Add(addHerbForageDefs)
