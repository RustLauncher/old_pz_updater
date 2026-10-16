CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local KENNEL_FIELDS = {
    "ownerKey", "ownerName",
    "uid", "breed", "sex", "genes", "lineage", "generation",
    "motherUid", "fatherUid", "motherName", "fatherName", "motherBreed", "fatherBreed",
    "name", "trust", "state",
    "isPup", "bornMin", "growthPaused", "bag", "maxHealth", "autoProtect", "alertMode", "huntMode",
    "breedingOff",
    "careMode", "careX", "careY", "careZ",
    "zombieKills", "preyKills",
    "sniffed", "fetched",
}

-- Estado com prazo, espelhado no snapshot mas FORA de KENNEL_FIELDS de proposito. O recFromKennelSnap
-- copia o snap inteiro, entao estes sobrevivem ao respawn; ja o restoreFromKennel so itera
-- KENNEL_FIELDS, e um campo aqui dentro dele ressuscitaria a doenca ja curada no proximo restore.
local VOLATILE_FIELDS = {
    "sickUntilMin", "meatDebtMin", "weak",
    "vetKind", "vetStage", "vetMin", "vetDress", "vetCureMin", "vetExpoMin", "vetLastHitMin", "vetPaw", "vetBleedMin",
    "vetBroken", "vetStageMin", "vetInfectMin", "vetCrit", "vetAbxMin", "vetStayForced",
    "vetGastroMin", "vetWorms", "vetWormsExpoMin", "vetDewormMin", "vetImmuneUntilMin", "vetWaterRollMin", "vetDressItem", "vetDressDirty",
    "vetFluMin", "vetFluQuiet", "vetFluRollMin", "vetFluExpoMin",
    "vetHwMin", "vetHwOutMin", "vetHwPrevUntilMin",
    "vetAlgMin", "vetAlgParts", "vetAlgSrc", "vetAllergen", "vetAllergenDrawn", "vetAllergenKnown", "vetAlgPrevUntilMin",
    "vetFleas", "vetTicks", "vetFleaPulseMin", "vetTickPulseMin", "vetFleaPrevUntilMin",
    "vetDewormPrevUntilMin",
    "vetCourseFlu", "vetCourseHw", "vetCourseAlg", "vetCourseFlea",
    "vetCourseWorms", "vetGarlicMin", "vetFluReliefMin", "vetAidPlantain", "vetAidAloe", "vetAidComfrey", "vetSplint",
    "vetPickedMin", "vetPickedFleas", "vetPickedTicks", "vetBalanceMin", "vetBoostUntilMin", "vetGastroEased", "vetToxicEased",
}

---Breed, sex, name and rounded genes joined in one string.
---@param animal IsoAnimal
---@return string
---@nodiscard
function CD.kennelFingerprint(animal)
    local d = CD.data(animal)
    local g = ""
    if type(d.genes) == "table" then
        local keys = {}
        for k in pairs(d.genes) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            g = g .. k .. ":" .. tostring(math.floor((d.genes[k] or 0) * 100 + 0.5)) .. ","
        end
    end
    return tostring(CD.getBreed(animal)) .. "|" .. tostring(d.sex or CD.animalSex(animal) or "?")
        .. "|" .. tostring(d.name or "") .. "|" .. g
end

