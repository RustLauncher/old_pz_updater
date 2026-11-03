require "ProjectALife/Decisions/ALifeEncounterScript"

ProjectALife = ProjectALife or {}

local Standoff = {
    defaults = {
        enabled = true,
        surpriseMs = 3000,
        answerMs = 10000,
        calloutPercent = 100,
        calloutMs = 45000,
        betrayalPercent = 100,
    },
    repeatMs = 12000,
    tickMs = 250,
    scanMs = 1000,
    detectTiles = 30,
    comeOutTiles = 9,
    closeTiles = 5,
    walkAwayTiles = 7,
    flankMs = 9000,
    flankTiles = 6,
    flankReach = 1.5,
    turnMs = 1500,
    betrayTurnMs = 700,
    aimGraceMs = 2000,
    nextAskMs = 2500,
    againHours = 24,
    truceMs = 600000,
    cooldownMs = 300000,
    releaseMs = 3000,
    againMs = 3000,
    leaveMs = 20000,
    leaveTiles = 45,
    postTiles = 9,
    maxActive = 6,
    crewTiles = 40,
    clientWaitMs = 1500,
    staleMs = 120000,
    timerEveryMs = 5000,
    answerReach = 14,
    shoutReach = 25,
    earshot = 30,
    cacheMs = 5000,
    baseTellMs = 3000,
    baseTellMemoryMs = 600000,
    baseHearTiles = 30,
    baseTells = {},
    active = {},
    byPlayer = {},
    byCrew = {},
    crewTruces = {},
    cooldowns = {},
    clientWait = {},
    sequence = 0,
    lastTickAtMs = 0,
    lastScanAtMs = 0,
    adapters = {},
    metrics = { started = 0, surprises = 0, callouts = 0, bases = 0, again = 0, revenge = 0, interrogations = 0,
        asked = 0, answered = 0, silences = 0, walkAways = 0, warningShots = 0, betrayals = 0, exposed = 0,
        turned = 0, fought = 0, parted = 0, left = 0, paid = 0, joined = 0, searched = 0, interrupted = 0,
        relayed = 0, aimWarned = 0, shakedowns = 0, truceBroken = 0 },
}
ProjectALife.Standoff = Standoff

Standoff.profiles = {
    civilian = { callout = 0.5, betray = 0, surpriseAttack = 0, refuse = "left", silence = "left",
        walkAway = "left", conclude = "left", afterCallout = "left", toll = false, join = 0.25,
        questions = { "ENC_ASK_WHO", "ENC_ASK_INTENT", "ENC_DEMAND_LEAVE" } },
    law = { callout = 0.7, betray = 0, surpriseAttack = 0, refuse = "warn", silence = "warn",
        walkAway = "warn", conclude = "parted", afterCallout = "search", afterWarn = "left", toll = false, join = 0.1,
        questions = { "ENC_ASK_WHO", "ENC_ASK_HOWMANY", "ENC_DEMAND_LEAVE" } },
    military = { callout = 0.6, betray = 0, surpriseAttack = 0.1, refuse = "warn", silence = "warn",
        walkAway = "warn", conclude = "parted", afterCallout = "search", afterWarn = "turn", toll = false, join = 0.05,
        questions = { "ENC_ASK_WHO", "ENC_ASK_HOWMANY", "ENC_DEMAND_LEAVE" } },
    outlaw = { callout = 0.45, betray = 0.25, surpriseAttack = 0.15, refuse = "turn", silence = "turn",
        walkAway = "turn", conclude = "parted", afterCallout = "search", toll = true, join = 0.05, shakedown = 0.35,
        questions = { "ENC_ASK_WHO", "ENC_ASK_CARRY", "ENC_DEMAND_TOLL" } },
    rough = { callout = 0.3, betray = 0.35, surpriseAttack = 0.3, refuse = "turn", silence = "turn",
        walkAway = "turn", conclude = "parted", afterCallout = "search", toll = true, join = 0.03, shakedown = 0.5,
        questions = { "ENC_ASK_WHO", "ENC_ASK_CARRY", "ENC_DEMAND_TOLL" } },
}
Standoff.voiceOf = {
    civilian = "civilian", family = "civilian", worker = "civilian", rescue = "civilian",
    law = "law", swat = "military", military = "military", elite = "military",
    outlaw = "outlaw", club = "outlaw", crime = "outlaw",
    raider = "rough", gang = "rough", prison = "rough",
}
Standoff.choiceKinds = {
    ENC_ANS_PASSING = "passing", ENC_ANS_ALONE = "alone", ENC_ANS_GROUP = "group", ENC_ANS_LITTLE = "little",
    ENC_ANS_COMPLY = "comply", ENC_ANS_PAY = "pay", ENC_ANS_LEAVING = "leave", ENC_ANS_REFUSE = "refuse",
    ENC_ANS_FLANKER = "flanker", ENC_ANS_JOIN = "join", YES = "yes", NO = "no",
}
Standoff.intentKinds = {
    YES = "yes", NO = "no", GO_AWAY = "refuse", FAREWELL = "leave", GREETING = "passing",
    JOIN_REQUEST = "join", COME_WITH_ME = "join",
}
Standoff.wordKinds = {
    { "just me", "alone" }, { "by myself", "alone" }, { "take it", "pay" }, { "take what", "pay" },
    { "have it", "pay" }, { "leaving", "leave" }, { "i'll go", "leave" }, { "i'm going", "leave" },
    { "passing", "passing" }, { "nobody", "passing" }, { "put it down", "comply" }, { "it's down", "comply" },
    { "your friend", "flanker" }, { "your buddy", "flanker" }, { "more of us", "group" }, { "not much", "little" },
}
Standoff.yesKinds = { ENC_DEMAND_DROP = "comply", ENC_DEMAND_TOLL = "pay", ENC_DEMAND_LEAVE = "leave" }
Standoff.peaceful = { parted = true, paid = true, joined = true, left = true }
Standoff.timerText = {
    callout = "They are calling you out. Answer or come out",
    base = "Someone is outside your place, calling you out",
    answer = "They want an answer",
}

function Standoff.configure(adapters)
    Standoff.adapters = type(adapters) == "table" and adapters or {}
    Standoff.cached = nil
end

function Standoff.reset()
    Standoff.active, Standoff.byPlayer, Standoff.byCrew = {}, {}, {}
    Standoff.crewTruces = {}
    Standoff.cooldowns, Standoff.clientWait = {}, {}
    Standoff.baseTells = {}
    Standoff.sequence, Standoff.lastTickAtMs, Standoff.lastScanAtMs = 0, 0, 0
    Standoff.cached = nil
    for name in pairs(Standoff.metrics) do Standoff.metrics[name] = 0 end
end

function Standoff.count(name)
    Standoff.metrics[name] = (Standoff.metrics[name] or 0) + 1
end

function Standoff.now()
    if type(Standoff.adapters.nowMs) == "function" then return Standoff.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Standoff.roll(maximum)
    maximum = math.max(1, math.floor(tonumber(maximum) or 1))
    if type(Standoff.adapters.roll) == "function" then return Standoff.adapters.roll(maximum) end
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

function Standoff.chance(share)
    share = tonumber(share) or 0
    if share <= 0 then return false end
    if share >= 1 then return true end
    return Standoff.roll(1000) < math.floor(share * 1000)
end

function Standoff.settings(now)
    now = now or Standoff.now()
    local cached = Standoff.cached
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Standoff.cacheMs then return cached end
    local d = Standoff.defaults
    local value = { atMs = now, enabled = d.enabled, surpriseMs = d.surpriseMs, answerMs = d.answerMs,
        calloutPercent = d.calloutPercent, calloutMs = d.calloutMs, betrayalPercent = d.betrayalPercent }
    local settings = ProjectALife.Settings
    if type(settings) == "table" and type(settings.read) == "function" then
        local ok, current = pcall(settings.read, nil, true)
        if ok and type(current) == "table" then
            if type(current.encounterStandoffs) == "boolean" then value.enabled = current.encounterStandoffs end
            if current.hostileEnabled == false then value.enabled = false end
            local surprise = tonumber(current.encounterSurpriseSeconds)
            if surprise ~= nil then value.surpriseMs = math.floor(surprise * 1000) end
            local answer = tonumber(current.encounterAnswerSeconds)
            if answer ~= nil then value.answerMs = math.floor(answer * 1000) end
            value.calloutPercent = tonumber(current.encounterCalloutPercent) or value.calloutPercent
            local callout = tonumber(current.encounterCalloutSeconds)
            if callout ~= nil then value.calloutMs = math.floor(callout * 1000) end
            value.betrayalPercent = tonumber(current.encounterBetrayalPercent) or value.betrayalPercent
        end
    end
    Standoff.cached = value
    return value
end

