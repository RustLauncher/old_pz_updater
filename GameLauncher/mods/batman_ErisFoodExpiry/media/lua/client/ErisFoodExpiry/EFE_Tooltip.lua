-- ============================================================================
-- Eris Food Expiry (batman fork) — tooltip lines through TooltipLib
-- ============================================================================

require "TooltipLib/Core"
require "ErisFoodExpiry/EFE_Core"
require "ErisFoodExpiry/EFE_Options"

if not TooltipLib or type(TooltipLib.registerProvider) ~= "function" then
    print("[ErisFoodExpiry] TooltipLib missing: no expiry lines in tooltips")
    return
end

local EFE = ErisFoodExpiry

local LABEL = { 1, 1, 0.8, 1 }
local VALUE = { 0.9, 0.9, 0.9, 1 }
local MUTED = { 0.65, 0.65, 0.65, 1 }

-- Rotten food: when the sandbox Rotten Food Removal will delete it.
local function addRemoval(ctx, item)
    local removal = EFE.removalDays(item)
    if removal then
        ctx:addKeyValue(getText("UI_EFE_RemovedIn"), EFE.formatDays(removal), LABEL, VALUE)
    end
end

TooltipLib.registerProvider({
    id = "batman_ErisFoodExpiry",
    target = "item",
    description = "UI_EFE_TooltipProvider",
    enabled = function(item)
        return instanceof(item, "Food")
    end,
    callback = function(ctx)
        local item = ctx.item
        if not EFE.canAge(item) then
            ctx:addLabel(getText("UI_EFE_NeverPerish"), MUTED)
            return
        end
        local color = EFE.COLORS[EFE.stage(item)]
        ctx:addProgress(getText("UI_EFE_Freshness"), EFE.freshFraction(item), LABEL, color)
        local character = ctx.tooltip and ctx.tooltip:getCharacter() or getSpecificPlayer(0)
        if not EFE.canReadExact(item, character, EFE.requireTrait()) then
            ctx:addLabel(getText(EFE.stateKey(item)), color)
            if EFE.stage(item) == "rotten" then addRemoval(ctx, item) end
            return
        end
        if item:isFrozen() then
            local thaw = EFE.thawDays(item)
            if thaw == nil then
                ctx:addLabel(getText("UI_EFE_Frozen"), VALUE)
                return
            end
            ctx:addKeyValue(getText("UI_EFE_ThawedIn"), EFE.formatDays(thaw), LABEL, VALUE)
        end
        local age = item:getAge()
        if age >= item:getOffAgeMax() then
            ctx:addLabel(getText("UI_EFE_StateRotten"), color)
            addRemoval(ctx, item)
            return
        end
        local rotten = EFE.daysUntil(item, item:getOffAgeMax())
        if rotten == nil then
            ctx:addLabel(getText("UI_EFE_Paused"), VALUE)
            return
        end
        if age < item:getOffAge() then
            ctx:addKeyValue(getText("UI_EFE_StaleIn"), EFE.formatDays(EFE.daysUntil(item, item:getOffAge())), LABEL, VALUE)
        end
        ctx:addKeyValue(getText("UI_EFE_RottenIn"), EFE.formatDays(rotten), LABEL, VALUE)
    end,
})
