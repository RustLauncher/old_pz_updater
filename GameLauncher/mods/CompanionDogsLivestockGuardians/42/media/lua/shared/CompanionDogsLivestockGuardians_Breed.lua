local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 5) then return end

local function registerGuardian(definition)
    definition.litter = { 5, 10 }
    definition.xpMult = { scent = 1, combat = 2.0, obedience = 1.5, hunt = 1.2, herding = 1.0 }
    definition.combatPower = 0.6
    definition.lethalityCurve = { min = 0.40, max = 1.3 }
    definition.canKnockdown = true
    definition.combatStressMult = 0.20
    definition.panicThreshold = 0.90
    definition.bagMult = 1.5
    definition.puppySize = 0.6
    definition.geneRange = {
        strength = { 0.30, 0.50 },
        aggressiveness = { 0.30, 0.50 },
        resistance = { 0.30, 0.50 },
        stress = { 0.20, 0.50 },
    }
    CD.registerBreed(definition)
end

registerGuardian({
    key = "anatolianshepherd",
    engineBreed = "anatolianshepherd",
    typePrefix = "anatolian",
    nameKey = "IGUI_PD_Breed_anatolianshepherd",
})

registerGuardian({
    key = "greaterswissmountaindog",
    engineBreed = "greaterswissmountaindog",
    typePrefix = "greaterswiss",
    nameKey = "IGUI_PD_Breed_greaterswissmountaindog",
})
