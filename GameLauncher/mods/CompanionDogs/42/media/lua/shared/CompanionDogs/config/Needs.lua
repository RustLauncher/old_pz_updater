CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.GROWL_SOUND = "CDDogGrowl"
CD.PET_SOUND = "CDDogPet"
CD.BARK_COOLDOWN_MS = 9000

CD.WILD_BARK_ENABLED = true
CD.WILD_BARK_SOUND = "CDDogBarkAmbient"
CD.WILD_BARK_MIN_SEC = 120
CD.WILD_BARK_MAX_SEC = 260
CD.WILD_BARK_RADIUS = 35

CD.SOUND_CATEGORY = {
    CDDogBark = "bark", CDDogGrowl = "bark",
    CDDogIdle = "bark", CDDogWhine = "bark", CDDogDeath = "bark", CDDogPickup = "bark",
    ZombieBite = "fx", CDDogEat = "fx", CDDogDrink = "fx", CDDogPet = "fx",
    CDDogBarkAmbient = "ambient",
}
CD.SOUND_CATEGORIES = { "bark", "fx", "ambient" }

CD.SOUND_NONBANK = {
    CDDogBark = true, CDDogBarkAmbient = true, CDDogGrowl = true, CDDogWhine = true, CDDogIdle = true,
    CDDogPickup = true, CDDogPet = true, CDDogDeath = true, CDDogEat = true, CDDogDrink = true,
}
CD.SOUND_LOOPED = { CDDogEat = true, CDDogDrink = true }

-- Alcance audivel em tiles, espelho do distanceMax de sounds_companiondogs.txt: mexeu num, mexe no outro.
CD.SOUND_RANGE = {
    CDDogBark = 30, CDDogBarkAmbient = 30, CDDogDeath = 25, CDDogWhine = 15, CDDogGrowl = 12,
    CDDogPet = 12, CDDogIdle = 10, CDDogEat = 10, CDDogDrink = 10, CDDogPickup = 8,
    -- Evento de banco, atenuacao propria do FMOD: aqui o numero so escolhe quem recebe o pacote.
    ZombieBite = 20, ChickenCoopWoodClose = 15, ChickenCoopWoodOpen = 15,
}
CD.SOUND_RANGE_BY_CAT = { bark = 30, fx = 12, ambient = 30 }
CD.SOUND_RANGE_DEFAULT = 30
-- Folga pro jitter de posicao entre servidor e client: o cao anda entre o envio e a chegada.
CD.SOUND_RANGE_MARGIN = 8

---@param sound string
---@return number tiles
function CD.soundRange(sound)
    local r = CD.SOUND_RANGE[sound]
    if r then return r end
    local cat = CD.SOUND_CATEGORY[sound]
    return (cat and CD.SOUND_RANGE_BY_CAT[cat]) or CD.SOUND_RANGE_DEFAULT
end

CD.SOUND_DEBUG = false

CD.ENGINE_VOICES = { "CDDogWhine", "CDDogDeath", "CDDogPickup" }

CD.IDLE_VOICE_ENABLED = true
CD.IDLE_VOICE_SOUND = "CDDogIdle"
CD.IDLE_VOICE_MIN_SEC = 100
CD.IDLE_VOICE_MAX_SEC = 110
CD.IDLE_VOICE_RADIUS = 12
-- Voz ociosa e contentamento: bufo de cao satisfeito, ronronado de gato. Vira-lata nao tem por que
-- fazer isso, e escondido dentro de casa a cada 100s vira zumbido de fundo. Ele fica so com o ambiente.
CD.IDLE_VOICE_STRAYS = false

CD.VOICE_DEFAULT = {
    bark     = CD.BARK_SOUND,
    growl    = CD.GROWL_SOUND,
    idle     = CD.IDLE_VOICE_SOUND,
    wildbark = CD.WILD_BARK_SOUND,
    pet      = CD.PET_SOUND,
    whine    = "CDDogWhine",
    eat      = "CDDogEat",
    drink    = "CDDogDrink",
}

