function ContainersInInventory()
    local items = getAllItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)

        if item.getItemType then
            local itemType = item:getItemType()
            if itemType == ItemType.CONTAINER then

                item:DoParam("DisplayCategory = Container")
                item:DoParam("AcceptItemFunction = ")
                item:DoParam("MaxItemSize = 0")

                if item.getTags and item.hasTag then
                    local tags = item:getTags()
                    if not item:hasTag(ItemTag.KEY_RING) then
                        tags:add(ItemTag.KEY_RING)
                    end
                end

            end
        end
    end
end

Events.OnGameBoot.Add(ContainersInInventory)