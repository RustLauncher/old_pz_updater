if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

-- O guard fica nos nomes velhos de proposito: se a Steam atualizar o addon antes do base, um guard
-- nos nomes novos faria este arquivo retornar cedo, o tipo cat* sumiria e a engine apagaria a celula
-- de animais do chunk em diante. Os nomes neutros entraram na API 7; o shim sai quando o piso do
-- gato subir para o base que os trouxe.
local applyModel = CD.applyCompanionModel or CD.applyDogModel
local applyBehaviour = CD.applyCompanionBehaviour or CD.applyDogBehaviour
local applyAvatar = CD.applyCompanionAvatar or CD.applyDogAvatar
local baseSounds = CD.COMPANION_SOUNDS or CD.DOG_SOUNDS
local catGenes = CD.defineGenome and CD.defineGenome("cat") or AnimalDefinitions.genome["dog"].genes

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["cat"] = {}
AnimalDefinitions.stages["cat"].stages = {}
AnimalDefinitions.stages["cat"].stages["catpup"] = {}
AnimalDefinitions.stages["cat"].stages["catpup"].ageToGrow = 3 * 30
AnimalDefinitions.stages["cat"].stages["catpup"].nextStage = "catfemale"
AnimalDefinitions.stages["cat"].stages["catpup"].nextStageMale = "catmale"
AnimalDefinitions.stages["cat"].stages["catmale"] = {}
AnimalDefinitions.stages["cat"].stages["catmale"].ageToGrow = 3 * 30
AnimalDefinitions.stages["cat"].stages["catfemale"] = {}
AnimalDefinitions.stages["cat"].stages["catfemale"].ageToGrow = 3 * 30

AnimalDefinitions.breeds["cat"] = {}
AnimalDefinitions.breeds["cat"].breeds = {}

local CAT_COATS = {
    { name = "cat",        texture = "Cat" },
    { name = "cat_white",  texture = "Cat_White" },
    { name = "cat_orange", texture = "Cat_Orange" },
    { name = "cat_calico", texture = "Cat_Calico" },
    { name = "cat_tuxedo", texture = "Cat_Tuxedo" },
    { name = "cat_brown_tabby",  texture = "Cat_BrownTabby" },
    { name = "cat_grey_tabby",   texture = "Cat_GreyTabby" },
    { name = "cat_orange_tabby", texture = "Cat_OrangeTabby" },
    { name = "cat_barley",       texture = "Cat_Barley" },
    { name = "cat_cow",          texture = "Cat_Cow" },
    { name = "cat_tortie",       texture = "Cat_Tortie" },
}

for _, coat in ipairs(CAT_COATS) do
    local b = {}
    b.name = coat.name
    b.texture = coat.texture
    b.textureMale = coat.texture
    b.rottenTexture = "Raccoon_Rotting"
    b.invIconMale = "CDDogPaw_64"
    b.invIconFemale = "CDDogPaw_64"
    b.invIconBaby = "CDDogPaw_64"
    b.invIconMaleDead = "CDDogPawDead_64"
    b.invIconFemaleDead = "CDDogPawDead_64"
    b.invIconBabyDead = "CDDogPawDead_64"
    b.invIconMaleSkel = "Item_Skeleton_Raccoon"
    b.invIconFemaleSkel = "Item_Skeleton_Raccoon"
    b.invIconBabySkel = "Item_Skeleton_Raccoon"
    AnimalDefinitions.breeds["cat"].breeds[coat.name] = b
end

local catpup = {}
applyModel(catpup, "Cat_Body")
applyBehaviour(catpup)
catpup.group = "cat"
catpup.shadoww = 0.2
catpup.shadowfm = 0.2
catpup.shadowbm = 0.2
catpup.minSize = 1.728
catpup.maxSize = 2.551
catpup.wanderMul = 500
catpup.hungerMultiplier = 0.001
catpup.thirstMultiplier = 0.002
catpup.hungerBoost = 25
catpup.thirstBoost = 30
catpup.baseEncumbrance = 4
catpup.trailerBaseSize = 20
catpup.minEnclosureSize = 30
catpup.needMom = false
catpup.eatFromMother = true
catpup.litterEatTogether = true
catpup.minWeight = 1
catpup.maxWeight = 2
catpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
catpup.breeds = AnimalDefinitions.breeds["cat"].breeds
catpup.stages = AnimalDefinitions.stages["cat"].stages
catpup.genes = catGenes
AnimalDefinitions.animals["catpup"] = catpup

