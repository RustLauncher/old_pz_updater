CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@return table|nil options the CompanionDogs page of SandboxVars
---@nodiscard
function CD.sandbox()
    return SandboxVars.CompanionDogs
end

---@return integer trust a stray must reach to be tamed
---@nodiscard
function CD.tameThreshold()
    local sv = CD.sandbox()
    return (sv and sv.TameThreshold) or CD.TAME_THRESHOLD
end

---@return integer limit pets per player, 0 for no limit
---@nodiscard
function CD.maxCompanions()
    local sv = CD.sandbox()
    return (sv and sv.MaxCompanions) or 0
end

---@return boolean
---@nodiscard
function CD.breedingEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.BreedingEnabled ~= false
end

---@return boolean
---@nodiscard
function CD.tripOverDogs()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.TripOverDogs ~= false
end

---@return number minutes
---@nodiscard
function CD.gestationMinutes()
    local sv = CD.sandbox()
    local days = (sv and sv.GestationDays) or CD.GESTATION_DAYS
    return days * 24 * 60
end

---Wait after a litter before the mother can breed again.
---@return number minutes
---@nodiscard
function CD.breedCooldownMinutes()
    return (CD.BREED_COOLDOWN_DAYS or 7) * 24 * 60
end

---@return integer days a puppy takes to grow up
---@nodiscard
function CD.maturityDays()
    local sv = CD.sandbox()
    return (sv and sv.MaturityDays) or CD.MATURITY_DAYS
end

---@return number minutes
---@nodiscard
function CD.maturityMinutes()
    return CD.maturityDays() * 24 * 60
end

---@return number chance in percent per day that an eligible female conceives on her own
---@nodiscard
function CD.breedChancePerDay()
    local sv = CD.sandbox()
    return (sv and sv.BreedChancePerDay) or CD.BREED_CHANCE_PER_DAY
end

---@return number trust a stray gains from food with no hunger value
---@nodiscard
function CD.feedTrustGain()
    return CD.FEED_TRUST_GAIN
end

---@return number trust gained per 0.01 of hunger the food restores; loyalty for a pet
---@nodiscard
function CD.feedTrustPerHunger()
    return CD.FEED_TRUST_PER_HUNGER
end

---@return boolean
---@nodiscard
function CD.combatEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.CombatEnabled ~= false
end

---Base strike damage, already scaled by the sandbox damage multiplier.
---@return number
---@nodiscard
function CD.hitDamage()
    local sv = CD.sandbox()
    local mult = (sv and sv.DogDamageMultiplier) or 1
    return CD.HIT_DAMAGE * mult
end

---@return boolean always true
---@nodiscard
function CD.knockdownEnabled()
    return true
end

---@return number ms
---@nodiscard
function CD.knockdownCooldownMs()
    return CD.KNOCKDOWN_COOLDOWN_MS
end

---@return number fraction of full health at or below which a fighting dog retreats
---@nodiscard
function CD.retreatHealthFrac()
    return CD.RETREAT_HEALTH_FRAC
end

---@return number value for the animalSpeed animation variable while running
---@nodiscard
function CD.runAnimSpeed()
    return CD.RUN_ANIM_SPEED
end

---@return number value for the animalSpeed animation variable while walking
---@nodiscard
function CD.walkAnimSpeed()
    return CD.WALK_ANIM_SPEED
end

-- A base do node de corrida no dedicado e outra (ver Motion.lua), por isso o knob e por lado.
---@return number
---@nodiscard
function CD.combatRunScale()
    if isServer() then return CD.COMBAT_RUN_SCALE_DED end
    return CD.COMBAT_RUN_SCALE
end

---Writes both gait scale variables as given, without the wound penalty.
---@param animal IsoAnimal
---@param runScale number
---@param walkScale number
function CD.setGaitScaleRaw(animal, runScale, walkScale)
    animal:setVariable("cdWalkScale", walkScale)
    animal:setVariable("cdRunScale", runScale)
end

