require "Items/ProceduralDistributions"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local BOWL = "CompanionDogsBowl"
local SADDLEBAG = "CompanionDogsSaddlebag"

local BOWL_TARGETS = {
    PetShopShelf = 18,
    CratePetSupplies = 14,
    GigamartHousewares = 8,
    GroceryStorageCrate1 = 4,
    GroceryStorageCrate2 = 4,
    GroceryStorageCrate3 = 4,
    GardenStoreMisc = 8,
    CrateFarming = 6,
    CrateGardening = 6,
    KitchenRandom = 2,
}

local SADDLEBAG_TARGETS = {
    PetShopShelf = 8,
    CratePetSupplies = 8,
    CampingStoreBackpacks = 8,
    CampingStoreGear = 6,
    CrateCamping = 6,
    HuntingLockers = 6,
    SurvivalGear = 6,
    GarageTools = 3,
    CrateFarming = 3,
}

-- Onde o jogador procura remedio de bicho: farmacia e posto, o armario do banheiro de casa, a
-- prateleira do pet shop e o galpao da fazenda.
local MED_TARGETS = {
    MedicalCabinet = 3,
    MedicalStorageDrugs = 4,
    MedicalClinicDrugs = 4,
    MedicalStorageTools = 2,
    MedicalClinicTools = 2,
    StoreShelfMedical = 4,
    ArmyStorageMedical = 2,
    PetShopShelf = 6,
    CratePetSupplies = 5,
    BathroomCabinet = 2,
    BathroomCounter = 1,
    GarageTools = 2,
    FarmerTools = 3,
    BarnTools = 3,
    CrateFarming = 2,
}

-- Quao comum e cada remedio dentro desses moveis. A vacina quase so aparece na clinica veterinaria,
-- que e o quarto de baixo.
local MEDICINES = {
    { item = "CompanionDogsAntibiotic", scale = 1.0 },
    { item = "CompanionDogsDewormer", scale = 1.0 },
    { item = "CompanionDogsAntihistamine", scale = 1.3 },
    { item = "CompanionDogsFleaTickMedicine", scale = 1.3 },
    { item = "CompanionDogsHeartwormMedicine", scale = 0.8 },
    { item = "CompanionDogsVaccine", scale = 0.6 },
}

-- A vacina so existe na clinica veterinaria: os balcoes da sala kennels do vanilla.
local VACCINE_ROOM = "kennels"
local VACCINE_CONTAINERS = { desk = 8, doghouse = 4 }

-- Remedio caseiro e insumo de ervas. Peso cru, sem o arredondamento dos remedios de farmacia: a revista
-- precisa de 0,1 na sala de estar, igual a revista de ervas do jogo.
local HERBAL_LOOT = {
    { item = "CompanionDogsFleaTickShampoo", targets = {
        PetShopShelf = 6, CratePetSupplies = 4, GigamartToiletries = 2, GasStoreToiletries = 1, BathroomCabinet = 1,
    } },
    { item = "CompanionDogsAloeVeraJuice", targets = {
        GigamartToiletries = 2, StoreShelfMedical = 2, KitchenBottles = 1, BathroomCabinet = 1,
    } },
    { item = "CompanionDogsCalendulaTincture", targets = {
        StoreShelfMedical = 2, Homesteading = 2, MedicalClinicDrugs = 1, BathroomCabinet = 1,
    } },
    { item = "CompanionDogsHomeVet", targets = {
        PetShopShelf = 2, BookstoreMisc = 2, MagazineRackMixed = 1, CrateMagazines = 1, LibraryMagazines = 1,
        PostOfficeMagazines = 1, LivingRoomShelf = 0.1, LivingRoomSideTable = 0.1,
    } },
}

-- As ervas saem onde o jogo guarda tempero e verdura: mercado, armario de cozinha, garagem, deposito.
local HERBS = {
    "CompanionDogsAloeVera", "CompanionDogsLicoriceRoot", "CompanionDogsEyebright", "CompanionDogsRedClover",
    "CompanionDogsRoseGeranium", "CompanionDogsOregonGrapeRoot", "CompanionDogsBlackWalnutHull",
    "CompanionDogsWormwood", "CompanionDogsMullein", "CompanionDogsEucalyptus", "CompanionDogsAstragalus",
    "CompanionDogsEchinacea", "CompanionDogsElderberry", "CompanionDogsTurkeyTail",
}
local HERB_TARGETS = {
    GigamartSpices = 1, Homesteading = 0.5, GroceryStorageCrate1 = 0.5, CrateFarming = 0.5, KitchenDryFood = 0.3,
}
local GARDEN_HERBS = { "CompanionDogsAloeVera", "CompanionDogsRoseGeranium", "CompanionDogsEucalyptus" }
local GARDEN_TARGETS = { CrateGardening = 2 }
local ALOE_TARGETS = { GroceryStandVegetables1 = 2, FridgeGeneric = 0.5 }

local injected = false

local function injectInto(list, item, targets)
    for name, weight in pairs(targets) do
        local t = list[name]
        if t and t.items then
            table.insert(t.items, item)
            table.insert(t.items, weight)
        end
    end
end

local function injectRoom(item, room, containers)
    local r = SuburbsDistributions[room]
    if not r then return end
    for name, weight in pairs(containers) do
        local c = r[name]
        if c and c.items then
            table.insert(c.items, item)
            table.insert(c.items, weight)
        end
    end
end

local function injectMedicines(list)
    for i = 1, #MEDICINES do
        local med = MEDICINES[i]
        for name, weight in pairs(MED_TARGETS) do
            local t = list[name]
            if t and t.items then
                table.insert(t.items, med.item)
                table.insert(t.items, math.max(1, math.ceil(weight * med.scale)))
            end
        end
    end
end

local function injectLoot()
    if injected then return end
    injected = true
    local list = ProceduralDistributions.list
    injectInto(list, BOWL, BOWL_TARGETS)
    injectInto(list, SADDLEBAG, SADDLEBAG_TARGETS)
    -- Remedio so entra no loot se o cuidado veterinario estiver ligado. Com ele desligado nada usa
    -- esses itens, e sem o gate eles ocupariam vaga em quinze moveis para sempre. A tigela e o
    -- alforje ficam de fora do gate: servem com o vetcare desligado.
    if not CD.vetCareEnabled() then return end
    injectMedicines(list)
    injectRoom("CompanionDogsVaccine", VACCINE_ROOM, VACCINE_CONTAINERS)
    injectRoom("CompanionDogsHeartwormMedicine", VACCINE_ROOM, VACCINE_CONTAINERS)
    for i = 1, #HERBAL_LOOT do
        injectInto(list, HERBAL_LOOT[i].item, HERBAL_LOOT[i].targets)
    end
    for i = 1, #HERBS do
        injectInto(list, HERBS[i], HERB_TARGETS)
    end
    for i = 1, #GARDEN_HERBS do
        injectInto(list, GARDEN_HERBS[i], GARDEN_TARGETS)
    end
    injectInto(list, "CompanionDogsAloeVera", ALOE_TARGETS)
    injectRoom("CompanionDogsHomeVet", VACCINE_ROOM, { desk = 2 })
end

Events.OnPreDistributionMerge.Add(injectLoot)