function Standoff.authoritative()
    if type(Standoff.adapters.authoritative) == "function" then return Standoff.adapters.authoritative() == true end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.authoritative) == "function" then return speech.authoritative() == true end
    return not (type(isClient) == "function" and isClient() == true)
end

function Standoff.registry()
    return ProjectALife.ActorRegistry
end

function Standoff.read(uid)
    local registry = Standoff.registry()
    if registry == nil then return nil end
    local look = registry.peek or registry.read
    if type(look) ~= "function" then return nil end
    return look(uid)
end

function Standoff.shellFor(uid)
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    return binding ~= nil and binding.shell or nil
end

function Standoff.alive(body)
    if body == nil or type(body.isDead) ~= "function" then return false end
    local ok, dead = pcall(body.isDead, body)
    return ok and dead ~= true
end

function Standoff.xyz(body)
    local knowledge = ProjectALife.Knowledge
    if knowledge ~= nil then return knowledge.xyz(body) end
    if body == nil or type(body.getX) ~= "function" then return nil end
    return body:getX(), body:getY(), body:getZ()
end

function Standoff.distance(a, b)
    local ax, ay = Standoff.xyz(a)
    local bx, by = Standoff.xyz(b)
    if ax == nil or bx == nil then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Standoff.isPlayer(body)
    if body == nil or type(instanceof) ~= "function" then return false end
    local kind = type(body)
    if kind ~= "table" and kind ~= "userdata" then return false end
    return instanceof(body, "IsoPlayer") == true
end

function Standoff.keyOf(player)
    local speech = ProjectALife.Speech
    if player ~= nil and speech ~= nil and type(speech.playerKey) == "function" then return speech.playerKey(player) end
    return nil
end

function Standoff.crewKey(actor)
    local knowledge = ProjectALife.Knowledge
    if knowledge ~= nil then return knowledge.crewKey(actor) end
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
    return tostring(memory.groupId or ("solo:" .. tostring(actor and actor.uid)))
end

function Standoff.worldHours()
    if type(Standoff.adapters.worldHours) == "function" then return tonumber(Standoff.adapters.worldHours()) end
    if type(getGameTime) ~= "function" then return nil end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return nil end
    return tonumber(clock:getWorldAgeHours())
end

function Standoff.voice(record)
    local speech = ProjectALife.Speech
    local register, temperament
    if speech ~= nil and type(speech.contextFor) == "function" then
        local ok, context = pcall(speech.contextFor, record, nil)
        if ok and type(context) == "table" then register, temperament = context.register, context.temperament end
    end
    return Standoff.voiceOf[tostring(register)] or "civilian", temperament
end

function Standoff.profileFor(record)
    local voice, temperament = Standoff.voice(record)
    local base = Standoff.profiles[voice] or Standoff.profiles.civilian
    local profile = {}
    for key, value in pairs(base) do profile[key] = value end
    profile.voice, profile.temperament = voice, temperament
    if temperament == "predator" then
        profile.betray = profile.betray * 1.5
        profile.surpriseAttack = profile.surpriseAttack * 1.5
    elseif temperament == "fresh" then
        profile.surpriseAttack = profile.surpriseAttack * 0.5
        if profile.silence == "turn" then profile.silence = "warn" end
        profile.afterWarn = profile.afterWarn or "turn"
    end
    profile.afterWarn = profile.afterWarn or "turn"
    return profile
end

function Standoff.crewOf(actor, shell)
    local members = { { record = actor, shell = shell, uid = actor.uid } }
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local registry = Standoff.registry()
    if registry == nil or type(registry.each) ~= "function" or (memory.groupId == nil and memory.outpostId == nil) then
        return members
    end
    registry.each(function(record)
        local m = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
        if m == nil or record.uid == actor.uid or record.lifecycle ~= "active" then return end
        if not ((memory.groupId ~= nil and m.groupId == memory.groupId)
                or (memory.outpostId ~= nil and m.outpostId == memory.outpostId)) then return end
        local other = Standoff.shellFor(record.uid)
        if other == nil or not Standoff.alive(other) or Standoff.distance(other, shell) > Standoff.crewTiles then return end
        members[#members + 1] = { record = record, shell = other, uid = record.uid }
    end)
    return members
end

function Standoff.previous(memory, key, now)
    local outcomes = type(memory) == "table" and memory.standoffOutcomes or nil
    local seen = type(outcomes) == "table" and key ~= nil and outcomes[key] or nil
    if type(seen) ~= "table" then return nil end
    local hours = Standoff.worldHours()
    if hours ~= nil and tonumber(seen.h) ~= nil and hours - seen.h > Standoff.againHours then return nil end
    return seen.o
end

function Standoff.inVehicle(player)
    local ok, vehicle = pcall(function() return player:getVehicle() end)
    return ok and vehicle ~= nil
end

function Standoff.fighting(members)
    for _, member in ipairs(members) do
        if type(member.record) == "table" and member.record.activity == "combat" then return true end
    end
    return false
end

function Standoff.kos(actor, hook, player, now)
    local warning = ProjectALife.ModuleWarning
    return warning ~= nil and type(warning.kos) == "function" and warning.kos(actor, hook, player, now) == true
end

function Standoff.waitMs(now)
    local script = ProjectALife.EncounterScript
    local answer = Standoff.settings(now).answerMs
    if script == nil then return answer end
    return script.waitMs(answer)
end

function Standoff.overdue(s, now)
    local phase = s.phase
    if phase ~= "interrogate" then return false end
    local warning = ProjectALife.ModuleWarning
    if warning == nil or type(warning.expired) ~= "function" then return false end
    local progress = math.max(tonumber(s.answeredAtMs) or 0, tonumber(s.pendingAtMs) or 0, tonumber(s.stepAtMs) or 0)
    if warning.expired(s.holdSinceMs, progress, now) ~= true then return false end
    if type(warning.timedOut) == "function" then warning.timedOut("standoff") end
    return true
end

function Standoff.expire(s, now)
    s.answeredAtMs = now
    return Standoff.react(s, s.profile.silence, now)
end

function Standoff.given(kind)
    local warning = ProjectALife.ModuleWarning
    if warning ~= nil and type(warning.given) == "function" then warning.given(kind) end
end

function Standoff.eligible(actor, shell, player, key, now)
    if not Standoff.settings(now).enabled then return false, "off" end
    if key == nil or not Standoff.isPlayer(player) or not Standoff.alive(player) then return false, "not_player" end
    if Standoff.kos(actor, "standoff", player, now) then return false, "kos" end
    if Standoff.byPlayer[key] ~= nil then return false, "player_busy" end
    local crew = Standoff.crewKey(actor)
    if Standoff.byCrew[crew] ~= nil then return false, "crew_busy" end
    if now < (Standoff.cooldowns[crew .. "|" .. key] or -1e12) then return false, "cooldown" end
    local robbery = ProjectALife.ModuleRobbery
    if robbery ~= nil and type(robbery.byPlayer) == "table" and robbery.byPlayer[key] ~= nil then return false, "robbery" end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.robbery) == "table" then return false, "robbing" end
    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[key] == true then return false, "grudge" end
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.underAttack) == "function" and fair.underAttack(actor, player, now) then return false, "attacked" end
    if Standoff.inVehicle(player) then return false, "vehicle" end
    if Standoff.previous(memory, key, now) == "fought" then return false, "fought" end
    local count = 0
    for _ in pairs(Standoff.active) do count = count + 1 end
    if count >= Standoff.maxActive then return false, "full" end
    return true, nil
end

function Standoff.kindFor(actor, key, requested)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if requested == "surprise" and memory.revengeKey ~= nil and tostring(memory.revengeKey) == tostring(key) then
        return "revenge"
    end
    if requested == "surprise" and Standoff.peaceful[Standoff.previous(memory, key) or ""] then return "again" end
    return requested
end

