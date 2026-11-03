require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorText"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorTalkRules"
require "ProjectALife/Visitors/ALifeVisitorFlirt"
require "ProjectALife/Visitors/ALifeVisitorBooks"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Text = ProjectALife.VisitorText
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Rules = ProjectALife.VisitorTalkRules
local Flirt = ProjectALife.VisitorFlirt
local Books = ProjectALife.VisitorBooks

local Lines = {
    familyOf = {},
    metrics = { rendered = 0, unresolved = 0, pools = 0, nodes = 0 },
}
ProjectALife.VisitorLines = Lines

Lines.familyVoices = {
    rural_elder = "V01 V16 VX24", young = "V02 VX23 VX29", working = "V03 V06 V11 V12 V13 VX27",
    professional = "V04 V14 VX25 VX28 VX30", religious = "V05 VX26", service_law = "V07 V08 V09 V10",
    wry = "V15 V20 VX21 VX22", rough = "V17 V18 V19",
}
for family, voices in pairs(Lines.familyVoices) do
    for voice in string.gmatch(voices, "%S+") do Lines.familyOf[voice] = family end
end

Lines.viceWords = { tobacco = "cigarettes", alcohol = "the bottle", pills = "the pills", heroin_withdrawal = "the stuff",
    gambling = "the cards" }
Lines.kinWords = { son = true, daughter = true, wife = true, husband = true, mother = true, father = true, brother = true,
    sister = true }
Lines.styles = { { "anx", 3, "SHY" }, { "pride", 4, "PROUD" }, { "temper", 4, "HOT" }, { "humor", 4, "JOKING", "honest", 3 },
    { "fatigue", 4, "TIRED" }, { "fear", 4, "SCARED" } }

function Lines.shortOf(qid)
    return (string.gsub(qid, "^VQ_", ""))
end

function Lines.namesKnow(record, key)
    local names = ProjectALife.Names
    if names == nil or type(names.knows) ~= "function" or key == nil then return false end
    return names.knows(record, key) == true
end

