require "ProjectALife/Visitors/ALifeVisitorSchema"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Ledger = {
    adapters = {},
    fallback = nil,
    metrics = { notes = 0, created = 0, pruned = 0, refused = 0, memoryOnly = false, lastWhy = "-" },
}
ProjectALife.VisitorLedger = Ledger

function Ledger.store()
    if type(Ledger.adapters.store) == "function" then return Ledger.adapters.store() end
    local director = ProjectALife.SafehouseDirector
    if type(director) == "table" and type(director.store) == "function" then
        local ok, store = pcall(director.store)
        if ok and type(store) == "table" then return store end
    end
    local persistence = ProjectALife.Persistence
    if type(persistence) == "table" and type(persistence.bucket) == "function" then
        local bucket = persistence.bucket("baseHeat", { players = {} })
        if type(bucket) == "table" then return bucket end
    end
    if Ledger.fallback == nil then Ledger.fallback = {} end
    Ledger.metrics.memoryOnly = true
    return Ledger.fallback
end

function Ledger.dirty()
    if type(Ledger.adapters.dirty) == "function" then
        Ledger.adapters.dirty()
        return
    end
    local director = ProjectALife.SafehouseDirector
    if type(director) == "table" and type(director.dirty) == "function" then
        director.dirty()
        return
    end
    local persistence = ProjectALife.Persistence
    if type(persistence) == "table" and type(persistence.touch) == "function" then persistence.touch() end
end

function Ledger.map()
    local store = Ledger.store()
    if type(store) ~= "table" or type(store.visitors) ~= "table" then return nil end
    return store.visitors
end

function Ledger.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Ledger.copy(item) end
    return result
end

function Ledger.entry(personId)
    local map = Ledger.map()
    if map == nil or type(personId) ~= "string" then return nil end
    local row = map[personId]
    if type(row) ~= "table" then return nil end
    return Ledger.copy(row)
end

function Ledger.who(personId, playerKey)
    local map = Ledger.map()
    if map == nil or type(personId) ~= "string" or type(playerKey) ~= "string" then return nil end
    local row = map[personId]
    local who = type(row) == "table" and type(row.who) == "table" and row.who[playerKey] or nil
    if type(who) ~= "table" then return nil end
    return { bond = Schema.clampInt(who.b, 0, 100, 0), facts = Schema.csv(who.k), flags = Schema.csv(who.f) }
end

function Ledger.bond(personId, playerKey)
    local who = Ledger.who(personId, playerKey)
    if who == nil then return 0 end
    return who.bond
end

function Ledger.alive(personId)
    local map = Ledger.map()
    if map == nil or type(personId) ~= "string" then return true end
    local row = map[personId]
    return not (type(row) == "table" and row.d == 1)
end

function Ledger.size()
    local map = Ledger.map()
    local count = 0
    if map == nil then return 0 end
    for _ in pairs(map) do count = count + 1 end
    return count
end