function Standoff.start(actor, shell, player, requested, extra, now)
    local key = Standoff.keyOf(player)
    local ok, reason = Standoff.eligible(actor, shell, player, key, now)
    if not ok then return nil, reason end
    local members = Standoff.crewOf(actor, shell)
    if Standoff.fighting(members) then return nil, "fighting" end
    local kind = Standoff.kindFor(actor, key, requested)
    Standoff.sequence = Standoff.sequence + 1
    local px, py, pz = Standoff.xyz(player)
    local s = { id = "standoff:" .. tostring(Standoff.sequence), kind = kind, crewKey = Standoff.crewKey(actor),
        player = player, playerKey = key, members = {}, roles = {}, posts = {}, leaderUid = actor.uid,
        phase = kind, phaseAtMs = now, startedAtMs = now, holdSinceMs = now, anchorX = px, anchorY = py, anchorZ = pz,
        profile = Standoff.profileFor(actor), queue = {}, answered = 0, silences = 0, walked = 0, calls = 0,
        lastBroadcastAtMs = 0 }
    for _, member in ipairs(members) do
        s.members[#s.members + 1] = member.uid
        s.roles[member.uid] = member.uid == actor.uid and "leader" or "member"
    end
    if type(extra) == "table" then
        s.point, s.buildingKey, s.building = extra.point, extra.buildingKey, extra.building
    end
    Standoff.active[s.id] = s
    Standoff.byPlayer[key] = s.id
    Standoff.byCrew[s.crewKey] = s.id
    Standoff.count("started")
    Standoff.given("standoff")
    Standoff.opening(s, now)
    return s
end

function Standoff.opening(s, now)
    local kind = s.kind
    if kind == "callout" or kind == "base" then
        Standoff.count(kind == "base" and "bases" or "callouts")
        s.untilMs = now + Standoff.settings(now).calloutMs
        s.nextCallAtMs = now + Standoff.repeatMs
        Standoff.calloutPosts(s)
        Standoff.broadcast(s)
        Standoff.say(s, s.leaderUid, kind == "base" and "ENC_BASE_CALLOUT" or "ENC_CALLOUT")
        s.calls = 1
        Standoff.timer(s, s.untilMs - now, kind)
        return
    end
    if kind == "again" then
        Standoff.count("again")
        Standoff.broadcast(s)
        Standoff.say(s, s.leaderUid, "ENC_AGAIN")
        return
    end
    if kind == "revenge" then Standoff.count("revenge") else Standoff.count("surprises") end
    s.untilMs = now + Standoff.settings(now).surpriseMs
    Standoff.broadcast(s)
    Standoff.say(s, s.leaderUid, kind == "revenge" and "ENC_REVENGE" or "ENC_SURPRISE")
end

function Standoff.bearing(ax, ay, bx, by)
    if type(math.atan2) == "function" then return math.atan2(by - ay, bx - ax) end
    return math.atan(by - ay, bx - ax)
end

function Standoff.calloutPosts(s)
    local point = s.point
    if type(point) ~= "table" then return end
    local cx, cy, n = 0, 0, 0
    for _, uid in ipairs(s.members) do
        local x, y = Standoff.xyz(Standoff.shellFor(uid))
        if x ~= nil then cx, cy, n = cx + x, cy + y, n + 1 end
    end
    if n == 0 then return end
    cx, cy = cx / n, cy / n
    local heading = Standoff.bearing(point.x, point.y, cx, cy)
    local knowledge = ProjectALife.Knowledge
    for index, uid in ipairs(s.members) do
        local angle = heading + (index - (#s.members + 1) / 2) * 0.45
        local radius = Standoff.postTiles
        local x, y = point.x + math.cos(angle) * radius, point.y + math.sin(angle) * radius
        if knowledge ~= nil and knowledge.buildingAt(x, y, point.z) ~= nil then
            radius = radius + 4
            x, y = point.x + math.cos(angle) * radius, point.y + math.sin(angle) * radius
        end
        s.posts[uid] = { x = x, y = y }
    end
end

function Standoff.broadcast(s, extra)
    local px, py, pz = Standoff.xyz(s.player)
    local now = Standoff.now()
    for _, uid in ipairs(s.members) do
        local post = s.posts[uid]
        local fields = { id = s.id, playerKey = s.playerKey, phase = s.phase, kind = s.kind, role = s.roles[uid],
            atMs = now, px = px, py = py, pz = pz,
            postX = post and post.x or nil, postY = post and post.y or nil,
            fx = s.point and s.point.x or px, fy = s.point and s.point.y or py }
        if s.flankerUid == uid and s.flankPost ~= nil then fields.flankX, fields.flankY = s.flankPost.x, s.flankPost.y end
        if type(extra) == "table" then for key, value in pairs(extra) do fields[key] = value end end
        if type(s.leave) == "table" and s.leave[uid] ~= nil then
            fields.leaveX, fields.leaveY = s.leave[uid].x, s.leave[uid].y
        end
        Standoff.writeMember(uid, function(memory) memory.standoff = fields end)
    end
    s.lastBroadcastAtMs = now
end

function Standoff.writeMember(uid, mutate)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.writeMemory) == "function" then return talk.writeMemory(uid, mutate) end
    local record = Standoff.read(uid)
    if record == nil then return false end
    record.memory = type(record.memory) == "table" and record.memory or {}
    mutate(record.memory)
    return true
end

function Standoff.say(s, uid, event)
    if type(Standoff.adapters.say) == "function" then return Standoff.adapters.say(s, uid, event) end
    local record, shell = Standoff.read(uid), Standoff.shellFor(uid)
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    if record == nil or shell == nil or talk == nil or speech == nil or type(talk.bark) ~= "function" then return nil end
    local data = ProjectALife.DialogueData
    if data ~= nil and type(data.load) == "function" then data.load() end
    local context = speech.contextFor(record, s.player)
    local script = ProjectALife.EncounterScript
    local ok, said, drawn
    if script ~= nil then
        ok, said, drawn = pcall(script.say, s, record, shell, s.player, event, context)
    else
        ok, said = pcall(talk.bark, record, shell, s.player, event, context)
        drawn = true
    end
    if ok and said ~= nil then
        s.lastLine = said
        if drawn ~= false then Standoff.relay(s, said) end
        if talk ~= nil and type(talk.issueOrder) == "function" then
            pcall(talk.issueOrder, s.player, uid, "standoff", Standoff.orderTtl(s, Standoff.now()))
        end
    end
    return ok and said or nil
end

function Standoff.relay(s, text)
    local player = s.player
    if player == nil or type(text) ~= "string" then return end
    local leader = Standoff.shellFor(s.leaderUid)
    if Standoff.distance(leader, player) <= 12 then return end
    pcall(function()
        if type(player.isLocalPlayer) == "function" and player:isLocalPlayer() ~= true then return end
        if type(player.setHaloNote) == "function" then player:setHaloNote(text, 255, 200, 120, 300) end
    end)
end

function Standoff.timer(s, ms, kind)
    local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
    if Standoff.distance(s.player, s.point or Standoff.shellFor(s.leaderUid)) > Standoff.earshot then return false end
    local text = Standoff.timerText[kind] or Standoff.timerText.answer
    if type(Standoff.adapters.timer) == "function" then return Standoff.adapters.timer(s.player, seconds, text) end
    if type(isServer) == "function" and isServer() and type(sendServerCommand) == "function" then
        pcall(sendServerCommand, s.player, "ProjectALife", "standoffTimer", { seconds = seconds, text = text })
        return true
    end
    local input = ProjectALife.TalkInput
    if input ~= nil and type(input.showTimer) == "function" then
        pcall(input.showTimer, seconds, text)
        return true
    end
    return false
end

function Standoff.notify(playerKey, text)
    if type(text) ~= "string" or text == "" then return false end
    if type(Standoff.adapters.notify) == "function" then return Standoff.adapters.notify(playerKey, text) == true end
    local presence = ProjectALife.ModuleTalkPresence
    local players = presence ~= nil and type(presence.players) == "function" and presence.players() or {}
    for _, player in ipairs(players) do
        if Standoff.keyOf(player) == playerKey then
            if type(isServer) == "function" and isServer() and type(sendServerCommand) == "function" then
                pcall(sendServerCommand, player, "ProjectALife", "standoffNotice", { text = text })
                return true
            end
            local input = ProjectALife.TalkInput
            if input ~= nil and type(input.showNotice) == "function" then return pcall(input.showNotice, text) == true end
            return false
        end
    end
    return false
end

function Standoff.pointOf(object, shell)
    local square
    if object ~= nil and type(object.getSquare) == "function" then
        local ok, value = pcall(object.getSquare, object)
        if ok then square = value end
    end
    local x, y, z = Standoff.xyz(square)
    if x == nil then x, y, z = Standoff.xyz(shell) end
    if x == nil then return nil end
    return { x = x, y = y, z = z or 0 }
end

function Standoff.nearestPlayer(point, reach)
    local presence = ProjectALife.ModuleTalkPresence
    local players = presence ~= nil and type(presence.players) == "function" and presence.players() or {}
    local best, bestDistance = nil, reach
    for _, player in ipairs(players) do
        local distance = Standoff.distance(player, point)
        if Standoff.alive(player) and distance <= bestDistance then best, bestDistance = player, distance end
    end
    return best
end

function Standoff.baseTold(actor, key, now)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[key] == true then return true end
    if type(memory.searchOrder) == "table" then return true end
    local outcomes = type(memory.standoffOutcomes) == "table" and memory.standoffOutcomes[key] or nil
    if type(outcomes) == "table" and outcomes.o == "ignored"
            and now - (tonumber(outcomes.ms) or -1e12) <= Standoff.baseTellMemoryMs then
        return true
    end
    local tell = Standoff.baseTells[Standoff.crewKey(actor) .. "|" .. tostring(key)]
    return tell ~= nil and now >= tell.readyAtMs and now - tell.readyAtMs <= Standoff.baseTellMemoryMs
end

function Standoff.allowBoundaryEntry(shell, object, actor, now)
    if type(actor) ~= "table" or actor.uid == nil then return true end
    now = tonumber(now) or Standoff.now()
    local point = Standoff.pointOf(object, shell)
    if point == nil then return true end
    local player = Standoff.nearestPlayer(point, Standoff.baseHearTiles)
    if player == nil then return true end
    if Standoff.holdsFor(actor.memory, Standoff.keyOf(player), now) then return false end
    if Standoff.kos(actor, "boundary", player, now) then return true end
    local relations = ProjectALife.Relations
    if relations == nil or type(relations.hostileToPlayer) ~= "function" or relations.hostileToPlayer(actor, player) ~= true then
        return true
    end
    local key = Standoff.keyOf(player)
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.underAttack) == "function" and fair.underAttack(actor, player, now) then return true end
    if Standoff.baseTold(actor, key, now) then return true end
    local id = Standoff.crewKey(actor) .. "|" .. tostring(key)
    local tell = Standoff.baseTells[id]
    if tell ~= nil and now < tell.readyAtMs then return false end
    Standoff.count("baseKnocks")
    local knowledge = ProjectALife.Knowledge
    local building = knowledge ~= nil and knowledge.buildingAt(point.x, point.y, point.z) or nil
    if Standoff.settings(now).enabled and Standoff.requestCallout(actor, shell, player, point, building, now) then
        Standoff.baseTells[id] = { readyAtMs = now + Standoff.settings(now).calloutMs }
        return false
    end
    Standoff.baseTells[id] = { readyAtMs = now + Standoff.baseTellMs }
    if fair ~= nil and type(fair.shout) == "function" then pcall(fair.shout, actor, shell, player, "ENC_BASE_CALLOUT") end
    return false
end

function Standoff.consider(actor, shell, player, now)
    if type(actor) ~= "table" or not Standoff.isPlayer(player) then return false end
    now = tonumber(now) or Standoff.now()
    if Standoff.kos(actor, "consider", player, now) then return false end
    local key = Standoff.keyOf(player)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if Standoff.holdsFor(memory, key, now) then return true end
    if not Standoff.authoritative() then
        return Standoff.awaitServer(actor, player, key, now, "STANDOFF_SURPRISE")
    end
    local live = Standoff.liveFor(actor, key)
    if live ~= nil then return Standoff.enroll(live, actor, shell, now) end
    local pair = Standoff.crewKey(actor) .. "|" .. tostring(key)
    local truce = Standoff.crewTruces[pair]
    if truce ~= nil and Standoff.grudged(memory, key) then
        Standoff.crewTruces[pair] = nil
        truce = nil
    end
    if truce ~= nil and now < truce then
        Standoff.writeMember(actor.uid, function(mem)
            mem.standoffTruce = type(mem.standoffTruce) == "table" and mem.standoffTruce or {}
            mem.standoffTruce[key] = truce
        end)
        return true
    end
    local s = Standoff.start(actor, shell, player, "surprise", nil, now)
    return s ~= nil
end

function Standoff.liveFor(actor, key)
    local id = Standoff.byCrew[Standoff.crewKey(actor)]
    local s = id ~= nil and Standoff.active[id] or nil
    if s == nil or s.phase == "done" or s.playerKey ~= key then return nil end
    return s
end

function Standoff.enroll(s, actor, shell, now)
    for _, uid in ipairs(s.members) do
        if uid == actor.uid then return true end
    end
    s.members[#s.members + 1] = actor.uid
    s.roles[actor.uid] = "member"
    Standoff.count("enrolled")
    Standoff.broadcast(s)
    local px, py = Standoff.xyz(s.player)
    local script = ProjectALife.EncounterScript
    if script ~= nil and script.enabled() and px ~= nil then script.cover(shell, px, py, now) end
    return true
end

function Standoff.awaitServer(actor, player, key, now, event, point)
    if not Standoff.settings(now).enabled or key == nil then return false end
    local wait = Standoff.clientWait[actor.uid]
    if wait == nil or wait.key ~= key or now - wait.atMs > Standoff.cooldownMs then
        local size = 0
        for uid, entry in pairs(Standoff.clientWait) do
            if now - entry.atMs > Standoff.cooldownMs then Standoff.clientWait[uid] = nil else size = size + 1 end
        end
        if size >= 256 then return false end
        wait = { key = key, atMs = now }
        Standoff.clientWait[actor.uid] = wait
        local executor = ProjectALife.Executor
        if executor ~= nil and type(executor.relayTell) == "function" then
            if executor.relayTell(actor, player, event, point) == true then Standoff.count("relayed") end
        end
    end
    return now - wait.atMs < Standoff.clientWaitMs
end

function Standoff.wantsCallout(actor, shell, point, building, now)
    if not Standoff.settings(now).enabled or type(point) ~= "table" then return false end
    if Standoff.kos(actor, "callout", nil, now) then return false end
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.inPlayerBase) == "function" then
        local ok, inside = pcall(policy.inPlayerBase, point.x, point.y)
        if ok and inside == true then return true end
    end
    local profile = Standoff.profileFor(actor)
    return Standoff.chance(profile.callout * Standoff.settings(now).calloutPercent / 100)
end

function Standoff.requestCallout(actor, shell, target, point, building, now)
    if not Standoff.isPlayer(target) then return false end
    local key = Standoff.keyOf(target)
    if not Standoff.authoritative() then
        return Standoff.awaitServer(actor, target, key, now, "STANDOFF_CALLOUT", point)
    end
    local kind = "callout"
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.inPlayerBase) == "function" then
        local ok, inside = pcall(policy.inPlayerBase, point.x, point.y)
        if ok and inside == true then kind = "base" end
    end
    local knowledge = ProjectALife.Knowledge
    local s = Standoff.start(actor, shell, target, kind, { point = point, building = building,
        buildingKey = knowledge ~= nil and knowledge.buildingKey(building) or nil }, now)
    return s ~= nil
