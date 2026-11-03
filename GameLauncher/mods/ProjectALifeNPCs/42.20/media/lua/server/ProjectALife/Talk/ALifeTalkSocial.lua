require "ProjectALife/Talk/ALifeTalkSocialRows"

ProjectALife = ProjectALife or {}

local Rows = ProjectALife.TalkSocialRows

local Social = {
    adapters = {},
    keep = 8,
    convoGapMinutes = 20,
    warmAt = 16,
    coolAt = -16,
    backHours = 6,
    staticHours = 24,
    annoyDecayHours = 0.5,
    thanksHours = 0.5,
    stateRank = { friendly = "friendly", careful = "careful" },
    matrix = {
        greet = { friendly = 1, neutral = 1, careful = 0 },
        farewell = { friendly = 1, neutral = 1, careful = 0 },
        smalltalk = { friendly = 1, neutral = 1, careful = 0 },
        personal = { friendly = 1, neutral = 1, careful = -1 },
        probe = { friendly = 0, neutral = -1, careful = -3 },
        info = { friendly = 0, neutral = 0, careful = 0 },
        request = { friendly = 0, neutral = -1, careful = -2 },
        offer = { friendly = 2, neutral = 2, careful = 1 },
        kind = { friendly = 2, neutral = 2, careful = 1 },
        threat = { friendly = -5, neutral = -4, careful = -3 },
    },
    stranger = { friendly = -1, neutral = -2, careful = -3 },
    override = {
        INSULT = { friendly = -6, neutral = -5, careful = -4 },
        THREATEN = { friendly = -6, neutral = -6, careful = -5 },
        GO_AWAY = { friendly = -3, neutral = -3, careful = -2 },
        FLIRT = { friendly = 0, neutral = -1, careful = -3 },
        THANKS = { friendly = 1, neutral = 1, careful = 1 },
        SORRY = { friendly = 0, neutral = 0, careful = 0 },
        ENCOURAGE = { friendly = 1, neutral = 1, careful = 1 },
        ASK_OKAY = { friendly = 1, neutral = 1, careful = 1 },
        ASK_TRADE = { friendly = 0, neutral = 0, careful = -1 },
        JOIN_REQUEST = { friendly = 0, neutral = -1, careful = -2 },
        WALK_WITH_ME = { friendly = 0, neutral = 0, careful = -1 },
        COME_WITH_ME = { friendly = 0, neutral = -1, careful = -2 },
    },
    tempScale = { fresh = 1.5, seasoned = 1, veteran = 0.5, predator = 0.5 },
    careCats = { kind = true, offer = true },
    timingCats = { smalltalk = true, info = true, probe = true, personal = true, request = true },
    reasons = {
        greet = "You were friendly.", farewell = "You left on good terms.", smalltalk = "You were easy to talk to.",
        kind = "You showed you cared.", offer = "You offered to help.", personal = "You asked about their life and they opened up.",
        stranger = "You got too personal, too soon.", probe = "You pushed for details about their people.",
        request = "You asked for a handout.", threat = "You came at them with words.", info = "You asked at a bad moment.",
        repeats = "You kept asking the same thing.", ended = "You wore out their patience.",
        back = "They were glad you came back.",
    },
    fallback = {
        TALK_REPEAT_1 = { "I just told you that", "Already answered that one", "We did this one already, remember?",
            "Ask me something else, I said my piece" },
        TALK_REPEAT_2 = { "Are you even listening? Third time now", "I'm getting tired of saying it twice",
            "Quit asking me the same thing" },
        TALK_ENDS = { "That's it, I'm done talking", "We're finished here, go on", "I've had enough, leave me be" },
        TALK_REFUSES = { "Not talking right now, give it a while", "I said I was done, come back later",
            "Go away, I'm not in the mood" },
        TALK_NOT_FAMILIAR = { "Don't know you well enough for that", "That's kinda personal, we just met",
            "Ask me again when I know you better" },
        TALK_NOSY = { "You sure got a lot of questions", "That's plenty of questions for one go" },
        TALK_WARMS = { "You're alright, you know that?", "Funny, I'm starting to like you" },
        TALK_COOLS = { "Careful, I'm watching you", "I'm getting a bad feeling about you" },
        TALK_NO_INFO = { "I'm not telling you a thing", "Nothing to say to you, go ask somebody else" },
        TALK_NOT_YET = { "Not yet, I don't trust you that far", "Ask me when I know you better" },
    },
    verdictEvent = { ["repeat"] = "TALK_REPEAT_1", annoy = "TALK_REPEAT_2", ["end"] = "TALK_ENDS", refuse = "TALK_REFUSES",
        notyet = "TALK_NOT_FAMILIAR" },
    verdictReason = { ["repeat"] = "social_repeat", annoy = "social_annoyed", ["end"] = "talk_ended", refuse = "talk_refused",
        notyet = "social_notyet" },
    countName = { ["repeat"] = "repeats", annoy = "annoyed", ["end"] = "ended", refuse = "refused", notyet = "deflected" },
    angryActions = { annoy = true, ["end"] = true, refuse = true },
    rotor = 0,
    metrics = { asks = 0, repeats = 0, annoyed = 0, ended = 0, refused = 0, deflected = 0, capped = 0, warned = 0,
        gained = 0, lost = 0 },
}
ProjectALife.TalkSocial = Social

