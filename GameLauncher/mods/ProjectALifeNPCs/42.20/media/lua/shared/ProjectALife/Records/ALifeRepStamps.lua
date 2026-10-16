ProjectALife = ProjectALife or {}

local Stamps = {}
ProjectALife.RepStamps = Stamps

function Stamps.nowHours()
    if type(getGameTime) == "function" then
        local time = getGameTime()
        if time ~= nil and type(time.getWorldAgeHours) == "function" then
            return tonumber(time:getWorldAgeHours()) or 0
        end
    end
    return 0
end

function Stamps.stamp(map, key, hours, firstOnly, maxKeys)
    if type(key) ~= "string" or tonumber(hours) == nil then return map, false end
    local current = type(map) == "table" and map or {}
    if firstOnly == true and tonumber(current[key]) ~= nil then return map, false end
    local kept = {}
    for name, value in pairs(current) do
        if type(name) == "string" and name ~= key and tonumber(value) ~= nil then
            kept[#kept + 1] = { name = name, at = tonumber(value) }
        end
    end
    table.sort(kept, function(left, right) return left.at > right.at end)
    local limit = math.max(1, math.floor(tonumber(maxKeys) or 4))
    local result = { [key] = tonumber(hours) }
    for index = 1, math.min(#kept, limit - 1) do result[kept[index].name] = kept[index].at end
    return result, true
end

return Stamps
