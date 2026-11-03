require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Movement/ALifeEntrances"
require "ProjectALife/Loot/ALifeScavenging"
require "ProjectALife/Senses/ALifeClues"
require "ProjectALife/Movement/ALifeObstacleTraversal"

ProjectALife = ProjectALife or {}

local Registry   = ProjectALife.ModuleRegistry
local Entrances  = ProjectALife.Entrances
local Scavenging = ProjectALife.Scavenging
local Clues      = ProjectALife.Clues
local Traversal  = ProjectALife.ObstacleTraversal

local Run = {
    settings = {
        buildingRadius  = 27,     
        approachMs      = 20000,  
        settleMs        = 700,    
        searchMs        = 3200,   
        containerLimit  = 4,      
        containerRadius = 6,
        inspectCap      = 169,    
        beatMs          = 400,
        carryLimit      = 8,      
        returnAfterBuildings = 2,
        restMs          = 30000,
        searchCooldownMs = 5000,

        travelTimeoutMs = 60000,
    },
    metrics = { buildings = 0, containers = 0, rerouted = 0, returns = 0, deposited = 0,

        travelled = 0 },
}
ProjectALife.ScavengeRun = Run

function Run.configure(options)
    options = options or {}
    Run.settings.buildingRadius = math.max(8, math.min(60, tonumber(options.buildingRadius) or 27))
    Run.settings.carryLimit = math.max(1, math.min(24, tonumber(options.carryLimit) or 8))
    Run.settings.returnAfterBuildings = math.max(1, math.min(8, tonumber(options.returnAfterBuildings) or 2))
    Run.groupPicks, Run.leaderSeen, Run.homeCache, Run.areaCache = {}, {}, {}, {}
end

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function memoryOf(actor)
    if type(actor.memory) ~= "table" then actor.memory = {} end
    return actor.memory
end

local function write(context, actor, key, value)
    if type(context.persistMemory) == "function" then
        context.persistMemory(actor, key, value)
    else
        memoryOf(actor)[key] = value
    end
end

local function positionOf(shell)
    local ok, x, y, z = pcall(function()
        return shell:getX(), shell:getY(), shell:getZ()
    end)
    if not ok then return nil end
    return { x = x, y = y, z = z }
end

local function flat(a, b)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

local function squareAt(x, y, z)
    local square
    pcall(function()
        local cell = getCell()
        if cell ~= nil then
            square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
        end
    end)
    return square
end

local function buildingIdOf(building)
    if building == nil then return nil end
    local id
    pcall(function() id = tostring(building:getID()) end)
    return id
end

local function pose(shell, id)
    pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.apply(shell, id) end
    end)
end

local function clearPose(shell)
    pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.clear(shell) end
    end)
end

local function say(shell, event)
    pcall(function()
        local speech = ProjectALife.Voice
        if speech ~= nil then speech.play(shell, event) end
    end)
end

Run.groupPicks = {}
Run.leaderSeen = {}
Run.homeCache = {}

local nextPruneMs = 0
local function pruneCaches(now)
    if now < nextPruneMs then return end
    nextPruneMs = now + 60000
    for id, value in pairs(Run.groupPicks) do
        if now - (tonumber(value.atMs) or 0) > 300000 then Run.groupPicks[id] = nil end
    end
    for id, value in pairs(Run.leaderSeen) do
        if now - value.atMs > 60000 then Run.leaderSeen[id] = nil end
    end
    for id, value in pairs(Run.homeCache) do
        if now >= value.untilMs then Run.homeCache[id] = nil end
    end
    for id, value in pairs(Run.areaCache or {}) do
        if now >= value.untilMs then Run.areaCache[id] = nil end
    end
end

