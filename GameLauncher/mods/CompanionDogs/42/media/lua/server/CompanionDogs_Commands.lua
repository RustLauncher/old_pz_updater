CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.Server = CD.Server or {}

local function resolveAnimal(args)
    if args.__animal then return args.__animal end
    if args.id then return getAnimal(tonumber(args.id)) end
    return nil
end

local function cdSpawnOne(atype, kind, x, y, z)
    if not CD.TYPES[atype] then return nil end
    local animal = CD.spawnDog(x, y, z, atype, CD.breedEngineName(kind))
    if animal then
        CD.setBreed(animal, kind)
        CD.transmit(animal)
    end
    return animal
end

---Admin debug: one dog of the breed at the tile.
---@param player IsoPlayer
---@param args table { kind, type, x, y, z }
CD.Server.spawn = function(player, args)
    if not CD.debugAllowed(player) then return end
    local kind = (args.kind and CD.BREEDS[args.kind]) and args.kind or CD.DEFAULT_BREED
    cdSpawnOne(args.type or "dogmale", kind, args.x, args.y, args.z)
end

---Admin: n dogs of random breeds around the tile, at most SPAWN_RANDOM_MAX.
---@param player IsoPlayer
---@param args table { x, y, z, n }
CD.Server.spawnrandom = function(player, args)
    if not CD.adminAllowed(player) then return end
    local order = CD.BREED_ORDER
    if not order or #order == 0 then return end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) then return end
    local n = math.min(math.max(tonumber(args.n) or 1, 1), CD.SPAWN_RANDOM_MAX)
    local made = 0
    for _ = 1, n do
        local kind = order[ZombRand(#order) + 1]
        local sex = CD.rollBreedSex(kind)
        -- espalha num quadrado de 5x5: sem isso os N animais disputam o mesmo square e a maioria
        -- cai no fallback de vizinho do spawnDog
        if cdSpawnOne(CD.breedAnimalType(kind, sex), kind, x + ZombRand(-2, 3), y + ZombRand(-2, 3), z) then
            made = made + 1
        end
    end
    CD.log("spawnrandom: " .. tostring(made) .. "/" .. tostring(n) .. " caes em " ..
          tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
end

-- Consome server-side: o SyncItemDelete emitido por um client comum faz o anticheat chutar.
local function cdConsumeFood(player, args)
    local id = tonumber(args.foodId)
    if not id then return true end
    local inv = player and player:getInventory()
    local food = inv and inv:getItemById(id)
    if not food then return false end
    if not instanceof(food, "Food") then return true end
    local frac = tonumber(args.partialFrac)
    if frac and frac > 0 and frac < 0.99 then
        food:multiplyFoodValues(1 - frac)
        food:syncItemFields()
    else
        food:setHungChange(0)
        food:UseAndSync()
    end
    return true
end

local function cdConsumeWater(player, args)
    local inv = player and player:getInventory()
    if not inv then return false end
    local id = args and tonumber(args.waterId)
    local water = id and inv:getItemById(id)
    if not (water and water:getFluidContainer()) then
        local list = inv:getAllWaterFluidSources(true)
        water = (list and list:size() > 0) and list:get(0) or nil
    end
    if not water then return false end
    local ok, tainted = false, false
    local fc = water:getFluidContainer()
    if fc and not fc:isEmpty() then
        tainted = fc:isPoisonous()
        fc:removeFluid(0.2, false)
        ok = true
    end
    water:syncItemFields()
    return ok, tainted
end

-- Cinco classes de item medico e cinco jeitos de gastar, mais a ferramenta que nao gasta (pinca).
-- Classe desconhecida devolve nil, senao qualquer item vira cura de graca. Item inteiro (emplastro,
-- tala, folha de babosa) so conta se for remedio da tabela do vet.
local function medicalKind(item)
    local def = CD.vetMedicineDef(item:getFullType())
    if def ~= nil and def.keep then return "keep" end
    if item:hasComponent(ComponentType.FluidContainer) then
        if item:getFluidContainer():getAmount() <= 0.15 then return nil end
        return "fluid"
    end
    if instanceof(item, "Food") then return "food" end
    if instanceof(item, "DrainableComboItem") then
        if item:getCurrentUsesFloat() <= 0 then return nil end
        return "use"
    end
    if item:isCanBandage() then return "use" end
    if def ~= nil then return "whole" end
    return nil
end

local function cdConsumeMedical(player, rawId)
    local id = tonumber(rawId)
    if not id then return false end
    local inv = player and player:getInventory()
    local item = inv and inv:getItemById(id)
    if not item then return false end
    local kind = medicalKind(item)
    if kind == "fluid" then
        item:getFluidContainer():removeFluid(0.15, false)
        item:syncItemFields()
    elseif kind == "food" then
        item:setHungChange(0)
        item:UseAndSync()
    elseif kind == "use" then
        item:UseAndSync()
    elseif kind == "whole" then
        local cont = item:getContainer() or inv
        if isServer() then
            sendRemoveItemFromContainer(cont, item)
        end
        cont:Remove(item)
    elseif kind ~= "keep" then
        return false
    end
    return true
end

local function setNeed(animal, kind, value)
    local stats = animal:getStats()
    if kind == "thirst" then
        stats:set(CharacterStat.THIRST, value)
    else
        local d = CD.data(animal)
        if d.gunHungerSave ~= nil then
            d.gunHungerSave = value
        end
        stats:set(CharacterStat.HUNGER, value)
    end
end

local function cdFeedIsToxic(player, args, breedKey)
    local id = tonumber(args.foodId)
    if not id or not player then return false end
    local food = player:getInventory():getItemById(id)
    return food ~= nil and CD.isBadDogFood(food, breedKey)
end

-- Lido antes do consumo: depois dele o item ja nao existe.
local function cdFeedSpoilage(player, args)
    local id = tonumber(args.foodId)
    if not id or not player then return nil end
    local food = player:getInventory():getItemById(id)
    if not food or not instanceof(food, "Food") then return nil end
    if food:isRotten() then return "rotten" end
    if not food:isFresh() then return "stale" end
    return nil
end

local function cdFeedProteinPoints(player, args, breedKey)
    local id = tonumber(args.foodId)
    if not id or not player then return 0 end
    local food = player:getInventory():getItemById(id)
    return food and CD.proteinPoints(food, breedKey) or 0
end

local function cdFeedProteinGroup(player, args, breedKey)
    local id = tonumber(args.foodId)
    if not id or not player then return nil end
    local food = player:getInventory():getItemById(id)
    return food and CD.vetProteinGroup(food, breedKey) or nil
end

local function cdCompanionCount(player)
    local c = CD.playerData(player).companions
    if type(c) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(c) do n = n + 1 end
    return n
end

---Rolls the skills and genes of a stray the first time a player opens its scan window.
---@param player IsoPlayer unused
---@param args table { id }
CD.Server.scanstray = function(player, args)
    local animal = resolveAnimal(args)
    if not (animal and CD.isDog(animal)) then return end
    if CD.isCompanion(animal) then return end
    local d = CD.data(animal)
    if d.genes then return end
    CD.initSkills(animal)
    CD.rollBreedGenes(animal)
    CD.transmit(animal)
end

---Hand feeding: a companion gets needs and loyalty back; a stray gains trust and is tamed at the threshold.
---@param player IsoPlayer
---@param args table { id, foodId, partialFrac, hunger, thirst }
CD.Server.feed = function(player, args)
    local animal = resolveAnimal(args)
    if animal and CD.isDog(animal) and CD.isCompanion(animal) and not CD.isOwnedBy(animal, player) then
        CD.notifyOwner(player, "notyourdog", { breed = CD.getBreed(animal) })
        return
    end
    local breedKey = animal and CD.getBreed(animal)
    local bad = cdFeedIsToxic(player, args, breedKey)
    local spoil = cdFeedSpoilage(player, args)
    local proteinPts = cdFeedProteinPoints(player, args, breedKey)
    local proteinGroup = cdFeedProteinGroup(player, args, breedKey)
    if not cdConsumeFood(player, args) then return end
    if not animal or not CD.isDog(animal) then return end

    CD.pulseEatAnim(animal, nil, "feed-na-mao")

    local raw = tonumber(args.hunger) or 0
    local red = (raw < 0) and math.min(-raw, 3.0) or 0
    local V = math.floor(red * 100 + 0.5)
    local trustGain = (V > 0) and (V * CD.feedTrustPerHunger()) or nil
    local rawT = tonumber(args.thirst) or 0
    local tCut = (rawT < 0) and math.min(-rawT, 1.0) or 0

    if CD.isCompanion(animal) then
        local d = CD.data(animal)
        local hungerCut = (red > 0) and red or CD.feedHungerRestore()
        setNeed(animal, "hunger", math.max(0, CD.getHunger(animal) - hungerCut))
        if tCut > 0 then
            setNeed(animal, "thirst", math.max(0, animal:getThirst() - tCut))
        end
        local cap = d.maxHealth or 1
        if not bad and not CD.blocksFeedBonus(animal) then
            animal:setHealth(math.min(cap, animal:getHealth() + CD.feedHealthBonus()))
        end
        if bad then
            local sev = CD.toxicSeverity(animal)
            CD.setLoyalty(animal, math.max(0, CD.loyalty(animal) - CD.TOXIC_LOYALTY_PENALTY * sev))
            CD.addCombatStress(animal, CD.TOXIC_STRESS * sev)
            d.sickUntilMin = CD.worldMinutes() + CD.TOXIC_SICK_MIN * sev
            CD.notifyOwner(player, "sick", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        else
            CD.setLoyalty(animal, math.min(CD.TRUST_MAX, CD.loyalty(animal) + (trustGain or CD.FEED_LOYALTY_GAIN)))
            CD.addCombatStress(animal, -0.4)
            if proteinPts > 0 then
                CD.markProteinMeal(d, proteinPts)
            end
            d.lastWarn = nil
            CD.notifyOwner(player, "fed", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
            CD.vetRollFoodAllergy(animal, proteinGroup)
            if spoil then
                CD.vetRollSpoiledFood(animal, player, spoil)
            end
        end
        CD.transmit(animal)
        return
    end

    if bad then
        CD.setTrust(animal, math.max(0, CD.getTrust(animal) - CD.TOXIC_TRUST_PENALTY))
        CD.notifyOwner(player, "sick", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        CD.transmit(animal)
        return
    end

    CD.setTrust(animal, CD.getTrust(animal) + (trustGain or CD.feedTrustGain()))

    if CD.getTrust(animal) >= CD.tameThreshold() then
        local lim = CD.maxCompanions()
        if lim > 0 and cdCompanionCount(player) >= lim then
            CD.notifyOwner(player, "limitreached", { max = lim })
            CD.transmit(animal)
            return
        end
        local pd = CD.playerData(player)
        if pd.token ~= nil and not CD.hasRecoverableCompanion(player) then
            pd.token = nil
            pd.name = nil
            pd.stash = nil
            player:transmitModData()
        end
        local prev = CD.getCompanionAnimal(player)
        CD.makeCompanion(animal, player)
        if prev and prev ~= animal then
            CD.setState(prev, CD.STATE_STAY)
            CD.transmit(prev)
        end
        player:transmitModData()
        local targs = { id = animal:getOnlineID(), breed = CD.getBreed(animal) }
        if not isServer() then
            targs.animal = animal
        end
        CD.notifyOwner(player, "tamed", targs)
    else
        CD.notifyOwner(player, "trust",
            { id = animal:getOnlineID(), trust = CD.getTrust(animal), max = CD.tameThreshold(), breed = CD.getBreed(animal) })
    end
    CD.transmit(animal)
end

---Admin debug: sets a need, stress, loyalty, health or one gene of the dog from a 0..1 value.
---@param player IsoPlayer
---@param args table { id, field, value }
CD.Server.debugset = function(player, args)
    if not CD.debugAllowed(player) then return end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    local v = tonumber(args.value)
    local field = args.field
    if v == nil or type(field) ~= "string" then return end
    v = math.max(0, math.min(1, v))
    local d = CD.data(animal)
    local gene = string.match(field, "^gene:(%w+)$")
    if gene then
        if not d.genes then
            CD.rollBreedGenes(animal)
        end
        d.genes = d.genes or {}
        d.genes[gene] = v
    elseif field == "hunger" or field == "thirst" then
        setNeed(animal, field, v)
    elseif field == "stress" then
        CD.addCombatStress(animal, v - CD.getStress(animal))
    elseif field == "loyalty" then
        CD.setLoyalty(animal, v * CD.TRUST_MAX)
    elseif field == "health" then
        animal:setIsInvincible(false)
        animal:setHealth(v * (d.maxHealth or 1))
        animal:setIsInvincible(true)
    else
        return
    end
    CD.transmit(animal)
end

---Admin debug: applies or clears one ailment, or cures them all.
---@param player IsoPlayer
---@param args table { id, action, ailment }
CD.Server.debughealth = function(player, args)
    if not CD.debugAllowed(player) then return end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    local action = args.action
    if action == "apply" then
        CD.vetDebugApply(animal, args.ailment)
    elseif action == "clear" then
        CD.vetDebugClear(animal, args.ailment)
    elseif action == "clearAll" then
        CD.vetClearAll(animal, CD.getOwnerPlayer(animal) or player)
        CD.notifyOwner(player, "debugmsg", { text = "Cured: " .. tostring(CD.data(animal).name or "dog") })
    end
end

---Admin debug: cures every ailment of the dog.
---@param player IsoPlayer
---@param args table { id }
CD.Server.vetclear = function(player, args)
    if not CD.debugAllowed(player) then return end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    CD.vetClearAll(animal, CD.getOwnerPlayer(animal) or player)
    CD.notifyOwner(player, "debugmsg", { text = "Cured: " .. tostring(CD.data(animal).name or "dog") })
end

---Admin debug: bumps or sets one skill, or every skill of the breed.
---@param player IsoPlayer
---@param args table { id, skill, bump, set }
CD.Server.debugskill = function(player, args)
    if not CD.debugAllowed(player) then return end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    local list = (args.skill == "all") and CD.skillsFor(animal) or { args.skill }
    for _, sk in ipairs(list) do
        if sk and CD.breedHasSkill(animal, sk) then
            local target
            if args.bump then target = CD.getSkillLevel(animal, sk) + 1
            elseif args.set ~= nil then target = tonumber(args.set) end
            if target then
                CD.setSkillLevel(animal, sk, target)
            end
        end
    end
end

---Hand watering from the given container, or from the first water source in the inventory.
---@param player IsoPlayer
---@param args table { id, waterId }
CD.Server.water = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    local drank, tainted = cdConsumeWater(player, args)
    if not drank then return end
    setNeed(animal, "thirst", math.max(0, animal:getThirst() - CD.waterThirstRestore()))
    if tainted then
        CD.vetRollWater(animal, CD.data(animal))
    end
    CD.pulseDrinkAnim(animal, nil, "water-na-mao")
    CD.setLoyalty(animal, math.min(CD.TRUST_MAX, CD.loyalty(animal) + CD.PET_LOYALTY_GAIN))
    CD.addCombatStress(animal, -0.2)
    local d = CD.data(animal)
    if d.lastWarn == "thirsty" then
        d.lastWarn = nil
    end
    CD.notifyOwner(player, "watered", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

---Moves the saddlebag item and its contents from the inventory onto the dog.
---@param player IsoPlayer
---@param args table { id, itemId }
CD.Server.equipsaddlebag = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    if CD.hasBag(animal) then
        CD.notifyOwner(player, "bagalready", {})
        return
    end
    local inv = player and player:getInventory()
    local item = inv and args.itemId and inv:getItemById(tonumber(args.itemId))
    if not item or not CD.isSaddlebagType(item:getFullType()) then return end
    local records = {}
    local inner = item.getInventory and item:getInventory() or nil
    if inner then
        local its = inner:getItems()
        for i = 0, its:size() - 1 do
            if CD.isLiveAnimalItem(its:get(i)) then
                CD.notifyOwner(player, "baglive", {})
                return
            end
        end
        records = CD.serializeBag(inner)
    end
    local cont = item:getContainer() or inv
    if isServer() then
        sendRemoveItemFromContainer(cont, item)
    end
    cont:Remove(item)
    CD.data(animal).bag = { equipped = true, cap = CD.bagCapacity(animal), items = records }
    CD.applyBagVisual(animal)
    CD.kennelSnapshot(player, animal)
    CD.transmit(animal)
    CD.notifyOwner(player, "bagequipped", { id = animal:getOnlineID(), name = CD.data(animal).name })
end

---Drops the saddlebag, with its contents, on the dog's tile.
---@param player IsoPlayer
---@param args table { id }
CD.Server.unequipsaddlebag = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    if not CD.hasBag(animal) then return end
    local d = CD.data(animal)
    local sq = animal:getCurrentSquare() or animal:getSquare()
    if not sq and player then
        sq = player:getCurrentSquare()
    end
    if sq then
        local bagItem = instanceItem(CD.SADDLEBAG_TYPE)
        if bagItem then
            CD.rehydrateBag(bagItem:getInventory(), d.bag.items)
            sq:AddWorldInventoryItem(bagItem, 0.5, 0.5, 0.0)
        end
    end
    d.bag = nil
    CD.kennelSnapshot(player, animal)
    CD.removeBagVisual(animal)
    CD.transmit(animal)
    CD.notifyOwner(player, "bagunequipped", { id = animal:getOnlineID(), name = d.name })
end

local function cdSendBagData(player, animal)
    local b = CD.data(animal).bag
    if not b or not b.equipped then return end
    CD.bagStampLegacy(b.items)
    b.cap = CD.bagCapacity(animal)
    CD.notifyOwner(player, "bagdata", { id = animal:getOnlineID(), cap = b.cap, items = b.items or {} })
end

---Sends the bag contents to the owner.
---@param player IsoPlayer
---@param args table { id }
CD.Server.bagopen = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    if not CD.hasBag(animal) then return end
    cdSendBagData(player, animal)
end

---Moves one item from the inventory into the dog's bag, within its capacity.
---@param player IsoPlayer
---@param args table { id, itemId }
CD.Server.bagput = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    if not CD.hasBag(animal) then return end
    local inv = player and player:getInventory()
    local item = inv and args.itemId and inv:getItemById(tonumber(args.itemId))
    if not item or CD.isSaddlebagType(item:getFullType()) then return end
    if instanceof(item, "AnimalInventoryItem") then return end
    local equipped = item:isEquipped()
    if equipped then return end
    local nested = false
    if instanceof(item, "InventoryContainer") then
        local its = item:getInventory():getItems()
        nested = its ~= nil and its:size() > 0
    end
    if nested then return end
    local d = CD.data(animal)
    if CD.bagWeight(d.bag.items or {}) + CD.itemWeight(item) > CD.bagCapacity(animal) then
        CD.notifyOwner(player, "bagfull", {})
        return
    end
    local cont = item:getContainer() or inv
    if isServer() then
        sendRemoveItemFromContainer(cont, item)
    end
    cont:Remove(item)
    CD.bagInsert(player, animal, item)
    cdSendBagData(player, animal)
end

---Moves one record out of the dog's bag into the inventory.
---@param player IsoPlayer
---@param args table { id, index } index into the bag record list, from 1
CD.Server.bagtake = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    if not CD.hasBag(animal) then return end
    local d = CD.data(animal)
    local idx = tonumber(args.index)
    if not idx or not d.bag.items or not d.bag.items[idx] then return end
    local rec = table.remove(d.bag.items, idx)
    local it = CD.bagItemFromRecord(rec)
    if it then
        local inv = player:getInventory()
        inv:AddItem(it)
        it:SynchSpawn()
    end
    CD.kennelSnapshot(player, animal)
    CD.transmit(animal)
    cdSendBagData(player, animal)
end

---Petting: calms the dog and raises loyalty, once per cooldown.
---@param player IsoPlayer
---@param args table { id }
CD.Server.pet = function(player, args)
    if not CD.bondingEnabled() then return end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    if d.lastPetMin and (now - d.lastPetMin) < CD.petCooldownMin() then
        CD.notifyOwner(player, "petcooldown", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        return
    end
    d.lastPetMin = now
    d.petCalmMin = now

    animal:petAnimal(player)
    CD.addCombatStress(animal, -CD.PET_STRESS_RELIEF)
    CD.setLoyalty(animal, math.min(CD.TRUST_MAX, CD.loyalty(animal) + CD.PET_LOYALTY_GAIN))
    CD.notifyOwner(player, "petted", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

local function ownedVetDog(player, args)
    if not CD.vetCareEnabled() then return nil end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) or not CD.isCompanion(animal) then return nil end
    if not CD.isOwnedBy(animal, player) then
        CD.notifyOwner(player, "notyourdog", { breed = CD.getBreed(animal) })
        return nil
    end
    return animal, { id = animal:getOnlineID(), name = CD.data(animal).name, breed = CD.getBreed(animal) }
end

-- A acao do client e cerimonia: todo gate mora aqui. O estado do cao decide antes de gastar o item.
---@param player IsoPlayer
---@param args table { id, bandageId, disinfectId }
CD.Server.vettreat = function(player, args)
    local animal, info = ownedVetDog(player, args)
    if not animal then return end
    local inv = player:getInventory()
    local bandageId = tonumber(args.bandageId)
    local bandage = bandageId and inv:getItemById(bandageId)
    if not (bandage and bandage:isCanBandage()) then return end
    local disinfectId = tonumber(args.disinfectId)
    local disinfect = disinfectId and inv:getItemById(disinfectId)
    if disinfect and not CD.isDisinfectant(disinfect) then
        disinfect = nil
    end
    local dirty = bandage:getBandagePower() < 1
    local sterile = not dirty and (bandage:isAlcoholic() or disinfect ~= nil)
    local dressType = bandage:getReplaceOnUseFullType() or bandage:getFullType()
    local ok, why = CD.vetApplyTreatment(animal, player, sterile, dirty, dressType)
    if not ok then
        CD.notifyOwner(player, why, info)
        return
    end
    -- Sem UseAndSync: a bandagem suja so volta quando o curativo sai do cao.
    local cont = bandage:getContainer() or inv
    if isServer() then
        sendRemoveItemFromContainer(cont, bandage)
    end
    cont:Remove(bandage)
    if sterile and disinfect and not bandage:isAlcoholic() then
        cdConsumeMedical(player, disinfectId)
    end
end

---Takes the dressing off the dog's wound.
---@param player IsoPlayer
---@param args table { id }
CD.Server.vetundress = function(player, args)
    local animal, info = ownedVetDog(player, args)
    if not animal then return end
    local ok, key = CD.vetRemoveDressing(animal, player)
    CD.notifyOwner(player, key, info)
end

---Gives one medicine; the item is spent only when the dog takes it.
---@param player IsoPlayer
---@param args table { id, itemId }
CD.Server.vetmedicate = function(player, args)
    local animal, info = ownedVetDog(player, args)
    if not animal then return end
    local itemId = tonumber(args.itemId)
    local item = itemId and player:getInventory():getItemById(itemId)
    if not item or medicalKind(item) == nil then return end
    local ok, key = CD.vetApplyMedicine(animal, item, player)
    if not ok then
        CD.notifyOwner(player, key, info)
        return
    end
    cdConsumeMedical(player, itemId)
    CD.notifyOwner(player, key, info)
end

-- Banho vet: gasta uma dose do produto e a agua; o pano nao gasta.
---@param player IsoPlayer
---@param args table { id, itemId }
CD.Server.vetbath = function(player, args)
    local animal, info = ownedVetDog(player, args)
    if not animal then return end
    local inv = player:getInventory()
    local itemId = tonumber(args.itemId)
    local product = itemId and inv:getItemById(itemId)
    if not product or medicalKind(product) ~= "use" then return end
    local def = CD.vetBathDef(product:getFullType())
    if def == nil then return end
    local water, cloth = CD.vetBathKit(inv)
    if not (water and cloth) then
        CD.notifyOwner(player, "vetbathkit", info)
        return
    end
    local ok, key = CD.vetApplyBath(animal, def, player)
    if not ok then
        CD.notifyOwner(player, key, info)
        return
    end
    product:UseAndSync()
    water:getFluidContainer():removeFluid(CD.VET_BATH_WATER_L, false)
    water:syncItemFields()
    CD.notifyOwner(player, key, info)
end

-- Com a opcao de sandbox ligada, todo personagem sai sabendo as receitas de ervas. Aprendida uma vez,
-- a receita fica no personagem: desligar a opcao depois nao tira de quem ja sabe.
---@param player IsoPlayer
CD.Server.vetrecipes = function(player)
    if not player or not CD.vetCareEnabled() or not CD.vetRecipesUnlocked() then return end
    local learned = false
    for i = 1, #CD.VET_RECIPES do
        if player:learnRecipe(CD.VET_RECIPES[i]) then
            learned = true
        end
    end
    if learned and isServer() then
        sendSyncPlayerFields(player, 0x00000001)
    end
end

---Follow, stay or guard order; the dog may refuse or disobey.
---@param player IsoPlayer
---@param args table { id, state }
CD.Server.setstate = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    local state = args.state
    if state ~= CD.STATE_FOLLOW and state ~= CD.STATE_STAY and state ~= CD.STATE_GUARD then return end
    if state == CD.STATE_GUARD and not CD.breedCanFight(animal) then return end
    if state ~= CD.STATE_STAY and CD.vetCritical(animal) then
        CD.notifyOwner(player, "refused", { reason = "critical", name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return
    end
    if state == CD.STATE_GUARD and CD.vetRefusesWork(animal) then
        CD.notifyOwner(player, "refused", { reason = CD.refusalReason(animal) or "bleeding", name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return
    end
    if CD.rollDisobey(animal, player) then return end
    CD.cancelTrickGoto(animal)
    CD.setState(animal, state)
    CD.stampActiveSnapshotState(player, animal, state)
    if state == CD.STATE_STAY or state == CD.STATE_GUARD then
        CD.stopCombat(animal, CD.data(animal))
        -- stopAllMovementNow e obrigatorio junto: AnimalPathFindState e PathFindBehavior2 ignoram blockMovement,
        -- e um caminho ja em voo continua conduzindo o cao com o clipe de corrida rodando parado.
        animal:setVariable("animalRunning", false)
        animal:setVariable("animalSpeed", 0)
        animal:stopAllMovementNow()
        local b = animal:getBehavior()
        if b then
            b:setBlockMovement(true)
        end
        CD.clearClimbVars(animal)
    end
    if state == CD.STATE_GUARD then
        local d = CD.data(animal)
        d.guardX, d.guardY, d.guardZ = animal:getX(), animal:getY(), animal:getZ()
    end
    local d = CD.data(animal)
    d.loiterX = nil
    d.standDown = (state ~= CD.STATE_GUARD) and true or nil
    CD.grantObedienceXP(animal)
    CD.kennelSnapshot(player, animal)
    CD.transmit(animal)
end

---Sets the alert mode from mode, or from the silent flag when mode is absent.
---@param player IsoPlayer
---@param args table { id, mode, silent }
CD.Server.setalertmode = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if args.mode then
        CD.setAlertMode(animal, args.mode)
    else
        CD.setSentinelSilent(animal, args.silent == true)
    end
    CD.transmit(animal)
end

---@param player IsoPlayer
---@param args table { id, on }
CD.Server.setautoprotect = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if not CD.breedCanFight(animal) then return end
    CD.setAutoProtect(animal, args.on == true)
    CD.transmit(animal)
end

---@param player IsoPlayer
---@param args table { id, keep } keep is the follow distance in tiles, snapped to the allowed steps
CD.Server.setfollowkeep = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    CD.setFollowKeep(animal, tonumber(args.keep))
    CD.transmit(animal)
end

---@param player IsoPlayer
---@param args table { id, on }
CD.Server.sethuntmode = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    local on = args.on == true
    -- O client esconde o botao quando o admin desliga a caca, mas quem estava com a tela aberta na
    -- hora do toggle ainda consegue mandar; ligar aqui daria um modo que nunca vai produzir cacada.
    if on and not CD.huntEnabled() then return end
    if on and CD.vetRefusesWork(animal) then
        CD.notifyOwner(player, "refused", { reason = CD.refusalReason(animal) or "bleeding", name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return
    end
    if on then
        CD.setHuntMode(animal, true)
    else
        CD.clearHuntMode(animal)
    end
    CD.notifyOwner(player, "huntmode", { id = animal:getOnlineID(), on = on, breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

---Turns hunt mode off and drops any hunt in progress.
---@param animal IsoAnimal
function CD.clearHuntMode(animal)
    CD.setHuntMode(animal, false)
    local d = CD.data(animal)
    d.hunting = nil
    d.huntTargetId = nil
    d.woundedPrey = nil
    d.huntGoingSinceMin = nil
    d.huntDeliverUntilMin = nil
    d.huntCooling = nil
end

---Livestock care on, anchored at x, y, z or at the dog and only inside an animal zone; or off.
---@param player IsoPlayer
---@param args table { id, on, x, y, z }
CD.Server.setcaremode = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    local on = args.on == true
    if on and not CD.breedCanTendLivestock(animal) then return end
    if on then
        local ax = args.x or animal:getX()
        local ay = args.y or animal:getY()
        local az = args.z or animal:getZ()
        local zone = DesignationZoneAnimal.getZone(math.floor(ax), math.floor(ay), math.floor(az))
        if not zone then
            CD.notifyOwner(player, "carenopen", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
            return
        end
        CD.setCareMode(animal, true, ax, ay, az)
        CD.setState(animal, CD.STATE_STAY)
        local pd = CD.playerData(player)
        if pd and pd.token ~= nil and pd.token == CD.data(animal).companionToken then
            pd.token = nil
            pd.name = nil
            if player then
                player:transmitModData()
            end
        end
    else
        CD.setCareMode(animal, false)
    end
    CD.notifyOwner(player, "caremode", { id = animal:getOnlineID(), on = on, breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

---Opens the auto-protect window of AUTO_PROTECT_WINDOW_MIN, or closes it with off.
---@param player IsoPlayer
---@param args table { id, off }
CD.Server.setprotectactive = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if args.off then
        CD.data(animal).protectUntilMin = nil
    else
        CD.data(animal).protectUntilMin = CD.worldMinutes() + CD.AUTO_PROTECT_WINDOW_MIN
    end
end

---Points the dog at a forage spot; the target expires after HUNT_FORAGE_SCOUT_TTL_MIN.
---@param player IsoPlayer
---@param args table { id, x, y, z }
CD.Server.foragescout = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if not args.x or not args.y then return end
    CD.data(animal).forageScoutTarget = {
        x = math.floor(args.x), y = math.floor(args.y), z = math.floor(args.z or 0),
        untilMin = CD.worldMinutes() + CD.HUNT_FORAGE_SCOUT_TTL_MIN,
    }
end

local function reapplyBagVisual(animal)
    if animal and CD.hasBag(animal) then
        CD.applyBagVisual(animal)
    end
end

---Recall: the dog drops what it is doing and paths to the player; a disloyal dog refuses.
---@param player IsoPlayer
---@param args table { id }
CD.Server.come = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if CD.vetCritical(animal) then
        CD.notifyOwner(player, "refused", { reason = "critical", name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return
    end
    if CD.distractActive(animal) then
        CD.endDistract(animal, CD.data(animal))
    end
    if not CD.isDisloyal(animal) and CD.rollDisobey(animal, player) then return end
    CD.cancelTrickGoto(animal)
    CD.setState(animal, CD.STATE_FOLLOW)
    if not CD.isDisloyal(animal) then
        local d = CD.data(animal)
        local now = CD.worldMinutes()
        d.recallUntilMin = now + CD.RECALL_OVERRIDE_MIN
        d.standDown = true
        local b = animal:getBehavior()
        if b then
            b:setBlockMovement(false)
        end
        CD.pathStatEmit(animal, "recall")
        animal:pathToCharacter(player)
        animal:setVariable("bPathfind", true)
        CD.grantObedienceXP(animal)
    else
        CD.notifyOwner(player, "refused", { reason = CD.refusalReason(animal), name = CD.data(animal).name, breed = CD.getBreed(animal) })
    end
    reapplyBagVisual(animal)
    CD.transmit(animal)
end

---Makes the dog the player's active companion; the previous one is told to stay.
---@param player IsoPlayer
---@param args table { id }
CD.Server.select = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    local d = CD.data(animal)
    local pd = CD.playerData(player)
    local wasCaring = CD.getCareMode(animal)
    if wasCaring then
        CD.setCareMode(animal, false)
        CD.notifyOwner(player, "caremode", { id = animal:getOnlineID(), on = false, breed = CD.getBreed(animal) })
    end
    local prev = CD.getCompanionAnimal(player)
    if d.companionToken == nil then
        pd.seq = (pd.seq or 0) + 1
        d.companionToken = pd.seq
    end
    pd.seq = math.max(pd.seq or 0, d.companionToken)
    pd.companions = pd.companions or {}
    pd.companions[d.companionToken] = true
    CD.setActiveDog(pd, d.companionToken, d.name)
    if prev and prev ~= animal then
        CD.cancelTrickGoto(prev)
        CD.setState(prev, CD.STATE_STAY)
        CD.kennelSnapshot(player, prev)
        CD.transmit(prev)
    end
    if pd.carried and pd.carried.data and pd.carried.data.companionToken ~= pd.token then
        pd.carried.data.state = CD.STATE_STAY
    end
    if pd.stash and pd.stash.data and pd.stash.data.companionToken ~= pd.token then
        pd.stash.data.state = CD.STATE_STAY
    end
    CD.setState(animal, CD.STATE_FOLLOW)
    d.lastUpkeepMin = nil
    d.standDown = true
    if not CD.isDisloyal(animal) then
        local now = CD.worldMinutes()
        d.recallUntilMin = now + CD.RECALL_OVERRIDE_MIN
        local b = animal:getBehavior()
        if b then
            b:setBlockMovement(false)
        end
        CD.pathStatEmit(animal, "recall")
        animal:pathToCharacter(player)
        animal:setVariable("bPathfind", true)
    end
    reapplyBagVisual(animal)
    CD.transmit(animal)
    CD.kennelSnapshot(player, animal)
    player:transmitModData()
    CD.notifyOwner(player, "selected", { id = animal:getOnlineID(), name = d.name, breed = CD.getBreed(animal) })
end

---The active dog stays where it is and the player is left with no active companion.
---@param player IsoPlayer
---@param args table { id }
CD.Server.dismiss = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    local d = CD.data(animal)
    local pd = CD.playerData(player)
    if d.companionToken == nil or d.companionToken ~= pd.token then return end
    CD.cancelTrickGoto(animal)
    CD.setState(animal, CD.STATE_STAY)
    -- O posto da vadiagem e o lugar onde o cao foi dispensado, nao a ancora de um turno passivo antigo.
    d.loiterX = nil
    d.recallUntilMin = nil
    d.attackUntilMin, d.attackArmed = nil, nil
    d.standDown = true
    pd.token = nil
    pd.name = nil
    pd.dismissed = true
    CD.transmit(animal)
    CD.kennelSnapshot(player, animal)
    player:transmitModData()
    CD.notifyOwner(player, "dismissed", { id = animal:getOnlineID(), name = d.name, breed = CD.getBreed(animal) })
end

---Sorts the pair into dam and sire and checks every breeding rule.
---@param a IsoAnimal|nil
---@param b IsoAnimal|nil
---@return boolean ok
---@return string|nil reason refusal key for the breedfail notice; nil when ok
---@return IsoAnimal|nil dam nil when the pair is invalid or not one female and one male
---@return IsoAnimal|nil sire
---@nodiscard
function CD.breedEligible(a, b)
    if not a or not b or a == b or not CD.isDog(a) or not CD.isDog(b) then return false, "invalid" end
    if not (CD.isCompanion(a) and CD.isCompanion(b)) then return false, "invalid" end
    local sa, sb = CD.animalSex(a), CD.animalSex(b)
    local dam, sire
    if sa == "female" and sb == "male" then dam, sire = a, b
    elseif sa == "male" and sb == "female" then dam, sire = b, a
    else return false, "sex" end
    local owner = CD.getOwnerPlayer(dam)
    if not owner or not CD.isOwnedBy(sire, owner) then return false, "owner", dam, sire end
    local dd, sd = CD.data(dam), CD.data(sire)
    if not (CD.breedCanBreed(dam) and CD.breedCanBreed(sire)) then return false, "off", dam, sire end
    if not CD.sameSpecies(dam, sire) then return false, "species", dam, sire end
    if dd.breedingOff or sd.breedingOff then return false, "off", dam, sire end
    if math.floor(dam:getZ()) ~= math.floor(sire:getZ()) or CD.dist2D(dam, sire) > CD.BREED_LEASH then return false, "far", dam, sire end
    if CD.isWoundedCritical(dam) or CD.isWoundedCritical(sire) or CD.blocksBreeding(dam) or CD.blocksBreeding(sire) then return false, "health", dam, sire end
    if not (CD.isWellFed(dam) and CD.isWellFed(sire)) then return false, "hunger", dam, sire end
    if dd.pregnant or dd.breedTarget then return false, "pregnant", dam, sire end
    local now = CD.worldMinutes()
    if dd.lastWhelpMin and now < dd.lastWhelpMin + CD.breedCooldownMinutes() then return false, "cooldown", dam, sire end
    local lim = CD.maxCompanions()
    if lim > 0 and cdCompanionCount(owner) >= lim then return false, "limit", dam, sire end
    return true, nil, dam, sire
end

---Sends the dam to the sire when the pair is eligible.
---@param player IsoPlayer
---@param args table { id, mateId }
CD.Server.breed = function(player, args)
    if not CD.breedingEnabled() then return end
    local a = resolveAnimal(args)
    local b = args.mateId and getAnimal(tonumber(args.mateId)) or nil
    if not a or not b or a == b or not CD.isDog(a) or not CD.isDog(b) then return end
    if not (CD.isCompanion(a) and CD.isOwnedBy(a, player)) then return end
    if not (CD.isCompanion(b) and CD.isOwnedBy(b, player)) then return end
    local ok, reason, dam, sire = CD.breedEligible(a, b)
    if not ok then
        CD.notifyOwner(player, "breedfail", { reason = reason })
        return
    end
    CD.startBreedingApproach(dam, sire)
    CD.notifyOwner(player, "goingtomate", { name = CD.data(dam).name, breed = CD.getBreed(dam) })
end

local lastBreedHour
---Once per game hour each free female may conceive with her nearest eligible mate, at the sandbox daily chance spread over 24 hours.
function CD.tickPassiveBreeding()
    if isClient() then return end
    if not CD.breedingEnabled() then return end
    local chanceDay = CD.breedChancePerDay()
    if not chanceDay or chanceDay <= 0 then return end
    local h = math.floor(CD.worldMinutes() / 60)
    if lastBreedHour == nil then
        lastBreedHour = h
        return
    end
    if h == lastBreedHour then return end
    lastBreedHour = h
    local females, dogs = {}, {}
    CD.regEach(CD.regCompanions(), function(a)
        dogs[#dogs + 1] = a
        local d = CD.data(a)
        if CD.animalSex(a) == "female" and not d.pregnant and not d.breedTarget then
            females[#females + 1] = a
        end
    end)
    if #females == 0 then return end
    local pHour = chanceDay / 100 / 24
    for _, dam in ipairs(females) do
        local best, bestDist = nil, 99999
        for _, sire in ipairs(dogs) do
            if sire ~= dam and CD.breedEligible(dam, sire) then
                local dist = CD.dist2D(dam, sire)
                if dist < bestDist then
                    bestDist, best = dist, sire
                end
            end
        end
        if best and (ZombRand(0, 1000000) / 1000000) < pHour then
            CD.conceive(dam, best)
            local owner = CD.getOwnerPlayer(dam)
            if owner then
                CD.notifyOwner(owner, "bred", { name = CD.data(dam).name })
            end
        end
    end
end

---Admin debug: pairs the dog, or the nearest companion, with the closest breedable dog of its species within 16 tiles.
---@param player IsoPlayer
---@param args table { id }
CD.Server.forcebreed = function(player, args)
    if not CD.debugAllowed(player) then return end
    local target = resolveAnimal(args) or CD.findNearbyCompanion(player, 16)
    if not target or not CD.isDog(target) then return end
    if CD.isPuppy(target) then return end
    if not CD.breedCanBreed(target) then return end
    local cell = getCell()
    if not cell then return end
    local other, best = nil, 99999
    local dx0, dy0, dz0 = math.floor(target:getX()), math.floor(target:getY()), math.floor(target:getZ())
    for dx = -16, 16 do
        for dy = -16, 16 do
            local sq = cell:getGridSquare(dx0 + dx, dy0 + dy, dz0)
            local list = sq and sq:getAnimals()
            if list then
                for i = 0, list:size() - 1 do
                    local cand = list:get(i)
                    if cand and CD.isDog(cand) and cand ~= target and not CD.isPuppy(cand)
                        and CD.breedCanBreed(cand)
                        and CD.sameSpecies(cand, target) then
                        local dist = CD.dist2D(cand, target)
                        if dist < best then
                            best, other = dist, cand
                        end
                    end
                end
            end
        end
    end
    if not other then return end
    local dam, sire
    if CD.animalSex(target) == "male" and CD.animalSex(other) == "female" then dam, sire = other, target
    else dam, sire = target, other end
    CD.startBreedingApproach(dam, sire)
end

---Admin debug: the dog, or the nearest companion, gives birth now if pregnant.
---@param player IsoPlayer
---@param args table { id }
CD.Server.forcewhelp = function(player, args)
    if not CD.debugAllowed(player) then return end
    local dam = resolveAnimal(args) or CD.findNearbyCompanion(player, 16)
    if not dam or not CD.isDog(dam) then return end
    local owner = CD.getOwnerPlayer(dam) or player
    CD.whelpLitter(dam, owner)
end

---Admin debug: ages the pup so the next growth pass turns it into an adult.
---@param player IsoPlayer
---@param args table { id }
CD.Server.maturepup = function(player, args)
    if not CD.debugAllowed(player) then return end
    local pup = resolveAnimal(args) or CD.findNearbyCompanion(player, 16)
    if not pup or not CD.isDog(pup) then return end
    local d = CD.data(pup)
    d.growthPaused = nil
    d.bornMin = CD.worldMinutes() - CD.maturityMinutes() - 1
    CD.transmit(pup)
end

---Breeding off for this dog, or back on; turning it off also cancels a walk to a mate.
---@param player IsoPlayer
---@param args table { id, off }
CD.Server.setbreedmode = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    if not CD.breedCanBreed(animal) then return end
    local off = (args and args.off == true) and true or nil
    CD.data(animal).breedingOff = off
    if off and CD.abortBreeding then
        CD.abortBreeding(animal)
    end
    CD.transmit(animal)
end

---@param player IsoPlayer
---@param args table { id, paused }
CD.Server.setgrowthmode = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    CD.data(animal).growthPaused = (args and args.paused == true) and true or nil
    CD.transmit(animal)
end

---Puts the dog on the player's tile, or one tile behind the player when that one has a floor.
---@param player IsoPlayer
---@param args table { id }
CD.Server.teleport = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if CD.isDisloyal(animal) then
        CD.notifyOwner(player, "refused", { reason = CD.refusalReason(animal), name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return
    end
    local sq = player:getCurrentSquare()
    if not sq then return end
    local d = CD.data(animal)
    if CD.getCareMode(animal) then
        CD.setCareMode(animal, false)
        CD.notifyOwner(player, "caremode", { id = animal:getOnlineID(), on = false, breed = CD.getBreed(animal) })
    end
    CD.setState(animal, CD.STATE_FOLLOW)
    CD.setInCombat(animal, d, false)
    d.retreating = false
    d.standDown = true
    local bx, by, bz = sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()
    local tsq = sq
    local f = player:getForwardDirection()
    local nx, ny = bx - f:getX(), by - f:getY()
    local s = getCell():getGridSquare(math.floor(nx), math.floor(ny), bz)
    if s and CD.squareHasFloor(s) then
        bx, by, tsq = nx, ny, s
    end
    CD.clearClimbVars(animal)
    animal:stopAllMovementNow()
    animal:setX(bx)
    animal:setY(by)
    animal:setZ(bz)
    animal:setCurrent(tsq)
    reapplyBagVisual(animal)
    CD.notifyOwner(player, "teleported", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

---Attack order: the dog engages for the attack command window; it may refuse or disobey.
---@param player IsoPlayer
---@param args table { id }
CD.Server.attack = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if not CD.combatEnabled() then return end
    if not CD.breedCanFight(animal) then return end
    if CD.isDisloyal(animal) or CD.isPanicked(animal) or CD.isWoundedCritical(animal) or CD.vetRefusesFight(animal) then
        CD.notifyOwner(player, "refused", { reason = CD.refusalReason(animal), name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return
    end
    if CD.rollDisobey(animal, player) then return end
    CD.cancelTrickGoto(animal)
    CD.setState(animal, CD.STATE_FOLLOW)
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    d.attackUntilMin = now + CD.attackCommandWindowMin()
    d.attackArmed = true
    d.recallUntilMin = nil
    d.standDown = nil
    CD.grantObedienceXP(animal)
    CD.notifyOwner(player, "attacking", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

local function resolveTrick(player, args, id)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return nil end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return nil end
    if not CD.tricksEnabled() then return nil end
    if not CD.trickUnlocked(animal, id) then
        local def = CD.trickDef(id)
        CD.notifyOwner(player, "tricklocked", {
            id = animal:getOnlineID(), breed = CD.getBreed(animal), name = CD.data(animal).name,
            trick = id, level = def and def.minLevel or 0, have = CD.trickLevel(animal),
        })
        return nil
    end
    if CD.isDisloyal(animal) or CD.isPanicked(animal) or CD.isWoundedCritical(animal)
        or CD.vetHeartworm(animal) then
        CD.notifyOwner(player, "refused", { reason = CD.refusalReason(animal), name = CD.data(animal).name, breed = CD.getBreed(animal) })
        return nil
    end
    if CD.rollDisobey(animal, player) then return nil end
    return animal
end

---Distract trick: a loud bark pulls the nearby zombies toward the dog, once per cooldown.
---@param player IsoPlayer
---@param args table { id }
CD.Server.trickdistract = function(player, args)
    local animal = resolveTrick(player, args, "distract")
    if not animal then return end
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    if d.trickDistractUntilMin and now < d.trickDistractUntilMin then
        CD.notifyOwner(player, "trickcooldown", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        return
    end
    d.trickDistractUntilMin = now + CD.TRICK_DISTRACT_COOLDOWN_MIN

    CD.trickDistract(animal)
    CD.addCombatStress(animal, CD.TRICK_DISTRACT_STRESS)
    d.distractingUntilMin = now + CD.TRICK_DISTRACT_TAG_MIN
    d.recallUntilMin = now + CD.TRICK_DISTRACT_RECALL_MIN
    d.standDown = true
    CD.grantTrickXP(animal, "distract")
    CD.notifyOwner(player, "trickdistract", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
    CD.transmit(animal)
end

---Go-to trick: the dog walks to a floor tile within TRICK_GOTO_MAX_DIST of the player and stays there.
---@param player IsoPlayer
---@param args table { id, x, y, z }
CD.Server.trickgoto = function(player, args)
    local animal = resolveTrick(player, args, "goto")
    if not animal then return end
    local x, y = tonumber(args.x), tonumber(args.y)
    if not x or not y then return end
    local z = tonumber(args.z) or 0
    x, y, z = math.floor(x), math.floor(y), math.floor(z)

    local dx, dy = (x + 0.5) - player:getX(), (y + 0.5) - player:getY()
    local maxd = CD.TRICK_GOTO_MAX_DIST
    if (dx * dx + dy * dy) > (maxd * maxd) then
        CD.notifyOwner(player, "trickgotofar", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        return
    end
    local sq = getCell() and getCell():getGridSquare(x, y, z)
    if not sq or (CD.squareHasFloor and not CD.squareHasFloor(sq)) then
        CD.notifyOwner(player, "trickgotobad", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        return
    end

    local d = CD.data(animal)
    d.gotoSpot = { x = x, y = y, z = z, sinceMin = CD.worldMinutes() }
    d.gotoPathMs, d.gotoProbeMs = nil, nil
    d.forageSpot = nil
    d.forageScoutTarget = nil
    d.recallUntilMin = nil
    d.standDown = true
    local b = animal:getBehavior()
    if b then
        b:setBlockMovement(false)
    end
    CD.setState(animal, CD.STATE_STAY)
    CD.stampActiveSnapshotState(player, animal, CD.STATE_STAY)

    CD.grantTrickXP(animal, "goto")
    CD.notifyOwner(player, "trickgoto", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
    CD.transmit(animal)
    if CD.DEBUG_TRICK_GOTO then
        CD.log(string.format("[CD-GOTO] COMANDO alvo(%d,%d,%d) cao em (%.2f,%.2f,%d) estado=%s ativo=%s",
            x, y, z, animal:getX(), animal:getY(), math.floor(animal:getZ()),
            tostring(CD.getState(animal)),
            tostring(d.companionToken == CD.playerData(player).token)))
    end
end

---Sniff trick: the dog learns the scent of the item in the player's hands.
---@param player IsoPlayer
---@param args table { id }
CD.Server.tricksniff = function(player, args)
    local animal = resolveTrick(player, args, "sniff")
    if not animal then return end
    local item = CD.heldSniffItem(player)
    if not item then
        CD.notifyOwner(player, "sniffnoitem", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
        return
    end
    local d = CD.data(animal)
    local ftype, fname
    ftype = item:getFullType()
    fname = item:getName()
    if not ftype then return end
    d.sniffed = { t = ftype, name = fname or ftype, sinceMin = CD.worldMinutes() }
    d.sniffSpot = nil
    d.sniffMark = nil
    d.sniffMute = nil
    d.sniffAlertUntilMin = nil
    d.lastSniffScanMin = nil
    d.sniffRetryMin = nil
    d.fetchTask = nil
    CD.pulseSniffAnim(animal, "cmd-farejar")
    CD.grantTrickXP(animal, "sniff", "scent")
    CD.notifyOwner(player, "tricksniff", {
        id = animal:getOnlineID(), breed = CD.getBreed(animal), item = d.sniffed.name,
    })
    CD.transmit(animal)
    if CD.DEBUG_TRICK_SNIFF then
        CD.log(string.format("[CD-SNIFF] GRAVADO tipo=%s nome=%s estado=%s ativo=%s obediencia=%d",
            tostring(ftype), tostring(fname), tostring(CD.getState(animal)),
            tostring(d.companionToken == CD.playerData(player).token),
            CD.getSkillLevel(animal, "obedience")))
    end
end

---Forgets the scent and stops the sniff search.
---@param player IsoPlayer
---@param args table { id }
CD.Server.tricksniffstop = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    local d = CD.data(animal)
    local scentName = d.sniffed and d.sniffed.name or nil
    d.sniffed = nil
    d.sniffSpot = nil
    d.sniffMark = nil
    d.sniffMute = nil
    d.sniffAlertUntilMin = nil
    d.lastSniffScanMin = nil
    d.sniffRetryMin = nil
    d.sniffLastX, d.sniffLastY = nil, nil
    d.fetchTask = nil
    d.fetchTagUntilMin = nil
    CD.setSniffTag(animal, d, false)
    CD.driveMemo(animal, "sniff", true)
    CD.notifyOwner(player, "sniffstopped", {
        id = animal:getOnlineID(), breed = CD.getBreed(animal), item = scentName,
    })
    CD.transmit(animal)
    if CD.DEBUG_TRICK_SNIFF then
        CD.log(string.format("[CD-SNIFF] PAROU (cheiro %s descartado)", tostring(scentName)))
    end
end

---Fetch trick: arms the item in the player's hands; with slept, rolls the find of the armed item after the player's sleep.
---@param player IsoPlayer
---@param args table { id, slept }
CD.Server.trickfetch = function(player, args)
    local animal = resolveTrick(player, args, "fetch")
    if not animal then return end
    local d = CD.data(animal)
    local slept = args and args.slept == true

    if not slept then
        local held = CD.heldSniffItem(player)
        if not held then
            CD.notifyOwner(player, "trickfetchnoitem", { id = animal:getOnlineID(), breed = CD.getBreed(animal) })
            return
        end
        local ht, hn
        ht = held:getFullType()
        hn = held:getName()
        if not ht then return end
        if not CD.hasBag(animal) then return end
        if not CD.fetchCanCarry(held) then
            CD.notifyOwner(player, "trickfetchheavy", {
                id = animal:getOnlineID(), breed = CD.getBreed(animal), item = hn or ht,
            })
            return
        end
        if CD.fetchRarityEnabled() and CD.fetchNightChance(ht) == nil then
            CD.notifyOwner(player, "trickfetchunknown", {
                id = animal:getOnlineID(), breed = CD.getBreed(animal), item = hn or ht,
            })
            return
        end
        d.fetched = { t = ht, name = hn or ht, sinceMin = CD.worldMinutes() }
        d.fetchTask, d.fetchDrive, d.fetchTagUntilMin = nil, nil, nil
        CD.transmit(animal)
        CD.notifyOwner(player, "trickfetcharmed", {
            id = animal:getOnlineID(), breed = CD.getBreed(animal), item = hn or ht,
        })
        return
    end

    local scent = CD.fetchedScent(animal)
    if not scent then return end
    if not CD.hasBag(animal) then return end
    local now = CD.worldMinutes()
    if d.trickFetchUntilMin and now < d.trickFetchUntilMin then
        if CD.DEBUG_TRICK_FETCH then
            CD.log(string.format("[CD-FETCH] sono: em cooldown, faltam %.0f min de jogo",
                d.trickFetchUntilMin - now))
        end
        return
    end

    local proto = instanceItem(scent.t)
    if proto and not CD.fetchCanCarry(proto) then
        d.fetched = nil
        CD.transmit(animal)
        CD.notifyOwner(player, "trickfetchheavy", {
            id = animal:getOnlineID(), breed = CD.getBreed(animal), item = scent.name,
        })
        return
    end
    local chance = CD.TRICK_FETCH_CHANCE
    if CD.fetchRarityEnabled() then
        chance = CD.fetchNightChance(scent.t)
        if chance == nil then
            d.fetched = nil
            CD.transmit(animal)
            CD.notifyOwner(player, "trickfetchunknown", {
                id = animal:getOnlineID(), breed = CD.getBreed(animal), item = scent.name,
            })
            return
        end
    end
    if CD.DEBUG_TRICK_FETCH then
        CD.log(string.format("[CD-FETCH] sono: item=%s abundancia=%s chance=%.1f%%",
            tostring(scent.t), tostring(CD.itemAbundance(scent.t) or "?"), chance * 100))
    end

    d.trickFetchUntilMin = now + CD.TRICK_FETCH_COOLDOWN_MIN
    if ZombRand(0, 1000) >= chance * 1000 then
        d.fetchResult = { ok = false }
        d.fetchResultUntilMin = now + CD.TRICK_FETCH_RESULT_TAG_MIN
        CD.transmit(animal)
        CD.notifyOwner(player, "trickfetchnone", {
            id = animal:getOnlineID(), breed = CD.getBreed(animal), item = scent.name,
        })
        return
    end

    local item = proto or instanceItem(scent.t)
    if not item then return end
    if CD.bagWeight(d.bag.items or {}) + CD.itemWeight(item) > CD.bagCapacity(animal) then
        CD.notifyOwner(player, "bagfull", {})
        CD.transmit(animal)
        return
    end
    local label = item:getName()
    CD.bagInsert(player, animal, item)
    CD.grantTrickXP(animal, "fetch", "scent")
    d.fetchResult = { ok = true, item = label }
    d.fetchResultUntilMin = now + CD.TRICK_FETCH_RESULT_TAG_MIN
    if CD.DEBUG_TRICK_FETCH then
        CD.log(string.format("[CD-FETCH] sono: TROUXE %s", tostring(label)))
    end
    CD.notifyOwner(player, "trickfetchslept", {
        id = animal:getOnlineID(), breed = CD.getBreed(animal), item = label,
    })
    CD.transmit(animal)
end

---Forgets the armed fetch item.
---@param player IsoPlayer
---@param args table { id }
CD.Server.trickfetchstop = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isCompanion(animal) or not CD.isOwnedBy(animal, player) then return end
    local d = CD.data(animal)
    local itemName = d.fetched and d.fetched.name or nil
    d.fetched = nil
    d.fetchTask = nil
    d.fetchTagUntilMin = nil
    d.trickFetchUntilMin = nil
    CD.driveMemo(animal, "fetch", true)
    CD.notifyOwner(player, "fetchstopped", {
        id = animal:getOnlineID(), breed = CD.getBreed(animal), item = itemName,
    })
    CD.transmit(animal)
    if CD.DEBUG_TRICK_FETCH then
        CD.log(string.format("[CD-FETCH] PAROU (alvo %s descartado)", tostring(itemName)))
    end
end

---@param player IsoPlayer
---@param args table { id, text } text is cut to 30 characters
CD.Server.rename = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    local text = args.text
    if type(text) ~= "string" then return end
    if #text > 30 then
        text = string.sub(text, 1, 30)
    end
    CD.data(animal).name = text
    animal:setCustomName(text)
    local pd = CD.playerData(player)
    if CD.data(animal).companionToken == pd.token then
        pd.name = text
    end
    CD.kennelSnapshot(player, animal)
    CD.transmit(animal)
end

local function cdRecordStillBonded(pd, tok)
    if tok == nil then return false end
    if type(pd.companions) == "table" and pd.companions[tok] then return true end
    return tok == pd.token
end

local function stashRecordFor(player)
    if not player then return nil end
    local pd = CD.playerData(player)
    local rec = pd.stash
    if not rec or not rec.data then return nil, pd end
    if not cdRecordStillBonded(pd, rec.data.companionToken) then return nil, pd end
    if not CD.isMounted(player) then return nil, pd end
    return rec, pd
end

---Renames the dog stashed in the vehicle the player is in.
---@param player IsoPlayer
---@param args table { text } cut to 30 characters
CD.Server.renamestashed = function(player, args)
    local rec, pd = stashRecordFor(player)
    if not rec then return end
    local text = args.text
    if type(text) ~= "string" then return end
    if #text > 30 then
        text = string.sub(text, 1, 30)
    end
    rec.data.name = text
    pd.name = text
    player:transmitModData()
end

---The client reports the grief left; the server only lets it go down, and zero or less ends it.
---@param player IsoPlayer
---@param args table|nil { left, applied }
CD.Server.griefsync = function(player, args)
    if not player then return end
    local pd = CD.playerData(player)
    local g = pd.grief
    if type(g) ~= "table" then return end
    local left = args and args.left
    if type(left) ~= "number" or left <= 0 then
        pd.grief = nil
        player:transmitModData()
        return
    end
    if left < (g.left or 0) then
        g.left = left
    end
    local applied = args and args.applied
    if type(applied) == "number" and applied >= 0 then
        g.applied = applied
    end
    g.sinceSync = 0
    player:transmitModData()
end

---Feeds the dog stashed in the vehicle the player is in.
---@param player IsoPlayer
---@param args table { foodId, partialFrac, hunger, thirst }
CD.Server.feedstashed = function(player, args)
    local rec = stashRecordFor(player)
    if not rec then return end
    local bad = cdFeedIsToxic(player, args, rec.data.breed)
    local proteinPts = cdFeedProteinPoints(player, args, rec.data.breed)
    if not cdConsumeFood(player, args) then return end
    local raw = tonumber(args.hunger) or 0
    local red = (raw < 0) and math.min(-raw, 3.0) or 0
    local hungerCut = (red > 0) and red or CD.feedHungerRestore()
    rec.hunger = math.max(0, (rec.hunger or 0) - hungerCut)
    local rawT = tonumber(args.thirst) or 0
    local tCut = (rawT < 0) and math.min(-rawT, 1.0) or 0
    if tCut > 0 then
        rec.thirst = math.max(0, (rec.thirst or 0) - tCut)
    end
    local cap = rec.data.maxHealth or 1
    if bad then
        rec.data.trust = math.max(0, (rec.data.trust or 0) - CD.TOXIC_LOYALTY_PENALTY)
        rec.data.combatStress = math.min(1, (rec.data.combatStress or 0) + CD.TOXIC_STRESS)
        rec.data.sickUntilMin = CD.worldMinutes() + CD.TOXIC_SICK_MIN
        player:transmitModData()
        CD.notifyOwner(player, "sick", { breed = rec.data.breed })
        return
    end
    local V = math.floor(red * 100 + 0.5)
    local trustGain = (V > 0) and (V * CD.feedTrustPerHunger()) or CD.FEED_LOYALTY_GAIN
    rec.hp = math.min(cap, (rec.hp or cap) + CD.feedHealthBonus())
    rec.data.trust = math.min(CD.TRUST_MAX, (rec.data.trust or 0) + trustGain)
    rec.data.combatStress = math.max(0, (rec.data.combatStress or 0) - 0.4)
    if proteinPts > 0 then
        CD.markProteinMeal(rec.data, proteinPts)
    end
    rec.data.lastWarn = nil
    player:transmitModData()
    CD.notifyOwner(player, "fed", { breed = rec.data.breed })
end

---Waters the dog stashed in the vehicle the player is in.
---@param player IsoPlayer
---@param args table { waterId }
CD.Server.waterstashed = function(player, args)
    local rec = stashRecordFor(player)
    if not rec then return end
    if not cdConsumeWater(player, args) then return end
    rec.thirst = math.max(0, (rec.thirst or 0) - CD.waterThirstRestore())
    rec.data.trust = math.min(CD.TRUST_MAX, (rec.data.trust or 0) + CD.PET_LOYALTY_GAIN)
    rec.data.combatStress = math.max(0, (rec.data.combatStress or 0) - 0.2)
    if rec.data.lastWarn == "thirsty" then
        rec.data.lastWarn = nil
    end
    player:transmitModData()
    CD.notifyOwner(player, "watered", { breed = rec.data.breed })
end

---Breaks the bond: the dog drops its bag and becomes a stray, and its kennel record is cleared.
---@param player IsoPlayer
---@param args table { id }
CD.Server.release = function(player, args)
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    local pd = CD.playerData(player)
    local name = CD.data(animal).name
    local tok = CD.data(animal).companionToken
    if tok == pd.token then
        pd.token = nil
        pd.name = nil
    end
    if tok ~= nil and type(pd.companions) == "table" then
        pd.companions[tok] = nil
    end
    CD.clearKennel(player, tok)
    if player then
        player:transmitModData()
    end
    CD.demote(animal)
    CD.notifyOwner(player, "released", { name = name })
end

-- Animal vivo mora no apop, um arquivo por celula. Sem o mod o tipo nao existe, o IsoAnimal.load
-- estoura NPE, o AnimalCell.load devolve false e o jogo repovoa a celula inteira.
local function cdPurgeDog(animal)
    if not animal then return false end
    CD.spillBag(animal)
    local d = CD.data(animal)
    local tok = d.companionToken
    local owner = CD.getOwnerPlayer(animal)
    if owner and tok ~= nil then
        local pd = CD.playerData(owner)
        if tok == pd.token then
            pd.token = nil
            pd.name = nil
        end
        if type(pd.companions) == "table" then
            pd.companions[tok] = nil
        end
        CD.clearKennel(owner, tok)
        if pd.stash and pd.stash.data and pd.stash.data.companionToken == tok then
            pd.stash = nil
        end
        if owner then
            owner:transmitModData()
        end
    end
    animal:stopAllMovementNow()
    CD.despawn(animal)
    CD.regInvalidate()
    return true
end

local function cdPurgePlayerRecords(player)
    if not player then return 0, 0 end
    local pd = CD.playerData(player)
    local kn, st = 0, 0
    if type(pd.kennel) == "table" then
        local toks = {}
        for tok in pairs(pd.kennel) do toks[#toks + 1] = tok end
        for _, tok in ipairs(toks) do
            kn = kn + 1
            CD.clearKennel(player, tok)
        end
        pd.kennel = {}
    end
    if pd.stash then
        pd.stash = nil
        st = 1
    end
    pd.token = nil
    pd.name = nil
    pd.companions = {}
    player:transmitModData()
    return kn, st
end

local function cdEachPlayer(fn)
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            fn(p)
        end
    end
    for i = 0, 3 do
        local p = getSpecificPlayer(i)
        if p then
            fn(p)
        end
    end
end

---Admin debug: deletes the dog and every record of it.
---@param player IsoPlayer
---@param args table { id }
CD.Server.deletedog = function(player, args)
    if not CD.debugAllowed(player) then return end
    local animal = resolveAnimal(args)
    if not animal or not CD.isDog(animal) then return end
    local name = CD.data(animal).name or CD.breedNoun(animal)
    if not cdPurgeDog(animal) then return end
    CD.notifyOwner(player, "debugmsg", { text = "Deleted: " .. tostring(name) })
end

---Admin debug: deletes every loaded dog and clears all kennel and stash records, then sweeps the saved animals unless nosweep.
---@param player IsoPlayer
---@param args table|nil { nosweep }
CD.Server.deletealldogs = function(player, args)
    if not CD.debugAllowed(player) then return end
    args = args or {}
    -- Copia pra tabela Lua antes de apagar: apagar durante a varredura encurta a lista Java e o get(i) estoura.
    local snapshot = {}
    for _, a in ipairs(CD.regDogs() or {}) do snapshot[#snapshot + 1] = a end
    local gone = 0
    for _, a in ipairs(snapshot) do
        if cdPurgeDog(a) then
            gone = gone + 1
        end
    end
    local kennels, stashes = 0, 0
    cdEachPlayer(function(p)
        local kn, st = cdPurgePlayerRecords(p)
        kennels = kennels + kn
        stashes = stashes + st
    end)
    local store = CD.kennelGlobalAll()
    if type(store) == "table" then
        local keys = {}
        for k in pairs(store) do keys[#keys + 1] = k end
        for _, k in ipairs(keys) do
            local recs = store[k]
            if type(recs) == "table" then
                for _ in pairs(recs) do kennels = kennels + 1 end
            end
            store[k] = nil
        end
    end
    CD.notifyOwner(player, "debugmsg", { text = string.format(
        "Deleted %d LOADED dog(s). Cleared %d kennel record(s) and %d stash record(s). Records only: clearing a " ..
        "record does NOT remove a dog that is stored on disk.", gone, kennels, stashes) })
    if not args.nosweep and CD.Server.wipedogsapop then
        CD.Server.wipedogsapop(player, { skipload = true })
    end
end

local function cdDeepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = cdDeepCopy(v) end
    return r
end
local function cdFindCarriedDogItem(player)
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

---The player picked a dog up: keeps the carried record, taken from the held item or from the data the client sent.
---@param player IsoPlayer
---@param args table { onlineID, data }
CD.Server.carry = function(player, args)
    if not player then return end
    local onlineID = tonumber(args.onlineID)
    if not onlineID then return end
    local data, src
    local _, held = cdFindCarriedDogItem(player)
    if held and CD.isDog(held) and CD.isCompanion(held) and CD.isOwnedBy(held, player) then
        data = cdDeepCopy(CD.data(held))
        src = "item"
    elseif type(args.data) == "table" and args.data.companion then
        data = args.data
        src = "client"
    end
    if not data then
        return
    end
    if (data.ownerKey ~= nil and data.ownerKey ~= "") or (data.ownerName ~= nil and data.ownerName ~= "") then
        local owned = (data.ownerKey ~= nil and data.ownerKey ~= "" and data.ownerKey == CD.ownerKey(player))
            or (data.ownerName ~= nil and data.ownerName ~= "" and data.ownerName == player:getUsername())
        if not owned then return end
    end
    local pd = CD.playerData(player)
    local aid = nil
    if held then
        aid = held:getAnimalID()
    end
    pd.carried = {
        onlineID = onlineID,
        animalId = aid,
        data = data,
    }
    pd.stash = nil
    if data.companionToken then
        CD.kennelSeedFromData(player, data.companionToken, data)
    end
    player:transmitModData()
end

local function cdDishAtSquare(sq, dishId)
    if not sq then return nil end
    local wobs = sq:getWorldObjects()
    local fbWo, fbItem
    dishId = tonumber(dishId)
    for i = 0, wobs:size() - 1 do
        local wo = wobs:get(i)
        local item = wo:getItem()
        if item and CD.isDishType(item:getFullType()) then
            if dishId and item:getID() == dishId then return wo, item end
            if not fbItem then
                fbWo, fbItem = wo, item
            end
        end
    end
    return fbWo, fbItem
end

---Server only: tells every client the food and water left in the dish at that tile.
---@param x number|nil
---@param y number|nil
---@param z number|nil
---@param md table|nil the dish ModData
---@param dish InventoryItem|nil
function CD.broadcastDishStock(x, y, z, md, dish)
    if isServer() and x and y and z and md then
        local id = dish and dish:getID()
        sendServerCommand(CD.MODULE, "dishstock",
            { x = x, y = y, z = z, id = id, food = md.cdFoodMeals or 0, water = md.cdWater or 0 })
    end
end

---Places the dish from the inventory on a free floor tile within reach of the player.
---@param player IsoPlayer
---@param args table|nil { x, y, z, xo, yo, rot, itemId }
CD.Server.placedish = function(player, args)
    if not player or not args then return end
    local cell = getCell()
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (cell and x and y and z) then return end
    if z ~= math.floor(player:getZ()) or math.abs(x + 0.5 - player:getX()) > 2.5 or math.abs(y + 0.5 - player:getY()) > 2.5 then
        CD.notifyOwner(player, "dishnospace", {})
        return
    end
    local sq = cell:getGridSquare(x, y, z)
    if not sq or not sq:getFloor() then
        CD.notifyOwner(player, "dishnospace", {})
        return
    end
    local blocked = sq:isSolid() or sq:isSolidTrans()
    if blocked then
        CD.notifyOwner(player, "dishnospace", {})
        return
    end
    local xo = math.max(0.05, math.min(0.95, tonumber(args.xo) or 0.5))
    local yo = math.max(0.05, math.min(0.95, tonumber(args.yo) or 0.5))
    local rot = math.max(0, math.min(360, tonumber(args.rot) or 0))
    local id = tonumber(args.itemId)
    local inv = player:getInventory()
    local item = id and inv and inv:getItemById(id)
    if not item or not CD.isDishType(item:getFullType()) then return end
    CD.absorbRealWater(item)
    CD.refreshDishModel(item)
    -- ItemContainer:Remove nao e recursivo: remover de inv deixaria uma duplicata presa na sub-bolsa.
    local cont = item:getContainer() or inv
    if isServer() then
        sendRemoveItemFromContainer(cont, item)
    end
    cont:Remove(item)
    -- Rotacao antes do add (viaja no broadcast do AddWorldInventoryItem) e de novo depois.
    item:setWorldZRotation(rot)
    if sq then
        local wi = sq:AddWorldInventoryItem(item, xo, yo, 0.0)
        if wi then
            wi:setWorldZRotation(rot)
        end
    end
    if item then
        CD.broadcastDishStock(x, y, z, item:getModData(), item)
    end
    CD.notifyOwner(player, "dishplaced", {})
end

local function dishFromArgs(player, args)
    if not player or not args then return nil end
    local cell = getCell()
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (cell and x and y and z) then return nil end
    local _, dish = cdDishAtSquare(cell:getGridSquare(x, y, z), args.dishId)
    if not dish then
        CD.notifyOwner(player, "dishgone", {})
        return nil
    end
    return dish, x, y, z
end

---Fills the dish with food up to DISH_MAX_MEALS; what does not fit stays in the item.
---@param player IsoPlayer
---@param args table { x, y, z, dishId, foodId }
CD.Server.dishaddfood = function(player, args)
    local dish, x, y, z = dishFromArgs(player, args)
    if not dish then return end
    local inv = player:getInventory()
    local food = inv and args.foodId and inv:getItemById(tonumber(args.foodId))
    if not food or not CD.isBowlFood(food) then return end
    if CD.isBadDogFood(food) then return end
    local md = dish:getModData()
    if (md.cdWater or 0) > 0 then
        CD.notifyOwner(player, "dishhaswater", {})
        return
    end
    local cur, cap = md.cdFoodMeals or 0, CD.DISH_MAX_MEALS
    local space = cap - cur
    if space <= 0 then
        CD.notifyOwner(player, "dishfull", {})
        return
    end
    local add = CD.dishMealsForFood(food)
    local credited = math.min(add, space)
    md.cdFoodMeals = cur + credited
    if CD.isProteinFood(food) then
        md.cdFoodMeat = (md.cdFoodMeat or 0) + credited
        md.cdFoodProtein = CD.vetProteinGroup(food)
    end
    CD.refreshDishModel(dish)
    CD.broadcastDishStock(x, y, z, md, dish)
    if credited >= add then
        food:setHungChange(0)
        food:UseAndSync()
    else
        food:multiplyFoodValues((add - credited) / add)
        food:syncItemFields()
    end
    CD.notifyOwner(player, "dishfilled", {})
end

---Fills the dish with water from the given container, or from the first water source in the inventory.
---@param player IsoPlayer
---@param args table { x, y, z, dishId, waterId }
CD.Server.dishaddwater = function(player, args)
    local dish, x, y, z = dishFromArgs(player, args)
    if not dish then return end
    local md = dish:getModData()
    if (md.cdFoodMeals or 0) > 0 then
        CD.notifyOwner(player, "dishhasfood", {})
        return
    end
    local cap = CD.DISH_MAX_WATER
    if (md.cdWater or 0) >= cap then
        CD.notifyOwner(player, "dishfull", {})
        return
    end
    local inv = player:getInventory()
    local water = inv and args.waterId and inv:getItemById(tonumber(args.waterId))
    if not (water and water:getFluidContainer()) then
        local list = inv and inv:getAllWaterFluidSources(true)
        water = (list and list:size() > 0) and list:get(0) or nil
    end
    if not water then
        CD.notifyOwner(player, "dishnowater", {})
        return
    end
    local fc = water:getFluidContainer()
    if fc and not fc:isEmpty() then
        fc:removeFluid(CD.DISH_WATER_SOURCE_DRAIN, false)
    end
    water:syncItemFields()
    md.cdWater = cap
    -- Agua contaminada do proprio jogo: a tigela lembra e o gole rola o estomago.
    if fc and fc:isPoisonous() then
        md.cdWaterTainted = 1
    else
        md.cdWaterTainted = nil
    end
    CD.refreshDishModel(dish)
    CD.broadcastDishStock(x, y, z, md, dish)
    CD.notifyOwner(player, "dishwatered", {})
end

---@param player IsoPlayer
---@param args table { x, y, z, dishId }
CD.Server.dishempty = function(player, args)
    local dish, x, y, z = dishFromArgs(player, args)
    if not dish then return end
    local md = dish:getModData()
    if (md.cdFoodMeals or 0) <= 0 and (md.cdWater or 0) <= 0 then return end
    md.cdFoodMeals = 0
    md.cdFoodMeat = 0
    md.cdWater = 0
    CD.refreshDishModel(dish)
    CD.broadcastDishStock(x, y, z, md, dish)
    CD.notifyOwner(player, "dishemptied", {})
end

---The client reports where its dogs are; at most 16 entries, kept only for the player's own tokens.
---@param player IsoPlayer
---@param args table|nil { list } entries { t, x, y, z, name }
CD.Server.dogpos = function(player, args)
    if not player or type(args) ~= "table" or type(args.list) ~= "table" then return end
    local pd = CD.playerData(player)
    local own = pd.companions
    local n = 0
    for _, e in ipairs(args.list) do
        n = n + 1
        if n > 16 then return end
        if type(e) == "table" and e.t ~= nil and ((type(own) == "table" and own[e.t]) or pd.token == e.t) then
            local x, y, z = tonumber(e.x), tonumber(e.y), tonumber(e.z)
            if x and y then
                local name = e.name
                if type(name) ~= "string" then name = nil
                elseif #name > 30 then name = string.sub(name, 1, 30) end
                pd.dogPositions = pd.dogPositions or {}
                pd.dogPositions[e.t] = { x = x, y = y, z = z or 0, name = name }
            end
        end
    end
end

---Admin debug: sends every kennel record of the world, grouped by owner.
---@param player IsoPlayer
---@param args table|nil unused
CD.Server.kenneladmin = function(player, args)
    if not player then return end
    if not CD.debugAllowed(player) then return end
    local onlineSet = {}
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        onlineSet[p:getUsername()] = true
    end
    local owners = {}
    local all = CD.kennelGlobalAll() or {}
    for key, bucket in pairs(all) do
        if type(bucket) == "table" then
            local o = { key = tostring(key), name = nil, online = (not isServer()) or onlineSet[key] == true, dogs = {} }
            for _, snap in pairs(bucket) do
                if type(snap) == "table" then
                    if o.name == nil and type(snap.ownerName) == "string" and snap.ownerName ~= "" then
                        o.name = snap.ownerName
                    end
                    o.dogs[#o.dogs + 1] = {
                        name = snap.name, breed = snap.breed, sex = snap.sex,
                        isPup = snap.isPup == true, lost = snap.lost == true,
                        x = snap.x, y = snap.y, z = snap.z,
                        savedAtMin = snap.savedAtMin, hp = snap.hp,
                        skills = snap.skills,
                    }
                end
            end
            if #o.dogs > 0 then
                owners[#owners + 1] = o
            end
        end
    end
    local payload = { owners = owners, now = CD.worldMinutes() }
    if isServer() then
        sendServerCommand(player, CD.MODULE, "kenneladminlist", payload)
    elseif CD.onKennelAdminList then
        CD.onKennelAdminList(payload)
    end
end

---Stores the player's auto-feed hunger trigger, clamped to 0.1..1.
---@param player IsoPlayer
---@param args table|nil { value }
CD.Server.feedtrigger = function(player, args)
    if not player or type(args) ~= "table" or type(args.value) ~= "number" then return end
    player:getModData().cdFeedTrigger = math.max(0.1, math.min(1.0, args.value))
end

---Stores the player's loiter radius in tiles, clamped to the loiter bounds and rounded.
---@param player IsoPlayer
---@param args table|nil { value }
CD.Server.loiterradius = function(player, args)
    if not player or type(args) ~= "table" or type(args.value) ~= "number" then return end
    player:getModData().cdLoiterRadius =
        math.floor(math.max(CD.LOITER_RADIUS_MIN, math.min(CD.LOITER_RADIUS_MAX, args.value)) + 0.5)
end

local TUNE_KEY = CD.MODULE .. "_Tuning"

local function tuneStore() return ModData.getOrCreate(TUNE_KEY) end

local function tuningPayload()
    local specs = {}
    for i = 1, #CD.TUNABLES do
        local s = CD.TUNABLES[i]
        specs[i] = { key = s.key, min = s.min, max = s.max, step = s.step, def = s.def, label = s.label, note = s.note }
    end
    return {
        specs  = specs,
        values = CD.tuningValues(),
        perf   = CD._perfLast,
        perfOn = CD.PERF_DEBUG == true,
        secs   = CD.PERF_DEBUG_SECS,
        level    = CD._perfLv or 0,
        csvOn    = CD.PERF_CSV == true,
        csvName  = (CD.PERF_CSV and CD.perfCsvName()) or nil,
        clockMs  = CD._perfCalMs,
        probeUs  = CD._perfCalUs,
        spikeMs  = CD._perfSpikeMs,
        trace    = CD._perfTraceLeft or 0,
        dmgOn    = CD.DMG_DEBUG == true,
        netAuthOn = CD.NET_AUTHORITY ~= false,
        loiterOn = CD.PASSIVE_IDLE_ENABLED ~= false,
        huntOn = CD.HUNT_ENABLED ~= false,
    }
end

local function sendTuning(player)
    if isServer() then
        sendServerCommand(player, CD.MODULE, "tuninglist", tuningPayload())
    elseif CD.onTuningList then
        CD.onTuningList(tuningPayload())
    end
end

---Admin: sends the tuning panel its values.
---@param player IsoPlayer
---@param args table|nil unused
CD.Server.tuningget = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    sendTuning(player)
end

---Admin: sets one tunable, clamped, and keeps it in the world save.
---@param player IsoPlayer
---@param args table|nil { key, value }
CD.Server.tuningset = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    if type(args) ~= "table" then return end
    local spec = CD.tunableSpec(args.key)
    if not spec then return end
    local v = CD.clampTunable(spec.key, args.value)
    if v == nil then return end
    local store = tuneStore()
    local old = CD[spec.key]
    if old == v then
        sendTuning(player)
        return
    end
    store[spec.key] = v
    CD.applyTuning(store)
    local who = tostring(player:getUsername() or "?")
    CD.log(string.format("[CD-TUNE] %s: %s %s -> %s", who, spec.key, tostring(old), tostring(v)))
    sendTuning(player)
end

---Admin: every tunable and toggle back to its default.
---@param player IsoPlayer
---@param args table|nil unused
CD.Server.tuningreset = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local store = tuneStore()
    for i = 1, #CD.TUNABLES do store[CD.TUNABLES[i].key] = nil end
    store.PERF_DEBUG = nil
    store.NET_AUTHORITY = nil
    store.PASSIVE_IDLE_ENABLED = nil
    store.HUNT_ENABLED = nil
    CD.applyTuning(store)
    CD.PERF_DEBUG = false
    CD.NET_AUTHORITY = true
    CD.PASSIVE_IDLE_ENABLED = true
    CD.HUNT_ENABLED = true
    CD.emit("huntenabled", { on = true })
    local who = tostring(player:getUsername() or "?")
    CD.log("[CD-TUNE] " .. who .. ": defaults restored")
    sendTuning(player)
end

---Admin: performance measurement on or off.
---@param player IsoPlayer
---@param args table|nil { on }
CD.Server.perfdebug = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local on = type(args) == "table" and args.on == true
    local store = tuneStore()
    store.PERF_DEBUG = on
    CD.PERF_DEBUG = on
    CD.perfApplyLevel()
    CD.perfReset()
    if on then
        CD.perfCalibrate()
    end
    CD.log("[CD-TUNE] measurement " .. (on and "ON" or "off"))
    sendTuning(player)
end

---Admin: measurement depth, 1 or 2.
---@param player IsoPlayer
---@param args table|nil { level }
CD.Server.perflevel = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local lv = tonumber(type(args) == "table" and args.level or nil) or 1
    if lv < 1 then lv = 1 elseif lv > 2 then lv = 2 end
    CD.PERF_LEVEL = lv
    CD.perfApplyLevel()
    CD.perfReset()
    CD.log("[CD-TUNE] measurement depth = " .. lv)
    sendTuning(player)
end

---The owner's client confirms, or denies, the kill of a zombie the dog brought down.
---@param player IsoPlayer unused
---@param args table|nil { id, ok, motivo }
CD.Server.killzombieack = function(player, args)
    if type(args) ~= "table" or args.id == nil then return end
    local rec = CD.zdmg and CD.zdmg[args.id]
    local dt = (rec and rec.pend) and (getTimestampMs() - rec.pend) or -1
    if args.ok == true then
        if CD.zdmg then
            CD.zdmg[args.id] = nil
        end
    elseif rec then
        rec.pend = nil
    end
    CD.perfCount("dmg.killack")
    if CD.DMG_DEBUG then
        CD.log(string.format("[CD-DMG] kill-ack z=%s ok=%s motivo=%s dt=%d",
            tostring(args.id), args.ok == true and "S" or "N", tostring(args.motivo or "-"), dt))
    end
end

---Admin: damage diagnostics on or off, on the server and on every client.
---@param player IsoPlayer
---@param args table|nil { on }
CD.Server.dmgdebug = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local on = type(args) == "table" and args.on == true
    CD.DMG_DEBUG = on
    CD.log("[CD-DMG] diagnostico " .. (on and "ON" or "off") .. " (lado=" .. (CD.perfSide() or "?") .. ")")
    CD.emit("dmgdebug", { on = on })
    sendTuning(player)
end

---Admin: idle dogs wander, on or off.
---@param player IsoPlayer
---@param args table|nil { on }
CD.Server.passiveidle = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local on = type(args) == "table" and args.on == true
    tuneStore().PASSIVE_IDLE_ENABLED = on
    CD.PASSIVE_IDLE_ENABLED = on
    CD.log("[CD-TUNE] idle dogs wander " .. (on and "ON" or "off"))
    sendTuning(player)
end

---Admin: hunting on or off for the whole world.
---@param player IsoPlayer
---@param args table|nil { on }
CD.Server.hunttoggle = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local on = type(args) == "table" and args.on == true
    tuneStore().HUNT_ENABLED = on
    CD.HUNT_ENABLED = on
    -- O portao tambem e lido no client (bonus de visao e batedor do forrageio), entao aqui
    -- nao basta guardar: sem o aviso o client segue dando o bonus de uma cacada desligada.
    CD.emit("huntenabled", { on = on })
    CD.log("[CD-TUNE] hunting " .. (on and "ON" or "off"))
    sendTuning(player)
end

-- Quem entra depois do toggle nao viu o aviso; o client pede o estado ao carregar.
---@param player IsoPlayer
---@param args table|nil unused
CD.Server.huntstate = function(player, args)
    if not player then return end
    if isServer() then
        sendServerCommand(player, CD.MODULE, "huntenabled", { on = CD.HUNT_ENABLED ~= false })
    end
end

---Admin: client position authority on or off; off takes it back from every client at once.
---@param player IsoPlayer
---@param args table|nil { on }
CD.Server.netauthority = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local on = type(args) == "table" and args.on == true
    tuneStore().NET_AUTHORITY = on
    CD.NET_AUTHORITY = on
    if not on and CD.netAuthRevokeAll then
        CD.netAuthRevokeAll("outro")
    end
    CD.log("[CD-TUNE] client authority " .. (on and "ON" or "off"))
    sendTuning(player)
end

---Admin: CSV recording of the measurement on or off; turning it on also starts the measurement.
---@param player IsoPlayer
---@param args table|nil { on }
CD.Server.perfcsv = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    local on = type(args) == "table" and args.on == true
    if on and not CD.PERF_DEBUG then
        CD.PERF_DEBUG = true
        tuneStore().PERF_DEBUG = true
        CD.perfApplyLevel()
        CD.perfReset()
        CD.perfCalibrate()
    end
    CD.perfCsvArm(on)
    sendTuning(player)
end

---Admin: traces the next ticks; does nothing while the measurement is off.
---@param player IsoPlayer
---@param args table|nil { ticks }
CD.Server.perftrace = function(player, args)
    if not player then return end
    if not CD.adminAllowed(player) then return end
    if not CD.PERF_DEBUG then return end
    CD.perfTraceArm(tonumber(type(args) == "table" and args.ticks or nil) or 0)
    sendTuning(player)
end

local function applySavedTuning()
    local store = tuneStore()
    CD.applyTuning(store)
    local parts = {}
    for i = 1, #CD.TUNABLES do
        local k = CD.TUNABLES[i].key
        parts[#parts + 1] = k .. "=" .. tostring(CD[k]) .. ((store[k] ~= nil) and "*" or "")
    end
    CD.log("[CD-TUNE] in effect (* = set by an admin): " .. table.concat(parts, " | ") ..
          " | measurement: " .. (CD.PERF_DEBUG and "ON" or "off"))
end

local function OnClientCommand(module, command, player, args)
    if module ~= CD.MODULE then return end
    local fn = CD.Server[command]
    if not fn then return end
    if CD._perfLv and CD._perfLv > 0 then
        CD.perfCount("rx." .. tostring(command))
        CD.perfEnter("srv.cmd")
        fn(player, args)
        CD.perfExit()
        return
    end
    fn(player, args)
end

if isServer() then
    Events.OnClientCommand.Add(OnClientCommand)
end

if not isClient() then
    Events.OnInitGlobalModData.Add(applySavedTuning)
end
