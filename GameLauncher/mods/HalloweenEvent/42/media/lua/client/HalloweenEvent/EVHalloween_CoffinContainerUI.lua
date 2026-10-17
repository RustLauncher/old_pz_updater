require "ISUI/ISInventoryPage"
require "HalloweenEvent/EVHalloween_CoffinPlacement"
local C=HalloweenEvent.Items.CoffinPlacement
-- Use the stock container button, supplying only our coffin's label/icon.
-- Keeping the container type as crate preserves loot and furniture behavior.
if not ISInventoryPage.EVHCoffinContainerUI then
    ISInventoryPage.EVHCoffinContainerUI=true
    local original=ISInventoryPage.addContainerButton
    local icon
    ISInventoryPage.addContainerButton=function(self,container,texture,name,tooltip)
        local parent=container and container:getParent()
        if parent and instanceof(parent,"IsoObject") and C.isCoffin(parent) then
            icon=icon or getTexture("media/textures/Item_EVHalloween_Decor_CoffinProp.png")
            local title=container:getCustomName() or getText("IGUI_EVH_Coffin")
            return original(self,container,icon or texture,title,title)
        end
        return original(self,container,texture,name,tooltip)
    end
end
