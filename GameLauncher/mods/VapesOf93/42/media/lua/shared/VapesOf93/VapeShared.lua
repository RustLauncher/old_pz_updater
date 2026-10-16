VapesOf93 = VapesOf93 or {}
VapesOf93OnEat = VapesOf93OnEat or {}

-- Flavor -> small perk category
VapesOf93.FlavorKind = {
    Mango = "fruit",
    Strawberry = "fruit",
    KiwiPassionGuava = "fruit",
    Banana = "fruit",
    BlueRazz = "fruit",
    Blueberry = "fruit",
    Watermelon = "fruit",
    Grape = "fruit",
    Peach = "fruit",
    Pineapple = "fruit",
    CottonCandy = "fruit",
    Mint = "mint",
    Menthol = "mint",
    Tobacco = "tobacco",
}
VapesOf93.FlavorNames = {
    Mango = "Mango",
    Strawberry = "Strawberry",
    KiwiPassionGuava = "Kiwi Passion Fruit Guava",
    Banana = "Banana",
    BlueRazz = "Blue Razz",
    Blueberry = "Blueberry",
    Watermelon = "Watermelon",
    Grape = "Grape",
    Peach = "Peach",
    Pineapple = "Pineapple",
    CottonCandy = "Cotton Candy",
    Mint = "Mint",
    Menthol = "Menthol",
    Tobacco = "Classic Tobacco",
}
VapesOf93.Strains = { "Sativa", "Indica", "Hybrid" }

-- Lines said now and then after a hit (flavors for nicotine vapes, strains for THC)
VapesOf93.Lines = {
    Mango = { "Mmm... sweet mango.", "Tastes like a tropical vacation.", "Mango. Juicy and smooth." },
    Strawberry = { "Strawberry candy in a cloud.", "Tastes like summer strawberries.", "Sweet strawberry. Nice." },
    KiwiPassionGuava = { "Kiwi, passion fruit, guava... what a mix.", "That tropical blend hits just right.", "Tastes like a fruit stand exploded." },
    Banana = { "Banana. Weirdly satisfying.", "Smells like banana bread.", "Creamy banana. Not bad." },
    BlueRazz = { "Blue razz. A classic.", "Tangy blue raspberry.", "Tastes like a blue slushie." },
    Blueberry = { "Blueberry. Smooth.", "Almost like a blueberry muffin.", "Sweet little blueberries." },
    Watermelon = { "Watermelon. Takes me back to picnics.", "Juicy watermelon.", "Tastes like summer." },
    Grape = { "Grape. Tastes like soda pop.", "Sweet grape. Kinda nostalgic.", "Purple and sweet." },
    Peach = { "Peachy.", "Soft peach, sweet and smooth.", "Like peach iced tea." },
    Pineapple = { "Tropical pineapple. Nice.", "Pineapple. Tangy.", "Tastes like a pina colada." },
    CottonCandy = { "Cotton candy. Like the fair.", "A sugary pink cloud.", "Tastes like a carnival." },
    Mint = { "Cool mint. Refreshing.", "Mint. Clears the head.", "Crisp and cool." },
    Menthol = { "Menthol. Ice cold.", "That chill hits the throat.", "Cold and sharp. Good." },
    Tobacco = { "Tastes like the real thing.", "Classic tobacco, no frills.", "Old-school flavor." },
    Sativa = { "Feeling energized and clear.", "My mind's racing in a good way.", "Bright and buzzy." },
    Indica = { "My body's melting into the floor.", "So heavy... so relaxed.", "Couch-lock incoming." },
    Hybrid = { "Perfect balance.", "Mellow but still sharp.", "Smooth ride." },
}
local SAY_CHANCE_NIC = 25   -- percent of hits that get a flavor line
local SAY_CHANCE_THC = 35
local MAX_HIGH, HIGH_PER_HIT = 240, 20

-- every smokable vape item -> its kind
VapesOf93.KIND = {}
for k in pairs(VapesOf93.FlavorKind) do VapesOf93.KIND["VapesOf93.VapePen_" .. k] = "nic" end
for _, k in ipairs(VapesOf93.Strains) do VapesOf93.KIND["VapesOf93.THCVape_" .. k] = "thc" end

-- ======================================================= stats
-- Build 42.13+: Stats:add/remove(CharacterStat.X, value). Amounts below are written for the usual ranges
-- (0..1 for stress/hunger/..., 0..100 for boredom/unhappiness/pain/panic/sickness) and rescaled if the
-- game reports a different range. If the new API is unavailable we fall back to the old getters/setters.
local ALIASES = {
    STRESS      = { "STRESS" },
    BOREDOM     = { "BOREDOM" },
    UNHAPPINESS = { "UNHAPPINESS", "UNHAPPYNESS" },
    PAIN        = { "PAIN" },
    PANIC       = { "PANIC" },
    HUNGER      = { "HUNGER" },
    THIRST      = { "THIRST" },
    FATIGUE     = { "FATIGUE" },
    ENDURANCE   = { "ENDURANCE" },
    FOOD_SICKNESS = { "FOOD_SICKNESS", "SICKNESS" },
}
local DEFAULT_MAX = { STRESS = 1, HUNGER = 1, THIRST = 1, FATIGUE = 1, ENDURANCE = 1,
                      BOREDOM = 100, UNHAPPINESS = 100, PAIN = 100, PANIC = 100, FOOD_SICKNESS = 100 }

