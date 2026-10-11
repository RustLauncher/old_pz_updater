--[[
    Fletcher: which arrow gets nocked, and from where.

    Quiver first: vanilla's reload moves the rounds it needs into the main inventory
    (ISInventoryPaneContextMenu.transferBullets: the first ones found in any container, a bag before
    the quiver if the bag comes first). For our arrows and bolts it takes them from the worn Hip
    Quiver first, then the main inventory, then any other container.

    Choosing in the radial (client/Fletcher/Radial.lua): F.radialChooseArrow sets the preference (synced
    to the server: F.choosePreferredArrow) and, if a different arrow is nocked, takes it off and nocks
    the chosen one once the bow is empty (F.renock, watched every tick); an empty bow nocks it at once.
    Wrapped once (ISInventoryPaneContextMenu.fl_quiverFirst); the wrapper calls F.* by name.
]]

require "ISUI/ISInventoryPaneContextMenu"
require "Fletcher/Core"
require "Fletcher/Gear"
require "Fletcher/Quiver"
require "Fletcher/Reload"
local F = Fletcher

--- n items of an arrow / bolt type for a reload: the worn quivers' first (hip, then back), then the
--- main inventory's, then any other container's. An ArrayList, as vanilla's getSomeTypeRecurse.
function F.pickArrows(player, ammoType, n)
    local out = ArrayList.new()
    local function take(list)
        for i = 0, (list and list:size() or 0) - 1 do
            if out:size() >= n then return end
            local it = list:get(i)
            if not out:contains(it) then out:add(it) end
        end
    end
    for _, q in ipairs(F.wornQuivers(player)) do take(q:getInventory():getSomeType(ammoType, n)) end
    local inv = player:getInventory()
    take(inv:getSomeType(ammoType, n))
    if out:size() < n then take(inv:getAllTypeRecurse(ammoType)) end
    return out
end

if not ISInventoryPaneContextMenu.fl_quiverFirst then
    ISInventoryPaneContextMenu.fl_quiverFirst = true
    local transfer = ISInventoryPaneContextMenu.transferBullets
    ISInventoryPaneContextMenu.transferBullets = function(playerObj, ammoType, currentAmmo, maxAmmo)
        if not (F.ARROW_DEFS and F.ARROW_DEFS[ammoType or ""]) then
            return transfer(playerObj, ammoType, currentAmmo, maxAmmo)
        end
        local ammoCount = math.min(playerObj:getInventory():getItemCountRecurse(ammoType), maxAmmo - currentAmmo)
        if ammoCount <= 0 then return 0 end
        ISInventoryPaneContextMenu.transferIfNeeded(playerObj, F.pickArrows(playerObj, ammoType, ammoCount))
        return ammoCount
    end
end

-- swaps waiting for the bow to be empty: player -> { bow, untilMs }
F.renock = F.renock or {}
F.RENOCK_WAIT_MS = 15000

--- The radial's choice: arrowType (nil = best available) for this launcher's family
function F.radialChooseArrow(player, bow, arrowType)
    local family = F.familyOf(bow)
    F.choosePreferredArrow(player, arrowType, family)
    local want = F.arrowFor(player, bow)
    if bow:isRoundChambered() or bow:getCurrentAmmoCount() > 0 then
        local nocked = bow:getModData().fl_nocked or F.bowArrow(bow)
        if nocked == want or F.arrowCount(player, want) == 0 then return end
        -- take it off as the Unnock slice does: a nocked arrow is a chambered round (count 0), so
        -- vanilla's rack ejects it; an unload only acts on a count above 0
        if bow:getCurrentAmmoCount() > 0 then
            ISTimedActionQueue.add(ISUnloadBulletsFromFirearm:new(player, bow, false))
        else
            ISTimedActionQueue.add(ISRackFirearm:new(player, bow))
        end
        F.renock[player] = { bow = bow, untilMs = getTimestampMs() + F.RENOCK_WAIT_MS }
    elseif F.arrowCount(player, want) > 0 then
        F.prepareBowAmmo(player, bow)        -- point it at the choice now (the per-tick sync hasn't run yet)
        ISReloadWeaponAction.BeginAutomaticReload(player, bow)
    end
end

function F.onRenockTick()
    local now = getTimestampMs()          -- (Kahlua has no next(): pairs over an empty table is cheap)
    for player, st in pairs(F.renock) do
        local bow = st.bow
        if now > st.untilMs or player:isDead() or player:getPrimaryHandItem() ~= bow then
            F.renock[player] = nil
        elseif not bow:isRoundChambered() and bow:getCurrentAmmoCount() == 0
                and #ISTimedActionQueue.getTimedActionQueue(player).queue == 0 then
            F.renock[player] = nil
            F.prepareBowAmmo(player, bow)
            ISReloadWeaponAction.BeginAutomaticReload(player, bow)
        end
    end
end

Events.OnTick.Add(function() F.onRenockTick() end)     -- by name: reloads apply

return F
