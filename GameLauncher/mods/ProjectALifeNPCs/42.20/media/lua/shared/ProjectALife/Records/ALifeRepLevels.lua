require "ProjectALife/Core/ALifeText"

ProjectALife = ProjectALife or {}

local Levels = {}
ProjectALife.RepLevels = Levels

Levels.scoreMin, Levels.scoreMax = -1000, 1000
Levels.hysteresis = 15

Levels.cells = {
    friendly = { stance = "friendly" },
    friendly_waved = { stance = "friendly", waved = true },
    careful = { stance = "careful" },
    careful_last = { stance = "careful", ladderFrom = "last" },
    careful_hide = { stance = "careful", hide = true },
    neutral_fear = { stance = "neutral", fear = true },
    neutral_bargain = { stance = "neutral", bargain = true },
}

local GOOD_HIGH = { law = "friendly_waved", civilian = "friendly", family = "friendly", crime = "careful" }

Levels.rows = {
    { id = "rep_n5", blurb = "Everyone who has heard of you locks the door. Most would sooner pay than fight you, and nobody turns their back.", min = -1000, en = "The Villain", drift = false, robbery = "bargain",
        bloc = { law = "careful_last", military = "careful_last", civilian = "careful_hide",
            family = "careful_hide", crime = "neutral_fear" } },
    { id = "rep_n4", blurb = "You are known for taking what you want. Travellers hide when you come near, and the lawful watch you from a distance.", min = -799, en = "Raider", drift = false, robbery = "bargain",
        bloc = { law = "careful_last", civilian = "careful_hide", family = "careful_hide", crime = "neutral_bargain" } },
    { id = "rep_n3", blurb = "The word about your robberies has spread. People hand things over before you ask, and the law is keeping count.", min = -549, en = "Cutthroat", drift = false, robbery = "bargain",
        bloc = { law = "careful_last", civilian = "careful_hide", family = "careful_hide", crime = "neutral_bargain" } },
    { id = "rep_n2", blurb = "You have crossed lines people remember. Honest folk keep their distance, but rough crowds will hear you out.", min = -349, en = "Outlaw",
        bloc = { law = "careful", civilian = "careful_hide", crime = "neutral_bargain" } },
    { id = "rep_n1", blurb = "You take from people who are already down. Nobody calls you an enemy yet, though the gangs have started to nod at you.", min = -174, en = "Vulture",
        bloc = { law = "careful", civilian = "careful_hide", crime = "neutral_bargain" } },
    { id = "rep_0", blurb = "Nobody here has a story about you. People take you as they find you.", min = -59, en = "Neutral", neutral = true, bloc = {} },
    { id = "rep_p1", blurb = "You have lent a hand more than once. Law and civilians are quicker to hear you out, and more of them knock to ask for help.", min = 60, en = "Helper", bloc = { law = "friendly", civilian = "friendly" } },
    { id = "rep_p2", blurb = "People talk about the day you stood between them and trouble. Traders ask a fairer price, and the needy know your door.", min = 175, en = "Protector", bloc = { law = "friendly", civilian = "friendly" } },
    { id = "rep_p3", blurb = "Law, families and civilians trust your word, and strangers wave before they ask your business. Gangs think a house like yours is an easy mark.", min = 350, en = "Sheriff", bloc = GOOD_HIGH },
    { id = "rep_p4", blurb = "Stories of what you did travel faster than you do. Most doors open for you.", min = 550, en = "Hero", bloc = GOOD_HIGH },
    { id = "rep_p5", blurb = "Survivors who have never met you know your name, and what they say about it is good.", min = 800, en = "The Legend", bloc = GOOD_HIGH },
}

Levels.blocs = {
    law = { factions = { "law" }, registers = { "law", "swat" } },
    military = { factions = { "military", "elite" }, registers = { "military", "elite" } },
    civilian = { factions = { "civilian", "worker", "rescue" }, registers = { "civilian", "worker", "rescue" } },
    family = { factions = { "family" }, registers = { "family" } },
    crime = { factions = { "crime", "gang", "club", "prison" },
        registers = { "outlaw", "gang", "club", "crime", "prison" } },
    raider = { factions = { "raider" }, registers = { "raider" } },
}

Levels.factionBlocs = { alife_ashguard = "military", alife_drifters = "crime", alife_blacktop = "raider" }

