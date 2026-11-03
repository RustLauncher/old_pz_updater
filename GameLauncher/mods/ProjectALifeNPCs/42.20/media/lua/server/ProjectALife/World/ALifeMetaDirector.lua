require "ProjectALife/World/ALifeMetaEvents"
require "ProjectALife/Core/ALifePersistence"
require "ProjectALife/Records/ALifeFactionSpawnRules"

ProjectALife = ProjectALife or {}
ProjectALife.MetaClient = ProjectALife.MetaClient or {}

local MetaDirector = {
    adapters = {},
    nextCheckAtMs = 0,
    sequence = 0,
    pending = nil,
    fallbackStore = { lastAtHour = -1e9, scenes = {} },
    metrics = { checks = 0, events = 0, refused = 0, crashes = 0 },
}
ProjectALife.MetaDirector = MetaDirector

local function nowMs()
    if type(MetaDirector.adapters.nowMs) == "function" then
        return tonumber(MetaDirector.adapters.nowMs()) or 0
    end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function calendar()
    if type(MetaDirector.adapters.calendar) == "function" then
        local day, hours = MetaDirector.adapters.calendar()
        return math.floor(tonumber(day) or 0), tonumber(hours) or 0
    end
    local day, hours = 0, 0
    pcall(function()
        local gameTime = getGameTime()
        day = gameTime:getNightsSurvived()
        hours = gameTime:getWorldAgeHours()
    end)
    return math.floor(tonumber(day) or 0), tonumber(hours) or 0
end

local function random()
    if type(MetaDirector.adapters.random) == "function" then
        return math.max(0, math.min(0.999999, tonumber(MetaDirector.adapters.random()) or 0))
    end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    return math.random()
end

local function persistentStore()
    if type(MetaDirector.adapters.store) == "function" then
        local supplied = MetaDirector.adapters.store()
        if type(supplied) == "table" then
            supplied.scenes = type(supplied.scenes) == "table" and supplied.scenes or {}
            return supplied
        end
    end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.bucket) == "function" then
        local value = persistence.bucket("metaEvents", {
            lastAtHour = -1e9, scenes = {},
        })
        if type(value) == "table" then
            value.scenes = type(value.scenes) == "table" and value.scenes or {}
            return value
        end
    end
    return MetaDirector.fallbackStore
end

local function dirty()
    if type(MetaDirector.adapters.dirty) == "function" then
        MetaDirector.adapters.dirty()
        return
    end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
end

function MetaDirector.configure(adapters)
    MetaDirector.adapters = type(adapters) == "table" and adapters or {}
    MetaDirector.nextCheckAtMs = 0
    MetaDirector.pending = nil
    return true
end

function MetaDirector.reset()
    MetaDirector.adapters = {}
    MetaDirector.nextCheckAtMs = 0
    MetaDirector.sequence = 0
    MetaDirector.pending = nil
    MetaDirector.fallbackStore = { lastAtHour = -1e9, scenes = {} }
    MetaDirector.metrics = { checks = 0, events = 0, refused = 0, crashes = 0 }
end

function MetaDirector.period(day)
    local settings = ProjectALife.MetaEvents.settings
    day = math.floor(tonumber(day) or -1)
    if day < 0 then return nil end
    if day < settings.earlyDays then return "early" end
    if day >= settings.militaryStartDay then return "military" end

    return "later"
end

function MetaDirector.rateScale()
    local scale = tonumber(MetaDirector.adapters.rateScale)
    if scale == nil or scale <= 0 then return 1 end
    return math.max(0.25, math.min(4, scale))
end

function MetaDirector.resolve(base, key)
    base = tonumber(base) or 1
    local whole = math.floor(base)
    local part = base - whole
    if part <= 0 then return whole end
    local threshold = (math.floor(tonumber(key) or 0) * 0.6180339887) % 1
    if threshold < part then whole = whole + 1 end
    return whole
end