-- Unico escritor da escala de marcha: a penalidade de ferida entra aqui e vale para os dois VMs.
-- Quem ja recebe a escala pronta pelo stream usa setGaitScaleRaw, senao a copia remota paga duas vezes.
---@param memo table|nil last written pair per animal object; when given, an identical rewrite is skipped
function CD.applyGaitScale(animal, runScale, walkScale, d, memo)
    if not animal then return end
    local wm, rm = CD.vetGaitMult(d or CD.data(animal))
    local run = (runScale or CD.PATH_RUN_SCALE or 1.0) * (rm or wm)
    local walk = (walkScale or CD.PATH_WALK_SCALE or 0.939) * wm
    if memo then
        -- Par numerico, nao string: converter dois floats por cao por passe custava mais que a escrita.
        local m = memo[animal]
        if m then
            if m[1] == run and m[2] == walk then return end
            m[1], m[2] = run, walk
        else
            memo[animal] = { run, walk }
        end
        CD.perfCount("gait.write")
    end
    CD.setGaitScaleRaw(animal, run, walk)
end

---On, a dog engages nearby zombies without waiting for its owner to fight.
---@return boolean
---@nodiscard
function CD.combatInitiative()
    return CD.COMBAT_INITIATIVE
end

---@return number minutes an attack order stays active
---@nodiscard
function CD.attackCommandWindowMin()
    return CD.ATTACK_COMMAND_WINDOW_MIN
end

---@return boolean always true
---@nodiscard
function CD.allowDebugSpawn()
    return true
end

---In MP only an admin passes; in SP only with the game's debug mode on.
---@param player IsoPlayer|nil checked in MP; nil means the local player
---@return boolean
---@nodiscard
function CD.debugAllowed(player)
    if not CD.allowDebugSpawn() then return false end
    if isClient() or isServer() then
        local adm = false
        local p = player
        if not p then
            p = getPlayer()
        end
        if p then
            adm = string.lower(tostring(p:getAccessLevel() or "")) == "admin"
        else
            adm = isAdmin()
        end
        return adm
    end
    local dbg = getDebug()
    return dbg
end

---@return boolean
---@nodiscard
function CD.upkeepEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.UpkeepEnabled ~= false
end

---Always off while upkeep is off.
---@return boolean
---@nodiscard
function CD.vetCareEnabled()
    if not CD.upkeepEnabled() then return false end
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.VetCareEnabled ~= false
end

---Every character knows the herbal recipes from the start. Off, only the Home Vet magazine teaches them.
---@return boolean
---@nodiscard
function CD.vetRecipesUnlocked()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.VetRecipesUnlocked ~= false
end

---Death by illness or neglect. Off, the default, every drain stops at VET_SAFE_HEALTH_FLOOR and
---nothing in the mod kills the pet; on, health goes to zero and the upkeep permadeath fires.
---@return boolean
---@nodiscard
function CD.deathEnabled()
    local sv = CD.sandbox()
    if sv == nil then return false end
    return sv.Death == true
end

---@param key string sandbox option name, a percent
---@param default number percent used when the option is absent
---@return number chance 0..1
local function sandboxChance(key, default)
    local sv = CD.sandbox()
    local pct = sv and sv[key]
    if pct == nil then
        pct = default
    end
    if pct < 0 then
        pct = 0
    end
    return pct / 100
end

---@return number chance 0..1 that a bite leaves the dog wounded
---@nodiscard
function CD.vetWoundChance()
    return sandboxChance("VetWoundChance", CD.VET_WOUND_CHANCE_PCT)
end

---@return number chance 0..1 that a fence hop sprains a paw
---@nodiscard
function CD.vetSprainChance()
    return sandboxChance("VetSprainChance", CD.VET_SPRAIN_HOP_PCT)
end

---@return number chance 0..1 that an upset stomach also brings worms
---@nodiscard
function CD.vetWormsChance()
    return sandboxChance("VetWormsChance", CD.VET_WORMS_CHANCE_PCT)
end

---@return number chance 0..1 that stale food or tainted water upsets the stomach; rotten food is
---always certain, whatever this says
---@nodiscard
function CD.vetSpoiledChance()
    return sandboxChance("VetSpoiledChance", CD.VET_GASTRO_SPOIL_PCT)
end

