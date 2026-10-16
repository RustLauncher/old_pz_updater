require "ProjectALife/Shells/ALifeAppearanceData"
require "ProjectALife/Records/ALifeLoadoutProgression"

ProjectALife = ProjectALife or {}

local Appearance = {
    counters = { spawns = 0, varied = 0, kept = 0, fixed = 0, legacy = 0, collisions = 0 },
    styleSets = {},
    classes = setmetatable({}, { __mode = "k" }),
    traitRows = setmetatable({}, { __mode = "k" }),
    shades = {},
}
ProjectALife.Appearance = Appearance

function Appearance.value(field, key, default)
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current[field] ~= nil then return current[field] end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" and SandboxVars.ALife[key] ~= nil then
        return SandboxVars.ALife[key]
    end
    return default
end

function Appearance.enabled()
    return Appearance.value("appearanceVariation", "Appearance_Variation", true) ~= false
end

function Appearance.keepPercent()
    local value = tonumber(Appearance.value("appearanceKeepAuthored", "Appearance_KeepAuthoredPercent", 35))
    return math.max(0, math.min(100, value or 35))
end

function Appearance.loadoutVariation()
    return Appearance.value("appearanceLoadoutVariation", "Appearance_LoadoutVariation", true) ~= false
end

function Appearance.seedOf(actor)
    if type(actor) ~= "table" then return "" end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    return tostring(memory ~= nil and memory.identitySeed or actor.uid or "")
end

function Appearance.stateOf(seed)
    seed = tostring(seed)
    if seed == Appearance.lastSeed then return Appearance.lastState end
    local text = seed .. "|"
    local value = 7
    for index = 1, #text do value = (value * 131 + string.byte(text, index)) % 2147483647 end
    Appearance.lastSeed, Appearance.lastState = seed, value
    return value
end

function Appearance.unit(seed, purpose)
    local value = Appearance.stateOf(seed)
    for index = 1, #purpose do value = (value * 131 + string.byte(purpose, index)) % 2147483647 end
    value = (value * 48271) % 2147483647
    value = (value * 48271) % 2147483647
    return value / 2147483647
end

function Appearance.pick(list, unit, set)
    if list.sealed ~= true or list.filter ~= set then
        local sum = 0
        for _, row in ipairs(list) do
            if set == nil or set[row[1]] == true then sum = sum + row[2] end
        end
        list.sealed, list.filter, list.total = true, set, sum
    end
    local total = list.total
    if total <= 0 then return nil end
    local needle, last = unit * total, nil
    for _, row in ipairs(list) do
        if set == nil or set[row[1]] == true then
            last = row[1]
            needle = needle - row[2]
            if needle < 0 then return row[1] end
        end
    end
    return last
end

function Appearance.stamp(record)
    if type(record) ~= "table" or type(record.memory) ~= "table" or record.memory.lookV ~= nil then return false end
    if not Appearance.enabled() then return false end
    record.memory.lookV = 1
    return true
end

function Appearance.modeFor(profile, actor)
    if not Appearance.enabled() or type(profile) ~= "table" or type(actor) ~= "table" then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or nil
    if memory == nil or (tonumber(memory.lookV) or 0) < 1 then return nil end
    local general = type(profile.general) == "table" and profile.general or {}
    if general.lookFixed == true or general.lookVary == false then return "fixed" end
    if general.lookVary ~= true and profile.shippedProgression ~= true then return "fixed" end
    if Appearance.unit(Appearance.seedOf(actor), "keep") * 100 < Appearance.keepPercent() then return "kept" end
    return "varied"
end

function Appearance.styleSet(kind, female)
    local key = "beard"
    if kind ~= "beard" then key = female == true and "hairF" or "hairM" end
    local known = Appearance.styleSets[key]
    if known ~= nil then return known or nil end
    local reader = getAllHairStyles
    if kind == "beard" then reader = getAllBeardStyles end
    local set = nil
    if type(reader) == "function" then
        local ok, list = pcall(reader, female == true)
        if ok and list ~= nil and type(list.size) == "function" and type(list.get) == "function" and list:size() > 0 then
            set = {}
            for index = 0, list:size() - 1 do set[tostring(list:get(index))] = true end
        end
    end
    Appearance.styleSets[key] = set or false
    return set