function Run.wantedFor(groupId)
    local id = tostring(groupId or "")
    if id == "" then return nil end
    local seed = 0
    for index = 1, #id do seed = (seed * 31 + string.byte(id, index)) % 2147483647 end
    local lists = { "medical", "food", "ammo", "tools" }
    return lists[seed % #lists + 1]
end

function Run.wantedForActor(actor)
    local memory = memoryOf(actor)
    local wanted = memory.scavengeWanted
    local catalog = ProjectALife.Catalog
    if wanted == nil and catalog ~= nil and type(catalog.faction) == "function" then
        local faction = catalog.faction(actor.factionId)
        wanted = faction and faction.scavenging and faction.scavenging.wanted or nil
    end
    if Scavenging.wantedKeywords[wanted] ~= nil then return wanted end
    return Run.wantedFor(memory.groupId)
end

function Run.leaderAlive(groupId, now)
    if type(groupId) ~= "string" then return false end
    local seen = Run.leaderSeen[groupId]
    if seen ~= nil and now - seen.atMs < 3000 then return seen.alive end
    local alive, leaderUid = false, nil
    local registry = ProjectALife.ActorRegistry
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record)
            local memory = type(record.memory) == "table" and record.memory or {}
            if record.lifecycle == "active" and memory.groupId == groupId
                    and memory.groupRole == "leader" then
                alive = true
                leaderUid = record.uid
                return true
            end
        end)
    end
    Run.leaderSeen[groupId] = { atMs = now, alive = alive, uid = leaderUid }
    return alive
end

function Run.leaderFor(groupId, now)
    if not Run.leaderAlive(groupId, now) then return nil end
    local seen, registry = Run.leaderSeen[groupId], ProjectALife.ActorRegistry
    local leader = seen and registry and registry.read and registry.read(seen.uid)
    if leader and leader.lifecycle == "active" and memoryOf(leader).groupRole == "leader" then return leader end
    Run.leaderSeen[groupId] = nil
    return nil
end

function Run.publishPick(actor, context, pick)
    local groupId = memoryOf(actor).groupId
    if groupId == nil then return end
    Run.groupPicks[groupId] = pick

    write(context, actor, "scavengePick", pick)
end

function Run.pickFor(actor, now)
    local memory = memoryOf(actor)
    local leader = memory.groupRole ~= "leader" and Run.leaderFor(memory.groupId, now) or actor
    local pick = leader and memoryOf(leader).scavengePick or Run.groupPicks[memory.groupId]
    if type(pick) == "table" and now - (tonumber(pick.atMs) or 0) <= 300000 then return pick end
    return nil
end

function Run.followPoint(actor, now)
    local leader = Run.leaderFor(memoryOf(actor).groupId, now)
    if leader == nil then return nil end
    local bindings = ProjectALife.Watchdog and ProjectALife.Watchdog.bindings
    local binding = bindings and bindings[leader.uid]
    local point = binding and binding.generation == leader.generation and positionOf(binding.shell)
        or leader.worldPosition
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then return nil end

    local index = math.max(1, tonumber(memoryOf(actor).groupIndex) or 1)
    local angle = (index % 8) * math.pi / 4
    return { x = point.x + math.cos(angle) * 2, y = point.y + math.sin(angle) * 2, z = point.z or 0 }
end

local function crewStillWorking(memory)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return false end
    local working = false
    registry.each(function(record)
        local mate = record.memory or {}
        if record.lifecycle == "active" and mate.groupId == memory.groupId
                and mate.groupRole ~= "leader" and mate.lootBuilding == memory.lootBuilding
                and (mate.lootPhase == "work" or mate.lootPhase == "search" or mate.lootPhase == "approach") then
            working = true
            return true
        end
    end)
    return working
end

local RINGS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

function Run.homeOfPlayer(building)
    local heat = ProjectALife.BaseHeat
    if building == nil or building.getDef == nil or heat == nil or type(heat.anchorOverlaps) ~= "function" then
        return false
    end
    local def = building:getDef()
    return def ~= nil and heat.anchorOverlaps(def:getX(), def:getY(), def:getX2(), def:getY2()) == true
end

function Run.siteSafe(shell, square)
    local caution = ProjectALife.Caution
    return caution == nil or caution.siteClear(shell, square)
end

