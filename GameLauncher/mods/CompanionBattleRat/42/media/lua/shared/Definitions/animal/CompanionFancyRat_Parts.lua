if CompanionDogs and CompanionDogs.defineDogParts then
    local defineParts = CompanionDogs.defineCompanionParts or CompanionDogs.defineDogParts
    local frMeat = { item = "Base.Smallanimalmeat", minNb = 1, maxNb = 2, pupMinNb = 1, pupMaxNb = 1 }
    for _, engineBreed in ipairs({ "fr_white", "fr_grey", "fr_hooded", "fr_naked", "fr_brown", "fr_blue" }) do
        defineParts("fr", engineBreed, frMeat)
    end
end