---@return number chance 0..1 that the dog catches the flu, on the daily starvation roll and on each
---hour of contact with a sick dog alike
---@nodiscard
function CD.vetFluChance()
    return sandboxChance("VetFluChance", CD.VET_FLU_CHANCE_PCT)
end

---@return number chance 0..1 that six straight hours outdoors bring heartworm disease
---@nodiscard
function CD.vetHeartwormChance()
    return sandboxChance("VetHeartwormChance", CD.VET_HW_EXPO_PCT)
end

---@return number chance 0..1 that the dog carries a lifelong meat allergy, rolled once per dog on its
---first vet pass
---@nodiscard
function CD.vetAllergyChance()
    return sandboxChance("VetAllergyChance", CD.VET_ALG_PROTEIN_PCT)
end

---@return number chance 0..1 that a landed bite brings fleas or ticks
---@nodiscard
function CD.vetInfestChance()
    return sandboxChance("VetInfestChance", CD.VET_INFEST_COMBAT_PCT)
end

---@return number loyalty lost per day, before neglect and breed multipliers
---@nodiscard
function CD.loyaltyDecayPerDay()
    local sv = CD.sandbox()
    return (sv and sv.LoyaltyDecayPerDay) or CD.LOYALTY_DECAY_PER_DAY
end

---@return number multiplier on hunger and thirst gain
---@nodiscard
function CD.needsRateMultiplier()
    local sv = CD.sandbox()
    return (sv and sv.NeedsRateMultiplier) or 1.0
end

---@return number hunger gained per day on the 0..1 scale, already scaled by the sandbox
---@nodiscard
function CD.hungerPerDay()
    return CD.HUNGER_PER_DAY * CD.needsRateMultiplier()
end

---@return number thirst gained per day on the 0..1 scale, already scaled by the sandbox
---@nodiscard
function CD.thirstPerDay()
    return CD.THIRST_PER_DAY * CD.needsRateMultiplier()
end

---@return number loyalty under which a dog turns disloyal, before its obedience level lowers it
---@nodiscard
function CD.loyaltyFloor()
    return CD.LOYALTY_FLOOR
end

---@return number hunger removed by food with no hunger value
---@nodiscard
function CD.feedHungerRestore()
    return CD.FEED_HUNGER_RESTORE
end

---@return number thirst removed when the owner gives water
---@nodiscard
function CD.waterThirstRestore()
    return CD.WATER_THIRST_RESTORE
end

---@param owner IsoPlayer|nil whose own setting replaces the default
---@return number hunger or thirst level at which the dog looks for food or water, 0..1
---@nodiscard
function CD.troughFeedTrigger(owner)
    if owner then
        local md = owner:getModData()
        local v = md and md.cdFeedTrigger
        if type(v) == "number" then return v end
    end
    return CD.TROUGH_FEED_TRIGGER
end

---@return number tiles the dog searches for a trough or bowl
---@nodiscard
function CD.troughFeedRadius()
    return CD.TROUGH_FEED_RADIUS
end

---@return number hunger removed per meal at a trough, bowl or caught prey
---@nodiscard
function CD.troughHungerRestore()
    return CD.TROUGH_HUNGER_RESTORE
end

---@return number thirst removed per drink at a trough or bowl
---@nodiscard
function CD.troughThirstRestore()
    return CD.TROUGH_THIRST_RESTORE
end

---A breed opts out with restAnim = false.
---@param animal IsoAnimal|nil without an animal returns the mod default
---@return boolean
---@nodiscard
function CD.restAnimEnabled(animal)
    if animal then
        local def = CD.getBreedDef(animal)
        if def and def.restAnim == false then return false end
    end
    return CD.REST_ANIM_ENABLED
end

---The breed's own restPoses list when it declares a non-empty one.
---@param animal IsoAnimal|nil without an animal returns the mod default
---@return table[] poses each with var and optional enter, exit and variation
---@nodiscard
function CD.restPoses(animal)
    if animal then
        local def = CD.getBreedDef(animal)
        local v = def and def.restPoses
        if type(v) == "table" and #v > 0 then return v end
    end
    return CD.REST_POSES
