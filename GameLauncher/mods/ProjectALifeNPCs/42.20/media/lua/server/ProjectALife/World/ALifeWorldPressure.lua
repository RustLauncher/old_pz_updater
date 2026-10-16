require "ProjectALife/World/ALifeRegionLedger"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Records/ALifeDifficultyPreset"
require "ProjectALife/Records/ALifeFactionSpawnRules"

ProjectALife = ProjectALife or {}

local Pressure = {
    settings = { fullDays = 3, floorDays = 21, floor = 0.35,
        crowdRadius = 240, crowdEarly = 4, crowdLater = 1,
        quietHours = 24, siteQuietHours = 168, pendingHours = 2, historyLimit = 256 },
    censusSettings = { size = 200, earlyPerWeek = 7, latePerWeek = 1, fadeDays = 28,
        clearedDays = 30, resettle = true, placeRadius = 20, siteRadius = 60,
        budgetFloor = 8, settleShare = 0.25, graves = 128, places = 128, factions = 512,
        highFloor = 2, townTiles = 150, roadTiles = 40, noiseTiles = 15, nearTiles = 150 },
    adapters = {},
    metrics = { crowded = 0, reserved = 0, committed = 0, released = 0,
        refused = 0, lastRefusal = "none", retryHours = 0,
        censusDeaths = 0, censusLosses = 0, censusArrivals = 0, censusRefused = 0,
        hidden = 0, floor = 0, inView = 0, cleared = 0 },
}
ProjectALife.WorldPressure = Pressure

function Pressure.at(hours)
    local s = Pressure.settings
    local days = (tonumber(hours) or 0) / 24
    if days <= s.fullDays then return 1 end
    if days >= s.floorDays then return s.floor end
    return 1 - (1 - s.floor) * (days - s.fullDays) / (s.floorDays - s.fullDays)
end

function Pressure.crowdCap(hours)
    local s = Pressure.settings
    local early = s.crowdEarly
    local gate = ProjectALife.FeatureGate
    if gate ~= nil and type(gate.number) == "function" then
        early = gate.number("Population_NeighbourGroups", s.crowdEarly, 1, 8)
    end
    if (tonumber(hours) or 0) / 24 <= s.fullDays then return early end
    return math.max(s.crowdLater, early - 1)
end

local function registry()
    return Pressure.adapters.actors or ProjectALife.ActorRegistry
end

function Pressure.excluded(skip, site, squad)
    return skip ~= nil and ((skip.site ~= nil and site == skip.site) or (skip.squad ~= nil and squad == skip.squad))
end

function Pressure.crowd(x, y, radius, exclude)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return 0 end
    radius = tonumber(radius) or Pressure.settings.crowdRadius
    local reach = radius * radius
    local groups, count = {}, 0
    local skip = type(exclude) == "table" and exclude or nil
    local actors = registry()
    if actors ~= nil and type(actors.each) == "function" then pcall(actors.each, function(record)
        if record.lifecycle == "dead" then return end
        local memory = type(record.memory) == "table" and record.memory or {}
        if Pressure.excluded(skip, memory.outpostId, memory.squadId) then return end
        local p = record.worldPosition
        if type(p) ~= "table" then return end
        local dx, dy = (tonumber(p.x) or 0) - x, (tonumber(p.y) or 0) - y
        if dx * dx + dy * dy > reach then return end
        local group
        if memory.outpostId ~= nil and memory.outpostSquadId == nil then group = "site:" .. tostring(memory.outpostId)
        else group = memory.squadId or memory.groupId or memory.outpostSquadId or ("solo:" .. tostring(record.uid)) end
        group = tostring(group)
        if not groups[group] then
            groups[group] = true
            count = count + 1
        end
    end) end
    local ledger = Pressure.adapters.ledger or ProjectALife.SquadLedger
    if ledger ~= nil and type(ledger.eachLive) == "function" then
        ledger.eachLive(function(squad)
            local sx, sy = tonumber(squad.x), tonumber(squad.y)
            if sx == nil or sy == nil or Pressure.excluded(skip, squad.homeOutpostId, squad.id) then return end
            local dx, dy = sx - x, sy - y
            if dx * dx + dy * dy > reach or groups[tostring(squad.id)] then return end
            groups[tostring(squad.id)] = true
            count = count + 1
        end)
    end
    return count
end

function Pressure.crowded(x, y, hours, exclude)
    local full = Pressure.crowd(x, y, nil, exclude) >= Pressure.crowdCap(hours)
    if full then Pressure.metrics.crowded = Pressure.metrics.crowded + 1 end
    return full
end

