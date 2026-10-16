if isServer() then return end

local pendingServerCommands = {}
local activeServerCommandHandler = nil
local MAX_PENDING_SERVER_COMMANDS = 128

local function routeServerCommand(module, command, args)
    if module ~= "CyesPushDoors" then return end
    if activeServerCommandHandler then
        activeServerCommandHandler(module, command, args)
        return
    end
    if #pendingServerCommands >= MAX_PENDING_SERVER_COMMANDS then
        table.remove(pendingServerCommands, 1)
    end
    pendingServerCommands[#pendingServerCommands + 1] = {
        module = module,
        command = command,
        args = args,
    }
end

Events.OnServerCommand.Add(routeServerCommand)

require "CyesPushDoors/Core"
require "CyesPushDoors/Settings"
require "TimedActions/ISCPDKickDoorAction"
require "TimedActions/ISCPDForceDoorPrepareAction"
require "TimedActions/ISCPDForceDoorAction"
require "CyesPushDoors/ForcedOpening"
require "CyesPushDoors/Hook"
require "CyesPushDoors/TargetOutline"

local CPD = CyesPushDoors
local C = CPD.Config
local S = CPD.Settings
CPD.mpDebug("CLIENT_LOAD", "CyesPushDoors_Client.lua loaded")

local function findZombie(args, allowDead)
    if not args or args.x == nil or args.y == nil or args.z == nil then return nil end
    local id = tonumber(args.id)
    if id == nil or id < 0 then return nil end
    local cx, cy, cz = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not cx or not cy or not cz then return nil end

    for radius = 0, 2 do
        for x = cx - radius, cx + radius do
            for y = cy - radius, cy + radius do
                if radius == 0 or x == cx - radius or x == cx + radius or y == cy - radius or y == cy + radius then
                    local sq = getCell():getGridSquare(x, y, cz)
                    local moving = sq and sq:getMovingObjects() or nil
                    if moving then
                        for i = 0, moving:size() - 1 do
                            local object = moving:get(i)
                            local eligible = object and CPD.isEligibleZombieTarget(object)
                            if not eligible and allowDead == true and object and instanceof then
                                local okZombie, isZombie = pcall(instanceof, object, "IsoZombie")
                                eligible = okZombie and isZombie == true
                            end
                            if eligible then
                                local onlineId = tonumber(object:getOnlineID())
                                if onlineId == id then
                                    return object
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function findLocalPlayer(args)
    local wantedId = args and tonumber(args.playerId) or nil

    if wantedId ~= nil and getNumActivePlayers and getSpecificPlayer then
        local count = getNumActivePlayers()
        for i = 0, count - 1 do
            local player = getSpecificPlayer(i)
            if player and tonumber(player:getOnlineID()) == wantedId then
                return player
            end
        end
    end

    return getPlayer and getPlayer() or nil
end

local function combatTextAvailable()
    return CombatText ~= nil
        and CombatTextCache ~= nil
        and CombatTextCache.TrackingList ~= nil
        and CombatTextCache.HealthBarManagers ~= nil
end

local function getCombatTextEntityId(zombie)
    local okUid, uid = pcall(function() return zombie:getUID() end)
    if okUid and uid ~= nil then return uid end

    if CombatText and CombatText.Fn and type(CombatText.Fn.getEntityId) == "function" then
        local okLegacy, legacyUid = pcall(CombatText.Fn.getEntityId, zombie)
        if okLegacy and legacyUid ~= nil then return legacyUid end
    end

    return nil
end

local function getCombatTextTimestamp()
    local ok, value = pcall(function()
        return getGameTime():getCalender():getTimeInMillis()
    end)
    if ok and value then return value end
    return getTimestampMs and getTimestampMs() or 0
end

