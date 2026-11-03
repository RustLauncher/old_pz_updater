CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---Record to respawn the dog from: type, sex, age, health, needs and its ModData table itself, not a copy.
---@param animal IsoAnimal
---@return table record { type, female, age, hp, hunger, thirst, lastNeedMin, data }
---@nodiscard
function CD.buildStashRecord(animal)
    return {
        type = animal:getAnimalType(),
        female = animal:isFemale(),
        age = animal:getAge(),
        hp = animal:getHealth(),
        hunger = CD.getHunger(animal),
        thirst = animal:getThirst(),
        lastNeedMin = CD.worldMinutes(),
        data = CD.data(animal),
    }
end

---Keeps the dog as the owner's vehicle stash and mirrors it in the kennel.
---@param animal IsoAnimal
---@param owner IsoPlayer|nil
function CD.writeStashRecord(animal, owner)
    if not owner then return end
    CD.playerData(owner).stash = CD.buildStashRecord(animal)
    CD.kennelSnapshot(owner, animal)
    owner:transmitModData()
end

---@param owner IsoPlayer|nil
function CD.clearStashRecord(owner)
    if not owner then return end
    local pd = CD.playerData(owner)
    if pd.stash then
        pd.stash = nil
        owner:transmitModData()
    end
end

local function respawnCompanion(oldDog, owner, rec, atSq)
    local sq = atSq or (owner and owner:getCurrentSquare())
    if not sq then return nil end
    local atype = (rec and rec.type) or "dogmale"
    if oldDog then
        atype = oldDog:getAnimalType() or atype
    end
    local fbreed = (oldDog and CD.data(oldDog).breed) or (rec and rec.data and rec.data.breed) or CD.DEFAULT_BREED
    local dog = CD.spawnDog(sq:getX(), sq:getY(), sq:getZ(), atype, CD.breedEngineName(fbreed))
    if not dog then return nil end
    if oldDog then
        dog:copyFrom(oldDog)
    elseif rec then
        if rec.female ~= nil then
            dog:setFemale(rec.female)
        end
        if rec.age then
            dog:setAgeDebug(rec.age)
        end
        if rec.hp then
            dog:setHealth(rec.hp)
        end
    end
    local src = (oldDog and CD.data(oldDog)) or (rec and rec.data)
    if src then
        dog:getModData().CompanionDogs = src
    end
    if owner then
        CD.restoreFromKennel(owner, dog)
    end
    if CD.hasBag(dog) then
        CD.applyBagVisual(dog)
    end
    if rec then
        if rec.hunger ~= nil then
            CD.setNeed(dog, "hunger", rec.hunger)
        end
        if rec.thirst ~= nil then
            CD.setNeed(dog, "thirst", rec.thirst)
        end
        if rec.hp ~= nil then
            dog:setHealth(rec.hp)
        end
    end
    local nd = CD.data(dog)
    nd.mounted = nil
    nd.stashed = nil
    nd.lastInvisMin = nil
    nd.followPathTile = nil
    nd.followPathMs = nil
    nd.followStallMs = nil
    nd.followLastX = nil
    nd.followLastY = nil
    nd.lastUpkeepMin = CD.worldMinutes()
    nd.lastKennelMin = nil
    nd.ownerId = nil
    if owner then
        CD.playerData(owner).offlineDebtMin = 0
    end
    dog:setShootable(false)
    dog:setCollidable(true)
    dog:setIsInvincible(true)
    if CD.getState(dog) == CD.STATE_FOLLOW then
        CD.followMaintainDogs[dog:getOnlineID()] = dog
        CD.letMove(dog)
    end
    if oldDog and isServer() then
        -- Reforco: se o despawn do cao velho se perdeu, o client ganha um segundo aviso junto com o novo.
        local oldId = oldDog:getOnlineID()
        if oldId ~= dog:getOnlineID() then
            sendServerCommand(CD.MODULE, "despawn", { id = oldId })
        end
    end
    if CD.DEBUG_DESPAWN then
        CD.log(string.format("[CD-DESPAWN] srv respawn novo=%s velho=%s pos(%.1f,%.1f)", tostring(dog:getOnlineID()),
            tostring(oldDog and oldDog:getOnlineID()), dog:getX(), dog:getY()))
    end
    CD.transmit(dog)
    return dog
