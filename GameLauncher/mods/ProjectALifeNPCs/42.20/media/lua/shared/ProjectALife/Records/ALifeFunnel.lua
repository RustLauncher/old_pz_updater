ProjectALife = ProjectALife or {}

local Funnel = {
    options = {
        enabled = "Funnel_Enabled",
        offset = "Funnel_DayOffset",
        loneMax = "Funnel_LoneSurvivorMax",
        skills = "Funnel_SkillRampPercent",
    },
    defaultLoneMax = 2,
    loneCeiling = 2,
    offsetLimit = 3650,
}
ProjectALife.Funnel = Funnel

Funnel.stages = {
    { id = 0, name = "earlygame", from = 0, to = 7, gear = 1, aim = 0, loneSplit = 1.0,
      weight = { responder = 1.0, lone = 1.0, small = 1.0, big = 0.0, outlaw = 1.0, raider = 1.0 } },
    { id = 1, name = "first_fortnight", from = 7, to = 14, gear = 1, aim = 0, loneSplit = 1.0,
      weight = { responder = 1.0, lone = 1.0, small = 1.0, big = 0.0, outlaw = 1.0, raider = 1.0 } },
    { id = 2, name = "first_month", from = 14, to = 30, gear = 2, aim = 0, loneSplit = 1.0,
      weight = { responder = 1.0, lone = 1.0, small = 1.0, big = 0.6, outlaw = 1.0, raider = 1.0 } },
    { id = 3, name = "second_month", from = 30, to = 60, gear = 3, aim = 1, loneSplit = 1.0,
      weight = { responder = 1.0, lone = 1.0, small = 1.0, big = 1.0, outlaw = 1.0, raider = 1.0 } },
    { id = 4, name = "first_season", from = 60, to = 120, gear = 4, aim = 1, loneSplit = 0.55,
      weight = { responder = 0.7, lone = 0.75, small = 1.0, big = 1.5, outlaw = 0.9, raider = 1.0 } },
    { id = 5, name = "federation_age", from = 120, to = 360, gear = 5, aim = 2, loneSplit = 0.35,
      weight = { responder = 0.0, lone = 0.5, small = 1.15, big = 2.0, outlaw = 0.5, raider = 0.9 } },
    { id = 6, name = "second_year", from = 360, to = 720, gear = 6, aim = 2, loneSplit = 0.2,
      weight = { responder = 0.0, lone = 0.35, small = 1.1, big = 2.4, outlaw = 0.4, raider = 1.0 } },
    { id = 7, name = "long_haul", from = 720, to = nil, gear = 6, aim = 3, loneSplit = 0.1,
      weight = { responder = 0.0, lone = 0.25, small = 1.0, big = 2.6, outlaw = 0.3, raider = 1.0 } },
}

