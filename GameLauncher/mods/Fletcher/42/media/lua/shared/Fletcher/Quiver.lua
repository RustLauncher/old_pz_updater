--[[
    Fletcher: the quivers. The Hip Quiver (Fletcher.HipQuiver, worn at fletcher:quiver) and the Back
    Quiver (0.7: Fletcher.BackQuiver, worn at fletcher:backquiver; both can be worn at once). Containers
    that take only arrows and bolts (their AcceptItemFunction). Ammo comes from the hip quiver first,
    then the back quiver, then the rest (client/Fletcher/Nock.lua F.pickArrows); loading is faster
    when the quiver it comes from holds the launcher's family (F.reloadFactor, shared/Fletcher/Gear.lua:
    F.QUIVER_SPEED from the hip, F.BACK_QUIVER_SPEED from the back).
]]

require "Fletcher/Core"
require "Fletcher/Gear"
local F = Fletcher

F.QUIVER = "Fletcher.HipQuiver"
F.BACK_QUIVER = "Fletcher.BackQuiver"

function F.isQuiverAmmo(item)
    return item ~= nil and F.ARROW_DEFS[item:getFullType()] ~= nil
end

-- The item script's AcceptItemFunction. Vanilla's server/Items/AcceptItemFunction.lua creates that
-- table after shared files load (wiping an entry made here), so it's registered again after it
-- (server/Fletcher/QuiverAccept.lua) and at boot.
function F.registerQuiverAccept()
    AcceptItemFunction = AcceptItemFunction or {}
    AcceptItemFunction.FletcherQuiver = function(container, item) return F.isQuiverAmmo(item) end
end
F.registerQuiverAccept()
Events.OnGameBoot.Add(function() F.registerQuiverAccept() end)

local quiverLocation
function F.wornQuiver(character)
    quiverLocation = quiverLocation or ItemBodyLocation.get(ResourceLocation.of("fletcher:quiver"))
    local it = character and character:getWornItem(quiverLocation)
    return it and it:getFullType() == F.QUIVER and it or nil
end

local backLocation
function F.wornBackQuiver(character)
    backLocation = backLocation or ItemBodyLocation.get(ResourceLocation.of("fletcher:backquiver"))
    local it = character and character:getWornItem(backLocation)
    return it and it:getFullType() == F.BACK_QUIVER and it or nil
end

--- The worn quivers, in the order ammo comes out of them (hip, then back)
function F.wornQuivers(character)
    local out = {}
    local h, b = F.wornQuiver(character), F.wornBackQuiver(character)
    if h then out[#out + 1] = h end
    if b then out[#out + 1] = b end
    return out
end

local function holds(q, family)
    local items = q:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local def = F.ARROW_DEFS[items:get(i):getFullType()]
        if def and def.family == family then return true end
    end
    return false
end

--- Which worn quiver the next arrow / bolt of this family comes out of: "hip", "back" or nil
function F.quiverFor(character, family)
    local h = F.wornQuiver(character)
    if h and holds(h, family) then return "hip" end
    local b = F.wornBackQuiver(character)
    if b and holds(b, family) then return "back" end
    return nil
end

--- Does a worn quiver hold ammo of this family (arrow / bolt)?
function F.quiverHolds(character, family)
    return F.quiverFor(character, family) ~= nil
end

return F
