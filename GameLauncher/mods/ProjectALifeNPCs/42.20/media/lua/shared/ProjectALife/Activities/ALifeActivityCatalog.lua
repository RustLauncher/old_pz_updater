ProjectALife = ProjectALife or {}

local Catalog = {

    enabledDefault = false,
}
ProjectALife.ActivityCatalog = Catalog

Catalog.NEEDS = { "food", "water", "ammo", "meds" }

Catalog.activities = {
    scavenge = {
        serves = { food = 0.6, water = 0.5, ammo = 0.6, meds = 0.6 }, base = 3,
        expedition = true, task = "scavenge", loaded = true, offline = true, built = true, lane = "1a",
        requires = { "scavenger_crew" }, duration = { 1, 3 },
    },
    hunt = {
        serves = { food = 1 }, base = 2, dawnDusk = 2, weather = { rain = -1, fog = -3 },
        expedition = true, task = "hunt", module = true, lane = "1b", duration = { 1, 3 },
        built = true, offline = true, loaded = true,
    },
    fish = {
        serves = { food = 0.9 }, base = 2, dawnDusk = 1.5, weather = { rain = 1, fog = -1, wind = -1 },
        expedition = true, task = "fish", module = true, lane = "1b", duration = { 1, 2 },
        built = true, offline = true, loaded = true,
    },
    forage = {
        serves = { food = 0.5, meds = 0.2 }, base = 1, weather = { rain = -2 },
        expedition = true, task = "forage", module = true, lane = "2", duration = { 1, 2 },
        entry = true, chore = "forage",
    },
    fetch_water = {
        serves = { water = 1 }, base = 1, expedition = true, task = "fetch_water",
        module = true, lane = "2", duration = { 0.5, 1 },
        entry = true, chore = "water",
    },
    chop_camp = { entry = true, built = true, chore = "firewood", duration = { 1, 2 } },
    build_camp = { entry = true, built = true, chore = "crate", duration = { 1, 2 } },
    return_base = {
        serves = {}, base = 0, shelter = true, night = true, task = "haven", lane = "1c", duration = { 0.5, 2 },
        built = true, loaded = true, always = true,
    },
    establish_haven = {
        serves = {}, base = 1, task = "haven", lane = "1c", duration = { 1, 2 },
    },
    haven_idle = {
        serves = {}, base = 1.5, night = true, shelter = true, rest = true, task = "haven",
        lane = "1c", duration = { 1, 3 }, built = true, loaded = true, always = true,
    },
    patrol_route = {
        serves = {}, base = 1.5, task = "patrol", offline = true, built = true, lane = "1a",
        requires = { "patrol", "town_patrol" }, duration = { 1, 3 },
    },
    travel = {
        serves = {}, base = 1, weather = { rain = -2 }, expedition = true, task = "travel",
        offline = true, built = true, lane = "1a", requires = { "roamer" }, duration = { 1, 4 },
    },
    fortify = {
        serves = {}, base = 1.5, shelter = true, task = "fortify", offline = true, built = true,
        lane = "1a", requires = { "scavenger_crew", "roamer", "poi_defenders" }, minSupplies = 25,
        noRepeat = true, duration = { 1, 2 },
    },
    camp = {
        serves = {}, base = 1, night = true, shelter = true, rest = true, task = "rest",
        loaded = true, offline = true, built = true, lane = "1a", duration = { 1, 2 },
    },

    repair_vehicle = { entry = true, built = true },
    defend_scene = { entry = true, built = true },
    assault = { entry = true, built = true },
    installation = { entry = true, hold = true, built = true },
    mission = { entry = true, hold = true, built = true },
}

Catalog.order = {
    "scavenge", "hunt", "fish", "return_base", "establish_haven",
    "patrol_route", "travel", "fortify", "camp", "haven_idle",
}

function Catalog.get(id)
    if id == nil then return nil end
    return Catalog.activities[id]
end

function Catalog.isEntry(id)
    local row = Catalog.activities[id]
    return row ~= nil and row.entry == true
end

function Catalog.sandbox(key)
    if type(SandboxVars) ~= "table" or type(SandboxVars.ALife) ~= "table" then return nil end
    return SandboxVars.ALife[key]
end

function Catalog.enabled()
    local value = Catalog.sandbox("Activities_Enabled")
    if type(value) == "boolean" then return value end
    return Catalog.enabledDefault == true
end

function Catalog.setting(name, fallback)
    local settings = ProjectALife.Settings
    if type(settings) ~= "table" or type(settings.current) ~= "table" then return fallback end
    local value = settings.current["activities" .. name]
    if value == nil then return fallback end
    return value
end

return Catalog
