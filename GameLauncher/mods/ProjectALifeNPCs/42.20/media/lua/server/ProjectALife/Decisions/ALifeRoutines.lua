require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Combat/ALifeSquadTactics"
require "ProjectALife/Records/ALifeBehaviorProfiles"
require "ProjectALife/Decisions/ALifeKnowledge"

ProjectALife = ProjectALife or {}

local Programs = { adapters = {}, settings = {} }
ProjectALife.Programs = Programs
local PlayerLocator = ProjectALife.PlayerLocator
local Tactics = ProjectALife.SquadTactics
local defaults = ProjectALife.BehaviorSettings.programs

local DIRECT_MODES = {
    roam = "roam", patrol = "patrol", scavenge = "scavenge",
    hunt = "hunt", manhunt = "manhunt",
}

local HOME_PROGRAMS = {
    camp = true,
    outpost = true,
    blockade = true,
}

local ENCOUNTER_MODES = {
    patrol = "patrol", raid = "hunt", fullscale_raid = "hunt",
    assassination = "manhunt",

    highway_ambush = "hunt",
    blockade = "guard",
    rooftop_snipers = "guard",
    poi_defenders = "guard",
    broken_car = "scavenge",
    town_patrol = "patrol",
    scavenger_crew = "scavenge",

    car_crash = "guard",
}

local ADMIN_MODES = {
    roam = "roam",
    patrol = "patrol",
    scavenge = "scavenge",
    scavenging = "scavenge",
    hunt = "hunt",
    manhunt = "manhunt",
    guard = "patrol",
    camp = "patrol",
    blockade = "patrol",
    outpost = "patrol",
    assault = "hunt",
    full_raid = "manhunt",

    looter = "scavenge",
    scavenger = "scavenge",
    seek_destroy = "hunt",
}

Programs.roamDefaults = {
    roamLegTiles = 24, roamLegSpreadTiles = 8, roamLegMs = 20000,
    roamTetherTiles = 40, roamTurnDegrees = 35,
}

function Programs.configure(adapters)
    Programs.adapters = adapters or {}
    Programs.settings = {}
    for name, value in pairs(defaults) do
        Programs.settings[name] = tonumber(Programs.adapters[name]) or value
    end
    for name, value in pairs(Programs.roamDefaults) do
        Programs.settings[name] = tonumber(Programs.adapters[name]) or value
    end
end

