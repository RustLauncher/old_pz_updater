CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.SADDLEBAG_TYPE = "Base.CompanionDogsSaddlebag"

---@param fullType string|nil
---@return boolean
---@nodiscard
function CD.isSaddlebagType(fullType)
    return fullType == CD.SADDLEBAG_TYPE
end

-- animal vivo nao sobrevive ao registro plano: o IsoAnimal mora dentro do item, nao no tipo, e o
-- save()/AddWorldInventoryItem de um AnimalInventoryItem com animal nulo desreferencia sem checar.
---@param it InventoryItem|nil
---@return boolean
---@nodiscard
function CD.isLiveAnimalItem(it)
    return it ~= nil and instanceof(it, "AnimalInventoryItem")
end

---@param animal IsoAnimal
---@return boolean
---@nodiscard
function CD.hasBag(animal)
    local b = CD.data(animal).bag
    return b ~= nil and b.equipped == true
end

---First saddlebag in the player's inventory, nested bags included.
---@param player IsoPlayer|nil
---@return InventoryItem|nil
---@nodiscard
function CD.findBagItem(player)
    if not player then return nil end
    local inv = player:getInventory()
    local it = inv:getFirstTypeRecurse(CD.SADDLEBAG_TYPE)
    return it
end

CD.BAG_CAP_BASE = 4
CD.BAG_CAP_SPAN = 8

---@return number multiplier >= 0, the sandbox CargoCapacityMultiplier
---@nodiscard
function CD.bagCapacityMultiplier()
    local sv = CD.sandbox()
    local m = sv and sv.CargoCapacityMultiplier
    if type(m) ~= "number" then
        m = 1
    end
    if m < 0 then
        m = 0
    end
    return m
end

---Weight the bag holds: strength gene, breed bagMult and sandbox multiplier, rounded and capped at 100.
---@param animal IsoAnimal|nil nil uses a mid strength gene and no breed multiplier
---@return integer
---@nodiscard
function CD.bagCapacity(animal)
    local ratio = 0.5
    if animal then
        ratio = CD.geneRatio(animal, "strength")
    end
    local mult = 1
    if animal then
        mult = CD.getBreedDef(animal).bagMult or 1
    end
    local cap = (CD.BAG_CAP_BASE + CD.BAG_CAP_SPAN * (ratio or 0.5)) * mult * CD.bagCapacityMultiplier()
    cap = math.floor(cap + 0.5)
    if cap < 0 then cap = 0 elseif cap > 100 then cap = 100 end
    return cap
end

---Unequipped weight, or the plain weight when that reads 0 or less; 0 for nil.
---@param it InventoryItem|nil
---@return number
---@nodiscard
function CD.itemWeight(it)
    if not it then return 0 end
    local w = it:getUnequippedWeight()
    if w <= 0 then
        w = it:getWeight()
    end
    return w
end

---Sum of the stored weights; a record without one is weighed from a fresh item of its type.
---@param records table[]|nil bag records
---@return number
---@nodiscard
function CD.bagWeight(records)
    local total = 0
    for _, r in ipairs(records or {}) do
        local w = r.w
        if not w then
            local it = instanceItem(r.t)
            if it then
                w = CD.itemWeight(it)
            end
        end
        total = total + (w or 0)
    end
    return total
end

---Rot speed multiplier of the FoodRotSpeed sandbox option: 1.7, 1.4, 1, 0.7 or 0.4.
---@return number
---@nodiscard
function CD.foodRotSpeed()
    local v = SandboxVars.FoodRotSpeed or 3
    if v == 1 then return 1.7 elseif v == 2 then return 1.4
    elseif v == 4 then return 0.7 elseif v == 5 then return 0.4 end
    return 1.0
end

---Stored food age advanced by the world hours since r.aged, scaled by foodRotSpeed().
---@param r table|nil bag record
---@return number|nil age in days; nil when the record has no age
---@nodiscard
function CD.projectedAge(r)
    if not r or not r.age then return nil end
    if not r.aged then return r.age end
    local dt = getGameTime():getWorldAgeHours() - r.aged
    if dt <= 0 then return r.age end
    return r.age + dt * CD.foodRotSpeed() / 24
end

---Fixes records from older saves: drops live animals and stamps the current world hour on aged food without one.
---@param records table[]|nil bag records, changed in place
function CD.bagStampLegacy(records)
    if not records then return end
    CD.bagPurgeLive(records)
    local now = getGameTime():getWorldAgeHours()
    for _, r in ipairs(records) do
        if r.age and not r.aged then
            r.aged = now
        end
    end
end

