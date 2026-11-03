require "ProjectALife/Outposts/ALifeOutpostPresets"
require "ProjectALife/Outposts/ALifeOutpostRegistry"
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Movement/ALifeUpperPosts"
require "ProjectALife/World/ALifeWorldPressure"
require "ProjectALife/Outposts/ALifeOutpostBuilder"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/World/ALifeRoadGraph"
require "ProjectALife/Offline/ALifeSquadLedger"

require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/Records/ALifePartyPolicy"
require "ProjectALife/Compat/ALifeInterop"
ProjectALife = ProjectALife or {}

local Presets = ProjectALife.OutpostPresets
local Registry = ProjectALife.OutpostRegistry
local Builder = ProjectALife.OutpostBuilder
local Telemetry = ProjectALife.Telemetry
local Interop = ProjectALife.Interop

local Director = {
    adapters = {},
    enabled = true,
    settings = {
        maxSites = 6,
        perCity = 1,
        intervalMinutes = 30,

        rollOnWorldClock = true,
        chancePercent = 20,
        buildRadius = 120,
        spawnRadius = 90,
        minPlayerDistance = 40,
        garrisonDeadHours = 24,

        structureLossPercent = 40,
        structureSample = 24,
        structureReviewMs = 15000,
        structureRadius = 90,
        structureMinSampled = 16,
        structureMinLost = 3,
        structureStrikes = 2,
        structureRecheck = 64,

        ringMinimum = 55,
        ringMaximum = 140,

        townStandoffMinimum = 30,
        townStandoffMaximum = 600,

        siteAttempts = 12,

        scanBudgetMs = 6,
        scanCoarse = true,
        scanBlock = 128,
        scanBackoffHours = 1,
        scanBackoffCapHours = 8,
        scanGiveUp = 0,
        scanExpireMs = 600000,

        squadsHardCap = 1,
        huntRadius = 110,
        refusedBackoffHours = 1,

        reinforceAtFraction = 0.5,

        holdoutClearRadius = 120,

        maxOutsideCity = 2,

        buildBudget = 100,
        maxCompounds = 1,
        compoundSpacing = 500,

        drainBudget = 200,
        drainScan = 256,
        drainMs = 25,

        drainProbeStep = 32,

        drainLogMs = 10000,

        garrisonWave = 8,

        crewCeiling = 64,
    },
    state = { lastRollMs = 0 },
    metrics = { rolls = 0, proposed = 0, built = 0, garrisoned = 0, expired = 0, refused = 0,

        avenged = 0,

        drained = 0, drainAbandoned = 0, streamHeld = 0,

        scanSliced = 0, scanResumed = 0, scanBackoffs = 0, negCacheHits = 0, scanWorstMs = 0, scanAbandoned = 0, scanUnloaded = 0,

        garrisonDeferred = {} },
}
ProjectALife.OutpostDirector = Director

local function nowMs()
    if type(Director.adapters.nowMs) == "function" then return Director.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    if type(Director.adapters.worldHours) == "function" then return Director.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function roll()
    if type(Director.adapters.roll) == "function" then return Director.adapters.roll() end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000000) / 1000000 end
    return 1
end

local function players()
    if type(Director.adapters.players) == "function" then return Director.adapters.players() or {} end
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

local function emit(category, fields)
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then
        pcall(Telemetry.emit, category, fields)
    end
end

function Director.configure(adapters)
    Director.adapters = adapters or {}
    local s = Director.settings
    local a = Director.adapters

    s.squadsHardCap = math.max(0, math.min(6, math.floor(tonumber(a.squadsHardCap) or 1)))
    if a.maxSites ~= nil then s.maxSites = math.max(0, math.min(40, math.floor(tonumber(a.maxSites) or 6))) end
    if a.perCity ~= nil then s.perCity = math.max(1, math.min(6, math.floor(tonumber(a.perCity) or 1))) end
    if a.intervalMinutes ~= nil then s.intervalMinutes = math.max(5, math.min(120, tonumber(a.intervalMinutes) or 30)) end
    if a.rollOnWorldClock ~= nil then s.rollOnWorldClock = a.rollOnWorldClock ~= false end
    if a.chancePercent ~= nil then s.chancePercent = math.max(0, math.min(100, tonumber(a.chancePercent) or 20)) end
    if a.buildRadius ~= nil then s.buildRadius = math.max(60, math.min(200, tonumber(a.buildRadius) or 120)) end
    Builder.streamGuard.stillMs = math.max(5, math.min(30, tonumber(a.streamHoldSeconds) or 5)) * 1000
    s.buildBudget = math.max(1, math.min(2000, math.floor(tonumber(a.buildBudget) or 100)))
    s.maxCompounds = math.max(0, math.min(40, math.floor(tonumber(a.maxCompounds) or 1)))
    s.compoundSpacing = math.max(0, math.min(5000, tonumber(a.compoundSpacing) or 500))
    if a.spawnRadius ~= nil then s.spawnRadius = math.max(40, math.min(150, tonumber(a.spawnRadius) or 90)) end
    if a.structureLossPercent ~= nil then
        s.structureLossPercent = math.max(0, math.min(100, tonumber(a.structureLossPercent) or 40))
    end

    if a.maxOutsideCity ~= nil then s.maxOutsideCity = math.max(0, math.min(20, math.floor(tonumber(a.maxOutsideCity) or 2))) end
    if ProjectALife.OutpostLights ~= nil then ProjectALife.OutpostLights.configure({ lightsOn = a.lightsOn }) end
    Director.enabled = a.enabled ~= false and s.maxSites > 0
    return true
end

function Director.drainMetrics()
    local metrics = Director.metrics
    metrics.drained = tonumber(metrics.drained) or 0
    metrics.drainAbandoned = tonumber(metrics.drainAbandoned) or 0
    metrics.streamHeld = tonumber(metrics.streamHeld) or 0
    for _, key in ipairs({ "scanSliced", "scanResumed", "scanBackoffs", "negCacheHits", "scanWorstMs", "scanAbandoned", "scanUnloaded" }) do
        metrics[key] = tonumber(metrics[key]) or 0
    end
end

function Director.reset()
    Director.state = { lastRollMs = 0, lastRollHours = nil, pendingGarrisons = {} }
    Director.drainMetrics()
    Director.metrics.garrisonDeferred = {}
    return true
end

function Director.garrisonDeferred(site, why)
    local metrics = Director.metrics
    if type(metrics.garrisonDeferred) ~= "table" then metrics.garrisonDeferred = {} end
    metrics.garrisonDeferred[why] = (metrics.garrisonDeferred[why] or 0) + 1
    local state = Director.state
    if type(state.garrisonWhy) ~= "table" then state.garrisonWhy = {} end
    if state.garrisonWhy[site.id] ~= why then
        state.garrisonWhy[site.id] = why
        emit("outpost_garrison_deferred", { site = site.id, reason = why })
    end
    return false
end

local function scanActors(actors, callback)

    if type(actors.each) == "function" then
        actors.each(callback)
        return
    end
    for _, record in ipairs(actors.list()) do callback(record) end
end

local function actorIndex()
    local index = Director.state.index
    if index ~= nil then return index end
    index = { garrison = {}, squadsAlive = {}, squadsSeen = {}, members = {} }
    local actors = Director.adapters.actors or ProjectALife.ActorRegistry
    if actors ~= nil then
        Director.metrics.scans = (Director.metrics.scans or 0) + 1
        scanActors(actors, function(record)
            local memory = type(record.memory) == "table" and record.memory or {}
            local dead = record.lifecycle == "dead"
            local encounter = memory.encounter
            local home = memory.outpostId
            if home == nil and type(encounter) == "string" and string.sub(encounter, 1, 8) == "outpost:" then
                home = string.sub(encounter, 9)
            end
            if home ~= nil and not dead then
                index.members[home] = index.members[home] or {}
                index.members[home][#index.members[home] + 1] = record
            end
            if type(encounter) == "string" and string.sub(encounter, 1, 8) == "outpost:" then
                local siteId = string.sub(encounter, 9)
                local row = index.garrison[siteId]
                if row == nil then
                    row = { alive = 0, total = 0 }
                    index.garrison[siteId] = row
                end
                row.total = row.total + 1
                if not dead then row.alive = row.alive + 1 end
            end
            local squadId = memory.outpostSquadId
            if squadId ~= nil then
                index.squadsSeen[squadId] = true
                if not dead and memory.outpostId ~= nil then
                    index.squadsAlive[squadId] = memory.outpostId
                end
            end
        end)
    end
    Director.state.index = index
    return index
end

local function forgetIndex()
    Director.state.index = nil
end

local function nearestPlayer(x, y, list)
    local best = math.huge
    for _, p in ipairs(list) do
        local dx, dy = x - p.x, y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < best then best = d end
    end
    return best
end

local function overlaps(a, b, margin)
    margin = margin or 0
    return a.x1 - margin <= b.x2 and a.x2 + margin >= b.x1
        and a.y1 - margin <= b.y2 and a.y2 + margin >= b.y1
end

function Director.countOutdoor(sites, classOf)
    local count = 0
    for _, site in ipairs(sites or {}) do
        if site.state ~= "expired" then
            local class = type(classOf) == "function" and classOf(site.presetId) or nil
            if class ~= "building" then count = count + 1 end
        end
    end
    return count
end

function Director.isCompound(preset)
    for _, op in ipairs(type(preset) == "table" and preset.kit or {}) do
        if op.op == "compound" then return true end
    end
    return false
end

function Director.compounds(x, y)
    local alive, nearest = 0, math.huge
    for _, site in ipairs(Registry.list()) do
        if Director.isCompound(Presets.get(site.presetId)) then
            if site.state ~= "expired" then alive = alive + 1 end
            if x ~= nil and y ~= nil then
                local dx, dy = site.x - x, site.y - y
                nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy))
            end
        end
    end
    return alive, nearest
end

function Director.compoundAllowed(preset)
    if not Director.isCompound(preset) then return true end
    local alive = Director.compounds()
    return alive < Director.settings.maxCompounds
end

function Director.compoundSpace(preset, x, y)
    if not Director.isCompound(preset) then return true end
    local _, nearest = Director.compounds(x, y)
    return nearest >= Director.settings.compoundSpacing
end

