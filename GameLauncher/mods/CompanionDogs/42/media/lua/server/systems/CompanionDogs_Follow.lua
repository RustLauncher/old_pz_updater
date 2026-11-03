CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local fenceSteering = {}
CD.fenceSteering = fenceSteering

local followSteering = {}
CD.followSteering = followSteering

local ownerMoveState = {}
CD.ownerMoveState = ownerMoveState

local ownerSpeed = {}

local function walkScaleFrom(_d)
    return CD.PATH_WALK_SCALE
end

local doorRefreshAt = {}
local function refreshDoorsAround(cell, ccx, ccy, ccz, R, cool, now)
    local did = false
    for dx = -R, R do
        for dy = -R, R do
            local sq = cell:getGridSquare(ccx + dx, ccy + dy, ccz)
            if sq then
                local objs = sq:getObjects()
                local n = objs and objs:size() or 0
                for i = 0, n - 1 do
                    local o = objs:get(i)
                    if o and instanceof(o, "IsoDoor") then
                        if o:isOpen() then
                            local key = sq:getX() .. "," .. sq:getY() .. "," .. ccz
                            if not doorRefreshAt[key] or (now - doorRefreshAt[key]) >= cool then
                                doorRefreshAt[key] = now
                                sq:RecalcAllWithNeighbours(true)
                                sq:setSquareChanged()
                                did = true
                            end
                        end
                    end
                end
            end
        end
    end
    return did
end

local function refreshOpenDoorsNear(animal, owner, d, now)
    if not CD.DOOR_NAV_REFRESH then return false end
    if d.doorScanMs and (now - d.doorScanMs) < CD.DOOR_REFRESH_SCAN_MS then return false end
    d.doorScanMs = now
    local cell = getCell()
    if not cell then return false end
    local R = CD.DOOR_REFRESH_SCAN
    local cool = CD.DOOR_REFRESH_COOLDOWN_MS
    local did = false
    local cur = animal:getCurrentSquare()
    if cur then
        did = refreshDoorsAround(cell, cur:getX(), cur:getY(), cur:getZ(), R, cool, now) or did
    end
    local osq = owner:getCurrentSquare()
    if osq then
        did = refreshDoorsAround(cell, osq:getX(), osq:getY(), osq:getZ(), R, cool, now) or did
    end
    return did
end

local steerAdvance = CD.steerAdvance

local function steerToFenceTile(animal, targetSq, run, d, now)
    if not animal then return end
    steerAdvance(animal, targetSq:getX() + 0.5, targetSq:getY() + 0.5, run, d, now,
                 CD.STEER_WALK_SPEED, CD.STEER_RUN_SPEED, nil)
    if CD.FENCE_LAND_USE_STREAM and isServer() then
        local sid = animal:getOnlineID()
        local rec = CD.landStreaming[sid]
        if rec then
            rec.animal = animal
            rec.untilMs = now + CD.FENCE_STEER_STREAM_MS
        else
            CD.landStreaming[sid] = { animal = animal, untilMs = now + CD.FENCE_STEER_STREAM_MS }
        end
    end
    if CD.MP_DENSE_FOLLOW_SYNC and isServer() then
        if not d._denseSyncMs or (now - d._denseSyncMs) >= CD.DENSE_SYNC_MS then
            d._denseSyncMs = now
            animal:sendExtraUpdateToClients()
        end
    end
end

-- devolve true quando a conducao de cerca acabou e o registro deve sair de fenceSteering
local function stepFenceSteer(animal, now)
    if not animal or not animal:isExistInTheWorld() then return true end
    local d = CD.data(animal)
    local st = d and d.fenceSteer
    if not st or now >= st.untilMs or d.fenceHop then return true end
    local cs = animal:getCurrentSquare()
    if cs and cs:getX() == st.tx and cs:getY() == st.ty then return false end
    local owner = CD.getOwnerPlayer(animal)
    if not owner then return false end
    local sq = getCell():getGridSquare(st.tx, st.ty, st.tz)
    if sq then
        steerToFenceTile(animal, sq, st.run, d, now)
    end
    return false
end

local function tickFenceSteer()
    if not isServer() then
        for k in pairs(fenceSteering) do fenceSteering[k] = nil end
        return
    end
    local now = getTimestampMs()
    for id, animal in pairs(fenceSteering) do
        if stepFenceSteer(animal, now) then
            fenceSteering[id] = nil
            local d = CD.data(animal)
            if d then
                d.fenceSteer = nil
            end
        end
    end
