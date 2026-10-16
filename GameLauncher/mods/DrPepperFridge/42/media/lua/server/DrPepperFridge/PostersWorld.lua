require 'DrPepperFridge/Posters'
if isClient() then return end
local P = DrPepperPosters

-- Deliberately ONLY OnNewWithSprite: old, saved chunks never receive posters.
-- These vanilla sprites identify drink vending machines and industrial fridges.
-- A second set admits checkout counters only when the player broadens locations.
P.drinkAnchors = {}
for _, id in ipairs({ 16,17,18,19,22,23,36,37,40,41,42,43,44,45,46,47 }) do
    P.drinkAnchors[#P.drinkAnchors + 1] = 'appliances_refrigeration_01_' .. id
end
for _, id in ipairs({ 8,9,12,13,18,19,30,31 }) do
    P.drinkAnchors[#P.drinkAnchors + 1] = 'location_shop_accessories_01_' .. id
end
P.shopAnchors = {}
for _, id in ipairs({ 0,1,2,3,20,21,22,23 }) do
    P.shopAnchors[#P.shopAnchors + 1] = 'location_shop_accessories_01_' .. id
end

local function state()
    local data = ModData.getOrCreate('DrPepperFridge_Posters')
    if type(data.seed) ~= 'number' then data.seed = ZombRand(1000000) end
    if type(data.locations) ~= 'table' then data.locations = {} end
    return data
end

function P.locationKey(square)
    local building = square:getBuilding()
    if building and building:getDef() then
        local def = building:getDef()
        return 'b:' .. def:getX() .. ':' .. def:getY()
    end
    -- Outdoor vending points share a 10x10 location: no rows of adjacent posters.
    return 'o:' .. math.floor(square:getX() / 10) .. ':' .. math.floor(square:getY() / 10) .. ':' .. square:getZ()
end

function P.isUnvisited(square)
    local building = square:getBuilding()
    if building and building:getDef() and building:getDef():isHasBeenVisited() then return false end
    local room = square:getRoom()
    return not (room and room:getRoomDef() and room:getRoomDef():isExplored())
end

function P.findPlacement(origin, key, existing)
    local radius = math.floor(P.numberOption('PosterRadius', 1, 6))
    local chunk = origin:getChunk()
    if not chunk then return end
    local cell = getCell()
    -- Closest first; stable scan order avoids consuming global game RNG.
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.abs(dx) + math.abs(dy) == distance then
                    local square = cell:getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    -- A new anchor must NEVER decorate a neighboring saved chunk.
                    if square and square:getChunk() == chunk and P.locationKey(square) == key
                            and (existing or P.isUnvisited(square)) then
                        for _, facing in ipairs({ 'S', 'E' }) do
                            if P.wallAvailable(square, facing, existing, false) then return square, facing end
                        end
                    end
                end
            end
        end
    end
end

function P.onNewAnchor(object, isCheckout)
    if not P.option('PostersEnabled') then return end
    if isCheckout and P.option('PosterNearDrinksOnly') then return end
    if not object or not object:getSquare() then return end
    local origin = object:getSquare()
    if not P.isUnvisited(origin) then return end
    local key = P.locationKey(origin)
    local data = state()
    local record = data.locations[key]
    if record and record.placed then return end
    if not record then
        record = { roll = P.hash(key, data.seed) % 10000 / 100 }
        data.locations[key] = record
    end
    if record.roll >= P.numberOption('PosterChance', 0, 100) then return end
    local square, facing = P.findPlacement(origin, key)
    if not square then return end
    local design = P.hash(key .. ':design', data.seed) % #P.designs + 1
    local name = P.spriteName(design, facing)
    local sprite = getSprite(name)
    if not sprite or not sprite:getProperties():has('IsMoveAble') then return end
    local poster = IsoObject.new(getCell(), square, sprite)
    local md = poster:getModData()
    md.DrPepperPoster = P.designs[design]
    md.DrPepperPosterLocation = key
    md.DrPepperPosterPlacementRevision = P.placementRevision
    md.DrPepperPosterSpriteIndex = (design - 1) * 2 + (facing == 'S' and 1 or 0)
    poster:getSpriteName()
    square:AddTileObject(poster)
    record.placed = true
    record.design = design
    record.x, record.y, record.z = square:getX(), square:getY(), square:getZ()
    square:RecalcAllWithNeighbours(true)
    if isServer() then poster:transmitCompleteItemToClients() end
    return poster
end

-- Repair only this mod's existing collectibles, never generate new ones here.
-- Corrected textures update every saved sprite without changing its ID. This
-- migration additionally fixes an unsupported face, and relocates only a
-- tracked automatically generated poster when its old wall is occupied.
function P.repairLoadedPoster(object)
    if not object or not object:getSquare() or not object:getSprite() then return end
    local design, facing = P.spriteInfo(object:getSprite():getName())
    if not design then return end
    local md = object:getModData()
    if md.DrPepperPosterPlacementRevision == P.placementRevision then return end
    local square = object:getSquare()
    local target, targetFacing = square, facing
    if not P.wallAvailable(square, facing, object, true) then
        local other = facing == 'S' and 'E' or 'S'
        if P.wallAvailable(square, other, object, true) then
            targetFacing = other
        elseif md.DrPepperPosterLocation and not md.DrPepperPosterPlayerPlaced then
            target, targetFacing = P.findPlacement(square, P.locationKey(square), object)
        else
            return -- Preserve player placement/item; it remains available for pickup.
        end
    end
    if not target then return end -- No safe surface: no deletion or item loss.
    local sprite = getSprite(P.spriteName(design, targetFacing))
    if not sprite then return end
    if target ~= square then
        -- Only non-container collectibles can migrate; preserve the actual
        -- object and all its modData instead of recreating/dropping a duplicate.
        if object:getContainer() then return end
        square:transmitRemoveItemFromSquare(object)
        object:setSquare(target)
        object:setSprite(sprite)
        target:AddTileObject(object)
        square:RecalcAllWithNeighbours(true)
        target:RecalcAllWithNeighbours(true)
        if isServer() then object:transmitCompleteItemToClients() end
    elseif targetFacing ~= facing then
        object:setSprite(sprite)
        square:RecalcAllWithNeighbours(true)
        if isServer() then object:transmitUpdatedSpriteToClients() end
    end
    md.DrPepperPosterPlacementRevision = P.placementRevision
    if isServer() then object:transmitModData() end
end

MapObjects.OnNewWithSprite(P.drinkAnchors, function(object) P.onNewAnchor(object, false) end, 100)
MapObjects.OnNewWithSprite(P.shopAnchors, function(object) P.onNewAnchor(object, true) end, 100)
local posterNames = {}
for i = 0, 9 do posterNames[#posterNames + 1] = P.prefix .. i end
MapObjects.OnLoadWithSprite(posterNames, P.repairLoadedPoster, 100)
