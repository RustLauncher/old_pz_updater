CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.Server = CD.Server or {}

local function recFromKennelSnap(player, pd, tok, snap)
    local data = CD.deepCopy(snap)
    data.fp = nil
    data.animalId = nil
    data.savedAtMin = nil
    data.lost = nil
    data.x, data.y, data.z = nil, nil, nil
    data.age, data.hunger, data.thirst, data.hp = nil, nil, nil, nil
    data.lastKennelMin = nil
    data.recallAtMin = nil
    data.companion = true
    CD.regInvalidate()
    data.ownerName = player:getUsername()
    data.ownerKey = CD.ownerKey(player)
    data.companionToken = tok
    data.state = (pd.token == nil or tok == pd.token) and CD.STATE_FOLLOW or CD.STATE_STAY
    return {
        type = CD.breedAnimalType(data.breed, data.isPup and "pup" or data.sex),
        female = (data.sex == "female"),
        age = snap.age,
        hp = snap.hp,
        hunger = snap.hunger,
        thirst = snap.thirst,
        data = data,
    }
end

local function stampRecall(player, pd, tok, now)
    pd.kennel = pd.kennel or {}
    pd.kennel[tok] = pd.kennel[tok] or { companionToken = tok }
    pd.kennel[tok].recallAtMin = now
    if player then
        player:transmitModData()
    end
end

---Binds the kennel record to the one unbonded stray carrying the snapshot's animal ID; nil when none or more than one matches.
---@param player IsoPlayer|nil
---@param tok number|nil companion token
---@param snap table|nil kennel snapshot
---@param maxDist number|nil tiles from the player on each axis; nil means anywhere loaded
---@return IsoAnimal|nil
CD.adoptByAnimalId = function(player, tok, snap, maxDist)
    if not player or tok == nil or type(snap) ~= "table" then return nil end
    local want = snap.animalId
    if want == nil then
        if CD.ADOPT_DEBUG then
            CD.log(string.format("[CD-ADOPT] token=%s sem animalId no snapshot (save anterior ao campo): recusa, sem fallback",
                tostring(tok)))
        end
        return nil
    end
    local wantFam = CD.BREEDS[snap.breed] and CD.BREEDS[snap.breed].typePrefix
    local px, py = player:getX(), player:getY()
    local found, ambiguous = nil, false
    CD.regEach(CD.regStrays(), function(a)
        local aid = a:getAnimalID()
        local hp = a:getHealth()
        local sq = a:getSquare()
        local fam = CD.BREEDS[CD.getBreed(a)] and CD.BREEDS[CD.getBreed(a)].typePrefix
        local near = maxDist == nil
            or (math.abs(a:getX() - px) <= maxDist and math.abs(a:getY() - py) <= maxDist)
        local ok = aid == want and hp > 0 and sq ~= nil and near
            and (wantFam == nil or fam == nil or wantFam == fam)
        if CD.ADOPT_DEBUG then
            CD.log(string.format("[CD-ADOPT] token=%s candidato aid=%s(quero %s) fam=%s(quero %s) hp=%.0f perto=%s -> %s",
                tostring(tok), tostring(aid), tostring(want), tostring(fam), tostring(wantFam),
                hp or 0, maxDist == nil and "s/limite" or tostring(near), ok and "CASOU" or "recusado"))
        end
        if ok then
            if found then
                if CD.ADOPT_DEBUG then
                    CD.log(string.format("[CD-ADOPT] token=%s AMBIGUO: 2 caes sem vinculo casaram aid=%s, nao carimba em nenhum",
                        tostring(tok), tostring(want)))
                end
                ambiguous = true
            end
            found = a
        end
    end)
    if ambiguous then return nil end
    if not found then
        if CD.ADOPT_DEBUG then
            CD.log(string.format("[CD-ADOPT] token=%s nenhum cao sem vinculo casou aid=%s: caller segue pro caminho antigo",
                tostring(tok), tostring(want)))
        end
        return nil
    end

    local pd = CD.playerData(player)
    found:getModData().CompanionDogs = recFromKennelSnap(player, pd, tok, snap).data
    if not CD.isCompanion(found) then return nil end
    found:setWild(false)
    found:setShootable(false)
    found:setIsInvincible(true)
    CD.transmit(found)
    if CD.hasBag(found) then
        CD.applyBagVisual(found)
    end
    pd.companions = pd.companions or {}
    pd.companions[tok] = true
    if pd.token == nil then
        CD.setActiveDog(pd, tok, CD.data(found).name)
    end
    CD.ensureUid(found)
    snap.uid = CD.data(found).uid
    CD.bumpCanonical(player, found)
    snap.lost = nil
    CD.kennelSnapshot(player, found)
    player:transmitModData()
    return found
end