end
CD.respawnCompanion = respawnCompanion

local function maturePup(pup)
    local owner = CD.getOwnerPlayer(pup)
    if not owner then return end
    local d = CD.data(pup)
    local breed = CD.getBreed(pup)
    local sex = d.sex or CD.animalSex(pup) or "male"
    if sex == "pup" then
        sex = "male"
    end
    local adultType = CD.breedAnimalType(breed, sex)
    local px, py, pz = pup:getX(), pup:getY(), pup:getZ()
    local adult = CD.spawnDog(px, py, pz, adultType, CD.breedEngineName(breed))
    if not adult then return end
    adult:setAgeDebug(CD.maturityDays())
    local ad = CD.deepCopy(d)
    ad.isPup = nil
    ad.growthPaused = nil
    adult:getModData().CompanionDogs = ad
    local nd = CD.data(adult)
    local pupMax = nd.maxHealth
    nd.maxHealth = adult:getHealth()
    -- Filhote e adulto sao animalType diferentes, com maxHealth diferentes: transporta a FRACAO.
    -- Tem que ficar antes do setIsInvincible abaixo, senao o setHealth de reducao vira no-op.
    if pupMax and pupMax > 0 then
        local frac = pup:getHealth() / pupMax
        if frac > 1 then
            frac = 1
        end
        if frac > 0 then
            adult:setHealth(nd.maxHealth * frac)
        end
    end
    nd.lastUpkeepMin = CD.worldMinutes()
    nd.ownerId = nil
    adult:setShootable(false)
    adult:setIsInvincible(true)
    adult:setWild(false)
    if CD.hasBag(adult) then
        CD.applyBagVisual(adult)
    end
    if CD.getState(adult) == CD.STATE_FOLLOW then
        CD.followMaintainDogs[adult:getOnlineID()] = adult
    end
    CD.bumpCanonical(owner, adult)
    CD.transmit(adult)
    owner:transmitModData()
    local pupId = pup:getOnlineID()
    CD.reapDogState(pupId)
    CD.despawn(pup)
    CD.notifyOwner(owner, "matured", { name = nd.name })
end

local function tickMaturation()
    if isClient() then return end
    if not CD.breedingEnabled() then return end
    local now = CD.worldMinutes()
    local mins = CD.maturityMinutes()
    local due
    CD.regEach(CD.regCompanions(), function(a)
        if CD.isPuppy(a) then
            local d = CD.data(a)
            if not d.growthPaused and now >= (d.bornMin or 0) + mins then
                due = due or {}
                due[#due + 1] = a
            end
        end
    end)
    if not due then return end
    for _, pup in ipairs(due) do maturePup(pup) end
end

local function stashMounted(animal, owner, d)
    if d.stashed then return end
    d.stashed = true
    CD.writeStashRecord(animal, owner)
    animal:stopAllMovementNow()
    CD.despawn(animal)
end

local function mountRefresh(animal, owner, d)
    stashMounted(animal, owner, d)
end

local function mountClear(animal, d)
    local was = d.mounted
    d.mounted = nil
    local owner = CD.getOwnerPlayer(animal)
    local done = true
    if owner then
        if respawnCompanion(animal, owner, CD.playerData(owner).stash) then
            d.stashed = nil
            CD.clearStashRecord(owner)
        else
            done = false
        end
    end
    if was then
        CD.transmit(animal)
    end
    return done
end
CD.mountRefresh, CD.mountClear, CD.tickMaturation = mountRefresh, mountClear, tickMaturation