function CPD.onCombatTextDoorHit(zombie, oldHealth, newHealth)
    if not zombie or not combatTextAvailable() then return false end

    oldHealth = tonumber(oldHealth)
    newHealth = tonumber(newHealth)
    if not oldHealth or not newHealth or newHealth >= oldHealth then return false end

    local uid = getCombatTextEntityId(zombie)
    if uid == nil then return false end

    local oldHp = oldHealth * 100.0
    local newHp = math.max(0, newHealth * 100.0)
    local lethal = newHealth <= 0 or zombie:isDead()
    local tick = getCombatTextTimestamp()
    local tracking = CombatTextCache.TrackingList[uid]

    if tracking == nil then
        tracking = {
            fullHp = oldHp,
            hp = oldHp,
            isDead = lethal,
            entity = zombie,
            isOnFire = zombie:isOnFire(),
            isBleeding = false,
            weapon = nil,
            isCrit = false,
            tick = tick,
        }
        CombatTextCache.TrackingList[uid] = tracking
        CombatTextCache.TrackingListCount = (tonumber(CombatTextCache.TrackingListCount) or 0) + 1
    else
        tracking.entity = zombie
        tracking.hp = oldHp
        if tracking.fullHp == nil or tonumber(tracking.fullHp) == nil or tonumber(tracking.fullHp) < oldHp then
            tracking.fullHp = oldHp
        end
        tracking.isDead = lethal
        tracking.isOnFire = zombie:isOnFire()
        tracking.isBleeding = false
        tracking.weapon = nil
        tracking.isCrit = false
        tracking.tick = tick
    end

    for _, manager in pairs(CombatTextCache.HealthBarManagers) do
        if manager then
            pcall(function() manager:onHit(uid, nil, false, tracking) end)
            local bar = manager.barList and manager.barList[uid] or nil
            if bar then
                bar.entity = zombie
                bar.weapon = nil
                bar.isCrit = false
                bar.isDead = false
                bar.currentHp = oldHp
                if not bar.maxHp or bar.maxHp < oldHp then bar.maxHp = oldHp end
                bar.hpChange = 0
                bar.isChangingHp = false
                bar.hpChangeStart = nil

                if lethal and type(manager.onZombieDead) == "function" then
                    pcall(function() manager:onZombieDead(uid, zombie:isOnFire()) end)
                end
            end
        end
    end

    CPD.log("Combat Text tracked door hit uid=" .. tostring(uid) ..
        " hp=" .. string.format("%.2f", oldHp) .. "->" .. string.format("%.2f", newHp) ..
        " lethal=" .. tostring(lethal))
    return true
end

