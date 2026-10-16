CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.careAref = { x = 0, y = 0, z = nil, a = nil }
---Stand-in reference at the care anchor, read by the zombie scan and the fence search like a character.
---@return number
---@nodiscard
CD.careAref.getX = function() return CD.careAref.x end
---@return number
---@nodiscard
CD.careAref.getY = function() return CD.careAref.y end
---@return number the anchor floor, or the dog's own when the anchor has none
---@nodiscard
CD.careAref.getZ = function() return CD.careAref.z or CD.careAref.a:getZ() end

-- Substituto do zone:getRandomFreeSquare(): a versao da engine chama isFree num square nil, e o NPE
-- que sai dali e excecao Java, capturada pela engine antes de virar erro de Lua.
---A free tile inside the zone, preferring one at least minD from fx, fy; 32 random tries, then the farthest one found.
---@param zone DesignationZoneAnimal|nil
---@param fx number|nil
---@param fy number|nil
---@param minD number|nil tiles
---@return IsoGridSquare|nil
---@nodiscard
CD.careRandomFreeSquare = function(zone, fx, fy, minD)
    local cell = getCell()
    if not cell or not zone then return nil end
    local zx, zy, zz, zw, zh
    zx, zy, zz, zw, zh = zone:getX(), zone:getY(), zone:getZ(), zone:getW(), zone:getH()
    if not zx or not zw or not zh or zw <= 0 or zh <= 0 then return nil end
    local x0, x1 = zx + 1, zx + zw - 2
    local y0, y1 = zy + 1, zy + zh - 2
    if x1 < x0 then
        x0, x1 = zx, zx + zw - 1
    end
    if y1 < y0 then
        y0, y1 = zy, zy + zh - 1
    end
    local best, bestD2 = nil, -1
    local min2 = (minD or 0) * (minD or 0)
    for _ = 1, 32 do
        local sq = cell:getGridSquare(ZombRand(x0, x1 + 1), ZombRand(y0, y1 + 1), zz)
        if sq then
            local free = sq:isFree(true)
            if free then
                if not fx then return sq end
                local dx, dy = (sq:getX() + 0.5) - fx, (sq:getY() + 0.5) - fy
                local d2 = dx * dx + dy * dy
                if d2 >= min2 then return sq end
                if d2 > bestD2 then
                    best, bestD2 = sq, d2
                end
            end
        end
    end
    return best
end

local function careAlert(owner, a, d, kind, now)
    if not owner then return end
    if d.lastCareAlertMin and (now - d.lastCareAlertMin) < CD.careAlertCooldownMin() then return end
    d.lastCareAlertMin = now
    CD.notifyOwner(owner, "carealert", { id = a:getOnlineID(), kind = kind, breed = CD.getBreed(a) })
end

