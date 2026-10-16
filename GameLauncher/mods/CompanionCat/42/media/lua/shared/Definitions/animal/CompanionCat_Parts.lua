-- Sem entrada em AnimalPartsDefinitions o abate vanilla estoura em def.feather nil, e a chave
-- do abate carrega a pelagem: uma chamada por pelagem, senao a pelagem de fora estoura.
-- A carne propria vai no terceiro argumento; um base anterior a ele ignora e cai na carne de cao.
if CompanionDogs and CompanionDogs.defineDogParts then
    local defineParts = CompanionDogs.defineCompanionParts or CompanionDogs.defineDogParts
    local catMeat = { item = "Base.CompanionCatCatMeat", minNb = 1, maxNb = 2, pupMinNb = 1, pupMaxNb = 1 }
    local coats = AnimalDefinitions.breeds["cat"] and AnimalDefinitions.breeds["cat"].breeds
    if coats then
        for name, _ in pairs(coats) do
            defineParts("cat", name, catMeat)
        end
    else
        for _, name in ipairs({ "cat", "cat_white", "cat_orange", "cat_calico", "cat_tuxedo",
                                "cat_brown_tabby", "cat_grey_tabby", "cat_orange_tabby",
                                "cat_barley", "cat_cow", "cat_tortie" }) do
            defineParts("cat", name, catMeat)
        end
    end
end
