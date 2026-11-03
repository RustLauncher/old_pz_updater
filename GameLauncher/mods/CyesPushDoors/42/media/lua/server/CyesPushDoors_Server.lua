if isClient() then return end

require "CyesPushDoors/Core"

local CPD = CyesPushDoors
local C = CPD.Config
CPD.mpDebug("SERVER_LOAD", "CyesPushDoors_Server.lua loaded")

local pendingDoors = {}
local doorCooldowns = {}
local forcedOpeningCooldowns = {}
local playerStrengthDoorLocks = {}
local playerStrengthSnapshotRequests = {}
local playerStrengthReadyClients = {}
local lastPlayerStrengthSnapshotAt = 0

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function playerOnlineId(player)
    local ok, id = pcall(function() return player:getOnlineID() end)
    if ok and id ~= nil then return id end
    return "unavailable"
end

local function playerKey(player)
    if not player then return "nil" end
    local id = player:getOnlineID()
    if id ~= nil and tonumber(id) and tonumber(id) >= 0 then
        return tostring(id)
    end
    return tostring(player:getUsername() or player)
end

local function playerStrengthDoorLockKey(player, door)
    return tostring(CPD.getDoorWorldKey(door)) .. "|" .. playerKey(player)
end

local function playerStrengthDoorLockDurationMs()
    return math.max(
        tonumber(C.PLAYER_STRENGTH_BLOCK_INPUT_LOCK_MS) or 1600,
        (tonumber(C.SERVER_DOOR_COOLDOWN_MS) or 900) + 250
    )
end

local function clearPlayerStrengthDoorLocksForDoor(door)
    local doorKey = tostring(CPD.getDoorWorldKey(door))
    for key, lock in pairs(playerStrengthDoorLocks) do
        if lock and tostring(lock.doorKey) == doorKey then
            playerStrengthDoorLocks[key] = nil
        end
    end
end

local function buildPlayerStrengthSnapshot()
    local entries = {}
    local players = nil
    if getOnlinePlayers then
        local ok, value = pcall(getOnlinePlayers)
        if ok then players = value end
    end
    if players then
        local okSize, size = pcall(function() return players:size() end)
        if okSize then
            for i = 0, size - 1 do
                local okPlayer, candidate = pcall(function() return players:get(i) end)
                if okPlayer and candidate then
                    local id = tonumber(playerOnlineId(candidate))
                    if id and id >= 0 then
                        entries[#entries + 1] = {
                            id = math.floor(id),
                            strength = math.floor(CPD.getStrength(candidate)),
                        }
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.id < b.id end)

    local encoded = {}
    for i = 1, #entries do
        encoded[i] = tostring(entries[i].id) .. ":" .. tostring(entries[i].strength)
    end
    return {
        strengths = table.concat(encoded, ","),
        serverTime = nowMs(),
        playerCount = #entries,
    }
end

local function sendPlayerStrengthSnapshot(recipient, snapshot)
    if not sendServerCommand then return false end
    local payload = snapshot or buildPlayerStrengthSnapshot()
    local ok, err = pcall(function()
        if recipient then
            sendServerCommand(
                recipient,
                "CyesPushDoors",
                "playerStrengthSnapshot",
                payload
            )
        else
            sendServerCommand(
                "CyesPushDoors",
                "playerStrengthSnapshot",
                payload
            )
        end
    end)
    CPD.mpDebug("PLAYER_STRENGTH_SNAPSHOT_SERVER",
        "target=" .. tostring(recipient and playerKey(recipient) or "broadcast") ..
        " players=" .. tostring(payload.playerCount) ..
        " sent=" .. tostring(ok) ..
        (ok and "" or " error=" .. tostring(err)))
    return ok
end

