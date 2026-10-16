require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Movement/ALifeEntrances"
require "ProjectALife/Outposts/ALifeOutpostBuilder"
require "ProjectALife/Core/ALifeDayCycle"
require "ProjectALife/Senses/ALifeAwareness"
require "ProjectALife/Outposts/ALifePlanks"
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Behaviours/ALifeCold"
require "ProjectALife/Loot/ALifeBodyLoot"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Actors = ProjectALife.ActorRegistry
local Entrances = ProjectALife.Entrances
local DayCycle = ProjectALife.DayCycle
local Awareness = ProjectALife.Awareness
local Planks = ProjectALife.Planks

local Life = {
    settings = {

        beatMinimumMs = 25000,
        beatSpreadMs = 35000,

        shelterChancePercent = 35,
        buildingRadius = 40,
        hammerMs = 4000,

        entranceClearance = 1.5,

        litOutside = 0.45,
        threatSide = 0.3,

        campFireMinutes = 540,

        warmBelowC = 8,
        warmRange = 6,
        warmMinMs = 7000,
        warmSpreadMs = 6000,
        warmRestMinMs = 14000,
        warmRestSpreadMs = 18000,
        warmFirstMs = 2000,
        warmFirstSpreadMs = 4000,

        benchReach = 1.5,
        benchRecheckMs = 5000,
        benchRetryMs = 10000,
        benchClaimMs = 6000,
        benchSeatTolerance = 0.25,
    },
    optionKeys = { campWarmHands = "Idle_CampWarmHands", benchSeat = "Idle_BenchSeat" },
    optionDefaults = { campWarmHands = true, benchSeat = true },
    warmCycle = setmetatable({}, { __mode = "k" }),
    seatOf = setmetatable({}, { __mode = "k" }),
    seatRetryAtMs = setmetatable({}, { __mode = "k" }),
    seatClaims = {},
    benchFacing = {
        furniture_seating_outdoor_01_0 = "S", furniture_seating_outdoor_01_1 = "S",
        furniture_seating_outdoor_01_4 = "N", furniture_seating_outdoor_01_5 = "N",
        furniture_seating_outdoor_01_3 = "E", furniture_seating_outdoor_01_2 = "E",
        furniture_seating_outdoor_01_7 = "W", furniture_seating_outdoor_01_6 = "W",
    },
    facingVector = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } },
    metrics = { beats = 0, shelters = 0, windows = 0, planks = 0, refused = 0, camps = 0, campsBroken = 0 },

    beatDurationMs = { eat = 12000, drink = 9000, smoke = 20000, sit_down = 2400 },
}
ProjectALife.ModuleIdleLife = Life

local RINGS = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
}

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function hourNow()
    local hour = 12
    pcall(function() hour = getGameTime():getHour() end)
    return hour
end

local function nightNow()
    local cycle = DayCycle or ProjectALife.DayCycle
    return cycle ~= nil and cycle.isNight() == true
end

local function shareFor(kind, memory)
    local awareness = Awareness or ProjectALife.Awareness
    return awareness ~= nil and awareness.forRole(kind, memory) or nil
end

local function dayNow()
    local day = 0
    pcall(function() day = getGameTime():getNightsSurvived() end)
    return day
end

local function seedOf(actor, salt)
    local id = tostring(actor and actor.uid or "") .. tostring(salt or "")
    local seed = 0
    for index = 1, #id do
        seed = (seed * 31 + string.byte(id, index)) % 2147483647
    end
    return (seed % 1000) / 1000
end

local function beatFor(seed, hour)
    local roll = (seed * 1000 + hour * 7) % 100
    if roll < 25 then return "eat" end
    if roll < 50 then return "drink" end
    if roll < 75 then return "smoke" end
    return "sit_down"
end

local function memoryOf(actor)
    return type(actor.memory) == "table" and actor.memory or {}
end

local function positionOf(shell)
    local ok, x, y, z = pcall(function() return shell:getX(), shell:getY(), shell:getZ() end)
    if not ok then return nil end
    return { x = x, y = y, z = z }
end

local function squareAt(x, y, z)
    local square
    pcall(function() square = getCell():getGridSquare(x, y, z) end)
    return square
end

local function buildingIdOf(building)
    if building == nil then return nil end
    local id
    pcall(function() id = tostring(building:getID()) end)
    return id
end

local SIDE_STEP = { N = { 0, -1 }, S = { 0, 1 }, W = { -1, 0 }, E = { 1, 0 } }

function Life.facingOf(centre, from)
    if type(centre) ~= "table" or type(from) ~= "table" then return nil end
    local dx, dy = (tonumber(from.x) or 0) - centre.x, (tonumber(from.y) or 0) - centre.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then return nil end
    return { x = dx / length, y = dy / length }
end

function Life.toward(opening, centre, facing)
    if type(facing) ~= "table" or type(centre) ~= "table" then return 0 end
    if tonumber(opening.x) == nil or tonumber(opening.y) == nil then return 0 end
    local dx, dy = opening.x + 0.5 - centre.x, opening.y + 0.5 - centre.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then return 0 end
    return (dx * facing.x + dy * facing.y) / length
end

function Life.rankOpenings(openings, centre, facing, from)
    local list = {}
    for _, opening in ipairs(type(openings) == "table" and openings or {}) do
        local score = Life.toward(opening, centre, facing) * 2 + (opening.road == true and 1 or 0)
        local dx = opening.x - (tonumber(from and from.x) or opening.x)
        local dy = opening.y - (tonumber(from and from.y) or opening.y)
        list[#list + 1] = { opening = opening, score = score, d = dx * dx + dy * dy }
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.d < b.d
    end)
    local out = {}
    for index, entry in ipairs(list) do out[index] = entry.opening end
    return out
