require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/World/ALifeSeasons"
require "ProjectALife/Records/ALifeSeasonalOutfitGenerator"
require "ProjectALife/World/ALifeVisitOutfits"
require "ProjectALife/Records/ALifeSeasonalWardrobe"
require "ProjectALife/Combat/ALifeWeapons"
require "ProjectALife/Shells/ALifeShellState"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Audio/ALifeVoiceAssignment"

require "ProjectALife/Records/ALifeDropPolicy"
require "ProjectALife/Records/ALifeLoadoutProgression"
require "ProjectALife/Records/ALifeLootRarity"
require "ProjectALife/Shells/ALifeDeathInventory"
require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Shells/ALifeAppearance"
require "ProjectALife/Shells/ALifeOutfitCollisions"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.Catalog
local Weapons = ProjectALife.Weapons
local Magazines = ProjectALife.MagazineState
local ShellState = ProjectALife.ShellState
local Animations = ProjectALife.Animations
local BehaviorSettings = ProjectALife.BehaviorSettings
local Hydrator = { adapters = {}, dressed = setmetatable({}, { __mode = "k" }) }
ProjectALife.ProfileHydrator = Hydrator
local setMetadata

local function trim(value)
    return string.match(tostring(value or ""), "^%s*(.-)%s*$")
end

local function stableIndex(seed, maximum)
    local value = 17
    for index = 1, #seed do value = (value * 131 + string.byte(seed, index)) % 2147483647 end
    return (value % maximum) + 1
end

local function identitySeed(actor)
    return actor.memory and actor.memory.identitySeed or actor.uid
end

