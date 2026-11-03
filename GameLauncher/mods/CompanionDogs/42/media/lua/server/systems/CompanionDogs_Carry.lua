CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs
CD.Server = CD.Server or {}

local function recordStillBonded(pd, tok)
    if tok == nil then return false end
    if type(pd.companions) == "table" and pd.companions[tok] then return true end
    return tok == pd.token
end
CD.recordStillBonded = recordStillBonded

local function findCarriedDogItem(player)
    if not player then return nil end
    local inv = player:getInventory()
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and instanceof(it, "AnimalInventoryItem") then
            local a = it:getAnimal()
            if a and CD.isDog(a) then return it, a end
        end
    end
    return nil
end

local function carryingDogWithToken(player, tok)
    if not player or tok == nil then return false end
    local inv = player:getInventory()
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and instanceof(it, "AnimalInventoryItem") then
            local a = it:getAnimal()
            if a and CD.isDog(a) and CD.isOwnedBy(a, player) and CD.data(a).companionToken == tok then return true end
        end
    end
    return false
end
CD.carryingDogWithToken = carryingDogWithToken

local function recoverStashedDogs()
    CD.eachOnlinePlayer(function(player)
        local pd = CD.playerData(player)
        local rec = pd.stash
        if not rec then return end
        local stok = rec.data and rec.data.companionToken
        if not recordStillBonded(pd, stok) then
            pd.stash = nil
            if player then
                player:transmitModData()
            end
            return
        end
        if CD.isMounted(player) then return end
        if CD.regByToken(player, stok) then
            pd.stash = nil
            if player then
                player:transmitModData()
            end
            return
        end
        if carryingDogWithToken(player, stok) then
            pd.stash = nil
            if player then
                player:transmitModData()
            end
            return
        end
        local fresh = CD.respawnCompanion(nil, player, rec)
        if fresh then
            local fd = CD.data(fresh)
            CD.ensureUidData(fd)
            CD.bumpCanonical(player, fresh)
            pd.stash = nil
            if player then
                player:transmitModData()
            end
        end
    end)
end