local liveTypeMemo = {}

---@param records table[]|nil bag records; those of a live animal item are removed in place
function CD.bagPurgeLive(records)
    if not records then return end
    local dropped = 0
    for i = #records, 1, -1 do
        local r = records[i]
        local t = r and r.t
        if t then
            local live = liveTypeMemo[t]
            if live == nil then
                live = CD.isLiveAnimalItem(instanceItem(t))
                liveTypeMemo[t] = live
            end
            if live then
                table.remove(records, i)
                dropped = dropped + 1
            end
        end
    end
    if dropped > 0 and CD.log then
        CD.log(string.format("[CD-BAG] descartado(s) %d registro(s) de animal vivo de bolsa antiga", dropped))
    end
end

---Light item for the bag list: only age, cooked, burnt and name come from the record.
---@param r table|nil bag record
---@return InventoryItem|nil nil for a missing type or a live animal
---@nodiscard
function CD.bagDisplayItem(r)
    if not r or not r.t then return nil end
    local it = instanceItem(r.t)
    if not it then return nil end
    if CD.isLiveAnimalItem(it) then return nil end
    if r.age then
        it:setAge(CD.projectedAge(r) or r.age)
    end
    if r.cooked then
        it:setCooked(true)
    end
    if r.burnt then
        it:setBurnt(true)
    end
    if r.name then
        it:setName(r.name)
        if r.custom then
            it:setCustomName(true)
        end
    end
    return it
end

---Food state code: f fresh, s stale, r rotten or b burnt, plus c when cooked and z when frozen; empty string for anything else.
---@param it InventoryItem|nil
---@return string
---@nodiscard
function CD.itemStateKey(it)
    if not it or not instanceof(it, "Food") then return "" end
    local k = "f"
    if it:isBurnt() then k = "b"
    elseif it:isRotten() then k = "r"
    elseif not it:isFresh() then k = "s"
    end
    if it:isCooked() then
        k = k .. "c"
    end
    if it:isFrozen() then
        k = k .. "z"
    end
    return k
end

