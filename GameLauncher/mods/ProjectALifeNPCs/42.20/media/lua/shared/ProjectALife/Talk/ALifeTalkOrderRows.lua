ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/ALifeTalkIntents"
require "ProjectALife/Records/ALifeRelationLayers"

local Intents = ProjectALife.TalkIntents

local Rows = {
    jobPatterns = {
        { group = "law", words = { "police", "security", "ranger", "sheriff", "officer" } },
        { group = "military", words = { "veteran", "soldier", "military", "marine" } },
        { group = "medical", words = { "doctor", "nurse", "medic", "paramedic" } },
        { group = "rescue", words = { "fire" } },
        { group = "trade", words = { "construct", "carpent", "electric", "engineer", "metal", "mechanic", "repair",
            "lumber", "farmer", "plumb", "welder" } },
        { group = "thief", words = { "burglar", "thief" } },
    },
    defs = {},
    metrics = { rows = 0 },
}
ProjectALife.TalkOrderRows = Rows

function Rows.classOf(record)
    if type(record) ~= "table" then return nil end
    local fear = ProjectALife.ModuleFear
    if fear == nil or type(fear.memberClass) ~= "function" then return nil end
    local ok, class = pcall(fear.memberClass, record)
    if ok and type(class) == "string" and class ~= "" then return class end
    return nil
end

function Rows.jobGroup(professionId)
    local id = string.lower(tostring(professionId or ""))
    if id == "" then return nil end
    if string.find(id, "fire", 1, true) ~= nil and string.find(id, "officer", 1, true) ~= nil then return "rescue" end
    for _, entry in ipairs(Rows.jobPatterns) do
        for _, word in ipairs(entry.words) do
            if string.find(id, word, 1, true) ~= nil then return entry.group end
        end
    end
    return "other"
end

function Rows.jobOf(player)
    local layers = ProjectALife.RelationLayers
    if player == nil or layers == nil or type(layers.professionOf) ~= "function" then return nil end
    local ok, id = pcall(layers.professionOf, player)
    if not ok then return nil end
    return Rows.jobGroup(id)
end

function Rows.show(row)
    return function(view)
        if row.needSurrender == true and view.surrendered ~= true then return false end
        if row.hideSurrendered == true and view.surrendered == true then return false end
        if type(row.classes) == "table" then
            local class = Rows.classOf(view.record)
            if class ~= nil and row.classes[class] ~= true then return false end
        end
        if type(row.jobs) == "table" then
            local job = Rows.jobOf(view.player)
            if job == nil or row.jobs[job] ~= true then return false end
        end
        return true
    end
end

function Rows.add(row)
    row.show = Rows.show(row)
    Rows.defs[#Rows.defs + 1] = row
    if Intents.addChoice(row) then Rows.metrics.rows = Rows.metrics.rows + 1 end
end

Intents.addGroup({ id = "Orders", label = "Orders" })

local WORKERS = { civilian = true, worker = true, rescue = true }
local ARMED = { police = true, military = true }

Rows.add({ id = "ORDER_HANDS_UP", text = "Hands up. Slow and easy.", words = "hands up", topic = "Orders",
    hideSurrendered = true, order = "hands_up",
    variants = { "Hands up. Slow and easy.", "Put your hands where I can see them.", "Hands up. Now." } })
Rows.add({ id = "ORDER_DROP_WEAPON", text = "Drop the weapon. Now.", words = "drop your weapon", topic = "Orders",
    hideSurrendered = true, order = "drop",
    variants = { "Drop the weapon. Now.", "Put it on the ground. Easy.", "Weapon down. All the way down." } })
Rows.add({ id = "ORDER_SURRENDER", text = "Drop it and get your hands up.", words = "drop it and put your hands up",
    topic = "Orders", hideSurrendered = true, order = "surrender" })
Rows.add({ id = "ORDER_ROB", text = "Hand it over. Everything you're carrying.", words = "give me your stuff",
    topic = "Orders", hideSurrendered = true, order = "rob" })
Rows.add({ id = "ORDER_GET_OUT", text = "Get out of here. Now.", words = "get out of here", topic = "Orders",
    hideSurrendered = true, order = "out" })
Rows.add({ id = "ORDER_LEAVE_AREA", text = "Take your people and clear out of this area.", words = "clear out of this area",
    topic = "Orders", hideSurrendered = true, order = "leave" })
Rows.add({ id = "ORDER_FOLLOW", text = "Fall in behind me. Move.", words = "fall in behind me", topic = "Orders",
    hideSurrendered = true, order = "follow" })
Rows.add({ id = "FRISK_WEAPONS", text = "Weapons first. Hand them over.", words = "give me your weapons", topic = "Orders",
    needSurrender = true, order = "frisk_weapons" })
Rows.add({ id = "FRISK_ITEMS", text = "Empty your pockets. Slowly.", words = "empty your pockets", topic = "Orders",
    needSurrender = true, order = "frisk_items" })
Rows.add({ id = "ORDER_AT_EASE", text = "Lower your hands. Go on.", words = "you can lower your hands", topic = "Orders",
    needSurrender = true, order = "at_ease" })

Rows.add({ id = "PRO_LAW", text = "I'm law enforcement. Talk to me.", words = "i am law enforcement", topic = "Personal",
    jobs = { law = true }, proBark = "ORD_PRO_LAW" })
Rows.add({ id = "PRO_MEDIC", text = "I've got medical training. Anybody hurt?", words = "i am a medic", topic = "Personal",
    jobs = { medical = true }, proBark = "ORD_PRO_MEDIC" })
Rows.add({ id = "PRO_MILITARY", text = "I served. Who's in charge here?", words = "i served", topic = "Personal",
    jobs = { military = true }, proBark = "ORD_PRO_MILITARY" })
Rows.add({ id = "PRO_TRADE", text = "I can fix and build things. Need a hand?", words = "i can fix things", topic = "Personal",
    jobs = { trade = true, rescue = true }, proBark = "ORD_PRO_TRADE" })
Rows.add({ id = "ASK_ORDERS", text = "What are your orders out here?", words = "what are your orders", topic = "World",
    classes = ARMED, proBark = "ORD_ASK_ORDERS" })
Rows.add({ id = "ASK_TOLL", text = "What does it cost to pass through?", words = "what does it cost to pass", topic = "World",
    classes = { criminal = true }, proBark = "ORD_ASK_TOLL" })
Rows.add({ id = "ASK_SHELTER", text = "Is anyone taking people in around here?", words = "is anyone taking people in",
    topic = "World", classes = WORKERS, proBark = "ORD_ASK_SHELTER" })

return Rows
