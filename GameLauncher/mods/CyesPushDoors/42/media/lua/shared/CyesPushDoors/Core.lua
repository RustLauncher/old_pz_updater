require "CyesPushDoors/Config"
require "CyesPushDoors/Settings"

CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors
local C = CPD.Config
local S = CPD.Settings

CPD._recentImpacts = CPD._recentImpacts or {}
CPD._pendingZombieDamage = CPD._pendingZombieDamage or {}
CPD._pendingZombieNetworkVerify = CPD._pendingZombieNetworkVerify or {}
CPD._impactRecoveryUntil = CPD._impactRecoveryUntil or {}
CPD._authoritativePlayerStrengths = CPD._authoritativePlayerStrengths or {}

local function emitServerDebugFile(tag, msg, renderedLine)
    if not (isServer and isServer()) then return end
    local sink = CPD and CPD._serverDebugFileSink or nil
    if type(sink) ~= "function" then return end
    pcall(sink, tag, msg, renderedLine)
end

local function log(msg)
    if C.DEBUG == true then
        local rendered = "[Cye's Push Doors!] " .. tostring(msg)
        print(rendered)
        emitServerDebugFile("LOG", msg, rendered)
    end
end
CPD.log = log

local function mpDebug(tag, msg)
    if C.DEBUG ~= true then return end
    local side = "LOCAL"
    if isServer and isServer() then
        side = "SERVER"
    elseif isClient and isClient() then
        side = "CLIENT"
    end
    local label = tostring(C.DEBUG_LABEL or C.VERSION or "DEBUG")
    local rendered = "[CPD " .. label .. "][" .. side .. "][" .. tostring(tag) .. "] " .. tostring(msg)
    print(rendered)
    if side == "SERVER" then
        emitServerDebugFile(tag, msg, rendered)
    end
end
CPD.mpDebug = mpDebug

require "CyesPushDoors/Feedback"

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function randomFloat(lo, hi)
    if lo == hi then return lo end
    if ZombRandFloat then
        return ZombRandFloat(lo, hi)
    end
    return lo + ((ZombRand(100000) / 100000.0) * (hi - lo))
end

local function randomIntInclusive(lo, hi)
    lo = math.floor(tonumber(lo) or 0)
    hi = math.floor(tonumber(hi) or lo)
    if hi < lo then lo, hi = hi, lo end
    if hi == lo then return lo end
    return lo + ZombRand((hi - lo) + 1)
end