local function finite(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function stateAt(hours)
    local actors = registry()
    local epoch = actors and actors.worldState
    if Pressure.store ~= actors or Pressure.epoch ~= epoch or Pressure.history == nil then
        Pressure.store = actors
        Pressure.epoch = epoch
        local saved = actors and type(actors.getWorldValue) == "function"
            and actors.getWorldValue("worldPressure") or nil
        Pressure.history = { rows = {}, clock = hours }
        if type(saved) == "table" and type(saved.rows) == "table" then
            local count = 0
            for id, row in pairs(saved.rows) do
                if count >= Pressure.settings.historyLimit then break end
                if type(id) == "string" and #id > 0 and #id <= 160 and type(row) == "table"
                        and finite(row.x) and finite(row.y) and finite(row.z)
                        and finite(row.born) and finite(row.expires) and finite(row.born) <= hours
                        and finite(row.expires) > hours and finite(row.expires) <= finite(row.born) + 168 then
                    Pressure.history.rows[id] = {
                        x = finite(row.x), y = finite(row.y), z = finite(row.z), born = finite(row.born), expires = finite(row.expires),
                        centerX = finite(row.centerX) or finite(row.x), centerY = finite(row.centerY) or finite(row.y),
                        quietUntil = math.min(finite(row.expires), finite(row.quietUntil) or finite(row.expires)),
                        pending = row.pending == true,
                        site = type(row.site) == "string" and #row.site <= 128 and row.site or nil,
                        group = type(row.group) == "string" and #row.group <= 160 and row.group or nil,
                        owner = type(row.owner) == "string" and #row.owner <= 128 and row.owner or nil,
                    }
                    count = count + 1
                end
            end
        end
    end
    local state = Pressure.history
    for id, row in pairs(state.rows) do
        if row.expires <= hours or row.born > hours then state.rows[id] = nil end
    end
    return state
end

local function save(state, hours)
    local actors = registry()
    if actors == nil or type(actors.setWorldValue) ~= "function" then return false end
    state.clock = hours
    return actors.setWorldValue("worldPressure", state) == true
end

local function refuse(reason, retry)
    local m = Pressure.metrics
    m.refused = m.refused + 1
    m.lastRefusal = reason
    m.retryHours = retry or 0
    return nil, reason
end

function Pressure.reserve(options)
    options = type(options) == "table" and options or {}
    if options.bypass == true or options.restored == true then return { bypass = true } end
    local x, y, z, hours = finite(options.x), finite(options.y), finite(options.z or 0), finite(options.hours)
    local id = options.id
    if x == nil or y == nil or z == nil or hours == nil or type(id) ~= "string"
            or #id < 1 or #id > 160 then return refuse("pressure_input") end
    local state = stateAt(hours)
    if state.rows[id] then return refuse("pressure_replayed", state.rows[id].expires) end
    local site = type(options.site) == "string" and #options.site <= 128 and options.site or nil
    local centerX, centerY = finite(options.centerX) or x, finite(options.centerY) or y
    local reach = Pressure.settings.crowdRadius ^ 2
    local count = 0
    local own = type(options.crowdExclude) == "table" and options.crowdExclude or nil
    local ownKey = own ~= nil and own.siteKey or nil
    local seed = options.seed == true or options.welcome == true
    for _, row in pairs(state.rows) do
        count = count + 1
        local dx, dy = row.x - x, row.y - y
        local cx, cy = (row.centerX or row.x) - centerX, (row.centerY or row.y) - centerY
        local foreign = ownKey == nil or (row.site ~= ownKey and row.owner ~= ownKey)
        local localQuiet = foreign and (row.pending or (not seed and hours < (row.quietUntil or row.expires)))
        if (site ~= nil and row.site == site and foreign) or (localQuiet
                and (dx * dx + dy * dy <= reach or cx * cx + cy * cy <= reach)) then
            return refuse(row.pending and "pressure_pending" or "pressure_quiet", row.expires)
        end
    end
    if count >= Pressure.settings.historyLimit then return refuse("pressure_history_full") end
    if not seed and (Pressure.crowded(centerX, centerY, hours, own) or Pressure.crowded(x, y, hours, own)) then
        return refuse("pressure_crowded")
    end
    local regions = ProjectALife.RegionLedger
    if not seed and regions ~= nil then
        local sealed, why, ready = regions.blocked(x, y, hours)
        if sealed then return refuse(why, ready) end
    end
    if options.preview == true then return { preview = true } end
    local row = { x = x, y = y, z = z, born = hours, centerX = centerX, centerY = centerY,
        expires = hours + math.max(0.01, math.min(48, finite(options.pendingHours) or Pressure.settings.pendingHours)),
        pending = true, site = site, owner = ownKey }
    state.rows[id] = row
    if not save(state, hours) then
        state.rows[id] = nil
        return refuse("pressure_persistence")
    end
    Pressure.metrics.reserved = Pressure.metrics.reserved + 1
    return { id = id }
end

function Pressure.available(x, y, z, hours, site, seed)
    local ticket, reason = Pressure.reserve({ id = "pressure:preview", x = x, y = y, z = z,
        hours = hours, site = site, preview = true, seed = seed == true })
    return ticket ~= nil, reason
end

function Pressure.commit(ticket, hours, group)
    if type(ticket) ~= "table" then return false end
    if ticket.bypass then return true end
    hours = finite(hours)
    if hours == nil then return false end
    local state = stateAt(hours)
    local row = state.rows[ticket.id]
    if row == nil then return false end
    if not row.pending then
        if ticket.renew == true then return Pressure.renew(state, row, hours) end
        return true
    end
    local previous = { pending = row.pending, born = row.born, expires = row.expires, group = row.group, quietUntil = row.quietUntil }
    row.pending, row.born = false, hours
    local quiet = Pressure.settings.quietHours / Pressure.at(hours)
    row.quietUntil = hours + math.min(168, quiet)
    if row.site ~= nil then quiet = math.max(quiet, Pressure.settings.siteQuietHours) end
    row.expires = hours + math.min(168, quiet)
    row.group = type(group) == "string" and #group <= 160 and group or nil
    if not save(state, hours) then
        row.pending, row.born, row.expires, row.group = previous.pending, previous.born, previous.expires, previous.group
        row.quietUntil = previous.quietUntil
        return false
    end
    Pressure.metrics.committed = Pressure.metrics.committed + 1
    local regions = ProjectALife.RegionLedger
    if regions ~= nil then regions.noteSpawn(row.x, row.y, hours) end
    return true
end

function Pressure.renew(state, row, hours)
    local quiet = math.min(168, Pressure.settings.quietHours / Pressure.at(hours))
    local quietUntil, expires = row.quietUntil, row.expires
    row.quietUntil = math.min(row.born + 168, math.max(tonumber(row.quietUntil) or hours, hours + quiet))
    row.expires = math.min(row.born + 168, math.max(row.expires, row.quietUntil))
    if not save(state, hours) then
        row.quietUntil, row.expires = quietUntil, expires
        return false
    end
    return true
end

function Pressure.called(call, hours)
    return type(call) == "string" and finite(hours) ~= nil and stateAt(hours).rows[call] ~= nil
end

function Pressure.release(ticket, hours)
    if type(ticket) ~= "table" then return false end
    if ticket.bypass or ticket.renew == true then return true end
    hours = finite(hours)
    if hours == nil then return false end
    local state = stateAt(hours)
    local row = state.rows[ticket.id]
    if row == nil then return true end
    if not row.pending then return false end
    state.rows[ticket.id] = nil
    if not save(state, hours) then state.rows[ticket.id] = row; return false end
    Pressure.metrics.released = Pressure.metrics.released + 1
    return true
end

function Pressure.hours(fallback)
    if type(Pressure.adapters.hours) == "function" then return finite(Pressure.adapters.hours()) or fallback end
    if type(getGameTime) == "function" then
        local clock = getGameTime()
        if clock ~= nil and type(clock.getWorldAgeHours) == "function" then
            return finite(clock:getWorldAgeHours()) or fallback
        end
    end
    return fallback
end

function Pressure.pending(ticket, hours)
    if type(ticket) ~= "table" or finite(hours) == nil then return false end
    local row = stateAt(hours).rows[ticket.id]
    return row ~= nil and row.pending == true
end

function Pressure.spawn(service, player, args, hours, options, admin)
    if service == nil or type(service.spawnEncounter) ~= "function" then return false, "service_unavailable" end
    options = options or {}
    options.id, options.x, options.y, options.z, options.hours = args.requestId, args.x, args.y, args.z or 0, hours
    if player ~= nil and type(player.getX) == "function" and type(player.getY) == "function" then
        options.centerX, options.centerY = finite(player:getX()), finite(player:getY())
    end
    if options.crowdExclude == nil and args.outpostId ~= nil then
        options.crowdExclude = { site = args.outpostId, siteKey = args.siteKey }
    end
    local gate = Pressure.spawnGate(player, args, hours, options, admin)
    if gate ~= nil then return false, gate end
    local call = type(options.call) == "string" and #options.call <= 160 and options.call or nil
    if call ~= nil then options.id = call end
    local ticket, refusal
    if options.bypass ~= true and Pressure.pending(options.ticket, hours) then ticket = options.ticket
    elseif options.bypass ~= true and Pressure.called(call, hours) then ticket = { id = call, renew = true }
    else ticket, refusal = Pressure.reserve(options) end
    if ticket == nil then return false, refusal end
    local ok, reason, result = service.spawnEncounter(player, args, admin)
    if not ok then Pressure.release(ticket, hours); return ok, reason, result end
    if type(service.watchGroup) == "function" then
        service.watchGroup(args.requestId, function(outcome)
            if type(outcome) ~= "table" then return end
            local settled = Pressure.hours(hours)
            if (tonumber(outcome.active) or 0) > 0 then
                Pressure.commit(ticket, settled, type(result) == "table" and result.groupId or nil)
            else Pressure.release(ticket, settled) end
        end)
    elseif type(result) == "table" and result.completed == true then
        if (tonumber(result.active) or 0) > 0 then Pressure.commit(ticket, hours, result.groupId)
        else Pressure.release(ticket, hours) end
    end
    return ok, reason, result
end

function Pressure.mirror()
    return type(isClient) == "function" and isClient() == true
end

function Pressure.roll()
    if type(Pressure.adapters.roll) == "function" then return tonumber(Pressure.adapters.roll()) or 0 end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000000) / 1000000 end
    return 0.5