local function nextBuilding(shell, done, radius)
    local here = positionOf(shell)
    if here == nil then return nil end
    local ox, oy, oz = math.floor(here.x), math.floor(here.y), math.floor(here.z)

    local current = squareAt(ox, oy, oz)
    local currentId = current and buildingIdOf(current:getBuilding())
    if currentId ~= nil and done[currentId] ~= true then
        if not Run.homeOfPlayer(current:getBuilding()) then return currentId, current end
        done[currentId] = true
    end
    local ring = 2
    while ring <= radius do
        for index = 1, #RINGS do
            local step = RINGS[index]
            local square = squareAt(ox + step[1] * ring, oy + step[2] * ring, oz)
            if square ~= nil then
                local building
                pcall(function() building = square:getBuilding() end)
                if building ~= nil then
                    local id = buildingIdOf(building)
                    if id ~= nil and done[id] ~= true then
                        if not Run.homeOfPlayer(building) then
                            if Run.siteSafe(shell, square) then return id, square end
                        else
                            done[id] = true
                        end
                    end
                end
            end
        end
        ring = ring + 3
    end
    return nil
end

local function insideBuilding(shell, id)
    if type(id) ~= "string" then return false end
    local current
    pcall(function()
        local square = shell:getCurrentSquare()
        if square == nil then return end
        local building = square:getBuilding()
        if building ~= nil then current = tostring(building:getID()) end
    end)
    return current == id
end

local function containerPreset(object)
    local name = ""
    pcall(function() name = string.lower(tostring(object:getSpriteName() or "")) end)
    if string.find(name, "shelves", 1, true)
            or string.find(name, "wallcabinet", 1, true)
            or string.find(name, "overhead", 1, true) then
        return "search_high"
    end
    if string.find(name, "crate", 1, true)
            or string.find(name, "floor", 1, true)
            or string.find(name, "bin", 1, true) then
        return "search_low"
    end
    return "search_mid"
end

local function notEmpty(container)
    local has = false
    pcall(function()
        local items = container:getItems()
        has = items ~= nil and items:size() > 0
    end)
    return has
end

local function containersOn(square)
    local found = {}
    if square == nil then return found end
    pcall(function()
        local objects = square:getObjects()
        if objects == nil then return end
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local count = 0
            pcall(function() count = object:getContainerCount() end)
            for containerIndex = 0, math.min(count, 8) - 1 do
                local container = object:getContainerByIndex(containerIndex)
                local unexplored = false
                pcall(function() unexplored = not container:isExplored() end)
                if container ~= nil and (notEmpty(container) or unexplored) then
                local spriteName
                pcall(function() spriteName = object:getSpriteName() end)
                found[#found + 1] = {

                    key = tostring(square:getX()) .. "," .. tostring(square:getY())
                        .. "," .. tostring(square:getZ()) .. ":"
                        .. tostring(spriteName or index) .. ":" .. containerIndex,
                    objectIndex = index, containerIndex = containerIndex,
                    spriteName = spriteName,
                    unexplored = unexplored,
                    object = object,
                    container = container,
                    preset = containerPreset(object),
                    x = square:getX() + 0.5,
                    y = square:getY() + 0.5,
                    z = square:getZ(),
                }
                end
            end
        end
    end)
    return found
end

local function workTheOpening(actor, shell, interior, now)
    if interior == nil then return "none" end
    local outcome = "walking"
    pcall(function()
        if Traversal == nil then return end
        if type(Traversal.openDoorAhead) == "function"
                and Traversal.openDoorAhead(shell, interior) then
            outcome = "door"
            return
        end
    end)
    if outcome ~= "walking" then return outcome end

    local claimed
    pcall(function()
        if Entrances == nil or type(Entrances.claim) ~= "function" then return end
        local cell = getCell()
        if cell == nil then return end
        local square = cell:getGridSquare(math.floor(interior.x),
            math.floor(interior.y), math.floor(interior.z))
        local building = square ~= nil and square:getBuilding() or nil
        if building == nil then return end
        claimed = Entrances.claim(actor, shell, building, now, true)
    end)
    if claimed == nil then return "locked" end
    return "walking"
end

local function standPoint(spot, buildingId)
    return Scavenging.standPoint(spot, buildingId)
end

