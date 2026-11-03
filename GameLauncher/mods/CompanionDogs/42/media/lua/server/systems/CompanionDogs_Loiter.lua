CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local loiter = {}
CD.loiterState = loiter

local ST_REST, ST_IDLE, ST_WALK, ST_DWELL, ST_FEED = "rest", "idle", "walk", "dwell", "feed"

local function rnd(lo, hi) return lo + ZombRand(hi - lo + 1) end

local function loiterLog(a, rec, tag, tx, ty)
    if not CD.DEBUG_LOITER then return end
    local d = CD.data(a)
    CD.log(string.format("[CD-LOITER] cao=%s %s -> %s pos=(%.1f,%.1f) ancora=(%.1f,%.1f) alvo=(%s,%s)",
        tostring(CD.animKey(a)), tostring(rec.st), tag, a:getX(), a:getY(),
        d.loiterX or -1, d.loiterY or -1, tostring(tx), tostring(ty)))
end

local function loiterBeat(a, rec, msg)
    if not CD.DEBUG_LOITER then return end
    local now = getTimestampMs()
    if rec.logMs and now - rec.logMs < 5000 then return end
    rec.logMs = now
    CD.log(string.format("[CD-LOITER] cao=%s estado=%s falta=%dms pos=(%.1f,%.1f) deitado=%s %s",
        tostring(CD.animKey(a)), tostring(rec.st), (rec.untilMs or now) - now, a:getX(), a:getY(),
        tostring(CD.restState[CD.animKey(a)] or false), msg or ""))
end

local function enter(a, rec, st, ms, tx, ty, act)
    loiterLog(a, rec, act or st, tx, ty)
    rec.st, rec.untilMs = st, getTimestampMs() + ms
end

-- O posto e FIXO: so muda por ordem do dono (setstate) ou se o cao reaparecer longe (teleporte, resgate).
local function ensureAnchor(a, d)
    local ax, ay, az = d.loiterX, d.loiterY, d.loiterZ
    if ax then
        local dx, dy = a:getX() - ax, a:getY() - ay
        local lim = CD.LOITER_REANCHOR_DIST
        if az ~= math.floor(a:getZ()) or (dx * dx + dy * dy) > lim * lim then
            ax = nil
        end
    end
    if not ax then
        ax, ay, az = a:getX(), a:getY(), math.floor(a:getZ())
        d.loiterX, d.loiterY, d.loiterZ = ax, ay, az
    end
    return ax, ay, az
end

-- A cerca e a CASA, nao o comodo: predio pelo id, e ao ar livre so ao ar livre.
local function areaKey(sq)
    local b = sq:getBuilding()
    if b then return b:getID() end
    return sq:isOutside() and -1 or -2
end

local function pickSquare(a, rec, ax, ay, az, r, minStep)
    local cell = getCell()
    if not cell then return nil end
    local home = cell:getGridSquare(math.floor(ax), math.floor(ay), az)
    if not home then return nil end
    local area = areaKey(home)
    local bad, nowMs = rec.bad, getTimestampMs()
    local pts, ptr2 = rec.badPts, CD.LOITER_BADPT_R * CD.LOITER_BADPT_R
    local x0, y0 = math.floor(ax), math.floor(ay)
    local fx, fy = a:getX(), a:getY()
    minStep = minStep or CD.LOITER_MIN_STEP
    local min2 = minStep * minStep
    for _ = 1, CD.LOITER_PICK_TRIES do
        local sq = cell:getGridSquare(ZombRand(x0 - r, x0 + r + 1), ZombRand(y0 - r, y0 + r + 1), az)
        local blocked = false
        if sq and bad then
            local until_ = bad[tostring(sq:getRoomID())]
            blocked = until_ ~= nil and nowMs < until_
        end
        if sq and not blocked and pts then
            for i = 1, #pts do
                local pt = pts[i]
                if nowMs < pt.untilMs then
                    local pdx, pdy = sq:getX() - pt.x, sq:getY() - pt.y
                    if (pdx * pdx + pdy * pdy) <= ptr2 then
                        blocked = true
                        break
                    end
                end
            end
        end
        if sq and not blocked and sq:isFree(true) and areaKey(sq) == area then
            local cx, cy = sq:getX() + 0.5, sq:getY() + 0.5
            local ddx, ddy = cx - ax, cy - ay
            local sx, sy = cx - fx, cy - fy
            if (ddx * ddx + ddy * ddy) <= r * r and (sx * sx + sy * sy) >= min2 then return sq end
        end
    end
    return nil
