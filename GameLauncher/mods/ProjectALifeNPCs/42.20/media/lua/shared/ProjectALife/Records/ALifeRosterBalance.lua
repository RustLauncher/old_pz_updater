ProjectALife = ProjectALife or {}

local Balance = {
    option = "Factions_LegacyRoster",
    adoptWeight = 0.5,
    cloneSuffix = "_m",
    keepMerged = true,
    mergedScale = 0.35,
}
ProjectALife.RosterBalance = Balance

Balance.moodLegacy = {
    { day = 0, friendly = 4.5, neutral = 2.2, careful = 0.9, hostile = 0.5 },
    { day = 7, friendly = 6.5, neutral = 1.7, careful = 1.0, hostile = 0.65 },
    { day = 30, friendly = 4.5, neutral = 1.2, careful = 1.0, hostile = 0.8 },
    { day = 90, friendly = 4.0, neutral = 1.0, careful = 1.0, hostile = 0.9 },
}

Balance.mood = {
    { day = 0, friendly = 1.0, neutral = 1.0, careful = 1.0, hostile = 1.0 },
    { day = 7, friendly = 1.0, neutral = 1.0, careful = 1.0, hostile = 1.05 },
    { day = 30, friendly = 1.0, neutral = 1.0, careful = 1.0, hostile = 1.1 },
    { day = 90, friendly = 1.0, neutral = 1.0, careful = 1.0, hostile = 1.15 },
}

