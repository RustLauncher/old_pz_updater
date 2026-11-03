ProjectALife = ProjectALife or {}

local Schema = {
    VERSION = 1,
    DIR = "alife_runtime/visitors/",
    MIN_AGE = 18,
    ADULT_AGE = 18,
    MAX_AGE = 90,
    MAX_PARTY = 3,
    NEED_MAX = 5,
    TRAIT_MAX = 5,
    SHARD_PEOPLE = 25,
    LEDGER_CAP = 256,
    LEDGER_PLAYERS = 3,
    LEDGER_FLAGS = 3,
    LEDGER_TEXT = 120,
    INSTANCE_BYTES = 1200,
    VT_PLAYERS = 4,
    VT_TEXT = 360,
}
ProjectALife.VisitorSchema = Schema

function Schema.set(list)
    local result = {}
    for index = 1, #list do result[list[index]] = true end
    return result
end

Schema.FILES = {
    index = "index.alife",
    questions = "questions.alife",
    books = "books.alife",
    events = "events.alife",
    archetypes = "archetypes.alife",
}

Schema.PREFIX = {
    person = "vp_", party = "vg_", arch = "va_", question = "VQ_",
    event = "VE_", pool = "VP_", book = "bk_",
}
Schema.KIND_ORDER = { "person", "party", "arch", "question", "event", "pool", "book" }

Schema.NEEDS = {
    { name = "hunger", key = "h" }, { name = "thirst", key = "w" }, { name = "cold", key = "c" },
    { name = "fear", key = "f" }, { name = "fatigue", key = "t" }, { name = "dirty", key = "d" },
    { name = "sick", key = "s" }, { name = "pain", key = "p" },
}
Schema.NEED_KEY, Schema.NEED_NAME = {}, {}
for index = 1, #Schema.NEEDS do
    local row = Schema.NEEDS[index]
    Schema.NEED_KEY[row.name] = row.key
    Schema.NEED_NAME[row.key] = row.name
end

Schema.TRAITS = { "open", "anx", "humor", "temper", "honest", "faith", "trustSpeed", "curious",
    "pride", "flirt", "social", "tidy", "nostalg" }
Schema.TRAIT_SET = Schema.set(Schema.TRAITS)

Schema.TABS = { "talk", "past", "now", "house", "world", "offer", "closer", "visit" }
Schema.TAB_SET = Schema.set(Schema.TABS)
Schema.QUESTION_KINDS = { "ask", "talk", "offer", "house", "world", "flirt", "book", "react", "visit" }
Schema.QUESTION_KIND_SET = Schema.set(Schema.QUESTION_KINDS)
Schema.VISIBILITY = Schema.set({ "open", "hidden" })
Schema.VICES = { "none", "tobacco", "alcohol", "pills", "heroin_withdrawal", "gambling" }
Schema.VICE_SET = Schema.set(Schema.VICES)
Schema.LEAVE_REASONS = Schema.set({ "need_met", "trust_low", "partner_recovered", "stay_cap", "morning",
    "danger_gone", "player_asks", "betray" })
Schema.EVENT_KINDS = Schema.set({ "talk", "house", "vice", "health", "memory", "alert", "arc", "world",
    "ambient", "feeling", "social", "book", "flirt", "party", "barter", "task" })
Schema.SPEAKERS = Schema.set({ "any", "adult", "party:lead" })
Schema.ADULT_TAGS = Schema.set({ "privacy", "undress", "bath_change", "bath_caught", "topoff", "changing",
    "tease", "flirt" })
Schema.DRESS_STATES = { "dressed", "topOff", "changing" }
Schema.DRESS_STATE_SET = Schema.set(Schema.DRESS_STATES)
Schema.CLEAN_STATES = { "dirty", "clean", "fresh" }
Schema.FRESH_HOURS = 0.5
Schema.CLEAN_HOURS = 12
Schema.ACTS = Schema.set({ "stand", "sit", "read", "look", "wash", "rest", "tv", "warm", "change", "feed",
    "approach", "privacy", "walk" })
