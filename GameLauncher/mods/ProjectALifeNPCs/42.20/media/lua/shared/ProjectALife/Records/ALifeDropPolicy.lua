ProjectALife = ProjectALife or {}
local Policy = {}
ProjectALife.DropPolicy = Policy

Policy.conditions = {
    { "Broken (0/10)", 0 },
    { "Scrap, a shot or two (1/10)", 1 },
    { "Very poor, a few shots (2/10)", 2 },
    { "Poor (3/10)", 3 },
    { "Worn (4/10)", 4 },
    { "Used, half gone (5/10)", 5 },
    { "Serviceable (6/10)", 6 },
    { "Good (7/10)", 7 },
    { "Very good (8/10)", 8 },
    { "Near new (9/10)", 9 },
    { "Issue fresh (10/10)", 10 },
}

function Policy.conditionFor(maximum, rating)
    maximum = math.max(1, math.floor(tonumber(maximum) or 1))
    local normalized = math.max(0, math.min(10, tonumber(rating) or 10))
    if normalized <= 0 then return 0 end
    return math.max(1, math.min(maximum, math.floor(maximum * normalized / 10 + 0.5)))
end

function Policy.hasBreakHandler(item)
    if item == nil or type(item.getOnBreak) ~= "function" then return false end
    local ok, handler = pcall(item.getOnBreak, item)
    return ok and handler ~= nil and tostring(handler) ~= ""
end

function Policy.breakSafe(item, condition)
    local value = tonumber(condition)
    if value == nil or value > 0 or item == nil then return condition, false end
    if not Policy.hasBreakHandler(item) then return condition, false end
    return 1, true
end

function Policy.issue(item, condition)
    condition = math.floor(tonumber(condition) or 1)
    local data = item:getModData()
    if condition <= 0 and Policy.hasBreakHandler(item) then condition = 1 end
    if condition <= 0 then
        data.ProjectALifeBreakOnDrop = true
        condition = 1
    else
        data.ProjectALifeBreakOnDrop = nil
    end
    item:setCondition(condition)
    data.ProjectALifeIssuedCondition = true
end

function Policy.wornRating(rating, seed)
    local normalized = math.max(0, math.min(10, tonumber(rating) or 0))
    if normalized <= 1 then return normalized end
    local hash, text = 0, tostring(seed or "") .. ":condition"
    for index = 1, #text do hash = (hash * 31 + string.byte(text, index)) % 2147483647 end
    return normalized - (hash % 3 == 0 and 1 or 0)
end

Policy.presets = {
    { "Off (0%)", "off", 0, 0 },
    { "Very low (0-10%)", "very_low", 0, 10 },
    { "Low (10-20%)", "low", 10, 20 },
    { "Moderate (20-30%)", "moderate", 20, 30 },
    { "High (30-50%)", "high", 30, 50 },
    { "Very high (50-70%)", "very_high", 50, 70 },
    { "Almost always (70-99%)", "almost_always", 70, 99 },
    { "Always (100%)", "always", 100, 100 },
}

function Policy.resolve(general)
    general = general or {}
    if general.dropWeapon == false then return Policy.presets[1] end
    for _, preset in ipairs(Policy.presets) do
        if preset[2] == general.dropWeaponPreset then return preset end
    end
    local value = math.max(0, math.min(100, tonumber(general.dropWeaponChance) or 55))
    if value == 0 then return Policy.presets[1] end
    if value == 100 then return Policy.presets[8] end
    for index = 2, 7 do
        if value < Policy.presets[index][4] or index == 7 then return Policy.presets[index] end
    end
end

function Policy.sandboxPreset(value)
    local index = math.floor(tonumber(value) or 1)
    local preset = index > 1 and Policy.presets[index - 1] or nil
    return preset and preset[2] or nil
end

function Policy.sandboxRating(value)
    local index = math.floor(tonumber(value) or 1)
    local rung = index > 1 and Policy.conditions[index - 1] or nil
    return rung and rung[2] or nil
end

function Policy.chance(general, seed)
    local preset = Policy.resolve(general)
    local hash = 0
    local text = tostring(seed or "") .. ":weapon-drop"
    for index = 1, #text do hash = (hash * 31 + string.byte(text, index)) % 2147483647 end
    return preset[3] + hash % (preset[4] - preset[3] + 1)
end

Policy.defaults = { master = 100, weapon = 100, armor = 100, ammo = 100, supplies = 100 }

