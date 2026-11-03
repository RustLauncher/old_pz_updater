ProjectALife = ProjectALife or {}

local Posts = { metrics = { scans = 0, posts = 0, fallbacks = 0 } }
ProjectALife.UpperPosts = Posts

local floorOf = math.floor
local STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function cellOf()
    local cell
    pcall(function() cell = getCell() end)
    return cell
end

local function squareAt(cell, x, y, z)
    local square
    pcall(function() square = cell:getGridSquare(x, y, z) end)
    return square
end

local function standable(square)
    if square == nil then return false end
    local ok, good = pcall(function()
        return square:getFloor() ~= nil
            and square:isFree(false) == true
            and square:TreatAsSolidFloor() == true
    end)
    return ok and good == true
end

local function looksOut(cell, square, x, y, z)
    local seen = false
    if type(square.getWindow) == "function" then
        local ok, window = pcall(square.getWindow, square)
        if ok and window ~= nil then return true end
    end
    for index = 1, 4 do
        local step = STEPS[index]
        local neighbour = squareAt(cell, x + step[1], y + step[2], z)
        if neighbour ~= nil then
            pcall(function()
                if (type(square.getWindowTo) == "function" and square:getWindowTo(neighbour) ~= nil)
                        or (type(square.getWindowFrameTo) == "function" and square:getWindowFrameTo(neighbour) ~= nil) then
                    seen = true
                end
            end)
            if seen then return true end
        end
    end
    return false
end
Posts.looksOut = looksOut

function Posts.buildingAt(x, y, z)
    local building, definition, top
    pcall(function()
        local cell = cellOf()
        if cell == nil then return end
        local square = cell:getGridSquare(floorOf(x), floorOf(y), floorOf(z))
        if square == nil then return end
        building = square:getBuilding()
        if building == nil then return end
        definition = building:getDef()
    end)
    if definition == nil then
        pcall(function()
            local grid = getWorld():getMetaGrid()
            definition = grid:getBuildingAt(floorOf(x), floorOf(y), floorOf(z))
            if definition == nil then
                definition = grid:getBuildingAt(floorOf(x), floorOf(y), 0)
            end
        end)
    end
    if definition == nil then return nil end
    pcall(function() top = definition:getMaxLevel() end)
    return definition, building, floorOf(tonumber(top) or 0)
end

function Posts.findFloorPosts(x, y, z, count, minLevel)
    local wanted = math.max(1, floorOf(tonumber(count) or 3))
    local lowest = math.max(0, floorOf(tonumber(minLevel) or 0))
    local definition, building, top = Posts.buildingAt(x, y, z)
    if definition == nil or top < lowest then return {} end
    local cell = cellOf()
    if cell == nil then return {} end

    local x1, y1, x2, y2 = 0, 0, 0, 0
    local read = pcall(function()
        x1, y1 = definition:getX(), definition:getY()
        x2, y2 = definition:getX2(), definition:getY2()
    end)
    if not read then return {} end

    Posts.metrics.scans = Posts.metrics.scans + 1
    local windowed, plain = {}, {}
    local level = top

    while level >= lowest do
        for gx = x1, x2 do
            for gy = y1, y2 do
                if #windowed < wanted * 3 then
                    local square = squareAt(cell, gx, gy, level)
                    if standable(square) then
                        local mine = false
                        pcall(function()
                            local owner = square:getBuilding()
                            mine = (building ~= nil and owner == building)
                                or (building == nil and owner ~= nil)
                        end)
                        if mine then
                            local point = { x = gx + 0.5, y = gy + 0.5, z = level }
                            if looksOut(cell, square, gx, gy, level) then
                                windowed[#windowed + 1] = point
                            elseif #plain < wanted * 2 then
                                plain[#plain + 1] = point
                            end
                        end
                    end
                end
            end
        end

        if #windowed >= wanted then level = lowest - 1 else level = level - 1 end
    end

    for index = 1, #plain do
        if #windowed >= wanted then break end
        Posts.metrics.fallbacks = Posts.metrics.fallbacks + 1
        windowed[#windowed + 1] = plain[index]
    end
    table.sort(windowed, function(left, right)
        if left.z ~= right.z then return left.z > right.z end
        local ld = (left.x - x) * (left.x - x) + (left.y - y) * (left.y - y)
        local rd = (right.x - x) * (right.x - x) + (right.y - y) * (right.y - y)
        return ld < rd
    end)

    local result = {}
    for index = 1, math.min(wanted, #windowed) do
        result[#result + 1] = windowed[index]
        Posts.metrics.posts = Posts.metrics.posts + 1
    end
    return result
end

function Posts.findUpperFloorPosts(x, y, z, count)
    return Posts.findFloorPosts(x, y, z, count, 1)
end

function Posts.pursuitPoint(shell, target)
    if shell == nil or target == nil or type(shell.getX) ~= "function" or type(shell.getY) ~= "function"
            or type(shell.getZ) ~= "function" or type(target.getX) ~= "function"
            or type(target.getY) ~= "function" or type(target.getZ) ~= "function" then return nil, "upper_invalid" end
    local sx, sy, sz = shell:getX(), shell:getY(), floorOf(shell:getZ())
    local tx, ty, tz = target:getX(), target:getY(), floorOf(target:getZ())
    if tz <= sz then return nil, "upper_floor_reached" end
    local definition, building = Posts.buildingAt(tx, ty, tz)
    local cell = cellOf()
    if definition == nil or cell == nil then return nil, "upper_building_unloaded" end
    local x1, y1, x2, y2
    local read = pcall(function()
        x1, y1 = math.max(definition:getX(), floorOf(sx) - 12), math.max(definition:getY(), floorOf(sy) - 12)
        x2, y2 = math.min(definition:getX2(), floorOf(sx) + 12), math.min(definition:getY2(), floorOf(sy) + 12)
    end)
    if not read then return nil, "upper_building_unloaded" end
    local stair, cost
    for x = x1, x2 do
        for y = y1, y2 do
            local square = squareAt(cell, x, y, sz)
            local allowed = false
            if square ~= nil and type(square.HasStairs) == "function" and type(square.getFloor) == "function"
                    and type(square.isFree) == "function" and type(square.TreatAsSolidFloor) == "function"
                    and type(square.getBuilding) == "function" then
                allowed = square:HasStairs() == true and standable(square)
                    and (building == nil or square:getBuilding() == building)
            end
            if allowed then
                local distance = (x + 0.5 - sx) ^ 2 + (y + 0.5 - sy) ^ 2
                if cost == nil or distance < cost then
                    stair, cost = { x = x + 0.5, y = y + 0.5, z = sz }, distance
                end
            end
        end
    end
    if stair == nil then return nil, "upper_no_loaded_stairs" end
    if cost > 2.25 then return stair, "upper_stair_approach" end
    local point, nearest
    for x = floorOf(tx) - 2, floorOf(tx) + 2 do
        for y = floorOf(ty) - 2, floorOf(ty) + 2 do
            local square = squareAt(cell, x, y, tz)
            if square ~= nil and type(square.getFloor) == "function" and type(square.isFree) == "function"
                    and type(square.TreatAsSolidFloor) == "function" and standable(square) then
                local distance = (x + 0.5 - tx) ^ 2 + (y + 0.5 - ty) ^ 2
                if nearest == nil or distance < nearest then
                    point, nearest = { x = x + 0.5, y = y + 0.5, z = tz }, distance
                end
            end
        end
    end
    if point == nil then return nil, "upper_goal_unloaded" end
    return point, "upper_stair_ascend"
end

return Posts
