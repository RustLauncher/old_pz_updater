require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorLedger"
require "ProjectALife/Decisions/ALifeNpcOpinion"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Ledger = ProjectALife.VisitorLedger

local React = {
    adapters = {},
    state = {},
    stateCount = 0,
    metrics = { notes = 0, applied = 0, capped = 0, refused = 0, repeated = 0 },
    defaults = { capConversation = 6, capDay = 12, ceiling = 40 },
}
ProjectALife.VisitorReact = React

React.events = {
    gave_food = { delta = 10, why = "You fed them.", class = "deed", hourly = true, cat = "food", did = "fed", memory = "gave_food" },
    gave_water = { delta = 6, why = "You gave them something to drink.", class = "deed", hourly = true, cat = "water" },
    gave_meds = { delta = 12, why = "You got them medicine.", class = "deed", cat = "meds", did = "healed", memory = "healed" },
    gave_clothes = { delta = 7, why = "You gave them something to wear.", class = "deed", cat = "clothes" },
    gave_blanket = { delta = 4, why = "You gave them a blanket.", class = "deed", cat = "blanket" },
    gave_book = { delta = 5, why = "You lent them a book.", class = "deed", cat = "book" },
    gave_smokes = { delta = 6, why = "You gave them cigarettes.", class = "deed", cat = "smokes", vice = "tobacco" },
    gave_alcohol = { delta = 6, why = "You gave them a drink.", class = "deed", cat = "alcohol", vice = "alcohol", adult = true },
    gave_tool = { delta = 2, why = "You lent them a tool.", class = "deed", cat = "tool" },
    offered_bed = { delta = 6, why = "You offered them a bed.", class = "deed", memory = "sheltered" },
    offered_bath = { delta = 5, why = "You offered them a wash.", class = "deed" },
    shared_meal = { delta = 5, why = "You shared a meal.", class = "deed", memory = "shared_meal" },
    promise_kept = { delta = 8, why = "You kept your word.", class = "deed", did = "kept_promise" },
    promise_broken = { delta = -15, why = "You broke your word.", class = "deed", did = "broke_promise" },
    robbed = { delta = -30, why = "You took from their bag.", class = "deed", public = true, did = "robbed", memory = "stole_from" },
    privacy_lingered = { delta = -12, why = "You watched them when you should not have.", class = "deed", adult = true },
    threat = { delta = -20, why = "You threatened them.", class = "deed", did = "threatened", memory = "threatened", mood = true },
    weapon_drawn = { delta = -40, why = "You aimed a weapon at them.", class = "deed", finish = "cancelled", mood = "scared" },
    event_timeout = { delta = -2, why = "You left their question hanging.", class = "deed" },
    tv_off = { delta = -3, why = "You switched it off on them.", class = "deed" },
    listened = { delta = 3, why = "You listened.", class = "word", session = 1, ceiling = true },
    boundary_respected = { delta = 1, why = "You let it drop when they asked.", class = "word" },
    compliment = { delta = 1, why = "You were kind to them.", class = "word", session = 2, did = "complimented", ceiling = true },
    honest_answer = { delta = 1, why = "You answered them straight.", class = "word" },
    repeat_unwanted = { delta = -2, why = "You kept asking the same thing.", class = "word" },
    pushed = { delta = -4, why = "You pushed when they said no.", class = "word" },
    deflect_again = { delta = -1, why = "You asked again.", class = "word" },
    insult = { delta = -6, why = "You were rude to them.", class = "word", did = "insulted", mood = "hot" },
    flirt_accepted = { delta = 3, why = "They liked the attention.", class = "word", adult = true },
    flirt_declined = { delta = 0, why = "You took no for an answer.", class = "word", adult = true },
    flirt_after_no = { delta = -10, why = "You kept at it after they said no.", class = "deed", adult = true },
    node = { delta = 0, why = "They told you something.", class = "word" },
    event_choice = { delta = 0, why = "You answered them.", class = "word" },
}

React.speed = { 0.5, 0.75, 1.0, 1.15, 1.3, 1.5 }


function React.register()
    local opinion = ProjectALife.NpcOpinion
    if opinion == nil or type(opinion.events) ~= "table" then return 0 end
    local count = 0
    for kind, entry in pairs(React.events) do
        opinion.events["v_" .. kind] = { entry.delta, entry.why }
        if entry.public == true and type(opinion.public) == "table" then opinion.public["v_" .. kind] = true end
        count = count + 1
    end
    return count
end

React.register()

