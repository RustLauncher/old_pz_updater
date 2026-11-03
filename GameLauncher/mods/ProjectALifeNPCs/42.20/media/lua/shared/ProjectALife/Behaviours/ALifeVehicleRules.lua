ProjectALife = ProjectALife or {}

local Vehicles = {

    harmlessKmh = 10,
    lethalKmh = 50,

    impactCooldownMs = 1500,

    reachTiles = 2.2,
    beatMs = 120,
    metrics = { impacts = 0, kills = 0, meleeBlocked = 0 },
}
ProjectALife.VehicleRules = Vehicles

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Vehicles.riding(character)
    local vehicle
    pcall(function()
        if character == nil or type(character.getVehicle) ~= "function" then return end
        vehicle = character:getVehicle()
    end)
    return vehicle
end

function Vehicles.openingAt(vehicle, seat)
    local open = false
    pcall(function()
        if vehicle == nil or type(vehicle.getPassengerDoor) ~= "function" then return end
        local door = vehicle:getPassengerDoor(seat)
        if door == nil then return end
        local hatch
        if type(door.getDoor) == "function" then hatch = door:getDoor() end
        if hatch ~= nil and type(hatch.isOpen) == "function" and hatch:isOpen() == true then
            open = true
            return
        end
        if type(door.getChildWindow) ~= "function" then return end
        local windowPart = door:getChildWindow()
        if windowPart == nil or type(windowPart.getWindow) ~= "function" then return end
        local window = windowPart:getWindow()
        if window == nil then return end

        if (type(window.isDestroyed) == "function" and window:isDestroyed() == true)
                or (type(window.isOpen) == "function" and window:isOpen() == true) then open = true end
    end)
    return open
end

function Vehicles.meleeBlocked(target)
    local vehicle = Vehicles.riding(target)
    if vehicle == nil then return false end
    local seat = -1
    pcall(function()
        if type(vehicle.getSeat) == "function" then seat = vehicle:getSeat(target) end
    end)

    if type(seat) ~= "number" or seat < 0 then
        Vehicles.metrics.meleeBlocked = Vehicles.metrics.meleeBlocked + 1
        return true
    end
    if Vehicles.openingAt(vehicle, seat) then return false end
    Vehicles.metrics.meleeBlocked = Vehicles.metrics.meleeBlocked + 1
    return true
end

Vehicles.glassSpan = 0.6    
Vehicles.middleSpan = 0.2   

