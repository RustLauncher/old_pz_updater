require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorTalkRules"
require "ProjectALife/Visitors/ALifeVisitorLines"
require "ProjectALife/Visitors/ALifeVisitorTalk"
require "ProjectALife/Visitors/ALifeVisitorActions"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Rules = ProjectALife.VisitorTalkRules
local Lines = ProjectALife.VisitorLines
local Talk = ProjectALife.VisitorTalk
local Actions = ProjectALife.VisitorActions

local Events = {
    adapters = {},
    actions = Actions.map,
    state = {},
    open = {},
    players = {},
    why = {},
    reasons = {},
    nextAtMs = 0,
    cursor = 0,
    settings = {
        passMs = 1000, evalMs = 5000, windowMs = 900000, windowMax = 3, quietLineMs = 30000, nearTiles = 6, approachMs = 45000,
        windowEvents = 8, maxVisitors = 8, maxStates = 32, maxPlayers = 16, thresholds = { 180, 300, 420 }, jitterSec = 60,
        resetOutsideMs = 90000, dtCapMs = 15000, quietFrom = 23, quietTo = 6, extendMs = 15000, extendMax = 8, choicesMax = 4,
        promptMax = 200, labelMax = 80, cooldownKeep = 4, queueMax = 3, queueTries = 3, notice = true,
    },
    metrics = { passes = 0, evals = 0, fired = 0, answered = 0, dismissed = 0, timeouts = 0, dropped = 0, queued = 0, approached = 0,
        refused = 0, ms = 0, maxMs = 0, lastWhy = "-", lastEvent = "-" },
}
ProjectALife.VisitorEvents = Events

Events.PRIVATE = { bathroom = true, change = true, bath = true, rest = true }
Events.PRIVATE_ACT = { privacy = true, change = true, rest = true }

function Events.nowMs()
    if type(Events.adapters.nowMs) == "function" then return Events.adapters.nowMs() end
    return Talk.nowMs()
end