---Brings a kennel dog to the player: teleports it when loaded, takes it out of a trailer, adopts its unbonded body or respawns it from the record.
---@param player IsoPlayer
---@param args table|nil { token }
CD.Server.recall = function(player, args)
    if not player then return end
    local tok = args and tonumber(args.token)
    if tok == nil then return end
    local pd = CD.playerData(player)
    local snap = pd.kennel and pd.kennel[tok]
    if not snap and CD.kennelGlobalGet then
        local g = CD.kennelGlobalGet(CD.ownerKey(player))
        if g and g[tok] then
            pd.kennel = pd.kennel or {}
            pd.kennel[tok] = CD.deepCopy(g[tok])
            snap = pd.kennel[tok]
        end
    end

    local now = CD.worldMinutes()
    local cd = CD.KENNEL_RECALL_COOLDOWN_MIN
    if snap and snap.recallAtMin and (now - snap.recallAtMin) < cd then
        CD.notifyOwner(player, "refused", { reason = "recallcd", name = snap.name, breed = snap.breed })
        return
    end

    local live = CD.regByToken(player, tok)
    if live then
        if CD.ADOPT_DEBUG then
            CD.log(string.format("[CD-ADOPT] Trazer token=%s: cao VIVO com vinculo ja na cell, teleporta (adocao nao foi consultada)",
                tostring(tok)))
        end
        if not CD.isDisloyal(live) then
            stampRecall(player, pd, tok, now)
        end
        CD.Server.teleport(player, { __animal = live })
        CD.kennelSnapshot(player, live)
        return
    end

    local ctok = pd.carried and pd.carried.data and pd.carried.data.companionToken
    if tok == ctok then
        CD.notifyOwner(player, "refused", { reason = "carried", name = snap and snap.name, breed = snap and snap.breed })
        return
    end
    local stok = pd.stash and pd.stash.data and pd.stash.data.companionToken
    if tok == stok then
        CD.notifyOwner(player, "refused", { reason = "invehicle", name = snap and snap.name, breed = snap and snap.breed })
        return
    end
    if CD.tokenTrailered(player, tok) then
        local driving = CD.isMounted(player) or player:getVehicle() ~= nil
        if not driving and CD.trailerExtract then
            local dog = CD.trailerExtract(player, tok)
            if dog then
                if not CD.isDisloyal(dog) then
                    stampRecall(player, pd, tok, now)
                end
                CD.Server.teleport(player, { __animal = dog })
                CD.kennelSnapshot(player, dog)
                return
            end
        end
        CD.notifyOwner(player, "refused", { reason = "invehicle", name = snap and snap.name, breed = snap and snap.breed })
        return
    end

    if not snap then
        CD.notifyOwner(player, "refused", { reason = "nodata" })
        return
    end
    local orphan = CD.adoptByAnimalId(player, tok, snap)
    if orphan then
        if not CD.isDisloyal(orphan) then
            stampRecall(player, pd, tok, now)
        end
        CD.Server.teleport(player, { __animal = orphan })
        CD.kennelSnapshot(player, orphan)
        return
    end

    if CD.ADOPT_DEBUG then
        CD.log(string.format("[CD-ADOPT] Trazer token=%s: caiu no RESPAWN (nenhum orfao casou) -- daqui sai um cao NOVO",
            tostring(tok)))
    end
    local dog = CD.respawnCompanion(nil, player, recFromKennelSnap(player, pd, tok, snap))
    if not dog then
        CD.notifyOwner(player, "refused", { reason = "nodata" })
        return
    end
    if pd.token == nil then
        CD.setActiveDog(pd, tok, CD.data(dog).name)
    end
    CD.ensureUid(dog)
    snap.uid = CD.data(dog).uid
    CD.bumpCanonical(player, dog)
    if CD.data(dog).isPup then
        local gd = dog:getData()
        if gd then
            gd:setSizeForced(CD.puppySize(dog))
        end
    end
    pd.companions = pd.companions or {}
    pd.companions[tok] = true
    snap.lost = nil
    stampRecall(player, pd, tok, now)
    CD.kennelSnapshot(player, dog)
    CD.notifyOwner(player, "teleported", { id = dog:getOnlineID(), breed = CD.getBreed(dog) })
end

do
    local KEY = CD.MODULE .. "_Kennel"
    local function store() return ModData.getOrCreate(KEY) end

    ---Mirrors a kennel record in the world store, which outlives the character.
    ---@param ownerKey string|nil
    ---@param tok number|nil
    ---@param snap table|nil kept as a deep copy
    function CD.kennelGlobalPut(ownerKey, tok, snap)
        if ownerKey == nil or ownerKey == "" or tok == nil or type(snap) ~= "table" then return end
        local s = store()
        s[ownerKey] = s[ownerKey] or {}
        s[ownerKey][tok] = CD.deepCopy(snap)
    end

    ---@param ownerKey string|nil
    ---@return table|nil records by token, the live table
    ---@nodiscard
    function CD.kennelGlobalGet(ownerKey)
        if ownerKey == nil or ownerKey == "" then return nil end
        return store()[ownerKey]
    end

    ---@return table store records by owner key, then by token; the live table
    ---@nodiscard
    function CD.kennelGlobalAll()
        return store()
    end

    ---Removes one record, and the owner's bucket once it is empty.
    ---@param ownerKey string|nil
    ---@param tok number|nil
    function CD.kennelGlobalDrop(ownerKey, tok)
        if ownerKey == nil or ownerKey == "" or tok == nil then return end
        local s = store()
        local recs = s[ownerKey]
        if type(recs) ~= "table" then return end
        recs[tok] = nil
        local empty = true
        for _ in pairs(recs) do  -- next() nao existe no Kahlua do PZ
            empty = false
            break
        end
        if empty then
            s[ownerKey] = nil
        end
    end
end
