if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["pug"] = {}
AnimalDefinitions.stages["pug"].stages = {}
AnimalDefinitions.stages["pug"].stages["pugpup"] = {}
AnimalDefinitions.stages["pug"].stages["pugpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["pug"].stages["pugpup"].nextStage = "pugfemale"
AnimalDefinitions.stages["pug"].stages["pugpup"].nextStageMale = "pugmale"
AnimalDefinitions.stages["pug"].stages["pugmale"] = {}
AnimalDefinitions.stages["pug"].stages["pugmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["pug"].stages["pugfemale"] = {}
AnimalDefinitions.stages["pug"].stages["pugfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["pug"] = {}
AnimalDefinitions.breeds["pug"].breeds = {}
AnimalDefinitions.breeds["pug"].breeds["pug"] = {}
AnimalDefinitions.breeds["pug"].breeds["pug"].name = "pug"
AnimalDefinitions.breeds["pug"].breeds["pug"].texture = "Pug"
AnimalDefinitions.breeds["pug"].breeds["pug"].textureMale = "Pug"
AnimalDefinitions.breeds["pug"].breeds["pug"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["pug"].breeds["pug"].invIconBabySkel = "Item_Skeleton_Raccoon"

local pugpup = {}
CD.applyDogModel(pugpup, "Pug_Body")
CD.applyDogBehaviour(pugpup)
pugpup.shadoww = 0.2
pugpup.shadowfm = 0.2
pugpup.shadowbm = 0.2
pugpup.minSize = 1.05
pugpup.maxSize = 1.55
pugpup.wanderMul = 500
pugpup.hungerMultiplier = 0.001
pugpup.thirstMultiplier = 0.002
pugpup.hungerBoost = 25
pugpup.thirstBoost = 30
pugpup.baseEncumbrance = 6
pugpup.trailerBaseSize = 20
pugpup.minEnclosureSize = 30
pugpup.needMom = false
pugpup.eatFromMother = true
pugpup.litterEatTogether = true
pugpup.minWeight = 1
pugpup.maxWeight = 4
pugpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
pugpup.breeds = AnimalDefinitions.breeds["pug"].breeds
pugpup.stages = AnimalDefinitions.stages["pug"].stages
pugpup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["pugpup"] = pugpup

local pugfemale = {}
CD.applyDogModel(pugfemale, "Pug_Body")
CD.applyDogBehaviour(pugfemale)
pugfemale.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
pugfemale.babyType = "pugpup"
pugfemale.shadoww = 0.3
pugfemale.shadowfm = 0.4
pugfemale.shadowbm = 0.4
pugfemale.minSize = 1.5
pugfemale.maxSize = 2.0
pugfemale.wanderMul = 600
pugfemale.hungerMultiplier = 0.004
pugfemale.thirstMultiplier = 0.010
pugfemale.hungerBoost = 20
pugfemale.thirstBoost = 25
pugfemale.baseEncumbrance = 10
pugfemale.trailerBaseSize = 25
pugfemale.minEnclosureSize = 30
pugfemale.minAge = 3 * 30
pugfemale.maxAgeGeriatric = 15 * 30
pugfemale.minAgeForBaby = 3 * 30
pugfemale.timeBeforeNextPregnancy = 7
pugfemale.pregnantPeriod = 35
pugfemale.minWeight = 5
pugfemale.maxWeight = 8
pugfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
pugfemale.breeds = AnimalDefinitions.breeds["pug"].breeds
pugfemale.stages = AnimalDefinitions.stages["pug"].stages
pugfemale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["pugfemale"] = pugfemale

local pugmale = {}
CD.applyDogModel(pugmale, "Pug_Body")
CD.applyDogBehaviour(pugmale)
pugmale.male = true
pugmale.babyType = "pugpup"
pugmale.dontAttackOtherMale = true
pugmale.shadoww = 0.3
pugmale.shadowfm = 0.4
pugmale.shadowbm = 0.4
pugmale.minSize = 1.5
pugmale.maxSize = 2.15
pugmale.wanderMul = 600
pugmale.hungerMultiplier = 0.004
pugmale.thirstMultiplier = 0.010
pugmale.hungerBoost = 20
pugmale.thirstBoost = 25
pugmale.baseEncumbrance = 10
pugmale.trailerBaseSize = 25
pugmale.minEnclosureSize = 30
pugmale.minAge = 3 * 30
pugmale.maxAgeGeriatric = 15 * 30
pugmale.minAgeForBaby = 3 * 30
pugmale.minWeight = 6
pugmale.maxWeight = 9
pugmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
pugmale.breeds = AnimalDefinitions.breeds["pug"].breeds
pugmale.stages = AnimalDefinitions.stages["pug"].stages
pugmale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["pugmale"] = pugmale

AnimalDefinitions.animals["pugpup"].breeds["pug"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["pugfemale"].breeds["pug"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["pugmale"].breeds["pug"].sounds = CD.DOG_SOUNDS

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["pugpup"] = {}
AnimalAvatarDefinition["pugfemale"] = {}
AnimalAvatarDefinition["pugmale"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition["pugpup"])
CD.applyDogAvatar(AnimalAvatarDefinition["pugfemale"])
CD.applyDogAvatar(AnimalAvatarDefinition["pugmale"])

local SIZE_RATIO = 0.5797
for _, t in ipairs({ AnimalAvatarDefinition["pugpup"], AnimalAvatarDefinition["pugfemale"],
                     AnimalAvatarDefinition["pugmale"] }) do
    t.zoom = t.zoom / SIZE_RATIO
    t.xoffset = t.xoffset * SIZE_RATIO
    t.yoffset = t.yoffset * SIZE_RATIO
    t.trailerZoom = t.trailerZoom / SIZE_RATIO
    t.trailerXoffset = t.trailerXoffset * SIZE_RATIO
    t.trailerYoffset = t.trailerYoffset * SIZE_RATIO
end
