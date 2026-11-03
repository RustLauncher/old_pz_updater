ProjectALife = ProjectALife or {}
if ProjectALife.Executor then return ProjectALife.Executor end
require "ProjectALife/Core/ALifeMirrorTransport"
require "ProjectALife/Core/ALifeExecutorHits"
require "ProjectALife/Shells/ALifeNPCHitRelay"
require "ProjectALife/Shells/ALifeWounds"
require "ProjectALife/Behaviours/ALifeVehicleRules"
require "ProjectALife/Compat/ALifeInterop"

local Interop = ProjectALife.Interop
local Executor = {
    MIRROR_TAG = "ProjectALife.Mirror.v1",
    enabled = true,
    started = false,
    settings = {
        tickIntervalMs = 100,
        reportIntervalMs = 1000,
        mirrorIntervalMs = 1000,
        auditIntervalMs = 500,
        deathStampGraceMs = 60000,
        decisionBudgetMinimum = 6,
        reportRateLimitMs = 200,

        reportServerGapMs = 120,
        reportPositionMaxDrift = 3,

        reportOwnerQuietMs = 2000,
        hydrateRetryMs = 5000,
        mirrorMissLimit = 3,

        spectatorPaintMs = 10000,

        ownershipLossReads = 3,

        strayMisses = 3,
        strayMirrorFreshMs = 3000,
        strayGraceMs = 6000,
        strayRetryMs = 1000,

        deathPushIntervalMs = 1000,
        deathPushLimit = 4,
        deathFallbackMs = 2000,
        deathForceMs = 8000,
        deathTrackMs = 15000,

        killerReachTiles = 80,

        diedAnnounceMs = 30000,
        serverDiedMs = 15000,
        serverDiedRadius = 3,

        corpseScrubCapMs = 10000,

        readoptCooldownMs = 5000,

        unreportedMs = 15000,
        droppedGraceMs = 2000,
        ownerWindowIn = 60,
        ownerWindowOut = 72,
        replicaResendMs = 60000,
        replicaResendLimit = 2,
        unownedQuietMs = 30000,
        parkBackoffLimit = 4,

        replicaMissingMs = 3000,
        replicaMissingRadius = 50,
        replicaAskMs = 5000,
        replicaAskBatch = 8,
        replicaAskLimit = 4,
        replicaAskSpacingMs = 4000,
        replicaAskQuietMs = 3000,
        ownerAuditBudget = 4,
        ownerAuditIntervalMs = 250,

        grudgeHandMs = 60000,

        handoffKeepMs = 10000,
    },

    executed = {},          
    byShell = setmetatable({}, { __mode = "k" }),
    order = {},
    mirror = { records = {}, receivedAtMs = 0, count = 0, sequence = 0 },
    metrics = {
        adopted = 0, released = 0, reports = 0, deaths = 0, ticks = 0, mirrorApplies = 0,
        faults = 0, lastError = nil,
        releaseReasons = {}, adoptRefusals = {},
        hydrated = 0, hydrateFailures = 0, lastHydrateError = nil,
        scrubbed = 0,

        strays = 0, reaped = 0,
        supportRelayed = 0,

        noiseRelayed = 0, noiseApplied = 0, noiseRejected = 0,

        healthHeld = 0, healthPushed = 0, healthApplied = 0, treatmentTimeouts = 0,

        unownedFarRejected = 0,

        playerHitsRelayed = 0,
        playerHitsApplied = 0,

        supportApplied = 0, supportRefused = 0, lastSupportReason = nil,

        transmits = 0, reportsApplied = 0, reportsRejected = 0, deathsApplied = 0, lastReject = nil,

        rejectedBy = {},

        deathsHanded = 0, deathPushes = 0, deathRevived = 0, deathFallbacks = 0, deathForced = 0,
        deathsReported = 0,

        killersReported = 0, killersRefused = 0,
        ownerDropped = 0, ownerWindowParked = 0, replicaResent = 0, unreported = 0,

        killedLocally = 0, corpseScrubs = 0, corpseScrubsReused = 0, reappeared = 0,
        deathReportsSkipped = 0, corpseKillsRefused = 0,

        grudgesHanded = 0, grudgesTaken = 0, grudgesKept = 0,

        refusalsSent = 0, reportsResent = 0,

        replicaAsks = 0, replicaAsked = 0, replicaAskRefused = {},
    },

    dying = {}, dyingOrder = {}, announced = {},

    serverDied = {}, serverDiedByOnline = {}, deadBodies = {}, deadCount = 0,
    releasedIds = {}, watchCount = 0, readoptAfterMs = {},

    handoffKept = {},
    ownerCursor = 0, lastOwnerAuditAtMs = -math.huge, replicaResends = {}, deathLines = 0,
    ownerParks = {},

    replicaWatch = {},
    adapters = {},
    lastTickAtMs = 0,
    lastAuditAtMs = 0,
    lastMirrorAtMs = 0,
    lastReportAtMs = {},

    releaseLines = 0, lifecycleLines = 0,
}
ProjectALife.Executor = Executor

local PROTECTED = {
    admin = true, persistent = true, encounter = true, encounterKind = true, encounterPersistent = true,
    outpostId = true, outpostSquadId = true, squadId = true, groupId = true,
    groupIndex = true, sessionOnly = true, natural = true, debugSpawn = true,
    loadoutDay = true, loadoutMonth = true, lookV = true,
    visit = true, guest = true, opinion = true, social = true, traderStock = true, hitByAt = true, engagedAt = true, walkWith = true,
    walkCooldownUntilHours = true, recognized = true, npcQuestion = true,
    home = true, stance = true, stanceAnchor = true, stanceHeading = true,
    stanceRole = true, stanceRoute = true, behaviorProfile = true, conduct = true,

    stanceFace = true,

    carefulRadii = true,

    holdPost = true,
    garrisonBounds = true, garrisonPost = true,

    outpostAlert = true,

    robbery = true, stolenLoot = true, talkHoldUntilMs = true, talkHoldPlayerKey = true, orderedTo = true,
    tolerateUntil = true, carefulPlayerKeys = true,
    robberyTruce = true,
    gossipHoldUntilMs = true, gossipFaceUid = true, gossipToken = true,
    offlineTask = true, scavengeArea = true, stanceRouteOneWay = true,
    nightCamp = true, nightCampKey = true, nightCampRestore = true, shelterUntilHours = true,
    shelterManagedByLife = true,
    activityId = true, activitySeq = true, activityState = true, havenId = true, supplyDepot = true,
    targetUsername = true, adminMode = true, revengeKey = true, role = true, supportRole = true,
    person = true, life = true, dress = true, vt = true, evq = true,
}

function Executor.mergeGrudges(own, theirs)
    local result, any = {}, false
    for _, bank in ipairs({ type(own) == "table" and own or {}, type(theirs) == "table" and theirs or {} }) do
        for uid, hostile in pairs(bank) do
            if type(uid) == "string" and #uid <= 128 and hostile == true then result[uid], any = true, true end
        end
    end
    if any then return result end
    return nil
end

local function nowMs()
    if type(Executor.adapters.nowMs) == "function" then return Executor.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function copy(value, depth)
    if type(value) ~= "table" then return value end
    depth = (depth or 0) + 1
    if depth > 12 then return nil end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry, depth) end
    return result
end

local function countPairs(map)
    local parts = {}
    for key, value in pairs(type(map) == "table" and map or {}) do
        parts[#parts + 1] = tostring(key) .. ":" .. tostring(value)
    end
    table.sort(parts)
    return parts[1] and table.concat(parts, ",") or "none"
end

local function scrubBody(shell, reason)
    if shell == nil then return end
    local guard = ProjectALife.AIFence
    if guard == nil or type(guard.releaseBody) ~= "function" then return end
    guard.releaseBody(shell, reason)
    Executor.metrics.scrubbed = Executor.metrics.scrubbed + 1
end

local function shellGone(shell)
    if type(Executor.adapters.shellGone) == "function" then return Executor.adapters.shellGone(shell) == true end
    local gone = false
    pcall(function()
        local id = shell:getOnlineID()
        gone = id == nil or id == -1
    end)
    return gone
end

local function fault(where, err)
    Executor.metrics.faults = Executor.metrics.faults + 1
    Executor.metrics.lastError = tostring(where) .. ":" .. tostring(err)
end

function Executor.multiplayer()
    if type(Executor.adapters.multiplayer) == "function" then return Executor.adapters.multiplayer() == true end
    return (type(isClient) == "function" and isClient() == true)
        or (type(isServer) == "function" and isServer() == true)
end

function Executor.executorSide()
    if type(Executor.adapters.executorSide) == "function" then return Executor.adapters.executorSide() == true end
    return type(isClient) == "function" and isClient() == true
        and not (type(isServer) == "function" and isServer() == true)
end

function Executor.serverDelegates()
    if not Executor.enabled then return false end
    if type(Executor.adapters.serverSide) == "function" then return Executor.adapters.serverSide() == true end
    return type(isServer) == "function" and isServer() == true
end

function Executor.executes(shell)
    return shell ~= nil and Executor.byShell[shell] ~= nil
end

function Executor.executesUid(uid)
    return uid ~= nil and Executor.executed[uid] ~= nil
end

function Executor.clientAuthority()
    return Executor.started == true and Executor.executorSide() == true
end

function Executor.authorityFor(shell)
    if shell ~= nil and Executor.byShell[shell] ~= nil then
        local uid = Executor.byShell[shell]
        if not Executor.entryMatches(shell, uid, Executor.executed[uid]) then return false end
        if type(Executor.adapters.isOwner) == "function" then return Executor.adapters.isOwner(shell) == true end
        local sim = ProjectALife.ShellSimulation
        return sim ~= nil and type(sim.isOwner) == "function" and sim.isOwner(shell) == true
    end
    if Executor.serverDelegates() then return false end
    return nil
end

local function isOwner(shell)
    if type(Executor.adapters.isOwner) == "function" then return Executor.adapters.isOwner(shell) == true end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.isOwner) == "function" then return sim.isOwner(shell) == true end
    return false
end

local function identityOf(shell)
    local adapter = ProjectALife.ShellAdapter
    if adapter ~= nil and type(adapter.shellIdentity) == "function" then
        local ok, uid, generation = pcall(adapter.shellIdentity, shell)

        if ok and type(uid) == "string" and uid ~= "" then return uid, generation end
    end
    local ok, uid, generation = pcall(function()
        local data = shell:getModData()
        return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration)
    end)
    if ok and type(uid) == "string" and uid ~= "" then return uid, generation end
    return nil, nil
end

function Executor.entryMatches(shell, uid, entry)
    if entry == nil or entry.shell ~= shell then return false end
    local currentUid, generation = identityOf(shell)
    return currentUid == uid and generation == entry.generation
end

Executor.noHitRules = {
    noteBound = function() return false end, noteMove = function() return nil end,
    grace = function() return nil end, slack = function() return 0 end,
    qaLine = function() return "" end,
    metrics = { acceptedOrdered = 0, graceAccepted = 0, graceRefused = 0, slackAccepted = 0 },
}

function Executor.hitRules()
    return ProjectALife.ExecutorHits or Executor.noHitRules
end

function Executor.bindingMatches(binding, uid)
    return binding ~= nil and Executor.entryMatches(binding.shell, uid, binding)
end

function Executor.buildMirror()
    local Registry = ProjectALife.ActorRegistry
    local records, count = {}, 0
    if Registry ~= nil and type(Registry.each) == "function" then
        Registry.each(function(record)
            if record.lifecycle == "active" then
                records[record.uid] = copy(record)
                count = count + 1
            end
        end)
    end
    return { records = records, count = count, at = nowMs() }
end

local function mirrorStore()
    if type(Executor.adapters.mirrorStore) == "function" then return Executor.adapters.mirrorStore() end
    if ModData ~= nil and type(ModData.getOrCreate) == "function" then
        local ok, store = pcall(ModData.getOrCreate, Executor.MIRROR_TAG)
        if ok then return store end
    end
    return nil
end

local function transmitMirror()
    if type(Executor.adapters.transmit) == "function" then return Executor.adapters.transmit(Executor.MIRROR_TAG) end
    if ModData ~= nil and type(ModData.transmit) == "function" then
        return pcall(ModData.transmit, Executor.MIRROR_TAG)
    end
    return false
end

function Executor.serverTick(now)
    if not Executor.serverDelegates() then return 0 end
    now = now or nowMs()
    Executor.settleDeaths(now)
    Executor.auditOwners(now)
    if Executor.adapters.transmit == nil and ProjectALife.MirrorTransport.available() then
        local sent = ProjectALife.MirrorTransport.tick(now)
        Executor.metrics.transmits = Executor.metrics.transmits + sent
        return sent
    end
    if now - Executor.lastMirrorAtMs < Executor.settings.mirrorIntervalMs then return 0 end
    Executor.lastMirrorAtMs = now
    local store = mirrorStore()
    if type(store) ~= "table" then return 0 end
    local built = Executor.buildMirror()
    local stale = {}
    for key in pairs(store) do stale[#stale + 1] = key end
    for _, key in ipairs(stale) do store[key] = nil end
    store.records = built.records
    store.count = built.count
    store.at = built.at
    store.died = Executor.diedFrame(now)
    transmitMirror()
    Executor.metrics.transmits = Executor.metrics.transmits + 1
    return built.count
end

Executor.authority = { unownedTrustRadius = 80, playerHitMaxRange = 80,
    noiseReporterRadius = 100, noisePerPlayerMs = 150 }
Executor.noiseByPlayerAtMs = {}

function Executor.playerNear(player, x, y, radius)
    if player == nil or not finite(x) or not finite(y) then return false end
    local near = false
    pcall(function()
        local dx, dy = player:getX() - x, player:getY() - y
        near = dx * dx + dy * dy <= radius * radius
    end)
    return near
end

local function ownerMatches(shell, player)
    if type(Executor.adapters.ownerMatches) == "function" then return Executor.adapters.ownerMatches(shell, player) == true end
    if shell == nil or player == nil then return false end
    local ok, owner = pcall(function() return shell:getOwnerPlayer() end)
    if ok and owner ~= nil then return owner == player end
    local x, y
    pcall(function() x, y = shell:getX(), shell:getY() end)
    local near = Executor.playerNear(player, x, y, Executor.authority.unownedTrustRadius)
    if not near then Executor.metrics.unownedFarRejected = (Executor.metrics.unownedFarRejected or 0) + 1 end
    return near
end

function Executor.engineOwner(shell)
    if shell == nil or type(shell.getOwnerPlayer) ~= "function" then return nil end
    return shell:getOwnerPlayer()
end

function Executor.takesOver(binding, player, now)
    if binding.reportOwner == nil then return true end
    if Executor.engineOwner(binding.shell) == player then return true end
    return (tonumber(now) or 0) - (tonumber(binding.reportOwnerAtMs) or -math.huge)
        >= Executor.settings.reportOwnerQuietMs
end

Executor.resendReasons = { rate_limited = true, actor_revision_conflict = true }

function Executor.tellRefused(player, message, reason)
    if player == nil or type(message) ~= "table" or not Executor.resendReasons[reason] then return false end
    local reply = { uid = message.uid, generation = message.generation, reason = reason,
        reportSerial = finite(message.reportSerial) and message.reportSerial or nil,
        memoryRevision = finite(message.memoryRevision) and message.memoryRevision or nil }
    if type(Executor.adapters.sendTo) == "function" then
        Executor.adapters.sendTo(player, "executorReportRefused", reply)
    elseif type(sendServerCommand) == "function" then
        pcall(sendServerCommand, player, "ProjectALife", "executorReportRefused", reply)
    else
        return false
    end
    Executor.metrics.refusalsSent = (Executor.metrics.refusalsSent or 0) + 1
    return true
end

local function reject(reason)
    Executor.metrics.reportsRejected = Executor.metrics.reportsRejected + 1
    Executor.metrics.lastReject = reason
    local by = Executor.metrics.rejectedBy
    if type(by) ~= "table" then
        by = {}
        Executor.metrics.rejectedBy = by
    end
    local key = tostring(reason)
    by[key] = (by[key] or 0) + 1
    return false, reason
end

function Executor.receivePose(binding, player, pose)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.receiveOwnerPose) ~= "function" then return false end
    local previous = animations.ownerPose[binding.shell]
    local changed = binding.poseOwner ~= player
    if changed then animations.ownerPose[binding.shell] = nil end
    if not animations.receiveOwnerPose(binding.shell, pose) then
        animations.ownerPose[binding.shell] = previous
        return false
    end
    if changed then binding.poseAtMs = nil end
    binding.poseOwner = player
    return true
end

function Executor.positionBody(position)
    return {
        x = position.x, y = position.y, z = position.z,
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function(self) return self.z end,
    }
end

function Executor.checkedReportPosition(binding, player, message, now)
    if type(binding) ~= "table" or type(message) ~= "table" then return nil end
    local serial = message.reportSerial
    if not finite(serial) or serial < 1 or serial ~= math.floor(serial)
            or (binding.positionOwner == player and serial <= (binding.positionSerial or 0)) then return nil end
    binding.positionOwner, binding.positionSerial = player, serial
    if not finite(message.x) or not finite(message.y) or not finite(message.z) then return nil end
    local shell, line = binding.shell, ProjectALife.LineOfFire
    if shell == nil or type(shell.getX) ~= "function" or type(shell.getY) ~= "function"
            or type(shell.getZ) ~= "function" or line == nil
            or type(line.hasClearBoundary) ~= "function" then return nil end
    local dx, dy = message.x - shell:getX(), message.y - shell:getY()
    if dx * dx + dy * dy > Executor.settings.reportPositionMaxDrift ^ 2
            or math.floor(message.z) ~= math.floor(shell:getZ()) then return nil end
    local position = Executor.positionBody(message)
    local checked, clear = pcall(line.hasClearBoundary, shell, position, "melee")
    if not checked or clear ~= true then return nil end
    position.owner, position.generation, position.atMs = player, binding.generation, now
    return position
end

function Executor.reportHitOrigin(binding, player, now)
    if type(binding) ~= "table" or not finite(now) then return nil end
    local position = binding.reportPosition
    if type(position) ~= "table" or not finite(position.x) or not finite(position.y)
            or not finite(position.z) or not finite(position.atMs)
            or position.owner ~= player or position.generation ~= binding.generation
            or now < position.atMs
            or now - position.atMs > Executor.settings.reportIntervalMs + Executor.settings.reportRateLimitMs then return nil end
    local shell, line = binding.shell, ProjectALife.LineOfFire
    if shell == nil or type(shell.getX) ~= "function" or type(shell.getY) ~= "function"
            or type(shell.getZ) ~= "function" then return nil end
    local dx, dy = position.x - shell:getX(), position.y - shell:getY()
    if dx * dx + dy * dy > Executor.settings.reportPositionMaxDrift ^ 2
            or math.floor(position.z) ~= math.floor(shell:getZ())
            or line == nil or type(line.hasClearBoundary) ~= "function" then return nil end
    local checked, clear = pcall(line.hasClearBoundary, shell, position, "melee")
    if not checked or clear ~= true then return nil end
    return position
