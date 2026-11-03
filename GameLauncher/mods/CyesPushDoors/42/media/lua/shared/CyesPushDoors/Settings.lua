require "CyesPushDoors/Config"

CyesPushDoors = CyesPushDoors or {}
CyesPushDoors.Settings = CyesPushDoors.Settings or {}

local S = CyesPushDoors.Settings

S.ClientImpactFeedback = true
S.ClientDynamicMessages = true
S.ClientCustomAnimations = true
S.ClientSoundEffects = true
S.ClientImpactTargetOutline = false
S.ClientImpactTargetOutlineColor = { r = 0.45, g = 1.0, b = 0.45, a = 1.0 }
S.ClientIncrementMessageColor = { r = 1.0, g = 1.0, b = 0.0, a = 1.0 }
S.ClientLimitationMessageColor = { r = 1.0, g = 0.0, b = 0.0, a = 1.0 }
S.ClientStandardMessageColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }

local function boolValue(value, default)
    if value == nil then return default end
    return value == true
end

local function numberValue(value, default, minValue, maxValue)
    local n = tonumber(value)
    if n == nil then n = default end
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

function S.isNetworkClient()
    return isClient and isClient() == true
end

function S.isNetworkServer()
    return isServer and isServer() == true
end

function S.getSandbox()
    if SandboxVars and SandboxVars.CyesPushDoors then
        return SandboxVars.CyesPushDoors
    end
    return {}
end

function S.hideIndividualOptions()
    if not S.isNetworkClient() then return false end
    return boolValue(S.getSandbox().HideIndividualOptions, false)
end

function S.globalImpactFeedback()
    return boolValue(S.getSandbox().GlobalImpactFeedback, true)
end

function S.setClientImpactFeedback(value)
    S.ClientImpactFeedback = value ~= false
end

function S.setClientDynamicMessages(value)
    S.ClientDynamicMessages = value == true
end

function S.setClientCustomAnimations(value)
    S.ClientCustomAnimations = value == true
end

function S.setClientSoundEffects(value)
    S.ClientSoundEffects = value == true
end

function S.setClientImpactTargetOutline(value)
    S.ClientImpactTargetOutline = value == true
    if S.ClientImpactTargetOutline ~= true
        and CyesPushDoors
        and type(CyesPushDoors.clearImpactTargetOutlines) == "function" then
        pcall(CyesPushDoors.clearImpactTargetOutlines)
    end
end

function S.impactTargetOutlineEnabled()
    return S.ClientImpactTargetOutline == true
end

local function colorField(value, field, index, method)
    if value == nil then return nil end
    local ok, result = pcall(function()
        local direct = value[field]
        if direct ~= nil then return direct end
        local indexed = value[index]
        if indexed ~= nil then return indexed end
        local getter = value[method]
        if getter then return getter(value) end
        return nil
    end)
    if ok then return result end
    return nil
end

local function colorNumber(value, default)
    local number = tonumber(value)
    if number ~= nil and number > 1.0 and number <= 255.0 then
        number = number / 255.0
    end
    return numberValue(number, default, 0.0, 1.0)
end

local function normalizedColor(value, defaults)
    defaults = defaults or {}
    return {
        r = colorNumber(colorField(value, "r", 1, "getRed"), defaults.r or 1.0),
        g = colorNumber(colorField(value, "g", 2, "getGreen"), defaults.g or 1.0),
        b = colorNumber(colorField(value, "b", 3, "getBlue"), defaults.b or 1.0),
        a = colorNumber(colorField(value, "a", 4, "getAlpha"), defaults.a or 1.0),
    }
end

function S.setClientIncrementMessageColor(value)
    if value == nil then return end
    S.ClientIncrementMessageColor = normalizedColor(value, { r = 1.0, g = 1.0, b = 0.0, a = 1.0 })
end

function S.setClientLimitationMessageColor(value)
    if value == nil then return end
    S.ClientLimitationMessageColor = normalizedColor(value, { r = 1.0, g = 0.0, b = 0.0, a = 1.0 })
end

function S.setClientStandardMessageColor(value)
    if value == nil then return end
    S.ClientStandardMessageColor = normalizedColor(value, { r = 1.0, g = 1.0, b = 1.0, a = 1.0 })
end

function S.setClientImpactTargetOutlineColor(value)
    if value == nil then return end
    S.ClientImpactTargetOutlineColor = normalizedColor(
        value,
        { r = 0.45, g = 1.0, b = 0.45, a = 1.0 }
    )
end

function S.incrementMessageColor()
    return normalizedColor(S.ClientIncrementMessageColor, { r = 1.0, g = 1.0, b = 0.0, a = 1.0 })
end

function S.limitationMessageColor()
    return normalizedColor(S.ClientLimitationMessageColor, { r = 1.0, g = 0.0, b = 0.0, a = 1.0 })
end

function S.standardMessageColor()
    return normalizedColor(S.ClientStandardMessageColor, { r = 1.0, g = 1.0, b = 1.0, a = 1.0 })
end

function S.impactTargetOutlineColor()
    return normalizedColor(
        S.ClientImpactTargetOutlineColor,
        { r = 0.45, g = 1.0, b = 0.45, a = 1.0 }
    )
