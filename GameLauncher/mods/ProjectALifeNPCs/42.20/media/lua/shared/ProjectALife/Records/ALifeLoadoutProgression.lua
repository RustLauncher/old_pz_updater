require "ProjectALife/Records/ALifeFunnel"

ProjectALife = ProjectALife or {}
local Progression = {}
ProjectALife.LoadoutProgression = Progression

local function percent(seed, purpose)
    local hash = 0
    local text = tostring(seed or "") .. ":" .. purpose
    for i = 1, #text do hash = (hash * 31 + string.byte(text, i)) % 2147483647 end
    return hash % 100
end

Progression.classByBloc = {
    law = "issued", military = "issued", elite = "issued",
    family = "civil", civilian = "civil", worker = "civil", rescue = "civil",
    crime = "armed", raider = "armed", gang = "armed", club = "armed", prison = "armed", federation = "armed",
}

Progression.blocByFaction = {
    alife_guard = "military", alife_cordon = "military", alife_police = "law",
    alife_fire = "rescue", alife_kettle = "gang", alife_riverside = "civilian",
}

Progression.growth = {
    civil = {
        keep = { { 0, 30 }, { 3, 40 }, { 7, 55 }, { 14, 70 }, { 30, 90 }, { 60, 100 } },
        grant = { { 0, 0 }, { 8, 0 }, { 14, 8 }, { 21, 15 }, { 30, 25 }, { 60, 40 }, { 90, 50 }, { 180, 60 } },
    },
    armed = {
        keep = { { 0, 45 }, { 7, 60 }, { 14, 75 }, { 30, 90 }, { 60, 100 } },
        grant = { { 0, 4 }, { 14, 20 }, { 30, 40 }, { 60, 60 }, { 90, 70 }, { 180, 80 } },
    },
}

Progression.blocShare = { rescue = 0.4, worker = 0.8, prison = 0.5, raider = 1.2, civilian = 0.9 }
Progression.trainedBonus = 30
Progression.secondaryShare = 0.6
Progression.militaryDay = { civil = 30, armed = 14 }
Progression.spearDay = 3
Progression.issueChance = { law = 100, military = 60, elite = 100 }
Progression.noSidearm = { civic = true }

Progression.military = {
    ["Base.AssaultRifle"] = true, ["Base.AssaultRifle2"] = true, ["Base.MSR7T_Rifle"] = true,
    ["Base.PALServiceRifle"] = true, ["Base.L92_Carbine"] = true,
}

Progression.gardenTools = {
    ["Base.LeafRake"] = true, ["Base.GardenHoe"] = true, ["Base.HandFork"] = true, ["Base.GardenFork"] = true,
}

Progression.pools = {
    federation = { "Base.VarmintRifle", "Base.HuntingRifle", "Base.DoubleBarrelShotgun", "Base.Shotgun", "Base.Pistol", "Base.Revolver" },
    family = { "Base.VarmintRifle", "Base.DoubleBarrelShotgun", "Base.Shotgun", "Base.Revolver_Short" },
    civilian = { "Base.Revolver_Short", "Base.VarmintRifle", "Base.DoubleBarrelShotgun" },
    worker = { "Base.Revolver_Short", "Base.Shotgun", "Base.DoubleBarrelShotgun" },
    rescue = { "Base.Revolver_Short", "Base.Pistol" },
    crime = { "Base.Revolver_Short", "Base.Pistol2", "Base.ShotgunSawnoff", "Base.Revolver" },
    gang = { "Base.Revolver_Short", "Base.Pistol2", "Base.ShotgunSawnoff" },
    club = { "Base.Pistol3", "Base.Revolver", "Base.ShotgunSawnoff", "Base.Shotgun" },
    raider = { "Base.Shotgun", "Base.ShotgunSawnoff", "Base.Pistol2", "Base.HuntingRifle" },
    prison = { "Base.Revolver_Short", "Base.Pistol2" },
    law = { "Base.Pistol", "Base.Pistol", "Base.Revolver" },
    military = { "Base.Pistol" },
    elite = { "Base.Pistol" },
}