end

---A breed may override it with a number or with a table keyed by variable.
---@param animal IsoAnimal|nil without an animal returns the mod default
---@param var string animation variable of the pulse
---@return number ms
---@nodiscard
function CD.idleAnimMs(animal, var)
    if animal then
        local def = CD.getBreedDef(animal)
        local v = def and def.idleAnimMs
        if type(v) == "table" then
            v = v[var]
        end
        if type(v) == "number" then return v end
    end
    return CD.IDLE_ANIM_MS
end

---Admin switch in the tuning window.
---@return boolean
---@nodiscard
function CD.huntEnabled()
    return CD.HUNT_ENABLED ~= false
end

---@return number tiles prey scan radius, before the hunt skill bonus
---@nodiscard
function CD.huntRadius() return CD.HUNT_RADIUS end
---@return number tiles a hunting dog may range from its owner
---@nodiscard
function CD.huntMaxLeash() return CD.HUNT_MAX_LEASH end
---@return integer level hunt skill a dog needs to engage tiny and small prey
---@nodiscard
function CD.huntSmallLevel() return CD.HUNT_SMALL_LEVEL end
---@return integer level hunt skill a dog needs to engage large prey
---@nodiscard
function CD.huntLargeLevel() return CD.HUNT_LARGE_LEVEL end
---@return boolean always true
---@nodiscard
function CD.huntFetchEnabled() return true end
---@param animal IsoAnimal|nil without an animal returns the mod default
---@return integer level
---@nodiscard
function CD.huntFetchLevel(animal)
    if animal then
        local def = CD.getBreedDef(animal)
        local lvl = def and def.huntFetchLevel
        if lvl then return lvl end
    end
    return CD.HUNT_FETCH_LEVEL
end
---@param animal IsoAnimal|nil without an animal returns the mod default
---@return number minutes
---@nodiscard
function CD.huntDeliverTimeout(animal)
    if animal then
        local def = CD.getBreedDef(animal)
        local t = def and def.huntDeliverTimeoutMin
        if t then return t end
    end
    return CD.HUNT_DELIVER_TIMEOUT_MIN
end
---@return boolean always false
---@nodiscard
function CD.huntAutonomyEnabled() return false end
---@return integer level hunt skill from which a dog left on stay in hunt mode hunts on its own
---@nodiscard
function CD.huntAutonomyLevel() return CD.HUNT_AUTONOMY_LEVEL end
---@return boolean always true
---@nodiscard
function CD.huntDeerCanHurtDog() return true end
---@return number combat stress a dog takes when a deer hurts it, on the 0..1 scale
---@nodiscard
function CD.huntDeerDogStress() return CD.HUNT_DEER_DOG_STRESS end
---@return number hunger a kill or a hit on large prey adds, on the 0..1 scale
---@nodiscard
function CD.huntHungerPerHunt() return CD.HUNT_HUNGER_PER_HUNT end
---@return boolean always true
---@nodiscard
function CD.huntBarkAttracts() return true end
---@return number multiplier on hunt skill XP
---@nodiscard
function CD.huntXPRate() return CD.HUNT_XP_RATE end
---@return boolean always true
---@nodiscard
function CD.huntForageBonusEnabled() return true end
---@return number forage vision bonus before the hunt skill scaling
---@nodiscard
function CD.huntForageRadiusBonus() return CD.HUNT_FORAGE_RADIUS_BONUS end
---@return number fraction added to the forage category bonus of animal finds
---@nodiscard
function CD.huntForageCategoryBonus() return CD.HUNT_FORAGE_CATEGORY_BONUS end
---@return boolean always true
---@nodiscard
function CD.huntForagePointEnabled() return true end

---@return boolean
---@nodiscard
function CD.fetchRarityEnabled() return CD.FETCH_RARITY ~= false end

---@return boolean
---@nodiscard
function CD.tricksEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.TricksEnabled ~= false
end

---@return boolean always true
---@nodiscard
function CD.obedienceFailureEnabled()
    return true
end

---@return boolean
---@nodiscard
function CD.proteinNeedEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.ProteinNeedEnabled ~= false
end

