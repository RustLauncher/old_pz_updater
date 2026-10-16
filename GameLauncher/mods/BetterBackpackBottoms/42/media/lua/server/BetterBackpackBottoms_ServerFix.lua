local trackedContainers = {
    ["Base.Toolbox"] = true,
    ["Base.FirstAidKit"] = true,
    ["Base.Lunchbox"] = true,
    ["Base.Tacklebox"] = true,
    ["Base.Toolbox_Farming"] = true,
    ["Base.Toolbox_Fishing"] = true,
    ["Base.Toolbox_Gardening"] = true,
    ["Base.Toolbox_Mechanic"] = true,
    ["Base.FirstAidKit_New"] = true,
    ["Base.FirstAidKit_NewPro"] = true,
}

local function findItemById(inv, id)
    if not inv or not id then return nil end
    if inv.getItemWithIDRecursiv then
        local it = inv:getItemWithIDRecursiv(id)
        if it then return it end
    end
    local items = inv:getItems()
    if not items then return nil end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:getID() == id then return it end
        if instanceof(it, "InventoryContainer") and it.getItemContainer then
            local found = findItemById(it:getItemContainer(), id)
            if found then return found end
        end
    end
    return nil
end

local function onClientCommand(module, command, player, args)
    if module ~= "BBB" then return end
    if command ~= "fixContainerParent" then return end
    if not player or not args or not args.id then return end

    local item = findItemById(player:getInventory(), args.id)
    if not item then return end
    if not trackedContainers[item:getFullType()] then return end

    local ic = item.getInventory and item:getInventory() or nil
    if ic and ic:getParent() then
        ic:setParent(nil)
    end
end

Events.OnClientCommand.Add(onClientCommand)