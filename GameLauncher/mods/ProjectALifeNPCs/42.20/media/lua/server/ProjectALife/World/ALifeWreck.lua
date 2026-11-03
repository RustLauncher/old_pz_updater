ProjectALife = ProjectALife or {}

local Wreck = {}
ProjectALife.Wreck = Wreck

local floor_ = math.floor

function Wreck.disable(vehicle, options)
    if vehicle == nil then return false end
    options = type(options) == "table" and options or {}
    local applied = false
    pcall(function()

        pcall(function()
            vehicle:setGeneralPartCondition(tonumber(options.spread) or 1.3,
                tonumber(options.variance) or 10)
        end)

        pcall(function()
            for index = 0, vehicle:getPartCount() - 1 do
                local part = vehicle:getPartByIndex(index)
                local wear = type(ZombRand) == "function" and ZombRand(15, 56)
                    or 15 + (index * 17) % 41
                part:setCondition(math.min(part:getCondition(), wear))
                pcall(function() vehicle:transmitPartCondition(part) end)
            end
        end)
        if options.hoodCondition ~= nil then
            local hood = vehicle:getPartById("EngineDoor")
            if hood ~= nil then
                hood:setCondition(math.max(0, math.min(100, floor_(options.hoodCondition))))
                pcall(function() vehicle:transmitPartCondition(hood) end)
            end
        end
        local tank = vehicle:getPartById("GasTank")
        if tank ~= nil then
            tank:setContainerContentAmount(0)
            pcall(function() vehicle:transmitPartModData(tank) end)
        end
        local engine = vehicle:getPartById("Engine")
        if engine ~= nil then
            engine:setCondition(floor_(tonumber(options.engineCondition) or 0))
            pcall(function() vehicle:transmitPartCondition(engine) end)
        end
        local battery = vehicle:getPartById("Battery")
        if battery ~= nil then
            battery:setCondition(floor_(tonumber(options.batteryCondition) or 0))
            pcall(function() vehicle:transmitPartCondition(battery) end)
        end

        if options.rust ~= nil then vehicle:setRust(tonumber(options.rust)) end
        if options.blood ~= nil then
            vehicle:setBloodIntensity("Front", tonumber(options.blood))
        end
        applied = true
    end)

    pcall(function()
        if vehicle:getPartById("Engine") == nil then return end
        vehicle:setEngineFeature(floor_(tonumber(options.quality) or 0),
                                 vehicle:getEngineLoudness(),
                                 vehicle:getEnginePower())
    end)
    return applied
end

function Wreck.state(vehicle)
    if vehicle == nil then return nil end
    local out
    pcall(function()
        local engine = vehicle:getPartById("Engine")
        local tank = vehicle:getPartById("GasTank")
        out = {
            engineCondition = vehicle:getEngineCondition(),
            engineQuality   = vehicle:getEngineQuality(),
            fuelPercent     = vehicle:getRemainingFuelPercentage(),
            fuelUnits       = tank and tank:getContainerContentAmount() or 0,
            fuelCapacity    = tank and tank:getContainerCapacity() or 0,
            enginePart      = engine and engine:getCondition() or 0,
        }
    end)
    return out
end

Wreck.repairSettings = { condition = { 45, 70 }, bonnet = 60, charge = 0.6 }

function Wreck.keyRoll(key, salt)
    local seed = 0
    local text = tostring(key or "") .. ":" .. tostring(salt or "")
    for i = 1, #text do seed = (seed * 31 + string.byte(text, i)) % 2147483647 end
    return (seed % 1000) / 1000
end

function Wreck.partCondition(vehicle, id, value)
    local part = vehicle:getPartById(id)
    if part == nil or type(part.setCondition) ~= "function" then return false end
    part:setCondition(math.max(0, math.min(100, floor_(value))))
    if type(vehicle.transmitPartCondition) == "function" then pcall(vehicle.transmitPartCondition, vehicle, part) end
    return true
end

function Wreck.chargeBattery(vehicle, level)
    local part = vehicle:getPartById("Battery")
    if part == nil or type(part.getInventoryItem) ~= "function" then return false end
    local item = part:getInventoryItem()
    if item == nil or type(item.setUsedDelta) ~= "function" then return false end
    local charge = 0
    if type(item.getCurrentUsesFloat) == "function" then charge = tonumber(item:getCurrentUsesFloat()) or 0 end
    if charge >= level then return true end
    item:setUsedDelta(level)
    if type(vehicle.transmitPartUsedDelta) == "function" then pcall(vehicle.transmitPartUsedDelta, vehicle, part) end
    return true
end

function Wreck.fillTank(vehicle, percent)
    local tank = vehicle:getPartById("GasTank")
    if tank == nil or type(tank.getContainerCapacity) ~= "function"
            or type(tank.setContainerContentAmount) ~= "function" then return false end
    local capacity = tonumber(tank:getContainerCapacity()) or 0
    tank:setContainerContentAmount(capacity * math.max(0, math.min(100, tonumber(percent) or 0)) / 100)
    if type(vehicle.transmitPartModData) == "function" then pcall(vehicle.transmitPartModData, vehicle, tank) end
    return true
end

function Wreck.shutBonnet(vehicle)
    local part = vehicle:getPartById("EngineDoor")
    if part == nil or type(part.getDoor) ~= "function" then return false end
    local door = part:getDoor()
    if door == nil or type(door.setOpen) ~= "function" then return false end
    door:setOpen(false)
    if type(vehicle.transmitPartDoor) == "function" then pcall(vehicle.transmitPartDoor, vehicle, part) end
    return true
end

function Wreck.repair(vehicle, key, fuelPercent)
    if vehicle == nil or type(vehicle.getPartById) ~= "function" then return false end
    local s = Wreck.repairSettings
    local span = s.condition[2] - s.condition[1] + 1
    local engine = s.condition[1] + floor_(Wreck.keyRoll(key, "engine") * span)
    Wreck.partCondition(vehicle, "Engine", engine)
    Wreck.partCondition(vehicle, "Battery", s.condition[1] + floor_(Wreck.keyRoll(key, "battery") * span))
    Wreck.partCondition(vehicle, "EngineDoor", s.bonnet)
    Wreck.chargeBattery(vehicle, s.charge)
    Wreck.fillTank(vehicle, fuelPercent)
    Wreck.shutBonnet(vehicle)
    if type(vehicle.setEngineFeature) == "function" and type(vehicle.getEngineLoudness) == "function"
            and type(vehicle.getEnginePower) == "function" then
        vehicle:setEngineFeature(engine, vehicle:getEngineLoudness(), vehicle:getEnginePower())
    end
    return true
end

function Wreck.disableNearest(x, y, z, radius)
    local chosen, chosenFlat
    local reach = tonumber(radius) or 12
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local vehicles = cell:getVehicles()
        if vehicles == nil or vehicles.toArray == nil then return end
        for _, vehicle in pairs(vehicles:toArray()) do
            local dx = vehicle:getX() - (tonumber(x) or 0)
            local dy = vehicle:getY() - (tonumber(y) or 0)
            local flat = dx * dx + dy * dy
            local occupied = false
            pcall(function()
                occupied = vehicle:isEngineRunning() == true
                    or vehicle:getDriver() ~= nil
            end)

            if not occupied and flat <= reach * reach
                    and (chosenFlat == nil or flat < chosenFlat) then
                chosen, chosenFlat = vehicle, flat
            end
        end
    end)
    if chosen == nil then return false end
    return Wreck.disable(chosen, { hoodCondition = 0 })
end
