require "ProjectALife/Core/ALifePersistence"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/Activities/ALifeActivityCatalog"
require "ProjectALife/Activities/ALifeActivityPlanner"
require "ProjectALife/Loot/ALifeStashRoom"
require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Planner = ProjectALife.ActivityPlanner

local Havens = {
    settings = {
        maxBases = 6, chance = 25, minMembers = 2, minAgeHours = 12, clearTiles = 45, spacingTiles = 150,
        playerBaseTiles = 60, staleHours = 72, tombstoneHours = 48, returnHours = 8, homeHours = 3, pruneHours = 24 * 30, stashLimit = 400,
        probeRadii = { 6, 13, 20, 27, 34, 41, 48 }, probeAngles = 8, depotScan = 400, minArea = 20, maxArea = 600,
    },
    seen = {},
    tried = {},
    cursor = 0,
    adapters = {},
    metrics = { founded = 0, refused = 0, abandoned = 0, visits = 0 },
}
ProjectALife.Havens = Havens

function Havens.store()
    local persistence = ProjectALife.Persistence
    local value = persistence ~= nil and persistence.bucket("havens", { byId = {}, byBuilding = {}, tombstones = {}, seq = 0 }) or nil
    if type(value) ~= "table" then
        Havens.fallback = Havens.fallback or { byId = {}, byBuilding = {}, tombstones = {}, seq = 0 }
        value = Havens.fallback
    end
    value.byId = type(value.byId) == "table" and value.byId or {}
    value.byBuilding = type(value.byBuilding) == "table" and value.byBuilding or {}
    value.tombstones = type(value.tombstones) == "table" and value.tombstones or {}
    value.seq = tonumber(value.seq) or 0
    return value
end

function Havens.dirty()
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
end

function Havens.reset()
    Havens.seen, Havens.tried, Havens.cursor = {}, {}, 0
    Havens.fallback = nil
    Havens.metrics = { founded = 0, refused = 0, abandoned = 0, visits = 0 }
end

function Havens.option(name, default)
    local settings = ProjectALife.Settings
    local current = settings ~= nil and type(settings.current) == "table" and settings.current or {}
    local value = current[name]
    if value == nil then return default end
    return value
end

function Havens.enabled()
    local catalog = ProjectALife.ActivityCatalog
    if catalog == nil or type(catalog.enabled) ~= "function" or not catalog.enabled() then return false end
    return Havens.option("activitiesBases", true) == true
end

function Havens.hours()
    if type(Havens.adapters.hours) == "function" then return Havens.adapters.hours() end
    local service = ProjectALife.ActivityService
    if service ~= nil and type(service.worldHours) == "function" then return service.worldHours() end
    return 0
end

function Havens.of(id)
    if id == nil then return nil end
    local haven = Havens.store().byId[id]
    if type(haven) == "table" and haven.state == "active" then return haven end
    return nil
end

