CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

if not isServer() then return end

CD.Server = CD.Server or {}

local pending = {}

local function pname(player)
    if not player then return nil end
    return player:getUsername() or player:getDisplayName()
end

local function rollCount(itemDef)
    if not itemDef then return 1 end
    if itemDef.minCount == itemDef.maxCount then return itemDef.minCount or 1 end
    return ZombRand(itemDef.minCount, itemDef.maxCount) + 1
end

local function poolFor(user, zoneId)
    local pools = forageServer and forageServer.pools and forageServer.pools[user]
    if not pools then return nil end
    return pools[zoneId]
end

local function insertIntoPool(user, entry, rec)
    rec.cdUntilMin = nil
    entry.icons[rec.iconID] = rec
    local byId = forageServer.byId[user]
    if not byId then
        byId = {}
        forageServer.byId[user] = byId
    end
    byId[rec.iconID] = rec
end

local function queuePending(user, zoneId, rec, now)
    local byUser = pending[user]
    if not byUser then
        byUser = {}
        pending[user] = byUser
    end
    local list = byUser[zoneId]
    if not list then
        list = {}
        byUser[zoneId] = list
    end
    rec.cdUntilMin = now + CD.HUNT_FORAGE_SCOUT_PENDING_TTL_MIN
    list[#list + 1] = rec
end

local function drainPending(player)
    local user = pname(player)
    if not user then return end
    local byUser = pending[user]
    if not byUser then return end
    local now = CD.worldMinutes()
    local zoneIds = {}
    for zoneId in pairs(byUser) do zoneIds[#zoneIds + 1] = zoneId end
    for _, zoneId in ipairs(zoneIds) do
        local entry = poolFor(user, zoneId)
        local keep = {}
        for _, rec in ipairs(byUser[zoneId]) do
            if now <= (rec.cdUntilMin or 0) then
                if entry then
                    insertIntoPool(user, entry, rec)
                else
                    keep[#keep + 1] = rec
                end
            end
        end
        byUser[zoneId] = (#keep > 0) and keep or nil
    end
    local empty = true
    for _ in pairs(byUser) do  -- next() nao existe no Kahlua do PZ
        empty = false
        break
    end
    if empty then
        pending[user] = nil
    end
end

if forageServer and forageServer.onRequestZone then
    local origRequestZone = forageServer.onRequestZone
    forageServer.onRequestZone = function(player, focus)
        origRequestZone(player, focus)
        drainPending(player)
    end

    local origDropPlayer = forageServer.dropPlayer
    forageServer.dropPlayer = function(user)
        pending[user] = nil
        origDropPlayer(user)
    end
else
    CD.log("forageServer ausente no load; o batedor de forrageio nao vai fixar critter em MP")
end

---Checks a forage find the client scout picked near the hunting dog, adds it to the player's forage icons and points the dog at it.
---@param player IsoPlayer
---@param args table { id, itemType, catName, x, y, z }
CD.Server.foragesniff = function(player, args)
    if not player or not args then return end
    if not forageServer then return end
    if not CD.huntEnabled() or not CD.huntForagePointEnabled() then return end

    local animal = args.__animal or (args.id and getAnimal(tonumber(args.id)))
    if not animal or not CD.isDog(animal) then return end
    if not CD.isOwnedBy(animal, player) then return end
    if not CD.getHuntMode(animal) then return end

    local itemType, catName = args.itemType, args.catName
    local placeCats = CD.HUNT_FORAGE_SCOUT_PLACE_CATEGORIES or {}
    if not itemType or not catName or not placeCats[catName] then return end
    local itemDef = forageSystem.itemDefs[itemType]
    local catDef = forageSystem.catDefs[catName]
    if not itemDef or not catDef then return end
    local okCat = false
    if itemDef.categories then
        for _, cn in ipairs(itemDef.categories) do
            if cn == catName then
                okCat = true
                break
            end
        end
    end
    if not okCat then return end

    local x = math.floor(tonumber(args.x) or 0)
    local y = math.floor(tonumber(args.y) or 0)
    local z = math.floor(tonumber(args.z) or 0)
    local R = CD.HUNT_FORAGE_SCOUT_PLACE_RADIUS + 2
    local gx, gy = x - animal:getX(), y - animal:getY()
    if (gx * gx + gy * gy) > (R * R) then return end

    local zoneData = forageSystem.getForageZoneAt(x, y)
    if not zoneData then return end
    if not forageSystem.isForageable(player, itemDef, zoneData) then return end

    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    if not sq or not forageSystem.isValidSquare(sq, itemDef, catDef) then return end

    local user = pname(player)
    if not user then return end

    local rec = {
        iconID = getRandomUUID(), zoneId = zoneData.id,
        x = x, y = y, z = z,
        itemType = itemType, catName = catName,
        count = rollCount(itemDef), isBonusIcon = true,
    }
    local entry = poolFor(user, zoneData.id)
    local now = CD.worldMinutes()
    if entry then
        insertIntoPool(user, entry, rec)
    else
        queuePending(user, zoneData.id, rec, now)
    end
    forageSystem.takeItem(zoneData, 1)

    CD.data(animal).forageScoutTarget = {
        x = x, y = y, z = z,
        untilMin = now + CD.HUNT_FORAGE_SCOUT_TTL_MIN,
    }
end
