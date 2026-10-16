ProjectALife = ProjectALife or {}

local Presets = { list = {}, byId = {} }
ProjectALife.OutpostPresets = Presets

Presets.Stores = {
    munitions = {
        { "Base.Bullets9mm", 6, 15 }, { "Base.556Bullets", 4, 20 },
        { "Base.ShotgunShells", 4, 8 }, { "Base.Bullets45", 3, 12 },
        { "Base.308Bullets", 2, 10 }, { "Base.Bullets38", 3, 12 },
    },

    rations = {
        { "Base.WaterRationCan", 5, 2 }, { "Base.Crackers", 4, 2 },
        { "Base.DehydratedMeatStick", 3, 2 }, { "Base.PeanutButter", 3, 1 },
        { "Base.DriedBlackBeans", 2, 1 }, { "Base.CannedMilk", 1, 1 },
    },

    medicine = {
        { "Base.RippedSheets", 6, 3 }, { "Base.PlantainCataplasm", 3, 2 },
        { "Base.ComfreyCataplasm", 2, 1 }, { "Base.WildGarlicCataplasm", 2, 1 },
        { "Base.Coldpack", 2, 1 }, { "Base.Antibiotics", 1, 1 },
    },
    hardware = {
        { "Base.Nails", 4, 25 }, { "Base.Screws", 4, 20 }, { "Base.Plank", 4, 4 },
        { "Base.Screwdriver", 2, 1 }, { "Base.Rope", 2, 1 }, { "Base.Wire", 1, 1 },
    },
}

Presets.Dressing = {
    munitionsCrate = "location_military_generic_01_4",
    rationsCrate = "location_shop_greenes_01_35",
    campBox = "furniture_storage_02_18",
    medicineDrawers = "location_community_medical_01_37",
    hardwareCabinet = "location_business_machinery_01_33",

    roadBlock = { alongX = "street_decoration_01_28", alongY = "street_decoration_01_29" },
    barrier = "fencing_01_100",
    floodlamp = "lighting_outdoor_01_49",
    table = "furniture_tables_low_01_16",
    logPile = { { "camping_01_37", 0, 0 }, { "camping_01_36", 0, 1 } },
    bunk = { { "furniture_bedding_01_85", 0, 0 }, { "furniture_bedding_01_84", 0, 1 } },
    sickbed = { { "location_community_medical_01_73", 0, 0 }, { "location_community_medical_01_72", 0, 1 } },
    litter = {
        paper = { "d_trash_1_0", "d_trash_1_3", "d_trash_1_6", "d_trash_1_14", "d_trash_1_22" },
        plastic = { "d_trash_1_8", "d_trash_1_12", "d_trash_1_17", "d_trash_1_21" },
        bags = { "d_trash_1_9", "d_trash_1_10", "d_trash_1_11" },
        wood = { "d_trash_1_24" },
    },
}
local D = Presets.Dressing