function Levels.blurb(id)
    local row = Levels.rowOf(id)
    return row ~= nil and row.blurb or nil
end

function Levels.count()
    return #Levels.rows
end

function Levels.indexOf(id)
    if id == nil then return nil end
    local rows = Levels.rows
    for index = 1, #rows do
        if rows[index].id == id then return index end
    end
    return nil
end

function Levels.rowOf(id)
    local index = Levels.indexOf(id)
    return index and Levels.rows[index] or nil
end

function Levels.neutralIndex()
    local rows = Levels.rows
    for index = 1, #rows do
        if rows[index].neutral == true then return index end
    end
    return math.floor((#rows + 1) / 2)
end

function Levels.neutralId()
    return Levels.rows[Levels.neutralIndex()].id
end

function Levels.band(id)
    local index = Levels.indexOf(id)
    if index == nil then return nil end
    local middle = Levels.neutralIndex()
    if index < middle then return "bad" end
    if index > middle then return "good" end
    return "neutral"
end

function Levels.endOf(id)
    local index = Levels.indexOf(id)
    if index == nil then return nil end
    if index == 1 then return "worst" end
    if index == #Levels.rows then return "best" end
    return nil
end

function Levels.tiers(id)
    local band = Levels.band(id)
    if band == nil then return { "neutral" } end
    if band == "neutral" then return { "neutral" } end
    local ends = Levels.endOf(id)
    local tiers = {}
    if ends ~= nil then tiers[#tiers + 1] = ends end
    tiers[#tiers + 1] = band
    tiers[#tiers + 1] = "neutral"
    return tiers
end

function Levels.clamp(score)
    local value = tonumber(score) or 0
    if value < Levels.scoreMin then value = Levels.scoreMin end
    if value > Levels.scoreMax then value = Levels.scoreMax end
    return value
end

function Levels.rangeOf(index)
    local rows = Levels.rows
    local row = rows[index]
    if row == nil then return nil, nil end
    local nextRow = rows[index + 1]
    local top = Levels.scoreMax
    if nextRow ~= nil then top = nextRow.min - 1 end
    return row.min, top
end

function Levels.at(score, previousId, hysteresis)
    local value = Levels.clamp(score)
    local band = tonumber(hysteresis) or Levels.hysteresis
    local previous = Levels.indexOf(previousId)
    if previous ~= nil and band > 0 then
        local low, high = Levels.rangeOf(previous)
        if value >= low - band and value <= high + band then return Levels.rows[previous] end
    end
    local rows = Levels.rows
    local found = rows[1]
    for index = 1, #rows do
        if value >= rows[index].min then found = rows[index] end
    end
    return found
end

function Levels.cell(id, repBloc)
    local row = Levels.rowOf(id)
    if row == nil or type(row.bloc) ~= "table" or repBloc == nil then return nil end
    local word = row.bloc[repBloc]
    if word == nil then return nil end
    return Levels.cells[word], word
end

function Levels.drifts(id)
    local row = Levels.rowOf(id)
    return row ~= nil and row.drift ~= false
end

function Levels.robbery(id)
    local row = Levels.rowOf(id)
    return row and row.robbery or nil
end

function Levels.repBlocOf(factionBloc, factionId)
    if factionBloc ~= nil then
        for repBloc, entry in pairs(Levels.blocs) do
            for _, bloc in ipairs(entry.factions) do
                if bloc == factionBloc then return repBloc end
            end
        end
    end
    if factionId ~= nil then return Levels.factionBlocs[tostring(factionId)] end
    return nil
end

function Levels.repBlocOfRegister(register)
    if register == nil then return nil end
    for repBloc, entry in pairs(Levels.blocs) do
        for _, name in ipairs(entry.registers) do
            if name == register then return repBloc end
        end
    end
    return nil
end

function Levels.name(id)
    local row = Levels.rowOf(id)
    if row == nil then return nil end
    local text = ProjectALife.Text
    if text ~= nil and type(text.ui) == "function" then return text.ui(row.en) end
    return row.en
end

function Levels.hint(id)
    local row = Levels.rowOf(id)
    if row == nil or type(row.hint) ~= "string" or row.hint == "" then return nil end
    local text = ProjectALife.Text
    if text ~= nil and type(text.ui) == "function" then return text.ui(row.hint) end
    return row.hint
end

return Levels