-- descreve a aresta entre o cao e o alvo para o log de cuidado; nil se nao ha aresta
local function careEdgeInfo(a, z)
    local cell = getCell()
    local ax, ay, az = math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ())
    local zx, zy = math.floor(z:getX()), math.floor(z:getY())
    local sdx, sdy = 0, 0
    if math.abs(zx - ax) >= math.abs(zy - ay) then sdx = (zx > ax) and 1 or ((zx < ax) and -1 or 0)
    else sdy = (zy > ay) and 1 or ((zy < ay) and -1 or 0) end
    local from = cell:getGridSquare(ax, ay, az)
    local to = cell:getGridSquare(ax + sdx, ay + sdy, az)
    if not from or not to then return nil end
    local owner, hop, tall, trans
    if sdx > 0 then     owner, hop, tall, trans = to,   IsoFlagType.HoppableW, IsoFlagType.TallHoppableW, IsoFlagType.WallWTrans
    elseif sdx < 0 then owner, hop, tall, trans = from, IsoFlagType.HoppableW, IsoFlagType.TallHoppableW, IsoFlagType.WallWTrans
    elseif sdy > 0 then owner, hop, tall, trans = to,   IsoFlagType.HoppableN, IsoFlagType.TallHoppableN, IsoFlagType.WallNTrans
    else                owner, hop, tall, trans = from, IsoFlagType.HoppableN, IsoFlagType.TallHoppableN, IsoFlagType.WallNTrans
    end
    local function fl(f) return owner:has(f) and 1 or 0 end
    local sprites = {}
    local objs = owner:getObjects()
    for i = 0, math.min(objs and objs:size() or 0, 4) - 1 do
        local sp = objs:get(i):getSprite()
        if sp and sp:getName() then
            sprites[#sprites + 1] = sp:getName()
        end
    end
    local sfw = a:shouldFollowWall()
    return string.format("passo=%d,%d hop=%d tall=%d trans=%d lowCross=%s sfw=%s sprites=[%s]",
        sdx, sdy, fl(hop), fl(tall), fl(trans),
        tostring(CD.lowFenceCrossable(from, to, sdx, sdy)), tostring(sfw), table.concat(sprites, ","))
end

local function careDebug(a, z, gap, tag)
    if not CD.CARE_DEBUG then return end
    local info = careEdgeInfo(a, z) or "sem-aresta"
    CD.log(string.format("[CD-CARE] %s cao=(%d,%d) alvo=(%d,%d) gap=%.1f %s", tag,
        math.floor(a:getX()), math.floor(a:getY()), math.floor(z:getX()), math.floor(z:getY()), gap, info))
end

local function careLog(a, d, tag, gap, gx, gy)
    if not CD.CARE_DEBUG then return end
    local goal = gx and string.format("(%d,%d)", gx, gy) or nil
    if CD.careWatch then
        local r = CD.careWatch[a:getOnlineID()]
        if r and (r.gx ~= gx or r.gy ~= gy) then
            if r.gx and (r.walked or 0) > 1 then
                local net = math.abs(a:getX() - (r.ox or 0)) + math.abs(a:getY() - (r.oy or 0))
                CD.log(string.format("[CD-CARE~] objetivo (%d,%d) encerrado: andou %.1f tiles, liquido %.1f, eficiencia %.2f, distFinal %.1f, %d ticks",
                    r.gx, r.gy, r.walked or 0, net, (r.walked or 0) > 0 and (net / r.walked) or 0,
                    r.lastDg or -1, r.ticks or 0))
            end
            r.gx, r.gy = gx, gy
            r.bestDg, r.lastDg, r.walked, r.ticks, r.warned = nil, nil, 0, 0, nil
            r.ox, r.oy = a:getX(), a:getY()
        end
    end
    d._careN = (d._careN or 0) + 1
    if d._careTag == tag and (d._careN % 20) ~= 0 then return false end
    d._careTag = tag
    local inZone = "?"
    if a then
        inZone = (DesignationZoneAnimal.getZone(math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ())) ~= nil)
                 and "S" or "N"
    end
    CD.log(string.format("[CD-CARE] %-16s cao=(%.1f,%.1f,%d) noCurral=%s ancora=(%s,%s) zumbi=%s alvo=%s lock=%s hop=%s",
        tag, a:getX(), a:getY(), math.floor(a:getZ()), inZone,
        tostring(d.careX or "-"), tostring(d.careY or "-"),
        gap and string.format("%.1f", gap) or "-", goal or "-",
        d.lockX and "SIM" or "-", d.fenceHop and "SIM" or "-"))
    return true
end

local function careDrive(a, d, tx, ty, run)
    d.careHold, d.careWantTx, d.careWantTy, d.careWantRun = false, tx, ty, run
    CD.standUp(a)
end

local function careVault(a, ref, d, anchorPt)
    if not CD.COMBAT_FENCE_HOP then return false, nil end
    if isServer() and not CD.COMBAT_FENCE_HOP_MP then return false, nil end
    local nowMs = getTimestampMs()
    local function mark()
        d.cstall = nil
        d.careHold, d.careWantTx, d.careWantTy = false, nil, nil
        CD.standUp(a)
        d.combatHop, d.careHop = true, true
        if anchorPt then
            d.careHopTx, d.careHopTy = anchorPt.x + 0.5, anchorPt.y + 0.5
            CD.combatTarget[a:getOnlineID()] = nil
        else
            d.careHopTx, d.careHopTy = nil, nil
            CD.combatTarget[a:getOnlineID()] = ref
        end
    end
    local toSq, dx, dy, key = CD.findFenceCrossing(a, ref, d, nowMs, CD.lowFenceCrossable)
    if toSq then
        mark()
        CD.startFenceHop(a, toSq, dx, dy, nil, key)
        return true, nil
    end
    local fSq, fdx, fdy, fkey, nearSq = CD.findFenceTowardOwner(a, ref, CD.FENCE_GHOST_SCAN, d, nowMs, CD.lowFenceCrossable)
    if fSq and nearSq then
        local cs = a:getCurrentSquare()
        if cs and cs:getX() == nearSq:getX() and cs:getY() == nearSq:getY() then
            mark()
            CD.startFenceHop(a, fSq, fdx, fdy, nil, fkey)
            return true, nil
        end
        return false, nearSq
    end
    return false, nil
