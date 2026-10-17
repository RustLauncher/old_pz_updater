-- Made by [TuNombre], adaptado del mod de la cerveza para FrikiToys

FrikiToyMenu = {};

-- Tabla de mapeo: cada juguete se asocia a su fragmento correspondiente
FrikiToyMenu.toyMapping = {
    SpongeBobToy      = "FrikiWeapons.KatanaFragment1",
    NemesisToy        = "FrikiWeapons.KatanaFragment2",
    XenomorphToy      = "FrikiWeapons.KatanaFragment3",
    ColossalTitanToy  = "FrikiWeapons.KatanaFragment4",
    C3poToy           = "FrikiWeapons.KatanaFragment5"
};

-- Función para crear el menú contextual en el inventario
FrikiToyMenu.doMenu = function(player, context, items)
    local toyItem = nil;
    local toyType = nil;
    for i, v in ipairs(items) do
        local tempitem = v;
        if not instanceof(v, "InventoryItem") then
            tempitem = v.items[1];
        end
        -- Si el item es uno de los juguetes definidos en el mapeo, lo usamos
        if FrikiToyMenu.toyMapping[tempitem:getType()] then
            toyItem = tempitem;
            toyType = tempitem:getType();
            break;  -- Procesamos uno a la vez
        end
    end
    if toyItem == nil then return end;
    
    local pl = getSpecificPlayer(player);
    local optionText = getText("ContextMenu_Investigate") .. " " .. toyItem:getDisplayName();
    local option = context:addOption(optionText, toyItem, FrikiToyMenu.Investigate, pl, toyItem, toyType);
    FrikiToyMenu.Tooltip(option, toyItem);
end

-- Función para añadir el tooltip a la opción
FrikiToyMenu.Tooltip = function(option, toyItem)
    local tooltip = ISInventoryPaneContextMenu.addToolTip();
    tooltip:setName(getText("ContextMenu_Investigate") .. " " .. toyItem:getDisplayName());
    tooltip:setTexture(toyItem:getTexture():getName());
    tooltip.description = " <RGB:1,1,1> " .. getText("ContextMenu_InvestigateTT");
    option.toolTip = tooltip;
end

-- Función que se ejecuta cuando se selecciona la opción "Investigate"
FrikiToyMenu.Investigate = function(item, playerObj, toyItem, toyType)
    if item then
        -- Obtiene el contenedor en el que se encuentra el juguete.
        local container = toyItem:getContainer();
        if container then
            container:Remove(toyItem);
        else
            -- Si no se encuentra un contenedor (por ejemplo, si está en el inventario del jugador),
            -- se intenta removerlo del inventario del jugador.
            local inv = playerObj:getInventory();
            inv:Remove(toyItem);
        end
        
        -- Ahora se añade el fragmento correspondiente al inventario del jugador.
        local inv = playerObj:getInventory();
        local fragmentItemType = FrikiToyMenu.toyMapping[toyType];
        if fragmentItemType then
            local newItem = InventoryItemFactory.CreateItem(fragmentItemType);
            inv:AddItem(newItem);
            playerObj:Say(getText("ContextMenu_InvestigateResult"));
        end
    end
end

-- Agrega la función al menú contextual de objetos del inventario
Events.OnFillInventoryObjectContextMenu.Add(FrikiToyMenu.doMenu);