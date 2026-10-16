require "ProjectALife/Senses/ALifeFoliage"
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Shells/ALifeTraversalHands"
require "ProjectALife/Compat/ALifeEquipEventShield"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Compat/ALifeInterop"
require "ProjectALife/Shells/ALifeArmor"
ProjectALife = ProjectALife or {}

if ProjectALife.AIFence ~= nil then
    return ProjectALife.AIFence
end

local Interop = ProjectALife.Interop
local Fence = {
    owned = setmetatable({}, { __mode = "k" }),
    rejected = setmetatable({}, { __mode = "k" }),
    voicedShells = setmetatable({}, { __mode = "k" }),
    nextVoiceSweepAtMs = setmetatable({}, { __mode = "k" }),
    nextTraversalAudioSweepAtMs = setmetatable({}, { __mode = "k" }),
    nextPaceRefreshAtMs = setmetatable({}, { __mode = "k" }),
    nextTerrainSweepAtMs = setmetatable({}, { __mode = "k" }),
    terrainSlow = setmetatable({}, { __mode = "k" }),

    aimFacing = setmetatable({}, { __mode = "k" }),

    reloadBumpSinceMs = setmetatable({}, { __mode = "k" }),
    hitAudioPending = setmetatable({}, { __mode = "k" }),
    nextHitReactAtMs = setmetatable({}, { __mode = "k" }),

    roomSweptAt = setmetatable({}, { __mode = "k" }),
    roomFrame = 0,

    observersLive = true,

    lowerMemo = {},
    lowerMemoSize = 0,
    groundMemo = {},
    groundMemoSize = 0,
    memoLimit = 256,
    registered = false,
    voiceSweepIntervalMs = 3000,
    traversalAudioSweepIntervalMs = 200,
    paceRefreshIntervalMs = 100,
    terrainSweepIntervalMs = 500,

    aimTurnRadiansPerSecond = 2.8,
    aimFacingStaleMs = 300,

    reloadBumpOverdueMs = 12000,

    hitReactCooldownMs = 3000,
    meleeHitReactCooldownMs = 1100,
    hitReactionPercent = 100,
    rangedHitReactionPercent = 100,
    hitReactionMs = 200,
    hitCleanupWindowMs = 550,

    groundRestMs = 1800,
    groundGetUpMs = 1100,
    metrics = {
        tracked = 0,
        updates = 0,
        failures = 0,
        lastError = nil,

        reactionsCut = 0,

        shovesShrugged = 0,

        freezesCleared = 0,

        finishers = 0,

        shovesAbsorbed = 0,
        stompsWeighed = 0,
        roomsRebound = 0,

        fenced = 0,
        restored = 0,

        delegatedKills = 0,

        physicsReactionsLeft = 0,

        ragdollLandings = 0,

        orphanPathsReleased = 0,

        crowdArrivals = 0,

        crowdNudges = 0,
        laneYields = 0,
        laneBlocked = 0,
        laneReturns = 0,
        laneShoves = 0,
        crowdBudgetSkips = 0,
        playerArrivals = 0,
        playerStopsRetried = 0,

        playerBumps = 0,
        playerBumpLinesHeld = 0,
    },
}
ProjectALife.AIFence = Fence

function Fence.repairRoom(square)
    if square == nil or square.getRoom == nil or square.getChunk == nil then return false end
    local room = square:getRoom()
    if room == nil or room.getBuilding == nil or room.getRoomDef == nil then return false end
    if room:getBuilding() ~= nil and room:getRoomDef() ~= nil then return false end
    if square:getChunk() == nil or type(getWorld) ~= "function" or type(getCell) ~= "function" then return false end
    local cell, world = getCell(), getWorld()
    if cell == nil or world == nil or world.getMetaGrid == nil then return false end
    if cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then return false end
    local meta = world:getMetaGrid()
    if meta == nil then return false end
    local definition = meta:getRoomAt(square:getX(), square:getY(), square:getZ())
    if definition ~= nil then
        local fresh = definition:getIsoRoom()
        if fresh == nil or fresh:getBuilding() == nil or fresh:getRoomDef() == nil then return false end

        square:setRoom(fresh)
    else

        square:setRoomID(-1)
    end
    square:RecalcProperties()
    Fence.metrics.roomsRebound = Fence.metrics.roomsRebound + 1
    return true
end

Fence.frameSampling = false
Fence.frameTiming = { every = 30, countdown = 0, spentMs = 0, calls = 0, windowMs = 60000, windowAtMs = nil,
    frames = 0, busyFrames = 0, sumMs = 0, maxMs = 0, callsSum = 0, over4 = 0, over8 = 0, over16 = 0 }

function Fence.resetFrameTiming(timing)
    timing.countdown, timing.spentMs, timing.calls, timing.windowAtMs = 0, 0, 0, nil
    timing.frames, timing.busyFrames, timing.sumMs, timing.maxMs, timing.callsSum = 0, 0, 0, 0, 0
    timing.over4, timing.over8, timing.over16 = 0, 0, 0
end

function Fence.noteSampledCall(startedAt)
    local timing = Fence.frameTiming
    timing.spentMs = timing.spentMs + math.max(0, getTimestampMs() - startedAt)
    timing.calls = timing.calls + 1
end

function Fence.closeSampledFrame(timing)
    local horde = ProjectALife.HordeRelations
    if horde ~= nil and type(horde.closeSampledFrame) == "function" then horde.closeSampledFrame() end
    timing.frames = timing.frames + 1
    if timing.calls <= 0 then return false end
    local spent = timing.spentMs
    timing.busyFrames = timing.busyFrames + 1
    timing.callsSum = timing.callsSum + timing.calls
    timing.sumMs = timing.sumMs + spent
    if spent > timing.maxMs then timing.maxMs = spent end
    if spent > 4 then timing.over4 = timing.over4 + 1 end
    if spent > 8 then timing.over8 = timing.over8 + 1 end
    if spent > 16 then
        timing.over16 = timing.over16 + 1
        local runtime = ProjectALife.Runtime
        if runtime ~= nil and type(runtime.noteDetail) == "function" then pcall(runtime.noteDetail, "frame_fence", spent) end
    end
    return true
end

function Fence.reportFrameTiming(timing, now)
    local windowMs = now - timing.windowAtMs
    local horde = ProjectALife.HordeRelations
    if horde ~= nil and type(horde.reportFrameTiming) == "function" then horde.reportFrameTiming(windowMs) end
    local line
    if timing.busyFrames > 0 and windowMs >= 0 then
        line = string.format("[ALIFE-PERF] frame_fence %ds sampled=%d/%d npcs=%.1f avg=%.2fms max=%dms over4=%d over8=%d over16=%d",
            math.floor(windowMs / 1000), timing.busyFrames, timing.frames, timing.callsSum / timing.busyFrames,
            timing.sumMs / timing.busyFrames, math.floor(timing.maxMs), timing.over4, timing.over8, timing.over16)
        print(line)
    end
    local countdown = timing.countdown
    Fence.resetFrameTiming(timing)
    timing.countdown, timing.windowAtMs = countdown, now
    return line
end

function Fence.frameBeat()
    local timing = Fence.frameTiming
    if Fence.frameSampling == true then
        Fence.frameSampling = false
        Fence.closeSampledFrame(timing)
    end
    local box = ProjectALife.BlackBox
    if box == nil or box.enabled ~= true or type(getTimestampMs) ~= "function" then
        if timing.windowAtMs ~= nil then Fence.resetFrameTiming(timing) end
        return false
    end
    local now = getTimestampMs()

    timing.nowMs = now
    if timing.windowAtMs == nil or now < timing.windowAtMs then
        timing.windowAtMs = now
    elseif now - timing.windowAtMs >= timing.windowMs then
        Fence.reportFrameTiming(timing, now)
    end
    timing.countdown = timing.countdown - 1
    if timing.countdown > 0 then return false end
    timing.countdown = timing.every
    timing.spentMs, timing.calls = 0, 0
    Fence.frameSampling = true
    return true
end

function Fence.repairOccupiedRooms()

    Fence.roomFrame = (Fence.roomFrame or 0) + 1

    local sweepAt = nil
    local box = ProjectALife.BlackBox
    if (box ~= nil and box.enabled == true) or Fence.frameSampling == true
            or Fence.frameTiming.windowAtMs ~= nil then
        sweepAt = Fence.frameBeat() and getTimestampMs() or nil
    end

    local live = type(isClient) == "function" and isClient()
        and (type(isServer) ~= "function" or not isServer())
    local executor = ProjectALife.Executor
    if not live and executor ~= nil and executor.started then live = true end
    Fence.observersLive = live and true or false

    local handsLive = type(isClient) == "function" and isClient()
    for shell in pairs(Fence.owned) do
        if handsLive then pcall(ProjectALife.TraversalHands.prepare, shell) end
        if shell.getCurrentSquare ~= nil then
            local ok, failure = pcall(Fence.repairRoom, shell:getCurrentSquare())
            if not ok then Fence.metrics.lastError = tostring(failure) end
            Fence.roomSweptAt[shell] = Fence.roomFrame
        end
    end

    if type(getSpecificPlayer) == "function" then

        local probeAt = nil
        if box ~= nil and box.enabled == true then probeAt = Fence.frameTiming.nowMs end
        for index = 0, 3 do
            local player = getSpecificPlayer(index)
            if player ~= nil and player.getCurrentSquare ~= nil then
                pcall(Fence.repairRoom, player:getCurrentSquare())
                if probeAt ~= nil then pcall(Fence.probeBump, player, index, probeAt) end
            end
        end
    end
    if sweepAt ~= nil then
        local timing = Fence.frameTiming
        timing.spentMs = timing.spentMs + math.max(0, getTimestampMs() - sweepAt)
    end
end

Fence.bumpProbe = { gapMs = 1000, sampleMs = 100, linesPerMinute = 12, linesAtMs = nil, lines = 0, slots = {} }
function Fence.probeBump(player, index, now)
    if type(player.getX) ~= "function" or type(player.getBumpType) ~= "function" then return false end
    local probe = Fence.bumpProbe
    local slot = probe.slots[index + 1]
    if slot == nil or slot.player ~= player then
        slot = { player = player, x = player:getX(), y = player:getY(), atMs = now, speed = 0, bumped = false }
        probe.slots[index + 1] = slot
    elseif now < slot.atMs or now - slot.atMs >= probe.sampleMs then
        local x, y = player:getX(), player:getY()
        local span = now - slot.atMs
        if span > 0 and span <= 1000 then
            local dx, dy = x - slot.x, y - slot.y
            slot.speed = math.sqrt(dx * dx + dy * dy) * 1000 / span
        else
            slot.speed = 0
        end
        slot.x, slot.y, slot.atMs = x, y, now
    end
    local bump = player:getBumpType()
    if bump == nil or bump == "" then
        slot.bumped = false
        return false
    end
    if slot.bumped == true then return false end
    slot.bumped = true
    if type(player.getBumpedChr) ~= "function" then return false end
    local body = player:getBumpedChr()
    if body == nil or not Fence.isActorBody(body) then return false end
    Fence.metrics.playerBumps = (Fence.metrics.playerBumps or 0) + 1
    if slot.lineAtMs ~= nil and now >= slot.lineAtMs and now - slot.lineAtMs < probe.gapMs then return false end
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or blackBox.enabled ~= true then return false end
    local line = Fence.bumpLine(player, body, slot.speed, bump)
    if blackBox.enabled == true and type(blackBox.note) == "function" then
        blackBox.note(body, "player-bump", line)
    end
    local detect = type(blackBox.metrics) == "table" and blackBox.metrics.detect or nil
    if type(detect) == "table" then detect["player-bump"] = (detect["player-bump"] or 0) + 1 end
    if not Fence.spendProbeLine(now) then return true end
    slot.lineAtMs = now
    print(tostring(blackBox.marker) .. " detect=player-bump " .. line)
    return true
end

function Fence.spendProbeLine(now)
    local probe = Fence.bumpProbe
    if probe.linesAtMs == nil or now < probe.linesAtMs or now - probe.linesAtMs >= 60000 then
        probe.linesAtMs, probe.lines = now, 0
    end
    if (probe.lines or 0) >= (probe.linesPerMinute or 12) then
        Fence.metrics.playerBumpLinesHeld = (Fence.metrics.playerBumpLinesHeld or 0) + 1
        return false
    end
    probe.lines = (probe.lines or 0) + 1
    return true
end

function Fence.flag(value)
    if value == true then return "1" end
    return "0"
end

function Fence.bumpLine(player, body, speed, bump)
    local data = body:getModData()
    local moving, remote, owner = "?", "?", "none"
    if type(body.isMoving) == "function" then moving = Fence.flag(body:isMoving()) end
    if type(body.isRemoteZombie) == "function" then remote = Fence.flag(body:isRemoteZombie()) end
    if type(body.getOwnerPlayer) == "function" then
        local who = body:getOwnerPlayer()
        if who ~= nil and type(who.getUsername) == "function" then owner = tostring(who:getUsername()) end
    end
    local name, run, sprint, fall = "?", "?", "?", "?"
    if type(player.getUsername) == "function" then name = tostring(player:getUsername()) end
    if type(player.isRunning) == "function" then run = Fence.flag(player:isRunning()) end
    if type(player.isSprinting) == "function" then sprint = Fence.flag(player:isSprinting()) end
    if type(player.isBumpFall) == "function" then fall = Fence.flag(player:isBumpFall()) end
    return string.format("uid=%s at=%.1f,%.1f phase=%s path=%s moving=%s remote=%s owner=%s driven=%s"
        .. " player=%s speed=%.2f run=%s sprint=%s fall=%s bump=%s down=%s",
        tostring(data.ProjectALifeUID), body:getX(), body:getY(), tostring(data.ProjectALifeCombatPhase or "idle"),
        Fence.flag(data.ProjectALifePathActive == true), moving, remote, owner, Fence.flag(Fence.drivesBody(body)),
        name, speed, run, sprint, fall, tostring(bump), tostring(data.ProjectALifeInjured or "-"))
end

Fence.reactionRecovery = setmetatable({}, { __mode = "k" })
function Fence.exitStandingReaction(shell)
    if shell == nil then return false end

    if Fence.physicsReaction(shell) then
        local stateOk, raw = pcall(shell.getActionStateName, shell)
        if stateOk and string.sub(string.lower(tostring(raw or "")), 1, 11) == "hitreaction" then
            if Fence.reactionRecovery[shell] ~= "physics" then
                Fence.reactionRecovery[shell] = "physics"
                Fence.metrics.physicsReactionsLeft = (Fence.metrics.physicsReactionsLeft or 0) + 1
            end
            return false
        end
    end
    return pcall(function()
        local state = string.lower(tostring(shell:getActionStateName() or ""))
        if string.sub(state, 1, 11) == "hitreaction" then
            Fence.reactionRecovery[shell] = true
            shell:setStaggerBack(true)
        elseif state == "staggerback" then
            shell:setStateEventDelayTimer(0)
        elseif state == "bumped" then
            shell:setBumpDone(true)
            shell:setVariable("BumpAnimFinished", true)
        end
    end)
end

function Fence.physicsReaction(shell)
    return type(shell.usePhysicHitReaction) == "function" and shell:usePhysicHitReaction() == true
        and type(shell.canRagdoll) == "function" and shell:canRagdoll() == true
end

function Fence.isRagdollState(state)
    return type(state) == "string" and string.find(state, "ragdoll", 1, true) ~= nil
end

function Fence.ragdollFlag(shell)
    return shell ~= nil and type(shell.isRagdoll) == "function" and shell:isRagdoll() == true
end

function Fence.ragdolling(shell, state)
    return Fence.isRagdollState(state) or Fence.ragdollFlag(shell)
end

function Fence.cutsReaction(actionState, staggerUntilMs, now, foreignBump)
    if type(actionState) ~= "string" then return false end
    local reaction = string.sub(actionState, 1, 11) == "hitreaction"
    local bumped = foreignBump == true and string.sub(actionState, 1, 6) == "bumped"
    if not reaction and not bumped then return false end

    if string.find(actionState, "onfloor", 1, true) ~= nil
            or string.find(actionState, "gettingup", 1, true) ~= nil then return false end
    local mine = tonumber(staggerUntilMs)
    if mine ~= nil and (tonumber(now) or 0) < mine then return false end
    return true
end

function Fence.bumpOrphaned(actionState, bumpType, ownedPreset)
    if actionState ~= "bumped" then return false end
    if ownedPreset ~= nil then return false end
    return tostring(bumpType or "") == ""
end

function Fence.downedHolds(untilMs, now)
    local limit = tonumber(untilMs)
    return limit ~= nil and (tonumber(now) or 0) < limit
end

Fence.finisherSettleMs = 500

Fence.friendForgivesMs = 60000

function Fence.friendForgives(shell, player, now)
    if shell == nil or player == nil or type(instanceof) ~= "function"
            or not instanceof(player, "IsoPlayer") or type(shell.getModData) ~= "function" then
        return false
    end
    local data = shell:getModData()
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    local registry, relations = ProjectALife.ActorRegistry, ProjectALife.Relations
    if type(uid) ~= "string" or registry == nil or type(registry.read) ~= "function"
            or relations == nil or type(relations.playerStance) ~= "function" then
        return false
    end
    local actor = registry.read(uid)
    if actor == nil then return false end
    now = tonumber(now) or 0
    local previous = tonumber(data.ProjectALifePlayerBlowAtMs) or -math.huge
    data.ProjectALifePlayerBlowAtMs = now
    if relations.playerStance(actor, player) == "friendly" and now - previous > Fence.friendForgivesMs then
        Fence.metrics.blowsForgiven = (Fence.metrics.blowsForgiven or 0) + 1
        return true
    end
    return false
end
function Fence.finishesDowned(grounded, melee, downedUntilMs, now, groundedSinceMs, shove)
    if grounded ~= true then return false end

    if shove == true then return false end

    local since = tonumber(groundedSinceMs)
    if since == nil or (tonumber(now) or 0) - since < Fence.finisherSettleMs then return false end
    if melee == true then return true end
    return Fence.downedHolds(downedUntilMs, now)
end

function Fence.heldDown(shell, now)
    local untilMs
    if shell ~= nil then
        local dataOk, data = pcall(shell.getModData, shell)
        if dataOk and type(data) == "table" then untilMs = data.ProjectALifeDownedUntilMs end
    end
    return Fence.downedHolds(untilMs, now)
end

function Fence.reloadBumpOverdue(since, now, limit)
    if since == nil then return false end
    return (tonumber(now) or 0) - (tonumber(since) or 0) >= (tonumber(limit) or 0)
end

function Fence.turnDirection(fromX, fromY, toX, toY, maxRadians)
    local dot = math.max(-1, math.min(1, fromX * toX + fromY * toY))
    local angle = math.acos(dot)
    if angle <= maxRadians then return toX, toY end
    local cross = fromX * toY - fromY * toX
    local sign = cross < 0 and -1 or 1
    local turn = math.max(0, maxRadians) * sign
    local cosine, sine = math.cos(turn), math.sin(turn)
    return fromX * cosine - fromY * sine,
        fromX * sine + fromY * cosine
