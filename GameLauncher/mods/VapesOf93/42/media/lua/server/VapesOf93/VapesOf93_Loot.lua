-- Vapes of '93 loot.
-- Every number below is a "chance" in the same unit as the vanilla loot tables (the number next to an item in
-- ProceduralDistributions, e.g. 8 for cigarettes in a desk). It applies to EACH of the four vape categories:
-- empty refillable pens, pens already filled with juice, vape juice boxes and THC vapes. The chance of a category
-- is split between the items inside it (the 13 juice flavours share it, the 3 THC strains share it, ...).
local CHANCE_SMALL       = 10   -- desks, kitchen counters, lockers/wardrobes
local CHANCE_GLOVEBOX    = 2   -- vehicle glove boxes (the small compartment in the dashboard)
local CHANCE_GAS_CRATE   = 10   -- crates in gas stations
local CHANCE_SHOP_SHELF  = 10   -- shelves, counters and display cases in convenience stores and gas stations
-- No vapes at all in: grocery stores / food markets and bars. No vapes on food shelves or magazine racks
-- in gas stations and convenience stores.

-- Fine tuning per category (1.0 = use the chance above as it is)
local SCALE_EMPTY_PEN     = 1.0   -- Refillable Vape Pen (Empty)
local SCALE_FLAVOURED_PEN = 1.0   -- pens already filled with juice
local SCALE_JUICE         = 1.0   -- Vape Juice boxes
local SCALE_THC           = 1.0   -- THC vapes

local ZOMBIE_CHANCE      = 5     -- % chance a killed zombie carries a vape product

-- { item, weight }
local POOL = {
    { "VapesOf93.VapePen", 70 },
    { "VapesOf93.VapePen_Mango", 2 },
    { "VapesOf93.VapePen_Strawberry", 2 },
    { "VapesOf93.VapePen_KiwiPassionGuava", 2 },
    { "VapesOf93.VapePen_Banana", 2 },
    { "VapesOf93.VapePen_BlueRazz", 2 },
    { "VapesOf93.VapePen_Blueberry", 2 },
    { "VapesOf93.VapePen_Watermelon", 2 },
    { "VapesOf93.VapePen_Grape", 2 },
    { "VapesOf93.VapePen_Peach", 2 },
    { "VapesOf93.VapePen_Pineapple", 2 },
    { "VapesOf93.VapePen_CottonCandy", 2 },
    { "VapesOf93.VapePen_Mint", 2 },
    { "VapesOf93.VapePen_Menthol", 2 },
    { "VapesOf93.VapePen_Tobacco", 2 },
    { "VapesOf93.Juice_Mango", 1 },
    { "VapesOf93.Juice_Strawberry", 1 },
    { "VapesOf93.Juice_KiwiPassionGuava", 1 },
    { "VapesOf93.Juice_Banana", 1 },
    { "VapesOf93.Juice_BlueRazz", 1 },
    { "VapesOf93.Juice_Blueberry", 1 },
    { "VapesOf93.Juice_Watermelon", 1 },
    { "VapesOf93.Juice_Grape", 1 },
    { "VapesOf93.Juice_Peach", 1 },
    { "VapesOf93.Juice_Pineapple", 1 },
    { "VapesOf93.Juice_CottonCandy", 1 },
    { "VapesOf93.Juice_Mint", 1 },
    { "VapesOf93.Juice_Menthol", 1 },
    { "VapesOf93.Juice_Tobacco", 1 },
    { "VapesOf93.THCVape_Sativa", 5 },
    { "VapesOf93.THCVape_Indica", 5 },
    { "VapesOf93.THCVape_Hybrid", 5 },
}
local TOTAL = 0
for _, e in ipairs(POOL) do TOTAL = TOTAL + e[2] end

local function pick()
    local r = ZombRand(TOTAL)
    for _, e in ipairs(POOL) do
        r = r - e[2]
        if r < 0 then return e[1] end
    end
    return POOL[1][1]
end

