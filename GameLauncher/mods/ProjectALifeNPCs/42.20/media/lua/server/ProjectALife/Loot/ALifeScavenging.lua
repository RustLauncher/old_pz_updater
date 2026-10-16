require "ProjectALife/Movement/ALifeMovement"
require "ProjectALife/Shells/ALifeShellState"
require "ProjectALife/Records/ALifeBehaviorSettings"

require "ProjectALife/Shells/ALifeDeathInventory"

ProjectALife = ProjectALife or {}

local Movement = ProjectALife.Movement
local ShellState = ProjectALife.ShellState
local defaults = ProjectALife.BehaviorSettings.scavenging
local movementDefaults = ProjectALife.BehaviorSettings.movement
local Scavenging = {
    adapters = {},
    settings = {},
    reservations = {},
    activeByActor = {},
    sequence = 0,
    vehicleVisited = setmetatable({}, { __mode = "k" }),
    metrics = { collected = 0, deposited = 0, transferFailed = 0, bagged = 0,

        handCarried = 0,

        baseSkips = 0 },
}
ProjectALife.Scavenging = Scavenging

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function authoritative()
    if type(isClient) ~= "function" or isClient() ~= true then return true end

    local executor = ProjectALife.Executor
    return executor ~= nil and executor.clientAuthority() == true
end

local function reservationFree(plan)
    if plan == nil then return true end
    local expiresAt = tonumber(plan.expiresAt)
    return expiresAt ~= nil and nowMs() >= expiresAt
end

local function listSize(list)
    if list == nil or list.size == nil then return 0 end
    return list:size() or 0
end

local function listGet(list, index)
    if list == nil then return nil end

    if list.get == nil then return nil end
    return list:get(index)
end

local function reservationFor(container, item)
    return tostring(container) .. ":" .. tostring(item)
end

local function containsItemId(container, item)
    local idOk, id = pcall(function() return item:getID() end)
    if not idOk or id == nil then return nil end
    local containsOk, contains = pcall(function() return container:containsID(id) end)
    return containsOk and contains == true or nil
end

local function restoreItem(container, item)
    if containsItemId(container, item) == true then return true end
    local ok, added = pcall(function() return container:AddItem(item) end)
    return ok and added == item
end