end

local steerStepPassable = CD.steerStepPassable

local function steerCorridorClear(animal, owner, d, now, keep)
    return CD.steerCorridorClear(animal, owner:getX(), owner:getY(), d, now, keep)
end

local function releaseFollowSteer(animal, d, now, st)
    if not animal then return end
    followSteering[animal:getOnlineID()] = nil
    if d then
        d._steerClear, d._steerProbeMs = nil, nil
        if now then
            -- Hold curto so pra quem provou que a corrida rendeu. Dentro de casa a conducao devolve
            -- o cao pro A* toda vez que chega numa quina, e carimbar os 2s cheios nesse caso joga
            -- fora justamente a emissao que se quer economizar. Corrida que nao andou nada continua
            -- pagando o hold longo, senao vira arm reprovado em loop.
            local paidOff = st and st.armGap and st.bestGap
                and (st.armGap - st.bestGap) >= CD.PROG_EPS
            d._steerHoldMs = now + (paidOff and CD.FOLLOW_STEER_RETRY_MS
                                           or CD.FOLLOW_STEER_COOLDOWN_MS)
        end
    end
    CD.letMove(animal)
end

local function followSteerStep(animal, owner, st, d, now)
    local keep = CD.followKeepFrom(d)
    local ax, ay = owner:getX(), owner:getY()
    local dx, dy = ax - animal:getX(), ay - animal:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= keep then
        d._steerMs = now
        return true
    end
    local nx = steerAdvance(animal, ax - dx / dist * keep, ay - dy / dist * keep, st.run == true, d, now,
                            CD.FOLLOW_STEER_WALK_SPEED, CD.FOLLOW_STEER_RUN_SPEED,
                            steerStepPassable)
    if not nx then
        CD.perfCount("steer.rel.blocked")
        releaseFollowSteer(animal, d, now, st)
        return false
    end
    CD.perfCount("steer.step")
    return true
end

local function followSteerGate(animal, owner, d, gap, now, run)
    local id = animal:getOnlineID()
    local st = followSteering[id]
    local ok = CD.FOLLOW_STEER ~= false and isServer()
        and not (d.fenceHop or d.fenceTraversal or d.fenceSteer)
        and gap <= CD.FOLLOW_STEER_MAX_DIST
        and math.floor(owner:getZ()) == math.floor(animal:getZ())
        and not (st == nil and d._steerHoldMs and now < d._steerHoldMs)
    local keep = CD.followKeepFrom(d)
    if ok then
        ok = gap > (st and keep or CD.followSteerArmFrom(d))
    end
    if ok then
        -- Basta um pedaco do caminho: o cao anda o trecho reto que existe e devolve a curva pro A*,
        -- em vez de perder a conducao inteira porque o quinto tile esta bloqueado.
        local clear = steerCorridorClear(animal, owner, d, now, keep)
        local need = CD.FOLLOW_STEER_MIN_CLEAR
        local reach = gap - keep
        if reach < need then
            need = reach
        end
        ok = need > 0 and clear >= need
    end
    if not ok then
        if st then
            releaseFollowSteer(animal, d, now, st)
        end
        return false
    end
    if not st then
        st = { animal = animal, armGap = gap, bestGap = gap,
               lastX = animal:getX(), lastY = animal:getY(), moveMs = now }
        followSteering[id] = st
        d._steerHoldMs = nil
        CD.perfCount("steer.arm")
    else
        if gap < st.bestGap then
            st.bestGap = gap
        end
        -- Freio pelo deslocamento do proprio cao, nao pelo fechamento do vao. Conduzido ele anda em
        -- linha reta pro dono: ou avanca, ou o guard de passo reprova e ja solta. Medir o vao
        -- confunde "travado" com "o dono anda tao rapido quanto eu", e nesse segundo caso devolver
        -- pro A* nao deixa o cao mais rapido, so gasta busca. Com passo de 1.90 contra dono a ~1.50
        -- o vao fecha ~0.40/s: um limiar de 0.35 no vao levaria ~875 ms, e o freio de 700 ms
        -- dispararia no meio de uma perseguicao saudavel.
        local px, py = animal:getX(), animal:getY()
        if (math.abs(px - st.lastX) + math.abs(py - st.lastY)) >= CD.FOLLOW_STEER_STALL_EPS then
            st.lastX, st.lastY, st.moveMs = px, py, now
        elseif (now - (st.moveMs or now)) >= CD.FOLLOW_STEER_STALL_MS then
            CD.perfCount("steer.rel.stall")
            releaseFollowSteer(animal, d, now, st)
            return false
        end
    end
    st.animal, st.run = animal, run
    st.untilMs = now + CD.FOLLOW_STEER_DRIVE_MS
    CD.applyGaitScale(animal,
        CD.FOLLOW_STEER_RUN_SPEED / CD.FOLLOW_STEER_RUN_RATE,
        CD.FOLLOW_STEER_WALK_SPEED / CD.FOLLOW_STEER_WALK_RATE, d)
    if not followSteerStep(animal, owner, st, d, now) then return false end
    -- So depois do passo aceito. Limpar na hora do arm faz um arm reprovado cair no followRepath sem
    -- o freio de commit e emitir uma rota, que e o contrario do que a conducao existe pra fazer.
    d.followPathTile = nil
    return true
