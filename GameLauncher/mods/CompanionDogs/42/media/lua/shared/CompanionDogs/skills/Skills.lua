CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.SKILLS = { "scent", "combat", "obedience", "hunt", "herding" }
CD.SKILL_MAX_LEVEL = 10
CD.SKILL_XP_BASE = 20

CD.DEFAULT_BREED = "caramelo"
---@type table<string, table> breed key -> definition (same format CD.registerBreed takes)
CD.BREEDS = {
    caramelo = {
        key = "caramelo",
        engineBreed = "brown",
        typePrefix = "dog",
        nameKey = "IGUI_PD_Breed_caramelo",
        limpAnim = true,
        bandSkin = { base = "Caramelo", front = "Caramelo_BandFront", back = "Caramelo_BandBack", cutFront = "Caramelo_CutFront", cutBack = "Caramelo_CutBack" },
        litter = { 2, 4 },
        xpMult = { scent = 1, combat = 1, obedience = 1, hunt = 1, herding = 1 },
        combatPower = 0.2,
        lethalityCurve = { min = 0.40, max = 1.5 },
        canKill = false,
        canKnockdown = true,
        geneRange = {
            strength       = { 0.0, 0.15 },
            aggressiveness = { 0.0, 0.15 },
            resistance     = { 0.0, 0.15 },
            stress         = { 0.85, 1.0 },
        },
    },
    germanshepherd = {
        key = "germanshepherd",
        bandSkin = { base = "GermanShepherd", front = "GermanShepherd_BandFront", back = "GermanShepherd_BandBack", cutFront = "GermanShepherd_CutFront", cutBack = "GermanShepherd_CutBack" },
        engineBreed = "germanshepherd",
        typePrefix = "gs",
        nameKey = "IGUI_PD_Breed_germanshepherd",
        limpAnim = true,
        litter = { 1, 2 },
        xpMult = { scent = 1, combat = 2.0, obedience = 1.5, hunt = 1.2, herding = 1.0 },
        combatPower = 0.6,
        lethalityCurve = { min = 0.40, max = 1.3 },
        canKnockdown = true,
        combatStressMult = 0.20,
        panicThreshold = 0.90,
        geneRange = {
            strength       = { 0.30, 0.50 },
            aggressiveness = { 0.30, 0.50 },
            resistance     = { 0.30, 0.50 },
            stress         = { 0.20, 0.50 },
        },
    },
    retriever = {
        key = "retriever",
        engineBreed = "golden",
        typePrefix = "retriever",
        nameKey = "IGUI_PD_Breed_retriever",
        limpAnim = true,
        bandSkin = { base = "RetrieverPoly", front = "RetrieverPoly_BandFront", back = "RetrieverPoly_BandBack", cutFront = "RetrieverPoly_CutFront", cutBack = "RetrieverPoly_CutBack" },
        litter = { 1, 2 },
        xpMult = { scent = 1.5, combat = 1, obedience = 1.2, hunt = 2.0, herding = 1.0 },
        combatPower = 0.34,
        lethalityCurve = { min = 0.40, max = 1.3 },
        canKill = true,
        canKnockdown = true,
        combatStressMult = 0.33,
        panicThreshold = 0.85,
        geneRange = {
            strength       = { 0.20, 0.40 },
            aggressiveness = { 0.10, 0.30 },
            resistance     = { 0.20, 0.40 },
            stress         = { 0.30, 0.60 },
        },
    },
    husky = {
        key = "husky",
        bandSkin = { base = "Husky", front = "Husky_BandFront", back = "Husky_BandBack", cutFront = "Husky_CutFront", cutBack = "Husky_CutBack" },
        engineBreed = "husky",
        typePrefix = "husky",
        nameKey = "IGUI_PD_Breed_husky",
        limpAnim = true,
        litter = { 1, 2 },
        xpMult = { scent = 2.0, combat = 1.2, obedience = 0.8, hunt = 1.5, herding = 1.0 },
        combatPower = 0.44,
        lethalityCurve = { min = 0.40, max = 1.3 },
        canKill = true,
        canKnockdown = true,
        combatStressMult = 0.6,
        panicThreshold = 0.85,
        bagMult = 1.5,
        geneRange = {
            strength       = { 0.55, 0.80 },
            aggressiveness = { 0.10, 0.30 },
            resistance     = { 0.40, 0.60 },
            stress         = { 0.20, 0.45 },
        },
    },
    bordercollie = {
        key = "bordercollie",
        bandSkin = { base = "BorderCollie", front = "BorderCollie_BandFront", back = "BorderCollie_BandBack", cutFront = "BorderCollie_CutFront", cutBack = "BorderCollie_CutBack" },
        engineBreed = "bordercollie",
        typePrefix = "bc",
        nameKey = "IGUI_PD_Breed_bordercollie",
        limpAnim = true,
        litter = { 1, 3 },
        xpMult = { scent = 1.2, combat = 1, obedience = 1.5, hunt = 1, herding = 2.0 },
        combatPower = 0.34,
        lethalityCurve = { min = 0.40, max = 1.3 },
        canKill = true,
        canKnockdown = true,
        combatStressMult = 0.33,
        panicThreshold = 0.85,
        calmMult = 1.5,
        geneRange = {
            strength       = { 0.20, 0.45 },
            aggressiveness = { 0.15, 0.40 },
            resistance     = { 0.25, 0.50 },
            stress         = { 0.30, 0.60 },
        },
    },
}

