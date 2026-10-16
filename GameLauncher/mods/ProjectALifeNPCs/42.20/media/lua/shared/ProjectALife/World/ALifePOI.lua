ProjectALife = ProjectALife or {}

local POI = { metrics = { scans = 0, hits = 0 } }
ProjectALife.POI = POI

local lower = string.lower
local floorOf = math.floor

POI.rooms = {
    police = { "policestorage", "policeoffice", "policelocker", "policearchive",
        "policegarage", "policegunstorage", "policeoutfitstorage", "policehall",
        "policelibrary", "policeswat", "evidenceroom", "interrogationroom",
        "detectiveoffice", "captainoffice", "firearmtraining",
        "prisoncells", "prisonstorage", "prisonarmory", "prisonlocker" },
    fire = { "firestorage", "firegarage", "firedisplay" },
    medical = { "medical", "medicaloffice", "medicalstorage", "hospitalroom",
        "hospitalhallway", "hospitalstorage", "pharmacy", "pharmacystorage",
        "morgue", "coroneroffice", "dentist", "dentiststorage", "oldmedical",
        "laboratory" },
    warehouse = { "warehouse", "storage", "storageunit", "factory",
        "factorystorage", "loggingwarehouse", "loggingfactory", "farmstorage",
        "garagestorage", "departmentstorage", "grocerystorage" },
    guns = { "gunstore", "gunstorestorage", "gunstorage", "armysurplus",
        "armysurplusguns", "armystorage", "armytent", "oldarmy", "hunting" },
}

POI.substrings = {
    police = { "police", "prison" },
    fire = { "fire" },
    medical = { "hospital", "medical", "pharmac" },
    warehouse = { "warehouse", "storageunit" },
    guns = { "gunstore", "armysurplus" },
}

local lookup   

local function index()
    if lookup ~= nil then return lookup end
    lookup = {}
    for category, names in pairs(POI.rooms) do
        for position = 1, #names do lookup[names[position]] = category end
    end
    return lookup
end

function POI.categoryOf(roomName)
    if type(roomName) ~= "string" or roomName == "" then return nil end
    local name = lower(roomName)
    local exact = index()[name]
    if exact ~= nil then return exact end
    for category, parts in pairs(POI.substrings) do
        for position = 1, #parts do
            if string.find(name, parts[position], 1, true) ~= nil then
                return category
            end
        end
    end
    return nil
end

function POI.roomNameAt(x, y, z)
    local name
    pcall(function()
        local square = getCell():getGridSquare(floorOf(x), floorOf(y), floorOf(z))
        if square == nil then return end
        local room = square:getRoom()
        if room ~= nil then name = room:getName() end
        if name == nil then
            local definition = square:getRoomDef()
            if definition ~= nil then name = definition:getName() end
        end
    end)
    if name == nil then
        pcall(function()
            local definition = getWorld():getMetaGrid():getRoomAt(
                floorOf(x), floorOf(y), floorOf(z))
            if definition ~= nil then name = definition:getName() end
        end)
    end
    return name
end

function POI.categoryAt(x, y, z)
    return POI.categoryOf(POI.roomNameAt(x, y, z))
end

function POI.search(x, y, radius, wanted)
    local results = {}
    local reach = math.max(8, floorOf(tonumber(radius) or 120))
    local filter
    if type(wanted) == "table" then
        filter = {}
        for position = 1, #wanted do filter[lower(tostring(wanted[position]))] = true end
    end
    POI.metrics.scans = POI.metrics.scans + 1
    pcall(function()
        local rooms = ArrayList.new()
        getWorld():getMetaGrid():getRoomsIntersecting(
            floorOf(x) - reach, floorOf(y) - reach, reach * 2, reach * 2, rooms)
        local count = math.min(rooms:size(), 400)
        for index2 = 0, count - 1 do
            local definition = rooms:get(index2)
            if definition ~= nil then
                local name = lower(tostring(definition:getName() or ""))
                local category = POI.categoryOf(name)

                local keep = filter == nil
                    or (category ~= nil and filter[category] == true)
                    or filter[name] == true
                if keep and (category ~= nil or filter ~= nil) then
                    local rx, ry, rz = 0, 0, 0
                    local read = pcall(function()
                        rx, ry, rz = definition:getX(), definition:getY(), definition:getZ()
                    end)
                    if read then
                        POI.metrics.hits = POI.metrics.hits + 1
                        results[#results + 1] = {
                            name = name,
                            category = category,
                            x = rx + floorOf((definition:getW() or 2) / 2),
                            y = ry + floorOf((definition:getH() or 2) / 2),
                            z = rz,
                            building = definition:getBuilding(),
                        }
                    end
                end
            end
        end
    end)
    table.sort(results, function(left, right)
        local ld = (left.x - x) * (left.x - x) + (left.y - y) * (left.y - y)
        local rd = (right.x - x) * (right.x - x) + (right.y - y) * (right.y - y)
        return ld < rd
    end)
    return results
end

return POI
