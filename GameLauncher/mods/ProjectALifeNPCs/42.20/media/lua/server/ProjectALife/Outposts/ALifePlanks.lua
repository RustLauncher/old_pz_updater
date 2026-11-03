ProjectALife = ProjectALife or {}

local Planks = {
    itemType = "Base.Plank",
    perOpeningMax = 4,  
    metrics = { taken = 0 },
}
ProjectALife.Planks = Planks

function Planks.plan(count, supply)
    local plan = {}
    count = math.max(0, math.floor(tonumber(count) or 0))
    supply = math.max(0, math.floor(tonumber(supply) or 0))
    if count == 0 or supply == 0 then return plan end
    local boardable = math.min(count, supply)
    local base = math.min(Planks.perOpeningMax, math.floor(supply / boardable))
    local spare = supply - base * boardable
    for index = 1, boardable do
        local planks = base
        if spare > 0 and planks < Planks.perOpeningMax then
            planks, spare = planks + 1, spare - 1
        end
        plan[index] = planks
    end
    return plan
end

function Planks.held(shells)
    local total = 0
    for _, shell in ipairs(type(shells) == "table" and shells or {}) do
        pcall(function()
            local inventory = shell:getInventory()
            if inventory ~= nil then total = total + (tonumber(inventory:getCountTypeRecurse(Planks.itemType)) or 0) end
        end)
    end
    return total
end

function Planks.take(shells, wanted)
    local taken = 0
    wanted = math.max(0, math.floor(tonumber(wanted) or 0))
    for _, shell in ipairs(type(shells) == "table" and shells or {}) do
        while taken < wanted do
            local item
            pcall(function() item = shell:getInventory():getFirstTypeRecurse(Planks.itemType) end)
            if item == nil then break end
            local removed = false
            pcall(function()
                item:getContainer():DoRemoveItem(item)
                removed = true
            end)
            if not removed then break end
            taken = taken + 1
        end
    end
    Planks.metrics.taken = Planks.metrics.taken + taken
    return taken
end

return Planks
