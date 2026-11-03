CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@param item InventoryItem|nil
---@param breedKey string|nil breed whose diet decides; nil uses the base diet
---@return boolean
---@nodiscard
function CD.isBadDogFood(item, breedKey)
    if not item then return false end
    if not instanceof(item, "Food") then return false end
    local diet = CD.dietFor(breedKey)

    local ft = item:getFoodType()
    if ft and diet.bad[ft] then return true end

    local t = item:getType()
    if t then
        local lt = string.lower(t)
        for _, part in ipairs(diet.badParts) do
            if string.find(lt, part, 1, true) then
                local innocent = (part == "grape" and string.find(lt, "grapefruit", 1, true))
                    or (part == "dough" and string.find(lt, "doughnut", 1, true))
                if not innocent then
                    return true
                end
            end
        end
    end
    return false
end

CD.PROTEIN_FOOD_TYPES = {
    Meat = true, Beef = true, Poultry = true, Game = true, Sausage = true, Bacon = true,
    Fish = true, Seafood = true, Roe = true, Egg = true, Insect = true, Venison = true,
    DogFood = true, CatFood = true,
}
CD.PROTEIN_NAME_PARTS = {
    "meat", "steak", "chicken", "fillet", "jerky", "bacon", "ham", "fish", "sausage", "egg", "venison",
    "mussel", "burger", "corndog",
}

CD.PROTEIN_MIN_GRAMS = 1
CD.PROTEIN_CARB_MAX_RATIO = 0.15

CD.NON_PROTEIN_FOOD_TYPES = {
    Bean = true, Berry = true, Bread = true, Candy = true, Cheese = true, Chocolate = true,
    Citrus = true, Cocoa = true, Coffee = true, Dressing = true, Fruits = true, Greens = true,
    Herb = true, HotPepper = true, Juice = true, Milk = true, Mushroom = true, NoExplicit = true,
    Nut = true, Oil = true, Pasta = true, Rice = true, Seed = true, Stock = true, Sugar = true,
    Tea = true, Thickener = true, Vegetable = true, Vegetables = true,
}

---@param item InventoryItem|nil
---@param breedKey string|nil breed whose diet decides; nil uses the base diet
---@return boolean
---@nodiscard
function CD.isProteinFood(item, breedKey)
    if not item then return false end
    if not instanceof(item, "Food") then return false end
    if item:isRotten() then return false end
    if CD.isBadDogFood(item, breedKey) then return false end
    local diet = CD.dietFor(breedKey)

    local ft = item:getFoodType()
    if ft and diet.protein[ft] then return true end

    local t = item:getType()
    if t then
        local lt = string.lower(t)
        for _, part in ipairs(diet.proteinParts) do
            if string.find(lt, part, 1, true) then
                -- "ham" mora dentro de chamomile e de graham, "burger" e "ham" dentro do pao
                -- BunsHamburger, e "egg" dentro de eggplant.
                local innocent = (part == "ham" and (string.find(lt, "chamomile", 1, true)
                        or string.find(lt, "graham", 1, true)
                        or string.find(lt, "buns", 1, true)))
                    or (part == "burger" and string.find(lt, "buns", 1, true))
                    or (part == "egg" and string.find(lt, "eggplant", 1, true))
                if not innocent then
                    return true
                end
            end
        end
    end

    -- Bicho inteiro de armadilha (esquilo, passaro, rato, coelho) e peixe cru por especie nao
    -- declaram FoodType nem carregam "meat" no nome. Sobra a nutricao, dentro do que o jogo marca
    -- como perigoso cru: proteina alta com carboidrato perto de zero e carne. Sem a marca de cru,
    -- panela de arroz, ramen e tortilha tambem entrariam, que declaram proteina e zero carboidrato.
    if item:isbDangerousUncooked() and not (ft and diet.nonProtein[ft]) then
        local prot = item:getProteins()
        if prot >= CD.PROTEIN_MIN_GRAMS and item:getCarbohydrates() <= prot * CD.PROTEIN_CARB_MAX_RATIO then
            return true
        end
    end

    if ft and ft ~= "" and not diet.nonProtein[ft] then
        CD.unknownFoodTypes = CD.unknownFoodTypes or {}
        local seen = tostring(breedKey) .. "/" .. ft
        if not CD.unknownFoodTypes[seen] then
            CD.unknownFoodTypes[seen] = true
            CD.log("FoodType fora das tabelas de proteina: " .. tostring(ft) ..
                " (item " .. tostring(item:getType()) .. "), tratado como nao-carne")
        end
    end
    return false
end

-- A alergia alimentar e por familia de carne, nao por item: quem passa mal com frango passa mal
-- com qualquer frango. Familias proximas caem na mesma linha, e o que o jogo nao classifica vira
-- carne generica.
CD.PROTEIN_GROUPS = {
    DogFood = "DogFood", CatFood = "DogFood",
    Poultry = "Poultry", Beef = "Beef", Venison = "Venison", Game = "Game",
    Fish = "Fish", Seafood = "Fish", Roe = "Fish",
    Sausage = "Sausage", Bacon = "Pork", Egg = "Egg", Insect = "Insect",
}

---Which protein family a meal belongs to, for the food allergy. Nil when it is not meat at all.
---@param item InventoryItem|nil
---@param breedKey string|nil breed whose diet decides; nil uses the base diet
---@return string|nil group
---@nodiscard
function CD.vetProteinGroup(item, breedKey)
    if not CD.isProteinFood(item, breedKey) then return nil end
    local ft = item:getFoodType()
    if ft == nil or ft == "" then return "Meat" end
    return CD.PROTEIN_GROUPS[ft] or "Meat"
end

---@param item InventoryItem|nil
---@param breedKey string|nil breed whose diet decides; nil uses the base diet
---@return boolean
---@nodiscard
function CD.isTroughFood(item, breedKey)
    if not item then return false end
    if instanceof(item, "Food") and item:isRotten() then return false end
    local diet = CD.dietFor(breedKey)
    local ft0 = item:getFullType()
    if ft0 and diet.troughItems[ft0] then return true end
    local aft = item:getAnimalFeedType()
    if aft and aft ~= "" and diet.trough[aft] then return true end
    if instanceof(item, "Food") then
        local ftype = item.getFoodType and item:getFoodType()
        if ftype and diet.trough[ftype] then return true end
    end
    return false
end

---Portion the dog takes for this need, clamped between FEED_MIN_BITE and the whole item.
---@param food InventoryItem
---@param need number|nil hunger to fill, in hunger change units; nil eats the whole item
---@return table bite { hunger, thirst, partialFrac }, or { fallback = true, hunger } when the item does not feed
---@nodiscard
function CD.computeBite(food, need)
    if not instanceof(food, "Food") then return { fallback = true, hunger = 0 } end
    local foodVal = -food:getHungerChange()
    if foodVal <= 0 then
        return { fallback = true, hunger = food:getHungerChange() }
    end
    local consumed = need or foodVal
    if consumed < 0 then
        consumed = 0
    end
    local minBite = math.min(foodVal, CD.FEED_MIN_BITE)
    if consumed < minBite then
        consumed = minBite
    end
    if consumed > foodVal then
        consumed = foodVal
    end
    local partialFrac
    if foodVal - consumed >= 0.01 then
        partialFrac = consumed / foodVal
    end
    local thirstBite
    local thirstVal = -food:getThirstChange()
    if thirstVal > 0 then
        thirstBite = -(thirstVal * (consumed / foodVal))
    end
    return { hunger = -consumed, thirst = thirstBite, partialFrac = partialFrac }
end
