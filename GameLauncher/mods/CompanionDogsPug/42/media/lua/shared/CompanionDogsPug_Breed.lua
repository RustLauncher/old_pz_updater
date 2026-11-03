local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 3) then return end

CD.PUG_HOUSE_RARITY = 1
CD.PUG_PETVET_CHANCE = 12

CD.PUG_RELIEF_MULT = 1.6
CD.PUG_STRESS_PER_MIN = 0.004

CD.PUG_HOT_ENTER = 28
CD.PUG_HOT_FULL = 36
CD.PUG_HEAT_STRESS_MAX = 0.30

---Air temperature in Celsius at the character, or the world temperature when char is nil.
---@param char IsoGameCharacter|nil
---@return number
---@nodiscard
function CD.pugAirTemp(char)
    local cm = getClimateManager()
    if char then return cm:getAirTemperatureForCharacter(char, false) end
    return cm:getTemperature()
end

---How deep the temperature is into the pug heat band, from 0 (below PUG_HOT_ENTER) to 1 (PUG_HOT_FULL or above).
---@param char IsoGameCharacter|nil
---@return number ratio
---@nodiscard
function CD.pugHeatRatio(char)
    local t = CD.pugAirTemp(char)
    local r = (t - CD.PUG_HOT_ENTER) / (CD.PUG_HOT_FULL - CD.PUG_HOT_ENTER)
    if r < 0 then return 0 elseif r > 1 then return 1 end
    return r
end

CD.registerBreed({
    key = "pug",
    engineBreed = "pug",
    typePrefix = "pug",
    nameKey = "IGUI_PD_Breed_pug",
    limpAnim = true,
    bandSkin = { base = "Pug", front = "Pug_BandFront", back = "Pug_BandBack", cutFront = "Pug_CutFront", cutBack = "Pug_CutBack" },
    litter = { 1, 2 },
    xpMult = { scent = 1.5, combat = 1, obedience = 2.0, hunt = 1.2, herding = 1.0 },
    combatPower = 0.15,
    lethalityCurve = { min = 0.40, max = 1.3 },
    canKill = false,
    canKnockdown = false,
    combatStressMult = 0.9,
    panicThreshold = 0.70,
    bagMult = 0.6,
    sentinelMult = 1.35,
    barkNoiseMult = 1.5,
    alertModeLocked = true,
    loyaltyDecayMult = 0,
    geneRange = {
        strength       = { 0.00, 0.10 },
        aggressiveness = { 0.05, 0.20 },
        resistance     = { 0.00, 0.15 },
        stress         = { 0.55, 0.85 },
    },
    -- Os sufixos |pg e |pv sao chave do store de spawn: NUNCA renomear num save vivo.
    spawns = {
        { id = "pughouse", class = "house", suffix = "|pg", breed = "pug",
          chance = function() return CD.strayChancePerHouse() / CD.PUG_HOUSE_RARITY end },
        { id = "pugpetvet", class = "petvet", suffix = "|pv", breed = "pug",
          chance = function() return CD.PUG_PETVET_CHANCE * CD.dogSpawnMultiplier() end },
    },
})