end

function Executor.treatmentHeld(data, now)
    local pendingUntil = tonumber(data.ProjectALifeHealthPendingUntilMs)
    if pendingUntil ~= nil and now < pendingUntil then return true end
    data.ProjectALifeTreatmentRevision, data.ProjectALifeTreatmentGeneration = nil, nil
    Executor.metrics.treatmentTimeouts = (Executor.metrics.treatmentTimeouts or 0) + 1
    return false
end

function Executor.applyReport(player, message)
    if not Executor.serverDelegates() then return reject("not_delegating") end
    if type(message) ~= "table" or type(message.uid) ~= "string" or not finite(message.generation) then
        return reject("bad_message")
    end
    local Watchdog, Registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local binding = Watchdog and Watchdog.bindings[message.uid] or nil
    if binding == nil or binding.generation ~= message.generation then return reject("not_bound") end
    if not Executor.bindingMatches(binding, message.uid) then return reject("shell_identity_changed") end
    if not ownerMatches(binding.shell, player) then return reject("not_owner") end
    if binding.shell:isDead() then return reject("shell_dead") end
    local now = nowMs()

    local tookOver = false
    if binding.reportOwner ~= player and Executor.takesOver(binding, player, now) then
        binding.reportOwner = player
        Executor.lastReportAtMs[message.uid] = nil
        Executor.handGrudge(binding.shell, message.uid, message.generation, player, now)
        tookOver = true
    end

    local handed = false
    if tookOver or (message.fresh == true and binding.reportOwner == player) then
        handed = Executor.handHealth(binding.shell, message.uid, message.generation, player, now) == true
    end
    local last = Executor.lastReportAtMs[message.uid] or -math.huge

    if now - last < Executor.settings.reportServerGapMs then
        Executor.tellRefused(player, message, "rate_limited")
        return reject("rate_limited")
    end
    local current = Registry.read(message.uid)
    if current == nil or current.lifecycle ~= "active" then return reject("not_active") end
    local data = binding.shell:getModData()
    local treatment = tonumber(data.ProjectALifeTreatmentRevision)
    if data.ProjectALifeTreatmentGeneration == message.generation and treatment ~= nil
            and (not finite(message.healthAck) or message.healthAck < treatment)
            and Executor.treatmentHeld(data, now) then
        Executor.lastReportAtMs[message.uid] = now
        Executor.metrics.healthHeld = (Executor.metrics.healthHeld or 0) + 1
        Executor.pushHealth(binding.shell, message.uid, message.generation, nil, nil, player, nil, nil, nil,
            data.ProjectALifeTreatmentTreated == true)
        Executor.tellRefused(player, message, "treatment_pending")
        return reject("treatment_pending")
    end
    Executor.lastReportAtMs[message.uid] = now
    local rules = Executor.hitRules()
    rules.noteBound(message.uid, binding, now)
    rules.noteMove(message.uid, message.x, message.y, now)
    Executor.forgetResends(message.uid)
    Executor.ownerParks[message.uid] = nil
    if binding.reportOwner == player then binding.reportOwnerAtMs = now end
    local mutate = function(record)
        if finite(message.x) and finite(message.y) then
            record.worldPosition = { x = message.x, y = message.y,
                z = finite(message.z) and message.z or (record.worldPosition and record.worldPosition.z) or 0 }
        end
        if type(message.activity) == "string" and message.activity ~= "" then
            record.activity = message.activity

            pcall(function()
                local watchdog, animations = ProjectALife.Watchdog, ProjectALife.Animations
                local binding = watchdog ~= nil and watchdog.bindings ~= nil and watchdog.bindings[message.uid] or nil
                if binding ~= nil and binding.shell ~= nil and animations ~= nil
                        and type(animations.noteRemoteActivity) == "function" then
                    animations.noteRemoteActivity(binding.shell, message.activity)
                end
            end)
        end
        if type(message.intent) == "string" and message.intent ~= "" then record.intent = message.intent end
        if type(message.memory) == "table" then
            local merged = {}
            for key, value in pairs(message.memory) do
                if not PROTECTED[key] then merged[key] = copy(value) end
            end
            local own = type(record.memory) == "table" and record.memory or {}
            for key in pairs(PROTECTED) do
                if own[key] ~= nil then merged[key] = own[key] end
            end
            if own.hostileOverride == true then merged.hostileOverride = true end
            merged.hostileToActorKeys = Executor.mergeGrudges(own.hostileToActorKeys, merged.hostileToActorKeys)
            merged.hostileToPlayerKeys = Executor.mergeGrudges(own.hostileToPlayerKeys, merged.hostileToPlayerKeys)
            local forgiven = ProjectALife.CharacterReset
            if forgiven ~= nil and type(forgiven.strip) == "function" then
                merged.hostileToPlayerKeys = forgiven.strip(merged.hostileToPlayerKeys)
            end
            record.memory = merged
        end
    end
    local updated, updateError
    if type(message.memory) == "table" then
        updated, updateError = Registry.update(current.uid, current.revision, mutate)
    else
        updated, updateError = Registry.updateTransient(current.uid, current.revision, mutate)
    end
    if updated == nil then
        Executor.tellRefused(player, message, tostring(updateError))
        return reject(tostring(updateError))
    end
    local position = Executor.checkedReportPosition(binding, player, message, now)
    if position ~= nil then binding.reportPosition = position end
    if message.pose ~= nil then Executor.receivePose(binding, player, message.pose) end
    if finite(message.health) then
        pcall(function()
            local data = binding.shell:getModData()

            if finite(message.healthAck) then data.ProjectALifeHealthAck = message.healthAck end

            local ceiling = tonumber(data.ProjectALifeHealthCeiling)
            if Executor.ceilingHeld(data, now, message.healthAck)
                    and (ceiling == nil or tonumber(message.health) >= ceiling) then
                Executor.metrics.healthHeld = (Executor.metrics.healthHeld or 0) + 1
                if not handed then Executor.pushHealth(binding.shell, message.uid, message.generation, nil, nil, player) end
                return
            end
            data.ProjectALifeExecutorHealth = message.health

            local meleeAt = tonumber(data.ProjectALifeRemoteMeleeAtMs)
            if meleeAt ~= nil then
                local before = tonumber(data.ProjectALifeRemoteMeleeHealth)
                if before ~= nil and tonumber(message.health) < before - 0.0001 then
                    Executor.metrics.remoteMeleeLanded = (Executor.metrics.remoteMeleeLanded or 0) + 1
                    data.ProjectALifeRemoteMeleeAtMs, data.ProjectALifeRemoteMeleeHealth = nil, nil
                elseif now - meleeAt > 4000 then
                    Executor.metrics.remoteMeleeMissed = (Executor.metrics.remoteMeleeMissed or 0) + 1
                    data.ProjectALifeRemoteMeleeAtMs, data.ProjectALifeRemoteMeleeHealth = nil, nil
                end
            end
            local sim = ProjectALife.ShellSimulation
            if sim ~= nil and type(sim.setHealth) == "function" then sim.setHealth(binding.shell, message.health) end
        end)
    end
    Executor.metrics.reportsApplied = Executor.metrics.reportsApplied + 1
    return true
end

function Executor.ceilingHeld(data, now, ack)
    if type(data) ~= "table" then return false end
    local revision = tonumber(data.ProjectALifeHealthRevision)
    local pendingUntil = tonumber(data.ProjectALifeHealthPendingUntilMs)
    if revision == nil or pendingUntil == nil then return false end
    if (tonumber(now) or 0) >= pendingUntil then return false end
    local acked = tonumber(ack) or tonumber(data.ProjectALifeHealthAck)
    return acked ~= revision
end

function Executor.pushHealth(shell, uid, generation, attacker, kind, to, forgiven, noClocks, injuryState, treated)
    if shell == nil or type(uid) ~= "string" then return false, "invalid" end
    local owner = to
    if owner == nil then
        local ok, found = pcall(function() return shell:getOwnerPlayer() end)
        if ok then owner = found end
    end
    if owner == nil then return false, "no_owner" end
    local data, health, revision = nil, nil, nil
    pcall(function()
        data = shell:getModData()

        local ceiling = type(data) == "table" and tonumber(data.ProjectALifeHealthCeiling) or nil
        local pool = type(data) == "table" and tonumber(data.ProjectALifeMaximumHealth) or nil
        local simulation = ProjectALife.ShellSimulation
        if shell.isDead ~= nil and shell:isDead() then
            health = 0
        elseif ceiling ~= nil then
            health = ceiling
            if pool ~= nil and pool > 0 and health > pool then health = pool end
        elseif simulation ~= nil and type(simulation.trueHealth) == "function" then
            health = simulation.trueHealth(shell)
        else
            health = shell:getHealth()
        end
        revision = tonumber(data.ProjectALifeHealthRevision)
    end)
    if health == nil then return false, "no_health" end
    local message = { uid = uid, generation = generation, health = health, revision = revision, kind = kind }
    if injuryState == nil and type(data) == "table" and data.ProjectALifeTreatmentGeneration == generation
            and tonumber(data.ProjectALifeTreatmentRevision) ~= nil then
        local record = ProjectALife.ActorRegistry.peek(uid)
        injuryState = record ~= nil and type(record.memory) == "table" and record.memory.injury or false
    end
    if injuryState ~= nil then message.injury = copy(injuryState) end
    if forgiven == true then message.forgiven = true end
    if data ~= nil then
        local health = ProjectALife.Health
        if health ~= nil and type(health.refreshInjuries) == "function" then pcall(health.refreshInjuries, data) end
        message.wound = { zone = data.ProjectALifeLastWoundZone,
            leg = data.ProjectALifeWoundLeg == true, count = tonumber(data.ProjectALifeWounds) or 0,
            treated = treated == true or nil }
        if type(data.ProjectALifeInjuries) == "table" then
            message.wound.injuries = ProjectALife.Wounds.copy(data.ProjectALifeInjuries)
        end
        if noClocks ~= true then
            message.wound.runMs = math.max(0, (tonumber(data.ProjectALifeHitRunUntilMs) or 0) - nowMs())
            message.wound.bleedMs = math.max(0, (tonumber(data.ProjectALifeBleedOutAtMs) or 0) - nowMs())
            message.wound.downMs = math.max(0, (tonumber(data.ProjectALifeDownedUntilMs) or 0) - nowMs())
        end
    end
    if attacker ~= nil then
        local actorUid, actorGeneration = identityOf(attacker)
        if actorUid ~= nil then
            message.attackerUid, message.attackerGeneration = actorUid, actorGeneration
            if kind == "actor" and data ~= nil then
                message.damage, message.zone = data.ProjectALifeLastHumanDamage, data.ProjectALifeLastHumanHitZone
                message.ranged = data.ProjectALifeLastHumanHitRanged == true
            end
        elseif attacker.getOnlineID ~= nil then
            pcall(function() message.attackerOnline = attacker:getOnlineID() end)
        end
    end
    if type(Executor.adapters.sendTo) == "function" then
        Executor.adapters.sendTo(owner, "executorHealth", message)
    elseif type(sendServerCommand) == "function" then
        pcall(sendServerCommand, owner, "ProjectALife", "executorHealth", message)
    else
        return false, "send_unavailable"
    end
    Executor.metrics.healthPushed = (Executor.metrics.healthPushed or 0) + 1
    return true, "pushed"
end

function Executor.handHealth(shell, uid, generation, owner, now)
    if shell == nil or owner == nil or type(shell.getModData) ~= "function" then return false, "invalid" end
    local data = shell:getModData()
    if type(data) ~= "table" or tonumber(data.ProjectALifeHealthCeiling) == nil then return false, "no_ceiling" end
    now = tonumber(now) or nowMs()
    if Executor.ceilingHeld(data, now) then return false, "pending" end
    data.ProjectALifeHealthRevision = (tonumber(data.ProjectALifeHealthRevision) or 0) + 1
    data.ProjectALifeHealthPendingUntilMs = now + 3000
    data.ProjectALifeHealthAck = nil
    Executor.metrics.healthHanded = (Executor.metrics.healthHanded or 0) + 1
    return Executor.pushHealth(shell, uid, generation, nil, nil, owner, nil, true)
end

function Executor.handGrudge(shell, uid, generation, owner, now)
    local perception = ProjectALife.Perception
    local held = perception ~= nil and type(perception.attackers) == "table" and perception.attackers[uid] or nil
    if type(held) ~= "table" or held.attacker == nil or owner == nil then return false, "none" end
    local left = (tonumber(held.untilMs) or 0) - (tonumber(now) or nowMs())
    if left <= 0 then return false, "expired" end
    local attacker = held.attacker
    local message = { uid = uid, generation = generation, kind = held.kind or "player",
        holdMs = math.min(left, Executor.settings.grudgeHandMs) }
    local actorUid, actorGeneration = identityOf(attacker)
    if actorUid ~= nil then
        message.attackerUid, message.attackerGeneration = actorUid, actorGeneration
    elseif attacker.getOnlineID ~= nil then
        message.attackerOnline = attacker:getOnlineID()
    else
        return false, "no_identity"
    end
    if type(Executor.adapters.sendTo) == "function" then
        Executor.adapters.sendTo(owner, "executorGrudge", message)
    elseif type(sendServerCommand) == "function" then
        pcall(sendServerCommand, owner, "ProjectALife", "executorGrudge", message)
    else
        return false, "send_unavailable"
    end
    Executor.metrics.grudgesHanded = (Executor.metrics.grudgesHanded or 0) + 1
    return true, "handed"
end

function Executor.applyDeath(player, message)
    if not Executor.serverDelegates() then return reject("not_delegating") end
    if type(message) ~= "table" or type(message.uid) ~= "string" or not finite(message.generation) then
        return reject("bad_message")
    end
    local Watchdog, Registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local binding = Watchdog and Watchdog.bindings[message.uid] or nil
    if binding == nil or binding.generation ~= message.generation then return reject("not_bound") end
    if not Executor.bindingMatches(binding, message.uid) then return reject("shell_identity_changed") end
    if not ownerMatches(binding.shell, player) then return reject("not_owner") end
    local current = Registry.read(message.uid)
    if current == nil then return reject("not_found") end
    if current.lifecycle == "dead" then return true end
    local position = current.worldPosition
    if finite(message.x) and finite(message.y) then
        position = { x = message.x, y = message.y, z = finite(message.z) and message.z or 0 }
    end
    local now = nowMs()
    pcall(function() binding.shell:getModData().ProjectALifeExecutorDeadAtMs = now end)
    local dead, deadError = Registry.markDead(current.uid, current.revision, current.generation, position)
    if dead == nil then return reject(tostring(deadError)) end

    local reported = Executor.trackReported(binding.shell, current.uid, current.generation, now)
    if reported ~= nil then

        local body = Executor.bodyFacts(binding.shell)
        reported.killer = Executor.acceptKiller(message, body.x ~= nil and body or position)
    end
    pcall(function()
        local lifecycle = ProjectALife.Lifecycle
        if lifecycle ~= nil and type(lifecycle.trackCorpse) == "function" then
            lifecycle.trackCorpse(current.uid, position, now)
        end
    end)
    pcall(function()
        local decisions = ProjectALife.DecisionLoop
        if decisions ~= nil then decisions.forget(current.uid, current.generation, "executor_death") end
    end)
    pcall(function()
        local leader = ProjectALife.ModuleLeader
        if leader ~= nil then leader.onActorDied(current) end
    end)
    pcall(function() Watchdog.unbind(current.uid, current.generation, "executor_death") end)
    pcall(function()
        ProjectALife.Telemetry.emit("actor_died", { uid = current.uid, generation = current.generation, remote = true })
    end)
    Executor.metrics.deathsApplied = Executor.metrics.deathsApplied + 1
    return true
end

function Executor.acceptKiller(message, position)
    local kind = type(message) == "table" and message.killerKind or nil
    if kind == nil then return nil end
    local metrics = Executor.metrics
    local accepted
    if kind == "zombie" then
        accepted = { kind = "zombie" }
    elseif (kind == "actor" or kind == "player") and type(message.killerKey) == "string"
            and #message.killerKey >= 1 and #message.killerKey <= 64 then
        if kind == "actor" then
            accepted = Executor.actorKiller(message.killerKey)
        else
            accepted = Executor.playerKiller(message.killerKey, position)
        end
    end
    if accepted ~= nil then
        metrics.killersReported = (metrics.killersReported or 0) + 1
    else
        metrics.killersRefused = (metrics.killersRefused or 0) + 1
    end
    return accepted
end

function Executor.actorKiller(uid)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and (registry.peek or registry.read)(uid) or nil
    if record == nil then return nil end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    local body = binding ~= nil and binding.shell or nil
    local facts = Executor.bodyFacts(body)
    local where = type(record.worldPosition) == "table" and record.worldPosition or {}
    return { kind = "actor", key = uid, x = facts.x or tonumber(where.x), y = facts.y or tonumber(where.y),
        object = body }
end

function Executor.playerKiller(key, position)
    if type(getOnlinePlayers) ~= "function" then return nil end
    local reputation = ProjectALife.Reputation
    if reputation == nil or type(reputation.playerKey) ~= "function" then return nil end
    local players = getOnlinePlayers()
    if players == nil or players.size == nil then return nil end
    local reach = Executor.settings.killerReachTiles
    for index = 0, players:size() - 1 do
        local player = players:get(index)
        if player ~= nil and reputation.playerKey(player) == key then
            local facts = Executor.bodyFacts(player)
            if type(position) == "table" and finite(position.x) and finite(position.y) then
                if facts.x == nil or math.abs(facts.x - position.x) > reach
                        or math.abs(facts.y - position.y) > reach then return nil end
            end
            return { kind = "player", key = key, x = facts.x, y = facts.y, object = player }
        end
    end
    return nil
end

function Executor.reportedKiller(shell)
    if shell == nil or not Executor.serverDelegates() then return nil end
    local order, newest = Executor.dyingOrder, nil
    for index = 1, #order do
        local entry = Executor.dying[order[index]]
        if entry ~= nil and entry.shell == shell
                and (newest == nil or (tonumber(entry.atMs) or 0) >= (tonumber(newest.atMs) or 0)) then
            newest = entry
        end
    end
    local killer = newest ~= nil and newest.reported == true and newest.killer or nil
    if type(killer) ~= "table" then return nil end
    return killer.kind, killer.key, killer.x, killer.y, killer.object