function MetaDirector.allowed(values, day, hours)
    local settings = ProjectALife.MetaEvents.settings
    if settings.enabled ~= true then return false, "disabled" end
    local period = MetaDirector.period(day)
    if period == nil then return false, "calendar" end
    local scale = MetaDirector.rateScale()
    if (tonumber(hours) or 0) < (tonumber(values.lastAtHour) or -1e9)
            + settings.minGapMinutes / 60 / scale then
        return false, "gap"
    end
    if period == "early" or period == "later" then
        local cap = MetaDirector.resolve(settings.laterPerDayMax, day)
        if period == "early" then cap = MetaDirector.resolve(settings.earlyPerDayMax, day) end
        if tonumber(values.earlyDay) ~= day then return true, period end
        if (tonumber(values.earlyCount) or 0) >= math.max(1, math.floor(cap * scale + 0.5)) then
            return false, "daily_cap"
        end
    else
        local week = math.floor(day / 7)
        if tonumber(values.militaryWeek) ~= week then return true, period end
        if (tonumber(values.militaryCount) or 0) >= math.max(1, math.floor(MetaDirector.resolve(settings.militaryPerWeek, week) * scale + 0.5)) then
            return false, "weekly_cap"
        end
    end
    return true, period
end

local function roster()
    if type(MetaDirector.adapters.players) == "function" then
        return MetaDirector.adapters.players()
    end
    local result = {}
    pcall(function()
        local online = getOnlinePlayers and getOnlinePlayers() or nil
        if online ~= nil then
            for index = 0, online:size() - 1 do result[#result + 1] = online:get(index) end
        end
    end)
    if #result == 0 then
        pcall(function()
            local solo = getSpecificPlayer and getSpecificPlayer(0) or nil
            if solo ~= nil then result[1] = solo end
        end)
    end
    return result
end

local function position(player)
    local point
    pcall(function() point = { x = player:getX(), y = player:getY(), z = player:getZ() } end)
    return point
end

function MetaDirector.offsetPoint(origin, firstRoll, secondRoll)
    if type(origin) ~= "table" then return nil end
    local settings = ProjectALife.MetaEvents.settings
    local radius = settings.offsetMinimum
        + (settings.offsetMaximum - settings.offsetMinimum) * (tonumber(firstRoll) or 0)
    local angle = (tonumber(secondRoll) or 0) * math.pi * 2
    return {
        x = math.floor(origin.x + math.cos(angle) * radius),
        y = math.floor(origin.y + math.sin(angle) * radius),
        z = math.floor(tonumber(origin.z) or 0),
    }
end

local function broadcast(payload)
    if type(MetaDirector.adapters.broadcast) == "function" then
        return MetaDirector.adapters.broadcast(payload) ~= false
    end
    pcall(function()
        if type(isServer) ~= "function" or not isServer() then return end
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players == nil then return end
        for index = 0, players:size() - 1 do
            sendServerCommand(players:get(index), "ProjectALife", "MetaEvent", payload)
        end
    end)
    pcall(function()
        local client = ProjectALife.MetaClient
        if client ~= nil and type(client.onEvent) == "function" then client.onEvent(payload) end
    end)
    return true
end

local function militaryNoise(point)
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.noteNoise) == "function" then
        pcall(first.noteNoise, point.x, point.y, point.z, 120, "siren")
    end
    if type(MetaDirector.adapters.addSound) == "function" then
        MetaDirector.adapters.addSound(point.x, point.y, point.z, 120, 80)
        return
    end
    pcall(function() addSound(nil, point.x, point.y, point.z, 120, 80) end)
end

local function nextId(kind, hours)
    MetaDirector.sequence = MetaDirector.sequence + 1
    return "meta:" .. tostring(kind) .. ":" .. tostring(math.floor(hours * 60))
        .. ":" .. tostring(MetaDirector.sequence)
end

local function crashPoint(origin)
    if type(MetaDirector.adapters.crashPoint) == "function" then
        return MetaDirector.adapters.crashPoint(origin)
    end
    local director = ProjectALife.EncounterDirector
    if director ~= nil and type(director.roadPointNear) == "function" then
        return director.roadPointNear(origin.x, origin.y, 90, 140)
    end
    return nil
end

local function watchGroup(requestId, listener)
    if type(MetaDirector.adapters.watchGroup) == "function" then
        return MetaDirector.adapters.watchGroup(requestId, listener)
    end
    local service = ProjectALife.DebugService
    if service == nil or type(service.watchGroup) ~= "function" then
        return false, "group_outcome_unavailable"
    end
    return service.watchGroup(requestId, listener)
end

