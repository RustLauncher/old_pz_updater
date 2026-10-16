require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Records/ALifeClothingMaster"
require "ProjectALife/Visitors/ALifeVisitorClothing"
require "ProjectALife/Visitors/ALifeVisitorReact"
require "ProjectALife/Visitors/ALifeVisitorTalk"
require "ProjectALife/Visitors/ALifeVisitorWardrobe"
require "ProjectALife/Talk/ALifeTalkSupplies"

ProjectALife = ProjectALife or {}

local Instance = ProjectALife.VisitorInstance
local Master = ProjectALife.ClothingMaster
local React = ProjectALife.VisitorReact
local Talk = ProjectALife.VisitorTalk
local Wardrobe = ProjectALife.VisitorWardrobe

local Offers = {
    adapters = {},
    gifts = {},
    seq = 0,
    limits = { ttlMs = 60000, quotes = 128, gather = 256, rows = 32 },
    metrics = { pickers = 0, empty = 0, gives = 0, refused = 0, stale = 0, worn = 0, lastWhy = "-" },
}
ProjectALife.VisitorOffers = Offers

Offers.RELIEF = {
    food = { { "hunger", -2 } },
    water = { { "thirst", -3 } },
    meds = { { "pain", -1 }, { "sick", -1 } },
    blanket = { { "cold", -1 } },
}

Offers.KEYWORDS = {
    blanket = { "blanket", "quilt" },
    smokes = { "cigar", "tobacco" },
    alcohol = { "whiskey", "wine", "beer", "vodka", "rum", "gin", "brandy", "liquor", "champagne" },
    tool = { "battery", "candle", "map", "glasses", "torch", "flashlight", "hammer", "screwdriver", "saw", "wrench", "pliers" },
}

Offers.KINDS = { food = "food", water = "drink", meds = "medicine", clothes = "clothing", book = "book", tool = "tool",
    blanket = "blanket", smokes = "smokes", alcohol = "alcohol" }

function Offers.nowMs()
    if type(Offers.adapters.nowMs) == "function" then return Offers.adapters.nowMs() end
    return Talk.nowMs()
end

function Offers.fail(why)
    Offers.metrics.lastWhy = tostring(why)
    return false, why
end

function Offers.call(item, name)
    local method = item ~= nil and item[name] or nil
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, item)
    if ok then return value end
    return nil
end

function Offers.has(text, words)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) ~= nil then return true end
    end
    return false
end

function Offers.matches(item, cat)
    local supplies = ProjectALife.TalkSupplies
    local full = tostring(Offers.call(item, "getFullType") or "")
    local lowered = string.lower(full)
    local category = tostring(Offers.call(item, "getCategory") or "")
    local display = tostring(Offers.call(item, "getDisplayCategory") or "")
    if Offers.call(item, "isEquipped") == true then return false end
    if cat == "food" then return supplies ~= nil and select(2, pcall(supplies.matches, item, "ASK_FOOD")) == true end
    if cat == "water" then return supplies ~= nil and select(2, pcall(supplies.matches, item, "ASK_WATER")) == true end
    if cat == "meds" then return supplies ~= nil and select(2, pcall(supplies.matches, item, "ASK_MEDS")) == true end
    if cat == "clothes" then
        if category ~= "Clothing" then return false end
        local info = Master.layerOf(full)
        return info ~= nil and not info.isUnderwear
    end
    if cat == "book" then return category == "Literature" end
    if cat == "blanket" then return Offers.has(lowered, Offers.KEYWORDS.blanket) end
    if cat == "smokes" then return Offers.has(lowered, Offers.KEYWORDS.smokes) end
    if cat == "alcohol" then
        if Offers.call(item, "isAlcoholic") == true then return true end
        return Offers.has(lowered, Offers.KEYWORDS.alcohol)
    end
    if cat == "tool" then return display == "Tool" or Offers.has(lowered, Offers.KEYWORDS.tool) end
    return false
end