local catfemale = {}
applyModel(catfemale, "Cat_Body")
applyBehaviour(catfemale)
catfemale.group = "cat"
catfemale.female = true
-- Sem `mate` de proposito: com ele a engine roda o acasalamento nativo dela, por fora do mod.
catfemale.babyType = "catpup"
catfemale.shadoww = 0.3
catfemale.shadowfm = 0.35
catfemale.shadowbm = 0.35
catfemale.minSize = 2.469
catfemale.maxSize = 3.291
catfemale.wanderMul = 600
catfemale.hungerMultiplier = 0.004
catfemale.thirstMultiplier = 0.010
catfemale.hungerBoost = 20
catfemale.thirstBoost = 25
catfemale.baseEncumbrance = 8
catfemale.trailerBaseSize = 25
catfemale.minEnclosureSize = 30
catfemale.minAge = 3 * 30
catfemale.maxAgeGeriatric = 15 * 30
catfemale.minAgeForBaby = 3 * 30
catfemale.timeBeforeNextPregnancy = 7
catfemale.pregnantPeriod = 35
catfemale.minWeight = 3
catfemale.maxWeight = 5
catfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
catfemale.breeds = AnimalDefinitions.breeds["cat"].breeds
catfemale.stages = AnimalDefinitions.stages["cat"].stages
catfemale.genes = catGenes
AnimalDefinitions.animals["catfemale"] = catfemale

local catmale = {}
applyModel(catmale, "Cat_Body")
applyBehaviour(catmale)
catmale.group = "cat"
catmale.male = true
catmale.babyType = "catpup"
catmale.dontAttackOtherMale = true
catmale.shadoww = 0.3
catmale.shadowfm = 0.35
catmale.shadowbm = 0.35
catmale.minSize = 2.469
catmale.maxSize = 3.539
catmale.wanderMul = 600
catmale.hungerMultiplier = 0.004
catmale.thirstMultiplier = 0.010
catmale.hungerBoost = 20
catmale.thirstBoost = 25
catmale.baseEncumbrance = 8
catmale.trailerBaseSize = 25
catmale.minEnclosureSize = 30
catmale.minAge = 3 * 30
catmale.maxAgeGeriatric = 15 * 30
catmale.minAgeForBaby = 3 * 30
catmale.minWeight = 4
catmale.maxWeight = 6
catmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
catmale.breeds = AnimalDefinitions.breeds["cat"].breeds
catmale.stages = AnimalDefinitions.stages["cat"].stages
catmale.genes = catGenes
AnimalDefinitions.animals["catmale"] = catmale

local cat_sounds = {}
for k, v in pairs(baseSounds) do cat_sounds[k] = v end
cat_sounds.pain    = { name = "CDCatHiss",  slot = "voice", priority = 50 }
cat_sounds.death   = { name = "CDCatMeow",  slot = "voice", priority = 100 }
cat_sounds.pick_up = { name = "CDCatPurr",  slot = "voice", priority = 1 }
cat_sounds.put_down = cat_sounds.pick_up

for _, coat in ipairs(CAT_COATS) do
    AnimalDefinitions.breeds["cat"].breeds[coat.name].sounds = cat_sounds
end

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["catpup"] = {}
AnimalAvatarDefinition["catfemale"] = {}
AnimalAvatarDefinition["catmale"] = {}
applyAvatar(AnimalAvatarDefinition["catpup"])
applyAvatar(AnimalAvatarDefinition["catfemale"])
applyAvatar(AnimalAvatarDefinition["catmale"])

local SIZE_RATIO = 0.3116
for _, t in ipairs({ AnimalAvatarDefinition["catpup"], AnimalAvatarDefinition["catfemale"],
                     AnimalAvatarDefinition["catmale"] }) do
    t.zoom = 5.99
    t.trailerZoom = 5.52
    t.xoffset = t.xoffset * SIZE_RATIO
    t.yoffset = t.yoffset * SIZE_RATIO
    t.trailerXoffset = t.trailerXoffset * SIZE_RATIO
    t.trailerYoffset = t.trailerYoffset * SIZE_RATIO
end
