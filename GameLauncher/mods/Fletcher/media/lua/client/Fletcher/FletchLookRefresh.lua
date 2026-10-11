--[[
    Fletcher: an arrow's fletching look (icon, ground model: F.refreshArrowLook, shared/Fletcher/
    Fletching.lua) isn't kept by a save. It is put back on the arrows of every container an inventory
    window shows (bags too), and on the arrows lying on a square when it loads. Only arrows that carry a
    fletching (md.fl_fletch) are touched.
]]

require "Fletcher/Core"
require "Fletcher/Fletching"
local F = Fletcher

local function refreshContainer(container, depth)
    if not container or (depth or 0) > 3 then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if F.fletchOf(item) then F.refreshArrowLook(item)
        elseif instanceof(item, "InventoryContainer") then refreshContainer(item:getInventory(), (depth or 0) + 1) end
    end
end

function F.onRefreshFletchLooks(page)
    if not (page and page.backpacks) then return end
    for _, button in ipairs(page.backpacks) do refreshContainer(button.inventory, 0) end
end

function F.onSquareFletchLooks(sq)
    local w = sq and sq:getWorldObjects()
    for i = 0, (w and w:size() or 0) - 1 do
        local item = w:get(i):getItem()
        if item and F.fletchOf(item) then F.refreshArrowLook(item) end
    end
end

Events.OnRefreshInventoryWindowContainers.Add(function(page, reason) F.onRefreshFletchLooks(page) end)
Events.LoadGridsquare.Add(function(sq) F.onSquareFletchLooks(sq) end)
