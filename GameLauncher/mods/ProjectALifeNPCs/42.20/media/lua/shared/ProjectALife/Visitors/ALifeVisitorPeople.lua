require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorText"
require "ProjectALife/Visitors/ALifeVisitorRule"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Text = ProjectALife.VisitorText
local Rule = ProjectALife.VisitorRule
local People = {
    metrics = { indexBuilt = 0, cardsBuilt = 0, cardsRejected = 0, nodesBuilt = 0, rejected = 0, lastWhy = "-" },
    reasons = {},
}
ProjectALife.VisitorPeople = People

function People.emptyTable()
    return {}
end

function People.note(reason)
    People.metrics.lastWhy = reason
    if #People.reasons >= 20 then table.remove(People.reasons, 1) end
    People.reasons[#People.reasons + 1] = reason
end

function People.shardName(personId, prefix)
    local number = tonumber(string.match(personId, "^vp_(%d%d%d%d)$"))
    if number == nil or number < 1 then return nil end
    local shard = math.floor((number - 1) / Schema.SHARD_PEOPLE) + 1
    if shard < 10 then return prefix .. "_0" .. tostring(shard) end
    return prefix .. "_" .. tostring(shard)
end

function People.gateOk(rule)
    if rule == nil then return true end
    return Rule.parse(rule) ~= nil
end

function People.entryOf(record)
    if not Schema.validId("person", record.id) then return nil, "id_invalid" end
    local tree = Schema.unflatten(record)
    local idx, arr = tree.idx or {}, tree.arr or {}
    if (tonumber(idx.age) or Schema.MAX_AGE) < Schema.MIN_AGE then return nil, "minor_removed" end
    local age = Schema.int(idx.age, Schema.MIN_AGE, Schema.MAX_AGE)
    if age == nil then return nil, "age_invalid" end
    local sex = idx.sex
    if sex ~= "m" and sex ~= "f" then return nil, "sex_invalid" end
    local party = Schema.str(idx.party)
    if party ~= nil and not Schema.validId("party", party) then return nil, "party_invalid" end
    local arch = Schema.str(idx.arch)
    if arch ~= nil and not Schema.validId("arch", arch) then return nil, "arch_invalid" end
    local band = Schema.band(age)
    if band == "teen" and party == nil then return nil, "teen_without_party" end
    local people = Schema.str(idx.people) or People.shardName(record.id, "people")
    local nodes = Schema.str(idx.nodes) or People.shardName(record.id, "nodes")
    if not Schema.validName(people) or not Schema.validName(nodes) then return nil, "shard_invalid" end
    local arrivals = {}
    for row, weight in pairs(arr) do
        local value = tonumber(weight)
        if type(row) == "string" and value ~= nil and value > 0 then arrivals[row] = value end
    end
    return {
        id = record.id, arch = arch, sex = sex, age = age, band = band, adult = band ~= "teen", teen = band == "teen",
        party = party, people = people, nodes = nodes, dayMin = Schema.num(idx.dayMin, 0),
        dayMax = Schema.num(idx.dayMax, 99999), hourMin = tonumber(idx.hourMin), hourMax = tonumber(idx.hourMax),
        arrivals = arrivals,
    }
end

function People.archEntry(record)
    if not Schema.validId("arch", record.id) then return nil, "arch_id_invalid" end
    local idx = (Schema.unflatten(record)).idx or {}
    local nodes = Schema.str(idx.nodes) or "archetypes"
    if not Schema.validName(nodes) then return nil, "shard_invalid" end
    return { id = record.id, nodes = nodes, carrier = Schema.str(idx.carrier), carrierPool = Schema.str(idx.carrierPool),
        ageMin = Schema.int(idx.ageMin, Schema.MIN_AGE, Schema.MAX_AGE),
        ageMax = Schema.int(idx.ageMax, Schema.MIN_AGE, Schema.MAX_AGE) }
end

function People.indexParties(index)
    local drop = {}
    for partyId, party in pairs(index.parties) do
        local adults, teens = 0, 0
        for position = 1, #party.ids do
            local entry = index.people[party.ids[position]]
            if entry.teen then teens = teens + 1 else adults = adults + 1 end
        end
        party.adults, party.teens = adults, teens
        if #party.ids > Schema.MAX_PARTY or adults < 1 then drop[#drop + 1] = partyId end
    end
    for position = 1, #drop do
        local party = index.parties[drop[position]]
        for member = 1, #party.ids do index.people[party.ids[member]] = nil end
        index.parties[drop[position]] = nil
        People.note("party_invalid:" .. drop[position])
        index.rejected = index.rejected + #party.ids
    end
    if #drop > 0 then
        local kept = {}
        for position = 1, #index.order do
            local id = index.order[position]
            if index.people[id] ~= nil then kept[#kept + 1] = id end
        end
        index.order = kept
    end
end

function People.buildIndex(result)
    local index = { people = {}, order = {}, archetypes = {}, archOrder = {}, parties = {}, generic = {},
        rejected = 0, version = 1 }
    for position = 1, #result.records do
        local record = result.records[position]
        if record.kind == "person" then
            local entry, reason = People.entryOf(record)
            if entry ~= nil and index.people[entry.id] == nil then
                index.people[entry.id] = entry
                index.order[#index.order + 1] = entry.id
                if entry.party ~= nil then
                    local party = index.parties[entry.party]
                    if party == nil then
                        party = { id = entry.party, ids = {} }
                        index.parties[entry.party] = party
                    end
                    party.ids[#party.ids + 1] = entry.id
                end
            else
                index.rejected = index.rejected + 1
                People.note("index_person:" .. tostring(record.id) .. ":" .. tostring(reason or "duplicate"))
            end
        elseif record.kind == "arch" then
            local entry, reason = People.archEntry(record)
            if entry ~= nil then
                index.archetypes[entry.id] = entry
                index.archOrder[#index.archOrder + 1] = entry.id
            else
                index.rejected = index.rejected + 1
                People.note("index_arch:" .. tostring(record.id) .. ":" .. tostring(reason))
            end
        elseif record.kind == "route" and record.id == "generic" then
            local idx = (Schema.unflatten(record)).idx or {}
            local limit = math.max(1, (Text.caps.lines or 6) - 1)
            for _, shard in ipairs(Schema.csv(idx.shards)) do
                if Schema.validName(shard) and #index.generic < limit then
                    index.generic[#index.generic + 1] = shard
                elseif Schema.validName(shard) then
                    People.note("generic_route_truncated:" .. shard)
                end
            end
        end
    end
    People.indexParties(index)
    index.count = #index.order
    People.metrics.indexBuilt = People.metrics.indexBuilt + 1
    People.metrics.rejected = People.metrics.rejected + index.rejected
    return index
end

function People.reason(path)
    local _, why = Text.get(path)
    if why == "loading" or why == "not_requested" then return "loading" end
    return tostring(why)
end

function People.warm()
    return Text.ensure(Schema.FILES.index, 20)
end

function People.index()
    local path = Schema.FILES.index
    if not Text.ensure(path, 20) then return nil, People.reason(path) end
    return Text.memo(path, "index", People.buildIndex)
end

function People.party(partyId)
    local index = People.index()
    if index == nil then return nil end
    return index.parties[partyId]
end

function People.cardTraits(tree, soft)
    local source = tree.traits or {}
    local traits = {}
    for position = 1, #Schema.TRAITS do
        local axis = Schema.TRAITS[position]
        local raw = source[axis]
        local value = Schema.int(raw, 0, Schema.TRAIT_MAX)
        if value == nil then
            soft[#soft + 1] = (raw == nil and "trait_missing:" or "trait_range:") .. axis
            value = Schema.clampInt(raw, 0, Schema.TRAIT_MAX, 0)
        end
        traits[axis] = value
    end
    return traits
end

function People.cardNeeds(tree, soft)
    local source = tree.need0 or {}
    local need = {}
    for position = 1, #Schema.NEEDS do
        local name = Schema.NEEDS[position].name
        local raw = source[name]
        local value = Schema.int(raw, 0, Schema.NEED_MAX)
        if value == nil then
            soft[#soft + 1] = (raw == nil and "need_missing:" or "need_range:") .. name
            value = Schema.clampInt(raw, 0, Schema.NEED_MAX, 0)
        end
        need[name] = value
    end
    return need
end

function People.cardPairs(source, valueKey, limit)
    local result = {}
    local items = Schema.list(source)
    for position = 1, #items do
        local item = items[position]
        if type(item) == "table" and Schema.str(item.id) ~= nil and #result < limit then
            local row = { id = Schema.str(item.id), bias = Schema.bool(item.bias) }
            row[valueKey] = Schema.clampInt(item[valueKey], 1, 5, 1)
            result[#result + 1] = row
        end
    end
    return result
end

function People.cardRules(source, limit, soft, label)
    local result = {}
    local items = Schema.list(source)
    for position = 1, #items do
        local item = items[position]
        if type(item) == "table" and Schema.str(item.id) ~= nil and #result < limit then
            local row = { id = Schema.str(item.id), kind = Schema.str(item.kind), tab = Schema.str(item.tab),
                fact = Schema.str(item.fact), label = Schema.str(item.label), gate = Schema.str(item.gate) }
            row.gateOk = People.gateOk(row.gate)
            if not row.gateOk then soft[#soft + 1] = label .. "_gate:" .. row.id end
            if row.tab ~= nil and not Schema.TAB_SET[row.tab] then soft[#soft + 1] = label .. "_tab:" .. row.id end
            result[#result + 1] = row
        end
    end
    return result
end

function People.cardArc(tree)
    local source = tree.arc or {}
    local leave = {}
    for _, reason in ipairs(Schema.texts(source.leave)) do
        if Schema.LEAVE_REASONS[reason] then leave[#leave + 1] = reason end
    end
    local arrivals = {}
    for row, weight in pairs(type(source.arrivals) == "table" and source.arrivals or {}) do
        local value = tonumber(weight)
        if type(row) == "string" and value ~= nil and value > 0 then arrivals[row] = value end
    end
    return { stayMax = Schema.clampInt(source.stayMax, 1, 48, 1), leave = leave,
        returns = Schema.bool(source.returns), arrivals = arrivals }
end

function People.cardSections(tree, soft)
    local chapters = {}
    for _, item in ipairs(Schema.list(tree.chapters)) do
        if type(item) == "table" and #chapters < 8 then
            local text = Schema.str(item.text) or ""
            if #text > 240 then soft[#soft + 1] = "chapter_long:" .. tostring(item.id) end
            chapters[#chapters + 1] = { id = Schema.str(item.id), at = Schema.str(item.at), text = text }
        end
    end
    local hooks, skills, origin, look = {}, {}, {}, {}
    for key, value in pairs(type(tree.hooks) == "table" and tree.hooks or {}) do hooks[key] = Schema.str(value) end
    for key, value in pairs(type(tree.skills) == "table" and tree.skills or {}) do
        skills[key] = Schema.clampInt(value, 0, 5, 0)
    end
    for key, value in pairs(type(tree.origin) == "table" and tree.origin or {}) do origin[key] = Schema.str(value) end
    local source = type(tree.look) == "table" and tree.look or {}
    look.skin = Schema.int(source.skin, 1, 5)
    look.hair, look.hairColor = Schema.str(source.hair), Schema.str(source.hairColor)
    look.beard, look.beardColor = Schema.str(source.beard), Schema.str(source.beardColor)
    look.pace = source.pace == "walk" and "walk" or "normal"
    return chapters, hooks, skills, origin, look
end

function People.cardRoutines(tree)
    local source = type(tree.rt) == "table" and tree.rt or {}
    local result = {}
    for position = 1, 12 do
        local raw = source[position]
        local row = nil
        if type(raw) == "string" then
            local first = string.find(raw, "|", 1, true)
            local second = first ~= nil and string.find(raw, "|", first + 1, true) or nil
            if first ~= nil and second ~= nil then
                row = { hours = string.sub(raw, 1, first - 1), where = string.sub(raw, first + 1, second - 1),
                    does = string.sub(raw, second + 1) }
            end
        elseif type(raw) == "table" then
            row = { hours = raw.hours, where = raw.where, does = raw.does }
        end
        if row ~= nil and type(row.hours) == "string" then
            local from, to = string.match(row.hours, "^%s*(%d+)%s*-%s*(%d+)%s*$")
            if from == nil then from = string.match(row.hours, "^%s*(%d+)%s*$") end
            if from ~= nil then
                result[#result + 1] = { from = tonumber(from), to = tonumber(to or from),
                    where = Schema.str(row.where), does = Schema.str(row.does) }
            end
        end
    end
    return result
end

function People.normalizeCard(record)
    if type(record) ~= "table" or not Schema.validId("person", record.id) then return nil, "id_invalid" end
    local tree, soft = Schema.unflatten(record)
    local c = tree.card or {}
    if (tonumber(c.age) or Schema.MAX_AGE) < Schema.MIN_AGE then return nil, "minor_removed" end
    local age = Schema.int(c.age, Schema.MIN_AGE, Schema.MAX_AGE)
    if age == nil then return nil, "age_invalid" end
    if c.sex ~= "m" and c.sex ~= "f" then return nil, "sex_invalid" end
    local name = type(tree.name) == "table" and tree.name or {}
    if Schema.str(name.first) == nil then return nil, "name_required" end
    if Schema.str(c.desc) == nil then return nil, "desc_required" end
    local band = Schema.band(age)
    local party = Schema.str(c.party)
    local rawFlirt = tonumber(type(tree.traits) == "table" and tree.traits.flirt or 0) or 0
    if band == "teen" then
        if party == nil or not Schema.validId("party", party) then return nil, "teen_without_party" end
        if rawFlirt ~= 0 then return nil, "teen_flirt" end
    end
    if party ~= nil and not Schema.validId("party", party) then return nil, "party_invalid" end
    local arch = Schema.str(c.arch)
    if arch ~= nil and not Schema.validId("arch", arch) then return nil, "arch_invalid" end
    local reveal = Schema.str(name.reveal) or "intro"
    local vice = type(tree.vice) == "table" and Schema.str(tree.vice.kind) or "none"
    if not Schema.VICE_SET[vice] then
        soft[#soft + 1] = "vice_unknown:" .. tostring(vice)
        vice = "none"
    end
    local chapters, hooks, skills, origin, look = People.cardSections(tree, soft)
    local dress = type(tree.dress) == "table" and tree.dress or {}
    local books = type(tree.books) == "table" and tree.books or {}
    local card = {
        id = record.id, v = Schema.int(c.v, 1, 99) or 1, batch = Schema.str(c.batch), arch = arch, party = party,
        sex = c.sex, age = age, band = band, adult = band ~= "teen", desc = Schema.str(c.desc),
        voice = Schema.str(c.voice), voiceNotes = Schema.str(c.voiceNotes), seed = Schema.num(c.seed, 0),
        name = { first = Schema.str(name.first), last = Schema.str(name.last), nick = Schema.str(name.nick),
            reveal = reveal, revealOk = reveal == "intro" or People.gateOk(reveal) },
        origin = origin, look = look, traits = People.cardTraits(tree, soft), need0 = People.cardNeeds(tree, soft),
        vice = vice, beliefs = People.cardPairs(tree.beliefs, "s", 3), wants = People.cardPairs(tree.wants, "u", 4),
        skills = skills, carry = Schema.texts(tree.carry), dress = { role = Schema.str(dress.role), flags = Schema.texts(dress.flags) },
        beats = Schema.texts(tree.beats), chapters = chapters,
        secrets = People.cardRules(tree.secrets, 3, soft, "secret"), facts = People.cardRules(tree.facts, 24, soft, "fact"),
        arc = People.cardArc(tree), hooks = hooks, routines = People.cardRoutines(tree),
        books = { reads = Schema.texts(books.reads), current = Schema.str(books.current), taste = Schema.texts(books.taste) },
        soft = soft,
    }
    while #card.carry > 12 do table.remove(card.carry) end
    return card
end

function People.card(personId)
    local index, reason = People.index()
    if index == nil then
        if reason == "loading" then return nil, "loading" end
        return nil, "index_unavailable:" .. tostring(reason)
    end
    local entry = index.people[personId]
    if entry == nil then return nil, "unknown_person" end
    local path = entry.people .. ".alife"
    if not Text.ensure(path, 10) then
        local why = People.reason(path)
        if why == "loading" then return nil, "loading" end
        return nil, "shard_unavailable:" .. why
    end
    local cards = Text.memo(path, "cards", People.emptyTable)
    local row = cards[personId]
    if row == nil then
        local record = (Text.get(path)).byId[personId]
        if record == nil or record.kind ~= "person" then
            row = { why = "person_missing_in_shard" }
        else
            local card, why = People.normalizeCard(record)
            if card == nil then
                row = { why = "card_invalid:" .. tostring(why) }
            elseif card.age ~= entry.age or card.sex ~= entry.sex or card.party ~= entry.party then
                row = { why = "card_invalid:index_mismatch" }
            else
                row = { card = card }
            end
        end
        if row.card ~= nil then
            People.metrics.cardsBuilt = People.metrics.cardsBuilt + 1
        else
            People.metrics.cardsRejected = People.metrics.cardsRejected + 1
            People.note(personId .. ":" .. row.why)
        end
        cards[personId] = row
    end
    if row.card == nil then return nil, row.why end
    return row.card
end

function People.normalizeQuestion(record)
    if not Schema.validId("question", record.id) then return nil, "id_invalid" end
    local tree = Schema.unflatten(record)
    local q = tree.q or {}
    local tab, kind = Schema.str(q.tab), Schema.str(q.kind) or "ask"
    if not Schema.TAB_SET[tab or ""] then return nil, "tab_invalid" end
    if not Schema.QUESTION_KIND_SET[kind] then return nil, "kind_invalid" end
    local adult = Schema.bool(q.adult)
    local adultOnly = adult or kind == "flirt" or tab == "closer"
    if (kind == "flirt" or tab == "closer") and not adult then return nil, "adult_required" end
    local visibility = Schema.str(q.vis) or "open"
    if not Schema.VISIBILITY[visibility] then return nil, "vis_invalid" end
    local see = Schema.str(q.see)
    if visibility == "hidden" and see == nil then return nil, "see_required" end
    if see ~= nil and not People.gateOk(see) then return nil, "see_invalid" end
    local labels = Schema.texts(tree.t)
    if #labels == 0 then labels[1] = record.id end
    local patterns = {}
    for _, pattern in ipairs(Schema.split(Schema.str(q.pat) or "", "|")) do patterns[#patterns + 1] = string.lower(pattern) end
    return { id = record.id, tab = tab, kind = kind, visibility = visibility, see = see, needs = Schema.str(q.needs),
        adult = adult, adultOnly = adultOnly, cost = Schema.clampInt(q.cost, 0, 5, 1), labels = labels,
        patterns = patterns }
end

function People.buildQuestions(result)
    local set = { list = {}, byId = {}, rejected = 0 }
    for position = 1, #result.records do
        local record = result.records[position]
        if record.kind == "question" then
            local question, reason = People.normalizeQuestion(record)
            if question ~= nil and set.byId[question.id] == nil then
                set.byId[question.id] = question
                set.list[#set.list + 1] = question
            else
                set.rejected = set.rejected + 1
                People.metrics.rejected = People.metrics.rejected + 1
                People.note("question:" .. tostring(record.id) .. ":" .. tostring(reason or "duplicate"))
            end
        end
    end
    return set
end

function People.questionSet()
    local path = Schema.FILES.questions
    if not Text.ensure(path, 15) then return nil, People.reason(path) end
    return Text.memo(path, "questions", People.buildQuestions)
end

function People.questions()
    local set, reason = People.questionSet()
    if set == nil then return nil, reason end
    return set.list
end

function People.question(id)
    local set, reason = People.questionSet()
    if set == nil then return nil, reason end
    local question = set.byId[id]
    if question == nil then return nil, "unknown_question" end
    return question
end

function People.adultKey(key)
    if string.sub(key, 1, 7) == "closer." or string.sub(key, 1, 6) == "flirt." then return true end
    if string.sub(key, 1, 3) ~= "VQ_" then return false end
    local question, reason = People.question(key)
    if question == nil then return nil, reason end
    return question.adultOnly == true
end

function People.mayAsk(personId, key)
    if type(key) ~= "string" or string.match(key, "^[%w_%.]+$") == nil then return false, "key_invalid" end
    local index, reason = People.index()
    if index == nil then return false, reason end
    local entry = index.people[personId]
    if entry == nil then return false, "unknown_person" end
    local adultOnly, why = People.adultKey(key)
    if adultOnly == nil then return false, why end
    if adultOnly and not entry.adult then return false, "adult_only" end
    return true
end

function People.splitNodeId(id)
    local dot = string.find(id, ".", 1, true)
    if dot == nil then return nil end
    local scope, rest = string.sub(id, 1, dot - 1), string.sub(id, dot + 1)
    if scope ~= "generic" and not Schema.validId("person", scope) and not Schema.validId("arch", scope) then return nil end
    local tier = 0
    if string.sub(rest, 1, 3) == "VQ_" then
        local base, suffix = string.match(rest, "^(.-)%.d(%d?)$")
        if base ~= nil and base ~= "" then
            rest = base
            tier = suffix == "" and 1 or tonumber(suffix)
            if tier < 1 or tier > 3 then return nil end
        end
    end
    if rest == "" then return nil end
    return scope, rest, tier
end

function People.nodeLines(tree)
    local lines = { any = {}, lo = {}, mid = {}, hi = {}, flirt = {}, ref = {} }
    local source = type(tree.t) == "table" and tree.t or {}
    lines.any = Schema.texts(source)
    for band, value in pairs(source) do
        if type(value) == "table" then
            if band == "ref" then
                for fact, text in pairs(value) do
                    if type(fact) == "string" and Schema.str(text) ~= nil then lines.ref[fact] = Schema.str(text) end
                end
            elseif Schema.NODE_BANDS[band] then
                local items = Schema.texts(value)
                for position = 1, #items do lines[band][#lines[band] + 1] = items[position] end
            end
        end
    end
    return lines
end

function People.nodeBeats(tree)
    local beats = {}
    local source = type(tree.beat) == "table" and tree.beat or {}
    for band, value in pairs(source) do
        local items = type(value) == "table" and Schema.texts(value) or {}
        for position = 1, #items do
            local delay, line = string.match(items[position], "^(%d+)|(.+)$")
            if delay ~= nil then
                beats[#beats + 1] = { band = tostring(band), afterMs = Schema.clampInt(delay, 0, 20000, 0), text = line }
            end
        end
    end
    table.sort(beats, function(a, b)
        if a.band ~= b.band then return a.band < b.band end
        return a.afterMs < b.afterMs
    end)
    return beats
end

function People.nodeEffects(tree, soft)
    local effects = {}
    for _, text in ipairs(Schema.texts(tree.fx)) do
        local verb, rest = string.match(text, "^(%a+)%s*(.-)$")
        if verb ~= nil and Schema.EFFECT_VERBS[verb] then
            effects[#effects + 1] = { verb = verb, arg = rest, text = text }
        else
            soft[#soft + 1] = "effect_verb:" .. tostring(verb)
        end
    end
    return effects
end

function People.normalizeNode(record)
    local scope, key, tier = People.splitNodeId(record.id)
    if scope == nil then return nil, "node_id_invalid" end
    local tree, soft = Schema.unflatten(record)
    local gate = type(tree.gate) == "table" and Schema.str(tree.gate.rule) or nil
    return { id = record.id, scope = scope, key = key, tier = tier, gate = gate, gateOk = People.gateOk(gate),
        lines = People.nodeLines(tree), cb = Schema.texts(tree.cb), short = Schema.texts(tree.short),
        beats = People.nodeBeats(tree), fx = People.nodeEffects(tree, soft), tags = Schema.texts(tree.tag),
        soft = soft }
end

function People.nodeShards(scope, index)
    if scope == "generic" then
        if #index.generic == 0 then return nil, "no_generic_route" end
        return index.generic
    end
    if Schema.validId("person", scope) then
        local entry = index.people[scope]
        if entry == nil then return nil, "unknown_person" end
        return { entry.nodes }, nil, entry
    end
    if Schema.validId("arch", scope) then
        local arch = index.archetypes[scope]
        return { arch ~= nil and arch.nodes or "archetypes" }
    end
    return nil, "scope_invalid"
end

function People.shardNode(path, id)
    local cache = Text.memo(path, "nodes", People.emptyTable)
    local row = cache[id]
    if row == nil then
        local record = (Text.get(path)).byId[id]
        row = false
        if record ~= nil and record.kind == "node" then
            local node, reason = People.normalizeNode(record)
            if node ~= nil then
                row = node
                People.metrics.nodesBuilt = People.metrics.nodesBuilt + 1
            else
                People.note("node:" .. id .. ":" .. tostring(reason))
            end
        end
        cache[id] = row
    end
    return row
end

function People.nodes(scope, key)
    if type(key) ~= "string" or string.match(key, "^[%w_%.]+$") == nil then return nil, "key_invalid" end
    local index, reason = People.index()
    if index == nil then return nil, reason end
    local shards, shardReason, entry = People.nodeShards(scope, index)
    if shards == nil then return nil, shardReason end
    if entry ~= nil and not entry.adult then
        local adultOnly, why = People.adultKey(key)
        if adultOnly == nil then return nil, why end
        if adultOnly then return nil, "adult_only" end
    end
    local paths = {}
    for position = 1, #shards do
        local path = shards[position] .. ".alife"
        if Text.ensure(path, 10) then
            paths[#paths + 1] = path
        else
            local why = People.reason(path)
            if why == "loading" then return nil, "loading" end
        end
    end
    local list = { scope = scope, key = key, defl = {} }
    local ids = { [0] = scope .. "." .. key, scope .. "." .. key .. ".d", scope .. "." .. key .. ".d2", scope .. "." .. key .. ".d3" }
    for tier = 0, 3 do
        for position = 1, #paths do
            local node = People.shardNode(paths[position], ids[tier])
            if node then
                if tier == 0 then list.node = node else list.defl[tier] = node end
                list[#list + 1] = node
                break
            end
        end
    end
    if #list == 0 then return nil, "no_node" end
    return list
end

function People.buildPools(result)
    local pools = {}
    for position = 1, #result.records do
        local record = result.records[position]
        if record.kind == "pool" and Schema.validId("pool", record.id) then
            local tree = Schema.unflatten(record)
            pools[record.id] = { id = record.id, lines = Schema.texts(tree.t) }
        end
    end
    return pools
end

function People.pool(id)
    if not Schema.validId("pool", id) then return nil, "pool_invalid" end
    local index, reason = People.index()
    if index == nil then return nil, reason end
    if #index.generic == 0 then return nil, "no_generic_route" end
    for position = 1, #index.generic do
        local path = index.generic[position] .. ".alife"
        if Text.ensure(path, 10) then
            local pools = Text.memo(path, "pools", People.buildPools)
            if pools[id] ~= nil then return pools[id] end
        else
            local why = People.reason(path)
            if why == "loading" then return nil, "loading" end
        end
    end
    return nil, "no_pool"
end

function People.poolId(key)
    if type(key) ~= "string" then return nil end
    return Schema.POOLS[key] or key
end

function People.pickLine(pool, options)
    local found, reason = People.pool(People.poolId(pool))
    if found == nil then return nil, reason end
    local count = #found.lines
    if count == 0 then return nil, "pool_empty" end
    if type(options) ~= "table" then options = {} end
    local index = nil
    if type(options.rand) == "function" then
        local drawn = tonumber(options.rand(count))
        if drawn ~= nil then index = math.floor(drawn) % count + 1 end
    end
    if index == nil then
        local seed = (tonumber(options.seed) or 0) % 2147483647
        index = (seed * 48271 + 11) % 2147483647 % count + 1
    end
    if options.avoid ~= nil and count > 1 and found.lines[index] == options.avoid then index = index % count + 1 end
    return found.lines[index], index
end

function People.normalizeBook(record)
    if not Schema.validId("book", record.id) then return nil, "id_invalid" end
    local tree = Schema.unflatten(record)
    local b = tree.bk or {}
    local title, author = Schema.str(b.title), Schema.str(b.author)
    if title == nil or author == nil then return nil, "title_author_required" end
    local year = Schema.int(b.year, 1000, 2100)
    if year == nil then return nil, "year_invalid" end
    if year > 1993 then return nil, "anachronism" end
    return { id = record.id, title = title, author = author, year = year, kind = Schema.str(b.kind) or "novel",
        genre = Schema.str(b.genre), item = Schema.str(b.item) or "Base.Book", pages = Schema.int(b.pages, 1, 5000),
        tags = Schema.split(Schema.str(b.tags) or "", "|"), raw = tree }
end

function People.buildBooks(result)
    local set = { list = {}, byId = {}, rejected = 0 }
    for position = 1, #result.records do
        local record = result.records[position]
        if record.kind == "book" then
            local book, reason = People.normalizeBook(record)
            if book ~= nil and set.byId[book.id] == nil then
                set.byId[book.id] = book
                set.list[#set.list + 1] = book
            else
                set.rejected = set.rejected + 1
                People.metrics.rejected = People.metrics.rejected + 1
                People.note("book:" .. tostring(record.id) .. ":" .. tostring(reason or "duplicate"))
            end
        end
    end
    return set
end

function People.bookSet()
    local path = Schema.FILES.books
    if not Text.ensure(path, 5) then return nil, People.reason(path) end
    return Text.memo(path, "books", People.buildBooks)
end

function People.book(id)
    local set, reason = People.bookSet()
    if set == nil then return nil, reason end
    if set.byId[id] == nil then return nil, "unknown_book" end
    return set.byId[id]
end

function People.normalizeEvent(record)
    if not Schema.validId("event", record.id) then return nil, "id_invalid" end
    local tree = Schema.unflatten(record)
    local ev = tree.ev or {}
    local kind = Schema.str(ev.kind) or "talk"
    if not Schema.EVENT_KINDS[kind] then return nil, "kind_invalid" end
    local speaker = Schema.str(ev.speaker) or "any"
    if not Schema.SPEAKERS[speaker] then return nil, "speaker_invalid" end
    local tags = {}
    local sensitive = kind == "flirt"
    for _, tag in ipairs(Schema.split(Schema.str(ev.tags) or "", ",")) do
        tags[tag] = true
        if Schema.ADULT_TAGS[tag] then sensitive = true end
    end
    local adult = Schema.bool(ev.adult)
    if sensitive and (not adult or speaker ~= "adult") then return nil, "adult_required" end
    local whenRule = Schema.str(ev.when)
    if whenRule ~= nil and not People.gateOk(whenRule) then return nil, "when_invalid" end
    return { id = record.id, kind = kind, when = whenRule, speaker = speaker, weight = Schema.num(ev.w, 1),
        cooldownHours = Schema.num(ev.cd, 24), once = Schema.bool(ev.once), timeoutSec = Schema.num(ev.timeout, 45),
        adult = adult, adultOnly = sensitive, tags = tags, prompts = Schema.texts(tree.t), raw = tree }
end

function People.buildEvents(result)
    local set = { list = {}, byId = {}, rejected = 0 }
    for position = 1, #result.records do
        local record = result.records[position]
        if record.kind == "event" then
            local event, reason = People.normalizeEvent(record)
            if event ~= nil and set.byId[event.id] == nil then
                set.byId[event.id] = event
                set.list[#set.list + 1] = event
            else
                set.rejected = set.rejected + 1
                People.metrics.rejected = People.metrics.rejected + 1
                People.note("event:" .. tostring(record.id) .. ":" .. tostring(reason or "duplicate"))
            end
        end
    end
    return set
end

function People.eventSet()
    local path = Schema.FILES.events
    if not Text.ensure(path, 5) then return nil, People.reason(path) end
    return Text.memo(path, "events", People.buildEvents)
end

function People.events()
    local set, reason = People.eventSet()
    if set == nil then return nil, reason end
    return set.list
end

function People.event(id)
    local set, reason = People.eventSet()
    if set == nil then return nil, reason end
    if set.byId[id] == nil then return nil, "unknown_event" end
    return set.byId[id]
end

function People.archetype(id)
    local index, reason = People.index()
    if index == nil then return nil, reason end
    local light = index.archetypes[id]
    local path = Schema.FILES.archetypes
    if Text.ensure(path, 5) then
        local record = (Text.get(path)).byId[id]
        if record ~= nil and record.kind == "arch" then
            local defs = Text.memo(path, "defs", People.emptyTable)
            if defs[id] == nil then defs[id] = (Schema.unflatten(record)) end
            return { id = id, light = light, tree = defs[id] }
        end
    elseif People.reason(path) == "loading" then
        return nil, "loading"
    end
    if light == nil then return nil, "unknown_archetype" end
    return { id = id, light = light, tree = {} }
end

function People.qaLine()
    local metrics = People.metrics
    local index = Text.entries[Schema.FILES.index]
    local persons = 0
    if index ~= nil and index.state == "ready" and index.result.memo.index ~= nil then
        persons = index.result.memo.index.count
    end
    return "[ALIFE-QA] VisitorPeople persons=" .. tostring(persons) .. " cardsBuilt=" .. tostring(metrics.cardsBuilt)
        .. " cardsRejected=" .. tostring(metrics.cardsRejected) .. " nodesBuilt=" .. tostring(metrics.nodesBuilt)
        .. " rejected=" .. tostring(metrics.rejected) .. " why=" .. tostring(metrics.lastWhy)
end

function People.reset()
    People.metrics = { indexBuilt = 0, cardsBuilt = 0, cardsRejected = 0, nodesBuilt = 0, rejected = 0, lastWhy = "-" }
    People.reasons = {}
end

return People