function Havens.activeList()
    local list = {}
    for _, haven in pairs(Havens.store().byId) do
        if type(haven) == "table" and haven.state == "active" then list[#list + 1] = haven end
    end
    table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return list
end

function Havens.takenAt(x, y, margin)
    margin = tonumber(margin) or 0
    for _, haven in ipairs(Havens.activeList()) do
        local b = haven.bounds
        if type(b) == "table" and x >= b.x1 - margin and x <= b.x2 + margin and y >= b.y1 - margin and y <= b.y2 + margin then
            return haven
        end
    end
    return nil
end

function Havens.near(x, y, radius)
    for _, haven in ipairs(Havens.activeList()) do
        if (haven.x - x) ^ 2 + (haven.y - y) ^ 2 <= radius * radius then return haven end
    end
    return nil
end

function Havens.playerNear(x, y, radius)
    local locator = ProjectALife.PlayerLocator
    local players = locator ~= nil and type(locator.list) == "function" and locator.list() or {}
    for _, player in ipairs(players) do
        if type(player.getX) == "function" and type(player.getY) == "function" then
            local dx, dy = player:getX() - x, player:getY() - y
            if dx * dx + dy * dy <= radius * radius then return true end
        end
    end
    return false
end

function Havens.squareAt(x, y, z)
    if type(Havens.adapters.square) == "function" then return Havens.adapters.square(x, y, z) end
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

function Havens.boundsOf(building)
    if building == nil or type(building.getDef) ~= "function" then return nil end
    local def = building:getDef()
    if def == nil then return nil end
    local x1, y1, x2, y2 = tonumber(def:getX()), tonumber(def:getY()), tonumber(def:getX2()), tonumber(def:getY2())
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return nil end
    return { x1 = math.floor(x1), y1 = math.floor(y1), x2 = math.floor(x2) - 1, y2 = math.floor(y2) - 1 }
end

function Havens.keyOf(bounds)
    return bounds.x1 .. ":" .. bounds.y1
end

function Havens.depotIn(bounds, z)
    local budget = Havens.settings.depotScan
    for x = bounds.x1, bounds.x2 do
        for y = bounds.y1, bounds.y2 do
            budget = budget - 1
            if budget < 0 then return nil end
            local square = Havens.squareAt(x, y, z)
            local objects = square ~= nil and type(square.getObjects) == "function" and square:getObjects() or nil
            local size = objects ~= nil and tonumber(objects:size()) or 0
            for index = 0, size - 1 do
                local object = objects:get(index)
                local container = object ~= nil and type(object.getContainer) == "function" and object:getContainer() or nil
                if container ~= nil then return { x = x + 0.5, y = y + 0.5, z = z } end
            end
        end
    end
    return nil
end

function Havens.containerAt(depot)
    local square = depot ~= nil and Havens.squareAt(depot.x, depot.y, depot.z) or nil
    local objects = square ~= nil and type(square.getObjects) == "function" and square:getObjects() or nil
    local size = objects ~= nil and tonumber(objects:size()) or 0
    for index = 0, size - 1 do
        local object = objects:get(index)
        local container = object ~= nil and type(object.getContainer) == "function" and object:getContainer() or nil
        if container ~= nil then return container end
    end
    return nil
end

function Havens.excluded(bounds, center, hours, store)
    local settings = Havens.settings
    local key = Havens.keyOf(bounds)
    if store.byBuilding[key] ~= nil then return "taken" end
    if (tonumber(store.tombstones[key]) or -math.huge) > hours then return "tombstone" end
    local spawn = ProjectALife.SpawnPolicy
    if spawn ~= nil and type(spawn.inPlayerBase) == "function"
            and spawn.inPlayerBase({ x = center.x, y = center.y, z = 0 }, settings.playerBaseTiles) then return "player_base" end
    local heat = ProjectALife.BaseHeat
    if heat ~= nil and type(heat.anchorOverlaps) == "function"
            and heat.anchorOverlaps(bounds.x1 - 8, bounds.y1 - 8, bounds.x2 + 8, bounds.y2 + 8) then return "player_base" end
    if SafeHouse ~= nil and type(SafeHouse.getSafeHouse) == "function" then
        local square = Havens.squareAt(center.x, center.y, 0)
        if square ~= nil and SafeHouse.getSafeHouse(square) ~= nil then return "safehouse" end
    end
    if Havens.near(center.x, center.y, settings.spacingTiles) ~= nil then return "spacing" end
    local sites = ProjectALife.OutpostRegistry
    if sites ~= nil and type(sites.list) == "function" then
        for _, site in ipairs(sites.list()) do
            if type(site) == "table" and site.state ~= "expired" and tonumber(site.x) ~= nil
                    and (site.x - center.x) ^ 2 + (site.y - center.y) ^ 2 <= 6400 then return "outpost" end
        end
    end
    if Havens.playerNear(center.x, center.y, Havens.option("activitiesBaseClearTiles", settings.clearTiles)) then return "player_near" end
    return nil
end

function Havens.candidates(origin)
    local settings, seen, list = Havens.settings, {}, {}
    for _, radius in ipairs(settings.probeRadii) do
        for step = 0, settings.probeAngles - 1 do
            local angle = step * 2 * math.pi / settings.probeAngles
            local square = Havens.squareAt(origin.x + math.cos(angle) * radius, origin.y + math.sin(angle) * radius, 0)
            local building = square ~= nil and type(square.getBuilding) == "function" and square:getBuilding() or nil
            local bounds = building ~= nil and Havens.boundsOf(building) or nil
            if bounds ~= nil then
                local key = Havens.keyOf(bounds)
                if not seen[key] then
                    seen[key] = true
                    local area = (bounds.x2 - bounds.x1 + 1) * (bounds.y2 - bounds.y1 + 1)
                    if area >= settings.minArea and area <= settings.maxArea then
                        list[#list + 1] = { bounds = bounds, area = area, radius = radius,
                            center = { x = (bounds.x1 + bounds.x2) / 2, y = (bounds.y1 + bounds.y2) / 2 } }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.radius < b.radius end)
    return list