end

local function outsideOf(opening)
    local step = SIDE_STEP[tostring(opening.side)]
    if step == nil then return nil end
    return squareAt(opening.x + step[1], opening.y + step[2], opening.z)
end

function Life.squadShells(actor, shell)
    local shells, groupId = { shell }, memoryOf(actor).groupId
    if groupId == nil then return shells end
    pcall(function()
        local watchdog = ProjectALife.Watchdog
        for uid, binding in pairs(watchdog and watchdog.bindings or {}) do
            if uid ~= actor.uid and type(binding) == "table" and binding.shell ~= nil and binding.shell ~= shell then
                local record = Actors.read(uid)
                if record ~= nil and type(record.memory) == "table" and record.memory.groupId == groupId
                        and record.lifecycle ~= "dead" then
                    shells[#shells + 1] = binding.shell
                end
            end
        end
    end)
    return shells
end

local function nextBuilding(shell, done, radius)
    local here = positionOf(shell)
    if here == nil then return nil end
    local ox, oy, oz = math.floor(here.x), math.floor(here.y), math.floor(here.z)
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
                    if id ~= nil and done[id] ~= true then return id, square, building end
                end
            end
        end
        ring = ring + 3
    end
    return nil
end

local function buildingRefused(building)
    local refused = false
    pcall(function()
        local def = building:getDef()
        if def == nil then return end
        local x1, y1, x2, y2 = def:getX(), def:getY(), def:getX2(), def:getY2()
        local heat = ProjectALife.BaseHeat
        if heat ~= nil and type(heat.anchorOverlaps) == "function" and heat.anchorOverlaps(x1, y1, x2, y2) then
            refused = true
            return
        end
        if SafeHouse ~= nil and SafeHouse.getSafehouseList ~= nil then
            local list = SafeHouse.getSafehouseList()
            for index = 0, list:size() - 1 do
                local house = list:get(index)
                local hx, hy, hw, hh = house:getX(), house:getY(), house:getW(), house:getH()
                if x2 >= hx and x1 <= hx + hw and y2 >= hy and y1 <= hy + hh then
                    refused = true
                    return
                end
            end
        end
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players ~= nil then
            for index = 0, players:size() - 1 do
                local player = players:get(index)
                if player ~= nil and player:getBuilding() == building then
                    refused = true
                    return
                end
            end
        elseif getSpecificPlayer ~= nil then
            local player = getSpecificPlayer(0)
            if player ~= nil and player:getBuilding() == building then refused = true end
        end
    end)
    return refused
end
Life.buildingRefused = buildingRefused

function Life.openingsToSecure(building, memory, from)
    local builder = ProjectALife.OutpostBuilder
    local probe, bounds
    pcall(function() probe, bounds = builder.probeBuilding(building) end)
    if probe == nil or type(bounds) ~= "table" then return {} end
    local centre = { x = (bounds.x1 + bounds.x2 + 1) / 2, y = (bounds.y1 + bounds.y2 + 1) / 2 }
    local way = type(memory.shelterEntrance) == "table" and memory.shelterEntrance or nil
    local clearance = Life.settings.entranceClearance
    local road = ProjectALife.Road
    local candidates = {}
    local function consider(opening, isDoor)
        if opening.barricaded == true or opening.object == nil then return end
        if isDoor and way ~= nil and math.floor(tonumber(way.z) or 0) == opening.z
                and (opening.x - way.x) ^ 2 + (opening.y - way.y) ^ 2 <= clearance * clearance then return end
        local outside = outsideOf(opening)
        if outside == nil then return end
        if (tonumber(opening.z) or 0) > 0 then
            local standable = false
            pcall(function() standable = outside:TreatAsSolidFloor() == true end)
            if not standable then return end
        end
        local byRoad = false
        pcall(function()
            byRoad = road ~= nil and type(road.isRoadSquare) == "function" and road.isRoadSquare(outside) == true
        end)
        candidates[#candidates + 1] = { x = opening.x, y = opening.y, z = opening.z, side = opening.side, road = byRoad }
    end
    for _, opening in ipairs(probe.windows()) do consider(opening, false) end
    if type(probe.doors) == "function" then
        for _, opening in ipairs(probe.doors()) do consider(opening, true) end
    end
    return Life.rankOpenings(candidates, centre, Life.facingOf(centre, memory.shelterFrom), from)
end

local function openingAt(building, spot)
    local found
    pcall(function()
        local probe = ProjectALife.OutpostBuilder.probeBuilding(building)
        if probe == nil then return end
        local lists = { probe.windows() }
        if type(probe.doors) == "function" then lists[2] = probe.doors() end
        for _, list in ipairs(lists) do
            for _, opening in ipairs(list) do
                if opening.x == spot.x and opening.y == spot.y and opening.z == spot.z
                        and tostring(opening.side) == tostring(spot.side) then
                    found = opening.object
                    return
                end
            end
        end
    end)
    return found
end

local function boardWindow(window, planks, character, shells)
    if type(isClient) == "function" and isClient() == true then
        local fires = ProjectALife.Campfires
        if fires and fires.requestShelter then
            local square = window:getSquare()
            fires.requestShelter(character, "board", { x = square:getX(), y = square:getY(), z = square:getZ() }, planks)
        end
        return false 
    end
    local ok = false
    pcall(function()
        local store = Planks or ProjectALife.Planks
        if store == nil or store.held(shells) <= 0 then return end

        local barricade = IsoBarricade.AddBarricadeToObject(window, character or false)
        if barricade == nil then return end
        local heat = ProjectALife.BaseHeat
        if heat ~= nil and type(heat.stampNpcBarricade) == "function" then heat.stampNpcBarricade(barricade) end
        local taken = store.take(shells, planks)
        for _ = 1, taken do barricade:addPlank(nil, nil) end
        if type(isServer) == "function" and isServer() then
            pcall(function() barricade:transmitCompleteItemToClients() end)
        end
        Life.metrics.planks = Life.metrics.planks + taken
        ok = taken > 0
    end)
    return ok
end

local function sentryOfGroup(actor)
    local groupId = memoryOf(actor).groupId
    local members = {}
    for _, record in ipairs(Actors.list()) do
        local memory = type(record.memory) == "table" and record.memory or {}
        if record.uid == actor.uid or (groupId ~= nil and memory.groupId == groupId) then
            members[#members + 1] = { uid = record.uid, groupIndex = memory.groupIndex, dead = record.lifecycle == "dead" }
        end
    end
    local awareness = Awareness or ProjectALife.Awareness
    return awareness ~= nil and awareness.sentryOf(members) or nil
end

local function shelterSquad(actor, anchor, buildingId)
    local groupId = memoryOf(actor).groupId
    local sentry = sentryOfGroup(actor)
    local count = 0
    for _, record in ipairs(Actors.list()) do
        local memory = type(record.memory) == "table" and record.memory or {}
        local same = record.uid == actor.uid
            or (groupId ~= nil and memory.groupId == groupId)
        if same and record.lifecycle ~= "dead" then
            Actors.update(record.uid, record.revision, function(fresh)
                fresh.memory = fresh.memory or {}
                fresh.memory.stance = "shelter"
                fresh.memory.stanceAnchor = { x = anchor.x, y = anchor.y, z = anchor.z or 0 }
                fresh.memory.stanceSentry = record.uid == sentry
                fresh.memory.stanceAwareness = shareFor("houseNight", fresh.memory)
                fresh.memory.shelterBuildingId = buildingId
                fresh.memory.shelterManagedByLife = true
                fresh.memory.shelterUntilHours = memoryOf(actor).shelterUntilHours
            end)
            count = count + 1
        end
    end
    return count
end

local function campSpot(shell)
    local here = positionOf(shell)
    if here == nil then return nil end
    local road = ProjectALife.Road
    for _, ring in ipairs(RINGS) do
        for step = 3, 6, 3 do
            local x, y = math.floor(here.x + ring[1] * step), math.floor(here.y + ring[2] * step)
            local square = squareAt(x, y, math.floor(here.z))
            local ok = false
            pcall(function()
                ok = square ~= nil and square:isOutside() == true and square:getBuilding() == nil
                    and square:isFree(true) == true
                    and not (road ~= nil and type(road.isRoadSquare) == "function" and road.isRoadSquare(square))
            end)
            if ok then return { x = x + 0.5, y = y + 0.5, z = math.floor(here.z) } end
        end
    end
    return nil
end

local function campSquad(actor, anchor, key, camping)
    local groupId = memoryOf(actor).groupId
    local sentry = camping and sentryOfGroup(actor) or nil
    local count = 0
    for _, record in ipairs(Actors.list()) do
        local memory = type(record.memory) == "table" and record.memory or {}
        local same = record.uid == actor.uid
            or (groupId ~= nil and memory.groupId == groupId)
        if same and record.lifecycle ~= "dead" then
            Actors.update(record.uid, record.revision, function(fresh)
                fresh.memory = fresh.memory or {}
                if camping then
                    if fresh.memory.nightCamp ~= true then
                        fresh.memory.nightCampRestore = { stance = fresh.memory.stance, stanceAnchor = fresh.memory.stanceAnchor,
                            stanceAwareness = fresh.memory.stanceAwareness, stancePost = fresh.memory.stancePost,
                            stancePhase = fresh.memory.stancePhase, stanceSentry = fresh.memory.stanceSentry }
                    end
                    fresh.memory.stance = "camp"
                    fresh.memory.stanceAnchor = { x = anchor.x, y = anchor.y, z = anchor.z or 0 }
                    fresh.memory.stanceSentry = record.uid == sentry
                    fresh.memory.stanceAwareness = shareFor("asleep", fresh.memory)
                    fresh.memory.nightCamp = true
                    fresh.memory.nightCampKey = key
                    fresh.memory.stancePost = nil
                    fresh.memory.stancePhase = nil
                else
                    local old = fresh.memory.nightCampRestore or {}
                    fresh.memory.stance = old.stance or ""
                    fresh.memory.stanceAnchor = old.stanceAnchor
                    fresh.memory.stanceAwareness = old.stanceAwareness
                    fresh.memory.stanceSentry = old.stanceSentry
                    fresh.memory.stancePhase = old.stancePhase
                    fresh.memory.nightCamp = nil
                    fresh.memory.nightCampKey = nil
                    fresh.memory.stancePost = old.stancePost
                    fresh.memory.nightCampRestore = nil
                end
            end)
            count = count + 1
        end
    end
    return count
end

function Life.makeCamp(actor, shell, context)
    local spot = campSpot(shell)
    if spot == nil then
        Life.metrics.refused = Life.metrics.refused + 1
        return nil
    end
    local memory = memoryOf(actor)
    local key = "camp:" .. tostring(memory.groupId or actor.uid)
    campSquad(actor, spot, key, true)
    pcall(function()
        local fires = ProjectALife.Campfires
        if fires ~= nil then fires.light(key, spot.x, spot.y, spot.z, Life.settings.campFireMinutes, actor) end
    end)
    Life.metrics.camps = (Life.metrics.camps or 0) + 1
    return { kind = "idle", intent = "make_camp", cooldownUntilMs = (tonumber(context and context.now) or nowMs()) + 200 }
end

function Life.breakCamp(actor)
    local memory = memoryOf(actor)
    local key = memory.nightCampKey
    campSquad(actor, nil, nil, false)
    pcall(function()
        local fires = ProjectALife.Campfires
        if fires ~= nil and type(key) == "string" then fires.douse(key, actor) end
    end)
    Life.metrics.campsBroken = (Life.metrics.campsBroken or 0) + 1
    return true
end

local function beat(actor, shell, context, now)

    if type(context) == "table" and context.threat ~= nil then return nil end
    local memory = memoryOf(actor)
    local nextAt = tonumber(memory.idleBeatAtMs)
    if nextAt == nil then
        context.persistMemory(actor, "idleBeatAtMs",
            now + 5000 * seedOf(actor, "first"))
        return nil
    end
    if now < nextAt then return nil end
    local which = beatFor(seedOf(actor, now), hourNow())
    local posed = ProjectALife.Animations
    if which == "sit_down" and posed ~= nil and type(posed.current) == "table" and posed.current[shell] == "sit_bench" then
        which = "drink"
    end
    local okay, applied = pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil and type(animations.apply) == "function" then
            return animations.apply(shell, which)
        end
    end)
    if not okay or applied ~= true then return nil end
    Life.metrics.beats = Life.metrics.beats + 1
    context.persistMemory(actor, "idleBeatAtMs", now + Life.settings.beatMinimumMs
        + Life.settings.beatSpreadMs * seedOf(actor, now + 1))
    context.setActivity(actor, "idle", "idle_" .. which)
    local duration = Life.beatDurationMs[which] or 12000
    return { kind = "idle", intent = "idle_" .. which, cooldownUntilMs = now + duration }
end

Life.postBeat = function(actor, shell, context)
    if not Registry.allows(actor, "idleLife") then return nil end
    return beat(actor, shell, context, tonumber(context.now) or nowMs())
end

function Life.pickBuilding(shell, radius)
    local done = {}
    for _ = 1, 6 do
        local id, square, building = nextBuilding(shell, done, radius)
        if id == nil then return nil end
        if buildingRefused(building) then
            done[id] = true
            Life.metrics.refused = Life.metrics.refused + 1
        else
            return id, square, building
        end
    end
    return nil
end

function Life.interiorSpot(actor, shell, building, now)
    local opening
    pcall(function() opening = Entrances.claim(actor, shell, building, now) end)
    if opening == nil then return nil end
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local inside = squareAt(math.floor(opening.x) + step[1], math.floor(opening.y) + step[2], opening.z)
        local valid = false
        pcall(function() valid = inside ~= nil and inside:getBuilding() == building
            and inside:isFree(false) and inside:TreatAsSolidFloor() end)
        if valid then
            return opening, { x = math.floor(opening.x) + step[1] + 0.5,
                y = math.floor(opening.y) + step[2] + 0.5, z = opening.z }
        end
    end
    Entrances.release(actor.uid)
    return nil
end

function Life.buildingIdAt(shell)
    local here = positionOf(shell)
    if here == nil then return nil end
    local square = squareAt(math.floor(here.x), math.floor(here.y), math.floor(here.z))
    local building
    pcall(function() building = square and square:getBuilding() or nil end)
    return buildingIdOf(building)
end

local function shelter(actor, shell, context, now)
    if type(context) == "table" and context.threat ~= nil then return nil end
    local memory = memoryOf(actor)
    local settings = Life.settings
    local night = nightNow()
    local task = type(memory.offlineTask) == "table" and memory.offlineTask or {}
    local directed = task.kind == "fortify" or (task.kind == "rest" and night)

    if memory.nightCamp == true and not night then
        local solo = (tonumber(memory.groupSize) or 1) <= 1
        if solo or memory.groupRole == "leader" then Life.breakCamp(actor) end
        return nil
    end
    if not night and not directed then return nil end
    if memory.stance ~= nil and memory.stance ~= "" then return nil end
    local solo = (tonumber(memory.groupSize) or 1) <= 1
    if not solo and memory.groupRole ~= "leader" then return nil end

    local phase = memory.shelterPhase
    if phase == nil then
        local day = dayNow()
        if directed then
            local stamp = tostring(task.assignedHours or task.untilHours or task.kind)
            if memory.shelterTaskStamp == stamp then return nil end
            context.persistMemory(actor, "shelterTaskStamp", stamp)
        elseif tonumber(memory.shelterRolledDay) == day then return nil end
        context.persistMemory(actor, "shelterRolledDay", day)
        if not directed and seedOf(actor, day) * 100 >= Life.shelterPercent() then return nil end
        local id, _, building = Life.pickBuilding(shell, settings.buildingRadius)

        if id == nil then
            if not night then return nil end
            return Life.makeCamp(actor, shell, context)
        end
        local opening, destination = Life.interiorSpot(actor, shell, building, now)
        if opening == nil then return nil end
        context.persistMemory(actor, "shelterBuildingId", id)
        context.persistMemory(actor, "shelterPhase", "entering")
        context.persistMemory(actor, "shelterWindows", 0)
        context.persistMemory(actor, "shelterPlan", nil)
        context.persistMemory(actor, "shelterFrom", positionOf(shell))
        context.persistMemory(actor, "shelterEntrance", { x = opening.x, y = opening.y, z = opening.z })
        context.persistMemory(actor, "shelterDestination", destination)
        context.persistMemory(actor, "shelterEnterUntilMs", now + 30000)
        if directed and not night then context.persistMemory(actor, "shelterUntilHours", task.untilHours) end
        Life.metrics.shelters = Life.metrics.shelters + 1
        return context.startMovement(actor, shell,
            destination, "idleLife", { pace = "walk", tolerance = 0.6, timeoutMs = 15000, activity = "moving" })
    end
    local id = memory.shelterBuildingId
    local here = positionOf(shell)
    if here == nil then return nil end
    local square = squareAt(math.floor(here.x), math.floor(here.y), math.floor(here.z))
    local building
    pcall(function() building = square and square:getBuilding() or nil end)
    local inside = building ~= nil and buildingIdOf(building) == id
    if phase == "entering" then
        if not inside then
            if now >= (tonumber(memory.shelterEnterUntilMs) or 0) or type(memory.shelterDestination) ~= "table" then
                context.persistMemory(actor, "shelterPhase", nil)
                Entrances.release(actor.uid)
                return nil
            end
            return context.startMovement(actor, shell, memory.shelterDestination, "idleLife",
                { pace = "walk", tolerance = 0.6, timeoutMs = 10000, activity = "moving" })
        end
        context.persistMemory(actor, "shelterPhase", "boarding")
        phase = "boarding"
    end
    if phase == "boarding" then
        if not inside or building == nil then
            context.persistMemory(actor, "shelterPhase", nil)
            return nil
        end
        local shells = Life.squadShells(actor, shell)

        local plan = memory.shelterPlan
        if type(plan) ~= "table" then
            local ranked = Life.openingsToSecure(building, memory, here)
            local members = math.max(#shells, math.floor(tonumber(memory.groupSize) or 1))
            local store = Planks or ProjectALife.Planks
            local planks = store ~= nil and store.plan(math.min(#ranked, members), store.held(shells)) or {}
            plan = {}
            for index, count in ipairs(planks) do
                local spot = ranked[index]
                plan[index] = { x = spot.x, y = spot.y, z = spot.z, side = spot.side, planks = count }
            end
            context.persistMemory(actor, "shelterPlan", plan)
        end
        local boarded = tonumber(memory.shelterWindows) or 0
        local hammerUntil = tonumber(memory.shelterHammerUntilMs)
        local at = plan[boarded + 1]
        if hammerUntil ~= nil and type(at) == "table" then
            if now < hammerUntil then
                return { kind = "idle", intent = "boarding_window", cooldownUntilMs = now + 600 }
            end

            local window = openingAt(building, at)
            if window ~= nil and boardWindow(window, at.planks, shell, shells) then
                Life.metrics.windows = Life.metrics.windows + 1
            end
            boarded = boarded + 1
            context.persistMemory(actor, "shelterWindows", boarded)
            context.persistMemory(actor, "shelterHammerUntilMs", nil)
            at = plan[boarded + 1]
        end
        if type(at) == "table" then
            local standX, standY = at.x + 0.5, at.y + 0.5
            local dx, dy = standX - here.x, standY - here.y
            if dx * dx + dy * dy > 2.25 or math.floor(here.z) ~= at.z then
                return context.startMovement(actor, shell,
                    { x = standX, y = standY, z = at.z }, "idleLife",
                    { pace = "walk", timeoutMs = 10000, activity = "moving" })
            end
            pcall(function()
                local animations = ProjectALife.Animations
                if animations ~= nil then animations.apply(shell, "board_up") end
            end)
            context.persistMemory(actor, "shelterHammerUntilMs", now + settings.hammerMs)
            return { kind = "idle", intent = "boarding_window", cooldownUntilMs = now + 600 }
        end

        pcall(Life.dressWindows, building, shell, memory.shelterFrom)
        shelterSquad(actor, here, id)
        context.persistMemory(actor, "shelterPhase", nil)
        context.persistMemory(actor, "shelterPlan", nil)
        return nil
    end
    return nil
end

Life.nightActivityPercent = { 0, 20, 45, 70, 95 }

function Life.shelterPercent()
    local current = ProjectALife.Settings and ProjectALife.Settings.current or nil
    local level = current and tonumber(current.nightActivity) or nil
    if level == nil then return Life.settings.shelterChancePercent end
    level = math.max(1, math.min(5, math.floor(level)))
    return 100 - Life.nightActivityPercent[level]
end

function Life.coverable(facts)
    if type(facts) ~= "table" then return true end
    if facts.light == nil or facts.occupied == nil then return true end
    if facts.light >= Life.settings.litOutside or facts.occupied == true then return true end
    return (tonumber(facts.toward) or 0) >= Life.settings.threatSide
end

function Life.outsideFacts(opening, centre, facing)
    local facts = { toward = Life.toward(opening, centre, facing) }
    local outside = outsideOf(opening)
    if outside == nil then return facts end
    pcall(function() facts.light = tonumber(outside:getLightLevel(0)) end)
    pcall(function()
        local moving = outside:getMovingObjects()
        facts.occupied = moving ~= nil and moving:size() > 0
    end)
    return facts
end

function Life.dressWindows(building, shell, from)
    local dressed = 0
    if building == nil then return 0 end
    if type(isClient) == "function" and isClient() == true then
        local fires = ProjectALife.Campfires
        local here = positionOf(shell)
        if fires and fires.requestShelter and here then fires.requestShelter(shell, "sheets", here) end
        return 0
    end
    pcall(function()
        local probe, bounds = ProjectALife.OutpostBuilder.probeBuilding(building)
        if probe == nil then return end
        local centre = type(bounds) == "table" and { x = (bounds.x1 + bounds.x2 + 1) / 2, y = (bounds.y1 + bounds.y2 + 1) / 2 } or nil
        local facing = Life.facingOf(centre, from)
        for _, opening in ipairs(probe.windows()) do
            if Life.coverable(Life.outsideFacts(opening, centre, facing)) then
                local ready, changed = ProjectALife.OutpostBuilder.closeSheet(opening.object)
                if ready and changed then dressed = dressed + 1 end
            end
        end
    end)
    Life.metrics.dressed = (Life.metrics.dressed or 0) + dressed
    return dressed
end

Life.sweepSettings = { everyMinutes = 10, playerRadius = 40, maximum = 12 }

function Life.sweepShelters(players)
    if type(isClient) == "function" and isClient() then return 0 end
    local held, found = {}, 0
    pcall(function()
        Actors.each(function(record)
            local memory = type(record.memory) == "table" and record.memory or {}
            local p = record.worldPosition
            if record.lifecycle == "active" and memory.shelterBuildingId ~= nil and type(p) == "table" then
                held[tostring(memory.shelterBuildingId)] = held[tostring(memory.shelterBuildingId)] or p
            end
        end)
    end)
    players = players or {}
    if #players == 0 then
        pcall(function()
            local locator = ProjectALife.PlayerLocator
            for _, player in ipairs(locator and locator.list() or {}) do
                players[#players + 1] = { x = player:getX(), y = player:getY() }
            end
        end)
    end
    for _, at in pairs(held) do
        local watched = false
        for _, player in ipairs(players) do
            local dx, dy = (tonumber(player.x) or 0) - at.x, (tonumber(player.y) or 0) - at.y
            if dx * dx + dy * dy <= Life.sweepSettings.playerRadius ^ 2 then watched = true end
        end
        if not watched then
            pcall(function()
                local cell = getCell()
                local square = cell:getGridSquare(math.floor(at.x), math.floor(at.y), math.floor(at.z or 0))
                local building = square and square:getBuilding() or nil
                local def = building and building:getDef() or nil
                if def == nil then return end
                for z = 0, 2 do
                    for x = def:getX(), def:getX2() do
                        for y = def:getY(), def:getY2() do
                            local here = cell:getGridSquare(x, y, z)
                            local moving = here and here:getRoom() ~= nil and here:getMovingObjects() or nil
                            for index = (moving and moving:size() or 0) - 1, 0, -1 do
                                local body = moving:get(index)
                                if found < Life.sweepSettings.maximum and body ~= nil
                                        and instanceof(body, "IsoZombie") and not body:isDead()

                                        and not ProjectALife.ShellSimulation.grappledCorpse(body) then

                                    local owned = false
                                    if body.hasModData == nil or body:hasModData() then
                                        local data = body:getModData()
                                        owned = type(data) == "table" and data.ProjectALifeOwned == true
                                    end
                                    if not owned then found = found + 1 end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
    Life.metrics.shelterZombies = found
    return found
end

function Life.option(field)
    local settings = ProjectALife.Settings
    local current = nil
    if type(settings) == "table" then current = settings.current end
    if type(current) == "table" and current[field] ~= nil then return current[field] end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" then
        local value = SandboxVars.ALife[Life.optionKeys[field]]
        if value ~= nil then return value end
    end
    return Life.optionDefaults[field]
end

function Life.weatherNow(now)
    local seasons = ProjectALife.Seasons
    if seasons == nil or type(seasons.weather) ~= "function" then return nil end
    local weather = seasons.weather(now)
    if type(weather) ~= "table" then return nil end
    return weather
end

function Life.coldNow(shell, now)
    local seasons = ProjectALife.Seasons
    if seasons ~= nil and type(seasons.current) == "function" and seasons.current() == "winter" then return true end
    local weather = Life.weatherNow(now)
    if weather == nil then return false end
    local air = tonumber(weather.air)
    local cold = ProjectALife.Cold
    if cold ~= nil and type(cold.airAt) == "function" then
        local felt = tonumber(cold.airAt(shell, weather))
        if felt ~= nil then air = felt end
    end
    return air ~= nil and air <= Life.settings.warmBelowC
end

function Life.fireNear(shell, now)
    local cold = ProjectALife.Cold
    if cold == nil or type(cold.nearestFire) ~= "function" or type(cold.positionOf) ~= "function" then return false end
    local x, y = cold.positionOf(shell)
    if x == nil then return false end
    local fire = cold.nearestFire(shell, Life.weatherNow(now), now)
    if fire == nil then return false end
    local dx, dy = fire.x - x, fire.y - y
    local range = Life.settings.warmRange
    return dx * dx + dy * dy <= range * range
end

function Life.campPose(shell, now, base, startWarm)
    base = base or "sit_ground"
    if Life.option("campWarmHands") == false then
        Life.warmCycle[shell] = nil
        return base
    end
    now = tonumber(now) or nowMs()
    if not Life.coldNow(shell, now) or not Life.fireNear(shell, now) then
        Life.warmCycle[shell] = nil
        return base
    end
    local settings = Life.settings
    local cycle = Life.warmCycle[shell]
    if cycle == nil then
        if startWarm == true then
            cycle = { warm = true, untilMs = now + settings.warmMinMs + ZombRand(settings.warmSpreadMs) }
            Life.metrics.warmHands = (Life.metrics.warmHands or 0) + 1
        else
            cycle = { warm = false, untilMs = now + settings.warmFirstMs + ZombRand(settings.warmFirstSpreadMs) }
        end
        Life.warmCycle[shell] = cycle
    end
    if now >= cycle.untilMs then
        cycle.warm = not cycle.warm
        if cycle.warm then
            cycle.untilMs = now + settings.warmMinMs + ZombRand(settings.warmSpreadMs)
            Life.metrics.warmHands = (Life.metrics.warmHands or 0) + 1
        else
            cycle.untilMs = now + settings.warmRestMinMs + ZombRand(settings.warmRestSpreadMs)
        end
    end
    if cycle.warm then return "warm_hands" end
    return base
end

Life.seatNames = { Chair = true, Chairs = true, Couch = true, Bench = true, Seat = true, Seating = true,
    Stool = true, Pew = true, Ottoman = true, Barstool = true, ["Bar Stool"] = true, ["50s Barstool"] = true,
    ["Blue Bar Stool"] = true }
Life.chairProps = { chairN = "N", chairS = "S", chairE = "E", chairW = "W" }

function Life.propFacing(object)
    if object == nil or type(object.getProperties) ~= "function" then return nil end
    local props = object:getProperties()
    if props == nil then return nil end
    local value = nil
    if type(props.get) == "function" and (type(props.has) ~= "function" or props:has("Facing") == true) then
        value = props:get("Facing")
    end
    if type(value) == "string" and Life.facingVector[value] ~= nil then return value end
    if type(SeatingManager) ~= "nil" and type(SeatingManager.getInstance) == "function" then
        local manager = SeatingManager.getInstance()
        if manager ~= nil and type(manager.getFacingDirection) == "function" then
            value = manager:getFacingDirection(object)
            if type(value) == "string" and Life.facingVector[value] ~= nil then return value end
        end
    end
    return nil
end

function Life.genericSeat(object)
    if object == nil or type(object.getProperties) ~= "function" then return nil end
    local props = object:getProperties()
    if props == nil or type(props.has) ~= "function" then return nil end
    local direction = nil
    for key, facing in pairs(Life.chairProps) do
        if props:has(key) == true then direction = facing end
    end
    local named = false
    if type(props.get) == "function" and props:has("CustomName") == true then
        named = Life.seatNames[props:get("CustomName")] == true
    end
    if direction == nil and not named then return nil end
    return Life.propFacing(object) or direction
end

function Life.seatFacing(square, any)
    if square == nil or type(square.getObjects) ~= "function" then return nil end
    local objects = square:getObjects()
    if objects == nil or type(objects.size) ~= "function" then return nil end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local name = nil
        if object ~= nil and type(object.getSprite) == "function" then
            local sprite = object:getSprite()
            if sprite ~= nil and type(sprite.getName) == "function" then name = sprite:getName() end
        end
        if type(name) == "string" then
            local facing = Life.benchFacing[name]
            if facing == nil and string.find(name, "furniture_seating", 1, true) == 1 then
                facing = Life.propFacing(object)
            end
            if facing == nil and any == true then facing = Life.genericSeat(object) end
            if facing ~= nil then return facing end
        end
    end
    return nil
end

function Life.passable(from, to)
    if from == nil or to == nil then return false end
    if from == to then return true end
    if type(from.isBlockedTo) == "function" and from:isBlockedTo(to) == true then return false end
    if type(from.isHoppableTo) == "function" and from:isHoppableTo(to) == true then return false end
    return true
end

function Life.seatTaken(square, key, shell, now)
    local claim = Life.seatClaims[key]
    if claim ~= nil and claim.shell ~= shell and now - claim.atMs < Life.settings.benchClaimMs then return true end
    local movers = nil
    if type(square.getMovingObjects) == "function" then movers = square:getMovingObjects() end
    if movers ~= nil and type(movers.size) == "function" then
        for index = 0, movers:size() - 1 do
            local other = movers:get(index)
            if other ~= nil and other ~= shell then return true end
        end
    end
    return false
end

function Life.findSeat(shell, post, now)
    local px, py = math.floor(post.x), math.floor(post.y)
    local z = math.floor(tonumber(post.z) or 0)
    local origin = squareAt(px, py, z)
    local reach = Life.settings.benchReach
    local best, bestDistance = nil, math.huge
    for _, step in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local sx, sy = px + step[1], py + step[2]
        local square = squareAt(sx, sy, z)
        local facing = Life.seatFacing(square)
        if facing ~= nil then
            local key = sx .. ":" .. sy .. ":" .. z
            local cx, cy = sx + 0.5, sy + 0.5
            local distance = (cx - post.x) ^ 2 + (cy - post.y) ^ 2
            if distance <= reach * reach and distance < bestDistance
                    and Life.passable(origin, square) and not Life.seatTaken(square, key, shell, now) then
                best, bestDistance = { x = cx, y = cy, z = z, sx = sx, sy = sy, key = key, facing = facing }, distance
            end
        end
    end
    return best
end

function Life.seatPost(actor, shell, post, now)
    local fence = ProjectALife.AIFence
    if Life.option("benchSeat") == false or type(post) ~= "table" or fence == nil
            or type(fence.drivesBody) ~= "function" or fence.drivesBody(shell) ~= true then
        Life.seatOf[shell] = nil
        return nil
    end
    now = tonumber(now) or nowMs()
    local seat = Life.seatOf[shell]
    if seat ~= nil and now < seat.checkAtMs then
        local claim = Life.seatClaims[seat.key]
        if claim == nil or claim.shell == shell then
            Life.seatClaims[seat.key] = { shell = shell, atMs = now }
            return seat
        end
        Life.seatOf[shell] = nil
    elseif seat == nil and now < (Life.seatRetryAtMs[shell] or 0) then
        return nil
    end
    local found = Life.findSeat(shell, post, now)
    if found == nil then
        Life.seatOf[shell] = nil
        Life.seatRetryAtMs[shell] = now + Life.settings.benchRetryMs
        return nil
    end
    found.checkAtMs = now + Life.settings.benchRecheckMs
    Life.seatOf[shell] = found
    Life.seatClaims[found.key] = { shell = shell, atMs = now }
    return found
end

function Life.seated(shell, seat)
    local x, y = shell:getX(), shell:getY()
    local tolerance = Life.settings.benchSeatTolerance
    return (x - seat.x) ^ 2 + (y - seat.y) ^ 2 <= tolerance * tolerance
end

function Life.snapTo(shell, seat)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.drivesBody) ~= "function" or fence.drivesBody(shell) ~= true
            or type(fence.moveBody) ~= "function" then return false end
    local x, y = shell:getX(), shell:getY()
    local reach = Life.settings.benchReach + 0.5
    if (x - seat.x) ^ 2 + (y - seat.y) ^ 2 > reach * reach then return false end
    local from = nil
    if type(shell.getCurrentSquare) == "function" then from = shell:getCurrentSquare() end
    local target = squareAt(seat.sx, seat.sy, seat.z)
    if target == nil then return false end
    if from ~= nil and not Life.passable(from, target) then return false end
    fence.moveBody(shell, seat.x, seat.y)
    Life.metrics.benchSeats = (Life.metrics.benchSeats or 0) + 1
    return true
end

function Life.faceSeat(shell, seat)
    local vector = Life.facingVector[seat.facing]
    if vector == nil or type(shell.setTargetAndCurrentDirection) ~= "function" then return false end
    shell:setTargetAndCurrentDirection(vector[1], vector[2])
    return true
end

function Life.seatAt(shell, x, y, z, now, from)
    local sx, sy = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)
    z = math.floor(tonumber(z) or 0)
    local square = squareAt(sx, sy, z)
    local facing = Life.seatFacing(square, true)
    if facing == nil then return nil end
    local key = sx .. ":" .. sy .. ":" .. z
    if from ~= nil and not Life.passable(from, square) then return nil end
    if Life.seatTaken(square, key, shell, tonumber(now) or nowMs()) then return nil end
    return { x = sx + 0.5, y = sy + 0.5, z = z, sx = sx, sy = sy, key = key, facing = facing }
end

function Life.claimSeat(seat, shell, now)
    if type(seat) ~= "table" or type(seat.key) ~= "string" then return false end
    local claim = Life.seatClaims[seat.key]
    now = tonumber(now) or nowMs()
    if claim ~= nil and claim.shell ~= shell and now - claim.atMs < Life.settings.benchClaimMs then return false end
    Life.seatClaims[seat.key] = { shell = shell, atMs = now }
    return true
end

function Life.releaseSeat(seat, shell)
    if type(seat) ~= "table" then return false end
    local claim = Life.seatClaims[seat.key]
    if claim ~= nil and claim.shell == shell then
        Life.seatClaims[seat.key] = nil
        return true
    end
    return false
end

local SeatApi = {}
ProjectALife.SeatApi = SeatApi

function SeatApi.facing(square, any) return Life.seatFacing(square, any) end
function SeatApi.objectFacing(object) return Life.genericSeat(object) end
function SeatApi.find(shell, post, now) return Life.findSeat(shell, post, now) end
function SeatApi.at(shell, x, y, z, now, from) return Life.seatAt(shell, x, y, z, now, from) end
function SeatApi.snap(shell, seat) return Life.snapTo(shell, seat) end
function SeatApi.face(shell, seat) return Life.faceSeat(shell, seat) end
function SeatApi.seated(shell, seat) return Life.seated(shell, seat) end
function SeatApi.claim(seat, shell, now) return Life.claimSeat(seat, shell, now) end
function SeatApi.release(seat, shell) return Life.releaseSeat(seat, shell) end
function SeatApi.taken(square, key, shell, now) return Life.seatTaken(square, key, shell, now) end
function SeatApi.passable(from, to) return Life.passable(from, to) end

function Life.sitPose(actor, shell, now)
    now = tonumber(now) or nowMs()
    local seat = Life.seatOf[shell]
    if seat ~= nil and now < seat.checkAtMs + Life.settings.benchClaimMs
            and (Life.seated(shell, seat) or Life.snapTo(shell, seat)) then
        Life.faceSeat(shell, seat)
        return "sit_bench"
    end
    return Life.campPose(shell, now, "sit_ground")
end

Registry.register({
    id = "idleLife",
    label = "Idle life",
    summary = "Eats, drinks and smokes between fights; at night a stance-less squad may board up a house and stay till morning.",
    kind = "upkeep",
    priority = 140,
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if not Registry.allows(actor, "idleLife") then return nil end
        local cold = ProjectALife.Cold
        if cold ~= nil then
            local chilled = cold.step(actor, shell, context, tonumber(context.now) or nowMs())
            if chilled ~= nil then return chilled end
        end
        local groups = ProjectALife.GroupLife
        if groups ~= nil and type(groups.step) == "function" then
            local held = groups.step(actor, shell, context)
            if held ~= nil then return held end
        end
        local bodyLoot = ProjectALife.BodyLoot
        if bodyLoot ~= nil and type(bodyLoot.step) == "function" then
            local looting = bodyLoot.step(actor, shell, context, tonumber(context.now) or nowMs())
            if looting ~= nil then return looting end
        end

        local armed = false
        pcall(function()
            armed = shell:getVariableBoolean("ALifeWeaponHeld") == true
        end)
        if not armed then
            pcall(function()
                local held = shell:getPrimaryHandItem()
                armed = held ~= nil and instanceof(held, "HandWeapon")
                    and tostring(held:getFullType()) ~= "Base.BareHands"
            end)
        end
        local now = tonumber(context.now) or nowMs()
        if armed then return beat(actor, shell, context, now) end
        local taken = shelter(actor, shell, context, now)
        if taken ~= nil then return taken end
        return beat(actor, shell, context, now)
    end,
})

return Life