local function nearestContainer(shell, worked, radius, cap, buildingId, wanted)
    local here = positionOf(shell)
    if here == nil then return nil end
    local ox, oy, oz = math.floor(here.x), math.floor(here.y), math.floor(here.z)
    local inspected = 0
    local best, bestScore = nil, -math.huge
    for ring = 0, radius do
        for dx = -ring, ring do
            for dy = -ring, ring do
                local edge = ring == 0
                    or math.abs(dx) == ring or math.abs(dy) == ring
                if edge then
                    inspected = inspected + 1
                    local square = squareAt(ox + dx, oy + dy, oz)
                    if square ~= nil and (buildingId == nil or buildingIdOf(square:getBuilding()) == buildingId) then
                        local list = containersOn(square)
                        for index = 1, #list do
                            local entry = list[index]
                            if worked[entry.key] ~= true then
                                local target = Scavenging.targetAt(entry, wanted)
                                local at = (target ~= nil or entry.unexplored) and standPoint(entry, buildingId) or nil
                                local priority = target and target.score or (entry.unexplored and 20 or -math.huge)
                                local score = priority - math.sqrt(flat(here, entry))
                                if at ~= nil and score > bestScore then
                                    entry.stand = at
                                    best, bestScore = entry, score
                                end
                            end
                        end
                    end
                    if inspected >= cap then return best end
                end
            end
        end
    end
    return best
end

function Run.homeFor(actor)
    local memory = memoryOf(actor)
    local siteId = memory.outpostId
    if siteId == nil and memory.squadId ~= nil and ProjectALife.SquadLedger ~= nil then
        local squad = ProjectALife.SquadLedger.read(memory.squadId)
        siteId = squad and squad.homeOutpostId or nil
    end
    if siteId ~= nil and ProjectALife.OutpostRegistry ~= nil then
        local cached = Run.homeCache[siteId]
        if cached ~= nil and nowMs() < cached.untilMs then return cached.home end
        local site = ProjectALife.OutpostRegistry.read(siteId)
        if site ~= nil and site.state ~= "expired" then
            local depot = type(site.containers) == "table" and site.containers[1] or nil
            local home = { x = depot and depot.x or site.x, y = depot and depot.y or site.y,
                z = depot and depot.z or 0, siteId = site.id, depots = {} }
            for index, point in ipairs(site.containers or {}) do
                if index > 16 then break end
                home.depots[#home.depots + 1] = { x = point.x, y = point.y, z = point.z or 0 }
            end
            Run.homeCache[siteId] = { home = home, untilMs = nowMs() + 60000 }
            return home
        end
        Run.homeCache[siteId] = { untilMs = nowMs() + 60000 }
        return nil
    end

    local home = memory.supplyDepot
    if type(home) == "table" and tonumber(home.x) and tonumber(home.y) then
        return { x = home.x, y = home.y, z = tonumber(home.z) or 0, vehicleSceneKey = home.vehicleSceneKey }
    end
    return nil
end

function Run.vehicleDepot(home)
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.vehicleAt) ~= "function" then return nil end
    local vehicle = kit.vehicleAt(home.vehicleSceneKey, home)
    if vehicle == nil or type(vehicle.getPartById) ~= "function" then return nil end
    local part = vehicle:getPartById("TruckBed")
    if part == nil or type(part.getItemContainer) ~= "function" then return nil end
    local container = part:getItemContainer()
    if container == nil then return nil end
    local at = nil
    if type(vehicle.getScript) == "function" and type(vehicle.areaPositionWorld4PlayerInteract) == "function"
            and type(part.getArea) == "function" then
        local script = vehicle:getScript()
        local area = script ~= nil and type(script.getAreaById) == "function" and script:getAreaById(part:getArea()) or nil
        local point = area ~= nil and vehicle:areaPositionWorld4PlayerInteract(area) or nil
        if point ~= nil then at = standPoint({ x = point:getX(), y = point:getY(), z = vehicle:getZ() }) end
    end
    return container, at
end