end

local function careCombat(a, ax, ay, az, d, hid, now, owner)
    CD.careAref.x, CD.careAref.y, CD.careAref.z, CD.careAref.a = ax, ay, az, a
    if CD.combatTarget[hid] or d.fenceHop or d.careHop or CD.landGlide[hid] then
        CD.scanAlert(d)
    end
    local z, count
    if not CD.scanQuietSkip(d) then
        z, count = CD.pz("srv.care.scan", CD.scanZombies, a, CD.careRadius(), nil,
                          CD.careAref, false, CD.CARE_DETOUR_FACTOR)
        CD.scanQuietResult(d, z ~= nil or (count or 0) > 0)
    end
    if z then
        d.carePatrolTx, d.carePatrolTy, d.carePatrolArr = nil, nil, nil
        local gap = CD.dist2D(a, z)
        if gap <= CD.STRIKE_DIST and not CD.pathBlocked(a, z) then
            CD.standUp(a)
            a:faceThisObject(z)
            CD.strikeExchange(a, z)
            CD.addSkillXP(a, "herding", CD.CARE_XP_PER_KILL)
            d.cstall = nil
            d.careGoalTx, d.careGoalTy = nil, nil
            d.careHold, d.careWantTx, d.careWantTy = true, nil, nil
            CD.holdStill(a)
            careLog(a, d, "GOLPE", gap, nil)
            careAlert(owner, a, d, "zombie", now)
            return true
        end
        local hopped, nearSq = careVault(a, z, d)
        if hopped then
            careLog(a, d, "PULOU-CERCA", gap, nil)
            careDebug(a, z, gap, "vault")
            careAlert(owner, a, d, "zombie", now)
            return true
        end
        local nowMs = getTimestampMs()
        local st = d.cstall
        if not st then
            st = { bg = gap, ax = a:getX(), ay = a:getY(), sfw = 0 }
            d.cstall = st
        end
        local net = math.abs(a:getX() - st.ax) + math.abs(a:getY() - st.ay)
        local gained = gap + 0.2 < st.bg
        if gained then
            st.bg = gap
        end
        if gained or net > CD.COMBAT_STALL_RADIUS then
            st.ax, st.ay, st.ms, st.sfw = a:getX(), a:getY(), nil, 0
        else
            st.ms = st.ms or nowMs
            local sfw = a:shouldFollowWall()
            st.sfw = sfw and (st.sfw + 1) or 0
        end
        if st.sfw >= 2 or (st.ms and (nowMs - st.ms) > CD.COMBAT_STALL_MS) then
            local id = a:getOnlineID()
            local unr = CD.combatUnreach[id]
            if not unr then
                unr = {}
                CD.combatUnreach[id] = unr
            end
            unr[z] = nowMs + CD.CARE_UNREACH_MS
            d.cstall = nil
            d.careGoalTx, d.careGoalTy = nil, nil
            CD.combatTarget[id] = nil
            careLog(a, d, "DESISTIU", gap, nil)
            careDebug(a, z, gap, "DESISTIU-inalcancavel")
        else
            local tx, ty, tz, tag = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()), "aproximando"
            if nearSq then
                tx, ty, tz, tag = nearSq:getX(), nearSq:getY(), nearSq:getZ(), "indo-a-borda"
            end
            careLog(a, d, nearSq and "INDO-A-BORDA" or "PERSEGUINDO", gap, tx, ty)
            careDrive(a, d, tx, ty, true)
            if d.careGoalTx ~= tx or d.careGoalTy ~= ty then
                d.careGoalTx, d.careGoalTy = tx, ty
                CD.moveTo(a, true, CD.runAnimSpeed(), tx, ty, tz, "gado-zumbi", nil, "gado")
                careDebug(a, z, gap, tag)
            else
                CD.forcePathfind(a)
            end
            careAlert(owner, a, d, "zombie", now)
            return true
        end
    else
        d.cstall = nil
        CD.combatTarget[a:getOnlineID()] = nil
        if CD.CARE_DEBUG then
            local raw, rd = CD.scanSentinelZombies(a, CD.careRadius() + 6)
            if raw and careLog(a, d, "NAO-ENGAJOU", rd, nil) then
                local unr = CD.combatUnreach[a:getOnlineID()]
                local dAnchor = math.sqrt((raw:getX() - ax) ^ 2 + (raw:getY() - ay) ^ 2)
                CD.log(string.format("[CD-CARE] filtrado: zumbi a %.1f do cao e %.1f da ancora (raio %d) | cooldownInalcancavel=%s",
                    rd, dAnchor, CD.careRadius(), tostring(unr and unr[raw] or false)))
            end
        end
    end
    return false