do
    local KEY = CD.MODULE .. "_OfflineStash"
    local function store() return ModData.getOrCreate(KEY) end

    -- Chamado fora do loop de iteracao: delete no meio encolhe a lista Java e o get(i) estoura.
    ---@param animal IsoAnimal
    function CD.offlineStashDog(animal)
        local d = CD.data(animal)
        local tok = d.companionToken
        local key = (d.ownerKey ~= nil and d.ownerKey ~= "") and d.ownerKey or d.ownerName
        if not key or key == "" or not tok then return end
        d.stashed = true
        local rec = CD.buildStashRecord(animal)
        rec.x = math.floor(animal:getX())
        rec.y = math.floor(animal:getY())
        rec.z = math.floor(animal:getZ())
        local s = store()
        s[key] = s[key] or {}
        s[key][tok] = rec
        local oid = animal:getOnlineID()
        animal:stopAllMovementNow()
        CD.despawn(animal)
        CD.reapDogState(oid)
    end

    ---A dog with this token waits in the offline stash, under the player's owner key or username.
    ---@param player IsoPlayer|nil
    ---@param tok number|nil companion token
    ---@return boolean
    ---@nodiscard
    function CD.offlineStashHas(player, tok)
        if not player or tok == nil then return false end
        local s = store()
        local recs = s[CD.ownerKey(player)] or s[player:getUsername()]
        return type(recs) == "table" and recs[tok] ~= nil
    end

    ---Brings back the dogs stashed while their owner was offline: the active follower beside the owner, the others on their saved tile once it is loaded.
    function CD.recoverOfflineStashes()
        CD.eachOnlinePlayer(function(player)
            local s = store()
            local name = player:getUsername()
            local key = CD.ownerKey(player)
            local bucketKey = (key and s[key]) and key or name
            local recs = bucketKey and s[bucketKey]
            if not recs then return end
            local pd = CD.playerData(player)
            local toks = {}
            for tok in pairs(recs) do toks[#toks + 1] = tok end
            for i = 1, #toks do
                local tok = toks[i]
                local rec = recs[tok]
                local drop = false
                if not rec or not rec.data or not recordStillBonded(pd, tok) then
                    drop = true
                elseif pd.stash and pd.stash.data and pd.stash.data.companionToken == tok then
                    drop = true
                elseif CD.regByToken(player, tok) or carryingDogWithToken(player, tok) then
                    drop = true
                else
                    local follow = (rec.data.state or CD.STATE_FOLLOW) == CD.STATE_FOLLOW and tok == pd.token
                    local ready, atSq = true, nil
                    if follow then
                        if CD.isMounted(player) then
                            ready = false
                        end
                    else
                        atSq = rec.x and getCell() and getCell():getGridSquare(rec.x, rec.y, rec.z) or nil
                        if not atSq then
                            ready = false
                        end
                    end
                    if ready then
                        local fresh = CD.respawnCompanion(nil, player, rec, atSq)
                        if fresh then
                            local fd = CD.data(fresh)
                            CD.ensureUidData(fd)
                            CD.bumpCanonical(player, fresh)
                            drop = true
                        end
                    end
                end
                if drop then
                    recs[tok] = nil
                end
            end
            local empty = true
            for _ in pairs(recs) do  -- next() nao existe no Kahlua do PZ
                empty = false
                break
            end
            if empty then
                s[bucketKey] = nil
            end
        end)
    end
end

---A dog carried in the arms of a player in a vehicle moves into the vehicle stash.
---@param player IsoPlayer|nil
---@return boolean converted
function CD.convertCarriedToStash(player)
    if not player or not CD.isMounted(player) then return false end
    local item, held = findCarriedDogItem(player)
    if not (item and held and CD.isDog(held) and CD.isOwnedBy(held, player) and CD.isCompanion(held)) then
        return false
    end
    local pd = CD.playerData(player)
    local oid = held:getOnlineID()
    CD.writeStashRecord(held, player)
    pd.carried = nil
    -- sendRemoveItemFromContainer antes do Remove: um Remove cru deixa item fantasma travado no client.
    local cont = item:getContainer() or player:getInventory()
    if isServer() then
        sendRemoveItemFromContainer(cont, item)
    end
    cont:Remove(item)
    CD.reapDogState(oid)
    player:transmitModData()
    return true
end

---@param player IsoPlayer
---@param args table|nil unused
CD.Server.stashcarried = function(player, args)
    CD.convertCarriedToStash(player)
end

---False only when the record keeps an animal ID and the dog has another: its online ID was reused.
---@param rec table|nil carried record { onlineID, animalId, data }
---@param dog IsoAnimal|nil
---@return boolean
---@nodiscard
CD.carriedIdentityOk = function(rec, dog)
    if rec == nil or rec.animalId == nil or dog == nil then return true end
    local aid = dog:getAnimalID()
    return aid == rec.animalId
end

local function rematerialize(dog, player)
    local nd = CD.data(dog)
    nd.mounted = nil
    nd.stashed = nil
    nd.diedNotified = nil
    nd.ownerId = nil
    if player then
        CD.restoreFromKennel(player, dog)
    end
    dog:setWild(false)
    dog:setShootable(false)
    dog:setIsInvincible(true)
    CD.transmit(dog)
    if CD.hasBag(dog) then
        CD.applyBagVisual(dog)
    end
end

-- Ate o 42.20 o copyFrom do drop e do trailer descartava o ModData e o cao voltava selvagem. No 42.21
-- ele copia o ModData, e o cao ja volta companheiro, com o mesmo token do registro.
local function backFromStow(rec, dog)
    if not CD.isCompanion(dog) then return true end
    return rec.data ~= nil and CD.data(dog).companionToken == rec.data.companionToken
end

---Puts the carried record back on the dog once it is out of the arms and in the world.
---@param player IsoPlayer|nil restores the kennel fields when given
---@param rec table|nil carried record { onlineID, animalId, data }
---@return IsoAnimal|nil dog nil while the dog is not back in the world
CD.reattachCarried = function(player, rec)
    if not rec then return nil end
    local dog = getAnimal(rec.onlineID)
    local inWorld = dog ~= nil and dog:getSquare() ~= nil
    if not (dog and inWorld and CD.isDog(dog) and backFromStow(rec, dog)) then return nil end
    if not CD.carriedIdentityOk(rec, dog) then return nil end
    dog:getModData().CompanionDogs = rec.data
    rematerialize(dog, player)
    return dog
end

---Keeps a carried dog that is back in the world tame, unshootable and invincible until its record is put back.
CD.tickCarriedGuard = function()
    CD.eachOnlinePlayer(function(player)
        local pd = CD.playerData(player)
        local rec = pd.carried
        if not rec then return end
        if not recordStillBonded(pd, rec.data and rec.data.companionToken) then return end
        local dog = getAnimal(rec.onlineID)
        if not dog then return end
        if dog:getSquare() == nil or not CD.isDog(dog) or not backFromStow(rec, dog) then return end
        if not CD.carriedIdentityOk(rec, dog) then return end
        dog:setWild(false)
        dog:setShootable(false)
        dog:setIsInvincible(true)
    end)
end

local function recoverCarriedDogs()
    CD.eachOnlinePlayer(function(player)
        local pd = CD.playerData(player)
        local item, held = findCarriedDogItem(player)

        if held and CD.isDog(held) and CD.isOwnedBy(held, player) and CD.isCompanion(held) then
            local d = CD.data(held)
            local oid = held:getOnlineID()
            if not pd.carried or pd.carried.onlineID ~= oid then
                local droppedActive = nil
                if pd.carried and pd.carried.data and pd.carried.data.companionToken ~= d.companionToken then
                    droppedActive = CD.reattachCarried(player, pd.carried)
                end
                local aid = held:getAnimalID()
                pd.carried = { onlineID = oid, animalId = aid, data = d }
                if pd.stash and pd.stash.data and pd.stash.data.companionToken == d.companionToken then
                    pd.stash = nil
                end
                if d.companionToken then
                    CD.kennelSeedFromData(player, d.companionToken, d)
                end
                if player then
                    player:transmitModData()
                end
                if droppedActive and CD.Server and CD.Server.select then
                    CD.Server.select(player, { __animal = droppedActive })
                end
            else
                pd.carried.data = d
                pd.carried.missingMs = nil
                if pd.carried.animalId == nil then
                    pd.carried.animalId = held:getAnimalID()
                end
            end

            local hp = held:getHealth()
            if hp <= 0 then
                if not d.diedNotified then
                    -- Antes do clearKennel abaixo, que apaga o espelho, e da remocao do item, que
                    -- leva o ModData: depois de qualquer um dos dois nao ha mais carga pra derramar.
                    CD.spillBag(held)
                    d.diedNotified = true
                    if d.companionToken == pd.token then
                        pd.token = nil
                        pd.name = nil
                    end
                    if d.companionToken ~= nil and type(pd.companions) == "table" then
                        pd.companions[d.companionToken] = nil
                    end
                    CD.clearKennel(player, d.companionToken)
                    local shock, mins = CD.griefFor(CD.loyalty(held))
                    CD.startGrief(player, shock, mins, d.name)
                    CD.notifyOwner(player, "died", { name = d.name, breed = CD.getBreed(held) })
                    CD.promoteSuccessor(player, held)
                    CD.logCompanionDeath(held, "colo")
                end
                local dcont = item:getContainer() or player:getInventory()
                if isServer() then
                    sendRemoveItemFromContainer(dcont, item)
                end
                if dcont then
                    dcont:Remove(item)
                end
                pd.carried = nil
                CD.reapDogState(oid)
                if player then
                    player:transmitModData()
                end
                return
            end
            if CD.convertCarriedToStash(player) then return end
            if CD.vetCareEnabled() then
                CD.tickVetOne(held, player, d, CD.worldMinutes())
            end
            if CD.upkeepEnabled() and d.companionToken == pd.token then
                CD.updateUpkeep(held, player, d)
            end
            return
        end

        local rec = pd.carried
        if not rec then return end
        if not recordStillBonded(pd, rec.data and rec.data.companionToken) then
            pd.carried = nil
            if player then
                player:transmitModData()
            end
            return
        end
        if CD.reattachCarried(player, rec) then
            pd.carried = nil
            if player then
                player:transmitModData()
            end
        end
        if pd.carried ~= nil then
            local tok = rec.data and rec.data.companionToken
            if tok ~= nil and CD.carriedTokenAnywhere and not CD.carriedTokenAnywhere(player, tok) then
                local nowMs = getTimestampMs()
                rec.missingMs = rec.missingMs or nowMs
                if nowMs - rec.missingMs >= CD.CARRIED_STALE_MS then
                    pd.carried = nil
                    CD.kennelSeedFromData(player, tok, rec.data)
                    local marked = CD.markCompanionLost(player, tok)
                    if marked then
                        CD.notifyOwner(player, "lost", { name = rec.data.name, breed = rec.data.breed })
                    end
                    if player then
                        player:transmitModData()
                    end
                end
            else
                rec.missingMs = nil
            end
        end
    end)
end

local function trailerAnimals(cell)
    local out = {}
    local set = cell and cell:getVehicles()
    if not set then return out end
    local vehicles = ArrayList.new()
    vehicles:addAll(set)
    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        local animals = v:getAnimals()
        if animals then
            for j = 0, animals:size() - 1 do
                local a = animals:get(j)
                if a and CD.isDog(a) and CD.isCompanion(a) then
                    out[#out + 1] = { a = a, v = v }
                end
            end
        end
    end
    return out
end

local function recoverTraileredDogs()
    local cell = getCell()
    if not cell then return end
    local seen = {}
    local evict = {}

    for _, p in ipairs(trailerAnimals(cell)) do
        local a, v = p.a, p.v
        local oid = a:getOnlineID()
        local d = CD.data(a)
        local staleClone, owner = false, nil
        if d.uid ~= nil then
            owner = CD.getOwnerPlayer(a)
            if owner then
                local wm = CD.playerData(owner).uidGen
                if type(wm) == "table" and wm[d.uid] ~= nil and (d.gen or 0) < wm[d.uid] then
                    staleClone = true
                end
            end
        end
        if staleClone then
            evict[#evict + 1] = { a = a, v = v, owner = owner }
        else
            local rec = CD.trailerRecords[oid]
            if not rec then
                CD.trailerRecords[oid] = { onlineID = oid, data = d, ownerName = d.ownerName, ownerKey = d.ownerKey }
            else
                rec.data = d
                rec.ownerName = d.ownerName
                rec.ownerKey = d.ownerKey
                rec.retries = nil
            end
            seen[oid] = true
            if not a:isInvincible() then
                a:setIsInvincible(true)
            end
        end
    end

    for e = 1, #evict do
        local ev = evict[e]
        local oid = nil
        if ev.a then
            oid = ev.a:getOnlineID()
        end
        if ev.v then
            local gone = ev.v:removeAnimalFromTrailer(ev.a)
            if gone and instanceof(gone, "IsoAnimal") then
                gone:addToWorld()
            end
            sendRemoveAnimalFromTrailer(ev.a, ev.owner, ev.v)
            if gone and instanceof(gone, "IsoAnimal") then
                CD.reapDogState(gone:getOnlineID())
                CD.despawn(gone)
            end
        end
        if oid ~= nil then
            CD.trailerRecords[oid] = nil
        end
    end

    for oid, rec in pairs(CD.trailerRecords) do
        if not seen[oid] then
            local stale = rec.data == nil
            if not stale then
                local players = getOnlinePlayers()
                if rec.ownerKey or rec.ownerName then
                    for i = 0, players:size() - 1 do
                        local p = players:get(i)
                        local match = false
                        if rec.ownerKey ~= nil and rec.ownerKey ~= "" then
                            match = CD.ownerKey(p) == rec.ownerKey
                        else
                            match = p:getUsername() == rec.ownerName
                        end
                        if p and match then
                            local pd = CD.playerData(p)
                            if rec.data.companionToken ~= nil
                               and not recordStillBonded(pd, rec.data.companionToken) then
                                stale = true
                            end
                            if rec.data.uid ~= nil and type(pd.uidGen) == "table" and pd.uidGen[rec.data.uid] ~= nil
                               and (rec.data.gen or 0) < pd.uidGen[rec.data.uid] then
                                rec.staleClone = true
                            end
                        end
                    end
                end
            end
            if stale then
                CD.trailerRecords[oid] = nil
            else
                local dog = getAnimal(oid)
                if dog and CD.isDog(dog) then
                    if rec.staleClone then
                        if backFromStow(rec, dog) then
                            CD.reapDogState(oid)
                            CD.despawn(dog)
                        end
                        CD.trailerRecords[oid] = nil
                    elseif not CD.isCompanion(dog) or (backFromStow(rec, dog) and dog:getSquare() ~= nil) then
                        dog:getModData().CompanionDogs = rec.data
                        rematerialize(dog, CD.getOwnerPlayer(dog))
                        CD.trailerRecords[oid] = nil
                    else
                        if dog:getSquare() ~= nil then
                            CD.trailerRecords[oid] = nil
                        end
                    end
                else
                    rec.retries = (rec.retries or 0) + 1
                    if rec.retries > CD.TRAILER_RECOVER_MAX_RETRIES then
                        CD.trailerRecords[oid] = nil
                    end
                end
            end
        end
    end
end

-- o cao do jogador num trailer, com a geracao ainda valida; nil se nenhum veiculo carrega ele
local function findTrailerDog(player, pd, tok)
    for _, p in ipairs(trailerAnimals(getCell())) do
        local a, v = p.a, p.v
        if CD.isOwnedBy(a, player) and CD.data(a).companionToken == tok then
            local d = CD.data(a)
            local wm = type(pd.uidGen) == "table" and d.uid ~= nil and pd.uidGen[d.uid] or nil
            if wm == nil or (d.gen or 0) >= wm then
                return a, v
            end
        end
    end
    return nil
end

---Takes the player's dog with this token out of a trailer into the world, with its record.
---@param player IsoPlayer|nil
---@param tok number|nil companion token
---@return IsoAnimal|nil dog the new world copy; nil when no trailer holds it
CD.trailerExtract = function(player, tok)
    if not player or tok == nil then return nil end
    local pd = CD.playerData(player)
    local found, foundVeh = findTrailerDog(player, pd, tok)
    if not found or not foundVeh then return nil end
    local data = CD.cdDeepCopy(CD.data(found))
    local oldOid = found:getOnlineID()
    local newDog = foundVeh:removeAnimalFromTrailer(found)
    if newDog and instanceof(newDog, "IsoAnimal") then
        newDog:addToWorld()
    end
    sendRemoveAnimalFromTrailer(found, player, foundVeh)
    CD.trailerRecords[oldOid] = nil
    if not newDog or not instanceof(newDog, "IsoAnimal") then return nil end
    newDog:getModData().CompanionDogs = data
    local nd = CD.data(newDog)
    nd.mounted = nil
    nd.stashed = nil
    nd.diedNotified = nil
    nd.ownerId = nil
    CD.restoreFromKennel(player, newDog)
    newDog:setWild(false)
    newDog:setShootable(false)
    newDog:setIsInvincible(true)
    CD.transmit(newDog)
    if CD.hasBag(newDog) then
        CD.applyBagVisual(newDog)
    end
    return newDog
end
CD.recoverStashedDogs, CD.recoverCarriedDogs, CD.recoverTraileredDogs = recoverStashedDogs, recoverCarriedDogs, recoverTraileredDogs
