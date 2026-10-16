require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorRule"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorTalkRules"

ProjectALife = ProjectALife or {}

local Rule = ProjectALife.VisitorRule
local Instance = ProjectALife.VisitorInstance
local Rules = ProjectALife.VisitorTalkRules

local Flirt = {
    needs = {},
    metrics = { guarded = 0, accepted = 0, declined = 0, closed = 0, faded = 0 },
    structural = { adult_only = true, minor_present = true, option_off = true, no_flirt = true, no_attract = true,
        sex_unknown = true, closed = true },
    closeIds = { VQ_CLOSER_ENOUGH = true },
    minTrust = 41,
    minInside = 60,
    stageTrust = { 41, 55, 70 },
}
ProjectALife.VisitorFlirt = Flirt

function Flirt.stage(env)
    local row = Rules.row(env)
    if Instance.flag(row, "F3") then return 3 end
    if Instance.flag(row, "F2") then return 2 end
    if Instance.flag(row, "F1") then return 1 end
    return 0
end

function Flirt.closed(env)
    local row = Rules.row(env)
    return Instance.flag(row, "FNO") or Instance.flag(row, "FD")
end

function Flirt.attracted(env, card)
    local raw = Rules.rawCard(card.id)
    if raw == nil or raw.attract == nil or raw.attract == "" then return false end
    local speech = ProjectALife.Speech
    local sex = speech ~= nil and type(speech.sexOf) == "function" and speech.sexOf(env.player) or nil
    if sex == nil then return nil end
    for piece in string.gmatch(tostring(raw.attract), "[^,]+") do
        if piece == sex or piece == "any" then return true end
    end
    return false
end

function Flirt.threatened(env)
    local person = env.person
    if Rules.atoms.armed(env) then return true end
    if Instance.flag(Rules.row(env), "D_threatened") then return true end
    return person.mood == "scared" or person.mood == "hot"
end

function Flirt.guard(env)
    local person = env.person
    if person == nil then return false, "adult_only" end
    if not Rules.adult(env) then return false, "adult_only" end
    if Rules.atoms.minorPresent(env) then return false, "minor_present" end
    if Rules.options().flirt ~= true then return false, "option_off" end
    local card = Rules.card(env)
    if card == nil then return false, "adult_only" end
    if card.traits.flirt < 1 then return false, "no_flirt" end
    local attracted = Flirt.attracted(env, card)
    if attracted == nil then return false, "sex_unknown" end
    if attracted == false then return false, "no_attract" end
    if Flirt.closed(env) then return false, "closed" end
    if Rules.trust(env) < Flirt.minTrust then return false, "trust" end
    if Rules.atoms.imin(env) < Flirt.minInside then return false, "early" end
    if Flirt.threatened(env) then return false, "threat" end
    return true
end

function Flirt.walk(node, found)
    if node.t == "atom" then
        if node.name == "trait" and node.arg == "flirt" and node.cmp == ">=" then found.flirt = math.max(found.flirt, node.num or 0) end
        if node.name == "trust" and node.cmp == ">=" then found.trust = math.max(found.trust, node.num or 0) end
    elseif node.t == "and" or node.t == "or" then
        for position = 1, #node.list do Flirt.walk(node.list[position], found) end
    elseif node.t == "not" then
        Flirt.walk(node.a, found)
    end
end

function Flirt.need(question)
    local cached = Flirt.needs[question.id]
    if cached ~= nil then return cached end
    local found = { flirt = 0, trust = 0 }
    local ast = question.see ~= nil and Rule.parse(question.see) or nil
    if ast ~= nil then Flirt.walk(ast, found) end
    found.stage = math.max(1, math.min(3, found.flirt))
    Flirt.needs[question.id] = found
    return found
end

function Flirt.isFlirt(question)
    return question.kind == "flirt" or question.tab == "closer"
end

