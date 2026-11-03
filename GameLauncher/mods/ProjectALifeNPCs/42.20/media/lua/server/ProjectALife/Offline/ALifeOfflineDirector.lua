require "ProjectALife/World/ALifeRoadGraph"
require "ProjectALife/Records/ALifePartyPolicy"
require "ProjectALife/Offline/ALifeSquadLedger"
require "ProjectALife/Offline/ALifeRenderProtocol"
require "ProjectALife/Offline/ALifeOfflineCombat"
require "ProjectALife/Offline/ALifeRevenge"
require "ProjectALife/Offline/ALifeOfflineLoot"
require "ProjectALife/Offline/ALifeHibernation"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/World/ALifeWorldPressure"

require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/Records/ALifeRosterDraw"
ProjectALife = ProjectALife or {}

local Graph = ProjectALife.RoadGraph
local Ledger = ProjectALife.SquadLedger
local Telemetry = ProjectALife.Telemetry

local Offline = {
    adapters = {},
    enabled = true,
    settings = {
        squadCap = 8,
        tickSeconds = 20,

        travelTilesPerHour = 150,

        foundGapHours = 6,
        foundPlayerDistance = 140,
        membersMinimum = 3,
        membersMaximum = 6,

        supplyDrainPerMemberHour = 0.35,
        moraleDecayPerHour = 0.02,

        scavengeSupplies = 12,
        restMorale = 0.08,
        homeReturnChance = 0.5,
        homeSuppliesFull = 70,
        homeWearyMorale = 0.35,

        wipedSweepHours = 168,

        graphSliceMs = 6,

        squadsPerSlice = 2,
        squadSliceMs = 3,

        spreadMargin = 600,

        occupiedRadius = 4,

        censusMs = 30000,
    },
    state = { lastTickMs = 0, lastFoundHours = -1e9, lastHours = nil, nextJitter = 0, lastFoundReason = nil,
        squadCursor = 1, squadClocks = {} },
    metrics = { ticks = 0, founded = 0, foundRefused = 0, tasked = 0, legs = 0, arrivals = 0, swept = 0,
        squadUpdates = 0, sliceYields = 0, serviceFaults = 0 },
}
ProjectALife.OfflineDirector = Offline
Offline.arrivals = {}

local function nowMs()
    if type(Offline.adapters.nowMs) == "function" then return Offline.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    if type(Offline.adapters.worldHours) == "function" then return Offline.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function hourOfDay()
    if type(Offline.adapters.hourOfDay) == "function" then return Offline.adapters.hourOfDay() end
    if type(getGameTime) ~= "function" then return 12 end
    local time = getGameTime()
    if time == nil or type(time.getHour) ~= "function" then return 12 end
    return tonumber(time:getHour()) or 12
end

local function roll()
    if type(Offline.adapters.roll) == "function" then return Offline.adapters.roll() end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000000) / 1000000 end
    return 1
end

local function playerPositions()
    if type(Offline.adapters.players) == "function" then return Offline.adapters.players() or {} end
    local result = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        for _, player in ipairs(locator.list()) do
            local position = locator.position(player)
            if position ~= nil then
                local key
                pcall(function() key = player:getUsername() end)
                position.key = tostring(key or "player0")
                result[#result + 1] = position
            end
        end
    end)
    return result
end

local function rosters()
    if type(Offline.adapters.rosters) == "function" then return Offline.adapters.rosters() or {} end
    local director = ProjectALife.Director
    return director and director.rosters or {}
end

local function emit(category, fields)
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then
        pcall(Telemetry.emit, category, fields)
    end
end

function Offline.timed(name, callback, ...)
    local started = nowMs()
    local first, second = callback(...)
    local spent = nowMs() - started
    local parts = Offline.metrics.partMs
    if type(parts) ~= "table" then
        parts = {}
        Offline.metrics.partMs = parts
    end
    parts[name] = (parts[name] or 0) + spent
    if spent > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then
            runtime.noteDetail("offline:" .. name, spent)
        end
    end
    return first, second
end

function Offline.configure(adapters)
    Offline.adapters = adapters or {}
    local settings = Offline.settings
    if Offline.adapters.foundGapHours ~= nil then
        settings.foundGapHours = math.max(0.25, math.min(48, tonumber(Offline.adapters.foundGapHours) or 6))
    end
    if Offline.adapters.squadCap ~= nil then

        settings.squadCap = math.max(0, math.min(500, math.floor(tonumber(Offline.adapters.squadCap) or 8)))
    end
    if Offline.adapters.tickSeconds ~= nil then
        settings.tickSeconds = math.max(10, math.min(60, tonumber(Offline.adapters.tickSeconds) or 20))
    end
    if Offline.adapters.travelTilesPerHour ~= nil then
        settings.travelTilesPerHour = math.max(20, math.min(400,
            tonumber(Offline.adapters.travelTilesPerHour) or 150))
    end
    Offline.enabled = Offline.adapters.enabled ~= false and settings.squadCap > 0
    pcall(function()
        ProjectALife.RenderProtocol.reset()
        ProjectALife.RenderProtocol.configure(Offline.adapters.render or {})
        ProjectALife.Revenge.configure({ enabled = Offline.adapters.revengeEnabled ~= false })
    end)
    return true
end

function Offline.reset()
    Offline.state = { lastTickMs = 0, lastFoundHours = -1e9, lastHours = nil, nextJitter = 0, lastFoundReason = nil,
        squadCursor = 1, squadClocks = {} }
    Offline.metrics.squadUpdates, Offline.metrics.sliceYields = 0, 0
    Offline.metrics.serviceFaults = 0
    return true
end

local function nearestPlayerDistance(x, y, players)
    local best = math.huge
    for _, p in ipairs(players) do
        local dx, dy = x - (tonumber(p.x) or 0), y - (tonumber(p.y) or 0)
        local d = math.sqrt(dx * dx + dy * dy)
        if d < best then best = d end
    end
    return best
end

local function legHours(len, tilesPerHour)
    return math.max(0.1, len / math.max(1, tilesPerHour))
end

local function graphStore()
    if type(Offline.adapters.graphStore) == "function" then return Offline.adapters.graphStore() end
    local result
    pcall(function()
        if ModData ~= nil and type(ModData.getOrCreate) == "function" then
            result = ModData.getOrCreate("ProjectALife.RoadGraph.v1")
        end
    end)
    return type(result) == "table" and result or nil
end

local function mapSignature()
    if type(Offline.adapters.mapSignature) == "function" then return Offline.adapters.mapSignature() end
    local name = "unknown"
    pcall(function() name = tostring(getWorld():getMap()) end)
    return name .. ";schema=" .. tostring(Graph.SCHEMA)
