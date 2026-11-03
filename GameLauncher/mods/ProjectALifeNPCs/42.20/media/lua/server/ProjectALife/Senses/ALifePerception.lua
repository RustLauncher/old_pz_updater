require "ProjectALife/Senses/ALifeFoliage"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Decisions/ALifeRelations"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Core/ALifePlayerLocator"
require "ProjectALife/Decisions/ALifeTargetPolicy"
require "ProjectALife/Combat/ALifeSquadTactics"
require "ProjectALife/Combat/ALifeLineOfFire"
require "ProjectALife/Senses/ALifeAwareness"
require "ProjectALife/Senses/ALifeSight"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Relations = ProjectALife.Relations
local Registry = ProjectALife.ActorRegistry
local PlayerLocator = ProjectALife.PlayerLocator
local TargetPolicy = ProjectALife.TargetPolicy
local Tactics = ProjectALife.SquadTactics
local Perception = {
    adapters = {}, cursors = {}, maximumZombieCandidates = 48,

    blindSpotFromTiles = 3,

    fieldOfViewDegrees = 180,
    alertFieldOfViewDegrees = 240,

    maximumSightChecks = 12,

    maximumActorSightChecks = 8,

    dangerRingSquared = 64,
    zombieUrgency = 1.25,

    nightCap = 12,
    nightCapFlashlight = 20,
    nightLitLift = 0.55,

    zombieStealRatio = 0.6,

    hordeCount = 3,
    hordeStealRatio = 0.85,

    zombieReachMelee = 14,
    zombieReachHandgun = 24,
    zombieReachRifle = 40,
    zombieHoldFactor = 1.4,

    replicaGraceMs = 1000,

    engagements = {},

    persons = {},

    ignored = {},

    lastKnown = {},

    contactReportAtMs = {},

    handOffAtMs = {},

    attackers = {},

    targetLogAtMs = {},
}
ProjectALife.Perception = Perception

Perception.legacyPicker = false

function Perception.ignore(actorUid, target, holdMs)
    if type(actorUid) ~= "string" or target == nil then return end
    local now = type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000)
    local set = Perception.ignored[actorUid]
    if type(set) ~= "table" then
        set = setmetatable({}, { __mode = "k" })
        Perception.ignored[actorUid] = set
    end
    set[target] = now + (tonumber(holdMs) or 15000)
end

function Perception.forgetIgnored(actorUid)
    Perception.ignored[actorUid] = nil
end

function Perception.forgetActor(actorUid)
    Perception.ignored[actorUid] = nil
    Perception.engagements[actorUid] = nil
    Perception.lastKnown[actorUid] = nil
    Perception.attackers[actorUid] = nil
    Perception.targetLogAtMs[actorUid] = nil
end

local function isIgnored(actorUid, candidate, now)
    local set = Perception.ignored[actorUid]
    if type(set) ~= "table" then return false end
    local untilMs = set[candidate]
    if untilMs == nil then return false end
    if now >= untilMs then
        set[candidate] = nil
        return false
    end
    return true
end

Perception.grudgeShieldMs = 10000

function Perception.refreshAttacker(victimUid, attacker, holdMs)
    local held = Perception.attackers[victimUid]
    if type(held) ~= "table" or held.attacker ~= attacker then return false end
    local now = type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000)
    local liveUntil = tonumber(held.untilMs) or 0
    if now >= liveUntil then return false end
    local duration = tonumber(holdMs) or 5000
    local untilMs = duration == math.huge and math.huge or now + duration
    if untilMs > liveUntil then held.untilMs = untilMs end

    held.atMs = now

    Perception.forgetIgnored(victimUid)
    return true
end

function Perception.noteAttacker(victimUid, attacker, holdMs, kind)
    if type(victimUid) ~= "string" or attacker == nil then return end
    if Perception.refreshAttacker(victimUid, attacker, holdMs) then return end

    local marked, proven = false, false
    pcall(function()
        local data = attacker:getModData()
        marked = type(data) == "table" and data.ProjectALifeOwned == true
        if not marked then return end
        local uid = data.ProjectALifeUID
        if type(uid) ~= "string" then return end
        local registry, relations = ProjectALife.ActorRegistry, ProjectALife.Relations
        if registry == nil or relations == nil then return end
        local look = registry.peek or registry.read
        local victim, aggressor = look(victimUid), look(uid)
        if victim == nil or aggressor == nil then return end

        if type(relations.sameSide) == "function"
                and relations.sameSide(victim, aggressor) then return end
        if relations.status(victim, aggressor) == "friendly"
                and relations.status(aggressor, victim) ~= "hostile" then return end
        proven = true
        if type(relations.provoke) == "function" then
            relations.provoke(victim, aggressor)
        end
    end)
    if marked and not proven then return end
    Perception.forgetIgnored(victimUid)
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and decisions.passiveQuietAtMs ~= nil then decisions.passiveQuietAtMs[victimUid] = nil end
    local now = type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000)
    kind = kind or "zombie"

    local held = Perception.attackers[victimUid]
    if kind == "zombie" and type(held) == "table" and held.kind ~= "zombie"
            and now < math.min(tonumber(held.untilMs) or 0,
                (tonumber(held.atMs) or 0) + Perception.grudgeShieldMs)
            and not (Perception.has(held.attacker, "isDead")
                and held.attacker:isDead() == true) then
        Perception.metrics = Perception.metrics or {}
        Perception.metrics.zombieGrudgeRefused =
            (Perception.metrics.zombieGrudgeRefused or 0) + 1
        return
    end
    local duration = tonumber(holdMs) or 5000
    Perception.attackers[victimUid] = {
        attacker = attacker,
        kind = kind,
        atMs = now,
        untilMs = duration == math.huge and math.huge or now + duration,
    }
end
ProjectALife.Perception = Perception

function Perception.has(body, method)
    local kind = type(body)
    return (kind == "table" or kind == "userdata") and body[method] ~= nil
end

function Perception.isPlayer(body)
    return body ~= nil and type(instanceof) == "function" and instanceof(body, "IsoPlayer") == true
end

function Perception.dataOf(body)
    if not Perception.has(body, "getModData") then return nil end
    if body.hasModData ~= nil and body:hasModData() ~= true then return nil end
    local data = body:getModData()
    if type(data) ~= "table" then return nil end
    return data
end

function Perception.zombieReach(shell, range)
    local data = Perception.dataOf(shell)
    local class = data ~= nil and data.ProjectALifeWeaponClass or nil
    local reach = Perception.zombieReachMelee
    if class == "rifle" then reach = Perception.zombieReachRifle
    elseif class == "handgun" then reach = Perception.zombieReachHandgun end
    range = tonumber(range) or reach
    return math.min(range, reach)
end

function Perception.xyzOf(body)
    if not Perception.has(body, "getX") or body.getY == nil or body.getZ == nil then return nil end
    return body:getX(), body:getY(), body:getZ()
end

function Perception.xyOf(body)
    if not Perception.has(body, "getX") or body.getY == nil then return nil end
    return body:getX(), body:getY()
end

function Perception.eitherWay(a, b, method)
    if a[method] == nil then return nil, false end
    local found = a[method](a, b)
    if found then return found, true end
    if b[method] == nil then return nil, false end
    return b[method](b, a), true
end

local function size(list)
    if not Perception.has(list, "size") then return 0 end
    return list:size() or 0
end

local function at(list, index)
    if not Perception.has(list, "get") then return nil end
    return list:get(index)
end

local function alive(candidate)
    if not Perception.has(candidate, "isDead") or candidate:isDead() == true then return false end

    if TargetPolicy.grappledCorpse(candidate) then return false end
    local healthOk = candidate.getHealth ~= nil
    local health = healthOk and candidate:getHealth() or nil
    if healthOk and tonumber(health) ~= nil and health <= 0 then return false end
    local data = Perception.dataOf(candidate)
    local owned = data ~= nil and (data.ProjectALifeOwned == true
        or data.ProjectALifeActor == true)
    if candidate.isOnKillDone ~= nil and candidate:isOnKillDone() == true
            and not (owned and healthOk and (tonumber(health) or 0) > 0) then return false end
    return true
end

local activeActorForShell