function Flirt.rowOk(env, question)
    if not Flirt.isFlirt(question) then return true end
    if not Flirt.guard(env) then return false end
    local need = Flirt.need(question)
    local card = Rules.card(env)
    if card == nil or card.traits.flirt < need.stage then return false end
    return Flirt.stage(env) >= need.stage - 1
end

function Flirt.declineKind(env, card)
    local person = env.person
    if Instance.need(person, "sick") >= 2 then return "sick" end
    if Instance.need(person, "fear") >= 3 then return "scared" end
    if card.traits.pride >= 4 or card.traits.temper >= 4 then return "firm" end
    return "kind"
end

function Flirt.decline(env, card, question, why, preview)
    if not preview then Flirt.metrics.declined = Flirt.metrics.declined + 1 end
    return { accept = false, decline = Flirt.declineKind(env, card), reason = why, set = { "FNO" }, clr = { "FA1" },
        note = "flirt_declined", stage = Flirt.stage(env) }
end

function Flirt.decide(env, question, session, preview)
    local ok, why = Flirt.guard(env)
    if not ok and Flirt.structural[why] == true then
        if not preview then Flirt.metrics.guarded = Flirt.metrics.guarded + 1 end
        return { refused = why }
    end
    local card = Rules.card(env)
    local current = Flirt.stage(env)
    if Flirt.closeIds[question.id] == true then
        if not preview then Flirt.metrics.closed = Flirt.metrics.closed + 1 end
        return { accept = true, close = true, step = "close", set = { "FNO" }, clr = { "FA1" }, stage = current }
    end
    if not ok then return Flirt.decline(env, card, question, why, preview) end
    local need = Flirt.need(question)
    local target = need.stage
    if card.traits.flirt < target then return Flirt.decline(env, card, question, "trait", preview) end
    if Rules.trust(env) < Flirt.stageTrust[target] or target > current + 1 then
        return Flirt.decline(env, card, question, "not_yet", preview)
    end
    local kind = Flirt.declineKind(env, card)
    if kind == "sick" or kind == "scared" then return Flirt.decline(env, card, question, kind, preview) end
    if target < 3 then
        if target <= current then return { accept = true, step = "keep", stage = current, set = {}, clr = {} } end
        if not preview then Flirt.metrics.accepted = Flirt.metrics.accepted + 1 end
        return { accept = true, step = "open", stage = target, set = { "F" .. target }, clr = {}, note = "flirt_accepted",
            node = "closer.f" .. target .. "_open", pool = "VP_CLOSER_F" .. target .. "_OPEN" }
    end
    local agreed = Instance.flag(Rules.row(env), "FA1")
    local consecutive = session ~= nil and session.lastFlirt == "F3"
    if agreed and consecutive then
        if not preview then
            Flirt.metrics.accepted = Flirt.metrics.accepted + 1
            Flirt.metrics.faded = Flirt.metrics.faded + 1
        end
        return { accept = true, step = "fade", stage = 3, set = { "F3", "FD", "bonded" }, clr = { "FA1" },
            note = "flirt_accepted", node = "closer.f3_fade", pool = "VP_CLOSER_F3_FADE", fade = true }
    end
    if not preview then Flirt.metrics.accepted = Flirt.metrics.accepted + 1 end
    return { accept = true, step = "agree", stage = 3, set = { "FA1" }, clr = {}, note = "flirt_accepted",
        node = "closer.f3_open", pool = "VP_CLOSER_F3_OPEN", kindOf = "F3" }
end

function Flirt.afterNo(env, question)
    if not Flirt.isFlirt(question) then return false end
    if not Instance.flag(Rules.row(env), "FNO") then return false end
    return Rules.card(env) ~= nil and Rules.adult(env)
end

function Flirt.qaLine()
    local m = Flirt.metrics
    return "[ALIFE-QA] VisitorFlirt guarded=" .. tostring(m.guarded) .. " accepted=" .. tostring(m.accepted)
        .. " declined=" .. tostring(m.declined) .. " closed=" .. tostring(m.closed) .. " faded=" .. tostring(m.faded)
end

return Flirt
