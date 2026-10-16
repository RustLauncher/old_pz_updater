require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Shells/ALifeCorpseDresser"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Picked = {
    id = "picked_over",
    KEY = "ProjectALife.PickedOver",
    legacyKey = "ProjectALifeJimmy.PickedOver",
    unseenDistance = 40, heatRadius = 200, heatDecayPerHour = 0.99, liveMs = 2000, pointsMs = 1000,
    cacheCap = 20000, factionCorpseChance = 0.5,
    lootShare = { 0.35, 0.60, 0.85 },
    caps = { doors = { 1, 1, 2 }, windows = { 0, 1, 2 }, blood = { 1, 2, 4 },
        zombieCorpses = { 0, 1, 2 }, factionCorpses = { 0, 1, 1 } },
    heatByTask = { scavenge = 1.0, fortify = 0.5, rest = 0.5 },
    roomWeights = { shed = 0.3, garage = 0.6, storageunit = 0.8 },
    valuableCategories = { FirstAid = true, Medical = true, Ammo = true, Tool = true, ToolWeapon = true,
        Weapon = true, WeaponPart = true, Food = true },
    ready = false, store = nil, cache = {}, cacheCount = 0,
    liveAtMs = -1, liveValue = false, pointsAtMs = -1, points = {},
    metrics = { rolled = 0, marked = 0, lootRemoved = 0, doors = 0, windows = 0, blood = 0,
        zombieCorpses = 0, factionCorpses = 0, dressFailed = 0 },
}
ProjectALife.PickedOver = Picked

function Picked.live()
    local now = Gate.nowMs()
    if now - Picked.liveAtMs < Picked.liveMs and now >= Picked.liveAtMs then return Picked.liveValue end
    Picked.liveAtMs = now
    Picked.liveValue = Picked.ready and Gate.authority() and Gate.on(Picked.id, "PickedOver_Enabled", true)
    return Picked.liveValue
end

function Picked.data()
    if Picked.store ~= nil then return Picked.store end
    if ModData == nil or type(ModData.getOrCreate) ~= "function" then return nil end
    local data = ModData.getOrCreate(Picked.KEY)
    data.buildings = type(data.buildings) == "table" and data.buildings or {}
    data.heat = type(data.heat) == "table" and data.heat or {}
    if data.migrated ~= true then
        data.migrated = true
        Picked.adopt(data)
    end
    Picked.store = data
    return data
end

function Picked.adopt(data)
    if type(ModData.exists) ~= "function" or not ModData.exists(Picked.legacyKey) then return 0 end
    local old = ModData.getOrCreate(Picked.legacyKey)
    local count = 0
    for key, rec in pairs(type(old.buildings) == "table" and old.buildings or {}) do
        if data.buildings[key] == nil and type(rec) == "table" then
            data.buildings[key] = rec
            count = count + 1
        end
    end
    for id, row in pairs(type(old.heat) == "table" and old.heat or {}) do
        if data.heat[id] == nil and type(row) == "table" then data.heat[id] = row end
    end
    return count
end

function Picked.onInit()
    Picked.ready = true
    Picked.store = nil
    Picked.cache, Picked.cacheCount = {}, 0
    Picked.liveAtMs = -1
end

function Picked.defOf(square)
    local building = square:getBuilding()
    if building == nil then return nil end
    return building:getDef()
end

function Picked.bounds(def)
    return { x1 = def:getX(), y1 = def:getY(), x2 = def:getX2(), y2 = def:getY2() }
end

function Picked.keyOf(def)
    return def:getX() .. ":" .. def:getY() .. ":" .. def:getX2() .. ":" .. def:getY2()
end

function Picked.visited(def)
    return type(def.isHasBeenVisited) == "function" and def:isHasBeenVisited() == true
end

function Picked.protected(def, square)
    local b = Picked.bounds(def)
    local center = { x = (b.x1 + b.x2) / 2, y = (b.y1 + b.y2) / 2, z = 0 }
    local policy = ProjectALife.SpawnPolicy
    if policy ~= nil and type(policy.inPlayerBase) == "function" then
        local ok, inside = pcall(policy.inPlayerBase, center, 10)
        if ok and inside then return true end
    end
    if SafeHouse ~= nil and type(SafeHouse.isSafeHouse) == "function" then
        local ok, safe = pcall(SafeHouse.isSafeHouse, square, nil, true)
        if ok and safe ~= nil and safe ~= false then return true end
    end
    local outposts = ProjectALife.OutpostRegistry
    if outposts ~= nil and type(outposts.list) == "function" then
        for _, site in ipairs(outposts.list() or {}) do
            local sb = site.bounds
            if site.state ~= "expired" and type(sb) == "table"
                    and b.x1 <= (tonumber(sb.x2) or 0) + 5 and b.x2 >= (tonumber(sb.x1) or 0) - 5
                    and b.y1 <= (tonumber(sb.y2) or 0) + 5 and b.y2 >= (tonumber(sb.y1) or 0) - 5 then
                return true
            end
        end
    end
    return false