local function itemText(item)
    local parts = {}
    for _, method in ipairs({ "getFullType", "getType", "getDisplayCategory" }) do
        local ok, value = pcall(function() return item[method](item) end)
        if ok and value ~= nil then parts[#parts + 1] = tostring(value) end
    end
    return string.lower(table.concat(parts, " "))
end

local function baseScore(text)
    if string.find(text, "firearm", 1, true) or string.find(text, "weapon", 1, true)
            or string.find(text, "rifle", 1, true) or string.find(text, "pistol", 1, true)
            or string.find(text, "shotgun", 1, true) then return 100 end
    if string.find(text, "ammo", 1, true) or string.find(text, "bullet", 1, true)
            or string.find(text, "magazine", 1, true) then return 90 end
    if string.find(text, "medical", 1, true) or string.find(text, "bandage", 1, true)
            or string.find(text, "firstaid", 1, true) then return 80 end
    if string.find(text, "food", 1, true) then return 70 end
    if string.find(text, "water", 1, true) or string.find(text, "drink", 1, true) then
        return 65
    end
    return 20
end

Scavenging.wantedKeywords = {
    medical = { "medical", "bandage", "firstaid", "pills", "disinfectant", "suture", "splint" },
    food = { "food" },
    ammo = { "ammo", "bullet", "magazine", "rounds", "shells" },
    tools = { "hammer", "saw", "nails", "screwdriver", "axe", "crowbar", "tool", "wrench" },
    water = { "water", "drink", "bottle" },
}

function Scavenging.foundEventFor(text)
    text = string.lower(tostring(text or ""))
    if string.find(text, "medical", 1, true) or string.find(text, "bandage", 1, true)
            or string.find(text, "firstaid", 1, true) or string.find(text, "pills", 1, true) then
        return "FOUND_MEDICINE"
    end
    if string.find(text, "ammo", 1, true) or string.find(text, "bullet", 1, true)
            or string.find(text, "magazine", 1, true) then return "FOUND_AMMO" end
    if string.find(text, "firearm", 1, true) or string.find(text, "weapon", 1, true)
            or string.find(text, "rifle", 1, true) or string.find(text, "pistol", 1, true) then
        return "FOUND_WEAPON"
    end
    if string.find(text, "water", 1, true) or string.find(text, "drink", 1, true) then return "FOUND_WATER" end
    if string.find(text, "food", 1, true) then return "FOUND_FOOD" end

    for _, word in ipairs(Scavenging.wantedKeywords.tools) do
        if string.find(text, word, 1, true) then return "FOUND_TOOL" end
    end

    return "FOUND_GEAR"
end

function Scavenging.foundSpoken(item)
    local name
    if item ~= nil then
        for _, method in ipairs({ "getDisplayName", "getName" }) do
            if name == nil and item[method] ~= nil then
                local ok, value = pcall(function() return item[method](item) end)
                if ok and type(value) == "string" and value ~= "" then name = value end
            end
        end
    end
    if name == nil then return { context = {} } end
    return { context = { found = name, named = "yes" } }
end

local function itemScore(item, wanted)
    if item == nil then return -math.huge end
    local text = itemText(item)
    local score = baseScore(text)
    local keywords = wanted ~= nil and Scavenging.wantedKeywords[tostring(wanted)] or nil
    if type(keywords) == "table" then
        for _, word in ipairs(keywords) do
            if string.find(text, word, 1, true) then return score + 200 end
        end
    end
    return score
end
Scavenging.scoreItem = itemScore

local function bestInContainer(square, container, best, wanted)
    local items = container and container:getItems() or nil
    for itemIndex = 0, math.min(listSize(items), 96) - 1 do
        local item = listGet(items, itemIndex)
        local reservation = reservationFor(container, item)
        if reservationFree(Scavenging.reservations[reservation]) then
            local score = itemScore(item, wanted)
            if best == nil or score > best.score then
                best = {
                    x = square:getX(), y = square:getY(), z = square:getZ(),
                    container = container, item = item, reservation = reservation,
                    score = score,
                }
            end
        end
    end
    return best
end

function Scavenging.searchPreset(object)
    local name = ""
    if object ~= nil then
        pcall(function() name = string.lower(tostring(object:getSpriteName() or "")) end)
    end
    if string.find(name, "shelves", 1, true) or string.find(name, "wallcabinet", 1, true)
            or string.find(name, "overhead", 1, true) then return "search_high" end
    if string.find(name, "crate", 1, true) or string.find(name, "floor", 1, true)
            or string.find(name, "bin", 1, true) then return "search_low" end
    return "search_mid"
end

local function targetOnSquare(square, wanted)
    if square == nil then return nil end
    local best
    local objects = square:getObjects()
    for objectIndex = 0, listSize(objects) - 1 do
        local object = listGet(objects, objectIndex)
        local countOk = object ~= nil and object.getContainerCount ~= nil
        local count = countOk and object:getContainerCount() or 0
        if countOk then
            for containerIndex = 0, count - 1 do
                local container = object:getContainerByIndex(containerIndex)
                if container ~= nil then
                    local target = bestInContainer(square, container, nil, wanted)
                    if target == nil and not container:isExplored() then
                        target = { x = square:getX(), y = square:getY(), z = square:getZ(),
                            container = container, unexplored = true, score = 20,
                            reservation = tostring(container) .. ":search" }
                    end
                    if target ~= nil and (best == nil or target.score > best.score) then
                        target.objectIndex, target.containerIndex = objectIndex, containerIndex

                        pcall(function() target.spriteName = object:getSpriteName() end)
                        target.preset = Scavenging.searchPreset(object)
                        best = target
                    end
                end
            end
        end
    end
    return best
end

function Scavenging.objectForSpot(square, spot)
    if square == nil or spot == nil then return nil end
    local objects = square:getObjects()
    local slot = spot.containerIndex or 0
    if spot.spriteName ~= nil then
        for objectIndex = 0, listSize(objects) - 1 do
            local object = listGet(objects, objectIndex)
            if object ~= nil and object.getContainerCount ~= nil
                    and object:getContainerCount() > slot then
                local name
                pcall(function() name = object:getSpriteName() end)
                if name == spot.spriteName then return object end
            end
        end
        return nil
    end

    local object = listGet(objects, spot.objectIndex or 0)
    if object ~= nil and object.getContainerCount ~= nil
            and object:getContainerCount() > slot then
        return object
    end
    return nil
end

function Scavenging.targetAt(spot, wanted, explore, shell)
    if type(spot) ~= "table" or type(getCell) ~= "function" then return nil end
    local square = getCell():getGridSquare(math.floor(spot.x), math.floor(spot.y), math.floor(spot.z))
    if square == nil then return nil end
    if explore == true then
        local ok, nearby = pcall(function()
            local from = shell:getCurrentSquare()
            return from ~= nil and from:canReachTo(square)
        end)
        if not ok or not nearby then return nil end
    end
    local object = Scavenging.objectForSpot(square, spot)
    if object == nil then return nil end
    local container = object:getContainerByIndex(spot.containerIndex or 0)
    if explore == true and authoritative() and container ~= nil and ItemPickerJava ~= nil then

        pcall(function()
            if container:isExplored() then return end
            ItemPickerJava.fillContainer(container, nil)
            container:setExplored(true)
            if type(sendItemsInContainer) == "function" then sendItemsInContainer(object, container) end
        end)
    end
    return bestInContainer(square, container, nil, wanted)
end

function Scavenging.standPoint(spot, buildingId)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return nil end
    local x, y, z = math.floor(spot.x), math.floor(spot.y), math.floor(spot.z)
    local square = cell:getGridSquare(x, y, z)
    if square == nil then return nil end
    for _, offset in ipairs({ {0,0}, {1,0}, {-1,0}, {0,1}, {0,-1} }) do
        local stand = cell:getGridSquare(x + offset[1], y + offset[2], z)
        local ok, allowed = pcall(function()
            local building = stand and stand:getBuilding()
            return stand ~= nil and stand:isFree(false) and stand:TreatAsSolidFloor()
                and (buildingId == nil or (building ~= nil and tostring(building:getID()) == buildingId))
                and stand:canReachTo(square)
        end)
        if ok and allowed then return { x = stand:getX() + 0.5, y = stand:getY() + 0.5, z = z } end
    end
    return nil
end

local function stableHash(value)
    local result = 23
    value = tostring(value or "")
    for index = 1, #value do result = (result * 33 + string.byte(value, index)) % 2147483647 end
    return result
end

local function parkedVehicle(vehicle)
    if vehicle:isEngineRunning() or math.abs(vehicle:getCurrentSpeedKmHour()) > 0.1 then return false end
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        if vehicle:getCharacter(seat) ~= nil then return false end
    end
    return vehicle:getCurrentSquare() ~= nil
end

local function vehicleAccess(vehicle, part)
    if not parkedVehicle(vehicle) then return nil end
    local hood = part:getId() == "EngineDoor"
    local doorPart = hood and part or (vehicle:getPartById("TrunkDoor")
        or vehicle:getPartById("DoorRear") or vehicle:getPartById("TrunkDoorOpened"))
    if not hood and vehicle:isTrunkLocked() then return nil end
    local door = doorPart and doorPart:getDoor()
    if door and door:isLocked() then return nil end
    local area = vehicle:getScript():getAreaById(part:getArea())
    if area == nil then return nil end
    local point = vehicle:areaPositionWorld4PlayerInteract(area)
    if point == nil then return nil end
    return { x = point:getX(), y = point:getY(), z = vehicle:getZ() }, doorPart
end

function Scavenging.findVehicleTarget(shell, radius, wanted, excludeNear)
    local best, bestScore = nil, -math.huge

    local ok, vehicles = pcall(function()
        local set = getCell():getVehicles()
        if set == nil or set.toArray == nil then return nil end
        return set:toArray()
    end)
    if not ok or vehicles == nil then return nil end
    local walked = 0
    for _, vehicle in pairs(vehicles) do
        walked = walked + 1
        if walked > 64 then break end

        if vehicle ~= nil then
        pcall(function()
            local distance = (vehicle:getX() - shell:getX())^2 + (vehicle:getY() - shell:getY())^2
            if distance > radius * radius or math.abs(vehicle:getZ() - shell:getZ()) > 0.5 then return end
            if excludeNear and (vehicle:getX()-excludeNear.x)^2 + (vehicle:getY()-excludeNear.y)^2 <= 36 then return end
            local visited = Scavenging.vehicleVisited[vehicle] or {}
            for _, id in ipairs({ "TruckBed", "TruckBedOpen", "EngineDoor" }) do
                local part = vehicle:getPartById(id)
                if part and nowMs() >= (visited[id] or 0) then
                    local at, door = vehicleAccess(vehicle, part)
                    local reservation = "vehicle:" .. tostring(vehicle:getId()) .. ":" .. id
                    if at and reservationFree(Scavenging.reservations[reservation]) then
                        local stand = Scavenging.standPoint(at)
                        local score = (id == "EngineDoor" and 5 or 20) - math.sqrt(distance)
                        if stand and score > bestScore then
                            bestScore = score
                            best = { x=at.x, y=at.y, z=at.z, stand=stand, vehicle=vehicle,
                                part=part, doorPart=door, container=part:getItemContainer(),
                                reservation=reservation, wanted=wanted, score=score }
                        end
                    end
                end
            end
        end)
        end
    end
    return best
end

local function vehicleSearch(plan, shell)
    local target, now = plan.target, nowMs()
    local ok, at, door = pcall(vehicleAccess, target.vehicle, target.part)
    if not ok or at == nil or (at.x-shell:getX())^2 + (at.y-shell:getY())^2 > 4 then
        return false, "vehicle_unavailable"
    end
    if plan.searchUntilMs == nil then
        if door then
            local opened = pcall(function()
                door:getDoor():setOpen(true)
                target.vehicle:transmitPartDoor(door)
            end)
            if not opened then return false, "vehicle_door_failed" end
        end
        pcall(function() shell:faceThisObject(target.vehicle) end)
        pcall(function() ProjectALife.Animations.apply(shell, "search_mid") end)
        plan.searchUntilMs = now + 6500
        plan.expiresAt = math.max(plan.expiresAt, now + 9000)
        return nil
    end
    if now < plan.searchUntilMs then return nil end
    pcall(function() ProjectALife.Animations.clear(shell) end)
    local visited = Scavenging.vehicleVisited[target.vehicle] or {}
    visited[target.part:getId()] = now + 120000
    Scavenging.vehicleVisited[target.vehicle] = visited
    Scavenging.metrics.vehiclesSearched = (Scavenging.metrics.vehiclesSearched or 0) + 1
    local found = target.container and bestInContainer(shell:getCurrentSquare(), target.container, nil, target.wanted)
    if found then
        target.item = found.item
        target.x, target.y, target.z = shell:getX(), shell:getY(), shell:getZ()
    end
    return true
end

function Scavenging.keptOut(actor, target)
    local policy = ProjectALife.DoorPolicy
    if type(target) ~= "table" or policy == nil or type(policy.keepsOut) ~= "function" then return false end
    local x, y = tonumber(target.x), tonumber(target.y)
    if x == nil or y == nil then return false end
    local ok, out = pcall(policy.keepsOut, actor, x, y, true)
    if not (ok == true and out == true) and type(policy.homeRefusal) == "function" then
        local asked, kind = pcall(policy.homeRefusal, actor, x, y)
        if asked == true and kind ~= nil then
            ok, out = true, true
            policy.note("path", kind)
        end
    end
    if ok ~= true or out ~= true then return false end
    Scavenging.metrics.baseSkips = (Scavenging.metrics.baseSkips or 0) + 1
    return true
end

local function defaultFindTarget(actor, shell, radius, wanted, excludeNear)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local originX, originY, originZ = math.floor(shell:getX()), math.floor(shell:getY()),
        math.floor(shell:getZ())
    local maximum = math.max(1, math.min(256, math.floor(
        tonumber(Scavenging.adapters.searchSquares)
            or Scavenging.settings.maximumSquares)))
    local inspected, best, bestScore = 0, nil, -math.huge
    local phase = stableHash(actor and actor.uid) % 4
    for ring = 0, radius do
        for edge = -ring, ring do
            local offsets
            if ring == 0 then
                offsets = { { 0, 0 } }
            else
                offsets = {
                    { edge, -ring }, { ring, edge },
                    { -edge, ring }, { -ring, -edge },
                }
            end
            for offsetIndex = 1, #offsets do
                local offset = offsets[(offsetIndex + phase - 1) % #offsets + 1]
                inspected = inspected + 1
                local x, y = originX + offset[1], originY + offset[2]
                local atHome = excludeNear ~= nil and (x - excludeNear.x) ^ 2 + (y - excludeNear.y) ^ 2 <= 36
                local target = not atHome and targetOnSquare(cell:getGridSquare(x, y, originZ), wanted) or nil
                if target ~= nil then
                    target.stand = Scavenging.standPoint(target)
                    local score = target.score - ring * 0.4
                    if target.stand ~= nil and score > bestScore and not Scavenging.keptOut(actor, target) then
                        best, bestScore = target, score
                    end
                end
                if inspected >= maximum then return best or Scavenging.findVehicleTarget(shell, radius, wanted, excludeNear) end
            end
        end
    end
    return best or Scavenging.findVehicleTarget(shell, radius, wanted, excludeNear)
end

local function bagContainer(item)
    if item == nil or item.getItemContainer == nil then return nil, 0 end
    local ok, container = pcall(function() return item:getItemContainer() end)
    if not ok or container == nil then return nil, 0 end
    local capacityOk, capacity = pcall(function() return container:getCapacity() end)
    return container, capacityOk and tonumber(capacity) or 0
end

function Scavenging.bagFor(shell, inventory)
    if shell == nil then return nil end
    local best, bestCapacity = nil, 0
    if shell.getClothingItem_Back ~= nil then
        local ok, worn = pcall(function() return shell:getClothingItem_Back() end)
        if ok then best, bestCapacity = bagContainer(worn) end
    end
    if best == nil and shell.getWornItems ~= nil then
        pcall(function()
            local worn = shell:getWornItems()
            if worn == nil or worn.getItemByIndex == nil then return end
            for index = 0, math.min(listSize(worn), 16) - 1 do
                local container, capacity = bagContainer(worn:getItemByIndex(index))
                if container ~= nil and capacity > bestCapacity then
                    best, bestCapacity = container, capacity
                end
            end
        end)
    end
    if best == nil then
        local ok, items = pcall(function()
            return (inventory or shell:getInventory()):getItems()
        end)
        if ok then
            for index = 0, math.min(listSize(items), 64) - 1 do
                local container, capacity = bagContainer(listGet(items, index))
                if container ~= nil and capacity > bestCapacity then
                    best, bestCapacity = container, capacity
                end
            end
        end
    end
    return best
end

function Scavenging.carryInHands(shell, item)
    if shell == nil or item == nil then return false end

    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    if server and not client then return false end
    local shown = false
    pcall(function()
        if shell:getSecondaryHandItem() ~= nil then return end
        shell:setSecondaryHandItem(item)
        shell:resetModelNextFrame()
        shell:getModData().ProjectALifeCarryInHands = true
        shown = true
    end)
    if shown then
        local animations = ProjectALife.Animations
        if animations ~= nil and type(animations.refreshWeapon) == "function" then
            pcall(animations.refreshWeapon, shell, false)
        end
    end
    return shown
end

function Scavenging.releaseHands(shell)
    if shell == nil then return false end
    local released = false
    pcall(function()
        local data = shell:getModData()
        if data.ProjectALifeCarryInHands ~= true then return end
        local held = shell:getSecondaryHandItem()
        if held ~= nil then
            local ownerOk, owner = pcall(function() return held:getContainer() end)

            if ownerOk and owner ~= nil and owner == shell:getInventory() then return end
            shell:setSecondaryHandItem(nil)
            shell:resetModelNextFrame()
        end
        data.ProjectALifeCarryInHands = nil
        released = true
    end)
    if released then
        local animations = ProjectALife.Animations
        if animations ~= nil and type(animations.refreshWeapon) == "function" then
            pcall(animations.refreshWeapon, shell, true)
        end
    end
    return released
end

function Scavenging.carried(shell, inventory)
    local result = {}
    pcall(function()
        inventory = inventory or shell:getInventory()
        local items = inventory:getItems()
        for index = 0, listSize(items) - 1 do result[#result + 1] = items:get(index) end
        local bag = Scavenging.bagFor(shell, inventory)
        if bag == nil or bag == inventory then return end
        local packed = bag:getItems()
        for index = 0, math.min(listSize(packed), 128) - 1 do
            result[#result + 1] = packed:get(index)
        end
    end)
    return result
end

local function moveItem(source, inventory, item, owner)
    if not authoritative() or source == nil or inventory == nil or source == inventory then return false end
    local sourceOk, actualSource = pcall(function() return item:getContainer() end)
    if not sourceOk or actualSource ~= source then return false end
    local capacityOk, room = pcall(function() return inventory:hasRoomFor(owner, item) end)
    if capacityOk and room == false then return false end
    if containsItemId(inventory, item) == true then return false end
    local containedOk, contained = pcall(function() return source:getItems():contains(item) end)
    if not containedOk or contained ~= true then return false end
    local removed = pcall(function() source:Remove(item) end)
    if not removed then return false end
    local verifyOk, stillContained = pcall(function() return source:getItems():contains(item) end)
    if not verifyOk then
        local ownerOk, ownerNow = pcall(function() return item:getContainer() end)
        if ownerOk and ownerNow == nil then restoreItem(source, item) end
        return false
    end
    if stillContained == true then return false end
    local addedOk, added = pcall(function() return inventory:AddItem(item) end)
    local destinationOk, destination = pcall(function() return item:getContainer() end)
    local inventoryContainsOk, inventoryContains = pcall(function() return inventory:getItems():contains(item) end)
    if not addedOk or added ~= item or not destinationOk or destination ~= inventory
            or not inventoryContainsOk or inventoryContains ~= true then
        if addedOk and added ~= nil then pcall(function() inventory:Remove(added) end) end
        if added ~= item then pcall(function() inventory:Remove(item) end) end
        restoreItem(source, item)
        return false
    end
    return true
end

Scavenging.moveItem = moveItem

local function transfer(shell, target, serverConfirmed)
    if not authoritative() then return false end
    if type(Scavenging.adapters.transfer) == "function" then
        return Scavenging.adapters.transfer(shell, target) == true
    end
    if target.container == nil or target.item == nil then return false end
    if type(isClient) == "function" and isClient() and serverConfirmed ~= true then
        require "ProjectALife/Loot/ALifeLootTransfer"
        return ProjectALife.LootTransfer.request(shell, target)
    end
    if target.x ~= nil then
        local reachable, allowed = pcall(function()
            local from = shell:getCurrentSquare()
            local to = getCell():getGridSquare(math.floor(target.x), math.floor(target.y), math.floor(target.z))
            return from ~= nil and to ~= nil and from:canReachTo(to)
        end)
        if not reachable or not allowed then return false end
    end
    local inventoryOk, inventory = pcall(function() return shell:getInventory() end)
    if not inventoryOk or inventory == nil then return false end

    local bag = Scavenging.bagFor(shell, inventory)
    local landed = bag ~= nil and bag ~= inventory
        and moveItem(target.container, bag, target.item, shell)
    if landed then
        Scavenging.metrics.bagged = Scavenging.metrics.bagged + 1
    elseif not moveItem(target.container, inventory, target.item, shell) then
        Scavenging.metrics.transferFailed = Scavenging.metrics.transferFailed + 1
        return false
    else

        if Scavenging.carryInHands(shell, target.item) then
            Scavenging.metrics.handCarried = (Scavenging.metrics.handCarried or 0) + 1
        end
    end
    local destination = landed and bag or inventory
    if not ShellState.markScavenged(target.item) then

        pcall(function() destination:Remove(target.item) end)
        restoreItem(target.container, target.item)
        return false
    end
    if not (type(isClient) == "function" and isClient())
            and type(sendRemoveItemFromContainer) == "function" then
        pcall(sendRemoveItemFromContainer, target.container, target.item)
    end
    if type(ShellState.noteForeignRemoval) == "function" then
        pcall(ShellState.noteForeignRemoval, target.container, target.item, "scavenge", shell)
    end

    local credited = false
    pcall(function()

        local weapons = ProjectALife.Weapons
        if weapons == nil or type(weapons.ammoValue) ~= "function" then return end
        local slot, rounds = "primary", 0
        if type(weapons.creditFor) == "function" then

            slot, rounds = weapons.creditFor(shell, target.item)
        else
            rounds = weapons.ammoValue(target.item)

            pcall(function()
                local equipped = tostring(shell:getModData().ProjectALifeEquippedSlot or "")
                if equipped == "secondary" then slot = "secondary" end
            end)
        end
        if (tonumber(rounds) or 0) <= 0 then return end
        weapons.addReserve(shell, slot, rounds)

        pcall(function() target.item:getModData().ProjectALifeScavenged = nil end)
        credited = true
    end)
    if credited then

        pcall(function() destination:Remove(target.item) end)
        Scavenging.releaseHands(shell)
        Scavenging.metrics.ammoCredited = (Scavenging.metrics.ammoCredited or 0) + 1
    else
        pcall(function() ProjectALife.DeathInventory.add(shell, target.item) end)
    end

    pcall(function()
        local event = Scavenging.foundEventFor(itemText(target.item))
        local voice = ProjectALife.Voice
        local spoken = Scavenging.foundSpoken(target.item)
        if event ~= nil and voice ~= nil then voice.play(shell, event, spoken) end
    end)
    Scavenging.metrics.collected = Scavenging.metrics.collected + 1
    return true
end

Scavenging.transfer = transfer

function Scavenging.cargo(shell)
    local result = {}

    for _, item in ipairs(Scavenging.carried(shell)) do
        local ok, marked = pcall(function()
            return item:getModData().ProjectALifeScavenged == true
        end)
        if ok and marked then result[#result + 1] = item end
    end
    return result
end

function Scavenging.deposit(shell, container, maximum)
    if not authoritative() or container == nil then return 0 end
    local inventory = shell:getInventory()
    local equipped
    pcall(function() equipped = ProjectALife.Weapons.current(shell) end)
    local count = 0
    for _, item in ipairs(Scavenging.cargo(shell)) do
        if count >= (maximum or 4) then break end

        local holderOk, holder = pcall(function() return item:getContainer() end)
        if item ~= equipped and holderOk and holder ~= nil
                and moveItem(holder, container, item, shell) then
            item:getModData().ProjectALifeScavenged = nil
            if type(sendAddItemToContainer) == "function" then
                pcall(sendAddItemToContainer, container, item)
            end
            count = count + 1
        end
    end
    if count > 0 then

        pcall(function()
            ProjectALife.DeathInventory.clear(shell)

            for _, packed in ipairs(Scavenging.carried(shell, inventory)) do
                ProjectALife.DeathInventory.add(shell, packed)
            end
        end)
        Scavenging.metrics.deposited = Scavenging.metrics.deposited + count

        Scavenging.releaseHands(shell)
    end
    return count
end

local function release(plan)
    if type(plan) ~= "table" then return end
    local animations = ProjectALife.Animations
    if plan.searchPose ~= nil and animations ~= nil and animations.current ~= nil
            and animations.current[plan.shell] == plan.searchPose then
        local ok, data = pcall(function() return plan.shell:getModData() end)
        local executor = ProjectALife.Executor
        local lease = not (executor and executor.clientAuthority())
            or (executor.executed[plan.uid] and executor.authorityFor(plan.shell) == true)
        if lease and ok and data.ProjectALifeUID == plan.uid
                and tonumber(data.ProjectALifeGeneration) == plan.generation then
            pcall(animations.clear, plan.shell)
        end
    end
    if plan.reservation and Scavenging.reservations[plan.reservation] == plan then
        Scavenging.reservations[plan.reservation] = nil
    end
    local key = plan.uid .. ":" .. tostring(plan.generation)
    if Scavenging.activeByActor[key] == plan then Scavenging.activeByActor[key] = nil end
end

function Scavenging.configure(adapters)
    Scavenging.adapters = adapters or {}
    Scavenging.settings = {
        radius = math.max(1, math.floor(tonumber(Scavenging.adapters.radius)
            or defaults.radius)),
        maximumSquares = math.max(1, math.floor(
            tonumber(Scavenging.adapters.maximumSquares) or defaults.maximumSquares)),
    }
end

function Scavenging.reset()
    Scavenging.reservations = {}
    Scavenging.activeByActor = {}
    Scavenging.sequence = 0
    Scavenging.vehicleVisited = setmetatable({}, { __mode = "k" })
end

function Scavenging.cancel(plan, reason)
    if type(plan) ~= "table" then return false end
    if plan.status == "moving" then
        plan.status = "cancelled"
        plan.reason = reason or "scavenging_cancelled"
    end
    release(plan)
    return true
end

function Scavenging.cancelActor(uid, generation, reason)
    local cancelled = 0
    for key, plan in pairs(Scavenging.activeByActor) do
        if plan.uid == uid and (generation == nil or plan.generation == generation) then
            Scavenging.cancel(plan, reason)
            cancelled = cancelled + 1
        end
    end
    return cancelled
end

function Scavenging.start(actor, shell, options)
    options = options or {}
    if not authoritative() then return nil, "scavenging_not_authoritative" end
    if Scavenging.adapters.enabled == false then return nil, "scavenging_disabled" end
    local finder = Scavenging.adapters.findTarget or defaultFindTarget
    local ok, target = true, options.target
    if target == nil then
        ok, target = pcall(finder, actor, shell,
            math.max(1, math.floor(options.radius or Scavenging.settings.radius)), options.wanted, options.excludeNear)
    end
    if not ok or type(target) ~= "table"
            or (target.vehicle == nil and (target.container == nil
                or (target.item == nil and target.unexplored ~= true))) then
        return nil, "scavenge_target_missing"
    end

    if Scavenging.keptOut(actor, target) then return nil, "scavenge_player_base" end
    target.supplyRun = options.supplyRun == true
    target.wanted = options.wanted or target.wanted
    local destination = target
    if Scavenging.adapters.findTarget == nil and type(getCell) == "function" then
        destination = target.stand or Scavenging.standPoint(target)
        if destination == nil then return nil, "scavenge_target_unreachable" end
    end
    local reservation = target.reservation or reservationFor(target.container, target.item)
    if not reservationFree(Scavenging.reservations[reservation]) then
        return nil, "scavenge_target_reserved"
    end
    Scavenging.sequence = Scavenging.sequence + 1
    local plan = {
        uid = actor.uid,
        generation = actor.generation,
        shell = shell,
        target = target,
        reservation = reservation,
        status = "moving",
        searchRequired = options.searched ~= true and target.vehicle == nil,

        expiresAt = nowMs() + 15000,
    }
    Scavenging.reservations[reservation] = plan
    Scavenging.activeByActor[actor.uid .. ":" .. tostring(actor.generation)] = plan
    local action, actionError = Movement.begin(actor, shell, destination, {
        doorsOnly = options.supplyRun == true,
        operationId = "scavenge:move:" .. actor.uid .. ":" .. actor.generation
            .. ":" .. Scavenging.sequence,

        tolerance = math.min(0.35, tonumber(options.tolerance) or 0.35),
        stallMs = options.stallMs or movementDefaults.stallMs,
        pathStartupGraceMs = options.pathStartupGraceMs
            or movementDefaults.pathStartupGraceMs,
        maximumRepathMs = options.maximumRepathMs
            or movementDefaults.maximumRepathMs,
        maximumConsecutiveStalls = options.maximumConsecutiveStalls
            or movementDefaults.maximumConsecutiveStalls,
        maximumTraversalFailures = options.maximumTraversalFailures
            or movementDefaults.maximumTraversalFailures,
        timeoutMs = options.timeoutMs or 12000,
    })
    if action == nil then
        Scavenging.cancel(plan, actionError)
        return nil, actionError
    end
    plan.action = action
    return plan
end

local function searchContainer(plan, shell)
    local target = plan.target
    if target.x ~= nil then
        local ok, reachable = pcall(function()
            local from = shell:getCurrentSquare()
            local to = getCell():getGridSquare(math.floor(target.x), math.floor(target.y), math.floor(target.z))
            return from ~= nil and to ~= nil and from:canReachTo(to)
        end)
        if not ok or not reachable then return false, "scavenge_out_of_reach" end
    end
    local now = nowMs()
    if plan.searchUntilMs == nil then
        plan.searchUntilMs = now + 3900
        plan.expiresAt = math.max(plan.expiresAt, plan.searchUntilMs + 2000)
        pcall(function()
            if target.objectIndex ~= nil then
                local square = getCell():getGridSquare(math.floor(target.x), math.floor(target.y), math.floor(target.z))

                if square == nil then return end
                local object = Scavenging.objectForSpot(square, target)
                if object ~= nil then shell:faceThisObject(object) end
            end
        end)
        plan.searchPose = target.preset or "search_mid"
        pcall(function() ProjectALife.Animations.apply(shell, plan.searchPose) end)
        return nil
    end
    if now < plan.searchUntilMs then return nil end
    pcall(function() ProjectALife.Animations.clear(shell) end)
    if target.unexplored then
        local found = Scavenging.targetAt(target, target.wanted, true, shell)
        target.item = found and found.item or nil
    end
    return true
end

function Scavenging.tick(plan, shell)
    if type(plan) ~= "table" or plan.status ~= "moving" then
        return plan and plan.status or "failed"
    end
    if plan.action.status == "running" then return "moving" end
    if plan.action.status ~= "complete" then
        plan.status = "failed"
        plan.reason = plan.action.result or plan.action.status
        release(plan)
        return plan.status
    end
    if plan.target.vehicle ~= nil then
        local searched, reason = vehicleSearch(plan, shell)
        if searched == nil then return "moving" end
        if not searched or plan.target.item == nil then
            plan.status = searched and "complete" or "failed"
            plan.reason = reason or "vehicle_inspected"
            release(plan)
            return plan.status
        end
    elseif plan.searchRequired then
        local searched, reason = searchContainer(plan, shell)
        if searched == nil then return "moving" end
        if not searched or plan.target.item == nil then
            plan.status = searched and "complete" or "failed"
            plan.reason = reason or "container_empty"
            release(plan)
            return plan.status
        end
    end
    local transferred = transfer(shell, plan.target)
    if transferred == nil then return "moving" end
    if transferred then
        plan.status = "complete"
        plan.result = "item_collected"
    else
        plan.status = "failed"
        plan.reason = "item_transfer_failed"
    end
    release(plan)
    return plan.status
end

return Scavenging
