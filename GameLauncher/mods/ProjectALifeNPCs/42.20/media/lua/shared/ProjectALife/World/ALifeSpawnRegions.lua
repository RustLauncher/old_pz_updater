require "ProjectALife/World/ALifePOI"
require "ProjectALife/World/ALifeTownRegions"

ProjectALife = ProjectALife or {}

local Regions = {}
ProjectALife.SpawnRegions = Regions
local TownRegions = ProjectALife.TownRegions

Regions.definitions = TownRegions.definitions

local function pool(value)
    local result = {}
    if type(value) == "table" then
        for _, id in ipairs(value) do
            id = string.match(tostring(id or ""), "^%s*(.-)%s*$")
            if id ~= "" then result[id] = true end
        end
        return result
    end
    for id in string.gmatch(tostring(value or "") .. "|", "(.-)|") do
        id = string.match(id, "^%s*(.-)%s*$")
        if id ~= "" then result[id] = true end
    end
    return result
end

function Regions.contains(position, id)
    return TownRegions.contains(position, id)
end

function Regions.inKnownTown(position)
    local definition = TownRegions.at(position)
    return definition ~= nil, definition and definition.id or nil
end

local function outsideBuilding(square)
    if square == nil then return true end
    local ok, outside = pcall(function() return square:isOutside() end)
    if ok and outside == false then return false end
    local roomOk, room = pcall(function() return square:getRoom() end)
    if roomOk and room ~= nil then return false end
    local buildingOk, building = pcall(function() return square:getBuilding() end)
    return not buildingOk or building == nil
end

local function highwayZone(zone)
    local ok, zoneType = pcall(function() return zone:getType() end)
    zoneType = ok and string.lower(tostring(zoneType or "")) or ""
    return zoneType == "nav" or zoneType == "road" or zoneType == "highway"
end

function Regions.isHighway(position, square)
    if type(position) ~= "table" then return false end
    local supplied = string.lower(tostring(position.zoneType or ""))
    if supplied == "nav" or supplied == "road" or supplied == "highway" then
        return true
    end
    local squareOk, zone = pcall(function()
        return square and square:getZone() or nil
    end)
    if squareOk and zone ~= nil and highwayZone(zone) then return true end
    if getWorld == nil then return false end
    local ok, zones = pcall(function()
        return getWorld():getMetaGrid():getZonesAt(
            math.floor(tonumber(position.x) or 0),
            math.floor(tonumber(position.y) or 0),
            math.floor(tonumber(position.z) or 0))
    end)
    if not ok or zones == nil then return false end
    local countOk, count = pcall(function() return zones:size() end)
    if not countOk then return false end
    for index = 0, count - 1 do
        local zoneOk, candidate = pcall(function() return zones:get(index) end)
        if zoneOk and candidate ~= nil and highwayZone(candidate) then return true end
    end
    return false
end

function Regions.allows(position, spawn, square)
    spawn = type(spawn) == "table" and spawn or {}
    local mode = string.lower(tostring(spawn.locationMode or "anywhere"))
    if mode == "anywhere" then return true end
    local inTown = Regions.inKnownTown(position)
    if mode == "wilderness" then return inTown ~= true and outsideBuilding(square) end
    if mode == "highways" then return Regions.isHighway(position, square) end
    if mode == "specific" then
        local selected = pool(spawn.specificPlacePool)
        local category = ProjectALife.POI and ProjectALife.POI.categoryAt(
            tonumber(position.x) or 0, tonumber(position.y) or 0,
            tonumber(position.z) or 0)
        return category ~= nil and selected[category] == true
    end
    if mode ~= "towns" then return true end
    if spawn.allTowns == true and inTown then return true end
    local authoredTowns = spawn.towns
    if authoredTowns == nil or tostring(authoredTowns) == "" then
        authoredTowns = spawn.townPool
    end
    local selected = pool(authoredTowns)
    for id in pairs(selected) do
        if Regions.contains(position, id) then return true end
    end
    return spawn.includeWilderness == true and inTown ~= true
        and outsideBuilding(square)
end

return Regions
