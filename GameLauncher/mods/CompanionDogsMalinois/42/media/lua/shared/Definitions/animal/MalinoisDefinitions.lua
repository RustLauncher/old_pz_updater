if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["mal"] = {}
AnimalDefinitions.stages["mal"].stages = {}
AnimalDefinitions.stages["mal"].stages["malpup"] = {}
AnimalDefinitions.stages["mal"].stages["malpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["mal"].stages["malpup"].nextStage = "malfemale"
AnimalDefinitions.stages["mal"].stages["malpup"].nextStageMale = "malmale"
AnimalDefinitions.stages["mal"].stages["malmale"] = {}
AnimalDefinitions.stages["mal"].stages["malmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["mal"].stages["malfemale"] = {}
AnimalDefinitions.stages["mal"].stages["malfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["mal"] = {}
AnimalDefinitions.breeds["mal"].breeds = {}
AnimalDefinitions.breeds["mal"].breeds["malinois"] = {}
AnimalDefinitions.breeds["mal"].breeds["malinois"].name = "malinois"
AnimalDefinitions.breeds["mal"].breeds["malinois"].texture = "Malinois"
AnimalDefinitions.breeds["mal"].breeds["malinois"].textureMale = "Malinois"
AnimalDefinitions.breeds["mal"].breeds["malinois"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["mal"].breeds["malinois"].invIconBabySkel = "Item_Skeleton_Raccoon"

local malpup = {}
CD.applyDogModel(malpup, "Malinois_Body")
CD.applyDogBehaviour(malpup)
malpup.shadoww = 0.2
malpup.shadowfm = 0.2
malpup.shadowbm = 0.2
malpup.minSize = 1.12
malpup.maxSize = 1.68
malpup.wanderMul = 500
malpup.hungerMultiplier = 0.001
malpup.thirstMultiplier = 0.002
malpup.hungerBoost = 25
malpup.thirstBoost = 30
malpup.baseEncumbrance = 10
malpup.trailerBaseSize = 30
malpup.minEnclosureSize = 40
malpup.needMom = false
malpup.eatFromMother = true
malpup.litterEatTogether = true
malpup.minWeight = 1
malpup.maxWeight = 8
malpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
malpup.breeds = AnimalDefinitions.breeds["mal"].breeds
malpup.stages = AnimalDefinitions.stages["mal"].stages
malpup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["malpup"] = malpup

local malfemale = {}
CD.applyDogModel(malfemale, "Malinois_Body")
CD.applyDogBehaviour(malfemale)
malfemale.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
malfemale.babyType = "malpup"
malfemale.shadoww = 0.3
malfemale.shadowfm = 0.5
malfemale.shadowbm = 0.5
malfemale.minSize = 1.68
malfemale.maxSize = 2.24
malfemale.wanderMul = 600
malfemale.hungerMultiplier = 0.008
malfemale.thirstMultiplier = 0.016
malfemale.hungerBoost = 20
malfemale.thirstBoost = 25
malfemale.baseEncumbrance = 20
malfemale.trailerBaseSize = 50
malfemale.minEnclosureSize = 40
malfemale.minAge = 3 * 30
malfemale.maxAgeGeriatric = 19 * 30
malfemale.minAgeForBaby = 3 * 30
malfemale.timeBeforeNextPregnancy = 7
malfemale.pregnantPeriod = 35
malfemale.minWeight = 9
malfemale.maxWeight = 16
malfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
malfemale.breeds = AnimalDefinitions.breeds["mal"].breeds
malfemale.stages = AnimalDefinitions.stages["mal"].stages
malfemale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["malfemale"] = malfemale

local malmale = {}
CD.applyDogModel(malmale, "Malinois_Body")
CD.applyDogBehaviour(malmale)
malmale.male = true
malmale.babyType = "malpup"
malmale.dontAttackOtherMale = true
malmale.shadoww = 0.3
malmale.shadowfm = 0.5
malmale.shadowbm = 0.5
malmale.minSize = 1.68
malmale.maxSize = 2.43
malmale.wanderMul = 600
malmale.hungerMultiplier = 0.008
malmale.thirstMultiplier = 0.016
malmale.hungerBoost = 20
malmale.thirstBoost = 25
malmale.baseEncumbrance = 20
malmale.trailerBaseSize = 50
malmale.minEnclosureSize = 40
malmale.minAge = 3 * 30
malmale.maxAgeGeriatric = 19 * 30
malmale.minAgeForBaby = 3 * 30
malmale.minWeight = 10
malmale.maxWeight = 18
malmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
malmale.breeds = AnimalDefinitions.breeds["mal"].breeds
malmale.stages = AnimalDefinitions.stages["mal"].stages
malmale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["malmale"] = malmale

AnimalDefinitions.animals["malpup"].breeds["malinois"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["malfemale"].breeds["malinois"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["malmale"].breeds["malinois"].sounds = CD.DOG_SOUNDS

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["malpup"] = {}
AnimalAvatarDefinition["malfemale"] = {}
AnimalAvatarDefinition["malmale"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition["malpup"])
CD.applyDogAvatar(AnimalAvatarDefinition["malfemale"])
CD.applyDogAvatar(AnimalAvatarDefinition["malmale"])