end

-- devolve true quando a conducao de follow acabou e o registro deve sair de followSteering
local function stepFollowSteer(st, animal, now)
    if not animal or not animal:isExistInTheWorld() then return true end
    if st.untilMs and now >= st.untilMs then return true end
    local d = CD.data(animal)
    if not d or d.fenceHop or d.fenceSteer or d.fenceTraversal then return true end
    local owner = CD.getOwnerPlayer(animal)
    if not owner or not owner:getCurrentSquare() then return true end
    if math.floor(owner:getZ()) ~= math.floor(animal:getZ()) then return true end
    followSteerStep(animal, owner, st, d, now)
    return false
end

local function tickFollowSteer()
    if not isServer() then
        for k in pairs(followSteering) do followSteering[k] = nil end
        return
    end
    local now = getTimestampMs()
    -- Desligado em runtime: para de conduzir na hora, mas NAO limpa a tabela aqui. Quem solta e o
    -- followSteerGate, que devolve o movimento com letMove; zerar direto deixaria o cao congelado
    -- de pe com o blockMovement que o ultimo passo carimbou.
    if CD.FOLLOW_STEER == false then return end
    for id, st in pairs(followSteering) do
        local animal = st.animal
        if stepFollowSteer(st, animal, now) then
            followSteering[id] = nil
            if animal and animal:isExistInTheWorld() then
                releaseFollowSteer(animal, CD.data(animal), now, st)
            end
        end
    end
end

---Combat vault over a low fence toward the zombie, or a steer to the take-off tile when the fence is a few steps away.
---@param animal IsoAnimal
---@param z IsoZombie
---@param d table companion ModData
---@param now number timestamp in ms
---@return boolean true when the vault owns the dog this tick
function CD.tryCombatVault(animal, z, d, now)
    if not CD.COMBAT_FENCE_HOP then return false end
    if isServer() and not CD.COMBAT_FENCE_HOP_MP then return false end
    local toSq, dx, dy, key = CD.findFenceCrossing(animal, z, d, now, CD.lowFenceCrossable)
    if toSq then
        d.cstall = nil
        d.combatHop = true
        CD.startFenceHop(animal, toSq, dx, dy, z, key)
        return true
    end
    local fSq, fdx, fdy, fkey, nearSq = CD.findFenceTowardOwner(animal, z, CD.FENCE_GHOST_SCAN, d, now, CD.lowFenceCrossable)
    if fSq and nearSq then
        local cs = animal:getCurrentSquare()
        if cs and cs:getX() == nearSq:getX() and cs:getY() == nearSq:getY() then
            d.cstall = nil
            d.combatHop = true
            CD.startFenceHop(animal, fSq, fdx, fdy, z, fkey)
        else
            steerToFenceTile(animal, nearSq, true, d, now)
        end
        return true
    end
    return false
end

local function doRepositionToOwner(animal, owner)
    CD.clearClimbVars(animal)
    if animal then
        animal:stopAllMovementNow()
    end
    if not CD.teleportRecover(animal, owner) then return false end
    if animal then
        CD.transmit(animal)
    end
    return true
end

