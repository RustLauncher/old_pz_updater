CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs
CD.Server = CD.Server or {}

local lastOwnerTile = {}

local pendingTeleportBring = {}
local rvExitBring = {}

local onlinePresent = {}
-- Roda no EveryOneMinute: o dado e de minuto, e a divida so importa quando o cao fica no mundo
-- com o dono offline. Com a opcao de sumir ligada o cao e guardado e a divida zerada na hora.
local function reconcileOwnerPresence()
    CD.perfCount("evt.minute")
    if CD.despawnOnOwnerOffline() then
        CD.perfCount("presence.skip")
        return
    end
    CD.perfCount("presence.run")
    local now = CD.worldMinutes()
    local current = {}
    CD.eachOnlinePlayer(function(player)
        local id = player:getOnlineID()
        current[id] = true
        local pd = CD.playerData(player)
        if not onlinePresent[id] and pd.token ~= nil and pd.lastSeenMin then
            local gap = now - pd.lastSeenMin
            if gap > 0 then
                CD.perfCount("presence.debt", gap)
                pd.offlineDebtMin = (pd.offlineDebtMin or 0) + gap
            end
        end
        pd.lastSeenMin = now
    end)
    onlinePresent = current
end

local function attemptTeleportBring(player, pid, pd)
    local dog = CD.getCompanionAnimal(player)
    if dog and CD.isOwnedBy(dog, player) and CD.data(dog).companionToken == pd.token then
        local u = CD.data(dog).uid
        local hw = (u and type(pd.uidGen) == "table") and pd.uidGen[u] or nil
        if u and hw and (CD.data(dog).gen or 0) < hw then
        else
            if CD.getState(dog) == CD.STATE_FOLLOW then
                if not CD.teleportRecover(dog, player) then return false end
                local dd = CD.data(dog)
                dd.running = nil
                dd.climbTries = nil
                CD.transmit(dog)
            end
            CD.bumpCanonical(player, dog)
            CD.reapClonesCellWide()
            return true
        end
    end
    local rec = pd.stash
    if rec then
        if CD.isMounted(player) then return true end
        local stok = rec.data and rec.data.companionToken
        local sstate = (rec.data and rec.data.state) or CD.STATE_FOLLOW
        if CD.recordStillBonded(pd, stok) and sstate == CD.STATE_FOLLOW
           and not CD.carryingDogWithToken(player, stok) and not CD.regByToken(player, stok) then
            local fresh = CD.respawnCompanion(nil, player, rec)
            if not fresh then return false end
            local fd = CD.data(fresh)
            fd.running = nil
            fd.climbTries = nil
            CD.ensureUidData(fd)
            CD.clearStashRecord(player)
            CD.bumpCanonical(player, fresh)
            return true
        end
        return true
    end

    local snap = CD.activeDogSnapshot[pid]
    local snapState = snap and snap.data and (snap.data.state or CD.STATE_FOLLOW)
    if not snap or snap.data.companionToken ~= pd.token or snapState ~= CD.STATE_FOLLOW then return true end
    if CD.isMounted(player) then return true end
    local fresh = CD.respawnCompanion(nil, player, snap)
    if not fresh then return false end
    local fd = CD.data(fresh)
    fd.running = nil
    fd.climbTries = nil
    CD.ensureUidData(fd)
    CD.bumpCanonical(player, fresh)
    CD.reapClonesCellWide()
    return true
end