Progression.latePools = {
    family = { "Base.HuntingRifle", "Base.Pistol2" },
    civilian = { "Base.HuntingRifle", "Base.Revolver" },
    worker = { "Base.Revolver", "Base.HuntingRifle" },
    rescue = { "Base.Revolver" },
    crime = { "Base.Shotgun", "Base.HuntingRifle", "Base.Pistol" },
    gang = { "Base.Revolver", "Base.Pistol", "Base.Shotgun" },
    club = { "Base.Pistol", "Base.HuntingRifle" },
    raider = { "Base.AssaultRifle2", "Base.Pistol", "Base.DoubleBarrelShotgun" },
    prison = { "Base.Shotgun" },
}
Progression.lateDay = 60

Progression.factionPools = {
    alife_redline_reavers = { "Base.HuntingRifle", "Base.Shotgun", "Base.Pistol2", "Base.Revolver" },
    alife_the_tithe = { "Base.HuntingRifle", "Base.DoubleBarrelShotgun", "Base.Revolver", "Base.Pistol" },
    alife_night_shift = { "Base.HuntingRifle", "Base.Shotgun", "Base.Pistol", "Base.Revolver" },
}

Progression.tools = {
    federation = { "Base.Hammer", "Base.Wrench", "Base.Crowbar", "Base.Shovel", "Base.TireIron", "Base.BaseballBat" },
    family = { "Base.Hammer", "Base.Shovel", "Base.GardenHoe", "Base.Axe", "Base.Rake", "Base.TireIron", "Base.RollingPin" },
    civilian = { "Base.Hammer", "Base.Wrench", "Base.PipeWrench", "Base.Shovel", "Base.TireIron", "Base.KitchenKnife" },
    worker = { "Base.Wrench", "Base.PipeWrench", "Base.Hammer", "Base.TireIron", "Base.Crowbar", "Base.Mop" },
    rescue = { "Base.Crowbar", "Base.PipeWrench", "Base.IceAxe", "Base.Wrench" },
    crime = { "Base.Hammer", "Base.Machete", "Base.Axe", "Base.Crowbar" },
    gang = { "Base.MetalPipe", "Base.BaseballBat", "Base.Crowbar" },
    club = { "Base.Poolcue", "Base.BallPeenHammer", "Base.Crowbar" },
    raider = { "Base.Machete", "Base.Axe", "Base.Crowbar" },
    prison = { "Base.KitchenKnife", "Base.MetalPipe" },
    law = { "Base.Nightstick" },
    military = { "Base.FightingKnife", "Base.HuntingKnife" },
    elite = { "Base.FightingKnife" },
}

Progression.lawRoles = {
    police = true, trooper = true, sheriff = true, federal = true, ranger = true, corrections = true, tactical = true,
}
Progression.instructionDays = 3

function Progression.setting(field, key, fallback)
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current[field] ~= nil then return tonumber(current[field]) or fallback end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" and SandboxVars.ALife[key] ~= nil then
        return tonumber(SandboxVars.ALife[key]) or fallback
    end
    return fallback
end