end

function Standoff.onRelay(record, shell, player, event, message)
    if not Standoff.authoritative() or type(record) ~= "table" then return false end
    local now = Standoff.now()
    if event == "STANDOFF_SURPRISE" then
        return Standoff.start(record, shell, player, "surprise", nil, now) ~= nil
    end
    if event == "STANDOFF_CALLOUT" and type(message) == "table" and tonumber(message.x) ~= nil then
        local knowledge = ProjectALife.Knowledge
        local point = { x = tonumber(message.x), y = tonumber(message.y), z = tonumber(message.z) or 0 }
        local building = knowledge ~= nil and knowledge.buildingAt(point.x, point.y, point.z) or nil
        return Standoff.requestCallout(record, shell, player, point, building, now)
    end
    return false
end

function Standoff.grudged(memory, key)
    local grudges = type(memory) == "table" and memory.hostileToPlayerKeys or nil
    return type(grudges) == "table" and key ~= nil and grudges[key] == true
end

function Standoff.truced(record, player)
    if type(record) ~= "table" or player == nil then return false end
    return Standoff.holdsFor(record.memory, Standoff.keyOf(player)) == true
end

function Standoff.breakTruce(actor, key, now)
    if type(actor) ~= "table" or key == nil then return 0 end
    key = tostring(key)
    now = tonumber(now) or Standoff.now()
    local crew = Standoff.crewKey(actor)
    local pair = crew .. "|" .. key
    local own = type(actor.memory) == "table" and type(actor.memory.standoffTruce) == "table"
        and actor.memory.standoffTruce[key] ~= nil
    if Standoff.crewTruces[pair] == nil and not own then return 0 end
    Standoff.crewTruces[pair] = nil
    local uids, seen = {}, {}
    if actor.uid ~= nil then
        uids[1] = actor.uid
        seen[actor.uid] = true
    end
    local registry = Standoff.registry()
    if registry ~= nil and type(registry.each) == "function" then
        registry.each(function(record)
            if type(record) == "table" and not seen[record.uid] and Standoff.crewKey(record) == crew then
                seen[record.uid] = true
                uids[#uids + 1] = record.uid
            end
        end)
    end
    local hours = Standoff.worldHours()
    for _, uid in ipairs(uids) do
        Standoff.writeMember(uid, function(memory)
            if type(memory.standoffTruce) == "table" then memory.standoffTruce[key] = nil end
            memory.standoffOutcomes = type(memory.standoffOutcomes) == "table" and memory.standoffOutcomes or {}
            memory.standoffOutcomes[key] = { o = "fought", h = hours, ms = now }
        end)
    end
    Standoff.count("truceBroken")
    return #uids
end

function Standoff.holdsFor(memory, key, now)
    if type(memory) ~= "table" or key == nil then return false end
    now = tonumber(now) or Standoff.now()
    local truce = memory.standoffTruce
    if type(truce) == "table" and now < (tonumber(truce[key]) or -1e12) and not Standoff.grudged(memory, key) then return true end
    local held = memory.standoff
    if type(held) ~= "table" or held.playerKey ~= key then return false end
    if Standoff.authoritative() then
        local live = Standoff.active[held.id]
        if live == nil then return false end
        return live.phase ~= "done"
    end
    return math.abs(now - (tonumber(held.atMs) or -1e12)) <= Standoff.staleMs
end

function Standoff.talking(record, player)
    if type(record) ~= "table" or player == nil then return false end
    local key = Standoff.keyOf(player)
    local id = key ~= nil and Standoff.byPlayer[key] or nil
    local s = id ~= nil and Standoff.active[id] or nil
    return s ~= nil and s.roles[record.uid] ~= nil
end

function Standoff.tick(now)
    now = now or Standoff.now()
    if not Standoff.authoritative() then return 0 end
    if now - Standoff.lastTickAtMs < Standoff.tickMs and now >= Standoff.lastTickAtMs then return 0 end
    Standoff.lastTickAtMs = now
    local processed = 0
    for _, s in pairs(Standoff.active) do
        local ok, failure = pcall(Standoff.advance, s, now)
        if not ok then Standoff.finish(s, "error:" .. tostring(failure), now) end
        processed = processed + 1
    end
    if now - Standoff.lastScanAtMs >= Standoff.scanMs or now < Standoff.lastScanAtMs then
        Standoff.lastScanAtMs = now
        processed = processed + Standoff.scan(now)
    end
    return processed
end

function Standoff.scan(now)
    if not Standoff.settings(now).enabled then return 0 end
    local robbery, careful = ProjectALife.ModuleRobbery, ProjectALife.ModuleCareful
    local relations = ProjectALife.Relations
    local presence = ProjectALife.ModuleTalkPresence
    if robbery == nil or type(robbery.crewsNear) ~= "function" or relations == nil then return 0 end
    local players = presence ~= nil and type(presence.players) == "function" and presence.players() or {}
    local started = 0
    for _, player in ipairs(players) do
        local key = Standoff.keyOf(player)
        if key ~= nil and Standoff.byPlayer[key] == nil and Standoff.alive(player) then
            for _, crew in pairs(robbery.crewsNear(player)) do
                local spotter = Standoff.spotter(crew, player, careful, relations)
                if spotter ~= nil and Standoff.start(spotter.record, spotter.shell, player, "surprise", nil, now) ~= nil then
                    started = started + 1
                    break
                end
            end
        end
    end
    return started
end

function Standoff.spotter(crew, player, careful, relations)
    for _, member in ipairs(crew.members or {}) do
        if member.distance <= Standoff.detectTiles and member.record.activity ~= "combat"
                and relations.hostileToPlayer(member.record, player) == true
                and (careful == nil or type(careful.lineOfSight) ~= "function"
                    or careful.lineOfSight(member.shell, player) == true) then
            return member
        end
    end
    return nil
end

function Standoff.living(s)
    local living = {}
    for _, uid in ipairs(s.members) do
        local record, shell = Standoff.read(uid), Standoff.shellFor(uid)
        if record ~= nil and record.lifecycle == "active" and Standoff.alive(shell) then living[#living + 1] = uid end
    end
    return living
end

function Standoff.attacked(s, now)
    local fair = ProjectALife.Fairness
    if fair == nil or type(fair.underAttack) ~= "function" then return false end
    for _, uid in ipairs(s.members) do
        local record = Standoff.read(uid)
        if record ~= nil and fair.underAttack(record, s.player, now) then return true end
    end
    return false
end

function Standoff.aimed(s, now)
    if now - (tonumber(s.aimReportAtMs) or -1e12) <= 1500 then return true end
    local player = s.player
    local ok, aiming = pcall(function() return player:isAiming() == true end)
    if not ok or not aiming then return false end
    local watch = ProjectALife.ThreatWatch
    local readable, armed = pcall(function()
        local weapon = player:getPrimaryHandItem()
        return weapon ~= nil and type(weapon.isRanged) == "function" and weapon:isRanged() == true
    end)
    if not readable or armed ~= true then return false end
    if watch == nil or type(watch.aimedAt) ~= "function" then return true end
    for _, uid in ipairs(s.members) do
        local shell = Standoff.shellFor(uid)
        local hit, answer = pcall(watch.aimedAt, player, shell, 16, 6, 0)
        if hit and answer then return true end
    end
    return false
end

function Standoff.playerArmed(player)
    local armed = false
    pcall(function()
        for _, item in pairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
            if item ~= nil and instanceof(item, "HandWeapon") and tostring(item:getFullType()) ~= "Base.BareHands" then
                armed = true
            end
        end
    end)
    return armed
end

function Standoff.advance(s, now)
    if s.phase == "done" then return end
    if not Standoff.alive(s.player) then return Standoff.finish(s, "player_gone", now) end
    local living = Standoff.living(s)
    if #living == 0 then return Standoff.finish(s, "crew_gone", now) end
    s.members = living
    if Standoff.read(s.leaderUid) == nil or not Standoff.alive(Standoff.shellFor(s.leaderUid)) then
        s.leaderUid = living[1]
        s.roles[living[1]] = "leader"
    end
    if Standoff.attacked(s, now) then return Standoff.fight(s, now, "attacked") end
    if Standoff.overdue(s, now) then return Standoff.expire(s, now) end
    if s.handsUpAtMs ~= nil and not s.handsUpArmed and Standoff.playerArmed(s.player) then
        s.handsUpAtMs = nil
        Standoff.count("brokenSurrender")
        return Standoff.turn(s, now, false, true)
    end
    for _, uid in ipairs(living) do
        local record = Standoff.read(uid)
        if record ~= nil and record.activity == "combat" and record.memory ~= nil
                and record.memory.combatTargetKind ~= "player" then
            Standoff.count("interrupted")
            return Standoff.finish(s, "interrupted", now)
        end
    end
    local phase = s.phase
    if phase == "turning" then return Standoff.turnStep(s, now) end
    if phase == "release" or phase == "leave" then
        if now >= (tonumber(s.releaseUntilMs) or 0) then return Standoff.finish(s, s.outcome or "released", now) end
        return Standoff.keepBroadcast(s, now)
    end
    if phase ~= "callout" and phase ~= "base" and Standoff.aimStep(s, now) then return end
    if phase == "surprise" or phase == "revenge" then return Standoff.surpriseStep(s, now) end
    if phase == "again" then
        if now - s.phaseAtMs >= Standoff.againMs then return Standoff.outcome(s, "parted", now, true) end
        return Standoff.keepBroadcast(s, now)
    end
    if phase == "callout" or phase == "base" then return Standoff.calloutStep(s, now) end
    if phase == "interrogate" then return Standoff.interrogateStep(s, now) end
end

function Standoff.keepBroadcast(s, now)
    if now - (s.lastBroadcastAtMs or 0) >= 1000 then Standoff.broadcast(s) end
end

function Standoff.aimStep(s, now)
    if not Standoff.aimed(s, now) then
        s.aimSinceMs = nil
        return false
    end
    if s.flanking == true then
        Standoff.count("exposed")
        Standoff.say(s, s.leaderUid, "ENC_CAUGHT")
        Standoff.outcome(s, "left", now, true)
        return true
    end
    if s.aimSinceMs == nil then
        s.aimSinceMs = now
        Standoff.count("aimWarned")
        Standoff.say(s, s.leaderUid, "ENC_DEMAND_DROP")
        return false
    end
    if now - s.aimSinceMs >= Standoff.aimGraceMs then
        Standoff.turn(s, now, false, true)
        return true
    end
    return false
end

function Standoff.surpriseStep(s, now)
    if now < (s.untilMs or now) then return Standoff.keepBroadcast(s, now) end
    if s.phase == "revenge" or Standoff.chance(s.profile.surpriseAttack) then
        return Standoff.turn(s, now, false, false)
    end
    return Standoff.beginInterrogation(s, now)
end

function Standoff.beginInterrogation(s, now)
    Standoff.count("interrogations")
    s.holdSinceMs = now
    s.phase, s.phaseAtMs = "interrogate", now
    s.anchorX, s.anchorY = Standoff.xyz(s.player)
    s.queue = {}
    if Standoff.playerArmed(s.player) then s.queue[1] = "ENC_DEMAND_DROP" end
    for _, question in ipairs(s.profile.questions) do s.queue[#s.queue + 1] = question end
    s.nextAskAtMs = now
    if #s.members >= 2 and not s.bluffed
            and Standoff.chance(s.profile.betray * Standoff.settings(now).betrayalPercent / 100) then
        s.betray = true
    end
    Standoff.broadcast(s)
end

function Standoff.calloutStep(s, now)
    local player = s.player
    if Standoff.cameOut(s) then
        Standoff.say(s, s.leaderUid, "ENC_CAME_OUT")
        return Standoff.beginInterrogation(s, now)
    end
    if now >= (s.untilMs or now) then
        local next = s.profile.afterCallout
        if next == "search" then return Standoff.orderSearch(s, now) end
        return Standoff.outcome(s, "left", now, false)
    end
    if now >= (s.nextCallAtMs or now) then
        s.calls = s.calls + 1
        s.nextCallAtMs = now + Standoff.repeatMs
        if s.calls >= 3 and not s.warned then
            Standoff.warningShot(s, now)
        else
            Standoff.say(s, s.leaderUid, "ENC_CALLOUT_REPEAT")
        end
        Standoff.timer(s, s.untilMs - now, s.kind)
    end
    return Standoff.keepBroadcast(s, now)
end

function Standoff.cameOut(s)
    local knowledge = ProjectALife.Knowledge
    if knowledge == nil then return false end
    local inside = knowledge.shellBuilding(s.player)
    if inside ~= nil and s.buildingKey ~= nil and knowledge.buildingKey(inside) == s.buildingKey then return false end
    for _, uid in ipairs(s.members) do
        if Standoff.distance(Standoff.shellFor(uid), s.player) <= Standoff.comeOutTiles then return true end
    end
    return false
end

function Standoff.orderSearch(s, now)
    Standoff.count("searched")
    local point = s.point or { x = s.anchorX, y = s.anchorY, z = s.anchorZ }
    local order = { x = point.x, y = point.y, z = point.z or 0, untilMs = now + 30000, key = s.playerKey }
    for _, uid in ipairs(s.members) do
        Standoff.writeMember(uid, function(memory)
            memory.searchOrder = order
            memory.standoffOutcomes = type(memory.standoffOutcomes) == "table" and memory.standoffOutcomes or {}
            memory.standoffOutcomes[s.playerKey] = { o = "ignored", h = Standoff.worldHours(), ms = now }
        end)
    end
    s.outcome = "searched"
    return Standoff.finish(s, "searched", now)
end

function Standoff.warningShot(s, now)
    s.warned = true
    Standoff.count("warningShots")
    Standoff.say(s, s.leaderUid, "ENC_WARNING_SHOT")
    if type(Standoff.adapters.shot) == "function" then return Standoff.adapters.shot(s) end
    for _, uid in ipairs(s.members) do
        local shell = Standoff.shellFor(uid)
        local fired = false
        pcall(function()
            local weapon = shell:getPrimaryHandItem()
            if weapon == nil or weapon:isRanged() ~= true then return end
            local sound = weapon:getSwingSound()
            if sound ~= nil and sound ~= "" then
                if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
                    sendPlaySound(sound, false, shell)
                else
                    shell:getEmitter():playSound(sound)
                end
            end
            if type(addSound) == "function" then
                addSound(shell, math.floor(shell:getX()), math.floor(shell:getY()), math.floor(shell:getZ()), 60, 60)
            end
            fired = true
        end)
        if fired then return true end
    end
    return false
end

function Standoff.interrogateStep(s, now)
    if Standoff.walkAwayStep(s, now) then return end
    if s.dropCheckAtMs ~= nil and now >= s.dropCheckAtMs then
        s.dropCheckAtMs = nil
        if Standoff.playerArmed(s.player) then return Standoff.answer(s, "refuse", now, "ENC_DEMAND_DROP") end
    end
    if s.betray and not s.flanking and s.answered >= 1 then Standoff.beginFlank(s, now) end
    if s.flanking then
        local flanker = Standoff.shellFor(s.flankerUid)
        if Standoff.distance(flanker, s.flankPost) <= Standoff.flankReach or now - s.flankAtMs >= Standoff.flankMs then
            Standoff.count("betrayals")
            Standoff.say(s, s.leaderUid, "ENC_BETRAY")
            return Standoff.turn(s, now, true, false)
        end
    end
    if s.pending ~= nil then
        if now - s.pendingAtMs >= Standoff.waitMs(now) then return Standoff.silenceStep(s, now) end
        return Standoff.keepBroadcast(s, now)
    end
    if now < (s.nextAskAtMs or now) then return Standoff.keepBroadcast(s, now) end
    if #s.queue == 0 then return Standoff.conclude(s, now) end
    return Standoff.ask(s, table.remove(s.queue, 1), now)
end

function Standoff.ask(s, question, now)
    s.pending, s.pendingAtMs = question, now
    Standoff.count("asked")
    Standoff.say(s, s.leaderUid, question)
    Standoff.offerAnswers(s, now)
    Standoff.timer(s, Standoff.waitMs(now), "answer")
    Standoff.broadcast(s)
end

function Standoff.offerAnswers(s, now)
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.state) ~= "function" then return end
    local state = talk.state(s.playerKey, s.leaderUid, now)
    state.pending = s.pending
    if state.menuOpen == true and state.sessionId ~= nil and type(talk.choiceReply) == "function" then
        pcall(talk.choiceReply, s.player, { uid = s.leaderUid, ok = true, pending = s.pending or "ENC_OPEN",
            playerKey = s.playerKey, sessionId = state.sessionId, text = s.lastLine, stance = "careful" })
    end
end

function Standoff.silenceStep(s, now)
    s.silences = s.silences + 1
    Standoff.count("silences")
    if s.silences == 1 then
        s.pendingAtMs = now
        Standoff.say(s, s.leaderUid, "ENC_SILENCE")
        Standoff.timer(s, Standoff.waitMs(now), "answer")
        return
    end
    if s.silences == 2 then
        s.pendingAtMs = now
        Standoff.say(s, s.leaderUid, "ENC_SILENCE_LAST")
        Standoff.timer(s, Standoff.waitMs(now), "answer")
        return
    end
    return Standoff.react(s, s.profile.silence, now)
end

function Standoff.walkAwayStep(s, now)
    local px, py = Standoff.xyz(s.player)
    if px == nil or s.anchorX == nil then return false end
    if math.sqrt((px - s.anchorX) ^ 2 + (py - s.anchorY) ^ 2) < Standoff.walkAwayTiles then return false end
    s.walked = s.walked + 1
    Standoff.count("walkAways")
    s.anchorX, s.anchorY = px, py
    if s.walked == 1 then
        Standoff.say(s, s.leaderUid, "ENC_WALK_AWAY")
        if s.pending ~= nil then s.pendingAtMs = now end
        Standoff.broadcast(s)
        return true
    end
    Standoff.react(s, s.profile.walkAway, now)
    return true
end

function Standoff.react(s, reaction, now)
    s.stepAtMs = now
    if reaction == "warn" then
        if not s.warned then
            Standoff.warningShot(s, now)
            s.pending, s.silences = nil, 0
            s.nextAskAtMs = now + Standoff.nextAskMs
            if #s.queue == 0 then s.queue[1] = "ENC_DEMAND_LEAVE" end
            return
        end
        reaction = s.profile.afterWarn
    end
    if reaction == "turn" then return Standoff.turn(s, now, false, false) end
    return Standoff.outcome(s, reaction or "left", now, false)
end

function Standoff.beginFlank(s, now)
    local leader = Standoff.shellFor(s.leaderUid)
    local px, py = Standoff.xyz(s.player)
    local lx, ly = Standoff.xyz(leader)
    if px == nil or lx == nil then s.betray = false return end
    for _, uid in ipairs(s.members) do
        if uid ~= s.leaderUid then s.flankerUid = uid break end
    end
    if s.flankerUid == nil then s.betray = false return end
    local dx, dy = px - lx, py - ly
    local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    local side = Standoff.roll(2) == 0 and 1 or -1
    s.flankPost = { x = px - dy / length * Standoff.flankTiles * side, y = py + dx / length * Standoff.flankTiles * side }
    s.flanking, s.flankAtMs = true, now
    s.roles[s.flankerUid] = "flanker"
    Standoff.say(s, s.leaderUid, "ENC_STALL")
    Standoff.broadcast(s)
end

function Standoff.answer(s, kind, now, question)
    question = question or s.pending
    s.answeredAtMs = now
    if kind == "yes" and Standoff.yesKinds[question or ""] ~= nil then kind = Standoff.yesKinds[question] end
    if kind == "no" and Standoff.yesKinds[question or ""] ~= nil then kind = "refuse" end
    s.answered = s.answered + 1
    s.silences = 0
    s.pending = nil
    s.nextAskAtMs = now + Standoff.nextAskMs
    Standoff.count("answered")
    if s.phase == "surprise" or s.phase == "callout" or s.phase == "base" then
        if (s.phase == "callout" or s.phase == "base") and not Standoff.cameOut(s) then
            if not s.comeOutSaid then
                s.comeOutSaid = true
                s.untilMs = math.max(s.untilMs or now, now + 15000)
                Standoff.say(s, s.leaderUid, "ENC_COME_OUT")
                Standoff.timer(s, s.untilMs - now, s.kind)
            end
            return
        end
        Standoff.beginInterrogation(s, now)
    end
    if s.phase == "revenge" and kind == "pay" then return Standoff.outcome(s, "paid", now, false) end
    if s.phase ~= "interrogate" then return end
    return Standoff.handle(s, kind, now, question)
end

function Standoff.handle(s, kind, now, question)
    local profile = s.profile
    if kind == "refuse" then return Standoff.react(s, profile.refuse, now) end
    if kind == "pay" then
        if profile.toll then return Standoff.outcome(s, "paid", now, false) end
        Standoff.say(s, s.leaderUid, "ENC_REPLY_OK")
        return
    end
    if kind == "leave" then
        if profile.toll and not s.tollAsked then
            s.tollAsked = true
            table.insert(s.queue, 1, "ENC_DEMAND_TOLL")
            Standoff.say(s, s.leaderUid, "ENC_REPLY_DOUBT")
            return
        end
        if profile.toll and Standoff.shakedown(s, now) then return end
        return Standoff.outcome(s, "parted", now, false)
    end
    if kind == "flanker" then
        if s.flanking then
            Standoff.count("exposed")
            Standoff.say(s, s.leaderUid, "ENC_CAUGHT")
            return Standoff.outcome(s, "left", now, true)
        end
        Standoff.say(s, s.leaderUid, "ENC_NO_FLANKER")
        return
    end
    if kind == "join" then
        if Standoff.chance(profile.join) then return Standoff.outcome(s, "joined", now, false) end
        Standoff.say(s, s.leaderUid, "ENC_JOIN_NO")
        return
    end
    if kind == "comply" then
        if Standoff.playerArmed(s.player) then s.dropCheckAtMs = now + 2500 end
        if s.handsUpAtMs ~= nil and profile.toll and s.outcome ~= "paid" then
            return Standoff.outcome(s, "paid", now, false)
        end
        Standoff.say(s, s.leaderUid, "ENC_REPLY_OK")
        return
    end
    if question == "ENC_DEMAND_TOLL" then
        if kind == "little" and not s.tollPressed then
            s.tollPressed = true
            table.insert(s.queue, 1, "ENC_DEMAND_TOLL")
            Standoff.say(s, s.leaderUid, "ENC_REPLY_DOUBT")
            return
        end
        return Standoff.react(s, profile.refuse, now)
    end
    if kind == "group" then
        s.bluffed = true
        if s.betray and not s.flanking and Standoff.roll(2) == 0 then s.betray = false end
        Standoff.say(s, s.leaderUid, "ENC_REPLY_DOUBT")
        return
    end
    if profile.toll and (kind == "little" or kind == "alone") then
        Standoff.say(s, s.leaderUid, "ENC_REPLY_DOUBT")
        return
    end
    Standoff.say(s, s.leaderUid, "ENC_REPLY_OK")
end

function Standoff.conclude(s, now)
    local verdict = s.profile.conclude
    if s.profile.toll and not s.tollAsked and not s.paid then
        s.tollAsked = true
        return Standoff.ask(s, "ENC_DEMAND_TOLL", now)
    end
    if s.profile.toll and Standoff.shakedown(s, now) then return end
    return Standoff.outcome(s, verdict or "parted", now, false)
end

function Standoff.shakedown(s, now)
    local share = tonumber(s.profile.shakedown) or 0
    if share <= 0 or s.paid == true then return false end
    if not Standoff.chance(share * Standoff.settings(now).betrayalPercent / 100) then return false end
    Standoff.count("shakedowns")
    Standoff.turn(s, now, false, false)
    return true
end

function Standoff.turn(s, now, betrayal, quick)
    s.phase, s.phaseAtMs = "turning", now
    s.betrayal = betrayal == true
    s.turnUntilMs = now + (quick and Standoff.betrayTurnMs or Standoff.turnMs)
    if not betrayal then Standoff.say(s, s.leaderUid, "ENC_TURN") end
    Standoff.broadcast(s)
end

function Standoff.turnStep(s, now)
    if now < (s.turnUntilMs or now) then return Standoff.keepBroadcast(s, now) end
    return Standoff.fight(s, now, s.betrayal and "betrayal" or "turned")
end

function Standoff.fight(s, now, reason)
    Standoff.count(reason == "attacked" and "fought" or "turned")
    local registry = Standoff.registry()
    local careful = ProjectALife.ModuleCareful
    s.outcome = "fought"
    Standoff.remember(s, "fought", now)
    Standoff.finish(s, reason, now)
    if registry ~= nil and careful ~= nil and type(careful.writeTurned) == "function" then
        pcall(careful.writeTurned, registry, s.members, s.playerKey)
    end
    local fair = ProjectALife.Fairness
    if fair ~= nil and type(fair.noteTell) == "function" then
        for _, uid in ipairs(s.members) do
            local record = Standoff.read(uid)
            if record ~= nil then pcall(fair.noteTell, record, s.player, "shout", now, 0) end
        end
    end
end

function Standoff.outcome(s, outcome, now, quiet)
    s.outcome = outcome
    Standoff.count(outcome)
    if not quiet then
        local line = ({ parted = "ENC_PART", left = "ENC_LEAVE", paid = "ENC_PAID", joined = "ENC_JOIN_YES" })[outcome]
        if line ~= nil then Standoff.say(s, s.leaderUid, line) end
    end
    Standoff.remember(s, outcome, now)
    if outcome == "paid" and Standoff.handToRobbery(s, now) then return Standoff.finish(s, "paid", now) end
    if outcome == "joined" then Standoff.tolerate(s, now) end
    s.phase, s.phaseAtMs = outcome == "left" and "leave" or "release", now
    s.releaseUntilMs = now + (outcome == "left" and Standoff.leaveMs or Standoff.releaseMs)
    if outcome == "left" then Standoff.leavePoints(s) end
    Standoff.broadcast(s)
end

function Standoff.remember(s, outcome, now)
    local hours = Standoff.worldHours()
    local truce = Standoff.peaceful[outcome] == true
    if truce then
        local count = 0
        for id, until_ in pairs(Standoff.crewTruces) do
            if now >= until_ then Standoff.crewTruces[id] = nil else count = count + 1 end
        end
        if count >= 64 then Standoff.crewTruces = {} end
        Standoff.crewTruces[tostring(s.crewKey) .. "|" .. tostring(s.playerKey)] = now + Standoff.truceMs
    end
    for _, uid in ipairs(s.members) do
        Standoff.writeMember(uid, function(memory)
            memory.standoffOutcomes = type(memory.standoffOutcomes) == "table" and memory.standoffOutcomes or {}
            memory.standoffOutcomes[s.playerKey] = { o = outcome, h = hours, ms = now }
            if truce then
                memory.standoffTruce = type(memory.standoffTruce) == "table" and memory.standoffTruce or {}
                memory.standoffTruce[s.playerKey] = now + Standoff.truceMs
            end
        end)
    end
end

function Standoff.tolerate(s, now)
    local talk = ProjectALife.Talk
    local record = Standoff.read(s.leaderUid)
    if talk ~= nil and type(talk.tolerate) == "function" and record ~= nil then
        pcall(talk.tolerate, record, s.playerKey, now + Standoff.truceMs * 3)
    end
end

function Standoff.handToRobbery(s, now)
    local robbery = ProjectALife.ModuleRobbery
    if robbery == nil or type(robbery.start) ~= "function" or type(robbery.settings) ~= "table"
            or robbery.settings.enabled ~= true then
        return false
    end
    local crew = { key = s.crewKey, members = {} }
    for _, uid in ipairs(s.members) do
        local record, shell = Standoff.read(uid), Standoff.shellFor(uid)
        if record ~= nil and shell ~= nil then
            crew.members[#crew.members + 1] = { record = record, shell = shell, distance = Standoff.distance(shell, s.player) }
        end
    end
    if #crew.members == 0 then return false end
    Standoff.clear(s)
    local register = type(robbery.registerOf) == "function" and robbery.registerOf(crew.members[1].record) or nil
    local ok, state = pcall(robbery.start, crew, s.player, s.playerKey, register, now, "rob")
    return ok and state ~= nil
end

function Standoff.leavePoints(s)
    local px, py = Standoff.xyz(s.player)
    s.leave = {}
    for _, uid in ipairs(s.members) do
        local x, y = Standoff.xyz(Standoff.shellFor(uid))
        if x ~= nil and px ~= nil then
            local dx, dy = x - px, y - py
            local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
            s.leave[uid] = { x = px + dx / length * Standoff.leaveTiles, y = py + dy / length * Standoff.leaveTiles }
        end
    end
end

function Standoff.clear(s)
    for _, uid in ipairs(s.members) do
        Standoff.writeMember(uid, function(memory) memory.standoff = nil end)
    end
end

function Standoff.finish(s, reason, now)
    now = now or Standoff.now()
    s.phase = "done"
    s.finishedReason = reason
    Standoff.active[s.id] = nil
    if Standoff.byPlayer[s.playerKey] == s.id then Standoff.byPlayer[s.playerKey] = nil end
    if Standoff.byCrew[s.crewKey] == s.id then Standoff.byCrew[s.crewKey] = nil end
    Standoff.cooldowns[s.crewKey .. "|" .. tostring(s.playerKey)] = now + Standoff.cooldownMs
    Standoff.clear(s)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.clearOrders) == "function" and s.player ~= nil then pcall(talk.clearOrders, s.player) end
    if talk ~= nil and type(talk.states) == "table" and s.playerKey ~= nil then
        local state = talk.states[tostring(s.playerKey) .. ":" .. tostring(s.leaderUid)]
        if type(state) == "table" and type(state.pending) == "string" and string.sub(state.pending, 1, 4) == "ENC_" then
            state.pending = nil
        end
    end
    Standoff.timer(s, 0, "answer")
end

function Standoff.stateFor(player)
    local key = Standoff.keyOf(player)
    local id = key ~= nil and Standoff.byPlayer[key] or nil
    return id ~= nil and Standoff.active[id] or nil
end

function Standoff.heard(s, player, uid, reach)
    if Standoff.inReach(s, uid, reach) then return true end
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.orderOk) ~= "function" then return false end
    for _, member in ipairs(s.members) do
        if member == uid then return talk.orderOk(player, uid, Standoff.now()) == true end
    end
    return false
end

function Standoff.noteFar(player, uid)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.orderAnswered) == "function" then talk.orderAnswered(player, uid) end
end

