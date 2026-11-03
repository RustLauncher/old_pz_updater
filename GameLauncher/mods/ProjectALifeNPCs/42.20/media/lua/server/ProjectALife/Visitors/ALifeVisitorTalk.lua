require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorText"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorLedger"
require "ProjectALife/Visitors/ALifeVisitorTalkRules"
require "ProjectALife/Visitors/ALifeVisitorReact"
require "ProjectALife/Visitors/ALifeVisitorFlirt"
require "ProjectALife/Visitors/ALifeVisitorBooks"
require "ProjectALife/Visitors/ALifeVisitorLines"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Text = ProjectALife.VisitorText
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Ledger = ProjectALife.VisitorLedger
local Rules = ProjectALife.VisitorTalkRules
local React = ProjectALife.VisitorReact
local Flirt = ProjectALife.VisitorFlirt
local Books = ProjectALife.VisitorBooks
local Lines = ProjectALife.VisitorLines

local VT = {
    adapters = {},
    sessions = {},
    sessionCount = 0,
    metrics = { asked = 0, answered = 0, deflected = 0, unknown = 0, refused = 0, loading = 0, committed = 0,
        commitFailed = 0, doors = 0, reactions = 0, events = 0, skippedAnim = 0 },
}
ProjectALife.VisitorTalk = VT

VT.menuHidden = { VQ_REACT_UNKNOWN = true, VQ_REACT_GIFT = true }
VT.reactKinds = { VQ_REACT_INSULT = "insult", VQ_REACT_THREAT = "threat", VQ_REACT_COMPLIMENT = "compliment" }
VT.offerCats = { FOOD = "food", DRINK = "water", BLANKET = "blanket", CLOTHES = "clothes", COAT = "clothes", SHOES = "clothes",
    MEDS = "meds", BANDAGE = "meds", BOOK = "book", SMOKES = "smokes", ALCOHOL = "alcohol", TOOL = "tool", BATTERIES = "tool",
    CANDLE = "tool", MAP = "tool", GLASSES = "tool" }
VT.offerActions = { BED = "offered_bed", SOAP = "offered_bath", WORK = false, CARDS = false }
VT.offerNotes = { food = "gave_food", water = "gave_water", blanket = "gave_blanket", clothes = "gave_clothes",
    meds = "gave_meds", book = "gave_book", smokes = "gave_smokes", alcohol = "gave_alcohol", tool = "gave_tool" }
VT.tabLabels = { talk = "Talk", past = "Past", now = "Now", house = "House", world = "World", offer = "Offer", closer = "Closer" }
VT.tabOrder = { "talk", "past", "now", "house", "world", "offer", "closer" }
VT.limits = { rows = 60, label = 80, bytes = 3800, newMs = 60000, boundaryMinutes = 10, lockDayHours = 24, sessions = 24, idleMs = 600000 }

function VT.nowMs()
    if type(VT.adapters.nowMs) == "function" then return VT.adapters.nowMs() end
    return Rules.nowMs()
end

function VT.recordOf(uid)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(uid) ~= "string" then return nil end
    if type(registry.peek) == "function" then return registry.peek(uid) end
    if type(registry.read) == "function" then return registry.read(uid) end
    return nil
end

function VT.shellOf(uid)
    local talk = ProjectALife.Talk
    if talk == nil or type(talk.shellFor) ~= "function" then return nil end
    return talk.shellFor(uid)
end

function VT.session(uid, key, nowMs)
    local id = tostring(uid) .. ":" .. tostring(key)
    local session = VT.sessions[id]
    if session ~= nil and nowMs - (session.last or nowMs) > VT.limits.idleMs and nowMs >= session.last then
        VT.endSession(uid, key)
        session = nil
    end
    if session == nil then
        if VT.sessionCount >= VT.limits.sessions then VT.sessions, VT.sessionCount = {}, 0 end
        session = { opened = nowMs, last = nowMs, rev = 0, sig = "", shown = {}, initial = nil, defl = {}, locks = {},
            personal = {}, personalCount = 0, repeated = false, misses = 0, spoken = {} }
        VT.sessions[id] = session
        VT.sessionCount = VT.sessionCount + 1
    end
    session.last = nowMs
    return session
end

function VT.endSession(uid, key)
    local id = tostring(uid) .. ":" .. tostring(key)
    if VT.sessions[id] ~= nil then
        VT.sessions[id] = nil
        VT.sessionCount = math.max(0, VT.sessionCount - 1)
    end
    React.endConversation(uid, key)
end

function VT.env(player, record, nowMs, shell, extra)
    local env = Rules.env(record, player, nowMs, extra)
    env.shell = shell
    if env.person ~= nil and env.key ~= nil then
        env.session = VT.session(env.uid, env.key, env.nowMs)
        if env.session.insideSince == nil and Rules.inside(env) then env.session.insideSince = env.nowMs end
    end
    local speech = ProjectALife.Speech
    env.psex = speech ~= nil and type(speech.sexOf) == "function" and speech.sexOf(player) or nil
    env.known = Lines.namesKnow(record, env.key)
    return env
end

function VT.freshEnv(env)
    return VT.env(env.player, VT.recordOf(env.uid) or env.record, env.nowMs, env.shell, env.extra)
end

function VT.render(text, person, player)
    return Lines.render(text, person, player)
end

function VT.rowCopy(row)
    if type(row) ~= "table" then return { k = "", a = "", f = "", u = 0, n = 0, last = 0 } end
    return { k = row.k or "", a = row.a or "", f = row.f or "", u = row.u or 0, n = row.n or 0, last = row.last or 0 }
end