local function tryStuckTeleport(animal, owner, d, gap, now)
    if CD.STUCK_TELEPORT_ENABLE == false then return false end
    if gap <= CD.followKeepFrom(d) or gap > CD.TELEPORT_DIST then
        d.stuckBestGap = nil
        d.stuckSinceMs = nil
        return false
    end
    if d.fenceHop or d.fenceTraversal then return false end
    if d.fenceHopUntilMs and now < d.fenceHopUntilMs then return false end
    if d.fallRecoverUntilMs and now < d.fallRecoverUntilMs then return false end
    if d.stuckTeleportUntilMs and now < d.stuckTeleportUntilMs then return false end
    if (not d.stuckBestGap) or gap <= d.stuckBestGap - CD.PROG_EPS then
        d.stuckBestGap = gap
        d.stuckSinceMs = now
        return false
    end
    local failedRecently = d.pathFailMs and (now - d.pathFailMs) <= CD.STUCK_RECENT_FAIL_MS
    local noGain = d.stuckSinceMs and (now - d.stuckSinceMs) >= CD.STUCK_TELEPORT_MS
    if not (failedRecently and noGain) then return false end
    if not doRepositionToOwner(animal, owner) then return false end
    CD.perfCount("stuck.teleport")
    if isServer() and animal then
        animal:sendExtraUpdateToClients()
    end
    d.stuckTeleportUntilMs = now + CD.STUCK_TELEPORT_COOLDOWN_MS
    d.stuckBestGap = nil
    d.stuckSinceMs = nil
    d.pathFailMs = nil
    d.followPathTile = nil
    return true
end

local function refreshOwnerCrossedDoor(owner, d, now)
    if not CD.DOOR_NAV_REFRESH then return end
    local osq = owner:getCurrentSquare()
    if not osq then return end
    local ox, oy, oz = osq:getX(), osq:getY(), osq:getZ()
    local px, py, pz = d.ownerDoorX, d.ownerDoorY, d.ownerDoorZ
    d.ownerDoorX, d.ownerDoorY, d.ownerDoorZ = ox, oy, oz
    if px == nil or pz ~= oz then return end
    if math.abs(ox - px) + math.abs(oy - py) ~= 1 then return end
    local cell = getCell()
    if not cell then return end
    local prev = cell:getGridSquare(px, py, pz)
    if not prev then return end
    local door = prev:getDoorTo(osq)
    if door and instanceof(door, "IsoDoor") and door:isOpen() then
        local sq = door:getSquare() or osq
        local key = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
        if not doorRefreshAt[key] or (now - doorRefreshAt[key]) >= CD.DOOR_REFRESH_COOLDOWN_MS then
            doorRefreshAt[key] = now
            sq:RecalcAllWithNeighbours(true)
            sq:setSquareChanged()
        end
    end
end

local function followFenceHop(animal, owner, d, gap, now, runDist)
    if isServer() and not CD.FENCE_HOP_MP then
        d.fenceTraversal = nil
        d.fenceSteer = nil
    elseif gap <= CD.FENCE_HOP_DETECT_DIST
       and not (d.fallRecoverUntilMs and now < d.fallRecoverUntilMs) then
        local toSq, dx, dy, key = CD.findFenceCrossing(animal, owner, d, now)
        if toSq then
            d.fenceTraversal = true
            CD.startFenceHop(animal, toSq, dx, dy, owner, key)
            return true
        end
        local fSq, fdx, fdy, fkey, nearSq = CD.findFenceTowardOwner(animal, owner, CD.FENCE_GHOST_SCAN, d, now)
        if fSq and nearSq then
            local need = CD.FENCE_ONLINE_STALL_MS or CD.FENCE_GHOST_STALL_MS
            local boxed = d.fenceStallMs and (now - d.fenceStallMs) >= need
            if boxed then
                d.fenceTraversal = true
                local curS = animal:getCurrentSquare()
                if curS and nearSq:getX() == curS:getX() and nearSq:getY() == curS:getY() then
                    CD.startFenceHop(animal, fSq, fdx, fdy, owner, fkey)
                    return true
                end
                local srun = gap > runDist
                d.fenceSteer = { tx = nearSq:getX(), ty = nearSq:getY(), tz = nearSq:getZ(),
                                 run = srun, untilMs = now + CD.FENCE_STEER_DRIVE_MS }
                fenceSteering[animal:getOnlineID()] = animal
                steerToFenceTile(animal, nearSq, srun, d, now)
                return true
            end
        else
            d.fenceTraversal = nil
        end
    end
    return false
end