---Server side: saves the dog's lasting fields in the owner's kennel record and transmits the player's ModData.
---@param player IsoPlayer|nil owner
---@param animal IsoAnimal|nil
function CD.kennelSnapshot(player, animal)
    if isClient() then return end
    if not player or not animal then return end
    local d = CD.data(animal)
    local token = d.companionToken
    if token == nil then return end
    if not d.uid then
        CD.ensureUid(animal)
        CD.transmit(animal)
    end
    local pd = CD.playerData(player)
    pd.kennel = pd.kennel or {}
    local snap = pd.kennel[token] or {}
    for _, f in ipairs(KENNEL_FIELDS) do
        if d[f] ~= nil then
            snap[f] = CD.deepCopy(d[f])
        end
    end
    snap.bag = CD.deepCopy(d.bag)
    snap.isPup = d.isPup
    snap.growthPaused = d.growthPaused
    snap.autoProtect = d.autoProtect
    snap.huntMode = d.huntMode
    snap.breedingOff = d.breedingOff
    snap.careMode = d.careMode
    snap.careX, snap.careY, snap.careZ = d.careX, d.careY, d.careZ
    for _, f in ipairs(VOLATILE_FIELDS) do snap[f] = d[f] end
    if snap.sex == nil then
        local sx = CD.animalSex(animal)
        if sx == "male" or sx == "female" then
            snap.sex = sx
        end
    end
    snap.companionToken = token
    snap.fp = CD.kennelFingerprint(animal)
    snap.animalId = animal:getAnimalID()
    snap.savedAtMin = CD.worldMinutes()
    snap.x, snap.y, snap.z = math.floor(animal:getX()), math.floor(animal:getY()), math.floor(animal:getZ())
    snap.age = animal:getAge()
    snap.hunger = CD.getHunger(animal)
    snap.thirst = animal:getThirst()
    snap.hp = animal:getHealth()
    snap.lost = nil
    snap.skills = snap.skills or {}
    if type(d.skills) == "table" then
        CD.mergeSkillsMax(snap.skills, d.skills)
    end
    pd.kennel[token] = snap
    if CD.kennelGlobalPut then
        CD.kennelGlobalPut(CD.ownerKey(player), token, snap)
    end
    player:transmitModData()
end

---kennelSnapshot at most once every KENNEL_MIRROR_MIN game minutes.
---@param player IsoPlayer owner
---@param animal IsoAnimal
function CD.kennelMirror(player, animal)
    if isClient() then return end
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    if d.lastKennelMin and (now - d.lastKennelMin) < CD.KENNEL_MIRROR_MIN then return end
    d.lastKennelMin = now
    CD.kennelSnapshot(player, animal)
end

---Whether a reaped clone's token may leave pd.companions: never the active token, the keeper's or one with a kennel record.
---@param pd table the player's CompanionDogs mod data
---@param vt number|nil token of the clone being reaped
---@param keeperTok number|nil token of the copy that stays
---@return boolean
---@nodiscard
function CD.cloneSlotShouldClear(pd, vt, keeperTok)
    if vt == nil or type(pd.companions) ~= "table" then return false end
    if vt == pd.token then return false end
    if keeperTok ~= nil and vt == keeperTok then return false end
    if type(pd.kennel) == "table" and pd.kennel[vt] ~= nil then return false end
    return true
end

---Server side: creates the kennel record from a data table, only when the token has none yet.
---@param player IsoPlayer|nil
---@param tok number|nil companion token
---@param data table|nil companion ModData or a stored copy of it
---@return boolean created
function CD.kennelSeedFromData(player, tok, data)
    if isClient() then return false end
    if not player or tok == nil or type(data) ~= "table" then return false end
    local pd = CD.playerData(player)
    if type(pd.kennel) == "table" and type(pd.kennel[tok]) == "table" then return false end
    pd.kennel = pd.kennel or {}
    local snap = {}
    for _, f in ipairs(KENNEL_FIELDS) do snap[f] = CD.deepCopy(data[f]) end
    for _, f in ipairs(VOLATILE_FIELDS) do snap[f] = data[f] end
    snap.companionToken = tok
    snap.savedAtMin = CD.worldMinutes()
    snap.skills = CD.deepCopy(data.skills) or {}
    pd.kennel[tok] = snap
    if CD.kennelGlobalPut then
        CD.kennelGlobalPut(CD.ownerKey(player), tok, snap)
    end
    return true
end

---Flags the kennel record as lost and, for the active token, clears the active dog.
---@param player IsoPlayer|nil
---@param token number|nil companion token
---@return boolean|nil marked true when flagged now, false when already lost, nil without a record
function CD.markCompanionLost(player, token)
    if not player or token == nil then return nil end
    local pd = CD.playerData(player)
    local snap = pd.kennel and pd.kennel[token]
    if not snap then return nil end
    if snap.lost == true then return false end
    snap.lost = true
    if CD.kennelGlobalPut then
        CD.kennelGlobalPut(CD.ownerKey(player), token, snap)
    end
    if token == pd.token then
        pd.token = nil
        pd.name = nil
    end
    player:transmitModData()
    return true
end

