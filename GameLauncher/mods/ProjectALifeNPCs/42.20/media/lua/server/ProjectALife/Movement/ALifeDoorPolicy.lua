ProjectALife = ProjectALife or {}

local Policy = {
    settings = {

        lockedBanMs = 180000,

        courtesyTiles = 10,
        baseMargin = 2,
        compoundMargin = 16,
        homeCacheMs = 1000,
        pathRefusalMs = 30000,
        evictEveryMs = 1500,
        evictRetryMs = 8000,
    },

    lockDataKeys = { "CustomLock" },

    adapters = {},
}
ProjectALife.DoorPolicy = Policy

function Policy.ask(object, name)
    if object == nil then return nil end
    local query = object[name]
    if type(query) ~= "function" then return nil end
    local ok, value = pcall(query, object)
    if not ok then return nil end
    return value
end

function Policy.callStatic(fn, ...)

    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

function Policy.keyHolds(object, from)
    if from == nil or type(from.has) ~= "function" or IsoFlagType == nil
            or IsoFlagType.exterior == nil then
        return true
    end
    local props = Policy.ask(object, "getProperties")
    if props ~= nil and type(props.has) == "function" then
        local asked, forced = pcall(props.has, props, "forceLocked")
        if asked and forced == true then return true end
    end
    local ok, outside = pcall(from.has, from, IsoFlagType.exterior)
    if ok ~= true or outside == true then return true end
    if type(instanceof) ~= "function" or not instanceof(object, "IsoDoor") then return true end
    local room = Policy.ask(from, "getRoom")
    if room == nil then return true end
    local here = Policy.ask(Policy.ask(object, "getSquare"), "getRoom")
    local across = Policy.ask(Policy.ask(object, "getOppositeSquare"), "getRoom")
    return room ~= here and room ~= across
end

function Policy.keyWaived(object, from)
    if object == nil or from == nil then return false end
    if Policy.ask(object, "isLockedByKey") ~= true then return false end

    if Policy.hopGate(object) then return true end
    return Policy.keyHolds(object, from) == false
end

function Policy.hopGate(object)
    if type(instanceof) ~= "function" or not instanceof(object, "IsoDoor") then return false end
    if Policy.ask(object, "IsOpen") == true then return false end
    return Policy.ask(object, "isHoppable") == true
end

function Policy.lockKind(object, from)
    if object == nil then return nil end
    if Policy.ask(object, "isLockedByKey") == true then return "key" end
    if Policy.ask(object, "isLocked") == true and not Policy.hopGate(object)
            and Policy.keyHolds(object, from) then return "key" end
    if Policy.ask(object, "isLockedByPadlock") == true then return "padlock" end

    if (tonumber(Policy.ask(object, "getLockedByCode")) or 0) > 0 then return "code" end

    if Policy.customLocked(object) then return "custom" end
    return nil
end

function Policy.customLocked(object)
    if Policy.ask(object, "hasModData") == false then return false end
    local data = Policy.ask(object, "getModData")
    if type(data) ~= "table" then return false end
    for index = 1, #Policy.lockDataKeys do
        local value = data[Policy.lockDataKeys[index]]
        if value ~= nil and value ~= false then return true end
    end
    return false
end

function Policy.playerLocked(object)
    if Policy.ask(object, "isLockedByPadlock") == true then return true end
    if (tonumber(Policy.ask(object, "getLockedByCode")) or 0) > 0 then return true end
    return Policy.customLocked(object)
end

function Policy.unlockableFrom(object, from)
    if object == nil then return false end
    local leaves, keyed = Policy.leaves(object), false
    for index = 1, #leaves do
        if Policy.ask(leaves[index], "isLockedByKey") == true then keyed = true end
    end
    if not keyed or Policy.keyHolds(object, from) then return false end
    for index = 1, #leaves do
        if Policy.playerLocked(leaves[index]) then return false end
    end
    return true
end

function Policy.groupObstructed(object)
    if object == nil or IsoDoor == nil then return false end
    if (tonumber(Policy.callStatic(IsoDoor.getDoubleDoorIndex, object)) or -1) > -1 then
        return Policy.callStatic(IsoDoor.isDoubleDoorObstructed, object) == true
    end
    if (tonumber(Policy.callStatic(IsoDoor.getGarageDoorIndex, object)) or -1) < 0 then return false end
    local section = Policy.callStatic(IsoDoor.getGarageDoorFirst, object)
    for _ = 1, 8 do
        if section == nil then return false end
        if Policy.ask(section, "isObstructed") == true then return true end
        if Policy.ask(Policy.ask(section, "getSquare"), "getVehicleContainer") ~= nil then return true end
        section = Policy.callStatic(IsoDoor.getGarageDoorNext, section)
    end
    return false
end

function Policy.blockKind(object, from)
    if object == nil then return nil end
    if Policy.ask(object, "isObstructed") == true or Policy.groupObstructed(object) then return "obstructed" end
    if Policy.ask(object, "isBarricaded") == true then return "barricaded" end
    return Policy.lockKind(object, from)