end

local function carePatrol(a, ax, ay, az, d, now, zone)
    local inZone = false
    if a then
        inZone = DesignationZoneAnimal.getZone(math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ())) ~= nil
    end
    if not zone or not inZone then
        d.carePatrolTx, d.carePatrolTy, d.carePatrolArr = nil, nil, nil
        if CD.CARE_DEBUG then
            local raw, rd = CD.scanSentinelZombies(a, CD.careRadius())
            local unr = CD.combatUnreach[a:getOnlineID()]
            CD.log(string.format("[CD-CARE] fora-do-curral cao=(%d,%d) ancora=(%d,%d) zumbiBruto=%s dist=%.1f cooldownInalcancavel=%s",
                math.floor(a:getX()), math.floor(a:getY()), math.floor(ax), math.floor(ay),
                raw and "SIM" or "nao", rd or -1, tostring(raw and unr and unr[raw] or false)))
        end
        local anchor = { x = math.floor(ax), y = math.floor(ay) }
        local aref = { getX = function() return anchor.x + 0.5 end, getY = function() return anchor.y + 0.5 end }
        local hopped, nearSq = careVault(a, aref, d, anchor)
        if hopped then
            careLog(a, d, "VOLTA-PULANDO", nil, nil)
            careDebug(a, aref, 0, "voltando-vault")
        else
            local tx, ty, tz = anchor.x, anchor.y, math.floor(az or a:getZ())
            if nearSq then
                tx, ty, tz = nearSq:getX(), nearSq:getY(), nearSq:getZ()
            end
            careLog(a, d, nearSq and "VOLTA-A-BORDA" or "VOLTANDO", nil, tx, ty)
            careDrive(a, d, tx, ty, true)
            if d.careBackTx ~= tx or d.careBackTy ~= ty then
                d.careBackTx, d.careBackTy = tx, ty
                CD.moveTo(a, true, CD.runAnimSpeed(), tx, ty, tz, "gado-zumbi", nil, "gado")
                careDebug(a, aref, 0, nearSq and "voltando-a-borda" or "voltando")
            else
                CD.forcePathfind(a)
            end
        end
    else
        d.careBackTx, d.careBackTy = nil, nil
        local px, py = d.carePatrolTx, d.carePatrolTy
        local arrived = px == nil
        if px then
            local ddx, ddy = a:getX() - (px + 0.5), a:getY() - (py + 0.5)
            if (ddx * ddx + ddy * ddy) <= 2.25 then
                arrived = true
            end
        end
        if px and arrived and not d.carePatrolArr then
            d.carePatrolArr, d.carePatrolMin = true, now
        end
        if arrived and (not d.carePatrolMin or (now - d.carePatrolMin) >= CD.CARE_PATROL_DWELL_MIN) then
            local nx, ny, nz
            local sq = CD.pz("srv.care.patrol", CD.careRandomFreeSquare,
                             zone, a:getX(), a:getY(), CD.CARE_PATROL_MIN_DIST)
            if sq then
                nx, ny, nz = sq:getX(), sq:getY(), sq:getZ()
            end
            if nx then
                d.carePatrolTx, d.carePatrolTy, d.carePatrolMin = nx, ny, now
                d.carePatrolArr = nil
                careLog(a, d, "PATRULHA", nil, nx, ny)
                careDrive(a, d, nx, ny, false)
                CD.moveTo(a, false, 1.0, nx, ny, nz or math.floor(a:getZ()), "gado-patrulha", nil, "gado")
            else
                careLog(a, d, "PATRULHA-SEM-TILE", nil, nil)
                d.careHold, d.careWantTx, d.careWantTy = true, nil, nil
                CD.holdStill(a)
            end
        elseif px and not arrived then
            careLog(a, d, "INDO-AO-PONTO", nil, px, py)
            careDrive(a, d, px, py, false)
            CD.forcePathfind(a)
        else
            careLog(a, d, "PARADO-NO-POSTO", nil, nil)
            d.careHold, d.careWantTx, d.careWantTy = true, nil, nil
            CD.holdStill(a)
            CD.updateRest(a, d)
        end
    end
end