function Hydrator.stableTint(seed)
    local hue = (stableIndex(tostring(seed), 360) - 1) % 360
    local s, v = 0.45, 0.72
    local c = v * s
    local x = c * (1 - math.abs((hue / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if hue < 60 then r, g, b = c, x, 0 elseif hue < 120 then r, g, b = x, c, 0
    elseif hue < 180 then r, g, b = 0, c, x elseif hue < 240 then r, g, b = 0, x, c
    elseif hue < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
    return r + m, g + m, b + m
end

local function humanSkinIndex(value)
    return math.max(0, math.min(4, math.floor(tonumber(value) or 0)))
end

local function humanSkinTexture(female, skin)
    return (female and "FemaleBody0" or "MaleBody0")
        .. tostring(humanSkinIndex(skin) + 1)
end
Hydrator.humanSkinTexture = humanSkinTexture

local function authoredColor(value)
    local r, g, b = string.match(tostring(value or ""),
        "^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
    if not r then return nil end
    return math.max(0, math.min(1, tonumber(r) or 0)),
        math.max(0, math.min(1, tonumber(g) or 0)),
        math.max(0, math.min(1, tonumber(b) or 0))
end

function Hydrator.prepareClothing(item, entry, seed)
    if item == nil or type(item.getVisual) ~= "function" then return nil end
    local visual = item:getVisual()
    if visual == nil then return nil end
    local key = tostring(seed or "") .. "|" .. tostring(entry.itemType)
    local r, g, b = authoredColor(entry.tint)
    if r ~= nil and type(item.setColorRed) == "function" and type(item.setColorGreen) == "function"
            and type(item.setColorBlue) == "function" and type(item.setCustomColor) == "function" then
        item:setColorRed(r); item:setColorGreen(g); item:setColorBlue(b)
        item:setCustomColor(true)
    end
    if not r then r, g, b = Hydrator.stableTint(key) end
    if ImmutableColor ~= nil and type(ImmutableColor.new) == "function" and type(visual.setTint) == "function" then
        visual:setTint(ImmutableColor.new(r, g, b, 1))
    end
    if type(visual.setHue) == "function" then visual:setHue(0) end
    local clothing = type(item.getClothingItem) == "function" and item:getClothingItem() or nil
    if clothing ~= nil and (type(clothing.isReady) ~= "function" or clothing:isReady())
            and type(clothing.getBaseTextures) == "function" and type(clothing.getTextureChoices) == "function" then
        local bases, choices = clothing:getBaseTextures(), clothing:getTextureChoices()
        if bases ~= nil and type(bases.size) == "function" and bases:size() > 0
                and type(visual.setBaseTexture) == "function" then
            visual:setBaseTexture(stableIndex(key .. "|base", bases:size()) - 1)
        end
        if choices ~= nil and type(choices.size) == "function" and choices:size() > 0
                and type(visual.setTextureChoice) == "function" then
            visual:setTextureChoice(stableIndex(key .. "|texture", choices:size()) - 1)
        end
    end
    return visual
end

local function applyAuthoredColor(visual, encoded, beard)
    local r, g, b = authoredColor(encoded)
    if not r or ImmutableColor == nil then return end
    local color = ImmutableColor.new(r, g, b, 1)
    if beard then
        visual:setBeardColor(color)
        visual:setNaturalBeardColor(color)
    else
        visual:setHairColor(color)
        visual:setNaturalHairColor(color)
    end
end

function Hydrator.isBodyLocation(where)
    local kind = type(where)
    if kind == "string" then return where ~= "" end
    return kind == "userdata" or kind == "table"
end

function Hydrator.wornLocation(item)
    if item == nil then return nil end
    local location = nil
    if item.getBodyLocation ~= nil then
        local ok, where = pcall(item.getBodyLocation, item)
        if ok and Hydrator.isBodyLocation(where) then location = where end
    end
    if location == nil and item.canBeEquipped ~= nil then
        local ok, where = pcall(item.canBeEquipped, item)
        if ok and Hydrator.isBodyLocation(where) then location = where end
    end
    return location
end

function Hydrator.bodyLocationOf(item)
    return Hydrator.wornLocation(item)
end

Hydrator.renderRanks, Hydrator.renderRankCount, Hydrator.renderRankCap = {}, 0, 512

function Hydrator.locationGroup()
    if BodyLocations == nil or type(BodyLocations.getGroup) ~= "function" then return nil end
    local ok, group = pcall(BodyLocations.getGroup, "Human")
    if not ok or group == nil or type(group.indexOf) ~= "function" then return nil end
    return group
end

function Hydrator.scriptLocation(fullType)
    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    if manager ~= nil and type(manager.FindItem) == "function" then
        local ok, script = pcall(manager.FindItem, manager, fullType)
        if ok and script ~= nil and type(script.getBodyLocation) == "function" then
            local located, where = pcall(script.getBodyLocation, script)
            if located and Hydrator.isBodyLocation(where) then return where end
        end
    end
    if type(instanceItem) ~= "function" then return nil end
    local ok, item = pcall(instanceItem, fullType)
    if not ok then return nil end
    return Hydrator.wornLocation(item)
end

function Hydrator.renderRank(group, fullType)
    local key = tostring(fullType or "")
    local rank = Hydrator.renderRanks[key]
    if rank ~= nil then return rank end
    rank = -1
    local location = Hydrator.scriptLocation(key)
    if location ~= nil then
        local ok, index = pcall(group.indexOf, group, location)
        if ok and tonumber(index) ~= nil then rank = tonumber(index) end
    end
    if Hydrator.renderRankCount >= Hydrator.renderRankCap then
        Hydrator.renderRanks, Hydrator.renderRankCount = {}, 0
    end
    Hydrator.renderRanks[key] = rank
    Hydrator.renderRankCount = Hydrator.renderRankCount + 1
    return rank
end

function Hydrator.byRenderRank(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.position < b.position
end

function Hydrator.renderOrder(entries)
    if type(entries) ~= "table" or #entries < 2 then return entries end
    local group = Hydrator.locationGroup()
    if group == nil then return entries end
    local rows = {}
    for position, entry in ipairs(entries) do
        rows[position] = { entry = entry, position = position,
            rank = Hydrator.renderRank(group, entry.itemType) }
    end
    table.sort(rows, Hydrator.byRenderRank)
    for position, row in ipairs(rows) do entries[position] = row.entry end
    return entries
end

function Hydrator.wearsGarments()
    return type(isClient) == "function" and isClient() == true
end

Hydrator.metrics = Hydrator.metrics or {}
Hydrator.bandageShown = setmetatable({}, { __mode = "k" })

function Hydrator.showBandages(shell, types)
    types = type(types) == "table" and types or {}
    local key = table.concat(types, "|")
    local state = Hydrator.bandageShown[shell]
    if (state == nil and key == "") or (state ~= nil and state.key == key) then return false end
    if type(instanceItem) ~= "function" or shell == nil then return false end
    local ok = pcall(function()
        local list, visuals = shell:getWornItems(), shell:getItemVisuals()
        if state ~= nil then
            for _, old in ipairs(state.items) do
                if list ~= nil and type(list.remove) == "function" then list:remove(old) end
                local oldVisual = old:getVisual()
                if visuals ~= nil and oldVisual ~= nil then visuals:remove(oldVisual) end
            end
        end
        local items = {}
        for _, itemType in ipairs(types) do
            local item = instanceItem(itemType)
            local visual = item ~= nil and item:getVisual() or nil
            if visual ~= nil then
                if visuals ~= nil then visuals:add(visual) end
                if Hydrator.wear(shell, item) then items[#items + 1] = item end
            end
        end
        Hydrator.bandageShown[shell] = { key = key, items = items }
        shell:resetModelNextFrame()
    end)
    return ok
end

function Hydrator.wear(shell, item, verifiedList)
    local location = Hydrator.wornLocation(item)
    if location == nil or shell == nil then return false end

    local worn = pcall(function()
        local list = verifiedList or shell:getWornItems()
        if list == nil then error("no_worn_items") end
        if verifiedList ~= nil and (type(list.setItem) ~= "function" or type(shell.onWornItemsChanged) ~= "function") then error("no_worn_methods") end
        list:setItem(location, item)
        shell:onWornItemsChanged()
    end)
    if worn then
        Hydrator.metrics.worn = (Hydrator.metrics.worn or 0) + 1
    else
        Hydrator.metrics.wearFailed = (Hydrator.metrics.wearFailed or 0) + 1
    end
    return worn
end

function Hydrator.medicalKitFor(conduct, profession, roll)
    if conduct == "medic" then
        return { { itemType = "Base.Bandage", count = 4 }, { itemType = "Base.AlcoholWipes", count = 2 } }
    end
    local job = string.lower(tostring(profession or ""))
    if string.find(job, "scaveng", 1, true) or string.find(job, "looter", 1, true) then
        return { { itemType = "Base.RippedSheets", count = 2 } }
    end
    local r = math.max(0, math.min(0.999, tonumber(roll) or 0.5))
    return { { itemType = "Base.Bandage", count = 1 + math.floor(r * 2) } }
end

function Hydrator.initializeIdentityDescriptor(shell, plan, card)
    if shell == nil or type(plan) ~= "table" or card == nil
            or type(instanceof) ~= "function" or not instanceof(shell, "IsoZombie")
            or type(shell.getModData) ~= "function" or type(shell.getDescriptor) ~= "function"
            or type(shell.isDead) ~= "function"
            or type(card.getModData) ~= "function" or type(card.getFullType) ~= "function"
            or type(card.getDisplayName) ~= "function" or type(card.getScriptItem) ~= "function"
            or type(getText) ~= "function" then return false end
    if shell:isDead() == true then return false end
    if type(shell.isReanimatedForGrappleOnly) == "function"
            and shell:isReanimatedForGrappleOnly() == true then return false end
    local data, cardData = shell:getModData(), card:getModData()
    if type(data) ~= "table" or data.ProjectALifeOwned ~= true
            or data.ProjectALifeUID ~= plan.actorUid or data.ProjectALifeCorpseOf ~= nil
            or type(cardData) ~= "table"
            or cardData.ProjectALifeIdentityCard ~= true
            or cardData.ProjectALifeActorUID ~= plan.actorUid then return false end
    local kind = card:getFullType()
    if kind ~= "Base.IDcard_Male" and kind ~= "Base.IDcard_Female" then return false end
    local descriptor = shell:getDescriptor()
    if descriptor == nil or type(descriptor.getForename) ~= "function"
            or type(descriptor.getSurname) ~= "function"
            or type(descriptor.setForename) ~= "function"
            or type(descriptor.setSurname) ~= "function" then return false end
    local first, last = descriptor:getForename(), descriptor:getSurname()
    if first ~= nil and first ~= "" and first ~= "None" then return false end
    if last ~= nil and last ~= "" and last ~= "None" then return false end
    local script = card:getScriptItem()
    if script == nil or type(script.getDisplayName) ~= "function" then return false end
    local label, name = script:getDisplayName(), card:getDisplayName()
    if type(label) ~= "string" or label == "" or type(name) ~= "string" then return false end
    local token = "__ALifeIdentityName__"
    local formatted = getText("IGUI_ItemWithDisplayName", label, token)
    if type(formatted) ~= "string" then return false end
    local start, finish = string.find(formatted, token, 1, true)
    if start == nil or string.find(formatted, token, finish + 1, true) then return false end
    local prefix, suffix = string.sub(formatted, 1, start - 1), string.sub(formatted, finish + 1)
    if string.sub(name, 1, #prefix) ~= prefix
            or (#suffix > 0 and string.sub(name, -#suffix) ~= suffix) then return false end
    first, last = string.match(string.sub(name, #prefix + 1, #name - #suffix), "^%s*(%S.-)%s+(%S+)%s*$")
    if first == nil or last == nil or first == "None" or last == "None" then return false end
    descriptor:setForename(first)
    descriptor:setSurname(last)
    return true
end

function Hydrator.personNameFor(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or type(memory.personFirst) ~= "string" or memory.personFirst == "" then return nil end
    local last = type(memory.personLast) == "string" and memory.personLast or ""
    if last == "" then return memory.personFirst end
    return memory.personFirst .. " " .. last
end

function Hydrator.nameIdentityCard(card, plan)
    if card == nil or type(plan) ~= "table" or type(plan.personName) ~= "string" or plan.personName == ""
            or type(getText) ~= "function" or type(card.getScriptItem) ~= "function"
            or type(card.setName) ~= "function" or type(card.getName) ~= "function" then return false end
    local script = card:getScriptItem()
    if script == nil or type(script.getDisplayName) ~= "function" then return false end
    local text = getText("IGUI_ItemWithDisplayName", script:getDisplayName(), plan.personName)
    if type(text) ~= "string" or text == "" or card:getName() == text then return false end
    card:setName(text)
    if type(card.setCustomName) == "function" then card:setCustomName(true) end
    return true
end

function Hydrator.ensureIdentityCard(shell, plan)
    if shell == nil or type(plan) ~= "table" or type(plan.actorUid) ~= "string" then
        return false, "identity_specification_invalid"
    end
    local inventoryOk, inventory = pcall(function() return shell:getInventory() end)
    local itemsOk, items = pcall(function() return inventory and inventory:getItems() end)
    if not inventoryOk or not itemsOk or items == nil then
        return false, "identity_inventory_unavailable"
    end

    local keep, extras = nil, {}
    local countOk, count = pcall(function() return items:size() end)
    if not countOk then return false, "identity_inventory_unavailable" end
    for index = 0, count - 1 do
        local item = items:get(index)
        local dataOk, data = pcall(function() return item:getModData() end)
        local typeOk, fullType = pcall(function() return item:getFullType() end)
        local card = typeOk and string.find(tostring(fullType or ""), "Base.IDcard_", 1, true) == 1
        if dataOk and type(data) == "table"
                and data.ProjectALifeIdentityCard == true then
            if keep == nil and data.ProjectALifeActorUID == plan.actorUid then
                keep = item
            else
                extras[#extras + 1] = item
            end
        elseif card then

            if keep == nil then keep = item else extras[#extras + 1] = item end
        end
    end
    for _, item in ipairs(extras) do
        pcall(function() inventory:Remove(item) end)
    end

    if keep == nil then
        local cardType = plan.female and "Base.IDcard_Female" or "Base.IDcard_Male"
        local addedOk, item = pcall(function() return inventory:AddItem(cardType) end)
        if not addedOk or item == nil then return false, "identity_create_failed" end
        keep = item
    end
    local marked, itemData = pcall(function() return keep:getModData() end)
    if not marked or type(itemData) ~= "table" then return false, "identity_mark_failed" end
    itemData.ProjectALifeIdentityCard = true
    itemData.ProjectALifeActorUID = plan.actorUid
    Hydrator.nameIdentityCard(keep, plan)
    local nameOk, identityName = pcall(function() return keep:getName() end)
    if nameOk and identityName ~= nil then
        setMetadata(shell, "ALifeIdentityName", identityName)
    end
    pcall(Hydrator.initializeIdentityDescriptor, shell, plan, keep)
    return true, keep
end

local POCKET_LOOT = {
    "Base.Comb", "Base.Toothbrush", "Base.Tissue", "Base.Lighter", "Base.Matches",
    "Base.Notepad", "Base.Pen", "Base.Pencil", "Base.CreditCard", "Base.Money",
    "Base.Lipstick", "Base.Perfume", "Base.Cologne", "Base.Photo", "Base.Postcard",
    "Base.Newspaper", "Base.Magazine", "Base.Dice", "Base.Razor", "Base.Cork",
    "Base.Candle", "Base.Bandage", "Base.Pills", "Base.Battery", "Base.Twine",
    "Base.MuldraughMap", "Base.WalkieTalkie2", "Base.Mirror", "Base.Doll", "Base.Yoyo",
    "Base.Note", "Base.GraphPaper", "Base.Paperwork", "Base.Paperclip", "Base.CordlessPhone",
}

local POCKET_FOOD = { "Base.Chocolate", "Base.Crisps", "Base.TinnedBeans", "Base.WaterBottle" }

local BAG_LOOT = {
    "Base.RippedSheets", "Base.Rope", "Base.Candle", "Base.Newspaper", "Base.Magazine",
    "Base.WaterBottle", "Base.TinOpener", "Base.Bandage", "Base.Twine", "Base.NailsBox",
    "Base.Whiskey", "Base.Photo", "Base.Notepad", "Base.Matches", "Base.Tissue",
}
Hydrator.pocketLoot, Hydrator.pocketFood, Hydrator.bagLoot = POCKET_LOOT, POCKET_FOOD, BAG_LOOT
Hydrator.traderBag = "Base.Bag_Schoolbag"

function Hydrator.traderMethods(object, names)
    if object == nil or (type(object) ~= "table" and type(object) ~= "userdata") then return false end
    for _, name in ipairs(names) do if type(object[name]) ~= "function" then return false end end
    return true
end

function Hydrator.traderItems(container)
    if not Hydrator.traderMethods(container, { "getItems" }) then return nil end
    local got, items = pcall(container.getItems, container)
    if not got or not Hydrator.traderMethods(items, { "size", "get" }) then return nil end
    local read, count = pcall(items.size, items)
    if not read or type(count) ~= "number" or count ~= count or count < 0 or count > 256 or count % 1 ~= 0 then return nil end
    return items, count
end

function Hydrator.traderType(fullType)
    if fullType == "Base.WaterBottle" or fullType == "Base.Whiskey" then return false end
    for _, kind in ipairs(BAG_LOOT) do if kind == fullType then return true end end
    return false
end

function Hydrator.validTraderStock(stock, issuing)
    if type(stock) ~= "table" or stock.version ~= 1 or type(stock.uid) ~= "string"
            or type(stock.visitId) ~= "string" or #stock.visitId > 256 or stock.bag ~= Hydrator.traderBag
            or type(stock.revision) ~= "number" or stock.revision ~= stock.revision or stock.revision < 1
            or stock.revision % 1 ~= 0 or stock.revision >= 9007199254740992
            or (stock.phase ~= "ready" and not (issuing == true and stock.phase == "issuing"))
            or type(stock.slots) ~= "table" or #stock.slots < 3 or #stock.slots > 6 then return false end
    for index in pairs(stock.slots) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #stock.slots then return false end
    end
    for index, slot in ipairs(stock.slots) do
        if type(slot) ~= "table" or slot.id ~= index or not Hydrator.traderType(slot.type)
                or not ({ available = true, reserved = true, sold = true, uncertain = true })[slot.state] then return false end
    end
    return true
end

function Hydrator.traderSnapshot(actor)
    local stock = actor and actor.memory and actor.memory.traderStock
    if not Hydrator.validTraderStock(stock) or stock.uid ~= actor.uid then return nil end
    local value = { version = 1, uid = stock.uid, visitId = stock.visitId, bag = stock.bag,
        revision = stock.revision, phase = stock.phase, slots = {} }
    for index, slot in ipairs(stock.slots) do
        value.slots[index] = { id = slot.id, type = slot.type, state = slot.state }
    end
    return value
end

function Hydrator.writeTraderStock(actor, stock)
    if type(isClient) == "function" and isClient() then return false end
    if type(actor) ~= "table" or type(stock) ~= "table" or stock.uid ~= actor.uid
            or (stock.phase ~= "ready" and stock.phase ~= "issuing" and stock.phase ~= "failed") then return false end
    local checked = { version = stock.version, uid = stock.uid, visitId = stock.visitId, bag = stock.bag,
        revision = stock.revision, phase = stock.phase == "failed" and "ready" or stock.phase, slots = stock.slots }
    if not Hydrator.validTraderStock(checked, true) then return false end
    for _, slot in ipairs(stock.slots) do
        if slot.token ~= nil and (type(slot.token) ~= "string" or slot.token == "" or #slot.token > 256) then return false end
    end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" or type(registry.update) ~= "function" then return false end
    local current = registry.read(actor.uid)
    if current == nil or current.generation ~= actor.generation then return false end
    local updated = registry.update(current.uid, current.revision, function(record)
        local detached = { version = stock.version, uid = stock.uid, visitId = stock.visitId, bag = stock.bag,
            revision = stock.revision, phase = stock.phase, slots = {} }
        for index, slot in ipairs(stock.slots) do
            detached.slots[index] = { id = slot.id, type = slot.type, state = slot.state, token = slot.token }
        end
        record.memory.traderStock = detached
    end)
    return updated ~= nil and updated ~= false
end

function Hydrator.traderBodyAllowed(shell, actor)
    if type(actor) ~= "table" or type(instanceof) ~= "function"
            or not Hydrator.traderMethods(shell, { "getModData" }) then return false end
    local shaped, npc = pcall(instanceof, shell, "IsoZombie")
    if not shaped or npc ~= true then return false end
    local read, data = pcall(function() return shell:getModData() end)
    if not read or type(data) ~= "table" or data.ProjectALifeUID ~= actor.uid
            or data.ProjectALifeGeneration ~= actor.generation then return false end
    if type(isClient) == "function" and isClient() then
        local sim = ProjectALife.ShellSimulation
        if sim == nil or type(sim.isOwner) ~= "function" then return false end
        local checked, owner = pcall(sim.isOwner, shell)
        if not checked or owner ~= true then return false end
    end
    return true
end

function Hydrator.restoreTraderStock(shell, actor, stock, issuing)
    if not Hydrator.validTraderStock(stock, issuing) or stock.uid ~= actor.uid then return false, "trader_stock_invalid" end
    if not Hydrator.traderBodyAllowed(shell, actor) then return false, "trader_body_stale" end
    if shell == nil or type(shell.getModData) ~= "function" or type(shell.getInventory) ~= "function" then
        return false, "trader_inventory_unavailable"
    end
    local dataOk, data = pcall(shell.getModData, shell)
    if not dataOk or type(data) ~= "table" or data.ProjectALifeUID ~= actor.uid
            or data.ProjectALifeGeneration ~= actor.generation then return false, "trader_body_stale" end
    if tonumber(data.ProjectALifeTraderRevision) and data.ProjectALifeTraderRevision > stock.revision then
        return false, "trader_stock_stale"
    end
    local read, inventory = pcall(shell.getInventory, shell)
    if not read or inventory == nil or type(inventory.getItems) ~= "function" or type(inventory.AddItem) ~= "function"
            or type(inventory.Remove) ~= "function" then return false, "trader_inventory_unavailable" end
    local listed, items = pcall(inventory.getItems, inventory)
    if not listed or items == nil or type(items.size) ~= "function" or type(items.get) ~= "function" then
        return false, "trader_inventory_unavailable"
    end
    local bag, count = nil, items:size()
    if count > 256 then return false, "trader_inventory_limit" end
    for index = 0, count - 1 do
        local item = items:get(index)
        if not Hydrator.traderMethods(item, { "getModData", "getFullType" }) then return false, "trader_inventory_unavailable" end
        local marked, metadata = pcall(item.getModData, item)
        if marked and type(metadata) == "table" and metadata.ProjectALifeTraderBag == actor.uid then
            if bag ~= nil or item:getFullType() ~= stock.bag then return false, "trader_bag_ambiguous" end
            bag = item
        elseif type(item.getFullType) == "function" and item:getFullType() == stock.bag then
            return false, "trader_bag_ambiguous"
        end
    end
    local created, newBag = {}, false
    if bag == nil then
        if data.ProjectALifeTraderRevision ~= nil then return false, "trader_bag_missing" end
        local added, value = pcall(inventory.AddItem, inventory, stock.bag)
        if not added or value == nil then return false, "trader_bag_unavailable" end
        bag, newBag = value, true
        local stamped = Hydrator.traderMethods(bag, { "getModData", "getFullType", "getContainer", "getInventory" })
            and pcall(function()
                if bag:getFullType() ~= stock.bag or bag:getContainer() ~= inventory then error("unsafe_bag") end
                bag:getModData().ProjectALifeTraderBag = actor.uid
            end)
        if not stamped then pcall(inventory.Remove, inventory, bag); return false, "trader_bag_unavailable" end
    end
    if not Hydrator.traderMethods(bag, { "getInventory" }) then return false, "trader_bag_unavailable" end
    local got, container = pcall(bag.getInventory, bag)
    if not got or container == nil or type(container.getItems) ~= "function" or type(container.AddItem) ~= "function"
            or type(container.Remove) ~= "function" then
        if newBag then pcall(inventory.Remove, inventory, bag) end
        return false, "trader_bag_unavailable"
    end
    local packed, size = Hydrator.traderItems(container)
    local found, remove = {}, {}
    if packed == nil then return false, "trader_inventory_unavailable" end
    for index = 0, size - 1 do
        local item = packed:get(index)
        if not Hydrator.traderMethods(item, { "getModData", "getFullType" }) then return false, "trader_inventory_unavailable" end
        local marked, metadata = pcall(item.getModData, item)
        if marked and type(metadata) == "table" and metadata.ProjectALifeTraderUID == actor.uid then
            local slot = stock.slots[metadata.ProjectALifeTraderSlot]
            if slot == nil then return false, "trader_stock_ambiguous"
            elseif slot.state ~= "available" then
                if type(isClient) == "function" and isClient() then remove[#remove + 1] = item
                elseif slot.state == "sold" then return false, "trader_sold_item_present" end
            elseif found[slot.id] ~= nil or item:getFullType() ~= slot.type then return false, "trader_stock_ambiguous"
            else found[slot.id] = item end
        end
    end
    for _, slot in ipairs(stock.slots) do
        if slot.state == "available" and found[slot.id] == nil then
            local previous = data.ProjectALifeTraderStates
            if data.ProjectALifeTraderRevision ~= nil and (type(previous) ~= "table" or previous[slot.id] == "available") then
                return false, "trader_stock_missing"
            end
            local added, value = pcall(container.AddItem, container, slot.type)
            if not added or value == nil then
                for _, item in ipairs(created) do pcall(container.Remove, container, item) end
                if newBag then pcall(inventory.Remove, inventory, bag) end
                return false, "trader_stock_issue_failed"
            end
            created[#created + 1] = value
            local valid = Hydrator.traderMethods(value, { "IsWeapon", "getFullType", "getContainer", "getCategory", "getModData" })
                and pcall(function()
                if type(value.IsWeapon) ~= "function" or value:IsWeapon() ~= false or value:getFullType() ~= slot.type
                        or value:getContainer() ~= container then error("unsafe_stock") end
                if value:getCategory() == "Food" then
                    local supplies = ProjectALife.TalkSupplies
                    if supplies == nil or type(supplies.matches) ~= "function" or supplies.matches(value, "ASK_FOOD") ~= true then
                        error("unsafe_stock")
                    end
                end
                local metadata = value:getModData()
                metadata.ProjectALifeTraderUID, metadata.ProjectALifeTraderSlot = actor.uid, slot.id
            end)
            if not valid then
                for _, item in ipairs(created) do pcall(container.Remove, container, item) end
                if newBag then pcall(inventory.Remove, inventory, bag) end
                return false, "trader_stock_issue_failed"
            end
        end
    end
    local wornOk, worn = false, nil
    if Hydrator.traderMethods(shell, { "getWornItems", "onWornItemsChanged" }) then wornOk, worn = pcall(shell.getWornItems, shell) end
    if not wornOk or not Hydrator.traderMethods(worn, { "setItem" })
            or not Hydrator.traderMethods(bag, { "canBeEquipped" })
            or (bag.getBodyLocation ~= nil and type(bag.getBodyLocation) ~= "function")
            or not Hydrator.wear(shell, bag, worn) then
        for _, item in ipairs(created) do pcall(container.Remove, container, item) end
        if newBag then pcall(inventory.Remove, inventory, bag) end
        return false, "trader_bag_wear_failed"
    end
    for _, item in ipairs(remove) do pcall(container.Remove, container, item) end
    data.ProjectALifeTraderRevision, data.ProjectALifeTraderStates = stock.revision, {}
    for _, slot in ipairs(stock.slots) do data.ProjectALifeTraderStates[slot.id] = slot.state end
    return true, #stock.slots
end

function Hydrator.ensureTraderStock(shell, actor)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" then return false, "trader_actor_invalid" end
    local stock = memory.traderStock
    if stock ~= nil then return Hydrator.restoreTraderStock(shell, actor, stock) end
    local visit = memory.visit
    if type(visit) ~= "table" or visit.event ~= "trader" then return true, 0 end
    if type(isClient) == "function" and isClient() then return false, "trader_stock_not_ready" end
    if memory.natural ~= true or memory.debugSpawn == true or actor.lifecycle ~= "active"
            or visit.generation ~= actor.generation or type(visit.pendingId) ~= "string" then
        return false, "trader_visit_stale"
    end
    if not Hydrator.traderBodyAllowed(shell, actor) then return false, "trader_body_stale" end
    local pool = {}
    for _, kind in ipairs(BAG_LOOT) do if Hydrator.traderType(kind) and Hydrator.itemKnown(kind) then pool[#pool + 1] = kind end end
    if #pool < 6 or not Hydrator.itemKnown(Hydrator.traderBag) then return false, "trader_stock_types_unavailable" end
    stock = { version = 1, uid = actor.uid, visitId = visit.pendingId, bag = Hydrator.traderBag,
        revision = 1, phase = "issuing", slots = {} }
    local count, first = 3 + stableIndex(actor.uid .. ":trader:count", 4) - 1, stableIndex(actor.uid .. ":trader:first", #pool)
    for index = 1, count do stock.slots[index] = { id = index, type = pool[1 + ((first + index) % #pool)], state = "available" } end
    if not Hydrator.writeTraderStock(actor, stock) then return false, "trader_stock_write_failed" end
    local restored, reason = Hydrator.restoreTraderStock(shell, actor, stock, true)
    stock.phase = restored and "ready" or "failed"
    if not Hydrator.writeTraderStock(actor, stock) then return false, "trader_stock_write_failed" end
    return restored, reason
end

function Hydrator.reserveTraderStock(shell, actor, item, token)
    if type(isClient) == "function" and isClient() then return false, "client_authority" end
    if not Hydrator.traderBodyAllowed(shell, actor) then return false, "trader_body_stale" end
    if type(token) ~= "string" or token == "" or #token > 256 then return false, "trader_token_invalid" end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" then return false, "trader_stock_unavailable" end
    local current = registry and registry.read(actor.uid)
    local stock = Hydrator.traderSnapshot(current)
    if current == nil or current.generation ~= actor.generation or stock == nil then return false, "trader_stock_invalid" end
    local bound, data = pcall(function() return shell:getModData() end)
    if not bound or data.ProjectALifeUID ~= actor.uid or data.ProjectALifeGeneration ~= actor.generation then
        return false, "trader_body_stale"
    end
    if not Hydrator.traderMethods(item, { "getModData", "getFullType", "getContainer" }) then return false, "trader_item_invalid" end
    local got, metadata = pcall(item.getModData, item)
    local slot = got and type(metadata) == "table" and stock.slots[metadata.ProjectALifeTraderSlot] or nil
    if slot == nil or metadata.ProjectALifeTraderUID ~= actor.uid or slot.state ~= "available"
            or item:getFullType() ~= slot.type then return false, "trader_item_invalid" end
    local held = false
    if not Hydrator.traderMethods(shell, { "getInventory" }) then return false, "trader_inventory_unavailable" end
    local scanned, inventory = pcall(shell.getInventory, shell)
    local items, count = Hydrator.traderItems(scanned and inventory or nil)
    if items == nil then return false, "trader_inventory_unavailable" end
    for index = 0, count - 1 do
        local bag = items:get(index)
        if not Hydrator.traderMethods(bag, { "getModData", "getFullType" }) then return false, "trader_inventory_unavailable" end
        local marked, bagData = pcall(bag.getModData, bag)
        if marked and type(bagData) == "table" and bagData.ProjectALifeTraderBag == actor.uid then
            if bag:getFullType() ~= stock.bag or not Hydrator.traderMethods(bag, { "getInventory" }) then return false, "trader_bag_unavailable" end
            local gotBag, packed = pcall(bag.getInventory, bag)
            local contents, size = Hydrator.traderItems(gotBag and packed or nil)
            if contents == nil then return false, "trader_inventory_unavailable" end
            for at = 0, size - 1 do
                if contents:get(at) == item and item:getContainer() == packed then held = true end
            end
        end
    end
    if not held or stock.revision + 1 >= 9007199254740992 then return false, "trader_item_invalid" end
    for _, saved in ipairs(stock.slots) do if saved.state == "reserved" or saved.state == "uncertain" then return false, "trader_stock_pending" end end
    stock.slots[slot.id].state, stock.slots[slot.id].token = "reserved", token
    stock.revision = stock.revision + 1
    if not Hydrator.writeTraderStock(current, stock) then return false, "trader_stock_write_failed" end
    return true, slot.id
end

function Hydrator.completeTraderStock(uid, generation, token, sold)
    if type(isClient) == "function" and isClient() then return false, "client_authority" end
    if type(token) ~= "string" or token == "" or #token > 256 or type(sold) ~= "boolean" then return false, "trader_token_invalid" end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" then return false, "trader_stock_unavailable" end
    local actor = registry and registry.read(uid)
    local saved = actor and actor.memory and actor.memory.traderStock
    if actor == nil or actor.generation ~= generation or not Hydrator.validTraderStock(saved)
            or saved.revision + 1 >= 9007199254740992 then return false, "trader_stock_invalid" end
    local slot
    for _, entry in ipairs(saved.slots) do if entry.state == "reserved" and entry.token == token then slot = entry; break end end
    if slot == nil then return false, "trader_token_stale" end
    slot.state, slot.token = sold == true and "sold" or "available", nil
    saved.revision = saved.revision + 1
    if not Hydrator.writeTraderStock(actor, saved) then return false, "trader_stock_write_failed" end
    return true
end

Hydrator.retiredPocketTypes = { ["Base.Map"] = true }

function Hydrator.isPocketType(fullType)
    local name = tostring(fullType or "")
    if string.find(name, "Base.Wallet_", 1, true) == 1 or string.find(name, "Base.IDcard_", 1, true) == 1 then
        return true
    end
    for _, list in ipairs({ POCKET_LOOT, POCKET_FOOD, BAG_LOOT }) do
        for _, id in ipairs(list) do if id == name then return true end end
    end
    return false
end

function Hydrator.ensurePocketLoot(shell, plan)
    if shell == nil or type(plan) ~= "table" or type(plan.actorUid) ~= "string" then
        return false, "pocket_specification_invalid"
    end
    local inventoryOk, inventory = pcall(function() return shell:getInventory() end)
    local itemsOk, items = pcall(function() return inventory and inventory:getItems() end)
    if not inventoryOk or not itemsOk or items == nil then
        return false, "pocket_inventory_unavailable"
    end
    local keep, stale = {}, {}
    local haveWallet = false
    local countOk, count = pcall(function() return items:size() end)
    if not countOk then return false, "pocket_inventory_unavailable" end
    for index = 0, count - 1 do
        local item = items:get(index)
        local dataOk, data = pcall(function() return item:getModData() end)
        local typeOk, fullType = pcall(function() return item:getFullType() end)
        fullType = typeOk and fullType or ""
        if dataOk and type(data) == "table" and data.ProjectALifePocketLoot == true
                and data.ProjectALifeActorUID ~= plan.actorUid then
            stale[#stale + 1] = item
        elseif Hydrator.retiredPocketTypes[fullType] then
            stale[#stale + 1] = item
        elseif Hydrator.isPocketType(fullType) then

            keep[#keep + 1] = item
            if string.find(fullType, "Base.Wallet_", 1, true) == 1 then haveWallet = true end
        end
    end
    for _, item in ipairs(stale) do pcall(function() inventory:Remove(item) end) end

    local wanted = 5 + (stableIndex(plan.actorUid .. ":pocket:count", 4) - 1)
    local authored = {}
    if not haveWallet then authored[#authored + 1] = plan.female and "Base.Wallet_Female" or "Base.Wallet_Male" end
    local first = stableIndex(plan.actorUid .. ":pocket:first", #POCKET_LOOT)
    local foodRoll = stableIndex(plan.actorUid .. ":pocket:food", 10)
    local slot = 0
    while #authored < wanted do
        slot = slot + 1
        if slot == 2 and foodRoll <= 5 then
            authored[#authored + 1] = POCKET_FOOD[1 + ((first + foodRoll) % #POCKET_FOOD)]
        else
            authored[#authored + 1] = POCKET_LOOT[1 + ((first + slot) % #POCKET_LOOT)]
        end
    end
    local function stamp(item)
        local dataOk, data = pcall(function() return item:getModData() end)
        if dataOk and type(data) == "table" then
            data.ProjectALifePocketLoot = true
            data.ProjectALifeActorUID = plan.actorUid
        end
    end
    for index = #keep + 1, wanted do
        local addedOk, item = pcall(function() return inventory:AddItem(authored[index]) end)
        if addedOk and item ~= nil then
            stamp(item)
            keep[#keep + 1] = item
        end
    end

    pcall(function()
        local scavenging = ProjectALife.Scavenging
        if scavenging == nil or type(scavenging.bagFor) ~= "function" then return end
        local bag = scavenging.bagFor(shell, inventory)
        if bag == nil or bag == inventory then return end
        local packed = bag:getItems()
        for index = 0, math.min(packed:size(), 32) - 1 do
            local typeOk, fullType = pcall(function() return packed:get(index):getFullType() end)
            if typeOk and Hydrator.isPocketType(fullType) then return end
        end
        local extras = 2 + (stableIndex(plan.actorUid .. ":bag:count", 2) - 1)
        local start = stableIndex(plan.actorUid .. ":bag:first", #BAG_LOOT)
        for offset = 1, extras do
            local addedOk, item = pcall(function() return bag:AddItem(BAG_LOOT[1 + ((start + offset) % #BAG_LOOT)]) end)
            if addedOk and item ~= nil then
                stamp(item)
                Hydrator.metrics.bagLoot = (Hydrator.metrics.bagLoot or 0) + 1
            end
        end
    end)
    return true, #keep
end

Hydrator.missingWeaponFallback = {
    primary = "Base.AssaultRifle", secondary = "Base.Pistol",
    keywords = { { "shotgun", "Base.Shotgun" }, { "revolver", "Base.Revolver" }, { "pistol", "Base.Pistol" } },
}
Hydrator.itemSeen, Hydrator.itemSeenCount, Hydrator.itemSeenCap = {}, 0, 4096
Hydrator.missingLogged, Hydrator.missingLoggedCount = {}, 0
Hydrator.metrics.missingItems = Hydrator.metrics.missingItems or 0

function Hydrator.itemKnown(fullType)
    local key = tostring(fullType or "")
    if key == "" then return false end
    local seen = Hydrator.itemSeen[key]
    if seen ~= nil then return seen end
    local share = ProjectALife.FactionShare
    local engine = type(share) == "table" and share.engine or nil
    if type(getScriptManager) ~= "function" or type(engine) ~= "table"
            or type(engine.itemMod) ~= "function" then return true end
    local known = engine.itemMod(key) ~= nil
    if Hydrator.itemSeenCount >= Hydrator.itemSeenCap then
        Hydrator.itemSeen, Hydrator.itemSeenCount = {}, 0
    end
    Hydrator.itemSeen[key] = known
    Hydrator.itemSeenCount = Hydrator.itemSeenCount + 1
    return known
end

function Hydrator.substituteWeapon(missing, slot)
    local fallback = Hydrator.missingWeaponFallback
    if slot ~= "primary" and slot ~= "secondary" then return nil end
    local lowered, pick = string.lower(tostring(missing or "")), nil
    for _, rule in ipairs(fallback.keywords or {}) do
        if string.find(lowered, rule[1], 1, true) then pick = rule[2] break end
    end
    pick = pick or fallback[slot]
    if pick == nil or not Hydrator.itemKnown(pick) then return nil end
    return pick
end

function Hydrator.noteMissing(fullType, where, substitute)
    Hydrator.metrics.missingItems = (Hydrator.metrics.missingItems or 0) + 1
    local key = tostring(fullType)
    if Hydrator.missingLogged[key] or Hydrator.missingLoggedCount >= 256 then return end
    Hydrator.missingLogged[key] = true
    Hydrator.missingLoggedCount = Hydrator.missingLoggedCount + 1
    print("[ALIFE-SPAWN] missing_item type=" .. key .. " at=" .. tostring(where or "?")
        .. " substitute=" .. tostring(substitute or "none"))
end

function Hydrator.usableChoice(choice, weaponSlot, where)
    if string.lower(choice) == "none" or Hydrator.itemKnown(choice) then return choice end
    local substitute = Hydrator.substituteWeapon(choice, weaponSlot)
    Hydrator.noteMissing(choice, where, substitute)
    return substitute
end

function Hydrator.authorsFirearm(profile)
    local weapons = type(profile) == "table" and profile.weapons or nil
    if type(weapons) ~= "table" then return false end
    for _, slot in ipairs({ "primary", "secondary" }) do
        local pool = weapons[slot]
        if type(pool) == "string" then
            for choice in string.gmatch(pool .. "|", "(.-)|") do
                choice = string.lower(trim(choice))
                if choice ~= "" and choice ~= "none" then return true end
            end
        elseif pool ~= nil then
            return true
        end
    end
    return false
end

local function resolveChoice(value, actor, slot, maximum, weaponSlot)
    if type(value) ~= "string" then return value end
    local choices = {}
    for choice in string.gmatch(value .. "|", "(.-)|") do
        choice = trim(choice)
        if choice ~= "" and (maximum == nil or #choices < maximum) then
            choice = Hydrator.usableChoice(choice, weaponSlot, slot)
            if choice ~= nil then choices[#choices + 1] = choice end
        end
    end
    if #choices == 0 then return nil end
    local selected = nil
    local appearance = ProjectALife.Appearance
    if weaponSlot ~= nil and appearance ~= nil and not appearance.loadoutVariation() then
        selected = choices[1]
    else
        selected = choices[stableIndex(
            tostring(identitySeed(actor) or "") .. "|" .. tostring(actor.profileId or "") .. "|" .. slot,
            #choices)]
    end
    if string.lower(selected) == "none" then return nil end
    return selected
end

local function sortedEntries(source, actor, profileId, tints)
    local keys = {}
    for key in pairs(source or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local result = {}
    for _, key in ipairs(keys) do
        local itemType = resolveChoice(source[key], actor,
            profileId .. ":clothing:" .. key, 4)
        if itemType ~= nil then result[#result + 1] = {
            slot = key, itemType = itemType, tint = tints and tints[key] or nil,
        } end
    end
    return Hydrator.renderOrder(result)
end

function Hydrator.seasonOfMonth(month)
    month = tonumber(month)
    if month == nil or month < 0 or month >= 12 then return nil end
    month = math.floor(month)
    if month <= 1 or month == 11 then return "winter" end
    if month <= 4 then return "spring" end
    if month <= 7 then return "summer" end
    return "autumn"
end

function Hydrator.calendarSeason(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    local month = type(memory) == "table" and tonumber(memory.loadoutMonth) or nil
    if month == nil and type(getGameTime) == "function" then
        local ok, value = pcall(function() return getGameTime():getMonth() end)
        if ok then month = tonumber(value) end
    end
    return Hydrator.seasonOfMonth(month)
end

Hydrator.climateWardrobe = true
Hydrator.seasonForced = nil

function Hydrator.wardrobeSeason(actor, context)
    context = type(context) == "table" and context or {}
    local seasons = ProjectALife.Seasons
    if Hydrator.climateWardrobe == true and seasons ~= nil and type(seasons.wardrobe) == "function" then
        local season, info = seasons.wardrobe(context.calendar)
        if season ~= nil then return season, info end
    end
    local season = Hydrator.calendarSeason(actor)
    return season, { source = "calendar", calendar = season, base = season }
end

function Hydrator.seasonFor(actor)
    if Hydrator.seasonForced ~= nil then return Hydrator.seasonForced end
    return (Hydrator.wardrobeSeason(actor))
end

function Hydrator.outfitSeasonFor(profile, actor)
    if type(profile) == "table" and profile.shippedProgression == true
            and Hydrator.worldSetting("seasonalDress", "Loadouts_SeasonalDress") == false then
        return nil
    end
    return Hydrator.seasonFor(actor)
end

function Hydrator.seasonalVariants(variants, seasons, season)
    if type(seasons) ~= "table" or season == nil then return variants end
    local matching, untagged = {}, {}
    for _, variant in ipairs(variants) do
        local tag = string.lower(tostring(seasons[variant.id] or "random"))
        if tag == season then
            matching[#matching + 1] = variant
        elseif tag == "random" or tag == "" then
            untagged[#untagged + 1] = variant
        end
    end
    if #matching > 0 then return matching end
    if #untagged > 0 then return untagged end
    return variants
end

function Hydrator.factionWardrobe(profile, actor, variants)
    if Hydrator.worldSetting("seasonalDress", "Loadouts_SeasonalDress") == false then return nil end
    local season = Hydrator.seasonFor(actor)
    if season == nil then return nil end
    for _, variant in ipairs(variants) do
        if not ProjectALife.CustomProfiles.syntheticOutfit(profile, variant.id) then
            local tag = type(profile.outfitSeason) == "table" and profile.outfitSeason[variant.id] or "random"
            tag = string.lower(tostring(tag or "random"))
            if tag == season or tag == "random" or tag == "" then return nil end
        end
    end
    local faction = Catalog.faction(type(profile.general) == "table" and profile.general.faction or nil)
    if type(faction) ~= "table" then return nil end
    for _, row in ipairs(ProjectALife.SeasonalWardrobe.rows(faction)) do
        if row.season == season and type(faction.outfitSeason) == "table"
                and faction.outfitSeason[row.id] == season
                and ProjectALife.SeasonalWardrobe.signature(row.clothing) ~= "" then return row end
    end
    return nil
end

local function clothingFor(profile, actor)
    local variants = {}
    for _, id in ipairs({ "A", "B", "C", "D", "E", "F" }) do
        local outfit = profile.outfitSets and profile.outfitSets[id]
            or profile["outfit" .. id]
            or profile.outfits and profile.outfits[id]

        local occupied = false
        if type(outfit) == "table" then
            for _ in pairs(outfit) do occupied = true break end
        end
        local enabled = profile.outfitEnabled == nil
            or profile.outfitEnabled[id] == nil
            or profile.outfitEnabled[id] == true
        if occupied and enabled then
            variants[#variants + 1] = { id = id, clothing = outfit,
                tints = profile["tint" .. id]
                    or profile.outfitTints and profile.outfitTints[id] or {} }
        end
    end

    local factionWardrobe = Hydrator.factionWardrobe(profile, actor, variants)
    if factionWardrobe ~= nil then
        return factionWardrobe.clothing, factionWardrobe.tints, true
    end
    if #variants == 0 then return profile.clothing or {}, {} end
    variants = Hydrator.seasonalVariants(variants, profile.outfitSeason, Hydrator.outfitSeasonFor(profile, actor))
    local index = stableIndex(tostring(identitySeed(actor) or "") .. "|"
        .. tostring(profile.id or "") .. "|outfit", #variants)
    return variants[index].clothing, variants[index].tints
end

local function setVariable(shell, name, value)
    local ok = pcall(function() shell:SetVariable(name, tostring(value)) end)
    if not ok then pcall(function() shell:setVariable(name, tostring(value)) end) end
end

setMetadata = function(shell, name, value)
    setVariable(shell, name, value)
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" then data["Project" .. name] = value end
end

function Hydrator.configure(adapters)
    Hydrator.adapters = adapters or {}
end

function Hydrator.spawnOverride(actor, key)
    local memory = type(actor) == "table" and type(actor.memory) == "table"
        and actor.memory or nil
    local value = memory ~= nil and memory[key] or nil
    if value == nil then return nil end
    return value
end

function Hydrator.dropSource(actor, general)
    local preset = Hydrator.spawnOverride(actor, "weaponChance")
    if preset == nil then return general end
    local copy = {}
    for key, value in pairs(type(general) == "table" and general or {}) do copy[key] = value end
    copy.dropWeaponPreset = preset
    copy.dropWeapon = preset ~= "off"
    copy.dropWeaponChance = nil
    return copy
end

function Hydrator.issueCondition(item, rating)
    local ok = pcall(function()
        local policy = ProjectALife.DropPolicy
        policy.issue(item, policy.conditionFor(item:getConditionMax(), rating))
    end)
    return ok
end

local function stablePercent(value)
    local seed = 0
    value = tostring(value or "")
    for index = 1, #value do
        seed = (seed * 33 + string.byte(value, index)) % 2147483647
    end
    return seed % 100
end

local function combatReadyFor(actor, profile, general)
    local settings = BehaviorSettings and BehaviorSettings.combat or {}
    local authoredMode = string.lower(tostring(general.combatReady
        or profile.combatReady or settings.combatReadyMode or "default"))
    if authoredMode ~= "yes" and authoredMode ~= "no"
            and authoredMode ~= "mixed" and authoredMode ~= "default" then
        authoredMode = "default"
    end
    local mode = authoredMode
    if mode == "default" then mode = "mixed" end
    if mode == "yes" then return true, authoredMode end
    if mode == "no" then return false, authoredMode end
    local chance = math.max(0, math.min(100,
        tonumber(settings.combatReadyMixedPercent) or 50))
    return stablePercent(actor.uid) < chance, authoredMode
end

Hydrator.seasonWear = {
    coats = { "Base.Jacket_PaddedDOWN", "Base.Jacket_SheepSkin", "Base.Jacket_Black",
        "Base.Jacket_NavyBlue", "Base.Jacket_LeatherBrown" },
    huntingCoat = "Base.Jacket_Padded_HuntingCamoDOWN",
    jackets = { "Base.Jacket_Black", "Base.Jacket_NavyBlue", "Base.Jacket_LeatherBrown", "Base.Jacket_Varsity" },
    hats = { "Base.Hat_WinterHat", "Base.Hat_WoolyHat" },
    gloves = { "Base.Gloves_LeatherGloves", "Base.Gloves_LeatherGlovesBlack",
        "Base.Gloves_LeatherGlovesBrown", "Base.Gloves_FingerlessGloves" },
    uniformGloves = "Base.Gloves_LeatherGlovesBlack",
    scarves = { "Base.Scarf_White", "Base.Scarf_StripeBlackWhite", "Base.Scarf_StripeBlueWhite",
        "Base.Scarf_StripeRedWhite" },

    serviceCoats = { { "sheriff", "Base.Jacket_Sheriff" }, { "police", "Base.Jacket_Police" },
        { "ranger", "Base.Jacket_Ranger" }, { "army", "Base.Jacket_CoatArmy" },
        { "military", "Base.Jacket_CoatArmy" }, { "fireman", "Base.Jacket_Fireman" } },

    uniform = { "sheriff", "police", "ranger", "army", "military", "swat", "prison", "fireman",
        "hospital", "scrubs", "doctor", "nurse", "priest", "chef", "security" },
    costume = { "hazmat", "spiffo", "ghillie", "bathrobe", "wedding", "fullsuit" },
    outer = { "jacket", "coat", "parka", "poncho", "hoodie", "robe", "trench" },
    jacket = { "jacket", "coat" },
    hat = { "hat", "helmet", "cap", "beret", "bandana", "hood", "balaclava" },
    torso = { "tshirt", "shirt", "tanktop", "jumper", "sweater", "hoodie", "dress", "boilersuit",
        "blouse", "jacket", "coat", "parka", "poncho" },
    heavy = { "padded", "parka", "sheepskin", "coatarmy", "winterhat", "woolyhat", "beanie", "scarf",
        "earmuff", "wool" },
    light = { "winterhat", "woolyhat", "beanie", "scarf", "earmuff", "wool" },
    sweater = { "jumper", "sweater" },
    chances = { coat = 90, hat = 55, gloves = 60, scarf = 35, jacket = 45, summer = 85, spring = 50,
        uniformScarf = 75, summerJacket = 60 },
}

function Hydrator.wearHas(itemType, words)
    local lowered = string.lower(tostring(itemType or ""))
    for _, word in ipairs(words) do
        if string.find(lowered, word, 1, true) then return word end
    end
    return nil
end

function Hydrator.wearAny(entries, words)
    for _, entry in ipairs(entries) do
        local found = Hydrator.wearHas(entry.itemType, words)
        if found ~= nil then return found end
    end
    return nil
end

function Hydrator.uniformOf(entries)
    for _, word in ipairs(Hydrator.seasonWear.uniform) do
        for _, entry in ipairs(entries) do
            local lowered = string.lower(tostring(entry.itemType or ""))
            if string.find(lowered, word, 1, true)
                    and Hydrator.wearHas(lowered, { "shoes", "vest", "bag" }) == nil then
                return word
            end
        end
    end
    return nil
end

function Hydrator.underlayer(entries, index, uniform)
    local wear = Hydrator.seasonWear
    for other, entry in ipairs(entries) do
        if other ~= index and Hydrator.wearHas(entry.itemType, wear.torso) ~= nil
                and Hydrator.wearHas(entry.itemType, wear.jacket) == nil
                and (not uniform or Hydrator.wearHas(entry.itemType, wear.uniform) ~= nil) then
            return true
        end
    end
    return false
end

function Hydrator.authoredSeasons(profile)
    local seasons = type(profile) == "table" and profile.outfitSeason or nil
    if type(seasons) ~= "table" then return false end
    for _, tag in pairs(seasons) do
        local lowered = string.lower(tostring(tag or ""))
        if lowered ~= "" and lowered ~= "random" then return true end
    end
    return false
end

function Hydrator.dressForSeason(entries, season, seed)
    local wear = Hydrator.seasonWear
    if type(entries) ~= "table" or season == nil or #entries == 0
            or Hydrator.wearAny(entries, wear.costume) ~= nil then
        return entries
    end
    seed = tostring(seed or "") .. ":" .. season
    local function roll(key) return stableIndex(seed .. ":" .. key, 100) - 1 end
    local function pick(list, key) return list[stableIndex(seed .. ":" .. key, #list)] end
    local uniform = Hydrator.uniformOf(entries) ~= nil
    local strip = season == "summer" and wear.heavy or season == "spring" and wear.light or nil
    local stripChance = season == "summer" and wear.chances.summer or wear.chances.spring
    local drops, covered = {}, false
    for index, entry in ipairs(entries) do
        if strip ~= nil and Hydrator.wearHas(entry.itemType, strip) ~= nil
                and roll("strip:" .. tostring(entry.itemType)) < stripChance then
            drops[index] = true
        elseif season == "summer" and not uniform and Hydrator.wearHas(entry.itemType, wear.sweater) ~= nil
                and roll("sweater") < stripChance then
            drops[index] = true
        elseif season == "summer" and Hydrator.wearHas(entry.itemType, wear.jacket) ~= nil
                and roll("jacket") < wear.chances.summerJacket and Hydrator.underlayer(entries, index, uniform) then
            drops[index] = true
        end
        if not drops[index] and Hydrator.wearHas(entry.itemType, wear.torso) ~= nil then covered = true end
    end
    local result = {}
    for index, entry in ipairs(entries) do
        local keep = not drops[index]

        if not keep and not covered and (Hydrator.wearHas(entry.itemType, wear.torso) ~= nil
                or Hydrator.wearHas(entry.itemType, wear.outer) ~= nil) then
            keep, covered = true, true
        end
        if keep then result[#result + 1] = entry end
    end
    local function add(slot, itemType)
        if itemType ~= nil and Hydrator.itemKnown(itemType) then
            result[#result + 1] = { slot = slot, itemType = itemType, seasonal = season }
        end
    end
    local hasOuter = Hydrator.wearAny(result, wear.outer) ~= nil
    if season == "winter" then
        if uniform then
            local family, serviceCoat = Hydrator.uniformOf(result), nil
            for _, row in ipairs(wear.serviceCoats) do
                if row[1] == family then serviceCoat = row[2] end
            end
            if serviceCoat ~= nil and not hasOuter and roll("coat") < wear.chances.coat then
                add("SeasonCoat", serviceCoat)
            end
            if Hydrator.wearAny(result, { "gloves" }) == nil and roll("gloves") < wear.chances.gloves then
                add("SeasonGloves", wear.uniformGloves)
            end

            if (serviceCoat == nil or hasOuter) and Hydrator.wearAny(result, { "scarf" }) == nil
                    and roll("scarf") < wear.chances.uniformScarf then
                add("SeasonScarf", wear.scarves[1])
            end
        else
            if not hasOuter and roll("coat") < wear.chances.coat then
                add("SeasonCoat", Hydrator.wearAny(result, { "hunting" }) ~= nil and wear.huntingCoat
                    or pick(wear.coats, "coat"))
            end
            if Hydrator.wearAny(result, wear.hat) == nil and roll("hat") < wear.chances.hat then
                add("SeasonHat", pick(wear.hats, "hat"))
            end
            if Hydrator.wearAny(result, { "gloves" }) == nil and roll("gloves") < wear.chances.gloves then
                add("SeasonGloves", pick(wear.gloves, "gloves"))
            end
            if Hydrator.wearAny(result, { "scarf" }) == nil and roll("scarf") < wear.chances.scarf then
                add("SeasonScarf", pick(wear.scarves, "scarf"))
            end
        end
    elseif season == "autumn" and not uniform and not hasOuter and roll("jacket") < wear.chances.jacket then
        add("SeasonCoat", pick(wear.jackets, "jacket"))
    end
    if #result == #entries then
        local same = true
        for index, entry in ipairs(result) do if entries[index] ~= entry then same = false end end
        if same then return entries end
    end
    return Hydrator.renderOrder(result)
end

function Hydrator.seasonalDress(entries, profile, actor, factionWardrobe)
    if Hydrator.worldSetting("seasonalDress", "Loadouts_SeasonalDress") == false then
        return entries
    end
    local seed, season = identitySeed(actor), Hydrator.seasonFor(actor)
    if Hydrator.authoredSeasons(profile) or factionWardrobe == true then
        if type(profile) == "table" and profile.shippedProgression == true then
            return Hydrator.rainDress(entries, season, seed, profile)
        end
        return entries
    end
    return Hydrator.rainDress(Hydrator.dressForSeason(entries, season, seed), season, seed, profile)
end

Hydrator.rainWear = {
    ponchos = { "Base.PonchoGreenDOWN", "Base.PonchoYellowDOWN" },
    hat = "Base.Hat_FishermanRainHat",
    wetSeasons = { spring = true, autumn = true },
    threshold = 0.1,
    freezingC = 2,
    chances = { raining = 65, wet = 0, hat = 40 },
    blocs = { civilian = true, family = true, worker = true },
    uniformWords = { "camo", "olivedrab", "army", "military", "swat", "ghillie" },
}

function Hydrator.worldDay()
    if type(getGameTime) ~= "function" then return 0 end
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    hours = ok and tonumber(hours) or nil
    if hours == nil or hours ~= hours then return 0 end
    return math.floor(hours / 24)
end

function Hydrator.precipitation()
    local rain = Hydrator.rainWear
    local seasons = ProjectALife.Seasons
    local override = seasons ~= nil and seasons.wardrobeOverride or nil
    if override ~= nil then
        if (tonumber(override.wet) or 0) <= rain.threshold then return nil, override.tempC end
        if override.tempC <= rain.freezingC then return "snow", override.tempC end
        return "rain", override.tempC
    end
    if type(getClimateManager) ~= "function" then return nil end
    local ok, kind, air = pcall(function()
        local climate = getClimateManager()
        if climate == nil or climate.getPrecipitationIntensity == nil then return nil end
        local wet = tonumber(climate:getPrecipitationIntensity()) or 0
        local temp = nil
        if type(climate.getTemperature) == "function" then temp = tonumber(climate:getTemperature()) end
        if wet <= rain.threshold then return nil, temp end
        local snowing = type(climate.isSnowing) == "function" and climate:isSnowing() == true
        if snowing or (temp ~= nil and temp <= rain.freezingC) then return "snow", temp end
        return "rain", temp
    end)
    if not ok then return nil end
    return kind, air
end

function Hydrator.raining()
    return Hydrator.precipitation() == "rain"
end

function Hydrator.armedProfile(profile)
    return type(profile) == "table" and Hydrator.authorsFirearm(profile) == true
end

function Hydrator.rainGear(profile, entries)
    if type(profile) ~= "table" then return true end
    local general = type(profile.general) == "table" and profile.general or {}
    local class = general.npcClass
    if class == "police" or class == "military" or class == "rescue" or class == "criminal" then return false end
    if profile.uniform == true or general.uniform == true then return false end
    local faction = Catalog.faction(general.faction)
    if type(faction) == "table" and faction.uniform == true then return false end
    local generator = ProjectALife.SeasonalOutfitGenerator
    if generator ~= nil and type(generator.classOf) == "function" then
        local ok, kind = pcall(generator.classOf, profile, faction)
        if ok and kind ~= nil and kind ~= "civilian" then return false end
        local blocOk, bloc = pcall(generator.blocOf, faction)
        if blocOk and bloc ~= nil and Hydrator.rainWear.blocs[bloc] ~= true then return false end
    end
    if Hydrator.uniformOf(entries) ~= nil or Hydrator.wearAny(entries, Hydrator.rainWear.uniformWords) ~= nil then
        return false
    end
    return true
end

function Hydrator.rainScope(profile, seed)
    local general = type(profile) == "table" and type(profile.general) == "table" and profile.general or nil
    if general == nil then return tostring(seed or "") end
    local scope = general.faction
    if scope == nil or scope == "" then scope = profile.id end
    return tostring(scope) .. ":" .. tostring(Hydrator.worldDay())
end

function Hydrator.rainDress(entries, season, seed, profile)
    local rain, wear = Hydrator.rainWear, Hydrator.seasonWear
    if type(entries) ~= "table" or #entries == 0 or Hydrator.wearAny(entries, wear.costume) ~= nil then
        return entries
    end
    local kind, air = Hydrator.precipitation()
    if kind == "snow" or season == "winter" then return entries end
    if air ~= nil and air <= rain.freezingC then return entries end
    if not Hydrator.rainGear(profile, entries) then return entries end
    local chance = rain.chances.wet
    if kind == "rain" then chance = rain.chances.raining
    elseif not rain.wetSeasons[tostring(season)] then chance = 0 end
    local scope = Hydrator.rainScope(profile, seed) .. ":rain"
    if stableIndex(scope, 100) - 1 >= chance then return entries end
    local result = {}
    for _, entry in ipairs(entries) do result[#result + 1] = entry end
    local added = false
    if Hydrator.wearAny(result, wear.outer) == nil then
        local poncho = rain.ponchos[stableIndex(scope .. ":poncho", #rain.ponchos)]
        if Hydrator.itemKnown(poncho) then
            result[#result + 1] = { slot = "SeasonRain", itemType = poncho, seasonal = "rain" }
            added = true
        end
    end
    if added and not Hydrator.armedProfile(profile) and Hydrator.wearAny(result, wear.hat) == nil
            and stableIndex(scope .. ":hat", 100) - 1 < rain.chances.hat and Hydrator.itemKnown(rain.hat) then
        result[#result + 1] = { slot = "SeasonRainHat", itemType = rain.hat, seasonal = "rain" }
    end
    if #result == #entries then return entries end
    return Hydrator.renderOrder(result)
end

Hydrator.evolution = {
    defaultDay = 10,
    makeshiftAt = 3,
    chances = { mixed = 55, makeshift = 85, armour = 45 },
    words = { "sheriff", "police", "ranger", "army", "military", "swat", "prison", "fireman",
        "scrubs", "doctor", "camo", "olivedrab" },
    exempt = { "shoes", "boots", "vest", "bag", "holster", "gloves", "necklace", "kneepad", "elbowpad" },
    plain = {
        Hat = { "none", "Base.Hat_BaseballCap", "Base.Hat_Beany", "Base.Hat_WoolyHat", "Base.Hat_Bandana" },
        Top = { "Base.Shirt_Denim", "Base.Shirt_Lumberjack", "Base.Shirt_Workman", "Base.Tshirt_DefaultTEXTURE_TINT" },
        Tshirt = { "Base.Tshirt_DefaultTEXTURE_TINT", "Base.Tshirt_WhiteTINT", "Base.Tshirt_Rock" },
        Sweater = { "Base.Jumper_RoundNeck", "Base.HoodieDOWN_WhiteTINT" },
        Jacket = { "Base.Jacket_Padded", "Base.Jacket_LeatherBrown", "Base.Jacket_Black", "Base.JacketLong_Random",
            "Base.Jacket_Varsity" },
        Pants = { "Base.Trousers_Denim", "Base.Trousers_DefaultTEXTURE_TINT", "Base.Trousers_Crafted_Denim" },
        SeasonCoat = { "Base.Jacket_PaddedDOWN", "Base.Jacket_SheepSkin", "Base.JacketLong_Random" },
    },
    makeshift = {
        { { "LeftKnee", "Base.Kneepad_Left_Workman" }, { "RightKnee", "Base.Kneepad_Right_Workman" } },
        { { "Gorget", "Base.Gorget_Denim" } },
        { { "LeftForearm", "Base.Vambrace_Leather_Left" }, { "RightForearm", "Base.Vambrace_Leather_Right" } },
        { { "Cuirass", "Base.Cuirass_Tire" } },
    },
}

function Hydrator.uniformPiece(itemType)
    local rule = Hydrator.evolution
    return Hydrator.wearHas(itemType, rule.words) ~= nil and Hydrator.wearHas(itemType, rule.exempt) == nil
end

function Hydrator.evolutionStage(actor)
    local rule = Hydrator.evolution
    local memory = type(actor) == "table" and actor.memory or nil
    local day = type(memory) == "table" and tonumber(memory.loadoutDay) or nil
    if day ~= nil then day = ProjectALife.LoadoutProgression.funnelDay(day) end
    local start = tonumber(Hydrator.worldSetting("uniformDecayDay", "Loadouts_UniformDecayDay")) or rule.defaultDay
    if day == nil or start <= 0 or day < start then return nil end
    if day >= start * rule.makeshiftAt then return "makeshift" end
    return "mixed"
end

function Hydrator.evolveUniform(entries, profile, actor)
    local rule, wear = Hydrator.evolution, Hydrator.seasonWear
    if type(entries) ~= "table" or #entries == 0 or type(profile) ~= "table"
            or profile.shippedProgression ~= true or Hydrator.uniformOf(entries) == nil
            or Hydrator.wearAny(entries, wear.costume) ~= nil then
        return entries
    end
    local stage = Hydrator.evolutionStage(actor)
    if stage == nil then return entries end
    local seed = tostring(identitySeed(actor) or "") .. ":evolve"
    if stableIndex(seed, 100) - 1 >= rule.chances[stage] then return entries end
    local pieces = {}
    for index, entry in ipairs(entries) do
        if Hydrator.uniformPiece(entry.itemType) then pieces[#pieces + 1] = index end
    end
    if #pieces == 0 then return entries end
    local keep = pieces[stableIndex(seed .. ":keep", #pieces)]
    local result, slots, suitGone = {}, {}, false
    for index, entry in ipairs(entries) do
        if index == keep or not Hydrator.uniformPiece(entry.itemType) then
            result[#result + 1] = entry
            slots[tostring(entry.slot)] = true
        elseif entry.slot == "FullSuit" then
            suitGone = true
        else
            local pool = rule.plain[tostring(entry.slot)]
            local swap = pool and pool[stableIndex(seed .. ":" .. tostring(entry.slot), #pool)] or nil
            if swap ~= nil and swap ~= "none" and Hydrator.itemKnown(swap) then
                result[#result + 1] = { slot = entry.slot, itemType = swap, evolved = stage }
                slots[tostring(entry.slot)] = true
            end
        end
    end
    if suitGone then
        Hydrator.evolvedPiece(result, slots, "Top", rule.plain.Top[stableIndex(seed .. ":suitTop", #rule.plain.Top)], stage)
        Hydrator.evolvedPiece(result, slots, "Pants",
            rule.plain.Pants[stableIndex(seed .. ":suitPants", #rule.plain.Pants)], stage)
    end
    if Hydrator.wearAny(result, wear.torso) == nil then
        Hydrator.evolvedPiece(result, slots, "Tshirt",
            rule.plain.Tshirt[stableIndex(seed .. ":torso", #rule.plain.Tshirt)], stage)
    end
    if stage == "makeshift" and stableIndex(seed .. ":armour", 100) - 1 < rule.chances.armour then
        local set = rule.makeshift[stableIndex(seed .. ":set", #rule.makeshift)]
        for _, piece in ipairs(set) do Hydrator.evolvedPiece(result, slots, piece[1], piece[2], stage) end
    end
    return Hydrator.renderOrder(result)
end

function Hydrator.evolvedPiece(result, slots, slot, itemType, stage)
    if slots[slot] or not Hydrator.itemKnown(itemType) then return false end
    result[#result + 1] = { slot = slot, itemType = itemType, evolved = stage }
    slots[slot] = true
    return true
end

Hydrator.faces = {
    male = {
        light = { trained = { "CrewCut", "Short", "Bald", "FlatTop" },
            plain = { "Short", "CrewCut", "Messy", "Recede", "CentreParting", "Mullet", "GreasedBack" } },
        dark = { trained = { "CrewCut", "Bald", "FlatTop", "ShortAfroCurly", "Fresh" },
            plain = { "ShortAfroCurly", "Cornrows", "Fresh", "Braids", "FlatTop", "Bald", "MessyCurly", "LongBraids" } },
        older = { "Bald", "Recede", "Short" },
    },
    female = {
        light = { plain = { "Bob", "PonyTail", "Bun", "ShortCurly", "Kate", "BobCurly", "Back", "LongBraids" } },
        dark = { plain = { "Cornrows", "LongBraids", "Braids", "PonyTailBraids", "ShortCurly", "BunCurly", "TopCurls",
            "BobCurly" } },
    },
    beards = { light = { "Moustache", "Chin" }, heavy = { "Full", "BeardOnly", "Chops" } },
    grey = "0.52,0.50,0.46",
}

function Hydrator.faceFamily(list, style)
    for _, value in ipairs(list or {}) do
        if value == style then return list end
    end
    return nil
end

function Hydrator.varyFace(plan, profile)
    if type(plan) ~= "table" or type(profile) ~= "table" or profile.shippedProgression ~= true then return plan end
    local faces = Hydrator.faces
    local seed = tostring(plan.appearanceSeed or plan.actorUid or "") .. ":face"
    local sex = plan.female == true and faces.female or faces.male
    local tone = (tonumber(plan.skin) or 0) >= 3 and sex.dark or sex.light
    local style, beard = tostring(plan.hairStyle or ""), tostring(plan.beardStyle or "")
    local family
    if plan.female ~= true and string.sub(tostring(plan.hairColor or ""), 1, #faces.grey) == faces.grey then
        family = Hydrator.faceFamily(faces.male.older, style)
    end
    if family == nil and plan.female ~= true and beard == "" then family = Hydrator.faceFamily(tone.trained, style) end
    family = family or Hydrator.faceFamily(tone.plain, style)
    if family ~= nil then plan.hairStyle = family[stableIndex(seed .. ":hair", #family)] end
    if beard ~= "" and plan.female ~= true then
        local beards = Hydrator.faceFamily(faces.beards.light, beard) or Hydrator.faceFamily(faces.beards.heavy, beard)
        if beards ~= nil then plan.beardStyle = beards[stableIndex(seed .. ":beard", #beards)] end
    end
    return plan
end

function Hydrator.npcHealth(profile, actor, health)
    local tuned = ProjectALife.NpcHealth
    if tuned == nil or type(tuned.scaleFor) ~= "function" then return 1, health end
    local ok, scale = pcall(tuned.scaleFor, profile, actor)
    scale = ok and tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return scale, math.max(1, health * scale)
end

function Hydrator.plan(actor)
    if type(actor) ~= "table" or type(actor.profileId) ~= "string" then
        return nil, "profile_actor_invalid"
    end
    local profile = Catalog.npc(actor.profileId)
    if profile == nil then return nil, "profile_missing:" .. actor.profileId end
    local general = profile.general or {}
    local female = general.female == true
    local skin = humanSkinIndex(general.skin)

    local admin = type(actor.memory) == "table"
        and type(actor.memory.admin) == "table" and actor.memory.admin or nil

    local healthScale = 1
    pcall(function()
        local combat = ProjectALife.BehaviorSettings
            and ProjectALife.BehaviorSettings.combat or nil
        healthScale = tonumber(combat and combat.healthMultiplier) or 1
    end)
    if healthScale <= 0 then healthScale = 1 end
    local exactHealth = admin and tonumber(admin.health) or nil
    local playerHealth
    local npcHealthScale = 1
    if exactHealth and exactHealth > 0 then
        playerHealth = exactHealth
    else
        local base = tonumber(general.healthHP) or ProjectALife.CustomProfiles.startingHP()
        local tunedHealth = ProjectALife.NpcHealth
        if tunedHealth ~= nil and type(tunedHealth.authored) == "function" then
            base = tunedHealth.authored(general, ProjectALife.CustomProfiles.startingHP())
        end
        playerHealth = math.max(1, base * healthScale)
        npcHealthScale, playerHealth = Hydrator.npcHealth(profile, actor, playerHealth)
    end

    local healthRating = math.max(1, math.min(20, playerHealth / 10))
    local authoredMode = string.lower(tostring(general.ammoMode
        or profile.ammoMode or "rounds"))
    if authoredMode ~= "magazines" then authoredMode = "rounds" end
    local authoredMagazines = profile.magazines or {}
    local primaryMagazines = authoredMode == "magazines" and
        (tonumber(general.primaryMagazines) or tonumber(authoredMagazines.primary)) or nil
    local secondaryMagazines = authoredMode == "magazines" and
        (tonumber(general.secondaryMagazines) or tonumber(authoredMagazines.secondary)) or nil
    local combatReady, combatReadyMode = combatReadyFor(actor, profile, general)
    local selectedClothing, selectedTints, factionWardrobe = clothingFor(profile, actor)
    local plan = {
        actorUid = actor.uid,
        appearanceSeed = identitySeed(actor),
        profileId = profile.id,
        factionId = general.faction,
        name = general.name,
        personName = Hydrator.personNameFor(actor),
        female = female,
        skin = skin,
        skinTexture = humanSkinTexture(female, skin),
        hairStyle = general.hairStyle or "",
        hairColor = general.hairColor or "",
        beardStyle = general.beardStyle or "",
        beardColor = general.beardColor or general.hairColor or "",
        health = math.max(1, playerHealth),
        healthRating = healthRating,
        npcHealthScale = npcHealthScale,
        strength = ProjectALife.CustomProfiles.rating(general, "strength"),
        endurance = ProjectALife.CustomProfiles.rating(general, "endurance"),
        awareness = ProjectALife.CustomProfiles.rating(general, "awareness"),
        aiming = ProjectALife.CustomProfiles.rating(general, "aiming"),

        aimPlayerPercent = tonumber(general.aimPlayerPercent),
        aimZombiePercent = tonumber(general.aimZombiePercent),

        damageReduction = math.max(0, math.min(90,
            (admin and tonumber(admin.damageReduction))
            or tonumber(general.damageReduction) or 0)),
        damageOutput = math.max(1, math.min(500,
            (admin and tonumber(admin.damageOutput))
            or tonumber(general.damageOutput) or 100)),

        voiceProfile = (ProjectALife.VoiceAssignment and ProjectALife.VoiceAssignment.assign(
            general.voiceProfile, general.faction, female, identitySeed(actor))) or general.voiceProfile or "",
        profession = general.profession or "none",
        infiniteAmmo = Hydrator.bottomless(profile, general),
        supportCaller = general.supportCaller == true,
        combatReady = combatReady,
        combatReadyMode = combatReadyMode,
        drop = {
            ammo = general.dropAmmo == true,
            magazineMax = tonumber(general.magazineDropMax) or 0,
            magazineChance = tonumber(general.magazineDropChance) or 0,
            weapon = general.dropWeapon == true,
            weaponChance = ProjectALife.DropPolicy.chance(
                Hydrator.dropSource(actor, general), identitySeed(actor)),

            weaponCondition = ProjectALife.DropPolicy.wornRating(
                Hydrator.spawnOverride(actor, "weaponCondition") or general.dropWeaponCondition,
                identitySeed(actor) .. ":weapon"),
            armorChance = tonumber(general.dropArmorChance) or 0,

            armorCondition = ProjectALife.DropPolicy.wornRating(
                Hydrator.spawnOverride(actor, "clothingCondition") or general.armorCondition,
                identitySeed(actor) .. ":armor"),
        },
        clothing = Hydrator.evolveUniform(Hydrator.seasonalDress(
            sortedEntries(selectedClothing, actor, profile.id, selectedTints), profile, actor, factionWardrobe), profile, actor),
        weapons = {
            primary = resolveChoice(profile.weapons and profile.weapons.primary or nil,
                actor, profile.id .. ":weapon:primary", nil, "primary"),
            secondary = resolveChoice(profile.weapons and profile.weapons.secondary or nil,
                actor, profile.id .. ":weapon:secondary", nil, "secondary"),

            melee = resolveChoice(profile.weapons and profile.weapons.melee or nil,
                actor, profile.id .. ":weapon:melee", nil, "melee") or "Base.BareHands",
        },
        weaponAttachments = profile.weaponAttachments or {},

        firearmsAuthored = Hydrator.authorsFirearm(profile),
        ammo = {
            primary = primaryMagazines
                or (profile.ammo and tonumber(profile.ammo.primary)) or 0,
            secondary = secondaryMagazines
                or (profile.ammo and tonumber(profile.ammo.secondary)) or 0,
        },
        ammoMode = {
            primary = primaryMagazines ~= nil and "magazines" or authoredMode,
            secondary = secondaryMagazines ~= nil and "magazines" or authoredMode,
        },
    }
    local appearance = ProjectALife.Appearance
    local handled = false
    if appearance ~= nil and type(appearance.apply) == "function" then
        local ok, result = pcall(appearance.apply, plan, profile, actor)
        handled = ok and result == true
    end
    if not handled then Hydrator.varyFace(plan, profile) end
    if profile.shippedProgression == true then
        plan = ProjectALife.LoadoutProgression.apply(actor, profile, plan, Hydrator.itemKnown)
        Hydrator.funnelAim(plan, actor)
    end
    plan = ProjectALife.LootRarity.sanitizePlan(plan, profile, actor)
    if appearance ~= nil and type(appearance.finish) == "function" then
        pcall(appearance.finish, plan, profile, actor, selectedClothing)
    end
    plan = Hydrator.sandboxDrops(actor, plan, identitySeed(actor))
    local memory = actor.memory
    local wardrobe = ProjectALife.VisitorWardrobe
    if type(memory) == "table" and memory.person ~= nil and wardrobe ~= nil and type(wardrobe.refine) == "function" then
        local refined = nil
        if pcall(function() refined = wardrobe.refine(plan, actor) end) and type(refined) == "table" then plan = refined end
    end
    local outfits = ProjectALife.VisitOutfits
    if type(memory) == "table" and memory.person == nil and type(memory.visit) == "table" and outfits ~= nil then
        local dressed = nil
        if pcall(function() dressed = outfits.apply(plan, actor, Hydrator.seasonFor(actor), Hydrator.uniformOf) end)
                and type(dressed) == "table" then plan = dressed end
    end
    return plan
end

function Hydrator.funnelAim(plan, actor)
    local funnel = ProjectALife.Funnel
    local memory = type(actor) == "table" and actor.memory or nil
    local day = type(memory) == "table" and tonumber(memory.loadoutDay) or nil
    if day == nil or type(plan) ~= "table" or type(funnel) ~= "table" or type(funnel.aimBonus) ~= "function" then
        return plan
    end
    local bonus = tonumber(funnel.aimBonus(day)) or 0
    if bonus <= 0 then return plan end
    plan.aiming = math.min(10, (tonumber(plan.aiming) or 0) + bonus)
    return plan
end

function Hydrator.worldSetting(field, sandboxKey)
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current[field] ~= nil then return current[field] end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" then
        return SandboxVars.ALife[sandboxKey]
    end
    return nil
end

function Hydrator.bottomless(profile, general)
    if type(general) ~= "table" or general.infiniteAmmo ~= true then return false end
    local mode = math.floor(tonumber(Hydrator.worldSetting("ammoBottomless", "Ammo_Bottomless")) or 1)
    if mode == 3 then return false end
    if mode == 2 then return true end
    return not (type(profile) == "table" and profile.shippedProgression == true)
end

function Hydrator.sandboxDrops(actor, plan, seed)
    if type(plan) ~= "table" or type(plan.drop) ~= "table" then return plan end
    if Hydrator.spawnOverride(actor, "weaponChance") ~= nil then plan.drop.weaponExplicit = true end
    if Hydrator.spawnOverride(actor, "weaponCondition") ~= nil then plan.drop.weaponConditionExplicit = true end
    local settings = ProjectALife.Settings and ProjectALife.Settings.current
    if type(settings) ~= "table" then return plan end
    local policy = ProjectALife.DropPolicy
    local preset = policy.sandboxPreset(settings.dropWeaponChance)
    if preset ~= nil and Hydrator.spawnOverride(actor, "weaponChance") == nil then
        plan.drop.weapon = preset ~= "off"
        plan.drop.weaponChance = policy.chance({ dropWeaponPreset = preset }, seed)
        plan.drop.weaponExplicit = true
    end
    local rating = policy.sandboxRating(settings.dropWeaponCondition)
    if rating ~= nil and Hydrator.spawnOverride(actor, "weaponCondition") == nil then
        plan.drop.weaponCondition = rating
        plan.drop.weaponConditionExplicit = true
    end
    return plan
end

function Hydrator.applyAppearance(shell, plan, withClothing)
    if shell == nil or type(plan) ~= "table" then return false end
    local ok = pcall(function()
        ProjectALife.AIFence.clearSkeleton(shell)
        shell:setFemaleEtc(plan.female)
        pcall(function() shell:SetName(plan.name) end)

        pcall(function() shell:setDressInRandomOutfit(false) end)
        pcall(function() shell:setPersistentOutfitID(0, true) end)
        local visual = shell:getHumanVisual()
        if visual == nil then return end

        visual:clear()
        visual:setSkinTextureIndex(plan.skin)
        visual:setSkinTextureName(plan.skinTexture)
        visual:removeBlood()
        visual:removeDirt()
        visual:setHairModel(plan.hairStyle)
        visual:setBeardModel(plan.beardStyle)
        applyAuthoredColor(visual, plan.hairColor, false)
        applyAuthoredColor(visual, plan.beardColor, true)
    end)

    if withClothing == true and ok then
        pcall(function()

            local deadOk, dead = pcall(function() return shell:isDead() end)
            if deadOk and dead == true then return end
            local worn = shell:getItemVisuals()
            if worn == nil or type(plan.clothing) ~= "table" then return end
            local signature = Hydrator.dressSignature(plan.actorUid, plan.appearanceSeed, plan.clothing)

            if Hydrator.dressed[shell] == signature and worn:size() > 0 then return end
            local visuals = {}
            for _, entry in ipairs(plan.clothing) do
                local itemType = type(entry) == "table" and entry.itemType or entry
                local item = type(instanceItem) == "function" and instanceItem(itemType) or nil
                local itemVisual = Hydrator.prepareClothing(item,
                    type(entry) == "table" and entry or { itemType = itemType },
                    plan.appearanceSeed or plan.actorUid)
                if itemVisual ~= nil then visuals[#visuals + 1] = itemVisual end
            end
            if #visuals == 0 or #visuals ~= #plan.clothing then return end
            worn:clear()
            for _, itemVisual in ipairs(visuals) do worn:add(itemVisual) end
            Hydrator.dressed[shell] = signature
            Hydrator.dressList[shell] = signature
            Hydrator.dressIdent[shell] = { uid = plan.actorUid, seed = plan.appearanceSeed }
            shell:resetModelNextFrame()
        end)
    end
    return ok
end

Hydrator.dressList = setmetatable({}, { __mode = "k" })
Hydrator.dressIdent = setmetatable({}, { __mode = "k" })

function Hydrator.dressSignature(uid, seed, clothing)
    local signature = { tostring(uid), tostring(seed) }
    for _, entry in ipairs(type(clothing) == "table" and clothing or {}) do
        signature[#signature + 1] = tostring(type(entry) == "table" and entry.itemType or entry)
            .. ":" .. tostring(type(entry) == "table" and entry.tint or "")
    end
    return table.concat(signature, "|")
end

function Hydrator.noteDress(shell, plan)
    if shell == nil or type(plan) ~= "table" or type(plan.clothing) ~= "table" then return false end
    Hydrator.dressIdent[shell] = { uid = plan.actorUid, seed = plan.appearanceSeed }
    Hydrator.dressList[shell] = Hydrator.dressSignature(plan.actorUid, plan.appearanceSeed, plan.clothing)
    return true
end

Hydrator.maxExtraItems = 24

function Hydrator.addExtraItems(inventory, extra)
    if inventory == nil or type(extra) ~= "table" then return 0 end
    local added = 0
    for _, row in ipairs(extra) do
        local itemType = type(row) == "table" and row.itemType or row
        local count = type(row) == "table" and math.floor(tonumber(row.count) or 1) or 1
        if type(itemType) == "string" and itemType ~= "" and Hydrator.itemKnown(itemType) then
            for _ = 1, math.max(1, math.min(count, 4)) do
                if added >= Hydrator.maxExtraItems then return added end
                local ok, item = pcall(function() return inventory:AddItem(itemType) end)
                if ok and item ~= nil then
                    added = added + 1
                    pcall(function() item:getModData().ProjectALifeCarried = true end)
                else
                    Hydrator.metrics.extraFailed = (Hydrator.metrics.extraFailed or 0) + 1
                end
            end
        end
    end
    return added
end

function Hydrator.itemList(inventory)
    local rows = {}
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or items == nil or type(items.size) ~= "function" or type(items.get) ~= "function" then return rows end
    for index = 0, math.min(items:size(), 256) - 1 do
        local got, item = pcall(items.get, items, index)
        if got and item ~= nil then rows[#rows + 1] = item end
    end
    return rows
end

function Hydrator.authoredClothing(item)
    local ok, flagged = pcall(function() return item:getModData().ProjectALifeAuthoredClothing == true end)
    return ok and flagged == true
end

function Hydrator.reuseClothing(rows, used, itemType)
    local spare = nil
    for _, item in ipairs(rows) do
        if not used[item] then
            local ok, full = pcall(function() return item:getFullType() end)
            if ok and full == itemType then
                if Hydrator.authoredClothing(item) then return item end
                spare = spare or item
            end
        end
    end
    return spare
end

function Hydrator.redress(shell, entries, ident)
    if shell == nil or type(entries) ~= "table" or #entries == 0 then return false, "empty_dress" end
    ident = type(ident) == "table" and ident or Hydrator.dressIdent[shell]
    if ident == nil then return false, "identity_unknown" end
    if type(instanceItem) ~= "function" then return false, "item_factory_unavailable" end
    local invOk, inventory = pcall(function() return shell:getInventory() end)
    local visOk, worn = pcall(function() return shell:getItemVisuals() end)
    if not invOk or inventory == nil or not visOk or worn == nil then return false, "body_unavailable" end
    local rows, used, planned = Hydrator.itemList(inventory), {}, {}
    local seed = ident.seed or ident.uid
    for _, entry in ipairs(entries) do
        local itemType = type(entry) == "table" and entry.itemType or entry
        local item = Hydrator.reuseClothing(rows, used, itemType)
        local created = false
        if item == nil then
            local made, fresh = pcall(instanceItem, itemType)
            item, created = made and fresh or nil, true
        end
        local visual = item ~= nil and Hydrator.prepareClothing(item,
            type(entry) == "table" and entry or { itemType = itemType }, seed) or nil
        if visual == nil then
            Hydrator.metrics.redressFailed = (Hydrator.metrics.redressFailed or 0) + 1
            return false, "visual_failed:" .. tostring(itemType)
        end
        used[item] = true
        planned[#planned + 1] = { item = item, visual = visual, created = created, entry = entry }
    end
    for _, item in ipairs(rows) do
        if not used[item] and Hydrator.authoredClothing(item) then pcall(function() inventory:Remove(item) end) end
    end
    pcall(function() worn:clear() end)
    local wearing = Hydrator.wearsGarments()
    if wearing and type(shell.clearWornItems) == "function" then pcall(shell.clearWornItems, shell) end
    local types, tints = {}, {}
    for _, row in ipairs(planned) do
        if row.created then pcall(function() inventory:AddItem(row.item) end) end
        pcall(function()
            local data = row.item:getModData()
            data.ProjectALifeAuthoredClothing = true
            data.ProjectALifeClothingSlot = type(row.entry) == "table" and row.entry.slot or nil
        end)
        worn:add(row.visual)
        if wearing then Hydrator.wear(shell, row.item) end
        types[#types + 1] = type(row.entry) == "table" and row.entry.itemType or row.entry
        tints[#tints + 1] = type(row.entry) == "table" and row.entry.tint or ""
    end
    local signature = Hydrator.dressSignature(ident.uid, ident.seed, entries)
    Hydrator.dressed[shell] = signature
    Hydrator.dressList[shell] = signature
    Hydrator.dressIdent[shell] = ident
    pcall(function()
        local data = shell:getModData()
        data.ProjectALifeClothingTypes, data.ProjectALifeClothingTints = types, tints
    end)
    pcall(function() shell:onWornItemsChanged() end)
    pcall(function() shell:resetModelNextFrame() end)
    Hydrator.metrics.redressed = (Hydrator.metrics.redressed or 0) + 1
    return true
end

Hydrator.wardrobe = {
    checkHours = 1, retryHours = 0.25, minGapHours = 6, watchTiles = 12, closeTiles = 5,
    worn = setmetatable({}, { __mode = "k" }),
    busyKinds = { combat = true, retreat = true, recovering = true },
    stats = { swaps = 0, skippedCombat = 0, pinned = 0, watched = 0, gap = 0, same = 0, failed = 0, checks = 0,
        nightKept = 0 },
}

function Hydrator.clothingAs(actor, season)
    Hydrator.seasonForced = season
    local ok, plan = pcall(Hydrator.plan, actor)
    Hydrator.seasonForced = nil
    if not ok or type(plan) ~= "table" or type(plan.clothing) ~= "table" then return nil end
    return plan.clothing, plan
end

function Hydrator.outerWarmth(entries)
    local wear, score = Hydrator.seasonWear, 0
    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        if Hydrator.wearHas(entry.itemType, wear.outer) ~= nil then
            score = math.max(score, Hydrator.wearHas(entry.itemType, wear.heavy) ~= nil and 2 or 1)
        end
    end
    return score
end

function Hydrator.wardrobePinned(actor)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.dress ~= nil or memory.person ~= nil or memory.outfitPinned == true then return true end
    local profile = Catalog.npc(actor.profileId)
    if type(profile) ~= "table" then return false end
    return profile.outfitPinned == true
        or (type(profile.general) == "table" and profile.general.outfitPinned == true)
end

function Hydrator.wardrobeBusy(actor, state, now)
    if type(state) == "table" and (Hydrator.wardrobe.busyKinds[state.kind] == true or state.intent == "talk_hold") then
        return true
    end
    local first = ProjectALife.FirstDays
    return first ~= nil and type(first.busy) == "function" and first.busy(actor, now) == true
end

function Hydrator.wardrobeSeen(shell)
    local W, locator = Hydrator.wardrobe, ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return false end
    local x, y, z = shell:getX(), shell:getY(), shell:getZ()
    local indoors = type(shell.isOutside) == "function" and shell:isOutside() == false
    local reach = indoors and W.closeTiles or W.watchTiles
    for _, player in ipairs(locator.list()) do
        if type(player.isDead) ~= "function" or player:isDead() ~= true then
            local dx, dy = player:getX() - x, player:getY() - y
            if math.abs(player:getZ() - z) <= 1 and dx * dx + dy * dy <= reach * reach then return true end
        end
    end
    return false
end

function Hydrator.wardrobeWatched(shell)
    local ok, seen = pcall(Hydrator.wardrobeSeen, shell)
    return not ok or seen == true
end

function Hydrator.noteWorn(shell, actor)
    local seasons = ProjectALife.Seasons
    local hours = seasons ~= nil and seasons.gameHours() or nil
    if shell == nil or hours == nil or type(actor) ~= "table" then return false end
    local W = Hydrator.wardrobe
    W.worn[shell] = { season = Hydrator.seasonFor(actor), since = hours,
        due = hours + stableIndex(tostring(actor.uid), 60) / 60 }
    return true
end

Hydrator.visitDressed = setmetatable({}, { __mode = "k" })

function Hydrator.visitDress(actor, shell)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" or memory.person ~= nil or type(memory.visit) ~= "table" or shell == nil then return false end
    local event = memory.visit.event
    local outfits = ProjectALife.VisitOutfits
    if event == nil or Hydrator.visitDressed[shell] == event then return false end
    if outfits == nil or outfits.row(event) == nil then
        Hydrator.visitDressed[shell] = event
        return false
    end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.drivesBody) == "function" and fence.drivesBody(shell) ~= true then return false end
    local ident = Hydrator.dressIdent[shell]
    if ident == nil then return false end
    Hydrator.visitDressed[shell] = event
    local plan = Hydrator.plan(actor)
    if type(plan) ~= "table" or type(plan.clothing) ~= "table" or #plan.clothing == 0 then return false end
    if Hydrator.dressList[shell] ~= Hydrator.dressSignature(ident.uid, ident.seed, plan.clothing) then
        if Hydrator.redress(shell, plan.clothing, ident) ~= true then return false end
    end
    local carry = outfits.itemsOf(event)
    if #carry > 0 then
        local opened, inventory = pcall(function() return shell:getInventory() end)
        if opened and inventory ~= nil then Hydrator.addExtraItems(inventory, carry) end
    end
    return true
end

function Hydrator.wardrobeTick(actor, shell, state, now)
    local W, seasons = Hydrator.wardrobe, ProjectALife.Seasons
    Hydrator.visitDress(actor, shell)
    if shell == nil or type(actor) ~= "table" or seasons == nil then return false end
    local hours = seasons.gameHours()
    if hours == nil then return false end
    local row = W.worn[shell]
    if row == nil then
        W.worn[shell] = { since = hours - W.minGapHours, due = hours + stableIndex(tostring(actor.uid), 60) / 60 }
        return false
    end
    if hours < row.due and row.due - hours <= W.checkHours + 1 then return false end
    row.due = hours + W.checkHours
    if Hydrator.worldSetting("seasonalDress", "Loadouts_SeasonalDress") == false then return false end
    local stats = W.stats
    stats.checks = stats.checks + 1
    if Hydrator.wardrobePinned(actor) then
        stats.pinned = stats.pinned + 1
        return false
    end
    local target, info = Hydrator.wardrobeSeason(actor)
    if info.source == "calendar" then return false end
    if row.season == nil then
        row.season = target
        return false
    end
    local desired, candidate = target, nil
    if info.nightSeason ~= nil and seasons.isNight() then
        if row.season == info.nightSeason then
            desired = row.season
            stats.nightKept = stats.nightKept + 1
        elseif row.nightNo ~= info.nightSeason .. ":" .. target then
            candidate = info.nightSeason
        end
    end
    if candidate == nil and desired == row.season then return false end
    if hours - row.since < W.minGapHours then
        stats.gap = stats.gap + 1
        return false
    end
    if Hydrator.wardrobeBusy(actor, state, now) then
        stats.skippedCombat = stats.skippedCombat + 1
        row.due = hours + W.retryHours
        return false
    end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.drivesBody) == "function" and fence.drivesBody(shell) ~= true then return false end
    if Hydrator.wardrobeWatched(shell) then
        stats.watched = stats.watched + 1
        row.due = hours + W.retryHours
        return false
    end
    if candidate ~= nil then
        local warm, plain = Hydrator.clothingAs(actor, candidate), Hydrator.clothingAs(actor, target)
        if warm ~= nil and plain ~= nil and Hydrator.outerWarmth(warm) > Hydrator.outerWarmth(plain) then
            desired = candidate
        else
            row.nightNo = candidate .. ":" .. target
        end
        if desired == row.season then return false end
    end
    local entries = Hydrator.clothingAs(actor, desired)
    if entries == nil or #entries == 0 then
        stats.failed = stats.failed + 1
        return false
    end
    local ident = Hydrator.dressIdent[shell]
    if ident ~= nil and Hydrator.dressList[shell] == Hydrator.dressSignature(ident.uid, ident.seed, entries) then
        row.season, row.since = desired, hours
        stats.same = stats.same + 1
        return false
    end
    if Hydrator.redress(shell, entries, ident) ~= true then
        stats.failed = stats.failed + 1
        return false
    end
    row.season, row.since, row.nightNo = desired, hours, nil
    stats.swaps = stats.swaps + 1
    return true
end

function Hydrator.wardrobeLine()
    local season, info = Hydrator.wardrobeSeason({})
    local stats = Hydrator.wardrobe.stats
    local function number(value)
        if type(value) ~= "number" then return "-" end
        return string.format("%.1f", value)
    end
    return "[ALIFE-QA] Wardrobe: season=" .. tostring(season) .. " temp=" .. number(info.temp)
        .. " smoothed=" .. number(info.smoothed) .. " swaps=" .. tostring(stats.swaps)
        .. " skippedCombat=" .. tostring(stats.skippedCombat) .. " pinned=" .. tostring(stats.pinned)
        .. " source=" .. tostring(info.source) .. " band=" .. tostring(info.bandName or "-")
        .. " push=" .. tostring(info.push ~= nil and info.push ~= "" and info.push or "-")
        .. " watched=" .. tostring(stats.watched) .. " gap=" .. tostring(stats.gap)
        .. " same=" .. tostring(stats.same) .. " failed=" .. tostring(stats.failed)
        .. " checks=" .. tostring(stats.checks)
end

local function defaultApply(shell, plan)
    local ok, result = pcall(function()
        local simulation = ProjectALife.ShellSimulation
        local scale = simulation and simulation.healthScale() or 1
        local nativeHealth = math.min(plan.health * scale, scale < 1 and 32 or math.huge)
        if simulation then simulation.setHealth(shell, nativeHealth) else shell:setHealth(nativeHealth) end
        setMetadata(shell, "ALifeHealthScale", nativeHealth / plan.health)
        setMetadata(shell, "ALifeInfiniteAmmo", plan.infiniteAmmo)

        Hydrator.applyAppearance(shell, plan)

        setMetadata(shell, "ALifeFirearmsAuthored", plan.firearmsAuthored ~= false)

        local inventory = shell:getInventory()
        if inventory == nil then return false end

        local cleared = pcall(function() inventory:clear() end)
        if not cleared then
            local inherited = inventory:getItems()
            for index = inherited:size() - 1, 0, -1 do
                inventory:Remove(inherited:get(index))
            end
        end
        pcall(function() ProjectALife.DeathInventory.clear(shell) end)

        local wearing = Hydrator.wearsGarments()
        if wearing and type(shell.clearWornItems) == "function" then
            pcall(shell.clearWornItems, shell)
        end
        local loadoutErrors = 0
        local clothingVisuals = {}
        for _, entry in ipairs(plan.clothing) do
            if type(entry.itemType) == "string" and entry.itemType ~= "" then
                local addedOk, item = pcall(function() return inventory:AddItem(entry.itemType) end)
                if addedOk and item ~= nil then
                    local itemDataOk, itemData = pcall(function() return item:getModData() end)
                    if itemDataOk and type(itemData) == "table" then
                        itemData.ProjectALifeAuthoredClothing = true
                        itemData.ProjectALifeClothingSlot = entry.slot
                    end
                    Hydrator.issueCondition(item, plan.drop.armorCondition)
                    local visualOk, itemVisual = pcall(function() return item:getVisual() end)
                    if visualOk and itemVisual ~= nil then
                        Hydrator.prepareClothing(item, entry, plan.appearanceSeed or plan.actorUid)
                        clothingVisuals[#clothingVisuals + 1] = itemVisual

                        if wearing then Hydrator.wear(shell, item) end
                    else
                        loadoutErrors = loadoutErrors + 1
                    end
                else
                    loadoutErrors = loadoutErrors + 1
                end
            end
        end
        local wornOk, worn = pcall(function() return shell:getItemVisuals() end)
        if wornOk and worn ~= nil then
            worn:clear()
            for _, itemVisual in ipairs(clothingVisuals) do worn:add(itemVisual) end
        else
            loadoutErrors = loadoutErrors + #clothingVisuals
        end
        Hydrator.noteDress(shell, plan)
        Hydrator.addExtraItems(inventory, plan.extraItems)

        local conduct
        pcall(function() conduct = shell:getModData().ProjectALifeConduct end)
        local kitRoll = type(ZombRand) == "function" and (ZombRand(1000) / 1000) or 0.5
        for _, entry in ipairs(Hydrator.medicalKitFor(conduct, plan.profession, kitRoll)) do
            for _ = 1, entry.count do
                if entry.itemType == "Base.Bandage" then
                    pcall(function() inventory:AddItem("Base.Bandage") end)
                else
                    pcall(function() inventory:AddItem(entry.itemType) end)
                end
            end
        end

        local equipped, equippedType, equippedSlot = nil, nil, nil
        local issued = {}

        local reserves = { primary = 0, secondary = 0 }
        for _, slot in ipairs({ "primary", "secondary", "melee" }) do
            local itemType = plan.weapons[slot]
            if type(itemType) == "string" and itemType ~= "" then
                local addedOk, item = pcall(function() return inventory:AddItem(itemType) end)
                local weaponOk, weapon = pcall(function() return item and item:IsWeapon() end)
                if addedOk and item ~= nil and weaponOk and weapon == true then
                    local attachmentPool = plan.weaponAttachments
                        and plan.weaponAttachments[itemType] or ""
                    for partType in string.gmatch(tostring(attachmentPool) .. "|", "(.-)|") do
                        if partType ~= "" then
                            local attachedOk = pcall(function()
                                local part = instanceItem(partType)
                                if part ~= nil then item:attachWeaponPart(part, true) end
                            end)
                            if not attachedOk then loadoutErrors = loadoutErrors + 1 end
                        end
                    end
                    local itemDataOk, itemData = pcall(function() return item:getModData() end)
                    if itemDataOk and type(itemData) == "table" then
                        itemData.ProjectALifeWeaponSlot = slot
                    end
                    Hydrator.issueCondition(item, plan.drop.weaponCondition)
                    if slot == "primary" or slot == "secondary" then
                        local loaded, remaining = Magazines.initialize(shell, item, slot,
                            plan.ammo[slot], plan.ammoMode
                                and plan.ammoMode[slot] or "rounds")
                        if type(Magazines.maximum) ~= "function" or Magazines.maximum(item) > 0 then
                            reserves[slot] = remaining
                        end
                        if plan.ammo[slot] > 0 and not loaded then
                            loadoutErrors = loadoutErrors + 1
                        end
                    end
                    if slot == "primary" or equipped == nil then
                        equipped, equippedType, equippedSlot = item, itemType, slot
                    end
                    issued[#issued + 1] =
                        { item = item, itemType = itemType, slot = slot }
                    pcall(function() ProjectALife.DeathInventory.add(shell, item) end)
                else
                    if addedOk and item ~= nil then pcall(function() inventory:Remove(item) end) end
                    loadoutErrors = loadoutErrors + 1
                end
            end
        end

        local function issuedRank(entry)
            local firearm = false
            pcall(function() firearm = entry.item:isAimedFirearm() == true end)
            if not firearm then
                pcall(function() firearm = entry.item:isRanged() == true end)
            end
            if not firearm then

                firearm = entry.slot == "primary" or entry.slot == "secondary"
            end
            if not firearm then return 1 end
            return entry.slot == "primary" and 3 or 2
        end
        local bestEntry, bestRank
        for _, entry in ipairs(issued) do
            local rank = issuedRank(entry)
            if bestRank == nil or rank > bestRank then
                bestEntry, bestRank = entry, rank
            end
        end
        if bestEntry ~= nil then
            equipped, equippedType, equippedSlot =
                bestEntry.item, bestEntry.itemType, bestEntry.slot
        end
        if equipped ~= nil then Weapons.select(shell, equipped, equippedSlot) end

        local carryClass = "melee"
        local lowered = string.lower(equippedType or "")

        local classified = false
        pcall(function()
            if equipped == nil then return end
            local firearm = equipped:isAimedFirearm() == true
            if not firearm then
                firearm = equipped:isRanged() == true
                    or (tonumber(equipped:getMaxAmmo()) or 0) > 0
            end
            if not firearm then return end
            local twoHanded = false
            pcall(function()
                twoHanded = tostring(equipped:getWeaponSprite() or ""):len() >= 0
                    and equipped:isTwoHandWeapon() == true
            end)
            carryClass = twoHanded and "rifle" or "handgun"
            classified = true
        end)
        if not classified then
            if string.find(lowered, "pistol", 1, true) or string.find(lowered, "revolver", 1, true) then
                carryClass = "handgun"
            elseif string.find(lowered, "rifle", 1, true) or string.find(lowered, "shotgun", 1, true) then
                carryClass = "rifle"
            elseif string.find(lowered, "spear", 1, true) then
                carryClass = "spear"
            end
        end

        setMetadata(shell, "ALifeVoiceProfile", plan.voiceProfile)
        setMetadata(shell, "ALifeFemale", plan.female)
        setMetadata(shell, "ALifeSkin", plan.skin)
        setMetadata(shell, "ALifeSkinTexture", plan.skinTexture)
        setMetadata(shell, "ALifeLookMode", plan.lookMode or "legacy")
        setMetadata(shell, "ALifeHairStyle", plan.hairStyle)
        setMetadata(shell, "ALifeHairColor", plan.hairColor)
        setMetadata(shell, "ALifeBeardStyle", plan.beardStyle)
        setMetadata(shell, "ALifeBeardColor", plan.beardColor)
        setMetadata(shell, "ALifeMaximumHealth", nativeHealth)
        setMetadata(shell, "ALifeHealthRating", plan.healthRating)
        setMetadata(shell, "ALifeNpcHealthScale", tonumber(plan.npcHealthScale) or 1)
        setMetadata(shell, "ALifeDamageReduction", plan.damageReduction)
        setMetadata(shell, "ALifeDamageOutput", plan.damageOutput)
        setMetadata(shell, "ALifeStrength", plan.strength)
        setMetadata(shell, "ALifeEndurance", plan.endurance)
        setMetadata(shell, "ALifeAwareness", plan.awareness)
        setMetadata(shell, "ALifeAiming", plan.aiming)
        setMetadata(shell, "ALifeInfiniteAmmo", plan.infiniteAmmo)
        setMetadata(shell, "ALifeSupportCaller", plan.supportCaller)
        setMetadata(shell, "ALifePrimaryAmmoUnits", reserves.primary)
        setMetadata(shell, "ALifeSecondaryAmmoUnits", reserves.secondary)
        setMetadata(shell, "ALifeEquippedSlot", equippedSlot or "none")
        if type(Animations.armsOf) == "function" then
            setVariable(shell, "ALifeArms", Animations.armsOf(carryClass))
        end
        pcall(function() shell:getModData().ProjectALifeWeaponClass = carryClass end)
        setMetadata(shell, "ALifeLoadoutErrors", loadoutErrors)
        setMetadata(shell, "ALifeDropWeapon", plan.drop.weapon)
        setMetadata(shell, "ALifeDropWeaponChance", plan.drop.weaponChance)
        setMetadata(shell, "ALifeDropAmmo", plan.drop.ammo)
        setMetadata(shell, "ALifeDropArmorChance", plan.drop.armorChance)
        setMetadata(shell, "ALifeCombatReadyMode", plan.combatReadyMode)
        local dataOk, data = pcall(function() return shell:getModData() end)
        if dataOk and type(data) == "table" then

            data.ProjectALifeAiming = tonumber(plan.aiming)
            data.ProjectALifeAimPlayerPercent = tonumber(plan.aimPlayerPercent)
            data.ProjectALifeAimZombiePercent = tonumber(plan.aimZombiePercent)
            data.ProjectALifeClothingTypes = {}
            data.ProjectALifeClothingTints = {}
            data.ProjectALifeAppearanceSeed = plan.appearanceSeed or plan.actorUid
            for _, entry in ipairs(plan.clothing) do
                data.ProjectALifeClothingTypes[#data.ProjectALifeClothingTypes + 1] =
                    entry.itemType
                data.ProjectALifeClothingTints[#data.ProjectALifeClothingTints + 1] = entry.tint or ""
            end
        end
        local weaponVisualReady = equipped == nil
        if equipped ~= nil then
            weaponVisualReady = Animations.presentWeapon(
                shell, equipped, equippedType, carryClass, false) == true
            local rangedCarry = carryClass == "handgun" or carryClass == "rifle"
            Animations.setReadyCarry(shell, rangedCarry and plan.combatReady == true)
        end
        setMetadata(shell, "ALifeWeaponVisualReady", weaponVisualReady)
        if loadoutErrors > 0 and type(Hydrator.adapters.emit) == "function" then
            pcall(Hydrator.adapters.emit, "loadout_errors", {
                uid = plan.actorUid,
                profileId = plan.profileId,
                errors = loadoutErrors,
            })
        end
        pcall(function() shell:onWornItemsChanged() end)
        pcall(function() shell:resetModelNextFrame() end)
        return true
    end)
    return ok and result == true
end

function Hydrator.apply(shell, plan)
    if type(Hydrator.adapters.apply) == "function" then
        local ok, result = pcall(Hydrator.adapters.apply, shell, plan)
        return ok and result == true
    end
    return defaultApply(shell, plan)
end

function Hydrator.hydrate(shell, actor)
    local plan, planError = Hydrator.plan(actor)
    if plan == nil then return false, planError end
    if not Hydrator.apply(shell, plan) then return false, "profile_apply_failed" end
    if ProjectALife.Appearance ~= nil then ProjectALife.Appearance.note(plan) end
    Hydrator.noteWorn(shell, actor)
    local checkpoint = actor.memory and actor.memory.shellState or nil
    if actor.memory and actor.memory.squadId and type(checkpoint) == "table"
            and checkpoint.maximumHealth == nil and checkpoint.reserve == nil
            and type(checkpoint.weapons) == "table" and #checkpoint.weapons == 0 then

        checkpoint = { version = 1, health = checkpoint.health, maximumHealth = 100 }
    end
    local restored, stateResult = ShellState.apply(shell, checkpoint)
    if not restored then return false, stateResult end

    setMetadata(shell, "ALifeInfiniteAmmo", plan.infiniteAmmo)
    setMetadata(shell, "ALifeStateErrors", tonumber(stateResult) or 0)

    local identityReady = Hydrator.ensureIdentityCard(shell, plan)
    setMetadata(shell, "ALifeIdentityCardReady", identityReady == true)
    local pocketReady, pocketCount = Hydrator.ensurePocketLoot(shell, plan)
    setMetadata(shell, "ALifePocketLootReady", pocketReady == true)
    setMetadata(shell, "ALifePocketLootCount", tonumber(pocketCount) or 0)
    local visit = actor.memory and actor.memory.visit
    if actor.memory and (actor.memory.traderStock ~= nil or (type(visit) == "table" and visit.event == "trader")) then
        local dataOk, data = pcall(function() return shell:getModData() end)
        if not dataOk or type(data) ~= "table" then return false, "trader_inventory_unavailable" end
        data.ProjectALifeTraderRevision, data.ProjectALifeTraderStates = nil, nil
        local ready, reason = Hydrator.ensureTraderStock(shell, actor)
        if not ready then return false, reason end
    end

    Animations.refreshWeapon(shell, Animations.readyCarry[shell] == true)
    Animations.syncPresentation(shell)
    return true, plan
end

return Hydrator