local function spawnCrash(player, origin, eventId, values)
    local point = crashPoint(origin)
    if point == nil then return false, "crash_road_missing" end
    local key = "car_crash:" .. tostring(math.floor(point.x))
        .. ":" .. tostring(math.floor(point.y))
    if values.scenes[key] ~= nil then return false, "crash_already_placed" end
    local service = ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function"
            or type(service.hostileProfileIds) ~= "function" then
        return false, "spawn_service_unavailable"
    end

    local faction = ProjectALife.FactionSpawnRules.pick(ProjectALife.Catalog and ProjectALife.Catalog.current,
        point, nil, random())
    if faction == nil then return false, "no_eligible_faction" end
    local profiles = service.hostileProfileIds(2, math.floor(origin.x + origin.y), faction.id, true)
    if type(profiles) ~= "table" then return false, "officer_profiles_missing" end
    local definition = ProjectALife.Encounters and ProjectALife.Encounters.get("car_crash")
    local heading = 0
    local director = ProjectALife.EncounterDirector
    if director ~= nil and type(director.headingFor) == "function" then
        heading = director.headingFor(definition or {}, point) or 0
    end
    local ok, reason, receipt = service.spawnEncounter(player, {
        requestId = eventId,
        encounterId = "car_crash",
        profileIds = profiles,
        count = 2,
        x = point.x, y = point.y, z = point.z,
        distance = 0, separation = 2, radius = 16,
        mode = "guard", profile = "patrol",
        stance = "defend", heading = heading,
        awareness = 0.7, conducts = { "leader" },
        animation = "normal",
        atomicGroup = true,
    })
    return ok, reason, { key = key, receipt = receipt, point = point }
end

local function commit(values, period, day, hours)
    values.lastAtHour = hours
    if period == "early" or period == "later" then
        if tonumber(values.earlyDay) ~= day then
            values.earlyDay, values.earlyCount = day, 0
        end
        values.earlyCount = (tonumber(values.earlyCount) or 0) + 1
    else
        local week = math.floor(day / 7)
        if tonumber(values.militaryWeek) ~= week then
            values.militaryWeek, values.militaryCount = week, 0
        end
        values.militaryCount = (tonumber(values.militaryCount) or 0) + 1
    end
    dirty()
end

local function settleCrash(eventId, key, values, period, day, hours, outcome)
    if MetaDirector.pending == nil or MetaDirector.pending.eventId ~= eventId then
        return false
    end
    MetaDirector.pending = nil
    local accepted = type(outcome) == "table" and tonumber(outcome.accepted) or 0
    local successful = type(outcome) == "table" and outcome.ok == true
        and accepted > 0 and tonumber(outcome.active) == accepted
        and (tonumber(outcome.failed) or 0) == 0
        and (tonumber(outcome.rejected) or 0) == 0
    if not successful then
        MetaDirector.metrics.refused = MetaDirector.metrics.refused + 1
        MetaDirector.nextCheckAtMs = nowMs() + 1000
        return false
    end
    values.scenes[key] = eventId
    MetaDirector.metrics.crashes = MetaDirector.metrics.crashes + 1
    commit(values, period, day, hours)
    MetaDirector.metrics.events = MetaDirector.metrics.events + 1
    return true
end

function MetaDirector.fire(kind, player, day, hours)
    if MetaDirector.pending ~= nil then return false, "event_pending" end
    local origin = position(player)
    if origin == nil then return false, "player_position_unavailable" end
    local values = persistentStore()
    local id = nextId(kind, hours)
    local ok, reason, detail = true, nil, nil
    if kind == "crash" then
        ok, reason, detail = spawnCrash(player, origin, id, values)

        if ok and type(detail) == "table" and type(detail.point) == "table" then
            broadcast({ eventId = id, kind = "crash",
                x = detail.point.x, y = detail.point.y, z = detail.point.z,
                seed = math.floor(random() * 2147483646) + 1 })
        end
    else
        local point = MetaDirector.offsetPoint(origin, random(), random())
        local payload = {
            eventId = id, kind = kind,
            x = point.x, y = point.y, z = point.z,
            seed = math.floor(random() * 2147483646) + 1,
        }
        ok = broadcast(payload)
        if ok and kind == "military" then militaryNoise(point) end
    end
    if not ok then return false, reason or "event_failed" end
    local period = MetaDirector.period(day)
    if kind == "crash" and type(detail) == "table"
            and reason == "accepted_pending"
            and type(detail.receipt) == "table" then
        MetaDirector.pending = { eventId = id, requestId = id, key = detail.key }
        local watched, watchReason = watchGroup(id, function(outcome)
            settleCrash(id, detail.key, values, period, day, hours, outcome)
        end)
        if not watched then
            MetaDirector.pending = nil
            return false, watchReason or "group_outcome_unavailable"
        end
        return true, id, "pending"
    end
    if kind == "crash" then
        values.scenes[detail.key] = id
        MetaDirector.metrics.crashes = MetaDirector.metrics.crashes + 1
    end
    commit(values, period, day, hours)
    MetaDirector.metrics.events = MetaDirector.metrics.events + 1
    return true, id
