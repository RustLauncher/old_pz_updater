require "ProjectALife/Talk/ALifeDialogueData"
require "ProjectALife/Talk/ALifeDialogueRoles"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalkIntents"
require "ProjectALife/Talk/ALifeTalkOrderRows"
require "ProjectALife/Talk/ALifeTalkWinterRows"
require "ProjectALife/Talk/ALifeTalkSocial"
require "ProjectALife/Talk/ALifeTalkQuestions"
require "ProjectALife/Decisions/ALifeRelations"
require "ProjectALife/Decisions/ALifeNpcOpinion"

ProjectALife = ProjectALife or {}

local Talk = {
    settings = {
        enabled = true,
        listenRadius = 12,
        loudRadius = 25,
        coneDegrees = 60,
        holdMs = 4000,
        stateMs = 60000,
        mateChance = 25,
        mateRadius = 6,
        tolerateMs = 480000,
        wariness = 300000,
        helpRadius = 10,
        orderMs = 45000,
        helpCooldownMs = 60000,
        hitRepeatMs = 30000,
        mateHitRadius = 15,

        hitBarkCooldownMs = 6000,
        groupHitBarkMs = 4000,

        hitBarkDelayMs = 350,
        maxTextLength = 200,
    },
    adapters = {},
    states = {},
    queue = {},
    sequences = {},
    emotes = {},
    helped = {},
    hits = {},
    hitBarkAt = {},
    groupHitBarkAt = {},
    metrics = { heard = 0, answered = 0, unknown = 0, nobody = 0, hostile = 0, busy = 0, mates = 0, helped = 0, hits = 0, emotes = 0,
        aggressionClosed = 0 },
}
ProjectALife.Talk = Talk

local function nowMs()
    if type(Talk.adapters.nowMs) == "function" then return Talk.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(maximum)
    if type(Talk.adapters.roll) == "function" then return Talk.adapters.roll(maximum) end
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

function Talk.configure(options)
    options = type(options) == "table" and options or {}
    if options.enabled ~= nil then Talk.settings.enabled = options.enabled ~= false end
    if type(options.adapters) == "table" then Talk.adapters = options.adapters end
end

function Talk.reset()
    Talk.states, Talk.queue, Talk.emotes, Talk.helped, Talk.hits = {}, {}, {}, {}, {}
    Talk.hitBarkAt, Talk.groupHitBarkAt = {}, {}
    Talk.sequences = {}
    Talk.lastCommandAt = {}
    Talk.fightSeenAtMs, Talk.fightSeenCount = {}, 0
    Talk.metrics = { heard = 0, answered = 0, unknown = 0, nobody = 0, hostile = 0, busy = 0, mates = 0, helped = 0, hits = 0, emotes = 0,
        aggressionClosed = 0 }
end

local function registry() return ProjectALife.ActorRegistry end

function Talk.shellFor(uid)
    if type(Talk.adapters.shellFor) == "function" then return Talk.adapters.shellFor(uid) end
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    if binding ~= nil then return binding.shell end

    local perception = ProjectALife.Perception
    if type(isClient) == "function" and isClient() and perception ~= nil
            and type(perception.activeActorForShell) == "function" then
        for _, sampled in ipairs(perception.zombieSnapshot and perception.zombieSnapshot.actors or {}) do
            local actor = perception.activeActorForShell(sampled.body)
            if actor ~= nil and actor.uid == uid then return sampled.body end
        end
    end
    return nil
end

local function position(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function"
            or type(object.getZ) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if ok then return x, y, z end
    return nil
end

local function alive(shell)
    return ProjectALife.Speech.alive(shell)
end

function Talk.talkable(shell, record)
    return ProjectALife.Speech.talkable(shell, record, nowMs())
end

function Talk.inCombat(record)
    if type(record) ~= "table" then return false end
    local activity, intent = tostring(record.activity or ""), tostring(record.intent or "")
    return activity == "combat" or string.find(intent, "attack", 1, true) ~= nil
        or string.find(intent, "engage", 1, true) ~= nil or string.find(intent, "manhunt", 1, true) ~= nil
end

Talk.fightHoldMs = 6000
Talk.fightSeenAtMs = {}
Talk.fightSeenCount = 0
function Talk.inFight(record, now)
    if type(record) ~= "table" then return false end
    local uid = tostring(record.uid)
    now = tonumber(now) or nowMs()
    if Talk.inCombat(record) then
        if Talk.fightSeenAtMs[uid] == nil then
            Talk.fightSeenCount = Talk.fightSeenCount + 1
            if Talk.fightSeenCount > 512 then Talk.fightSeenAtMs, Talk.fightSeenCount = {}, 1 end
        end
        Talk.fightSeenAtMs[uid] = now
        return true
    end
    local seen = Talk.fightSeenAtMs[uid]
    if seen == nil then return false end
    if now >= seen and now - seen < Talk.fightHoldMs then return true end
    Talk.fightSeenAtMs[uid] = nil
    Talk.fightSeenCount = math.max(0, Talk.fightSeenCount - 1)
    return false
end

function Talk.busy(record, now)
    if type(record) ~= "table" then return false end
    return Talk.inFight(record, now) or record.activity == "fleeing"
        or record.intent == "retreat" or record.intent == "recover_endurance" or record.intent == "gun_flee"
end

Talk.coopWords = {
    "Don't like strangers, but we're in deep shit here, eh? Stay back and watch my rear",
    "Don't like you being here, but they don't care who you are - keep off me and watch my back",
    "Strangers make me jumpy, the dead make me worse - stay off me, cover my rear",
    "Not the time to argue, eh? You look like you can handle yourself, just watch behind us",
    "Fine, stick around, just give me room and keep 'em off my back",
}
Talk.coopCount = 0
function Talk.coopLine()
    Talk.coopCount = Talk.coopCount + 1
    return Talk.coopWords[(Talk.coopCount - 1) % #Talk.coopWords + 1]
end

function Talk.stance(record, player)
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.talking) == "function" and standoff.talking(record, player) then return "careful" end
    if standoff ~= nil and type(standoff.truced) == "function" and standoff.truced(record, player) then return "careful" end
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.playerStance) ~= "function" then return "neutral" end
    local ok, stance = pcall(relations.playerStance, record, player)
    if not ok or stance == nil then return "neutral" end
    if stance == "allied" then return "friendly" end
    return stance
end

function Talk.listeners(player, radius)
    local px, py, pz = position(player)
    local list = {}
    if px == nil or registry() == nil then return list end
    local facingX, facingY = nil, nil
    pcall(function()
        local forward = player:getForwardDirection()
        facingX, facingY = forward:getX(), forward:getY()
    end)
    local cosLimit = math.cos(math.rad(Talk.settings.coneDegrees))
    registry().each(function(record)
        if record.lifecycle ~= "active" then return end
        local shell = Talk.shellFor(record.uid)
        if shell == nil then return end
        local x, y, z = position(shell)
        if x == nil or math.floor(z or 0) ~= math.floor(pz or 0) then return end
        local dx, dy = x - px, y - py
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > radius then return end
        if not Talk.talkable(shell, record) then return end
        local inCone = false
        if facingX ~= nil and distance > 0.01 then
            inCone = (dx * facingX + dy * facingY) / distance >= cosLimit
        end
        list[#list + 1] = { record = record, shell = shell, distance = distance, inCone = inCone }
    end)
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

function Talk.addressee(listeners)
    for _, listener in ipairs(listeners) do
        if listener.inCone then return listener end
    end
    return listeners[1]
end

local function stateKey(playerKey, uid) return tostring(playerKey) .. ":" .. tostring(uid) end

function Talk.state(playerKey, uid, now)
    local key = stateKey(playerKey, uid)
    local state = Talk.states[key]
    if state == nil or now - (state.at or 0) > Talk.settings.stateMs then
        state = { pending = nil, misses = 0, turns = 0, at = now }
        Talk.states[key] = state
    end
    state.at = now
    return state
end

function Talk.openSession(playerKey, uid, sessionId)
    local now = nowMs()
    local state = Talk.state(playerKey, uid, now)
    state.menuOpen, state.sessionId, state.sessionActivityAtMs = true, sessionId, now
    return state
end

Talk.walkHours = 1

function Talk.walkWith(player, listener, intent)
    local personal = ProjectALife.PersonalRep
    if personal == nil or personal.enabled ~= true then return false, "walk_off" end
    local key = ProjectALife.Speech.playerKey(player)
    local memory = type(listener.record.memory) == "table" and listener.record.memory or {}
    local hours = 0
    if type(getGameTime) == "function" and getGameTime() ~= nil then hours = getGameTime():getWorldAgeHours() end
    if intent == "WALK_STOP" then
        if type(memory.walkWith) ~= "table" or memory.walkWith.key ~= key then return false, "not_walking" end
        Talk.writeMemory(listener.record.uid, function(m)
            m.walkWith, m.walkCooldownUntilHours = nil, hours + 2
            if m.stance == "walkWith" then m.stance, m.stanceAnchor = nil, nil end
        end)
        return true, "Yeah, ok, see ya out there"
    end
    if memory.stance ~= nil and memory.stance ~= "route" and memory.stance ~= "walkWith" then return false, "busy" end
    if hours < (tonumber(memory.walkCooldownUntilHours) or -math.huge) then return false, "busy" end
    local x, y, z = position(player)
    if x == nil then return false, "unavailable" end
    local written = Talk.writeMemory(listener.record.uid, function(m)
        m.walkWith = { key = key, untilHours = hours + Talk.walkHours, startedHours = hours }
        m.stance, m.stanceAnchor = "walkWith", { x = x, y = y, z = z or 0 }
    end)
    if not written then return false, "unavailable" end
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.note) == "function" then pcall(opinion.note, "walk", listener.record, player) end
    return true, "Sure, go ahead, I'm right behind you"
