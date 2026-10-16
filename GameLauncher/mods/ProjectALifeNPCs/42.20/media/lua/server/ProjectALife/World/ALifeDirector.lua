require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Records/ALifeRosterDraw"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Decisions/ALifeRoutines"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/World/ALifeSpawnRegions"
require "ProjectALife/Records/ALifePartyPolicy"
require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/World/ALifeKeepOut"
require "ProjectALife/World/ALifeWorldPressure"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Registry = ProjectALife.ActorRegistry
local Programs = ProjectALife.Programs
local PlayerLocator = ProjectALife.PlayerLocator
local SpawnPolicy = ProjectALife.SpawnPolicy
local SpawnRegions = ProjectALife.SpawnRegions
local Director = {
    adapters = {},
    rosters = {},
    lastWindow = nil,
    enabled = true,
    spawnMultiplier = 1,
    groupMultiplier = 1,
    maximumLivingActors = 32,
    encounterIntervalHours = 6,
    encounterChance = 0.15,
    lastDecision = "not_checked",
}
ProjectALife.Director = Director

local function worldHour()
    if type(Director.adapters.worldHour) == "function" then
        return Director.adapters.worldHour()
    end
    if type(getGameTime) == "function" and getGameTime() ~= nil then
        return getGameTime():getWorldAgeHours()
    end
    return 0
end

local function clockHour(fallback)
    if type(Director.adapters.timeOfDay) == "function" then
        return tonumber(Director.adapters.timeOfDay()) or 0
    end

    if type(Director.adapters.worldHour) ~= "function"
            and type(getGameTime) == "function" then
        local ok, value = pcall(function() return getGameTime():getTimeOfDay() end)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    end
    return (tonumber(fallback) or 0) % 24
end

local function roll()
    if type(Director.adapters.roll) == "function" then return Director.adapters.roll() end
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000000) / 1000000 end
    return 1
end

local function choose(maximum)
    if maximum <= 1 then return 1 end
    if type(Director.adapters.chooseIndex) == "function" then
        return math.max(1, math.min(maximum, Director.adapters.chooseIndex(maximum)))
    end
    if type(ZombRandBetween) == "function" then return ZombRandBetween(1, maximum + 1) end
    if type(ZombRand) == "function" then return ZombRand(maximum) + 1 end
    return 1
end

local function players()
    return PlayerLocator.list(Director.adapters.players)
end

local function playerPosition(player)
    return PlayerLocator.position(player, Director.adapters.playerPosition)
end

local function spawnRange(spawn, anchor)
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() and type(anchor) == "table" then
        local low, high = fairness.band(anchor.x, anchor.y)
        return low, high + 8
    end
    return ProjectALife.KeepOut.partyRing()
end
Director.spawnRange = spawnRange

local function spawnPosition(player, memberIndex, spawn)
    if type(Director.adapters.spawnPosition) == "function" then
        return Director.adapters.spawnPosition(player, memberIndex, spawn)
    end
    local origin = playerPosition(player)
    if origin == nil then return nil end
    local minimum, maximum = spawnRange(spawn, origin)

    local roads = ProjectALife.EncounterDirector
    if roads ~= nil and type(roads.roadPointNear) == "function" then
        local backX, backY
        pcall(function()
            local forward = player:getForwardDirection()
            backX, backY = -forward:getX(), -forward:getY()
        end)
        local road = roads.roadPointNear(origin.x, origin.y, minimum, maximum, backX, backY)
        if road ~= nil then return { x = road.x, y = road.y, z = 0 } end
    end
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() and fairness.kindAt(origin.x, origin.y) ~= "town" then
        fairness.noteCut("rural_no_road")
        return nil
    end
    if fairness ~= nil and fairness.enabled() then
        local point = fairness.ringPoint(origin.x, origin.y, minimum, maximum)
        if point == nil then return nil end
        return { x = point.x, y = point.y, z = origin.z }
    end
    local distance = minimum + roll() * (maximum - minimum)
    local angle = roll() * math.pi * 2
    return {
        x = origin.x + math.cos(angle) * distance,
        y = origin.y + math.sin(angle) * distance,
        z = origin.z,
    }
end

local function formationPosition(anchor, index, size)
    local columns = math.ceil(math.sqrt(size))
    local rows = math.ceil(size / columns)
    local diagonal = math.sqrt((columns - 1)^2 + (rows - 1)^2)
    local gap = diagonal > 0 and math.min(3, 16 / diagonal) or 0
    return {
        x = anchor.x + (((index - 1) % columns) - (columns - 1) / 2) * gap,
        y = anchor.y + (math.floor((index - 1) / columns) - (rows - 1) / 2) * gap,
        z = anchor.z,
    }
