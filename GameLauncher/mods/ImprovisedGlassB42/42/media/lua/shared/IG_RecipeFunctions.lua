-- IG_RecipeFunctions.lua
-- OnCreate callbacks for Improvised Glass recipes in Build 42

function IG_UnprepareGlassShards_OnCreate(recipe, resultItem, player)
    if player and player:getInventory() then
        player:getInventory():AddItem("Base.RoastingPan")
    end
end

function IG_RemoveGlassPane_OnCreate(recipe, resultItem, player)
    if player and player:getInventory() then
        player:getInventory():AddItem("Base.RoastingPan")
    end
end

function ImprovisedGlass_GiveBackGlassPane(recipe, resultItem, player)
    if player and player:getInventory() then
        player:getInventory():AddItem("Base.GlassPane")
    end
end