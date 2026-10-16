require "ProjectALife/World/ALifeTownRegions"
require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/World/ALifeWorldPressure"

ProjectALife = ProjectALife or {}

local Welcome = {
    KEY = "townWelcome",
    settings = {
        enabled = true,
        perTown = 4,
        firstDayOnly = true,
        windowHours = 24,
        laterHours = 168,
        maxMembers = 3,
        delayMs = 40000,
        scanMs = 5000,
        retryMs = 20000,
        capRetryMs = 120000,
        nextGroupMs = 30000,
        maxAttempts = 10,
        minDistance = 50,
        maxDistance = 85,
        tries = 24,
        graceHours = 0.5,
        groupDistance = 60,
        jumpTiles = 150,
        calmMs = 60000,
        stances = { friendly = true, allied = true, neutral = true, careful = true },
        blocOrders = {
            { "family", "civilian", "worker", "rescue" },
            { "civilian", "family", "worker", "rescue" },
            { "rescue", "worker", "family", "civilian" },
        },
    },
    adapters = {},
    metrics = { welcomed = 0, spawned = 0, refused = 0, capped = 0, lastRefusal = "none",
        near = 0, jumps = 0, calm = 0, existing = 0 },
    seen = {},
    retryAt = {},
    attempts = {},
    lastAt = {},
    calmUntil = {},
    noMemory = {},
    nextAtMs = 0,
}
ProjectALife.TownWelcome = Welcome

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

local function emit(category, fields)
    local telemetry = ProjectALife.Telemetry
    if telemetry ~= nil and type(telemetry.emit) == "function" then
        pcall(telemetry.emit, category, fields)
    end
end

function Welcome.configure(adapters)
    Welcome.adapters = type(adapters) == "table" and adapters or {}
    local a = Welcome.adapters
    if a.enabled ~= nil then Welcome.settings.enabled = a.enabled == true end
    if a.firstDayOnly ~= nil then Welcome.settings.firstDayOnly = a.firstDayOnly == true end
    if tonumber(a.perTown) ~= nil then
        Welcome.settings.perTown = math.max(1, math.min(6, math.floor(tonumber(a.perTown))))
    end
end

function Welcome.reset()
    Welcome.seen, Welcome.retryAt, Welcome.attempts, Welcome.nextAtMs = {}, {}, {}, 0
    Welcome.lastAt, Welcome.calmUntil = {}, {}
    Welcome.metrics = { welcomed = 0, spawned = 0, refused = 0, capped = 0, lastRefusal = "none",
        near = 0, jumps = 0, calm = 0, existing = 0 }
end

function Welcome.load()
    local actors = Welcome.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.getWorldValue) ~= "function" then return nil end
    local saved = actors.getWorldValue(Welcome.KEY)
    if type(saved) ~= "table" then saved = {} end
    if type(saved.towns) ~= "table" then saved.towns = {} end
    if type(saved.players) ~= "table" then saved.players = {} end
    if type(saved.counts) ~= "table" then saved.counts = {} end
    return saved
end

function Welcome.save(state)
    local actors = Welcome.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.setWorldValue) ~= "function" then return false end
    local count, oldest, oldestHours = 0, nil, math.huge
    for name, at in pairs(state.players) do
        count = count + 1
        if (tonumber(at) or 0) < oldestHours then oldest, oldestHours = name, tonumber(at) or 0 end
    end
    if count > 512 and oldest ~= nil then state.players[oldest] = nil end
    return actors.setWorldValue(Welcome.KEY, state) == true
end

function Welcome.players()
    if type(Welcome.adapters.players) == "function" then return Welcome.adapters.players() or {} end
    local result = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        for _, player in ipairs(locator.list()) do
            local position = locator.position(player)
            if position ~= nil then
                position.player = player
                result[#result + 1] = position
            end
        end
    end)
    return result
end

function Welcome.keyOf(player)
    local name
    if type(player.getUsername) == "function" then name = player:getUsername() end
    if name == nil or name == "" then name = "sp" end
    return tostring(name)
end

function Welcome.survived(player)
    if type(player.getHoursSurvived) ~= "function" then return nil end
    local hours = tonumber(player:getHoursSurvived())
    if hours == nil or hours ~= hours then return nil end
    return hours
end

