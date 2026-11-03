CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local lastRunMin = {}
local lastTarget = {}
local lastSniffMin = {}
local heldTarget = {}

local function pickableFor(player, zd, itemType)
    if not itemType then return nil end
    local itemDef = forageSystem.itemDefs[itemType]
    if not itemDef then return nil end
    if not forageSystem.isForageable(player, itemDef, zd) then return nil end
    return itemDef
end

local function iconSquareHolds(player, zd, icon, cell)
    local itemDef = pickableFor(player, zd, icon.itemType)
    if not itemDef then return false end
    local catDef = forageSystem.catDefs[icon.catName]
    if not catDef then return false end
    local sq = cell:getGridSquare(math.floor(icon.x), math.floor(icon.y), math.floor(icon.z or 0))
    if not sq then return false end
    return forageSystem.isValidSquare(sq, itemDef, catDef) and true or false
end

local function nearestCritterIcon(player, zd, dx, dy, dz, prev)
    if not zd.forageIcons then return nil end
    local cell = getCell()
    if not cell then return nil end
    local R2 = CD.HUNT_FORAGE_SCOUT_RADIUS ^ 2
    local cats = CD.HUNT_FORAGE_SCOUT_CATEGORIES or {}
    local cand = {}
    for _, icon in pairs(zd.forageIcons) do
        if icon and icon.x and icon.y and icon.itemType and cats[icon.catName] then
            local ix, iy = math.floor(icon.x), math.floor(icon.y)
            local gx, gy = ix - dx, iy - dy
            local dd = gx * gx + gy * gy
            if dd <= R2 then
                cand[#cand + 1] = { icon = icon, x = ix, y = iy, z = math.floor(icon.z or dz), dd = dd }
            end
        end
    end
    if #cand == 0 then return nil end
    table.sort(cand, function(a, b) return a.dd < b.dd end)

    local maxCheck = CD.HUNT_FORAGE_SCOUT_VALIDATE_MAX
    local best, prevEntry
    for i = 1, math.min(#cand, maxCheck) do
        local c = cand[i]
        if prev and c.x == prev.x and c.y == prev.y then
            prevEntry = c
        end
        if not best and iconSquareHolds(player, zd, c.icon, cell) then
            best = c
            if prevEntry then break end
        end
    end
    if not best then return nil end
    if prevEntry and prevEntry ~= best and math.sqrt(prevEntry.dd) <= math.sqrt(best.dd) + 2 then
        if iconSquareHolds(player, zd, prevEntry.icon, cell) then
            return { x = prevEntry.x, y = prevEntry.y, z = prevEntry.z }
        end
    end
    return { x = best.x, y = best.y, z = best.z }
end

local function queueIconForOwner(player, zd, icon)
    local mgr = ISSearchManager.players[player]
    if not mgr or not mgr.isSearchMode then return end
    if not mgr.activeZones or not mgr.activeZones[zd.id] then return end
    if mgr.forageIcons[icon.id] or mgr.iconStack[icon] then return end
    mgr.iconStack[icon] = zd
    mgr.iconQueue = (mgr.iconQueue or 0) + 1
end

local function sniffOutCritter(player, dog, zd, dx, dy, dz)
    if (zd.itemsLeft or 0) < 1 then return nil end
    local placeCats = CD.HUNT_FORAGE_SCOUT_PLACE_CATEGORIES or {}
    local itemType, catName, itemDef
    for _ = 1, CD.HUNT_FORAGE_SCOUT_ROLLS do
        local it, cn = forageSystem.pickRandomItemType(zd.name)
        if it and cn and placeCats[cn] then
            local def = pickableFor(player, zd, it)
            if def then
                itemType, catName, itemDef = it, cn, def
                break
            end
        end
    end
    if not itemType then return nil end
    local catDef = forageSystem.catDefs[catName]
    if not catDef then return nil end
    local cell = getCell()
    if not cell then return nil end

    local occupied = {}
    if zd.forageIcons then
        for _, icon in pairs(zd.forageIcons) do
            if icon and icon.x and icon.y then
                occupied[math.floor(icon.x) .. "," .. math.floor(icon.y)] = true
            end
        end
    end

    local R = CD.HUNT_FORAGE_SCOUT_PLACE_RADIUS
    local R2 = R * R
    local bestX, bestY, bestD
    for gx = -R, R do
        for gy = -R, R do
            local dd = gx * gx + gy * gy
            if dd <= R2 and (not bestD or dd > bestD) then
                local sx, sy = dx + gx, dy + gy
                if not occupied[sx .. "," .. sy] then
                    local sq = cell:getGridSquare(sx, sy, dz)
                    if sq and forageSystem.isValidSquare(sq, itemDef, catDef) then
                        bestX, bestY, bestD = sx, sy, dd
                    end
                end
            end
        end
    end
    if not bestX then return nil end

    if isClient() then
        CD.request("foragesniff", dog, {
            x = bestX, y = bestY, z = dz, itemType = itemType, catName = catName,
        }, player)
        return { x = bestX, y = bestY, z = dz, sent = true }
    end

    local id = getRandomUUID()
    local icon = {
        id = id, zoneid = zd.id, x = bestX, y = bestY, z = dz,
        catName = catName, itemType = itemType, isBonusIcon = true, canRollForSearchFocus = false,
    }
    zd.forageIcons[id] = icon
    queueIconForOwner(player, zd, icon)
    forageSystem.takeItem(zd, 1)
    return { x = bestX, y = bestY, z = dz }
end

local function findZoneNear(dx, dy, ox, oy)
    local zd = forageSystem.getForageZoneAt(dx, dy)
    if zd then return zd end
    if ox and oy then
        zd = forageSystem.getForageZoneAt(ox, oy)
        if zd then return zd end
    end
    local p = CD.HUNT_FORAGE_SCOUT_ZONE_PROBE
    local dirs = { { p, 0 }, { -p, 0 }, { 0, p }, { 0, -p }, { p, p }, { p, -p }, { -p, p }, { -p, -p } }
    for _, d in ipairs(dirs) do
        zd = forageSystem.getForageZoneAt(dx + d[1], dy + d[2])
        if zd then return zd end
    end
    return nil
end

local function detectForageTarget(player, dog, pn, dx, dy, dz, ox, oy, prev, now)
    local held = heldTarget[pn]
    if held then
        if now <= (held.untilMin or 0) then return { x = held.x, y = held.y, z = held.z } end
        heldTarget[pn] = nil
    end

    local zd = findZoneNear(dx, dy, ox, oy)
    if not zd then return nil end
    local existing = nearestCritterIcon(player, zd, dx, dy, dz, prev)
    if existing then return existing end
    local cd = CD.HUNT_FORAGE_RETRY_COOLDOWN_MIN
    if lastSniffMin[zd.id] and (now - lastSniffMin[zd.id]) < cd then return nil end
    local placed = sniffOutCritter(player, dog, zd, dx, dy, dz)
    if placed then
        lastSniffMin[zd.id] = now
        heldTarget[pn] = {
            x = placed.x, y = placed.y, z = placed.z,
            untilMin = now + CD.HUNT_FORAGE_SCOUT_HOLD_MIN,
        }
    end
    return placed
end

local function runForageScout(player, pn, now)
    local dog = CD.getCompanionAnimal(player)
    if not dog or not CD.getHuntMode(dog) then
        lastTarget[pn] = nil
        heldTarget[pn] = nil
        return
    end

    local dx, dy, dz = math.floor(dog:getX()), math.floor(dog:getY()), math.floor(dog:getZ())
    local ox, oy = math.floor(player:getX()), math.floor(player:getY())
    local target = detectForageTarget(player, dog, pn, dx, dy, dz, ox, oy, lastTarget[pn], now)
    lastTarget[pn] = target
    if target and not target.sent then
        CD.request("foragescout", dog, { x = target.x, y = target.y, z = target.z }, player)
    end
end

local function onForageScout(player)
    if not player then return end
    if not CD.huntEnabled() or not CD.huntForagePointEnabled() then return end
    local pn = player:getPlayerNum()

    local now = math.floor(CD.worldMinutes())
    if lastRunMin[pn] == now then return end
    lastRunMin[pn] = now

    runForageScout(player, pn, now)
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onForageScout, "cli.foragescout")
end