end

function Executor.killerOf(shell)
    local attribution = ProjectALife.KillAttribution
    if shell == nil or attribution == nil or type(attribution.peek) ~= "function" then return nil end
    local ok, kind, key = pcall(attribution.peek, shell)
    if not ok or (kind ~= "actor" and kind ~= "player" and kind ~= "zombie") then return nil end
    if type(key) ~= "string" or #key > 64 then key = nil end
    return kind, key
end

function Executor.recentRemoteDeath(shell, now)
    local ok, stamp = pcall(function() return tonumber(shell:getModData().ProjectALifeExecutorDeadAtMs) end)
    if not ok or stamp == nil then return false end
    now = now or nowMs()
    return now >= stamp and now - stamp < Executor.settings.deathStampGraceMs
end

function Executor.bodyFacts(shell)
    local facts = {}
    local kind = type(shell)
    if kind ~= "userdata" and kind ~= "table" then return facts end
    if shell.getOnlineID ~= nil then facts.onlineId = tonumber(shell:getOnlineID()) end
    if shell.getX ~= nil and shell.getY ~= nil then
        facts.x, facts.y = tonumber(shell:getX()), tonumber(shell:getY())
        facts.z = shell.getZ ~= nil and tonumber(shell:getZ()) or 0
    end
    return facts
end

function Executor.killDelegated(shell, uid, reason)
    if not Executor.serverDelegates() then return false, "not_delegating" end
    if shell == nil or type(uid) ~= "string" then return false, "invalid" end
    local now = nowMs()
    local entry = Executor.dying[uid]
    if entry ~= nil and entry.shell == shell then

        if reason ~= nil and entry.reason == "server_kill" then entry.reason = tostring(reason) end
        return true, "already"
    end
    local generation
    if shell.getModData ~= nil then
        local data = shell:getModData()
        generation = type(data) == "table" and tonumber(data.ProjectALifeGeneration) or nil
    end
    if generation == nil then
        local watchdog = ProjectALife.Watchdog
        local binding = watchdog ~= nil and watchdog.bindings[uid] or nil
        generation = binding ~= nil and binding.generation or nil
    end
    entry = Executor.trackDeath(shell, uid, generation, tostring(reason or "server_kill"), now)
    Executor.pushDeath(entry, now)
    Executor.metrics.deathsHanded = Executor.metrics.deathsHanded + 1
    return true, "handed"
end