end

function Havens.livingMembers(members)
    local list = {}
    for _, record in ipairs(members) do
        if type(record) == "table" and record.lifecycle == "active" and type(record.memory) == "table" then
            list[#list + 1] = record
        end
    end
    return list
end

function Havens.eligibleGroup(members)
    if #members < Havens.settings.minMembers then return false end
    local catalog = ProjectALife.Catalog
    local modules = ProjectALife.ModuleRegistry
    for _, record in ipairs(members) do
        local memory = record.memory
        if modules ~= nil and type(modules.allows) == "function" and not modules.allows(record, "home") then return false end
        if memory.havenId ~= nil or memory.natural ~= true or memory.outpostId ~= nil or memory.admin ~= nil
                or memory.visit ~= nil or memory.guest ~= nil or memory.activityId == "hold" or memory.garrisonPost ~= nil then
            return false
        end
        local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(record.factionId) or nil
        if type(faction) == "table" and type(faction.spawn) == "table" and faction.spawn.havens == false then return false end
    end
    return true
end

function Havens.found(groupId, members, hours)
    local store = Havens.store()
    local origin = members[1].worldPosition
    if type(origin) ~= "table" then return nil, "no_position" end
    for _, candidate in ipairs(Havens.candidates(origin)) do
        local why = Havens.excluded(candidate.bounds, candidate.center, hours, store)
        if why == nil then
            local depot = Havens.depotIn(candidate.bounds, 0)
            if depot ~= nil then
                store.seq = store.seq + 1
                local id = "haven:" .. store.seq
                local haven = { id = id, kind = "house", state = "active", x = candidate.center.x, y = candidate.center.y, z = 0,
                    buildingKey = Havens.keyOf(candidate.bounds), bounds = candidate.bounds, depot = depot,
                    foundedHours = hours, lastHomeHours = hours, stock = { items = 0 }, groupId = groupId }
                store.byId[id], store.byBuilding[haven.buildingKey] = haven, id
                for _, record in ipairs(members) do
                    local registry = ProjectALife.ActorRegistry
                    registry.update(record.uid, record.revision, function(entry)
                        entry.memory = type(entry.memory) == "table" and entry.memory or {}
                        entry.memory.havenId = id
                        entry.memory.supplyDepot = { x = depot.x, y = depot.y, z = depot.z }
                    end)
                end
                Havens.metrics.founded = Havens.metrics.founded + 1
                Havens.dirty()
                return haven
            end
        else
            Havens.metrics.refused = Havens.metrics.refused + 1
        end
    end
    return Havens.foundCamp(groupId, members, hours, store, origin)
end

function Havens.foundCamp(groupId, members, hours, store, origin)
    local service = ProjectALife.ActivityService
    local spot = service ~= nil and type(service.campSpot) == "function" and service.campSpot(origin) or nil
    if spot == nil then return nil, "no_site" end
    local x, y = math.floor(spot.x), math.floor(spot.y)
    local bounds = { x1 = x - 3, y1 = y - 3, x2 = x + 3, y2 = y + 3 }
    if Havens.excluded(bounds, { x = spot.x, y = spot.y }, hours, store) ~= nil then return nil, "no_site" end
    store.seq = store.seq + 1
    local id = "haven:" .. store.seq
    local haven = { id = id, kind = "camp", state = "active", x = spot.x, y = spot.y, z = spot.z or 0,
        buildingKey = Havens.keyOf(bounds), bounds = bounds, depot = { x = spot.x, y = spot.y, z = spot.z or 0 },
        foundedHours = hours, lastHomeHours = hours, stock = { items = 0 }, groupId = groupId }
    store.byId[id], store.byBuilding[haven.buildingKey] = haven, id
    for _, record in ipairs(members) do
        ProjectALife.ActorRegistry.update(record.uid, record.revision, function(entry)
            entry.memory = type(entry.memory) == "table" and entry.memory or {}
            entry.memory.havenId = id
            entry.memory.supplyDepot = { x = haven.depot.x, y = haven.depot.y, z = haven.depot.z }
        end)
    end
    Havens.metrics.founded = Havens.metrics.founded + 1
    Havens.dirty()
    return haven
end

function Havens.consider(groupId, members)
    if not Havens.enabled() or type(members) ~= "table" then return nil end
    local hours = Havens.hours()
    local alive = Havens.livingMembers(members)
    if Havens.seen[groupId] == nil then Havens.seen[groupId] = hours end
    if hours - Havens.seen[groupId] < Havens.settings.minAgeHours then return nil end
    if not Havens.eligibleGroup(alive) then return nil end
    local day = math.floor(hours / 24)
    if Havens.tried[groupId] == day then return nil end
    Havens.tried[groupId] = day
    if #Havens.activeList() >= Havens.option("activitiesMaxBases", Havens.settings.maxBases) then return nil end
    if Planner.stableRoll(tostring(groupId) .. ":haven:" .. day) >= Havens.option("activitiesBaseChance", Havens.settings.chance) / 100 then
        return nil
    end
    return Havens.found(groupId, alive, hours)
end

function Havens.contextFor(members, hours)
    local memory = members[1] ~= nil and members[1].memory or nil
    local haven = type(memory) == "table" and Havens.of(memory.havenId) or nil
    if haven == nil then return nil end
    local since = hours - (tonumber(haven.lastHomeHours) or hours)
    return { havenId = haven.id, away = since, returnHours = Havens.option("activitiesBaseReturnHours", Havens.settings.returnHours),
        atHome = since < Havens.settings.homeHours, homeCovers = false }
end

function Havens.arrive(haven, hours, deposited)
    haven.lastHomeHours = hours
    haven.stock.items = (tonumber(haven.stock.items) or 0) + (tonumber(deposited) or 0)
    Havens.metrics.visits = Havens.metrics.visits + 1
    Havens.dirty()
end

function Havens.visited(members)
    local registry = ProjectALife.ActorRegistry
    if type(members) ~= "table" or registry == nil then return false end
    for _, record in ipairs(members) do
        local memory = type(record) == "table" and record.memory or nil
        if type(memory) == "table" and memory.havenVisit ~= nil then
            local haven = Havens.of(memory.havenId)
            if haven ~= nil then Havens.arrive(haven, Havens.hours(), 0) end
            registry.update(record.uid, record.revision, function(entry)
                if type(entry.memory) == "table" then entry.memory.havenVisit = nil end
            end)
            return haven ~= nil
        end
    end
    return false
end

function Havens.playerKey(player)
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.playerKey) == "function" then
        local key = reputation.playerKey(player)
        if key ~= nil then return tostring(key) end
    end
    return nil
