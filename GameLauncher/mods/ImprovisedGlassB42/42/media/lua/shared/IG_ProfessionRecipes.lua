-- On Player Load, check their professions and add free recipes

local function learnRecipe(player, recipeName)
    if not player or not recipeName then return end

    if player.getKnownRecipes then
        local knownRecipes = player:getKnownRecipes()
        if knownRecipes and knownRecipes.add then
            if not (knownRecipes.contains and knownRecipes:contains(recipeName)) then
                knownRecipes:add(recipeName)
            end
        end
    end
end

function IGAddRecipesToExistingPlayers(id, playerObj)
    local player = playerObj or id
    if not player or not player.getDescriptor then return end

    local descriptor = player:getDescriptor()
    if not descriptor or not descriptor.getProfession then return end

    local profession = descriptor:getProfession()

    -- Engineers know glass smelting
    if profession == "engineer" then
        learnRecipe(player, "IGPrepareGlassShards")
        learnRecipe(player, "IGUnprepareGlassShards")
        learnRecipe(player, "IGRemoveGlassPane")
    end

    -- Carpenters know wooden window frames
    if profession == "carpenter" then
        learnRecipe(player, "IGCraftWoodenWindowSingle")
        learnRecipe(player, "IGCraftWoodenWindowDouble")
        learnRecipe(player, "IGCraftWoodenWindowTriple")
        learnRecipe(player, "IGCraftWoodenWindowWhite")
        learnRecipe(player, "IGCraftWoodenWindowLarge")
    end   

    -- Mechanics know vehicle glass cutting
    if profession == "mechanics" then
        learnRecipe(player, "IGWindshield1")
        learnRecipe(player, "IGWindshield2")
        learnRecipe(player, "IGWindshield3")
        learnRecipe(player, "IGRearWindshield1")
        learnRecipe(player, "IGRearWindshield2")
        learnRecipe(player, "IGRearWindshield3")
        learnRecipe(player, "IGFrontWindow1")
        learnRecipe(player, "IGFrontWindow2")
        learnRecipe(player, "IGFrontWindow3")
        learnRecipe(player, "IGRearWindow1")
        learnRecipe(player, "IGRearWindow2")
        learnRecipe(player, "IGRearWindow3")
    end

    -- Metalworkers know metal window framing
    if profession == "metalworker" then
        learnRecipe(player, "IGCraftMetalWindow")
    end

    -- Construction workers know glass smelting
    if profession == "constructionworker" then
        learnRecipe(player, "IGPrepareGlassShards")
        learnRecipe(player, "IGUnprepareGlassShards")
        learnRecipe(player, "IGRemoveGlassPane")
    end
end

Events.OnCreatePlayer.Add(IGAddRecipesToExistingPlayers)