end

function Policy.playerLock(kind)
    return kind == "padlock" or kind == "code" or kind == "custom"
end

function Policy.groupLocked(object, from)
    if object == nil or IsoDoor == nil then return false end
    local double = tonumber(Policy.callStatic(IsoDoor.getDoubleDoorIndex, object)) or -1
    if double > -1 then
        for index = 1, 4 do
            local leaf = Policy.callStatic(IsoDoor.getDoubleDoorObject, object, index)
            if leaf ~= nil and leaf ~= object and Policy.lockKind(leaf, from) ~= nil then
                return true
            end
        end
        return false
    end
    if (tonumber(Policy.callStatic(IsoDoor.getGarageDoorIndex, object)) or -1) < 0 then
        return false
    end
    local leaf = Policy.callStatic(IsoDoor.getGarageDoorFirst, object)

    for _ = 1, 8 do
        if leaf == nil then return false end
        if leaf ~= object and Policy.lockKind(leaf, from) ~= nil then return true end
        leaf = Policy.callStatic(IsoDoor.getGarageDoorNext, leaf)
    end
    return false
end

function Policy.grouped(object)
    if object == nil or IsoDoor == nil then return false end
    if (tonumber(Policy.callStatic(IsoDoor.getDoubleDoorIndex, object)) or -1) > -1 then return true end
    return (tonumber(Policy.callStatic(IsoDoor.getGarageDoorIndex, object)) or -1) > -1
end

function Policy.strength(object, floor)
    floor = math.max(0, tonumber(floor) or 0)
    local health = tonumber(Policy.ask(object, "getHealth"))
    if health ~= nil and health > 0 then return health, "health" end
    local maximum = tonumber(Policy.ask(object, "getMaxHealth"))
    if maximum ~= nil and maximum > 0 then
        if health ~= nil then return health, "worn" end
        return math.min(maximum, floor), "floor"
    end
    return floor, "floor"
end

function Policy.actorOf(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    local ok, data = pcall(shell.getModData, shell)
    if not ok or type(data) ~= "table" or data.ProjectALifeUID == nil then return nil end
    local actors = ProjectALife.ActorRegistry
    if actors == nil or type(actors.read) ~= "function" then return nil end
    local read, actor = pcall(actors.read, data.ProjectALifeUID)
    if not read or type(actor) ~= "table" then return nil end
    return actor
end

function Policy.mayBreach(shell, object, kind)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.ownSiteObject) == "function"
            and traversal.ownSiteObject(shell, object) == true then
        return false
    end
    if not Policy.playerLock(kind) then return true end
    local actor = Policy.actorOf(shell)
    local registry = ProjectALife.ModuleRegistry
    if actor == nil or registry == nil or type(registry.allows) ~= "function" then
        return false
    end
    local ok, allowed = pcall(registry.allows, actor, "doorstack")
    return ok and allowed == true
end

function Policy.pointOf(object)
    local square = Policy.ask(object, "getSquare")
    local x, y = tonumber(Policy.ask(square, "getX")), tonumber(Policy.ask(square, "getY"))
    if x == nil or y == nil then return nil end
    return x + 0.5, y + 0.5
end

function Policy.oppositePoint(object)
    local square = Policy.ask(object, "getOppositeSquare")
    local x, y = tonumber(Policy.ask(square, "getX")), tonumber(Policy.ask(square, "getY"))
    if x == nil or y == nil then return nil end
    return x + 0.5, y + 0.5
end

function Policy.breachAllowed(shell, object)
    local actor = Policy.actorOf(shell)
    if actor == nil then return true end
    local x, y = Policy.pointOf(object)
    if x == nil then return true end
    local home = Policy.homeRefusal(actor, x, y)
    if home == nil then
        local ox, oy = Policy.oppositePoint(object)
        if ox ~= nil then home = Policy.homeRefusal(actor, ox, oy) end
    end
    if home ~= nil and Policy.insideHome(actor, shell) == nil then
        Policy.note("door", home)
        return false
    end
    return not Policy.keepsOut(actor, x, y)
end

function Policy.keepsOut(actor, x, y, baseOnly, given)
    local relations = ProjectALife.Relations
    if type(actor) ~= "table" or relations == nil or type(relations.playerStance) ~= "function" then
        return false
    end
    local owners = given or Policy.baseOwners(x, y)
    local anyone = owners ~= nil and #owners == 0
    local reach = Policy.settings.courtesyTiles * Policy.settings.courtesyTiles
    local players, asked = Policy.players(), false
    for index = 1, #players do
        local player = players[index]
        local px, py = tonumber(Policy.ask(player, "getX")), tonumber(Policy.ask(player, "getY"))
        if px ~= nil and py ~= nil and Policy.ask(player, "isDead") ~= true
                and (anyone or Policy.claimOwner(owners, player)
                    or (baseOnly ~= true and (px - x) * (px - x) + (py - y) * (py - y) <= reach
                        and not Policy.inCompany(actor, player))) then
            asked = true
            if Policy.courteousTo(relations, actor, player) then return true end
        end
    end
    if anyone then return not asked and Policy.courteousTo(relations, actor, nil) end
    if owners == nil then return false end

    for index = 1, #owners do
        if owners[index] ~= false and Policy.courteousTo(relations, actor, owners[index]) then return true end
    end
    return false