function Executor.trackDeath(shell, uid, generation, reason, now)
    local facts = Executor.bodyFacts(shell)
    if Executor.dying[uid] == nil then
        local order = Executor.dyingOrder
        if #order >= 64 then Executor.dying[table.remove(order, 1)] = nil end
        order[#order + 1] = uid
    end
    local entry = { uid = uid, generation = generation, shell = shell, atMs = now, pushes = 0,
        reason = reason, onlineId = facts.onlineId, x = facts.x, y = facts.y, z = facts.z }
    Executor.dying[uid] = entry
    Executor.announce(uid, generation, facts.onlineId, facts.x, facts.y, facts.z, now)
    return entry
end

function Executor.trackReported(shell, uid, generation, now)
    if not Executor.serverDelegates() or shell == nil or type(uid) ~= "string" then return nil end
    local entry = Executor.trackDeath(shell, uid, generation, "reported", now or nowMs())
    entry.reported = true
    Executor.metrics.deathsReported = Executor.metrics.deathsReported + 1
    return entry
end

function Executor.takeReported(shell, uid, generation)
    local entry = type(uid) == "string" and Executor.dying[uid] or nil
    if entry == nil or entry.reported ~= true or entry.settled == true or entry.shell ~= shell then return false end
    if generation ~= nil and entry.generation ~= nil and entry.generation ~= generation then return false end
    entry.settled = true
    return true
end

function Executor.sameLife(entry)
    local shell = entry.shell
    local kind = type(shell)
    if (kind ~= "userdata" and kind ~= "table") or shell.getModData == nil then return false end
    if shell.hasModData ~= nil and shell:hasModData() ~= true then return false end
    local data = shell:getModData()
    if type(data) ~= "table" or data.ProjectALifeUID ~= entry.uid then return false end
    return entry.generation == nil or tonumber(data.ProjectALifeGeneration) == entry.generation
end

function Executor.announce(uid, generation, onlineId, x, y, z, now)
    Executor.announced[uid] = { g = generation, id = onlineId, x = x, y = y, z = z,
        untilMs = (tonumber(now) or nowMs()) + Executor.settings.diedAnnounceMs }
    Executor.diedCache = nil
end

function Executor.diedFrame(now)
    now = tonumber(now) or nowMs()
    local cache = Executor.diedCache
    if cache ~= nil and cache.atMs == now then return cache.frame end
    local frame, expired, count = nil, nil, 0
    for uid, fact in pairs(Executor.announced) do
        if now >= fact.untilMs then
            expired = expired or {}
            expired[#expired + 1] = uid
        elseif count < 32 then
            frame = frame or {}
            frame[uid] = { g = fact.g, id = fact.id, x = fact.x, y = fact.y, z = fact.z }
            count = count + 1
        end
    end
    for _, uid in ipairs(expired or {}) do Executor.announced[uid] = nil end
    Executor.diedCache = { atMs = now, frame = frame }
    return frame
end

function Executor.pushDeath(entry, now)
    local shell = entry.shell
    if shell == nil or shell.getOwnerPlayer == nil then return false, "no_owner" end
    local owner = shell:getOwnerPlayer()
    if owner == nil then return false, "no_owner" end
    local message = { uid = entry.uid, generation = entry.generation, health = 0, death = true,
        onlineId = entry.onlineId, x = entry.x, y = entry.y, z = entry.z }
    local sent = false
    if type(Executor.adapters.sendTo) == "function" then
        Executor.adapters.sendTo(owner, "executorHealth", message)
        sent = true
    elseif type(sendServerCommand) == "function" then
        sent = pcall(sendServerCommand, owner, "ProjectALife", "executorHealth", message)
    end
    if not sent then return false, "send_unavailable" end
    entry.pushes, entry.pushedAtMs, entry.owner = entry.pushes + 1, now, owner
    Executor.metrics.deathPushes = Executor.metrics.deathPushes + 1
    return true
end

function Executor.corpseState(shell)
    local state = { corpse = false }
    local kind = type(shell)
    if kind ~= "userdata" and kind ~= "table" then
        state.corpse = true
        return state
    end
    if shell.isOnDeathDone ~= nil and shell:isOnDeathDone() == true then state.corpse = true end
    if shell.getCurrentSquare ~= nil and shell:getCurrentSquare() == nil then state.corpse, state.gone = true, true end
    if shell.getHealth ~= nil then state.health = tonumber(shell:getHealth()) end
    if shell.isOnKillDone ~= nil then state.killDone = shell:isOnKillDone() == true end
    if shell.getOnlineID ~= nil then state.onlineId = shell:getOnlineID() end
    return state
end

function Executor.finishOnServer(entry, how)
    local shell = entry.shell
    if entry.finishedBy ~= nil or shell == nil then return false end
    entry.finishedBy = how
    if shell.getCurrentSquare == nil or shell:getCurrentSquare() == nil then return false end
    if shell.setHealth ~= nil then shell:setHealth(0) end
    if type(shell.die) ~= "function" then return false end
    local ok = pcall(shell.die, shell)
    if how == "forced" then Executor.metrics.deathForced = Executor.metrics.deathForced + 1
    else Executor.metrics.deathFallbacks = Executor.metrics.deathFallbacks + 1 end
    return ok
end

function Executor.deathLine(entry, state, mark)
    if Executor.deathLines >= 200 then return end
    Executor.deathLines = Executor.deathLines + 1
    local owner = "nil"
    local player = entry.owner
    if player ~= nil and player.getUsername ~= nil then owner = tostring(player:getUsername()) end
    print("[ALIFE-LIFECYCLE] " .. (mark == "revived" and "server_revived" or "server_death")
        .. " uid=" .. tostring(entry.uid) .. " generation=" .. tostring(entry.generation)
        .. " after=" .. tostring(mark) .. " via=" .. tostring(entry.reason)
        .. " health=" .. tostring(state.health) .. " onlineId=" .. tostring(state.onlineId)
        .. " killDone=" .. tostring(state.killDone) .. " corpse=" .. tostring(state.corpse)
        .. " pushes=" .. tostring(entry.pushes) .. " owner=" .. owner
        .. " finished=" .. tostring(entry.finishedBy))
end

function Executor.settleDeaths(now)
    local order = Executor.dyingOrder
    if #order == 0 then return 0 end
    local settings, handled = Executor.settings, 0
    for index = #order, 1, -1 do
        local uid = order[index]
        local entry = Executor.dying[uid]
        local done = entry == nil
        if not done then
            local age = now - entry.atMs
            local state = Executor.corpseState(entry.shell)
            if entry.corpseAtMs == nil then
                if not Executor.sameLife(entry) then
                    entry.corpseAtMs, entry.reused = now, true
                elseif state.corpse then
                    entry.corpseAtMs = now
                end
            end
            if entry.reused == true then state.health, state.onlineId = nil, nil end
            if entry.corpseAtMs ~= nil then
                state.corpse = true
            elseif entry.reported == true then

                if age >= settings.deathFallbackMs then Executor.finishOnServer(entry, "fallback") end
            elseif state.health ~= nil and state.health > 0 then
                if entry.revived ~= true and age >= settings.deathPushIntervalMs then
                    entry.revived = true
                    Executor.metrics.deathRevived = Executor.metrics.deathRevived + 1
                    Executor.deathLine(entry, state, "revived")
                end
                if age >= settings.deathForceMs then
                    Executor.finishOnServer(entry, "forced")
                elseif entry.pushes < settings.deathPushLimit
                        and now - (entry.pushedAtMs or -math.huge) >= settings.deathPushIntervalMs then
                    Executor.pushDeath(entry, now)
                end
            elseif age >= settings.deathFallbackMs then
                Executor.finishOnServer(entry, "fallback")
            end
            if age >= 1000 and entry.logged1 ~= true then
                entry.logged1 = true
                Executor.deathLine(entry, state, "1s")
            end
            if age >= 5000 and entry.logged5 ~= true then
                entry.logged5 = true
                Executor.deathLine(entry, state, "5s")
            end
            done = (entry.corpseAtMs ~= nil and entry.logged5 == true) or age >= settings.deathTrackMs
        end
        if done then
            table.remove(order, index)
            if entry ~= nil and Executor.dying[uid] == entry then Executor.dying[uid] = nil end
            handled = handled + 1
        end
    end
    return handled
end

function Executor.auditOwners(now)
    local watchdog, adapter = ProjectALife.Watchdog, ProjectALife.ShellAdapter
    if watchdog == nil or adapter == nil or type(adapter.shellAlive) ~= "function" then return 0 end
    local settings = Executor.settings
    if now - Executor.lastOwnerAuditAtMs < settings.ownerAuditIntervalMs then return 0 end
    Executor.lastOwnerAuditAtMs = now
    local order = watchdog.order
    local count = #order
    if count == 0 then return 0 end
    for _ = 1, math.min(count, settings.ownerAuditBudget) do
        Executor.ownerCursor = (Executor.ownerCursor % count) + 1
        local uid = order[Executor.ownerCursor]
        local binding = uid ~= nil and watchdog.bindings[uid] or nil

        if binding ~= nil and Executor.auditOwner(binding, now) then return 1 end
    end
    return 0
end

function Executor.auditOwner(binding, now)
    local shell = binding.shell
    local kind = type(shell)
    if (kind ~= "userdata" and kind ~= "table") or shell.getOwnerPlayer == nil
            or shell.getX == nil or shell.getY == nil
            or not ProjectALife.ShellAdapter.shellAlive(shell) then return false end
    local owner = shell:getOwnerPlayer()
    if owner ~= nil and (owner.getX == nil or owner.getY == nil) then owner = nil end
    local settings = Executor.settings
    local last = Executor.lastReportAtMs[binding.uid]
    local since = math.max(tonumber(binding.boundAtMs) or now, tonumber(last) or -math.huge)
    local droppedAt = binding.ownerDroppedAtMs
    local dropped = owner ~= nil and droppedAt ~= nil and (last == nil or droppedAt > last)
        and now - droppedAt >= settings.droppedGraceMs
    if not dropped and now - since < settings.unreportedMs then return false end
    local reach = Executor.ownerReach(owner, shell)
    if binding.unreportedLogged ~= true then
        binding.unreportedLogged = true
        Executor.metrics.unreported = Executor.metrics.unreported + 1
        Executor.ownerLine("unreported", binding, owner, reach, now - since, dropped)
    end
    if reach ~= nil and (reach >= settings.ownerWindowOut or (dropped and reach > settings.ownerWindowIn)) then
        return Executor.parkForOwner(binding, owner, reach, now)
    end
    if reach ~= nil and reach > settings.ownerWindowIn then return false end
    if not dropped and now - since < Executor.unreportedQuietMs(binding.uid, owner) then return false end
    return Executor.recoverUnreported(binding, owner, reach, now)
end

function Executor.unreportedQuietMs(uid, owner)
    local settings = Executor.settings
    local base = owner == nil and settings.unownedQuietMs or settings.unreportedMs
    return base * 2 ^ math.min(Executor.ownerParks[uid] or 0, settings.parkBackoffLimit)
end

function Executor.ownerReach(owner, shell)
    if owner == nil then return nil end
    return math.max(math.abs((tonumber(owner:getX()) or 0) - (tonumber(shell:getX()) or 0)),
        math.abs((tonumber(owner:getY()) or 0) - (tonumber(shell:getY()) or 0)))
end

function Executor.recoverUnreported(binding, owner, reach, now)
    local settings = Executor.settings
    local record = Executor.replicaResends[binding.uid]
    if record == nil or record.count < settings.replicaResendLimit then
        return Executor.resendReplica(binding, owner, reach, now)
    end
    if now - record.atMs < settings.replicaResendMs then return false end
    local uid = binding.uid
    if Executor.parkForOwner(binding, owner, reach, now) then
        Executor.ownerParks[uid] = (Executor.ownerParks[uid] or 0) + 1
        return true
    end
    Executor.forgetResends(uid)
    return Executor.resendReplica(binding, owner, reach, now)
end

function Executor.forgetResends(uid)
    if Executor.replicaResends[uid] == nil then return false end
    Executor.replicaResends[uid] = nil
    Executor.replicaResendCount = math.max(0, (Executor.replicaResendCount or 1) - 1)
    return true
end

function Executor.ownerLine(event, binding, owner, reach, quietMs, dropped)
    if Executor.deathLines >= 200 then return end
    Executor.deathLines = Executor.deathLines + 1
    local name, onlineId = "nil", nil
    if owner ~= nil and owner.getUsername ~= nil then name = tostring(owner:getUsername()) end
    local shell = binding.shell
    if shell ~= nil and shell.getOnlineID ~= nil then onlineId = shell:getOnlineID() end
    print("[ALIFE-LIFECYCLE] " .. event .. " uid=" .. tostring(binding.uid) .. " generation="
        .. tostring(binding.generation) .. " onlineId=" .. tostring(onlineId) .. " owner=" .. name
        .. " reach=" .. tostring(math.floor((tonumber(reach) or 0) * 10 + 0.5) / 10)
        .. " quietMs=" .. tostring(quietMs) .. " dropped=" .. tostring(dropped == true))
end

function Executor.parkForOwner(binding, owner, reach, now)
    local spawn = ProjectALife.SpawnService
    if spawn == nil or type(spawn.dehydrate) ~= "function" then return false end
    local uid = binding.uid
    local parked = spawn.dehydrate(uid, "owner_window")
    if parked ~= true then return false end
    local population = ProjectALife.Population
    if population ~= nil and type(population.holdNear) == "function" then
        population.holdNear(uid, Executor.settings.ownerWindowIn)
    end
    Executor.forgetResends(uid)
    Executor.metrics.ownerWindowParked = Executor.metrics.ownerWindowParked + 1
    Executor.ownerLine("owner_window_parked", binding, owner, reach, nil, nil)
    return true
end

function Executor.resendReplica(binding, owner, reach, now, asked)
    local settings = Executor.settings
    local watchdog = ProjectALife.Watchdog
    if type(watchdog.forceRecovery) ~= "function" then return false end
    local uid = binding.uid
    local record = Executor.replicaResends[uid] or { count = 0, atMs = -math.huge }
    local limit = asked == true and settings.replicaAskLimit or settings.replicaResendLimit
    local spacing = asked == true and settings.replicaAskSpacingMs or settings.replicaResendMs
    if record.count >= limit or now - record.atMs < spacing then
        return false
    end
    record.count, record.atMs = record.count + 1, now
    if Executor.replicaResends[uid] == nil then

        Executor.replicaResendCount = (Executor.replicaResendCount or 0) + 1
        if Executor.replicaResendCount > 256 then
            Executor.replicaResends, Executor.replicaResendCount = {}, 1
        end
    end
    Executor.replicaResends[uid] = record
    Executor.ownerLine(asked == true and "replica_asked" or "replica_resent", binding, owner, reach, nil, nil)
    local recovered = watchdog.forceRecovery(uid, "replica_missing")
    if recovered then Executor.metrics.replicaResent = Executor.metrics.replicaResent + 1 end
    return recovered == true
end

function Executor.refuseAsk(reason)
    local by = Executor.metrics.replicaAskRefused
    if type(by) ~= "table" then
        by = {}
        Executor.metrics.replicaAskRefused = by
    end
    by[reason] = (by[reason] or 0) + 1
    return false, reason
end

function Executor.askReplica(player, ask, now)
    if type(ask) ~= "table" or type(ask.uid) ~= "string" or #ask.uid > 128
            or not finite(ask.generation) or not finite(ask.onlineId) or ask.onlineId == -1 then
        return Executor.refuseAsk("invalid")
    end
    local watchdog, adapter = ProjectALife.Watchdog, ProjectALife.ShellAdapter
    local binding = watchdog ~= nil and watchdog.bindings[ask.uid] or nil
    if binding == nil or binding.generation ~= ask.generation then return Executor.refuseAsk("not_bound") end
    local shell = binding.shell
    if adapter == nil or type(adapter.shellAlive) ~= "function" or not adapter.shellAlive(shell)
            or shell.getOnlineID == nil or shell:getOnlineID() ~= ask.onlineId then
        return Executor.refuseAsk("other_body")
    end
    if Executor.engineOwner(shell) ~= player then return Executor.refuseAsk("not_owner") end
    local settings = Executor.settings
    local boundAt = tonumber(binding.boundAtMs) or now
    if now - boundAt < settings.replicaMissingMs then return Executor.refuseAsk("newborn") end
    local last = Executor.lastReportAtMs[ask.uid]
    if last ~= nil and now - last < settings.replicaAskQuietMs then return Executor.refuseAsk("reported") end
    local reach = math.max(math.abs((tonumber(player:getX()) or 0) - (tonumber(shell:getX()) or 0)),
        math.abs((tonumber(player:getY()) or 0) - (tonumber(shell:getY()) or 0)))
    if reach > settings.ownerWindowIn then return Executor.refuseAsk("far") end
    if not Executor.resendReplica(binding, player, reach, now, true) then return Executor.refuseAsk("limit") end
    Executor.metrics.replicaAsked = Executor.metrics.replicaAsked + 1
    return true
end

function Executor.applyReplicaMissing(player, message)
    if not Executor.serverDelegates() or player == nil or type(message) ~= "table"
            or type(message.bodies) ~= "table" then return 0 end
    local now, rebuilt = nowMs(), 0
    for index = 1, math.min(#message.bodies, Executor.settings.replicaAskBatch) do
        if Executor.askReplica(player, message.bodies[index], now) then rebuilt = rebuilt + 1 end
    end
    return rebuilt
end

function Executor.cellOnlineIds()
    local ids = {}
    if type(getCell) ~= "function" then return ids end
    local cell = getCell()
    local zombies = cell ~= nil and cell.getZombieList ~= nil and cell:getZombieList() or nil
    if zombies == nil then return ids end
    for index = 0, zombies:size() - 1 do
        local shell = zombies:get(index)
        if shell ~= nil and shell.getOnlineID ~= nil then ids[shell:getOnlineID()] = true end
    end
    return ids
end

function Executor.replicaObserved(client, onlineId)
    local shell = type(client.observed) == "table" and client.observed[onlineId] or nil
    if shell == nil or shell.getOnlineID == nil or shell.getCurrentSquare == nil then return false end
    return shell:getOnlineID() == onlineId and shell:getCurrentSquare() ~= nil
end

function Executor.auditReplicas(now)
    if not Executor.executorSide() then return 0 end
    local client = ProjectALife.AnimationClient
    if client == nil or type(client.announced) ~= "table" or type(client.announcedIdentity) ~= "function" then
        return 0
    end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    if player == nil then return 0 end
    local settings, watch, records = Executor.settings, Executor.replicaWatch, Executor.mirror.records or {}
    local asks, cellIds, unseen = {}, nil, {}
    for onlineId in pairs(client.announced) do
        local uid, generation = client.announcedIdentity(onlineId, now)
        local record = uid ~= nil and records[uid] or nil
        local p = type(record) == "table" and record.worldPosition or nil
        if finite(generation) and type(p) == "table"
                and Executor.playerNear(player, p.x, p.y, settings.replicaMissingRadius)
                and not Executor.replicaObserved(client, onlineId) then
            unseen[onlineId] = { uid = uid, generation = generation }
        end
    end

    for onlineId, body in pairs(unseen) do
        local key = body.uid .. ":" .. tostring(body.generation)
        local entry = watch[onlineId]
        if entry == nil or entry.key ~= key then
            entry = { key = key, sinceMs = now, askedAtMs = -math.huge, asks = 0 }
            watch[onlineId] = entry
        end
        if now - entry.sinceMs >= settings.replicaMissingMs and now - entry.askedAtMs >= settings.replicaAskMs
                and entry.asks < settings.replicaAskLimit and #asks < settings.replicaAskBatch then
            cellIds = cellIds or Executor.cellOnlineIds()
            if cellIds[onlineId] then
                entry.sinceMs = now
            else
                entry.askedAtMs, entry.asks = now, entry.asks + 1
                asks[#asks + 1] = { uid = body.uid, generation = body.generation, onlineId = onlineId }
            end
        end
    end
    local gone = {}
    for onlineId in pairs(watch) do
        if unseen[onlineId] == nil then gone[#gone + 1] = onlineId end
    end
    for _, onlineId in ipairs(gone) do watch[onlineId] = nil end
    if #asks == 0 then return 0 end
    local message = { bodies = asks }
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorReplicaMissing", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorReplicaMissing", message)
    end
    Executor.metrics.replicaAsks = Executor.metrics.replicaAsks + #asks
    return #asks
end

function Executor.applyReleased(player, message)
    if not Executor.serverDelegates() or type(message) ~= "table" or type(message.uid) ~= "string"
            or #message.uid > 128 or not finite(message.generation) then return false end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and watchdog.bindings[message.uid] or nil
    if binding == nil or binding.generation ~= message.generation
            or not Executor.bindingMatches(binding, message.uid)
            or not ownerMatches(binding.shell, player) then return false end
    binding.ownerDroppedAtMs = nowMs()
    binding.unreportedLogged = nil
    Executor.metrics.ownerDropped = Executor.metrics.ownerDropped + 1
    return true
end

function Executor.applySupport(player, message)
    if not Executor.serverDelegates() then return reject("not_delegating") end
    if type(message) ~= "table" or type(message.uid) ~= "string" or not finite(message.generation)
            or type(message.contact) ~= "table" then
        return reject("bad_message")
    end
    local Watchdog, Registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local binding = Watchdog and Watchdog.bindings[message.uid] or nil
    if binding == nil or binding.generation ~= message.generation then return reject("not_bound") end
    if not Executor.bindingMatches(binding, message.uid) then return reject("shell_identity_changed") end
    if not ownerMatches(binding.shell, player) then return reject("not_owner") end
    local record = Registry.read(message.uid)
    if record == nil or record.lifecycle ~= "active" then return reject("not_active") end
    local contact = { x = tonumber(message.contact.x), y = tonumber(message.contact.y),
        z = tonumber(message.contact.z) or 0 }
    if not finite(contact.x) or not finite(contact.y) then return reject("bad_contact") end
    if type(message.contact.playerKey) == "string" then contact.playerKey = message.contact.playerKey end
    if type(message.contact.targetUid) == "string" then contact.targetUid = message.contact.targetUid end
    local ok, reason
    if type(Executor.adapters.supportRequest) == "function" then
        ok, reason = Executor.adapters.supportRequest(record, binding.shell, contact, nowMs())
    else
        local support = ProjectALife.Support
        if support == nil or type(support.request) ~= "function" then return reject("support_unavailable") end
        local called, result, why = pcall(support.request, record, binding.shell, contact, nowMs())
        ok, reason = called and result == true, called and why or tostring(result)
    end
    if ok then Executor.metrics.supportApplied = Executor.metrics.supportApplied + 1
    else Executor.metrics.supportRefused = Executor.metrics.supportRefused + 1 end
    Executor.metrics.lastSupportReason = tostring(reason)
    return ok == true, reason
end

Executor.biteSettings = { perShellMs = 250, maxText = 16 }
Executor.biteKinds = { scratch = true, laceration = true, bite = true, killed = true }
Executor.biteRelayAtMs = setmetatable({}, { __mode = "k" })
Executor.biteApplyAtMs = setmetatable({}, { __mode = "k" })

function Executor.relayBite(shell, kind)
    if not Executor.biteKinds[kind] then return false, "invalid" end
    local uid = shell ~= nil and Executor.byShell[shell] or nil
    local entry = uid ~= nil and Executor.executed[uid] or nil
    if entry == nil or not Executor.clientAuthority() or Executor.authorityFor(shell) ~= true then
        return false, "not_owner"
    end
    local now = nowMs()
    local last = Executor.biteRelayAtMs[shell]
    if last ~= nil and now - last < Executor.biteSettings.perShellMs then return false, "rate_limited" end
    local message = { uid = uid, generation = entry.generation, kind = kind }
    pcall(function() message.x, message.y, message.z = shell:getX(), shell:getY(), shell:getZ() end)
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorBite", message)
    elseif type(sendClientCommand) == "function" then
        if not pcall(sendClientCommand, "ProjectALife", "executorBite", message) then return false, "send_failed" end
    else
        return false, "relay_unavailable"
    end
    Executor.biteRelayAtMs[shell] = now
    Executor.metrics.bitesRelayed = (Executor.metrics.bitesRelayed or 0) + 1
    return true
end

function Executor.applyBite(player, message)
    if not Executor.serverDelegates() then return reject("not_delegating") end
    if type(message) ~= "table" or type(message.uid) ~= "string" or #message.uid > 128
            or not finite(message.generation) or not Executor.biteKinds[message.kind] then
        return reject("bad_message")
    end
    local Watchdog, Registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local binding = Watchdog and Watchdog.bindings[message.uid] or nil
    if binding == nil or binding.generation ~= message.generation then return reject("not_bound") end
    if not Executor.bindingMatches(binding, message.uid) then return reject("shell_identity_changed") end
    local shell = binding.shell
    if not ownerMatches(shell, player) then return reject("not_owner") end
    if not Executor.playerNear(player, shell:getX(), shell:getY(), Executor.authority.unownedTrustRadius) then
        return reject("far_from_sender")
    end
    local record = Registry and Registry.read(message.uid) or nil
    if record == nil or record.lifecycle ~= "active" or record.generation ~= message.generation
            or shell:isDead() then return reject("not_active") end
    local now = nowMs()
    local last = Executor.biteApplyAtMs[shell]
    if last ~= nil and now - last < Executor.biteSettings.perShellMs then return reject("bite_rate") end
    Executor.biteApplyAtMs[shell] = now
    local sim = ProjectALife.ShellSimulation
    if sim == nil or type(sim.woundInfects) ~= "function" or type(sim.infect) ~= "function"
            or type(ZombRand) ~= "function" then return reject("bite_unavailable") end
    local data = shell:getModData()
    if type(data) ~= "table" then return reject("no_data") end
    data.ProjectALifeLastWound = message.kind
    data.ProjectALifeLastBiteAtMs = now
    if sim.woundInfects(message.kind, ZombRand(100))
            and sim.infect(shell, message.kind, ZombRand(1001) / 1000) then
        Executor.metrics.bitesInfected = (Executor.metrics.bitesInfected or 0) + 1
    end
    Executor.metrics.bitesApplied = (Executor.metrics.bitesApplied or 0) + 1
    return true
end

function Executor.relayPlayerHit(actor, target, weaponType)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" then
        return false, "player_hit_invalid"
    end
    local entry = Executor.executed[actor.uid]
    if entry == nil or entry.generation ~= actor.generation
            or not Executor.authorityFor(entry.shell) then return false, "not_owner" end
    local relay = ProjectALife.NPCHitRelay
    local attack = relay and relay.attacks[entry.shell]
    if attack == nil then return false, "unpaid_attack" end
    Executor.reportCombat(entry, nowMs())
    local message = { uid = actor.uid, generation = actor.generation,
        weapon = type(weaponType) == "string" and weaponType or nil, attack = attack }
    if target ~= nil and type(target.getOnlineID) == "function" then
        local ok, id = pcall(function() return target:getOnlineID() end)
        if ok then message.online = tonumber(id) end
    end
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorPlayerHit", message)
    elseif type(sendClientCommand) == "function" then
        local sent = pcall(sendClientCommand, "ProjectALife", "executorPlayerHit", message)
        if not sent then return false, "player_hit_send_failed" end
    else
        return false, "player_hit_relay_unavailable"
    end
    Executor.metrics.playerHitsRelayed = Executor.metrics.playerHitsRelayed + 1
    return true
end

function Executor.applyPlayerHit(player, message, attemptOnly)
    if not Executor.serverDelegates() then return reject("not_delegating") end
    if type(message) ~= "table" or type(message.uid) ~= "string" or #message.uid > 128
            or not finite(message.generation) or not finite(message.online) or message.online < 0
            or message.online ~= math.floor(message.online) or not finite(message.attack)
            or message.attack < 1 or message.attack ~= math.floor(message.attack)
            or type(message.weapon) ~= "string" or #message.weapon > 128 then
        return reject("bad_message")
    end
    local Watchdog, Registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local hits = Executor.hitRules()
    local binding = Watchdog and Watchdog.bindings[message.uid] or nil
    local graced = false
    if binding == nil or binding.generation ~= message.generation then
        local held = hits.grace(message.uid, message.generation, nowMs())
        if held == nil then return reject("not_bound") end
        binding, graced = held, true
    end
    if not graced and not Executor.bindingMatches(binding, message.uid) then
        return reject("shell_identity_changed")
    end

    if not ownerMatches(binding.shell, player) then return reject("not_owner") end
    local record = Registry.read(message.uid)
    if record == nil or record.lifecycle ~= "active" or record.generation ~= message.generation
            or binding.shell:isDead() then return reject("not_active") end
    local victim = Executor.playerByOnlineId(message.online)
    if victim == nil then return reject("no_victim") end
    local policy, relations = ProjectALife.TargetPolicy, ProjectALife.Relations
    if policy == nil or not policy.canAttack(victim) then return reject("protected_target") end
    local hostile, hostileWhy
    if relations ~= nil then hostile, hostileWhy = relations.hostileToPlayer(record, victim) end
    if not hostile then return reject("not_hostile") end
    local shell, last, now = binding.shell, binding.npcHitAttack, nowMs()
    if last == nil or last.owner ~= player or last.id ~= message.attack
            or last.weapon ~= message.weapon or now - last.atMs > 1500 then return reject("unpaid_attack") end
    local weapon = last.item

    if weapon == nil or ProjectALife.Weapons.current(shell) ~= weapon then return reject("stowed_weapon") end
    if type(shell.getX) ~= "function" or type(shell.getY) ~= "function" or type(shell.getZ) ~= "function"
            or type(victim.getX) ~= "function" or type(victim.getY) ~= "function"
            or type(victim.getZ) ~= "function" then return reject("invalid_body") end
    local ranged = weapon:isAimedFirearm() == true
    local reach = tonumber(weapon:getMaxRange()) or 1
    if ranged then
        reach = math.max(2, math.min(40, reach))
        if shell:getModData().ProjectALifeConduct == "sniper" then reach = reach * 1.5 end
    else reach = math.max(0.7, math.min(3, reach)) end
    local origin = Executor.reportHitOrigin(binding, player, now)
    local slack = 0
    if origin == nil then
        origin = shell
        slack = hits.slack(message.uid, Executor.lastReportAtMs[message.uid], now)
    end
    local dx, dy, dz = origin:getX() - victim:getX(), origin:getY() - victim:getY(), origin:getZ() - victim:getZ()
    local planar = dx * dx + dy * dy
    if planar > (reach + 0.5 + slack) ^ 2 or math.abs(dz) > (ranged and 3 or 0.5) then
        return reject("victim_out_of_range")
    end
    local slackUsed = planar > (reach + 0.5) ^ 2
    local line = ProjectALife.LineOfFire
    if line == nil or type(line.hasClearBoundary) ~= "function" then return reject("blocked") end
    local mode
    if not ranged then mode = "melee" end
    local checked, clear = pcall(line.hasClearBoundary, origin, victim, mode)
    if not checked or clear ~= true then return reject("blocked") end
    if not ranged then
        local vehicles = ProjectALife.VehicleRules
        if vehicles == nil or type(vehicles.meleeBlocked) ~= "function" then
            return reject("vehicle_rules_unavailable")
        end
        local checkedVehicle, blocked = pcall(vehicles.meleeBlocked, victim)
        if not checkedVehicle or blocked ~= false then return reject("vehicle") end
    end
    if attemptOnly == true then
        if type(relations.noteAggression) ~= "function" then return reject("relations_unavailable") end
        return relations.noteAggression(record, victim, now)
    end
    local key = "player:" .. tostring(message.online)
    local maximumVictims = ranged and ProjectALife.Weapons.firesPellets(weapon) and 8 or 1
    if last.hunt == true or last.victims[key] or last.count >= maximumVictims then return reject("duplicate_attack") end
    last.victims[key], last.count = true, last.count + 1
    local applied = false
    if type(Executor.adapters.playerHit) == "function" then
        applied = Executor.adapters.playerHit(victim, record, message.weapon) == true
    else

        local combat, part = ProjectALife.Combat, -1
        if combat ~= nil and type(combat.hitPartIndex) == "function" then
            part = combat.hitPartIndex(math.sqrt(dx * dx + dy * dy))
        end
        applied = Executor.woundPlayer(victim, message.weapon, weapon, part, shell)
    end
    if not applied then return reject("not_applied") end
    if type(relations.noteAggression) == "function" then relations.noteAggression(record, victim, now) end
    Executor.metrics.playerHitsApplied = Executor.metrics.playerHitsApplied + 1
    if hostileWhy == "ordered_hostile" then
        hits.metrics.acceptedOrdered = hits.metrics.acceptedOrdered + 1
        if hits.metrics.acceptedOrdered <= 12 then
            print("[ALIFE-HIT] reason=ordered_hostile uid=" .. tostring(message.uid) .. " victim=" .. tostring(message.online))
        end
    end
    if graced then hits.metrics.graceAccepted = hits.metrics.graceAccepted + 1 end
    if slackUsed then hits.metrics.slackAccepted = hits.metrics.slackAccepted + 1 end
    return true
end

function Executor.playerByOnlineId(online)
    online = tonumber(online)
    if online == nil then return nil end
    local found
    if type(getPlayerByOnlineID) == "function" then
        local ok, player = pcall(getPlayerByOnlineID, online)
        if ok and player ~= nil then found = player end
    end
    if found ~= nil then return found end
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return nil end
    for _, player in ipairs(locator.list()) do
        if type(player) == "userdata" or type(player) == "table" then
            local ok, id = pcall(function() return player:getOnlineID() end)
            if ok and tonumber(id) == online then return player end
        end
    end
    return nil
end

function Executor.bodyPartsHealth(bodyDamage)
    if bodyDamage == nil or bodyDamage.getBodyParts == nil then return nil end
    local parts = bodyDamage:getBodyParts()
    if parts == nil or parts.size == nil or parts.get == nil then return nil end
    local total = 0
    for index = 0, parts:size() - 1 do
        local bodyPart = parts:get(index)
        if bodyPart ~= nil and bodyPart.getHealth ~= nil then total = total + (tonumber(bodyPart:getHealth()) or 0) end
    end
    return total
end

function Executor.woundPlayer(victim, weaponType, issuedWeapon, part, attacker)
    if victim == nil then return false end
    local bodyOk, bodyDamage = pcall(function() return victim:getBodyDamage() end)
    if not bodyOk or bodyDamage == nil then return false end

    local weapon = issuedWeapon
    if weapon == nil and type(weaponType) == "string" and weaponType ~= ""
            and type(instanceItem) == "function" then
        pcall(function() weapon = instanceItem(weaponType) end)
    end
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.playerWoundWeapon) == "function" then
        weapon = combat.playerWoundWeapon(attacker, weapon)
    end

    local _, before = pcall(Executor.bodyPartsHealth, bodyDamage)
    local called = false
    if weapon ~= nil and type(bodyDamage.DamageFromWeapon) == "function" then
        called = ProjectALife.Wounds.damagePlayer(bodyDamage, weapon, tonumber(part) or -1) == true
    end
    local _, after = pcall(Executor.bodyPartsHealth, bodyDamage)
    before, after = tonumber(before), tonumber(after)
    local damaged = called and before ~= nil and after ~= nil and after < before

    if not called and type(bodyDamage.AddDamage) == "function" then
        local power = 6
        if weapon ~= nil then
            pcall(function()
                local value = tonumber(weapon:getMaxDamage())
                if value ~= nil then power = value * 8 end
            end)
        end
        damaged = pcall(function() bodyDamage:AddDamage(BodyPartType.Torso_Upper, power) end)
        Executor.metrics.playerHitsFallback = (Executor.metrics.playerHitsFallback or 0) + 1
    elseif called and not damaged then

        Executor.metrics.playerHitsAbsorbed = (Executor.metrics.playerHitsAbsorbed or 0) + 1
        damaged = true
    end
    if not damaged then return false end

    if type(sendDamage) == "function" then pcall(sendDamage, victim) end

    pcall(function()
        local cry = victim:isFemale() == true and "VoiceFemalePainFromHitBlunt"
            or "VoiceMalePainFromHitBlunt"
        if type(sendPlaySound) == "function" then
            sendPlaySound(cry, false, victim)
        else
            victim:playSound(cry)
        end
    end)
    return true
end

function Executor.sendPose(shell, pose)
    local uid = Executor.byShell[shell]
    local entry = uid and Executor.executed[uid]
    if entry == nil or not Executor.authorityFor(shell) or type(pose) ~= "table"
            or entry.lastPoseEvent == pose.animationSerial then return false end
    if type(sendClientCommand) ~= "function" then return false end
    local ok = pcall(sendClientCommand, "ProjectALife", "executorPose", {
        uid = uid, generation = entry.generation, pose = pose })
    if ok then entry.lastPoseEvent = pose.animationSerial end
    return ok
end

function Executor.applyPose(player, message)
    if not Executor.serverDelegates() or type(message) ~= "table"
            or type(message.uid) ~= "string" or #message.uid > 128
            or not finite(message.generation) then return false end
    local watchdog, registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local binding = watchdog and watchdog.bindings[message.uid]
    local actor = registry and (registry.peek or registry.read)(message.uid)
    if binding == nil or binding.generation ~= message.generation or actor == nil
            or actor.lifecycle ~= "active" or actor.generation ~= message.generation
            or not Executor.bindingMatches(binding, message.uid)
            or not ownerMatches(binding.shell, player) or binding.shell:isDead() then return false end
    local now = nowMs()
    if binding.poseOwner == player and now - (binding.poseAtMs or -math.huge) < 40 then return false end
    if not Executor.receivePose(binding, player, message.pose) then return false end
    binding.poseAtMs = now
    return true
end

function Executor.onClientCommand(module, command, player, message)
    if module ~= "ProjectALife" then return end
    if command == "executorMirrorRequest" then
        if Executor.serverDelegates() then ProjectALife.MirrorTransport.request(player) end
    elseif command == "executorNPCHit" then
        ProjectALife.NPCHitRelay.apply(player, message)
    elseif command == "executorNPCAction" then
        ProjectALife.NPCHitRelay.action(player, message)
    elseif command == "executorHuntShot" then
        local service = ProjectALife.ActivityService
        if service ~= nil and type(service.huntingShot) == "function" then service.huntingShot(player, message) end
    elseif command == "executorReport" then
        Executor.applyReport(player, message)
    elseif command == "executorPose" then
        Executor.applyPose(player, message)
    elseif command == "executorDied" then
        Executor.applyDeath(player, message)
    elseif command == "executorReleased" then
        Executor.applyReleased(player, message)
    elseif command == "executorReplicaMissing" then
        Executor.applyReplicaMissing(player, message)
    elseif command == "executorSupport" then
        Executor.applySupport(player, message)
    elseif command == "executorPlayerHit" then
        local hitOk, hitWhy = Executor.applyPlayerHit(player, message)
        local plus = ProjectALife.BlackBoxPlus
        if hitOk ~= true and plus ~= nil then pcall(plus.hitRejected, player, message, hitWhy) end
    elseif command == "executorBite" then
        Executor.applyBite(player, message)

    elseif command == "executorCampfire" then
        local campfires = ProjectALife.Campfires
        if type(message) == "table" and message.op == "shelter" then
            Executor.applyShelter(player, message)
        elseif campfires ~= nil and type(campfires.onCommand) == "function" then
            pcall(campfires.onCommand, player, message)
        end
    elseif command == "executorLoot" then
        Executor.applyLoot(player, message)
    elseif command == "executorNoise" then
        Executor.applyNoise(player, message)
    elseif command == "executorShotFx" then
        Executor.applyShotFx(player, message)
    elseif command == "executorTell" then
        Executor.applyTell(player, message)
    end
end

Executor.tellEvents = { WARN_BEFORE_ATTACK = true, ANNOUNCE_ENTRY = true, STANDOFF_SURPRISE = true,
    STANDOFF_CALLOUT = true, ENC_SEARCH_START = true, ENC_SEARCH_POST = true, ENC_ROOM_CLEAR = true,
    ENC_SEARCH_DONE = true, ENC_GIVE_UP = true, ENC_BASE_CALLOUT = true }
Executor.standoffEvents = { STANDOFF_SURPRISE = true, STANDOFF_CALLOUT = true }
function Executor.relayTell(actor, player, event, point)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or not finite(actor.generation)
            or player == nil or type(player.getOnlineID) ~= "function" or not Executor.tellEvents[event] then
        return false
    end
    local online = tonumber(player:getOnlineID())
    if not finite(online) or online < 0 then return false end
    local message = { uid = actor.uid, generation = actor.generation, online = online, event = event }
    if type(point) == "table" and finite(point.x) and finite(point.y) then
        message.x, message.y, message.z = point.x, point.y, tonumber(point.z) or 0
    end
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorTell", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorTell", message)
    else
        return false
    end
    return true
end

function Executor.applyTell(player, message)
    if not Executor.serverDelegates() or type(message) ~= "table" or type(message.uid) ~= "string"
            or #message.uid > 128 or not finite(message.generation) or not finite(message.online)
            or not Executor.tellEvents[message.event] then
        return false
    end
    local watchdog, registry = ProjectALife.Watchdog, ProjectALife.ActorRegistry
    local binding = watchdog and watchdog.bindings[message.uid]
    local record = registry and registry.peek(message.uid)
    if binding == nil or record == nil or record.lifecycle ~= "active"
            or binding.generation ~= message.generation or record.generation ~= message.generation
            or not Executor.bindingMatches(binding, message.uid)
            or not ownerMatches(binding.shell, player) then
        return false
    end
    local now = nowMs()
    if now - (binding.tellAtMs or -1e12) < 1000 then return false end
    binding.tellAtMs = now
    local target = Executor.playerByOnlineId(message.online)
    local standoff = ProjectALife.Standoff
    if target ~= nil and Executor.standoffEvents[message.event] and standoff ~= nil and type(standoff.onRelay) == "function" then
        return standoff.onRelay(record, binding.shell, target, message.event, message) == true
    end
    local fair = ProjectALife.Fairness
    if target == nil or fair == nil or type(fair.bark) ~= "function" then return false end
    return fair.bark(record, binding.shell, target, message.event) ~= nil
end

function Executor.applyShelter(player, message)
    if not Executor.serverDelegates() or type(message) ~= "table"
        or type(message.uid) ~= "string" or not finite(message.generation) then return false end
    local watchdog, registry, camps = ProjectALife.Watchdog, ProjectALife.ActorRegistry, ProjectALife.Campfires
    local binding = watchdog and watchdog.bindings[message.uid]
    local record = registry and registry.peek(message.uid)
    if not binding or not record or record.lifecycle ~= "active"
        or binding.generation ~= message.generation or record.generation ~= message.generation
        or not Executor.bindingMatches(binding, message.uid)
        or not ownerMatches(binding.shell, player) or not camps or not camps.applyShelter then return false end
    local now = nowMs()
    if message.kind ~= "board" and message.kind ~= "sheets" and message.kind ~= "leave" then return false end
    binding.shelterAtMs = binding.shelterAtMs or {}
    if now - (binding.shelterAtMs[message.kind] or -1e12) < 1000 then return false end
    binding.shelterAtMs[message.kind] = now
    return camps.applyShelter(binding.shell, message)
end

function Executor.applyLoot(player, message)
    if not Executor.serverDelegates() or type(message) ~= "table"
            or type(message.uid) ~= "string" or not finite(message.generation)
            or not finite(message.request) or not finite(message.item)
            or not finite(message.x) or not finite(message.y) or not finite(message.z)
            or (message.vehicle ~= nil and (not finite(message.vehicle)
                or type(message.part) ~= "string" or #message.part > 64)) then return false end
    local binding = ProjectALife.Watchdog.bindings[message.uid]
    local record = ProjectALife.ActorRegistry.read(message.uid)
    local valid = binding ~= nil and binding.generation == message.generation
        and record ~= nil and record.generation == message.generation
        and Executor.bindingMatches(binding, message.uid)
        and record.lifecycle == "active" and ownerMatches(binding.shell, player)
    local collected = false
    if valid then
        local shell = binding.shell
        local now = nowMs()
        if now - (binding.lootAtMs or -1e12) >= 1000 then
            binding.lootAtMs, binding.lootCount = now, 0
        end
        binding.lootCount = (binding.lootCount or 0) + 1
        local ok, result = pcall(function()
            if binding.lootCount > 8 or shell:isDead() or math.abs(shell:getZ() - message.z) >= 0.6
                    or (shell:getX() - message.x)^2 + (shell:getY() - message.y)^2 > 9 then return false end
            require "ProjectALife/Loot/ALifeLootTransfer"
            return ProjectALife.LootTransfer.collect(shell, message)
        end)
        collected = ok and result == true
    end
    if type(sendServerCommand) == "function" then
        sendServerCommand(player, "ProjectALife", "executorLootResult", {
            request = message.request, uid = message.uid, generation = message.generation, ok = collected })
    end
    return collected
end

Executor.noiseSettings = { maxRadius = 200, maxVolume = 200, perShellMs = 250 }
Executor.noiseAtMs = setmetatable({}, { __mode = "k" })
function Executor.applyNoise(player, message)
    if type(message) ~= "table" then return false, "invalid" end
    local x, y, z = tonumber(message.x), tonumber(message.y), tonumber(message.z) or 0
    local radius, volume = tonumber(message.radius), tonumber(message.volume)
    if x == nil or y == nil or radius == nil or volume == nil then return false, "invalid" end

    if player == nil or not Executor.playerNear(player, x, y, Executor.authority.noiseReporterRadius) then
        Executor.metrics.noiseRejected = (Executor.metrics.noiseRejected or 0) + 1
        return false, "noise_far_from_sender"
    end
    local key = "?"
    pcall(function() key = tostring(player:getUsername() or player:getOnlineID()) end)
    local now, last = nowMs(), Executor.noiseByPlayerAtMs[key]
    if last ~= nil and now - last < Executor.authority.noisePerPlayerMs then
        Executor.metrics.noiseRejected = (Executor.metrics.noiseRejected or 0) + 1
        return false, "noise_rate_limited"
    end
    Executor.noiseByPlayerAtMs[key] = now
    radius = math.max(0, math.min(Executor.noiseSettings.maxRadius, math.floor(radius)))
    volume = math.max(0, math.min(Executor.noiseSettings.maxVolume, math.floor(volume)))
    if type(addSound) ~= "function" then return false, "no_addSound" end
    pcall(addSound, nil, math.floor(x), math.floor(y), math.floor(z), radius, volume)
    Executor.metrics.noiseApplied = (Executor.metrics.noiseApplied or 0) + 1
    return true, "applied"
end

function Executor.relayCampfire(message)
    if type(message) ~= "table" then return false, "invalid" end
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorCampfire", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorCampfire", message)
    else
        return false, "relay_unavailable"
    end
    Executor.metrics.campfiresRelayed = (Executor.metrics.campfiresRelayed or 0) + 1
    return true, "relayed"
end

function Executor.relayNoise(shell, x, y, z, radius, volume)
    local now = nowMs()

    local last = shell ~= nil and Executor.noiseAtMs[shell] or nil
    if last ~= nil and now - last < Executor.noiseSettings.perShellMs then
        return false, "rate_limited"
    end
    if shell ~= nil then Executor.noiseAtMs[shell] = now end
    local message = { x = math.floor(tonumber(x) or 0), y = math.floor(tonumber(y) or 0),
        z = math.floor(tonumber(z) or 0), radius = math.floor(tonumber(radius) or 0),
        volume = math.floor(tonumber(volume) or 0) }
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorNoise", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorNoise", message)
    else
        return false, "relay_unavailable"
    end
    Executor.metrics.noiseRelayed = (Executor.metrics.noiseRelayed or 0) + 1
    return true, "relayed"
end

Executor.shotFxSettings = { range = 90, perShellMs = 60, perPlayerMs = 25, maxText = 64 }
Executor.shotFxAtMs = setmetatable({}, { __mode = "k" })
Executor.shotFxByPlayerAtMs = {}

function Executor.shotFxRange()
    local range = Executor.shotFxSettings.range
    pcall(function()
        local value = tonumber(SandboxVars.ALife.Combat_ShotFxRange)
        if value ~= nil then range = value end
    end)
    return math.max(10, math.min(150, range))
end

function Executor.shotFxPayload(event)
    if type(event) ~= "table" then return nil end
    local x, y, ax, ay = tonumber(event.x), tonumber(event.y), tonumber(event.ax), tonumber(event.ay)
    if not (finite(x) and finite(y) and finite(ax) and finite(ay)) then return nil end
    local limit = Executor.shotFxSettings.maxText
    local function text(value, uid)
        local pattern = "[^%w_%.%-]"
        if uid == true then pattern = "[^%w_%.%-%:]" end
        if type(value) == "string" and value ~= "" and #value <= limit
                and not string.find(value, pattern) then
            return value
        end
        return nil
    end
    local function span(value, low, high, fallback)
        value = tonumber(value)
        if not finite(value) then value = fallback end
        return math.max(low, math.min(high, value))
    end
    return {
        x = x, y = y, z = math.floor(span(event.z, -8, 32, 0)), ax = ax, ay = ay,
        pel = math.floor(span(event.pel, 1, 12, 1)), fl = math.floor(span(event.fl, 0, 30, 10)),
        lr = math.floor(span(event.lr, 0, 10, 4)), mz = math.floor(span(event.mz, 20, 150, 60)),
        gn = span(event.gn, 0.2, 6, 1), sp = event.sp == 1 and 1 or 0,
        sw = text(event.sw), br = text(event.br),
        weapon = text(event.weapon), owner = text(event.owner, true),
    }
end

function Executor.relayShotFx(shell, event)
    local now = nowMs()
    local last = shell ~= nil and Executor.shotFxAtMs[shell] or nil
    if last ~= nil and now - last < Executor.shotFxSettings.perShellMs then
        return false, "rate_limited"
    end
    local message = Executor.shotFxPayload(event)
    if message == nil then return false, "invalid" end
    if shell ~= nil then Executor.shotFxAtMs[shell] = now end
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorShotFx", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorShotFx", message)
    else
        return false, "relay_unavailable"
    end
    Executor.metrics.shotFxRelayed = (Executor.metrics.shotFxRelayed or 0) + 1
    return true, "relayed"
end

function Executor.broadcastShotFx(message, except)
    if type(sendServerCommand) ~= "function" or type(getOnlinePlayers) ~= "function" then return 0 end
    local players = getOnlinePlayers()
    if players == nil then return 0 end
    local range, sent = Executor.shotFxRange(), 0
    for index = 0, players:size() - 1 do
        local other = players:get(index)
        if other ~= nil and other ~= except and Executor.playerNear(other, message.x, message.y, range) then
            if pcall(sendServerCommand, other, "ProjectALife", "shotFx", message) then sent = sent + 1 end
        end
    end
    Executor.metrics.shotFxSent = (Executor.metrics.shotFxSent or 0) + sent
    return sent
end

function Executor.applyShotFx(player, message)
    if not Executor.serverDelegates() then return false, "not_server" end
    local payload = Executor.shotFxPayload(message)
    if payload == nil then return false, "invalid" end
    if player == nil or not Executor.playerNear(player, payload.x, payload.y, Executor.authority.noiseReporterRadius) then
        Executor.metrics.shotFxRejected = (Executor.metrics.shotFxRejected or 0) + 1
        return false, "far_from_sender"
    end
    local key = "?"
    pcall(function() key = tostring(player:getUsername() or player:getOnlineID()) end)
    local now, last = nowMs(), Executor.shotFxByPlayerAtMs[key]
    if last ~= nil and now - last < Executor.shotFxSettings.perPlayerMs then
        Executor.metrics.shotFxRejected = (Executor.metrics.shotFxRejected or 0) + 1
        return false, "rate_limited"
    end
    Executor.shotFxByPlayerAtMs[key] = now
    Executor.broadcastShotFx(payload, player)
    return true, "applied"
end

function Executor.relaySupport(actor, contact)
    if type(actor) ~= "table" or type(actor.uid) ~= "string" or type(contact) ~= "table" then
        return false, "support_relay_invalid"
    end
    local message = { uid = actor.uid, generation = actor.generation,
        contact = { x = tonumber(contact.x), y = tonumber(contact.y), z = tonumber(contact.z) or 0,
            playerKey = type(contact.playerKey) == "string" and contact.playerKey or nil,
            targetUid = type(contact.targetUid) == "string" and contact.targetUid or nil } }
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorSupport", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorSupport", message)
    else
        return false, "support_relay_unavailable"
    end
    Executor.metrics.supportRelayed = Executor.metrics.supportRelayed + 1
    return true, "relayed"
