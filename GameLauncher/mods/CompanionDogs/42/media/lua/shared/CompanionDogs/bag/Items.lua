CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---Adds the item's record to the dog's bag; the item itself stays where it is.
---@param player IsoPlayer|nil owner whose kennel record is refreshed
---@param animal IsoAnimal|nil
---@param item InventoryItem|nil
---@return boolean ok
---@return string|nil reason "nobag", "live" or "full" when refused
function CD.bagInsert(player, animal, item)
    if not animal or not item then return false, "nobag" end
    if not CD.hasBag(animal) then return false, "nobag" end
    if CD.isLiveAnimalItem(item) then return false, "live" end
    local d = CD.data(animal)
    d.bag.items = d.bag.items or {}
    if CD.bagWeight(d.bag.items) + CD.itemWeight(item) > CD.bagCapacity(animal) then return false, "full" end
    table.insert(d.bag.items, CD.serializeItem(item))
    if player and CD.kennelSnapshot then
        CD.kennelSnapshot(player, animal)
    end
    CD.transmit(animal)
    return true
end

---Rebuilds the item with every field serializeItem stored.
---@param r table|nil bag record
---@return InventoryItem|nil nil for a missing type or a live animal
---@nodiscard
function CD.bagItemFromRecord(r)
    if not r or not r.t then return nil end
    local it = instanceItem(r.t)
    if not it then return nil end
    if CD.isLiveAnimalItem(it) then return nil end
    if r.cond then
        it:setCondition(r.cond)
    end
    if r.sharp then
        it:setSharpness(r.sharp)
    end
    if r.delta then
        it:setCurrentUsesFloat(r.delta)
    end
    if r.fluids then
        local fc = it:getFluidContainer()
        if fc then
            fc:Empty()
            for _, f in ipairs(r.fluids) do fc:addFluid(f.f, f.a) end
        end
    end
    -- cada bloco espelha o teste de tipo que Bag.lua usou para gravar o campo
    if r.hung and instanceof(it, "Food") then
        it:setHungChange(r.hung)
    end
    if r.age then
        it:setAge(CD.projectedAge(r) or r.age)
    end
    if r.cooked then
        it:setCooked(true)
    end
    if r.burnt then
        it:setBurnt(true)
    end
    if r.ammo then
        it:setCurrentAmmoCount(r.ammo)
    end
    if instanceof(it, "HandWeapon") then
        if r.chamber then
            it:setRoundChambered(true)
        end
        if r.clip then
            it:setContainsClip(true)
        end
        if r.parts then
            it:clearAllWeaponParts()
            for _, pr in ipairs(r.parts) do
                local part = CD.bagItemFromRecord(pr)
                if part and instanceof(part, "WeaponPart") then
                    it:attachWeaponPart(part)
                end
            end
            if r.clipsz then
                it:setClipSize(r.clipsz)
            end
        end
    end
    if r.key then
        it:setKeyId(r.key)
    end
    if r.keyn and instanceof(it, "Key") then
        it:setNumberOfKey(r.keyn)
    end
    if r.media then
        it:setRecordedMediaIndexInteger(r.media)
    end
    if r.repaired then
        it:setHaveBeenRepaired(r.repaired)
    end
    if instanceof(it, "Literature") then
        if r.pages then
            for i, t in pairs(r.pages) do it:addPage(i, t) end
            if r.canwrite ~= nil then
                it:setCanBeWrite(r.canwrite)
            end
        end
        if r.locked then
            it:setLockedBy(r.locked)
        end
    end
    if r.cloth and instanceof(it, "Clothing") then
        local c = r.cloth
        local v = it:getVisual()
        if v then
            if c.holes then
                for i in pairs(c.holes)   do v:setHole(BloodBodyPartType.FromIndex(i - 1)) end
            end
            if c.pblood then
                for i, b in pairs(c.pblood) do v:setBlood(BloodBodyPartType.FromIndex(i - 1), b) end
            end
            if c.pdirt then
                for i, d in pairs(c.pdirt)  do v:setDirt(BloodBodyPartType.FromIndex(i - 1), d) end
            end
            if c.tex then
                v:setBaseTexture(c.tex)
            end
            if c.texc then
                v:setTextureChoice(c.texc)
            end
        end
        if c.blood then
            it:setBloodLevel(c.blood)
        end
        if c.dirt then
            it:setDirtiness(c.dirt)
        end
        if c.wet then
            it:setWetness(c.wet)
        end
        if c.patches then for _, p in ipairs(c.patches) do
            it:addPatchForSync(p.part, p.lvl, p.fab, p.hole == true)
            if p.cg and p.cg ~= 0 then
                local cp = it:getPatchType(BloodBodyPartType.FromIndex(p.part))
                if cp then
                    cp.conditionGain = p.cg
                end
            end
        end end
    end
    if r.md then
        local m = it:getModData()
        for k, v in pairs(r.md) do m[k] = v end
    end
    if r.name then
        it:setName(r.name)
        if r.custom then
            it:setCustomName(true)
        end
    end
    return it
