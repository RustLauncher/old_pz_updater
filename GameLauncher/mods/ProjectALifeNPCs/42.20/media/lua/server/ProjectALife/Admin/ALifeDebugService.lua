require "ProjectALife/Compat/ALifeCompatRegistry"
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/World/ALifeSpawnService"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/Admin/ALifeDiagnostics"
require "ProjectALife/Admin/ALifeSquadMapEncounters"
require "ProjectALife/Core/ALifeTelemetry"
require "ProjectALife/Admin/ALifeBlackBox"
require "ProjectALife/Core/ALifeWatchdog"
require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/Outposts/ALifeOutpostPresets"
require "ProjectALife/Outposts/ALifeSceneKit"
require "ProjectALife/Records/ALifeCustomProfileAuthority"
require "ProjectALife/Records/ALifeCustomFactionAuthority"
require "ProjectALife/Records/ALifeCreatorTransfer"
require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Admin/ALifeAdminConsoleService"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Animations = ProjectALife.Animations
local Registry = ProjectALife.ActorRegistry
local SpawnService = ProjectALife.SpawnService
local SpawnPolicy = ProjectALife.SpawnPolicy
local Diagnostics = ProjectALife.Diagnostics
local Telemetry = ProjectALife.Telemetry
local Watchdog = ProjectALife.Watchdog
local Service = {
    adapters = {}, lastAtMs = {}, sequence = 0, requestSequence = 0,
    gameplaySequences = setmetatable({}, { __mode = "k" }),
    lastSwingAtMs = setmetatable({}, { __mode = "k" }),
    minimumIntervalMs = 250,
    queue = {}, maximumQueued = 32,
    groups = {}, pendingJobs = {}, pendingOrder = {},
    groupOutcomes = {}, groupOutcomeOrder = {}, maximumGroupOutcomes = 128,
}
ProjectALife.DebugService = Service

local SPAWN_CONDUCTS = {
    leader = true, sniper = true, medic = true, ambusher = true, stealth = true,

    gunner = true,

}

local offsets = {
    { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 },
    { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 },
}

local modeOrder = {
    "roam", "patrol", "scavenge", "hunt", "manhunt", "guard",
    "camp", "blockade", "outpost", "assault", "full_raid",
}

local modes = {
    roam = {
        label = "Scout Assault", encounter = "roamer", intent = "enter_world",
        summary = "Moves through the area and attacks threats it detects.",
        profile = "seek_destroy",
    },
    patrol = {
        label = "Area Patrol", encounter = "roamer", intent = "patrol", home = true,
        summary = "Circulates around the spawn point and returns to its route.",
        profile = "patrol",
    },
    scavenge = {
        label = "Scavenge Route", encounter = "roamer", intent = "collect_supplies",
        summary = "Searches nearby containers, collects supplies, then continues.",
        profile = "scavenger",
    },
    hunt = {
        label = "Search and Destroy", encounter = "roamer", intent = "hunt_nearby",
        summary = "Actively searches the local area for hostile targets.",
        profile = "seek_destroy",
    },
    manhunt = {
        label = "Manhunt", encounter = "assassination", intent = "manhunt_player",
        summary = "Tracks the designated player and keeps re-engaging.",
        profile = "manhunt",
    },
    guard = {
        label = "Hold Position", encounter = "poi_defenders", intent = "guard", home = true,
        allowProtected = true,
        summary = "Treats the spawn point as home and defends its radius.",
        profile = "patrol",
    },
    camp = {
        label = "Camp", encounter = "camp", intent = "guard_camp", home = true,
        summary = "Stays around a temporary camp and defends the perimeter.",
        profile = "patrol", stance = "camp", scene = "camp",
    },
    blockade = {
        label = "Blockade", encounter = "blockade", intent = "guard_blockade",
        home = true,
        summary = "Cars across the road, a line of guns behind them.",
        profile = "patrol", stance = "blockade", scene = "blockade",
    },
    outpost = {
        label = "Outpost Defence", encounter = "outpost", intent = "guard_outpost",
        home = true,
        summary = "Patrols and defends a persistent outpost anchor.",
        profile = "patrol",
    },
    assault = {
        label = "Assault", encounter = "raid", intent = "assault_player",
        summary = "Advances on nearby players as an attacking group.",
        profile = "seek_destroy",
    },
    full_raid = {
        label = "Full Raid", encounter = "fullscale_raid", intent = "full_raid",
        summary = "Runs a sustained coordinated attack against players.",
        profile = "manhunt",
    },
}

local spawnCommands = {
    debugSpawn = "request",
    debugSpawnRoam = "roam",
    debugSpawnPatrol = "patrol",
    debugSpawnScavenge = "scavenge",
    debugSpawnHunt = "hunt",
    debugSpawnManhunt = "manhunt",
    debugSpawnGuard = "guard",
    debugSpawnCamp = "camp",
    debugSpawnBlockade = "blockade",
    debugSpawnOutpost = "outpost",
    debugSpawnAssault = "assault",
    debugSpawnFullRaid = "full_raid",
}

local commands = {

    shellHit = true,
    debugPickedOver = true,
    debugWardrobe = true,
    weaponNoise = true,
    shout = true,
    playerDied = true,
    outpostRadioList = true,
    outpostRadioDisable = true,
    outpostRadioUse = true,
    RaidPreludeFinished = true,
    FullRaidPreludeFinished = true,
    creatorProfileHello = true,
    creatorFactionHello = true,

    safehouseHello = true,
    safehouseWash = true,

    debugSafehouse = true,
    debugInjury = true,
    debugModuleQA = true,
    debugBlackbox = true,
    debugMetaEvent = true,
    debugBuildOutpost = true,
    debugForceSupport = true,
    raidStart = true,
    debugSquadMap = true,
    debugTownCensus = true,

    debugSquadDelete = true,
    debugOutpostDelete = true,
    debugOutpostSquadNow = true,
    debugOutpostDelay = true,
    debugOutpostSquadCap = true,
    debugOutpostLights = true,
    debugEncounterMarks = true,
    debugDirectorState = true,
    debugCatalog = true,
    debugCatalogFaction = true,
    debugEncounters = true,
    debugSpawnCatalog = true,
    debugDiagnostics = true,
    debugRepair = true,
    debugRepAdjust = true,
    debugActors = true,
    debugAddNoSpawnZone = true,
    debugClearNoSpawnZones = true,
    debugPurgeActors = true,
    debugResetCreator = true,
    debugSyncCreator = true,
    creatorUpload = true,
    adminActorFlags = true,
    creatorProfileUpsert = true,
    creatorProfileDelete = true,
    creatorFactionUpsert = true,
    creatorFactionDelete = true,
    creatorFactionReset = true,

    alifeDiagnostics = true,
}
for command in pairs(spawnCommands) do commands[command] = true end
for command in pairs((ProjectALife.AdminConsoleService or {}).commands or {}) do commands[command] = true end

Service.diagnosticsBy = {}
Service.diagnosticCommands = {}
for _, command in ipairs({
    "debugInjury", "debugModuleQA", "debugBlackbox", "debugMetaEvent", "debugBuildOutpost",
    "debugForceSupport", "raidStart", "debugSquadMap", "debugSquadDelete",
    "debugOutpostDelete", "debugOutpostSquadNow", "debugOutpostDelay",
    "debugOutpostSquadCap", "debugEncounterMarks", "debugDirectorState",
    "debugCatalog", "debugCatalogFaction", "debugEncounters", "debugSpawnCatalog",
    "debugDiagnostics",
    "debugRepair", "debugActors", "debugAddNoSpawnZone",
    "debugClearNoSpawnZones", "debugPurgeActors", "debugResetCreator",
    "adminActorFlags", "debugTownCensus", "debugRepAdjust", "debugPickedOver", "debugOutpostLights", "debugWardrobe",
}) do Service.diagnosticCommands[command] = true end
for command in pairs(spawnCommands) do Service.diagnosticCommands[command] = true end
for command in pairs((ProjectALife.AdminConsoleService or {}).commands or {}) do Service.diagnosticCommands[command] = true end

