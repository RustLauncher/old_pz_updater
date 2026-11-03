ProjectALife = ProjectALife or {}

local Regions = {}
ProjectALife.TownRegions = Regions

Regions.definitions = {
    { id = "brandenburg", label = "Brandenburg", minX = 1064, maxX = 3564, minY = 5003, maxY = 7503 },
    { id = "echo_creek", label = "Echo Creek", minX = 3185, maxX = 5285, minY = 10019, maxY = 12119 },
    { id = "ekron", label = "Ekron", minX = -30, maxX = 2070, minY = 8788, maxY = 10888 },
    { id = "fallas_lake", label = "Fallas Lake", minX = 6298, maxX = 8398, minY = 7321, maxY = 9421 },
    { id = "irvington", label = "Irvington", minX = 1479, maxX = 3979, minY = 12547, maxY = 15047 },

    { id = "louisville", label = "Louisville", minX = 11700, maxX = 14699, minY = 900, maxY = 3899 },
    { id = "march_ridge", label = "March Ridge", minX = 8721, maxX = 11121, minY = 11403, maxY = 13803 },
    { id = "muldraugh", label = "Muldraugh", minX = 9631, maxX = 12731, minY = 8175, maxY = 11275 },
    { id = "riverside", label = "Riverside", minX = 4950, maxX = 7650, minY = 4318, maxY = 7018 },
    { id = "rosewood", label = "Rosewood", minX = 7246, maxX = 9646, minY = 10356, maxY = 12756 },
    { id = "valley_station", label = "Valley Station", minX = 11656, maxX = 14456, minY = 4631, maxY = 7431 },
    { id = "west_point", label = "West Point", minX = 10181, maxX = 12981, minY = 5516, maxY = 8316 },
}

local byId = {}
for _, definition in ipairs(Regions.definitions) do byId[definition.id] = definition end

function Regions.get(id)
    return byId[tostring(id or "")]
end

function Regions.contains(position, id)
    local definition = Regions.get(id)
    if type(position) ~= "table" or definition == nil then return false end
    local x, y = tonumber(position.x), tonumber(position.y)
    return x ~= nil and y ~= nil
        and x >= definition.minX and x <= definition.maxX
        and y >= definition.minY and y <= definition.maxY
end

function Regions.distanceToTown(position)
    if type(position) ~= "table" then return nil, nil end
    local x, y = tonumber(position.x), tonumber(position.y)
    if x == nil or y == nil then return nil, nil end
    local best, town
    for _, d in ipairs(Regions.definitions) do
        local dx = math.max(d.minX - x, 0, x - d.maxX)
        local dy = math.max(d.minY - y, 0, y - d.maxY)
        local distance = math.sqrt(dx * dx + dy * dy)
        if best == nil or distance < best then best, town = distance, d end
    end
    return best, town
end

function Regions.at(position)
    for _, definition in ipairs(Regions.definitions) do
        if Regions.contains(position, definition.id) then return definition end
    end
    return nil
end

return Regions