end

function Executor.directiveChanged(own, theirs)
    local a, b = own.stanceAnchor or {}, theirs.stanceAnchor or {}
    if own.stance ~= theirs.stance or a.x ~= b.x or a.y ~= b.y or a.z ~= b.z then return true end
    local old, fresh = own.offlineTask or {}, theirs.offlineTask or {}
    return old.kind ~= fresh.kind or old.dest ~= fresh.dest or old.untilHours ~= fresh.untilHours
end

function Executor.conversationChanged(own, theirs, now)
    now = now or nowMs()
    local oldRobbery, newRobbery = own.robbery or {}, theirs.robbery or {}
    if oldRobbery.id ~= newRobbery.id or oldRobbery.phase ~= newRobbery.phase then return true end
    local a = (tonumber(own.talkHoldUntilMs) or 0) > now or (tonumber(own.gossipHoldUntilMs) or 0) > now
    local b = (tonumber(theirs.talkHoldUntilMs) or 0) > now or (tonumber(theirs.gossipHoldUntilMs) or 0) > now
    return a ~= b or own.gossipToken ~= theirs.gossipToken or own.talkHoldPlayerKey ~= theirs.talkHoldPlayerKey
end

function Executor.applyMirror(data)
    if type(data) ~= "table" or type(data.records) ~= "table" then return false end
    local Registry = ProjectALife.ActorRegistry
    if Registry == nil then return false end
    if type(data.died) == "table" then Executor.noteDiedFrame(data.died) end
    local seen, applied, doomed = {}, 0, nil
    for uid, record in pairs(data.records) do
        if type(record) == "table" and type(record.uid) == "string" then
            seen[uid] = true
            local mine = Executor.executed[uid]
            local local_ = Registry.records[uid]
            if mine ~= nil and mine.generation ~= record.generation then
                Executor.release(uid, "generation_changed")
                mine = nil
            end
            if mine ~= nil and local_ ~= nil then
                mine.mirrorMisses = 0
                if data.changed == nil or data.changed[uid] ~= nil then
                    local own = type(local_.memory) == "table" and local_.memory or {}
                    local theirs = type(record.memory) == "table" and record.memory or {}
                    local directiveChanged = Executor.directiveChanged(own, theirs)
                    local conversationChanged = Executor.conversationChanged(own, theirs)
                    local stock = theirs.traderStock
                    local previousStock = own.traderStock
                    local stockChanged = type(stock) == "table" and stock.phase == "ready"
                        and (type(previousStock) ~= "table" or previousStock.revision ~= stock.revision
                            or previousStock.phase ~= stock.phase or previousStock.uid ~= stock.uid)
                    for key in pairs(PROTECTED) do own[key] = copy(theirs[key]) end
                    if theirs.hostileOverride == true then own.hostileOverride = true end
                    own.hostileToActorKeys = Executor.mergeGrudges(own.hostileToActorKeys, theirs.hostileToActorKeys)
                    own.hostileToPlayerKeys = Executor.mergeGrudges(own.hostileToPlayerKeys, theirs.hostileToPlayerKeys)
                    if ProjectALife.CalmDown ~= nil then ProjectALife.CalmDown.release(own, theirs) end
                    if (tonumber(theirs.carefulTurnedAtMs) or 0) > (tonumber(own.carefulTurnedAtMs) or 0) then
                        own.carefulTurnedAtMs = theirs.carefulTurnedAtMs
                    end
                    if directiveChanged then
                        own.stancePost, own.stancePhase, own.stancePostUntilMs = nil, nil, nil
                    end
                    local_.memory = own
                    if stockChanged and type(isClient) == "function" and isClient() then
                        local sim, relay = ProjectALife.ShellSimulation, ProjectALife.NPCHitRelay
                        if sim ~= nil and type(sim.isOwner) == "function" and sim.isOwner(mine.shell)
                                and relay ~= nil and type(relay.requestEquipment) == "function" then
                            pcall(relay.requestEquipment, mine.shell)
                        end
                    end
                    if (directiveChanged or conversationChanged) and ProjectALife.DecisionLoop and ProjectALife.DecisionLoop.refreshDirective then
                        ProjectALife.DecisionLoop.refreshDirective(uid)
                    end
                end
            elseif local_ == nil or data.changed == nil or data.changed[uid] ~= nil then
                local fresh = copy(record)
                if Registry.records[uid] == nil then Registry.order[#Registry.order + 1] = uid end
                Registry.records[uid] = fresh
                applied = applied + 1
            end
        end
    end

    for index = #Registry.order, 1, -1 do
        local uid = Registry.order[index]
        if not seen[uid] then
            local entry = Executor.executed[uid]
            if data.present ~= nil and entry ~= nil and data.present[uid] == entry.generation then

                entry.mirrorMisses = 0
            elseif entry == nil then
                Registry.records[uid] = nil
                table.remove(Registry.order, index)
            elseif Executor.diedMatches(uid, entry.generation) then

                doomed = doomed or {}
                doomed[#doomed + 1] = uid
            else

                entry.mirrorMisses = (entry.mirrorMisses or 0) + 1
                if entry.mirrorMisses >= Executor.settings.mirrorMissLimit then
                    local shell = entry.shell
                    Executor.release(uid, "record_gone")
                    Registry.records[uid] = nil
                    table.remove(Registry.order, index)
                    scrubBody(shell, "record_gone")
                    pcall(function() shell:removeFromWorld() end)
                    pcall(function() shell:removeFromSquare() end)
                end
            end
        end
    end

    for _, uid in ipairs(doomed or {}) do
        local entry = Executor.executed[uid]
        if entry ~= nil then
            local killed = Executor.killLocal(entry.shell, uid, "died_on_server")

            if Executor.executed[uid] == entry then
                local shell = entry.shell
                if killed or (shell ~= nil and shell.isDead ~= nil and shell:isDead() == true) then
                    Executor.reportDeath(shell)
                else
                    Executor.release(uid, "died_on_server")
                end
            end
        end
    end
    Executor.mirror.receivedAtMs = nowMs()
    Executor.mirror.present = data.present

    Executor.mirror.sequence = Executor.mirror.sequence + 1
    Executor.mirror.count = data.count or applied
    Executor.metrics.mirrorApplies = Executor.metrics.mirrorApplies + 1
    return true, applied
end

function Executor.onReceiveGlobalModData(key, data)
    if key ~= Executor.MIRROR_TAG then return end
    if not Executor.executorSide() then return end
    if ProjectALife.MirrorTransport.client.stream ~= nil then return end
    local ok, err = pcall(Executor.applyMirror, data)
    if not ok then fault("mirror", err) end
end

local function watchdogAdapters()
    return {
        nowMs = nowMs,
        emit = function() end,
        getActor = function(uid) return ProjectALife.ActorRegistry.read(uid) end,
        shellAlive = function(shell)
            if shell == nil then return false end
            local ok, dead = pcall(function() return shell:isDead() end)
            if not ok or dead == true then return false end
            local squareOk, square = pcall(function() return shell:getCurrentSquare() end)
            return squareOk and square ~= nil
        end,
        shellIdentity = identityOf,
        recoverShell = function() return false end,
        detachShell = function() return true end,
        onShellLost = function() return true end,
    }
end

function Executor.start(options)
    if Executor.started then return true, "already_started" end
    if not Executor.executorSide() then return false, "executor_side_required" end
    if not Executor.enabled then return false, "executor_disabled" end
    options = options or {}
    local Registry = ProjectALife.ActorRegistry
    local Watchdog = ProjectALife.Watchdog
    local Decisions = ProjectALife.DecisionLoop
    local Animations = ProjectALife.Animations
    if Registry == nil or Watchdog == nil or Decisions == nil then return false, "runtime_modules_missing" end
    Registry.reset()
    Registry.configure({ nowMs = nowMs, emit = function() end })
    Watchdog.reset()
    local ok, err = Watchdog.configure(watchdogAdapters())
    if not ok then return false, err end
    if Animations ~= nil and type(Animations.configure) == "function" then
        Animations.configure({ nowMs = nowMs })
    end
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and type(catalog.load) == "function" and catalog.current == nil then
        pcall(catalog.load)
    end
    Decisions.reset()
    Decisions.configure(options.decisionAdapters)
    Executor.executed, Executor.order = {}, {}
    Executor.byShell = setmetatable({}, { __mode = "k" })
    Executor.strays = setmetatable({}, { __mode = "k" })
    Executor.serverDied, Executor.serverDiedByOnline, Executor.releasedIds = {}, {}, {}
    Executor.deadBodies, Executor.deadCount, Executor.watchCount = {}, 0, 0
    Executor.readoptAfterMs = {}
    Executor.handoffKept = {}
    Executor.started = true
    Executor.lastTickAtMs = 0
    Executor.releaseLines, Executor.lifecycleLines = 0, 0
    ProjectALife.MirrorTransport.reset()
    ProjectALife.MirrorTransport.requestFull()
    return true
end

function Executor.stop()
    for uid in pairs(Executor.executed) do Executor.release(uid, "stop") end
    Executor.started = false
    return true
end

local function hydrateBody(entry, record, now)
    if entry == nil then return false end
    if entry.nextHydrateAtMs ~= nil and now < entry.nextHydrateAtMs then return false end
    entry.nextHydrateAtMs = now + Executor.settings.hydrateRetryMs
    if type(Executor.adapters.hydrate) == "function" then
        local ok = Executor.adapters.hydrate(entry.shell, record) == true
        if ok then
            entry.hydrated = true

            entry.freshHealth = true
            Executor.metrics.hydrated = Executor.metrics.hydrated + 1
            Interop.spawned(entry.shell, record.uid, record.generation)
            ProjectALife.NPCHitRelay.requestEquipment(entry.shell)
        else
            Executor.metrics.hydrateFailures = Executor.metrics.hydrateFailures + 1
        end
        return ok
    end
    local adapter = ProjectALife.ShellAdapter
    if adapter == nil or type(adapter.hydrateShell) ~= "function" then return false end
    local ok, result = pcall(adapter.hydrateShell, entry.shell, record)
    if ok and result == true then
        entry.hydrated = true
        entry.freshHealth = true
        Executor.metrics.hydrated = Executor.metrics.hydrated + 1
        pcall(function() entry.shell:getModData().ProjectALifeExecutorHydrated = true end)

        Interop.spawned(entry.shell, record.uid, record.generation)
        ProjectALife.NPCHitRelay.requestEquipment(entry.shell)
        return true
    end
    Executor.metrics.hydrateFailures = Executor.metrics.hydrateFailures + 1
    local reason = ok and "profile_apply_failed" or tostring(result)
    pcall(function()
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator ~= nil and type(hydrator.plan) == "function" then
            local plan, planError = hydrator.plan(record)
            if plan == nil then reason = tostring(planError) end
        end
    end)
    Executor.metrics.lastHydrateError = reason

    return false
end

local function adoptInternal(shell, uid, generation)
    if not Executor.started or shell == nil then return false, "not_started" end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and sim.grappledCorpse(shell) then return false, "grappled_corpse" end
    local previousUid = Executor.byShell[shell]
    if previousUid ~= nil then
        if Executor.entryMatches(shell, previousUid, Executor.executed[previousUid]) then return true, "already" end
        Executor.release(previousUid, "identity_changed")
    end
    if type(uid) ~= "string" then uid, generation = identityOf(shell) end
    if type(uid) ~= "string" then return false, "no_identity" end
    local record = ProjectALife.ActorRegistry.read(uid)
    if record == nil then return false, "no_record" end
    if record.lifecycle ~= "active" then return false, "not_active" end

    local aliveOk, dead = pcall(function() return shell:isDead() end)
    if aliveOk and dead == true then return false, "shell_dead" end
    if generation ~= nil and record.generation ~= generation then return false, "generation_mismatch" end
    if not isOwner(shell) then return false, "not_owner" end
    local existing = Executor.executed[uid]
    if existing ~= nil and existing.shell ~= shell then Executor.release(uid, "replaced") end
    local bound, bindError = ProjectALife.Watchdog.bind(uid, record.generation, shell)
    if not bound then return false, bindError end
    Executor.executed[uid] = { shell = shell, generation = record.generation, adoptedAtMs = nowMs(),
        lastReportAtMs = 0, lastRevision = -1, lastX = nil, lastY = nil, onlineId = Executor.onlineIdOf(shell) }
    Executor.byShell[shell] = uid
    Executor.order[#Executor.order + 1] = uid
    Executor.restoreHandoff(uid, record.generation, nowMs())

    ProjectALife.DecisionLoop.lastSyncAtMs = -math.huge
    Executor.metrics.adopted = Executor.metrics.adopted + 1
    hydrateBody(Executor.executed[uid], record, nowMs())
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.track) == "function" then guard.track(shell) end
    end)
    return true
end

function Executor.adopt(shell, uid, generation)
    local ok, reason = adoptInternal(shell, uid, generation)
    if ok ~= true and type(reason) == "string" then

        local strays = Executor.strays
        local entry = strays ~= nil and strays[shell] or nil
        if entry == nil or entry.refused ~= reason then
            Executor.metrics.adoptRefusals[reason] = (Executor.metrics.adoptRefusals[reason] or 0) + 1
        end
        if entry ~= nil then entry.refused = reason end
    end
    return ok, reason
end

function Executor.release(uid, reason)
    local entry = Executor.executed[uid]
    if entry == nil then return false end
    local why = reason or "executor_release"
    Executor.noteRelease(uid, entry, why)
    Executor.metrics.releaseReasons[why] = (Executor.metrics.releaseReasons[why] or 0) + 1
    Executor.executed[uid] = nil
    if entry.shell ~= nil then Executor.byShell[entry.shell] = nil end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil then traversal.forget(entry.shell, "executor:" .. tostring(why)) end
    for index = #Executor.order, 1, -1 do
        if Executor.order[index] == uid then table.remove(Executor.order, index) end
    end
    if why == "ownership_lost" then Executor.keepForHandoff(uid, entry, nowMs()) end
    pcall(function() ProjectALife.DecisionLoop.forget(uid, entry.generation, reason or "executor_release") end)
    pcall(function() ProjectALife.Watchdog.unbind(uid, entry.generation, reason or "executor_release") end)
    Executor.metrics.released = Executor.metrics.released + 1
    ProjectALife.NPCHitRelay.pending[entry.shell] = nil
    ProjectALife.NPCHitRelay.selected[entry.shell] = nil
    Executor.rememberRelease(uid, entry, why)
    return true
end

function Executor.noteRelease(uid, entry, why)
    if (Executor.releaseLines or 0) >= 200 then return end
    Executor.releaseLines = (Executor.releaseLines or 0) + 1
    local shell = type(entry) == "table" and entry.shell or nil
    local kind = type(shell)
    local object = kind == "userdata" or kind == "table"
    local at, id, alive, marks
    if object and shell.getX ~= nil and shell.getY ~= nil then
        local x, y = tonumber(shell:getX()), tonumber(shell:getY())
        if x ~= nil and y ~= nil then at = math.floor(x) .. "," .. math.floor(y) end
    end
    if object and shell.getOnlineID ~= nil then id = shell:getOnlineID() end
    if object and shell.isDead ~= nil then alive = shell:isDead() ~= true end
    if object then marks = Executor.marksOf(shell) end
    print("[ALIFE-LIFECYCLE] client_release uid=" .. tostring(uid) .. " generation="
        .. tostring(type(entry) == "table" and entry.generation or nil) .. " reason=" .. why
        .. " onlineId=" .. tostring(id) .. " at=" .. tostring(at)
        .. " alive=" .. tostring(alive) .. " listed=" .. tostring(object and Executor.listed(shell) or nil)
        .. " marks=" .. tostring(marks)
        .. " recordDead=" .. tostring(Executor.recordDead(uid, type(entry) == "table" and entry.generation or nil)))
end

function Executor.marksOf(shell)
    local owned = false
    if shell.getModData ~= nil and (shell.hasModData == nil or shell:hasModData() == true) then
        local data = shell:getModData()
        owned = type(data) == "table" and data.ProjectALifeOwned == true
    end
    local actor = shell.GetVariable ~= nil and shell:GetVariable("ALifeActor") or nil
    return tostring(owned) .. "/" .. tostring(actor)
end

function Executor.listed(shell)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or cell.getZombieList == nil then return nil end
    local zombies = cell:getZombieList()
    if zombies == nil or zombies.contains == nil then return nil end
    return zombies:contains(shell) == true
end

function Executor.recordDead(uid, generation)
    if Executor.diedMatches(uid, generation) then return true end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.records) == "table" and registry.records[uid] or nil
    return record ~= nil and record.lifecycle == "dead"