---Server side: refills from the kennel record the fields the dog lacks, never overwriting one, and merges the skills.
---@param player IsoPlayer|nil owner
---@param animal IsoAnimal|nil
---@return boolean changed
function CD.restoreFromKennel(player, animal)
    if isClient() then return false end
    if not player or not animal then return false end
    local d = CD.data(animal)
    local token = d.companionToken
    if token == nil then return false end
    local pd = CD.playerData(player)
    local snap = pd.kennel and pd.kennel[token]
    if not snap then return false end
    local changed = false
    for _, f in ipairs(KENNEL_FIELDS) do
        if d[f] == nil and snap[f] ~= nil then
            d[f] = CD.deepCopy(snap[f])
            changed = true
        end
    end
    if type(snap.skills) == "table" then
        d.skills = d.skills or {}
        CD.mergeSkillsMax(d.skills, snap.skills)
        changed = true
    end
    return changed
end

---Removes the token's kennel record from the player and from the world store.
---@param player IsoPlayer|nil
---@param token number|nil companion token
function CD.clearKennel(player, token)
    if not player or token == nil then return end
    local pd = CD.playerData(player)
    if type(pd.kennel) == "table" then
        pd.kennel[token] = nil
    end
    if CD.kennelGlobalDrop then
        CD.kennelGlobalDrop(CD.ownerKey(player), token)
    end
end

local function allocCompanionToken(player, d)
    local pd = CD.playerData(player)
    local m = pd.seq or 0
    if type(pd.companions) == "table" then
        for k in pairs(pd.companions) do if k > m then m = k end end
    end
    pd.seq = m + 1
    d.companionToken = pd.seq
    pd.companions = pd.companions or {}
    pd.companions[d.companionToken] = true
    return pd
end

---Bonds the stray to the player as the new active dog: tame, following, invincible, with skills and genes rolled.
---@param animal IsoAnimal
---@param player IsoPlayer
function CD.makeCompanion(animal, player)
    CD.regInvalidate()
    local d = CD.data(animal)
    d.companion = true
    d.trust = CD.TAMED_LOYALTY
    d.ownerId = nil
    d.ownerName = player:getUsername()
    d.ownerKey = CD.ownerKey(player)
    d.state = CD.STATE_FOLLOW
    d.autoProtect = true
    d.maxHealth = animal:getHealth()
    CD.initSkills(animal)
    CD.rollBreedGenes(animal)
    d.lineage = d.lineage or { [CD.getBreed(animal)] = 1.0 }

    local pd = allocCompanionToken(player, d)
    CD.setActiveDog(pd, d.companionToken, d.name)

    animal:setWild(false)
    local stats = animal:getStats()
    stats:set(CharacterStat.HUNGER, 0)
    stats:set(CharacterStat.THIRST, 0)
    d.stress = 0
    d.combatStress = 0
    animal:setDebugStress(0)
    animal:setIsInvincible(true)
    CD.calmAcceptance(animal, player)
    CD.kennelSnapshot(player, animal)
end

---Bonds a newborn pup to the player, staying put, with its parentage taken from info.
---@param animal IsoAnimal
---@param player IsoPlayer
---@param info table sex, breed, genes, lineage, generation and each parent's uid, name and breed
function CD.makePuppy(animal, player, info)
    CD.regInvalidate()
    local d = CD.data(animal)
    d.companion = true
    d.ownerId = nil
    d.ownerName = player:getUsername()
    d.ownerKey = CD.ownerKey(player)
    d.state = CD.STATE_STAY
    d.maxHealth = animal:getHealth()
    d.trust = CD.PUPPY_BORN_LOYALTY
    d.isPup = true
    d.bornMin = CD.worldMinutes()
    d.sex = info.sex
    d.breed = info.breed
    d.genes = info.genes
    d.lineage = info.lineage
    d.generation = info.generation
    d.motherUid = info.motherUid
    d.fatherUid = info.fatherUid
    d.motherName = info.motherName
    d.fatherName = info.fatherName
    d.motherBreed = info.motherBreed
    d.fatherBreed = info.fatherBreed
    CD.ensureUid(animal)
    CD.initSkills(animal)

    allocCompanionToken(player, d)

    animal:setWild(false)
    d.stress = 0
    d.combatStress = 0
    local stats = animal:getStats()
    stats:set(CharacterStat.HUNGER, 0)
    stats:set(CharacterStat.THIRST, 0)
    animal:setIsInvincible(true)
    CD.kennelSnapshot(player, animal)
end

