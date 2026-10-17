-- Native outfit naming is opt-in and only used for XML-backed recipe profiles.
-- The original HWE costume and visual recipes remain authoritative fallbacks.
local HWE = HalloweenEvent
local byNativeName = {}
local count = 0
for _, costume in ipairs(HWE.Costumes or {}) do
    if costume.visualItems and #costume.visualItems > 0 then
        costume.nativeOutfit = "HWE_Native_" .. costume.id
        byNativeName[costume.nativeOutfit] = costume
        count = count + 1
    else
        -- Original vanilla outfits already have a native PersistentOutfits ID.
        costume.nativeOutfit = costume.outfit
    end
end
HWE.NativeOutfits = {byName = byNativeName, customCount = count,
    fromName = function(name) return byNativeName[tostring(name or "")] end}
return HWE.NativeOutfits