function Lines.slotKin(env)
    local _, record = Rules.rawCard(env.person.id)
    local rows = record ~= nil and type(record.rl) == "table" and record.rl or {}
    local keys = {}
    for key in pairs(rows) do keys[#keys + 1] = tonumber(key) or 0 end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local kind = Schema.split(tostring(rows[tostring(key)] or rows[key] or ""), "|")[2]
        if kind ~= nil and Lines.kinWords[kind] then return "my " .. kind end
    end
    return nil
end

function Lines.slotPartner(env)
    local other = Rules.scan(env).members[1]
    if other == nil then return nil end
    local who = Instance.of(other)
    local card = who ~= nil and People.card(who.id) or nil
    if card == nil or not Lines.namesKnow(other, env.key) then return nil end
    return card.name.first
end

function Lines.slot(env, name)
    local card = Rules.card(env)
    if card == nil then return nil end
    if name == "first" then return (env.known or env.revealing) and card.name.first or nil end
    if name == "last" then return (env.known or env.revealing) and card.name.last or nil end
    if name == "desc" then return card.desc end
    if name == "job" or name == "jobpast" then
        local work = card.origin.work
        if work == nil then return nil end
        return string.match(work, "^%s*([^;%(]-)%s*[;%(]") or work
    end
    if name == "town" then return card.origin.town end
    if name == "kin" then return Lines.slotKin(env) end
    if name == "partner" then return Lines.slotPartner(env) end
    if name == "book" or name == "author" then return Books.slot(env, name) end
    if name == "poi" then
        if type(Lines.adapters) == "table" and type(Lines.adapters.poiWord) == "function" then return Lines.adapters.poiWord(env) end
        return nil
    end
    if name == "room" then return Rules.safeRoom(Rules.shell(env)) end
    if name == "he" then return card.sex == "f" and "she" or "he" end
    if name == "his" then return card.sex == "f" and "her" or "his" end
    if name == "vice" then return Lines.viceWords[card.vice] end
    return nil
end

function Lines.envOf(person, player)
    local record = person
    if type(person) == "table" and person.memory == nil then record = { memory = { person = person } } end
    local env = Rules.env(record, player, nil, nil)
    env.known = Lines.namesKnow(record, env.key)
    return env
end

function Lines.render(text, person, player, env)
    if type(text) ~= "string" then return nil end
    if string.find(text, "{@", 1, true) == nil then return text end
    env = env or Lines.envOf(person, player)
    local missing = false
    local result = string.gsub(text, "{@(%w+)}", function(name)
        local value = Lines.slot(env, name)
        if value == nil then
            missing = true
            return ""
        end
        return value
    end)
    if missing then
        Lines.metrics.unresolved = Lines.metrics.unresolved + 1
        return nil
    end
    Lines.metrics.rendered = Lines.metrics.rendered + 1
    return result
end

function Lines.prio(node)
    for _, tag in ipairs(node.tags or {}) do
        local value = string.match(tag, "^prio:(%d+)$")
        if value ~= nil then return tonumber(value) end
    end
    return 0
end

function Lines.passes(env, node)
    if node.gate == nil then return true end
    if not node.gateOk then return false end
    return (Rules.test(env, node.gate))
end

function Lines.scopes(env)
    local card = Rules.card(env)
    local scopes = { env.person.id }
    if card ~= nil and card.arch ~= nil then scopes[#scopes + 1] = card.arch end
    scopes[#scopes + 1] = "generic"
    return scopes
end

function Lines.altNodes(scope, key, base, candidates)
    for number = 2, 4 do
        local list, why = People.nodes(scope, key .. ".a" .. number)
        if list == nil and why == "loading" then return false end
        if list ~= nil and list.node ~= nil then
            candidates[#candidates + 1] = { node = list.node, alt = number, prio = Lines.prio(list.node), list = base }
        end
    end
    return true
end

function Lines.scopeNodes(scope, key)
    local list, why = People.nodes(scope, key)
    if list == nil and (why == "loading" or why == "adult_only") then return nil, why end
    local candidates = {}
    if list ~= nil and list.node ~= nil then
        candidates[1] = { node = list.node, alt = 1, prio = Lines.prio(list.node), list = list }
    end
    if not Lines.altNodes(scope, key, list, candidates) then return nil, "loading" end
    return candidates, nil, list
end

function Lines.lookup(env, key)
    for _, scope in ipairs(Lines.scopes(env)) do
        local candidates, why, list = Lines.scopeNodes(scope, key)
        if candidates == nil and why ~= nil then return nil, why end
        if candidates ~= nil and #candidates > 0 then
            local best = nil
            for position = 1, #candidates do
                local candidate = candidates[position]
                if Lines.passes(env, candidate.node) then
                    if best == nil or candidate.prio > best.prio or (candidate.prio == best.prio and candidate.alt > best.alt) then
                        best = candidate
                    end
                end
            end
            Lines.metrics.nodes = Lines.metrics.nodes + 1
            if best ~= nil then return { scope = scope, node = best.node, alt = best.alt, list = best.list or list } end
            return { scope = scope, locked = true, list = list }
        elseif list ~= nil and (list.defl[1] ~= nil or list.defl[2] ~= nil or list.defl[3] ~= nil) then
            return { scope = scope, locked = true, list = list }
        end
    end
    return {}
end

function Lines.bandLines(lines, band)
    local list = lines[band]
    if list ~= nil and #list > 0 then return list end
    if #lines.any > 0 then return lines.any end
    local order = band == "lo" and { "mid", "hi" } or (band == "mid" and { "hi", "lo" } or { "mid", "lo" })
    for position = 1, #order do
        if #lines[order[position]] > 0 then return lines[order[position]] end
    end
    return {}
end

function Lines.flirtActive(env)
    return Flirt.stage(env) >= 1 and (Flirt.guard(env))
end

function Lines.sequenceOf(env, node, band)
    local lines = node.lines
    local seq = {}
    local ids = {}
    for fact in pairs(lines.ref) do ids[#ids + 1] = fact end
    table.sort(ids)
    for _, fact in ipairs(ids) do
        if Rules.knows(env, fact) then
            seq[#seq + 1] = { text = lines.ref[fact], kind = "ref" }
            break
        end
    end
    local variants = Lines.bandLines(lines, band)
    if #lines.flirt > 0 and Lines.flirtActive(env) then variants = lines.flirt end
    for position = 1, #variants do seq[#seq + 1] = { text = variants[position], kind = "v" } end
    local head = #seq
    for position = 1, #node.cb do seq[#seq + 1] = { text = node.cb[position], kind = "cb" } end
    for position = 1, #node.short do seq[#seq + 1] = { text = node.short[position], kind = "short" } end
    return seq, head
end

function Lines.tailStart(seq, head, start)
    local size = #seq
    local tail = {}
    for position = head + 1, size do tail[#tail + 1] = position end
    local shorts = {}
    for position = 1, #tail do
        if seq[tail[position]].kind == "short" then shorts[#shorts + 1] = tail[position] end
    end
    if #shorts > 0 then tail = shorts end
    if #tail == 0 then
        for position = 1, size do tail[#tail + 1] = position end
    end
    return tail[(start - size - 1) % #tail + 1]
end

function Lines.compose(env, node, band, count)
    local seq, head = Lines.sequenceOf(env, node, band)
    local size = #seq
    if size == 0 then return nil end
    local start = count + 1
    if start > size then start = Lines.tailStart(seq, head, start) end
    for step = 0, size - 1 do
        local index = (start - 1 + step) % size + 1
        local text = Lines.render(seq[index].text, env.person, env.player, env)
        if text ~= nil then return text, index, seq[index].kind, size end
    end
    return nil
end

function Lines.beatsOf(env, node, band, kind)
    local result = {}
    if kind ~= "v" and kind ~= "ref" then return result end
    for _, beat in ipairs(node.beats or {}) do
        if beat.band == band or beat.band == "any" then
            local text = Lines.render(beat.text, env.person, env.player, env)
            if text ~= nil then result[#result + 1] = { afterMs = beat.afterMs, t = text } end
        end
    end
    return result
end

function Lines.parsePool(record)
    local tree = Schema.unflatten(record)
    local pool = { id = record.id, entries = {}, flat = {}, adult = type(tree.p) == "table" and Schema.bool(tree.p.adult) }
    local source = type(tree.t) == "table" and tree.t or {}
    for family, bands in pairs(source) do
        if type(family) == "string" and type(bands) == "table" then
            for band, items in pairs(bands) do
                if type(items) == "table" then
                    local gate = type(tree.g) == "table" and type(tree.g[family]) == "table" and tree.g[family][band] or nil
                    pool.entries[family .. "." .. band] = { lines = Schema.texts(items), gate = type(gate) == "string" and gate or nil }
                end
            end
        elseif type(family) == "number" and type(bands) == "string" then
            pool.flat[#pool.flat + 1] = bands
        end
    end
    return pool
end

function Lines.poolRecord(id)
    local index = People.index()
    if index == nil then return nil, "loading" end
    for position = 1, #index.generic do
        local path = index.generic[position] .. ".alife"
        if Text.ensure(path, 10) then
            local cache = Text.memo(path, "vtpools", People.emptyTable)
            local found = cache[id]
            if found == nil then
                local record = (Text.get(path)).byId[id]
                found = (record ~= nil and record.kind == "pool") and Lines.parsePool(record) or false
                cache[id] = found
            end
            if found then return found end
        elseif People.reason(path) == "loading" then
            return nil, "loading"
        end
    end
    return nil, "no_pool"
end

function Lines.poolLines(env, pool, band)
    local card = Rules.card(env)
    local family = card ~= nil and card.voice ~= nil and Lines.familyOf[card.voice] or "any"
    local order = { family .. "." .. band, family .. ".any", "any." .. band, "any.any" }
    for position = 1, #order do
        local entry = pool.entries[order[position]]
        if entry ~= nil and #entry.lines > 0 and (entry.gate == nil or Rules.test(env, entry.gate)) then return entry.lines end
    end
    if #pool.flat > 0 then return pool.flat end
    local keys = {}
    for key in pairs(pool.entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local entry = pool.entries[key]
        if #entry.lines > 0 and (entry.gate == nil or Rules.test(env, entry.gate)) then return entry.lines end
    end
    return {}
end

function Lines.pick(env, poolId, band, count, tier)
    local pool, why = nil, nil
    if tier ~= nil then pool, why = Lines.poolRecord(poolId .. "." .. tier) end
    if pool == nil and why ~= "loading" then pool, why = Lines.poolRecord(poolId) end
    if pool == nil then return nil, why end
    if pool.adult and not Rules.adult(env) then return nil, "adult_only" end
    local lines = Lines.poolLines(env, pool, band)
    if #lines == 0 then return nil, "pool_empty" end
    for step = 0, #lines - 1 do
        local index = (count + step) % #lines + 1
        local text = Lines.render(lines[index], env.person, env.player, env)
        if text ~= nil then
            Lines.metrics.pools = Lines.metrics.pools + 1
            return text, index
        end
    end
    return nil, "pool_unrendered"
end

function Lines.styleOf(env)
    local card = Rules.card(env)
    local person = env.person
    for _, row in ipairs(Lines.styles) do
        local name = row[1]
        local value = card.traits[name]
        if value == nil then value = Instance.need(person, name) end
        if value >= row[2] and (row[4] == nil or card.traits[row[4]] <= row[5]) then return row[3] end
    end
    return "PLAIN"
end

function Lines.qaLine()
    local m = Lines.metrics
    return "[ALIFE-QA] VisitorLines rendered=" .. tostring(m.rendered) .. " unresolved=" .. tostring(m.unresolved)
        .. " pools=" .. tostring(m.pools) .. " nodes=" .. tostring(m.nodes)
end

Lines.adapters = {}

return Lines