---Hands another owner's companion over to the player; it becomes the active dog only when the player has none.
---@param animal IsoAnimal
---@param player IsoPlayer
function CD.adoptOrphan(animal, player)
    CD.regInvalidate()
    local d = CD.data(animal)
    d.companion = true
    d.ownerId = nil
    d.ownerName = player:getUsername()
    d.ownerKey = CD.ownerKey(player)

    local pd = allocCompanionToken(player, d)

    if pd.token == nil then
        CD.setActiveDog(pd, d.companionToken, d.name)
        d.state = CD.STATE_FOLLOW
    else
        d.state = CD.STATE_STAY
    end

    animal:setWild(false)
    animal:setIsInvincible(true)
    CD.transmit(animal)
    CD.kennelSnapshot(player, animal)
    player:transmitModData()
end

---Turns the companion back into a stray: drops the bag and clears the bond and every task field.
---@param animal IsoAnimal
function CD.demote(animal)
    CD.spillBag(animal)
    CD.regInvalidate()
    local d = CD.data(animal)
    d.companion = false
    d.ownerId = nil
    d.ownerName = nil
    d.ownerKey = nil
    d.companionToken = nil
    d.state = nil
    d.inCombat = nil
    d.retreating = nil
    d.recallUntilMin = nil
    d.attackUntilMin = nil
    d.attackArmed = nil
    d.standDown = nil
    d.alertTier = nil
    d.mounted = nil
    d.gunHungerSave = nil
    d.huntMode = nil
    CD.clearCareFields(d)
    d.hunting = nil
    d.huntCooling = nil
    d.huntTargetId = nil
    d.huntAlerted = nil
    d.huntSniffXp = nil
    d.woundedPrey = nil
    d.huntRetrieve = nil
    d.huntGoingSinceMin = nil
    d.huntRetryMin = nil
    d.huntDeerHeldSinceMin = nil
    d.huntDeerHeldNotified = nil
    d.forageSpot = nil
    d.foragePointSinceMin = nil
    d.forageGoingSinceMin = nil
    d.forageRetryMin = nil
    d.forageAlerted = nil
    d.forageScoutTarget = nil
    d.sniffed = nil
    d.sniffSpot = nil
    d.sniffMark = nil
    d.sniffMute = nil
    d.sniffDrive = nil
    d.sniffRetryMin = nil
    d.sniffAlertUntilMin = nil
    d.sniffing = nil
    d.sniffingUntilMin = nil
    d.lastSniffScanMin = nil
    d.sniffLastX, d.sniffLastY = nil, nil
    d.fetched = nil
    d.fetchTask = nil
    d.fetchDrive = nil
    d.fetchTagUntilMin = nil
    d.trickFetchUntilMin = nil
    animal:setWild(true)
    animal:setShootable(true)
    animal:setIsInvincible(false)
    animal:setInvulnerable(false)
    CD.releaseFallFlag(animal)
    animal:setCollidable(true)
    animal:setInvisible(false, true)
    local oid = animal:getOnlineID()
    for _, pose in ipairs(CD.restPoses(animal)) do
        CD.emit("animvar", { id = oid, var = pose.var, on = false }, animal)
    end
    CD.emit("animvar", { id = oid, var = CD.EAT_ANIM_VAR, on = false }, animal)
    CD.emit("animvar", { id = oid, var = CD.SNIFF_ANIM_VAR, on = false }, animal)
    CD.transmit(animal)
end

---Calls fn for every local player, split screen included.
---@param fn fun(p: IsoPlayer)
function CD.eachLocalPlayer(fn)
    local n = getNumActivePlayers() or 1
    for i = 0, n - 1 do
        local p = getSpecificPlayer(i)
        if p then
            fn(p)
        end
    end
end

-- Alguem nesta maquina esta perto o bastante pra ouvir? Em tela dividida os dois players contam.
-- O rolloff inverso do FMOD nunca chega a zero: passado o distanceMax o som para de atenuar e fica
-- num piso audivel pra sempre. Entao o corte por distancia tem que ser aqui, antes de tocar.
---@param a IsoAnimal|nil
---@param radius number tiles
---@return boolean
---@nodiscard
function CD.nearAnyLocalPlayer(a, radius)
    if not a then return false end
    local n = getNumActivePlayers() or 1
    for i = 0, n - 1 do
        local p = getSpecificPlayer(i)
        if p and CD.dist2D(a, p) <= radius then return true end
    end
    return false
end