CD.coopTask = CD.coopTask or {}
CD.coopWait = CD.coopWait or {}
CD.coopCall = CD.coopCall or {}
CD.coopSkip = CD.coopSkip or {}

local COOP_SND_SHUT, COOP_SND_OPEN = "ChickenCoopWoodClose", "ChickenCoopWoodOpen"

local function coopKey(x, y, z) return x .. "," .. y .. "," .. z end

local function coopNightFor(bird)
    if not bird then return nil end
    local adef = bird:getAdef()
    if not adef then return nil end
    return not adef:isOutsideHutchTime()
end

local function coopBirdInside(hutch)
    local n = hutch:getMaxAnimals()
    for i = 0, n - 1 do
        local bird = hutch:getAnimal(i)
        if bird and not bird:isDead() then return bird end
    end
    local nb = hutch:getMaxNestBox()
    for i = 0, nb - 1 do
        local bird = hutch:getAnimalInNestBox(i)
        if bird and not bird:isDead() then return bird end
    end
    return nil
end

local function coopStraggler(zone, hutch)
    local herd = zone:getAnimalsConnected()
    local n = 0
    if herd then
        n = herd:size()
    end
    for i = 0, n - 1 do
        local la = herd:get(i)
        if la and not CD.isDog(la) and not la:isDead() and not la:isWild()
           and la:needHutch() and la:getHutch() == nil and la:canBePutInHutch(hutch) then
            return la
        end
    end
    return nil
end

local function coopDestFor(zone, hutch, bird)
    if hutch:isOpen() and hutch:getAnimalInside():size() < hutch:getMaxAnimals()
       and bird:canBePutInHutch(hutch) then
        return hutch
    end
    local hutches = zone:getHutchsConnected()
    local n = 0
    if hutches then
        n = hutches:size()
    end
    for i = 0, n - 1 do
        local h = hutches:get(i)
        if h and h ~= hutch and h:isOpen() and h:getAnimalInside():size() < h:getMaxAnimals()
           and bird:canBePutInHutch(h) then
            return h
        end
    end
    return nil
end

local function coopHutchAct(hutch, zone, now, key)
    if hutch:isOpen() then
        local bird = coopBirdInside(hutch)
        if not bird then return nil end
        if coopNightFor(bird) ~= true then
            CD.coopWait[key], CD.coopCall[key] = nil, nil
            return nil
        end
        local out = coopStraggler(zone, hutch)
        if out and coopDestFor(zone, hutch, out) then
            local since = CD.coopWait[key]
            if not since then
                CD.coopWait[key] = now
                since = now
            end
            if (now - since) < CD.CARE_COOP_WAIT_MIN then
                local last = CD.coopCall[key]
                if last and (now - last) < CD.CARE_COOP_CALL_MIN then return nil end
                return "call"
            end
        end
        CD.coopWait[key], CD.coopCall[key] = nil, nil
        return "shut"
    end
    if hutch:getModData().cdShut ~= true then return nil end
    local ref = coopBirdInside(hutch) or coopStraggler(zone, hutch)
    if coopNightFor(ref) ~= false then return nil end
    return "open"
end

local function coopDecide(now, zone)
    local hutches = zone:getHutchsConnected()
    local n = 0
    if hutches then
        n = hutches:size()
    end
    for i = 0, n - 1 do
        local hutch = hutches:get(i)
        local sq = nil
        if hutch then
            sq = hutch:getSquare()
        end
        if sq then
            local key = coopKey(sq:getX(), sq:getY(), sq:getZ())
            local skip = CD.coopSkip[key]
            if not skip or now >= skip then
                local act = coopHutchAct(hutch, zone, now, key)
                local esq = act and hutch:getEntrySq() or nil
                if esq then
                    return { x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                             ex = esq:getX(), ey = esq:getY(), ez = esq:getZ(),
                             act = act, sinceMin = now }
                end
            end
        end
    end
    return nil
end

local function coopHutchAt(zone, x, y, z)
    local hutches = zone:getHutchsConnected()
    local n = 0
    if hutches then
        n = hutches:size()
    end
    for i = 0, n - 1 do
        local h = hutches:get(i)
        local sq = nil
        if h then
            sq = h:getSquare()
        end
        if sq and sq:getX() == x and sq:getY() == y and sq:getZ() == z then return h end
    end
    return nil
end

