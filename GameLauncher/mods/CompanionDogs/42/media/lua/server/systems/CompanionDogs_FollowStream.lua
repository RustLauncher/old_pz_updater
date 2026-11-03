CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- O canal nativo de animal NAO pode ser desligado (todo animal e marcado sujo em todo tick do
-- servidor), entao isto e sempre um segundo canal por cima dele. Um quadro por JOGADOR, nao por cao.

local followStreamActive = {}

local viewerBuf = {}
local viewerX, viewerY, viewerId = {}, {}, {}
local viewerN = 0
local viewerMs = nil

-- Posicao lida UMA vez por passada: o filtro roda caes x jogadores, e ler dentro do laco custa
-- chamada Java por par.
local function refreshViewers(now)
    if viewerMs == now then return viewerN end
    viewerMs = now
    for i = 1, viewerN do viewerBuf[i] = nil end
    viewerN = 0
    local list = getOnlinePlayers()
    local np = list:size()
    for i = 0, np - 1 do
        local p = list:get(i)
        viewerN = viewerN + 1
        viewerBuf[viewerN] = p
        viewerX[viewerN] = p:getX()
        viewerY[viewerN] = p:getY()
        viewerId[viewerN] = p:getOnlineID()
    end
    CD.perfCount("iter.followviewer", np)
    return viewerN
end

local STOP_KEY = { radius = "followstop.radius", leftfollow = "followstop.leftfollow",
                   noviewer = "followstop.noviewer", landing = "followstop.landing" }
local function stopFollowStream(id, animal, why)
    followStreamActive[id] = nil
    CD.perfCount("followstop")
    CD.perfCount(STOP_KEY[why] or "followstop.other")
    if animal then
        local d = CD.data(animal)
        if d then
            d._followStreaming = nil
            d._followStreamMs = nil
            d._streamLastX, d._streamLastY = nil, nil
        end
    end
    local args = { id = id }
    if animal and animal:isExistInTheWorld() then
        args.x, args.y, args.z = animal:getX(), animal:getY(), animal:getZ()
    end
    sendServerCommand(CD.MODULE, "followstop", args)
end

local function encodeDog(animal, d, now)
    local fx, fy = 0, 1
    local f = animal:getForwardDirection()
    if f then
        fx, fy = f:getX(), f:getY()
    end
    local px, py = animal:getX(), animal:getY()
    local moved = d._streamLastX == nil
        or (math.abs(px - d._streamLastX) + math.abs(py - d._streamLastY)) > 0.005
    if not moved then
        CD.perfCount("stream.idle")
    end
    d._streamLastX, d._streamLastY = px, py
    d._followSeq = (d._followSeq or 0) + 1
    d._followStreaming = true
    d._followStreamMs = now
    local flags = 0
    if animal:getVariableBoolean("animalRunning") then
        flags = flags + 1
    end
    if moved then
        flags = flags + 2
    end
    return string.format("%d,%d,%.3f,%.3f,%.2f,%.3f,%.3f,%.3f,%.3f,%d",
        animal:getOnlineID(), d._followSeq, px, py, animal:getZ(), fx, fy,
        animal:getVariableFloat("cdRunScale", CD.PATH_RUN_SCALE),
        animal:getVariableFloat("cdWalkScale", CD.PATH_WALK_SCALE),
        flags)
end

local candBuf, candN = {}, 0
local hitBuf = {}

local function addCandidate(animal, now)
    if not animal or not animal:isExistInTheWorld() then return end
    local d = CD.data(animal)
    if not d or d.fenceHop then return end
    if d._followStreamMs and (now - d._followStreamMs) < CD.FOLLOW_STREAM_MS then return end
    candN = candN + 1
    candBuf[candN] = animal
end