function Perception.retaliationTarget(victimUid, suppliedNow)
    local entry = type(victimUid) == "string" and Perception.attackers[victimUid] or nil
    if entry == nil then return nil end
    local now = tonumber(suppliedNow) or (type(getTimestampMs) == "function"
        and getTimestampMs() or math.floor(os.time() * 1000))
    if now >= entry.untilMs or not alive(entry.attacker)
            or isIgnored(victimUid, entry.attacker, now) then
        Perception.attackers[victimUid] = nil
        return nil
    end
    local targetActor, owned = activeActorForShell(entry.attacker)
    if (owned and targetActor == nil)
            or TargetPolicy.canAttack(entry.attacker, nil, victimUid) ~= true then
        Perception.attackers[victimUid] = nil
        return nil
    end
    return entry.attacker, entry.kind or "zombie"
end

local function actorShell(candidate)
    local data = Perception.dataOf(candidate)
    if data ~= nil and data.ProjectALifeOwned == true then return true, data.ProjectALifeUID end
    if not Perception.has(candidate, "GetVariable") then return false, nil end
    if tostring(candidate:GetVariable("ALifeActor")) ~= "true" then return false, nil end
    return true, candidate:GetVariable("ALifeUID")
end

activeActorForShell = function(candidate)
    local owned, uid = actorShell(candidate)
    if not owned then return nil, false end

    local actor = type(uid) == "string" and (Registry.peek or Registry.read)(uid) or nil
    if actor == nil or actor.lifecycle ~= "active" then return nil, true end
    local watchdog = ProjectALife.Watchdog
    local bindings = watchdog and watchdog.bindings or nil
    local binding = type(bindings) == "table" and bindings[uid] or nil
    if binding ~= nil and binding.shell == candidate
            and binding.generation == actor.generation then
        return actor, true
    end

    if binding == nil and type(isClient) == "function" and isClient() then
        local generation
        pcall(function()
            generation = tonumber(candidate:getModData().ProjectALifeGeneration)
            if generation == nil and candidate.GetVariable ~= nil then
                generation = tonumber(candidate:GetVariable("ALifeGeneration"))
            end
        end)
        if generation == actor.generation then return actor, true end
    end

    if watchdog == nil then return actor, true end
    return nil, true
end

Perception.activeActorForShell = activeActorForShell

function Perception.grudgeHolds(uid, body, now)
    local grudge = type(uid) == "string" and Perception.attackers[uid] or nil
    if type(grudge) ~= "table" or body == nil or grudge.attacker ~= body then return false end
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000))
    return now < (tonumber(grudge.untilMs) or 0)
end

function Perception.bitBy(shell, body, now)
    local owned, uid = actorShell(shell)
    return owned and Perception.grudgeHolds(uid, body, now)
end

function Perception.replicaIdentity(body, now)
    if type(isClient) ~= "function" or isClient() ~= true then return nil end
    if not Perception.has(body, "getOnlineID") then return nil end

    if Perception.isPlayer(body) then return nil end
    local id = body:getOnlineID()
    if id == nil or id == -1 then return nil end
    local client = ProjectALife.AnimationClient
    if type(client) ~= "table" then return nil end
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs() or 0)

    local key = type(client.pendingByOnline) == "table" and client.pendingByOnline[id] or nil
    local message = key ~= nil and type(client.pending) == "table" and client.pending[key] or nil
    if type(message) == "table" and now < (tonumber(message.deadlineAtMs) or math.huge) then
        if type(message.uid) == "string" then return message.uid end
        return ""
    end
    key = type(client.onlineIdentity) == "table" and client.onlineIdentity[id] or nil
    if type(key) == "string" then
        local uid, generation = string.match(key, "^uid:(.+):([^:]*)$")
        local record = uid ~= nil and (Registry.peek or Registry.read)(uid) or nil
        if record ~= nil and record.lifecycle == "active"
                and tonumber(record.generation) == tonumber(generation) then
            return uid
        end
    end

    if type(client.announcedIdentity) == "function" then
        local leased, leasedGeneration = client.announcedIdentity(id, now)
        local leasedRecord = leased ~= nil and (Registry.peek or Registry.read)(leased) or nil
        if leasedRecord ~= nil and leasedRecord.lifecycle == "active"
                and tonumber(leasedRecord.generation) == leasedGeneration then
            return leased
        end
    end

    if (tonumber(client.observedCount) or 0) <= 0 or type(client.replicaAgeMs) ~= "function" then
        return nil
    end
    local age = client.replicaAgeMs(body, now)
    if age == nil or (age >= 0 and age < Perception.replicaGraceMs) then return "" end
    return nil
end

function Perception.knownReplica(body, now)
    return Perception.replicaIdentity(body, now) ~= nil
end

function Perception.comrade(actor, body)
    if type(actor) ~= "table" or body == nil then return false end
    if Perception.isPlayer(body) then return false end
    local owned, uid = actorShell(body)
    if not owned then
        uid = Perception.replicaIdentity(body)
        if uid == nil then return false end
        if uid == "" then return not Perception.grudgeHolds(actor.uid, body) end
    elseif type(uid) ~= "string" then
        return false
    end
    local record = (Registry.peek or Registry.read)(uid)
    if record == nil then return true end
    if Relations.hostile(actor, record) then return false end
    return not Perception.grudgeHolds(actor.uid, body)
end

function Perception.isComrade(shell, body)
    if shell == nil or body == nil or shell == body then return false end
    local owned, uid = actorShell(shell)
    if not owned or type(uid) ~= "string" then return false end
    local actor = (Registry.peek or Registry.read)(uid)
    if actor == nil then return false end
    return Perception.comrade(actor, body) == true
end

function Perception.boardKind(body, kind, now)
    if body == nil or kind ~= "zombie" then return body, kind end
    if actorShell(body) then return body, "actor" end
    if Perception.knownReplica(body, now) then return nil, nil end
    return body, kind
end

function Perception.riskAllows(actor, shell, body, kind)
    if kind ~= "player" and kind ~= "actor" then return true end
    local risk = ProjectALife.Risk
    if risk == nil or type(risk.mayInitiate) ~= "function" then return true end
    return risk.mayInitiate(actor, shell, body, kind) == true
end

function Perception.reportedBeyond(shell, entry, limit2)
    local point = type(entry) == "table" and entry.position or nil
    local px = type(point) == "table" and tonumber(point.x) or nil
    local py = type(point) == "table" and tonumber(point.y) or nil
    local sx, sy = Perception.xyOf(shell)
    if px == nil or py == nil or sx == nil then return false end
    return (px - sx) ^ 2 + (py - sy) ^ 2 > limit2
end

Perception.targetLogMs = 3000

function Perception.targetLinesOn()
    local box = ProjectALife.BlackBox
    return type(box) == "table" and box.enabled == true
end

function Perception.logIdOf(target, uid)
    if uid ~= nil then return tostring(uid) end
    if Perception.has(target, "getOnlineID") then
        local online = target:getOnlineID()
        if online ~= nil and online ~= -1 then return "online:" .. tostring(online) end
    end
    local id = Perception.has(target, "getID") and tonumber(target:getID()) or nil
    if id == nil then id = tonumber(string.match(tostring(target), "ID:%s*(%-?%d+)")) end
    return id ~= nil and string.format("obj:%d", math.floor(id)) or "?"
end

function Perception.logTarget(actor, target, kind, via, now, shell)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or target == nil then return false end
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000))
    via = tostring(via or "pick")
    local stamps = Perception.targetLogAtMs[actor.uid]
    if stamps == nil then
        stamps = {}
        Perception.targetLogAtMs[actor.uid] = stamps
    end
    local last = stamps[via]
    if last ~= nil and now >= last and now - last < Perception.targetLogMs then return false end
    stamps[via] = now
    if not Perception.targetLinesOn() then
        local metrics = Perception.metrics or {}
        Perception.metrics = metrics
        metrics.targetLinesSuppressed = (metrics.targetLinesSuppressed or 0) + 1
        return false
    end
    local owned, uid = actorShell(target)
    local id = Perception.logIdOf(target, uid)
    local relation = "-"
    if owned then
        local record = type(uid) == "string" and (Registry.peek or Registry.read)(uid) or nil
        relation = record ~= nil and tostring(Relations.status(actor, record)) or "norecord"
    elseif kind == "player" and type(Relations.playerStance) == "function" then
        relation = tostring(Relations.playerStance(actor, target))
    end
    if shell == nil then
        local watchdog = ProjectALife.Watchdog
        local binding = watchdog ~= nil and type(watchdog.bindings) == "table"
            and watchdog.bindings[actor.uid] or nil
        shell = binding ~= nil and binding.shell or nil
    end
    local x, y = Perception.xyOf(target)
    local sx, sy = Perception.xyOf(shell)
    local dist = "?"
    if x ~= nil and sx ~= nil then
        dist = string.format("%.1f", math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2))
    end
    pcall(print, "[ALIFE-COMBAT] target shooter=" .. actor.uid
        .. " kind=" .. tostring(kind or "?") .. " target=" .. id
        .. " owned=" .. (owned and "yes" or "no") .. " relation=" .. relation
        .. " via=" .. via
        .. " at=" .. (x ~= nil and (math.floor(x) .. "," .. math.floor(y)) or "?")
        .. " dist=" .. dist)
    return true