function Events.stamp()
    if type(Events.adapters.stamp) == "function" then return Events.adapters.stamp() end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function Events.rand(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 1 then return 0 end
    if type(Events.adapters.rand) == "function" then return math.floor(tonumber(Events.adapters.rand(n)) or 0) % n end
    if type(ZombRand) == "function" then return math.floor(tonumber(ZombRand(n)) or 0) end
    return 0
end

function Events.clientSide()
    if type(Events.adapters.clientSide) == "function" then return Events.adapters.clientSide() == true end
    return type(isClient) == "function" and isClient() == true
end

function Events.deny(uid, why)
    local m = Events.metrics
    m.refused, m.lastWhy = m.refused + 1, why
    Events.reasons[why] = (Events.reasons[why] or 0) + 1
    if uid ~= nil then Events.why[uid] = why end
    return false, why
end

function Events.lastWhy(uid)
    if uid == nil then return Events.metrics.lastWhy end
    return Events.why[uid] or "-"
end

function Events.onceFlag(id)
    return "Q_" .. (string.gsub(id, "^VE_", ""))
end

function Events.houseOf(record)
    local memory = type(record) == "table" and record.memory or nil
    local guest = type(memory) == "table" and memory.guest or nil
    local director = ProjectALife.SafehouseDirector
    if type(guest) ~= "table" or director == nil or type(director.store) ~= "function" then return nil end
    return director.store().houses[guest.house]
end

function Events.playersOf(house)
    local director = ProjectALife.SafehouseDirector
    if house == nil or director == nil or type(director.onlineResidents) ~= "function" then return {} end
    return director.onlineResidents(house) or {}
end

function Events.playerByKey(record, key)
    for _, player in ipairs(Events.playersOf(Events.houseOf(record))) do
        if Rules.playerKey(player) == key then return player end
    end
    return nil
end

function Events.eligibleRecord(record, pending)
    if type(record) ~= "table" or record.lifecycle ~= "active" or type(record.memory) ~= "table" then return false end
    local guest = record.memory.guest
    return type(guest) == "table" and guest.pendingId == pending.id and type(record.memory.person) == "table"
end

function Events.visitors(only)
    local list = {}
    local director, registry = ProjectALife.SafehouseDirector, ProjectALife.ActorRegistry
    if director == nil or registry == nil or type(director.store) ~= "function" or type(registry.peek) ~= "function" then return list end
    for _, house in pairs(director.store().houses or {}) do
        for _, pending in ipairs(type(house.pending) == "table" and house.pending or {}) do
            if pending.lane == "visit" and pending.resolved ~= true and pending.state == "inside" then
                for _, uid in ipairs(type(pending.uids) == "table" and pending.uids or {}) do
                    if (only == nil and #list < Events.settings.maxVisitors) or only == uid then
                        local record = registry.peek(uid)
                        if Events.eligibleRecord(record, pending) then
                            list[#list + 1] = { uid = uid, record = record, house = house, pending = pending }
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    return list
end

function Events.stateOf(uid, nowMs)
    local st = Events.state[uid]
    if st == nil then
        local count = 0
        for _ in pairs(Events.state) do count = count + 1 end
        if count >= Events.settings.maxStates then Events.state = {} end
        st = { nextMs = nowMs, lastMs = nowMs, insideSec = 0, outsideMs = 0, jitter = Events.rand(Events.settings.jitterSec + 1),
            cursor = 0, queue = {}, tries = 0, approachMs = nil, fresh = true }
        Events.state[uid] = st
    end
    return st
end

function Events.playerRow(key)
    local row = Events.players[key]
    if row == nil then
        local count = 0
        for _ in pairs(Events.players) do count = count + 1 end
        if count >= Events.settings.maxPlayers then Events.players = {} end
        row = { lastMs = nil, stamps = {} }
        Events.players[key] = row
    end
    return row
end

function Events.dropSaved(uid)
    return Instance.write(uid, function(memory)
        if type(memory.evq) == "table" then memory.evq.open = nil end
    end)
end

function Events.gateVisitor(v, record, nowMs)
    if type(record) ~= "table" or record.lifecycle ~= "active" then return "gone" end
    local person = Instance.of(record)
    if person == nil then return "noperson" end
    local pending = v.pending
    if type(pending) ~= "table" or pending.state ~= "inside" or pending.resolved == true or type(record.memory.guest) ~= "table" then
        return "notinside"
    end
    local life = record.memory.life
    local kind = type(life) == "table" and life.k or nil
    if (kind ~= nil and Events.PRIVATE[kind]) or (person.act ~= nil and Events.PRIVATE_ACT[person.act])
            or (person.ds ~= nil and person.ds ~= "dressed") then
        return "private"
    end
    if record.activity == "combat" then return "busy" end
    return nil
end

function Events.playerState(player)
    if type(player.getVehicle) == "function" and player:getVehicle() ~= nil then return "vehicle" end
    if type(player.isAsleep) == "function" and player:isAsleep() == true then return "asleep" end
    return nil
end

function Events.threatened(player)
    if type(Events.adapters.threat) == "function" then return Events.adapters.threat(player) == true end
    local stats = type(player.getStats) == "function" and player:getStats() or nil
    if stats ~= nil and type(stats.getNumChasingZombies) == "function" and (tonumber(stats:getNumChasingZombies()) or 0) > 0 then
        return true
    end
    return false
end

function Events.gateInside(v, record, st, nowMs, force)
    local players = Events.playersOf(v.house)
    if #players == 0 then return nil, "noplayer" end
    local dt = math.max(0, math.min(nowMs - st.lastMs, Events.settings.dtCapMs))
    st.lastMs = nowMs
    local found, paused = nil, nil
    for _, player in ipairs(players) do
        local env = Rules.env(record, player, nowMs, nil)
        if Rules.inside(env) then
            paused = Events.playerState(player)
            if paused == nil and found == nil then found = player end
        end
    end
    if found == nil then
        if paused ~= nil then return nil, paused end
        st.outsideMs = st.outsideMs + dt
        if st.outsideMs > Events.settings.resetOutsideMs then st.insideSec = 0 end
        if force then return players[1] end
        return nil, "outside"
    end
    st.outsideMs = 0
    st.insideSec = st.insideSec + dt / 1000
    if force then return found end
    local saved = type(record.memory.evq) == "table" and record.memory.evq or {}
    local steps = Events.settings.thresholds
    local need = steps[math.min((tonumber(saved.n) or 0) + 1, #steps)] + st.jitter
    if st.insideSec < need then return nil, "insidesec" end
    return found
end

function Events.gateSafe(record, player, nowMs)
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.alive) == "function" and not speech.alive(player) then return "dead" end
    if type(player.isAiming) == "function" and player:isAiming() == true then return "aiming" end
    local questions, talk = ProjectALife.TalkQuestions, ProjectALife.Talk
    if questions ~= nil and talk ~= nil and speech ~= nil and type(questions.playerSafe) == "function"
            and not questions.playerSafe(player, nowMs) then
        return "unsafe"
    end
    if Events.threatened(player) then return "threat" end
    if talk ~= nil then
        if type(talk.busy) == "function" and talk.busy(record, nowMs) then return "busy" end
        if type(talk.sessionOpenFor) == "function" and talk.sessionOpenFor(record.uid) then return "talking" end
    end
    return nil
end

function Events.gatePacing(uid, key, nowMs, options)
    local settings = Events.settings
    local row = Events.playerRow(key)
    local gapMs = (tonumber(options.eventMinGapSeconds) or 240) * 1000 * (tonumber(options.eventGapScale) or 1)
    if row.lastMs ~= nil and nowMs >= row.lastMs and nowMs - row.lastMs < gapMs then return "gap" end
    local kept = {}
    for _, at in ipairs(row.stamps) do
        if nowMs >= at and nowMs - at < settings.windowMs then kept[#kept + 1] = at end
    end
    row.stamps = kept
    if #kept >= settings.windowMax then return "window" end
    for _, open in pairs(Events.open) do
        if open.key == key then return "open" end
    end
    local session = Talk.sessions[tostring(uid) .. ":" .. tostring(key)]
    if session ~= nil and nowMs >= session.last and nowMs - session.last < settings.quietLineMs then return "recent" end
    return nil
end

function Events.approach(v, record, st, nowMs)
    if st.approachMs ~= nil and nowMs >= st.approachMs and nowMs - st.approachMs < Events.settings.approachMs then return false end
    local life = ProjectALife.VisitorLife
    local row = record.memory.life
    if life ~= nil and type(life.POSED) == "table" and type(row) == "table" and life.POSED[row.k] then return false end
    st.approachMs = nowMs
    Events.metrics.approached = Events.metrics.approached + 1
    return Actions.approach(v.uid, record) == true
end

function Events.gateNear(v, record, st, player, nowMs)
    local sx, sy, sz = Rules.pos(Talk.shellOf(v.uid))
    local px, py, pz = Rules.pos(player)
    if sx == nil or px == nil then return "noshell" end
    local reach = Events.settings.nearTiles
    if math.floor(sz) == math.floor(pz) and (sx - px) * (sx - px) + (sy - py) * (sy - py) <= reach * reach then return nil end
    Events.approach(v, record, st, nowMs)
    return "far"
end

function Events.context(v, record, player, st, key, nowMs, options, force)
    local env = Rules.env(record, player, nowMs, { inside = true, insideSec = st.insideSec })
    local card = Rules.card(env)
    if card == nil then return nil, "loading" end
    local clock = Rules.clockOf(env)
    return { env = env, record = record, person = env.person, card = card, st = st, key = key, player = player, nowMs = nowMs,
        evq = type(record.memory.evq) == "table" and record.memory.evq or {}, row = Rules.row(env), hours = env.hours,
        hour = tonumber(clock.hour), options = options, forced = force == true, v = v }
end

function Events.quiet(c, ev)
    local hour = c.hour
    if hour == nil then return false end
    local settings = Events.settings
    if hour < settings.quietFrom and hour >= settings.quietTo then return false end
    if ev.tags.night or (ev.when ~= nil and string.find(ev.when, "night", 1, true) ~= nil) then return false end
    return true
end

function Events.isLead(c)
    local person = c.person
    if #person.with == 0 then return false end
    for _, id in ipairs(person.with) do
        if id < person.id then return false end
    end
    return true
end

function Events.choicesOf(ev)
    local list, valid = {}, {}
    local source = type(ev.raw) == "table" and ev.raw.ch or nil
    if type(source) ~= "table" then return list, valid end
    local index = 1
    while type(source[index]) == "table" and #list < Events.settings.choicesMax do
        local label = Schema.str(source[index].label)
        if label ~= nil then
            list[#list + 1] = { i = index, label = string.sub(label, 1, Events.settings.labelMax) }
            valid[index] = true
        end
        index = index + 1
    end
    return list, valid
end

function Events.refusal(ev, c, queued)
    if ev.adultOnly then
        if not Rules.adult(c.env) then return "adult" end
        if #Events.choicesOf(ev) == 0 then return "reactive" end
        if Rules.atoms.minorPresent(c.env) then return "minor" end
    end
    if ev.speaker == "adult" and not Rules.adult(c.env) then return "speaker" end
    if ev.speaker == "party:lead" and not Events.isLead(c) then return "speaker" end
    if c.forced then return nil end
    if ev.once and Instance.flag(c.row, Events.onceFlag(ev.id)) then return "once" end
    local cooling = tonumber(type(c.evq.cd) == "table" and c.evq.cd[ev.id] or nil)
    if cooling ~= nil and cooling > c.hours then return "cooldown" end
    if not queued and c.evq.lk == ev.kind then return "samekind" end
    if Events.quiet(c, ev) then return "quiet" end
    if ev.when ~= nil and not Rules.test(c.env, ev.when) then return "when" end
    return nil
end

function Events.hasPrompt(ev, c)
    local found = Lines.lookup(c.env, ev.id .. ".prompt")
    if found == nil then return nil end
    return found.node ~= nil
end

function Events.urgency(ev, c)
    local best = 0
    for name in string.gmatch(ev.when or "", "need:(%a+)") do
        if Instance.needKey(name) ~= nil then best = math.max(best, Instance.need(c.person, name)) end
    end
    return math.min(2.5, 1 + math.max(0, best - 2) * 0.5)
end

function Events.weightOf(ev, c)
    local social = 0.5 + 0.2 * (tonumber(c.card.traits.social) or 2)
    return math.max(0.1, ev.weight * social * Events.urgency(ev, c))
end

function Events.window(c, events)
    local list, size = {}, #events
    if size == 0 then return list end
    local span = math.min(Events.settings.windowEvents, size)
    for step = 0, span - 1 do list[#list + 1] = events[(c.st.cursor + step) % size + 1] end
    c.st.cursor = (c.st.cursor + span) % size
    return list
end

function Events.weigh(c, list)
    local picks, total, outcome = {}, 0, "noevent"
    for _, ev in ipairs(list) do
        local reason = Events.refusal(ev, c, false)
        if reason ~= nil then
            Events.reasons[reason] = (Events.reasons[reason] or 0) + 1
        else
            local ready = Events.hasPrompt(ev, c)
            if ready == true then
                local weight = math.max(1, math.floor(Events.weightOf(ev, c) * 10))
                picks[#picks + 1] = { ev = ev, weight = weight }
                total = total + weight
            elseif ready == nil then
                outcome = "loading"
            elseif outcome == "noevent" then
                outcome = "noprompt"
            end
        end
    end
    return picks, total, outcome
end

function Events.pick(picks, total)
    local roll = Events.rand(total)
    for _, row in ipairs(picks) do
        roll = roll - row.weight
        if roll < 0 then return row.ev end
    end
    return picks[#picks].ev
end

function Events.queued(c)
    local st = c.st
    local id = st.queue[1]
    if id == nil then return nil end
    local ev, why = People.event(id)
    if ev == nil then
        if why ~= "loading" then table.remove(st.queue, 1) end
        return nil
    end
    local ready = nil
    if Events.refusal(ev, c, true) == nil then
        ready = Events.hasPrompt(ev, c)
        if ready == nil then return nil end
        if ready then
            table.remove(st.queue, 1)
            st.tries = 0
            return ev
        end
    end
    st.tries = st.tries + 1
    if st.tries >= Events.settings.queueTries then
        table.remove(st.queue, 1)
        st.tries = 0
    end
    return nil
end

function Events.trimCooldowns(cd, hours, keep)
    local rows, spent = {}, {}
    for id, untilHours in pairs(cd) do
        if (tonumber(untilHours) or 0) <= hours then
            spent[#spent + 1] = id
        else
            rows[#rows + 1] = id
        end
    end
    for _, id in ipairs(spent) do cd[id] = nil end
    table.sort(rows, function(a, b) return cd[a] < cd[b] end)
    while #rows > keep do
        cd[table.remove(rows, 1)] = nil
    end
end

function Events.persist(uid, key, ev, hours, opens)
    local keep = Events.settings.cooldownKeep
    return Instance.write(uid, function(memory)
        local q = type(memory.evq) == "table" and memory.evq or {}
        memory.evq = q
        local cd = type(q.cd) == "table" and q.cd or {}
        q.cd = cd
        cd[ev.id] = Instance.hours(hours + ev.cooldownHours)
        Events.trimCooldowns(cd, hours, keep)
        q.last, q.n, q.lk = Instance.hours(hours), (tonumber(q.n) or 0) + 1, ev.kind
        if opens then q.open = { id = ev.id, since = Instance.hours(hours) } else q.open = nil end
        local person = memory.person
        if ev.once and type(person) == "table" then Instance.setFlag(Instance.vt(person, key, true), Events.onceFlag(ev.id)) end
    end)
end

function Events.notify(record, player, key)
    local party = ProjectALife.Party
    if not Events.settings.notice or party == nil or type(party.notice) ~= "function" then return false end
    local names = ProjectALife.Names
    local name = nil
    if names ~= nil and type(names.shown) == "function" then name = (names.shown(record, key)) end
    if type(name) ~= "string" or name == "" then name = "Your guest" end
    return party.notice(player, name .. " asked you something. Open Talk.") == true
end

function Events.deliver(v, record, player, ev, c)
    local shell = Talk.shellOf(v.uid)
    local env = Talk.env(player, record, c.nowMs, shell, { inside = true, insideSec = c.st.insideSec })
    if env.key == nil or env.person == nil then return false, "nokey" end
    local choices, valid = Events.choicesOf(ev)
    local words = Talk.speakKey(env, ev.id .. ".prompt", nil)
    if words == nil then return false, "nosay" end
    local ok = Events.persist(v.uid, c.key, ev, c.hours, #choices > 0)
    local row = Events.playerRow(c.key)
    row.lastMs = c.nowMs
    row.stamps[#row.stamps + 1] = c.nowMs
    local m = Events.metrics
    m.fired, m.lastEvent = m.fired + 1, ev.id
    if #choices > 0 and ok then
        local timeoutMs = math.max(5, tonumber(ev.timeoutSec) or 45) * 1000
        Events.open[v.uid] = { id = ev.id, key = c.key, sinceMs = c.nowMs, untilMs = c.nowMs + timeoutMs, extends = 0,
            prompt = string.sub(words, 1, Events.settings.promptMax), choices = choices, valid = valid, kind = ev.kind,
            privacy = ev.adultOnly == true or ev.tags.privacy == true }
        Events.notify(record, player, c.key)
    end
    Events.why[v.uid] = "fired"
    m.lastWhy = "fired"
    if not ok then return true, "write_failed" end
    return true, ev.id
end

function Events.run(v, nowMs, options, only, force)
    local uid = v.uid
    local st = Events.stateOf(uid, nowMs)
    st.nextMs = nowMs + Events.settings.evalMs
    Events.metrics.evals = Events.metrics.evals + 1
    local record = Talk.recordOf(uid) or v.record
    v.record = record
    local why = Events.gateVisitor(v, record, nowMs)
    if why ~= nil then return Events.deny(uid, why) end
    if Events.open[uid] ~= nil then return Events.deny(uid, "open") end
    local player, reason = Events.gateInside(v, record, st, nowMs, force)
    if player == nil then return Events.deny(uid, reason) end
    local key = Rules.playerKey(player)
    if key == nil then return Events.deny(uid, "nokey") end
    reason = Events.gateSafe(record, player, nowMs)
    if reason ~= nil then return Events.deny(uid, reason) end
    if not force then
        reason = Events.gatePacing(uid, key, nowMs, options)
        if reason == nil then reason = Events.gateNear(v, record, st, player, nowMs) end
        if reason ~= nil then return Events.deny(uid, reason) end
    end
    local c, loading = Events.context(v, record, player, st, key, nowMs, options, force)
    if c == nil then return Events.deny(uid, loading) end
    if only ~= nil then
        local refused = Events.refusal(only, c, true)
        if refused ~= nil then return Events.deny(uid, refused) end
        local ready = Events.hasPrompt(only, c)
        if ready == nil then return Events.deny(uid, "loading") end
        if ready == false then return Events.deny(uid, "noprompt") end
        return Events.deliver(v, record, player, only, c)
    end
    local chosen = Events.queued(c)
    if chosen == nil then
        local events, waiting = People.events()
        if events == nil then return Events.deny(uid, waiting == "loading" and "loading" or "noevent") end
        local picks, total, outcome = Events.weigh(c, Events.window(c, events))
        if #picks == 0 then return Events.deny(uid, outcome) end
        chosen = Events.pick(picks, total)
    end
    local ok, result = Events.deliver(v, record, player, chosen, c)
    if not ok then return Events.deny(uid, result) end
    return ok, result
end

function Events.fire(uid, eventId, force)
    if Events.clientSide() then return false, "client" end
    local ev, why = People.event(eventId)
    if ev == nil then return Events.deny(uid, tostring(why or "unknown_event")) end
    local list = Events.visitors(uid)
    if list[1] == nil then return Events.deny(uid, "notinside") end
    return Events.run(list[1], Events.nowMs() or 0, Rules.options(), ev, force == true)
end

function Events.answer(player, uid, eventId, choiceIndex)
    return Talk.answerEvent(player, uid, eventId, choiceIndex)
end

function Events.beforeAnswer(player, uid, eventId, choiceIndex)
    local open = Events.open[uid]
    if open == nil or open.id ~= eventId then return false, "not_open" end
    if Rules.playerKey(player) ~= open.key then return false, "not_yours" end
    local index = tonumber(choiceIndex) or 0
    if index ~= 0 and open.valid[index] ~= true then return false, "invalid_choice" end
    return true
end

function Events.afterAnswer(player, uid, eventId, choiceIndex, result)
    local open = Events.open[uid]
    Events.open[uid] = nil
    local m = Events.metrics
    if open ~= nil and open.timedOut == true then
        m.timeouts = m.timeouts + 1
    elseif (tonumber(choiceIndex) or 0) == 0 then
        m.dismissed = m.dismissed + 1
    else
        m.answered = m.answered + 1
    end
    Events.dropSaved(uid)
    if type(result) ~= "table" or type(result.actions) ~= "table" then return 0 end
    local ctx = { uid = uid, record = Talk.recordOf(uid), player = player, event = eventId, choice = choiceIndex }
    for _, text in ipairs(result.actions) do Actions.run(ctx, text) end
    return #result.actions
end

function Events.cancel(uid)
    Events.open[uid] = nil
    Events.metrics.dropped = Events.metrics.dropped + 1
    return Events.dropSaved(uid)
end

function Events.expire(uid, nowMs)
    local open = Events.open[uid]
    if open == nil then return false end
    local talk = ProjectALife.Talk
    if open.extends < Events.settings.extendMax and talk ~= nil and type(talk.sessionOpenFor) == "function"
            and talk.sessionOpenFor(uid) then
        open.untilMs, open.extends = nowMs + Events.settings.extendMs, open.extends + 1
        return false
    end
    local record = Talk.recordOf(uid)
    local player = record ~= nil and Events.playerByKey(record, open.key) or nil
    if player == nil or open.privacy then
        Events.cancel(uid)
        return true
    end
    open.timedOut = true
    if not Talk.answerEvent(player, uid, open.id, 0) then Events.cancel(uid) end
    return true
end

function Events.sweepOpen(nowMs)
    local due = {}
    for uid, open in pairs(Events.open) do
        if nowMs >= open.untilMs then due[#due + 1] = uid end
    end
    for _, uid in ipairs(due) do Events.expire(uid, nowMs) end
    return #due
end

function Events.sweepState(list)
    local live, gone = {}, {}
    for _, v in ipairs(list) do live[v.uid] = true end
    for uid in pairs(Events.state) do
        if not live[uid] then gone[#gone + 1] = uid end
    end
    for _, uid in ipairs(gone) do
        Events.state[uid] = nil
        Events.why[uid] = nil
    end
    gone = {}
    for uid in pairs(Events.open) do
        if not live[uid] then gone[#gone + 1] = uid end
    end
    for _, uid in ipairs(gone) do Events.cancel(uid) end
end

function Events.dropStale(v, st)
    if not st.fresh then return false end
    st.fresh = false
    local q = v.record.memory.evq
    if type(q) ~= "table" or q.open == nil or Events.open[v.uid] ~= nil then return false end
    Events.dropSaved(v.uid)
    Events.metrics.dropped = Events.metrics.dropped + 1
    return true
end

function Events.due(list, nowMs)
    local count = #list
    for offset = 1, count do
        local position = (Events.cursor + offset - 1) % count + 1
        local st = Events.state[list[position].uid]
        if st == nil or st.nextMs <= nowMs then
            Events.cursor = position
            return list[position]
        end
    end
    return nil
end

function Events.tick(nowMs)
    nowMs = tonumber(nowMs) or Events.nowMs()
    if nowMs == nil or nowMs < Events.nextAtMs or Events.clientSide() then return 0 end
    Events.nextAtMs = nowMs + Events.settings.passMs
    local began = Events.stamp()
    local m = Events.metrics
    m.passes = m.passes + 1
    local work = Events.sweepOpen(nowMs)
    local list = Events.visitors(nil)
    Events.sweepState(list)
    for _, v in ipairs(list) do Events.dropStale(v, Events.stateOf(v.uid, nowMs)) end
    local v = #list > 0 and Events.due(list, nowMs) or nil
    if v ~= nil then
        local options = Rules.options()
        if options.proactive == false or options.persons == false then
            Events.stateOf(v.uid, nowMs).nextMs = nowMs + Events.settings.evalMs
            Events.deny(v.uid, "off")
        else
            Events.run(v, nowMs, options, nil, false)
        end
        work = work + 1
    end
    local took = Events.stamp() - began
    m.ms = m.ms + took
    if took > m.maxMs then m.maxMs = took end
    return work
end

function Events.enqueue(record, id)
    if type(record) ~= "table" or type(record.uid) ~= "string" or type(id) ~= "string" or string.match(id, "^VE_[%w_]+$") == nil then
        return false
    end
    local st = Events.stateOf(record.uid, Events.nowMs() or 0)
    for _, queued in ipairs(st.queue) do
        if queued == id then return false end
    end
    if #st.queue >= Events.settings.queueMax then return false end
    st.queue[#st.queue + 1] = id
    Events.metrics.queued = Events.metrics.queued + 1
    return true
end

function Events.pendingFor(record, player)
    local open = type(record) == "table" and Events.open[record.uid] or nil
    if open == nil or Rules.playerKey(player) ~= open.key then return nil end
    return { id = open.id, prompt = open.prompt, choices = open.choices, cancel = true, untilMs = open.untilMs }
end

function Events.install()
    if Talk.adapters.pending == nil then Talk.adapters.pending = Events.pendingFor end
    return true
end
Events.install()

function Events.reset()
    Events.state, Events.open, Events.players, Events.why, Events.reasons = {}, {}, {}, {}, {}
    Events.nextAtMs, Events.cursor = 0, 0
    for key, value in pairs(Events.metrics) do Events.metrics[key] = type(value) == "number" and 0 or "-" end
    Actions.reset()
end

function Events.qaLine()
    local m = Events.metrics
    local names = {}
    for name in pairs(Events.reasons) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if Events.reasons[a] ~= Events.reasons[b] then return Events.reasons[a] > Events.reasons[b] end
        return a < b
    end)
    local parts = {}
    for position = 1, math.min(#names, 6) do parts[position] = names[position] .. ":" .. tostring(Events.reasons[names[position]]) end
    local open = 0
    for _ in pairs(Events.open) do open = open + 1 end
    local a = Actions.metrics
    return "[ALIFE-QA] VisitorEvents: passes=" .. tostring(m.passes) .. " evals=" .. tostring(m.evals) .. " fired=" .. tostring(m.fired)
        .. " answered=" .. tostring(m.answered) .. " dismissed=" .. tostring(m.dismissed) .. " timeouts=" .. tostring(m.timeouts)
        .. " dropped=" .. tostring(m.dropped) .. " open=" .. tostring(open) .. " queued=" .. tostring(m.queued)
        .. " approached=" .. tostring(m.approached) .. " actions=" .. tostring(a.ok) .. "/" .. tostring(a.refused)
        .. " deferred=" .. tostring(a.deferred) .. " last=" .. tostring(m.lastEvent) .. " why=" .. tostring(m.lastWhy)
        .. " refusals=" .. (#parts > 0 and table.concat(parts, ",") or "-") .. " maxMs=" .. tostring(m.maxMs)
end

return Events
