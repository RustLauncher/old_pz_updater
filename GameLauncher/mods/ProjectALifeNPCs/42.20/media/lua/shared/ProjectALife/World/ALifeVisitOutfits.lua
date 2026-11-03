require "ProjectALife/Visitors/ALifeVisitorClothing"

ProjectALife = ProjectALife or {}

local Outfits = { metrics = { applied = 0, skippedPerson = 0, skippedUniform = 0, collided = 0, carried = 0 } }
ProjectALife.VisitOutfits = Outfits

local function row(role, entries, extra)
    local made = { role = role, entries = entries }
    for key, value in pairs(extra or {}) do made[key] = value end
    return made
end

local function piece(slot, itemType)
    return { slot = slot, itemType = itemType, tint = "" }
end

local SHERIFF = { piece("shirt", "Base.Shirt_Sheriff"), piece("pants", "Base.Trousers_PoliceGrey"),
    piece("shoes", "Base.Shoes_Black"), piece("hat", "Base.Hat_Sheriff"), piece("belt", "Base.Belt2") }
local SHERIFF_WARM = { piece("jacket", "Base.Jacket_Sheriff") }
local DEPUTY_KIT = { "Base.Badge", "Base.Notebook", "Base.Pen" }
local SCRUBS = { piece("shirt", "Base.Shirt_Scrubs"), piece("pants", "Base.Trousers_Scrubs"), piece("shoes", "Base.Shoes_Black") }
local SCRUBS_WARM = { piece("jacketsuit", "Base.JacketLong_Doctor") }
local MEDIC_KIT = { "Base.Bandage", "Base.Bandage", "Base.Disinfectant", "Base.Stethoscope", "Base.Tweezers" }
local WORKER = { piece("shirt", "Base.Shirt_Workman"), piece("pants", "Base.Trousers_Denim"), piece("shoes", "Base.Shoes_WorkBoots") }
local DRAB = { piece("shirt", "Base.Shirt_Denim"), piece("pants", "Base.Trousers_Black"), piece("shoes", "Base.Shoes_Brown") }

Outfits.events = {
    law_guns = row("law", SHERIFF, { warm = SHERIFF_WARM, carry = { "Base.Badge", "Base.Nightstick", "Base.Notebook" }, ifBare = true }),
    law_census = row("law", SHERIFF, { warm = SHERIFF_WARM, carry = DEPUTY_KIT, ifBare = true }),
    law_stay_inside = row("law", SHERIFF, { warm = SHERIFF_WARM, carry = { "Base.Badge", "Base.Whistle" }, ifBare = true }),
    law_fake = row("law", { piece("shirt", "Base.Shirt_PoliceBlue"), piece("pants", "Base.Trousers_Black"),
        piece("shoes", "Base.Shoes_RedTrainers"), piece("hat", "Base.Hat_BaseballCap_Police_Reverse") },
        { warm = { piece("jacket", "Base.Jacket_Black") }, carry = {}, tell = "no_badge",
            wrong = { "no badge", "reversed cap", "trainers", "plain trousers" } }),
    medic_rounds = row("medical", SCRUBS, { warm = SCRUBS_WARM, carry = MEDIC_KIT }),
    medical_visit = row("medical", {}, { person = true }),
    preacher = row("clergy", { piece("shirt", "Base.Shirt_Priest"), piece("pants", "Base.Trousers_Suit"),
        piece("shoes", "Base.Shoes_Black") }, { warm = { piece("jacketsuit", "Base.Suit_Jacket") }, carry = { "Base.Notebook", "Base.Pen" } }),
    trader = row("trader", { piece("shirt", "Base.Shirt_Lumberjack"), piece("pants", "Base.Trousers_Denim"),
        piece("shoes", "Base.Shoes_WorkBoots"), piece("hat", "Base.Hat_BaseballCap") }, { warm = { piece("jacket", "Base.Jacket_NavyBlue") },
        carry = { "Base.Bag_ALICEpack", "Base.Notebook", "Base.Pen" } }),
    messenger = row("courier", { piece("shirt", "Base.Shirt_Denim"), piece("pants", "Base.Trousers_Denim"),
        piece("shoes", "Base.Shoes_TrainerTINT"), piece("hat", "Base.Hat_BaseballCap") }, { warm = { piece("jacket", "Base.Jacket_NavyBlue") },
        carry = { "Base.Bag_Satchel", "Base.SheetPaper2", "Base.Pen" } }),
    neighbour = row("neighbour", WORKER, { warm = { piece("jacket", "Base.Jacket_Black") }, carry = {} }),
    neighbour_borrow = row("neighbour", WORKER, { warm = { piece("jacket", "Base.Jacket_Black") }, carry = { "Base.Pen" } }),
    returning_things = row("neighbour", WORKER, { warm = { piece("jacket", "Base.Jacket_NavyBlue") }, carry = {} }),
    radio_rumour = row("neighbour", { piece("shirt", "Base.Shirt_Denim"), piece("pants", "Base.Trousers_Denim"),
        piece("shoes", "Base.Shoes_Brown") }, { warm = { piece("jacket", "Base.Jacket_NavyBlue") }, carry = { "Base.RadioReceiver" } }),
    beggar = row("needy", DRAB, { warm = {}, carry = {} }),
    sleep_one_night = row("needy", DRAB, { warm = { piece("jacket", "Base.Jacket_Black") }, carry = { "Base.Bag_Satchel" } }),
    chased = row("needy", DRAB, { warm = {}, carry = {} }),
    wounded = row("needy", DRAB, { warm = {}, carry = {} }),
    asks_help = row("needy", WORKER, { warm = { piece("jacket", "Base.Jacket_Black") }, carry = {} }),
    racket = row("crime", DRAB, { keepFaction = true, carry = {} }),
    drunk = row("drunk", { piece("shirt", "Base.Shirt_HawaiianRed"), piece("pants", "Base.Trousers_Denim"), piece("shoes", "Base.Shoes_Brown") },
        { warm = { piece("jacket", "Base.Jacket_Black") }, carry = { "Base.Whiskey" } }),
    family_in_need = row("civilian", {}, { person = true }),
    returning_guest = row("civilian", {}, { person = true }),
    lodger_request = row("civilian", {}, { person = true }),
    panic_knock = row("civilian", {}, { person = true }),
    weather_shelter = row("civilian", {}, { person = true }),
}

