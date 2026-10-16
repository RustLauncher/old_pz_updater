ProjectALife = ProjectALife or {}
if ProjectALife.LootTransfer then return ProjectALife.LootTransfer end
local Loot = { pending = {}, sequence = 0 }
ProjectALife.LootTransfer = Loot

function Loot.request(shell, target)
    if target.transferResult ~= nil then return target.transferResult end
    local now = getTimestampMs()
    local count = 0
    for id, pending in pairs(Loot.pending) do
        if now - pending.atMs > 10000 then
            pending.target.transferResult = false
            Loot.pending[id] = nil
        else
            count = count + 1
            if pending.target == target then return nil end
        end
    end
    if count >= 32 or target.x == nil or target.y == nil or target.z == nil then return false end
    local executor = ProjectALife.Executor
    local uid = executor and executor.byShell[shell]
    local entry = uid and executor.executed[uid]
    if entry == nil or not executor.authorityFor(shell) then return false end
    Loot.sequence = Loot.sequence + 1
    local id = Loot.sequence
    local message = { request = id, uid = uid, generation = entry.generation,
        x = target.x, y = target.y, z = target.z, item = target.item:getID() }
    if target.vehicle ~= nil and target.part ~= nil then
        message.vehicle = target.vehicle:getId()
        message.part = target.part:getId()
    end
    Loot.pending[id] = { shell = shell, target = target, uid = uid,
        generation = entry.generation, atMs = now }
    local ok = pcall(sendClientCommand, "ProjectALife", "executorLoot", message)
    if not ok then Loot.pending[id] = nil return false end
    return nil
end

function Loot.itemIn(container, itemId)
    if container == nil then return nil end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item:getID() == itemId then return item end
    end
    return nil
end

function Loot.collect(shell, message)
    local square = getCell():getGridSquare(math.floor(message.x), math.floor(message.y), math.floor(message.z))
    if square == nil or shell:getCurrentSquare() == nil
            or not shell:getCurrentSquare():canReachTo(square) then return false end
    local container, item
    if message.vehicle ~= nil then
        if type(getVehicleById) ~= "function" or type(message.part) ~= "string" then return false end
        local vehicle = getVehicleById(message.vehicle)
        if vehicle == nil or (vehicle:getX() - message.x)^2 + (vehicle:getY() - message.y)^2 > 36 then return false end
        local part = vehicle:getPartById(message.part)
        if part == nil then return false end
        local door = part:getDoor()
        if door ~= nil and door:isLocked() then return false end
        container = part:getItemContainer()
        item = Loot.itemIn(container, message.item)
    else
        for _, objects in ipairs({ square:getObjects(), square:getStaticMovingObjects() }) do
            for index = 0, objects:size() - 1 do
                local object = objects:get(index)
                if object.getContainerCount ~= nil then
                    for slot = 0, object:getContainerCount() - 1 do
                        local candidate = object:getContainerByIndex(slot)
                        local found = Loot.itemIn(candidate, message.item)
                        if found ~= nil then container, item = candidate, found break end
                    end
                elseif object.getContainer ~= nil then
                    local candidate = object:getContainer()
                    local found = Loot.itemIn(candidate, message.item)
                    if found ~= nil then container, item = candidate, found end
                end
                if item ~= nil then break end
            end
            if item ~= nil then break end
        end
    end
    if item == nil then return false end
    return ProjectALife.Scavenging.transfer(shell, { container = container, item = item,
        x = message.x, y = message.y, z = message.z }) == true
end

function Loot.onResult(module, command, message)
    if module ~= "ProjectALife" or command ~= "executorLootResult" or type(message) ~= "table" then return end
    local pending = Loot.pending[message.request]
    if pending == nil or pending.uid ~= message.uid or pending.generation ~= message.generation then return end
    Loot.pending[message.request] = nil
    local target, shell = pending.target, pending.shell
    target.transferResult = false
    local executor = ProjectALife.Executor
    local entry = executor and executor.executed[pending.uid]
    if message.ok ~= true or entry == nil or entry.shell ~= shell
            or entry.generation ~= pending.generation or not executor.authorityFor(shell)
            or shell:isDead() then return end

    if not target.container:getItems():contains(target.item) then
        if target.item:getContainer() ~= nil then return end
        target.container:AddItem(target.item)
    end
    target.transferResult = ProjectALife.Scavenging.transfer(shell, target, true) == true
end

if Events ~= nil and Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(Loot.onResult) end
return Loot