function Director.pickPreset(day, r)
    local eligible = {}
    for _, preset in ipairs(Presets.list) do
        if preset.placeholder ~= true and preset.manualOnly ~= true
                and day >= (tonumber(preset.minDay) or 0)
                and (preset.lastDay == nil or day < preset.lastDay)
                and Director.compoundAllowed(preset) then
            eligible[#eligible + 1] = preset
        end
    end
    if #eligible == 0 then return nil end
    return eligible[1 + math.floor(r * #eligible) % #eligible]
end

function Director.candidateAt(preset, point)
    local square = getCell():getGridSquare(math.floor(point.x), math.floor(point.y), 0)
    local building = square and square:getBuilding() or nil
    if building == nil or building.getDef == nil then return nil end

    local def = building:getDef()
    if def == nil then return nil end
    local bounds = { x1 = def:getX(), y1 = def:getY(), x2 = def:getX2() - 1, y2 = def:getY2() - 1, z = 0 }
    local area = (bounds.x2 - bounds.x1 + 1) * (bounds.y2 - bounds.y1 + 1)
    local centreX, centreY = math.floor((bounds.x1 + bounds.x2) / 2), math.floor((bounds.y1 + bounds.y2) / 2)
    if area < (tonumber(preset.minArea) or 0) or area > (tonumber(preset.maxArea) or math.huge) then
        return { bounds = bounds, area = area, roomOk = true, x = centreX, y = centreY }
    end
    local roomOk = preset.roomNames == nil
    if not roomOk then
        local poi = ProjectALife.POI
        for x = bounds.x1, bounds.x2, 3 do
            for y = bounds.y1, bounds.y2, 3 do
                local name = poi and poi.roomNameAt(x, y, 0) or nil
                if name ~= nil then
                    for _, wanted in ipairs(preset.roomNames) do
                        if string.find(string.lower(name), wanted, 1, true) then roomOk = true end
                    end
                end
            end
        end
    end
    if not roomOk then
        return { bounds = bounds, area = area, roomOk = false, x = centreX, y = centreY }
    end
    local probe, probed = Builder.probeBuilding(building)
    if probe == nil then return nil end
    bounds = probed or bounds
    local townName
    pcall(function()
        local zones = getWorld():getMetaGrid():getZonesAt(math.floor(point.x), math.floor(point.y), 0)
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            if tostring(zone:getType()) == "TownZone" then townName = tostring(zone:getName() or "") end
        end
    end)
    return { bounds = bounds, probe = probe, area = area, roomOk = roomOk,
        x = math.floor((bounds.x1 + bounds.x2) / 2), y = math.floor((bounds.y1 + bounds.y2) / 2),
        townName = townName }
end

local function candidateBuilding(preset, picked)
    if type(Director.adapters.candidateBuilding) == "function" then
        return Director.adapters.candidateBuilding(preset, picked)
    end
    local result
    pcall(function()
        local encounters = ProjectALife.EncounterDirector
        if encounters == nil or type(encounters.placeFor) ~= "function" then return end
        local point = encounters.placeFor({ placement = "building", locations = { "city" } }, picked.player)
        if point == nil then return end
        result = Director.candidateAt(preset, point)
    end)
    return result
end

local function safehouseOverlap(bounds)
    if type(Director.adapters.safehouseOverlap) == "function" then return Director.adapters.safehouseOverlap(bounds) end
    local hit = false
    pcall(function()
        if SafeHouse == nil or SafeHouse.getSafehouseList == nil then return end
        local list = SafeHouse.getSafehouseList()
        for index = 0, list:size() - 1 do
            local house = list:get(index)
            local rect = { x1 = house:getX(), y1 = house:getY(), x2 = house:getX() + house:getW(), y2 = house:getY() + house:getH() }

            local policy = ProjectALife.SpawnPolicy
            local margin = policy ~= nil
                and tonumber(policy.installationMargin) or 45
            if overlaps(bounds, rect, margin) then hit = true return end
        end
    end)
    return hit
end

local function besidePlayer(bounds, x, y)
    if safehouseOverlap(bounds) then return true, "safehouse" end
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.insidePlayerBuild) ~= "function" then return false end
    local centre = { x = tonumber(x) or 0, y = tonumber(y) or 0, z = 0 }
    if policy.insidePlayerBuild(centre, policy.installationBuiltRadius) then
        return true, "player_ground"
    end

    if type(policy.inPlayerBase) == "function"
            and policy.inPlayerBase(centre, policy.installationMargin) then
        return true, "player_base"
    end
    return false
end

local function ownedGround(bounds, margin)
    margin = math.max(6, math.floor(tonumber(margin) or 6))
    for _, site in ipairs(Registry.list()) do
        if overlaps(bounds, site.bounds, margin) then return true end
    end
    return false
end

local function nearEnoughToTown(x, y)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" then return true end
    local distance = regions.distanceToTown({ x = x, y = y })
    if distance == nil then return true end
    return distance >= Director.settings.townStandoffMinimum
        and distance <= Director.settings.townStandoffMaximum
end

function Director.regionLocked(x, y)
    local locks = ProjectALife.RegionLocks
    if locks == nil or type(locks.refuse) ~= "function" then return false end
    local closed = false
    pcall(function() closed = locks.refuse(x, y) == true end)
    return closed
end

function Director.censusRefusal(picked, candidate, hours)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" then return nil end
    if picked.admin ~= true and type(census.shelterRefusal) == "function" then
        local z = type(candidate.bounds) == "table" and tonumber(candidate.bounds.z) or 0
        local why = census.shelterRefusal(picked.player, candidate.x, candidate.y, z)
        if why ~= nil then return why end
    end
    if type(census.censusClosed) == "function" and census.censusClosed(candidate.x, candidate.y, hours,
            "outpost-location:" .. tostring(candidate.x) .. ":" .. tostring(candidate.y),
            census.censusSettings.siteRadius) then
        return "census_cleared"
    end
    return nil
end

function Director.siteKey(site)
    return "outpost-location:" .. tostring(site.x) .. ":" .. tostring(site.y)
end

function Director.censusCleared(site, hours)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusMarkCleared) ~= "function" then return false end
    return census.censusMarkCleared(Director.siteKey(site), site.x, site.y, hours)
end

function Director.scanKey(preset, picked)
    local block = math.max(16, tonumber(Director.settings.scanBlock) or 128)
    local class = preset.class == "building" and "building" or tostring(preset.id)
    return class .. ":" .. tostring(math.floor((tonumber(picked.x) or 0) / block))
        .. ":" .. tostring(math.floor((tonumber(picked.y) or 0) / block))
end

function Director.scanNegative(key, why, hours)
    local state = Director.state
    if type(state.scanSkip) ~= "table" then state.scanSkip = {} end
    local row = state.scanSkip[key]
    if row == nil then
        row = { fails = 0 }
        local stale = {}
        for other, kept in pairs(state.scanSkip) do
            if hours > kept.untilHours + 24 then stale[#stale + 1] = other end
        end
        for _, other in ipairs(stale) do state.scanSkip[other] = nil end
        state.scanSkip[key] = row
    elseif hours > row.untilHours + 24 then
        row.fails = 0
    end
    row.fails = row.fails + 1
    local span = math.max(0, tonumber(Director.settings.scanBackoffHours) or 1)
    for _ = 2, row.fails do span = span * 2 end
    span = math.min(span, tonumber(Director.settings.scanBackoffCapHours) or 8)
    row.untilHours = hours + span
    row.why = why
    Director.metrics.scanBackoffs = (Director.metrics.scanBackoffs or 0) + 1
end

function Director.scanRefuse(job, why)
    job.stage, job.why = "refused", why
    if (why == "no_building" or why == "ground") and job.key ~= nil then
        if why == "ground" and (tonumber(job.unloaded) or 0) > 0 then
            Director.metrics.scanUnloaded = (tonumber(Director.metrics.scanUnloaded) or 0) + 1
            return
        end
        Director.scanNegative(job.key, why, job.hours)
    end
end

function Director.proposeOpen(hours)
    local list = players()
    if #list == 0 then return nil, "no_players" end
    local picked = list[1 + math.floor(roll() * #list) % #list]
    local day = hours / 24
    local preset = Director.pickPreset(day, roll())
    if preset == nil then return nil, "no_preset_for_day" end
    if Registry.count() >= Director.settings.maxSites then return nil, "site_cap" end
    if preset.class ~= "building" then

        local outdoor = Director.countOutdoor(Registry.list(), function(id)
            local p = Presets.get(id)
            return p and p.class or nil
        end)
        if outdoor >= Director.settings.maxOutsideCity then return nil, "outside_city_cap" end
    end
    local key = Director.scanKey(preset, picked)
    local skips = Director.state.scanSkip
    local row = type(skips) == "table" and skips[key] or nil
    if row ~= nil then
        if hours < row.untilHours then
            Director.metrics.negCacheHits = (Director.metrics.negCacheHits or 0) + 1
            return nil, row.why
        end
    end
    local job = { hours = hours, picked = picked, preset = preset, key = key, ticks = 0, startedMs = nowMs() }
    if preset.class == "building" then
        job.stage = "building"
    else
        local footprint = preset.footprint
        job.stage = "ground"
        job.w, job.h = (footprint and footprint.w) or 10, (footprint and footprint.h) or 10
        job.allowance = footprint and footprint.roadAllowance
        job.attempts = math.max(1, math.floor(tonumber(Director.settings.siteAttempts) or 1))
        job.attempt = 0
    end
    return job
end

function Director.loadedRingMax(picked, ringMin, ringMax)
    local fairness = ProjectALife.SpawnFairness
    if fairness == nil or type(fairness.nearest) ~= "function" or type(fairness.windowCap) ~= "function" then
        return ringMax
    end
    local row = fairness.nearest(picked.x, picked.y)
    if row == nil then return ringMax end
    local cap = tonumber(fairness.windowCap(row, nowMs()))
    if cap == nil then return ringMax end
    return math.max(ringMin + 10, math.min(ringMax, cap))
end

function Director.groundOpen(job)
    local preset, picked, w, h = job.preset, job.picked, job.w, job.h
    local ringMin = (preset.ring and tonumber(preset.ring.min)) or Director.settings.ringMinimum
    local ringMax = (preset.ring and tonumber(preset.ring.max)) or Director.settings.ringMaximum
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() then
        ringMin = math.max(ringMin, fairness.baseRing())
        ringMax = math.max(ringMax, ringMin + 40)
        ringMax = Director.loadedRingMax(picked, ringMin, ringMax)
    end
    local angle, radius = roll() * 2 * math.pi, ringMin + roll() * math.max(0, ringMax - ringMin)
    local cx, cy = math.floor(picked.x + math.cos(angle) * radius), math.floor(picked.y + math.sin(angle) * radius)
    local bounds = { x1 = cx - math.floor(w / 2), y1 = cy - math.floor(h / 2),
        x2 = cx + math.floor(w / 2), y2 = cy + math.floor(h / 2), z = 0 }
    if nearEnoughToTown(cx, cy)
            and Director.compoundSpace(preset, cx, cy)
            and not ownedGround(bounds, math.floor(math.max(w, h) / 2)) then
        job.bounds, job.cx, job.cy = bounds, cx, cy
        return true
    end
    return false
end

function Director.stageGround(job, left)
    if job.nat ~= nil then
        local done = Builder.naturalStep(job.nat, left, Director.stamp)
        if not done then return end
        local free, why = Builder.naturalResult(job.nat)
        job.nat = nil
        if why == "ground_unloaded" then job.unloaded = (tonumber(job.unloaded) or 0) + 1 end
        if free then
            job.candidate = { bounds = job.bounds, x = job.cx, y = job.cy, probe = {} }
            job.stage = "finish"
        end
        return
    end
    if job.attempt >= job.attempts then
        Director.scanRefuse(job, "ground")
        return
    end
    job.attempt = job.attempt + 1
    if not Director.groundOpen(job) then return end
    local bounds, w, h = job.bounds, job.w, job.h
    if Builder.naturalSpace ~= Builder.naturalSpaceBase then
        local free, why = Builder.naturalSpace(bounds.x1, bounds.y1, 0, w, h, job.allowance)
        if why == "ground_unloaded" then job.unloaded = (tonumber(job.unloaded) or 0) + 1 end
        if free then
            job.candidate = { bounds = bounds, x = job.cx, y = job.cy, probe = {} }
            job.stage = "finish"
        end
        return
    end
    job.nat = Builder.naturalBegin(bounds.x1, bounds.y1, 0, w, h, job.allowance, Director.settings.scanCoarse ~= false)
end

function Director.stageBuilding(job, left)
    local encounters = ProjectALife.EncounterDirector
    if type(Director.adapters.candidateBuilding) == "function" or encounters == nil
            or type(encounters.placeBegin) ~= "function" or type(encounters.placeStep) ~= "function" then
        job.candidate = candidateBuilding(job.preset, job.picked)
        job.stage = "check"
        return
    end
    if job.place == nil then
        local opened, place = pcall(encounters.placeBegin, { placement = "building", locations = { "city" } },
            job.picked.player)
        if not opened or place == nil then
            job.stage = "check"
            return
        end
        local cap = tonumber(Director.settings.scanGiveUp) or 0
        if cap > 0 then place.maxUnits = cap end
        job.place = place
    end
    local fine, done = pcall(encounters.placeStep, job.place, left, Director.stamp)
    if not fine then
        job.stage = "check"
        return
    end
    if done ~= true then return end
    if job.place.point == nil then
        job.stage = "check"
    else
        job.point = job.place.point
        job.stage = "at"
    end
end

function Director.stageCheck(job)
    local candidate, preset = job.candidate, job.preset
    if candidate == nil then return Director.scanRefuse(job, "no_building") end
    if candidate.area < preset.minArea or candidate.area > preset.maxArea then return Director.scanRefuse(job, "area") end
    if not candidate.roomOk then return Director.scanRefuse(job, "rooms") end
    local policy = ProjectALife.SpawnPolicy
    if policy ~= nil and type(policy.claimBuilding) == "function" then
        local claimed, claimReason = policy.claimBuilding({ x = candidate.x, y = candidate.y, z = 0 }, candidate.probe)
        if claimed ~= true then return Director.scanRefuse(job, claimReason) end
    end
    job.stage = "finish"
end

function Director.scanRun(job, hours, budgetMs)
    local began = Director.stamp()
    while true do
        local stage = job.stage
        local left = budgetMs
        if left ~= nil then left = math.max(1, budgetMs - (Director.stamp() - began)) end
        if stage == "building" then
            Director.stageBuilding(job, left)
        elseif stage == "at" then
            local fine, found = pcall(Director.candidateAt, job.preset, job.point)
            job.candidate = fine and found or nil
            job.stage = "check"
        elseif stage == "check" then
            Director.stageCheck(job)
        elseif stage == "ground" then
            Director.stageGround(job, left)
        elseif stage == "refused" then
            return true, nil, job.why
        elseif stage == "finish" then
            if budgetMs ~= nil and Director.stamp() - began >= budgetMs then return false end
            if job.key ~= nil and type(Director.state.scanSkip) == "table" then Director.state.scanSkip[job.key] = nil end
            return true, Director.proposeFinish(job, job.candidate, hours)
        end
        if budgetMs ~= nil and Director.stamp() - began >= budgetMs and job.stage ~= "refused" then return false end
    end
end

function Director.proposeFinish(job, candidate, hours)
    local picked, preset = job.picked, job.preset
    local blocked, blockedWhy = besidePlayer(candidate.bounds, candidate.x, candidate.y)
    if blocked then return nil, blockedWhy end
    if ownedGround(candidate.bounds) then return nil, "owned" end
    local refusal = Director.censusRefusal(picked, candidate, hours)
    if refusal ~= nil then return nil, refusal end

    if Director.regionLocked(candidate.x, candidate.y) then return nil, "region_locked" end
    local cityKey = Registry.cityKeyFor(candidate.x, candidate.y, candidate.townName)

    local quota = tonumber(preset.perCity) or Director.settings.perCity
    if Registry.countIn(cityKey) >= quota then return nil, "city_quota" end
    local lifetime = preset.lifetime
    local maxLife = lifetime.minHours + roll() * (lifetime.maxHours - lifetime.minHours)

    if preset.lastDay ~= nil then maxLife = math.max(1, math.min(maxLife, preset.lastDay * 24 - hours)) end
    local factionId = type(Director.adapters.factionFor) == "function"
        and Director.adapters.factionFor(preset) or nil
    local faction
    if factionId == nil then

        faction = ProjectALife.FactionSpawnRules.pick(ProjectALife.Catalog and ProjectALife.Catalog.current,
            { x = candidate.x, y = candidate.y, z = 0 },
            preset.id == "forest_camp" and "camp" or "outpost", roll(), nil, nil, nil, nil,
            function(candidateFaction)

                return ProjectALife.FactionSpawnRules.holdsGround(candidateFaction, preset)
                    and ProjectALife.FactionSpawnRules.seatAllows(candidateFaction, preset.id)
            end)
        if faction == nil then return nil, "no_eligible_faction" end
        factionId = faction.id
    end
    local crewed = type(preset.garrison) == "table" and preset.garrison.crew == true
    if faction and not crewed and ProjectALife.PartyPolicy.choose(faction, roll, 1, 8) <= 0 then
        return nil, "party_exceeds_garrison_budget"
    end
    local pressure = ProjectALife.WorldPressure
    local siteKey = "outpost-location:" .. tostring(candidate.x) .. ":" .. tostring(candidate.y)
    local ticket, refusal = pressure.reserve({ id = siteKey .. ":" .. tostring(nowMs()),
        x = candidate.x, y = candidate.y, z = candidate.bounds.z or 0, hours = hours,
        site = siteKey, pendingHours = 24 })
    if ticket == nil then return nil, refusal end
    local site = Registry.create({
        presetId = preset.id, x = candidate.x, y = candidate.y, cityKey = cityKey,
        bounds = candidate.bounds, createdHours = hours,
        minLifeHours = math.min(lifetime.minHours, maxLife),
        maxLifeHours = maxLife,
        factionId = factionId,
        hostileToPlayers = "faction",
        pressureTicket = ticket,
    })
    if site == nil then pressure.release(ticket, hours); return nil, "registry" end
    Director.metrics.proposed = Director.metrics.proposed + 1
    emit("outpost_proposed", { site = site.id, preset = preset.id, x = site.x, y = site.y })
    return site
end

function Director.propose(hours)
    local job, why = Director.proposeOpen(hours)
    if job == nil then return nil, why end
    local _, site, refusal = Director.scanRun(job, hours, nil)
    return site, refusal
end

function Director.scanAdvance(job, hours)
    local metrics = Director.metrics
    local started = Director.stamp()
    local budget = tonumber(Director.settings.scanBudgetMs) or 0
    if budget <= 0 then budget = nil end
    if job.ticks > 0 then metrics.scanResumed = (metrics.scanResumed or 0) + 1 end
    local done, site, why = Director.scanRun(job, hours, budget)
    local spent = Director.stamp() - started
    if spent > (metrics.scanWorstMs or 0) then metrics.scanWorstMs = spent end
    job.ticks = job.ticks + 1
    if done then
        Director.state.scan = nil
        return true, site, why
    end
    if job.ticks == 1 then metrics.scanSliced = (metrics.scanSliced or 0) + 1 end
    Director.state.scan = job
    return false
end

function Director.proposalResult(site, why)
    if site ~= nil then return 1 end
    why = tostring(why or "unknown")
    Director.metrics.proposeRefused = Director.metrics.proposeRefused or {}
    Director.metrics.proposeRefused[why] = (Director.metrics.proposeRefused[why] or 0) + 1
    emit("outpost_propose_refused", { reason = why })
    return 0
end

function Director.fixedBounds(preset, x, y)
    local w = (preset.footprint and preset.footprint.w) or 10
    local h = (preset.footprint and preset.footprint.h) or 10
    return { x1 = x - math.floor(w / 2), y1 = y - math.floor(h / 2),
        x2 = x + math.floor(w / 2), y2 = y + math.floor(h / 2), z = 0 }
end

function Director.blueprintHome(preset)
    local blueprints = ProjectALife.Blueprints
    if type(preset) ~= "table" or type(preset.blueprint) ~= "table" or blueprints == nil then return nil end
    return blueprints.anchorOf(preset.blueprint.id)
end

function Director.foundFixed(presetId, x, y, hours, factionId, lifetimeHours)
    local preset = Presets.get(presetId)
    if preset == nil then return nil, "no_preset" end
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    local bounds = Director.fixedBounds(preset, x, y)
    local blocked, blockedWhy = besidePlayer(bounds, x, y)
    if blocked then return nil, blockedWhy end
    if ownedGround(bounds) then return nil, "owned" end
    if Director.regionLocked(x, y) then return nil, "region_locked" end

    local life = math.max(1, math.floor(tonumber(lifetimeHours)
        or preset.lifetime.minHours))
    local site = Registry.create({
        presetId = preset.id, x = x, y = y,
        cityKey = Registry.cityKeyFor(x, y, nil),
        bounds = bounds, createdHours = tonumber(hours) or 0,
        minLifeHours = life, maxLifeHours = life,
        factionId = factionId,
        hostileToPlayers = "faction",
    })
    if site == nil then return nil, "registry" end
    Director.metrics.proposed = Director.metrics.proposed + 1
    emit("outpost_proposed", { site = site.id, preset = preset.id, x = site.x, y = site.y })
    return site
end

function Director.streamHold(site, list, box)
    if not Builder.streamActive() or type(site) ~= "table" then return false end
    box = box or site.bounds
    if type(box) ~= "table" or tonumber(box.x1) == nil or tonumber(box.y1) == nil
            or tonumber(box.x2) == nil or tonumber(box.y2) == nil then
        local x, y = tonumber(site.x) or 0, tonumber(site.y) or 0
        box = { x1 = x, y1 = y, x2 = x, y2 = y }
    end
    return Builder.streamHeld(box, list or players(), nowMs())
end

function Director.noteHeld(site, held)
    local now = nowMs()
    Director.state.holdClocks = Director.state.holdClocks or {}
    local last = Director.state.holdClocks[site.id]
    local elapsed = last ~= nil and math.max(0, now - last) or 0
    local fresh = Registry.read(site.id)
    if fresh ~= nil and elapsed > 0 then
        fresh = Registry.update(fresh.id, fresh.revision, function(record)
            record.streamHoldMs = (tonumber(record.streamHoldMs) or 0) + elapsed
        end) or fresh
        Director.metrics.streamHoldMs = (tonumber(Director.metrics.streamHoldMs) or 0) + elapsed
    end
    Director.metrics.streamHoldBySite = Director.metrics.streamHoldBySite or {}
    if fresh ~= nil then
        Director.metrics.streamHoldBySite[site.id] = tonumber(fresh.streamHoldMs) or 0
    end
    local said = Director.state.heldSaid
    if type(said) ~= "table" then
        said = {}
        Director.state.heldSaid = said
    end
    if held ~= true then
        Director.state.holdClocks[site.id] = nil
        if said[site.id] ~= nil then
            emit("outpost_build_resumed", { site = site.id,
                heldMs = fresh ~= nil and tonumber(fresh.streamHoldMs) or 0 })
        end
        said[site.id] = nil
        return
    end
    Director.state.holdClocks[site.id] = now
    Director.metrics.streamHeld = (tonumber(Director.metrics.streamHeld) or 0) + 1
    if said[site.id] == nil then
        said[site.id] = true
        emit("outpost_build_held", { site = site.id, reason = "client_streaming" })
    end
end

local function buildSite(site, list)
    local preset = Presets.get(site.presetId)
    if preset == nil then return false end
    local d = nearestPlayer(site.x, site.y, list)
    local reach = preset.fixedSite == true and math.max(200, Director.settings.buildRadius)
        or Director.settings.buildRadius
    if d > reach then Director.noteHeld(site, false); return false end

    local started = tonumber(site.buildCursor) ~= nil or site.adminBuilt == true
    local minimum = math.max(Director.settings.minPlayerDistance, tonumber(preset.minBuildDistance) or 0)
    if preset.fixedSite ~= true and not started and d < minimum then
        return false
    end
    Director.state.sheets = Director.state.sheets or {}
    Director.state.buildBackoff = Director.state.buildBackoff or {}
    local backoff = Director.state.buildBackoff[site.id]
    local clock = nowMs()
    if backoff ~= nil and clock < backoff.untilMs then return false end
    local cached = Director.state.sheets[site.id] ~= nil
    local probe
    if cached then

        probe = {}
    elseif type(Director.adapters.probeFor) == "function" then
        probe = Director.adapters.probeFor(site)
    elseif preset.class == "building" then
        pcall(function()
            local square = getCell():getGridSquare(site.x, site.y, 0)
            local building = square and square:getBuilding() or nil
            if building ~= nil then probe = Builder.probeBuilding(building) end
        end)
    else
        probe = {}
    end
    if probe == nil then return false end
    if preset.class == "building" and not started and not cached then
        if besidePlayer(site.bounds, site.x, site.y) then return false end
        local policy = ProjectALife.SpawnPolicy
        if policy ~= nil and type(policy.claimBuilding) == "function" then

            local own = site.buildingClaimed == true or tonumber(site.openingsFixed) ~= nil
            local claimed = policy.claimBuilding({ x = site.x, y = site.y, z = tonumber(site.bounds.z) or 0 }, probe,
                own and { ownBoards = true } or nil)
            if claimed ~= true then return false end
            if not own then
                site = Registry.update(site.id, site.revision, function(s) s.buildingClaimed = true end) or site
            end
        end
    end

    Director.state.sheets = Director.state.sheets or {}
    local sheet = Director.state.sheets[site.id]
    if sheet == nil then
        if Director.state.teardownNotified ~= nil then Director.state.teardownNotified[site.id] = nil end
        sheet = Builder.resolve(preset, site, site.x * 31 + site.y, probe)
        if sheet == nil then return false end
        sheet.cursor = Builder.resumeCursor(sheet, site.buildCursor, site.buildLayout)
        Director.state.sheets[site.id] = sheet
    end
    local hold = Director.streamHold(site, list)
    local ok, placed, done = Builder.execute(sheet, site, roll, Director.settings.buildBudget, hold)
    if not ok then
        Director.noteHeld(site, false)
        ProjectALife.WorldPressure.release(site.pressureTicket, worldHours())
        Director.state.sheets[site.id] = nil
        Director.metrics.refused = Director.metrics.refused + 1
        local strikes = (backoff ~= nil and backoff.strikes or 0) + 1
        Director.state.buildBackoff[site.id] = { strikes = strikes,
            untilMs = clock + math.min(300000, 15000 * strikes * strikes) }
        if strikes >= 6 and not started and (tonumber(site.propCount) or 0) == 0 then
            Registry.expire(site.id, site.revision, worldHours(), "build_refused")
            Director.state.buildBackoff[site.id] = nil
            emit("outpost_expired", { site = site.id, reason = "build_refused", deleted = 0, removed = 0, left = 0 })
        end
        return false
    end
    Director.state.buildBackoff[site.id] = nil
    Director.noteHeld(site, hold and done == false)
    if done == false then
        if not (hold and placed == 0) then
            emit("outpost_building", { site = site.id, preset = preset.id,
                done = (tonumber(sheet.cursor) or 1) - 1, total = #sheet.ops })
        end
        return true
    end
    Director.state.sheets[site.id] = nil
    Director.metrics.built = Director.metrics.built + 1
    emit("outpost_built", { site = site.id, preset = preset.id, placed = placed })
    return true
end

function Director.beginBuild(site, sheet)
    if type(site) ~= "table" or site.id == nil or type(sheet) ~= "table"
            or type(sheet.ops) ~= "table" then return false end
    Director.state.sheets = Director.state.sheets or {}
    if Director.state.teardownNotified ~= nil then Director.state.teardownNotified[site.id] = nil end
    sheet.cursor = 1
    Director.state.sheets[site.id] = sheet
    return true
end

local function garrisonPosts(preset, site, count)

    if type(Director.adapters.garrisonPosts) == "function" then
        local supplied = Director.adapters.garrisonPosts(preset, site, count)
        if type(supplied) == "table" and #supplied > 0 then return supplied end
    end

    local result = {}
    for _, post in ipairs(type(site.posts) == "table" and site.posts or {}) do
        if #result >= count then break end

        result[#result + 1] = { x = tonumber(post.x) or site.x, y = tonumber(post.y) or site.y,
            z = tonumber(post.z) or (site.bounds.z or 0), role = post.role, conduct = post.conduct,
            face = type(post.face) == "table" and post.face or nil }
    end
    if preset ~= nil and type(preset.posts) == "table" and #preset.posts > 0 then
        local index = 0
        while #result < count do
            local offset = preset.posts[index % #preset.posts + 1]
            index = index + 1
            result[#result + 1] = { x = site.x + offset.x + 0.5,
                y = site.y + offset.y + 0.5, z = site.bounds.z or 0 }
        end
        return result
    end
    if #result > 0 then return result end
    if preset == nil or preset.class ~= "building" then return nil end
    local slots
    pcall(function()
        local posts = ProjectALife.UpperPosts
        if posts == nil or type(posts.findFloorPosts) ~= "function" then return end
        local found = posts.findFloorPosts(site.x, site.y, site.bounds and site.bounds.z or 0,
            count, 0)
        if type(found) == "table" and #found > 0 then slots = found end
    end)
    return slots
end

function Director.waveInView(slots, keepOut)
    local policy, ring = ProjectALife.SpawnPolicy, ProjectALife.KeepOut
    keepOut = tonumber(keepOut) or 0
    if type(slots) ~= "table" or #slots == 0 or keepOut <= 0 or policy == nil or ring == nil
            or type(policy.playerPoints) ~= "function" or type(ring.spotAllowed) ~= "function" then
        return false
    end
    local points = policy.playerPoints()
    local cone = policy.keepOutSight == true and (tonumber(policy.keepOutCone) or 0) or 0
    for _, slot in ipairs(slots) do
        local x, y = tonumber(slot.x), tonumber(slot.y)
        if x == nil or y == nil or ring.spotAllowed(math.floor(x) + 0.5, math.floor(y) + 0.5,
                points, keepOut, cone, policy.keepOutHalfCos) then
            return false
        end
    end
    return true
end

local function garrison(site, list, hours)
    Director.state.pendingGarrisons = Director.state.pendingGarrisons or {}
    if Director.state.pendingGarrisons[site.id] then return false end
    if hours < (tonumber(site.nextGarrisonHour) or 0) then return Director.garrisonDeferred(site, "backoff") end
    local preset = Presets.get(site.presetId)
    if preset == nil then return Director.garrisonDeferred(site, "no_preset") end
    local nearest, picked = math.huge, nil
    for _, p in ipairs(list) do
        local dx, dy = site.x - p.x, site.y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < nearest then nearest, picked = d, p end
    end
    if picked == nil or nearest > Director.settings.spawnRadius then return Director.garrisonDeferred(site, "too_far") end

    if picked.admin ~= true and preset.fixedSite ~= true and nearest < Director.settings.minPlayerDistance then
        return Director.garrisonDeferred(site, "too_close")
    end
    local service = Director.adapters.service or ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function"
            or type(service.watchGroup) ~= "function" then return Director.garrisonDeferred(site, "no_service") end

    local count = preset.fixedSite == true and preset.garrison.max
        or (preset.garrison.min + math.floor(roll() * (preset.garrison.max - preset.garrison.min + 1)))

    local crewed = type(preset.garrison) == "table" and preset.garrison.crew == true
    if site.garrisonCount == nil and site.factionId and ProjectALife.Catalog and not crewed then
        local faction = ProjectALife.Catalog.faction(site.factionId)
        if faction then
            count = ProjectALife.PartyPolicy.choose(faction, roll, 1, 8)
        end
        if count <= 0 then return Director.garrisonDeferred(site, "party_empty") end
    end

    local ceiling = math.max(1, math.min(crewed and Director.settings.crewCeiling or 16,
        math.floor(tonumber(preset.garrison.max) or 8)))

    local posted = crewed and type(site.posts) == "table" and #site.posts > 0
    if posted then count = #site.posts end
    count = math.max(1, math.min(ceiling, (not posted and tonumber(site.garrisonCount)) or count))

    local planned = count
    local spawned = math.max(0, math.floor(tonumber(site.garrisonSpawned) or 0))
    if spawned >= planned then spawned = 0 end
    count = math.min(planned - spawned, math.max(1, Director.settings.garrisonWave or 11))
    local profileIds = type(service.hostileProfileIds) == "function"
        and service.hostileProfileIds(count, math.floor(hours * 1000), site.factionId, true) or nil
    if type(profileIds) ~= "table" or #profileIds == 0 then
        Director.metrics.refused = Director.metrics.refused + 1
        return Director.garrisonDeferred(site, "no_profiles")
    end
    local requestId = "outpost:" .. site.id .. ":" .. tostring(math.floor(hours * 100)) .. ":"
        .. tostring(nowMs()) .. ":w" .. tostring(spawned)
    local hostileOverride
    if type(site.hostileToPlayers) == "boolean" then hostileOverride = site.hostileToPlayers
    elseif site.hostileToPlayers ~= "faction" and type(preset.hostileToPlayers) == "boolean" then
        hostileOverride = preset.hostileToPlayers
    end

    local allSlots = garrisonPosts(preset, site, planned)
    local slots, conducts, roles, faces
    if type(allSlots) == "table" then
        slots, conducts, roles, faces = {}, {}, {}, {}
        for index = 1, count do
            local slot = allSlots[spawned + index]
            if slot == nil then break end
            slots[index] = slot
            conducts[index] = slot.conduct
            roles[index] = slot.role
            faces[index] = slot.face
        end

        if type(preset.crewProfiles) == "table"
                and (preset.factionId == nil or preset.factionId == site.factionId) then
            local named = Director.crewProfileIds(preset.crewProfiles, slots, spawned)
            if #named == #slots and #named > 0 then profileIds = named end
        end
    end

    if preset.class == "building" and (type(slots) ~= "table" or #slots < count) then
        local fresh = Registry.read(site.id)
        if fresh ~= nil then
            Registry.update(fresh.id, fresh.revision, function(s)
                s.nextGarrisonHour = hours + Director.settings.refusedBackoffHours
            end)
        end
        Director.metrics.refused = Director.metrics.refused + 1
        emit("outpost_garrison_posts_unavailable", { site = site.id, wanted = count,
            found = type(slots) == "table" and #slots or 0 })
        return false
    end
    local args = {

        requestId = requestId, atomicGroup = not crewed,
        count = count,
        factionId = site.factionId,
        x = site.x, y = site.y, z = tonumber(site.bounds.z) or 0,
        distance = 0, separation = 2,
        radius = math.max(6, math.floor((site.bounds.x2 - site.bounds.x1) / 2)),
        mode = "guard", profile = "defend",
        profileIds = profileIds,
        animation = "normal",
        anchor = true,
        encounterId = "outpost:" .. site.id,
        encounterPersistent = true,

        slots = slots,

        conducts = conducts,
        roles = roles,

        faces = faces,

        careful = type(preset.careful) == "table" and preset.careful or nil,

        scripted = type(preset.scripted) == "table" and preset.scripted or nil,
        garrisonBounds = site.bounds,

        holdPost = preset.holdPosts == true or nil,
        stance = preset.stance or "garrison",
        schedule = preset.schedule,
        awareness = preset.awareness,

        hostileOverride = hostileOverride,
        heading = site.mainEntrance and (site.mainEntrance.side == "N" and math.pi / 2
            or site.mainEntrance.side == "E" and 0 or site.mainEntrance.side == "W" and math.pi or -math.pi / 2) or 0,
        outpostId = site.id,
        siteKey = Director.siteKey(site),
    }
    for key, value in pairs(site.spawnOverrides or {}) do args[key] = value end
    args.persistent = false 

    if preset.fixedSite == true then args.playerKeepOut = 0 end

    if picked.admin ~= true and type(service.keepOutFor) == "function"
            and Director.waveInView(slots, service.keepOutFor({ directed = true,
                outpostId = site.id, playerKeepOut = args.playerKeepOut })) then
        return Director.garrisonDeferred(site, "in_view")
    end
    local ok = ProjectALife.WorldPressure.spawn(service, picked.player, args, hours, {
        ticket = site.pressureTicket,
        census = picked.admin ~= true,
        site = "outpost-location:" .. tostring(site.x) .. ":" .. tostring(site.y),
        bypass = picked.admin == true or site.adminBuilt == true or preset.fixedSite == true or spawned > 0,
    }, site.spawnOverrides ~= nil)
    if not ok then
        Director.metrics.refused = Director.metrics.refused + 1
        return Director.garrisonDeferred(site, "spawn_refused")
    end
    if type(Director.state.garrisonWhy) == "table" then Director.state.garrisonWhy[site.id] = nil end
    Director.state.pendingGarrisons[site.id] = requestId
    local watched = service.watchGroup(requestId, function(outcome)
        if Director.state.pendingGarrisons[site.id] ~= requestId then return end
        Director.state.pendingGarrisons[site.id] = nil
        local fresh = Registry.read(site.id)
        if fresh == nil or fresh.state ~= "built" then return end
        local arrived = math.max(0, math.floor(tonumber(outcome.active) or 0))
        local complete = outcome.ok == true and arrived == count

        local fails = 0
        if crewed and arrived == 0 then fails = (tonumber(fresh.garrisonWaveFails) or 0) + 1 end
        local landed = complete or (crewed and (arrived > 0 or fails >= 3))
        local total = landed and arrived or 0
        if spawned > 0 then total = total + math.floor(tonumber(fresh.garrisonArrived) or 0) end
        local last = landed and spawned + count >= planned
        local manned = last and total > 0
        Registry.update(fresh.id, fresh.revision, function(s)

            if landed then
                s.garrisonSpawned = spawned + count
                s.garrisonArrived = total
                s.garrisonWaveFails = nil
            elseif crewed then
                s.garrisonWaveFails = fails
            end

            if last and not manned then s.garrisonSpawned = nil end
            s.state = manned and "garrisoned" or "built"
            if manned then s.garrisonCount = crewed and total or planned end

            if manned then s.nextSquadHour = hours end
            if landed and (manned or not last) then s.nextGarrisonHour = nil
            else s.nextGarrisonHour = hours + Director.settings.refusedBackoffHours end
        end)
        forgetIndex()
        if landed and not last then
            emit("outpost_garrison_wave", { site = site.id, count = arrived,
                spawned = spawned + count, planned = planned })
        elseif manned then
            Director.metrics.garrisoned = Director.metrics.garrisoned + 1
            emit("outpost_garrisoned", { site = site.id, count = crewed and total or planned })

            pcall(function()
                local service = Director.adapters.service or ProjectALife.DebugService
                if service ~= nil and type(service.broadcastOutpostRadios) == "function" then
                    service.broadcastOutpostRadios()
                end
            end)
        else
            Director.metrics.refused = Director.metrics.refused + 1
            emit("outpost_garrison_failed", { site = site.id, requestId = requestId,
                reason = "arrived=" .. tostring(arrived) .. "/" .. tostring(count)
                    .. " failed=" .. tostring(outcome.failed or 0)
                    .. " posts=" .. tostring(spawned + count) .. "/" .. tostring(planned)
                    .. " first=" .. tostring(outcome.reason or "-") })
        end
    end)
    if not watched then

        Director.state.pendingGarrisons[site.id] = nil

        local fresh = Registry.read(site.id)
        if fresh ~= nil then
            Registry.update(fresh.id, fresh.revision, function(s)
                s.nextGarrisonHour = hours + Director.settings.refusedBackoffHours
            end)
        end
        emit("outpost_garrison_receipt_missing", { site = site.id, requestId = requestId })
    end
    return true, "accepted_pending"
end

function Director.garrisonNow(site, player, hours)
    if type(site) ~= "table" or player == nil then return false end
    local x, y = 0, 0
    pcall(function() x, y = player:getX(), player:getY() end)

    return garrison(site, { { player = player, x = x, y = y, admin = true } },
        tonumber(hours) or worldHours())
end

local garrisonAlive

local function garrisonRestored(siteId)
    local actors = Director.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil then return false end
    local found = false
    scanActors(actors, function(record)
        if found then return end
        local memory = type(record.memory) == "table" and record.memory or {}
        if record.lifecycle ~= "dead" and memory.outpostSquadId == nil
                and (memory.outpostId == siteId or memory.encounter == "outpost:" .. tostring(siteId)) then
            found = true
        end
    end)
    return found
end

function Director.resumeSession()

    local outbreak = ProjectALife.RealisticOutbreak
    if outbreak ~= nil and type(outbreak.resume) == "function" then pcall(outbreak.resume) end
    for _, site in ipairs(Registry.list()) do
        if site.state ~= "expired" then
            local restored = site.state == "garrisoned" and garrisonRestored(site.id)
            Registry.update(site.id, site.revision, function(s)
                s.squads = {}
                s.nextGarrisonHour = nil

                s.garrisonSpawned = nil
                s.garrisonArrived = nil
                s.garrisonWaveFails = nil
                if s.state == "garrisoned" and s.garrisonCount ~= 0 and s.garrisonDeadHours == nil
                        and not restored then
                    s.state = "built"
                end
            end)
            if restored then Director.metrics.restored = (Director.metrics.restored or 0) + 1 end
        end
    end
    forgetIndex()
end

function Director.rollTask(weights, r)
    local total = 0
    local order = {}
    for _, name in ipairs({ "patrol", "scavenge", "hunt" }) do
        local weight = tonumber(weights and weights[name]) or 0
        if weight > 0 then
            total = total + weight
            order[#order + 1] = { name = name, weight = weight }
        end
    end
    if total <= 0 then return nil end
    local pick = r * total
    local acc = 0
    for _, entry in ipairs(order) do
        acc = acc + entry.weight
        if pick < acc then return entry.name end
    end
    return order[#order].name
end

function Director.dispatchPoint(site)
    local main = type(site) == "table" and site.mainEntrance or nil
    if type(main) ~= "table" then return { x = site.x, y = site.y, z = 0 } end
    local ox, oy = 0, 1
    if main.side == "N" then ox, oy = 0, -1
    elseif main.side == "W" then ox, oy = -1, 0
    elseif main.side == "E" then ox, oy = 1, 0 end
    return { x = main.x + ox * 2, y = main.y + oy * 2, z = main.z or 0 }
end

Director.settings.dispatchRadius = 60
Director.dispatchSteps = { { 0, 0 }, { 8, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 } }

function Director.dispatchGroundReady(point, list)
    local x, y = tonumber(point.x), tonumber(point.y)
    if x == nil or y == nil or nearestPlayer(x, y, list) > Director.settings.dispatchRadius then return false end
    for _, step in ipairs(Director.dispatchSteps) do
        if not Builder.groundLoaded(x + step[1], y + step[2]) then return false end
    end
    return true
end

local function liveSquads(site)
    local alive = actorIndex().squadsAlive
    local kept, count = {}, 0
    for _, squad in ipairs(site.squads or {}) do
        if alive[squad.id] == site.id or (squad.departedHours ~= nil and squad.pending == true) then
            kept[#kept + 1] = squad
            count = count + 1
        end
    end
    return kept, count
end

function Director.squadCap(site, preset)
    preset = preset or Presets.get(site and site.presetId)
    local maxLive = preset ~= nil and type(preset.squad) == "table" and tonumber(preset.squad.maxLive) or 0
    local base = math.min(Director.settings.squadsHardCap, maxLive)
    return math.max(0, base + math.floor(tonumber(site and site.squadCapBonus) or 0))
end

local function dispatch(site, list, hours)

    if site.disabled == true then return false end
    local preset = Presets.get(site.presetId)
    if preset == nil or type(preset.squad) ~= "table" then return false end

    local forced = type(list) == "table" and type(list[1]) == "table" and list[1].admin == true
    if not forced then
        if site.commsDisabled == true then return false end
    end
    if hours < (tonumber(site.nextSquadHour) or 0) then return false end
    local cap = Director.squadCap(site, preset)
    local kept, count = liveSquads(site)
    if count >= cap then return false end
    local sizeMin, sizeMax = preset.squad.size.min or 2, preset.squad.size.max or 3
    if sizeMax <= 0 then return false end
    local nearest, picked = math.huge, nil
    for _, p in ipairs(list) do
        local dx, dy = site.x - p.x, site.y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < nearest then nearest, picked = d, p end
    end
    if picked == nil or nearest > Director.settings.spawnRadius then return false end

    if not forced and picked.atPlayer ~= true
            and nearest < Director.settings.minPlayerDistance then return false end

    if not forced and picked.atPlayer ~= true
            and not Director.dispatchGroundReady(Director.dispatchPoint(site), list) then return false end

    local pressure = ProjectALife.WorldPressure
    if picked.atPlayer ~= true and not forced and pressure ~= nil
            and pressure.crowded(picked.x, picked.y, hours, { site = site.id }) then
        local fresh = Registry.read(site.id) or site
        Registry.update(fresh.id, fresh.revision, function(s) s.nextSquadHour = hours + 0.5 end)
        return false
    end
    local task = Director.rollTask(preset.squad.taskWeights, roll()) or "patrol"
    if task == "hunt" and not (site.hostileToPlayers == true or site.hostileToPlayers == "faction")
            or (task == "hunt" and nearest > Director.settings.huntRadius)
            or (task == "hunt" and site.hostileToPlayers == "faction"
                and not ProjectALife.FactionSpawnRules.huntsPlayers(site.factionId)) then
        task = "patrol"
    end
    local service = Director.adapters.service or ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function"
            or type(service.watchGroup) ~= "function" then return false end
    local count2 = sizeMin + math.floor(roll() * (sizeMax - sizeMin + 1))
    local profileIds = type(service.hostileProfileIds) == "function"
        and service.hostileProfileIds(count2, math.floor(hours * 1000) + 7, site.factionId) or nil
    local sequence = (tonumber(site.dispatchSequence) or 0) + 1
    local squadId = "outpostsquad:" .. site.id .. ":" .. tostring(sequence)

    local point = picked.atPlayer == true
        and { x = picked.x, y = picked.y, z = 0 }
        or Director.dispatchPoint(site)
    local args = {
        requestId = squadId .. ":" .. tostring(math.floor(hours * 100)),
        count = count2,
        factionId = site.factionId, atomicGroup = true,
        hostileOverride = site.hostileToPlayers,
        x = point.x, y = point.y, z = point.z,
        distance = 0, separation = 1.5, radius = 6,
        animation = "normal",
        profileIds = profileIds,
        encounterId = squadId,
        encounterPersistent = false,
        outpostId = site.id,
        outpostSquadId = squadId,
        siteKey = Director.siteKey(site),
    }

    if forced then args.adminPick = true end
    if task == "patrol" then
        args.mode, args.profile = "patrol", "patrol"
        args.stance = "route"

        local graph = ProjectALife.RoadGraph
        local tx, ty = site.x + 45, site.y
        pcall(function()
            local townId = graph and graph.nearest(site.x, site.y, "town")
            local node = townId and graph.nodes[townId] or nil
            if node ~= nil then
                local dx, dy = node.x - site.x, node.y - site.y
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 1 then tx, ty = site.x + dx / len * 45, site.y + dy / len * 45 end
            end
        end)
        local route = {}
        for index = 0, 3 do
            local angle = index * (math.pi / 2) + math.pi / 4
            route[#route + 1] = { x = tx + math.cos(angle) * 24, y = ty + math.sin(angle) * 24, z = 0 }
        end

        if type(preset.squad.route) == "table" and #preset.squad.route > 0 then
            route = {}
            for _, point in ipairs(preset.squad.route) do
                route[#route + 1] = { x = site.x + (tonumber(point.x) or 0) + 0.5,
                    y = site.y + (tonumber(point.y) or 0) + 0.5, z = 0 }
            end
        end
        args.route = route
    elseif task == "scavenge" then
        args.mode, args.profile = "scavenge", "scavenger"

        pcall(function()
            local graph = ProjectALife.RoadGraph
            if graph == nil or type(graph.nearest) ~= "function" then return end
            local townId = graph.nearest(site.x, site.y, "town")
            local node = townId ~= nil and graph.nodes and graph.nodes[townId] or nil
            if node == nil then return end
            args.scavengeArea = { x = node.x, y = node.y, z = 0 }
        end)
    else
        args.mode, args.profile = "assault", "seek_destroy"
    end
    local ok = (type(profileIds) == "table" and #profileIds > 0)
        and pressure.spawn(service, picked.player, args, hours, { bypass = forced }) or false
    local fresh = Registry.read(site.id) or site
    if not ok then
        Registry.update(fresh.id, fresh.revision, function(s)
            s.nextSquadHour = hours + Director.settings.refusedBackoffHours
        end)
        Director.metrics.refused = Director.metrics.refused + 1
        return false
    end
    local interval = preset.squad.intervalHours or { min = 4, max = 10 }

    local stretch = 1 / math.max(0.1, pressure ~= nil and pressure.at(hours) or 1)
    Registry.update(fresh.id, fresh.revision, function(s)
        s.dispatchSequence = sequence
        s.squads = kept
        s.squads[#s.squads + 1] = { id = squadId, task = task, departedHours = hours, pending = true }
        s.nextSquadHour = hours + ((interval.min or 4) + roll() * math.max(0, (interval.max or 10) - (interval.min or 4))) * stretch
    end)
    service.watchGroup(args.requestId, function(outcome)
        local current = Registry.read(site.id)
        if current == nil then return end
        Registry.update(current.id, current.revision, function(s)
            for index, squad in ipairs(s.squads or {}) do
                if squad.id == squadId then
                    if outcome.ok == true then squad.pending = false
                    else table.remove(s.squads, index) end
                    break
                end
            end
        end)
        forgetIndex()
    end)
    forgetIndex()
    Director.metrics.dispatched = (Director.metrics.dispatched or 0) + 1
    emit("outpost_dispatch", { site = site.id, preset = task, count = count2 })
    return true
end

function Director.wipedSquad(site, alive, seen)
    for _, squad in ipairs(type(site) == "table" and site.squads or {}) do
        if squad.pending ~= true and squad.avenged ~= true
                and seen[squad.id] == true and alive[squad.id] ~= site.id then
            return squad
        end
    end
    return nil
end

local function avenge(site, list, hours)
    if site.disabled == true or site.commsDisabled == true then return false end

    if site.hostileToPlayers ~= true and site.hostileToPlayers ~= "faction" then return false end
    local index = actorIndex()
    local alive, seen = index.squadsAlive, index.squadsSeen
    local standing = site.assassinSquadId
    if standing ~= nil and alive[standing] == site.id then return false end
    local wiped = Director.wipedSquad(site, alive, seen)
    if wiped == nil then return false end
    if Director.owedLapsed(site, wiped, hours) then return false end
    local residents = index.garrison[site.id]
    if residents == nil or residents.alive < 1 then return false end
    local tied = type(wiped.killers) == "table" and #wiped.killers > 0 and wiped.killers or nil
    local nearest, picked = math.huge, nil
    for _, p in ipairs(list) do
        local dx, dy = site.x - p.x, site.y - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < nearest and (tied == nil or Director.tiedTo(tied, p.player)) then nearest, picked = d, p end
    end
    if picked == nil or nearest > Director.settings.spawnRadius then return false end
    local service = Director.adapters.service or ProjectALife.DebugService
    if service == nil or type(service.spawnEncounter) ~= "function"
            or type(service.watchGroup) ~= "function" then return false end
    local point = Director.dispatchPoint(site)
    if not Director.dispatchGroundReady(point, list) then return false end
    local preset = Presets.get(site.presetId)
    local size = preset ~= nil and type(preset.squad) == "table" and preset.squad.size or nil
    local count = math.max(1, math.min(4, (size and size.min or 2)))
    local profileIds = type(service.hostileProfileIds) == "function"
        and service.hostileProfileIds(count, math.floor(hours * 1000) + 31, site.factionId) or nil
    if type(profileIds) ~= "table" or #profileIds == 0 then return false end
    local sequence = (tonumber(site.dispatchSequence) or 0) + 1
    local squadId = "outpostavenger:" .. site.id .. ":" .. tostring(sequence)
    local current = Registry.read(site.id) or site
    local hunted
    if type(picked.player.getUsername) == "function" then
        local name = picked.player:getUsername()
        if type(name) == "string" and name ~= "" then hunted = name end
    end
    local requestId = squadId .. ":" .. tostring(math.floor(hours * 100))
    local ok = ProjectALife.WorldPressure.spawn(service, picked.player, {
        requestId = requestId,
        count = count,
        factionId = site.factionId, atomicGroup = true,
        hostileOverride = true,
        x = point.x, y = point.y, z = point.z,
        distance = 0, separation = 1.5, radius = 6,
        animation = "normal",
        profileIds = profileIds,
        encounterId = squadId,
        encounterPersistent = false,
        outpostId = site.id,
        outpostSquadId = squadId,
        siteKey = Director.siteKey(site),
        mode = "manhunt", profile = "manhunt",

        targetUsername = hunted,
        origin = "director",
    }, hours)
    if not ok then return false end
    local fresh = Registry.read(site.id) or current
    Registry.update(fresh.id, fresh.revision, function(s)
        s.dispatchSequence = sequence
        for _, squad in ipairs(s.squads or {}) do
            if squad.id == wiped.id then squad.avenged = true end
        end
        s.assassinSquadId = squadId
        s.squads = s.squads or {}
        s.squads[#s.squads + 1] = { id = squadId, task = "avenge",
            departedHours = hours, pending = true, avenged = true }
    end)
    service.watchGroup(requestId, function(outcome) Director.avengerSettled(site.id, squadId, outcome) end)
    forgetIndex()
    Director.metrics.avenged = (Director.metrics.avenged or 0) + 1
    emit("outpost_avenge", { site = site.id, preset = "manhunt", count = count })
    return true
end

Director.settings.avengerOwedHours = 24
Director.settings.avengerKillersMax = 4

function Director.owedLapsed(site, wiped, hours)
    local now = tonumber(hours)
    if now == nil or type(wiped) ~= "table" then return false end
    local since = tonumber(wiped.wipedHours)
    local lapsed = since ~= nil and since <= now
        and now - since > (tonumber(Director.settings.avengerOwedHours) or 24)
    if since ~= nil and since <= now and not lapsed then return false end
    local current = Registry.read(site.id) or site
    Registry.update(current.id, current.revision, function(s)
        for _, squad in ipairs(s.squads or {}) do
            if squad.id == wiped.id then
                if lapsed then squad.avenged, squad.owedLapsed = true, true else squad.wipedHours = now end
            end
        end
    end)
    if lapsed then Director.metrics.avengeLapsed = (Director.metrics.avengeLapsed or 0) + 1 end
    return lapsed
end

function Director.tiedTo(killers, player)
    if player == nil then return false end
    local reputation = ProjectALife.Reputation
    local key = reputation ~= nil and type(reputation.playerKey) == "function" and reputation.playerKey(player) or nil
    local name
    if type(player) ~= "string" and player.getUsername ~= nil then name = player:getUsername() end
    for _, killer in ipairs(killers) do
        if killer == key or (name ~= nil and killer == name) then return true end
    end
    return false
end

function Director.noteKill(siteId, squadId, playerKey)
    if siteId == nil or squadId == nil or type(playerKey) ~= "string" or playerKey == "" then return false end
    local current = Registry.read(siteId)
    if current == nil then return false end
    local noted = false
    Registry.update(current.id, current.revision, function(s)
        for _, squad in ipairs(s.squads or {}) do
            if squad.id == squadId then
                squad.killers = type(squad.killers) == "table" and squad.killers or {}
                local known = false
                for _, killer in ipairs(squad.killers) do if killer == playerKey then known = true end end
                if not known and #squad.killers < (tonumber(Director.settings.avengerKillersMax) or 4) then
                    squad.killers[#squad.killers + 1] = playerKey
                    noted = true
                end
            end
        end
    end)
    return noted
end

function Director.avengerSettled(siteId, squadId, outcome)
    local current = Registry.read(siteId)
    if current == nil then return false end
    local landed = type(outcome) == "table" and outcome.ok == true
    Registry.update(current.id, current.revision, function(s)
        for index = #(s.squads or {}), 1, -1 do
            if s.squads[index].id == squadId then
                if landed then s.squads[index].pending = false else table.remove(s.squads, index) end
            end
        end
        if not landed and s.assassinSquadId == squadId then s.assassinSquadId = nil end
    end)
    forgetIndex()
    return true
end

Director.settings.avengerPendingHours = 2

function Director.ghostAvenger(squad, seen, hours)
    if type(squad) ~= "table" or squad.task ~= "avenge" or squad.pending ~= true then return false end
    if type(seen) == "table" and seen[squad.id] then return false end
    local departed, now = tonumber(squad.departedHours), tonumber(hours)
    if departed == nil or now == nil then return false end
    return now - departed > Director.settings.avengerPendingHours
end

function Director.adminSquadNow(siteId, player)
    local site = Registry.read(siteId)
    if site == nil then return false, "site_unknown" end
    if site.state ~= "garrisoned" then return false, "site_not_garrisoned" end
    local hours = worldHours()
    site = Registry.update(site.id, site.revision, function(s) s.nextSquadHour = 0 end) or site
    Director.state.index = nil

    local loaded = false
    pcall(function()
        local point = Director.dispatchPoint(site)
        loaded = getSquare ~= nil and getSquare(math.floor(point.x), math.floor(point.y),
            math.floor(point.z or 0)) ~= nil
    end)
    local list = { { player = player, x = site.x, y = site.y, admin = true } }
    if not loaded and player ~= nil then
        local px, py
        pcall(function() px, py = player:getX(), player:getY() end)
        if px ~= nil then list = { { player = player, x = px, y = py, atPlayer = true, admin = true } } end
    end
    local ok = dispatch(site, list, hours)
    if not ok then
        local _, live = liveSquads(site)
        return false, live >= Director.squadCap(site) and "squad_cap" or "dispatch_refused"
    end
    return true
end

function Director.adminDelaySquad(siteId, delayHours)
    local site = Registry.read(siteId)
    if site == nil then return false, "site_unknown" end
    local hours = worldHours()
    local base = math.max(hours, tonumber(site.nextSquadHour) or hours)
    local delay = math.max(0, math.min(24 * 60, tonumber(delayHours) or 0))
    local updated = Registry.update(site.id, site.revision, function(s) s.nextSquadHour = base + delay end)
    if updated == nil then return false, "site_update_failed" end
    return true, nil, updated.nextSquadHour - hours
end

function Director.adminSquadCap(siteId, delta)
    local site = Registry.read(siteId)
    if site == nil then return false, "site_unknown" end
    local updated = Registry.update(site.id, site.revision, function(s)
        s.squadCapBonus = math.max(-2, math.min(4, math.floor(tonumber(s.squadCapBonus) or 0)
            + math.floor(tonumber(delta) or 0)))
    end)
    if updated == nil then return false, "site_update_failed" end
    return true, nil, Director.squadCap(updated)
end

local function settleDispatches(site, hours)
    if type(site.squads) ~= "table" then return nil end
    local seen = actorIndex().squadsSeen
    local changed = false
    for index = #site.squads, 1, -1 do
        local squad = site.squads[index]
        if squad.pending == true and seen[squad.id] then squad.pending = false changed = true
        elseif Director.ghostAvenger(squad, seen, hours) then
            table.remove(site.squads, index)
            if site.assassinSquadId == squad.id then site.assassinSquadId = nil end
            changed = true
        end
    end
    if not changed then return nil end
    return Registry.update(site.id, site.revision, function(s)
        s.squads = site.squads
        s.assassinSquadId = site.assassinSquadId
    end)
end

local function askReinforcement(site, hours)

    if site.disabled == true then return false end
    if site.reinforcementAskedHours ~= nil then return false end

    if site.commsDisabled == true then return false end
    local alive, total = garrisonAlive(site)
    if total == 0 or alive > total * Director.settings.reinforceAtFraction then return false end
    local ledger, graph = ProjectALife.SquadLedger, ProjectALife.RoadGraph
    if ledger == nil or graph == nil then return false end
    local nodeId = graph.nearest(site.x, site.y)
    if nodeId == nil then return false end
    if ledger.requestReinforcement(site.id, nodeId, 3, site.factionId) then

        local fresh = Registry.read(site.id) or site
        Registry.update(fresh.id, fresh.revision, function(s) s.reinforcementAskedHours = hours end)
        emit("outpost_reinforcement", { site = site.id, reason = "garrison_halved" })
        return true
    end
    return false
end

garrisonAlive = function(site)
    local row = actorIndex().garrison[site.id]
    if row == nil then return 0, 0 end
    return row.alive, row.total
end

local function deleteGarrison(site)
    local actors = Director.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil then return 0 end

    local uids = {}
    scanActors(actors, function(record)
        local memory = type(record.memory) == "table" and record.memory or {}
        if memory.outpostId == site.id
                or memory.encounter == "outpost:" .. site.id then
            uids[#uids + 1] = record.uid
        end
    end)
    forgetIndex()
    local removed = 0
    for _, uid in ipairs(uids) do
        pcall(function()
            local service = ProjectALife.SpawnService
            if service ~= nil and type(service.dehydrate) == "function" then service.dehydrate(uid, "outpost_expired") end
        end)
        local fresh = actors.read(uid)
        if fresh ~= nil and actors.remove(fresh.uid, fresh.revision, "outpost_expired") then removed = removed + 1 end
    end
    return removed
end

local function removeAnimalNear(cell, prop)
    local removed = 0
    local reach = 6
    for px = math.floor(prop.x) - reach, math.floor(prop.x) + reach do
        for py = math.floor(prop.y) - reach, math.floor(prop.y) + reach do
            pcall(function()
                local square = cell:getGridSquare(px, py, prop.z or 0)
                if square == nil then return end
                local movers = square:getMovingObjects()
                for index = (movers and movers:size() or 0) - 1, 0, -1 do
                    local mover = movers:get(index)
                    if instanceof(mover, "IsoAnimal") then
                        mover:remove()
                        removed = removed + 1
                    end
                end
            end)
        end
    end
    return removed
end

function Director.rowPlacesThumpable(prop)
    if prop.op == "thumpable" or prop.op == "stairs" then return true end
    if prop.op ~= "tile" or type(prop.sprite) ~= "string" or type(getSprite) ~= "function" then return false end
    local sprite = getSprite(prop.sprite)
    local props = sprite ~= nil and sprite.getProperties ~= nil and sprite:getProperties() or nil
    if props == nil or Builder.flag(props, "doorN") or Builder.flag(props, "doorW") then return false end
    return Builder.flag(props, "WallN") or Builder.flag(props, "WallW")
end

function Director.drainHold(site, list)
    if not Builder.streamActive() then return false end
    local x1, y1, x2, y2 = Registry.propsBox(site.id)
    local box = nil
    if x1 ~= nil then box = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end
    return Director.streamHold(site, list, box)
end

function Director.teardownResult(site, removed, left, remaining)
    if tonumber(left) == 0 then
        Director.state.teardownNotified = Director.state.teardownNotified or {}
        local fresh = Registry.read(site.id)
        if Director.state.teardownNotified[site.id] ~= true
                and (fresh == nil or (tonumber(fresh.drainAbandoned) or 0) == 0) then
            Director.state.teardownNotified[site.id] = true
            local notification = Interop.snapshot(fresh or site, {}, 0)
            notification.props, notification.propCount = nil, 0
            Interop.run("outpost.afterTeardown", notification)
        end
    end
    return removed, left, remaining
end

local function removeProps(site, list)
    if type(Director.adapters.removeProps) == "function" then
        return Director.teardownResult(site, Director.removeByAdapter(site))
    end
    local hold = Director.drainHold(site, list)
    if type(site.props) == "table" then

        local removed, remaining, rowLimits = 0, {}, { holdStructure = hold }
        for _, prop in ipairs(site.props) do
            local ok, verdict, objects = pcall(Director.drainRow, prop, site.id, rowLimits)
            if ok and verdict == "gone" then
                removed = removed + (tonumber(objects) or 0)
            else
                remaining[#remaining + 1] = prop
            end
        end
        return Director.teardownResult(site, removed, #remaining, remaining)
    end
    local owed = tonumber(site.propCount) or 0
    local limits = Director.drainBudget()
    if limits.deadline == nil then limits.deadline = nowMs() + (tonumber(limits.window) or 0) end
    if not Registry.drainOpen(limits) then return 0, owed end

    if not Director.footprintLoaded(site) then return 0, owed end
    limits.holdStructure = hold
    local gone, removed, left, abandoned = Registry.drainProps(site.id, Director.drainRow, limits)
    limits.holdStructure = nil
    Director.metrics.drained = (tonumber(Director.metrics.drained) or 0) + gone
    for _, row in ipairs(abandoned or {}) do
        Director.metrics.drainAbandoned = (tonumber(Director.metrics.drainAbandoned) or 0) + 1
        emit("outpost_prop_abandoned", { site = site.id, reason = string.sub(tostring(row.error), 1, 120),
            x = row.x, y = row.y, z = row.z or 0, sprite = row.sprite or row.class })
    end
    return Director.teardownResult(site, removed, left)
end

Director.barricadeSteps = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Director.barricadeOurs(barricade, prop, siteId)
    local tag
    pcall(function()
        if type(barricade.hasModData) == "function" and barricade:hasModData() ~= true then return end
        tag = barricade:getModData().ProjectALifeOutpostSite
    end)
    if tag ~= nil then return tostring(tag) == tostring(siteId) end
    return prop.marked ~= true
end

function Director.removeBarricades(prop, siteId)
    local cell = getCell()
    if cell == nil then return 0, 0 end
    local className = prop.op == "barricade_window" and "IsoWindow" or "IsoDoor"
    local px, py, pz = math.floor(tonumber(prop.x) or 0), math.floor(tonumber(prop.y) or 0), math.floor(tonumber(prop.z) or 0)
    local targets, foreign = {}, 0
    for _, step in ipairs(Director.barricadeSteps) do
        local near = cell:getGridSquare(px + step[1], py + step[2], pz)
        local objects = near ~= nil and near:getObjects() or nil
        if objects ~= nil then
            for index = 0, objects:size() - 1 do
                local object = objects:get(index)
                local fits = false
                pcall(function()
                    fits = object ~= nil and instanceof(object, className)
                        and (prop.north == nil or object:getNorth() == prop.north)
                end)
                if fits then
                    for _, getter in ipairs({ "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }) do
                        local barricade
                        pcall(function()
                            if type(object[getter]) == "function" then barricade = object[getter](object) end
                        end)
                        if barricade ~= nil then
                            if Director.barricadeOurs(barricade, prop, siteId) then targets[#targets + 1] = barricade
                            else foreign = foreign + 1 end
                        end
                    end
                end
            end
        end
        if #targets > 0 or (prop.north ~= nil and step[1] == 0 and step[2] == 0) then break end
    end
    local removed = 0
    for _, barricade in ipairs(targets) do
        pcall(function()
            local square = barricade:getSquare()
            square:transmitRemoveItemFromSquare(barricade)
            square:RemoveTileObject(barricade)
            removed = removed + 1
        end)
    end
    return removed, foreign
end

function Director.dropObject(square, object)
    pcall(function() square:transmitRemoveItemFromSquare(object) end)
    local still = false
    pcall(function() still = square:getObjects():contains(object) == true end)
    if still then pcall(function() square:RemoveTileObject(object) end) end
    pcall(function() still = square:getObjects():contains(object) == true end)
    return still ~= true
end

function Director.openingMatches(object, spriteName)
    if type(getSprite) ~= "function" or type(Builder.flag) ~= "function" then return false end
    local sprite = getSprite(spriteName)
    local props = sprite ~= nil and type(sprite.getProperties) == "function" and sprite:getProperties() or nil
    if props == nil then return false end
    local door = Builder.flag(props, "doorN") or Builder.flag(props, "doorW")
    local window = Builder.flag(props, "windowN") or Builder.flag(props, "windowW")
    local className = (door and "IsoDoor") or (window and "IsoWindow") or nil
    if className == nil or instanceof(object, className) ~= true
            or type(object.getNorth) ~= "function" then return false end
    local north = Builder.flag(props, "doorN") or Builder.flag(props, "windowN")
    return (object:getNorth() == true) == (north == true)
end

function Director.stackedSprite(spriteName)
    if type(spriteName) ~= "string" or type(getSprite) ~= "function" then return nil end
    local sprite = getSprite(spriteName)
    if sprite == nil or type(sprite.getProperties) ~= "function" then return nil end
    local props = sprite:getProperties()
    if props == nil or type(props.get) ~= "function" then return nil end
    local prefix, index = string.match(spriteName, "^(.*_)(%d+)$")
    local offset = tonumber(props:get("StackReplaceTileOffset"))
    if prefix == nil or offset == nil or offset ~= math.floor(offset) then return nil end
    index = tonumber(index) + offset
    if index < 0 then return nil end
    return prefix .. tostring(index)
end

function Director.drainCampfire(square, prop)
    if prop.op ~= "campfire" then return 0 end
    local system = SCampfireSystem ~= nil and SCampfireSystem.instance or nil
    if system == nil or type(system.getLuaObjectAt) ~= "function" then return 0 end
    local ok, fire = pcall(system.getLuaObjectAt, system, prop.x, prop.y, prop.z or 0)
    if ok and fire == nil then return 0 end
    if ok and type(system.removeCampfire) == "function" then
        ok = pcall(system.removeCampfire, system, fire)
        if ok then return 1 end
    end
    Director.metrics.drainFailed = (tonumber(Director.metrics.drainFailed) or 0) + 1
    return -1
end

function Director.drainRow(prop, siteId, limits)
    local x, y = tonumber(prop.x), tonumber(prop.y)
    if x == nil or y == nil then return "gone", 0, 0 end
    if type(limits) == "table" and limits.holdStructure == true and Builder.structural(prop) then
        return "keep", 0, 0
    end
    local cell = getCell()
    if cell == nil or not Builder.groundLoaded(x, y) then return "keep", 0, 0 end
    local square = cell:getGridSquare(x, y, prop.z or 0)
    if square == nil then

        prop.missing = (tonumber(prop.missing) or 0) + 1
        if prop.missing >= 3 then return "gone", 0, 0 end
        return "keep", 0, 0
    end
    local removed, cost = 0, 0
    local campfireRemoved = Director.drainCampfire(square, prop)
    if campfireRemoved < 0 then return "keep", 0, 1 end
    if campfireRemoved > 0 then return "gone", campfireRemoved, campfireRemoved end
    if prop.op == "barricade_door" or prop.op == "barricade_window" then
        local foreign
        removed, foreign = Director.removeBarricades(prop, siteId)
        cost = removed
        if foreign > 0 then
            emit("outpost_prop_abandoned", { site = siteId, reason = "barricade_not_ours", x = x, y = y, z = prop.z or 0,
                sprite = prop.op })
        end
        return "gone", removed, cost
    end
    if prop.class == "BaseVehicle" then

        pcall(function()
            local vehicle = square:getVehicleContainer()
            local data = vehicle ~= nil and vehicle:getModData() or nil
            if type(data) == "table" and type(siteId) == "string"
                    and data.ProjectALifeOutpostVehicleSite == siteId
                    and vehicle:isPreviouslyEntered() == false
                    and vehicle:isPreviouslyMoved() == false then
                vehicle:permanentlyRemove()
                removed = removed + 1
            end
        end)
        cost = removed
    elseif prop.class == "IsoAnimal" then

        removed = removeAnimalNear(cell, prop)
        cost = math.max(3, removed)
    elseif prop.sprite ~= nil or prop.class ~= nil then
        local objects = square:getObjects()
        for index = objects:size() - 1, 0, -1 do

            local object = index < objects:size() and objects:get(index) or nil
            local match = false
            if object == nil then
                match = false
            elseif prop.sprite ~= nil then
                local name
                pcall(function()
                    name = object:getSprite() and object:getSprite():getName()
                end)
                match = name == prop.sprite
                if not match and prop.op == "campfire" then
                    match = name == "camping_01_5" or name == "camping_01_6"
                end
                if not match and prop.op == "container" then
                    local stacked = Director.stackedSprite(prop.sprite)
                    if stacked ~= nil then match = name == stacked end
                end
                if not match then
                    pcall(function() match = Director.openingMatches(object, prop.sprite) end)
                end
            else

                pcall(function()
                    match = instanceof(object, prop.class) == true
                end)
            end

            if match and instanceof(object, "IsoThumpable")
                    and not Director.rowPlacesThumpable(prop) then
                match = false
            end
            if match then
                if Director.dropObject(square, object) then
                    removed = removed + 1
                else
                    Director.metrics.drainStuck = (tonumber(Director.metrics.drainStuck) or 0) + 1
                    emit("outpost_prop_abandoned", { site = siteId, reason = "remove_failed", x = x, y = y,
                        z = prop.z or 0, sprite = prop.sprite or prop.class })
                end
                cost = cost + 1

                if prop.op == "floor" and type(prop.restore) == "string"
                        and math.floor(tonumber(prop.z) or 0) == 0 then
                    pcall(function() square:addFloor(prop.restore) end)
                    cost = cost + 1
                end
            end
        end
    end
    if removed == 0 and prop.op == "floor" and type(prop.restore) == "string"
            and math.floor(tonumber(prop.z) or 0) == 0 and type(square.getFloor) == "function"
            and type(square.addFloor) == "function" and square:getFloor() == nil then
        local ok, floor = pcall(square.addFloor, square, prop.restore)
        if ok and floor ~= nil then return "gone", 0, cost + 1 end
        Director.metrics.drainFailed = (tonumber(Director.metrics.drainFailed) or 0) + 1
        return "keep", 0, cost + 1
    end
    if removed == 0 and (prop.sprite ~= nil or prop.class ~= nil) then
        Director.metrics.drainNoMatch = (tonumber(Director.metrics.drainNoMatch) or 0) + 1
        emit("outpost_prop_abandoned", { site = siteId, reason = "no_match", x = x, y = y, z = prop.z or 0,
            sprite = prop.sprite or prop.class })
    end
    return "gone", removed, cost
end

local function expire(site, hours, reason)
    if reason == "garrison_dead" then Director.censusCleared(site, hours) end
    local deleted = deleteGarrison(site)

    local removed, left = removeProps(site)
    local fresh = Registry.read(site.id) or site
    ProjectALife.WorldPressure.release(fresh.pressureTicket, hours)
    Registry.expire(fresh.id, fresh.revision, hours, reason)
    Director.metrics.expired = Director.metrics.expired + 1
    emit("outpost_expired", { site = site.id, reason = reason, deleted = deleted, removed = removed, left = left })
    return true
end

function Director.structureLossProbe(row)
    local x, y = tonumber(row.x), tonumber(row.y)
    if x == nil or y == nil or type(row.sprite) ~= "string" or type(getCell) ~= "function" then return nil end
    if not Builder.groundLoaded(x, y) then return nil end
    local cell = getCell()
    local square = cell ~= nil and cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(row.z) or 0)) or nil
    if square == nil then return nil end
    local objects = square:getObjects()
    if objects == nil then return nil end
    local fire = false
    pcall(function() fire = square:haveFire() == true end)
    local found = false
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object ~= nil then
            local name
            pcall(function() name = object:getSprite() and object:getSprite():getName() end)
            if name == row.sprite then found = true break end
            local match = false
            pcall(function() match = Director.openingMatches(object, row.sprite) end)
            if match then found = true break end
        end
    end
    if fire then return "burn" end
    if found then return "ok" end
    return "lost"
end

function Director.structureEnough(t, percent)
    local s = Director.settings
    return t ~= nil and t.sampled >= math.min(t.total, s.structureMinSampled)
        and t.lost >= math.min(t.total, s.structureMinLost) and t.lost * 100 >= percent * t.sampled
end

function Director.structureReview(site, list, hours, now)
    local s = Director.settings
    local percent = tonumber(s.structureLossPercent) or 0
    if percent <= 0 or (site.state ~= "built" and site.state ~= "garrisoned") then return false end
    if (tonumber(site.propCount) or 0) < 3 then return false end
    Director.state.lossAt = Director.state.lossAt or {}
    local due = Director.state.lossAt[site.id]
    if due ~= nil and now < due then return false end
    if nearestPlayer(site.x, site.y, list) > s.structureRadius then return false end
    Director.state.lossAt[site.id] = now + s.structureReviewMs
    local stats = Registry.sampleLoss(site.id, s.structureSample, Director.structureLossProbe, Builder.lossRow)
    if stats == nil or stats.visited == 0 then return false end
    local fresh = Registry.read(site.id) or site
    local strikes = tonumber(fresh.lossStrikes) or 0
    if not Director.structureEnough(stats, percent) then
        if strikes ~= 0 then Registry.update(fresh.id, fresh.revision, function(r) r.lossStrikes = nil end) end
        return false
    end
    strikes = strikes + 1
    if strikes < s.structureStrikes then
        Registry.update(fresh.id, fresh.revision, function(r) r.lossStrikes = strikes end)
        return false
    end
    stats = Registry.sampleLoss(site.id, s.structureRecheck, Director.structureLossProbe, Builder.lossRow, true)
    fresh = Registry.read(site.id) or fresh
    if not Director.structureEnough(stats, percent) then
        Registry.update(fresh.id, fresh.revision, function(r) r.lossStrikes = nil end)
        return false
    end
    emit("outpost_structure_destroyed", { site = site.id, total = stats.total, sampled = stats.sampled,
        lost = stats.lost, burn = stats.burn, percent = percent })
    Director.metrics.structureExpired = (tonumber(Director.metrics.structureExpired) or 0) + 1
    return expire(fresh, hours, "structure_destroyed")
end

function Director.removeByAdapter(site)
    local ledger = site.props
    if ledger == nil and type(Registry.propsOf) == "function" then ledger = Registry.propsOf(site.id) end
    local view = site
    if site.props == nil then
        view = { props = ledger }
        for key, value in pairs(site) do
            if key ~= "props" then view[key] = value end
        end
    end
    local removed, remaining = Director.adapters.removeProps(view)
    if type(remaining) ~= "table" then remaining = {} end
    if site.props == nil then
        local fresh = Registry.read(site.id)
        if fresh ~= nil then
            Registry.update(fresh.id, fresh.revision, function(s)
                local before = type(s.props) == "table" and #s.props or 0
                s.drainRemoved = (tonumber(s.drainRemoved) or 0) + math.max(0, before - #remaining)
                s.props = remaining
            end)
        end
    end
    return tonumber(removed) or 0, #remaining, remaining
end

function Director.drainLimits(detached)
    local s = Director.settings
    local limits = { units = tonumber(s.drainBudget) or 200, rows = tonumber(s.drainScan) or 256,
        window = tonumber(s.drainMs) or 25, now = nowMs }
    if detached ~= true then Director.state.drain = limits end
    return limits
end

function Director.drainBudget()
    local limits = type(Director.state) == "table" and Director.state.drain or nil
    if type(limits) == "table" then return limits end
    return Director.drainLimits(true)
end

function Director.footprintLoaded(site)
    local x1, y1, x2, y2 = Registry.propsBox(site.id)
    if x1 == nil then return true end
    local step = math.max(1, math.floor(tonumber(Director.settings.drainProbeStep) or 32))
    if (math.floor((x2 - x1) / step) + 2) * (math.floor((y2 - y1) / step) + 2) > 64 then return true end
    local x = x1
    while true do
        local y = y1
        while true do
            if Builder.groundLoaded(x, y) then return true end
            if y >= y2 then break end
            y = math.min(y2, y + step)
        end
        if x >= x2 then break end
        x = math.min(x2, x + step)
    end
    return false
end

function Director.drainTombstone(site, list)
    if type(site) ~= "table" or site.state ~= "expired" or (tonumber(site.propCount) or 0) <= 0 then return false end
    if nearestPlayer(site.x, site.y, list or {}) > Director.settings.buildRadius then return false end
    local started = nowMs()
    local removed, left = removeProps(site, list)
    local now = nowMs()
    local runtime = ProjectALife.Runtime
    if now - started > 16 and runtime ~= nil and type(runtime.noteDetail) == "function" then
        runtime.noteDetail("outposts:drain", now - started)
    end
    local fresh = Registry.read(site.id)
    local total = 0
    if fresh ~= nil then total = tonumber(fresh.drainRemoved) or 0 end
    if left <= 0 then
        emit("outpost_props_drained", { site = site.id, count = total })
        return true
    end
    Director.state.drainSaid = Director.state.drainSaid or {}
    local said = Director.state.drainSaid[site.id]
    if said == nil or (now >= said.at and left ~= said.left) then
        Director.state.drainSaid[site.id] = { at = now + (tonumber(Director.settings.drainLogMs) or 10000), left = left }
        emit("outpost_props_draining", { site = site.id, removed = total, left = left })
    end
    return removed > 0
end

local function maybeExpire(site, hours)
    local age = hours - (tonumber(site.createdHours) or hours)
    if age < (tonumber(site.minLifeHours) or 0) then return false end
    if age >= (tonumber(site.maxLifeHours) or math.huge) then
        local fairness = ProjectALife.SpawnFairness
        if fairness ~= nil and type(fairness.siteMayExpire) == "function"
                and not fairness.siteMayExpire(site.x, site.y, 0) then
            return false
        end
        local preset = Presets.get(site.presetId)
        if preset ~= nil and preset.lastDay ~= nil then
            local nearest = nearestPlayer(site.x, site.y, players())
            if nearest <= Director.settings.holdoutClearRadius then return false end
        end
        return expire(site, hours, "max_life")
    end
    if site.state == "garrisoned" then
        local alive, total = garrisonAlive(site)
        if (total > 0 and alive == 0) or site.garrisonCount == 0 then
            local since = tonumber(site.garrisonDeadHours)
            if since == nil then
                Registry.update(site.id, site.revision, function(s) s.garrisonDeadHours = hours end)
            elseif hours - since >= Director.settings.garrisonDeadHours then
                return expire(site, hours, "garrison_dead")
            end
        end
    end
    return false
end

function Director.needsRelayout(site)
    if type(site) ~= "table" or site.state == "garrisoned" or site.state == "expired" then return false end
    local preset = Presets.get(site.presetId)
    local wanted = preset and tonumber(preset.planVersion) or nil
    if wanted == nil then return false end
    return (tonumber(site.planVersion) or 0) < wanted
end

Director.settings.rebuildRadius = 45

function Director.rebuild(site, list)
    local owed = tonumber(site.propCount) or 0
    if owed > 0 and nearestPlayer(site.x, site.y, list) > Director.settings.rebuildRadius then return false end
    if owed > 0 then

        local _removed, left = removeProps(site, list)
        if left > 0 then return false end

        site = Registry.read(site.id) or site
    end
    local preset = Presets.get(site.presetId)
    Director.state.sheets = Director.state.sheets or {}
    Director.state.sheets[site.id] = nil
    local home = Director.blueprintHome(preset)
    local updated = Registry.update(site.id, site.revision, function(s)
        s.state = "proposed"
        if home ~= nil then
            s.x, s.y = home.x, home.y
            s.bounds = Director.fixedBounds(preset, home.x, home.y)
        end
        s.drainCursor = nil
        s.drainRemoved = nil
        s.buildCursor = nil
        s.buildError = nil
        s.posts = nil
        s.lossStrikes = nil
        s.lossTotal = nil
        s.mainEntrance = nil
        s.containers = {}
        s.radio = nil
        s.planVersion = preset and tonumber(preset.planVersion) or s.planVersion

        if preset ~= nil and type(preset.factionId) == "string" then s.factionId = preset.factionId end
    end)
    if updated == nil then return false end
    forgetIndex()
    Director.metrics.rebuilt = (Director.metrics.rebuilt or 0) + 1
    emit("outpost_rebuilding", { site = site.id, preset = site.presetId })
    return true
end

function Director.crewProfileIds(crew, slots, offset)
    local ids, cursor = {}, {}
    for index, slot in ipairs(type(slots) == "table" and slots or {}) do
        local key = "default"
        if slot.conduct ~= nil and type(crew[slot.conduct]) == "table" then key = slot.conduct
        elseif slot.role ~= nil and type(crew[slot.role]) == "table" then key = slot.role end
        local pool = crew[key]
        if type(pool) ~= "table" or #pool == 0 then key, pool = "default", crew.default end
        if type(pool) ~= "table" or #pool == 0 then return ids end
        cursor[key] = (cursor[key] or math.floor(tonumber(offset) or 0)) + 1
        ids[index] = pool[(cursor[key] - 1) % #pool + 1]
    end
    return ids
end

function Director.intro(site, list)
    local preset = Presets.get(site.presetId)
    local intro = preset and preset.intro or nil
    if type(intro) ~= "table" or site.state == "expired" then return 0 end
    local heard = type(site.introHeard) == "table" and site.introHeard or {}
    local sent = 0
    local radius = tonumber(intro.radius) or 160
    for _, p in ipairs(list or {}) do
        local key = p.key
        if key == nil then
            pcall(function()
                local reputation = ProjectALife.Reputation
                key = reputation and reputation.playerKey(p.player) or nil
            end)
        end
        local dx, dy = (tonumber(p.x) or 0) - site.x, (tonumber(p.y) or 0) - site.y
        if key ~= nil and heard[key] ~= true and dx * dx + dy * dy <= radius * radius then
            local meta = Director.adapters.meta or ProjectALife.MetaDirector
            local offset = type(intro.offset) == "table" and intro.offset or {}
            local ok = false
            pcall(function()
                ok = meta.announceTo(p.player, intro.kind or "gunfire",
                    site.x + (tonumber(offset.x) or 0), site.y + (tonumber(offset.y) or 0), 0) == true
            end)
            if ok then
                local fresh = Registry.read(site.id)
                if fresh ~= nil then
                    Registry.update(fresh.id, fresh.revision, function(s)
                        s.introHeard = type(s.introHeard) == "table" and s.introHeard or {}
                        s.introHeard[key] = true
                    end)
                end
                heard[key] = true
                sent = sent + 1
                emit("outpost_intro", { site = site.id, player = key, kind = intro.kind or "gunfire" })
            end
        end
    end
    return sent
end

function Director.turnOnPlayer(site, player)
    local careful = ProjectALife.ModuleCareful
    local registry, watchdog = ProjectALife.ActorRegistry, ProjectALife.Watchdog
    if careful == nil or type(careful.turnGroup) ~= "function" or registry == nil
            or type(registry.each) ~= "function" or watchdog == nil
            or type(watchdog.bindings) ~= "table" then
        return false
    end
    local member, shell
    registry.each(function(record)
        local memory = type(record.memory) == "table" and record.memory or {}
        if record.lifecycle ~= "active" or tostring(memory.outpostId) ~= tostring(site.id) then return end
        local binding = watchdog.bindings[record.uid]
        if binding ~= nil and binding.shell ~= nil then
            member, shell = record, binding.shell
            return true
        end
    end)
    if member == nil then return false end
    local ok, turned = pcall(careful.turnGroup, member, shell, player)
    if not ok or turned == false then return false end

    pcall(function()
        local stamp = type(getTimestampMs) == "function" and getTimestampMs() or os.time() * 1000
        local key = careful.ladderKey(member, player)
        local ladder = careful.ladders[key]
        if ladder == nil then
            ladder = {}
            careful.ladders[key] = ladder
        end
        ladder.step, ladder.atMs, ladder.lastInsideAtMs = 3, stamp, stamp
    end)
    return true
end

function Director.tripLine(site, list)
    local preset = Presets.get(site.presetId)
    local line = preset and preset.tripLine or nil
    if type(line) ~= "table" or (site.state ~= "built" and site.state ~= "garrisoned") then return 0 end
    local tripped = type(site.tripped) == "table" and site.tripped or {}
    local count = 0
    for _, p in ipairs(list or {}) do
        local key = p.key
        if key == nil then
            pcall(function()
                local reputation = ProjectALife.Reputation
                key = reputation and reputation.playerKey(p.player) or nil
            end)
        end
        local dx, dy = (tonumber(p.x) or 0) - site.x, (tonumber(p.y) or 0) - site.y

        local careful = ProjectALife.ModuleCareful
        local unseen = p.player ~= nil and careful ~= nil and type(careful.visible) == "function"
            and careful.visible(p.player) ~= true
        if key ~= nil and not unseen and tripped[key] ~= true and math.floor(tonumber(p.z) or 0) == 0
                and dx >= line.x1 and dx <= line.x2 and dy >= line.y1 and dy <= line.y2
                and Director.turnOnPlayer(site, p.player) then
            local fresh = Registry.read(site.id)
            if fresh ~= nil then
                Registry.update(fresh.id, fresh.revision, function(s)
                    s.tripped = type(s.tripped) == "table" and s.tripped or {}
                    s.tripped[key] = true
                end)
            end
            tripped[key] = true
            count = count + 1
            Director.metrics.tripped = (Director.metrics.tripped or 0) + 1
            emit("outpost_tripline", { site = site.id, player = key,
                x = math.floor(tonumber(p.x) or 0), y = math.floor(tonumber(p.y) or 0) })
        end
    end
    return count
end

Director.settings.zombieCullSight = 30
Director.settings.zombieSweepMs = 3000

function Director.insideBounds(site, x, y)
    local bounds = type(site) == "table" and site.bounds or nil
    if type(bounds) ~= "table" then return false end
    local x1, y1 = tonumber(bounds.x1), tonumber(bounds.y1)
    local x2, y2 = tonumber(bounds.x2), tonumber(bounds.y2)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return false end
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return false end
    return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

function Director.clearZombies(site, list, now)
    local preset = Presets.get(site.presetId)
    local radius = preset and tonumber(preset.zombieFreeRadius) or nil
    if radius == nil or site.state == "expired" then return 0 end
    Director.state.zombieSweepAt = Director.state.zombieSweepAt or {}
    if (tonumber(now) or 0) < (Director.state.zombieSweepAt[site.id] or 0) then return 0 end
    Director.state.zombieSweepAt[site.id] = (tonumber(now) or 0) + Director.settings.zombieSweepMs
    if nearestPlayer(site.x, site.y, list) > radius + 150 then return 0 end

    local bound = {}
    pcall(function()
        local watchdog = Director.adapters.watchdog or ProjectALife.Watchdog
        if watchdog == nil or type(watchdog.order) ~= "table" then return end
        for index = 1, #watchdog.order do
            local binding = watchdog.bindings[watchdog.order[index]]
            if binding ~= nil and binding.shell ~= nil then bound[binding.shell] = true end
        end
    end)
    local doomed = {}
    pcall(function()
        local zombies = (Director.adapters.zombieList and Director.adapters.zombieList())
            or getCell():getZombieList()
        for index = 0, zombies:size() - 1 do
            local body = zombies:get(index)

            local zx, zy
            if body ~= nil and body.getX ~= nil and body.getY ~= nil then zx, zy = body:getX(), body:getY() end
            local inReach = zx == nil
            if not inReach then
                local rx, ry = zx - site.x, zy - site.y
                inReach = rx * rx + ry * ry <= radius * radius
            end
            if inReach then
                local ours = bound[body] == true

                if not ours and body ~= nil and type(body.getModData) == "function" then
                    local hasData = true
                    if type(body.hasModData) == "function" then
                        local hasOk, has = pcall(body.hasModData, body)
                        hasData = not hasOk or has == true
                    end
                    if hasData then
                        local dataOk, data = pcall(body.getModData, body)
                        ours = dataOk and type(data) == "table" and (data.ProjectALifeOwned == true
                            or data.ProjectALifeActor == true or data.ProjectALifeUID ~= nil)
                    end
                end
                if not ours and not ProjectALife.ShellSimulation.grappledCorpse(body) then
                    if zx == nil then zx, zy = body:getX(), body:getY() end
                    local dx, dy = zx - site.x, zy - site.y
                    if dx * dx + dy * dy <= radius * radius then

                        if Director.insideBounds(site, zx, zy)
                                or nearestPlayer(zx, zy, list) > Director.settings.zombieCullSight then
                            doomed[#doomed + 1] = body
                        end
                    end
                end
            end
        end
    end)
    for _, body in ipairs(doomed) do
        pcall(function()
            body:removeFromWorld()
            body:removeFromSquare()
        end)
    end
    if #doomed > 0 then
        Director.metrics.zombiesCleared = (Director.metrics.zombiesCleared or 0) + #doomed
    end
    return #doomed
end

function Director.clampLife(site)
    local preset = Presets.get(site.presetId)
    if preset == nil or preset.fixedSite ~= true then return false end
    local cap = type(preset.lifetime) == "table" and tonumber(preset.lifetime.minHours) or nil
    if cap == nil or site.state == "expired" then return false end
    if (tonumber(site.maxLifeHours) or 0) <= cap then return false end
    local fresh = Registry.read(site.id)
    if fresh == nil then return false end
    Registry.update(fresh.id, fresh.revision, function(s)
        s.maxLifeHours = cap
        s.minLifeHours = math.min(tonumber(s.minLifeHours) or cap, cap)
    end)
    return true
end

function Director.repairOpenings(site, list, now)
    if (tonumber(site.openingsFixed) or 0) >= Builder.openingsVersion then return false end
    Director.state.repairAt = Director.state.repairAt or {}
    if (tonumber(now) or 0) < (Director.state.repairAt[site.id] or 0) then return false end
    Director.state.repairAt[site.id] = (tonumber(now) or 0) + 15000
    if nearestPlayer(site.x, site.y, list) > 60 then return false end
    local repaired, pending = Builder.repairOpenings(site, Director.streamHold(site, list))
    if pending == 0 then
        local fresh = Registry.read(site.id)
        if fresh ~= nil then
            Registry.update(fresh.id, fresh.revision, function(s) s.openingsFixed = Builder.openingsVersion end)
        end
    end
    if repaired > 0 then emit("outpost_openings_repaired", { site = site.id, count = repaired }) end
    return repaired > 0
end

function Director.upkeepLights(site, list, now)
    local lights = ProjectALife.OutpostLights
    if lights == nil or type(lights.tick) ~= "function" or not lights.enabled() then return false end
    if nearestPlayer(site.x, site.y, list) > Director.settings.buildRadius then return false end
    local ok, worked = pcall(lights.tick, site, now, worldHours())
    return ok and worked == true
end

function Director.repairGarage(site, list, now)
    if type(site) ~= "table" or type(site.vehicles) ~= "table" or #site.vehicles == 0 then return false end
    Director.state.garageAt = Director.state.garageAt or {}
    if (tonumber(now) or 0) < (Director.state.garageAt[site.id] or 0) then return false end
    Director.state.garageAt[site.id] = (tonumber(now) or 0) + 20000
    if nearestPlayer(site.x, site.y, list) > Director.settings.buildRadius then return false end
    local restored, rows = 0, {}
    for _, bay in ipairs(site.vehicles) do
        if bay.retired ~= true and Builder.groundLoaded(bay.x, bay.y) then

            local occupied = false
            pcall(function()
                local vehicles = getCell():getVehicles()
                if vehicles == nil or vehicles.toArray == nil then return end
                for _, vehicle in pairs(vehicles:toArray()) do
                    local ok, vx, vy = pcall(function() return vehicle:getX(), vehicle:getY() end)
                    if ok and vx ~= nil and (vx - bay.x) ^ 2 + (vy - bay.y) ^ 2 <= 9 then
                        occupied = true
                        return
                    end
                end
            end)

            if occupied then
                bay.retired = true
            elseif Builder.placeVehicle(bay.x, bay.y, bay.z or 0, bay.script, bay.facing, bay.fuel, site.id) ~= nil then
                bay.retired = true
                restored = restored + 1

                rows[#rows + 1] = { op = "vehicle", x = bay.x, y = bay.y, z = bay.z or 0, class = "BaseVehicle" }
            end
        end
    end
    if restored == 0 then return false end
    local fresh = Registry.read(site.id)
    if fresh ~= nil then
        Registry.update(fresh.id, fresh.revision, function(s)
            s.vehicles = site.vehicles
            if type(s.props) ~= "table" then s.props = {} end
            for _, row in ipairs(rows) do s.props[#s.props + 1] = row end
        end)
    end
    emit("outpost_garage_restored", { site = site.id, count = restored })
    return true
end

function Director.enforceDisposition(site)
    local preset = Presets.get(site.presetId)
    if not preset or preset.hostileToPlayers ~= true or site.hostilityPolicy == 126
            or site.state == "expired" then return site end
    local actors = Director.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.update) ~= "function" then return site end
    for _, record in ipairs(actorIndex().members[site.id] or {}) do
        if record.memory.hostileOverride ~= true and not actors.update(record.uid, record.revision, function(fresh)
            fresh.memory.hostileOverride = true
        end) then return site end
    end
    return Registry.update(site.id, site.revision, function(fresh)
        fresh.hostileToPlayers = true
        fresh.hostilityPolicy = 126
    end) or site
end

function Director.stamp()
    return type(getTimestampMs) == "function" and getTimestampMs() or 0
end

function Director.noteSlow(key, started, suffix)
    local spent = Director.stamp() - started
    if spent <= 16 then return end
    local runtime = ProjectALife.Runtime
    if runtime ~= nil and type(runtime.noteDetail) == "function" then
        runtime.noteDetail(suffix ~= nil and (key .. tostring(suffix)) or key, spent)
    end
end

function Director.tickAdminSites(list, hours)
    local work = 0
    if Builder.streamActive() then Builder.watchPlayers(list, nowMs()) end
    Director.drainLimits()
    for _, site in ipairs(Registry.list()) do
        if Director.drainTombstone(site, list) then work = work + 1 end
        if site.adminBuilt == true then
            if site.state == "proposed" then
                if buildSite(site, list) then work = work + 1 end
            elseif site.state == "built" then
                if garrison(site, list, hours) then work = work + 1 end
            end
            if (site.state == "built" or site.state == "garrisoned")
                    and Director.upkeepLights(site, list, nowMs()) then work = work + 1 end
        end
    end
    Director.state.drain = nil
    return work
end

function Director.tick()
    if not Director.enabled then
        Director.state.scan = nil
        return Director.tickAdminSites(players(), worldHours())
    end
    local now = nowMs()
    local hours = worldHours()
    local list = players()
    local work = 0
    if Builder.streamActive() then Builder.watchPlayers(list, now) end

    Director.drainLimits()

    Director.state.index = nil

    Registry.sweep(hours)

    local interval = Director.settings.intervalMinutes
    local lastHours = tonumber(Director.state.lastRollHours)
    local dueByWorld = Director.settings.rollOnWorldClock ~= false
        and (lastHours == nil or hours - lastHours >= interval / 60)
    local dueByReal = now - Director.state.lastRollMs >= interval * 60000
    local scanning = Director.state.scan
    if scanning ~= nil then
        local proposeStarted = Director.stamp()
        if now - scanning.startedMs > (tonumber(Director.settings.scanExpireMs) or 600000) then
            Director.state.scan = nil
            Director.metrics.scanAbandoned = (Director.metrics.scanAbandoned or 0) + 1
        else
            local done, site, why = Director.scanAdvance(scanning, hours)
            if done then work = work + Director.proposalResult(site, why) end
        end
        Director.noteSlow("outposts:propose", proposeStarted)
    elseif dueByWorld or dueByReal then
        Director.state.lastRollMs = now
        Director.state.lastRollHours = hours
        Director.metrics.rolls = Director.metrics.rolls + 1
        if roll() * 100 < Director.settings.chancePercent then

            local proposeStarted = Director.stamp()
            local job, why = Director.proposeOpen(hours)
            if job == nil then
                work = work + Director.proposalResult(nil, why)
            else
                local done, site, refusal = Director.scanAdvance(job, hours)
                if done then work = work + Director.proposalResult(site, refusal) end
            end
            Director.noteSlow("outposts:propose", proposeStarted)
        end
    end

    local outbreak = ProjectALife.RealisticOutbreak
    if outbreak ~= nil and type(outbreak.tick) == "function" then
        local outbreakStarted = Director.stamp()
        local ok, founded = pcall(outbreak.tick, hours)
        Director.noteSlow("outposts:outbreak", outbreakStarted)
        if ok and founded then work = work + 1 end
    end
    for _, site in ipairs(Registry.list()) do
        local siteStarted = Director.stamp()
        site = Director.enforceDisposition(site)
        local relaying = site.state == "build_failed" or Director.needsRelayout(site)
        if relaying then
            if Director.rebuild(site, list) then work = work + 1 end
        elseif site.state == "proposed" then
            local buildStarted = nowMs()
            if buildSite(site, list) then work = work + 1 end
            local runtime, spent = ProjectALife.Runtime, nowMs() - buildStarted
            if spent > 16 and runtime ~= nil and type(runtime.noteDetail) == "function" then
                runtime.noteDetail("outposts:build", spent)
            end
        elseif site.state == "built" then
            if garrison(site, list, hours) then
                work = work + 1
            end
        elseif site.state == "garrisoned" then

            local current = settleDispatches(site, hours) or site
            local alive, total = garrisonAlive(current)
            if total > 0 and current.garrisonCount ~= alive then
                current = Registry.update(current.id, current.revision, function(s) s.garrisonCount = alive end) or current
            end

            local theft = ProjectALife.OutpostTheft
            if theft ~= nil and type(theft.tick) == "function" then
                local ok, flipped = pcall(theft.tick, current, list, now)
                if ok and flipped then
                    work = work + 1
                    current = Registry.read(site.id) or current
                end
            end

            if avenge(current, list, hours) then
                work = work + 1
                current = Registry.read(site.id) or current
            end
            if dispatch(current, list, hours) then
                work = work + 1
                current = Registry.read(site.id) or current
            end
            if askReinforcement(current, hours) then work = work + 1 end
        elseif site.state == "expired" and (site.propCount or 0) > 0 then

            if Director.drainTombstone(site, list) then work = work + 1 end
        end

        Director.noteSlow("outposts:state:", siteStarted, site.state)
        local upkeepStarted = Director.stamp()
        if (site.state == "built" and not relaying) or site.state == "garrisoned" then
            if Director.repairOpenings(site, list, now) then work = work + 1 end
            if Director.repairGarage(site, list, now) then work = work + 1 end
            if Director.upkeepLights(site, list, now) then work = work + 1 end
        end
        if Director.intro(site, list) > 0 then work = work + 1 end
        if Director.tripLine(site, list) > 0 then work = work + 1 end
        if Director.clearZombies(site, list, now) > 0 then work = work + 1 end
        Director.clampLife(site)
        local fresh = Registry.read(site.id)
        local broken = false
        if fresh ~= nil and fresh.state ~= "expired" then
            local asked, result = pcall(Director.structureReview, fresh, list, hours, now)
            broken = asked and result == true
            if broken then work = work + 1 end
        end
        if not broken and fresh ~= nil and fresh.state ~= "expired" and maybeExpire(fresh, hours) then
            work = work + 1
        end
        Director.noteSlow("outposts:upkeep", upkeepStarted)
    end

    local talkStarted = Director.stamp()
    local radio = ProjectALife.OutpostRadio
    if radio ~= nil and type(radio.tick) == "function" then
        local ok, extra = pcall(radio.tick, hours, now, list)
        if ok then work = work + (tonumber(extra) or 0) end
    end

    local chatter = ProjectALife.OutpostGossip
    if chatter ~= nil and type(chatter.tick) == "function" then
        local ok, spoke = pcall(chatter.tick, Registry.list(), list)
        if ok and spoke then work = work + 1 end
    end
    Director.noteSlow("outposts:talk", talkStarted)
    Director.state.drain = nil
    return work
end

return Director
