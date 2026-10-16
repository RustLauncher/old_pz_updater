if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["rott"] = {}
AnimalDefinitions.stages["rott"].stages = {}
AnimalDefinitions.stages["rott"].stages["rottpup"] = {}
AnimalDefinitions.stages["rott"].stages["rottpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["rott"].stages["rottpup"].nextStage = "rottfemale"
AnimalDefinitions.stages["rott"].stages["rottpup"].nextStageMale = "rottmale"
AnimalDefinitions.stages["rott"].stages["rottmale"] = {}
AnimalDefinitions.stages["rott"].stages["rottmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["rott"].stages["rottfemale"] = {}
AnimalDefinitions.stages["rott"].stages["rottfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["rott"] = {}
AnimalDefinitions.breeds["rott"].breeds = {}
AnimalDefinitions.breeds["rott"].breeds["rottweiler"] = {}
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].name = "rottweiler"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].texture = "Rottweiler"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].textureMale = "Rottweiler"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["rott"].breeds["rottweiler"].invIconBabySkel = "Item_Skeleton_Raccoon"

local rottpup = {}
CD.applyDogModel(rottpup, "Rottweiler_Body")
CD.applyDogBehaviour(rottpup)
rottpup.shadoww = 0.2
rottpup.shadowfm = 0.2
rottpup.shadowbm = 0.2
rottpup.minSize = 0.957
rottpup.maxSize = 1.436
rottpup.wanderMul = 500
rottpup.hungerMultiplier = 0.001
rottpup.thirstMultiplier = 0.002
rottpup.hungerBoost = 25
rottpup.thirstBoost = 30
rottpup.baseEncumbrance = 10
rottpup.trailerBaseSize = 30
rottpup.minEnclosureSize = 40
rottpup.needMom = false
rottpup.eatFromMother = true
rottpup.litterEatTogether = true
rottpup.minWeight = 1
rottpup.maxWeight = 8
rottpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
rottpup.breeds = AnimalDefinitions.breeds["rott"].breeds
rottpup.stages = AnimalDefinitions.stages["rott"].stages
rottpup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["rottpup"] = rottpup

local rottfemale = {}
CD.applyDogModel(rottfemale, "Rottweiler_Body")
CD.applyDogBehaviour(rottfemale)
rottfemale.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
rottfemale.babyType = "rottpup"
rottfemale.shadoww = 0.3
rottfemale.shadowfm = 0.5
rottfemale.shadowbm = 0.5
rottfemale.minSize = 1.436
rottfemale.maxSize = 1.915
rottfemale.wanderMul = 600
rottfemale.hungerMultiplier = 0.008
rottfemale.thirstMultiplier = 0.016
rottfemale.hungerBoost = 20
rottfemale.thirstBoost = 25
rottfemale.baseEncumbrance = 20
rottfemale.trailerBaseSize = 50
rottfemale.minEnclosureSize = 40
rottfemale.minAge = 3 * 30
rottfemale.maxAgeGeriatric = 19 * 30
rottfemale.minAgeForBaby = 3 * 30
rottfemale.timeBeforeNextPregnancy = 7
rottfemale.pregnantPeriod = 35
rottfemale.minWeight = 9
rottfemale.maxWeight = 16
rottfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
rottfemale.breeds = AnimalDefinitions.breeds["rott"].breeds
rottfemale.stages = AnimalDefinitions.stages["rott"].stages
rottfemale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["rottfemale"] = rottfemale

local rottmale = {}
CD.applyDogModel(rottmale, "Rottweiler_Body")
CD.applyDogBehaviour(rottmale)
rottmale.male = true
rottmale.babyType = "rottpup"
rottmale.dontAttackOtherMale = true
rottmale.shadoww = 0.3
rottmale.shadowfm = 0.5
rottmale.shadowbm = 0.5
rottmale.minSize = 1.436
rottmale.maxSize = 2.077
rottmale.wanderMul = 600
rottmale.hungerMultiplier = 0.008
rottmale.thirstMultiplier = 0.016
rottmale.hungerBoost = 20
rottmale.thirstBoost = 25
rottmale.baseEncumbrance = 20
rottmale.trailerBaseSize = 50
rottmale.minEnclosureSize = 40
rottmale.minAge = 3 * 30
rottmale.maxAgeGeriatric = 19 * 30
rottmale.minAgeForBaby = 3 * 30
rottmale.minWeight = 10
rottmale.maxWeight = 18
rottmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
rottmale.breeds = AnimalDefinitions.breeds["rott"].breeds
rottmale.stages = AnimalDefinitions.stages["rott"].stages
rottmale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["rottmale"] = rottmale

AnimalDefinitions.animals["rottpup"].breeds["rottweiler"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["rottfemale"].breeds["rottweiler"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["rottmale"].breeds["rottweiler"].sounds = CD.DOG_SOUNDS

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["rottpup"] = {}
AnimalAvatarDefinition["rottfemale"] = {}
AnimalAvatarDefinition["rottmale"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition["rottpup"])
CD.applyDogAvatar(AnimalAvatarDefinition["rottfemale"])
CD.applyDogAvatar(AnimalAvatarDefinition["rottmale"])