Schema.POOLS = {
    feeding = "VP_CANNIBAL_FEEDING",
    feedApproach = "VP_CANNIBAL_APPROACH",
    feedInterrupted = "VP_CANNIBAL_INTERRUPTED",
    feedLeave = "VP_CANNIBAL_LEAVE",
    feedStab = "VP_CANNIBAL_STAB",
    feedPlayerBody = "VP_CANNIBAL_PLAYER_BODY",
    feedFindBody = "VP_CANNIBAL_FIND_BODY",
    washUp = "VP_WASH_ASK",
    washDone = "VP_WASH_DONE_SINK",
    washDoneBath = "VP_WASH_DONE_BATH",
    washBlood = "VP_WASH_BLOOD",
    washNoWater = "VP_WASH_NO_WATER",
    washThanks = "VP_WASH_THANKS",
    washChange = "VP_WASH_CHANGE",
    freshLook = "VP_DOLINES_FRESH",
    dirtyLook = "VP_DOLINES_DIRTY",
    topOffCaught = "VP_WASH_CAUGHT",
}
Schema.BANDS = Schema.set({ "teen", "adult", "mid", "senior" })
Schema.EFFECT_VERBS = Schema.set({ "set", "clr", "gset", "reveal", "op", "need", "mood", "next", "lock",
    "anim", "give", "ask", "ev", "arc", "ledger" })
Schema.REVEAL_RULES = Schema.set({ "intro" })
Schema.NODE_BANDS = Schema.set({ "lo", "mid", "hi", "any", "ref", "flirt" })

Schema.OUTCOMES = { "other", "left", "gave_food", "let_sleep", "treated_wounded", "sheltered_chased",
    "fair_trade", "census_answer", "neighbour_watch", "rude_no", "turned_away", "turned_inside",
    "guest_turned", "cancelled", "expired", "ignored", "died", "hostile", "betrayed", "returned" }

function Schema.outcomeCode(name)
    if type(name) == "number" then
        if name >= 0 and name < #Schema.OUTCOMES and name == math.floor(name) then return name end
        return 0
    end
    for index = 1, #Schema.OUTCOMES do
        if Schema.OUTCOMES[index] == name then return index - 1 end
    end
    return 0
end

function Schema.outcomeName(code)
    return Schema.OUTCOMES[(tonumber(code) or 0) + 1] or Schema.OUTCOMES[1]
end