local function coopWorkDoor(a, task, owner, zone, now)
    local hutch = coopHutchAt(zone, task.x, task.y, task.z)
    if not hutch then return end
    local key = coopKey(task.x, task.y, task.z)
    if task.act == "call" then
        CD.coopCall[key] = now
        if not hutch:isOpen() then return end
        local herd = zone:getAnimalsConnected()
        local n = 0
        if herd then
            n = herd:size()
        end
        local called = 0
        for i = 0, n - 1 do
            local la = herd:get(i)
            if la and not CD.isDog(la) and not la:isDead() and not la:isWild()
               and la:needHutch() and la:getHutch() == nil then
                local dest = coopDestFor(zone, hutch, la)
                if dest and la:getBehavior():callToHutch(dest, true) then
                    called = called + 1
                    if called >= CD.CARE_COOP_CALL_MAX then break end
                end
            end
        end
        if called > 0 then
            a:faceThisObject(hutch)
            CD.emitSound(a, CD.breedVoice(a, "bark"))
            CD.addSkillXP(a, "herding", CD.CARE_XP_PER_CALL)
        end
        return
    end
    local shut = task.act == "shut"
    if shut then
        if hutch:isDoorClosed() then return end
    elseif hutch:isOpen() then
        hutch:getModData().cdShut = nil
        return
    end
    a:faceThisObject(hutch)
    hutch:toggleDoor()
    hutch:sync()
    hutch:getModData().cdShut = shut and true or nil
    CD.emitSound(a, shut and COOP_SND_SHUT or COOP_SND_OPEN)
    CD.addSkillXP(a, "herding", CD.CARE_XP_PER_COOP)
    CD.notifyOwner(owner, "carecoop", { id = a:getOnlineID(), act = task.act, breed = CD.getBreed(a) })
    CD.coopWait[key], CD.coopCall[key] = nil, nil
end

local function careCoop(a, d, now, zone, owner)
    if not CD.CARE_COOP_ENABLED or not zone then return false end
    local hid = a:getOnlineID()
    if not SandboxVars.AnimalMetaPredator then
        CD.coopTask[hid] = nil
        return false
    end
    local task = CD.coopTask[hid]
    if not task then
        if d.coopNextMin and now < d.coopNextMin then return false end
        d.coopNextMin = now + CD.CARE_COOP_CHECK_MIN
        task = coopDecide(now, zone)
        if not task then return false end
        CD.coopTask[hid] = task
        d.carePatrolTx, d.carePatrolTy, d.carePatrolArr = nil, nil, nil
        careLog(a, d, task.act == "call" and "GALINHEIRO-CHAMAR"
                   or (task.act == "open" and "GALINHEIRO-ABRIR" or "GALINHEIRO-FECHAR"), nil, task.ex, task.ey)
    end
    if (now - task.sinceMin) > CD.CARE_COOP_TIMEOUT_MIN then
        CD.coopSkip[coopKey(task.x, task.y, task.z)] = now + CD.CARE_COOP_TIMEOUT_MIN
        CD.coopTask[hid] = nil
        d.coopGoalTx, d.coopGoalTy = nil, nil
        careLog(a, d, "GALINHEIRO-DESISTIU", nil, task.ex, task.ey)
        return false
    end
    local ddx, ddy = a:getX() - (task.ex + 0.5), a:getY() - (task.ey + 0.5)
    local reach = CD.CARE_COOP_REACH_DIST
    if (ddx * ddx + ddy * ddy) > (reach * reach) then
        careLog(a, d, "INDO-AO-GALINHEIRO", nil, task.ex, task.ey)
        careDrive(a, d, task.ex, task.ey, false)
        if d.coopGoalTx ~= task.ex or d.coopGoalTy ~= task.ey then
            d.coopGoalTx, d.coopGoalTy = task.ex, task.ey
            CD.moveTo(a, false, 1.0, task.ex, task.ey, task.ez, "gado-porteiro", nil, "gado")
        else
            CD.forcePathfind(a)
        end
        return true
    end
    careLog(a, d, task.act == "call" and "CHAMOU-AS-AVES"
               or (task.act == "open" and "ABRIU-GALINHEIRO" or "FECHOU-GALINHEIRO"), nil, task.ex, task.ey)
    d.careHold, d.careWantTx, d.careWantTy = true, nil, nil
    CD.holdStill(a)
    CD.pz("srv.care.coop", coopWorkDoor, a, task, owner, zone, now)
    CD.coopTask[hid] = nil
    d.coopGoalTx, d.coopGoalTy = nil, nil
    return true
end