end

function Fence.positionOf(shell)
    return shell:getX(), shell:getY()
end

function Fence.snapDirection(shell, dx, dy)
    shell:setTargetAndCurrentDirection(dx, dy)
    return true
end

function Fence.faceAimPoint(shell, aimX, aimY, suppliedNow)
    if shell == nil then return false end
    local positionOk, x, y = pcall(Fence.positionOf, shell)
    aimX, aimY = tonumber(aimX), tonumber(aimY)
    if not positionOk or aimX == nil or aimY == nil then return false end
    local dx, dy = aimX - x, aimY - y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return false end
    dx, dy = dx / length, dy / length
    local now = tonumber(suppliedNow)
        or (type(getTimestampMs) == "function" and getTimestampMs())
        or math.floor(os.time() * 1000)
    local facing = Fence.aimFacing[shell]
    if type(facing) ~= "table" or now - (tonumber(facing.atMs) or 0) > Fence.aimFacingStaleMs then
        local fx, fy
        pcall(function()
            local forward = shell:getForwardDirection()
            fx, fy = forward:getX(), forward:getY()
        end)
        local facingLength = math.sqrt((tonumber(fx) or 0) ^ 2
            + (tonumber(fy) or 0) ^ 2)
        if facingLength < 0.001 then
            fx, fy, facingLength = dx, dy, 1
        end
        facing = { x = fx / facingLength, y = fy / facingLength,
            atMs = now - 33 }
    end
    local elapsed = math.max(16, math.min(100, now - (tonumber(facing.atMs) or now)))
    dx, dy = Fence.turnDirection(facing.x, facing.y, dx, dy,
        Fence.aimTurnRadiansPerSecond * elapsed / 1000)
    facing.x, facing.y, facing.atMs = dx, dy, now
    Fence.aimFacing[shell] = facing
    if shell.setTargetAndCurrentDirection ~= nil
            and pcall(Fence.snapDirection, shell, dx, dy) then
        return true
    end
    local turned, turnError = pcall(shell.faceLocationF, shell, aimX, aimY)
    if turned then return true end
    return false, turnError
end

function Fence.stableStrafe(sx, sy)
    sx, sy = tonumber(sx) or 0, tonumber(sy) or 0
    if math.abs(sx) < 0.1 then sx = 0 end
    if math.abs(sy) < 0.1 then sy = 0 end
    if sy < -0.55 and math.abs(sx) < 0.3 then sx = 0 end
    return sx, sy
end

Fence.nativeCueSources = {
    foley = {
        "ZombieScratch", "ZombieBite", "NeckBite", "ZombieCrawlLungeSwing",
        "ZombieCrawlLungeHit", "ZombieSurprisedPlayer", "ZombieTrip",
        "ZombieClawChainlinkFence", "ZombieClawGarageDoor", "ZombieClawMetal",
        "ZombieClawWood",
    },
    sexes = { "Female", "Male" },
    banks = { { "Voice", 3 }, { "SprinterVoice", 2 }, { "Bite", 3 }, { "SprinterBite", 2 } },
}

function Fence.nativeCueNames(sources)
    sources = sources or Fence.nativeCueSources
    local names = {}
    for _, name in ipairs(sources.foley) do names[#names + 1] = name end
    for _, sex in ipairs(sources.sexes) do
        for _, bank in ipairs(sources.banks) do
            for letter = 1, bank[2] do
                names[#names + 1] = sex .. "Zombie" .. bank[1] .. string.char(64 + letter)
            end
        end
    end
    return names
end
Fence.nativeCues = Fence.nativeCueNames()

local NATIVE_TRAVERSAL_SOUNDS = {
    "ZombieTrip", "ZombieCrawlLungeSwing", "ZombieCrawlLungeHit",
    "ZombieClawChainlinkFence", "ZombieClawGarageDoor",
    "ZombieClawMetal", "ZombieClawWood",
}

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

Fence.silentVoiceBank = "ALifeSilentBank"

function Fence.claimVoiceBank(shell)
    if shell == nil or type(shell.getDescriptor) ~= "function" then return false end
    local ok, descriptor = pcall(shell.getDescriptor, shell)
    if not ok or descriptor == nil then return false end
    if type(descriptor.getVoicePrefix) == "function" then
        local readOk, current = pcall(descriptor.getVoicePrefix, descriptor)
        if readOk and current == Fence.silentVoiceBank then return false end
    end
    if type(descriptor.setVoicePrefix) ~= "function" then return false end
    return pcall(descriptor.setVoicePrefix, descriptor, Fence.silentVoiceBank) == true
end

local function silenceNativeVoice(shell, force)
    if shell == nil then return end
    local sweep = Fence.claimVoiceBank(shell) or force == true
    if Fence.hitAudioPending[shell] then
        Fence.hitAudioPending[shell] = nil
        sweep = true
    end
    local now = nowMs()
    if not sweep and now < (Fence.nextVoiceSweepAtMs[shell] or 0) then return end
    Fence.nextVoiceSweepAtMs[shell] = now + Fence.voiceSweepIntervalMs
    Fence.voicedShells[shell] = true
    pcall(function() shell:setCanShout(false) end)
    pcall(function()
        local emitter = shell:getEmitter()
        if emitter == nil then return end
        local cues = Fence.nativeCues
        for index = 1, #cues do emitter:stopSoundByName(cues[index]) end
    end)
end

local function silenceTraversalAudio(shell, force)
    if shell == nil then return end
    local now = nowMs()
    if not force and now < (Fence.nextTraversalAudioSweepAtMs[shell] or 0) then return end
    Fence.nextTraversalAudioSweepAtMs[shell] = now
        + Fence.traversalAudioSweepIntervalMs
    pcall(function()
        local emitter = shell:getEmitter()
        if emitter == nil then return end
        for _, name in ipairs(NATIVE_TRAVERSAL_SOUNDS) do
            emitter:stopSoundByName(name)
        end
    end)
end

Fence.combatSpeed = {
    ["1hand"] = 1.18,
    ["2hand"] = 1.02,
    spear = 1.06,
    default = 1.12,
}

function Fence.combatSpeedFor(grip, carry)
    local speeds = Fence.combatSpeed
    local speed = speeds[grip] or speeds[carry] or speeds.default
    return math.max(0.6, math.min(2, tonumber(speed) or 1))
end

local function markOwned(shell)
    pcall(function()
        local data = shell:getModData()
        data.ProjectALifeOwned = true
        data.ProjectALifeActor = true
    end)
    local ok = pcall(function()
        shell:SetVariable("ALifeActor", "true")
    end)
    if not ok then
        pcall(function()
            shell:setVariable("ALifeActor", "true")
        end)
    end
end

local function isMarkedOwned(shell)
    local ok, data = pcall(shell.getModData, shell)
    return ok and data ~= nil
        and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
end

function Fence.marksOwned(data)
    return data ~= nil and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
end

Fence.stuckLimits = { turnalerted = 300 }

Fence.stuckSinceMs = setmetatable({}, { __mode = "k" })

Fence.lastPosition = setmetatable({}, { __mode = "k" })
Fence.voiceBurstUntilMs = setmetatable({}, { __mode = "k" })
Fence.proneSinceMs = setmetatable({}, { __mode = "k" })

Fence.observeSkip = setmetatable({}, { __mode = "k" })
Fence.observeEvery = 30

Fence.proneFirstMs = setmetatable({}, { __mode = "k" })
Fence.proneMaxMs = 4000

Fence.downedHardCapMs = 16000

Fence.fallShield = setmetatable({}, { __mode = "k" })
Fence.fallShieldMaxMs = 4000
Fence.hitWindowUntilMs = setmetatable({}, { __mode = "k" })
Fence.nextStaggerAtMs = setmetatable({}, { __mode = "k" })

Fence.nativeStatePolicy = {
    lunge = "leave",
    turnalerted = "leave",
    ["face-target"] = "leave",
    attack = "leave",
    attackvehicle = "leave",
    eatbody = "leave",
    thump = "leave",
}

function Fence.leaveNativeState(shell, state)
    if Fence.nativeStatePolicy[state] ~= "leave" or ZombieIdleState == nil then return false end
    local left = pcall(function()
        shell:changeState(ZombieIdleState.instance())
        shell:setTarget(nil)
        shell:clearAggroList()
    end)
    if not left then return false end
    Fence.metrics.nativeStateExits = (Fence.metrics.nativeStateExits or 0) + 1
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled == true and type(blackBox.note) == "function" then
        pcall(blackBox.note, shell, "native_state_exit", state)
    end
    return true
end

local GROUND_STATE_PREFIXES = {
    "onground", "falldown", "getdown", "getup", "knockeddown",
    "staggerback-knockeddown", "hitreaction-onfloor", "hitreaction-gettingup",
    "vehiclecollision-falldown", "vehiclecollision-onground",
    "sitonground", "fakedead",
}

local function isGroundStateName(state)
    if state == nil or state == "" then return false end
    local known = Fence.groundMemo[state]
    if known ~= nil then return known end
    local grounded = false
    for index = 1, #GROUND_STATE_PREFIXES do
        local prefix = GROUND_STATE_PREFIXES[index]
        if string.sub(state, 1, #prefix) == prefix then grounded = true; break end
    end
    if Fence.groundMemoSize >= (Fence.memoLimit or 256) then
        Fence.groundMemo, Fence.groundMemoSize = {}, 0
    end
    Fence.groundMemo[state] = grounded
    Fence.groundMemoSize = Fence.groundMemoSize + 1
    return grounded
end

local function actionState(shell)

    if shell == nil or shell.getActionStateName == nil then return "" end
    local ok, state = pcall(shell.getActionStateName, shell)
    if not ok then return "" end
    if state ~= nil then
        local known = Fence.lowerMemo[state]
        if known ~= nil then return known end
    end
    local lowered = string.lower(tostring(state or ""))
    if state ~= nil then
        if Fence.lowerMemoSize >= (Fence.memoLimit or 256) then
            Fence.lowerMemo, Fence.lowerMemoSize = {}, 0
        end
        Fence.lowerMemo[state] = lowered
        Fence.lowerMemoSize = Fence.lowerMemoSize + 1
    end
    return lowered
end

function Fence.groundFlags(shell)
    return shell:isProne() == true or shell:isOnFloor() == true
        or shell:isKnockedDown() == true or shell:isCrawling() == true
        or shell:isBumpFall() == true
        or shell:getVariableBoolean("bOnFloor") == true
        or Fence.ragdollFlag(shell)
end

local function isGrounded(shell, suppliedState)
    local state = suppliedState or actionState(shell)
    if isGroundStateName(state) then return true end
    if Fence.isRagdollState(state) then return true end
    local ok, grounded = pcall(Fence.groundFlags, shell)
    return ok and grounded == true
end

function Fence.grounded(shell)
    if shell == nil then return false end
    local state = actionState(shell)
    if string.sub(state, 1, 11) == "sitonground" then return false end
    if type(shell.getBumpType) == "function" and string.sub(tostring(shell:getBumpType() or ""), 1, 8) == "ALifeSit" then
        return false
    end
    return isGrounded(shell, state) == true
end

function Fence.airborneRagdoll(shell, state)
    return not isGroundStateName(state) and Fence.ragdolling(shell, state)
end

local function releaseGroundPath(shell)
    pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior ~= nil then
            behavior:cancel()
            pcall(function() behavior:reset() end)
        end
        pcall(function() shell:setPath2(nil) end)
        pcall(function() shell:setMoving(false) end)
        pcall(function() shell:setVariable("bMoving", false) end)
        pcall(function() shell:setVariable("bPathfind", false) end)
        shell:setTarget(nil)
        shell:clearAggroList()
        local data = shell:getModData()
        if type(data) == "table" then data.ProjectALifePathActive = nil end
    end)
end

local function beginGetUp(shell, suppliedNow)
    local state = actionState(shell)

    if string.sub(state, 1, 5) == "getup"
            or string.sub(state, 1, 11) == "hitreaction" then return end
    local now = tonumber(suppliedNow) or nowMs()
    releaseGroundPath(shell)
    pcall(function()
        shell:setUseless(true)
        shell:setHitReaction("")
        pcall(function() shell:setStaggerBack(false) end)
        shell:setBumpFall(false)
        pcall(function() shell:setBumpStaggered(false) end)
        shell:setBumpDone(true)
        shell:setBumpType("")
        shell:setBumpFallType("")

        pcall(function() shell:setCrawler(false) end)
        pcall(function() shell:setBecomeCrawler(false) end)
        pcall(function() shell:setCanWalk(true) end)
        pcall(function() shell:setFakeDead(false) end)
        pcall(function() shell:setForceFakeDead(false) end)

        shell:setReanimateTimer(0)
    end)
    pcall(function()
        local data = shell:getModData()
        if type(data) == "table" then
            data.ProjectALifeGroundRecoveryUntilMs = now + Fence.groundGetUpMs
            data.ProjectALifeStaggerUntilMs = now + Fence.groundGetUpMs
        end
    end)

end

function Fence.authoritative()
    if type(isServer) == "function" and isServer() then return true end
    if type(isClient) == "function" and isClient() then return false end

    return true
end

local function spectatorSide()
    return type(isClient) == "function" and isClient()
        and (type(isServer) ~= "function" or not isServer())
end

function Fence.raise(shell)
    shell:setUseless(true)
    shell:setNoTeeth(true)
end

function Fence.writeAttackerFence(shell, suppliedNow)
        local data = shell:getModData()
        local openUntil = type(data) == "table" and tonumber(data.ProjectALifeBiteUntilMs) or nil
        if openUntil ~= nil and (suppliedNow or nowMs()) < openUntil then return end
        shell:setZombiesDontAttack(true)
end

function Fence.refuseNativeAttackers(shell, suppliedNow)
    pcall(Fence.writeAttackerFence, shell, suppliedNow)
end

Fence.fenced = setmetatable({}, { __mode = "k" })
Fence.restoredBodies = {}

function Fence.lower(shell, reason)
    if shell == nil or Fence.fenced[shell] == nil then return false end
    if Fence.owned[shell] == true then return false end
    Fence.fenced[shell] = nil
    pcall(shell.setUseless, shell, false)
    pcall(shell.setNoTeeth, shell, false)
    pcall(shell.setZombiesDontAttack, shell, false)
    Fence.metrics.restored = (Fence.metrics.restored or 0) + 1
    local key = tostring(reason or "unspecified")
    Fence.restoredBodies[key] = (Fence.restoredBodies[key] or 0) + 1
    return true
end

function Fence.pushingThroughFoliage(shell)
    local now = nowMs()
    if now < (Fence.nextTerrainSweepAtMs[shell] or 0) then
        return Fence.terrainSlow[shell] == true
    end
    Fence.nextTerrainSweepAtMs[shell] = now + Fence.terrainSweepIntervalMs
    local slow = false
    pcall(function()
        local square = shell:getSquare()
        local foliage = ProjectALife.Foliage
        slow = square ~= nil and foliage ~= nil and foliage.on(square) == true
    end)
    Fence.terrainSlow[shell] = slow
    return slow
end

function Fence.strideRhythm(data)
    local rhythm = tonumber(data.ProjectALifeGaitJitter)
    if rhythm ~= nil then return rhythm end
    local id = tostring(data.ProjectALifeUID or "")
    local seed = 0
    for index = 1, #id do
        seed = (seed * 31 + string.byte(id, index)) % 997
    end
    rhythm = 0.94 + (seed % 13) / 100
    data.ProjectALifeGaitJitter = rhythm
    return rhythm
end

Fence.humanWalkType = "ALifeHuman"

function Fence.gaitTuning()
    local behavior = ProjectALife.BehaviorSettings
    local gait = type(behavior) == "table" and type(behavior.gait) == "table" and behavior.gait or {}
    local health = ProjectALife.Health
    local dressed = health ~= nil and type(health.settings) == "table"
        and tonumber(health.settings.healToFraction) or nil
    return tonumber(gait.thicketSpeed) or 0.75, dressed or 0.65, tonumber(gait.limpTempo) or 0.66
end

function Fence.gaitTempo(shell)
    local _, woundedBelow, limp = Fence.gaitTuning()
    local okHurt, hurt = pcall(Fence.woundedUnder, shell, woundedBelow)
    hurt = okHurt and hurt == true
    local walkSpeed = hurt and 0.78 or 1.02
    local data = shell ~= nil and shell.getModData ~= nil and shell:getModData() or nil
    if type(data) == "table" then
        walkSpeed = walkSpeed * Fence.strideRhythm(data)
        if data.ProjectALifeSweepSlow == true then
            walkSpeed = walkSpeed * (tonumber(data.ProjectALifeSweepTempo) or 0.72)
        end
        local chill = tonumber(data.ProjectALifeColdPace)
        if chill ~= nil then walkSpeed = walkSpeed * chill end
        if data.ProjectALifeWoundLeg == true then
            walkSpeed = walkSpeed * limp
        elseif data.ProjectALifeSneakActive == true then
            walkSpeed = walkSpeed * 0.85
        end
    end
    return walkSpeed, hurt and 0.60 or 0.78, hurt and 0.66 or 0.84
end

function Fence.woundedUnder(shell, woundedBelow)
    local ceiling = ProjectALife.ShellSimulation.maximumFor(shell)
    return shell:getHealth() < woundedBelow * ceiling
end

Fence.gaitWritten = setmetatable({}, { __mode = "k" })

function Fence.writeGaitTempo(shell, walk, run, sprint)
    shell:SetVariable("ALifeWalkSpeed", tostring(walk))
    shell:SetVariable("ALifeRunSpeed", tostring(run))
    shell:SetVariable("ALifeSprintSpeed", tostring(sprint))
end

function Fence.writeGaitFields(shell, speedMod)
    shell:setSpeedMod(speedMod)
    shell:setWalkType(Fence.humanWalkType)
end

Fence.rustleSound = "Bushes"
Fence.rustleGapMs = 5000
Fence.rustleAt = setmetatable({}, { __mode = "k" })

function Fence.holdHumanGait(shell, slow)
    local thicket = Fence.gaitTuning()

    local okTempo, walk, run, sprint = pcall(Fence.gaitTempo, shell)
    if okTempo then
        local now = nowMs()
        local last = Fence.gaitWritten[shell]
        if last == nil or last.walk ~= walk or last.run ~= run or last.sprint ~= sprint
                or now >= last.untilMs or now < last.atMs then
            if pcall(Fence.writeGaitTempo, shell, walk, run, sprint) then
                if last == nil then
                    last = {}
                    Fence.gaitWritten[shell] = last
                end
                last.walk, last.run, last.sprint = walk, run, sprint
                last.atMs, last.untilMs = now, now + Fence.paceRefreshIntervalMs
            end
        end
    end
    pcall(Fence.writeGaitFields, shell, slow and thicket or 1)
    if slow and type(ZombRand) == "function" and ZombRand(90) == 0
            and shell ~= nil and shell.playSound ~= nil then
        local now = nowMs()
        local last = Fence.rustleAt[shell]
        if last == nil or now < last or now - last >= Fence.rustleGapMs then
            Fence.rustleAt[shell] = now
            pcall(shell.playSound, shell, Fence.rustleSound)
        end
    end
end

function Fence.authorityFor(shell)
    local executor = ProjectALife.Executor
    if executor ~= nil and type(executor.authorityFor) == "function" then
        local answer = executor.authorityFor(shell)
        if answer ~= nil then return answer == true end
    end
    return Fence.authoritative()
end

function Fence.clearCorpsePose(shell)
    if shell:isFakeDead() == true then
        shell:setFakeDead(false)
        shell:setForceFakeDead(false)
        shell:setOnFloor(true)
    end
    local reaction = tostring(shell:getHitReaction() or "")
    if reaction ~= "" and string.find(reaction, "Death", 1, true)
            and string.sub(actionState(shell), 1, 11) ~= "hitreaction" then
        shell:setHitReaction("")
    end
end

function Fence.clearFeedingTargets(shell)
    if shell == nil or type(shell.getModData) ~= "function" or type(shell.isDead) ~= "function" then return false end
    local dataOk, data = pcall(shell.getModData, shell)
    if not dataOk or type(data) ~= "table" or data.ProjectALifeCorpseOf ~= nil or not Fence.marksOwned(data) then return false end
    local deadOk, dead = pcall(shell.isDead, shell)
    if not deadOk or dead == true then return false end
    if type(shell.isReanimatedForGrappleOnly) == "function" then
        local grappleOk, grapple = pcall(shell.isReanimatedForGrappleOnly, shell)
        if not grappleOk or grapple == true then return false end
    end
    if type(shell.getTarget) == "function" and type(shell.setTarget) == "function" then
        local targetOk, target = pcall(shell.getTarget, shell)
        if targetOk and target ~= nil then
            local corpse = false
            if type(instanceof) == "function" then
                local kindOk, isCorpse = pcall(instanceof, target, "IsoDeadBody")
                corpse = kindOk and isCorpse == true
            end
            if not corpse and type(target.isDead) == "function" then
                local targetDeadOk, targetDead = pcall(target.isDead, target)
                corpse = targetDeadOk and targetDead == true
            end
            if corpse then pcall(shell.setTarget, shell, nil) end
        end
    end
    if type(shell.setEatBodyTarget) == "function" then pcall(shell.setEatBodyTarget, shell, nil, false) end
    if type(shell.setBodyToEat) == "function" then pcall(shell.setBodyToEat, shell, nil) end
    if type(shell.setForceEatingAnimation) == "function" then pcall(shell.setForceEatingAnimation, shell, false) end
    return true
end

function Fence.clearNativeTargets(shell, leftNative, liveActionState)
    if not leftNative and liveActionState ~= "lunge" and type(shell.setTarget) == "function" then shell:setTarget(nil) end
    Fence.clearFeedingTargets(shell)
end

function Fence.expireStagger(shell)
    local data = shell:getModData()
    if type(data) ~= "table" then return end
    local untilMs = tonumber(data.ProjectALifeStaggerUntilMs)
    if untilMs == nil then return end
    local animations = ProjectALife.Animations
    if nowMs() >= untilMs then
        data.ProjectALifeStaggerUntilMs = nil
        if animations ~= nil and animations.current ~= nil
                and animations.current[shell] == "hit_react"
                and type(animations.clear) == "function" then
            animations.clear(shell)
        end
    elseif animations ~= nil and animations.current ~= nil
            and animations.current[shell] ~= "hit_react" then
        data.ProjectALifeStaggerUntilMs = nil
    end
end

function Fence.apply(shell)
    if shell == nil then return false, "shell_required" end
    local deadOk, dead = pcall(shell.isDead, shell)
    if deadOk and dead == true then

        pcall(Fence.enforceDeath, shell)
        return true
    end

    if Fence.roomSweptAt[shell] ~= Fence.roomFrame and shell.getCurrentSquare ~= nil then
        Fence.repairRoom(shell:getCurrentSquare())
    end
    if shell ~= nil and ProjectALife.Campfires ~= nil
            and type(ProjectALife.Campfires.protect) == "function" then ProjectALife.Campfires.protect(shell) end

    if (ProjectALife.Executor and ProjectALife.Executor.serverDelegates())
            or (spectatorSide() and not (ProjectALife.ShellSimulation
                and ProjectALife.ShellSimulation.isOwner(shell))) then
        Fence.applyCosmetic(shell)
        return true
    end

    local recoveryState = actionState(shell)
    if Fence.reactionRecovery[shell] then
        if recoveryState == "staggerback" and not isGrounded(shell, recoveryState) then
            Fence.exitStandingReaction(shell)
        elseif string.sub(recoveryState, 1, 11) ~= "hitreaction" then
            Fence.reactionRecovery[shell] = nil
        end
    end

    local flagsOk, flagsError = pcall(Fence.raise, shell)
    Fence.refuseNativeAttackers(shell)
    Fence.holdHumanGait(shell, Fence.pushingThroughFoliage(shell))

    if not isGrounded(shell, recoveryState) then
        pcall(shell.setBumpFall, shell, false)
    end

    pcall(Fence.clearCorpsePose, shell)

    local liveActionState = recoveryState

    local leftNative = Fence.leaveNativeState(shell, liveActionState)

    local frameState = liveActionState
    if leftNative then frameState = actionState(shell) end
    local cleanupOk, cleanupError = pcall(Fence.clearNativeTargets, shell, leftNative, liveActionState)

    pcall(Fence.expireStagger, shell)

    local frameNow = nowMs()
    local paceOk, current = pcall(shell.getModData, shell)
    if frameNow < (Fence.hitWindowUntilMs[shell] or 0) then

        if Fence.hitAudioPending[shell] == true then
            silenceNativeVoice(shell, true)
            Fence.hitAudioPending[shell] = nil
        end
        pcall(Fence.clearHitResidue, shell, liveActionState, frameState)
    end

    if not isGrounded(shell, frameState) and ZombieIdleState ~= nil then
        local staggerUntilMs
        if paceOk and type(current) == "table" then staggerUntilMs = current.ProjectALifeStaggerUntilMs end

        local foreignBump = false
        local bumpOk, bump = pcall(shell.getBumpType, shell)
        if bumpOk then
            bump = tostring(bump or "")
            foreignBump = string.sub(bump, 1, 5) ~= "ALife"
        end
        if Fence.cutsReaction(liveActionState, staggerUntilMs, frameNow, foreignBump) then
            local cut = Fence.exitStandingReaction(shell)
            if cut then Fence.metrics.reactionsCut = (Fence.metrics.reactionsCut or 0) + 1 end
        end
    end

    silenceNativeVoice(shell)

    if liveActionState == "climbfence" or liveActionState == "climbwindow" then
        silenceTraversalAudio(shell)
    end

    local pace = nil
    if paceOk then ProjectALife.Animations.migrateHeldBump(shell, current) end
    local paceNow = frameNow

    local restamp = false
    if paceOk and type(current) == "table"
            and paceNow >= (Fence.nextPaceRefreshAtMs[shell] or 0) then
        Fence.nextPaceRefreshAtMs[shell] = paceNow + Fence.paceRefreshIntervalMs
        restamp = true

        pcall(Fence.releaseOrphanBump, shell)

        pcall(Fence.releaseStaleReload, shell, paceNow)
        pcall(Fence.refreshMovementPace, shell)
    end

    if restamp and current.ProjectALifeActor == true then
        pcall(shell.SetVariable, shell, "ALifeActor", "true")
    end

    if restamp and current.ProjectALifeActor == true and Fence.authorityFor(shell) then
        pcall(Fence.repairForward, shell)
    end
    if paceOk and type(current) == "table" then pace = current.ProjectALifePace end

    if restamp then
        local healthSystem = ProjectALife.Health
        if Fence.authorityFor(shell) and healthSystem ~= nil then
            pcall(healthSystem.tick, shell, current, paceNow)
        end
        local injurySystem = ProjectALife.Injury
        if injurySystem ~= nil and Fence.authorityFor(shell) then
            pcall(injurySystem.beat, shell, current, paceNow)
        end

        pcall(Fence.staleCombatBeat, shell, current, paceNow)

        if current.ProjectALifePathActive == true
                and not (type(isServer) == "function" and isServer()) then
            pcall(Fence.clearArrivedPath, shell, current)
        end
        local gunner = ProjectALife.ModuleGunner
        if Fence.authorityFor(shell) and gunner ~= nil then
            pcall(gunner.tick, shell, current, paceNow)
        end
        local roomSweep = ProjectALife.RoomSweep
        if Fence.authorityFor(shell) and roomSweep ~= nil then
            pcall(roomSweep.tick, shell, current, paceNow)
        end

        local blackBox = ProjectALife.BlackBox
        if blackBox ~= nil and type(blackBox.recoverPath) == "function" then
            pcall(blackBox.recoverPath, shell, current, paceNow)
        end
        if blackBox ~= nil and blackBox.enabled then
            pcall(blackBox.tick, shell, current, paceNow)
        end

        pcall(Fence.enforceDeath, shell)

        pcall(Fence.staggerSelfHeal, shell, current, paceNow, frameState)

        pcall(Fence.fallShieldBeat, shell, paceNow, frameState)

        pcall(Fence.dropAimFlag, shell)

        pcall(Fence.playerArrival, shell, current, paceNow, frameState)
        pcall(Fence.crowdArrival, shell, current, paceNow, frameState)
        pcall(Fence.crowdNudge, shell, current, paceNow, paceOk, frameState)

        pcall(Fence.climbSelfHeal, shell, current, paceNow, blackBox, frameState)

        local leader = ProjectALife.ModuleLeader
        if Fence.authorityFor(shell) and leader ~= nil and current.ProjectALifeConduct == "leader" then
            pcall(leader.tick, shell, current, paceNow)
        end

        local stealthSystem = ProjectALife.Stealth
        if Fence.authorityFor(shell) and stealthSystem ~= nil then
            local sneaking = current.ProjectALifeWoundLeg ~= true
                and stealthSystem.stanceActive(current)
            pcall(shell.SetVariable, shell, "ALifeSneak", sneaking and "true" or "false")
            current.ProjectALifeSneakActive = sneaking or nil
        end

        pcall(Fence.faceHeardSound, shell, current, paceNow)
        if healthSystem ~= nil then
            local limping = current.ProjectALifeWoundLeg == true
            if limping and (pace == "run" or pace == "sprint") then
                pace = "walk"
                current.ProjectALifePace = "walk"
                current.ProjectALifeSprintUntilMs = nil
            end

            local healthSystem = ProjectALife.Health
            local armedLimp = healthSystem ~= nil and type(healthSystem.settings) == "table"
                and healthSystem.settings.limpWithWeapon == true
            local limpClip = limping and (armedLimp or current.ProjectALifeWeaponHeld ~= true)
            pcall(shell.SetVariable, shell, "ALifeLimp", limpClip and "true" or "false")
        end
    end
    if restamp and (pace == "run" or pace == "sprint" or pace == "walk") then
        pcall(shell.SetVariable, shell, "ALifePace", pace)
    end

    if paceOk and type(current) == "table" then
        pcall(Fence.aimedMovement, shell, current, liveActionState)
    end

    if restamp then
        pcall(Fence.restampWeaponPose, shell, current)
    end

    if paceOk and type(current) == "table" then
        local held = current.ProjectALifeHeldBump

        if held ~= nil and held ~= "" and current.ProjectALifePathActive ~= true
                and current.ProjectALifeHeldAct == nil then
            local liveOk, live = pcall(shell.getBumpType, shell)

            if liveOk and live ~= held and not isGrounded(shell, frameState) then
                pcall(shell.setBumpType, shell, held)
            end
        end
        if current.ProjectALifeInjuryAnchorX ~= nil then
            local pinning = ProjectALife.Injury
            if pinning ~= nil and type(pinning.pin) == "function" then pcall(pinning.pin, shell, current) end
        end
    end

    pcall(Fence.nativeWatchdog, shell, frameState)

    Fence.metrics.updates = Fence.metrics.updates + 1
    if flagsOk and cleanupOk then return true end

    Fence.metrics.failures = Fence.metrics.failures + 1
    Fence.metrics.lastError = tostring(flagsOk and cleanupError or flagsError)
    return false, Fence.metrics.lastError
end

function Fence.clearHitResidue(shell, liveActionState, frameState)

    if string.sub(liveActionState, 1, 11) ~= "hitreaction" then
        shell:setHitReaction("")
    end
    pcall(shell.setStaggerBack, shell, false)

    if not isGrounded(shell, frameState) then
        shell:setKnockedDown(false)
        shell:setOnFloor(false)
        shell:setBumpFall(false)
    else
        shell:setUseless(true)
    end
    local bump = tostring(shell:getBumpType() or "")

    if bump ~= "" and string.sub(bump, 1, 5) ~= "ALife" then
        shell:setBumpDone(true)
        shell:setBumpType("")
    end
end

function Fence.releaseOrphanBump(shell)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.current) ~= "table"
            or animations.current[shell] ~= nil then return end
    local bump = tostring(shell:getBumpType() or "")
    if bump ~= "" and string.sub(bump, 1, 5) == "ALife"
            and not shell:isBumpDone() then
        shell:setBumpDone(true)
        shell:setBumpType("")
    end
end

function Fence.releaseStaleReload(shell, paceNow)
    local bump = tostring(shell:getBumpType() or "")
    if bump == "" or (string.find(bump, "ALifeReload", 1, true) ~= 1
            and bump ~= "ALifeLongarmRefill") or shell:isBumpDone() then
        Fence.reloadBumpSinceMs[shell] = nil
        return
    end
    local since = Fence.reloadBumpSinceMs[shell]
    if since == nil then Fence.reloadBumpSinceMs[shell] = paceNow return end
    if not Fence.reloadBumpOverdue(since, paceNow, Fence.reloadBumpOverdueMs) then return end
    Fence.reloadBumpSinceMs[shell] = nil
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.clear) == "function" then
        animations.clear(shell)
    else
        shell:setBumpDone(true)
        shell:setBumpType("")
    end
