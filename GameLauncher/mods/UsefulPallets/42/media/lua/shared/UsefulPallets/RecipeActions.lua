require "UsefulPallets/Recipes"
require "Entity/TimedActions/ISHandcraftAction"

local original = ISHandcraftAction.performRecipe
function ISHandcraftAction:performRecipe()
    if not UsefulPalletsRecipes.kind(self.craftRecipe) then return original(self) end
    if not self.logic or not self.logic:performCurrentRecipe() then return end
    local items = ArrayList.new()
    self.logic:getCreatedOutputItems(items)
    -- Initialize before native add/drop chooses by weight or serializes an item.
    UsefulPalletsRecipes.prepareOutputs(self.craftRecipe, items)
    for i = 0, items:size() - 1 do Actions.addOrDropItem(self.character, items:get(i)) end
    local data = self.logic:getRecipeData()
    data:luaCallOnCreate(self.character)
    data:processDestroyAndUsedItems(self.character)
    -- Preserve vanilla's consumed-material provenance on the single output.
    if items:size() == 1 then
        local modData = items:get(0):getModData()
        local used = data:getAllConsumedItems()
        for i = 0, used:size() - 1 do
            local itemType = used:get(i):getFullType()
            modData[itemType] = (modData[itemType] or 0) + 1
        end
    end
end