local ownerIndex, ownerIndexMs, ownerIndexCount = {}, 0, -1

local function ownerIndexNow()
    local now = getTimestampMs()
    if ownerIndexCount >= 0 and (now - ownerIndexMs) < CD.OWNER_INDEX_TTL_MS then return ownerIndex end
    local players = getOnlinePlayers()
    local np = players:size()
    ownerIndexMs, ownerIndexCount = now, np
    for k in pairs(ownerIndex) do ownerIndex[k] = nil end
    for i = 0, np - 1 do
        local p = players:get(i)
        if p then
            local u = p:getUsername()
            if u and u ~= "" and ownerIndex[u] == nil then
                ownerIndex[u] = p
            end
        end
    end
    CD.perfCount("iter.ownerindex", np)
    return ownerIndex
end

---@param animal IsoAnimal
---@param d table|nil the already resolved CD.data(animal), spares one Java call per caller that has it
---@return IsoPlayer|nil owner nil while the owner is offline
function CD.getOwnerPlayer(animal, d)
    if CD._perfLv and CD._perfLv > 0 then
        CD._perfCnt["call.getOwnerPlayer"] = (CD._perfCnt["call.getOwnerPlayer"] or 0) + 1
    end
    if isClient() or isServer() then
        local idx = ownerIndexNow()
        if not idx then return nil end
        d = d or CD.data(animal)
        local key = d.ownerKey
        if key ~= nil and key ~= "" then return idx[key] end
        local name = d.ownerName
        if name ~= nil and name ~= "" then return idx[name] end
        return nil
    end
    if (getNumActivePlayers() or 1) <= 1 then return getPlayer() end
    local found = nil
    CD.eachLocalPlayer(function(p)
        if found == nil and CD.isOwnedBy(animal, p) then
            found = p
        end
    end)
    return found
end

---Horizontal distance in tiles; the floor is ignored.
---@param a IsoObject
---@param b IsoObject
---@return number
---@nodiscard
function CD.dist2D(a, b)
    local dx = a:getX() - b:getX()
    local dy = a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end

---Inside a vehicle.
---@param player IsoPlayer|nil
---@return boolean
---@nodiscard
function CD.isMounted(player)
    if not player then return false end
    if player:getVehicle() ~= nil then return true end
    return player:isSeatedInVehicle()
end

---World age in game minutes.
---@return number
---@nodiscard
function CD.worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

CD.actMs = CD.actMs or {}

---Real-time stamps (ms) of the animal by key, kept by online id for the session and created on first call.
---@param animal IsoAnimal
---@return table<string, number>
CD.act = function(animal)
    local id = animal:getOnlineID()
    local t = CD.actMs[id]
    if not t then
        t = {}
        CD.actMs[id] = t
    end
    return t
end

---True while key is still cooling down; otherwise stamps it now and returns false.
---@param animal IsoAnimal
---@param key string
---@param ms number cooldown in real-time ms
---@return boolean cooling
CD.cooldown = function(animal, key, ms)
    local t = CD.act(animal)
    local now = getTimestampMs()
    if t[key] and (now - t[key]) < ms then return true end
    t[key] = now
    return false
end

---@param animal IsoAnimal
---@param key string
---@param ms number real-time ms
---@return boolean true when key was never stamped or ms have passed since
---@nodiscard
CD.cooledDown = function(animal, key, ms)
    local t = CD.act(animal)[key]
    return (not t) or (getTimestampMs() - t) >= ms
end

---Marks key as used now, for cooledDown.
---@param animal IsoAnimal
---@param key string
CD.stamp = function(animal, key)
    CD.act(animal)[key] = getTimestampMs()
end

-- Nunca z:knockDown() cru: ele grava playerAttackPosition null e hitForce 1.0, nenhum node do
-- staggerback casa com esse par e o zumbi congela na pose. Regravar a direcao FRONT logo depois.
---@param z IsoZombie|nil
---@return boolean knocked false when the zombie is dead, on the floor or already reacting to a hit
function CD.applyKnockdown(z)
    if not z then return false end
    local can = not z:isDead() and z:getHealth() > 0 and not z:isOnFloor()
    if not can then return false end
    local hr = z:getHitReaction()
    local busy = hr ~= nil and hr ~= ""
    if busy then return false end
    z:knockDown(false)
    z:setPlayerAttackPosition("FRONT")
    return true
end