local function spawn(fullType, container)
    if ItemSpawner and ItemSpawner.spawnItem then
        if pcall(ItemSpawner.spawnItem, fullType, container, false) then return end
    end
    pcall(function() container:AddItem(fullType) end)
end

-- Distribution patching -----------------------------------------------------------------------
local function lower(s) return tostring(s or ""):lower() end

local function categoryOf(fullType)
    local n = fullType:gsub("^VapesOf93%.", "")
    if n == "VapePen" then return "empty", SCALE_EMPTY_PEN end
    if n:find("^VapePen_") then return "pen", SCALE_FLAVOURED_PEN end
    if n:find("^Juice_") then return "juice", SCALE_JUICE end
    if n:find("^THCVape_") then return "thc", SCALE_THC end
    return "other", 1.0
end

-- share of every item inside its category (the shares of a category add up to 1)
local CATEGORY_SHARE = {}
do
    local sums = {}
    for _, e in ipairs(POOL) do
        local cat = categoryOf(e[1])
        sums[cat] = (sums[cat] or 0) + e[2]
    end
    for _, e in ipairs(POOL) do
        local cat = categoryOf(e[1])
        CATEGORY_SHARE[e[1]] = e[2] / sums[cat]
    end
end

local BAR_ROOMS = { bar = true, barkitchen = true, barstorage = true }

-- Grocery stores / food markets and bars never get vapes (any container)
local function isNoVapeRoom(room)
    local r = lower(room)
    return r:find("grocery", 1, true) ~= nil or r:find("market", 1, true) ~= nil or BAR_ROOMS[r] == true
end

-- Which chance applies to this room / container? (nil = no vapes here)
local function chanceFor(room, cont)
    local r, c = lower(room), lower(cont)
    if isNoVapeRoom(room) then return nil end
    local gas = r:find("gas", 1, true) ~= nil
    local shop = gas or r:find("convenience", 1, true) ~= nil
    if c == "desk" or c == "locker" then return CHANCE_SMALL end
    if c == "wardrobe" and (r == "mechanic" or r == "prisoncells") then return CHANCE_SMALL end
    if c == "counter" then
        if r == "kitchen" then return CHANCE_SMALL end
        if shop then return CHANCE_SHOP_SHELF end
    end
    if c == "crate" then
        if gas then return CHANCE_GAS_CRATE end
    end
    if shop and (c:find("shel", 1, true) or c == "displaycase") then return CHANCE_SHOP_SHELF end
    return nil
end

local patchedCount, patchedNames = 0, {}

local function hasVapes(items)
    for i = 1, #items - 1, 2 do
        if type(items[i]) == "string" and items[i]:find("^VapesOf93%.") then return true end
    end
    return false
end

-- items = flat list { "Module.Item", weight, "Module.Item", weight, ... }
local function addVapes(items, chance)
    if hasVapes(items) then return false end
    for _, e in ipairs(POOL) do
        local _, scale = categoryOf(e[1])
        local w = chance * scale * CATEGORY_SHARE[e[1]]
        w = math.floor(w * 1000 + 0.5) / 1000
        if w < 0.001 then w = 0.001 end
        table.insert(items, e[1])
        table.insert(items, w)
    end
    return true
end

local function note(label)
    patchedCount = patchedCount + 1
    patchedNames[#patchedNames + 1] = label
end

local function deepCopy(t, depth)
    if type(t) ~= "table" or depth > 4 then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v, depth + 1) end
    return c
end

-- Procedural lists are shared between many containers, so a private copy (with the vapes added) is made for
-- each container that needs one: vapes only appear where they are meant to, not in every container that
-- happens to use the same vanilla list.
local function cloneList(name, chance)
    local proc = ProceduralDistributions and ProceduralDistributions.list
    if not proc or not name then return nil end
    if tostring(name):find("_V93_", 1, true) then return name end
    local newName = tostring(name) .. "_V93_" .. tostring(chance)
    if proc[newName] then return newName end
    local src = proc[name]
    if type(src) ~= "table" or type(src.items) ~= "table" then return nil end
    local copy = deepCopy(src, 0)
    if not addVapes(copy.items, chance) then return nil end
    proc[newName] = copy
    return newName
