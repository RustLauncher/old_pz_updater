require "CyesPushDoors/Config"
require "CyesPushDoors/Settings"

CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors
local C = CPD.Config
local S = CPD.Settings

CPD.Feedback = CPD.Feedback or {}
CPD.Feedback.Animations = CPD.Feedback.Animations or {}
CPD.Feedback.SoundEffects = CPD.Feedback.SoundEffects or {}
CPD.Feedback.Visual = CPD.Feedback.Visual or {}

local Animations = CPD.Feedback.Animations
local SoundEffects = CPD.Feedback.SoundEffects
local Visual = CPD.Feedback.Visual

Animations.Reactions = Animations.Reactions or CPD.ZOMBIE_REACTIONS or {}
Animations.ReactionGroups = Animations.ReactionGroups or CPD.ZOMBIE_REACTION_GROUPS or {}
CPD.ZOMBIE_REACTIONS = Animations.Reactions
CPD.ZOMBIE_REACTION_GROUPS = Animations.ReactionGroups

local function copyDefinition(definition)
    local copy = {}
    for key, value in pairs(definition or {}) do
        copy[key] = value
    end
    return copy
end

local function randomIndex(count)
    count = tonumber(count) or 0
    if count <= 0 then return nil end
    if ZombRand then return ZombRand(count) + 1 end
    return math.random(1, count)
end

local function safeMethod(object, methodName, ...)
    if not object then return nil, false end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or not method then return nil, false end
    local ok, result = pcall(method, object, ...)
    if not ok then return nil, false end
    return result, true
end

local function safeCall(object, methodName, ...)
    local result = safeMethod(object, methodName, ...)
    return result
end

local function log(message)
    if CPD.log then CPD.log(message) end
end

function CPD.registerZombieReaction(id, definition)
    id = tostring(id or "")
    if id == "" or type(definition) ~= "table" then return false end

    local stored = copyDefinition(definition)
    stored.id = id
    stored.type = tostring(stored.type or "hitReaction")
    CPD.ZOMBIE_REACTIONS[id] = stored
    return true
end

function CPD.registerZombieReactionGroup(id, definition)
    id = tostring(id or "")
    if id == "" or type(definition) ~= "table" then return false end

    local stored = copyDefinition(definition)
    stored.id = id
    stored.mode = tostring(stored.mode or "random")
    stored.reactions = stored.reactions or {}
    CPD.ZOMBIE_REACTION_GROUPS[id] = stored
    return true
end

function CPD.getZombieReaction(id)
    if id == nil then return nil end
    return CPD.ZOMBIE_REACTIONS[tostring(id)]
end

function CPD.getZombieReactionGroup(id)
    if id == nil then return nil end
    return CPD.ZOMBIE_REACTION_GROUPS[tostring(id)]
end

function CPD.findZombieReaction(requested)
    if requested == nil then return nil end
    requested = tostring(requested)

    local direct = CPD.getZombieReaction(requested)
    if direct then return direct end

    for _, definition in pairs(CPD.ZOMBIE_REACTIONS) do
        if definition and (
            requested == tostring(definition.reaction)
            or requested == tostring(definition.observedAnimation)
        ) then
            return definition
        end
    end
    return nil
end

local function definitionMatchesRequested(definition, requested)
    if not definition or requested == nil then return false end
    requested = tostring(requested)
    return requested == tostring(definition.id)
        or requested == tostring(definition.reaction)
        or requested == tostring(definition.observedAnimation)
end

local function findRequestedInGroup(group, requested)
    if not group or requested == nil then return nil end
    local entries = group.reactions or {}
    for i = 1, #entries do
        local definition = CPD.getZombieReaction(entries[i])
        if definitionMatchesRequested(definition, requested) then
            return definition
        end
    end
    return nil
end