local function add(preset)

    if preset.id ~= "sturdy_house" and preset.id ~= "holdout_house"
            and preset.id ~= "bridge_checkpoint" then
        preset.hostileToPlayers = true
    end
    Presets.list[#Presets.list + 1] = preset
    Presets.byId[preset.id] = preset
end

add({
    id = "police_station", label = "Fortified station", class = "building",

    roomNames = { "police", "armystorage", "gunstore" },
    minArea = 120, maxArea = 2600,
    minDay = 3, lifetime = { minHours = 96, maxHours = 240 },
    garrison = { min = 4, max = 6 },
    squad = { size = { min = 2, max = 4 }, maxLive = 2, maxOffline = 0,
        intervalHours = { min = 4, max = 10 },
        taskWeights = { patrol = 40, scavenge = 35, hunt = 25 } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,
    planVersion = 2,
    kit = {
        { op = "mark_entrances" },
        { op = "barricade_doors", planks = 3 },

        { op = "barricade_windows", chance = 100, material = "metal" },

        { op = "entry_barrier", run = 5, standoff = 3, pieces = D.roadBlock },
        { op = "yard_barrier", span = 4, standoff = 6, sprite = D.barrier },
        { op = "campfire", at = "interior" },
        { op = "object", at = "interior", pieces = D.logPile },
        { op = "container", sprite = D.munitionsCrate, loot = "munitions", draws = 4 },
        { op = "container", sprite = D.rationsCrate, loot = "rations", draws = 3 },
        { op = "container", sprite = D.medicineDrawers, loot = "medicine", draws = 2 },
        { op = "generator", at = "yard" },
        { op = "light", sprite = D.floodlamp, at = "interior" },
        { op = "blood", count = 6, at = "interior" },
        { op = "items", item = "Base.Bullets38", count = 2, stack = 6, at = "interior" },
        { op = "dress_litter", kinds = { "paper", "bags", "plastic" }, heaps = 4 },
        { op = "radio", sprite = "appliances_com_01_0", at = "interior" },
    },
})

add({
    id = "sturdy_house", label = "Held house", class = "building",
    roomNames = nil, minArea = 60, maxArea = 400,
    minDay = 1, lifetime = { minHours = 72, maxHours = 192 },
    garrison = { min = 3, max = 5 },
    squad = { size = { min = 2, max = 3 }, maxLive = 1, maxOffline = 0,
        intervalHours = { min = 6, max = 12 },
        taskWeights = { patrol = 30, scavenge = 60, hunt = 10 } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,
    planVersion = 2,
    kit = {
        { op = "mark_entrances" },
        { op = "barricade_doors", planks = 3 },
        { op = "barricade_windows", chance = 100 },

        { op = "entry_barrier", run = 3, standoff = 1,
            pieces = { alongX = D.barrier, alongY = D.barrier } },
        { op = "campfire", at = "yard" },
        { op = "container", sprite = D.rationsCrate, loot = "rations", draws = 3 },
        { op = "container", sprite = D.hardwareCabinet, loot = "hardware", draws = 2 },
        { op = "dress_litter", kinds = { "paper", "plastic" }, heaps = 2 },
        { op = "radio", sprite = "appliances_com_01_0", at = "interior" },
    },
})

add({
    id = "fortified_field_base", label = "Fortified field base", class = "clearing",
    manualOnly = true,
    footprint = { w = 15, h = 15 },
    minDay = 3, lifetime = { minHours = 120, maxHours = 288 },
    garrison = { min = 5, max = 7 },

    stance = "garrison", awareness = 1,

    posts = { { x = -5, y = -1 }, { x = 5, y = 4 }, { x = -4, y = -2 },
        { x = -2, y = 5 }, { x = 2, y = 5 }, { x = -1, y = 1 }, { x = 1, y = 1 } },
    squad = { size = { min = 2, max = 4 }, maxLive = 2, maxOffline = 1,
        intervalHours = { min = 4, max = 9 },
        taskWeights = { patrol = 55, scavenge = 30, hunt = 15 } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,

    planVersion = 3,
    kit = {
        { op = "site_survey" },
        { op = "site_clearance" },

        { op = "fortified_perimeter", family = "palisade", gate = "double" },

        { op = "guard_tower", offset = { x = 1, y = -6 }, door = "S", facing = "N" },

        { op = "object", sprite = D.barrier, offset = { x = -3, y = 6 } },
        { op = "object", sprite = D.barrier, offset = { x = -2, y = 6 } },
        { op = "object", sprite = D.barrier, offset = { x = 2, y = 6 } },
        { op = "object", sprite = D.barrier, offset = { x = 3, y = 6 } },

        { op = "object", sprite = D.roadBlock.alongX, offset = { x = -2, y = -6 } },
        { op = "object", sprite = D.roadBlock.alongY, offset = { x = -6, y = 6 } },
        { op = "object", sprite = D.roadBlock.alongY, offset = { x = 6, y = 6 } },

        { op = "tent", offset = { x = -2, y = -4 } },
        { op = "tent", offset = { x = -3, y = -1 } },
        { op = "tent", offset = { x = -3, y = 3 } },
        { op = "tent", offset = { x = 3, y = 3 } },
        { op = "campfire", at = "center" },
        { op = "object", sprite = D.table, offset = { x = -5, y = 3 } },
        { op = "object", pieces = D.bunk, offset = { x = 5, y = 1 } },
        { op = "container", sprite = D.hardwareCabinet, loot = "hardware",
            draws = 3, offset = { x = -6, y = 1 } },
        { op = "items", item = "Base.Plank", count = 1, stack = 3, offset = { x = -6, y = 2 } },
        { op = "generator", offset = { x = 5, y = -1 } },

        { op = "light", sprite = D.floodlamp, offset = { x = 0, y = -2 } },
        { op = "light", sprite = D.floodlamp, offset = { x = 0, y = 5 } },
        { op = "container", sprite = D.munitionsCrate, loot = "munitions",
            draws = 5, offset = { x = -3, y = 5 } },
        { op = "container", sprite = D.medicineDrawers, loot = "medicine",
            draws = 3, offset = { x = 0, y = 3 } },
        { op = "container", sprite = D.rationsCrate, loot = "rations",
            draws = 4, offset = { x = 3, y = 5 } },
        { op = "radio", sprite = "appliances_com_01_0",
            offset = { x = -1, y = -5 } },
    },
})

add({
    id = "forest_camp", label = "Forest camp", class = "clearing",
    footprint = { w = 10, h = 10 },
    minDay = 0, lifetime = { minHours = 48, maxHours = 120 },
    garrison = { min = 2, max = 4 },

    stance = "camp",
    awareness = 1,
    schedule = { style = "camp" },
    squad = { size = { min = 2, max = 3 }, maxLive = 1, maxOffline = 0,
        intervalHours = { min = 6, max = 12 },
        taskWeights = { patrol = 20, scavenge = 70, hunt = 10 } },
    hostileToPlayers = "faction",
    radio = false, theftTurnsHostile = true,
    planVersion = 2,
    kit = {
        { op = "site_survey" },
        { op = "site_clearance" },
        { op = "tent", offset = { x = -2, y = -3 } },
        { op = "tent", offset = { x = 3, y = -3 } },
        { op = "tent", offset = { x = -2, y = 2 } },
        { op = "campfire", at = "center" },
        { op = "object", sprite = D.table, offset = { x = 3, y = 2 } },
        { op = "container", sprite = D.rationsCrate, loot = "rations",
            draws = 3, offset = { x = 3, y = 3 } },
        { op = "container", sprite = D.campBox, loot = "hardware",
            draws = 2, offset = { x = -3, y = 3 } },
        { op = "items", item = "Base.BeerCanEmpty", count = 5, stack = 3, at = "center" },
        { op = "dress_litter", kinds = { "bags", "wood", "paper" }, heaps = 3 },
    },
})

add({
    id = "field_hospital", label = "Field aid station", class = "clearing",
    footprint = { w = 13, h = 13 },
    minDay = 2, lifetime = { minHours = 96, maxHours = 216 },
    garrison = { min = 3, max = 5 },
    stance = "guard", awareness = 1,
    roles = { "medic" },
    squad = { size = { min = 2, max = 3 }, maxLive = 1, maxOffline = 1,
        intervalHours = { min = 5, max = 11 },
        taskWeights = { patrol = 35, scavenge = 55, hunt = 10 } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,

    planVersion = 3,
    kit = {
        { op = "site_survey" },
        { op = "site_clearance" },

        { op = "fortified_perimeter", family = "wood", gate = "single" },

        { op = "object", pieces = D.sickbed, offset = { x = -5, y = -4 } },
        { op = "object", pieces = D.sickbed, offset = { x = -5, y = -1 } },
        { op = "object", pieces = D.sickbed, offset = { x = 5, y = -4 } },
        { op = "object", pieces = D.sickbed, offset = { x = 5, y = -1 } },
        { op = "container", sprite = D.medicineDrawers, loot = "medicine",
            draws = 5, offset = { x = 0, y = -5 } },
        { op = "container", sprite = D.medicineDrawers, loot = "medicine",
            draws = 4, offset = { x = 1, y = -5 } },
        { op = "container", sprite = D.rationsCrate, loot = "rations",
            draws = 3, offset = { x = 4, y = 3 } },
        { op = "generator", offset = { x = -4, y = 4 } },
        { op = "light", sprite = D.floodlamp, at = "center" },
        { op = "radio", sprite = "appliances_com_01_0", offset = { x = -2, y = 4 } },
    },
})

add({
    id = "supply_depot", label = "Supply depot", class = "clearing",
    footprint = { w = 12, h = 12 },
    minDay = 5, lifetime = { minHours = 120, maxHours = 264 },
    garrison = { min = 4, max = 6 },
    stance = "guard", awareness = 1,
    squad = { size = { min = 2, max = 4 }, maxLive = 2, maxOffline = 1,
        intervalHours = { min = 4, max = 10 },
        taskWeights = { patrol = 45, scavenge = 40, hunt = 15 } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,
    planVersion = 2,
    kit = {
        { op = "site_survey" },
        { op = "site_clearance" },
        { op = "fortified_perimeter", family = "palisade", gate = "double" },

        { op = "guard_tower", offset = { x = 0, y = -5 }, door = "S", facing = "N" },
        { op = "generator", offset = { x = -4, y = -5 } },
        { op = "light", sprite = D.floodlamp, offset = { x = -2, y = -3 } },
        { op = "light", sprite = D.floodlamp, offset = { x = 0, y = 4 } },
        { op = "object", sprite = D.barrier, offset = { x = -2, y = 5 } },
        { op = "object", sprite = D.barrier, offset = { x = 2, y = 5 } },

        { op = "container", sprite = D.munitionsCrate, loot = "munitions",
            draws = 6, offset = { x = -3, y = 0 } },
        { op = "container", sprite = D.hardwareCabinet, loot = "hardware",
            draws = 4, offset = { x = -3, y = 1 } },
        { op = "container", sprite = D.rationsCrate, loot = "rations",
            draws = 5, offset = { x = 3, y = 0 } },
        { op = "container", sprite = D.medicineDrawers, loot = "medicine",
            draws = 2, offset = { x = 3, y = 1 } },
        { op = "campfire", at = "center" },
        { op = "items", item = "Base.Plank", count = 4, stack = 3, at = "center" },
        { op = "dress_litter", kinds = { "bags", "paper" }, heaps = 3 },
        { op = "radio", sprite = "appliances_com_01_0", offset = { x = 0, y = 3 } },
    },
})

add({
    id = "holdout_house", label = "Holdout", class = "building",
    roomNames = nil, minArea = 40, maxArea = 300,
    minDay = 0, lastDay = 10, lifetime = { minHours = 24, maxHours = 96 },
    perCity = 2,
    garrison = { min = 1, max = 3 },
    squad = { size = { min = 0, max = 0 }, maxLive = 0, maxOffline = 0,
        intervalHours = { min = 999, max = 999 }, taskWeights = {} },
    hostileToPlayers = false,
    radio = false, theftTurnsHostile = true,
    stance = "holdout",
    planVersion = 2,
    kit = {
        { op = "mark_entrances" },
        { op = "barricade_doors", planks = 3 },

        { op = "barricade_windows", chance = 100, planks = 4 },
        { op = "container", sprite = D.rationsCrate, loot = "rations", draws = 2 },
    },
})

add({
    id = "alexandria", label = "Walled compound", class = "clearing",

    footprint = { w = 61, h = 61, roadAllowance = 0.14 },
    minDay = 14, lifetime = { minHours = 240, maxHours = 720 },

    garrison = { min = 24, max = 28, crew = true },
    stance = "garrison", awareness = 1,

    ring = { min = 85, max = 150 },
    minBuildDistance = 80,

    posts = { { x = -2, y = 3 }, { x = 2, y = 3 }, { x = 3, y = -2 }, { x = -3, y = 2 } },
    squad = { size = { min = 3, max = 5 }, maxLive = 1, maxOffline = 4,
        intervalHours = { min = 3, max = 8 },
        taskWeights = { patrol = 30, scavenge = 30, hunt = 40 } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,

    planVersion = 2,

    kit = {
        { op = "site_survey", roadAllowance = 0.14 },
        { op = "site_clearance", margin = 4 },
        { op = "compound" },

        { op = "generator", offset = { x = 28, y = -3 } },
    },
})

local function checkpointPost(x, y, role, conduct, face)
    return { x = x, y = y, role = role, conduct = conduct, face = face }
end

local function bridgeFace(x)
    return { x = x + 0.5, y = 45.5 }
end

local function checkpointPosts()
    local list = {
        checkpointPost(3, 10, "guard", "gunner", bridgeFace(9)),
        checkpointPost(4, 9, "guard", nil, bridgeFace(9)),
        checkpointPost(5, 10, "guard", nil, bridgeFace(9)),
        checkpointPost(6, 9, "guard", nil, bridgeFace(6)),
        checkpointPost(7, 10, "guard", nil, bridgeFace(7)),
        checkpointPost(8, 9, "guard", nil, bridgeFace(8)),
        checkpointPost(9, 10, "guard", nil, bridgeFace(9)),
        checkpointPost(10, 9, "guard", nil, bridgeFace(10)),
        checkpointPost(11, 10, "sniper", "sniper", bridgeFace(9)),
        checkpointPost(12, 9, "sniper", "sniper", bridgeFace(9)),
        checkpointPost(12, 10, "sniper", "sniper", bridgeFace(9)),
        checkpointPost(-19, -24, "radio", nil, { x = -17.5, y = -24.5 }),
    }
    for _, spot in ipairs({ { -5, 1 }, { -3, 2 }, { -3, 3 }, { -5, 5 }, { -7, 4 }, { -7, 3 } }) do
        list[#list + 1] = checkpointPost(spot[1], spot[2], "sit", nil, { x = -4.5, y = 3.5 })
    end
    return list
end

add({
    id = "bridge_checkpoint", label = "Cordon bridge checkpoint", class = "clearing",
    manualOnly = true,

    fixedSite = true,

    planVersion = 92,
    footprint = { w = 63, h = 65 },

    blueprint = {
        id = "westpoint_checkpoint_new",
        entrance = { x = 8, y = 11, side = "S" },
        loot = {
            { x = -17, y = 4, store = "munitions", draws = 5 },
            { x = -16, y = 4, store = "munitions", draws = 4 },
            { x = -20, y = 5, store = "medicine", draws = 3 },
            { x = -5, y = -13, store = "rations", draws = 4 },
        },
    },

    tripLine = { x1 = -17, x2 = -8, y1 = 13, y2 = 69 },

    minDay = 0, lifetime = { minHours = 72, maxHours = 73 },

    holdPosts = true,

    zombieFreeRadius = 60,

    garrison = { min = 18, max = 18, crew = true },

    factionId = "alife_cordon",
    crewProfiles = {
        gunner = { "cordon_gunner" },
        sniper = { "cordon_marksman" },
        radio = { "cordon_sergeant" },
        default = { "cordon_rifleman", "cordon_rifleman_pack", "cordon_rifleman" },
    },

    stance = "garrison", awareness = 1,

    posts = checkpointPosts(),

    careful = { warnRadius = 60, closeRadius = 38, contactRadius = 24, contactHoldMs = 4000 },

    scripted = {
        id = "bridge_cordon",

        warnRadius = 60, closeRadius = 38, contactRadius = 24, contactHoldMs = 4000,

        holdPost = true, noClimb = true,

        fireHoldMs = 4000, volley = true,
    },

    intro = { kind = "gunfire", radius = 160, offset = { x = 9, y = 81 } },

    announcer = { sounds = { "PALAnnouncerCheckpoint" }, everySeconds = 300, jitterSeconds = 20,
        radius = 90, near = 20 },

    squad = { size = { min = 2, max = 3 }, maxLive = 1, maxOffline = 0,
        intervalHours = { min = 1, max = 2 },
        taskWeights = { patrol = 100 },
        route = { { x = -3, y = -9 }, { x = 17, y = -9 }, { x = 17, y = 7 }, { x = 1, y = 7 } } },
    hostileToPlayers = "faction",
    radio = true, theftTurnsHostile = true,
    kit = {

        { op = "blueprint", id = "westpoint_checkpoint_new" },

        { op = "blood", count = 6 },
    },
})
function Presets.get(id)
    return Presets.byId[tostring(id or "")]
end

local KNOWN_OPS = {
    mark_entrances = true, barricade_windows = true, barricade_doors = true,
    entry_barrier = true, yard_barrier = true, fortified_perimeter = true,
    campfire = true, tent = true, object = true, container = true,
    dress_litter = true, radio = true, site_survey = true, site_clearance = true,

    blood = true, items = true, light = true, generator = true,

    guard_tower = true,

    path = true, pen = true,

    compound = true,

    checkpoint = true,

    blueprint = true,
}

function Presets.validate()
    local problems = {}
    for _, preset in ipairs(Presets.list) do
        local function fail(what) problems[#problems + 1] = preset.id .. ": " .. what end
        if type(preset.kit) ~= "table" or #preset.kit == 0 then fail("no kit") end
        if preset.class ~= "building" and preset.class ~= "clearing" then fail("bad class") end
        if type(preset.lifetime) ~= "table" or preset.lifetime.minHours >= preset.lifetime.maxHours then fail("bad lifetime") end
        if type(preset.garrison) ~= "table" or preset.garrison.min > preset.garrison.max then fail("bad garrison") end
        if preset.class == "building" and (preset.minArea == nil or preset.maxArea == nil or preset.minArea >= preset.maxArea) then fail("bad area") end
        local entrances = 0
        for _, op in ipairs(preset.kit or {}) do
            if not KNOWN_OPS[op.op] then fail("unknown op " .. tostring(op.op)) end
            if op.op == "mark_entrances" then entrances = entrances + 1 end
            if op.op == "container" and Presets.Stores[op.loot] == nil then fail("unknown store " .. tostring(op.loot)) end
            if op.op == "container" and type(op.draws) ~= "number" then fail("container without draws") end
            if (op.op == "object" or op.op == "container" or op.op == "radio"
                    or op.op == "light") and type(op.sprite) ~= "string"
                    and not (op.op == "object" and type(op.pieces) == "table" and #op.pieces > 0) then
                fail("op without sprite " .. tostring(op.op))
            end
            if op.op == "items" and type(op.item) ~= "string" then fail("items op without an item") end
            if op.op == "blueprint" and type(op.id) ~= "string" then fail("blueprint op without an id") end
            if op.op == "entry_barrier" and (type(op.pieces) ~= "table"
                    or type(op.pieces.alongX) ~= "string" or type(op.run) ~= "number") then
                fail("entry barrier without pieces or run")
            end
            if op.op == "yard_barrier" and (type(op.sprite) ~= "string" or type(op.span) ~= "number"
                    or type(op.standoff) ~= "number") then
                fail("yard barrier without sprite, span or standoff")
            end
            if op.op == "dress_litter" then
                if type(op.heaps) ~= "number" or op.heaps < 1 or type(op.kinds) ~= "table" or #op.kinds == 0 then
                    fail("litter without heaps or kinds")
                end
                for _, kind in ipairs(op.kinds or {}) do
                    if type(Presets.Dressing.litter[kind]) ~= "table" then fail("unknown litter " .. tostring(kind)) end
                end
            end

            if op.op == "fortified_perimeter" and op.family ~= "palisade" and op.family ~= "wood" then
                fail("perimeter without a map wall family")
            end

            if op.op == "path" and (type(op.points) ~= "table" or #op.points < 2) then
                fail("path op needs at least two points")
            end
            if op.op == "path" then
                for _, point in ipairs(op.points or {}) do
                    if type(point) ~= "table" or type(point.x) ~= "number"
                            or type(point.y) ~= "number" then
                        fail("path point without coordinates")
                    end
                end
            end

            if op.op == "line" then
                local from, to = op.from, op.to
                if type(from) ~= "table" or type(to) ~= "table"
                        or type(from.x) ~= "number" or type(from.y) ~= "number"
                        or type(to.x) ~= "number" or type(to.y) ~= "number" then
                    fail("line op without from/to")
                elseif from.x ~= to.x and from.y ~= to.y then
                    fail("line op is diagonal")
                end
            end
            if op.op == "pen" then
                if type(op.animals) ~= "table" or #op.animals == 0 then
                    fail("pen op without animals")
                else
                    for _, animal in ipairs(op.animals) do
                        if type(animal) ~= "string" or animal == "" then
                            fail("pen animal without a type")
                        end
                    end
                end
            end
        end
        if preset.class == "building" and entrances ~= 1 then fail("a building preset needs exactly one mark_entrances") end
        if preset.radio == true then

            local hasRadio = false
            for _, op in ipairs(preset.kit) do
                if op.op == "radio" then hasRadio = true end

                if op.op == "compound" or op.op == "blueprint" then hasRadio = true end
            end
            if not hasRadio then fail("radio preset with nothing to broadcast from") end
        end
    end
    for name, rows in pairs(Presets.Stores) do
        for _, row in ipairs(rows) do
            if type(row[1]) ~= "string" or type(row[2]) ~= "number" or row[2] <= 0 or type(row[3]) ~= "number" then
                problems[#problems + 1] = "store " .. name .. ": bad row"
            end
        end
    end
    return #problems == 0, problems
end

return Presets
