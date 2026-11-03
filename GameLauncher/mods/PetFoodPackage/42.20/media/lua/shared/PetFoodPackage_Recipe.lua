Recipe = Recipe or {}
Recipe.OnCreate = Recipe.OnCreate or {}

local function oldestFoodAge(items)
    local oldestAge = 0
    if not items then
        return oldestAge
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and instanceof(item, "Food") then
            local age = item:getAge() or 0
            if age > oldestAge then
                oldestAge = age
            end
        end
    end

    return oldestAge
end

local function applyFoodAge(items, age)
    if not items then
        return
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and instanceof(item, "Food") then
            item:setAge(age)
            item:syncItemFields()
        end
    end
end

function Recipe.OnCreate.PetFoodPackage_PreserveOldestAge(craftRecipeData, character)
    local consumed = craftRecipeData:getAllConsumedItems()
    local created = craftRecipeData:getAllCreatedItems()
    applyFoodAge(created, oldestFoodAge(consumed))
end