end

function Appearance.channels(text)
    local r, g, b = string.match(tostring(text or ""), "^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
    if r == nil then return nil end
    return tonumber(r), tonumber(g), tonumber(b)
end

function Appearance.greyish(text)
    local r, g, b = Appearance.channels(text)
    return r ~= nil and math.abs(r - g) < 0.05 and math.abs(g - b) < 0.06
end

function Appearance.ageBand(general, hairColor)
    local tags = string.lower(tostring(general.tags or ""))
    if string.find(tags, "elder", 1, true) or string.find(tags, "retired", 1, true) then return "older" end
    local r, g, b = Appearance.channels(hairColor)
    if r ~= nil and Appearance.greyish(hairColor) and (r + g + b) / 3 >= 0.38 then return "older" end
    if string.find(tags, "student", 1, true) or string.find(tags, "trainee", 1, true)
            or string.find(tags, "recruit", 1, true) then return "young" end
    return "adult"
end

function Appearance.classOf(profile)
    if type(profile) ~= "table" then return "working" end
    local known = Appearance.classes[profile]
    if known ~= nil then return known end
    local data = ProjectALife.AppearanceData
    local progression = ProjectALife.LoadoutProgression
    local bloc = "civilian"
    if progression ~= nil and type(progression.classify) == "function" then
        local ok, _, found = pcall(progression.classify, profile)
        if ok and type(found) == "string" then bloc = found end
    end
    local class = "working"
    if data.uniformedBlocs[bloc] == true then class = "uniformed"
    elseif data.roughBlocs[bloc] == true then class = "rough" end
    Appearance.classes[profile] = class
    return class
end

function Appearance.beardShade(hairColor)
    local known = Appearance.shades[hairColor]
    if known ~= nil then return known end
    local r, g, b = Appearance.channels(hairColor)
    if r == nil then return hairColor end
    local shade
    if Appearance.greyish(hairColor) then shade = string.format("%.2f,%.2f,%.2f", r, g, b)
    else shade = string.format("%.2f,%.2f,%.2f", math.min(1, r * 0.88 + 0.015), g * 0.80, b * 0.76) end
    Appearance.shades[hairColor] = shade
    return shade
end

function Appearance.traits(profile, general, hairColor)
    local known = Appearance.traitRows[profile]
    if known ~= nil and known.tags == general.tags and known.hair == hairColor then return known.class, known.band end
    local class, band = Appearance.classOf(profile), Appearance.ageBand(general, hairColor)
    Appearance.traitRows[profile] = { class = class, band = band, tags = general.tags, hair = hairColor }
    return class, band
end

function Appearance.vary(plan, profile, actor)
    local data = ProjectALife.AppearanceData
    local seed = Appearance.seedOf(actor)
    local general = type(profile.general) == "table" and profile.general or {}
    local female = plan.female == true
    local class, band = Appearance.traits(profile, general, plan.hairColor)
    local tone = math.max(0, math.min(4, math.floor(tonumber(plan.skin) or 0)))
    if general.toneFixed ~= true then
        local unit = Appearance.unit(seed, "tone")
        if unit < 0.25 then tone = tone - 1 elseif unit >= 0.75 then tone = tone + 1 end
        tone = math.max(0, math.min(4, tone))
    end
    if tone ~= plan.skin then
        plan.skin = tone
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator ~= nil and type(hydrator.humanSkinTexture) == "function" then
            plan.skinTexture = hydrator.humanSkinTexture(female, tone)
        end
    end
    local textured = tone >= 3
    local pools = data.hair[female and "female" or "male"][band == "older" and "elder" or class]
    local style = Appearance.pick(textured and pools.textured or pools.plain, Appearance.unit(seed, "hair"),
        Appearance.styleSet("hair", female))
    if style ~= nil then plan.hairStyle = style end
    local tints = data.hairTints.adult
    if band == "older" then tints = textured and data.hairTints.darkOlder or data.hairTints.older
    elseif textured then tints = data.hairTints.dark
    elseif band == "young" then tints = data.hairTints.young end
    local tint = Appearance.pick(tints, Appearance.unit(seed, "tint"), nil)
    if tint ~= nil then plan.hairColor = tint end
    if female then
        plan.beardStyle, plan.beardColor = "", plan.hairColor
        return plan
    end
    local rules = data.beards[band == "older" and "elder" or (band == "young" and "young" or class)] or data.beards.working
    local chance = rules.chance
    if tostring(general.beardStyle or "") ~= "" then chance = math.max(chance, data.beards.authoredKeeps) end
    plan.beardStyle = ""
    if Appearance.unit(seed, "beardchance") < chance then
        plan.beardStyle = Appearance.pick(rules.styles, Appearance.unit(seed, "beard"), Appearance.styleSet("beard", false)) or ""
    end
    plan.beardColor = Appearance.beardShade(plan.hairColor)
    return plan
end

function Appearance.apply(plan, profile, actor)
    local mode = Appearance.modeFor(profile, actor)
    plan.lookMode = mode
    if mode == nil then return false end
    if mode == "varied" then Appearance.vary(plan, profile, actor) end
    return true
end

function Appearance.dye(plan, actor)
    local data = ProjectALife.AppearanceData
    local seed = Appearance.seedOf(actor)
    for _, entry in ipairs(plan.clothing) do
        if type(entry) == "table" and (entry.tint == nil or entry.tint == "") and data.tintable[entry.itemType] == true then
            local group = data.dye[data.dyeClass[tostring(entry.slot)] or "tops"]
            local color = Appearance.pick(group, Appearance.unit(seed, tostring(entry.slot) .. ":" .. tostring(entry.itemType) .. "|dye"), nil)
            if color ~= nil then entry.tint = color end
        end
    end
    return plan
end

function Appearance.finish(plan, profile, actor, selected)
    if type(plan) ~= "table" or not Appearance.enabled() then return plan end
    local collisions = ProjectALife.OutfitCollisions
    plan.collisionsResolved = 0
    if collisions ~= nil and type(collisions.resolve) == "function" and type(plan.clothing) == "table" then
        local ok, count = pcall(collisions.resolve, plan, selected, Appearance.seedOf(actor))
        if ok then plan.collisionsResolved = tonumber(count) or 0 end
    end
    if plan.lookMode == "varied" and type(plan.clothing) == "table" then Appearance.dye(plan, actor) end
    return plan
end

function Appearance.note(plan)
    local counters = Appearance.counters
    counters.spawns = counters.spawns + 1
    local mode = type(plan) == "table" and plan.lookMode or nil
    if mode == "varied" then counters.varied = counters.varied + 1
    elseif mode == "kept" then counters.kept = counters.kept + 1
    elseif mode == "fixed" then counters.fixed = counters.fixed + 1
    else counters.legacy = counters.legacy + 1 end
    counters.collisions = counters.collisions + (type(plan) == "table" and tonumber(plan.collisionsResolved) or 0)
end

function Appearance.qaLine()
    local counters = Appearance.counters
    local draw = ProjectALife.RosterDraw
    local avoided = type(draw) == "table" and type(draw.metrics) == "table" and tonumber(draw.metrics.avoided) or 0
    return "[ALIFE-QA] Appearance: spawns=" .. counters.spawns .. " varied=" .. counters.varied
        .. " keptAuthored=" .. counters.kept .. " fixed=" .. counters.fixed
        .. " collisionsResolved=" .. counters.collisions .. " rosterRepeatsAvoided=" .. avoided
        .. " legacy=" .. counters.legacy
end

return Appearance