function Offers.entries(player, cat)
    local robbery = ProjectALife.ModuleRobbery
    local result = {}
    if player == nil or robbery == nil or type(robbery.gatherItems) ~= "function" then return result end
    local gathered, listed = pcall(robbery.gatherItems, player, { playerOnly = true, limit = Offers.limits.gather })
    if not gathered or type(listed) ~= "table" then return result end
    for _, entry in ipairs(listed) do
        local item = entry.source == "player" and entry.item or nil
        if item ~= nil and Offers.matches(item, cat) then
            local name = Offers.call(item, "getDisplayName")
            local full = Offers.call(item, "getFullType")
            local id = Offers.call(item, "getID")
            if type(name) == "string" and #name > 0 and type(full) == "string" and type(id) == "number" and id == id and id % 1 == 0 then
                entry.id, entry.name, entry.fullType = id, string.sub(string.gsub(name, "[<>\r\n]", ""), 1, 160), full
                result[#result + 1] = entry
            end
        end
    end
    return result
end

function Offers.keyOf(uid, player)
    local speech = ProjectALife.Speech
    local key = speech ~= nil and type(speech.playerKey) == "function" and speech.playerKey(player) or nil
    return tostring(uid) .. ":" .. tostring(key)
end

function Offers.sweep(now)
    local count, expired = 0, {}
    for key, saved in pairs(Offers.gifts) do
        if now >= saved.untilMs then expired[#expired + 1] = key else count = count + 1 end
    end
    for _, key in ipairs(expired) do Offers.gifts[key] = nil end
    return count
end

function Offers.picker(player, record, cat)
    if type(record) ~= "table" or Instance.of(record) == nil or Offers.KINDS[cat] == nil then return nil, "offer_unavailable" end
    local now = Offers.nowMs()
    local key = Offers.keyOf(record.uid, player)
    local live = Offers.sweep(now)
    if live >= Offers.limits.quotes and Offers.gifts[key] == nil then return nil, "trade_quotes_busy" end
    local entries = Offers.entries(player, cat)
    if #entries == 0 then
        Offers.gifts[key] = nil
        Offers.metrics.empty = Offers.metrics.empty + 1
        return nil, "nothing_to_give"
    end
    Offers.seq = Offers.seq + 1
    local token = tostring(record.uid) .. ":offer:" .. string.format("%.0f", Offers.seq)
    local rows, grouped = {}, {}
    for _, entry in ipairs(entries) do
        local group = entry.fullType .. ":" .. entry.name
        local row = grouped[group]
        if row == nil and #rows < Offers.limits.rows then
            row = { name = entry.name, itemId = entry.id, count = 0, kind = Offers.KINDS[cat] }
            grouped[group], rows[#rows + 1] = row, row
        end
        if row ~= nil then row.count = row.count + 1 end
    end
    Offers.gifts[key] = { token = token, uid = record.uid, generation = record.generation, untilMs = now + Offers.limits.ttlMs,
        cat = cat, entries = entries }
    Offers.metrics.pickers = Offers.metrics.pickers + 1
    return { token = token, rows = rows, cat = cat }
end

function Offers.pickerFor(player, record, cat)
    local picker = Offers.picker(player, record, cat)
    return picker
end

function Offers.relieve(uid, cat)
    local plan = Offers.RELIEF[cat]
    if plan == nil then return true end
    return Instance.write(uid, function(memory)
        local person = memory.person
        if type(person) ~= "table" then return end
        for _, row in ipairs(plan) do Instance.setNeed(person, row[1], Instance.need(person, row[1]) + row[2]) end
    end)
end

function Offers.delta(record, cat, itemType, player)
    local person = Instance.of(record)
    if person == nil then return nil end
    if cat == "food" then
        return React.baseDelta("gave_food", React.events.gave_food, person, ProjectALife.VisitorPeople.card(person.id), nil)
    end
    if cat == "clothes" then
        local wants, why = Wardrobe.wants(record, player, itemType)
        if wants and why == "need" then return 7 end
        return 3
    end
    return nil
end

function Offers.refuse(player, record, why)
    Offers.metrics.refused = Offers.metrics.refused + 1
    local shell = Talk.shellOf(record.uid)
    local env = Talk.env(player, record, nil, shell, nil)
    if env.key ~= nil then Talk.speakKey(env, "react.gift_refused", "VP_REACT_GIFT_REFUSED") end
    return Offers.fail("offer_refused")
end

function Offers.validGift(gift)
    return type(gift) == "table" and type(gift.token) == "string" and #gift.token <= 256 and type(gift.itemId) == "number"
        and gift.itemId == gift.itemId and gift.itemId % 1 == 0
end

function Offers.transfer(player, record, selected, source, destination, shell)
    local robbery, state = ProjectALife.ModuleRobbery, ProjectALife.ShellState
    if robbery == nil or type(robbery.removeItem) ~= "function" then return false, "inventory_api_unavailable" end
    if state == nil or type(state.markScavenged) ~= "function" or type(selected.getModData) ~= "function" then
        return false, "item_persistence_unavailable"
    end
    local dataOk, data = pcall(selected.getModData, selected)
    if not dataOk or type(data) ~= "table" then return false, "item_persistence_unavailable" end
    local previous = data.ProjectALifeScavenged
    local markedOk, marked = pcall(state.markScavenged, selected)
    if not markedOk or marked ~= true then return false, "item_persistence_unavailable" end
    local moved, reason = robbery.removeItem({ item = selected, container = source, source = "player" }, destination, shell)
    if not moved then
        data.ProjectALifeScavenged = previous
        return false, reason or "transfer_refused"
    end
    return true
end

function Offers.give(player, record, cat, args)
    local gift = type(args) == "table" and args.gift or nil
    if not Offers.validGift(gift) then return Offers.fail("gift_selection_required") end
    if type(record) ~= "table" or Instance.of(record) == nil then return Offers.fail("not_visitor") end
    local key, now = Offers.keyOf(record.uid, player), Offers.nowMs()
    local saved = Offers.gifts[key]
    if saved == nil or saved.token ~= gift.token or now >= saved.untilMs or saved.uid ~= record.uid
            or saved.generation ~= record.generation or saved.cat ~= cat then
        Offers.metrics.stale = Offers.metrics.stale + 1
        return Offers.fail("gift_selection_required")
    end
    local original = nil
    for _, entry in ipairs(saved.entries) do
        if entry.id == gift.itemId then original = entry break end
    end
    if original == nil then return Offers.fail("gift_item_changed") end
    local selected, source = nil, nil
    for _, entry in ipairs(Offers.entries(player, cat)) do
        if entry.item == original.item and entry.container == original.container and entry.id == gift.itemId then
            selected, source = entry.item, entry.container
            break
        end
    end
    if selected == nil then return Offers.fail("gift_item_changed") end
    local shell = Talk.shellOf(record.uid)
    local inventory = shell ~= nil and type(shell.getInventory) == "function" and shell:getInventory() or nil
    if inventory == nil then return Offers.fail("inventory_unavailable") end
    local itemType = Offers.call(selected, "getFullType")
    local delta = Offers.delta(record, cat, itemType, player)
    if cat == "clothes" then
        local wants = Wardrobe.wants(record, player, itemType)
        if not wants then return Offers.refuse(player, record, "pride") end
    end
    local moved, reason = Offers.transfer(player, record, selected, source, inventory, shell)
    if not moved then return Offers.fail(reason) end
    Offers.gifts[key] = nil
    Offers.metrics.gives = Offers.metrics.gives + 1
    Offers.relieve(record.uid, cat)
    local info = { cat = cat, fullType = itemType, name = original.name, delta = delta }
    if cat == "clothes" then
        local worn, replaced, how = Wardrobe.wear(record.uid, selected)
        info.worn = worn and (how or "now") or "refused"
        info.replaced = {}
        for _, entry in ipairs(replaced or {}) do info.replaced[#info.replaced + 1] = entry.itemType end
        if worn and how == nil then Offers.metrics.worn = Offers.metrics.worn + 1 end
    end
    Offers.metrics.lastWhy = "-"
    return true, info
end

function Offers.install()
    if Talk.adapters.give == nil then Talk.adapters.give = Offers.give end
    if Talk.adapters.picker == nil then Talk.adapters.picker = Offers.pickerFor end
    return true
end
Offers.install()

function Offers.reset()
    Offers.gifts, Offers.seq = {}, 0
    for key, value in pairs(Offers.metrics) do Offers.metrics[key] = type(value) == "number" and 0 or "-" end
end

function Offers.qaLine()
    local m = Offers.metrics
    return "[ALIFE-QA] VisitorOffers pickers=" .. tostring(m.pickers) .. " empty=" .. tostring(m.empty)
        .. " gives=" .. tostring(m.gives) .. " refused=" .. tostring(m.refused) .. " stale=" .. tostring(m.stale)
        .. " worn=" .. tostring(m.worn) .. " why=" .. tostring(m.lastWhy)
end

return Offers
