AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.genome = AnimalDefinitions.genome or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["dog"] = {}
AnimalDefinitions.stages["dog"].stages = {}
AnimalDefinitions.stages["dog"].stages["dogpup"] = {}
AnimalDefinitions.stages["dog"].stages["dogpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["dog"].stages["dogpup"].nextStage = "dogfemale"
AnimalDefinitions.stages["dog"].stages["dogpup"].nextStageMale = "dogmale"
AnimalDefinitions.stages["dog"].stages["dogmale"] = {}
AnimalDefinitions.stages["dog"].stages["dogmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["dog"].stages["dogfemale"] = {}
AnimalDefinitions.stages["dog"].stages["dogfemale"].ageToGrow = 3 * 30

AnimalDefinitions.stages["gs"] = {}
AnimalDefinitions.stages["gs"].stages = {}
AnimalDefinitions.stages["gs"].stages["gspup"] = {}
AnimalDefinitions.stages["gs"].stages["gspup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["gs"].stages["gspup"].nextStage = "gsfemale"
AnimalDefinitions.stages["gs"].stages["gspup"].nextStageMale = "gsmale"
AnimalDefinitions.stages["gs"].stages["gsmale"] = {}
AnimalDefinitions.stages["gs"].stages["gsmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["gs"].stages["gsfemale"] = {}
AnimalDefinitions.stages["gs"].stages["gsfemale"].ageToGrow = 3 * 30

AnimalDefinitions.stages["retriever"] = {}
AnimalDefinitions.stages["retriever"].stages = {}
AnimalDefinitions.stages["retriever"].stages["retrieverpup"] = {}
AnimalDefinitions.stages["retriever"].stages["retrieverpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["retriever"].stages["retrieverpup"].nextStage = "retrieverfemale"
AnimalDefinitions.stages["retriever"].stages["retrieverpup"].nextStageMale = "retrievermale"
AnimalDefinitions.stages["retriever"].stages["retrievermale"] = {}
AnimalDefinitions.stages["retriever"].stages["retrievermale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["retriever"].stages["retrieverfemale"] = {}
AnimalDefinitions.stages["retriever"].stages["retrieverfemale"].ageToGrow = 3 * 30

AnimalDefinitions.stages["husky"] = {}
AnimalDefinitions.stages["husky"].stages = {}
AnimalDefinitions.stages["husky"].stages["huskypup"] = {}
AnimalDefinitions.stages["husky"].stages["huskypup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["husky"].stages["huskypup"].nextStage = "huskyfemale"
AnimalDefinitions.stages["husky"].stages["huskypup"].nextStageMale = "huskymale"
AnimalDefinitions.stages["husky"].stages["huskymale"] = {}
AnimalDefinitions.stages["husky"].stages["huskymale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["husky"].stages["huskyfemale"] = {}
AnimalDefinitions.stages["husky"].stages["huskyfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["dog"] = {}
AnimalDefinitions.breeds["dog"].breeds = {}
AnimalDefinitions.breeds["dog"].breeds["brown"] = {}
AnimalDefinitions.breeds["dog"].breeds["brown"].name = "brown"
AnimalDefinitions.breeds["dog"].breeds["brown"].texture = "Caramelo"
AnimalDefinitions.breeds["dog"].breeds["brown"].textureMale = "Caramelo"
AnimalDefinitions.breeds["dog"].breeds["brown"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["dog"].breeds["brown"].invIconBabySkel = "Item_Skeleton_Raccoon"

AnimalDefinitions.breeds["gs"] = {}
AnimalDefinitions.breeds["gs"].breeds = {}
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"] = {}
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].name = "germanshepherd"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].texture = "GermanShepherd"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].textureMale = "GermanShepherd"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["gs"].breeds["germanshepherd"].invIconBabySkel = "Item_Skeleton_Raccoon"

AnimalDefinitions.breeds["retriever"] = {}
AnimalDefinitions.breeds["retriever"].breeds = {}
AnimalDefinitions.breeds["retriever"].breeds["golden"] = {}
AnimalDefinitions.breeds["retriever"].breeds["golden"].name = "golden"
AnimalDefinitions.breeds["retriever"].breeds["golden"].texture = "RetrieverPoly"
AnimalDefinitions.breeds["retriever"].breeds["golden"].textureMale = "RetrieverPoly"
AnimalDefinitions.breeds["retriever"].breeds["golden"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["retriever"].breeds["golden"].invIconBabySkel = "Item_Skeleton_Raccoon"

AnimalDefinitions.breeds["husky"] = {}
AnimalDefinitions.breeds["husky"].breeds = {}
AnimalDefinitions.breeds["husky"].breeds["husky"] = {}
AnimalDefinitions.breeds["husky"].breeds["husky"].name = "husky"
AnimalDefinitions.breeds["husky"].breeds["husky"].texture = "Husky"
AnimalDefinitions.breeds["husky"].breeds["husky"].textureMale = "Husky"
AnimalDefinitions.breeds["husky"].breeds["husky"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["husky"].breeds["husky"].invIconBabySkel = "Item_Skeleton_Raccoon"

CompanionDogs = CompanionDogs or {}

---@type string[]
CompanionDogs.COMPANION_GENES = {
    "maxSize", "meatRatio", "maxWeight", "lifeExpectancy", "resistance", "strength",
    "hungerResistance", "thirstResistance", "aggressiveness", "ageToGrow", "fertility", "stress",
}

-- A engine so le a lista `genes` de cada estagio; a chave do genome e convencao nossa. Cria o
-- genoma da especie com a lista padrao, se ainda nao existir, e devolve a tabela de genes.
---@param key string key in AnimalDefinitions.genome
---@return table<string, string> genes
function CompanionDogs.defineGenome(key)
    local g = AnimalDefinitions.genome[key]
    if not g then
        g = { genes = {} }
        for _, name in ipairs(CompanionDogs.COMPANION_GENES) do g.genes[name] = name end
        AnimalDefinitions.genome[key] = g
    end
    return g.genes
end

local dogGenes = CompanionDogs.defineGenome("dog")

local dog_sounds = {
    death = { name = "CDDogDeath", slot = "voice", priority = 100 },
    fallover = { name = "AnimalFoleyRaccoonBodyfall" },
    pain = { name = "CDDogWhine", slot = "voice", priority = 50 },
    pick_up = { name = "CDDogPickup", slot = "voice", priority = 1 },
    pick_up_corpse = { name = "PickUpAnimalDeadRaccoon" },
    put_down = { name = "CDDogPickup", slot = "voice", priority = 1 },
    put_down_corpse = { name = "PutDownAnimalDeadRaccoon" },
    runloop = { name = "AnimalFootstepsRaccoonRun", slot = "runloop" },
    walkBack = { name = "AnimalFootstepsRaccoonWalkBack" },
    walkFront = { name = "AnimalFootstepsRaccoonWalkFront" },
}

---@type table<string, table> event -> { name, slot?, priority? }, the AnimalDefinitions `sounds` format
CompanionDogs.DOG_SOUNDS = dog_sounds
-- Alias neutro de especie do contrato de addon; os nomes com Dog continuam validos.
CompanionDogs.COMPANION_SOUNDS = dog_sounds

---@param a table AnimalDefinitions.animals entry
---@param bodyModel string|nil model name from models_*.txt; defaults to Caramelo_Body
function CompanionDogs.applyDogModel(a, bodyModel)
    a.bodyModel = bodyModel or "Caramelo_Body"
    a.bodyModelSkel = "Raccoon_Skeleton"
    a.textureSkeleton = "RaccoonSkeleton"
    a.textureSkeletonBloody = "RaccoonSkeleton_Butchered"
    a.bodyModelSkelNoHead = "Raccoon_Skeleton_NoHead"
    -- Tem que continuar "raccoon": um nome de animset forkado nao carrega e o animal congela sem FSM.
    a.animset = "raccoon"
    a.feedByHandAnim = "AnimalLureLow"
end

---@param a table AnimalDefinitions.animals entry
function CompanionDogs.applyDogBehaviour(a)
    a.group = "dog"
    a.wild = false
    a.alwaysFleeHumans = false
    a.fleeHumansMod = 0
    a.canBeAlerted = false
    a.fleeZombies = false
    a.attackBack = false
    a.healthLossMultiplier = 0.004
    a.canBeDomesticated = true
    a.canBePet = true
    a.canBePicked = true
    a.canClimbStairs = true
    a.canClimbFences = false
    a.collidable = false
    a.idleTypeNbr = 2
    a.idleEmoteChance = 450
    a.sitRandomly = false
    a.turnDelta = 0.95
    -- animalSize e a margem de chegada do PathFindBehavior2: em 0.0 o ramo de chegada nunca conclui
    -- e o cao para de transladar ate alguem re-emitir o caminho.
    a.animalSize = 0.25
    a.addTrackingXp = false
    a.corpseSize = 0
    a.dung = "Dung_Raccoon"
    a.canBeKilledWithoutWeapon = true
    a.eatTypeTrough = "AnimalFeed,Grass,Hay,Vegetables,Fruits"
    a.thirstHungerTrigger = 0.1
    a.distToEat = 1
end

local STRAY_NO_BLEEDOUT = 1000000
CompanionDogs.STRAY_NO_BLEEDOUT = STRAY_NO_BLEEDOUT

CompanionDogs.applyCompanionModel = CompanionDogs.applyDogModel
CompanionDogs.applyCompanionBehaviour = CompanionDogs.applyDogBehaviour

local applyDogModel = CompanionDogs.applyDogModel
local applyDogBehaviour = CompanionDogs.applyDogBehaviour

local pup = {}
applyDogModel(pup, "Caramelo_Body")
applyDogBehaviour(pup)
pup.shadoww = 0.2
pup.shadowfm = 0.2
pup.shadowbm = 0.2
pup.minSize = 0.78
pup.maxSize = 1.17
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
pup.minWeight = 1
pup.maxWeight = 8
pup.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
pup.breeds = AnimalDefinitions.breeds["dog"].breeds
pup.stages = AnimalDefinitions.stages["dog"].stages
pup.genes = dogGenes
AnimalDefinitions.animals["dogpup"] = pup

local female = {}
applyDogModel(female, "Caramelo_Body")
applyDogBehaviour(female)
female.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
-- Nao re-adicionar.
female.babyType = "dogpup"
female.shadoww = 0.3
female.shadowfm = 0.5
female.shadowbm = 0.5
female.minSize = 1.17
female.maxSize = 1.56
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
female.minWeight = 9
female.maxWeight = 16
female.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
female.breeds = AnimalDefinitions.breeds["dog"].breeds
female.stages = AnimalDefinitions.stages["dog"].stages
female.genes = dogGenes
AnimalDefinitions.animals["dogfemale"] = female

local male = {}
applyDogModel(male, "Caramelo_Body")
applyDogBehaviour(male)
male.male = true
male.babyType = "dogpup"
male.dontAttackOtherMale = true
male.shadoww = 0.3
male.shadowfm = 0.5
male.shadowbm = 0.5
male.minSize = 1.17
male.maxSize = 1.69
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
male.minWeight = 10
male.maxWeight = 18
male.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
male.breeds = AnimalDefinitions.breeds["dog"].breeds
male.stages = AnimalDefinitions.stages["dog"].stages
male.genes = dogGenes
AnimalDefinitions.animals["dogmale"] = male

AnimalDefinitions.animals["dogpup"].breeds["brown"].sounds = dog_sounds
AnimalDefinitions.animals["dogfemale"].breeds["brown"].sounds = dog_sounds
AnimalDefinitions.animals["dogmale"].breeds["brown"].sounds = dog_sounds

local gspup = {}
applyDogModel(gspup, "GermanShepherd_Body")
applyDogBehaviour(gspup)
gspup.shadoww = 0.2
gspup.shadowfm = 0.2
gspup.shadowbm = 0.2
gspup.minSize = 1.12
gspup.maxSize = 1.68
gspup.wanderMul = 500
gspup.hungerMultiplier = 0.001
gspup.thirstMultiplier = 0.002
gspup.hungerBoost = 25
gspup.thirstBoost = 30
gspup.baseEncumbrance = 10
gspup.trailerBaseSize = 30
gspup.minEnclosureSize = 40
gspup.needMom = false
gspup.eatFromMother = true
gspup.litterEatTogether = true
gspup.minWeight = 1
gspup.maxWeight = 8
gspup.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
gspup.breeds = AnimalDefinitions.breeds["gs"].breeds
gspup.stages = AnimalDefinitions.stages["gs"].stages
gspup.genes = dogGenes
AnimalDefinitions.animals["gspup"] = gspup

local gsfemale = {}
applyDogModel(gsfemale, "GermanShepherd_Body")
applyDogBehaviour(gsfemale)
gsfemale.female = true
gsfemale.babyType = "gspup"
gsfemale.shadoww = 0.3
gsfemale.shadowfm = 0.5
gsfemale.shadowbm = 0.5
gsfemale.minSize = 1.68
gsfemale.maxSize = 2.24
gsfemale.wanderMul = 600
gsfemale.hungerMultiplier = 0.008
gsfemale.thirstMultiplier = 0.016
gsfemale.hungerBoost = 20
gsfemale.thirstBoost = 25
gsfemale.baseEncumbrance = 20
gsfemale.trailerBaseSize = 50
gsfemale.minEnclosureSize = 40
gsfemale.minAge = 3 * 30
gsfemale.maxAgeGeriatric = 19 * 30
gsfemale.minAgeForBaby = 3 * 30
gsfemale.timeBeforeNextPregnancy = 7
gsfemale.pregnantPeriod = 35
gsfemale.minWeight = 9
gsfemale.maxWeight = 16
gsfemale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
gsfemale.breeds = AnimalDefinitions.breeds["gs"].breeds
gsfemale.stages = AnimalDefinitions.stages["gs"].stages
gsfemale.genes = dogGenes
AnimalDefinitions.animals["gsfemale"] = gsfemale

local gsmale = {}
applyDogModel(gsmale, "GermanShepherd_Body")
applyDogBehaviour(gsmale)
gsmale.male = true
gsmale.babyType = "gspup"
gsmale.dontAttackOtherMale = true
gsmale.shadoww = 0.3
gsmale.shadowfm = 0.5
gsmale.shadowbm = 0.5
gsmale.minSize = 1.68
gsmale.maxSize = 2.43
gsmale.wanderMul = 600
gsmale.hungerMultiplier = 0.008
gsmale.thirstMultiplier = 0.016
gsmale.hungerBoost = 20
gsmale.thirstBoost = 25
gsmale.baseEncumbrance = 20
gsmale.trailerBaseSize = 50
gsmale.minEnclosureSize = 40
gsmale.minAge = 3 * 30
gsmale.maxAgeGeriatric = 19 * 30
gsmale.minAgeForBaby = 3 * 30
gsmale.minWeight = 10
gsmale.maxWeight = 18
gsmale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
gsmale.breeds = AnimalDefinitions.breeds["gs"].breeds
gsmale.stages = AnimalDefinitions.stages["gs"].stages
gsmale.genes = dogGenes
AnimalDefinitions.animals["gsmale"] = gsmale

AnimalDefinitions.animals["gspup"].breeds["germanshepherd"].sounds = dog_sounds
AnimalDefinitions.animals["gsfemale"].breeds["germanshepherd"].sounds = dog_sounds
AnimalDefinitions.animals["gsmale"].breeds["germanshepherd"].sounds = dog_sounds

local retrieverpup = {}
applyDogModel(retrieverpup, "Retriever_Body")
applyDogBehaviour(retrieverpup)
retrieverpup.shadoww = 0.2
retrieverpup.shadowfm = 0.2
retrieverpup.shadowbm = 0.2
retrieverpup.minSize = 1.05
retrieverpup.maxSize = 1.55
retrieverpup.wanderMul = 500
retrieverpup.hungerMultiplier = 0.001
retrieverpup.thirstMultiplier = 0.002
retrieverpup.hungerBoost = 25
retrieverpup.thirstBoost = 30
retrieverpup.baseEncumbrance = 10
retrieverpup.trailerBaseSize = 30
retrieverpup.minEnclosureSize = 40
retrieverpup.needMom = false
retrieverpup.eatFromMother = true
retrieverpup.litterEatTogether = true
retrieverpup.minWeight = 1
retrieverpup.maxWeight = 8
retrieverpup.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
retrieverpup.breeds = AnimalDefinitions.breeds["retriever"].breeds
retrieverpup.stages = AnimalDefinitions.stages["retriever"].stages
retrieverpup.genes = dogGenes
AnimalDefinitions.animals["retrieverpup"] = retrieverpup

local retrieverfemale = {}
applyDogModel(retrieverfemale, "Retriever_Body")
applyDogBehaviour(retrieverfemale)
retrieverfemale.female = true
retrieverfemale.babyType = "retrieverpup"
retrieverfemale.shadoww = 0.3
retrieverfemale.shadowfm = 0.5
retrieverfemale.shadowbm = 0.5
retrieverfemale.minSize = 1.5
retrieverfemale.maxSize = 2.0
retrieverfemale.wanderMul = 600
retrieverfemale.hungerMultiplier = 0.008
retrieverfemale.thirstMultiplier = 0.016
retrieverfemale.hungerBoost = 20
retrieverfemale.thirstBoost = 25
retrieverfemale.baseEncumbrance = 20
retrieverfemale.trailerBaseSize = 50
retrieverfemale.minEnclosureSize = 40
retrieverfemale.minAge = 3 * 30
retrieverfemale.maxAgeGeriatric = 19 * 30
retrieverfemale.minAgeForBaby = 3 * 30
retrieverfemale.timeBeforeNextPregnancy = 7
retrieverfemale.pregnantPeriod = 35
retrieverfemale.minWeight = 9
retrieverfemale.maxWeight = 16
retrieverfemale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
retrieverfemale.breeds = AnimalDefinitions.breeds["retriever"].breeds
retrieverfemale.stages = AnimalDefinitions.stages["retriever"].stages
retrieverfemale.genes = dogGenes
AnimalDefinitions.animals["retrieverfemale"] = retrieverfemale

local retrievermale = {}
applyDogModel(retrievermale, "Retriever_Body")
applyDogBehaviour(retrievermale)
retrievermale.male = true
retrievermale.babyType = "retrieverpup"
retrievermale.dontAttackOtherMale = true
retrievermale.shadoww = 0.3
retrievermale.shadowfm = 0.5
retrievermale.shadowbm = 0.5
retrievermale.minSize = 1.5
retrievermale.maxSize = 2.15
retrievermale.wanderMul = 600
retrievermale.hungerMultiplier = 0.008
retrievermale.thirstMultiplier = 0.016
retrievermale.hungerBoost = 20
retrievermale.thirstBoost = 25
retrievermale.baseEncumbrance = 20
retrievermale.trailerBaseSize = 50
retrievermale.minEnclosureSize = 40
retrievermale.minAge = 3 * 30
retrievermale.maxAgeGeriatric = 19 * 30
retrievermale.minAgeForBaby = 3 * 30
retrievermale.minWeight = 10
retrievermale.maxWeight = 18
retrievermale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
retrievermale.breeds = AnimalDefinitions.breeds["retriever"].breeds
retrievermale.stages = AnimalDefinitions.stages["retriever"].stages
retrievermale.genes = dogGenes
AnimalDefinitions.animals["retrievermale"] = retrievermale

AnimalDefinitions.animals["retrieverpup"].breeds["golden"].sounds = dog_sounds
AnimalDefinitions.animals["retrieverfemale"].breeds["golden"].sounds = dog_sounds
AnimalDefinitions.animals["retrievermale"].breeds["golden"].sounds = dog_sounds

local huskypup = {}
applyDogModel(huskypup, "Husky_Body")
applyDogBehaviour(huskypup)
huskypup.shadoww = 0.2
huskypup.shadowfm = 0.2
huskypup.shadowbm = 0.2
huskypup.minSize = 1.05
huskypup.maxSize = 1.55
huskypup.wanderMul = 500
huskypup.hungerMultiplier = 0.0013
huskypup.thirstMultiplier = 0.002
huskypup.hungerBoost = 25
huskypup.thirstBoost = 30
huskypup.baseEncumbrance = 10
huskypup.trailerBaseSize = 30
huskypup.minEnclosureSize = 40
huskypup.needMom = false
huskypup.eatFromMother = true
huskypup.litterEatTogether = true
huskypup.minWeight = 1
huskypup.maxWeight = 8
huskypup.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
huskypup.breeds = AnimalDefinitions.breeds["husky"].breeds
huskypup.stages = AnimalDefinitions.stages["husky"].stages
huskypup.genes = dogGenes
AnimalDefinitions.animals["huskypup"] = huskypup

local huskyfemale = {}
applyDogModel(huskyfemale, "Husky_Body")
applyDogBehaviour(huskyfemale)
huskyfemale.female = true
huskyfemale.babyType = "huskypup"
huskyfemale.shadoww = 0.3
huskyfemale.shadowfm = 0.5
huskyfemale.shadowbm = 0.5
huskyfemale.minSize = 1.5
huskyfemale.maxSize = 2.0
huskyfemale.wanderMul = 600
huskyfemale.hungerMultiplier = 0.011
huskyfemale.thirstMultiplier = 0.016
huskyfemale.hungerBoost = 20
huskyfemale.thirstBoost = 25
huskyfemale.baseEncumbrance = 20
huskyfemale.trailerBaseSize = 50
huskyfemale.minEnclosureSize = 40
huskyfemale.minAge = 3 * 30
huskyfemale.maxAgeGeriatric = 19 * 30
huskyfemale.minAgeForBaby = 3 * 30
huskyfemale.timeBeforeNextPregnancy = 7
huskyfemale.pregnantPeriod = 35
huskyfemale.minWeight = 9
huskyfemale.maxWeight = 16
huskyfemale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
huskyfemale.breeds = AnimalDefinitions.breeds["husky"].breeds
huskyfemale.stages = AnimalDefinitions.stages["husky"].stages
huskyfemale.genes = dogGenes
AnimalDefinitions.animals["huskyfemale"] = huskyfemale

local huskymale = {}
applyDogModel(huskymale, "Husky_Body")
applyDogBehaviour(huskymale)
huskymale.male = true
huskymale.babyType = "huskypup"
huskymale.dontAttackOtherMale = true
huskymale.shadoww = 0.3
huskymale.shadowfm = 0.5
huskymale.shadowbm = 0.5
huskymale.minSize = 1.5
huskymale.maxSize = 2.15
huskymale.wanderMul = 600
huskymale.hungerMultiplier = 0.011
huskymale.thirstMultiplier = 0.016
huskymale.hungerBoost = 20
huskymale.thirstBoost = 25
huskymale.baseEncumbrance = 20
huskymale.trailerBaseSize = 50
huskymale.minEnclosureSize = 40
huskymale.minAge = 3 * 30
huskymale.maxAgeGeriatric = 19 * 30
huskymale.minAgeForBaby = 3 * 30
huskymale.minWeight = 10
huskymale.maxWeight = 18
huskymale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
huskymale.breeds = AnimalDefinitions.breeds["husky"].breeds
huskymale.stages = AnimalDefinitions.stages["husky"].stages
huskymale.genes = dogGenes
AnimalDefinitions.animals["huskymale"] = huskymale

AnimalDefinitions.animals["huskypup"].breeds["husky"].sounds = dog_sounds
AnimalDefinitions.animals["huskyfemale"].breeds["husky"].sounds = dog_sounds
AnimalDefinitions.animals["huskymale"].breeds["husky"].sounds = dog_sounds

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
---@param t table AnimalAvatarDefinition entry
function CompanionDogs.applyDogAvatar(t)
    t.zoom = 10
    t.xoffset = -0.1
    t.yoffset = -0.2
    t.avatarWidth = 200
    t.avatarDir = IsoDirections.SE
    t.trailerDir = IsoDirections.SW
    t.trailerZoom = 8.5
    t.trailerXoffset = 0.2
    t.trailerYoffset = -0.3
end
CompanionDogs.applyCompanionAvatar = CompanionDogs.applyDogAvatar
local applyDogAvatar = CompanionDogs.applyDogAvatar
AnimalAvatarDefinition["dogpup"] = {}
AnimalAvatarDefinition["dogfemale"] = {}
AnimalAvatarDefinition["dogmale"] = {}
applyDogAvatar(AnimalAvatarDefinition["dogpup"])
applyDogAvatar(AnimalAvatarDefinition["dogfemale"])
applyDogAvatar(AnimalAvatarDefinition["dogmale"])
AnimalAvatarDefinition["gspup"] = {}
AnimalAvatarDefinition["gsfemale"] = {}
AnimalAvatarDefinition["gsmale"] = {}
applyDogAvatar(AnimalAvatarDefinition["gspup"])
applyDogAvatar(AnimalAvatarDefinition["gsfemale"])
applyDogAvatar(AnimalAvatarDefinition["gsmale"])
AnimalAvatarDefinition["retrieverpup"] = {}
AnimalAvatarDefinition["retrieverfemale"] = {}
AnimalAvatarDefinition["retrievermale"] = {}
applyDogAvatar(AnimalAvatarDefinition["retrieverpup"])
applyDogAvatar(AnimalAvatarDefinition["retrieverfemale"])
applyDogAvatar(AnimalAvatarDefinition["retrievermale"])
AnimalAvatarDefinition["huskypup"] = {}
AnimalAvatarDefinition["huskyfemale"] = {}
AnimalAvatarDefinition["huskymale"] = {}
applyDogAvatar(AnimalAvatarDefinition["huskypup"])
applyDogAvatar(AnimalAvatarDefinition["huskyfemale"])
applyDogAvatar(AnimalAvatarDefinition["huskymale"])

AnimalDefinitions.stages["bordercollie"] = {}
AnimalDefinitions.stages["bordercollie"].stages = {}
AnimalDefinitions.stages["bordercollie"].stages["bcpup"] = {}
AnimalDefinitions.stages["bordercollie"].stages["bcpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["bordercollie"].stages["bcpup"].nextStage = "bcfemale"
AnimalDefinitions.stages["bordercollie"].stages["bcpup"].nextStageMale = "bcmale"
AnimalDefinitions.stages["bordercollie"].stages["bcmale"] = {}
AnimalDefinitions.stages["bordercollie"].stages["bcmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["bordercollie"].stages["bcfemale"] = {}
AnimalDefinitions.stages["bordercollie"].stages["bcfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["bordercollie"] = {}
AnimalDefinitions.breeds["bordercollie"].breeds = {}
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"] = {}
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].name = "bordercollie"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].texture = "BorderCollie"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].textureMale = "BorderCollie"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].rottenTexture = "Raccoon_Rotting"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconMale = "CDDogPaw_64"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconFemale = "CDDogPaw_64"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconBaby = "CDDogPaw_64"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconMaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconFemaleDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconBabyDead = "CDDogPawDead_64"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconMaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconFemaleSkel = "Item_Skeleton_Raccoon"
AnimalDefinitions.breeds["bordercollie"].breeds["bordercollie"].invIconBabySkel = "Item_Skeleton_Raccoon"

local bcpup = {}
applyDogModel(bcpup, "BorderCollie_Body")
applyDogBehaviour(bcpup)
bcpup.shadoww = 0.2
bcpup.shadowfm = 0.2
bcpup.shadowbm = 0.2
bcpup.minSize = 1.05
bcpup.maxSize = 1.55
bcpup.wanderMul = 500
bcpup.hungerMultiplier = 0.001
bcpup.thirstMultiplier = 0.002
bcpup.hungerBoost = 25
bcpup.thirstBoost = 30
bcpup.baseEncumbrance = 10
bcpup.trailerBaseSize = 30
bcpup.minEnclosureSize = 40
bcpup.needMom = false
bcpup.eatFromMother = true
bcpup.litterEatTogether = true
bcpup.minWeight = 1
bcpup.maxWeight = 8
bcpup.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
bcpup.breeds = AnimalDefinitions.breeds["bordercollie"].breeds
bcpup.stages = AnimalDefinitions.stages["bordercollie"].stages
bcpup.genes = dogGenes
AnimalDefinitions.animals["bcpup"] = bcpup

local bcfemale = {}
applyDogModel(bcfemale, "BorderCollie_Body")
applyDogBehaviour(bcfemale)
bcfemale.female = true
bcfemale.babyType = "bcpup"
bcfemale.shadoww = 0.3
bcfemale.shadowfm = 0.5
bcfemale.shadowbm = 0.5
bcfemale.minSize = 1.5
bcfemale.maxSize = 2.0
bcfemale.wanderMul = 600
bcfemale.hungerMultiplier = 0.008
bcfemale.thirstMultiplier = 0.016
bcfemale.hungerBoost = 20
bcfemale.thirstBoost = 25
bcfemale.baseEncumbrance = 20
bcfemale.trailerBaseSize = 50
bcfemale.minEnclosureSize = 40
bcfemale.minAge = 3 * 30
bcfemale.maxAgeGeriatric = 19 * 30
bcfemale.minAgeForBaby = 3 * 30
bcfemale.timeBeforeNextPregnancy = 7
bcfemale.pregnantPeriod = 35
bcfemale.minWeight = 9
bcfemale.maxWeight = 16
bcfemale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
bcfemale.breeds = AnimalDefinitions.breeds["bordercollie"].breeds
bcfemale.stages = AnimalDefinitions.stages["bordercollie"].stages
bcfemale.genes = dogGenes
AnimalDefinitions.animals["bcfemale"] = bcfemale

local bcmale = {}
applyDogModel(bcmale, "BorderCollie_Body")
applyDogBehaviour(bcmale)
bcmale.male = true
bcmale.babyType = "bcpup"
bcmale.dontAttackOtherMale = true
bcmale.shadoww = 0.3
bcmale.shadowfm = 0.5
bcmale.shadowbm = 0.5
bcmale.minSize = 1.5
bcmale.maxSize = 2.15
bcmale.wanderMul = 600
bcmale.hungerMultiplier = 0.008
bcmale.thirstMultiplier = 0.016
bcmale.hungerBoost = 20
bcmale.thirstBoost = 25
bcmale.baseEncumbrance = 20
bcmale.trailerBaseSize = 50
bcmale.minEnclosureSize = 40
bcmale.minAge = 3 * 30
bcmale.maxAgeGeriatric = 19 * 30
bcmale.minAgeForBaby = 3 * 30
bcmale.minWeight = 10
bcmale.maxWeight = 18
bcmale.wildFleeTimeUntilDeadTimer = STRAY_NO_BLEEDOUT
bcmale.breeds = AnimalDefinitions.breeds["bordercollie"].breeds
bcmale.stages = AnimalDefinitions.stages["bordercollie"].stages
bcmale.genes = dogGenes
AnimalDefinitions.animals["bcmale"] = bcmale

AnimalDefinitions.animals["bcpup"].breeds["bordercollie"].sounds = dog_sounds
AnimalDefinitions.animals["bcfemale"].breeds["bordercollie"].sounds = dog_sounds
AnimalDefinitions.animals["bcmale"].breeds["bordercollie"].sounds = dog_sounds

AnimalAvatarDefinition["bcpup"] = {}
AnimalAvatarDefinition["bcfemale"] = {}
AnimalAvatarDefinition["bcmale"] = {}
applyDogAvatar(AnimalAvatarDefinition["bcpup"])
applyDogAvatar(AnimalAvatarDefinition["bcfemale"])
applyDogAvatar(AnimalAvatarDefinition["bcmale"])
