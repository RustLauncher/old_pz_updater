CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- IsoAnimal parado num square sem chao cai no caminho de queda humano da engine, que da NPE todo
-- frame porque animal nao tem humanVisual. A flag de ragdollFall e o desligador da engine: com ela
-- ligada o shouldBeFalling devolve falso (nada acumula) e o DoLand sai na primeira linha (nada
-- pousa). Escrita uma vez por cao no sweep de 2 s, em vez de zerar acumulador por tick.
---@param animal IsoAnimal
---@return boolean written false when the flag was already on
function CD.suppressFallFlag(animal)
    if animal:isRagdollFall() then return false end
    CD.perfCount("fallguard.write")
    animal:setRagdollFall(true)
    animal:setLastFallSpeed(0)
    animal:setbFalling(false)
    animal:setFallTime(0)
    return true
end

-- Antes de matar ou soltar: o cadaver copia a flag e a pose de morte viraria ragdoll.
---@param animal IsoAnimal
function CD.releaseFallFlag(animal)
    if animal:isRagdollFall() then
        animal:setRagdollFall(false)
    end
end

-- Recuperar o cao preso em square sem chao nao precisa de tick: sem a queda ele nao crasha nem
-- desliza, so fica parado ali.
---@param animal IsoAnimal
---@param d table companion ModData
function CD.floorlessRecoverOne(animal, d)
    if d.fenceHop then
        d.floorlessSince = nil
        return
    end
    if CD.squareHasFloor(animal:getCurrentSquare()) then
        d.floorlessSince = nil
        return
    end
    local now = getTimestampMs()
    if not d.floorlessSince then
        d.floorlessSince = now
        return
    end
    if now - d.floorlessSince < CD.FALL_GUARD_DEBOUNCE_MS then return end
    d.floorlessSince = nil
    local owner = CD.getOwnerPlayer(animal, d)
    if not owner then return end
    CD.perfCount("fall.recover")
    CD.clearClimbVars(animal)
    if CD.teleportRecover(animal, owner) then
        d.fallRecoverUntilMs = now + CD.FALL_RECOVER_COOLDOWN_MS
        CD.transmit(animal)
    end
end

local SHOUT_LOCK_STILL_MS = 400
-- Posicao do dono lida uma vez por tick e compartilhada pelos caes dele: era o grosso do custo
-- desta trava, com todos os companions num dono so.
local ownerX, ownerY, ownerStamp = {}, {}, {}
local function ownerPosNow(owner, now)
    if ownerStamp[owner] ~= now then
        ownerStamp[owner] = now
        ownerX[owner], ownerY[owner] = owner:getX(), owner:getY()
    end
    return ownerX[owner], ownerY[owner]
end

-- Posicao de quem esta armado, lida uma vez por tick. Sao poucos; os caes sao muitos.
local armedN, armedX, armedY = 0, {}, {}
local function refreshArmed()
    armedN = 0
    for _, p in pairs(CD.armedPlayers()) do
        armedN = armedN + 1
        armedX[armedN], armedY[armedN] = p:getX(), p:getY()
    end
end

local function gunNear(x, y)
    local r = CD.SHOUT_LOCK_GUN_RANGE
    for i = 1, armedN do
        if math.abs(armedX[i] - x) <= r and math.abs(armedY[i] - y) <= r then return true end
    end
    return false
end