function Social.sandbox(key, fallback)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return fallback end
    local value = vars[key]
    if value == nil then return fallback end
    return value
end

function Social.number(key, fallback, low, high)
    local value = tonumber(Social.sandbox(key, fallback))
    if value == nil or value ~= value then value = fallback end
    return math.max(low, math.min(high, value))
end

function Social.enabled()
    if Social.sandbox("Talk_AntiSpam", true) == false then return false end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.authoritative) == "function" then return speech.authoritative() == true end
    return true
end

function Social.config()
    local cfg = {}
    cfg.cooldownHours = Social.number("Talk_RepeatCooldownMinutes", 30, 1, 600) / 60
    cfg.staticHours = Social.staticHours
    cfg.gapHours = Social.convoGapMinutes / 60
    cfg.refuseHours = Social.number("Talk_RefuseMinutes", 60, 5, 1440) / 60
    cfg.capConversation = Social.number("Talk_OpinionCapPerConversation", 6, 1, 40)
    cfg.capConversationNeg = math.ceil(cfg.capConversation * 1.5)
    cfg.capDay = Social.number("Talk_OpinionCapPerDay", 12, 1, 100)
    cfg.capDayNeg = math.ceil(cfg.capDay * 1.5)
    cfg.ceiling = Social.number("Talk_OpinionWordCeiling", 40, 0, 100)
    cfg.scale = Social.number("Talk_OpinionFromTalk", 100, 0, 300) / 100
    cfg.questions = Social.number("Talk_QuestionsPerTalk", 10, 2, 30)
    cfg.personalAfter = Social.number("Talk_PersonalAfterTalks", 2, 1, 10)
    return cfg
end

function Social.hours()
    if type(Social.adapters.hours) == "function" then return tonumber(Social.adapters.hours()) or 0 end
    if type(getGameTime) ~= "function" then return 0 end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return 0 end
    return tonumber(clock:getWorldAgeHours()) or 0
end

function Social.keyOf(player)
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.playerKey) == "function" then return speech.playerKey(player) end
    return nil
end

function Social.count(name)
    Social.metrics[name] = (Social.metrics[name] or 0) + 1
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.metrics) == "table" then
        talk.metrics.social = type(talk.metrics.social) == "table" and talk.metrics.social or {}
        talk.metrics.social[name] = (talk.metrics.social[name] or 0) + 1
    end
end

function Social.rowOf(record, key)
    local memory = type(record) == "table" and record.memory or nil
    local map = type(memory) == "table" and memory.social or nil
    if type(map) ~= "table" or key == nil then return nil end
    local row = map[key]
    if type(row) ~= "table" then return nil end
    return row
end

function Social.copy(row)
    local out = {}
    if type(row) ~= "table" then return out end
    for name, value in pairs(row) do
        if name == "a" and type(value) == "table" then
            local asked = {}
            for intent, entry in pairs(value) do
                if type(entry) == "table" then asked[intent] = { h = entry.h, c = entry.c, d = entry.d } end
            end
            out.a = asked
        elseif type(value) ~= "table" then
            out[name] = value
        end
    end
    return out
end