local traceN, traceX, traceY, traceMs = 0, nil, nil, nil
local function followTrace(animal, d, nowMs, px, py, gap, why)
    if not CD.DEBUG_FOLLOW_TRACE then return end
    if traceN >= CD.DEBUG_TRACE_MAX then return end
    if traceMs then
        local dt = nowMs - traceMs
        if dt > 0 then
            local dx, dy = px - traceX, py - traceY
            local dist = math.sqrt(dx * dx + dy * dy)
            traceN = traceN + 1
            local mv = tostring(animal:isMoving())
            local snd = tostring(CD.pathHijacked(animal))
            local st = tostring(animal:getCurrentStateName())
            local tgt = -1
            local pl = -1
            local b = animal:getPathFindBehavior2()
            if b then
                local tx, ty = b:getTargetX() - px, b:getTargetY() - py
                tgt = math.sqrt(tx * tx + ty * ty)
                pl = b:getPathLength()
            end
            CD.log(string.format("[CD-TRACE] %d dt=%d d=%.4f v=%.2f gap=%.1f x=%.2f y=%.2f st=%s run=%s rs=%.3f ws=%.3f wr=%.2f mov=%s mv=%s snd=%s tgt=%.1f pl=%.1f %s",
                traceN, dt, dist, dist / (dt / 1000), gap or -1, px, py, st, tostring(d.running == true),
                d._rs or -1, d._ws or -1, d._walkV or -1, tostring(animal:isAnimalMoving()), mv, snd, tgt, pl, why))
        end
    end
    traceX, traceY, traceMs = px, py, nowMs
end

-- So aritmetica: roda por passada de follow, e uma leitura de square aqui seria 4 chamadas Java por cao por
-- passada. A validacao do tile mora no goalTileUsable, chamado so quando o path vai de fato ser emitido.
local function followGoalTile(animal, keep, ox, oy, otx, oty, otz)
    if keep <= CD.FOLLOW_START_DIST then return otx, oty, otz end
    local ax, ay = animal:getX(), animal:getY()
    local dx, dy = ax - ox, ay - oy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.5 then return otx, oty, otz end
    if dist <= keep then return math.floor(ax), math.floor(ay), otz end
    return math.floor(ox + dx / dist * keep), math.floor(oy + dy / dist * keep), otz
end

local function goalTileUsable(gx, gy, gz)
    local cell = getCell()
    local sq = cell and cell:getGridSquare(gx, gy, gz)
    return sq ~= nil and not sq:isSolid() and not sq:isSolidTrans() and CD.squareHasFloor(sq)
end