function Standoff.orderTtl(s, now)
    local ttl = Standoff.waitMs(now) + 6000
    if (s.phase == "callout" or s.phase == "base") and tonumber(s.untilMs) ~= nil then
        ttl = math.max(ttl, s.untilMs - now + 5000)
    end
    return ttl
end

function Standoff.inReach(s, uid, reach)
    for _, member in ipairs(s.members) do
        if member == uid then return Standoff.distance(Standoff.shellFor(uid), s.player) <= reach end
    end
    return false
end

function Standoff.onChoice(player, uid, choice, sessionId)
    if not Standoff.authoritative() or type(choice) ~= "table" then return false, nil end
    local s = Standoff.stateFor(player)
    if s == nil or s.phase == "done" or not Standoff.heard(s, player, tostring(uid), Standoff.answerReach) then return false, nil end
    local now = Standoff.now()
    Standoff.noteFar(player, tostring(uid))
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.state) == "function" then
        local state = talk.state(s.playerKey, tostring(uid), now)
        state.menuOpen, state.sessionId, state.sessionActivityAtMs = true, sessionId, now
        if type(talk.hold) == "function" then
            local record, shell = Standoff.read(tostring(uid)), Standoff.shellFor(tostring(uid))
            if record ~= nil and shell ~= nil then pcall(talk.hold, record, shell, player, now, 15000) end
        end
    end
    if tostring(uid) ~= s.leaderUid then
        s.roles[tostring(uid)] = s.roles[tostring(uid)] or "member"
    end
    local kind = Standoff.choiceKinds[choice.id]
    if kind ~= nil then
        Standoff.answer(s, kind, now)
    elseif choice.id == "NPC_OPEN" and s.phase == "surprise" then
        Standoff.beginInterrogation(s, now)
    elseif choice.id == "NPC_OPEN" and (s.phase == "callout" or s.phase == "base") then
        Standoff.answer(s, "talk", now)
    end
    return true, { ok = true, text = s.lastLine, pending = s.pending or "ENC_OPEN", stance = "careful",
        reason = "standoff" }