end

function Pressure.configureCensus(value)
    if type(value) ~= "table" then return false end
    local s = Pressure.censusSettings
    s.size = math.max(20, math.min(5000, math.floor(tonumber(value.censusSize) or s.size)))
    s.earlyPerWeek = math.max(0, math.min(100, tonumber(value.censusEarlyPerWeek) or s.earlyPerWeek))
    s.latePerWeek = math.max(0, math.min(100, tonumber(value.censusLatePerWeek) or s.latePerWeek))
    s.fadeDays = math.max(1, math.min(365, tonumber(value.censusFadeDays) or s.fadeDays))
    s.clearedDays = math.max(1, math.min(365, tonumber(value.censusClearedDays) or s.clearedDays))
    if type(value.censusResettle) == "boolean" then s.resettle = value.censusResettle end
    return true
end

function Pressure.censusClean(saved)
    local total = finite(saved.total)
    if total == nil or total < 1 then return nil end
    local s = Pressure.censusSettings
    local c = { v = 1, total = math.floor(total), born = finite(saved.born) or 0,
        dead = math.max(0, math.floor(finite(saved.dead) or 0)),
        arrived = math.max(0, math.floor(finite(saved.arrived) or 0)),
        carry = math.max(0, math.min(1, finite(saved.carry) or 0)),
        last = finite(saved.last) or finite(saved.born) or 0,
        settle = math.max(0, math.min(4, finite(saved.settle) or 0)),
        legacy = saved.legacy == true or nil, factions = {}, graves = {}, places = {} }
    local count = 0
    for id, row in pairs(type(saved.factions) == "table" and saved.factions or {}) do
        if count >= s.factions then break end
        if type(id) == "string" and #id > 0 and #id <= 128 and type(row) == "table" then
            local budget = finite(row.q)
            c.factions[id] = { d = math.max(0, math.floor(finite(row.d) or 0)),
                a = math.max(0, math.floor(finite(row.a) or 0)),
                q = budget ~= nil and math.max(1, math.floor(budget)) or nil }
            count = count + 1
        end
    end
    for index, uid in ipairs(type(saved.graves) == "table" and saved.graves or {}) do
        if index > s.graves then break end
        if type(uid) == "string" and #uid > 0 and #uid <= 64 then c.graves[#c.graves + 1] = uid end
    end
    count = 0
    for key, place in pairs(type(saved.places) == "table" and saved.places or {}) do
        if count >= s.places then break end
        if type(key) == "string" and #key > 0 and #key <= 160 and type(place) == "table"
                and finite(place.x) and finite(place.y) and finite(place.h) then
            c.places[key] = { x = finite(place.x), y = finite(place.y), h = finite(place.h) }
            count = count + 1
        end
    end
    return c
