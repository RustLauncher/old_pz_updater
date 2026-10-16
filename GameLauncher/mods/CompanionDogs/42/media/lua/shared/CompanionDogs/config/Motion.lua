CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.PERF_DEBUG_SECS = 20
CD.PERF_LEVEL = 1
CD.PERF_CSV = false
CD.PERF_BUCKET_MS = 1000
CD.PERF_CSV_MAX_MIN = 30
CD.PERF_CSV_MAX_ROWS = 2000000
CD.PERF_SPIKE_MS = 25
CD.log("dog registry: " ..
       ((CD.DOG_REG == false) and "OFF (A/B baseline, sweeps the world per query)" or "ON") ..
       " | measurement: " .. (CD.PERF_DEBUG and "ON" or "off"))
CD.FOLLOW_REPATH_MS = 250

CD.FOLLOW_COMMIT_MS = 0
CD.FOLLOW_DWELL_MS = 1000
CD.FOLLOW_REPATH_LEAD = 2.5
CD.FOLLOW_GOAL_DRIFT = 3.0

CD.FOLLOW_STALL_EPS = 0.05
CD.FOLLOW_STALL_REPATH_MS = 600
CD.FOLLOW_PATH_RESOLVE_MS = 1500

CD.FOLLOW_STEER = true
CD.FOLLOW_STEER_ARM_DIST = 2.5
CD.FOLLOW_STEER_MAX_DIST = 12
CD.FOLLOW_STEER_WALK_SPEED = 1.90
CD.FOLLOW_STEER_RUN_SPEED = 5.40
CD.FOLLOW_STEER_LOS_MS = 300
CD.FOLLOW_STEER_PROBE_TILES = 5
CD.FOLLOW_STEER_MIN_CLEAR = 1.5
CD.FOLLOW_STEER_STALL_MS = 700
CD.FOLLOW_STEER_STALL_EPS = 0.05
CD.FOLLOW_STEER_COOLDOWN_MS = 2000
CD.FOLLOW_STEER_RETRY_MS = 400
CD.FOLLOW_STEER_DRIVE_MS = 500
CD.FOLLOW_STEER_WALK_RATE = 1.60
CD.FOLLOW_STEER_RUN_RATE = 5.408

CD.STUCK_TELEPORT_ENABLE = true
CD.STUCK_TELEPORT_MS = 10000
CD.STUCK_RECENT_FAIL_MS = 2500
CD.STUCK_TELEPORT_COOLDOWN_MS = 3000
CD.MP_DENSE_FOLLOW_SYNC = true
CD.DENSE_SYNC_MS = 50
CD.DENSE_SYNC_MIN_MOVE = 0.02
CD.DOOR_NAV_REFRESH = true
CD.DOOR_REFRESH_SCAN = 3
CD.DOOR_REFRESH_SCAN_MS = 750
CD.DOOR_REFRESH_COOLDOWN_MS = 8000
CD.FOLLOW_STREAM = true
CD.FOLLOW_STREAM_MS = 50
CD.FOLLOW_STREAM_RANGE = 40
CD.FOLLOW_INTERP_DELAY_MS = 100
CD.FOLLOW_STREAM_TIMEOUT_MS = 500
CD.FOLLOW_STREAM_BUF = 20
CD.FOLLOW_EXTRAP_MAX_MS = 80
-- Teto de caes por quadro: o quadro e uma string so.
CD.FOLLOW_STREAM_MAX_DOGS = 12