local function flushBatch(now)
    if candN == 0 then return end
    local nv = refreshViewers(now)
    if nv == 0 then
        for i = 1, candN do
            local a = candBuf[i]
            local id = a:getOnlineID()
            if followStreamActive[id] then
                stopFollowStream(id, a, "noviewer")
            end
        end
        return
    end
    local range = CD.FOLLOW_STREAM_RANGE
    local maxDogs = CD.FOLLOW_STREAM_MAX_DOGS
    local enc, seen = {}, 0
    for i = 1, candN do
        local a = candBuf[i]
        local d = CD.data(a)
        local ax, ay = a:getX(), a:getY()
        -- O dono que conduz fica de fora: ele e a fonte. Os outros jogadores continuam recebendo.
        local holder = CD.netAuthHolder(a:getOnlineID())
        CD.perfCount("stream.pairs", nv)
        local np = 0
        for v = 1, nv do
            if viewerId[v] ~= holder
               and (math.abs(viewerX[v] - ax) + math.abs(viewerY[v] - ay)) <= range then
                np = np + 1
                hitBuf[np] = viewerBuf[v]
            end
        end
        if np == 0 then
            local id = a:getOnlineID()
            if followStreamActive[id] then
                stopFollowStream(id, a, "radius")
            end
            d._followStreamMs = now
        else
            local line = encodeDog(a, d, now)
            local id = a:getOnlineID()
            followStreamActive[id] = a
            seen = seen + 1
            CD.perfCount("stream.dogs")
            if CD._perfLv > 0 then
                CD._perfStreamDogs[id] = true
            end
            for k = 1, np do
                local p = hitBuf[k]
                local pn = p:getOnlineID()
                local bucket = enc[pn]
                if not bucket then
                    bucket = { p = p, n = 0 }
                    enc[pn] = bucket
                end
                if bucket.n < maxDogs then
                    bucket.n = bucket.n + 1
                    bucket[bucket.n] = line
                end
            end
        end
    end
    if seen == 0 then return end
    local sent = 0
    for _, bucket in pairs(enc) do
        if bucket.n > 0 then
            local blob = table.concat(bucket, ";")
            sendServerCommand(bucket.p, CD.MODULE, "followb", { s = blob })
            sent = sent + 1
            CD.perfCount("stream.bytes", string.len(blob))
        end
    end
    CD.perfCount("net.followbatch", sent)
end

---Server only: streams the position of dogs that just landed a fence hop to the players near them, for FENCE_LAND_STREAM_MS.
function CD.tickLandStream()
    local landStreaming = CD.landStreaming
    if not isServer() then
        for k in pairs(landStreaming) do landStreaming[k] = nil end
        return
    end
    local now = getTimestampMs()
    candN = 0
    for id, rec in pairs(landStreaming) do
        local a = rec.animal
        if a and a:isExistInTheWorld() and now < rec.untilMs then
            addCandidate(a, now)
        else
            landStreaming[id] = nil
            stopFollowStream(id, rec.animal, "landing")
        end
    end
    flushBatch(now)
    candN = 0
end

---Server only: sends each nearby player one batch with a position line per following or fighting dog, and ends the stream of dogs that left those states.
function CD.tickFollowStream()
    if not CD.FOLLOW_STREAM or not isServer() then return end
    local now = getTimestampMs()
    local followMaintainDogs, combatMaintainDogs = CD.followMaintainDogs, CD.combatMaintainDogs
    candN = 0
    for _, animal in pairs(followMaintainDogs) do addCandidate(animal, now) end
    for id, animal in pairs(combatMaintainDogs) do
        if not followMaintainDogs[id] then
            addCandidate(animal, now)
        end
    end
    flushBatch(now)
    candN = 0
    for id, animal in pairs(followStreamActive) do
        if not (followMaintainDogs[id] or combatMaintainDogs[id]) then
            stopFollowStream(id, animal, "leftfollow")
        end
    end
end

-- Reusada pelo sync de fundo pra nao varrer os jogadores duas vezes.
---@param now number timestamp in ms; the players are read again only when it changes
---@return IsoPlayer[] players
---@return integer count entries valid in the four arrays, which are reused buffers
---@return number[] x
---@return number[] y
---@return integer[] onlineId
function CD.streamViewers(now)
    local n = refreshViewers(now)
    return viewerBuf, n, viewerX, viewerY, viewerId
end
