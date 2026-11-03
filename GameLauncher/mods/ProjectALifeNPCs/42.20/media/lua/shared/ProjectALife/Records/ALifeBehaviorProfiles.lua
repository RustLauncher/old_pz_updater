ProjectALife = ProjectALife or {}

local Profiles = { adapters = {} }
ProjectALife.BehaviorProfiles = Profiles

local ALL_OVERLAYS = {
    "scavenge",      
    "investigate",   
    "regroup",       
    "groupMarch",    
    "patrolAnchor",  
    "flee",          
    "orders",        

    "cover",         
    "withdraw",      
    "healing",       
    "gunner",        
    "leader",        
    "sniper",        
    "medic",         
    "ambusher",      
    "stealth",       
    "weave",         
    "spread",        
    "stance",        
    "strafe",        
    "flanking",      

    "idleLife",      
    "search",        
    "patrolRest",    
    "radioman",      
    "panic",
    "fear",
    "gunFear",
    "careful",
    "fortify",
    "nightHold",
    "doorstack",
    "cqbsweep",
    "talk",
    "robbery",
    "activity",
    "home",
    "plan",
    "meleeFootwork",
    "meleeFlank",
    "meleeBreach",
    "meleeIntimidate",
    "meleeCaution",
    "zombieAvoid",
    "warning",
    "weaponSwitchMelee",
    "visitorLife",
}
Profiles.overlayNames = ALL_OVERLAYS

local UNIVERSAL_OVERLAYS = {
    "idleLife", "search", "radioman", "panic", "fear", "gunFear", "careful", "fortify", "nightHold", "doorstack", "cqbsweep",

    "talk", "robbery", "warning",

    "strafe", "flanking", "zombieAvoid",
    "plan",
    "activity",
    "home",
    "weaponSwitchMelee",
    "visitorLife",
}
Profiles.universalOverlays = UNIVERSAL_OVERLAYS

local definitions = {
    {
        id = "seek_destroy",
        label = "Roaming hostile (Scout)",
        summary = "Roams between contacts, then hunts the nearest hostile and keeps pressure on it.",

        mode = "assault",

        roamWhenIdle = true,
        overlays = { orders = true, spread = true, stance = true, patrolRest = true, flee = true, cover = true, withdraw = true, healing = true, weave = true, gunner = true, leader = true, sniper = true, medic = true, ambusher = true, stealth = true, strafe = true },
    },
    {
        id = "patrol",
        label = "Area patrol",
        summary = "Holds a route around its anchor and warns players off.",
        mode = "patrol",
        roamWhenIdle = false,
        overlays = { orders = true, spread = true, stance = true, patrolRest = true, patrolAnchor = true, flee = true,
            investigate = true, cover = true, withdraw = true, healing = true, weave = true, gunner = true, leader = true, sniper = true, medic = true, ambusher = true, stealth = true, strafe = true },
    },
    {
        id = "scavenger",
        label = "Scavenger",
        summary = "Works containers for supplies and investigates noises.",
        mode = "scavenge",
        roamWhenIdle = true,
        overlays = { orders = true, spread = true, stance = true, scavenge = true, regroup = true, groupMarch = true, investigate = true,
            flee = true, cover = true, withdraw = true, healing = true, weave = true, gunner = true, leader = true, sniper = true, medic = true, ambusher = true, stealth = true, strafe = true },
    },
    {
        id = "squad",
        label = "Squad member",
        summary = "Moves and fights as part of a group.",
        mode = "assault",
        roamWhenIdle = true,
        overlays = { orders = true, spread = true, stance = true, patrolRest = true, regroup = true, groupMarch = true, flee = true,
            investigate = true, cover = true, withdraw = true, healing = true, weave = true, gunner = true, leader = true, sniper = true, medic = true, ambusher = true, stealth = true, strafe = true },
    },
    {
        id = "manhunt",
        label = "Manhunt",
        summary = "Tracks players specifically and re-engages relentlessly.",
        mode = "manhunt",
        roamWhenIdle = true,
        overlays = { orders = true, spread = true, stance = true, investigate = true, flee = true, cover = true, withdraw = true, healing = true, weave = true, gunner = true, leader = true, sniper = true, medic = true, ambusher = true, stealth = true, strafe = true },
    },
    {
        id = "test_all",
        label = "TEST -- every module",
        summary = "Permits every behaviour module at once. For testing only.",
        mode = "assault",
        roamWhenIdle = true,

        overlays = {},
    },
}

for _, definition in ipairs(definitions) do
    if definition.id == "test_all" then
        for _, overlay in ipairs(ALL_OVERLAYS) do
            definition.overlays[overlay] = true
        end
    end
    for _, overlay in ipairs(UNIVERSAL_OVERLAYS) do
        definition.overlays[overlay] = true
    end
end

Profiles.definitions = definitions
Profiles.defaultId = "seek_destroy"

local byId = {}
for _, profile in ipairs(definitions) do byId[profile.id] = profile end

local resolved = {}

function Profiles.get(id)
    if id == nil then return nil end
    local hit = resolved[id]
    if hit ~= nil then return hit or nil end
    local profile = byId[string.lower(tostring(id))]

    resolved[id] = profile or false
    return profile
end

function Profiles.list()
    local result = {}
    for _, profile in ipairs(definitions) do
        result[#result + 1] = {
            id = profile.id, label = profile.label, summary = profile.summary,
        }
    end
    return result
end

local defaultProfile

function Profiles.forActor(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    local id = type(memory) == "table" and memory.behaviorProfile or nil
    if id == nil then
        defaultProfile = defaultProfile or byId[Profiles.defaultId]
        return defaultProfile
    end
    local profile = Profiles.get(id)
    if profile ~= nil then return profile end
    defaultProfile = defaultProfile or byId[Profiles.defaultId]
    return defaultProfile
end

function Profiles.allows(actor, overlay)
    local profile = Profiles.forActor(actor)
    if profile == nil then return false end
    return profile.overlays[overlay] == true
end

function Profiles.mode(actor)
    local profile = Profiles.forActor(actor)
    return profile ~= nil and profile.mode or nil
end

function Profiles.roamWhenIdle(actor)
    local profile = Profiles.forActor(actor)
    return profile ~= nil and profile.roamWhenIdle == true
end

return Profiles