local warned = {}
local function resolve(key)
    if not CharacterStat then return nil end
    for _, n in ipairs(ALIASES[key] or { key }) do
        if CharacterStat[n] then return CharacterStat[n] end
    end
    if not warned[key] then
        warned[key] = true
        print("[VapesOf93] CharacterStat." .. key .. " not found in this build; using old stat API for it.")
    end
    return nil
end

local function ratio(e, key)
    local ok, m = pcall(function() return e:getMaximum() end)
    if ok and type(m) == "number" and m > 0 and DEFAULT_MAX[key] then return m / DEFAULT_MAX[key] end
    return 1
end

local function legacyChange(player, key, amount)
    local stats, body = player:getStats(), player:getBodyDamage()
    local map = {
        STRESS = { stats, "Stress", 1 },   HUNGER = { stats, "Hunger", 1 },  THIRST = { stats, "Thirst", 1 },
        FATIGUE = { stats, "Fatigue", 1 }, ENDURANCE = { stats, "Endurance", 1 },
        PAIN = { stats, "Pain", 100 },     PANIC = { stats, "Panic", 100 },
        BOREDOM = { body, "BoredomLevel", 100 }, UNHAPPINESS = { body, "UnhappynessLevel", 100 },
        FOOD_SICKNESS = { body, "FoodSicknessLevel", 100 },
    }
    local m = map[key]
    if not m then return false end
    return (pcall(function()
        local obj, nm, hi = m[1], m[2], m[3]
        local v = obj["get" .. nm](obj) + amount
        if v < 0 then v = 0 elseif v > hi then v = hi end
        obj["set" .. nm](obj, v)
    end))
end

-- amount > 0 raises the stat, amount < 0 lowers it (the game clamps to the stat's range)
function VapesOf93.change(player, key, amount)
    local e = resolve(key)
    if e then
        local scaled = amount * ratio(e, key)
        local ok = pcall(function()
            local stats = player:getStats()
            if scaled >= 0 then stats:add(e, scaled) else stats:remove(e, -scaled) end
        end)
        if ok then return true end
    end
    return legacyChange(player, key, amount)
end
local change = VapesOf93.change

function VapesOf93.read(player, key)
    local e = resolve(key)
    if not e then return nil end
    local ok, v = pcall(function() return player:getStats():get(e) end)
    return ok and v or nil
end

-- ======================================================= a vape hit
local function suffix(fullType) return fullType and fullType:match("_(.+)$") or nil end

local function maybeSay(character, key, chance)
    local list = VapesOf93.Lines[key or ""]
    if not list or ZombRand(100) >= chance then return end
    character:Say(list[ZombRand(#list) + 1])
end

local function gameHours()
    local ok, h = pcall(function() return getGameTime():getWorldAgeHours() end)
    return ok and h or nil
end

-- Called after the vanilla smoke action has run. (fullType, character[, stress value from before the hit])
-- Several hooks can call this for the same hit; the game-time guard makes sure it only counts once.
function VapesOf93.afterHit(fullType, character, stressBefore)
    local kind = VapesOf93.KIND[fullType or ""]
    if not kind or not character then return end
    local md = character:getModData()
    local h = gameHours()
    if h then
        if md.VapeLastHitH and math.abs(h - md.VapeLastHitH) < 0.003 then return end
        md.VapeLastHitH = h
    end
    local key = suffix(fullType)

    if kind == "nic" then
        -- stress relief / withdrawal / cough are done by vanilla's nicotine handler; we add the flavor perk
        local perk = VapesOf93.FlavorKind[key or ""]
        if perk == "fruit" then
            change(character, "UNHAPPINESS", -3)           -- tastes nice
        elseif perk == "mint" then
            change(character, "ENDURANCE", 0.05)           -- cool and refreshing
            change(character, "THIRST", -0.01)
        elseif perk == "tobacco" then
            change(character, "STRESS", -0.03)             -- the real-deal feel
        end
        maybeSay(character, key, SAY_CHANCE_NIC)
    else
        -- THC: instant relief (depression & anxiety) plus a high that keeps working (see VapeHigh.lua)
        local strain = key or "Hybrid"
        md.VapeHigh = math.min((md.VapeHigh or 0) + HIGH_PER_HIT, MAX_HIGH)
        md.VapeStrain = strain
        change(character, "STRESS", -0.15)
        change(character, "UNHAPPINESS", -30)
        change(character, "BOREDOM", -15)
        change(character, "PANIC", -25)
        maybeSay(character, strain, SAY_CHANCE_THC)
    end
    print(string.format("[VapesOf93] hit %s: stress %s -> %s", tostring(fullType),
          tostring(stressBefore), tostring(VapesOf93.read(character, "STRESS"))))
end

-- THC items also route through their own OnEat (guarded above, so a hit is never counted twice)
function VapesOf93OnEat.thc(item, character, percent)
    local ok, t = pcall(function() return item:getFullType() end)
    if ok and t then VapesOf93.afterHit(t, character) end
end