Policy.neverDrop = {
    exact = {
        ["Base.Sledgehammer"] = true, ["Base.Sledgehammer2"] = true, ["Base.SledgehammerForged"] = true,
        ["Base.Chainsaw"] = true, ["Base.Katana"] = true,
        ["Base.PropaneTank"] = true, ["Base.BlowTorch"] = true, ["Base.WeldingRods"] = true,
        ["Base.Cuirass_CoatOfPlates"] = true, ["Base.Cuirass_Metal"] = true, ["Base.Cuirass_MetalScrap"] = true,
        ["Base.Hat_MetalScrapHelmet"] = true, ["Base.Hat_HockeyMask_MetalScrap"] = true,
        ["Base.Gloves_MetalArmour"] = true, ["Base.Gloves_MetalScrapArmour"] = true,
        ["Base.Shoulderpad_MetalScrap_L"] = true, ["Base.Shoulderpad_MetalScrap_R"] = true,
    },
    patterns = {
        "^Base%.Sledge", "^Base%.Katana", "^Base%.Chainsaw", "^Base%.%a+Head$", "^Base%.%a*Maul$",
        "^Base%.Generator", "^Base%.GreaveBodyArmour", "^Base%.ThighBodyArmour", "^Base%.Vambrace_BodyArmour",
    },
    keep = { ["Base.Bandage_Head"] = true, ["Base.FlashLight_AngleHead"] = true },
}

Policy.ammoPatterns = { "^Base%.Bullets", "^Base%.%d+Bullets", "^Base%.ShotgunShells", "Clip$" }

function Policy.fullName(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    if string.find(fullType, ".", 1, true) == nil then return "Base." .. fullType end
    return fullType
end

function Policy.neverDrops(fullType)
    fullType = Policy.fullName(fullType)
    if fullType == nil then return false end
    local list = Policy.neverDrop
    if list.keep[fullType] == true then return false end
    if list.exact[fullType] == true then return true end
    for index = 1, #list.patterns do
        if string.find(fullType, list.patterns[index]) ~= nil then return true end
    end
    return false
end

function Policy.isAmmo(fullType)
    fullType = Policy.fullName(fullType)
    if fullType == nil then return false end
    for index = 1, #Policy.ammoPatterns do
        if string.find(fullType, Policy.ammoPatterns[index]) ~= nil then return true end
    end
    return false
end

function Policy.raw(key, fallback)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = nil
    if type(vars) == "table" then value = tonumber(vars[key]) end
    if value == nil then return fallback end
    return math.max(0, math.min(100, value))
end

function Policy.percents()
    local defaults = Policy.defaults
    local gate = ProjectALife.FeatureGate
    if type(gate) ~= "table" or type(gate.number) ~= "function" then
        return {
            master = Policy.raw("Loot_NpcDropPercent", defaults.master),
            weapon = Policy.raw("Loot_NpcWeaponPercent", defaults.weapon),
            armor = Policy.raw("Loot_NpcArmorPercent", defaults.armor),
            ammo = Policy.raw("Loot_NpcAmmoPercent", defaults.ammo),
            supplies = Policy.raw("Loot_NpcSuppliesPercent", defaults.supplies),
        }
    end
    return {
        master = ProjectALife.FeatureGate.number("Loot_NpcDropPercent", defaults.master, 0, 100),
        weapon = ProjectALife.FeatureGate.number("Loot_NpcWeaponPercent", defaults.weapon, 0, 100),
        armor = ProjectALife.FeatureGate.number("Loot_NpcArmorPercent", defaults.armor, 0, 100),
        ammo = ProjectALife.FeatureGate.number("Loot_NpcAmmoPercent", defaults.ammo, 0, 100),
        supplies = ProjectALife.FeatureGate.number("Loot_NpcSuppliesPercent", defaults.supplies, 0, 100),
    }
end

function Policy.scales(explicitWeapon)
    local p = Policy.percents()
    return {
        master = p.master,
        weapon = explicitWeapon == true and 100 or p.master * p.weapon / 100,
        armor = p.master * p.armor / 100,
        ammo = p.master * p.ammo / 100,
        supplies = p.master * p.supplies / 100,
    }
end

function Policy.scaled(chance, percent)
    chance = tonumber(chance) or 0
    percent = tonumber(percent)
    if percent == nil or percent >= 100 then return chance end
    return math.max(0, chance * math.max(0, percent) / 100)
end

return Policy
