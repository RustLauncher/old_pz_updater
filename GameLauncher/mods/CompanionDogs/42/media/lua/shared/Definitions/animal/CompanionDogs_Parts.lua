-- Sem entrada em AnimalPartsDefinitions o abate vanilla estoura em def.feather nil.
-- A engine multiplica minNb/maxNb e a fome de cada peca pelo animalSize da carcaca, e os caes
-- do mod usam size acima de 1 como escala visual: por isso as contagens aqui sao baixas.
local dogMeat = { item = "Base.CompanionDogsDogMeat", minNb = 2, maxNb = 4, pupMinNb = 1, pupMaxNb = 2 }

local function defineStage(key, parts, boneMin, boneMax)
    local d = AnimalPartsDefinitions.animals[key] or {}
    d.parts = d.parts or parts
    d.bones = d.bones or {}
    table.insert(d.bones, { item = "Base.SmallAnimalBone", minNb = boneMin, maxNb = boneMax })
    d.noSkeleton = true
    d.xpPerItem = 10
    AnimalPartsDefinitions.animals[key] = d
end

CompanionDogs = CompanionDogs or {}
---@param typePrefix string prefix of the three animal types (dog, gs, husky...)
---@param engineBreed string engine breed name (brown, germanshepherd...)
---@param meat table|nil { item, minNb, maxNb, pupMinNb, pupMaxNb }; defaults to dog meat
function CompanionDogs.defineDogParts(typePrefix, engineBreed, meat)
    meat = meat or dogMeat
    local adultParts = { { item = meat.item, minNb = meat.minNb, maxNb = meat.maxNb } }
    local pupParts = { { item = meat.item, minNb = meat.pupMinNb, maxNb = meat.pupMaxNb } }
    defineStage(typePrefix .. "male" .. engineBreed, adultParts, 1, 2)
    defineStage(typePrefix .. "female" .. engineBreed, adultParts, 1, 2)
    defineStage(typePrefix .. "pup" .. engineBreed, pupParts, 1, 1)
end
CompanionDogs.defineCompanionParts = CompanionDogs.defineDogParts

CompanionDogs.defineDogParts("dog", "brown")
CompanionDogs.defineDogParts("gs", "germanshepherd")
CompanionDogs.defineDogParts("retriever", "golden")
CompanionDogs.defineDogParts("husky", "husky")
CompanionDogs.defineDogParts("bc", "bordercollie")