function Ledger.merge(text, additions, limit, separator)
    local items = Schema.split(text or "", separator)
    for _, piece in ipairs(additions) do
        local present = false
        for position = 1, #items do
            if items[position] == piece then present = true end
        end
        if not present then items[#items + 1] = piece end
    end
    while #items > limit do table.remove(items, 1) end
    local joined = table.concat(items, separator)
    while #joined > Schema.LEDGER_TEXT and #items > 1 do
        table.remove(items, 1)
        joined = table.concat(items, separator)
    end
    return joined
end

function Ledger.list(value)
    if type(value) == "string" then return Schema.csv(value) end
    if type(value) == "table" then return Schema.texts(value) end
    return {}
end

function Ledger.applyPlayer(entry, playerKey, patch)
    if type(entry.who) ~= "table" then entry.who = {} end
    local row = entry.who[playerKey]
    if type(row) ~= "table" then
        row = { b = 0, k = "", f = "" }
        entry.who[playerKey] = row
        Ledger.limitPlayers(entry, playerKey)
    end
    if patch.bond ~= nil then row.b = Schema.clampInt(patch.bond, 0, 100, row.b) end
    if patch.bondDelta ~= nil then row.b = Schema.clampInt((tonumber(row.b) or 0) + (tonumber(patch.bondDelta) or 0), 0, 100, row.b) end
    if patch.facts ~= nil then
        local numbers = {}
        for _, piece in ipairs(Ledger.list(patch.facts)) do
            if tonumber(piece) ~= nil then numbers[#numbers + 1] = tostring(math.floor(tonumber(piece))) end
        end
        row.k = Ledger.merge(row.k, numbers, 64, ",")
    end
    if patch.flags ~= nil then
        local names = {}
        for _, piece in ipairs(Ledger.list(patch.flags)) do
            if string.match(piece, "^[%w_]+$") ~= nil then names[#names + 1] = piece end
        end
        row.f = Ledger.merge(row.f, names, Schema.LEDGER_FLAGS, ",")
    end
end

function Ledger.limitPlayers(entry, keep)
    while true do
        local count, weakest, weakestBond = 0, nil, nil
        for key, row in pairs(entry.who) do
            count = count + 1
            local bond = type(row) == "table" and (tonumber(row.b) or 0) or -1
            if key ~= keep and (weakest == nil or bond < weakestBond) then weakest, weakestBond = key, bond end
        end
        if count <= Schema.LEDGER_PLAYERS or weakest == nil then return end
        entry.who[weakest] = nil
    end
end

function Ledger.note(personId, playerKey, patch)
    if not Schema.validId("person", personId) or type(patch) ~= "table" then
        Ledger.metrics.refused = Ledger.metrics.refused + 1
        return false, "arguments_invalid"
    end
    if playerKey ~= nil and (type(playerKey) ~= "string" or playerKey == "" or #playerKey > 48) then
        Ledger.metrics.refused = Ledger.metrics.refused + 1
        return false, "player_invalid"
    end
    if type(isClient) == "function" and isClient() == true then
        Ledger.metrics.refused = Ledger.metrics.refused + 1
        Ledger.metrics.lastWhy = "client_write_refused"
        return false, "client_write_refused"
    end
    local store = Ledger.store()
    if type(store) ~= "table" then return false, "store_unavailable" end
    if type(store.visitors) ~= "table" then store.visitors = {} end
    local entry = store.visitors[personId]
    local created = false
    if type(entry) ~= "table" then
        entry = { n = 0, who = {} }
        store.visitors[personId] = entry
        created = true
    end
    local hours = tonumber(patch.hours)
    if hours ~= nil then
        entry.l = math.floor(hours * 100 + 0.5) / 100
        if entry.f == nil then entry.f = entry.l end
    end
    if patch.visit == true then entry.n = (tonumber(entry.n) or 0) + 1 end
    if patch.outcome ~= nil then entry.o = Schema.outcomeCode(patch.outcome) end
    if patch.dead == true then entry.d = 1 elseif patch.dead == false then entry.d = nil end
    if playerKey ~= nil then Ledger.applyPlayer(entry, playerKey, patch) end
    Ledger.metrics.notes = Ledger.metrics.notes + 1
    if created then
        Ledger.metrics.created = Ledger.metrics.created + 1
        Ledger.prune(hours, personId)
    end
    Ledger.dirty()
    return true
end

function Ledger.strongest(entry)
    local best = 0
    for _, row in pairs(type(entry.who) == "table" and entry.who or {}) do
        if type(row) == "table" then best = math.max(best, tonumber(row.b) or 0) end
    end
    return best
end

function Ledger.prune(now, keep)
    local map = Ledger.map()
    if map == nil then return 0 end
    local count, candidates = 0, {}
    for id, entry in pairs(map) do
        count = count + 1
        if type(entry) == "table" and entry.d ~= 1 and id ~= keep
                and not (now ~= nil and tonumber(entry.l) ~= nil and entry.l >= now) then
            candidates[#candidates + 1] = { id = id, last = tonumber(entry.l) or 0,
                strong = Ledger.strongest(entry) >= 20 and 1 or 0 }
        end
    end
    local excess = count - Schema.LEDGER_CAP
    if excess <= 0 then return 0 end
    table.sort(candidates, function(a, b)
        if a.strong ~= b.strong then return a.strong < b.strong end
        if a.last ~= b.last then return a.last < b.last end
        return a.id < b.id
    end)
    local removed = 0
    for position = 1, math.min(excess, #candidates) do
        map[candidates[position].id] = nil
        removed = removed + 1
    end
    Ledger.metrics.pruned = Ledger.metrics.pruned + removed
    return removed
end

function Ledger.qaLine()
    local map = Ledger.map()
    local entries, dead, players = 0, 0, 0
    if map ~= nil then
        for _, entry in pairs(map) do
            entries = entries + 1
            if type(entry) == "table" then
                if entry.d == 1 then dead = dead + 1 end
                for _ in pairs(type(entry.who) == "table" and entry.who or {}) do players = players + 1 end
            end
        end
    end
    local m = Ledger.metrics
    return "[ALIFE-QA] VisitorLedger entries=" .. tostring(entries) .. "/" .. tostring(Schema.LEDGER_CAP)
        .. " dead=" .. tostring(dead) .. " players=" .. tostring(players) .. " notes=" .. tostring(m.notes)
        .. " pruned=" .. tostring(m.pruned) .. " refused=" .. tostring(m.refused)
        .. " memoryOnly=" .. tostring(m.memoryOnly) .. " why=" .. tostring(m.lastWhy)
end

function Ledger.reset()
    Ledger.fallback = nil
    Ledger.metrics = { notes = 0, created = 0, pruned = 0, refused = 0, memoryOnly = false, lastWhy = "-" }
end

return Ledger
