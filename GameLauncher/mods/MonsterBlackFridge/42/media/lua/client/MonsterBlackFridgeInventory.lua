require 'MonsterBlackFridge/Core'
require 'ISUI/ISInventoryPage'
local M=MonsterBlackFridge
local icons={}
local paths={fridge='media/ui/MonsterBlackFridge_Fridge.png',
    freezer='media/ui/MonsterBlackFridge_Freezer.png'}
local kinds={fridge='fridge',fridgeoff='fridge',freezer='freezer',freezeroff='freezer'}

if not M.inventoryAppearanceInstalled then
    M.inventoryAppearanceInstalled=true
    local previous=ISInventoryPage.addContainerButton
    function ISInventoryPage:addContainerButton(container,texture,name,tooltip,...)
        local parent=container and container:getParent()
        local kind=container and kinds[container:getType()]
        if kind and parent and instanceof(parent,'IsoObject') and M.isMonster(parent) then
            icons[kind]=icons[kind] or getTexture(paths[kind])
            texture=icons[kind] or texture
            name = getText('IGUI_MonsterBlackFridge_Name')
            tooltip=getText(kind=='freezer' and 'IGUI_MonsterBlackFridge_Freezer' or 'IGUI_MonsterBlackFridge_Fridge')
        end
        -- Preserve container identity, types, capacities, sounds and pooled-button reset.
        return previous(self,container,texture,name,tooltip,...)
    end
end