local function bringActiveOnTeleport(player)
    local pid = player:getOnlineID()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local prev = lastOwnerTile[pid]
    lastOwnerTile[pid] = { x = px, y = py }

    local minx, miny = CD.RV_INTERIOR_MIN_X, CD.RV_INTERIOR_MIN_Y
    if prev and prev.x > minx and prev.y > miny and not (px > minx and py > miny) then
        rvExitBring[pid] = CD.TELEPORT_BRING_TRIES
    end
    if prev and not rvExitBring[pid] then
        local dx, dy = px - prev.x, py - prev.y
        local jump = CD.TELEPORT_JUMP_MIN
        if dx * dx + dy * dy > jump * jump then
            pendingTeleportBring[pid] = CD.TELEPORT_BRING_TRIES
        end
    end
    -- Sem salto pendente nao ha o que fazer. A sonda de inventario abaixo e o custo desta funcao,
    -- e num servidor cheio ela rodava pra cada dono a cada tick.
    if not rvExitBring[pid] and not pendingTeleportBring[pid] then return end
    local pd = CD.playerData(player)

    local activeCarried = (pd.carried and pd.carried.data and pd.carried.data.companionToken == pd.token)
        or CD.carryingDogWithToken(player, pd.token)
    if activeCarried then
        rvExitBring[pid] = nil
        pendingTeleportBring[pid] = nil
        return
    end

    if rvExitBring[pid] then
        if pd.token == nil or attemptTeleportBring(player, pid, pd) then
            rvExitBring[pid] = nil
        else
            rvExitBring[pid] = rvExitBring[pid] - 1
            if rvExitBring[pid] <= 0 then
                rvExitBring[pid] = nil
            end
        end
        return
    end

    if CD.isMounted(player) then
        pendingTeleportBring[pid] = nil
        return
    end
    if player:getVehicle() ~= nil then
        pendingTeleportBring[pid] = nil
        return
    end
    if pd.stash ~= nil then
        pendingTeleportBring[pid] = nil
        return
    end
    local tries = pendingTeleportBring[pid]
    if not tries then return end
    if pd.token == nil then
        pendingTeleportBring[pid] = nil
        return
    end
    if attemptTeleportBring(player, pid, pd) then
        pendingTeleportBring[pid] = nil
    elseif tries <= 1 then
        pendingTeleportBring[pid] = nil
    else
        pendingTeleportBring[pid] = tries - 1
    end
end

---The player left an RV interior: the following dog is stashed and brought back beside the player on the next ticks.
---@param player IsoPlayer
CD.Server.rvexit = function(player)
    if not player then return end
    local pd = CD.playerData(player)
    local sawParkedLive = false
    if pd.token and not pd.stash then
        local dog = CD.getCompanionAnimal(player)
        if dog and CD.isOwnedBy(dog, player) and CD.data(dog).companionToken == pd.token then
            if CD.getState(dog) == CD.STATE_FOLLOW then
                CD.writeStashRecord(dog, player)
                if pd.stash then
                    CD.data(dog).stashed = true
                    dog:stopAllMovementNow()
                    CD.despawn(dog)
                end
            else
                sawParkedLive = true
            end
        end
    end
    if pd.token and not pd.stash and not sawParkedLive then
        local snap = CD.activeDogSnapshot[player:getOnlineID()]
        local sstate = snap and snap.data and (snap.data.state or CD.STATE_FOLLOW)
        if snap and snap.data.companionToken == pd.token and sstate == CD.STATE_FOLLOW then
            local sd = CD.cdDeepCopy(snap.data)
            CD.ensureUidData(sd)
            pd.stash = { type = snap.type, female = snap.female, age = snap.age, hp = snap.hp,
                         hunger = snap.hunger, thirst = snap.thirst, lastNeedMin = CD.worldMinutes(), data = sd }
            player:transmitModData()
        end
    end
    rvExitBring[player:getOnlineID()] = CD.TELEPORT_BRING_TRIES
end
---The player entered an RV interior: the next ticks bring the following dog along.
---@param player IsoPlayer
CD.Server.rventer = function(player)
    if not player then return end
    pendingTeleportBring[player:getOnlineID()] = CD.TELEPORT_BRING_TRIES
end