function Welcome.given(state, key, hours, survived)
    local mark = tonumber(state.players[key])
    if mark == nil or mark < (hours - survived) - 1 then return 0 end
    local counts = type(state.counts) == "table" and state.counts or {}
    return math.max(1, math.floor(tonumber(counts[key]) or 1))
end

function Welcome.welcomed(state, key, hours, survived)
    return Welcome.given(state, key, hours, survived) >= Welcome.settings.perTown
end

function Welcome.livingGroups()
    local alive = {}
    local actors = Welcome.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.each) ~= "function" then return alive end
    actors.each(function(record)
        local memory = record.memory
        if record.lifecycle ~= "dead" and type(memory) == "table" and memory.groupId ~= nil then
            alive[tostring(memory.groupId)] = true
        end
    end)
    return alive
end

function Welcome.living(state, townId, hours, alive)
    local row = state.towns[townId]
    if type(row) ~= "table" or type(row.groups) ~= "table" then return 0, false end
    alive = alive or Welcome.livingGroups()
    local kept = {}
    for _, group in ipairs(row.groups) do
        if type(group) == "table" and (alive[tostring(group.id)]
                or hours - (tonumber(group.at) or -1e9) < Welcome.settings.graceHours) then
            kept[#kept + 1] = group
        end
    end
    local changed = #kept ~= #row.groups
    row.groups = kept
    return #kept, changed
end

function Welcome.positionOf(record)
    local watchdog = ProjectALife.Watchdog
    local bindings = watchdog ~= nil and watchdog.bindings or nil
    local binding = type(bindings) == "table" and bindings[record.uid] or nil
    local shell = type(binding) == "table" and binding.shell or nil
    if shell ~= nil and type(shell.getX) == "function" and type(shell.getY) == "function" then
        local okX, x = pcall(shell.getX, shell)
        local okY, y = pcall(shell.getY, shell)
        x, y = tonumber(x), tonumber(y)
        if okX and okY and x ~= nil and y ~= nil then return x, y end
    end
    local placed = record.worldPosition
    if type(placed) ~= "table" then return nil, nil end
    return tonumber(placed.x), tonumber(placed.y)
end

function Welcome.groupKey(record, memory)
    if memory.outpostId ~= nil and memory.outpostSquadId == nil then
        return "site:" .. tostring(memory.outpostId)
    end
    local key = memory.squadId or memory.groupId or memory.outpostSquadId
    if key == nil then return "solo:" .. tostring(record.uid) end
    return tostring(key)
end

function Welcome.claim(census, key)
    local group = census.groups[key]
    if group ~= nil and not group.inTown then
        group.inTown = true
        census.inTown = census.inTown + 1
    end
end

function Welcome.note(census, key, x, y)
    local group = census.groups[key]
    if group == nil then
        group = { key = key, inTown = false, placed = false }
        census.groups[key] = group
        census.total = census.total + 1
    end
    if x == nil or y == nil then return group end
    group.placed = true
    census.points[#census.points + 1] = { x = x, y = y, key = key }
    if not group.inTown then
        local probe = census.probe
        probe.x, probe.y = x, y
        if ProjectALife.TownRegions.contains(probe, census.town) then Welcome.claim(census, key) end
    end
    return group
end

function Welcome.noteSquad(census, squad)
    local key = tostring(squad.id)
    if squad.adoptedGroupId ~= nil then census.byGroupId[tostring(squad.adoptedGroupId)] = key end
    local known = census.groups[key]
    if known ~= nil and known.placed then return nil end
    Welcome.note(census, key, tonumber(squad.x), tonumber(squad.y))
    local head = type(squad.stageHead) == "table" and squad.stageHead
        or (type(squad.stagePending) == "table" and squad.stagePending.head or nil)
    if type(head) == "table" then Welcome.note(census, key, tonumber(head.x), tonumber(head.y)) end
    return nil
end

function Welcome.noteRows(census, state, hours)
    local towns = type(state) == "table" and state.towns or nil
    if type(towns) ~= "table" then return end
    hours = tonumber(hours) or 0
    local grace = Welcome.settings.graceHours
    for id, row in pairs(towns) do
        if type(row) == "table" and type(row.groups) == "table" then
            for _, group in ipairs(row.groups) do
                if type(group) == "table" and group.id ~= nil then
                    local groupId = tostring(group.id)
                    local key = census.byGroupId[groupId]
                    if key == nil and hours - (tonumber(group.at) or -1e9) < grace then
                        key = groupId
                        Welcome.note(census, key, tonumber(group.x), tonumber(group.y))
                    end
                    if key ~= nil and id == census.town then Welcome.claim(census, key) end
                end
            end
        end
    end
end

function Welcome.census(townId, state, hours)
    local census = { town = townId, groups = {}, points = {}, byGroupId = {},
        inTown = 0, total = 0, probe = { x = 0, y = 0 } }
    local actors = Welcome.adapters.actors or ProjectALife.ActorRegistry
    if actors ~= nil and type(actors.each) == "function" then
        actors.each(function(record)
            if record.lifecycle == "dead" then return nil end
            local memory = type(record.memory) == "table" and record.memory or Welcome.noMemory
            local key = Welcome.groupKey(record, memory)
            if memory.groupId ~= nil then census.byGroupId[tostring(memory.groupId)] = key end
            local x, y = Welcome.positionOf(record)
            Welcome.note(census, key, x, y)
            return nil
        end)
    end
    local ledger = Welcome.adapters.ledger or ProjectALife.SquadLedger
    if ledger ~= nil and type(ledger.eachLive) == "function" then
        ledger.eachLive(function(squad)
            return Welcome.noteSquad(census, squad)
        end)
    end
    local outposts = Welcome.adapters.outposts or ProjectALife.OutpostRegistry
    if outposts ~= nil and type(outposts.list) == "function" then
        for _, site in ipairs(outposts.list()) do
            local x, y = tonumber(site.x), tonumber(site.y)
            if site.state ~= "expired" and x ~= nil and y ~= nil then
                census.points[#census.points + 1] = { x = x, y = y, key = "site:" .. tostring(site.id) }
            end
        end
    end
    Welcome.noteRows(census, state, hours)
    return census
end

function Welcome.clearOfGroups(point, census)
    local points = type(census) == "table" and census.points or nil
    if points == nil then return true end
    local limit = Welcome.settings.groupDistance
    limit = limit * limit
    local x, y = point.x, point.y
    for index = 1, #points do
        local other = points[index]
        local dx, dy = other.x - x, other.y - y
        if dx * dx + dy * dy < limit then return false, other.key end
    end
    return true
end

function Welcome.track(key, entry, now)
    local x, y = tonumber(entry.x), tonumber(entry.y)
    if x == nil or y == nil then return false end
    local last = Welcome.lastAt[key]
    if last == nil then
        Welcome.lastAt[key] = { x = x, y = y }
        return false
    end
    local dx, dy = x - last.x, y - last.y
    last.x, last.y = x, y
    local jump = Welcome.settings.jumpTiles
    if dx * dx + dy * dy <= jump * jump then return false end
    Welcome.calmUntil[key] = now + Welcome.settings.calmMs
    Welcome.metrics.jumps = Welcome.metrics.jumps + 1
    return true
end

function Welcome.allowed(faction, bloc)
    local rules = ProjectALife.FactionSpawnRules
    if type(faction) ~= "table" or rules.blocOf(faction) ~= bloc then return false end
    local stance = type(faction.relations) == "table" and faction.relations.player or nil
    if stance == nil or Welcome.settings.stances[stance] ~= true or rules.hostile(faction) then return false end
    return (tonumber(faction.spawn and faction.spawn.most) or 1) >= 2
end

function Welcome.pickFaction(point, day, hour, unit)
    local rules, catalog = ProjectALife.FactionSpawnRules, ProjectALife.Catalog and ProjectALife.Catalog.current
    if rules == nil or catalog == nil then return nil end
    local orders = Welcome.settings.blocOrders
    local order = orders[1 + math.floor(math.max(0, math.min(0.999, unit)) * #orders)] or orders[1]
    for _, bloc in ipairs(order) do
        local faction = rules.pick(catalog, point, nil, roll(1000) / 1000, nil, day, hour, nil,
            function(candidate) return Welcome.allowed(candidate, bloc) end)
        if faction ~= nil then return faction end
    end
    return nil
end

function Welcome.squareLoaded(point)
    if type(getCell) ~= "function" then return true end
    local ok, loaded = pcall(function()
        local cell = getCell()
        return cell ~= nil and cell:getGridSquare(math.floor(point.x), math.floor(point.y), 0) ~= nil
    end)
    return not ok or loaded == true
end

function Welcome.pickPoint(player, townId, census)
    local s = Welcome.settings
    local px, py = player:getX(), player:getY()
    local policy = ProjectALife.SpawnPolicy
    local regions = ProjectALife.TownRegions
    local fairness = ProjectALife.SpawnFairness
    local fair = fairness ~= nil and fairness.enabled() and not fairness.graceActive()
    local crowded, unloaded = false, false
    for _ = 1, s.tries do
        local point
        if fair then
            local low, high = fairness.band(px, py)
            point = fairness.ringPoint(px, py, low, high)
        else
            local angle = roll(360) * math.pi / 180
            local distance = s.minDistance + roll(math.max(1, s.maxDistance - s.minDistance + 1))
            point = { x = math.floor(px + math.cos(angle) * distance),
                y = math.floor(py + math.sin(angle) * distance), z = 0 }
        end
        if point ~= nil and regions.contains(point, townId) then
            if not Welcome.clearOfGroups(point, census) then
                crowded = true
            elseif policy == nil or type(policy.clearOfRim) ~= "function" or policy.clearOfRim(point) then
                if Welcome.squareLoaded(point) then return point end
                unloaded = true
            end
        end
    end
    if crowded then return nil, "near_group" end
    if unloaded then return nil, "unloaded" end
    return nil
end

function Welcome.refuse(key, why, now)
    Welcome.metrics.refused = Welcome.metrics.refused + 1
    Welcome.metrics.lastRefusal = tostring(why)
    Welcome.attempts[key] = (Welcome.attempts[key] or 0) + 1
    Welcome.retryAt[key] = now + Welcome.settings.retryMs
    return false
end

function Welcome.hold(key, why, now)
    Welcome.metrics.near = Welcome.metrics.near + 1
    Welcome.metrics.lastRefusal = tostring(why)
    Welcome.retryAt[key] = now + Welcome.settings.retryMs
    return false
end

function Welcome.give(state, key, town, hours, result, count, faction, before, point)
    local row = state.towns[town.id]
    if type(row) ~= "table" then row = { groups = {} }; state.towns[town.id] = row end
    local entry = { id = tostring(result.groupId), at = hours }
    if type(point) == "table" then entry.x, entry.y = point.x, point.y end
    row.groups[#row.groups + 1] = entry
    if type(state.counts) ~= "table" then state.counts = {} end
    before = tonumber(before) or 0
    state.counts[key] = before + 1
    state.players[key] = hours
    if before == 0 then Welcome.metrics.welcomed = Welcome.metrics.welcomed + 1 end
    Welcome.save(state)
    Welcome.metrics.spawned = Welcome.metrics.spawned + 1
    emit("town_welcome", { town = town.id, faction = faction.id, count = count, player = key })
end

function Welcome.take(key, town, hours, groupId)
    local state = Welcome.load()
    if state == nil then return end
    local row = state.towns[town.id]
    if type(row) == "table" and type(row.groups) == "table" then
        for index = #row.groups, 1, -1 do
            if row.groups[index].id == tostring(groupId) then table.remove(row.groups, index) end
        end
    end
    if type(state.counts) ~= "table" then state.counts = {} end
    local left = math.max(0, math.floor(tonumber(state.counts[key]) or 1) - 1)
    state.counts[key] = left > 0 and left or nil
    if left == 0 then state.players[key] = nil end
    Welcome.save(state)
end

function Welcome.spawn(player, key, town, state, now, hours, before, census)
    local s = Welcome.settings
    local service = Welcome.adapters.service or ProjectALife.DebugService
    local definition = ProjectALife.Encounters.get("scavenger_crew")
    if service == nil or type(service.spawnEncounter) ~= "function" or definition == nil then
        return Welcome.refuse(key, "service_unavailable", now)
    end
    if census == nil then census = Welcome.census(town.id, state, hours) end
    local point, why = Welcome.pickPoint(player, town.id, census)
    if point == nil then
        if why == "near_group" then return Welcome.hold(key, why, now) end
        if why == "unloaded" then
            Welcome.metrics.unloaded = (Welcome.metrics.unloaded or 0) + 1
            return Welcome.hold(key, why, now)
        end
        return Welcome.refuse(key, "no_point", now)
    end
    local day, hour = hours / 24, math.floor((hours + 7) % 24)
    local faction = Welcome.pickFaction(point, day, hour, roll(1000) / 1000)
    if faction == nil then return Welcome.refuse(key, "no_faction", now) end
    local director = ProjectALife.EncounterDirector
    local wanted = director ~= nil and type(director.partySize) == "function"
        and director.partySize(faction, definition, roll(1000) / 1000) or 2
    wanted = math.max(1, math.min(s.maxMembers, wanted))
    if director ~= nil and type(director.capacityLeft) == "function" then
        wanted = math.min(wanted, director.capacityLeft())
    end
    if wanted <= 0 then return Welcome.refuse(key, "no_capacity", now) end
    local profiles = service.hostileProfileIds(wanted, math.floor(now), faction.id, true)
    if type(profiles) ~= "table" or #profiles == 0 then return Welcome.refuse(key, "no_profiles", now) end
    local requestId = "welcome:" .. town.id .. ":" .. key .. ":" .. tostring(math.floor(now))
    local ok, reason, result = ProjectALife.WorldPressure.spawn(service, player, {
        requestId = requestId,
        origin = "director",
        count = #profiles,
        profileIds = profiles,
        factionId = faction.id,
        x = point.x, y = point.y, z = 0,
        distance = 0, separation = 2, radius = 14,
        mode = definition.mode,
        profile = definition.profile,
        conducts = definition.conducts,
        animation = "normal",
        encounterId = definition.id,
        stance = definition.stance,
        startGroup = true,
    }, hours, { welcome = true })
    if not ok then return Welcome.refuse(key, reason or "spawn_refused", now) end
    if type(result) ~= "table" or type(result.groupId) ~= "string" then
        return Welcome.refuse(key, "no_group", now)
    end
    Welcome.give(state, key, town, hours, result, #profiles, faction, before, point)
    Welcome.retryAt[key] = now + s.nextGroupMs
    if type(service.watchGroup) == "function" then
        service.watchGroup(requestId, function(outcome)
            if type(outcome) == "table" and (tonumber(outcome.active) or 0) <= 0 then
                Welcome.take(key, town, hours, result.groupId)
                Welcome.refuse(key, "group_empty", nowMs())
            end
        end)
    end
    return true
end

function Welcome.consider(entry, now, hours)
    local s = Welcome.settings
    local player = entry.player
    if player == nil or type(player.getX) ~= "function" then return false end
    local key = Welcome.keyOf(player)
    local survived = Welcome.survived(player)
    if survived == nil then return false end
    if survived > (s.firstDayOnly and s.windowHours or s.laterHours) then return false end
    Welcome.track(key, entry, now)
    local first = Welcome.seen[key]
    if first == nil then
        Welcome.seen[key] = now
        return false
    end
    if now - first < s.delayMs or now < (Welcome.retryAt[key] or 0) then return false end
    if now < (Welcome.calmUntil[key] or 0) then
        Welcome.metrics.calm = Welcome.metrics.calm + 1
        return false
    end
    if (Welcome.attempts[key] or 0) >= s.maxAttempts then return false end
    local town = ProjectALife.TownRegions.at(entry)
    if town == nil then return false end
    local state = Welcome.load()
    if state == nil then return false end
    local before = Welcome.given(state, key, hours, survived)
    if before >= s.perTown then return false end
    local census = Welcome.census(town.id, state, hours)
    local _, changed = Welcome.living(state, town.id, hours, census.byGroupId)
    if changed then Welcome.save(state) end
    Welcome.metrics.existing = census.inTown
    if census.inTown >= s.perTown then
        Welcome.metrics.capped = Welcome.metrics.capped + 1
        Welcome.retryAt[key] = now + s.capRetryMs
        return false
    end
    return Welcome.spawn(player, key, town, state, now, hours, before, census)
end

function Welcome.tick(now, hours)
    if Welcome.settings.enabled ~= true then return 0 end
    now = tonumber(now) or nowMs()
    if now < Welcome.nextAtMs then return 0 end
    Welcome.nextAtMs = now + Welcome.settings.scanMs
    hours = tonumber(hours) or ProjectALife.WorldPressure.hours(0)
    for _, entry in ipairs(Welcome.players()) do
        if Welcome.consider(entry, now, hours) then return 1 end
    end
    return 0
end

function Welcome.summary()
    local m = Welcome.metrics
    return { spawned = m.spawned, refused = m.refused, capped = m.capped, lastRefusal = m.lastRefusal,
        near = m.near, jumps = m.jumps, calm = m.calm, existing = m.existing }
end

return Welcome
