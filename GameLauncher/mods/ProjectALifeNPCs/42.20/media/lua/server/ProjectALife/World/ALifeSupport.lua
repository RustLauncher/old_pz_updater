require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/World/ALifeKeepOut"
require "ProjectALife/World/ALifeWorldPressure"
require "ProjectALife/Outposts/ALifeOutpostRegistry"
require "ProjectALife/World/ALifeHeliDirector"

ProjectALife = ProjectALife or {}

local Telemetry = ProjectALife.Telemetry

local Support = {
    adapters = {},
    enabled = true,
    settings = {
        cooldownHours = 0.18,
        successPercent = 35,
        backoffMs = 30000,
        callerHomeRange = 180,
        contactRange = 120,
        defaultSize = 4,
        maxCallsCap = 3,
        noiseRadius = 80,
        noiseVolume = 80,

        heliArriveMinimum = 18,
        heliArriveMaximum = 25,
        heliNoiseRadius = 55,
        heliNoiseVolume = 70,
        heliDurationS = 35,

        spotlightPercent = 12,
        spotlightCooldownMs = 600000,
        spotlightBackoffMs = 30000,
        spotlightDurationS = 180,

        spotlightWorldGapMs = 1200000,
        spotlightEnabled = true,
        spotlightRadius = 11,
        spotlightBrightness = 100,
        lowLightStrength = 0.4,

        vehicleAliases = {
            pickup = "Base.PickUpTruck",
            truck = "Base.PickUpTruck_Camo",
            workvan = "Base.StepVan",
            wagon = "Base.CarStationWagon",
            offroad = "Base.OffRoad",
            police = "Base.CarLightsPolice",
        },
    },

    ledger = {},
    intel = {},
    metrics = { requests = 0, refused = 0, rolledOff = 0, dispatched = 0, spotlights = 0, vehicles = 0, reasons = {} },
}
ProjectALife.Support = Support

local function nowMs()
    if type(Support.adapters.nowMs) == "function" then return Support.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    if type(Support.adapters.worldHours) == "function" then return Support.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function roll()
    if type(Support.adapters.roll) == "function" then return Support.adapters.roll() end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(10000) / 10000 end
    return 1
end

local function emit(category, fields)
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then pcall(Telemetry.emit, category, fields) end
end