local function careHerd(a, d, now, owner, zone)
    if not d.lastCareCalmMin or (now - d.lastCareCalmMin) >= CD.careCalmThrottleMin() then
        d.lastCareCalmMin = now
        local t0herd = CD.perfIn()
        local delta = CD.effectiveCalmStrength(a)
        local cap = CD.effectiveCalmCap(a)
        if zone then
            local herd = zone:getAnimalsConnected()
            if herd then
                local n = herd:size()
                local maxHerd = CD.CARE_CALM_MAX_HERD
                if n > maxHerd then
                    n = maxHerd
                end
                local applied, stressSum, stressN, panicked = false, 0, 0, 0
                for i = 0, n - 1 do
                    local la = herd:get(i)
                    local live = false
                    if la then
                        live = la ~= nil and not CD.isDog(la) and not la:isWild() and not la:isDead()
                    end
                    if live then
                        if delta ~= 0 then
                            la:changeStress(delta)
                        end
                        if cap < 100 then
                            if la:getStress() > cap then
                                la:setDebugStress(cap)
                                panicked = panicked + 1
                            end
                        end
                        applied = true
                        stressSum = stressSum + la:getStress()
                        stressN = stressN + 1
                    end
                end
                local tendXp = false
                if applied and delta <= 0 then
                    if not d.lastCareTendXpMin or (now - d.lastCareTendXpMin) >= CD.CARE_XP_TEND_THROTTLE_MIN then
                        d.lastCareTendXpMin = now
                        CD.addSkillXP(a, "herding", CD.CARE_XP_PER_TEND)
                        tendXp = true
                    end
                end
                local panicXp = false
                if panicked > 0 then
                    if not d.lastCarePanicXpMin or (now - d.lastCarePanicXpMin) >= CD.CARE_XP_PANIC_THROTTLE_MIN then
                        d.lastCarePanicXpMin = now
                        CD.addSkillXP(a, "herding", CD.CARE_XP_PER_PANIC)
                        panicXp = true
                    end
                end
                if CD.CARE_DEBUG then
                    CD.log(string.format("[CD-CARE] rebanho n=%d estresseMedio=%.0f delta=%+.2f teto=%.0f pastoreio=%d panico=%d xp=%s",
                        stressN, stressN > 0 and (stressSum / stressN) or -1, delta, cap, CD.getSkillLevel(a, "herding"),
                        panicked, (tendXp and "cuidado" or "") .. (panicXp and "+panico" or "")))
                end
                if stressN > 0 and (stressSum / stressN) >= CD.CARE_STRESS_ALERT then
                    careAlert(owner, a, d, "stress", now)
                end
            end
        end
        CD.perfOut("srv.care.herd", t0herd)
    end
end

local function careDog(a, d, now)
    local hid = a:getOnlineID()
    if d.fenceHop then
        local st = d.fenceHop.startMs
        if st and (getTimestampMs() - st) > CD.FENCE_HOP_DURATION_MS + 1000 then
            CD.clearClimbVars(a)
        else
            return
        end
    end
    local lg = CD.landGlide[hid]
    if lg then
        if lg.startMs and (getTimestampMs() - lg.startMs) > 5000 then
            CD.landGlide[hid] = nil
        else
            return
        end
    end
    local owner = CD.getOwnerPlayer(a)

    if not d.skills then
        CD.restoreFromKennel(owner, a)
        CD.initSkills(a)
    end
    if CD.upkeepEnabled() then
        CD.pz("srv.care.upkeep", CD.updateUpkeep, a, owner, d)
    end
    if a:isDead() then return end

    if d.alertTier ~= nil or d.autoFeeding ~= nil or d.hunting ~= nil or d.inCombat then
        d.alertTier, d.autoFeeding, d.autoFeedKind = nil, nil, nil
        d.hunting, d.huntTargetId = nil, nil
        d.inCombat, d.retreating = nil, nil
        CD.transmit(a)
    end

    local ax, ay, az = d.careX, d.careY, d.careZ
    if not ax then
        ax, ay, az = a:getX(), a:getY(), a:getZ()
    end

    if careCombat(a, ax, ay, az, d, hid, now, owner) then return end

    d.careGoalTx, d.careGoalTy = nil, nil

    local zone = DesignationZoneAnimal.getZone(math.floor(ax), math.floor(ay), math.floor(az or a:getZ()))

    if not careCoop(a, d, now, zone, owner) then
        carePatrol(a, ax, ay, az, d, now, zone)
    end
    careHerd(a, d, now, owner, zone)