function React.config()
    local config = { capConversation = React.defaults.capConversation, capDay = React.defaults.capDay,
        ceiling = React.defaults.ceiling }
    local social = ProjectALife.TalkSocial
    if social ~= nil and type(social.config) == "function" then
        local ok, found = pcall(social.config)
        if ok and type(found) == "table" then
            config.capConversation = tonumber(found.capConversation) or config.capConversation
            config.capDay = tonumber(found.capDay) or config.capDay
            config.ceiling = tonumber(found.ceiling) or config.ceiling
        end
    end
    config.capConversationNeg = math.ceil(config.capConversation * 1.5)
    config.capDayNeg = math.ceil(config.capDay * 1.5)
    return config
end

function React.hours()
    if type(React.adapters.hours) == "function" then return tonumber(React.adapters.hours()) or 0 end
    if type(getGameTime) ~= "function" then return 0 end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return 0 end
    return tonumber(clock:getWorldAgeHours()) or 0
end

function React.sessionOf(uid, key)
    local id = tostring(uid) .. ":" .. tostring(key)
    local row = React.state[id]
    if row == nil then
        if React.stateCount >= 48 then React.state, React.stateCount = {}, 0 end
        row = { cp = 0, cm = 0, dp = 0, dm = 0, day = -1, hourly = {}, counts = {} }
        React.state[id] = row
        React.stateCount = React.stateCount + 1
    end
    return row
end

function React.clear()
    React.state, React.stateCount = {}, 0
end

function React.endConversation(uid, key)
    local row = React.state[tostring(uid) .. ":" .. tostring(key)]
    if row == nil then return end
    row.cp, row.cm, row.counts = 0, 0, {}
end

function React.speedOf(card)
    local value = card ~= nil and card.traits.trustSpeed or 2
    return React.speed[math.max(0, math.min(5, value)) + 1]
end

function React.baseDelta(kind, entry, person, card, extra)
    local base = entry.delta
    if extra ~= nil and extra.delta ~= nil then return tonumber(extra.delta) or 0 end
    if kind == "gave_food" then
        local hunger = Instance.need(person, "hunger")
        if hunger >= 3 then return 10 end
        if hunger == 2 then return 7 end
        return 5
    end
    if kind == "gave_clothes" then
        if Instance.need(person, "cold") >= 3 or Instance.need(person, "dirty") >= 4 then return 7 end
        return 2
    end
    if kind == "gave_book" then
        if extra ~= nil and extra.liked == true then return 5 end
        return 2
    end
    if entry.vice ~= nil then
        if card ~= nil and card.vice == entry.vice then return 6 end
        return 2
    end
    if kind == "honest_answer" and extra ~= nil and extra.amount ~= nil then
        return math.max(1, math.min(3, math.floor(tonumber(extra.amount) or 1)))
    end
    return base
end

function React.limit(entry, kind, delta, state, config, standing, hours)
    local day = math.floor(hours / 24)
    if state.day ~= day then state.day, state.dp, state.dm = day, 0, 0 end
    if entry.hourly == true then
        local last = state.hourly[kind]
        if last ~= nil and hours - last < 1 and hours >= last then return 0, "hourly" end
    end
    if entry.session ~= nil and (state.counts[kind] or 0) >= entry.session then return 0, "session" end
    if entry.class ~= "word" or delta == 0 then return delta, nil end
    if delta > 0 then
        local room = math.min(config.capConversation - state.cp, config.capDay - state.dp)
        if entry.ceiling == true then room = math.min(room, config.ceiling - standing) end
        local allowed = math.max(0, math.min(delta, room))
        if allowed ~= delta then return allowed, "capped" end
        return allowed, nil
    end
    local room = math.min(config.capConversationNeg - state.cm, config.capDayNeg - state.dm)
    local allowed = -math.max(0, math.min(-delta, room))
    if allowed ~= delta then return allowed, "capped" end
    return allowed, nil
end

function React.account(entry, kind, applied, state, hours)
    if entry.class == "word" then
        if applied > 0 then
            state.cp, state.dp = state.cp + applied, state.dp + applied
        elseif applied < 0 then
            state.cm, state.dm = state.cm - applied, state.dm - applied
        end
    end
    state.counts[kind] = (state.counts[kind] or 0) + 1
    if entry.hourly == true then state.hourly[kind] = hours end
end

function React.moodFor(entry, card)
    if entry.mood == true then
        if card ~= nil and card.traits.temper >= 4 then return "hot" end
        return "scared"
    end
    if entry.mood == "hot" and card ~= nil and card.traits.temper >= 4 then return "hot" end
    if type(entry.mood) == "string" and entry.mood ~= "hot" then return entry.mood end
    return nil
end