end

function Fence.refreshMovementPace(shell)
    local movement = ProjectALife.Movement
    if Fence.authorityFor(shell) and movement ~= nil and type(movement.refreshPace) == "function" then
        movement.refreshPace(shell)
    end
end

function Fence.repairForward(shell)
    local forward = shell:getForwardDirection()
    local fx, fy = tonumber(forward:getX()) or 0, tonumber(forward:getY()) or 0
    if fx * fx + fy * fy >= 0.000001 then return end
    local facing = Fence.aimFacing[shell]
    local nx, ny = 0, 1
    if type(facing) == "table" and (facing.x * facing.x + facing.y * facing.y) > 0.5 then
        nx, ny = facing.x, facing.y
    end
    if shell.setTargetAndCurrentDirection ~= nil then
        shell:setTargetAndCurrentDirection(nx, ny)
    end
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled == true then blackBox.note(shell, "facing-fix", "zero vector") end
end

function Fence.noteStalePhase(shell, stalePhase, released)
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled == true then
        blackBox.note(shell, "self-heal", "stale phase " .. stalePhase .. (released and " +path" or ""))
    end
end

Fence.stalePhaseMs = 3000
function Fence.staleCombatBeat(shell, current, paceNow)
    local stalePhase = tostring(current.ProjectALifeCombatPhase or "idle")
    if stalePhase == "idle" or stalePhase == "" or stalePhase == "aborted" then return false end
    local pulse = tonumber(current.ProjectALifeCombatPulseMs)
    if pulse ~= nil and paceNow - pulse <= Fence.stalePhaseMs then return false end

    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.inClip) == "function" and traversal.inClip(shell) == true then
        return false
    end
    current.ProjectALifeCombatPhase = "idle"
    current.ProjectALifeAimWalk = false
    pcall(Fence.dropAimFlag, shell)

    local released = Fence.releaseOrphanCombatPath(shell, current)
    pcall(Fence.noteStalePhase, shell, stalePhase, released)
    return true
end

function Fence.releaseOrphanCombatPath(shell, current)
    if current.ProjectALifePathActive ~= true then return false end
    local combat = ProjectALife.Combat
    local requests = combat ~= nil and type(combat.pathRequests) == "table" and combat.pathRequests or nil
    local request = requests ~= nil and requests[shell] or nil
    if type(request) ~= "table" or shell.getPathFindBehavior2 == nil then return false end
    local behavior = shell:getPathFindBehavior2()
    if behavior == nil or behavior.getTargetX == nil or behavior.getTargetY == nil then return false end
    local rx, ry = tonumber(request.x), tonumber(request.y)
    if rx == nil or ry == nil then return false end
    local dx, dy = behavior:getTargetX() - rx, behavior:getTargetY() - ry
    if dx * dx + dy * dy > 1 then return false end
    requests[shell] = nil
    local movement = ProjectALife.Movement
    if movement ~= nil and type(movement.stop) == "function" then
        movement.stop(shell)
    else
        releaseGroundPath(shell)
    end
    current.ProjectALifePathActive = nil
    current.ProjectALifeNudgeX, current.ProjectALifeNudgeY, current.ProjectALifeNudgeSinceMs = nil, nil, nil
    Fence.metrics.orphanPathsReleased = (Fence.metrics.orphanPathsReleased or 0) + 1
    return true
end