---Meat debt at which the dog turns weak.
---@return number minutes
---@nodiscard
function CD.proteinMaxMinutes()
    local sv = CD.sandbox()
    local h = sv and sv.ProteinHours
    if type(h) ~= "number" or h <= 0 then
        h = CD.PROTEIN_MAX_HOURS or 72
    end
    return h * 60
end

---The FarmCareEnabled sandbox option: dogs may tend penned livestock.
---@return boolean
---@nodiscard
function CD.careEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.FarmCareEnabled ~= false
end
---@return number tiles a dog tending livestock scans for zombies
---@nodiscard
function CD.careRadius() return CD.CARE_RADIUS end
---@return number minutes between calming passes over the herd
---@nodiscard
function CD.careCalmThrottleMin() return CD.CARE_CALM_THROTTLE_MIN end
---@return number minutes between livestock alerts to the owner
---@nodiscard
function CD.careAlertCooldownMin() return CD.CARE_ALERT_COOLDOWN_MIN end

---@return number health added per meal
---@nodiscard
function CD.feedHealthBonus()
    return CD.FEED_HEALTH_BONUS
end

---@return boolean always true
---@nodiscard
function CD.woundedEnabled()
    return true
end

---@return number health fraction at or below which the dog turns wounded
---@nodiscard
function CD.woundedEnterFrac()
    return CD.WOUNDED_ENTER_FRAC
end

---@return number health fraction at or above which the dog stops being wounded
---@nodiscard
function CD.woundedExitFrac()
    return CD.WOUNDED_EXIT_FRAC
end

---@return number health fraction at or below which the dog turns critical
---@nodiscard
function CD.criticalEnterFrac()
    return CD.CRITICAL_ENTER_FRAC
end

---@return number health fraction at or above which the dog leaves critical
---@nodiscard
function CD.criticalExitFrac()
    return CD.CRITICAL_EXIT_FRAC
end

---@return number health regained per day when fed and watered
---@nodiscard
function CD.healthRegenPerDay()
    return CD.HEALTH_REGEN_PER_DAY
end

---@return number hunger or thirst level at which health regen stops
---@nodiscard
function CD.healthRegenNeedMax()
    return CD.HEALTH_REGEN_NEED_MAX
end

---@return number combat stress per strike the dog lands, before skill, gene and breed cuts
---@nodiscard
function CD.combatStressPerStrike()
    return CD.COMBAT_STRESS_PER_STRIKE
end

---@return number combat stress recovered per day out of combat
---@nodiscard
function CD.combatStressRecoveryPerDay()
    return CD.COMBAT_STRESS_RECOVERY_PER_DAY
end

---@return boolean always false
---@nodiscard
function CD.stressBarkEnabled()
    return false
end

---@return boolean
---@nodiscard
function CD.noiseAttractsZombies()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.DogNoiseAttractsZombies ~= false
end

---Same switch as noiseAttractsZombies.
---@return boolean
---@nodiscard
function CD.stressAttractsZombies()
    return CD.noiseAttractsZombies()
end

---@return boolean
---@nodiscard
function CD.sentinelEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.SentinelEnabled ~= false
end

---@return boolean always true
---@nodiscard
function CD.autoProtectEnabled()
    return true
end

---Same switch as noiseAttractsZombies.
---@return boolean
---@nodiscard
function CD.sentinelBarkAttracts()
    return CD.noiseAttractsZombies()
end

---@return number tiles zombie scan radius, before the scent skill and breed multipliers
---@nodiscard
function CD.sentinelRadius()
    return CD.SENTINEL_RADIUS
end

---@return number tiles the sentinel scans in quiet alert mode
---@nodiscard
function CD.sentinelQuietRadius()
    return CD.SENTINEL_QUIET_RADIUS
end

---@return boolean
---@nodiscard
function CD.bondingEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.BondingEnabled ~= false
end

---@return number unhappiness and boredom the owner loses per petting
---@nodiscard
function CD.petMoodRelief()
    return CD.PET_MOOD_RELIEF
end

---@return number minutes between pettings
---@nodiscard
function CD.petCooldownMin()
    return CD.PET_COOLDOWN_MIN
