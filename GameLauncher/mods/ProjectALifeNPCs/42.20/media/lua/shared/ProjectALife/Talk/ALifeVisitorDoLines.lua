ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/Data/ALifeDoLinesIndex"
require "ProjectALife/Talk/ALifeTalkUi"

local DoLines = {
    loaded = false,
    adapters = {},
    pools = {},
    rules = {},
    gates = {},
    errors = {},
    shardDone = {},
    last = {},
    lastOrder = {},
    lastCap = 64,
    counts = { shards = 0, rows = 0, lines = 0, rules = 0 },
    metrics = { picks = 0, refused = 0 },
}
ProjectALife.VisitorDoLines = DoLines

DoLines.gateKeys = { tr = true, nd = true, ["in"] = true, kind = true, out = true, sex = true, mood = true, turn = true }
DoLines.bands = { "hates", "wary", "neutral", "warm", "friend" }
DoLines.needs = {
    beggar = "food", wounded = "meds", sleep_one_night = "shelter", chased = "safety",
    law_stay_inside = "duty", law_census = "duty", law_guns = "duty", law_fake = "duty",
    messenger = "help", asks_help = "help",
}
DoLines.tokens = {
    He = { "He", "She" }, he = { "he", "she" }, His = { "His", "Her" }, his = { "his", "her" },
    him = { "him", "her" }, Him = { "Him", "Her" }, himself = { "himself", "herself" },
}
DoLines.maxLength = 64

function DoLines.random(maximum)
    if maximum <= 1 then return 0 end
    if type(DoLines.adapters.random) == "function" then return DoLines.adapters.random(maximum) end
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

function DoLines.band(value)
    value = tonumber(value) or 0
    if value <= -61 then return "hates" end
    if value <= -21 then return "wary" end
    if value <= 20 then return "neutral" end
    if value <= 60 then return "warm" end
    return "friend"
end

function DoLines.needOf(kind)
    if kind == nil then return "none" end
    return DoLines.needs[tostring(kind)] or "none"
end

function DoLines.isVisitor(record)
    return ProjectALife.TalkUi.visitStamp(record) ~= nil
end

function DoLines.parseGate(text)
    text = tostring(text or "")
    local cached = DoLines.gates[text]
    if cached ~= nil then return cached end
    local gate = { keys = 0 }
    for part in string.gmatch(text, "[^|]+") do
        local key, value = string.match(part, "^([a-z]+)=(.*)$")
        if key == nil or DoLines.gateKeys[key] ~= true then
            gate.bad = part
        elseif key == "turn" then
            local low, high = string.match(value, "^(%d+),(%d+)$")
            if low == nil then
                gate.bad = part
            else
                gate.turn = { tonumber(low), tonumber(high) }
                gate.keys = gate.keys + 1
            end
        else
            local set = {}
            for item in string.gmatch(value, "[^,]+") do set[item] = true end
            gate[key] = set
            gate.keys = gate.keys + 1
        end
    end
    DoLines.gates[text] = gate
    return gate
end

function DoLines.matches(gate, ctx)
    if gate.bad ~= nil then return false end
    if gate.tr ~= nil and gate.tr[ctx.band] ~= true then return false end
    if gate.nd ~= nil and gate.nd[ctx.need] ~= true then return false end
    if gate["in"] ~= nil and gate["in"][ctx.intent or ""] ~= true then return false end
    if gate.kind ~= nil and gate.kind[ctx.kind or ""] ~= true then return false end
    if gate.out ~= nil and gate.out[ctx.outcome or ""] ~= true then return false end
    if gate.sex ~= nil and gate.sex[ctx.sex or ""] ~= true then return false end
    if gate.mood ~= nil and gate.mood[ctx.mood or ""] ~= true then return false end
    if gate.turn ~= nil and (ctx.turn < gate.turn[1] or ctx.turn > gate.turn[2]) then return false end
    return true
end

function DoLines.rowsOf(id)
    local store = ProjectALife.DoLineShards
    local rows = store ~= nil and store[id] or nil
    if rows == nil then
        require("ProjectALife/Talk/Data/ALifeDoLines_" .. tostring(id))
        store = ProjectALife.DoLineShards
        rows = store ~= nil and store[id] or nil
    end
    if type(rows) ~= "table" then error("shard_missing") end
    return rows
end

