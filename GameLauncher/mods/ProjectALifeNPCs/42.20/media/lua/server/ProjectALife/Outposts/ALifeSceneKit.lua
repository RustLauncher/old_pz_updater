require "ProjectALife/World/ALifeWreck"
require "ProjectALife/World/ALifeRoads"
require "ProjectALife/Core/ALifePersistence"
require "ProjectALife/Outposts/ALifeOutpostLights"

ProjectALife = ProjectALife or {}

local SceneKit = {

    placed = {},
    fallbackStore = { records = {} },
    settings = {

        carOffset = 2.8,

        shoulderOffset = 5.6,
        shoulderCount = 2,

        brokenCarLane = 1.5,
        brokenCarNose = 2.6,
        policeCar = "Base.CarLightsPolice",
        civilianCar = "Base.CarNormal",
        civilianPool = { "Base.SUV", "Base.PickUpTruck", "Base.CarStationWagon", "Base.CarNormal" },

        shoulderBlocks = { alongX = "street_decoration_01_28", alongY = "street_decoration_01_29" },

        blockadeSpacing = 150,

        blockadeCapCount = 1,
        blockadeCapRadius = 250,

        cleanupKinds = { blockade = "blockade" },

        orphanGraceMs = 60000,

        guardReach = 40,

        drainBudget = 12,

        drainClearRadius = 30,

        scanMs = 5000,
    },
    metrics = { scenes = 0, vehicles = 0, objects = 0, refused = 0,
        live = 0, draining = 0, condemned = 0, drained = 0, spaced = 0, capped = 0 },

    adapters = {},

    emptySince = {},
    scanAtMs = 0,
}
ProjectALife.SceneKit = SceneKit

function SceneKit.vehicleFor(key, index)
    local seed = 0
    local text = tostring(key or "")
    for i = 1, #text do seed = (seed * 31 + string.byte(text, i)) % 2147483647 end
    local pool = SceneKit.settings.civilianPool
    return pool[(seed + math.max(0, (tonumber(index) or 1) - 1)) % #pool + 1]
end

local function sceneStore()
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.bucket) == "function" then
        local values = persistence.bucket("scenes", { records = {} })
        if type(values) == "table" then
            values.records = type(values.records) == "table" and values.records or {}
            return values
        end
    end
    return SceneKit.fallbackStore
end

local function persist(key, record)
    sceneStore().records[key] = record
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then
        persistence.touch()
    end
end

local function plan(key, record, created)
    return {
        key = key, kind = record.kind, created = created == true,
        origin = record.origin, slots = record.slots,
    }
end

local function authoritative()
    if type(isClient) == "function" and isClient() then return false end
    return true
end

local function squareAt(x, y, z)
    local square
    pcall(function()
        square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    end)
    return square
end

local function atan2(y, x)
    if type(math.atan2) == "function" then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function directionIndex(dx, dy)
    local angle = atan2(-dy, dx)
    if angle < 0 then angle = angle + 2 * math.pi end

    local eighth = math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8
    local byEighth = { [0] = 6, [1] = 7, [2] = 0, [3] = 1, [4] = 2, [5] = 3, [6] = 4, [7] = 5 }
    return byEighth[eighth] or 0
end

local function direction(dx, dy)
    local value
    pcall(function()
        if IsoDirections ~= nil and type(IsoDirections.fromIndex) == "function" then
            value = IsoDirections.fromIndex(directionIndex(dx, dy))
        end
    end)
    if value == nil then pcall(function() value = IsoDirections.N end) end
    return value
end

local function placeVehicle(kind, x, y, z, dx, dy, sceneKey, sceneKind)
    local vehicle
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        vehicle = addVehicleDebug(kind, direction(dx, dy), nil, square)
        if vehicle ~= nil then
            local data = vehicle:getModData()
            data.ProjectALife_Setpiece = true
            data.ProjectALifeSceneKey = sceneKey
            data.ProjectALifeSceneKind = sceneKind
        end
    end)
    return vehicle
end

local function openBonnet(vehicle)
    pcall(function()
        local part = vehicle:getPartById("EngineDoor")
        if part == nil then return end
        local door = part:getDoor()
        if door == nil then return end
        door:setOpen(true)
        pcall(function() vehicle:transmitPartDoor(part) end)
    end)
end

local function ageCar(vehicle, options)
    local wreck = ProjectALife.Wreck
    if vehicle == nil or wreck == nil or type(wreck.disable) ~= "function" then return end
    if type(options) ~= "table" then
        pcall(wreck.disable, vehicle, {
            rust = 0.35, engineCondition = 0, batteryCondition = 0,
        })
        return
    end
    options.rust = tonumber(options.rust) or 0.35
    options.engineCondition = 0
    options.batteryCondition = 0
    pcall(wreck.disable, vehicle, options)