function Schema.kindOf(id)
    if type(id) ~= "string" then return nil end
    for index = 1, #Schema.KIND_ORDER do
        local kind = Schema.KIND_ORDER[index]
        local prefix = Schema.PREFIX[kind]
        if string.sub(id, 1, #prefix) == prefix then return kind end
    end
    return nil
end

function Schema.validId(kind, id)
    local prefix = Schema.PREFIX[kind]
    if prefix == nil or type(id) ~= "string" or #id > 64 then return false end
    if string.sub(id, 1, #prefix) ~= prefix then return false end
    if kind == "person" then return string.match(id, "^vp_%d%d%d%d$") ~= nil end
    if kind == "party" then return string.match(id, "^vg_%d%d%d$") ~= nil end
    return #id > #prefix and string.match(id, "^[%w_]+$") ~= nil
end

function Schema.validName(text)
    return type(text) == "string" and #text > 0 and #text <= 48 and string.match(text, "^[%w_%-]+$") ~= nil
end

function Schema.qid(argument)
    if type(argument) ~= "string" or argument == "" then return nil end
    if string.sub(argument, 1, 3) == "VQ_" then return argument end
    return "VQ_" .. argument
end

function Schema.int(value, low, high)
    local number = tonumber(value)
    if number == nil or number ~= number or number ~= math.floor(number) then return nil end
    if low ~= nil and number < low then return nil end
    if high ~= nil and number > high then return nil end
    return number
end

function Schema.num(value, fallback)
    local number = tonumber(value)
    if number == nil or number ~= number then return fallback end
    return number
end

function Schema.bool(value)
    return value == true or value == "true"
end

function Schema.clampInt(value, low, high, fallback)
    local number = tonumber(value)
    if number == nil or number ~= number then number = fallback end
    number = math.floor(number)
    if number < low then number = low elseif number > high then number = high end
    return number
end

function Schema.band(age)
    local number = Schema.int(age, Schema.MIN_AGE, Schema.MAX_AGE)
    if number == nil then return nil end
    if number < Schema.ADULT_AGE then return "teen" end
    if number < 40 then return "adult" end
    if number < 60 then return "mid" end
    return "senior"
end

function Schema.isAdult(age)
    local number = Schema.int(age, Schema.MIN_AGE, Schema.MAX_AGE)
    return number ~= nil and number >= Schema.ADULT_AGE
end

function Schema.split(text, separator)
    local result = {}
    if type(text) ~= "string" or type(separator) ~= "string" or separator == "" then return result end
    local cursor = 1
    while true do
        local stop = string.find(text, separator, cursor, true)
        local piece = string.sub(text, cursor, (stop or (#text + 1)) - 1)
        piece = string.match(piece, "^%s*(.-)%s*$")
        if piece ~= "" then result[#result + 1] = piece end
        if stop == nil then break end
        cursor = stop + #separator
    end
    return result
end

function Schema.csv(text)
    return Schema.split(text, ",")
end

function Schema.str(value)
    if value == nil or type(value) == "table" then return nil end
    local text = tostring(value)
    if text == "" then return nil end
    return text
end

function Schema.list(tbl)
    local result = {}
    if type(tbl) ~= "table" then return result end
    local keys = {}
    for key in pairs(tbl) do
        if type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for index = 1, #keys do result[#result + 1] = tbl[keys[index]] end
    return result
end

function Schema.texts(tbl)
    local result = {}
    local items = Schema.list(tbl)
    for index = 1, #items do
        local text = Schema.str(items[index])
        if text ~= nil then result[#result + 1] = text end
    end
    return result
end

function Schema.splitPath(field)
    local parts, cursor = {}, 1
    while true do
        local dot = string.find(field, ".", cursor, true)
        parts[#parts + 1] = string.sub(field, cursor, (dot or (#field + 1)) - 1)
        if dot == nil then break end
        cursor = dot + 1
    end
    return parts
end

function Schema.pathKey(part)
    if string.match(part, "^%d+$") ~= nil and #part < 9 then return tonumber(part) end
    return part
end

function Schema.place(root, field, value, problems, section)
    local parts = Schema.splitPath(field)
    local count = #parts
    local node = root
    for index = 1, count - 1 do
        local key = Schema.pathKey(parts[index])
        local child = node[key]
        if child == nil then
            child = {}
            node[key] = child
        elseif type(child) ~= "table" then
            problems[#problems + 1] = "path_conflict:" .. section .. "." .. field
            return false
        end
        node = child
    end
    local last = Schema.pathKey(parts[count])
    if type(node[last]) == "table" then
        problems[#problems + 1] = "path_conflict:" .. section .. "." .. field
        return false
    end
    node[last] = value
    return true
end

function Schema.unflatten(record)
    local tree, problems = {}, {}
    if type(record) ~= "table" then return tree, problems end
    for section, bucket in pairs(record) do
        if type(bucket) == "table" then
            local root = {}
            tree[section] = root
            for field, value in pairs(bucket) do
                Schema.place(root, tostring(field), value, problems, tostring(section))
            end
        end
    end
    return tree, problems
end

Schema.ATOMS = {}

function Schema.addAtom(name, spec)
    if not Schema.validName(name) or type(spec) ~= "table" then return false end
    if Schema.ATOMS[name] ~= nil then return false end
    Schema.ATOMS[name] = { arg = spec.arg or "none", cmp = spec.cmp or "none" }
    return true
end

for _, name in ipairs({ "trust", "imin", "gmin", "rsec", "insideSec", "nearPlayer", "visits", "lastgap", "day" }) do
    Schema.addAtom(name, { arg = "none", cmp = "req" })
end
for _, name in ipairs({ "night", "dawn", "rain", "coldout", "inside", "door", "alone", "partner",
        "partnerGone", "power", "armed", "adult", "wet", "bloody", "minorPresent" }) do
    Schema.addAtom(name, { arg = "none", cmp = "none" })
end
for _, name in ipairs({ "room", "pRoom", "poi", "act", "wit", "pwit", "gave", "gaveever", "mood", "did",
        "carry", "vice" }) do
    Schema.addAtom(name, { arg = "word", cmp = "none" })
end
for _, name in ipairs({ "knows", "heard", "flag", "gflag", "belief", "want" }) do
    Schema.addAtom(name, { arg = "id", cmp = "none" })
end
Schema.addAtom("clean", { arg = "none", cmp = "none" })
Schema.addAtom("fresh", { arg = "none", cmp = "none" })
Schema.addAtom("dress", { arg = "word", cmp = "none" })
Schema.addAtom("hour", { arg = "hours", cmp = "none" })
Schema.addAtom("psex", { arg = "sex", cmp = "none" })
Schema.addAtom("asked", { arg = "qid", cmp = "opt" })
Schema.addAtom("need", { arg = "word", cmp = "req" })
Schema.addAtom("trait", { arg = "word", cmp = "req" })
for _, name in ipairs({ "morning", "staynear", "leaving" }) do
    Schema.addAtom(name, { arg = "none", cmp = "none" })
end
Schema.addAtom("bond", { arg = "word", cmp = "none" })
Schema.addAtom("opt", { arg = "word", cmp = "none" })
Schema.addAtom("pneed", { arg = "word", cmp = "req" })

Schema.OPTIONS = {
    { key = "Visitors_Persons", field = "persons", kind = "boolean", default = true },
    { key = "Visitors_ProactiveEvents", field = "proactiveLevel", kind = "enum", min = 1, max = 4, default = 3 },
    { key = "Visitors_EventMinGapSeconds", field = "eventMinGapSeconds", kind = "integer", min = 60, max = 1800, default = 240 },
    { key = "Visitors_StayHours", field = "stayHours", kind = "integer", min = 1, max = 48, default = 1 },
    { key = "Visitors_Parties", field = "parties", kind = "boolean", default = true },
    { key = "Visitors_ReturningChance", field = "returningChance", kind = "integer", min = 0, max = 50, default = 15 },
    { key = "Visitors_Life", field = "life", kind = "boolean", default = true },
    { key = "Visitors_ChangeClothes", field = "changeClothes", kind = "boolean", default = true },
    { key = "Visitors_Privacy", field = "privacy", kind = "enum", min = 1, max = 2, default = 1 },
    { key = "Visitors_Flirt", field = "flirtLevel", kind = "enum", min = 1, max = 2, default = 2 },
    { key = "Visitors_Books", field = "books", kind = "boolean", default = true },
    { key = "Visitors_ChatMirror", field = "chatMirror", kind = "boolean", default = true },
    { key = "Visitors_Debug", field = "debug", kind = "boolean", default = false },
}

Schema.PROACTIVE = { { name = "Off" }, { name = "Rare", gap = 2.0 }, { name = "Normal", gap = 1.0 },
    { name = "Often", gap = 0.6 } }

function Schema.deriveOptions(options)
    options.proactive = options.proactiveLevel > 1
    local row = Schema.PROACTIVE[options.proactiveLevel]
    options.eventGapScale = row ~= nil and row.gap or nil
    options.privacyStrict = options.privacy == 1
    options.flirt = options.flirtLevel == 2
    return options
end

function Schema.options(source)
    if source == nil and type(SandboxVars) == "table" then source = SandboxVars.ALife end
    if type(source) ~= "table" then source = {} end
    local result = {}
    for index = 1, #Schema.OPTIONS do
        local row = Schema.OPTIONS[index]
        local value = source[row.key]
        if row.kind == "boolean" then
            if type(value) ~= "boolean" then value = row.default end
        else
            value = Schema.clampInt(value, row.min, row.max, row.default)
        end
        result[row.field] = value
    end
    return Schema.deriveOptions(result)
end

return Schema
