if isServer() then return end

local function ContainersInInventoryExtra(inventoryPage, state)
    if state ~= "buttonsAdded" then return end

    local playerObj = getSpecificPlayer(inventoryPage.player)
    local playerInv = playerObj and playerObj:getInventory() or nil

    local buttons = inventoryPage.backpacks
    if not buttons then return end

    local currentCount = #buttons
    for i = 1, currentCount do
        local button = buttons[i]
        local inventory = button.inventory

        if inventory and inventory ~= playerInv then
            local items = inventory:getItems()
            if items then
                for j = 0, items:size() - 1 do
                    local item = items:get(j)
                    if item:isItemType(ItemType.KEY_RING) or item:hasTag(ItemTag.KEY_RING) then
                        local itemInv = item:getInventory()

                        local alreadyAdded = false
                        for k = 1, #inventoryPage.backpacks do
                            if inventoryPage.backpacks[k].inventory == itemInv then
                                alreadyAdded = true
                                break
                            end
                        end

                        if not alreadyAdded then
                            local itemContainerButton = inventoryPage:addContainerButton(itemInv, item:getTex(), item:getName(), item:getName())
                            if item:getVisual() and item:getClothingItem() then
                                local tint = item:getVisual():getTint(item:getClothingItem())
                                itemContainerButton:setTextureRGBA(tint:getRedFloat(), tint:getGreenFloat(), tint:getBlueFloat(), 1.0)
                            end
                        end
                    end
                end
            end
        end
    end
end

Events.OnRefreshInventoryWindowContainers.Add(ContainersInInventoryExtra)