end

local function bowlNear(a, ax, ay, az, r, wantFood)
    local o, _, bx, by, bz = CD.findTroughNear(a, r, wantFood == true, wantFood ~= true)
    if not o then return nil end
    local cell = getCell()
    local home = cell and cell:getGridSquare(math.floor(ax), math.floor(ay), az)
    local sq = cell and cell:getGridSquare(math.floor(bx), math.floor(by), math.floor(bz))
    if not home or not sq then return nil end
    if areaKey(sq) ~= areaKey(home) then return nil end
    local ddx, ddy = (sq:getX() + 0.5) - ax, (sq:getY() + 0.5) - ay
    if (ddx * ddx + ddy * ddy) > r * r then return nil end
    return sq
end

local function startWalk(a, rec, sq, run)
    if not sq then return false end
    CD.standUp(a)
    rec.tx, rec.ty = sq:getX() + 0.5, sq:getY() + 0.5
    rec.troom = sq:getRoomID()
    a:setStateEventDelayTimer(CD.LOITER_WANDER_HOLD)
    rec.bestGap, rec.progMs = nil, getTimestampMs()
    CD.moveTo(a, run, run and CD.runAnimSpeed() or 1.0, sq:getX(), sq:getY(), sq:getZ(), "vadiagem", nil, "vadiagem")
    -- moveTo carimba a escala cheia; a marcha e latchada na entrada do node, entao a correcao tem que
    -- vir aqui, no mesmo tick, e nao no sweep do proximo.
    CD.applyGaitScale(a, CD.PATH_RUN_IDLE_SCALE)
    enter(a, rec, ST_WALK, CD.LOITER_WALK_TIMEOUT_MS, sq:getX(), sq:getY(), run and "run" or "walk")
    return true
end

-- A var de comer/beber so cai sozinha 3 s depois do ultimo pulso: sem isso ela atravessa a acao seguinte.
local function stopFeedAnim(a, rec)
    if not rec.feedVar then return end
    CD.emitEatVar(a, false, rec.feedVar)
    CD.pendingClears.eat[CD.animKey(a)] = nil
    rec.feedVar = nil
end

local function pickFrom(list)
    if not list then return "idle" end
    local total = 0
    for i = 1, #list do total = total + (list[i].w or 0) end
    if total <= 0 then return "idle" end
    local roll = ZombRand(total)
    for i = 1, #list do
        roll = roll - (list[i].w or 0)
        if roll < 0 then return list[i].act end
    end
    return "idle"
end

local function sniffHere(a)
    CD.pulseSniffAnim(a, "vadiagem")
    CD.idleVarNext[CD.animKey(a)] = getTimestampMs() + CD.HANDFEED_EAT_MS + CD.IDLE_GAP_MIN_MS
end

local function park(a, rec, failed)
    a:setVariable("animalRunning", false)
    a:setVariable("animalSpeed", 1.0)
    CD.holdStill(a)
    local want = rec.after
    rec.after = nil
    if want == "feed" then
        local dx, dy = a:getX() - (rec.tx or a:getX()), a:getY() - (rec.ty or a:getY())
        if (dx * dx + dy * dy) <= CD.LOITER_ARRIVE_DIST * CD.LOITER_ARRIVE_DIST then
            enter(a, rec, ST_FEED, rnd(CD.LOITER_FEED_MS_MIN, CD.LOITER_FEED_MS_MAX), nil, nil, "tigela")
            return
        end
    end
    if failed then
        local act = pickFrom(CD.LOITER_STUCK_ACTIONS)
        if act == "rest" and not CD.restAnimEnabled(a) then
            act = "sniff"
        end
        if act == "rest" then
            enter(a, rec, ST_REST, rnd(CD.LOITER_REST_MS_MIN, CD.LOITER_REST_MS_MAX), nil, nil, act)
            return
        end
        if act == "eat" or act == "drink" then
            rec.feedVar = (act == "drink") and CD.DRINK_ANIM_VAR or CD.EAT_ANIM_VAR
            enter(a, rec, ST_FEED, rnd(CD.LOITER_FEED_MS_MIN, CD.LOITER_FEED_MS_MAX), nil, nil, act)
            return
        end
        if act == "sniff" then
            sniffHere(a)
        elseif act == "bark" then
            CD.barkOnce(a)
        end
        enter(a, rec, ST_DWELL, rnd(CD.LOITER_DWELL_MS_MIN, CD.LOITER_DWELL_MS_MAX), nil, nil, act)
        return
    end
    if ZombRand(100) < CD.LOITER_SNIFF_PCT then
        sniffHere(a)
    end
    enter(a, rec, ST_DWELL, rnd(CD.LOITER_DWELL_MS_MIN, CD.LOITER_DWELL_MS_MAX))
