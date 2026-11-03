require "ProjectALife/Talk/ALifeTalkQuestionRows"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Decisions/ALifeNpcOpinion"

ProjectALife = ProjectALife or {}
local Questions = { cooldownMs = 600000 }
ProjectALife.TalkQuestions = Questions

function Questions.enabled()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(vars) ~= "table" or vars.Talk_NpcQuestions ~= false
end

function Questions.playerSafe(player, now)
    if player == nil then return false end
    if type(player.getVariableBoolean) == "function" then
        for _, name in ipairs({ "IsSurrendering", "Surrender", "HandsUp" }) do
            local ok, raised = pcall(player.getVariableBoolean, player, name)
            if not ok or raised == true then return false end
        end
    end
    local talk = ProjectALife.Talk
    local key = ProjectALife.Speech.playerKey(player)
    if type(talk.handsUpSince) == "function" and talk.handsUpSince(key, now - talk.settings.stateMs) then return false end
    local robbery = ProjectALife.ModuleRobbery
    for _, state in pairs(robbery ~= nil and type(robbery.active) == "table" and robbery.active or {}) do
        if state.playerKey == key then return false end
    end
    return true
end

function Questions.safe(record, shell, player, now)
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    if not Questions.enabled() or not speech.authoritative() or not speech.alive(player)
            or talk.busy(record, now) or not talk.talkable(shell, record) then return false end
    if speech.quietReason(shell, record, now) ~= nil then return false end
    if talk.stance(record, player) == "hostile" or not Questions.playerSafe(player, now) then return false end
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.visit ~= nil or memory.robbery ~= nil or memory.surrender ~= nil then return false end
    if type(memory.injuries) == "table" and #memory.injuries > 0 then return false end
    if type(memory.injury) == "table" and (memory.injury.s == "down" or memory.injury.s == "recovering") then return false end
    if type(shell.hasModData) == "function" and type(shell.getModData) == "function" then
        local ok, present = pcall(shell.hasModData, shell)
        if not ok then return false end
        if present then
            local got, body = pcall(shell.getModData, shell)
            if not got or type(body) ~= "table" then return false end
            if body.ProjectALifeWoundLeg == true or body.ProjectALifeBleedOutAtMs ~= nil
                    or (tonumber(body.ProjectALifeWounds) or 0) > 0 then return false end
        end
    end
    local caution = ProjectALife.Caution
    if caution ~= nil and type(caution.idleDanger) == "function" and caution.idleDanger(record, shell, now) ~= nil then return false end
    return true
end

function Questions.prepare(state, sessionId)
    if state.npcQuestionSession ~= sessionId then
        state.npcQuestionCount, state.npcQuestionSession = 0, sessionId
        if type(state.pending) == "string" and string.sub(state.pending, 1, 9) == "NPC_ASKS_" then state.pending = nil end
    end
end

function Questions.start(record, shell, player, state, context, now)
    if state.pending ~= nil then return nil end
    if (state.npcQuestionCount or 0) >= 2 or not Questions.safe(record, shell, player, now) then return nil end
    local memory = type(record.memory) == "table" and record.memory or {}
    local last = type(memory.npcQuestion) == "table" and memory.npcQuestion or {}
    local at = tonumber(last.at)
    local key = ProjectALife.Speech.playerKey(player)
    if at ~= nil and now - at < Questions.cooldownMs
            and not (state.npcQuestionCount == 1 and last.key == key and last.session == state.npcQuestionSession) then return nil end
    if type(ZombRand) == "function" and ZombRand(4) ~= 0 then return nil end
    local rows = ProjectALife.TalkQuestionRows
    local count = state.npcQuestionCount or 0
    local event = rows.events[(tonumber(last.next) or 0) % #rows.events + 1]
    context = Questions.context(record, player, context)
    if not ProjectALife.Talk.writeMemory(record.uid, function(m)
        m.npcQuestion = { at = now, key = key, session = state.npcQuestionSession,
            next = (tonumber(last.next) or 0) + 1 }
    end) then return nil end
    local said = ProjectALife.Talk.bark(record, shell, player, event, context)
    if said == nil then
        ProjectALife.Talk.writeMemory(record.uid, function(m) m.npcQuestion = memory.npcQuestion end)
        return nil
    end
    state.pending, state.npcQuestionCount = event, count + 1
    return said
end

function Questions.answer(player, listener, choice, state, context, now)
    if not Questions.safe(listener.record, listener.shell, player, now) then
        state.pending = nil
        return nil, "busy"
    end
    if type(choice.answerTo) ~= "table" or state.pending == nil or choice.answerTo[state.pending] ~= true then return nil, "no_question" end
    context = Questions.context(listener.record, player, context)
    local said = ProjectALife.Talk.speak(listener.record, listener.shell, player,
        ProjectALife.DialogueData.replies[choice.id], context)
    if said == nil then return nil, "no_reply" end
    state.pending = nil
    if choice.kind then
        local opinion = ProjectALife.NpcOpinion
        if opinion ~= nil and type(opinion.enabled) == "function" and opinion.enabled() and type(opinion.adjust) == "function" then
            opinion.adjust(listener.record, player, 1, "You answered their question")
        end
    end
    return said, "answered"
end

function Questions.context(record, player, source)
    local context = {}
    for key, value in pairs(source or {}) do context[key] = value end
    if ProjectALife.NpcOpinion.greetTone(record, player) == "cold" then context.stance = "careful" end
    return context
end

Questions.followIntents = { HOW_ARE_YOU = true, ASK_NEWS = true, ASK_NAME = true, TELL_STORY = true,
    ASK_FAMILY = true, ASK_DESTINATION = true, ASK_JOB_BEFORE = true, ASK_HOME = true }
function Questions.follow(player, listener, state, now)
    if state.pending ~= nil or (state.npcQuestionCount or 0) >= 2 then return false end
    local session, turns, generation = state.sessionId, state.turns, listener.record.generation
    local key = ProjectALife.Speech.playerKey(player)
    ProjectALife.Talk.later(1800, function()
        local talk, registry = ProjectALife.Talk, ProjectALife.ActorRegistry
        local record = registry.read(listener.record.uid)
        local shell = talk.shellFor(listener.record.uid)
        if record == nil or shell ~= listener.shell or record.generation ~= generation or state.menuOpen ~= true or state.sessionId ~= session
                or state.turns ~= turns or not talk.lineOfSight(player, shell) then return end
        if (record.memory or {}).talkHoldPlayerKey ~= key then return end
        local near = false
        for _, listener in ipairs(talk.listeners(player, 6)) do
            if listener.record.uid == record.uid and listener.shell == shell then near = true; break end
        end
        if not near then return end
        local now = type(getTimestampMs) == "function" and getTimestampMs() or nil
        if type(talk.adapters.nowMs) == "function" then now = talk.adapters.nowMs() end
        if now == nil or not Questions.safe(record, shell, player, now) then return end
        local context = ProjectALife.Speech.contextFor(record, player)
        context.stance = talk.stance(record, player)
        local said = Questions.start(record, shell, player, state, context, now)
        if said ~= nil then talk.choiceReply(player, { uid = record.uid, playerKey = ProjectALife.Speech.playerKey(player),
            sessionId = session, ok = true, reason = "answered", text = said, pending = state.pending, stance = context.stance }) end
    end)
    return true
end

return Questions