local function nowMs()
    if type(Service.adapters.nowMs) == "function" then return Service.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function tableCount(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end

local function clone(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do result[key] = value end
    return result
end

local function positionCopy(position)
    return { x = position.x, y = position.y, z = position.z }
end

local function configBool(value)
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
    local text = string.lower(tostring(value or ""))
    return text == "true" or text == "1" or text == "yes" or text == "on"
end

local function hostility(value)
    if type(value) == "boolean" then return value end
    if value == "friendly" then return false end
    if value == "hostile" then return true end
end

local function spawnStance(value)
    if value == "friendly" or value == "neutral"
            or value == "careful" or value == "hostile" then return value end
    return nil
end
Service.normalizeSpawnStance = spawnStance

local function conditionRung(value)
    local rung = tonumber(value)
    if rung == nil or rung ~= rung then return nil end
    rung = math.floor(rung)
    if rung < 0 or rung > 10 then return nil end
    return rung
end
Service.normalizeConditionRung = conditionRung

local function arrivalMode(value)
    if value == "heli" or value == "ground" then return value end
    return "foot"
end
Service.normalizeArrival = arrivalMode

function Service.arrivalDelayMs(mode)
    if mode == "heli" then return 22000 end
    if mode == "ground" then return 11000 end
    return 0
end

function Service.announceArrival(mode, point, target)
    if mode ~= "heli" and mode ~= "ground" then return false end
    if type(point) ~= "table" then return false end
    local payload = {
        supportId = "admin:arrival:" .. tostring(math.floor(nowMs())),
        x = point.x, y = point.y, z = 0,
        delivery = mode, mode = "admin",
        tx = tonumber(target and target.x) or point.x,
        ty = tonumber(target and target.y) or point.y,
        duration = mode == "heli" and 22 or 11,
    }
    pcall(function()
        if type(isServer) ~= "function" or not isServer() then return end
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players == nil then return end
        for index = 0, players:size() - 1 do
            local watcher = players:get(index)
            if watcher ~= nil then
                sendServerCommand(watcher, "ProjectALife", "supportArrival", payload)
            end
        end
    end)
    pcall(function()
        local fx = ProjectALife.SupportClient
        if fx ~= nil and type(fx.onArrival) == "function" then fx.onArrival(payload) end
    end)
    return true
end
Service.normalizeHostility = hostility

local function normalizeAdminFlags(source, anchor, existing)
    source = type(source) == "table" and source or {}
    existing = type(existing) == "table" and existing or {}
    anchor = type(anchor) == "table" and anchor or { x = 0, y = 0, z = 0 }
    local result = {}
    for _, name in ipairs({ "persistent", "invulnerable", "stationary" }) do
        if source[name] ~= nil then
            result[name] = configBool(source[name])
        else
            result[name] = existing[name] == true
        end
    end

    for _, name in ipairs({ "health", "damageReduction", "damageOutput" }) do
        local supplied = tonumber(source[name])
        if supplied ~= nil and supplied >= 0 then
            result[name] = supplied
        elseif tonumber(existing[name]) ~= nil then
            result[name] = tonumber(existing[name])
        end
    end
    local suppliedRadius = source.leashRadius
    if suppliedRadius == nil and type(source.leash) == "table" then
        suppliedRadius = source.leash.radius
    end
    if suppliedRadius ~= nil then
        local radius = math.max(0, math.min(100, tonumber(suppliedRadius) or 0))
        if radius > 0 then
            result.leash = {
                x = tonumber(anchor.x) or 0,
                y = tonumber(anchor.y) or 0,
                z = tonumber(anchor.z) or 0,
                radius = radius,
            }
        end
    elseif type(existing.leash) == "table"
            and tonumber(existing.leash.radius) ~= nil
            and tonumber(existing.leash.radius) > 0 then
        result.leash = {
            x = tonumber(existing.leash.x) or tonumber(anchor.x) or 0,
            y = tonumber(existing.leash.y) or tonumber(anchor.y) or 0,
            z = tonumber(existing.leash.z) or tonumber(anchor.z) or 0,
            radius = math.max(0, math.min(100, tonumber(existing.leash.radius))),
        }
    end
    return result
end

Service.normalizeAdminFlags = normalizeAdminFlags

local function playerKey(player)
    if player == nil or player.getUsername == nil then return tostring(player) end
    local username = player:getUsername()
    return tostring(username)
end

local function authorized(player)
    if type(Service.adapters.authorized) == "function" then
        return Service.adapters.authorized(player) == true
    end
    if type(isServer) ~= "function" or not isServer() then return true end
    if player == nil or type(player.getAccessLevel) ~= "function" then return false end
    local ok, level = pcall(player.getAccessLevel, player)
    return ok and string.lower(tostring(level or "")) == "admin"
end

function Service.diagnosticsAllowed(player)
    return Service.diagnosticsBy[playerKey(player)] == true
end

function Service.setDiagnostics(player, enabled, recorder)
    Service.diagnosticsBy[playerKey(player)] = enabled == true
    local box = ProjectALife.BlackBox
    if box ~= nil then

        if type(box.setEnabled) == "function" then box.setEnabled(recorder == true)
        else box.enabled = recorder == true end
    end
    return enabled == true
end

function Service.actorWithin(actor, originX, originY, radius)
    if type(actor) ~= "table" or originX == nil or originY == nil
            or radius == nil or radius <= 0 then return false end
    local ax, ay
    local binding = Watchdog.bindings[actor.uid]
    local shell = binding ~= nil and binding.shell or nil
    if shell ~= nil then
        pcall(function() ax, ay = shell:getX(), shell:getY() end)
    end
    if ax == nil or ay == nil then
        local placed = type(actor.worldPosition) == "table" and actor.worldPosition or nil
        ax = placed ~= nil and tonumber(placed.x) or tonumber(actor.x)
        ay = placed ~= nil and tonumber(placed.y) or tonumber(actor.y)
    end
    if ax == nil or ay == nil then return false end
    local dx, dy = ax - originX, ay - originY
    return dx * dx + dy * dy <= radius * radius
end

local function runtimeReady()
    if type(Service.adapters.runtimeReady) == "function" then
        return Service.adapters.runtimeReady() == true
    end
    return ProjectALife.Runtime ~= nil and ProjectALife.Runtime.started == true
end

local function playerPosition(player)
    if type(Service.adapters.playerPosition) == "function" then
        return Service.adapters.playerPosition(player)
    end
    local ok, x, y, z = pcall(function()
        return player:getX(), player:getY(), player:getZ()
    end)
    return ok and { x = x, y = y, z = z } or nil
end

function Service.dumpDestination()
    if type(isServer) == "function" and isServer() then
        return "the SERVER log (coop-console.txt for a co-op host)"
    end
    return "console.txt"
end

local function reply(player, command, payload)
    local console = ProjectALife.AdminConsoleService
    if console ~= nil and console.capture ~= nil then console.tap(command, payload) end
    if type(Service.adapters.send) == "function" then
        Service.adapters.send(player, "ProjectALife", command, payload)
    elseif (type(isServer) ~= "function" or not isServer())
            and type(ProjectALife.DebugClientReceive) == "function" then
        ProjectALife.DebugClientReceive("ProjectALife", command, payload)
    elseif type(sendServerCommand) == "function" then
        sendServerCommand(player, "ProjectALife", command, payload)
    end
end

local function safeReply(player, command, payload, context)
    local ok, reason = pcall(reply, player, command, payload)
    if not ok then
        Telemetry.emit("admin_spawn_reply_failed", {
            requestId = context and context.requestId,
            operationId = context and context.operationId,
            error = tostring(reason),
        })
    end
    return ok
end

local function hostile(profile)
    local faction = profile and Catalog.faction(profile.general.faction)
    return faction ~= nil and faction.spawn and faction.spawn.peaceable ~= true
end

local function rosterIndex(seed, size)
    local value = math.floor(math.abs(tonumber(seed) or 0))

    return value - math.floor(value / size) * size
end

local function hostileFactionId(seed)
    local current = Catalog.current or Catalog.load()
    if current == nil then return nil end
    local choices, seen = {}, {}
    for _, profile in ipairs(current.npcOrder or {}) do
        local factionId = tostring(profile.general and profile.general.faction or "")
        if factionId ~= "" and not seen[factionId] and hostile(profile)
                and not Service.visitorOnlyFaction(factionId) then
            seen[factionId] = true
            choices[#choices + 1] = factionId
        end
    end
    if #choices == 0 then return nil end
    local index = rosterIndex(seed, #choices)
    return choices[index + 1]
end
Service.hostileFactionId = hostileFactionId

local function modePayload()
    local result = {}
    for _, id in ipairs(modeOrder) do
        local specification = modes[id]
        result[#result + 1] = {
            id = id,
            label = specification.label,
            summary = specification.summary,
            encounter = specification.encounter,
            intent = specification.intent,
        }
    end
    return result
end

local function encounterDefinition(id)
    id = tostring(id or "")
    local encounters = ProjectALife.Encounters
    local definition = encounters ~= nil and encounters.get(id) or nil
    if definition ~= nil or id ~= "camp" then return definition end
    local presets = ProjectALife.OutpostPresets
    local preset = presets ~= nil and presets.get("forest_camp") or nil
    if preset == nil then return nil end
    return {
        id = "camp", label = tostring(preset.label or "Wilderness camp"),
        summary = "Builds the complete campsite and stages its squad in one plan.",
        minCount = preset.garrison.min, maxCount = preset.garrison.max,
        mode = "camp", profile = "patrol", placement = "clearing",
        persistent = true, stance = preset.stance or "camp", scene = "camp",
        schedule = preset.schedule, awareness = preset.awareness,
        conducts = { "leader" },
    }
end

local function encounterPayload()
    local result = {}
    for _, definition in ipairs(ProjectALife.Encounters.definitions or {}) do
        result[#result + 1] = {
            id = definition.id, label = definition.label, summary = definition.summary,
            minCount = definition.minCount, maxCount = definition.maxCount,

            stance = definition.stance, placement = definition.placement,
            admin = definition.admin,
            mode = definition.mode, placement = definition.placement or "town",
            stance = definition.stance, scene = definition.scene,
            persistent = definition.persistent == true,
        }
    end
    local camp = encounterDefinition("camp")
    if camp ~= nil then
        result[#result + 1] = {
            id = camp.id, label = camp.label, summary = camp.summary,
            minCount = camp.minCount, maxCount = camp.maxCount,
            mode = camp.mode, placement = camp.placement, stance = camp.stance,
            scene = camp.scene, persistent = true,
        }
    end
    return result
end

Service.encounterTally = {}

function Service.tallyEncounter(id, reason, count)
    id = tostring(id or "?")
    local row = Service.encounterTally[id]
    if row == nil then
        row = { queued = 0, spawned = 0, refused = {} }
        Service.encounterTally[id] = row
    end
    if reason == "queued" then
        row.queued = row.queued + (tonumber(count) or 1)
    elseif reason == nil then
        row.spawned = row.spawned + (tonumber(count) or 1)
    else
        reason = tostring(reason)
        row.refused[reason] = (row.refused[reason] or 0) + (tonumber(count) or 1)
    end
end

function Service.encounterQaLine()
    local ids = {}
    for id in pairs(Service.encounterTally) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        local row = Service.encounterTally[id]
        local reasons = {}
        for reason, count in pairs(row.refused) do reasons[#reasons + 1] = reason .. "=" .. tostring(count) end
        table.sort(reasons)
        parts[#parts + 1] = id .. "{queued=" .. tostring(row.queued) .. " spawned=" .. tostring(row.spawned)
            .. (#reasons > 0 and (" refused:" .. table.concat(reasons, "|")) or "") .. "}"
    end
    return "EncounterAdmin: " .. (#parts > 0 and table.concat(parts, " ") or "-")
end

function Service.refuseEncounter(player, args, id, reason, detail, base)
    reason = tostring(reason or "unknown")
    Service.tallyEncounter(id, reason)
    local encounters = ProjectALife.Encounters
    local text = reason
    if encounters ~= nil and type(encounters.refusalText) == "function" then
        text = encounters.refusalText(detail or reason)
        if text == (detail or reason) then text = encounters.refusalText(reason) end
    end
    local payload = {}
    if type(base) == "table" then
        for key, value in pairs(base) do payload[key] = value end
    end
    payload.ok, payload.requestId = false, payload.requestId or (type(args) == "table" and args.requestId or nil)
    payload.reason, payload.text, payload.detail = reason, text, detail
    payload.encounterId = tostring(id or "?")
    pcall(function() player:Say("A-Life: spawn refused (" .. text .. ")") end)
    reply(player, "debugSpawnResult", payload)
    return false
end

Service.anyFactionTokens = { ["*"] = true, [""] = true, any = true, all = true }

function Service.wantedFaction(factionId)
    if type(factionId) ~= "string" then return nil end
    local trimmed = string.lower(factionId)
    if Service.anyFactionTokens[trimmed] == true then return nil end
    return factionId
end

function Service.visitorOnlyFaction(factionId)
    local faction = type(factionId) == "string" and Catalog.faction(factionId) or nil
    return type(faction) == "table" and type(faction.spawn) == "table" and faction.spawn.visitorOnly == true
end

function Service.hostileProfileIds(count, seed, factionId, includeFriendly, asVisitor)
    local current = Catalog.current or Catalog.load()
    if current == nil then return nil end
    local wantedFaction = Service.wantedFaction(factionId)
    if wantedFaction ~= nil and asVisitor ~= true and Service.visitorOnlyFaction(wantedFaction) then
        return nil, "visitor_only_faction"
    end
    local pool = {}
    local weighted, profiles = false, {}
    for _, profile in ipairs(current.npcOrder or {}) do
        local mine = wantedFaction == nil
            or tostring(profile.general and profile.general.faction or "") == wantedFaction
        local faction = profile.general and Catalog.faction(profile.general.faction)
        local weight = tonumber(profile.general and profile.general.spawnWeight) or 1
        local visitorOnly = faction ~= nil and type(faction.spawn) == "table" and faction.spawn.visitorOnly == true
        if mine and faction ~= nil and weight > 0 and (includeFriendly == true or hostile(profile))
                and (asVisitor == true and wantedFaction ~= nil or not visitorOnly) then
            pool[#pool + 1] = profile.id
            profiles[#profiles + 1] = profile
            if weight ~= 1 then weighted = true end
        end
    end

    if #pool == 0 and wantedFaction ~= nil then
        return nil, includeFriendly and "faction_has_no_members" or "faction_has_no_hostiles"
    end
    if #pool == 0 then return nil end
    local wanted = math.max(1, math.min(8, math.floor(tonumber(count) or 1)))
    local picked = {}
    local index = rosterIndex(seed, #pool)
    local randomSeed = math.max(1, (tonumber(seed) or 1) % 2147483647)
    for _ = 1, wanted do
        index = (index + 1) % #pool
        randomSeed = (randomSeed * 48271) % 2147483647
        picked[#picked + 1] = weighted and Catalog.weightedProfile(profiles, randomSeed / 2147483647).id
            or pool[index + 1]
    end
    return picked
end

Service.catalogPageRows = 40
Service.catalogPageBytes = 8000
Service.catalogTextMax = 160
Service.catalogSlowMs = 50
Service.catalogLogGapMs = 30000
Service.catalogLoggedAt = {}
Service.catalogCache = nil
Service.catalogStamp = 0
Service.catalogMetrics = {
    requests = 0, factionRequests = 0, builds = 0, cacheHits = 0, pagesSent = 0,
    lastMs = 0, maxMs = 0, lastBuildMs = 0, refused = {},
}

function Service.resetCatalog()
    Service.catalogCache = nil
    Service.catalogLoggedAt = {}
    Service.catalogMetrics = {
        requests = 0, factionRequests = 0, builds = 0, cacheHits = 0, pagesSent = 0,
        lastMs = 0, maxMs = 0, lastBuildMs = 0, refused = {},
    }
end

function Service.utf8Size(text)
    if string.find(text, "[^\1-\127]") == nil then return #text end
    local size = 0
    for index = 1, #text do
        local unit = string.byte(text, index)
        if unit < 128 then size = size + 1
        elseif unit < 2048 then size = size + 2
        else size = size + 3 end
    end
    return size
end

function Service.wireSize(value)
    local kind = type(value)
    if kind == "string" then return 2 + Service.utf8Size(value) end
    if kind == "number" then return 8 end
    if kind == "boolean" then return 1 end
    if kind ~= "table" then return 0 end
    local size = 4
    for key, item in pairs(value) do
        size = size + 2 + Service.wireSize(key) + Service.wireSize(item)
    end
    return size
end

function Service.catalogText(value, fallback)
    local text = tostring(value or fallback or "")
    if #text <= Service.catalogTextMax then return text end
    local last = Service.catalogTextMax
    local edge = string.byte(text, last)
    if edge >= 55296 and edge <= 56319 then last = last - 1 end
    return string.sub(text, 1, last)
end

function Service.catalogPages(rows, maxRows, maxBytes)
    local pages, page, bytes = {}, {}, 0
    for _, row in ipairs(rows or {}) do
        local size = Service.wireSize(row)
        if #page > 0 and (#page >= maxRows or bytes + size > maxBytes) then
            pages[#pages + 1] = page
            page, bytes = {}, 0
        end
        page[#page + 1] = row
        bytes = bytes + size
    end
    if #page > 0 or #pages == 0 then pages[#pages + 1] = page end
    return pages
end

function Service.buildCatalog(current)
    local started = nowMs()
    local factions, slots, byFaction, profiles = {}, {}, {}, 0
    for _, profile in ipairs(current.npcOrder or {}) do
        local general = profile.general
        local faction = general ~= nil and current.factions[general.faction] or nil
        if faction ~= nil then
            local slot = slots[faction.id]
            if slot == nil then
                slot = {
                    id = faction.id,
                    name = Service.catalogText(faction.general and faction.general.name, faction.id),
                    program = faction.spawn and string.lower(tostring(faction.spawn.program or "patrol")) or "patrol",
                    count = 0,
                    visitorOnly = faction.spawn and faction.spawn.visitorOnly == true or nil,
                }
                slots[faction.id] = slot
                factions[#factions + 1] = slot
                byFaction[faction.id] = {}
            end
            local rows = byFaction[faction.id]
            slot.count = slot.count + 1
            rows[#rows + 1] = {
                id = profile.id,
                name = Service.catalogText(general.name, profile.id),
                factionId = faction.id,
                factionName = slot.name,
                endurance = tonumber(general.endurance) or 5,
                program = slot.program,
            }
            profiles = profiles + 1
        end
    end
    local ordinary, visitors = {}, {}
    for _, slot in ipairs(factions) do
        if slot.visitorOnly == true then visitors[#visitors + 1] = slot else ordinary[#ordinary + 1] = slot end
    end
    for _, slot in ipairs(visitors) do ordinary[#ordinary + 1] = slot end
    factions = ordinary

    local outpostPresets = {}
    local presets = ProjectALife.OutpostPresets
    for _, preset in ipairs(presets and presets.list or {}) do
        if preset.placeholder ~= true then
            outpostPresets[#outpostPresets + 1] = {
                id = preset.id, label = preset.label, class = preset.class,
                garrisonMin = preset.garrison and preset.garrison.min or nil,
                garrisonMax = preset.garrison and preset.garrison.max or nil,
            }
        end
    end
    Service.catalogStamp = Service.catalogStamp + 1
    local cache = {
        source = current, total = #(current.npcOrder or {}),
        stamp = string.format("%.0f", started) .. ":" .. tostring(Service.catalogStamp),
        factionCount = #factions, profileCount = profiles,
        factionPages = Service.catalogPages(factions, Service.catalogPageRows, Service.catalogPageBytes),
        profileRows = byFaction, profilePages = {},
        meta = {
            animations = Animations.list(), modes = modePayload(),
            encounters = encounterPayload(), outpostPresets = outpostPresets,
        },
    }
    Service.catalogCache = cache
    local metrics = Service.catalogMetrics
    metrics.builds = metrics.builds + 1
    metrics.lastBuildMs = math.max(0, nowMs() - started)
    return cache
end

function Service.catalog()
    local current = Catalog.current or Catalog.load()
    if current == nil then return nil, false end
    local cache = Service.catalogCache
    if cache ~= nil and cache.source == current and cache.total == #(current.npcOrder or {}) then
        Service.catalogMetrics.cacheHits = Service.catalogMetrics.cacheHits + 1
        return cache, true
    end
    return Service.buildCatalog(current), false
end

function Service.noteCatalogRefusal(player, command, reason)
    if command ~= "debugCatalog" and command ~= "debugCatalogFaction" then return false end
    local refused = Service.catalogMetrics.refused
    local key = tostring(reason or "refused")
    refused[key] = (refused[key] or 0) + 1
    if key == "rate_limited" then return true end
    local logKey, now = playerKey(player) .. ":" .. key, nowMs()
    local last = Service.catalogLoggedAt[logKey]
    if last == nil or now < last or now - last >= Service.catalogLogGapMs then
        Service.catalogLoggedAt[logKey] = now
        print("[ALIFE-DEBUG] catalog refused user=" .. playerKey(player) .. " command=" .. command
            .. " reason=" .. key .. " count=" .. tostring(refused[key]))
    end
    return true
end

function Service.noteCatalogSent(player, what, pages, cached, started)
    local metrics = Service.catalogMetrics
    local elapsed = math.max(0, nowMs() - started)
    metrics.pagesSent = metrics.pagesSent + pages
    metrics.lastMs = elapsed
    if elapsed > metrics.maxMs then metrics.maxMs = elapsed end
    Service.noteDumpCost("admin_catalog", elapsed)
    if cached ~= true or elapsed >= Service.catalogSlowMs then
        print("[ALIFE-DEBUG] catalog user=" .. playerKey(player) .. " sent=" .. tostring(what)
            .. " pages=" .. tostring(pages) .. " cached=" .. tostring(cached == true)
            .. " buildMs=" .. tostring(metrics.lastBuildMs) .. " ms=" .. tostring(elapsed))
    end
    return elapsed
end

function Service.sendCatalogIndex(player, resultCommand)
    local started = nowMs()
    local metrics = Service.catalogMetrics
    metrics.requests = metrics.requests + 1
    local cache, cached = Service.catalog()
    if cache == nil then
        Service.noteCatalogRefusal(player, "debugCatalog", "catalog_unavailable")
        reply(player, resultCommand, { ok = false, reason = "catalog_unavailable" })
        return false
    end
    local pages = cache.factionPages
    local parts = #pages + 1
    for index = 1, #pages do
        reply(player, resultCommand, { ok = true, schema = 2, stamp = cache.stamp,
            part = index, parts = parts, factions = pages[index],
            factionCount = cache.factionCount, profileCount = cache.profileCount })
    end
    local meta = cache.meta
    reply(player, resultCommand, { ok = true, schema = 2, stamp = cache.stamp,
        part = parts, parts = parts, factions = {},
        factionCount = cache.factionCount, profileCount = cache.profileCount,
        animations = meta.animations, modes = meta.modes,
        encounters = meta.encounters, outpostPresets = meta.outpostPresets })
    Service.noteCatalogSent(player, "index", parts, cached, started)
    return true
end

function Service.sendCatalogFaction(player, resultCommand, args)
    local started = nowMs()
    local metrics = Service.catalogMetrics
    metrics.factionRequests = metrics.factionRequests + 1
    local factionId = type(args.factionId) == "string" and args.factionId or nil
    local cache, cached = Service.catalog()
    local rows = cache ~= nil and factionId ~= nil and cache.profileRows[factionId] or nil
    if rows == nil then
        local reason = "faction_not_found"
        if cache == nil then reason = "catalog_unavailable" end
        Service.noteCatalogRefusal(player, "debugCatalogFaction", reason)
        reply(player, resultCommand, { ok = false, reason = reason, factionId = factionId })
        return false
    end
    local pages = cache.profilePages[factionId]
    if pages == nil then
        pages = Service.catalogPages(rows, Service.catalogPageRows, Service.catalogPageBytes)
        cache.profilePages[factionId] = pages
    end
    for index = 1, #pages do
        reply(player, resultCommand, { ok = true, schema = 2, stamp = cache.stamp,
            factionId = factionId, part = index, parts = #pages,
            count = #rows, profiles = pages[index] })
    end
    Service.noteCatalogSent(player, "faction:" .. factionId, #pages, cached, started)
    return true
end

function Service.catalogQaLine()
    local m = Service.catalogMetrics
    local refused = {}
    for reason, count in pairs(m.refused) do refused[#refused + 1] = tostring(reason) .. ":" .. tostring(count) end
    table.sort(refused)
    return "[ALIFE-QA] AdminCatalog: requests=" .. tostring(m.requests)
        .. " factionRequests=" .. tostring(m.factionRequests) .. " builds=" .. tostring(m.builds)
        .. " cacheHits=" .. tostring(m.cacheHits) .. " pagesSent=" .. tostring(m.pagesSent)
        .. " lastMs=" .. tostring(m.lastMs) .. " maxMs=" .. tostring(m.maxMs)
        .. " lastBuildMs=" .. tostring(m.lastBuildMs) .. " refused={" .. table.concat(refused, ";") .. "}"
        .. Service.placementQa()
end

function Service.placementQa()
    local p = Service.placementMetrics
    if type(p) ~= "table" then return "" end
    return " placeRetries=" .. tostring(p.retries) .. " placedOnRetry=" .. tostring(p.placedOnRetry)
        .. " placeGaveUp=" .. tostring(p.gaveUp)
end

local function finiteCoordinate(value)
    local number = tonumber(value)
    return number ~= nil and number == number and number > -10000000 and number < 10000000
end

local function requestedOrigin(player, args)
    local fallback = playerPosition(player)
    if type(fallback) ~= "table" then return nil, nil, "player_position_unavailable" end
    local tileOrigin = {
        x = math.floor(tonumber(fallback.x) or 0),
        y = math.floor(tonumber(fallback.y) or 0),
        z = math.floor(tonumber(fallback.z) or 0),
    }
    local supplied = args.x ~= nil or args.y ~= nil or args.z ~= nil
    if not supplied then return tileOrigin, fallback end
    if not finiteCoordinate(args.x) or not finiteCoordinate(args.y)
            or not finiteCoordinate(args.z) then
        return nil, fallback, "spawn_origin_invalid"
    end
    local z = math.floor(tonumber(args.z))
    if z < -32 or z > 32 then return nil, fallback, "spawn_origin_invalid" end
    return {
        x = math.floor(tonumber(args.x)),
        y = math.floor(tonumber(args.y)),
        z = z,
    }, fallback
end

local function spawnRequestId(args)
    if type(args.requestId) == "string" then
        local supplied = string.sub(args.requestId, 1, 96)
        if supplied ~= "" then return supplied end
    end
    Service.requestSequence = Service.requestSequence + 1
    return "spawn-request:" .. tostring(nowMs()) .. ":"
        .. tostring(Service.requestSequence)
end

local function normalizeMode(args)
    local requested = tostring(args.mode or "")
    if modes[requested] ~= nil then return requested end
    if args.anchor == true then return "guard" end
    return "roam"
end

local function requestedProfile(args, mode)
    local profiles = ProjectALife.BehaviorProfiles
    local asked = type(args) == "table" and args.profile or nil
    if profiles ~= nil and type(asked) == "string"
            and profiles.get(asked) ~= nil then
        return string.lower(asked)
    end
    if type(mode) == "table" and type(mode.profile) == "string" then
        return mode.profile
    end
    return profiles ~= nil and profiles.defaultId or "seek_destroy"
end

local function authoredModules(profile)
    local result = { flee = "off" }
    local factionId = profile and profile.general and profile.general.faction
    local faction = factionId and Catalog.faction(factionId) or nil
    for id, value in pairs(faction and faction.memberModules or {}) do
        if value ~= "inherit" and value ~= "" then result[id] = value end
    end
    for id, value in pairs(profile and profile.moduleOverrides or {}) do
        if value ~= "inherit" and value ~= "" then result[id] = value end
    end
    return result
end

local function authoredConduct(profile)
    local value = profile and profile.general and profile.general.primaryBehavior
    value = string.lower(tostring(value or ""))
    if SPAWN_CONDUCTS[value] then return value end

    return nil
end

local function stagingPosition(origin, playerOrigin, distance)
    if distance <= 0 then return positionCopy(origin) end
    local dx, dy = origin.x - playerOrigin.x, origin.y - playerOrigin.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.1 then dx, dy, length = 1, 0, 1 end
    return {
        x = origin.x + dx / length * distance,
        y = origin.y + dy / length * distance,
        z = origin.z,
    }
end

function Service.appendSiteRows(rows, sites, cap, hours)
    if type(rows) ~= "table" or type(sites) ~= "table" then return rows end
    cap = tonumber(cap) or 128
    local director = ProjectALife.OutpostDirector
    for _, site in ipairs(sites) do
        if #rows >= cap then break end

        if site.state ~= "expired" and site.mapHidden ~= true then
            local squadCap
            if director ~= nil and type(director.squadCap) == "function" then
                pcall(function() squadCap = director.squadCap(site) end)
            end
            rows[#rows + 1] = {
                siteId = site.id,
                factionId = site.factionId,
                persistent = true,

                nextSquadHours = (site.state == "garrisoned" and tonumber(hours) ~= nil)
                    and math.max(0, (tonumber(site.nextSquadHour) or 0) - hours) or nil,
                squadCap = squadCap,
                squadsOut = #(type(site.squads) == "table" and site.squads or {}),
                x = math.floor(tonumber(site.x) or 0),
                y = math.floor(tonumber(site.y) or 0),
                members = type(site.garrison) == "table" and #site.garrison or 0,
                active = site.state == "garrisoned",
                outpost = true,
                label = tostring(site.presetId or "outpost"),
                task = tostring(site.state or "?"),
                activity = site.state == "garrisoned"
                    and (tostring(#(type(site.squads) == "table" and site.squads or {})) .. " squad(s) sent out")
                    or ("site is " .. tostring(site.state)),
            }
        end
    end
    return rows
end

function Service.offlineEta(squad, nodes, adjacency, tilesPerHour)
    if type(squad) ~= "table" or type(squad.route) ~= "table" or #squad.route == 0 then return nil end
    nodes = type(nodes) == "table" and nodes or {}
    adjacency = type(adjacency) == "table" and adjacency or {}
    local first = nodes[squad.route[1]]
    if first == nil then return nil end
    local dx = (tonumber(first.x) or 0) - (tonumber(squad.x) or 0)
    local dy = (tonumber(first.y) or 0) - (tonumber(squad.y) or 0)
    local remaining = math.sqrt(dx * dx + dy * dy)
    for index = 1, #squad.route - 1 do
        local a, b = squad.route[index], squad.route[index + 1]
        local len = adjacency[a] ~= nil and adjacency[a][b] or nil
        if len == nil then
            local na, nb = nodes[a], nodes[b]
            if na ~= nil and nb ~= nil then
                local ex, ey = na.x - nb.x, na.y - nb.y
                len = math.sqrt(ex * ex + ey * ey)
            else
                len = 0
            end
        end
        remaining = remaining + len
    end
    return remaining / math.max(1, tonumber(tilesPerHour) or 50)
end

function Service.offlineActivity(squad, nodes)
    if type(squad) ~= "table" then return nil end
    nodes = type(nodes) == "table" and nodes or {}
    if squad.state == "staging" then return "forming up nearby" end
    local task = type(squad.task) == "table" and squad.task or {}
    if type(task.activity) == "string" and task.activity ~= "" then return task.activity end
    if type(squad.route) == "table" and #squad.route > 0 then
        if squad.nightCamp == true then return "camping for the night" end
        local verb = "travelling"
        if task.kind == "withdraw" then verb = "fleeing"
        elseif task.kind == "scavenge" then verb = "heading out to scavenge"
        elseif task.kind == "reinforce" then verb = "marching to reinforce an outpost"
        elseif task.kind == "patrol" then verb = "patrolling"
        elseif task.kind == "return" then verb = "heading back to camp" end
        local nextNode = nodes[squad.route[1]]
        local from = squad.legFrom ~= nil and nodes[squad.legFrom] or nil

        local graph = ProjectALife.RoadGraph
        if graph ~= nil and type(graph.displayName) ~= "function" then graph = nil end
        local nextName = nextNode ~= nil and tostring(graph and graph.displayName(squad.route[1], nextNode) or nextNode.name) or nil
        local text = verb
        if from ~= nil and nextNode ~= nil then
            local fromName = tostring(graph and graph.displayName(squad.legFrom, from) or from.name)
            if fromName == nextName then return text .. " near " .. nextName end
            text = text .. " (" .. fromName .. " -> " .. nextName .. ")"
        elseif nextNode ~= nil then
            text = text .. " to " .. nextName
        end
        return text
    end
    if task.kind == "rest" then
        local home = squad.homeNodeId ~= nil and nodes[squad.homeNodeId] or nil
        if home ~= nil and squad.nodeId == squad.homeNodeId then
            return "camping at home in " .. tostring(home.name or squad.homeNodeId)
        end
        return "resting"
    end
    if task.kind == "scavenge" then return "scavenging" end
    if task.kind == "fortify" then return "securing a shelter" end
    if task.kind == "withdraw" then return "regrouping after a fight" end
    if task.kind == "return" then return "back at camp" end
    if task.kind == "travel" then return "settling in" end
    if task.kind == "reinforce" then return "reinforcing an outpost" end
    if task.kind == "patrol" then return "patrolling" end
    return "waiting for orders"
end

function Service.groupTask(memory)
    if type(memory) ~= "table" then return nil end
    if type(memory.outpostSquadId) == "string" then
        return "outpost squad" .. (type(memory.stance) == "string" and (" (" .. memory.stance .. ")") or "")
    end
    if type(memory.encounter) == "string" and string.sub(memory.encounter, 1, 8) == "outpost:" then
        return "garrison of " .. string.sub(memory.encounter, 9)
    end
    if type(memory.mode) == "string" then return memory.mode end
    if type(memory.mode) == "table" then return tostring(memory.mode.id or memory.mode.name or "?") end
    if type(memory.stance) == "string" then return memory.stance end
    if type(memory.encounter) == "string" then return memory.encounter end
    return nil
end

local activityWords = { combat = "fighting", warning = "warning someone off",
    moving = "travelling", idle = "idle", dead = "dead", fleeing = "fleeing", scavenging = "scavenging",
    resting = "resting", camping = "camping", hunting = "hunting", foraging = "foraging" }
function Service.activityText(activity, intent)
    local text = activityWords[tostring(activity)] or tostring(activity or "idle")
    if type(intent) == "string" and intent ~= "" then
        text = text .. " (" .. string.gsub(intent, "_", " ") .. ")"
    end
    return text
end

function Service.factionLabel(factionId)
    if type(factionId) ~= "string" or factionId == "" then return nil end
    local faction = Catalog.faction(factionId)
    local name = faction and faction.general and faction.general.name
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

function Service.squadLabel(factionId, name)
    if type(name) == "string" and name ~= "" then return name end
    return Service.factionLabel(factionId)
end

function Service.appendOfflineRows(rows, squads, nodes, cap, adjacency, tilesPerHour)
    if type(rows) ~= "table" or type(squads) ~= "table" then return rows end
    cap = tonumber(cap) or 128
    nodes = type(nodes) == "table" and nodes or {}

    local graph = ProjectALife.RoadGraph
    if graph ~= nil and (type(graph.displayName) ~= "function" or type(graph.displayLabel) ~= "function") then
        graph = nil
    end
    local live = {}
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.groupId ~= nil and row.offline ~= true then live[tostring(row.groupId)] = true end
    end
    for _, squad in ipairs(squads) do
        if #rows >= cap then break end
        if (squad.state == "offline" or squad.state == "staging") and live[tostring(squad.id)] ~= true then
            local task = type(squad.task) == "table" and squad.task or {}
            local destination = task.dest ~= nil and nodes[task.dest] or nil
            local home = squad.homeNodeId ~= nil and nodes[squad.homeNodeId] or nil
            rows[#rows + 1] = {
                x = math.floor(tonumber(squad.x) or 0),
                y = math.floor(tonumber(squad.y) or 0),
                members = type(squad.members) == "table" and #squad.members or 0,
                active = false,
                offline = true,
                groupId = tostring(squad.id),
                factionId = squad.factionId,
                persistent = true,
                label = Service.squadLabel(squad.factionId, squad.name)
                    or tostring(squad.id or "squad"),
                task = task.label ~= nil
                    and tostring(graph and graph.displayLabel(task.label, task.dest, destination) or task.label) or nil,
                dest = destination ~= nil
                    and tostring(graph and graph.displayName(task.dest, destination) or destination.name or task.dest) or nil,

                activity = Service.offlineActivity(squad, nodes),
                eta = Service.offlineEta(squad, nodes, adjacency, tilesPerHour),
                home = home ~= nil
                    and tostring(graph and graph.displayName(squad.homeNodeId, home) or home.name or squad.homeNodeId) or nil,
            }
        end
    end
    return rows
end

function Service.offlineByDistance(ledger, x, y)
    local squads, total = {}, 0
    if ledger == nil or type(ledger.eachLive) ~= "function" then return squads, 0 end
    x, y = tonumber(x), tonumber(y)
    local distances = {}
    ledger.eachLive(function(squad)
        if squad.state == "offline" or squad.state == "staging" then
            total = total + 1
            squads[total] = squad
            local d = math.huge
            if x ~= nil and y ~= nil then
                local dx, dy = (tonumber(squad.x) or 0) - x, (tonumber(squad.y) or 0) - y
                d = dx * dx + dy * dy
                if d ~= d then d = math.huge end
            end
            distances[squad] = d
        end
    end)
    if x ~= nil and y ~= nil and total > 1 then
        table.sort(squads, function(a, b)
            local da, db = distances[a], distances[b]
            if da ~= db then return da < db end
            return tostring(a.id) < tostring(b.id)
        end)
    end
    return squads, total
end

function Service.appendNearestOffline(payload, at)
    local squads = payload.squads
    payload.offlineTotal, payload.offlineShown = 0, 0
    local ledger, graph = ProjectALife.SquadLedger, ProjectALife.RoadGraph
    if ledger == nil or type(squads) ~= "table" then return payload end
    local offline = ProjectALife.OfflineDirector
    local pace = offline ~= nil and type(offline.settings) == "table"
        and offline.settings.travelTilesPerHour or 50
    local px, py = type(at) == "table" and at.x or nil, type(at) == "table" and at.y or nil
    local nearest, total = Service.offlineByDistance(ledger, px, py)
    local before = #squads
    Service.appendOfflineRows(squads, nearest,
        graph and graph.nodes or {}, 128,
        graph and graph.adjacency or {}, pace)
    payload.offlineTotal, payload.offlineShown = total, #squads - before
    return payload
end

function Service.blocOf(factionId)
    if type(factionId) ~= "string" or factionId == "" then return nil end
    local faction = Catalog.faction(factionId)
    if type(faction) ~= "table" then return nil end
    local rules = ProjectALife.FactionSpawnRules
    if rules == nil or type(rules.blocOf) ~= "function" then return nil end
    local bloc = rules.blocOf(faction)
    if type(bloc) ~= "string" or bloc == "" then return nil end
    return bloc
end

function Service.appendBlocs(payload)
    local rows = type(payload) == "table" and payload.squads or nil
    if type(rows) ~= "table" then return payload end
    local known = {}
    for _, row in ipairs(rows) do
        local id = row.factionId
        if type(id) == "string" and row.bloc == nil then
            local bloc = known[id]
            if bloc == nil then
                bloc = Service.blocOf(id) or false
                known[id] = bloc
            end
            if bloc ~= false then row.bloc = bloc end
        end
    end
    return payload
end

function Service.squadMapReply(squads, at)
    local payload = { command = "debugSquadMapResult", squads = squads }
    pcall(Service.appendNearestOffline, payload, at)
    local populate = ProjectALife.PopulateDirector
    if populate ~= nil and type(populate.mapPlaces) == "function" then
        pcall(function()
            Service.appendPlaceRows(squads, populate.mapPlaces(), 128)
        end)
    end
    pcall(Service.appendBlocs, payload)
    pcall(Service.appendCensus, payload)
    return payload
end

function Service.bodyWait(actor, at, now)
    if type(actor) ~= "table" or actor.lifecycle ~= "dormant" then return nil end
    local population = ProjectALife.Population
    local hold = population ~= nil and type(population.holdInfo) == "function"
        and population.holdInfo(actor.uid, now) or nil
    local row = { uid = actor.uid, reason = hold ~= nil and hold.why or "pending",
        ageS = hold ~= nil and hold.ageS or 0, retryS = hold ~= nil and hold.retryS or 0 }
    local position = actor.worldPosition
    if type(at) == "table" and type(position) == "table" then
        local coordinates = { position.x, position.y, at.x, at.y }
        for index = 1, 4 do
            local value = coordinates[index]
            if type(value) ~= "number" or value ~= value or value <= -math.huge or value >= math.huge then
                return row
            end
        end
        local dx, dy = position.x - at.x, position.y - at.y
        row.distance = math.floor(math.sqrt(dx * dx + dy * dy))
    end
    return row
end

function Service.appendBodyWaitLines(lines, player)
    local at, now, count = playerPosition(player), nowMs(), 0
    Registry.each(function(actor)
        local row = Service.bodyWait(actor, at, now)
        if row == nil then return end
        count = count + 1
        if count > 24 then return end
        lines[#lines + 1] = "[ALIFE-QA] BodyWait uid=" .. tostring(row.uid)
            .. " reason=" .. tostring(row.reason) .. " distance=" .. tostring(row.distance)
            .. " ageS=" .. tostring(row.ageS) .. " retryS=" .. tostring(row.retryS)
    end)
    if count > 24 then lines[#lines + 1] = "[ALIFE-QA] BodyWait omitted=" .. tostring(count - 24) end
end

function Service.appendCensus(payload)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusBrief) ~= "function" then return payload end
    local brief = census.censusBrief()
    if brief == nil then return payload end
    payload.census = { total = brief.total, living = brief.living, alive = brief.alive, dead = brief.dead,
        arrived = brief.arrived, room = brief.room }
    local byFaction = {}
    for _, row in ipairs(brief.factions) do byFaction[tostring(row.id)] = row end
    for _, row in ipairs(type(payload.squads) == "table" and payload.squads or {}) do
        local entry = row.factionId ~= nil and byFaction[tostring(row.factionId)] or nil
        if entry ~= nil then
            row.census = "alive " .. tostring(entry.alive) .. ", killed " .. tostring(entry.dead)
                .. ", arrivals " .. tostring(entry.arrived)
        end
    end
    return payload
end

function Service.appendPlaceRows(rows, places, cap)
    if type(rows) ~= "table" or type(places) ~= "table" then return rows end
    cap = tonumber(cap) or 128
    for _, place in ipairs(places) do
        if #rows >= cap then break end
        if type(place) == "table" and place.manned ~= true
                and tonumber(place.x) ~= nil and tonumber(place.y) ~= nil then
            rows[#rows + 1] = {
                x = math.floor(tonumber(place.x)),
                y = math.floor(tonumber(place.y)),
                members = 0,
                active = false,
                place = true,
                persistent = true,
                label = tostring(place.name or place.category or "place"),
                task = "planned place" .. (place.town ~= nil and (" in " .. tostring(place.town)) or ""),
                activity = Service.placeActivity(place),
            }
        end
    end
    return rows
end

Service.placeWhy = {
    too_close = "a player is inside the spawn keep-out",
    player_close = "a player is close and could see the residents appear",
    region_locked = "the region is closed",
    ["building_unloaded:place"] = "the building is outside the loaded area",
    ["building_unloaded:edge"] = "the building is at the edge of the loaded area",
    ["building_unloaded:window"] = "the rooms around the place are not loaded yet",
    ["building_unloaded:probe"] = "the building could not be read",
    building_unloaded = "the building is not loaded",
    player_hidden = "the player is hidden off-road, away from towns and quiet",
    in_player_sight = "the place is in a player's line of sight",
    player_below_ground = "the player is below ground",
    player_high_up = "the player is high up",
    floor_mismatch = "the place is on another floor than the player",
    census_exhausted = "the world census has nobody left to send",
    census_short = "the world census cannot fill the group",
    census_cleared = "its people died; the place stays empty for now",
    inside_player_base = "a player is inside the building or used it as a base in the last 12 hours",
    no_capacity = "the NPC limit is reached",
    pressure_quiet = "another group arrived within 240 tiles in the last day",
    pressure_pending = "another group within 240 tiles is still arriving",
    pressure_crowded = "too many groups are within 240 tiles",
    pressure_history_full = "too many recent arrivals are on record",
    region_cooldown = "the region is resting after recent arrivals",
    region_regrowing = "the region is recovering after deaths",
}
function Service.placeActivity(place)
    if type(place) ~= "table" or place.waiting == nil then return "manned when a player comes within reach" end
    local why = Service.placeWhy[tostring(place.waiting)] or tostring(place.waiting)
    local distance = tonumber(place.distance)
    return "waiting: " .. why .. (distance ~= nil and (" (" .. tostring(math.floor(distance)) .. " tiles)") or "")
end

Service.censusMargin = 600

function Service.censusBucket(x, y, regions)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    regions = regions or ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" then return "rural" end
    local distance, town = regions.distanceToTown({ x = x, y = y })
    if town ~= nil and distance ~= nil and distance <= Service.censusMargin then return town.id end
    return "rural"
end

function Service.actorXY(actor)
    if type(actor) ~= "table" then return nil end
    local binding = Watchdog ~= nil and type(Watchdog.bindings) == "table" and Watchdog.bindings[actor.uid] or nil
    local shell = binding ~= nil and binding.shell or nil
    if shell ~= nil and shell.getX ~= nil and shell.getY ~= nil then
        local okX, x = pcall(shell.getX, shell)
        local okY, y = pcall(shell.getY, shell)
        if okX and okY and tonumber(x) ~= nil and tonumber(y) ~= nil then return x, y end
    end
    local placed = type(actor.worldPosition) == "table" and actor.worldPosition or actor
    return tonumber(placed.x), tonumber(placed.y)
end

function Service.censusPlayers()
    local result = {}
    pcall(function()
        local players = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
        if players ~= nil and players:size() > 0 then
            for index = 0, players:size() - 1 do
                local player = players:get(index)
                if player ~= nil then result[#result + 1] = { x = player:getX(), y = player:getY() } end
            end
        elseif type(getSpecificPlayer) == "function" and getSpecificPlayer(0) ~= nil then
            local player = getSpecificPlayer(0)
            result[#result + 1] = { x = player:getX(), y = player:getY() }
        end
    end)
    return result
end

function Service.censusFactions(source)
    local catalog = source.catalog or Catalog
    local rules = source.rules or ProjectALife.FactionSpawnRules
    local rosters = source.rosters
    if rosters == nil then
        local director = ProjectALife.Director
        rosters = director ~= nil and director.rosters or {}
    end
    local eligible = {}
    if catalog == nil or type(catalog.faction) ~= "function" or type(rules) ~= "table" then return eligible end
    local hours = tonumber(source.hours)
    if hours == nil then
        hours = 0
        pcall(function() hours = getGameTime():getWorldAgeHours() end)
    end
    local hour = tonumber(source.hour)
    if hour == nil then
        hour = 12
        pcall(function() hour = getGameTime():getHour() end)
    end
    local ids = {}
    for factionId in pairs(rosters) do ids[#ids + 1] = tostring(factionId) end
    table.sort(ids)
    for _, factionId in ipairs(ids) do
        local roster = rosters[factionId]
        local ok, keep, faction = pcall(function()
            local found = catalog.faction(factionId)
            if found == nil or type(roster) ~= "table" or #roster == 0 then return false end
            local roaming = #rules.roamingEncounters(found.spawn) > 0
            return roaming and rules.available(found, hours / 24, hour) == true, found
        end)
        if ok and keep == true then eligible[#eligible + 1] = faction end
    end
    return eligible
end

function Service.townCensus(source)
    source = type(source) == "table" and source or {}
    local regions = source.regions or ProjectALife.TownRegions
    local graph = source.graph or ProjectALife.RoadGraph
    local locks = source.locks or ProjectALife.RegionLocks
    local spawnRegions = source.spawnRegions or ProjectALife.SpawnRegions
    local rows, byId = {}, {}
    local function row(id, label)
        local found = byId[id]
        if found == nil then
            found = { id = id, label = label or id, nodes = 0, open = 0, locked = 0, blind = 0,
                live = 0, offline = 0, offlineMen = 0, heading = 0, outposts = 0,
                places = 0, placesManned = 0, nearPlayer = false }
            byId[id] = found
            rows[#rows + 1] = found
        end
        return found
    end
    if regions ~= nil and type(regions.definitions) == "table" then
        for _, definition in ipairs(regions.definitions) do row(definition.id, definition.label) end
    end
    row("rural", "Countryside")

    local nodeBucket = {}
    if graph ~= nil and type(graph.towns) == "table" and type(graph.nodes) == "table" then
        for _, nodeId in ipairs(graph.towns) do
            local node = graph.nodes[nodeId]
            local key = node ~= nil and Service.censusBucket(node.x, node.y, regions) or nil
            if key ~= nil then
                nodeBucket[nodeId] = key
                local target = row(key)
                target.nodes = target.nodes + 1
                local locked = locks ~= nil and type(locks.locked) == "function"
                    and locks.locked(node.x, node.y) == true
                if locked then
                    target.locked = target.locked + 1
                elseif node.seeded == true then
                    target.blind = target.blind + 1
                else
                    target.open = target.open + 1
                    local gap = 0
                    if regions ~= nil and type(regions.distanceToTown) == "function" then
                        gap = regions.distanceToTown({ x = node.x, y = node.y }) or 0
                    end
                    if target.probe == nil or gap < target.probeGap then
                        target.probe, target.probeGap = node, gap
                    end
                end
            end
        end
    end
    local registry = source.registry or Registry
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(actor)
            if actor.lifecycle ~= "dead" then
                local x, y = Service.actorXY(actor)
                local key = Service.censusBucket(x, y, regions)
                if key ~= nil then row(key).live = row(key).live + 1 end
            end
        end)
    end

    local ledger = source.ledger or ProjectALife.SquadLedger
    local destinations = {}
    local function countSquad(squad)
        if squad.state == "offline" or squad.state == "staging" then
            local key = Service.censusBucket(squad.x, squad.y, regions)
            if key ~= nil then
                local target = row(key)
                target.offline = target.offline + 1
                target.offlineMen = target.offlineMen + (type(squad.members) == "table" and #squad.members or 0)
            end
            local task = type(squad.task) == "table" and squad.task or nil
            local dest = task ~= nil and task.dest or nil
            if dest ~= nil then destinations[dest] = (destinations[dest] or 0) + 1 end
            local heading = dest ~= nil and nodeBucket[dest] or nil
            if heading ~= nil then row(heading).heading = row(heading).heading + 1 end
        end
    end
    if type(source.squads) == "table" then
        for _, squad in ipairs(source.squads) do countSquad(squad) end
    elseif ledger ~= nil and type(ledger.eachLive) == "function" then
        ledger.eachLive(countSquad)
    elseif ledger ~= nil and type(ledger.list) == "function" then
        for _, squad in ipairs(ledger.list(true)) do countSquad(squad) end
    end
    local sites = source.sites
    if sites == nil then
        local outposts = ProjectALife.OutpostRegistry
        if outposts ~= nil and type(outposts.list) == "function" then sites = outposts.list() end
    end
    for _, site in ipairs(type(sites) == "table" and sites or {}) do
        if site.state ~= "expired" then
            local key = Service.censusBucket(site.x, site.y, regions)
            if key ~= nil then row(key).outposts = row(key).outposts + 1 end
        end
    end
    local places = source.places
    if places == nil then
        local populate = ProjectALife.PopulateDirector
        if populate ~= nil and type(populate.mapPlaces) == "function" then places = populate.mapPlaces() end
    end
    for _, place in ipairs(type(places) == "table" and places or {}) do
        local key = byId[tostring(place.town)] ~= nil and tostring(place.town)
            or Service.censusBucket(place.x, place.y, regions)
        if key ~= nil then
            local target = row(key)
            target.places = target.places + 1
            if place.manned == true then target.placesManned = target.placesManned + 1 end
        end
    end
    local players = source.players or Service.censusPlayers()
    local offline = ProjectALife.OfflineDirector
    local reach = tonumber(source.playerReach)
        or (offline ~= nil and type(offline.settings) == "table" and tonumber(offline.settings.foundPlayerDistance))
        or 140
    for _, target in ipairs(rows) do
        local box = regions ~= nil and type(regions.get) == "function" and regions.get(target.id) or nil
        if box ~= nil then
            for _, player in ipairs(players) do
                local px, py = tonumber(player.x), tonumber(player.y)
                if px ~= nil and py ~= nil then
                    local dx = math.max(box.minX - px, 0, px - box.maxX)
                    local dy = math.max(box.minY - py, 0, py - box.maxY)
                    if dx * dx + dy * dy <= reach * reach then target.nearPlayer = true end
                end
            end
        end
    end
    local eligible = Service.censusFactions(source)
    for _, target in ipairs(rows) do
        if target.probe ~= nil and spawnRegions ~= nil and type(spawnRegions.allows) == "function" then
            local point, count = { x = target.probe.x, y = target.probe.y, z = 0 }, 0
            for _, faction in ipairs(eligible) do
                local ok, allowed = pcall(spawnRegions.allows, point, faction.spawn)
                if ok and allowed == true then count = count + 1 end
            end
            target.factions = count
        end
    end

    local ranked = {}
    for nodeId, count in pairs(destinations) do
        local node = graph ~= nil and type(graph.nodes) == "table" and graph.nodes[nodeId] or nil
        ranked[#ranked + 1] = { id = tostring(nodeId), name = node ~= nil and node.name or nil, count = count }
    end
    table.sort(ranked, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.id < b.id end)
    return { rows = rows, byId = byId, eligible = #eligible, destinations = ranked }
end

function Service.townDestLine(census, limit)
    local parts = {}
    local dest = type(census.destinations) == "table" and census.destinations or {}
    for index = 1, math.min(#dest, limit or 6) do
        local entry = dest[index]
        parts[#parts + 1] = entry.id .. (entry.name ~= nil and ("(" .. tostring(entry.name) .. ")") or "")
            .. "=" .. entry.count
    end
    return "[ALIFE-QA] townDest " .. (#parts > 0 and table.concat(parts, " ") or "none")
end

function Service.censusClosed(row)
    if row.nodes == 0 then return "no_road_node" end
    if row.open == 0 then return row.locked > 0 and "region_locked" or "never_seen" end
    if row.factions == 0 then return "no_faction_spawns_here" end
    return "-"
end

function Service.townCensusLines(census)
    local lines, totals = {}, { populated = 0, open = 0, zeroFaction = 0, closed = 0, live = 0,
        offline = 0, men = 0, heading = 0, outposts = 0, places = 0, manned = 0 }
    for _, row in ipairs(census.rows) do
        if row.live + row.offline + row.outposts + row.places > 0 then totals.populated = totals.populated + 1 end
        local closed = Service.censusClosed(row)
        if closed == "-" then totals.open = totals.open + 1
        elseif closed == "no_faction_spawns_here" then totals.zeroFaction = totals.zeroFaction + 1
        else totals.closed = totals.closed + 1 end
        totals.live, totals.offline = totals.live + row.live, totals.offline + row.offline
        totals.men, totals.heading = totals.men + row.offlineMen, totals.heading + row.heading
        totals.outposts, totals.places = totals.outposts + row.outposts, totals.places + row.places
        totals.manned = totals.manned + row.placesManned
    end
    lines[1] = "[ALIFE-QA] towns total=" .. #census.rows .. " populated=" .. totals.populated
        .. " open=" .. totals.open .. " zeroFaction=" .. totals.zeroFaction .. " closed=" .. totals.closed
        .. " live=" .. totals.live .. " offline=" .. totals.offline .. "/" .. totals.men
        .. " heading=" .. totals.heading .. " outposts=" .. totals.outposts
        .. " places=" .. totals.places .. "/" .. totals.manned .. " founders=" .. tostring(census.eligible)
    for _, row in ipairs(census.rows) do
        lines[#lines + 1] = "[ALIFE-QA] town " .. tostring(row.label) .. " id=" .. tostring(row.id)
            .. " nodes=" .. row.nodes .. " open=" .. row.open .. " locked=" .. row.locked .. " blind=" .. row.blind
            .. " factions=" .. tostring(row.factions or "?")
            .. " live=" .. row.live .. " offline=" .. row.offline .. "/" .. row.offlineMen
            .. " heading=" .. row.heading .. " outposts=" .. row.outposts
            .. " places=" .. row.places .. "/" .. row.placesManned
            .. " nearPlayer=" .. (row.nearPlayer and "yes" or "no")
            .. " closed=" .. Service.censusClosed(row)
    end
    lines[#lines + 1] = Service.townDestLine(census, 12)
    return lines
end

function Service.townCountsLine(census)
    local parts = {}
    for _, row in ipairs(census.rows) do
        if row.live + row.offline + row.places + row.outposts > 0 then
            parts[#parts + 1] = tostring(row.id) .. "=l" .. row.live .. "/o" .. row.offline
                .. "/p" .. row.places .. "/s" .. row.outposts
        end
    end
    return "[ALIFE-QA] townCounts " .. (#parts > 0 and table.concat(parts, " ") or "none")
end

function Service.positionText(x, y, z)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return "?" end
    return string.format("%.1f,%.1f,%d", x, y, math.floor(tonumber(z) or 0))
end

function Service.snapshotText(shell, now)
    local box = ProjectALife.BlackBox
    if box == nil or type(box.snapshotFields) ~= "function" then return "" end
    local ok, text = pcall(box.snapshotFields, shell, now)
    return ok and tostring(text) or "snapshot=?"
end

function Service.peopleMetDay()
    if type(getGameTime) ~= "function" then return 0 end
    local time = getGameTime()
    if time == nil or type(time.getWorldAgeHours) ~= "function" then return 0 end
    local hours = tonumber(time:getWorldAgeHours())
    if hours == nil or hours ~= hours or math.abs(hours) == math.huge then return 0 end
    return math.max(0, math.floor(hours / 24))
end

function Service.peopleMetState(day)
    if Service.peopleMetWorld ~= Registry.worldState then
        Service.peopleMet, Service.peopleMetDirty = nil, false
        Service.peopleMetFlushedAtMs, Service.peopleMetFlushedDay = nil, nil
        Service.peopleMetWorld = Registry.worldState
    end
    local state = Service.peopleMet
    if state == nil then
        local saved = Registry.getWorldValue("presetPeopleMet")
        state = { day = day, count = 0, seen = {}, history = {}, capped = false }
        if type(saved) == "table" and saved.v == 1 and tonumber(saved.day) == day then
            for key, value in pairs(type(saved.seen) == "table" and saved.seen or {}) do
                if type(key) == "string" and #key <= 160 and value == true and state.count < 500 then
                    state.seen[key], state.count = true, state.count + 1
                end
            end
            state.capped = state.count >= 500
        elseif type(saved) == "table" and saved.v == 1 and tonumber(saved.day) ~= nil then
            state.day = math.floor(tonumber(saved.day))
            state.count = math.max(0, math.min(500, tonumber(saved.count) or 0))
            state.capped = saved.capped == true
        end
        if type(saved) == "table" and type(saved.history) == "table" then
            for i = 1, math.min(2, #saved.history) do
                local row = saved.history[i]
                if type(row) == "table" and tonumber(row.day) ~= nil then
                    state.history[#state.history + 1] = { day = math.floor(tonumber(row.day)),
                        count = math.max(0, math.min(500, tonumber(row.count) or 0)), capped = row.capped == true }
                end
            end
        end
        Service.peopleMet = state
    end
    if state.day ~= day then
        local history = {}
        for past = math.max(0, day - 2), day - 1 do
            local count, capped = 0, false
            if past == state.day then count, capped = state.count, state.capped end
            for _, row in ipairs(state.history) do
                if row.day == past then count, capped = row.count, row.capped end
            end
            history[#history + 1] = { day = past, count = count, capped = capped }
        end
        state.day, state.count, state.seen, state.capped, state.history = day, 0, {}, false, history
        Service.peopleMetDirty = true
    end
    return state
end

function Service.peopleMetPosition(actor, binding, delegated)
    local p
    if delegated then
        p = actor.worldPosition
    else
        local shell = binding.shell
        if shell == nil or type(shell.getX) ~= "function" or type(shell.getY) ~= "function"
                or type(shell.getZ) ~= "function" then return nil end
        local ok, x, y, z = pcall(function() return shell:getX(), shell:getY(), shell:getZ() end)
        if not ok then return nil end
        p = { x = x, y = y, z = z }
    end
    if type(p) ~= "table" then return nil end
    for _, key in ipairs({ "x", "y", "z" }) do
        local value = tonumber(p[key])
        if value == nil or value ~= value or math.abs(value) == math.huge then return nil end
    end
    return tonumber(p.x), tonumber(p.y), math.floor(tonumber(p.z))
end

function Service.collectPeopleMet(now)
    now = tonumber(now) or 0
    if Service.peopleMetAtMs ~= nil and now >= Service.peopleMetAtMs and now - Service.peopleMetAtMs < 2000 then return end
    Service.peopleMetAtMs = now
    local state = Service.peopleMetState(Service.peopleMetDay())
    local points = {}
    for _, player in ipairs(ProjectALife.FeatureGate.players()) do
        if type(player.getX) == "function" and type(player.getY) == "function" and type(player.getZ) == "function" then
            local ok, x, y, z = pcall(function()
                if type(player.isDead) == "function" and player:isDead() then return nil end
                return tonumber(player:getX()), tonumber(player:getY()), tonumber(player:getZ())
            end)
            if ok and x ~= nil and y ~= nil and z ~= nil then points[#points + 1] = { x = x, y = y, z = math.floor(z) } end
        end
    end
    if #points == 0 then return end
    local executor = ProjectALife.Executor
    local delegated = type(executor) == "table" and type(executor.serverDelegates) == "function" and executor.serverDelegates()
    Registry.each(function(actor)
        if state.count >= 500 then state.capped = true; return true end
        local binding = type(Watchdog.bindings) == "table" and Watchdog.bindings[actor.uid] or nil
        if actor.lifecycle ~= "active" or binding == nil or binding.generation ~= actor.generation then return end
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local key = memory.squadId or memory.groupId or memory.outpostSquadId or ("solo:" .. actor.uid)
        if memory.outpostId ~= nil and memory.outpostSquadId == nil then key = "site:" .. tostring(memory.outpostId) end
        key = tostring(key)
        if state.seen[key] then return end
        local x, y, z = Service.peopleMetPosition(actor, binding, delegated)
        if x == nil then return end
        for _, p in ipairs(points) do
            local dx, dy = p.x - x, p.y - y
            if p.z == z and dx * dx + dy * dy <= 900 then
                state.seen[key], state.count = true, state.count + 1
                state.capped, Service.peopleMetDirty = state.count >= 500, true
                return
            end
        end
    end)
end

Service.peopleMetFlushGapMs = 120000

function Service.flushPeopleMet()
    Service.peopleMetState(Service.peopleMetDay())
    if Service.peopleMet == nil or Service.peopleMetDirty ~= true then return true end
    local state, now = Service.peopleMet, nowMs()
    local last = Service.peopleMetFlushedAtMs
    if last ~= nil and state.day == Service.peopleMetFlushedDay and now >= last
            and now - last < Service.peopleMetFlushGapMs then return true end
    local ok = Registry.setWorldValue("presetPeopleMet", { v = 1, day = state.day, count = state.count,
        seen = state.seen, history = state.history, capped = state.capped })
    if ok then
        Service.peopleMetDirty, Service.peopleMetFlushedAtMs, Service.peopleMetFlushedDay = false, now, state.day
    end
    return ok
end

function Service.peopleMetLine()
    local state = Service.peopleMetState(Service.peopleMetDay())
    local first, days, counts = math.max(0, state.day - 2), {}, {}
    for day = first, first + 2 do
        local count = day <= state.day and "0" or "-"
        if day == state.day then count = tostring(state.count) .. (state.capped and "+" or "") end
        for _, row in ipairs(state.history) do
            if row.day == day then count = tostring(row.count) .. (row.capped and "+" or "") end
        end
        days[#days + 1], counts[#counts + 1] = tostring(day), count
    end
    local settings = type(ProjectALife.Settings) == "table" and ProjectALife.Settings.read(nil, true) or {}
    return "[ALIFE-QA] Presets: world=" .. tostring(settings.presetWorld or 3)
        .. " difficulty=" .. tostring(settings.presetDifficulty or 2) .. " days=" .. table.concat(days, ",")
        .. " peopleMet(day1..3)=" .. table.concat(counts, ",") .. " capped=" .. (state.capped and "1" or "0")
        .. " sampled=2s/same-floor"
end

function Service.moduleRuleLines(lines)
    local rules = ProjectALife.ModuleRules
    if rules == nil or type(rules.qaLine) ~= "function" then return end
    lines[#lines + 1] = "[ALIFE-QA] " .. rules.qaLine()
    local crew = ProjectALife.MeleeCrew
    if crew ~= nil and type(crew.footworkLine) == "function" then lines[#lines + 1] = "[ALIFE-QA] " .. crew.footworkLine() end
    if crew ~= nil and type(crew.facingLine) == "function" then lines[#lines + 1] = "[ALIFE-QA] " .. crew.facingLine() end
    local registry, watchdog = ProjectALife.ModuleRegistry, ProjectALife.Watchdog
    if registry == nil or watchdog == nil or type(watchdog.order) ~= "table" then return end
    local shown = 0
    for index = 1, #watchdog.order do
        if shown >= 12 then break end
        local actor = ProjectALife.ActorRegistry.peek(watchdog.order[index])
        if type(actor) == "table" and actor.lifecycle == "active" then
            shown = shown + 1
            local off = {}
            for id in pairs(registry.modules) do
                if rules.optIn(id) and registry.override(actor, id) ~= "on" then off[#off + 1] = id end
            end
            table.sort(off)
            local held = rules.suppressed(actor)
            lines[#lines + 1] = "[ALIFE-QA] ModuleRules actor uid=" .. tostring(actor.uid) .. " faction=" .. tostring(actor.factionId)
                .. " suppressed=" .. (#held > 0 and table.concat(held, ",") or "none")
                .. " inheritOff=" .. (#off > 0 and table.concat(off, ",") or "none")
        end
    end
end

function Service.debugWardrobe(args)
    local seasons, hydrator = ProjectALife.Seasons, ProjectALife.ProfileHydrator
    if seasons == nil or hydrator == nil or type(hydrator.wardrobeLine) ~= "function" then
        return { ok = false, reason = "wardrobe_missing" }
    end
    args = type(args) == "table" and args or {}
    if args.clear == true then
        seasons.setWardrobeOverride(nil)
    elseif tonumber(args.tempC) ~= nil then
        seasons.setWardrobeOverride(math.max(-40, math.min(55, tonumber(args.tempC))),
            { wet = args.wet, wind = args.wind, ground = args.ground, night = args.night })
    end
    if args.now == true then
        for _, row in pairs(hydrator.wardrobe.worn) do row.due, row.since = -math.huge, -math.huge end
    end
    local line = hydrator.wardrobeLine()
    print(line)
    return { ok = true, line = line, override = seasons.wardrobeOverride ~= nil }
end

function Service.qaExtraLines(lines)
    lines[#lines + 1] = Service.peopleMetLine()
    pcall(Service.moduleRuleLines, lines)
    local speechModule = ProjectALife.Speech
    if speechModule ~= nil and type(speechModule.textQaLine) == "function" then lines[#lines + 1] = speechModule.textQaLine() end
    if speechModule ~= nil and type(speechModule.orderQaLine) == "function" then lines[#lines + 1] = speechModule.orderQaLine() end
    local bubbles = ProjectALife.SpeechBubbles
    if bubbles ~= nil and type(bubbles.qaLine) == "function" then lines[#lines + 1] = bubbles.qaLine() end
    local npcChat = ProjectALife.NpcChat
    if npcChat ~= nil and type(npcChat.qaLine) == "function" then lines[#lines + 1] = npcChat.qaLine() end
    local talkPrompt = ProjectALife.TalkPrompt
    if talkPrompt ~= nil and type(talkPrompt.qaLine) == "function" then lines[#lines + 1] = talkPrompt.qaLine() end
    local visitModule = ProjectALife.SafehouseVisit
    if visitModule ~= nil and type(visitModule.wantQaLine) == "function" then lines[#lines + 1] = visitModule.wantQaLine() end
    if visitModule ~= nil and type(visitModule.themedQaLine) == "function" then lines[#lines + 1] = visitModule.themedQaLine() end
    local runtime = ProjectALife.Runtime
    local m = runtime ~= nil and type(runtime.metrics) == "table" and runtime.metrics or nil
    if m ~= nil then
        lines[#lines + 1] = "[ALIFE-QA] Runtime: ticks=" .. tostring(m.ticks or 0)
            .. " overruns=" .. tostring(m.overruns or 0) .. " worstTickMs=" .. tostring(m.maximumTickMs or 0)
            .. " lastTickMs=" .. tostring(m.lastTickMs or 0) .. " faults=" .. tostring(m.faults or 0)
            .. " lastFault=" .. tostring(m.lastFault or "-")
    end
    local guard = ProjectALife.OrphanGuard
    if type(guard) == "table" then
        lines[#lines + 1] = "[ALIFE-QA] OrphanGuard: scans=" .. tostring(guard.scans or 0)
            .. " removed=" .. tostring(guard.removed or 0) .. " disarmed=" .. tostring(guard.disarmed or 0)
            .. " ghosts=" .. tostring(guard.ghosts or 0) .. " cursor=" .. tostring(guard.cursor or 0)
        local spawnService = ProjectALife.SpawnService
        local spawnMetrics = spawnService ~= nil and type(spawnService.metrics) == "table" and spawnService.metrics or {}
        local population = ProjectALife.Population
        local populationMetrics = population ~= nil and type(population.metrics) == "table" and population.metrics or {}
        lines[#lines + 1] = "[ALIFE-QA] ReloadGuard: orphansRemoved=" .. tostring(guard.orphansRemoved or 0)
            .. " reloadReadopt=" .. tostring(guard.reloadReadopt or 0)
            .. " reloadZombiesCleared=" .. tostring(spawnMetrics.reloadZombiesCleared or 0)
            .. " reloadDeferred=" .. tostring(guard.reloadDeferred or 0)
            .. " reloadExpired=" .. tostring(guard.reloadExpired or 0)
            .. " ghostSquads=" .. tostring(guard.ghostSquads or 0)
            .. " bodylessSquads=" .. tostring(guard.bodylessSquads or 0)
            .. " bodylessInReach=" .. tostring(guard.bodylessInReach or 0)
            .. " bodylessFar=" .. tostring(guard.bodylessFar or 0)
            .. " widenedHydrate=" .. tostring(populationMetrics.widenedHydrate or 0)
            .. " stuckForced=" .. tostring(populationMetrics.stuckForced or 0)
            .. " stuckCapacity=" .. tostring(populationMetrics.stuckCapacity or 0)
            .. " heldReleased=" .. tostring(populationMetrics.heldReleased or 0)
            .. " heldForCapacity=" .. tostring(populationMetrics.heldForCapacity or 0)
            .. " heldForKept=" .. tostring(populationMetrics.heldForKept or 0)
            .. " heldForNoSquare=" .. tostring(populationMetrics.heldForNoSquare or 0)
            .. " heldForHandoff=" .. tostring(populationMetrics.heldForHandoff or 0)
    end
    local box = ProjectALife.BlackBox
    if box ~= nil and type(box.metrics) == "table" then
        local detect = type(box.metrics.detect) == "table" and box.metrics.detect or {}
        local kinds = type(box.metrics.freezeKinds) == "table" and box.metrics.freezeKinds or {}
        lines[#lines + 1] = "[ALIFE-QA] verdict recorder=" .. tostring(box.enabled == true)
            .. " freezes=" .. tostring(box.metrics.freezes or 0)
            .. " travHung=" .. tostring(kinds["trav-hung"] or 0)
            .. " edgeStuck=" .. tostring(detect["edge-stuck"] or 0)
            .. " homing=" .. tostring(detect.homing or 0)
            .. " wrongWay=" .. tostring(detect["wrong-way"] or 0)
            .. " backWalk=" .. tostring(detect["back-walk"] or 0)
            .. " strafeMismatch=" .. tostring(detect["strafe-mismatch"] or 0)
            .. " dupUid=" .. tostring(detect["dup-uid"] or 0)
            .. " rebased=" .. tostring(box.metrics.rebased or 0)
            .. " dumps=" .. tostring(box.metrics.dumps or 0)
            .. " suppressed=" .. tostring(box.metrics.suppressed or 0)
        local plus = ProjectALife.BlackBoxPlus
        if plus ~= nil and type(plus.verdictText) == "function" then
            lines[#lines] = lines[#lines] .. plus.verdictText()
        end
    end
    lines[#lines + 1] = Service.catalogQaLine()
    local searchOwner = ProjectALife.Population
    if searchOwner ~= nil and type(searchOwner.qaLine) == "function" then
        lines[#lines + 1] = searchOwner.qaLine()
    end
    local adminConsole = ProjectALife.AdminConsoleService
    if adminConsole ~= nil and type(adminConsole.qaLine) == "function" then
        lines[#lines + 1] = adminConsole.qaLine()
    end
    if ProjectALife.SafehouseDirector ~= nil and type(ProjectALife.SafehouseDirector.visitRateLine) == "function" then
        lines[#lines + 1] = ProjectALife.SafehouseDirector.visitRateLine()
    end
    pcall(function()
        local drops = ProjectALife.DeathDrops
        if drops ~= nil and type(drops.qaLine) == "function" then lines[#lines + 1] = drops.qaLine() end
        local worn = drops ~= nil and type(drops.wearQaLine) == "function" and drops.wearQaLine() or nil
        if worn ~= nil then lines[#lines + 1] = worn end
    end)
    pcall(function()
        local siteLights = ProjectALife.OutpostLights
        if siteLights ~= nil and type(siteLights.qaLine) == "function" then lines[#lines + 1] = siteLights.qaLine() end
    end)
    pcall(function()
        local horde = ProjectALife.HordeRelations
        if horde ~= nil and type(horde.targetLine) == "function" then lines[#lines + 1] = horde.targetLine() end
    end)
    pcall(function()
        local policy = ProjectALife.ZombieRetarget
        if policy ~= nil and type(policy.qaLine) == "function" then lines[#lines + 1] = policy.qaLine() end
        local control = ProjectALife.FireControl
        if control ~= nil and type(control.qaLine) == "function" then lines[#lines + 1] = control.qaLine() end
    end)
    pcall(function()
        local injury = ProjectALife.Injury
        if injury ~= nil and type(injury.qaLine) == "function" then lines[#lines + 1] = injury.qaLine() end
    end)
    pcall(function()
        local armor = ProjectALife.Armor
        if armor ~= nil and type(armor.qaLine) == "function" then lines[#lines + 1] = armor.qaLine() end
    end)
    pcall(function()
        local dressing = ProjectALife.ProfileHydrator
        if dressing ~= nil and type(dressing.wardrobeLine) == "function" then lines[#lines + 1] = dressing.wardrobeLine() end
    end)
    pcall(function()
        local populate = ProjectALife.PopulateDirector
        if populate ~= nil and type(populate.summary) == "function" then
            lines[#lines + 1] = "[ALIFE-QA] " .. tostring(populate.summary())
        end
    end)
    pcall(function()
        local census = Service.townCensus()
        lines[#lines + 1] = Service.townCensusLines(census)[1]
        lines[#lines + 1] = Service.townCountsLine(census)
        lines[#lines + 1] = Service.townDestLine(census, 6)
    end)
    pcall(Service.censusLines, lines)
    pcall(function()
        for _, name in ipairs({ "GunDiscipline", "RegionLedger", "Hibernation", "GroupPlan", "SpawnFairness", "Funnel", "Interop", "CompatRegistry", "Cleanup", "DoorPolicy", "GuestLife", "VisitorEvents" }) do
            local module = ProjectALife[name]
            if type(module) == "table" and type(module.qaLine) == "function" then lines[#lines + 1] = module.qaLine() end
        end
    end)
    return lines
end

function Service.censusLines(lines)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusLines) ~= "function" then return lines end
    for _, line in ipairs(census.censusLines(nil, 32)) do lines[#lines + 1] = line end
    return lines
end

function Service.noteDumpCost(name, elapsed)
    local runtime = ProjectALife.Runtime
    if tonumber(elapsed) == nil or elapsed <= 16 or runtime == nil
            or type(runtime.noteDetail) ~= "function" then return false end
    return pcall(runtime.noteDetail, name, elapsed)
end

local function spawn(player, args, allowAdminFlags, visitStamp)
    local requestId = spawnRequestId(args)
    local mode = normalizeMode(args)
    if Service.groups[requestId] ~= nil then
        return { ok = false, reason = "spawn_request_duplicate", requestId = requestId,
            accepted = 0, failed = 0, mode = mode }
    end
    if Service.groupOutcomes[requestId] ~= nil then
        Service.groupOutcomes[requestId] = nil
        for index = #Service.groupOutcomeOrder, 1, -1 do
            if Service.groupOutcomeOrder[index] == requestId then
                table.remove(Service.groupOutcomeOrder, index)
            end
        end
    end
    if not runtimeReady() then
        return { ok = false, reason = "runtime_not_started", requestId = requestId,
            accepted = 0, failed = 0, mode = mode }
    end
    local hasProfileIds = type(args.profileIds) == "table" and #args.profileIds > 0
    local hasProfileId = type(args.profileId) == "string" and args.profileId ~= ""
    if not hasProfileIds and not hasProfileId then
        local picked, pickError = Service.hostileProfileIds(
            args.count, nowMs(), args.factionId, allowAdminFlags == true
                or Service.wantedFaction(args.factionId) ~= nil)
        if picked == nil then
            return { ok = false, reason = pickError or "no_hostile_profiles",
                requestId = requestId, accepted = 0, failed = 0, mode = mode }
        end
        args = clone(args)
        args.profileIds = picked
    end
    local profiles = {}
    if type(args.profileIds) == "table" then
        for _, profileId in ipairs(args.profileIds) do
            if #profiles >= 8 then break end
            local candidate = type(profileId) == "string" and Catalog.npc(profileId) or nil
            if candidate == nil or candidate.general == nil
                    or Catalog.faction(candidate.general.faction) == nil then

                local detail = "unknown"
                if type(profileId) ~= "string" then detail = "not_a_string:" .. type(profileId)
                elseif candidate == nil then detail = "no_such_profile"
                else
                    local homeId = candidate.general and candidate.general.faction
                    local faction = homeId and Catalog.faction(homeId) or nil
                    if faction == nil then detail = "faction_missing:" .. tostring(homeId)
                    elseif faction.spawn == nil then detail = "faction_has_no_spawn:" .. tostring(homeId)
                    else detail = "faction_is_friendly:" .. tostring(homeId) end
                end
                return { ok = false,
                    reason = "profile_invalid:" .. tostring(profileId) .. ":" .. detail,
                    requestId = requestId, accepted = 0, failed = 0, mode = mode }
            end
            profiles[#profiles + 1] = candidate
        end
    end
    local profile = #profiles > 0 and profiles[1]
        or (type(args.profileId) == "string" and Catalog.npc(args.profileId) or nil)
    if profile == nil or profile.general == nil or Catalog.faction(profile.general.faction) == nil then
        return { ok = false, reason = "profile_invalid", requestId = requestId,
            accepted = 0, failed = 0, mode = mode }
    end
    if #profiles == 0 then profiles[1] = profile end
    local origin, playerOrigin, originError = requestedOrigin(player, args)
    if origin == nil then
        return { ok = false, reason = originError, requestId = requestId,
            accepted = 0, failed = 0, mode = mode }
    end
    local count = #profiles > 1 and #profiles
        or math.max(1, math.min(8, math.floor(tonumber(args.count) or 1)))
    local radius = math.max(6, math.min(80, math.floor(tonumber(args.radius) or 24)))
    local distance = math.max(0, math.min(80, math.floor(tonumber(args.distance) or 0)))
    local separation = math.max(1, math.min(8, math.floor(tonumber(args.separation) or 2)))
    local animation = Animations.supports(args.animation) and args.animation or "normal"
    if #Service.queue >= Service.maximumQueued then
        return { ok = false, reason = "spawn_queue_full", requestId = requestId,
            accepted = 0, failed = count, mode = mode }
    end

    local definition
    if args.encounterId ~= nil then
        definition = encounterDefinition(args.encounterId)
    end
    if definition == nil and mode == "camp" and ProjectALife.OutpostPresets ~= nil then
        definition = ProjectALife.OutpostPresets.get("forest_camp")
    end
    local descriptor = modes[mode] or modes.roam

    local keepOut = args.directed == true and type(args.outpostId) ~= "string"
    local stance = args.stance or (definition and definition.stance) or descriptor.stance
    local roles = type(args.roles) == "table" and args.roles
        or (definition and definition.roles)
    local heading = tonumber(args.heading)
    local schedule = type(args.schedule) == "table" and args.schedule
        or (definition and definition.schedule)
    local awareness = tonumber(args.awareness)
        or tonumber(definition and definition.awareness)
    local roleAwareness = type(args.roleAwareness) == "table" and args.roleAwareness
        or (definition and definition.roleAwareness)
    local scene = type(args.scene) == "string" and args.scene
        or (definition and definition.scene) or descriptor.scene
    local atomicGroup = scene ~= nil or args.atomicGroup == true
    local scenePlan
    if atomicGroup then

        local remaining = Service.maximumQueued - #Service.queue
        if remaining < count then
            return { ok = false, reason = "spawn_queue_capacity", requestId = requestId,
                accepted = 0, failed = count, mode = mode }
        end
    end
    if scene ~= nil then
        local key = tostring(args.encounterId or mode) .. ":"
            .. tostring(math.floor(origin.x)) .. ":" .. tostring(math.floor(origin.y))
        local kit = ProjectALife.SceneKit
        if kit == nil or type(kit.build) ~= "function" then
            return { ok = false, reason = "scene_kit_unavailable", requestId = requestId,
                accepted = 0, failed = count, mode = mode }
        end

        if scene == "blockade" and keepOut and allowAdminFlags ~= true then
            local fairness = ProjectALife.SpawnFairness
            local why = fairness ~= nil and type(fairness.checkpointRefusal) == "function"
                and fairness.checkpointRefusal(origin) or nil
            if why ~= nil then
                return { ok = false, reason = why, requestId = requestId,
                    accepted = 0, failed = count, mode = mode }
            end
        end
        local sceneOptions = {
            allowProtected = descriptor.allowProtected == true and not keepOut,
            adminPlaced = not keepOut or nil,
            drivingKeepOut = args.directed == true,

            playerKeepOut = Service.keepOutFor({ directed = args.directed,
                outpostId = type(args.outpostId) == "string" and args.outpostId or nil,
                playerKeepOut = args.playerKeepOut }),
        }
        local sceneContext = SpawnPolicy.context(sceneOptions)
        local built, sceneReason, plan = kit.build(scene, origin, heading, key, {

            squareAllowed = function(position)
                local allowed = SpawnPolicy.check(position, sceneOptions, sceneContext)
                return allowed == true
            end,
        })
        if not built then
            return { ok = false, reason = sceneReason or "scene_build_failed",
                requestId = requestId, accepted = 0, failed = count, mode = mode }
        end
        scenePlan = type(plan) == "table" and plan or nil
        if scenePlan ~= nil and scenePlan.created == false then
            return { ok = false, reason = sceneReason or "scene_already_placed",
                requestId = requestId, accepted = 0, failed = count, mode = mode }
        end
        if scenePlan ~= nil and type(scenePlan.origin) == "table" then
            origin = positionCopy(scenePlan.origin)
        end
    end
    local stage = stagingPosition(origin, playerOrigin, distance)
    local adminFlags = allowAdminFlags == true
        and normalizeAdminFlags(args, origin) or nil
    Service.sequence = Service.sequence + 1
    local groupId = "alife-admin-group:" .. tostring(nowMs()) .. ":"
        .. tostring(Service.sequence)
    local accepted, rejected, queued = 0, 0, {}
    local timestamp = nowMs()
    local hostileOverride = hostility(args.hostileOverride)
    local authoredStance = spawnStance(args.playerStance)
    local weaponCondition = conditionRung(args.weaponCondition)
    local clothingCondition = conditionRung(args.clothingCondition)

    local weaponChance = type(args.weaponChance) == "string"
        and args.weaponChance ~= "" and args.weaponChance or nil
    local arrival = arrivalMode(args.arrival)
    for index = 1, count do
        local jobProfile = profiles[((index - 1) % #profiles) + 1]

        local requestedConduct
        if type(args.conducts) == "table" then
            local candidate = args.conducts[index]
            if type(candidate) == "string" and SPAWN_CONDUCTS[candidate] then
                requestedConduct = candidate
            end
        end
        local offset = offsets[index]

        local planned = (type(args.slots) == "table" and args.slots[index])
            or (scenePlan and type(scenePlan.slots) == "table"
                and scenePlan.slots[index]) or nil
        local requested = planned and positionCopy(planned) or {
            x = stage.x + offset[1] * separation + 0.5,
            y = stage.y + offset[2] * separation + 0.5,
            z = origin.z,
        }
        if #Service.queue >= Service.maximumQueued then
            rejected = rejected + 1
        else
            Service.sequence = Service.sequence + 1
            local operationId = "admin:" .. tostring(timestamp) .. ":"
                .. tostring(Service.sequence)
            local job = {
                operationId = operationId,

                profile = jobProfile,
                conduct = requestedConduct,
                encounterId = args.encounterId,
                encounterActivity = definition ~= nil and definition.activityStart == true and definition.activity or nil,
                encounterPersistent = args.encounterPersistent == true,

                stance = stance,
                garrisonBounds = type(args.garrisonBounds) == "table" and clone(args.garrisonBounds) or nil,
                stanceRoles = roles,

                stanceFaces = type(args.faces) == "table" and args.faces or nil,

                carefulRadii = type(args.careful) == "table" and args.careful or nil,

                scripted = type(args.scripted) == "table" and clone(args.scripted) or nil,

                holdPost = args.holdPost == true or nil,
                stanceRoute = args.route,

                scavengeArea = type(args.scavengeArea) == "table"
                    and clone(args.scavengeArea) or nil,
                stanceHeading = heading,
                behaviorProfile = requestedProfile(args, modes[mode]),
                requestId = requestId,

                natural = args.origin == "director" or nil,
                dormant = args.dormant == true or nil,
                visit = type(visitStamp) == "table" and clone(visitStamp) or nil,
                person = (type(visitStamp) == "table" and type(args.person) == "table") and clone(args.person) or nil,
                exactSquare = (type(visitStamp) == "table" and args.exactSquare == true) or nil,

                directed = args.directed == true or nil,
                startGroup = args.startGroup == true or nil,
                requester = player,
                requesterName = playerKey(player),

                targetUsername = type(args.targetUsername) == "string" and args.targetUsername or nil,
                jobIndex = index,

                readyAtMs = nowMs() + math.max(0, math.min(30000,
                    tonumber(args.spawnDelayMs) or Service.arrivalDelayMs(arrival))),
                requestedCount = count,
                profileId = jobProfile.id,
                factionId = jobProfile.general.faction,
                requested = requested,

                strictRequested = (args.garrisonBounds ~= nil and planned ~= nil)
                    or (type(visitStamp) == "table" and args.exactSquare == true),
                origin = positionCopy(origin),
                stage = positionCopy(stage),
                mode = mode,
                groupId = groupId,
                groupWarfare = args.groupWarfare == true,
                radius = radius,
                distance = distance,
                separation = separation,
                animation = animation,
                admin = adminFlags,

                supportPolicy = type(args.supportPolicy) == "string" and args.supportPolicy or nil,
                supportRole = type(args.supportRole) == "string" and args.supportRole or nil,
                supportForGroupId = type(args.supportForGroupId) == "string" and args.supportForGroupId or nil,
                supportType = type(args.supportType) == "string" and args.supportType or nil,
                supportHeli = type(args.supportHeli) == "string" and args.supportHeli or nil,
                supportSize = tonumber(args.supportSize),
                supportMaxCalls = tonumber(args.supportMaxCalls),
                supportCooldownHours = tonumber(args.supportCooldownHours),
                objectiveX = tonumber(args.objectiveX), objectiveY = tonumber(args.objectiveY),

                hostileOverride = hostileOverride,

                spawnStance = authoredStance,

                weaponChance = weaponChance,
                weaponCondition = weaponCondition,
                clothingCondition = clothingCondition,

                outpostId = type(args.outpostId) == "string" and args.outpostId or nil,
                outpostSquadId = type(args.outpostSquadId) == "string" and args.outpostSquadId or nil,

                playerKeepOut = tonumber(args.playerKeepOut),
                hidden = args.hidden == true or nil,

                awareness = awareness,
                roleAwareness = roleAwareness,
                schedule = schedule,

                moduleOverrides = (function()
                    if type(args.moduleOverrides) ~= "table" then return nil end
                    local clean, any = {}, false
                    for id, value in pairs(args.moduleOverrides) do
                        if type(id) == "string" and (value == "on" or value == "off") then
                            clean[id], any = value, true
                        end
                    end
                    return any and clean or nil
                end)(),
            }
            Service.queue[#Service.queue + 1] = job
            queued[#queued + 1] = job
            accepted = accepted + 1
        end
    end
    for _, job in ipairs(queued) do
        job.acceptedCount = accepted
        job.rejectedCount = rejected
    end
    if accepted > 0 then
        Service.groups[requestId] = {
            requestId = requestId,
            encounterId = type(args.encounterId) == "string" and args.encounterId or nil,
            requester = player,
            profileId = profile.id,
            mode = mode,
            groupId = groupId,
            origin = positionCopy(origin),
            requested = count,
            accepted = accepted,
            rejected = rejected,
            started = 0,
            completed = 0,
            active = 0,
            failed = 0,
            actorUids = {},
            allActorUids = {},
            atomic = atomicGroup,
            sceneKey = scenePlan and scenePlan.key or nil,
            sceneCreated = scenePlan and scenePlan.created == true or false,
        }
    end

    if accepted > 0 and arrival ~= "foot" then
        pcall(Service.announceArrival, arrival, origin,
            { x = tonumber(args.objectiveX), y = tonumber(args.objectiveY) })
    end

    if accepted > 0 and args.encounterId == nil then
        pcall(function()
            local log = ProjectALife.EncounterLog
            if log == nil then return end
            local descriptor = modes[mode] or {}
            log.record({
                id = mode,
                label = descriptor.label or mode,
                stance = args.stance,
            }, origin, accepted, "admin", groupId)
        end)
    end

    if accepted > 0 and args.encounterId == "car_crash"
            and not (type(requestId) == "string" and string.sub(requestId, 1, 5) == "meta:") then
        pcall(function()
            local meta = ProjectALife.MetaDirector
            if meta ~= nil and type(meta.announceCrash) == "function" then
                meta.announceCrash(origin.x, origin.y, origin.z)
            end
        end)
    end
    Telemetry.emit(args.origin == "director" and "director_spawn" or "admin_spawn", {
        requestId = requestId, profileId = profile.id, groupId = groupId,
        mode = mode, accepted = accepted, failed = rejected,
        distance = distance, separation = separation, radius = radius,
    })
    return {
        ok = accepted > 0,
        reason = rejected > 0 and "partial_failure" or "accepted_pending",
        accepted = accepted,
        failed = rejected,
        animation = animation,
        requestId = requestId,
        profileId = profile.id,
        groupId = groupId,
        mode = mode,
        radius = radius,
        distance = distance,
        separation = separation,
        origin = positionCopy(origin),
        scene = scene,
        stance = stance,
        plan = scenePlan,
    }
end

function Service.keepOutFor(job)
    if type(job) ~= "table" then return 0 end
    local named = tonumber(job.playerKeepOut)
    if named ~= nil then return math.max(0, named) end
    if job.directed ~= true then return 0 end
    if job.outpostId ~= nil then return tonumber(SpawnPolicy.postKeepOut) or 12 end
    return tonumber(SpawnPolicy.playerKeepOut) or 40
end

function Service.postDiscipline(memory, job)
    if type(memory) ~= "table" or (memory.garrisonPost == nil and memory.holdPost ~= true) then return false end
    if type(job) == "table" and type(job.moduleOverrides) == "table" and job.moduleOverrides.stance ~= nil then
        return false
    end
    memory.moduleOverrides = type(memory.moduleOverrides) == "table" and memory.moduleOverrides or {}
    memory.moduleOverrides.stance = "on"
    return true
end

function Service.attachPerson(memory, job)
    if type(job.person) ~= "table" then return nil end
    local visitors = ProjectALife.VisitorDirector
    if visitors == nil or type(visitors.instantiate) ~= "function" then return false, "visitor_director_missing" end
    local person, names = visitors.instantiate(job.person, job.jobIndex, { seed = job.jobIndex })
    if person == nil then return false, names end
    memory.person = person
    if type(names) == "table" then memory.personFirst, memory.personLast, memory.personName = names.first, names.last, names.name end
    return true
end

local function processJob(job)
    local profile = job.profile or Catalog.npc(job.profileId)
    if profile == nil or profile.id ~= job.profileId
            or profile.general == nil or profile.general.faction ~= job.factionId then
        return false, "profile_snapshot_invalid"
    end
    local mode = modes[job.mode] or modes.roam

    local keepOut = job.directed == true and job.outpostId == nil
    local options = {
        allowProtected = mode.allowProtected == true and not keepOut,
        adminPlaced = not keepOut or nil,

        searchRadius = math.max(8, job.separation * 2, tonumber(job.searchRadius) or 0),

        playerKeepOut = Service.keepOutFor(job),
        drivingKeepOut = job.directed == true,
        startGroup = job.startGroup,
    }
    if job.admin ~= nil then options.fairness = false end
    if job.outpostId ~= nil and job.outpostSquadId == nil then options.stationed = true end
    if job.hidden == true then
        options.stationed, options.occluded, options.validator = true, true, SpawnPolicy.hidden
    end
    if job.exactSquare == true then
        local exact = SpawnPolicy.exactOptions()
        options.allowProtected, options.playerKeepOut, options.drivingKeepOut = exact.allowProtected, exact.playerKeepOut, exact.drivingKeepOut
    end
    local worldPosition, policyError
    if job.dormant == true then
        worldPosition = { x = job.requested.x, y = job.requested.y, z = job.requested.z }
    elseif job.strictRequested == true then
        local allowed, reason, normalized = SpawnPolicy.check(job.requested, options)
        worldPosition, policyError = allowed and normalized or nil, reason
    else
        worldPosition, policyError = SpawnPolicy.find(job.requested, options)
    end
    if worldPosition == nil then
        job.placementRefused = policyError or "spawn_square_unavailable"
        return false, job.placementRefused
    end
    local memory = {
        encounter = mode.encounter,

        behaviorProfile = job.behaviorProfile
            or mode.profile
            or (ProjectALife.BehaviorProfiles
                and ProjectALife.BehaviorProfiles.defaultId)
            or "seek_destroy",
        debugSpawn = (job.natural ~= true and job.directed ~= true) or nil,
        natural = job.natural == true or nil,
        startGroup = job.startGroup,
        visit = type(job.visit) == "table" and clone(job.visit) or nil,
        adminMode = job.mode,
        behavior = job.mode,

        conduct = job.conduct
            or authoredConduct(profile)
            or ((job.jobIndex == 1 and (job.acceptedCount or 0) >= 3)
                and "leader" or nil),
        moduleOverrides = authoredModules(profile),

        encounter = job.encounterPersistent and job.encounterId or nil,
        encounterKind = job.encounterId,
        activityId = job.encounterActivity,
        persistent = (job.encounterPersistent == true
            or (type(job.admin) == "table" and job.admin.persistent == true)) or nil,

        sessionOnly = job.outpostSquadId ~= nil,
        admin = type(job.admin) == "table" and job.admin or nil,
        groupId = job.groupId,
        debugGroupWarfare = job.groupWarfare == true,

        stance = job.stance,
        garrisonPost = job.garrisonBounds ~= nil and positionCopy(worldPosition) or nil,
        garrisonBounds = job.garrisonBounds,
        garrisonRest = job.garrisonBounds ~= nil
            and job.jobIndex > math.min(4, math.max(1, job.requestedCount - 1)) or nil,
        stanceAnchor = job.stance ~= nil and positionCopy(job.origin) or nil,
        stanceHeading = job.stanceHeading,
        stanceRole = type(job.stanceRoles) == "table"
            and job.stanceRoles[job.jobIndex] or nil,
        carefulRadii = type(job.carefulRadii) == "table" and job.carefulRadii or nil,

        scripted = (ProjectALife.ScriptedEncounter ~= nil
            and ProjectALife.ScriptedEncounter.clean(job.scripted)) or nil,
        holdPost = job.holdPost == true or nil,
        stanceFace = type(job.stanceFaces) == "table" and type(job.stanceFaces[job.jobIndex]) == "table"
            and { x = tonumber(job.stanceFaces[job.jobIndex].x), y = tonumber(job.stanceFaces[job.jobIndex].y) } or nil,
        stanceRoute = job.stanceRoute,
        stanceRouteIndex = job.stanceRoute ~= nil and 1 or nil,

        scavengeArea = type(job.scavengeArea) == "table" and job.scavengeArea or nil,

        nightvision = (ProjectALife.Settings and ProjectALife.Settings.current
            and ProjectALife.Settings.current.nightvision == true) or nil,
        flashlight = not (ProjectALife.Settings and ProjectALife.Settings.current
            and ProjectALife.Settings.current.nightvision == true) or nil,

        outpostId = job.outpostId,
        outpostSquadId = job.outpostSquadId,
        hostileOverride = job.hostileOverride,
        spawnStance = job.spawnStance,
        weaponChance = job.weaponChance,
        weaponCondition = job.weaponCondition,
        clothingCondition = job.clothingCondition,
        support = (job.supportPolicy ~= nil or job.supportType ~= nil or job.supportHeli ~= nil) and {
            policy = job.supportPolicy, type = job.supportType, heli = job.supportHeli,
            size = job.supportSize, maxCalls = job.supportMaxCalls,
            cooldownHours = job.supportCooldownHours } or nil,
        role = job.supportRole,
        supportForGroupId = job.supportForGroupId,
        objective = job.objectiveX ~= nil and { x = job.objectiveX, y = job.objectiveY,
            z = 0, untilMs = nowMs() + 90000 } or nil,

        stanceSchedule = type(job.schedule) == "table" and job.schedule or nil,

        stanceAwareness = (function()
            local role = type(job.stanceRoles) == "table"
                and job.stanceRoles[job.jobIndex] or nil
            local byRole = type(job.roleAwareness) == "table" and role ~= nil
                and tonumber(job.roleAwareness[role]) or nil
            return byRole or tonumber(job.awareness)
        end)(),
        groupIndex = job.jobIndex,
        groupSize = job.acceptedCount,
        groupRole = job.jobIndex == 1 and "leader" or "member",
        spawnOrigin = positionCopy(job.origin),
        spawnStage = positionCopy(job.stage),
        patrolRadius = job.radius,
        spawnDistance = job.distance,
        spawnSeparation = job.separation,
    }

    if type(job.moduleOverrides) == "table" then
        for id, value in pairs(job.moduleOverrides) do
            memory.moduleOverrides[id] = value
        end
    end
    Service.postDiscipline(memory, job)
    local personOk, personWhy = Service.attachPerson(memory, job)
    if personOk == false then return false, "person_unavailable:" .. tostring(personWhy) end
    if mode.home then memory.home = positionCopy(job.origin) end
    if job.mode == "manhunt" or job.mode == "assault" or job.mode == "full_raid" then
        memory.targetUsername = job.targetUsername
            or (job.supportRole ~= "backup" and job.requesterName or nil)
    end
    local actor, createError = Registry.create({
        operationId = job.operationId,
        fingerprint = job.operationId,
        profileId = profile.id,
        factionId = profile.general.faction,
        worldPosition = worldPosition,
        activity = "idle",
        intent = mode.intent,
        memory = memory,
    })
    if actor == nil then return false, createError end
    if job.dormant == true then return true, "dormant_created", actor.uid, nil end
    local request, requestError = SpawnService.request(
        actor.uid, job.operationId .. ":spawn", job.operationId .. ":spawn", 2500)
    if request == nil then
        local current = Registry.read(actor.uid)
        if current and current.lifecycle == "dormant" then
            Registry.remove(current.uid, current.revision, "admin_spawn_rejected")
        end
        return false, requestError or "spawn_request_rejected", actor.uid
    end
    Animations.apply(request.shell, job.animation, true)
    return true, "spawn_started", actor.uid, request.operationId
end

local function jobPayload(job, successful, completed, reason, actorUid, spawnOperationId)
    return {
        ok = successful,
        completed = completed,
        status = completed and (successful and "active" or "failed") or "spawning",
        reason = reason,
        requestId = job.requestId,
        operationId = job.operationId,
        spawnOperationId = spawnOperationId,
        actorUid = actorUid,
        profileId = job.profileId,
        mode = job.mode,
        groupId = job.groupId,
        groupIndex = job.jobIndex,
        groupSize = job.acceptedCount,
        jobIndex = job.jobIndex,
        requested = job.requestedCount,
        accepted = job.acceptedCount,
        rejected = job.rejectedCount,
    }
end

function Service.noteGroupRefusal(group, reason)
    if type(group) ~= "table" then return false end
    reason = tostring(reason or "unknown")
    if group.firstReason == nil then group.firstReason = reason end
    group.reasons = type(group.reasons) == "table" and group.reasons or {}
    group.reasons[reason] = (group.reasons[reason] or 0) + 1
    return true
end

function Service.groupReason(group)
    if type(group) ~= "table" then return nil end
    if group.firstReason ~= nil then return group.firstReason end
    if (tonumber(group.rejected) or 0) > 0 then return "queue_full" end
    return nil
end

local function rollbackGroup(group)
    local removed = 0
    for _, uid in ipairs(group.allActorUids or {}) do
        local actor = Registry.read(uid)
        if actor ~= nil and actor.lifecycle == "active" then
            pcall(SpawnService.dehydrate, uid, "scene_atomic_rollback")
            actor = Registry.read(uid)
        end
        if actor ~= nil and actor.lifecycle ~= "active" then
            local ok = Registry.remove(actor.uid, actor.revision,
                "scene_atomic_rollback")
            if ok then removed = removed + 1 end
        end
    end
    if group.sceneCreated and group.sceneKey ~= nil then
        local kit = ProjectALife.SceneKit
        if kit ~= nil and type(kit.remove) == "function" then
            pcall(kit.remove, group.sceneKey)
        end
    end
    group.actorUids = {}
    group.active = 0
    group.rolledBack = true
    group.rolledBackActors = removed
end

function Service.tallyGroup(group, outcome)
    if type(group.encounterId) ~= "string" then return false end
    if (tonumber(group.active) or 0) > 0 then Service.tallyEncounter(group.encounterId, nil) end
    local any = false
    for reason, count in pairs(type(group.reasons) == "table" and group.reasons or {}) do
        Service.tallyEncounter(group.encounterId, reason, count)
        any = true
    end
    if not any and (tonumber(group.active) or 0) == 0 then
        Service.tallyEncounter(group.encounterId, outcome.reason or "no_member_settled")
    end
    return true
end

local function finishGroup(group)
    if group == nil or group.completed < group.accepted then return false end
    local successful = group.active == group.accepted and group.failed == 0
        and group.rejected == 0
    if not successful and group.atomic then rollbackGroup(group) end
    local outcome = {
        ok = successful,
        partial = group.active > 0 and not successful,
        rolledBack = group.rolledBack == true,
        rolledBackActors = group.rolledBackActors or 0,
        completed = true,
        requestId = group.requestId,
        profileId = group.profileId,
        mode = group.mode,
        groupId = group.groupId,
        origin = group.origin,
        requested = group.requested,
        accepted = group.accepted,
        rejected = group.rejected,
        started = group.started,
        completedCount = group.completed,
        active = group.active,
        failed = group.failed,
        actorUids = group.actorUids,

        reason = Service.groupReason(group),
        reasons = group.reasons,
        encounterId = group.encounterId,
    }
    Service.tallyGroup(group, outcome)
    safeReply(group.requester, "debugSpawnGroupResult", outcome, group)
    Telemetry.emit("admin_spawn_group_complete", {
        requestId = group.requestId,
        groupId = group.groupId,
        mode = group.mode,
        active = group.active,
        failed = group.failed,
        rejected = group.rejected,
    })
    Service.groupOutcomes[group.requestId] = outcome
    Service.groupOutcomeOrder[#Service.groupOutcomeOrder + 1] = group.requestId
    while #Service.groupOutcomeOrder > Service.maximumGroupOutcomes do
        local expired = table.remove(Service.groupOutcomeOrder, 1)
        Service.groupOutcomes[expired] = nil
    end
    Service.groups[group.requestId] = nil
    for _, listener in ipairs(group.listeners or {}) do
        pcall(listener, outcome)
    end
    return true
end

local function settleJob(job, successful, reason, actorUid, spawnOperationId)
    if job.completed then return false end
    job.completed = true
    local group = Service.groups[job.requestId]
    if group ~= nil then
        group.completed = group.completed + 1
        if actorUid ~= nil then
            group.allActorUids[#group.allActorUids + 1] = actorUid
        end
        if successful then
            group.active = group.active + 1
            group.actorUids[#group.actorUids + 1] = actorUid
        else
            group.failed = group.failed + 1
            Service.noteGroupRefusal(group, reason)
        end
    end
    safeReply(job.requester, "debugSpawnJobResult",
        jobPayload(job, successful, true, reason, actorUid, spawnOperationId), job)
    finishGroup(group)
    return true
end

local function startJob(job, actorUid, spawnOperationId)
    if job.placeAttempts ~= nil then
        Service.placementMetrics.placedOnRetry = Service.placementMetrics.placedOnRetry + 1
    end
    job.actorUid = actorUid
    job.spawnOperationId = spawnOperationId
    local group = Service.groups[job.requestId]
    if group ~= nil then group.started = group.started + 1 end
    Service.pendingJobs[spawnOperationId] = job
    Service.pendingOrder[#Service.pendingOrder + 1] = spawnOperationId
    safeReply(job.requester, "debugSpawnJobResult",
        jobPayload(job, true, false, "spawn_started", actorUid, spawnOperationId), job)
end

local function pollSettled(maximum)
    local inspected, settled, index = 0, 0, 1
    while inspected < maximum and index <= #Service.pendingOrder do
        local operationId = Service.pendingOrder[index]
        local job = Service.pendingJobs[operationId]
        local request = SpawnService.settled[operationId]
        if job == nil then
            table.remove(Service.pendingOrder, index)
        elseif request ~= nil then
            Service.pendingJobs[operationId] = nil
            table.remove(Service.pendingOrder, index)
            local successful = request.status == "active"
            settleJob(job, successful,
                successful and "spawn_active" or (request.reason or request.status),
                request.uid or job.actorUid, operationId)
            settled = settled + 1
        else
            index = index + 1
        end
        inspected = inspected + 1
    end
    return settled
end

function Service.waitsOutView(job, reason)
    if reason ~= "in_player_view" and reason ~= "too_close_to_player" then return false end
    if job.outpostId == nil or job.outpostSquadId ~= nil then return false end
    job.viewDeadlineMs = job.viewDeadlineMs or (nowMs() + 120000)
    return nowMs() < job.viewDeadlineMs
end

Service.placementRetryMs = 200
Service.placementWindowMs = 2000
Service.placementRadii = { 12, 16, 20, 24 }
Service.placementMetrics = { retries = 0, placedOnRetry = 0, gaveUp = 0 }
function Service.retriesPlacement(job)
    local refused = job.placementRefused
    job.placementRefused = nil
    if refused == nil or job.directed == true or job.strictRequested == true then return false end
    local now = nowMs()
    job.placementReasons = job.placementReasons or {}
    job.placementReasons[refused] = (job.placementReasons[refused] or 0) + 1

    job.placeFirstAtMs = job.placeFirstAtMs or math.min(now, tonumber(job.readyAtMs) or now)
    if now - job.placeFirstAtMs >= Service.placementWindowMs then
        Service.placementMetrics.gaveUp = Service.placementMetrics.gaveUp + 1
        return false
    end
    job.placeAttempts = (job.placeAttempts or 0) + 1
    job.searchRadius = Service.placementRadii[math.min(job.placeAttempts, #Service.placementRadii)]
    job.readyAtMs = now + Service.placementRetryMs
    Service.placementMetrics.retries = Service.placementMetrics.retries + 1
    return true
end

function Service.outpostGone(job)
    if job.viewDeadlineMs == nil then return false end
    local registry = ProjectALife.OutpostRegistry
    if registry == nil or type(registry.read) ~= "function" then return false end
    local site = registry.read(job.outpostId)
    return site == nil or site.state == "expired"
end

function Service.aiRead(object, method)
    local kind = type(object)
    if kind ~= "table" and kind ~= "userdata" then return nil end
    local ok, callback = pcall(function() return object[method] end)
    if not ok or type(callback) ~= "function" then return nil end
    local called, value = pcall(callback, object)
    if called then return value end
    return nil
end

function Service.aiTargetKey(target)
    local data = Service.aiRead(target, "getModData")
    if type(data) == "table" and data.ProjectALifeUID ~= nil then
        return tostring(data.ProjectALifeUID)
    end
    local id = Service.aiRead(target, "getOnlineID")
    if id ~= nil then return "online:" .. tostring(id) end
    return target == nil and "none" or "unknown"
end

Service.aiTraceHeartbeatMs = 30000

function Service.aiTrace(now)
    if ProjectALife.AdminConsoleService ~= nil and ProjectALife.AdminConsoleService.logging.aiTrace == false then return end
    now = tonumber(now) or 0
    if now - (Service.aiTraceAtMs or -math.huge) < 5000 then return end
    local enabled = false
    local diagnostics = type(Service.diagnosticsBy) == "table" and Service.diagnosticsBy or {}
    for _, value in pairs(diagnostics) do
        if value == true then enabled = true; break end
    end
    if not enabled or type(Registry.order) ~= "table" or #Registry.order == 0
            or type(Registry.records) ~= "table" or type(Watchdog.bindings) ~= "table" then return end
    Service.aiTraceAtMs = now
    local decisions = ProjectALife.DecisionLoop
    local perception = ProjectALife.Perception
    local movement = ProjectALife.Movement
    local fence = ProjectALife.AIFence
    local simulation = ProjectALife.ShellSimulation
    local printed = 0
    for _ = 1, math.min(#Registry.order, 64) do
        Service.aiTraceCursor = ((Service.aiTraceCursor or 0) % #Registry.order) + 1
        local uid = Registry.order[Service.aiTraceCursor]
        local actor = Registry.records[uid]
        local binding = Watchdog.bindings[uid]
        local state = decisions ~= nil and type(decisions.states) == "table" and decisions.states[uid] or nil
        if type(actor) == "table" and actor.lifecycle == "active" and type(binding) == "table"
                and binding.generation == actor.generation and binding.shell ~= nil
                and type(state) == "table" then
            local shell = binding.shell
            local action = type(state.action) == "table" and state.action or {}
            local target = action.target or state.threat
            local owner = Service.aiRead(shell, "getOwnerPlayer")
            local remote = Service.aiRead(shell, "isRemoteZombie")
            local data = Service.aiRead(shell, "getModData")
            if type(data) ~= "table" then data = {} end
            local sx, sy = tonumber(Service.aiRead(shell, "getX")), tonumber(Service.aiRead(shell, "getY"))
            local tx, ty = tonumber(Service.aiRead(target, "getX")), tonumber(Service.aiRead(target, "getY"))
            if type(target) == "table" then tx, ty = tx or tonumber(target.x), ty or tonumber(target.y) end
            local distance = "unknown"
            if sx ~= nil and sy ~= nil and tx ~= nil and ty ~= nil then
                distance = string.format("%.2f", math.sqrt((tx - sx)^2 + (ty - sy)^2))
            end
            local contact = perception ~= nil and type(perception.engagements) == "table"
                and perception.engagements[uid] or nil
            local contactAt = type(contact) == "table" and tonumber(contact.atMs) or nil
            local seenAge = "unknown"
            if type(contact) == "table" and target ~= nil and contact.target == target
                    and contactAt ~= nil and now >= contactAt then
                seenAge = tostring(now - contactAt)
            end
            local driven, phase, health = "unknown", "unknown", "unknown"
            if fence ~= nil and type(fence.drivesBody) == "function" then
                local ok, value = pcall(fence.drivesBody, shell)
                if ok then driven = tostring(value == true) end
            end
            if movement ~= nil and type(movement.pathPhase) == "function" then
                local ok, value = pcall(movement.pathPhase, shell)
                if ok and value ~= nil then phase = tostring(value) end
            end
            if simulation ~= nil and type(simulation.trueHealth) == "function"
                    and type(shell.getHealth) == "function" then
                local ok, value = pcall(simulation.trueHealth, shell)
                if ok and value ~= nil then health = tostring(value) end
            end
            local signature = Service.aiTargetKey(target) .. "|" .. tostring(state.kind) .. ":" .. tostring(state.intent)
                .. "|" .. tostring(action.status) .. "|" .. phase .. "|" .. tostring(data.ProjectALifeHeldBump)
            Service.aiTraceLast = type(Service.aiTraceLast) == "table" and Service.aiTraceLast or {}
            local last = Service.aiTraceLast[uid]
            if type(last) ~= "table" or last.signature ~= signature or now - last.atMs >= Service.aiTraceHeartbeatMs then
                Service.aiTraceLast[uid] = { signature = signature, atMs = now }
                local seenMs = tonumber(seenAge)
                print("[ALIFE-AI] uid=" .. tostring(uid)
                    .. " owner=" .. tostring(Service.aiRead(owner, "getOnlineID"))
                    .. " remote=" .. tostring(remote) .. " driven=" .. driven
                    .. " target=" .. Service.aiTargetKey(target)
                    .. " decisionThreat=" .. Service.aiTargetKey(state.threat)
                    .. " seen=" .. tostring(seenMs ~= nil and seenMs <= 2000) .. " seenAgeMs=" .. seenAge .. " dist=" .. distance
                    .. " decision=" .. tostring(state.kind) .. ":" .. tostring(state.intent)
                    .. " action=" .. tostring(action.status) .. " result=" .. tostring(action.result)
                    .. " pathPhase=" .. phase .. " loaded=" .. tostring(Service.aiRead(shell, "getCurrentSquare") ~= nil)
                    .. " hp=" .. health .. " endurance=" .. tostring(data.ProjectALifeEndurance)
                    .. " suppressTracking=" .. tostring(data.ProjectALifeSuppressTracking)
                    .. " suppressUntilMs=" .. tostring(data.ProjectALifeSuppressUntilMs) .. " nowMs=" .. tostring(now)
                    .. " heldBump=" .. tostring(data.ProjectALifeHeldBump))
                printed = printed + 1
                if printed >= 16 then break end
            end
        end
    end
end

function Service.tick(budget)
    Service.aiTrace(nowMs())
    Service.collectPeopleMet(nowMs())
    local maximum = math.max(1, math.min(4, math.floor(tonumber(budget) or 1)))
    local processed = pollSettled(math.max(8, maximum * 4))
    local started = 0
    local inspected, queued = 0, #Service.queue
    while started < maximum and #Service.queue > 0 and inspected < queued do
        local job = table.remove(Service.queue, 1)
        inspected = inspected + 1
        if nowMs() < (job.readyAtMs or 0) then
            Service.queue[#Service.queue + 1] = job
        else
        local callOk, spawned, reason, actorUid, spawnOperationId = true, false, "outpost_gone"
        if not Service.outpostGone(job) then
            callOk, spawned, reason, actorUid, spawnOperationId = pcall(processJob, job)
        end
        if callOk and spawned == false and reason == "moving_vehicle_approach" then
            job.readyAtMs = nowMs() + 1000
            Service.queue[#Service.queue + 1] = job
        elseif callOk and spawned == false and Service.waitsOutView(job, reason) then
            job.readyAtMs = nowMs() + 1000
            Service.queue[#Service.queue + 1] = job
        elseif callOk and spawned == false and Service.retriesPlacement(job) then
            Service.queue[#Service.queue + 1] = job
        else
        local successful = callOk and spawned == true
            and (type(spawnOperationId) == "string" or job.dormant == true)
        local resultReason = successful and (reason or "spawn_started")
            or (callOk and reason or tostring(spawned))
        Telemetry.emit(successful and "admin_spawn_started" or "admin_spawn_failed", {
            requestId = job.requestId,
            operationId = job.operationId,
            profileId = job.profileId,
            groupId = job.groupId,
            mode = job.mode,
            error = (not successful) and resultReason or nil,
        })
        if successful and job.dormant == true then
            settleJob(job, true, "dormant_created", actorUid, nil)
        elseif successful then
            startJob(job, actorUid, spawnOperationId)
        else
            settleJob(job, false, resultReason, actorUid, spawnOperationId)
        end
        end
        started = started + 1
        end
    end
    return processed + started
end

local function shellSnapshot(actor)
    local binding = Watchdog.bindings[actor.uid]
    if binding == nil or binding.generation ~= actor.generation then return {} end
    local result = {}
    local healthOk, health = pcall(function() return binding.shell:getHealth() end)
    if healthOk then result.health = tonumber(health) end
    local dataOk, data = pcall(function() return binding.shell:getModData() end)
    if dataOk and type(data) == "table" then
        result.endurance = tonumber(data.ProjectALifeEndurance)
        result.enduranceMaximum = tonumber(data.ProjectALifeEnduranceMaximum)
        result.combatMode = data.ProjectALifeEnduranceMode
        result.combatPhase = data.ProjectALifeCombatPhase
        result.dangerPosture = data.ProjectALifeDangerPosture
        result.weaponJammed = data.ProjectALifeWeaponJammed == true
        result.weaponJamCount = math.max(0,
            math.floor(tonumber(data.ProjectALifeWeaponJamCount) or 0))
        result.primaryAmmoReserve = math.max(0,
            math.floor(tonumber(data.ProjectALifePrimaryAmmoUnits) or 0))
        result.secondaryAmmoReserve = math.max(0,
            math.floor(tonumber(data.ProjectALifeSecondaryAmmoUnits) or 0))
    end
    return result
end

local function actorPayload(player)
    local actors, all = {}, Registry.list()
    local origin = playerPosition(player)
    table.sort(all, function(left, right)
        if origin == nil then return tostring(left.uid) < tostring(right.uid) end
        local ldx, ldy = left.worldPosition.x - origin.x, left.worldPosition.y - origin.y
        local rdx, rdy = right.worldPosition.x - origin.x, right.worldPosition.y - origin.y
        return ldx * ldx + ldy * ldy < rdx * rdx + rdy * rdy
    end)
    for index, actor in ipairs(all) do
        if index > 64 then break end
        local profile = Catalog.npc(actor.profileId)
        local faction = Catalog.faction(actor.factionId)
        local memory = type(actor.memory) == "table" and actor.memory or {}
        local enduranceState = type(memory.enduranceState) == "table"
            and memory.enduranceState or {}
        local shell = shellSnapshot(actor)
        local distance
        if origin ~= nil then
            local dx, dy = actor.worldPosition.x - origin.x, actor.worldPosition.y - origin.y
            distance = math.sqrt(dx * dx + dy * dy)
        end
        actors[#actors + 1] = {
            uid = actor.uid,
            generation = actor.generation,
            lifecycle = actor.lifecycle,
            profileId = actor.profileId,
            profileName = profile and profile.general and profile.general.name or actor.profileId,
            profileEndurance = profile and profile.general
                and tonumber(profile.general.endurance) or nil,
            factionId = actor.factionId,
            factionName = faction and faction.general and faction.general.name or actor.factionId,
            activity = actor.activity,
            intent = actor.intent,
            behavior = memory.adminMode or memory.behavior or actor.intent,
            combatMode = shell.combatMode or memory.enduranceMode or actor.activity,
            combatPhase = shell.combatPhase,
            dangerPosture = shell.dangerPosture,
            weaponJammed = shell.weaponJammed,
            weaponJamCount = shell.weaponJamCount,
            primaryAmmoReserve = shell.primaryAmmoReserve,
            secondaryAmmoReserve = shell.secondaryAmmoReserve,
            endurance = tonumber(enduranceState.value) or tonumber(memory.endurance)
                or shell.endurance,
            enduranceMaximum = tonumber(enduranceState.maximum)
                or tonumber(memory.enduranceMaximum) or shell.enduranceMaximum,
            health = shell.health,
            groupId = memory.groupId,
            groupIndex = memory.groupIndex,
            groupSize = memory.groupSize,
            targetUsername = memory.targetUsername,
            distance = distance,
            x = actor.worldPosition.x,
            y = actor.worldPosition.y,
            z = actor.worldPosition.z,
        }
    end
    return {
        ok = true,
        actors = actors,
        truncated = #all > #actors,
        queuedAdminSpawns = #Service.queue,
        pendingAdminSpawns = #Service.pendingOrder,
        adminSpawnGroups = tableCount(Service.groups),
    }
end

function Service.configure(adapters)
    Service.adapters = adapters or {}
    ProjectALife.CreatorTransfer.pending = setmetatable({}, { __mode = "k" })
    ProjectALife.CreatorTransfer.completed = setmetatable({}, { __mode = "k" })
    Service.gameplaySequences = setmetatable({}, { __mode = "k" })
    Service.lastSwingAtMs = setmetatable({}, { __mode = "k" })
    Service.lastAtMs = {}
    Service.sequence = 0
    Service.requestSequence = 0
    Service.queue = {}
    Service.groups = {}
    Service.pendingJobs = {}
    Service.pendingOrder = {}
    Service.groupOutcomes = {}
    Service.groupOutcomeOrder = {}
    Service.encounterTally = {}
    if ProjectALife.AdminConsoleService ~= nil then ProjectALife.AdminConsoleService.reset() end
    Service.resetCatalog()
end

function Service.watchGroup(requestId, listener)
    if type(requestId) ~= "string" or type(listener) ~= "function" then
        return false, "group_watch_invalid"
    end
    local group = Service.groups[requestId]
    if group ~= nil then
        group.listeners = group.listeners or {}
        group.listeners[#group.listeners + 1] = listener
        return true, "pending"
    end
    local outcome = Service.groupOutcomes[requestId]
    if outcome ~= nil then
        local ok = pcall(listener, outcome)
        return ok, ok and "complete" or "listener_failed"
    end
    return false, "group_not_found"
end

function Service.groupStatus(requestId)
    local group = Service.groups[requestId]
    if group ~= nil then
        return { ok = nil, completed = false, requestId = requestId,
            accepted = group.accepted, active = group.active,
            failed = group.failed, rejected = group.rejected }
    end
    return Service.groupOutcomes[requestId]
end

local function finiteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Service.recentlyAttacked(player, weapon)
    local now = nowMs()
    local swings = Service.lastSwingAtMs
    if player:isAttacking() == true then
        swings[player] = now
        return true
    end
    if now - (swings[player] or -math.huge) <= 1500 then return true end

    return player.isAiming ~= nil and player:isAiming() == true and weapon ~= nil
        and weapon.isAimedFirearm ~= nil and weapon:isAimedFirearm() == true
end

function Service.lineOfFire(player, shell)
    local seen = false
    pcall(function() seen = player:CanSee(shell) == true end)
    if seen then return true end
    local clear = false
    pcall(function()
        if LosUtil == nil or type(getCell) ~= "function" then return end
        local result = LosUtil.lineClear(getCell(),
            math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ()),
            math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ()), false)
        clear = tostring(result) ~= "Blocked"
    end)
    return clear
end

local function gameplayReport(player, args, command)
    local sequence = tonumber(args.sequence)
    if not finiteNumber(sequence) or sequence < 1 or sequence > 2147483647
            or sequence ~= math.floor(sequence) then return nil end
    local seen = Service.gameplaySequences[player] or {}
    if sequence <= (seen[command] or 0) then return nil end
    if player:isDead() then return nil end
    local x, y, z = player:getX(), player:getY(), player:getZ()
    if not finiteNumber(x) or not finiteNumber(y) or not finiteNumber(z) then return nil end
    local weapon = player.getAttackingWeapon and player:getAttackingWeapon() or player:getPrimaryHandItem()
    local weaponType = weapon and tostring(weapon:getFullType()) or ""
    local bareHands = (weaponType == "" or weaponType == "Base.BareHands")
        and (args.weapon == "" or args.weapon == "Base.BareHands")
    if type(args.weapon) ~= "string" or (args.weapon ~= weaponType and not bareHands) then return nil end

    if not Service.recentlyAttacked(player, weapon) then return nil end
    seen[command] = sequence
    Service.gameplaySequences[player] = seen
    return { x = x, y = y, z = z, weapon = weapon }
end

function Service.purgeActor(actor, reason)
    if type(actor) ~= "table" or actor.uid == nil then return false end
    reason = reason or "admin_purge"
    local removed, failure = SpawnService.retire(actor.uid, reason)
    if not removed then return false, failure end
    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.release) == "function" then
        pcall(executor.release, actor.uid, reason)
    end
    return true
end

function Service.outpostRadios()
    local rows = {}
    pcall(function()
        local registry = ProjectALife.OutpostRegistry
        if registry == nil or type(registry.list) ~= "function" then return end
        for _, site in ipairs(registry.list()) do

            if site.state ~= "expired" and site.commsDisabled ~= true
                    and type(site.radio) == "table" then

                local ambience, announcer
                pcall(function()
                    local preset = ProjectALife.OutpostPresets.get(site.presetId)
                    ambience = preset and preset.ambience or nil

                    announcer = preset and type(preset.announcer) == "table" and preset.announcer or nil
                end)
                rows[#rows + 1] = { site = site.id,
                    x = math.floor(tonumber(site.radio.x) or 0),
                    y = math.floor(tonumber(site.radio.y) or 0),
                    z = math.floor(tonumber(site.radio.z) or 0),
                    disabled = site.commsDisabled == true,
                    ambience = site.state == "garrisoned" and ambience or nil,
                    announcer = site.state == "garrisoned" and announcer or nil }
            end
        end
    end)
    return rows
end

function Service.broadcastOutpostRadios()
    local rows = Service.outpostRadios()
    local sent = false
    pcall(function()
        if type(sendServerCommand) ~= "function" then return end
        sendServerCommand("ProjectALife", "outpostRadioListResult", { ok = true, radios = rows })
        sent = true
    end)
    pcall(function()
        local menu = ProjectALife.OutpostRadioMenu
        if menu ~= nil and type(menu.acceptRadios) == "function" then menu.acceptRadios(rows) end
    end)
    return sent
end

function Service.pushAdminFlags(uid, generation, flags)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.serverDelegates) ~= "function" or executor.serverDelegates() ~= true then
        return false
    end
    local message = { uid = uid, generation = generation, flags = flags }
    if type(Service.adapters.broadcast) == "function" then
        Service.adapters.broadcast("ProjectALife", "adminActorFlagsApply", message)
        return true
    end
    if type(sendServerCommand) ~= "function" then return false end
    local ok = pcall(sendServerCommand, "ProjectALife", "adminActorFlagsApply", message)
    return ok
end

function Service.safehouseCommand(player, command, resultCommand, args)
    local director = ProjectALife.SafehouseDirector
    if director == nil or type(director.debugCommand) ~= "function" then
        reply(player, resultCommand, { ok = false, reason = "safehouse_unavailable", action = args.action })
        return false
    end
    if command == "safehouseWash" then
        local ok, why = director.wash(player)
        reply(player, resultCommand, { ok = ok == true, reason = why })
        return ok == true
    end
    if command == "safehouseHello" then
        local ok = director.noteCoopHost(player, args.coopHost == true)
        reply(player, resultCommand, { ok = ok == true })
        return ok == true
    end
    local ok, answer = pcall(director.debugCommand, player, args)
    if not ok then
        print("[ALIFE-SAFEHOUSE] debug command failed: " .. tostring(answer))
        answer = { ok = false, reason = "safehouse_failed", action = args.action }
    end
    reply(player, resultCommand, answer)
    return answer.ok == true
end

function Service.hostSelf(player)
    if player == nil or type(player.isLocalPlayer) ~= "function" then return false end
    local ok, own = pcall(player.isLocalPlayer, player)
    return ok and own == true
end

function Service.injuryDebug(player, args)
    local injury = ProjectALife.Injury
    local result = { ok = false, reason = "injury_missing" }
    if injury ~= nil and type(injury.debugCommand) == "function" then
        local ok, answer = pcall(injury.debugCommand, player, args)
        if ok and type(answer) == "table" then result = answer else result = { ok = false, reason = tostring(answer) } end
    end
    print("[ALIFE-INJURY] debug action=" .. tostring(args.action) .. " ok=" .. tostring(result.ok)
        .. " reason=" .. tostring(result.reason))
    return result
end

function Service.spawnCatalog(player, args)
    local definition = encounterDefinition(args.encounterId)
    if definition == nil then
        return Service.refuseEncounter(player, args, args.encounterId, "unknown_encounter")
    end
    local director = ProjectALife.EncounterDirector
    local fallback = playerPosition(player) or { x = 0, y = 0, z = 0 }
    local point = { x = tonumber(args.x) or fallback.x,
        y = tonumber(args.y) or fallback.y, z = tonumber(args.z) or fallback.z }
    local span = math.max(0, math.min(8, definition.maxCount or 4)
        - math.max(1, definition.minCount or 2))
    local count = math.max(1, math.min(8,
        (definition.minCount or 2) + math.floor(span / 2)))
    local routed = clone(args)
    routed.count = (tonumber(args.count) or 0) > 0 and tonumber(args.count) or count

    if definition.trigger == "raid_director" then
        local raid = ProjectALife.RaidDirector
        local ok, result = false, "raid_director_unavailable"
        if raid ~= nil and type(raid.start) == "function" then
            local raidOptions = {
                groupSize = routed.count,
                waves = tonumber(args.waves),
                waveDelayMinutes = tonumber(args.waveDelayMinutes),
                factionId = args.factionId,
                distance = tonumber(args.distance),
            }
            if type(args.raidHeli) == "boolean" then raidOptions.heli = args.raidHeli end
            ok, result = raid.start(player, raidOptions, true)
        end
        if ok ~= true then
            return Service.refuseEncounter(player, args, definition.id, tostring(result), nil,
                { accepted = 0, failed = 0, mode = "full_raid" })
        end
        pcall(function()
            player:Say("A-Life: full-scale raid started (" .. tostring(result) .. ")")
        end)
        Service.tallyEncounter(definition.id, nil)
        reply(player, "debugSpawnResult", { ok = true, requestId = args.requestId,
            reason = "raid_started", accepted = 0, failed = 0,
            mode = "full_raid", raidId = result, encounterId = definition.id })
        return true
    end

    routed.profileId = nil
    routed.profileIds = nil
    local picked, pickError = Service.hostileProfileIds(
        routed.count, nowMs(), args.factionId, true)
    if picked == nil then
        return Service.refuseEncounter(player, args, definition.id, pickError or "no_hostile_profiles")
    end
    routed.profileIds = picked

    local ruleSite = tostring(args.placementMode or "here") == "rule"
    if (ruleSite or definition.placement == "shore") and director ~= nil
            and type(director.siteFor) == "function" then
        local forward = type(SpawnPolicy.forwardOf) == "function"
            and select(2, pcall(SpawnPolicy.forwardOf, player)) or nil
        local site, why = director.siteFor(definition, point, { count = routed.count,
            fx = type(forward) == "table" and forward.x or nil,
            fy = type(forward) == "table" and forward.y or nil })
        if site == nil then
            local reason = why or "no_site_rule"
            if ruleSite then
                reason = "no_placement:" .. tostring(definition.placement or "town")
            end
            return Service.refuseEncounter(player, args, definition.id, reason, why)
        end
        routed.x, routed.y, routed.z = site.x, site.y, site.z
        point = { x = site.x, y = site.y, z = site.z }
        if type(site.slots) == "table" then
            routed.slots = {}
            for index, slot in ipairs(site.slots) do
                routed.slots[index] = { x = slot.x, y = slot.y, z = slot.z }
            end
        end
    elseif ruleSite and director ~= nil and type(director.placeFor) == "function" then
        local placed = director.placeFor(definition, player)
        if placed == nil then
            return Service.refuseEncounter(player, args, definition.id,
                "no_placement:" .. tostring(definition.placement or "town"))
        end
        routed.x, routed.y, routed.z = placed.x, placed.y, placed.z
        point = placed
    end
    routed.mode = definition.mode or "roam"
    routed.profile = definition.profile

    routed.awareness = definition.awareness
    routed.roleAwareness = definition.roleAwareness

    routed.schedule = definition.schedule
    routed.conducts = definition.conducts
    routed.animation = "normal"
    routed.anchor = definition.persistent == true
    routed.encounterId = definition.id
    routed.encounterPersistent = definition.persistent == true

    if args.persistent ~= nil then
        routed.encounterPersistent = args.persistent == true
        routed.anchor = args.persistent == true
    end
    routed.stance = definition.stance
    routed.roles = definition.roles
    routed.separation = tonumber(args.separation) or 2
    routed.radius = tonumber(args.radius) or 24
    routed.distance = tonumber(args.distance) or 0
    if director ~= nil then
        routed.route = director.routeFor(definition, point)
        routed.heading = director.headingFor(definition, point)
    end
    local payload = spawn(player, routed, true)
    if payload ~= nil and payload.ok == true then
        if type(payload.origin) == "table" then point = payload.origin end
        pcall(function()
            local log = ProjectALife.EncounterLog
            if log ~= nil then
                log.record(definition, point, routed.count, "manual",
                    payload.groupId)
            end
        end)
    else
        Service.refuseEncounter(player, args, definition.id, payload and payload.reason or "unknown",
            nil, payload)
        return false
    end
    Service.tallyEncounter(definition.id, "queued")
    if type(payload) == "table" then payload.encounterId = definition.id end
    reply(player, "debugSpawnResult", payload)
    return payload.ok == true
end

function Service.outpostDelete(player, resultCommand, args)
    local registry = ProjectALife.OutpostRegistry
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    local px = tonumber(args.x) or 0
    local py = tonumber(args.y) or 0
    local reach = math.max(4, math.min(160, tonumber(args.reach) or 60))
    local best, bestDistance
    if registry ~= nil then
        for _, site in ipairs(registry.list()) do
            if site.state ~= "expired" then
                local dx, dy = (tonumber(site.x) or 0) - px, (tonumber(site.y) or 0) - py
                local d = math.sqrt(dx * dx + dy * dy)
                if d <= reach and (bestDistance == nil or d < bestDistance) then
                    best, bestDistance = site, d
                end
            end
        end
    end
    if best == nil then
        reply(player, resultCommand, { ok = false, reason = "no_outpost_nearby" })
        return false
    end
    local removed, failed = 0, 0
    for _, actor in ipairs(Registry.list()) do
        local memory = type(actor.memory) == "table" and actor.memory or {}
        if tostring(memory.outpostId or "") == best.id then
            if Service.purgeActor(actor, "admin_outpost_delete") then removed = removed + 1
            else failed = failed + 1 end
        end
    end
    if failed > 0 then
        reply(player, resultCommand, { ok = false, removed = removed, failed = failed,
            siteId = best.id, reason = "outpost_delete_failed" })
        return false
    end
    local expired = registry.expire(best.id, best.revision, hours, "admin_outpost_delete")
    reply(player, resultCommand, { ok = expired ~= nil, removed = removed,
        siteId = best.id, reason = expired == nil and "site_revision_conflict" or nil })
    return expired ~= nil
end

function Service.outpostLights(player, resultCommand, args)
    local registry, lights = ProjectALife.OutpostRegistry, ProjectALife.OutpostLights
    if registry == nil or lights == nil or type(lights.relight) ~= "function" then
        reply(player, resultCommand, { ok = false, reason = "lights_unavailable" })
        return false
    end
    local px, py = tonumber(args.x), tonumber(args.y)
    if px == nil or py == nil then
        pcall(function() px, py = player:getX(), player:getY() end)
    end
    local best, bestDistance
    for _, site in ipairs(registry.list()) do
        if site.state == "built" or site.state == "garrisoned" then
            local b = type(site.bounds) == "table" and site.bounds or {}
            local cx, cy = ((tonumber(b.x1) or site.x) + (tonumber(b.x2) or site.x)) / 2,
                ((tonumber(b.y1) or site.y) + (tonumber(b.y2) or site.y)) / 2
            local d = math.sqrt(((px or 0) - cx) ^ 2 + ((py or 0) - cy) ^ 2)
            if d <= 120 and (bestDistance == nil or d < bestDistance) then best, bestDistance = site, d end
        end
    end
    if best == nil then
        reply(player, resultCommand, { ok = false, reason = "no_outpost_nearby" })
        return false
    end
    local ok, stats = lights.relight(best, nowMs())
    stats = type(stats) == "table" and stats or {}
    print("[A-Life] outpost lights: site=" .. tostring(best.id) .. " ok=" .. tostring(ok)
        .. " state=" .. (stats.campfires ~= nil and "done" or "queued")
        .. " campfires=" .. tostring(stats.campfires) .. " lit=" .. tostring(stats.lit)
        .. " lamps=" .. tostring(stats.lamps) .. " on=" .. tostring(stats.on)
        .. " failed=" .. tostring(stats.failed))
    reply(player, resultCommand, { ok = ok == true, siteId = best.id, queued = stats.campfires == nil,
        campfires = stats.campfires, lit = stats.lit,
        lamps = stats.lamps, on = stats.on, failed = stats.failed })
    return ok == true
end

function Service.squadDelete(player, resultCommand, args)
    local groupId = type(args.groupId) == "string" and args.groupId or nil

    local everySquad = args.all == true
    local removed, failed = 0, 0
    if everySquad then
        for _, actor in ipairs(Registry.list()) do
            local memory = type(actor.memory) == "table" and actor.memory or {}
            if type(memory.groupId) == "string" and memory.groupId ~= "" then
                if Service.purgeActor(actor, "admin_squad_delete_all") then removed = removed + 1
                else failed = failed + 1 end
            end
        end
        local ok = pcall(function()
            local ledger = ProjectALife.SquadLedger
            if ledger == nil or type(ledger.ids) ~= "function" or type(ledger.peek) ~= "function" then return end

            for _, id in ipairs(ledger.ids()) do
                local squad = ledger.peek(id)
                if squad ~= nil then
                    if ledger.remove(id, squad.revision, "admin_squad_delete_all") then
                        removed = removed + 1
                    else
                        failed = failed + 1
                    end
                end
            end
        end)
        if not ok then failed = failed + 1 end
    elseif groupId ~= nil then
        for _, actor in ipairs(Registry.list()) do
            local memory = type(actor.memory) == "table" and actor.memory or {}
            local key = memory.groupId or ("solo:" .. actor.uid)
            if key == groupId then
                if Service.purgeActor(actor, "admin_squad_delete") then removed = removed + 1
                else failed = failed + 1 end
            end
        end
        local ok = pcall(function()
            local ledger = ProjectALife.SquadLedger
            local squad = ledger ~= nil and type(ledger.read) == "function" and ledger.read(groupId) or nil
            if squad ~= nil then
                if ledger.remove(squad.id, squad.revision, "admin_squad_delete") then removed = removed + 1
                else failed = failed + 1 end
            end
        end)
        if not ok then failed = failed + 1 end
    end
    reply(player, resultCommand, { ok = removed > 0 and failed == 0, removed = removed, failed = failed,
        groupId = groupId, all = everySquad or nil,
        reason = failed > 0 and "squad_delete_failed"
            or (removed <= 0 and (everySquad and "no_squads_on_map" or "squad_not_found") or nil) })
    return removed > 0 and failed == 0
end

function Service.handle(module, command, player, args)
    if module ~= "ProjectALife" or player == nil
            or commands[command] ~= true then return false end
    args = type(args) == "table" and args or {}
    local isSpawnCommand = spawnCommands[command] ~= nil
    local resultCommand = isSpawnCommand and "debugSpawnResult" or command .. "Result"
    if command == "creatorUpload" then
        resultCommand = args.kind == "profile" and "creatorProfileUpsertResult"
            or args.kind == "faction" and "creatorFactionUpsertResult" or "debugSyncCreatorResult"
    end
    local rejection = { ok = false }
    if isSpawnCommand then
        rejection.requestId = args.requestId
        rejection.mode = spawnCommands[command] == "request"
            and normalizeMode(args) or spawnCommands[command]
    end

    local gameplay = command == "shellHit" or command == "weaponNoise"
        or command == "shout"
        or command == "playerDied"
        or command == "outpostRadioDisable" or command == "outpostRadioUse"
        or command == "outpostRadioList"
        or command == "RaidPreludeFinished"
        or command == "FullRaidPreludeFinished"
        or (command == "safehouseHello" and Service.hostSelf(player))
        or command == "safehouseWash"
        or command == "creatorProfileHello"
        or command == "creatorFactionHello"
    if not gameplay and not authorized(player) then
        rejection.reason = "admin_required"
        Service.noteCatalogRefusal(player, command, rejection.reason)
        if command == "alifeDiagnostics" then
            print("[ALIFE-DEBUG] diagnostics refused user="
                .. tostring(player ~= nil and player.getUsername ~= nil and player:getUsername() or "?")
                .. " reason=admin_required")
        end
        reply(player, resultCommand, rejection)
        return false
    end

    if command == "alifeDiagnostics" then
        Service.setDiagnostics(player, args.enabled == true, args.recorder == true)
        print("[ALIFE-DEBUG] diagnostics user="
            .. tostring(player ~= nil and player.getUsername ~= nil and player:getUsername() or "?")
            .. " enabled=" .. tostring(args.enabled == true)
            .. " recorder=" .. tostring(args.recorder == true))
        reply(player, resultCommand, { ok = true, enabled = args.enabled == true,
            recorder = args.recorder == true })
        return true
    end
    if (Service.diagnosticCommands[command] == true or (command == "debugSafehouse" and args.action == "diagnostics"))
            and not Service.diagnosticsAllowed(player) then
        rejection.reason = "diagnostics_disabled"
        Service.noteCatalogRefusal(player, command, rejection.reason)
        reply(player, resultCommand, rejection)
        return false
    end
    if command == "creatorUpload" then
        local upload, uploadReason = ProjectALife.CreatorTransfer.receive(player, args, nowMs())
        if upload == false then return true end
        if upload == nil then
            reply(player, resultCommand, { ok = false, reason = uploadReason })
            return false
        end
        if upload.kind == "profile" then
            command, args = "creatorProfileUpsert", { profileId = upload.recordId, text = upload.profiles }
        elseif upload.kind == "faction" then
            command, args = "creatorFactionUpsert", { factionId = upload.recordId, text = upload.factions }
        else
            command, args = "debugSyncCreator", { profilesText = upload.profiles, factionsText = upload.factions }
        end
    end
    local profileMutation = command == "creatorProfileUpsert"
        or command == "creatorProfileDelete"
    local factionMutation = command == "creatorFactionUpsert"
        or command == "creatorFactionDelete"
    local rateKey = isSpawnCommand and "debugSpawn" or command
    if profileMutation and type(args.profileId) == "string" then
        rateKey = rateKey .. ":" .. args.profileId
    elseif factionMutation and type(args.factionId) == "string" then
        rateKey = rateKey .. ":" .. args.factionId
    elseif command == "debugCatalogFaction" and type(args.factionId) == "string" then
        rateKey = rateKey .. ":" .. string.sub(args.factionId, 1, 64)
    end
    local key, currentTime = playerKey(player) .. ":" .. rateKey, nowMs()

    local limit = gameplay and 60 or Service.minimumIntervalMs
    if currentTime - (Service.lastAtMs[key] or -math.huge) < limit then
        rejection.reason = "rate_limited"
        Service.noteCatalogRefusal(player, command, rejection.reason)
        if command == "creatorProfileHello" or command == "creatorFactionHello" then rejection.retryAfterMs = 1000 end
        reply(player, resultCommand, rejection)
        return false
    end
    Service.lastAtMs[key] = currentTime

    if ProjectALife.AdminConsoleService ~= nil and ProjectALife.AdminConsoleService.commands[command] ~= nil then
        return ProjectALife.AdminConsoleService.handle(Service, command, player, args, resultCommand)
    end

    if command == "debugSafehouse" or command == "safehouseHello" or command == "safehouseWash" then
        return Service.safehouseCommand(player, command, resultCommand, args)
    end

    if command == "debugInjury" then
        local result = Service.injuryDebug(player, args)
        reply(player, resultCommand, result)
        return result.ok == true
    end

    if command == "creatorProfileHello" then
        local ok, reason, revision, retryAfterMs = ProjectALife.CustomProfileAuthority.hello(
            player, args.revision)
        if not ok then
            reply(player, resultCommand, { ok = false, reason = reason,
                revision = revision, retryAfterMs = retryAfterMs })
        end
        return ok == true
    end

    if command == "creatorFactionHello" then
        local ok, reason, revision, retryAfterMs = ProjectALife.CustomFactionAuthority.hello(
            player, args.revision)
        if not ok then
            reply(player, resultCommand, { ok = false, reason = reason,
                revision = revision, retryAfterMs = retryAfterMs })
        end
        return ok == true
    end

    if command == "creatorFactionUpsert" then
        local ok, reason, revision = ProjectALife.CustomFactionAuthority.upsert(
            args.factionId, args.text)
        reply(player, resultCommand, { ok = ok == true, reason = reason,
            factionId = args.factionId, revision = revision })
        return ok == true
    elseif command == "creatorFactionDelete" then
        local ok, reason, revision = ProjectALife.CustomFactionAuthority.delete(
            args.factionId)
        reply(player, resultCommand, { ok = ok == true, reason = reason,
            factionId = args.factionId, revision = revision })
        return ok == true
    elseif command == "creatorFactionReset" then
        local ok, reason, revision = ProjectALife.CustomFactionAuthority.resetToShipped()
        reply(player, resultCommand, { ok = ok == true, reason = reason, revision = revision })
        return ok == true
    end

    if command == "creatorProfileUpsert" then
        local ok, reason, revision = ProjectALife.CustomProfileAuthority.upsert(
            args.profileId, args.text)
        reply(player, resultCommand, { ok = ok == true, reason = reason,
            profileId = args.profileId, revision = revision })
        return ok == true
    elseif command == "creatorProfileDelete" then
        local ok, reason, revision = ProjectALife.CustomProfileAuthority.delete(
            args.profileId)
        reply(player, resultCommand, { ok = ok == true, reason = reason,
            profileId = args.profileId, revision = revision })
        return ok == true
    end

    if command == "RaidPreludeFinished" or command == "FullRaidPreludeFinished" then
        local name
        pcall(function() name = player:getUsername() end)
        local director = ProjectALife.RaidDirector
        local ok, reason = false, "raid_director_unavailable"
        if director ~= nil and type(director.confirm) == "function" then
            ok, reason = director.confirm(name, args.raidId)
        end
        reply(player, resultCommand, { ok = ok == true, reason = reason,
            raidId = args.raidId })
        return ok == true
    end

    if command == "adminActorFlags" then
        local uid = type(args.uid) == "string" and args.uid or nil
        local actor = uid ~= nil and Registry.read(uid) or nil
        if actor == nil then
            reply(player, resultCommand, { ok = false, reason = "actor_not_found", uid = uid })
            return false
        end
        local source = type(args.flags) == "table" and args.flags or {}
        local oldAdmin = type(actor.memory) == "table" and actor.memory.admin or nil
        local flags = normalizeAdminFlags(source, actor.worldPosition, oldAdmin)
        local updated, updateError = Registry.update(actor.uid, actor.revision, function(record)
            record.memory = type(record.memory) == "table" and record.memory or {}
            record.memory.admin = flags

            record.memory.persistent = (flags.persistent == true
                or record.memory.encounter ~= nil) and true or nil
        end)
        if updated == nil then
            reply(player, resultCommand, { ok = false, reason = updateError, uid = uid })
            return false
        end
        local binding = Watchdog.bindings[uid]
        if binding ~= nil and binding.generation == updated.generation then
            pcall(function()
                local data = binding.shell:getModData()
                data.ProjectALifeAdminManaged = true
                data.ProjectALifeAdminPersistent = flags.persistent == true
                data.ProjectALifeInvulnerable = flags.invulnerable == true
                data.ProjectALifeAdminStationary = flags.stationary == true
                data.ProjectALifeLeashX = flags.leash and flags.leash.x or nil
                data.ProjectALifeLeashY = flags.leash and flags.leash.y or nil
                data.ProjectALifeLeashZ = flags.leash and flags.leash.z or nil
                data.ProjectALifeLeashRadius = flags.leash and flags.leash.radius or nil
                if flags.invulnerable then
                    ProjectALife.ShellSimulation.setHealth(binding.shell,
                        ProjectALife.ShellSimulation.maximumFor(binding.shell))
                end
                ProjectALife.Animations.syncPresentation(binding.shell)
            end)
            if flags.stationary and ProjectALife.Movement
                    and type(ProjectALife.Movement.stop) == "function" then
                pcall(ProjectALife.Movement.stop, binding.shell)
            end
        end
        Service.pushAdminFlags(uid, updated.generation, flags)
        reply(player, resultCommand, { ok = true, uid = uid, flags = flags })
        return true
    end

    if command == "playerDied" then
        return ProjectALife.Reputation.onPlayerDied(player)
    end
    if command == "shout" then

        local handled = false
        pcall(function()
            local investigation = ProjectALife.Investigation
            if investigation == nil
                    or type(investigation.handleClientCommand) ~= "function" then
                return
            end
            handled = investigation.handleClientCommand("ProjectALife", "shout", player) == true
        end)
        return handled
    end
    if command == "shellHit" then

        local accepted = false
        pcall(function()
            local uid = type(args) == "table" and tostring(args.uid or "") or ""
            if uid == "" or #uid > 64 then return end
            local watchdog = ProjectALife.Watchdog
            local binding = watchdog and watchdog.bindings[uid]
            if binding == nil or binding.shell == nil then return end
            if tonumber(args.generation) ~= binding.generation then return end
            local record = ProjectALife.ActorRegistry and ProjectALife.ActorRegistry.read(uid)
            if record == nil or record.lifecycle ~= "active" or record.generation ~= binding.generation then return end
            local report = gameplayReport(player, args, command)
            if report == nil or binding.shell:isDead() then return end
            local x, y, z = binding.shell:getX(), binding.shell:getY(), binding.shell:getZ()
            if not finiteNumber(x) or not finiteNumber(y) or not finiteNumber(z) then return end
            local weapon, range = report.weapon, 1.5
            if weapon ~= nil then

                if weapon.getMaxRange == nil then return end
                range = tonumber(weapon:getMaxRange(player))
            end
            if not finiteNumber(range) or range <= 0 then return end
            range = math.min(100, range) + 1 
            if (x-report.x)^2 + (y-report.y)^2 > range^2 or math.abs(z-report.z) > 0.5 then return end
            if not Service.lineOfFire(player, binding.shell) then return end

            local fence = ProjectALife.AIFence
            local forgiven = fence ~= nil and type(fence.friendForgives) == "function"
                and fence.friendForgives(binding.shell, player, nowMs()) == true

            if args.shove == true and args.stomp ~= true then
                local talk = ProjectALife.Talk
                if talk ~= nil and type(talk.onHitByPlayer) == "function" then
                    talk.onHitByPlayer(player, binding.shell, "fists")
                end
            end
            local careful, reputation = ProjectALife.ModuleCareful, ProjectALife.Reputation
            local key = reputation and reputation.playerKey and reputation.playerKey(player)
            local grudges = record.memory and record.memory.hostileToPlayerKeys or {}
            if not forgiven and careful ~= nil and type(careful.turnGroup) == "function"
                    and not grudges[key or ""] then
                careful.turnGroup(record, binding.shell, player, true)
            end
            local healthSystem = ProjectALife.Health

            local shielded = false
            if args.shove ~= true and fence ~= nil and type(fence.remoteShield) == "function" then
                local okShield, answer = pcall(fence.remoteShield, binding.shell, report.weapon, args.bodyPart)
                shielded = okShield and answer == true
            end
            if healthSystem ~= nil and (args.shove ~= true or args.stomp == true) then

                healthSystem.onEngineHit(binding.shell, player, args.bodyPart or "torso", nil, nil, forgiven,
                    report.weapon or (args.ranged == true and "firearm" or nil), shielded)
            end

            pcall(function()
                local guard = ProjectALife.AIFence
                if guard == nil then return end
                if args.shove == true then
                    if type(guard.remoteShove) == "function" then
                        guard.remoteShove(binding.shell, player, args.stomp == true)
                    end
                    return
                end
                if type(guard.remoteFinisher) == "function"
                        and guard.remoteFinisher(binding.shell, player, report.weapon, false) then
                    return
                end
                if type(guard.applyRemoteHit) == "function" then
                    guard.applyRemoteHit(binding.shell, player, report.weapon, args.bodyPart, shielded)
                end
            end)
            local data = binding.shell:getModData()
            data.ProjectALifeLastHitAtMs = nowMs()

            pcall(function()
                local panic = ProjectALife.ModulePanic
                if panic ~= nil and type(panic.onShot) == "function" then
                    panic.onShot(record, binding.shell, player, args.ranged == true, nowMs())
                end
            end)
            local perception = ProjectALife.Perception
            if not forgiven and perception ~= nil and type(perception.noteAttacker) == "function" then
                perception.noteAttacker(uid, player, 12000, "player")
            end

            pcall(function()
                local executor = ProjectALife.Executor
                if executor ~= nil and type(executor.pushHealth) == "function" then
                    executor.pushHealth(binding.shell, uid, binding.generation, player, "player", nil, forgiven)
                end
            end)
            accepted = true
        end)
        return accepted
    end
    if command == "debugWardrobe" then
        local answer = Service.debugWardrobe(args)
        reply(player, resultCommand, answer)
        return answer.ok == true
    end
    if command == "debugPickedOver" then
        local picked = ProjectALife.PickedOver
        local result = { ok = false, reason = "picked_over_missing" }
        if picked ~= nil and type(picked.debug) == "function" then
            local ok, answer = pcall(picked.debug, player, tostring(args.action or "info"), args.level)
            if ok and type(answer) == "table" then result = answer
            else result = { ok = false, reason = tostring(answer) } end
        end
        print("[A-Life] picked-over debug: ok=" .. tostring(result.ok) .. " building=" .. tostring(result.building)
            .. " level=" .. tostring(result.level) .. " faction=" .. tostring(result.faction)
            .. " applied=" .. tostring(result.applied) .. " reason=" .. tostring(result.reason))
        reply(player, resultCommand, result)
        return result.ok == true
    end
    if command == "weaponNoise" then

        local accepted = false
        pcall(function()
            local investigation = ProjectALife.Investigation
            if investigation == nil or type(args) ~= "table" then return end
            local report = gameplayReport(player, args, command)
            if report == nil then return end
            local radius = 10
            if report.weapon ~= nil and report.weapon.isAimedFirearm == nil then return end
            if report.weapon ~= nil and report.weapon:isAimedFirearm() then
                radius = tonumber(report.weapon:getSoundRadius())
            end
            if not finiteNumber(radius) then return end
            investigation.note(report.x, report.y, report.z,
                math.max(4, math.min(120, radius)), 20000, nil, "noise", nil, player)
            accepted = true
        end)
        return accepted
    end
    if command == "outpostRadioList" then

        reply(player, resultCommand, { ok = true, radios = Service.outpostRadios() })
        return true
    end
    if command == "outpostRadioDisable" or command == "outpostRadioUse" then

        local payload = { ok = false, reason = "radio_unavailable" }
        pcall(function()
            local radio = ProjectALife.OutpostRadio
            if radio == nil or type(radio.handle) ~= "function" then return end
            local ok, reason, wasFriendly = radio.handle(player, command, args, nowMs())
            payload.ok, payload.reason = ok == true, reason
            payload.wasFriendly = wasFriendly == true
        end)
        reply(player, resultCommand, payload)
        return payload.ok == true
    end
    if command == "debugForceSupport" then

        local payload = { ok = false }
        pcall(function()
            local support = ProjectALife.Support
            if support == nil then payload.reason = "support_unavailable" return end
            local px, py = player:getX(), player:getY()
            local best, bestActor, bestShell = math.huge, nil, nil
            for _, actor in ipairs(Registry.list()) do
                if actor.lifecycle == "active" then
                    local binding = Watchdog.bindings[actor.uid]
                    if binding ~= nil and binding.shell ~= nil then
                        local dx, dy = binding.shell:getX() - px, binding.shell:getY() - py
                        local d = dx * dx + dy * dy
                        if d < best then best, bestActor, bestShell = d, actor, binding.shell end
                    end
                end
            end
            if bestActor == nil then payload.reason = "no_living_actor" return end
            local key
            pcall(function() key = player:getUsername() end)
            local ok, reason = support.request(bestActor, bestShell,
                { x = px, y = py, playerKey = key or "player0" }, nowMs())
            payload.ok, payload.reason, payload.caller = ok == true, reason, bestActor.uid
        end)
        pcall(function()
            player:Say(payload.ok and "A-Life: support called (" .. tostring(payload.reason) .. ")"
                or "A-Life: support refused (" .. tostring(payload.reason) .. ")")
        end)
        reply(player, resultCommand, payload)
        return payload.ok == true
    end
    if command == "raidStart" then
        local payload = { ok = false }
        pcall(function()
            local director = ProjectALife.RaidDirector
            if director == nil or type(director.start) ~= "function" then
                payload.reason = "raid_director_unavailable"
                return
            end
            local ok, value = director.start(player, args, true)
            payload.ok = ok == true
            if ok then payload.raidId, payload.reason = value, "raid_started"
            else payload.reason = value end
        end)
        pcall(function()
            player:Say(payload.ok and "A-Life: full raid started"
                or "A-Life: raid refused (" .. tostring(payload.reason) .. ")")
        end)
        reply(player, resultCommand, payload)
        return payload.ok
    end
    if command == "debugBuildOutpost" then

        local payload = { ok = false }
        pcall(function()
            local presets = ProjectALife.OutpostPresets
            local registry = ProjectALife.OutpostRegistry
            local builder = ProjectALife.OutpostBuilder
            local director = ProjectALife.OutpostDirector
            if presets == nil or registry == nil or builder == nil or director == nil
                    or type(director.beginBuild) ~= "function" then
                payload.reason = "outposts_unavailable"
                return
            end
            local presetId = type(args) == "table" and args.presetId or nil
            local origin, _, originError = requestedOrigin(player, args or {})
            if origin == nil then payload.reason = originError return end
            local px, py, pz = origin.x, origin.y, origin.z
            local clickedSquare, building
            pcall(function()
                clickedSquare = getCell():getGridSquare(
                    math.floor(px), math.floor(py), math.floor(pz))
                building = clickedSquare and clickedSquare:getBuilding() or nil
            end)
            local preset = presets.get(presetId or (building ~= nil and "police_station" or "forest_camp"))
            if preset == nil then payload.reason = "preset_unknown" return end
            local bounds, probe
            if building ~= nil and preset.class == "building" then
                probe, bounds = builder.probeBuilding(building)
                if probe == nil then payload.reason = "building_unreadable" return end
            elseif preset.class == "building" then

                payload.reason = "building_required"
                return
            else
                local footprint = preset.footprint or { w = 11, h = 11 }
                local width = math.max(3, math.floor(tonumber(footprint.w) or 11))
                local height = math.max(3, math.floor(tonumber(footprint.h) or 11))
                local x1 = math.floor(px) - math.floor(width / 2)
                local y1 = math.floor(py) - math.floor(height / 2)
                bounds = { x1 = x1, y1 = y1, x2 = x1 + width - 1,
                    y2 = y1 + height - 1, z = math.floor(pz) }
                probe = {}
            end
            local hours = 0
            pcall(function() hours = getGameTime():getWorldAgeHours() end)
            local factionId = type(args) == "table" and args.factionId or nil
            if type(factionId) ~= "string" or factionId == "" then
                factionId = hostileFactionId(math.floor(px * 31 + py))
            end
            if factionId == nil then payload.reason = "hostile_faction_not_found" return end
            local site = registry.create({ presetId = preset.id, x = math.floor(px), y = math.floor(py),
                bounds = bounds, createdHours = hours,
                minLifeHours = preset.lifetime.minHours,
                maxLifeHours = preset.lifetime.maxHours,
                factionId = factionId,
                hostileToPlayers = preset.hostileToPlayers })
            if site == nil then payload.reason = "site_create_failed" return end
            site = registry.update(site.id, site.revision, function(s)
                s.adminBuilt = true
                s.spawnOverrides = {}
                for _, key in ipairs({ "animation", "profile", "heading", "supportPolicy", "supportType",
                        "supportHeli", "supportSize", "awareness", "leashRadius", "health", "damageReduction",
                        "damageOutput", "invulnerable", "stationary" }) do
                    local value = args and args[key]
                    if (type(value) == "string" and #value <= 80) or type(value) == "boolean"
                            or (type(value) == "number" and finiteCoordinate(value)) then
                        s.spawnOverrides[key] = value
                    end
                end
                if type(args.conducts) == "table" and SPAWN_CONDUCTS[args.conducts[1]] then
                    s.spawnOverrides.conducts = { args.conducts[1] }
                end
                if finiteCoordinate(args.count) and tonumber(args.count) > 0 then
                    s.garrisonCount = math.max(1, math.min(8, math.floor(tonumber(args.count))))
                end
                local override = hostility(args.hostileOverride)
                if override ~= nil then s.hostileToPlayers = override end
            end) or site

            local sheet = builder.resolve(preset, site, math.floor(px * 31 + py), probe)
            if sheet == nil or not director.beginBuild(site, sheet) then
                registry.expire(site.id, site.revision, hours, "sheet_failed")
                payload.reason = "sheet_failed"
                return
            end
            payload.ok, payload.placed, payload.ops, payload.site = true, 0, #sheet.ops, site.id
            payload.building, payload.garrisonPending, payload.garrisoned = true, true, false
            payload.keepAway = tonumber(director.settings and director.settings.minPlayerDistance) or 40
        end)
        pcall(function()
            player:Say(payload.ok and ("A-Life: outpost building, " .. tostring(payload.ops)
                    .. " ops; its squad comes once nobody is within " .. tostring(payload.keepAway) .. " tiles")
                or ("A-Life: outpost refused (" .. tostring(payload.reason) .. ")"))
        end)
        reply(player, resultCommand, payload)
        return payload.ok == true
    end
    if command == "debugModuleQA" then
        if type(args) == "table" and args.footworkForce ~= nil and ProjectALife.MeleeCrew ~= nil
                and type(ProjectALife.MeleeCrew.setForce) == "function" then
            ProjectALife.MeleeCrew.setForce(args.footworkForce)
        end
        local ok, failure = pcall(function()
            local startedAt = nowMs()
            local lines = { "[ALIFE-QA] ==== module status ====" }
            lines[#lines + 1] = "[ALIFE-QA] build="
                .. tostring(ProjectALife.Runtime and ProjectALife.Runtime.BUILD or "unknown")
            local registry = ProjectALife.ModuleRegistry
            if registry ~= nil then
                for id, module in pairs(registry.modules) do
                    lines[#lines + 1] = string.format(
                        "[ALIFE-QA] %-12s kind=%-11s enabled=%-5s primary=%s",
                        id, tostring(module.kind),
                        tostring(registry.isEnabled(id)),
                        tostring(module.primary == true))
                end
                lines[#lines + 1] = "[ALIFE-QA] lastError="
                    .. tostring(registry.lastError)
            end

            local census, actors = {}, 0
            local watchdog = ProjectALife.Watchdog
            if watchdog ~= nil and type(watchdog.bindings) == "table" then
                for _, binding in pairs(watchdog.bindings) do
                    actors = actors + 1
                    pcall(function()
                        local conduct = binding.shell:getModData().ProjectALifeConduct
                        if conduct ~= nil then
                            census[conduct] = (census[conduct] or 0) + 1
                        end
                    end)
                end
            end
            local conducts = "[ALIFE-QA] shells=" .. actors .. " conducts:"
            for conduct, count in pairs(census) do
                conducts = conducts .. " " .. conduct .. "=" .. count
            end
            lines[#lines + 1] = conducts
            local lifecycle = { active = 0, spawning = 0, dormant = 0, dead = 0 }
            ProjectALife.ActorRegistry.each(function(actor)
                lifecycle[actor.lifecycle] = (lifecycle[actor.lifecycle] or 0) + 1
            end)
            lines[#lines + 1] = "[ALIFE-QA] lifecycle active=" .. lifecycle.active
                .. " spawning=" .. lifecycle.spawning .. " dormant=" .. lifecycle.dormant
                .. " dead=" .. lifecycle.dead .. " decisionQueue=" .. #ProjectALife.DecisionLoop.order
            Service.appendBodyWaitLines(lines, player)
            local telemetry = ProjectALife.Telemetry
            lines[#lines + 1] = "[ALIFE-QA] recovery=" .. telemetry.count("shell_recovery")
                .. " rollback=" .. telemetry.count("spawn_rollback")
                .. " callbackErrors=" .. telemetry.count("action_handler_failed")

            pcall(function()
                local decisions = ProjectALife.DecisionLoop
                if decisions ~= nil and type(decisions.profileTop) == "function" then
                    lines[#lines + 1] = "[ALIFE-QA] decisionprofile " .. decisions.profileTop(decisions.profile.total, 16)
                end
            end)
            local runtimeMetrics = ProjectALife.Runtime and ProjectALife.Runtime.metrics or {}
            for name, timing in pairs(runtimeMetrics.subsystems or {}) do
                lines[#lines + 1] = string.format(
                    "[ALIFE-QA] timing %-20s last=%dms max=%dms average=%.2fms calls=%d",
                    name, timing.lastMs, timing.maximumMs,
                    timing.totalMs / math.max(1, timing.calls), timing.calls)
            end

            for _, name in ipairs({ "FirstDays", "Stealth", "Health", "ModuleGunner",
                    "ModuleLeader", "ModuleWithdraw", "ModuleFear", "ModuleCover",
                    "ModuleConducts", "ModuleHealing", "Support", "HeliSearch", "HeliDirector", "BlackBox",
                    "DecisionLoop", "ActionLedger", "AIFence", "ShellSimulation", "Scavenging", "ScavengeRun", "Gossip",
                    "ChatterDirector", "ModuleTalkPresence",
                    "Talk", "Speech", "KnoxRadio", "NPCHitRelay", "ModuleRobbery",

                    "OutpostDirector", "OutpostBuilder", "OutpostGossip", "RoadGraph", "SceneKit", "RaidDirector",

                    "HordeRelations", "ScriptedEncounter",

                    "ProfileHydrator",

                    "RegionLocks",

                    "Campfires", "ModuleNightHold", "Perception", "StashRoom", "ExecutorHits", "CharacterReset",

                    "Gait", "ObstacleTraversal", "Combat", "HumanDamage",
                    "OfflineDirector", "RenderProtocol", "Population", "Persistence", "BaseHeat", "SpawnPolicy",
                    "ActivityService", "ActivityPlanner", "ModuleActivity",
                    "OrphanGuard", "Lifecycle", "DeathDrops",
                    "SpawnService", "SafehouseDirector", "SafehouseDoor", "SafehouseFx", "SafehouseVisit", "InteractionCues", "IntrusionCue", "Party", "PersonalRep", "NpcOpinion",
                    "ModulePanic", "ThreatWatch", "Discretion", "Standoff", "Wounds", "RoomSweep", "BodyLoot",
                    "ModuleGunFear", "Resistance",
                    "TownWelcome", "Havens", "CampLife",

                    "GroupSpread", "GroupLife",

                    "Movement", "Entrances", "ModuleBreach", "Risk",
                    "Fairness", "MeleeCrew", "ModuleWarning", "Blood", "ModuleRobbery", "Frisk", "EncounterScript" }) do
                local system = ProjectALife[name]
                if type(system) == "table" and type(system.metrics) == "table" then
                    local metrics = ""
                    for key, value in pairs(system.metrics) do

                        if type(value) == "table" then
                            local parts = {}
                            for reason, count in pairs(value) do
                                parts[#parts + 1] = tostring(reason) .. ":" .. tostring(count)
                            end
                            table.sort(parts)
                            value = "{" .. table.concat(parts, ";") .. "}"
                        end
                        metrics = metrics .. " " .. key .. "=" .. tostring(value)
                    end
                    if metrics ~= "" then lines[#lines + 1] = "[ALIFE-QA] " .. name .. ":" .. metrics end
                end
            end
            Service.qaExtraLines(lines)

            pcall(function()
                local encounter = ProjectALife.EncounterDirector
                if encounter ~= nil and type(encounter.qaLine) == "function" then
                    lines[#lines + 1] = "[ALIFE-QA] " .. encounter.qaLine()
                end
                lines[#lines + 1] = "[ALIFE-QA] " .. Service.encounterQaLine()
                local director = ProjectALife.Director
                if director ~= nil then
                    lines[#lines + 1] = "[ALIFE-QA] Director: window=" .. tostring(director.lastWindow)
                        .. " decision=" .. tostring(director.lastDecision)
                end
            end)

            local census = {}
            pcall(function()
                local watchdog = ProjectALife.Watchdog
                for index = 1, #watchdog.order do
                    local binding = watchdog.bindings[watchdog.order[index]]
                    local shell = binding and binding.shell or nil
                    if shell ~= nil then
                        local entry = { uid = tostring(watchdog.order[index]) }
                        pcall(function() entry.onlineId = shell:getOnlineID() end)
                        pcall(function() entry.remote = shell:isRemoteZombie() end)
                        pcall(function()
                            local owner = shell:getOwnerPlayer()
                            entry.owner = owner ~= nil and tostring(owner:getUsername()) or "none"
                        end)
                        pcall(function()
                            local square = shell:getCurrentSquare()
                            entry.inCell = square ~= nil and square:getMovingObjects():contains(shell) == true
                            entry.x, entry.y, entry.z = shell:getX(), shell:getY(), shell:getZ()
                        end)
                        census[#census + 1] = entry
                        lines[#lines + 1] = "[ALIFE-QA] ShellCensus: uid=" .. entry.uid
                            .. " onlineId=" .. tostring(entry.onlineId) .. " remote=" .. tostring(entry.remote)
                            .. " owner=" .. tostring(entry.owner) .. " inCell=" .. tostring(entry.inCell)
                            .. " pos=" .. Service.positionText(entry.x, entry.y, entry.z)
                            .. " " .. Service.snapshotText(shell, startedAt)
                        local blackbox = ProjectALife.BlackBox
                        if blackbox ~= nil and type(blackbox.relationLines) == "function" then
                            blackbox.relationLines(shell, lines)
                        end
                        if blackbox ~= nil and type(blackbox.hordeLines) == "function" then
                            blackbox.hordeLines(shell, lines)
                        end
                    end
                end
            end)
            pcall(function()
                local executor = ProjectALife.Executor
                if executor ~= nil then lines[#lines + 1] = "[ALIFE-QA] " .. executor.qaLine() end
            end)
            lines[#lines + 1] = "[ALIFE-QA] ==== end ===="
            pcall(function()
                local director = ProjectALife.SafehouseDirector
                if director ~= nil and type(director.diagnosticLines) == "function" then
                    local read, safehouse = pcall(director.diagnosticLines, player)
                    if read and type(safehouse) == "table" then
                        for index = 1, #safehouse do lines[#lines + 1] = "[ALIFE-QA] " .. safehouse[index] end
                    else lines[#lines + 1] = "[ALIFE-QA] Safehouse diagnostics: report_read_failed" end
                end
            end)
            print(table.concat(lines, "\n"))
            ProjectALife.BlackBox.saveReport("qa", table.concat(lines, "\n"))
            if type(isServer) == "function" and isServer() then
                pcall(sendServerCommand, "ProjectALife", "simulationQA", { shells = census })
            end
            Service.noteDumpCost("qa_dump", nowMs() - startedAt)
        end)
        reply(player, resultCommand, {
            ok = ok == true,
            reason = (not ok) and tostring(failure or "qa_dump_failed") or nil,

            where = Service.dumpDestination(),
        })
        return ok == true
    end

    if command == "debugSquadMap" then
        local groups, orderIds = {}, {}
        local mapAt, mapNow = playerPosition(player), nowMs()

        local rank = { combat = 4, warning = 3, moving = 2, idle = 1 }
        pcall(function()

            Registry.each(function(actor)
                if actor.lifecycle ~= "dead" and actor.worldPosition ~= nil then
                    local position = actor.worldPosition

                    local binding = Watchdog.bindings[actor.uid]
                    if binding ~= nil and binding.shell ~= nil then
                        pcall(function()
                            position = { x = binding.shell:getX(),
                                y = binding.shell:getY(), z = binding.shell:getZ() }
                        end)
                    end
                    local memory = type(actor.memory) == "table" and actor.memory or {}
                    local key = memory.groupId or ("solo:" .. actor.uid)
                    local group = groups[key]
                    if group == nil then
                        group = { x = 0, y = 0, members = 0, dormant = 0, bodyWaits = {}, active = false, rank = 0,
                            groupId = key, factionId = actor.factionId,
                            persistent = memory.persistent == true or memory.squadId ~= nil
                                or (type(memory.admin) == "table" and memory.admin.persistent == true)
                                or (memory.outpostId ~= nil and memory.outpostSquadId == nil) }
                        pcall(function()

                            local ledger = ProjectALife.SquadLedger
                            local squad = ledger ~= nil and type(ledger.read) == "function"
                                and ledger.read(memory.squadId or key) or nil
                            group.label = Service.squadLabel(actor.factionId, squad and squad.name)
                            if group.label == nil then
                                local profile = Catalog.npc(actor.profileId)
                                group.label = profile and profile.general
                                    and profile.general.name or actor.profileId
                            end
                        end)
                        group.task = Service.groupTask(memory)
                        groups[key] = group
                        orderIds[#orderIds + 1] = key
                    end
                    group.x = group.x + position.x
                    group.y = group.y + position.y
                    group.members = group.members + 1
                    if actor.lifecycle == "active" then group.active = true end
                    if actor.lifecycle == "dormant" then
                        group.dormant = group.dormant + 1
                        local wait = Service.bodyWait(actor, mapAt, mapNow)
                        local why = wait.reason
                        if #group.bodyWaits < 32 then group.bodyWaits[#group.bodyWaits + 1] = wait end
                        if group.holdReason == nil then group.holdReason = why
                        elseif group.holdReason ~= why then group.holdReason = "mixed" end
                    end
                    local activity = tostring(actor.activity or "idle")
                    if (rank[activity] or 0) >= group.rank then
                        group.rank = rank[activity] or 0
                        group.activity = Service.activityText(activity, actor.intent)
                    end
                end
            end)
        end)
        local squads = {}

        pcall(function()
            local registry = ProjectALife.OutpostRegistry
            if registry == nil or type(registry.list) ~= "function" then return end
            local hours
            pcall(function() hours = getGameTime():getWorldAgeHours() end)
            Service.appendSiteRows(squads, registry.list(), 64, hours)
        end)
        for _, key in ipairs(orderIds) do
            if #squads >= 128 then break end
            local group = groups[key]
            squads[#squads + 1] = {
                x = math.floor(group.x / group.members),
                y = math.floor(group.y / group.members),
                members = group.members,
                active = group.active,
                dormant = group.dormant,
                holdReason = group.holdReason,
                bodyWaits = group.bodyWaits,
                label = group.label,
                task = group.task,
                activity = group.activity,
                groupId = group.groupId,
                factionId = group.factionId,
                persistent = group.persistent == true,
            }
        end

        local marks = ProjectALife.SquadMapEncounters
        if marks ~= nil and type(marks.append) == "function" then pcall(marks.append, squads, 128) end
        reply(player, resultCommand, Service.squadMapReply(squads, playerPosition(player)))
        return true
    end
    if command == "debugPurgeArea" then

        reply(player, resultCommand, { ok = false, reason = "use_debugPurgeActors_radius" })
        return false
    end
    if command == "debugOutpostDelete" then
        return Service.outpostDelete(player, resultCommand, args)
    end
    if command == "debugSquadDelete" then
        return Service.squadDelete(player, resultCommand, args)
    end
    if command == "debugOutpostLights" then
        return Service.outpostLights(player, resultCommand, args)
    end
    if command == "debugOutpostSquadNow" or command == "debugOutpostDelay"
            or command == "debugOutpostSquadCap" then
        local director = ProjectALife.OutpostDirector
        local ok, reason, value = false, "outpost_director_unavailable", nil
        if director ~= nil then
            if command == "debugOutpostSquadNow" then
                ok, reason = director.adminSquadNow(args.siteId, player)
            elseif command == "debugOutpostDelay" then
                ok, reason, value = director.adminDelaySquad(args.siteId, args.hours)
            else
                ok, reason, value = director.adminSquadCap(args.siteId, args.delta)
            end
        end
        reply(player, resultCommand, { ok = ok == true, reason = reason, siteId = args.siteId, value = value })
        return ok == true
    end
    if command == "debugMetaEvent" then

        local meta = ProjectALife.MetaDirector
        local ok, reason = false, "meta_director_unavailable"
        if meta ~= nil and type(meta.debugFire) == "function" then
            ok, reason = meta.debugFire(args.kind, player)
        end
        reply(player, resultCommand, { ok = ok == true, reason = reason, kind = args.kind })
        return ok == true
    end
    if command == "debugBlackbox" then
        local count = 0
        local ok, failure = pcall(function()
            local blackBox = ProjectALife.BlackBox
            if blackBox == nil or type(blackBox.dumpAll) ~= "function" then
                error("blackbox_unavailable")
            end
            count = blackBox.dumpAll("menu") or 0
        end)
        reply(player, resultCommand, {
            ok = ok == true,
            reason = (not ok) and tostring(failure or "blackbox_dump_failed") or nil,
            count = count,
            where = Service.dumpDestination(),
        })
        return ok == true
    end
    if command == "debugTownCensus" then
        local count = 0
        local ok, failure = pcall(function()
            local census = Service.townCensus()
            local lines = Service.townCensusLines(census)
            count = #census.rows
            print(table.concat(lines, "\n"))
            ProjectALife.BlackBox.saveReport("towns", table.concat(lines, "\n"))
        end)
        reply(player, resultCommand, {
            ok = ok == true,
            reason = (not ok) and tostring(failure or "town_census_failed") or nil,
            count = count,
            where = Service.dumpDestination(),
        })
        return ok == true
    end
    if command == "debugDirectorState" then
        local director = ProjectALife.EncounterDirector
        local log = ProjectALife.EncounterLog
        reply(player, resultCommand, {
            ok = true,
            director = director ~= nil and {
                rolls = director.metrics and director.metrics.rolls or 0,
                spawned = director.metrics and director.metrics.spawned or 0,
                forfeits = director.metrics and director.metrics.forfeits or 0,
                lastOutcome = director.lastOutcome,
                enabled = director.enabled == true,
            } or nil,
            encounters = log ~= nil and log.live() or {},
        })
        return true
    elseif command == "debugEncounterMarks" then
        local log = ProjectALife.EncounterLog
        local list = log ~= nil and log.live() or nil
        reply(player, resultCommand, list ~= nil
            and { ok = true, encounters = list }
            or { ok = false, reason = "encounter_log_unavailable" })
        return list ~= nil
    elseif command == "debugEncounters" then
        local encounters = ProjectALife.Encounters
        local list = encounters ~= nil and encounters.list() or nil
        reply(player, resultCommand, list ~= nil
            and { ok = true, encounters = list }
            or { ok = false, reason = "encounters_unavailable" })
        return list ~= nil
    elseif command == "debugSpawnCatalog" then
        return Service.spawnCatalog(player, args)
    elseif command == "debugCatalog" then
        return Service.sendCatalogIndex(player, resultCommand)
    elseif command == "debugCatalogFaction" then
        return Service.sendCatalogFaction(player, resultCommand, args)
    elseif isSpawnCommand then
        local routed = clone(args)
        if spawnCommands[command] ~= "request" then routed.mode = spawnCommands[command] end
        local payload = spawn(player, routed, true)
        if payload == nil or payload.ok ~= true then
            pcall(function()
                player:Say("A-Life: spawn refused ("
                    .. tostring(payload and payload.reason or "unknown") .. ")")
            end)
        end
        reply(player, resultCommand, payload)
        return payload.ok == true
    elseif command == "debugDiagnostics" then
        local payload = Diagnostics.snapshot()
        payload.queuedAdminSpawns = #Service.queue
        payload.pendingAdminSpawns = #Service.pendingOrder
        payload.adminSpawnGroups = tableCount(Service.groups)
        reply(player, resultCommand, payload)
        return payload.ok == true
    elseif command == "debugRepAdjust" then
        local personal = ProjectALife.PersonalRep
        local reputation = ProjectALife.Reputation
        local delta = math.max(-50, math.min(50, math.floor(tonumber(args.delta) or 0)))
        local key = reputation ~= nil and type(reputation.playerKey) == "function" and reputation.playerKey(player) or nil
        local row = key ~= nil and personal ~= nil and type(personal.rowFor) == "function" and personal.rowFor(key, player, true) or nil
        if row == nil or type(personal.adjust) ~= "function" or delta == 0 then
            reply(player, resultCommand, { ok = false, delta = delta })
            return false
        end
        local before = row.score
        row.gained = 0
        local applied, from = personal.adjust(row, delta, personal.nowHours(), false)
        if type(personal.announce) == "function" then pcall(personal.announce, player, "debug", applied, from) end
        if type(reputation.sync) == "function" then pcall(reputation.sync, player) end
        print("[ALIFE-REP] debug delta=" .. tostring(delta) .. " applied=" .. tostring(applied)
            .. " score=" .. tostring(before) .. "->" .. tostring(row.score) .. " level=" .. tostring(row.level))
        reply(player, resultCommand, { ok = true, delta = delta, applied = applied, before = before,
            score = row.score, level = row.level })
        return true
    elseif command == "debugRepair" then
        local ok, repaired, failed, report = Diagnostics.repair()
        reply(player, resultCommand, {
            ok = ok, repaired = repaired, failed = failed, report = report,
        })
        return ok
    elseif command == "debugActors" then
        reply(player, resultCommand, actorPayload(player))
        return true
    elseif command == "debugAddNoSpawnZone" then
        local position = playerPosition(player)
        local zone, reason
        if position == nil then
            reason = "player_position_unavailable"
        else
            zone, reason = Registry.addNoSpawnZone({
                x = position.x, y = position.y, z = position.z,
                radius = math.max(1, math.min(200, tonumber(args.radius) or 20)),
                name = args.name or "Admin protected area",
                createdBy = playerKey(player),
            })
        end
        reply(player, resultCommand, { ok = zone ~= nil, zone = zone, reason = reason })
        return zone ~= nil
    elseif command == "debugClearNoSpawnZones" then
        local ok, value = Registry.clearNoSpawnZones()
        reply(player, resultCommand, {
            ok = ok, cleared = ok and value or 0, reason = (not ok) and value or nil,
        })
        return ok
    elseif command == "debugPurgeActors" then

        local removed, failed = 0, 0

        local radius = tonumber(args.radius)
        local originX, originY = tonumber(args.x), tonumber(args.y)
        if radius == nil or radius <= 0 or originX == nil or originY == nil then
            radius = nil
        else
            radius = math.min(1000, radius)
        end
        local subjects = Registry.list()
        if radius ~= nil then
            local within = {}
            for _, candidate in ipairs(subjects) do
                if Service.actorWithin(candidate, originX, originY, radius) then
                    within[#within + 1] = candidate
                end
            end
            subjects = within
        else
            Service.queue = {}
            Service.groups = {}
        end
        for _, actor in ipairs(subjects) do
            local binding = Watchdog.bindings[actor.uid]
            local shell = binding and binding.shell or nil
            pcall(function()
                Watchdog.unbind(actor.uid, actor.generation, "admin_purge")
            end)
            if shell ~= nil then
                pcall(function()
                    local adapter = ProjectALife.ShellAdapter
                    if adapter ~= nil and type(adapter.cleanupShell) == "function" then
                        adapter.cleanupShell(shell)
                    end
                end)
                pcall(function()
                    local guard = ProjectALife.AIFence
                    if guard ~= nil and type(guard.untrack) == "function" then
                        guard.untrack(shell)
                    end
                end)
                pcall(function()
                    shell:removeFromWorld()
                    shell:removeFromSquare()
                end)
            end

            pcall(function()
                local service = ProjectALife.SpawnService
                if service ~= nil and type(service.dehydrate) == "function" then
                    service.dehydrate(actor.uid, "admin_purge")
                end
            end)

            local fresh = Registry.read(actor.uid) or actor
            local ok = Registry.remove(fresh.uid, fresh.revision, "admin_purge")
            if ok then removed = removed + 1 else failed = failed + 1 end
        end

        reply(player, resultCommand, { ok = true, removed = removed, failed = failed, radius = radius,
            x = radius ~= nil and originX or nil, y = radius ~= nil and originY or nil })
        return true
    elseif command == "debugSyncCreator" then
        local transfer = ProjectALife.CreatorTransfer
        local profilesText, profileReason = args.profilesText, nil
        local factionsText, factionReason = args.factionsText, nil
        if args.profilesChunks ~= nil then profilesText, profileReason = transfer.join(args.profilesChunks, transfer.profileLimit) end
        if args.factionsChunks ~= nil then factionsText, factionReason = transfer.join(args.factionsChunks, transfer.factionLimit) end
        if profileReason ~= nil or factionReason ~= nil
                or type(profilesText) ~= "string" or type(factionsText) ~= "string" then
            reply(player, resultCommand, { ok = false, reason = profileReason or factionReason or "creator_text_required" })
            return false
        end
        local ok, reason = ProjectALife.CustomProfileAuthority.replaceCreator(profilesText, factionsText)
        reply(player, resultCommand, {
            ok = ok, profiles = ok, factions = ok, reloaded = ok, reason = reason,
        })
        return ok
    elseif command == "debugResetCreator" then

        local ok, reason = ProjectALife.CustomProfileAuthority.replaceCreator("", "")
        reply(player, resultCommand, {
            ok = ok, profiles = ok, factions = ok, reloaded = ok, reason = reason,
        })
        return ok
    end
    return false
end

function Service.onClientCommand(module, command, player, args)
    local runtime = ProjectALife.Runtime
    if module ~= "ProjectALife" or runtime == nil or type(runtime.timeHook) ~= "function" then
        return Service.handle(module, command, player, args)
    end
    local started = nowMs()
    local handled = runtime.timeHook("admin_command", Service.handle, module, command, player, args)
    local spent = nowMs() - started
    if spent > 16 and type(runtime.noteDetail) == "function" then
        runtime.noteDetail("admin_command:" .. tostring(command), spent)
    end
    return handled
end

function Service.register()
    if Service.registered or type(Events) ~= "table"
            or Events.OnClientCommand == nil then return false end
    Service.registered = true
    Events.OnClientCommand.Add(Service.onClientCommand)
    return true
end

function Service.outOfSeason(args)
    if type(args) ~= "table" then return nil end
    local ids = {}
    local wanted = Service.wantedFaction(args.factionId)
    if wanted ~= nil then ids[1] = wanted end
    local cast = type(args.profileIds) == "table" and args.profileIds or { args.profileId }
    for index = 1, math.min(#cast, 8) do
        local profile = type(cast[index]) == "string" and Catalog.npc(cast[index]) or nil
        local home = profile ~= nil and type(profile.general) == "table" and profile.general.faction or nil
        if home ~= nil then ids[#ids + 1] = home end
    end
    local day
    if type(getGameTime) == "function" then
        local time = getGameTime()
        local hours = time ~= nil and type(time.getWorldAgeHours) == "function"
            and tonumber(time:getWorldAgeHours()) or nil
        if hours ~= nil then day = hours / 24 end
    end
    local rules = ProjectALife.FactionSpawnRules
    for _, id in ipairs(ids) do
        if type(Catalog.deletedReason) == "function" and Catalog.deletedReason(id, nil) ~= nil then
            return "faction_deleted:" .. tostring(id)
        end
        local faction = Catalog.faction(id)
        if day ~= nil and faction ~= nil and rules ~= nil and type(rules.inSeason) == "function"
                and not rules.inSeason(faction, day) then
            return "faction_out_of_window:" .. tostring(id)
        end
    end
    return nil
end

function Service.censusGate(args)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusGate) ~= "function" then return nil end
    return census.censusGate(args)
end

function Service.spawnEncounter(player, args, allowAdminFlags)

    if type(args) == "table" then args.directed = true end

    if type(args) == "table" and allowAdminFlags ~= true and args.adminPick ~= true then
        local refused = Service.outOfSeason(args)
        if refused == nil then refused = Service.censusGate(args) end
        if refused ~= nil then
            return false, refused, { ok = false, reason = refused, requestId = args.requestId,
                accepted = 0, failed = 0 }
        end
    end
    local visitStamp = nil
    if type(args) == "table" and args.origin == "director" and type(args.visit) == "table" then
        local visit = ProjectALife.SafehouseVisit
        if visit == nil or type(visit.spawnStamp) ~= "function" then return false, "visit_unavailable" end
        visitStamp = visit.spawnStamp(args.visit.house, args.visit.pendingId)
        if visitStamp == nil then return false, "visit_stamp_refused" end
    end
    local result = spawn(player, type(args) == "table" and args or {}, allowAdminFlags == true, visitStamp)

    if type(result) == "table" then
        return result.ok == true, result.reason, result
    end
    return result == true, nil, result
end

Service.authorizedPlayer = authorized
Service.playerKeyOf = playerKey
Service.sendReply = reply
Service.rawSpawn = spawn
Service.requestedOriginOf = requestedOrigin
Service.encounterDefinitionOf = encounterDefinition
Service.clockMs = nowMs
Service.playerAt = playerPosition

return Service
