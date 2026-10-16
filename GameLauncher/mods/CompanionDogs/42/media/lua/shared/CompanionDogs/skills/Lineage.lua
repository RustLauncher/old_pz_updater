CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local GENE_MIN, GENE_MAX = 0.2, 0.6

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

---Breed key -> share of ancestry (0..1); created as 100% of the dog's breed on first call.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return table<string, number> lineage
function CD.getLineage(animal)
    local d = CD.data(animal)
    if not d.lineage then
        d.lineage = { [CD.getBreed(animal)] = 1.0 }
    end
    return d.lineage
end

---More than one breed in the lineage.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return boolean
function CD.isMongrel(animal)
    local n = 0
    for _, v in pairs(CD.getLineage(animal)) do if v and v > 0 then n = n + 1 end end
    return n > 1
end

---Share of each breed as percent and breed name, comma separated, in CD.BREED_ORDER order.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return string
function CD.lineageLabel(animal)
    local lin = CD.getLineage(animal)
    local parts = {}
    for _, k in ipairs(CD.BREED_ORDER) do
        local v = lin[k]
        if v and v > 0 then
            parts[#parts + 1] = tostring(math.floor(v * 100 + 0.5)) .. "% " .. CD.breedNounFromKey(k)
        end
    end
    return table.concat(parts, ", ")
end

---Breed with the largest share; ties go to the first in CD.BREED_ORDER, an empty lineage gives CD.DEFAULT_BREED.
---@param lineage table<string, number> breed key -> share
---@return string breedKey
---@nodiscard
function CD.lineageDominant(lineage)
    local bestK, bestV = nil, -1
    for _, k in ipairs(CD.BREED_ORDER) do
        local v = lineage[k]
        if v and v > bestV then
            bestK, bestV = k, v
        end
    end
    return bestK or CD.DEFAULT_BREED
end

---Random breed weighted by share; CD.DEFAULT_BREED when every share is 0.
---@param lineage table<string, number> breed key -> share
---@return string breedKey
---@nodiscard
function CD.lineageRoll(lineage)
    local total = 0
    for _, v in pairs(lineage) do if v and v > 0 then total = total + v end end
    if total <= 0 then return CD.DEFAULT_BREED end
    local r = (ZombRand(0, 1000000) / 1000000) * total
    local acc = 0
    for _, k in ipairs(CD.BREED_ORDER) do
        local v = lineage[k]
        if v and v > 0 then
            acc = acc + v
            if r <= acc then return k end
        end
    end
    return CD.lineageDominant(lineage)
end

---Mean of the two lineages, normalized to sum 1.
---@param a table<string, number>|nil
---@param b table<string, number>|nil
---@return table<string, number> lineage
---@nodiscard
function CD.blendLineage(a, b)
    a = a or {}
    b = b or {}
    local out, sum = {}, 0
    local keys = {}
    for k in pairs(a) do keys[k] = true end
    for k in pairs(b) do keys[k] = true end
    for k in pairs(keys) do
        local v = ((a[k] or 0) + (b[k] or 0)) * 0.5
        if v > 0 then
            out[k] = v
            sum = sum + v
        end
    end
    if sum > 0 then
        for k, v in pairs(out) do out[k] = v / sum end
    end
    return out
end

---Widest range of the gene across the lineage's breeds; 0, 1 when none declares it.
---@param lineage table<string, number> breed key -> share
---@param gene string
---@return number lo
---@return number hi
---@nodiscard
function CD.lineageGeneRange(lineage, gene)
    local lo, hi
    for k, v in pairs(lineage) do
        if v and v > 0 then
            local def = CD.BREEDS[k]
            local r = def and def.geneRange and def.geneRange[gene]
            if r then
                if lo == nil or r[1] < lo then
                    lo = r[1]
                end
                if hi == nil or r[2] > hi then
                    hi = r[2]
                end
            end
        end
    end
    if lo == nil then return 0, 1 end
    return lo, hi
end

---Per gene, the parents' mean plus a jitter of up to CD.GENE_MUTATION, clamped to the lineage range.
---@param damGenes table<string, number>|nil
---@param sireGenes table<string, number>|nil
---@param lineage table<string, number> the puppy's lineage
---@return table<string, number>|nil genes nil on the client
---@nodiscard
function CD.blendGenes(damGenes, sireGenes, lineage)
    if isClient() then return nil end
    local out, keys = {}, {}
    if damGenes then
        for g in pairs(damGenes) do keys[g] = true end
    end
    if sireGenes then
        for g in pairs(sireGenes) do keys[g] = true end
    end
    local mut = CD.GENE_MUTATION
    for g in pairs(keys) do
        local a = damGenes and damGenes[g]
        local b = sireGenes and sireGenes[g]
        if a == nil then
            a = b
        end
        if b == nil then
            b = a
        end
        local mid = (a + b) * 0.5
        local jitter = (ZombRand(0, 1001) / 1000 - 0.5) * 2 * mut
        local lo, hi = CD.lineageGeneRange(lineage, g)
        out[g] = clamp(mid + jitter, lo, hi)
    end
    return out
end

local function cumulativeXpForLevel(level)
    return CD.SKILL_XP_BASE * level * (level + 1) / 2
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@param skill string
---@return number xp
---@nodiscard
function CD.getSkillXP(animal, skill)
    local s = CD.data(animal).skills
    return (s and s[skill]) or 0
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@param skill string
---@return integer level 0..CD.SKILL_MAX_LEVEL
---@nodiscard
function CD.getSkillLevel(animal, skill)
    local xp = CD.getSkillXP(animal, skill)
    local level = 0
    while level < CD.SKILL_MAX_LEVEL and xp >= cumulativeXpForLevel(level + 1) do
        level = level + 1
    end
    return level
end

---At max level into and need are equal, so the bar reads full.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@param skill string
---@return integer level
---@return number into XP gained inside the current level
---@return number need XP the next level takes
---@nodiscard
function CD.skillProgress(animal, skill)
    local level = CD.getSkillLevel(animal, skill)
    if level >= CD.SKILL_MAX_LEVEL then
        local span = CD.SKILL_XP_BASE * CD.SKILL_MAX_LEVEL
        return level, span, span
    end
    local base = cumulativeXpForLevel(level)
    local need = cumulativeXpForLevel(level + 1) - base
    local into = CD.getSkillXP(animal, skill) - base
    if into < 0 then
        into = 0
    end
    return level, into, need
end

---Server only. Scaled by the breed's xpMult and the sandbox XP rate; a level up transmits and refreshes the kennel.
---@param animal IsoAnimal
---@param skill string
---@param amount number|nil
function CD.addSkillXP(animal, skill, amount)
    if not CD.skillsEnabled() then return end
    if not amount or amount <= 0 then return end
    if isClient() then return end
    if not CD.breedHasSkill(animal, skill) then return end
    if CD.getSkillLevel(animal, skill) >= CD.SKILL_MAX_LEVEL then return end

    local before = CD.getSkillLevel(animal, skill)
    local d = CD.data(animal)
    d.skills = d.skills or {}
    local mult = (CD.getBreedDef(animal).xpMult[skill]) or 1
    d.skills[skill] = (d.skills[skill] or 0) + amount * mult * CD.skillXPRate()
    if CD.getSkillLevel(animal, skill) ~= before then
        CD.transmit(animal)
        local owner = CD.getOwnerPlayer(animal)
        if owner and CD.kennelSnapshot then
            CD.kennelSnapshot(owner, animal)
        end
    end
end

---Raises each skill XP in dst to the one in src where src is higher.
---@param dst table<string, number>|nil skill -> XP
---@param src table<string, number>|nil skill -> XP
function CD.mergeSkillsMax(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for s, b in pairs(src) do
        if type(b) == "number" and b > (dst[s] or 0) then
            dst[s] = b
        end
    end
end

---Server only. Sets the XP to the start of the level, clamped to 0..CD.SKILL_MAX_LEVEL, and transmits.
---@param animal IsoAnimal
---@param skill string|nil
---@param level number
function CD.setSkillLevel(animal, skill, level)
    if isClient() then return end
    if not skill then return end
    if not CD.breedHasSkill(animal, skill) then return end
    level = math.max(0, math.min(tonumber(level) or 0, CD.SKILL_MAX_LEVEL))
    local d = CD.data(animal)
    d.skills = d.skills or {}
    d.skills[skill] = cumulativeXpForLevel(level)
    CD.transmit(animal)
end

---The stored gene, else the engine allele rescaled from 0.2..0.6, else 0.5.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@param gene string
---@return number ratio 0..1
---@nodiscard
function CD.geneRatio(animal, gene)
    local d = CD.data(animal)
    if d.genes and d.genes[gene] ~= nil then return clamp(d.genes[gene], 0, 1) end
    local v
    if instanceof(animal, "IsoAnimal") then
        local allele = animal:getUsedGene(gene)
        if allele then
            v = allele:getCurrentValue()
        end
    end
    if v == nil then return 0.5 end
    return clamp((v - GENE_MIN) / (GENE_MAX - GENE_MIN), 0, 1)
end

local function lvl(animal, skill)
    if not CD.skillsEnabled() then return 0 end
    return CD.getSkillLevel(animal, skill)
end

local function geneDelta(animal, gene)
    if not CD.genomeEffects() then return 0 end
    return CD.geneRatio(animal, gene) - 0.5
end

---Base hit damage scaled by combatPower, the combat level curve and the strength gene; times CD.WEAK_DAMAGE_MULT while weak.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.effectiveHitDamage(animal)
    local curve = CD.getBreedDef(animal).lethalityCurve
    local levelMult
    if curve and CD.skillsEnabled() then
        levelMult = curve.min + (curve.max - curve.min) * (lvl(animal, "combat") / CD.SKILL_MAX_LEVEL)
    else
        levelMult = 1 + 0.05 * lvl(animal, "combat")
    end
    local base = CD.hitDamage() * CD.breedCombatPower(animal) * levelMult
    local dmg = base * (1 + 0.30 * geneDelta(animal, "strength"))
    if CD.isWeak(animal) then
        dmg = dmg * CD.WEAK_DAMAGE_MULT
    end
    return dmg
end

---@param animal IsoAnimal
---@return number chance 0..1, growing with combat level up to CD.KNOCKDOWN_CHANCE_CAP
---@nodiscard
function CD.knockdownChance(animal)
    local chance = CD.KNOCKDOWN_CHANCE_BASE + CD.KNOCKDOWN_CHANCE_PER_LEVEL * lvl(animal, "combat")
    return clamp(chance, 0, CD.KNOCKDOWN_CHANCE_CAP)
end

---@param animal IsoAnimal
---@return number multiplier on the chance of a combat wound, lower with combat level
---@nodiscard
function CD.combatWoundMult(animal)
    return 1 - CD.VET_WOUND_COMBAT_CUT_PER_LEVEL * lvl(animal, "combat")
end

---Stress one strike adds, cut by combat level and the resistance gene.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.effectiveCombatStress(animal)
    local reduction = clamp(0.03 * lvl(animal, "combat") + 0.20 * geneDelta(animal, "resistance"), 0, 0.5)
    local breedMult = CD.getBreedDef(animal).combatStressMult or 1
    return CD.combatStressPerStrike() * (1 - reduction) * CD.stressGeneMult(animal) * breedMult
end

---Up to 50% wider with scent level, times the breed's sentinelMult.
---@param animal IsoAnimal
---@return integer tiles
---@nodiscard
function CD.effectiveSentinelRadius(animal)
    local mult = 1 + 0.05 * lvl(animal, "scent")
    if mult > 1.5 then
        mult = 1.5
    end
    return math.floor(CD.sentinelRadius() * mult * CD.breedNumber(animal, "sentinelMult") + 0.5)
end

---Up to 67% wider with scent level.
---@param animal IsoAnimal
---@return integer tiles
---@nodiscard
function CD.effectiveSniffRadius(animal)
    local mult = 1 + 0.067 * lvl(animal, "scent")
    if mult > 1.67 then
        mult = 1.67
    end
    return math.floor(CD.TRICK_SNIFF_RADIUS * mult + 0.5)
end

---Up to 60% wider with hunt level.
---@param animal IsoAnimal
---@return integer tiles
---@nodiscard
function CD.effectiveHuntRadius(animal)
    local mult = 1 + 0.06 * lvl(animal, "hunt")
    if mult > 1.6 then
        mult = 1.6
    end
    return math.floor(CD.huntRadius() * mult + 0.5)
end

---Stress change for nearby livestock: negative calms; CD.CARE_PREDATOR_STRESS when disloyal or panicked.
---@param animal IsoAnimal
---@return number delta
---@nodiscard
function CD.effectiveCalmStrength(animal)
    if CD.isDisloyal(animal) then return CD.CARE_PREDATOR_STRESS end
    local dogStress = CD.getStress(animal)
    if dogStress >= CD.breedPanicThreshold(animal) then return CD.CARE_PREDATOR_STRESS end
    local l = lvl(animal, "herding")
    if l <= 0 then return 0 end
    local loy = CD.loyalty(animal) / CD.TRUST_MAX
    local breedMult = (CD.getBreedDef(animal).calmMult or 1)
    local calm = CD.CARE_CALM_BASE * (l / CD.SKILL_MAX_LEVEL) * (0.5 + 0.5 * loy) * (1 - dogStress) * breedMult
    return -calm
end

---Stress ceiling, 0..100, the dog holds nearby livestock under; 100 means no cap.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.effectiveCalmCap(animal)
    if CD.isDisloyal(animal) then return 100 end
    if CD.getStress(animal) >= CD.breedPanicThreshold(animal) then return 100 end
    local l = lvl(animal, "herding")
    if l <= 0 then return 100 end
    local loy = CD.loyalty(animal) / CD.TRUST_MAX
    local floor = CD.CARE_CALM_CAP_MIN
    local breedMult = (CD.getBreedDef(animal).calmMult or 1)
    local cap = 100 - (100 - floor) * (l / CD.SKILL_MAX_LEVEL) * (0.5 + 0.5 * loy) * breedMult
    if cap < floor then
        cap = floor
    end
    return cap
end

---Forage radius bonus: half the base bonus at hunt level 0, all of it at max level.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.effectiveForageBonus(animal)
    local l = lvl(animal, "hunt")
    return CD.huntForageRadiusBonus() * (0.5 + 0.5 * l / CD.SKILL_MAX_LEVEL)
end

---Loyalty under which the dog is disloyal: 1.5 lower per obedience level, never under 10.
---@param animal IsoAnimal|table the dog, or the stash proxy
---@return number
---@nodiscard
function CD.effectiveLoyaltyFloor(animal)
    local floor = CD.loyaltyFloor() - 1.5 * lvl(animal, "obedience")
    if floor < 10 then
        floor = 10
    end
    return floor
end

---Combat XP multiplier from the aggressiveness gene, 0.85..1.15.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.combatXPRate(animal)
    return 1 + 0.30 * geneDelta(animal, "aggressiveness")
end

---Stress multiplier from the stress gene, 0.9..1.1.
---@param animal IsoAnimal
---@return number
---@nodiscard
function CD.stressGeneMult(animal)
    return 1 + 0.20 * geneDelta(animal, "stress")
end
