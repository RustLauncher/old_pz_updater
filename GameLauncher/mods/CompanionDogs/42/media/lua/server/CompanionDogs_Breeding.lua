CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---Pups in a litter: the breed's litter range, both ends included; 1..2 when the breed declares none.
---@param dam IsoAnimal
---@return integer
---@nodiscard
function CD.rollLitterSize(dam)
    local r = CD.getBreedDef(dam).litter or { 1, 2 }
    local lo, hi = r[1], r[2]
    if hi < lo then
        hi = lo
    end
    return lo + ZombRand(0, hi - lo + 1)
end

---Server side; pups never conceive. Stamps the pregnancy and the sire's genes, lineage and name on the dam.
---@param dam IsoAnimal|nil
---@param sire IsoAnimal|nil
---@param gestMinutes number|nil game minutes to the birth; nil uses the sandbox gestation
function CD.conceive(dam, sire, gestMinutes)
    if isClient() then return end
    if not dam or not sire then return end
    if CD.isPuppy(dam) or CD.isPuppy(sire) then return end
    local d = CD.data(dam)
    local sd = CD.data(sire)
    d.pregnant = true
    d.gestEndMin = CD.worldMinutes() + (gestMinutes or CD.gestationMinutes())
    d.litterSize = CD.rollLitterSize(dam)
    d.sireGenes = CD.deepCopy(sd.genes)
    d.sireLineage = CD.deepCopy(CD.getLineage(sire))
    d.sireUid = CD.ensureUid(sire)
    d.sireName = sd.name
    d.sireBreed = CD.getBreed(sire)
    CD.transmit(dam)
end

---@param uid string|nil
---@return IsoAnimal|nil dog nil when no loaded dog carries the uid
---@nodiscard
function CD.findDogByUid(uid)
    if not uid then return nil end
    local found = nil
    CD.regEach(CD.regDogs(), function(a)
        if found == nil and CD.data(a).uid == uid then
            found = a
        end
    end)
    return found
end

---Server side: the dam starts walking to the sire; driveBreedingApproach conceives on contact.
---@param dam IsoAnimal|nil
---@param sire IsoAnimal|nil
function CD.startBreedingApproach(dam, sire)
    if isClient() then return end
    if not dam or not sire then return end
    if CD.isPuppy(dam) or CD.isPuppy(sire) then return end
    local d = CD.data(dam)
    d.breedTarget = CD.ensureUid(sire)
    d.breedTargetId = sire:getOnlineID()
    d.breedSinceMin = CD.worldMinutes()
    d.breedPathTile = nil
    local b = dam:getBehavior()
    if b then
        b:setBlockMovement(false)
    end
    CD.transmit(dam)
end

---Server side: cancels the walk to the sire.
---@param dam IsoAnimal
function CD.abortBreeding(dam)
    if isClient() then return end
    local d = CD.data(dam)
    d.breedTarget = nil
    d.breedTargetId = nil
    d.breedSinceMin = nil
    d.breedPathTile = nil
    CD.transmit(dam)
end

---One step of the walk: gives up on timeout or on any broken rule, conceives within BREED_RANGE.
---@param female IsoAnimal
---@param now number world minutes
function CD.driveBreedingApproach(female, now)
    local d = CD.data(female)
    if d.breedSinceMin and (now - d.breedSinceMin) > CD.BREED_APPROACH_TIMEOUT_MIN then
        CD.abortBreeding(female)
        return
    end
    local sire = (d.breedTargetId and getAnimal(d.breedTargetId)) or CD.findDogByUid(d.breedTarget)
    if not sire or not CD.isDog(sire) or sire:isDead() then
        CD.abortBreeding(female)
        return
    end
    if d.breedingOff or CD.data(sire).breedingOff then
        CD.abortBreeding(female)
        return
    end
    if not (CD.breedCanBreed(female) and CD.breedCanBreed(sire)) then
        CD.abortBreeding(female)
        return
    end
    if not CD.sameSpecies(female, sire) then
        CD.abortBreeding(female)
        return
    end
    if math.floor(sire:getZ()) ~= math.floor(female:getZ()) or CD.dist2D(female, sire) > CD.BREED_LEASH then
        CD.abortBreeding(female)
        return
    end
    if CD.dist2D(female, sire) <= CD.BREED_RANGE then
        female:faceThisObject(sire)
        CD.conceive(female, sire, nil)
        d.breedTarget = nil
        d.breedTargetId = nil
        d.breedSinceMin = nil
        d.breedPathTile = nil
        CD.transmit(female)
        local owner = CD.getOwnerPlayer(female)
        if owner then
            CD.notifyOwner(owner, "bred", { name = d.name })
        end
        return
    end
    local b = female:getBehavior()
    if b then
        b:setBlockMovement(false)
    end
    local tile = math.floor(sire:getX()) .. "," .. math.floor(sire:getY())
    if d.breedPathTile ~= tile then
        d.breedPathTile = tile
        female:faceThisObject(sire)
        CD.pathStatEmit(female, "cruzamento")
        female:pathToLocation(sire:getX(), sire:getY(), sire:getZ())
        female:setVariable("bPathfind", true)
    end
