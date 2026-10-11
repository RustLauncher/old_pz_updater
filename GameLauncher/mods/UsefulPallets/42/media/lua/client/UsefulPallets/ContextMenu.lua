require "UsefulPallets/StackAction"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISTimedActionQueue"

local WP = UsefulPallets

local function name(itemType)
    local script = ScriptManager.instance:getItem(itemType)
    return script and script:getDisplayName() or itemType
end

local function available(character, itemType)
    local result = {}
    local seen = {}
    local function collect(container)
        if not WP.canUseSource(character, container) then return end
        local items = container:getAllTypeRecurse(itemType)
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if not seen[item] and WP.canLoadItem(character, item, itemType) then
                seen[item] = true
                result[#result + 1] = item
            end
        end
    end
    collect(character:getInventory())
    local containers = ISInventoryPaneContextMenu.getContainers(character)
    for i = 0, containers:size() - 1 do collect(containers:get(i)) end
    return result
end

function WP.queueTransfer(pallet, character, itemType, direction, amount)
    local state = WP.state(pallet)
    if not WP.canTransfer(state, itemType, direction) or character:getVehicle() then return end
    if not luautils.walkAdj(character, pallet:getSquare(), false) then return end
    if direction == "add" then
        local items = available(character, itemType)
        local count = math.min(amount, #items, WP.totalCapacity(state, itemType) - state.count)
        for i = 1, count do
            -- Remove directly from the validated source, avoiding temporary carry limits.
            ISTimedActionQueue.add(ISUsefulPalletTransfer:new(character, pallet, itemType, direction, items[i]))
        end
    else
        for i = 1, math.min(amount, WP.activeState(state).count) do
            ISTimedActionQueue.add(ISUsefulPalletTransfer:new(character, pallet, itemType, direction, nil))
        end
    end
end

local function submenu(parent, label)
    local option = parent:addOption(label)
    local menu = ISContextMenu:getNew(parent)
    parent:addSubMenu(option, menu)
    return menu, option
end

local function addMaterial(menu, pallet, character, material, state)
    local room = WP.capacity(state.kind, material.item) - state.count
    local count = math.min(#available(character, material.item), math.max(0, room))
    if (state.item and state.item ~= material.item) or count == 0 then return end
    local option = menu:addOption(name(material.item))
    local choices = ISContextMenu:getNew(menu)
    menu:addSubMenu(option, choices)
    choices:addOption(getText("ContextMenu_UP_AddOne"), pallet, WP.queueTransfer, character, material.item, "add", 1)
    choices:addOption(getText("ContextMenu_UP_Fill", count), pallet, WP.queueTransfer, character, material.item, "add", count)
end

local function disable(option, reason)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = getText(reason)
end

function WP.queueStack(pallet, character, direction)
    local state = WP.state(pallet)
    if character:getVehicle() then return end
    if direction == "attach" and not WP.canAttach(state) then return end
    if direction == "detach" and not WP.canDetach(state) then return end
    if not luautils.walkAdj(character, pallet:getSquare(), false) then return end
    local item
    if direction == "attach" then
        item = WP.carriedPallets(character)[1]
        if not item then return end
        ISInventoryPaneContextMenu.transferIfNeeded(character, item)
    end
    ISTimedActionQueue.add(ISUsefulPalletStack:new(character, pallet, direction, item))
end

local function fillTransfers(menu, pallet, character, state)
    if state.count > 0 then
        local take = submenu(menu, getText("ContextMenu_UP_Take"))
        take:addOption(getText("ContextMenu_UP_TakeOne"), pallet, WP.queueTransfer, character, state.item, "take", 1)
        if state.count >= 2 then
            local half = math.floor(state.count / 2)
            take:addOption(getText("ContextMenu_UP_TakeHalf", half), pallet, WP.queueTransfer, character, state.item, "take", half)
        end
        take:addOption(getText("ContextMenu_UP_TakeAll", state.count), pallet, WP.queueTransfer, character, state.item, "take", state.count)
    end
    local addOption = menu:addOption(getText("ContextMenu_UP_Add"))
    local add = ISContextMenu:getNew(menu)
    for _, material in ipairs(WP.materials) do
        if WP.capacity(state.kind, material.item) > 0 then
            addMaterial(add, pallet, character, material, state)
        end
    end
    if #add.options > 0 then
        menu:addSubMenu(addOption, add)
    else
        addOption.notAvailable = true
        addOption.toolTip = ISWorldObjectContextMenu.addToolTip()
        addOption.toolTip.description = state.item and state.count >= WP.capacity(state.kind, state.item)
            and getText("ContextMenu_UP_Full") or getText("ContextMenu_UP_NoItems")
    end
end

local function palletLabel(key, state)
    return getText(key) .. " - " .. (state.item and getText("ContextMenu_UP_Count", name(state.item), state.count,
        WP.capacity("military", state.item)) or getText(state.kind == "military" and "ContextMenu_UP_EmptyMilitary" or "ContextMenu_UP_Empty"))
end

function WP.fillContextMenu(player, context, worldobjects, test)
    local character = getSpecificPlayer(player)
    if not character then return end
    local seen = {}
    for _, pallet in ipairs(worldobjects) do
        local state = WP.state(pallet)
        if state and not seen[pallet] then
            seen[pallet] = true
            if test then return ISWorldObjectContextMenu.setTest() end
            -- Original entity context entries survive a sprite change. Remove their bulk-take options.
            context:removeOptionByName(getText("ContextMenu_TakeBricks"))
            context:removeOptionByName(getText("ContextMenu_TakeGoldBars"))
            local title = state.item and getText("ContextMenu_UP_Count", name(state.item), state.count, WP.totalCapacity(state, state.item))
                or getText(state.kind == "military" and "ContextMenu_UP_EmptyMilitary" or "ContextMenu_UP_Empty")
            if state.vanillaIntact then
                title = getText("ContextMenu_UP_Ecstasy") .. " - " .. title
            end
            local menu = submenu(context, title)
            if state.kind == "construction" then
                fillTransfers(menu, pallet, character, state)
            elseif state.kind == "stacked" then
                local active = WP.activeState(state)
                local top = submenu(menu, palletLabel("ContextMenu_UP_Top", active))
                fillTransfers(top, pallet, character, active)
                local remove = top:addOption(getText("ContextMenu_UP_RemovePallet"), pallet, WP.queueStack, character, "detach")
                if not WP.canDetach(state) then
                    disable(remove, "ContextMenu_UP_EmptyTopFirst")
                elseif not character:getInventory():hasRoomFor(character, state.topPallet.weight) then
                    disable(remove, "ContextMenu_UP_NoRoom")
                end
                local bottomState = {item = state.item, count = WP.bottomCount(state)}
                local bottom = menu:addOption(palletLabel("ContextMenu_UP_Bottom", bottomState))
                disable(bottom, "ContextMenu_UP_RemoveTopFirst")
            else
                if #WP.carriedPallets(character) > 0 then
                    local attach = menu:addOption(getText("ContextMenu_UP_AddTop"), pallet, WP.queueStack, character, "attach")
                    if not WP.canAttach(state) then disable(attach, "ContextMenu_UP_FillBottomFirst") end
                end
                local bottom = submenu(menu, palletLabel("ContextMenu_UP_Bottom", state))
                fillTransfers(bottom, pallet, character, state)
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(WP.fillContextMenu)