end

function Executor.noteDiedFrame(died)
    local now = nowMs()
    for uid, fact in pairs(died) do
        if type(uid) == "string" and type(fact) == "table" then
            Executor.noteServerDeath(uid, tonumber(fact.g), tonumber(fact.id),
                tonumber(fact.x), tonumber(fact.y), tonumber(fact.z), now)
        end
    end
end

function Executor.noteServerDeath(uid, generation, onlineId, x, y, z, now)
    if type(uid) ~= "string" then return false end
    now = tonumber(now) or nowMs()
    local known = Executor.serverDied[uid]
    if known ~= nil and known.onlineId ~= nil and Executor.serverDiedByOnline[known.onlineId] == uid then
        Executor.serverDiedByOnline[known.onlineId] = nil
    end
    if known == nil then Executor.watchCount = Executor.watchCount + 1 end
    Executor.serverDied[uid] = { generation = generation, onlineId = onlineId, x = x, y = y, z = z,
        untilMs = now + Executor.settings.serverDiedMs }
    if onlineId ~= nil and onlineId ~= -1 then Executor.serverDiedByOnline[onlineId] = uid end
    return true
end

function Executor.diedMatches(uid, generation)
    local fact = uid ~= nil and Executor.serverDied[uid] or nil
    return fact ~= nil and (fact.generation == nil or generation == nil or fact.generation == generation)
end

function Executor.killLocal(shell, uid, reason)
    if shell == nil or shell.isDead == nil then return false, "no_body" end
    if shell:isDead() == true then return false, "dead" end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.grappledCorpse) == "function" and sim.grappledCorpse(shell) then
        Executor.metrics.corpseKillsRefused = Executor.metrics.corpseKillsRefused + 1
        return false, "corpse"
    end
    if not isOwner(shell) then return false, "not_owner" end
    if shell.setHealth ~= nil then shell:setHealth(0) end
    if type(shell.Kill) ~= "function" then return false, "no_kill" end
    local ok = pcall(shell.Kill, shell, shell)
    if not ok then return false, "kill_failed" end
    Executor.metrics.killedLocally = Executor.metrics.killedLocally + 1
    if (Executor.lifecycleLines or 0) < 200 then
        Executor.lifecycleLines = (Executor.lifecycleLines or 0) + 1
        print("[ALIFE-LIFECYCLE] client_kill uid=" .. tostring(uid) .. " reason=" .. tostring(reason)
            .. " onlineId=" .. tostring(shell.getOnlineID ~= nil and shell:getOnlineID() or nil))
    end
    return true