end

function MetaDirector.announceTo(player, kind, x, y, z)
    if tonumber(x) == nil or tonumber(y) == nil then return false end
    MetaDirector.sequence = MetaDirector.sequence + 1
    local payload = { eventId = "intro:" .. tostring(kind) .. ":" .. tostring(math.floor(x)) .. ":"
            .. tostring(math.floor(y)) .. ":" .. tostring(MetaDirector.sequence),
        kind = tostring(kind or "gunfire"), x = math.floor(x), y = math.floor(y),
        z = math.floor(tonumber(z) or 0), seed = math.floor(random() * 2147483646) + 1 }
    if type(MetaDirector.adapters.announceTo) == "function" then
        return MetaDirector.adapters.announceTo(player, payload) ~= false
    end
    local delivered = false
    pcall(function()
        if type(isServer) == "function" and isServer() and player ~= nil then
            sendServerCommand(player, "ProjectALife", "MetaEvent", payload)
            delivered = true
        end
    end)
    if not delivered then
        pcall(function()
            local client = ProjectALife.MetaClient
            if client ~= nil and type(client.onEvent) == "function" then
                client.onEvent(payload)
                delivered = true
            end
        end)
    end
    if delivered then MetaDirector.metrics.events = MetaDirector.metrics.events + 1 end
    return delivered
end

function MetaDirector.announceCrash(x, y, z)
    if tonumber(x) == nil or tonumber(y) == nil then return false end
    MetaDirector.sequence = MetaDirector.sequence + 1
    return broadcast({ eventId = "crash:" .. tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))
            .. ":" .. tostring(MetaDirector.sequence),
        kind = "crash", x = math.floor(x), y = math.floor(y), z = math.floor(tonumber(z) or 0),
        seed = math.floor(random() * 2147483646) + 1 })
end

function MetaDirector.debugFire(kind, player)
    if kind == "searchlight" then
        local director = ProjectALife.HeliDirector
        if director == nil or type(director.debugStart) ~= "function" then return false, "heli_director_unavailable" end
        return director.debugStart(player)
    end
    local day, hours = calendar()
    return MetaDirector.fire(tostring(kind or "ambience"), player, day, hours)
end

function MetaDirector.tick()
    if type(isClient) == "function" and isClient() then return 0 end
    local settings = ProjectALife.MetaEvents.settings
    if settings.enabled ~= true then return 0 end
    if MetaDirector.pending ~= nil then return 0 end
    local now = nowMs()
    if now < MetaDirector.nextCheckAtMs then return 0 end
    MetaDirector.nextCheckAtMs = now + 10000
    MetaDirector.metrics.checks = MetaDirector.metrics.checks + 1
    local day, hours = calendar()
    local values = persistentStore()
    local allowed, period = MetaDirector.allowed(values, day, hours)
    if not allowed then return 0 end
    local players = roster()
    if #players == 0 then return 0 end
    local player = players[1 + math.floor(random() * #players) % #players]

    local kind = ProjectALife.MetaEvents.kindForRoll(random())
    if period == "military" and random() < (tonumber(settings.militaryShare) or 0.5) then
        kind = "military"
    end
    if kind == nil then return 0 end

    local settings = ProjectALife.Settings
    if (kind == "heli" or kind == "military") and settings ~= nil
            and type(settings.helicoptersAllowed) == "function"
            and not settings.helicoptersAllowed() then
        kind = "gunfire"
    end
    local fired = MetaDirector.fire(kind, player, day, hours)
    if not fired then MetaDirector.metrics.refused = MetaDirector.metrics.refused + 1 end
    return fired and 1 or 0
end

return MetaDirector