end

local function distanceSquared(shell, candidate)
    local sx, sy, sz = Perception.xyzOf(shell)
    local cx, cy, cz = Perception.xyzOf(candidate)
    if sx == nil or cx == nil then return math.huge end
    local dx, dy, dz = sx - cx, sy - cy, sz - cz
    return dx * dx + dy * dy + dz * dz
end

Perception.sightWindowMs = 33
Perception.sightChecksPerPass = 48
Perception.sightReentryHoldMs = 250
Perception.sightFaultHoldMs = 3000
Perception.sightPass = 0
Perception.weakKeys = { __mode = "k" }
Perception.metrics = Perception.metrics or {}
Perception.metrics.sightReentered = Perception.metrics.sightReentered or 0
Perception.metrics.sightFaults = Perception.metrics.sightFaults or 0
Perception.metrics.sightCapped = Perception.metrics.sightCapped or 0

function Perception.sightFrame(now)
    local frame = Perception.sightFrameTable
    if frame == nil or now < frame.atMs or now - frame.atMs >= Perception.sightWindowMs then
        frame = {
            atMs = now, queries = 0,
            answers = setmetatable({}, Perception.weakKeys),
            raw = setmetatable({}, Perception.weakKeys),
        }
        Perception.sightFrameTable = frame
    end
    return frame
end

function Perception.forgetSight()
    Perception.sightFrameTable = nil
    Perception.sightPass = (Perception.sightPass or 0) + 1
end

function Perception.rememberedSight(map, shell, candidate)
    local byTarget = map[shell]
    if byTarget == nil then return nil end
    return byTarget[candidate]
end

function Perception.rememberSight(map, shell, candidate, answer)
    local byTarget = map[shell]
    if byTarget == nil then
        byTarget = setmetatable({}, Perception.weakKeys)
        map[shell] = byTarget
    end
    byTarget[candidate] = answer
    return answer
end

function Perception.countSight(field)
    local metrics = Perception.metrics
    if metrics == nil then
        metrics = {}
        Perception.metrics = metrics
    end
    metrics[field] = (metrics[field] or 0) + 1
end

function Perception.sightByContact(shell, candidate)
    if distanceSquared(shell, candidate) > 2.25 then return false end
    local shellSquare, candidateSquare = Perception.squaresOnOneLevel(shell, candidate)
    if shellSquare == nil then return false end
    local blocked, asked = Perception.eitherWay(shellSquare, candidateSquare, "isBlockedTo")
    return asked and blocked ~= true
end

function Perception.sightRay(shell, candidate)
    local sight = ProjectALife.Sight
    if sight == nil or type(sight.between) ~= "function" then return nil end
    local ok, classification = pcall(function()
        return sight.between(shell:getX(), shell:getY(), shell:getZ(),
            candidate:getX(), candidate:getY(), candidate:getZ())
    end)
    return ok and classification or nil
end

function Perception.engineCanSee(shell, candidate, now, frame)
    if not Perception.has(shell, "CanSee") or candidate == nil then
        return nil, "unavailable"
    end
    now = tonumber(now)
    if now == nil then
        now = type(getTimestampMs) == "function" and getTimestampMs()
            or math.floor(os.time() * 1000)
    end
    frame = frame or Perception.sightFrame(now)
    local remembered = Perception.rememberedSight(frame.raw, shell, candidate)
    if remembered == "door" then return false, "door" end
    if remembered ~= nil then return remembered end
    local busy = Perception.sightBusyAtMs
    if busy ~= nil then
        if now - busy < Perception.sightReentryHoldMs then

            Perception.countSight("sightReentered")
            return nil, "held"
        end

        Perception.sightBusyAtMs = nil
        Perception.sightFaultUntilMs = now + Perception.sightFaultHoldMs
        Perception.countSight("sightFaults")
    end
    if now < (Perception.sightFaultUntilMs or -1e12) then return nil, "ray" end
    if frame.queries >= Perception.sightChecksPerPass then
        Perception.countSight("sightCapped")
        return nil, "held"
    end
    frame.queries = frame.queries + 1
    Perception.sightBusyAtMs = now
    local ok, result = pcall(shell.CanSee, shell, candidate)
    local classification = ok and result == true and Perception.sightRay(shell, candidate) or nil
    Perception.sightBusyAtMs = nil
    if not ok then
        Perception.sightFaultUntilMs = now + Perception.sightFaultHoldMs
        Perception.countSight("sightFaults")
        return nil, "ray"
    end
    if classification == "door" then
        Perception.rememberSight(frame.raw, shell, candidate, "door")
        return false, "door"
    end
    return Perception.rememberSight(frame.raw, shell, candidate, result == true)
end

local function visible(shell, candidate)
    if shell == nil or candidate == nil then return false end
    local now = type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000)
    local frame = Perception.sightFrame(now)
    local remembered = Perception.rememberedSight(frame.answers, shell, candidate)
    if remembered ~= nil then return remembered end

    local seen, why = Perception.engineCanSee(shell, candidate, now, frame)
    if seen == true then
        return Perception.rememberSight(frame.answers, shell, candidate, true)
    end
    if why == "door" then
        return Perception.rememberSight(frame.answers, shell, candidate, false)
    end
    if why == "held" then

        return Perception.sightByContact(shell, candidate)
    end

    local line = ProjectALife.LineOfFire
    local classification = Perception.sightRay(shell, candidate)
    if classification == "door" then
        return Perception.rememberSight(frame.answers, shell, candidate, false)
    end
    local ray = classification ~= nil and classification == "clear" or nil
    if classification == "blocked" then ray = false end
    if classification == nil and line ~= nil and type(line.tileRayClear) == "function" then
        ray = line.tileRayClear(shell, candidate)
    end
    if ray == true then
        return Perception.rememberSight(frame.answers, shell, candidate, true)
    end
    if ray == false then

        return Perception.rememberSight(frame.answers, shell, candidate,
            line ~= nil and type(line.hasClearBoundary) == "function"
                and line.hasClearBoundary(shell, candidate, true) == true)
    end
    return Perception.rememberSight(frame.answers, shell, candidate,
        Perception.sightByContact(shell, candidate))
end

function Perception.squaresOnOneLevel(shell, candidate)
    if not Perception.has(shell, "getZ") or not Perception.has(candidate, "getZ")
            or shell.getCurrentSquare == nil or candidate.getCurrentSquare == nil
            or math.abs(shell:getZ() - candidate:getZ()) >= 0.4 then
        return nil
    end
    local shellSquare, candidateSquare = shell:getCurrentSquare(), candidate:getCurrentSquare()
    if shellSquare == nil or candidateSquare == nil then return nil end
    return shellSquare, candidateSquare
end

local function alertness(actor)
    local id = tostring(actor and actor.uid or "")
    local seed = 0
    for index = 1, #id do
        seed = (seed * 31 + string.byte(id, index)) % 2147483647
    end
    return (seed % 100) / 100
end

Perception.sightTiles = 30
Perception.paceVisibility = { still = 0.8, walk = 1, run = 1.35, sprint = 1.7 }
Perception.sneakVisibility = 0.55
Perception.foliageVisibility = 0.7

