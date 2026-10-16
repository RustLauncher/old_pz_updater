require 'RedbullFreezer/Core'
require 'ISUI/ISInventoryPage'
local M=RedbullFreezer
local icons={}
local paths={fridge='media/ui/RedbullFreezer_Container.png',
    freezer='media/ui/RedbullFreezer_Container.png'}
local kinds={fridge='fridge',fridgeoff='fridge',freezer='freezer',freezeroff='freezer'}

if not M.inventoryAppearanceInstalled then
    M.inventoryAppearanceInstalled=true
    local previous=ISInventoryPage.addContainerButton
    function ISInventoryPage:addContainerButton(container,texture,name,tooltip,...)
        local parent=container and container:getParent()
        local kind=container and kinds[container:getType()]
        if kind and parent and instanceof(parent,'IsoObject') and M.isRedbull(parent) then
            icons[kind]=icons[kind] or getTexture(paths[kind])
            texture=icons[kind] or texture
            name = getText('IGUI_RedbullFreezer_Name')
        tooltip=name
        end
        -- Preserve container identity, types, capacities, sounds and pooled-button reset.
        return previous(self,container,texture,name,tooltip,...)
    end
end
