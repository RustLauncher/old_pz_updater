-- Optional integration with TwisTonFire - DuffleBag (twistdufflebag).
-- Uses its models and vanilla conversion action; no third-party assets bundled.
if not getActivatedMods():contains("twistdufflebag") then return end
require "TTF_DuffelLowerBack_ScriptBodyLocationPatch"
require "TTF_DuffelLowerBack_ScriptManager"
local Mod = TTF_DuffelLowerBack
local module = "BolsasEspecialidades"
local types = { "Bag_Mecanica", "Bag_Pesca", "Bag_Caca", "Bag_Firearms", "Bag_Carpintaria" }
for _, name in ipairs(types) do
    local normal, lower = module .. "." .. name, module .. "." .. name .. "_LowerBack"
    local found = false
    for _, pair in ipairs(Mod.BagPairs) do
        if pair.normal == normal and pair.lower == lower then found = true; break end
    end
    if not found then table.insert(Mod.BagPairs, {normal = normal, lower = lower}) end
    Mod.NormalToLower[normal] = lower
    Mod.NormalToLower[name] = lower
    Mod.LowerToNormal[lower] = normal
    Mod.LowerToNormal[name .. "_LowerBack"] = normal
    Mod.NormalTypes[normal] = true
    Mod.NormalTypes[name] = true
    Mod.LowerTypes[lower] = true
    Mod.LowerTypes[name .. "_LowerBack"] = true
end
local function applyCompatibility()
    local sm = ScriptManager.instance
    for _, name in ipairs(types) do
        local normalType = module .. "." .. name
        local lowerType = normalType .. "_LowerBack"
        local normal, lower = sm:FindItem(normalType), sm:FindItem(lowerType)
        if normal and lower then
            lower:DoParam("CanBeEquipped = ttf:lowerback")
            lower:DoParam("BodyLocation = ttf:lowerback")
            lower:setDisplayName(normal:getDisplayName())
            normal:DoParam("ClothingItemExtra = " .. lowerType)
            normal:DoParam("ClothingItemExtraOption = LowerBack")
            normal:DoParam("ClothingExtraSubmenu = OnBack")
            lower:DoParam("ClothingItemExtra = " .. normalType)
            lower:DoParam("ClothingItemExtraOption = OnBack")
            lower:DoParam("ClothingExtraSubmenu = LowerBack")
        end
    end
    print("[BolsasEspecialidades] TwisTonFire lower-back compatibility: " .. #types .. " bags.")
end
Events.OnGameBoot.Add(applyCompatibility)