Fence.crowdArrivalRadius = 1.5
Fence.crowdArrivalMs = 600
Fence.crowdTouch = 0.8
Fence.crowdArrivedLeaseMs = 2000
function Fence.crowdArrival(shell, current, paceNow, frameState)
    if current.ProjectALifePathActive ~= true then
        current.ProjectALifeCrowdGoalDist, current.ProjectALifeCrowdSinceMs = nil, nil
        return false
    end
    local phase = tostring(current.ProjectALifeCombatPhase or "idle")
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted" then return false end
    if shell.getPathFindBehavior2 == nil then return false end
    local state = frameState or actionState(shell)
    if isGrounded(shell, state) or state == "falling" or string.sub(state, 1, 5) == "climb" then return false end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.isBusy) == "function" and traversal.isBusy(shell) == true then
        return false
    end
    local behavior = shell:getPathFindBehavior2()
    if behavior == nil or behavior.getTargetX == nil or behavior.getTargetY == nil then return false end
    local gx, gy = tonumber(behavior:getTargetX()), tonumber(behavior:getTargetY())
    if gx == nil or gy == nil then return false end
    local sx, sy = shell:getX(), shell:getY()
    local distance = math.sqrt((gx - sx) * (gx - sx) + (gy - sy) * (gy - sy))
    if distance > Fence.crowdArrivalRadius then
        current.ProjectALifeCrowdGoalDist, current.ProjectALifeCrowdSinceMs = nil, nil
        return false
    end
    local mark = tonumber(current.ProjectALifeCrowdGoalDist)
    if mark == nil or distance < mark - 0.1 then
        current.ProjectALifeCrowdGoalDist, current.ProjectALifeCrowdSinceMs = distance, paceNow
        return false
    end
    if paceNow - (tonumber(current.ProjectALifeCrowdSinceMs) or paceNow) < Fence.crowdArrivalMs then return false end
    if not Fence.touchesBody(shell, sx, sy) then return false end
    current.ProjectALifeCrowdGoalDist, current.ProjectALifeCrowdSinceMs = nil, nil
    current.ProjectALifeCrowdArrivedAtMs = paceNow
    current.ProjectALifeCrowdArrivedX, current.ProjectALifeCrowdArrivedY = gx, gy
    local movement = ProjectALife.Movement
    if movement ~= nil and type(movement.stop) == "function" then
        movement.stop(shell)
    else
        releaseGroundPath(shell)
    end
    current.ProjectALifePathActive = nil
    Fence.metrics.crowdArrivals = (Fence.metrics.crowdArrivals or 0) + 1
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled == true and type(blackBox.note) == "function" then
        blackBox.note(shell, "crowd-arrival", string.format("goal=%.1f,%.1f dist=%.2f", gx, gy, distance))
    end
    return true
end

function Fence.touchesBody(shell, sx, sy)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return false end
    local z, reach = shell:getZ(), Fence.crowdTouch * Fence.crowdTouch
    local fx, fy = math.floor(sx), math.floor(sy)
    for ox = -1, 1 do
        for oy = -1, 1 do
            local square = cell:getGridSquare(fx + ox, fy + oy, z)
            local moving = square ~= nil and square:getMovingObjects() or nil
            if moving ~= nil then
                for index = 0, moving:size() - 1 do
                    local body = moving:get(index)
                    if body ~= nil and body ~= shell and body.getX ~= nil and body.isDead ~= nil
                            and body:isDead() ~= true then
                        local dx, dy = body:getX() - sx, body:getY() - sy
                        if dx * dx + dy * dy <= reach and Fence.isActorBody(body) then return true end
                    end
                end
            end
        end
    end
    return false
end

Fence.playerGoalReach = 0.9
Fence.playerStandOff = 1.6
Fence.playerRetryMs = 20000
function Fence.playerArrival(shell, current, paceNow, frameState)
    if current.ProjectALifePathActive ~= true then return false end
    local phase = tostring(current.ProjectALifeCombatPhase or "idle")
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted" then return false end
    if shell.getPathFindBehavior2 == nil or not Fence.drivesBody(shell) then return false end
    local state = frameState or actionState(shell)
    if isGrounded(shell, state) or state == "falling" or string.sub(state, 1, 5) == "climb" then return false end
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.isBusy) == "function" and traversal.isBusy(shell) == true then
        return false
    end
    local behavior = shell:getPathFindBehavior2()
    if behavior == nil or behavior.getTargetX == nil or behavior.getTargetY == nil then return false end
    local gx, gy = tonumber(behavior:getTargetX()), tonumber(behavior:getTargetY())
    if gx == nil or gy == nil then return false end
    if Fence.playerStopRetried(current, gx, gy, paceNow) then return false end
    local people = Fence.samplePeople(paceNow)
    if people.count == 0 then return false end
    local sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
    local reach, standOff = Fence.playerGoalReach * Fence.playerGoalReach, Fence.playerStandOff * Fence.playerStandOff
    for index = 1, people.count do
        local person = people.list[index]
        if math.abs(person.z - sz) <= 0.3 then
            local gdx, gdy = gx - person.x, gy - person.y
            local dx, dy = sx - person.x, sy - person.y
            if gdx * gdx + gdy * gdy <= reach and dx * dx + dy * dy <= standOff then
                current.ProjectALifeCrowdGoalDist, current.ProjectALifeCrowdSinceMs = nil, nil
                current.ProjectALifeCrowdArrivedAtMs = paceNow
                current.ProjectALifeCrowdArrivedX, current.ProjectALifeCrowdArrivedY = gx, gy
                current.ProjectALifePlayerStopX, current.ProjectALifePlayerStopY = gx, gy
                current.ProjectALifePlayerStopAtMs = paceNow
                local movement = ProjectALife.Movement
                if movement ~= nil and type(movement.stop) == "function" then
                    movement.stop(shell)
                else
                    releaseGroundPath(shell)
                end
                current.ProjectALifePathActive = nil
                Fence.metrics.playerArrivals = (Fence.metrics.playerArrivals or 0) + 1
                local blackBox = ProjectALife.BlackBox
                if blackBox ~= nil and blackBox.enabled == true and type(blackBox.note) == "function" then
                    blackBox.note(shell, "player-arrival", string.format("goal=%.1f,%.1f", gx, gy))
                end
                return true
            end
        end
    end
    return false
end

function Fence.playerStopRetried(current, gx, gy, now)
    local at = tonumber(current.ProjectALifePlayerStopAtMs)
    if at == nil then return false end
    local lx, ly = tonumber(current.ProjectALifePlayerStopX), tonumber(current.ProjectALifePlayerStopY)
    if lx == nil or ly == nil or now < at or now - at >= Fence.playerRetryMs then
        current.ProjectALifePlayerStopX, current.ProjectALifePlayerStopY = nil, nil
        current.ProjectALifePlayerStopAtMs = nil
        return false
    end
    local dx, dy = gx - lx, gy - ly
    if dx * dx + dy * dy > 1 then return false end
    Fence.metrics.playerStopsRetried = (Fence.metrics.playerStopsRetried or 0) + 1
    return true
end

function Fence.isActorBody(body)
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return false end
    if type(body.getModData) ~= "function" then return false end
    local data = body:getModData()
    return type(data) == "table" and data.ProjectALifeOwned == true
end

function Fence.crowdArrived(shell, target)
    if shell == nil or type(target) ~= "table" or shell.getModData == nil then return false end
    if type(shell.hasModData) == "function" and shell:hasModData() ~= true then return false end
    local data = shell:getModData()
    if type(data) ~= "table" then return false end
    local at = tonumber(data.ProjectALifeCrowdArrivedAtMs)
    if at == nil or nowMs() - at > Fence.crowdArrivedLeaseMs then return false end
    local gx, gy = tonumber(data.ProjectALifeCrowdArrivedX), tonumber(data.ProjectALifeCrowdArrivedY)
    local tx, ty = tonumber(target.x), tonumber(target.y)
    if gx == nil or gy == nil or tx == nil or ty == nil then return false end
    local dx, dy = gx - tx, gy - ty
    return dx * dx + dy * dy <= 1
end

function Fence.clearArrivedPath(shell, current)
    local behavior = shell:getPathFindBehavior2()
    if behavior ~= nil
            and shell:getVariableBoolean("bPathfind") ~= true
            and not shell:isMoving() then
        current.ProjectALifePathActive = nil
    end
end

function Fence.enforceDeath(shell)
    if shell:getHealth() > 0 then return end

    local killed
    if type(shell.isOnKillDone) == "function" then killed = shell:isOnKillDone() == true
    else killed = shell:isDead() == true end
    if killed or not Fence.authorityFor(shell) then return end

    local killer = shell
    local health = ProjectALife.Health
    if health ~= nil and type(health.lastAttacker) == "table" then
        killer = health.lastAttacker[shell] or shell
    end
    shell:Kill(killer)
end

function Fence.staggerSelfHeal(shell, current, paceNow, frameState)

    local state = frameState or actionState(shell)

    if Fence.ragdolling(shell, state) then
        Fence.ragdollBeat(shell, current, paceNow, state)
        return
    end
    current.ProjectALifeRagdollStaleSinceMs = nil

    local head = type(state) == "string" and string.sub(state, 1, 11) or ""
    local stuck = head == "staggerback" or head == "hitreaction"

    local orphanBump = false
    if not stuck and state == "bumped" then
        pcall(function()
            local animations = ProjectALife.Animations
            local preset = animations ~= nil
                and type(animations.current) == "table"
                and animations.current[shell] or nil

            if preset ~= nil and type(animations.actSet) == "table"
                    and animations.actSet[shell] ~= nil then preset = nil end
            orphanBump = Fence.bumpOrphaned(state, shell:getBumpType(), preset)
        end)
        stuck = orphanBump
    end
    if stuck then
        local since = tonumber(current.ProjectALifeStaggerStateSinceMs)
        local limit = state == "staggerback" and 2000 or 1200
        local completed = false
        pcall(function()
            completed = shell:isBumpDone() == true
                or string.lower(tostring(shell:GetVariable("BumpAnimFinished") or "")) == "true"
        end)
        if orphanBump then

            completed = false
            limit = 600
        end
        if since == nil then
            current.ProjectALifeStaggerStateSinceMs = paceNow
        elseif completed or paceNow - since > limit then
            if orphanBump then
                Fence.metrics.freezesCleared =
                    (Fence.metrics.freezesCleared or 0) + 1
            end
            current.ProjectALifeStaggerStateSinceMs = nil
            if not isGrounded(shell, state) then
                Fence.exitStandingReaction(shell)
                return
            end

            releaseGroundPath(shell)
        end
    else
        current.ProjectALifeStaggerStateSinceMs = nil
    end
end

Fence.ragdollStaleMs = 3000
function Fence.ragdollBeat(shell, current, paceNow, state)
    current.ProjectALifeStaggerStateSinceMs = nil
    if Fence.ragdollFlag(shell) or not Fence.isRagdollState(state) or isGroundStateName(state) then
        current.ProjectALifeRagdollStaleSinceMs = nil
        return false
    end
    local since = tonumber(current.ProjectALifeRagdollStaleSinceMs)
    if since == nil then
        current.ProjectALifeRagdollStaleSinceMs = paceNow
        return false
    end
    if paceNow - since < Fence.ragdollStaleMs then return false end
    current.ProjectALifeRagdollStaleSinceMs = nil
    if type(shell.setOnFloor) == "function" then
        shell:setOnFloor(true)
        Fence.metrics.ragdollLandings = (Fence.metrics.ragdollLandings or 0) + 1
    end
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled == true and type(blackBox.note) == "function" then
        blackBox.note(shell, "self-heal", "ragdoll landed " .. state)
    end
    return true
end

function Fence.fallShieldBeat(shell, paceNow, frameState)
    if not Fence.authorityFor(shell) then return end
    local state = frameState or actionState(shell)
    local falling = state == "falling" or string.sub(state, 1, 8) == "falldown"
    local shield = Fence.fallShield[shell]
    if falling and shield == nil then
        local health = Fence.realHealth(shell)
        if health <= 0 then return end
        Fence.fallShield[shell] = { health = health, sinceMs = paceNow }
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, health + Fence.playerFire.lift)
        else shell:setHealth(health + Fence.playerFire.lift) end
        Fence.metrics.fallsShielded = (Fence.metrics.fallsShielded or 0) + 1
    elseif shield ~= nil and (not falling or paceNow - shield.sinceMs > Fence.fallShieldMaxMs) then
        Fence.fallShield[shell] = nil
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, shield.health)
        else shell:setHealth(shield.health) end
    end
end

function Fence.crowdNudge(shell, current, paceNow, paceOk, frameState)
    if not Fence.drivesBody(shell) then return end
    local state = frameState or actionState(shell)
    if isGrounded(shell, state) or state == "falling"
            or string.sub(state, 1, 5) == "climb" then return end
    local animations = ProjectALife.Animations
    if animations and animations.blocksLocomotion
            and animations.blocksLocomotion(shell) then return end
    local square = shell:getCurrentSquare()
    if square == nil then return end
    local moving = square:getMovingObjects()
    if moving == nil then return end
    local sx, sy = shell:getX(), shell:getY()
    if paceOk and type(current) == "table"
            and Fence.laneYield(shell, current, square, sx, sy, paceNow) then return end

    if type(isClient) == "function" and isClient() == true
            and type(shell.isMoving) == "function" and shell:isMoving() == true then return end

    if paceOk and type(current) == "table" then
        if current.ProjectALifePathActive == true then
            local markX = tonumber(current.ProjectALifeNudgeX)
            local markY = tonumber(current.ProjectALifeNudgeY)
            local gapX, gapY = sx - (markX or sx), sy - (markY or sy)
            if markX == nil or markY == nil
                    or gapX * gapX + gapY * gapY > 0.01 then
                current.ProjectALifeNudgeX = sx
                current.ProjectALifeNudgeY = sy
                current.ProjectALifeNudgeSinceMs = paceNow
                return
            end
            local wedgedSince = tonumber(current.ProjectALifeNudgeSinceMs)
            if wedgedSince == nil then
                current.ProjectALifeNudgeSinceMs = paceNow
                return
            end
            if paceNow - wedgedSince < 600 then return end
        else
            current.ProjectALifeNudgeX = nil
            current.ProjectALifeNudgeY = nil
            current.ProjectALifeNudgeSinceMs = nil
        end
    end
    local pushX, pushY, crowd = 0, 0, 0
    for index = 0, moving:size() - 1 do
        local body = moving:get(index)
        if body ~= nil and body ~= shell and Fence.isActorBody(body) then
            local dx, dy = sx - body:getX(), sy - body:getY()
            local flat = dx * dx + dy * dy
            if flat < 0.49 then
                if flat < 0.0004 then

                    local angle = Fence.uidSeed(shell) * 0.0648
                    dx, dy = math.cos(angle), math.sin(angle)
                    flat = 1
                end
                local length = math.sqrt(flat)
                pushX = pushX + dx / length
                pushY = pushY + dy / length
                crowd = crowd + 1
            end
        end
    end
    if crowd == 0 then return end
    local length = math.sqrt(pushX * pushX + pushY * pushY)
    if length < 0.001 then return end
    local nx = sx + pushX / length * Fence.crowd.step
    local ny = sy + pushY / length * Fence.crowd.step
    if not Fence.stepClear(shell, square, sx, sy, nx, ny) then return end
    if not Fence.spendWrite(paceNow, Fence.crowd.laneReserve) then return end
    Fence.moveBody(shell, nx, ny)
    Fence.metrics.crowdNudges = (Fence.metrics.crowdNudges or 0) + 1
end

Fence.crowd = {
    step = 0.05,
    contact = 0.54,
    laneMargin = 0.30,
    lookaheadS = 1.3,
    runSpeed = 2.4,
    maxSpeed = 40,
    yieldStep = 0.12,
    yieldMax = 1.2,
    returnStep = 0.06,
    returnDelayMs = 1200,
    returnGiveUpMs = 15000,

    bodyGap = 0.60,

    budget = 12,
    laneReserve = 4,
    windowMs = 100,
    sampleMs = 100,
    pruneSamples = 50,

    rootedPoses = { sit_ground = true, sit_bench = true, fish_wait = true, fish_cast = true, fish_pull = true,
        play_guitar = true, sit_down = true, sit_up = true,
        search_low = true, search_mid = true, search_high = true, forage = true, farm_tend = true,
        board_up = true, surrender = true, stop = true,
        heal_bandage = true, heal_arm = true, heal_body = true, heal_head = true,
        ready_melee = true, ready_melee_2h = true, ready_spear = true, ready_handgun = true,
        ready_rifle = true, ready_kneel = true,
        drag_lie = true, drag_writhe = true, drag_body = true, drag_carry = true, warm_hands = true },
}
Fence.crowdWindow = { atMs = nil, writes = 0 }
Fence.people = { atMs = nil, sample = 0, prunedAt = 0, count = 0, runners = 0,
    list = {}, byPlayer = {}, stale = {} }

function Fence.drivesBody(shell)
    if type(isServer) == "function" and isServer() == true then return false end
    return Fence.authorityFor(shell) == true
end

function Fence.spendWrite(now, reserve)
    now = tonumber(now) or nowMs()
    local window, crowd = Fence.crowdWindow, Fence.crowd
    if window.atMs == nil or now < window.atMs or now - window.atMs >= crowd.windowMs then
        window.atMs, window.writes = now, 0
    end
    if window.writes >= crowd.budget - (tonumber(reserve) or 0) then
        Fence.metrics.crowdBudgetSkips = (Fence.metrics.crowdBudgetSkips or 0) + 1
        return false
    end
    window.writes = window.writes + 1
    return true
end

function Fence.stepClear(shell, square, sx, sy, nx, ny)
    local fx, fy, tx, ty = math.floor(sx), math.floor(sy), math.floor(nx), math.floor(ny)
    if fx == tx and fy == ty then return true end
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return false end
    local z = shell:getZ()
    local landing = cell:getGridSquare(tx, ty, z)
    if landing == nil then return false end
    if landing:isFree(false) ~= true then return false end
    local blocked = square:isBlockedTo(landing) == true or square:isHoppableTo(landing) == true
    if not blocked and fx ~= tx and fy ~= ty then
        local sideX = cell:getGridSquare(tx, fy, z)
        local sideY = cell:getGridSquare(fx, ty, z)
        blocked = sideX == nil or sideY == nil
            or square:isBlockedTo(sideX) == true or square:isBlockedTo(sideY) == true
            or sideX:isBlockedTo(landing) == true or sideY:isBlockedTo(landing) == true
            or square:isHoppableTo(sideX) == true or square:isHoppableTo(sideY) == true
            or sideX:isHoppableTo(landing) == true or sideY:isHoppableTo(landing) == true
    end
    return not blocked
end

function Fence.moveBody(shell, nx, ny)
    shell:setX(nx)
    shell:setY(ny)
    if type(shell.setNextX) == "function" then shell:setNextX(nx) end
    if type(shell.setNextY) == "function" then shell:setNextY(ny) end
end

function Fence.uidSeed(shell)
    local seed = 0
    local data = shell:getModData()
    local uid = type(data) == "table" and tostring(data.ProjectALifeUID or "") or ""
    for position = 1, #uid do
        seed = (seed * 31 + string.byte(uid, position)) % 97
    end
    return seed
end

function Fence.uidSide(current)
    local uid = tostring(current.ProjectALifeUID or "")
    if #uid > 0 and string.byte(uid, #uid) % 2 == 1 then return -1 end
    return 1
end

function Fence.samplePeople(now)
    local people, crowd = Fence.people, Fence.crowd
    now = tonumber(now) or nowMs()
    if people.atMs ~= nil and now >= people.atMs and now - people.atMs < crowd.sampleMs then return people end
    local dt = nil
    if people.atMs ~= nil and now > people.atMs and now - people.atMs <= 1000 then
        dt = (now - people.atMs) / 1000
    end
    people.atMs, people.count, people.runners = now, 0, 0
    people.sample = people.sample + 1
    if type(getSpecificPlayer) == "function" then
        for index = 0, 3 do Fence.notePerson(getSpecificPlayer(index), dt) end
    end

    if type(isClient) == "function" and isClient() == true and type(getOnlinePlayers) == "function" then
        local online = getOnlinePlayers()
        if online ~= nil and type(online.size) == "function" and type(online.get) == "function" then
            for index = 0, online:size() - 1 do Fence.notePerson(online:get(index), dt) end
        end
    end
    if people.sample - people.prunedAt >= crowd.pruneSamples then Fence.prunePeople() end
    return people
