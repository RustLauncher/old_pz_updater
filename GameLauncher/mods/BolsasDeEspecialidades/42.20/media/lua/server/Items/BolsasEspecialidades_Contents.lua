require "BolsasEspecialidades_Core"
local BE = BolsasEspecialidades
local warnedMissing = {}

local function fillBag(bag)
    local pool = BE.pools[bag:getFullType()]
    if not pool or not instanceof(bag, "InventoryContainer") then return end
    local data = bag:getModData()
    if data[BE.stateKey] then return end
    local inventory = bag:getInventory()
    -- Persist BEFORE adding anything. Empty rolls must also never reroll.
    data[BE.stateKey] = "world"
    inventory:setExplored(true)
    if inventory:getItems():size() > 0 then return end
    if ZombRand(100) >= BE.contentChance then return end

    local candidates = {}
    for _, entry in ipairs(pool) do
        if ScriptManager.instance:getItem(entry[1]) then
            candidates[#candidates + 1] = entry
        elseif not warnedMissing[entry[1]] then
            warnedMissing[entry[1]] = true
            print("[BolsasDeEspecialidades] Skipping missing loot item: " .. entry[1])
        end
    end
    local count = ZombRand(BE.minTypes, BE.maxTypes + 1)
    for draw = 1, count do
        local total = 0
        for _, entry in ipairs(candidates) do total = total + entry[2] end
        if total == 0 then break end
        local roll = ZombRand(total)
        local chosen = 1
        for i, entry in ipairs(candidates) do
            roll = roll - entry[2]
            if roll < 0 then chosen = i; break end
        end
        local entry = table.remove(candidates, chosen)
        local quantity = ZombRand(entry[3], entry[4] + 1)
        for n = 1, quantity do inventory:AddItem(entry[1]) end
        -- At most one ammo box, regardless of caliber, in a firearms bag.
        if entry[5] then
            for i = #candidates, 1, -1 do
                if candidates[i][5] == entry[5] then table.remove(candidates, i) end
            end
        end
    end
end

local function onFillContainer(roomType, containerType, container)
    if isClient() then return end
    -- B42 sometimes sends an ItemPickerContainer, not an ItemContainer.
    -- Test the Java class before indexing any methods on it.
    if not container or not instanceof(container, "ItemContainer") then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do fillBag(items:get(i)) end
end

Events.OnFillContainer.Add(onFillContainer)
