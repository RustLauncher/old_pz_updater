ProjectALife = ProjectALife or {}

local Rarity = {
    options = { rareDrop = "Loot_RareDropPercent", profiles = "Loot_AllowRareFromProfiles" },
    defaults = { rareDrop = 5 },
    denyExact = {
        ["Base.Sledgehammer"] = true, ["Base.Sledgehammer2"] = true, ["Base.SledgehammerForged"] = true,
        ["Base.SledgehammerHead"] = true, ["Base.Chainsaw"] = true,
    },
    denyPatterns = { "^Base%.Sledge", "^Base%.Katana", "^Base%.Chainsaw", "^Base%.%a+Head$" },
    denyKeep = { ["Base.Bandage_Head"] = true, ["Base.FlashLight_AngleHead"] = true },
    heavyPatterns = {
        "^Base%.Vest_BulletArmy$", "^Base%.Vest_BulletSWAT$", "^Base%.Vest_BulletDesert", "^Base%.Vest_BulletOliveDrab$",
        "^Base%.Hat_Army", "^Base%.Hat_RiotHelmet", "^Base%.Hat_SWAT$",
        "^Base%.Boilersuit_SWAT", "^Base%.Vambrace_BodyArmour", "^Base%.Hazmat", "^Base%.HazmatSuit",
        "^Base%.Hat_GasMask", "^Base%.Hat_Hazmat",
    },
    mediumPatterns = { "^Base%.Vest_BulletPolice$", "^Base%.Vest_BulletCivilian$" },
    scarceWeapons = {
        ["Base.AssaultRifle"] = true, ["Base.AssaultRifle2"] = true, ["Base.MSR7T_Rifle"] = true,
        ["Base.PALServiceRifle"] = true, ["Base.L92_Carbine"] = true,
    },
    substitutes = {
        ["Base.Vest_BulletArmy"] = "Base.Vest_Hunting_Camo", ["Base.Vest_BulletSWAT"] = "Base.Vest_Hunting_Camo",
        ["Base.Vest_BulletDesert"] = "Base.Vest_Hunting_Camo", ["Base.Vest_BulletDesertNew"] = "Base.Vest_Hunting_Camo",
        ["Base.Vest_BulletOliveDrab"] = "Base.Vest_Hunting_Camo",
        ["Base.Vest_BulletPolice"] = "Base.Vest_Hunting_Khaki", ["Base.Vest_BulletCivilian"] = "Base.Vest_Hunting_Khaki",
        ["Base.Hat_Army"] = "Base.Hat_BaseballCapArmy", ["Base.Hat_ArmyDesert"] = "Base.Hat_BaseballCapArmy",
        ["Base.Hat_ArmyDesertNew"] = "Base.Hat_BaseballCapArmy", ["Base.Hat_ArmyWWII"] = "Base.Hat_BaseballCapArmy",
        ["Base.Hat_RiotHelmet"] = "Base.Hat_HockeyHelmet", ["Base.Hat_SWAT"] = "Base.Hat_BaseballCap",
        ["Base.Boilersuit_SWAT"] = "Base.Boilersuit_BlueRed",
        ["Base.Vambrace_BodyArmour_Left_Army"] = "Base.Vambrace_Leather_Left",
        ["Base.Vambrace_BodyArmour_Right_Army"] = "Base.Vambrace_Leather_Right",
        ["Base.Hat_GasMask"] = "Base.Hat_DustMask",
    },
    meleeSubstitutes = { "Base.Axe", "Base.Machete", "Base.BaseballBat", "Base.Crowbar", "Base.HandAxe" },
    classRank = { civilian = 1, raider = 2, police = 3, military = 4, elite = 5 },
    classBand = {
        civilian = { 20, 45 }, raider = { 25, 50 }, police = { 30, 55 }, military = { 35, 65 }, elite = { 40, 70 },
    },
    rareBand = { 10, 40 },
    blocClass = {
        civilian = "civilian", family = "civilian", worker = "civilian", rescue = "civilian",
        crime = "raider", gang = "raider", club = "raider", raider = "raider", prison = "raider", federation = "raider",
        law = "police", military = "military", elite = "elite",
    },
    stockBlocs = {
        alife_police = "law", alife_guard = "military", alife_cordon = "military",
        alife_fire = "rescue", alife_riverside = "civilian", alife_kettle = "worker",
    },
    rareFactions = { alife_ksp_srt = true, alife_vault_police = true },
    factionClasses = {
        alife_commonwealth_knox = "police", alife_ridge_militia_league = "police",
        alife_valley_caravan_league = "police", alife_iron_choir = "police",
    },
    metrics = { denied = 0, substituted = 0, stripped = 0, rareKept = 0, degraded = 0, firearmsOnly = 0 },
}
ProjectALife.LootRarity = Rarity