end

function Talk.writeMemory(uid, mutate)
    local reg = registry()
    if reg == nil or type(reg.read) ~= "function" then return false end
    local current = reg.read(uid)
    if current == nil then return false end
    local memory = current.memory or {}
    local before = { talkHoldUntilMs = memory.talkHoldUntilMs, talkHoldPlayerKey = memory.talkHoldPlayerKey,
        gossipHoldUntilMs = memory.gossipHoldUntilMs, gossipToken = memory.gossipToken,
        robbery = memory.robbery }
    local ok, updated = pcall(reg.update, current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        mutate(record.memory)
    end)
    ok = ok and updated ~= nil and updated ~= false
    local executor, brain = ProjectALife.Executor, ProjectALife.DecisionLoop
    if ok and executor ~= nil and type(executor.conversationChanged) == "function"
            and brain ~= nil and type(brain.refreshDirective) == "function" then
        local fresh = reg.read(uid)
        if fresh ~= nil and executor.conversationChanged(before, fresh.memory or {}, nowMs()) then brain.refreshDirective(uid) end
    end
    return ok
end

function Talk.hold(record, shell, player, now, ms)
    if Talk.busy(record, now) then
        Talk.releaseHold(record.uid, ProjectALife.Speech.playerKey(player))
        return false
    end
    ProjectALife.Speech.face(shell, player)
    local untilMs = now + (ms or Talk.settings.holdMs)
    Talk.writeMemory(record.uid, function(memory)
        memory.talkHoldUntilMs = untilMs
        memory.talkHoldPlayerKey = ProjectALife.Speech.playerKey(player)
    end)
    local decisions = ProjectALife.DecisionLoop
    if decisions ~= nil and type(decisions.stopNow) == "function" then pcall(decisions.stopNow, record.uid, now) end
end

function Talk.releaseHold(uid, playerKey)
    local current = registry() and registry().read(uid)
    if current == nil or playerKey == nil or (current.memory or {}).talkHoldPlayerKey ~= playerKey then return false end
    return Talk.writeMemory(uid, function(memory)
        if memory.talkHoldPlayerKey == playerKey then memory.talkHoldUntilMs = nil; memory.talkHoldPlayerKey = nil end
    end)
end

function Talk.groupMembers(record, radius, fromShell)
    local members = {}
    local memory = type(record.memory) == "table" and record.memory or {}
    local groupId, outpostId = memory.groupId, memory.outpostId
    if (groupId == nil and outpostId == nil) or registry() == nil then return members end
    local sx, sy = position(fromShell)
    registry().each(function(other)
        if other.uid == record.uid or other.lifecycle ~= "active" then return end
        local m = type(other.memory) == "table" and other.memory or {}
        if not ((groupId ~= nil and m.groupId == groupId) or (outpostId ~= nil and m.outpostId == outpostId)) then return end
        local shell = Talk.shellFor(other.uid)
        if shell == nil or not alive(shell) then return end
        local x, y = position(shell)
        if x == nil or sx == nil or (x - sx) ^ 2 + (y - sy) ^ 2 > radius * radius then return end
        members[#members + 1] = { record = other, shell = shell }
    end)
    return members
end

function Talk.destinationFor(record)
    local memory = type(record.memory) == "table" and record.memory or {}
    local target = memory.travelTarget or memory.destination or memory.routeTarget
    if type(target) == "table" and target.x ~= nil then
        local town = ProjectALife.Speech.nearestTown(target.x, target.y)
        if town ~= nil then return town end
    end

    return nil
end

function Talk.denFor(shell)
    local rumors = ProjectALife.Rumors
    if rumors == nil or type(rumors.den) ~= "function" then return nil end
    local x, y = position(shell)
    local ok, den = pcall(rumors.den, x, y)
    if ok and type(den) == "table" then return den.where end
    return nil
end

Talk.denAsking = { ASK_DEN = true, ASK_RAIDERS = true, ASK_DANGER = true, ASK_NEWS = true, COME_WITH_ME = true }
Talk.escalating = { INSULT = true, THREATEN = true, DEMAND_ITEMS = true, HANDS_UP = true, DROP_WEAPON = true }
Talk.freshRegisters = { civilian = true, family = true, worker = true, rescue = true }

function Talk.varsFor(intent, record, shell, player, text)
    local vars = {}
    local Intents = ProjectALife.TalkIntents
    if intent == "ASK_DESTINATION" or intent == "JOIN_REQUEST" then vars.destination = Talk.destinationFor(record) end
    if intent == "ASK_DIRECTIONS" then
        local town = Intents.townIn(text)
        if town ~= nil then vars.town = town.label; vars.destination = town.label end
    end
    if intent == "ASK_WHERE_AM_I" then
        local px, py = position(player)
        vars.town = ProjectALife.Speech.nearestTown(px, py)
    end
    if Talk.denAsking[intent] then vars.den = Talk.denFor(shell) end
    local ok, item = pcall(function() return player:getPrimaryHandItem() end)
    if ok and item ~= nil then
        pcall(function() vars.weapon = string.lower(tostring(item:getDisplayName())) end)
    end
    return vars
end

function Talk.observations(record, shell, player, now)
    local facts = {}
    local visit = ProjectALife.SafehouseVisit
    if visit ~= nil and type(visit.observations) == "function" then
        for key, value in pairs(visit.observations(record, player)) do facts[key] = value end
    end
    local perception = ProjectALife.Perception
    local sx, sy, sz = position(shell)
    if perception ~= nil and sx ~= nil then
        for _, map in ipairs({ perception.engagements or {}, perception.lastKnown or {} }) do
            local seen = map[record.uid]
            local age = seen and now - (tonumber(seen.atMs) or -math.huge)
            if seen and age >= 0 and age <= 15000 and tonumber(seen.x) and tonumber(seen.y)
                    and math.floor(tonumber(seen.z) or -1) == math.floor(sz or 0)
                    and (seen.x - sx)^2 + (seen.y - sy)^2 <= 625 then
                if seen.kind == "zombie" then facts.recent_zombie_contact = true
                elseif seen.kind == "player" or seen.kind == "actor" then facts.recent_human_contact = true end
            end
        end
    end
    if player ~= nil and type(instanceof) == "function" then
        pcall(function()
            for _, item in pairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
                if instanceof(item, "HandWeapon") and item:getFullType() ~= "Base.BareHands" then facts.player_armed = true end
            end
        end)
    end
    return facts
end

function Talk.doorSay(record, shell, player, intent, words)
    local speech, data = ProjectALife.Speech, ProjectALife.DialogueData
    local visitor = ProjectALife.SafehouseVisit
    local near = nil
    if visitor ~= nil and type(visitor.nearUid) == "function" then
        near = function(listener) return visitor.nearUid(record.uid, listener) end
    end
    if data ~= nil and type(data.replies) == "table" and type(data.load) == "function"
            and speech ~= nil and type(speech.contextFor) == "function" then
        data.load()
        local context = speech.contextFor(record, player)
        context.scope, context.near = "visitor", near
        context.stance = Talk.stance(record, player)
        context.facts = Talk.observations(record, shell, player, nowMs())
        local social, opinion = ProjectALife.TalkSocial, ProjectALife.NpcOpinion
        if social ~= nil and type(social.mood) == "function" then context.mood = social.mood(record, player) end
        if context.stance ~= "hostile" and opinion ~= nil and type(opinion.greetTone) == "function"
                and opinion.greetTone(record, player) == "cold" then
            context.stance = "careful"
            if context.mood == nil or context.mood == "warm" then context.mood = "grim" end
        end
        local pool
        if intent == "DOOR_SEARCH" then pool = context.facts.visit_search_refused and "DOOR_SEARCH_REFUSE" or "DOOR_SEARCH_YES"
        elseif intent == "DOOR_WHO" and context.facts.visit_asks_headcount == true then pool = "VISIT_TELL_HEADCOUNT" end
        local visit = ProjectALife.SafehouseVisit
        if pool == nil and visit ~= nil and type(visit.replyPool) == "function" then
            local facts
            pool, facts = visit.replyPool(record, player, intent)
            for key, value in pairs(facts or {}) do context.facts[key] = value end
        end
        if type(data.replies) == "table" and type(data.replies[pool]) == "table" then
            local vars = {}
            if intent == "DOOR_WEAPONS_DOWN" and visit ~= nil and type(visit.weaponsReply) == "function" then
                local _, weaponVars = visit.weaponsReply(record)
                vars = weaponVars or vars
            end
            local said = Talk.speak(record, shell, player, data.replies[pool], context, vars)
            if said ~= nil then
                if intent == "DOOR_TRADE_CONFIRM" then return words .. " " .. said end
                return said
            end
        end
    end
    speech.say(shell, words, { face = player, scope = "visitor", near = near })
    return words
end

function Talk.doorUnknown(record, shell, player)
    local speech, data = ProjectALife.Speech, ProjectALife.DialogueData
    if data == nil or type(data.barks) ~= "table" or type(data.load) ~= "function"
            or speech == nil or type(speech.contextFor) ~= "function" then return nil end
    data.load()
    local visitor = ProjectALife.SafehouseVisit
    local context = speech.contextFor(record, player)
    context.scope = "visitor"
    if visitor ~= nil and type(visitor.nearUid) == "function" then
        context.near = function(listener) return visitor.nearUid(record.uid, listener) end
    end
    context.stance = Talk.stance(record, player)
    context.facts = Talk.observations(record, shell, player, nowMs())
    return Talk.bark(record, shell, player, "TALK_FALLBACK_1", context)
end

function Talk.speak(record, shell, player, records, context, vars, allowShortRepeat)
    local Speech = ProjectALife.Speech
    local playerKey = Speech.playerKey(player)
    local chosen = Speech.pick(records, context, record.uid, playerKey, vars, allowShortRepeat ~= true)
    if chosen == nil and type(context) == "table" and context.mood ~= nil then
        local mood = context.mood
        context.mood = nil
        chosen = Speech.pick(records, context, record.uid, playerKey, vars, allowShortRepeat ~= true)
        context.mood = mood
    end
    if chosen == nil then return nil, nil end
    if chosen.beats ~= nil then
        if Talk.busy(record, nowMs()) or context.stance == "hostile" or #Talk.queue + #chosen.beats > Talk.queueCap then return nil, nil end
        for _, beat in ipairs(chosen.beats) do
            if Speech.claimsUnknown(beat.t, vars) then return nil, nil end
        end
    end
    local text = Speech.render(chosen.t, vars, shell, context.psex or Speech.sexOf(player))
    local face = nil
    if not Talk.busy(record, nowMs()) and context.stance ~= "hostile" then face = player end
    if not Speech.say(shell, text, { face = face, downedOk = context.downedOk == true, scope = context.scope,
            near = context.near }) then return nil, nil end
    Speech.remember(record.uid, playerKey, chosen.t)
    if chosen.beats ~= nil then Talk.sequence(record, shell, player, chosen, vars) end
    return text, chosen
end

function Talk.homeSay(record, shell, player, answer, stance)
    local speech, data = ProjectALife.Speech, ProjectALife.DialogueData
    if data ~= nil and type(data.replies) == "table" and type(data.load) == "function"
            and speech ~= nil and type(speech.contextFor) == "function" and type(answer.pool) == "string" then
        data.load()
        local records = data.replies[answer.pool]
        if type(records) == "table" then
            local context = speech.contextFor(record, player)
            context.stance = stance
            local said = Talk.speak(record, shell, player, records, context, answer.vars or {})
            if said ~= nil then return said end
        end
    end
    speech.say(shell, answer.text, { face = player })
    return answer.text
end

function Talk.calmGreeting(record, shell, player, now)
    if not Talk.talkable(shell, record) or Talk.busy(record, now) then return false end
    local stance = Talk.stance(record, player)
    if stance ~= "friendly" and stance ~= "neutral" then return false end
    local speech = ProjectALife.Speech
    local key = speech.playerKey(player)
    local memory = type(record.memory) == "table" and record.memory or {}
    if key ~= nil and type(memory.hostileToPlayerKeys) == "table"
            and memory.hostileToPlayerKeys[key] == true then return false end
    if key ~= nil and type(memory.carefulPlayerKeys) == "table"
            and now < (tonumber(memory.carefulPlayerKeys[key]) or 0) then return false end
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.greetTone) == "function"
            and opinion.greetTone(record, player) == "cold" then return false end
    local caution = ProjectALife.Caution
    if caution ~= nil and type(caution.idleDanger) == "function"
            and caution.idleDanger(record, shell, now) ~= nil then return false end
    return true