end

function Fence.notePerson(player, dt)
    if player == nil or type(player.getX) ~= "function" or type(player.getCurrentSquare) ~= "function" then return end
    local people = Fence.people
    local mark = people.byPlayer[player]
    if mark ~= nil and mark.sample == people.sample then return end
    if type(player.isDead) == "function" and player:isDead() == true then return end
    if type(player.isGhostMode) == "function" and player:isGhostMode() == true then return end
    if type(player.isInvisible) == "function" and player:isInvisible() == true then return end
    if type(player.getVehicle) == "function" and player:getVehicle() ~= nil then return end
    if player:getCurrentSquare() == nil then return end
    local x, y, z = player:getX(), player:getY(), player:getZ()
    local speed, ux, uy = 0, 0, 0
    if mark == nil then
        mark = {}
        people.byPlayer[player] = mark
    elseif dt ~= nil and mark.sample == people.sample - 1 then
        local dx, dy = x - mark.x, y - mark.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.0001 then speed, ux, uy = length / dt, dx / length, dy / length end
    end
    mark.x, mark.y, mark.sample = x, y, people.sample
    if speed > Fence.crowd.maxSpeed then speed = 0 end
    people.count = people.count + 1
    local entry = people.list[people.count]
    if entry == nil then
        entry = {}
        people.list[people.count] = entry
    end
    entry.x, entry.y, entry.z, entry.speed, entry.ux, entry.uy = x, y, z, speed, ux, uy
    entry.running = speed >= Fence.crowd.runSpeed
    if entry.running then people.runners = people.runners + 1 end
end

function Fence.prunePeople()
    local people = Fence.people
    local stale, count = people.stale, 0
    for player, mark in pairs(people.byPlayer) do
        if mark.sample < people.sample - Fence.crowd.pruneSamples then
            count = count + 1
            stale[count] = player
        end
    end
    for index = 1, count do
        people.byPlayer[stale[index]] = nil
        stale[index] = nil
    end
    people.prunedAt = people.sample
end

function Fence.personNear(people, x, y, z, skip)
    local reach = Fence.crowd.contact * Fence.crowd.contact
    for index = 1, people.count do
        local person = people.list[index]
        if person ~= skip and math.abs(person.z - z) <= 0.3 then
            local dx, dy = person.x - x, person.y - y
            if dx * dx + dy * dy < reach then return true end
        end
    end
    return false
end

function Fence.bodyNear(shell, nx, ny, sx, sy)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return nil end
    local gap, z = Fence.crowd.bodyGap, shell:getZ()
    local reach = gap * gap
    for x = math.floor(nx - gap), math.floor(nx + gap) do
        for y = math.floor(ny - gap), math.floor(ny + gap) do
            local square = cell:getGridSquare(x, y, z)
            local moving = square ~= nil and square:getMovingObjects() or nil
            if moving ~= nil then
                for index = 0, moving:size() - 1 do
                    local body = moving:get(index)
                    if body ~= nil and body ~= shell and type(body.isZombie) == "function" and body:isZombie() == true
                            and not (type(body.isDead) == "function" and body:isDead() == true) then
                        local bx, by = body:getX(), body:getY()
                        local dx, dy = bx - nx, by - ny
                        local flat = dx * dx + dy * dy
                        if flat < reach then
                            local ox, oy = bx - sx, by - sy
                            if flat < ox * ox + oy * oy - 1e-6 then return body end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Fence.shoveMate(mate, vx, vy, now, people, runner)
    if not Fence.isActorBody(mate) or not Fence.drivesBody(mate) then return false end
    local data = mate:getModData()
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    if (phase ~= "idle" and phase ~= "" and phase ~= "aborted") or data.ProjectALifePathActive == true
            or (type(mate.isMoving) == "function" and mate:isMoving() == true) then return false end
    local state = actionState(mate)
    if isGrounded(mate, state) or state == "falling" or string.sub(state, 1, 5) == "climb" then return false end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.current) == "table" then
        local pose = animations.current[mate]
        if pose ~= nil and Fence.crowd.rootedPoses[pose] == true then return false end
    end
    local square = mate:getCurrentSquare()
    if square == nil then return false end
    local crowd = Fence.crowd
    local mx, my = mate:getX(), mate:getY()
    local tx, ty = mx + vx, my + vy
    local ax, ay = tonumber(data.ProjectALifeYieldX), tonumber(data.ProjectALifeYieldY)
    if ax == nil or ay == nil then ax, ay = mx, my end
    local ox, oy = tx - ax, ty - ay
    if ox * ox + oy * oy > crowd.yieldMax * crowd.yieldMax
            or Fence.personNear(people, tx, ty, mate:getZ(), runner)
            or Fence.bodyNear(mate, tx, ty, mx, my) ~= nil
            or not Fence.stepClear(mate, square, mx, my, tx, ty) then return false end
    if not Fence.spendWrite(now) then return false end
    data.ProjectALifeYieldX, data.ProjectALifeYieldY, data.ProjectALifeYieldAtMs = ax, ay, now
    Fence.moveBody(mate, tx, ty)
    Fence.metrics.laneShoves = (Fence.metrics.laneShoves or 0) + 1
    return true
end

function Fence.dropYield(current)
    if current.ProjectALifeYieldX == nil and current.ProjectALifeYieldAtMs == nil then return end
    current.ProjectALifeYieldX, current.ProjectALifeYieldY, current.ProjectALifeYieldAtMs = nil, nil, nil
end

function Fence.laneYield(shell, current, square, sx, sy, now)
    local phase = tostring(current.ProjectALifeCombatPhase or "idle")
    if (phase ~= "idle" and phase ~= "" and phase ~= "aborted")
            or current.ProjectALifePathActive == true
            or (type(shell.isMoving) == "function" and shell:isMoving() == true) then
        Fence.dropYield(current)
        return false
    end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.current) == "table" then
        local pose = animations.current[shell]
        if pose ~= nil and Fence.crowd.rootedPoses[pose] == true then return false end
    end
    now = tonumber(now) or nowMs()
    local people = Fence.samplePeople(now)
    if people.runners > 0 then
        local stepped = Fence.laneStep(shell, current, square, sx, sy, now, people)
        if stepped ~= nil then return stepped end
    end
    return Fence.yieldReturn(shell, current, square, sx, sy, now, people)
end

function Fence.laneStep(shell, current, square, sx, sy, now, people)
    local crowd = Fence.crowd
    local clear = crowd.contact + crowd.laneMargin
    local sz = shell:getZ()
    local ax, ay = tonumber(current.ProjectALifeYieldX), tonumber(current.ProjectALifeYieldY)
    local held = false
    for index = 1, people.count do
        local runner = people.list[index]
        if runner.running == true and math.abs(runner.z - sz) <= 0.3 then
            local reach = runner.speed * crowd.lookaheadS
            local rx, ry = sx - runner.x, sy - runner.y
            local along = rx * runner.ux + ry * runner.uy
            local lateral = ry * runner.ux - rx * runner.uy
            if along > -crowd.contact and along < reach and math.abs(lateral) < clear then
                return Fence.stepAside(shell, current, square, sx, sy, now, people, runner, lateral)
            end
            if ax ~= nil and ay ~= nil then
                rx, ry = ax - runner.x, ay - runner.y
                along = rx * runner.ux + ry * runner.uy
                lateral = ry * runner.ux - rx * runner.uy
                if along > -crowd.contact and along < reach and math.abs(lateral) < clear then held = true end
            end
        end
    end
    if held then
        current.ProjectALifeYieldAtMs = now
        return false
    end
    return nil
end

function Fence.stepAside(shell, current, square, sx, sy, now, people, runner, lateral)
    local crowd = Fence.crowd
    current.ProjectALifeYieldAtMs = now
    local ax, ay = tonumber(current.ProjectALifeYieldX), tonumber(current.ProjectALifeYieldY)
    if ax == nil or ay == nil then
        ax, ay = sx, sy
        current.ProjectALifeYieldX, current.ProjectALifeYieldY = sx, sy
    end
    local side = 1
    if lateral < 0 then side = -1 end
    if math.abs(lateral) < 0.02 then side = Fence.uidSide(current) end
    local step = math.min(crowd.yieldStep, crowd.contact + crowd.laneMargin - math.abs(lateral))
    local sz = shell:getZ()
    for attempt = 1, 2 do
        local nx = sx - runner.uy * side * step
        local ny = sy + runner.ux * side * step
        local ox, oy = nx - ax, ny - ay
        if ox * ox + oy * oy <= crowd.yieldMax * crowd.yieldMax
                and not Fence.personNear(people, nx, ny, sz, runner)
                and Fence.stepClear(shell, square, sx, sy, nx, ny) then
            local mate = Fence.bodyNear(shell, nx, ny, sx, sy)
            if mate ~= nil and Fence.shoveMate(mate, nx - sx, ny - sy, now, people, runner) then
                mate = Fence.bodyNear(shell, nx, ny, sx, sy)
            end
            if mate == nil then
                if not Fence.spendWrite(now) then return true end
                Fence.moveBody(shell, nx, ny)
                Fence.metrics.laneYields = (Fence.metrics.laneYields or 0) + 1
                return true
            end
        end
        if attempt == 1 and math.abs(lateral) >= 0.1 then break end
        side = -side
    end
    Fence.metrics.laneBlocked = (Fence.metrics.laneBlocked or 0) + 1
    return false
end

function Fence.yieldReturn(shell, current, square, sx, sy, now, people)
    local ax, ay = tonumber(current.ProjectALifeYieldX), tonumber(current.ProjectALifeYieldY)
    if ax == nil or ay == nil then return false end
    local crowd = Fence.crowd
    local since = tonumber(current.ProjectALifeYieldAtMs)
    if since == nil or now < since then
        current.ProjectALifeYieldAtMs = now
        return false
    end
    if now - since < crowd.returnDelayMs then return false end
    if now - since > crowd.returnGiveUpMs then
        Fence.dropYield(current)
        return false
    end
    local dx, dy = ax - sx, ay - sy
    local gap = math.sqrt(dx * dx + dy * dy)
    if gap < 0.001 then
        Fence.dropYield(current)
        return false
    end
    local nx, ny = ax, ay
    if gap > crowd.returnStep then
        nx, ny = sx + dx / gap * crowd.returnStep, sy + dy / gap * crowd.returnStep
    end
    if Fence.personNear(people, nx, ny, shell:getZ(), nil)
            or Fence.bodyNear(shell, nx, ny, sx, sy) ~= nil
            or not Fence.stepClear(shell, square, sx, sy, nx, ny) then return false end
    if not Fence.spendWrite(now) then return true end
    Fence.moveBody(shell, nx, ny)
    Fence.metrics.laneReturns = (Fence.metrics.laneReturns or 0) + 1
    if gap <= crowd.returnStep then Fence.dropYield(current) end
    return true
end

function Fence.climbSelfHeal(shell, current, paceNow, blackBox, frameState)
    local state = frameState or actionState(shell)
    if state == "climbfence" or state == "climbwindow" then
        local since = tonumber(current.ProjectALifeClimbSinceMs)
        if since == nil then
            current.ProjectALifeClimbSinceMs = paceNow
        elseif paceNow - since > 5000 then

            pcall(function()
                shell:setVariable("ClimbFenceStarted", true)
                shell:setVariable("ClimbFenceFinished", true)
                shell:setVariable("ClimbWindowStarted", true)
                shell:setVariable("ClimbWindowFinished", true)
                shell:setVariable("ClimbingFence", false)
            end)
            current.ProjectALifeClimbSinceMs = nil

            current.ProjectALifeClimbCutAtMs = paceNow
            Fence.endWedgedClimb(shell, state)
            if blackBox ~= nil and blackBox.enabled == true then
                pcall(blackBox.note, shell, "self-heal", "wedged " .. state)
            end
        end
    else
        current.ProjectALifeClimbSinceMs = nil
    end
end

function Fence.endWedgedClimb(shell, state)
    local traversal = ProjectALife.ObstacleTraversal
    local via = "cancel"
    if traversal ~= nil and type(traversal.abortClip) == "function" then
        local ok, ended = pcall(traversal.abortClip, shell, "climb_self_heal")
        if ok and ended ~= false then via = "abort" end
    end
    if via == "cancel" then Fence.cancelWedgedClimb(shell, traversal) end

    if not Fence.ragdolling(shell, state) and type(shell.setOnFloor) == "function" then
        pcall(shell.setOnFloor, shell, false)
    end
    if type(shell.setCrawler) == "function" then pcall(shell.setCrawler, shell, false) end
    return via
end

function Fence.cancelWedgedClimb(shell, traversal)
    if traversal ~= nil and type(traversal.cancel) == "function" then pcall(traversal.cancel, shell, "climb_heal_cancel") end
    if ZombieIdleState ~= nil and type(shell.changeState) == "function" then
        pcall(shell.changeState, shell, ZombieIdleState.instance())
    end
    if traversal ~= nil and type(traversal.releaseClimbAction) == "function" then
        pcall(traversal.releaseClimbAction, shell, true, true)
    end
    if type(shell.resetModelNextFrame) == "function" then pcall(shell.resetModelNextFrame, shell) end
end

function Fence.faceHeardSound(shell, current, paceNow)
    local investigation = ProjectALife.Investigation
    if not Fence.authorityFor(shell) or investigation == nil
            or type(investigation.facingFor) ~= "function" then
        return
    end
    local phase = tostring(current.ProjectALifeCombatPhase or "idle")
    if phase ~= "idle" and phase ~= "" and phase ~= "aborted" then return end
    if current.ProjectALifePathActive == true then return end
    if paceNow < (tonumber(current.ProjectALifeNextFaceAtMs) or 0) then return end
    local mark = investigation.facingFor(shell:getX(), shell:getY(), paceNow)
    if mark == nil then return end
    current.ProjectALifeNextFaceAtMs = paceNow + 1200

    if math.abs(mark.x - shell:getX()) < 0.5 and math.abs(mark.y - shell:getY()) < 0.5 then return end
    shell:faceLocationF(mark.x, mark.y)
end

Fence.strafeMotions = setmetatable({}, { __mode = "k" })
Fence.strafeMotionMin = 0.004
Fence.strafeMotionKeep = 0.6
Fence.strafeMotionStaleMs = 400

function Fence.strafeMotion(shell, last, x, y)
    if last == nil then
        Fence.strafeMotions[shell] = nil
        return nil, nil
    end
    local dx, dy = x - last.x, y - last.y
    local now = nowMs()
    local seen = Fence.strafeMotions[shell]
    if seen ~= nil and (now < seen.atMs or now - seen.atMs > Fence.strafeMotionStaleMs) then seen = nil end
    if seen ~= nil then
        local keep = Fence.strafeMotionKeep
        dx, dy = seen.x * keep + dx * (1 - keep), seen.y * keep + dy * (1 - keep)
    end
    if seen == nil then
        seen = { x = dx, y = dy, atMs = now }
        Fence.strafeMotions[shell] = seen
    else
        seen.x, seen.y, seen.atMs = dx, dy, now
    end
    if math.sqrt(dx * dx + dy * dy) < Fence.strafeMotionMin then return nil, nil end
    return dx, dy
end

Fence.footworkKeepCosine = 0.82

function Fence.footworkLive(shell, current)
    local untilMs = tonumber(current.ProjectALifeFootworkUntilMs)
    if untilMs == nil then return false end
    if nowMs() >= untilMs then
        current.ProjectALifeFootworkUntilMs = nil
        return false
    end
    local carry = current.ProjectALifeWeaponClass
    if carry == "rifle" or carry == "handgun" then return false end
    if tostring(current.ProjectALifeCombatPhase or "") ~= "kite" then return false end
    return Fence.drivesBody(shell) == true
end

function Fence.footworkNote(shell, current, aimX, aimY)
    local x, y = shell:getX(), shell:getY()
    local forward = shell:getForwardDirection()
    local fx, fy = forward:getX(), forward:getY()
    local dx, dy = aimX - x, aimY - y
    local length, facing = math.sqrt(dx * dx + dy * dy), math.sqrt(fx * fx + fy * fy)
    current.ProjectALifeFootworkTicks = (tonumber(current.ProjectALifeFootworkTicks) or 0) + 1
    if length > 0.001 and facing > 0.001 and (fx * dx + fy * dy) / (length * facing) >= Fence.footworkKeepCosine then
        current.ProjectALifeFootworkKept = (tonumber(current.ProjectALifeFootworkKept) or 0) + 1
    end
end

function Fence.aimedMovement(shell, current, liveActionState)
    local aimX, aimY = tonumber(current.ProjectALifeAimAtX),
        tonumber(current.ProjectALifeAimAtY)
    local carry = current.ProjectALifeWeaponClass
    local ranged = carry == "rifle" or carry == "handgun"
    local footwork = Fence.footworkLive(shell, current)
    local traversing = liveActionState == "climbfence"
        or liveActionState == "climbwindow"
    local traversal = ProjectALife.ObstacleTraversal
    if not traversing and traversal ~= nil
            and type(traversal.isBusy) == "function" then
        traversing = traversal.isBusy(shell) == true
    end
    local x, y = shell:getX(), shell:getY()
    local last = Fence.lastPosition[shell]
    local craft = ProjectALife.ModuleStrafe

    local strafe = aimX ~= nil and aimY ~= nil and (ranged or footwork)
        and not traversing
        and current.ProjectALifePace ~= "run"
        and current.ProjectALifePace ~= "sprint"
        and (current.ProjectALifeAimWalk == true or footwork)
        and current.ProjectALifeWeaponHeld == true
        and current.ProjectALifeWoundLeg ~= true
        and (footwork or craft == nil or craft.active(current))
    if strafe then

        if shell:isAiming() then shell:setIsAiming(false) end

        Fence.faceAimPoint(shell, aimX, aimY)
        if footwork then Fence.footworkNote(shell, current, aimX, aimY) end

        local mx, my = Fence.strafeMotion(shell, last, x, y)
        if mx == nil and current.ProjectALifePathActive == true
                and shell.getPathFindBehavior2 ~= nil then
            local behavior = shell:getPathFindBehavior2()
            if behavior ~= nil and behavior.getTargetX ~= nil then
                mx, my = behavior:getTargetX() - x, behavior:getTargetY() - y
            end
        end
        if mx == nil and last ~= nil then mx, my = x - last.x, y - last.y end
        local sx, sy = 0, 0
        if mx ~= nil then
            local length = math.sqrt(mx * mx + my * my)
            if length > 0.004 then
                mx, my = mx / length, my / length

                local fx, fy = aimX - x, aimY - y
                local facing = math.sqrt(fx * fx + fy * fy)
                if facing > 0.004 then
                    fx, fy = fx / facing, fy / facing
                else
                    local forward = shell:getForwardDirection()
                    fx, fy = forward:getX(), forward:getY()
                end

                sy = mx * fx + my * fy
                sx = mx * -fy + my * fx
                sx, sy = Fence.stableStrafe(sx, sy)
            end
        end
        shell:SetVariable("ALifeStrafe", "true")
        shell:SetVariable("ALifeStrafeX", tostring(sx))
        shell:SetVariable("ALifeStrafeY", tostring(sy))
    else
        if shell:isAiming() then shell:setIsAiming(false) end

        if aimX ~= nil and aimY ~= nil and ranged and not traversing
                and current.ProjectALifeWoundLeg == true
                and current.ProjectALifeAimWalk == true
                and current.ProjectALifeWeaponHeld == true
                and current.ProjectALifePathActive ~= true then
            Fence.faceAimPoint(shell, aimX, aimY)
        end
        shell:SetVariable("ALifeStrafe", "false")
    end
    if last == nil then
        Fence.lastPosition[shell] = { x = x, y = y }
    else
        last.x, last.y = x, y
    end