Run.areaCache = {}
function Run.areaFor(actor)
    local memory = memoryOf(actor)
    local area = memory.scavengeArea
    if type(area) == "table" and tonumber(area.x) ~= nil and tonumber(area.y) ~= nil then
        return { x = tonumber(area.x), y = tonumber(area.y), z = tonumber(area.z) or 0 }
    end
    local key = tostring(memory.outpostId or memory.groupId or "")
    if key == "" then return nil end
    local cached = Run.areaCache[key]
    if cached ~= nil and nowMs() < cached.untilMs then return cached.area end
    local found
    pcall(function()
        local graph = ProjectALife.RoadGraph
        if graph == nil or type(graph.nearest) ~= "function" then return end
        local anchor = Run.homeFor(actor)
        if anchor == nil then return end
        local townId = graph.nearest(anchor.x, anchor.y, "town")
        local node = townId ~= nil and graph.nodes and graph.nodes[townId] or nil
        if node == nil then return end
        found = { x = node.x, y = node.y, z = 0 }
    end)
    Run.areaCache[key] = { area = found, untilMs = nowMs() + 60000 }
    return found
end

local function homeDepot(home, shell)
    if home.vehicleSceneKey ~= nil then return Run.vehicleDepot(home) end
    local points = home.depots or { home }
    local cargo = Scavenging.cargo(shell)
    for _, point in ipairs(points or {}) do
        local square = squareAt(point.x, point.y, point.z or 0)
        if square ~= nil then
            local objects = square:getObjects()
            for index = 0, objects:size() - 1 do
                local object = objects:get(index)
                local count = object:getContainerCount()
                for containerIndex = 0, math.min(count, 8) - 1 do
                    local container = object:getContainerByIndex(containerIndex)
                    if container ~= nil then
                        local spot = { x = point.x, y = point.y, z = point.z or 0 }
                        local at = standPoint(spot)
                        local capacityOk, room = pcall(function() return cargo[1] == nil or container:hasRoomFor(shell, cargo[1]) end)
                        if at ~= nil and (not capacityOk or room) then return container, at end
                    end
                end
            end
        end
    end
    return nil
end

local function crewFollow(actor, shell, context, pick, now)
    if pick == nil then pick = Run.followPoint(actor, now) end

    if pick == nil then return nil end
    if pick ~= nil then
        local target = { x = pick.x, y = pick.y, z = pick.z }
        if flat(positionOf(shell), target) > 25 then
            return context.startMovement(actor, shell, target, "scavenge", {
                pace = "walk", timeoutMs = 12000, activity = "moving" })
        end
    end
    context.setActivity(actor, "idle", "wait_for_scavenge_leader")
    return { kind = "idle", intent = "wait_for_scavenge_leader", cooldownUntilMs = now + 1200 }
end

local function returnHome(actor, shell, context, now, home)
    local container, at = homeDepot(home, shell)
    local target = at or home
    if flat(positionOf(shell), target) > 2.25 or math.floor(shell:getZ()) ~= math.floor(target.z) then
        return context.startMovement(actor, shell, target, "scavenge", {
            pace = "walk", timeoutMs = 20000, activity = "return_with_loot" })
    end
    local moved = container and Scavenging.deposit(shell, container, 4) or 0
    Run.metrics.deposited = Run.metrics.deposited + moved
    if moved > 0 then
        say(shell, "RETURN_WITH_LOOT")
        return { kind = "idle", intent = "deposit_supplies", cooldownUntilMs = now + 1600 }
    end
    write(context, actor, "lootPhase", nil)
    write(context, actor, "lootBuildings", 0)
    write(context, actor, "lootRestUntilMs", now + Run.settings.restMs)
    local pick = Run.pickFor(actor, now)
    if memoryOf(actor).groupRole == "leader" and pick ~= nil then
        pick.returning, pick.id, pick.atMs = false, nil, now
        Run.publishPick(actor, context, pick)
    end
    return { kind = "idle", intent = "rest_after_scavenge", cooldownUntilMs = now + Run.settings.restMs }
end