end

---@return number unhappiness and boredom the owner loses on waking next to the pet
---@nodiscard
function CD.sleepMoodRelief()
    return CD.SLEEP_MOOD_RELIEF
end

---@return number tiles that count as sleeping next to the pet
---@nodiscard
function CD.sleepNearRadius()
    return CD.SLEEP_NEAR_RADIUS
end

---@return boolean
---@nodiscard
function CD.restedBuffEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.RestedBuffEnabled ~= false
end

---@return number minutes
---@nodiscard
function CD.restedBuffDurationMin()
    local sv = CD.sandbox()
    local h = sv and sv.RestedBuffHours
    if type(h) ~= "number" or h <= 0 then return CD.RESTED_BUFF_DURATION_MIN end
    return h * 60
end

---@return boolean always true
---@nodiscard
function CD.dogMoodlesEnabled()
    return true
end

---@return boolean
---@nodiscard
function CD.breedMoodlesEnabled()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.BreedMoodlesEnabled ~= false
end

---Grief of an owner who lost a pet; both values grow with its loyalty.
---@param loyalty number|nil the lost pet's loyalty
---@return number shock unhappiness added at once, fading as the grief runs out
---@return number minutes how long the grief lasts
---@nodiscard
function CD.griefFor(loyalty)
    local frac = (loyalty or 0) / (CD.TRUST_MAX or 100)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local shock = CD.GRIEF_SHOCK_MIN + frac * (CD.GRIEF_SHOCK_MAX - CD.GRIEF_SHOCK_MIN)
    local mins = CD.GRIEF_MIN_MIN + frac * (CD.GRIEF_MAX_MIN - CD.GRIEF_MIN_MIN)
    return shock, mins
end

---@return number minutes between grief syncs to the server
---@nodiscard
function CD.griefSyncMin()
    return CD.GRIEF_SYNC_MIN
end

---@return number tiles the pet must be within for its proximity moodles and bonuses
---@nodiscard
function CD.moodleHappyRadius()
    return CD.MOODLE_HAPPY_RADIUS
end

---Radius at which the proximity moodles drop; never smaller than moodleHappyRadius.
---@return number tiles
---@nodiscard
function CD.moodleHappyRadiusExit()
    local r = CD.MOODLE_HAPPY_RADIUS_EXIT or CD.MOODLE_HAPPY_RADIUS
    if r < CD.MOODLE_HAPPY_RADIUS then return CD.MOODLE_HAPPY_RADIUS end
    return r
end

---@return number minutes the proximity moodles linger after the pet leaves range
---@nodiscard
function CD.moodleGraceMin()
    return CD.MOODLE_GRACE_MIN or 10
end

---@return number
---@nodiscard
function CD.moodleReliefPerMin()
    return CD.MOODLE_RELIEF_PER_MIN
end

---@return number panic the owner loses per minute under the courage moodle
---@nodiscard
function CD.couragePanicReliefPerMin()
    return CD.COURAGE_PANIC_RELIEF_PER_MIN
end

---@return number XP multiplier the retriever moodle gives its owner
---@nodiscard
function CD.goldenXPMult()
    return CD.GOLDEN_XP_MULT
end

---@return number forage vision bonus a nearby retriever adds
---@nodiscard
function CD.goldenForageVisionExtra()
    return CD.GOLDEN_FORAGE_VISION_EXTRA
end

---@return number Strength XP multiplier the husky moodle gives its owner
---@nodiscard
function CD.huskyStrengthXPMult()
    return CD.HUSKY_STRENGTH_XP_MULT
end

---@return number XP multiplier the border collie moodle gives its owner
---@nodiscard
function CD.collieXPMult()
    return CD.COLLIE_XP_MULT
end

---@return number tiles of the border collie's passive calming
---@nodiscard
function CD.collieCalmRadius()
    return CD.COLLIE_CALM_RADIUS
end

---@return number minutes between passive calming passes
---@nodiscard
function CD.collieCalmThrottleMin()
    return CD.COLLIE_CALM_THROTTLE_MIN
end

