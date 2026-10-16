CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.BREED = "brown"
---@type table<string, boolean> engine animal types the mod treats as dogs
CD.TYPES = { dogpup = true, dogfemale = true, dogmale = true,
             gspup = true, gsfemale = true, gsmale = true,
             retrieverpup = true, retrieverfemale = true, retrievermale = true,
             huskypup = true, huskyfemale = true, huskymale = true,
             bcpup = true, bcfemale = true, bcmale = true }
CD.SPAWN_TYPES = { "dogmale", "dogfemale" }

-- teto do spawn aleatorio do menu de admin
CD.SPAWN_RANDOM_MAX = 50

CD.TRUST_MAX = 100
CD.FEED_TRUST_GAIN = 25
CD.FEED_TRUST_PER_HUNGER = 1.0
CD.TAME_THRESHOLD = 100
CD.TAMED_LOYALTY = 50

CD.GENE_MUTATION = 0.06
CD.GESTATION_DAYS = 4
CD.MATURITY_DAYS = 90
CD.BREED_COOLDOWN_DAYS = 7
CD.BREED_RANGE = 2
-- Fome e sede so barram o cruzamento no critico. Um limite abaixo do aviso de fome (HUNGER_WARN, 0.6)
-- barra o bicho antes de a tela mostrar qualquer coisa, e o par para de conceber parecendo saudavel.
CD.BREED_NEED_CRITICAL = 0.9
CD.BREED_LEASH = 40
CD.BREED_APPROACH_TIMEOUT_MIN = 10
CD.BREED_CHANCE_PER_DAY = 5
CD.BREED_NEARTERM_FRAC = 0.25
CD.PUPPY_BORN_LOYALTY = 50
CD.PUPPY_SIZE = 0.6

CD.STATE_FOLLOW = "follow"
CD.STATE_STAY = "stay"
CD.STATE_GUARD = "guard"
CD.KENNEL_RECALL_COOLDOWN_MIN = 120
CD.KENNEL_MIRROR_MIN = 30
CD.CARRIED_STALE_MS = 60000
CD.GUARD_RADIUS = 10
CD.GUARD_RETURN_DIST = 2
CD.FOLLOW_START_DIST = 2
CD.FOLLOW_RUN_DIST = 6
CD.FOLLOW_KEEP_MIN = 2
CD.FOLLOW_KEEP_MAX = 8
CD.FOLLOW_KEEP_STEP = 0.5
CD.OWNER_INDEX_TTL_MS = 150
CD.TELEPORT_DIST = 24
CD.TELEPORT_BACK_DIST = 2
CD.STAIR_CLIMB_MAX_TRIES = 30
CD.FENCE_HOP_DETECT_DIST = 20
CD.FENCE_HOP_STEP = 0.021
CD.FENCE_HOP_DURATION_MS = 800
CD.FENCE_HOP_ARC = 0.3
CD.FENCE_HOP_TALL = false
CD.FENCE_GHOST_SCAN = 8
CD.FENCE_GHOST_STALL_MS = 400
CD.FENCE_STALL_RADIUS = 0.8
CD.FENCE_HOP_LAND_BLEND = 0.82
CD.FENCE_HOP_MIN_GAIN = 0.05
CD.FENCE_HOP_COOLDOWN_MS = 1500
CD.FENCE_RECROSS_BLOCK_MS = 1500
CD.STEER_RUN_SPEED = 3.6
CD.STEER_WALK_SPEED = 1.8
CD.STEER_MAX_DT_MS = 250
-- Passo normal a 10 tps vai de 0,18 a 0,54 tile; acima disto alguem escreveu a posicao de uma vez.
CD.JUMP_WATCH_TILES = 0.7
-- No servidor a amostra e por tick, e um tick nao dura sempre o mesmo tanto: so a distancia acusaria
-- a corrida normal num tick longo. O veredito la e velocidade, com teto acima da escala cheia do
-- clipe de corrida (RUN_CLIP_RATE, 5,408 tile/s).
CD.JUMP_WATCH_SPEED = 8.0
CD.JUMP_WATCH_MAX_DT_MS = 1000
-- Ponto cego dos dois detectores do client: cada um mede DENTRO do seu regime e comeca do zero no
-- primeiro quadro do seguinte, entao a troca de dono da reproducao nunca era contada por ninguem.
CD.JUMP_YIELD_WATCH_MS = 1500
CD.FENCE_BACKBLOCK_MS = 2000
CD.REGION_TTL_MS = 300
CD.COMBAT_REGION_RADIUS = 12
CD.COMBAT_REGION_MAX_TILES = 700
CD.REGION_REUSE_TILES = 4
CD.TILEKEY_STRIDE = 32768
CD.COMBAT_DETOUR_FACTOR = 1.5
CD.COMBAT_DETOUR_ADD = 2
CD.PROG_EPS = 0.35
CD.FENCE_HOP_REDIRECT = false
CD.FENCE_HOP_MP_BLINK = false
CD.FENCE_HOP_SETTLE_MS = 300
CD.FENCE_LAND_PUSH_MS = 1200
CD.FENCE_LAND_STREAM_MS = 2000
CD.FENCE_STEER_STREAM_MS = 500
CD.FENCE_STEER_DRIVE_MS = 500
CD.FENCE_LAND_USE_STREAM = true
CD.FENCE_LAND_GLIDE = true
CD.FENCE_HOP_MP = true
CD.FENCE_ONLINE_STALL_MS = 150
CD.FALL_GUARD_DEBOUNCE_MS = 150
CD.FALL_RECOVER_COOLDOWN_MS = 1500
-- Fogo mata em dezenas de segundos; 3 ticks de atraso na restauracao e na fuga nao mudam nada.
CD.FIRE_GUARD_TICKS = 3
CD.TELEPORT_JUMP_MIN = 6
CD.TELEPORT_BRING_TRIES = 300
CD.RV_INTERIOR_MIN_X = 22500
CD.RV_INTERIOR_MIN_Y = 12000
CD.PHANTOM_LOST_GRACE_MIN = 3
CD.RECALL_OVERRIDE_MIN = 1
CD.AUTO_PROTECT_WINDOW_MIN = 5
CD.AUTO_PROTECT_ACTIONS = {
    ISReadABook = true,
    ISEatFoodAction = true,
    ISFishingAction = true,
}
CD.ZOMBIE_ATTACK_RADIUS = 8
CD.FOLLOW_DEFEND_RADIUS = 5
CD.FOLLOW_DEFEND_DROP = 8
CD.COMPANION_TICK_INTERVAL = 20
CD.FOLLOW_TICK_INTERVAL = 2
CD.DOG_REG_TICKS = 5
CD.DOG_REG_RECONCILE_MS = 2000
CD.DOG_REG_MAX_AGE_MS = 250
CD.DOG_REG_STALE_MS = 2000
-- Caixa de relevancia da engine: alem disso o client nao tem o animal carregado.
CD.EMIT_RANGE = 96
CD.GHOST_SCAN_RADIUS = 2