Registry.register({
    id = "scavenge",
    label = "Scavenge",
    summary = "Works a nearby building end to end, falling back to loose containers.",
    kind = "upkeep",
    priority = 118,
    evaluate = function(actor, shell, context)
        if context.mode ~= "scavenge" then return nil end
        if type(isClient) == "function" and isClient() == true
                and not (ProjectALife.Executor ~= nil and ProjectALife.Executor.clientAuthority()) then return nil end
        local now = tonumber(context.now) or nowMs()
        pruneCaches(now)
        local here = positionOf(shell)
        if here == nil then return nil end
        local memory = memoryOf(actor)
        local phase = memory.lootPhase
        local settings = Run.settings
        if now < (tonumber(memory.lootRestUntilMs) or 0) then
            return { kind = "idle", intent = "rest_after_scavenge", cooldownUntilMs = memory.lootRestUntilMs }
        end
        local home = Run.homeFor(actor)
        local cargoCount = #Scavenging.cargo(shell)
        local pick = Run.pickFor(actor, now)
        if home ~= nil and (phase == "return" or (pick ~= nil and pick.returning == true)
                or cargoCount >= settings.carryLimit
                or (tonumber(memory.lootBuildings) or 0) >= settings.returnAfterBuildings) then
            if phase ~= "return" then
                clearPose(shell)
                write(context, actor, "lootPhase", "return")
                write(context, actor, "lootSpot", nil)
                Run.metrics.returns = Run.metrics.returns + 1
                if memory.groupRole == "leader" and memory.groupId ~= nil then
                    Run.publishPick(actor, context, { returning = true, x = home.x, y = home.y,
                        z = home.z, atMs = now })
                end
            end
            return returnHome(actor, shell, context, now, home)
        elseif phase == "return" then
            write(context, actor, "lootPhase", nil)
            phase = nil
        end
        if home == nil and cargoCount >= settings.carryLimit then
            clearPose(shell)
            write(context, actor, "lootPhase", nil)
            return nil
        end

        if phase == nil then
            local done = type(memory.lootDone) == "table" and memory.lootDone or {}
            local groupId = memory.groupId
            local id, square
            if type(groupId) == "string" and memory.groupRole ~= "leader"
                    and Run.leaderAlive(groupId, now) then
                local pick = Run.pickFor(actor, now)
                if pick == nil or pick.id == nil or done[pick.id] == true then
                    return crewFollow(actor, shell, context, pick, now)
                end
                id, square = pick.id, squareAt(pick.x, pick.y, pick.z)
                if square == nil then return nil end
            else
                if now < (tonumber(memory.lootNextScanMs) or 0) then return nil end
                write(context, actor, "lootNextScanMs", now + settings.searchCooldownMs)
                local planned = ProjectALife.GroupPlan
                if planned ~= nil and type(planned.buildingFor) == "function" then
                    local plannedOk, plannedId, plannedSquare = pcall(planned.buildingFor, actor, done)
                    if plannedOk then id, square = plannedId, plannedSquare end
                end
                if id == nil then id, square = nextBuilding(shell, done, settings.buildingRadius) end
                if id ~= nil and home ~= nil then
                    local homeSquare = squareAt(home.x, home.y, home.z)
                    if homeSquare ~= nil and buildingIdOf(homeSquare:getBuilding()) == id then
                        done[id] = true
                        write(context, actor, "lootDone", done)
                        return nil
                    end
                end
                if id ~= nil and type(groupId) == "string" then
                    local sx, sy, sz = 0, 0, 0
                    pcall(function() sx, sy, sz = square:getX(), square:getY(), square:getZ() end)
                    Run.publishPick(actor, context, { id = id, x = sx, y = sy, z = sz, atMs = now })
                    say(shell, "SCAVENGE_START")
                end
            end
            if id == nil then

                local area = Run.areaFor(actor)
                if area ~= nil and flat(here, area) > settings.buildingRadius * settings.buildingRadius then
                    if type(groupId) == "string" and memory.groupRole == "leader" then
                        Run.publishPick(actor, context, { id = nil, x = area.x, y = area.y,
                            z = area.z, atMs = now })
                    end
                    Run.metrics.travelled = (Run.metrics.travelled or 0) + 1
                    return context.startMovement(actor, shell, area, "scavenge", {
                        pace = "walk", timeoutMs = settings.travelTimeoutMs,
                        activity = "travel_to_scavenge" })
                end
                local plan = Scavenging.start(actor, shell, {
                    radius = context.defaults.scavenging.radius,
                    timeoutMs = context.defaults.movement.patrolTimeoutMs,
                    wanted = Run.wantedForActor(actor),
                    excludeNear = home,
                    supplyRun = true,
                })
                if plan == nil then return nil end
                context.setActivity(actor, "scavenging", "collect_supplies")
                return { kind = "scavenging", plan = plan,
                    intent = "collect_supplies", cooldownUntilMs = 0 }
            end
            local rooms = Clues.roomsToSearch(square, 32)
            if type(rooms) ~= "table" or #rooms == 0 then
                done[id] = true
                write(context, actor, "lootDone", done)
                return nil
            end
            write(context, actor, "lootDone", done)
            write(context, actor, "lootBuilding", id)
            write(context, actor, "lootRooms", rooms)
            write(context, actor, "lootRoomIndex", 1)
            write(context, actor, "lootRoomUntilMs", nil)
            write(context, actor, "lootWorked", {})
            write(context, actor, "lootCount", 0)
            write(context, actor, "lootPhase", "approach")
            write(context, actor, "lootUntilMs", now + settings.approachMs)
            Run.metrics.buildings = Run.metrics.buildings + 1
            memory = memoryOf(actor)
            phase = "approach"
        end

        if phase == "approach" then
            local rooms = memory.lootRooms
            local interior = type(rooms) == "table" and rooms[1] or nil
            if interior == nil then
                write(context, actor, "lootPhase", "leave")
                phase = "leave"
            elseif insideBuilding(shell, memory.lootBuilding) then
                say(shell, "ENTER_BUILDING")
                write(context, actor, "lootPhase", "work")
                phase = "work"
            else
                local outcome = workTheOpening(actor, shell, interior, now)
                if outcome == "locked" then
                    Run.metrics.rerouted = Run.metrics.rerouted + 1
                    say(shell, "DOOR_LOCKED")
                    write(context, actor, "lootPhase", "leave")
                    phase = "leave"
                elseif now >= (tonumber(memory.lootUntilMs) or 0) then

                    write(context, actor, "lootPhase", "leave")
                    phase = "leave"
                end
                if phase == "approach" then
                    return context.startMovement(actor, shell, interior, "scavenge", {
                        pace = "walk", timeoutMs = 12000, activity = "moving",
                    })
                end
            end
        end

        if phase == "work" then
            local count = tonumber(memory.lootCount) or 0
            local worked = type(memory.lootWorked) == "table" and memory.lootWorked or {}
            local spot
            if count < settings.containerLimit then
                spot = nearestContainer(shell, worked,
                    settings.containerRadius, settings.inspectCap, memory.lootBuilding, Run.wantedForActor(actor))
            end
            if spot == nil then

                local rooms = memory.lootRooms or {}
                local index = tonumber(memory.lootRoomIndex) or 1
                while count < settings.containerLimit and index <= #rooms do
                    local room = rooms[index]
                    local at = { x = room.x + 0.5, y = room.y + 0.5, z = room.z or 0 }
                    local deadline = tonumber(memory.lootRoomUntilMs) or (now + 12000)
                    if (flat(here, at) > 1 or math.abs(here.z - at.z) > 0.5) and now < deadline then
                        write(context, actor, "lootRoomIndex", index)
                        write(context, actor, "lootRoomUntilMs", deadline)
                        return context.startMovement(actor, shell, at, "scavenge", {
                            pace = "walk", tolerance = 0.75,
                            timeoutMs = math.min(10000, deadline - now), activity = "moving",
                        })
                    end
                    index = index + 1
                    write(context, actor, "lootRoomIndex", index)
                    write(context, actor, "lootRoomUntilMs", nil)
                end
                say(shell, "SEARCH_COMPLETE")
                write(context, actor, "lootPhase", "leave")
                phase = "leave"
            else
                write(context, actor, "lootRoomUntilMs", nil)
                local at = spot.stand
                if flat(here, at) > 0.1225 then
                    return context.startMovement(actor, shell, at, "scavenge", {
                        pace = "walk", tolerance = 0.35, timeoutMs = 10000, activity = "moving",
                    })
                end
                write(context, actor, "lootKey", spot.key)
                write(context, actor, "lootSpot", { x = spot.x, y = spot.y, z = spot.z,
                    objectIndex = spot.objectIndex, containerIndex = spot.containerIndex,
                    spriteName = spot.spriteName })
                write(context, actor, "lootPhase", "search")
                write(context, actor, "lootUntilMs",
                    now + settings.settleMs + settings.searchMs)
                pcall(function() shell:faceThisObject(spot.object) end)
                pose(shell, spot.preset)
                say(shell, "CONTAINER_SEARCH")
                context.setActivity(actor, "scavenging", "search_container")
                return { kind = "idle", intent = "search_container",
                    cooldownUntilMs = now + settings.beatMs }
            end
        end

        if phase == "search" then
            if now < (tonumber(memory.lootUntilMs) or 0) then
                context.setActivity(actor, "scavenging", "search_container")
                return { kind = "idle", intent = "search_container",
                    cooldownUntilMs = now + settings.beatMs }
            end
            local worked = type(memory.lootWorked) == "table" and memory.lootWorked or {}
            if type(memory.lootKey) == "string" then worked[memory.lootKey] = true end
            write(context, actor, "lootWorked", worked)
            write(context, actor, "lootCount", (tonumber(memory.lootCount) or 0) + 1)
            write(context, actor, "lootKey", nil)
            write(context, actor, "lootPhase", "work")
            Run.metrics.containers = Run.metrics.containers + 1
            clearPose(shell)

            local target = memory.lootSpot and Scavenging.targetAt(memory.lootSpot, Run.wantedForActor(actor), true, shell)
            write(context, actor, "lootSpot", nil)
            local plan = target and Scavenging.start(actor, shell,
                { target = target, radius = 1, tolerance = 0.35, timeoutMs = 6000, searched = true,
                    wanted = Run.wantedForActor(actor), supplyRun = true })
            if plan ~= nil then
                context.setActivity(actor, "scavenging", "collect_supplies")
                return { kind = "scavenging", plan = plan,
                    intent = "collect_supplies", cooldownUntilMs = 0 }
            end
            say(shell, "LOOT_EMPTY")
            return { kind = "idle", intent = "search_container",
                cooldownUntilMs = now + settings.beatMs }
        end

        if phase == "leave" then
            if memory.groupRole == "leader" and memory.groupId ~= nil and crewStillWorking(memory) then
                if memory.lootCrewWaitUntilMs == nil then
                    write(context, actor, "lootCrewWaitUntilMs", now + 12000)
                end
                if now < memory.lootCrewWaitUntilMs then
                    return { kind = "idle", intent = "wait_for_scavenge_crew", cooldownUntilMs = now + 1200 }
                end
            end
            local done = type(memory.lootDone) == "table" and memory.lootDone or {}
            if type(memory.lootBuilding) == "string" then
                done[memory.lootBuilding] = true
            end
            clearPose(shell)
            Entrances.release(actor.uid)
            local exit
            pcall(function()
                local square = shell:getCurrentSquare()
                local building = square ~= nil and square:getBuilding() or nil
                if building == nil then return end
                local opening = Entrances.claim(actor, shell, building)
                if opening ~= nil then
                    exit = { x = opening.x, y = opening.y, z = opening.z }
                end
            end)
            write(context, actor, "lootDone", done)
            write(context, actor, "lootPhase", nil)
            write(context, actor, "lootBuilding", nil)
            write(context, actor, "lootRooms", nil)
            write(context, actor, "lootRoomIndex", nil)
            write(context, actor, "lootRoomUntilMs", nil)
            write(context, actor, "lootWorked", nil)
            write(context, actor, "lootCount", nil)
            write(context, actor, "lootBuildings", (tonumber(memory.lootBuildings) or 0) + 1)
            write(context, actor, "lootUntilMs", nil)
            write(context, actor, "lootCrewWaitUntilMs", nil)
            say(shell, "EXIT_BUILDING")
            if exit ~= nil then
                return context.startMovement(actor, shell, exit, "scavenge", {
                    pace = "walk", timeoutMs = 12000, activity = "moving",
                })
            end
            return nil
        end

        return nil
    end,
})

return Run