end

function Standoff.kindOfWords(text)
    local lowered = string.lower(tostring(text or ""))
    for _, row in ipairs(Standoff.wordKinds) do
        if string.find(lowered, row[1], 1, true) ~= nil then return row[2] end
    end
    local intents, data = ProjectALife.TalkIntents, ProjectALife.DialogueData
    if intents ~= nil and type(intents.classify) == "function" then
        local ok, intent = pcall(intents.classify, text, true, data)
        if ok and intent ~= nil and Standoff.intentKinds[intent] ~= nil then return Standoff.intentKinds[intent] end
    end
    return "talk"
end

function Standoff.onPlayerWords(player, text, loud, now)
    if not Standoff.authoritative() then return false end
    local s = Standoff.stateFor(player)
    if s == nil or s.phase == "done" or s.phase == "turning" then return false end
    local reach = loud == true and Standoff.shoutReach or Standoff.answerReach
    local near = false
    for _, uid in ipairs(s.members) do
        if Standoff.heard(s, player, uid, reach) then near = true Standoff.noteFar(player, uid) break end
    end
    if not near then return false end
    Standoff.answer(s, Standoff.kindOfWords(text), tonumber(now) or Standoff.now())
    return true
end

function Standoff.onPlayerEmote(player, emote)
    if not Standoff.authoritative() then return false end
    local s = Standoff.stateFor(player)
    if s == nil or s.phase == "done" or s.phase == "turning" then return false end
    if emote == "surrender" then
        local now = Standoff.now()
        s.handsUpAtMs, s.handsUpArmed = now, Standoff.playerArmed(player)
        Standoff.count("surrendered")
        Standoff.answer(s, "comply", now)
        return true
    end
    if emote == "insult" then
        Standoff.answer(s, "refuse", Standoff.now())
        return true
    end
    return false
