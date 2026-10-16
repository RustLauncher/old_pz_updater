ProjectALife = ProjectALife or {}

local Road = {}
ProjectALife.Road = Road

local floor_, sqrt_, abs_, max_ = math.floor, math.sqrt, math.abs, math.max
local lower_, sub_ = string.lower, string.sub

Road.gravelTiles = {
    ["blends_street_01_48"] = true, ["blends_street_01_53"] = true,
    ["blends_street_01_54"] = true, ["blends_street_01_55"] = true,
}

local function startsWith(text, prefix)
    return sub_(text, 1, #prefix) == prefix
end

function Road.surfaceOf(square)
    if square == nil then return nil, nil end
    local ok, name, material = pcall(function()
        local floorObject = square:getFloor()
        if floorObject == nil then return nil, nil end
        local props = floorObject:getProperties()
        local value = nil
        if props ~= nil then value = props:get("FloorMaterial") end
        return floorObject:getSpriteName(), value
    end)
    if not ok then return nil, nil end
    return name, material
end

function Road.isPavedSurface(square)
    local name, material = Road.surfaceOf(square)
    if type(material) == "string" and startsWith(material, "Road_") then return true end
    if type(name) ~= "string" then return false end
    return startsWith(name, "blends_street")
        or startsWith(name, "floors_exterior_street")
end

local function zoneFlags(square)
    local nav, stall = false, false
    pcall(function()
        local zone = square:getZone()
        if zone ~= nil then
            local kind = lower_(tostring(zone:getType() or ""))
            if kind == "nav" then nav = true end
            if kind == "parkingstall" then stall = true end
        end
    end)
    pcall(function()
        local x, y, z = square:getX(), square:getY(), square:getZ()
        if getVehicleZoneAt ~= nil and getVehicleZoneAt(x, y, z) ~= nil then stall = true end
        local zones = getWorld():getMetaGrid():getZonesAt(x, y, z)
        if zones == nil then return end
        for index = 0, zones:size() - 1 do
            local candidate = zones:get(index)
            if candidate ~= nil then
                local kind = lower_(tostring(candidate:getType() or ""))
                if kind == "nav" then nav = true end
                if kind == "parkingstall" then stall = true end
            end
        end
    end)
    return nav, stall
end

function Road.isRoadSquare(square)
    if square == nil then return false end
    if not Road.isPavedSurface(square) then return false end
    local nav, stall = zoneFlags(square)
    if stall and not nav then return false end
    return nav
end

function Road.pavedRun(cell, x, y, z, dx, dy, limit)
    local count = 1
    for sign = -1, 1, 2 do
        for step = 1, limit - 1 do
            if count >= limit then return count end
            local beside = cell:getGridSquare(x + dx * step * sign, y + dy * step * sign, z)
            if beside == nil or not Road.isPavedSurface(beside) then break end
            count = count + 1
        end
    end
    return count
end

function Road.isStreetSquare(square, cell, run)
    if square == nil or cell == nil or not Road.isPavedSurface(square) then return false end
    if type(square.isOutside) == "function" and square:isOutside() ~= true then return false end
    local _, stall = zoneFlags(square)
    if stall then return false end
    run = max_(2, floor_(tonumber(run) or 3))
    local x, y, z = square:getX(), square:getY(), square:getZ()
    return Road.pavedRun(cell, x, y, z, 1, 0, run) >= run and Road.pavedRun(cell, x, y, z, 0, 1, run) >= run
end

function Road.axisAt(square)
    local ax, ay
    pcall(function()
        local zones = getWorld():getMetaGrid():getZonesAt(
            square:getX(), square:getY(), square:getZ())
        if zones == nil then return end
        local bestSpan, bestW, bestH = -1, 0, 0
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            if zone ~= nil and lower_(tostring(zone:getType() or "")) == "nav" then
                local w, h = zone:getWidth(), zone:getHeight()
                local span = max_(w, h)
                if span > bestSpan then bestSpan, bestW, bestH = span, w, h end
            end
        end
        if bestSpan < 0 then return end
        if bestH >= bestW then ax, ay = 0, 1 else ax, ay = 1, 0 end
    end)
    return ax, ay
end

return Road