end

function Policy.nowMs()
    if type(Policy.adapters.nowMs) == "function" then return Policy.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Policy.inCompany(actor, player)
    if type(actor) ~= "table" or player == nil then return false end
    local now = Policy.nowMs()
    local decisions = ProjectALife.DecisionLoop
    local orders = decisions ~= nil and decisions.orders or nil
    local order = type(orders) == "table" and actor.uid ~= nil and orders[actor.uid] or nil
    if type(order) == "table" and order.kind == "follow" and order.generation == actor.generation
            and (order.untilMs == nil or now < (tonumber(order.untilMs) or 0)) then
        if order.player == player then return true end
        local name = Policy.ask(player, "getUsername")
        if name ~= nil and name == Policy.ask(order.player, "getUsername") then return true end
    end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    local leases = memory ~= nil and memory.tolerateUntil or nil
    local speech = ProjectALife.Speech
    if type(leases) ~= "table" or speech == nil or type(speech.playerKey) ~= "function" then return false end
    local ok, key = pcall(speech.playerKey, player)
    local untilMs = ok and key ~= nil and tonumber(leases[key]) or nil
    return untilMs ~= nil and now < untilMs
end

function Policy.courteousTo(relations, actor, player)
    local ok, stance = pcall(relations.playerStance, actor, player)
    return ok == true and type(stance) == "string" and stance ~= "hostile"
end

function Policy.claimOwner(owners, player)
    if owners == nil then return false end
    local heat, key = ProjectALife.BaseHeat, nil
    if heat ~= nil and type(heat.keyOf) == "function" then
        local ok, value = pcall(heat.keyOf, player)
        if ok then key = value end
    end
    local name, found = Policy.ask(player, "getUsername"), false
    for index = 1, #owners do
        local owner = owners[index]
        if owner ~= false and (owner == key or owner == name) then
            owners[index] = false
            found = true
        end
    end
    return found
end

function Policy.players()
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return {} end
    local ok, list = pcall(locator.list, Policy.adapters.players)
    if not ok or type(list) ~= "table" then return {} end
    return list
end

function Policy.playerNear(x, y)
    local reach = Policy.settings.courtesyTiles * Policy.settings.courtesyTiles
    local players = Policy.players()
    for index = 1, #players do
        local player = players[index]
        local px, py = tonumber(Policy.ask(player, "getX")), tonumber(Policy.ask(player, "getY"))
        if Policy.ask(player, "isDead") ~= true and px ~= nil and py ~= nil
                and (px - x) * (px - x) + (py - y) * (py - y) <= reach then
            return true
        end
    end
    return false
end

function Policy.baseOwners(x, y, occupied, listed)
    local owners = nil
    local house = Policy.safehouseAt(x, y)
    if house ~= nil then
        owners = {}
        Policy.addName(owners, Policy.ask(house, "getOwner"))
        local members = Policy.ask(house, "getPlayers")
        if members ~= nil and type(members.size) == "function" and type(members.get) == "function" then
            for index = 0, math.min(tonumber(members:size()) or 0, 32) - 1 do
                Policy.addName(owners, members:get(index))
            end
        end
    end
    local bases, margin = listed or Policy.baseList(), Policy.settings.baseMargin
    for index = 1, #bases do
        local base = bases[index]
        if type(base) == "table" and (base.occupied ~= true or occupied == true) then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil
                    and x >= x1 - margin and x <= x2 + margin and y >= y1 - margin and y <= y2 + margin then
                owners = owners or {}
                Policy.addName(owners, base.owner)
            end
        end
    end
    return owners
end

function Policy.playerBuiltDoor(object)
    return type(instanceof) == "function" and instanceof(object, "IsoThumpable") == true
        and Policy.ask(object, "isDoor") == true
end

function Policy.boundaryOwners(object)
    local x, y = Policy.pointOf(object)
    if x == nil then return nil end
    local owners = Policy.baseOwners(x, y)
    if owners ~= nil or not Policy.playerBuiltDoor(object) then return owners, x, y end
    local bases, reach = Policy.baseList(), Policy.settings.compoundMargin
    for index = 1, #bases do
        local base = bases[index]
        if type(base) == "table" and base.occupied ~= true then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil
                    and x >= x1 - reach and x <= x2 + reach and y >= y1 - reach and y <= y2 + reach then
                owners = owners or {}
                Policy.addName(owners, base.owner)
            end
        end
    end
    return owners, x, y
end

function Policy.boundaryKeepsOut(actor, object)
    local owners, x, y = Policy.boundaryOwners(object)
    if owners == nil then return false end
    if Policy.accompanies(actor, owners) then return false end
    return Policy.keepsOut(actor, x, y, true, owners)