Balance.rows = {
    { id = "alife_police", stance = "neutral", odds = 0.12, title = "County and Town Police", encounters = "roamer|blockade|poi_defenders|rooftop_snipers|town_patrol|patrol", seats = "police_station|sturdy_house" },
    { id = "alife_sheriff", stance = "friendly", odds = 0.12, encounters = "patrol|town_patrol|blockade|poi_defenders|broken_car" },
    { id = "alife_ksp_post", stance = "neutral", odds = 0.08, encounters = "patrol|blockade|poi_defenders|broken_car" },
    { id = "alife_ksp_srt", stance = "careful", odds = 0.03, encounters = "poi_defenders|blockade|patrol|outpost" },
    { id = "alife_county_jail", stance = "careful", odds = 0.08, title = "Corrections Detail", encounters = "poi_defenders|patrol|outpost", seats = "police_station|sturdy_house", towns = "muldraugh|rosewood", allTowns = false },
    { id = "alife_conservation", stance = "neutral", odds = 0.05, encounters = "patrol|roamer|broken_car" },
    { id = "alife_county_law_remnants", stance = "careful", odds = 0.12, title = "Law Remnants", encounters = "outpost|scavenger_crew@14|patrol|broken_car|blockade|roamer", seats = "sturdy_house|police_station|holdout_house|forest_camp", towns = "muldraugh|west_point|rosewood", allTowns = false },
    { id = "alife_vault_police", stance = "careful", odds = 0.015, encounters = "outpost|poi_defenders|patrol" },
    { id = "alife_guard", stance = "careful", odds = 0.1, encounters = "roamer|outpost|poi_defenders|raid|assassination|fullscale_raid|patrol|town_patrol|blockade|broken_car|scavenger_crew", seats = "police_station|fortified_field_base|supply_depot|field_hospital" },
    { id = "alife_guard_remnants", stance = "careful", odds = 0.1, encounters = "outpost|patrol|blockade|scavenger_crew|roamer|poi_defenders", seats = "fortified_field_base|supply_depot|sturdy_house|forest_camp", towns = "", allTowns = true },
    { id = "alife_cordon", stance = "careful", odds = 0.01, encounters = "outpost" },
    { id = "alife_road_militia", stance = "careful", odds = 0.1, encounters = "blockade|patrol|outpost|poi_defenders" },
    { id = "alife_deserters", stance = "hostile", odds = 0.1, peaceable = false, encounters = "roamer|scavenger_crew|blockade|highway_ambush@21" },
    { id = "alife_sf_detachment", stance = "careful", odds = 0.02, encounters = "patrol|poi_defenders|outpost", seats = "forest_camp|fortified_field_base|sturdy_house" },
    { id = "alife_fire", stance = "allied", odds = 0.18, title = "Fire and Rescue Crew", firstDay = 0, lastDay = 3650, encounters = "roamer|poi_defenders|rooftop_snipers|camp|broken_car|outpost|scavenger_crew@10", seats = "sturdy_house|holdout_house" },
    { id = "alife_county_ems", stance = "friendly", odds = 0.15, firstDay = 0, lastDay = 3650, encounters = "broken_car|poi_defenders|roamer|outpost", seats = "field_hospital|holdout_house|sturdy_house" },
    { id = "alife_hospital", stance = "friendly", odds = 0.14, title = "Medical Staff", firstDay = 0, lastDay = 3650, encounters = "poi_defenders|outpost|roamer|scavenger_crew@10|broken_car", seats = "field_hospital|sturdy_house|supply_depot", towns = "louisville|rosewood", allTowns = true },
    { id = "alife_church_volunteers", stance = "friendly", odds = 0.08, firstDay = 0, lastDay = 3650, encounters = "roamer|outpost", seats = "sturdy_house", towns = "west_point", allTowns = true },
    { id = "alife_first_responders", stance = "friendly", odds = 0.05, encounters = "patrol|broken_car|poi_defenders|outpost|scavenger_crew@14" },
    { id = "alife_bell_family", stance = "careful", odds = 0.11, title = "Neighbourhood Households", firstDay = 0, lastDay = 3650, encounters = "outpost|rooftop_snipers|scavenger_crew|broken_car|roamer", seats = "sturdy_house|holdout_house|supply_depot", towns = "riverside|louisville|west_point|march_ridge|irvington|valley_station|rosewood|muldraugh", allTowns = true },
    { id = "alife_vittitoe", stance = "careful", odds = 0.09, title = "Farm Families", firstDay = 0, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol@21|broken_car", seats = "alexandria|sturdy_house|supply_depot", towns = "muldraugh|ekron|echo_creek|fallas_lake|brandenburg", allTowns = true },
    { id = "alife_tackett", stance = "careful", odds = 0.08, title = "Hollow Folk", firstDay = 0, lastDay = 3650, encounters = "outpost|highway_ambush|patrol|roamer", seats = "forest_camp|sturdy_house" },
    { id = "alife_preppers", stance = "careful", odds = 0.08, firstDay = 0, lastDay = 3650, encounters = "outpost|roamer|patrol|poi_defenders", seats = "holdout_house|forest_camp|sturdy_house|fortified_field_base|alexandria" },
    { id = "alife_survivor_commune", stance = "friendly", odds = 0.06, encounters = "outpost|scavenger_crew@14|patrol@21" },
    { id = "alife_truckstop", stance = "careful", odds = 0.06, encounters = "outpost|broken_car|scavenger_crew|blockade@21" },
    { id = "alife_schoolhouse", stance = "friendly", odds = 0.06, encounters = "outpost|scavenger_crew@7" },
    { id = "alife_kettle", stance = "neutral", odds = 0.11, firstDay = 0, lastDay = 3650, encounters = "roamer|scavenger_crew|camp|broken_car|outpost", seats = "supply_depot|sturdy_house" },
    { id = "alife_lineworkers", stance = "neutral", odds = 0.08, title = "Line and Road Crews", firstDay = 0, lastDay = 3650, encounters = "broken_car|scavenger_crew|outpost|roamer|blockade@21", seats = "supply_depot|sturdy_house|holdout_house" },
    { id = "alife_riverside", stance = "neutral", odds = 0.12, firstDay = 0, lastDay = 3650, encounters = "roamer|camp|scavenger_crew|broken_car|outpost", seats = "holdout_house|sturdy_house|forest_camp" },
    { id = "alife_lone_hiker", stance = "neutral", odds = 0.08, title = "Lone Survivor", firstDay = 0, lastDay = 3650, encounters = "roamer|broken_car|outpost", seats = "holdout_house|sturdy_house|forest_camp" },
    { id = "alife_married_pair", stance = "neutral", odds = 0.08, title = "Survivor Pair", firstDay = 0, lastDay = 3650, encounters = "roamer|broken_car|outpost", seats = "holdout_house|forest_camp", towns = "", allTowns = true },
    { id = "alife_renfro", stance = "hostile", odds = 0.28, title = "Road Crooks", firstDay = 0, lastDay = 3650, encounters = "blockade|broken_car|roamer|scavenger_crew|outpost|highway_ambush|patrol|camp", seats = "sturdy_house|supply_depot|holdout_house|forest_camp|police_station" },
    { id = "alife_ironhorse", stance = "hostile", odds = 0.035, title = "Biker Club", firstDay = 0, lastDay = 3650, encounters = "patrol|scavenger_crew|outpost|blockade@14|highway_ambush@30|roamer", seats = "alexandria|sturdy_house|fortified_field_base|supply_depot", towns = "muldraugh|west_point|louisville|valley_station|march_ridge|riverside", allTowns = false },
    { id = "alife_outlaws_mc", stance = "hostile", odds = 0.025, encounters = "patrol|scavenger_crew|outpost|blockade@14|highway_ambush@30", seats = "alexandria|sturdy_house|fortified_field_base|supply_depot", towns = "louisville|valley_station|march_ridge|west_point", allTowns = false },
    { id = "alife_grim_reapers_mc", stance = "hostile", odds = 0.025, encounters = "patrol|scavenger_crew|outpost|blockade@14|highway_ambush@30", seats = "alexandria|sturdy_house|fortified_field_base|supply_depot", towns = "louisville|riverside|west_point", allTowns = false },
    { id = "alife_undertakers_mc", stance = "hostile", odds = 0.025, firstDay = 7, lastDay = 3650, encounters = "patrol|scavenger_crew|outpost|blockade@14|highway_ambush@30", seats = "alexandria|sturdy_house|fortified_field_base|supply_depot" },
    { id = "alife_derby_set", stance = "hostile", odds = 0.03, title = "Street Crews", firstDay = 3, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol|town_patrol|roamer", seats = "sturdy_house|holdout_house|police_station|supply_depot", towns = "louisville", allTowns = false },
    { id = "alife_vice_lords", stance = "hostile", odds = 0.02, firstDay = 7, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol|town_patrol", seats = "sturdy_house|holdout_house|police_station", towns = "louisville|valley_station|west_point", allTowns = false },
    { id = "alife_gangster_disciples", stance = "hostile", odds = 0.02, firstDay = 7, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol|town_patrol", seats = "sturdy_house|supply_depot", towns = "louisville|valley_station|march_ridge", allTowns = false },
    { id = "alife_bloods_victory", stance = "hostile", odds = 0.02, firstDay = 7, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol|town_patrol", seats = "sturdy_house|supply_depot", towns = "louisville|west_point|riverside", allTowns = false },
    { id = "alife_crips_victory", stance = "hostile", odds = 0.02, firstDay = 7, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol|town_patrol", seats = "sturdy_house|holdout_house|police_station", towns = "louisville|west_point|march_ridge", allTowns = false },
    { id = "alife_roadside_pickers", stance = "careful", odds = 0.085, encounters = "scavenger_crew|broken_car" },
    { id = "alife_dixie_road", stance = "hostile", odds = 0.07, firstDay = 7, lastDay = 3650, encounters = "highway_ambush|blockade|raid|scavenger_crew|fullscale_raid|outpost|roamer", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria" },
    { id = "alife_knob_stalkers", stance = "hostile", odds = 0.06, encounters = "highway_ambush|roamer|patrol|assassination|camp" },
    { id = "alife_pit", stance = "hostile", odds = 0.04, firstDay = 31, lastDay = 3650, encounters = "outpost|raid|fullscale_raid|scavenger_crew|patrol|highway_ambush|blockade|roamer|poi_defenders", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria" },
    { id = "alife_cinder_raiders", stance = "hostile", odds = 0.03, encounters = "scavenger_crew|raid|outpost|highway_ambush", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria", towns = "muldraugh|west_point|valley_station", allTowns = false },
    { id = "alife_scrapyard_reavers", stance = "hostile", odds = 0.03, encounters = "outpost|blockade|raid|scavenger_crew|highway_ambush", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria", towns = "muldraugh|west_point", allTowns = false },
    { id = "alife_bone_raiders", stance = "hostile", odds = 0.04, firstDay = 31, lastDay = 3650, encounters = "outpost|patrol|raid|fullscale_raid|highway_ambush|camp|blockade|roamer", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria" },
    { id = "alife_convoy_predators", stance = "hostile", odds = 0.03, encounters = "highway_ambush|blockade|fullscale_raid|raid", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria" },
    { id = "alife_tollmen", stance = "hostile", odds = 0.03, encounters = "blockade|highway_ambush|fullscale_raid|raid|outpost", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria" },
    { id = "alife_false_checkpoint", stance = "hostile", odds = 0.06, encounters = "blockade" },
    { id = "alife_prison_predators", stance = "hostile", odds = 0.1, firstDay = 1, lastDay = 3650, encounters = "outpost|scavenger_crew|patrol|raid@14|roamer", seats = "fortified_field_base|forest_camp|supply_depot|police_station|alexandria|sturdy_house|field_hospital", towns = "rosewood", allTowns = false },
    { id = "alife_sawmill_hands", stance = "careful", odds = 0.03, firstDay = 3, lastDay = 3650, encounters = "roamer|patrol|scavenger_crew|outpost", seats = "forest_camp|sturdy_house" },
    { id = "alife_commonwealth_knox", stance = "careful", odds = 0.078, firstDay = 120, encounters = "patrol|blockade|outpost|scavenger_crew|poi_defenders", seats = "sturdy_house|holdout_house|supply_depot" },
    { id = "alife_ridge_militia_league", stance = "careful", odds = 0.045, firstDay = 45, encounters = "patrol|blockade|outpost|scavenger_crew", seats = "forest_camp|sturdy_house|supply_depot" },
    { id = "alife_valley_caravan_league", stance = "neutral", odds = 0.045, firstDay = 60, encounters = "broken_car|scavenger_crew|outpost|patrol", seats = "supply_depot|sturdy_house" },
    { id = "alife_ekron_farm_cooperative", stance = "friendly", odds = 0.065, firstDay = 60, encounters = "outpost|scavenger_crew|patrol|broken_car", seats = "alexandria|sturdy_house|supply_depot" },
    { id = "alife_riverside_ferry_union", stance = "neutral", odds = 0.039, firstDay = 60, encounters = "fishing|camp|outpost|scavenger_crew", seats = "forest_camp|sturdy_house|supply_depot" },
    { id = "alife_mount_hope_fellowship", stance = "friendly", odds = 0.065, firstDay = 60, encounters = "outpost|camp|scavenger_crew|broken_car", seats = "holdout_house|sturdy_house|supply_depot" },
    { id = "alife_foundry_works", stance = "neutral", odds = 0.039, firstDay = 120, encounters = "outpost|scavenger_crew|broken_car|patrol", seats = "supply_depot|sturdy_house" },
    { id = "alife_hollow_compact", stance = "careful", odds = 0.0325, firstDay = 120, encounters = "outpost|camp|patrol|scavenger_crew", seats = "forest_camp|sturdy_house" },
    { id = "alife_clinic_circle", stance = "friendly", odds = 0.08, firstDay = 120, encounters = "outpost|broken_car|scavenger_crew|roamer", seats = "field_hospital|holdout_house|sturdy_house" },
    { id = "alife_redline_reavers", stance = "hostile", odds = 0.085, firstDay = 120, encounters = "highway_ambush|blockade|raid|scavenger_crew|outpost", seats = "forest_camp|supply_depot|fortified_field_base" },
    { id = "alife_the_tithe", stance = "careful", odds = 0.05, firstDay = 120, encounters = "blockade|outpost|patrol", seats = "sturdy_house|supply_depot|forest_camp" },
    { id = "alife_night_shift", stance = "hostile", odds = 0.04, firstDay = 360, encounters = "raid|fullscale_raid|highway_ambush|outpost", seats = "forest_camp|supply_depot" },
    { id = "alife_iron_choir", stance = "hostile", odds = 0.035, firstDay = 720, encounters = "raid|fullscale_raid|outpost|patrol|highway_ambush", seats = "fortified_field_base|supply_depot|forest_camp" },
    { id = "alife_slackwater_rats", stance = "hostile", odds = 0.02, firstDay = 10, lastDay = 3650, encounters = "scavenger_crew|camp|roamer|outpost", seats = "forest_camp|holdout_house|sturdy_house", towns = "riverside|west_point|valley_station", allTowns = false },
    { id = "alife_black_lung_crew", stance = "hostile", odds = 0.02, firstDay = 14, lastDay = 3650, encounters = "scavenger_crew|outpost|roamer|patrol", seats = "forest_camp|supply_depot|holdout_house" },
    { id = "alife_breaker_nine", stance = "hostile", odds = 0.02, firstDay = 21, lastDay = 3650, encounters = "highway_ambush|blockade|broken_car|scavenger_crew", seats = "supply_depot|forest_camp|fortified_field_base" },
    { id = "alife_longshot_crew", stance = "hostile", odds = 0.02, firstDay = 14, lastDay = 3650, encounters = "scavenger_crew|outpost|patrol|roamer|broken_car", seats = "sturdy_house|holdout_house|forest_camp", towns = "muldraugh|rosewood|march_ridge|irvington", allTowns = false },
}

Balance.mergedInto = {
    ["alife_angler_pair"] = "alife_married_pair",
    ["alife_apartment_watch"] = "alife_bell_family",
    ["alife_armor_school"] = "alife_guard",
    ["alife_army_medical"] = "alife_guard",
    ["alife_bauer_family"] = "alife_vittitoe",
    ["alife_bledsoe"] = "alife_kettle",
    ["alife_chicago_contacts"] = "alife_renfro",
    ["alife_chopshop"] = "alife_kettle",
    ["alife_conservation_remnants"] = "alife_county_law_remnants",
    ["alife_cornbread_network"] = "alife_renfro",
    ["alife_cornfield"] = "alife_renfro",
    ["alife_corrections_remnants"] = "alife_county_law_remnants",
    ["alife_countyline"] = "alife_renfro",
    ["alife_courthouse"] = "alife_county_law_remnants",
    ["alife_coworker_pair"] = "alife_married_pair",
    ["alife_coyle"] = "alife_renfro",
    ["alife_crume"] = "alife_kettle",
    ["alife_dabney"] = "alife_hospital",
    ["alife_delta_detachment"] = "alife_sf_detachment",
    ["alife_diner_survivors"] = "alife_bell_family",
    ["alife_distillery_workers"] = "alife_kettle",
    ["alife_dixie_network"] = "alife_renfro",
    ["alife_engineer_holdouts"] = "alife_guard_remnants",
    ["alife_ferrymen"] = "alife_kettle",
    ["alife_first_family"] = "alife_renfro",
    ["alife_freeman_family"] = "alife_bell_family",
    ["alife_guard_engineers"] = "alife_guard",
    ["alife_guard_infantry"] = "alife_guard",
    ["alife_gunclub"] = "alife_preppers",
    ["alife_hensley_family"] = "alife_vittitoe",
    ["alife_highway_maintenance"] = "alife_lineworkers",
    ["alife_hobbs"] = "alife_renfro",
    ["alife_hornback_family"] = "alife_bell_family",
    ["alife_jefferson_police"] = "alife_police",
    ["alife_kessinger"] = "alife_vittitoe",
    ["alife_lawson_family"] = "alife_bell_family",
    ["alife_ledford"] = "alife_tackett",
    ["alife_lockup_escapees"] = "alife_riverside",
    ["alife_lone_commuter"] = "alife_lone_hiker",
    ["alife_lone_courier"] = "alife_lone_hiker",
    ["alife_lone_farmhand"] = "alife_lone_hiker",
    ["alife_lone_hitchhiker"] = "alife_lone_hiker",
    ["alife_lone_mechanic"] = "alife_lineworkers",
    ["alife_lone_nurse"] = "alife_county_ems",
    ["alife_lone_retiree"] = "alife_lone_hiker",
    ["alife_lone_student"] = "alife_lone_hiker",
    ["alife_lone_veteran"] = "alife_lone_hiker",
    ["alife_long_road"] = "alife_riverside",
    ["alife_lost_teen"] = "alife_lone_hiker",
    ["alife_lost_tourist"] = "alife_lone_hiker",
    ["alife_louisville_police"] = "alife_police",
    ["alife_mattingly_family"] = "alife_bell_family",
    ["alife_mercer_family"] = "alife_bell_family",
    ["alife_moonshine_coop"] = "alife_renfro",
    ["alife_mp_brigade"] = "alife_guard",
    ["alife_muldraugh_pd"] = "alife_police",
    ["alife_napier"] = "alife_bell_family",
    ["alife_napier_collectors"] = "alife_dixie_road",
    ["alife_nguyen_family"] = "alife_bell_family",
    ["alife_office_workers"] = "alife_riverside",
    ["alife_ortiz_family"] = "alife_bell_family",
    ["alife_otter_creek_trappers"] = "alife_riverside",
    ["alife_paramedics_offduty"] = "alife_county_ems",
    ["alife_pharmacy_staff"] = "alife_hospital",
    ["alife_postal_workers"] = "alife_riverside",
    ["alife_prather"] = "alife_church_volunteers",
    ["alife_price_family"] = "alife_bell_family",
    ["alife_prison_escape_pair"] = "alife_riverside",
    ["alife_prison_infirmary"] = "alife_hospital",
    ["alife_prison_peaceful"] = "alife_prison_predators",
    ["alife_pruitt_family"] = "alife_bell_family",
    ["alife_radio_station"] = "alife_bell_family",
    ["alife_rail_workers"] = "alife_kettle",
    ["alife_red_cross"] = "alife_hospital",
    ["alife_refugee_walkers"] = "alife_riverside",
    ["alife_reservist_remnants"] = "alife_guard_remnants",
    ["alife_rivermen"] = "alife_kettle",
    ["alife_riverside_pd"] = "alife_police",
    ["alife_rosewood_corrections"] = "alife_county_jail",
    ["alife_rosewood_pd"] = "alife_police",
    ["alife_sanitation"] = "alife_kettle",
    ["alife_sibling_pair"] = "alife_married_pair",
    ["alife_skaggs_family"] = "alife_vittitoe",
    ["alife_slaughter"] = "alife_fire",
    ["alife_stockyard"] = "alife_vittitoe",
    ["alife_stuck_trucker"] = "alife_lone_hiker",
    ["alife_sutter_family"] = "alife_bell_family",
    ["alife_telephone_crew"] = "alife_lineworkers",
    ["alife_trailer_neighbors"] = "alife_bell_family",
    ["alife_training_remnants"] = "alife_guard_remnants",
    ["alife_transit_strike"] = "alife_kettle",
    ["alife_transport_detail"] = "alife_guard",
    ["alife_traveller_pair"] = "alife_married_pair",
    ["alife_trooper_remnants"] = "alife_county_law_remnants",
    ["alife_turner_family"] = "alife_vittitoe",
    ["alife_utility_survivors"] = "alife_lineworkers",
    ["alife_vfd"] = "alife_fire",
    ["alife_walker_family"] = "alife_bell_family",
    ["alife_ward_survivors"] = "alife_hospital",
    ["alife_warehouse_nightshift"] = "alife_lineworkers",
    ["alife_waterworks"] = "alife_kettle",
    ["alife_westpoint_pd"] = "alife_police",
    ["alife_whitaker"] = "alife_lineworkers",
}

Balance.adopt = {
    { faction = "alife_police", members = { "k93_muldraugh_pd_02", "k93_rosewood_pd_02", "k93_riverside_pd_02", "k93_westpoint_pd_02", "k93_louisville_police_02", "k93_jefferson_police_02", "k93_muldraugh_pd_03", "k93_rosewood_pd_03", "k93_riverside_pd_03", "k93_westpoint_pd_03", "k93_louisville_police_03", "k93_jefferson_police_03", "k93_jefferson_police_09", "k93_louisville_police_09", "k93_muldraugh_pd_07", "k93_riverside_pd_07", "k93_rosewood_pd_09", "k93_westpoint_pd_09" } },
    { faction = "alife_county_jail", members = { "k93_rosewood_corrections_02", "k93_rosewood_corrections_03", "k93_rosewood_corrections_04", "k93_rosewood_corrections_09" } },
    { faction = "alife_county_law_remnants", members = { "k93_courthouse_02", "k93_trooper_remnants_02", "k93_corrections_remnants_02", "k93_conservation_remnants_02", "k93_courthouse_03", "k93_trooper_remnants_03", "k93_corrections_remnants_03", "k93_conservation_remnants_03", "k93_courthouse_04", "k93_trooper_remnants_04", "k93_corrections_remnants_04", "k93_conservation_remnants_04", "k93_conservation_remnants_08", "k93_corrections_remnants_07", "k93_courthouse_09", "k93_trooper_remnants_08" } },
    { faction = "alife_guard", members = { "k93_mp_brigade_02", "k93_guard_infantry_02", "k93_armor_school_02", "k93_guard_engineers_02", "k93_transport_detail_02", "k93_army_medical_02", "k93_mp_brigade_03", "k93_guard_infantry_03", "k93_armor_school_03", "k93_guard_engineers_03", "k93_transport_detail_03", "k93_army_medical_03", "k93_armor_school_10", "k93_army_medical_09", "k93_guard_engineers_07", "k93_guard_infantry_08", "k93_mp_brigade_07", "k93_transport_detail_07" } },
    { faction = "alife_guard_remnants", members = { "k93_engineer_holdouts_02", "k93_training_remnants_02", "k93_reservist_remnants_02", "k93_engineer_holdouts_03", "k93_training_remnants_03", "k93_reservist_remnants_03", "k93_engineer_holdouts_04", "k93_training_remnants_04", "k93_reservist_remnants_04", "k93_engineer_holdouts_09", "k93_reservist_remnants_10", "k93_training_remnants_09" } },
    { faction = "alife_sf_detachment", members = { "k93_delta_detachment_02", "k93_delta_detachment_03", "k93_delta_detachment_04", "k93_delta_detachment_09" } },
    { faction = "alife_fire", members = { "k93_vfd_02", "k93_slaughter_02", "k93_vfd_03", "k93_slaughter_03", "k93_vfd_04", "k93_slaughter_04", "k93_slaughter_07", "k93_vfd_07" } },
    { faction = "alife_county_ems", members = { "k93_lone_nurse_01", "k93_paramedics_offduty_02", "k93_lone_nurse_02", "k93_paramedics_offduty_03", "k93_paramedics_offduty_04", "k93_lone_nurse_04", "k93_paramedics_offduty_06" } },
    { faction = "alife_hospital", members = { "k93_red_cross_02", "k93_ward_survivors_02", "k93_prison_infirmary_02", "k93_dabney_02", "k93_pharmacy_staff_02", "k93_red_cross_03", "k93_ward_survivors_03", "k93_prison_infirmary_03", "k93_dabney_03", "k93_pharmacy_staff_03", "k93_red_cross_04", "k93_ward_survivors_04", "k93_dabney_08", "k93_pharmacy_staff_08", "k93_prison_infirmary_07", "k93_red_cross_07", "k93_ward_survivors_07" } },
    { faction = "alife_church_volunteers", members = { "k93_prather_02", "k93_prather_03", "k93_prather_04", "k93_prather_09" } },
    { faction = "alife_bell_family", members = { "k93_freeman_family_02", "k93_ortiz_family_02", "k93_nguyen_family_02", "k93_walker_family_02", "k93_price_family_02", "k93_lawson_family_02", "k93_mattingly_family_02", "k93_hornback_family_02", "k93_pruitt_family_02", "k93_sutter_family_02", "k93_mercer_family_02", "k93_trailer_neighbors_02", "k93_apartment_watch_09", "k93_diner_survivors_07", "k93_freeman_family_07", "k93_hornback_family_09", "k93_lawson_family_07", "k93_mattingly_family_07", "k93_mercer_family_09", "k93_napier_09", "k93_nguyen_family_09", "k93_ortiz_family_09", "k93_price_family_07", "k93_pruitt_family_07", "k93_radio_station_06", "k93_sutter_family_07", "k93_trailer_neighbors_09", "k93_walker_family_09" } },
    { faction = "alife_vittitoe", members = { "k93_kessinger_02", "k93_hensley_family_02", "k93_bauer_family_02", "k93_turner_family_02", "k93_skaggs_family_02", "k93_stockyard_02", "k93_kessinger_03", "k93_hensley_family_03", "k93_bauer_family_03", "k93_turner_family_03", "k93_skaggs_family_03", "k93_stockyard_03", "k93_bauer_family_10", "k93_hensley_family_07", "k93_kessinger_08", "k93_skaggs_family_08", "k93_stockyard_09", "k93_turner_family_08" } },
    { faction = "alife_tackett", members = { "k93_ledford_02", "k93_ledford_03", "k93_ledford_04", "k93_ledford_07" } },
    { faction = "alife_preppers", members = { "k93_gunclub_02", "k93_gunclub_03", "k93_gunclub_04", "k93_gunclub_10" } },
    { faction = "alife_kettle", members = { "k93_chopshop_02", "k93_crume_02", "k93_sanitation_02", "k93_waterworks_02", "k93_rail_workers_02", "k93_distillery_workers_02", "k93_transit_strike_02", "k93_rivermen_02", "k93_bledsoe_02", "k93_ferrymen_02", "k93_chopshop_03", "k93_crume_03", "k93_bledsoe_07", "k93_chopshop_09", "k93_crume_09", "k93_distillery_workers_07", "k93_ferrymen_09", "k93_rail_workers_09", "k93_rivermen_07", "k93_sanitation_09", "k93_transit_strike_08", "k93_waterworks_07" } },
    { faction = "alife_lineworkers", members = { "k93_utility_survivors_02", "k93_highway_maintenance_02", "k93_telephone_crew_02", "k93_lone_mechanic_01", "k93_warehouse_nightshift_02", "k93_whitaker_02", "k93_utility_survivors_03", "k93_highway_maintenance_03", "k93_telephone_crew_03", "k93_lone_mechanic_02", "k93_warehouse_nightshift_03", "k93_whitaker_03", "k93_highway_maintenance_09", "k93_lone_mechanic_07", "k93_telephone_crew_07", "k93_utility_survivors_07", "k93_warehouse_nightshift_07", "k93_whitaker_10" } },
    { faction = "alife_riverside", members = { "k93_office_workers_01", "k93_postal_workers_02", "k93_long_road_01", "k93_refugee_walkers_02", "k93_otter_creek_trappers_02", "k93_lockup_escapees_02", "k93_prison_escape_pair_02", "k93_office_workers_02", "k93_postal_workers_03", "k93_long_road_02", "k93_refugee_walkers_03", "k93_otter_creek_trappers_03", "k93_lockup_escapees_06", "k93_long_road_07", "k93_office_workers_09", "k93_otter_creek_trappers_07", "k93_postal_workers_06", "k93_prison_escape_pair_07", "k93_refugee_walkers_09" } },
    { faction = "alife_lone_hiker", members = { "k93_lone_commuter_01", "k93_lone_courier_01", "k93_lone_retiree_01", "k93_lone_farmhand_01", "k93_lone_student_01", "k93_lone_veteran_01", "k93_lone_hitchhiker_01", "k93_lost_tourist_01", "k93_lost_teen_01", "k93_stuck_trucker_01", "k93_lone_commuter_02", "k93_lone_courier_02", "k93_lone_commuter_07", "k93_lone_courier_07", "k93_lone_farmhand_05", "k93_lone_hitchhiker_05", "k93_lone_retiree_07", "k93_lone_student_07", "k93_lone_veteran_07", "k93_lost_teen_07", "k93_lost_tourist_05", "k93_stuck_trucker_07" } },
    { faction = "alife_married_pair", members = { "k93_sibling_pair_02", "k93_coworker_pair_02", "k93_angler_pair_02", "k93_traveller_pair_02", "k93_sibling_pair_03", "k93_coworker_pair_03", "k93_angler_pair_03", "k93_traveller_pair_03", "k93_sibling_pair_04", "k93_coworker_pair_04", "k93_angler_pair_05", "k93_coworker_pair_05", "k93_sibling_pair_05", "k93_traveller_pair_07" } },
    { faction = "alife_renfro", members = { "k93_countyline_02", "k93_coyle_02", "k93_hobbs_02", "k93_cornfield_02", "k93_cornbread_network_02", "k93_chicago_contacts_02", "k93_first_family_02", "k93_dixie_network_02", "k93_moonshine_coop_02", "k93_countyline_03", "k93_coyle_03", "k93_hobbs_03", "k93_chicago_contacts_09", "k93_cornbread_network_07", "k93_cornfield_09", "k93_countyline_09", "k93_coyle_09", "k93_dixie_network_09", "k93_first_family_07", "k93_hobbs_07", "k93_moonshine_coop_10" } },
    { faction = "alife_ironhorse", members = { "k93_outlaws_mc_02", "k93_grim_reapers_mc_02", "k93_undertakers_mc_02", "k93_outlaws_mc_03", "k93_grim_reapers_mc_03", "k93_undertakers_mc_03", "k93_outlaws_mc_04", "k93_grim_reapers_mc_04", "k93_undertakers_mc_04", "k93_grim_reapers_mc_08", "k93_outlaws_mc_08", "k93_undertakers_mc_08" } },
    { faction = "alife_derby_set", members = { "k93_vice_lords_02", "k93_gangster_disciples_02", "k93_bloods_victory_02", "k93_crips_victory_02", "k93_vice_lords_03", "k93_gangster_disciples_03", "k93_bloods_victory_03", "k93_crips_victory_03", "k93_vice_lords_04", "k93_gangster_disciples_04", "k93_bloods_victory_04", "k93_crips_victory_04", "k93_bloods_victory_10", "k93_crips_victory_08", "k93_gangster_disciples_10", "k93_vice_lords_08" } },
    { faction = "alife_dixie_road", members = { "k93_napier_collectors_02", "k93_napier_collectors_03", "k93_napier_collectors_04", "k93_napier_collectors_10" } },
    { faction = "alife_pit", members = { "k93_cinder_raiders_02", "k93_scrapyard_reavers_02", "k93_cinder_raiders_03", "k93_scrapyard_reavers_03", "k93_cinder_raiders_04", "k93_scrapyard_reavers_04", "k93_cinder_raiders_08", "k93_scrapyard_reavers_08" } },
    { faction = "alife_bone_raiders", members = { "k93_tollmen_02", "k93_convoy_predators_02", "k93_tollmen_03", "k93_convoy_predators_03", "k93_tollmen_04", "k93_convoy_predators_04", "k93_convoy_predators_10", "k93_tollmen_10" } },
    { faction = "alife_prison_predators", members = { "k93_prison_peaceful_02", "k93_prison_peaceful_03", "k93_prison_peaceful_04", "k93_prison_peaceful_07" } },
}

function Balance.legacy()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(vars) == "table" and vars[Balance.option] == true
end

function Balance.keptScale(faction)
    if Balance.keepMerged ~= true or type(faction) ~= "table" or Balance.mergedInto[tostring(faction.id)] == nil then return 1 end
    if Balance.legacy() then return 1 end
    local spawn = type(faction.spawn) == "table" and faction.spawn or nil
    if spawn ~= nil and (tonumber(spawn.most) or 9) <= 1 then return 1 end
    return tonumber(Balance.mergedScale) or 1
end

function Balance.moodRows()
    if Balance.legacy() then return Balance.moodLegacy end
    return Balance.mood
end

function Balance.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = Balance.copy(item, seen) end
    return result
end

function Balance.visitorOnly(faction)
    return type(faction) == "table" and type(faction.spawn) == "table" and faction.spawn.visitorOnly == true
end

function Balance.retire(faction, survivorId)
    if Balance.visitorOnly(faction) then return end
    faction.spawn = type(faction.spawn) == "table" and faction.spawn or {}
    faction.spawn.enabled = false
    faction.spawn.hiddenFromSpawn = true
    faction.spawn.mergedInto = survivorId
end

function Balance.setRow(faction, row)
    if Balance.visitorOnly(faction) then return end
    faction.spawn = type(faction.spawn) == "table" and faction.spawn or {}
    faction.relations = type(faction.relations) == "table" and faction.relations or {}
    faction.general = type(faction.general) == "table" and faction.general or {}
    local spawn = faction.spawn
    faction.relations.player = row.stance
    spawn.odds = row.odds
    spawn.encounterPool = row.encounters
    if row.title ~= nil then faction.general.name = row.title end
    if row.firstDay ~= nil then spawn.firstDay = row.firstDay end
    if row.lastDay ~= nil then spawn.lastDay = row.lastDay end
    if row.peaceable ~= nil then spawn.peaceable = row.peaceable end
    if row.seats ~= nil then spawn.seats = row.seats end
    if row.towns ~= nil then spawn.towns = row.towns end
    if row.allTowns ~= nil then spawn.allTowns = row.allTowns end
    spawn.enabled = true
    spawn.hiddenFromSpawn = nil
    spawn.mergedInto = nil
end

Balance.restored = {
    ["alife_vice_lords"] = true,
    ["alife_gangster_disciples"] = true,
    ["alife_bloods_victory"] = true,
    ["alife_crips_victory"] = true,
    ["alife_outlaws_mc"] = true,
    ["alife_grim_reapers_mc"] = true,
    ["alife_undertakers_mc"] = true,
    ["alife_cinder_raiders"] = true,
    ["alife_scrapyard_reavers"] = true,
    ["alife_convoy_predators"] = true,
    ["alife_tollmen"] = true,
}

function Balance.restoredMember(memberId)
    local id = tostring(memberId)
    for factionId in pairs(Balance.restored) do
        local prefix = "k93_" .. string.sub(factionId, 7) .. "_"
        if string.sub(id, 1, #prefix) == prefix then return true end
    end
    return false
end

function Balance.adoptMembers(loaded)
    local added = 0
    for _, entry in ipairs(Balance.adopt) do
        if loaded.factions[entry.faction] ~= nil and not Balance.visitorOnly(loaded.factions[entry.faction]) then
            for _, memberId in ipairs(entry.members) do
                local source = loaded.npcs[memberId]
                local id = memberId .. Balance.cloneSuffix
                if type(source) == "table" and type(source.general) == "table" and loaded.npcs[id] == nil then
                    local clone = Balance.copy(source)
                    clone.id = id
                    clone.general.faction = entry.faction
                    clone.general.spawnWeight = (Balance.keepMerged == true or Balance.restoredMember(memberId)) and 0
                        or Balance.adoptWeight
                    loaded.npcs[id] = clone
                    loaded.npcOrder[#loaded.npcOrder + 1] = clone
                    added = added + 1
                end
            end
        end
    end
    return added
end

function Balance.apply(loaded)
    Balance.applied, Balance.retired, Balance.adopted, Balance.kept = false, 0, 0, 0
    if type(loaded) ~= "table" or type(loaded.factions) ~= "table" or type(loaded.npcs) ~= "table" then return loaded end
    if Balance.legacy() then return loaded end
    for _, row in ipairs(Balance.rows) do
        local faction = loaded.factions[row.id]
        if faction ~= nil then Balance.setRow(faction, row) end
    end
    for old, survivorId in pairs(Balance.mergedInto) do
        local faction = loaded.factions[old]
        if faction ~= nil and loaded.factions[survivorId] ~= nil and not Balance.visitorOnly(faction) then
            if Balance.keepMerged == true then
                Balance.kept = Balance.kept + 1
            else
                Balance.retire(faction, survivorId)
                Balance.retired = Balance.retired + 1
            end
        end
    end
    Balance.adopted = Balance.adoptMembers(loaded)
    Balance.applied = true
    return loaded
end

function Balance.activeIds()
    local list = {}
    for _, row in ipairs(Balance.rows) do list[#list + 1] = row.id end
    return list
end

return Balance