end

function Standoff.onPlayerState(player, args)
    local s = Standoff.stateFor(player)
    if s == nil or type(args) ~= "table" then return false end
    if args.aiming == true and args.armed ~= false then s.aimReportAtMs = Standoff.now() end
    return true
end

function Standoff.memberStep(actor, shell, context, now)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    local held = memory ~= nil and memory.standoff or nil
    if type(held) ~= "table" or held.phase == nil or held.phase == "done" then return nil end
    if not Standoff.holdsFor(memory, held.playerKey, now) then return nil end
    local start = type(context) == "table" and context.startMovement or nil
    local sx, sy, sz = Standoff.xyz(shell)
    if sx == nil then return nil end
    if held.phase == "leave" and tonumber(held.leaveX) ~= nil and type(start) == "function" then
        local state = start(actor, shell, { x = held.leaveX, y = held.leaveY, z = sz }, "standoff_leave",
            { pace = "walk", timeoutMs = 15000, tolerance = 3 })
        if state ~= nil then return state end
    end
    local target = Standoff.memberTarget(held, sx, sy)
    if target ~= nil and type(start) == "function" then
        local state = start(actor, shell, { x = target.x, y = target.y, z = sz }, target.intent,
            { pace = "walk", timeoutMs = 8000, tolerance = 1 })
        if state ~= nil then return state end
    end
    Standoff.face(shell, held, now)
    if type(context) == "table" and type(context.setActivity) == "function" then
        context.setActivity(actor, "warning", "standoff_hold")
    end
    return { kind = "idle", intent = "standoff_hold", cooldownUntilMs = now + 400 }
