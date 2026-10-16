CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@param item InventoryItem|nil
---@param breedKey string|nil breed whose diet decides; nil uses the base diet
---@return boolean
---@nodiscard
function CD.isBowlFood(item, breedKey)
    if not item then return false end
    if CD.isTroughFood(item, breedKey) then return true end
    return instanceof(item, "Food") and not item:isRotten() and item:getHungerChange() < 0
end

---@param fullType string|nil
---@return boolean
---@nodiscard
function CD.isDishType(fullType)
    return fullType == CD.DISH_TYPE
end

---Bowl meal points for the food: its hunger value in hundredths, at least 1.
---@param item Food
---@return integer
---@nodiscard
function CD.dishMealsForFood(item)
    local hc = item:getHungerChange()
    local points = math.floor((math.abs(hc) * 100) + 0.5)
    if points < 1 then
        points = 1
    end
    return points
end

---Real water (sink, bottle) the player poured into the bowl before dropping it on the ground. The
---stock the dog drinks from lives in the ModData, so the model refresh used to throw that fluid away
---with no warning; here it becomes stock. A bowl filled to the brim yields a full deposit, and water
---the game tainted stays tainted. A bowl from an old save does not carry the script whitelist (the
---engine keeps that list inside the item itself), so it goes on accepting sink water and relies on this.
---@param item InventoryItem|nil
---@return boolean credited
function CD.absorbRealWater(item)
    if not item then return false end
    local md = item:getModData()
    if (md.cdFoodMeals or 0) > 0 or (md.cdWater or 0) > 0 then return false end
    local fc = item:getFluidContainerFromSelfOrWorldItem()
    if not fc or fc:isEmpty() then return false end
    if fc:isPrimaryFluidType(CD.DISH_FLUID_WATER) or fc:isPrimaryFluidType(CD.DISH_FLUID_FOOD) then
        return false
    end
    local cap = fc:getCapacity()
    if cap <= 0 then return false end
    local pts = math.floor((fc:getAmount() / cap) * CD.DISH_MAX_WATER + 0.5)
    if pts < 1 then return false end
    md.cdWater = math.min(pts, CD.DISH_MAX_WATER)
    if fc:isPoisonous() then
        md.cdWaterTainted = 1
    else
        md.cdWaterTainted = nil
    end
    return true
end

---Matches the bowl's model and fluid to the stock in its ModData.
---@param item InventoryItem|nil the bowl
---@param localOnly boolean|nil true skips the network sync
function CD.refreshDishModel(item, localOnly)
    if not item then return end
    local md = item:getModData()
    local want
    if (md.cdFoodMeals or 0) > 0 then want = "food"
    elseif (md.cdWater or 0) > 0 then want = "water"
    else want = "empty" end
    -- o indice tem que ser normalizado ANTES de qualquer early-return: a engine SORTEIA o modelIndex de quem
    -- declara WorldStaticModelsByIndex, entao uma tigela recem-craftada nasce com o modelo errado
    local idx = CD.DISH_MODEL_FOOD
    if want == "water" then
        idx = CD.DISH_MODEL_WATER
    end
    local idxChanged = item:getModelIndex() ~= idx
    if idxChanged then
        item:setModelIndex(idx)
    end
    local fc = item:getFluidContainerFromSelfOrWorldItem()
    if not fc then
        md.cdVisual = want
        return
    end
    local applied = false
    local empty = fc:isEmpty()
    if want == "empty" then applied = (md.cdVisual == "empty") and empty
    else applied = (md.cdVisual == want) and (not empty) end
    if applied and not idxChanged then return end
    if not applied then
        fc:removeFluid()
        if want ~= "empty" then
            local fluidName = (want == "food") and CD.DISH_FLUID_FOOD
                or CD.DISH_FLUID_WATER
            fc:addFluid(fluidName, fc:getCapacity())
        end
    end
    local wo = item:getWorldItem()
    if wo then
        local rsq = wo:getRenderSquare()
        if rsq then
            rsq:invalidateRenderChunkLevel(68)
        end
        if not localOnly then
            wo:sync()
        end
    elseif not localOnly then
        item:syncItemFields()
    end
    md.cdVisual = want
end