end

function Fence.walkingFromAim(shell, current)
    if current.ProjectALifePathActive ~= true or shell.getPathFindBehavior2 == nil then return false end
    local aimX, aimY = tonumber(current.ProjectALifeAimAtX), tonumber(current.ProjectALifeAimAtY)
    if aimX == nil or aimY == nil then return false end
    local ok, away = pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior == nil or behavior.getTargetX == nil then return false end
        local x, y = shell:getX(), shell:getY()
        local mx, my = behavior:getTargetX() - x, behavior:getTargetY() - y
        local fx, fy = aimX - x, aimY - y
        local ml, fl = math.sqrt(mx * mx + my * my), math.sqrt(fx * fx + fy * fy)
        if ml < 1 or fl < 0.5 then return false end
        return (mx * fx + my * fy) / (ml * fl) < -0.3
    end)
    return ok and away == true
end

function Fence.restampWeaponPose(shell, current)

    local held = current.ProjectALifeWeaponHeld == true
    shell:SetVariable("ALifeWeaponHeld", held and "true" or "false")
    local carry = current.ProjectALifeWeaponClass

    local settings = ProjectALife.BehaviorSettings
    local guardWalk = type(settings) == "table" and type(settings.combat) == "table"
        and settings.combat.meleeGuardWalk ~= false
    local aimWalk = current.ProjectALifeAimWalk == true
        and current.ProjectALifePace ~= "run" and current.ProjectALifePace ~= "sprint"
        and (carry == "rifle" or carry == "handgun" or (guardWalk and (carry == "melee" or carry == "spear")))
    if aimWalk and (carry == "melee" or carry == "spear") and Fence.walkingFromAim(shell, current) then
        aimWalk = false
    end
    shell:SetVariable("ALifeAimWalk", aimWalk and "true" or "false")
    local arms = Fence.armsToken(carry)
    if arms ~= nil then shell:SetVariable("ALifeArms", arms) end
    local grip = current.ProjectALifeGrip
    if type(grip) == "string" and grip ~= "" then
        shell:SetVariable("ALifeGrip", grip)
    end

    shell:SetVariable("ALifeCombatSpeed",
        tostring(Fence.combatSpeedFor(grip, carry)))
end

function Fence.nativeWatchdog(shell, frameState)
    local state = frameState or actionState(shell)
    local limits = Fence.stuckLimits

    local prone = isGrounded(shell, state)
    if prone then

        pcall(shell.setHideWeaponModel, shell, false)

        local unauthored = Fence.proneSinceMs[shell] == nil
            and not Fence.heldDown(shell, nowMs())
        if Fence.airborneRagdoll(shell, state) then

        elseif unauthored and not Fence.shoveLands(shell) then
            beginGetUp(shell, nowMs())
            local blackBox = ProjectALife.BlackBox
            if blackBox ~= nil and blackBox.enabled == true then blackBox.note(shell, "shove", "shrugged") end
        elseif Fence.proneSinceMs[shell] == nil then
            Fence.proneSinceMs[shell] = nowMs()
            Fence.proneFirstMs[shell] = Fence.proneFirstMs[shell] or nowMs()
            releaseGroundPath(shell)
            pcall(function() shell:setUseless(true) end)
        elseif nowMs() - (Fence.proneFirstMs[shell] or nowMs()) >= Fence.downedHardCapMs then
            Fence.proneSinceMs[shell] = nil
            Fence.proneFirstMs[shell] = nil
            pcall(function()
                local data = shell:getModData()
                if type(data) == "table" then
                    data.ProjectALifeDownedUntilMs = nil
                    data.ProjectALifeBleedOutAtMs = nil
                end

                local health = Fence.realHealth(shell)

                local simulation = ProjectALife.ShellSimulation
                local maximum = 1
                if simulation ~= nil and type(simulation.maximumFor) == "function" then
                    maximum = tonumber(simulation.maximumFor(shell)) or 1
                end
                if maximum <= 0 then maximum = 1 end
                local blackBox = ProjectALife.BlackBox
                if Fence.authorityFor(shell) and not shell:isDead() and health <= maximum * 0.10 then
                    local killer = shell
                    local wounds = ProjectALife.Health
                    if wounds ~= nil and type(wounds.lastAttacker) == "table" then
                        killer = wounds.lastAttacker[shell] or shell
                    end
                    if ProjectALife.ShellSimulation ~= nil then ProjectALife.ShellSimulation.setHealth(shell, 0) end
                    shell:Kill(killer)
                    if blackBox ~= nil and blackBox.enabled == true then blackBox.note(shell, "prone-cap", "killed") end
                else
                    beginGetUp(shell, nowMs())
                    if blackBox ~= nil and blackBox.enabled == true then blackBox.note(shell, "prone-cap", "getup") end
                end
            end)
        elseif nowMs() - Fence.proneSinceMs[shell] >= Fence.groundRestMs
                and not Fence.heldDown(shell, nowMs()) then
            Fence.proneSinceMs[shell] = nil
            Fence.proneFirstMs[shell] = nil
            beginGetUp(shell, nowMs())
        end
    else
        Fence.proneSinceMs[shell] = nil
        Fence.proneFirstMs[shell] = nil

        Fence.shoveVerdict[shell] = nil
    end
    local limit = limits[state]
    if limit == nil then
        Fence.stuckSinceMs[shell] = nil
    else
        local since = Fence.stuckSinceMs[shell]
        if since == nil then
            Fence.stuckSinceMs[shell] = nowMs()
        elseif nowMs() - since >= limit then
            Fence.stuckSinceMs[shell] = nil
            if state == "climbfence" or state == "climbwindow" then

                local traversal = ProjectALife.ObstacleTraversal
                if traversal ~= nil and type(traversal.cancel) == "function" then
                    pcall(traversal.cancel, shell, "stuck_climb_state")
                end
                pcall(function()
                    if ZombieIdleState ~= nil then
                        shell:changeState(ZombieIdleState.instance())
                    end
                    shell:setIgnoreMovement(false)
                    shell:setHideWeaponModel(false)
                end)
                if traversal ~= nil and type(traversal.releaseClimbAction) == "function" then
                    pcall(traversal.releaseClimbAction, shell, state == "climbfence", state == "climbwindow")
                end
                return
            end

            if string.sub(state, 1, 11) ~= "hitreaction" then
                shell:setHitReaction("")
            end
            pcall(function() shell:setStaggerBack(false) end)

            if not isGrounded(shell, state) then
                shell:setKnockedDown(false)
                shell:setOnFloor(false)
                shell:setFallOnFront(false)
            end
            shell:setBumpFall(false)
            pcall(function() shell:setBumpStaggered(false) end)
            shell:setBumpDone(true)
            shell:setBumpType("")
            shell:setBumpFallType("")
            pcall(function() shell:setBumpedChr(nil) end)
            if state == "onground" or state == "knockeddown" then

                pcall(function() shell:setCrawler(false) end)
                pcall(function() shell:setBecomeCrawler(false) end)
                pcall(function() shell:setCanWalk(true) end)
                pcall(function()
                    if ZombieIdleState ~= nil then
                        shell:changeState(ZombieIdleState.instance())
                    end
                end)
                pcall(function() shell:resetModelNextFrame() end)
            end
        end
    end
end

function Fence.dropAimFlag(shell)
    if shell:isAiming() then shell:setIsAiming(false) end
end

function Fence.clearSkeleton(shell)
    if shell == nil or shell.isSkeleton == nil or shell.setSkeleton == nil then return false end
    if shell.isDead ~= nil and shell:isDead() then return false end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and sim.grappledCorpse ~= nil and sim.grappledCorpse(shell) then return false end
    if not shell:isSkeleton() then return false end
    shell:setSkeleton(false)
    if shell.resetModelNextFrame ~= nil then shell:resetModelNextFrame() end
    return true
end

function Fence.track(shell)
    if shell == nil then return false, "shell_required" end
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and sim.grappledCorpse ~= nil and sim.grappledCorpse(shell) then return false, "grappled_corpse" end
    if Fence.owned[shell] ~= true then
        Fence.metrics.tracked = Fence.metrics.tracked + 1
    end
    Fence.owned[shell] = true

    if Fence.fenced[shell] == nil then
        Fence.fenced[shell] = true
        Fence.metrics.fenced = (Fence.metrics.fenced or 0) + 1
    end
    Fence.rejected[shell] = nil
    markOwned(shell)
    pcall(Fence.clearSkeleton, shell)
    return Fence.apply(shell)
end

function Fence.armsToken(carry)
    if type(carry) ~= "string" or carry == "" then return nil end
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.armsOf) ~= "function" then return nil end
    return animations.armsOf(carry)
end

function Fence.untrack(shell)
    Fence.reactionRecovery[shell] = nil
    if shell == nil then return false end
    if Fence.pendingHit[shell] ~= nil then pcall(Fence.settlePlayerHit, shell) end
    if ProjectALife.Campfires ~= nil and type(ProjectALife.Campfires.releaseProtection) == "function" then
        ProjectALife.Campfires.releaseProtection(shell)
    end
    if ProjectALife.ShellSimulation then ProjectALife.ShellSimulation.applied[shell] = nil end
    Fence.owned[shell] = nil
    Fence.rejected[shell] = nil
    Fence.aimFacing[shell] = nil
    Fence.nextTerrainSweepAtMs[shell] = nil
    Fence.terrainSlow[shell] = nil
    for _, name in ipairs({ "voicedShells", "nextVoiceSweepAtMs", "nextTraversalAudioSweepAtMs",
            "nextPaceRefreshAtMs", "reloadBumpSinceMs", "hitAudioPending", "nextHitReactAtMs",

            "pendingHit", "fallShield", "shoving", "proneFirstMs", "shoveVerdict",
            "shoveVerdict", "roomSweptAt",
            "hitWindowUntilMs", "nextStaggerAtMs", "lastPosition", "strafeMotions", "proneSinceMs", "stuckSinceMs",
            "gaitWritten" }) do
        if Fence[name] then Fence[name][shell] = nil end
    end

    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and type(blackBox.forget) == "function" then
        blackBox.forget(shell)
    elseif blackBox ~= nil then
        blackBox.tracked[shell] = nil
    end

    local presentation = ProjectALife.AnimationClient
    if presentation ~= nil and type(presentation.forget) == "function" then presentation.forget(shell) end

    Fence.lower(shell, "untrack")
    return true
end

Fence.releasedBodies = {}
function Fence.releaseBody(shell, reason)
    if shell == nil then return false end
    return ProjectALife.EquipEventShield.withCleanup(shell, function()
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.forget) == "function" then
        pcall(animations.forget, shell)
    end
    pcall(shell.clearAttachedItems, shell)
    pcall(shell.setSecondaryHandItem, shell, nil)
    pcall(shell.setPrimaryHandItem, shell, nil)
    pcall(Fence.untrack, shell)
    local key = tostring(reason or "unspecified")
    Fence.releasedBodies[key] = (Fence.releasedBodies[key] or 0) + 1
    return true
    end)
end

function Fence.isTracked(shell)
    return shell ~= nil and Fence.owned[shell] == true
end

function Fence.cosmeticStamp(shell)
    local data = shell:getModData()
    if type(data) ~= "table" then return end
    ProjectALife.Animations.migrateHeldBump(shell, data)
    shell:SetVariable("ALifeActor", "true")
    local pace = data.ProjectALifePace
    if pace == "run" or pace == "sprint" or pace == "walk" then
        shell:SetVariable("ALifePace", pace)
    end
    if data.ProjectALifeWeaponHeld ~= nil then
        shell:SetVariable("ALifeWeaponHeld",
            data.ProjectALifeWeaponHeld == true and "true" or "false")
    end
    local arms = Fence.armsToken(data.ProjectALifeWeaponClass)
    if arms ~= nil then shell:SetVariable("ALifeArms", arms) end
    shell:SetVariable("ALifeAimWalk",
        data.ProjectALifeAimWalk == true and "true" or "false")
    if data.ProjectALifeSneakActive ~= nil then
        shell:SetVariable("ALifeSneak",
            data.ProjectALifeSneakActive == true and "true" or "false")
    end
    if data.ProjectALifeWoundLeg ~= nil then
        local healthSystem = ProjectALife.Health
        local armedLimp = healthSystem ~= nil and type(healthSystem.settings) == "table"
            and healthSystem.settings.limpWithWeapon == true
        shell:SetVariable("ALifeLimp",
            data.ProjectALifeWoundLeg == true
            and (armedLimp or data.ProjectALifeWeaponHeld ~= true) and "true" or "false")
    end
end

function Fence.applyCosmetic(shell)
    if shell == nil or type(shell.isDead) ~= "function" then return end
    local deadOk, dead = pcall(shell.isDead, shell)
    if not deadOk or dead == true then return end
    Fence.clearFeedingTargets(shell)
    pcall(Fence.cosmeticStamp, shell)
    silenceNativeVoice(shell)
end

local function onZombieUpdate(shell)
    if shell == nil then return end

    local simulation = ProjectALife.ShellSimulation
    if simulation and simulation.retireUntilMs ~= nil and simulation.removeRetired(shell) then return end

    if Fence.observersLive ~= true and Fence.owned[shell] ~= true and Fence.rejected[shell] == true then
        if Fence.fenced[shell] ~= nil then Fence.lower(shell, "sweep") end
        return
    end
    local executor = ProjectALife.Executor

    local skip = Fence.observeSkip[shell]
    if skip ~= nil and skip > 0 then
        Fence.observeSkip[shell] = skip - 1
    else
        Fence.observeSkip[shell] = Fence.observeEvery - 1

        if spectatorSide() and ProjectALife.AnimationClient ~= nil
                and type(ProjectALife.AnimationClient.observe) == "function" then
            ProjectALife.AnimationClient.observe(shell)
        end

        if executor ~= nil and executor.started then executor.observe(shell) end
    end

    local marks, marked = nil, false
    if Fence.owned[shell] == true then
        local marksOk
        marksOk, marks = pcall(shell.getModData, shell)
        if not marksOk then marks = nil end
        marked = Fence.marksOwned(marks)
    end
    if marked and ProjectALife.ShellSimulation
            and not (executor ~= nil and executor.executes(shell)) then
        ProjectALife.ShellSimulation.drive(shell)
        marked = Fence.marksOwned(marks)
    end
    if Fence.owned[shell] == true and not marked then

        local corpseData = marks
        if corpseData == nil and shell.getModData ~= nil then corpseData = shell:getModData() end
        if type(corpseData) == "table" and corpseData.ProjectALifeCorpseOf ~= nil then
            pcall(Fence.untrack, shell)
            Fence.rejected[shell] = true
            return
        end
        Fence.releaseBody(shell, "recycled")
        Fence.rejected[shell] = true
        return
    end
    if Fence.owned[shell] == true then
        local sampledAt = Fence.frameSampling == true and getTimestampMs() or nil
        if Fence.pendingHit[shell] ~= nil then Fence.settlePlayerHit(shell) end
        Fence.apply(shell)

        local combat = ProjectALife.Combat
        if Fence.authorityFor(shell) and combat ~= nil and type(combat.relax) == "function" then
            pcall(combat.relax, shell)
        end
        if sampledAt ~= nil then Fence.noteSampledCall(sampledAt) end
        return
    end
    if Fence.rejected[shell] == true then

        if Fence.fenced[shell] ~= nil then Fence.lower(shell, "sweep") end
        return
    end
    if isMarkedOwned(shell) then

        local runtime = ProjectALife.Runtime
        local serverish = type(isServer) ~= "function" or isServer()
            or type(isClient) ~= "function" or not isClient()
        if serverish and (runtime == nil or runtime.started ~= true) then
            return 
        end
        if not serverish then

            Fence.track(shell)
            return
        end

        local sim = ProjectALife.ShellSimulation
        if sim ~= nil and sim.grappledCorpse ~= nil and sim.grappledCorpse(shell) then return end
        if shell.isDead ~= nil then
            local deadOk, alreadyDead = pcall(shell.isDead, shell)
            if deadOk and alreadyDead == true then return end
        end
        local verdict = "track"
        pcall(function()
            local registry = ProjectALife.ActorRegistry
            if registry == nil then return end 
            local data = shell:getModData()
            local uid = data.ProjectALifeUID
            if type(uid) ~= "string" then verdict = "cull" return end

            local bornAt = tonumber(data.ProjectALifeSpawnedAtMs)
            if bornAt ~= nil and nowMs() - bornAt < 6000 then return end
            local actor = (registry.peek or registry.read)(uid)
            if actor == nil then verdict = "cull" return end
            if actor.lifecycle == "dead" then

                if executor ~= nil and executor.recentRemoteDeath ~= nil
                        and actor.generation == tonumber(data.ProjectALifeGeneration)
                        and executor.recentRemoteDeath(shell) == true then
                    return
                end
                if shell:isDead() ~= true then verdict = "cull" end
                return 
            end
            if actor.lifecycle ~= "active" and actor.lifecycle ~= "spawning" then
                verdict = "cull" return
            end
            if actor.generation ~= tonumber(data.ProjectALifeGeneration) then
                verdict = "cull"
            end
        end)
        if verdict == "cull" then

            if type(Fence.untrack) == "function" then
                pcall(Fence.untrack, shell)
            end
            Fence.rejected[shell] = true
            pcall(function()
                if ProjectALife.ShellAdapter ~= nil then
                    ProjectALife.ShellAdapter.cleanupShell(shell)
                else
                    if ProjectALife.Animations ~= nil then ProjectALife.Animations.forget(shell) end
                    shell:removeFromWorld()
                    shell:removeFromSquare()
                end
            end)
            local blackBox = ProjectALife.BlackBox
            if blackBox ~= nil and type(blackBox.metrics) == "table" then
                blackBox.metrics.ghostCulls = (blackBox.metrics.ghostCulls or 0) + 1
            end
            return
        end
        Fence.track(shell)
    else

        Fence.rejected[shell] = true
        if ProjectALife.Animations ~= nil and type(ProjectALife.Animations.forget) == "function" then
            pcall(ProjectALife.Animations.forget, shell)
        end

        local blackBox = ProjectALife.BlackBox
        if blackBox ~= nil and type(blackBox.metrics) == "table" then
            blackBox.metrics.unownedShells = (blackBox.metrics.unownedShells or 0) + 1
        end
    end