end

function Pressure.censusLoad()
    local actors = registry()
    local epoch = actors ~= nil and actors.worldState or nil
    if Pressure.censusLoaded == true and Pressure.censusStore == actors and Pressure.censusEpoch == epoch then
        return Pressure.census
    end
    Pressure.censusLoaded, Pressure.censusStore, Pressure.censusEpoch = true, actors, epoch
    Pressure.census = nil
    if actors ~= nil and type(actors.getWorldValue) == "function" then
        local saved = actors.getWorldValue("worldCensus")
        if type(saved) == "table" then Pressure.census = Pressure.censusClean(saved) end
    end
    return Pressure.census
end

function Pressure.censusSave()
    local c, actors = Pressure.census, registry()
    if c == nil or actors == nil or type(actors.setWorldValue) ~= "function" then return false end
    local saved = actors.setWorldValue("worldCensus", c) == true
    Pressure.censusDirty = not saved
    return saved
end

function Pressure.censusAdmin(record)
    local memory = type(record) == "table" and record.memory or nil
    return type(memory) == "table" and type(memory.admin) == "table"
end

function Pressure.censusHostile(factionId, fields)
    fields = type(fields) == "table" and fields or {}
    local value = fields.hostileOverride
    if value == true or value == "hostile" then return true end
    if value == false or value == "friendly" then return false end
    local stance = fields.spawnStance or fields.playerStance
    if stance == "hostile" then return true end
    if stance == "friendly" or stance == "neutral" or stance == "careful" or stance == "allied" then return false end
    local catalog, rules = ProjectALife.Catalog, ProjectALife.FactionSpawnRules
    if type(catalog) ~= "table" or type(catalog.faction) ~= "function"
            or type(rules) ~= "table" or type(rules.hostile) ~= "function" then return false end
    local faction = catalog.faction(factionId)
    return faction ~= nil and rules.hostile(faction) == true
end

function Pressure.censusTally(countHostiles)
    local factions, total, hostile = {}, 0, 0
    local actors = registry()
    if actors ~= nil and type(actors.each) == "function" then
        actors.each(function(record)
            if record.lifecycle ~= "dead" and not Pressure.censusAdmin(record) then
                local id = tostring(record.factionId or "?")
                factions[id] = (factions[id] or 0) + 1
                total = total + 1
                if countHostiles and Pressure.censusHostile(record.factionId, record.memory) then hostile = hostile + 1 end
            end
        end)
    end
    local squads = Pressure.adapters.ledger or ProjectALife.SquadLedger
    if type(squads) == "table" and type(squads.eachLive) == "function" then
        squads.eachLive(function(squad)
            local members = type(squad.members) == "table" and #squad.members or 0
            local rendered = type(squad.renderedUids) == "table" and #squad.renderedUids or 0
            if members > rendered then
                local id = tostring(squad.factionId or "?")
                factions[id] = (factions[id] or 0) + members - rendered
                total = total + members - rendered
                if countHostiles and Pressure.censusHostile(squad.factionId, squad) then hostile = hostile + members - rendered end
            end
        end)
    end
    local service = Pressure.adapters.service or ProjectALife.DebugService
    local queue = type(service) == "table" and service.queue or nil
    if type(queue) == "table" then
        for index = 1, #queue do
            local job = queue[index]
            if type(job) == "table" and job.admin == nil then
                local id = tostring(job.factionId or "?")
                factions[id] = (factions[id] or 0) + 1
                total = total + 1
                if countHostiles and Pressure.censusHostile(job.factionId, job) then hostile = hostile + 1 end
            end
        end
    end
    return { total = total, factions = factions, hostile = hostile }
end

function Pressure.censusEnsure(hours)
    if Pressure.mirror() then return nil end
    local actors = registry()
    if actors == nil or type(actors.setWorldValue) ~= "function" then return nil end
    local c = Pressure.censusLoad()
    if c ~= nil then return c end
    hours = finite(hours) or 0
    local size = Pressure.censusSettings.size
    local alive = Pressure.censusTally().total
    c = { v = 1, total = size, born = hours, dead = 0, arrived = 0, carry = 0, last = hours, settle = 0,
        factions = {}, graves = {}, places = {} }
    if alive > 0 then
        c.total = math.max(size, alive + math.floor(size / 4))
        c.legacy = true
    end
    Pressure.census = c
    Pressure.censusSave()
    return c
end

function Pressure.censusRate(hours)
    local s = Pressure.censusSettings
    local day = math.max(0, (tonumber(hours) or 0) / 24)
    local share = math.max(0, 1 - day / math.max(1, tonumber(s.fadeDays) or 28))
    return (s.latePerWeek + (s.earlyPerWeek - s.latePerWeek) * share) / 168
end

function Pressure.keptScale(faction)
    local scale = 1
    local balance = ProjectALife.RosterBalance
    if balance ~= nil and type(balance.keptScale) == "function" then scale = scale * balance.keptScale(faction) end
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.hostileFactionScale) == "function" then
        scale = scale * (tonumber(settings.hostileFactionScale(faction)) or 1)
    end
    return scale