local function followRepath(animal, owner, d, nowMs, gap, keep)
    -- pathTo* e fire-and-forget e re-emitir cancela o A* em voo: PathFindBehavior2.setData() nao tem
    -- guard de igualdade de goal, e o cao fica com o path eternamente nao resolvido, correndo no lugar.
    local ox, oy = owner:getX(), owner:getY()
    local otx, oty, otz = math.floor(ox), math.floor(oy), math.floor(owner:getZ())
    local gtx, gty, gtz = followGoalTile(animal, keep or CD.FOLLOW_START_DIST, ox, oy, otx, oty, otz)
    local pt = d.followPathTile
    local sameGoal = pt and pt.x == gtx and pt.y == gty and pt.z == gtz

    CD.pathStatHijack(animal, "follow")

    local px, py = animal:getX(), animal:getY()
    local moved = d.followLastX and (math.abs(px - d.followLastX) + math.abs(py - d.followLastY)) or 999
    if moved >= CD.FOLLOW_STALL_EPS then
        d.followLastX, d.followLastY, d.followStallMs = px, py, nowMs
    end
    local stalled = d.followStallMs and (nowMs - d.followStallMs) >= CD.FOLLOW_STALL_REPATH_MS
    local sinceIssue = (d.followPathMs and (nowMs - d.followPathMs)) or 999999

    if sameGoal and (not stalled or sinceIssue < CD.FOLLOW_PATH_RESOLVE_MS) then
        followTrace(animal, d, nowMs, px, py, gap, "skip-samegoal")
        CD.forcePathfind(animal)
        return
    end
    local outOfRoad, drifted = false, false
    if pt then
        local dx, dy = px - (pt.x + 0.5), py - (pt.y + 0.5)
        local lead = CD.FOLLOW_REPATH_LEAD
        outOfRoad = (dx * dx + dy * dy) <= (lead * lead)
        drifted = (math.abs(gtx - pt.x) + math.abs(gty - pt.y)) > CD.FOLLOW_GOAL_DRIFT
    end
    local failed = d.pathFailMs and (nowMs - d.pathFailMs) < CD.STUCK_RECENT_FAIL_MS
    if pt and not stalled then
        if sinceIssue < CD.FOLLOW_COMMIT_MS and not (outOfRoad or drifted or failed) then
            followTrace(animal, d, nowMs, px, py, gap, "skip-commit")
            CD.forcePathfind(animal)
            return
        end
        if sinceIssue < CD.FOLLOW_REPATH_MS then
            followTrace(animal, d, nowMs, px, py, gap, "skip-floor")
            CD.forcePathfind(animal)
            return
        end
    end

    followTrace(animal, d, nowMs, px, py, gap, "EMIT")
    d.followPathMs = nowMs
    d.followLastX, d.followLastY, d.followStallMs = px, py, nowMs

    CD.letMove(animal)
    CD.pathStatEmit(animal, "follow")
    -- Sem fallback pra pathToLocation: excecao dentro do pathToCharacter e capturada pelo MethodCaller
    -- e nunca chega ao Lua, e o pathToLocation carrega as mesmas guardas de corda.
    if gtx ~= otx or gty ~= oty or gtz ~= otz then
        -- Ponto da folga em parede, movel ou vazio: cai pro dono, o alvo que sempre funcionou. A validacao fica
        -- aqui e nao no calculo do objetivo pra que ela custe por EMISSAO (no maximo 4/s) e nao por passada.
        if not goalTileUsable(gtx, gty, gtz) then
            gtx, gty, gtz = otx, oty, otz
        end
    end
    d.followPathTile = { x = gtx, y = gty, z = gtz }
    if gtx == otx and gty == oty and gtz == otz then
        animal:pathToCharacter(owner)
    else
        animal:pathToLocation(gtx, gty, gtz)
    end
    CD.forcePathfind(animal)
    if CD.DEBUG_PATH then
        CD.logPath(animal, "follow", gtx, gty)
    end
end

