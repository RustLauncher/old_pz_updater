ProjectALife = ProjectALife or {}

local Script = {
    gestureGapMs = 2500,
    waitShare = 0.8,
    spotMs = 5000,
    spotLimit = 128,
    spotted = {},
    spottedSize = 0,
    gestureAt = setmetatable({}, { __mode = "k" }),
    metrics = { overhead = 0, panel = 0, silent = 0, gestures = 0, covers = 0 },
}
ProjectALife.EncounterScript = Script

Script.classOf = {
    ENC_SURPRISE = "notice", ENC_REVENGE = "notice", ENC_AGAIN = "notice", ENC_CALLOUT = "notice",
    ENC_BASE_CALLOUT = "notice", ROBBERY_SPOT = "notice",
    ENC_ASK_WHO = "challenge", ENC_ASK_INTENT = "challenge", ENC_ASK_HOWMANY = "challenge",
    ENC_ASK_CARRY = "challenge", ENC_DEMAND_DROP = "challenge", ENC_DEMAND_LEAVE = "challenge",
    ENC_DEMAND_TOLL = "challenge", ROBBERY_HANDS_UP_1 = "challenge", ROBBERY_WEAPON_DOWN = "challenge",
    ENC_TURN = "escalate", ENC_BETRAY = "escalate", ROBBERY_EXECUTE = "escalate",
    ENC_PART = "finish", ENC_LEAVE = "finish", ENC_PAID = "finish", ENC_JOIN_YES = "finish",
    ENC_CAUGHT = "finish", ROBBERY_TAKE = "finish", ROBBERY_NOTHING = "finish", ROBBERY_DONT_FOLLOW = "finish",
}

Script.gestures = {
    ENC_SURPRISE = "stop", ENC_REVENGE = "stop", ENC_CALLOUT = "shout", ENC_BASE_CALLOUT = "shout",
    ENC_CALLOUT_REPEAT = "shout", ENC_DEMAND_DROP = "stop", ENC_DEMAND_LEAVE = "stop", ENC_DEMAND_TOLL = "come_here",
    ENC_SILENCE = "come_here", ENC_SILENCE_LAST = "stop", ENC_WALK_AWAY = "stop", ENC_REPLY_OK = "yes",
    ENC_REPLY_DOUBT = "undecided", ENC_NO_FLANKER = "no", ENC_JOIN_NO = "no_thanks", ENC_JOIN_YES = "thumbs_up",
    ENC_PART = "wave", ENC_COME_OUT = "come_here", ENC_CAME_OUT = "stop", ENC_STALL = "undecided",
    ROBBERY_SPOT = "stop", ROBBERY_HANDS_UP_1 = "stop", ROBBERY_HANDS_UP_2 = "stop", ROBBERY_HANDS_UP_3 = "stop",
    ROBBERY_WEAPON_DOWN = "stop", ROBBERY_SHUT_UP = "stop", ROBBERY_MOVE = "stop", ROBBERY_RELEASE = "wave",
}

function Script.reset()
    Script.spotted, Script.spottedSize = {}, 0
    Script.gestureAt = setmetatable({}, { __mode = "k" })
    Script.metrics = { overhead = 0, panel = 0, silent = 0, gestures = 0, covers = 0 }
end

function Script.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Script.enabled()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return true end
    return vars.Encounter_ScriptedCues ~= false
end

function Script.holdMs()
    local warning = ProjectALife.ModuleWarning
    if warning ~= nil and type(warning.holdMs) == "function" then return warning.holdMs() end
    return 8000
end

function Script.waitMs(base)
    base = tonumber(base) or 10000
    return math.max(500, math.min(base, math.floor(Script.holdMs() * Script.waitShare)))
end

