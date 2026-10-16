require 'DrPepperFridge/PostersPlacement'
local function installInventoryCursorPatch()
    -- The native cursor belongs to server/BuildingObjects and may be loaded
    -- or redefined after client mod files. Patch the current class once its
    -- lifecycle has finished, without forcing an early require of that file.
    local cursor=ISMoveableCursor
    if not cursor or type(cursor.getInventoryObjectList)~='function' then return false end
    if cursor.getInventoryObjectList==cursor.DrPepperPosterInventoryWrapper then return true end
    local getList=cursor.getInventoryObjectList
    local wrapper=function(self)
        -- An old inventory item may still carry an alias after MDO was enabled.
        -- Its exact Dr item type proves the design before sprite lookup.
        local items=self.character:getInventory():getItems()
        for i=0,items:size()-1 do DrPepperPosterIds.normalizeInventoryPoster(items:get(i)) end
        DrPepperPosterIds.normalizeInventoryPoster(self.tryInitialInvItem)
        return getList(self)
    end
    cursor.DrPepperPosterInventoryWrapper=wrapper
    cursor.DrPepperPosterInventoryPatched=true
    cursor.getInventoryObjectList=wrapper
    return true
end
installInventoryCursorPatch()
Events.OnMainMenuEnter.Add(installInventoryCursorPatch)
Events.OnGameStart.Add(installInventoryCursorPatch)