local function sendPlayerStrengthSnapshotsToReadyClients()
    if not getOnlinePlayers then return end
    local okPlayers, players = pcall(getOnlinePlayers)
    if not okPlayers or not players then return end

    local online = {}
    local snapshot = buildPlayerStrengthSnapshot()
    local okSize, size = pcall(function() return players:size() end)
    if not okSize then return end
    for i = 0, size - 1 do
        local okPlayer, candidate = pcall(function() return players:get(i) end)
        if okPlayer and candidate then
            local key = playerKey(candidate)
            online[key] = true
            if playerStrengthReadyClients[key] == true then
                sendPlayerStrengthSnapshot(candidate, snapshot)
            end
        end
    end
    for key in pairs(playerStrengthReadyClients) do
        if online[key] ~= true then playerStrengthReadyClients[key] = nil end
    end
end

local function isCoolingDown(key, now)
    local last = doorCooldowns[key]
    return last ~= nil and (now - last) < C.SERVER_DOOR_COOLDOWN_MS
end

local function candidateIsBetter(a, b)
    if b == nil then return true end
    if a.interaction ~= b.interaction then
        return a.interaction == true
    end
    if a.distanceSq ~= b.distanceSq then
        return a.distanceSq < b.distanceSq
    end
    return a.receivedAt < b.receivedAt
end




local function validateRequestEnvelope(player, door, transition)
    if not CPD.isEligiblePlayerTarget(player) then
        CPD.mpDebug("INVALID_OPENER", "reason=invalid-opener id=" .. tostring(playerOnlineId(player)))
        return false
    end
    if not door or not CPD.isSupportedDoor(door) then
        return false
    end

    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" and transition ~= "close" then return false end
    if not garage and transition == "close" and not CPD.supportsClosingControlImpact(door) then return false end

    local sq = door:getSquare()
    if not sq or sq:getZ() ~= player:getZ() then return false end

    local distSq = CPD.getPlayerDoorDistanceSq(player, door)
    if CPD.isDoubleDoor(door) then
        local parts = CPD.getDoubleDoorParts(door)
        for i = 1, #parts do
            local candidateDistance = CPD.getPlayerDoorDistanceSq(player, parts[i])
            if candidateDistance < distSq then distSq = candidateDistance end
        end
    end

    local maxDist = tonumber(C.MAX_SERVER_VALIDATION_DISTANCE) or 2.25
    return distSq <= (maxDist * maxDist)
end

local function restoreActivePlayerStrengthDoorLock(player, door, transition)
    local now = nowMs()
    local lockKey = playerStrengthDoorLockKey(player, door)
    local lock = playerStrengthDoorLocks[lockKey]
    if not lock then return false end
    if (tonumber(lock.expiresAt) or 0) <= now then
        playerStrengthDoorLocks[lockKey] = nil
        return false
    end

    local doorKey = CPD.getDoorWorldKey(door)
    lock.expiresAt = now + playerStrengthDoorLockDurationMs()
    lock.player = player
    lock.door = door
    lock.doorKey = doorKey
    lock.transition = transition
    pendingDoors[doorKey] = nil
    doorCooldowns[doorKey] = now
    local restored = CPD.restoreDoorAfterPlayerStrengthBlock(
        player,
        door,
        transition,
        lock.desiredOpen
    )
    CPD.mpDebug("SERVER_PLAYER_STRENGTH_LOCK_RESTORE",
        "player=" .. tostring(player and player:getUsername()) ..
        " key=" .. tostring(doorKey) ..
        " transition=" .. tostring(transition) ..
        " canonicalOpen=" .. tostring(lock.desiredOpen) ..
        " restored=" .. tostring(restored))
    return true
end