end

function Executor.rememberRelease(uid, entry, why)
    if why == "dead" or why == "stop" or why == "retired" then return end
    local shell = entry.shell
    local now = nowMs()

    local id = Executor.onlineIdOf(shell) or entry.onlineId
    if why == "shell_gone" then
        Executor.readoptAfterMs[uid] = { untilMs = now + Executor.settings.readoptCooldownMs,
            onlineId = id, shell = shell }
        Executor.sendReleased(uid, entry.generation, why)
    end
    if id == nil then return end
    if Executor.releasedIds[id] == nil then Executor.watchCount = Executor.watchCount + 1 end
    Executor.releasedIds[id] = { uid = uid, shell = shell, why = why, untilMs = now + 30000 }
end

function Executor.onlineIdOf(shell)
    local kind = type(shell)
    if (kind ~= "userdata" and kind ~= "table") or shell.getOnlineID == nil then return nil end
    local id = tonumber(shell:getOnlineID())
    if id == nil or id == -1 then return nil end
    return id
end

function Executor.cooling(shell, uid, now)
    local cooling = Executor.readoptAfterMs[uid]
    if cooling == nil or now >= cooling.untilMs then return false end
    if cooling.onlineId == nil then return cooling.shell == shell end
    return Executor.onlineIdOf(shell) == cooling.onlineId
end

function Executor.sendReleased(uid, generation, why)
    local message = { uid = uid, generation = generation, reason = why }
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorReleased", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorReleased", message)
    end
end

