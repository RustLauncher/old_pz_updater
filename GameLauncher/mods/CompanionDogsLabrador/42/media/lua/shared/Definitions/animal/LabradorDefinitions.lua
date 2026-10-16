if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["lab"] = {}
AnimalDefinitions.stages["lab"].stages = {}
AnimalDefinitions.stages["lab"].stages["labpup"] = {}
AnimalDefinitions.stages["lab"].stages["labpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["lab"].stages["labpup"].nextStage = "labfemale"
AnimalDefinitions.stages["lab"].stages["labpup"].nextStageMale = "labmale"
AnimalDefinitions.stages["lab"].stages["labmale"] = {}
AnimalDefinitions.stages["lab"].stages["labmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["lab"].stages["labfemale"] = {}
AnimalDefinitions.stages["lab"].stages["labfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["lab"] = {}
AnimalDefinitions.breeds["lab"].breeds = {}
AnimalDefinitions.breeds["lab"].breeds["labrador"] = {}
AnimalDefinitions.breeds["lab"].breeds["labrador"].name = "labrador"
AnimalDefinitions.breeds["lab"].breeds["labrador"].texture = "Labrador"
AnimalDefinitions.breeds["lab"].breeds["labrador"].textureMale = "Labrador"
AnimalDefinitions.breeds["lab"].breeds["labrador"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["lab"].breeds["labrador"].invIconBabySkel = "Item_Skeleton_Raccoon"

local labpup = {}
CD.applyDogModel(labpup, "Labrador_Body")
CD.applyDogBehaviour(labpup)
labpup.shadoww = 0.2
labpup.shadowfm = 0.2
labpup.shadowbm = 0.2
labpup.minSize = 1.05
labpup.maxSize = 1.55
labpup.wanderMul = 500
labpup.hungerMultiplier = 0.001
labpup.thirstMultiplier = 0.002
labpup.hungerBoost = 25
labpup.thirstBoost = 30
labpup.baseEncumbrance = 10
labpup.trailerBaseSize = 30
labpup.minEnclosureSize = 40
labpup.needMom = false
labpup.eatFromMother = true
labpup.litterEatTogether = true
labpup.minWeight = 1
labpup.maxWeight = 8
labpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
labpup.breeds = AnimalDefinitions.breeds["lab"].breeds
labpup.stages = AnimalDefinitions.stages["lab"].stages
labpup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["labpup"] = labpup

local labfemale = {}
CD.applyDogModel(labfemale, "Labrador_Body")
CD.applyDogBehaviour(labfemale)
labfemale.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
labfemale.babyType = "labpup"
labfemale.shadoww = 0.3
labfemale.shadowfm = 0.5
labfemale.shadowbm = 0.5
labfemale.minSize = 1.5
labfemale.maxSize = 2.0
labfemale.wanderMul = 600
labfemale.hungerMultiplier = 0.008
labfemale.thirstMultiplier = 0.016
labfemale.hungerBoost = 20
labfemale.thirstBoost = 25
labfemale.baseEncumbrance = 20
labfemale.trailerBaseSize = 50
labfemale.minEnclosureSize = 40
labfemale.minAge = 3 * 30
labfemale.maxAgeGeriatric = 19 * 30
labfemale.minAgeForBaby = 3 * 30
labfemale.timeBeforeNextPregnancy = 7
labfemale.pregnantPeriod = 35
labfemale.minWeight = 9
labfemale.maxWeight = 16
labfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
labfemale.breeds = AnimalDefinitions.breeds["lab"].breeds
labfemale.stages = AnimalDefinitions.stages["lab"].stages
labfemale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["labfemale"] = labfemale

local labmale = {}
CD.applyDogModel(labmale, "Labrador_Body")
CD.applyDogBehaviour(labmale)
labmale.male = true
labmale.babyType = "labpup"
labmale.dontAttackOtherMale = true
labmale.shadoww = 0.3
labmale.shadowfm = 0.5
labmale.shadowbm = 0.5
labmale.minSize = 1.5
labmale.maxSize = 2.15
labmale.wanderMul = 600
labmale.hungerMultiplier = 0.008
labmale.thirstMultiplier = 0.016
labmale.hungerBoost = 20
labmale.thirstBoost = 25
labmale.baseEncumbrance = 20
labmale.trailerBaseSize = 50
labmale.minEnclosureSize = 40
labmale.minAge = 3 * 30
labmale.maxAgeGeriatric = 19 * 30
labmale.minAgeForBaby = 3 * 30
labmale.minWeight = 10
labmale.maxWeight = 18
labmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
labmale.breeds = AnimalDefinitions.breeds["lab"].breeds
labmale.stages = AnimalDefinitions.stages["lab"].stages
labmale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["labmale"] = labmale

AnimalDefinitions.animals["labpup"].breeds["labrador"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["labfemale"].breeds["labrador"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["labmale"].breeds["labrador"].sounds = CD.DOG_SOUNDS

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["labpup"] = {}
AnimalAvatarDefinition["labfemale"] = {}
AnimalAvatarDefinition["labmale"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition["labpup"])
CD.applyDogAvatar(AnimalAvatarDefinition["labfemale"])
CD.applyDogAvatar(AnimalAvatarDefinition["labmale"])
