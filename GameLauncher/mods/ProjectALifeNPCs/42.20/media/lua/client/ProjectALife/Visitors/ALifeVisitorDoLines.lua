require "ProjectALife/Talk/ALifeVisitorDoLines"
require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorText"
require "ProjectALife/Visitors/ALifeVisitorRule"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Text = ProjectALife.VisitorText
local Rule = ProjectALife.VisitorRule
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance

local DoLines = ProjectALife.VisitorDoLines or {}
ProjectALife.VisitorDoLines = DoLines

DoLines.corpus = {
    poolIds = { "VP_DOLINES_FRESH" },
    families = {
        rural_elder = "V01 V16 VX24", young = "V02 VX23 VX29", working = "V03 V06 V11 V12 V13 VX27",
        professional = "V04 V14 VX25 VX28 VX30", religious = "V05 VX26", service_law = "V07 V08 V09 V10",
        wry = "V15 V20 VX21 VX22", rough = "V17 V18 V19",
    },
    familyOf = {},
    maxLines = 3,
    maxLength = 96,
    metrics = { picks = 0, empty = 0, gated = 0 },
}
for family, voices in pairs(DoLines.corpus.families) do
    for voice in string.gmatch(voices, "%S+") do DoLines.corpus.familyOf[voice] = family end
end

function DoLines.corpusCache()
    return {}
end

function DoLines.corpusParse(record)
    local tree = Schema.unflatten(record)
    local pool = { id = record.id, entries = {}, adult = type(tree.p) == "table" and Schema.bool(tree.p.adult) == true }
    local source = type(tree.t) == "table" and tree.t or {}
    for family, bands in pairs(source) do
        if type(family) == "string" and type(bands) == "table" then
            for band, items in pairs(bands) do
                if type(items) == "table" then
                    local gate = type(tree.g) == "table" and type(tree.g[family]) == "table" and tree.g[family][band] or nil
                    pool.entries[family .. "." .. band] = { lines = Schema.texts(items), gate = type(gate) == "string" and gate or nil }
                end
            end
        end
    end
    return pool
end

function DoLines.corpusPool(id)
    local index = People.index()
    if index == nil then return nil end
    for position = 1, #index.generic do
        local path = index.generic[position] .. ".alife"
        if Text.ensure(path, 10) then
            local cache = Text.memo(path, "dopools", DoLines.corpusCache)
            local found = cache[id]
            if found == nil then
                local result = Text.get(path)
                local record = result ~= nil and result.byId[id] or nil
                found = (record ~= nil and record.kind == "pool") and DoLines.corpusParse(record) or false
                cache[id] = found
            end
            if found then return found end
        elseif People.reason(path) == "loading" then
            return nil
        end
    end
    return nil
end

function DoLines.clockHour()
    if type(getGameTime) ~= "function" then return 12 end
    local clock = getGameTime()
    if clock == nil or type(clock.getHour) ~= "function" then return 12 end
    return tonumber(clock:getHour()) or 12
end

function DoLines.clockHours()
    if type(getGameTime) ~= "function" then return nil end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return nil end
    return clock:getWorldAgeHours()
end

function DoLines.corpusCtx(person, card, c, trust)
    local hour = DoLines.clockHour()
    local clean = Instance.cleanState(person, DoLines.clockHours())
    local mood = c.mood or person.mood
    return {
        trust = trust,
        clean = clean ~= "dirty",
        fresh = clean == "fresh",
        mood = function(arg) return mood == arg end,
        need = function(arg) return Instance.need(person, arg) end,
        trait = function(arg) return card.traits[arg] or 0 end,
        act = function(arg) return person.act == arg end,
        dress = function(arg) return Instance.dressState(person) == arg end,
        door = c.door == true,
        inside = c.door ~= true,
        partner = c.partner == true,
        partnerGone = c.partnerGone == true,
        adult = card.adult == true,
        night = Rule.inHours(hour, 21, 5),
        dawn = Rule.inHours(hour, 5, 7),
        morning = Rule.inHours(hour, 6, 10),
        hour = function(arg, node) return Rule.inHours(hour, node.lo, node.hi) end,
    }
end

function DoLines.corpusEntry(pool, family, band, ctx)
    local order = { family .. "." .. band, family .. ".any", "any." .. band, "any.any" }
    for position = 1, #order do
        local entry = pool.entries[order[position]]
        if entry ~= nil and #entry.lines > 0 then
            if entry.gate == nil or Rule.test(entry.gate, ctx) then return entry end
            DoLines.corpus.metrics.gated = DoLines.corpus.metrics.gated + 1
        end
    end
    return nil
end

function DoLines.corpusUsable(text)
    return type(text) == "string" and text ~= "" and #text <= DoLines.corpus.maxLength and string.find(text, "{", 1, true) == nil
end

function DoLines.lines(record, context)
    local out = {}
    local person = Instance.of(record)
    if person == nil then return out end
    local c = type(context) == "table" and context or {}
    local card = People.card(person.id)
    if card == nil then return out end
    local trust = tonumber(c.trust) or 0
    local band = trust < 16 and "lo" or (trust <= 40 and "mid" or "hi")
    local ctx = DoLines.corpusCtx(person, card, c, trust)
    local family = DoLines.corpus.familyOf[card.voice or ""] or "any"
    local pool = {}
    for index = 1, #DoLines.corpus.poolIds do
        local found = DoLines.corpusPool(DoLines.corpus.poolIds[index])
        if found ~= nil and (not found.adult or card.adult) then
            local entry = DoLines.corpusEntry(found, family, band, ctx)
            if entry ~= nil then
                for slot = 1, #entry.lines do
                    if DoLines.corpusUsable(entry.lines[slot]) then pool[#pool + 1] = entry.lines[slot] end
                end
            end
        end
    end
    if #pool == 0 then
        DoLines.corpus.metrics.empty = DoLines.corpus.metrics.empty + 1
        return out
    end
    local start = DoLines.random(#pool) + 1
    for step = 0, #pool - 1 do
        local text = pool[(start - 1 + step) % #pool + 1]
        if text ~= c.previous or #pool == 1 then out[#out + 1] = text end
        if #out >= DoLines.corpus.maxLines then break end
    end
    DoLines.corpus.metrics.picks = DoLines.corpus.metrics.picks + 1
    return out
end

function DoLines.corpusQaLine()
    local m = DoLines.corpus.metrics
    return "[ALIFE-QA] VisitorDoLines corpus picks=" .. tostring(m.picks) .. " empty=" .. tostring(m.empty) .. " gated=" .. tostring(m.gated)
end

return DoLines