end

function Picked.roomWeight(def)
    local rooms = type(def.getRooms) == "function" and def:getRooms() or nil
    if rooms == nil then return 1 end
    local best
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        local name = room ~= nil and string.lower(tostring(room:getName() or "")) or ""
        local w = Picked.roomWeights[name]
        if w ~= nil and (best == nil or w > best) then best = w end
    end
    return best or 1
end

function Picked.addHeat(id, x, y, factionId, amount)
    local data = Picked.data()
    if data == nil then return end
    local row = data.heat[id] or { n = 0, x = x, y = y, factions = {} }
    row.n = row.n + amount
    if factionId ~= nil then row.factions[factionId] = (row.factions[factionId] or 0) + amount end
    data.heat[id] = row
end

function Picked.gatherHeat()
    if not Picked.live() then return 0 end
    local data = Picked.data()
    local ledger, graph = ProjectALife.SquadLedger, ProjectALife.RoadGraph
    if data == nil or ledger == nil or type(ledger.eachLive) ~= "function" or graph == nil or type(graph.nodes) ~= "table" then return 0 end
    local decay = Picked.heatDecayPerHour
    for id, row in pairs(data.heat) do
        row.n = (tonumber(row.n) or 0) * decay
        for faction, n in pairs(row.factions or {}) do row.factions[faction] = n * decay end
        if row.n < 0.05 then data.heat[id] = nil end
    end
    local added = 0
    ledger.eachLive(function(squad)
        local task = type(squad.task) == "table" and squad.task or nil
        local weight = task ~= nil and Picked.heatByTask[task.kind] or nil
        local node = weight ~= nil and task.dest ~= nil and graph.nodes[task.dest] or nil
        if node ~= nil then
            Picked.addHeat(tostring(task.dest), node.x, node.y, squad.factionId, weight)
            added = added + 1
        end
    end)
    return added
end

function Picked.heatAt(x, y)
    local data = Picked.data()
    local total, byFaction = 0, {}
    local reach = Picked.heatRadius * Picked.heatRadius
    for _, row in pairs(data ~= nil and data.heat or {}) do
        local dx, dy = (tonumber(row.x) or 0) - x, (tonumber(row.y) or 0) - y
        if dx * dx + dy * dy <= reach then
            total = total + (tonumber(row.n) or 0)
            for faction, n in pairs(row.factions or {}) do byFaction[faction] = (byFaction[faction] or 0) + n end
        end
    end
    local best, bestN
    for faction, n in pairs(byFaction) do if bestN == nil or n > bestN then best, bestN = faction, n end end
    return total, best
end

