require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Records/ALifeDropPolicy"

ProjectALife = ProjectALife or {}

local Wear = {
    option = "Loot_NpcWearPercent",
    default = 100,
    debugPristine = false,
    skew = 1.5,
    ammo = { magazine = 0.25, internal = 0.30, reserve = 0.25 },
    tiers = {
        firearm = {
            { "broken", 15, 0, 0 }, { "very_low", 44, 0.01, 0.25 }, { "low_mid", 28, 0.25, 0.60 },
            { "decent", 12, 0.60, 0.90 }, { "pristine", 1, 0.95, 1 },
        },
        melee = {
            { "broken", 8, 0, 0 }, { "very_low", 40, 0.01, 0.25 }, { "low_mid", 37, 0.25, 0.60 },
            { "decent", 15, 0.60, 0.90 },
        },
        clothing = {
            { "very_low", 30, 0.01, 0.15 }, { "low", 40, 0.15, 0.45 }, { "medium", 25, 0.45, 0.75 },
            { "good", 5, 0.75, 0.95 },
        },
        armor = {
            { "broken", 5, 0, 0 }, { "very_low", 25, 0.01, 0.15 }, { "low", 40, 0.15, 0.45 },
            { "medium", 25, 0.45, 0.75 }, { "good", 5, 0.75, 0.95 },
        },
    },
    buckets = { 0, 0.25, 0.60 },
    armorPatterns = {
        "Vest_Bullet", "Helmet", "BodyArmour", "Cuirass", "Kevlar", "Gloves_Metal", "Shoulderpad", "Hat_Army", "Hat_SWAT",
    },
    dirt = { clothing = 0.5, armor = 0.7 },
}
ProjectALife.LootWear = Wear

function Wear.raw()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = type(vars) == "table" and tonumber(vars[Wear.option]) or nil
    if value == nil then return Wear.default end
    return math.max(0, math.min(100, value))
end

function Wear.percent()
    local gate = ProjectALife.FeatureGate
    if type(gate) ~= "table" or type(gate.number) ~= "function" then return Wear.raw() end
    return gate.number(Wear.option, Wear.default, 0, 100)
end

function Wear.strength()
    if Wear.debugPristine == true then return 0 end
    return Wear.percent() / 100
end

function Wear.unit(key, tag)
    local text = tostring(key) .. "|" .. tostring(tag)
    local h = 7919
    for index = 1, #text do h = (h * 131 + string.byte(text, index)) % 2147483647 end
    for _ = 1, 3 do
        h = (h * 48271) % 2147483647
        h = (h * ((h % 65521) + 1) + 12345) % 2147483647
    end
    return h / 2147483647
end

