require 'PepsiFridge/Core'
require 'ISUI/ISInventoryPage'
local M=PepsiFridge
local icons={}
local paths={
    clean={fridge='media/ui/PepsiFridge_Fridge.png',freezer='media/ui/PepsiFridge_Freezer.png'},
    worn={fridge='media/ui/PepsiFridgeWorn_Fridge.png',freezer='media/ui/PepsiFridgeWorn_Freezer.png'},
}
local kinds={fridge='fridge',fridgeoff='fridge',freezer='freezer',freezeroff='freezer'}

if not M.inventoryAppearanceInstalled then
    M.inventoryAppearanceInstalled=true
    local previous=ISInventoryPage.addContainerButton
    function ISInventoryPage:addContainerButton(container,texture,name,tooltip,...)
        local parent=container and container:getParent()
        local kind=container and kinds[container:getType()]
        if kind and parent and instanceof(parent,'IsoObject') and M.isPepsi(parent) then
            local variant=M.isWorn(parent) and 'worn' or 'clean'
            local iconKey=variant..'_'..kind
            icons[iconKey]=icons[iconKey] or getTexture(paths[variant][kind])
            texture=icons[iconKey] or texture
            name = getText(variant=='worn' and 'IGUI_PepsiFridge_WornName' or 'IGUI_PepsiFridge_Name')
            tooltip=name..' - '..getText(kind=='freezer' and 'IGUI_PepsiFridge_Freezer' or 'IGUI_PepsiFridge_Fridge')
        end
        -- Preserve container identity, types, capacities, sounds and pooled-button reset.
        return previous(self,container,texture,name,tooltip,...)
    end
end
