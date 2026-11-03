-- FTZ Carts & Trolleys - a few carts standing on the floor of supermarkets and warehouses.
-- Rolled once per room (sandbox FTZCarts.WorldSpawnChance / WorldSpawnMax), placed when the room's
-- squares are loaded for the first time. Runs where the world lives: the server in multiplayer, the game in solo.
if isClient() then return end

local CART = "Base.FTZ_ShoppingCart"
local TROLLEY = "Base.FTZ_PlatformTrolley"

-- room type -> what can stand there
local ROOMS = {
    -- supermarkets / shops
    grocery = { CART, CART, TROLLEY }, gigamart = { CART, CART, TROLLEY }, zippeestore = { CART },
    conveniencestore = { CART }, grocerystorage = { TROLLEY, CART }, zippeestorage = { TROLLEY },
    generalstorestorage = { TROLLEY }, departmentstorage = { TROLLEY, CART },
    -- warehouses / stockrooms
    warehouse = { TROLLEY, TROLLEY, CART }, loggingwarehouse = { TROLLEY }, factorystorage = { TROLLEY },
    toolstorestorage = { TROLLEY }, metalshipping = { TROLLEY }, cabinetshipping = { TROLLEY },
}

local PLACE_CHANCE = 8 -- % per free square while a room still has carts to place (spreads them out)

local function sv(name, default)
    local t = SandboxVars and SandboxVars.FTZCarts
    if t and t[name] ~= nil then return tonumber(t[name]) or default end
    return default
end

local function data()
    local md = ModData.getOrCreate("FTZCarts")
    md.rooms = md.rooms or {}
    return md.rooms
end

local function roomType(sq)
    local room = sq:getRoom()
    if not room then return nil end
    local ok, name = pcall(function() return room:getRoomDef():getName() end)
    if ok and name then return string.lower(name) end
    return nil
end

local function isGoodSpot(sq)
    if not sq:hasFloor() or sq:isOutside() or sq:HasStairs() then return false end
    if not sq:isFree(false) then return false end
    if sq:getObjects():size() > 1 then return false end  -- only the floor: no shelves, counters, furniture
    if sq:getWorldObjects():size() > 0 then return false end
    return true
end

local function onLoadSquare(sq)
    if not sq then return end
    local rtype = roomType(sq)
    local choices = rtype and ROOMS[rtype]
    if not choices then return end

    local rooms = data()
    local key = tostring(sq:getRoomID())
    local left = rooms[key]
    if left == nil then
        -- first time this room is seen: roll once
        left = 0
        if ZombRand(100) < sv("WorldSpawnChance", 35) then
            left = 1 + ZombRand(math.max(1, math.floor(sv("WorldSpawnMax", 2))))
        end
        rooms[key] = left
    end
    if left <= 0 then return end
    if ZombRand(100) >= PLACE_CHANCE or not isGoodSpot(sq) then return end

    local itemType = choices[ZombRand(#choices) + 1]
    sq:AddWorldInventoryItem(itemType, 0.3 + ZombRand(40) / 100, 0.3 + ZombRand(40) / 100, 0)
    rooms[key] = left - 1
end

Events.LoadGridsquare.Add(onLoadSquare)