function DoLines.addLines(rows)
    for r = 1, #rows do
        local row = rows[r]
        local state, texts = row[1], row[3]
        if type(state) ~= "string" or type(texts) ~= "table" then error("bad_row") end
        local gate = DoLines.parseGate(row[2])
        if gate.bad ~= nil then error("bad_gate:" .. gate.bad) end
        local pool = DoLines.pools[state]
        if pool == nil then pool = {}; DoLines.pools[state] = pool end
        for i = 1, #texts do
            pool[#pool + 1] = { t = texts[i], g = gate, w = 1 + gate.keys }
            DoLines.counts.lines = DoLines.counts.lines + 1
        end
        DoLines.counts.rows = DoLines.counts.rows + 1
    end
end

function DoLines.addRules(rows)
    for r = 1, #rows do
        local row = rows[r]
        if type(row[1]) ~= "string" then error("bad_rule") end
        local gate = DoLines.parseGate(row[2])
        if gate.bad ~= nil then error("bad_gate:" .. gate.bad) end
        DoLines.rules[#DoLines.rules + 1] = { state = row[1], gate = gate }
        DoLines.counts.rules = DoLines.counts.rules + 1
    end
end

function DoLines.loadShard(kind, id)
    if DoLines.shardDone[id] then return true end
    DoLines.shardDone[id] = true
    local ok, err = pcall(function()
        local rows = DoLines.rowsOf(id)
        if kind == "rules" then DoLines.addRules(rows) else DoLines.addLines(rows) end
    end)
    if not ok then
        DoLines.errors[#DoLines.errors + 1] = tostring(id) .. ":" .. tostring(err)
        return false
    end
    DoLines.counts.shards = DoLines.counts.shards + 1
    return true
end

function DoLines.load()
    if DoLines.loaded then return DoLines end
    DoLines.loaded = true
    local index = ProjectALife.DoLineIndex
    if type(index) ~= "table" then
        DoLines.errors[#DoLines.errors + 1] = "index_missing"
        return DoLines
    end
    for _, id in ipairs(index.rules or {}) do DoLines.loadShard("rules", id) end
    for _, id in ipairs(index.lines or {}) do DoLines.loadShard("lines", id) end
    return DoLines
end

function DoLines.reset()
    DoLines.loaded = false
    DoLines.pools, DoLines.rules, DoLines.errors, DoLines.shardDone = {}, {}, {}, {}
    DoLines.gates, DoLines.last, DoLines.lastOrder = {}, {}, {}
    DoLines.counts = { shards = 0, rows = 0, lines = 0, rules = 0 }
    DoLines.metrics = { picks = 0, refused = 0 }
end

function DoLines.sexOf(record, context)
    local given = context.sex
    if given == "f" or given == "m" then return given end
    local shell = context.shell
    if shell ~= nil and type(shell.isFemale) == "function" then
        local ok, female = pcall(shell.isFemale, shell)
        if ok and type(female) == "boolean" then
            if female then return "f" end
            return "m"
        end
    end
    local roles = ProjectALife.DialogueRoles
    if roles ~= nil and type(roles.factsFor) == "function" then
        local ok, facts = pcall(roles.factsFor, record)
        if ok and type(facts) == "table" and facts.female == true then return "f" end
    end
    return "m"
end

function DoLines.contextFor(record, context)
    local c = type(context) == "table" and context or {}
    local stamp = ProjectALife.TalkUi.visitStamp(record)
    local ctx = {}
    ctx.kind = c.kind
    if ctx.kind == nil and stamp ~= nil then ctx.kind = stamp.event end
    ctx.need = c.need
    if ctx.need == nil then ctx.need = DoLines.needOf(ctx.kind) end
    ctx.trust = tonumber(c.trust) or 0
    ctx.band = DoLines.band(ctx.trust)
    ctx.intent, ctx.outcome, ctx.mood, ctx.state = c.intent, c.outcome, c.mood, c.state
    ctx.turn = tonumber(c.turn) or 0
    ctx.sex = DoLines.sexOf(record, c)
    ctx.previousRaw = c.previousRaw
    return ctx
end

function DoLines.stateFor(ctx)
    local pools = DoLines.pools
    if type(ctx.state) == "string" and pools[ctx.state] ~= nil then return ctx.state end
    for index = 1, #DoLines.rules do
        local rule = DoLines.rules[index]
        if pools[rule.state] ~= nil and DoLines.matches(rule.gate, ctx) then return rule.state end
    end
    return nil
end

function DoLines.render(raw, sex)
    local slot = 1
    if sex == "f" then slot = 2 end
    local text = string.gsub(raw, "{v:(%a+)}", function(key)
        local forms = DoLines.tokens[key]
        if forms == nil then return "{v:" .. key .. "}" end
        return forms[slot]
    end)
    return text
end

function DoLines.remember(uid, raw)
    if uid == nil then return end
    uid = tostring(uid)
    if DoLines.last[uid] == nil then
        DoLines.lastOrder[#DoLines.lastOrder + 1] = uid
        while #DoLines.lastOrder > DoLines.lastCap do
            local oldest = table.remove(DoLines.lastOrder, 1)
            DoLines.last[oldest] = nil
        end
    end
    DoLines.last[uid] = raw
end

function DoLines.forget(uid)
    if uid == nil then return end
    uid = tostring(uid)
    DoLines.last[uid] = nil
    for index = #DoLines.lastOrder, 1, -1 do
        if DoLines.lastOrder[index] == uid then table.remove(DoLines.lastOrder, index) end
    end
end

function DoLines.candidates(state, ctx, avoid)
    local pool = DoLines.pools[state]
    local list, total = {}, 0
    if pool == nil then return list, total end
    for index = 1, #pool do
        local entry = pool[index]
        if entry.t ~= avoid and DoLines.matches(entry.g, ctx) then
            list[#list + 1] = entry
            total = total + entry.w
        end
    end
    return list, total
end

function DoLines.pick(record, context)
    if type(record) ~= "table" then return nil end
    local given = type(context) == "table" and context or {}
    if not DoLines.isVisitor(record) and given.visitor ~= true then
        DoLines.metrics.refused = DoLines.metrics.refused + 1
        return nil
    end
    DoLines.load()
    local ctx = DoLines.contextFor(record, given)
    local state = DoLines.stateFor(ctx)
    if state == nil then return nil end
    local avoid = ctx.previousRaw
    if avoid == nil then avoid = DoLines.last[tostring(record.uid)] end
    local list, total = DoLines.candidates(state, ctx, avoid)
    if #list == 0 then list, total = DoLines.candidates(state, ctx, nil) end
    if #list == 0 then return nil end
    local roll = DoLines.random(total)
    local chosen = list[#list]
    for index = 1, #list do
        roll = roll - list[index].w
        if roll < 0 then chosen = list[index]; break end
    end
    DoLines.remember(record.uid, chosen.t)
    DoLines.metrics.picks = DoLines.metrics.picks + 1
    return DoLines.render(chosen.t, ctx.sex), state, chosen.t
end

function DoLines.stateCounts()
    DoLines.load()
    local result = {}
    for state, pool in pairs(DoLines.pools) do result[state] = #pool end
    return result
end

return DoLines