end

function Havens.placeName(haven)
    local door = ProjectALife.SafehouseDoor
    local town = nil
    if door ~= nil and type(door.regionAt) == "function" then
        local _, name = door.regionAt(haven.x, haven.y)
        town = name
    end
    return type(town) == "string" and town or nil
end

Havens.kindNames = { camp = "Camp", house = "House", outpost = "Outpost", post = "Post", place = "Home" }
Havens.reach = { stone = 30, short = 100, far = 250, hike = 600 }

function Havens.pointOk(point)
    return type(point) == "table" and tonumber(point.x) ~= nil and tonumber(point.y) ~= nil
end

function Havens.siteOk(site)
    if not Havens.pointOk(site) then return false end
    local state = site.state
    return state ~= "expired" and state ~= "proposed" and state ~= "build_failed"
end

function Havens.nearestSite(record, sites)
    if sites == nil or type(sites.list) ~= "function" or record.factionId == nil then return nil end
    local at = type(record.worldPosition) == "table" and record.worldPosition or nil
    local best, bestSq = nil, math.huge
    for _, site in ipairs(sites.list()) do
        if Havens.siteOk(site) and site.factionId == record.factionId and site.hostileToPlayers ~= true then
            local dx = at ~= nil and tonumber(at.x) ~= nil and (site.x - at.x) or 0
            local dy = at ~= nil and tonumber(at.y) ~= nil and (site.y - at.y) or 0
            local sq = dx * dx + dy * dy
            if sq < bestSq then best, bestSq = site, sq end
        end
    end
    return best