end

function Pressure.censusBudget(c, id)
    local s = Pressure.censusSettings
    local catalog = ProjectALife.Catalog
    local current = type(catalog) == "table" and catalog.current or nil
    if type(current) ~= "table" or type(current.factionOrder) ~= "table" then return s.budgetFloor end
    if Pressure.censusOddsOf ~= current then
        local sum = 0
        for _, faction in ipairs(current.factionOrder) do
            local spawn = type(faction.spawn) == "table" and faction.spawn or {}
            if spawn.enabled ~= false and spawn.natural ~= false and spawn.visitorOnly ~= true then
                sum = sum + math.max(0, tonumber(spawn.odds) or 0) * Pressure.keptScale(faction)
            end
        end
        Pressure.censusOddsOf, Pressure.censusOddsSum = current, sum
    end
    local faction = type(catalog.faction) == "function" and catalog.faction(id) or nil
    local odds = type(faction) == "table" and type(faction.spawn) == "table"
        and math.max(0, tonumber(faction.spawn.odds) or 0) * Pressure.keptScale(faction) or 0
    local sum = tonumber(Pressure.censusOddsSum) or 0
    if sum <= 0 then return s.budgetFloor end
    return math.max(s.budgetFloor, math.floor(c.total * odds / sum + 0.5))
end

function Pressure.censusRow(c, id)
    if c == nil or type(id) ~= "string" or #id < 1 or #id > 128 then return nil end
    local row = c.factions[id]
    if row ~= nil then return row end
    local count = 0
    for _ in pairs(c.factions) do count = count + 1 end
    if count >= Pressure.censusSettings.factions then return nil end
    row = { d = 0, a = 0, q = Pressure.censusBudget(c, id) }
    c.factions[id] = row
    return row
end