---Flat record of everything the bag must keep about the item; nil for a live animal item.
---@param it InventoryItem
---@return table|nil record
---@nodiscard
function CD.serializeItem(it)
    if CD.isLiveAnimalItem(it) then return nil end
    local r = { t = it:getFullType() }
    r.w = CD.itemWeight(it)
    local nm = it:getDisplayName()
    local custom = it:isCustomName()
    local si = it:getScriptItem()
    local def = si and si:getDisplayName()
    if nm and nm ~= "" and (custom or (def and nm ~= def)) then
        r.name = nm
        if custom then
            r.custom = true
        end
    end
    r.cond = it:getCondition()
    if it:hasSharpness() then
        r.sharp = it:getSharpness()
    end
    -- B42 nao tem getUsedDelta() (so o setter): le o preenchimento por getCurrentUsesFloat().
    if instanceof(it, "DrainableComboItem") then
        r.delta = it:getCurrentUsesFloat()
    end
    -- FluidInstance nao esta exposta ao Lua: indexar metodo dela lanca excecao Java, que nao vira erro de Lua.
    local fc = it:getFluidContainer()
    if fc then
        local fl = {}
        local s = fc:createFluidSample()
        if s then
            local total = s:getAmount()
            for i = 0, s:size() - 1 do
                local f = s:getFluid(i)
                if f then
                    local a = fc:getSpecificFluidAmount(f)
                    if a <= 0 then
                        a = s:getPercentage(i) * total
                    end
                    if a > 0 then
                        fl[#fl + 1] = { f = f:getFluidTypeString(), a = a }
                    end
                end
            end
            s:release()
        end
        r.fluids = fl
    end
    if instanceof(it, "Food") then
        r.hung = it:getHungerChange()
        r.age = it:getAge()
        r.aged = getGameTime():getWorldAgeHours()
        if it:isCooked() then
            r.cooked = true
        end
        if it:isBurnt() then
            r.burnt = true
        end
    end
    local ammo = it:getCurrentAmmoCount()
    if ammo ~= 0 then
        r.ammo = ammo
    end
    if instanceof(it, "HandWeapon") then
        if it:isRoundChambered() then
            r.chamber = true
        end
        if it:isContainsClip() then
            r.clip = true
        end
    end
    if instanceof(it, "HandWeapon") then
        local parts = it:getAllWeaponParts()
        if parts and parts:size() > 0 then
            local list = {}
            for i = 0, parts:size() - 1 do
                local p = parts:get(i)
                if p then
                    list[#list + 1] = CD.serializeItem(p)
                end
            end
            if #list > 0 then
                r.parts = list
                r.clipsz = it:getClipSize()
            end
        end
    end
    local kid = it:getKeyId()
    if kid >= 0 then
        r.key = kid
    end
    if instanceof(it, "Key") then
        local n = it:getNumberOfKey()
        if n ~= 0 then
            r.keyn = n
        end
    end
    local media = it:getRecordedMediaIndex()
    if media ~= -1 then
        r.media = media
    end
    local rep = it:getHaveBeenRepaired()
    if rep ~= 0 then
        r.repaired = rep
    end
    if instanceof(it, "Literature") then
        local pages
        for i = 1, it:getNumberOfPages() do
            local t = it:seePage(i)
            if t and t ~= "" then
                pages = pages or {}
                pages[i] = t
            end
        end
        if pages then
            r.pages = pages
            r.canwrite = it:canBeWrite()
        end
        if it:getLockedBy() then
            r.locked = it:getLockedBy()
        end
    end
    if instanceof(it, "Clothing") then
        local c = {}
        local bl = it:getBloodlevel()
        if bl > 0 then
            c.blood = bl
        end
        local dt = it:getDirtiness()
        if dt > 0 then
            c.dirt = dt
        end
        local wet = it:getWetness()
        if wet > 0 then
            c.wet = wet
        end
        local v = it:getVisual()
        if v then
            local tex = v:getBaseTexture()
            if tex ~= -1 then
                c.tex = tex
            end
            local texc = v:getTextureChoice()
            if texc ~= -1 then
                c.texc = texc
            end
            local holes, blood, dirt
            for i = 0, 17 do
                local part = BloodBodyPartType.FromIndex(i)
                if v:getHole(part) > 0 then
                    holes = holes or {}
                    holes[i + 1] = true
                end
                local b = v:getBlood(part)
                if b > 0 then
                    blood = blood or {}
                    blood[i + 1] = b
                end
                local d = v:getDirt(part)
                if d > 0 then
                    dirt = dirt or {}
                    dirt[i + 1] = d
                end
            end
            if holes then
                c.holes = holes
            end
            if blood then
                c.pblood = blood
            end
            if dirt then
                c.pdirt = dirt
            end
        end
        if it:getPatchesNumber() > 0 then
            local patches
            for i = 0, 17 do
                local p = it:getPatchType(BloodBodyPartType.FromIndex(i))
                if p then
                    patches = patches or {}
                    patches[#patches + 1] = { part = i, lvl = p.tailorLvl, fab = p:getFabricType(), hole = p.hasHole == true, cg = p.conditionGain }
                end
            end
            if patches then
                c.patches = patches
            end
        end
        local any = false
        for _ in pairs(c) do
            any = true
            break
        end
        if any then
            r.cloth = c
        end
    end
    local md = it:getModData()
    if md then
        local any = false
        for _ in pairs(md) do
            any = true
            break
        end
        if any then
            r.md = CD.deepCopy(md)
        end
    end
    return r
end

---@param container ItemContainer|nil
---@return table[] records empty when container is nil
---@nodiscard
function CD.serializeBag(container)
    local out = {}
    if not container then return out end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            local r = CD.serializeItem(it)
            if r then
                out[#out + 1] = r
            end
        end
    end
    return out
end

---First item of this full type lying on the square or inside a container on it.
---@param sq IsoGridSquare|nil
---@param ftype string|nil full type
---@return InventoryItem|nil item
---@return ItemContainer|nil container nil when the item lies on the floor
---@return IsoObject|nil holder the world item, or the object that owns the container
---@nodiscard
function CD.sniffItemAtSquare(sq, ftype)
    if not sq or not ftype then return nil end
    local wobs = sq:getWorldObjects()
    if wobs then
        for i = 0, wobs:size() - 1 do
            local wo = wobs:get(i)
            local it = wo and wo:getItem()
            if it and it:getFullType() == ftype then return it, nil, wo end
        end
    end
    local objs = sq:getObjects()
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local cont = o and o:getContainer()
            if cont then
                local items = cont:getItems()
                for j = 0, items:size() - 1 do
                    local it = items:get(j)
                    if it and it:getFullType() == ftype then return it, cont, o end
                end
            end
        end
    end
    return nil
end

---@param sq IsoGridSquare|nil
---@param ftype string|nil full type
---@return IsoObject|nil holder the world item, or the object that owns the container
---@nodiscard
function CD.sniffHolderAtSquare(sq, ftype)
    local it, _, holder = CD.sniffItemAtSquare(sq, ftype)
    return it and holder or nil
end
