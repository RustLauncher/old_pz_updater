ProjectALife = ProjectALife or {}

require "ProjectALife/Records/ALifeLootRarity"
require "ProjectALife/Records/ALifeDifficultyPreset"

local NpcHealth = {
    keys = {
        percent = "NpcHealth_Percent",
        taken = "NpcHealth_DamageTakenPercent",
        regen = "NpcHealth_RegenPercent",
        legacy = "NpcHealth_Legacy",
    },
    defaults = { percent = 98, taken = 130, regen = 50 },
    limits = { percent = { 25, 300 }, taken = { 25, 400 }, regen = { 0, 400 } },
    scaleLimits = { 0.05, 5 },

    classMax = { civilian = 0.9, raider = 1, police = 1, military = 1, elite = 1.07 },
    classNames = {
        civilian = "civilian", worker = "civilian", rescue = "civilian",
        police = "police", military = "military", criminal = "raider",
    },
    minor = { scale = 0.8, words = { "teenager", "kid brother", "younger brother" } },

    shots = { rifle = 3.5, pistol = 4.5, shotgun = 2, light = 10, melee = 6, heavy = 4.8 },
    fire = {
        head = 3, helmetedHead = 2, meleeHead = 2.2, meleeHelmetedHead = 1.6,
        vest = 0.8, toughnessMin = 0.25,
    },
    sources = { zombie = 1, npcGun = 1, npcMelee = 0.75 },
    rest = { quietMs = 120000, shotQuietMs = 60000 },
    bleedScale = 1.5,

    cache = {},
    metrics = { scaled = 0, overlays = 0 },
}
ProjectALife.NpcHealth = NpcHealth

function NpcHealth.option(name)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return nil end
    return vars[name]
end

function NpcHealth.number(kind)
    local limits = NpcHealth.limits[kind]
    local name = NpcHealth.keys[kind]
    local value = NpcHealth.option(name)
    local preset = ProjectALife.DifficultyPreset
    if preset ~= nil and type(preset.option) == "function" then value = preset.option(name, value) end
    value = tonumber(value) or NpcHealth.defaults[kind]
    return math.max(limits[1], math.min(limits[2], value))
end

function NpcHealth.legacy()
    return NpcHealth.option(NpcHealth.keys.legacy) == true
end

function NpcHealth.percentScale()
    return NpcHealth.number("percent") / 100
end

function NpcHealth.takenScale()
    return NpcHealth.number("taken") / 100
end

function NpcHealth.regenScale()
    return NpcHealth.number("regen") / 100
end

function NpcHealth.classOf(general, factionId)
    local own = type(general) == "table" and general.npcClass or nil
    if type(own) == "string" and NpcHealth.classNames[own] ~= nil then return NpcHealth.classNames[own] end
    local rarity = ProjectALife.LootRarity
    if rarity == nil or type(rarity.factionClass) ~= "function" then return nil end
    local ok, class = pcall(rarity.factionClass, factionId)
    if ok and type(class) == "string" then return class end
    return nil
end

function NpcHealth.isMinor(general)
    local name = type(general) == "table" and general.name or nil
    if type(name) ~= "string" then return false end
    name = string.lower(name)
    for _, word in ipairs(NpcHealth.minor.words) do
        if string.find(name, word, 1, true) ~= nil then return true end
    end
    return false
end

function NpcHealth.announce()
    if NpcHealth.announced == true then return end
    NpcHealth.announced = true
    print("[ALIFE-HP] npc health legacy=" .. tostring(NpcHealth.legacy()) .. " percent=" .. NpcHealth.number("percent")
        .. " taken=" .. NpcHealth.number("taken") .. " regen=" .. NpcHealth.number("regen"))
end

function NpcHealth.authored(general, standard)
    local hp = tonumber(type(general) == "table" and general.healthHP or nil)
    if hp == nil or hp ~= hp or hp <= 0 then return tonumber(standard) or 50 end
    return hp
end

function NpcHealth.scaleOf(general, factionId)
    if NpcHealth.legacy() then return 1 end
    general = type(general) == "table" and general or {}
    if factionId == nil then factionId = general.faction end
    local class = NpcHealth.classOf(general, factionId)
    local scale = NpcHealth.percentScale() * (class ~= nil and NpcHealth.classMax[class] or 1)
    if NpcHealth.isMinor(general) then scale = scale * NpcHealth.minor.scale end
    return math.max(NpcHealth.scaleLimits[1], math.min(NpcHealth.scaleLimits[2], scale))
end

function NpcHealth.preview(general, standard, multiplier)
    multiplier = tonumber(multiplier) or 1
    if multiplier <= 0 then multiplier = 1 end
    local base = math.max(1, NpcHealth.authored(general, standard) * multiplier)
    return math.max(1, math.floor(base * NpcHealth.scaleOf(general) + 0.5))
end

function NpcHealth.scaleFor(profile, actor)
    NpcHealth.announce()
    if NpcHealth.legacy() then return 1 end
    local general = type(profile) == "table" and type(profile.general) == "table" and profile.general or {}
    local factionId = general.faction
    if factionId == nil and type(actor) == "table" then factionId = actor.factionId end
    NpcHealth.metrics.scaled = NpcHealth.metrics.scaled + 1
    return NpcHealth.scaleOf(general, factionId)
end

function NpcHealth.fireFor(base)
    if type(base) ~= "table" or type(base.shots) ~= "table" or NpcHealth.legacy() then return base end
    local taken = NpcHealth.takenScale()
    local cache = NpcHealth.cache
    if cache.base == base and cache.taken == taken and cache.fire ~= nil then return cache.fire end
    local fire = {}
    for key, value in pairs(base) do fire[key] = value end
    for key, value in pairs(NpcHealth.fire) do fire[key] = value end
    fire.shots = {}
    for key, value in pairs(base.shots) do fire.shots[key] = value end
    for key, value in pairs(NpcHealth.shots) do fire.shots[key] = value end
    for key, value in pairs(fire.shots) do fire.shots[key] = value / taken end
    cache.base, cache.taken, cache.fire = base, taken, fire
    NpcHealth.metrics.overlays = NpcHealth.metrics.overlays + 1
    return fire
end

function NpcHealth.takenBy(ranged)
    if NpcHealth.legacy() then return 1 end
    local source = ranged == true and NpcHealth.sources.npcGun or NpcHealth.sources.npcMelee
    return NpcHealth.takenScale() * source
end

function NpcHealth.biteScale(data)
    if NpcHealth.legacy() then return 1 end
    local own = type(data) == "table" and tonumber(data.ProjectALifeNpcHealthScale) or nil
    if own == nil or own <= 0 then own = 1 end
    return NpcHealth.takenScale() * NpcHealth.sources.zombie / own
end

function NpcHealth.bleed()
    if NpcHealth.legacy() then return 1 end
    return NpcHealth.bleedScale
end

function NpcHealth.rested(data, now)
    if type(data) ~= "table" then return true end
    local rest = NpcHealth.rest
    local hit = tonumber(data.ProjectALifeLastHitAtMs)
    if hit ~= nil and now >= hit and now - hit < rest.quietMs then return false end
    local shot = tonumber(data.ProjectALifeLastShotAtMs)
    if shot ~= nil and now >= shot and now - shot < rest.shotQuietMs then return false end
    return true
end

function NpcHealth.regenPlan(data, now, rate)
    if NpcHealth.legacy() then return true, rate end
    if not NpcHealth.rested(data, tonumber(now) or 0) then return false, rate end
    return true, rate * NpcHealth.regenScale()
end

return NpcHealth