Funnel.classes = {
    alife_angler_pair = "lone",
    alife_apartment_watch = "small",
    alife_armor_school = "responder",
    alife_army_medical = "responder",
    alife_bauer_family = "small",
    alife_bell_family = "small",
    alife_bledsoe = "small",
    alife_black_lung_crew = "raider",
    alife_bloods_victory = "outlaw",
    alife_bone_raiders = "raider",
    alife_breaker_nine = "raider",
    alife_chicago_contacts = "outlaw",
    alife_chopshop = "small",
    alife_church_volunteers = "small",
    alife_cinder_raiders = "raider",
    alife_conservation = "responder",
    alife_conservation_remnants = "responder",
    alife_convoy_predators = "raider",
    alife_cordon = "responder",
    alife_cornbread_network = "outlaw",
    alife_cornfield = "outlaw",
    alife_corrections_remnants = "responder",
    alife_county_ems = "responder",
    alife_county_jail = "responder",
    alife_county_law_remnants = "responder",
    alife_countyline = "outlaw",
    alife_courthouse = "small",
    alife_coworker_pair = "lone",
    alife_coyle = "outlaw",
    alife_crips_victory = "outlaw",
    alife_crume = "small",
    alife_dabney = "small",
    alife_delta_detachment = "responder",
    alife_derby_set = "outlaw",
    alife_deserters = "raider",
    alife_diner_survivors = "small",
    alife_distillery_workers = "small",
    alife_dixie_network = "outlaw",
    alife_dixie_road = "raider",
    alife_engineer_holdouts = "responder",
    alife_false_checkpoint = "raider",
    alife_ferrymen = "small",
    alife_fire = "responder",
    alife_first_family = "outlaw",
    alife_first_responders = "responder",
    alife_freeman_family = "small",
    alife_gangster_disciples = "outlaw",
    alife_grim_reapers_mc = "outlaw",
    alife_guard = "responder",
    alife_guard_engineers = "responder",
    alife_guard_infantry = "responder",
    alife_guard_remnants = "responder",
    alife_gunclub = "small",
    alife_hensley_family = "small",
    alife_highway_maintenance = "small",
    alife_hobbs = "outlaw",
    alife_hornback_family = "small",
    alife_hospital = "responder",
    alife_ironhorse = "outlaw",
    alife_jefferson_police = "responder",
    alife_kessinger = "small",
    alife_kettle = "small",
    alife_knob_stalkers = "raider",
    alife_ksp_post = "responder",
    alife_ksp_srt = "responder",
    alife_lawson_family = "small",
    alife_ledford = "small",
    alife_lineworkers = "small",
    alife_lockup_escapees = "small",
    alife_longshot_crew = "raider",
    alife_lone_commuter = "lone",
    alife_lone_courier = "lone",
    alife_lone_farmhand = "lone",
    alife_lone_hiker = "lone",
    alife_lone_hitchhiker = "lone",
    alife_lone_mechanic = "lone",
    alife_lone_nurse = "lone",
    alife_lone_retiree = "lone",
    alife_lone_student = "lone",
    alife_lone_veteran = "lone",
    alife_long_road = "lone",
    alife_lost_teen = "lone",
    alife_lost_tourist = "lone",
    alife_louisville_police = "responder",
    alife_married_pair = "lone",
    alife_mattingly_family = "small",
    alife_mercer_family = "small",
    alife_moonshine_coop = "outlaw",
    alife_mp_brigade = "responder",
    alife_muldraugh_pd = "responder",
    alife_napier = "small",
    alife_napier_collectors = "raider",
    alife_nguyen_family = "small",
    alife_office_workers = "small",
    alife_ortiz_family = "small",
    alife_otter_creek_trappers = "lone",
    alife_outlaws_mc = "outlaw",
    alife_paramedics_offduty = "responder",
    alife_pharmacy_staff = "responder",
    alife_pit = "raider",
    alife_police = "responder",
    alife_postal_workers = "small",
    alife_prather = "small",
    alife_preppers = "small",
    alife_price_family = "small",
    alife_prison_escape_pair = "lone",
    alife_prison_infirmary = "responder",
    alife_prison_peaceful = "small",
    alife_prison_predators = "raider",
    alife_pruitt_family = "small",
    alife_radio_station = "small",
    alife_rail_workers = "small",
    alife_red_cross = "responder",
    alife_refugee_walkers = "small",
    alife_renfro = "outlaw",
    alife_reservist_remnants = "responder",
    alife_rivermen = "small",
    alife_riverside = "small",
    alife_riverside_pd = "responder",
    alife_road_militia = "big",
    alife_rosewood_corrections = "responder",
    alife_rosewood_pd = "responder",
    alife_sanitation = "small",
    alife_sawmill_hands = "small",
    alife_schoolhouse = "small",
    alife_scrapyard_reavers = "raider",
    alife_sf_detachment = "responder",
    alife_sheriff = "responder",
    alife_sibling_pair = "lone",
    alife_skaggs_family = "small",
    alife_slackwater_rats = "raider",
    alife_slaughter = "small",
    alife_stockyard = "small",
    alife_stuck_trucker = "lone",
    alife_survivor_commune = "big",
    alife_sutter_family = "small",
    alife_tackett = "small",
    alife_telephone_crew = "lone",
    alife_tollmen = "raider",
    alife_trailer_neighbors = "small",
    alife_training_remnants = "responder",
    alife_transit_strike = "small",
    alife_transport_detail = "responder",
    alife_traveller_pair = "lone",
    alife_trooper_remnants = "responder",
    alife_truckstop = "small",
    alife_turner_family = "small",
    alife_undertakers_mc = "outlaw",
    alife_utility_survivors = "small",
    alife_vault_police = "responder",
    alife_vfd = "responder",
    alife_vice_lords = "outlaw",
    alife_vittitoe = "small",
    alife_walker_family = "small",
    alife_ward_survivors = "responder",
    alife_warehouse_nightshift = "small",
    alife_waterworks = "small",
    alife_westpoint_pd = "responder",
    alife_whitaker = "small",
}

Funnel.content = {
    alife_commonwealth_knox = "big", alife_ridge_militia_league = "big", alife_valley_caravan_league = "big",
    alife_ekron_farm_cooperative = "big", alife_riverside_ferry_union = "big", alife_mount_hope_fellowship = "big",
    alife_foundry_works = "big", alife_hollow_compact = "big", alife_clinic_circle = "small",
    alife_redline_reavers = "raider", alife_the_tithe = "raider", alife_night_shift = "raider", alife_iron_choir = "raider",
}
for id, class in pairs(Funnel.content) do Funnel.classes[id] = class end

function Funnel.register(factionId, class)
    if type(factionId) ~= "string" or factionId == "" then return false end
    Funnel.classes[factionId] = class
    return true
end

function Funnel.read(field, key)
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and current[field] ~= nil then return current[field] end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" then return vars[key] end
    return nil
end

function Funnel.enabled()
    local value = Funnel.read("funnelEnabled", Funnel.options.enabled)
    if type(value) == "boolean" then return value end
    return true
end

function Funnel.dayOffset()
    local value = tonumber(Funnel.read("funnelDayOffset", Funnel.options.offset))
    if value == nil or value ~= value then return 0 end
    return math.max(-Funnel.offsetLimit, math.min(Funnel.offsetLimit, value))
