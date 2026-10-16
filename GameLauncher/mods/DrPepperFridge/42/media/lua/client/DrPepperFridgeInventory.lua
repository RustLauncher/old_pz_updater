require 'DrPepperFridge/Core'
require 'ISUI/ISInventoryPage'
local M=DrPepperFridge
local icons={}
local paths={
    clean={fridge='media/ui/DrPepperFridge_Fridge.png',freezer='media/ui/DrPepperFridge_Freezer.png'},
    worn={fridge='media/ui/DrPepperFridgeWorn_Fridge.png',freezer='media/ui/DrPepperFridgeWorn_Freezer.png'},
}
local kinds={fridge='fridge',fridgeoff='fridge',freezer='freezer',freezeroff='freezer'}

if not M.inventoryAppearanceInstalled then
    M.inventoryAppearanceInstalled=true
    local previous=ISInventoryPage.addContainerButton
    function ISInventoryPage:addContainerButton(container,texture,name,tooltip,...)
        local parent=container and container:getParent()
        local kind=container and kinds[container:getType()]
        if kind and parent and instanceof(parent,'IsoObject') and M.isDrPepper(parent) then
            local variant=M.isWorn(parent) and 'worn' or 'clean'
            local iconKey=variant..'_'..kind
            icons[iconKey]=icons[iconKey] or getTexture(paths[variant][kind])
            texture=icons[iconKey] or texture
            local label='IGUI_DrPepperFridge_'..(variant=='worn' and 'Worn' or '')..(kind=='freezer' and 'Freezer' or 'Fridge')
            name=getText(label)
            tooltip=name
        end
        -- Preserve container identity, types, capacities, sounds and pooled-button reset.
        return previous(self,container,texture,name,tooltip,...)
    end
end
