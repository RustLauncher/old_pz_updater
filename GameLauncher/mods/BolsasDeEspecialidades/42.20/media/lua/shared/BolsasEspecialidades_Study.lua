require "BolsasEspecialidades_Core"
local BE = BolsasEspecialidades
BE.tailoringLevel = 3
BE.studyRecipes = {
    "SewSpecialtyBagMecanica",
    "SewSpecialtyBagPesca",
    "SewSpecialtyBagCaca",
    "SewSpecialtyBagFirearms",
    "SewSpecialtyBagCarpintaria",
}

function BE.isStudyBag(item)
    if not item or not instanceof(item, "InventoryContainer") then return false end
    local studyType = item:getFullType():gsub("_LowerBack$", "")
    if BE.pools[studyType] then return true end
    -- Vanilla bags/backpacks; excludes purses, sacks and other generic containers.
    return item:getModule() == "Base" and string.sub(item:getType(), 1, 4) == "Bag_"
end

function BE.knowsBagRecipes(character)
    local known = character:getKnownRecipes()
    for _, recipe in ipairs(BE.studyRecipes) do
        if not known:contains(recipe) then return false end
    end
    return true
end

function BE.studyBlockReason(character, item)
    if not BE.isStudyBag(item) then return "ContextMenu_BE_InvalidBag" end
    if BE.knowsBagRecipes(character) then return "ContextMenu_BE_AlreadyKnown" end
    if not character:getInventory():contains(item) then return "ContextMenu_BE_TakeBag" end
    if character:getPerkLevel(Perks.Tailoring) < BE.tailoringLevel then return "ContextMenu_BE_NeedTailoring" end
    if character:tooDarkToRead() then return "ContextMenu_BE_NeedLight" end
    return nil
end