---@param map table<string, string> sound name -> volume category
---@param engineVoices string[]|nil engine sounds the player's mute also silences
---@param ranges table<string, number>|nil sound name -> audible range in tiles (mirror of distanceMax)
function CD.registerVoices(map, engineVoices, ranges)
    if type(map) ~= "table" then return end
    for name, cat in pairs(map) do
        CD.SOUND_CATEGORY[name] = cat
        CD.SOUND_NONBANK[name] = true
    end
    if type(ranges) == "table" then
        for name, r in pairs(ranges) do
            CD.SOUND_RANGE[name] = r
        end
    end
    if type(engineVoices) == "table" then
        for i = 1, #engineVoices do
            CD.ENGINE_VOICES[#CD.ENGINE_VOICES + 1] = engineVoices[i]
        end
    end
end

CD.ATTACK_ANIM_ENABLED = true
CD.ATTACK_ANIM_VAR = "cdAttack"
CD.ATTACK_ANIM_VARS = { "cdAttack", "cdAttack2", "cdAttack3" }
CD.ATTACK_ANIM_MS = 1200
CD.EAT_ANIM_VAR = "cdEat"
CD.DRINK_ANIM_VAR = "cdDrink"
CD.SNIFF_ANIM_VAR = "cdSniff"
CD.JUMP_ANIM_VAR = "cdJump"
CD.HANDFEED_EAT_MS = 3000
CD.REST_ANIM_ENABLED = true
CD.REST_ANIM_VAR     = "cdRest"
-- Poses de descanso sorteadas na entrada. A raca troca a lista por `restPoses` no def; cada entrada
-- pode trazer `enter` / `exit` (pulso de transicao) e `variation` (pulsos ao longo da pausa).
CD.REST_POSES        = { { var = CD.REST_ANIM_VAR } }
CD.REST_DWELL_MIN    = 1.0
CD.REST_REASSERT_MIN = 2.0
CD.IDLE_ANIM_ENABLED  = true
CD.IDLE_ANIM_VARS     = { "cdIdle2", "cdIdle3" }
CD.IDLE_ANIM_MS       = 4200
CD.IDLE_GAP_MIN_MS    = 9000
CD.IDLE_GAP_MAX_MS    = 22000
CD.FEED_BY_HAND_ANIM = "AnimalLureLow"

CD.SENTINEL_RADIUS = 18
CD.SENTINEL_QUIET_RADIUS = 10
CD.SENTINEL_SEEN_DIST = 12
CD.SENTINEL_CLOSE_DIST = 6
CD.SENTINEL_ALARM_COUNT = 3
CD.SENTINEL_SCAN_INTERVAL_MS = 1800
CD.SENTINEL_AWARE_COOLDOWN_MS = 75000
CD.SENTINEL_NOISE_COOLDOWN_MS = 22500
CD.SENTINEL_ALERT_HOLD_MS = 7500
CD.SENTINEL_ALARM_BARK_COOLDOWN_MS = 75000
CD.SENTINEL_BARK_RADIUS = 16
CD.SENTINEL_BARK_VOLUME = 6
CD.SENTINEL_BAND_CLOSE = 7
CD.SENTINEL_BAND_NEAR = 13
-- Sem esta margem um zumbi parado em cima da fronteira alterna de faixa a cada varredura e
-- dispara um transmitModData a cada 1,8 s.
CD.SENTINEL_BAND_HYST = 1

CD.SCAN_QUIET_STREAK = 4
CD.SCAN_QUIET_SKIP_MAX = 3
CD.UNREACH_PRUNE_MIN = 10

CD.UPKEEP_INTERVAL_MIN = 3
CD.LOYALTY_DECAY_PER_DAY = 12
CD.NEGLECT_MULT = 3
CD.LOYALTY_FLOOR = 30
CD.FEED_LOYALTY_GAIN = 15
CD.FEED_HUNGER_RESTORE = 0.5
CD.WATER_THIRST_RESTORE = 0.5
CD.FEED_HEALTH_BONUS = 0.10
CD.TOXIC_LOYALTY_PENALTY = 20
CD.TOXIC_TRUST_PENALTY = 15
CD.TOXIC_STRESS = 0.3
CD.TOXIC_SICK_MIN = 120
CD.TOXIC_SICK_HEALTH_FLOOR = 0.2
CD.TOXIC_SICK_DRAIN_PER_DAY = 9.6
CD.FEED_MIN_BITE = 0.05
CD.HUNGER_PER_DAY = 0.30
CD.THIRST_PER_DAY = 0.60
CD.NEGLECT_HEALTH_LOSS_PER_DAY = 3.0
CD.SEVERE_NEED = 0.8
CD.UPKEEP_MAX_CATCHUP_MIN = 360
CD.HUNGER_WARN = 0.6
CD.THIRST_WARN = 0.6
CD.STRESS_W_HUNGER = 0.5
CD.STRESS_W_THIRST = 0.3
CD.STRESS_W_HEALTH = 0.4
CD.STRESS_W_LOYALTY = 0.3
CD.STRESS_BARK_THRESHOLD = 0.5
CD.STRESS_PANIC_THRESHOLD = 0.80
CD.PANIC_TIER1_FRAC = 0.50
CD.PANIC_TIER3_FRAC = 1.00
CD.TROUGH_FEED_TRIGGER = 0.5
CD.TROUGH_FEED_RADIUS = 16
CD.TROUGH_REACH_DIST = 0.85
CD.TROUGH_HUNGER_RESTORE = 0.5
CD.TROUGH_THIRST_RESTORE = 0.5
-- LITROS: removeWater() do IsoFeedingTrough vai direto pro FluidContainer, nao e a escala 0..100 da tigela.
-- A UI do bebedouro mostra x1000, entao 0.25 aparece pro jogador como 250 mL de um tanque de 50000 mL.
CD.TROUGH_WATER_PER_DRINK = 0.25
CD.TROUGH_EAT_DWELL_MIN = 3
CD.TROUGH_SCAN_THROTTLE_MS = 2000
CD.TROUGH_REPATH_STALL_MS = 1200
CD.TROUGH_GIVEUP_STALL_MS = 15000
CD.TROUGH_RETRY_COOLDOWN_MS = 45000
CD.TROUGH_PROGRESS_EPS = 0.25
CD.FEED_COMMAND_YIELD_MIN = 5
CD.FEED_MISS_TOLERANCE = 3
CD.TROUGH_EAT_TYPES = { AnimalFeed = true, Grass = true, Hay = true, Vegetables = true, Fruits = true, DogFood = true }
CD.TROUGH_EAT_ITEMS = { ["Base.DogfoodOpen"] = true, ["Base.DogFoodBag"] = true }
CD.TROUGH_FOOD_PORTION = 0.1
CD.DISH_TYPE = "Base.CompanionDogsBowl"
CD.DISH_MAX_MEALS = 100
CD.DISH_MAX_WATER = 100
-- LITROS tirados da fonte para encher a tigela. Junto com DISH_POINTS_PER_THIRST fecha a conta:
-- 1 L rende 4 bebidas de 250 mL, o mesmo que o cao gasta por bebida no bebedouro vanilla.
CD.DISH_WATER_SOURCE_DRAIN = 1.0
CD.DISH_POINTS_PER_THIRST = 50
CD.DISH_FLUID_FOOD = "CompanionDogsKibble"
CD.DISH_FLUID_WATER = "CompanionDogsBowlWater"
-- posicao no WorldStaticModelsByIndex do item (companiondogs_bowl.txt); vazia fica no pote de racao
CD.DISH_MODEL_FOOD = 0
CD.DISH_MODEL_WATER = 1
CD.STRAY_SCAVENGE_TRIGGER = 0.7
CD.STRAY_SCAVENGE_FORCE = 0.78
CD.STRAY_SCAVENGE_CHANCE = 40
CD.STRAY_SCAVENGE_LEVEL = 0.15
CD.STRESS_BARK_RADIUS = 30
CD.STRESS_BARK_VOLUME = 9
CD.STRESS_BARK_COOLDOWN_MIN = 60
CD.REFUSE_WARN_COOLDOWN_MIN = 3

CD.WOUNDED_ENTER_FRAC = 0.30
CD.WOUNDED_EXIT_FRAC = 0.40
CD.CRITICAL_ENTER_FRAC = 0.10
CD.CRITICAL_EXIT_FRAC = 0.20
CD.HEALTH_REGEN_PER_DAY = 3.0
CD.HEALTH_REGEN_NEED_MAX = 0.5

CD.PET_MOOD_RELIEF = 2
CD.PET_COOLDOWN_MIN = 90
CD.PET_STRESS_RELIEF = 0.10
CD.PET_LOYALTY_GAIN = 2
CD.PET_CALM_RELIEF = 0.25
CD.PET_CALM_DURATION_MIN = 180
CD.SLEEP_MOOD_RELIEF = 2
CD.SLEEP_NEAR_RADIUS = 8

CD.RESTED_BUFF_DURATION_MIN = 120
CD.RESTED_PANIC_PER_MIN = 1.0
CD.RESTED_STRESS_PER_MIN = 0.006
CD.RESTED_FATIGUE_PER_MIN = 0.0025
CD.RESTED_MOOD_PER_MIN = 1.0

CD.GRIEF_SHOCK_MAX = 65
CD.GRIEF_SHOCK_MIN = 20
CD.GRIEF_MAX_MIN = 2880
CD.GRIEF_MIN_MIN = 240
CD.GRIEF_SYNC_MIN = 60

CD.MOODLE_HAPPY_RADIUS = 8
CD.MOODLE_HAPPY_RADIUS_EXIT = 12
CD.MOODLE_GRACE_MIN = 10
CD.MOODLE_RELIEF_PER_MIN = 1.5
CD.MOODLE_TICK_MIN = 0.5
CD.MOODLE_ELAPSED_CAP = 10
CD.MOODLE_NEGLECT_MAX = 0.75
CD.COURAGE_PANIC_RELIEF_PER_MIN = 3
CD.GOLDEN_XP_MULT = 1.2
CD.GOLDEN_FORAGE_VISION_EXTRA = 4
CD.HUSKY_WARMTH_TEMP = 12
CD.HUSKY_WARMTH_RADIUS = 3
CD.HUSKY_COLD_ENTER = 37.0
CD.HUSKY_COLD_EXIT = 37.4
CD.HUSKY_STRENGTH_XP_MULT = 1.5
CD.HUSKY_ENDURANCE_PER_MIN = 0.001
CD.COLLIE_XP_MULT = 1.2
CD.COLLIE_CALM_RADIUS = 8
CD.COLLIE_CALM_THROTTLE_MIN = 2
CD.COLLIE_CALM_MAX_HERD = 12

CD.COMBAT_XP_PER_STRIKE = 1
CD.COMBAT_XP_PER_KILL = 5
CD.SCENT_XP_PER_DETECT = 1
CD.OBEDIENCE_XP_PER_CMD = 2
CD.OBEDIENCE_XP_COOLDOWN_MIN = 5
CD.OBEDIENCE_EARLY_LEVEL = 3
CD.OBEDIENCE_EARLY_MULT = 4
CD.SKILL_XP_RATE = 0.5

CD.OBEY_FAIL_BASE = 0.30
CD.OBEY_FAIL_PER_LEVEL = 0.03
CD.OBEY_LOCK_MS = 2000
CD.OBEY_FAIL_GRACE_MS = 8000

CD.PROTEIN_MAX_HOURS = 72
CD.PROTEIN_MEAL_POINTS = 20
CD.WEAK_DAMAGE_MULT = 0.50
CD.WEAK_OBEY_FAIL_ADD = 0.25

CD.TRICK_XP_COOLDOWN_MIN = 60
CD.TRICK_GOTO_MAX_DIST = 30
CD.TRICK_GOTO_TIMEOUT_MIN = 15
CD.TRICK_GOTO_STALL_MS = 1500
CD.WALK_HIJACK_GRACE_MS = 600
CD.WALK_GIVEUP_MS = 4500
CD.WALK_UNREACHABLE_TOL = 2
CD.TRICK_GOTO_ARRIVE_DIST = 0.4
CD.DEBUG_TRICK_GOTO = false
CD.TRICK_DISTRACT_RADIUS = 24
CD.TRICK_DISTRACT_VOLUME = 8
CD.TRICK_DISTRACT_COOLDOWN_MIN = 10
CD.TRICK_DISTRACT_STRESS = 0.08
CD.TRICK_DISTRACT_RECALL_MIN = 3
CD.TRICK_DISTRACT_TAG_MIN = 10
CD.TRICK_SNIFF_RADIUS = 12
CD.TRICK_SNIFF_SCAN_MIN = 1
CD.TRICK_SNIFF_CONTAINER_BUDGET = 60
CD.TRICK_SNIFF_SCAN_BUDGET = 500
CD.TRICK_SNIFF_SCAN_RESET_DIST = 6
CD.TRICK_SNIFF_TICK_QUOTA = 1500
CD.TRICK_SNIFF_SCAN_JITTER = 0.35
CD.TRICK_SNIFF_TIMEOUT_MIN = 10
CD.TRICK_SNIFF_RETRY_MIN = 20
CD.TRICK_SNIFF_TAG_TTL_MIN = 6
CD.TRICK_SNIFF_TAG_BEAT_MIN = 5
CD.TRICK_SNIFF_DWELL_MIN = 2
CD.TRICK_SNIFF_HOLD_DIST = 22
CD.TRICK_SNIFF_RECHECK_MIN = 1
CD.TRICK_SNIFF_NEAR_ENOUGH = 4.0
CD.TRICK_SNIFF_HOLD_SLACK = 4.0
CD.TRICK_SNIFF_POSE_MS = 2000
CD.SNIFF_HIGHLIGHT_TICK_MS = 1000
CD.SNIFF_HIGHLIGHT_R = 0.35
CD.SNIFF_HIGHLIGHT_G = 0.95
CD.SNIFF_HIGHLIGHT_B = 0.45
CD.SNIFF_HIGHLIGHT_A = 0.75
CD.DEBUG_TRICK_SNIFF = CD.DEBUG_ALL