function Wear.pick(kind, u)
    local rows = Wear.tiers[kind]
    local sum = 0
    for index = 1, #rows do
        sum = sum + rows[index][2]
        if u * 100 < sum then return rows[index] end
    end
    return rows[#rows]
end

function Wear.fraction(kind, key, strength)
    local row = Wear.pick(kind, Wear.unit(key, kind .. ":tier"))
    local f = row[3] + (row[4] - row[3]) * Wear.unit(key, kind .. ":pos")
    strength = math.max(0, math.min(1, tonumber(strength) or 0))
    return 1 - (1 - f) * strength, row[1]
end

function Wear.conditionFor(maximum, fraction)
    maximum = math.max(1, math.floor(tonumber(maximum) or 1))
    if fraction <= 0 then return 0 end
    return math.max(1, math.min(maximum, math.floor(maximum * fraction + 0.5)))
end

function Wear.bucket(fraction)
    local edges = Wear.buckets
    if fraction <= edges[1] then return 1 end
    if fraction <= edges[2] then return 2 end
    if fraction <= edges[3] then return 3 end
    return 4
end

function Wear.ask(item, method)
    if item == nil or type(item[method]) ~= "function" then return nil end
    local ok, value = pcall(item[method], item)
    if ok then return value end
    return nil
end

function Wear.isArmor(fullType)
    local rarity = ProjectALife.LootRarity
    if type(rarity) == "table" and type(rarity.armorTier) == "function" and rarity.armorTier(fullType) ~= nil then
        return true
    end
    local text = tostring(fullType or "")
    for index = 1, #Wear.armorPatterns do
        if string.find(text, Wear.armorPatterns[index], 1, true) ~= nil then return true end
    end
    return false
end

function Wear.isFirearm(item)
    if Wear.ask(item, "isAimedFirearm") == true then return true end
    return Wear.ask(item, "isRanged") == true and (tonumber(Wear.ask(item, "getMaxAmmo")) or 0) > 0
end

function Wear.kindOf(item, fullType, hint)
    if Wear.ask(item, "IsWeapon") == true then
        return Wear.isFirearm(item) and "firearm" or "melee"
    end
    local data = Wear.ask(item, "getModData")
    local clothing = type(data) == "table" and data.ProjectALifeAuthoredClothing == true
    if not clothing and type(instanceof) == "function" then
        local ok, value = pcall(instanceof, item, "Clothing")
        clothing = ok and value == true
    end
    if clothing then return Wear.isArmor(fullType) and "armor" or "clothing" end
    if hint == "ammo" then
        if (tonumber(Wear.ask(item, "getMaxAmmo")) or 0) > 0 then return "magazine" end
        return "loose"
    end
    return nil
end

function Wear.newTally()
    return {
        corpses = 0, guns = { 0, 0, 0, 0 }, melee = { 0, 0, 0, 0 }, armor = { 0, 0, 0, 0 }, clothing = { 0, 0, 0, 0 },
        mags = 0, magFill = 0, issued = 0, dropped = 0, loose = 0, looseKept = 0,
    }
end

function Wear.note(tally, kind, fraction)
    if type(tally) ~= "table" then return end
    local rows = kind == "firearm" and tally.guns or tally[kind]
    if type(rows) == "table" then
        local at = Wear.bucket(fraction)
        rows[at] = rows[at] + 1
    end
end

function Wear.noteMag(tally, fraction)
    if type(tally) ~= "table" then return end
    tally.mags = tally.mags + 1
    tally.magFill = tally.magFill + math.max(0, math.min(1, fraction))
end

function Wear.dirty(item, kind, key, fraction)
    local limit = Wear.dirt[kind]
    if limit == nil then return end
    local amount = limit * (1 - fraction) * (0.5 + Wear.unit(key, "dirt"))
    if type(item.setDirtyness) == "function" and type(item.getDirtyness) == "function" then
        pcall(function()
            local now = tonumber(item:getDirtyness()) or 0
            item:setDirtyness(math.min(100, math.max(now, amount * 100)))
        end)
    end
end

function Wear.condition(item, kind, key, strength)
    if strength <= 0 or item == nil then return nil end
    local data = Wear.ask(item, "getModData")
    if type(data) ~= "table" then return nil end
    if data.ProjectALifeWorn == true then return nil, "already" end
    local maximum = tonumber(Wear.ask(item, "getConditionMax")) or 0
    if maximum <= 0 or type(item.setCondition) ~= "function" then return nil end
    local fraction, tier = Wear.fraction(kind, key, strength)
    local target = Wear.conditionFor(maximum, fraction)
    local current = tonumber(Wear.ask(item, "getCondition")) or maximum
    if target < current then
        if target <= 0 then target = ProjectALife.DropPolicy.breakSafe(item, 0) end
        pcall(item.setCondition, item, target)
        current = tonumber(Wear.ask(item, "getCondition")) or target
    end
    data.ProjectALifeWorn = true
    if kind == "clothing" or kind == "armor" then Wear.dirty(item, kind, key, current / maximum) end
    return current / maximum, tier
end

function Wear.rounds(current, capacity, ceiling, key, tag, strength)
    current = math.max(0, math.floor(tonumber(current) or 0))
    local u = Wear.unit(key, tag)
    local rolled = math.floor(capacity * ceiling * (u ^ Wear.skew))
    if rolled >= current then return current end
    return current - math.floor((current - rolled) * strength + 0.5)
end

function Wear.setLoaded(item, rounds)
    local magazines = ProjectALife.MagazineState
    if type(magazines) == "table" and type(magazines.setLoaded) == "function" then
        magazines.setLoaded(item, rounds)
        return
    end
    if type(item.setCurrentAmmoCount) == "function" then pcall(item.setCurrentAmmoCount, item, rounds) end
end

function Wear.fill(item, kind, key, strength)
    if strength <= 0 or item == nil then return nil end
    local capacity = math.floor(tonumber(Wear.ask(item, "getMaxAmmo")) or 0)
    if capacity <= 0 then return nil end
    local data = Wear.ask(item, "getModData")
    if type(data) == "table" and data.ProjectALifeAmmoWorn == true then return nil, "already" end
    local current = math.floor(tonumber(Wear.ask(item, "getCurrentAmmoCount")) or 0)
    local magazineType = Wear.ask(item, "getMagazineType")
    local detachable = kind == "magazine" or (magazineType ~= nil and tostring(magazineType) ~= ""
        and tostring(magazineType) ~= "null")
    local ceiling = detachable and Wear.ammo.magazine or Wear.ammo.internal
    local after = Wear.rounds(current, capacity, ceiling, key, "fill", strength)
    if after < current then
        Wear.setLoaded(item, after)
        if after <= 0 and kind ~= "magazine" and type(item.setRoundChambered) == "function" then
            pcall(item.setRoundChambered, item, false)
        end
    end
    if type(data) == "table" then data.ProjectALifeAmmoWorn = true end
    return after, capacity, current, detachable
end

function Wear.reserve(rounds, key, tag, strength)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    if strength <= 0 then return rounds end
    local exact = rounds * (1 - strength * (1 - Wear.ammo.reserve))
    local whole = math.floor(exact)
    if Wear.unit(key, tag) < exact - whole then whole = whole + 1 end
    return math.min(rounds, whole)
end

function Wear.keepLoose(key, strength)
    if strength <= 0 then return true end
    return Wear.unit(key, "loose") < 1 - strength * (1 - Wear.ammo.reserve)
end

return Wear
