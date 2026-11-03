ProjectALife = ProjectALife or {}

local Sight = { metrics = { rays = 0, failed = 0 } }
ProjectALife.Sight = Sight

function Sight.classify(result)
    if result == nil then return nil end
    local blocked, door
    pcall(function()
        local outcomes = LosUtil ~= nil and LosUtil.TestResults or nil
        if outcomes ~= nil then blocked, door = outcomes.Blocked, outcomes.ClearThroughClosedDoor end
    end)
    if blocked ~= nil and type(result) ~= "string" then
        if result == blocked then return "blocked" end
        if door ~= nil and result == door then return "door" end
        return "clear"
    end
    local name = tostring(result)
    if name == "Blocked" then return "blocked" end
    if name == "ClearThroughClosedDoor" then return "door" end
    return "clear"
end

function Sight.between(fromX, fromY, fromZ, toX, toY, toZ)
    if LosUtil == nil or type(getCell) ~= "function" then return nil end
    local ok, result = pcall(function()
        return LosUtil.lineClear(getCell(),
            math.floor(tonumber(fromX) or 0), math.floor(tonumber(fromY) or 0), math.floor(tonumber(fromZ) or 0),
            math.floor(tonumber(toX) or 0), math.floor(tonumber(toY) or 0), math.floor(tonumber(toZ) or 0), false)
    end)
    if not ok then
        Sight.metrics.failed = Sight.metrics.failed + 1
        return nil
    end
    Sight.metrics.rays = Sight.metrics.rays + 1
    return Sight.classify(result)
end

function Sight.hides(answer)
    return answer == "blocked" or answer == "door"
end

return Sight
