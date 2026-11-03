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

local function clearAttachedContainerParent(character, item)
    if not item then return end
    if not instanceof(item, "InventoryContainer") then return end
    if not trackedContainers[item:getFullType()] then return end

    local ic = item:getInventory()
    if not ic then return end

    local parent = ic:getParent()
    local dirty = parent and instanceof(parent, "IsoGameCharacter")
    if dirty then
        ic:setParent(nil)
    end

	-- required to fire on servers due to the server holdign authority.
    if isClient() and character then
        sendClientCommand(character, "BBB", "fixContainerParent", { id = item:getID() })
    end
end

local function onClothingUpdated(character)
    if not character then return end
    local hotbar = getPlayerHotbar(character:getPlayerNum())
    if not hotbar or not hotbar.attachedItems then return end
    for _, item in pairs(hotbar.attachedItems) do
        clearAttachedContainerParent(character, item)
    end
end

Events.OnClothingUpdated.Add(onClothingUpdated)

local oldAttachItemHotbarStop = ISAttachItemHotbar.stop
function ISAttachItemHotbar:stop()
    oldAttachItemHotbarStop(self)
    clearAttachedContainerParent(self.character, self.item)
end