end

function Policy.addName(list, name)
    if type(name) == "string" and name ~= "" then list[#list + 1] = name end
end

function Policy.inPlayerBase(x, y, occupied)
    return Policy.baseOwners(x, y, occupied) ~= nil
end

function Policy.flaggedBaseAt(x, y, listed)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    x, y = math.floor(x), math.floor(y)
    local bases = listed or Policy.baseList()
    for index = 1, #bases do
        local base = bases[index]
        if type(base) == "table" and base.flagged == true then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil and x >= x1 and x <= x2 and y >= y1 and y <= y2 then
                return base
            end
        end
    end
    return nil
end

function Policy.invitedAt(actor, x, y)
    if type(Policy.adapters.invited) == "function" then return Policy.adapters.invited(actor, x, y) == true end
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    local party = ProjectALife.Party
    if party ~= nil and type(party.sharesGroup) == "function" and party.sharesGroup(actor, x, y) then return true end
    local guest = memory ~= nil and memory.guest or nil
    x, y = tonumber(x), tonumber(y)
    if type(guest) ~= "table" or x == nil or y == nil or type(getGameTime) ~= "function" then return false end
    local now = tonumber(Policy.ask(getGameTime(), "getWorldAgeHours"))
    if now == nil or now > (tonumber(guest.untilHours) or -math.huge)
            or now > (tonumber(guest.renewedHours) or -math.huge) + 3 then return false end
    local x1, y1 = tonumber(guest.x1), tonumber(guest.y1)
    local x2, y2 = tonumber(guest.x2), tonumber(guest.y2)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return false end
    return x >= x1 - 1 and x <= x2 + 1 and y >= y1 - 1 and y <= y2 + 1
end

Policy.metrics = { refused = 0, invited = 0, evicted = 0, by = {}, kinds = {} }
Policy.cache = nil
Policy.keyCache = setmetatable({}, { __mode = "k" })
Policy.stepCache = {}
Policy.evictClock = {}
Policy.exemptIntents = { fear_flee = true, gun_flee = true, retreat = true, robbery_leave = true, robbery_close = true, leave_home = true,
    panic = true }

function Policy.reset()
    Policy.metrics = { refused = 0, invited = 0, evicted = 0, by = {}, kinds = {} }
    Policy.cache, Policy.stepCache, Policy.evictClock = nil, {}, {}
    Policy.keyCache = setmetatable({}, { __mode = "k" })
end

function Policy.dropCache()
    Policy.cache, Policy.stepCache = nil, {}
end

function Policy.note(path, kind)
    local metrics = Policy.metrics
    metrics.refused = metrics.refused + 1
    metrics.by[path] = (metrics.by[path] or 0) + 1
    if kind ~= nil then metrics.kinds[kind] = (metrics.kinds[kind] or 0) + 1 end
end

function Policy.qaLine()
    local metrics = Policy.metrics
    local by, kinds = metrics.by, metrics.kinds
    return string.format("[ALIFE-QA] HomeEntry: refused=%d byReason door=%d window=%d path=%d clue=%d warn=%d combat=%d"
        .. " evict=%d invited=%d kinds flagged=%d occupied=%d safehouse=%d", metrics.refused,
        by.door or 0, by.window or 0, by.path or 0, by.clue or 0, by.warn or 0, by.combat or 0, metrics.evicted,
        metrics.invited, kinds.flagged or 0, kinds.occupied or 0, kinds.safehouse or 0)
end

function Policy.boundsKey(x1, y1, x2, y2)
    return string.format("%d:%d:%d:%d", math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2))
end

function Policy.buildingKey(building)
    if building == nil or building == false then return nil end
    local hit = Policy.keyCache[building]
    if hit ~= nil then return hit or nil end
    local definition = Policy.ask(building, "getDef")
    local x1, y1 = tonumber(Policy.ask(definition, "getX")), tonumber(Policy.ask(definition, "getY"))
    local x2, y2 = tonumber(Policy.ask(definition, "getX2")), tonumber(Policy.ask(definition, "getY2"))
    local key = false
    if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then key = Policy.boundsKey(x1, y1, x2, y2) end
    Policy.keyCache[building] = key
    return key or nil
end

function Policy.homeCache()
    local now = Policy.nowMs()
    local cache = Policy.cache
    if cache == nil or now < cache.atMs or now - cache.atMs >= Policy.settings.homeCacheMs or cache.count > 512 then
        cache = { atMs = now, tiles = {}, count = 0 }
        Policy.cache = cache
    end
    return cache
end

