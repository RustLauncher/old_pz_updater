CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.dogReg = { stampMs = -1, dogs = {}, companions = {}, strays = {}, byId = {}, byToken = {} }

---@param list List<IsoAnimal>
---@param i integer zero-based index
---@return IsoAnimal
---@nodiscard
CD.regListGet = function(list, i) return list:get(i) end
---@param a IsoAnimal
---@return boolean
---@nodiscard
CD.regIsLoadedDog = function(a) return CD.isDog(a) and a:isExistInTheWorld() end
---Files the animal under its online id and tells whether it is a companion.
---@param a IsoAnimal
---@param byId table online id to animal, filled in place
---@return boolean companion
CD.regClassifyDog = function(a, byId)
    byId[a:getOnlineID()] = a
    return CD.isCompanion(a)
end
---@param a IsoAnimal
---@param v boolean
CD.regApplySolid = function(a, v) a:setSolid(v) end
---Groups the companion by owner key, or by owner name when the record has no key.
---@param a IsoAnimal
---@param byOwner table owner key to list of animals, filled in place
---@param byOwnerName table owner username to list of animals, filled in place
CD.regIndexOwner = function(a, byOwner, byOwnerName)
    local d = CD.data(a)
    local key = d.ownerKey
    if key ~= nil and key ~= "" then
        local g = byOwner[key]
        if not g then
            g = {}
            byOwner[key] = g
        end
        g[#g + 1] = a
        return
    end
    local name = d.ownerName
    if name ~= nil and name ~= "" then
        local g = byOwnerName[name]
        if not g then
            g = {}
            byOwnerName[name] = g
        end
        g[#g + 1] = a
    end
end
---@param a IsoAnimal
---@param byToken table companion token to list of animals, filled in place
CD.regIndexToken = function(a, byToken)
    local t = CD.data(a).companionToken
    if t == nil then return end
    local g = byToken[t]
    if not g then
        g = {}
        byToken[t] = g
    end
    g[#g + 1] = a
end

---Rescans the cell into fresh CD.dogReg buckets and, unless CD.tripOverDogs(), makes companions non-solid and strays solid.
---@return table reg CD.dogReg
function CD.rebuildDogReg()
    local reg = CD.dogReg
    reg.stampMs = getTimestampMs()
    CD._regBuilds = (CD._regBuilds or 0) + 1
    local dogs, comps, strays, byId, byToken = {}, {}, {}, {}, {}
    reg.dogs, reg.companions, reg.strays, reg.byId, reg.byToken = dogs, comps, strays, byId, byToken
    local byOwner, byOwnerName = {}, {}
    reg.byOwner, reg.byOwnerName = byOwner, byOwnerName
    local cell = getCell()
    if not cell then return reg end
    local list = cell:getAnimals()
    local get, isdog, classify, index = CD.regListGet, CD.regIsLoadedDog, CD.regClassifyDog, CD.regIndexToken
    local solid = (not CD.tripOverDogs()) and CD.regApplySolid or nil
    local n = list:size()
    CD.perfCount("iter.regscan", n)
    for i = 0, n - 1 do
        local a = get(list, i)
        if a and isdog(a) then
            dogs[#dogs + 1] = a
            if classify(a, byId) then
                index(a, byToken)
                CD.regIndexOwner(a, byOwner, byOwnerName)
                comps[#comps + 1] = a
                if solid then
                    solid(a, false)
                end
            else
                strays[#strays + 1] = a
                if solid then
                    solid(a, true)
                end
            end
        end
    end
    return reg
end

---Forces the next registry read to rescan the cell.
function CD.regInvalidate()
    CD.dogReg.stampMs = -1
    CD.dogReg.lastSize = nil
end

---Rescans only when invalidated, the animal count changed, a listed dog left the world or DOG_REG_RECONCILE_MS passed.
---@return table reg CD.dogReg
function CD.rebuildDogRegIfChanged()
    local reg = CD.dogReg
    local now = getTimestampMs()
    local due = (reg.reconcileMs == nil)
                or ((now - reg.reconcileMs) > CD.DOG_REG_RECONCILE_MS)
    local cell = getCell()
    local list = cell and cell:getAnimals()
    local size = (list and list:size()) or -1
    local live = true
    if (not due) and size >= 0 and size == reg.lastSize and reg.stampMs >= 0 then
        local dg = reg.dogs
        for i = 1, #dg do
            local a = dg[i]
            if not (a and a:isExistInTheWorld()) then
                live = false
                break
            end
        end
        if live then
            CD.perfCount("reg.livecheck", #dg)
            CD.perfCount("reg.skipped")
            reg.stampMs = now
            return reg
        end
    end
    local prevDogs = (due and reg.dogs) and #reg.dogs or nil
    CD.rebuildDogReg()
    reg.lastSize = size
    if due then
        reg.reconcileMs = now
        if prevDogs ~= nil and prevDogs ~= #reg.dogs then
            CD.perfCount("reg.drift", math.abs(#reg.dogs - prevDogs))
        end
    end
    return reg
end

local function freshDogReg()
    if CD.DOG_REG == false then return CD.rebuildDogReg() end
    local reg = CD.dogReg
    local maxAge = CD._regTickDriven and CD.DOG_REG_STALE_MS or CD.DOG_REG_MAX_AGE_MS
    if reg.stampMs < 0 or (getTimestampMs() - reg.stampMs) > maxAge then
        return CD.rebuildDogReg()
    end
    return reg
end

---CD.dogReg, rescanned first when older than DOG_REG_STALE_MS (tick driven) or DOG_REG_MAX_AGE_MS.
---@return table reg
function CD.dogRegNow() return freshDogReg() end

---Companions and strays alike; a snapshot, so an entry may have left the world since.
---@return IsoAnimal[]
function CD.regDogs() return freshDogReg().dogs end

---Companions of every owner; a snapshot, so an entry may have left the world since.
---@return IsoAnimal[]
function CD.regCompanions() return freshDogReg().companions end

---Loaded companions filed under the player's owner key and, for records without a key, under the username.
---@param player IsoPlayer
---@return IsoAnimal[]|nil byKey
---@return IsoAnimal[]|nil byName
function CD.regCompanionsOf(player)
    local reg = freshDogReg()
    if not (reg.byOwner and reg.byOwnerName) then return nil, nil end
    local byKey, byName = nil, nil
    local k = CD.ownerKey(player)
    if k ~= nil and k ~= "" then
        byKey = reg.byOwner[k]
    end
    local u = player:getUsername()
    if u ~= nil and u ~= "" then
        byName = reg.byOwnerName[u]
    end
    return byKey, byName
end

---Loaded strays; a snapshot, so an entry may have left the world since.
---@return IsoAnimal[]
function CD.regStrays() return freshDogReg().strays end

---@param a IsoAnimal|nil
---@return boolean
---@nodiscard
CD.regLive = function(a) return a ~= nil and a:isExistInTheWorld() end

---Calls fn on every entry still in the world.
---@param list IsoAnimal[]|nil
---@param fn fun(a: IsoAnimal)
---@param key string|nil perf counter name, "iter.dogsweep" by default
---@return integer visited
CD.regEach = function(list, fn, key)
    if not list then return 0 end
    local n = 0
    for i = 1, #list do
        local a = list[i]
        if CD.regLive(a) then
            n = n + 1
            fn(a)
        end
    end
    CD.perfCount(key or "iter.dogsweep", n)
    return n
end

---The player's dog with this companion token, when it is loaded.
---@param player IsoPlayer|nil
---@param tok number|nil companion token
---@return IsoAnimal|nil
function CD.regByToken(player, tok)
    if player == nil or tok == nil then return nil end
    local g = freshDogReg().byToken[tok]
    if not g then return nil end
    for i = 1, #g do
        local a = g[i]
        if a and a:isExistInTheWorld() and CD.isOwnedBy(a, player) then return a end
    end
    return nil
end

---Closest owned companion on the player's floor, within radius tiles.
---@param playerObj IsoPlayer|nil
---@param radius number|nil 14 by default
---@return IsoAnimal|nil
function CD.findNearbyCompanion(playerObj, radius)
    if not playerObj then return nil end
    local pz = math.floor(playerObj:getZ())
    local R = radius or 14
    local best, bestDist = nil, 9999
    local ownKeyed, ownNamed = CD.regCompanionsOf(playerObj)
    for pass = 1, 2 do
        local lst = (pass == 1) and ownKeyed or ownNamed
        if lst then
            CD.perfCount("iter.ownercheck", #lst)
            for i = 1, #lst do
                local a = lst[i]
                local ok = a and a:isExistInTheWorld() and math.floor(a:getZ()) == pz and CD.isOwnedBy(a, playerObj)
                if ok then
                    local d = CD.dist2D(a, playerObj)
                    if d <= R and d < bestDist then
                        best, bestDist = a, d
                    end
                end
            end
        end
    end
    return best
end

---The active dog when loaded, else any owned dog not in care mode; nil after the player dismissed the active one.
---@param playerObj IsoPlayer|nil
---@return IsoAnimal|nil
function CD.getCompanionAnimal(playerObj)
    if not playerObj then return nil end
    local pd = CD.playerData(playerObj)
    local token = pd.token
    -- Sem a saida aqui o fallback abaixo devolveria um passivo qualquer e a UI voltaria a comanda-lo.
    if token == nil and pd.dismissed then return nil end
    local anyOwned = nil
    local ownKeyed, ownNamed = CD.regCompanionsOf(playerObj)
    for pass = 1, 2 do
        local comps = ((pass == 1) and ownKeyed or ownNamed) or {}
        for i = 1, #comps do
            local a = comps[i]
            if a:isExistInTheWorld() and CD.isOwnedBy(a, playerObj) then
                if not CD.data(a).careMode then
                    if token ~= nil and CD.data(a).companionToken == token then return a end
                    anyOwned = anyOwned or a
                end
            end
        end
    end
    return anyOwned
end

---Retries on the square and then on its dry neighbours when the engine hands back a half-built animal.
---@param x number
---@param y number
---@param z number
---@param atype string|nil animal type, "dogmale" by default
---@param breedName string|nil engine breed name; nil or unknown picks a random breed of the type
---@return IsoAnimal|nil
function CD.spawnDog(x, y, z, atype, breedName)
    atype = atype or "dogmale"
    if not CD.TYPES[atype] then return nil end
    local def = AnimalDefinitions.getDef(atype)
    if not def then return nil end
    local breed = (breedName and def:getBreedByName(breedName)) or def:getRandomBreed()
    local cell = getCell()
    x, y, z = tonumber(x), tonumber(y), tonumber(z)

    -- O construtor do IsoAnimal sai no meio em square de agua e em colisao de animalID, devolvendo um
    -- objeto com type, data e adef nulos. Valida antes de addToWorld: depois o cadaver ja esta na cell.
    local SAME_SQUARE_TRIES, NEIGHBOR_TRIES = 3, 2
    local function trySpawn(sx, sy)
        local a = addAnimal(cell, sx, sy, z, atype, breed, false)
        if not a then return nil end
        -- o objeto meio construido devolve nil nas tres leituras, sem lancar: o teste e por nil, nao por erro
        local half = not (a:getSquare() and a:getAnimalType() and a:getData())
        if not half then return a end
        a:removeFromWorld()
        a:delete()
        if not CD.spawnRejectLogged then
            CD.spawnRejectLogged = true
            CD.log("spawnDog descartou um animal meio construido em " .. tostring(sx) .. "," ..
                  tostring(sy) .. "," .. tostring(z) .. " (" .. tostring(atype) .. "); tentando de novo")
        end
        return nil
    end

    local animal
    local origin = cell:getGridSquare(x, y, z)
    if origin and not origin:isWaterSquare() then
        for _ = 1, SAME_SQUARE_TRIES do
            animal = trySpawn(x, y)
            if animal then break end
        end
    end
    if not animal then
        for dx = -1, 1 do
            for dy = -1, 1 do
                if not animal and (dx ~= 0 or dy ~= 0) then
                    local sq = cell:getGridSquare(x + dx, y + dy, z)
                    if sq and not sq:isWaterSquare() then
                        for _ = 1, NEIGHBOR_TRIES do
                            animal = trySpawn(x + dx, y + dy)
                            if animal then break end
                        end
                    end
                end
            end
        end
    end
    if not animal then
        CD.log("spawnDog falhou em todas as tentativas em " .. tostring(x) .. "," .. tostring(y) ..
              "," .. tostring(z) .. " (" .. tostring(atype) .. "); nenhum square seco disponivel")
        return nil
    end

    animal:randomizeAge()
    animal:setWild(false)
    animal:addToWorld()
    return animal
end

-- Nunca emitter:playSound aqui: num objeto movel o client reenvia um PlaySoundPacket que o server
-- retransmite, e os outros clients tocam duplicado e ignorando o mute. playSoundImpl e a rota certa.
CD.soundRefs = CD.soundRefs or {}
-- O emissor guardado ao lado do ref e o que salva o canal. O emissor so devolve canal dentro do
-- tick() dele, que so roda em IsoAnimal.update, e removeFromWorld nao encosta nele: cao que sai do
-- mundo com som de pe prende o canal pelo resto da sessao. O objeto Java do emissor sobrevive
-- enquanto o Lua o segurar, mesmo com getAnimal(id) ja devolvendo nil, e e por ele que o reaper
-- alcanca o canal orfao.
CD.soundEmitters = CD.soundEmitters or {}

-- Emissor so ganha posicao no update() do animal: fora do mundo ou sem atualizar ele esta em (0,0) e o FMOD toca em 2D.
---@param animal IsoAnimal
---@param sound string
---@return integer handle 0 when nothing played (muted, out of range, no emitter)
function CD.playAnimalSound(animal, sound)
    if not animal or not sound then return 0 end
    local f = (CD.Settings and CD.Settings.getVolumeFactor(sound)) or 1.0
    if f <= 0 then return 0 end
    if not animal:getSquare() then return 0 end
    if not CD.nearAnyLocalPlayer(animal, CD.soundRange(sound) + CD.SOUND_RANGE_MARGIN) then return 0 end
    local emitter = animal:getEmitter()
    local ref = emitter:playSoundImpl(sound, nil)
    if ref ~= 0 then
        if f ~= 1.0 then
            emitter:setVolume(ref, f)
        end
        if CD.SOUND_LOOPED and CD.SOUND_LOOPED[sound] then
            local id = animal:getOnlineID()
            CD.soundRefs[id] = CD.soundRefs[id] or {}
            CD.soundRefs[id][sound] = ref
            CD.soundEmitters[id] = emitter
        end
    end
    return ref or 0
end

local function semLoop(refs)
    for _ in pairs(refs) do return false end   -- Kahlua nao expoe next()
    return true
end

local function esqueceSom(id)
    CD.soundRefs[id] = nil
    CD.soundEmitters[id] = nil
end

---@param animal IsoAnimal|nil
---@param sound string|nil
function CD.stopAnimalSound(animal, sound)
    if not animal or not sound then return end
    local em = animal:getEmitter()
    if em then
        em:stopSoundByName(sound)
    end
    local id = animal:getOnlineID()
    local refs = CD.soundRefs[id]
    if refs then
        refs[sound] = nil
        if semLoop(refs) then
            esqueceSom(id)
        end
    end
end

-- Cao que sumiu sem passar pelo stop: o registro do loop continua de pe e o id nao resolve mais para
-- animal nenhum. Sem isto o canal toca ate o jogo fechar, porque quem devolveria o canal e o tick do
-- emissor e ele nao roda mais. O emissor retido alcanca o canal do mesmo jeito.
---Stops and forgets the looped sounds of dogs that left the world without a stop call.
function CD.reapSoundRefs()
    for id, refs in pairs(CD.soundRefs) do
        if not getAnimal(id) then
            local em = CD.soundEmitters[id]
            if em then
                for name in pairs(refs) do em:stopSoundByName(name) end
            end
            esqueceSom(id)
        end
    end
end

-- Chamar ANTES de o cao sair do mundo. O stopAll pega os tres sub-emissores do animal (extra,
-- footsteps, vocals), entao leva junto o foley da engine e o one-shot ainda pausado na fila toStart,
-- que um stop pela nossa lista de nomes nao alcancaria. Nao manda pacote: quem transmite StopSound
-- pela rede e o stopOrTriggerSound, nao este.
---@param animal IsoAnimal
function CD.releaseAnimalSounds(animal)
    if not animal then return end
    local em = animal:getEmitter()
    if em then
        em:stopAll()
    end
    esqueceSom(animal:getOnlineID())
end

---Re-applies the volume settings to the looped sounds still playing; one turned down to 0 is stopped.
function CD.refreshSoundVolumes()
    CD.reapSoundRefs()   -- depois desta linha todo id restante resolve para um animal vivo
    for id, refs in pairs(CD.soundRefs) do
        local em = getAnimal(id):getEmitter()
        for name, ref in pairs(refs) do
            local f = (CD.Settings and CD.Settings.getVolumeFactor and CD.Settings.getVolumeFactor(name)) or 1.0
            if f <= 0 then
                em:stopSoundByName(name)
                refs[name] = nil
            else
                em:setVolume(ref, f)
            end
        end
        if semLoop(refs) then
            esqueceSom(id)
        end
    end
end

-- A sobrecarga de 4 argumentos do sendClientCommand descarta EM SILENCIO quem nao e jogador LOCAL, e
-- varios chamadores passam CD.getOwnerPlayer, que num client de MP pode devolver jogador remoto. Sem
-- o player local o pacote vai com indice -1 e o servidor resolve pro primeiro slot da conexao, ou
-- seja o jogador 1 paga pelo que o jogador 2 pediu na tela dividida.
---@param player IsoPlayer|nil
---@param command string
---@param extra table
function CD.sendAs(player, command, extra)
    if player and player:isLocalPlayer() then
        sendClientCommand(player, CD.MODULE, command, extra)
    else
        sendClientCommand(CD.MODULE, command, extra)
    end
end

---Sends a command to the server; in SP calls the handler directly.
---@param command string key in CD.Server
---@param animal IsoAnimal|nil
---@param extra table|nil command arguments
---@param player IsoPlayer|nil who asks; in MP it must be the local player
function CD.request(command, animal, extra, player)
    extra = extra or {}
    if isClient() then
        if animal then
            extra.id = animal:getOnlineID()
        end
        CD.sendAs(player, command, extra)
    elseif CD.Server and CD.Server[command] then
        if animal then
            extra.__animal = animal
        end
        CD.Server[command](player or getPlayer(), extra)
    end
end

-- Com animal, so quem esta na caixa de relevancia: fora dela o client nem tem o cao carregado e
-- rodava o handler a toa. Sem animal continua broadcast.
local function emitNear(command, args, animal)
    local players = getOnlinePlayers()
    local range = CD.EMIT_RANGE
    local ax, ay = animal:getX(), animal:getY()
    local np = players:size()
    local sent = 0
    for i = 0, np - 1 do
        local p = players:get(i)
        if p and math.abs(p:getX() - ax) <= range and math.abs(p:getY() - ay) <= range then
            sendServerCommand(p, CD.MODULE, command, args)
            sent = sent + 1
        end
    end
    CD.perfCount("net.emit", sent)
end

---Server: to the clients within EMIT_RANGE of the animal, or to all without one; otherwise runs the client handler here.
---@param command string
---@param args table
---@param animal IsoAnimal|nil
function CD.emit(command, args, animal)
    if isServer() then
        if animal then
            emitNear(command, args, animal)
        else
            sendServerCommand(CD.MODULE, command, args)
        end
    else
        if animal then
            args.__animal = animal
        end
        CD.onServerCommand(CD.MODULE, command, args)
    end
end

-- O delete da engine avisa os clients uma vez so, quase sempre em pacote UDP sem garantia
-- (AnimalUpdateUnreliablePacket). Perdeu, o client fica com um cao fantasma congelado ate
-- descarregar o chunk. O comando abaixo vai por ClientCommand, que e confiavel.
---@param animal IsoAnimal
function CD.despawn(animal)
    local id = animal:getOnlineID()
    CD.releaseAnimalSounds(animal)
    animal:delete()
    if CD.DEBUG_DESPAWN then
        CD.log(string.format("[CD-DESPAWN] srv delete id=%s nome=%s pos(%.1f,%.1f) isServer=%s",
            tostring(id), tostring(CD.data(animal).name), animal:getX(), animal:getY(), tostring(isServer())))
    end
    if isServer() then
        sendServerCommand(CD.MODULE, "despawn", { id = id })
    end
end

---CD.request with no animal, for commands about a dog that is not loaded.
---@param command string key in CD.Server
---@param extra table|nil command arguments
---@param player IsoPlayer|nil who asks; in MP it must be the local player
function CD.requestStashed(command, extra, player)
    extra = extra or {}
    if isClient() then
        CD.sendAs(player, command, extra)
    elseif CD.Server and CD.Server[command] then
        CD.Server[command](player or getPlayer(), extra)
    end
end
