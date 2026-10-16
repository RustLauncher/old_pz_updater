if not (CompanionDogs and CompanionDogs.applyDogModel and CompanionDogs.DOG_SOUNDS) then return end
local CD = CompanionDogs

local applyModel = CD.applyCompanionModel or CD.applyDogModel
local applyBehaviour = CD.applyCompanionBehaviour or CD.applyDogBehaviour
local applyAvatar = CD.applyCompanionAvatar or CD.applyDogAvatar
local baseSounds = CD.COMPANION_SOUNDS or CD.DOG_SOUNDS
local frGenes = CD.defineGenome and CD.defineGenome("fr") or AnimalDefinitions.genome["dog"].genes

AnimalDefinitions = AnimalDefinitions or {}
AnimalDefinitions.stages = AnimalDefinitions.stages or {}
AnimalDefinitions.breeds = AnimalDefinitions.breeds or {}
AnimalDefinitions.animals = AnimalDefinitions.animals or {}

AnimalDefinitions.stages["fr"] = {}
AnimalDefinitions.stages["fr"].stages = {}
AnimalDefinitions.stages["fr"].stages["frpup"] = {}
AnimalDefinitions.stages["fr"].stages["frpup"].ageToGrow = 1 * 30
AnimalDefinitions.stages["fr"].stages["frpup"].nextStage = "frfemale"
AnimalDefinitions.stages["fr"].stages["frpup"].nextStageMale = "frmale"
AnimalDefinitions.stages["fr"].stages["frmale"] = {}
AnimalDefinitions.stages["fr"].stages["frmale"].ageToGrow = 1 * 30
AnimalDefinitions.stages["fr"].stages["frfemale"] = {}
AnimalDefinitions.stages["fr"].stages["frfemale"].ageToGrow = 1 * 30

AnimalDefinitions.breeds["fr"] = {}
AnimalDefinitions.breeds["fr"].breeds = {}

local COAT_BREEDS = {
    { name = "fr_white", texture = "FRWhite" },
    { name = "fr_grey",  texture = "FRGrey" },
    { name = "fr_hooded", texture = "FRHooded" },
    { name = "fr_naked",  texture = "FRNaked" },
    { name = "fr_brown",  texture = "FRBrown" },
	{ name = "fr_blue",  texture = "FRBlue" },
}
for _, cb in ipairs(COAT_BREEDS) do
    local b = {}
    b.name = cb.name
    b.texture = cb.texture
    b.textureMale = cb.texture
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
    AnimalDefinitions.breeds["fr"].breeds[cb.name] = b
end

local frpup = {}
applyModel(frpup, "FRBody")
applyBehaviour(frpup)
frpup.group = "fr"
frpup.shadoww = 0.10
frpup.shadowfm = 0.10
frpup.shadowbm = 0.10
frpup.minSize = 0.56
frpup.maxSize = 0.9
frpup.wanderMul = 400
frpup.hungerMultiplier = 0.0015
frpup.thirstMultiplier = 0.003
frpup.hungerBoost = 25
frpup.thirstBoost = 30
frpup.baseEncumbrance = 1
frpup.trailerBaseSize = 6
frpup.minEnclosureSize = 15
frpup.needMom = false
frpup.eatFromMother = true
frpup.litterEatTogether = true
frpup.minWeight = 0.05
frpup.maxWeight = 0.15
frpup.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
frpup.breeds = AnimalDefinitions.breeds["fr"].breeds
frpup.stages = AnimalDefinitions.stages["fr"].stages
frpup.genes = frGenes
AnimalDefinitions.animals["frpup"] = frpup