function Pressure.censusArrive(c, hours)
    local catalog = ProjectALife.Catalog
    local current = type(catalog) == "table" and catalog.current or nil
    local rules = ProjectALife.FactionSpawnRules
    if type(current) ~= "table" or type(current.factionOrder) ~= "table" or type(rules) ~= "table"
            or type(rules.available) ~= "function" or type(rules.weightFor) ~= "function" then return nil end
    local day, hour = (tonumber(hours) or 0) / 24, math.floor(((tonumber(hours) or 0) + 7) % 24)
    local total, rows = 0, {}
    for _, faction in ipairs(current.factionOrder) do
        local spawn = type(faction.spawn) == "table" and faction.spawn or {}
        if spawn.visitorOnly ~= true and rules.available(faction, day, hour) then
            local weight = tonumber(rules.weightFor(faction, day, true)) or 0
            if weight > 0 then
                total = total + weight
                rows[#rows + 1] = { id = faction.id, ceiling = total }
            end
        end
    end
    if total <= 0 then return nil end
    local needle = math.max(0, math.min(0.999999, Pressure.roll())) * total
    for _, row in ipairs(rows) do
        if needle < row.ceiling then
            local entry = Pressure.censusRow(c, tostring(row.id))
            if entry ~= nil then entry.a = entry.a + 1 end
            return row.id
        end
    end
    return nil
end

function Pressure.censusAccrue(c, hours)
    hours = finite(hours)
    if c == nil or hours == nil then return 0 end
    local last = finite(c.last) or hours
    if hours <= last then
        if hours < last then c.last = hours end
        return 0
    end
    local added, at, steps = 0, last, 0
    while at < hours and steps < 4000 do
        local step = math.min(6, hours - at)
        c.carry = c.carry + Pressure.censusRate(at + step / 2) * step
        at, steps = at + step, steps + 1
        while c.carry >= 1 and c.arrived < c.dead do
            c.carry = c.carry - 1
            c.arrived = c.arrived + 1
            c.settle = math.min(4, c.settle + Pressure.censusSettings.settleShare)
            Pressure.censusArrive(c, at)
            added = added + 1
        end
        if c.arrived >= c.dead then c.carry = 0 end
    end
    c.last = hours
    Pressure.metrics.censusArrivals = Pressure.metrics.censusArrivals + added
    return added
end

function Pressure.censusStrength(faction)
    local id = type(faction) == "table" and faction.id or faction
    if type(id) ~= "string" then return 1 end
    local c = Pressure.censusLoad()
    local row = c ~= nil and c.factions[id] or nil
    if row == nil or row.d <= 0 then return 1 end
    local budget = (row.q or Pressure.censusSettings.budgetFloor) + row.a
    return math.max(0, 1 - row.d / math.max(1, budget))
end

function Pressure.censusVitality()
    local c = Pressure.censusLoad()
    if c == nil or c.total <= 0 then return 1 end
    return math.max(0, math.min(1, (c.total + c.arrived - c.dead) / c.total))
end

function Pressure.censusAdmit(count, factionId, hours, fields)
    count = math.max(1, math.floor(tonumber(count) or 1))
    local c = Pressure.censusEnsure(hours)
    if c == nil then return count end
    if Pressure.censusAccrue(c, finite(hours) or c.last) > 0 then Pressure.censusSave() end
    if factionId ~= nil and Pressure.censusStrength(factionId) <= 0 then
        Pressure.metrics.censusRefused = Pressure.metrics.censusRefused + 1
        return 0, "census_faction_spent"
    end
    local preset = ProjectALife.DifficultyPreset
    local limit = type(preset) == "table" and type(preset.hostileLimit) == "function" and preset.hostileLimit() or nil
    local tally = Pressure.censusTally(limit ~= nil)
    local room = c.total + c.arrived - c.dead - tally.total
    if room <= 0 then
        Pressure.metrics.censusRefused = Pressure.metrics.censusRefused + 1
        return 0, "census_exhausted"
    end
    if limit ~= nil and Pressure.censusHostile(factionId, fields) then
        local hostileRoom = math.max(0, limit - tally.hostile)
        if hostileRoom < count then
            Pressure.metrics.censusRefused = Pressure.metrics.censusRefused + 1
            return math.min(room, hostileRoom), "difficulty_hostile_cap"
        end
    end
    if room < count then return room, "census_short" end
    return count
end

function Pressure.censusPlaceKey(memory)
    if type(memory) ~= "table" or memory.squadId ~= nil or memory.outpostSquadId ~= nil then return nil end
    if memory.outpostId ~= nil then return "site:" .. tostring(memory.outpostId) end
    if memory.groupId ~= nil and (memory.persistent == true or type(memory.garrisonBounds) == "table") then
        return "group:" .. tostring(memory.groupId)
    end
    return nil
end

function Pressure.censusClear(c, key, x, y, hours)
    x, y = finite(x), finite(y)
    if c == nil or type(key) ~= "string" or x == nil or y == nil then return false end
    local count, oldest, oldestKey = 0, nil, nil
    for placeKey, place in pairs(c.places) do
        count = count + 1
        if oldest == nil or place.h < oldest then oldest, oldestKey = place.h, placeKey end
    end
    if c.places[key] == nil and count >= Pressure.censusSettings.places and oldestKey ~= nil then
        c.places[oldestKey] = nil
    end
    c.places[key] = { x = x, y = y, h = finite(hours) or 0 }
    Pressure.metrics.cleared = Pressure.metrics.cleared + 1
    return true
end

function Pressure.censusMarkCleared(key, x, y, hours)
    hours = finite(hours) or Pressure.hours(0)
    local c = Pressure.censusEnsure(hours)
    if not Pressure.censusClear(c, key, x, y, hours) then return false end
    return Pressure.censusSave()
end

function Pressure.censusWiped(c, record, hours)
    local memory = record.memory
    local key = Pressure.censusPlaceKey(memory)
    if key == nil then return false end
    local survivor = false
    local actors = registry()
    if actors ~= nil and type(actors.each) == "function" then
        actors.each(function(other)
            if other.uid ~= record.uid and other.lifecycle ~= "dead"
                    and Pressure.censusPlaceKey(other.memory) == key then
                survivor = true
                return true
            end
        end)
    end
    if survivor then return false end
    local x, y
    local bounds = memory.garrisonBounds
    if type(bounds) == "table" and finite(bounds.x1) and finite(bounds.x2) and finite(bounds.y1) and finite(bounds.y2) then
        x, y = (bounds.x1 + bounds.x2) / 2, (bounds.y1 + bounds.y2) / 2
    else
        local at = memory.stanceAnchor
        if type(at) ~= "table" then at = memory.spawnOrigin end
        if type(at) ~= "table" then at = record.worldPosition end
        if type(at) == "table" then x, y = finite(at.x), finite(at.y) end
    end
    return Pressure.censusClear(c, key, x, y, hours)
end

function Pressure.censusDeath(record)
    if Pressure.mirror() or type(record) ~= "table" or Pressure.censusAdmin(record) then return false end
    local hours = Pressure.hours(0)
    local c = Pressure.censusEnsure(hours)
    if c == nil then return false end
    Pressure.censusAccrue(c, hours)
    c.dead = c.dead + 1
    local row = Pressure.censusRow(c, tostring(record.factionId or "?"))
    if row ~= nil then row.d = row.d + 1 end
    if type(record.uid) == "string" then
        c.graves[#c.graves + 1] = record.uid
        while #c.graves > Pressure.censusSettings.graves do table.remove(c.graves, 1) end
    end
    Pressure.censusWiped(c, record, hours)
    Pressure.metrics.censusDeaths = Pressure.metrics.censusDeaths + 1
    local regions = ProjectALife.RegionLedger
    local at = record.worldPosition
    if regions ~= nil and type(at) == "table" then regions.noteDeaths(at.x, at.y, 1, hours) end
    return Pressure.censusSave()
end

function Pressure.censusLoss(factionId, count, hours)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 or Pressure.mirror() then return false end
    hours = finite(hours) or Pressure.hours(0)
    local c = Pressure.censusEnsure(hours)
    if c == nil then return false end
    Pressure.censusAccrue(c, hours)
    c.dead = c.dead + count
    local row = Pressure.censusRow(c, tostring(factionId or "?"))
    if row ~= nil then row.d = row.d + count end
    Pressure.metrics.censusLosses = Pressure.metrics.censusLosses + count
    return Pressure.censusSave()
end

function Pressure.censusBuried(uid)
    local c = Pressure.censusLoad()
    if c == nil or type(uid) ~= "string" then return false end
    for index = 1, #c.graves do
        if c.graves[index] == uid then return true end
    end
    return false
end

function Pressure.censusClearedHours()
    return Pressure.censusSettings.clearedDays * 24
end

function Pressure.censusSettle(key, hours, x, y)
    local s = Pressure.censusSettings
    if s.resettle ~= true then return false end
    local c = Pressure.censusEnsure(hours)
    if c == nil then return true end
    if Pressure.censusAccrue(c, finite(hours) or c.last) > 0 then Pressure.censusSave() end
    if c.settle < 1 then return false end
    c.settle = c.settle - 1
    x, y = finite(x), finite(y)
    if x ~= nil and y ~= nil then
        for placeKey, place in pairs(c.places) do
            local dx, dy = place.x - x, place.y - y
            if dx * dx + dy * dy <= s.placeRadius * s.placeRadius then c.places[placeKey] = nil end
        end
    end
    Pressure.censusSave()
    return true
end

function Pressure.censusClosed(x, y, hours, key, radius)
    local c = Pressure.censusLoad()
    hours = finite(hours)
    if c == nil or hours == nil then return false end
    x, y = finite(x), finite(y)
    local s = Pressure.censusSettings
    radius = tonumber(radius) or s.placeRadius
    local stale = false
    for placeKey, place in pairs(c.places) do
        if place.h > hours then
            c.places[placeKey] = nil
            stale = true
        end
    end
    if stale then Pressure.censusSave() end
    for placeKey, place in pairs(c.places) do
        local near = key ~= nil and placeKey == key
        if not near and x ~= nil and y ~= nil and radius > 0 then
            local dx, dy = place.x - x, place.y - y
            near = dx * dx + dy * dy <= radius * radius
        end
        if near then
            if s.resettle == true and hours >= place.h + s.clearedDays * 24
                    and Pressure.censusAccrue(c, hours) > 0 then
                Pressure.censusSave()
            end
            if s.resettle ~= true or hours < place.h + s.clearedDays * 24 or c.settle < 1 then
                return true, placeKey
            end
            c.settle = c.settle - 1
            c.places[placeKey] = nil
            Pressure.censusSave()
            return false
        end
    end
    return false
end

function Pressure.censusFactionOf(args)
    if type(args.factionId) == "string" then return args.factionId end
    local ids = args.profileIds
    local first = type(ids) == "table" and ids[1] or args.profileId
    local catalog = ProjectALife.Catalog
    if type(first) == "string" and type(catalog) == "table" and type(catalog.npc) == "function" then
        local profile = catalog.npc(first)
        if type(profile) == "table" and type(profile.general) == "table" then return profile.general.faction end
    end
    return nil
end

function Pressure.censusGate(args, hours, admin, options)
    if type(args) ~= "table" or args.censusAdmitted == true then return nil end
    if admin == true or args.adminPick == true or (type(options) == "table" and options.census == false) then
        args.censusAdmitted = true
        return nil
    end
    local wanted = type(args.profileIds) == "table" and #args.profileIds or 0
    if wanted < 1 then wanted = math.max(1, math.floor(tonumber(args.count) or 1)) end
    local granted, why = Pressure.censusAdmit(wanted, Pressure.censusFactionOf(args), finite(hours) or Pressure.hours(0), args)
    if (tonumber(granted) or 0) < wanted then
        local _, reason = refuse(why or "census_exhausted")
        return reason
    end
    args.censusAdmitted = true
    return nil
end

function Pressure.floorRefusal(playerZ, spawnZ, upper)
    local pz = math.floor((tonumber(playerZ) or 0) + 0.001)
    local sz = math.floor((tonumber(spawnZ) or 0) + 0.001)
    if pz < 0 then return "player_below_ground" end
    if pz >= Pressure.censusSettings.highFloor then return "player_high_up" end
    if sz < 0 then return "spawn_below_ground" end
    if sz > pz and upper ~= true then return "floor_mismatch" end
    return nil
end

function Pressure.landmarks(x, y)
    local s = Pressure.censusSettings
    local reach = math.max(s.townTiles, s.roadTiles)
    if type(getWorld) ~= "function" then return 0, 0 end
    local world = getWorld()
    if world == nil or type(world.getMetaGrid) ~= "function" then return 0, 0 end
    local grid = world:getMetaGrid()
    if grid == nil or type(grid.getZonesIntersecting) ~= "function" then return 0, 0 end
    local zones = grid:getZonesIntersecting(math.floor(x - reach), math.floor(y - reach), 0,
        math.floor(reach * 2), math.floor(reach * 2))
    if zones == nil or type(zones.size) ~= "function" or type(zones.get) ~= "function" then return 0, 0 end
    local town, road = math.huge, math.huge
    for index = 0, zones:size() - 1 do
        local zone = zones:get(index)
        local kind = zone ~= nil and type(zone.getType) == "function" and tostring(zone:getType()) or ""
        local isTown = kind == "TownZone" or kind == "TrailerPark"
        if isTown or kind == "Nav" then
            local d = 0
            if type(zone.getX) == "function" and type(zone.getY) == "function"
                    and type(zone.getWidth) == "function" and type(zone.getHeight) == "function" then
                local x1, y1 = tonumber(zone:getX()) or x, tonumber(zone:getY()) or y
                local x2, y2 = x1 + (tonumber(zone:getWidth()) or 0), y1 + (tonumber(zone:getHeight()) or 0)
                local dx, dy = math.max(x1 - x, 0, x - x2), math.max(y1 - y, 0, y - y2)
                d = math.sqrt(dx * dx + dy * dy)
            end
            if isTown then town = math.min(town, d) else road = math.min(road, d) end
        end
    end
    return town, road
end

function Pressure.noisy(player, x, y)
    if type(player.getVehicle) == "function" then
        local vehicle = player:getVehicle()
        if vehicle ~= nil and (type(vehicle.isEngineRunning) ~= "function" or vehicle:isEngineRunning()) then
            return true
        end
    end
    local investigation = ProjectALife.Investigation
    local marks = type(investigation) == "table" and investigation.marks or nil
    if type(marks) ~= "table" then return false end
    local now = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    local reach = Pressure.censusSettings.noiseTiles
    for index = 1, #marks do
        local mark = marks[index]
        if type(mark) == "table" and mark.kind == "noise" and now < (tonumber(mark.untilMs) or 0) then
            if mark.source == player then return true end
            local dx, dy = (tonumber(mark.x) or 0) - x, (tonumber(mark.y) or 0) - y
            if dx * dx + dy * dy <= reach * reach then return true end
        end
    end
    return false
end

function Pressure.concealed(player)
    if player == nil or type(player.getX) ~= "function" or type(player.getY) ~= "function" then return false end
    local x, y = tonumber(player:getX()), tonumber(player:getY())
    if x == nil or y == nil or Pressure.noisy(player, x, y) then return false end
    local ok, town, road = pcall(Pressure.landmarks, x, y)
    if not ok then return false end
    local s = Pressure.censusSettings
    return (tonumber(town) or 0) > s.townTiles and (tonumber(road) or 0) > s.roadTiles
end

function Pressure.inSight(x, y, z)
    x, y = finite(x), finite(y)
    if x == nil or y == nil or type(getCell) ~= "function" or type(getSpecificPlayer) ~= "function" then return false end
    if type(isServer) == "function" and isServer() then return false end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(z) or 0))
    if square == nil or type(square.isCanSee) ~= "function" then return false end
    for index = 0, 3 do
        if getSpecificPlayer(index) ~= nil and square:isCanSee(index) == true then return true end
    end
    return false