local function cancelShoutNudge(animal, d, now, id)
    -- Sob autoridade de client quem diz onde o cao esta e o report, nao a ancora.
    if CD.netAuthHolder(id) then
        d.lockX = nil
        return
    end
    if CD.loiterDriving(animal, id) then
        d.lockX = nil
        return
    end
    if (d.careMode and not d.careHold) or d.fenceHop or d.breedTarget or d.autoFeeding or d.hunting or (d.inCombat and not d.combatHold) or d.retreating
       or d.huntTargetId or d.forageGoingSinceMin or d.recallUntilMin or d.protectX or d.gotoSpot
       or d.sniffSpot then
        d.lockX = nil
        return
    end
    local state = d.state or CD.STATE_FOLLOW
    local shouldLock = false
    local x, y
    if state == CD.STATE_STAY then
        shouldLock = true
    elseif state == CD.STATE_FOLLOW then
        local owner = CD.getOwnerPlayer(animal, d)
        if not owner then
            d.lockX = nil
            return
        end
        local ox, oy = ownerPosNow(owner, now)
        if not d._olx or (math.abs(ox - d._olx) + math.abs(oy - d._oly)) >= CD.OWNER_STILL_EPS then
            d._olx, d._oly, d._ostill = ox, oy, now
        end
        if (now - (d._ostill or now)) < SHOUT_LOCK_STILL_MS then
            d.lockX = nil
            return
        end
        -- Dono parou e o seguir ainda conduz: para o cao assim que ele chega, sem esperar a passada
        -- do seguir. Le a posicao so enquanto o cao ainda esta a caminho.
        if d.running ~= nil and not d.lockX then
            x, y = animal:getX(), animal:getY()
            local dx, dy = x - ox, y - oy
            if math.sqrt(dx * dx + dy * dy) <= CD.followKeepFrom(d) then
                d.running = nil
                animal:setVariable("animalRunning", false)
                animal:setVariable("animalSpeed", 1.0)
                CD.holdStill(animal)
            end
        end
        -- A trava contra o empurrao do som so vale com tiro ao alcance; grito e porta dao um passo
        -- que o seguir desfaz sozinho.
        if armedN == 0 or not gunNear(ox, oy) then
            d.lockX = nil
            return
        end
        if d.lockX then
            shouldLock = true
        else
            if not x then
                x, y = animal:getX(), animal:getY()
            end
            local dx, dy = x - ox, y - oy
            shouldLock = math.sqrt(dx * dx + dy * dy) <= CD.followKeepFrom(d)
        end
    end
    if not shouldLock then
        d.lockX = nil
        return
    end
    CD.perfCount("fall.lock")

    if not x then
        x, y = animal:getX(), animal:getY()
    end
    if not d.lockX then
        d.lockX, d.lockY, d.lockZ = x, y, animal:getZ()
        return
    end
    local drift = math.abs(x - d.lockX) + math.abs(y - d.lockY)
    if drift > 0.05 then
        animal:stopAllMovementNow()
        local ax, ay, az = d.lockX, d.lockY, d.lockZ
        animal:setX(ax)
        animal:setY(ay)
        animal:setNextX(ax)
        animal:setNextY(ay)
        animal:setZ(az)
    end
end

---Livestock care: when the engine path ends away from the dog's goal, issues the goal again, backing off after CARE_REASSERT_MAX tries.
---@param a IsoAnimal
---@param d table companion ModData
---@param nowMs number timestamp in ms
function CD.careAntiHijack(a, d, nowMs)
    if not d.careMode or d.careHold or d.fenceHop then return end
    local wx, wy = d.careWantTx, d.careWantTy
    if not wx then return end
    if d.careBackoffMs and nowMs < d.careBackoffMs then return end
    if d.careReassertMs and (nowMs - d.careReassertMs) < CD.CARE_REASSERT_MS then return end
    local ddx, ddy = a:getX() - (wx + 0.5), a:getY() - (wy + 0.5)
    if (ddx * ddx + ddy * ddy) <= 2.25 then return end

    local tx, ty
    local b = a:getPathFindBehavior2()
    if b then
        tx, ty = math.floor(b:getTargetX()), math.floor(b:getTargetY())
    end
    if not tx then return end
    if tx == wx and ty == wy then
        d.careReassertN = nil
        return
    end

    d.careReassertMs = nowMs
    d.careReassertN = (d.careReassertN or 0) + 1
    d.careHijacks = (d.careHijacks or 0) + 1
    if d.careReassertN > CD.CARE_REASSERT_MAX then
        d.careBackoffMs = nowMs + CD.CARE_REASSERT_BACKOFF_MS
        d.careReassertN = nil
        if CD.CARE_DEBUG then
            CD.log(string.format("[CD-CARE] sequestro insistente -> backoff (alvo da engine %d,%d)", tx, ty))
        end
        return
    end
    if CD.CARE_DEBUG then
        CD.log(string.format("[CD-CARE] path SEQUESTRADO: engine mandou (%d,%d), nosso alvo e (%d,%d) -- re-emitindo", tx, ty, wx, wy))
    end
    d.careGoalTx, d.careGoalTy, d.careBackTx, d.careBackTy = nil, nil, nil, nil
    local sq = getCell():getGridSquare(wx, wy, math.floor(a:getZ()))
    local run = d.careWantRun == true
    CD.moveTo(a, run, run and CD.runAnimSpeed() or 1.0, wx, wy, sq and sq:getZ() or math.floor(a:getZ()), "gado-antihijack", nil, "gado")
end

-- Diagnostico, so com a medicao ligada: descontinuidade de posicao por tick, com o dono do
-- movimento. Salto e distancia E velocidade: so a distancia conta a corrida normal de um tick longo
-- como pulo.
local JUMP_OWNER = { glide = "jump.by.glide", hop = "jump.by.hop", steer = "jump.by.steer",
                     lock = "jump.by.lock", auth = "jump.by.auth", engine = "jump.by.engine" }
local jumpX, jumpY, jumpT = {}, {}, {}