local function enforcePlayerStrengthInteractionBlock(
    player,
    door,
    preferredImpactSquare,
    transition
)
    local canonicalOpen = transition == "close"
    local blocked, state, reason = CPD.enforcePlayerStrengthInteractionBlock(
        player,
        door,
        preferredImpactSquare,
        transition,
        nil,
        canonicalOpen
    )
    if not blocked then
        CPD.mpDebug("SERVER_PLAYER_STRENGTH_CHECK",
            "blocked=false reason=" .. tostring(reason or "strength-allowed") ..
            " key=" .. tostring(CPD.getDoorWorldKey(door)))
        return false
    end

    local now = nowMs()
    local doorKey = CPD.getDoorWorldKey(door)
    playerStrengthDoorLocks[playerStrengthDoorLockKey(player, door)] = {
        desiredOpen = canonicalOpen,
        expiresAt = now + playerStrengthDoorLockDurationMs(),
        player = player,
        door = door,
        doorKey = doorKey,
        transition = transition,
    }
    pendingDoors[doorKey] = nil
    doorCooldowns[doorKey] = now
    CPD.mpDebug("SERVER_EARLY_PLAYER_STRENGTH_BLOCK",
        "player=" .. tostring(player and player:getUsername()) ..
        " key=" .. tostring(doorKey) ..
        " transition=" .. tostring(transition) ..
        " canonicalOpen=" .. tostring(canonicalOpen) ..
        " openerStrength=" .. tostring(state and state.openerStrength) ..
        " blockerStrength=" .. tostring(state and state.blockerStrength) ..
        " restored=" .. tostring(state and state.doorRestored))
    return true
end

local function queueDoorReport(player, args, door)
    local now = nowMs()
    local key = CPD.getDoorWorldKey(door)
    if isCoolingDown(key, now) then return nil, nil, "door-cooldown" end

    local recovering, remainingMs, recoveryBand = CPD.isImpactRecoveryActive(player)
    if recovering then
        return nil, nil, "muscle-recovery:" .. tostring(recoveryBand) .. ":" .. tostring(remainingMs)
    end

    local pending = pendingDoors[key]
    if not pending then
        pending = {
            firstAt = now,
            lastAt = now,
            hasInteraction = false,
            candidates = {},
        }
        pendingDoors[key] = pending
    else
        pending.lastAt = now
    end

    local candidate = {
        player = player,
        args = args,
        door = door,
        interaction = args.interaction == true,
        distanceSq = CPD.getPlayerDoorDistanceSq(player, door),
        receivedAt = now,
    }

    if candidate.interaction then pending.hasInteraction = true end

    local pKey = playerKey(player)
    local existing = pending.candidates[pKey]
    if existing == nil or candidateIsBetter(candidate, existing) then
        pending.candidates[pKey] = candidate
    end

    return key, pending, nil
end

local function isAttachedServerDoor(door)
    if not door or not CPD.isSupportedDoor(door) then return false end
    local sq = door:getSquare()
    if not sq then return false end
    local index = door:getObjectIndex()
    return index == nil or tonumber(index) == nil or tonumber(index) >= 0
end

local function serverDoorStateMatches(door, transition)
    if not isAttachedServerDoor(door) then return false end
    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" and transition ~= "close" then return false end
    if not garage and transition == "close" and not CPD.supportsClosingControlImpact(door) then return false end

    local ok, open = pcall(function() return door:IsOpen() end)
    if not ok then return false end
    if transition == "close" then return open == false end
    return open == true
end

local function resolveCandidateDoor(candidate, key)
    if not candidate then return nil end

    
    
    
    local door = candidate.door
    if isAttachedServerDoor(door) and CPD.getDoorWorldKey(door) == key then
        return door
    end

    door = CPD.findDoor(candidate.args)
    if isAttachedServerDoor(door) and CPD.getDoorWorldKey(door) == key then
        candidate.door = door
        return door
    end
    return nil
end

