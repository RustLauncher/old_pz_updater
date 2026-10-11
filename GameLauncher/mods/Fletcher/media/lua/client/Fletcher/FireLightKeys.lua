--[[
    Fletcher: quick ways to light a nocked fire arrow (0.6.1), besides the radial's Light Arrow slice.
      - Tap the reload key again (R, or RB on a controller): with an unlit fire arrow on the string,
        vanilla's tap would try to reload a bow that is already full (nothing happens); it lights the
        arrow instead. So: tap R to nock, tap R again to light.
      - A key of its own, "Light Fire Arrow" in Options > Mod Options > Fletcher (unbound by default:
        every letter key already has a vanilla binding).
    Wrapped once (ISReloadWeaponAction.fl_lightWrapped); the wrapper calls F.* by name.
]]

require "TimedActions/ISReloadWeaponAction"
require "Fletcher/Core"
require "Fletcher/FireLight"
local F = Fletcher

--- Light the arrow on this character's bow if there's an unlit fire arrow on it. True if queued.
function F.tryQuickLight(character)
    local bow = character and character:getPrimaryHandItem()
    if not (bow and F.canLightArrow and F.canLightArrow(character, bow)) then return false end
    if #ISTimedActionQueue.getTimedActionQueue(character).queue > 0 then return false end
    return F.queueLightArrow(character, bow)
end

if not ISReloadWeaponAction.fl_lightWrapped then
    ISReloadWeaponAction.fl_lightWrapped = true
    local begin = ISReloadWeaponAction.BeginAutomaticReload
    ISReloadWeaponAction.BeginAutomaticReload = function(playerObj, gun, ...)
        if gun and F.isBow and F.isBow(gun) and F.tryQuickLight(playerObj) then return end
        return begin(playerObj, gun, ...)
    end
end

-- the key of its own (Mod Options)
if PZAPI and PZAPI.ModOptions and not F.modOptions then
    F.modOptions = PZAPI.ModOptions:create("Fletcher", getText("IGUI_Fletcher_Name"))
    F.modOptions:addKeyBind("lightArrow", getText("UI_Fletcher_Option_LightArrowKey"), 0,
        getText("UI_Fletcher_Option_LightArrowKey_tooltip"))
end

function F.onLightKey(key)
    local opt = F.modOptions and F.modOptions:getOption("lightArrow")
    local bound = opt and opt:getValue()
    if not bound or bound == 0 or key ~= bound then return end
    local p = getSpecificPlayer(0)
    if p and not p:isDead() then F.tryQuickLight(p) end
end

Events.OnKeyPressed.Add(function(key) F.onLightKey(key) end)     -- by name: reloads apply

return F