end

local function ensureGraph()
    if Graph.built then return true end
    local shipped = false
    if Graph.build == nil then
        local saved = graphStore()
        if saved ~= nil and Graph.import(saved, mapSignature()) then
            Offline.metrics.graphRestored = (Offline.metrics.graphRestored or 0) + 1
            emit("road_graph_restored", { towns = #Graph.towns, edges = #Graph.edges })
            return true
        end
        shipped = Graph.importShipped()
        if shipped then
            Offline.metrics.graphShipped = (Offline.metrics.graphShipped or 0) + 1
            emit("road_graph_shipped", { towns = #Graph.towns, edges = #Graph.edges })
        else
            Graph.startWorldBuild()
        end
    end
    if not shipped then
        if not Graph.buildStep(Offline.settings.graphSliceMs) then return false end
        Offline.metrics.graphBuilt = (Offline.metrics.graphBuilt or 0) + 1
        emit("road_graph_built", { towns = #Graph.towns, edges = #Graph.edges,
            slices = Graph.metrics.slices, ms = Graph.metrics.buildMs })
    end
    local store = graphStore()
    if store ~= nil then

        local exported = Graph.export(mapSignature())
        if exported.partial then
            Offline.metrics.graphPartial = (Offline.metrics.graphPartial or 0) + 1
            emit("road_graph_partial", { towns = #Graph.towns, expected = exported.expected })
        else
            for key, value in pairs(exported) do store[key] = value end
        end
    end
    return true
end

local function factionLabel(factionId)
    if type(Offline.adapters.factionName) == "function" then return Offline.adapters.factionName(factionId) end
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(factionId) or nil
    local name = faction ~= nil and type(faction.general) == "table" and faction.general.name or nil
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function Offline.weightSpan(total)
    local rules = ProjectALife.FactionSpawnRules
    local reference = type(rules) == "table" and tonumber(rules.referenceWeight) or nil
    return math.max(total, reference or 0)
end

function Offline.censusSeats(size, factionId, hours)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusAdmit) ~= "function" then return size end
    return census.censusAdmit(size, factionId, hours)
end

function Offline.drawMembers(roster, size)
    local catalog = ProjectALife.Catalog
    local draw = ProjectALife.RosterDraw
    local drawn = draw ~= nil and draw.begin() or nil
    local members = {}
    for index = 1, size do
        local profile = roster[1 + (index - 1) % #roster]
        if drawn ~= nil and catalog and catalog.weightedProfile then
            profile = draw.pick(roster, drawn, roll)
        elseif catalog and catalog.weightedProfile then
            profile = catalog.weightedProfile(roster, roll())
        end
        if profile == nil then return nil, "roster_unseen" end
        members[#members + 1] = { profileId = tostring(profile.id or profile), health = 100 }
    end
    return members
end

function Offline.factionCounts()
    local counts = {}
    Ledger.eachLive(function(squad)
        local id = squad.factionId
        if id ~= nil then counts[id] = (counts[id] or 0) + 1 end
    end)
    return counts
end

Offline.diversityStep = 0.5
Offline.factionShareCap = 0.12
Offline.factionShareFloor = 2

function Offline.factionFull(counts, factionId)
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    local cap = math.max(Offline.factionShareFloor, math.ceil(total * Offline.factionShareCap))
    return (counts[factionId] or 0) >= cap
end

local function foundSquad(hours, initialTown)
    local players = initialTown == nil and playerPositions() or {}
    local candidates = {}
    local locks = ProjectALife.RegionLocks
    for _, id in ipairs(Graph.towns) do
        if initialTown == nil or initialTown == id then
            local node = Graph.nodes[id]

            local closed = node.seeded == true
                or (locks ~= nil and type(locks.refuse) == "function" and locks.refuse(node.x, node.y))
                or not ProjectALife.WorldPressure.available(node.x, node.y, 0, hours, nil, initialTown ~= nil)
            if not closed and nearestPlayerDistance(node.x, node.y, players) >= Offline.settings.foundPlayerDistance then
                candidates[#candidates + 1] = id
            end
        end
    end
    if #candidates == 0 then return nil, "no_town_clear_of_players" end

    local factions, weights, spawns, total, rawTotal = {}, {}, {}, 0, 0
    local clock = hourOfDay()
    local counts = Offline.factionCounts()
    local availableRosters = rosters()
    for pass = 1, 2 do
    if pass == 2 then factions, weights, spawns, total, rawTotal = {}, {}, {}, 0, 0 end
    for factionId, roster in pairs(availableRosters) do
        local catalog = ProjectALife.Catalog
        local faction = catalog and catalog.faction(factionId)
        local roaming = faction and #ProjectALife.FactionSpawnRules.roamingEncounters(faction.spawn) > 0
        if type(roster) == "table" and #roster > 0 and roaming
                and (pass == 2 or not Offline.factionFull(counts, factionId))
                and ProjectALife.FactionSpawnRules.available(faction, hours / 24, clock) then
            factions[#factions + 1] = factionId
            spawns[factionId] = faction.spawn
            local base = ProjectALife.FactionSpawnRules.weightFor(faction, hours / 24)
            weights[factionId] = base / (1 + (counts[factionId] or 0) * Offline.diversityStep)
            rawTotal = rawTotal + base
            total = total + weights[factionId]
        end
    end
    if total > 0 and rawTotal > total then
        local keep = rawTotal / total
        for factionId, weight in pairs(weights) do weights[factionId] = weight * keep end
        total = rawTotal
    end
    if total > 0 then break end
    end
    table.sort(factions)
    local factionId, towns
    local span = Offline.weightSpan(total)
    while factionId == nil and #factions > 0 do
        local needle, at = roll() * span, #factions
        if span > total and needle >= total then
            if initialTown == nil then Offline.state.lastFoundHours = hours end
            return nil, "faction_weight"
        end
        for index, id in ipairs(factions) do
            needle = needle - weights[id]
            if needle < 0 then at = index; break end
        end
        local chosen = factions[at]
        local open = {}
        for _, id in ipairs(candidates) do
            local node = Graph.nodes[id]
            if ProjectALife.SpawnRegions.allows({ x = node.x, y = node.y, z = 0 }, spawns[chosen]) then
                open[#open + 1] = id
            end
        end
        if #open > 0 then
            factionId, towns = chosen, open
        else
            total = total - weights[chosen]
            span = total
            table.remove(factions, at)
        end
    end
    if factionId == nil then return nil, "no_rosters" end
    local townId
    if initialTown ~= nil then
        townId = towns[1 + math.floor(roll() * #towns) % #towns]
    else
        townId = Offline.refillNode(towns, nowMs(), hours)
        if townId == nil then return nil, "nodes_occupied" end
    end
    local node = Graph.nodes[townId]
    local roster = availableRosters[factionId]
    local catalog = ProjectALife.Catalog
    local faction = catalog and type(catalog.faction) == "function" and catalog.faction(factionId) or {}
    local size, partyKind = ProjectALife.PartyPolicy.choose(faction, roll, 1, Ledger.settings.membersMaximum)
    if size <= 0 then return nil, "party_disabled" end
    local seats, short = Offline.censusSeats(size, factionId, hours)
    if seats < 1 then return nil, short or "census_exhausted" end
    size = math.min(size, seats)
    local members, drawError = Offline.drawMembers(roster, size)
    if members == nil then return nil, drawError end
    local pressure = ProjectALife.WorldPressure
    local ticket, refusal = Offline.timed("reserve", pressure.reserve, { id = "offline:" .. tostring(townId) .. ":" .. tostring(hours),
        x = node.x, y = node.y, z = 0, hours = hours, seed = initialTown ~= nil })
    if ticket == nil then return nil, refusal end
    local squad, createError = Offline.timed("create", Ledger.create, {
        name = (factionLabel(factionId) or Offline.placeName(townId, node)) .. " "
            .. (type(Ledger.nextSuffix) == "function" and Ledger.nextSuffix() or string.char(65 + (Ledger.metrics.created % 26))),
        factionId = factionId, x = node.x, y = node.y, nodeId = townId, homeNodeId = townId,
        members = members, partyKind = partyKind, foundedHours = hours, decisionDueHours = hours,
    })
    if squad ~= nil then
        Offline.timed("commit", pressure.commit, ticket, hours, squad.id)
        Offline.metrics.founded = Offline.metrics.founded + 1
        Offline.noteSquadAt(node, townId)
        emit("offline_founded", { squad = squad.id, name = squad.name, faction = factionId,
            town = townId, members = #members })
    else pressure.release(ticket, hours) end
    return squad, createError
end

function Offline.stableRoll(key)
    local value = 7
    key = tostring(key or "")
    for index = 1, #key do value = (value * 131 + string.byte(key, index)) % 2147483647 end
    return (value - math.floor(value / 10000) * 10000) / 10000
end

function Offline.bucketOf(id, node)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.at) ~= "function" or type(node) ~= "table" then return id end
    local at = regions.at(node)
    if at ~= nil then return at.id end
    if type(regions.distanceToTown) == "function" then
        local distance, town = regions.distanceToTown(node)
        if distance ~= nil and town ~= nil and distance <= Offline.settings.spreadMargin then return town.id end
    end
    return "rural"
end

function Offline.bucketBefore(a, b)
    if a == "rural" or b == "rural" then return b == "rural" and a ~= "rural" end
    return a < b
end

function Offline.spreadOrder(towns, nodes)
    local buckets, keys, bucketOf = {}, {}, {}
    for _, id in ipairs(towns or {}) do
        local key = Offline.bucketOf(id, nodes[id])
        local list = buckets[key]
        if list == nil then
            list = {}
            buckets[key] = list
            keys[#keys + 1] = key
        end
        list[#list + 1] = id
        bucketOf[id] = key
    end
    table.sort(keys, Offline.bucketBefore)
    local regions, locks = ProjectALife.TownRegions, ProjectALife.RegionLocks
    for _, key in ipairs(keys) do
        local box = regions ~= nil and type(regions.get) == "function" and regions.get(key) or nil
        local rank = {}
        for _, id in ipairs(buckets[key]) do
            local node = nodes[id] or { x = 0, y = 0 }
            if box ~= nil then
                local dx, dy = node.x - (box.minX + box.maxX) / 2, node.y - (box.minY + box.maxY) / 2
                rank[id] = dx * dx + dy * dy
            else
                rank[id] = Offline.stableRoll(id)
            end
            if node.seeded == true
                    or (locks ~= nil and type(locks.locked) == "function" and locks.locked(node.x, node.y)) then
                rank[id] = rank[id] + 1e12
            end
        end
        table.sort(buckets[key], function(a, b)
            if rank[a] ~= rank[b] then return rank[a] < rank[b] end
            return a < b
        end)
    end
    local order, round, added = {}, 1, true
    while added do
        added = false
        for _, key in ipairs(keys) do
            local id = buckets[key][round]
            if id ~= nil then
                order[#order + 1] = id
                added = true
            end
        end
        round = round + 1
    end
    return order, bucketOf
end

function Offline.seedPlan()
    local state = Offline.state
    if state.seedOrder == nil or state.seedEpoch ~= Graph.epoch then
        state.seedOrder, state.seedBuckets = Offline.spreadOrder(Graph.towns, Graph.nodes)
        state.seedEpoch = Graph.epoch
        state.seedCursor = 0
    end
    return state.seedOrder, state.seedBuckets
end

function Offline.bucketAt(x, y)
    local state = Offline.state
    local cx, cy = math.floor(x / 32), math.floor(y / 32)
    local key = cx * 65536 + cy
    local memo = state.bucketMemo
    if memo == nil or (tonumber(state.bucketMemoSize) or 0) >= 4096 then
        memo = {}
        state.bucketMemo, state.bucketMemoSize = memo, 0
    end
    local known = memo[key]
    if known == nil then
        known = Offline.bucketOf(nil, { x = cx * 32 + 16, y = cy * 32 + 16 }) or false
        memo[key] = known
        state.bucketMemoSize = state.bucketMemoSize + 1
    end
    return known or nil
end

function Offline.census(now)
    local state = Offline.state
    local census = state.census
    now = tonumber(now) or nowMs()
    if census ~= nil and now < (tonumber(state.censusUntilMs) or 0) then return census end
    census = { cells = {}, towns = {} }
    local cell = Offline.settings.occupiedRadius
    for _, brief in ipairs(Ledger.briefs()) do
        local x, y = tonumber(brief.x), tonumber(brief.y)
        if brief.state ~= "wiped" and x ~= nil and y ~= nil then
            census.cells[math.floor(x / cell) * 65536 + math.floor(y / cell)] = true
            local key = Offline.bucketAt(x, y)
            if key ~= nil then census.towns[key] = (census.towns[key] or 0) + 1 end
        end
    end
    state.census, state.censusUntilMs = census, now + Offline.settings.censusMs
    return census
end

function Offline.noteSquadAt(node, id)
    local census = Offline.state.census
    if census == nil or type(node) ~= "table" then return end
    local cell = Offline.settings.occupiedRadius
    census.cells[math.floor(node.x / cell) * 65536 + math.floor(node.y / cell)] = true
    local key = Offline.bucketAt(node.x, node.y)
    if key ~= nil then census.towns[key] = (census.towns[key] or 0) + 1 end
end

function Offline.nodeOccupied(node, now)
    if type(node) ~= "table" then return true end
    local cells = Offline.census(now).cells
    local cell = Offline.settings.occupiedRadius
    local cx, cy = math.floor(node.x / cell), math.floor(node.y / cell)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if cells[(cx + dx) * 65536 + cy + dy] then return true end
        end
    end
    return false
end

function Offline.refillNode(towns, now, hours)
    hours = tonumber(hours) or worldHours()
    local census = Offline.census(now)
    local groups, keys = {}, {}
    for _, id in ipairs(towns) do
        local node = Graph.nodes[id]
        if not Offline.nodeOccupied(node, now)
                and ProjectALife.WorldPressure.available(node.x, node.y, 0, hours) then
            local key = Offline.bucketOf(id, node) or id
            local list = groups[key]
            if list == nil then
                list = {}
                groups[key] = list
                keys[#keys + 1] = key
            end
            list[#list + 1] = id
        end
    end
    if #keys == 0 then return nil end
    table.sort(keys)
    local fewest, tied = math.huge, {}
    for _, key in ipairs(keys) do
        local live = census.towns[key] or 0
        if live < fewest then fewest, tied = live, { key }
        elseif live == fewest then tied[#tied + 1] = key end
    end
    local list = groups[tied[1 + math.floor(roll() * #tied) % #tied]]
    return list[1 + math.floor(roll() * #list) % #list]
end

function Offline.seedPerTown()
    local hibernation = ProjectALife.Hibernation
    local floor = hibernation ~= nil and hibernation.seedPerTown() or 2
    return math.max(floor, math.ceil((tonumber(Offline.settings.squadCap) or 0) / 60))
end

function Offline.seedClear(node, players)
    local hibernation = ProjectALife.Hibernation
    local tiles = hibernation ~= nil and hibernation.seedClearTiles() or 0
    if tiles <= 0 then return false end
    return nearestPlayerDistance(node.x, node.y, players) < tiles
end

function Offline.nextSeedNode(now)
    local order = Offline.seedPlan()
    local count = #order
    if count == 0 then return nil end
    local state, locks = Offline.state, ProjectALife.RegionLocks
    local limit = Offline.seedPerTown()
    local players = nil
    for _ = 1, count do
        local index = (tonumber(state.seedCursor) or 0) % count + 1
        state.seedCursor = index
        local id = order[index]
        local node = Graph.nodes[id]
        local seeded = Ledger.townSeedCount(id)
        if seeded == nil then return nil end
        local closed = node == nil or node.seeded == true
            or (locks ~= nil and type(locks.locked) == "function" and locks.locked(node.x, node.y))
        if not closed then
            local hibernation = ProjectALife.Hibernation
            if hibernation ~= nil and hibernation.seedClearTiles() > 0 then
                players = players or playerPositions()
                closed = Offline.seedClear(node, players)
            end
        end
        if not closed and seeded < limit and not Offline.nodeOccupied(node, now) then return id end
    end
    return nil
end

function Offline.travelTarget(here, routes)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.at) ~= "function" or type(routes) ~= "table" then return nil end
    local order, bucketOf = Offline.seedPlan()
    local own, locks = bucketOf[here], ProjectALife.RegionLocks
    local groups, keys = {}, {}
    for _, id in ipairs(order) do
        local key = bucketOf[id]
        if key ~= own and key ~= "rural" and id ~= here then
            local node, len = Graph.nodes[id], routes.distances[id]
            local closed = node == nil or node.seeded == true
                or (locks ~= nil and type(locks.locked) == "function" and locks.locked(node.x, node.y))
            if not closed and len ~= nil and len < math.huge then
                local list = groups[key]
                if list == nil then
                    list = {}
                    groups[key] = list
                    keys[#keys + 1] = key
                end
                list[#list + 1] = id
            end
        end
    end
    if #keys == 0 then return nil end
    table.sort(keys)
    local towns = Offline.census().towns
    local total, weights = 0, {}
    for index, key in ipairs(keys) do
        weights[index] = 1 / (1 + (towns[key] or 0))
        total = total + weights[index]
    end
    local needle, chosen = roll() * total, keys[#keys]
    for index, key in ipairs(keys) do
        needle = needle - weights[index]
        if needle < 0 then
            chosen = key
            break
        end
    end
    local list = groups[chosen]
    return list[1 + math.floor(roll() * #list) % #list]
end

function Offline.seedTown(hours, now)
    if Offline.adapters.seedTowns == false then return 0 end
    if now < (Offline.state.nextSeedAtMs or 0) then return 0 end
    Offline.state.nextSeedAtMs = now + 1000
    local pressure = ProjectALife.WorldPressure ~= nil and ProjectALife.WorldPressure.at(hours) or 1
    local cap = math.min(Ledger.settings.maximum, Offline.settings.squadCap)
    if cap > 0 then cap = math.max(math.min(3, cap), math.floor(cap * pressure + 0.5)) end

    local done = tonumber(Offline.state.seedDoneAt)
    if done ~= nil and cap <= done then return 0 end
    local order = Offline.seedPlan()
    if #order == 0 then return 0 end
    local lifetime = 0
    for _, town in ipairs(order) do lifetime = lifetime + (Ledger.townSeedCount(town) or 0) end
    if lifetime >= cap then
        Offline.state.seedDoneAt = cap
        return 0
    end

    if Ledger.count() >= cap then
        Offline.state.nextSeedAtMs = now + Offline.settings.censusMs
        return 0
    end
    local id = Offline.nextSeedNode(now)
    if id == nil then
        Offline.state.nextSeedAtMs = now + Offline.settings.censusMs
        return 0
    end
    local squad = foundSquad(hours, id)
    if squad == nil then return 0 end
    Ledger.townSeedCount(id, true)
    Offline.state.lastFoundHours = hours
    return 1
end

function Offline.placeName(nodeId, node)
    if type(Graph.displayName) == "function" then return tostring(Graph.displayName(nodeId, node)) end
    return tostring(type(node) == "table" and node.name or nodeId)
end

local function labelFor(kind, nodeId, extra)
    local node = Graph.nodes[nodeId]
    local where = node and Offline.placeName(nodeId, node) or tostring(nodeId)
    if kind == "scavenge" then return "scavenge " .. where .. (extra and (" " .. extra) or "") end
    if kind == "patrol" then return "patrol " .. where end
    if kind == "travel" then return "travel to " .. where end
    if kind == "reinforce" then return "reinforce " .. where end
    if kind == "rest" then return "rest at " .. where end
    if kind == "return" then return "return to camp at " .. where end
    if kind == "fortify" then return "secure shelter in " .. where end
    return kind
end
Offline.labelFor = labelFor

local function neighboursOf(nodeId)
    local result = {}
    local locks = ProjectALife.RegionLocks
    for other, len in pairs(Graph.adjacency[nodeId] or {}) do

        local node = Graph.nodes[other]
        local closed = node == nil or node.seeded == true
            or (locks ~= nil and type(locks.refuse) == "function" and locks.refuse(node.x, node.y))
        if not closed then result[#result + 1] = { id = other, len = len } end
    end
    table.sort(result, function(a, b) return a.len < b.len end)
    return result
end

local function chooseTask(squad, hours)
    local hour = hourOfDay()

    local here = squad.nodeId
    if here == nil or Graph.nodes[here] == nil then here = Graph.nearest(squad.x, squad.y) end
    if here == nil then return nil end
    local catalog = ProjectALife.Catalog
    local faction = catalog and type(catalog.faction) == "function" and catalog.faction(squad.factionId)
    local allowed = faction and faction.spawn and ProjectALife.FactionSpawnRules.encounters(faction.spawn)
        or { roamer = true, patrol = true, scavenger_crew = true }
    local canPatrol = allowed.patrol or allowed.town_patrol

    if hour < 22 and hour >= 6 then
        local route
        local request = Ledger.takeReinforcement(function(candidate)
            if Graph.nodes[candidate.nodeId] == nil then return false end
            local factionId = candidate.factionId
            local registry = ProjectALife.OutpostRegistry
            if registry ~= nil and type(registry.read) == "function" then
                local site = registry.read(candidate.outpostId)
                if site == nil then return false end
                factionId = site.factionId
            end
            if factionId == nil then return false end
            if factionId ~= squad.factionId then
                local relations = ProjectALife.Relations
                if relations == nil or type(relations.status) ~= "function" then return false end
                local source = { uid = squad.id, factionId = squad.factionId }
                local target = { uid = "outpost:" .. candidate.outpostId, factionId = factionId }
                if relations.status(source, target) ~= "friendly"
                        or relations.status(target, source) ~= "friendly" then return false end
            end
            local candidateRoute = Graph.route(here, candidate.nodeId)
            if candidateRoute == nil then return false end
            route = candidateRoute
            return true
        end)
        if request ~= nil then
            return { kind = "reinforce", label = labelFor("reinforce", request.nodeId),
                dest = request.nodeId, outpostId = request.outpostId }, route
        end
    end
    local groupPlans = ProjectALife.GroupPlan
    if groupPlans ~= nil and type(groupPlans.offlineTask) == "function" then
        local goalOk, goalTask, goalRoute = pcall(groupPlans.offlineTask, squad, hours, here, allowed, hour)
        if goalOk and goalTask ~= nil then return goalTask, goalRoute end
    end
    local planned, plannedRoute = Offline.plannedTask(squad, hours, here, allowed, hour)
    if planned ~= nil then return planned, plannedRoute end
    local homeId = squad.homeNodeId
    if homeId ~= nil and homeId ~= here and Graph.nodes[homeId] ~= nil
            and not (squad.task and squad.task.kind == "return") then
        local settings = Offline.settings
        local evening = hour >= 18 and hour < 22
        local stocked = (tonumber(squad.supplies) or 0) >= settings.homeSuppliesFull
        local weary = (tonumber(squad.morale) or 0.65) < settings.homeWearyMorale
        local homeNode = Graph.nodes[homeId]
        local locks = ProjectALife.RegionLocks
        local closed = homeNode.seeded == true
            or (locks ~= nil and type(locks.refuse) == "function" and locks.refuse(homeNode.x, homeNode.y))
        if (evening or stocked or weary) and not closed and roll() < settings.homeReturnChance then
            local route = Graph.route(here, homeId)
            if route ~= nil and #route >= 2 then
                return { kind = "return", label = labelFor("return", homeId), dest = homeId }, route
            end
        end
    end
    if (hour >= 22 or hour < 6) and Offline.restsTonight(squad, hours, hour) then
        return { kind = "rest", label = labelFor("rest", here), dest = here }, { here }
    end
    local wants = roll()
    local near = neighboursOf(here)

    if (allowed.scavenger_crew or allowed.roamer or allowed.poi_defenders)
            and squad.supplies >= 25 and wants >= 0.45 and wants < 0.60
            and not (squad.task and squad.task.kind == "fortify") then
        return { kind = "fortify", label = labelFor("fortify", here), dest = here }, { here }
    end
    if allowed.scavenger_crew and (squad.supplies < 25 or wants < 0.45) then
        local target = near[1] and near[1].id or here

        return { kind = "scavenge", label = labelFor("scavenge", target),
            dest = target }, target == here and { here } or Graph.route(here, target)
    end
    if canPatrol and wants < 0.75 and #near >= 2 then

        local loop = { here, near[1].id, near[2].id, here }
        local route = {}
        for index = 1, #loop - 1 do
            local leg = Graph.route(loop[index], loop[index + 1])
            if leg == nil then route = nil break end
            for step = (index == 1 and 1 or 2), #leg do route[#route + 1] = leg[step] end
        end
        if route ~= nil then
            return { kind = "patrol", label = labelFor("patrol", here), dest = here }, route
        end
    end

    local locks = ProjectALife.RegionLocks
    local farthest, farLen = nil, -1

    local routes = nil
    if allowed.roamer then
        routes = type(Graph.treeFrom) == "function" and Graph.treeFrom(here) or Graph.routesFrom(here)
    end

    local target = routes ~= nil and Offline.travelTarget(here, routes) or nil
    if target ~= nil then
        return { kind = "travel", label = labelFor("travel", target), dest = target },
            Graph.route(here, target, routes)
    end
    for _, id in ipairs(allowed.roamer and Graph.towns or {}) do
        local node = Graph.nodes[id]
        local closed = node.seeded == true
            or (locks ~= nil and type(locks.refuse) == "function" and locks.refuse(node.x, node.y))
        if id ~= here and not closed then
            local len = routes and routes.distances[id]
            if len ~= nil and len < math.huge then
                if len > farLen then farthest, farLen = id, len end
            end
        end
    end
    if allowed.roamer and farthest ~= nil then
        return { kind = "travel", label = labelFor("travel", farthest), dest = farthest },
            Graph.route(here, farthest, routes)
    end
    if allowed.scavenger_crew and near[1] then
        local target = near[1].id
        return { kind = "scavenge", label = labelFor("scavenge", target), dest = target }, Graph.route(here, target)
    end
    if canPatrol then
        return { kind = "patrol", label = labelFor("patrol", here), dest = here }, { here }
    end
    return { kind = "rest", label = labelFor("rest", here), dest = here }, { here }
end

function Offline.activitiesOn()
    local planner = ProjectALife.ActivityPlanner
    return planner ~= nil and type(planner.enabled) == "function" and planner.enabled() == true
end

function Offline.plannedTask(squad, hours, here, allowed, hour)
    if not Offline.activitiesOn() then return nil end
    local planner = ProjectALife.ActivityPlanner
    local near = neighboursOf(here)
    local ctx = planner.offlineContext(squad, hours, hour, allowed, not Offline.restsTonight(squad, hours, hour))
    ctx.habitat = Graph.nodes[here] ~= nil and Graph.nodes[here].habitat or nil
    if near[1] ~= nil then ctx.routeTiles.scavenge = near[1].len end
    ctx.off = {}
    for _ = 1, 4 do
        local id = planner.decide(ctx)
        if id == nil then return nil end
        local task, route = Offline.taskForActivity(id, here, near, ctx.needs)
        if task ~= nil then return task, route end
        ctx.off[id] = true
    end
    return nil
end

function Offline.patrolLoop(here, near)
    if #near < 2 then return nil end
    local loop = { here, near[1].id, near[2].id, here }
    local route = {}
    for index = 1, #loop - 1 do
        local leg = Graph.route(loop[index], loop[index + 1])
        if leg == nil then return nil end
        for step = (index == 1 and 1 or 2), #leg do route[#route + 1] = leg[step] end
    end
    return route
end

function Offline.routeTree(here)
    local tree = nil
    if type(Graph.treeFrom) == "function" then tree = Graph.treeFrom(here) end
    if tree == nil then tree = Graph.routesFrom(here) end
    return tree
end

function Offline.travelTown(here, tree)
    if tree == nil then return nil end
    local picked = Offline.travelTarget(here, tree)
    if picked ~= nil then return picked end
    local locks, best, bestLength = ProjectALife.RegionLocks, nil, -1
    for _, id in ipairs(Graph.towns) do
        local node = Graph.nodes[id]
        local length = type(tree.distances) == "table" and tree.distances[id] or nil
        local open = node ~= nil and node.seeded ~= true
            and not (locks ~= nil and type(locks.refuse) == "function" and locks.refuse(node.x, node.y))
        if id ~= here and open and length ~= nil and length < math.huge and length > bestLength then
            best, bestLength = id, length
        end
    end
    return best
end

function Offline.taskForActivity(id, here, near, needs)
    local catalog = ProjectALife.ActivityCatalog
    local row = catalog ~= nil and catalog.activities[id] or nil
    if row == nil or type(row.task) ~= "string" then return nil end
    local task, route
    if id == "scavenge" then
        local target = here
        if near[1] ~= nil then target = near[1].id end
        task = { kind = "scavenge", label = labelFor("scavenge", target), dest = target }
        route = { here }
        if target ~= here then route = Graph.route(here, target) end
    elseif id == "patrol_route" then
        route = Offline.patrolLoop(here, near)
        task = { kind = "patrol", label = labelFor("patrol", here), dest = here }
    elseif id == "travel" then
        local tree = Offline.routeTree(here)
        local target = Offline.travelTown(here, tree)
        if target == nil then return nil end
        task = { kind = "travel", label = labelFor("travel", target), dest = target }
        route = Graph.route(here, target, tree)
    else
        task = { kind = row.task, label = labelFor(row.task, here), dest = here }
        route = { here }
    end
    if route == nil then return nil end
    task.activityId = id
    task.wanted = ProjectALife.ActivityPlanner.lowest(needs)
    return task, route
end

function Offline.activityNeeds(q, elapsed)
    if not Offline.activitiesOn() then return false end
    local members = type(q.members) == "table" and #q.members or 0
    return ProjectALife.ActivityPlanner.serviceNeeds(q, members, elapsed)
end

function Offline.activityOwned(squad)
    return Offline.activitiesOn() and (squad.adoptedFrom ~= nil
        or (type(squad.activity) == "table" and (squad.activity.id == "fish" or squad.activity.id == "hunt")))
end

function Offline.applyTask(q, task, route, hours)
    local legs = {}
    if type(route) == "table" then
        for index = 2, #route do legs[#legs + 1] = route[index] end
    end
    q.task = task
    q.route = legs
    q.legFrom = (q.nodeId ~= nil and Graph.nodes[q.nodeId] ~= nil) and q.nodeId or Graph.nearest(q.x, q.y)
    q.legStartedHours = hours
    q.legHours = nil
    q.task.assignedHours = hours
    q.task.untilHours = hours + 0.75 + roll() * 1.25
    q.task.stationary = #legs == 0
    if #legs == 0 then

        q.decisionDueHours = q.task.untilHours
    end
    if q.task.activityId ~= nil then ProjectALife.ActivityPlanner.stampTask(q, q.task, hours) end
    return #legs
end

function Offline.noteTasked(id, task, legs)
    Offline.metrics.tasked = Offline.metrics.tasked + 1
    emit("offline_tasked", { squad = id, task = task.label, legs = legs, town = task.dest })
end

local function assignTask(squad, hours)
    local task, route = chooseTask(squad, hours)
    if task == nil then return false end
    local legs = 0
    local updated = Ledger.update(squad.id, squad.revision, function(q)
        legs = Offline.applyTask(q, task, route, hours)
    end)
    if updated ~= nil then Offline.noteTasked(squad.id, task, legs) end
    return updated ~= nil
end

local function arrive(q, hours)
    local task = q.task or {}
    if task.completedHours ~= nil then return end
    task.completedHours = hours
    if task.kind == "scavenge" then
        q.supplies = math.min(100, (q.supplies or 35)
            + Offline.settings.scavengeSupplies + roll() * Offline.settings.scavengeSupplies)
    elseif task.kind == "rest" then
        q.morale = math.min(1, (q.morale or 0.65) + Offline.settings.restMorale)
    elseif task.kind == "return" then
        q.morale = math.min(1, (q.morale or 0.65) + Offline.settings.restMorale * 0.5)
    end
    local hook = Offline.arrivals ~= nil and Offline.arrivals[task.kind] or nil
    if type(hook) == "function" then pcall(hook, q, task, hours) end
    local haul = ProjectALife.OfflineLoot
    if haul ~= nil then pcall(haul.onArrive, q, roll) end
    if Offline.activitiesOn() then ProjectALife.ActivityPlanner.arrive(q, task, roll(), hourOfDay()) end
    local groupPlans = ProjectALife.GroupPlan
    if groupPlans ~= nil and type(groupPlans.onArrive) == "function" then pcall(groupPlans.onArrive, q, task, hours) end
    q.decisionDueHours = hours + 0.4 + roll() * 1.2
    Offline.metrics.arrivals = Offline.metrics.arrivals + 1
end

function Offline.walkLegs(q, hours)

    for _ = 1, 8 do
        local from = q.legFrom
        if from == nil or Graph.nodes[from] == nil then from = Graph.nearest(q.x, q.y) end
        local to = q.route[1]
        local len = (Graph.adjacency[from] or {})[to]
        if len == nil then

            q.route = {}
            q.nodeId = from
            return
        end
        if q.legHours == nil then
            q.legHours = legHours(len, Offline.settings.travelTilesPerHour)
            q.legStartedHours = q.legStartedHours or hours
        end
        local t = (hours - q.legStartedHours) / q.legHours
        if t >= 1 then
            local node = Graph.nodes[to]
            q.x, q.y, q.nodeId = node.x, node.y, to
            table.remove(q.route, 1)
            q.legFrom, q.legStartedHours, q.legHours = to, q.legStartedHours + q.legHours, nil
            Offline.metrics.legs = Offline.metrics.legs + 1
            if #q.route == 0 then arrive(q, hours); return end
        else
            local p = Graph.interpolate(from, to, t)
            if p ~= nil then q.x, q.y = p.x, p.y end
            q.nodeId = nil
            return
        end
    end
end

Offline.nightWindow = { from = 22, to = 6 }

function Offline.restsTonight(squad, hours, hour)
    hour = tonumber(hour) or hourOfDay()
    local window = Offline.nightWindow
    if not (hour >= window.from or hour < window.to) then return false end
    local percent = 0
    pcall(function()
        local current = ProjectALife.Settings and ProjectALife.Settings.current
        local level = current and tonumber(current.nightActivity)
        local life = ProjectALife.ModuleIdleLife
        if level ~= nil and life ~= nil and type(life.nightActivityPercent) == "table" then
            percent = life.nightActivityPercent[math.max(1, math.min(5, math.floor(level)))]
        elseif level ~= nil then
            percent = ({ 0, 20, 45, 70, 95 })[math.max(1, math.min(5, math.floor(level)))]
        end
    end)

    local evening = (tonumber(hours) or 0) - hour - (hour < window.to and 24 or 0)
    local night = math.floor(evening / 24 + 0.5)
    local seed = 7
    local name = tostring(squad.id or "")
    for index = 1, #name do seed = (seed * 31 + string.byte(name, index)) % 9973 end
    seed = (seed * 131 + night * 17) % 100
    return seed >= percent
end

function Offline.serviceJob(hours, elapsed)
    local job = Offline.state.service
    if job == nil then
        job = {}
        Offline.state.service = job
    end
    job.hours, job.elapsed = hours, math.max(0, tonumber(elapsed) or 0)
    job.work, job.task, job.legs = 0, nil, 0
    return job
end

function Offline.serviceMutation(q)
    local job = Offline.state.service
    local hours, elapsed = job.hours, job.elapsed
    local hibernation = ProjectALife.Hibernation
    if hibernation ~= nil and hibernation.asleep(q) then
        hibernation.freeze(q, hours, elapsed)
        return
    end
    local members = type(q.members) == "table" and #q.members or 0
    q.supplies = math.max(0, (q.supplies or 35)
        - Offline.settings.supplyDrainPerMemberHour * members * elapsed)
    Offline.activityNeeds(q, elapsed)
    if q.supplies <= 0 then
        q.morale = math.max(0.1, (q.morale or 0.65) - Offline.settings.moraleDecayPerHour * elapsed)
    end
    q.lastSimulatedHours = hours
    if type(q.route) == "table" and #q.route > 0 then
        if Offline.restsTonight(q, hours) then

            if elapsed > 0 then
                if q.legStartedHours ~= nil then q.legStartedHours = q.legStartedHours + elapsed end
                q.nightCamp = true
            end
        else
            q.nightCamp = nil
            Offline.walkLegs(q, hours)
            job.work = job.work + 1
        end
    elseif hours >= (tonumber(q.decisionDueHours) or 0) then
        local task = q.task
        if task ~= nil and task.stationary == true and task.completedHours == nil
                and hours >= (tonumber(task.untilHours) or math.huge) then
            arrive(q, hours)
        end
        local chosen, route = chooseTask(q, hours)
        if chosen ~= nil then
            job.task, job.legs = chosen, Offline.applyTask(q, chosen, route, hours)
            job.work = job.work + 1
        end
    end
end

function Offline.stampMutation(q)
    Offline.activityNeeds(q, Offline.state.service.elapsed)
    q.lastSimulatedHours = Offline.state.service.hours
end

function Offline.noteServiceFault(failure)
    Offline.metrics.serviceFaults = (Offline.metrics.serviceFaults or 0) + 1
    local reason = tostring(failure or "unknown")
    if reason ~= Offline.state.lastServiceFault then
        Offline.state.lastServiceFault = reason
        emit("offline_service_fault", { reason = reason })
    end
end

local function upkeep(squad, elapsedHours, hours)
    Offline.serviceJob(hours, elapsedHours)
    local updated, failure = Ledger.update(squad.id, squad.revision, Offline.serviceMutation)
    if updated == nil and type(failure) == "string" and string.sub(failure, 1, 21) == "squad_mutation_failed" then
        Offline.noteServiceFault(failure)
    end
    return updated
end

function Offline.squadIds()
    local state, metrics = Offline.state, Ledger.metrics
    local store = Ledger.storage
    local order = type(store) == "table" and store.order or nil
    local memo = state.idsMemo
    if memo ~= nil and order ~= nil and memo.order == order and memo.size == #order
            and memo.sequence == store.sequence
            and memo.created == metrics.created and memo.removed == metrics.removed then
        return memo.ids, false
    end
    local ids = Ledger.ids()
    store = Ledger.storage
    order = type(store) == "table" and store.order or nil
    if order ~= nil then
        state.idsMemo = { order = order, size = #order, sequence = store.sequence,
            created = metrics.created, removed = metrics.removed, ids = ids }
    else
        state.idsMemo = nil
    end
    return ids, true
end

function Offline.serviceBatch(count, now)
    local state = Offline.state
    local interval = 1000
    local last = tonumber(state.lastServiceMs)
    if last ~= nil and now >= last then interval = math.max(100, math.min(1000, now - last)) end
    state.lastServiceMs = now
    local gap = math.max(1000, Offline.settings.tickSeconds * 1000)
    return math.max(Offline.settings.squadsPerSlice, math.ceil(count * interval / gap))
end

function Offline.serviceSquads(hours, now)
    local ids, changed = Offline.squadIds()
    local state = Offline.state
    local count, serviced, work = #ids, 0, 0
    if count == 0 then state.squadClocks = {}; state.squadCursor = 1; return 0 end
    local gap = Offline.settings.tickSeconds * 1000
    if changed then
        local present = {}
        for index, id in ipairs(ids) do
            present[id] = true
            if state.squadClocks[id] == nil then
                state.squadClocks[id] = { nextMs = now + (index - 1) * gap / count, lastHours = hours }
            end
        end
        for id in pairs(state.squadClocks) do if not present[id] then state.squadClocks[id] = nil end end
    end
    local batch = Offline.serviceBatch(count, now)
    local hibernation = ProjectALife.Hibernation
    if hibernation ~= nil and hibernation.tiles() > 0 and hibernation.stale(now) then hibernation.refresh(playerPositions(), now) end
    local started = nowMs()
    for _ = 1, count do
        if state.squadCursor > count then state.squadCursor = 1 end
        local index = state.squadCursor
        local id = ids[index]
        state.squadCursor = index + 1
        local clock = state.squadClocks[id]
        if clock == nil then
            clock = { nextMs = now + (index - 1) * gap / count, lastHours = hours }
            state.squadClocks[id] = clock
        end
        if now >= clock.nextMs then
            clock.nextMs = now + gap
            local squad = Ledger.peek(id)
            local elapsed = math.max(0, hours - (squad and tonumber(squad.lastSimulatedHours) or clock.lastHours))
            clock.lastHours = hours
            local job = Offline.serviceJob(hours, elapsed)
            local stamped = false
            if squad ~= nil and Offline.sweep(squad, hours) then
                work = work + 1
            elseif squad ~= nil and squad.state == "offline" then
                stamped = upkeep(squad, elapsed, hours) ~= nil
                if stamped then
                    work = work + job.work
                    if job.task ~= nil then Offline.noteTasked(id, job.task, job.legs) end
                end
            elseif squad ~= nil and squad.state == "rendered" and Offline.activityOwned(squad) then
                stamped = false
            elseif squad ~= nil and squad.state == "rendered"
                    and hours >= (tonumber(squad.task and squad.task.untilHours) or 0) then
                local render = ProjectALife.RenderProtocol
                if render and render.canRetask and render.canRetask(squad) then
                    squad = render.rebase(squad)
                    if assignTask(squad, hours) then
                        render.refreshTask(Ledger.read(id))
                        work = work + 1
                    end
                end
            end
            if not stamped then
                local fresh = Ledger.peek(id)
                if fresh ~= nil then
                    Offline.serviceJob(hours, elapsed)
                    Ledger.update(id, fresh.revision, Offline.stampMutation, true)
                end
            end
            serviced = serviced + 1
            Offline.metrics.squadUpdates = Offline.metrics.squadUpdates + 1
            if serviced >= batch or nowMs() - started >= Offline.settings.squadSliceMs then
                Offline.metrics.sliceYields = Offline.metrics.sliceYields + 1
                break
            end
        end
    end
    return work
end

function Offline.sweep(squad, hours)
    if squad.state ~= "wiped" then return false end
    if hours - (tonumber(squad.wipedHours) or hours) < Offline.settings.wipedSweepHours then return false end
    local fresh = Ledger.read(squad.id)
    if fresh ~= nil and Ledger.remove(fresh.id, fresh.revision, "swept") then
        Offline.metrics.swept = Offline.metrics.swept + 1
        return true
    end
    return false
end

function Offline.tick()
    if not Offline.enabled then return 0 end
    local hours = worldHours()
    local work = 0

    pcall(function()
        local render = ProjectALife.RenderProtocol
        if render ~= nil and type(render.tick) == "function" then work = work + (Offline.timed("render", render.tick, hours) or 0) end
    end)

    if not Graph.built then
        local ok, done = pcall(Offline.timed, "graph", ensureGraph)
        if not ok then
            Offline.metrics.graphFaults = (Offline.metrics.graphFaults or 0) + 1
            emit("road_graph_fault", { error = tostring(done) })
            return 0
        end
        if not done then return 0 end

        return work
    end
    if #Graph.towns == 0 then return 0 end
    local now = nowMs()
    local seeded = Offline.timed("seed", Offline.seedTown, hours, now)
    if seeded > 0 then

        Offline.timed("service", Offline.serviceSquads, hours, now)
        return work + seeded
    end
    local gap = Offline.settings.tickSeconds * 1000 + Offline.state.nextJitter
    if now - Offline.state.lastTickMs < gap then return work + Offline.timed("service", Offline.serviceSquads, hours, now) end
    Offline.state.lastTickMs = now
    Offline.state.nextJitter = math.floor((roll() - 0.5) * 6000)
    Offline.metrics.ticks = Offline.metrics.ticks + 1
    Offline.state.lastHours = hours

    if Telemetry ~= nil and type(Telemetry.flushOffline) == "function" then pcall(Telemetry.flushOffline) end

    Offline.state.beat = ((tonumber(Offline.state.beat) or 2) + 1) % 3
    local beat = Offline.state.beat

    local pressure = ProjectALife.WorldPressure ~= nil and ProjectALife.WorldPressure.at(hours) or 1
    local cap = Offline.settings.squadCap
    if cap > 0 then cap = math.max(math.min(3, cap), math.floor(cap * pressure + 0.5)) end
    if beat == 0 and Ledger.count() < cap
            and hours - Offline.state.lastFoundHours >= Offline.settings.foundGapHours / math.max(0.1, pressure) then
        local squad, reason = Offline.timed("found", foundSquad, hours)
        if squad ~= nil then
            Offline.state.lastFoundHours = hours
            work = work + 1
        else

            reason = tostring(reason or "unknown")
            Offline.metrics.foundRefused = Offline.metrics.foundRefused + 1
            if reason ~= Offline.state.lastFoundReason then
                Offline.state.lastFoundReason = reason
                emit("offline_found_refused", { reason = reason, squads = Ledger.count() })
            end
        end
    end

    if beat ~= 0 then
        pcall(function()
            local players = playerPositions()
            if beat == 1 then
                local combat = ProjectALife.OfflineCombat
                if combat ~= nil then work = work + (Offline.timed("combat", combat.tick, hours, players) or 0) end
            else
                local revenge = ProjectALife.Revenge
                if revenge ~= nil then work = work + (Offline.timed("revenge", revenge.tick, hours, players) or 0) end
            end
        end)
    end
    return work + Offline.timed("service", Offline.serviceSquads, hours, now)
end

return Offline