function Progression.curve(points, day)
    if day <= points[1][1] then return points[1][2] end
    for i = 2, #points do
        local from, to = points[i - 1], points[i]
        if day <= to[1] then return from[2] + (to[2] - from[2]) * (day - from[1]) / (to[1] - from[1]) end
    end
    return points[#points][2]
end

function Progression.roleOf(tags)
    local index = 0
    for tag in string.gmatch(tostring(tags or ""), "[^,]+") do
        index = index + 1
        if index == 2 then return string.lower((string.gsub(tag, "^%s*(.-)%s*$", "%1"))) end
    end
    return ""
end

function Progression.classify(profile)
    local general = type(profile.general) == "table" and profile.general or {}
    local factionId = tostring(general.faction or "")
    local catalog = ProjectALife.Catalog
    local faction = type(catalog) == "table" and type(catalog.faction) == "function" and catalog.faction(factionId) or nil
    local bloc = type(faction) == "table" and type(faction.relations) == "table" and faction.relations.bloc or nil
    bloc = tostring(bloc or Progression.blocByFaction[factionId] or "civilian")
    local role = Progression.roleOf(general.tags)
    if role == "civic" then bloc = "civilian" end
    return Progression.classByBloc[bloc] or "civil", bloc, role
end

function Progression.isGun(itemType)
    return type(itemType) == "string" and itemType ~= "" and itemType ~= "none"
end

function Progression.hasGun(plan)
    return Progression.isGun(plan.weapons.primary) or Progression.isGun(plan.weapons.secondary)
end

function Progression.pick(list, known, seed, purpose)
    local usable = {}
    for _, itemType in ipairs(list or {}) do
        if known == nil or known(itemType) then usable[#usable + 1] = itemType end
    end
    if #usable == 0 then return nil end
    return usable[percent(seed, purpose) % #usable + 1]
end

function Progression.pool(bloc, day, factionId)
    local authored = Progression.factionPools[factionId]
    if authored ~= nil then return authored end
    local list = {}
    for _, itemType in ipairs(Progression.pools[bloc] or Progression.pools.family) do list[#list + 1] = itemType end
    if day >= Progression.lateDay then
        for _, itemType in ipairs(Progression.latePools[bloc] or {}) do list[#list + 1] = itemType end
    end
    return list
end

function Progression.grant(plan, bloc, chance, day, seed, known, mags, factionId)
    if percent(seed, "grant") >= chance then return false end
    local gun = Progression.pick(Progression.pool(bloc, day, factionId), known, seed, "gunpick")
    if gun == nil then return false end
    plan.weapons.primary = gun
    plan.ammo.primary = mags
    plan.ammoMode = plan.ammoMode or {}
    plan.ammoMode.primary = "magazines"
    plan.firearmsAuthored = true
    return true
end

function Progression.arm(plan, profile, class, bloc, role, day, share, seed, known)
    local factionId = type(profile.general) == "table" and profile.general.faction or nil
    if class == "issued" then
        if Progression.hasGun(plan) or Progression.noSidearm[role] == true then return end
        Progression.grant(plan, bloc, Progression.issueChance[bloc] or 70, day, seed, known, 2, factionId)
        return
    end
    local growth = Progression.growth[class]
    local trained = profile.general and tonumber(profile.general.aiming) or 0
    local keep = Progression.curve(growth.keep, day) * share
    if trained >= 6 then keep = keep + Progression.trainedBonus end
    keep = math.max(0, math.min(100, keep))
    local armsCap = day < 14 and 1 or 2
    for _, slot in ipairs({ "primary", "secondary" }) do
        local gun = plan.weapons[slot]
        if Progression.isGun(gun) then
            local rate = slot == "secondary" and keep * Progression.secondaryShare or keep
            if percent(seed, slot) >= rate then
                plan.weapons[slot] = nil
                plan.ammo[slot] = 0
            else
                if Progression.military[gun] == true and day < Progression.militaryDay[class] then
                    local swap = Progression.pick(Progression.pool(bloc, day, factionId), known, seed, "swap" .. slot)
                    if swap ~= nil then plan.weapons[slot] = swap end
                end
                if plan.ammoMode and plan.ammoMode[slot] == "magazines" then
                    plan.ammo[slot] = math.min(tonumber(plan.ammo[slot]) or 0, armsCap)
                end
            end
        end
    end
    if Progression.hasGun(plan) then return end
    local chance = Progression.curve(growth.grant, day) * share * (Progression.blocShare[bloc] or 1)
    Progression.grant(plan, bloc, math.min(100, chance), day, seed, known, day >= 45 and 2 or 1, factionId)
end

function Progression.noncombat(profile)
    if type(profile) ~= "table" or profile.shippedProgression ~= true
            or type(profile.general) ~= "table"
            or not string.match(tostring(profile.general.tags or ""), "^p7_successor,%s*elder%s*$") then return false end
    local class, bloc, role = Progression.classify(profile)
    return bloc == "federation" and role == "elder"
end

function Progression.melee(plan, class, bloc, day, seed)
    local melee = plan.weapons.melee
    local bare = melee == nil or melee == "" or melee == "Base.BareHands" or melee == "none"
    local list = Progression.tools[bloc] or Progression.tools.family
    local swap = bare
    if not bare and class == "civil" and day < Progression.spearDay and string.find(melee, "^Base%.Spear") then
        swap = true
    end
    if not bare and bloc == "military" and Progression.gardenTools[melee] == true then swap = true end
    if swap then plan.weapons.melee = list[percent(seed, "tool") % #list + 1] end
end

function Progression.instructs(profile, day)
    if type(profile) ~= "table" then return false end
    local class, bloc, role = Progression.classify(profile)
    return bloc == "law" and class == "issued" and Progression.lawRoles[role] == true
        and (tonumber(day) or 0) < Progression.instructionDays
end

function Progression.funnelDay(day)
    local funnel = ProjectALife.Funnel
    if type(funnel) ~= "table" or type(funnel.day) ~= "function" then return day end
    return funnel.day(day)
end

function Progression.funnelTier(day, tier)
    local funnel = ProjectALife.Funnel
    if type(funnel) ~= "table" or type(funnel.gearTier) ~= "function" then return tier end
    local staged = funnel.gearTier(day)
    if staged == nil then return tier end
    return staged
end

function Progression.apply(actor, profile, plan, known)
    local day = tonumber(actor.memory and actor.memory.loadoutDay)
    if profile.shippedProgression ~= true or day == nil then return plan end
    local worldDay = day
    day = Progression.funnelDay(day)
    local tier = day >= 180 and 5 or day >= 90 and 4 or day >= 30 and 3 or day >= 14 and 2 or 1
    tier = Progression.funnelTier(worldDay, tier)
    local seed = plan.appearanceSeed or actor.uid
    local class, bloc, role = Progression.classify(profile)
    local pace = math.max(10, Progression.setting("armingPace", "Loadouts_ArmingPace", 100))
    local share = math.max(0, Progression.setting("armingShare", "Loadouts_ArmingShare", 100)) / 100
    local scaled = day * pace / 100
    if Progression.noncombat(profile) then
        plan.weapons.primary, plan.weapons.secondary, plan.weapons.melee = nil, nil, nil
        plan.ammo.primary, plan.ammo.secondary = 0, 0
        plan.firearmsAuthored = false
    else
        Progression.arm(plan, profile, class, bloc, role, scaled, share, seed, known)
        Progression.melee(plan, class, bloc, scaled, seed)
    end

    local quality = percent(seed, "quality")
    if tier == 1 then plan.drop.weaponCondition = quality < 85 and 0 or 1
    elseif tier == 2 then plan.drop.weaponCondition = quality < 65 and 1 or 2
    elseif tier == 3 then plan.drop.weaponCondition = quality < 35 and 1 or 2
    elseif tier == 4 then plan.drop.weaponCondition = quality < 15 and 1 or 2 + quality % 2
    else plan.drop.weaponCondition = quality < 5 and 2 or 3 + quality % 3 end

    local marksman = type(profile) == "table" and type(profile.moduleOverrides) == "table"
        and tostring(profile.moduleOverrides.sniper or "") == "on"
    if marksman or (tier >= 3 and percent(seed, "parts") < (tier - 2) * 25) then
        plan.weaponAttachments = {}
        for weapon, parts in pairs(profile.weaponAttachments or {}) do plan.weaponAttachments[weapon] = parts end
        for _, slot in ipairs({ "primary", "secondary" }) do
            local gun = plan.weapons[slot]
            if gun and plan.weaponAttachments[gun] == nil then

                if gun == "Base.MSR7T_Rifle" or gun == "Base.L94_Rifle"
                        or gun == "Base.JS14_Rifle" then
                    plan.weaponAttachments[gun] = tier >= 4 and "Base.x8Scope|Base.RecoilPad" or "Base.x4Scope"
                elseif gun == "Base.HuntingRifle" or gun == "Base.VarmintRifle" then
                    plan.weaponAttachments[gun] = tier >= 4 and "Base.x4Scope|Base.RecoilPad" or "Base.x2Scope"
                elseif gun == "Base.AssaultRifle" or gun == "Base.AssaultRifle2" then
                    plan.weaponAttachments[gun] = "Base.RedDot"
                elseif gun == "Base.Shotgun" or gun == "Base.DoubleBarrelShotgun" then
                    plan.weaponAttachments[gun] = "Base.RecoilPad"
                end
            end
        end
    end
    return plan
end

return Progression