function Support.readLedger()
    local registry = ProjectALife.ActorRegistry
    local saved = registry ~= nil and type(registry.getWorldValue) == "function"
        and registry.getWorldValue("supportCalls") or nil
    local ledger, count = {}, 0
    for key, row in pairs(type(saved) == "table" and saved or {}) do
        local calls = type(row) == "table" and tonumber(row.calls) or nil
        local untilHours = type(row) == "table" and tonumber(row.nextAtHours) or nil
        if count < 256 and type(key) == "string" and #key > 0 and #key <= 160
                and calls ~= nil and calls == calls and calls > 0 and calls <= 10
                and untilHours ~= nil and untilHours == untilHours and math.abs(untilHours) < math.huge then
            ledger[key] = { calls = math.floor(calls), nextAtHours = untilHours, nextAttemptMs = 0,
                call = type(row.call) == "string" and #row.call <= 160 and row.call or nil }
            count = count + 1
        end
    end
    return ledger
end

function Support.persistLedger()
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function"
            or type(registry.setWorldValue) ~= "function" then return false end
    local live, retainedOutposts, saved, count = {}, {}, {}, 0
    registry.each(function(record)
        if record.lifecycle == "dead" then return end
        local memory = type(record.memory) == "table" and record.memory or {}
        live[memory.groupId or ("solo:" .. tostring(record.uid))] = true
    end)
    local outposts = ProjectALife.OutpostRegistry
    local sites = outposts ~= nil and type(outposts.list) == "function" and outposts.list() or {}
    for _, site in ipairs(sites) do
        if site.state ~= "expired" then
            retainedOutposts["outpost:" .. tostring(site.id) .. ":backup"] = true
            retainedOutposts["outpost:" .. tostring(site.id) .. ":help"] = true
        end
    end
    for key, row in pairs(Support.ledger) do
        if (live[key] or retainedOutposts[key]) and row.calls > 0 then
            count = count + 1
            if count > 256 then return false end
            saved[key] = { calls = row.calls, nextAtHours = row.nextAtHours, call = row.call }
        end
    end
    return registry.setWorldValue("supportCalls", saved) == true
end

function Support.takeCall(entry, hours, cooldown)
    local previousCalls, previousHours = entry.calls, entry.nextAtHours
    entry.calls = entry.calls + 1
    entry.nextAtHours = hours + (tonumber(cooldown) or Support.settings.cooldownHours)
    if Support.persistLedger() then return true end
    entry.calls, entry.nextAtHours = previousCalls, previousHours
    return false
end

function Support.configure(adapters)
    Support.adapters = adapters or {}
    Support.enabled = Support.adapters.enabled ~= false
    for key, bounds in pairs({ cooldownHours = { 0, 168 }, successPercent = { 0, 100 },
            defaultSize = { 1, 8 }, maxCallsCap = { 0, 10 }, spotlightPercent = { 0, 100 },
            spotlightDurationS = { 5, 180 }, heliDurationS = { 5, 180 } }) do
        local value = tonumber(Support.adapters[key])
        if value ~= nil and value == value then
            Support.settings[key] = math.max(bounds[1], math.min(bounds[2], value))
        end
    end
    Support.settings.defaultSize = math.floor(Support.settings.defaultSize)
    Support.settings.maxCallsCap = math.floor(Support.settings.maxCallsCap)
    if Support.adapters.spotlightEnabled ~= nil then
        Support.settings.spotlightEnabled = Support.adapters.spotlightEnabled ~= false
    end
    for key, bounds in pairs({ spotlightRadius = { 4, 24 }, spotlightBrightness = { 20, 100 } }) do
        local value = tonumber(Support.adapters[key])
        if value ~= nil and value == value then
            Support.settings[key] = math.max(bounds[1], math.min(bounds[2], value))
        end
    end
    local gapMinutes = tonumber(Support.adapters.spotlightGapMinutes)
    if gapMinutes ~= nil and gapMinutes == gapMinutes then
        Support.settings.spotlightWorldGapMs = math.max(2, math.min(240, gapMinutes)) * 60000
    end
    Support.syncHeliSettings()
    Support.ledger, Support.intel, Support.nextIntelAtMs = Support.readLedger(), {}, nil
    Support.lastSpotlightUntilMs = nil
    return true
end

function Support.vehicleKind(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" then return nil end
    local alias = Support.settings.vehicleAliases[string.lower(text)]
    if alias ~= nil then return alias end
    if string.sub(text, 1, 5) == "Base." then return text end
    return nil
end

local function answererPool(value)
    local result = {}
    if type(value) == "table" then
        for index = 1, math.min(3, #value) do
            local id = tostring(value[index] or "")
            if id ~= "" then result[#result + 1] = id end
        end
        return result
    end
    local encoded = string.gsub(tostring(value or ""), ",", "|")
    for id in string.gmatch(encoded .. "|", "(.-)|") do
        id = string.match(id, "^%s*(.-)%s*$")
        if id ~= "" and #result < 3 then result[#result + 1] = id end
    end
    return result
end

Support.spotlightBlocs = { law = true, military = true, elite = true }

function Support.doctrineFor(memory, faction, profile)
    local out = { policy = "any", type = "ground", size = Support.settings.defaultSize,
        maxCalls = 1, heli = "none", vehicle = nil, answerers = { "same" } }
    local sources = {}
    if type(faction) == "table" and type(faction.support) == "table" then sources[#sources + 1] = faction.support end
    local general = type(profile) == "table" and profile.general or nil
    if type(general) == "table" and (general.supportPolicy ~= nil
            or general.supportType ~= nil or general.supportHeli ~= nil) then
        sources[#sources + 1] = { policy = general.supportPolicy,
            type = general.supportType,
            heli = general.supportHeli }
    end

    if type(memory) == "table" and type(memory.support) == "table"
            and memory.support.inherited ~= true then sources[#sources + 1] = memory.support end
    for _, source in ipairs(sources) do
        if source.policy ~= nil then out.policy = tostring(source.policy) end
        if source.type ~= nil then out.type = tostring(source.type) end
        if source.heli ~= nil then out.heli = tostring(source.heli) end
        if source.vehicle ~= nil then out.vehicle = Support.vehicleKind(source.vehicle) or out.vehicle end
        if source.answerers ~= nil then
            local answerers = answererPool(source.answerers)
            if #answerers > 0 then out.answerers = answerers end
        end
        if source.size ~= nil then out.size = math.max(1, math.min(8, math.floor(tonumber(source.size) or out.size))) end
        if source.maxCalls ~= nil then out.maxCalls = math.max(0, math.min(Support.settings.maxCallsCap, math.floor(tonumber(source.maxCalls) or out.maxCalls))) end

        if source.cooldownHours ~= nil then out.cooldownHours = math.max(0, math.min(168, tonumber(source.cooldownHours) or 0)) end
    end

    out.maxCalls = math.min(out.maxCalls, Support.settings.maxCallsCap)
    out.cooldownHours = math.max(Support.settings.cooldownHours, tonumber(out.cooldownHours) or 0)
    local authoredHeli = false
    for _, source in ipairs(sources) do
        if source.heli ~= nil then authoredHeli = true end
    end
    local rules = ProjectALife.FactionSpawnRules
    local bloc = type(faction) == "table" and (rules ~= nil and type(rules.blocOf) == "function"
        and rules.blocOf(faction) or (type(faction.relations) == "table" and faction.relations.bloc)) or nil
    if not authoredHeli and Support.spotlightBlocs[tostring(bloc)] == true then
        out.heli = "spotlight"
    end
    if out.policy ~= "any" and out.policy ~= "radio" and out.policy ~= "disabled" then out.policy = "any" end
    if out.type ~= "ground" and out.type ~= "heli" and out.type ~= "both" then out.type = "ground" end
    if out.heli ~= "none" and out.heli ~= "spotlight" and out.heli ~= "support"
            and out.heli ~= "support_spotlight" then out.heli = "none" end
    if out.policy == "disabled" then out.heli = "none" end
    if not Support.helicoptersAllowed() then out.heli = "none" end
    if Support.settings.spotlightEnabled == false then
        if out.heli == "spotlight" then out.heli = "none"
        elseif out.heli == "support_spotlight" then out.heli = "support" end
    end
    return out
end

function Support.syncHeliSettings()
    local heli = ProjectALife.HeliSearch
    if heli == nil or type(heli.configure) ~= "function" then return false end
    return heli.configure({ enabled = Support.settings.spotlightEnabled,
        radius = Support.settings.spotlightRadius,
        brightness = Support.settings.spotlightBrightness / 100 })
end

function Support.helicoptersAllowed()
    local settings = ProjectALife.Settings
    if settings == nil or type(settings.helicoptersAllowed) ~= "function" then return true end
    return settings.helicoptersAllowed() == true
end

function Support.supportFaction(factionId, doctrine, callNumber)
    local answerers = type(doctrine) == "table" and doctrine.answerers or nil
    local wanted = type(answerers) == "table"
        and answerers[math.max(1, math.floor(tonumber(callNumber) or 1))] or nil
    if wanted == nil or wanted == "" or wanted == "same" or wanted == factionId then
        return factionId
    end
    local catalog = ProjectALife.Catalog
    local source = catalog and catalog.faction and catalog.faction(factionId) or nil
    local target = catalog and catalog.faction and catalog.faction(wanted) or nil
    if source == nil or target == nil then return factionId end

    local rules = ProjectALife.FactionSpawnRules
    if rules ~= nil and type(rules.inSeason) == "function" and not rules.inSeason(target, worldHours() / 24) then
        return factionId
    end
    local forward = source.relations and source.relations[wanted] or nil
    local reverse = target.relations and target.relations[factionId] or nil
    forward, reverse = string.lower(tostring(forward or "")),
        string.lower(tostring(reverse or ""))
    if forward == "friendly" or forward == "allied"
            or reverse == "friendly" or reverse == "allied" then
        return wanted
    end
    return factionId
end

function Support.deliveryFor(doctrine, r)
    local canFly = doctrine.heli == "support" or doctrine.heli == "support_spotlight"
    if doctrine.type == "heli" then return canFly and "heli" or "ground" end
    if doctrine.type == "both" and canFly then return (tonumber(r) or 0.5) < 0.5 and "heli" or "ground" end
    return "ground"
end

function Support.insertionPoint(delivery, callerX, callerY, contactX, contactY, r)
    if delivery ~= "heli" then return Support.arrivalPoint(callerX, callerY, contactX, contactY, r) end
    local dx, dy = callerX - contactX, callerY - contactY
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then dx, dy, len = 1, 0, 1 end
    dx, dy = dx / len, dy / len
    local reach = Support.settings.heliArriveMinimum
        + (Support.settings.heliArriveMaximum - Support.settings.heliArriveMinimum) * (tonumber(r) or 0.5)
    return { x = contactX + dx * reach, y = contactY + dy * reach, z = 0 }
end

function Support.mayCall(entry, doctrine, hours, now, radiomanAlive)
    if doctrine.policy == "disabled" then return false, "policy_disabled" end
    if doctrine.policy == "radio" and radiomanAlive ~= true then return false, "no_radioman" end
    if doctrine.maxCalls <= 0 then return false, "no_calls" end
    entry = entry or { calls = 0, nextAtHours = -1e9, nextAttemptMs = 0 }
    if entry.calls >= doctrine.maxCalls then return false, "calls_spent" end
    if hours < (tonumber(entry.nextAtHours) or -1e9) then return false, "cooldown" end
    if now < (tonumber(entry.nextAttemptMs) or 0) then return false, "backoff" end
    return true
end

local function distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function Support.arrivalPoint(callerX, callerY, contactX, contactY, r)
    local dx, dy = callerX - contactX, callerY - contactY
    local len = distance(callerX, callerY, contactX, contactY)
    if len < 0.01 then dx, dy, len = 1, 0, 1 end
    dx, dy = dx / len, dy / len
    local nearest, farthest = ProjectALife.KeepOut.partyRing()
    local reach = nearest + (farthest - nearest) * (tonumber(r) or 0.5)
    return { x = contactX + dx * reach, y = contactY + dy * reach, z = 0 }
end

Support.relayLocks = {}
Support.relayLockMs = 90000

function Support.mayBegin(groupId, doctrine, now, operatorAlive)
    if now ~= nil and (tonumber(Support.relayLocks[groupId]) or 0) > now then
        return false, "call_in_flight"
    end
    return Support.mayCall(Support.ledger[groupId], doctrine, worldHours(), now, operatorAlive)
end

function Support.mayCallRadio(actor)
    if type(Support.adapters.mayCallRadio) == "function" then
        return Support.adapters.mayCallRadio(actor) == true
    end
    if type(actor) ~= "table" then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.supportCaller == true then return true end
    if memory.supportCaller == false then return false end
    local runtime = type(memory.support) == "table" and memory.support or nil
    if runtime ~= nil and runtime.inherited ~= true and runtime.policy ~= nil then
        return runtime.policy == "any"
    end
    local allowed = false
    pcall(function()
        local catalog = ProjectALife.Catalog
        local profile = catalog and catalog.npc and catalog.npc(actor.profileId) or nil
        local general = profile and profile.general or {}
        if general.supportCaller == true or general.supportPolicy == "any" then
            allowed = true
            return
        end
        if general.supportPolicy ~= nil and general.supportPolicy ~= "inherit" then return end
        local faction = catalog and catalog.faction and catalog.faction(actor.factionId) or nil
        local factionSupport = faction and faction.support or nil
        allowed = factionSupport ~= nil and factionSupport.policy == "any"
    end)
    return allowed
end

function Support.callerAlive(groupId)
    if type(Support.adapters.radiomanAlive) == "function" then return Support.adapters.radiomanAlive(groupId) end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or groupId == nil then return false end
    for _, record in ipairs(registry.list()) do
        local memory = type(record.memory) == "table" and record.memory or {}
        if memory.groupId == groupId and record.lifecycle ~= "dead"
                and Support.mayCallRadio(record) then return true end
    end
    return false
end

local function broadcast(payload)
    if type(Support.adapters.broadcast) == "function" then return Support.adapters.broadcast(payload) end
    pcall(function()
        if type(isServer) ~= "function" or not isServer() then return end
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players == nil then return end
        for index = 0, players:size() - 1 do
            local player = players:get(index)
            if player ~= nil then sendServerCommand(player, "ProjectALife", "supportArrival", payload) end
        end
    end)

    pcall(function()
        local fx = ProjectALife.SupportClient
        if fx ~= nil and type(fx.onArrival) == "function" then fx.onArrival(payload) end
    end)
end

local function broadcastSpotlight(payload)
    if type(Support.adapters.spotlight) == "function" then return Support.adapters.spotlight(payload) end
    pcall(function()
        if type(isServer) ~= "function" or not isServer() then return end
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players == nil then return end
        for index = 0, players:size() - 1 do
            local player = players:get(index)
            if player ~= nil then sendServerCommand(player, "ProjectALife", "supportSpotlight", payload) end
        end
    end)
    pcall(function()
        local fx = ProjectALife.SupportClient
        if fx ~= nil and type(fx.onSpotlight) == "function" then fx.onSpotlight(payload) end
    end)
end

local function isNight()
    if type(Support.adapters.isNight) == "function" then return Support.adapters.isNight() == true end
    local night = false
    pcall(function()
        local hour = getGameTime():getHour()
        night = hour >= 21 or hour < 6
        if not night and type(getClimateManager) == "function" then
            night = getClimateManager():getDayLightStrength() < Support.settings.lowLightStrength
        end
    end)
    return night
end

local function worldNoise(x, y, z, radius, volume)
    local first = ProjectALife.FirstDays
    if first ~= nil and type(first.noteNoise) == "function" then pcall(first.noteNoise, x, y, z, radius, "heli") end
    if type(Support.adapters.noise) == "function" then return Support.adapters.noise(x, y, z, radius, volume) end
    pcall(function()
        if type(addSound) == "function" then addSound(nil, math.floor(x), math.floor(y), math.floor(z or 0), radius, volume) end
    end)
end

Support.worldNoise = worldNoise

Support.settings.backupCars = {
    "Base.PickUpTruck", "Base.PickUpVan", "Base.CarNormal", "Base.CarStationWagon",
    "Base.CarStationWagon2", "Base.SUV", "Base.OffRoad", "Base.SmallCar", "Base.SmallCar02",
    "Base.ModernCar", "Base.ModernCar02", "Base.StepVan", "Base.PickUpTruck_Camo",
    "Base.PickUpVan_Camo", "Base.CarNormalSmashedFront", "Base.PickUpTruckSmashedLeft",
    "Base.SUVSmashedRear", "Base.OffRoadSmashedRight",
}

Support.settings.backupCarCondition = { min = 10, max = 30 }

function Support.backupCarScript(value)
    local pool = Support.settings.backupCars
    local index = 1 + math.floor((tonumber(value) or 0) * #pool)
    return pool[math.max(1, math.min(#pool, index))]
end

function Support.wornCondition(value)
    local band = Support.settings.backupCarCondition
    return math.floor(band.min + (tonumber(value) or 0) * (band.max - band.min + 1))
end

function Support.wearCar(vehicle)
    local worn = 0
    pcall(function()
        for index = 0, vehicle:getPartCount() - 1 do
            local part = vehicle:getPartByIndex(index)
            pcall(function()
                part:setCondition(math.min(part:getCondition(), Support.wornCondition(roll())))
                vehicle:transmitPartCondition(part)
                worn = worn + 1
            end)
        end
        pcall(function() vehicle:setRust(0.5 + roll() * 0.4) end)
        local tank = vehicle:getPartById("GasTank")
        if tank ~= nil then
            tank:setContainerContentAmount(2 + math.floor(roll() * 6))
            pcall(function() vehicle:transmitPartModData(tank) end)
        end
    end)
    return worn
end

function Support.parkCar(point, towardX, towardY, script, worn)
    if type(point) ~= "table" then return false end
    local builder = ProjectALife.OutpostBuilder
    if builder == nil or type(builder.placeVehicle) ~= "function" then return false end
    local bx, by = math.floor(tonumber(point.x) or 0), math.floor(tonumber(point.y) or 0)
    local best
    pcall(function()
        local cell = getCell()
        for radius = 0, 5 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if best == nil and (math.abs(dx) == radius or math.abs(dy) == radius) then
                        local clear = true
                        for ox = -1, 1 do
                            for oy = -2, 2 do
                                local square = cell:getGridSquare(bx + dx + ox, by + dy + oy, 0)
                                if square == nil or not square:isOutside() or square:isFree(false) ~= true then clear = false end
                            end
                        end
                        if clear then best = { x = bx + dx, y = by + dy } end
                    end
                end
            end
        end
    end)
    if best == nil then return false end
    local dx, dy = (tonumber(towardX) or best.x) - best.x, (tonumber(towardY) or best.y) - best.y
    local facing
    if math.abs(dx) > math.abs(dy) then facing = dx > 0 and "E" or "W" else facing = dy > 0 and "S" or "N" end
    local car = builder.placeVehicle(best.x, best.y, 0, script or "Base.PickUpTruck", facing, 12)
    if car ~= nil then
        Support.metrics.vehicles = (Support.metrics.vehicles or 0) + 1
        if worn == true then Support.wearCar(car) end
    end
    return car ~= nil
end

local function dispatchAt(actor, sx, sy, contact, doctrine, now, hours, extra)
    local service = Support.adapters.service or ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function" then return false, "no_spawn_service" end
    extra = extra or {}
    local cx, cy = tonumber(contact.x) or 0, tonumber(contact.y) or 0
    local delivery = Support.deliveryFor(doctrine, roll())
    local point = Support.insertionPoint(delivery, sx, sy, cx, cy, roll())
    local supportId = extra.requestId or ("support:" .. tostring(actor.uid) .. ":" .. tostring(math.floor(now)))
    local count = doctrine.size
    local supportFactionId = Support.supportFaction(actor.factionId, doctrine,
        extra.callNumber)
    local profileIds = type(service.hostileProfileIds) == "function"
        and service.hostileProfileIds(count, math.floor(now / 1000), supportFactionId, true) or nil
    if type(profileIds) ~= "table" or #profileIds == 0 then return false, "no_profiles" end
    local player = extra.player or Support.adapters.player
    if player == nil then
        pcall(function()
            local locator = ProjectALife.PlayerLocator
            player = locator and locator.list()[1] or nil
        end)
    end

    local vehicleKind = delivery == "ground" and doctrine.vehicle or nil
    local ok, spawnReason = ProjectALife.WorldPressure.spawn(service, player, {
        requestId = extra.requestId or supportId,
        count = count,
        factionId = supportFactionId,
        x = point.x, y = point.y, z = 0,
        distance = 0, separation = 1.5, radius = 6,
        mode = "assault", profile = "seek_destroy",
        profileIds = profileIds,
        atomicGroup = true,

        playerKeepOut = 0,

        spawnDelayMs = delivery == "heli" and 22000 or (delivery == "ground" and 11000 or 0),
        conducts = { "leader" },
        animation = "normal",
        encounterId = extra.encounterId or supportId,
        encounterPersistent = false,
        supportPolicy = "disabled",
        supportRole = "backup",
        supportForGroupId = actor.memory and actor.memory.groupId or ("solo:" .. tostring(actor.uid)),
        objectiveX = cx, objectiveY = cy,

        targetUsername = (not extra.friendly) and contact.playerKey or nil,
        outpostId = extra.outpostId,
        siteKey = extra.siteKey,
        arrival = delivery,
    }, hours, { bypass = extra.friendly == true, call = extra.call })
    if not ok then return false, spawnReason or "spawn_refused" end
    if not extra.friendly and (contact.playerKey or contact.targetUid) then
        Support.intel[supportId] = { groupId = supportId, playerKey = contact.playerKey, targetUid = contact.targetUid,
            kind = "arrival", expiresAtMs = now + 30000 }
    end
    if type(service.watchGroup) == "function" then
        service.watchGroup(supportId, function(outcome)
            if outcome.ok == true and extra.parkCar == true and delivery == "ground" then
                pcall(Support.parkCar, point, cx, cy, Support.backupCarScript(roll()), true)
            end
            emit(outcome.ok == true and "support_arrived" or "support_failed", {
                squad = supportId, factionId = supportFactionId,
                count = outcome.ok == true and outcome.active or outcome.failed })
        end)
    end
    if delivery == "heli" then
        worldNoise(point.x, point.y, 0, Support.settings.heliNoiseRadius, Support.settings.heliNoiseVolume)
    else
        worldNoise(point.x, point.y, 0, Support.settings.noiseRadius, Support.settings.noiseVolume)
    end
    local lit = false
    local director = ProjectALife.HeliDirector
    if delivery == "heli" and doctrine.heli == "support_spotlight" and isNight() and director ~= nil
            and type(director.start) == "function" and (contact.playerKey or contact.targetUid) then
        lit = director.start({ id = supportId, startX = point.x, startY = point.y, anchorX = cx, anchorY = cy,
            durationS = Support.settings.heliDurationS, seed = math.floor(now), nowMs = now, targetKey = contact.playerKey,
            targetUid = contact.targetUid, groupId = actor.memory and actor.memory.groupId or nil,
            factionId = actor.factionId, radius = Support.settings.spotlightRadius,
            brightness = Support.settings.spotlightBrightness / 100 }) ~= nil
    end
    broadcast({ supportId = supportId, x = point.x, y = point.y, z = 0, delivery = delivery, mode = doctrine.type,
        tx = cx, ty = cy, duration = Support.settings.heliDurationS, vehicle = vehicleKind,
        targetUsername = contact.playerKey,
        targetUid = contact.targetUid, spotlight = lit,
        factionId = supportFactionId, callerFactionId = actor.factionId })
    emit("support_faction", { squad = supportId, factionId = supportFactionId,
        callerFactionId = actor.factionId, delivery = delivery, count = #profileIds })
    if vehicleKind ~= nil then emit("support_vehicle", { squad = supportId, task = vehicleKind, count = 1 }) end
    return true, supportId
end

local function dispatch(actor, shell, contact, doctrine, now, hours, callNumber)
    local sx, sy = 0, 0
    pcall(function() sx, sy = shell:getX(), shell:getY() end)
    return dispatchAt(actor, sx, sy, contact, doctrine, now, hours,
        { callNumber = callNumber })
end

local function watchCall(entry, requestId, hours)
    local service = Support.adapters.service or ProjectALife.DebugService
    if service == nil or type(service.watchGroup) ~= "function" then return end
    service.watchGroup(requestId, function(outcome)
        if outcome.ok == true or (tonumber(outcome.active) or 0) > 0 then return end
        entry.calls = math.max(0, entry.calls - 1)
        entry.nextAtHours = math.min(tonumber(entry.nextAtHours) or hours, hours)
        entry.nextAttemptMs = nowMs() + Support.settings.backoffMs
        Support.persistLedger()
    end)
end

function Support.commsDown(outpostId)
    if outpostId == nil then return false end
    if type(Support.adapters.commsDown) == "function" then return Support.adapters.commsDown(outpostId) == true end
    local down = false
    pcall(function()
        local registry = ProjectALife.OutpostRegistry
        local site = registry and registry.read(tostring(outpostId)) or nil
        down = site ~= nil and site.commsDisabled == true
    end)
    return down
end

local function outpostOrigin(site)
    local door = type(site.mainEntrance) == "table" and site.mainEntrance or nil
    local x, y = tonumber(site.x) or 0, tonumber(site.y) or 0
    if door ~= nil then
        local side = tostring(door.side or "")
        local dx, dy = 0, 0
        if side == "N" then dy = -2 elseif side == "S" then dy = 2 elseif side == "E" then dx = 2 elseif side == "W" then dx = -2 end
        x, y = (tonumber(door.x) or x) + dx, (tonumber(door.y) or y) + dy
    end
    return x, y
end

function Support.callKey(site)
    local stamp = tonumber(site.backupCallHours) or tonumber(site.commsDisabledHours)
    if stamp == nil then return nil end
    return "outpostcall:" .. tostring(site.id) .. ":" .. tostring(math.floor(stamp * 100))
end

function Support.requestFromOutpost(site, contact, purpose, now, hours, player)
    if not Support.enabled or type(site) ~= "table" or type(contact) ~= "table" then return false, "support_off" end
    if purpose ~= "help" and Support.againstPlayersOff(contact, now) then return false, "hostile_off" end
    now = tonumber(now) or nowMs()
    hours = tonumber(hours) or worldHours()
    Support.metrics.requests = Support.metrics.requests + 1
    local faction
    pcall(function() faction = ProjectALife.Catalog and ProjectALife.Catalog.faction(site.factionId) or nil end)
    local doctrine = Support.doctrineFor(nil, faction)
    doctrine.policy = "any"

    if purpose == "backup" then doctrine.type = "ground" end
    local groupId = "outpost:" .. tostring(site.id) .. ":" .. tostring(purpose)
    local entry = Support.ledger[groupId] or { calls = 0, nextAtHours = -1e9, nextAttemptMs = 0 }
    Support.ledger[groupId] = entry
    local call = purpose == "backup" and Support.callKey(site) or nil
    if purpose ~= "help" then
        if (tonumber(site.backups) or 0) >= math.max(0, tonumber(site.backupCap) or 1) then
            return false, "calls_spent"
        end
        if hours < (tonumber(entry.nextAtHours) or -1e9) and (call == nil or entry.call ~= call) then
            return false, "cooldown"
        end
    end
    if now < (tonumber(entry.nextAttemptMs) or 0) then
        Support.metrics.refused = Support.metrics.refused + 1
        return false, "backoff"
    end
    local ox, oy = outpostOrigin(site)
    local prefix = purpose == "help" and "outposthelp:" or "outpostbackup:"
    local previousCall = entry.call
    entry.call = call
    if not Support.takeCall(entry, hours, doctrine.cooldownHours) then
        entry.call = previousCall
        return false, "support_persistence"
    end
    local sent, detail = dispatchAt({ uid = "outpost:" .. tostring(site.id), factionId = site.factionId }, ox, oy,
        contact, doctrine, now, hours, {
            encounterId = prefix .. tostring(site.id),
            requestId = prefix .. tostring(site.id) .. ":" .. tostring(math.floor(now)),
            outpostId = site.id, player = player, friendly = purpose == "help",
            callNumber = entry.calls, parkCar = purpose == "backup",
            siteKey = "outpost-location:" .. tostring(site.x) .. ":" .. tostring(site.y),
            call = call,
        })
    if not sent then
        entry.calls = math.max(0, entry.calls - 1)
        entry.nextAtHours = hours
        Support.persistLedger()
        entry.nextAttemptMs = now + Support.settings.backoffMs
        Support.metrics.refused = Support.metrics.refused + 1
        return false, detail
    end
    watchCall(entry, detail, hours)
    Support.metrics.dispatched = Support.metrics.dispatched + 1
    emit("support_dispatched", { squad = groupId, task = detail, count = doctrine.size })
    return true, detail
end

function Support.againstPlayersOff(contact, now)
    local fair = ProjectALife.Fairness
    return type(contact) == "table" and contact.playerKey ~= nil and fair ~= nil
        and type(fair.hostileOff) == "function" and fair.hostileOff(now) == true
end

function Support.noteReason(reason)
    local reasons = Support.metrics.reasons
    if type(reasons) ~= "table" then
        reasons = {}
        Support.metrics.reasons = reasons
    end
    reason = tostring(reason)
    reasons[reason] = (reasons[reason] or 0) + 1
    return reason
end

function Support.refuse(reason)
    Support.metrics.refused = Support.metrics.refused + 1
    Support.noteReason(reason)
    return false, reason
end

function Support.request(actor, shell, contact, now)
    if not Support.enabled or type(actor) ~= "table" or type(contact) ~= "table" then return false, "support_off" end
    if Support.againstPlayersOff(contact, now) then
        return Support.refuse("hostile_off")
    end

    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.relaySupport) == "function"
            and type(executor.clientAuthority) == "function" and executor.clientAuthority() then
        local memory = type(actor.memory) == "table" and actor.memory or {}
        Support.relayLocks[memory.groupId or ("solo:" .. tostring(actor.uid))] = (tonumber(now) or nowMs()) + Support.relayLockMs
        return executor.relaySupport(actor, contact)
    end
    now = tonumber(now) or nowMs()
    local hours = worldHours()
    Support.metrics.requests = Support.metrics.requests + 1
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local faction
    pcall(function() faction = ProjectALife.Catalog and ProjectALife.Catalog.faction(actor.factionId) or nil end)
    local profile = ProjectALife.Catalog and ProjectALife.Catalog.npc
        and ProjectALife.Catalog.npc(actor.profileId) or nil
    local doctrine = Support.doctrineFor(memory, faction, profile)
    local groupId = memory.groupId or ("solo:" .. tostring(actor.uid))

    local sx, sy = 0, 0
    pcall(function() sx, sy = shell:getX(), shell:getY() end)
    local home = memory.home or memory.spawnOrigin
    if type(home) == "table" and distance(sx, sy, tonumber(home.x) or sx, tonumber(home.y) or sy) > Support.settings.callerHomeRange then
        return Support.refuse("caller_far_from_home")
    end
    if distance(sx, sy, tonumber(contact.x) or sx, tonumber(contact.y) or sy) > Support.settings.contactRange then
        return Support.refuse("contact_far")
    end
    if doctrine.policy == "radio" and not Support.mayCallRadio(actor) then
        return Support.refuse("radio_only")
    end

    local modules = ProjectALife.ModuleRegistry
    if modules and modules.get("radioman") and not modules.allows(actor, "radioman") then
        return Support.refuse("caller_module_disabled")
    end

    if doctrine.policy ~= "disabled" and doctrine.heli == "spotlight"
            and (doctrine.type == "heli" or doctrine.type == "both")
            and (doctrine.policy ~= "radio" or (Support.mayCallRadio(actor)
                and Support.callerAlive(memory.groupId)))
            and not (memory.outpostId ~= nil and Support.commsDown(memory.outpostId)) then

        local lit, spotlightReason = Support.spotlight(groupId, shell, contact, now, nil, actor.factionId)

        if doctrine.type == "heli" then
            Support.noteReason(lit and "spotlight_only" or ("spotlight_" .. tostring(spotlightReason)))
            return lit, spotlightReason
        end
    end

    local entry = Support.ledger[groupId]
    local ok, reason = Support.mayCall(entry, doctrine, hours, now,
        doctrine.policy == "radio" and Support.callerAlive(memory.groupId) or nil)
    if not ok then
        return Support.refuse(reason)
    end

    if memory.outpostId ~= nil and Support.commsDown(memory.outpostId) then
        return Support.refuse("comms_down")
    end
    entry = entry or { calls = 0, nextAtHours = -1e9, nextAttemptMs = 0 }
    Support.ledger[groupId] = entry

    if roll() * 100 >= Support.settings.successPercent then
        entry.nextAttemptMs = now + Support.settings.backoffMs
        Support.metrics.rolledOff = Support.metrics.rolledOff + 1
        emit("support_rolled_off", { squad = groupId, task = "no answer" })
        Support.noteReason("rolled_off")
        return false, "rolled_off"
    end
    if not Support.takeCall(entry, hours, doctrine.cooldownHours) then return Support.refuse("support_persistence") end
    local sent, detail = dispatch(actor, shell, contact, doctrine, now, hours, entry.calls)
    if not sent then
        entry.calls = math.max(0, entry.calls - 1)
        entry.nextAtHours = hours
        Support.persistLedger()
        entry.nextAttemptMs = now + Support.settings.backoffMs
        return Support.refuse(detail)
    end
    watchCall(entry, detail, hours)
    Support.metrics.dispatched = Support.metrics.dispatched + 1
    emit("support_dispatched", { squad = groupId, task = detail, count = doctrine.size })
    return true, detail
end

function Support.contactFromTarget(target)
    if target == nil then return nil end
    local contact
    pcall(function()
        if target:isDead() then return end
        contact = { x = target:getX(), y = target:getY(), z = target:getZ() }
        if target.getUsername then contact.playerKey = target:getUsername()
        elseif target.getModData then contact.targetUid = target:getModData().ProjectALifeUID end
    end)
    return contact
end

function Support.spotlight(groupId, shell, contact, now, forced, factionId)
    if not Support.enabled or type(contact) ~= "table" then return false, "support_off" end
    if not Support.helicoptersAllowed() then return false, "helicopters_off" end
    if Support.settings.spotlightEnabled == false then return false, "spotlight_off" end
    if not isNight() then return false, "daylight" end
    now = tonumber(now) or nowMs()

    for _, track in pairs(Support.intel) do
        if track.kind == "spotlight" and now < track.expiresAtMs then return false, "aircraft_busy" end
    end
    if now < (tonumber(Support.lastSpotlightUntilMs) or -math.huge)
            + (tonumber(Support.settings.spotlightWorldGapMs) or 0) then
        return false, "aircraft_resting"
    end

    local tactics = ProjectALife.SquadTactics
    local held = tactics and tactics.contacts and tactics.contacts[groupId]
    if held and held.kind == "player" and now - (tonumber(held.atMs) or 0) <= 12000 then
        contact = Support.contactFromTarget(held.target) or contact
    end
    if not contact.playerKey and not contact.targetUid then return false, "unidentified_target" end
    local key = "spot:" .. tostring(groupId)
    local entry = Support.ledger[key] or { calls = 0, nextAtHours = -1e9, nextAttemptMs = 0 }
    Support.ledger[key] = entry
    if now < (tonumber(entry.nextAttemptMs) or 0) then return false, "backoff" end
    if forced ~= true and roll() * 100 >= Support.settings.spotlightPercent then
        entry.nextAttemptMs = now + Support.settings.spotlightBackoffMs
        return false, "rolled_off"
    end
    entry.nextAttemptMs = now + Support.settings.spotlightCooldownMs
    entry.calls = entry.calls + 1
    local sx, sy = 0, 0
    pcall(function() sx, sy = shell:getX(), shell:getY() end)
    local cx, cy = tonumber(contact.x) or sx, tonumber(contact.y) or sy
    local point = Support.insertionPoint("heli", sx, sy, cx, cy, roll())
    local payload = { supportId = "spotlight:" .. tostring(groupId) .. ":" .. tostring(math.floor(now)),
        x = cx, y = cy, z = contact.z or 0, tx = cx, ty = cy, ix = point.x, iy = point.y,
        targetUsername = contact.playerKey, targetUid = contact.targetUid,
        duration = Support.settings.spotlightDurationS, delivery = "spotlight",
        radius = Support.settings.spotlightRadius, brightness = Support.settings.spotlightBrightness / 100 }
    local heli = ProjectALife.HeliDirector
    if heli ~= nil and type(heli.start) == "function" then
        local flight, why = heli.start({ id = payload.supportId, startX = point.x, startY = point.y,
            anchorX = cx, anchorY = cy, durationS = payload.duration, seed = math.floor(now), nowMs = now,
            targetKey = contact.playerKey, targetUid = contact.targetUid, groupId = groupId,
            factionId = factionId, radius = payload.radius, brightness = payload.brightness })
        if flight == nil and why ~= nil then
            entry.nextAttemptMs = now + Support.settings.spotlightBackoffMs
            entry.calls = math.max(0, entry.calls - 1)
            return false, why
        end
    end
    broadcastSpotlight(payload)
    Support.intel[payload.supportId] = { groupId = groupId, playerKey = contact.playerKey, targetUid = contact.targetUid,
        kind = "spotlight", expiresAtMs = now + payload.duration * 1000,
        originX = cx, originY = cy }
    Support.lastSpotlightUntilMs = now + payload.duration * 1000
    worldNoise(cx, cy, 0, Support.settings.heliNoiseRadius, Support.settings.heliNoiseVolume)
    Support.metrics.spotlights = Support.metrics.spotlights + 1
    emit("support_spotlight", { squad = groupId, task = "spotlight", count = 1 })
    return true, payload.supportId
end

function Support.tick()
    local now = nowMs()
    if now < (Support.nextIntelAtMs or 0) then return end
    Support.nextIntelAtMs = now + 1000
    local registry, watchdog = ProjectALife.ActorRegistry, ProjectALife.Watchdog
    if not registry or not watchdog then return end

    local players
    local read = registry.peek or registry.read
    for key, track in pairs(Support.intel) do
        if now >= track.expiresAtMs then
            Support.intel[key] = nil
        else
            local target
            players = players or Support.adapters.players or
                (ProjectALife.PlayerLocator and ProjectALife.PlayerLocator.list()) or {}
            for _, player in ipairs(players) do
                if player:getUsername() == track.playerKey and not player:isDead() then target = player; break end
            end
            if not track.playerKey and track.targetUid then
                local binding = watchdog.bindings[track.targetUid]
                local subject = binding and binding.shell
                if subject and not subject:isDead() then target = subject end
            end
            local report = target ~= nil
            if report and track.kind == "spotlight" then
                report = now < (tonumber(track.spottedUntilMs) or 0)
                    and distance(target:getX(), target:getY(), track.originX, track.originY) <= Support.settings.contactRange
            end
            for uid, binding in pairs(watchdog.bindings) do
                local actor = read(uid)
                if binding.shell and actor and actor.lifecycle == "active" and actor.memory
                        and (actor.memory.groupId or ("solo:" .. uid)) == track.groupId then
                    if track.kind == "arrival" and not track.startedAtMs then
                        track.startedAtMs, track.expiresAtMs = now, now + 5000
                    end
                    if report then
                        local point = { x = target:getX(), y = target:getY(), z = target:getZ() }
                        point.untilMs = now + (track.kind == "spotlight" and 10000 or 90000)
                        registry.updateTransient(uid, actor.revision, function(record)
                            local field = track.kind == "arrival" and "objective" or "supportSpotlightObjective"
                            record.memory[field] = point
                        end)
                    end
                end
            end
        end
    end
end

if type(Events) == "table" and Events.OnTick then Events.OnTick.Add(Support.tick) end

function Support.reset()
    Support.ledger, Support.intel, Support.nextIntelAtMs = Support.readLedger(), {}, nil
    Support.lastSpotlightUntilMs = nil
    local director = ProjectALife.HeliDirector
    if director ~= nil and type(director.reset) == "function" then director.reset() end
    return true
end

return Support