local function resolvePendingDoor(key, pending)
    if not pending or pendingDoors[key] ~= pending then return false, "missing" end

    local best = nil
    local bestDoor = nil

    for _, candidate in pairs(pending.candidates) do
        local candidateDoor = resolveCandidateDoor(candidate, key)
        if candidateDoor and serverDoorStateMatches(candidateDoor, candidate.args.transition) then
            
            
            
            
            if candidateIsBetter(candidate, best) then
                best = candidate
                bestDoor = candidateDoor
            end
        end
    end

    local now = nowMs()
    local age = now - (pending.firstAt or now)
    if not best or not bestDoor then
        if pending.hasInteraction and age < (tonumber(C.SERVER_INTERACTION_STATE_GRACE_MS) or 500) then
            return false, "state-wait"
        end

        pendingDoors[key] = nil
        CPD.mpDebug("SERVER_RESOLVE_DROP",
            "no valid candidate key=" .. tostring(key) ..
            " interaction=" .. tostring(pending.hasInteraction == true) ..
            " ageMs=" .. tostring(age))
        return false, "invalid"
    end

    pendingDoors[key] = nil
    doorCooldowns[key] = now

    local preferred = CPD.findPreferredImpactSquare(best.args, bestDoor)
    local transition = best.args.transition or (CPD.isGarageDoor(bestDoor) and "close" or "open")
    CPD.mpDebug("SERVER_RESOLVE_START",
        "player=" .. tostring(best.player and best.player:getUsername()) ..
        " transition=" .. tostring(transition) ..
        " interaction=" .. tostring(best.interaction == true) ..
        " kind=" .. tostring(best.args and best.args.interactionKind or "unknown") ..
        " queueAgeMs=" .. tostring(age) ..
        " doorKey=" .. tostring(key))

    local ok, result = pcall(CPD.resolveDoorImpact, best.player, bestDoor, preferred, transition)
    if not ok then
        if C.DEBUG == true then
            print("[Cye's Push Doors!] Server impact error: " .. tostring(result))
        end
        CPD.mpDebug("SERVER_RESOLVE_ERROR", tostring(result))
    else
        CPD.mpDebug("SERVER_RESOLVE_END", "resolveDoorImpact returned=" .. tostring(result))
    end
    return ok == true, "resolved"
end