function Perception.lightAt(square, fallback)
    fallback = tonumber(fallback) or 0.6
    if type(isServer) == "function" and isServer() == true then
        local ok, light = pcall(function()
            local climate = type(getClimateManager) == "function" and getClimateManager() or nil
            if climate == nil and ClimateManager ~= nil and type(ClimateManager.getInstance) == "function" then climate = ClimateManager.getInstance() end
            if climate == nil or type(climate.getDayLightStrength) ~= "function" or type(climate.getAmbient) ~= "function" then return nil end
            return math.min(climate:getDayLightStrength(), climate:getAmbient())
        end)
        if ok and tonumber(light) ~= nil then return math.max(0, math.min(1, tonumber(light))) end
        return fallback
    end
    local ok, light = pcall(function()
        return square ~= nil and square.getLightLevel ~= nil and square:getLightLevel(0) or nil
    end)
    return ok and tonumber(light) or fallback
end

function Perception.visibleRange(candidate, watcherAlertness)
    local light, pace, sneaking, square = 0.6, "walk", false, nil
    if Perception.has(candidate, "getSquare") then
        square = candidate:getSquare()
    end
    light = Perception.lightAt(square, light)
    if Perception.has(candidate, "isSprinting") then
        if candidate:isSprinting() then pace = "sprint"
        elseif candidate.isRunning ~= nil then
            if candidate:isRunning() then pace = "run"
            elseif candidate.isPlayerMoving ~= nil and candidate:isPlayerMoving() == false then
                pace = "still"
            end
        end
    end
    sneaking = Perception.has(candidate, "isSneaking") and candidate:isSneaking() == true
    if not sneaking and ProjectALife.SneakProfile ~= nil then
        sneaking = ProjectALife.SneakProfile.sneaking(candidate)
    end
    local visibility = math.max(0.05, math.min(1, light)) * (Perception.paceVisibility[pace] or 1)
    if sneaking then
        visibility = visibility * Perception.sneakVisibility
        local foliage = ProjectALife.Foliage
        if square ~= nil and foliage ~= nil and foliage.on(square) then
            visibility = visibility * Perception.foliageVisibility
        end
    end
    local alert = math.max(0, math.min(1, tonumber(watcherAlertness) or 0.5))
    return Perception.sightTiles * visibility * (0.7 + 0.6 * alert)
end

function Perception.concealment(candidate)
    if type(Perception.adapters.concealment) == "function" then
        return tonumber(Perception.adapters.concealment(candidate)) or 1
    end
    local factor = 1
    local climate = type(getClimateManager) == "function" and getClimateManager() or nil
    if climate ~= nil and climate.getFogIntensity ~= nil and climate.getRainIntensity ~= nil then
        local fog = math.max(0, math.min(1, tonumber(climate:getFogIntensity()) or 0))
        local rain = math.max(0, math.min(1, tonumber(climate:getRainIntensity()) or 0))
        factor = factor * (1 - 0.5 * fog) * (1 - 0.25 * rain)
    end
    if CharacterTrait ~= nil and CharacterTrait.INCONSPICUOUS ~= nil
            and CharacterTrait.CONSPICUOUS ~= nil and Perception.has(candidate, "hasTrait") then
        if candidate:hasTrait(CharacterTrait.INCONSPICUOUS) == true then
            factor = factor * 0.75
        elseif candidate:hasTrait(CharacterTrait.CONSPICUOUS) == true then
            factor = factor * 1.25
        end
    end
    return factor
end

function Perception.inView(shell, candidate, degrees)

    if not Perception.has(shell, "getForwardDirection") then return true end
    local sx, sy = Perception.xyOf(shell)
    local cx, cy = Perception.xyOf(candidate)
    local forward = sx ~= nil and cx ~= nil and shell:getForwardDirection() or nil
    if forward == nil then return true end
    local fx, fy = forward:getX(), forward:getY()
    local dx, dy = cx - sx, cy - sy
    local f, d = math.sqrt(fx * fx + fy * fy), math.sqrt(dx * dx + dy * dy)
    if f < 0.001 or d < 0.001 then return true end
    return (fx * dx + fy * dy) / (f * d)
        >= math.cos(math.rad((tonumber(degrees) or 180) * 0.5))
end

function Perception.fieldOfViewFor(shell)
    local data = Perception.dataOf(shell)
    if data == nil or type(getTimestampMs) ~= "function" then return Perception.fieldOfViewDegrees end
    local last = math.max(tonumber(data.ProjectALifeLastShotAtMs) or -1,
        tonumber(data.ProjectALifeLastHitAtMs) or -1)
    if last >= 0 and getTimestampMs() - last < 10000 then
        return Perception.alertFieldOfViewDegrees
    end
    return Perception.fieldOfViewDegrees
end

local function playerNoticed(actor, shell, candidate, distance)
    local hearing = ProjectALife.Investigation
    if hearing ~= nil and type(hearing.peripheral) == "function" and hearing.peripheral(actor, shell, candidate, distance, type(getTimestampMs) == "function" and getTimestampMs() or 0) then
        hearing.alert(actor, "red", type(getTimestampMs) == "function" and getTimestampMs() or 0)
        return true
    end

    if distance <= Perception.blindSpotFromTiles then return true end
    if not Perception.inView(shell, candidate, Perception.fieldOfViewFor(shell)) then
        return false
    end
    return Perception.playerInSightRange(actor, candidate, distance)
end

function Perception.playerInSightRange(actor, candidate, distance)
    if distance <= Perception.blindSpotFromTiles then return true end
    distance = distance / math.max(0.3, Perception.concealment(candidate))
    return distance <= Perception.visibleRange(candidate, alertness(actor))
end

local function playerList()
    return PlayerLocator.list(Perception.adapters.players)
end

local function isNight()
    local clock = type(getGameTime) == "function" and getGameTime() or nil
    local hour = clock ~= nil and clock.getHour ~= nil and clock:getHour() or nil
    if hour == nil then return false end
    return hour >= 22 or hour < 6
end

local function nightAwarenessOk(actor, shell, candidate, flat)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) == "table" and memory.nightvision == true then return true end
    if not isNight() then return true end
    if Perception.attackers[actor.uid] ~= nil
            or Perception.engagements[actor.uid] ~= nil then
        return true
    end
    local square = candidate ~= nil and candidate.getSquare ~= nil and candidate:getSquare() or nil
    local lit = Perception.lightAt(square, 0) >= (Perception.nightLitLift or 0.55)
    if lit then return true end
    local adapter = ProjectALife.ShellAdapter
    local torch = type(memory) == "table" and memory.flashlight == true
    if not torch and adapter ~= nil and type(adapter.carriesLight) == "function" then
        torch = adapter.carriesLight(actor) == true
    end
    local cap = torch and (Perception.nightCapFlashlight or 20) or (Perception.nightCap or 12)
    return flat <= cap * cap
end

function Perception.actorAwarenessOk(actor, shell, candidate, flat)
    return (flat <= Perception.blindSpotFromTiles * Perception.blindSpotFromTiles
        or Perception.inView(shell, candidate, Perception.fieldOfViewFor(shell)))
        and nightAwarenessOk(actor, shell, candidate, flat)
end

Perception.calmFloorTiles = 1.5
Perception.hostileAwakeShare = 0.7
Perception.awakeFromShare = 0.25
local function calmAwarenessOk(actor, candidate, flat, now, shell)
    local memory = type(actor) == "table" and actor.memory or nil
    local raw = type(memory) == "table" and memory.stanceAwareness or nil
    if tonumber(raw) == nil then return true end
    if Perception.attackers[actor.uid] ~= nil
            or Perception.engagements[actor.uid] ~= nil then
        return true
    end
    local hearing = ProjectALife.Investigation
    if shell ~= nil and hearing ~= nil and type(hearing.peripheral) == "function" and hearing.peripheral(actor, shell, candidate, math.sqrt(flat), now) then return true end
    local awareness = ProjectALife.Awareness
    local share = awareness ~= nil and awareness.shareFor(memory, raw, Perception.sightTiles) or math.min(1, tonumber(raw))
    if share >= Perception.awakeFromShare and share < Perception.hostileAwakeShare then
        share = Perception.hostileAwakeShare
    end
    local reach = math.max(Perception.calmFloorTiles, share * Perception.visibleRange(candidate, alertness(actor)))
    return flat <= reach * reach
end