function Programs.encounterForFaction(faction, chooseIndex)
    local spawn = faction and faction.spawn or {}
    local choices = {}
    for value in string.gmatch(tostring(spawn.encounterPool or "roamer") .. "|", "(.-)|") do
        value = string.match(value, "^%s*(.-)%s*$")

        value = (string.gsub(value, "@%d+$", ""))
        if HOME_PROGRAMS[value] or DIRECT_MODES[value] or ENCOUNTER_MODES[value]
                or value == "roamer" then
            choices[#choices + 1] = value
        end
    end
    if #choices == 0 then return "roamer" end
    local index = type(chooseIndex) == "function" and chooseIndex(#choices) or 1
    return choices[math.max(1, math.min(#choices, math.floor(tonumber(index) or 1)))]
end

function Programs.programForFaction(faction, chooseIndex)
    local spawn = faction and faction.spawn or {}
    local choices = {}
    for value in string.gmatch(tostring(spawn.programPool or spawn.program or "patrol")
            .. "|", "(.-)|") do
        value = string.lower(string.match(value, "^%s*(.-)%s*$"))
        if DIRECT_MODES[value] or ADMIN_MODES[value] then choices[#choices + 1] = value end
    end
    if #choices == 0 then return tostring(spawn.program or "patrol") end
    local index = type(chooseIndex) == "function" and chooseIndex(#choices) or 1
    return choices[math.max(1, math.min(#choices, math.floor(tonumber(index) or 1)))]
end

local function players()
    return PlayerLocator.list(Programs.adapters.players)
end

local function position(value)
    return PlayerLocator.position(value, Programs.adapters.position)
end

local function alive(value)
    local ok, dead = pcall(function() return value:isDead() end)
    return not ok or dead ~= true
end

local function nearestPlayer(shell, maximumDistance, hostileFor)
    local origin = position(shell)
    if origin == nil then return nil, nil, math.huge end
    local relations = hostileFor ~= nil and ProjectALife.Relations or nil
    local judge = relations ~= nil and type(relations.hostileToPlayer) == "function"
        and relations.hostileToPlayer or nil

    local policy = ProjectALife.TargetPolicy
    local shielded = policy ~= nil and type(policy.protection) == "function" and policy.protection or nil
    local best, bestPosition, bestDistance = nil, nil, math.huge
    for _, player in ipairs(players()) do
        local candidate = position(player)
        if candidate ~= nil and alive(player)
                and (judge == nil or judge(hostileFor, player) == true)
                and (shielded == nil or shielded(player) == nil) then
            local dx, dy, dz = origin.x - candidate.x,
                origin.y - candidate.y, origin.z - candidate.z
            local distance = dx * dx + dy * dy + dz * dz
            if distance < bestDistance then
                best, bestPosition, bestDistance = player, candidate, distance
            end
        end
    end
    local limit = tonumber(maximumDistance)
    if limit ~= nil and bestDistance > limit * limit then return nil, nil, bestDistance end
    return best, bestPosition, bestDistance
end

function Programs.answersTo(player, expected)
    local ok, current = pcall(function() return player:getUsername() end)
    if ok and string.lower(tostring(current or "")) == expected then return true end
    local reputation = ProjectALife.Reputation
    if reputation == nil or type(reputation.playerKey) ~= "function" then return false end
    return string.lower(tostring(reputation.playerKey(player) or "")) == expected
end

local function namedPlayer(username)
    if type(username) ~= "string" or username == "" then return nil, nil end
    local expected = string.lower(username)
    local policy = ProjectALife.TargetPolicy
    local shielded = policy ~= nil and type(policy.protection) == "function" and policy.protection or nil
    for _, player in ipairs(players()) do
        if Programs.answersTo(player, expected) and alive(player) then
            if shielded ~= nil and shielded(player) ~= nil then return nil, nil end
            return player, position(player)
        end
    end
    return nil, nil
end

function Programs.mode(actor, factionProgram)
    local memory = actor and actor.memory or {}

    local profiles = ProjectALife.BehaviorProfiles
    if profiles ~= nil and type(memory.behaviorProfile) == "string" then
        local profileMode = profiles.mode(actor)

        if profileMode == "assault" then
            local asked = ADMIN_MODES[string.lower(tostring(memory.adminMode or ""))]
                or ADMIN_MODES[string.lower(tostring(memory.behavior or ""))]
                or ENCOUNTER_MODES[string.lower(tostring(memory.encounter or ""))]
            if asked == "hunt" or asked == "manhunt" then return asked end
        end
        if profileMode ~= nil then return profileMode end
    end
    local admin = ADMIN_MODES[string.lower(tostring(memory.adminMode or ""))]
        or ADMIN_MODES[string.lower(tostring(memory.behavior or ""))]
    if admin ~= nil then return admin end
    local encounter = string.lower(tostring(memory.encounter or "roamer"))
    if ENCOUNTER_MODES[encounter] then return ENCOUNTER_MODES[encounter] end
    if HOME_PROGRAMS[encounter] then return "patrol" end

    if DIRECT_MODES[encounter] then return DIRECT_MODES[encounter] end

    local program = string.lower(tostring(factionProgram or "roam"))
    if program == "looter" then return "scavenge" end
    if program == "assault" then return "hunt" end
    if program == "full_raid" then return "manhunt" end
    return program == "patrol" and "patrol" or "roam"
end

function Programs.grudgeStands(actor, player)
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.hostileToPlayer) ~= "function" then return true end
    return relations.hostileToPlayer(actor, player) == true
end

function Programs.pursuitTarget(actor, shell, factionProgram)
    local mode = Programs.mode(actor, factionProgram)
    if mode ~= "hunt" and mode ~= "manhunt" then return nil, mode end
    local radius = mode == "manhunt" and Programs.settings.manhuntRadius
        or Programs.settings.huntRadius
    local memory = actor and actor.memory or {}

    if memory.role == "backup" or memory.supportRole == "backup" then return nil, mode end
    local requested, requestedPosition = namedPlayer(memory.targetUsername)

    if requested ~= nil and memory.revengeKey ~= nil and not Programs.grudgeStands(actor, requested) then
        requested = nil
    end
    if requested ~= nil then
        local origin = position(shell)
        if origin ~= nil and requestedPosition ~= nil then
            local dx, dy, dz = origin.x - requestedPosition.x,
                origin.y - requestedPosition.y, origin.z - requestedPosition.z
            if dx * dx + dy * dy + dz * dz <= radius * radius then
                return requested, mode, requestedPosition
            end
        end
    end

    local blame = ProjectALife.Blame
    if blame ~= nil and blame.keepsTarget(memory) then return nil, mode end

    local target, targetPosition = nearestPlayer(shell, radius, actor)
    return target, mode, targetPosition
end

function Programs.pursuitThreat(actor, shell, factionProgram)
    local target, mode = Programs.pursuitTarget(actor, shell, factionProgram)
    local knowledge = ProjectALife.Knowledge
    if target == nil or knowledge == nil or type(knowledge.pursuitThreat) ~= "function" then return target, mode end
    return knowledge.pursuitThreat(actor, shell, target), mode
end

function Programs.pursuitPoint(actor, shell, target, targetPosition, mode, now)
    local knowledge = ProjectALife.Knowledge
    if knowledge == nil or type(knowledge.pursuitLead) ~= "function" then return targetPosition end
    return knowledge.pursuitLead(actor, shell, target, targetPosition, mode, now)
end

function Programs.baseRefuses(x, y)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.inPlayerBase) ~= "function" then return false end
    local ok, inside = pcall(policy.inPlayerBase, x, y, true)
    return ok and inside == true
end

local TWO_PI = math.pi * 2

local function degreesToRadians(degrees)
    return degrees * math.pi / 180
end

local function randomDegrees(minimum, maximum)
    if type(ZombRandBetween) == "function" then return ZombRandBetween(minimum, maximum) end
    return math.random(minimum, maximum)
end

function Programs.roamHeading(previousHeadingRad)
    if type(previousHeadingRad) ~= "number" then
        return degreesToRadians(randomDegrees(0, 359))
    end
    local heading = previousHeadingRad + degreesToRadians(randomDegrees(-45, 45))
    heading = heading % TWO_PI
    if heading < 0 then heading = heading + TWO_PI end
    return heading
end

function Programs.normalHeading(heading)
    heading = heading % TWO_PI
    if heading < 0 then heading = heading + TWO_PI end
    return heading
end

function Programs.bearing(ax, ay, bx, by)
    if type(math.atan2) == "function" then return math.atan2(by - ay, bx - ax) end
    return math.atan(by - ay, bx - ax)
end

function Programs.loadedAt(x, y, z)
    if type(Programs.adapters.loadedAt) == "function" then
        return Programs.adapters.loadedAt(x, y, z) == true
    end
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or cell.getGridSquare == nil then return true end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(z) or 0)) ~= nil
end

function Programs.roamAnchor(memory)
    if type(memory) ~= "table" then return nil, nil end
    local point = memory.home
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then
        point = memory.spawnOrigin
    end
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then
        return nil, nil
    end
    return tonumber(point.x), tonumber(point.y)
end

function Programs.roamLeg(memory, origin, previousHeadingRad, now)
    local settings = Programs.settings
    local heading = Programs.roamHeading(previousHeadingRad)
    local anchorX, anchorY = Programs.roamAnchor(memory)
    local tether = tonumber(settings.roamTetherTiles) or 40
    if anchorX ~= nil and (anchorX - origin.x) ^ 2 + (anchorY - origin.y) ^ 2 > tether * tether then
        local turn = tonumber(settings.roamTurnDegrees) or 35
        heading = Programs.bearing(origin.x, origin.y, anchorX, anchorY)
            + degreesToRadians(randomDegrees(-turn, turn))
    end
    local length = (tonumber(settings.roamLegTiles) or 24)
        + randomDegrees(0, math.max(0, math.floor(tonumber(settings.roamLegSpreadTiles) or 8)))
    for _ = 1, 4 do
        local x = origin.x + math.cos(heading) * length
        local y = origin.y + math.sin(heading) * length
        local z = origin.z
        local loaded = Programs.loadedAt(x, y, z)
        if not loaded and (tonumber(z) or 0) ~= 0 and Programs.loadedAt(x, y, 0) then
            loaded, z = true, 0
        end
        if loaded and Programs.baseRefuses(x, y) then loaded = false end
        if loaded then
            heading = Programs.normalHeading(heading)
            return { x = x, y = y, z = z, heading = heading,
                untilMs = (tonumber(now) or 0) + (tonumber(settings.roamLegMs) or 20000) }
        end
        heading = heading + math.pi * 0.5
    end
    return nil
end

function Programs.roamDestination(shell, previousHeadingRad, radius)
    local heading = Programs.roamHeading(previousHeadingRad)
    radius = math.max(16, tonumber(radius) or 16)
    local origin = position(shell)
    if origin == nil then return nil, heading end
    local fraction = type(ZombRandBetween) == "function"
        and (ZombRandBetween(0, 100) / 100) or math.random()
    local distance = radius * 0.5 + radius * 0.5 * fraction
    return {
        x = origin.x + math.cos(heading) * distance,
        y = origin.y + math.sin(heading) * distance,
        z = origin.z,
    }, heading
end

function Programs.supportDestination(actor, shell, suppliedNow)
    local memory = actor.memory or {}

    local alert = memory.outpostAlert
    if type(alert) == "table" and (tonumber(suppliedNow) or 0) < (tonumber(alert.untilMs) or 0) then
        local origin = position(shell)
        if origin and (origin.x - (tonumber(alert.x) or 0))^2 + (origin.y - (tonumber(alert.y) or 0))^2 > 9 then
            return { x = tonumber(alert.x) or 0, y = tonumber(alert.y) or 0, z = tonumber(alert.z) or 0 }, "outpost_alarm"
        end
    end
    local backup = memory.role == "backup" or memory.supportRole == "backup"
    local field = backup and "objective" or "supportSpotlightObjective"
    local objective = memory[field]
    if type(objective) == "table" and not objective.searched then
        local origin = position(shell)
        if origin and (objective.untilMs == nil or (tonumber(suppliedNow) or 0) < objective.untilMs) then
            if (origin.x - objective.x)^2 + (origin.y - objective.y)^2 > 9 then
                return objective, "backup_search"
            end

            local registry = ProjectALife.ActorRegistry
            if registry and registry.updateTransient and actor.uid then
                registry.updateTransient(actor.uid, actor.revision, function(record)
                    local current = record.memory[field]
                    if current and current.x == objective.x and current.y == objective.y then current.searched = true end
                end)
            end
        end
    end
end

function Programs.destination(
        actor, shell, randomTarget, factionProgram, suppliedNow, previousHeadingRad)
    local memory = actor.memory or {}
    local mode = Programs.mode(actor, factionProgram)
    local objective, supportIntent = Programs.supportDestination(actor, shell, suppliedNow)
    if objective then return objective, supportIntent, { mode = mode } end
    if mode == "hunt" or mode == "manhunt" then
        local target, _, targetPosition = Programs.pursuitTarget(actor, shell, factionProgram)
        local lead = targetPosition ~= nil
            and Programs.pursuitPoint(actor, shell, target, targetPosition, mode, suppliedNow) or nil
        if lead ~= nil then
            return lead, mode == "manhunt" and "manhunt_player" or "hunt_nearby",
                { target = target, pursuit = true, mode = mode, lead = lead }
        end
    end
    if mode == "patrol" then
        local anchor = type(memory.home) == "table" and memory.home
            or type(memory.spawnOrigin) == "table" and memory.spawnOrigin
            or position(shell)
        local target = Tactics.patrolDestination(
            actor, anchor, suppliedNow,
            memory.patrolRadius or Programs.settings.patrolRadius)
        local Movement = ProjectALife.Movement
        if target ~= nil and Movement ~= nil and type(Movement.patrolBlocked) == "function"
                and Movement.patrolBlocked(shell, target, suppliedNow) then
            Tactics.advancePatrol(actor)
            return nil
        end
        if target ~= nil then return target, "patrol", { mode = mode } end
    end
    if mode == "scavenge" then

        local target, nextHeading = Programs.roamDestination(
            shell, previousHeadingRad, Programs.settings.roamRadius)
        if target ~= nil then
            return target, "collect_supplies", { mode = mode }, nextHeading
        end
        return randomTarget(shell, Programs.settings.roamRadius),
            "collect_supplies", { mode = mode }
    end

    if mode == "roam" or mode == "assault" or mode == "hunt" or mode == "manhunt" then
        local latch = type(memory.travelLeg) == "table" and memory.travelLeg or nil
        local origin = position(shell)
        local now = tonumber(suppliedNow) or 0
        if origin ~= nil then
            local arrived = latch ~= nil
                and ((tonumber(latch.x) or 0) - origin.x) ^ 2
                    + ((tonumber(latch.y) or 0) - origin.y) ^ 2 <= 16
            local expired = latch == nil or now >= (tonumber(latch.untilMs) or 0)
            if arrived or expired then

                latch = Programs.roamLeg(memory, origin, previousHeadingRad, now)
                if latch == nil then return nil, "patrol", { mode = mode } end
                return latch, "patrol", { mode = mode, travelLeg = latch, newLeg = true }, latch.heading
            end

            return { x = latch.x, y = latch.y, z = latch.z }, "patrol",
                { mode = mode, travelLeg = latch }, tonumber(latch.heading)
        end
        local target, nextHeading = Programs.roamDestination(
            shell, previousHeadingRad, Programs.settings.roamRadius)
        if target ~= nil then return target, "patrol", { mode = mode }, nextHeading end
    end
    local radius = mode == "roam" and Programs.settings.roamRadius
        or Programs.settings.patrolRadius
    return randomTarget(shell, radius), "patrol", { mode = mode }
end

Programs.configure()

return Programs
