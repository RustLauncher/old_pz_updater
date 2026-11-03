require "UsefulPallets/Config"

UsefulPalletsRecipes = UsefulPalletsRecipes or {}

local function initializeItem(pallet, kind)
    -- Recipes resolve script items, so create the vanilla template first.
    -- Sprite initialization makes it the same furniture as native pickup.
    if not pallet or not instanceof(pallet, "Moveable")
        or not pallet:ReadFromWorldSprite(UsefulPallets.emptySprites[kind]) then
        error("Useful Pallets could not initialize crafted " .. kind .. " pallet")
    end
end

function UsefulPalletsRecipes.construction(data, character)
    initializeItem(data:getFirstCreatedItem(), "construction")
end

function UsefulPalletsRecipes.military(data, character)
    initializeItem(data:getFirstCreatedItem(), "military")
end

local kinds = {UP_MakePallet = "construction", UP_MakeMilitaryPallet = "military"}

function UsefulPalletsRecipes.kind(recipe)
    return recipe and recipe.getName and kinds[recipe:getName()] or nil
end

function UsefulPalletsRecipes.prepareOutputs(recipe, items)
    local kind = UsefulPalletsRecipes.kind(recipe)
    if not kind then return end
    for i = 0, items:size() - 1 do initializeItem(items:get(i), kind) end
end