function Perception.configure(adapters)
    Perception.adapters = adapters or {}
    Perception.zombieSnapshot = nil

    Perception.forgetSight()
    Perception.sightBusyAtMs = nil
    Perception.sightFaultUntilMs = nil
    Perception.metrics = Perception.metrics or {}
    Perception.metrics.sightReentered = 0
    Perception.metrics.sightFaults = 0
    Perception.metrics.sightCapped = 0
    Perception.cursors = {}
    Perception.engagements = {}
    Perception.persons = {}
    Perception.maximumZombieCandidates = math.max(8, math.min(128,
        math.floor(tonumber(Perception.adapters.maximumZombieCandidates) or 48)))
    Relations.configure(Perception.adapters.relations)
    TargetPolicy.configure(Perception.adapters.targetPolicy)
end

local KIND_WEIGHTS = {

    assault = { player = 1, zombie = 1, actor = 1 },
    hunt = { player = 0.25, zombie = 1.5, actor = 0.6 },
    manhunt = { player = 0.2, zombie = 1.6, actor = 0.7 },
}

local DEFAULT_WEIGHTS = { player = 0.5, zombie = 1.0, actor = 0.45 }

local function movingAway(shell, candidate)
    if not Perception.has(candidate, "isMoving") or candidate:isMoving() ~= true
            or candidate.getForwardDirection == nil then return false end
    local cx, cy = Perception.xyOf(candidate)
    local sx, sy = Perception.xyOf(shell)
    if cx == nil or sx == nil then return false end
    local forward = candidate:getForwardDirection()
    if forward == nil then return false end
    local dx, dy = cx - sx, cy - sy
    local span = math.sqrt(dx * dx + dy * dy)
    if span < 0.01 then return false end
    return (forward:getX() * dx + forward:getY() * dy) / span > 0.35
end

function Perception.closingSpeed(shell, candidate)
    if not Perception.has(candidate, "isMoving") or candidate:isMoving() ~= true then return 0 end
    if candidate.getForwardDirection == nil then return 0 end
    local sx, sy = Perception.xyOf(shell)
    local cx, cy = Perception.xyOf(candidate)
    if sx == nil or cx == nil then return 0 end
    local dx, dy = sx - cx, sy - cy
    local span = math.sqrt(dx * dx + dy * dy)
    if span < 0.01 then return 0 end
    local forward = candidate:getForwardDirection()
    if forward == nil then return 0 end
    local alignment = (forward:getX() * dx + forward:getY() * dy) / span
    if alignment <= 0 then return 0 end

    local pace = 1.0
    if candidate.isSprinting ~= nil and candidate:isSprinting() == true then
        pace = 3.0
    elseif candidate.isRunning ~= nil and candidate:isRunning() == true then
        pace = 2.0
    end
    return math.min(1, alignment) * pace
end

function Perception.targetScore(kind, distance, mode, armed, away, contact, grudge, closing)
    kind = tostring(kind or "zombie")
    distance = math.max(0, tonumber(distance) or 0)
    local base = kind == "zombie" and 0.55 or 1.0
    if kind == "player" then
        if mode == "hunt" then
            base = base * 1.4
        elseif mode == "manhunt" then
            base = base * 1.8
        end
    end

    local urgency = math.max(0, tonumber(closing) or 0) / (distance + 2)
    local score = base * (1 / (1 + distance / 8))
        * (armed == true and 1.25 or 1)
        * (away == true and 0.6 or 1)
        * (1 + 1.6 * math.min(0.75, urgency))
    if contact == true then score = score + 3 end
    if grudge == true then score = score + 2 end

    if grudge == true and kind ~= "zombie" then score = score + 3 end
    return score
end

function Perception.challengerWins(heldScore, challengerScore, sinceHandOffMs, interrupt,
        heldDistanceSquared, challengerDistanceSquared)
    local elapsed = tonumber(sinceHandOffMs) or 0
    local challenger = tonumber(challengerScore) or -math.huge
    local held = tonumber(heldScore) or 0
    if interrupt == true and challenger > held * 1.2 then return true end
    local heldFlat = tonumber(heldDistanceSquared) or math.huge
    local challengerFlat = tonumber(challengerDistanceSquared) or math.huge
    if heldFlat > 0 and heldFlat < math.huge and challengerFlat < math.huge
            and challengerFlat <= heldFlat * 0.49 then
        return elapsed > 1500
    end
    if challenger <= held * 1.2 then return false end
    return elapsed > 5000
end

local function weightFor(mode, kind)
    local weights = KIND_WEIGHTS[tostring(mode or "")] or DEFAULT_WEIGHTS
    local weight = weights[kind] or 1
    return weight * weight
end

local function rememberEngagement(actorUid, target, kind, now)
    local entry = { target = target, kind = kind, atMs = now }
    entry.x, entry.y, entry.z = Perception.xyzOf(target)
    Perception.engagements[actorUid] = entry
    return entry
end

function Perception.nearerFirst(a, b) return a.flat < b.flat end

