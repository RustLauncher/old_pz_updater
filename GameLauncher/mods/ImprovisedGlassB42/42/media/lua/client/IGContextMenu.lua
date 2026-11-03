require "IGRepairWindowAction"

local function ImprovisedGlassRepairWindow(worldobjects, playerID, window)
    local playerObj = getSpecificPlayer(playerID)
    if not playerObj or not window then return end

    local inv = playerObj:getInventory()
    local glass = inv:getFirstTypeRecurse("Base.GlassPanel") 
        or inv:getFirstTypeRecurse("GlassPanel") 
        or inv:getFirstTypeRecurse("ImprovisedGlass.GlassPane") 
        or inv:getFirstTypeRecurse("GlassPane")
        
    local glue = inv:getFirstTypeRecurse("Base.Woodglue") 
        or inv:getFirstTypeRecurse("Base.Glue") 
        or inv:getFirstTypeRecurse("Woodglue") 
        or inv:getFirstTypeRecurse("Glue")

    if luautils.walkAdjWindowOrDoor(playerObj, window:getSquare(), window) or luautils.walkAdj(playerObj, window:getSquare()) then
        ISTimedActionQueue.add(IGRepairWindowAction:new(playerObj, window, glass, glue))
    end
end

local function ImprovisedGlassRightClick(playerID, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local player = getSpecificPlayer(playerID)
    if not player or player:isDead() then return end

    local window = nil
    for _, obj in ipairs(worldobjects) do
        if instanceof(obj, "IsoWindow") then
            window = obj
            break
        elseif obj.getSquare and obj:getSquare() and obj:getSquare():getWindow() then
            window = obj:getSquare():getWindow()
            break
        end
    end

    if not window then return end

    -- Only permit repair if jagged glass has been removed and it's not barricaded
    if window:isGlassRemoved() and not window:isBarricaded() then
        local inv = player:getInventory()
        local glass = inv:getFirstTypeRecurse("Base.GlassPanel") 
            or inv:getFirstTypeRecurse("GlassPanel") 
            or inv:getFirstTypeRecurse("ImprovisedGlass.GlassPane") 
            or inv:getFirstTypeRecurse("GlassPane")
            
        local glue = inv:getFirstTypeRecurse("Base.Woodglue") 
            or inv:getFirstTypeRecurse("Base.Glue") 
            or inv:getFirstTypeRecurse("Woodglue") 
            or inv:getFirstTypeRecurse("Glue")

        local textRepair = getTextOrNull("ContextMenu_IGRepairWindow") or "Repair Window"
        local option = context:addOption(textRepair, worldobjects, ImprovisedGlassRepairWindow, playerID, window)

        if not glass or not glue then
            option.notAvailable = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = getTextOrNull("ContextMenu_IGRepairWindow_MissingItems") or "Requires Wood Glue and a Glass Pane to repair."
            option.toolTip = tooltip
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(ImprovisedGlassRightClick)