end

local function rebuildRosters()
    Director.rosters = {}
    local catalog = Catalog.current
    if catalog == nil then return end
    for _, profile in ipairs(catalog.npcOrder) do
        local factionId = profile.general.faction
        Director.rosters[factionId] = Director.rosters[factionId] or {}
        if (tonumber(profile.general.spawnWeight) or 1) > 0 then
            Director.rosters[factionId][#Director.rosters[factionId] + 1] = profile
        end
    end
end

local function livingCount()
    if ProjectALife.Population and ProjectALife.Population.capacityUsed then
        return ProjectALife.Population.capacityUsed(true)
    end
    local count = 0

    Registry.each(function(actor)
        if actor.lifecycle ~= "dead" then count = count + 1 end
    end)
    return count
end

local function activeAtHour(spawn, hour)
    return ProjectALife.FactionSpawnRules.activeAtHour(spawn, hour)
end
Director.activeAtHour = activeAtHour

local function locationAllowed(faction, player)
    local position = playerPosition(player)
    return position ~= nil and SpawnRegions.allows(position, faction.spawn)
end

local function eligible(faction, day, hour, online)
    local spawn = faction.spawn
    if not ProjectALife.FactionSpawnRules.available(faction, day, hour)
            or #ProjectALife.FactionSpawnRules.roamingEncounters(spawn) == 0
            or Director.rosters[faction.id] == nil then return false end
    for _, player in ipairs(online or {}) do
        if locationAllowed(faction, player) then return true end
    end
    return false
end

local PRIMARY_CONDUCTS = {
    leader = true, sniper = true, medic = true,
    ambusher = true, stealth = true,
}
local PRIMARY_CONDUCT_ORDER = {
    "leader", "sniper", "medic", "ambusher", "stealth",
}

local LEGACY_CONDUCT_OVERRIDES = { "radioman" }

local function conductFor(profile, faction, memberIndex, groupSize)
    local general = type(profile) == "table" and profile.general or {}
    local authored = string.lower(tostring(general.primaryBehavior or ""))
    if PRIMARY_CONDUCTS[authored] then return authored end

    local inherited = type(faction) == "table" and faction.memberModules or {}
    if inherited.leader == "on" and tonumber(memberIndex) == 1
            and (tonumber(groupSize) or 0) >= 3 then
        return "leader"
    end
    return nil
end
Director.conductFor = conductFor

local function mergedModuleOverrides(faction, profile, conduct)
    local result = { flee = "off" }
    for id, value in pairs(faction.memberModules or {}) do
        if value ~= "inherit" and value ~= "" then result[id] = value end
    end
    for id, value in pairs(profile.moduleOverrides or {}) do
        if value ~= "inherit" and value ~= "" then result[id] = value end
    end

    if conduct ~= nil then
        result[conduct] = "on"
    end
    return result
end
Director.moduleOverridesFor = mergedModuleOverrides

function Director.restoreMemberPolicy(record, faction, profile, natural)
    local memory = record.memory

    natural = natural or (type(memory) == "table" and type(memory.groupId) == "string"
        and string.sub(memory.groupId, 1, 6) == "group:" and memory.debugSpawn ~= true)
    if type(memory) ~= "table" or (tonumber(memory.memberPolicyVersion) or 0) >= 2
            or not (natural or memory.squadId ~= nil) then return end
    local overrides = memory.moduleOverrides
    local conduct = memory.conduct
    local synthetic = conduct ~= nil and type(overrides) == "table"
    for _, id in ipairs(PRIMARY_CONDUCT_ORDER) do
        if not synthetic or overrides[id] ~= (id == conduct and "on" or "off") then
            synthetic = false
            break
        end
    end
    if synthetic then
        local authored = mergedModuleOverrides(faction, profile, conduct)
        for _, id in ipairs(PRIMARY_CONDUCT_ORDER) do overrides[id] = authored[id] end
        for _, id in ipairs(LEGACY_CONDUCT_OVERRIDES) do overrides[id] = authored[id] end
    end
    if natural and type(memory.support) == "table"
            and memory.supportRole ~= "backup" and memory.role ~= "backup" then
        memory.support.inherited = true
    end
    memory.memberPolicyVersion = 2
end

local function supportAnswerers(value)
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

local function supportFor(faction)
    local source = type(faction) == "table" and faction.support or nil
    if type(source) ~= "table" then return nil end
    local policy = string.lower(tostring(source.policy or "any"))
    if policy ~= "any" and policy ~= "radio" and policy ~= "disabled" then policy = "any" end
    local kind = string.lower(tostring(source.type or "ground"))
    if kind ~= "ground" and kind ~= "heli" and kind ~= "both" then kind = "ground" end
    local heli = string.lower(tostring(source.heli or "none"))
    if heli ~= "none" and heli ~= "spotlight" and heli ~= "support"
            and heli ~= "support_spotlight" then heli = "none" end
    return {
        inherited = true,
        policy = policy, type = kind, heli = heli,
        size = math.max(1, math.min(12, math.floor(tonumber(source.size) or 4))),
        maxCalls = math.max(0, math.min(3, math.floor(tonumber(source.maxCalls) or 1))),
        answerers = supportAnswerers(source.answerers),
        vehicle = source.vehicle,
    }
end
Director.supportFor = supportFor

local PROGRAM_PROFILES = {
    roam = "seek_destroy", hunt = "seek_destroy", seek_destroy = "seek_destroy",
    patrol = "patrol", guard = "patrol", camp = "patrol",
    scavenge = "scavenger", scavenger = "scavenger", looter = "scavenger",
    manhunt = "manhunt",
}

local function behaviorFor(profile, encounter, program)
    local general = profile.general or {}
    local authored = string.lower(tostring(general.behaviorProfile or ""))
    if authored ~= "" and authored ~= "default" then return authored end

    local activity = PROGRAM_PROFILES[string.lower(tostring(program or ""))]
    if activity ~= nil then return activity end
    if encounter == "patrol" or encounter == "town_patrol" then return "patrol" end
    if encounter == "scavenger_crew" or encounter == "scavenge" then return "scavenger" end
    return "seek_destroy"
end

local function profileFor(roster)
    local total = 0
    for _, profile in ipairs(roster) do
        total = total + math.max(0,
            tonumber(profile.general and profile.general.spawnWeight) or 1)
    end
    if total <= 0 then return roster[choose(#roster)] end
    local needle = roll() * total
    for _, profile in ipairs(roster) do
        needle = needle - math.max(0,
            tonumber(profile.general and profile.general.spawnWeight) or 1)
        if needle < 0 then return profile end
    end
    return roster[#roster]
end

function Director.admit(player, at, faction, size)
    local pressure = ProjectALife.WorldPressure
    if type(pressure) ~= "table" then return size end
    if type(pressure.shelterRefusal) == "function" then
        local refusal = pressure.shelterRefusal(player, at.x, at.y, at.z)
        if refusal ~= nil then return 0, refusal end
    end
    if type(pressure.censusAdmit) ~= "function" then return size end
    return pressure.censusAdmit(size, faction.id, worldHour())
end

function Director.inSight(point)
    local pressure = ProjectALife.WorldPressure
    return type(pressure) == "table" and type(pressure.inSight) == "function"
        and pressure.inSight(point.x, point.y, point.z) == true
end

local function spawnGroup(faction, online, window, available)
    local roster = Director.rosters[faction.id]
    if #roster == 0 or #online == 0 then return 0 end
    local spawn = faction.spawn

    local jobs = ProjectALife.FactionSpawnRules.roamingEncounters(spawn)
    local activities = {
        roamer = "roam", patrol = "patrol", town_patrol = "patrol",
        scavenger_crew = "scavenge",
    }
    if #jobs == 0 then return 0 end
    local groupSize, partyKind = ProjectALife.PartyPolicy.choose(
        faction, roll, Director.groupMultiplier, available)
    if groupSize <= 0 then return 0 end
    local allowedPlayers = {}
    for _, candidate in ipairs(online) do
        if locationAllowed(faction, candidate) then allowedPlayers[#allowedPlayers + 1] = candidate end
    end
    if #allowedPlayers == 0 then return 0 end
    local player = allowedPlayers[choose(#allowedPlayers)]
    local anchor = playerPosition(player)
    if anchor == nil then return 0 end
    local fairness = ProjectALife.SpawnFairness
    if fairness ~= nil and fairness.enabled() and not fairness.densityPass(anchor.x, anchor.y, roll()) then
        Director.lastDecision = "rural_density"
        return 0
    end

    local groupAnchor = spawnPosition(player, 1, spawn)
    if groupAnchor == nil then return 0 end
    local seats, refusal = Director.admit(player, groupAnchor, faction, groupSize)
    if seats < 1 then
        Director.lastDecision = "pressure_" .. tostring(refusal or "census")
        return 0
    end
    groupSize = math.min(groupSize, seats)
    local rangeMin, rangeMax = spawnRange(spawn, anchor)
    local groupId = "group:" .. tostring(window) .. ":" .. faction.id

    local nightvision = (ProjectALife.Settings and ProjectALife.Settings.current
        and ProjectALife.Settings.current.nightvision == true) or false
    local squadLight = false
    if not nightvision then
        local hash, text = 0, tostring(groupId)
        for index = 1, #text do hash = (hash * 31 + string.byte(text, index)) % 2147483647 end
        squadLight = hash % 100 < 50
    end
    local encounter = jobs[choose(#jobs)]
    if fairness ~= nil and not fairness.typeAllowed(encounter, fairness.kindAt(anchor.x, anchor.y)) then
        fairness.noteCut("rural_type")
        Director.lastDecision = "rural_type"
        return 0
    end

    local program = activities[encounter]
    local support = supportFor(faction)
    local reserved = {}
    Registry.each(function(actor)
        if actor.lifecycle ~= "dead" then
            local position = actor.worldPosition
            reserved[math.floor(position.x) .. ":" .. math.floor(position.y)
                .. ":" .. math.floor(position.z)] = true
        end
    end)
    local planned = {}
    local observers = {}
    for _, observer in ipairs(online) do
        local point = playerPosition(observer)
        if point then observers[#observers + 1] = point end
    end

    for memberIndex = 1, groupSize do
        local candidate = formationPosition(groupAnchor, memberIndex, groupSize)
        local position = SpawnPolicy.find(candidate, {
            searchRadius = 8,
            validator = function(point, square)
                local key = math.floor(point.x) .. ":" .. math.floor(point.y) .. ":" .. math.floor(point.z)
                if reserved[key] then return false end
                local dx, dy = point.x - anchor.x, point.y - anchor.y
                local gx, gy = point.x - groupAnchor.x, point.y - groupAnchor.y
                if dx * dx + dy * dy > rangeMax * rangeMax or gx * gx + gy * gy > 64 then return false end
                for _, observer in ipairs(observers) do
                    local ox, oy = point.x - observer.x, point.y - observer.y
                    if ox * ox + oy * oy < rangeMin * rangeMin then return false end
                end
                if fairness ~= nil and not fairness.windowOk(point.x, point.y) then return false end
                return SpawnRegions.allows(point, spawn, square) and not Director.inSight(point)
            end,
        })
        if not position then
            Director.lastDecision = "party_placement_unavailable"
            return 0
        end
        planned[memberIndex] = position
        reserved[math.floor(position.x) .. ":" .. math.floor(position.y) .. ":" .. math.floor(position.z)] = true
    end
    local pressure = ProjectALife.WorldPressure
    local hours = worldHour()
    local ticket, refusal = pressure.reserve({ id = "director:" .. groupId,
        x = groupAnchor.x, y = groupAnchor.y, z = groupAnchor.z, hours = hours,
        centerX = anchor.x, centerY = anchor.y })
    if ticket == nil then Director.lastDecision = refusal; return 0 end
    local spawned = 0
    local drawn = ProjectALife.RosterDraw ~= nil and ProjectALife.RosterDraw.begin() or nil
    for memberIndex = 1, groupSize do
        local profile = nil
        if drawn ~= nil then profile = ProjectALife.RosterDraw.pick(roster, drawn, roll) end
        profile = profile or profileFor(roster)
        local position = planned[memberIndex]
        if position ~= nil then
            local operationId = "director:" .. tostring(window) .. ":" .. faction.id
                .. ":" .. tostring(memberIndex)
            local conduct = conductFor(profile, faction, memberIndex, groupSize)
            local actor, replayed = Registry.create({
                operationId = operationId,
                fingerprint = operationId,
                profileId = profile.id,
                factionId = faction.id,
                worldPosition = position,
                activity = "idle",
                intent = "enter_world",
                memory = {
                    groupId = groupId,
                    groupIndex = memberIndex,
                    groupSize = groupSize,
                    partyKind = partyKind,
                    encounter = encounter,
                    behavior = program,
                    behaviorProfile = behaviorFor(profile, encounter, program),
                    conduct = conduct,
                    moduleOverrides = mergedModuleOverrides(faction, profile, conduct),
                    memberPolicyVersion = 2,
                    support = support,
                    supportCaller = profile.general
                        and profile.general.supportCaller == true or nil,

                    nightvision = nightvision or nil,
                    flashlight = squadLight or nil,
                    home = position,
                    spawnOrigin = position,
                },
            })
            if actor ~= nil and replayed ~= true then spawned = spawned + 1 end
        end
    end
    if spawned > 0 then pressure.commit(ticket, hours, groupId)
    else pressure.release(ticket, hours) end
    return spawned
end

function Director.configure(adapters)
    Director.adapters = adapters or {}
    Director.enabled = Director.adapters.enabled ~= false
    Director.spawnMultiplier = math.max(
        0, tonumber(Director.adapters.spawnMultiplier) or 1)
    Director.groupMultiplier = math.max(
        0.25, tonumber(Director.adapters.groupMultiplier) or 1)
    Director.maximumLivingActors = math.max(

        1, math.min(400, math.floor(tonumber(Director.adapters.maximumLivingActors) or 32)))
    Director.encounterIntervalHours = math.max(
        1, math.min(24, tonumber(Director.adapters.encounterIntervalHours) or 6))
    Director.encounterChance = math.max(
        0, math.min(1, tonumber(Director.adapters.encounterChance) or 0.15))
    rebuildRosters()
end

function Director.reset()
    Director.rosters = {}
    Director.lastWindow = tonumber(Registry.getWorldValue("directorWindow"))
    Director.lastDecision = "not_checked"
end

local function weightedFactions(day, hour, online)
    local result, total = {}, 0
    for _, faction in ipairs(Catalog.current.factionOrder) do
        if eligible(faction, day, hour, online) then

            local weight = ProjectALife.FactionSpawnRules.weightFor(faction, day)
            if weight > 0 then
                total = total + weight
                result[#result + 1] = { faction = faction, ceiling = total }
            end
        end
    end
    return result, total
end

function Director.pacing(total, reference)
    local rules, pressure = ProjectALife.FactionSpawnRules, ProjectALife.WorldPressure
    local presence, vitality = 1, 1
    if type(rules) == "table" and type(rules.presence) == "function" then presence = rules.presence(total, reference) end
    if type(pressure) == "table" and type(pressure.censusVitality) == "function" then
        vitality = pressure.censusVitality()
    end
    return presence, vitality
end

function Director.stockReference(day, hour, online)
    local catalog, rules = ProjectALife.Catalog, ProjectALife.FactionSpawnRules
    local shipped = type(catalog) == "table" and catalog.shipped or nil
    if type(shipped) ~= "table" or type(shipped.factionOrder) ~= "table" or type(rules) ~= "table"
            or type(rules.presence) ~= "function" then return nil end
    local total = 0
    for _, faction in ipairs(shipped.factionOrder) do
        if rules.available(faction, day, hour) and #rules.roamingEncounters(faction.spawn) > 0 then
            for _, player in ipairs(online or {}) do
                if locationAllowed(faction, player) then
                    total = total + rules.weightFor(faction, day, true)
                    break
                end
            end
        end
    end
    if total <= 0 then return nil end
    return math.min(tonumber(rules.referenceWeight) or 1, total)
end

local function chooseWeighted(candidates, total)
    if #candidates == 0 or total <= 0 then return nil end
    local needle = roll() * total
    for _, candidate in ipairs(candidates) do
        if needle < candidate.ceiling then return candidate.faction end
    end
    return candidates[#candidates].faction
end

function Director.tick()
    if not Director.enabled or Catalog.current == nil then return 0 end
    local hour = worldHour()
    local clock = clockHour(hour)
    local window = math.floor(hour / Director.encounterIntervalHours)
    if Director.lastWindow == window then return 0 end
    local online = players()
    if #online == 0 then Director.lastDecision = "no_players"; return 0 end
    local persisted, persistError = Registry.setWorldValue("directorWindow", window)
    if not persisted then
        Director.lastDecision = persistError or "window_persistence_failed"
        return 0
    end
    Director.lastWindow = window
    local day = hour / 24
    local living = livingCount()
    if living >= Director.maximumLivingActors then
        Director.lastDecision = "actor_cap"
        return 0
    end
    local gate = math.min(0.9, Director.encounterChance * Director.spawnMultiplier)
    local unit = roll()
    if unit >= gate then Director.lastDecision = "chance_gate"; return 0 end
    local candidates, total = weightedFactions(day, clock, online)
    local presence, vitality = Director.pacing(total, Director.stockReference(day, clock, online))
    if unit >= gate * presence then Director.lastDecision = "faction_weight"; return 0 end
    if unit >= gate * presence * vitality then Director.lastDecision = "census_quiet"; return 0 end
    local faction = chooseWeighted(candidates, total)
    if faction == nil then Director.lastDecision = "no_eligible_faction"; return 0 end
    local actors = spawnGroup(
        faction, online, window, Director.maximumLivingActors - living)
    if actors > 0 then Director.lastDecision = "spawned:" .. faction.id
    elseif string.sub(tostring(Director.lastDecision), 1, 9) ~= "pressure_" then
        Director.lastDecision = "no_valid_square"
    end
    return actors
end

return Director
