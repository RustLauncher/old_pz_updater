-- ============================================================================
-- Eris Food Expiry (batman fork) — mod options
-- Names and tooltips are translation keys: MainOptions translates them.
-- ============================================================================

require "ErisFoodExpiry/EFE_Core"

local EFE = ErisFoodExpiry

if not EFE.options and PZAPI and PZAPI.ModOptions then
    EFE.options = PZAPI.ModOptions:create("batman_ErisFoodExpiry", "UI_EFE_Title")
    EFE.options:addTickBox("RequireTrait", "UI_EFE_RequireTrait", false, "UI_EFE_RequireTrait_tooltip")
end

function EFE.requireTrait()
    local option = EFE.options and EFE.options:getOption("RequireTrait")
    return option ~= nil and option:getValue() == true
end
