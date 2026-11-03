if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["dob"] = {}
AnimalDefinitions.stages["dob"].stages = {}
AnimalDefinitions.stages["dob"].stages["dobpup"] = {}
AnimalDefinitions.stages["dob"].stages["dobpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["dob"].stages["dobpup"].nextStage = "dobfemale"
AnimalDefinitions.stages["dob"].stages["dobpup"].nextStageMale = "dobmale"
AnimalDefinitions.stages["dob"].stages["dobmale"] = {}
AnimalDefinitions.stages["dob"].stages["dobmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["dob"].stages["dobfemale"] = {}
AnimalDefinitions.stages["dob"].stages["dobfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["dob"] = {}
AnimalDefinitions.breeds["dob"].breeds = {}
AnimalDefinitions.breeds["dob"].breeds["doberman"] = {}
AnimalDefinitions.breeds["dob"].breeds["doberman"].name = "doberman"
AnimalDefinitions.breeds["dob"].breeds["doberman"].texture = "Doberman"
AnimalDefinitions.breeds["dob"].breeds["doberman"].textureMale = "Doberman"
AnimalDefinitions.breeds["dob"].breeds["doberman"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["dob"].breeds["doberman"].invIconBabySkel = "Item_Skeleton_Raccoon"

local dobpup = {}
CD.applyDogModel(dobpup, "Doberman_Body")
CD.applyDogBehaviour(dobpup)
dobpup.shadoww = 0.2
dobpup.shadowfm = 0.2
dobpup.shadowbm = 0.2
dobpup.minSize = 1.12
dobpup.maxSize = 1.68
dobpup.wanderMul = 500
dobpup.hungerMultiplier = 0.001
dobpup.thirstMultiplier = 0.002
dobpup.hungerBoost = 25
dobpup.thirstBoost = 30
dobpup.baseEncumbrance = 10
dobpup.trailerBaseSize = 30
dobpup.minEnclosureSize = 40
dobpup.needMom = false
dobpup.eatFromMother = true
dobpup.litterEatTogether = true
dobpup.minWeight = 1
dobpup.maxWeight = 8
dobpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
dobpup.breeds = AnimalDefinitions.breeds["dob"].breeds
dobpup.stages = AnimalDefinitions.stages["dob"].stages
dobpup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["dobpup"] = dobpup

local dobfemale = {}
CD.applyDogModel(dobfemale, "Doberman_Body")
CD.applyDogBehaviour(dobfemale)
dobfemale.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
dobfemale.babyType = "dobpup"
dobfemale.shadoww = 0.3
dobfemale.shadowfm = 0.5
dobfemale.shadowbm = 0.5
dobfemale.minSize = 1.68
dobfemale.maxSize = 2.24
dobfemale.wanderMul = 600
dobfemale.hungerMultiplier = 0.008
dobfemale.thirstMultiplier = 0.016
dobfemale.hungerBoost = 20
dobfemale.thirstBoost = 25
dobfemale.baseEncumbrance = 20
dobfemale.trailerBaseSize = 50
dobfemale.minEnclosureSize = 40
dobfemale.minAge = 3 * 30
dobfemale.maxAgeGeriatric = 19 * 30
dobfemale.minAgeForBaby = 3 * 30
dobfemale.timeBeforeNextPregnancy = 7
dobfemale.pregnantPeriod = 35
dobfemale.minWeight = 9
dobfemale.maxWeight = 16
dobfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
dobfemale.breeds = AnimalDefinitions.breeds["dob"].breeds
dobfemale.stages = AnimalDefinitions.stages["dob"].stages
dobfemale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["dobfemale"] = dobfemale

local dobmale = {}
CD.applyDogModel(dobmale, "Doberman_Body")
CD.applyDogBehaviour(dobmale)
dobmale.male = true
dobmale.babyType = "dobpup"
dobmale.dontAttackOtherMale = true
dobmale.shadoww = 0.3
dobmale.shadowfm = 0.5
dobmale.shadowbm = 0.5
dobmale.minSize = 1.68
dobmale.maxSize = 2.43
dobmale.wanderMul = 600
dobmale.hungerMultiplier = 0.008
dobmale.thirstMultiplier = 0.016
dobmale.hungerBoost = 20
dobmale.thirstBoost = 25
dobmale.baseEncumbrance = 20
dobmale.trailerBaseSize = 50
dobmale.minEnclosureSize = 40
dobmale.minAge = 3 * 30
dobmale.maxAgeGeriatric = 19 * 30
dobmale.minAgeForBaby = 3 * 30
dobmale.minWeight = 10
dobmale.maxWeight = 18
dobmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
dobmale.breeds = AnimalDefinitions.breeds["dob"].breeds
dobmale.stages = AnimalDefinitions.stages["dob"].stages
dobmale.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals["dobmale"] = dobmale

AnimalDefinitions.animals["dobpup"].breeds["doberman"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["dobfemale"].breeds["doberman"].sounds = CD.DOG_SOUNDS
AnimalDefinitions.animals["dobmale"].breeds["doberman"].sounds = CD.DOG_SOUNDS

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["dobpup"] = {}
AnimalAvatarDefinition["dobfemale"] = {}
AnimalAvatarDefinition["dobmale"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition["dobpup"])
CD.applyDogAvatar(AnimalAvatarDefinition["dobfemale"])
CD.applyDogAvatar(AnimalAvatarDefinition["dobmale"])