local function processPendingDoors()
    local now = nowMs()
    for key, pending in pairs(pendingDoors) do
        if pending then
            local age = now - (pending.firstAt or now)
            if pending.hasInteraction then
                local _, status = resolvePendingDoor(key, pending)
                if status == "state-wait" and C.DEBUG == true then
                    
                    
                    CPD.mpDebug("SERVER_STATE_WAIT",
                        "waiting for vanilla door state key=" .. tostring(key) ..
                        " ageMs=" .. tostring(age))
                end
            elseif age >= C.SERVER_REPORT_WINDOW_MS then
                resolvePendingDoor(key, pending)
            end
        end
    end

    for key, last in pairs(doorCooldowns) do
        if (now - last) > 5000 then
            doorCooldowns[key] = nil
        end
    end
    for key, last in pairs(forcedOpeningCooldowns) do
        if (now - last) > 5000 then
            forcedOpeningCooldowns[key] = nil
        end
    end
    for key, lock in pairs(playerStrengthDoorLocks) do
        if (tonumber(lock and lock.expiresAt) or 0) <= now then
            playerStrengthDoorLocks[key] = nil
        elseif lock.door and lock.player and isAttachedServerDoor(lock.door) then
            local current = CPD.getLogicalDoorOpenState(lock.door)
            if current ~= (lock.desiredOpen == true) then
                local restored = CPD.restoreDoorAfterPlayerStrengthBlock(
                    lock.player,
                    lock.door,
                    lock.transition,
                    lock.desiredOpen
                )
                local doorKey = CPD.getDoorWorldKey(lock.door)
                pendingDoors[doorKey] = nil
                doorCooldowns[doorKey] = now
                CPD.mpDebug("SERVER_PLAYER_STRENGTH_LOCK_RECONCILE",
                    "key=" .. tostring(doorKey) ..
                    " canonicalOpen=" .. tostring(lock.desiredOpen) ..
                    " restored=" .. tostring(restored))
            end
        end
    end
    for key, last in pairs(playerStrengthSnapshotRequests) do
        if (now - last) > 5000 then
            playerStrengthSnapshotRequests[key] = nil
        end
    end

    local snapshotInterval = math.max(
        250,
        tonumber(C.PLAYER_STRENGTH_SNAPSHOT_INTERVAL_MS) or 500
    )
    if now - lastPlayerStrengthSnapshotAt >= snapshotInterval then
        lastPlayerStrengthSnapshotAt = now
        sendPlayerStrengthSnapshotsToReadyClients()
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= "CyesPushDoors" then return end

    if command == "clientReady" then
        if not player then return end
        local key = playerKey(player)
        playerStrengthReadyClients[key] = true
        local clientProtocol = tonumber(args and args.protocol) or 1
        local serverProtocol = tonumber(C.NETWORK_PROTOCOL) or 1
        if clientProtocol ~= serverProtocol and sendServerCommand then
            pcall(function()
                sendServerCommand(player, "CyesPushDoors", "versionMismatch", {
                    clientVersion = tostring(args and args.version or "unknown"),
                    clientProtocol = clientProtocol,
                    serverVersion = tostring(C.VERSION or "unknown"),
                    serverProtocol = serverProtocol,
                })
            end)
        end
        sendPlayerStrengthSnapshot(player)
        return
    end

    if command == "requestPlayerStrengthSnapshot" then
        if not CPD.isEligiblePlayerTarget(player) then return end
        local now = nowMs()
        local key = playerKey(player)
        playerStrengthReadyClients[key] = true
        local cooldown = math.max(
            100,
            tonumber(C.PLAYER_STRENGTH_SNAPSHOT_REQUEST_COOLDOWN_MS) or 250
        )
        if now - (tonumber(playerStrengthSnapshotRequests[key]) or 0) >= cooldown then
            playerStrengthSnapshotRequests[key] = now
            CPD.mpDebug("PLAYER_STRENGTH_SNAPSHOT_REQUEST",
                "player=" .. tostring(player and player:getUsername()))
            sendPlayerStrengthSnapshot(player)
        end
        return
    end

    if command == "zombieImpactAck" then
        CPD.mpDebug("SERVER_ACK",
            "player=" .. tostring(player and player:getUsername()) ..
            " zombieId=" .. tostring(args and args.id) ..
            " hp=" .. tostring(args and args.health) ..
            " token=" .. tostring(args and args.syncToken))
        return
    end

    if command == "forceOpenDoor" then
        if not args then return end
        local useCustomAnimation = args.forcedOpeningUseAnimation
        if useCustomAnimation == nil then
            useCustomAnimation = true
        else
            useCustomAnimation = useCustomAnimation == true
        end
        local forcedActionAnim = args.forcedOpeningAction
        if useCustomAnimation and CPD.getForcedOpeningAnimationSide(forcedActionAnim) == nil then
            CPD.mpDebug("FORCED_OPENING_REJECT", "reason=invalid-animation")
            return
        end
        if not useCustomAnimation then forcedActionAnim = nil end
        local door = CPD.findDoor(args)
        if not validateRequestEnvelope(player, door, "open") then
            CPD.mpDebug("FORCED_OPENING_REJECT", "reason=invalid-envelope")
            return
        end

        local now = nowMs()
        local pKey = playerKey(player)
        local lastPlayerRequest = tonumber(forcedOpeningCooldowns[pKey]) or 0
        local requestCooldown = tonumber(C.FORCED_OPENING_REQUEST_COOLDOWN_MS) or 1200
        if now - lastPlayerRequest < requestCooldown then
            CPD.mpDebug("FORCED_OPENING_REJECT", "reason=player-cooldown")
            return
        end

        local doorKey = CPD.getDoorWorldKey(door)
        if isCoolingDown(doorKey, now) then
            CPD.mpDebug("FORCED_OPENING_REJECT", "reason=door-cooldown key=" .. tostring(doorKey))
            return
        end

        forcedOpeningCooldowns[pKey] = now
        pendingDoors[doorKey] = nil
        clearPlayerStrengthDoorLocksForDoor(door)
        doorCooldowns[doorKey] = now
        local ok, success, reason = pcall(
            CPD.resolveForcedDoorOpening,
            player,
            door,
            forcedActionAnim,
            useCustomAnimation
        )
        if not ok then
            if C.DEBUG == true then
                print("[Cye's Push Doors!] Forced opening error: " .. tostring(success))
            end
            CPD.mpDebug("FORCED_OPENING_ERROR", tostring(success))
        else
            CPD.mpDebug("FORCED_OPENING_SERVER_END",
                "success=" .. tostring(success == true) ..
                " reason=" .. tostring(reason or "none") ..
                " customAnimation=" .. tostring(useCustomAnimation) ..
                " key=" .. tostring(doorKey))
        end
        return
    end

    if command ~= "doorOpened" or not args then return end

    CPD.mpDebug("SERVER_RECEIVE",
        "doorOpened player=" .. tostring(player and player:getUsername()) ..
        " transition=" .. tostring(args.transition) ..
        " door=" .. tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z) ..
        " index=" .. tostring(args.index) ..
        " interaction=" .. tostring(args.interaction == true) ..
        " kind=" .. tostring(args.interactionKind or "unknown"))

    local door = CPD.findDoor(args)
    if door and args.transition == "close" and not CPD.isGarageDoor(door) and args.interaction ~= true then
        CPD.log("Rejected non-interaction closing control report from " .. tostring(player and player:getUsername()))
        return
    end
    local envelopeValid = validateRequestEnvelope(player, door, args.transition)
    local preferredImpactSquare = envelopeValid and CPD.findPreferredImpactSquare(args, door) or nil
    local impactSideValid = preferredImpactSquare ~= nil
    local stateValid = envelopeValid and CPD.validateServerRequest(player, door, args.transition) or false

    CPD.mpDebug("SERVER_VALIDATE",
        "doorFound=" .. tostring(door ~= nil) ..
        " envelope=" .. tostring(envelopeValid) ..
        " state=" .. tostring(stateValid) ..
        " impactSide=" .. tostring(impactSideValid) ..
        " worldKey=" .. tostring(door and CPD.getDoorWorldKey(door) or "nil"))

    if not envelopeValid then
        CPD.log("Rejected door transition envelope from " .. tostring(player and player:getUsername()))
        return
    end

    if not impactSideValid then
        CPD.log("Rejected door transition without a valid frozen impact side from " .. tostring(player and player:getUsername()))
        CPD.mpDebug("SERVER_IMPACT_SIDE_REJECT",
            "player=" .. tostring(player and player:getUsername()) ..
            " transition=" .. tostring(args.transition) ..
            " doorKey=" .. tostring(door and CPD.getDoorWorldKey(door) or "nil"))
        return
    end

    if args.interaction == true then
        if restoreActivePlayerStrengthDoorLock(
            player,
            door,
            args.transition
        ) then
            return
        end
        if args.transition == "open" or stateValid then
            if enforcePlayerStrengthInteractionBlock(
                player,
                door,
                preferredImpactSquare,
                args.transition
            ) then
                return
            end
        end
        clearPlayerStrengthDoorLocksForDoor(door)
    end

    if args.interaction ~= true and not stateValid then
        CPD.log("Rejected scanner door transition with stale server state from " .. tostring(player and player:getUsername()))
        return
    end

    local key, pending, queueReason = queueDoorReport(player, args, door)
    if not key or not pending then
        CPD.mpDebug("SERVER_QUEUE_SKIP",
            "reason=" .. tostring(queueReason or "unknown") ..
            " key=" .. tostring(door and CPD.getDoorWorldKey(door) or "nil") ..
            " interaction=" .. tostring(args.interaction == true))
        return
    end

    CPD.mpDebug("SERVER_QUEUE",
        "door report queued interaction=" .. tostring(args.interaction == true) ..
        " kind=" .. tostring(args.interactionKind or
            (CPD.isGarageDoor(door) and "garage") or
            (CPD.isDoubleDoor(door) and "double-door") or "door") ..
        " stateReady=" .. tostring(stateValid))

    if args.interaction == true then
        if stateValid then
            CPD.mpDebug("SERVER_FAST_RESOLVE",
                "interaction state ready; resolving immediately key=" .. tostring(key))
            resolvePendingDoor(key, pending)
        else
            CPD.mpDebug("SERVER_STATE_WAIT",
                "interaction arrived before vanilla door state key=" .. tostring(key) .. " ageMs=0")
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)

local function onTick()
    CPD.updatePendingZombieDamage()
    processPendingDoors()
end

if Events and Events.OnTick then Events.OnTick.Add(onTick) end