function Picked.anyFaction()
    local ledger = ProjectALife.SquadLedger
    if ledger == nil or type(ledger.eachLive) ~= "function" then return nil end
    local alive = {}
    ledger.eachLive(function(squad) if squad.factionId ~= nil then alive[#alive + 1] = squad.factionId end end)
    if #alive == 0 then return nil end
    return alive[Gate.roll(#alive) + 1]
end

function Picked.roll(def, key)
    local b = Picked.bounds(def)
    local heat, faction = Picked.heatAt((b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2)
    local strength = Gate.number("PickedOver_Strength", 100, 0, 300) / 100
    local baseline = Gate.number("PickedOver_Baseline", 5, 0, 100) / 100
    local heatBonus = math.min(0.6, heat / 50)
    if heatBonus <= 0 and baseline <= 0 then return 0, nil end
    local chance = math.min(0.95, (baseline + heatBonus) * Picked.roomWeight(def) * strength)
    Picked.metrics.rolled = Picked.metrics.rolled + 1
    if Gate.hash01(key .. ":roll") >= chance then return 0, nil end
    local r = Gate.hash01(key .. ":level") + heatBonus * 0.5
    local level = 1
    if r > 1.0 then level = 3 elseif r > 0.55 then level = 2 end
    return level, faction or Picked.anyFaction()
end

function Picked.remember(def, value)
    if Picked.cacheCount >= Picked.cacheCap then Picked.cache, Picked.cacheCount = {}, 0 end
    if Picked.cache[def] == nil then Picked.cacheCount = Picked.cacheCount + 1 end
    Picked.cache[def] = value
end

function Picked.decide(def, square)
    local cached = Picked.cache[def]
    if cached ~= nil then return cached or nil end
    local data = Picked.data()
    if data == nil then return nil end
    local key = Picked.keyOf(def)
    local rec = data.buildings[key]
    if type(rec) ~= "table" then
        if Picked.visited(def) or Picked.protected(def, square) then Picked.remember(def, false) return nil end
        local level, faction = Picked.roll(def, key)
        if level == 0 then Picked.remember(def, false) return nil end
        rec = { level = level, faction = faction, hours = Gate.worldHours(), applied = {} }
        data.buildings[key] = rec
    end
    if type(rec.applied) ~= "table" then rec.applied = {} end
    Picked.remember(def, rec)
    return rec
end

function Picked.valuable(item)
    if item == nil then return false end
    if item:IsFood() or item:IsWeapon() then return true end
    return Picked.valuableCategories[tostring(item:getDisplayCategory() or "")] == true
end

function Picked.squareOf(container)
    local parent = type(container.getParent) == "function" and container:getParent() or nil
    if parent ~= nil and type(parent.getSquare) == "function" then
        local square = parent:getSquare()
        if square ~= nil then return square end
    end
    if type(container.getSourceGrid) == "function" then return container:getSourceGrid() end
    return nil
end

function Picked.onFillContainer(roomName, containerType, container)
    if container == nil or not Picked.live() or type(instanceof) ~= "function" then return 0 end
    local okKind, isContainer = pcall(instanceof, container, "ItemContainer")
    if not okKind or isContainer ~= true then return 0 end
    local square = Picked.squareOf(container)
    local def = square ~= nil and Picked.defOf(square) or nil
    local rec = def ~= nil and Picked.decide(def, square) or nil
    if rec == nil then return 0 end
    local share = Picked.lootShare[rec.level] or 0.5
    local list = container:getItems()
    local items = {}
    for i = 0, list:size() - 1 do items[#items + 1] = list:get(i) end
    local removed = 0
    for _, item in ipairs(items) do
        if Picked.valuable(item) and Gate.chance(share) then
            container:Remove(item)
            removed = removed + 1
        end
    end
    Picked.metrics.lootRemoved = Picked.metrics.lootRemoved + removed
    return removed
end

function Picked.playersFar(square)
    local now = Gate.nowMs()
    if now - Picked.pointsAtMs >= Picked.pointsMs or now < Picked.pointsAtMs then
        Picked.pointsAtMs = now
        Picked.points = Gate.playerPoints()
    end
    return Gate.nearestPlayer(square:getX(), square:getY(), Picked.points) >= Picked.unseenDistance
end

function Picked.capOf(rec, what) return (Picked.caps[what] or {})[rec.level] or 0 end
function Picked.room(rec, what) return (rec.applied[what] or 0) < Picked.capOf(rec, what) end
function Picked.count(rec, what)
    rec.applied[what] = (rec.applied[what] or 0) + 1
    Picked.metrics[what] = (Picked.metrics[what] or 0) + 1
end

function Picked.capsReached(rec)
    for what in pairs(Picked.caps) do
        if Picked.room(rec, what) then return false end
    end
    return true
end

function Picked.openDoor(door, square)
    if door:IsOpen() or (type(door.isBarricaded) == "function" and door:isBarricaded()) then return false end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.toggleGroup) == "function" then
        local ok, grouped = pcall(traversal.toggleGroup, door)
        if ok and grouped then return true end
    end
    door:ToggleDoorSilent()
    if traversal ~= nil and type(traversal.settleLeaf) == "function" then
        pcall(traversal.settleLeaf, door, square)
    elseif type(door.syncIsoObject) == "function" then
        pcall(door.syncIsoObject, door, false, 1, nil, nil)
    end
    return door:IsOpen() == true
end

function Picked.smashWindow(window)
    if type(window.isSmashed) ~= "function" or window:isSmashed() then return false end
    if type(window.setSmashed) ~= "function" then return false end
    window:setSmashed(true)
    if type(window.addBrokenGlass) == "function" then window:addBrokenGlass(true) end
    if Gate.dedicated() and type(window.transmitUpdatedSpriteToClients) == "function" then
        window:transmitUpdatedSpriteToClients()
    end
    return true
end

function Picked.factionCorpse(square, factionId)
    local dresser = ProjectALife.CorpseDresser
    local body = dresser.plain(square, 10)
    if body == nil then return false end
    local seed = "picked:" .. square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
    if not dresser.dress(body, factionId, seed) then Picked.metrics.dressFailed = Picked.metrics.dressFailed + 1 end
    return true
end

function Picked.openings(square, rec, visuals)
    if not visuals then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if instanceof(object, "IsoDoor") and Picked.room(rec, "doors") then
            if Picked.openDoor(object, square) then
                Picked.count(rec, "doors")
                if Picked.room(rec, "blood") and ProjectALife.CorpseDresser.blood(square, 10) then Picked.count(rec, "blood") end
            end
        elseif instanceof(object, "IsoWindow") and Picked.room(rec, "windows") then
            if Picked.smashWindow(object) then Picked.count(rec, "windows") end
        end
    end
end

function Picked.applySquare(square, rec, force)
    if rec == nil or rec.done then return end
    if Picked.capsReached(rec) then rec.done = true return end
    if not force and not Picked.playersFar(square) then return end
    local visuals = Gate.flag("PickedOver_Visuals", true)
    pcall(Picked.openings, square, rec, visuals)
    if square:getRoom() == nil or not square:isFree(false) then return end
    local dresser = ProjectALife.CorpseDresser
    if Gate.flag("PickedOver_FactionCorpses", true) and Picked.room(rec, "factionCorpses")
            and rec.faction ~= nil and Gate.chance(Picked.factionCorpseChance) then
        if Picked.factionCorpse(square, rec.faction) then
            Picked.count(rec, "factionCorpses")
            if Picked.room(rec, "blood") and dresser.blood(square, 16) then Picked.count(rec, "blood") end
            return
        end
    end
    if Gate.flag("PickedOver_ZombieCorpses", true) and Picked.room(rec, "zombieCorpses") and Gate.roll(6) == 0 then
        if dresser.plain(square, 6) ~= nil then Picked.count(rec, "zombieCorpses") end
    elseif visuals and Picked.room(rec, "blood") and Gate.roll(10) == 0 then
        if dresser.blood(square, 8) then Picked.count(rec, "blood") end
    end
end

function Picked.onLoadSquare(square)
    if square == nil or not Picked.live() then return end
    local def = Picked.defOf(square)
    if def == nil then return end
    local rec = Picked.decide(def, square)
    if rec == nil or rec.done then return end
    if Picked.visited(def) then rec.done = true return end
    Picked.applySquare(square, rec, false)
end

function Picked.forEachSquare(def, visit)
    local b = Picked.bounds(def)
    local cell = getCell()
    for z = 0, 7 do
        for x = b.x1, b.x2 do
            for y = b.y1, b.y2 do
                local square = cell:getGridSquare(x, y, z)
                if square ~= nil and Picked.defOf(square) == def then visit(square) end
            end
        end
    end
end

function Picked.debug(player, action, level)
    local square = player ~= nil and player:getCurrentSquare() or nil
    local def = square ~= nil and Picked.defOf(square) or nil
    local data = Picked.data()
    if def == nil or data == nil then return { ok = false, reason = "not_in_building" } end
    local key = Picked.keyOf(def)
    if action == "mark" then
        local b = Picked.bounds(def)
        local _, faction = Picked.heatAt((b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2)
        local rec = { level = math.max(1, math.min(3, math.floor(tonumber(level) or 3))),
            faction = faction or Picked.anyFaction(), hours = Gate.worldHours(), applied = {}, debug = true }
        data.buildings[key] = rec
        Picked.remember(def, rec)
        Picked.metrics.marked = Picked.metrics.marked + 1
        Picked.forEachSquare(def, function(sq) Picked.applySquare(sq, rec, true) end)
    elseif action == "clear" then
        data.buildings[key] = nil
        Picked.cache[def] = nil
    end
    local rec = data.buildings[key]
    local applied = {}
    for what, n in pairs(type(rec) == "table" and rec.applied or {}) do applied[#applied + 1] = what .. "=" .. tostring(n) end
    table.sort(applied)
    return { ok = true, building = key, level = type(rec) == "table" and rec.level or 0,
        faction = type(rec) == "table" and rec.faction or nil, applied = table.concat(applied, " ") }
end

if type(Events) == "table" then
    if Events.OnInitGlobalModData ~= nil then Events.OnInitGlobalModData.Add(Picked.onInit) end
    if Events.LoadGridsquare ~= nil then
        Events.LoadGridsquare.Add(function(square) pcall(Picked.onLoadSquare, square) end)
    end
    if Events.OnFillContainer ~= nil then
        Events.OnFillContainer.Add(function(roomName, containerType, container)
            pcall(Picked.onFillContainer, roomName, containerType, container)
        end)
    end
    if Events.EveryHours ~= nil then Events.EveryHours.Add(function() pcall(Picked.gatherHeat) end) end
end

return Picked