end

local function pickNext(a, rec, ax, ay, az, r)
    local act = pickFrom(CD.LOITER_ACTIONS)
    rec.after = nil
    if act == "rest" and (rec.st == ST_REST or not CD.restAnimEnabled(a)) then
        act = "walk"
    end
    if act == "rest" then
        enter(a, rec, ST_REST, rnd(CD.LOITER_REST_MS_MIN, CD.LOITER_REST_MS_MAX), nil, nil, act)
        return
    end
    if act == "eat" or act == "drink" then
        rec.feedVar = (act == "drink") and CD.DRINK_ANIM_VAR or CD.EAT_ANIM_VAR
        local sq = bowlNear(a, ax, ay, az, r, act == "eat")
        if sq then
            local dx, dy = a:getX() - (sq:getX() + 0.5), a:getY() - (sq:getY() + 0.5)
            if (dx * dx + dy * dy) <= CD.TROUGH_REACH_DIST * CD.TROUGH_REACH_DIST then
                enter(a, rec, ST_FEED, rnd(CD.LOITER_FEED_MS_MIN, CD.LOITER_FEED_MS_MAX), nil, nil, act)
                return
            end
            rec.after = "feed"
            if startWalk(a, rec, sq, false) then return end
            rec.after = nil
        end
        act = "walk"
    end
    if act == "bark" then
        CD.barkOnce(a)
    end
    if act == "walk" or act == "run" then
        local run = act == "run"
        local sq = pickSquare(a, rec, ax, ay, az, r, run and CD.LOITER_RUN_MIN_STEP or CD.LOITER_MIN_STEP)
        if startWalk(a, rec, sq, run) then return end
        if CD.DEBUG_LOITER then
            CD.log(string.format("[CD-LOITER] cao=%s sem tile livre no raio %d em volta de (%.1f,%.1f,%d)",
                tostring(CD.animKey(a)), r, ax, ay, az))
        end
    end
    enter(a, rec, ST_IDLE, rnd(CD.LOITER_IDLE_MS_MIN, CD.LOITER_IDLE_MS_MAX), nil, nil, act)
end

---@param key integer|nil the already resolved CD.animKey(a), spares two Java calls per caller that has it
local function loiterDriving(a, key)
    local rec = loiter[key or CD.animKey(a)]
    return rec ~= nil and rec.st == ST_WALK
end

local function loiterForget(a)
    loiter[CD.animKey(a)] = nil
end

