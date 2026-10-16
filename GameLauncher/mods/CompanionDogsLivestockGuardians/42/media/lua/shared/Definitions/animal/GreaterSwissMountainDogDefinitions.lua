if not (CompanionDogs and (CompanionDogs.API_VERSION or 0) >= 5
    and CompanionDogs.applyDogModel and CompanionDogs.applyDogBehaviour
    and CompanionDogs.applyDogAvatar and CompanionDogs.DOG_SOUNDS) then return end

local CD = CompanionDogs
local family = "greaterswissmountaindog"
local prefix = "greaterswiss"

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages[family] = { stages = {} }
local stages = AnimalDefinitions.stages[family].stages
stages[prefix .. "pup"] = {
    ageToGrow = 3 * 30,
    nextStage = prefix .. "female",
    nextStageMale = prefix .. "male",
}
stages[prefix .. "female"] = { ageToGrow = 3 * 30 }
stages[prefix .. "male"] = { ageToGrow = 3 * 30 }

AnimalDefinitions.breeds[family] = { breeds = {} }
local breed = {
    name = family,
    texture = "GreaterSwissMountainDog",
    textureMale = "GreaterSwissMountainDog",
    rottenTexture = "Raccoon_Rotting",
    invIconMale = "CDDogPaw_64",
    invIconFemale = "CDDogPaw_64",
    invIconBaby = "CDDogPaw_64",
    invIconMaleDead = "CDDogPawDead_64",
    invIconFemaleDead = "CDDogPawDead_64",
    invIconBabyDead = "CDDogPawDead_64",
    invIconMaleSkel = "Item_Skeleton_Raccoon",
    invIconFemaleSkel = "Item_Skeleton_Raccoon",
    invIconBabySkel = "Item_Skeleton_Raccoon",
}
AnimalDefinitions.breeds[family].breeds[family] = breed

local pup = {}
CD.applyDogModel(pup, "CDLG_GreaterSwiss_Body")
CD.applyDogBehaviour(pup)
pup.shadoww = 0.2
pup.shadowfm = 0.2
pup.shadowbm = 0.2
pup.minSize = 0.4
pup.maxSize = 1.2
pup.wanderMul = 500
pup.hungerMultiplier = 0.001
pup.thirstMultiplier = 0.002
pup.hungerBoost = 25
pup.thirstBoost = 30
pup.baseEncumbrance = 10
pup.trailerBaseSize = 30
pup.minEnclosureSize = 40
pup.needMom = false
pup.eatFromMother = true
pup.litterEatTogether = true
pup.minWeight = 0.71384
pup.maxWeight = 19.27368
pup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
pup.breeds = AnimalDefinitions.breeds[family].breeds
pup.stages = stages
pup.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals[prefix .. "pup"] = pup

local female = {}
CD.applyDogModel(female, "CDLG_GreaterSwiss_Body")
CD.applyDogBehaviour(female)
female.female = true
female.babyType = prefix .. "pup"
female.shadoww = 0.3
female.shadowfm = 0.5
female.shadowbm = 0.5
female.minSize = 1.71
female.maxSize = 2.46
female.wanderMul = 600
female.hungerMultiplier = 0.008
female.thirstMultiplier = 0.016
female.hungerBoost = 20
female.thirstBoost = 25
female.baseEncumbrance = 20
female.trailerBaseSize = 50
female.minEnclosureSize = 40
female.minAge = 3 * 30
female.maxAgeGeriatric = 19 * 30
female.minAgeForBaby = 3 * 30
female.timeBeforeNextPregnancy = 7
female.pregnantPeriod = 35
female.minWeight = 36
female.maxWeight = 50
female.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
female.breeds = AnimalDefinitions.breeds[family].breeds
female.stages = stages
female.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals[prefix .. "female"] = female

local male = {}
CD.applyDogModel(male, "CDLG_GreaterSwiss_Body")
CD.applyDogBehaviour(male)
male.male = true
male.babyType = prefix .. "pup"
male.dontAttackOtherMale = true
male.shadoww = 0.3
male.shadowfm = 0.5
male.shadowbm = 0.5
male.minSize = 1.85
male.maxSize = 2.6
male.wanderMul = 600
male.hungerMultiplier = 0.008
male.thirstMultiplier = 0.016
male.hungerBoost = 20
male.thirstBoost = 25
male.baseEncumbrance = 20
male.trailerBaseSize = 50
male.minEnclosureSize = 40
male.minAge = 3 * 30
male.maxAgeGeriatric = 19 * 30
male.minAgeForBaby = 3 * 30
male.minWeight = 52
male.maxWeight = 64
male.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
male.breeds = AnimalDefinitions.breeds[family].breeds
male.stages = stages
male.genes = AnimalDefinitions.genome["dog"].genes
AnimalDefinitions.animals[prefix .. "male"] = male

breed.sounds = CD.DOG_SOUNDS

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition[prefix .. "pup"] = {}
AnimalAvatarDefinition[prefix .. "female"] = {}
AnimalAvatarDefinition[prefix .. "male"] = {}
CD.applyDogAvatar(AnimalAvatarDefinition[prefix .. "pup"])
CD.applyDogAvatar(AnimalAvatarDefinition[prefix .. "female"])
CD.applyDogAvatar(AnimalAvatarDefinition[prefix .. "male"])