function Executor.pruneWatch(now)
    if Executor.watchCount <= 0 then return end
    local dropDied, dropIds
    for uid, fact in pairs(Executor.serverDied) do
        if now >= fact.untilMs then dropDied = dropDied or {}; dropDied[#dropDied + 1] = uid end
    end
    for id, fact in pairs(Executor.releasedIds) do
        if now >= fact.untilMs then dropIds = dropIds or {}; dropIds[#dropIds + 1] = id end
    end
    for _, uid in ipairs(dropDied or {}) do
        local fact = Executor.serverDied[uid]
        if fact.onlineId ~= nil and Executor.serverDiedByOnline[fact.onlineId] == uid then
            Executor.serverDiedByOnline[fact.onlineId] = nil
        end
        Executor.serverDied[uid] = nil
        Executor.watchCount = Executor.watchCount - 1
    end
    for _, id in ipairs(dropIds or {}) do
        Executor.releasedIds[id] = nil
        Executor.watchCount = Executor.watchCount - 1
    end
end

function Executor.pruneCooldowns(now)
    local cooled
    for uid, cooling in pairs(Executor.readoptAfterMs) do
        if now >= cooling.untilMs then cooled = cooled or {}; cooled[#cooled + 1] = uid end
    end
    for _, uid in ipairs(cooled or {}) do Executor.readoptAfterMs[uid] = nil end
    local stale
    for uid, kept in pairs(Executor.handoffKept or {}) do
        if now >= kept.untilMs then stale = stale or {}; stale[#stale + 1] = uid end
    end
    for _, uid in ipairs(stale or {}) do Executor.handoffKept[uid] = nil end
end

function Executor.keepForHandoff(uid, entry, now)
    local perception = ProjectALife.Perception
    if perception == nil or type(entry) ~= "table" then return false end
    local grudge = type(perception.attackers) == "table" and perception.attackers[uid] or nil
    local engagement = type(perception.engagements) == "table" and perception.engagements[uid] or nil
    if grudge == nil and engagement == nil then return false end
    Executor.handoffKept = Executor.handoffKept or {}
    Executor.handoffKept[uid] = { generation = entry.generation, grudge = grudge, engagement = engagement,
        untilMs = now + Executor.settings.handoffKeepMs }
    return true
end

function Executor.restoreHandoff(uid, generation, now)
    local kept = Executor.handoffKept ~= nil and Executor.handoffKept[uid] or nil
    if kept == nil then return false end
    Executor.handoffKept[uid] = nil
    if kept.generation ~= generation or now >= kept.untilMs then return false end
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.attackers) ~= "table" or type(perception.engagements) ~= "table" then
        return false
    end
    local restored = false
    local grudge = kept.grudge
    if type(grudge) == "table" and perception.attackers[uid] == nil and now < (tonumber(grudge.untilMs) or 0) then
        perception.attackers[uid] = grudge
        restored = true
    end
    if kept.engagement ~= nil and perception.engagements[uid] == nil then
        perception.engagements[uid] = kept.engagement
        restored = true
    end
    if restored then Executor.metrics.grudgesKept = (Executor.metrics.grudgesKept or 0) + 1 end
    return restored
end

function Executor.noteReappeared(shell, id, fact, marked)
    Executor.metrics.reappeared = Executor.metrics.reappeared + 1
    if (Executor.lifecycleLines or 0) > 199 then return end
    Executor.lifecycleLines = (Executor.lifecycleLines or 0) + 1
    local at = nil
    if shell.getX ~= nil and shell.getY ~= nil then
        at = math.floor(tonumber(shell:getX()) or 0) .. "," .. math.floor(tonumber(shell:getY()) or 0)
    end
    print("[ALIFE-LIFECYCLE] reappeared uid=" .. tostring(fact.uid) .. " onlineId=" .. tostring(id)
        .. " sameObject=" .. tostring(fact.shell == shell) .. " was=" .. tostring(fact.why)
        .. " marks=" .. (marked and Executor.marksOf(shell) or "none") .. " at=" .. tostring(at))
end

function Executor.watchUnmarked(shell)
    if shell.getOnlineID == nil then return false end
    local id = tonumber(shell:getOnlineID())
    if id == nil or id == -1 then return false end
    local released = Executor.releasedIds[id]
    if released ~= nil then
        Executor.releasedIds[id] = nil
        Executor.watchCount = Executor.watchCount - 1
        Executor.noteReappeared(shell, id, released, false)
    end
    local uid = Executor.serverDiedByOnline[id]
    local fact = uid ~= nil and Executor.serverDied[uid] or nil
    if fact == nil or nowMs() >= fact.untilMs then return false end

    if fact.x ~= nil and fact.y ~= nil and shell.getX ~= nil and shell.getY ~= nil then
        local radius = Executor.settings.serverDiedRadius
        if math.abs((tonumber(shell:getX()) or 0) - fact.x) > radius
                or math.abs((tonumber(shell:getY()) or 0) - fact.y) > radius then return false end
    end
    return Executor.killLocal(shell, uid, "unmarked_copy")
end

function Executor.watchMarked(shell, uid, generation)
    if shell.getOnlineID ~= nil then
        local id = tonumber(shell:getOnlineID())
        local released = id ~= nil and Executor.releasedIds[id] or nil
        if released ~= nil and released.uid == uid then
            Executor.releasedIds[id] = nil
            Executor.watchCount = Executor.watchCount - 1
            Executor.noteReappeared(shell, id, released, true)
        end
    end
    if not Executor.diedMatches(uid, generation) then return false end
    if nowMs() >= Executor.serverDied[uid].untilMs then return false end
    Executor.killLocal(shell, uid, "record_dead")
    return true
end

function Executor.holdCorpse(shell, uid)
    if shell == nil or type(uid) ~= "string" then return false end
    local guard = ProjectALife.AIFence
    if guard ~= nil and type(guard.untrack) == "function" then pcall(guard.untrack, shell) end
    Executor.dropPresentation(shell)
    if Executor.deadBodies[uid] == nil then Executor.deadCount = Executor.deadCount + 1 end
    Executor.deadBodies[uid] = { uid = uid, shell = shell, atMs = nowMs() }
    return true
end

Executor.presentationCaches = { "active", "current", "fallback", "weaponVisuals", "idleProps",
    "combatHold", "readyCarry", "ownerPose", "serial", "remoteToken", "actBeat" }

function Executor.dropPresentation(shell)
    local animations = ProjectALife.Animations
    if animations == nil or shell == nil then return false end
    if type(animations.dropCaches) == "function" then return animations.dropCaches(shell) end
    if type(animations.actSet) == "table" and animations.actSet[shell] ~= nil
            and type(animations.stopAct) == "function" then
        pcall(animations.stopAct, shell)
    end
    for _, name in ipairs(Executor.presentationCaches) do
        local cache = animations[name]
        if type(cache) == "table" then cache[shell] = nil end
    end
    return true
end

function Executor.scrubCorpse(entry)
    local shell = entry.shell
    if shell == nil then return false end
    local uid = identityOf(shell)
    local corpseOf
    if shell.getModData ~= nil and (shell.hasModData == nil or shell:hasModData() == true) then
        local data = shell:getModData()
        corpseOf = type(data) == "table" and data.ProjectALifeCorpseOf or nil
    end
    Executor.metrics.corpseScrubs = Executor.metrics.corpseScrubs + 1
    if uid == entry.uid or corpseOf == entry.uid then
        scrubBody(shell, "dead")
        return true
    end
    Executor.metrics.corpseScrubsReused = Executor.metrics.corpseScrubsReused + 1
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.forget) == "function" then pcall(animations.forget, shell) end
    return true
end

function Executor.takeDeadBody(uid)
    local entry = Executor.deadBodies[uid]
    if entry == nil then return nil end
    Executor.deadBodies[uid] = nil
    Executor.deadCount = math.max(0, Executor.deadCount - 1)
    return entry
end

function Executor.onDeadBodySpawn(body)
    if Executor.deadCount <= 0 or body == nil or body.getModData == nil then return end
    if body.hasModData ~= nil and body:hasModData() ~= true then return end
    local data = body:getModData()
    if type(data) ~= "table" then return end
    local uid = data.ProjectALifeCorpseOf or data.ProjectALifeUID
    local entry = type(uid) == "string" and Executor.takeDeadBody(uid) or nil
    if entry ~= nil then Executor.scrubCorpse(entry) end
end

function Executor.sweepDeadBodies(now)
    if Executor.deadCount <= 0 then return 0 end
    local due
    for uid, entry in pairs(Executor.deadBodies) do
        local shell = entry.shell
        local gone = shell == nil or shell.getCurrentSquare == nil or shell:getCurrentSquare() == nil
        if gone or now - entry.atMs >= Executor.settings.corpseScrubCapMs then
            due = due or {}
            due[#due + 1] = uid
        end
    end
    for _, uid in ipairs(due or {}) do
        local entry = Executor.takeDeadBody(uid)
        if entry ~= nil then Executor.scrubCorpse(entry) end
    end
    return due and #due or 0
end

Executor.paintedAtMs = setmetatable({}, { __mode = "k" })

function Executor.paintSpectator(shell, record, now)
    if shell == nil or type(record) ~= "table" then return false end

    local deadOk, dead = pcall(function() return shell:isDead() end)
    if deadOk and dead == true then return false end

    local client = ProjectALife.AnimationClient
    if client ~= nil and client.presented[shell] ~= nil then
        local ok, count = pcall(function() return shell:getItemVisuals():size() end)
        if ok and count > 0 then return false end
    end
    now = tonumber(now) or nowMs()
    if now < (Executor.paintedAtMs[shell] or 0) then return false end
    Executor.paintedAtMs[shell] = now + Executor.settings.spectatorPaintMs
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator == nil or type(hydrator.plan) ~= "function"
            or type(hydrator.applyAppearance) ~= "function" then return false end
    local plan = hydrator.plan(record)
    if type(plan) ~= "table" then return false end
    local painted = hydrator.applyAppearance(shell, plan, true) == true
    if painted then Executor.metrics.painted = (Executor.metrics.painted or 0) + 1 end
    return painted
end

Executor.strays = setmetatable({}, { __mode = "k" })

local function strayFor(shell, uid, now)
    local entry = Executor.strays[shell]
    if entry == nil or entry.uid ~= uid then
        entry = { uid = uid, misses = 0, sequence = -1, firstSeenAtMs = now }
        Executor.strays[shell] = entry
    end
    entry.nextTryAtMs = now + Executor.settings.strayRetryMs
    return entry
end

function Executor.reapStray(shell, uid, now, generation)
    if shell == nil or type(uid) ~= "string" then return false, "no_body" end
    if Executor.mirror.present ~= nil and Executor.mirror.present[uid] ~= nil then
        if generation == nil and shell.getModData ~= nil then local id; id, generation = identityOf(shell) end
        if generation == Executor.mirror.present[uid] then return false, "outside_interest" end
    end
    now = tonumber(now) or nowMs()
    local entry = strayFor(shell, uid, now)

    if now - Executor.mirror.receivedAtMs > Executor.settings.strayMirrorFreshMs then
        entry.misses, entry.sequence = 0, -1
        return false, "mirror_stale"
    end

    if now - (entry.firstSeenAtMs or now) < Executor.settings.strayGraceMs then
        return false, "newborn"
    end

    if shell.isDead ~= nil then
        local ok, dead = pcall(function() return shell:isDead() end)
        if ok and dead == true then return false, "corpse" end
    end
    if Executor.mirror.sequence == entry.sequence then return false, "same_mirror" end
    entry.sequence = Executor.mirror.sequence
    entry.misses = entry.misses + 1
    if entry.misses == 1 then Executor.metrics.strays = Executor.metrics.strays + 1 end
    if entry.misses < Executor.settings.strayMisses then return false, "waiting" end
    scrubBody(shell, "stray")
    if shell.removeFromWorld ~= nil then pcall(function() shell:removeFromWorld() end) end
    if shell.removeFromSquare ~= nil then pcall(function() shell:removeFromSquare() end) end

    entry.misses, entry.sequence = 0, -1
    entry.nextTryAtMs = now + Executor.settings.deathStampGraceMs
    Executor.metrics.reaped = Executor.metrics.reaped + 1
    return true, "reaped"
end

function Executor.observe(shell)
    if not Executor.started or shell == nil then return end
    local uid = Executor.byShell[shell]
    if uid ~= nil then return end 
    local id, generation = identityOf(shell)
    if type(id) ~= "string" then
        if Executor.watchCount > 0 then Executor.watchUnmarked(shell) end
        return
    end
    if Executor.executed[id] ~= nil then return end
    local now = nowMs()
    local stray = Executor.strays[shell]
    if stray ~= nil and stray.uid == id and now < (stray.nextTryAtMs or 0) then return end
    strayFor(shell, id, now)
    if Executor.watchCount > 0 and Executor.watchMarked(shell, id, generation) then return end

    if Executor.cooling(shell, id, now) then
        local cooled = ProjectALife.ActorRegistry.read(id)
        if cooled ~= nil and cooled.lifecycle ~= "dead" then Executor.paintSpectator(shell, cooled) end
        return
    end
    local adopted, reason = Executor.adopt(shell, id, generation)
    if adopted == true then Executor.strays[shell] = nil; return end

    local record = ProjectALife.ActorRegistry.read(id)
    if record ~= nil and record.lifecycle ~= "dead" then
        Executor.paintSpectator(shell, record)
    end

    if reason == "no_record" then Executor.reapStray(shell, id, now, generation) end
end

local function reportOne(uid, entry, now, force)
    if not Executor.authorityFor(entry.shell) then return false end
    local Registry = ProjectALife.ActorRegistry
    local record = Registry.read(uid)
    if record == nil then return false end
    local shell = entry.shell
    local x, y, z, health
    pcall(function() x, y, z = shell:getX(), shell:getY(), shell:getZ() end)
    pcall(function()
        health = shell:getHealth()

        local data = shell:getModData()
        local pool = type(data) == "table" and tonumber(data.ProjectALifeMaximumHealth) or nil
        if pool ~= nil and pool > 0 and health ~= nil and health > pool then
            health = math.min(tonumber(data.ProjectALifeHealthCeiling) or pool, pool)
        end
    end)
    local moved = entry.lastX == nil or math.abs((x or 0) - entry.lastX) > 0.25 or math.abs((y or 0) - entry.lastY) > 0.25
    local changed = record.revision ~= entry.lastRevision
    if not force and not entry.poseDirty and not moved and not changed and now - entry.lastReportAtMs < Executor.settings.reportIntervalMs * 5 then
        return false
    end
    local message = { uid = uid, generation = entry.generation, x = x, y = y, z = z, health = health,
        activity = record.activity, intent = record.intent }

    if entry.freshHealth == true then message.fresh = true end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.capturePose) == "function" then message.pose = animations.capturePose(shell) end

    pcall(function() message.healthAck = tonumber(shell:getModData().ProjectALifeHealthAckLocal) end)
    if changed then
        message.memory = copy(record.memory)
        message.memoryRevision = record.revision
    end

    entry.reportSerial = (tonumber(entry.reportSerial) or 0) + 1
    message.reportSerial = entry.reportSerial
    if type(Executor.adapters.send) == "function" then
        Executor.adapters.send("executorReport", message)
    elseif type(sendClientCommand) == "function" then
        pcall(sendClientCommand, "ProjectALife", "executorReport", message)
    end
    entry.lastReportAtMs, entry.lastRevision, entry.lastX, entry.lastY = now, record.revision, x, y
    entry.poseDirty = nil
    entry.lastPoseSent = message.pose
    Executor.metrics.reports = Executor.metrics.reports + 1
    return true
end

function Executor.reportCombat(entry, now)
    if entry == nil or entry.shell == nil or not Executor.authorityFor(entry.shell)
            or now - (entry.lastReportAtMs or -math.huge) < Executor.settings.reportRateLimitMs then return false end
    local uid = Executor.byShell[entry.shell]
    if uid == nil then return false end
    return reportOne(uid, entry, now, true)
end

function Executor.applyReportRefused(message)
    if type(message) ~= "table" or type(message.uid) ~= "string" then return false, "invalid" end
    local entry = Executor.executed[message.uid]
    if entry == nil or entry.generation ~= tonumber(message.generation) then return false, "not_executed" end
    local again = false
    if finite(message.memoryRevision) and entry.lastRevision == message.memoryRevision then
        entry.lastRevision = -1
        again = true
    end
    if finite(message.reportSerial) and message.reportSerial == entry.reportSerial then again = true end
    if not again then return false, "superseded" end
    entry.poseDirty = true
    Executor.metrics.reportsResent = (Executor.metrics.reportsResent or 0) + 1
    return true, "resend"
end

function Executor.reportDeath(shell)
    local uid = Executor.byShell[shell]
    if uid == nil then return false end
    local entry = Executor.executed[uid]
    if not Executor.entryMatches(shell, uid, entry) then
        Executor.release(uid, "identity_changed")
        return false
    end

    if Executor.diedMatches(uid, entry.generation) then
        Executor.metrics.deathReportsSkipped = Executor.metrics.deathReportsSkipped + 1
    else
        local x, y, z
        pcall(function() x, y, z = shell:getX(), shell:getY(), shell:getZ() end)
        local message = { uid = uid, generation = entry.generation, x = x, y = y, z = z }

        message.killerKind, message.killerKey = Executor.killerOf(shell)
        if type(Executor.adapters.send) == "function" then
            Executor.adapters.send("executorDied", message)
        elseif type(sendClientCommand) == "function" then
            pcall(sendClientCommand, "ProjectALife", "executorDied", message)
        end
    end
    Executor.metrics.deaths = Executor.metrics.deaths + 1
    Executor.release(uid, "dead")
    Executor.holdCorpse(shell, uid)
    return true
end

function Executor.audit(now)
    for index = #Executor.order, 1, -1 do
        local uid = Executor.order[index]
        local entry = Executor.executed[uid]
        if entry == nil then
            table.remove(Executor.order, index)
        else
            local record = ProjectALife.ActorRegistry.read(uid)
            local alive = true
            local ok, dead = pcall(function() return entry.shell:isDead() end)
            if ok and dead == true then alive = false end
            if isOwner(entry.shell) then entry.remoteReads = 0 end
            if not Executor.entryMatches(entry.shell, uid, entry) then

                Executor.release(uid, "identity_changed")
            elseif record == nil or record.lifecycle ~= "active" then
                Executor.release(uid, "record_gone")
            elseif not alive then
                Executor.reportDeath(entry.shell)
            elseif shellGone(entry.shell) then

                entry.missingSinceMs = entry.missingSinceMs or now
                if now - entry.missingSinceMs >= 1500 then
                    local shell = entry.shell
                    Executor.release(uid, "shell_gone")

                    local confirmedAlive = ok and dead == false
                    if confirmedAlive then
                        scrubBody(shell, "shell_gone")
                    else
                        Executor.metrics.scrubsSpared =
                            (Executor.metrics.scrubsSpared or 0) + 1
                    end
                end
            elseif not isOwner(entry.shell) then
                entry.missingSinceMs = nil
                entry.remoteReads = (entry.remoteReads or 0) + 1
                if entry.remoteReads >= Executor.settings.ownershipLossReads then
                    Executor.release(uid, "ownership_lost")
                end
            elseif entry.hydrated ~= true then
                entry.missingSinceMs = nil
                hydrateBody(entry, record, now)
            else
                entry.missingSinceMs = nil
            end
        end
    end
end

function Executor.step(name, callback, ...)
    local ok, result = pcall(callback, ...)
    if ok then return tonumber(result) or 0 end
    fault(name, result)
    return 0
end

function Executor.guardTick()
        local guard = ProjectALife.AIFence
        local count = 0
        for index = 1, #Executor.order do
            local entry = Executor.executed[Executor.order[index]]
            if entry ~= nil and guard ~= nil and type(guard.onZombieUpdate) == "function" then
                guard.onZombieUpdate(entry.shell)
                count = count + 1
            end
        end
        return count
end

function Executor.decisionTick()
        local budget = math.max(Executor.settings.decisionBudgetMinimum, math.min(24, math.ceil(#Executor.order / 3)))
        return ProjectALife.DecisionLoop.tick(budget)
end

function Executor.poseChanged(entry)
    local sent = entry.lastPoseSent
    local shell = entry.shell
    if type(sent) ~= "table" or shell == nil or shell.getModData == nil then return false end
    local data = shell:getModData()
    if type(data) ~= "table" then return false end
    local pace = data.ProjectALifePace == "sprint" and "sprint" or (data.ProjectALifePace == "run" and "run" or "walk")
    return sent.aimWalk ~= (data.ProjectALifeAimWalk == true)
        or sent.weaponHeld ~= (data.ProjectALifeWeaponHeld == true)
        or sent.pace ~= pace
end

function Executor.reportTick(now)
        local sent = 0
        for index = 1, #Executor.order do
            local uid = Executor.order[index]
            local entry = Executor.executed[uid]
            if entry ~= nil and entry.poseDirty ~= true and Executor.poseChanged(entry) then entry.poseDirty = true end
            if entry ~= nil and now - entry.lastReportAtMs >= (entry.poseDirty
                    and Executor.settings.reportRateLimitMs or Executor.settings.reportIntervalMs) then
                if reportOne(uid, entry, now, false) then sent = sent + 1 end
            end
        end
        return sent
end

function Executor.tick()
    if not Executor.started then return 0 end
    local now = nowMs()
    if now - Executor.lastTickAtMs < Executor.settings.tickIntervalMs then return 0 end
    Executor.lastTickAtMs = now
    local transport = ProjectALife.MirrorTransport
    if now - (transport.client.receivedAtMs or -1e12) > 5000 then transport.requestFull(now) end
    Executor.metrics.ticks = Executor.metrics.ticks + 1
    if now - Executor.lastAuditAtMs >= Executor.settings.auditIntervalMs then
        Executor.lastAuditAtMs = now
        Executor.step("audit", Executor.audit, now)
        Executor.step("replicas", Executor.auditReplicas, now)
        Executor.pruneWatch(now)
        Executor.pruneCooldowns(now)
    end
    Executor.sweepDeadBodies(now)
    if #Executor.order == 0 then return 0 end
    local processed = Executor.step("ledger", ProjectALife.ActionLedger.tick, 8)
        + Executor.step("movement", ProjectALife.Movement.tick, 4)
        + Executor.step("animations", ProjectALife.Animations.tick, 8)
        + Executor.step("guard", Executor.guardTick)
        + Executor.step("decisions", Executor.decisionTick)
        + Executor.step("report", Executor.reportTick, now)
    return processed
end

function Executor.onZombieDead(shell)
    if not Executor.started or shell == nil then return end
    if Executor.byShell[shell] == nil then return end

    pcall(function()
        local uid = Executor.byShell[shell]
        local record = uid ~= nil and ProjectALife.ActorRegistry.read(uid) or nil
        if record ~= nil and record.lifecycle == "dead" then return end
        local reactions = ProjectALife.HumanReactions
        if reactions ~= nil and uid ~= nil then reactions.death(shell, uid); reactions.forget(uid) end
    end)
    Executor.reportDeath(shell)

    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.markCorpse) == "function" then sim.markCorpse(shell) end
end

function Executor.dumpExecuted()
    if not Executor.executorSide() then return 0 end
    local Registry, Decisions = ProjectALife.ActorRegistry, ProjectALife.DecisionLoop
    local count = 0
    for index = 1, #Executor.order do
        local uid = Executor.order[index]
        local entry = Executor.executed[uid]
        if entry ~= nil then
            count = count + 1
            local shell = entry.shell
            local record = Registry ~= nil and Registry.read(uid) or nil
            local state = Decisions ~= nil and type(Decisions.states) == "table" and Decisions.states[uid] or nil
            local memory = record ~= nil and type(record.memory) == "table" and record.memory or {}
            local line = "[ALIFE-MP] body uid=" .. uid
                .. " decisions=" .. tostring(state and state.kind) .. "/" .. tostring(state and state.intent)
                .. " action=" .. tostring(state and state.action and state.action.status)
                .. " record=" .. tostring(record and record.activity) .. "/" .. tostring(record and record.intent)
                .. " stance=" .. tostring(memory.stance) .. " conduct=" .. tostring(memory.conduct)
            pcall(function()
                local data = shell:getModData()
                line = line .. " onlineId=" .. tostring(shell:getOnlineID())
                    .. " pathActive=" .. tostring(data.ProjectALifePathActive)
                    .. " bPathfind=" .. tostring(shell:getVariableBoolean("bPathfind"))
                    .. " state=" .. tostring(shell:getActionStateName())
                    .. " moving=" .. tostring(shell:isMoving())
                    .. " useless=" .. tostring(shell:isUseless())
                    .. " pos=" .. tostring(shell:getX()) .. "," .. tostring(shell:getY()) .. "," .. tostring(shell:getZ())
                    .. " phase=" .. tostring(data.ProjectALifeCombatPhase)
                    .. " abort=" .. tostring(data.ProjectALifeCombatAbortReason)
                    .. " line=" .. tostring(data.ProjectALifeLastLineReason)
                    .. " hydrated=" .. tostring(entry.hydrated)
                local weapons = ProjectALife.Weapons
                local weapon = weapons ~= nil and type(weapons.current) == "function" and weapons.current(shell) or nil
                local ammo
                pcall(function() if weapon ~= nil then ammo = weapon:getCurrentAmmoCount() end end)
                line = line .. " weapon=" .. tostring(weapon and weapon:getFullType()) .. " ammo=" .. tostring(ammo)
                    .. " reserve=" .. tostring(data.ProjectALifePrimaryAmmoUnits)
            end)
            print(line)
            pcall(function()
                local blackBox = ProjectALife.BlackBox
                if blackBox ~= nil and type(blackBox.dump) == "function" then blackBox.dump(shell, "qa") end
            end)
        end
    end
    return count
end

function Executor.qaLine()
    local m = Executor.metrics
    if Executor.executorSide() then
        local extra = ""
        pcall(function()
            local Watchdog, Decisions = ProjectALife.Watchdog, ProjectALife.DecisionLoop
            local Ledger, movement, modules = ProjectALife.ActionLedger, ProjectALife.Movement, ProjectALife.ModuleRegistry
            local mm = movement ~= nil and movement.metrics or {}
            local cm = ProjectALife.Combat ~= nil and ProjectALife.Combat.metrics or {}
            extra = " releases=" .. countPairs(m.releaseReasons) .. " refusals=" .. countPairs(m.adoptRefusals)
                .. " bindings=" .. tostring(Watchdog and Watchdog.order and #Watchdog.order)
                .. " decisionOrder=" .. tostring(Decisions and Decisions.order and #Decisions.order)
                .. " ledger=" .. tostring(Ledger and Ledger.order and #Ledger.order)
                .. " movement=" .. tostring(mm.requested) .. "/" .. tostring(mm.requestErrors) .. "/" .. tostring(mm.stalls)
                .. "/" .. tostring(mm.unreachableFailures) .. "/" .. tostring(mm.lastFailure)
                .. " modules=" .. tostring(modules and modules.lastError)
                .. " hydrated=" .. m.hydrated .. "/" .. m.hydrateFailures .. ":" .. tostring(m.lastHydrateError)
                .. " catalog=" .. tostring(ProjectALife.Catalog and ProjectALife.Catalog.current
                    and #ProjectALife.Catalog.current.npcOrder)
                .. " ledgerRefused=" .. countPairs(Ledger and Ledger.metrics and Ledger.metrics.refused)
                .. " beginRefused=" .. countPairs(Decisions and Decisions.metrics and Decisions.metrics.beginRefused)
                .. " grudges=" .. tostring(m.grudgesTaken or 0) .. "/" .. tostring(m.grudgesKept or 0)
                .. " resent=" .. tostring(m.reportsResent or 0)
                .. " replicaAsks=" .. tostring(m.replicaAsks or 0)
                .. " combat=" .. tostring(ProjectALife.Combat and ProjectALife.Combat.sequence)
                .. " strikes=" .. tostring(cm.zombieStrikes) .. "/" .. tostring(cm.zombieStruck)
                .. " playerHits=" .. tostring(cm.playerHits) .. "/" .. tostring(cm.playerHitFailures)
                .. ":" .. tostring(cm.lastPlayerHitError)
                .. " attacks=" .. tostring(cm.attackTries) .. " refusedBy=" .. countPairs(cm.attackRefusedBy)
                .. " shots=" .. tostring(cm.shots) .. "/" .. tostring(cm.swings) .. "/" .. tostring(cm.shoves)
                .. "/" .. tostring(cm.misses) .. " actorHits=" .. tostring(cm.actorHits)
                .. " gunner=" .. tostring(ProjectALife.ModuleGunner and ProjectALife.ModuleGunner.metrics.orders)
                .. "/" .. tostring(ProjectALife.ModuleGunner and ProjectALife.ModuleGunner.metrics.rounds)
                .. " combatHotfix=20260915"
                .. " scrubbed=" .. m.scrubbed .. " support=" .. m.supportRelayed
                .. " strays=" .. m.strays .. "/" .. m.reaped
                .. " hitsRelayed=" .. m.playerHitsRelayed
                .. " painted=" .. tostring(m.painted or 0)

                .. " flinchCut=" .. tostring(ProjectALife.AIFence
                    and ProjectALife.AIFence.metrics.reactionsCut)
                .. " careful=" .. tostring(ProjectALife.ModuleCareful
                    and ProjectALife.ModuleCareful.metrics.warnings)
                .. "/" .. tostring(ProjectALife.ModuleCareful
                    and ProjectALife.ModuleCareful.metrics.lastWarnings)
                .. "/" .. tostring(ProjectALife.ModuleCareful
                    and ProjectALife.ModuleCareful.metrics.turned)
                .. " shouts=" .. tostring(ProjectALife.Investigation
                    and ProjectALife.Investigation.metrics.shoutAnswers)

                .. " guard=" .. (function()
                    local g = ProjectALife.AIFence and ProjectALife.AIFence.metrics or {}
                    return tostring(g.reactionsCut or 0) .. "/" .. tostring(g.freezesCleared or 0)
                        .. "/" .. tostring(g.finishers or 0) .. "/" .. tostring(g.blowsTurned or 0)
                        .. "/" .. tostring(g.fallsShielded or 0)

                        .. "/fence:" .. tostring(g.fenced or 0) .. ":" .. tostring(g.restored or 0)
                end)()

                .. " crowd=" .. (function()
                    local g = ProjectALife.AIFence and ProjectALife.AIFence.metrics or {}
                    return tostring(g.crowdNudges or 0) .. "/" .. tostring(g.laneYields or 0)
                        .. "/" .. tostring(g.laneBlocked or 0) .. "/" .. tostring(g.laneReturns or 0)
                        .. "/" .. tostring(g.laneShoves or 0) .. "/" .. tostring(g.crowdBudgetSkips or 0)
                        .. "/" .. tostring(g.playerArrivals or 0) .. ":" .. tostring(g.playerStopsRetried or 0)
                        .. "/" .. tostring(g.playerBumps or 0)
                end)()
                .. " horde=" .. (function()
                    local h = ProjectALife.HordeRelations and ProjectALife.HordeRelations.metrics or {}
                    return tostring(h.chases or 0) .. "/" .. tostring(h.bites or 0) .. "/"
                        .. tostring(h.posed or 0) .. "/" .. tostring(h.damaged or 0) .. "/" .. tostring(h.reclaimed or 0)
                end)()
                .. " worn=" .. tostring(ProjectALife.ProfileHydrator and ProjectALife.ProfileHydrator.metrics
                    and ProjectALife.ProfileHydrator.metrics.worn or 0)
                .. "/" .. tostring(ProjectALife.ProfileHydrator and ProjectALife.ProfileHydrator.metrics
                    and ProjectALife.ProfileHydrator.metrics.wearFailed or 0)

                .. " props=" .. (function()
                    local a = ProjectALife.Animations and ProjectALife.Animations.metrics or {}
                    return tostring(a.propsApplied or 0) .. "/ded:" .. tostring(a.propsRefusedDedicated or 0)
                        .. "/nofac:" .. tostring(a.propsNoFactory or 0)
                end)()
                .. " noise=" .. tostring(m.noiseRelayed or 0)

                .. " lifecycle=" .. tostring(m.killedLocally) .. "/" .. tostring(m.corpseScrubs)
                .. ":" .. tostring(m.corpseScrubsReused) .. "/" .. tostring(m.reappeared)
        end)
        return "Executor: started=" .. tostring(Executor.started) .. " executing=" .. #Executor.order
            .. " adopted=" .. m.adopted .. " released=" .. m.released .. " reports=" .. m.reports
            .. " deaths=" .. m.deaths .. " ticks=" .. m.ticks .. " mirror=" .. tostring(Executor.mirror.count)
            .. " mirrorApplies=" .. m.mirrorApplies .. " faults=" .. m.faults .. " error=" .. tostring(m.lastError)
            .. ProjectALife.MirrorTransport.qaLine()
            .. extra
    end
    return "Executor: delegating=" .. tostring(Executor.serverDelegates()) .. " transmits=" .. m.transmits
        .. " reportsApplied=" .. m.reportsApplied .. " reportsRejected=" .. m.reportsRejected
        .. " deathsApplied=" .. m.deathsApplied .. " lastReject=" .. tostring(m.lastReject)
        .. " rejectedBy=" .. countPairs(m.rejectedBy) .. " grudgesHanded=" .. tostring(m.grudgesHanded or 0)
        .. " resendAsked=" .. tostring(m.refusalsSent or 0)
        .. " support=" .. m.supportApplied .. "/" .. m.supportRefused .. ":" .. tostring(m.lastSupportReason)
        .. " playerHitsApplied=" .. m.playerHitsApplied .. Executor.hitRules().qaLine()

        .. " handed=" .. m.deathsHanded .. "/" .. m.deathPushes .. "/" .. m.deathRevived
        .. "/" .. m.deathFallbacks .. "/" .. m.deathForced .. " reported=" .. m.deathsReported
        .. " owners=" .. m.ownerDropped .. "/" .. m.unreported .. "/" .. m.ownerWindowParked
        .. "/" .. m.replicaResent
        .. " replicaAsked=" .. tostring(m.replicaAsked or 0) .. " askRefused=" .. countPairs(m.replicaAskRefused)
        .. ProjectALife.MirrorTransport.qaLine()
end

function Executor.register()
    if Executor.registered then return true end
    if type(Events) ~= "table" then return false end
    Executor.registered = true
    local function add(name, callback)
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
    end
    if Executor.executorSide() then
        add("OnGameStart", function()
            local options = ProjectALife.Settings and ProjectALife.Settings.runtimeOptions() or {}
            local ok, err = Executor.start(options)
            if not ok then fault("start", err) end
        end)
        add("OnReceiveGlobalModData", Executor.onReceiveGlobalModData)
        add("OnServerCommand", function(module, command, message)
            if module == "ProjectALife" and command == "executorMirror" then
                local ok, err = pcall(ProjectALife.MirrorTransport.receive, message)
                if not ok then fault("mirror_frame", err) end
            elseif module == "ProjectALife" and command == "executorReportRefused" then
                Executor.applyReportRefused(message)
            end
        end)
        add("OnTick", function()
            local ok, err = pcall(Executor.tick)
            if not ok then fault("tick", err) end
        end)
        add("OnZombieDead", Executor.onZombieDead)
        add("OnDeadBodySpawn", Executor.onDeadBodySpawn)
    elseif type(isServer) == "function" and isServer() then
        add("OnClientCommand", Executor.onClientCommand)
    end
    return true
end

return Executor