end

Fence.playerFire = {

    shots = { rifle = 3.5, pistol = 4.5, shotgun = 2, light = 5, melee = 3, heavy = 2.5,
        shove = 40, stomp = 10.8 },

    lightBelow = 0.8, heavyFrom = 2,

    toughnessMin = 0.5, toughnessMax = 3,

    meleeHead = 1.8, meleeHelmetedHead = 1.4,

    meleeArmourFloor = 0.7,

    shoveFloor = 0.20,

    stompBoot = 2.1, stompBare = 0.8, stompStrengthStep = 0.2,
    stompBaseStrength = 5, stompScaleMin = 0.35, stompScaleMax = 1.5,

    head = 2.2, helmetedHead = 1.6, vest = 0.8,

    blastMs = 80,

    shotgunNear = 5, shotgunFar = 14, shotgunFarFactor = 0.4,

    lift = 1000,
}
Fence.pendingHit = setmetatable({}, { __mode = "k" })

Fence.shoving = setmetatable({}, { __mode = "k" })

Fence.shoveLandsPercent = 20

Fence.shoveVerdict = setmetatable({}, { __mode = "k" })
Fence.shoveShrugWindowMs = 1500

function Fence.shoveKnockdownPercent()
    local behavior = ProjectALife.BehaviorSettings
    local percent
    if type(behavior) == "table" and type(behavior.combat) == "table" then
        percent = tonumber(behavior.combat.shoveKnockdownPercent)
    end
    if percent == nil then percent = tonumber(Fence.shoveLandsPercent) or 20 end
    if percent < 0 then return 0 end
    if percent > 100 then return 100 end
    return percent
end

function Fence.shrugHolds(shell, now)
    local lease = Fence.shoveVerdict[shell]
    return lease ~= nil and lease.landed == false
        and (tonumber(now) or 0) < lease.untilMs
end

function Fence.shoveLands(shell)
    local lease = Fence.shoveVerdict[shell]
    if lease ~= nil then
        if lease.landed == true then return true end
        if nowMs() < lease.untilMs then return false end

        Fence.shoveVerdict[shell] = { landed = true, untilMs = nowMs() }
        return true
    end
    local chance = Fence.shoveKnockdownPercent()

    local rolled = 100
    if type(ZombRand) == "function" then rolled = ZombRand(100)
    else rolled = math.random(0, 99) end
    if rolled < chance then
        Fence.shoveVerdict[shell] = { landed = true, untilMs = nowMs() }
        return true
    end
    Fence.shoveVerdict[shell] = { landed = false,
        untilMs = nowMs() + (tonumber(Fence.shoveShrugWindowMs) or 1500) }

    pcall(function()
        local data = shell:getModData()
        if type(data) == "table" then data.ProjectALifeDownedUntilMs = nil end
    end)
    Fence.proneSinceMs[shell] = nil
    Fence.metrics.shovesShrugged = (Fence.metrics.shovesShrugged or 0) + 1
    return false
end

function Fence.fireClass(ammo, fullType)
    ammo, fullType = string.lower(tostring(ammo or "")), string.lower(tostring(fullType or ""))
    if string.find(ammo, "shotgun", 1, true) or string.find(fullType, "shotgun", 1, true) then return "shotgun" end
    for _, mark in ipairs({ "9mm", "45", "38", "44", "pistol", "revolver" }) do
        if string.find(ammo, mark, 1, true) or string.find(fullType, mark, 1, true) then return "pistol" end
    end
    return "rifle"
end

function Fence.meleeClass(weapon)
    local fire, damage = Fence.playerFire, 0
    if weapon ~= nil and weapon.getMaxDamage ~= nil then
        local ok, value = pcall(weapon.getMaxDamage, weapon)
        if ok then damage = tonumber(value) or 0 end
    end
    if damage >= fire.heavyFrom then return "heavy" end
    if damage > 0 and damage < fire.lightBelow then return "light" end
    return "melee"
end

function Fence.soakOf(shell, data)
    local value = type(data) == "table" and tonumber(data.ProjectALifeDamageReduction) or nil
    if value == nil and shell ~= nil and shell.GetVariable ~= nil then
        local ok, raw = pcall(shell.GetVariable, shell, "ALifeDamageReduction")
        if ok then value = tonumber(raw) end
    end
    return math.max(0, math.min(90, value or 0))
end

function Fence.hitShare(class, zone, distance, helmet, vest, rating, soak)
    local fire = Fence.playerFire
    local tuned = ProjectALife.NpcHealth
    if tuned ~= nil and type(tuned.fireFor) == "function" then
        local ok, tuning = pcall(tuned.fireFor, fire)
        if ok and type(tuning) == "table" then fire = tuning end
    end
    local toughness = math.max(fire.toughnessMin, math.min(fire.toughnessMax, (tonumber(rating) or 6) / 6))
    local share = 1 / ((fire.shots[class] or fire.shots.rifle) * toughness)
    local melee = class == "light" or class == "melee" or class == "heavy"
    local armour = 1
    if zone == "head" then
        share = share * (melee and (helmet and fire.meleeHelmetedHead or fire.meleeHead)
            or (helmet and fire.helmetedHead or fire.head))
    elseif vest then armour = fire.vest end
    if melee or class == "stomp" then
        local reduction = math.max(0, math.min(90, tonumber(soak) or 0))
        armour = math.max(math.min(armour, fire.meleeArmourFloor), armour * (1 - reduction / 100))
    end
    share = share * armour
    if class == "shotgun" then
        local d = tonumber(distance) or 0
        if d > fire.shotgunNear then
            local t = math.min(1, (d - fire.shotgunNear) / math.max(1, fire.shotgunFar - fire.shotgunNear))
            share = share * (1 - t * (1 - fire.shotgunFarFactor))
        end
    end
    return share
end

function Fence.armourKind(fullType)
    local name = string.lower(tostring(fullType or ""))
    if string.find(name, "vest_bullet", 1, true) then return "vest" end
    if string.find(name, "hat_army", 1, true) or string.find(name, "helmet", 1, true)
            or string.find(name, "hat_swat", 1, true) or string.find(name, "hat_riot", 1, true) then
        return "helmet"
    end
    return nil
end

function Fence.shield(shell, bodyPart, weapon)
    local armor = ProjectALife.Armor
    if armor == nil or type(armor.blocksWeapon) ~= "function" or type(armor.informed) ~= "function" then
        return false, false
    end
    local known, informed = pcall(armor.informed, shell)
    if not known or informed ~= true then return false, false end
    local ok, blocked = pcall(armor.blocksWeapon, shell, bodyPart, weapon)
    return true, ok and blocked == true
end

function Fence.armourOn(shell)
    local helmet, vest = false, false
    local function note(fullType)
        local kind = Fence.armourKind(fullType)
        if kind == "vest" then vest = true elseif kind == "helmet" then helmet = true end
    end
    pcall(function()

        if shell:isDead() then return end
        local visuals = shell:getItemVisuals()
        for index = 0, visuals:size() - 1 do note(visuals:get(index):getItemType()) end
    end)
    pcall(function()
        local worn = shell:getWornItems()
        for index = 0, worn:size() - 1 do note(worn:get(index):getItem():getFullType()) end
    end)
    return helmet, vest
end

function Fence.weaponFacts(weapon)
    local firearm, ammo, fullType, degraded = false, "", "", false
    local function read(name)
        local method = weapon ~= nil and weapon[name] or nil
        if type(method) ~= "function" then return nil end
        local ok, value = pcall(method, weapon)
        if ok then return value end
        return nil
    end
    local aimed = read("isAimedFirearm")
    if aimed == nil then aimed = read("isRanged") end
    if aimed == nil then degraded = true end
    firearm = aimed == true
    local kind = read("getFullType")
    if kind ~= nil then fullType = tostring(kind) end
    local round = read("getAmmoType")
    if round ~= nil then ammo = tostring(round) end
    return firearm, ammo, fullType, degraded
end

function Fence.heldWeapon(wielder)
    if wielder == nil or type(wielder.getPrimaryHandItem) ~= "function" then return nil end
    local ok, item = pcall(wielder.getPrimaryHandItem, wielder)
    if not ok or item == nil or type(item.IsWeapon) ~= "function" then return nil end
    local armed = false
    pcall(function() armed = item:IsWeapon() == true end)
    if armed then return item end
    return nil
end

function Fence.ownedBody(body)
    if body == nil or type(body.getModData) ~= "function" then return false end
    local ok, data = pcall(body.getModData, body)
    return ok and Fence.marksOwned(data)
end

function Fence.weighPlayerHit(shell, wielder, bodyPart, weapon)
    local after
    local had = Fence.pendingHit[shell]
    local ok = pcall(function() after = Fence.weighBlow(shell, wielder, bodyPart, weapon, false) end)
    if ok then return after end
    Fence.metrics.weighFaults = (Fence.metrics.weighFaults or 0) + 1
    local pending = Fence.pendingHit[shell]
    if pending ~= nil and pending ~= had then return pending.target end
    pcall(function() after = Fence.weighBlow(shell, wielder, bodyPart, nil, true) end)
    return after
end

function Fence.weighBlow(shell, wielder, bodyPart, weapon, plain)
    if wielder == nil or wielder == shell or Fence.ownedBody(wielder) then return nil end
    if plain == true then
        weapon = nil
    elseif weapon == nil then
        weapon = Fence.heldWeapon(wielder)
    end
    local firearm, ammo, fullType, degraded = Fence.weaponFacts(weapon)
    if weapon == nil then degraded = false end
    if degraded then
        Fence.metrics.damageZeroFloored = (Fence.metrics.damageZeroFloored or 0) + 1
    end
    local healthSystem = ProjectALife.Health
    if healthSystem ~= nil and healthSystem.invulnerable(shell) then return nil end
    local now = nowMs()
    local pending = Fence.pendingHit[shell]
    local class = firearm and Fence.fireClass(ammo, fullType) or Fence.meleeClass(weapon)

    if pending ~= nil and class == "shotgun" and pending.class == "shotgun"
            and now - pending.atMs <= Fence.playerFire.blastMs then
        return pending.target
    end
    local data = shell:getModData()
    local maximum = tonumber(data.ProjectALifeMaximumHealth) or tonumber(shell:getHealth()) or 1

    local before = pending ~= nil and pending.target or Fence.realHealth(shell)
    local zone = string.find(string.lower(tostring(bodyPart)), "head", 1, true) and "head" or "torso"
    local distance = 0
    pcall(function()
        local dx, dy = shell:getX() - wielder:getX(), shell:getY() - wielder:getY()
        distance = math.sqrt(dx * dx + dy * dy)
    end)
    local helmet, vest = Fence.armourOn(shell)
    local soak = 0
    if not firearm then soak = Fence.soakOf(shell, data) end
    local rolled, blocked = Fence.shield(shell, bodyPart, weapon)
    if rolled then helmet, vest = false, false end
    local target = before - maximum * Fence.hitShare(class, zone, distance, helmet, vest,
        tonumber(data.ProjectALifeHealthRating), soak)
    if blocked then
        target = before
        Fence.metrics.armourBlocked = (Fence.metrics.armourBlocked or 0) + 1
    end
    Fence.pendingHit[shell] = { target = target, wielder = wielder, class = class, atMs = now, blocked = blocked,
        before = pending ~= nil and (pending.before or before) or before }

    local simulation = ProjectALife.ShellSimulation
    if simulation ~= nil then simulation.setHealth(shell, before + Fence.playerFire.lift)
    else shell:setHealth(before + Fence.playerFire.lift) end
    Fence.metrics.weighed = (Fence.metrics.weighed or 0) + 1
    return target
end

function Fence.stompScale(wielder)
    if wielder == nil then return 1 end
    local fire = Fence.playerFire
    local boot, strength = 0, fire.stompBaseStrength
    pcall(function()
        if wielder.getWornItems == nil then return end
        local worn = wielder:getWornItems()
        if worn == nil or worn.size == nil or worn.get == nil then return end
        for index = 0, worn:size() - 1 do
            local entry = worn:get(index)
            local item
            if entry ~= nil and entry.getItem ~= nil then item = entry:getItem() end
            if item ~= nil and item.getStompPower ~= nil then
                local power = tonumber(item:getStompPower()) or 0
                if power > boot then boot = power end
            end
        end
    end)
    pcall(function()
        if wielder.getPerkLevel == nil or Perks == nil then return end
        local level = tonumber(wielder:getPerkLevel(Perks.Strength))
        if level ~= nil and level > 0 then strength = level end
    end)
    if boot <= 0 then boot = fire.stompBare end
    local scale = (boot / fire.stompBoot)
        * (1 + (strength - fire.stompBaseStrength) * fire.stompStrengthStep)
    return math.max(fire.stompScaleMin, math.min(fire.stompScaleMax, scale))
end

function Fence.shoveTarget(shell, before, stomp, wielder)
    local fire = Fence.playerFire
    local maximum, rating, stored = 0, nil, nil
    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        stored = data
        maximum = tonumber(data.ProjectALifeMaximumHealth) or 0
        rating = tonumber(data.ProjectALifeHealthRating)
    end)
    if maximum <= 0 then
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil and simulation.maximumFor ~= nil then
            maximum = tonumber(simulation.maximumFor(shell)) or 0
        end
    end
    if maximum <= 0 then maximum = before end
    if stomp == true then
        local _, vest = Fence.armourOn(shell)
        local target = before - maximum
            * Fence.hitShare("stomp", "torso", 0, false, vest, rating, Fence.soakOf(shell, stored))
            * Fence.stompScale(wielder)
        if target < 0 then target = 0 end
        return target
    end
    local floor = maximum * fire.shoveFloor
    local target = before - maximum * Fence.hitShare("shove", "torso", 0, false, false, rating)
    if target < floor then target = floor end
    if target > before then target = before end
    return target
end

function Fence.absorbShove(shell, stomp, wielder)
    local after
    pcall(function()
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and healthSystem.invulnerable(shell) then return end
        local pending = Fence.pendingHit[shell]
        local before = pending ~= nil and pending.target or Fence.realHealth(shell)

        if before <= 0 then return end

        local target = before
        if wielder ~= nil then target = Fence.shoveTarget(shell, before, stomp == true, wielder) end
        Fence.pendingHit[shell] = { target = target, wielder = wielder,
            class = stomp == true and "stomp" or "shove", atMs = nowMs(),
            before = pending ~= nil and (pending.before or before) or before }
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, before + Fence.playerFire.lift)
        else shell:setHealth(before + Fence.playerFire.lift) end
        if stomp == true then
            Fence.metrics.stompsWeighed = (Fence.metrics.stompsWeighed or 0) + 1
        else
            Fence.metrics.shovesAbsorbed = (Fence.metrics.shovesAbsorbed or 0) + 1
        end
        after = target
    end)
    return after
end

function Fence.realHealth(shell)
    local simulation = ProjectALife.ShellSimulation
    if simulation ~= nil and type(simulation.trueHealth) == "function" then
        return tonumber(simulation.trueHealth(shell)) or 0
    end
    return tonumber(shell:getHealth()) or 0
end

function Fence.settlePlayerHit(shell)
    local pending = Fence.pendingHit[shell]
    Fence.pendingHit[shell] = nil
    if pending == nil then return end
    pcall(function()
        if shell:isDead() then return end
        local simulation = ProjectALife.ShellSimulation

        local target = pending.target <= 0.001 and pending.class ~= "shove" and 0 or pending.target
        if simulation ~= nil then simulation.setHealth(shell, target) else shell:setHealth(target) end
        Interop.hit(shell, pending.wielder, (tonumber(pending.before) or target) - target)
        if target <= 0 then
            local uid, generation = Fence.delegatedIdentity(shell)
            shell:Kill(pending.wielder or shell)
            Fence.metrics.weighedKills = (Fence.metrics.weighedKills or 0) + 1
            if uid ~= nil then Fence.killDelegated(shell, uid, generation, pending.wielder, "settle") end
        end
    end)
end

Fence.silentReachSquared = 2500
Fence.silentGapMs = 250
Fence.silentAtMs = setmetatable({}, { __mode = "k" })

function Fence.adoptSilentHit(shell, health, ceiling)
    if shell == nil or Fence.owned[shell] ~= true or Fence.pendingHit[shell] ~= nil then return false end
    if not Fence.authorityFor(shell) then return false end
    local now = nowMs()
    if (Fence.hitWindowUntilMs[shell] or 0) > now then return false end
    local attacker
    pcall(function() attacker = shell:getAttackedBy() end)
    if attacker == nil or attacker == shell or Fence.ownedBody(attacker) then return false end
    local player = false
    pcall(function() player = instanceof(attacker, "IsoPlayer") == true end)
    if not player then return false end
    local distance2 = math.huge
    pcall(function()
        local dx, dy = shell:getX() - attacker:getX(), shell:getY() - attacker:getY()
        distance2 = dx * dx + dy * dy
    end)
    if distance2 > Fence.silentReachSquared then return false end
    local burning = false
    pcall(function() burning = type(shell.isOnFire) == "function" and shell:isOnFire() == true end)
    if burning then return false end
    if now - (Fence.silentAtMs[shell] or -1e12) < Fence.silentGapMs then return false end
    Fence.silentAtMs[shell] = now
    local healthSystem = ProjectALife.Health
    if healthSystem ~= nil and healthSystem.invulnerable(shell) then return false end
    local data = shell:getModData()
    local weapon = Fence.heldWeapon(attacker)
    local firearm, ammo, fullType = false, "", ""
    if weapon ~= nil then firearm, ammo, fullType = Fence.weaponFacts(weapon) end
    local class = firearm and Fence.fireClass(ammo, fullType) or Fence.meleeClass(weapon)
    local maximum = tonumber(data.ProjectALifeMaximumHealth) or ceiling
    local helmet, vest = Fence.armourOn(shell)
    local soak = 0
    if not firearm then soak = Fence.soakOf(shell, data) end
    local rolled, blocked = Fence.shield(shell, "torso", weapon)
    if rolled then helmet, vest = false, false end
    local target = ceiling - maximum * Fence.hitShare(class, "torso", math.sqrt(distance2), helmet, vest,
        tonumber(data.ProjectALifeHealthRating), soak)
    if blocked then
        target = ceiling
        Fence.metrics.armourBlocked = (Fence.metrics.armourBlocked or 0) + 1
    end
    if target <= 0.001 then target = 0 end
    local simulation = ProjectALife.ShellSimulation
    if simulation ~= nil then simulation.setHealth(shell, target) else shell:setHealth(target) end
    Interop.hit(shell, attacker, math.max(0, ceiling - math.max(0, target)))
    Fence.metrics.silentBlows = (Fence.metrics.silentBlows or 0) + 1
    data.ProjectALifeLastHitAtMs = now
    pcall(function()
        if healthSystem ~= nil then
            healthSystem.onEngineHit(shell, attacker, "torso", nil, target, false, weapon, blocked)
        end
    end)
    if target <= 0 then
        local uid, generation = Fence.delegatedIdentity(shell)
        shell:Kill(attacker)
        Fence.metrics.weighedKills = (Fence.metrics.weighedKills or 0) + 1
        if uid ~= nil then Fence.killDelegated(shell, uid, generation, attacker, "silent") end
    end
    return true