local function followOwner(animal, owner)
    CD.followMaintainDogs[animal:getOnlineID()] = animal
    if not owner:getCurrentSquare() then return end
    local d = CD.data(animal)
    -- Sob autoridade de client o servidor so recebe a posicao; emitir rota aqui puxaria dos dois lados.
    if CD.netAuthUpdate(animal, d, owner) then return end
    refreshOwnerCrossedDoor(owner, d, getTimestampMs())
    CD.standUp(animal)
    local gap = CD.dist2D(animal, owner)
    -- Uma leitura por passada, reusada ate o fim: este corpo roda por cao a cada FOLLOW_TICK_INTERVAL ticks,
    -- entao cada re-leitura aqui e um getModData por cao por passada num servidor cheio.
    local keepDist, runDist = CD.followKeepFrom(d), CD.followRunFrom(d)

    if d.fenceHop then
        if CD.fenceHopping[animal:getOnlineID()] then
            CD.holdStill(animal)
            return
        end
        CD.clearClimbVars(animal)
    end

    if animal:getVariableBoolean("ClimbFence") then
        CD.clearClimbVars(animal)
    end

    if gap > CD.TELEPORT_DIST then
        CD.teleportRecover(animal, owner)
        d.running = nil
        d.climbTries = nil
        d.followPathTile = nil
        d.fenceTraversal = nil
        return
    end

    if math.floor(owner:getZ()) ~= math.floor(animal:getZ()) then
        d.followPathTile = nil
        d.climbTries = (d.climbTries or 0) + 1
        if d.climbTries > CD.STAIR_CLIMB_MAX_TRIES then
            CD.teleportRecover(animal, owner)
            d.running = nil
            d.climbTries = nil
            return
        end
        local srun = CD.mayRunFrom(d)
        d.running = srun
        CD.letMove(animal)
        animal:setVariable("animalRunning", srun)
        animal:setVariable("animalSpeed", srun and CD.runAnimSpeed() or CD.walkAnimSpeed())
        CD.pathStatEmit(animal, "escada")
        animal:pathToCharacter(owner)
        CD.forcePathfind(animal)
        return
    end
    d.climbTries = nil

    if animal:shouldFollowWall() then
        d.pathFailMs = getTimestampMs()
        animal:setShouldFollowWall(false)
        refreshOpenDoorsNear(animal, owner, d, getTimestampMs())
    end

    do
        local px, py = animal:getX(), animal:getY()
        local r = CD.FENCE_STALL_RADIUS
        if (not d.fenceAnchorX) or gap <= keepDist
           or (math.abs(px - d.fenceAnchorX) + math.abs(py - d.fenceAnchorY)) > r then
            d.fenceAnchorX, d.fenceAnchorY, d.fenceAnchorMs = px, py, getTimestampMs()
            d.fenceStallMs = nil
        else
            d.fenceStallMs = d.fenceAnchorMs
        end
    end

    local now = getTimestampMs()
    if followFenceHop(animal, owner, d, gap, now, runDist) then return end

    if tryStuckTeleport(animal, owner, d, gap, now) then return end

    local oid = owner:getOnlineID()
    local nowMs = getTimestampMs()
    local ox, oy = owner:getX(), owner:getY()
    local oms = ownerMoveState[oid]
    local ownerStationary = false
    if oms and (math.abs(ox - oms.x) + math.abs(oy - oms.y)) < CD.OWNER_STILL_EPS then
        ownerStationary = (nowMs - oms.sinceMs) >= CD.OWNER_STILL_MS
    else
        ownerMoveState[oid] = { x = ox, y = oy, sinceMs = nowMs }
    end

    local osp = ownerSpeed[oid]
    if osp then
        local dt = (nowMs - osp.ms) / 1000
        if dt >= 0.1 then
            local sdx, sdy = ox - osp.x, oy - osp.y
            local inst = math.sqrt(sdx * sdx + sdy * sdy) / dt
            osp.spd = (osp.spd or inst) * (1 - CD.OWNER_SPEED_SMOOTH) + inst * CD.OWNER_SPEED_SMOOTH
            osp.x, osp.y, osp.ms = ox, oy, nowMs
        end
    else
        ownerSpeed[oid] = { x = ox, y = oy, ms = nowMs, spd = 0 }
    end

    local settledInSlack = keepDist > CD.FOLLOW_START_DIST

    if gap <= keepDist then
        if ownerStationary or settledInSlack then
            d.running = nil
            animal:setVariable("animalRunning", false)
            animal:setVariable("animalSpeed", 1.0)
            CD.holdStill(animal)
            CD.updateIdleVariation(animal)
            d.followPathTile = nil
            return
        end
    end

    local dwellMs = CD.FOLLOW_DWELL_MS
    if dwellMs > 0 then
        if d.dwellUntil and (nowMs >= d.dwellUntil or gap > runDist) then
            d.dwellUntil = nil
        elseif not d.dwellUntil and d.running == true and gap <= keepDist then
            d.dwellUntil = nowMs + dwellMs
        end
    end

    local run = d.running == true
    if gap > runDist then run = true
    elseif owner:isRunning() or owner:isSprinting() then run = true
    elseif gap <= keepDist + 1 then run = false end
    if d.dwellUntil then
        run = false
    end
    run = run and CD.mayRunFrom(d)
    d.running = run

    animal:setVariable("animalSpeed", run and CD.runAnimSpeed() or CD.walkAnimSpeed())
    animal:setVariable("animalRunning", run)
    local rs = CD.PATH_RUN_SCALE
    if gap <= runDist then
        rs = owner:isSprinting() and CD.PATH_RUN_SPRINT_SCALE or CD.PATH_RUN_CRUISE_SCALE
        local msp = ownerSpeed[oid] and ownerSpeed[oid].spd or 0
        if msp > 0.5 then
            local m = msp * CD.CRUISE_MARGIN / CD.RUN_CLIP_RATE
            if m > rs then
                rs = m
            end
            if rs > CD.PATH_RUN_SCALE then
                rs = CD.PATH_RUN_SCALE
            end
        end
    end
    local ws = walkScaleFrom(d)
    if CD.DEBUG_FOLLOW_TRACE then
        d._rs, d._ws = rs, ws
    end
    CD.applyGaitScale(animal, rs, ws, d)

    if followSteerGate(animal, owner, d, gap, nowMs, run) then return end

    return followRepath(animal, owner, d, nowMs, gap, keepDist)
end
CD.followOwner = followOwner
CD.tickFenceSteer = tickFenceSteer
CD.tickFollowSteer = tickFollowSteer