end

function S.messageColor(sector)
    sector = tostring(sector or "standard")
    if sector == "increment" then return S.incrementMessageColor() end
    if sector == "limitation" then return S.limitationMessageColor() end
    return S.standardMessageColor()
end

function S.isLocalServerOwner()
    if not S.isNetworkClient() then
        return S.isNetworkServer()
    end

    if isCoopHost then
        local ok, value = pcall(isCoopHost)
        if ok then return value == true end
    end

    return false
end

local function feedbackChannelEnabled(clientValue)
    if S.isNetworkClient() and S.hideIndividualOptions() then
        return S.globalImpactFeedback()
    end
    if S.isNetworkServer() then
        local sandbox = S.getSandbox()
        if boolValue(sandbox.HideIndividualOptions, false) then
            return boolValue(sandbox.GlobalImpactFeedback, true)
        end
        return true
    end
    if S.ClientImpactFeedback ~= false then return true end
    return clientValue == true
end

function S.generalFeedbackEnabled()
    if S.isNetworkClient() and S.hideIndividualOptions() then
        return S.globalImpactFeedback()
    end
    if S.isNetworkServer() then
        local sandbox = S.getSandbox()
        if boolValue(sandbox.HideIndividualOptions, false) then
            return boolValue(sandbox.GlobalImpactFeedback, true)
        end
        return true
    end
    return S.ClientImpactFeedback ~= false
end

function S.dynamicMessagesEnabled()
    return feedbackChannelEnabled(S.ClientDynamicMessages)
end

function S.animationsEnabled()
    return feedbackChannelEnabled(S.ClientCustomAnimations)
end

function S.soundEffectsEnabled()
    return feedbackChannelEnabled(S.ClientSoundEffects)
end

function S.impactFeedbackEnabled()
    return S.generalFeedbackEnabled()
end

function S.setClientDynamicMessageColor(value)
    S.setClientLimitationMessageColor(value)
end

function S.dynamicMessageColor()
    return S.limitationMessageColor()
end

function S.zombieDamageMultiplier()
    return numberValue(S.getSandbox().ZombieDamageMultiplier, 1.0, 0.0, 2.0)
end

function S.zombiesAffectedMultiplier()
    return numberValue(S.getSandbox().ZombiesAffectedMultiplier, 1.0, 0.25, 2.0)
end

function S.doorBlockCapacityMultiplier()
    return numberValue(S.getSandbox().DoorBlockCapacityMultiplier, 1.0, 0.5, 2.0)
end

function S.zombieKnockdownChance()
    return numberValue(S.getSandbox().ZombieKnockdownChance, 35, 0, 100) / 100
end

function S.doorWearMultiplier()
    return numberValue(S.getSandbox().DoorWearMultiplier, 1.0, 0.0, 3.0)
end

function S.forcedOpeningDoorWearMultiplier()
    return numberValue(S.getSandbox().ForcedOpeningDoorWearMultiplier, 1.0, 0.0, 3.0)
end

function S.garageDoorWearMultiplier()
    return numberValue(S.getSandbox().GarageDoorWearMultiplier, 1.0, 0.25, 3.0)
end

function S.garageFailureChanceMultiplier()
    return numberValue(S.getSandbox().GarageFailureChanceMultiplier, 1.0, 0.0, 3.0)
end

function S.enduranceCostMultiplier()
    return numberValue(S.getSandbox().EnduranceCostMultiplier, 1.0, 0.0, 3.0)
end

function S.forcedOpeningFractureRiskMultiplier()
    return numberValue(S.getSandbox().ForcedOpeningFractureRiskMultiplier, 1.0, 0.0, 2.0)
end

function S.armStrainGainMultiplier()
    return numberValue(S.getSandbox().ArmStrainGainMultiplier, 1.0, 0.0, 3.0)
end

function S.armStrainUsageLimitMultiplier()
    return numberValue(S.getSandbox().ArmStrainUsageLimitMultiplier, 1.0, 0.25, 5.0)
end

function S.garageArmStrainMultiplier()
    return numberValue(S.getSandbox().GarageArmStrainMultiplier, 1.0, 0.25, 3.0)
end

function S.armStrainPenaltyMultiplier()
    return numberValue(S.getSandbox().ArmStrainPenaltyMultiplier, 1.0, 0.0, 2.0)
end

function S.armStrainRecoveryMultiplier()
    return numberValue(S.getSandbox().ArmStrainRecoveryMultiplier, 1.0, 0.25, 3.0)
end

function S.damagePlayers()
    return boolValue(S.getSandbox().DamagePlayers, true)
end

function S.knockDownPlayers()
    return boolValue(S.getSandbox().KnockDownPlayers, true)
end

function S.playerKnockdownChance()
    return numberValue(S.getSandbox().PlayerKnockdownChance, 25, 0, 100) / 100
end

function S.affectCrawlers()
    return boolValue(S.getSandbox().AffectCrawlers, true)
end

function S.allowImpactsFromBothSides()
    return boolValue(S.getSandbox().AllowImpactsFromBothSides, false)
end

return CyesPushDoors.Settings
