-- Native furniture placement is provided by the stock Moveable cursor.
require "HalloweenEvent/EVHalloween_CoffinPlacement"
require "TimedActions/ISEVHalloweenConvertCoffinAction"
-- The stock server/BuildingObjects cursor is autoloaded by the game. It is
-- not available to client require while these client modules are loading.
local Items=HalloweenEvent.Items
local function convert(player,item)
    ISTimedActionQueue.add(ISEVHalloweenConvertCoffinAction:new(player,item))
end
local function inventoryMenu(n,context,selection)
    local player=getSpecificPlayer(n)
    if not player or not context then return end
    for _,value in ipairs(selection or {}) do
        local item=type(value)=="table" and value.items and value.items[1] or value
        if item and item.getFullType and item:getFullType()==Items.coffinType then
            if not Items.CoffinPlacement.initItem(item) then return end
            -- A loose 3D prop's Place action does not install native furniture.
            -- Use the exact stock menu and stock cursor used by vanilla crates.
            if ISInventoryPaneContextMenu and context.removeOptionByName then
                context:removeOptionByName(getText("ContextMenu_PlaceItemOnGround"))
            end
            local native=ISMoveableContextMenu
            if not native or not native.createMenu then return end
            for _,option in ipairs(context.options or {}) do
                if option.target==item and option.onSelect==native.openMovableCursor then return end
            end
            native.createMenu(context,item,player)
            return
        end
        if item and item.getFullType and item:getFullType()==Items.legacyCoffinType then
            local option=context:addOption(HalloweenEvent.text("ConvertCoffin"),player,convert,item)
            option.notAvailable=not ISEVHalloweenConvertCoffinAction:new(player,item):isValid()
            if option.notAvailable then
                local tooltip=ISWorldObjectContextMenu.addToolTip()
                tooltip.description=HalloweenEvent.text("ConvertCoffinHelp")
                option.toolTip=tooltip
            end
            return
        end
    end
end
if Events.OnFillInventoryObjectContextMenu then Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu) end
