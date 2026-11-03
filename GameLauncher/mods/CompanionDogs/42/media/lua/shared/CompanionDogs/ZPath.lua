CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Diagnostico: o pathing do cao piora com zumbi perto? Janela curta por cao e resumo acumulado por
-- faixa de densidade. No servidor mede a rota real; no client de MP, o que o jogador ve.

local NEAR_R, FAR_R = 5, 12
local ZSCAN_MS = 500
local SEG_MIN = 0.35
local MOVE_SPEED = 0.3
local JUMP_TILES, JUMP_SPEED = 0.7, 8.0
local HANDOFF_MS = 1500
local MAX_DT_MS = 1000
local STALE_MS = 10000

local BUCKET_ORDER = { "0", "1-3", "4-8", "9+" }
local SRV_MODES = { "posse", "seguir", "conduz", "trava", "combate", "golpe", "recuo", "cerca", "outro" }
local CLI_MODES = { "posse", "stream", "nativo" }
local SUM_KEYS = { "anda", "liq", "rev", "salto", "saltoTroca", "vira", "should", "stuck", "tranco", "troca",
                   "emitN", "cancel", "alvo", "inalc", "falha", "som", "gsom", "colis", "n", "dtSum", "dtN" }

local recs = {}
local buckets = { srv = {}, cli = {} }
local nextSumMs = nil

local function newWin(now)
    return { t0 = now, n = 0, anda = 0, liq = 0, rev = 0, salto = 0, saltoTroca = 0, vira = 0,
             should = 0, stuck = 0, tranco = 0, troca = 0, mode = {},
             zn = 0, z5 = 0, z12 = 0, zmax = 0, caca = 0,
             emit = {}, emitN = 0, cancel = 0, alvo = 0, inalc = 0, falha = 0,
             som = 0, gsom = 0, colis = 0, est = {}, dtN = 0, dtSum = 0, dtMax = 0 }
end

local function ratio(a, b)
    if b <= 0 then return 0 end
    return a / b
end

local function tortStr(anda, liq)
    if liq < 0.1 then return "-" end
    return string.format("%.1f", anda / liq)
end

local function bucketOf(z12)
    if z12 < 0.5 then return "0" end
    if z12 < 3.5 then return "1-3" end
    if z12 < 8.5 then return "4-8" end
    return "9+"
end

