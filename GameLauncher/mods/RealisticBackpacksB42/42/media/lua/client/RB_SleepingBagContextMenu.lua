require "TimedActions/ISTimedActionQueue"
require "TimedActions/RB_ToggleSleepingBagAction"

local PACKED_SLEEPING_BAG = "Base.SleepingBag_Green_Packed"

local ATTACHABLE = {
    ["Base.Assault_Backpack"] = true,
    ["Base.Assault_Backpack_Black"] = true,
    ["Base.Assault_Backpack_Green"] = true,
    ["Base.Assault_Backpack_Camo"] = true,
    ["Base.Assault_Backpack_Pidoras"] = true,
}

local DETACHABLE = {
    ["Base.Assault_Backpack_Mattress"] = true,
    ["Base.Assault_Backpack_Mattress_Black"] = true,
    ["Base.Assault_Backpack_Mattress_Green"] = true,
    ["Base.Assault_Backpack_Mattress_Camo"] = true,
    ["Base.Assault_Backpack_Mattress_Pidoras"] = true,
}

local function getBackpackFromSelection(items)
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then
            item = entry.items and entry.items[1] or nil
        end

        if item then
            local fullType = item:getFullType()
            if ATTACHABLE[fullType] or DETACHABLE[fullType] then
                return item
            end
        end
    end
    return nil
end

local function queueToggle(backpack, playerObj, attach)
    if not backpack or not playerObj then
        return
    end
    ISTimedActionQueue.add(RB_ToggleSleepingBagAction:new(playerObj, backpack, attach))
end

local function addSleepingBagOptions(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then
        return
    end

    local backpack = getBackpackFromSelection(items)
    if not backpack or backpack:getContainer() ~= playerObj:getInventory() then
        return
    end

    if ATTACHABLE[backpack:getFullType()] then
        if playerObj:getInventory():getFirstTypeRecurse(PACKED_SLEEPING_BAG) then
            context:addOption(
                getText("ContextMenu_RB_AttachSleepingBag"),
                backpack,
                queueToggle,
                playerObj,
                true
            )
        end
        return
    end

    context:addOption(
        getText("ContextMenu_RB_DetachSleepingBag"),
        backpack,
        queueToggle,
        playerObj,
        false
    )
end

Events.OnFillInventoryObjectContextMenu.Add(addSleepingBagOptions)
