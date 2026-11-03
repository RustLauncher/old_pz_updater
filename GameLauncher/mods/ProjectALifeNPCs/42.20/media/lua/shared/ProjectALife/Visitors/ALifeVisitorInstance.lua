require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local People = ProjectALife.VisitorPeople
local Instance = {
    metrics = { created = 0, writes = 0, conflicts = 0, refused = 0, trimmed = 0, lastWhy = "-" },
}
ProjectALife.VisitorInstance = Instance

function Instance.lcg(seed, step)
    local value = (tonumber(seed) or 0) * 1103515245 + 12345 + (tonumber(step) or 0) * 7919
    return value % 2147483648
end

function Instance.jitter(seed, step, rand)
    if rand ~= nil then
        local drawn = tonumber(rand(3))
        if drawn ~= nil then return math.floor(drawn) - 1 end
    end
    return Instance.lcg(seed, step) % 3 - 1
end

function Instance.hours(value)
    local number = tonumber(value) or 0
    return math.floor(number * 100 + 0.5) / 100
end

function Instance.create(personId, context)
    if type(context) ~= "table" then context = {} end
    local card, reason = People.card(personId)
    if card == nil then
        Instance.metrics.lastWhy = tostring(reason)
        return nil, reason
    end
    local rand = nil
    if type(context.rand) == "function" then rand = context.rand end
    local seed = (card.seed + Schema.num(context.seed, 0)) % 2147483647
    local need = {}
    for position = 1, #Schema.NEEDS do
        local row = Schema.NEEDS[position]
        local base = card.need0[row.name] or 0
        need[row.key] = Schema.clampInt(base + Instance.jitter(seed, position, rand), 0, Schema.NEED_MAX, base)
    end
    local with = {}
    for _, id in ipairs(type(context.with) == "table" and context.with or {}) do
        if Schema.validId("person", id) and id ~= personId and #with < Schema.MAX_PARTY - 1 then
            with[#with + 1] = id
        end
    end
    local via = Schema.str(context.via)
    if via == nil or string.match(via, "^[%w_]+$") == nil or #via > 24 then via = "visit" end
    local adult = 0
    if card.adult then adult = 1 end
    local clean = 0
    if need.d <= 1 then clean = 1 end
    local person = {
        id = personId, v = 1, t0 = Instance.hours(context.now), seed = seed, via = via, need = need,
        mood = Schema.str(context.mood) or "wary", act = "stand", with = with, vt = {},
        ad = adult, ds = "dressed", cl = clean,
    }
    Instance.trim(person)
    Instance.metrics.created = Instance.metrics.created + 1
    return person
end

function Instance.of(record)
    if type(record) ~= "table" or type(record.memory) ~= "table" then return nil end
    local person = record.memory.person
    if type(person) ~= "table" or type(person.id) ~= "string" then return nil end
    return person
end

function Instance.needKey(name)
    if Schema.NEED_KEY[name] ~= nil then return Schema.NEED_KEY[name] end
    if Schema.NEED_NAME[name] ~= nil then return name end
    return nil
end

function Instance.need(person, name)
    local key = Instance.needKey(name)
    if key == nil or type(person) ~= "table" or type(person.need) ~= "table" then return 0 end
    return Schema.clampInt(person.need[key], 0, Schema.NEED_MAX, 0)
end

function Instance.setNeed(person, name, value)
    local key = Instance.needKey(name)
    if key == nil or type(person) ~= "table" then return false end
    if type(person.need) ~= "table" then person.need = {} end
    person.need[key] = Schema.clampInt(value, 0, Schema.NEED_MAX, 0)
    return true
end

function Instance.dressState(person)
    if type(person) ~= "table" or not Schema.DRESS_STATE_SET[person.ds or ""] then return "dressed" end
    return person.ds
end

function Instance.setDressState(person, state)
    if type(person) ~= "table" then return false, "person_invalid" end
    if not Schema.DRESS_STATE_SET[state or ""] then return false, "state_invalid" end
    if state ~= "dressed" and person.ad ~= 1 then
        Instance.metrics.refused = Instance.metrics.refused + 1
        return false, "adult_only"
    end
    person.ds = state
    return true
end

function Instance.cleanState(person, now)
    if type(person) ~= "table" or person.cl ~= 1 then return "dirty" end
    local washed = tonumber(person.wt)
    local hours = tonumber(now)
    if washed ~= nil and hours ~= nil then
        local gap = hours - washed
        if gap <= Schema.FRESH_HOURS then return "fresh" end
        if gap > Schema.CLEAN_HOURS then return "dirty" end
    end
    return "clean"
end

function Instance.markWashed(person, now, dirtyLevel)
    if type(person) ~= "table" then return false end
    person.cl = 1
    person.wt = Instance.hours(now)
    Instance.setNeed(person, "dirty", tonumber(dirtyLevel) or 0)
    return true
end

function Instance.markDirty(person, dirtyLevel)
    if type(person) ~= "table" then return false end
    person.cl = 0
    person.wt = nil
    if dirtyLevel ~= nil then Instance.setNeed(person, "dirty", dirtyLevel) end
    return true
end

function Instance.vt(person, playerKey, create)
    if type(person) ~= "table" or type(playerKey) ~= "string" or playerKey == "" or #playerKey > 48 then return nil end
    if type(person.vt) ~= "table" then
        if create ~= true then return nil end
        person.vt = {}
    end
    local row = person.vt[playerKey]
    if row == nil and create == true then
        row = { k = "", a = "", f = "", u = 0, n = 0, last = 0 }
        person.vt[playerKey] = row
        Instance.limitPlayers(person, playerKey)
    end
    return row
end

function Instance.limitPlayers(person, keep)
    while true do
        local count, oldestKey, oldestLast = 0, nil, nil
        for key, row in pairs(person.vt) do
            count = count + 1
            local last = type(row) == "table" and (tonumber(row.last) or 0) or -1
            if key ~= keep and (oldestKey == nil or last < oldestLast) then oldestKey, oldestLast = key, last end
        end
        if count <= Schema.VT_PLAYERS or oldestKey == nil then return end
        person.vt[oldestKey] = nil
        Instance.metrics.trimmed = Instance.metrics.trimmed + 1
    end
end

function Instance.facts(row)
    local result = {}
    if type(row) ~= "table" then return result end
    for _, piece in ipairs(Schema.csv(row.k)) do
        local number = tonumber(piece)
        if number ~= nil then result[#result + 1] = number end
    end
    return result
end

function Instance.knows(row, factIndex)
    for _, number in ipairs(Instance.facts(row)) do
        if number == factIndex then return true end
    end
    return false
end

function Instance.learn(row, factIndex)
    if type(row) ~= "table" or tonumber(factIndex) == nil then return false end
    if Instance.knows(row, factIndex) then return false end
    local text = Schema.str(row.k)
    row.k = (text ~= nil and (text .. ",") or "") .. tostring(math.floor(factIndex))
    Instance.clip(row)
    return true
end

function Instance.asked(row, questionId)
    if type(row) ~= "table" or type(questionId) ~= "string" then return 0, 0 end
    local short = string.gsub(questionId, "^VQ_", "")
    for _, piece in ipairs(Schema.split(row.a or "", ";")) do
        local id, count, variant = string.match(piece, "^([%w_]+):(%d+):(%d+)$")
        if id == short then return tonumber(count), tonumber(variant) end
    end
    return 0, 0
end

function Instance.noteAsked(row, questionId, variant)
    if type(row) ~= "table" or type(questionId) ~= "string" then return 0 end
    local short = string.gsub(questionId, "^VQ_", "")
    if string.match(short, "^[%w_]+$") == nil then return 0 end
    local kept, count = {}, 0
    for _, piece in ipairs(Schema.split(row.a or "", ";")) do
        local id, seen = string.match(piece, "^([%w_]+):(%d+):%d+$")
        if id == short then count = tonumber(seen) else kept[#kept + 1] = piece end
    end
    count = count + 1
    kept[#kept + 1] = short .. ":" .. tostring(count) .. ":" .. tostring(Schema.clampInt(variant, 0, 99, 0))
    row.a = table.concat(kept, ";")
    Instance.clip(row)
    return count
end

function Instance.flag(row, name)
    if type(row) ~= "table" or type(name) ~= "string" then return false end
    for _, piece in ipairs(Schema.csv(row.f)) do
        if piece == name then return true end
    end
    return false
end

function Instance.setFlag(row, name)
    if type(row) ~= "table" or type(name) ~= "string" or string.match(name, "^[%w_]+$") == nil then return false end
    if Instance.flag(row, name) then return false end
    local text = Schema.str(row.f)
    row.f = (text ~= nil and (text .. ",") or "") .. name
    Instance.clip(row)
    return true
end

function Instance.clearFlag(row, name)
    if type(row) ~= "table" or type(name) ~= "string" then return false end
    local kept, found = {}, false
    for _, piece in ipairs(Schema.csv(row.f)) do
        if piece == name then found = true else kept[#kept + 1] = piece end
    end
    if found then row.f = table.concat(kept, ",") end
    return found
end

function Instance.dropOldest(text, separator)
    local cut = string.find(text, separator, 1, true)
    if cut == nil then return "" end
    return string.sub(text, cut + #separator)
end

function Instance.clip(row)
    local limits = { k = ",", a = ";", f = "," }
    for field, separator in pairs(limits) do
        local text = row[field]
        if type(text) ~= "string" then
            row[field] = ""
        else
            while #text > Schema.VT_TEXT do text = Instance.dropOldest(text, separator) end
            row[field] = text
        end
    end
end

function Instance.size(value)
    local kind = type(value)
    if kind == "string" then return #value end
    if kind == "number" then return #tostring(value) end
    if kind == "boolean" then return 4 end
    if kind ~= "table" then return 0 end
    local total = 0
    for key, item in pairs(value) do total = total + #tostring(key) + Instance.size(item) + 3 end
    return total
end

function Instance.halve(row, field)
    local separator = field == "a" and ";" or ","
    local text = row[field]
    local target = math.floor(#text / 2)
    while text ~= "" and #text > target do text = Instance.dropOldest(text, separator) end
    row[field] = text
end

function Instance.longest(person)
    local bestRow, bestField, bestLength = nil, nil, 0
    for _, row in pairs(person.vt) do
        if type(row) == "table" then
            for _, field in ipairs({ "k", "a", "f" }) do
                local length = type(row[field]) == "string" and #row[field] or 0
                if length > bestLength then bestRow, bestField, bestLength = row, field, length end
            end
        end
    end
    return bestRow, bestField
end

function Instance.trim(person)
    if type(person) ~= "table" then return 0 end
    person.v = Schema.int(person.v, 1, 99) or 1
    person.t0 = Instance.hours(person.t0)
    person.seed = Schema.num(person.seed, 0)
    for _, field in ipairs({ "via", "mood", "act" }) do
        local limit = field == "via" and 24 or 16
        local text = Schema.str(person[field]) or (field == "via" and "visit" or (field == "act" and "stand" or "wary"))
        person[field] = string.sub(text, 1, limit)
    end
    if type(person.need) ~= "table" then person.need = {} end
    for position = 1, #Schema.NEEDS do
        local key = Schema.NEEDS[position].key
        person.need[key] = Schema.clampInt(person.need[key], 0, Schema.NEED_MAX, 0)
    end
    person.ad = person.ad == 1 and 1 or 0
    person.cl = person.cl == 1 and 1 or 0
    if person.wt ~= nil then person.wt = Instance.hours(person.wt) end
    if not Schema.DRESS_STATE_SET[person.ds or ""] or (person.ds ~= "dressed" and person.ad ~= 1) then
        person.ds = "dressed"
    end
    if type(person.with) ~= "table" then person.with = {} end
    while #person.with > Schema.MAX_PARTY - 1 do table.remove(person.with) end
    if type(person.vt) ~= "table" then person.vt = {} end
    for _, row in pairs(person.vt) do
        if type(row) == "table" then Instance.clip(row) end
    end
    Instance.limitPlayers(person, nil)
    local guard = 0
    while Instance.size(person) > Schema.INSTANCE_BYTES and guard < 128 do
        guard = guard + 1
        local row, field = Instance.longest(person)
        if row == nil then break end
        Instance.halve(row, field)
        Instance.metrics.trimmed = Instance.metrics.trimmed + 1
    end
    return Instance.size(person)
end

function Instance.write(uid, mutate, options)
    if type(mutate) ~= "function" then return false, "mutation_invalid" end
    if type(isClient) == "function" and isClient() == true then
        Instance.metrics.refused = Instance.metrics.refused + 1
        return false, "client_write_refused"
    end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.peek) ~= "function" or type(registry.update) ~= "function" then
        return false, "registry_unavailable"
    end
    local current = registry.peek(uid)
    if current == nil then return false, "actor_not_found" end
    if type(options) ~= "table" then options = {} end
    local revision = tonumber(options.revision) or current.revision
    local update = registry.update
    if options.transient == true and type(registry.updateTransient) == "function" then update = registry.updateTransient end
    local updated, reason = update(uid, revision, function(candidate)
        if type(candidate.memory) ~= "table" then candidate.memory = {} end
        mutate(candidate.memory)
        if type(candidate.memory.person) == "table" then Instance.trim(candidate.memory.person) end
    end)
    if updated == nil then
        Instance.metrics.lastWhy = tostring(reason)
        if reason == "actor_revision_conflict" then Instance.metrics.conflicts = Instance.metrics.conflicts + 1 end
        return false, reason
    end
    Instance.metrics.writes = Instance.metrics.writes + 1
    return true
end

function Instance.qaLine()
    local m = Instance.metrics
    return "[ALIFE-QA] VisitorInstance created=" .. tostring(m.created) .. " writes=" .. tostring(m.writes)
        .. " conflicts=" .. tostring(m.conflicts) .. " refused=" .. tostring(m.refused)
        .. " trimmed=" .. tostring(m.trimmed) .. " why=" .. tostring(m.lastWhy)
end

return Instance
