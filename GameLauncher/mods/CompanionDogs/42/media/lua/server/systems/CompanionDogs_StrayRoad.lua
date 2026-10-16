CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local PRUNE_MS = 60000

local CARDINAL = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAGONAL = { { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }

local roadMemo, roadMemoN = {}, 0
local sweepMs, zonesN, zonesLast = nil, -1, nil
local recs = {}
local pruneMs = 0

local function roadLog(a, fmt, ...)
    if CD.DEBUG_STRAYROAD then
        CD.log(string.format("[CD-ROAD] cao=%s " .. fmt, tostring(CD.animKey(a)), ...))
    end
end

-- Rua e a zona Nav do mapa. O getZoneType() do tile so devolve a zona preferida, e ali a TownZone pode ganhar da Nav.
local function isRoad(x, y)
    local k = x .. "," .. y
    local v = roadMemo[k]
    if v ~= nil then return v end
    CD.perfCount("road.zoneq")
    v = false
    local zones = getWorld():getMetaGrid():getZonesAt(x, y, 0)
    for i = 0, zones:size() - 1 do
        if zones:get(i):getType() == "Nav" then
            v = true
            break
        end
    end
    if roadMemoN >= CD.STRAY_ROAD_MEMO_MAX then
        roadMemo, roadMemoN = {}, 0
    end
    roadMemo[k] = v
    roadMemoN = roadMemoN + 1
    return v
end

-- A lista de zonas muda em jogo (pesca, rebrota de grama, mapa gerado): o cache so vale enquanto ela nao mudar.
local function checkZones(now)
    if sweepMs and (now - sweepMs) < 1 then return end
    sweepMs = now
    local zones = getWorld():getMetaGrid():getZones()
    local n = zones:size()
    local last = n > 0 and zones:get(n - 1) or nil
    if n ~= zonesN or last ~= zonesLast then
        zonesN, zonesLast = n, last
        roadMemo, roadMemoN = {}, 0
    end
end

local function freeTile(cell, x, y)
    local sq = cell:getGridSquare(x, y, 0)
    if sq and sq:isFree(true) and not sq:isWaterSquare() then return sq end
    return nil
end

-- Da borda o cao segue ate STRAY_ROAD_MARGIN tiles para fora, para nao parar no meio-fio.
local function exitAlong(cell, x0, y0, dir, d, rec)
    local dx, dy = dir[1], dir[2]
    if rec.badDx and (dx * rec.badDx + dy * rec.badDy) > 0 then return nil end
    local ex, ey = x0 + dx * d, y0 + dy * d
    if isRoad(ex, ey) then return nil end
    local best
    for m = 0, CD.STRAY_ROAD_MARGIN do
        local mx, my = ex + dx * m, ey + dy * m
        if m > 0 and isRoad(mx, my) then break end
        local sq = freeTile(cell, mx, my)
        if not sq then break end
        best = sq
    end
    return best
end

local function exitSearch(cell, x0, y0, rec)
    local s = ZombRand(4)
    for d = 1, CD.STRAY_ROAD_SEARCH do
        for k = 0, 3 do
            local sq = exitAlong(cell, x0, y0, CARDINAL[(s + k) % 4 + 1], d, rec)
            if sq then return sq end
        end
        for k = 0, 3 do
            local sq = exitAlong(cell, x0, y0, DIAGONAL[(s + k) % 4 + 1], d, rec)
            if sq then return sq end
        end
    end
    return nil
end

-- Depois de uma falha o lado dela fica por ultimo: cerca colada na estrada deixa o lado inteiro sem caminho.
local function exitSquare(x0, y0, rec)
    local cell = getCell()
    local sq = exitSearch(cell, x0, y0, rec)
    if not sq and rec.badDx then
        rec.badDx, rec.badDy = nil, nil
        sq = exitSearch(cell, x0, y0, rec)
    end
    return sq
end

-- Jogador a pe do lado esta dando comida, domando ou fazendo carinho; dentro do carro nao conta.
local function heldInPlace(a, ax, ay, players, px, py)
    local data = a:getData()
    if data:getAttachedPlayer() or data:getAttachedTree() or a:getDZone() or a:isOnFire() then return true end
    local r2 = CD.STRAY_ROAD_PLAYER_DIST * CD.STRAY_ROAD_PLAYER_DIST
    for i = 1, #players do
        local dx, dy = px[i] - ax, py[i] - ay
        if dx * dx + dy * dy <= r2 and not players[i]:getVehicle() then return true end
    end
    return false
end

local function walking(a, rec, now)
    local dx, dy = a:getX() - rec.tx, a:getY() - rec.ty
    local gap = math.sqrt(dx * dx + dy * dy)
    if gap <= CD.STRAY_ROAD_ARRIVE_DIST then
        roadLog(a, "saiu da rua em (%.1f,%.1f)", rec.tx, rec.ty)
        recs[a] = nil
        return false
    end
    if rec.best == nil or gap < (rec.best - CD.STRAY_ROAD_PROGRESS_EPS) then
        rec.best, rec.progMs = gap, now
    end
    if (now - rec.progMs) >= CD.STRAY_ROAD_STALL_MS or now >= rec.untilMs then
        CD.perfCount("road.fail")
        rec.untilMs = nil
        rec.badDx, rec.badDy = rec.tx - rec.ox, rec.ty - rec.oy
        rec.nextMs = now + CD.STRAY_ROAD_RETRY_MS
        roadLog(a, "nao chegou na saida (%d,%d), faltando %.1f", math.floor(rec.tx), math.floor(rec.ty), gap)
        return false
    end
    -- O wanderIdle roda nas frestas em que o cao esta parado (a espera do A*, por exemplo) e cancela o pedido.
    if a:getStateEventDelayTimer() < CD.STRAY_ROAD_HOLD * 0.5 then
        a:setStateEventDelayTimer(CD.STRAY_ROAD_HOLD)
    end
    return true
end

local function prune(now)
    pruneMs = now
    for a, rec in pairs(recs) do
        if (now - rec.seenMs) > PRUNE_MS then
            recs[a] = nil
        end
    end
end

---Walks a stray off the road when it stops on one, or when it walks along it to another road tile.
---@param a IsoAnimal
---@param now number getTimestampMs() of this sweep
---@param players IsoPlayer[] players read at the start of this sweep
---@param px number[] their X, same index
---@param py number[] their Y, same index
local function strayRoadTick(a, now, players, px, py)
    checkZones(now)
    if (now - pruneMs) > PRUNE_MS then
        prune(now)
    end
    local rec = recs[a]
    if rec then
        rec.seenMs = now
        if rec.untilMs and walking(a, rec, now) then return end
        if now < rec.nextMs then return end
    end
    local ax, ay = a:getX(), a:getY()
    local x, y = math.floor(ax), math.floor(ay)
    if not isRoad(x, y) then
        recs[a] = nil
        return
    end
    if math.floor(a:getZ()) ~= 0 then return end
    local moving = a:isAnimalMoving()
    if moving then
        if a:getVariableBoolean("animalRunning") then return end
        local pfb = a:getPathFindBehavior2()
        if not pfb:isGoalLocation() then return end
        if not isRoad(math.floor(pfb:getTargetX()), math.floor(pfb:getTargetY())) then return end
    end
    if heldInPlace(a, ax, ay, players, px, py) then return end
    if not rec then
        rec = { nextMs = 0, seenMs = now }
        recs[a] = rec
    end
    local sq = exitSquare(x, y, rec)
    if not sq then
        CD.perfCount("road.noexit")
        rec.nextMs = now + CD.STRAY_ROAD_NOEXIT_MS
        roadLog(a, "sem saida em %d tiles de (%d,%d)", CD.STRAY_ROAD_SEARCH, x, y)
        return
    end
    local tx, ty = sq:getX(), sq:getY()
    a:setVariable("animalRunning", false)
    a:pathToLocation(tx, ty, 0)
    a:setStateEventDelayTimer(CD.STRAY_ROAD_HOLD)
    rec.tx, rec.ty = tx + 0.5, ty + 0.5
    rec.ox, rec.oy = x + 0.5, y + 0.5
    rec.untilMs = now + CD.STRAY_ROAD_TIMEOUT_MS
    rec.best, rec.progMs = nil, now
    CD.perfCount("road.leave")
    roadLog(a, "%s na rua em (%d,%d) -> saida (%d,%d)", moving and "andando" or "parado", x, y, tx, ty)
end
CD.strayRoadTick = strayRoadTick