local function shuffledCopy(list)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    for i = #copy, 2, -1 do
        local j = randomIntInclusive(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

local function safeCall(object, methodName, ...)
    if not object then return nil end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or not method then return nil end
    local ok, result = pcall(method, object, ...)
    if ok then return result end
    return nil
end

local excludedNpcVariables = {
    "Bandit",
    "IsHDXStrangerNPC",
    "NoZombieHandling",
    "SurvivorNPC",
}

local function isInstanceOf(object, className)
    if not object or not instanceof then return false end
    local ok, result = pcall(instanceof, object, className)
    return ok and result == true
end

local function variableIsTrue(object, name)
    if safeCall(object, "getVariableBoolean", name) == true then return true end
    local value = safeCall(object, "getVariableString", name)
    return type(value) == "string" and string.lower(value) == "true"
end

local function hasNpcSignature(container)
    if not container then return false end
    local ok, marker = pcall(function()
        if container.npcUid ~= nil then return "npcUid" end
        if container.recruited ~= nil then return "recruited" end
        if container.master ~= nil then return "master" end
        if container.masterName ~= nil then return "masterName" end
        if container.hostile ~= nil then return "hostile" end
        if container.hostileP ~= nil then return "hostileP" end
        if container.id ~= nil and container.program ~= nil then return "id+program" end
        return nil
    end)
    return ok and marker or nil
end

local function hasNpcBrain(object)
    local modData = safeCall(object, "getModData")
    if not modData then return false end

    local directMarker = hasNpcSignature(modData)
    if directMarker then return "npc-brain-direct:" .. directMarker end

    local brain = nil
    local ok = pcall(function() brain = modData.brain end)
    local nestedMarker = ok and hasNpcSignature(brain) or nil
    if nestedMarker then return "npc-brain-nested:" .. nestedMarker end

    return false
end

local function hasBanditClusterBrainReason(object)
    local banditUtils = nil
    local okBanditUtils = pcall(function() banditUtils = BanditUtils end)
    if not okBanditUtils or type(banditUtils) ~= "table" then return nil end

    local getZombieID = nil
    local okGetZombieID = pcall(function() getZombieID = banditUtils.GetZombieID end)
    if not okGetZombieID or type(getZombieID) ~= "function" then return nil end

    local getBanditClusterDataFn = nil
    local okGetBanditClusterDataFn = pcall(function() getBanditClusterDataFn = GetBanditClusterData end)
    if not okGetBanditClusterDataFn or type(getBanditClusterDataFn) ~= "function" then return nil end

    local id = nil
    local okId = pcall(function() id = getZombieID(object) end)
    if not okId or id == nil then return nil end

    local cluster = nil
    local okCluster = pcall(function() cluster = getBanditClusterDataFn(id) end)
    if not okCluster or type(cluster) ~= "table" then return nil end

    local brain = nil
    local okBrain = pcall(function() brain = cluster[id] end)
    if not okBrain or type(brain) ~= "table" then return nil end

    local brainId = nil
    local hasBrainId = false
    pcall(function()
        brainId = brain.id
        hasBrainId = brainId ~= nil
    end)
    if hasBrainId and brainId ~= id then return nil end

    local isRecruited = false
    pcall(function() isRecruited = (brain.recruited == true) end)

    local hasNpcUid = false
    pcall(function() hasNpcUid = (brain.npcUid ~= nil) end)

    if isRecruited or hasNpcUid then
        return "bandit-cluster:true-companion"
    end

    return "bandit-cluster:bandit"
end

local function targetClassLabel(object)
    if isInstanceOf(object, "IsoAnimal") then return "IsoAnimal" end
    if isInstanceOf(object, "IsoZombie") then return "IsoZombie" end
    if isInstanceOf(object, "IsoPlayer") then return "IsoPlayer" end
    if safeCall(object, "getAnimalType") ~= nil then return "animal-like" end
    return "unknown"
end

local function logTargetClassification(object, targetType, reason, source)
    local displayedReason = reason
    if targetType == "zombie" and displayedReason == nil then
        displayedReason = "valid-zombie"
    end
    mpDebug("TARGET_CLASSIFY",
        "source=" .. tostring(source or "unknown") ..
        " class=" .. targetClassLabel(object) ..
        " id=" .. tostring(safeCall(object, "getOnlineID")) ..
        " result=" .. tostring(targetType or "excluded") ..
        " reason=" .. tostring(displayedReason or "unknown"))
end

function CPD.getImpactTargetType(object)
    if not object then return nil, "invalid" end

    if isInstanceOf(object, "IsoAnimal") or safeCall(object, "getAnimalType") ~= nil then
        return nil, "animal"
    end

    if isInstanceOf(object, "IsoZombie") then
        if safeCall(object, "isAlive") ~= true then return nil, "dead-zombie" end
        for i = 1, #excludedNpcVariables do
            local marker = excludedNpcVariables[i]
            if variableIsTrue(object, marker) then
                return nil, "npc-variable:" .. marker
            end
        end
        local npcReason = hasNpcBrain(object)
        if npcReason then return nil, npcReason end
        local banditReason = hasBanditClusterBrainReason(object)
        if banditReason then return nil, banditReason end
        return "zombie", nil
    end

    if isInstanceOf(object, "IsoPlayer") then
        if safeCall(object, "isAlive") == true then return "player", nil end
        return nil, "dead-player"
    end

    return nil, "unsupported"
end

function CPD.isEligibleZombieTarget(object)
    return CPD.getImpactTargetType(object) == "zombie"
end

function CPD.isEligiblePlayerTarget(object)
    return CPD.getImpactTargetType(object) == "player"
end

function CPD.isEligibleImpactTarget(object)
    local targetType = CPD.getImpactTargetType(object)
    return targetType == "zombie" or targetType == "player"
end

local function isMultiplayerEnvironment()
    local ok, result = pcall(function()
        if isMultiplayer then return isMultiplayer() end
        return nil
    end)
    if ok and result ~= nil then return result == true end
    if isServer and isServer() then return true end
    if isClient and isClient() then return true end
    return false
end

local function readServerBooleanOption(name)
    local options = nil
    local okOptions = pcall(function()
        if getServerOptions then options = getServerOptions() end
    end)
    if not okOptions or not options then return nil, false end

    local value = nil
    local okValue = pcall(function() value = options:getBoolean(name) end)
    if not okValue or type(value) ~= "boolean" then return nil, false end
    return value, true
end

local function readPlayerSafety(player)
    local safety = safeCall(player, "getSafety")
    if not safety then return nil end
    local enabled = safeCall(safety, "isEnabled")
    if enabled == nil then return nil end
    return enabled == true
end

local function readNonPvpState(player)
    local zoneClass = nil
    pcall(function() zoneClass = NonPvpZone end)
    if not zoneClass then return nil end

    local okDirect, direct = pcall(function()
        return zoneClass.isInNonPvpZone(player)
    end)
    if okDirect and type(direct) == "boolean" then return direct end

    local x = tonumber(safeCall(player, "getX"))
    local y = tonumber(safeCall(player, "getY"))
    if not x or not y then return nil end

    local okZone, zone = pcall(function()
        return zoneClass.getNonPvpZone(math.floor(x), math.floor(y))
    end)
    if not okZone then return nil end
    return zone ~= nil
end

function CPD.canAffectPlayerInMultiplayer(opener, target)
    if not CPD.isEligiblePlayerTarget(opener) then return false, "invalid-opener" end
    if not CPD.isEligiblePlayerTarget(target) then return false, "invalid-target" end
    if not isMultiplayerEnvironment() then return true, "singleplayer" end

    local pvpEnabled, pvpReadable = readServerBooleanOption("PVP")
    if not pvpReadable then return false, "pvp-unavailable" end
    if not pvpEnabled then return false, "pvp-disabled" end

    if safeCall(target, "isGodMod") == true then return false, "target-god-mode" end
    if safeCall(target, "isInvulnerable") == true then return false, "target-invulnerable" end

    local openerInNonPvp = readNonPvpState(opener)
    local targetInNonPvp = readNonPvpState(target)
    if openerInNonPvp == nil or targetInNonPvp == nil then
        return false, "non-pvp-zone-unavailable"
    end
    if openerInNonPvp or targetInNonPvp then return false, "non-pvp-zone" end

    local safetySystem, safetyReadable = readServerBooleanOption("SafetySystem")
    if not safetyReadable then return false, "safety-system-unavailable" end
    if safetySystem then
        local openerSafety = readPlayerSafety(opener)
        local targetSafety = readPlayerSafety(target)
        if openerSafety == nil or targetSafety == nil then
            return false, "player-safety-unavailable"
        end
        if openerSafety then return false, "opener-safety-enabled" end
        if targetSafety then return false, "target-safety-enabled" end
    end

    return true, "pvp-allowed"
end

function CPD.getStrength(character)
    if not character then return 0 end
    local level = safeCall(character, "getPerkLevel", Perks.Strength) or 0
    return clamp(tonumber(level) or 0, 0, 10)
end

local function authoritativeStrengthNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function CPD.updateAuthoritativePlayerStrengthSnapshot(serializedStrengths)
    local fresh = {}
    local count = 0
    for rawId, rawStrength in string.gmatch(
        tostring(serializedStrengths or ""),
        "(-?%d+):(%d+)"
    ) do
        local id = tonumber(rawId)
        local strength = tonumber(rawStrength)
        if id and id >= 0 and strength then
            fresh[tostring(id)] = clamp(math.floor(strength), 0, 10)
            count = count + 1
        end
    end
    CPD._authoritativePlayerStrengths = fresh
    CPD._authoritativePlayerStrengthSnapshotAt = authoritativeStrengthNowMs()
    mpDebug("PLAYER_STRENGTH_SNAPSHOT_CLIENT",
        "players=" .. tostring(count))
    return count
end

function CPD.getAuthoritativePlayerStrength(character)
    if not character then return nil, "missing-player" end
    local id = tonumber(safeCall(character, "getOnlineID"))
    if id == nil or id < 0 then return nil, "invalid-online-id" end

    local receivedAt = tonumber(CPD._authoritativePlayerStrengthSnapshotAt) or 0
    local ttl = math.max(
        500,
        tonumber(C.PLAYER_STRENGTH_SNAPSHOT_TTL_MS) or 2500
    )
    if receivedAt <= 0 or (authoritativeStrengthNowMs() - receivedAt) > ttl then
        return nil, "stale-snapshot"
    end

    local value = tonumber(CPD._authoritativePlayerStrengths[tostring(id)])
    if value == nil then return nil, "player-not-in-snapshot" end
    return clamp(math.floor(value), 0, 10), nil
end

function CPD.requestPlayerStrengthSnapshot(force)
    if not (isClient and isClient()) or not sendClientCommand then return false end
    local now = authoritativeStrengthNowMs()
    local cooldown = math.max(
        100,
        tonumber(C.PLAYER_STRENGTH_SNAPSHOT_REQUEST_COOLDOWN_MS) or 250
    )
    if force ~= true
        and now - (tonumber(CPD._lastPlayerStrengthSnapshotRequestAt) or 0) < cooldown then
        return false
    end
    CPD._lastPlayerStrengthSnapshotRequestAt = now
    local ok = pcall(function()
        sendClientCommand("CyesPushDoors", "requestPlayerStrengthSnapshot", {})
    end)
    mpDebug("PLAYER_STRENGTH_SNAPSHOT_REQUEST", "sent=" .. tostring(ok))
    return ok
end

function CPD.isPlayerStrengthBlocking(opener, target)
    if not CPD.isEligiblePlayerTarget(opener) then
        return false, 0, 0, "invalid-opener"
    end
    if not CPD.isEligiblePlayerTarget(target) then
        return false, CPD.getStrength(opener), 0, "invalid-target"
    end

    local pvpAllowed, pvpReason = CPD.canAffectPlayerInMultiplayer(opener, target)
    local openerStrength = CPD.getStrength(opener)
    local targetStrength = CPD.getStrength(target)
    if not pvpAllowed then
        return false, openerStrength, targetStrength, pvpReason
    end
    return targetStrength > openerStrength,
        openerStrength,
        targetStrength,
        targetStrength > openerStrength and "stronger-player" or "strength-allowed"
end

function CPD.findPlayerStrengthBlocker(opener, players)
    for i = 1, #(players or {}) do
        local target = players[i]
        local blocked, openerStrength, targetStrength, reason =
            CPD.isPlayerStrengthBlocking(opener, target)
        if blocked then
            return target, openerStrength, targetStrength, reason
        end
    end
    return nil, CPD.getStrength(opener), nil, "none"
end

function CPD.findAuthoritativePlayerStrengthBlocker(opener, players)
    local openerStrength, openerReason =
        CPD.getAuthoritativePlayerStrength(opener)
    if openerStrength == nil then
        return nil,
            CPD.getStrength(opener),
            nil,
            openerReason or "strength-sync-pending",
            true
    end

    local missingReason = nil
    for i = 1, #(players or {}) do
        local target = players[i]
        local targetStrength, targetReason =
            CPD.getAuthoritativePlayerStrength(target)
        if targetStrength == nil then
            missingReason = targetReason or "strength-sync-pending"
        elseif targetStrength > openerStrength then
            return target,
                openerStrength,
                targetStrength,
                "stronger-player",
                false
        end
    end

    if missingReason then
        return nil, openerStrength, nil, missingReason, true
    end
    return nil, openerStrength, nil, "strength-allowed", false
end

function CPD.getFitness(character)
    if not character then return 0 end
    local level = safeCall(character, "getPerkLevel", Perks.Fitness) or 0
    return clamp(tonumber(level) or 0, 0, 10)
end

function CPD.getEndurance(character)
    if not character then return 1.0 end
    local stats = safeCall(character, "getStats")
    if not stats then return 1.0 end

    local value = nil
    if CharacterStat and CharacterStat.ENDURANCE then
        value = safeCall(stats, "get", CharacterStat.ENDURANCE)
    end
    if value == nil then
        value = safeCall(stats, "getEndurance")
    end
    return clamp(tonumber(value) or 1.0, 0.0, 1.0)
end

function CPD.setEnduranceAbsolute(character, value)
    if not character then return false end
    local stats = safeCall(character, "getStats")
    if not stats then return false end

    value = clamp(tonumber(value) or 0.0, 0.0, 1.0)
    if CharacterStat and CharacterStat.ENDURANCE then
        local ok, result = pcall(function() return stats:set(CharacterStat.ENDURANCE, value) end)
        if ok and result ~= false then return true end
    end
    return pcall(function() stats:setEndurance(value) end)
end

function CPD.getEnduranceBand(character)
    local endurance = CPD.getEndurance(character)
    local thresholds = C.ENDURANCE_THRESHOLDS or {}
    if endurance <= (tonumber(thresholds.critical) or 0.10) then return "critical", endurance end
    if endurance <= (tonumber(thresholds.high) or 0.20) then return "high", endurance end
    if endurance <= (tonumber(thresholds.medium) or 0.35) then return "medium", endurance end
    if endurance <= (tonumber(thresholds.light) or 0.50) then return "light", endurance end
    return "none", endurance
end

function CPD.getEnduranceModifiers(character)
    local band, endurance = CPD.getEnduranceBand(character)
    local row = (C.ENDURANCE_DEBUFF or {})[band] or (C.ENDURANCE_DEBUFF or {}).none or {}
    return {
        band = band,
        endurance = endurance,
        damageMult = clamp(tonumber(row.damageMult) or 1.0, 0.0, 1.0),
        knockdownMult = clamp(tonumber(row.knockdownMult) or 1.0, 0.0, 1.0),
    }
end

function CPD.isImpactBlockedByEndurance(character)
    local band = CPD.getEnduranceBand(character)
    return band == "critical"
end

local function getArmPartDefs()
    if not BodyPartType then return {} end
    return {
        { name="Hand_L",     type=BodyPartType.Hand_L },
        { name="ForeArm_L",  type=BodyPartType.ForeArm_L },
        { name="UpperArm_L", type=BodyPartType.UpperArm_L },
        { name="Hand_R",     type=BodyPartType.Hand_R },
        { name="ForeArm_R",  type=BodyPartType.ForeArm_R },
        { name="UpperArm_R", type=BodyPartType.UpperArm_R },
    }
end

local function getArmBodyPart(character, partType)
    if not character or not partType then return nil end
    local bodyDamage = safeCall(character, "getBodyDamage")
    if not bodyDamage then return nil end
    return safeCall(bodyDamage, "getBodyPart", partType)
end

function CPD.getArmStrainBySide(character)
    if not character then return 0, 0 end
    local leftMaximum = 0
    local rightMaximum = 0
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local part = getArmBodyPart(character, def.type)
        local stiffness = tonumber(safeCall(part, "getStiffness")) or 0
        if string.sub(def.name, -2) == "_L" then
            if stiffness > leftMaximum then leftMaximum = stiffness end
        else
            if stiffness > rightMaximum then rightMaximum = stiffness end
        end
    end
    return clamp(leftMaximum, 0, 100), clamp(rightMaximum, 0, 100)
end

function CPD.getArmStrainForSide(character, side)
    local leftStrain, rightStrain = CPD.getArmStrainBySide(character)
    if side == "left" then return leftStrain end
    if side == "right" then return rightStrain end
    return math.max(leftStrain, rightStrain)
end

function CPD.getArmStrain(character)
    local leftStrain, rightStrain = CPD.getArmStrainBySide(character)
    return math.max(leftStrain, rightStrain)
end

function CPD.getArmStrainThresholds()
    local scale = S.armStrainUsageLimitMultiplier()
    local thresholds = C.ARM_STRAIN_THRESHOLDS or {}
    return {
        light = (tonumber(thresholds.light) or 5.0) * scale,
        medium = (tonumber(thresholds.medium) or 12.0) * scale,
        high = (tonumber(thresholds.high) or 20.0) * scale,
    }
end

function CPD.getArmStrainUsageLimit()
    return (tonumber(C.ARM_STRAIN_USAGE_LIMIT) or 20.0) * S.armStrainUsageLimitMultiplier()
end

function CPD.getArmStrainBand(character)
    local strain = CPD.getArmStrain(character)
    local thresholds = CPD.getArmStrainThresholds()
    if strain >= thresholds.high then return "high", strain end
    if strain >= thresholds.medium then return "medium", strain end
    if strain >= thresholds.light then return "light", strain end
    return "none", strain
end

function CPD.getArmStrainModifiers(character)
    local band, strain = CPD.getArmStrainBand(character)
    local row = C.ARM_STRAIN_DEBUFF[band] or C.ARM_STRAIN_DEBUFF.none
    local penalty = S.armStrainPenaltyMultiplier()
    local baseDamage = tonumber(row.damageMult) or 1.0
    local baseKnockdown = tonumber(row.knockdownMult) or 1.0
    return {
        band = band,
        strain = strain,
        damageMult = clamp(1.0 - ((1.0 - baseDamage) * penalty), 0.0, 1.0),
        knockdownMult = clamp(1.0 - ((1.0 - baseKnockdown) * penalty), 0.0, 1.0),
    }
end

function CPD.getCombinedImpactModifiers(character)
    local strainMods = CPD.getArmStrainModifiers(character)
    local enduranceMods = CPD.getEnduranceModifiers(character)
    return {
        band = strainMods.band,
        strain = strainMods.strain,
        enduranceBand = enduranceMods.band,
        endurance = enduranceMods.endurance,
        damageMult = clamp(strainMods.damageMult * enduranceMods.damageMult, 0.0, 1.0),
        knockdownMult = clamp(strainMods.knockdownMult * enduranceMods.knockdownMult, 0.0, 1.0),
    }
end

local function recoveryNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function CPD.getImpactRecoveryBand(character)
    local band, strain = CPD.getArmStrainBand(character)
    if band == "high" and not CPD.isImpactBlockedByArmStrain(character) then
        band = "medium"
    end
    return band, strain
end

function CPD.getImpactRecoveryDurationMs(character)
    local band, strain = CPD.getImpactRecoveryBand(character)
    local durations = C.ARM_STRAIN_RECOVERY_MS or {}
    local baseMs = tonumber(durations[band]) or tonumber(durations.none) or 750
    local enduranceBand, endurance = CPD.getEnduranceBand(character)
    local additions = C.ENDURANCE_RECOVERY_ADDITION_MS or {}
    local enduranceAdditionMs = tonumber(additions[enduranceBand]) or 0
    local durationMs = math.max(0, math.floor(
        (baseMs * S.armStrainRecoveryMultiplier()) + enduranceAdditionMs + 0.5
    ))
    return durationMs, band, strain, enduranceBand, endurance
end

function CPD.getImpactRecoveryRemainingMs(character)
    if not character then return 0, "none" end
    local untilAt = tonumber(CPD._impactRecoveryUntil[character]) or 0
    local remaining = untilAt - recoveryNowMs()
    if remaining <= 0 then
        CPD._impactRecoveryUntil[character] = nil
        return 0, CPD.getImpactRecoveryBand(character)
    end
    local band = CPD.getImpactRecoveryBand(character)
    return math.ceil(remaining), band
end

function CPD.isImpactRecoveryActive(character)
    local remaining, band = CPD.getImpactRecoveryRemainingMs(character)
    return remaining > 0, remaining, band
end

function CPD.startImpactRecovery(character)
    if not character then return 0, "none", 0 end
    local durationMs, band, strain, enduranceBand, endurance = CPD.getImpactRecoveryDurationMs(character)
    if durationMs <= 0 then
        CPD._impactRecoveryUntil[character] = nil
        return 0, band, strain, enduranceBand, endurance
    end
    CPD._impactRecoveryUntil[character] = recoveryNowMs() + durationMs
    return durationMs, band, strain, enduranceBand, endurance
end

local function getSandboxMuscleStrainMultiplier()
    if SandboxVars and SandboxVars.MuscleStrainFactor ~= nil then
        return math.max(0, tonumber(SandboxVars.MuscleStrainFactor) or 1.0)
    end
    return 1.0
end

function CPD.setArmStrainAbsolute(character, values)
    if not character or not values then return end
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local value = tonumber(values[def.name])
        if value ~= nil then
            local part = getArmBodyPart(character, def.type)
            if part then safeCall(part, "setStiffness", clamp(value, 0, 100)) end
        end
    end
end

function CPD.getArmStrainParts(character)
    local values = {}
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local part = getArmBodyPart(character, def.type)
        values[def.name] = tonumber(safeCall(part, "getStiffness")) or 0
    end
    return values
end

function CPD.isImpactBlockedByArmStrain(character)
    if not character then return false end

    local limit = CPD.getArmStrainUsageLimit()
    local leftStrain, rightStrain = CPD.getArmStrainBySide(character)
    return leftStrain >= limit and rightStrain >= limit
end

function CPD.applyArmStrain(character, fitness, targetCount, doorProfile)
    targetCount = math.max(0, tonumber(targetCount) or 0)
    if not character or targetCount <= 0 then return 0 end

    fitness = clamp(tonumber(fitness) or CPD.getFitness(character), 0, 10)
    local perTarget = tonumber(C.FITNESS_ARM_STRAIN_PER_TARGET[fitness]) or 0
    if doorProfile and doorProfile.garage == true then
        perTarget = tonumber(C.GARAGE_FITNESS_ARM_STRAIN_PER_TARGET[fitness]) or perTarget
    elseif doorProfile and doorProfile.doubleDoor == true then
        perTarget = tonumber(C.DOUBLE_DOOR_FITNESS_ARM_STRAIN_PER_TARGET[fitness]) or perTarget
    end

    local amount = perTarget * targetCount * getSandboxMuscleStrainMultiplier() * S.armStrainGainMultiplier()
    if doorProfile and doorProfile.garage == true then
        amount = amount * S.garageArmStrainMultiplier()
    end
    if amount <= 0 then return 0 end

    local values = {}
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local part = getArmBodyPart(character, def.type)
        if part then
            local current = tonumber(safeCall(part, "getStiffness")) or 0
            local newValue = clamp(current + amount, 0, 100)
            safeCall(part, "setStiffness", newValue)
            values[def.name] = newValue
        end
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(character, "CyesPushDoors", "armStrainSync", values)
    end

    log("Arm strain fitness=" .. tostring(fitness) ..
        " targets=" .. tostring(targetCount) ..
        " profile=" .. tostring(doorProfile and doorProfile.kind or "standard") ..
        " added=" .. string.format("%.3f", amount) ..
        " maxNow=" .. string.format("%.3f", CPD.getArmStrain(character)))
    return amount
end

function CPD.isSupportedDoor(door)
    if not door then return false end
    if instanceof(door, "IsoDoor") then return true end
    if instanceof(door, "IsoThumpable") then
        local ok, isDoor = pcall(function() return door:isDoor() end)
        return ok and isDoor == true
    end
    return false
end

function CPD.isGarageDoor(door)
    if not door or not IsoDoor or not IsoDoor.getGarageDoorIndex then return false end
    local ok, index = pcall(IsoDoor.getGarageDoorIndex, door)
    return ok and index ~= nil and tonumber(index) ~= nil and tonumber(index) >= 0
end

function CPD.getGarageDoorParts(door)
    if not CPD.isGarageDoor(door) then
        return door and { door } or {}
    end

    local first = nil
    if IsoDoor and IsoDoor.getGarageDoorFirst then
        local ok, value = pcall(IsoDoor.getGarageDoorFirst, door)
        if ok then first = value end
    end
    first = first or door

    local result = {}
    local seen = {}
    local current = first
    for i = 1, 3 do
        if not current or seen[current] then break end
        result[#result + 1] = current
        seen[current] = true

        if IsoDoor and IsoDoor.getGarageDoorNext then
            local ok, value = pcall(IsoDoor.getGarageDoorNext, current)
            if ok then
                current = value
            else
                current = nil
            end
        else
            current = nil
        end
    end

    if #result == 0 then result[1] = door end
    return result
end

function CPD.getGarageDoorMaster(door)
    local parts = CPD.getGarageDoorParts(door)
    return parts[1] or door
end




function CPD.isDoubleDoor(door)
    if not door or CPD.isGarageDoor(door) or not IsoDoor or not IsoDoor.getDoubleDoorIndex then
        return false
    end
    local ok, index = pcall(IsoDoor.getDoubleDoorIndex, door)
    index = ok and tonumber(index) or nil
    return index ~= nil and index >= 0
end

function CPD.getDoubleDoorParts(door)
    if not CPD.isDoubleDoor(door) then
        return door and { door } or {}
    end

    local result = {}
    local seen = {}
    local function addPart(part)
        if not part or seen[part] or not CPD.isSupportedDoor(part) then return end
        seen[part] = true
        result[#result + 1] = part
    end

    addPart(door)

    
    
    
    if IsoDoor and IsoDoor.getDoubleDoorObject then
        for index = 0, 4 do
            local ok, part = pcall(IsoDoor.getDoubleDoorObject, door, index)
            if ok then addPart(part) end
        end
    end

    
    
    table.sort(result, function(a, b)
        local ai, bi = math.huge, math.huge
        if IsoDoor and IsoDoor.getDoubleDoorIndex then
            local oka, va = pcall(IsoDoor.getDoubleDoorIndex, a)
            local okb, vb = pcall(IsoDoor.getDoubleDoorIndex, b)
            if oka and tonumber(va) then ai = tonumber(va) end
            if okb and tonumber(vb) then bi = tonumber(vb) end
        end
        if ai ~= bi then return ai < bi end

        local asq = safeCall(a, "getSquare")
        local bsq = safeCall(b, "getSquare")
        if asq and bsq then
            if asq:getZ() ~= bsq:getZ() then return asq:getZ() < bsq:getZ() end
            if asq:getY() ~= bsq:getY() then return asq:getY() < bsq:getY() end
            if asq:getX() ~= bsq:getX() then return asq:getX() < bsq:getX() end
        end
        return (tonumber(safeCall(a, "getObjectIndex")) or 0) <
               (tonumber(safeCall(b, "getObjectIndex")) or 0)
    end)

    if #result == 0 then result[1] = door end
    return result
end

function CPD.getDoubleDoorMaster(door)
    local parts = CPD.getDoubleDoorParts(door)
    return parts[1] or door
end

local function identifierContainsFence(value)
    if value == nil then return false end
    return string.find(string.lower(tostring(value)), "fence", 1, true) ~= nil
end

local function objectHasFenceIdentifier(object)
    if not object then return false end
    if identifierContainsFence(safeCall(object, "getName")) then return true end
    if identifierContainsFence(safeCall(object, "getSpriteName")) then return true end
    if identifierContainsFence(safeCall(object, "getObjectName")) then return true end
    if identifierContainsFence(safeCall(object, "getTextureName")) then return true end
    return false
end

function CPD.isSingleFenceGate(door)
    if not door or not CPD.isSupportedDoor(door) then return false end
    if CPD.isGarageDoor(door) or CPD.isDoubleDoor(door) then return false end
    if objectHasFenceIdentifier(door) then return true end
    if objectHasFenceIdentifier(safeCall(door, "getSprite")) then return true end
    if objectHasFenceIdentifier(safeCall(door, "getOpenSprite")) then return true end
    if identifierContainsFence(safeCall(door, "getClosedSpriteTextureName")) then return true end

    local properties = safeCall(door, "getProperties")
    local propertyNames = {
        "ID",
        "id",
        "Name",
        "Type",
        "CustomName",
        "GroupName",
        "SpriteName",
        "FenceType",
    }
    for i = 1, #propertyNames do
        if identifierContainsFence(safeCall(properties, "Val", propertyNames[i])) then
            return true
        end
    end
    return false
end

function CPD.getLogicalDoorOpenState(door)
    if not door then return nil end

    if CPD.isDoubleDoor(door) then
        local parts = CPD.getDoubleDoorParts(door)
        local sawState = false
        for i = 1, #parts do
            local state = safeCall(parts[i], "IsOpen")
            if state ~= nil then
                sawState = true
                if state == true then return true end
            end
        end
        if sawState then return false end
    end

    return safeCall(door, "IsOpen")
end

function CPD.getDoorSpriteName(door)
    if not door then return nil end
    local name = safeCall(door, "getSpriteName")
    if name ~= nil then return tostring(name) end

    local sprite = safeCall(door, "getSprite")
    local spriteName = safeCall(sprite, "getName")
    if spriteName ~= nil then return tostring(spriteName) end
    return nil
end

function CPD.getDoorProfileKey(door)
    if not door then return "standard" end
    if CPD.isGarageDoor(door) then return "garage" end
    if CPD.isDoubleDoor(door) then return "doubleDoor" end

    local sliding = C.SPECIAL_SLIDING_DOOR_SPRITES or {}
    local profiles = C.DOOR_PROFILE_BY_SPRITE or {}

    local current = CPD.getDoorSpriteName(door)
    if current and sliding[current] == true then return "slidingGlass" end
    if current and profiles[current] then return profiles[current] end

    local openSprite = safeCall(door, "getOpenSprite")
    local openName = safeCall(openSprite, "getName")
    if openName then
        openName = tostring(openName)
        if sliding[openName] == true then return "slidingGlass" end
        if profiles[openName] then return profiles[openName] end
    end

    return "standard"
end

function CPD.isSlidingGlassDoor(door)
    return CPD.getDoorProfileKey(door) == "slidingGlass"
end

function CPD.supportsPlayerStrengthBlocking(door)
    return CPD.isSupportedDoor(door)
        and not CPD.isGarageDoor(door)
        and not CPD.isSlidingGlassDoor(door)
end

function CPD.supportsClosingControlImpact(door)
    return CPD.isSupportedDoor(door)
        and not CPD.isGarageDoor(door)
        and not CPD.isSlidingGlassDoor(door)
end

function CPD.getDoorImpactProfile(door, strength)
    local kind = CPD.getDoorProfileKey(door)

    if kind == "garage" then
        local damage = C.GARAGE_DOOR_ZOMBIE_DAMAGE[strength] or C.GARAGE_DOOR_ZOMBIE_DAMAGE[0]
        return {
            kind = "garage",
            garage = true,
            doubleDoor = false,
            sliding = false,
            maxZombies = nil,
            neverZombieKnockdown = false,
            neverPlayerKnockdown = false,
            forceZombieStun = false,
            zombieDamageMin = tonumber(damage.min) or 0,
            zombieDamageMax = tonumber(damage.max) or 0,
            playerDamageMult = tonumber(C.GARAGE_DOOR_PLAYER_DAMAGE_MULT) or 2.0,
            doorWearMult = tonumber(C.GARAGE_DOOR_WEAR_MULT) or 1.00,
            ignoreMaterialWear = true,
        }
    end

    if kind == "doubleDoor" then
        local damage = C.DOUBLE_DOOR_ZOMBIE_DAMAGE[strength] or C.DOUBLE_DOOR_ZOMBIE_DAMAGE[0]
        return {
            kind = "doubleDoor",
            garage = false,
            doubleDoor = true,
            sliding = false,
            maxZombies = nil,
            neverZombieKnockdown = false,
            neverPlayerKnockdown = false,
            forceZombieStun = false,
            zombieDamageMin = tonumber(damage.min) or 0,
            zombieDamageMax = tonumber(damage.max) or 0,
            maxZombieDamageFraction = tonumber(C.DOUBLE_DOOR_MAX_ZOMBIE_DAMAGE_FRACTION) or 0.85,
            playerDamageMult = tonumber(C.DOUBLE_DOOR_PLAYER_DAMAGE_MULT) or 0.75,
            doorWearMult = tonumber(C.DOUBLE_DOOR_WEAR_MULT) or 0.75,
            ignoreMaterialWear = false,
        }
    end

    if kind == "slidingGlass" then
        local damage = C.SLIDING_DOOR_ZOMBIE_DAMAGE[strength] or C.SLIDING_DOOR_ZOMBIE_DAMAGE[0]
        return {
            kind = "slidingGlass",
            garage = false,
            doubleDoor = false,
            sliding = true,
            maxZombies = tonumber(C.SLIDING_DOOR_MAX_ZOMBIES[strength]) or 1,
            neverZombieKnockdown = true,
            neverPlayerKnockdown = true,
            forceZombieStun = true,
            zombieDamageMin = tonumber(damage.min) or 0,
            zombieDamageMax = tonumber(damage.max) or 0,
            playerDamageMult = tonumber(C.SLIDING_DOOR_PLAYER_DAMAGE_MULT) or 0.20,
            doorWearMult = tonumber(C.SLIDING_DOOR_WEAR_MULT) or 1.50,
            ignoreMaterialWear = true,
        }
    end

    local values = (C.DOOR_PROFILE_VALUES or {})[kind] or (C.DOOR_PROFILE_VALUES or {}).standard or {}
    return {
        kind = kind,
        garage = false,
        doubleDoor = false,
        sliding = false,
        maxZombies = nil,
        neverZombieKnockdown = false,
        neverPlayerKnockdown = false,
        forceZombieStun = false,
        zombieDamageMult = tonumber(values.zombieDamageMult) or 1.0,
        playerDamageMult = tonumber(values.playerDamageMult) or 1.0,
        doorWearMult = tonumber(values.doorWearMult) or 1.0,
        ignoreMaterialWear = values.ignoreMaterialWear == true,
    }
end

function CPD.getEnduranceFamily(door, doorProfile)
    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, 0)
    if doorProfile.garage == true then return "garage" end
    if doorProfile.sliding == true then return "sliding" end
    if doorProfile.doubleDoor == true then return "doubleDoor" end
    if CPD.isSingleFenceGate(door) then return "fence" end
    return "standard"
end

function CPD.getEnduranceCost(character, door, targetCount, doorProfile)
    targetCount = math.max(0, math.floor(tonumber(targetCount) or 0))
    if not character or not door or targetCount <= 0 then return 0.0, "standard" end

    local family = CPD.getEnduranceFamily(door, doorProfile)
    local row = (C.ENDURANCE_COST or {})[family] or (C.ENDURANCE_COST or {}).standard or {}
    local fitness = math.floor(clamp(CPD.getFitness(character), 0, 10))
    local fitnessMultiplier = tonumber((C.FITNESS_ENDURANCE_MULTIPLIER or {})[fitness]) or 1.0
    local baseCost = tonumber(row.base) or 0.0
    local perTargetCost = tonumber(row.perTarget) or 0.0
    local cost = (baseCost + (perTargetCost * targetCount))
        * fitnessMultiplier
        * S.enduranceCostMultiplier()
    return math.max(0.0, cost), family
end

function CPD.applyEnduranceCost(character, door, targetCount, doorProfile)
    local cost, family = CPD.getEnduranceCost(character, door, targetCount, doorProfile)
    local before = CPD.getEndurance(character)
    if cost <= 0.0 then return 0.0, before, before, family end

    local after = clamp(before - cost, 0.0, 1.0)
    if not CPD.setEnduranceAbsolute(character, after) then
        mpDebug("ENDURANCE_APPLY_FAIL",
            "player=" .. tostring(safeCall(character, "getUsername") or character) ..
            " family=" .. tostring(family) ..
            " requested=" .. string.format("%.4f", cost))
        return 0.0, before, before, family
    end

    if isServer and isServer() and sendServerCommand then
        pcall(function()
            sendServerCommand(character, "CyesPushDoors", "enduranceSync", {
                endurance = after,
                playerId = safeCall(character, "getOnlineID"),
            })
        end)
    end

    local applied = before - after
    mpDebug("ENDURANCE_APPLY",
        "player=" .. tostring(safeCall(character, "getUsername") or character) ..
        " family=" .. tostring(family) ..
        " fitness=" .. tostring(CPD.getFitness(character)) ..
        " targets=" .. tostring(targetCount) ..
        " multiplier=" .. string.format("%.2f", S.enduranceCostMultiplier()) ..
        " cost=" .. string.format("%.4f", applied) ..
        " endurance=" .. string.format("%.4f", before) .. "->" .. string.format("%.4f", after))
    return applied, before, after, family
end

local function appendMaterialText(parts, value)
    if value ~= nil then
        parts[#parts + 1] = string.lower(tostring(value))
    end
end

function CPD.getDoorMaterial(door)
    local parts = {}
    appendMaterialText(parts, safeCall(door, "getSpriteName"))
    appendMaterialText(parts, safeCall(door, "getThumpSound"))
    appendMaterialText(parts, safeCall(door, "getBreakSound"))
    appendMaterialText(parts, safeCall(door, "getName"))

    local props = safeCall(door, "getProperties")
    if props then
        local val = props.Val
        if val then
            local ok1, material = pcall(val, props, "Material")
            if ok1 then appendMaterialText(parts, material) end
            local ok2, material2 = pcall(val, props, "Material2")
            if ok2 then appendMaterialText(parts, material2) end
        end
    end

    local text = table.concat(parts, " ")
    local metalHints = {
        "metal", "steel", "iron", "chain", "wire", "security",
        "prison", "industrial", "chainlink"
    }
    for i = 1, #metalHints do
        if string.find(text, metalHints[i], 1, true) then
            return "metal"
        end
    end
    return "wood"
end

function CPD.getDoorWorldKey(door)
    local keyedDoor = door
    if CPD.isGarageDoor(door) then
        keyedDoor = CPD.getGarageDoorMaster(door) or door
    elseif CPD.isDoubleDoor(door) then
        keyedDoor = CPD.getDoubleDoorMaster(door) or door
    end

    local sq = keyedDoor and keyedDoor:getSquare() or nil
    if not sq then return "unknown" end
    return sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ() .. ":" .. tostring(keyedDoor:getObjectIndex())
end

function CPD.getPlayerDoorDistanceSq(player, door)
    if not player or not door then return math.huge end
    local sq = door:getSquare()
    if not sq then return math.huge end
    local dx = player:getX() - (sq:getX() + 0.5)
    local dy = player:getY() - (sq:getY() + 0.5)
    return (dx * dx) + (dy * dy)
end

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function CPD.isDuplicateImpact(opener, door)
    local key = CPD.getDoorWorldKey(door)
    local now = nowMs()
    local last = CPD._recentImpacts[key]
    if last and (now - last) < C.IMPACT_DEDUPE_MS then
        return true
    end
    CPD._recentImpacts[key] = now

    CPD._recentImpactPruneAt = tonumber(CPD._recentImpactPruneAt) or 0
    if (now - CPD._recentImpactPruneAt) >= 60000 then
        CPD._recentImpactPruneAt = now
        for oldKey, oldTime in pairs(CPD._recentImpacts) do
            if not oldTime or (now - oldTime) > 10000 then
                CPD._recentImpacts[oldKey] = nil
            end
        end
    end

    return false
end

function CPD.getDoorSideSquares(door)
    if not door then return nil, nil end
    local same = safeCall(door, "getSquare")
    if not same then return nil, nil end

    local opposite = safeCall(door, "getOppositeSquare")
    if opposite then return same, opposite end

    local north = safeCall(door, "getNorth")
    if north == nil then return same, nil end

    local x, y, z = same:getX(), same:getY(), same:getZ()
    if north == true then
        opposite = getCell():getGridSquare(x, y - 1, z)
    else
        opposite = getCell():getGridSquare(x - 1, y, z)
    end
    return same, opposite
end

local function squareDistanceToCharacter(square, character)
    if not square or not character then return math.huge end
    local dx = character:getX() - (square:getX() + 0.5)
    local dy = character:getY() - (square:getY() + 0.5)
    return (dx * dx) + (dy * dy)
end

function CPD.getImpactSquare(opener, door)
    if not opener or not door then return nil end

    local same, opposite = CPD.getDoorSideSquares(door)
    local openerSq = safeCall(opener, "getCurrentSquare")

    if openerSq and same and openerSq == same then
        return opposite
    end
    if openerSq and opposite and openerSq == opposite then
        return same
    end

    if same and opposite then
        if squareDistanceToCharacter(same, opener) <= squareDistanceToCharacter(opposite, opener) then
            return opposite
        end
        return same
    end

    return safeCall(door, "getOtherSideOfDoor", opener)
end

local function entrySquaresSameCoordinates(a, b)
    if not a or not b then return false end
    return a:getX() == b:getX() and a:getY() == b:getY() and a:getZ() == b:getZ()
end

local function entrySquareKey(square)
    if not square then return nil end
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end

local function appendUniqueEntrySquare(list, seen, square)
    local key = entrySquareKey(square)
    if not key or seen[key] then return end
    seen[key] = true
    list[#list + 1] = square
end

local function getEntryParts(door)
    if CPD.isGarageDoor(door) then
        return CPD.getGarageDoorParts(door)
    end
    if CPD.isDoubleDoor(door) then
        return CPD.getDoubleDoorParts(door)
    end
    return door and { door } or {}
end

function CPD.getEntrySideBands(door)
    local parts = getEntryParts(door)
    if #parts == 0 then return {}, {} end

    if #parts == 1 and not CPD.isGarageDoor(door) and not CPD.isDoubleDoor(door) then
        local same, opposite = CPD.getDoorSideSquares(parts[1])
        return same and { same } or {}, opposite and { opposite } or {}
    end

    local representative = door
    local sameRef, oppositeRef = CPD.getDoorSideSquares(representative)
    if not sameRef or not oppositeRef then
        for i = 1, #parts do
            local same, opposite = CPD.getDoorSideSquares(parts[i])
            if same and opposite then
                representative = parts[i]
                sameRef, oppositeRef = same, opposite
                break
            end
        end
    end
    if not sameRef or not oppositeRef then return {}, {} end

    local rawDx = oppositeRef:getX() - sameRef:getX()
    local rawDy = oppositeRef:getY() - sameRef:getY()
    if rawDx == 0 and rawDy == 0 then return {}, {} end

    local offsetX, offsetY = 0, 0
    if math.abs(rawDx) >= math.abs(rawDy) then
        offsetX = rawDx >= 0 and 1 or -1
    else
        offsetY = rawDy >= 0 and 1 or -1
    end

    local minT, maxT, z = nil, nil, sameRef:getZ()
    for i = 1, #parts do
        local square = safeCall(parts[i], "getSquare")
        if square and square:getZ() == z then
            local tangent = offsetX ~= 0 and square:getY() or square:getX()
            minT = minT and math.min(minT, tangent) or tangent
            maxT = maxT and math.max(maxT, tangent) or tangent
        end
    end

    if minT == nil or maxT == nil then return {}, {} end

    local sameBand, oppositeBand = {}, {}
    local sameSeen, oppositeSeen = {}, {}
    local cell = getCell and getCell() or nil
    if not cell then return {}, {} end

    for tangent = minT, maxT do
        local sameSquare, oppositeSquare = nil, nil
        if offsetX ~= 0 then
            sameSquare = cell:getGridSquare(sameRef:getX(), tangent, z)
            oppositeSquare = cell:getGridSquare(sameRef:getX() + offsetX, tangent, z)
        else
            sameSquare = cell:getGridSquare(tangent, sameRef:getY(), z)
            oppositeSquare = cell:getGridSquare(tangent, sameRef:getY() + offsetY, z)
        end
        appendUniqueEntrySquare(sameBand, sameSeen, sameSquare)
        appendUniqueEntrySquare(oppositeBand, oppositeSeen, oppositeSquare)
    end

    if #sameBand == 0 or #oppositeBand == 0 then
        return {}, {}
    end

    return sameBand, oppositeBand
end

local function bandContainsSquare(band, square)
    if not square then return false end
    for i = 1, #band do
        if band[i] == square or entrySquaresSameCoordinates(band[i], square) then
            return true
        end
    end
    return false
end

local function bandDistanceSqToCharacter(band, character)
    local best = math.huge
    if not character then return best end
    for i = 1, #band do
        local distance = squareDistanceToCharacter(band[i], character)
        if distance < best then best = distance end
    end
    return best
end

local function nearestSquareInBand(band, character)
    local best, bestDistance = nil, math.huge
    for i = 1, #band do
        local distance = squareDistanceToCharacter(band[i], character)
        if distance < bestDistance then
            bestDistance = distance
            best = band[i]
        end
    end
    return best
end

local function getCharacterFacingVector(character)
    if not character then return nil, nil end

    local forward = safeCall(character, "getForwardDirection")
    if forward then
        local fx = tonumber(safeCall(forward, "getX"))
        local fy = tonumber(safeCall(forward, "getY"))
        if fx == nil or fy == nil then
            local okX, rawX = pcall(function() return forward.x end)
            local okY, rawY = pcall(function() return forward.y end)
            if fx == nil and okX then fx = tonumber(rawX) end
            if fy == nil and okY then fy = tonumber(rawY) end
        end
        if fx and fy and ((fx * fx) + (fy * fy)) > 0.0001 then
            local length = math.sqrt((fx * fx) + (fy * fy))
            return fx / length, fy / length
        end
    end

    local dir = safeCall(character, "getDir")
    if dir == nil then return nil, nil end
    local text = string.upper(tostring(dir))
    local token = text:match("([NSEW][NSEW]?)$") or text
    local diagonal = 0.70710678118
    local vectors = {
        N = { 0, -1 }, NE = { diagonal, -diagonal },
        E = { 1, 0 }, SE = { diagonal, diagonal },
        S = { 0, 1 }, SW = { -diagonal, diagonal },
        W = { -1, 0 }, NW = { -diagonal, -diagonal },
    }
    local vector = vectors[token]
    if not vector then return nil, nil end
    return vector[1], vector[2]
end

local function bandCenter(band)
    if not band or #band == 0 then return nil, nil end
    local x, y = 0, 0
    for i = 1, #band do
        x = x + band[i]:getX() + 0.5
        y = y + band[i]:getY() + 0.5
    end
    return x / #band, y / #band
end

function CPD.getOpeningApproachDirection(door, impactSide)
    if not door or (impactSide ~= "same" and impactSide ~= "opposite") then return nil end
    local sameBand, oppositeBand = CPD.getEntrySideBands(door)
    local sameX, sameY = bandCenter(sameBand)
    local oppositeX, oppositeY = bandCenter(oppositeBand)
    if not sameX or not oppositeX then return nil end

    local dx = oppositeX - sameX
    local dy = oppositeY - sameY
    if impactSide == "same" then
        dx = -dx
        dy = -dy
    end
    if (dx * dx) + (dy * dy) <= 0.0001 then return nil end
    if math.abs(dx) >= math.abs(dy) then
        return dx >= 0 and "E" or "W"
    end
    return dy >= 0 and "S" or "N"
end

local function closestEntryPlanePoint(character, sameBand, oppositeBand)
    if not character or not sameBand or not oppositeBand then return nil, nil, math.huge end
    local count = math.min(#sameBand, #oppositeBand)
    local bestX, bestY, bestDistance = nil, nil, math.huge

    for i = 1, count do
        local x = ((sameBand[i]:getX() + 0.5) + (oppositeBand[i]:getX() + 0.5)) * 0.5
        local y = ((sameBand[i]:getY() + 0.5) + (oppositeBand[i]:getY() + 0.5)) * 0.5
        local dx = character:getX() - x
        local dy = character:getY() - y
        local distance = (dx * dx) + (dy * dy)
        if distance < bestDistance then
            bestDistance = distance
            bestX, bestY = x, y
        end
    end

    return bestX, bestY, bestDistance
end

function CPD.getPlayerEntrySide(opener, door)
    if not opener or not door then return nil, "missing" end
    local sameBand, oppositeBand = CPD.getEntrySideBands(door)
    if #sameBand == 0 or #oppositeBand == 0 then return nil, "missing-bands" end

    local openerSquare = safeCall(opener, "getCurrentSquare")
    local inSame = bandContainsSquare(sameBand, openerSquare)
    local inOpposite = bandContainsSquare(oppositeBand, openerSquare)
    if inSame ~= inOpposite then
        return inSame and "same" or "opposite", nil, sameBand, oppositeBand
    end

    local sameX, sameY = bandCenter(sameBand)
    local oppositeX, oppositeY = bandCenter(oppositeBand)
    if not sameX or not oppositeX then
        return nil, "missing-center", sameBand, oppositeBand
    end

    local nx = oppositeX - sameX
    local ny = oppositeY - sameY
    local lengthSq = (nx * nx) + (ny * ny)
    if lengthSq <= 0.0001 then
        return nil, "ambiguous-side", sameBand, oppositeBand
    end
    local length = math.sqrt(lengthSq)
    nx, ny = nx / length, ny / length

    local planeX = (sameX + oppositeX) * 0.5
    local planeY = (sameY + oppositeY) * 0.5
    local signed = ((opener:getX() - planeX) * nx) + ((opener:getY() - planeY) * ny)
    local epsilon = 0.05
    if math.abs(signed) <= epsilon then
        return nil, "ambiguous-side", sameBand, oppositeBand
    end

    return signed < 0 and "same" or "opposite", nil, sameBand, oppositeBand
end

function CPD.getInteractionEntryContext(opener, door)
    local playerSide, reason, sameBand, oppositeBand = CPD.getPlayerEntrySide(opener, door)
    if not playerSide then return nil, reason or "no-player-side" end

    local planeX, planeY, planeDistanceSq = closestEntryPlanePoint(opener, sameBand, oppositeBand)
    if not planeX or not planeY then return nil, "missing-entry-plane" end

    local maxDistance = tonumber(C.IMPACT_INTERACTION_MAX_DISTANCE) or 1.75
    if planeDistanceSq > (maxDistance * maxDistance) then
        return nil, "too-far"
    end

    local sameX, sameY = bandCenter(sameBand)
    local oppositeX, oppositeY = bandCenter(oppositeBand)
    if not sameX or not oppositeX then return nil, "missing-center" end

    local nx = oppositeX - sameX
    local ny = oppositeY - sameY
    local normalLengthSq = (nx * nx) + (ny * ny)
    if normalLengthSq <= 0.0001 then return nil, "ambiguous-facing" end
    local normalLength = math.sqrt(normalLengthSq)
    nx, ny = nx / normalLength, ny / normalLength

    local towardEntryX = playerSide == "same" and nx or -nx
    local towardEntryY = playerSide == "same" and ny or -ny
    local facingX, facingY = getCharacterFacingVector(opener)
    local facingDot = nil
    if facingX ~= nil and facingY ~= nil then
        facingDot = (facingX * towardEntryX) + (facingY * towardEntryY)
    end

    local impactSide = playerSide == "same" and "opposite" or "same"
    local playerBand = playerSide == "same" and sameBand or oppositeBand
    local impactBand = impactSide == "same" and sameBand or oppositeBand
    local anchor = nearestSquareInBand(impactBand, opener)
    if not anchor then return nil, "missing-impact-anchor" end

    return {
        playerSide = playerSide,
        impactSide = impactSide,
        playerBand = playerBand,
        impactBand = impactBand,
        anchor = anchor,
        entryDistanceSq = planeDistanceSq,
        facingDot = facingDot,
        towardEntryX = towardEntryX,
        towardEntryY = towardEntryY,
    }, nil
end

function CPD.getInteractionImpactContext(opener, door)
    local context, reason = CPD.getInteractionEntryContext(opener, door)
    if not context then return nil, reason end
    if context.facingDot == nil then return nil, "facing-unavailable" end

    local minDot = tonumber(C.IMPACT_INTERACTION_FACING_DOT_MIN)
    if minDot == nil then minDot = -0.01 end
    if context.facingDot < minDot then
        return nil, "not-facing-entry"
    end
    return context, nil
end

function CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if not door or not preferredImpactSquare then return nil, nil end
    local sameBand, oppositeBand = CPD.getEntrySideBands(door)
    if bandContainsSquare(sameBand, preferredImpactSquare) then
        return sameBand, "same"
    end
    if bandContainsSquare(oppositeBand, preferredImpactSquare) then
        return oppositeBand, "opposite"
    end
    return nil, nil
end

function CPD.isEntrySideSquare(door, square)
    local band = CPD.getImpactBandFromPreferred(door, square)
    return band ~= nil
end

function CPD.getGarageImpactSquares(opener, door, preferredImpactSquare)
    local band = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if band then return band end
    local context = CPD.getInteractionImpactContext(opener, door)
    return context and context.impactBand or {}
end

function CPD.getDoubleDoorImpactSquares(opener, door, preferredImpactSquare)
    local band, selectedSide = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if not band then
        local context = CPD.getInteractionImpactContext(opener, door)
        if context then
            band = context.impactBand
            selectedSide = context.impactSide
        end
    end
    band = band or {}

    mpDebug("DOUBLE_DOOR_BAND",
        "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
        " parts=" .. tostring(#CPD.getDoubleDoorParts(door)) ..
        " side=" .. tostring(selectedSide or "none") ..
        " selectedBand=" .. tostring(#band))
    return band
end

function CPD.getDoubleDoorImpactPart(door, impactSquare)
    if not door or not impactSquare or not CPD.isDoubleDoor(door) then return door end
    local parts = CPD.getDoubleDoorParts(door)
    local best = nil
    local bestDistance = math.huge
    for i = 1, #parts do
        local part = parts[i]
        local sq = safeCall(part, "getSquare")
        if sq then
            local dx = (sq:getX() + 0.5) - (impactSquare:getX() + 0.5)
            local dy = (sq:getY() + 0.5) - (impactSquare:getY() + 0.5)
            local d = (dx * dx) + (dy * dy)
            if d < bestDistance then
                bestDistance = d
                best = part
            end
        elseif not best then
            best = part
        end
    end
    return best or CPD.getDoubleDoorMaster(door) or door
end

function CPD.collectTargetsFromSquares(squares, opener)
    local targets = {}
    local squareByTarget = {}
    local seen = {}

    for i = 1, #squares do
        local square = squares[i]
        local found = CPD.collectTargets(square, opener)
        for j = 1, #found do
            local target = found[j]
            if not seen[target] then
                seen[target] = true
                targets[#targets + 1] = target
                squareByTarget[target] = square
            end
        end
    end

    return targets, squareByTarget
end

local function collectEligibleInteractionTargets(opener, squares)
    local found = CPD.collectTargetsFromSquares(squares or {}, opener)
    local valid = {}
    local zombies = 0
    local players = 0

    for i = 1, #found do
        local target = found[i]
        local targetType = CPD.getImpactTargetType(target)
        if targetType == "zombie" then
            if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                valid[#valid + 1] = target
                zombies = zombies + 1
            end
        elseif targetType == "player" then
            local allowed = CPD.canAffectPlayerInMultiplayer(opener, target)
            if allowed then
                valid[#valid + 1] = target
                players = players + 1
            end
        end
    end
    return valid, zombies, players
end

function CPD.getDoorFacingGuardState(opener, door, transition)
    if not CPD.isEligiblePlayerTarget(opener) then return nil, "invalid-opener" end
    if not CPD.isSupportedDoor(door) then return nil, "unsupported-door" end
    if CPD.isGarageDoor(door) then return nil, "garage-excluded" end

    local current = CPD.getLogicalDoorOpenState(door)
    transition = transition or (current == false and "open" or (current == true and "close" or nil))
    if transition ~= "open" and transition ~= "close" then return nil, "invalid-transition" end
    if transition == "open" and current ~= false then return nil, "not-opening" end
    if transition == "close" and current ~= true then return nil, "not-closing" end

    if transition == "open" then
        if safeCall(door, "couldBeOpen", opener) == false then return nil, "vanilla-cannot-open" end
        if safeCall(door, "isObstructed") == true then return nil, "obstructed" end
        if safeCall(door, "isBarricaded") == true then return nil, "barricaded" end
    end

    local context, reason = CPD.getInteractionEntryContext(opener, door)
    if not context then return nil, reason or "invalid-geometry" end

    local targets, zombieCount, playerCount = collectEligibleInteractionTargets(
        opener,
        context.impactBand
    )
    local targetCount = #targets
    local minDot = tonumber(C.DOOR_INTERACTION_FACING_DOT_MIN) or 0.50
    local facingDot = tonumber(context.facingDot)
    local facingRequired = targetCount > 0
    local facingAllowed = not facingRequired
        or (facingDot ~= nil and facingDot >= minDot)

    return {
        blocked = facingRequired and not facingAllowed,
        transition = transition,
        targetCount = targetCount,
        zombieCount = zombieCount,
        playerCount = playerCount,
        targets = targets,
        facingRequired = facingRequired,
        facingAllowed = facingAllowed,
        facingDot = facingDot,
        minimumFacingDot = minDot,
        playerSide = context.playerSide,
        impactSide = context.impactSide,
        impactBand = context.impactBand,
        anchor = context.anchor,
    }, nil
end

function CPD.getDoorBlockCapacityFamily(door)
    if CPD.isSlidingGlassDoor(door) then return "sliding" end
    if CPD.isDoubleDoor(door) then return "doubleDoor" end
    return "standard"
end

function CPD.getDoorBlockCapacity(door, strength)
    local family = CPD.getDoorBlockCapacityFamily(door)
    local familyTable = (C.DOOR_BLOCK_CAPACITY or {})[family]
        or (C.DOOR_BLOCK_CAPACITY or {}).standard
        or {}
    strength = math.max(0, math.min(10, math.floor(tonumber(strength) or 0)))
    local base = math.max(1, math.floor(tonumber(familyTable[strength]) or 1))
    local multiplier = S.doorBlockCapacityMultiplier()
    local capacity = math.max(1, math.floor((base * multiplier) + 0.5))
    return capacity, base, family, multiplier
end

function CPD.getDoorCrowdBlockState(opener, door)
    if not CPD.isEligiblePlayerTarget(opener) then return nil, "invalid-opener" end
    if not CPD.isSupportedDoor(door) then return nil, "unsupported-door" end
    if CPD.isGarageDoor(door) then return nil, "garage-excluded" end
    if CPD.getLogicalDoorOpenState(door) ~= false then return nil, "not-opening" end

    local couldBeOpen = safeCall(door, "couldBeOpen", opener)
    if couldBeOpen == false then return nil, "vanilla-cannot-open" end
    if safeCall(door, "isObstructed") == true then return nil, "obstructed" end

    local context, reason = CPD.getInteractionImpactContext(opener, door)
    if not context then return nil, reason or "invalid-geometry" end

    local sliding = CPD.isSlidingGlassDoor(door)
    local openingDirection = CPD.getOpeningApproachDirection(door, context.impactSide)
    if not sliding and not S.allowImpactsFromBothSides() then
        if openingDirection ~= "E" and openingDirection ~= "S" then
            return nil, "unsupported-impact-direction"
        end
    end

    local targets = CPD.collectTargetsFromSquares(context.impactBand or {}, opener)
    local zombies = {}
    for i = 1, #targets do
        local target = targets[i]
        if CPD.isEligibleZombieTarget(target) then
            if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                zombies[#zombies + 1] = target
            end
        end
    end

    local strength = CPD.getStrength(opener)
    local capacity, baseCapacity, family, multiplier = CPD.getDoorBlockCapacity(door, strength)
    return {
        blocked = #zombies > capacity,
        zombieCount = #zombies,
        zombies = zombies,
        capacity = capacity,
        baseCapacity = baseCapacity,
        family = family,
        multiplier = multiplier,
        strength = strength,
        impactBand = context.impactBand,
        impactSide = context.impactSide,
        openingDirection = openingDirection,
    }, nil
end

function CPD.getDoorPlayerStrengthBlockState(
    opener,
    door,
    transition,
    authoritativeSnapshot,
    precollectedPlayers
)
    if not CPD.isEligiblePlayerTarget(opener) then return nil, "invalid-opener" end
    if not CPD.isSupportedDoor(door) then return nil, "unsupported-door" end
    if not CPD.supportsPlayerStrengthBlocking(door) then
        return nil, CPD.isGarageDoor(door) and "garage-excluded" or "sliding-excluded"
    end

    local garage = false
    local current = CPD.getLogicalDoorOpenState(door)
    transition = transition or (current == false and "open" or (current == true and "close" or nil))
    if transition ~= "open" and transition ~= "close" then return nil, "invalid-transition" end
    if transition == "open" and current ~= false then return nil, "not-opening" end
    if transition == "close" and current ~= true then return nil, "not-closing" end
    if transition == "close" and not CPD.supportsClosingControlImpact(door) then
        return nil, "closing-excluded"
    end

    local playerEffectsEnabled = transition == "open"
    if playerEffectsEnabled then
        playerEffectsEnabled = S.damagePlayers() or S.knockDownPlayers()
    else
        playerEffectsEnabled = S.knockDownPlayers()
    end
    if not playerEffectsEnabled then return nil, "player-effects-disabled" end

    local context, contextReason = CPD.getInteractionEntryContext(opener, door)
    if not context then return nil, contextReason or "invalid-geometry" end

    local players = {}
    local targets = precollectedPlayers
    if type(targets) ~= "table" then
        targets = CPD.collectTargetsFromSquares(context.impactBand or {}, opener)
    end
    for i = 1, #targets do
        local target = targets[i]
        if CPD.getImpactTargetType(target) == "player" then
            local pvpAllowed = CPD.canAffectPlayerInMultiplayer(opener, target)
            if pvpAllowed then players[#players + 1] = target end
        end
    end

    local blocker, openerStrength, blockerStrength, blockerReason, strengthPending
    if authoritativeSnapshot == true then
        blocker, openerStrength, blockerStrength, blockerReason, strengthPending =
            CPD.findAuthoritativePlayerStrengthBlocker(opener, players)
    else
        blocker, openerStrength, blockerStrength, blockerReason =
            CPD.findPlayerStrengthBlocker(opener, players)
        strengthPending = false
    end
    return {
        blocked = blocker ~= nil,
        strengthPending = strengthPending == true and blocker == nil and #players > 0,
        blocker = blocker,
        players = players,
        playerCount = #players,
        openerStrength = openerStrength,
        blockerStrength = blockerStrength,
        blockerReason = blockerReason,
        garage = garage,
        transition = transition,
        impactBand = context.impactBand,
        impactSide = context.impactSide,
    }, nil
end

local function forcedOpeningDirectionVector(direction)
    if direction == "N" then return 0, -1 end
    if direction == "S" then return 0, 1 end
    if direction == "E" then return 1, 0 end
    if direction == "W" then return -1, 0 end
    return nil, nil
end

local FORCED_OPENING_ANIMATION_SIDES = {
    CPDForcePushDoor = "left",
    CPDForcePushDoor2 = "right",
}

local FORCED_OPENING_SIDE_ANIMATIONS = {
    left = "CPDForcePushDoor",
    right = "CPDForcePushDoor2",
}

function CPD.getForcedOpeningAnimationSide(actionAnim)
    if actionAnim == nil then return nil end
    return FORCED_OPENING_ANIMATION_SIDES[tostring(actionAnim)]
end

function CPD.getForcedOpeningAnimationForSide(side)
    return FORCED_OPENING_SIDE_ANIMATIONS[tostring(side or "")]
end

local function randomForcedOpeningIndex(count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then return nil end
    if ZombRand then return ZombRand(count) + 1 end
    return math.random(1, count)
end

local function forcedOpeningFracturePartDefs(side)
    if not BodyPartType then return {} end
    if side == "left" then
        return {
            { key="hand", name="Hand_L", type=BodyPartType.Hand_L },
            { key="forearm", name="ForeArm_L", type=BodyPartType.ForeArm_L },
            { key="upperarm", name="UpperArm_L", type=BodyPartType.UpperArm_L },
        }
    end
    if side == "right" then
        return {
            { key="hand", name="Hand_R", type=BodyPartType.Hand_R },
            { key="forearm", name="ForeArm_R", type=BodyPartType.ForeArm_R },
            { key="upperarm", name="UpperArm_R", type=BodyPartType.UpperArm_R },
        }
    end
    return {}
end

local function forcedOpeningPartDefinition(side, partKey)
    local defs = forcedOpeningFracturePartDefs(side)
    partKey = tostring(partKey or "")
    for i = 1, #defs do
        if defs[i].key == partKey or defs[i].name == partKey then return defs[i] end
    end
    return nil
end

local function forcedOpeningPartFractured(character, partType)
    local part = getArmBodyPart(character, partType)
    if not part then return false end
    local fractureTime = tonumber(safeCall(part, "getFractureTime")) or 0
    if fractureTime > 0 then return true end
    return safeCall(part, "isFracture") == true
end

function CPD.getForcedOpeningFractureProfile(character)
    local profile = {
        left = { count=0, fractured={}, available={} },
        right = { count=0, fractured={}, available={} },
        blocked = false,
    }
    for _, side in ipairs({ "left", "right" }) do
        local sideState = profile[side]
        local defs = forcedOpeningFracturePartDefs(side)
        for i = 1, #defs do
            local def = defs[i]
            local fractured = forcedOpeningPartFractured(character, def.type)
            sideState.fractured[def.key] = fractured
            if fractured then
                sideState.count = sideState.count + 1
            else
                sideState.available[#sideState.available + 1] = def.key
            end
        end
        sideState.upperArmFractured = sideState.fractured.upperarm == true
    end
    profile.bothUpperArmsFractured = profile.left.upperArmFractured
        and profile.right.upperArmFractured
    profile.bothSidesAtFractureLimit = profile.left.count >= 2
        and profile.right.count >= 2
    profile.blocked = profile.bothUpperArmsFractured or profile.bothSidesAtFractureLimit
    return profile
end

function CPD.isForcedOpeningSideAllowed(character, side, profile)
    side = side == "left" and "left" or (side == "right" and "right" or nil)
    if not side then return false end
    profile = profile or CPD.getForcedOpeningFractureProfile(character)
    if profile.blocked then return false end
    local left = profile.left
    local right = profile.right
    if left.upperArmFractured ~= right.upperArmFractured then
        if left.upperArmFractured then return side == "right" end
        return side == "left"
    end
    if left.count < right.count then return side == "left" end
    if right.count < left.count then return side == "right" end
    return true
end

function CPD.selectForcedOpeningSide(character, preferredSide, profile)
    profile = profile or CPD.getForcedOpeningFractureProfile(character)
    if profile.blocked then return nil, nil, profile end
    if CPD.isForcedOpeningSideAllowed(character, preferredSide, profile) then
        return preferredSide, preferredSide == "left" and 1 or 2, profile
    end
    local allowed = {}
    if CPD.isForcedOpeningSideAllowed(character, "left", profile) then
        allowed[#allowed + 1] = "left"
    end
    if CPD.isForcedOpeningSideAllowed(character, "right", profile) then
        allowed[#allowed + 1] = "right"
    end
    local side = allowed[randomForcedOpeningIndex(#allowed)]
    if not side then return nil, nil, profile end
    return side, side == "left" and 1 or 2, profile
end

function CPD.selectForcedOpeningMechanicalSide(character)
    if character then return CPD.selectForcedOpeningSide(character) end
    local roll = nil
    if ZombRand then
        roll = ZombRand(2) + 1
    else
        roll = math.random(1, 2)
    end
    return roll == 1 and "left" or "right", roll
end

function CPD.getForcedOpeningFractureState(character)
    local profile = CPD.getForcedOpeningFractureProfile(character)
    return profile.left.count > 0, profile.right.count > 0, profile
end

function CPD.hasBothForcedOpeningArmsFractured(character)
    local profile = CPD.getForcedOpeningFractureProfile(character)
    return profile.blocked == true, profile
end

CPD._authoritativePlayerStrengthDoorBlocks =
    CPD._authoritativePlayerStrengthDoorBlocks or {}

local function playerStrengthBlockNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function CPD.markAuthoritativePlayerStrengthDoorBlock(doorOrKey, durationMs, inputLockMs)
    local key = type(doorOrKey) == "string"
        and doorOrKey
        or CPD.getDoorWorldKey(doorOrKey)
    if not key or tostring(key) == "unknown" then return false end

    local duration = math.max(
        1000,
        tonumber(durationMs)
            or tonumber(C.PLAYER_STRENGTH_BLOCK_CACHE_MS)
            or 10000
    )
    local inputDuration = math.min(duration, math.max(
        250,
        tonumber(inputLockMs)
            or tonumber(C.PLAYER_STRENGTH_BLOCK_INPUT_LOCK_MS)
            or 1600
    ))
    local now = playerStrengthBlockNowMs()
    CPD._authoritativePlayerStrengthDoorBlocks[tostring(key)] = {
        forcedUntil = now + duration,
        inputUntil = now + inputDuration,
    }
    mpDebug("PLAYER_STRENGTH_BLOCK_CACHE",
        "key=" .. tostring(key) ..
        " durationMs=" .. tostring(duration) ..
        " inputLockMs=" .. tostring(inputDuration))
    return true
end

local function getAuthoritativePlayerStrengthDoorBlockRecord(key)
    local raw = CPD._authoritativePlayerStrengthDoorBlocks[key]
    if type(raw) == "table" then
        return tonumber(raw.forcedUntil) or 0, tonumber(raw.inputUntil) or 0
    end

    local legacyUntil = tonumber(raw) or 0
    return legacyUntil, legacyUntil
end

function CPD.hasAuthoritativePlayerStrengthDoorBlock(doorOrKey)
    local key = type(doorOrKey) == "string"
        and doorOrKey
        or CPD.getDoorWorldKey(doorOrKey)
    if not key or tostring(key) == "unknown" then return false end
    key = tostring(key)

    local expiresAt = getAuthoritativePlayerStrengthDoorBlockRecord(key)
    if expiresAt <= playerStrengthBlockNowMs() then
        CPD._authoritativePlayerStrengthDoorBlocks[key] = nil
        return false
    end
    return true
end

function CPD.isAuthoritativePlayerStrengthDoorInputLocked(doorOrKey)
    local key = type(doorOrKey) == "string"
        and doorOrKey
        or CPD.getDoorWorldKey(doorOrKey)
    if not key or tostring(key) == "unknown" then return false end
    key = tostring(key)

    local forcedUntil, inputUntil =
        getAuthoritativePlayerStrengthDoorBlockRecord(key)
    local now = playerStrengthBlockNowMs()
    if forcedUntil <= now then
        CPD._authoritativePlayerStrengthDoorBlocks[key] = nil
        return false
    end
    return inputUntil > now
end

function CPD.getForcedOpeningState(opener, door, quietPreview)
    if not CPD.isEligiblePlayerTarget(opener) then return nil, "invalid-opener" end
    if not CPD.isSupportedDoor(door) then return nil, "unsupported-door" end
    if CPD.isGarageDoor(door) then return nil, "garage-excluded" end
    if CPD.isSlidingGlassDoor(door) then return nil, "sliding-excluded" end
    if CPD.getLogicalDoorOpenState(door) ~= false then return nil, "not-closed" end

    local couldBeOpen = safeCall(door, "couldBeOpen", opener)
    if couldBeOpen == false then return nil, "vanilla-cannot-open" end
    if safeCall(door, "isObstructed") == true then return nil, "obstructed" end
    if safeCall(door, "isBarricaded") == true then return nil, "barricaded" end

    local playerSide, sideReason, sameBand, oppositeBand = CPD.getPlayerEntrySide(opener, door)
    if not playerSide then return nil, sideReason or "missing-player-side" end

    local impactSide = playerSide == "same" and "opposite" or "same"
    local playerBand = playerSide == "same" and sameBand or oppositeBand
    local impactBand = impactSide == "same" and sameBand or oppositeBand
    local standSquare = nearestSquareInBand(playerBand, opener)
    local anchor = nearestSquareInBand(impactBand, opener)
    if not standSquare or not anchor then return nil, "missing-approach-square" end

    local openingDirection = CPD.getOpeningApproachDirection(door, impactSide)
    local directionAllowed = S.allowImpactsFromBothSides()
        or openingDirection == "E"
        or openingDirection == "S"

    local zombies = {}
    local previewPlayers = nil
    if quietPreview == true and type(CPD.collectImpactPreviewTargets) == "function" then
        zombies, previewPlayers = CPD.collectImpactPreviewTargets(opener, impactBand)
    else
        local targets = CPD.collectTargetsFromSquares(impactBand or {}, opener)
        for i = 1, #targets do
            local target = targets[i]
            if CPD.isEligibleZombieTarget(target) then
                if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                    zombies[#zombies + 1] = target
                end
            end
        end
    end

    local strength = CPD.getStrength(opener)
    local capacity, baseCapacity, family, multiplier = CPD.getDoorBlockCapacity(door, strength)
    local snapshotClient = not (isServer and isServer())
        and isClient and isClient()
    local playerStrengthState, playerStrengthReason =
        CPD.getDoorPlayerStrengthBlockState(
            opener,
            door,
            "open",
            snapshotClient,
            previewPlayers
        )
    if quietPreview ~= true
        and snapshotClient
        and playerStrengthState
        and playerStrengthState.strengthPending == true
        and type(CPD.requestPlayerStrengthSnapshot) == "function" then
        pcall(CPD.requestPlayerStrengthSnapshot, false)
    end
    local livePlayerStrengthBlocked = playerStrengthState ~= nil
        and playerStrengthState.blocked == true
    local cachedPlayerStrengthBlocked = false
    if not (isServer and isServer()) and isClient and isClient() then
        cachedPlayerStrengthBlocked =
            CPD.hasAuthoritativePlayerStrengthDoorBlock(door)
    end
    local crowdBlocked = #zombies > capacity
    local playerStrengthBlocked = livePlayerStrengthBlocked
        or cachedPlayerStrengthBlocked
    local state = {
        blocked = crowdBlocked or playerStrengthBlocked,
        blockedByCrowd = crowdBlocked,
        blockedByPlayerStrength = playerStrengthBlocked,
        livePlayerStrengthBlocked = livePlayerStrengthBlocked,
        cachedPlayerStrengthBlocked = cachedPlayerStrengthBlocked,
        zombieCount = #zombies,
        zombies = zombies,
        players = playerStrengthState and playerStrengthState.players or {},
        playerCount = playerStrengthState and playerStrengthState.playerCount or 0,
        blocker = playerStrengthState and playerStrengthState.blocker or nil,
        blockerStrength = playerStrengthState and playerStrengthState.blockerStrength or nil,
        playerStrengthReason = playerStrengthReason,
        capacity = capacity,
        baseCapacity = baseCapacity,
        family = family,
        multiplier = multiplier,
        strength = strength,
        playerSide = playerSide,
        impactSide = impactSide,
        playerBand = playerBand,
        impactBand = impactBand,
        standSquare = standSquare,
        anchor = anchor,
        openingDirection = openingDirection,
        directionAllowed = directionAllowed,
    }

    if state.blocked ~= true then return state, "not-crowd-blocked" end

    local fractureBlocked, fractureProfile = CPD.hasBothForcedOpeningArmsFractured(opener)
    state.fractureProfile = fractureProfile
    if fractureBlocked then
        return state, "both-arms-fractured"
    end
    if not directionAllowed then return state, "wrong-side" end

    state.strainBlocked = CPD.isImpactBlockedByArmStrain(opener)
    state.enduranceBlocked = CPD.isImpactBlockedByEndurance(opener)
    state.resourceOverload = state.strainBlocked or state.enduranceBlocked
    return state, nil
end

function CPD.getForcedOpeningImpactSquares(state)
    if not state or not state.impactBand then return {} end
    local dx, dy = forcedOpeningDirectionVector(state.openingDirection)
    if dx == nil then return {} end

    local result = {}
    local seen = {}
    local cell = getCell and getCell() or nil
    local function append(square)
        if not square then return end
        local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
        if seen[key] then return end
        seen[key] = true
        result[#result + 1] = square
    end

    for i = 1, #state.impactBand do
        local square = state.impactBand[i]
        append(square)
        if cell and square then
            append(cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ()))
        end
    end
    return result
end

local function visitImpactPreviewMovingObjects(square, visitor)
    local moving = safeCall(square, "getMovingObjects")
    if not moving then return end

    local size = tonumber(safeCall(moving, "size"))
    if size ~= nil then
        for i = 0, math.max(0, size) - 1 do
            local target = safeCall(moving, "get", i)
            if target then visitor(target) end
        end
        return
    end
    
    if type(moving) == "table" then
        for i = 1, #moving do
            if moving[i] then visitor(moving[i]) end
        end
    end
end

function CPD.collectImpactPreviewTargets(opener, squares)
    local zombies = {}
    local players = {}
    local targetSquares = {}
    local seen = {}

    for i = 1, #(squares or {}) do
        local square = squares[i]
        visitImpactPreviewMovingObjects(square, function(target)
            if target == opener or seen[target] then return end
            local targetType = CPD.getImpactTargetType(target)
            if targetType == "zombie" then
                if not S.affectCrawlers() and safeCall(target, "isCrawling") == true then
                    return
                end
                seen[target] = true
                zombies[#zombies + 1] = target
                targetSquares[target] = square
            elseif targetType == "player" then
                seen[target] = true
                players[#players + 1] = target
                targetSquares[target] = square
            end
        end)
    end

    return zombies, players, targetSquares
end


function CPD.collectImpactPreviewZombies(opener, squares)
    local zombies, _, targetSquares = CPD.collectImpactPreviewTargets(opener, squares)
    return zombies, targetSquares
end

function CPD.getDoorImpactPreviewState(opener, door, transition, forcedOpening)
    if not CPD.isEligiblePlayerTarget(opener) then return nil, "invalid-opener" end
    if not CPD.isSupportedDoor(door) then return nil, "unsupported-door" end

    local garage = CPD.isGarageDoor(door)
    local sliding = CPD.isSlidingGlassDoor(door)
    local current = CPD.getLogicalDoorOpenState(door)
    if transition == nil then
        if garage then
            transition = current == true and "close" or nil
        elseif current == false then
            transition = "open"
        elseif current == true then
            transition = "close"
        end
    end

    if garage then
        if transition ~= "close" or current ~= true then
            return nil, "invalid-garage-transition"
        end
    else
        if transition ~= "open" and transition ~= "close" then
            return nil, "invalid-transition"
        end
        if transition == "open" and current ~= false then return nil, "not-opening" end
        if transition == "close" then
            if current ~= true then return nil, "not-closing" end
            if not CPD.supportsClosingControlImpact(door) then
                return nil, "closing-excluded"
            end
        end
    end

    forcedOpening = forcedOpening == true
    if forcedOpening and (garage or sliding or transition ~= "open") then
        return nil, "forced-opening-excluded"
    end

    if transition == "open" then
        if safeCall(door, "couldBeOpen", opener) == false then
            return nil, "vanilla-cannot-open"
        end
        if safeCall(door, "isObstructed") == true then return nil, "obstructed" end
        if safeCall(door, "isBarricaded") == true then return nil, "barricaded" end
    end

    local context, contextReason = CPD.getInteractionImpactContext(opener, door)
    if not context then return nil, contextReason or "invalid-geometry" end

    local minimumFacingDot = tonumber(C.DOOR_INTERACTION_FACING_DOT_MIN) or 0.50
    if tonumber(context.facingDot) == nil or context.facingDot < minimumFacingDot then
        return nil, "not-facing-entry"
    end

    local impactSquares = context.impactBand or {}
    local impactSide = context.impactSide
    local impactDirection = CPD.getOpeningApproachDirection(door, impactSide)
    local forcedState = nil

    if forcedOpening then
        local forcedReason = nil
        forcedState, forcedReason = CPD.getForcedOpeningState(opener, door, true)
        if not forcedState or forcedState.blocked ~= true or forcedReason ~= nil then
            return nil, forcedReason or "forced-opening-unavailable"
        end
        impactSquares = CPD.getForcedOpeningImpactSquares(forcedState)
        impactSide = forcedState.impactSide
        impactDirection = forcedState.openingDirection
    else
        if transition == "open" and not garage and not sliding
            and not S.allowImpactsFromBothSides()
            and impactDirection ~= "E" and impactDirection ~= "S" then
            return nil, "unsupported-impact-direction"
        end
        if transition == "close" and not S.allowImpactsFromBothSides()
            and impactDirection ~= "N" and impactDirection ~= "W" then
            return nil, "unsupported-impact-direction"
        end
    end

    if #impactSquares == 0 then return nil, "missing-impact-squares" end
    local zombies, players, targetSquares =
        CPD.collectImpactPreviewTargets(opener, impactSquares)

    if not forcedOpening then
        if transition == "open" and not garage then
            local capacity = CPD.getDoorBlockCapacity(
                door,
                CPD.getStrength(opener)
            )
            if #zombies > capacity then
                return nil, "crowd-blocked"
            end
        end

        if CPD.supportsPlayerStrengthBlocking(door) then
            local authoritativeSnapshot = not (isServer and isServer())
                and isClient and isClient()
            local playerState = CPD.getDoorPlayerStrengthBlockState(
                opener,
                door,
                transition,
                authoritativeSnapshot,
                players
            )
            if playerState and playerState.blocked == true then
                return nil, "player-strength-blocked"
            end
            if authoritativeSnapshot
                and CPD.hasAuthoritativePlayerStrengthDoorBlock(door) then
                return nil, "player-strength-blocked"
            end
        end

        if CPD.isImpactBlockedByArmStrain(opener) then
            return nil, "arm-strain-blocked"
        end
        if CPD.isImpactBlockedByEndurance(opener) then
            return nil, "endurance-blocked"
        end
        local recovering = CPD.isImpactRecoveryActive(opener)
        if recovering then return nil, "impact-recovery" end
    end

    return {
        door = door,
        transition = transition,
        forcedOpening = forcedOpening,
        garage = garage,
        sliding = sliding,
        impactSide = impactSide,
        impactDirection = impactDirection,
        impactSquares = impactSquares,
        anchor = forcedState and forcedState.anchor or context.anchor,
        zombies = zombies,
        zombieCount = #zombies,
        targetSquares = targetSquares,
    }, nil
end

CPD._forcedDoorTransitions = CPD._forcedDoorTransitions or {}

function CPD.markForcedDoorTransition(doorOrKey, durationMs)
    local key = type(doorOrKey) == "string" and doorOrKey or CPD.getDoorWorldKey(doorOrKey)
    if not key then return false end
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    CPD._forcedDoorTransitions[tostring(key)] = now
        + (tonumber(durationMs) or tonumber(C.FORCED_OPENING_TRANSITION_SUPPRESS_MS) or 1800)
    return true
end

function CPD.isForcedDoorTransitionMarked(doorOrKey)
    local key = type(doorOrKey) == "string" and doorOrKey or CPD.getDoorWorldKey(doorOrKey)
    if not key then return false end
    key = tostring(key)
    local expires = tonumber(CPD._forcedDoorTransitions[key]) or 0
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    if expires <= now then
        CPD._forcedDoorTransitions[key] = nil
        return false
    end
    return true
end

CPD._doorCrowdRenderPulses = CPD._doorCrowdRenderPulses or {}

local function crowdFeedbackNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function queueDoorCrowdRenderPulses(door, parts)
    if not S.animationsEnabled() then return false end
    if not RenderEffectType or not RenderEffectType.Hit_Door then return false end
    local key = nil
    pcall(function() key = CPD.getDoorWorldKey(door) end)
    key = tostring(key or door)
    CPD._doorCrowdRenderPulses[key] = {
        parts = parts,
        remaining = 3,
        nextAt = crowdFeedbackNowMs(),
    }
    return true
end

function CPD.updateDoorCrowdBlockedFeedback()
    local pendingByDoor = CPD._doorCrowdRenderPulses
    if not pendingByDoor or not RenderEffectType or not RenderEffectType.Hit_Door then return end
    if not S.animationsEnabled() then
        CPD._doorCrowdRenderPulses = {}
        return
    end

    local now = crowdFeedbackNowMs()
    for key, pending in pairs(pendingByDoor) do
        if not pending or not pending.parts or (tonumber(pending.remaining) or 0) <= 0 then
            pendingByDoor[key] = nil
        elseif now >= (tonumber(pending.nextAt) or now) then
            local seen = {}
            local applied = 0
            for i = 1, #pending.parts do
                local part = pending.parts[i]
                if part and not seen[part] then
                    seen[part] = true
                    local ok = pcall(function()
                        part:setRenderEffect(RenderEffectType.Hit_Door, true)
                    end)
                    if ok then applied = applied + 1 end
                end
            end

            pending.remaining = (tonumber(pending.remaining) or 1) - 1
            pending.nextAt = now + 90
            if pending.remaining <= 0 then
                pendingByDoor[key] = nil
            end
            CPD.mpDebug("DOOR_BLOCK_RENDER_PULSE",
                "key=" .. tostring(key) ..
                " parts=" .. tostring(applied) ..
                " remaining=" .. tostring(math.max(0, pending.remaining)))
        end
    end
end

function CPD.playDoorCrowdBlockedFeedback(opener, door, state)
    if not opener or not door or not state or state.blocked ~= true then return false end

    local parts = CPD.isDoubleDoor(door) and CPD.getDoubleDoorParts(door) or { door }
    local effectQueued = queueDoorCrowdRenderPulses(door, parts)
    local dialogueShown = false
    if type(CPD.notifyDoorCrowdBlocked) == "function" then
        local ok, result = pcall(CPD.notifyDoorCrowdBlocked, opener)
        dialogueShown = ok and result == true
    end

    local animationPlayed = false
    if state.family ~= "sliding" and type(CPD.playKickDoorAnimationForOpener) == "function" then
        local actionAnim = CPD.isSingleFenceGate(door) and "CPDPushFencesFail" or "CPDPushDoorFail"
        local ok, result = pcall(
            CPD.playKickDoorAnimationForOpener,
            opener,
            door,
            nil,
            false,
            "open",
            actionAnim
        )
        animationPlayed = ok and result == true
    end

    CPD.mpDebug("DOOR_BLOCK_FEEDBACK",
        "renderQueued=" .. tostring(effectQueued) ..
        " animationQueued=" .. tostring(animationPlayed) ..
        " dialogueShown=" .. tostring(dialogueShown) ..
        " parts=" .. tostring(#parts))
    return effectQueued or animationPlayed or dialogueShown
end

function CPD.getPlayerDoorFailAction(door, garage, transition, playerDoorAction)
    garage = garage == true or (door ~= nil and CPD.isGarageDoor(door))
    if garage then return "CPDCloseGaragesFail" end
    if transition == "close" then return "CPDPushFencesFail" end
    if door and CPD.isSlidingGlassDoor(door) then return nil end
    if playerDoorAction == "CPDPushFences" or (door and CPD.isSingleFenceGate(door)) then
        return "CPDPushFencesFail"
    end
    return "CPDPushDoorFail"
end

function CPD.restoreDoorAfterPlayerStrengthBlock(opener, door, transition, desiredOpenOverride)
    if not opener or not door then return false end
    local desiredOpen = desiredOpenOverride
    if desiredOpen == nil then desiredOpen = transition == "close" end
    desiredOpen = desiredOpen == true
    local current = CPD.getLogicalDoorOpenState(door)
    local key = CPD.getDoorWorldKey(door)
    CPD.markForcedDoorTransition(key)
    if isServer and isServer() and sendServerCommand then
        local args = CPD.makeDoorArgs(
            door,
            nil,
            true,
            desiredOpen and "open" or "close"
        ) or {}
        args.doorKey = key
        args.playerId = safeCall(opener, "getOnlineID")
        args.playerStrengthBlocked = true
        args.playerStrengthBlockCacheMs =
            tonumber(C.PLAYER_STRENGTH_BLOCK_CACHE_MS) or 10000
        args.playerStrengthBlockInputLockMs =
            tonumber(C.PLAYER_STRENGTH_BLOCK_INPUT_LOCK_MS) or 1600
        args.attemptedTransition = transition
        args.canonicalOpen = desiredOpen
        local sent = pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "forcedDoorTransition", args)
        end)
        mpDebug("PLAYER_STRENGTH_BLOCK_SIGNAL",
            "key=" .. tostring(key) ..
            " attemptedTransition=" .. tostring(transition) ..
            " cacheMs=" .. tostring(args.playerStrengthBlockCacheMs) ..
            " inputLockMs=" .. tostring(args.playerStrengthBlockInputLockMs) ..
            " canonicalOpen=" .. tostring(desiredOpen) ..
            " sent=" .. tostring(sent))
    end

    if current == desiredOpen then return true end

    if CPD.isDoubleDoor(door) and IsoDoor and IsoDoor.toggleDoubleDoor then
        pcall(IsoDoor.toggleDoubleDoor, door, true)
    else
        pcall(function() door:ToggleDoor(opener) end)
    end
    return CPD.getLogicalDoorOpenState(door) == desiredOpen
end

function CPD.playPlayerStrengthBlockedFeedback(opener, door, state, garage, transition, playerDoorAction)
    if not opener or not door or not state or state.blocked ~= true then return false end

    local feedbackKey = tostring(safeCall(opener, "getOnlineID") or opener) .. ":" ..
        tostring(CPD.getDoorWorldKey(door))
    local feedbackNow = crowdFeedbackNowMs()
    if CPD._lastPlayerStrengthBlockFeedbackKey == feedbackKey
        and feedbackNow - (tonumber(CPD._lastPlayerStrengthBlockFeedbackAt) or 0) < 750 then
        return true
    end
    CPD._lastPlayerStrengthBlockFeedbackKey = feedbackKey
    CPD._lastPlayerStrengthBlockFeedbackAt = feedbackNow

    garage = garage == true or state.garage == true or CPD.isGarageDoor(door)
    transition = transition or state.transition or (garage and "close" or "open")
    local dialogueShown = false
    if type(CPD.notifyPlayerStrengthBlocked) == "function" then
        local ok, result = pcall(CPD.notifyPlayerStrengthBlocked, opener)
        dialogueShown = ok and result == true
    end

    local failAction = CPD.getPlayerDoorFailAction(
        door, garage, transition, playerDoorAction
    )
    local animationPlayed = false
    if failAction and type(CPD.playKickDoorAnimationForOpener) == "function" then
        local ok, result = pcall(
            CPD.playKickDoorAnimationForOpener,
            opener,
            door,
            nil,
            garage,
            transition,
            failAction
        )
        animationPlayed = ok and result == true
    end

    mpDebug("PLAYER_STRENGTH_BLOCK_FEEDBACK",
        "openerStrength=" .. tostring(state.openerStrength) ..
        " blockerStrength=" .. tostring(state.blockerStrength) ..
        " action=" .. tostring(failAction or "none") ..
        " animation=" .. tostring(animationPlayed) ..
        " dialogue=" .. tostring(dialogueShown))
    return animationPlayed or dialogueShown
end

function CPD.enforcePlayerStrengthInteractionBlock(
    opener,
    door,
    preferredImpactSquare,
    transition,
    playerDoorAction,
    desiredOpenOverride
)
    if not CPD.isEligiblePlayerTarget(opener) then
        return false, nil, "invalid-opener"
    end
    if not CPD.isSupportedDoor(door) then
        return false, nil, "unsupported-door"
    end
    if not CPD.supportsPlayerStrengthBlocking(door) then
        return false, nil,
            CPD.isGarageDoor(door) and "garage-excluded" or "sliding-excluded"
    end
    if transition ~= "open" and transition ~= "close" then
        return false, nil, "invalid-transition"
    end

    local garage = CPD.isGarageDoor(door)
    if garage and transition ~= "close" then
        return false, nil, "garage-open-excluded"
    end
    if not garage and transition == "close"
        and not CPD.supportsClosingControlImpact(door) then
        return false, nil, "closing-excluded"
    end

    local playerEffectsEnabled = garage or transition == "open"
    if playerEffectsEnabled then
        playerEffectsEnabled = S.damagePlayers() or S.knockDownPlayers()
    else
        playerEffectsEnabled = S.knockDownPlayers()
    end
    if not playerEffectsEnabled then
        return false, nil, "player-effects-disabled"
    end

    local impactBand, impactSide =
        CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if not impactBand then return false, nil, "invalid-impact-side" end

    local targets = CPD.collectTargetsFromSquares(impactBand, opener)
    local players = {}
    for i = 1, #targets do
        local target = targets[i]
        if CPD.getImpactTargetType(target) == "player" then
            local pvpAllowed = CPD.canAffectPlayerInMultiplayer(opener, target)
            if pvpAllowed then players[#players + 1] = target end
        end
    end

    local blocker, openerStrength, blockerStrength, blockerReason =
        CPD.findPlayerStrengthBlocker(opener, players)
    if not blocker then
        return false, {
            blocked = false,
            players = players,
            playerCount = #players,
            openerStrength = openerStrength,
            blockerStrength = blockerStrength,
            blockerReason = blockerReason,
            garage = garage,
            transition = transition,
            impactBand = impactBand,
            impactSide = impactSide,
        }, nil
    end

    local state = {
        blocked = true,
        blocker = blocker,
        players = players,
        playerCount = #players,
        openerStrength = openerStrength,
        blockerStrength = blockerStrength,
        blockerReason = blockerReason,
        garage = garage,
        transition = transition,
        impactBand = impactBand,
        impactSide = impactSide,
    }
    state.doorRestored = CPD.restoreDoorAfterPlayerStrengthBlock(
        opener,
        door,
        transition,
        desiredOpenOverride
    )
    CPD.playPlayerStrengthBlockedFeedback(
        opener,
        door,
        state,
        garage,
        transition,
        playerDoorAction
    )
    mpDebug("PLAYER_STRENGTH_INTERACTION_ENFORCED",
        "opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
        " blocker=" .. tostring(safeCall(blocker, "getUsername") or blocker) ..
        " strength=" .. tostring(openerStrength) .. "<" .. tostring(blockerStrength) ..
        " transition=" .. tostring(transition) ..
        " canonicalOpen=" .. tostring(desiredOpenOverride) ..
        " restored=" .. tostring(state.doorRestored))
    return true, state, nil
end


local function sameSquareCoordinates(a, b)
    if not a or not b then return false end
    return safeCall(a, "getX") == safeCall(b, "getX") and
           safeCall(a, "getY") == safeCall(b, "getY") and
           safeCall(a, "getZ") == safeCall(b, "getZ")
end

local function objectOccupiesSquare(object, square)
    if not object or not square then return false end

    
    
    
    local objectSquare = safeCall(object, "getCurrentSquare") or safeCall(object, "getSquare")
    if objectSquare and sameSquareCoordinates(objectSquare, square) then
        return true
    end

    
    
    
    local ox = tonumber(safeCall(object, "getX"))
    local oy = tonumber(safeCall(object, "getY"))
    local oz = tonumber(safeCall(object, "getZ"))
    local sx = tonumber(safeCall(square, "getX"))
    local sy = tonumber(safeCall(square, "getY"))
    local sz = tonumber(safeCall(square, "getZ"))
    if not ox or not oy or not oz or not sx or not sy or not sz then return false end

    return math.floor(ox) == sx and math.floor(oy) == sy and math.floor(oz) == sz
end

local function addTargetUnique(result, seen, object, opener, source)
    if not object or object == opener or seen[object] then return false end
    local targetType, exclusionReason = CPD.getImpactTargetType(object)
    logTargetClassification(object, targetType, exclusionReason, source)
    if targetType then
        seen[object] = true
        result[#result + 1] = object
        return true
    end
    if exclusionReason ~= "unsupported" then
        mpDebug("TARGET_EXCLUDED", "reason=" .. tostring(exclusionReason))
    end
    return false
end

local function scanJavaListForSquare(list, square, opener, result, seen, source)
    local inspected = 0
    local matched = 0
    if not list then return inspected, matched end

    local okSize, size = pcall(function() return list:size() end)
    if not okSize or not size then return inspected, matched end

    inspected = tonumber(size) or 0
    for i = 0, inspected - 1 do
        local okGet, object = pcall(function() return list:get(i) end)
        if okGet and object and object ~= opener and objectOccupiesSquare(object, square) then
            if addTargetUnique(result, seen, object, opener, source) then
                matched = matched + 1
            end
        end
    end

    return inspected, matched
end

local function debugNearestServerZombies(square, zombieList)
    if not square or not zombieList then return end

    local sx = tonumber(safeCall(square, "getX"))
    local sy = tonumber(safeCall(square, "getY"))
    local sz = tonumber(safeCall(square, "getZ"))
    if not sx or not sy or not sz then return end

    local okSize, size = pcall(function() return zombieList:size() end)
    if not okSize or not size then return end

    local nearby = {}
    for i = 0, (tonumber(size) or 0) - 1 do
        local okGet, zombie = pcall(function() return zombieList:get(i) end)
        if okGet and zombie then
            local zx = tonumber(safeCall(zombie, "getX"))
            local zy = tonumber(safeCall(zombie, "getY"))
            local zz = tonumber(safeCall(zombie, "getZ"))
            if zx and zy and zz and math.floor(zz) == sz then
                local dx = zx - (sx + 0.5)
                local dy = zy - (sy + 0.5)
                local d2 = (dx * dx) + (dy * dy)
                if d2 <= 6.25 then
                    nearby[#nearby + 1] = {
                        d2 = d2,
                        text = tostring(safeCall(zombie, "getOnlineID")) .. "@" ..
                            string.format("%.2f,%.2f,%.2f", zx, zy, zz),
                    }
                end
            end
        end
    end

    table.sort(nearby, function(a, b) return a.d2 < b.d2 end)
    local parts = {}
    for i = 1, math.min(#nearby, 5) do parts[#parts + 1] = nearby[i].text end
    mpDebug("TARGET_NEAR",
        "square=" .. sx .. "," .. sy .. "," .. sz ..
        " nearby=" .. (#parts > 0 and table.concat(parts, " | ") or "none"))
end

function CPD.collectTargets(square, opener)
    local result = {}
    local seen = {}
    if not square then return result end

    local movingCount = 0
    local moving = safeCall(square, "getMovingObjects")
    if moving then
        local okSize, size = pcall(function() return moving:size() end)
        if okSize and size then
            movingCount = tonumber(size) or 0
            for i = 0, movingCount - 1 do
                local okGet, object = pcall(function() return moving:get(i) end)
                if okGet and object and object ~= opener then
                    addTargetUnique(result, seen, object, opener, "movingObjects")
                end
            end
        end
    end

    
    
    
    
    if isServer and isServer() then
        local zombieInspected, zombieMatched = 0, 0
        local playerInspected, playerMatched = 0, 0
        local cell = getCell and getCell() or nil
        local zombieList = cell and safeCall(cell, "getZombieList") or nil

        zombieInspected, zombieMatched = scanJavaListForSquare(
            zombieList, square, opener, result, seen, "zombieList"
        )

        local players = nil
        if getOnlinePlayers then
            local okPlayers, value = pcall(getOnlinePlayers)
            if okPlayers then players = value end
        end
        playerInspected, playerMatched = scanJavaListForSquare(
            players, square, opener, result, seen, "onlinePlayers"
        )

        mpDebug("TARGET_SCAN",
            "square=" .. tostring(safeCall(square, "getX")) .. "," ..
                tostring(safeCall(square, "getY")) .. "," ..
                tostring(safeCall(square, "getZ")) ..
            " moving=" .. tostring(movingCount) ..
            " zombieList=" .. tostring(zombieInspected) ..
            " zombieMatched=" .. tostring(zombieMatched) ..
            " playerList=" .. tostring(playerInspected) ..
            " playerMatched=" .. tostring(playerMatched) ..
            " total=" .. tostring(#result))

        if #result == 0 then
            debugNearestServerZombies(square, zombieList)
        end
    end

    return result
end

local function targetScore(square, opener)
    local targets = CPD.collectTargets(square, opener)
    local zombies, players = 0, 0
    for i = 1, #targets do
        local target = targets[i]
        local targetType = CPD.getImpactTargetType(target)
        if targetType == "zombie" then
            zombies = zombies + 1
        elseif targetType == "player" then
            players = players + 1
        end
    end

    return (zombies * 100) + (players * 10) + #targets, zombies, players
end

function CPD.isDoorSideSquare(door, square)
    if not door or not square then return false end
    local same, opposite = CPD.getDoorSideSquares(door)
    if square == same or square == opposite then return true end
    if same and square:getX() == same:getX() and square:getY() == same:getY() and square:getZ() == same:getZ() then return true end
    if opposite and square:getX() == opposite:getX() and square:getY() == opposite:getY() and square:getZ() == opposite:getZ() then return true end
    return false
end

function CPD.getTargetAwareImpactSquare(opener, door)
    return CPD.getImpactSquare(opener, door)
end

function CPD.findPreferredImpactSquare(args, door)
    if not args or args.impactX == nil or args.impactY == nil or args.impactZ == nil then return nil end
    local square = getCell():getGridSquare(tonumber(args.impactX), tonumber(args.impactY), tonumber(args.impactZ))
    if square and CPD.isEntrySideSquare(door, square) then return square end
    return nil
end

function CPD.notifyCombatTextDoorHit(opener, zombie, oldHealth, newHealth)
    if not opener or not zombie then return end
    oldHealth = tonumber(oldHealth)
    newHealth = tonumber(newHealth)
    if not oldHealth or not newHealth or newHealth >= oldHealth then return end

    if isServer and isServer() and sendServerCommand then
        local sq = zombie:getCurrentSquare()
        if not sq then return end
        pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "combatTextHit", {
                id = safeCall(zombie, "getOnlineID"),
                x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                oldHealth = oldHealth,
                newHealth = newHealth,
            })
        end)
        return
    end

    if CPD.onCombatTextDoorHit then
        pcall(CPD.onCombatTextDoorHit, zombie, oldHealth, newHealth)
    end
end

local function notifyZombieClients(zombie, newHealth, knockedDown, staggered, crawlerStunned, slidingAnimated, hitAnimation, staggerAnimation)
    if not isServer or not isServer() or not sendServerCommand then return end

    local zombieId = tonumber(safeCall(zombie, "getOnlineID"))
    if zombieId == nil or zombieId < 0 then
        mpDebug("SERVER_SYNC_SKIP", "zombieImpact not broadcast because zombie has invalid online id=" .. tostring(zombieId))
        return
    end
    local sq = safeCall(zombie, "getCurrentSquare")
    if not sq then
        mpDebug("SERVER_SYNC_SKIP", "zombieImpact not broadcast because zombie has no current square; zombieId=" .. tostring(zombieId))
        return
    end

    local stamp = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    local payload = {
        id = zombieId,
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        health = tonumber(newHealth),
        knockedDown = knockedDown == true,
        staggered = staggered == true,
        crawlerStunned = crawlerStunned == true,
        slidingAnimated = slidingAnimated == true,
        hitAnimation = hitAnimation,
        staggerAnimation = staggerAnimation,
        syncToken = tostring(zombieId) .. ":" .. tostring(stamp),
    }

    mpDebug("SERVER_SYNC_BROADCAST",
        "zombieImpact zombieId=" .. tostring(payload.id) ..
        " hp=" .. tostring(payload.health) ..
        " knock=" .. tostring(payload.knockedDown) ..
        " stagger=" .. tostring(payload.staggered) ..
        " staggerAnim=" .. tostring(payload.staggerAnimation) ..
        " token=" .. tostring(payload.syncToken))

    local ok, err = pcall(function()
        
        
        sendServerCommand("CyesPushDoors", "zombieImpact", payload)
    end)
    if ok then
        mpDebug("SERVER_SYNC_BROADCAST_OK", "zombieId=" .. tostring(payload.id) .. " token=" .. tostring(payload.syncToken))
    else
        mpDebug("SERVER_SYNC_BROADCAST_FAIL", "zombieId=" .. tostring(payload.id) .. " error=" .. tostring(err))
    end
end

local function getCapacityCount(capacityTable, strength, zombieCount, multiplier)
    zombieCount = math.max(0, tonumber(zombieCount) or 0)
    if zombieCount <= 0 then return 0 end

    local cap = capacityTable[strength] or capacityTable[0]
    multiplier = tonumber(multiplier) or 1.0

    if cap and cap.all == true then
        if multiplier >= 1.0 then return zombieCount end
        return math.min(zombieCount, math.max(1, math.floor((zombieCount * multiplier) + 0.5)))
    end

    local minCount = cap and tonumber(cap.min) or 0
    local maxCount = cap and tonumber(cap.max) or minCount
    if maxCount <= 0 then return 0 end

    local base = randomIntInclusive(minCount, maxCount)
    local scaled = math.floor((base * multiplier) + 0.5)
    if base > 0 and multiplier > 0 and scaled < 1 then scaled = 1 end
    return math.min(zombieCount, math.max(0, scaled))
end

function CPD.getZombieAffectedCount(strength, zombieCount)
    return getCapacityCount(C.AFFECTED_CAPACITY, strength, zombieCount, S.zombiesAffectedMultiplier())
end

function CPD.getDoubleDoorAffectedCount(strength, zombieCount)
    return getCapacityCount(
        C.DOUBLE_DOOR_AFFECTED_CAPACITY,
        strength,
        zombieCount,
        S.zombiesAffectedMultiplier()
    )
end

function CPD.getZombieKnockdownCount(strength, zombieCount)
    return getCapacityCount(C.KNOCKDOWN_CAPACITY, strength, zombieCount, 1.0)
end

function CPD.getDoubleDoorKnockdownCount(strength, zombieCount)
    return getCapacityCount(C.DOUBLE_DOOR_KNOCKDOWN_CAPACITY, strength, zombieCount, 1.0)
end

function CPD.limitZombieTargets(zombies, impactSquare, count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then return {} end
    if count >= #zombies then return zombies end

    local cx = impactSquare and (impactSquare:getX() + 0.5) or 0
    local cy = impactSquare and (impactSquare:getY() + 0.5) or 0
    local sorted = {}
    for i = 1, #zombies do
        sorted[i] = zombies[i]
    end

    table.sort(sorted, function(a, b)
        local adx = a:getX() - cx
        local ady = a:getY() - cy
        local bdx = b:getX() - cx
        local bdy = b:getY() - cy
        local da = (adx * adx) + (ady * ady)
        local db = (bdx * bdx) + (bdy * bdy)
        if da == db then
            local aid = tonumber(safeCall(a, "getOnlineID")) or 0
            local bid = tonumber(safeCall(b, "getOnlineID")) or 0
            return aid < bid
        end
        return da < db
    end)

    local result = {}
    for i = 1, math.min(count, #sorted) do
        result[#result + 1] = sorted[i]
    end
    return result
end

function CPD.prepareZombieHealth(zombie)
    if not zombie or not zombie:isAlive() then return nil end

    local health = tonumber(safeCall(zombie, "getHealth"))
    local firstUpdate = safeCall(zombie, "isFirstUpdate") == true
    local invalid = health == nil or health ~= health or health <= 0

    if invalid then
        log("Zombie health invalid; impact skipped health=" .. tostring(health) .. " firstUpdate=" .. tostring(firstUpdate))
        return nil
    end

    if firstUpdate then
        log("Zombie health pre-init health=" .. tostring(health) .. " firstUpdate=" .. tostring(firstUpdate))
        safeCall(zombie, "DoZombieStats")
        health = tonumber(safeCall(zombie, "getHealth"))
        if health == nil or health ~= health or health <= 0 then
            log("Zombie health invalid after init; impact skipped health=" .. tostring(health))
            return nil
        end
    end

    return health
end

function CPD.queueZombieDamageVerification(opener, zombie, expectedHealth, lethal)
    if not zombie then return end
    local expected = math.max(0, tonumber(expectedHealth) or 0)
    CPD._pendingZombieDamage[zombie] = {
        opener = opener,
        expectedHealth = expected,
        lethal = lethal == true,
        ticks = C.ZOMBIE_DAMAGE_VERIFY_TICKS,
    }

    if C.DEBUG == true and isServer and isServer() then
        local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
        CPD._pendingZombieNetworkVerify[zombie] = {
            expectedHealth = expected,
            lethal = lethal == true,
            verifyAt = now + 750,
        }
    end
end

function CPD.updatePendingZombieDamage()
    for zombie, pending in pairs(CPD._pendingZombieDamage) do
        local remove = false
        if not zombie or not pending then
            remove = true
        elseif not zombie:isAlive() then
            remove = true
        else
            local current = tonumber(safeCall(zombie, "getHealth"))
            if pending.lethal then

                if current == nil or current > 0 then
                    safeCall(zombie, "setAttackedBy", pending.opener)
                    safeCall(zombie, "setHealth", 0)

                    if pending.opener then
                        pcall(function() zombie:Kill(pending.opener, false) end)
                    end
                    log("Reasserted lethal door damage current=" .. tostring(current))
                end
            elseif current ~= nil and current == current and current > (pending.expectedHealth + C.ZOMBIE_HEALTH_EPSILON) then

                if safeCall(zombie, "isFirstUpdate") == true then
                    safeCall(zombie, "DoZombieStats")
                    current = tonumber(safeCall(zombie, "getHealth")) or current
                end
                if current > (pending.expectedHealth + C.ZOMBIE_HEALTH_EPSILON) then
                    safeCall(zombie, "setHealth", pending.expectedHealth)
                    log("Reapplied door damage health=" .. tostring(current) .. "->" .. tostring(pending.expectedHealth))
                end
            end

            pending.ticks = (pending.ticks or 1) - 1
            if pending.ticks <= 0 then remove = true end
        end

        if remove then CPD._pendingZombieDamage[zombie] = nil end
    end

    if C.DEBUG == true and isServer and isServer() then
        local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
        for zombie, pending in pairs(CPD._pendingZombieNetworkVerify) do
            if not zombie or not pending then
                CPD._pendingZombieNetworkVerify[zombie] = nil
            elseif now >= (pending.verifyAt or 0) then
                local actual = tonumber(safeCall(zombie, "getHealth"))
                mpDebug("SERVER_VERIFY_750MS",
                    "zombieId=" .. tostring(safeCall(zombie, "getOnlineID")) ..
                    " expected=" .. tostring(pending.expectedHealth) ..
                    " actual=" .. tostring(actual) ..
                    " alive=" .. tostring(safeCall(zombie, "isAlive")))
                CPD._pendingZombieNetworkVerify[zombie] = nil
            end
        end
    end
end

function CPD.applyImpactDirection(target, door, impactSquare, strength, applyForce)
    if not target or not door then return end
    local same, opposite = CPD.getDoorSideSquares(door)
    local cx, cy
    if same and opposite then
        cx = ((same:getX() + 0.5) + (opposite:getX() + 0.5)) * 0.5
        cy = ((same:getY() + 0.5) + (opposite:getY() + 0.5)) * 0.5
    else
        local dsq = door:getSquare()
        if not dsq then return end
        cx, cy = dsq:getX() + 0.5, dsq:getY() + 0.5
    end

    local tx = target:getX()
    local ty = target:getY()
    local dx, dy = tx - cx, ty - cy
    local len = math.sqrt((dx * dx) + (dy * dy))
    if len < 0.001 and impactSquare then
        dx = (impactSquare:getX() + 0.5) - cx
        dy = (impactSquare:getY() + 0.5) - cy
        len = math.sqrt((dx * dx) + (dy * dy))
    end
    if len < 0.001 then return end

    dx, dy = dx / len, dy / len
    if Vector2 and Vector2.new then
        local ok, vec = pcall(Vector2.new, dx, dy)
        if ok and vec then safeCall(target, "setHitDir", vec) end
    end
    if applyForce == false then
        safeCall(target, "setHitForce", 0.0)
    else
        safeCall(target, "setHitForce", 0.20 + (0.045 * (tonumber(strength) or 0)))
    end
end

function CPD.applyZombieImpact(opener, zombie, strength, forceKnockdown, door, impactSquare, impactMods, doorProfile)
    if not CPD.isEligibleZombieTarget(zombie) then return false end
    if isServer and isServer() then
        local onlineId = tonumber(safeCall(zombie, "getOnlineID"))
        if onlineId == nil or onlineId < 0 then
            mpDebug("SERVER_ZOMBIE_SKIP", "impact skipped because zombie has invalid online id=" .. tostring(onlineId))
            return false
        end
    end
    local row = C.STRENGTH[strength] or C.STRENGTH[0]
    impactMods = impactMods or C.ARM_STRAIN_DEBUFF.none
    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, strength)

    safeCall(zombie, "setAttackedBy", opener)
    local health = CPD.prepareZombieHealth(zombie)
    if not health then return false end

    local damageMult = tonumber(impactMods.damageMult) or 1.0
    local knockdownMult = tonumber(impactMods.knockdownMult) or 1.0
    local knockdownChance = clamp(knockdownMult * S.zombieKnockdownChance(), 0.0, 1.0)

    local damageMin = row.zombieDamageMin
    local damageMax = row.zombieDamageMax
    if doorProfile.zombieDamageMin ~= nil then
        damageMin = tonumber(doorProfile.zombieDamageMin) or 0
        damageMax = tonumber(doorProfile.zombieDamageMax) or damageMin
    else
        local profileDamageMult = tonumber(doorProfile.zombieDamageMult) or 1.0
        damageMin = damageMin * profileDamageMult
        damageMax = damageMax * profileDamageMult
    end

    local fraction = randomFloat(damageMin, damageMax) * damageMult * S.zombieDamageMultiplier()
    local maxFraction = tonumber(doorProfile.maxZombieDamageFraction)
    if maxFraction ~= nil then
        fraction = math.min(fraction, math.max(0, maxFraction))
    end
    local damage = math.max(0, health * fraction)
    local newHealth = math.max(0, health - damage)

    local lethal = damage > 0 and (newHealth <= 0 or newHealth <= C.ZOMBIE_FINISH_HEALTH)
    local crawler = safeCall(zombie, "isCrawling") == true
    if crawler and not S.affectCrawlers() then return false end
    local knockedDown = false
    local crawlerStunned = false
    local slidingAnimated = false
    local slidingAnimation = nil
    local staggerAnimation = nil

    if not lethal then
        if doorProfile.sliding == true then
            slidingAnimated = doorProfile.forceZombieStun == true
            if slidingAnimated then
                slidingAnimation = CPD.selectSlidingDoorAnimation(zombie)
            end
        elseif crawler then
            crawlerStunned = true
        elseif forceKnockdown == "always" then
            knockedDown = true
        elseif forceKnockdown == true then
            knockedDown = randomFloat(0.0, 1.0) < knockdownChance
        end
    end

    local staggered = not lethal and not knockedDown and not crawlerStunned and not slidingAnimated
    if staggered then
        staggerAnimation = CPD.selectDoorStaggerAnimation()
    end
    CPD.applyImpactDirection(zombie, door, impactSquare, strength, not knockedDown)

    if lethal then
        safeCall(zombie, "setHealth", 0)
        pcall(function() zombie:Kill(opener, false) end)
        newHealth = 0
        CPD.queueZombieDamageVerification(opener, zombie, 0, true)
    else
        safeCall(zombie, "setHealth", newHealth)
        local after = tonumber(safeCall(zombie, "getHealth"))
        if after ~= nil and after > (newHealth + C.ZOMBIE_HEALTH_EPSILON) then
            safeCall(zombie, "setHealth", newHealth)
        end
        CPD.queueZombieDamageVerification(opener, zombie, newHealth, false)

        if slidingAnimated then
            if S.animationsEnabled() and (not isServer or not isServer()) then
                CPD.playSlidingDoorAnimation(zombie, slidingAnimation)
            end
        elseif crawlerStunned then
            safeCall(zombie, "setHitLegsWhileOnFloor", true)
            safeCall(zombie, "setHitTime", C.CRAWLER_STUN_HIT_TIME)
        elseif knockedDown then
            safeCall(zombie, "setHitForce", 0.0)
            local okSetDown = pcall(function() zombie:setKnockedDown(true) end)
            if not okSetDown then pcall(function() zombie:knockDown(false) end) end
        else
            if S.animationsEnabled() and (not isServer or not isServer()) then
                CPD.playDoorStaggerAnimation(zombie, staggerAnimation)
            end
        end
    end

    log("Zombie door damage strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " crawler=" .. tostring(crawler) ..
        " strainBand=" .. tostring(impactMods.band or "none") ..
        " damageMult=" .. string.format("%.2f", damageMult) ..
        " knockMult=" .. string.format("%.2f", knockdownMult) ..
        " knockChance=" .. string.format("%.2f", knockdownChance) ..
        " health=" .. tostring(health) ..
        " fraction=" .. string.format("%.4f", fraction) ..
        " damage=" .. string.format("%.4f", damage) ..
        " expected=" .. tostring(newHealth) ..
        " knockedDown=" .. tostring(knockedDown) ..
        " crawlerStunned=" .. tostring(crawlerStunned) ..
        " slidingAnimated=" .. tostring(slidingAnimated) ..
        " hitAnimation=" .. tostring(slidingAnimation) ..
        " staggerAnimation=" .. tostring(staggerAnimation) ..
        " lethal=" .. tostring(lethal))

    local dbgSq = safeCall(zombie, "getCurrentSquare")
    mpDebug("SERVER_ZOMBIE_RESULT",
        "zombieId=" .. tostring(safeCall(zombie, "getOnlineID")) ..
        " hp=" .. tostring(health) .. "->" .. tostring(newHealth) ..
        " damage=" .. tostring(damage) ..
        " lethal=" .. tostring(lethal) ..
        " knock=" .. tostring(knockedDown) ..
        " stagger=" .. tostring(staggered) ..
        " square=" .. tostring(dbgSq and (dbgSq:getX() .. "," .. dbgSq:getY() .. "," .. dbgSq:getZ()) or "nil"))

    CPD.notifyCombatTextDoorHit(opener, zombie, health, newHealth)
    notifyZombieClients(zombie, newHealth, knockedDown, staggered, crawlerStunned, slidingAnimated, slidingAnimation, staggerAnimation)
    return true, knockedDown, crawlerStunned
end

function CPD.getPlayerContest(opener, target)
    local aStrength = CPD.getStrength(opener)
    local aFitness = CPD.getFitness(opener)
    local tStrength = CPD.getStrength(target)
    local tFitness = CPD.getFitness(target)

    local strengthWin = aStrength > tStrength
    local fitnessWin = aFitness > tFitness

    if strengthWin and fitnessWin then
        return 1.00, 1.35, aStrength, aFitness, tStrength, tFitness
    end
    if strengthWin or fitnessWin then
        return 0.50, 1.00, aStrength, aFitness, tStrength, tFitness
    end
    return 0.00, 0.65, aStrength, aFitness, tStrength, tFitness
end

function CPD.applyPlayerImpact(
    opener,
    target,
    strength,
    door,
    impactSquare,
    impactMods,
    doorProfile,
    forceKnockdown,
    bypassStrengthBlock
)
    if not target or not target:isAlive() then return false end

    local pvpAllowed, pvpReason = CPD.canAffectPlayerInMultiplayer(opener, target)
    if not pvpAllowed then
        mpDebug("PLAYER_PVP_SKIP",
            "route=opening opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " target=" .. tostring(safeCall(target, "getUsername") or target) ..
            " reason=" .. tostring(pvpReason))
        return false
    end

    local strengthBlocked, openerStrength, targetStrength =
        CPD.isPlayerStrengthBlocking(opener, target)
    if strengthBlocked and bypassStrengthBlock ~= true then
        mpDebug("PLAYER_STRENGTH_BLOCK",
            "route=opening opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " target=" .. tostring(safeCall(target, "getUsername") or target) ..
            " strength=" .. tostring(openerStrength) .. "<" .. tostring(targetStrength))
        return false, "stronger-player"
    end
    if strengthBlocked then
        mpDebug("FORCED_PLAYER_STRENGTH_OVERRIDE",
            "opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " target=" .. tostring(safeCall(target, "getUsername") or target) ..
            " strength=" .. tostring(openerStrength) .. "<" .. tostring(targetStrength))
    end

    local allowDamage = S.damagePlayers()
    local allowKnockdown = S.knockDownPlayers()
    if not allowDamage and not allowKnockdown then return false end

    impactMods = impactMods or C.ARM_STRAIN_DEBUFF.none
    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, strength)

    local chance, damageMult = CPD.getPlayerContest(opener, target)
    local row = C.STRENGTH[strength] or C.STRENGTH[0]
    local strainDamageMult = tonumber(impactMods.damageMult) or 1.0
    local strainKnockMult = tonumber(impactMods.knockdownMult) or 1.0
    local profileDamageMult = tonumber(doorProfile.playerDamageMult) or 1.0
    local knockdownChance = clamp(chance * strainKnockMult * S.playerKnockdownChance(), 0.0, 1.0)
    if forceKnockdown == true
        and allowKnockdown
        and doorProfile.neverPlayerKnockdown ~= true then
        knockdownChance = 1.0
    end

    local damage = 0
    if allowDamage then
        damage = row.playerDamage * damageMult * strainDamageMult * profileDamageMult * randomFloat(0.85, 1.15)
    end

    local knockedDown = false
    if allowKnockdown and doorProfile.neverPlayerKnockdown ~= true then
        if forceKnockdown == true then
            knockedDown = true
        else
            knockedDown = randomFloat(0.0, 1.0) < knockdownChance
        end
    end

    CPD.applyImpactDirection(target, door, impactSquare, strength)

    local bodyDamage = target:getBodyDamage()
    if bodyDamage and damage > 0 then
        bodyDamage:ReduceGeneralHealth(damage)
    end

    if knockedDown then
        safeCall(target, "setHitForce", 0.0)
        safeCall(target, "setFallOnFront", false)
        safeCall(target, "setKnockedDown", true)
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(target, "CyesPushDoors", "playerImpact", {
            knockedDown = knockedDown,
            playerId = safeCall(target, "getOnlineID"),
        })
    end

    log("Player door impact strength=" .. tostring(strength) ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " damage=" .. string.format("%.4f", damage) ..
        " knockChance=" .. string.format("%.2f", knockdownChance) ..
        " knockedDown=" .. tostring(knockedDown))
    return damage > 0 or knockedDown
end

function CPD.applyZombieClosingImpact(opener, zombie, strength, forceKnockdown, door, impactSquare, impactMods)
    if not CPD.isEligibleZombieTarget(zombie) then return false end
    if isServer and isServer() then
        local onlineId = tonumber(safeCall(zombie, "getOnlineID"))
        if onlineId == nil or onlineId < 0 then
            mpDebug("SERVER_ZOMBIE_SKIP", "closing impact skipped because zombie has invalid online id=" .. tostring(onlineId))
            return false
        end
    end

    local crawler = safeCall(zombie, "isCrawling") == true
    if crawler and not S.affectCrawlers() then return false end

    impactMods = impactMods or C.ARM_STRAIN_DEBUFF.none
    local knockdownMult = tonumber(impactMods.knockdownMult) or 1.0
    local knockdownChance = clamp(knockdownMult * S.zombieKnockdownChance(), 0.0, 1.0)
    local knockedDown = false
    local crawlerStunned = false

    if crawler then
        crawlerStunned = true
    elseif forceKnockdown == true then
        knockedDown = randomFloat(0.0, 1.0) < knockdownChance
    end

    local staggered = not knockedDown and not crawlerStunned
    local staggerAnimation = staggered and CPD.selectDoorStaggerAnimation() or nil
    CPD.applyImpactDirection(zombie, door, impactSquare, strength, false)

    if crawlerStunned then
        safeCall(zombie, "setHitLegsWhileOnFloor", true)
        safeCall(zombie, "setHitTime", C.CRAWLER_STUN_HIT_TIME)
    elseif knockedDown then
        safeCall(zombie, "setHitForce", 0.0)
        local okSetDown = pcall(function() zombie:setKnockedDown(true) end)
        if not okSetDown then pcall(function() zombie:knockDown(false) end) end
    elseif S.animationsEnabled() and (not isServer or not isServer()) then
        CPD.playDoorStaggerAnimation(zombie, staggerAnimation)
    end

    notifyZombieClients(zombie, nil, knockedDown, staggered, crawlerStunned, false, nil, staggerAnimation)
    mpDebug("CLOSING_ZOMBIE_RESULT",
        "zombieId=" .. tostring(safeCall(zombie, "getOnlineID")) ..
        " healthPreserved=true" ..
        " knock=" .. tostring(knockedDown) ..
        " stagger=" .. tostring(staggered) ..
        " crawler=" .. tostring(crawlerStunned))
    return true, knockedDown, crawlerStunned
end

function CPD.applyPlayerClosingImpact(opener, target, strength, impactMods)
    if not CPD.isEligiblePlayerTarget(target) or not S.knockDownPlayers() then return false end

    local pvpAllowed, pvpReason = CPD.canAffectPlayerInMultiplayer(opener, target)
    if not pvpAllowed then
        mpDebug("PLAYER_PVP_SKIP",
            "route=closing opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " target=" .. tostring(safeCall(target, "getUsername") or target) ..
            " reason=" .. tostring(pvpReason))
        return false
    end

    local strengthBlocked, openerStrength, targetStrength =
        CPD.isPlayerStrengthBlocking(opener, target)
    if strengthBlocked then
        mpDebug("PLAYER_STRENGTH_BLOCK",
            "route=closing opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " target=" .. tostring(safeCall(target, "getUsername") or target) ..
            " strength=" .. tostring(openerStrength) .. "<" .. tostring(targetStrength))
        return false, "stronger-player"
    end

    impactMods = impactMods or C.ARM_STRAIN_DEBUFF.none
    local chance = CPD.getPlayerContest(opener, target)
    local strainKnockMult = tonumber(impactMods.knockdownMult) or 1.0
    local knockdownChance = clamp(chance * strainKnockMult * S.playerKnockdownChance(), 0.0, 1.0)
    local knockedDown = randomFloat(0.0, 1.0) < knockdownChance

    if knockedDown then
        safeCall(target, "setHitForce", 0.0)
        safeCall(target, "setFallOnFront", false)
        safeCall(target, "setKnockedDown", true)
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(target, "CyesPushDoors", "playerImpact", {
            knockedDown = knockedDown,
            playerId = safeCall(target, "getOnlineID"),
        })
    end

    mpDebug("CLOSING_PLAYER_RESULT",
        "target=" .. tostring(safeCall(target, "getUsername") or target) ..
        " damage=0" ..
        " knockChance=" .. string.format("%.2f", knockdownChance) ..
        " knockedDown=" .. tostring(knockedDown))
    return true, knockedDown
end

local function syncDoorHealth(door, health)
    if instanceof(door, "IsoThumpable") then
        pcall(function() door:syncIsoThumpable() end)
    end

    if isServer and isServer() and sendServerCommand then
        local sq = door:getSquare()
        if sq then
            sendServerCommand("CyesPushDoors", "doorHealth", {
                x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                index = door:getObjectIndex(),
                health = health,
            })
        end
    end
end

local function destroyDoor(door)
    if not door then return end

    if CPD.isGarageDoor(door) and IsoDoor and IsoDoor.destroyGarageDoor then
        local okDestroy, result = pcall(IsoDoor.destroyGarageDoor, door)
        if okDestroy and result == true then return end
    end

    if IsoDoor and IsoDoor.getDoubleDoorIndex and IsoDoor.destroyDoubleDoor then
        local ok, index = pcall(IsoDoor.getDoubleDoorIndex, door)
        if ok and index ~= nil and tonumber(index) and tonumber(index) >= 0 then
            local destroyed = false
            local okDestroy, result = pcall(IsoDoor.destroyDoubleDoor, door)
            if okDestroy then destroyed = result == true end
            if destroyed then return end
        end
    end

    pcall(function() door:destroy() end)
end

function CPD.applyDoorWear(door, strength, zombieCount, playerCount, doorProfile, wearContext)
    zombieCount = math.max(0, tonumber(zombieCount) or 0)
    playerCount = math.max(0, tonumber(playerCount) or 0)
    local targetCount = zombieCount + playerCount
    if targetCount <= 0 or not door then return false end

    strength = clamp(tonumber(strength) or 0, 0, 10)
    local row = C.STRENGTH[strength]
    if not row then return false end

    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, strength)
    local garage = CPD.isGarageDoor(door)
    local doubleDoor = CPD.isDoubleDoor(door)
    local healthDoor = door
    if garage then
        healthDoor = CPD.getGarageDoorMaster(door) or door
    elseif doubleDoor then
        healthDoor = CPD.getDoubleDoorMaster(door) or door
    end
    local health = safeCall(healthDoor, "getHealth")
    local maxHealth = safeCall(healthDoor, "getMaxHealth")
    if not health or not maxHealth or maxHealth <= 0 then return false end

    if S.doorWearMultiplier() <= 0 then return false end

    local material = CPD.getDoorMaterial(healthDoor)
    local materialMult = 1.0
    if doorProfile.ignoreMaterialWear ~= true then
        materialMult = C.MATERIAL_DOOR_DAMAGE_MULTIPLIER[material] or 1.0
    end

    local profileWearMult = tonumber(doorProfile.doorWearMult) or 1.0
    local rawWear = 0
    local wearMode = "normal"
    local capacity = nil
    local pressure = nil
    local extraZombies = nil
    local finalWearFraction = nil

    if garage then
        wearMode = "garage"
        
        
        local garageRow = (C.GARAGE_DOOR_WEAR_PER_TARGET or {})[strength]
            or (C.GARAGE_DOOR_WEAR_PER_TARGET or {})[0]
        if not garageRow then return false end

        local durabilityMult = math.max(0.05, tonumber(C.GARAGE_DOOR_DURABILITY_MULT) or 0.75)
        local wearHealthBasis = maxHealth / durabilityMult
        local zombieWearMult = math.max(0, tonumber(C.GARAGE_ZOMBIE_WEAR_MULT) or 1.0)
        local playerWearMult = math.max(0, tonumber(C.GARAGE_PLAYER_WEAR_MULT) or 1.0)

        for i = 1, zombieCount do
            local wearFraction = randomFloat(garageRow.min, garageRow.max)
            rawWear = rawWear + (wearHealthBasis * wearFraction * zombieWearMult)
        end
        for i = 1, playerCount do
            local wearFraction = randomFloat(garageRow.min, garageRow.max)
            rawWear = rawWear + (wearHealthBasis * wearFraction * playerWearMult)
        end
    else
        wearContext = type(wearContext) == "table" and wearContext or {}
        local forced = wearContext.forced == true
        local wearValues = forced and (C.FORCED_DOOR_WEAR or {}) or (C.NORMAL_DOOR_WEAR or {})
        local wearFraction = 0.0

        if forced then
            wearMode = "forced"
            capacity = math.max(1, math.floor(tonumber(wearContext.capacity)
                or select(1, CPD.getDoorBlockCapacity(door, strength))))
            extraZombies = math.max(0, zombieCount - capacity)
            wearFraction = randomFloat(
                tonumber(wearValues.baseMin) or 0.025,
                tonumber(wearValues.baseMax) or 0.040
            ) + (extraZombies * (tonumber(wearValues.perZombieOverCapacity) or 0.005))
        else
            capacity = select(1, CPD.getDoorBlockCapacity(door, strength))
            pressure = clamp(targetCount / math.max(1, capacity), 0.0, 1.0)
            local loadMultiplier = (tonumber(wearValues.loadBase) or 0.75)
                + ((tonumber(wearValues.loadPressure) or 0.75) * pressure)
            local crowdMultiplier = 1.0
                + (math.max(0, targetCount - 1)
                    * (tonumber(wearValues.crowdPerExtraTarget) or 0.25))
            crowdMultiplier = math.min(
                crowdMultiplier,
                tonumber(wearValues.crowdMultiplierMax) or 2.0
            )
            wearFraction = randomFloat(
                tonumber(wearValues.baseMin) or 0.006,
                tonumber(wearValues.baseMax) or 0.010
            ) * loadMultiplier * crowdMultiplier
        end

        local sandboxWearMult = S.doorWearMultiplier()
        if forced then
            sandboxWearMult = sandboxWearMult * S.forcedOpeningDoorWearMultiplier()
        end
        wearFraction = wearFraction * materialMult * profileWearMult * sandboxWearMult
        local maximumFraction = tonumber(wearValues.maxFractionPerAction)
            or (forced and 0.08 or 0.04)
        finalWearFraction = clamp(wearFraction, 0.0, maximumFraction)
        if finalWearFraction <= 0.0 then return false end
        rawWear = maxHealth * finalWearFraction
    end

    local sandboxWearMult = S.doorWearMultiplier()
    if garage then
        sandboxWearMult = sandboxWearMult * S.garageDoorWearMultiplier()
    end

    local adjustedWear = rawWear
    if garage then
        adjustedWear = rawWear * materialMult * profileWearMult * sandboxWearMult
    end
    local wear = math.floor(adjustedWear + 0.5)
    if wear < 1 then wear = 1 end

    local newHealth = math.max(0, health - wear)
    if garage then
        local parts = CPD.getGarageDoorParts(door)
        for i = 1, #parts do
            safeCall(parts[i], "setHealth", newHealth)
            syncDoorHealth(parts[i], newHealth)
        end
    elseif doubleDoor then
        local parts = CPD.getDoubleDoorParts(door)
        for i = 1, #parts do
            safeCall(parts[i], "setHealth", newHealth)
            syncDoorHealth(parts[i], newHealth)
        end
    else
        door:setHealth(newHealth)
        syncDoorHealth(door, newHealth)
    end

    log("Door impact strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " material=" .. material ..
        " mode=" .. wearMode ..
        " zombies=" .. zombieCount ..
        " players=" .. playerCount ..
        " capacity=" .. tostring(capacity or "n/a") ..
        " pressure=" .. (pressure and string.format("%.3f", pressure) or "n/a") ..
        " extraZombies=" .. tostring(extraZombies or 0) ..
        " wearFraction=" .. (finalWearFraction and string.format("%.4f", finalWearFraction) or "garage") ..
        " wear=" .. wear ..
        " health=" .. health .. "->" .. newHealth)

    if newHealth <= 0 then
        destroyDoor(door)
        return true
    end

    return false
end

function CPD.rollGarageBreakChance(door, strength, conditionHealth, conditionMaxHealth)
    if not door or not CPD.isGarageDoor(door) then return false end
    if S.doorWearMultiplier() <= 0 then return false end

    strength = clamp(tonumber(strength) or 0, 0, 10)
    local healthDoor = CPD.getGarageDoorMaster(door) or door
    local health = tonumber(safeCall(healthDoor, "getHealth")) or 0
    local maxHealth = tonumber(safeCall(healthDoor, "getMaxHealth")) or 0
    if maxHealth <= 0 then return false end
    if health <= 0 then
        destroyDoor(door)
        return true
    end

    local failureMult = S.garageFailureChanceMultiplier()
    if failureMult <= 0 then return false end

    local strengthChance = tonumber((C.GARAGE_FORCE_BREAK_CHANCE or {})[strength]) or 0
    local chanceHealth = tonumber(conditionHealth) or health
    local chanceMaxHealth = tonumber(conditionMaxHealth) or maxHealth
    if chanceMaxHealth <= 0 then chanceMaxHealth = maxHealth end
    local lostCondition = clamp(1.0 - (chanceHealth / chanceMaxHealth), 0.0, 1.0)
    local conditionChance = lostCondition * (tonumber(C.GARAGE_CONDITION_BREAK_CHANCE_MAX) or 0.20)
    local maxChance = tonumber(C.GARAGE_TOTAL_BREAK_CHANCE_MAX) or 0.75
    local baseChance = strengthChance + conditionChance
    local totalChance = clamp(baseChance * failureMult, 0.0, maxChance)

    if totalChance <= 0 then return false end

    local roll = randomFloat(0.0, 1.0)
    log("Garage failure roll strength=" .. tostring(strength) ..
        " strengthChance=" .. string.format("%.3f", strengthChance) ..
        " conditionChance=" .. string.format("%.3f", conditionChance) ..
        " multiplier=" .. string.format("%.2f", failureMult) ..
        " total=" .. string.format("%.3f", totalChance) ..
        " roll=" .. string.format("%.3f", roll))

    if roll < totalChance then
        local stressRow = (C.GARAGE_FORCE_STRESS_DAMAGE or {})[strength]
            or (C.GARAGE_FORCE_STRESS_DAMAGE or {})[0]
        if not stressRow then return false end

        local stressFraction = randomFloat(stressRow.min, stressRow.max)
        if stressFraction <= 0 then return false end
        local structuralDamage = math.floor((maxHealth * stressFraction) + 0.5)
        if structuralDamage < 1 then structuralDamage = 1 end

        local newHealth = math.max(0, health - structuralDamage)
        local parts = CPD.getGarageDoorParts(door)
        for i = 1, #parts do
            safeCall(parts[i], "setHealth", newHealth)
            syncDoorHealth(parts[i], newHealth)
        end

        if newHealth <= 0 then
            destroyDoor(door)
            log("Garage door failed from force/condition")
            return true
        end
    end

    return false
end

local function playBlockedImpactFailAnimation(opener, door, garage, transition, playerDoorAction)
    local failAction = CPD.getPlayerDoorFailAction(door, garage, transition, playerDoorAction)
    if not failAction then return false end
    return pcall(CPD.playKickDoorAnimationForOpener, opener, door, nil, garage == true, transition, failAction)
end

function CPD.resolveDoorClosingImpact(opener, door, preferredImpactSquare)
    if not opener or not door then return false end
    if not CPD.isEligiblePlayerTarget(opener) then
        mpDebug("INVALID_OPENER", "reason=invalid-opener id=" .. tostring(safeCall(opener, "getOnlineID")))
        return false
    end
    if not CPD.supportsClosingControlImpact(door) then return false end
    if CPD.getLogicalDoorOpenState(door) ~= false then return false end

    local strainBlockedAtStart = CPD.isImpactBlockedByArmStrain(opener)
    local enduranceBlockedAtStart = CPD.isImpactBlockedByEndurance(opener)

    local recovering, recoveryRemainingMs, recoveryBand = CPD.isImpactRecoveryActive(opener)
    if recovering and not strainBlockedAtStart and not enduranceBlockedAtStart then
        mpDebug("CLOSING_RECOVERY_BLOCK",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " band=" .. tostring(recoveryBand) ..
            " remainingMs=" .. tostring(recoveryRemainingMs))
        return false
    end

    local impactSquares, impactSide = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    local geometrySource = "preferred"
    if not impactSquares then
        local context, geometryReason = CPD.getInteractionImpactContext(opener, door)
        if context then
            impactSquares = context.impactBand
            impactSide = context.impactSide
            geometrySource = "runtime"
        else
            impactSquares = {}
            geometrySource = "invalid:" .. tostring(geometryReason or "unknown")
        end
    end

    local closingDirection = CPD.getOpeningApproachDirection(door, impactSide)
    if not S.allowImpactsFromBothSides()
        and closingDirection ~= "N" and closingDirection ~= "W" then
        mpDebug("CLOSING_DIRECTION_BLOCK",
            "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
            " direction=" .. tostring(closingDirection or "unresolved") ..
            " impactSide=" .. tostring(impactSide or "none"))
        return false
    end

    if CPD.isDuplicateImpact(opener, door) then return false end

    mpDebug("CLOSING_GEOMETRY",
        "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
        " source=" .. tostring(geometrySource) ..
        " direction=" .. tostring(closingDirection) ..
        " impactSide=" .. tostring(impactSide or "none") ..
        " squares=" .. tostring(#impactSquares))

    if #impactSquares == 0 then return false end

    local targets, targetSquares = CPD.collectTargetsFromSquares(impactSquares, opener)
    if #targets == 0 then return false end

    local strength = CPD.getStrength(opener)
    local fitness = CPD.getFitness(opener)
    local doubleDoor = CPD.isDoubleDoor(door)
    local doorProfile = CPD.getDoorImpactProfile(door, strength)
    local zombies = {}
    local players = {}

    for i = 1, #targets do
        local target = targets[i]
        local targetType = CPD.getImpactTargetType(target)
        if targetType == "zombie" then
            if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                zombies[#zombies + 1] = target
            end
        elseif targetType == "player" then
            local pvpAllowed, pvpReason = CPD.canAffectPlayerInMultiplayer(opener, target)
            if pvpAllowed then
                players[#players + 1] = target
            else
                mpDebug("PLAYER_PVP_FILTER",
                    "route=closing opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
                    " target=" .. tostring(safeCall(target, "getUsername") or target) ..
                    " reason=" .. tostring(pvpReason))
            end
        end
    end

    if S.knockDownPlayers() and #players > 0 then
        local blocker, openerStrength, blockerStrength, blockerReason =
            CPD.findPlayerStrengthBlocker(opener, players)
        if blocker then
            local blockState = {
                blocked = true,
                blocker = blocker,
                openerStrength = openerStrength,
                blockerStrength = blockerStrength,
                blockerReason = blockerReason,
                transition = "close",
                garage = false,
            }
            blockState.doorRestored = CPD.restoreDoorAfterPlayerStrengthBlock(
                opener, door, "close"
            )
            CPD.playPlayerStrengthBlockedFeedback(
                opener, door, blockState, false, "close", "CPDPushFences"
            )
            mpDebug("CLOSING_PLAYER_STRENGTH_BLOCK",
                "opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
                " blocker=" .. tostring(safeCall(blocker, "getUsername") or blocker) ..
                " strength=" .. tostring(openerStrength) .. "<" .. tostring(blockerStrength) ..
                " restored=" .. tostring(blockState.doorRestored))
            return false
        end
    end

    local validTargetCount = #zombies + #players
    local strainBlocked = CPD.isImpactBlockedByArmStrain(opener)
    local enduranceBlocked = CPD.isImpactBlockedByEndurance(opener)
    if validTargetCount > 0 and (strainBlocked or enduranceBlocked) then
        mpDebug("CLOSING_RESOURCE_BLOCK",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " strainBlocked=" .. tostring(strainBlocked) ..
            " enduranceBlocked=" .. tostring(enduranceBlocked) ..
            " usageLimit=" .. string.format("%.2f", CPD.getArmStrainUsageLimit()) ..
            " endurance=" .. string.format("%.3f", CPD.getEndurance(opener)))
        CPD.notifyImpactBlocked(opener, strainBlocked, enduranceBlocked)
        playBlockedImpactFailAnimation(opener, door, false, "close", "CPDPushFences")
        return false
    end

    if #zombies > 0 then
        local cap = doubleDoor
            and CPD.getDoubleDoorAffectedCount(strength, #zombies)
            or CPD.getZombieAffectedCount(strength, #zombies)
        if doubleDoor and cap < #zombies then
            local shuffledTargets = shuffledCopy(zombies)
            local limited = {}
            for i = 1, cap do limited[i] = shuffledTargets[i] end
            zombies = limited
        else
            zombies = CPD.limitZombieTargets(zombies, impactSquares[1], cap)
        end
        mpDebug("CLOSING_CAPACITY",
            "profile=" .. tostring(doorProfile.kind or "standard") ..
            " cap=" .. tostring(cap) ..
            " affected=" .. tostring(#zombies))
    end

    local knockableZombies = {}
    for i = 1, #zombies do
        if safeCall(zombies[i], "isCrawling") ~= true then
            knockableZombies[#knockableZombies + 1] = zombies[i]
        end
    end

    local shuffledZombies = shuffledCopy(knockableZombies)
    local knockdownCount = doubleDoor
        and CPD.getDoubleDoorKnockdownCount(strength, #shuffledZombies)
        or CPD.getZombieKnockdownCount(strength, #shuffledZombies)
    local knockdownSet = {}
    for i = 1, knockdownCount do knockdownSet[shuffledZombies[i]] = true end

    local initialStrainMods = CPD.getArmStrainModifiers(opener)
    local initialEnduranceMods = CPD.getEnduranceModifiers(opener)
    local zombieHits = 0
    local playerHits = 0
    local zombieKnockdowns = 0
    local crawlerStuns = 0
    local strainBlockedMidImpact = false

    for i = 1, #zombies do
        if CPD.isImpactBlockedByArmStrain(opener) then
            strainBlockedMidImpact = true
            break
        end

        local zombie = zombies[i]
        local targetSquare = targetSquares[zombie] or impactSquares[1]
        local impactDoor = doubleDoor and CPD.getDoubleDoorImpactPart(door, targetSquare) or door
        local impactMods = CPD.getCombinedImpactModifiers(opener)
        local hit, knockedDown, crawlerStunned = CPD.applyZombieClosingImpact(
            opener, zombie, strength, knockdownSet[zombie] == true, impactDoor, targetSquare, impactMods
        )
        if hit then
            zombieHits = zombieHits + 1
            if knockedDown then zombieKnockdowns = zombieKnockdowns + 1 end
            if crawlerStunned then crawlerStuns = crawlerStuns + 1 end
            CPD.applyArmStrain(opener, fitness, 1, doorProfile)
        end
    end

    for i = 1, #players do
        if CPD.isImpactBlockedByArmStrain(opener) then
            strainBlockedMidImpact = true
            break
        end

        local target = players[i]
        local impactMods = CPD.getCombinedImpactModifiers(opener)
        if CPD.applyPlayerClosingImpact(opener, target, strength, impactMods) then
            playerHits = playerHits + 1
            CPD.applyArmStrain(opener, fitness, 1, doorProfile)
        end
    end

    local hitCount = zombieHits + playerHits
    local recoveryMs = 0
    local recoveryBandEnd = "none"
    local enduranceCost = 0.0
    local enduranceBefore = CPD.getEndurance(opener)
    local enduranceAfter = enduranceBefore
    local enduranceFamily = CPD.getEnduranceFamily(door, doorProfile)
    if hitCount > 0 then
        CPD.playImpactSoundForOpener(opener, door)
        CPD.playEffortVoiceForOpener(opener)
        enduranceCost, enduranceBefore, enduranceAfter, enduranceFamily =
            CPD.applyEnduranceCost(opener, door, hitCount, doorProfile)
        recoveryMs, recoveryBandEnd = CPD.startImpactRecovery(opener)
        pcall(CPD.playKickDoorAnimationForOpener, opener, door, nil, false, "close", "CPDPushFences")
        mpDebug("CLOSING_RECOVERY_START",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " band=" .. tostring(recoveryBandEnd) ..
            " durationMs=" .. tostring(recoveryMs) ..
            " hits=" .. tostring(hitCount))
    end

    local finalStrainMods = CPD.getArmStrainModifiers(opener)
    local finalEnduranceMods = CPD.getEnduranceModifiers(opener)
    if hitCount > 0 then
        CPD.notifyStatThresholdCrossings(
            opener,
            initialStrainMods.strain,
            finalStrainMods.strain,
            enduranceBefore,
            enduranceAfter
        )
    end
    log("Resolved closing control impact strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " direction=" .. tostring(closingDirection) ..
        " strainBandStart=" .. tostring(initialStrainMods.band) ..
        " strainStart=" .. string.format("%.2f", initialStrainMods.strain or 0) ..
        " strainBandEnd=" .. tostring(finalStrainMods.band) ..
        " strainEnd=" .. string.format("%.2f", finalStrainMods.strain or 0) ..
        " enduranceBandStart=" .. tostring(initialEnduranceMods.band) ..
        " enduranceStart=" .. string.format("%.3f", enduranceBefore) ..
        " enduranceBandEnd=" .. tostring(finalEnduranceMods.band) ..
        " enduranceEnd=" .. string.format("%.3f", enduranceAfter) ..
        " enduranceCost=" .. string.format("%.3f", enduranceCost) ..
        " enduranceFamily=" .. tostring(enduranceFamily) ..
        " recoveryBand=" .. tostring(recoveryBandEnd) ..
        " recoveryMs=" .. tostring(recoveryMs) ..
        " zombieHits=" .. tostring(zombieHits) ..
        " zombieKnockdowns=" .. tostring(zombieKnockdowns) ..
        " crawlerStuns=" .. tostring(crawlerStuns) ..
        " playerHits=" .. tostring(playerHits) ..
        " healthDamage=0 doorWear=0" ..
        " strainBlockedMidImpact=" .. tostring(strainBlockedMidImpact))

    return hitCount > 0
end

function CPD.resolveDoorImpact(opener, door, preferredImpactSquare, transition)
    if not opener or not door then return false end
    if not CPD.isEligiblePlayerTarget(opener) then
        mpDebug("INVALID_OPENER", "reason=invalid-opener id=" .. tostring(safeCall(opener, "getOnlineID")))
        return false
    end
    if not CPD.isSupportedDoor(door) then return false end

    local garage = CPD.isGarageDoor(door)
    local doubleDoor = CPD.isDoubleDoor(door)
    local slidingDoor = CPD.isSlidingGlassDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" and transition ~= "close" then return false end
    if not garage and transition == "close" then
        return CPD.resolveDoorClosingImpact(opener, door, preferredImpactSquare)
    end

    local openState = CPD.getLogicalDoorOpenState(door)
    if garage and openState ~= false then return false end
    if not garage and openState ~= true then return false end

    local playerDoorAction = nil
    if garage then
        playerDoorAction = "CPDCloseGarages"
    elseif not slidingDoor then
        if CPD.isSingleFenceGate(door) then
            playerDoorAction = "CPDPushFences"
        else
            playerDoorAction = "CPDKickDoor"
        end
    end

    local strainBlockedAtStart = CPD.isImpactBlockedByArmStrain(opener)
    local enduranceBlockedAtStart = CPD.isImpactBlockedByEndurance(opener)

    local recovering, recoveryRemainingMs, recoveryBand = CPD.isImpactRecoveryActive(opener)
    if recovering and not strainBlockedAtStart and not enduranceBlockedAtStart then
        log("Door impact skipped during muscle recovery")
        mpDebug("IMPACT_RECOVERY_BLOCK",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " band=" .. tostring(recoveryBand) ..
            " remainingMs=" .. tostring(recoveryRemainingMs))
        return false
    end

    local impactSquares, impactSide = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    local geometrySource = "preferred"
    if not impactSquares then
        local context, geometryReason = CPD.getInteractionImpactContext(opener, door)
        if context then
            impactSquares = context.impactBand
            impactSide = context.impactSide
            geometrySource = "runtime"
        else
            impactSquares = {}
            geometrySource = "invalid:" .. tostring(geometryReason or "unknown")
        end
    end

    local openingDirection = CPD.getOpeningApproachDirection(door, impactSide)
    if not garage and not slidingDoor and not S.allowImpactsFromBothSides() then
        if openingDirection ~= "E" and openingDirection ~= "S" then
            mpDebug("IMPACT_DIRECTION_BLOCK",
                "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
                " direction=" .. tostring(openingDirection or "unresolved") ..
                " impactSide=" .. tostring(impactSide or "none"))
            return false
        end
    end

    if CPD.isDuplicateImpact(opener, door) then return false end

    mpDebug("IMPACT_GEOMETRY",
        "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
        " transition=" .. tostring(transition) ..
        " source=" .. tostring(geometrySource) ..
        " direction=" .. tostring(openingDirection or "unresolved") ..
        " impactSide=" .. tostring(impactSide or "none") ..
        " squares=" .. tostring(#impactSquares))

    if doubleDoor then
        mpDebug("DOUBLE_DOOR_GROUP",
            "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
            " parts=" .. tostring(#CPD.getDoubleDoorParts(door)) ..
            " impactSquares=" .. tostring(#impactSquares))
    end

    if #impactSquares == 0 then
        log("Door transition but no impact square could be resolved")
        return false
    end

    local targets, targetSquares = CPD.collectTargetsFromSquares(impactSquares, opener)
    mpDebug("SERVER_TARGETS",
        "transition=" .. tostring(transition) ..
        " garage=" .. tostring(garage) ..
        " doubleDoor=" .. tostring(doubleDoor) ..
        " impactSquares=" .. tostring(#impactSquares) ..
        " rawTargets=" .. tostring(#targets))
    log("Impact transition=" .. tostring(transition) ..
        " garage=" .. tostring(garage) ..
        " doubleDoor=" .. tostring(doubleDoor) ..
        " squares=" .. tostring(#impactSquares) ..
        " targets=" .. tostring(#targets))
    if #targets == 0 then return false end

    local strength = CPD.getStrength(opener)
    local doorProfile = CPD.getDoorImpactProfile(door, strength)

    local zombies = {}
    local players = {}
    for i = 1, #targets do
        local target = targets[i]
        local targetType = CPD.getImpactTargetType(target)
        if targetType == "zombie" then
            if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                zombies[#zombies + 1] = target
            end
        elseif targetType == "player" then
            local pvpAllowed, pvpReason = CPD.canAffectPlayerInMultiplayer(opener, target)
            if pvpAllowed then
                players[#players + 1] = target
            else
                mpDebug("PLAYER_PVP_FILTER",
                    "route=opening opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
                    " target=" .. tostring(safeCall(target, "getUsername") or target) ..
                    " reason=" .. tostring(pvpReason))
            end
        end
    end

    if (S.damagePlayers() or S.knockDownPlayers()) and #players > 0 then
        local blocker, openerStrength, blockerStrength, blockerReason =
            CPD.findPlayerStrengthBlocker(opener, players)
        if blocker then
            local blockState = {
                blocked = true,
                blocker = blocker,
                openerStrength = openerStrength,
                blockerStrength = blockerStrength,
                blockerReason = blockerReason,
                transition = transition,
                garage = garage,
            }
            blockState.doorRestored = CPD.restoreDoorAfterPlayerStrengthBlock(
                opener, door, transition
            )
            CPD.playPlayerStrengthBlockedFeedback(
                opener, door, blockState, garage, transition, playerDoorAction
            )
            mpDebug("PLAYER_STRENGTH_BLOCK_RESOLVE",
                "opener=" .. tostring(safeCall(opener, "getUsername") or opener) ..
                " blocker=" .. tostring(safeCall(blocker, "getUsername") or blocker) ..
                " strength=" .. tostring(openerStrength) .. "<" .. tostring(blockerStrength) ..
                " restored=" .. tostring(blockState.doorRestored))
            return false
        end
    end

    local validTargetCount = #zombies + #players
    local strainBlocked = CPD.isImpactBlockedByArmStrain(opener)
    local enduranceBlocked = CPD.isImpactBlockedByEndurance(opener)
    if validTargetCount > 0 and (strainBlocked or enduranceBlocked) then
        log("Door impact blocked by critical player resources")
        mpDebug("IMPACT_RESOURCE_BLOCK",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " strainBlocked=" .. tostring(strainBlocked) ..
            " enduranceBlocked=" .. tostring(enduranceBlocked) ..
            " usageLimit=" .. string.format("%.2f", CPD.getArmStrainUsageLimit()) ..
            " endurance=" .. string.format("%.3f", CPD.getEndurance(opener)))
        CPD.notifyImpactBlocked(opener, strainBlocked, enduranceBlocked)
        playBlockedImpactFailAnimation(opener, door, garage, transition, playerDoorAction)
        return false
    end

    if #zombies > 0 then
        local cap = 0
        if doorProfile.sliding == true then
            local baseCap = math.max(1, math.floor(tonumber(doorProfile.maxZombies) or 1))
            cap = math.max(1, math.floor((baseCap * S.zombiesAffectedMultiplier()) + 0.5))
            if cap > 3 then cap = 3 end
        elseif doorProfile.doubleDoor == true then
            cap = CPD.getDoubleDoorAffectedCount(strength, #zombies)
        else
            cap = CPD.getZombieAffectedCount(strength, #zombies)
        end
        if (garage or doubleDoor) and cap < #zombies then
            
            
            
            local shuffledMultiTargets = shuffledCopy(zombies)
            local limited = {}
            for i = 1, cap do
                limited[i] = shuffledMultiTargets[i]
            end
            zombies = limited
        else
            zombies = CPD.limitZombieTargets(zombies, impactSquares[1], cap)
        end
        log("Zombie target capacity profile=" .. tostring(doorProfile.kind or "standard") ..
            " cap=" .. tostring(cap) .. " affected=" .. tostring(#zombies))
    end

    local initialStrainMods = CPD.getArmStrainModifiers(opener)
    local initialEnduranceMods = CPD.getEnduranceModifiers(opener)
    local fitness = CPD.getFitness(opener)

    local garageConditionHealthBefore = nil
    local garageConditionMaxHealthBefore = nil
    if garage then
        local healthDoor = CPD.getGarageDoorMaster(door) or door
        garageConditionHealthBefore = tonumber(safeCall(healthDoor, "getHealth"))
        garageConditionMaxHealthBefore = tonumber(safeCall(healthDoor, "getMaxHealth"))
    end

    local knockableZombies = {}
    if doorProfile.neverZombieKnockdown ~= true then
        for i = 1, #zombies do
            if safeCall(zombies[i], "isCrawling") ~= true then
                knockableZombies[#knockableZombies + 1] = zombies[i]
            end
        end
    end

    local shuffledZombies = shuffledCopy(knockableZombies)
    local knockdownCount = 0
    if doorProfile.neverZombieKnockdown ~= true then
        if doorProfile.doubleDoor == true then
            knockdownCount = CPD.getDoubleDoorKnockdownCount(strength, #shuffledZombies)
        else
            knockdownCount = CPD.getZombieKnockdownCount(strength, #shuffledZombies)
        end
    end

    local knockdownSet = {}
    for i = 1, knockdownCount do
        knockdownSet[shuffledZombies[i]] = true
    end

    local zombieHits = 0
    local playerHits = 0
    local actualZombieKnockdowns = 0
    local crawlerStuns = 0
    local garageBroken = false
    local strainBlockedMidImpact = false

    for i = 1, #zombies do
        if garageBroken then break end
        if CPD.isImpactBlockedByArmStrain(opener) then
            strainBlockedMidImpact = true
            break
        end

        local impactMods = CPD.getCombinedImpactModifiers(opener)
        local zombie = zombies[i]
        local targetSquare = targetSquares[zombie] or impactSquares[1]
        local impactDoor = doubleDoor and CPD.getDoubleDoorImpactPart(door, targetSquare) or door
        local hit, knockedDown, crawlerStunned = CPD.applyZombieImpact(
            opener, zombie, strength, knockdownSet[zombie] == true, impactDoor, targetSquare, impactMods, doorProfile
        )
        if hit then
            zombieHits = zombieHits + 1
            if knockedDown then actualZombieKnockdowns = actualZombieKnockdowns + 1 end
            if crawlerStunned then crawlerStuns = crawlerStuns + 1 end

            
            
            
            
            CPD.applyArmStrain(opener, fitness, 1, doorProfile)
        end
    end

    for i = 1, #players do
        if garageBroken then break end
        if CPD.isImpactBlockedByArmStrain(opener) then
            strainBlockedMidImpact = true
            break
        end

        local impactMods = CPD.getCombinedImpactModifiers(opener)
        local target = players[i]
        local targetSquare = targetSquares[target] or impactSquares[1]
        local impactDoor = doubleDoor and CPD.getDoubleDoorImpactPart(door, targetSquare) or door
        if CPD.applyPlayerImpact(opener, target, strength, impactDoor, targetSquare, impactMods, doorProfile) then
            playerHits = playerHits + 1
            CPD.applyArmStrain(opener, fitness, 1, doorProfile)
        end
    end

    local hitCount = zombieHits + playerHits
    local recoveryMs = 0
    local recoveryBandEnd = "none"
    local enduranceCost = 0.0
    local enduranceBefore = CPD.getEndurance(opener)
    local enduranceAfter = enduranceBefore
    local enduranceFamily = CPD.getEnduranceFamily(door, doorProfile)
    if hitCount > 0 then
        CPD.playImpactSoundForOpener(opener, door)
        CPD.playEffortVoiceForOpener(opener)
        if garage then
            garageBroken = CPD.applyDoorWear(door, strength, zombieHits, playerHits, doorProfile) == true
            if not garageBroken then
                garageBroken = CPD.rollGarageBreakChance(
                    door, strength, garageConditionHealthBefore, garageConditionMaxHealthBefore
                ) == true
            end
        else
            CPD.applyDoorWear(door, strength, zombieHits, playerHits, doorProfile)
        end
        enduranceCost, enduranceBefore, enduranceAfter, enduranceFamily =
            CPD.applyEnduranceCost(opener, door, hitCount, doorProfile)
        recoveryMs, recoveryBandEnd = CPD.startImpactRecovery(opener)
        mpDebug("IMPACT_RECOVERY_START",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " band=" .. tostring(recoveryBandEnd) ..
            " durationMs=" .. tostring(recoveryMs) ..
            " hits=" .. tostring(hitCount))
    end

    if hitCount > 0 and playerDoorAction then
        pcall(CPD.playKickDoorAnimationForOpener, opener, door, nil, garage, transition, playerDoorAction)
    end

    local finalStrainMods = CPD.getArmStrainModifiers(opener)
    local finalEnduranceMods = CPD.getEnduranceModifiers(opener)
    if hitCount > 0 then
        CPD.notifyStatThresholdCrossings(
            opener,
            initialStrainMods.strain,
            finalStrainMods.strain,
            enduranceBefore,
            enduranceAfter
        )
    end
    log("Resolved impact transition=" .. tostring(transition) ..
        " strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " strainBandStart=" .. tostring(initialStrainMods.band) ..
        " strainStart=" .. string.format("%.2f", initialStrainMods.strain or 0) ..
        " strainBandEnd=" .. tostring(finalStrainMods.band) ..
        " strainEnd=" .. string.format("%.2f", finalStrainMods.strain or 0) ..
        " enduranceBandStart=" .. tostring(initialEnduranceMods.band) ..
        " enduranceStart=" .. string.format("%.3f", enduranceBefore) ..
        " enduranceBandEnd=" .. tostring(finalEnduranceMods.band) ..
        " enduranceEnd=" .. string.format("%.3f", enduranceAfter) ..
        " enduranceCost=" .. string.format("%.3f", enduranceCost) ..
        " enduranceFamily=" .. tostring(enduranceFamily) ..
        " usageLimit=" .. string.format("%.2f", CPD.getArmStrainUsageLimit()) ..
        " recoveryBand=" .. tostring(recoveryBandEnd) ..
        " recoveryMs=" .. tostring(recoveryMs) ..
        " zombieHits=" .. zombieHits ..
        " zombieKnockdowns=" .. actualZombieKnockdowns ..
        " crawlerStuns=" .. crawlerStuns ..
        " playerHits=" .. playerHits ..
        " strainBlockedMidImpact=" .. tostring(strainBlockedMidImpact) ..
        " garageBroken=" .. tostring(garageBroken))

    return hitCount > 0
end

local function forcedOpeningRollPercent(chance)
    chance = clamp(tonumber(chance) or 0, 0, 100)
    if chance <= 0 then return false end
    if ZombRand then return ZombRand(10000) < math.floor(chance * 100 + 0.5) end
    return math.random() * 100 < chance
end

function CPD.getForcedOpeningFractureChance(opener, state, side, successfulImpactCount)
    if not opener or not state then return 0, "invalid", 0 end
    side = side == "left" and "left" or (side == "right" and "right" or nil)
    if not side then return 0, "invalid-side", CPD.getArmStrain(opener) end

    local sideStrain = CPD.getArmStrainForSide(opener, side)
    if state.strainBlocked == true or state.enduranceBlocked == true
        or state.resourceOverload == true then
        return 100, "resource-overload", sideStrain
    end

    local limit = CPD.getArmStrainUsageLimit()
    if sideStrain >= limit then
        return 100, "usage-limit", sideStrain
    end

    successfulImpactCount = math.max(0, math.floor(tonumber(successfulImpactCount) or 0))
    if successfulImpactCount <= 0 then
        return 0, "no-successful-impacts", sideStrain
    end

    local thresholds = CPD.getArmStrainThresholds()
    local band = "belowLight"
    if sideStrain >= (tonumber(thresholds.medium) or 12) then
        band = "medium"
    elseif sideStrain >= (tonumber(thresholds.light) or 5) then
        band = "light"
    end

    local row = (C.FORCED_OPENING_FRACTURE_BY_STRAIN or {})[band] or {}
    local base = tonumber(row.base) or 0
    local perExtraTarget = tonumber(row.perExtraTarget) or 0
    local extraTargets = math.max(0, successfulImpactCount - 1)
    local rawChance = base + (perExtraTarget * extraTargets)
    local chance = clamp(rawChance * S.forcedOpeningFractureRiskMultiplier(), 0, 100)
    return chance, band, sideStrain, rawChance, extraTargets
end

function CPD.selectForcedOpeningFracturePart(character, side)
    side = side == "left" and "left" or (side == "right" and "right" or nil)
    if not character or not side then return nil end
    local profile = CPD.getForcedOpeningFractureProfile(character)
    local available = profile[side] and profile[side].available or {}
    return available[randomForcedOpeningIndex(#available)]
end

function CPD.applyForcedOpeningFracturePart(character, side, partKey, duration)
    if not character or not BodyPartType then return false end
    side = side == "left" and "left" or (side == "right" and "right" or nil)
    if not side then return false end

    local definition = forcedOpeningPartDefinition(side, partKey)
    if not definition or forcedOpeningPartFractured(character, definition.type) then return false end
    local bodyPart = getArmBodyPart(character, definition.type)
    if not bodyPart then return false end
    duration = math.max(1, tonumber(duration) or tonumber(C.FORCED_OPENING_FRACTURE_TIME) or 50)

    local generated = pcall(function() bodyPart:generateFractureNew(duration) end)
    if not generated then
        generated = pcall(function() bodyPart:generateFracture(duration) end)
    end
    local setOk = pcall(function() bodyPart:setFractureTime(duration) end)
    if not generated and not setOk then return false end

    local limit = CPD.getArmStrainUsageLimit()
    local values = CPD.getArmStrainParts(character)
    local suffix = side == "left" and "_L" or "_R"
    for name, value in pairs(values) do
        if string.sub(name, -2) == suffix then
            values[name] = math.max(tonumber(value) or 0, limit)
        end
    end
    CPD.setArmStrainAbsolute(character, values)
    return true, values, definition.key
end

function CPD.applyForcedOpeningFractureSide(character, side, duration)
    local partKey = CPD.selectForcedOpeningFracturePart(character, side)
    if not partKey then return false end
    return CPD.applyForcedOpeningFracturePart(character, side, partKey, duration)
end

function CPD.rollForcedOpeningFracture(character, state, preferredSide, successfulImpactCount)
    local side = preferredSide == "left" and "left" or (preferredSide == "right" and "right" or nil)
    if not side then side = CPD.selectForcedOpeningMechanicalSide(character) end

    local chance, band, sideStrain, rawChance, extraTargets = CPD.getForcedOpeningFractureChance(
        character,
        state,
        side,
        successfulImpactCount
    )
    if not forcedOpeningRollPercent(chance) then
        return nil, chance, nil, band, sideStrain, rawChance, extraTargets
    end

    local fractureProfile = CPD.getForcedOpeningFractureProfile(character)
    if fractureProfile.blocked then
        return nil, chance, nil, band, sideStrain, rawChance, extraTargets
    end

    local duration = tonumber(C.FORCED_OPENING_FRACTURE_TIME) or 50
    local applied = false
    local values = nil
    local partKey = nil
    for _ = 1, 3 do
        local candidatePart = CPD.selectForcedOpeningFracturePart(character, side)
        if not candidatePart then break end
        applied, values, partKey = CPD.applyForcedOpeningFracturePart(
            character,
            side,
            candidatePart,
            duration
        )
        if applied then break end
    end
    if not applied or not partKey then
        return nil, chance, nil, band, sideStrain, rawChance, extraTargets
    end
    return side, chance, values, band, sideStrain, rawChance, extraTargets, partKey
end

function CPD.applyForcedOpeningEnduranceCost(character, targetCount)
    targetCount = math.max(1, math.floor(tonumber(targetCount) or 1))
    local fitness = math.floor(clamp(CPD.getFitness(character), 0, 10))
    local fitnessMultiplier = tonumber((C.FITNESS_ENDURANCE_MULTIPLIER or {})[fitness]) or 1.0
    local base = tonumber(C.FORCED_OPENING_ENDURANCE_BASE) or 0.20
    local perTarget = tonumber(C.FORCED_OPENING_ENDURANCE_PER_TARGET) or 0.05
    local cap = tonumber(C.FORCED_OPENING_ENDURANCE_CAP) or 0.50
    local requested = (base + (perTarget * targetCount))
        * fitnessMultiplier
        * S.enduranceCostMultiplier()
    requested = clamp(requested, 0, cap)

    local before = CPD.getEndurance(character)
    local after = clamp(before - requested, 0, 1)
    if not CPD.setEnduranceAbsolute(character, after) then return 0, before, before end

    if isServer and isServer() and sendServerCommand then
        pcall(function()
            sendServerCommand(character, "CyesPushDoors", "enduranceSync", {
                endurance = after,
                playerId = safeCall(character, "getOnlineID"),
            })
        end)
    end
    return before - after, before, after
end

function CPD.applyForcedOpeningArmStrain(character, side, targetCount, resourceOverload)
    if not character then return 0, 0, 0, {} end
    side = side == "left" and "left" or (side == "right" and "right" or nil)
    if not side then return 0, CPD.getArmStrain(character), CPD.getArmStrain(character), {} end

    targetCount = math.max(0, math.floor(tonumber(targetCount) or 0))
    local before = CPD.getArmStrain(character)
    if targetCount <= 0 then return 0, before, before, {} end
    local fitness = math.floor(clamp(CPD.getFitness(character), 0, 10))
    local curve = C.FORCED_OPENING_FITNESS_ARM_STRAIN_PER_TARGET or {}
    local perTarget = tonumber(curve[fitness]) or 0
    local amount = perTarget
        * targetCount
        * getSandboxMuscleStrainMultiplier()
        * S.armStrainGainMultiplier()
    if resourceOverload == true then
        amount = amount * (tonumber(C.FORCED_OPENING_OVERLOAD_STRAIN_MULTIPLIER) or 1.20)
    end
    amount = math.max(0, amount)

    local values = {}
    local suffix = side == "left" and "_L" or "_R"
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        if string.sub(def.name, -2) == suffix then
            local part = getArmBodyPart(character, def.type)
            if part then
                local current = tonumber(safeCall(part, "getStiffness")) or 0
                local updated = clamp(current + amount, 0, 100)
                safeCall(part, "setStiffness", updated)
                values[def.name] = updated
            end
        end
    end

    if isServer and isServer() and sendServerCommand then
        pcall(function()
            sendServerCommand(character, "CyesPushDoors", "armStrainSync", values)
        end)
    end

    local after = CPD.getArmStrain(character)
    log("Forced opening arm strain fitness=" .. tostring(fitness) ..
        " side=" .. tostring(side) ..
        " targets=" .. tostring(targetCount) ..
        " overload=" .. tostring(resourceOverload == true) ..
        " added=" .. string.format("%.3f", amount) ..
        " max=" .. string.format("%.3f", before) .. "->" .. string.format("%.3f", after))
    return amount, before, after, values
end

function CPD.toggleForcedDoorOpen(opener, door)
    if not opener or not door or CPD.getLogicalDoorOpenState(door) ~= false then return false end
    local toggled = false
    if CPD.isDoubleDoor(door) and IsoDoor and IsoDoor.toggleDoubleDoor then
        toggled = pcall(IsoDoor.toggleDoubleDoor, door, true)
    end
    if CPD.getLogicalDoorOpenState(door) ~= true then
        local ok = pcall(function() door:ToggleDoor(opener) end)
        toggled = toggled or ok
    end
    return toggled and CPD.getLogicalDoorOpenState(door) == true
end

function CPD.resolveForcedDoorOpening(opener, door, forcedActionAnim, useCustomAnimation)
    if useCustomAnimation == nil then
        useCustomAnimation = forcedActionAnim ~= nil
    else
        useCustomAnimation = useCustomAnimation == true
    end

    local executionSide = nil
    local mechanicalSideRoll = nil
    if useCustomAnimation then
        executionSide = CPD.getForcedOpeningAnimationSide(forcedActionAnim)
    end
    if useCustomAnimation and executionSide == nil then
        return false, "invalid-forced-animation"
    end
    local state, reason = CPD.getForcedOpeningState(opener, door)
    if not state then return false, reason or "invalid-state" end
    if reason == "wrong-side" or reason == "both-arms-fractured" then
        if reason == "both-arms-fractured" then
            pcall(
                CPD.playKickDoorAnimationForOpener,
                opener,
                door,
                nil,
                false,
                "open",
                "CPDPushDoorFail"
            )
        end
        CPD.notifyForcedOpeningMessage(opener, reason)
        return false, reason
    end
    if reason ~= nil then return false, reason end

    if useCustomAnimation then
        if not CPD.isForcedOpeningSideAllowed(opener, executionSide, state.fractureProfile) then
            return false, "forced-side-unavailable"
        end
    else
        forcedActionAnim = nil
        executionSide, mechanicalSideRoll = CPD.selectForcedOpeningMechanicalSide(opener)
        if not executionSide then
            CPD.notifyForcedOpeningMessage(opener, "both-arms-fractured")
            return false, "both-arms-fractured"
        end
    end

    local impactSquares = CPD.getForcedOpeningImpactSquares(state)
    if #impactSquares == 0 then return false, "missing-impact-squares" end
    local targets, targetSquares = CPD.collectTargetsFromSquares(impactSquares, opener)
    local zombies = {}
    local players = {}
    for i = 1, #targets do
        local target = targets[i]
        local targetType = CPD.getImpactTargetType(target)
        if targetType == "zombie" then
            if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                zombies[#zombies + 1] = target
            end
        elseif targetType == "player" then
            local pvpAllowed = CPD.canAffectPlayerInMultiplayer(opener, target)
            if pvpAllowed then players[#players + 1] = target end
        end
    end
    local crowdStillBlocked = #zombies > state.capacity
    local playerStrengthStillBlocked = state.blockedByPlayerStrength == true
        and state.blocker ~= nil
    if not crowdStillBlocked and not playerStrengthStillBlocked then
        return false, "block-changed"
    end

    mpDebug("FORCED_OPENING_BLOCK_SOURCE",
        "crowd=" .. tostring(crowdStillBlocked) ..
        " playerStrength=" .. tostring(playerStrengthStillBlocked) ..
        " blocker=" .. tostring(state.blocker and
            (safeCall(state.blocker, "getUsername") or state.blocker) or "none") ..
        " openerStrength=" .. tostring(state.strength) ..
        " blockerStrength=" .. tostring(state.blockerStrength or "none"))

    local key = CPD.getDoorWorldKey(door)
    CPD.markForcedDoorTransition(key)
    if isServer and isServer() and sendServerCommand then
        local transitionArgs = CPD.makeDoorArgs(door, state.anchor, true, "open") or {}
        transitionArgs.doorKey = key
        transitionArgs.playerId = safeCall(opener, "getOnlineID")
        pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "forcedDoorTransition", transitionArgs)
        end)
    end
    if not CPD.toggleForcedDoorOpen(opener, door) then return false, "toggle-failed" end

    local strength = CPD.getStrength(opener)
    local doorProfile = CPD.getDoorImpactProfile(door, strength)
    local impactMods = CPD.getCombinedImpactModifiers(opener)
    local zombieHits = 0
    local playerHits = 0
    for i = 1, #zombies do
        local zombie = zombies[i]
        local square = targetSquares[zombie] or impactSquares[1]
        local impactDoor = CPD.isDoubleDoor(door) and CPD.getDoubleDoorImpactPart(door, square) or door
        local hit = CPD.applyZombieImpact(
            opener, zombie, strength, true, impactDoor, square, impactMods, doorProfile
        )
        if hit then zombieHits = zombieHits + 1 end
    end
    for i = 1, #players do
        local player = players[i]
        local square = targetSquares[player] or impactSquares[1]
        local impactDoor = CPD.isDoubleDoor(door) and CPD.getDoubleDoorImpactPart(door, square) or door
        if CPD.applyPlayerImpact(
            opener,
            player,
            strength,
            impactDoor,
            square,
            impactMods,
            doorProfile,
            true,
            true
        ) then
            playerHits = playerHits + 1
        end
    end

    local targetCount = #zombies + #players
    local successfulImpactCount = zombieHits + playerHits
    CPD.applyDoorWear(door, strength, #zombies, #players, doorProfile, {
        forced = true,
        capacity = state.capacity,
    })
    local enduranceCost, enduranceBefore, enduranceAfter =
        CPD.applyForcedOpeningEnduranceCost(opener, targetCount)
    local forcedStrainAdded, strainBefore, strainAfter = CPD.applyForcedOpeningArmStrain(
        opener,
        executionSide,
        successfulImpactCount,
        state.resourceOverload == true
    )
    local fractureSide, fractureChance, strainValues, fractureBand,
        targetArmStrain, rawFractureChance, extraSuccessfulTargets,
        fracturePart = CPD.rollForcedOpeningFracture(
            opener,
            state,
            executionSide,
            successfulImpactCount
        )
    if fractureSide and isServer and isServer() and sendServerCommand then
        pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "forcedFracture", {
                side = fractureSide,
                part = fracturePart,
                duration = tonumber(C.FORCED_OPENING_FRACTURE_TIME) or 50,
                playerId = safeCall(opener, "getOnlineID"),
            })
            sendServerCommand(opener, "CyesPushDoors", "armStrainSync", strainValues or {})
        end)
    end

    CPD.playImpactSoundForOpener(opener, door)
    CPD.playEffortVoiceForOpener(opener)
    CPD.startImpactRecovery(opener)
    strainAfter = CPD.getArmStrain(opener)
    CPD.notifyStatThresholdCrossings(
        opener,
        strainBefore,
        strainAfter,
        enduranceBefore,
        enduranceAfter
    )

    mpDebug("FORCED_OPENING_RESULT",
        "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
        " doorKey=" .. tostring(key) ..
        " strength=" .. tostring(strength) ..
        " zombies=" .. tostring(#zombies) ..
        " players=" .. tostring(#players) ..
        " zombieHits=" .. tostring(zombieHits) ..
        " playerHits=" .. tostring(playerHits) ..
        " successfulImpacts=" .. tostring(successfulImpactCount) ..
        " endurance=" .. string.format("%.3f->%.3f", enduranceBefore, enduranceAfter) ..
        " enduranceCost=" .. string.format("%.3f", enduranceCost) ..
        " strain=" .. string.format("%.3f->%.3f", strainBefore, strainAfter) ..
        " strainAdded=" .. string.format("%.3f", forcedStrainAdded) ..
        " resourceOverload=" .. tostring(state.resourceOverload == true) ..
        " customAnimation=" .. tostring(useCustomAnimation) ..
        " forcedAction=" .. tostring(forcedActionAnim or "none") ..
        " executionSide=" .. tostring(executionSide) ..
        " mechanicalSideRoll=" .. tostring(mechanicalSideRoll or "animation") ..
        " fractureBand=" .. tostring(fractureBand) ..
        " targetArmStrain=" .. string.format("%.3f", targetArmStrain or 0) ..
        " rawFractureChance=" .. string.format("%.1f", rawFractureChance or fractureChance or 0) ..
        " extraSuccessfulTargets=" .. tostring(extraSuccessfulTargets or 0) ..
        " fractureChance=" .. string.format("%.1f", fractureChance or 0) ..
        " fractureSide=" .. tostring(fractureSide or "none") ..
        " fracturePart=" .. tostring(fracturePart or "none"))

    return true, nil, {
        zombieHits = zombieHits,
        playerHits = playerHits,
        enduranceCost = enduranceCost,
        armStrainAdded = forcedStrainAdded,
        resourceOverload = state.resourceOverload == true,
        blockedByCrowd = crowdStillBlocked,
        blockedByPlayerStrength = playerStrengthStillBlocked,
        customAnimation = useCustomAnimation,
        forcedAction = forcedActionAnim,
        executionSide = executionSide,
        mechanicalSideRoll = mechanicalSideRoll,
        successfulImpactCount = successfulImpactCount,
        fractureBand = fractureBand,
        targetArmStrain = targetArmStrain,
        fractureSide = fractureSide,
        fracturePart = fracturePart,
        fractureChance = fractureChance,
    }
end

function CPD.resolveDoorOpening(opener, door, preferredImpactSquare)
    return CPD.resolveDoorImpact(opener, door, preferredImpactSquare, "open")
end

function CPD.makeDoorArgs(door, impactSquare, interaction, transition)
    if not door or not door:getSquare() then return nil end
    local sq = door:getSquare()
    local args = {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        index = door:getObjectIndex(),
        interaction = interaction == true,
        transition = transition or (CPD.isGarageDoor(door) and "close" or "open"),
    }
    if impactSquare and CPD.isEntrySideSquare(door, impactSquare) then
        args.impactX = impactSquare:getX()
        args.impactY = impactSquare:getY()
        args.impactZ = impactSquare:getZ()
    end
    return args
end

function CPD.findDoor(args)
    if not args or args.x == nil or args.y == nil or args.z == nil or args.index == nil then return nil end
    local sq = getCell():getGridSquare(tonumber(args.x), tonumber(args.y), tonumber(args.z))
    if not sq then return nil end
    local index = tonumber(args.index)
    if not index or index < 0 or index >= sq:getObjects():size() then return nil end
    local object = sq:getObjects():get(index)
    if CPD.isSupportedDoor(object) then return object end
    return nil
end

function CPD.validateServerRequest(player, door, transition)
    if not CPD.isEligiblePlayerTarget(player) or not door then return false end

    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" and transition ~= "close" then return false end
    if not garage and transition == "close" and not CPD.supportsClosingControlImpact(door) then return false end

    local sq = door:getSquare()
    if not sq or sq:getZ() ~= player:getZ() then return false end

    local dx = player:getX() - (sq:getX() + 0.5)
    local dy = player:getY() - (sq:getY() + 0.5)
    local distSq = (dx * dx) + (dy * dy)
    if CPD.isDoubleDoor(door) then
        local parts = CPD.getDoubleDoorParts(door)
        for i = 1, #parts do
            local partSq = safeCall(parts[i], "getSquare")
            if partSq and partSq:getZ() == player:getZ() then
                local pdx = player:getX() - (partSq:getX() + 0.5)
                local pdy = player:getY() - (partSq:getY() + 0.5)
                local partDistSq = (pdx * pdx) + (pdy * pdy)
                if partDistSq < distSq then distSq = partDistSq end
            end
        end
    end
    local maxDist = C.MAX_SERVER_VALIDATION_DISTANCE
    if distSq > (maxDist * maxDist) then return false end

    local open = CPD.getLogicalDoorOpenState(door)
    if transition == "close" then
        if open ~= nil and open ~= false then return false end
    else
        if open ~= nil and open ~= true then return false end
    end

    return true
end

return CyesPushDoors