---@type string[] CD.BREEDS keys in alphabetical order
CD.BREED_ORDER = {}
for _bk in pairs(CD.BREEDS) do CD.BREED_ORDER[#CD.BREED_ORDER + 1] = _bk end
table.sort(CD.BREED_ORDER)

---The breed's descKey, else IGUI_PD_BreedDesc_ followed by the key.
---@param key string|nil breed key
---@return string translationKey
---@nodiscard
function CD.breedDescKey(key)
    local def = key and CD.BREEDS[key]
    return (def and def.descKey) or ("IGUI_PD_BreedDesc_" .. tostring(key))
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local SEX_SUFFIX = { male = true, female = true, pup = true }

CD.BREED_BY_ENGINE = {}
---Rebuilds CD.BREED_BY_ENGINE, engine breed name -> breed key.
function CD.rebuildEngineIndex()
    local idx = {}
    for key, def in pairs(CD.BREEDS) do
        if def.engineBreed then
            idx[def.engineBreed] = key
        end
    end
    CD.BREED_BY_ENGINE = idx
end
CD.rebuildEngineIndex()

---Breed key from the engine breed, else from the animal type prefix.
---@param animal IsoAnimal|table the stash proxy and other non-animals give nil
---@return string|nil breedKey nil when nothing matches
---@nodiscard
function CD.breedFromType(animal)
    if not instanceof(animal, "IsoAnimal") then return nil end
    local b = animal:getBreed()
    if b then
        local key = CD.BREED_BY_ENGINE[b:getName()]
        if key then return key end
    end
    local t = animal:getAnimalType()
    if not t then return nil end
    for key, def in pairs(CD.BREEDS) do
        local p = def.typePrefix
        if p and string.len(t) > string.len(p)
                and string.sub(t, 1, string.len(p)) == p
                and SEX_SUFFIX[string.sub(t, string.len(p) + 1)] then
            return key
        end
    end
    return nil
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return string breedKey
---@nodiscard
function CD.getBreed(animal)
    local stored = CD.data(animal).breed
    local byType = CD.breedFromType(animal)
    if byType then
        local sdef = stored and CD.BREEDS[stored]
        if not sdef or sdef.typePrefix ~= CD.BREEDS[byType].typePrefix then
            return byType
        end
    end
    return stored or CD.DEFAULT_BREED
end

---Unknown keys are ignored.
---@param animal IsoAnimal
---@param key string breed key
function CD.setBreed(animal, key)
    if CD.BREEDS[key] then
        CD.data(animal).breed = key
    end
end

---Translated breed name; the generic dog name without an animal.
---@param animal IsoAnimal|table|nil the dog, or the stash proxy
---@return string
---@nodiscard
function CD.breedNoun(animal)
    local key = "IGUI_PD_DogDefaultName"
    if animal then
        key = CD.getBreedDef(animal).nameKey
    end
    return getText(key)
end

---Unknown or nil keys give the generic dog name.
---@param breedKey string|nil
---@return string
---@nodiscard
function CD.breedNounFromKey(breedKey)
    local def = breedKey and CD.BREEDS[breedKey]
    if def and def.nameKey then return getText(def.nameKey) end
    return getText("IGUI_PD_DogDefaultName")
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return table def CD.BREEDS entry, never nil
---@nodiscard
function CD.getBreedDef(animal)
    return CD.BREEDS[CD.getBreed(animal)] or CD.BREEDS[CD.DEFAULT_BREED]
end

---@param animal IsoAnimal
---@param field string
---@param fallback number|nil used when the field is not a number; defaults to 1
---@return number
---@nodiscard
function CD.breedNumber(animal, field, fallback)
    local v = CD.getBreedDef(animal)[field]
    if type(v) == "number" then return v end
    return fallback or 1
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@param field string
---@return boolean
---@nodiscard
function CD.breedFlag(animal, field)
    return CD.getBreedDef(animal)[field] == true
end

---The breed's puppySize, else CD.PUPPY_SIZE.
---@param animal IsoAnimal
---@return number scale
---@nodiscard
function CD.puppySize(animal)
    local def = CD.getBreedDef(animal)
    return (def and def.puppySize) or CD.PUPPY_SIZE
end

---Unknown keys give CD.BREED.
---@param key string breed key
---@return string engineBreed
---@nodiscard
function CD.breedEngineName(key)
    local def = CD.BREEDS[key]
    return (def and def.engineBreed) or CD.BREED
end

---Type prefix plus sex, such as gsfemale; unknown or nil keys use the dog prefix.
---@param key string|nil breed key
---@param sex string|nil "male", "female" or "pup"; nil means "male"
---@return string animalType
---@nodiscard
function CD.breedAnimalType(key, sex)
    local def = CD.BREEDS[key]
    return ((def and def.typePrefix) or "dog") .. (sex or "male")
end

---@param key string breed key
---@return string "male" | "female"
---@nodiscard
function CD.rollBreedSex(key)
    local def = CD.BREEDS[key]
    local chance = (def and def.maleChance) or 0.5
    -- Parte por milhao, e nao por cento: o macho do gato tricolor e 1 em 3000, e numa faixa mais
    -- curta o ZombRand inteiro arredondaria essa fatia para cima (em 100, viraria 1 em 100).
    return (ZombRand(0, 1000000) < chance * 1000000) and "male" or "female"
end

---@param key string breed key
---@return boolean
---@nodiscard
function CD.breedSterileMale(key)
    local def = CD.BREEDS[key]
    return def ~= nil and def.sterileMale == true
end

---The breed's combatPower, 1 when undeclared.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.breedCombatPower(animal)
    local p = CD.getBreedDef(animal).combatPower
    return p ~= nil and p or 1
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.breedCanKnockdown(animal)
    return CD.knockdownEnabled() and CD.getBreedDef(animal).canKnockdown == true
end

---True unless the breed declares canKill = false.
---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.breedCanKill(animal)
    return CD.getBreedDef(animal).canKill ~= false
end

---True unless the breed's skills table sets the skill to false.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@param skill string
---@return boolean
---@nodiscard
function CD.breedHasSkill(animal, skill)
    local t = CD.getBreedDef(animal).skills
    return type(t) ~= "table" or t[skill] ~= false
end

---Skills the breed has, in CD.SKILLS order. breedKey is read only without an animal; neither gives every skill.
---@param animal IsoAnimal|table|nil the dog, or the stash proxy
---@param breedKey string|nil
---@return string[]
---@nodiscard
function CD.skillsFor(animal, breedKey)
    local def
    if animal ~= nil then def = CD.getBreedDef(animal)
    elseif breedKey then def = CD.BREEDS[breedKey] end
    local t = def and def.skills
    local out = {}
    for i = 1, #CD.SKILLS do
        local s = CD.SKILLS[i]
        if type(t) ~= "table" or t[s] ~= false then
            out[#out + 1] = s
        end
    end
    return out
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.breedCanFight(animal)
    return CD.breedHasSkill(animal, "combat")
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.breedCanSense(animal)
    return CD.breedHasSkill(animal, "scent")
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.breedCanLearnTricks(animal)
    return CD.breedHasSkill(animal, "obedience")
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.breedCanHunt(animal)
    return CD.breedHasSkill(animal, "hunt")
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
---@nodiscard
function CD.breedCanTendLivestock(animal)
    return CD.breedHasSkill(animal, "herding")
end

---@param animal IsoAnimal
---@param key string one of the CD.VOICE_DEFAULT voices (bark, growl, idle, wildbark, pet, whine, eat, drink)
---@return string|nil soundName
---@nodiscard
function CD.breedVoice(animal, key)
    local t = CD.getBreedDef(animal).voices
    local v = t and t[key]
    if v then return v end
    return CD.VOICE_DEFAULT and CD.VOICE_DEFAULT[key]
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.breedCanBreed(animal)
    local def = CD.getBreedDef(animal)
    if def.canBreed == false then return false end
    return not (def.sterileMale == true and CD.animalSex(animal) == "male")
end

CD.HUNT_PREY_RANK = { tiny = 1, small = 2, large = 3 }

---@param animal IsoAnimal
---@param cls string "tiny" | "small" | "large"
---@return boolean
---@nodiscard
function CD.breedCanHuntClass(animal, cls)
    if not CD.breedCanHunt(animal) then return false end
    local rank = CD.HUNT_PREY_RANK[cls]
    if not rank then return false end
    local max = CD.HUNT_PREY_RANK[CD.getBreedDef(animal).huntMaxPrey] or CD.HUNT_PREY_RANK.large
    return rank <= max
end

---@param animal IsoAnimal
---@param kind string|nil without kind returns the breed's whole distract table
---@return table|nil
---@nodiscard
function CD.breedDistract(animal, kind)
    local t = CD.getBreedDef(animal).distract
    if type(t) ~= "table" then return nil end
    if kind == nil then return t end
    local cfg = t[kind]
    return type(cfg) == "table" and cfg or nil
end

---@param animal IsoAnimal
---@param kind string
---@return number chance 0..1, 0 when the breed does not declare the kind
---@nodiscard
function CD.distractChance(animal, kind)
    local cfg = CD.breedDistract(animal, kind)
    return (cfg and cfg.chance) or 0
end

---Stress at which the dog panics; math.huge for panicImmune breeds.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return number
---@nodiscard
function CD.breedPanicThreshold(animal)
    local def = CD.getBreedDef(animal)
    if def.panicImmune == true then return math.huge end
    return def.panicThreshold or CD.STRESS_PANIC_THRESHOLD
end

---Fills the stored breed and the skills table when missing.
---@param animal IsoAnimal
function CD.initSkills(animal)
    local d = CD.data(animal)
    d.breed = d.breed or CD.breedFromType(animal) or CD.DEFAULT_BREED
    d.skills = d.skills or {}
end

---Rolls the genes once from the breed's geneRange; server only.
---@param animal IsoAnimal
function CD.rollBreedGenes(animal)
    if isClient() then return end
    local d = CD.data(animal)
    if d.genes then return end
    local range = CD.getBreedDef(animal).geneRange
    if not range then return end
    d.genes = {}
    for gene, r in pairs(range) do
        local lo, hi = r[1], r[2]
        d.genes[gene] = clamp(lo + (hi - lo) * (ZombRand(0, 1001) / 1000), 0, 1)
    end

end
