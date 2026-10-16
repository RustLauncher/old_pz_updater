require "VapesOf93/VapeShared"

local EMPTY_PEN = "VapesOf93.VapePen"

local function usesLeft(item)
    local ok, u = pcall(function() return item:getCurrentUses() end)
    return ok and u or nil
end

local function find(inv, shortType)
    local it
    pcall(function() it = inv:getFirstTypeRecurse("VapesOf93." .. shortType) end)
    if not it then pcall(function() it = inv:getFirstTypeRecurse(shortType) end) end
    return it
end

function VapesOf93.refill(player, pen, juice)
    if not pen or not juice then return end
    local flavor = juice:getType():match("^Juice_(.+)$")
    if not flavor then return end
    local inv = player:getInventory()
    local loaded = inv:AddItem("VapesOf93.VapePen_" .. flavor)
    if not loaded then print("[VapesOf93] refill failed: could not create VapePen_" .. flavor) return end
    local from = pen:getContainer() or inv
    from:Remove(pen)
    juice:Use()                                              -- one of the box's 3 refills
    local left = usesLeft(juice)
    if left and left <= 0 then
        local c = juice:getContainer()
        if c then c:Remove(juice) end
    end
    pcall(function() ISInventoryPage.dirtyUI() end)
    player:Say("Loaded up some " .. (VapesOf93.FlavorNames[flavor] or flavor) .. ".")
end

local function itemOf(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    return entry.items and entry.items[1]
end

local function fillMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local inv = player:getInventory()
    local pen, juice
    for _, entry in ipairs(items) do
        local it = itemOf(entry)
        if it then
            local t = it:getFullType()
            if t == EMPTY_PEN then pen = pen or it end
            if t:find("^VapesOf93%.Juice_") then juice = juice or it end
        end
    end

    if pen then
        local found = {}
        for key, name in pairs(VapesOf93.FlavorNames) do
            local j = find(inv, "Juice_" .. key)
            if j then found[#found + 1] = { name = name, item = j, uses = usesLeft(j) } end
        end
        table.sort(found, function(x, y) return x.name < y.name end)
        if #found == 0 then
            local opt = context:addOption("Refill with Juice (no juice on you)")
            opt.notAvailable = true
        else
            local opt = context:addOption("Refill with Juice")
            local sub = ISContextMenu:getNew(context)
            context:addSubMenu(opt, sub)
            for _, j in ipairs(found) do
                local label = j.name .. " Juice" .. (j.uses and (" (" .. j.uses .. " left)") or "")
                sub:addOption(label, player, VapesOf93.refill, pen, j.item)
            end
        end
    elseif juice then
        local empty = find(inv, "VapePen")
        if empty then
            context:addOption("Refill an Empty Vape Pen", player, VapesOf93.refill, empty, juice)
        else
            local opt = context:addOption("Refill an Empty Vape Pen (none on you)")
            opt.notAvailable = true
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)