function VT.dropAsked(row, short)
    local kept, found = {}, false
    for _, piece in ipairs(Schema.split(row.a or "", ";")) do
        local id = string.match(piece, "^([%w_]+):%d+:%d+$")
        if id == short then found = true else kept[#kept + 1] = piece end
    end
    if found then row.a = table.concat(kept, ";") end
    return found
end

function VT.deflCount(row, short)
    return (Instance.asked(row, "d_" .. short))
end

function VT.newPlan(env)
    return { row = VT.rowCopy(Rules.row(env)), needs = {}, ops = {}, locks = {}, events = {}, ledgerFlags = {}, ledgerFacts = {},
        gsets = {}, learned = {}, notes = {} }
end

VT.fx = {}

function VT.fx.set(env, plan, arg)
    local name = string.match(arg, "^flag:([%w_]+)$")
    if name ~= nil then Instance.setFlag(plan.row, name) end
end

function VT.fx.clr(env, plan, arg)
    local name = string.match(arg, "^flag:([%w_]+)$")
    if name ~= nil then Instance.clearFlag(plan.row, name) end
end

function VT.fx.gset(env, plan, arg)
    local name = string.match(arg, "^gflag:([%w_]+)$")
    if name ~= nil then plan.gsets[#plan.gsets + 1] = name end
end

function VT.fx.reveal(env, plan, arg)
    local index = Rules.factIndex(env, arg)
    if index == nil then return end
    if Instance.learn(plan.row, index) then
        plan.learned[#plan.learned + 1] = arg
        plan.ledgerFacts[#plan.ledgerFacts + 1] = index
    end
end

function VT.fx.op(env, plan, arg)
    local delta, why = string.match(arg, "^([+-]%d+)%s*(.*)$")
    if delta == nil then return end
    plan.ops[#plan.ops + 1] = { delta = tonumber(delta), why = why }
end

function VT.fx.need(env, plan, arg)
    local name, delta = string.match(arg, "^(%a+)%s+([+-]%d+)$")
    if name == nil or Instance.needKey(name) == nil then return end
    local base = plan.needs[name]
    if base == nil then base = Instance.need(env.person, name) end
    plan.needs[name] = Schema.clampInt(base + tonumber(delta), 0, Schema.NEED_MAX, base)
end

function VT.fx.mood(env, plan, arg)
    if string.match(arg, "^%a+$") ~= nil then plan.mood = arg end
end

function VT.fx.next(env, plan, arg)
    if string.match(arg, "^VQ_[%w_]+$") ~= nil then Instance.setFlag(plan.row, "N_" .. Lines.shortOf(arg)) end
end

function VT.fx.lock(env, plan, arg)
    local qid, minutes = string.match(arg, "^(VQ_[%w_]+)%s+(%d+)$")
    if qid ~= nil then plan.locks[#plan.locks + 1] = { q = qid, minutes = tonumber(minutes) } end
end

function VT.fx.anim(env, plan, arg)
    if string.match(arg, "^[%w_]+$") ~= nil then plan.anim = arg end
end

function VT.fx.give(env, plan, arg)
    local item = string.match(arg, "^carry:(Base%.[%w_]+)$")
    if item ~= nil then plan.give = item end
end

function VT.fx.ask(env, plan, arg)
    if string.match(arg, "^wn_[%w_]+$") ~= nil then plan.askWant = arg end
end

function VT.fx.ev(env, plan, arg)
    if string.match(arg, "^VE_[%w_]+$") ~= nil then plan.events[#plan.events + 1] = arg end
end

function VT.fx.arc(env, plan, arg)
    local stay = string.match(arg, "^stay%s+([+-]%d+)$")
    if stay ~= nil then plan.stay = (plan.stay or 0) + tonumber(stay) end
    local leave = string.match(arg, "^leave%s+([%a_]+)$")
    if leave ~= nil and Schema.LEAVE_REASONS[leave] then plan.leave = leave end
end

function VT.fx.ledger(env, plan, arg)
    if string.match(arg, "^[%w_]+$") ~= nil then plan.ledgerFlags[#plan.ledgerFlags + 1] = arg end
end

function VT.effects(env, plan, list)
    for _, effect in ipairs(list or {}) do
        local handler = VT.fx[effect.verb]
        if handler ~= nil then handler(env, plan, effect.arg) end
    end
end

function VT.commit(env, plan)
    local key = env.key
    local hours = React.hours()
    local ok, why = Instance.write(env.uid, function(memory)
        local person = memory.person
        if type(person) ~= "table" then return end
        local row = Instance.vt(person, key, true)
        row.k, row.a, row.f = plan.row.k, plan.row.a, plan.row.f
        row.last = Instance.hours(hours)
        if plan.mood ~= nil then person.mood = plan.mood end
        for name, value in pairs(plan.needs) do Instance.setNeed(person, name, value) end
        if plan.stay ~= nil then person.sx = (tonumber(person.sx) or 0) + plan.stay / 60 end
        if plan.leave ~= nil then person.lv = plan.leave end
        if plan.ti ~= nil and person.ti == nil then person.ti = plan.ti end
    end)
    if ok then
        VT.metrics.committed = VT.metrics.committed + 1
    else
        VT.metrics.commitFailed = VT.metrics.commitFailed + 1
    end
    return ok, why
end

function VT.gflags(names)
    local store = Ledger.store()
    if type(store) ~= "table" then return end
    if type(store.vflags) ~= "table" then store.vflags = {} end
    local count = 0
    for _ in pairs(store.vflags) do count = count + 1 end
    for _, name in ipairs(names) do
        if store.vflags[name] == nil and count < 40 then
            store.vflags[name] = 1
            count = count + 1
        end
    end
    Ledger.dirty()
end

function VT.animate(env, preset)
    if type(VT.adapters.anim) == "function" then return VT.adapters.anim(env.shell, preset, env.record) end
    local fence, animations = ProjectALife.AIFence, ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" or env.shell == nil then return false end
    if fence ~= nil and type(fence.drivesBody) == "function" and fence.drivesBody(env.shell) ~= true then
        VT.metrics.skippedAnim = VT.metrics.skippedAnim + 1
        return false
    end
    return animations.apply(env.shell, preset) == true
end

function VT.schedule(env, events, result)
    result.events = events
    if type(VT.adapters.schedule) == "function" then return VT.adapters.schedule(env.record, events) end
    local scheduler = ProjectALife.VisitorEvents
    if scheduler ~= nil and type(scheduler.enqueue) == "function" then
        for _, id in ipairs(events) do scheduler.enqueue(env.record, id) end
    end
    return true
end

function VT.afterEffects(env, plan, result)
    local session = env.session
    local person = env.person
    if #plan.ledgerFacts > 0 or #plan.ledgerFlags > 0 then
        Ledger.note(person.id, env.key, { facts = plan.ledgerFacts, flags = plan.ledgerFlags })
    end
    if #plan.gsets > 0 then VT.gflags(plan.gsets) end
    for _, lock in ipairs(plan.locks) do session.locks[lock.q] = env.hours + lock.minutes / 60 end
    for _, op in ipairs(plan.ops) do
        local extra = { delta = op.delta, why = op.why ~= "" and op.why or nil }
        local applied = React.note("node", VT.recordOf(env.uid) or env.record, env.player, extra)
        result.opinion = (result.opinion or 0) + applied
    end
    for _, note in ipairs(plan.notes) do
        local applied = React.note(note.kind, VT.recordOf(env.uid) or env.record, env.player, note.extra)
        result.opinion = (result.opinion or 0) + applied
    end
    if plan.anim ~= nil then VT.animate(env, plan.anim) end
    if plan.give ~= nil then result.give = plan.give end
    if plan.askWant ~= nil then result.ask = plan.askWant end
    if #plan.events > 0 then VT.schedule(env, plan.events, result) end
    if #plan.learned > 0 then result.learned = plan.learned end
    if plan.leave ~= nil then result.leave = plan.leave end
end

function VT.speakNear(env)
    local visit = ProjectALife.SafehouseVisit
    if visit == nil or type(visit.nearUid) ~= "function" then return nil end
    local uid = env.uid
    return function(listener) return visit.nearUid(uid, listener) end
end

function VT.say(env, text, beats)
    local speech = ProjectALife.Speech
    local shell = env.shell
    if shell == nil or speech == nil or text == nil then return false end
    local rendered = speech.render(text, {}, shell, env.psex)
    if rendered == nil or not speech.say(shell, rendered, { face = env.player, scope = "visitor", near = VT.speakNear(env) }) then
        return false
    end
    if beats ~= nil and #beats > 0 then
        local talk = ProjectALife.Talk
        local queue = {}
        for position = 1, #beats do
            queue[position] = { afterMs = beats[position].afterMs, t = speech.render(beats[position].t, {}, shell, env.psex) }
        end
        if talk ~= nil and type(talk.sequence) == "function" then
            talk.sequence(env.record, shell, env.player, { beats = queue }, {})
        end
    end
    return true, rendered
end

function VT.checkIntro(env, plan, qid)
    local card = Rules.card(env)
    if card == nil or env.known then return false end
    local reveal = card.name.reveal
    local open = false
    if reveal == "intro" then
        open = qid == "VQ_TALK_NAME"
    elseif card.name.revealOk then
        env.rowOverride = plan.row
        open = (Rules.test(env, reveal))
        env.rowOverride = nil
    end
    if not open then return false end
    Instance.setFlag(plan.row, "intro")
    plan.introduce = true
    return true
end

function VT.introduce(env)
    local talk, names = ProjectALife.Talk, ProjectALife.Names
    if names == nil or type(names.markIntroduced) ~= "function" or env.key == nil then return false end
    local key = env.key
    if talk ~= nil and type(talk.writeMemory) == "function" then
        talk.writeMemory(env.uid, function(memory) names.markIntroduced(memory, key) end)
    end
    env.known = true
    return true
end

function VT.deflectText(env, question, found, tier, band, count, plan)
    local order = {}
    if found ~= nil and found.list ~= nil then order[#order + 1] = found.list end
    for _, scope in ipairs(Lines.scopes(env)) do
        if found == nil or found.scope ~= scope then
            local list, why = People.nodes(scope, question.id)
            if list == nil and why == "loading" then return nil, "loading" end
            if list ~= nil then order[#order + 1] = list end
        end
    end
    for _, list in ipairs(order) do
        local node = list.defl[tier]
        if node ~= nil then
            local lines = node.lines.any
            if #lines == 0 then lines = Lines.bandLines(node.lines, band) end
            for step = 0, #lines - 1 do
                local rendered = Lines.render(lines[(count + step) % #lines + 1], env.person, env.player, env)
                if rendered ~= nil then
                    if tier == 1 then VT.effects(env, plan, node.fx) end
                    return rendered, "node"
                end
            end
        end
    end
    local text, why = Lines.pick(env, "VP_DEFLECT_" .. Lines.styleOf(env), band, count, tier)
    if text ~= nil then return text, "style" end
    if why == "loading" then return nil, "loading" end
    text, why = Lines.pick(env, "VP_DONTKNOW", band, count)
    if text ~= nil then return text, "dontknow" end
    return nil, why
end

function VT.deflect(env, question, found, plan)
    local session = env.session
    local short = Lines.shortOf(question.id)
    local hours = env.hours
    local entry = session.defl[question.id]
    local tier = 1
    if entry ~= nil and hours >= entry.at and hours - entry.at <= VT.limits.boundaryMinutes / 60 then
        tier = math.min(entry.tier + 1, 3)
    end
    local band = Rules.band(Rules.trust(env))
    local count = VT.deflCount(Rules.row(env), short)
    local text, source = VT.deflectText(env, question, found, tier, band, count, plan)
    if text == nil then return nil, nil, source end
    session.defl[question.id] = { at = hours, tier = tier, paid = tier > 1 }
    Instance.noteAsked(plan.row, "d_" .. short, 0)
    if tier == 2 then plan.notes[#plan.notes + 1] = { kind = "deflect_again" } end
    if tier == 3 then
        plan.notes[#plan.notes + 1] = { kind = "pushed" }
        plan.locks[#plan.locks + 1] = { q = question.id, minutes = VT.limits.lockDayHours * 60 }
    end
    return text, tier, source
end

function VT.sweep(env)
    local session = env.session
    if session == nil then return 0 end
    local granted = 0
    local limit = VT.limits.boundaryMinutes / 60
    for qid, entry in pairs(session.defl) do
        if entry.paid ~= true and entry.tier == 1 and env.hours - entry.at >= limit then
            entry.paid = true
            local flag = "B_" .. Lines.shortOf(qid)
            if not Instance.flag(Rules.row(env), flag) then
                local applied = React.note("boundary_respected", VT.recordOf(env.uid) or env.record, env.player, nil)
                Instance.write(env.uid, function(memory)
                    local who = memory.person
                    if type(who) == "table" then Instance.setFlag(Instance.vt(who, env.key, true), flag) end
                end)
                if applied ~= 0 then granted = granted + 1 end
            end
        end
    end
    return granted
end

function VT.locked(env, qid)
    local session = env.session
    local untilHours = session ~= nil and session.locks[qid] or nil
    if untilHours == nil then return false end
    if env.hours >= untilHours then
        session.locks[qid] = nil
        return false
    end
    return true
end

function VT.hasNeed(env, token)
    if token == nil or token == "" then return true end
    if token == "book" then return Books.has(env) end
    local card = Rules.card(env)
    if card == nil then return false end
    for _, fact in ipairs(card.facts) do
        if fact.kind == token then return true end
    end
    return false
end

function VT.visible(env, question)
    local person = env.person
    if person == nil or VT.menuHidden[question.id] == true or question.kind == "visit" then return false end
    if not People.mayAsk(person.id, question.id) then return false end
    if question.adultOnly and not Rules.adult(env) then return false end
    if question.needs ~= nil and not VT.hasNeed(env, question.needs) then return false end
    if Flirt.isFlirt(question) and not Flirt.rowOk(env, question) then return false end
    if VT.locked(env, question.id) then return false end
    if Instance.flag(Rules.row(env), "N_" .. Lines.shortOf(question.id)) then return true end
    if question.visibility == "open" then return true end
    if question.see == nil then return false end
    return (Rules.test(env, question.see))
end

function VT.statusOf(env, question)
    local row = Rules.row(env)
    if (Instance.asked(row, question.id)) > 0 then return "asked" end
    if VT.deflCount(row, Lines.shortOf(question.id)) > 0 then
        local found = Lines.lookup(env, question.id)
        if found ~= nil and found.node ~= nil then return "new" end
        return "later"
    end
    local session = env.session
    if session ~= nil and session.initial ~= nil and session.initial[question.id] ~= true then
        local seen = session.shown[question.id] or env.nowMs
        if env.nowMs - seen < VT.limits.newMs then return "new" end
    end
    return "open"
end

function VT.answerable(env, question)
    if question.kind == "offer" and VT.offerCats[string.match(question.id, "^VQ_OFFER_(%w+)$") or ""] ~= nil then
        return true
    end
    if Flirt.isFlirt(question) then
        local out, why = VT.flirt(env, question, true)
        return out ~= nil, why
    end
    local found, why = Lines.lookup(env, question.id)
    if found == nil then return nil, why end
    local band = Rules.band(Rules.trust(env))
    local count = Instance.asked(Rules.row(env), question.id)
    local plan = VT.newPlan(env)
    if found.locked and found.node == nil then
        local entry = env.session.defl[question.id]
        local tier = 1
        if entry ~= nil and env.hours >= entry.at and env.hours - entry.at <= VT.limits.boundaryMinutes / 60 then
            tier = math.min(entry.tier + 1, 3)
        end
        local text, reason = VT.deflectText(env, question, found, tier, band,
            VT.deflCount(Rules.row(env), Lines.shortOf(question.id)), plan)
        return text ~= nil, reason
    end
    local revealing = env.revealing
    env.revealing = VT.willReveal(env, question)
    local out, reason = VT.resolveAnswer(env, question, found, plan, band, count)
    env.revealing = revealing
    return out ~= nil, reason
end

function VT.rowsOf(env)
    local questions, why = People.questions()
    if questions == nil then return nil, why end
    local rows = {}
    for position = 1, #questions do
        local question = questions[position]
        if VT.visible(env, question) then
            local available, reason = VT.answerable(env, question)
            if available then rows[#rows + 1] = { q = question, st = VT.statusOf(env, question) } end
            if reason == "loading" then return nil, "loading" end
        end
    end
    return rows
end

function VT.labelOf(env, question)
    local count = Instance.asked(Rules.row(env), question.id)
    return string.sub(question.labels[count % #question.labels + 1], 1, VT.limits.label)
end

function VT.tabsOf(rows)
    local counts, fresh, tabs = {}, {}, {}
    for position = 1, #rows do
        local tab = rows[position].q.tab
        counts[tab] = (counts[tab] or 0) + 1
        if rows[position].st == "new" then fresh[tab] = (fresh[tab] or 0) + 1 end
    end
    for _, id in ipairs(VT.tabOrder) do
        if counts[id] ~= nil then tabs[#tabs + 1] = { id = id, label = VT.tabLabels[id], count = counts[id], new = fresh[id] or 0 } end
    end
    return tabs, counts
end

function VT.header(env, record, player)
    local names, opinion = ProjectALife.Names, ProjectALife.NpcOpinion
    local name = nil
    if names ~= nil and type(names.shown) == "function" then name = (names.shown(record, env.key)) end
    local payload = opinion ~= nil and type(opinion.payload) == "function" and opinion.payload(record, player) or nil
    return { name = name, desc = Rules.card(env).desc, opinion = payload, mood = env.person.mood, lines = {} }
end

function VT.menu(player, record, options)
    local person = Instance.of(record)
    if person == nil then return nil, "not_visitor" end
    options = options or {}
    local env = VT.env(player, record, options.nowMs, nil, options.extra)
    if env.key == nil then return nil, "no_player_key" end
    if Rules.card(env) == nil then
        local _, why = People.card(person.id)
        return nil, why or "loading"
    end
    VT.sweep(env)
    local rows, why = VT.rowsOf(env)
    if rows == nil then return nil, why end
    local session = env.session
    if session.initial == nil then
        session.initial = {}
        for position = 1, #rows do session.initial[rows[position].q.id] = true end
    end
    local parts = {}
    for position = 1, #rows do
        local id = rows[position].q.id
        if session.shown[id] == nil then session.shown[id] = env.nowMs end
        parts[position] = id .. rows[position].st
    end
    local signature = table.concat(parts, ",")
    if signature ~= session.sig then
        session.sig = signature
        session.rev = session.rev + 1
    end
    local tabs, counts = VT.tabsOf(rows)
    local open = options.tab
    if open == nil or counts[open] == nil then open = tabs[1] ~= nil and tabs[1].id or nil end
    local out, bytes = {}, 0
    for position = 1, #rows do
        local row = rows[position]
        if row.q.tab == open and #out < VT.limits.rows then
            local label = VT.labelOf(env, row.q)
            bytes = bytes + #label + #row.q.id + #row.st + 40
            if bytes > VT.limits.bytes then break end
            out[#out + 1] = { id = row.q.id, tab = row.q.tab, label = label, st = row.st }
        end
    end
    local menu = { v = 1, rev = session.rev, tab = open, header = VT.header(env, record, player), tabs = tabs, rows = out }
    if type(VT.adapters.pending) == "function" then menu.pending = VT.adapters.pending(record, player) end
    return menu
end

function VT.normalize(text)
    local lowered = string.lower(tostring(text or ""))
    lowered = string.gsub(lowered, "'", "")
    lowered = string.gsub(lowered, "[^a-z0-9]+", " ")
    lowered = string.gsub(lowered, "^%s+", "")
    lowered = string.gsub(lowered, "%s+$", "")
    return lowered
end

function VT.patternIndex()
    local questions = People.questions()
    if questions == nil then return nil end
    return Text.memo(Schema.FILES.questions, "vtpatterns", function()
        local list = {}
        for position = 1, #questions do
            local question = questions[position]
            for _, pattern in ipairs(question.patterns) do
                local clean = VT.normalize(pattern)
                if #clean >= 3 then list[#list + 1] = { id = question.id, text = " " .. clean .. " ", size = #clean } end
            end
        end
        return list
    end)
end

function VT.classify(text)
    local clean = VT.normalize(text)
    if clean == "" then return nil, 0 end
    local list = VT.patternIndex()
    if list == nil then return nil, 0 end
    local hay = " " .. clean .. " "
    local best, bestScore = nil, 0
    for position = 1, #list do
        local entry = list[position]
        if entry.size > bestScore and string.find(hay, entry.text, 1, true) ~= nil then
            best, bestScore = entry.id, entry.size
        end
    end
    return best, bestScore
end

function VT.answerNode(env, question, found, plan, band, count)
    local node = found.node
    local short = Lines.shortOf(question.id)
    local nodeShort = found.alt > 1 and (short .. "_a" .. found.alt) or short
    local nodeCount = count
    if found.alt > 1 then nodeCount = (Instance.asked(Rules.row(env), nodeShort)) end
    local text, index, kind = Lines.compose(env, node, band, nodeCount)
    if text == nil then return nil end
    local out = { kind = "answer", text = text, variant = index, line = kind, node = node, scope = found.scope,
        nodeShort = nodeShort, firstUse = nodeCount == 0 }
    out.beats = Lines.beatsOf(env, node, band, kind)
    if out.firstUse then VT.effects(env, plan, node.fx) end
    return out
end

function VT.willReveal(env, question)
    local card = Rules.card(env)
    if card == nil or env.known then return false end
    local reveal = card.name.reveal
    if reveal == "intro" then return question.id == "VQ_TALK_NAME" end
    if not card.name.revealOk then return false end
    local row = VT.rowCopy(Rules.row(env))
    Instance.noteAsked(row, question.id, 1)
    env.rowOverride = row
    local open = (Rules.test(env, reveal))
    env.rowOverride = nil
    return open
end

function VT.resolveAnswer(env, question, found, plan, band, count)
    local out = nil
    if found.node ~= nil then out = VT.answerNode(env, question, found, plan, band, count) end
    if out ~= nil then return out end
    if question.kind == "book" or question.id == "VQ_HOUSE_BOOK" then
        local text, index = Books.answer(env, question.id, count)
        local rendered = text ~= nil and Lines.render(text, env.person, env.player, env) or nil
        if rendered ~= nil then return { kind = "answer", text = rendered, variant = index, source = "book" } end
    end
    local text, index = Lines.pick(env, "VP_" .. Lines.shortOf(question.id), band, count)
    if text ~= nil then return { kind = "answer", text = text, variant = index, source = "pool" } end
    local fallback = Lines.pick(env, "VP_DONTKNOW", band, count)
    if fallback ~= nil then return { kind = "answer", text = fallback, variant = 1, source = "dontknow" } end
    return nil, index == "loading" and "loading" or "no_answer"
end

function VT.resolve(env, question, options)
    options = options or {}
    if Rules.card(env) == nil then return nil, "loading" end
    local band = Rules.band(Rules.trust(env))
    local count = options.count
    if count == nil then count = (Instance.asked(Rules.row(env), question.id)) end
    local plan = VT.newPlan(env)
    for _, note in ipairs(options.notes or {}) do plan.notes[#plan.notes + 1] = note end
    local found, why = Lines.lookup(env, question.id)
    if found == nil then return nil, why end
    local out = nil
    if found.locked and found.node == nil then
        local text, tier, source = VT.deflect(env, question, found, plan)
        if text == nil then return nil, source == "loading" and "loading" or "no_deflection" end
        out = { kind = "deflect", text = text, tier = tier, source = source }
    else
        env.revealing = VT.willReveal(env, question)
        out, why = VT.resolveAnswer(env, question, found, plan, band, count)
        env.revealing = false
        if out == nil then return nil, why end
    end
    out.qid, out.plan, out.band, out.count = question.id, plan, band, count
    return out
end

function VT.afterAnswer(env, question, out)
    local plan = out.plan
    local short = Lines.shortOf(question.id)
    local session = env.session
    if out.kind ~= "answer" then return end
    if out.flirt ~= nil and not out.flirt.accept then return end
    Instance.noteAsked(plan.row, question.id, out.variant or 1)
    if out.nodeShort ~= nil and out.nodeShort ~= short then Instance.noteAsked(plan.row, out.nodeShort, out.variant or 1) end
    VT.dropAsked(plan.row, "d_" .. short)
    session.defl[question.id] = nil
    VT.checkIntro(env, plan, question.id)
    if out.count > 0 then
        session.repeated = true
        if question.cost >= 1 and out.count >= 4 then plan.notes[#plan.notes + 1] = { kind = "repeat_unwanted" } end
    end
    if out.count == 0 and (question.tab == "past" or question.tab == "now") and session.personal[question.id] == nil then
        session.personal[question.id] = true
        session.personalCount = session.personalCount + 1
        if session.personalCount == 3 and not session.repeated then plan.notes[#plan.notes + 1] = { kind = "listened" } end
    end
    local reactKind = VT.reactKinds[question.id]
    if reactKind ~= nil then plan.notes[#plan.notes + 1] = { kind = reactKind } end
end

function VT.gate(player, record, shell, nowMs)
    local speech, talk = ProjectALife.Speech, ProjectALife.Talk
    if speech == nil or talk == nil then return false, "unavailable" end
    if type(speech.authoritative) == "function" and not speech.authoritative() then return false, "unavailable" end
    if type(speech.alive) == "function" and not speech.alive(player) then return false, "unavailable" end
    if type(talk.busy) == "function" and talk.busy(record, nowMs) then return false, "busy" end
    if shell == nil then return false, "unavailable" end
    if type(talk.talkable) == "function" and not talk.talkable(shell, record) then return false, "busy" end
    if type(talk.stance) == "function" and talk.stance(record, player) == "hostile" then return false, "hostile" end
    local visit = ProjectALife.SafehouseVisit
    if visit ~= nil and type(visit.live) == "function" and visit.live(record.uid) ~= nil then
        if type(visit.doorPeer) ~= "function" or visit.doorPeer(player, record.uid) == nil then return false, "not_door_peer" end
    end
    return true
end

function VT.stampEntry(env, plan)
    local memory = type(env.record) == "table" and env.record.memory or nil
    local guest = type(memory) == "table" and memory.guest or nil
    if env.person.ti == nil and type(guest) == "table" then plan.ti = tonumber(guest.renewedHours) or env.hours end
end

function VT.finish(env, question, out)
    local plan = out.plan
    VT.stampEntry(env, plan)
    VT.afterAnswer(env, question, out)
    local ok, why = VT.commit(env, plan)
    if not ok then return false, "write_failed:" .. tostring(why) end
    local spoken, rendered = VT.say(env, out.text, out.beats)
    local result = { ok = true, id = question.id, kind = out.kind, words = rendered or out.text, said = spoken == true,
        variant = out.variant, tier = out.tier, source = out.source or (out.node ~= nil and "node" or nil), band = out.band,
        line = out.line }
    if plan.introduce then VT.introduce(env) end
    VT.afterEffects(env, plan, result)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.hold) == "function" then talk.hold(env.record, env.shell, env.player, env.nowMs) end
    if out.kind == "answer" then VT.metrics.answered = VT.metrics.answered + 1 end
    if out.kind == "deflect" then VT.metrics.deflected = VT.metrics.deflected + 1 end
    return true, result
end

function VT.speakKey(env, nodeKey, poolId)
    local session = env.session
    local count = session ~= nil and session.spoken[nodeKey] or 0
    local band = Rules.band(Rules.trust(env))
    local text, beats = nil, nil
    local found = Lines.lookup(env, nodeKey)
    if found ~= nil and found.node ~= nil then
        local line, _, kind = Lines.compose(env, found.node, band, count)
        if line ~= nil then
            text, beats = line, Lines.beatsOf(env, found.node, band, kind)
        end
    end
    if text == nil and poolId ~= nil then text = Lines.pick(env, poolId, band, count) end
    if text == nil then return nil end
    if session ~= nil then session.spoken[nodeKey] = count + 1 end
    local spoken, rendered = VT.say(env, text, beats)
    if not spoken then return nil end
    return rendered
end

function VT.reaction(player, uid, kind, extra)
    local record = VT.recordOf(uid)
    if record == nil or Instance.of(record) == nil then return 0, nil end
    local shell = VT.shellOf(uid)
    local applied, info = React.note(kind, record, player, extra)
    VT.metrics.reactions = VT.metrics.reactions + 1
    local env = VT.env(player, VT.recordOf(uid), nil, shell, nil)
    local words = VT.speakKey(env, "react." .. kind, "VP_REACT_" .. string.upper(kind))
    return applied, words, info
end

function VT.offerItem(player, record, question, cat, args, env)
    if args == nil or args.gift == nil then
        local offer = { kind = cat }
        if type(VT.adapters.picker) == "function" then offer.picker = VT.adapters.picker(player, record, cat) end
        return true, "", { ok = true, id = question.id, offer = offer }
    end
    local give = VT.adapters.give
    if type(give) ~= "function" then return false, "offer_unavailable", {} end
    local ok, info = give(player, record, cat, args)
    if not ok then return false, tostring(info or "offer_refused"), {} end
    local extra = type(info) == "table" and info or {}
    local noteKind = VT.offerNotes[cat]
    local applied, words = 0, nil
    if noteKind ~= nil then
        applied = React.note(noteKind, VT.recordOf(record.uid) or record, player, extra)
        words = VT.speakKey(VT.freshEnv(env), "react." .. noteKind, "VP_REACT_" .. string.upper(noteKind))
    end
    if cat == "book" then
        Instance.write(record.uid, function(memory)
            local who = memory.person
            if type(who) == "table" then Books.lend(env, Instance.vt(who, env.key, true), extra) end
        end)
    end
    return true, words or "", { ok = true, id = question.id, gift = cat, opinion = applied, words = words }
end

function VT.flirt(env, question, preview)
    local decision = Flirt.decide(env, question, env.session, preview)
    if decision.refused ~= nil then return nil, decision.refused end
    if decision.accept and decision.step == "keep" then
        local own = Lines.lookup(env, question.id)
        if own ~= nil and own.node ~= nil then return VT.resolve(env, question, nil) end
        decision.node, decision.pool = "closer.f" .. decision.stage .. "_open", "VP_CLOSER_F" .. decision.stage .. "_OPEN"
    end
    local plan = VT.newPlan(env)
    for _, name in ipairs(decision.set or {}) do Instance.setFlag(plan.row, name) end
    for _, name in ipairs(decision.clr or {}) do Instance.clearFlag(plan.row, name) end
    if decision.note ~= nil then plan.notes[#plan.notes + 1] = { kind = decision.note } end
    local band = Rules.band(Rules.trust(env))
    local key, pool = decision.node, decision.pool
    if decision.close then
        key, pool = "closer.close_track", "VP_CLOSER_CLOSE_TRACK"
    elseif decision.accept == false then
        key, pool = "closer.decline_" .. decision.decline, "VP_CLOSER_DECLINE_" .. string.upper(decision.decline)
    end
    local text, beats = nil, nil
    local count = env.session.spoken[key] or 0
    local found, why = Lines.lookup(env, key)
    if found == nil and why == "loading" then return nil, "loading" end
    if found ~= nil and found.node ~= nil then
        local line, _, kind = Lines.compose(env, found.node, band, count)
        if line ~= nil then text, beats = line, Lines.beatsOf(env, found.node, band, kind) end
    end
    if text == nil then text, why = Lines.pick(env, pool, band, count) end
    if text == nil then return nil, why == "loading" and "loading" or "no_answer" end
    if not preview then env.session.spoken[key] = count + 1 end
    return { kind = "answer", text = text, beats = beats, variant = 1, source = "flirt", flirt = decision, qid = question.id,
        plan = plan, band = band, count = 0 }
end

function VT.choose(player, uid, questionId, args)
    VT.metrics.asked = VT.metrics.asked + 1
    local record = VT.recordOf(uid)
    if record == nil or Instance.of(record) == nil then return false, "not_visitor", {} end
    local question, why = People.question(questionId)
    if question == nil then return false, why == "loading" and "loading" or "unknown_question", {} end
    local shell = VT.shellOf(uid)
    local nowMs = VT.nowMs()
    local allowed, reason = VT.gate(player, record, shell, nowMs)
    if not allowed then return false, reason, {} end
    local mayAsk, askWhy = People.mayAsk(Instance.of(record).id, questionId)
    if not mayAsk then
        VT.metrics.refused = VT.metrics.refused + 1
        return false, askWhy or "refused", {}
    end
    local env = VT.env(player, record, nowMs, shell, nil)
    if env.key == nil then return false, "no_player_key", {} end
    if Rules.card(env) == nil then
        VT.metrics.loading = VT.metrics.loading + 1
        return false, "loading", {}
    end
    VT.sweep(env)
    if not VT.visible(env, question) then
        if Flirt.afterNo(env, question) then
            local applied = React.note("flirt_after_no", record, player, nil)
            local words = VT.speakKey(VT.freshEnv(env), "closer.close_track", "VP_CLOSER_CLOSE_TRACK")
            return true, words or "", { ok = true, id = questionId, kind = "closed", opinion = applied, words = words }
        end
        VT.metrics.refused = VT.metrics.refused + 1
        return false, "visitor_row_stale", {}
    end
    local options = nil
    if question.kind == "offer" then
        local suffix = string.match(question.id, "^VQ_OFFER_(%w+)$") or ""
        local cat = VT.offerCats[suffix]
        local action = VT.offerActions[suffix]
        if cat ~= nil then
            local ok, words, result = VT.offerItem(player, record, question, cat, args, env)
            return ok, words, result
        end
        if action then options = { notes = { { kind = action } } } end
    end
    local out, outWhy
    if Flirt.isFlirt(question) then
        out, outWhy = VT.flirt(env, question)
    else
        out, outWhy = VT.resolve(env, question, options)
    end
    if out == nil then
        if outWhy == "loading" then
            VT.metrics.loading = VT.metrics.loading + 1
            return false, "loading", {}
        end
        return false, outWhy or "no_answer", {}
    end
    env.session.lastFlirt = out.flirt ~= nil and out.flirt.kindOf or nil
    local okFinish, result = VT.finish(env, question, out)
    if not okFinish then return false, result, {} end
    if out.flirt ~= nil then result.flirt = out.flirt.step end
    return true, result.words, result
end

function VT.unknown(env)
    local session = env.session
    local question = People.question("VQ_REACT_UNKNOWN")
    if question == nil then return nil end
    session.misses = session.misses + 1
    local out = VT.resolve(env, question, { count = session.misses - 1 })
    if out == nil or out.text == nil then return nil end
    local spoken, rendered = VT.say(env, out.text, out.beats)
    if not spoken then return nil end
    VT.metrics.unknown = VT.metrics.unknown + 1
    return rendered
end

function VT.doorIntent(text, choiceId)
    local intents = ProjectALife.TalkIntents
    if intents == nil or type(intents.doorFor) ~= "function" then return nil end
    return intents.doorFor(text, choiceId)
end

function VT.door(player, listener, intent, env)
    local visit = ProjectALife.SafehouseVisit
    if visit == nil or type(visit.choose) ~= "function" then return nil, "unavailable" end
    VT.metrics.doors = VT.metrics.doors + 1
    local uid = listener.record.uid
    local accepted, words = visit.choose(player, uid, intent)
    if not accepted then return nil, words end
    if (intent == "DOOR_GIVE" or intent == "DOOR_TREAT") and type(visit.giftView) == "function" and visit.giftView(player, uid) ~= nil then
        return words, "gift_select"
    end
    VT.say(env, words, nil)
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.noteDoor) == "function" then opinion.noteDoor(intent, listener.record, player) end
    return words, "door_answered"
end

VT.memoryOrder = { "stole_from", "threatened", "lied_to", "refused_door", "healed", "sheltered", "gave_food", "shared_meal" }

function VT.greet(player, record, shell, nowMs)
    local env = VT.env(player, record, nowMs, shell, nil)
    if env.key == nil or env.session.greeted then return nil end
    local who = Ledger.who(env.person.id, env.key)
    local entry = Ledger.entry(env.person.id)
    local visits = entry ~= nil and tonumber(entry.n) or 0
    if visits < 1 then return nil end
    env.session.greeted = true
    local flags = who ~= nil and who.flags or {}
    for _, memory in ipairs(VT.memoryOrder) do
        for _, name in ipairs(flags) do
            if name == memory then
                local words = VT.speakKey(env, "return." .. memory, "VP_RETURN_" .. string.upper(memory))
                if words ~= nil then return words end
            end
        end
    end
    return VT.speakKey(env, "return.arrive", "VP_RETURN_ARRIVE")
end

function VT.respond(player, listener, text, now, choiceId)
    local record, shell = listener.record, listener.shell
    local nowMs = tonumber(now) or VT.nowMs()
    local allowed, reason = VT.gate(player, record, shell, nowMs)
    if not allowed then return nil, reason end
    local env = VT.env(player, record, nowMs, shell, nil)
    local door = VT.doorIntent(text, choiceId)
    if door ~= nil then return VT.door(player, listener, door, env) end
    if choiceId == "NPC_OPEN" or choiceId == "GREETING" then
        local words = VT.greet(player, record, shell, nowMs)
        if words ~= nil then return words, "answered" end
        return nil, "menu"
    end
    if type(choiceId) == "string" and string.sub(choiceId, 1, 3) == "EV:" then
        local event, index = string.match(choiceId, "^EV:([%w_]+):(%d+)$")
        if event == nil then return nil, "invalid_choice" end
        local ok, words = VT.answerEvent(player, record.uid, event, tonumber(index))
        if ok then return words, "event_answered" end
        return nil, "invalid_choice"
    end
    local qid = nil
    if type(choiceId) == "string" and string.sub(choiceId, 1, 3) == "VQ_" then
        qid = choiceId
    elseif text ~= nil then
        qid = VT.classify(text)
    end
    if qid == nil then return VT.unknown(env), "unknown" end
    local ok, words, result = VT.choose(player, record.uid, qid, nil)
    if ok and (words == nil or words == "") then return nil, result.offer ~= nil and "offer" or "answered" end
    if ok then return words, result.kind == "deflect" and "deflected" or "answered" end
    if words == "visitor_row_stale" and choiceId == nil then return VT.unknown(env), "unknown" end
    return nil, words
end

function VT.eventEffects(event, choiceIndex)
    local raw = event.raw or {}
    local source = raw.to
    if choiceIndex ~= nil and choiceIndex > 0 then
        local choice = type(raw.ch) == "table" and raw.ch[choiceIndex] or nil
        source = type(choice) == "table" and choice.fx or nil
    end
    local effects, actions = {}, {}
    for _, text in ipairs(Schema.texts(source)) do
        local verb, rest = string.match(text, "^(%a+)%s*(.-)$")
        if verb == "do" then
            actions[#actions + 1] = rest
        elseif verb ~= nil and Schema.EFFECT_VERBS[verb] then
            effects[#effects + 1] = { verb = verb, arg = rest }
        end
    end
    return effects, actions
end

function VT.answerEvent(player, uid, eventId, choiceIndex)
    local record = VT.recordOf(uid)
    if record == nil or Instance.of(record) == nil then return false, "not_visitor" end
    local event, why = People.event(eventId)
    if event == nil then return false, why or "unknown_event" end
    local shell = VT.shellOf(uid)
    local env = VT.env(player, record, nil, shell, nil)
    if env.key == nil then return false, "no_player_key" end
    if Rules.card(env) == nil then return false, "loading" end
    if event.adultOnly and not Rules.adult(env) then return false, "adult_only" end
    local scheduler = ProjectALife.VisitorEvents
    if scheduler ~= nil and type(scheduler.beforeAnswer) == "function" then
        local allowed, reason = scheduler.beforeAnswer(player, uid, eventId, choiceIndex)
        if not allowed then return false, reason or "not_open" end
    end
    local plan = VT.newPlan(env)
    local effects, actions = VT.eventEffects(event, choiceIndex)
    VT.effects(env, plan, effects)
    VT.stampEntry(env, plan)
    local ok, commitWhy = VT.commit(env, plan)
    if not ok then return false, "write_failed:" .. tostring(commitWhy) end
    local result = { ok = true, event = eventId, choice = choiceIndex, actions = actions }
    VT.afterEffects(env, plan, result)
    local key = (choiceIndex ~= nil and choiceIndex > 0) and tostring(choiceIndex) or "timeout"
    local words = VT.speakKey(VT.freshEnv(env), eventId .. ".reply." .. key, nil)
    if scheduler ~= nil and type(scheduler.afterAnswer) == "function" then
        scheduler.afterAnswer(player, uid, eventId, choiceIndex, result)
    end
    VT.metrics.events = VT.metrics.events + 1
    return true, words, result
end

function VT.command(player, args)
    local speech = ProjectALife.Speech
    local uid = tostring(type(args) == "table" and args.uid or "")
    local choice = type(args) == "table" and args.choice or nil
    local sessionId = type(args) == "table" and args.sessionId or nil
    local reply = { uid = uid, ok = false, reason = "unavailable", sessionId = sessionId,
        playerKey = speech ~= nil and type(speech.playerKey) == "function" and speech.playerKey(player) or nil }
    local record = VT.recordOf(uid)
    if record == nil or Instance.of(record) == nil then
        reply.reason = "not_visitor"
        return reply
    end
    local ok, words, result = false, "invalid_choice", {}
    if choice == "NPC_OPEN" or choice == "GREETING" then
        local greeting = VT.greet(player, record, VT.shellOf(uid), VT.nowMs())
        ok, words = true, greeting
    elseif type(choice) == "string" and string.sub(choice, 1, 3) == "VQ_" then
        ok, words, result = VT.choose(player, uid, choice, args.args)
    elseif type(choice) == "string" and string.sub(choice, 1, 3) == "EV:" then
        local event, index = string.match(choice, "^EV:([%w_]+):(%d+)$")
        if event ~= nil then ok, words, result = VT.answerEvent(player, uid, event, tonumber(index)) end
    end
    reply.ok = ok == true
    if ok then
        reply.reason, reply.text = "answered", words
        if type(result) == "table" then
            reply.offer, reply.give, reply.ask, reply.leave, reply.delta = result.offer, result.give, result.ask, result.leave, result.opinion
        end
    else
        reply.reason = tostring(words)
    end
    local menu = VT.menu(player, VT.recordOf(uid) or record, { tab = type(args) == "table" and args.tab or nil })
    reply.visitorMenu = menu
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.attach) == "function" then opinion.attach(reply, uid, player) end
    return reply
end

function VT.witness(uid, scope, id, playerKey)
    if (scope ~= "wit" and scope ~= "pwit") or type(id) ~= "string" or string.match(id, "^[%w_]+$") == nil then return false end
    local prefix = scope == "wit" and "W_" or "P_"
    return Instance.write(uid, function(memory)
        local who = memory.person
        if type(who) == "table" then Instance.setFlag(Instance.vt(who, playerKey, true), prefix .. id) end
    end)
end

function VT.prefetch(personId)
    People.warm()
    local card = People.card(personId)
    if card == nil then return false end
    People.nodes(personId, "VQ_TALK_HOWARE")
    People.questions()
    return true
end

function VT.ctx(record, player, now, extra)
    local env = VT.env(player, record, now, nil, extra)
    return Rules.ctx(env), env
end

function VT.qaLine()
    local m = VT.metrics
    return "[ALIFE-QA] VisitorTalk asked=" .. tostring(m.asked) .. " answered=" .. tostring(m.answered)
        .. " deflected=" .. tostring(m.deflected) .. " unknown=" .. tostring(m.unknown) .. " refused=" .. tostring(m.refused)
        .. " loading=" .. tostring(m.loading) .. " committed=" .. tostring(m.committed)
        .. " commitFailed=" .. tostring(m.commitFailed) .. " sessions=" .. tostring(VT.sessionCount)
end

function VT.reset()
    VT.sessions, VT.sessionCount = {}, 0
    React.clear()
    Rules.reset()
end

return VT
