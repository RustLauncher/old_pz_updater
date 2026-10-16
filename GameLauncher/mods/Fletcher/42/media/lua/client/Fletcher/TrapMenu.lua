--[[
    Crossbow tripwire trap: the right-click menu (the trap and the kneel, FletcherSetTrapAction:
    shared/Fletcher/Trap.lua).
]]
require "Fletcher/Trap"         -- (shared/Fletcher/Trap.lua)
local F = Fletcher

function F.queueSetTrap(player, bow)
    ISTimedActionQueue.add(FletcherSetTrapAction:new(player, bow))
end

--- Right-click a crossbow: "Set Tripwire Trap" (greyed out, with the reason, when it can't be)
function F.onTrapContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local bow
    for _, entry in ipairs(items) do
        local item = type(entry) == "table" and entry.items and entry.items[1] or entry
        if item and item.getFullType and F.isCrossbow(item) then bow = item; break end
    end
    if not (player and bow) then return end
    local opt = context:addOption(getText("IGUI_Fletcher_SetTrap"), player, F.queueSetTrap, bow)
    local why
    if not bow:isRoundChambered() then why = "IGUI_Fletcher_TrapNeedsBolt"
    elseif not F.trapWire(player) then why = "IGUI_Fletcher_TrapNeedsWire"
    elseif player:getVehicle() then why = "IGUI_Fletcher_TrapNotHere" end
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText(why or "IGUI_Fletcher_TrapHow")
    opt.toolTip = tip
    if why then opt.notAvailable = true end
end

Events.OnFillInventoryObjectContextMenu.Add(function(...) F.onTrapContextMenu(...) end)

return F