function React.persist(uid, key, kind, entry, person, mood, leave)
    local flags = {}
    if entry.cat ~= nil then flags[#flags + 1] = "G_" .. entry.cat end
    if entry.did ~= nil then flags[#flags + 1] = "D_" .. entry.did end
    if kind == "gave_smokes" or kind == "gave_alcohol" then flags[#flags + 1] = "enabled_vice" end
    if #flags == 0 and mood == nil and leave == nil then return true end
    return Instance.write(uid, function(memory)
        local who = memory.person
        if type(who) ~= "table" then return end
        local row = Instance.vt(who, key, true)
        for position = 1, #flags do Instance.setFlag(row, flags[position]) end
        if mood ~= nil then who.mood = mood end
        if leave ~= nil then who.lv = leave end
        row.last = Instance.hours(React.hours())
    end)
end

function React.ledgerNote(person, key, entry, kind)
    local name = entry.memory
    if name == nil and entry.cat ~= nil then name = "gave_" .. entry.cat end
    if name == nil or key == nil then return end
    Ledger.note(person.id, key, { flags = { name } })
end

function React.endVisit(record, player, outcome)
    if type(React.adapters.endVisit) == "function" then return React.adapters.endVisit(record, player, outcome) end
    local visit, director = ProjectALife.SafehouseVisit, ProjectALife.SafehouseDirector
    if visit == nil or director == nil or type(visit.live) ~= "function" or type(visit.settle) ~= "function" then return false end
    local pending, house = visit.live(record.uid)
    if pending == nil or house == nil then return false end
    visit.settle(house, pending, outcome, nil, director.hours())
    return true
end

function React.note(kind, record, player, extra)
    React.metrics.notes = React.metrics.notes + 1
    local entry = React.events[kind]
    local person = Instance.of(record)
    local opinion = ProjectALife.NpcOpinion
    if entry == nil or person == nil or player == nil or opinion == nil or type(opinion.adjust) ~= "function" then
        React.metrics.refused = React.metrics.refused + 1
        return 0, nil, "refused"
    end
    if type(opinion.enabled) == "function" and not opinion.enabled() then return 0, nil, "opinion_off" end
    local card = People.card(person.id)
    if entry.adult == true and (person.ad ~= 1 or card == nil or card.adult ~= true) then
        React.metrics.refused = React.metrics.refused + 1
        return 0, nil, "adult_only"
    end
    local key = opinion.keyOf(player)
    if key == nil then return 0, nil, "no_player_key" end
    local hours = React.hours()
    local state = React.sessionOf(record.uid, key)
    local standing = tonumber((opinion.valueOf(record, player))) or 0
    local config = React.config()
    local base = React.baseDelta(kind, entry, person, card, extra)
    local delta = base
    if delta > 0 then
        delta = opinion.rounded(delta * React.speedOf(card))
    end
    if delta ~= 0 and type(opinion.scale) == "function" then
        local scaled = delta * opinion.scale()
        delta = opinion.rounded(scaled)
    end
    local allowed, why = React.limit(entry, kind, delta, state, config, standing, hours)
    local info = { kind = kind, base = base, delta = allowed, why = why, line = entry.why }
    local reason = entry.why
    if extra ~= nil and type(extra.why) == "string" and extra.why ~= "" then reason = extra.why end
    info.reason = reason
    if allowed ~= 0 then
        if not opinion.adjust(record, player, allowed, reason) then
            React.metrics.refused = React.metrics.refused + 1
            return 0, info, "adjust_failed"
        end
        if entry.public == true and type(opinion.spreadTo) == "function" then
            opinion.spreadTo(record, player, allowed, reason, true)
        end
    elseif why == "hourly" or why == "session" then
        React.metrics.repeated = React.metrics.repeated + 1
    end
    React.account(entry, kind, allowed, state, hours)
    if why == "capped" then React.metrics.capped = React.metrics.capped + 1 end
    local mood = React.moodFor(entry, card)
    local leave = nil
    if kind == "threat" and card ~= nil and card.traits.temper >= 4 then leave = "trust_low" end
    if kind == "weapon_drawn" then leave = "trust_low" end
    info.mood, info.leave = mood, leave
    React.persist(record.uid, key, kind, entry, person, mood, leave)
    React.ledgerNote(person, key, entry, kind)
    if entry.finish ~= nil then
        info.ended = React.endVisit(record, player, entry.finish)
    end
    React.metrics.applied = React.metrics.applied + (allowed ~= 0 and 1 or 0)
    return allowed, info
end

function React.qaLine()
    local m = React.metrics
    return "[ALIFE-QA] VisitorReact notes=" .. tostring(m.notes) .. " applied=" .. tostring(m.applied)
        .. " capped=" .. tostring(m.capped) .. " repeated=" .. tostring(m.repeated) .. " refused=" .. tostring(m.refused)
end

return React