local function onServerCommand(module, command, args)
    if module ~= "CyesPushDoors" then return end

    if command == "playerStrengthSnapshot" then
        CPD.updateAuthoritativePlayerStrengthSnapshot(
            args and args.strengths or ""
        )
        return
    end

    if command == "versionMismatch" then
        if CPD._networkVersionMismatchReported ~= true then
            CPD._networkVersionMismatchReported = true
            if C.DEBUG == true then
                print("[Cye's Push Doors!] Multiplayer version mismatch: client " ..
                    tostring(C.VERSION) .. ", server " ..
                    tostring(args and args.serverVersion or "unknown") .. ".")
            end
        end
        CPD.mpDebug(
            "NETWORK_VERSION_MISMATCH",
            "client=" .. tostring(C.VERSION) ..
            " server=" .. tostring(args and args.serverVersion) ..
            " protocol=" .. tostring(args and args.serverProtocol)
        )
        return
    end

    if command == "impactSound" then
        local player = findLocalPlayer(args)
        if S.soundEffectsEnabled() and player and args and args.sound then
            CPD.playImpactSoundLocal(player, args.sound)
        end
        return
    end

    if command == "effortVoice" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.playEffortVoiceLocal(player, args.variant)
        end
        return
    end

    if command == "strainThreshold" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showArmStrainThresholdLocal(player, args.band)
        end
        return
    end

    if command == "enduranceThreshold" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showEnduranceThresholdLocal(player, args.band)
        end
        return
    end

    if command == "combinedThreshold" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showCombinedThresholdLocal(player, args.strainBand, args.enduranceBand)
        end
        return
    end

    if command == "strainBlocked" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showArmStrainBlockedLocal(player, args.lineIndex)
        end
        return
    end

    if command == "enduranceBlocked" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showEnduranceBlockedLocal(player, args.lineIndex)
        end
        return
    end

    if command == "impactBlockedDialogue" then
        local player = findLocalPlayer(args)
        if player and args and args.textKey then
            CPD.showImpactBlockedLocal(player, args.textKey)
        end
        return
    end

    if command == "crowdBlockedDialogue" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showDoorCrowdBlockedLocal(player, args.lineIndex)
        end
        return
    end

    if command == "playerStrengthBlockedDialogue" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showPlayerStrengthBlockedLocal(player, args.lineIndex)
        end
        return
    end

    if command == "forcedOpeningMessage" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.showForcedOpeningMessageLocal(player, args.reason, args.lineIndex)
        end
        return
    end

    if command == "forcedDoorTransition" then
        if args then
            local door = CPD.findDoor(args)
            CPD.markForcedDoorTransition(args.doorKey or door)
            if args.playerStrengthBlocked == true then
                CPD.markAuthoritativePlayerStrengthDoorBlock(
                    args.doorKey or door,
                    args.playerStrengthBlockCacheMs,
                    args.playerStrengthBlockInputLockMs
                )
            end
        end
        return
    end

    if command == "forcedFracture" then
        local player = findLocalPlayer(args)
        if player and args and args.side then
            if args.part then
                CPD.applyForcedOpeningFracturePart(player, args.side, args.part, args.duration)
            else
                CPD.applyForcedOpeningFractureSide(player, args.side, args.duration)
            end
        end
        return
    end

    if command == "enduranceSync" then
        local player = findLocalPlayer(args)
        if player and args and args.endurance ~= nil then
            CPD.setEnduranceAbsolute(player, tonumber(args.endurance))
        end
        return
    end

    if command == "doorHealth" then
        local door = CPD.findDoor(args)
        if door and args.health ~= nil then
            door:setHealth(tonumber(args.health) or door:getHealth())
        end
        return
    end

    if command == "armStrainSync" then
        local player = findLocalPlayer(args)
        if player then CPD.setArmStrainAbsolute(player, args) end
        return
    end

    if command == "combatTextHit" then
        local zombie = findZombie(args, true)
        if zombie and args.oldHealth ~= nil and args.newHealth ~= nil then
            CPD.onCombatTextDoorHit(zombie, tonumber(args.oldHealth), tonumber(args.newHealth))
        end
        return
    end

    if command == "playerImpact" then
        if args and args.knockedDown == true then
            local player = findLocalPlayer(args)
            if player and player:isAlive() then
                pcall(function() player:setHitForce(0.0) end)
                pcall(function() player:setFallOnFront(false) end)
                pcall(function() player:setKnockedDown(true) end)
            end
        end
        return
    end

    if command == "kickDoorAnimation" then
        local player = findLocalPlayer(args)
        if player and args then
            CPD.playKickDoorAnimationForOpener(
                player,
                nil,
                args.token,
                args.garage == true,
                args.transition,
                args.actionAnim
            )
        end
        return
    end

    if command == "zombieImpact" then
        CPD.mpDebug("CLIENT_RECEIVE",
            "zombieImpact id=" .. tostring(args and args.id) ..
            " hp=" .. tostring(args and args.health) ..
            " knock=" .. tostring(args and args.knockedDown) ..
            " stagger=" .. tostring(args and args.staggered) ..
            " staggerAnim=" .. tostring(args and args.staggerAnimation) ..
            " pos=" .. tostring(args and args.x) .. "," .. tostring(args and args.y) .. "," .. tostring(args and args.z))
        local zombie = findZombie(args)
        if not zombie then
            CPD.mpDebug("CLIENT_FIND_FAIL", "Could not find zombie for server payload id=" .. tostring(args and args.id))
            return
        end
        CPD.mpDebug("CLIENT_FIND_OK",
            "found zombie id=" .. tostring(zombie:getOnlineID()) ..
            " currentHp=" .. tostring(zombie:getHealth()))
        if args.health ~= nil then
            local expected = tonumber(args.health) or zombie:getHealth()
            local before = zombie:getHealth()
            zombie:setHealth(expected)
            CPD.mpDebug("CLIENT_HEALTH_APPLY",
                "zombieId=" .. tostring(zombie:getOnlineID()) ..
                " hp=" .. tostring(before) .. "->" .. tostring(zombie:getHealth()) ..
                " expected=" .. tostring(expected))
            CPD.queueZombieDamageVerification(nil, zombie, expected, expected <= 0)
        end

        if args.slidingAnimated == true then
            if S.animationsEnabled() and args.hitAnimation ~= nil and CPD and CPD.playSlidingDoorAnimation then
                CPD.playSlidingDoorAnimation(zombie, tostring(args.hitAnimation))
            end
        elseif args.crawlerStunned == true then
            pcall(function() zombie:setHitLegsWhileOnFloor(true) end)
            pcall(function() zombie:setHitTime(C.CRAWLER_STUN_HIT_TIME) end)
        elseif args.knockedDown == true then
            pcall(function() zombie:setHitForce(0.0) end)
            local alreadyDown = false
            pcall(function() alreadyDown = zombie:isOnFloor() == true end)
            if not alreadyDown then
                pcall(function() alreadyDown = zombie:isKnockedDown() == true end)
            end
            if not alreadyDown then
                pcall(function() zombie:setKnockedDown(true) end)
            end
        elseif args.staggered == true then
            if S.animationsEnabled() and args.staggerAnimation ~= nil and CPD and CPD.playDoorStaggerAnimation then
                CPD.playDoorStaggerAnimation(zombie, tostring(args.staggerAnimation))
            end
        end
        CPD.mpDebug("CLIENT_REACTION_APPLY",
            "zombieId=" .. tostring(zombie:getOnlineID()) ..
            " knock=" .. tostring(args.knockedDown == true) ..
            " stagger=" .. tostring(args.staggered == true) ..
            " staggerAnim=" .. tostring(args.staggerAnimation) ..
            " crawler=" .. tostring(args.crawlerStunned == true) ..
            " sliding=" .. tostring(args.slidingAnimated == true))

        if sendClientCommand then
            local ack = {
                id = tonumber(zombie:getOnlineID()),
                health = tonumber(zombie:getHealth()),
                syncToken = args and args.syncToken or nil,
            }
            local okAck, errAck = pcall(function()
                sendClientCommand("CyesPushDoors", "zombieImpactAck", ack)
            end)
            if okAck then
                CPD.mpDebug("CLIENT_ACK",
                    "zombieId=" .. tostring(ack.id) ..
                    " hp=" .. tostring(ack.health) ..
                    " token=" .. tostring(ack.syncToken))
            else
                CPD.mpDebug("CLIENT_ACK_FAIL", tostring(errAck))
            end
        end
    end
end

activeServerCommandHandler = onServerCommand
for i = 1, #pendingServerCommands do
    local pending = pendingServerCommands[i]
    onServerCommand(pending.module, pending.command, pending.args)
end
pendingServerCommands = {}

local lastClientReadyAt = -1000

local function requestInitialPlayerStrengthSnapshot()
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    if sendClientCommand and now - lastClientReadyAt >= 1000 then
        lastClientReadyAt = now
        pcall(function()
            sendClientCommand("CyesPushDoors", "clientReady", {
                version = tostring(C.VERSION or "unknown"),
                protocol = tonumber(C.NETWORK_PROTOCOL) or 1,
            })
        end)
    end
    if type(CPD.requestPlayerStrengthSnapshot) == "function" then
        pcall(CPD.requestPlayerStrengthSnapshot, false)
    end
end

if Events.OnGameStart then
    Events.OnGameStart.Add(requestInitialPlayerStrengthSnapshot)
end
if Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(requestInitialPlayerStrengthSnapshot)
end