Outfits.coldSeasons = { autumn = true, winter = true }

function Outfits.row(event)
    return Outfits.events[event]
end

function Outfits.lookup()
    return ProjectALife.ClothingMaster
end

function Outfits.copy(list)
    local copy = {}
    for index, entry in ipairs(list or {}) do copy[index] = entry end
    return copy
end

function Outfits.entriesFor(event, season)
    local rowData = Outfits.events[event]
    if rowData == nil then return nil end
    local list = Outfits.copy(rowData.entries)
    if Outfits.coldSeasons[season] == true and type(rowData.warm) == "table" then
        for _, entry in ipairs(rowData.warm) do list[#list + 1] = entry end
    end
    return list
end

function Outfits.merge(current, wanted)
    local master = Outfits.lookup()
    local list = Outfits.copy(current)
    local placed, collided = 0, 0
    for _, entry in ipairs(wanted) do
        local accepted, replaced, why = true, {}, nil
        if master ~= nil and type(master.accepts) == "function" then accepted, replaced, why = master.accepts(list, entry.itemType) end
        if not accepted and why == "unknown_item" then accepted, replaced = true, {} end
        if accepted then
            for _, old in ipairs(replaced or {}) do
                for position = #list, 1, -1 do
                    if list[position] == old then table.remove(list, position) end
                end
            end
            list[#list + 1] = { slot = entry.slot, itemType = entry.itemType, tint = entry.tint or "" }
            placed = placed + 1
        else
            collided = collided + 1
        end
    end
    if master ~= nil and type(master.ordered) == "function" then list = master.ordered(list) end
    return list, placed, collided
end

function Outfits.itemsOf(event)
    local rowData = Outfits.events[event]
    if rowData == nil or type(rowData.carry) ~= "table" then return {} end
    return rowData.carry
end

function Outfits.apply(plan, actor, season, uniformOf)
    if type(plan) ~= "table" or type(actor) ~= "table" or type(actor.memory) ~= "table" then return plan end
    local memory = actor.memory
    if memory.person ~= nil then
        Outfits.metrics.skippedPerson = Outfits.metrics.skippedPerson + 1
        return plan
    end
    local visit = memory.visit
    if type(visit) ~= "table" then return plan end
    local rowData = Outfits.events[visit.event]
    if rowData == nil or rowData.person == true or rowData.keepFaction == true then return plan end
    if rowData.ifBare == true and type(uniformOf) == "function" and type(plan.clothing) == "table"
            and uniformOf(plan.clothing) ~= nil then
        Outfits.metrics.skippedUniform = Outfits.metrics.skippedUniform + 1
        return plan
    end
    local wanted = Outfits.entriesFor(visit.event, season)
    if wanted ~= nil and #wanted > 0 then
        local merged, placed, collided = Outfits.merge(plan.clothing, wanted)
        plan.clothing = merged
        Outfits.metrics.collided = Outfits.metrics.collided + collided
        if placed > 0 then Outfits.metrics.applied = Outfits.metrics.applied + 1 end
    end
    local carry = Outfits.itemsOf(visit.event)
    if #carry > 0 then
        local extra = type(plan.extraItems) == "table" and plan.extraItems or {}
        for _, itemType in ipairs(carry) do extra[#extra + 1] = itemType end
        plan.extraItems = extra
        Outfits.metrics.carried = Outfits.metrics.carried + #carry
    end
    return plan
end

function Outfits.tell(event)
    local rowData = Outfits.events[event]
    return rowData ~= nil and rowData.tell or nil
end

function Outfits.qaLine()
    local m = Outfits.metrics
    return "[ALIFE-QA] VisitOutfits applied=" .. m.applied .. " skippedPerson=" .. m.skippedPerson
        .. " skippedUniform=" .. m.skippedUniform .. " collided=" .. m.collided .. " carried=" .. m.carried
end

return Outfits
