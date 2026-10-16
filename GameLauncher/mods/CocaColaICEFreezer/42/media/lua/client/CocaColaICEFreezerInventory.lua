require 'CocaColaICEFreezer/Core'
require 'ISUI/ISInventoryPage'

local M = CocaColaICEFreezer
local iconPath = 'media/ui/CocaColaICEFreezer_Container.png'
local icon

local function isCocaContainer(container)
    local parent = container and container:getParent()
    if not parent or not instanceof(parent, 'IsoObject') then return false end
    local sprite = parent:getSprite()
    local name = sprite and sprite:getName()
    local entry = name and M.tiles[name]
    return entry ~= nil and M.isCokeName(name)
end

if not M.inventoryAppearanceInstalled then
    M.inventoryAppearanceInstalled = true
    local previous = ISInventoryPage.addContainerButton
    function ISInventoryPage:addContainerButton(container, texture, name, tooltip, ...)
        if isCocaContainer(container) then
            icon = icon or getTexture(iconPath)
            texture = icon or texture
            name = getText('IGUI_CocaColaICEFreezer_Name')
            tooltip = name
        end
        -- The native method resets pooled buttons, retains capacity/clicks and
        -- uses this name for the selected container's title. Do not rename
        -- container types or replace the shared freezer icon/translation.
        return previous(self, container, texture, name, tooltip, ...)
    end
end