local function tickLoiter(a)
    local d = CD.data(a)
    local oid = CD.animKey(a)
    if not CD.passiveIdleEnabled() or d.inCombat or d.autoFeeding or d.retreating or d.fenceHop or d.mounted then
        loiter[oid] = nil
        CD.holdStill(a)
        if CD.DEBUG_LOITER then
            CD.log(string.format("[CD-LOITER] cao=%s BARRADO sandbox=%s inCombat=%s autoFeeding=%s retreating=%s fenceHop=%s montado=%s",
                tostring(oid), tostring(CD.passiveIdleEnabled()), tostring(d.inCombat), tostring(d.autoFeeding),
                tostring(d.retreating), tostring(d.fenceHop ~= nil), tostring(d.mounted or false)))
        end
        return
    end
    local rec = loiter[oid]
    if rec and rec.st ~= ST_FEED and rec.after ~= "feed" and rec.feedVar then
        stopFeedAnim(a, rec)
    end
    if not rec then
        rec = { st = ST_IDLE, untilMs = getTimestampMs() + rnd(CD.LOITER_IDLE_MS_MIN, CD.LOITER_IDLE_MS_MAX) }
        loiter[oid] = rec
        loiterLog(a, rec, "inicio")
    end
    local r = CD.passiveIdleRadius(CD.getOwnerPlayer(a))
    local ax, ay, az = ensureAnchor(a, d)
    local now = getTimestampMs()

    if rec.st == ST_WALK then
        local dx, dy = a:getX() - rec.tx, a:getY() - rec.ty
        local gap = math.sqrt(dx * dx + dy * dy)
        if CD.DEBUG_LOITER then
            loiterBeat(a, rec, string.format("alvo=(%.1f,%.1f) falta=%.2f melhor=%.2f", rec.tx, rec.ty, gap, rec.bestGap or gap))
        end
        local arrived = gap <= CD.LOITER_ARRIVE_DIST
        -- Alvo inalcancavel move o cao um passo por passada sem nunca encurtar o vao: a trava e PROGRESSO, nao deslocamento.
        if rec.bestGap == nil or gap < (rec.bestGap - CD.LOITER_PROGRESS_EPS) then
            rec.bestGap, rec.progMs = gap, now
        end
        local stalled = not arrived and (now - (rec.progMs or now)) >= CD.LOITER_STALL_MS
        if not arrived and (stalled or now >= rec.untilMs) then
            -- So o comodo do OUTRO lado da porta entra na lista: barrar o proprio comodo deixaria o cao sem destino.
            local msq = a:getCurrentSquare()
            local myRoom = msq and msq:getRoomID() or -1
            if rec.troom and rec.troom ~= -1 and rec.troom ~= myRoom then
                rec.bad = rec.bad or {}
                rec.bad[tostring(rec.troom)] = now + CD.LOITER_BADROOM_MS
            end
            rec.badPts = rec.badPts or {}
            table.insert(rec.badPts, { x = math.floor(rec.tx), y = math.floor(rec.ty), untilMs = now + CD.LOITER_BADROOM_MS })
            while #rec.badPts > CD.LOITER_BADPT_MAX do table.remove(rec.badPts, 1) end
            loiterLog(a, rec, "sem-caminho", rec.tx, rec.ty)
        end
        if arrived or stalled or now >= rec.untilMs then
            park(a, rec, not arrived)
        else
            -- wanderIdle roda nas frestas em que o cao nao esta se movendo (o A* ainda em voo, por
            -- exemplo) e re-caminha o animal para perto do dono, cancelando o pedido em curso.
            if a:getStateEventDelayTimer() < CD.LOITER_WANDER_HOLD * 0.5 then
                a:setStateEventDelayTimer(CD.LOITER_WANDER_HOLD)
            end
            CD.forcePathfind(a)
        end
        return
    end

    if CD.DEBUG_LOITER then
        loiterBeat(a, rec, string.format("ancora=(%.1f,%.1f,%d) raio=%d", ax, ay, az, r))
    end
    CD.holdStill(a)
    local ddx, ddy = a:getX() - ax, a:getY() - ay
    if (ddx * ddx + ddy * ddy) > (r + 1) * (r + 1) then
        local home = getCell():getGridSquare(math.floor(ax), math.floor(ay), az)
        if startWalk(a, rec, home, false) then return end
    end

    if rec.st == ST_REST then
        CD.setRest(a, true)
    elseif rec.st == ST_FEED then
        if rec.feedVar == CD.DRINK_ANIM_VAR then
            CD.pulseDrinkAnim(a, true, "vadiagem")
        else
            CD.pulseEatAnim(a, true, "vadiagem")
        end
    else
        CD.updateIdleVariation(a)
    end
    if now < rec.untilMs then return end
    if rec.st == ST_REST then
        CD.standUp(a)
    end
    if rec.st == ST_FEED then
        stopFeedAnim(a, rec)
    end
    pickNext(a, rec, ax, ay, az, r)
end

CD.tickLoiter = tickLoiter
CD.loiterForget = loiterForget
CD.loiterDriving = loiterDriving
