require "DrPepperFridge/Drinks"

local M = DrPepperDrinks
local sodas = { ["Base.Pop"] = true, ["Base.Pop2"] = true,
    ["Base.Pop3"] = true, ["Base.SodaCan"] = true }
local filled = setmetatable({}, { __mode = "k" })
local AREA_KEY = "DrPepperDrinksGeneratedArea"

function M.markNewDrinkArea(square)
    if (isClient and isClient()) or not square then return end
    local chunk = square:getChunk()
    if not chunk or not chunk:isNewChunk() then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object:getContainerCount() > 0 then
            square:getModData()[AREA_KEY] = true
            return
        end
    end
end

function M.isNewDrinkArea(container)
    local square = container.getSourceGrid and container:getSourceGrid()
    if not square then return false end
    if square:getModData()[AREA_KEY] then return true end
    local chunk = square:getChunk()
    -- Initial filling can precede LoadGridsquare on a freshly generated chunk.
    if chunk and chunk:isNewChunk() then
        square:getModData()[AREA_KEY] = true
        return true
    end
    return false
end

function M.fillDrinks(roomName, containerType, container)
    -- Bag rolls can pass a Java distribution object instead of an ItemContainer.
    -- Validate its native type before reading any container methods.
    if (isClient and isClient()) or not container or not instanceof(container, "ItemContainer")
        or container:isExplored() or filled[container] then return end
    if not M.isNewDrinkArea(container) then return end
    filled[container] = true
    local items = container:getItems()
    local count = 0
    for i = 0, items:size() - 1 do
        if sodas[items:get(i):getFullType()] then count = count + 1 end
    end
    if count == 0 then return end
    local function add(id, key)
        -- One extra can per three native cans on average at multiplier 1.
        -- Sampling actual soda loot follows kitchens, shops, gas stations,
        -- restaurants and modded soda locations without overwriting any pool.
        local expected = count * M.option(key) / 3
        local amount = math.floor(expected)
        if ZombRand(10000) < (expected - amount) * 10000 then amount = amount + 1 end
        for _ = 1, math.min(amount, 100) do
            local item = instanceItem(id)
            if not item or not container:hasRoomFor(nil, item) then break end
            container:AddItem(item)
        end
    end
    add("DrPepper.CanRegular", "RegularLootMultiplier")
    add("DrPepper.CanDiet", "DietLootMultiplier")
end

-- ItemPickerJava fires this before setting explored=true on an initial roll.
-- LootRespawn fills already-explored containers, which the guard excludes.
-- No loaded-world scan, no replacement of native items and no respawn backfill.
Events.LoadGridsquare.Add(M.markNewDrinkArea)
Events.OnFillContainer.Add(M.fillDrinks)