end

local function tickCareDogs(now)
    if isClient() then return end
    if not CD.careEnabled() then return end
    local cell = getCell()
    if not cell then return end

    CD.regEach(CD.regCompanions(), function(a)
        if not a:isDead() and CD.data(a).careMode == true then
            if CD.CARE_DEBUG and CD.CARE_DEBUG_TICK then
                local w = CD.careWatch
                if not w then
                    w = {}
                    CD.careWatch = w
                end
                local id = a:getOnlineID()
                if not w[id] then
                    w[id] = { a = a }
                else
                    w[id].a = a
                end
            end
            if a then
                careDog(a, CD.data(a), now)
            end
        end
    end, "iter.caresweep")
end

-- devolve true quando o cao saiu do modo de cuidado e o registro deve sair de CD.careWatch
local function careWatchStep(id, rec)
    local a = rec.a
    if not a or not a:isExistInTheWorld() then return true end
    local d = CD.data(a)
    if not d or not d.careMode then return true end
    local x, y = a:getX(), a:getY()
    if rec.x then
        local step = math.abs(x - rec.x) + math.abs(y - rec.y)
        if step > CD.CARE_JUMP_EPS then
            CD.log(string.format("[CD-CARE!] SALTO %.2f tile em 1 tick (%.2f,%.2f)->(%.2f,%.2f) | hop=%s glide=%s steer=%s lock=%s parado=%s seq=%d",
                step, rec.x, rec.y, x, y,
                d.fenceHop and "SIM" or "-", CD.landGlide[id] and "SIM" or "-",
                d.fenceSteer and "SIM" or "-",
                d.lockX and string.format("(%.2f,%.2f)", d.lockX, d.lockY) or "-",
                d.careHold and "SIM" or "-", d.careHijacks or 0))
            rec.still = 0
        elseif step < 0.01 then
            rec.still = (rec.still or 0) + 1
            if rec.still == CD.CARE_STUCK_TICKS and rec.gx then
                local sfw = tostring(a:shouldFollowWall())
                local bp = tostring(a:getVariableBoolean("bPathfind"))
                CD.log(string.format("[CD-CARE!] PARADO %d ticks em (%.2f,%.2f) com objetivo (%d,%d) | seguindoParede=%s bPathfind=%s hop=%s lock=%s",
                    rec.still, x, y, rec.gx, rec.gy, sfw, bp,
                    d.fenceHop and "SIM" or "-", d.lockX and "SIM" or "-"))
            end
        else
            rec.still = 0
        end
        if rec.gx then
            rec.ticks = (rec.ticks or 0) + 1
            rec.walked = (rec.walked or 0) + step
            local dg = math.abs(x - (rec.gx + 0.5)) + math.abs(y - (rec.gy + 0.5))
            rec.lastDg = dg
            if not rec.bestDg or dg < rec.bestDg then
                rec.bestDg = dg
            end
            if not rec.warned and rec.walked > CD.CARE_CONVERGE_MIN_WALK then
                local net = math.abs(x - (rec.ox or x)) + math.abs(y - (rec.oy or y))
                local eff = rec.walked > 0 and (net / rec.walked) or 0
                if dg > rec.bestDg + 2.0 then
                    rec.warned = true
                    CD.log(string.format("[CD-CARE!] AFASTANDO-SE do objetivo (%d,%d): dist agora %.1f, melhor foi %.1f | andou %.1f liquido %.1f efic %.2f",
                        rec.gx, rec.gy, dg, rec.bestDg, rec.walked, net, eff))
                elseif eff < CD.CARE_CONVERGE_MIN_EFF then
                    rec.warned = true
                    local sfw = tostring(a:shouldFollowWall())
                    CD.log(string.format("[CD-CARE!] ORBITANDO rumo a (%d,%d): andou %.1f tiles mas liquido so %.1f (efic %.2f) | dist %.1f melhor %.1f seguindoParede=%s",
                        rec.gx, rec.gy, rec.walked, net, eff, dg, rec.bestDg, sfw))
                end
            end
        end
    end
    rec.x, rec.y = x, y
    return false
end

local function tickCareWatch()
    if not CD.CARE_DEBUG or not CD.CARE_DEBUG_TICK then return end
    local w = CD.careWatch
    if not w then return end
    for id, rec in pairs(w) do
        if careWatchStep(id, rec) then
            w[id] = nil
        end
    end
end
CD.tickCareDogs, CD.tickCareWatch = tickCareDogs, tickCareWatch