end

---@param container ItemContainer|nil
---@param records table[]|nil bag records, each added as a rebuilt item
function CD.rehydrateBag(container, records)
    if not container then return end
    for _, r in ipairs(records or {}) do
        local it = CD.bagItemFromRecord(r)
        if it then
            container:addItem(it)
        end
    end
end

---Server side: drops the bag and its load on the dog's square, or on the owner's while the dog is carried.
---@param animal IsoAnimal
function CD.spillBag(animal)
    if isClient() then return end
    local d = CD.data(animal)
    local b = d.bag
    if not b or not b.equipped then return end
    local sq = animal:getCurrentSquare() or animal:getSquare()
    if not sq then
        -- Cao dentro de um AnimalInventoryItem nao esta no mundo e as duas leituras voltam nil.
        -- Sem este fallback a carga era apagada em vez de cair no chao.
        local owner = CD.getOwnerPlayer(animal)
        sq = owner and (owner:getCurrentSquare() or owner:getSquare())
    end
    if not sq then return end
    local bagItem = instanceItem(CD.SADDLEBAG_TYPE)
    if not bagItem then return end
    CD.rehydrateBag(bagItem:getInventory(), b.items)
    sq:AddWorldInventoryItem(bagItem, 0.5, 0.5, 0.0)
    d.bag = nil
    CD.transmit(animal)
end

CD.SADDLEBAG_STRAP_TYPE = "Base.CompanionDogsSaddlebagStrap"
CD.SADDLEBAG_PARTS = {
    { loc = "saddlebags_l", item = CD.SADDLEBAG_TYPE },
    { loc = "saddlebags_r", item = CD.SADDLEBAG_TYPE },
    { loc = "saddlebags_c", item = CD.SADDLEBAG_STRAP_TYPE },
}

-- Um IsoAnimal pode chegar ao mundo com attachedItems null (todo construtor tem early-return antes
-- da ultima linha). O NPE nao vira erro Lua: a leitura simplesmente volta nil.
---@param animal IsoAnimal|nil
---@return boolean ready
function CD.ensureAttachSlots(animal)
    if not animal then return false end
    if animal:getAttachedItems() ~= nil then return true end
    animal:initAttachedItems("Animal")
    return animal:getAttachedItems() ~= nil
end

---Server side: hangs the bag parts on the dog and tells every client.
---@param animal IsoAnimal|nil
function CD.applyBagVisual(animal)
    if isClient() then return end
    if not animal or not CD.hasBag(animal) then return end
    if not CD.ensureAttachSlots(animal) then return end
    local oid = animal:getOnlineID()
    for _, p in ipairs(CD.SADDLEBAG_PARTS) do
        animal:setAttachedItem(p.loc, instanceItem(p.item))
        if isServer() then
            sendServerCommandV("animal", "attach",
                "id", tostring(oid), "location", p.loc, "item", p.item)
        end
    end
end

---Server side: takes the bag parts off the dog, with no network message.
---@param animal IsoAnimal|nil
function CD.removeBagVisual(animal)
    if isClient() then return end
    if not animal then return end
    if not CD.ensureAttachSlots(animal) then return end
    for _, p in ipairs(CD.SADDLEBAG_PARTS) do
        animal:setAttachedItem(p.loc, nil)
    end
end

---Hangs the bag parts on this VM's copy of the dog only.
---@param animal IsoAnimal|nil
function CD.applyBagVisualLocal(animal)
    if not animal then return end
    if not CD.ensureAttachSlots(animal) then return end
    for _, p in ipairs(CD.SADDLEBAG_PARTS) do
        animal:setAttachedItem(p.loc, instanceItem(p.item))
    end
end

---Takes the bag parts off this VM's copy of the dog only.
---@param animal IsoAnimal|nil
function CD.removeBagVisualLocal(animal)
    if not animal then return end
    if not CD.ensureAttachSlots(animal) then return end
    for _, p in ipairs(CD.SADDLEBAG_PARTS) do
        animal:setAttachedItem(p.loc, nil)
    end
end