local function jumpWatch(a, d, id, now)
    local x, y = a:getX(), a:getY()
    local px, py, pms = jumpX[a], jumpY[a], jumpT[a]
    jumpX[a], jumpY[a], jumpT[a] = x, y, now
    if not px then return end
    local dt = now - pms
    if dt <= 0 or dt > CD.JUMP_WATCH_MAX_DT_MS then return end
    local dx, dy = x - px, y - py
    local dist = math.sqrt(dx * dx + dy * dy)
    local who = "engine"
    if d.fenceHop then who = "hop"
    elseif CD.landGlide[id] then who = "glide"
    elseif d.fenceSteer or CD.followSteering[id] then who = "steer"
    elseif d.lockX then who = "lock"
    elseif CD.netAuthHolder(id) then who = "auth" end

    -- Perfil de velocidade, contado SEMPRE e fora da posse (la o avanco e o degrau do report, nao o
    -- passo do cao). Contador de salto sozinho nao separa "pulou" de "correu rapido demais". Faixas
    -- pela regua do Motion.lua: ate 4,7 cabe cruzeiro (3,23) e sprint (3,93) com o jitter de tick;
    -- 4,7 a 6 e a escala cheia do clipe (5,408), que marcha calibrada nao mostra; acima e empurrao.
    if who ~= "auth" then
        CD.perfCount("jump.move.tiles", dist)
        CD.perfCount("jump.move.ms", dt)
        local v = dist * 1000 / dt
        if v >= 16 then CD.perfCount("jump.v.16")
        elseif v >= 8 then CD.perfCount("jump.v.8")
        elseif v >= 6 then CD.perfCount("jump.v.6")
        elseif v >= 4.7 then CD.perfCount("jump.v.cheia")
        elseif v >= 0.2 then CD.perfCount("jump.v.ok") end
    end

    if dist < CD.JUMP_WATCH_TILES then return end
    if dist * 1000 < CD.JUMP_WATCH_SPEED * dt then return end
    CD.perfCount("jump.srv")
    if dist >= 4 then CD.perfCount("jump.far")
    elseif dist >= 1.5 then CD.perfCount("jump.mid")
    else CD.perfCount("jump.near") end
    CD.perfCount(JUMP_OWNER[who])
    if who ~= "engine" then return end
    -- Quem move o cao quando nenhum sistema nosso esta ativo: o objetivo do path da engine diz se
    -- foi a fuga por som da 42.20 (Goal.Sound) ou o caminho de combate.
    local b = a:getPathFindBehavior2()
    if b and b:isGoalSound() then
        CD.perfCount("jump.eng.sound")
    elseif d.inCombat then
        CD.perfCount("jump.eng.combat")
    else
        CD.perfCount("jump.eng.other")
    end
end

local jumpClearMs = 0
local function companionFallPass(comps, now)
    CD.perfCount("fall.comps.n", #comps)
    -- Nivel 2 do medidor: le a posicao de todo companion por tick, entao fica fora do nivel 1.
    local watch = CD._perfLv > 1
    if watch and now - jumpClearMs > 120000 then
        jumpClearMs = now
        jumpX, jumpY, jumpT = {}, {}, {}
    end
    for i = 1, #comps do
        local a = comps[i]
        local d = CD.data(a)
        local id = a:getOnlineID()
        cancelShoutNudge(a, d, now, id)
        if watch then
            jumpWatch(a, d, id, now)
        end
        CD.careAntiHijack(a, d, now)
    end
end

local ownerCacheClearMs = 0
local function tickFallGuard()
    local now = getTimestampMs()
    if now - ownerCacheClearMs > 60000 then
        ownerCacheClearMs = now
        ownerX, ownerY, ownerStamp = {}, {}, {}
    end
    refreshArmed()
    CD.pz("srv.fall.comps", companionFallPass, CD.dogRegNow().companions, now)
end

-- So cao ativo (follow ou combate). Cao parado, passivo e vira-lata ficam no sync nativo da
-- engine: o desync deles e so visual, e a varredura caes x jogadores era o custo.
local function pushDenseSync(animal, now)
    local d = CD.data(animal)
    if d.fenceHop then return end
    if d._followStreaming then return end
    -- Sob autoridade de client o pacote nativo iria pro dono e viraria alvo atrasado pro mover.
    if CD.netAuthHolder(animal:getOnlineID()) then return end
    if d._denseSyncMs and (now - d._denseSyncMs) < CD.DENSE_SYNC_MS then return end
    local px, py = animal:getX(), animal:getY()
    local moved = d._denseLastX and (math.abs(px - d._denseLastX) + math.abs(py - d._denseLastY)) or 999
    d._denseLastX, d._denseLastY = px, py
    d._denseSyncMs = now
    if moved < CD.DENSE_SYNC_MIN_MOVE then return end
    animal:sendExtraUpdateToClients()
end

local function tickDenseSync()
    if not CD.MP_DENSE_FOLLOW_SYNC or not isServer() then return end
    local now = getTimestampMs()
    for _, animal in pairs(CD.followMaintainDogs) do pushDenseSync(animal, now) end
    for id, animal in pairs(CD.combatMaintainDogs) do
        if not CD.followMaintainDogs[id] then
            pushDenseSync(animal, now)
        end
    end
end
CD.tickFallGuard, CD.tickDenseSync = tickFallGuard, tickDenseSync