end

function Funnel.loneMax()
    local value = tonumber(Funnel.read("funnelLoneMax", Funnel.options.loneMax))
    if value == nil or value ~= value then value = Funnel.defaultLoneMax end
    return math.max(1, math.min(Funnel.loneCeiling, math.floor(value)))
end

function Funnel.skillPercent()
    local value = tonumber(Funnel.read("funnelSkillPercent", Funnel.options.skills))
    if value == nil or value ~= value then return 100 end
    return math.max(0, math.min(200, value))
end

function Funnel.today()
    local day = 0
    pcall(function() day = getGameTime():getWorldAgeHours() / 24 end)
    day = tonumber(day) or 0
    if day ~= day then return 0 end
    return day
end

function Funnel.day(day)
    day = tonumber(day)
    if day == nil or day ~= day then day = Funnel.today() end
    if not Funnel.enabled() then return day end
    return day + Funnel.dayOffset()
end

function Funnel.stageAt(day)
    day = tonumber(day)
    if day == nil or day ~= day then day = 0 end
    local index = 0
    for _, row in ipairs(Funnel.stages) do
        if day >= row.from then index = row.id end
    end
    return index
end

function Funnel.stage(day)
    return Funnel.stageAt(Funnel.day(day))
end

function Funnel.stageOf(day)
    return Funnel.stages[Funnel.stage(day) + 1]
end

function Funnel.classOf(faction)
    local id = faction
    if type(faction) == "table" then
        id = faction.id
        if type(faction.spawn) == "table" and faction.spawn.visitorOnly == true then return nil end
    end
    if type(id) ~= "string" then return nil end
    return Funnel.classes[id]
end

function Funnel.weight(faction, day)
    if not Funnel.enabled() then
        local id = type(faction) == "table" and faction.id or faction
        return Funnel.content[id] ~= nil and 0 or 1
    end
    local class = Funnel.classOf(faction)
    if class == nil then return 1 end
    local value = Funnel.stageOf(day).weight[class]
    if value == nil then return 1 end
    return value
end

function Funnel.allows(faction, day)
    return Funnel.weight(faction, day) > 0
end

function Funnel.isLone(faction)
    return Funnel.enabled() and Funnel.classOf(faction) == "lone"
end

function Funnel.loneScale(faction, day)
    if not Funnel.enabled() then return 1 end
    local class = Funnel.classOf(faction)
    if class == nil or class == "lone" then return 1 end
    return Funnel.stageOf(day or Funnel.today()).loneSplit
end

function Funnel.clampSize(faction, size)
    size = tonumber(size) or 0
    if Funnel.isLone(faction) then return math.min(size, Funnel.loneMax()) end
    return size
end

function Funnel.gearTier(day)
    if not Funnel.enabled() then return nil end
    return Funnel.stageOf(day).gear
end

function Funnel.aimBonus(day)
    if not Funnel.enabled() then return 0 end
    local percent = Funnel.skillPercent()
    return math.floor(Funnel.stageOf(day).aim * percent / 100 + 0.5)
end

function Funnel.census()
    local result = { lone = 0, pairs = 0, groups = 0, big = 0, raiders = 0 }
    local registry = ProjectALife.ActorRegistry
    if type(registry) ~= "table" or type(registry.each) ~= "function" then return result end
    local parties, order = {}, {}
    registry.each(function(record)
        if type(record) ~= "table" or record.lifecycle == "dead" then return false end
        local memory = type(record.memory) == "table" and record.memory or {}
        local key = memory.groupId or memory.squadId or ("solo:" .. tostring(record.uid))
        key = tostring(key)
        local party = parties[key]
        if party == nil then
            party = { size = 0, class = Funnel.classOf(record.factionId) }
            parties[key] = party
            order[#order + 1] = party
        end
        party.size = party.size + 1
        return false
    end)
    for _, party in ipairs(order) do
        if party.size <= 1 then result.lone = result.lone + 1
        elseif party.size == 2 then result.pairs = result.pairs + 1
        else result.groups = result.groups + 1 end
        if party.class == "big" then result.big = result.big + 1 end
        if party.class == "raider" then result.raiders = result.raiders + 1 end
    end
    return result
end

function Funnel.qaLine()
    local day = Funnel.day()
    local count = Funnel.census()
    return "[ALIFE-QA] Funnel: stage=" .. tostring(Funnel.stageAt(day)) .. " day=" .. tostring(math.floor(day))
        .. " lone=" .. tostring(count.lone) .. " pairs=" .. tostring(count.pairs)
        .. " groups=" .. tostring(count.groups) .. " big=" .. tostring(count.big)
        .. " raiders=" .. tostring(count.raiders)
end

function Funnel.minuteText()
    local day = Funnel.day()
    local count = Funnel.census()
    return " funnel=" .. tostring(Funnel.stageAt(day)) .. "/" .. tostring(count.lone) .. "/" .. tostring(count.pairs)
        .. "/" .. tostring(count.groups) .. "/" .. tostring(count.big) .. "/" .. tostring(count.raiders)
end

return Funnel
