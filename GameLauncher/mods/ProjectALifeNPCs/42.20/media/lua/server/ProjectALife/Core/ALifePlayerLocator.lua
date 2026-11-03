ProjectALife = ProjectALife or {}

local PlayerLocator = { anchors = {} }
ProjectALife.PlayerLocator = PlayerLocator

local function appendOnline(result)
    if type(getOnlinePlayers) ~= "function" then return end
    local ok, online = pcall(getOnlinePlayers)
    local kind = type(online)
    if not ok or (kind ~= "userdata" and kind ~= "table")
            or online.size == nil or online.get == nil then return end
    for index = 0, (tonumber(online:size()) or 0) - 1 do
        local player = online:get(index)
        if player ~= nil then result[#result + 1] = player end
    end
end

function PlayerLocator.list(adapter)
    if type(adapter) == "function" then return adapter() or {} end
    local result = {}
    appendOnline(result)

    if #result == 0 and type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok and player ~= nil then result[1] = player end
    end
    return result
end

function PlayerLocator.position(player, adapter)
    if type(adapter) == "function" then return adapter(player) end
    if player == nil then return nil end
    for _, anchor in ipairs(PlayerLocator.anchors) do
        local answered, at = pcall(anchor, player)
        if answered and type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
            return { x = tonumber(at.x), y = tonumber(at.y), z = tonumber(at.z) or 0 }
        end
    end
    local kind = type(player)
    if (kind ~= "userdata" and kind ~= "table") or player.getX == nil
            or player.getY == nil or player.getZ == nil then return nil end
    return { x = player:getX(), y = player:getY(), z = player:getZ() }
end

return PlayerLocator
