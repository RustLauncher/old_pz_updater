require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Outposts/ALifeOutpostRegistry"
require "ProjectALife/Core/ALifeDayCycle"
require "ProjectALife/Senses/ALifeAwareness"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Sites = ProjectALife.OutpostRegistry
local DayCycle = ProjectALife.DayCycle
local Awareness = ProjectALife.Awareness

local Hold = {
    settings = {
        beatMs = 4000,

        wallRadius = 4,
        liftMs = 60000,

        sweepRadius = 20,
        sweepHours = 1.5,
    },
    metrics = { nights = 0, dawns = 0, lifts = 0, sweeps = 0 },
    adapters = {},
}
ProjectALife.ModuleNightHold = Hold

local function memoryOf(actor)
    return type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
end

local function worldHours()
    if type(Hold.adapters.worldHours) == "function" then return Hold.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return tonumber(hours) or 0
end

function Hold.isNight()
    return DayCycle ~= nil and DayCycle.isNight() == true
end

function Hold.siteIdOf(actor)
    local memory = memoryOf(actor)
    if memory.outpostSquadId ~= nil then return nil end
    if type(memory.outpostId) == "string" then return memory.outpostId end
    return nil
end

function Hold.playerAtWalls(bounds, players, radius)
    if type(bounds) ~= "table" then return false end
    radius = tonumber(radius) or Hold.settings.wallRadius
    for _, p in ipairs(players or {}) do
        local dx = math.max(bounds.x1 - p.x, 0, p.x - bounds.x2)
        local dy = math.max(bounds.y1 - p.y, 0, p.y - bounds.y2)
        if dx * dx + dy * dy <= radius * radius then return true end
    end
    return false
end

function Hold.widen(bounds, by)
    if type(bounds) ~= "table" then return nil end
    by = tonumber(by) or 0
    return { x1 = bounds.x1 - by, y1 = bounds.y1 - by, x2 = bounds.x2 + by, y2 = bounds.y2 + by, z = bounds.z }
end

local function players()
    if type(Hold.adapters.players) == "function" then return Hold.adapters.players() or {} end
    local result = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        for _, player in ipairs(locator.list() or {}) do
            local position = locator.position(player)
            if position ~= nil then result[#result + 1] = { x = position.x, y = position.y } end
        end
    end)
    return result
end

local function siteOf(siteId)
    if type(Hold.adapters.site) == "function" then return Hold.adapters.site(siteId) end
    if Sites == nil or type(Sites.read) ~= "function" then return nil end
    return Sites.read(siteId)
end

local function presetClass(site)
    if site == nil then return nil end
    local presets = ProjectALife.OutpostPresets
    local preset = presets ~= nil and type(presets.get) == "function" and presets.get(site.presetId) or nil
    return preset ~= nil and preset.class or nil
end

function Hold.evaluate(actor, shell, context)
    if type(actor) ~= "table" or type(context) ~= "table" then return nil end
    local memory = memoryOf(actor)
    local now = tonumber(context.now) or 0
    if now < (tonumber(memory.nightHoldNextAtMs) or 0) then return nil end
    context.persistMemory(actor, "nightHoldNextAtMs", now + Hold.settings.beatMs)
    local siteId = Hold.siteIdOf(actor)
    if siteId == nil then return nil end
    local site = siteOf(siteId)
    if site == nil or presetClass(site) ~= "building" then return nil end
    local settings = Hold.settings
    local night = Hold.isNight()
    local hours = worldHours()
    if night then

        context.persistMemory(actor, "quietIndoorsUntilMs", now + Hold.settings.beatMs * 4)
        if memory.nightHold ~= true then

            context.persistMemory(actor, "nightHold", true)
            context.persistMemory(actor, "quietIndoors", true)
            context.persistMemory(actor, "garrisonRest", true)
            context.persistMemory(actor, "nightHoldAwarenessHome", memory.stanceAwareness)
            context.persistMemory(actor, "stanceAwareness", Awareness.forRole("houseNight", memory))
            Hold.metrics.nights = Hold.metrics.nights + 1
        end

        if Hold.playerAtWalls(site.bounds, players(), settings.wallRadius) then
            if now >= (tonumber(memory.quietLiftedUntilMs) or 0) then
                Hold.metrics.lifts = Hold.metrics.lifts + 1
            end
            context.persistMemory(actor, "quietLiftedUntilMs", now + settings.liftMs)
        end
        return nil
    end
    if memory.nightHold == true then

        context.persistMemory(actor, "nightHold", nil)
        context.persistMemory(actor, "quietIndoors", nil)
        context.persistMemory(actor, "quietIndoorsUntilMs", nil)
        context.persistMemory(actor, "garrisonRest", nil)
        context.persistMemory(actor, "quietLiftedUntilMs", nil)
        context.persistMemory(actor, "stanceAwareness", memory.nightHoldAwarenessHome)
        context.persistMemory(actor, "nightHoldAwarenessHome", nil)
        local home = memory.garrisonBounds
        if type(home) == "table" then
            context.persistMemory(actor, "nightHoldHomeBounds", home)
            context.persistMemory(actor, "garrisonBounds", Hold.widen(home, settings.sweepRadius))
        end
        context.persistMemory(actor, "sweepUntilHours", hours + settings.sweepHours)
        Hold.metrics.dawns = Hold.metrics.dawns + 1
        Hold.metrics.sweeps = Hold.metrics.sweeps + 1
        return nil
    end

    local sweepUntil = tonumber(memory.sweepUntilHours)
    if sweepUntil ~= nil and hours >= sweepUntil then
        if type(memory.nightHoldHomeBounds) == "table" then
            context.persistMemory(actor, "garrisonBounds", memory.nightHoldHomeBounds)
        end
        context.persistMemory(actor, "nightHoldHomeBounds", nil)
        context.persistMemory(actor, "sweepUntilHours", nil)
    end
    return nil
end

function Hold.reset()
    Hold.metrics = { nights = 0, dawns = 0, lifts = 0, sweeps = 0 }
    return true
end

Registry.register({
    id = "nightHold",
    kind = "upkeep",
    dispatch = "decision",

    priority = 79,
    label = "Hold the house at night",
    summary = "A house crew goes quiet after dark -- sits, eats, talks, ignores the dead outside -- wakes when a player comes to the walls, and clears the yard at dawn.",
    defaultEnabled = true,
    evaluate = Hold.evaluate,
})

return Hold
