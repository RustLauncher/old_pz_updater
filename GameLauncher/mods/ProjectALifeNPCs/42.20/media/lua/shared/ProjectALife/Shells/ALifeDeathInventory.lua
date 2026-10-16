ProjectALife = ProjectALife or {}

local DeathInventory = { pending = setmetatable({}, { __mode = "k" }) }
ProjectALife.DeathInventory = DeathInventory

function DeathInventory.clear(shell)
    DeathInventory.pending[shell] = nil
    shell:clearItemsToSpawnAtDeath()
end

function DeathInventory.add(shell, item)
    if type(isServer) == "function" and isServer()
            and type(instanceof) == "function" and instanceof(item, "Food") then

        if shell:isDead() then return end
        local data = shell:getModData()
        local entry = DeathInventory.pending[shell]
        if entry == nil or entry.uid ~= data.ProjectALifeUID
                or entry.generation ~= data.ProjectALifeGeneration then
            entry = { uid = data.ProjectALifeUID, generation = data.ProjectALifeGeneration, items = {} }
            DeathInventory.pending[shell] = entry
        end
        entry.items[item] = true
        return
    end
    shell:addItemToSpawnAtDeath(item)
end

function DeathInventory.restore(shell)
    local entry = DeathInventory.pending[shell]
    DeathInventory.pending[shell] = nil
    if entry == nil then return end
    local data = shell:getModData()
    if entry.uid ~= data.ProjectALifeUID or entry.generation ~= data.ProjectALifeGeneration then return end
    local inventory = shell:getInventory()
    for item in pairs(entry.items) do
        DeathInventory.put(inventory, item)
    end
end

function DeathInventory.put(inventory, item)
    if inventory:contains(item) then return item end
    if type(isServer) == "function" and isServer()
            and type(instanceof) == "function" and instanceof(item, "Food") then

        item:updateAge(false)
    end
    return inventory:AddItem(item)
end

return DeathInventory