end

function Fence.delegatedIdentity(shell)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.serverDelegates) ~= "function"
            or executor.serverDelegates() ~= true then return nil end
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    if type(shell.hasModData) == "function" and shell:hasModData() ~= true then return nil end
    local data = shell:getModData()
    if type(data) ~= "table" or type(data.ProjectALifeUID) ~= "string" then return nil end
    return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration)
end

function Fence.killDelegated(shell, uid, generation, killer, via)
    local executor = ProjectALife.Executor
    if executor == nil then return false end
    if type(executor.killDelegated) == "function" then
        local _, outcome = executor.killDelegated(shell, uid, via)
        if outcome ~= "handed" then return false end
    elseif type(executor.pushHealth) == "function" then
        executor.pushHealth(shell, uid, generation, killer, "player")
    else
        return false
    end
    Fence.metrics.delegatedKills = (Fence.metrics.delegatedKills or 0) + 1
    return true
end

Fence.engineEstimate = { rifle = 2.1, pistol = 1.3, shotgun = 40 }
function Fence.remoteShield(shell, weapon, bodyPart)
    if shell == nil or weapon == nil or type(weapon) == "string" or type(weapon.isAimedFirearm) ~= "function" then
        return false
    end
    local ok, aimed = pcall(weapon.isAimedFirearm, weapon)
    if not ok or aimed ~= true then return false end
    local _, blocked = Fence.shield(shell, bodyPart, weapon)
    if blocked then Fence.metrics.armourBlocked = (Fence.metrics.armourBlocked or 0) + 1 end
    return blocked == true
end

function Fence.applyRemoteHit(shell, player, weapon, bodyPart, shielded)
    local dealt = 0

    pcall(function()
        if shell == nil or weapon == nil or shell:isDead() then return end
        if weapon:isAimedFirearm() == true then return end
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        if data.ProjectALifeRemoteMeleeAtMs ~= nil then
            Fence.metrics.remoteMeleeOverlapped = (Fence.metrics.remoteMeleeOverlapped or 0) + 1
        end
        Fence.metrics.remoteMeleeUnweighed = (Fence.metrics.remoteMeleeUnweighed or 0) + 1
        data.ProjectALifeRemoteMeleeAtMs = type(getTimestampMs) == "function" and getTimestampMs() or 0
        data.ProjectALifeRemoteMeleeHealth = Fence.realHealth(shell)
    end)
    pcall(function()
        if shell == nil or shell:isDead() or weapon == nil or weapon:isAimedFirearm() ~= true then return end
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and healthSystem.invulnerable(shell) then return end
        local data = shell:getModData()
        local maximum = tonumber(data.ProjectALifeMaximumHealth) or tonumber(shell:getHealth()) or 1
        local class = Fence.fireClass(tostring(weapon:getAmmoType()), weapon:getFullType())
        local distance = 0
        pcall(function()
            local dx, dy = shell:getX() - player:getX(), shell:getY() - player:getY()
            distance = math.sqrt(dx * dx + dy * dy)
        end)
        local helmet, vest = Fence.armourOn(shell)
        if shielded == true then return end
        local armor = ProjectALife.Armor
        if armor ~= nil and type(armor.informed) == "function" and armor.informed(shell) then helmet, vest = false, false end

        local zone = string.find(string.lower(tostring(bodyPart or "")), "head", 1, true) and "head" or "torso"
        local extra = maximum * Fence.hitShare(class, zone, distance, zone == "head" or helmet, vest,
            tonumber(data.ProjectALifeHealthRating))
        if extra <= 0 then return end

        local health = math.max(0, Fence.realHealth(shell) - extra)
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, health) else shell:setHealth(health) end
        if health <= 0 then shell:Kill(player) end
        dealt = extra
    end)
    return dealt
end

function Fence.remoteShove(shell, player, stomp)
    local dealt = 0
    pcall(function()
        if shell == nil or shell:isDead() then return end
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and healthSystem.invulnerable(shell) then return end
        local before = Fence.realHealth(shell)
        if before <= 0 then return end
        local boot = stomp == true and isGrounded(shell)
        local target = Fence.shoveTarget(shell, before, boot, player)
        if target >= before then return end
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, target) else shell:setHealth(target) end
        if target <= 0 then shell:Kill(player) end
        if boot then
            Fence.metrics.stompsWeighed = (Fence.metrics.stompsWeighed or 0) + 1
        else
            Fence.metrics.shovesAbsorbed = (Fence.metrics.shovesAbsorbed or 0) + 1
        end
        dealt = before - target
    end)
    return dealt
end

function Fence.remoteFinisher(shell, player, weapon, shove)
    local finished = false
    pcall(function()
        if shell == nil or shell:isDead() then return end
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and healthSystem.invulnerable(shell) then return end
        local melee = weapon == nil or weapon:isAimedFirearm() ~= true
        local downedUntilMs
        pcall(function() downedUntilMs = shell:getModData().ProjectALifeDownedUntilMs end)
        if not Fence.finishesDowned(isGrounded(shell), melee, downedUntilMs, nowMs(),
                Fence.proneSinceMs[shell], shove == true) then
            return
        end
        Fence.pendingHit[shell] = nil
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, 0) else shell:setHealth(0) end
        shell:Kill(player)
        Fence.metrics.finishers = (Fence.metrics.finishers or 0) + 1
        finished = true
    end)
    return finished
end

Fence.outplay = { shoveMs = 900, meleeMs = 450, meleeEveryMs = 1200, cacheMs = 5000 }

function Fence.outplayEnabled(now)
    local cached = Fence.outplayCache
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Fence.outplay.cacheMs then return cached.on end
    local on = true
    local settings = ProjectALife.Settings
    if type(settings) == "table" and type(settings.read) == "function" then
        local ok, current = pcall(settings.read, nil, true)
        if ok and type(current) == "table" and current.outplayStagger == false then on = false end
    end
    Fence.outplayCache = { atMs = now, on = on }
    return on
end

function Fence.playerStagger(shell, shove, weapon, now)
    now = tonumber(now) or nowMs()
    if shell == nil or type(shell.getModData) ~= "function" or not Fence.outplayEnabled(now) then return false end
    local firearm = false
    if weapon ~= nil and type(weapon.isAimedFirearm) == "function" then
        local ok, value = pcall(weapon.isAimedFirearm, weapon)
        firearm = ok and value == true
    end
    if firearm and shove ~= true then return false end
    local data = shell:getModData()
    if type(data) ~= "table" then return false end
    if shove ~= true then
        if now < (tonumber(data.ProjectALifeOutplayNextAtMs) or -1e12) then return false end
        data.ProjectALifeOutplayNextAtMs = now + Fence.outplay.meleeEveryMs
    end
    local untilMs = now + (shove == true and Fence.outplay.shoveMs or Fence.outplay.meleeMs)
    if (tonumber(data.ProjectALifeStaggerUntilMs) or -1e12) < untilMs then data.ProjectALifeStaggerUntilMs = untilMs end
    Fence.metrics.outplayStaggers = (Fence.metrics.outplayStaggers or 0) + 1
    return true
end

local function onHitOwnedShell(shell, _wielder, _bodyPart, weapon)
    if shell == nil or Fence.owned[shell] ~= true then return end

    local shoving = false
    pcall(function()
        if _wielder == nil or _wielder.isDoShove == nil then return end
        shoving = _wielder:isDoShove() == true
    end)
    if not shoving then
        pcall(function()
            if weapon == nil then
                shoving = _wielder == nil or _wielder.isDoShove == nil
            else
                shoving = tostring(weapon:getFullType()) == "Base.BareHands"
            end
        end)
    end

    local playerBlow = false
    pcall(function() playerBlow = instanceof(_wielder, "IsoPlayer") == true end)
    local stomping = false
    if playerBlow then
        pcall(function()
            if _wielder.isDoStomp == nil then return end
            stomping = _wielder:isDoStomp() == true
        end)
        if not stomping and shoving and isGrounded(shell) then stomping = true end
        if stomping and not isGrounded(shell) then stomping = false end
    end

    local pushed = playerBlow and shoving and not stomping
    local blowFrom
    if playerBlow then blowFrom = _wielder end
    Fence.shoving[shell] = shoving or nil

    Fence.hitAudioPending[shell] = true

    if spectatorSide() and not Fence.authorityFor(shell) then
        pcall(function()
            local player = _wielder
            if player == nil or type(sendClientCommand) ~= "function" then return end
            if not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then return end

            local simulation = ProjectALife.ShellSimulation
            local owning = simulation ~= nil and type(simulation.isOwner) == "function"
                and simulation.isOwner(shell) == true
            local healthSystem = ProjectALife.Health
            if not pushed and not owning and healthSystem ~= nil
                    and type(healthSystem.stain) == "function" then
                local zone = "torso"
                if string.find(string.lower(tostring(_bodyPart)), "head", 1, true) then zone = "head" end
                healthSystem.stain(shell, zone)
            end
            local data = shell:getModData()
            Fence.hitReportSequence = (Fence.hitReportSequence or 0) + 1

            local uid, generation = data.ProjectALifeUID, data.ProjectALifeGeneration
            if uid == nil then
                pcall(function()
                    uid = shell:GetVariable("ALifeUID")
                    generation = tonumber(shell:GetVariable("ALifeGeneration"))
                end)
            end
            if uid == nil or uid == "" then return end
            sendClientCommand(player, "ProjectALife", "shellHit", {
                uid = uid,
                generation = generation,
                sequence = Fence.hitReportSequence,
                bodyPart = tostring(_bodyPart),
                weapon = tostring(weapon and weapon:getFullType() or ""),

                ranged = weapon ~= nil and weapon.isAimedFirearm ~= nil
                    and weapon:isAimedFirearm() == true,

                shove = shoving == true,

                stomp = stomping == true,
            })
        end)
        return
    end

    if (Fence.hitWindowUntilMs[shell] or 0) < nowMs() then
        Fence.hitWindowUntilMs[shell] = nowMs() + Fence.hitCleanupWindowMs
    end
    Fence.hitAudioPending[shell] = true

    if ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.enabled then
        pcall(function()
            local who = instanceof(_wielder, "IsoPlayer") and "player" or "npc/zombie"
            ProjectALife.BlackBox.note(shell, "hit", "by=" .. who
                .. " part=" .. tostring(_bodyPart)
                .. " weapon=" .. tostring(weapon and weapon:getFullType()))
        end)
    end

    local forgiven = false
    if playerBlow then
        local asked, answer = pcall(Fence.friendForgives, shell, _wielder, nowMs())
        forgiven = asked and answer == true
        if not stomping then pcall(Fence.playerStagger, shell, shoving, weapon, nowMs()) end
    end

    local after
    local shielded = false
    if shoving then
        after = Fence.absorbShove(shell, stomping, blowFrom)
    else
        after = Fence.weighPlayerHit(shell, _wielder, _bodyPart, weapon)
        local weighed = Fence.pendingHit[shell]
        shielded = weighed ~= nil and weighed.blocked == true
    end
    pcall(function()
        local healthSystem = ProjectALife.Health

        if healthSystem ~= nil and not pushed then
            healthSystem.onEngineHit(shell, _wielder, _bodyPart, nil, after, forgiven, weapon, shielded)
        end
    end)

    pcall(function()
        if not instanceof(_wielder, "IsoPlayer") or shell:isDead() then return end
        local healthSystem = ProjectALife.Health
        if healthSystem ~= nil and healthSystem.invulnerable(shell) then return end
        local melee = weapon == nil or weapon:isAimedFirearm() ~= true
        local downedUntilMs
        pcall(function() downedUntilMs = shell:getModData().ProjectALifeDownedUntilMs end)

        if shoving == true then return end
        if not Fence.finishesDowned(isGrounded(shell), melee, downedUntilMs, nowMs(),
                Fence.proneSinceMs[shell], false) then
            return
        end

        Fence.pendingHit[shell] = nil
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(shell, 0) else shell:setHealth(0) end
        local uid, generation = Fence.delegatedIdentity(shell)
        shell:Kill(_wielder)
        Fence.metrics.finishers = (Fence.metrics.finishers or 0) + 1
        if uid ~= nil then Fence.killDelegated(shell, uid, generation, _wielder, "finisher") end
    end)

    pcall(function()
        if not instanceof(_wielder, "IsoPlayer") then return end
        local data = shell:getModData()
        data.ProjectALifeLastHitAtMs = nowMs()

        pcall(function()
            local panic = ProjectALife.ModulePanic
            if panic == nil or type(panic.onShot) ~= "function" then return end
            local bullet = weapon ~= nil and weapon.isAimedFirearm ~= nil
                and weapon:isAimedFirearm() == true
            if not bullet or type(data.ProjectALifeUID) ~= "string" then return end
            local store = ProjectALife.ActorRegistry
            local record = store ~= nil and type(store.read) == "function"
                and store.read(data.ProjectALifeUID) or nil
            if record == nil then return end
            panic.onShot(record, shell, _wielder, true, nowMs())
        end)
        local perception = ProjectALife.Perception
        if perception ~= nil and type(perception.noteAttacker) == "function"
                and type(data.ProjectALifeUID) == "string" then
            local registry, tactics = ProjectALife.ActorRegistry,
                ProjectALife.SquadTactics
            local actor = registry and registry.read
                and registry.read(data.ProjectALifeUID) or nil
            local relations = ProjectALife.Relations
            if actor ~= nil and relations ~= nil
                    and type(relations.hostileToPlayer) == "function" then

                if pushed then
                    local talk = ProjectALife.Talk
                    if talk ~= nil and type(talk.onHitByPlayer) == "function" then
                        talk.onHitByPlayer(_wielder, shell, "fists")
                    end
                end
                if forgiven then return end
                local careful = ProjectALife.ModuleCareful
                local reputation = ProjectALife.Reputation
                local playerKey = reputation and reputation.playerKey and reputation.playerKey(_wielder)
                local grudges = actor.memory and actor.memory.hostileToPlayerKeys or {}
                if careful ~= nil and type(careful.turnGroup) == "function" and not grudges[playerKey or ""] then
                    pcall(careful.turnGroup, actor, shell, _wielder, true)
                    Fence.metrics.blowsTurned = (Fence.metrics.blowsTurned or 0) + 1
                end
            end

            perception.noteAttacker(data.ProjectALifeUID, _wielder,
                math.huge, "player")

            if actor ~= nil and tactics ~= nil
                    and type(tactics.reportThreat) == "function" then
                tactics.reportThreat(actor, _wielder, "player", nowMs())
            end
        end
    end)

    if isGrounded(shell) and not Fence.shrugHolds(shell, nowMs()) then
        local now = nowMs()
        local first = Fence.proneFirstMs[shell] or now
        Fence.proneFirstMs[shell] = first
        Fence.proneSinceMs[shell] = math.min(now, first + Fence.proneMaxMs - Fence.groundRestMs)
    end

    local staggerNow = nowMs()
    if type(shell.isDead) == "function"
            and shell:isDead() ~= true and not isGrounded(shell)
            and staggerNow >= (Fence.nextStaggerAtMs[shell] or 0) then
        local ranged = false
        pcall(function()
            ranged = weapon ~= nil and type(weapon.isAimedFirearm) == "function"
                and weapon:isAimedFirearm() == true
        end)

        local vaulting = false
        pcall(function()
            local state = actionState(shell)
            vaulting = state == "climbfence" or state == "climbwindow"
        end)

        if not vaulting then
            Fence.nextStaggerAtMs[shell] = staggerNow
                + (ranged and Fence.hitReactCooldownMs or Fence.meleeHitReactCooldownMs)
        end
        if not vaulting and (type(ZombRand) ~= "function"
                or ZombRand(100) < (ranged and Fence.rangedHitReactionPercent or Fence.hitReactionPercent)) then
            pcall(function()
                local data = shell:getModData()
                if type(data) == "table" then
                    data.ProjectALifeStaggerUntilMs = staggerNow + Fence.hitReactionMs
                end
            end)
            local animations = ProjectALife.Animations
            if animations ~= nil and type(animations.apply) == "function" then
                pcall(animations.apply, shell, "hit_react")
            end
        end
    end

    local now = nowMs()
    if not shielded and ProjectALife.AudioPolicy.allowsNPC() and now >= (Fence.nextHitReactAtMs[shell] or 0) then
        Fence.nextHitReactAtMs[shell] = now + 700
        pcall(function()
            local female = shell:isFemale() == true
            ProjectALife.AudioPolicy.nearSound(shell, female and "VoiceFemalePainFromHitBlunt"
                or "VoiceMalePainFromHitBlunt", { key = shell })
        end)
    end
end

function Fence.register()
    if Fence.registered then return true end
    if type(Events) ~= "table" or Events.OnZombieUpdate == nil
            or type(Events.OnZombieUpdate.Add) ~= "function" then
        return false, "on_zombie_update_unavailable"
    end
    Events.OnZombieUpdate.Add(onZombieUpdate)

    local rooms = Events.OnTickEvenPaused or Events.OnTick
    if rooms ~= nil and type(rooms.Add) == "function" then
        rooms.Add(Fence.repairOccupiedRooms)
    end
    if Events.OnHitZombie ~= nil and type(Events.OnHitZombie.Add) == "function" then
        Events.OnHitZombie.Add(onHitOwnedShell)
    end
    Fence.registered = true
    return true
end

function Fence.snapshot()
    return {
        registered = Fence.registered,
        tracked = Fence.metrics.tracked,
        updates = Fence.metrics.updates,
        failures = Fence.metrics.failures,
        roomsRebound = Fence.metrics.roomsRebound,
        lastError = Fence.metrics.lastError,
    }
end

Fence.onZombieUpdate = onZombieUpdate
Fence.onHitOwnedShell = onHitOwnedShell
Fence.silenceNativeVoice = silenceNativeVoice
Fence.silenceTraversalAudio = silenceTraversalAudio

return Fence
