-- IG_recipecode.lua

-- Returns the recipe output AND returns the roasting pan back to the inventory
function ImprovisedGlass_GiveBackRoastingPan(recipe, ingredients, result, player)
    if not player then return end
    local inv = player:getInventory()
    if inv then
        inv:AddItem("Base.RoastingPan")
    end
end

-- Returns the recipe output AND returns a glass pane back to the inventory
function ImprovisedGlass_GiveBackGlassPane(recipe, ingredients, result, player)
    if not player then return end
    local inv = player:getInventory()
    if inv then
        inv:AddItem("Base.GlassPane")
    end
end

-- Global functions for OnGiveXP callbacks in B42

function ImprovisedGlass_XPMakeWindowWood(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.Woodwork, 10)
    end
end

function ImprovisedGlass_XPDestroyWindowWood(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.Woodwork, 5)
    end
end

function ImprovisedGlass_XPMakeWindowMetal(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.MetalWelding, 10)
    end
end

function ImprovisedGlass_XPDestroyWindowMetal(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.MetalWelding, 5)
    end
end

function ImprovisedGlass_XPMakeGlass(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.Cooking, 1)
    end
end

function ImprovisedGlass_XPMakeWindshieldCar(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.Mechanics, 10)
    end
end

function ImprovisedGlass_XPMakeWindowCar(recipe, ingredients, result, player)
    if player and player:getXp() then
        player:getXp():AddXP(Perks.Mechanics, 5)
    end
end