function CPD.selectZombieReaction(sourceId, requested)
    local direct = CPD.getZombieReaction(sourceId)
    if direct then
        if requested == nil or definitionMatchesRequested(direct, requested) then
            return direct
        end
        return nil
    end

    local group = CPD.getZombieReactionGroup(sourceId)
    if not group then return nil end

    if requested ~= nil then
        return findRequestedInGroup(group, requested)
    end

    local entries = group.reactions or {}
    if #entries == 0 then return nil end

    if group.mode == "random" then
        local index = randomIndex(#entries)
        return index and CPD.getZombieReaction(entries[index]) or nil
    end

    return CPD.getZombieReaction(entries[1])
end

function CPD.playZombieReaction(zombie, sourceId, requested)
    if not zombie then return false, nil, nil, "no-zombie" end
    if not S.animationsEnabled() then return false, nil, nil, "disabled" end

    local alive, aliveOk = safeMethod(zombie, "isAlive")
    if aliveOk and alive ~= true then
        return false, nil, nil, "not-alive"
    end

    local definition = CPD.selectZombieReaction(sourceId, requested)
    if not definition then
        return false, requested, nil, "not-registered"
    end

    local kind = tostring(definition.type or "hitReaction")

    if kind == "hitReaction" then
        local reaction = tostring(definition.reaction or "")
        local event = tostring(definition.event or "wasHit")
        if reaction == "" then return false, reaction, definition.id, "missing-reaction" end

        if definition.clearStaggerBack ~= false then
            safeMethod(zombie, "setStaggerBack", false)
        end
        if definition.clearKnockedDown == true then
            safeMethod(zombie, "setKnockedDown", false)
        end

        local _, reactionOk = safeMethod(zombie, "setHitReaction", reaction)
        if not reactionOk then
            return false, reaction, definition.id, "setHitReaction"
        end

        local _, eventOk = safeMethod(zombie, "reportEvent", event)
        if not eventOk then
            return false, reaction, definition.id, "wasHit"
        end

        return true, reaction, definition.id, nil
    end

    if kind == "event" then
        local event = tostring(definition.event or "")
        if event == "" then return false, event, definition.id, "missing-event" end
        local _, eventOk = safeMethod(zombie, "reportEvent", event)
        if not eventOk then return false, event, definition.id, "reportEvent" end
        return true, event, definition.id, nil
    end

    if kind == "animation" then
        local animation = tostring(definition.animation or definition.observedAnimation or "")
        if animation == "" then return false, animation, definition.id, "missing-animation" end
        local _, animOk = safeMethod(zombie, "PlayAnimUnlooped", animation)
        if not animOk then return false, animation, definition.id, "PlayAnimUnlooped" end
        return true, animation, definition.id, nil
    end

    return false, nil, definition.id, "unsupported-type"
end

CPD.registerZombieReaction("DoorHitChestL", {
    type = "hitReaction",
    reaction = "ShotChest",
    event = "wasHit",
    observedAnimation = "Zombie_ShotChestL",
})

CPD.registerZombieReaction("DoorHitChestR", {
    type = "hitReaction",
    reaction = "ShotChestStepR",
    event = "wasHit",
    observedAnimation = "Zombie_ShotChestStepR",
})

CPD.registerZombieReactionGroup("DoorNormalHit", {
    mode = "random",
    reactions = {
        "DoorHitChestL",
        "DoorHitChestR",
    },
})

CPD.registerZombieReaction("SlidingDoorHitLegL", {
    type = "hitReaction",
    reaction = "ShotLegL",
    event = "wasHit",
    observedAnimation = "Zombie_ShotLeg_L",
    clearKnockedDown = true,
})

CPD.registerZombieReaction("SlidingDoorHitLegR", {
    type = "hitReaction",
    reaction = "ShotLegR",
    event = "wasHit",
    observedAnimation = "Zombie_ShotLeg_R",
    clearKnockedDown = true,
})

CPD.registerZombieReaction("SlidingDoorCrawlerFloorFront", {
    type = "hitReaction",
    reaction = "FloorOnFront",
    event = "wasHit",
    observedAnimation = "Zombie_HitReact_FloorOnFront",
})

CPD.registerZombieReaction("SlidingDoorCrawlerKneesToFloorFront", {
    type = "hitReaction",
    reaction = "OnKneesToFloorFront",
    event = "wasHit",
    observedAnimation = "Zombie_OnKnees_ToFloorFront",
})

CPD.registerZombieReactionGroup("SlidingDoorStandingHit", {
    mode = "random",
    reactions = {
        "SlidingDoorHitLegL",
        "SlidingDoorHitLegR",
    },
})

CPD.registerZombieReactionGroup("SlidingDoorCrawlerHit", {
    mode = "random",
    reactions = {
        "SlidingDoorCrawlerFloorFront",
        "SlidingDoorCrawlerKneesToFloorFront",
    },
})

local DOOR_STAGGER_REACTION_GROUP = "DoorNormalHit"

function CPD.selectDoorStaggerReaction(requestedReaction)
    local definition = CPD.selectZombieReaction(DOOR_STAGGER_REACTION_GROUP, requestedReaction)
    if not definition then return nil end
    return definition.reaction or definition.id
end

function CPD.playDoorStaggerReaction(zombie, requestedReaction)
    if not zombie or not safeCall(zombie, "isAlive") then return false end

    local ok, selected, selectedId, stage = CPD.playZombieReaction(
        zombie,
        DOOR_STAGGER_REACTION_GROUP,
        requestedReaction
    )

    if not ok then
        log("Door stagger hit reaction failed selected=" .. tostring(selected) .. " stage=" .. tostring(stage or "router"))
        return false, selected
    end

    log("Door stagger hit reaction=" .. tostring(selected) .. " method=setHitReaction+wasHit")
    return true, selected, selectedId
end

function CPD.selectDoorStaggerAnimation(requestedAnimation)
    return CPD.selectDoorStaggerReaction(requestedAnimation)
end

function CPD.playDoorStaggerAnimation(zombie, requestedAnimation)
    return CPD.playDoorStaggerReaction(zombie, requestedAnimation)
end

local SLIDING_STANDING_REACTION_GROUP = "SlidingDoorStandingHit"
local SLIDING_CRAWLER_REACTION_GROUP = "SlidingDoorCrawlerHit"

local function slidingReactionGroup(zombie)
    local crawler = safeCall(zombie, "isCrawling") == true
    return crawler and SLIDING_CRAWLER_REACTION_GROUP or SLIDING_STANDING_REACTION_GROUP
end

function CPD.selectSlidingDoorReaction(zombie, requestedReaction)
    local groupId = slidingReactionGroup(zombie)
    local definition = CPD.selectZombieReaction(groupId, requestedReaction)

    if not definition and requestedReaction ~= nil and CPD.findZombieReaction then
        definition = CPD.findZombieReaction(requestedReaction)
    end

    return definition
end

function CPD.playSlidingDoorReaction(zombie, requestedReaction)
    if not zombie or not safeCall(zombie, "isAlive") then return false end

    local definition = CPD.selectSlidingDoorReaction(zombie, requestedReaction)
    if not definition then return false, requestedReaction end

    local ok, reaction, selectedId, stage = CPD.playZombieReaction(zombie, definition.id)
    local selectedClip = definition.observedAnimation or reaction or definition.id

    if not ok then
        log("Sliding-door hit reaction failed selected=" .. tostring(selectedClip) ..
            " reaction=" .. tostring(reaction) .. " stage=" .. tostring(stage or "router"))
        return false, selectedClip
    end

    log("Sliding-door hit reaction=" .. tostring(reaction) .. " selected=" .. tostring(selectedClip))
    return true, selectedClip, selectedId
end

function CPD.selectSlidingDoorAnimation(zombie, requestedAnimation)
    local definition = CPD.selectSlidingDoorReaction(zombie, requestedAnimation)
    if not definition then return nil end
    return definition.observedAnimation or definition.reaction or definition.id
end

function CPD.playSlidingDoorAnimation(zombie, requestedAnimation)
    return CPD.playSlidingDoorReaction(zombie, requestedAnimation)
end

function CPD.getDoorImpactSound(door)
    local sound = safeCall(door, "getThumpSound")
    if sound == nil then return nil end
    sound = tostring(sound)
    if sound == "" or sound == "nil" then return nil end
    return sound
end

function CPD.playImpactSoundLocal(player, sound)
    if not player or sound == nil or not S.soundEffectsEnabled() then return false end
    return pcall(function() player:playSoundLocal(tostring(sound)) end)
end

function CPD.playImpactSoundForOpener(opener, door)
    if not opener then return end
    local sound = CPD.getDoorImpactSound(door)
    if not sound then
        log("Impact registered but door has no thump sound")
        return
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(opener, "CyesPushDoors", "impactSound", {
            sound = sound,
            playerId = safeCall(opener, "getOnlineID"),
        })
        return
    end

    if S.soundEffectsEnabled() then
        safeCall(opener, "playSoundLocal", sound)
    end
end

local effortVoices = {
    male = {
        "CPDVoiceMaleAttackDefault",
        "CPDVoiceMaleAttackHeavy",
        "CPDVoiceMaleLowEffort",
        "CPDVoiceMaleHighEffort",
    },
    female = {
        "CPDVoiceFemaleAttackDefault",
        "CPDVoiceFemaleAttackHeavy",
        "CPDVoiceFemaleLowEffort",
        "CPDVoiceFemaleHighEffort",
    },
}

local exhaustedTextKeys = {
    "IGUI_CyesPushDoors_Exhausted_1",
    "IGUI_CyesPushDoors_Exhausted_2",
    "IGUI_CyesPushDoors_Exhausted_3",
    "IGUI_CyesPushDoors_Exhausted_4",
    "IGUI_CyesPushDoors_Exhausted_5",
}

local enduranceBlockedTextKeys = {
    "IGUI_CyesPushDoors_EnduranceBlocked_1",
    "IGUI_CyesPushDoors_EnduranceBlocked_2",
    "IGUI_CyesPushDoors_EnduranceBlocked_3",
}

local doorCrowdBlockedTextKeys = {
    "IGUI_CyesPushDoors_DoorCrowdBlocked_1",
    "IGUI_CyesPushDoors_DoorCrowdBlocked_2",
    "IGUI_CyesPushDoors_DoorCrowdBlocked_3",
    "IGUI_CyesPushDoors_DoorCrowdBlocked_4",
}

local playerStrengthBlockedTextKeys = {
    "IGUI_CyesPushDoors_PlayerStrengthBlocked_1",
    "IGUI_CyesPushDoors_PlayerStrengthBlocked_2",
    "IGUI_CyesPushDoors_PlayerStrengthBlocked_3",
}

local forcedOpeningInjuryTextKeys = {
    "IGUI_CyesPushDoors_ForcedOpeningInjured_1",
    "IGUI_CyesPushDoors_ForcedOpeningInjured_2",
    "IGUI_CyesPushDoors_ForcedOpeningInjured_3",
}

local blockedTextFallbacks = {
    IGUI_CyesPushDoors_Exhausted_1 = "Ugh... damn cramps",
    IGUI_CyesPushDoors_Exhausted_2 = "I'm completely spent",
    IGUI_CyesPushDoors_Exhausted_3 = "Too much strain...",
    IGUI_CyesPushDoors_Exhausted_4 = "Ugh... my arms can't take any more",
    IGUI_CyesPushDoors_Exhausted_5 = "My arms... they're all cramped up",
    IGUI_CyesPushDoors_EnduranceBlocked_1 = "Ugh... I need to catch my breath.",
    IGUI_CyesPushDoors_EnduranceBlocked_2 = "I'm too exhausted to move it.",
    IGUI_CyesPushDoors_EnduranceBlocked_3 = "I can barely hold myself up... I can't open it.",
    IGUI_CyesPushDoors_DoorCrowdBlocked_1 = "Blocked.. there are too many on the other side.",
    IGUI_CyesPushDoors_DoorCrowdBlocked_2 = "Impossible to push it, there are too many on the other side.",
    IGUI_CyesPushDoors_DoorCrowdBlocked_3 = "There are a lot on the other side.",
    IGUI_CyesPushDoors_DoorCrowdBlocked_4 = "Damn! It's not giving way.",
    IGUI_CyesPushDoors_PlayerStrengthBlocked_1 = "Ugh! Someone's blocking the door.",
    IGUI_CyesPushDoors_PlayerStrengthBlocked_2 = "It won't budge! Someone's behind it.",
    IGUI_CyesPushDoors_PlayerStrengthBlocked_3 = "I'm not strong enough.",
    IGUI_CyesPushDoors_ForcedOpeningWrongSide = "I can't open it from here.",
    IGUI_CyesPushDoors_ForcedOpeningBothArms = "My arms can't take that kind of force.",
    IGUI_CyesPushDoors_ForcedOpeningInjured_1 = "Ugh... I'm badly hurt.",
    IGUI_CyesPushDoors_ForcedOpeningInjured_2 = "My arms are useless.",
    IGUI_CyesPushDoors_ForcedOpeningInjured_3 = "I can't do this anymore.",
    IGUI_CyesPushDoors_ForcedOpeningNotNeeded = "There's no need to do that here.",
    IGUI_CyesPushDoors_ForcedOpeningManageable = "I think I can handle this.",
    IGUI_CyesPushDoors_FacingRequired = "I need to face the entrance.",
}

local IMPACT_BLOCKED_MESSAGE_COOLDOWN_MS = 4000
local FACING_REQUIRED_MESSAGE_COOLDOWN_MS = 1500

local function feedbackNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function translatedText(key, fallback)
    if getText then
        local ok, value = pcall(getText, key)
        if ok and value and tostring(value) ~= key then return value end
    end
    return fallback
end

local function dynamicColorInts(sector)
    local color = S.messageColor(sector)
    return math.floor((color.r * 255) + 0.5),
        math.floor((color.g * 255) + 0.5),
        math.floor((color.b * 255) + 0.5)
end

local function setDynamicHalo(player, text, withArrow, sector)
    if not player or not S.dynamicMessagesEnabled() then return false end
    local r, g, b = dynamicColorInts(sector)
    return pcall(function()
        if HaloTextHelper and HaloTextHelper.forceNextAddText then
            HaloTextHelper.forceNextAddText()
            if withArrow and HaloTextHelper.addTextWithArrow and HaloTextHelper.addText then
                HaloTextHelper.addTextWithArrow(player, "", true, r, g, b)
                HaloTextHelper.addText(player, text, " ", r, g, b)
                return
            end
            if HaloTextHelper.addText then
                HaloTextHelper.addText(player, text, "", r, g, b)
                return
            end
        end
        player:setHaloNote(text)
    end)
end

local function setEssentialHalo(player, text, sector)
    if not player or not S.dynamicMessagesEnabled() then return false end
    local r, g, b = dynamicColorInts(sector)
    return pcall(function()
        if HaloTextHelper and HaloTextHelper.forceNextAddText then
            HaloTextHelper.forceNextAddText()
            if HaloTextHelper.addText then
                HaloTextHelper.addText(player, text, "", r, g, b)
                return
            end
        end
        player:setHaloNote(text)
    end)
end

function CPD.playEffortVoiceLocal(player, variant)
    if not player or not S.soundEffectsEnabled() then return false end
    variant = math.max(1, math.min(4, math.floor(tonumber(variant) or 1)))
    local female = safeCall(player, "isFemale") == true
    local list = female and effortVoices.female or effortVoices.male
    local sound = list[variant]
    if not sound then return false end
    local _, played = safeMethod(player, "playSoundLocal", sound)
    log("Effort voice sex=" .. (female and "female" or "male") ..
        " variant=" .. tostring(variant) .. " sound=" .. tostring(sound) ..
        " played=" .. tostring(played))
    return played == true
end

function CPD.playEffortVoiceForOpener(opener)
    if not opener then return false end
    local variant = randomIndex(4) or 1
    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "effortVoice", {
                variant = variant,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.playEffortVoiceLocal(opener, variant)
end

function CPD.showArmStrainThresholdLocal(player, band)
    if not player or not S.dynamicMessagesEnabled() then return false end
    local text = translatedText("IGUI_CyesPushDoors_Tiredness", "Fatigue")
    CPD._lastDynamicThreshold = tostring(band or "unknown")
    CPD._lastDynamicThresholdAt = feedbackNowMs()
    return setDynamicHalo(player, text, true, "increment")
end

function CPD.showEnduranceThresholdLocal(player, band)
    if not player or not S.dynamicMessagesEnabled() then return false end
    local text = translatedText("IGUI_CyesPushDoors_EnduranceTiredness", "Tiredness")
    CPD._lastDynamicEnduranceThreshold = tostring(band or "unknown")
    CPD._lastDynamicEnduranceThresholdAt = feedbackNowMs()
    return setDynamicHalo(player, text, true, "increment")
end

function CPD.showCombinedThresholdLocal(player, strainBand, enduranceBand)
    if not player or not S.dynamicMessagesEnabled() then return false end
    local text = translatedText("IGUI_CyesPushDoors_CombinedExhaustion", "Exhaustion")
    CPD._lastDynamicThreshold = tostring(strainBand or "unknown")
    CPD._lastDynamicEnduranceThreshold = tostring(enduranceBand or "unknown")
    CPD._lastDynamicThresholdAt = feedbackNowMs()
    CPD._lastDynamicEnduranceThresholdAt = CPD._lastDynamicThresholdAt
    return setDynamicHalo(player, text, true, "increment")
end

local function showImpactBlockedTextLocal(player, textKey)
    if not player or not S.dynamicMessagesEnabled() or not textKey then return false end
    local now = feedbackNowMs()
    local lastAt = tonumber(CPD._lastImpactBlockedMessageAt) or 0
    if lastAt > 0 and now - lastAt < IMPACT_BLOCKED_MESSAGE_COOLDOWN_MS then return false end
    CPD._lastImpactBlockedMessageAt = now
    local text = translatedText(textKey, blockedTextFallbacks[textKey] or tostring(textKey))
    return setDynamicHalo(player, text, false, "limitation")
end

function CPD.showArmStrainBlockedLocal(player, lineIndex)
    lineIndex = math.max(1, math.min(#exhaustedTextKeys, math.floor(tonumber(lineIndex) or 1)))
    return showImpactBlockedTextLocal(player, exhaustedTextKeys[lineIndex])
end

function CPD.showEnduranceBlockedLocal(player, lineIndex)
    lineIndex = math.max(1, math.min(#enduranceBlockedTextKeys, math.floor(tonumber(lineIndex) or 1)))
    return showImpactBlockedTextLocal(player, enduranceBlockedTextKeys[lineIndex])
end

function CPD.showImpactBlockedLocal(player, textKey)
    return showImpactBlockedTextLocal(player, tostring(textKey or ""))
end

function CPD.showDoorCrowdBlockedLocal(player, lineIndex)
    if not player or not S.dynamicMessagesEnabled() then return false end
    lineIndex = math.max(1, math.min(#doorCrowdBlockedTextKeys, math.floor(tonumber(lineIndex) or 1)))
    local textKey = doorCrowdBlockedTextKeys[lineIndex]
    local text = translatedText(textKey, blockedTextFallbacks[textKey])
    return setDynamicHalo(player, text, false, "limitation")
end

function CPD.showPlayerStrengthBlockedLocal(player, lineIndex)
    if not player or not S.dynamicMessagesEnabled() then return false end
    lineIndex = math.max(1, math.min(
        #playerStrengthBlockedTextKeys,
        math.floor(tonumber(lineIndex) or 1)
    ))
    return showImpactBlockedTextLocal(player, playerStrengthBlockedTextKeys[lineIndex])
end

function CPD.showForcedOpeningMessageLocal(player, reason, lineIndex)
    if not player then return false end
    local textKey = "IGUI_CyesPushDoors_ForcedOpeningWrongSide"
    if reason == "both-arms-fractured" then
        lineIndex = math.max(1, math.min(
            #forcedOpeningInjuryTextKeys,
            math.floor(tonumber(lineIndex) or randomIndex(#forcedOpeningInjuryTextKeys) or 1)
        ))
        textKey = forcedOpeningInjuryTextKeys[lineIndex]
    elseif reason == "not-needed" then
        textKey = "IGUI_CyesPushDoors_ForcedOpeningNotNeeded"
    elseif reason == "manageable" then
        textKey = "IGUI_CyesPushDoors_ForcedOpeningManageable"
    end
    local text = translatedText(textKey, blockedTextFallbacks[textKey])
    local sector = reason == "both-arms-fractured" and "limitation" or "standard"
    return setEssentialHalo(player, text, sector)
end

function CPD.showDoorFacingRequiredLocal(player)
    if not player or not S.dynamicMessagesEnabled() then return false end
    local now = feedbackNowMs()
    local lastAt = tonumber(CPD._lastFacingRequiredMessageAt) or 0
    if lastAt > 0 and now - lastAt < FACING_REQUIRED_MESSAGE_COOLDOWN_MS then return false end
    CPD._lastFacingRequiredMessageAt = now
    local key = "IGUI_CyesPushDoors_FacingRequired"
    local text = translatedText(key, blockedTextFallbacks[key])
    return setEssentialHalo(player, text, "standard")
end

function CPD.notifyForcedOpeningMessage(opener, reason)
    if not opener then return false end
    if reason ~= "both-arms-fractured" and reason ~= "not-needed" and reason ~= "manageable" then
        reason = "wrong-side"
    end
    local lineIndex = nil
    if reason == "both-arms-fractured" then
        lineIndex = randomIndex(#forcedOpeningInjuryTextKeys) or 1
    end
    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "forcedOpeningMessage", {
                reason = reason,
                lineIndex = lineIndex,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.showForcedOpeningMessageLocal(opener, reason, lineIndex)
end

function CPD.getArmStrainThresholdCrossingBand(beforeStrain, afterStrain)
    if not CPD.getArmStrainThresholds then return nil end
    beforeStrain = tonumber(beforeStrain) or 0
    afterStrain = tonumber(afterStrain) or beforeStrain
    if afterStrain <= beforeStrain then return nil end

    local thresholds = CPD.getArmStrainThresholds()
    if beforeStrain < thresholds.high and afterStrain >= thresholds.high then
        return "high"
    elseif beforeStrain < thresholds.medium and afterStrain >= thresholds.medium then
        return "medium"
    elseif beforeStrain < thresholds.light and afterStrain >= thresholds.light then
        return "light"
    end
    return nil
end

function CPD.notifyArmStrainThresholdCrossing(opener, beforeStrain, afterStrain)
    if not opener then return false end
    local band = CPD.getArmStrainThresholdCrossingBand(beforeStrain, afterStrain)
    if not band then return false end

    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "strainThreshold", {
                band = band,
                before = beforeStrain,
                after = afterStrain,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.showArmStrainThresholdLocal(opener, band)
end

function CPD.getEnduranceThresholdCrossingBand(beforeEndurance, afterEndurance)
    beforeEndurance = math.max(0.0, math.min(1.0, tonumber(beforeEndurance) or 1.0))
    afterEndurance = math.max(0.0, math.min(1.0, tonumber(afterEndurance) or beforeEndurance))
    if afterEndurance >= beforeEndurance then return nil end

    local thresholds = C.ENDURANCE_MESSAGE_THRESHOLDS or {}
    if beforeEndurance > (tonumber(thresholds.critical) or 0.10)
        and afterEndurance <= (tonumber(thresholds.critical) or 0.10) then
        return "critical"
    elseif beforeEndurance > (tonumber(thresholds.high) or 0.25)
        and afterEndurance <= (tonumber(thresholds.high) or 0.25) then
        return "high"
    elseif beforeEndurance > (tonumber(thresholds.medium) or 0.50)
        and afterEndurance <= (tonumber(thresholds.medium) or 0.50) then
        return "medium"
    elseif beforeEndurance > (tonumber(thresholds.light) or 0.75)
        and afterEndurance <= (tonumber(thresholds.light) or 0.75) then
        return "light"
    end
    return nil
end

function CPD.notifyEnduranceThresholdCrossing(opener, beforeEndurance, afterEndurance)
    if not opener then return false end
    local band = CPD.getEnduranceThresholdCrossingBand(beforeEndurance, afterEndurance)
    if not band then return false end

    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "enduranceThreshold", {
                band = band,
                before = beforeEndurance,
                after = afterEndurance,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.showEnduranceThresholdLocal(opener, band)
end

function CPD.notifyStatThresholdCrossings(
    opener,
    beforeStrain,
    afterStrain,
    beforeEndurance,
    afterEndurance
)
    if not opener then return false end
    local strainBand = CPD.getArmStrainThresholdCrossingBand(beforeStrain, afterStrain)
    local enduranceBand = CPD.getEnduranceThresholdCrossingBand(beforeEndurance, afterEndurance)
    if strainBand and enduranceBand then
        if isServer and isServer() then
            if not sendServerCommand then return false end
            return pcall(function()
                sendServerCommand(opener, "CyesPushDoors", "combinedThreshold", {
                    strainBand = strainBand,
                    enduranceBand = enduranceBand,
                    playerId = safeCall(opener, "getOnlineID"),
                })
            end)
        end
        return CPD.showCombinedThresholdLocal(opener, strainBand, enduranceBand)
    end
    if strainBand then
        return CPD.notifyArmStrainThresholdCrossing(opener, beforeStrain, afterStrain)
    end
    if enduranceBand then
        return CPD.notifyEnduranceThresholdCrossing(opener, beforeEndurance, afterEndurance)
    end
    return false
end

local function appendTextKeys(destination, source)
    for i = 1, #source do
        destination[#destination + 1] = source[i]
    end
end

function CPD.notifyImpactBlocked(opener, strainBlocked, enduranceBlocked)
    if not opener then return false end
    strainBlocked = strainBlocked == true
    enduranceBlocked = enduranceBlocked == true
    if not strainBlocked and not enduranceBlocked then return false end

    local textKeys = {}
    if strainBlocked then appendTextKeys(textKeys, exhaustedTextKeys) end
    if enduranceBlocked then appendTextKeys(textKeys, enduranceBlockedTextKeys) end
    local textKey = textKeys[randomIndex(#textKeys) or 1]

    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "impactBlockedDialogue", {
                textKey = textKey,
                strainBlocked = strainBlocked,
                enduranceBlocked = enduranceBlocked,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.showImpactBlockedLocal(opener, textKey)
end

function CPD.notifyArmStrainBlocked(opener)
    return CPD.notifyImpactBlocked(opener, true, false)
end

function CPD.notifyEnduranceBlocked(opener)
    return CPD.notifyImpactBlocked(opener, false, true)
end

function CPD.notifyDoorCrowdBlocked(opener)
    if not opener then return false end
    local lineIndex = randomIndex(#doorCrowdBlockedTextKeys) or 1
    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "crowdBlockedDialogue", {
                lineIndex = lineIndex,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.showDoorCrowdBlockedLocal(opener, lineIndex)
end

function CPD.notifyPlayerStrengthBlocked(opener)
    if not opener then return false end
    local lineIndex = randomIndex(#playerStrengthBlockedTextKeys) or 1
    if isServer and isServer() then
        if not sendServerCommand then return false end
        return pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "playerStrengthBlockedDialogue", {
                lineIndex = lineIndex,
                playerId = safeCall(opener, "getOnlineID"),
            })
        end)
    end
    return CPD.showPlayerStrengthBlockedLocal(opener, lineIndex)
end

local kickDoorFeedbackSeen = CPD._kickDoorFeedbackSeen or {}
CPD._kickDoorFeedbackSeen = kickDoorFeedbackSeen
local kickDoorFeedbackSequence = 0
local kickDoorFeedbackPruneCounter = 0
local KICK_DOOR_FEEDBACK_TTL_MS = 60000
local KICK_DOOR_FEEDBACK_PRUNE_INTERVAL = 128

local function pruneKickDoorFeedbackSeen(now)
    kickDoorFeedbackPruneCounter = kickDoorFeedbackPruneCounter + 1
    if kickDoorFeedbackPruneCounter % KICK_DOOR_FEEDBACK_PRUNE_INTERVAL ~= 0 then return end
    for token, seenAt in pairs(kickDoorFeedbackSeen) do
        seenAt = tonumber(seenAt)
        if seenAt == nil or now - seenAt > KICK_DOOR_FEEDBACK_TTL_MS then
            kickDoorFeedbackSeen[token] = nil
        end
    end
end

local PLAYER_DOOR_ACTIONS = {
    CPDKickDoor = true,
    CPDPushFences = true,
    CPDCloseGarages = true,
    CPDPushDoorFail = true,
    CPDPushFencesFail = true,
    CPDCloseGaragesFail = true,
}

local function kickDoorFeedbackToken(door)
    kickDoorFeedbackSequence = kickDoorFeedbackSequence + 1
    local key = nil
    local okKey = pcall(function() key = CPD.getDoorWorldKey(door) end)
    if not okKey or key == nil then key = tostring(door) end
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    return tostring(now) .. ":" .. tostring(kickDoorFeedbackSequence) .. ":" .. tostring(key)
end

local function selectPlayerDoorAction(door, garage, transition, requestedAction)
    if requestedAction and PLAYER_DOOR_ACTIONS[requestedAction] == true then return requestedAction end
    if garage == true or (door and CPD.isGarageDoor(door)) then
        if transition == "close" then return "CPDCloseGarages" end
        return nil
    end
    if door and CPD.isSingleFenceGate and CPD.isSingleFenceGate(door) then
        return "CPDPushFences"
    end
    return "CPDKickDoor"
end

function CPD.playKickDoorAnimationForOpener(opener, door, token, garage, transition, requestedAction)
    if not opener then return false end
    if not S.animationsEnabled() then return false end
    if not CPD.isEligiblePlayerTarget(opener) then return false end

    garage = garage == true or (door ~= nil and CPD.isGarageDoor(door))
    transition = transition or (garage and "close" or "open")
    local actionAnim = selectPlayerDoorAction(door, garage, transition, requestedAction)
    if not actionAnim then return false end
    if not door and token == nil then return false end

    token = tostring(token or kickDoorFeedbackToken(door))
    if kickDoorFeedbackSeen[token] then return false end
    local seenAt = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    kickDoorFeedbackSeen[token] = seenAt
    pruneKickDoorFeedbackSeen(seenAt)

    if isServer and isServer() then
        if not sendServerCommand then
            kickDoorFeedbackSeen[token] = nil
            return false
        end
        local doorArgs = door and CPD.makeDoorArgs(door, nil, false, transition) or nil
        local ok = pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "kickDoorAnimation", {
                token = token,
                playerId = safeCall(opener, "getOnlineID"),
                garage = garage,
                transition = transition,
                actionAnim = actionAnim,
                door = doorArgs,
            })
        end)
        if not ok then kickDoorFeedbackSeen[token] = nil end
        return ok
    end

    if not ISTimedActionQueue or not ISCPDKickDoorAction then
        kickDoorFeedbackSeen[token] = nil
        log("KICK_ACTION_UNAVAILABLE")
        return false
    end

    local ok = pcall(function()
        ISTimedActionQueue.add(ISCPDKickDoorAction:new(opener, token, actionAnim))
    end)
    if not ok then
        kickDoorFeedbackSeen[token] = nil
        log("KICK_ACTION_QUEUE_FAILED")
    end
    return ok
end

Animations.registerZombieReaction = CPD.registerZombieReaction
Animations.registerZombieReactionGroup = CPD.registerZombieReactionGroup
Animations.getZombieReaction = CPD.getZombieReaction
Animations.getZombieReactionGroup = CPD.getZombieReactionGroup
Animations.findZombieReaction = CPD.findZombieReaction
Animations.selectZombieReaction = CPD.selectZombieReaction
Animations.playZombieReaction = CPD.playZombieReaction
Animations.selectDoorStaggerReaction = CPD.selectDoorStaggerReaction
Animations.playDoorStaggerReaction = CPD.playDoorStaggerReaction
Animations.selectDoorStaggerAnimation = CPD.selectDoorStaggerAnimation
Animations.playDoorStaggerAnimation = CPD.playDoorStaggerAnimation
Animations.selectSlidingDoorReaction = CPD.selectSlidingDoorReaction
Animations.playSlidingDoorReaction = CPD.playSlidingDoorReaction
Animations.selectSlidingDoorAnimation = CPD.selectSlidingDoorAnimation
Animations.playSlidingDoorAnimation = CPD.playSlidingDoorAnimation
Animations.playKickDoorAnimationForOpener = CPD.playKickDoorAnimationForOpener
SoundEffects.getDoorImpactSound = CPD.getDoorImpactSound
SoundEffects.playImpactSoundLocal = CPD.playImpactSoundLocal
SoundEffects.playImpactSoundForOpener = CPD.playImpactSoundForOpener
SoundEffects.playEffortVoiceLocal = CPD.playEffortVoiceLocal
SoundEffects.playEffortVoiceForOpener = CPD.playEffortVoiceForOpener
Visual.showArmStrainThresholdLocal = CPD.showArmStrainThresholdLocal
Visual.showEnduranceThresholdLocal = CPD.showEnduranceThresholdLocal
Visual.showCombinedThresholdLocal = CPD.showCombinedThresholdLocal
Visual.showArmStrainBlockedLocal = CPD.showArmStrainBlockedLocal
Visual.showEnduranceBlockedLocal = CPD.showEnduranceBlockedLocal
Visual.showImpactBlockedLocal = CPD.showImpactBlockedLocal
Visual.showDoorCrowdBlockedLocal = CPD.showDoorCrowdBlockedLocal
Visual.showForcedOpeningMessageLocal = CPD.showForcedOpeningMessageLocal
Visual.notifyArmStrainThresholdCrossing = CPD.notifyArmStrainThresholdCrossing
Visual.notifyEnduranceThresholdCrossing = CPD.notifyEnduranceThresholdCrossing
Visual.notifyStatThresholdCrossings = CPD.notifyStatThresholdCrossings
Visual.notifyArmStrainBlocked = CPD.notifyArmStrainBlocked
Visual.notifyEnduranceBlocked = CPD.notifyEnduranceBlocked
Visual.notifyImpactBlocked = CPD.notifyImpactBlocked
Visual.notifyDoorCrowdBlocked = CPD.notifyDoorCrowdBlocked
Visual.notifyForcedOpeningMessage = CPD.notifyForcedOpeningMessage