end

function Pressure.shelterRefusal(player, x, y, z, upper)
    if player == nil then return nil end
    x, y = finite(x), finite(y)
    if x ~= nil and y ~= nil and type(player.getX) == "function" and type(player.getY) == "function" then
        local dx, dy = (tonumber(player:getX()) or x) - x, (tonumber(player:getY()) or y) - y
        local near = Pressure.censusSettings.nearTiles
        if dx * dx + dy * dy > near * near then return nil end
    end
    local m = Pressure.metrics
    local pz = type(player.getZ) == "function" and tonumber(player:getZ()) or 0
    local why = Pressure.floorRefusal(pz, z, upper)
    if why ~= nil then
        m.floor = m.floor + 1
        return why
    end
    if Pressure.concealed(player) then
        m.hidden = m.hidden + 1
        return "player_hidden"
    end
    if x ~= nil and Pressure.inSight(x, y, z) then
        m.inView = m.inView + 1
        return "in_player_sight"
    end
    return nil
end

function Pressure.settles(args, options)
    return options.site ~= nil or args.encounterPersistent == true
        or (args.outpostId ~= nil and args.outpostSquadId == nil)
end

function Pressure.spawnGate(player, args, hours, options, admin)
    if options.bypass ~= true and admin ~= true then
        local why = Pressure.shelterRefusal(player, args.x, args.y, args.z or 0,
            options.upper == true or args.upper == true)
        if why == nil and Pressure.settles(args, options)
                and Pressure.censusClosed(args.x, args.y, hours, options.site, Pressure.censusSettings.placeRadius) then
            why = "census_cleared"
        end
        if why ~= nil then
            local _, reason = refuse(why)
            return reason
        end
    end
    return Pressure.censusGate(args, hours, admin, options)