end

function Talk.bark(record, shell, player, event, context, vars)
    local data = ProjectALife.DialogueData
    if (event == "GREET_PLAYER" or event == "PASSING_PLAYER")
            and not Talk.calmGreeting(record, shell, player, nowMs()) then
        Talk.metrics.quieted = (Talk.metrics.quieted or 0) + 1
        return nil
    end
    local allowed, reason = ProjectALife.Speech.allows(shell, record, event, nil, nil)
    if not allowed then
        Talk.metrics.quieted = (Talk.metrics.quieted or 0) + 1
        return nil
    end
    if type(context) == "table" then context.downedOk = reason == "downed" or nil end
    local lines = data.barks[event]
    local text, chosen = Talk.speak(record, shell, player, lines, context, vars, true)
    if text == nil then
        local fallback = ProjectALife.Speech.combatFallback(event)
        if fallback ~= nil then
            return Talk.speak(record, shell, player, { { t = fallback } }, context, vars, true)
        end
    end
    return text, chosen
end

function Talk.awaitAnswer(record, player, said, now)
    if type(said) ~= "string" or string.find(said, "%?[\"')]*%s*$") == nil then return false end
    Talk.state(ProjectALife.Speech.playerKey(player), record.uid, now).pending = "GENERIC"
    return true
end

function Talk.respond(player, listener, text, now, choiceIntent)
    if listener ~= nil and type(listener.record) == "table" and type(listener.record.memory) == "table"
            and type(listener.record.memory.person) == "table" then
        local visitorTalk = ProjectALife.VisitorTalk
        if visitorTalk == nil or type(visitorTalk.respond) ~= "function" then return nil, "unavailable" end
        return visitorTalk.respond(player, listener, text, now, choiceIntent)
    end
    local Speech, data, Intents = ProjectALife.Speech, ProjectALife.DialogueData, ProjectALife.TalkIntents
    local visit = ProjectALife.SafehouseVisit
    if visit ~= nil and type(visit.doorPeer) == "function" and listener ~= nil and listener.record ~= nil
            and visit.doorPeer(player, listener.record.uid) ~= nil then
        if not Speech.authoritative() or not alive(player) then return nil, "unavailable" end
        if Talk.busy(listener.record, now) or not Talk.talkable(listener.shell, listener.record) then return nil, "busy" end
        if Talk.stance(listener.record, player) == "hostile" then return nil, "hostile" end
        local doorIntent = Intents.doorFor(text, choiceIntent)
        if doorIntent == nil then
            local line = Talk.doorUnknown(listener.record, listener.shell, player)
            if line ~= nil then return line, "unknown" end
            return nil, "door_choice_required"
        end
        local accepted, words = visit.choose(player, listener.record.uid, doorIntent)
        if accepted and (doorIntent == "DOOR_GIVE" or doorIntent == "DOOR_TREAT" or doorIntent == "DOOR_LEND")
                and visit.giftView(player, listener.record.uid) ~= nil then
            local party = ProjectALife.Party
            local notified = false
            if party ~= nil and type(party.notice) == "function" then
                notified = party.notice(player, "Open Talk to choose which item to give") == true
            end
            if not notified then Speech.say(listener.shell, "Show me what you're offering first", {}) end
            return words, "gift_select"
        end
        if accepted then return Talk.doorSay(listener.record, listener.shell, player, doorIntent, words), "door_answered" end
        return nil, words
    end
    if visit ~= nil and type(visit.live) == "function" and listener ~= nil and listener.record ~= nil
            and visit.live(listener.record.uid) ~= nil then return nil, "not_door_peer" end
    data.load()
    local record, shell = listener.record, listener.shell
    Talk.sequences[record.uid] = nil
    local playerKey = Speech.playerKey(player)
    local state = Talk.state(playerKey, record.uid, now)
    local context = Speech.contextFor(record, player)
    context.stance = Talk.stance(record, player)
    context.facts = Talk.observations(record, shell, player, now)
    local social = ProjectALife.TalkSocial
    if social ~= nil and type(social.mood) == "function" then
        local okMood, mood = pcall(social.mood, record, player)
        if okMood then context.mood = mood end
    end
    state.turns = state.turns + 1
    if Talk.busy(record, now) then
        Talk.releaseHold(record.uid, playerKey)
        Talk.metrics.busy = Talk.metrics.busy + 1
        return Talk.bark(record, shell, player, "TALK_BUSY_COMBAT", context), "busy"
    end
    local intent = choiceIntent or Intents.classify(text, state.pending ~= nil, data)
    if context.stance == "hostile" then
        Talk.metrics.hostile = Talk.metrics.hostile + 1
        local said = nil
        if intent ~= nil and data.replies[intent] ~= nil then
            said = Talk.speak(record, shell, player, data.replies[intent], context, Talk.varsFor(intent, record, shell, player, text))
        end
        return said or Talk.bark(record, shell, player, "TALK_IGNORE_HOSTILE", context), "hostile"
    end
    Talk.hold(record, shell, player, now)

    if intent == nil then
        Talk.metrics.unknown = Talk.metrics.unknown + 1
        state.misses = state.misses + 1
        local event = "TALK_FALLBACK_1"
        if state.misses == 2 then event = "TALK_FALLBACK_2"
        elseif state.misses >= 3 then
            event = state.pending ~= nil and "TALK_FALLBACK_3" or "TALK_FALLBACK_END"
            if state.misses >= 4 or state.pending == nil then state.misses, state.pending = 0, nil end
        end
        return Talk.bark(record, shell, player, event, context), "unknown"
    end
    state.misses = 0
    if choiceIntent == nil and social ~= nil and type(social.typed) == "function" then
        local okTyped, line, why = pcall(social.typed, player, listener, intent)
        if okTyped and line ~= nil then return line, why end
    end
    if intent == "NPC_OPEN" and state.pending == nil then
        local questions = ProjectALife.TalkQuestions
        if questions ~= nil then
            local asked = questions.start(record, shell, player, state, context, now)
            if asked ~= nil then return asked, "answered" end
        end
        local orders = ProjectALife.TalkOrders
        local greeted = orders ~= nil and type(orders.greet) == "function" and orders.greet(record, shell, player, context, now) or nil
        if greeted ~= nil then
            Talk.metrics.answered = Talk.metrics.answered + 1
            return greeted, "answered"
        end
    end

    local answer = Intents.choiceById(intent)
    if answer ~= nil and answer.npcAnswer == true and ProjectALife.TalkQuestions ~= nil then
        return ProjectALife.TalkQuestions.answer(player, listener, answer, state, context, now)
    end

    if state.pending ~= nil and (intent == "YES" or intent == "NO") then
        local ask = state.pending
        state.pending = nil
        local pools = intent == "YES" and data.yesPools or data.noPools

        local said = Talk.speak(record, shell, player, pools[ask] or pools.GENERIC, context,
            Talk.varsFor(ask, record, shell, player, text))
        if intent == "YES" then Talk.accept(record, player, ask, now) end
        return said, "answered"
    end
    local asked = state.pending
    state.pending = nil

    local handler = Talk.choiceHandlers[intent]
    if type(handler) == "function" then
        local handled, handledReason = handler(record, shell, player, context, now, text, asked)
        if handled ~= nil then
            Talk.metrics.answered = Talk.metrics.answered + 1
            return handled, handledReason or "answered"
        end
    end

    local supplies = ProjectALife.TalkSupplies or require "ProjectALife/Talk/ALifeTalkSupplies"
    if supplies and supplies.handles(intent) then return supplies.respond(record, shell, player, intent, now) end

    if intent == "COME_WITH_ME" and context.temperament == "fresh" and Talk.freshRegisters[context.register] then
        local said = Talk.bark(record, shell, player, "COME_WITH_ME_REFUSE", context, { den = Talk.denFor(shell) })
        if said ~= nil then return said, "refused" end
    end

    if Talk.escalating[intent] then Talk.escalate(record, shell, player, context, now) end

    local vars = Talk.varsFor(intent, record, shell, player, text)
    local said, chosen = Talk.speak(record, shell, player, data.replies[intent], context, vars)
    if said == nil then
        return Talk.bark(record, shell, player, "TALK_FALLBACK_END", context), "no_reply"
    end
    if chosen ~= nil and chosen.ask ~= nil and chosen.beats == nil then state.pending = chosen.ask end
    Talk.metrics.answered = Talk.metrics.answered + 1
    if intent == "FAREWELL" or intent == "GO_AWAY" then Talk.releaseHold(record.uid, playerKey) end
    return said, chosen.beats ~= nil and "scripted" or "answered"