function Perception.snapshotFor(now)
    now = tonumber(now) or (type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000))
    local cell = type(getCell) == "function" and getCell() or nil
    local snapshot = Perception.zombieSnapshot
    if snapshot ~= nil and snapshot.cell == cell and now >= snapshot.atMs
            and now - snapshot.atMs < 200 then return snapshot end
    local began = type(getTimestampMs) == "function" and getTimestampMs() or nil
    snapshot = { cell = cell, atMs = now, bodies = {}, actors = {} }
    pcall(function()
        local zombies = cell ~= nil and cell:getZombieList() or nil
        for index = 0, size(zombies) - 1 do
            local body = zombies:get(index)
            if body ~= nil then
                local sampled = { body = body, x = body:getX(), y = body:getY(), z = body:getZ() }
                if actorShell(body) then
                    snapshot.actors[#snapshot.actors + 1] = sampled
                else
                    snapshot.bodies[#snapshot.bodies + 1] = sampled
                end
            end
        end
    end)
    Perception.zombieSnapshot = snapshot
    Perception.countSight("snapshotBuilds")
    if began ~= nil and getTimestampMs() - began > 16 then
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then
            runtime.noteDetail("perception:snapshot", getTimestampMs() - began)
        end
    end
    return snapshot
end

Perception.cellSize = 16
Perception.cellLimit = 10000000
Perception.cellSweeps = 3
function Perception.buildCells(snapshot)
    local cells, bodies = {}, snapshot.bodies
    local size, limit, floor = Perception.cellSize, Perception.cellLimit, math.floor
    snapshot.cellSize = size
    for index = 1, #bodies do
        local sampled = bodies[index]
        local x = sampled ~= nil and sampled.x or nil
        local y = sampled ~= nil and sampled.y or nil
        if type(x) ~= "number" or type(y) ~= "number"
                or not (x > -limit and x < limit and y > -limit and y < limit) then
            snapshot.cellsOff = true
            return nil
        end
        local key = floor(x / size) * 2097152 + floor(y / size)
        local list = cells[key]
        if list == nil then cells[key] = { index } else list[#list + 1] = index end
    end
    snapshot.cells = cells
    return cells
end

function Perception.cellOrder(snapshot, ox, oy, oz, range)
    if snapshot.cellsOff == true then return nil end
    if type(ox) ~= "number" or type(oy) ~= "number" or type(oz) ~= "number"
            or type(range) ~= "number" or not (range >= 0) then return nil end
    local reach = range + 1
    local limit = Perception.cellLimit
    if not (math.abs(ox) + reach < limit and math.abs(oy) + reach < limit) then return nil end
    local size = snapshot.cellSize or Perception.cellSize
    local x1, x2 = math.floor((ox - reach) / size), math.floor((ox + reach) / size)
    local y1, y2 = math.floor((oy - reach) / size), math.floor((oy + reach) / size)
    local bodies = snapshot.bodies
    local total = #bodies
    if (x2 - x1 + 1) * (y2 - y1 + 1) > total then return nil end
    local cells = snapshot.cells
    if cells == nil then
        snapshot.sweeps = (snapshot.sweeps or 0) + 1
        if snapshot.sweeps < Perception.cellSweeps then return nil end
        cells = Perception.buildCells(snapshot)
        if cells == nil then return nil end
    end
    local covered = 0
    for cx = x1, x2 do
        local base = cx * 2097152
        for cy = y1, y2 do
            local list = cells[base + cy]
            if list ~= nil then covered = covered + #list end
        end
    end
    if covered * 2 > total then return nil end
    local worst = range * range
    local order, count = {}, 0
    for cx = x1, x2 do
        local base = cx * 2097152
        for cy = y1, y2 do
            local list = cells[base + cy]
            if list ~= nil then
                for slot = 1, #list do
                    local index = list[slot]
                    local sampled = bodies[index]
                    local z = sampled.z
                    if type(z) ~= "number" then return nil end
                    local dx = sampled.x - ox
                    local dy = sampled.y - oy
                    local dz = z - oz
                    if dx * dx + dy * dy + dz * dz <= worst then
                        count = count + 1
                        order[count] = index
                    end
                end
            end
        end
    end

    if count * 8 > total then return nil end
    if count > 1 then table.sort(order) end
    return order
end

function Perception.nearbyActors(actor, shell, range, stance)
    local found, seen = {}, {}

    local sx, sy, sz = Perception.xyzOf(shell)
    local offer = Perception.offerNearby
    local watchdog = ProjectALife.Watchdog
    for _, binding in pairs(watchdog and watchdog.bindings or {}) do
        offer(found, seen, actor, shell, sx, sy, sz, range, stance, binding.shell)
    end
    local snapshot = Perception.zombieSnapshot
    for _, sampled in ipairs(snapshot and snapshot.actors or {}) do
        offer(found, seen, actor, shell, sx, sy, sz, range, stance, sampled.body)
    end
    table.sort(found, Perception.nearerFirst)
    return found
end

function Perception.offerNearby(found, seen, actor, shell, sx, sy, sz, range, stance, candidate)
    if candidate == nil or candidate == shell or seen[candidate] then return end
    seen[candidate] = true
    local flat = math.huge
    local cx, cy, cz = Perception.xyzOf(candidate)
    if sx ~= nil and cx ~= nil then
        local dx, dy, dz = sx - cx, sy - cy, sz - cz
        flat = dx * dx + dy * dy + dz * dz
    end
    if flat > range * range then return end
    local record = activeActorForShell(candidate)
    if record ~= nil and alive(candidate) and TargetPolicy.canAttack(candidate, nil, actor)
            and ((stance == nil and Relations.hostile(actor, record))
                or (stance ~= nil and Relations.status(actor, record) == stance)) then
        found[#found + 1] = { body = candidate, actor = record, flat = flat }
    end
end

function Perception.quietRefuses(actor, shell, candidate)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or memory.quietIndoors ~= true then return false end

    local now = type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000)
    local leaseUntil = tonumber(memory.quietIndoorsUntilMs)
    if leaseUntil == nil or now >= leaseUntil then return false end
    local lifted = tonumber(memory.quietLiftedUntilMs)
    if lifted ~= nil and now < lifted then return false end
    local refuse = true
    pcall(function()
        local mine = shell:getSquare()
        local theirs = candidate:getSquare()
        local home = mine ~= nil and mine:getBuilding() or nil
        local there = theirs ~= nil and theirs:getBuilding() or nil

        refuse = not (home ~= nil and there == home)
    end)
    if refuse then
        Perception.metrics = Perception.metrics or {}
        Perception.metrics.quietRefused = (Perception.metrics.quietRefused or 0) + 1
    end
    return refuse
end

function Perception.findThreat(actor, shell, mode)
    if type(Perception.adapters.findThreat) == "function" then
        return Perception.adapters.findThreat(actor, shell, mode)
    end

    Perception.forgetSight()
    local legacy = Perception.legacyPicker == true
    local ignoreNow = type(getTimestampMs) == "function" and getTimestampMs()
        or math.floor(os.time() * 1000)
    Perception.persons[actor.uid] = nil
    local personScore = -math.huge
    local grudge, grudgeKind = Perception.retaliationTarget(actor.uid, ignoreNow)
    if grudge ~= nil then
        if legacy then
            rememberEngagement(actor.uid, grudge, grudgeKind, ignoreNow)
            return grudge, distanceSquared(shell, grudge), grudgeKind
        end
    end
    if legacy then

        local contact, contactKind = Perception.contactThreat(shell)
        if contact ~= nil then
            rememberEngagement(actor.uid, contact, contactKind, ignoreNow)
            Perception.lastKnown[actor.uid] = nil
            return contact, 0, contactKind
        end
    end
    local profile = Catalog.npc(actor.profileId)
    local general = profile and profile.general or nil
    local awareness = tonumber(general and general.awareness)
        or ProjectALife.CustomProfiles.newcomer.awareness

    local range = math.max(16, 16 + awareness * 5)
    local best, bestDistance, bestKind = nil, range * range, nil

    local zombieReach2 = Perception.zombieReach(shell, range) ^ 2

    local clientSide = type(isClient) == "function" and isClient() == true
    local bestScore = -math.huge
    local scoredCandidates = {}
    local function consider(candidate, kind, flat)
        if scoredCandidates[candidate] then return end
        scoredCandidates[candidate] = true
        if legacy then
            local scored = kind == "zombie" and flat
                or flat * weightFor(mode, kind)
            if scored < bestDistance then
                best, bestDistance, bestKind = candidate, scored, kind
            end
            return
        end

        local combat = ProjectALife.Combat
        local armed = combat ~= nil and type(combat.targetIsGunman) == "function"
            and combat.targetIsGunman(candidate) == true
        local contact = flat <= 2.25
            and Perception.contactReachable(shell, candidate)
        local score = Perception.targetScore(kind, math.sqrt(flat), mode,
            armed, movingAway(shell, candidate), contact, candidate == grudge,
            Perception.closingSpeed(shell, candidate))
        if score > bestScore then
            best, bestDistance, bestKind, bestScore = candidate, flat, kind, score
        end
        if kind ~= "zombie" and score > personScore then
            personScore = score
            Perception.persons[actor.uid] = { target = candidate, kind = kind, flat = flat, atMs = ignoreNow }
        end
    end

    if not legacy and grudge ~= nil and visible(shell, grudge) then
        consider(grudge, grudgeKind or "zombie", distanceSquared(shell, grudge))
    end
    local nearestZombie, nearestZombieFlat = nil, math.huge

    local ringZombies = 0

    local nearestActor, nearestActorFlat = nil, math.huge

    if type(getCell) == "function" then
        local snapshot = Perception.snapshotFor(ignoreNow)

        local shortlist, shortlistCount = {}, 0
        local worst = range * range

        local originOk, ox, oy, oz = pcall(function()
            return shell:getX(), shell:getY(), shell:getZ()
        end)
        if originOk then
            pcall(function()

                local bodies = snapshot.bodies
                local order = Perception.cellOrder(snapshot, ox, oy, oz, range)
                for step = 1, order ~= nil and #order or #bodies do
                    local sampled = bodies[order ~= nil and order[step] or step]
                    local candidate = sampled.body
                    if candidate ~= nil and candidate ~= shell then
                        local dx = sampled.x - ox
                        local dy = sampled.y - oy
                        local dz = sampled.z - oz
                        local distance = dx * dx + dy * dy + dz * dz
                        if distance <= worst then
                            shortlistCount = shortlistCount + 1
                            shortlist[shortlistCount] = { body = candidate, flat = distance }
                            if shortlistCount > Perception.maximumZombieCandidates then

                                local farthest, farthestAt = -1, 1
                                for slot = 1, shortlistCount do
                                    if shortlist[slot].flat > farthest then
                                        farthest, farthestAt = shortlist[slot].flat, slot
                                    end
                                end
                                shortlist[farthestAt] = shortlist[shortlistCount]
                                shortlist[shortlistCount] = nil
                                shortlistCount = shortlistCount - 1
                                worst = farthest
                            end
                        end
                    end
                end
            end)
        end
        table.sort(shortlist, Perception.nearerFirst)

        local sightChecks = 0
        for slot = 1, shortlistCount do
            local candidate = shortlist[slot].body
            local distance = shortlist[slot].flat

            if distance > zombieReach2 or (sightChecks >= Perception.maximumSightChecks
                    and (not legacy or distance > Perception.dangerRingSquared)) then
                break
            end
            local ownedMark = actorShell(candidate)
            if not ownedMark and alive(candidate) then

                if not (clientSide and Perception.knownReplica(candidate, ignoreNow)) then
                    local kind = "zombie"
                    if distance <= Perception.dangerRingSquared then
                        ringZombies = ringZombies + 1
                    end
                    local seeable = false

                    if not isIgnored(actor.uid, candidate, ignoreNow)
                            and not (kind == "zombie" and Perception.quietRefuses(actor, shell, candidate))
                            and sightChecks < Perception.maximumSightChecks then
                        seeable = visible(shell, candidate)
                        if seeable then sightChecks = sightChecks + 1 end
                    end
                    if seeable then
                        consider(candidate, kind, distance)
                        if distance < nearestZombieFlat and distance < 64 then
                            nearestZombie, nearestZombieFlat = candidate, distance
                        end
                    end
                end
            end
        end
    end

    do

        local hostiles = Perception.nearbyActors(actor, shell, range)
        if hostiles ~= nil then
            if #hostiles > Perception.maximumActorSightChecks then
                table.sort(hostiles, Perception.nearerFirst)
            end
            for index = 1, math.min(#hostiles, Perception.maximumActorSightChecks) do
                local entry = hostiles[index]
                if not isIgnored(actor.uid, entry.body, ignoreNow)
                        and Perception.actorAwarenessOk(actor, shell, entry.body, entry.flat)
                        and visible(shell, entry.body) and (ProjectALife.Risk == nil
                        or ProjectALife.Risk.mayInitiate(actor, shell, entry.body, "actor")) then
                    consider(entry.body, "actor", entry.flat)
                    if entry.flat < nearestActorFlat then
                        nearestActor, nearestActorFlat = entry.body, entry.flat
                    end
                end
            end
            if #hostiles > Perception.maximumActorSightChecks then
                Perception.metrics = Perception.metrics or {}
                Perception.metrics.actorSightCapped = (Perception.metrics.actorSightCapped or 0) + 1
            end
        end
    end

    local players = playerList()
    for _, candidate in ipairs(players) do
        if Relations.hostileToPlayer(actor, candidate) then
            if alive(candidate) and TargetPolicy.canAttack(candidate, nil, actor) then
                local flat = distanceSquared(shell, candidate)
                if (legacy or flat <= range * range) and visible(shell, candidate)
                        and calmAwarenessOk(actor, candidate, flat, ignoreNow, shell)
                        and nightAwarenessOk(actor, shell, candidate, flat)
                        and playerNoticed(actor, shell, candidate, math.sqrt(flat))
                        and (ProjectALife.Risk == nil or ProjectALife.Risk.mayInitiate(actor, shell, candidate, "player")) then
                    consider(candidate, "player", flat)
                end
            end
        end
    end

    local humanHeld = bestKind == "player" or bestKind == "actor"
    if legacy and nearestZombie ~= nil and nearestZombieFlat <= Perception.dangerRingSquared
            and not isIgnored(actor.uid, nearestZombie, ignoreNow) then
        local currentFlat = best ~= nil and distanceSquared(shell, best) or math.huge
        local steal
        if not humanHeld then
            local urgency = Perception.zombieUrgency
            steal = best == nil or nearestZombieFlat <= currentFlat * urgency * urgency
        else

            local ratio = ringZombies >= (Perception.hordeCount or 3)
                and (Perception.hordeStealRatio or 0.85)
                or (Perception.zombieStealRatio or 0.6)
            steal = nearestZombieFlat <= 6.25
                or nearestZombieFlat <= currentFlat * ratio * ratio
        end
        if steal then
            best, bestDistance, bestKind = nearestZombie, nearestZombieFlat, "zombie"
        end
    end

    if legacy and best ~= nil and (bestKind == "player" or bestKind == "actor")
            and nearestActor ~= nil and nearestActor ~= best

            and nearestActorFlat < distanceSquared(shell, best) * 0.5
            and ignoreNow - (Perception.handOffAtMs[actor.uid] or -1e12) > 5000
            and movingAway(shell, best) then
        Perception.handOffAtMs[actor.uid] = ignoreNow
        best, bestDistance, bestKind = nearestActor, nearestActorFlat, "actor"
    end

    local held = Perception.engagements[actor.uid]
    if held ~= nil then
        local target = held.target
        local heldActor, heldOwned = activeActorForShell(target)

        local heldComrade = heldOwned and heldActor ~= nil
            and Perception.comrade(actor, target)

        local heldReplica = clientSide and not heldOwned and held.kind == "zombie"
            and target ~= grudge and Perception.knownReplica(target, ignoreNow)
        local valid = target ~= nil and alive(target)
            and TargetPolicy.canAttack(target, nil, actor)
            and not isIgnored(actor.uid, target, ignoreNow)
            and (not heldOwned or heldActor ~= nil)
            and not heldComrade and not heldReplica
            and (held.kind ~= "player" or Relations.hostileToPlayer(actor, target)
                or target == grudge)
        if heldComrade or heldReplica then
            pcall(Perception.logTarget, actor, target, held.kind, "drop", ignoreNow, shell)
        end
        local heldFlat = valid and distanceSquared(shell, target) or math.huge

        local zombieFar = valid and held.kind == "zombie" and target ~= grudge
            and heldFlat > zombieReach2 * Perception.zombieHoldFactor * Perception.zombieHoldFactor
        local heldVisible = valid and not zombieFar and heldFlat <= range * range
            and visible(shell, target)

        local contactInterrupt = best ~= nil and best ~= target
            and bestDistance <= 2.25 and Perception.contactReachable(shell, best)
        if valid and held.kind == "player" and not heldVisible
                and held.x ~= nil and held.y ~= nil and not contactInterrupt
                and ignoreNow - (tonumber(held.atMs) or -1e12) <= 2500 then
            Perception.lastKnown[actor.uid] = {
                x = held.x, y = held.y, z = held.z, kind = held.kind,
                target = target, atMs = held.atMs,
            }
            return nil, math.huge, nil
        end
        if not valid or zombieFar or heldFlat > range * range or not heldVisible then

            if valid and not zombieFar and held.x ~= nil and held.y ~= nil then
                local lx, ly, lz = held.x, held.y, held.z
                if lx ~= nil and ly ~= nil then
                    Perception.lastKnown[actor.uid] = {
                        x = lx, y = ly, z = lz,
                        kind = held.kind,
                        target = target,
                        atMs = ignoreNow,
                    }

                    if held.kind == "player" or held.kind == "actor" then
                        pcall(function()
                            local gunner = ProjectALife.ModuleGunner
                            if gunner ~= nil then
                                gunner.order(actor, shell,
                                    { x = lx, y = ly, z = lz }, ignoreNow)
                            end
                        end)
                    end
                end
            else
                Perception.lastKnown[actor.uid] = nil
            end
            Perception.engagements[actor.uid] = nil
        else

            local hx, hy, hz = Perception.xyzOf(target)
            if hx ~= nil then
                held.x, held.y, held.z = hx, hy, hz
                held.atMs = ignoreNow
            end
        end
        if heldVisible and target ~= best then
            if not legacy then
                local combat = ProjectALife.Combat
                local heldArmed = combat ~= nil and type(combat.targetIsGunman) == "function"
                    and combat.targetIsGunman(target) == true
                local heldContact = heldFlat <= 2.25
                    and Perception.contactReachable(shell, target)
                local heldScore = Perception.targetScore(held.kind, math.sqrt(heldFlat), mode,
                    heldArmed, movingAway(shell, target), heldContact, target == grudge,
                    Perception.closingSpeed(shell, target))
                local challengerContact = best ~= nil and bestDistance <= 2.25
                    and Perception.contactReachable(shell, best)
                local interrupt = challengerContact or best == grudge
                local elapsed = ignoreNow
                    - (Perception.handOffAtMs[actor.uid] or -1e12)
                if best == nil or (held.kind == "player" and not interrupt)
                        or not Perception.challengerWins(
                        heldScore, bestScore, elapsed, interrupt,
                        heldFlat, bestDistance) then
                    best, bestDistance, bestKind, bestScore =
                        target, heldFlat, held.kind, heldScore
                else
                    Perception.handOffAtMs[actor.uid] = ignoreNow
                end
            else
                local candidateFlat = best ~= nil
                    and distanceSquared(shell, best) or math.huge

                local heldRunning = (held.kind == "player" or held.kind == "actor")
                    and (bestKind == "player" or bestKind == "actor")
                    and movingAway(shell, target)
                local displaced = candidateFlat <= 1.44
                    or candidateFlat <= heldFlat * 0.60

                    or (heldRunning and candidateFlat <= heldFlat * 0.85
                        and ignoreNow - (Perception.handOffAtMs[actor.uid] or -1e12) > 5000)
                if not displaced then
                    best, bestDistance, bestKind = target, heldFlat, held.kind
                end
            end
        end
    end

    if legacy and bestKind == "player" and nearestZombie ~= nil
            and nearestZombieFlat < 64
            and distanceSquared(shell, best) > 144 then

        if nearestActor ~= nil and nearestActorFlat < 144
                and not isIgnored(actor.uid, nearestActor, ignoreNow) then
            best, bestDistance, bestKind = nearestActor, nearestActorFlat, "actor"
        else
            best, bestDistance, bestKind = nearestZombie, nearestZombieFlat, "zombie"
        end
    end

    if best == nil and Tactics ~= nil
            and type(Tactics.assistTarget) == "function" then
        local shared, sharedKind, sharedEntry = Tactics.assistTarget(actor, shell, ignoreNow)

        shared, sharedKind = Perception.boardKind(shared, sharedKind, ignoreNow)
        if shared ~= nil and sharedKind == "zombie"
                and Perception.reportedBeyond(shell, sharedEntry, zombieReach2) then
            shared = nil
        end

        if shared ~= nil and not isIgnored(actor.uid, shared, ignoreNow)
                and (sharedKind ~= "player" or Relations.hostileToPlayer(actor, shared))
                and not Perception.comrade(actor, shared)
                and Perception.riskAllows(actor, shell, shared, sharedKind) then

            if visible(shell, shared) then
                best = shared
                bestKind = sharedKind or "actor"
                bestDistance = distanceSquared(shell, shared)
            else
                Perception.sharedLead(actor, shared, sharedKind, sharedEntry)
            end
        end
    end

    local zombieHeld = bestKind == "zombie" and best ~= grudge
        and bestDistance > Perception.dangerRingSquared
    if (best == nil or zombieHeld) and Tactics ~= nil and type(Tactics.acquireThreat) == "function" then
        local shared, sharedKind, sharedEntry = Tactics.acquireThreat(actor, nil, nil, ignoreNow)
        if shared ~= nil and (sharedKind == "player" or sharedKind == "actor")
                and not isIgnored(actor.uid, shared, ignoreNow) and alive(shared)
                and (sharedKind ~= "player" or Relations.hostileToPlayer(actor, shared))
                and not Perception.comrade(actor, shared) then
            local flat = distanceSquared(shell, shared)
            local reach = (type(Tactics.settings) == "table" and tonumber(Tactics.settings.alarmRange)) or 40
            if flat ~= nil and flat <= reach * reach
                    and Perception.riskAllows(actor, shell, shared, sharedKind) then
                if visible(shell, shared) then
                    best, bestKind, bestDistance = shared, sharedKind, flat
                elseif Perception.sharedLead(actor, shared, sharedKind, sharedEntry) ~= nil
                        and zombieHeld then
                    Perception.engagements[actor.uid] = nil
                    return nil, math.huge, nil
                end
            end
        end
    end

    if best ~= nil then
        local previous = Perception.engagements[actor.uid]
        rememberEngagement(actor.uid, best, bestKind, ignoreNow)

        Perception.lastKnown[actor.uid] = nil

        if previous == nil or previous.target ~= best then
            pcall(Perception.logTarget, actor, best, bestKind, "pick", ignoreNow, shell)

            if (bestKind == "player" or bestKind == "actor") and Tactics ~= nil
                    and type(Tactics.reportThreat) == "function" then
                pcall(Tactics.reportThreat, actor, best, bestKind, ignoreNow)
            end

            pcall(function()
                local panic = ProjectALife.ModulePanic
                if panic ~= nil and (bestKind == "player" or bestKind == "actor") then
                    panic.onFirstContact(actor, shell, best, bestKind, ignoreNow)
                end
            end)
            local investigation = ProjectALife.Investigation
            if investigation ~= nil
                    and type(investigation.reportContact) == "function"

                    and ignoreNow - (Perception.contactReportAtMs[actor.uid] or -1e12)
                        > 6000 then
                Perception.contactReportAtMs[actor.uid] = ignoreNow
                pcall(function()
                    investigation.reportContact(actor, best,
                        best:getX(), best:getY(), best:getZ(), 20)
                end)
            end
        end
    end
    return best, bestDistance, bestKind
end

function Perception.personPick(uid, now)
    local entry = Perception.persons[uid]
    if entry == nil then return nil end
    if now < entry.atMs or now - entry.atMs > 600 or not alive(entry.target) then
        Perception.persons[uid] = nil
        return nil
    end
    return entry.target, entry.kind, entry.flat
end

function Perception.lastKnownFor(actor, now, lifetimeMs)
    local entry = Perception.lastKnown[actor.uid]
    if entry == nil then return nil end

    if entry.target ~= nil then
        local dead = Perception.has(entry.target, "isDead") and entry.target:isDead() == true
        if dead then
            Perception.lastKnown[actor.uid] = nil
            return nil
        end
    end
    now = tonumber(now) or 0

    local lifetime = tonumber(lifetimeMs)
        or (entry.kind == "player" and 25000 or 12000)
    if now - entry.atMs > lifetime then
        Perception.lastKnown[actor.uid] = nil
        return nil
    end
    return entry
end

function Perception.clearLastKnown(actor)
    Perception.lastKnown[actor.uid] = nil
end

function Perception.sharedLead(actor, target, kind, entry)
    local point = type(entry) == "table" and entry.position or nil
    if type(point) ~= "table" or tonumber(point.x) == nil or tonumber(point.y) == nil then
        return nil
    end
    local current = Perception.lastKnown[actor.uid]
    if current ~= nil and current.shared ~= true then return nil end
    local lead = { x = point.x, y = point.y, z = point.z, kind = kind,
        target = target, atMs = tonumber(entry.atMs) or 0, shared = true }
    Perception.lastKnown[actor.uid] = lead
    return lead
end

function Perception.contactReachable(shell, candidate)
    if shell == nil or candidate == nil
            or distanceSquared(shell, candidate) > 2.25 then return false end
    local shellSquare, candidateSquare = Perception.squaresOnOneLevel(shell, candidate)
    if shellSquare == nil then return false end
    if shellSquare == candidateSquare then return true end

    local window = Perception.eitherWay(shellSquare, candidateSquare, "getWindowTo")
    if window ~= nil then
        return window.IsOpen ~= nil and (window:IsOpen() == true
            or (window.isSmashed ~= nil and window:isSmashed() == true))
    end

    local door = Perception.eitherWay(shellSquare, candidateSquare, "getDoorTo")
    if door ~= nil then
        return door.IsOpen ~= nil and door:IsOpen() == true
    end

    local hop, hopAsked = Perception.eitherWay(shellSquare, candidateSquare, "isHoppableTo")
    if hop == true then return false end
    if hopAsked and Perception.eitherWay(shellSquare, candidateSquare, "getHoppableTo") ~= nil then
        return false
    end

    local blocked, asked = Perception.eitherWay(shellSquare, candidateSquare, "isBlockedTo")
    return asked and blocked ~= true
end

function Perception.contactThreat(shell)
    local best, bestKind, bestDistance = nil, nil, 2.25
    local ok = pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local x, y, z = math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ())
        local inspected = 0
        for dx = -2, 2 do
          for dy = -2, 2 do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            local bodies = square and square:getMovingObjects() or nil
            for index = 0, size(bodies) - 1 do
              local candidate = at(bodies, index)
              inspected = inspected + 1
              if inspected > 128 then return end
              if candidate ~= nil and candidate ~= shell and instanceof(candidate, "IsoZombie") then
                local distance = distanceSquared(shell, candidate)
                if distance < bestDistance and alive(candidate)
                        and not actorShell(candidate)
                        and not (Perception.knownReplica(candidate)
                            and not Perception.bitBy(shell, candidate))
                        and visible(shell, candidate)
                        and Perception.contactReachable(shell, candidate) then
                    best, bestKind, bestDistance = candidate, "zombie", distance
                end
              end
            end
          end
        end
    end)
    if not ok then return nil end
    return best, bestKind
end

Perception.distanceSquared = distanceSquared

Perception.visible = visible

Perception.findThreatPlain = Perception.findThreat

function Perception.findThreat(actor, shell, mode)
    local focus = ProjectALife.ZombieFocus
    if focus == nil or type(Perception.adapters.findThreat) == "function" then
        return Perception.findThreatPlain(actor, shell, mode)
    end
    return focus.pick(Perception.findThreatPlain, actor, shell, mode)
end

return Perception