---@return boolean always true
---@nodiscard
function CD.skillsEnabled()
    return true
end

---@return boolean always true
---@nodiscard
function CD.genomeEffects()
    return true
end

---@return number multiplier on all pet skill XP
---@nodiscard
function CD.skillXPRate()
    local sv = CD.sandbox()
    return (sv and sv.SkillXPRate) or CD.SKILL_XP_RATE
end

---@return boolean
---@nodiscard
function CD.showNameTags()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.ShowNameTags ~= false
end

---@return boolean always true
---@nodiscard
function CD.showMapMarker()
    return true
end

---The player's own text setting; true where the client settings are not loaded.
---@return boolean
---@nodiscard
function CD.showNotifications()
    if CD.Settings then return CD.Settings.getShowTexts() end
    return true
end

---@return boolean
---@nodiscard
function CD.urbanSpawnEnabled()
    return CD.URBAN_SPAWN_ENABLED
end

---@return boolean
---@nodiscard
function CD.wildDogsInvincible()
    local sv = CD.sandbox()
    if sv == nil then return false end
    return sv.WildDogsInvincible == true
end

---@return boolean always true
---@nodiscard
function CD.countDogKillsForPlayer()
    return true
end

---@return boolean
---@nodiscard
function CD.despawnOnOwnerOffline()
    local sv = CD.sandbox()
    if sv == nil then return true end
    return sv.DespawnOnOwnerOffline ~= false
end

---@return number multiplier >= 0, the sandbox DogSpawnMultiplier
---@nodiscard
function CD.dogSpawnMultiplier()
    local sv = CD.sandbox()
    local m = sv and sv.DogSpawnMultiplier
    if m == nil then
        m = 1.0
    end
    if m < 0 then
        m = 0
    end
    return m
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.strayChancePerHouse()
    return CD.STRAY_CHANCE_PER_HOUSE * CD.dogSpawnMultiplier()
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.policeShepherdChance()
    return CD.POLICE_SHEPHERD_CHANCE * CD.dogSpawnMultiplier()
end

---@return number divisor >= 1 applied to the house stray chance
---@nodiscard
function CD.goldenStrayRarity()
    local r = CD.GOLDEN_STRAY_RARITY
    if r < 1 then
        r = 1
    end
    return r
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.goldenStrayChance()
    return CD.strayChancePerHouse() / CD.goldenStrayRarity()
end

---@return boolean
---@nodiscard
function CD.isWinter()
    local id = -1
    local cm = getClimateManager() or ClimateManager.getInstance()
    if cm then
        id = cm:getSeasonId()
    end
    return id == 5
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.huskyStrayChance()
    return CD.HUSKY_WINTER_CHANCE * CD.dogSpawnMultiplier()
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.huskyPetVetChance()
    return (CD.HUSKY_PETVET_CHANCE or 10) * CD.dogSpawnMultiplier()
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.farmBorderChance()
    return (CD.FARM_BORDER_CHANCE or 15) * CD.dogSpawnMultiplier()
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.rareHouseChance()
    return CD.RARE_HOUSE_CHANCE * CD.dogSpawnMultiplier()
end

---@return number chance in percent, already scaled by the sandbox
---@nodiscard
function CD.huskyHouseChance()
    return CD.HUSKY_HOUSE_CHANCE * CD.dogSpawnMultiplier()
end

---Admin switch in the tuning window.
---@return boolean
---@nodiscard
function CD.passiveIdleEnabled()
    return CD.PASSIVE_IDLE_ENABLED ~= false
end

---The owner's setting counts from LOITER_RADIUS_MIN and is capped at LOITER_RADIUS_MAX.
---@param owner IsoPlayer|nil whose own setting replaces the default
---@return integer tiles an idle dog wanders from its anchor
---@nodiscard
function CD.passiveIdleRadius(owner)
    if owner then
        local md = owner:getModData()
        local v = md and md.cdLoiterRadius
        if type(v) == "number" and v >= CD.LOITER_RADIUS_MIN then
            return math.floor(math.min(v, CD.LOITER_RADIUS_MAX))
        end
    end
    return CD.LOITER_RADIUS
end