function Vehicles.hullCrossings(ax, az, bx, bz, cx, cz, hx, hz)
    local crossings = {}
    if not (hx > 0 and hz > 0) then return crossings end
    local dx, dz = bx - ax, bz - az
    local enter, leave, enterFace, leaveFace = -1e9, 1e9, nil, nil
    if math.abs(dx) < 1e-6 then
        if math.abs(ax - cx) > hx then return crossings end
    else
        local near, far, nearFace, farFace = (cx - hx - ax) / dx, (cx + hx - ax) / dx, "right", "left"
        if near > far then near, far, nearFace, farFace = far, near, farFace, nearFace end
        if near > enter then enter, enterFace = near, nearFace end
        if far < leave then leave, leaveFace = far, farFace end
    end
    if math.abs(dz) < 1e-6 then
        if math.abs(az - cz) > hz then return crossings end
    else
        local near, far, nearFace, farFace = (cz - hz - az) / dz, (cz + hz - az) / dz, "rear", "front"
        if near > far then near, far, nearFace, farFace = far, near, farFace, nearFace end
        if near > enter then enter, enterFace = near, nearFace end
        if far < leave then leave, leaveFace = far, farFace end
    end
    if enter > leave then return crossings end
    if enter > 0 and enter < 1 then
        crossings[#crossings + 1] = { face = enterFace, along = (az + dz * enter - cz) / hz }
    end
    if leave > 0 and leave < 1 then
        crossings[#crossings + 1] = { face = leaveFace, along = (az + dz * leave - cz) / hz }
    end
    return crossings
end

function Vehicles.windowAt(face, along, carries)
    local id
    if face == "front" then
        id = "Windshield"
    elseif face == "rear" then
        id = "WindshieldRear"
    elseif (face == "left" or face == "right") and math.abs(along) <= Vehicles.glassSpan then
        local side = face == "left" and "Left" or "Right"
        if math.abs(along) < Vehicles.middleSpan and carries("WindowMiddle" .. side) then
            id = "WindowMiddle" .. side
        elseif along >= 0 then
            id = "WindowFront" .. side
        else
            id = "WindowRear" .. side
        end
    end
    if id ~= nil and carries(id) then return id end
    return nil
end

function Vehicles.passesFire(vehicle, sx, sy, sz, tx, ty, tz)
    local passes = false
    pcall(function()
        if vehicle == nil or Vector3f == nil or vehicle.isBurntOrSmashed == nil
                or vehicle.getLocalPos == nil or vehicle.getScript == nil
                or vehicle.getPartById == nil then return end
        if vehicle:isBurntOrSmashed() ~= false then return end
        local script = vehicle:getScript()
        if script == nil then return end
        local extents, centre = script:getExtents(), script:getCenterOfMassOffset()
        if extents == nil or centre == nil then return end
        Vehicles.localPoint = Vehicles.localPoint or Vector3f.new()
        local point = Vehicles.localPoint
        vehicle:getLocalPos(sx, sy, sz or 0, point)
        local ax, az = point:x(), point:z()
        vehicle:getLocalPos(tx, ty, tz or 0, point)
        local crossings = Vehicles.hullCrossings(ax, az, point:x(), point:z(),
            centre:x(), centre:z(), extents:x() / 2, extents:z() / 2)

        if #crossings == 0 then return end
        local function has(id) return vehicle:getPartById(id) ~= nil end
        for _, crossing in ipairs(crossings) do
            local id = Vehicles.windowAt(crossing.face, crossing.along, has)
            if id == nil then return end
            local window = vehicle:getPartById(id):getWindow()
            if window == nil or window:isHittable() ~= false then return end
        end
        passes = true
    end)
    return passes
end

function Vehicles.impactShare(speedKmh)
    speedKmh = math.abs(tonumber(speedKmh) or 0)
    local floor, ceiling = Vehicles.harmlessKmh, Vehicles.lethalKmh
    if speedKmh <= floor then return 0 end
    if speedKmh >= ceiling then return 1 end
    return (speedKmh - floor) / (ceiling - floor)
end

function Vehicles.contact(shell, vehicle)
    if shell == nil or vehicle == nil or type(vehicle.testCollisionWithCharacter) ~= "function"
            or Vector2 == nil or type(Vector2.new) ~= "function" then return false end
    if Vehicles.contactPoint == nil then Vehicles.contactPoint = Vector2.new() end
    local ok, point = pcall(vehicle.testCollisionWithCharacter, vehicle, shell, 0.2, Vehicles.contactPoint)
    if not ok or (type(point) ~= "table" and type(point) ~= "userdata")
            or type(point.getX) ~= "function" then return false end
    local x = tonumber(point:getX())
    return x ~= nil and x == x and math.abs(x) < math.huge and x ~= -1
end

function Vehicles.strike(shell, vehicle, speedKmh, now)
    local share = Vehicles.impactShare(speedKmh)
    if share <= 0 or not Vehicles.contact(shell, vehicle) then return false end
    local applied = false
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        if now < (tonumber(data.ProjectALifeNextVehicleHitMs) or 0) then return end
        data.ProjectALifeNextVehicleHitMs = now + Vehicles.impactCooldownMs

        local health = ProjectALife.Health
        local simulation = ProjectALife.ShellSimulation
        if health == nil or simulation == nil then return end
        if type(health.invulnerable) == "function" and health.invulnerable(shell) then return end

        local maximum = simulation.maximumFor(shell) or 0

        local current
        if type(simulation.trueHealth) == "function" then current = tonumber(simulation.trueHealth(shell)) end
        if current == nil then current = tonumber(shell:getHealth()) or 0 end
        if maximum <= 0 then return end
        local after = math.max(0, current - maximum * share)

        local driver
        if type(vehicle.getDriver) == "function" then
            driver = vehicle:getDriver()
            if driver ~= nil and (type(instanceof) ~= "function" or not instanceof(driver, "IsoPlayer")
                    or type(driver.getVehicle) ~= "function" or driver:getVehicle() ~= vehicle
                    or type(driver.getCurrentSquare) ~= "function" or driver:getCurrentSquare() == nil) then
                driver = nil
            end
        end

        if type(simulation.setHealth) == "function" then
            simulation.setHealth(shell, after)
        else
            shell:setHealth(after)
        end
        health.onEngineHit(shell, driver, "leg", now, after, nil, "vehicle")
        Vehicles.metrics.impacts = Vehicles.metrics.impacts + 1
        if after <= 0 then
            Vehicles.metrics.kills = Vehicles.metrics.kills + 1
            pcall(function() shell:Kill(driver or shell) end)
        end
        applied = true
    end)
    return applied
end

function Vehicles.allowed()
    if Vehicles.retired == true then return false end
    local settings = ProjectALife.Settings
    local world = settings ~= nil and settings.current or nil
    if type(world) == "table" and world.vehicleDamage == false then return false end
    return true
end

function Vehicles.tick()
    if not Vehicles.allowed() then return end
    local now = nowMs()
    if now < (Vehicles.nextBeatAtMs or 0) then return end
    Vehicles.nextBeatAtMs = now + Vehicles.beatMs

    local guard = ProjectALife.AIFence
    if guard == nil or type(guard.owned) ~= "table" then return end

    local any = false
    for _ in pairs(guard.owned) do any = true break end
    if not any then return end

    local moving = {}
    local listOk = pcall(function()
        local cell = type(getCell) == "function" and getCell() or nil
        if cell == nil or cell.getVehicles == nil then return end
        local list = cell:getVehicles()
        if list == nil then return end

        local function consider(vehicle)
            if vehicle == nil then return end
            local speed = math.abs(tonumber(vehicle:getCurrentSpeedKmHour()) or 0)
            if speed > Vehicles.harmlessKmh then
                moving[#moving + 1] = { vehicle = vehicle, speed = speed }
            end
        end
        local walked = false
        if list.size ~= nil and list.get ~= nil then
            local count = 0
            if pcall(function() count = tonumber(list:size()) or 0 end) then
                walked = true
                for index = 0, count - 1 do
                    pcall(function() consider(list:get(index)) end)
                end
            end
        end
        if not walked and list.iterator ~= nil then
            local iterator
            if pcall(function() iterator = list:iterator() end)
                    and iterator ~= nil and iterator.hasNext ~= nil then
                walked = true

                for _ = 1, 512 do
                    local more = false
                    if not pcall(function() more = iterator:hasNext() == true end) then break end
                    if not more then break end
                    if not pcall(function() consider(iterator:next()) end) then break end
                end
            end
        end
        if not walked then
            Vehicles.retired = true
            Vehicles.metrics.retired = 1
        end
    end)
    if not listOk then
        Vehicles.listFailures = (Vehicles.listFailures or 0) + 1

        if Vehicles.listFailures >= 3 then
            Vehicles.retired = true
            Vehicles.metrics.retired = 1
        end
        return
    end
    Vehicles.listFailures = 0
    if #moving == 0 then return end

    local reach = Vehicles.reachTiles * Vehicles.reachTiles
    for shell in pairs(guard.owned) do
        pcall(function()
            if shell:isDead() then return end

            if type(guard.authorityFor) == "function" and not guard.authorityFor(shell) then return end
            local sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
            for _, entry in ipairs(moving) do
                local vehicle = entry.vehicle
                local vx, vy, vz = vehicle:getX(), vehicle:getY(), vehicle:getZ()
                if math.floor(vz) == math.floor(sz) then
                    local dx, dy = vx - sx, vy - sy
                    if dx * dx + dy * dy <= reach then
                        if Vehicles.strike(shell, vehicle, entry.speed, now) then return end
                    end
                end
            end
        end)
    end
end

function Vehicles.register()
    if Vehicles.registered or type(Events) ~= "table" then return false end
    if Events.OnTick == nil or type(Events.OnTick.Add) ~= "function" then return false end
    Vehicles.registered = true
    Events.OnTick.Add(function()
        local ok, err = pcall(Vehicles.tick)
        if not ok then Vehicles.lastError = tostring(err) end
    end)
    return true
end

Vehicles.register()

return Vehicles