-- Autoridade de posicao no client do dono: enquanto vale, o servidor nao conduz nem pathea o cao.
CD.NET_AUTHORITY = true
CD.NET_AUTH_GRANT_DIST = 20
CD.NET_AUTH_REVOKE_DIST = 30
CD.NET_AUTH_REGRANT_MS = 2000
-- Posse mais curta que isto conta como flapping e escala o degelo; mais longa zera a conta.
CD.NET_AUTH_FLAP_MS = 1500
CD.NET_AUTH_MISS_DECAY_MS = 15000
CD.NET_AUTH_REGRANT_MAX_MS = 6000
-- Tempo sem o followOwner passar pela ficha antes de dar o cao por abandonado.
CD.NET_AUTH_SEEN_MS = 1500
CD.NET_AUTH_TIMEOUT_MS = 700
CD.NET_AUTH_REPORT_MS = 200
CD.NET_AUTH_IDLE_REPORT_MS = 400
-- Cao que nenhum OUTRO jogador ve reporta MULT vezes mais devagar. Multiplicador, nao valor fixo:
-- assim o knob de idle do painel continua mandando no caso comum em vez de ser contornado.
CD.NET_AUTH_LONE_MULT = 5
CD.NET_AUTH_LONE_MAX_MS = 3000
CD.NET_AUTH_LONE_CHECK_MS = 1000
-- Aviso fora de hora quando o cao andou tanto assim desde o ultimo: limita o atraso da copia do
-- servidor no ESPACO, o que cadencia por tempo sozinha nao faz.
CD.NET_AUTH_REPORT_STEP = 2.0
-- Piso do aviso fora de hora (troca de marcha). Sem ele o gatilho vira uma torneira por quadro.
CD.NET_AUTH_FORCE_MIN_MS = 120
-- Trava de sanidade do report.
CD.NET_AUTH_MAX_SPEED = 8.0
CD.NET_AUTH_MAX_JUMP = 3.0
-- Quanto o servidor espera a posicao final depois de revogar por conta propria. A copia dele pode
-- estar ate NET_AUTH_REPORT_STEP atras, e mandar o pacote nativo antes da devolucao chegar joga o cao
-- de volta esse tanto na tela do dono.
CD.NET_AUTH_YIELD_WAIT_MS = 250
-- Acima disto a divergencia entre posicao pretendida e real e teleporte, nao empurrao do mover.
CD.STEER_ABS_RESYNC = 2.0
CD.NET_AUTH_STALL_MS = 700
CD.NET_AUTH_STALL_EPS = 0.02
CD.OWNER_STILL_EPS = 0.10
CD.OWNER_STILL_MS = 450
CD.WALK_ANIM_SPEED = 6.03
CD.RUN_ANIM_SPEED = 3.82
CD.PATH_WALK_SCALE = 0.939
CD.PATH_RUN_SCALE = 1.00
CD.PATH_RUN_CRUISE_SCALE = 0.598
CD.PATH_RUN_SPRINT_SCALE = 0.727
-- Vira-lata e cao passivo: 3.43 tile/s, 5% acima da corrida do player (3.267). A escala cheia daria
-- 5.408, 65% acima da corrida do dono.
CD.PATH_RUN_IDLE_SCALE = 0.634
-- Perseguicao em combate, alvo 3.9 tile/s (o sprint do player). Sem escala propria o combate herdaria
-- a escala cheia do upkeep e o cao dispararia de zumbi em zumbi. O valor NAO sai de RUN_CLIP_RATE, e
-- e um por lado, porque a base do node nao e a mesma: no DEDICADO o servidor avanca o clipe ~1.6x
-- (fpsMultiplier inflado e animacao de personagem invisivel em passos de 5 ticks) e o node entrega
-- ~7.4 tile/s por unidade de escala, medido pela e2e (salto.node.cheia); em SP e host o cao esta na
-- tela e a base e o root motion do GLB, 4.62. Quem le e CD.combatRunScale().
CD.COMBAT_RUN_SCALE = 0.85
CD.COMBAT_RUN_SCALE_DED = 0.53
CD.NET_GAIT_HOLD_MS = 250
CD.RUN_CLIP_RATE = 5.408
CD.CRUISE_MARGIN = 0.99
CD.OWNER_SPEED_SMOOTH = 0.3
CD.TRAILER_RECOVER_MAX_RETRIES = 5

CD.GUN_RISK_RADIUS = 10
CD.GUN_GUARD_HOLD_TICKS = 12
CD.GUN_GUARD_SWEEP_TICKS = 3
CD.GUN_GUARD_RESCAN_TICKS = 30
CD.SHOUT_LOCK_GUN_RANGE = 100
CD.GUN_AIM_HINT_TTL = 120

CD.STRIKE_DIST = 1.5

-- Re-emissao de caminho no combate. Cada pathToCharacter cancela o A* pendente, entao o gatilho e o
-- CAMINHO, nao o tile do zumbi: um alvo que anda troca de tile toda passada e o caminho nunca resolve.
CD.COMBAT_REPATH_MS = 400
CD.COMBAT_REPATH_LEAD = 1.5
CD.COMBAT_GOAL_DRIFT = 2.0
CD.COMBAT_PATH_RESOLVE_MS = 900
CD.COMBAT_STALL_EPS = 0.05
CD.COMBAT_STALL_REPATH_MS = 600
CD.HIT_DAMAGE = 0.6
CD.SUBLETHAL_HEALTH_FLOOR = 0.1
CD.ZDMG_STALE_MS = 7500
CD.HIT_COOLDOWN_MS = 900
CD.KNOCKDOWN_COOLDOWN_MS = 1800
CD.KNOCKDOWN_CHANCE_BASE = 0.10
CD.KNOCKDOWN_CHANCE_PER_LEVEL = 0.04
CD.KNOCKDOWN_CHANCE_CAP = 0.50
CD.RETREAT_HEALTH_FRAC = 0.1
CD.COMBAT_INITIATIVE = false
CD.ATTACK_COMMAND_WINDOW_MIN = 2
CD.ATTACK_COMMAND_RADIUS = 12
CD.COMBAT_STALL_MS = 2500
CD.COMBAT_STALL_RADIUS = 2.5
CD.COMBAT_UNREACH_MS = 12000
CD.COMBAT_FENCE_HOP = true
CD.COMBAT_FENCE_HOP_MP = true
CD.COMBAT_STRESS_PER_STRIKE = 0.025
CD.COMBAT_STRESS_RECOVERY_PER_DAY = 12
CD.RETREAT_BACK_DIST = 3
CD.RETREAT_MIN_DURATION_MS = 1800
CD.BITE_SOUND = "ZombieBite"
CD.BARK_SOUND = "CDDogBark"