end

Talk.choiceHandlers = {}

function Talk.introduce(record, shell, player, context, now)
    local names, speech = ProjectALife.Names, ProjectALife.Speech
    if names == nil or type(names.of) ~= "function" or names.of(record) == nil or type(context) ~= "table" then return nil end
    local friendly = context.stance == "friendly" or context.stance == "neutral"
    local pool = friendly and names.introPool(context.register) or names.refuseLines
    if type(pool) ~= "table" or #pool == 0 then return nil end
    local text = speech.render(pool[roll(#pool) + 1], names.vars(record), shell, context.psex)
    if not speech.say(shell, text, { face = player }) then return nil end
    local key = speech.playerKey(player)
    if friendly and key ~= nil then
        Talk.writeMemory(record.uid, function(memory) names.markIntroduced(memory, key) end)
    end
    return text, friendly and "introduced" or "answered"
end

Talk.choiceHandlers.ASK_NAME = function(record, shell, player, context, now)
    return Talk.introduce(record, shell, player, context, now)
end

function Talk.nameResult(result, uid, player)
    local names, reg = ProjectALife.Names, registry()
    if type(result) ~= "table" or names == nil or reg == nil or type(reg.read) ~= "function" then return result end
    local record = reg.read(uid)
    if record == nil or names.of(record) == nil then return result end
    local key = ProjectALife.Speech.playerKey(player)
    if result.ok == true and result.stance == "friendly" and key ~= nil and not names.knows(record, key) then
        Talk.writeMemory(uid, function(memory) names.markIntroduced(memory, key) end)
        record = reg.read(uid) or record
    end
    result.name, result.known = names.shown(record, key)
    return result
end

function Talk.accept(record, player, ask, now)
    local playerKey = ProjectALife.Speech.playerKey(player)
    if ask == "JOIN_GROUP" or ask == "WALK_TOGETHER" or ask == "STAY_NIGHT" then
        Talk.tolerate(record, playerKey, now + Talk.settings.tolerateMs)
    end
end

function Talk.tolerate(record, playerKey, untilMs)
    if playerKey == nil then return end
    local memory = type(record.memory) == "table" and record.memory or {}
    local groupId, outpostId = memory.groupId, memory.outpostId
    local uids = { record.uid }
    if registry() ~= nil and (groupId ~= nil or outpostId ~= nil) then
        registry().each(function(other)
            local m = type(other.memory) == "table" and other.memory or {}
            if other.uid ~= record.uid and ((groupId ~= nil and m.groupId == groupId) or (outpostId ~= nil and m.outpostId == outpostId)) then
                uids[#uids + 1] = other.uid
            end
        end)
    end
    for _, uid in ipairs(uids) do
        Talk.writeMemory(uid, function(m)
            m.tolerateUntil = type(m.tolerateUntil) == "table" and m.tolerateUntil or {}
            m.tolerateUntil[playerKey] = untilMs
        end)
    end
end

function Talk.escalate(record, shell, player, context, now)
    if context.stance == "careful" then
        local careful = ProjectALife.ModuleCareful
        if careful ~= nil and type(careful.noteShout) == "function" then pcall(careful.noteShout, record, shell, player) end
    elseif context.stance == "neutral" or context.stance == "friendly" then
        local playerKey = ProjectALife.Speech.playerKey(player)
        if playerKey ~= nil then
            Talk.writeMemory(record.uid, function(m)
                m.carefulPlayerKeys = type(m.carefulPlayerKeys) == "table" and m.carefulPlayerKeys or {}
                m.carefulPlayerKeys[playerKey] = now + Talk.settings.wariness
            end)
        end
    end
end

Talk.typedNotices = {
    not_door_peer = "Step closer to the door to talk to them",
    door_choice_required = "Pick one of the door options to talk to them",
    unavailable = "They can't answer right now",
    loading = "They are thinking it over, try again in a moment",
    busy = "They are busy right now",
}
Talk.noticeAt = {}

function Talk.typedLog(reason, uid, now)
    local why = tostring(reason)
    if Talk.typedLogWhy == why and now - (Talk.typedLogAt or 0) < 10000 then return end
    Talk.typedLogWhy, Talk.typedLogAt = why, now
    print("[ALIFE-TALK] typed text got no answer why=" .. why .. " uid=" .. tostring(uid))
end

function Talk.typedNotice(player, reason, now)
    local text = Talk.typedNotices[tostring(reason)]
    local party = ProjectALife.Party
    if text == nil or party == nil or type(party.notice) ~= "function" then return false end
    local key = tostring(ProjectALife.Speech.playerKey(player))
    if now - (Talk.noticeAt[key] or -math.huge) < 3000 then return false end
    Talk.noticeAt[key] = now
    return pcall(party.notice, player, text) == true
end

function Talk.onPlayerText(player, text, loud)
    if Talk.settings.enabled ~= true or player == nil then return false, "disabled" end
    if not ProjectALife.Speech.authoritative() then return false, "server_authority_required" end
    text = tostring(text or "")
    text = string.gsub(text, "[%c]", " ")
    if #text > Talk.settings.maxTextLength then text = string.sub(text, 1, Talk.settings.maxTextLength) end
    if string.match(text, "^%s*$") then return false, "empty" end
    Talk.metrics.heard = Talk.metrics.heard + 1
    local now = nowMs()
    local robbery = ProjectALife.ModuleRobbery
    if robbery ~= nil and type(robbery.onPlayerWords) == "function" then
        local handled = robbery.onPlayerWords(player, text, loud == true, now)
        if handled then return true, "robbery" end
    end
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.onPlayerWords) == "function"
            and standoff.onPlayerWords(player, text, loud == true, now) then
        return true, "standoff"
    end
    if loud == true then
        local investigation = ProjectALife.Investigation
        local px, py, pz = position(player)
        if investigation ~= nil and type(investigation.noteShout) == "function" and px ~= nil then
            pcall(investigation.noteShout, px, py, pz, player)
        end
    end
    local listeners = Talk.listeners(player, loud == true and Talk.settings.loudRadius or Talk.settings.listenRadius)
    if loud == true and ProjectALife.ModuleCareful and ProjectALife.ModuleCareful.hearShout then
        local heard = false
        for _, listener in ipairs(listeners) do
            heard = ProjectALife.ModuleCareful.hearShout(listener.record, listener.shell, player, now) or heard
        end
        if heard then return true, "noise_warning" end
    end
    local addressee = Talk.addressee(listeners)
    if addressee == nil then
        Talk.metrics.nobody = Talk.metrics.nobody + 1
        Talk.typedLog("nobody", nil, now)
        return false, "nobody"
    end
    local said, reason = Talk.respond(player, addressee, text, now)
    if said == nil then
        Talk.typedNotice(player, reason, now)
        Talk.typedLog(reason, addressee.record.uid, now)
    end

    if said ~= nil and reason == "answered" and roll(100) < Talk.settings.mateChance then
        for _, listener in ipairs(listeners) do
            local a = type(addressee.record.memory) == "table" and addressee.record.memory or {}
            local b = type(listener.record.memory) == "table" and listener.record.memory or {}
            if #Talk.queue < Talk.queueCap and listener ~= addressee and a.groupId ~= nil and a.groupId == b.groupId
                    and listener.distance <= addressee.distance + Talk.settings.mateRadius then
                Talk.queue[#Talk.queue + 1] = { at = now + 1200 + roll(1300), player = player, listener = listener, text = text }
                break
            end
        end
    end
    return said ~= nil, reason
end

Talk.queueCap = 64
function Talk.later(delayMs, fn)
    if type(fn) ~= "function" or #Talk.queue >= Talk.queueCap then return false end
    Talk.queue[#Talk.queue + 1] = { at = nowMs() + math.max(0, tonumber(delayMs) or 0), fn = fn }
    return true
end

function Talk.sequence(record, shell, player, chosen, vars)
    local token = { uid = record.uid, generation = record.generation, shell = shell,
        player = player, chosen = chosen, vars = vars, index = 1 }
    Talk.sequences[record.uid] = token
    if Talk.later(chosen.beats[1].afterMs, function() Talk.advanceSequence(token) end) then
        Talk.hold(record, shell, player, nowMs(), chosen.beats[1].afterMs + Talk.settings.holdMs)
    else
        Talk.sequences[record.uid] = nil
    end
end

function Talk.advanceSequence(token)
    local uid, shell, player, chosen = token.uid, token.shell, token.player, token.chosen
    if Talk.sequences[uid] ~= token then return end
    local current = registry() and registry().read(uid)
    local sx, sy, sz = position(shell)
    local px, py, pz = position(player)
    local valid = current and Talk.shellFor(uid) == shell and Talk.talkable(shell, current)
        and current.generation == token.generation and alive(shell) and alive(player)
        and not Talk.busy(current, nowMs()) and sx ~= nil and px ~= nil
        and math.floor(sz or 0) == math.floor(pz or 0)
        and (sx - px)^2 + (sy - py)^2 <= Talk.settings.listenRadius^2
    if not valid then Talk.sequences[uid] = nil; return end
    local speech, now = ProjectALife.Speech, nowMs()
    local context = speech.contextFor(current, player)
    context.stance = Talk.stance(current, player)
    context.facts = Talk.observations(current, shell, player, now)
    if context.stance == "hostile" or not ProjectALife.DialogueData.allows(chosen.g, context) then
        Talk.sequences[uid] = nil; return
    end
    local beat = chosen.beats[token.index]
    if not speech.say(shell, speech.render(beat.t, token.vars, shell, context.psex), { face = player }) then
        Talk.sequences[uid] = nil; return
    end
    speech.remember(uid, speech.playerKey(player), beat.t)
    token.index = token.index + 1
    local following = chosen.beats[token.index]
    if following == nil then
        if chosen.ask ~= nil then
            Talk.state(speech.playerKey(player), uid, now).pending = chosen.ask

            Talk.choiceReply(player, { uid = uid, ok = true, pending = chosen.ask, stance = context.stance })
        end
        Talk.sequences[uid] = nil
    elseif not Talk.later(following.afterMs, function() Talk.advanceSequence(token) end) then
        Talk.sequences[uid] = nil
    end

    Talk.hold(current, shell, player, now, (following and following.afterMs or 0) + Talk.settings.holdMs)
end

function Talk.tick(now)
    if Talk.settings.enabled ~= true or not ProjectALife.Speech.authoritative() then
        Talk.queue, Talk.sequences = {}, {}
        return 0
    end
    now = now or nowMs()
    local orders = ProjectALife.TalkOrders
    if orders ~= nil and type(orders.tick) == "function" then pcall(orders.tick, now) end
    local pending, done = Talk.queue, 0
    Talk.queue = {}
    for _, item in ipairs(pending) do
        if now < item.at then Talk.queue[#Talk.queue + 1] = item end
    end
    for _, item in ipairs(pending) do
        if now >= item.at and item.fn ~= nil then
            done = done + 1
            pcall(item.fn)
        elseif now >= item.at then
            done = done + 1

            local current = registry() and registry().read(item.listener.record.uid)
            local shell = current and Talk.shellFor(current.uid)
            local sx, sy, sz = position(shell)
            local px, py, pz = position(item.player)
            if current and shell == item.listener.shell and Talk.talkable(shell, current)
                    and alive(item.player) and not Talk.busy(current, now) and sx ~= nil and px ~= nil
                    and math.floor(sz or 0) == math.floor(pz or 0)
                    and (sx - px) ^ 2 + (sy - py) ^ 2 <= Talk.settings.listenRadius ^ 2 then
                item.listener.record = current
                local data = ProjectALife.DialogueData
                local intent = ProjectALife.TalkIntents.classify(item.text, false, data)
                local context = ProjectALife.Speech.contextFor(item.listener.record, item.player)
                context.stance = Talk.stance(item.listener.record, item.player)
                context.facts = Talk.observations(item.listener.record, item.listener.shell, item.player, now)
                if intent ~= nil and context.stance ~= "hostile" then
                    local said = Talk.speak(item.listener.record, item.listener.shell, item.player, data.replies[intent], context,
                        Talk.varsFor(intent, item.listener.record, item.listener.shell, item.player, item.text))
                    if said ~= nil then Talk.metrics.mates = Talk.metrics.mates + 1 end
                end
            end
        end
    end
    for key, state in pairs(Talk.states) do
        if now - (state.at or 0) > Talk.settings.stateMs * 2 then Talk.states[key] = nil end
    end
    return done
end

function Talk.onPlayerEmote(player, emote)
    local playerKey = ProjectALife.Speech.playerKey(player)
    if playerKey == nil then return false end
    local at = nowMs()
    local previous = Talk.emotes[playerKey]
    local handsUpAt = previous and previous.handsUpAt or nil
    if emote == "surrender" then handsUpAt = at end
    Talk.emotes[playerKey] = { emote = tostring(emote or ""), at = at, handsUpAt = handsUpAt }
    Talk.metrics.emotes = Talk.metrics.emotes + 1
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.onPlayerEmote) == "function"
            and standoff.onPlayerEmote(player, tostring(emote or "")) then
        return true
    end
    local robbery = ProjectALife.ModuleRobbery
    if robbery ~= nil and type(robbery.onPlayerEmote) == "function" then
        pcall(robbery.onPlayerEmote, player, tostring(emote or ""))
    end
    return true
end

function Talk.handsUpSince(playerKey, since)
    local entry = Talk.emotes[tostring(playerKey)]
    return entry ~= nil and entry.handsUpAt ~= nil and entry.handsUpAt >= (tonumber(since) or 0)
end

function Talk.onHelped(player, x, y)
    if Talk.settings.enabled ~= true or player == nil or x == nil or registry() == nil then return 0 end
    local now = nowMs()
    local playerKey = ProjectALife.Speech.playerKey(player)
    local thanked = 0
    local reach = Talk.settings.helpRadius * Talk.settings.helpRadius
    registry().each(function(record)
        if thanked >= 1 or record.lifecycle ~= "active" or not Talk.inCombat(record) then return end
        local shell = Talk.shellFor(record.uid)
        if shell == nil or not alive(shell) then return end
        local sx, sy = position(shell)
        if sx == nil or (sx - x) ^ 2 + (sy - y) ^ 2 > reach then return end
        local stance = Talk.stance(record, player)
        if stance ~= "friendly" and stance ~= "neutral" then return end
        local key = tostring(playerKey) .. ":" .. record.uid
        if now < (Talk.helped[key] or 0) then return end
        Talk.helped[key] = now + Talk.settings.helpCooldownMs
        local context = ProjectALife.Speech.contextFor(record, player)
        context.stance = stance
        if Talk.bark(record, shell, player, "HELPED_BY_PLAYER", context) ~= nil then
            thanked = thanked + 1
            local opinion = ProjectALife.NpcOpinion
            if opinion ~= nil and type(opinion.note) == "function" then pcall(opinion.note, "help_fight", record, player) end
            Talk.metrics.helped = Talk.metrics.helped + 1
            local safehouse = ProjectALife.SafehouseDirector
            if safehouse ~= nil and type(safehouse.deed) == "function" then
                safehouse.deed("helped_fight", playerKey, record.factionId, record.uid,
                    tostring(record.uid) .. ":helped:" .. string.format("%.0f", now))
            end
        end
    end)
    return thanked
end

function Talk.startedFight(record, player, now)
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.startedFight) == "function" then
        return fair.startedFight(record, player, now) == true
    end
    local relations = ProjectALife.Relations
    return relations ~= nil and type(relations.wasAggressor) == "function"
        and relations.wasAggressor(record, player, now) == true
end

Talk.losingHealth = 0.35
function Talk.losing(record, shell, now)
    if shell == nil or type(shell.getModData) ~= "function" then return false end
    local data = shell:getModData()
    if type(data) == "table" and now < (tonumber(data.ProjectALifeDownedUntilMs) or -1) then return true end
    local survival = ProjectALife.Survival
    if survival == nil or type(survival.healthRatio) ~= "function" then return false end
    local ok, ratio = pcall(survival.healthRatio, record, shell)
    return ok and tonumber(ratio) ~= nil and ratio <= Talk.losingHealth
end

function Talk.aggressorEvent(record, shell, context, now)
    if not Talk.losing(record, shell, now) then return "HURT" end
    if context.temperament == "veteran" or context.temperament == "predator" then return "RETREAT" end
    return "SURRENDER"
end

function Talk.onHitByPlayer(player, target, attack)
    if Talk.settings.enabled ~= true or player == nil or target == nil or registry() == nil then return false end
    if type(instanceof) == "function" and not instanceof(player, "IsoPlayer") then return false end

    if not alive(target) then return false end
    local uid = ProjectALife.Speech.variable(target, "ALifeUID")
    if uid == nil then return false end
    local record = registry().read(tostring(uid))
    if record == nil then return false end
    local relations = ProjectALife.Relations
    if ProjectALife.ModuleRobbery and ProjectALife.ModuleRobbery.onPlayerAttack then
        ProjectALife.ModuleRobbery.onPlayerAttack(player, record)
    end
    local now = nowMs()
    local playerKey = ProjectALife.Speech.playerKey(player)
    local key = tostring(playerKey) .. ":" .. record.uid
    local again = now < (Talk.hits[key] or 0)
    Talk.hits[key] = now + Talk.settings.hitRepeatMs
    Talk.metrics.hits = Talk.metrics.hits + 1
    local memory = type(record.memory) == "table" and record.memory or {}
    local groupKey = memory.groupId or ("solo:" .. record.uid)
    if now < (Talk.hitBarkAt[record.uid] or 0) or now < (Talk.groupHitBarkAt[groupKey] or 0) then
        Talk.metrics.hitBarksThrottled = (Talk.metrics.hitBarksThrottled or 0) + 1
        return true
    end
    Talk.hitBarkAt[record.uid] = now + Talk.settings.hitBarkCooldownMs
    Talk.groupHitBarkAt[groupKey] = now + Talk.settings.groupHitBarkMs
    local context = ProjectALife.Speech.contextFor(record, player)
    context.stance = Talk.stance(record, player)
    context.aggressor = Talk.startedFight(record, player, now)
    context.attack = attack or ProjectALife.Wounds.attackKind(player, nil)
    local event = again and "HIT_BY_PLAYER_AGAIN" or "HIT_BY_PLAYER"
    if context.aggressor then event = Talk.aggressorEvent(record, target, context, now)
    elseif not again and context.temperament == "fresh" and roll(100) < 50 then event = "PLEAD" end
    Talk.later(Talk.settings.hitBarkDelayMs, function()
        if not alive(target) then return end
        local hitEvent = event
        if ProjectALife.Speech.quietReason(target, record, nowMs()) == "downed" then hitEvent = "HURT" end
        Talk.bark(record, target, player, hitEvent, context)
        if again or context.aggressor then return end
        for _, mate in ipairs(Talk.groupMembers(record, Talk.settings.mateHitRadius, target)) do
            local mateContext = ProjectALife.Speech.contextFor(mate.record, player)
            mateContext.stance = Talk.stance(mate.record, player)
            mateContext.attack = context.attack
            if relations ~= nil and type(relations.witnesses) == "function"
                    and relations.witnesses(mate.record, record, player)
                    and Talk.bark(mate.record, mate.shell, player, "MATE_HIT_BY_PLAYER", mateContext) ~= nil then break end
        end
    end)
    return true
end

Talk.commandIntervalMs = { talkSay = 800, talkChoose = 800, talkSession = 1000, talkEmote = 400, talkHelped = 3000, talkState = 250, safehouseDoorSync = 5000 }
Talk.lastCommandAt = {}

function Talk.choiceReply(player, payload)
    if type(isServer) == "function" and isServer() then
        if type(sendServerCommand) == "function" then sendServerCommand(player, "ProjectALife", "talkResult", payload) end
    elseif type(ProjectALife.TalkClientReceive) == "function" then
        ProjectALife.TalkClientReceive("ProjectALife", "talkResult", payload)
    end
end

function Talk.lineOfSight(player, shell, record)
    if type(record) == "table" and type(record.memory) == "table"
            and (type(record.memory.guest) == "table" or type(record.memory.visit) == "table") then return true end
    if LosUtil == nil or type(getCell) ~= "function" then return true end
    local px, py, pz = position(player)
    local sx, sy, sz = position(shell)
    if px == nil or sx == nil or type(LosUtil.lineClear) ~= "function" then return false end
    local ok, ray = pcall(function() return LosUtil.lineClear(getCell(),
        math.floor(px), math.floor(py), math.floor(pz), math.floor(sx), math.floor(sy), math.floor(sz), false) end)
    return ok and tostring(ray) ~= "Blocked"
end

Talk.orders = {}
Talk.orderCap = 64
Talk.answerKinds = { standoff = true }

function Talk.orderKey(player, uid)
    return stateKey(ProjectALife.Speech.playerKey(player), uid)
end

function Talk.issueOrder(player, uid, kind, ttlMs)
    local speech = ProjectALife.Speech
    uid = tostring(uid or "")
    local shell = Talk.shellFor(uid)
    local px, py = position(player)
    local sx, sy = position(shell)
    if uid == "" or #uid > 160 or px == nil or sx == nil or not alive(player) or not alive(shell) then return false end
    local now = nowMs()
    local reach = speech.orderReach(math.sqrt((px - sx) ^ 2 + (py - sy) ^ 2))
    local ttl = math.max(speech.orderSettings.minMs, math.min(speech.orderSettings.maxMs, tonumber(ttlMs) or Talk.settings.orderMs))
    local key, count = Talk.orderKey(player, uid), 0
    for other, entry in pairs(Talk.orders) do
        if now > entry.untilMs then Talk.orders[other] = nil else count = count + 1 end
    end
    if Talk.orders[key] == nil and count >= Talk.orderCap then return false end
    if Talk.orders[key] == nil then speech.orderMetrics.orders = speech.orderMetrics.orders + 1 end
    Talk.orders[key] = { uid = uid, kind = tostring(kind or "order"), reach = reach, untilMs = now + ttl }
    if reach > speech.orderMetrics.maxRange then speech.orderMetrics.maxRange = reach end
    local payload = { uid = uid, kind = Talk.orders[key].kind, reach = reach, ttlMs = ttl }
    if Talk.answerKinds[payload.kind] ~= true then return true end
    if type(isServer) == "function" and isServer() then
        if type(sendServerCommand) == "function" then pcall(sendServerCommand, player, "ProjectALife", "talkOrder", payload) end
    else
        speech.orderNote(payload, now)
    end
    return true
end

function Talk.orderOk(player, uid, now)
    local speech = ProjectALife.Speech
    uid = tostring(uid or "")
    local entry = Talk.orders[Talk.orderKey(player, uid)]
    if entry == nil then return false, "no_order" end
    now = now or nowMs()
    return speech.orderRule(entry, player, Talk.shellFor(uid), now)
end

function Talk.clearOrders(player, uid)
    local prefix = tostring(ProjectALife.Speech.playerKey(player)) .. ":"
    for key, entry in pairs(Talk.orders) do
        if string.sub(key, 1, #prefix) == prefix and (uid == nil or entry.uid == tostring(uid)) then
            Talk.orders[key] = nil
            if Talk.answerKinds[entry.kind] == true then
                local payload = { uid = entry.uid, kind = entry.kind, clear = true }
                if type(isServer) == "function" and isServer() then
                    if type(sendServerCommand) == "function" then pcall(sendServerCommand, player, "ProjectALife", "talkOrder", payload) end
                else
                    ProjectALife.Speech.orderNote(payload, nowMs())
                end
            end
        end
    end
end

function Talk.orderAnswered(player, uid)
    local px, py = position(player)
    local sx, sy = position(Talk.shellFor(tostring(uid)))
    if px == nil or sx == nil then return false end
    if (px - sx) ^ 2 + (py - sy) ^ 2 > ProjectALife.Speech.orderSettings.floorTiles ^ 2 then
        local metrics = ProjectALife.Speech.orderMetrics
        metrics.answeredFar = metrics.answeredFar + 1
        return true
    end
    return false
end

function Talk.orderRefused(player, uid)
    if Talk.orders[Talk.orderKey(player, uid)] == nil then return false end
    local metrics = ProjectALife.Speech.orderMetrics
    metrics.refusedRange = metrics.refusedRange + 1
    return true
end

function Talk.absentReason(player, uid, reach)
    local reg = registry()
    local record = reg ~= nil and type(reg.read) == "function" and reg.read(uid) or nil
    if record == nil then return "too_far" end
    if record.lifecycle ~= "active" then return "unavailable" end
    local shell = Talk.shellFor(uid)
    if shell == nil or Talk.talkable(shell, record) then return "too_far" end
    local px, py, pz = position(player)
    local sx, sy, sz = position(shell)
    if px == nil or sx == nil or math.floor(sz or 0) ~= math.floor(pz or 0)
            or (sx - px) ^ 2 + (sy - py) ^ 2 > reach * reach then
        return "too_far"
    end
    return "unavailable"
end

function Talk.visitorTarget(uid)
    local reg = registry()
    if reg == nil then return nil end
    local record = type(reg.peek) == "function" and reg.peek(uid) or (type(reg.read) == "function" and reg.read(uid) or nil)
    if type(record) ~= "table" or type(record.memory) ~= "table" or type(record.memory.person) ~= "table" then return nil end
    return record
end

function Talk.visitorReply(player, args, uid)
    local engine, id = ProjectALife.VisitorTalk, args.choice
    if engine == nil or type(engine.command) ~= "function" or type(id) ~= "string" or #uid > 160 then return nil end
    local prefix = string.sub(id, 1, 3)
    if prefix ~= "VQ_" and prefix ~= "EV:" and id ~= "VT_TAB" and id ~= "NPC_OPEN" then return nil end
    local target = Talk.visitorTarget(uid)
    if target == nil then return nil end
    local visit = ProjectALife.SafehouseVisit
    if id == "NPC_OPEN" and visit ~= nil and type(visit.doorPeer) == "function" and visit.doorPeer(player, uid) ~= nil then return nil end
    local reply = engine.command(player, args)
    local atDoor = visit ~= nil and type(visit.doorPeer) == "function" and visit.doorPeer(player, uid) ~= nil
    reply.doorPeer = atDoor
    reply.doorChoices = atDoor and type(visit.choices) == "function" and visit.choices(uid, player) or nil
    reply.doorLabels = atDoor and type(visit.doorLabels) == "function" and visit.doorLabels(uid) or nil
    if id == "NPC_OPEN" and reply.ok == true then
        local shell = Talk.shellFor(uid)
        if shell ~= nil then Talk.hold(target, shell, player, nowMs()) end
    end
    if id == "VT_TAB" then
        reply.ok, reply.tabOnly = reply.visitorMenu ~= nil, true
        reply.reason = reply.ok and "tab" or "loading"
    end
    if reply.ok and reply.playerKey ~= nil then
        local state = Talk.state(reply.playerKey, uid, nowMs())
        state.menuOpen, state.sessionId, state.sessionActivityAtMs = true, reply.sessionId, nowMs()
    end
    return reply
end

function Talk.choose(player, args)
    local uid = tostring(args.uid or "")
    local sessionId = type(args.sessionId) == "string" and #args.sessionId > 0 and #args.sessionId <= 160 and args.sessionId or nil
    local result = { uid = uid, ok = false, reason = "unavailable", sessionId = sessionId,
        playerKey = ProjectALife.Speech.playerKey(player) }
    local function finish(reason)
        result.reason = reason
        local engine = ProjectALife.VisitorTalk
        if result.ok == true and result.visitorMenu == nil and engine ~= nil and type(engine.menu) == "function" then
            local person = Talk.visitorTarget(uid)
            if person ~= nil then result.visitorMenu = engine.menu(player, person, { tab = args.tab }) end
        end
        if reason == "not_door_peer" then
            local visitModule = ProjectALife.SafehouseVisit
            result.why = visitModule ~= nil and type(visitModule.peerWhy) == "table" and visitModule.peerWhy[uid] or nil
            local blackBox = ProjectALife.BlackBox
            if blackBox ~= nil and blackBox.enabled and type(blackBox.note) == "function" then
                pcall(blackBox.note, player, "visit-peer-refused", "uid=" .. tostring(uid) .. " why=" .. tostring(result.why))
            end
        end
        if reason == "busy" or reason == "hostile" then
            Talk.session(player, { uid = uid, sessionId = sessionId, close = true })
            result.interrupted = true
        end
        local opinion = ProjectALife.NpcOpinion
        if opinion ~= nil and result.opinion == nil and type(opinion.attach) == "function" then
            pcall(opinion.attach, result, uid, player)
        end
        local party = ProjectALife.Party
        if party ~= nil and type(party.decorate) == "function" then pcall(party.decorate, result, uid, player) end
        local social = ProjectALife.TalkSocial
        local gained = result.sdelta
        result.sdelta = nil
        if social ~= nil and type(social.decorate) == "function" then pcall(social.decorate, result, uid, player, gained) end
        Talk.choiceReply(player, result)
        return result.ok, reason
    end
    if args.sessionId ~= nil and sessionId == nil then return finish("invalid_session") end
    if Talk.settings.enabled ~= true or not ProjectALife.Speech.authoritative() then return finish("disabled") end
    if not alive(player) then return finish("unavailable") end
    local visitorReply = Talk.visitorReply(player, args, uid)
    if visitorReply ~= nil then
        Talk.choiceReply(player, visitorReply)
        return visitorReply.ok, visitorReply.reason
    end
    local choice
    for _, row in ipairs(ProjectALife.TalkIntents.choices) do
        if row.id == args.choice then choice = row; break end
    end
    if choice == nil or #uid > 160 then return finish("invalid_choice") end
    local visit = ProjectALife.SafehouseVisit
    local doorListener = visit ~= nil and visit.doorPeer(player, uid) or nil
    if doorListener == nil and visit ~= nil and type(visit.live) == "function" and visit.live(uid) ~= nil then
        result.doorPeer, result.doorChoices = true, {}
        return finish("not_door_peer")
    end
    if choice.door and doorListener == nil then return finish("not_door_peer") end
    if doorListener ~= nil then
        result.doorPeer, result.doorChoices = true, {}
        if Talk.busy(doorListener.record, nowMs()) or not Talk.talkable(doorListener.shell, doorListener.record) then return finish("busy") end
        result.stance = Talk.stance(doorListener.record, player)
        if result.stance == "hostile" then return finish("hostile") end
        local intent = choice.id
        if intent == "NPC_OPEN" or intent == "GREETING" then intent = "DOOR_WHO" end
        if not visit.handles(intent, doorListener.record) then return finish("door_choice_required") end
        local ok, words = visit.choose(player, uid, intent, args.quote, args.gift)
        result.ok, result.text, result.doorPeer = ok == true, ok and words or nil, true
        result.doorChoices = visit.choices(uid, player)
        result.doorLabels = type(visit.doorLabels) == "function" and visit.doorLabels(uid) or nil
        result.tradeQuote = visit.tradeView(player, uid)
        if result.doorChoices.DOOR_GIVE == true or result.doorChoices.DOOR_TREAT == true then
            local kind = visit.giftKind(select(2, visit.doorPeer(player, uid)))
            result.giftEmpty = #visit.giftEntries(player, kind) == 0
            result.giftEmptyReason = kind == "ASK_MEDS" and "no_safe_meds" or "no_safe_food"
        end
        if result.doorChoices.DOOR_LEND == true then
            result.giftEmpty = #visit.giftEntries(player, "LEND_TOOL") == 0
            result.giftEmptyReason = "no_tool_to_lend"
        end
        if ok and (intent == "DOOR_GIVE" or intent == "DOOR_TREAT" or intent == "DOOR_LEND") and args.gift == nil then
            result.giftPicker = visit.giftView(player, uid)
            if result.giftPicker ~= nil then result.text, result.giftPrompt = nil, words end
        end
        if ok then
            if intent ~= "DOOR_LEAVE" and intent ~= "DOOR_LEAVE_RUDE" and intent ~= "GUEST_LEAVE" then
                Talk.openSession(result.playerKey, uid, sessionId)
                Talk.hold(doorListener.record, doorListener.shell, player, nowMs())
            end
            if intent == "DOOR_SEARCH" then result.searchItems = visit.searchItems(doorListener.record, player) end
            if result.giftPicker == nil then
                result.text = Talk.doorSay(doorListener.record, doorListener.shell, player, intent, words)
                local opinion = ProjectALife.NpcOpinion
                local noted, noteKind, declined = false, nil, false
                if type(visit.doorNote) == "function" then noted, noteKind, declined = visit.doorNote(uid, intent) end
                if declined == true then result.wantDeclined = true end
                if opinion ~= nil and noted then
                    if noteKind ~= nil and type(opinion.note) == "function" then pcall(opinion.note, noteKind, doorListener.record, player) end
                elseif opinion ~= nil and type(opinion.noteDoor) == "function" then
                    pcall(opinion.noteDoor, intent, doorListener.record, player)
                end
            end
        end
        return finish(ok and "door_answered" or words)
    end
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.onChoice) == "function" then
        local handled, reply = standoff.onChoice(player, uid, choice, sessionId)
        if handled and type(reply) == "table" then
            result.ok, result.text, result.pending, result.stance = reply.ok == true, reply.text, reply.pending, reply.stance
            return finish(reply.reason or "standoff")
        end
    end
    local listener
    for _, row in ipairs(Talk.listeners(player, 6)) do
        if tostring(row.record.uid) == uid then listener = row; break end
    end
    if listener == nil then
        Talk.orderRefused(player, uid)
        return finish(Talk.absentReason(player, uid, 6))
    end
    if not Talk.lineOfSight(player, listener.shell) then return finish("blocked") end
    result.stance = Talk.stance(listener.record, player)
    if Talk.busy(listener.record, nowMs()) then return finish("busy") end
    if result.stance == "hostile" then return finish("hostile") end
    if (listener.record.memory or {}).talkHoldPlayerKey ~= ProjectALife.Speech.playerKey(player) then
        Talk.hold(listener.record, listener.shell, player, nowMs())
    end
    if choice.friendly and result.stance ~= "friendly" then return finish("not_friendly") end
    local social = ProjectALife.TalkSocial
    local socialOn = social ~= nil and type(social.gate) == "function" and social.enabled()
    if socialOn and choice.npcAnswer ~= true then
        local okGate, verdict = pcall(social.gate, player, listener, choice, sessionId, "menu")
        if okGate and verdict ~= nil then
            result.sdelta = verdict.delta
            if verdict.stop then
                local playerKey = ProjectALife.Speech.playerKey(player)
                local state = Talk.state(playerKey, uid, nowMs())
                result.ok, result.text = true, verdict.text
                if verdict.close then
                    result.ended = true
                    state.menuOpen, state.sessionId = nil, nil
                    Talk.releaseHold(uid, playerKey)
                else
                    state.menuOpen, state.sessionId, state.sessionActivityAtMs = true, sessionId, nowMs()
                end
                return finish(verdict.reason)
            end
        end
    end
    local personalRep = ProjectALife.PersonalRep
    local npcOpinion = ProjectALife.NpcOpinion
    local walkAsk = choice.id == "WALK_WITH_ME"
    if (not walkAsk or socialOn) and personalRep ~= nil and type(personalRep.talkRefusal) == "function" then
        local refusal = nil
        if not walkAsk then refusal = personalRep.talkRefusal(player, listener.record, choice, result.stance) end
        if refusal == nil and npcOpinion ~= nil and type(npcOpinion.talkRefusal) == "function" then
            refusal = npcOpinion.talkRefusal(player, listener.record, choice)
        end
        if refusal ~= nil then
            ProjectALife.Speech.say(listener.shell, refusal, { face = player })
            result.ok, result.text = true, refusal
            Talk.openSession(result.playerKey, uid, sessionId)
            return finish("answered")
        end
    end
    if choice.id == "WALK_WITH_ME" or choice.id == "WALK_STOP" then
        local ok, text = Talk.walkWith(player, listener, choice.id)
        result.ok, result.text = ok == true, ok and text or nil
        if ok then
            ProjectALife.Speech.say(listener.shell, text, { face = player })
            Talk.openSession(result.playerKey, uid, sessionId)
        end
        return finish(ok and "answered" or text)
    end
    if choice.id == "ASK_HOME" then
        local havens = ProjectALife.Havens
        local answer = { pool = "HOME_NONE", vars = {}, text = "Got no place of my own, not anymore" }
        if havens ~= nil and type(havens.homeAnswer) == "function" then answer = havens.homeAnswer(player, listener.record, result.stance) end
        local text = Talk.homeSay(listener.record, listener.shell, player, answer, result.stance)
        local marker = answer.marker
        result.ok, result.text = true, text
        if marker ~= nil then
            if type(havens.annotate) == "function" then havens.annotate(marker, listener.record, listener.shell) end
            havens.sendMarker(player, marker)
        end
        Talk.openSession(result.playerKey, uid, sessionId)
        return finish("answered")
    end
    if choice.id == "ASK_ABOUT_ME" then
        local personal = ProjectALife.PersonalRep
        local text = personal ~= nil and type(personal.aboutLine) == "function" and personal.aboutLine(player)
            or "Can't say I've heard a thing about you"
        ProjectALife.Speech.say(listener.shell, text, { face = player })
        result.ok, result.text = true, text
        Talk.openSession(result.playerKey, uid, sessionId)
        return finish("answered")
    end
    local state = Talk.state(ProjectALife.Speech.playerKey(player), uid, nowMs())
    if choice.npcAnswer == true and (state.menuOpen ~= true or state.sessionId ~= sessionId) then return finish("no_question") end
    if ProjectALife.TalkQuestions ~= nil then ProjectALife.TalkQuestions.prepare(state, sessionId) end
    if choice.id == "NPC_OPEN" and state.pending ~= nil then return finish("no_question") end
    if choice.answer and not ProjectALife.TalkIntents.answers(choice, state.pending) then return finish("no_question") end
    if choice.id == "NPC_OPEN" and ProjectALife.PersonalRep ~= nil and type(ProjectALife.PersonalRep.recognize) == "function" then
        local okRecognize, line = pcall(ProjectALife.PersonalRep.recognize, player, listener.record, listener.shell)
        if okRecognize and type(line) == "string" then
            ProjectALife.Speech.say(listener.shell, line, { face = player })
            result.ok, result.text = true, line
            Talk.openSession(result.playerKey, uid, sessionId)
            return finish("answered")
        end
    end
    if type(choice.answerTo) == "table" and (state.pending == nil or choice.answerTo[state.pending] ~= true) then
        return finish("no_question")
    end
    local text, reason = Talk.respond(player, listener, choice.words, nowMs(), choice.id)
    result.ok, result.text, result.pending = text ~= nil, text, state.pending
    if result.ok then state.menuOpen = true; state.sessionId = sessionId; state.sessionActivityAtMs = nowMs() end
    local questions = ProjectALife.TalkQuestions
    if result.ok and questions ~= nil and questions.followIntents[choice.id] == true then
        questions.follow(player, listener, state, nowMs())
    end
    if result.ok and choice.id == "FAREWELL" and socialOn then result.ended = true end
    Talk.nameResult(result, uid, player)
    local orders = ProjectALife.TalkOrders
    if orders ~= nil and type(orders.decorate) == "function" then orders.decorate(result, uid, player) end
    return finish(reason)
end

function Talk.session(player, args)
    local uid, now = tostring(args.uid or ""), nowMs()
    if #uid > 160 or not alive(player) or not ProjectALife.Speech.authoritative() then return false end
    local key = ProjectALife.Speech.playerKey(player)
    local state = Talk.states[stateKey(key, uid)]
    if state == nil then return false end
    if state.menuOpen ~= true then return false end
    if state.sessionId ~= args.sessionId then return false end
    if args.close == true then
        state.pending, state.npcQuestionCount, state.npcQuestionSession = nil, nil, nil
        state.menuOpen, state.sessionId = nil, nil
        Talk.writeMemory(uid, function(memory)
            if memory.talkHoldPlayerKey == key then memory.talkHoldUntilMs = nil; memory.talkHoldPlayerKey = nil end
        end)
        return true
    end
    if Talk.settings.enabled ~= true then return false end
    local reason = Talk.absentReason(player, uid, 6)
    local near = false
    for _, listener in ipairs(Talk.listeners(player, 6)) do
        if tostring(listener.record.uid) == uid then
            near = true
            if Talk.busy(listener.record, now) then reason = "busy"
            elseif now - (state.sessionActivityAtMs or state.at or now) >= Talk.idleMs(listener.record) then reason = "session_ended"
            elseif Talk.stance(listener.record, player) == "hostile" then reason = "hostile"
            elseif not Talk.lineOfSight(player, listener.shell, listener.record) then reason = "blocked"
            elseif (listener.record.memory or {}).talkHoldPlayerKey ~= key then reason = "session_ended"
            else
                state.at = now
                Talk.hold(listener.record, listener.shell, player, now)
                return true
            end
            break
        end
    end
    if not near and now - (state.sessionActivityAtMs or state.at or now) < Talk.settings.stateMs
            and Talk.orderOk(player, uid, now) then
        state.at = now
        return true
    end
    Talk.session(player, { uid = uid, sessionId = args.sessionId, close = true })
    Talk.choiceReply(player, { uid = uid, playerKey = key, sessionId = args.sessionId,
        ok = false, reason = reason, interrupted = true })
    return false
end

function Talk.endSession(player, key, uid, reason)
    local state = Talk.states[stateKey(key, uid)]
    if state == nil or state.menuOpen ~= true then return false end
    local sessionId = state.sessionId
    state.pending, state.npcQuestionCount, state.npcQuestionSession = nil, nil, nil
    state.menuOpen, state.sessionId = nil, nil
    pcall(Talk.writeMemory, uid, function(memory)
        if memory.talkHoldPlayerKey == key then memory.talkHoldUntilMs = nil; memory.talkHoldPlayerKey = nil end
    end)
    if player ~= nil then
        Talk.choiceReply(player, { uid = uid, playerKey = key, sessionId = sessionId,
            ok = false, reason = reason, interrupted = true })
    end
    Talk.metrics.aggressionClosed = Talk.metrics.aggressionClosed + 1
    return true
end

function Talk.sessionOpenFor(uid)
    local suffix, now = ":" .. tostring(uid), nowMs()
    for key, state in pairs(Talk.states) do
        if state.menuOpen == true and string.sub(key, -#suffix) == suffix
                and now - (state.at or 0) <= Talk.settings.stateMs then return true end
    end
    return false
end

function Talk.idleMs(record)
    local memory = type(record) == "table" and record.memory or nil
    if type(memory) == "table" and (type(memory.guest) == "table" or type(memory.visit) == "table") then return 600000 end
    return Talk.settings.stateMs
end

function Talk.anySessionOpen()
    for _, state in pairs(Talk.states) do
        if state.menuOpen == true then return true end
    end
    return false
end

function Talk.onAggression(aggressor, victim)
    if not Talk.anySessionOpen() then return false end
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.actorRecord) ~= "function" then return false end
    local record, other = relations.actorRecord(aggressor), victim
    if record == nil then record, other = relations.actorRecord(victim), aggressor end
    if record == nil or other == nil then return false end
    local player, key
    if type(other) == "string" then
        key = other
        local orders = ProjectALife.TalkOrders
        if orders ~= nil and type(orders.playerByKey) == "function" then player = orders.playerByKey(key) end
    elseif type(instanceof) == "function" and instanceof(other, "IsoPlayer") then
        player, key = other, ProjectALife.Speech.playerKey(other)
    end
    if key == nil then return false end
    return Talk.endSession(player, key, tostring(record.uid), "hostile")
end

function Talk.handleClientCommand(module, command, player, args)
    if module ~= "ProjectALife" or player == nil or Talk.commandIntervalMs[command] == nil then return false end
    args = type(args) == "table" and args or {}
    local key = tostring(ProjectALife.Speech.playerKey(player) or "0") .. ":" .. command
    local interval = Talk.commandIntervalMs[command]
    if command == "talkChoose" and args.choice == "VT_TAB" then key, interval = key .. ":tab", 200 end
    local now = nowMs()
    if not (command == "talkSession" and args.close == true)
            and now - (Talk.lastCommandAt[key] or -math.huge) < interval then
        if command == "talkChoose" then Talk.choiceReply(player, { uid = tostring(args.uid or ""),
            playerKey = ProjectALife.Speech.playerKey(player),
            sessionId = type(args.sessionId) == "string" and #args.sessionId <= 160 and args.sessionId or nil,
            ok = false, reason = "rate_limited" }) end
        return false
    end
    Talk.lastCommandAt[key] = now
    if command == "safehouseDoorSync" then
        local visit = ProjectALife.SafehouseVisit
        return visit ~= nil and type(visit.syncDoor) == "function" and visit.syncDoor(player) == true
    elseif command == "talkChoose" then
        return Talk.choose(player, args)
    elseif command == "talkSession" then
        return Talk.session(player, args)
    elseif command == "talkSay" then
        return Talk.onPlayerText(player, tostring(args.text or ""), args.loud == true)
    elseif command == "talkEmote" then
        return Talk.onPlayerEmote(player, tostring(args.emote or ""))
    elseif command == "talkHelped" then
        local px, py = position(player)
        local x, y = tonumber(args.x), tonumber(args.y)
        if px == nil or x == nil or y == nil or (x - px) ^ 2 + (y - py) ^ 2 > 144 then return false end
        return Talk.onHelped(player, x, y) > 0
    elseif command == "talkState" then
        local robbery = ProjectALife.ModuleRobbery

        local watch = ProjectALife.ThreatWatch
        local answered = false
        if watch ~= nil and type(watch.onPlayerState) == "function" then
            answered = watch.onPlayerState(player, { aiming = args.aiming == true }) == true
        end
        local standoff = ProjectALife.Standoff
        if standoff ~= nil and type(standoff.onPlayerState) == "function" then
            answered = standoff.onPlayerState(player, { aiming = args.aiming == true, armed = args.armed == true }) == true
                or answered
        end
        if robbery ~= nil and type(robbery.onPlayerState) == "function" then
            return robbery.onPlayerState(player, { armed = args.armed == true }) == true or answered
        end
        return answered
    end
    return false
end

if type(Events) == "table" and Events.OnClientCommand ~= nil and type(Events.OnClientCommand.Add) == "function" then
    Events.OnClientCommand.Add(Talk.handleClientCommand)
end

return Talk