end

-- Gas stations and convenience stores: NO vapes on food shelves or magazine racks ---------------------------------------------
-- A list is skipped when its name contains one of these words, or when most of its items are food / magazines.
local SKIP_NAME_TOKENS = { "magazine", "newspaper", "snack", "food", "drink", "beverage", "candy", "chocolate",
                           "cereal", "canned", "tinned", "bread", "fridge", "freezer", "soda", "produce" }

local function isCigaretteName(name)
    return type(name) == "string" and name:lower():find("cigarette", 1, true) ~= nil
end

-- Item type ("Food", "Literature", ...) from the item scripts, or nil if the game cannot tell yet.
local function itemTypeName(fullType)
    local sm = (getScriptManager and getScriptManager()) or nil
    if not sm then return nil end
    local ok, it = pcall(function() return sm:FindItem(fullType) end)
    if not ok or not it then return nil end
    local ok2, t = pcall(function() return it:getType() end)
    if ok2 and t then return tostring(t) end
    return nil
end

local function isFoodOrMagazineList(listName, items)
    local n = lower(listName)
    for _, tok in ipairs(SKIP_NAME_TOKENS) do
        if n:find(tok, 1, true) then return true end
    end
    local total, food, mag = 0, 0, 0
    for i = 1, #items - 1, 2 do
        local name = items[i]
        if type(name) == "string" and not name:find("^VapesOf93%.") then
            total = total + 1
            local l = name:lower()
            if l:find("magazine", 1, true) or l:find("newspaper", 1, true) then
                mag = mag + 1
            elseif not isCigaretteName(name) then
                local t = itemTypeName(name)
                if t == "Food" then food = food + 1
                elseif t == "Literature" then mag = mag + 1 end
            end
        end
    end
    if total == 0 then return false end
    return (mag / total) >= 0.25 or (food >= 3 and (food / total) >= 0.5)
end