end

function Havens.homeOf(record)
    local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
    if memory == nil then return nil end
    local haven = Havens.of(memory.havenId) or Havens.havenOfRecord(record)
    if haven ~= nil then
        local kind = "house"
        if haven.kind == "camp" then kind = "camp" end
        return { kind = kind, x = haven.x, y = haven.y, haven = haven }
    end
    local sites = ProjectALife.OutpostRegistry
    if memory.outpostId ~= nil and sites ~= nil and type(sites.read) == "function" then
        local site = sites.read(memory.outpostId)
        if Havens.siteOk(site) then return { kind = "outpost", x = site.x, y = site.y } end
    end
    if Havens.pointOk(memory.garrisonPost) then return { kind = "post", x = memory.garrisonPost.x, y = memory.garrisonPost.y } end
    if Havens.pointOk(memory.home) then return { kind = "place", x = memory.home.x, y = memory.home.y } end
    local site = Havens.nearestSite(record, sites)
    if site ~= nil then return { kind = "outpost", x = site.x, y = site.y } end
    return nil
end

function Havens.heading(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    local north, east = dy < 0, dx > 0
    if ay * 2.4 < ax then
        if east then return "east" end
        return "west"
    end
    if ax * 2.4 < ay then
        if north then return "north" end
        return "south"
    end
    if north then
        if east then return "northeast" end
        return "northwest"
    end
    if east then return "southeast" end
    return "southwest"
end

function Havens.whereText(player, home)
    if player == nil or type(player.getX) ~= "function" or type(player.getY) ~= "function" then
        return "somewhere not far from here"
    end
    local dx, dy = home.x - player:getX(), home.y - player:getY()
    local distance = math.sqrt(dx * dx + dy * dy)
    local reach = Havens.reach
    if distance < reach.stone then return "just a stone's throw from here" end
    local heading = Havens.heading(dx, dy)
    if distance < reach.short then return "a short walk " .. heading .. " of here" end
    if distance < reach.far then return "a good ways " .. heading .. " of here" end
    if distance < reach.hike then return "a long hike " .. heading .. " of here" end
    return "a day's walk or more " .. heading .. " of here"
end

function Havens.homeAnswer(player, record, stance)
    local home = Havens.homeOf(record)
    if home == nil then
        return { pool = "HOME_NONE", vars = {}, text = "No place of my own, we just move around" }
    end
    if stance == "careful" or stance == "hostile" then
        return { pool = "HOME_REFUSE", vars = {}, text = "Where I sleep? Not telling you that" }
    end
    local haven = home.haven
    if haven ~= nil then
        local key = Havens.playerKey(player)
        haven.knownBy = type(haven.knownBy) == "table" and haven.knownBy or {}
        local count = 0
        for _ in pairs(haven.knownBy) do count = count + 1 end
        if key ~= nil and haven.knownBy[key] == nil and count < 8 then haven.knownBy[key] = Havens.hours() end
        Havens.dirty()
    end
    local place = Havens.placeName(home)
    local where = Havens.whereText(player, home)
    local label = Havens.kindNames[home.kind] or "Home"
    local marker = { x = math.floor(home.x), y = math.floor(home.y), name = label }
    if place ~= nil then marker.name = label .. " near " .. place end
    return { pool = "HOME_TELL", vars = { kind = home.kind, where = where }, marker = marker,
        text = "Our " .. home.kind .. " is " .. where .. ", I marked it on your map for you" }
end

function Havens.tellHome(player, record, stance)
    local answer = Havens.homeAnswer(player, record, stance)
    return answer.text, answer.marker
end

function Havens.annotate(marker, record, shell)
    if type(marker) ~= "table" then return marker end
    if type(record) == "table" then
        marker.uid = record.uid
        local catalog = ProjectALife.Catalog
        local faction = nil
        if catalog ~= nil and type(catalog.faction) == "function" then faction = catalog.faction(record.factionId) end
        if type(faction) == "table" and type(faction.general) == "table" and type(faction.general.name) == "string" then
            marker.faction = faction.general.name
        end
    end
    if shell ~= nil and type(shell.getDescriptor) == "function" then
        local descriptor = shell:getDescriptor()
        if descriptor ~= nil and type(descriptor.getForename) == "function" then
            local parts = {}
            local forename = descriptor:getForename()
            if forename ~= nil and forename ~= "" then parts[#parts + 1] = forename end
            if type(descriptor.getSurname) == "function" then
                local surname = descriptor:getSurname()
                if surname ~= nil and surname ~= "" then parts[#parts + 1] = surname end
            end
            if #parts > 0 then marker.npc = table.concat(parts, " ") end
        end
    end
    return marker
end

function Havens.sendMarker(player, marker)
    if type(isServer) == "function" and isServer() == true then
        if type(sendServerCommand) == "function" then pcall(sendServerCommand, player, "ProjectALife", "havenMarker", marker) end
        return true
    end
    local client = ProjectALife.SafehouseClient
    if client ~= nil and type(client.mark) == "function" then
        client.mark(marker, player)
        return true
    end
    return false
end

Havens.coldGreetings = {
    "Oh... you again",
    "You're back, huh- hands where I can see 'em",
}

Havens.warmGreetings = {
    "There you are! Been wondering where you got to",
    "Sit down, you look wrecked, c'mon",
}

Havens.greetings = {
    "Hey, look who's back",
    "Hey, it's you, glad you made it back",
    "You found us, huh, good for you",
}

function Havens.greet(haven, now)
    if type(haven.knownBy) ~= "table" then return 0 end
    local locator = ProjectALife.PlayerLocator
    local players = locator ~= nil and type(locator.list) == "function" and locator.list() or {}
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    if talk == nil or type(talk.shellFor) ~= "function" or speech == nil or type(speech.say) ~= "function" then return 0 end
    haven.greeted = type(haven.greeted) == "table" and haven.greeted or {}
    for _, player in ipairs(players) do
        local key = Havens.playerKey(player)
        if key ~= nil and haven.knownBy[key] ~= nil and now - (tonumber(haven.greeted[key]) or -math.huge) >= 24
                and type(player.getX) == "function" and type(player.getY) == "function"
                and (player:getX() - haven.depot.x) ^ 2 + (player:getY() - haven.depot.y) ^ 2 <= 400 then
            local said = 0
            ProjectALife.ActorRegistry.each(function(record)
                if said == 0 and type(record.memory) == "table" and record.memory.havenId == haven.id
                        and record.lifecycle == "active" and record.activity ~= "combat" then
                    local shell = talk.shellFor(record.uid)
                    if shell ~= nil and type(shell.getX) == "function"
                            and (shell:getX() - player:getX()) ^ 2 + (shell:getY() - player:getY()) ^ 2 <= 400 then
                        local pool = Havens.greetings
                        local opinion = ProjectALife.NpcOpinion
                        if opinion ~= nil and type(opinion.greetTone) == "function" then
                            local tone = opinion.greetTone(record, player)
                            if tone == "cold" then pool = Havens.coldGreetings elseif tone == "warm" then pool = Havens.warmGreetings end
                        end
                        local line = pool[1 + (math.floor(now) + #key) % #pool]
                        if speech.say(shell, line, { face = player }) then said = 1 end
                    end
                end
                return said == 1
            end)
            if said == 1 then
                haven.greeted[key] = now
                Havens.dirty()
                return 1
            end
        end
    end
    return 0
end

function Havens.release(id)
    local registry = ProjectALife.ActorRegistry
    registry.each(function(record)
        if type(record.memory) == "table" and record.memory.havenId == id then
            registry.update(record.uid, record.revision, function(entry)
                entry.memory.havenId, entry.memory.supplyDepot = nil, nil
            end)
        end
    end)
end

function Havens.abandon(id, reason, forever)
    local store = Havens.store()
    local haven = store.byId[id]
    if type(haven) ~= "table" or haven.state ~= "active" then return false end
    local hours = Havens.hours()
    haven.state, haven.reason, haven.endedHours = "abandoned", reason, hours
    store.byBuilding[haven.buildingKey] = nil
    store.tombstones[haven.buildingKey] = forever == true and 1e12 or hours + Havens.settings.tombstoneHours
    Havens.release(id)
    Havens.metrics.abandoned = Havens.metrics.abandoned + 1
    Havens.dirty()
    return true
end

function Havens.havenOfRecord(record)
    if type(record) ~= "table" then return nil end
    if record.havenId ~= nil then
        local direct = Havens.of(record.havenId)
        if direct ~= nil then return direct end
    end
    local group = record.adoptedGroupId
    if group == nil then return nil end
    for _, haven in pairs(Havens.store().byId) do
        if type(haven) == "table" and haven.state == "active" and haven.groupId == group then return haven end
    end
    return nil
end

function Havens.stashOf(haven)
    if type(haven) ~= "table" or type(haven.stock) ~= "table" then return nil end
    local stash = haven.stock.stash
    if type(stash) ~= "table" then
        stash = { items = {} }
        haven.stock.stash = stash
    end
    if type(stash.items) ~= "table" then stash.items = {} end
    return stash
end

function Havens.stashFor(record)
    local haven = Havens.havenOfRecord(record)
    if haven == nil or type(haven.depot) ~= "table" then return nil end
    local container = Havens.containerAt(haven.depot)
    if container ~= nil then
        Havens.flushStash(haven, container)
        return container
    end
    local stash = Havens.stashOf(haven)
    if stash == nil or #stash.items >= Havens.settings.stashLimit then return nil end
    Havens.dirty()
    return stash
end

function Havens.flushStash(haven, container)
    local stash = type(haven) == "table" and type(haven.stock) == "table" and haven.stock.stash or nil
    if type(stash) ~= "table" or type(stash.items) ~= "table" or #stash.items == 0 or container == nil
            or type(container.AddItem) ~= "function" then return 0 end
    local state = ProjectALife.ShellState
    if state == nil or type(state.createItem) ~= "function" then return 0 end
    local moved = 0
    for index = #stash.items, 1, -1 do
        local item = state.createItem(stash.items[index])
        if item ~= nil then
            local placed, why = ProjectALife.StashRoom.place(container, item)
            if placed then
                table.remove(stash.items, index)
                moved = moved + 1
            elseif why == "full" then
                break
            end
        else
            table.remove(stash.items, index)
        end
    end
    if moved > 0 then
        haven.stock.items = (tonumber(haven.stock.items) or 0) + moved
        Havens.dirty()
    end
    return moved
end

function Havens.crewAlive(id)
    local found = false
    ProjectALife.ActorRegistry.each(function(record)
        if type(record.memory) == "table" and record.memory.havenId == id and record.lifecycle ~= "dead" then
            found = true
            return true
        end
        return false
    end)
    return found
end

function Havens.prune(store, hours)
    local removed = 0
    for id, haven in pairs(store.byId) do
        if type(haven) ~= "table" or (haven.state ~= "active"
                and (tonumber(haven.endedHours) or 0) + Havens.settings.pruneHours < hours) then
            store.byId[id] = nil
            removed = removed + 1
        end
    end
    for key, expires in pairs(store.tombstones) do
        local value = tonumber(expires)
        if value == nil or (value <= hours and value < 1e11) then
            store.tombstones[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then Havens.dirty() end
    return removed
end

function Havens.tick()
    if not Havens.enabled() then return 0 end
    Havens.prune(Havens.store(), Havens.hours())
    local list = Havens.activeList()
    local limit = Havens.option("activitiesMaxBases", Havens.settings.maxBases)
    if #list > limit then
        table.sort(list, function(a, b) return a.foundedHours < b.foundedHours end)
        Havens.abandon(list[1].id, "cap")
        return 1
    end
    if #list == 0 then return 0 end
    Havens.cursor = (Havens.cursor % #list) + 1
    local haven, hours = list[Havens.cursor], Havens.hours()
    local b = haven.bounds
    local heat = ProjectALife.BaseHeat
    local spawn = ProjectALife.SpawnPolicy
    if (heat ~= nil and type(heat.anchorOverlaps) == "function" and heat.anchorOverlaps(b.x1, b.y1, b.x2, b.y2))
            or (spawn ~= nil and type(spawn.inPlayerBase) == "function" and spawn.inPlayerBase({ x = haven.x, y = haven.y, z = 0 }, 0)) then
        Havens.abandon(haven.id, "player_took_it", true)
        return 1
    end
    if hours - (tonumber(haven.lastHomeHours) or hours) > Havens.settings.staleHours then
        Havens.abandon(haven.id, "stale")
        return 1
    end
    if not Havens.crewAlive(haven.id) then
        Havens.abandon(haven.id, "crew_gone")
        return 1
    end
    local pending = type(haven.stock) == "table" and type(haven.stock.stash) == "table" and haven.stock.stash.items or nil
    if type(pending) == "table" and #pending > 0 then
        Havens.flushStash(haven, Havens.containerAt(haven.depot))
    end
    local camp = ProjectALife.CampLife
    if camp ~= nil and type(camp.offline) == "function" then camp.offline(haven, hours) end
    return Havens.greet(haven, hours)
end

if ProjectALife.ModuleRegistry ~= nil and type(ProjectALife.ModuleRegistry.register) == "function"
        and ProjectALife.ModuleRegistry.modules.home == nil then
    ProjectALife.ModuleRegistry.register({
        id = "home",
        label = "Home base",
        summary = "May keep a house or camp that the crew returns to between trips. Off: this member's crew never founds one.",
        kind = "upkeep",
        priority = 96,
        defaultEnabled = true,
        evaluate = function() return nil end,
    })
end

return Havens