end

---Server side: drives every companion that is walking to a mate.
function CD.tickBreedingApproach()
    if isClient() then return end
    if not CD.breedingEnabled() then return end
    local now = CD.worldMinutes()
    CD.regEach(CD.regCompanions(), function(a)
        if CD.data(a).breedTarget then
            CD.driveBreedingApproach(a, now)
        end
    end)
end

---Server side: births the litter beside the dam, capped by the owner's free companion slots, and ends the pregnancy.
---@param dam IsoAnimal|nil
---@param owner IsoPlayer|nil
function CD.whelpLitter(dam, owner)
    if isClient() then return end
    if not dam or not owner then return end
    local d = CD.data(dam)
    if not d.pregnant then return end

    local lim = CD.maxCompanions()
    local n = d.litterSize or 1
    if lim > 0 then
        local free = lim - CD.companionCount(owner)
        if free < 0 then
            free = 0
        end
        if n > free then
            n = free
        end
    end

    local born = 0
    if n > 0 then
        local damGenes = d.genes
        local damLineage = CD.getLineage(dam)
        local sireGenes = d.sireGenes
        local sireLineage = d.sireLineage or { [d.sireBreed or CD.DEFAULT_BREED] = 1.0 }
        local damX, damY, damZ = dam:getX(), dam:getY(), dam:getZ()
        local damName = d.name
        local damUid = CD.ensureUid(dam)
        local damBreed = CD.getBreed(dam)
        local gen = (d.generation or 1) + 1

        for _ = 1, n do
            local lineage = CD.blendLineage(damLineage, sireLineage)
            local domKey = CD.lineageRoll(lineage)
            local sex = CD.rollBreedSex(domKey)
            local pupType = CD.breedAnimalType(domKey, "pup")
            local pup = CD.spawnDog(damX, damY, damZ, pupType, CD.breedEngineName(domKey))
            if pup then
                -- setAgeDebug e nao setAge: IsoAnimal nao tem setAge, so o AnimalData tem.
                pup:setAgeDebug(0)
                local dt = pup:getData()
                if dt then
                    dt:setSizeForced(CD.puppySize(pup))
                end
                CD.makePuppy(pup, owner, {
                    genes        = CD.blendGenes(damGenes, sireGenes, lineage),
                    lineage      = lineage,
                    breed        = domKey,
                    sex          = sex,
                    generation   = gen,
                    motherUid    = damUid,
                    fatherUid    = d.sireUid,
                    motherName   = damName,
                    fatherName   = d.sireName,
                    motherBreed  = damBreed,
                    fatherBreed  = d.sireBreed,
                })
                CD.transmit(pup)
                born = born + 1
            end
        end
    end

    d.pregnant = nil
    d.gestEndMin = nil
    d.litterSize = nil
    d.sireGenes = nil
    d.sireLineage = nil
    d.sireUid = nil
    d.sireName = nil
    d.sireBreed = nil
    d.lastWhelpMin = CD.worldMinutes()
    CD.transmit(dam)
    if owner then
        owner:transmitModData()
    end
    CD.notifyOwner(owner, "whelped", { count = born, name = d.name })
end

---Server side: whelps every pregnant companion whose term is due and whose owner is online.
function CD.tickGestation()
    if isClient() then return end
    if not CD.breedingEnabled() then return end
    local now = CD.worldMinutes()
    local due
    CD.regEach(CD.regCompanions(), function(a)
        local d = CD.data(a)
        if d.pregnant and d.gestEndMin and now >= d.gestEndMin then
            due = due or {}
            due[#due + 1] = a
        end
    end)
    if not due then return end
    for _, dam in ipairs(due) do
        local owner = CD.getOwnerPlayer(dam)
        if owner then
            CD.whelpLitter(dam, owner)
        end
    end
end