local function modeStr(modes, order)
    local total = 0
    for _, ms in pairs(modes) do total = total + ms end
    if total <= 0 then return "-" end
    local parts = {}
    for _, m in ipairs(order) do
        local ms = modes[m]
        if ms and ms > 0 then
            parts[#parts + 1] = string.format("%s:%.2f", m, ms / total)
        end
    end
    return table.concat(parts, " ")
end

local function emitStr(emit)
    local parts = {}
    for k, c in pairs(emit) do
        parts[#parts + 1] = string.format("%s:%d", k, c)
    end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, " ") .. ")"
end

local function estStr(est, n)
    if n <= 0 then return "" end
    local parts = {}
    for name, c in pairs(est) do
        local short = string.gsub(string.gsub(name, "^Animal", ""), "State$", "")
        parts[#parts + 1] = string.format("%s:%.2f", short, c / n)
    end
    if #parts == 0 then return "" end
    return " est=" .. table.concat(parts, ",")
end

-- O deslocamento liquido soma trechos continuos: posse do client e salto quebram o trecho, senao o
-- que o cao nao andou por conta propria entraria no liquido e nao no percorrido.
local function breakRun(f, w)
    if f.runX and f.x then
        local dx, dy = f.x - f.runX, f.y - f.runY
        w.liq = w.liq + math.sqrt(dx * dx + dy * dy)
    end
    f.runX = nil
end

local function moveSample(f, w, x, y, dt, should, now, drive)
    if not drive or not f.x or dt <= 0 or dt > MAX_DT_MS then
        breakRun(f, w)
        f.x, f.y = x, y
        f.segX, f.segY, f.dirX, f.dirY, f.moving = x, y, nil, nil, nil
        if drive then
            f.runX, f.runY = x, y
        end
        return
    end
    local dx, dy = x - f.x, y - f.y
    local step = math.sqrt(dx * dx + dy * dy)
    local v = step * 1000 / dt
    if step >= JUMP_TILES and v >= JUMP_SPEED then
        w.salto = w.salto + 1
        if f.swapMs and (now - f.swapMs) <= HANDOFF_MS then
            w.saltoTroca = w.saltoTroca + 1
        end
        breakRun(f, w)
        f.x, f.y, f.runX, f.runY = x, y, x, y
        f.segX, f.segY, f.dirX, f.dirY = x, y, nil, nil
        return
    end
    if not f.runX then
        f.runX, f.runY = f.x, f.y
    end
    f.x, f.y = x, y
    w.anda = w.anda + step
    local moving = v >= MOVE_SPEED
    if should then
        w.should = w.should + dt
        if not moving then
            w.stuck = w.stuck + dt
            if f.moving then
                w.tranco = w.tranco + 1
            end
        end
    end
    f.moving = moving
    local sx, sy = x - f.segX, y - f.segY
    local sl = math.sqrt(sx * sx + sy * sy)
    if sl >= SEG_MIN then
        local ux, uy = sx / sl, sy / sl
        if f.dirX and (ux * f.dirX + uy * f.dirY) < -0.5 then
            w.rev = w.rev + 1
        end
        f.dirX, f.dirY, f.segX, f.segY = ux, uy, x, y
    end
end

local function faceSample(f, w, animal)
    local fd = animal:getForwardDirection()
    local fx, fy = fd:getX(), fd:getY()
    if f.fx and (fx * f.fx + fy * f.fy) < 0 then
        w.vira = w.vira + 1
    end
    f.fx, f.fy = fx, fy
end

local function modeSample(f, w, mode, dt, now)
    if dt > 0 and dt <= MAX_DT_MS then
        w.mode[mode] = (w.mode[mode] or 0) + dt
    end
    if f.curMode and f.curMode ~= mode then
        w.troca = w.troca + 1
        f.swapMs = now
    end
    f.curMode = mode
end

-- Varredura propria: o CD.zsnap guarda cache por CD.zseq, que nao anda no client, e sobrescreveria o
-- CD.zbox que o combate usa no mesmo tick.
local function countZombies(animal, owner)
    local cell = getCell()
    if not cell then return 0, 0, 0 end
    local ax, ay = animal:getX(), animal:getY()
    local cx, cy, cz = math.floor(ax), math.floor(ay), math.floor(animal:getZ())
    local near, far, chase = 0, 0, 0
    local n2, f2 = NEAR_R * NEAR_R, FAR_R * FAR_R
    for dx = -FAR_R, FAR_R do
        for dy = -FAR_R, FAR_R do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if sq then
                local mo = sq:getMovingObjects()
                for i = 0, mo:size() - 1 do
                    local o = mo:get(i)
                    if CD.isThreatZombie(o) then
                        local ox, oy = o:getX() - ax, o:getY() - ay
                        local d2 = ox * ox + oy * oy
                        if d2 <= f2 then
                            far = far + 1
                            if d2 <= n2 then
                                near = near + 1
                            end
                            local t = o:getTarget()
                            if t ~= nil and (t == animal or (owner ~= nil and t == owner)) then
                                chase = chase + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return near, far, chase
end

local function zombieSample(f, w, animal, now)
    if f.zNextMs and now < f.zNextMs then return end
    f.zNextMs = now + ZSCAN_MS
    local near, far, chase = countZombies(animal, f.owner)
    w.zn = w.zn + 1
    w.z5 = w.z5 + near
    w.z12 = w.z12 + far
    w.caca = w.caca + chase
    if far > w.zmax then
        w.zmax = far
    end
end

local function addBucket(side, name, w, dur)
    local bs = buckets[side]
    local b = bs[name]
    if not b then
        b = { wins = 0, ms = 0, mode = {} }
        bs[name] = b
    end
    b.wins = b.wins + 1
    b.ms = b.ms + dur
    for _, k in ipairs(SUM_KEYS) do
        b[k] = (b[k] or 0) + w[k]
    end
    for m, ms in pairs(w.mode) do
        b.mode[m] = (b.mode[m] or 0) + ms
    end
end

local function printWin(f, side, w, z5, z12)
    local tick = math.floor(ratio(w.dtSum, w.dtN) + 0.5)
    if side == "srv" then
        CD.log(string.format("[CD-ZPATH] srv cao=%s z5=%.1f z12=%.1f max=%d caca=%.1f | modo %s troca=%d | anda=%.1f liq=%.1f tort=%s rev=%d trav=%.2f tranco=%d salto=%d vira=%d | emit=%d%s cancel=%d alvo=%d inalc=%d falha=%d som=%.2f gsom=%.2f colis=%.2f%s | tick=%d/%d",
            tostring(f.id), z5, z12, w.zmax, ratio(w.caca, w.zn), modeStr(w.mode, SRV_MODES), w.troca,
            w.anda, w.liq, tortStr(w.anda, w.liq), w.rev, ratio(w.stuck, w.should), w.tranco, w.salto, w.vira,
            w.emitN, emitStr(w.emit), w.cancel, w.alvo, w.inalc, w.falha,
            ratio(w.som, w.n), ratio(w.gsom, w.n), ratio(w.colis, w.n), estStr(w.est, w.n), tick, w.dtMax))
    else
        CD.log(string.format("[CD-ZPATH] cli cao=%s z5=%.1f z12=%.1f max=%d | reg %s troca=%d | anda=%.1f liq=%.1f tort=%s rev=%d trav=%.2f tranco=%d salto=%d salto-troca=%d vira=%d | quadro=%d/%d",
            tostring(f.id), z5, z12, w.zmax, modeStr(w.mode, CLI_MODES), w.troca,
            w.anda, w.liq, tortStr(w.anda, w.liq), w.rev, ratio(w.stuck, w.should), w.tranco, w.salto,
            w.saltoTroca, w.vira, tick, w.dtMax))
    end
end

local function closeWin(f, side)
    local w = f.w
    if not w then return end
    f.w = nil
    local wasRun = f.runX ~= nil
    breakRun(f, w)
    if wasRun then
        f.runX, f.runY = f.x, f.y
    end
    local dur = (f.lastMs or w.t0) - w.t0
    if dur < 500 then return end
    local z5, z12 = ratio(w.z5, w.zn), ratio(w.z12, w.zn)
    local active = w.anda >= 0.5 or w.should > 0 or w.emitN > 0
    if active then
        addBucket(side, bucketOf(z12), w, dur)
    end
    if active or z12 >= 0.5 then
        printWin(f, side, w, z5, z12)
    end
end

local function printSummary(side)
    for _, name in ipairs(BUCKET_ORDER) do
        local b = buckets[side][name]
        if b and b.ms > 0 then
            local mins = b.ms / 60000
            local tick = math.floor(ratio(b.dtSum, b.dtN) + 0.5)
            if side == "srv" then
                CD.log(string.format("[CD-ZPATH] srv resumo z12=%s janelas=%d min=%.1f | tort=%s rev/min=%.1f trav=%.2f tranco/min=%.1f salto/min=%.1f vira/min=%.1f | emit/s=%.2f cancel=%.2f alvo/min=%.1f inalc/min=%.1f falha/min=%.1f troca/min=%.1f som=%.2f gsom=%.2f colis=%.2f | modo %s | tick=%d",
                    name, b.wins, mins, tortStr(b.anda, b.liq), b.rev / mins, ratio(b.stuck, b.should),
                    b.tranco / mins, b.salto / mins, b.vira / mins,
                    b.emitN / (mins * 60), ratio(b.cancel, b.emitN), b.alvo / mins, b.inalc / mins,
                    b.falha / mins, b.troca / mins, ratio(b.som, b.n), ratio(b.gsom, b.n), ratio(b.colis, b.n),
                    modeStr(b.mode, SRV_MODES), tick))
            else
                CD.log(string.format("[CD-ZPATH] cli resumo z12=%s janelas=%d min=%.1f | tort=%s rev/min=%.1f trav=%.2f tranco/min=%.1f salto/min=%.1f salto-troca/min=%.1f vira/min=%.1f troca/min=%.1f | reg %s | quadro=%d",
                    name, b.wins, mins, tortStr(b.anda, b.liq), b.rev / mins, ratio(b.stuck, b.should),
                    b.tranco / mins, b.salto / mins, b.saltoTroca / mins, b.vira / mins, b.troca / mins,
                    modeStr(b.mode, CLI_MODES), tick))
            end
        end
    end
end

local function housekeeping(now, side)
    if not nextSumMs then
        nextSumMs = now + CD.ZPATH_SUMMARY_MS
        return
    end
    if now < nextSumMs then return end
    nextSumMs = now + CD.ZPATH_SUMMARY_MS
    for a, f in pairs(recs) do
        if now - (f.lastMs or now) > STALE_MS then
            closeWin(f, side)
            recs[a] = nil
        end
    end
    printSummary(side)
end

-- Ficha e janela do cao; fecha a janela vencida antes da amostra nova entrar.
local function recFor(animal, id, now, side)
    local f = recs[animal]
    if not f then
        f = { id = id, unrN = 0 }
        recs[animal] = f
    end
    if f.w and (now - f.w.t0) >= CD.ZPATH_WINDOW_MS then
        closeWin(f, side)
    end
    if not f.w then
        f.w = newWin(now)
    end
    return f, f.w
end

---Counts a path request in the dog's open sampling window, and a cancel when it comes within FOLLOW_PATH_RESOLVE_MS of the last one.
---@param animal IsoAnimal
---@param system string subsystem that asked for the path
function CD.zpathEmit(animal, system)
    local f = recs[animal]
    if not f or not f.w then return end
    local w = f.w
    local now = getTimestampMs()
    w.emitN = w.emitN + 1
    local k = tostring(system)
    w.emit[k] = (w.emit[k] or 0) + 1
    if f.emitMs and (now - f.emitMs) < CD.FOLLOW_PATH_RESOLVE_MS then
        w.cancel = w.cancel + 1
    end
    f.emitMs = now
end

local function serverMode(id, d)
    if CD.netAuthHolder(id) then return "posse" end
    if d.fenceHop or CD.landGlide[id] then return "cerca" end
    if CD.combatMaintainDogs[id] then
        if d.combatMode == "retreat" then return "recuo" end
        if d.combatHold then return "golpe" end
        return "combate"
    end
    if CD.followSteering[id] then return "conduz" end
    if d.lockX then return "trava" end
    if CD.followMaintainDogs[id] then return "seguir" end
    return "outro"
end

local function farFrom(x, y, tx, ty, lim)
    local dx, dy = tx - x, ty - y
    return dx * dx + dy * dy > lim * lim
end

-- Devia estar andando: longe do dono no seguir, do zumbi na aproximacao, do ponto no recuo.
local function serverShould(id, d, mode, owner, x, y)
    if mode == "seguir" or mode == "conduz" then
        return owner ~= nil and farFrom(x, y, owner:getX(), owner:getY(), CD.followKeepFrom(d) + 1)
    end
    if mode == "combate" then
        local z = CD.combatTarget[id]
        return z ~= nil and farFrom(x, y, z:getX(), z:getY(), CD.STRIKE_DIST + 0.5)
    end
    if mode == "recuo" then
        local rt = d.retreatTile
        return rt ~= nil and farFrom(x, y, rt.x + 0.5, rt.y + 0.5, 1)
    end
    return false
end

local function sampleServerDog(animal, id, now, tickDt)
    if not animal:isExistInTheWorld() then return end
    local f, w = recFor(animal, id, now, "srv")
    local dt = f.lastMs and (now - f.lastMs) or 0
    f.lastMs = now
    if not f.zNextMs or now >= f.zNextMs then
        f.owner = CD.getOwnerPlayer(animal)
    end
    local d = CD.data(animal)
    local mode = serverMode(id, d)
    modeSample(f, w, mode, dt, now)
    local x, y = animal:getX(), animal:getY()
    moveSample(f, w, x, y, dt, serverShould(id, d, mode, f.owner, x, y), now, mode ~= "posse")
    faceSample(f, w, animal)
    zombieSample(f, w, animal, now)

    local z = CD.combatTarget[id]
    if z then
        if f.tgt and f.tgt ~= z then
            w.alvo = w.alvo + 1
        end
        f.tgt = z
    end
    local un = 0
    local unr = CD.combatUnreach[id]
    if unr then
        for _ in pairs(unr) do un = un + 1 end
    end
    if un > f.unrN then
        w.inalc = w.inalc + un - f.unrN
    end
    f.unrN = un

    -- O AnimalPathFindState liga isto no Failed do A*, junto de um stopAllMovementNow.
    local sfw = animal:shouldFollowWall()
    if sfw and not f.sfw then
        w.falha = w.falha + 1
    end
    f.sfw = sfw
    if animal:getLastSoundRespondedTo() ~= nil then
        w.som = w.som + 1
    end
    if animal:getPathFindBehavior2():isGoalSound() then
        w.gsom = w.gsom + 1
    end
    if animal:isCollidedThisFrame() then
        w.colis = w.colis + 1
    end
    local st = animal:getCurrentStateName()
    if st and not (string.find(st, "PathFind", 1, true) or string.find(st, "Walk", 1, true)
                   or string.find(st, "Idle", 1, true)) then
        w.est[st] = (w.est[st] or 0) + 1
    end
    w.n = w.n + 1
    if tickDt > 0 and tickDt <= MAX_DT_MS then
        w.dtN = w.dtN + 1
        w.dtSum = w.dtSum + tickDt
        if tickDt > w.dtMax then
            w.dtMax = tickDt
        end
    end
end

local lastTickMs = nil
local function serverTick()
    local now = getTimestampMs()
    local tickDt = lastTickMs and (now - lastTickMs) or 0
    lastTickMs = now
    for id, animal in pairs(CD.followMaintainDogs) do
        sampleServerDog(animal, id, now, tickDt)
    end
    for id, animal in pairs(CD.combatMaintainDogs) do
        if not CD.followMaintainDogs[id] then
            sampleServerDog(animal, id, now, tickDt)
        end
    end
    housekeeping(now, "srv")
end

local cliDog, cliDogMs = nil, 0
local lastFrameMs = nil
local function clientTick()
    local now = getTimestampMs()
    local frameDt = lastFrameMs and (now - lastFrameMs) or 0
    lastFrameMs = now
    local player = getPlayer()
    if not player then return end
    if now - cliDogMs >= 1000 then
        cliDogMs = now
        cliDog = CD.getCompanionAnimal(player)
    end
    local animal = cliDog
    if animal and animal:isExistInTheWorld() then
        local id = animal:getOnlineID()
        local f, w = recFor(animal, id, now, "cli")
        local dt = f.lastMs and (now - f.lastMs) or 0
        f.lastMs = now
        local reg = "nativo"
        if CD.netAuthOwned(id) then
            reg = "posse"
        elseif CD.followStreamActive(id) then
            reg = "stream"
        end
        modeSample(f, w, reg, dt, now)
        local d = CD.data(animal)
        local x, y = animal:getX(), animal:getY()
        local should = not d.inCombat and CD.getState(animal) == CD.STATE_FOLLOW
            and farFrom(x, y, player:getX(), player:getY(), CD.followKeepFrom(d) + 1)
        moveSample(f, w, x, y, dt, should, now, true)
        faceSample(f, w, animal)
        zombieSample(f, w, animal, now)
        w.n = w.n + 1
        if frameDt > 0 and frameDt <= MAX_DT_MS then
            w.dtN = w.dtN + 1
            w.dtSum = w.dtSum + frameDt
            if frameDt > w.dtMax then
                w.dtMax = frameDt
            end
        end
    end
    housekeeping(now, "cli")
end

local function onTick()
    if isClient() then
        clientTick()
    else
        serverTick()
    end
end

if CD.DEBUG_ZPATH then
    CD.evAdd(Events.OnTick, onTick, "dbg.zpath")
    CD.log("[CD-ZPATH] sonda ligada: janela " .. tostring(CD.ZPATH_WINDOW_MS) .. " ms, resumo "
        .. tostring(CD.ZPATH_SUMMARY_MS) .. " ms")
end
