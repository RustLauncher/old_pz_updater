ProjectALife = ProjectALife or {}

local Encounters = {}
ProjectALife.Encounters = Encounters

Encounters.onlyId = nil

Encounters.definitions = {
    {
        id = "safehouse_visit", label = "Safehouse visitor",
        summary = "An uninvited visitor waiting outside a resident's door.",
        weight = 0, minCount = 1, maxCount = 1, locations = { "anywhere" },
        timeOfDay = { "day" }, mode = "roam", profile = "patrol", stance = "visit",
        trigger = "safehouse_director", conducts = {},
    },
    {
        id = "patrol",
        label = "Patrol",
        summary = "A small armed group walking a real circuit, abreast, pausing at the corners. Warns before it shoots.",
        weight = 30,
        minCount = 2, maxCount = 4,
        locations = { "city", "outside_city" },
        timeOfDay = { "day" },
        mode = "patrol", profile = "patrol",
        conducts = {},

        stance = "route",
        routeRadius = 22,
    },
    {
        id = "raid",
        label = "Hostile Scouts",
        summary = "An attacking group that pushes at the nearest players.",
        weight = 15,
        minCount = 3, maxCount = 5,
        locations = { "city" },
        timeOfDay = { "day", "night" },
        mode = "assault", profile = "seek_destroy",
        conducts = { "leader", "gunner" },
    },
    {
        id = "fullscale_raid",
        label = "Full-scale raid",
        summary = "A big, sustained, coordinated push. Rare and loud.",
        weight = 4,
        minCount = 6, maxCount = 8,
        locations = { "city" },
        timeOfDay = { "night", "evening" },
        mode = "full_raid", profile = "seek_destroy",
        conducts = { "leader", "medic" },
        trigger = "raid_director",
    },
    {
        id = "car_crash",
        label = "Road crash",
        summary = "A wreck on the road and the survivors of it -- any faction's people.",
        weight = 0,
        minCount = 2, maxCount = 2,
        locations = { "city", "outside_city" },
        timeOfDay = { "day", "night" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        stance = "defend",
        placement = "road",
        scene = "carCrash",

        awareness = 0.7,
        trigger = "meta_director",
    },
    {
        id = "assassination",
        label = "Assassination squad",
        summary = "A tracker and a rifle: quiet approach, one loud second.",
        weight = 6,
        minCount = 2, maxCount = 3,
        locations = { "anywhere" },
        timeOfDay = { "night", "evening" },
        mode = "manhunt", profile = "manhunt",
        conducts = { "stealth", "sniper" },
    },

    {
        id = "blockade",
        label = "Blockade",
        summary = "Cars across the road and a line of guns behind them, holding the crossing. They do not chase far.",
        weight = 12,
        minCount = 3, maxCount = 5,
        locations = { "outside_city", "city" },
        timeOfDay = { "day", "night" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        stance = "blockade",
        placement = "road",

        scene = "blockade",

        awareness = 1,
    },
    {
        id = "highway_ambush",
        label = "Highway ambush",
        summary = "Hidden guns on both shoulders of a road, holding fire until something drives into the middle.",
        weight = 8,
        minCount = 3, maxCount = 6,
        locations = { "outside_city" },
        timeOfDay = { "day", "night" },
        mode = "guard", profile = "patrol",
        conducts = { "ambusher", "ambusher", "ambusher", "ambusher", "ambusher", "ambusher" },
        stance = "blockade",
        placement = "road",

        trigger = "vehicle_distance",
    },
    {
        id = "rooftop_snipers",
        label = "Rooftop shooters",
        summary = "A pair of rifles on an upper floor, working the street below and refusing to come down.",
        weight = 7,
        minCount = 2, maxCount = 3,
        locations = { "city" },
        timeOfDay = { "day", "morning", "midday" },
        mode = "guard", profile = "patrol",
        conducts = { "sniper", "sniper", "sniper" },
        stance = "occupy_high",
        placement = "upper_building",
    },
    {
        id = "poi_defenders",
        label = "Station garrison",
        summary = "A crew that has taken somewhere worth taking -- a station, a warehouse -- and means to keep it.",
        weight = 8,
        minCount = 3, maxCount = 5,
        locations = { "city" },
        timeOfDay = { "day", "night" },
        mode = "guard", profile = "patrol",
        conducts = { "leader", "medic" },
        stance = "defend",
        placement = "poi",

        poi = { "police", "fire", "guns", "medical", "warehouse" },
        persistent = true,

        modules = { withdraw = "off", flee = "off" },
    },
    {
        id = "broken_car",
        label = "Broken-down car",
        summary = "A dead engine, an empty tank, one pair of hands under the bonnet and the rest of them watching the road.",
        weight = 10,
        minCount = 3, maxCount = 4,
        locations = { "outside_city", "city" },
        timeOfDay = { "day", "morning", "midday", "evening" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        stance = "repair",
        roles = { "mechanic" },
        placement = "road",

        awareness = 0.4,
        roleAwareness = { mechanic = 0.2 },

        scene = "brokenCar",
        wreck = true,
    },
    {
        id = "town_patrol",
        label = "Town patrol route",
        summary = "A circuit of the same four corners, walked all day. Predictable on purpose: it can be learned.",
        weight = 14,
        minCount = 2, maxCount = 4,
        locations = { "city" },
        timeOfDay = { "day", "night" },
        mode = "patrol", profile = "patrol",
        conducts = { "leader" },
        stance = "route",
        placement = "town",

        routeRadius = 26,
    },
    {
        id = "scavenger_crew",
        label = "Scavenger crew",
        summary = "A crew out for one thing -- medicine, food, ammunition or tools -- working a street house by house behind its leader, in through doors only.",
        weight = 25,
        minCount = 2, maxCount = 4,
        locations = { "city" },
        timeOfDay = { "day", "morning", "midday" },
        mode = "scavenge", profile = "scavenger",
        conducts = { "leader" },
        placement = "town",
    },
    {
        id = "fishing_party",
        label = "Fishing party",
        summary = "A few people with rods at the water's edge, working the bank for a meal. They pack up when the day's catch is in.",
        weight = 6,
        minCount = 2, maxCount = 3,
        locations = { "outside_city", "city" },
        timeOfDay = { "morning", "midday", "evening" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "shore",
        activity = "fish", activityNext = "scavenge", activityStart = true,
    },
    {
        id = "hunting_party",
        label = "Hunting party",
        summary = "Two or three hunters working the tree line for game, quiet and spread out. They head back once there is meat.",
        weight = 5,
        minCount = 2, maxCount = 3,
        locations = { "outside_city" },
        timeOfDay = { "morning", "evening" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "clearing",
        activity = "hunt", activityNext = "scavenge", activityStart = true,
    },
    {
        id = "foraging_party",
        label = "Foraging party",
        summary = "People bent low in a clearing, picking over the ground for anything edible or useful.",
        weight = 5,
        minCount = 2, maxCount = 4,
        locations = { "outside_city" },
        timeOfDay = { "morning", "midday" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "clearing",
        activity = "forage", activityNext = "scavenge", activityStart = true,
    },
    {
        id = "firewood_camp",
        label = "Firewood camp",
        summary = "A working camp: one swings the axe, another saws the logs into planks, and the stack grows while you watch.",
        weight = 4,
        minCount = 2, maxCount = 3,
        locations = { "outside_city" },
        timeOfDay = { "morning", "midday", "evening" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "clearing",
        activity = "chop_camp", activityNext = "scavenge", activityStart = true,
    },
    {
        id = "camp_builders",
        label = "Camp builders",
        summary = "A crew nailing a storage crate together out of planks and a borrowed hammer.",
        weight = 3,
        minCount = 2, maxCount = 3,
        locations = { "outside_city" },
        timeOfDay = { "morning", "midday", "evening" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "clearing",
        activity = "build_camp", activityNext = "scavenge", activityStart = true,
    },
    {
        id = "scavenging_trip",
        label = "Scavenging trip",
        summary = "A crew sent out from its base for a shopping list. They work the street and carry what they find home.",
        weight = 8,
        minCount = 2, maxCount = 4,
        locations = { "city" },
        timeOfDay = { "morning", "midday" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "town",
        activity = "scavenge", activityNext = "return_base", activityStart = true,
    },
    {
        id = "water_run",
        label = "Water run",
        summary = "Two people with empty bottles walking to the nearest water and back.",
        weight = 4,
        minCount = 2, maxCount = 3,
        locations = { "outside_city", "city" },
        timeOfDay = { "morning", "midday", "evening" },
        mode = "guard", profile = "patrol",
        conducts = { "leader" },
        placement = "shore",
        activity = "fetch_water", activityNext = "scavenge", activityStart = true,
    },
    {
        id = "outpost",
        label = "Building residents (NPCs only)",
        summary = "People who live here. They hold the inside of the building, they do not breach out, and they do not leave.",
        weight = 6,
        minCount = 4, maxCount = 6,
        locations = { "outside_city", "city" },
        timeOfDay = { "day", "night" },
        mode = "guard", profile = "patrol",
        conducts = { "leader", "medic" },
        stance = "garrison",
        placement = "building",
        persistent = true,

        admin = { leash = 10, doctrine = "fireteam" },
    },
}

Encounters.activityDefaults = {
    safehouse_visit = { activity = "mission", activityHold = true },
    patrol = { activity = "patrol_route" },
    town_patrol = { activity = "patrol_route" },
    raid = { activity = "assault", activityNext = "travel" },
    fullscale_raid = { activity = "mission", activityHold = true },
    car_crash = { activity = "defend_scene", activityNext = "scavenge" },
    assassination = { activity = "mission", activityHold = true },
    blockade = { activity = "installation", activityHold = true },
    highway_ambush = { activity = "installation", activityHold = true },
    rooftop_snipers = { activity = "installation", activityHold = true },
    poi_defenders = { activity = "installation", activityHold = true },
    broken_car = { activity = "repair_vehicle", activityNext = "scavenge" },
    scavenger_crew = { activity = "scavenge", activityNext = "return_base" },
    outpost = { activity = "installation", activityHold = true },
}

for _, definition in ipairs(Encounters.definitions) do
    local row = Encounters.activityDefaults[definition.id]
    if row ~= nil then
        if definition.activity == nil then definition.activity = row.activity end
        if definition.activityNext == nil then definition.activityNext = row.activityNext end
        if definition.activityHold == nil then definition.activityHold = row.activityHold end
    end
end

function Encounters.adminDefaults(definition)
    local values = { doctrine = "profile", role = "profile", hostility = "profile",
        placement = "here", stationary = "false", leash = "0" }
    if type(definition) ~= "table" then return values end
    local admin = type(definition.admin) == "table" and definition.admin or {}
    if definition.placement ~= nil then values.placement = "rule" end
    local leash = tonumber(admin.leash)
    if leash == nil and (definition.stance == "garrison" or definition.stance == "holdout") then
        leash = 10
    end
    if leash ~= nil then values.leash = tostring(math.floor(leash)) end
    if admin.stationary == true or definition.stance == "occupy_high" then
        values.stationary = "true"
    end
    if admin.hostility ~= nil then values.hostility = tostring(admin.hostility) end
    if admin.doctrine ~= nil then values.doctrine = tostring(admin.doctrine) end
    if admin.role ~= nil then values.role = tostring(admin.role) end
    return values
end

function Encounters.slotForHour(hour)
    hour = tonumber(hour) or 12
    if hour >= 5 and hour < 11 then return "morning" end
    if hour >= 11 and hour < 16 then return "midday" end
    if hour >= 16 and hour < 21 then return "evening" end
    return "night"
end

function Encounters.timeAllowed(definition, hour)
    local slots = definition.timeOfDay
    if type(slots) ~= "table" or #slots == 0 then return true end
    local fine = Encounters.slotForHour(hour)
    local day = fine ~= "night"
    for _, slot in ipairs(slots) do
        if slot == fine then return true end
        if slot == "noon" and fine == "midday" then return true end
        if slot == "day" and day then return true end
        if slot == "night" and not day then return true end
    end
    return false
end

function Encounters.partyScale()
    local catalog = ProjectALife.ActivityCatalog
    if catalog == nil or type(catalog.enabled) ~= "function" or type(catalog.setting) ~= "function"
            or not catalog.enabled() then return 0 end
    return math.max(0, math.min(500, tonumber(catalog.setting("PartyWeight", 100)) or 100)) / 100
end

function Encounters.pick(hour, roll, allowed)
    local total, legal = 0, {}
    for _, definition in ipairs(Encounters.definitions) do
        local weight = tonumber(definition.weight) or 0

        if definition.trigger ~= nil then weight = 0 end
        if definition.activityStart == true then weight = weight * Encounters.partyScale() end

        if Encounters.onlyId ~= nil and definition.id ~= Encounters.onlyId then
            weight = 0
        end
        if weight > 0 and Encounters.timeAllowed(definition, hour)
                and (allowed == nil or allowed(definition) == true) then
            total = total + weight
            legal[#legal + 1] = { definition = definition, weight = weight }
        end
    end
    if total <= 0 then return nil end
    local point = (tonumber(roll) or 0) % total
    for _, entry in ipairs(legal) do
        point = point - entry.weight
        if point < 0 then return entry.definition end
    end
    return legal[#legal].definition
end

function Encounters.get(id)
    for _, definition in ipairs(Encounters.definitions) do
        if definition.id == id then return definition end
    end
    return nil
end

function Encounters.list()
    local result = {}
    for _, definition in ipairs(Encounters.definitions) do

        local live = Encounters.onlyId == nil
            or definition.id == Encounters.onlyId
        result[#result + 1] = {
            id = definition.id, label = definition.label,
            summary = definition.summary,
            weight = live and definition.weight or 0,
            suppressed = not live or nil,
        }
    end
    return result
end

Encounters.refusalTexts = {
    no_shore_near = "No lake or river bank within 32 tiles of the spot. Stand at the water's edge.",
    no_clearing_near = "No open ground within 36 tiles (no building, road or tree line). Move out of town.",
    no_road_near = "No paved road within 36 tiles. Stand on or beside a road.",
    no_town_near = "No town within 36 tiles. Stand inside a town.",
    no_building_near = "No building within 36 tiles. Stand next to a building.",
    no_upper_floor_near = "No building with an upper floor within 36 tiles.",
    no_upper_building_near = "No building with an upper floor within 36 tiles.",
    no_poi_near = "No matching station, shop or warehouse within 72 tiles.",
    no_site_rule = "This encounter has no placement rule. Use 'placed here'.",
    site_error = "The site search failed. Use 'placed here' and report it.",
    unknown_encounter = "That encounter id is not known to the server.",
    hostile_profile_not_found = "No profile fits that squad and faction.",
    no_hostile_profiles = "The catalog has no profile to cast for this encounter.",
    faction_has_no_members = "That faction has no profiles to cast.",
    faction_has_no_hostiles = "That faction has no hostile profiles to cast.",
    visitor_only_faction = "That faction only appears as visitors at a door. Spawn it as a visitor.",
    profile_invalid = "The cast profile is invalid or its faction is gone.",
    spawn_queue_full = "The spawn queue is full. Wait a few seconds.",
    spawn_queue_capacity = "Not enough room in the spawn queue for the whole scene.",
    spawn_origin_invalid = "The spawn point is not valid.",
    player_position_unavailable = "The server cannot read your position.",
    scene_kit_unavailable = "The scene builder is not loaded.",
    raid_director_unavailable = "The raid director is not loaded.",
    car_crash_site_unavailable = "No clear paved stretch for a wreck here. Stand on a straight open road.",
    broken_car_site_unavailable = "No clear paved stretch for a broken-down car here. Stand on an open road.",
    blockade_site_unavailable = "No clear road for a blockade here. Stand on a straight road with free shoulders.",
    camp_site_unavailable = "No open ground for the camp layout (about 12 by 8 free tiles). Try a field.",
    raid_active = "A raid is already running against that player.",
    target_missing = "The raid has no target player.",
    target_unavailable = "The raid target position is not available.",
    faction_raid_policy = "That faction's raid policy does not allow a raid.",
    hostile_profiles_missing = "No hostile profiles are available for the raid.",
    approach_unavailable = "No approach route for the raid was found.",
    wave_position_unavailable = "No position for the raid wave was found.",
    group_outcome_unavailable = "The raid group could not be tracked.",
    spawn_service_unavailable = "The spawn service is not ready.",
    buildup_active = "The raid is still building up.",
    scene_not_authoritative = "Only the server can build scenes.",
    scene_point_missing = "The scene has no position.",
    scene_already_placed = "A scene already stands on this spot.",
    square_water = "That square is water.",
    square_blocked = "That square is blocked or occupied.",
    square_unloaded = "That square is not loaded. Stand closer.",
    inside_safehouse = "That spot is inside a protected safehouse.",
    inside_player_base = "That spot is inside a player base.",
    inside_no_spawn_zone = "That spot is inside a no-spawn zone.",
    too_close_to_player = "That spot is too close to a player.",
    in_player_view = "That spot is in a player's view.",
    spawn_square_unavailable = "No free square near the spot for this squad.",
    diagnostics_disabled = "Debug tools are switched off.",
    admin_required = "Admin access is required.",
    rate_limited = "Too many requests. Wait a moment.",
    runtime_not_started = "The A-Life runtime has not started yet.",
    catalog_unavailable = "The faction catalog is not ready.",
}

function Encounters.refusalText(reason)
    reason = tostring(reason or "unknown")
    local direct = Encounters.refusalTexts[reason]
    if direct ~= nil then return direct end
    local kind = string.match(reason, "^no_placement:(.+)$")
    if kind ~= nil then
        local named = Encounters.refusalTexts["no_" .. kind .. "_near"]
        if named ~= nil then return named end
        return "No site for the '" .. kind .. "' placement rule near the spot. Use 'placed here'."
    end
    return reason
end

return Encounters