end

function Standoff.memberTarget(held, sx, sy)
    if held.role == "flanker" and tonumber(held.flankX) ~= nil
            and (held.flankX - sx) ^ 2 + (held.flankY - sy) ^ 2 > Standoff.flankReach ^ 2 then
        return { x = held.flankX, y = held.flankY, intent = "standoff_flank" }
    end
    if (held.phase == "callout" or held.phase == "base") and tonumber(held.postX) ~= nil
            and (held.postX - sx) ^ 2 + (held.postY - sy) ^ 2 > 2.25 then
        return { x = held.postX, y = held.postY, intent = "standoff_post" }
    end
    if held.role == "leader" and held.phase == "interrogate" and tonumber(held.px) ~= nil then
        local dx, dy = sx - held.px, sy - held.py
        local length = math.sqrt(dx * dx + dy * dy)
        if length > Standoff.closeTiles + 0.5 then
            return { x = held.px + dx / length * (Standoff.closeTiles - 0.5),
                y = held.py + dy / length * (Standoff.closeTiles - 0.5), intent = "standoff_close" }
        end
    end
    return nil
end

function Standoff.face(shell, held, now)
    local fx, fy = tonumber(held.px), tonumber(held.py)
    if held.phase == "callout" or held.phase == "base" then fx, fy = tonumber(held.fx) or fx, tonumber(held.fy) or fy end
    if fx == nil then return end
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then guard.faceAimPoint(shell, fx, fy, now) end
        local combat, animations = ProjectALife.Combat, ProjectALife.Animations
        if combat ~= nil and animations ~= nil and type(combat.readyPresetFor) == "function" and type(animations.apply) == "function"
                and not (type(animations.active) == "table" and animations.active[shell] ~= nil) then
            local preset = combat.readyPresetFor(shell, shell:getPrimaryHandItem(), nil)
            if preset ~= nil then animations.apply(shell, preset) end
        end
    end)
end

return Standoff