local frfemale = {}
applyModel(frfemale, "FRBody")
applyBehaviour(frfemale)
frfemale.group = "fr"
frfemale.female = true
frfemale.babyType = "frpup"
frfemale.shadoww = 0.14
frfemale.shadowfm = 0.16
frfemale.shadowbm = 0.16
frfemale.minSize = 0.75
frfemale.maxSize = 0.9
frfemale.wanderMul = 500
frfemale.hungerMultiplier = 0.003
frfemale.thirstMultiplier = 0.006
frfemale.hungerBoost = 20
frfemale.thirstBoost = 25
frfemale.baseEncumbrance = 2
frfemale.trailerBaseSize = 8
frfemale.minEnclosureSize = 15
frfemale.minAge = 1 * 30
frfemale.maxAgeGeriatric = 3 * 30
frfemale.minAgeForBaby = 1 * 30
frfemale.timeBeforeNextPregnancy = 3
frfemale.pregnantPeriod = 21
frfemale.minWeight = 0.2
frfemale.maxWeight = 0.4
frfemale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
frfemale.breeds = AnimalDefinitions.breeds["fr"].breeds
frfemale.stages = AnimalDefinitions.stages["fr"].stages
frfemale.genes = frGenes
AnimalDefinitions.animals["frfemale"] = frfemale

local frmale = {}
applyModel(frmale, "FRBody")
applyBehaviour(frmale)
frmale.group = "fr"
frmale.male = true
frmale.babyType = "frpup"
frmale.dontAttackOtherMale = true
frmale.shadoww = 0.14
frmale.shadowfm = 0.16
frmale.shadowbm = 0.16
frmale.minSize = 0.8
frmale.maxSize = 1.0
frmale.wanderMul = 500
frmale.hungerMultiplier = 0.003
frmale.thirstMultiplier = 0.006
frmale.hungerBoost = 20
frmale.thirstBoost = 25
frmale.baseEncumbrance = 2
frmale.trailerBaseSize = 8
frmale.minEnclosureSize = 15
frmale.minAge = 1 * 30
frmale.maxAgeGeriatric = 3 * 30
frmale.minAgeForBaby = 1 * 30
frmale.minWeight = 0.2
frmale.maxWeight = 0.45
frmale.wildFleeTimeUntilDeadTimer = CD.STRAY_NO_BLEEDOUT
frmale.breeds = AnimalDefinitions.breeds["fr"].breeds
frmale.stages = AnimalDefinitions.stages["fr"].stages
frmale.genes = frGenes
AnimalDefinitions.animals["frmale"] = frmale

local fr_sounds = {}
for k, v in pairs(baseSounds) do fr_sounds[k] = v end
fr_sounds.pain     = { name = "CDFRChatter", slot = "voice", priority = 50 }
fr_sounds.death    = { name = "CDFRSqueak",  slot = "voice", priority = 100 }
fr_sounds.pick_up  = { name = "CDFRSqueak",  slot = "voice", priority = 1 }
fr_sounds.put_down = fr_sounds.pick_up
for _, cb in ipairs(COAT_BREEDS) do
    AnimalDefinitions.breeds["fr"].breeds[cb.name].sounds = fr_sounds
end

AnimalAvatarDefinition = AnimalAvatarDefinition or {}
AnimalAvatarDefinition["frpup"] = {}
AnimalAvatarDefinition["frfemale"] = {}
AnimalAvatarDefinition["frmale"] = {}
applyAvatar(AnimalAvatarDefinition["frpup"])
applyAvatar(AnimalAvatarDefinition["frfemale"])
applyAvatar(AnimalAvatarDefinition["frmale"])

local PORTE = 0.4
for _, t in ipairs({ AnimalAvatarDefinition["frpup"], AnimalAvatarDefinition["frfemale"],
                     AnimalAvatarDefinition["frmale"] }) do
    t.zoom = t.zoom / PORTE
    t.trailerZoom = t.trailerZoom / PORTE
    t.xoffset = t.xoffset * PORTE
    t.yoffset = t.yoffset * PORTE
    t.trailerXoffset = t.trailerXoffset * PORTE
    t.trailerYoffset = t.trailerYoffset * PORTE
end