local function reapPhantomCompanions(player)
    local pd = CD.playerData(player)
    if type(pd.companions) ~= "table" then return end
    local osq = player:getCurrentSquare()
    if not osq then return end
    local cell = getCell()
    if not cell then return end
    pd.tokenAnchor = pd.tokenAnchor or {}
    local pid = CD.ownerKey(player)
    CD.phantomLostSince[pid] = CD.phantomLostSince[pid] or {}
    local lost = CD.phantomLostSince[pid]
    if type(pd.dogPositions) == "table" then
        for t, p in pairs(pd.dogPositions) do
            if pd.companions[t] and not pd.tokenAnchor[t] and p and p.x and p.y then
                pd.tokenAnchor[t] = { x = math.floor(p.x), y = math.floor(p.y), z = math.floor(p.z or 0) }
            end
        end
    end
    local now = CD.worldMinutes()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local R = CD.TELEPORT_DIST + 4
    local grace = CD.PHANTOM_LOST_GRACE_MIN
    local changed = false
    local tokens = {}
    for t in pairs(pd.companions) do tokens[#tokens + 1] = t end
    for _, t in ipairs(tokens) do
        local alive = CD.regByToken(player, t) ~= nil
        if not alive then
            local stok = pd.stash and pd.stash.data and pd.stash.data.companionToken
            local ctok = pd.carried and pd.carried.data and pd.carried.data.companionToken
            if t == stok or t == ctok then
                alive = true
            elseif CD.offlineStashHas(player, t) then
                alive = true
            elseif CD.tokenTrailered(player, t) then
                alive = true
            end
        end
        if alive then
            lost[t] = nil
        else
            local anc = pd.tokenAnchor[t]
            local ancLoaded = false
            if anc then
                ancLoaded = cell:getGridSquare(anc.x, anc.y, anc.z) ~= nil
            end
            if anc and ancLoaded and math.abs(px - anc.x) <= R and math.abs(py - anc.y) <= R then
                lost[t] = lost[t] or now
                if (now - lost[t]) >= grace then
                    local nm = (type(pd.dogPositions) == "table" and pd.dogPositions[t] and pd.dogPositions[t].name)
                        or (t == pd.token and pd.name) or nil
                    local re = CD.adoptByAnimalId and pd.kennel and pd.kennel[t]
                        and CD.adoptByAnimalId(player, t, pd.kennel[t], CD.TELEPORT_DIST)
                    if re then
                        changed = true
                    else
                        local marked = CD.markCompanionLost(player, t)
                        if marked ~= nil then
                            if marked then
                                CD.notifyOwner(player, "lost", { name = nm, breed = pd.kennel[t] and pd.kennel[t].breed })
                                changed = true
                            end
                        else
                            CD.clearCompanionSlot(player, t, nm, nil, nil)
                            pd.tokenAnchor[t] = nil
                            if type(pd.dogPositions) == "table" then
                                pd.dogPositions[t] = nil
                            end
                            changed = true
                        end
                    end
                    lost[t] = nil
                end
            else
                lost[t] = nil
            end
        end
    end
    if changed then
        player:transmitModData()
    end
end

---Despawns extra copies of a dog sharing one uid, keeping the newest generation, and a lone copy older than its owner's canonical generation.
CD.reapClonesCellWide = function()
    if isClient() then return end
    local reaped = false
    local function reapDup(owner, a, keeperTok)
        if owner then
            local pd = CD.playerData(owner)
            local vt = CD.data(a).companionToken
            if CD.cloneSlotShouldClear(pd, vt, keeperTok) and pd.companions ~= nil then
                pd.companions[vt] = nil
            end
        end
        CD.reapDogState(a:getOnlineID())
        CD.despawn(a)
        reaped = true
    end
    local byUid = {}
    CD.regEach(CD.regCompanions(), function(a)
        if not a:isDead() then
            local u = CD.data(a).uid
            if u ~= nil then
                local g = byUid[u]
                if not g then
                    g = {}
                    byUid[u] = g
                end
                g[#g + 1] = a
            end
        end
    end)
    for u, dogs in pairs(byUid) do
        local owner = CD.getOwnerPlayer(dogs[1])
        local ptoken = owner and CD.playerData(owner).token or nil
        if #dogs > 1 then
            local keeper = dogs[1]
            for k = 2, #dogs do
                local a = dogs[k]
                local ag = CD.data(a).gen or 0
                local kg = CD.data(keeper).gen or 0
                if ag > kg or (ag == kg and ptoken ~= nil and CD.data(a).companionToken == ptoken and CD.data(keeper).companionToken ~= ptoken) then
                    keeper = a
                end
            end
            for k = 1, #dogs do
                if dogs[k] ~= keeper then
                    reapDup(owner, dogs[k], CD.data(keeper).companionToken)
                end
            end
        elseif owner then
            local pd = CD.playerData(owner)
            local canonGen = type(pd.uidGen) == "table" and pd.uidGen[u] or nil
            if canonGen ~= nil and (CD.data(dogs[1]).gen or 0) < canonGen then
                reapDup(owner, dogs[1], nil)
            end
        end
    end
    if reaped then
        CD.regInvalidate()
    end
end

---At most once per game minute: drops kennel records and companion slots held under a player who does not own that dog.
CD.repairOwnership = function()
    if isClient() then return end
    if not (CD.kennelGlobalAll and CD.kennelGlobalDrop) then return end
    local nowMin = CD.worldMinutes()
    if CD._repairMin ~= nil and (nowMin - CD._repairMin) < 1 then return end
    CD._repairMin = nowMin
    local s = CD.kennelGlobalAll()
    if type(s) ~= "table" then return end

    local truth = {}
    CD.regEach(CD.regCompanions(), function(a)
        local d = CD.data(a)
        if d.ownerId ~= nil then
            d.ownerId = nil
            CD.transmit(a)
        end
        if isServer() and d.ownerKey ~= nil and d.ownerKey ~= "" and d.ownerName ~= nil and d.ownerName ~= ""
           and d.ownerKey ~= d.ownerName then
            d.ownerKey = d.ownerName
            CD.transmit(a)
        end
        if d.uid ~= nil and d.ownerKey ~= nil and d.ownerKey ~= "" then
            truth[d.uid] = d.ownerKey
        end
    end)
    local byUid = {}
    for key, recs in pairs(s) do
        if type(recs) == "table" then
            for tok, snap in pairs(recs) do
                if type(snap) == "table" and snap.uid ~= nil then
                    local g = byUid[snap.uid]
                    if not g then
                        g = {}
                        byUid[snap.uid] = g
                    end
                    g[#g + 1] = { key = key, tok = tok }
                    if truth[snap.uid] == nil and snap.ownerKey ~= nil and snap.ownerKey == key then
                        truth[snap.uid] = key
                    end
                end
            end
        end
    end
    local stolen = {}
    for uid, entries in pairs(byUid) do
        local owner = truth[uid]
        if owner ~= nil then
            for i = 1, #entries do
                local e = entries[i]
                if e.key ~= owner then
                    CD.kennelGlobalDrop(e.key, e.tok)
                    stolen[e.key] = stolen[e.key] or {}
                    stolen[e.key][e.tok] = uid
                end
            end
        end
    end
    CD.eachOnlinePlayer(function(player)
        local key = CD.ownerKey(player)
        local pd = CD.playerData(player)
        local drops = stolen[key]
        if type(pd.kennel) == "table" then
            for tok, snap in pairs(pd.kennel) do
                if type(snap) == "table" then
                    local bad = (snap.ownerKey ~= nil and snap.ownerKey ~= "" and snap.ownerKey ~= key)
                        or (snap.uid ~= nil and truth[snap.uid] ~= nil and truth[snap.uid] ~= key)
                    if bad then
                        drops = drops or {}
                        drops[tok] = snap.uid
                    end
                end
            end
        end
        if not drops then return end
        local changed = false
        for tok, _ in pairs(drops) do
            if type(pd.kennel) == "table" then
                pd.kennel[tok] = nil
            end
            if type(pd.companions) == "table" then
                pd.companions[tok] = nil
            end
            if type(pd.tokenAnchor) == "table" then
                pd.tokenAnchor[tok] = nil
            end
            if type(pd.dogPositions) == "table" then
                pd.dogPositions[tok] = nil
            end
            if pd.token == tok then
                pd.token = nil
                pd.name = nil
            end
            changed = true
        end
        if changed and player then
            player:transmitModData()
        end
    end)
end
-- Tela dividida: a chave do jogador 2 e sid#spKey, e o spKey morria junto com o personagem. Quem ja
-- perdeu o vinculo tem os caes vivos na cell sem dono que responda por eles, e o bucket antigo
-- parado no store global. O slot de CD.splitSlotBind evita a proxima perda; isto recupera a que ja
-- aconteceu, movendo o bucket orfao para a identidade ATUAL do jogador.
local function splitOwnerPrefix()
    local sid = getCurrentUserSteamID()
    if sid == nil or sid == "" then
        sid = CD.SP_OWNER_MARKER
    end
    return sid .. "#"
end

local function splitSuffix(key, prefix)
    if type(key) ~= "string" then return nil end
    local n = #prefix
    if #key <= n or string.sub(key, 1, n) ~= prefix then return nil end
    return string.sub(key, n + 1, #key)
end

local function ownsAnyDog(player)
    local pd = CD.playerData(player)
    if pd.token ~= nil then return true end
    if type(pd.companions) == "table" then
        for _ in pairs(pd.companions) do return true end
    end
    if type(pd.kennel) == "table" then
        for _ in pairs(pd.kennel) do return true end
    end
    return false
end

-- Mesmo criterio do allocCompanionToken: cao tamado depois da morte nao pode colidir com os que
-- voltam do bucket orfao.
local function nextSplitToken(pd)
    local m = pd.seq or 0
    if type(pd.companions) == "table" then
        for k in pairs(pd.companions) do if k > m then m = k end end
    end
    if type(pd.kennel) == "table" then
        for k in pairs(pd.kennel) do if k > m then m = k end end
    end
    pd.seq = m + 1
    return pd.seq
end

local function adoptOrphanBucket(player, orphanKey)
    local store = CD.kennelGlobalAll()
    local bucket = type(store) == "table" and store[orphanKey] or nil
    if type(bucket) ~= "table" then return 0 end
    local toks = {}
    for tok in pairs(bucket) do toks[#toks + 1] = tok end
    if #toks == 0 then return 0 end

    -- Cao vivo primeiro: o adoptOrphan ja reescreve o dono, tira token novo e grava o snapshot no
    -- bucket certo. O token velho marca qual entrada do bucket orfao ele acabou de substituir.
    local taken = {}
    CD.regEach(CD.regCompanions(), function(a)
        local d = CD.data(a)
        if d.ownerKey == orphanKey then
            local old = d.companionToken
            CD.adoptOrphan(a, player)
            if old ~= nil then
                taken[old] = true
            end
        end
    end)

    local pd = CD.playerData(player)
    pd.kennel = pd.kennel or {}
    pd.companions = pd.companions or {}
    local myKey, myName = CD.ownerKey(player), player:getUsername()
    for i = 1, #toks do
        local snap = bucket[toks[i]]
        if type(snap) == "table" and not taken[toks[i]] then
            local fresh = CD.deepCopy(snap)
            fresh.ownerKey = myKey
            fresh.ownerName = myName
            local nt = nextSplitToken(pd)
            pd.kennel[nt] = fresh
            pd.companions[nt] = true
            CD.kennelGlobalPut(myKey, nt, fresh)
        end
    end
    for i = 1, #toks do
        CD.kennelGlobalDrop(orphanKey, toks[i])
    end
    player:transmitModData()
    return #toks
end

---Split screen only, at most once per game minute: a player whose split key changed takes over the orphaned kennel bucket of the old key.
CD.repairSplitIdentity = function()
    if isServer() or isClient() then return end
    if (getNumActivePlayers() or 1) <= 1 then return end
    if not (CD.kennelGlobalAll and CD.kennelGlobalPut and CD.kennelGlobalDrop) then return end
    local nowMin = CD.worldMinutes()
    if CD._splitRepairMin ~= nil and (nowMin - CD._splitRepairMin) < 1 then return end
    CD._splitRepairMin = nowMin

    local prefix = splitOwnerPrefix()
    local claimed, players = {}, {}
    CD.eachLocalPlayer(function(p)
        local key = CD.ownerKey(p)
        if key == nil or key == "" then return end
        claimed[key] = true
        players[#players + 1] = p
        local suffix = splitSuffix(key, prefix)
        if suffix then
            CD.splitSlotBind(p:getPlayerNum(), suffix)
        end
    end)

    local store = CD.kennelGlobalAll()
    if type(store) ~= "table" then return end
    local orphans = {}
    for key, bucket in pairs(store) do
        if type(bucket) == "table" and not claimed[key] and splitSuffix(key, prefix) then
            local name, n = nil, 0
            for _, snap in pairs(bucket) do
                if type(snap) == "table" then
                    n = n + 1
                    if name == nil and type(snap.ownerName) == "string" and snap.ownerName ~= "" then
                        name = snap.ownerName
                    end
                end
            end
            if n > 0 then
                orphans[#orphans + 1] = { key = key, name = name }
            end
        end
    end
    if #orphans == 0 then return end

    for i = 1, #players do
        local player = players[i]
        if player:getPlayerNum() > 0 then
            -- O nome do personagem e o unico sinal que atravessa a morte. Sem ele, so adota quando
            -- ha um orfao unico e o jogador nao tem cao nenhum: ambiguidade nao move nada.
            local pick, free, count = nil, nil, 0
            local u = player:getUsername()
            for j = 1, #orphans do
                local o = orphans[j]
                if not o.taken then
                    count = count + 1
                    free = free or o
                    if pick == nil and o.name ~= nil and o.name == u then
                        pick = o
                    end
                end
            end
            if pick == nil and count == 1 and not ownsAnyDog(player) then
                pick = free
            end
            if pick then
                pick.taken = true
                local n = adoptOrphanBucket(player, pick.key)
                if CD.ADOPT_DEBUG then
                    CD.log(string.format("[CD-ADOPT] tela dividida: %s herdou %d registro(s) da chave orfa %s",
                        tostring(u), n, tostring(pick.key)))
                end
            end
        end
    end
end

CD.reconcileOwnerPresence, CD.bringActiveOnTeleport, CD.reapPhantomCompanions = reconcileOwnerPresence, bringActiveOnTeleport, reapPhantomCompanions