end

local function placeObject(sprite, x, y, z, sceneKey, sceneKind)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        local object = IsoObject.new(getCell(), square, getSprite(sprite))
        if object == nil then return end
        local data = object:getModData()
        data.ProjectALife_Setpiece = true
        data.ProjectALifeSceneKey = sceneKey
        data.ProjectALifeSceneKind = sceneKind
        square:AddTileObject(object)
        if type(isServer) == "function" and isServer() then
            pcall(function() object:transmitCompleteItemToClients() end)
        end
        placed = object
    end)
    return placed
end

local function rollbackObjects(objects)
    for index = #objects, 1, -1 do
        local object = objects[index]
        pcall(function()
            local square = object and object:getSquare() or nil
            if square == nil then return end
            local lights = ProjectALife.OutpostLights
            if lights ~= nil and lights.isEngineFire(object) and lights.removeCampfire(square) then return end
            local removed = pcall(function()
                square:transmitRemoveItemFromSquare(object)
            end)
            if not removed then
                pcall(function() square:RemoveTileObject(object) end)
            end
        end)
    end
end

local function rollbackVehicles(vehicles)
    for index = #vehicles, 1, -1 do
        local vehicle = vehicles[index]
        pcall(function() vehicle:permanentlyRemove() end)
        pcall(function() vehicle:removeFromWorld() end)
        pcall(function() vehicle:removeFromSquare() end)
    end
end

local function sceneSquareUsable(x, y, z, squareAllowed)
    local square = squareAt(x, y, z)
    if square == nil then return false end
    local usable = true
    local ok = pcall(function()
        if not square:isOutside() or square:getBuilding() ~= nil
                or square:getPlayer() ~= nil or square:getVehicleContainer() ~= nil
                or square:isSolid() or square:isSolidTrans()
                or square:isFree(false) ~= true then
            usable = false
            return
        end
        if SafeHouse ~= nil and SafeHouse.isSafeHouse ~= nil
                and SafeHouse.isSafeHouse(square, nil, true) then
            usable = false
            return
        end
        local objects = square:getObjects()
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local data = object and object:getModData() or nil
            if data ~= nil and data.ProjectALife_Setpiece then
                usable = false
                return
            end
        end
    end)
    if not ok or not usable then return false end
    if type(squareAllowed) == "function" then
        local accepted, allowed = pcall(squareAllowed, {
            x = math.floor(x) + 0.5,
            y = math.floor(y) + 0.5,
            z = math.floor(z),
        })
        if not accepted or allowed ~= true then return false end
    end
    return true
end

local function lineVector(heading)
    local h = tonumber(heading) or 0
    return -math.sin(h), math.cos(h)
end