function Policy.occupiedIndex(cache)
    if cache.index ~= nil then return cache.index, cache.boxes end
    local index, boxes = {}, {}
    local bases = Policy.cachedBases(cache)
    for position = 1, #bases do
        local base = bases[position]
        if type(base) == "table" and base.occupied == true then
            local x1, y1 = tonumber(base.x1), tonumber(base.y1)
            local x2, y2 = tonumber(base.x2), tonumber(base.y2)
            if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                local key = Policy.boundsKey(x1, y1, x2, y2)
                local row = index[key]
                if row == nil then
                    row = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, key = key, owners = {} }
                    index[key] = row
                    boxes[#boxes + 1] = row
                end
                Policy.addName(row.owners, base.owner)
            end
        end
    end
    cache.index, cache.boxes = index, boxes
    return index, boxes
end

function Policy.cachedBases(cache)
    if cache.bases == nil then cache.bases = Policy.baseList() end
    return cache.bases
end

function Policy.tileHome(cache, fx, fy)
    local tile = fx * 131072 + fy
    local row = cache.tiles[tile]
    if row == nil then
        local flagged = Policy.flaggedBaseAt(fx, fy, Policy.cachedBases(cache))
        local house = nil
        if flagged == nil then house = Policy.safehouseAt(fx, fy, 0) end
        row = { flagged = flagged or false, house = house or false }
        cache.tiles[tile] = row
        cache.count = cache.count + 1
    end
    return row
end

function Policy.houseId(house)
    local x, y = Policy.ask(house, "getX"), Policy.ask(house, "getY")
    if x == nil or y == nil then return "s:" .. tostring(Policy.ask(house, "getOwner") or house) end
    return "s:" .. tostring(x) .. ":" .. tostring(y)
end

function Policy.privateAt(x, y, building)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    local fx, fy = math.floor(x), math.floor(y)
    local cache = Policy.homeCache()
    local row = Policy.tileHome(cache, fx, fy)
    if row.flagged ~= false then
        return { kind = "flagged", row = row, cache = cache,
            id = "f:" .. tostring(row.flagged.key or (row.flagged.x1 .. ":" .. row.flagged.y1)) }
    end
    local index, boxes = Policy.occupiedIndex(cache)
    if building ~= false and #boxes > 0 then
        local found = nil
        if building ~= nil then
            local key = Policy.buildingKey(building)
            found = key ~= nil and index[key] or nil
        else
            for position = 1, #boxes do
                local box = boxes[position]
                if fx >= box.x1 and fx <= box.x2 and fy >= box.y1 and fy <= box.y2 then found = box break end
            end
        end
        if found ~= nil then
            return { kind = "occupied", id = "o:" .. found.key, owners = found.owners, row = row, cache = cache }
        end
    end
    if row.house ~= false then return { kind = "safehouse", id = Policy.houseId(row.house), row = row, cache = cache } end
    return nil
end

function Policy.homeOwners(home, x, y)
    local row = home.row
    if row ~= nil and row.owners == nil then
        row.owners = Policy.baseOwners(math.floor(x) + 0.5, math.floor(y) + 0.5, true, Policy.cachedBases(home.cache)) or false
    end
    local owners = row ~= nil and row.owners or false
    if owners == false then owners = home.owners end
    return Policy.copyList(owners)
end

function Policy.copyList(list)
    if type(list) ~= "table" then return nil end
    local copy = {}
    for index = 1, #list do copy[index] = list[index] end
    return copy
end

function Policy.ownPost(actor, x, y)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or memory.outpostSquadId ~= nil then return false end
    local bounds = memory.nightHoldHomeBounds or memory.garrisonBounds
    if type(bounds) ~= "table" and type(memory.outpostId) == "string" then
        local sites = ProjectALife.OutpostRegistry
        local site = sites ~= nil and type(sites.read) == "function" and sites.read(memory.outpostId) or nil
        bounds = type(site) == "table" and site.bounds or nil
    end
    if type(bounds) ~= "table" then return false end
    local x1, y1, x2, y2 = tonumber(bounds.x1), tonumber(bounds.y1), tonumber(bounds.x2), tonumber(bounds.y2)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return false end
    return x >= x1 - 1 and x <= x2 + 1 and y >= y1 - 1 and y <= y2 + 1
end

function Policy.accompanies(actor, owners)
    if type(owners) ~= "table" then return false end
    local players = Policy.players()
    for index = 1, #players do
        local player = players[index]
        local heat, key = ProjectALife.BaseHeat, nil
        if heat ~= nil and type(heat.keyOf) == "function" then
            local ok, value = pcall(heat.keyOf, player)
            if ok then key = value end
        end
        local name = Policy.ask(player, "getUsername")
        for position = 1, #owners do
            local owner = owners[position]
            if owner ~= false and (owner == key or owner == name) and Policy.inCompany(actor, player) then return true end
        end
    end
    return false
end

function Policy.homeRefusal(actor, x, y, building)
    if type(actor) ~= "table" then return nil end
    local home = Policy.privateAt(x, y, building)
    if home == nil then return nil end
    x, y = tonumber(x), tonumber(y)
    if Policy.invitedAt(actor, x, y) then
        Policy.metrics.invited = Policy.metrics.invited + 1
        return nil
    end
    if home.kind == "occupied" and Policy.ownPost(actor, x, y) then return nil end
    local owners = Policy.homeOwners(home, x, y)
    if owners == nil then return nil end
    if Policy.accompanies(actor, owners) then return nil end
    if not Policy.keepsOut(actor, x, y, true, owners) then return nil end
    return home.kind
end

function Policy.mayEnterHome(actor, x, y, building)
    return Policy.homeRefusal(actor, x, y, building) == nil
end

function Policy.crossingKind(from, to)
    if from == nil or to == nil then return "door" end
    local names = { "getWindowTo", "getWindowFrameTo", "getWindowThumpableTo" }
    for index = 1, #names do
        local query = from[names[index]]
        if type(query) == "function" then
            local ok, found = pcall(query, from, to)
            if ok and found ~= nil then return "window" end
        end
    end
    return "door"
end

function Policy.homeEntryRefused(shell, from, to)
    local tx, ty = tonumber(Policy.ask(to, "getX")), tonumber(Policy.ask(to, "getY"))
    local fx, fy = tonumber(Policy.ask(from, "getX")), tonumber(Policy.ask(from, "getY"))
    if tx == nil or ty == nil or fx == nil or fy == nil then return false end
    if Policy.flaggedBaseAt(tx, ty) ~= nil then return false end
    local target = Policy.privateAt(tx, ty, Policy.ask(to, "getBuilding") or false)
    if target == nil then return false end
    local source = Policy.privateAt(fx, fy, Policy.ask(from, "getBuilding") or false)
    if source ~= nil and source.id == target.id then return false end
    local actor = Policy.actorOf(shell)
    if actor == nil then return false end
    local kind = Policy.homeRefusal(actor, tx, ty, Policy.ask(to, "getBuilding") or false)
    if kind == nil then return false end
    Policy.note(Policy.crossingKind(from, to), kind)
    return true
end

function Policy.pathRefusal(actor, shell, target, intent)
    if type(actor) ~= "table" or type(target) ~= "table" then return nil end
    if intent ~= nil and Policy.exemptIntents[intent] == true then return nil end
    if type(actor.memory) == "table" and type(actor.memory.visit) == "table" then return nil end
    local kind = Policy.homeRefusal(actor, target.x, target.y)
    if kind ~= nil then Policy.note(intent == "combat" and "combat" or "path", kind) end
    return kind
end

function Policy.doorStep(building, shell)
    local definition = Policy.ask(building, "getDef")
    local x1, y1 = tonumber(Policy.ask(definition, "getX")), tonumber(Policy.ask(definition, "getY"))
    local x2, y2 = tonumber(Policy.ask(definition, "getX2")), tonumber(Policy.ask(definition, "getY2"))
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return nil end
    local key = Policy.boundsKey(x1, y1, x2, y2)
    local now = Policy.nowMs()
    local held = Policy.stepCache[key]
    if held == nil or now < held.atMs or now - held.atMs >= 5000 then
        held = { atMs = now, points = {} }
        Policy.stepCache[key] = held
        local cell = type(getCell) == "function" and getCell() or nil
        if type(Policy.adapters.squareAt) ~= "function" and cell == nil then return nil end
        x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
        local function consider(x, y)
            local square = nil
            if type(Policy.adapters.squareAt) == "function" then square = Policy.adapters.squareAt(x, y, 0)
            else square = cell:getGridSquare(x, y, 0) end
            if square == nil or Policy.ask(square, "getBuilding") ~= nil then return end
            local free = true
            if type(square.isFree) == "function" then
                local ok, answer = pcall(square.isFree, square, false)
                free = ok and answer == true
            end
            if free then held.points[#held.points + 1] = { x = x + 0.5, y = y + 0.5, z = 0 } end
        end
        for x = x1 - 1, x2 + 1 do consider(x, y1 - 1) consider(x, y2 + 1) end
        for y = y1, y2 do consider(x1 - 1, y) consider(x2 + 1, y) end
    end
    local sx, sy = tonumber(Policy.ask(shell, "getX")), tonumber(Policy.ask(shell, "getY"))
    local best, bestDistance = nil, math.huge
    for index = 1, #held.points do
        local point = held.points[index]
        local distance = sx == nil and 0 or (point.x - sx) ^ 2 + (point.y - sy) ^ 2
        if distance < bestDistance then best, bestDistance = point, distance end
    end
    if best == nil then return nil end
    return { x = best.x, y = best.y, z = best.z }
end

function Policy.insideHome(actor, body)
    if type(actor) ~= "table" or body == nil then return nil end
    local square = Policy.ask(body, "getCurrentSquare") or Policy.ask(body, "getSquare")
    local building = Policy.ask(square, "getBuilding")
    if building == nil then return nil end
    local x, y = tonumber(Policy.ask(square, "getX")), tonumber(Policy.ask(square, "getY"))
    if x == nil or y == nil then return nil end
    return Policy.homeRefusal(actor, x, y, building), building
end

function Policy.evictionTarget(actor, shell)
    local kind, building = Policy.insideHome(actor, shell)
    if kind == nil then return nil end
    return Policy.doorStep(building, shell), kind
end

function Policy.evictionStep(actor, shell, now, begin)
    if type(actor) ~= "table" or type(begin) ~= "function" or not Policy.evictionDue(actor.uid, now) then return nil end
    local target, kind = Policy.evictionTarget(actor, shell)
    if kind == nil then return nil end
    if target == nil then
        Policy.evictionFailed(actor.uid, now)
        return nil
    end
    local state = begin(actor, shell, target)
    if state == nil then
        Policy.evictionFailed(actor.uid, now)
        return nil
    end
    Policy.metrics.evicted = Policy.metrics.evicted + 1
    Policy.metrics.kinds[kind] = (Policy.metrics.kinds[kind] or 0) + 1
    return state
end

function Policy.evictionDue(uid, now)
    if type(uid) ~= "string" then return false end
    local due = Policy.evictClock[uid]
    now = tonumber(now) or Policy.nowMs()
    if due ~= nil and now < due and now >= due - Policy.settings.evictRetryMs then return false end
    Policy.evictClock[uid] = now + Policy.settings.evictEveryMs
    return true
end

function Policy.evictionFailed(uid, now)
    if type(uid) ~= "string" then return end
    Policy.evictClock[uid] = (tonumber(now) or Policy.nowMs()) + Policy.settings.evictRetryMs
end

function Policy.clueLead(actor, shell, lead)
    if type(actor) ~= "table" or type(lead) ~= "table" then return nil end
    local kind = Policy.homeRefusal(actor, lead.x, lead.y)
    if kind == nil then return nil end
    Policy.note("clue", kind)
    local cell = type(getCell) == "function" and getCell() or nil
    local square = nil
    if type(Policy.adapters.squareAt) == "function" then
        square = Policy.adapters.squareAt(math.floor(lead.x), math.floor(lead.y), math.floor(tonumber(lead.z) or 0))
    elseif cell ~= nil then
        square = cell:getGridSquare(math.floor(lead.x), math.floor(lead.y), math.floor(tonumber(lead.z) or 0))
    end
    local building = Policy.ask(square, "getBuilding")
    if building == nil then return false end
    local step = Policy.doorStep(building, shell)
    if step == nil or Policy.homeRefusal(actor, step.x, step.y) ~= nil then return false end
    return step
end

function Policy.baseEntryRefused(shell, from, to)
    local tx, ty = tonumber(Policy.ask(to, "getX")), tonumber(Policy.ask(to, "getY"))
    local fx, fy = tonumber(Policy.ask(from, "getX")), tonumber(Policy.ask(from, "getY"))
    if tx == nil or ty == nil or fx == nil or fy == nil then return false end
    if Policy.homeEntryRefused(shell, from, to) then return true end
    if Policy.flaggedBaseAt(tx, ty) == nil or Policy.flaggedBaseAt(fx, fy) ~= nil then return false end
    local actor = Policy.actorOf(shell)
    if actor == nil then return false end
    if Policy.invitedAt(actor, tx, ty) then return false end
    if Policy.accompanies(actor, Policy.baseOwners(tx, ty)) then return false end
    return Policy.keepsOut(actor, tx + 0.5, ty + 0.5, true)
end

function Policy.safehouseAt(x, y, suppliedMargin)
    local houses = SafeHouse
    if houses == nil or houses.getSafehouseOverlapping == nil then return nil end
    local margin = tonumber(suppliedMargin) or Policy.settings.baseMargin
    local fx, fy = math.floor(x), math.floor(y)
    local ok, found = pcall(houses.getSafehouseOverlapping, fx - margin, fy - margin,
        fx + margin + 1, fy + margin + 1)
    if ok ~= true then return nil end
    return found
end

function Policy.baseList()
    local bases = nil
    if type(isClient) == "function" and isClient() == true then bases = Policy.mirroredBases() end
    if bases ~= nil then return bases end
    local spawn = ProjectALife.SpawnPolicy
    if spawn == nil or type(spawn.playerBases) ~= "function" then return {} end
    local ok, list = pcall(spawn.playerBases)
    if ok ~= true or type(list) ~= "table" then return {} end
    return list
end

function Policy.mirroredBases()
    local transport = ProjectALife.MirrorTransport
    if transport == nil or type(transport.clientBases) ~= "function" then return {} end
    local ok, bases = pcall(transport.clientBases)
    if ok ~= true or type(bases) ~= "table" then return {} end
    return bases
end

function Policy.entering(from, to, object)
    if object ~= nil and type(instanceof) == "function" and instanceof(object, "IsoThumpable") then
        return true
    end
    if Policy.ask(to, "getRoom") == nil then return false end
    local building = Policy.ask(to, "getBuilding")
    return building == nil or Policy.ask(from, "getBuilding") ~= building
end

function Policy.playersDoor(object, keyed)
    local x, y = Policy.pointOf(object)
    if x == nil then return false end
    if Policy.inPlayerBase(x, y) then return true end
    return keyed == true and Policy.playerNear(x, y)
end

function Policy.unlock(object)
    if object == nil then return false end
    local leaves, unlocked = Policy.leaves(object), 0
    for index = 1, #leaves do
        local leaf = leaves[index]
        if Policy.ask(leaf, "isLockedByKey") == true and type(leaf.setLockedByKey) == "function"
                and pcall(leaf.setLockedByKey, leaf, false) then
            if type(leaf.syncIsoObject) == "function" then pcall(leaf.syncIsoObject, leaf, false, 0, nil, nil) end
            unlocked = unlocked + 1
        end
    end
    return unlocked > 0
end

function Policy.steadyLeaf(object)
    if object == nil or IsoDoor == nil then return object end
    if (tonumber(Policy.callStatic(IsoDoor.getDoubleDoorIndex, object)) or -1) < 1 then return object end
    local first = Policy.callStatic(IsoDoor.getDoubleDoorObject, object, 1)
    if first == nil then return object end
    return first
end

function Policy.doorwaySquares(object)
    local square, opposite = Policy.ask(object, "getSquare"), Policy.ask(object, "getOppositeSquare")
    if square == nil or opposite == nil then return nil end
    local squares = { square, opposite }
    if IsoDoor ~= nil and (tonumber(Policy.callStatic(IsoDoor.getGarageDoorIndex, object)) or -1) > -1 then
        local section = Policy.callStatic(IsoDoor.getGarageDoorFirst, object)

        for _ = 1, 8 do
            if section == nil then break end
            if section ~= object then
                local here, across = Policy.ask(section, "getSquare"), Policy.ask(section, "getOppositeSquare")
                if here ~= nil then squares[#squares + 1] = here end
                if across ~= nil then squares[#squares + 1] = across end
            end
            section = Policy.callStatic(IsoDoor.getGarageDoorNext, section)
        end
        return squares
    end
    if IsoDoor == nil or type(getCell) ~= "function"
            or (tonumber(Policy.callStatic(IsoDoor.getDoubleDoorIndex, object)) or -1) ~= 1 then
        return squares
    end
    local x, y = tonumber(Policy.ask(square, "getX")), tonumber(Policy.ask(square, "getY"))
    local ox, oy = tonumber(Policy.ask(opposite, "getX")), tonumber(Policy.ask(opposite, "getY"))
    local z = tonumber(Policy.ask(square, "getZ")) or 0
    local cell = getCell()
    if x == nil or y == nil or ox == nil or oy == nil or cell == nil then return squares end
    local north = Policy.ask(object, "getNorth") == true
    for step = 1, 3 do
        local dx, dy = 0, -step
        if north then dx, dy = step, 0 end
        local here = cell:getGridSquare(x + dx, y + dy, z)
        local across = cell:getGridSquare(ox + dx, oy + dy, z)
        if here ~= nil then squares[#squares + 1] = here end
        if across ~= nil then squares[#squares + 1] = across end
    end
    return squares
end

function Policy.leaves(object)
    local leaves = { object }
    if IsoDoor ~= nil then
        for index = 1, 4 do
            local leaf = Policy.callStatic(IsoDoor.getDoubleDoorObject, object, index)
            if leaf ~= nil and leaf ~= object then leaves[#leaves + 1] = leaf end
        end
        local section = nil
        if (tonumber(Policy.callStatic(IsoDoor.getGarageDoorIndex, object)) or -1) > -1 then
            section = Policy.callStatic(IsoDoor.getGarageDoorFirst, object)
        end

        for _ = 1, 8 do
            if section == nil then break end
            if section ~= object then leaves[#leaves + 1] = section end
            section = Policy.callStatic(IsoDoor.getGarageDoorNext, section)
        end
    end
    return leaves
end

function Policy.lockLeaves(object)
    local leaves, locked = Policy.leaves(object), 0
    for index = 1, #leaves do
        local leaf = leaves[index]
        if Policy.ask(leaf, "isLockedByKey") ~= true and type(leaf.setLockedByKey) == "function"
                and pcall(leaf.setLockedByKey, leaf, true) then
            if type(leaf.syncIsoObject) == "function" then pcall(leaf.syncIsoObject, leaf, false, 0, nil, nil) end
            locked = locked + 1
        end
    end
    return locked
end

function Policy.edgeBanned(square, nextSquare, now)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.edgeKey) ~= "function" then return false end
    local key = traversal.edgeKey(square, nextSquare)
    if key == nil or type(traversal.edgeBans) ~= "table" then return false end
    return (traversal.edgeBans[key] or 0) > (tonumber(now) or 0)
end

function Policy.refuse(square, nextSquare, now, shell)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or type(traversal.edgeKey) ~= "function" then return false end
    local key = traversal.edgeKey(square, nextSquare)
    if key == nil or type(traversal.edgeBans) ~= "table" then return false end
    traversal.edgeBans[key] = (tonumber(now) or 0) + Policy.settings.lockedBanMs
    if type(traversal.noteBanOrigin) == "function" then
        traversal.noteBanOrigin(key, shell, "door_locked")
    end
    return true
end

return Policy