function Social.prune(row, now)
    if type(row.a) ~= "table" then return end
    local stale = {}
    for intent, entry in pairs(row.a) do
        if type(entry) ~= "table" or now - (tonumber(entry.h) or -1e9) > 72 then stale[#stale + 1] = intent end
    end
    for _, intent in ipairs(stale) do row.a[intent] = nil end
end

function Social.put(memory, key, row)
    memory.social = type(memory.social) == "table" and memory.social or {}
    memory.social[key] = Social.copy(row)
    local count, oldestKey, oldest = 0, nil, math.huge
    for other, entry in pairs(memory.social) do
        count = count + 1
        local at = type(entry) == "table" and tonumber(entry.at) or -math.huge
        if other ~= key and at < oldest then oldestKey, oldest = other, at end
    end
    if count > Social.keep and oldestKey ~= nil then memory.social[oldestKey] = nil end
end

function Social.write(uid, mutate)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" or type(registry.update) ~= "function" then return false end
    local current = registry.read(uid)
    if current == nil then return false end
    local ok, updated = pcall(registry.update, current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        mutate(record.memory)
    end)
    return ok and updated ~= nil and updated ~= false
end

function Social.anger(row, now)
    local level = tonumber(row.an) or 0
    if level <= 0 then return 0 end
    local relief = math.floor(math.max(0, now - (tonumber(row.aat) or now)) / Social.annoyDecayHours)
    return math.max(0, level - relief)
end

function Social.hurt(record, shell)
    if type(shell) == "table" and type(shell.getModData) == "function" then
        local has = true
        if type(shell.hasModData) == "function" then has = shell:hasModData() == true end
        if has then
            local data = shell:getModData()
            if type(data) == "table" and (data.ProjectALifeWoundLeg == true or data.ProjectALifeBleedOutAtMs ~= nil
                    or (tonumber(data.ProjectALifeWounds) or 0) > 0) then return true end
        end
    end
    local memory = type(record) == "table" and record.memory or nil
    return type(memory) == "table" and type(memory.injuries) == "table" and #memory.injuries > 0
end

function Social.scared(record)
    local fear = ProjectALife.ModuleFear
    local state = fear ~= nil and type(fear.actors) == "table" and type(record) == "table" and fear.actors[record.uid] or nil
    return type(state) == "table" and state.state == "afraid"
end

function Social.inParty(record, player)
    local party = ProjectALife.Party
    if party == nil or type(party.mineFor) ~= "function" then return false end
    local ok, mine = pcall(party.mineFor, record, player)
    return ok and mine ~= nil
end

function Social.valueOf(record, player)
    local opinion = ProjectALife.NpcOpinion
    if opinion == nil or type(opinion.valueOf) ~= "function" or not opinion.enabled() then return 0, false end
    return opinion.valueOf(record, player), true
end

function Social.stanceKey(stance)
    if stance == "friendly" or stance == "allied" then return "friendly" end
    if stance == "careful" then return "careful" end
    return "neutral"
end

function Social.context(record, shell, player, row, cfg, now)
    local talk, roles, speech = ProjectALife.Talk, ProjectALife.DialogueRoles, ProjectALife.Speech
    local ctx = { stance = "neutral", temperament = "seasoned" }
    if talk ~= nil and type(talk.stance) == "function" then ctx.stance = Social.stanceKey(talk.stance(record, player)) end
    if roles ~= nil and type(roles.describe) == "function" and speech ~= nil and type(speech.clock) == "function" then
        local ok, who = pcall(roles.describe, record, speech.clock().daysSurvived)
        if ok and type(who) == "table" then ctx.temperament = who.temperament or ctx.temperament end
    end
    ctx.value, ctx.tracked = Social.valueOf(record, player)
    ctx.hurt = Social.hurt(record, shell)
    ctx.scared = Social.scared(record)
    ctx.anger = Social.anger(row, now)
    ctx.thanked = row.kt ~= nil and now - (tonumber(row.kt) or -1e9) <= Social.thanksHours
    ctx.repair = ctx.anger > 0 or (tonumber(row.dm) or 0) > 0 and math.floor(now / 24) == row.dd
    ctx.familiar = (tonumber(row.n) or 0) >= cfg.personalAfter or ctx.value >= 30 or Social.inParty(record, player)
    return ctx
end

function Social.round(value)
    if value >= 0 then return math.floor(value) end
    return -math.floor(-value + 0.5)
end

function Social.delta(intent, ctx, cfg)
    local cat = Rows.category(intent)
    local matrix = Social.matrix[cat]
    if matrix == nil then return 0, cat end
    local stance = Social.stanceKey(ctx.stance)
    local base
    local special = Social.override[intent]
    if cat == "personal" and ctx.familiar ~= true then
        base = Social.stranger[stance]
        cat = "stranger"
    elseif special ~= nil then
        base = special[stance]
    else
        base = matrix[stance]
    end
    if intent == "SORRY" and ctx.repair then base = 2 end
    if intent == "THANKS" and ctx.thanked then base = 2 end
    local state = ctx.hurt == true or ctx.scared == true
    if state then
        if Social.careCats[Rows.category(intent)] and base > 0 then base = base * 2
        elseif Social.timingCats[Rows.category(intent)] then
            base = base - 1
            if cat ~= "stranger" then cat = "info" end
        end
    end
    local value = base * (cfg ~= nil and cfg.scale or 1)
    if value > 0 then
        value = value * (Social.tempScale[tostring(ctx.temperament)] or 1)
        local standing = tonumber(ctx.value) or 0
        if standing >= 40 then value = value * 0.5 end
        if standing <= -30 and intent ~= "SORRY" then value = value * 0.5 end
    end
    return Social.round(value), cat
end

function Social.limit(row, delta, standing, cfg, now)
    if delta == 0 then return 0 end
    local allowed = delta
    if delta > 0 then
        local room = math.min(cfg.capConversation - (tonumber(row.cp) or 0), cfg.capDay - (tonumber(row.dp) or 0),
            cfg.ceiling - standing)
        allowed = math.max(0, math.min(delta, room))
        row.cp = (tonumber(row.cp) or 0) + allowed
        row.dp = (tonumber(row.dp) or 0) + allowed
    else
        local room = math.min(cfg.capConversationNeg - (tonumber(row.cm) or 0), cfg.capDayNeg - (tonumber(row.dm) or 0))
        allowed = -math.max(0, math.min(-delta, room))
        row.cm = (tonumber(row.cm) or 0) - allowed
        row.dm = (tonumber(row.dm) or 0) - allowed
    end
    if allowed ~= delta then Social.count("capped") end
    return allowed
end

function Social.patience(standing, cfg)
    return math.max(4, math.min(14, cfg.questions + math.floor(standing / 15)))
end

function Social.decide(row, intent, ctx, cfg, now)
    local verdict = { action = "go", delta = 0, want = 0, intent = intent }
    if row.ru ~= nil and now < row.ru then
        verdict.action, verdict.close = "refuse", true
        return verdict
    end
    local cat = Rows.category(intent)
    if Rows.exempt[cat] == true then return verdict end
    verdict.dirty = true
    row.ru = nil
    local away = nil
    if row.at == nil or now - row.at > cfg.gapHours then
        if row.at ~= nil then away = now - row.at end
        row.n = (tonumber(row.n) or 0) + 1
        row.ct, row.cp, row.cm = 0, 0, 0
        ctx.familiar = ctx.familiar or row.n >= cfg.personalAfter
    end
    local day = math.floor(now / 24)
    if row.dd ~= day then row.dd, row.dp, row.dm = day, 0, 0 end
    row.at = now
    row.ct = (tonumber(row.ct) or 0) + 1
    row.a = type(row.a) == "table" and row.a or {}
    local stranger = cat == "personal" and ctx.familiar ~= true
    local window = Rows.windowKind(intent) == "S" and cfg.staticHours or cfg.cooldownHours
    local entry = row.a[intent]
    if type(entry) == "table" and entry.d == true and not stranger then entry = nil end
    local level = 0
    if type(entry) == "table" and now - (tonumber(entry.h) or -1e9) < window then
        entry.c = (tonumber(entry.c) or 1) + 1
        entry.h = now
        level = entry.c - 1
    else
        row.a[intent] = { h = now, c = 1 }
    end
    local patience = Social.patience(ctx.value, cfg)
    local anger = ctx.anger
    local why, want = nil, 0
    if level >= 3 or row.ct > patience then
        verdict.action, verdict.close = "end", true
        want = -2
        if level >= 3 then why = Social.reasons.repeats else why = Social.reasons.ended end
        row.ru = now + cfg.refuseHours
        row.an, row.aat = math.max(2, anger), now
        row.ct = 0
    elseif level == 2 then
        verdict.action = "annoy"
        want, why = -1, Social.reasons.repeats
        row.an, row.aat = math.min(3, anger + 1), now
    elseif level == 1 and not stranger then
        verdict.action = "repeat"
    else
        local category
        want, category = Social.delta(intent, ctx, cfg)
        why = Social.reasons[category]
        if away ~= nil and away >= Social.backHours and ctx.value >= 5 and not stranger and want >= 0 then
            want, why = want + 1, Social.reasons.back
        end
        if stranger then
            verdict.action = "notyet"
            row.a[intent].d = true
        end
        if intent == "SORRY" and anger > 0 then row.an, row.aat = anger - 1, now end
        if row.ct == patience then verdict.warn = true end
    end
    verdict.want, verdict.why = want, why
    verdict.delta = Social.limit(row, want, ctx.value, cfg, now)
    verdict.level, verdict.patience = level, patience
    return verdict
end

function Social.line(kind, record, shell, player, context)
    local talk, data, speech = ProjectALife.Talk, ProjectALife.DialogueData, ProjectALife.Speech
    if talk == nil or speech == nil then return nil end
    local text = nil
    if data ~= nil and type(data.replies) == "table" then
        if type(data.load) == "function" then data.load() end
        local pool = data.replies[kind]
        if type(pool) == "table" and #pool > 0 then text = talk.speak(record, shell, player, pool, context, {}) end
    end
    if text ~= nil then return text end
    local list = Social.fallback[kind]
    if list == nil then return nil end
    Social.rotor = Social.rotor + 1
    text = list[(Social.rotor + string.len(tostring(record.uid))) % #list + 1]
    speech.say(shell, text, { face = player })
    return text
end

function Social.text(kind, record, player)
    if not Social.enabled() or type(record) ~= "table" then return nil end
    local data, speech, talk = ProjectALife.DialogueData, ProjectALife.Speech, ProjectALife.Talk
    if data ~= nil and speech ~= nil and talk ~= nil and type(data.replies) == "table" then
        if type(data.load) == "function" then data.load() end
        local pool = data.replies[kind]
        if type(pool) == "table" and #pool > 0 then
            local shell = talk.shellFor(record.uid)
            local context = Social.speechContext(record, shell, player, nil)
            local key = Social.keyOf(player)
            local chosen = speech.pick(pool, context, record.uid, key)
            if chosen ~= nil then
                speech.remember(record.uid, key, chosen.t)
                return speech.render(chosen.t, nil, shell, context.psex)
            end
        end
    end
    local list = Social.fallback[kind]
    if list == nil then return nil end
    Social.rotor = Social.rotor + 1
    return list[(Social.rotor + string.len(tostring(record.uid))) % #list + 1]
end

function Social.speechContext(record, shell, player, mood)
    local talk, speech = ProjectALife.Talk, ProjectALife.Speech
    local context = speech.contextFor(record, player)
    context.stance = talk.stance(record, player)
    context.mood = mood
    return context
end

function Social.mood(record, player)
    if not Social.enabled() or type(record) ~= "table" then return nil end
    local key = Social.keyOf(player)
    local row = Social.rowOf(record, key)
    local now = Social.hours()
    if row ~= nil and Social.anger(row, now) >= 1 then return "angry" end
    if Social.scared(record) then return "fear" end
    local value = Social.valueOf(record, player)
    if value >= 40 then return "warm" end
    return nil
end

function Social.persist(record, player, row, verdict)
    local key = Social.keyOf(player)
    Social.prune(row, Social.hours())
    local function store(memory) Social.put(memory, key, row) end
    local opinion = ProjectALife.NpcOpinion
    if verdict.delta ~= 0 and opinion ~= nil and opinion.enabled() and type(opinion.adjust) == "function" then
        if opinion.adjust(record, player, verdict.delta, verdict.why or "You talked to them.", store) then return true end
    end
    return Social.write(record.uid, store)
end

function Social.ask(player, listener, intent, source)
    if not Social.enabled() or type(listener) ~= "table" or type(listener.record) ~= "table" then return nil end
    local record, shell = listener.record, listener.shell
    local key = Social.keyOf(player)
    if key == nil then return nil end
    local cfg = Social.config()
    local now = Social.hours()
    local row = Social.copy(Social.rowOf(record, key))
    local ctx = Social.context(record, shell, player, row, cfg, now)
    local verdict = Social.decide(row, intent, ctx, cfg, now)
    verdict.before = ctx.value
    if verdict.delta ~= 0 and ctx.tracked == true and verdict.action == "go" then
        Social.crossing(verdict, row, ctx.value, now)
    end
    if verdict.dirty then
        Social.persist(record, player, row, verdict)
        Social.count("asks")
    end
    if verdict.delta > 0 then Social.metrics.gained = Social.metrics.gained + verdict.delta
    elseif verdict.delta < 0 then Social.metrics.lost = Social.metrics.lost - verdict.delta end
    local kind = Social.verdictEvent[verdict.action]
    if kind ~= nil then
        Social.count(Social.countName[verdict.action])
        local mood = nil
        if Social.angryActions[verdict.action] == true then mood = "angry" end
        verdict.text = Social.line(kind, record, shell, player, Social.speechContext(record, shell, player, mood))
        verdict.reason = Social.verdictReason[verdict.action]
    end
    if verdict.warn and verdict.action == "go" then
        Social.count("warned")
        local talk = ProjectALife.Talk
        if talk ~= nil and type(talk.later) == "function" then
            talk.later(1800, function()
                Social.line("TALK_NOSY", record, shell, player, Social.speechContext(record, shell, player, "angry"))
            end)
        end
    end
    if verdict.shift ~= nil then
        Social.count(verdict.shift == "TALK_WARMS" and "warmed" or "cooled")
        local talk = ProjectALife.Talk
        if talk ~= nil and type(talk.later) == "function" then
            local kind = verdict.shift
            talk.later(3200, function()
                Social.line(kind, record, shell, player, Social.speechContext(record, shell, player, nil))
            end)
        end
    end
    verdict.source = source
    return verdict
end

function Social.crossing(verdict, row, before, now)
    local after = before + verdict.delta
    local day = math.floor(now / 24)
    if after > before and before < Social.warmAt and after >= Social.warmAt and row.wm ~= day then
        verdict.shift, row.wm = "TALK_WARMS", day
    elseif after < before and before >= Social.coolAt and after < Social.coolAt and row.cl ~= day then
        verdict.shift, row.cl = "TALK_COOLS", day
    end
end

function Social.gate(player, listener, choice, sessionId, source)
    if type(choice) ~= "table" then return nil end
    local verdict = Social.ask(player, listener, choice.id, source)
    if verdict == nil then return nil end
    verdict.stop = verdict.action ~= "go"
    return verdict
end

function Social.typed(player, listener, intent)
    local verdict = Social.ask(player, listener, intent, "typed")
    if verdict == nil or verdict.action == "go" then return nil end
    local talk = ProjectALife.Talk
    if verdict.close and talk ~= nil and type(talk.releaseHold) == "function" then
        talk.releaseHold(listener.record.uid, ProjectALife.Speech.playerKey(player))
    end
    return verdict.text, verdict.reason
end

function Social.deedAllowed(kind, record, player)
    if kind ~= "walk" or not Social.enabled() then return true end
    local key = Social.keyOf(player)
    if key == nil or type(record) ~= "table" then return true end
    local row = Social.copy(Social.rowOf(record, key))
    local day = math.floor(Social.hours() / 24)
    if row.wk == day then return false end
    row.wk = day
    Social.write(record.uid, function(memory) Social.put(memory, key, row) end)
    return true
end

Social.kindDeeds = { gift = true, medicine = true, help_fight = true, saved = true, trade = true, door_kind = true,
    party_task = true, promise = true, walk = true }

function Social.deedStamp(kind, player)
    if Social.kindDeeds[kind] ~= true or not Social.enabled() then return nil end
    local key = Social.keyOf(player)
    if key == nil then return nil end
    local now = Social.hours()
    return function(memory)
        local map = type(memory.social) == "table" and memory.social or nil
        local row = map ~= nil and type(map[key]) == "table" and Social.copy(map[key]) or {}
        row.kt = now
        Social.put(memory, key, row)
    end
end

function Social.view(record, shell, player)
    if not Social.enabled() or type(record) ~= "table" then return nil end
    local key = Social.keyOf(player)
    local cfg = Social.config()
    local now = Social.hours()
    local row = Social.copy(Social.rowOf(record, key))
    local ctx = Social.context(record, shell, player, row, cfg, now)
    local memory = type(record.memory) == "table" and record.memory or {}
    local view = { on = true, fam = ctx.familiar == true, ct = tonumber(row.ct) or 0, an = ctx.anger, asked = {}, ctx = {},
        sug = {}, patience = Social.patience(ctx.value, cfg), focus = Social.sandbox("Talk_MenuFocus", true) ~= false }
    view.walk = type(memory.walkWith) == "table" and memory.walkWith.key == key
    if row.ru ~= nil and now < row.ru then view.left = math.ceil((row.ru - now) * 60) end
    for intent, entry in pairs(type(row.a) == "table" and row.a or {}) do
        local window = Rows.windowKind(intent) == "S" and cfg.staticHours or cfg.cooldownHours
        if type(entry) == "table" and now - (tonumber(entry.h) or -1e9) < window then view.asked[intent] = true end
    end
    local sug = view.sug
    if ctx.hurt then
        view.ctx.ASK_OKAY, view.ctx.OFFER_HELP = true, true
        sug[#sug + 1] = "ASK_OKAY"
        sug[#sug + 1] = "OFFER_HELP"
    elseif ctx.scared then
        view.ctx.ASK_OKAY, view.ctx.ENCOURAGE = true, true
        sug[#sug + 1] = "ENCOURAGE"
        sug[#sug + 1] = "ASK_OKAY"
    end
    if ctx.thanked then
        view.ctx.THANKS = true
        sug[#sug + 1] = "THANKS"
    end
    if ctx.repair then
        view.ctx.SORRY = true
        sug[#sug + 1] = "SORRY"
    end
    if view.ct >= 1 then view.ctx.FAREWELL = true end
    Social.suggest(view, record, shell, player, ctx)
    local fresh = {}
    for _, id in ipairs(view.sug) do
        if view.asked[id] ~= true then fresh[#fresh + 1] = id end
    end
    view.sug = fresh
    return view
end

function Social.suggest(view, record, shell, player, ctx)
    local sug = view.sug
    if ctx.stance ~= "careful" then
        local supplies = ProjectALife.TalkSupplies
        local inventory = type(shell) == "table" and type(shell.getInventory) == "function" and shell:getInventory() or nil
        local items = inventory ~= nil and type(inventory.getItems) == "function" and inventory:getItems() or nil
        if supplies ~= nil and type(supplies.matches) == "function" and items ~= nil then
            local found = {}
            for index = 0, math.min(items:size(), 64) - 1 do
                for _, intent in ipairs({ "ASK_FOOD", "ASK_WATER", "ASK_MEDS" }) do
                    if found[intent] == nil then
                        local ok, matched = pcall(supplies.matches, items:get(index), intent)
                        if ok and matched == true then found[intent] = true end
                    end
                end
            end
            for _, intent in ipairs({ "ASK_FOOD", "ASK_WATER", "ASK_MEDS" }) do
                if found[intent] == true then sug[#sug + 1] = intent end
            end
        end
    end
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.observations) == "function" and Social.clock ~= nil then
        local ok, facts = pcall(talk.observations, record, shell, player, Social.clock())
        if ok and type(facts) == "table" and facts.recent_zombie_contact == true then sug[#sug + 1] = "ASK_DANGER" end
    end
end

function Social.clock()
    if type(Social.adapters.nowMs) == "function" then return Social.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Social.decorate(result, uid, player, delta)
    if type(result) ~= "table" then return result end
    local registry, talk = ProjectALife.ActorRegistry, ProjectALife.Talk
    local record = registry ~= nil and type(registry.read) == "function" and registry.read(uid) or nil
    if record == nil or talk == nil then return result end
    local shell = talk.shellFor(uid)
    local view = Social.view(record, shell, player)
    if view == nil then return result end
    result.social = view
    if type(result.opinion) == "table" and delta ~= nil and delta ~= 0 then result.opinion.delta = delta end
    return result
end

function Social.reset()
    Social.rotor = 0
    Social.metrics = { asks = 0, repeats = 0, annoyed = 0, ended = 0, refused = 0, deflected = 0, capped = 0, warned = 0,
        gained = 0, lost = 0 }
    return true
end

return Social