end

function Pressure.censusBrief(hours)
    local c = Pressure.censusLoad()
    if c == nil then return nil end
    hours = finite(hours) or Pressure.hours(c.last)
    if Pressure.censusAccrue(c, hours) > 0 then Pressure.censusSave() end
    local tally = Pressure.censusTally()
    local living = c.total + c.arrived - c.dead
    local brief = { total = c.total, living = living, alive = tally.total, dead = c.dead, arrived = c.arrived,
        room = math.max(0, living - tally.total), legacy = c.legacy == true, settle = c.settle,
        places = 0, spent = 0, factions = {} }
    for _ in pairs(c.places) do brief.places = brief.places + 1 end
    local listed = {}
    for id, row in pairs(c.factions) do
        listed[id] = true
        local strength = Pressure.censusStrength(id)
        if strength <= 0 then brief.spent = brief.spent + 1 end
        brief.factions[#brief.factions + 1] = { id = id, alive = tally.factions[id] or 0,
            dead = row.d, arrived = row.a, budget = row.q, strength = strength }
    end
    for id, alive in pairs(tally.factions) do
        if not listed[id] then
            brief.factions[#brief.factions + 1] = { id = id, alive = alive, dead = 0, arrived = 0, strength = 1 }
        end
    end
    table.sort(brief.factions, Pressure.censusOrder)
    return brief
end

function Pressure.censusOrder(a, b)
    local wa, wb = a.alive + a.dead, b.alive + b.dead
    if wa ~= wb then return wa > wb end
    return tostring(a.id) < tostring(b.id)
end

function Pressure.censusLines(hours, limit)
    local brief = Pressure.censusBrief(hours)
    local m = Pressure.metrics
    local guard = "[ALIFE-QA] censusGuard hidden=" .. tostring(m.hidden) .. " floor=" .. tostring(m.floor)
        .. " in_view=" .. tostring(m.inView) .. " cleared=" .. tostring(m.cleared)
        .. " refused=" .. tostring(m.censusRefused) .. " deaths=" .. tostring(m.censusDeaths)
        .. " losses=" .. tostring(m.censusLosses) .. " arrivals=" .. tostring(m.censusArrivals)
    if brief == nil then return { "[ALIFE-QA] census none", guard } end
    local lines = { "[ALIFE-QA] census total=" .. brief.total .. " living=" .. brief.living
        .. " alive=" .. brief.alive .. " killed=" .. brief.dead .. " arrivals=" .. brief.arrived
        .. " room=" .. brief.room .. " spent=" .. brief.spent .. " cleared=" .. brief.places
        .. " settle=" .. string.format("%.2f", brief.settle) .. (brief.legacy and " legacy" or "") }
    local parts = {}
    for index = 1, math.min(#brief.factions, tonumber(limit) or 24) do
        local row = brief.factions[index]
        parts[#parts + 1] = tostring(row.id) .. "=a" .. row.alive .. "/k" .. row.dead .. "/r" .. row.arrived
    end
    lines[2] = "[ALIFE-QA] censusFactions " .. (#parts > 0 and table.concat(parts, " ") or "none")
    lines[3] = guard
    return lines
end

return Pressure