function Rarity.option(key, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = nil
    if type(vars) == "table" then value = vars[key] end
    if value == nil then return default end
    return value
end

function Rarity.rareDropPercent()
    local value = tonumber(Rarity.option(Rarity.options.rareDrop, Rarity.defaults.rareDrop)) or Rarity.defaults.rareDrop
    return math.max(0, math.min(100, value))
end

function Rarity.allowFromProfiles()
    return Rarity.option(Rarity.options.profiles, false) == true
end

function Rarity.normal(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    if string.find(fullType, ".", 1, true) == nil then return "Base." .. fullType end
    return fullType
end

function Rarity.matches(list, fullType)
    for index = 1, #list do
        if string.find(fullType, list[index]) ~= nil then return true end
    end
    return false
end

function Rarity.denied(fullType)
    fullType = Rarity.normal(fullType)
    if fullType == nil or Rarity.denyKeep[fullType] == true then return false end
    if Rarity.denyExact[fullType] == true then return true end
    return Rarity.matches(Rarity.denyPatterns, fullType)
end

function Rarity.heavy(fullType)
    fullType = Rarity.normal(fullType)
    if fullType == nil then return false end
    return Rarity.matches(Rarity.heavyPatterns, fullType)
end

function Rarity.medium(fullType)
    fullType = Rarity.normal(fullType)
    if fullType == nil then return false end
    return Rarity.matches(Rarity.mediumPatterns, fullType)
end

function Rarity.armorTier(fullType)
    if Rarity.heavy(fullType) then return "heavy" end
    if Rarity.medium(fullType) then return "medium" end
    return nil
end

function Rarity.scarceWeapon(fullType)
    fullType = Rarity.normal(fullType)
    return fullType ~= nil and Rarity.scarceWeapons[fullType] == true
end

function Rarity.hash(text)
    local value = 0
    text = tostring(text or "")
    for index = 1, #text do value = (value * 31 + string.byte(text, index)) % 2147483647 end
    return value
end

function Rarity.fraction(seed, purpose)
    return (Rarity.hash(tostring(seed or "") .. ":" .. tostring(purpose or "")) % 1000) / 1000
end

function Rarity.classOf(bloc, factionId)
    if Rarity.rareFactions[tostring(factionId or "")] == true then return "elite" end
    local assigned = Rarity.factionClasses[tostring(factionId or "")]
    if assigned ~= nil then return assigned end
    bloc = tostring(bloc or Rarity.stockBlocs[tostring(factionId or "")] or "civilian")
    return Rarity.blocClass[bloc] or "civilian"
end

function Rarity.classOfFaction(faction)
    if type(faction) ~= "table" then return "civilian" end
    local relations = type(faction.relations) == "table" and faction.relations or {}
    return Rarity.classOf(relations.bloc, faction.id)
end

function Rarity.factionClass(factionId)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(factionId) or nil
    if type(faction) == "table" then return Rarity.classOfFaction(faction) end
    return Rarity.classOf(nil, factionId)
end

function Rarity.rank(class)
    return Rarity.classRank[tostring(class)] or 1
end

function Rarity.rareEligible(class, factionId)
    if Rarity.rareFactions[tostring(factionId or "")] == true then return true end
    return Rarity.rank(class) >= Rarity.classRank.military
end

function Rarity.mayWear(fullType, class, factionId)
    local tier = Rarity.armorTier(fullType)
    if tier == nil then return true end
    if tier == "medium" then return Rarity.rank(class) >= Rarity.classRank.police end
    return Rarity.rareEligible(class, factionId)
end

function Rarity.rareRoll(class, factionId, seed)
    if not Rarity.rareEligible(class, factionId) then return false end
    local percent = Rarity.rareDropPercent()
    if percent <= 0 then return false end
    return Rarity.hash(tostring(seed or "") .. ":rare") % 10000 < percent * 100
end

function Rarity.conditionPercent(class, seed, purpose, rare)
    local band = rare == true and Rarity.rareBand or Rarity.classBand[tostring(class)] or Rarity.classBand.civilian
    return band[1] + (band[2] - band[1]) * Rarity.fraction(seed, purpose)
end

function Rarity.ratingFor(class, seed, purpose, rare)
    return Rarity.conditionPercent(class, seed, purpose, rare) / 10
end

function Rarity.conditionFor(maximum, percent)
    maximum = math.max(1, math.floor(tonumber(maximum) or 1))
    percent = math.max(0, math.min(100, tonumber(percent) or 0))
    return math.max(1, math.min(maximum, math.floor(maximum * percent / 100 + 0.5)))
end

function Rarity.meleeFor(seed, class)
    local list = Rarity.meleeSubstitutes
    return list[Rarity.hash(tostring(seed or "") .. ":melee") % #list + 1]
end

function Rarity.swap(fullType, class, factionId)
    local normal = Rarity.normal(fullType)
    if normal == nil then return fullType end
    if Rarity.denied(normal) then return nil end
    if Rarity.mayWear(normal, class, factionId) then return fullType end
    return Rarity.substitutes[normal]
end

function Rarity.allowedItem(fullType)
    if Rarity.denied(fullType) then return false end
    return Rarity.armorTier(fullType) == nil
end

function Rarity.filterList(list)
    local kept = {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        local kind = type(entry) == "table" and entry[1] or entry
        if Rarity.allowedItem(kind) then kept[#kept + 1] = entry
        else Rarity.metrics.denied = Rarity.metrics.denied + 1 end
    end
    return kept
end

function Rarity.filterChoice(choice, class, factionId)
    if type(choice) ~= "string" or choice == "" then return choice, false end
    local changed = false
    local kept = {}
    for token in string.gmatch(choice .. "|", "(.-)|") do
        local trimmed = string.match(token, "^%s*(.-)%s*$")
        if trimmed ~= "" then
            local swapped = Rarity.swap(trimmed, class, factionId)
            if swapped ~= trimmed then changed = true end
            if swapped ~= nil then kept[#kept + 1] = swapped end
        end
    end
    if #kept == 0 then return "none", true end
    return table.concat(kept, "|"), changed
end

function Rarity.sanitizeWeapons(plan, class, factionId, seed)
    local weapons = type(plan.weapons) == "table" and plan.weapons or nil
    if weapons == nil then return end
    for _, slot in ipairs({ "primary", "secondary", "melee" }) do
        local kind = weapons[slot]
        if type(kind) == "string" and Rarity.denied(kind) then
            Rarity.metrics.denied = Rarity.metrics.denied + 1
            if slot == "melee" then
                weapons[slot] = Rarity.meleeFor(seed, class)
            else
                weapons[slot] = nil
                if type(plan.ammo) == "table" then plan.ammo[slot] = 0 end
            end
        end
    end
end

function Rarity.sanitizeClothing(plan, class, factionId)
    if type(plan.clothing) ~= "table" then return false end
    local kept, heavyWorn = {}, false
    for _, entry in ipairs(plan.clothing) do
        local kind = type(entry) == "table" and entry.itemType or entry
        local swapped = Rarity.swap(kind, class, factionId)
        if swapped == nil then
            Rarity.metrics.stripped = Rarity.metrics.stripped + 1
        else
            if swapped ~= kind then
                Rarity.metrics.substituted = Rarity.metrics.substituted + 1
                if type(entry) == "table" then entry.itemType = swapped else entry = swapped end
            end
            if Rarity.armorTier(swapped) ~= nil then heavyWorn = true end
            kept[#kept + 1] = entry
        end
    end
    plan.clothing = kept
    return heavyWorn
end

function Rarity.sanitizePlan(plan, profile, actor)
    if type(plan) ~= "table" then return plan end
    local custom = type(profile) == "table" and profile.shippedProgression ~= true
    if custom and Rarity.allowFromProfiles() then return plan end
    local factionId = plan.factionId
    local class = Rarity.factionClass(factionId)
    local seed = tostring(plan.appearanceSeed or plan.actorUid or "")
    Rarity.sanitizeWeapons(plan, class, factionId, seed)
    local heavyWorn = Rarity.sanitizeClothing(plan, class, factionId)
    local drop = type(plan.drop) == "table" and plan.drop or nil
    if drop == nil then return plan end
    drop.class = class
    drop.rareDrop = Rarity.rareRoll(class, factionId, seed)
    drop.rareRating = Rarity.ratingFor(class, seed, "rare", true)
    drop.heavyWorn = heavyWorn
    if not custom then
        local armor = Rarity.ratingFor(class, seed, "armor")
        drop.armorCondition = math.min(tonumber(drop.armorCondition) or armor, armor)
        local gun = Rarity.ratingFor(class, seed, "weapon")
        drop.weaponCondition = math.min(tonumber(drop.weaponCondition) or gun, gun)
    end
    local weapons = type(plan.weapons) == "table" and plan.weapons or {}
    drop.scarceCarried = Rarity.rank(class) < Rarity.classRank.military
        and (Rarity.scarceWeapon(weapons.primary) or Rarity.scarceWeapon(weapons.secondary))
    return plan
end

function Rarity.mayBreak(item)
    local firearm = false
    if type(item) == "table" or type(item) == "userdata" then
        pcall(function()
            if type(item.isAimedFirearm) == "function" then firearm = item:isAimedFirearm() == true end
        end)
    end
    if not firearm then Rarity.metrics.firearmsOnly = Rarity.metrics.firearmsOnly + 1 end
    return firearm
end

function Rarity.degradeItem(item, percent, dirty)
    if item == nil then return false end
    local ok = pcall(function()
        local maximum = tonumber(item:getConditionMax()) or 0
        if maximum > 0 and type(item.setCondition) == "function" then
            item:setCondition(Rarity.conditionFor(maximum, percent))
        end
        if dirty == true then
            if type(item.setDirtiness) == "function" then item:setDirtiness(0.6 + 0.4 * Rarity.fraction(tostring(percent), "dirt")) end
            if type(item.setBloodLevel) == "function" then item:setBloodLevel(0.3 + 0.5 * Rarity.fraction(tostring(percent), "blood")) end
        end
    end)
    if ok then Rarity.metrics.degraded = Rarity.metrics.degraded + 1 end
    return ok
end

function Rarity.itemType(item)
    local kind = nil
    pcall(function() kind = item:getFullType() end)
    return kind ~= nil and tostring(kind) or ""
end

function Rarity.scrubInventory(inventory)
    local removed = 0
    if inventory == nil then return 0 end
    pcall(function()
        local items = inventory:getItems()
        for index = items:size() - 1, 0, -1 do
            local item = items:get(index)
            if Rarity.denied(Rarity.itemType(item)) then
                inventory:Remove(item)
                removed = removed + 1
            end
        end
    end)
    Rarity.metrics.denied = Rarity.metrics.denied + removed
    return removed
end

return Rarity