local skippedNames, skippedSet = {}, {}
local function skip(name)
    if not skippedSet[name] then
        skippedSet[name] = true
        skippedNames[#skippedNames + 1] = name
    end
end

-- Desks and lockers use the game-wide "all" lists unless a room defines its own. So that grocery stores / food
-- markets and bars stay completely free of vapes, they get a clean copy (made before the vapes are added).
local cleanAll = nil
local function captureCleanAll(sub)
    if cleanAll then return end
    cleanAll = {}
    local a = sub["all"]
    if type(a) ~= "table" then return end
    for _, cname in ipairs({ "desk", "locker" }) do
        local c = a[cname]
        if type(c) == "table" and not (type(c.items) == "table" and hasVapes(c.items)) then
            cleanAll[cname] = deepCopy(c, 0)
        end
    end
end

local function protectGroceryRooms(sub)
    for room, rt in pairs(sub) do
        if type(rt) == "table" and isNoVapeRoom(room) then
            for cname, copy in pairs(cleanAll) do
                if rt[cname] == nil then rt[cname] = deepCopy(copy, 0) end
            end
        end
    end
end

local function patchSuburbs()
    local sub = SuburbsDistributions
    if type(sub) ~= "table" then return end
    local proc = ProceduralDistributions and ProceduralDistributions.list
    captureCleanAll(sub)
    protectGroceryRooms(sub)
    for room, rt in pairs(sub) do
        if type(rt) == "table" then
            local lr = lower(room)
            local isFoodShop = (lr:find("gas", 1, true) or lr:find("convenience", 1, true)) ~= nil
            for cname, c in pairs(rt) do
                if type(c) == "table" then
                    local chance = chanceFor(room, cname)
                    if chance then
                        local label = tostring(room) .. "/" .. tostring(cname) .. "=" .. tostring(chance)
                        if type(c.items) == "table" then
                            if isFoodShop and isFoodOrMagazineList(label, c.items) then
                                skip(tostring(room) .. "/" .. tostring(cname))
                            elseif addVapes(c.items, chance) then
                                note(label)
                            end
                        end
                        if type(c.procList) == "table" then
                            for _, pr in pairs(c.procList) do
                                if type(pr) == "table" and pr.name then
                                    local src = proc and proc[pr.name] or nil
                                    local srcItems = (type(src) == "table" and type(src.items) == "table") and src.items or {}
                                    if isFoodShop and isFoodOrMagazineList(pr.name, srcItems) then
                                        skip(tostring(pr.name))
                                    else
                                        local nn = cloneList(pr.name, chance)
                                        if nn and nn ~= pr.name then
                                            pr.name = nn
                                            note(label .. "(" .. nn .. ")")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local gloveCount = 0
local function patchVehicles()
    local seen = {}
    local function patchGlove(items, label)
        if type(items) ~= "table" or seen[items] then return end
        seen[items] = true
        if addVapes(items, CHANCE_GLOVEBOX) then
            gloveCount = gloveCount + 1
            note("glovebox/" .. label .. "=" .. tostring(CHANCE_GLOVEBOX))
        end
    end
    local function visit(t, depth)
        if type(t) ~= "table" or seen[t] or depth > 3 then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "table" then
                if type(k) == "string" and k:lower():find("glovebox", 1, true) then
                    patchGlove(v.items, k)
                else
                    visit(v, depth + 1)
                end
            end
        end
    end
    if type(VehicleDistributions) == "table" then visit(VehicleDistributions, 0) end
    local proc = ProceduralDistributions and ProceduralDistributions.list
    if proc then
        for name, v in pairs(proc) do
            if type(name) == "string" and name:lower():find("glovebox", 1, true) and type(v) == "table" then
                patchGlove(v.items, name)
            end
        end
    end
end

local function patchAll()
    patchSuburbs()
    patchVehicles()
    if patchedCount > 0 then
        local shown = {}
        for i = 1, math.min(#patchedNames, 80) do shown[i] = patchedNames[i] end
        print("[VapesOf93] loot: added vapes to " .. patchedCount .. " places: " .. table.concat(shown, ", "))
        if #skippedNames > 0 then
            print("[VapesOf93] loot: skipped food/magazine shelves in gas stations / convenience stores: " .. table.concat(skippedNames, ", "))
        end
    else
        print("[VapesOf93] loot: WARNING - no matching rooms/containers found in the distribution tables, nothing was added")
    end
    print("[VapesOf93] loot: vehicle glove boxes patched: " .. gloveCount)
end

pcall(require, "Items/ProceduralDistributions")
pcall(require, "Items/SuburbsDistributions")
pcall(require, "Vehicles/VehicleDistributions")
patchAll()
if Events.OnPreDistributionMerge then Events.OnPreDistributionMerge.Add(patchAll) end

-- Self check: does the game know every vape item? (result goes to console.txt)
local function checkItems()
    local sm = (getScriptManager and getScriptManager()) or nil
    if not sm then return end
    local missing = {}
    for _, e in ipairs(POOL) do
        local ok, it = pcall(function() return sm:FindItem(e[1]) end)
        if not ok or not it then missing[#missing + 1] = e[1] end
    end
    if #missing == 0 then
        print("[VapesOf93] item check: all " .. #POOL .. " items found")
    else
        print("[VapesOf93] item check: MISSING " .. #missing .. " items: " .. table.concat(missing, ", "))
    end
end
Events.OnGameStart.Add(checkItems)

-- Killed zombies (roll once per zombie; dragging/dropping a corpse re-fires the event)
local function onZombieDead(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    if md.VapesRolled then return end
    md.VapesRolled = true
    if ZombRand(100) >= ZOMBIE_CHANCE then return end
    local inv = zombie:getInventory()
    if inv then spawn(pick(), inv) end
end
Events.OnZombieDead.Add(onZombieDead)