function Script.crewKeyOf(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
    if memory.groupId ~= nil then return tostring(memory.groupId) end
    if memory.outpostId ~= nil then return "outpost:" .. tostring(memory.outpostId) end
    return "solo:" .. tostring(type(actor) == "table" and actor.uid or "?")
end

function Script.noteSpot(actor, playerKey, now)
    if not Script.enabled() or playerKey == nil then return false end
    if Script.spottedSize >= Script.spotLimit then Script.spotted, Script.spottedSize = {}, 0 end
    local key = Script.crewKeyOf(actor) .. "|" .. tostring(playerKey)
    if Script.spotted[key] == nil then Script.spottedSize = Script.spottedSize + 1 end
    Script.spotted[key] = tonumber(now) or Script.now()
    return true
end

function Script.mayDraw(state, event)
    if not Script.enabled() then return true end
    local class = Script.classOf[event]
    if class == nil then return false end
    local said = type(state) == "table" and state.said or nil
    if said ~= nil and said[class] == true then return false end
    if class == "notice" and type(state) == "table" then
        local crew = state.crewKey or state.groupKey
        local at = crew ~= nil and Script.spotted[tostring(crew) .. "|" .. tostring(state.playerKey)] or nil
        if at ~= nil and Script.now() - at < Script.spotMs then return false end
    end
    return true
end

function Script.mark(state, event)
    Script.metrics.overhead = Script.metrics.overhead + 1
    local class = Script.classOf[event]
    if type(state) ~= "table" or class == nil then return end
    state.said = type(state.said) == "table" and state.said or {}
    state.said[class] = true
end

function Script.gesture(shell, id)
    if shell == nil or type(id) ~= "string" then return false end
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" or type(animations.presetOf) ~= "function"
            or animations.presetOf(id) == nil then return false end
    if type(animations.active) == "table" and animations.active[shell] ~= nil then return false end
    if type(animations.blocksLocomotion) == "function" and animations.blocksLocomotion(shell) == true then return false end
    local now = Script.now()
    if now - (Script.gestureAt[shell] or -1e12) < Script.gestureGapMs then return false end
    Script.gestureAt[shell] = now
    local ok, applied = pcall(animations.apply, shell, id)
    if ok and applied == true then
        Script.metrics.gestures = Script.metrics.gestures + 1
        return true
    end
    return false
end

function Script.cover(shell, x, y, now)
    if shell == nil or tonumber(x) == nil then return false end
    Script.metrics.covers = Script.metrics.covers + 1
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then guard.faceAimPoint(shell, x, y, now) end
        local combat, animations = ProjectALife.Combat, ProjectALife.Animations
        if combat ~= nil and animations ~= nil and type(combat.readyPresetFor) == "function"
                and type(animations.apply) == "function"
                and not (type(animations.active) == "table" and animations.active[shell] ~= nil) then
            local preset = combat.readyPresetFor(shell, shell:getPrimaryHandItem(), nil)
            if preset ~= nil then animations.apply(shell, preset) end
        end
    end)
    return true
end

function Script.line(record, shell, player, event, context)
    local speech, data = ProjectALife.Speech, ProjectALife.DialogueData
    if speech == nil or data == nil or type(record) ~= "table" or type(speech.pick) ~= "function" then return nil end
    if type(data.load) == "function" then data.load() end
    local pool = type(data.barks) == "table" and data.barks[event] or nil
    if type(pool) ~= "table" then return nil end
    if type(context) ~= "table" then context = speech.contextFor(record, player) end
    local key = player ~= nil and speech.playerKey(player) or nil
    local chosen = speech.pick(pool, context, record.uid, key, nil)
    if chosen == nil then return nil end
    local text = speech.render(chosen.t, nil, shell, context.psex)
    speech.remember(record.uid, key, chosen.t)
    return text
end

function Script.deliver(player, uid, text)
    if type(text) ~= "string" or text == "" then return false end
    local server = type(isServer) == "function" and isServer() == true
    if server then
        if player == nil or type(sendServerCommand) ~= "function" then return false end
        return pcall(sendServerCommand, player, "ProjectALife", "encounterLine",
            { uid = tostring(uid or ""), text = text }) == true
    end
    local receive = ProjectALife.TalkClientReceive
    if type(receive) ~= "function" then return false end
    return pcall(receive, "ProjectALife", "speech", { uid = uid, text = text }) == true
end

function Script.say(state, record, shell, player, event, context, vars)
    local talk = ProjectALife.Talk
    if not Script.enabled() then
        if talk == nil or type(talk.bark) ~= "function" then return nil, false end
        return talk.bark(record, shell, player, event, context, vars), true
    end
    Script.gesture(shell, Script.gestures[event])
    if Script.mayDraw(state, event) then
        if talk == nil or type(talk.bark) ~= "function" then return nil, false end
        local text = talk.bark(record, shell, player, event, context, vars)
        if text ~= nil then Script.mark(state, event) end
        return text, text ~= nil
    end
    local text = Script.line(record, shell, player, event, context)
    if text == nil then
        Script.metrics.silent = Script.metrics.silent + 1
        return nil, false
    end
    Script.metrics.panel = Script.metrics.panel + 1
    Script.deliver(player, record.uid, text)
    return text, false
end

return Script
