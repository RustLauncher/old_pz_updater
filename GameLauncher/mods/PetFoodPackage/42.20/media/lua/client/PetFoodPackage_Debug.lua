require "ISUI/AdminPanel/ISItemsListViewer"

local originalItemsViewerInitList = ISItemsListViewer.initList
if not ISItemsListViewer.PetFoodPackagePatched then
    function ISItemsListViewer:initList()
        originalItemsViewerInitList(self)

        local boxedTypes = {}
        for _, itemType in ipairs(PetFoodPackageItems or {}) do
            boxedTypes[itemType] = true
        end

        local boxedItems = {}
        for i = 0, self.items:size() - 1 do
            local item = self.items:get(i)
            if boxedTypes[item:getFullName()] then
                table.insert(boxedItems, item)
            end
        end

        if #boxedItems > 0 then
            local boxedList = ISItemsListTable:new(0, 0, self.panel.width, self.panel.height - self.panel.tabHeight, self)
            boxedList:initialise()
            self.panel:addView(getText("UI_PetFoodPackage_DebugTitle"), boxedList)
            boxedList:initList(boxedItems)
        end
    end
    ISItemsListViewer.PetFoodPackagePatched = true
end