function SceneKit.blockade(point, heading, key, options)
    if type(point) ~= "table" then return false, "scene_point_missing" end
    if not authoritative() then return false, "scene_not_authoritative" end
    key = tostring(key or (math.floor(point.x) .. ":" .. math.floor(point.y)))
    local existing = SceneKit.placed[key]
    if existing ~= nil then
        return true, "scene_already_placed", {
            key = key, kind = existing.kind, created = false,
            origin = existing.origin, slots = existing.slots,
        }
    end
    local px, py = lineVector(heading)
    local z = tonumber(point.z) or 0
    local settings = SceneKit.settings
    local blocks = settings.shoulderBlocks
    local shoulderBlock = math.abs(px) >= math.abs(py) and blocks.alongX or blocks.alongY
    local squareAllowed = type(options) == "table" and options.squareAllowed or nil
    local cars, props, slots = {}, {}, {}
    for _, side in ipairs({ 1, -1 }) do
        cars[#cars + 1] = {
            x = point.x + px * side * settings.carOffset,
            y = point.y + py * side * settings.carOffset,
            dx = -px * side, dy = -py * side,
        }
        for step = 0, settings.shoulderCount - 1 do
            local along = settings.shoulderOffset + step
            props[#props + 1] = {
                x = point.x + px * side * along,
                y = point.y + py * side * along,
                sprite = shoulderBlock,
            }
        end
    end
    local axisX, axisY = math.cos(tonumber(heading) or 0), math.sin(tonumber(heading) or 0)
    for _, back in ipairs({ 2, 4 }) do
        for _, across in ipairs({ -3, -1, 1, 3 }) do
            slots[#slots + 1] = {
                x = math.floor(point.x - axisX * back + px * across) + 0.5,
                y = math.floor(point.y - axisY * back + py * across) + 0.5,
                z = math.floor(z),
            }
        end
    end
    for _, collection in ipairs({ cars, props, slots }) do
        for _, placement in ipairs(collection) do
            if not sceneSquareUsable(placement.x, placement.y, z, squareAllowed) then
                SceneKit.metrics.refused = SceneKit.metrics.refused + 1
                return false, "blockade_site_unavailable"
            end
        end
    end

    local record = { vehicles = {}, squares = {}, kind = "blockade",
        origin = { x = point.x, y = point.y, z = z }, slots = slots }
    local createdVehicles, createdObjects = {}, {}
    for index, placement in ipairs(cars) do
        local car = placeVehicle(SceneKit.vehicleFor(key, index), placement.x, placement.y, z,
            placement.dx, placement.dy, key, "blockade")
        if car ~= nil then
            createdVehicles[#createdVehicles + 1] = car
            ageCar(car)
            pcall(function()
                record.vehicles[#record.vehicles + 1] = {
                    id = car:getId(), x = math.floor(placement.x),
                    y = math.floor(placement.y), z = z,
                    tag = key, kind = "blockade",
                }
            end)
        end
    end
    for _, placement in ipairs(props) do
        local object = placeObject(placement.sprite, placement.x, placement.y, z,
            key, "blockade")
        if object ~= nil then
            createdObjects[#createdObjects + 1] = object
            record.squares[#record.squares + 1] = {
                x = math.floor(placement.x), y = math.floor(placement.y), z = z,
                sprite = placement.sprite, tag = key, kind = "blockade",
            }
        end
    end
    if #createdVehicles ~= #cars or #createdObjects ~= #props then
        rollbackObjects(createdObjects)
        rollbackVehicles(createdVehicles)
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "blockade_scene_incomplete"
    end
    SceneKit.placed[key] = record
    persist(key, record)
    SceneKit.metrics.vehicles = SceneKit.metrics.vehicles + #createdVehicles
    SceneKit.metrics.objects = SceneKit.metrics.objects + #createdObjects
    SceneKit.metrics.scenes = SceneKit.metrics.scenes + 1
    return true, "scene_placed", plan(key, record, true)
end

SceneKit.settings.campFireSprite = "camping_01_4"

local CAMP_LAYOUT = {
    { sprite = SceneKit.settings.campFireSprite, dx = 0, dy = 0 },
    { sprite = "camping_01_2", dx = -1, dy = -4 },
    { sprite = "camping_01_3", dx = 0, dy = -4 },
    { sprite = "camping_01_2", dx = -6, dy = 0 },
    { sprite = "camping_01_3", dx = -5, dy = 0 },
    { sprite = "camping_01_2", dx = 3, dy = 3 },
    { sprite = "camping_01_3", dx = 4, dy = 3 },
    { sprite = "furniture_seating_outdoor_01_4", dx = -1, dy = 2 },
    { sprite = "furniture_seating_outdoor_01_5", dx = 0, dy = 2 },
    { sprite = "furniture_seating_outdoor_01_7", dx = 2, dy = -1 },
    { sprite = "furniture_seating_outdoor_01_6", dx = 2, dy = 0 },
    { sprite = "furniture_tables_low_01_16", dx = -3, dy = -2 },
}

local CAMP_SLOTS = {
    { 1, 1 }, { -1, 1 }, { -2, 0 }, { 1, -1 },
    { -1, -2 }, { 3, -1 }, { -3, 1 }, { 1, 3 },
}

function SceneKit.placeFire(sprite, x, y, z, sceneKey, sceneKind)
    local lights = ProjectALife.OutpostLights
    local square = lights ~= nil and lights.enabled() and squareAt(x, y, z) or nil
    if square ~= nil then
        local _, _, fire = lights.campfireAt(square, nil, lights.hours())
        if fire ~= nil then
            local data = fire:getModData()
            data.ProjectALife_Setpiece = true
            data.ProjectALifeSceneKey = sceneKey
            data.ProjectALifeSceneKind = sceneKind
            return fire
        end
    end
    return placeObject(sprite, x, y, z, sceneKey, sceneKind)
end

local function campSquareUsable(x, y, z, squareAllowed)
    if not sceneSquareUsable(x, y, z, squareAllowed) then return false end
    local square = squareAt(x, y, z)
    local offRoad = true
    local ok = pcall(function()
        local road = ProjectALife.Road
        if road ~= nil and type(road.isRoadSquare) == "function"
                and road.isRoadSquare(square) then
            offRoad = false
        end
    end)
    return ok and offRoad
end

local function campAnchor(point, squareAllowed)
    local originX, originY = math.floor(point.x), math.floor(point.y)
    local z = math.floor(tonumber(point.z) or 0)
    for radius = 0, 24 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local x, y = originX + dx, originY + dy
                    local viable = campSquareUsable(x, y, z, squareAllowed)
                    if viable then
                        for _, item in ipairs(CAMP_LAYOUT) do
                            if not campSquareUsable(x + item.dx, y + item.dy,
                                    z, squareAllowed) then
                                viable = false
                                break
                            end
                        end
                    end
                    if viable then
                        for _, slot in ipairs(CAMP_SLOTS) do
                            if not campSquareUsable(x + slot[1], y + slot[2],
                                    z, squareAllowed) then
                                viable = false
                                break
                            end
                        end
                    end
                    if viable then return { x = x, y = y, z = z } end
                end
            end
        end
    end
    return nil
end

function SceneKit.camp(point, heading, key, options)
    if type(point) ~= "table" then return false, "scene_point_missing" end
    if not authoritative() then return false, "scene_not_authoritative" end
    key = tostring(key or (math.floor(point.x) .. ":" .. math.floor(point.y)))
    local existing = SceneKit.placed[key]
    if existing ~= nil then
        return true, "scene_already_placed", {
            key = key, kind = existing.kind, created = false,
            origin = existing.origin, slots = existing.slots,
        }
    end
    local squareAllowed = type(options) == "table" and options.squareAllowed or nil
    local origin = campAnchor(point, squareAllowed)
    if origin == nil then
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "camp_site_unavailable"
    end
    local record = { vehicles = {}, squares = {}, kind = "camp",
        origin = origin, slots = {} }
    for _, slot in ipairs(CAMP_SLOTS) do
        record.slots[#record.slots + 1] = {
            x = origin.x + slot[1] + 0.5,
            y = origin.y + slot[2] + 0.5,
            z = origin.z,
        }
    end
    local created = {}
    for _, item in ipairs(CAMP_LAYOUT) do
        local place = item.sprite == SceneKit.settings.campFireSprite and SceneKit.placeFire or placeObject
        local object = place(item.sprite, origin.x + item.dx,
            origin.y + item.dy, origin.z, key, "camp")
        if object ~= nil then
            created[#created + 1] = object
            record.squares[#record.squares + 1] = {
                x = origin.x + item.dx, y = origin.y + item.dy, z = origin.z,
                sprite = item.sprite, tag = key, kind = "camp",
            }
        end
    end
    if #record.squares ~= #CAMP_LAYOUT then
        rollbackObjects(created)
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "camp_scene_incomplete"
    end
    SceneKit.placed[key] = record
    persist(key, record)
    SceneKit.metrics.objects = SceneKit.metrics.objects + #record.squares
    SceneKit.metrics.scenes = SceneKit.metrics.scenes + 1
    return true, "scene_placed", plan(key, record, true)
end

function SceneKit.carCrash(point, heading, key, options)
    if type(point) ~= "table" then return false, "scene_point_missing" end
    if not authoritative() then return false, "scene_not_authoritative" end
    key = tostring(key or (math.floor(point.x) .. ":" .. math.floor(point.y)))
    local existing = SceneKit.placed[key]
    if existing ~= nil then return true, "scene_already_placed", plan(key, existing, false) end
    local h = tonumber(heading) or 0
    local ax, ay, px, py = math.cos(h), math.sin(h), -math.sin(h), math.cos(h)
    local z = math.floor(tonumber(point.z) or 0)
    local squareAllowed = type(options) == "table" and options.squareAllowed or nil
    local cars = {
        { kind = SceneKit.vehicleFor(key, 1), x = point.x + ax,
            y = point.y + ay, dx = ax, dy = ay, blood = 0.6 },
        { kind = SceneKit.vehicleFor(key, 2), x = point.x - ax * 5,
            y = point.y - ay * 5, dx = ax, dy = ay },
    }
    local slots = {
        { x = math.floor(point.x - ax * 7 + px * 2) + 0.5,
            y = math.floor(point.y - ay * 7 + py * 2) + 0.5, z = z },
        { x = math.floor(point.x - ax * 7 - px * 2) + 0.5,
            y = math.floor(point.y - ay * 7 - py * 2) + 0.5, z = z },
    }
    for _, placement in ipairs(cars) do
        if not sceneSquareUsable(placement.x, placement.y, z, squareAllowed) then
            SceneKit.metrics.refused = SceneKit.metrics.refused + 1
            return false, "car_crash_site_unavailable"
        end
    end
    for _, placement in ipairs(slots) do
        if not sceneSquareUsable(placement.x, placement.y, z, squareAllowed) then
            SceneKit.metrics.refused = SceneKit.metrics.refused + 1
            return false, "car_crash_site_unavailable"
        end
    end
    local record = { vehicles = {}, squares = {}, kind = "carCrash",
        origin = { x = point.x, y = point.y, z = z }, slots = slots }
    local created = {}
    for _, placement in ipairs(cars) do
        local car = placeVehicle(placement.kind, placement.x, placement.y, z,
            placement.dx, placement.dy, key, "carCrash")
        if car ~= nil then
            created[#created + 1] = car
            ageCar(car, { blood = placement.blood })
            pcall(function()
                record.vehicles[#record.vehicles + 1] = {
                    id = car:getId(), x = math.floor(placement.x),
                    y = math.floor(placement.y), z = z,
                    tag = key, kind = "carCrash",
                }
            end)
        end
    end
    if #created ~= #cars then
        rollbackVehicles(created)
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "car_crash_scene_incomplete"
    end
    SceneKit.placed[key] = record
    persist(key, record)
    SceneKit.metrics.vehicles = SceneKit.metrics.vehicles + #created
    SceneKit.metrics.scenes = SceneKit.metrics.scenes + 1
    return true, "scene_placed", plan(key, record, true)
end

function SceneKit.brokenCarSlots(bonnet, heading, ringRadius)
    local h = tonumber(heading) or 0
    local radius = tonumber(ringRadius) or 3.2
    local z = math.floor(tonumber(bonnet.z) or 0)
    local slots = { { x = math.floor(bonnet.x) + 0.5, y = math.floor(bonnet.y) + 0.5, z = z } }
    for index = 1, 5 do
        local angle = h + (index / 6 - 0.5) * math.pi
        slots[#slots + 1] = {
            x = math.floor(bonnet.x + math.cos(angle) * radius) + 0.5,
            y = math.floor(bonnet.y + math.sin(angle) * radius) + 0.5,
            z = z,
        }
    end
    return slots
end

function SceneKit.brokenCar(point, heading, key, options)
    if type(point) ~= "table" then return false, "scene_point_missing" end
    if not authoritative() then return false, "scene_not_authoritative" end
    key = tostring(key or (math.floor(point.x) .. ":" .. math.floor(point.y)))
    local existing = SceneKit.placed[key]
    if existing ~= nil then return true, "scene_already_placed", plan(key, existing, false) end
    local h = tonumber(heading) or 0
    local ax, ay, px, py = math.cos(h), math.sin(h), -math.sin(h), math.cos(h)
    local z = math.floor(tonumber(point.z) or 0)
    local squareAllowed = type(options) == "table" and options.squareAllowed or nil
    local settings = SceneKit.settings
    local carX = point.x + px * settings.brokenCarLane
    local carY = point.y + py * settings.brokenCarLane
    local bonnet = { x = carX + ax * settings.brokenCarNose, y = carY + ay * settings.brokenCarNose, z = z }
    local slots = SceneKit.brokenCarSlots(bonnet, h, 3.2)
    if not sceneSquareUsable(carX, carY, z, squareAllowed) then
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "broken_car_site_unavailable"
    end
    for _, placement in ipairs(slots) do
        if not sceneSquareUsable(placement.x, placement.y, z, squareAllowed) then
            SceneKit.metrics.refused = SceneKit.metrics.refused + 1
            return false, "broken_car_site_unavailable"
        end
    end
    local record = { vehicles = {}, squares = {}, kind = "brokenCar",
        origin = bonnet, slots = slots }
    local car = placeVehicle(SceneKit.vehicleFor(key, 1), carX, carY, z, ax, ay, key, "brokenCar")
    if car == nil then
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "broken_car_scene_incomplete"
    end
    ageCar(car, { hoodCondition = 0 })
    openBonnet(car)
    pcall(function()
        record.vehicles[#record.vehicles + 1] = {
            id = car:getId(), x = math.floor(carX), y = math.floor(carY), z = z,
            tag = key, kind = "brokenCar",
        }
    end)
    SceneKit.placed[key] = record
    persist(key, record)
    SceneKit.metrics.vehicles = SceneKit.metrics.vehicles + 1
    SceneKit.metrics.scenes = SceneKit.metrics.scenes + 1
    return true, "scene_placed", plan(key, record, true)
end

local function removeTaggedObjects(key, record)
    local count = 0
    for _, location in ipairs(type(record.squares) == "table" and record.squares or {}) do
        local square = squareAt(location.x, location.y, location.z)
        if square ~= nil then
            pcall(function()
                local objects = square:getObjects()
                for index = objects:size() - 1, 0, -1 do
                    local object = objects:get(index)
                    local data = object and object:getModData() or nil
                    if data ~= nil and tostring(data.ProjectALifeSceneKey or "") == key then
                        local lights = ProjectALife.OutpostLights
                        local engine = lights ~= nil and lights.isEngineFire(object) and lights.removeCampfire(square)
                        if not engine then
                            local removed = pcall(function()
                                square:transmitRemoveItemFromSquare(object)
                            end)
                            if not removed then square:RemoveTileObject(object) end
                        end
                        count = count + 1
                    end
                end
            end)
        end
    end
    return count
end

function SceneKit.untouched(vehicle)
    local untouched = false
    pcall(function()
        untouched = vehicle:isPreviouslyEntered() == false
            and vehicle:isPreviouslyMoved() == false
    end)
    return untouched
end

function SceneKit.dropVehicle(vehicle)
    pcall(function() vehicle:permanentlyRemove() end)
    pcall(function() vehicle:removeFromWorld() end)
    pcall(function() vehicle:removeFromSquare() end)
end

local function removeTaggedVehicles(key, record)
    local count = 0
    pcall(function()
        local vehicles = getCell():getVehicles()
        if vehicles == nil or vehicles.toArray == nil then return end

        for _, vehicle in pairs(vehicles:toArray()) do
            local tag
            pcall(function() tag = vehicle:getModData().ProjectALifeSceneKey end)
            if tostring(tag or "") == key and SceneKit.untouched(vehicle) then
                SceneKit.dropVehicle(vehicle)
                count = count + 1
            end
        end
    end)
    return count
end

function SceneKit.vehicleOn(row, key)
    local square = squareAt(row.x, row.y, row.z)
    if square == nil or type(square.getVehicleContainer) ~= "function" then return nil end
    local found
    pcall(function()
        local vehicle = square:getVehicleContainer()
        if vehicle == nil then return end

        if type(vehicle.hasModData) == "function" and not vehicle:hasModData() then return end
        if tostring(vehicle:getModData().ProjectALifeSceneKey or "") == key then found = vehicle end
    end)
    return found
end

function SceneKit.removeSceneVehicles(key, record)
    if record.state == "released" then return 0 end
    local count, missing = 0, false
    for _, row in ipairs(type(record.vehicles) == "table" and record.vehicles or {}) do
        local vehicle = SceneKit.vehicleOn(row, key)
        if vehicle == nil then
            missing = true
        elseif SceneKit.untouched(vehicle) then
            SceneKit.dropVehicle(vehicle)
            count = count + 1
        end
    end
    if missing then count = count + removeTaggedVehicles(key, record) end
    return count
end

function SceneKit.removeScene(key, record)
    local count = removeTaggedObjects(key, record) + SceneKit.removeSceneVehicles(key, record)
    SceneKit.placed[key] = nil
    sceneStore().records[key] = nil
    SceneKit.emptySince[key] = nil
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
    return count
end

function SceneKit.remove(key)
    key = tostring(key or "")
    local record = SceneKit.placed[key] or sceneStore().records[key]
    if type(record) ~= "table" then return false, "scene_not_found" end
    SceneKit.removeScene(key, record)
    return true
end

function SceneKit.within(record, kind, x, y, limit)
    if type(record) ~= "table" or record.kind ~= kind or type(record.origin) ~= "table" then return false end
    local dx = (tonumber(record.origin.x) or 0) - (tonumber(x) or 0)
    local dy = (tonumber(record.origin.y) or 0) - (tonumber(y) or 0)
    return dx * dx + dy * dy <= limit
end

function SceneKit.siteRefusal(kind, point)
    if kind ~= "blockade" or type(point) ~= "table" then return nil end
    local spacing = tonumber(SceneKit.settings.blockadeSpacing) or 0
    if spacing <= 0 then return nil end
    local limit = spacing * spacing
    for _, record in pairs(sceneStore().records) do
        if SceneKit.within(record, kind, point.x, point.y, limit) then
            SceneKit.metrics.spaced = (tonumber(SceneKit.metrics.spaced) or 0) + 1
            return "blockade_spacing"
        end
    end
    return nil
end

function SceneKit.capReached(kind, x, y)
    if kind ~= "blockade" then return false end
    local count = math.floor(tonumber(SceneKit.settings.blockadeCapCount) or 0)
    local radius = tonumber(SceneKit.settings.blockadeCapRadius) or 0
    if count <= 0 or radius <= 0 then return false end
    local limit, live = radius * radius, 0
    for _, record in pairs(sceneStore().records) do
        if SceneKit.within(record, kind, x, y, limit) and record.state ~= "draining" then
            live = live + 1
            if live >= count then
                SceneKit.metrics.capped = (tonumber(SceneKit.metrics.capped) or 0) + 1
                return true
            end
        end
    end
    return false
end

function SceneKit.bind(key, groupId)
    key = tostring(key or "")
    local record = SceneKit.placed[key] or sceneStore().records[key]
    if type(record) ~= "table" or groupId == nil then return false end
    record.groupId = tostring(groupId)
    SceneKit.placed[key] = record
    persist(key, record)
    return true
end

function SceneKit.census()
    local alive, guards, pending = {}, {}, {}
    local registry = SceneKit.adapters.registry or ProjectALife.ActorRegistry
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record)
            local memory = type(record.memory) == "table" and record.memory or nil
            if memory == nil or memory.groupId == nil or record.lifecycle == "dead" then return end
            local group = tostring(memory.groupId)
            alive[group] = true
            local at = record.worldPosition
            if type(memory.stance) == "string" and type(at) == "table" then
                local list = guards[memory.stance] or {}
                guards[memory.stance] = list
                list[#list + 1] = { group = group, x = tonumber(at.x) or 0, y = tonumber(at.y) or 0 }
            end
        end)
    end
    local service = SceneKit.adapters.service or ProjectALife.DebugService
    if type(service) == "table" and type(service.groups) == "table" then
        for _, group in pairs(service.groups) do
            if type(group) == "table" and group.sceneKey ~= nil then pending[tostring(group.sceneKey)] = true end
        end
    end
    return alive, guards, pending
end

function SceneKit.manned(key, record, alive, guards, pending)
    if pending[key] then return true end
    if record.groupId ~= nil then return alive[tostring(record.groupId)] == true end
    local stance = SceneKit.settings.cleanupKinds[record.kind]
    local reach = tonumber(SceneKit.settings.guardReach) or 40
    local limit = reach * reach
    for _, guard in ipairs(guards[stance] or {}) do
        local dx = guard.x - (tonumber(record.origin.x) or 0)
        local dy = guard.y - (tonumber(record.origin.y) or 0)
        if dx * dx + dy * dy <= limit then
            SceneKit.bind(key, guard.group)
            return true
        end
    end
    return false
end

function SceneKit.condemnOrphans(now)
    local kinds = type(SceneKit.settings.cleanupKinds) == "table" and SceneKit.settings.cleanupKinds or {}
    local grace = tonumber(SceneKit.settings.orphanGraceMs) or 60000
    local alive, guards, pending = SceneKit.census()
    local live, draining = 0, 0
    for key, record in pairs(sceneStore().records) do
        if type(record) == "table" and kinds[record.kind] ~= nil and type(record.origin) == "table"
                and record.state ~= "released" then
            if record.state == "draining" then
                draining = draining + 1
            elseif SceneKit.manned(key, record, alive, guards, pending) then
                SceneKit.emptySince[key] = nil
                live = live + 1
            else
                local since = SceneKit.emptySince[key] or now
                SceneKit.emptySince[key] = since
                if now - since >= grace then
                    record.state = "draining"
                    record.drainReason = record.groupId ~= nil and "squad_gone" or "orphan"
                    SceneKit.placed[key] = record
                    persist(key, record)
                    SceneKit.metrics.condemned = (tonumber(SceneKit.metrics.condemned) or 0) + 1
                    draining = draining + 1
                else
                    live = live + 1
                end
            end
        end
    end
    SceneKit.metrics.live, SceneKit.metrics.draining = live, draining
end

function SceneKit.playerPositions()
    if type(SceneKit.adapters.players) == "function" then return SceneKit.adapters.players() or {} end
    local positions = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil or type(locator.list) ~= "function" then return end
        for _, player in ipairs(locator.list() or {}) do
            local at = locator.position(player)
            if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
                positions[#positions + 1] = { x = tonumber(at.x), y = tonumber(at.y) }
            end
        end
    end)
    return positions
end

function SceneKit.drainReady(record)
    local origin = record.origin
    if squareAt(origin.x, origin.y, origin.z) == nil then return false end
    for _, list in ipairs({ record.squares, record.vehicles }) do
        for _, row in ipairs(type(list) == "table" and list or {}) do
            if squareAt(row.x, row.y, row.z) == nil then return false end
        end
    end
    local clear = tonumber(SceneKit.settings.drainClearRadius) or 0
    if clear <= 0 then return true end
    local limit = clear * clear
    for _, at in ipairs(SceneKit.playerPositions()) do
        local dx, dy = at.x - (tonumber(origin.x) or 0), at.y - (tonumber(origin.y) or 0)
        if dx * dx + dy * dy <= limit then return false end
    end
    return true
end

function SceneKit.drainCost(record)
    local cost = 0
    for _, list in ipairs({ record.squares, record.vehicles }) do
        cost = cost + (type(list) == "table" and #list or 0)
    end
    return math.max(1, cost)
end

function SceneKit.drain()
    local budget = math.max(1, math.floor(tonumber(SceneKit.settings.drainBudget) or 12))
    local records, keys, spent, removed = sceneStore().records, {}, 0, 0
    for key, record in pairs(records) do
        if type(record) == "table" and record.state == "draining" and type(record.origin) == "table" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local record = records[key]
        local cost = SceneKit.drainCost(record)
        if spent > 0 and spent + cost > budget then break end
        if SceneKit.drainReady(record) then
            spent = spent + cost
            removed = removed + SceneKit.removeScene(key, record)
            SceneKit.metrics.drained = (tonumber(SceneKit.metrics.drained) or 0) + 1
        end
    end
    return removed
end

function SceneKit.tick(now)
    if not authoritative() then return 0 end
    now = tonumber(now) or 0
    if now >= (tonumber(SceneKit.scanAtMs) or 0) then
        SceneKit.scanAtMs = now + (tonumber(SceneKit.settings.scanMs) or 5000)
        SceneKit.condemnOrphans(now)
    end
    local lights = ProjectALife.OutpostLights
    if lights ~= nil and type(lights.tickScenes) == "function" then
        pcall(lights.tickScenes, sceneStore().records, now)
    end
    return SceneKit.drain()
end

function SceneKit.recover()
    local recovered = 0
    for key, record in pairs(sceneStore().records) do
        if type(record) == "table" and type(record.origin) == "table"
                and type(record.kind) == "string" then
            SceneKit.placed[tostring(key)] = record
            recovered = recovered + 1
        end
    end
    return recovered
end

function SceneKit.sceneNear(kind, x, y, limit)
    local reach = tonumber(limit) or 4
    local bestKey, bestDistance = nil, math.huge
    for key, record in pairs(sceneStore().records) do
        if SceneKit.within(record, kind, x, y, reach * reach) then
            local dx = (tonumber(record.origin.x) or 0) - (tonumber(x) or 0)
            local dy = (tonumber(record.origin.y) or 0) - (tonumber(y) or 0)
            local distance = dx * dx + dy * dy
            if distance < bestDistance or (distance == bestDistance and tostring(key) < tostring(bestKey)) then
                bestKey, bestDistance = key, distance
            end
        end
    end
    return bestKey
end

function SceneKit.vehicleAt(key, point)
    key = tostring(key or "")
    local record = SceneKit.placed[key] or sceneStore().records[key]
    if type(record) == "table" and type(record.vehicles) == "table" then
        for _, row in ipairs(record.vehicles) do
            local vehicle = SceneKit.vehicleOn(row, key)
            if vehicle ~= nil then return vehicle end
        end
    end
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then return nil end
    return SceneKit.vehicleOn({ x = point.x, y = point.y, z = tonumber(point.z) or 0 }, key)
end

SceneKit.metrics.repaired = 0
SceneKit.metrics.released = 0

function SceneKit.repairCar(key, options)
    if not authoritative() then return false, "scene_not_authoritative" end
    key = tostring(key or "")
    local record = SceneKit.placed[key] or sceneStore().records[key]
    if type(record) ~= "table" or record.kind ~= "brokenCar" or type(record.origin) ~= "table" then
        return false, "scene_not_found"
    end
    local row = type(record.vehicles) == "table" and record.vehicles[1] or nil
    local at = row or record.origin
    local depot = { vehicleSceneKey = key, x = tonumber(at.x) or 0, y = tonumber(at.y) or 0, z = tonumber(at.z) or 0 }
    if record.state == "released" then return true, "already_released", depot end
    options = type(options) == "table" and options or {}
    if options.drivable == true then
        local vehicle = SceneKit.vehicleAt(key, row)
        local fixer = ProjectALife.Wreck
        if vehicle ~= nil and fixer ~= nil and type(fixer.repair) == "function"
                and fixer.repair(vehicle, key, options.fuelPercent) then
            SceneKit.metrics.repaired = (tonumber(SceneKit.metrics.repaired) or 0) + 1
        end
    end
    record.state = "released"
    SceneKit.placed[key] = record
    persist(key, record)
    SceneKit.metrics.released = (tonumber(SceneKit.metrics.released) or 0) + 1
    return true, "released", depot
end

SceneKit.builders = {
    blockade = SceneKit.blockade,
    camp = SceneKit.camp,
    carCrash = SceneKit.carCrash,
    brokenCar = SceneKit.brokenCar,
}

function SceneKit.build(name, point, heading, key, options)
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("scene") then return false, "cleanup_locked" end
    local builder = SceneKit.builders[tostring(name or "")]
    if builder == nil then
        SceneKit.metrics.refused = SceneKit.metrics.refused + 1
        return false, "scene_unknown"
    end
    return builder(point, heading, key, options)
end

function SceneKit.reset()
    SceneKit.placed = {}
    SceneKit.emptySince = {}
    SceneKit.scanAtMs = 0
end

return SceneKit
