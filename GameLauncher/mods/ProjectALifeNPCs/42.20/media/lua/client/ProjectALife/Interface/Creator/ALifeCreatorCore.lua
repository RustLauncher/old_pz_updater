require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Records/ALifeCustomFactions"
require "ProjectALife/Records/ALifeFactionShare"
require "ProjectALife/Records/ALifePartyPolicy"
require "ProjectALife/Records/ALifeCustomProfiles"
require "ProjectALife/Records/ALifeDropPolicy"
require "ProjectALife/Records/ALifeCustomProfileClient"
require "ProjectALife/Records/ALifeCreatorTransfer"
require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/Records/ALifeBehaviorProfiles"
require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/World/ALifeSpawnRegions"
require "ProjectALife/Audio/ALifeVoiceCatalog"
require "ProjectALife/Audio/ALifeVoiceAssignment"
require "ProjectALife/Audio/ALifeAudioPolicy"
require "ProjectALife/Audio/ALifeInteractionCues"
require "ProjectALife/Interface/Creator/ALifeCreatorFolders"
require "ProjectALife/Interface/ALifeStatusStore"
require "ProjectALife/Compat/ALifeModCompat"
require "ProjectALife/Core/ALifeText"
require "ISUI/ISColorPicker"
require "ISUI/ISColorPickerHSB"
require "ISUI/ISModalDialog"
require "RadioCom/ISUIRadio/ISSliderPanel"

ProjectALife = ProjectALife or {}

local Creator = { window = nil, serial = 0 }
ProjectALife.CreatorScreen = Creator

Creator.layout = "domains"

local ROSE = { r = 0.34, g = 0.52, b = 0.57, a = 1 }
local ROSE_DARK = { r = 0.022, g = 0.032, b = 0.036, a = 1 }
local PANEL_BG = { r = 0.010, g = 0.013, b = 0.015, a = 1 }
local CARD_BG = { r = 0.017, g = 0.022, b = 0.024, a = 1 }
local CONTROL_BG = { r = 0.028, g = 0.035, b = 0.038, a = 1 }
local CONTROL_BORDER = { r = 0.115, g = 0.145, b = 0.152, a = 1 }
local TEXT = { r = 0.79, g = 0.81, b = 0.79, a = 1 }
local MUTED = { r = 0.43, g = 0.48, b = 0.47, a = 1 }

local function copyColor(value)
    if type(value) ~= "table" then return value end
    return { r = value.r, g = value.g, b = value.b, a = value.a }
end

local SCENARIOS = {
    { "Travelling survivors", "roamer", "Travel between places" },
    { "Patrol", "patrol", "An open-area route" },
    { "Town patrol", "town_patrol", "Streets and neighborhoods" },
    { "Scavengers", "scavenger_crew", "Search for supplies" },
    { "Fishing parties", "fishing_party", "Rods at the water's edge" },
    { "Hunting parties", "hunting_party", "Hunters on the tree line" },
    { "Foraging parties", "foraging_party", "Picking the ground over" },
    { "Firewood camps", "firewood_camp", "Chopping and sawing" },
    { "Camp builders", "camp_builders", "Building a storage crate" },
    { "Scavenging trips", "scavenging_trip", "Out from base and home again" },
    { "Water runs", "water_run", "Bottles to the nearest water" },
    { "Camps", "camp", "Outdoor survivor camps" },
    { "Outposts & residents", "outpost", "Bases and building garrisons" },
    { "Station guards", "poi_defenders", "Protect important buildings" },
    { "Rooftop shooters", "rooftop_snipers", "Hold elevated positions" },
    { "Road blockade", "blockade", "Defend a stretch of road" },
    { "Broken-down car", "broken_car", "Stranded repair crew" },
    { "Road crash", "car_crash", "Triggered by world events" },
    { "Highway ambush", "highway_ambush", "Triggered by driving" },
    { "Enemy scouts", "raid", "Hostile reconnaissance" },
    { "Assassination", "assassination", "Hunt a target" },
    { "Full-scale raid", "fullscale_raid", "Scout buildup + raid-day rules" },
}

Creator.partyIcons = {
    fishing_party = "roamer", hunting_party = "roamer", foraging_party = "scavenger_crew",
    firewood_camp = "camp", camp_builders = "camp", scavenging_trip = "scavenger_crew", water_run = "scavenger_crew",
}

Creator.outpostSeats = {
    { "Holdout", "holdout_house", "A house a family holds" },
    { "Walled compound", "alexandria", "A walled settlement" },
    { "Fortified station", "police_station", "A station turned into a base" },
    { "Held house", "sturdy_house", "A sturdy house, garrisoned" },
    { "Fortified field base", "fortified_field_base", "A built camp in the open" },
    { "Forest camp", "forest_camp", "A camp under the trees" },
    { "Field aid station", "field_hospital", "A place that treats people" },
    { "Supply depot", "supply_depot", "Stores, and people guarding them" },
    { "Checkpoint", "bridge_checkpoint", "A bridge or road cordon" },
}
local PROGRAMS = {
    { "Patrol / guard", "patrol" }, { "Scavenge / loot", "looter" },
    { "Roam", "roam" }, { "Hunt", "hunt" }, { "Manhunt", "manhunt" },
}
local SPECIFIC_PLACES = {
    { "Police & prisons", "police" }, { "Fire stations", "fire" },
    { "Hospitals & clinics", "medical" }, { "Warehouses", "warehouse" },
    { "Gun & military sites", "guns" },
}

local HAIR = { "", "Bald", "Spike", "CentreParting", "CentrePartingLong",
    "LeftParting", "RightParting", "PonyTail", "PonyTailBraids", "Braids",
    "Cornrows", "GreasedBack", "FlatTop", "Grungey" }
local BEARD = { "", "Chops", "Moustache", "Goatee", "BeardOnly", "Chin",
    "Full", "Long", "LongScruffy" }
local SKIN_COLORS = {
    { r = 1.00, g = 0.91, b = 0.72 }, { r = 0.98, g = 0.79, b = 0.49 },
    { r = 0.80, g = 0.65, b = 0.45 }, { r = 0.54, g = 0.38, b = 0.25 },
    { r = 0.36, g = 0.25, b = 0.14 },
}

Creator.hairPalette = {
    natural = {
        { r = 0.05, g = 0.05, b = 0.07 }, { r = 0.11, g = 0.09, b = 0.08 },
        { r = 0.20, g = 0.13, b = 0.09 }, { r = 0.31, g = 0.20, b = 0.12 },
        { r = 0.45, g = 0.27, b = 0.15 }, { r = 0.52, g = 0.22, b = 0.12 },
        { r = 0.68, g = 0.33, b = 0.16 }, { r = 0.80, g = 0.55, b = 0.38 },
        { r = 0.78, g = 0.60, b = 0.34 }, { r = 0.74, g = 0.66, b = 0.48 },
        { r = 0.66, g = 0.62, b = 0.53 }, { r = 0.91, g = 0.88, b = 0.80 },
        { r = 0.42, g = 0.41, b = 0.40 }, { r = 0.68, g = 0.68, b = 0.70 },
        { r = 0.93, g = 0.93, b = 0.92 },
    },
    dyed = {
        { r = 0.96, g = 0.93, b = 0.75 }, { r = 0.60, g = 0.06, b = 0.10 },
        { r = 0.12, g = 0.22, b = 0.62 }, { r = 0.36, g = 0.14, b = 0.52 },
        { r = 0.18, g = 0.40, b = 0.20 }, { r = 0.93, g = 0.42, b = 0.66 },
        { r = 0.10, g = 0.46, b = 0.48 },
    },
}

Creator.hairPalette.fallback = Creator.hairPalette.natural[3]
local CLOTHING = {
    Hat = { "none", "Base.Hat_Bandana", "Base.Hat_BaseballCap", "Base.Hat_Beany",
        "Base.Hat_Fedora", "Base.Hat_HardHat", "Base.Hat_Army" },
    Eyes = { "none", "Base.Glasses", "Base.Glasses_Aviators", "Base.Glasses_Sun" },
    Mask = { "none", "Base.Hat_BalaclavaFace", "Base.Hat_DustMask" },

    Faces = { "none", "Base.face5" },

    Top = { "Base.Shirt_Workman", "Base.Shirt_Denim", "Base.Shirt_Lumberjack",
        "Base.Tshirt_DefaultTEXTURE_TINT", "Base.Shirt_FormalWhite" },
    Jacket = { "none", "Base.Jacket_Leather", "Base.JacketLong_Random",
        "Base.Jacket_Black", "Base.Jacket_ArmyCamoGreen" },
    Vest = { "none", "Base.Vest_HighViz", "Base.Vest_BulletCivilian",
        "Base.Vest_BulletPolice", "Base.Vest_BulletArmy" },
    Hands = { "none", "Base.Gloves_LeatherGloves", "Base.Gloves_FingerlessGloves" },
    Pants = { "Base.Trousers_Denim", "Base.Trousers", "Base.Trousers_Suit",
        "Base.Shorts_LongDenim", "Base.Trousers_CamoGreen" },
    Socks = { "none", "Base.Socks_Ankle", "Base.Socks_Long" },
    Shoes = { "Base.Shoes_Random", "Base.Shoes_ArmyBoots", "Base.Shoes_Black",
        "Base.Shoes_TrainerTINT" },
    Back = { "none", "Base.Bag_Schoolbag", "Base.Bag_DuffelBagTINT",
        "Base.Bag_ALICEpack" },
    Ears = { "none" },
    Neck = { "none" },
    Scarf = { "none" },
    Wrist = { "none" },
    Fingers = { "none" },
    Underwear = { "none" },
    AmmoStrap = { "none" },

    MakeUpFullFace = { "none" },
    MakeUpEyes = { "none" },
    MakeUpEyesShadow = { "none" },
    MakeUpLips = { "none" },

    ModdedA = { "none" },
    ModdedB = { "none" },
    ModdedC = { "none" },
}
local CLOTHING_ORDER = {
    "Hat", "Eyes", "Mask", "Ears", "Faces", "Neck", "Scarf",
    "Top", "Jacket", "Vest", "AmmoStrap", "Hands", "Wrist",
    "Fingers", "Underwear", "Pants", "Socks", "Shoes", "Back",
    "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftHand", "RightHand",
    "LeftWrist", "RightWrist", "LeftShin", "RightShin", "LeftGaiter", "RightGaiter",
    "Belt", "Holster", "ShoulderHolster", "AnkleHolster", "FannyPackFront", "FannyPackBack",
    "Necklace", "LongNecklace", "Nose", "BellyButton", "LeftRing", "RightRing",
    "LeftMiddleRing", "RightMiddleRing", "UnderwearTop", "UnderwearBottom",
    "LongJohnsTop", "LongJohnsBottom", "TankTop", "Tshirt", "Sweater", "ShoulderPads",
    "Gorget", "Cuirass", "Codpiece", "Apron", "Tail", "FullSuit", "FullRobe",
    "LeftGreave", "RightGreave", "LeftKnee", "RightKnee", "LeftThigh", "RightThigh",
    "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "Webbing", "BreathingGear",

    "MakeUpFullFace", "MakeUpEyes", "MakeUpEyesShadow", "MakeUpLips",
    "ModdedA", "ModdedB", "ModdedC",
}
local PRIMARY = { "none", "Base.Pistol", "Base.Pistol2", "Base.Pistol3",
    "Base.Revolver", "Base.Revolver_Long", "Base.Shotgun",
    "Base.DoubleBarrelShotgun", "Base.VarmintRifle", "Base.HuntingRifle",
    "Base.AssaultRifle", "Base.AssaultRifle2" }
local MELEE = { "none", "Base.HuntingKnife", "Base.Machete", "Base.Crowbar",
    "Base.BaseballBat", "Base.HandAxe", "Base.Axe", "Base.SpearCrafted" }
local GENDERS = { { "Male", "male" }, { "Female", "female" } }
Creator.genders = GENDERS
Creator.skinColors = SKIN_COLORS

local VOICES = {
    { "Automatic  /  faction voice", "" },
    { "Outlaw Survivor 1", "pal_outlaw_1" },
    { "Outlaw Survivor 2", "pal_outlaw_2" },
    { "Outlaw Survivor 3", "pal_outlaw_3" },
    { "Experienced Survivor 1", "pal_csky_1" },
    { "Experienced Survivor 2", "pal_csky_2" },
    { "Experienced Survivor 3", "pal_csky_3" },
    { "Paramilitary Survivor 1", "pal_dolg_1" },
    { "Paramilitary Survivor 2", "pal_dolg_2" },
    { "Paramilitary Survivor 3", "pal_dolg_3" },
    { "Scientist 1", "pal_ecolog_1" },
    { "Scientist 2", "pal_ecolog_2" },
    { "Scientist 3", "pal_ecolog_3" },
    { "Anarchist Survivor 1", "pal_freedom_1" },
    { "Anarchist Survivor 2", "pal_freedom_2" },
    { "Anarchist Survivor 3", "pal_freedom_3" },
    { "Military Soldier 1", "pal_military_1" },
    { "Military Soldier 2", "pal_military_2" },
    { "Military Soldier 3", "pal_military_3" },
    { "Foreign Survivor 1", "pal_stalker_1" },
    { "Foreign Survivor 2", "pal_stalker_2" },
    { "Foreign Survivor 3", "pal_stalker_3" },
    { "Mercenary 1", "pal_mercenary_1" },
    { "Mercenary 2", "pal_mercenary_2" },
    { "Mercenary 3", "pal_mercenary_3" },
    { "Mercenary 4", "pal_mercenary_4" },
    { "Mercenary 5", "pal_mercenary_5" },
    { "Mercenary 6", "pal_mercenary_6" },
    { "Mercenary 7", "pal_mercenary_7" },
    { "Mercenary 8", "pal_mercenary_8" },
    { "Law Enforcement - Team Lead", "pal_law_enforcement_team_lead" },
    { "Law Enforcement - Operator 1", "pal_law_enforcement_operator_1" },
    { "Law Enforcement - Operator 2", "pal_law_enforcement_operator_2" },
    { "Law Enforcement - Operator 3", "pal_law_enforcement_operator_3" },
    { "Law Enforcement - Operator 4", "pal_law_enforcement_operator_4" },
    { "American Survivor 1", "pal_american_survivor_1" },
    { "American Survivor 2", "pal_american_survivor_2" },
    { "American Survivor 3", "pal_american_survivor_3" },
    { "Russian Survivor 1", "pal_russian_survivor_1" },
    { "Russian Survivor 2", "pal_russian_survivor_2" },
    { "Russian Survivor 3", "pal_russian_survivor_3" },
    { "Foreign Female Survivor", "pal_foreign_female_survivor" },
    { "American Female Survivor", "pal_american_female_survivor" },
}
local ROLES = {
    { "Scout", "Scout" }, { "Guard", "Guard" }, { "Raider", "Raider" },
    { "Heavy", "Heavy" }, { "Medic", "Medic" }, { "Leader", "Leader" },
    { "Sniper", "Sniper" }, { "Scavenger", "Scavenger" },
    { "Radio operator", "RadioOperator" }, { "Breacher", "Breacher" },
    { "Mechanic", "Mechanic" }, { "Driver", "Driver" },
    { "Quartermaster", "Quartermaster" }, { "Hunter", "Hunter" },
    { "Civilian", "Civilian" },
}
for _,id in ipairs(ProjectALife.VoiceCatalog.profileIds()) do
    local voice=ProjectALife.VoiceCatalog.profiles[id]
    if voice.sourcePack=="legacy_imported" then VOICES[#VOICES+1]={voice.label,id} end
end
local RANKS = {
    { "Recruit", "Recruit" }, { "Regular", "Regular" },
    { "Veteran", "Veteran" }, { "Elite", "Elite" }, { "Leader", "Leader" },
}
local ACTIVITIES = {
    { "Patrol / Scavenge", "patrol" }, { "Scavenge", "scavenge" },
    { "Guard", "guard" }, { "Hunt", "hunt" }, { "Manhunt", "manhunt" },
    { "Assault", "assault" }, { "Full Raid", "full_raid" },
}
local PROFILE_MODULES = {
    { "Decision module", "decisions" }, { "Perception module", "perception" },
    { "Movement module", "movement" }, { "Combat module", "combat" },
    { "Scavenging module", "scavenging" }, { "Voice module", "voice" },
}
local FACTION_MODULES = {
    { "Encounter module", "encounter" }, { "Raid module", "raid" },
    { "Relations module", "relations" }, { "Director module", "director" },
}

local RELATIONS = {
    { "Allied", "allied" }, { "Friendly", "friendly" },
    { "Neutral", "neutral" }, { "Careful", "careful" },
    { "Hostile", "hostile" },
}

local AMMO_MODES = { { "Magazines", "magazines" } }
local COMBAT_READY = {
    { "Default (Mixed)", "default" }, { "Yes", "yes" },
    { "No", "no" }, { "Mixed", "mixed" },
}
local BEHAVIOR_PROFILES = {}
for _, profile in ipairs(ProjectALife.BehaviorProfiles.list()) do
    BEHAVIOR_PROFILES[#BEHAVIOR_PROFILES + 1] = { profile.label, profile.id }
end
local PRIMARY_BEHAVIORS = {
    { "None", "none" }, { "Leader", "leader" }, { "Gunner", "gunner" },
    { "Medic", "medic" }, { "Sniper", "sniper" },
    { "Stealth", "stealth" }, { "Ambusher", "ambusher" },
}

local MEMBER_MODULES = {
    { "Follow orders", "orders", "orders" }, { "Hold stance", "stance", "orders" },
    { "Panic", "panic", "reaction" }, { "Fear of the dead", "fear", "reaction" },
    { "Gun fear", "gunFear", "reaction" },
    { "Withdraw", "withdraw", "reaction" }, { "Flee", "flee", "reaction" },
    { "Warn first", "warning", "reaction" },
    { "Strafe", "strafe", "craft" }, { "Weave", "weave", "craft" },
    { "Cover", "cover", "craft" }, { "Door stack", "doorstack", "craft" },
    { "CQB sweep", "cqbsweep", "craft" }, { "Flanking", "flanking", "craft" },
    { "Melee footwork", "meleeFootwork", "craft" }, { "Melee flank", "meleeFlank", "craft" },
    { "Axe breacher", "meleeBreach", "craft" }, { "Intimidate", "meleeIntimidate", "craft" },
    { "Melee caution", "meleeCaution", "craft" },
    { "Avoid zombies (Off = fight them)", "zombieAvoid", "reaction" },
    { "Switch to melee vs zombies", "weaponSwitchMelee", "craft" },
    { "Healing", "healing", "upkeep" }, { "Scavenge", "scavenge", "upkeep" }, { "Home base", "home", "upkeep" },
    { "Search", "search", "upkeep" },
    { "Investigate", "investigate", "upkeep" }, { "Idle life", "idleLife", "upkeep" },
    { "Regroup", "regroup", "upkeep" }, { "Group march", "groupMarch", "upkeep" },
    { "Spread", "spread", "upkeep" }, { "Patrol rest", "patrolRest", "upkeep" },
    { "Group plan", "plan", "upkeep" },

    { "Rob players", "robbery", "outlaw" },
}
local MODULE_HELP = {
    orders = "Follow the leader's current order instead of selecting an unrelated task.",
    stance = "Hold the assigned guard, route, blockade or garrison stance until the squad changes it.",
    panic = "React to overwhelming danger and recover after reaching a safer distance.",
    fear = "Members of civilian class (and, less easily, rescue and worker class) leave distant zombies alone and run as a group when too many close in; police, military and criminal members, veterans and hardened members stay steady. Set each member's class on its Identity page. The world Fear switch and Fear days also apply.",
    gunFear = "Back away and run from a player or hostile who aims or raises a firearm, toward cover that breaks line of sight, then return once the gun has been out of sight for a few seconds. Armed members never use it, and leaders, snipers and ambushers hold their ground. Inherit follows the member's class: on for civilian, worker and rescue, off for police, military and criminal; On forces it for this member or faction. The world Gun fear switch and chance also apply.",
    withdraw = "Back away while facing and aiming at the threat; fire remains available during the retreat.",
    flee = "Allow a full break-contact escape. The world Flee switch must also be enabled; a faction or NPC override cannot bypass it.",
    warning = "A hostile crew shouts a warning and gives the player a moment before the first shot, may knock before it enters a base, and may stop him for a few questions and a toll. Off means kill on sight: no warning, no grace, no toll question, and a hold-up never starts. On means this crew always warns, except in a raid. Raid crews, assassins and ambushers ship Off, and raids, assassinations and highway ambushes are kill on sight whatever a crew's setting. The Warning sandbox settings give an Off crew a chance to warn anyway and put a time limit on every warning.",
    strafe = "Move laterally while keeping the weapon and attention on the current target.",
    weave = "Vary the approach path under fire instead of running in one predictable line.",
    cover = "Search for nearby cover and fight from it when the path and line of fire are valid.",
    doorstack = "Queue at an entrance so squad members do not jam the same doorway.",
    cqbsweep = "Clear close interior spaces in a controlled room-to-room sequence.",
    flanking = "Move to a side angle when another squad member already occupies the target's attention.",
    meleeFootwork = "Melee fighters step back and sideways between swings with their face to the enemy, back off from a press of zombies and step back in. Needs the Melee crew sandbox switch.",
    meleeFlank = "In a melee group one member engages and the others circle to the far side of the target. Needs the Melee crew sandbox switch.",
    meleeBreach = "A fighter holding an axe cuts through doors and windows faster and does it when checking a noise. Needs the Melee crew sandbox switch.",
    meleeIntimidate = "Walk up on a player at a walk, shout the warning from range, then close in to strike. Needs the Melee crew sandbox switch.",
    meleeCaution = "Retreat early when a few zombies close in, then return. Needs the Melee crew sandbox switch.",
    zombieAvoid = "How this NPC treats zombies. Inherit keeps the standard caution: detour or wait when a crowd stands on the route, leave a zombie alone while on a mission, fight it when it attacks. On avoids zombies harder: waits or detours for a single one and fights only when attacked. Off fights zombies on sight: no travel waits or detours, and guns are never held back.",
    weaponSwitchMelee = "Inherit and On keep the standard gun discipline: a gun user may leave the gun stowed and use a melee weapon, a rifle-butt shove or walk past a zombie. Off makes this NPC use the weapon it holds against zombies: no holding fire, no switch to melee, no shove at point blank. Ammo-out and reload swaps stay.",
    healing = "Treat wounds during a safe pause and return to the previous squad task afterwards.",
    scavenge = "Search valid containers, reserve loot and carry useful supplies for the squad.",
    search = "After combat, search at most two bodies (at most one infected). Take a bounded quarter of non-clothing items, prioritizing weapons. Gear remains recoverable.",
    investigate = "Inspect recent sounds, sightings and clues without forgetting the squad objective.",
    idleLife = "Use believable calm-state activities while no urgent task or threat is active.",
    regroup = "Return isolated members to a safe formation around the squad leader.",
    groupMarch = "Travel as a formation instead of sending every member through an independent path.",
    spread = "Maintain useful spacing so the squad does not form a single vulnerable cluster.",
    patrolRest = "Let patrols pause together for rest, idle activities and conversation. Rest timing and the master switch come from sandbox settings.",
    plan = "A free group picks a goal (loot a building, find a radio, get supplies, find a roof for the night), talks it over, walks there and sticks to it until it is done, blocked or too dangerous. The sandbox Groups make plans switch also applies.",
    robbery = "Hold up a player: weapons down, hands up, a few valuable items taken, then the crew leaves. Refusing gets him shot. Inherit robs by register (raiders almost always, mercenaries about half the time) and only when the player is alone. On means this crew always tries, whatever its faction and whoever he is with.",
}
local MODULE_GROUPS = {
    { "orders", "ORDERS", "Leadership and assigned stance" },
    { "reaction", "DANGER RESPONSE", "Warnings, controlled retreat and escape" },
    { "craft", "COMBAT MOVEMENT", "Cover, spacing and coordinated manoeuvres" },
    { "upkeep", "SURVIVAL & ROUTINE", "Recovery, scavenging and calm-state activity" },
    { "outlaw", "OUTLAW CONDUCT", "Demands made of players at gunpoint" },
}
local MODULE_STATES = {
    { "Inherit", "inherit" }, { "On", "on" }, { "Off", "off" },
}
Creator.moduleControlLabel = function(spec)
    return tostring(spec[1])
end
local VOICE_EVENTS = {}
for _, id in ipairs(ProjectALife.VoiceCatalog.eventIds()) do
    VOICE_EVENTS[#VOICE_EVENTS + 1] = {
        tostring(id):gsub("_", " "):lower():gsub("^%l", string.upper), id,
    }
end
local OUTFIT_IDS = { "A", "B", "C", "D", "E", "F" }
Creator.outfitIds = OUTFIT_IDS

Creator.outfitSeasonChoices = {
    { "Any season", "random" }, { "Spring only", "spring" },
    { "Summer only", "summer" }, { "Autumn only", "autumn" },
    { "Winter only", "winter" },
}
Creator.spawnWeightChoices = { { "Common", 1 }, { "Uncommon", 0.5 },
    { "Rare", 0.2 }, { "Very Rare", 0.05 }, { "Unseen", 0 } }
Creator.clothingOrder = CLOTHING_ORDER
Creator.clothingChoices = CLOTHING

Creator.makeupItems = {
    MakeUpFullFace = {
        "Base.MakeUp_CamoFullFace1", "Base.MakeUp_CamoFullFace2",
        "Base.MakeUp_BraveHeart", "Base.MakeUp_ClownFace1",
        "Base.MakeUp_ClownFace2", "Base.MakeUp_SkullFace1",
        "Base.MakeUp_SkullFace2",
    },
    MakeUpEyes = {
        "Base.MakeUp_Crow", "Base.MakeUp_RedStripes1", "Base.MakeUp_RedStripes2",
        "Base.MakeUp_CamoEyes1", "Base.MakeUp_CamoEyes2",
        "Base.MakeUp_CamoStripes", "Base.MakeUp_Football",
    },
    MakeUpEyesShadow = {
        "Base.MakeUp_EyesShadowWhite", "Base.MakeUp_EyesShadowLightBlue",
        "Base.MakeUp_EyesShadowBlue", "Base.MakeUp_EyesShadowRed",
        "Base.MakeUp_EyesShadowPink", "Base.MakeUp_EyesShadowGreen",
        "Base.MakeUp_EyesShadowYellow",
    },
    MakeUpLips = {
        "Base.MakeUp_LipsRed", "Base.MakeUp_LipsLightBlue", "Base.MakeUp_LipsBlue",
        "Base.MakeUp_LipsBlack", "Base.MakeUp_LipsGreen", "Base.MakeUp_LipsPink",
    },
}

Creator.makeupRows = {
    { "MakeUpFullFace", "Full face" },
    { "MakeUpEyes", "Eyes" },
    { "MakeUpEyesShadow", "Eyeshadow" },
    { "MakeUpLips", "Lips" },
}
Creator.makeupRowHeight = 36

Creator.makeupSwatches = {
    CamoFullFace1 = { "makeup_0006_camo ", 0.514, 0.490, 0.363, true },
    CamoFullFace2 = { "makeup_0007_camo2", 0.496, 0.535, 0.329, true },
    BraveHeart = { "makeup_0010_braveheart", 0.559, 0.727, 0.849, true },
    ClownFace1 = { "makeup_0011_clown1", 0.718, 0.578, 0.568, true },
    ClownFace2 = { "makeup_0012_clown2", 0.915, 0.843, 0.822, true },
    SkullFace1 = { "makeup_0013_skull1", 0.819, 0.810, 0.792, true },
    SkullFace2 = { "makeup_0014_skull2", 0.793, 0.724, 0.706, true },
    Crow = { "makeup_0001_crow", 0.371, 0.381, 0.358, true },
    RedStripes1 = { "makeup_0003_redstripes", 0.662, 0.300, 0.247, true },
    RedStripes2 = { "makeup_0002_redstripes2", 0.470, 0.117, 0.098, true },
    CamoEyes1 = { "makeup_0005_camo3", 0.301, 0.391, 0.219, true },
    CamoEyes2 = { "makeup_0004_camo4", 0.353, 0.413, 0.164, true },
    CamoStripes = { "makeup_0008_stripes", 0.244, 0.241, 0.239, true },
    Football = { "makeup_0009_football", 0.285, 0.285, 0.285, true },
    EyesShadowWhite = { "makeup_0015_eyeshadowwhite", 0.651, 0.651, 0.651, false },
    EyesShadowLightBlue = { "makeup_0015_eyeshadowlightblue", 0.439, 0.757, 0.800, false },
    EyesShadowBlue = { "makeup_0015_eyeshadowblue", 0.427, 0.478, 0.804, false },
    EyesShadowRed = { "makeup_0015_eyeshadowred", 0.910, 0.212, 0.224, false },
    EyesShadowPink = { "makeup_0015_eyeshadowpink", 0.871, 0.271, 0.722, false },
    EyesShadowGreen = { "makeup_0015_eyeshadowgreen", 0.518, 0.765, 0.502, false },
    EyesShadowYellow = { "makeup_0015_eyeshadowyellow", 0.804, 0.804, 0.424, false },
    LipsRed = { "makeup_0015_lipstickred", 0.494, 0.106, 0.059, false },
    LipsLightBlue = { "makeup_0015_lipsticklightblue", 0.067, 0.400, 0.478, false },
    LipsBlue = { "makeup_0015_lipstickblue", 0.090, 0.275, 0.439, false },
    LipsBlack = { "makeup_0015_lipstickblack", 0.118, 0.118, 0.118, false },
    LipsGreen = { "makeup_0015_lipstickgreen", 0.153, 0.392, 0.122, false },
    LipsPink = { "makeup_0015_lipstickpink", 0.631, 0.012, 0.518, false },
}

Creator.makeupCrop = { 107, 16, 44, 44 }
Creator.makeupSkin = { 0.84, 0.69, 0.55 }

function Creator.makeupSwatch(fullType)
    local key = string.match(tostring(fullType or ""), "MakeUp_([A-Za-z0-9]+)$")
    if key == nil then return nil end
    local entry = Creator.makeupSwatches[key]
    if entry == nil then return nil end
    if entry[5] == true and entry[6] == nil then
        local ok, texture = false, nil
        if type(getTexture) == "function" then
            ok, texture = pcall(getTexture,
                "media/textures/Body/MakeUp/" .. entry[1] .. ".png")
        end
        if ok and texture ~= nil then entry[6] = texture else entry[6] = false end
    end
    return entry
end

function Creator.drawMakeupSwatch(panel, fullType, x, y, size)
    local entry = Creator.makeupSwatch(fullType)
    if entry == nil or panel == nil then return false end
    size = math.max(8, math.floor(tonumber(size) or 0))
    local texture = entry[6]
    if texture and type(panel.drawSubTexture) == "function" then

        panel:drawRect(x, y, size, size, 1, Creator.makeupSkin[1],
            Creator.makeupSkin[2], Creator.makeupSkin[3])
        panel:drawSubTexture(texture, Creator.makeupCrop[1],
            Creator.makeupCrop[2], Creator.makeupCrop[3], Creator.makeupCrop[4],
            x, y, size, size, 1, 1, 1, 1)
    else
        panel:drawRect(x, y, size, size, 1, entry[2], entry[3], entry[4])
    end
    panel:drawRectBorder(x, y, size, size, 0.8, 0.30, 0.31, 0.34)
    return true
end

function Creator.paintColorSwatch(button, color)
    if button == nil or color == nil then return end
    button.backgroundColor = { r = color.r, g = color.g, b = color.b, a = 1 }
    if button.backgroundColorEnabled ~= nil then
        button.backgroundColorEnabled = { r = color.r, g = color.g, b = color.b, a = 1 }
    end
end
Creator.primaryWeaponChoices = PRIMARY
Creator.meleeWeaponChoices = MELEE
Creator.behaviorProfileChoices = BEHAVIOR_PROFILES
Creator.primaryBehaviorChoices = PRIMARY_BEHAVIORS
Creator.combatReadyChoices = COMBAT_READY
Creator.voiceChoices = VOICES
Creator.voiceEventChoices = VOICE_EVENTS
Creator.memberModules = MEMBER_MODULES
local REGION_BADGES = {
    march_ridge = "media/textures/worldMap/MarchRidgeBadge.png",
    muldraugh = "media/textures/worldMap/MuldraughBadge.png",
    riverside = "media/textures/worldMap/RiversideBadge.png",
    rosewood = "media/textures/worldMap/RosewoodBadge.png",
    west_point = "media/textures/worldMap/WestPointBadge.png",
}

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[deepCopy(key, seen)] = deepCopy(item, seen) end
    return result
end

local function safeText(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

local function decodeColor(value, fallback)
    if type(value) == "table" then
        return { r = tonumber(value.r) or 0, g = tonumber(value.g) or 0,
            b = tonumber(value.b) or 0 }
    end
    local r, g, b = string.match(tostring(value or ""),
        "^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
    if not r then return deepCopy(fallback or Creator.hairPalette.fallback) end
    return { r = math.max(0, math.min(1, tonumber(r) or 0)),
        g = math.max(0, math.min(1, tonumber(g) or 0)),
        b = math.max(0, math.min(1, tonumber(b) or 0)) }
end

local function encodeColor(value)
    local color = decodeColor(value)
    return string.format("%.3f,%.3f,%.3f", color.r, color.g, color.b)
end

local function applyVisualColor(visual, encoded, beard)
    if not visual or ImmutableColor == nil then return end
    local color = decodeColor(encoded)
    local immutable = ImmutableColor.new(color.r, color.g, color.b, 1)
    if beard then
        visual:setBeardColor(immutable)
        visual:setNaturalBeardColor(immutable)
    else
        visual:setHairColor(immutable)
        visual:setNaturalHairColor(immutable)
    end
end

function Creator.beardShadeOf(hairColor)
    local color = decodeColor(hairColor)
    return { r = math.min(1, color.r * 0.88 + 0.015),
        g = math.min(1, color.g * 0.80), b = math.min(1, color.b * 0.76) }
end

function Creator.newAppearanceColors()
    local shades = Creator.hairPalette.natural
    local index = 1
    if type(ZombRand) == "function" then index = ZombRand(#shades) + 1
    else index = math.random(#shades) end
    local hair = shades[math.max(1, math.min(#shades, index))]
    return encodeColor(hair), encodeColor(Creator.beardShadeOf(hair))
end

local ITEM_CAPACITY_CACHE, ITEM_LOCATION_CACHE = {}, {}

local function itemCapacity(fullType)
    if type(instanceItem) ~= "function" or not fullType or fullType == "none" then return 0 end
    local cached = ITEM_CAPACITY_CACHE[fullType]
    if cached ~= nil then return cached end
    local capacity = 0
    pcall(function()
        local item = instanceItem(fullType)
        capacity = item and tonumber(item:getMaxAmmo()) or 0
    end)
    capacity = math.max(0, math.floor(capacity or 0))
    ITEM_CAPACITY_CACHE[fullType] = capacity
    return capacity
end

local function itemBodyLocation(fullType)
    if type(instanceItem) ~= "function" or not fullType or fullType == "none" then return nil end
    local cached = ITEM_LOCATION_CACHE[fullType]

    if cached ~= nil then return cached or nil end
    local location
    pcall(function()
        local item = instanceItem(fullType)
        location = item and item:getBodyLocation() or nil
    end)
    ITEM_LOCATION_CACHE[fullType] = location or false
    return location
end

local function locationsCollide(first, second)
    if not first or not second then return false end
    if tostring(first) == tostring(second) then return true end
    local exclusive = false
    pcall(function()
        local group = BodyLocations and BodyLocations.getGroup("Human") or nil
        exclusive = group and group:isExclusive(first, second) == true or false
    end)
    return exclusive
end

local function signature(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, result = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        result[#result + 1] = tostring(key) .. "=" .. signature(value[key])
    end
    return "{" .. table.concat(result, ";") .. "}"
end

local FIT_TEXT_CACHE, FIT_TEXT_COUNT = {}, 0

local function fitText(value, font, maximumWidth)
    local text = safeText(value)
    local fontHeight = getTextManager and getTextManager():getFontHeight(font) or 0
    local key = tostring(font) .. "|" .. tostring(fontHeight) .. "|" .. tostring(maximumWidth) .. "|" .. text
    local cached = FIT_TEXT_CACHE[key]
    if cached ~= nil then return cached end
    local answer = text
    if getTextManager and getTextManager():MeasureStringX(font, text) > maximumWidth then
        while #answer > 1 and
              getTextManager():MeasureStringX(font, answer .. "...") > maximumWidth do
            answer = answer:sub(1, #answer - 1)
        end
        answer = answer .. "..."
    end

    if FIT_TEXT_COUNT > 4000 then FIT_TEXT_CACHE, FIT_TEXT_COUNT = {}, 0 end
    FIT_TEXT_CACHE[key] = answer
    FIT_TEXT_COUNT = FIT_TEXT_COUNT + 1
    return answer
end

local function firstPoolChoice(value)
    for item in string.gmatch(tostring(value or "") .. "|", "(.-)|") do
        if item ~= "" and item ~= "none" then return item end
    end
    return nil
end

local function poolChoice(value, variation)
    local choices = {}
    for item in string.gmatch(tostring(value or "") .. "|", "(.-)|") do
        if item ~= "" then choices[#choices + 1] = item end
    end
    if #choices == 0 then return nil end
    local index = ((math.max(0, math.floor(tonumber(variation) or 0))) % #choices) + 1
    if choices[index] == "none" then return nil end
    return choices[index]
end

local function shortItemName(value)
    local item = firstPoolChoice(value)
    if not item then return "Unarmed" end
    return tostring(item):match("%.(.+)$") or tostring(item)
end

local function uniqueId(prefix)
    Creator.serial = Creator.serial + 1
    local stamp = type(getTimestampMs) == "function" and getTimestampMs()
        or (os.time and os.time() or 0)
    return prefix .. "_" .. tostring(stamp) .. "_" .. tostring(Creator.serial)
end

local function styleButton(button, accent)
    button.backgroundColor = copyColor(accent and ROSE_DARK or CONTROL_BG)
    button.backgroundColorMouseOver = copyColor(accent and
        { r = 0.050, g = 0.082, b = 0.090, a = 1 } or
        { r = 0.045, g = 0.055, b = 0.058, a = 1 })
    button.borderColor = copyColor(accent and ROSE or CONTROL_BORDER)
    button.textColor = copyColor(TEXT)

    if button.borderColorEnabled ~= nil then
        button.borderColorEnabled = copyColor(button.borderColor)
        button.backgroundColorEnabled = copyColor(button.backgroundColor)
    end
end

function Creator.playUiSound(label)
    if type(getSoundManager) ~= "function" then return end
    local text = string.upper(tostring(label or ""))
    local sound = (text:find("APPLY", 1, true) or text:find("CREATE", 1, true)
            or text:find("NEW", 1, true) or text:find("DONE", 1, true)
            or text:find("SAVE", 1, true) or text == "CONFIRM" or text == "YES" or text == "OK")
            and "PALUIConfirm" or "PALUIClick"
    pcall(function() getSoundManager():playUISound(sound) end)
end

Creator.notifyGapMs = 2000
Creator.notifyAt = nil
Creator.notifyReason = nil
Creator.notifyCount = 0

function Creator.notifySoundOn()
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.creatorSoundsOn) == "function" then return prefs.creatorSoundsOn() == true end
    return true
end

function Creator.notifyCue(reason)
    local cues = ProjectALife.InteractionCues
    if cues == nil or type(cues.playUI) ~= "function" or not Creator.notifySoundOn() then return false end
    local now = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or nil
    local at = Creator.notifyAt
    if at ~= nil and now ~= nil and now >= at and now - at < Creator.notifyGapMs then return false end
    if cues.playUI("PALUINotification") ~= true then return false end
    Creator.notifyAt, Creator.notifyReason = now, reason
    Creator.notifyCount = Creator.notifyCount + 1
    return true
end

function Creator.noteSaveTone(previous, tone)
    if tone == "saved" and (previous == "saving" or previous == "dirty") then
        Creator.notifyCue("saved")
    elseif tone == "error" and previous ~= "error" then
        Creator.notifyCue("error")
    end
end

function Creator.paintSaveStatus(label, text, tone)
    if not label then return end
    local previous = label.alifeTone
    label.alifeTone = tone
    label:setName(text)
    Creator.noteSaveTone(previous, tone)
    if tone == "dirty" then
        label:setColor(0.89, 0.66, 0.32)
    elseif tone == "saving" then
        label:setColor(ROSE.r, ROSE.g, ROSE.b)
    elseif tone == "error" then
        label:setColor(0.85, 0.27, 0.30)
    else
        label:setColor(0.40, 0.70, 0.52)
    end
end

Creator.uiRowCache = nil
function Creator.fontHeight(font)
    if getTextManager == nil then return 16 end
    local height = 0
    pcall(function() height = getTextManager():getFontHeight(font or UIFont.Small) end)
    return height > 0 and height or 16
end
function Creator.rowHeight(base)
    if Creator.uiRowCache == nil then Creator.uiRowCache = Creator.fontHeight(UIFont.Small) end
    return math.max(Creator.px(tonumber(base) or 23), Creator.uiRowCache + Creator.px(7))
end

Creator.uiScale = nil
function Creator.layoutScale(screenW, screenH)
    local scale = Creator.fontHeight(UIFont.Small) / 19
    local room = math.min(((tonumber(screenW) or 0) - 24) / 1000,
        ((tonumber(screenH) or 0) - 24) / 680)
    return math.max(1, math.min(scale, room))
end

function Creator.px(value)
    return math.floor(value * (Creator.uiScale or 1) + 0.5)
end
function Creator.textWidth(text, font)
    if getTextManager == nil then return 0 end
    local width = 0
    pcall(function() width = getTextManager():MeasureStringX(font or UIFont.Small, tostring(text or "")) end)
    return width
end

function Creator.fitButtonTitle(button)
    if not (button and button.fullTitle and button.setTitle) then return end
    local room = math.max(8, (tonumber(button.width) or 0) - 8)
    local title = button.fullTitle
    if Creator.textWidth(title, UIFont.Small) > room then
        title = fitText(title, UIFont.Small, room)
    end
    if button.title ~= title then button:setTitle(title) end
end

local function addButton(panel, x, y, width, label, callback, accent)
    local action = callback

    local caption = label
    if Creator.textWidth(caption, UIFont.Small) > width - 8 then
        caption = fitText(caption, UIFont.Small, math.max(8, width - 8))
    end
    local button = ISButton:new(x, y, width, Creator.rowHeight(25), caption, panel, function(target, pressed)
        Creator.playUiSound(label)
        if action then return action(target, pressed) end
    end)
    button:initialise()
    button:instantiate()

    button:setSound("activate", nil)
    styleButton(button, accent)

    button.setEnable = function(self, enabled)
        ISButton.setEnable(self, enabled)
        if not enabled then
            self.borderColor = copyColor(CONTROL_BORDER)
            self.backgroundColor = copyColor(CONTROL_BG)
        end
    end
    button.fullTitle = label
    panel:addChild(button)
    return button
end

local function addLabel(panel, x, y, label, color, font, room)
    color = color or TEXT

    local text = label
    if room ~= nil and Creator.textWidth(text, font or UIFont.Small) > room then
        text = fitText(text, font or UIFont.Small, math.max(8, room))
    end
    local item = ISLabel:new(x, y, Creator.rowHeight(22), text, color.r, color.g, color.b,
        color.a or 1, font or UIFont.Small, true)
    item:initialise()
    panel:addChild(item)
    return item
end

local function addCenteredLabel(panel, fieldX, y, fieldW, label, color, font)
    font = font or UIFont.Small
    local width = getTextManager():MeasureStringX(font, label)
    return addLabel(panel, fieldX + math.floor((fieldW - width) / 2), y,
        label, color, font)
end

local function addEntry(panel, x, y, width, value, numbers)
    local entry = ISTextEntryBox:new(tostring(value or ""), x, y, width, Creator.rowHeight(23))
    entry:initialise()
    entry:instantiate()
    if numbers then entry:setOnlyNumbers(true) end
    panel:addChild(entry)
    return entry
end

local function addCombo(panel, x, y, width, options)
    local combo = ISComboBox:new(x, y, width, Creator.rowHeight(23))
    combo:initialise()
    combo.borderColor = copyColor(CONTROL_BORDER)
    for _, option in ipairs(options or {}) do
        local label, value = option, option
        if type(option) == "table" then label, value = option[1], option[2] end
        combo:addOptionWithData(label == "" and "(none)" or label, value)
    end
    panel:addChild(combo)
    return combo
end

local function selectedData(combo)
    return combo and combo:getOptionData(combo.selected) or nil
end

local function selectData(combo, wanted, fallback)
    if combo == nil then return end
    for index = 1, combo:getOptionCount() do
        if tostring(combo:getOptionData(index) or "") == tostring(wanted or "") then
            combo.selected = index
            return
        end
    end
    if fallback ~= nil then
        for index = 1, combo:getOptionCount() do
            if tostring(combo:getOptionData(index) or "") == tostring(fallback) then
                combo.selected = index
                return
            end
        end
    end
    combo:addOptionWithData(safeText(wanted), wanted)
    combo.selected = combo:getOptionCount()
end

local function addTick(panel, x, y, width, label)
    local tick = ISTickBox:new(x, y, width, Creator.px(24), "", panel, nil)
    tick:initialise()
    tick:addOption(label)
    panel:addChild(tick)
    return tick
end

local function addNumberChoices(panel, x, y, width, options, suffix)
    local combo = addCombo(panel, x, y, width, options)
    combo.getText = function(self) return tostring(selectedData(self)) end
    combo.setText = function(self, text)
        local value = tonumber(text) or 0
        for index = 1, self:getOptionCount() do
            if tonumber(self:getOptionData(index)) == value then self.selected = index; return end
        end
        self:addOptionWithData("Custom (" .. tostring(value) .. (suffix or "") .. ")", value)
        self.selected = self:getOptionCount()
    end
    return combo
end

Creator.statKeys = { "healthHP", "strength", "endurance", "awareness", "aiming",
    "aimPlayerPercent", "aimZombiePercent" }
Creator.statRanges = {
    healthHP = { 0, 200 }, strength = { 1, 10 }, endurance = { 1, 10 },
    awareness = { 1, 10 }, aiming = { 1, 10 },

    aimPlayerPercent = { 1, 200 }, aimZombiePercent = { 1, 200 },
}

function Creator.statValue(general, key)
    local value = tonumber(general and general[key])
    if value ~= nil then return value end
    if key == "aimPlayerPercent" or key == "aimZombiePercent" then return 100 end
    return ProjectALife.CustomProfiles.rating(general, key)
end

function Creator.healthHP(general)
    return Creator.statValue(general, "healthHP")
end

function Creator.worldHP(general)
    local combat = ProjectALife.BehaviorSettings and ProjectALife.BehaviorSettings.combat
    local scale = tonumber(combat and combat.healthMultiplier) or 1
    if scale <= 0 then scale = 1 end
    local tuned = ProjectALife.NpcHealth
    if tuned ~= nil and type(tuned.preview) == "function" then
        local ok, value = pcall(tuned.preview, general, ProjectALife.CustomProfiles.startingHP(), scale)
        if ok and tonumber(value) ~= nil then return value end
    end
    return math.max(1, math.floor(Creator.healthHP(general) * scale + 0.5))
end

local function addTooltip(control, text)
    if not control or not text or text == "" then return control end
    if control.setToolTipMap then
        control:setToolTipMap({ defaultTooltip = text })
    elseif control.setTooltip then
        control:setTooltip(text)
    else
        control.tooltip = text
    end
    return control
end

local function addInfoBadge(panel, x, y, text)
    local badge = addButton(panel, x, y, Creator.px(22), "i", function() end)
    badge.textColor = copyColor(MUTED)
    return addTooltip(badge, text)
end

local function addSectionCard(panel, x, y, width, height, title, summary)
    local card = ISPanel:new(x, y, width, height)
    card:initialise()
    card.backgroundColor = copyColor(CARD_BG)
    card.borderColor = copyColor(CONTROL_BORDER)
    card.sectionTitle, card.sectionSummary = title, summary
    card.prerender = function(self)
        ISPanel.prerender(self)
        local px = Creator.px
        self:drawText(self.sectionTitle, px(12), px(9),
            ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        if self.sectionSummary and self.sectionSummary ~= "" then
            self:drawText(fitText(self.sectionSummary, UIFont.Small, self.width - px(24)),
                px(12), px(27), MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        end
    end
    panel:addChild(card)
    return card
end

local function poolVisual(value)
    local first, count, label, texture = firstPoolChoice(value), 0, "Empty", nil
    local iconItem
    for itemType in string.gmatch(tostring(value or "") .. "|", "(.-)|") do
        if itemType ~= "" then count = count + 1 end
    end
    if first then
        label = shortItemName(first)
        if type(instanceItem) == "function" then
            pcall(function()
                local item = instanceItem(first)
                if item then
                    iconItem = item
                    label = item:getDisplayName()
                    texture = item.getTexture and item:getTexture() or nil
                    if not texture and item.getTex then texture = item:getTex() end
                end
            end)
        end
    end
    return label, texture, count, iconItem
end

local function addPickerTile(panel, x, y, width, height, title, combo, callback, tooltip)
    local tile = ISPanel:new(x, y, width, height)
    tile:initialise()
    tile.backgroundColor = copyColor(CARD_BG)
    tile.borderColor = copyColor(CONTROL_BORDER)
    tile.title, tile.combo = title, combo
    tile.itemName, tile.itemTexture, tile.poolCount = "Empty", nil, 0
    tile.prerender = function(self)
        ISPanel.prerender(self)
        local hovered = self.openButton and self.openButton:isMouseOver()
        self:drawRect(0, 0, self.width, self.height, 0.98,
            hovered and 0.075 or CARD_BG.r,
            hovered and 0.080 or CARD_BG.g,
            hovered and 0.078 or CARD_BG.b)
        self:drawRectBorder(0, 0, self.width, self.height, 0.94,
            hovered and ROSE.r or CONTROL_BORDER.r,
            hovered and ROSE.g or CONTROL_BORDER.g,
            hovered and ROSE.b or CONTROL_BORDER.b)
        local px = Creator.px
        local iconSize = math.max(px(30), math.min(self.height - px(14), px(54)))
        self:drawRect(px(7), px(7), iconSize, iconSize, 0.72,
            CONTROL_BG.r, CONTROL_BG.g, CONTROL_BG.b)
        if Creator.drawMakeupSwatch(self, self.poolFirst, px(9), px(9), iconSize - px(4)) then

        elseif self.iconItem and self.drawItemIcon then

            self:drawItemIcon(self.iconItem, px(9), px(9), 1, iconSize - px(4), iconSize - px(4))
        elseif self.itemTexture then
            pcall(function()
                self:drawTextureScaledAspect2(self.itemTexture, px(9), px(9),
                    iconSize - px(4), iconSize - px(4), 1, 1, 1, 1)
            end)
        else

            local glyph = self.title == "VEST" and "V"
                or self.title == "BACK" and "B"
                or self.title == "HAT" and "H"
                or self.title == "SIDEARM" and "S"
                or self.title == "MELEE / BELT" and "M" or "-"
            self:drawTextCentre(glyph, px(7) + iconSize / 2,
                px(7) + math.floor((iconSize - getTextManager():getFontHeight(UIFont.Large)) / 2),
                MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Large)
        end
        local textX = iconSize + px(17)
        self:drawText(self.title, textX, px(8),
            ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        self:drawText(fitText(self.itemName, UIFont.Small, self.width - textX - px(12)),
            textX, px(29), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        self:drawText(self.poolCount > 1 and
                (tostring(self.poolCount) .. " SPAWN OPTIONS") or "",
            textX, self.height - px(18), MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        if self.poolCount > 1 then
            local badge = "+" .. tostring(self.poolCount - 1)
            local badgeW = getTextManager():MeasureStringX(UIFont.Small, badge) + px(10)
            self:drawRect(self.width - badgeW - px(5), px(5), badgeW, px(17), 0.96,
                ROSE_DARK.r, ROSE_DARK.g, ROSE_DARK.b)
            self:drawTextCentre(badge, self.width - badgeW / 2 - px(5), px(5),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        end
    end
    panel:addChild(tile)
    local hit = ISButton:new(0, 0, width, height, "", tile, callback)
    hit:initialise(); hit:instantiate(); hit.displayBackground = false
    hit.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    hit.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    addTooltip(hit, tooltip)
    tile:addChild(hit)
    tile.openButton = hit
    tile.syncValue = function(self)
        self.itemName, self.itemTexture, self.poolCount, self.iconItem = poolVisual(selectedData(self.combo))
        self.poolFirst = firstPoolChoice(selectedData(self.combo))
    end
    tile:syncValue()
    return tile
end

function Creator.installRightClickClear(button, clear)
    local handled = false
    button.onRightMouseDown = function()
        handled = clear() ~= false
        return true
    end
    button.onRightMouseUp = function()
        if handled then handled = false; return true end
        clear()
        return true
    end
end

function Creator.setPickerTileClear(tile, clear)
    if tile and tile.openButton then Creator.installRightClickClear(tile.openButton, clear) end
end

local function syncPickerTiles(tiles)
    for _, tile in ipairs(tiles or {}) do tile:syncValue() end
end

local function buildModuleOverrideCards(panel, x, y, width, destination, scope)
    local cursor = y
    local states = scope == "faction" and {
        { "Use NPC profile", "inherit" }, { "On by default", "on" }, { "Off by default", "off" },
    } or { { "Use faction", "inherit" }, { "On for this NPC", "on" }, { "Off for this NPC", "off" } }
    local sourceHelp = scope == "faction"
        and " Use NPC profile leaves the choice to each member's behavior profile. Individual NPC overrides take precedence."
        or " Use faction follows its default, then the NPC behavior profile when the faction has no override."
    local px = Creator.px
    for _, group in ipairs(MODULE_GROUPS) do
        local members = {}
        for _, spec in ipairs(MEMBER_MODULES) do
            if spec[3] == group[1] then members[#members + 1] = spec end
        end
        local columns = width >= px(520) and 2 or 1
        local rows = math.ceil(#members / columns)

        local fontH = Creator.fontHeight(UIFont.Small)

        local labelDrop = math.max(px(18), fontH + px(2))
        local controlH = Creator.rowHeight(23)
        local pitch = math.max(px(45), labelDrop + controlH + px(4))

        local headerY = math.max(px(49), px(27) + fontH + px(6))

        local buttonDrop = math.max(px(29), controlH + px(6))
        local cardH = headerY + rows * pitch
            + (scope == "faction" and px(4) or (buttonDrop + px(7)))
        local card = addSectionCard(panel, x, cursor, width, cardH, group[2], group[3])
        local gap = px(10)
        local itemW = math.floor((width - px(24) - gap * (columns - 1)) / columns)
        for index, spec in ipairs(members) do
            local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
            local itemX, itemY = px(12) + column * (itemW + gap), headerY + row * pitch
            local help = MODULE_HELP[spec[2]] or "Overrides this module for the current scope."
            if Creator.moduleRuleNote then help = help .. Creator.moduleRuleNote(spec[2]) end

            addTooltip(addLabel(card, itemX, itemY, Creator.moduleControlLabel(spec),
                TEXT, UIFont.Small, itemW - px(30)), help)
            destination[spec[2]] = addCombo(card, itemX, itemY + labelDrop, itemW - px(28),
                Creator.moduleStatesFor and Creator.moduleStatesFor(spec[2], states) or states)
            destination[spec[2]].ruleTip = help .. sourceHelp .. " World switches and valid task conditions always apply."
            addTooltip(destination[spec[2]], destination[spec[2]].ruleTip)
            addInfoBadge(card, itemX + itemW - px(24), itemY + labelDrop - px(1), help .. sourceHelp)
        end
        if scope ~= "faction" then
            addButton(card, px(12), cardH - buttonDrop, width - px(24),
                "APPLY " .. group[2] .. " TO FACTION", function()
                    if type(panel.applyModuleGroup) == "function" then
                        panel.applyModuleGroup(group[1])
                    end
                end, true)
        end
        cursor = cursor + cardH + px(10)
    end
    if Creator.installModuleRuleHints then Creator.installModuleRuleHints(destination) end
    return cursor
end
Creator.addTooltip = addTooltip
Creator.addSectionCard = addSectionCard
Creator.addPickerTile = addPickerTile
Creator.syncPickerTiles = syncPickerTiles
Creator.buildModuleOverrideCards = buildModuleOverrideCards

local function addRatingSlider(panel, x, y, width, value, maximum, minimum)
    maximum, minimum = maximum or 10, minimum or 1
    local sliderW = math.max(Creator.px(120), width - Creator.px(42))
    local slider = ISSliderPanel:new(x, y, sliderW, Creator.px(23), panel,
        function(_, newValue, control)
            if control.valueLabel then
                control.valueLabel:setName(tostring(math.floor(newValue + 0.5)))
            end
        end)
    slider:initialise()
    slider:instantiate()
    slider:setValues(minimum, maximum, 1, maximum > 10 and 10 or 2, true)
    slider:setDoButtons(true)
    slider.sliderColor = copyColor(ROSE)
    slider.sliderMouseOverColor = copyColor(TEXT)
    slider.sliderBarColor = copyColor(CONTROL_BG)
    slider.sliderBarBorderColor = copyColor(CONTROL_BORDER)
    panel:addChild(slider)
    slider.valueLabel = addLabel(panel, x + sliderW + Creator.px(10), y + Creator.px(3),
        tostring(math.floor(tonumber(value) or 5)), TEXT, UIFont.Medium)
    slider.getText = function(self)
        return tostring(math.floor((self:getCurrentValue() or 5) + 0.5))
    end
    slider.setText = function(self, newValue)
        local number = math.max(minimum, math.min(maximum, tonumber(newValue) or 5))
        self:setCurrentValue(number, true)
        self.valueLabel:setName(tostring(math.floor(number + 0.5)))
    end
    slider:setText(value or 5)
    return slider
end
Creator.addRatingSlider = addRatingSlider

local function addChoiceGrid(panel, x, y, width, options, columns, rowHeight)
    local control = { selected = {}, buttons = {} }
    columns, rowHeight = math.max(1, columns or 2), rowHeight or Creator.px(31)
    local gap = Creator.px(6)
    local buttonW = math.floor((width - gap * (columns - 1)) / columns)
    function control:isSelected(index) return self.selected[index] == true end
    function control:setSelected(index, value)
        self.selected[index] = value == true
        local button = self.buttons[index]
        if button then styleButton(button, self.selected[index]) end
    end
    for index, option in ipairs(options or {}) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local label = type(option) == "table" and option[1] or option.label or tostring(option)
        local choiceIndex = index
        local button = addButton(panel, x + column * (buttonW + gap),
            y + row * rowHeight, buttonW, string.upper(tostring(label)), function()
                control:setSelected(choiceIndex, not control:isSelected(choiceIndex))
            end)
        control.buttons[index] = button
    end
    control.height = math.ceil(#(options or {}) / columns) * rowHeight
    return control
end

local function addRegionGrid(panel, x, y, width, options, columns)
    local control = { selected = {}, cards = {} }
    columns = math.max(1, columns or 3)
    local gap, rowHeight = 8, 66
    local cardW = math.floor((width - gap * (columns - 1)) / columns)
    function control:isSelected(index) return self.selected[index] == true end
    function control:setSelected(index, value)
        self.selected[index] = value == true
    end
    for index, definition in ipairs(options or {}) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local card = ISPanel:new(x + column * (cardW + gap),
            y + row * rowHeight, cardW, rowHeight - 7)
        card:initialise()
        card.choiceIndex, card.definition, card.control = index, definition, control
        card.badge = nil
        local badgePath = REGION_BADGES[definition.id]
        if badgePath and type(getTexture) == "function" then
            pcall(function() card.badge = getTexture(badgePath) end)
        end
        card.prerender = function(self)
            ISPanel.prerender(self)
            local active = self.control:isSelected(self.choiceIndex)
            self:drawRect(0, 0, self.width, self.height, 0.98,
                active and 0.17 or 0.035, active and 0.055 or 0.040,
                active and 0.090 or 0.048)

            self:drawRect(10, 17, 42, 5, 0.50, 0.28, 0.30, 0.31)
            self:drawRect(27, 8, 5, 41, 0.50, 0.28, 0.30, 0.31)
            if self.badge then
                pcall(function()
                    self:drawTextureScaledAspect2(self.badge, 6, 5, 50, 49,
                        1, 1, 1, 1)
                end)
            end
            self:drawRectBorder(0, 0, self.width, self.height, 0.95,
                active and ROSE.r or CONTROL_BORDER.r,
                active and ROSE.g or CONTROL_BORDER.g,
                active and ROSE.b or CONTROL_BORDER.b)
            self:drawText(fitText(string.upper(self.definition.label or
                    self.definition.id), UIFont.Small, self.width - 72),
                64, 12, TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            self:drawText(active and "ALLOWED" or "NOT SELECTED", 64, 34,
                active and ROSE.r or MUTED.r, active and ROSE.g or MUTED.g,
                active and ROSE.b or MUTED.b, 1, UIFont.Small)
        end
        panel:addChild(card)
        control.cards[index] = card
        local choiceIndex = index
        local hit = ISButton:new(0, 0, card.width, card.height, "", card, function()
            control:setSelected(choiceIndex, not control:isSelected(choiceIndex))
        end)
        hit:initialise(); hit:instantiate(); hit.displayBackground = false
        hit.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        hit.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        card:addChild(hit)
    end
    control.height = math.ceil(#(options or {}) / columns) * rowHeight
    return control
end

local function createFramedPanel(parent, x, y, width, height)
    local panel = ISPanel:new(x, y, width, height)
    panel:initialise()
    panel.backgroundColor = copyColor(CARD_BG)
    panel.borderColor = copyColor(CONTROL_BORDER)
    parent:addChild(panel)
    return panel
end

local function installDragHandle(panel, height)
    local handle = ISPanel:new(0, 0, panel.width, height or Creator.px(42))
    handle:initialise()
    handle.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    handle.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    handle.dragging = false
    handle.onMouseDown = function(self)
        self.dragging = true
        self.panel:bringToTop()
        return true
    end
    handle.onMouseMove = function(self, dx, dy)
        if not self.dragging then return end
        local parent = self.panel:getParent()
        local maxX = parent and math.max(0, parent.width - self.panel.width) or 0
        local maxY = parent and math.max(0, parent.height - self.panel.height) or 0
        self.panel:setX(math.max(0, math.min(maxX, self.panel.x + dx)))
        self.panel:setY(math.max(0, math.min(maxY, self.panel.y + dy)))
    end
    handle.onMouseMoveOutside = handle.onMouseMove
    handle.onMouseUp = function(self) self.dragging = false; return true end
    handle.onMouseUpOutside = handle.onMouseUp
    handle.panel = panel
    panel:addChild(handle)
    panel.dragHandle = handle
    return handle
end

function Creator.orphanNotice(loaded)
    local orphans = type(loaded) == "table" and loaded.orphanedProfiles or nil
    if type(orphans) ~= "table" then return "" end
    local count, firstId = 0, nil
    for id in pairs(orphans) do
        count = count + 1
        if firstId == nil or tostring(id) < firstId then firstId = tostring(id) end
    end
    if count == 0 then return "" end
    local name = firstId
    local custom = ProjectALife.CustomProfiles
    if type(custom) == "table" and type(custom.get) == "function" then
        local ok, profile = pcall(custom.get, firstId)
        if ok and type(profile) == "table" and type(profile.general) == "table"
                and type(profile.general.name) == "string" and profile.general.name ~= "" then
            name = profile.general.name
        end
    end
    return ProjectALife.Text.ui("{n} NPC preset(s) hidden: faction missing ({name})", { n = count, name = name })
end

local function reloadCatalog(window)

    ProjectALife.CreatorFolders.load()
    ProjectALife.Catalog.reset()
    local loaded, reason = ProjectALife.Catalog.load(true)
    window.catalog = loaded
    window.rosterRevision = (window.rosterRevision or 0) + 1

    if loaded ~= nil then
        pcall(ProjectALife.CreatorFolders.seedDefaults, loaded.factionOrder)
        pcall(ProjectALife.CreatorFolders.seedVisitors, loaded.factionOrder)
    end
    if window.statusLabel then
        window.statusLabel:setName(loaded and Creator.orphanNotice(loaded) or ("CATALOG ERROR: " .. tostring(reason)))
    end
    return loaded
end

local function createPortraitDescriptor(profile, outfitId, tintCache, variation, previewWeapon, previewParts)
    if not profile or not profile.general then return nil end
    local general = profile.general
    local female = general.female == true

    local made, desc = pcall(function()
        return SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, female)
    end)
    if not made or not desc then return nil end
    local pendingAssets = false

    local sig = { tostring(female), tostring(math.max(0, math.min(4, math.floor(tonumber(general.skin) or 0)))),
        tostring(general.hairStyle or ""), encodeColor(general.hairColor),
        encodeColor(general.beardColor or general.hairColor) }
    if not female then sig[#sig + 1] = tostring(general.beardStyle or "") end
    pcall(function()
        local visual = desc:getHumanVisual()
        visual:setSkinTextureIndex(math.max(0, math.min(4,
            math.floor(tonumber(general.skin) or 0))))
        visual:setHairModel(tostring(general.hairStyle or ""))
        visual:setBeardModel(female and "" or tostring(general.beardStyle or ""))
        applyVisualColor(visual, general.hairColor, false)
        applyVisualColor(visual, general.beardColor or general.hairColor, true)
    end)
    outfitId = outfitId or "A"
    local outfit = profile.outfits and profile.outfits[outfitId] or profile.clothing
    local authoredTints = profile.outfitTints and profile.outfitTints[outfitId] or {}
    for slotIndex, slot in ipairs(CLOTHING_ORDER) do
        local fullType = poolChoice(outfit and outfit[slot],
            (tonumber(variation) or 0) + slotIndex - 1)
        if fullType then
            sig[#sig + 1] = slot .. "=" .. tostring(fullType)
            pcall(function()
                local item = instanceItem(fullType)
                local location = item and item:getBodyLocation() or nil
                if not location and item and item.canBeEquipped then location = item:canBeEquipped() end
                local itemVisual = item and item:getVisual() or nil
                local clothingItem = item and item.getClothingItem and item:getClothingItem() or nil
                local itemPending = false
                if itemVisual and not clothingItem
                        or clothingItem and clothingItem.isReady and not clothingItem:isReady() then
                    pendingAssets, itemPending = true, true
                end
                local encoded = authoredTints and authoredTints[slot] or nil
                local cacheKey = tostring(profile.id) .. ":" .. outfitId .. ":"
                    .. slot .. ":" .. fullType
                local cached = tintCache and tintCache[cacheKey] or nil
                if type(cached) == "string" then cached = { tint = cached } end
                if tintCache and type(cached) ~= "table" and clothingItem
                        and (not clothingItem.isReady or clothingItem:isReady()) and itemVisual then

                    itemVisual:pickUninitializedValues(clothingItem)
                    cached = {}
                    local color = itemVisual:getTint(clothingItem)
                    if color then cached.tint = encodeColor({ r = color:getRedFloat(),
                        g = color:getGreenFloat(), b = color:getBlueFloat() }) end
                    for _, spec in ipairs({ { "baseTexture", clothingItem:getBaseTextures(), itemVisual:getBaseTexture(clothingItem) },
                            { "textureChoice", clothingItem:getTextureChoices(), itemVisual:getTextureChoice(clothingItem) } }) do
                        for i = 0, spec[2]:size() - 1 do
                            if spec[2]:get(i) == spec[3] then cached[spec[1]] = i; break end
                        end
                    end
                    tintCache[cacheKey] = cached
                end
                if itemVisual and type(cached) == "table" then
                    pcall(function()
                        if cached.baseTexture ~= nil then
                            itemVisual:setBaseTexture(cached.baseTexture)
                        end
                        if cached.textureChoice ~= nil then
                            itemVisual:setTextureChoice(cached.textureChoice)
                        end
                    end)
                end
                if (not encoded or encoded == "native") and type(cached) == "table" then
                    encoded = cached.tint
                end
                local tint = decodeColor(encoded, nil)
                if encoded and encoded ~= "native" and itemVisual and ImmutableColor then
                    itemVisual:setTint(ImmutableColor.new(tint.r, tint.g, tint.b, 1))
                end
                if location then desc:setWornItem(location, item) end
                local chosen = type(cached) == "table" and cached or {}
                local appliedTint = "native"
                if encoded and encoded ~= "native" then appliedTint = encodeColor(encoded) end
                sig[#sig + 1] = table.concat({ tostring(location), tostring(itemPending),
                    tostring(chosen.baseTexture), tostring(chosen.textureChoice), appliedTint }, ":")
            end)
        end
    end

    if previewWeapon then
        local location = previewWeapon:getBodyLocation()
        if location then desc:setWornItem(location, previewWeapon) end
        local asset = previewWeapon:getClothingItem()
        if not asset or not asset:isReady() then pendingAssets = true end
        sig[#sig + 1] = Creator.previewItemKey(previewWeapon) .. ":" .. tostring(location)
            .. ":" .. tostring(asset ~= nil and asset:isReady())

        for _, part in ipairs(previewParts or {}) do
            local partLocation = part:getBodyLocation()
            if partLocation then desc:setWornItem(partLocation, part) end
            local partAsset = part:getClothingItem()
            if not partAsset or not partAsset:isReady() then pendingAssets = true end
            sig[#sig + 1] = Creator.previewItemKey(part) .. ":" .. tostring(partLocation)
                .. ":" .. tostring(partAsset ~= nil and partAsset:isReady())
        end
    end
    sig[#sig + 1] = tostring(pendingAssets)
    return desc, pendingAssets, table.concat(sig, "|")
end

function Creator.submitPortrait(panel)
    if panel == nil or panel.palSubmitted == true or panel.javaObject == nil then return end
    panel.palSubmitted = true
    local key = nil
    if panel.palSignature ~= nil and panel.palDescriptor ~= nil then
        key = tostring(panel.palState) .. "\31" .. panel.palSignature
    end
    if key ~= nil and key == panel.palAppliedKey and panel.javaObject == panel.palAppliedTo then return end
    panel.palAppliedKey, panel.palAppliedTo = key, panel.javaObject
    pcall(function()
        if panel.palState ~= nil then panel:setState(panel.palState) end
        if panel.palDescriptor ~= nil then panel:setSurvivorDesc(panel.palDescriptor) end
        if panel.palAnimate == false then panel.javaObject:setAnimate(false) end
    end)
end

function Creator.markModelDirty(panel, descriptor, state, descSignature)
    if panel == nil then return end
    panel.palDescriptor, panel.palState, panel.palSignature = descriptor, state, descSignature
    panel.palSubmitted = false
end

function Creator.previewItemKey(item)
    if item ~= nil and item.getFullType then return tostring(item:getFullType()) end
    return tostring(item)
end

local function staticPortraitPrerender(panel)
    ISUIElement.prerender(panel)
    Creator.submitPortrait(panel)
    if panel.javaObject then panel.javaObject:setAnimate(false) end
end

local function liveAvatarPrerender(panel)
    ISUI3DModel.prerender(panel)
    Creator.submitPortrait(panel)
end

local function installPortrait(parent, x, y, width, height, descriptor, headOnly)
    if not descriptor then return nil end
    local portrait = ISUI3DModel:new(x, y, width, height)
    portrait.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    portrait.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    portrait.prerender = staticPortraitPrerender
    portrait:initialise()
    parent:addChild(portrait)
    portrait.palDescriptor, portrait.palState, portrait.palAnimate = descriptor, "idle", false

    portrait.palSubmitted = false
    portrait:setState("idle")
    portrait:setDirection(IsoDirections.S)
    portrait:setIsometric(false)
    portrait:setDoRandomExtAnimations(false)
    portrait:setZoom(headOnly and 14 or -3)
    portrait:setYOffset(headOnly and -0.85 or 0)
    if portrait.javaObject then portrait.javaObject:setAnimate(false) end
    return portrait
end

local function previewAvatars(window)
    local list
    if window.previewAvatars and #window.previewAvatars > 0 then
        list = window.previewAvatars
    else
        list = window.avatar and { window.avatar } or {}
    end

    local compat = ProjectALife.ModCompat
    if compat == nil then return list end
    return compat.supportedPreviews(list)
end

local function disposeAvatar(window)
    if window.voicePreviewSound and type(getSoundManager) == "function" then
        pcall(function() getSoundManager():stopUISound(window.voicePreviewSound) end)
        window.voicePreviewSound = nil
    end
    for _, avatar in ipairs(previewAvatars(window)) do avatar:setVisible(false) end
    window.avatarDescriptor = nil
end

local function buildAvatar(window)
    for _, avatar in ipairs(previewAvatars(window)) do
        avatar.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        avatar.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        avatar:setAnimSetName("alife-creator")
        avatar:setState("idle")
        avatar:setDirection(IsoDirections.S)
        avatar:setIsometric(false)
        avatar:setDoRandomExtAnimations(false)
        avatar:setZoom(-3)
        avatar:setYOffset(0)
        avatar:setXOffset(0)
        avatar:setAnimateWhilePaused(true)
    end
end

function Creator.avatarStateFor(id, weaponClass)

    if id == "idle" then
        if weaponClass == "rifle" then return "idle-rifle" end
        if weaponClass == "handgun" then return "idle-handgun" end
        return "idle"
    end
    if id == "aim" and weaponClass == "rifle" then return "aim-rifle" end
    return id
end

function Creator.setAvatarAnimation(window, id)
    id = tostring(id or "idle")
    local states = { idle = true, walk = true, run = true, sprint = true,
        aim = true, ["aim-sneak"] = true, hands_up = true }
    if not states[id] then id = "idle" end

    if window.previewWeaponClass ~= nil and window.avatarDescriptor ~= nil and id ~= window.avatarAnimationApplied then
        window.avatarAnimationApplied = id
        Creator.refreshAvatar(window)
    end
    for _, avatar in ipairs(previewAvatars(window)) do
        avatar:clearVariables()
        avatar:setAnimSetName("alife-creator")
        local state = Creator.avatarStateFor(id, window.previewWeaponClass)
        avatar:setState(state)

        if window.avatarDescriptor then
            Creator.markModelDirty(avatar, window.avatarDescriptor, state, window.avatarSignature)
        end
    end
    window.avatarAnimationApplied = id
end
function Creator.refreshAvatarLoadout(window)
    local profile = window.itemPreviewProfile or window.currentProfile
    if not profile then return end
    local weapons = profile.weapons or {}
    window.avatarLoadout = {}
    for _, slot in ipairs({ "primary", "secondary", "melee" }) do
        local pool, poolCount = tostring(weapons[slot] or "none"), 0
        for choice in string.gmatch(pool .. "|", "(.-)|") do
            if choice ~= "" and choice ~= "none" then poolCount = poolCount + 1 end
        end
        local focus = window.previewChoice
        local fullType = not window.itemPreviewProfile and focus and focus.kind ~= "clothing" and focus.slot == slot
            and focus.profileId == profile.id
            and ("|" .. pool .. "|"):find("|" .. focus.id .. "|", 1, true)
            and focus.id or firstPoolChoice(pool)
        local entry = { slot = slot, fullType = fullType,
            label = shortItemName(fullType), poolCount = poolCount }
        if fullType and fullType ~= "none" then
            pcall(function()
                local item = Creator.stablePreviewItem(instanceItem(fullType))
                entry.item = item
                entry.texture = item and (item:getTexture() or item:getTex()) or nil
            end)
        end
        window.avatarLoadout[#window.avatarLoadout + 1] = entry
    end

end
Creator.itemCapacity = itemCapacity

Creator.previewStandIns = { rifle = "AssaultRifle", shotgun = "Shotgun", handgun = "Handgun",
    Stab = "FightingKnife", Spear = "SpearCrafted", Heavy = "SledgeHammer", Throw = "Molotov",
    twohand = "BaseballBat", melee = "LeadPipe" }

Creator.previewPartStandIns = { Scope = { "x4Scope", "x2Scope", "RedDot", "x8Scope" },
    RecoilPad = { "RecoilPad" } }

function Creator.previewSpriteCandidates(item)
    local names, seen = {}, {}
    local function add(name)
        name = type(name) == "string" and name or nil
        if name and name ~= "" and not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    local list = type(item.getWeaponSpritesByIndex) == "function" and item:getWeaponSpritesByIndex() or nil
    if list ~= nil and type(list.size) == "function" then
        for i = 0, list:size() - 1 do add(list:get(i)) end
    end
    add(item:getWeaponSprite())
    if type(item.getStaticModel) == "function" then add(item:getStaticModel()) end
    if type(item.getWorldStaticModel) == "function" then add(item:getWorldStaticModel()) end

    local module = type(item.getModule) == "function" and item:getModule() or nil
    if type(module) == "string" and module ~= "" and module ~= "Base" then
        for i = 1, #names do
            if not string.find(names[i], ".", 1, true) then add(module .. "." .. names[i]) end
        end
    end
    return names
end

function Creator.previewMeshOf(manager, name)
    if type(name) ~= "string" or name == "" or type(manager.getModelScript) ~= "function" then return nil end
    local ok, model = pcall(manager.getModelScript, manager, name)
    if not ok or model == nil or type(model.getMeshName) ~= "function" then return nil end
    local mesh = model:getMeshName()
    if type(mesh) ~= "string" or mesh == "" then return nil end
    return string.lower((string.gsub(mesh, "\\", "/")))
end

function Creator.previewMeshIndex(manager)
    if Creator.previewMeshes ~= nil then return Creator.previewMeshes end
    local index = {}
    Creator.previewMeshes = index
    if type(manager.getAllItems) ~= "function" then return index end
    local ok, all = pcall(manager.getAllItems, manager)
    if not ok or all == nil or type(all.size) ~= "function" then return index end
    for i = 0, all:size() - 1 do
        local script = all:get(i)
        local name = script ~= nil and type(script.getName) == "function" and script:getName() or nil
        if type(name) == "string" and string.sub(name, 1, 11) == "PALPreview_"
                and string.sub(name, 12, 16) ~= "Part_"
                and (type(script.getModuleName) ~= "function" or script:getModuleName() == "ProjectALife") then
            local sprite = string.sub(name, 12)
            local mesh = Creator.previewMeshOf(manager, sprite)
            if mesh and index[mesh] == nil then index[mesh] = sprite end
        end
    end
    return index
end

function Creator.previewBaked(manager, name)
    if type(name) ~= "string" then return nil end
    local sprite = string.gsub(name, "^Base%.", "")
    if string.match(sprite, "^[%w_]+$") and manager:FindItem("ProjectALife.PALPreview_" .. sprite) then
        return sprite
    end
    return nil
end

function Creator.previewKindOf(item)
    local twohand = type(item.isTwoHandWeapon) == "function" and item:isTwoHandWeapon() == true
    if type(item.isRanged) == "function" and item:isRanged() == true then

        local ammo = string.lower(tostring(type(item.getAmmoType) == "function" and item:getAmmoType() or ""))
        local reload = type(item.getWeaponReloadType) == "function" and item:getWeaponReloadType() or nil
        local text = string.lower(tostring(type(item.getFullType) == "function" and item:getFullType() or "")
            .. " " .. ammo .. " " .. tostring(reload or ""))
        if string.find(text, "shotgun", 1, true) then return "shotgun" end
        if string.find(ammo, "shell", 1, true) then return "shotgun" end
        return twohand and "rifle" or "handgun"
    end
    local swing = type(item.getSwingAnim) == "function" and item:getSwingAnim() or nil
    if type(swing) == "string" and Creator.previewStandIns[swing] then return swing end
    return twohand and "twohand" or "melee"
end

function Creator.previewProxyFor(item, manager)
    local candidates = Creator.previewSpriteCandidates(item)
    for _, name in ipairs(candidates) do
        local sprite = Creator.previewBaked(manager, name)
        if sprite then return sprite, "own" end
    end
    local meshes, modelled = Creator.previewMeshIndex(manager), false
    for _, name in ipairs(candidates) do
        local mesh = Creator.previewMeshOf(manager, name)
        if mesh then
            modelled = true
            if meshes[mesh] then return meshes[mesh], "mesh" end
        end
    end
    if not modelled then return nil, nil end
    local standIn = Creator.previewStandIns[Creator.previewKindOf(item)]
    if standIn and manager:FindItem("ProjectALife.PALPreview_" .. standIn) then return standIn, "standin" end
    return nil, nil
end

function Creator.previewPartIsVanilla(part, partType)
    if type(part.getModID) == "function" then
        local ok, modId = pcall(part.getModID, part)
        if ok and type(modId) == "string" and modId ~= "" then return modId == "pz-vanilla" end
    end
    return string.sub(partType, 1, 5) == "Base."
end

function Creator.previewPartStandIn(manager, sprite, partType, how)
    if type(partType) ~= "string" or type(instanceItem) ~= "function" then return nil end
    local ok, part = pcall(instanceItem, partType)
    if not ok or part == nil or type(part.getPartType) ~= "function" then return nil end
    if how == "own" and Creator.previewPartIsVanilla(part, partType) then return nil end
    for _, short in ipairs(Creator.previewPartStandIns[tostring(part:getPartType())] or {}) do
        local id = "ProjectALife.PALPreview_Part_" .. sprite .. "__" .. short
        if manager:FindItem(id) then return id end
    end
    return nil
end

function Creator.stablePreviewItem(item)
    if item == nil or type(item.getWeaponSpritesByIndex) ~= "function"
            or type(item.setModelIndex) ~= "function" then
        return item
    end
    local list = item:getWeaponSpritesByIndex()
    if list == nil or type(list.size) ~= "function" or list:size() < 2 then return item end
    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    local index = 0
    if manager then
        for i = list:size() - 1, 0, -1 do
            if Creator.previewBaked(manager, list:get(i)) then index = i end
        end
    end
    item:setModelIndex(index)
    return item
end

function Creator.previewSlotLabel(held, standIn, index, width)
    local label = held and (standIn and "SIMILAR MODEL" or "IN HAND")
        or (index == 1 and "PRIMARY" or (index == 2 and "SIDEARM" or "MELEE"))
    local fitted = fitText(label, UIFont.Small, width)
    if fitted ~= label and label == "SIMILAR MODEL" then fitted = fitText("SIMILAR", UIFont.Small, width) end
    return fitted
end

function Creator.previewHeldWeapon(window)
    local profile = window.itemPreviewProfile or window.currentProfile
    window.previewWeaponStandIn = false
    if not profile then return nil end
    local focus = not window.itemPreviewProfile and window.previewChoice or nil
    local slot = window.previewWeaponSlot or "primary"
    if focus and focus.kind ~= "clothing" and focus.profileId == profile.id
            and not window.previewWeaponSlot then slot = focus.slot end
    local pool = (profile.weapons or {})[slot]
    local id = firstPoolChoice(pool)
    if not window.previewWeaponSlot and not focus and (not id or id == "none") then
        for _, fallback in ipairs({ "secondary", "melee" }) do
            id = firstPoolChoice((profile.weapons or {})[fallback])
            if id and id ~= "none" then break end
        end
    end
    if focus and focus.slot == slot and focus.profileId == profile.id then id = focus.id end
    if not id or id == "none" then return nil end
    local item = instanceItem(id)
    if not item or not item.getWeaponSprite then return nil end

    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    if not manager then return nil end
    local sprite, how = Creator.previewProxyFor(item, manager)
    if not sprite then return nil end

    window.previewWeaponStandIn = how ~= "own"
    local proxyId = "ProjectALife.PALPreview_" .. sprite
    local proxy = instanceItem(proxyId)
    if proxy and proxy:getVisual() then proxy:getVisual():setTint(ImmutableColor.new(1, 1, 1, 1)) end
    local twohand = item.isTwoHandWeapon and item:isTwoHandWeapon()
    local weaponClass = item.isRanged and item:isRanged()
        and (twohand and "rifle" or "handgun") or (twohand and "twohand" or "melee")

    local parts, seen = {}, {}
    local chosen = (profile.weaponAttachments or {})[id]
    for partType in string.gmatch(tostring(chosen or "") .. "|", "(.-)|") do
        local short = string.match(partType, "[^%.]+$")
        local partId = short and short ~= "" and ("ProjectALife.PALPreview_Part_" .. sprite .. "__" .. short) or nil
        if partId and not manager:FindItem(partId) then
            partId = Creator.previewPartStandIn(manager, sprite, partType, how)
            if partId then window.previewWeaponStandIn = true end
        end
        if partId and not seen[partId] then
            seen[partId] = true
            local part = instanceItem(partId)
            if part then parts[#parts + 1] = part end
        end
    end
    return proxy, weaponClass, parts
end

Creator.previewLongGunStates = { ["idle-rifle"] = true, ["aim-rifle"] = true }

function Creator.previewHeldVariant(manager, item, prefix, heldPrefix)
    if item == nil or type(item.getFullType) ~= "function" then return nil end
    local id, module = item:getFullType(), "ProjectALife."
    if type(id) ~= "string" or string.sub(id, 1, #module + #prefix) ~= module .. prefix then return nil end
    local heldId = module .. heldPrefix .. string.sub(id, #module + #prefix + 1)
    if not manager:FindItem(heldId) then return nil end
    return instanceItem(heldId)
end

function Creator.previewWornFor(state, weaponClass, weapon, parts)
    parts = parts or {}
    if weapon == nil then return nil, parts end
    if weaponClass == "rifle" and not Creator.previewLongGunStates[state] then return nil, {} end
    if state ~= "idle-rifle" or type(instanceItem) ~= "function" then return weapon, parts end
    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    if manager == nil then return weapon, parts end
    local held = Creator.previewHeldVariant(manager, weapon, "PALPreview_", "PALPreview_Held_")
    if held == nil then return weapon, parts end
    local heldParts = {}
    for i = 1, #parts do
        heldParts[i] = Creator.previewHeldVariant(manager, parts[i], "PALPreview_Part_", "PALPreview_HeldPart_")
        if heldParts[i] == nil then return weapon, parts end
    end
    local visual = type(held.getVisual) == "function" and held:getVisual() or nil
    if visual and ImmutableColor then visual:setTint(ImmutableColor.new(1, 1, 1, 1)) end
    return held, heldParts
end

local function refreshAvatar(window, assetRetry)
    if not assetRetry then
        window.avatarAssetRetries, window.avatarSettleRetries = 0, 2
    end
    local profile = window.itemPreviewProfile or window.currentProfile
    if not profile then return end
    local focus = window.previewChoice
    if not window.itemPreviewProfile and focus and focus.kind == "clothing"
            and focus.profileId == profile.id and focus.outfitId == (window.activeOutfit or "A") then
        local outfit = profile.outfits and profile.outfits[focus.outfitId]
        if outfit then
            local found = false
            for id in string.gmatch(tostring(outfit[focus.slot] or "none") .. "|", "(.-)|") do
                if id == focus.id then found = true end
            end
            if found then
                profile = deepCopy(profile)
                profile.outfits[focus.outfitId][focus.slot] = focus.id
            end
        end
    end
    local weapon, weaponClass, weaponParts = Creator.previewHeldWeapon(window)
    window.previewWeaponClass = weaponClass
    weapon, weaponParts = Creator.previewWornFor(Creator.avatarStateFor(window.avatarAnimationApplied or "idle",
        weaponClass), weaponClass, weapon, weaponParts)
    local waiting = false
    for index, avatar in ipairs(previewAvatars(window)) do
        local descriptor, pendingAssets, descSignature = createPortraitDescriptor(profile,
            window.activeOutfit or "A", window.previewTintCache,
            window.outfitPreviewVariation or 0, weapon, weaponParts)
        waiting = waiting or pendingAssets
        if not descriptor then
            avatar:setVisible(false)
        else
            if index == 1 then window.avatarDescriptor, window.avatarSignature = descriptor, descSignature end
            local pose = window.avatarAnimationApplied or "idle"

            avatar.palState = Creator.avatarStateFor(pose, weaponClass)
            avatar.palDescriptor = descriptor
            Creator.markModelDirty(avatar, descriptor, avatar.palState, descSignature)
            avatar:setState(avatar.palState)
            avatar:setVisible(true)
        end
    end
    Creator.refreshAvatarLoadout(window)
    window.avatarAssetsPending = waiting
end
Creator.refreshAvatar = refreshAvatar

local function factionFromRecord(record)
    return Creator.copyFactionWardrobe(record, { id = record.id, general = deepCopy(record.general or {}),
        spawn = deepCopy(record.spawn or {}), modules = deepCopy(record.modules or {}),
        relations = deepCopy(record.relations or {}), support = deepCopy(record.support or {}),
        memberModules = deepCopy(record.memberModules or {}) })
end

function Creator.fillProfileSupport(window, general)
    selectData(window.supportPolicy, general.supportPolicy or
        (general.supportCaller == true and "any" or "inherit"))
    selectData(window.supportType, general.supportType or "inherit")
    selectData(window.supportHeli, general.supportHeli or "inherit")
    if window.syncProfileSupport then window.syncProfileSupport() end
end

function Creator.harvestProfileSupport(window, general)
    if not window.supportPolicy then return end
    local policy = selectedData(window.supportPolicy) or "inherit"
    general.supportPolicy = policy ~= "inherit" and policy or nil
    general.supportCaller = policy == "any"
    local delivery, helicopter = selectedData(window.supportType), selectedData(window.supportHeli)
    general.supportType = delivery ~= "inherit" and delivery or nil
    general.supportHeli = helicopter ~= "inherit" and helicopter or nil
end

local function profileFromRecord(record)
    local blank = ProjectALife.CustomProfiles.blank(record.id)
    blank.general = deepCopy(record.general or blank.general)
    blank.clothing = deepCopy(record.clothing or blank.clothing)
    blank.weapons = deepCopy(record.weapons or blank.weapons)
    blank.weaponAttachments = deepCopy(record.weaponAttachments or blank.weaponAttachments or {})
    blank.ammo = deepCopy(record.ammo or blank.ammo)
    blank.modules = deepCopy(record.modules or blank.modules)
    blank.outfits = {}
    blank.outfitSets = blank.outfits
    blank.outfitTints = {}
    for _, id in ipairs(OUTFIT_IDS) do
        local outfit = record["outfit" .. id]
            or record.outfits and record.outfits[id]
        if id == "A" and outfit == nil then outfit = record.clothing or blank.clothing end
        if outfit ~= nil then
            blank.outfits[id] = deepCopy(outfit)
            blank.outfitTints[id] = deepCopy(record["tint" .. id]
                or record.outfitTints and record.outfitTints[id] or {})
        end
    end
    blank.clothing = deepCopy(blank.outfits.A)
    blank.outfitEnabled = deepCopy(record.outfitEnabled or {})
    for _, id in ipairs(OUTFIT_IDS) do
        if blank.outfitEnabled[id] == nil then
            blank.outfitEnabled[id] = blank.outfits[id] ~= nil
        end
    end
    blank.outfitEnabled.A = blank.outfitEnabled.A ~= false
    blank.outfitSeason = deepCopy(record.outfitSeason or {})
    blank.syntheticOutfitA = deepCopy(record.syntheticOutfitA)
    blank.moduleOverrides = deepCopy(record.moduleOverrides or blank.moduleOverrides or {})
    return blank
end

local function poolSet(value)
    local result = {}
    for item in string.gmatch(tostring(value or "") .. "|", "(.-)|") do
        if item ~= "" then result[item] = true end
    end
    return result
end

function Creator.keepOpeningDays(ticked, authored)
    local opens = {}
    for entry in string.gmatch(tostring(authored or "") .. "|", "(.-)|") do
        local id, day = string.match(entry, "^%s*(.-)(@%d+)%s*$")
        if id ~= nil and id ~= "" then opens[id] = day end
    end
    local result = {}
    for id in string.gmatch(tostring(ticked or "") .. "|", "(.-)|") do
        if id ~= "" then result[#result + 1] = id .. (opens[id] or "") end
    end
    return table.concat(result, "|")
end

local function tableHasAny(value)
    for _ in pairs(value or {}) do return true end
    return false
end

local function eachCollection(collection, callback)
    if type(collection) == "table" then
        for _, value in ipairs(collection) do callback(value) end
        return
    end
    if collection and collection.size and collection.get then
        for index = 0, collection:size() - 1 do callback(collection:get(index)) end
    end
end

local function selectedPool(ticks, definitions, fallback)
    local result = {}
    if ticks then
        for index, definition in ipairs(definitions or {}) do
            if ticks:isSelected(index) then result[#result + 1] = definition[2] or definition.id end
        end
    end
    if #result == 0 and fallback then result[1] = fallback end
    return table.concat(result, "|")
end

local function applyPool(ticks, definitions, value)
    if not ticks then return end
    local selected = poolSet(value)
    for index, definition in ipairs(definitions or {}) do
        ticks:setSelected(index, selected[definition[2] or definition.id] == true)
    end
end

local function currentOutfit(window)
    if not window.currentProfile then return nil end
    local profile = window.currentProfile
    profile.outfits = profile.outfits or {}
    local id = window.activeOutfit or "A"
    profile.outfits[id] = profile.outfits[id] or deepCopy(profile.clothing or {})
    return profile.outfits[id]
end

local function outfitIsEnabled(profile, id)
    if not profile then return false end
    profile.outfitEnabled = profile.outfitEnabled or {}
    if profile.outfitEnabled[id] == nil then
        profile.outfitEnabled[id] = id == "A" or (profile.outfits and profile.outfits[id] ~= nil)
    end
    return profile.outfitEnabled[id] == true
end

local function syncOutfitButtons(window)
    local profile = window.currentProfile
    if not profile then return end
    local enabledCount = 0
    for outfitId, button in pairs(window.outfitButtons or {}) do
        local exists = profile.outfits and profile.outfits[outfitId] ~= nil
        local enabled = outfitIsEnabled(profile, outfitId)
        if exists and enabled then enabledCount = enabledCount + 1 end
        button:setTitle(Creator.memberSeasonTitle(profile, outfitId,
            not exists and " +" or (enabled and "  ON" or "  OFF")))
        styleButton(button, outfitId == (window.activeOutfit or "A"))
    end
    if window.outfitEnabled then
        window.outfitEnabled:setSelected(1, outfitIsEnabled(profile, window.activeOutfit or "A"))
    end
    if window.outfitSeasonCombo then
        selectData(window.outfitSeasonCombo, profile.outfitSeason
            and profile.outfitSeason[window.activeOutfit or "A"] or "random")
    end
    if window.previewOutfitButton then
        window.previewOutfitButton:setEnable(enabledCount > 0)

        window.previewOutfitButton:setTitle(fitText(enabledCount > 0 and
            "PREVIEW VARIATION" or
            "ENABLE AN OUTFIT SET TO PREVIEW", UIFont.Small,
            math.max(8, window.previewOutfitButton.width - 8)))
    end
    if window.outfitPreviewStatus then
        window.outfitPreviewStatus:setName(enabledCount > 0 and "" or
            "No outfit set is enabled for spawning")
    end
end

function Creator.setOutfitEnabled(window, enabled)
    local profile = window.currentProfile
    if not profile then return end
    local id = window.activeOutfit or "A"
    profile.outfitEnabled = profile.outfitEnabled or {}

    profile.outfitEnabled[id] = enabled == true
    syncOutfitButtons(window)
end

function Creator.setOutfitSeason(window, season)
    local profile = window.currentProfile
    if not profile then return end
    profile.outfitSeason = profile.outfitSeason or {}
    if season == nil or season == "random" then
        profile.outfitSeason[window.activeOutfit or "A"] = nil
    else
        profile.outfitSeason[window.activeOutfit or "A"] = season
    end
    syncOutfitButtons(window)
end
local function currentOutfitTints(window)
    if not window.currentProfile then return nil end
    local profile = window.currentProfile
    profile.outfitTints = profile.outfitTints or {}
    local id = window.activeOutfit or "A"
    profile.outfitTints[id] = profile.outfitTints[id] or {}
    return profile.outfitTints[id]
end

local function setOutfitTint(window, encoded)
    local slot = window.selectedClothingSlot
    local tints = currentOutfitTints(window)
    if not slot or not tints then return end

    if encoded == "native" then tints[slot] = nil else tints[slot] = encodeColor(encoded) end
    if window.outfitTintStatus then
        window.outfitTintStatus:setName(string.upper(slot) .. " COLOR: "
            .. (tints[slot] and "CUSTOM" or "NATIVE ITEM COLOR"))
    end
    refreshAvatar(window)
end

local function onOutfitColorPicked(window, color)
    if window and color then setOutfitTint(window, color) end
end

local function openOutfitColorPicker(window, button)
    local slot = window.selectedClothingSlot
    if not slot then return end
    local encoded = currentOutfitTints(window)[slot]
    local current = decodeColor(encoded, { r = 1, g = 1, b = 1 })
    local picker = ISColorPickerHSB:new(0, 0,
        ColorInfo.new(current.r, current.g, current.b, 1))
    picker:initialise()
    picker.keepOnScreen = true
    picker.pickedTarget = window
    picker:setPickedFunc(onOutfitColorPicked)
    picker:setInitialColor(ColorInfo.new(current.r, current.g, current.b, 1))
    picker:setX(math.max(0, math.min(getCore():getScreenWidth() - picker.width,
        button:getAbsoluteX())))
    picker:setY(math.max(0, math.min(getCore():getScreenHeight() - picker.height,
        button:getAbsoluteY() + button.height)))
    picker:addToUIManager()
    picker:setAlwaysOnTop(true)
    picker:bringToTop()
end
Creator.currentOutfitTints = currentOutfitTints
Creator.setOutfitTint = setOutfitTint
Creator.openOutfitColorPicker = openOutfitColorPicker

local function storeOutfitControls(window)
    local outfit = currentOutfit(window)
    if not outfit or not window.clothingCombos then return end
    for _, slot in ipairs(CLOTHING_ORDER) do
        local combo = slot == "Faces" and window.faceCombo or window.clothingCombos[slot]
        if combo then outfit[slot] = selectedData(combo) or "none" end
    end
end

local function showOutfit(window, id, skipStore)
    if not window.currentProfile then return end
    if not skipStore then storeOutfitControls(window) end
    window.activeOutfit = id
    local outfit = currentOutfit(window)
    for _, slot in ipairs(CLOTHING_ORDER) do
        local combo = slot == "Faces" and window.faceCombo or window.clothingCombos[slot]
        if combo then selectData(combo, outfit[slot] or "none") end
    end
    window.currentProfile.clothing = deepCopy(outfit)
    syncOutfitButtons(window)
    if window.syncLoadoutTiles then window.syncLoadoutTiles() end
    refreshAvatar(window)
end

function Creator.previewNextEnabledOutfit(window)
    window.previewChoice = nil
    local profile = window.currentProfile
    if not profile then return end
    storeOutfitControls(window)
    local enabled = {}
    for _, id in ipairs(OUTFIT_IDS) do
        if profile.outfits and profile.outfits[id] and outfitIsEnabled(profile, id) then
            enabled[#enabled + 1] = id
        end
    end
    if #enabled == 0 then
        syncOutfitButtons(window)
        return
    end
    local currentIndex = 0
    for index, id in ipairs(enabled) do
        if id == window.activeOutfit then currentIndex = index break end
    end
    window.outfitPreviewVariation = (window.outfitPreviewVariation or 0) + 1
    local nextIndex = currentIndex == 0 and 1 or (currentIndex % #enabled) + 1
    showOutfit(window, enabled[nextIndex])
end
local ITEM_CHOICE_CACHE = {}
local CLOTHING_LOCATIONS = {
    Hat = { "Hat", "FullHat", "JacketHat", "JacketHat_Bulky", "SweaterHat",
        "FullSuitHead", "EarTop" },
    Eyes = { "Eyes", "LeftEye", "RightEye", "MaskEyes" },
    Mask = { "Mask", "MaskEyes", "MaskFull" },
    Faces = {}, 
    Ears = { "Ears", "EarTop" },
    Neck = { "Neck", "Neck_Texture", "Necklace", "Necklace_Long", "Gorget" },
    Scarf = { "Scarf" },
    Top = { "Shirt", "Tshirt", "TankTop", "Sweater", "ShortSleeveShirt",
        "Jersey", "FullTop", "Dress", "LongDress", "BathRobe", "Boilersuit" },
    Jacket = { "Jacket", "Jacket_Bulky", "Jacket_Down", "JacketHat",
        "JacketHat_Bulky", "JacketSuit", "FullSuit" },
    Vest = { "TorsoExtra", "TorsoExtraVest", "TorsoExtraVestBullet",
        "VestTexture", "Webbing", "Cuirass", "SCBA", "SCBANoTank" },
    AmmoStrap = { "AmmoStrap", "ShoulderHolster", "AnkleHolster" },

    MakeUpFullFace = { "MakeUp_FullFace" },
    MakeUpEyes = { "MakeUp_Eyes" },
    MakeUpEyesShadow = { "MakeUp_EyesShadow" },
    MakeUpLips = { "MakeUp_Lips" },
    Hands = { "Hands" },
    LeftArm = { "LeftArm" }, RightArm = { "RightArm" },
    LeftForearm = { "ForeArm_Left" }, RightForearm = { "ForeArm_Right" },
    LeftHand = { "HandsLeft" }, RightHand = { "HandsRight" },
    LeftWrist = { "LeftWrist" }, RightWrist = { "RightWrist" },
    LeftShin = { "Calf_Left_Texture" }, RightShin = { "Calf_Right_Texture" },
    LeftGreave = { "Calf_Left" }, RightGreave = { "Calf_Right" },
    LeftKnee = { "Knee_Left" }, RightKnee = { "Knee_Right" },
    LeftThigh = { "Thigh_Left" }, RightThigh = { "Thigh_Right" },
    LeftShoulder = { "ShoulderpadLeft" }, RightShoulder = { "ShoulderpadRight" },
    LeftElbow = { "Elbow_Left" }, RightElbow = { "Elbow_Right" },
    Webbing = { "Webbing" }, BreathingGear = { "SCBA", "SCBANoTank" },
    LeftGaiter = { "Gaiter_Left" }, RightGaiter = { "Gaiter_Right" },
    Belt = { "Belt" }, Holster = { "BeltExtra" },
    ShoulderHolster = { "ShoulderHolster" }, AnkleHolster = { "AnkleHolster" },
    FannyPackFront = { "FannyPackFront" }, FannyPackBack = { "FannyPackBack" },
    Necklace = { "Necklace" }, LongNecklace = { "Necklace_Long" },
    Nose = { "Nose" }, BellyButton = { "BellyButton" },
    LeftRing = { "Left_RingFinger" }, RightRing = { "Right_RingFinger" },
    LeftMiddleRing = { "Left_MiddleFinger" }, RightMiddleRing = { "Right_MiddleFinger" },
    UnderwearTop = { "UnderwearTop" }, UnderwearBottom = { "UnderwearBottom" },
    LongJohnsTop = { "Torso1", "Torso1Legs1" }, LongJohnsBottom = { "Legs1" },
    TankTop = { "TankTop" }, Tshirt = { "Tshirt" }, Sweater = { "Sweater", "SweaterHat" },
    ShoulderPads = { "SportShoulderpad", "SportShoulderpadOnTop" }, Gorget = { "Gorget" },
    Cuirass = { "Cuirass" }, Codpiece = { "Codpiece" }, Apron = { "TorsoExtra" },
    Tail = { "Tail" }, FullSuit = { "FullSuit", "FullSuitHead", "FullSuitHeadSCBA", "BodyCostume" },
    FullRobe = { "FullRobe" },
    Wrist = { "LeftWrist", "RightWrist" },
    Fingers = { "Left_RingFinger", "Right_RingFinger", "Left_MiddleFinger",
        "Right_MiddleFinger", "Nose", "BellyButton" },
    Underwear = { "Underwear", "UnderwearTop", "UnderwearBottom",
        "UnderwearExtra1", "UnderwearExtra2", "Codpiece" },
    Pants = { "Pants", "Pants_Skinny", "PantsExtra", "ShortPants",
        "ShortsShort", "Skirt", "LongSkirt", "Legs1", "Torso1Legs1" },
    Socks = { "Socks", "Gaiter_Left", "Gaiter_Right" }, Shoes = { "Shoes" },
    Back = { "Back", "Satchel", "FannyPackBack", "FannyPackFront", "Belt",
        "BeltExtra" },
}

Creator.extraLocations = Creator.extraLocations or {}
Creator.moddedSlots = { ModdedA = true, ModdedB = true, ModdedC = true }
Creator.hiddenLocations = { ["base:zeddmg"] = true, ["base:legs5"] = true,
    ["base:bandage"] = true, ["base:wound"] = true }

function Creator.moddedLocations()
    local result = {}
    if BodyLocations == nil or type(BodyLocations.getGroup) ~= "function" then return result end
    pcall(function()
        local group = BodyLocations.getGroup("Human")
        if group == nil or group.getAllLocations == nil then return end
        local all = group:getAllLocations()
        for index = 0, all:size() - 1 do
            local location = all:get(index)
            local id = location ~= nil and location.getId ~= nil
                and string.lower(tostring(location:getId())) or ""
            if string.find(id, ":", 1, true) and string.sub(id, 1, 5) ~= "base:"
                    and not Creator.hiddenLocations[id] and Creator.extraLocations[id] == nil then
                result[#result + 1] = id
            end
        end
    end)
    table.sort(result)
    return result
end

function Creator.extraLocationItems(slot, append)
    if type(getAllItemsForBodyLocation) ~= "function" then return 0 end
    local locations = Creator.moddedSlots[slot] and Creator.moddedLocations() or {}
    for id, target in pairs(Creator.extraLocations) do
        if target == slot and not Creator.hiddenLocations[string.lower(tostring(id))] then
            locations[#locations + 1] = tostring(id)
        end
    end
    for _, id in ipairs(locations) do
        pcall(function() eachCollection(getAllItemsForBodyLocation(id), append) end)
    end
    return #locations
end

function Creator.isSidearm(item)

    if not item then return false end
    local ok, result = pcall(function()
        return item:isRanged() == true and item:isTwoHandWeapon() == false
    end)
    return ok and result == true
end

function Creator.idWords(fullType)
    local name = string.match(tostring(fullType or ""), "^[^.]+%.(.+)$") or tostring(fullType or "")
    name = string.gsub(name, "(%l)(%u)", "%1 %2")
    name = string.gsub(name, "(%d)(%u)", "%1 %2")
    name = string.gsub(name, "_", " ")
    local words = {}
    for word in string.gmatch(name, "%S+") do words[#words + 1] = word end
    return words
end

function Creator.disambiguateLabels(result)
    local groups = {}
    for _, entry in ipairs(result) do
        if entry.id ~= "none" then
            local key = string.lower(tostring(entry.label or ""))
            groups[key] = groups[key] or {}
            table.insert(groups[key], entry)
        end
    end
    for _, group in pairs(groups) do
        if #group > 1 then
            local split = {}
            for index, entry in ipairs(group) do split[index] = Creator.idWords(entry.id) end
            local shared = #split[1]
            for index = 2, #split do
                local common = 0
                while common < shared and common < #split[index]
                        and split[index][common + 1] == split[1][common + 1] do
                    common = common + 1
                end
                shared = common
            end
            local seen = {}
            for index, entry in ipairs(group) do
                local rest = {}
                for word = shared + 1, #split[index] do rest[#rest + 1] = split[index][word] end
                local suffix = table.concat(rest, " ")
                local module = string.match(entry.id, "^([^.]+)%.") or ""
                if seen[suffix] and module ~= "" then
                    suffix = suffix ~= "" and (suffix .. ", " .. module) or module
                end
                seen[suffix] = true
                if suffix ~= "" then entry.label = entry.label .. " (" .. suffix .. ")" end
            end
        end
    end
    return result
end

function Creator.toggleWeaponPart(selection, item, choices)
    if selection[item.id] then selection[item.id] = nil; return end
    if item.partType and item.partType ~= "" then
        for _, other in ipairs(choices) do
            if other.partType == item.partType then selection[other.id] = nil end
        end
    end
    selection[item.id] = true
end

local function itemChoices(kind, slot)
    local cacheKey = tostring(kind) .. ":" .. tostring(slot)
    if ITEM_CHOICE_CACHE[cacheKey] then return ITEM_CHOICE_CACHE[cacheKey] end
    local source = kind == "clothing" and (CLOTHING[slot] or {})
        or (kind == "melee" and MELEE or PRIMARY)
    local result, seen = {}, {}
    local function appendItemChoice(fullType)
        fullType = tostring(fullType or "")
        if fullType == "" or seen[fullType] then return end
        if slot == "Ears" and fullType == "Base.face5" then return end

        local made = nil
        if fullType ~= "none" and type(instanceItem) == "function" then
            local ok, item = pcall(instanceItem, fullType)
            if not ok or not item then return end
            made = item
        end
        seen[fullType] = true
        local label, texture, bodyLocation = fullType == "none" and "None"
            or shortItemName(fullType), nil, nil
        if made ~= nil then
            pcall(function()
                if made.getDisplayName then label = made:getDisplayName() end
                if made.getTexture then texture = made:getTexture() end
                if not texture and made.getTex then texture = made:getTex() end
                if made.getBodyLocation then bodyLocation = made:getBodyLocation() end
            end)
        end
        if slot == "secondary" and fullType ~= "none"
                and not Creator.isSidearm(made) then
            return
        end
        result[#result + 1] = { id = fullType, label = label, texture = texture,
            bodyLocation = bodyLocation }
    end
    appendItemChoice("none")
    if kind == "clothing" and slot == "Faces" then

        appendItemChoice("Base.face5")
    elseif kind == "clothing" then

        for _, fullType in ipairs(Creator.makeupItems[slot] or {}) do
            appendItemChoice(fullType)
        end

        if type(getAllItemsForBodyLocation) == "function" then
            for _, location in ipairs(CLOTHING_LOCATIONS[slot] or {}) do
                pcall(function()
                    local items = getAllItemsForBodyLocation(location)
                    eachCollection(items, appendItemChoice)
                end)
            end
        end
        Creator.extraLocationItems(slot, appendItemChoice)
    elseif kind ~= "clothing" and type(getAllItems) == "function" then
        pcall(function()
            local scripts = getAllItems()
            for index = 0, scripts:size() - 1 do
                local script = scripts:get(index)
                local hidden = script:getObsolete() or script:isHidden()
                if not hidden then
                    local fullType = script:getFullName()
                    local item = type(instanceItem) == "function" and instanceItem(fullType) or nil
                    if item and type(instanceof) == "function" and instanceof(item, "HandWeapon") then
                        local ranged = item.isRanged and item:isRanged() == true
                        if (kind == "firearm" and ranged) or (kind == "melee" and not ranged) then
                            appendItemChoice(fullType)
                        end
                    end
                end
            end
        end)
    end
    for _, fullType in ipairs(source) do
        if not seen[fullType] then
            appendItemChoice(fullType)
        end
    end
    Creator.disambiguateLabels(result)
    table.sort(result, function(a, b)
        if a.id == "none" then return true end
        if b.id == "none" then return false end
        return string.lower(a.label) < string.lower(b.label)
    end)
    table.insert(result, 1, { id = "remove", label = "Remove" })
    ITEM_CHOICE_CACHE[cacheKey] = result
    return result
end

local function closeItemPicker(window)
    local picker = window.itemPicker
    if not picker then return end
    picker:setVisible(false)
    pcall(function() window:removeChild(picker) end)
    window.itemPicker = nil
    window.itemPreviewProfile = nil
    refreshAvatar(window)
end

local function openWeaponAttachmentPicker(window)
    if not window.currentProfile then return end
    closeItemPicker(window)
    local weaponTypes, seenWeapons = {}, {}
    for _, combo in ipairs({ window.primaryCombo, window.secondaryCombo }) do
        for weaponType in string.gmatch(tostring(selectedData(combo) or "") .. "|", "(.-)|") do
            if weaponType ~= "" and weaponType ~= "none" and not seenWeapons[weaponType] then
                seenWeapons[weaponType] = true
                weaponTypes[#weaponTypes + 1] = weaponType
            end
        end
    end
    local px = Creator.px
    local pickerW, pickerH = math.min(px(1040), window.width - px(48)), math.min(px(780), window.height - px(48))
    local picker = createFramedPanel(window, math.floor((window.width - pickerW) / 2),
        math.floor((window.height - pickerH) / 2), pickerW, pickerH)
    picker.backgroundColor = copyColor(PANEL_BG)
    picker.borderColor = copyColor(ROSE)
    picker:bringToTop()
    window.itemPicker = picker
    installDragHandle(picker, px(42))
    addLabel(picker, px(24), px(18), "WEAPON ATTACHMENTS", ROSE, UIFont.Medium)
    addButton(picker, picker.width - px(48), px(10), px(30), "X",
        function() closeItemPicker(window) end)
    if #weaponTypes == 0 then
        addLabel(picker, px(24), px(58), "Choose a primary or secondary firearm first.", TEXT)
        addButton(picker, picker.width - px(140), picker.height - px(64), px(116), "CLOSE",
            function() closeItemPicker(window) end, true)
        return
    end
    local weaponOptions = {}
    for _, weaponType in ipairs(weaponTypes) do
        weaponOptions[#weaponOptions + 1] = { shortItemName(weaponType), weaponType }
    end
    local compactPicker = picker.width < px(860)
    addLabel(picker, px(24), px(52), "Weapon choice", MUTED)
    local weaponCombo = addCombo(picker, px(128), px(48),
        compactPicker and math.max(px(120), picker.width - px(152)) or px(310), weaponOptions)
    local safeMode, cards, page, appliedWeapon = true, {}, 1, ""
    local safeButton, unsafeButton, warning
    local selections = {}
    for _, weaponType in ipairs(weaponTypes) do
        selections[weaponType] = poolSet(window.currentProfile.weaponAttachments
            and window.currentProfile.weaponAttachments[weaponType] or "")
    end
    local filterY = compactPicker and px(82) or px(48)
    local warningY = compactPicker and px(114) or px(88)
    local areaY = compactPicker and px(142) or px(126)
    local area = ISPanel:new(px(24), areaY, picker.width - px(48), picker.height - areaY - px(78))
    area:initialise(); area.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    area.borderColor = { r = 0, g = 0, b = 0, a = 0 }; picker:addChild(area)
    local pageLabel = addLabel(picker, px(82), picker.height - px(60), "PAGE 1 / 1", MUTED)
    local selectionLabel = addLabel(picker, px(244), picker.height - px(60), "0 ATTACHED", ROSE)
    local function partChoices(weaponType)
        local result = {}
        if type(getAllItems) ~= "function" or type(instanceItem) ~= "function" then return result end
        pcall(function()
            local scripts = getAllItems()
            for index = 0, scripts:size() - 1 do
                local script = scripts:get(index)
                if not script:getObsolete() and not script:isHidden() then
                    local fullType, part = script:getFullName(), instanceItem(script:getFullName())
                    if part and type(instanceof) == "function" and instanceof(part, "WeaponPart") then
                        local compatible = false
                        pcall(function()
                            local mountOn = part:getMountOn()
                            local shortType = string.match(weaponType, "[^%.]+$") or weaponType
                            eachCollection(mountOn, function(value)
                                value = tostring(value or "")
                                if value == weaponType or value == shortType then compatible = true end
                            end)
                        end)
                        local modded = not string.match(fullType, "^Base%.")
                        if compatible or (not safeMode and modded) then
                            local label, texture = part:getDisplayName(), nil
                            if part.getTexture then texture = part:getTexture() end
                            if not texture and part.getTex then texture = part:getTex() end
                            result[#result + 1] = { id = fullType, label = label,
                                texture = texture, compatible = compatible, modded = modded,
                                partType = part:getPartType() }
                        end
                    end
                end
            end
        end)
        table.sort(result, function(a, b) return string.lower(a.label) < string.lower(b.label) end)
        return result
    end
    local rebuild
    rebuild = function()
        for _, card in ipairs(cards) do
            card:setVisible(false); pcall(function() area:removeChild(card) end)
        end
        cards = {}
        local weaponType = selectedData(weaponCombo)
        local selection = selections[weaponType] or {}
        selections[weaponType] = selection
        local all = partChoices(weaponType)
        local columns, rows, gap = compactPicker and 3 or 4, compactPicker and 2 or 3, px(10)
        local cardW = math.floor((area.width - gap * (columns - 1)) / columns)
        local cardH = math.floor((area.height - gap * (rows - 1)) / rows)
        local capacity, pages = columns * rows, math.max(1, math.ceil(#all / (columns * rows)))
        page = math.max(1, math.min(page, pages))
        pageLabel:setName("PAGE " .. tostring(page) .. " / " .. tostring(pages))
        local count = 0
        for _ in pairs(selection) do count = count + 1 end
        selectionLabel:setName(tostring(count) .. " ATTACHED TO THIS WEAPON")
        local first = (page - 1) * capacity + 1
        for index = first, math.min(#all, first + capacity - 1) do
            local item, slotIndex = all[index], index - first
            local card = ISPanel:new((slotIndex % columns) * (cardW + gap),
                math.floor(slotIndex / columns) * (cardH + gap), cardW, cardH)
            card:initialise(); card.item, card.selection = item, selection
            card.prerender = function(self)
                ISPanel.prerender(self)
                local picked = self.selection[self.item.id] == true
                self:drawRect(0, 0, self.width, self.height, 0.98,
                    picked and ROSE_DARK.r or CARD_BG.r,
                    picked and ROSE_DARK.g or CARD_BG.g,
                    picked and ROSE_DARK.b or CARD_BG.b)
                self:drawRectBorder(0, 0, self.width, self.height, 0.9,
                    picked and ROSE.r or 0.28, picked and ROSE.g or 0.29,
                    picked and ROSE.b or 0.32)
                if self.item.texture then pcall(function()
                    self:drawTextureScaledAspect2(self.item.texture, px(18), px(12),
                        self.width - px(36), math.max(px(18), self.height - px(70)), 1, 1, 1, 1)
                end) end
                self:drawTextCentre(fitText(self.item.label, UIFont.Small, self.width - px(12)),
                    self.width / 2, self.height - px(46), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
                local detail = picked and "ATTACHED - CLICK TO REMOVE"
                    or (self.item.compatible and "COMPATIBLE" or "UNVERIFIED MOD PART")
                self:drawTextCentre(detail, self.width / 2, self.height - px(24),
                    self.item.compatible and MUTED.r or 0.88,
                    self.item.compatible and MUTED.g or 0.58,
                    self.item.compatible and MUTED.b or 0.18, 1, UIFont.Small)
            end
            area:addChild(card); cards[#cards + 1] = card
            local chosenCard = card
            local choose = ISButton:new(0, 0, card.width, card.height, "", card, function()
                local id = chosenCard.item.id
                Creator.toggleWeaponPart(selection, chosenCard.item, all)
                rebuild()
            end)
            choose:initialise(); choose:instantiate(); choose.displayBackground = false
            choose.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
            choose.borderColor = { r = 0, g = 0, b = 0, a = 0 }
            card:addChild(choose); choose:bringToTop()
        end
        picker.pickerPageCount = pages
    end
    local filterW = compactPicker and math.floor((picker.width - px(58)) / 2) or px(180)
    local safeX = compactPicker and px(24) or px(460)
    local unsafeX = compactPicker and (px(34) + filterW) or px(650)
    safeButton = addButton(picker, safeX, filterY, filterW, "COMPATIBLE", function()
        safeMode, page = true, 1; styleButton(safeButton, true); styleButton(unsafeButton, false)
        warning:setName("Only parts whose mount list names this weapon."); rebuild()
    end, true)
    unsafeButton = addButton(picker, unsafeX, filterY, filterW, "MODDED / UNSAFE", function()
        safeMode, page = false, 1; styleButton(safeButton, false); styleButton(unsafeButton, true)
        warning:setName("UNVERIFIED MOD PARTS MAY ERROR OR CRASH - USE AT YOUR OWN RISK."); rebuild()
    end)
    warning = addLabel(picker, px(24), warningY,
        "Only parts whose mount list names this weapon.", MUTED)
    addButton(picker, picker.width - px(144), warningY - px(4), px(120), "REMOVE ALL", function()
        selections[selectedData(weaponCombo)] = {}; rebuild()
    end)
    addButton(picker, px(24), picker.height - px(64), px(48), "<", function()
        page = math.max(1, page - 1); rebuild()
    end)
    addButton(picker, px(174), picker.height - px(64), px(48), ">", function()
        page = math.min(picker.pickerPageCount or 1, page + 1); rebuild()
    end)
    addButton(picker, picker.width - px(258), picker.height - px(64), px(108), "CANCEL",
        function() closeItemPicker(window) end)
    addButton(picker, picker.width - px(140), picker.height - px(64), px(116), "APPLY", function()
        if not window.currentProfile then
            closeItemPicker(window)
            return
        end
        window.currentProfile.weaponAttachments = window.currentProfile.weaponAttachments or {}
        for _, weaponType in ipairs(weaponTypes) do
            local values = {}
            for partType in pairs(selections[weaponType] or {}) do values[#values + 1] = partType end
            table.sort(values)
            window.currentProfile.weaponAttachments[weaponType] = table.concat(values, "|")
        end
        closeItemPicker(window)
    end, true)
    picker.update = function(self)
        ISPanel.update(self)
        local weaponType = tostring(selectedData(weaponCombo) or "")
        if weaponType ~= appliedWeapon then appliedWeapon, page = weaponType, 1; rebuild() end
    end
    rebuild()
end

local function openItemPicker(window, kind, slot, combo, title)
    if not window.currentProfile then return end
    closeItemPicker(window)
    if kind ~= "clothing" then window.previewWeaponSlot = slot; refreshAvatar(window) end
    local px = Creator.px
    local pickerW = math.min(px(1320), window.width - px(48))
    local pickerH = math.min(px(820), window.height - px(48))
    local stage = window.avatarPreviewPane
    if stage and stage.getAbsoluteX and window.getAbsoluteX then
        local besidePreview = stage:getAbsoluteX() - window:getAbsoluteX() - px(36)
        if besidePreview >= px(640) then pickerW = math.min(pickerW, besidePreview) end
    end
    local picker = createFramedPanel(window,
        px(12),
        math.floor((window.height - pickerH) / 2), pickerW, pickerH)
    picker.backgroundColor = copyColor(PANEL_BG)
    picker.borderColor = copyColor(ROSE)
    picker:bringToTop()
    window.itemPicker = picker
    installDragHandle(picker, px(42))
    addLabel(picker, px(24), px(18), string.upper(title or "SELECT ITEM"), ROSE, UIFont.Medium)
    addLabel(picker, px(24), px(46), "Equal chance per choice. None leaves this slot empty.", MUTED)
    local railW = math.min(px(250), math.floor(picker.width * 0.24))
    local search = addEntry(picker, railW + px(38), px(76), math.min(px(560), picker.width - railW - px(260)), "")
    search:setPlaceholderText("Search item name or type...")
    local selection = poolSet(selectedData(combo))
    if not tableHasAny(selection) then selection.none = true end
    local mode = kind == "clothing" and window.multipleClothing or window.multipleWeapons
    local count = 0
    for id in pairs(selection) do count = count + 1 end
    local multiple = (mode and mode:isSelected(1)) or count > 1
    if mode then mode:setSelected(1, multiple) end
    local lastChosen
    local multipleTick = ISTickBox:new(math.max(px(280), picker.width - px(264)), px(43), px(240), px(22), "", picker,
        function(_, _, enabled)
            multiple = enabled == true
            if mode then mode:setSelected(1, multiple) end
        end)
    multipleTick:initialise()
    multipleTick:addOption("Enable multiple options")
    multipleTick:setSelected(1, multiple)
    picker:addChild(multipleTick)
    local page, applied, cards, selectedCards = 1, "", {}, {}
    local all = itemChoices(kind, slot)

    local known = {}
    for _, item in ipairs(all) do known[item.id] = true end
    all = deepCopy(all)
    for id in pairs(selection) do
        if not known[id] then all[#all + 1] = { id = id, label = shortItemName(id) } end
    end
    local advice = kind == "clothing" and Creator.clothingView ~= nil
        and Creator.clothingView.open(window, slot, picker, search, all, selection,
            { collide = locationsCollide, locationOf = itemBodyLocation, outfit = currentOutfit }) or nil
    local function previewChoice(id)
        lastChosen = id
        window.itemPreviewProfile = Creator.itemPreview(window.currentProfile,
            kind, slot, id, window.activeOutfit or "A")
        refreshAvatar(window)
    end
    local function authoredPoolValue()
        local values = {}
        for _, item in ipairs(all) do
            if selection[item.id] then values[#values + 1] = item.id end
        end
        if #values == 0 then values[1] = "none" end
        return table.concat(values, "|")
    end
    local selectedAreaBottom = kind == "firearm" and px(244) or px(190)
    local selectedArea = ISPanel:new(px(24), px(112), railW,
        picker.height - selectedAreaBottom)
    selectedArea:initialise()
    selectedArea.backgroundColor = copyColor(CARD_BG)
    selectedArea.borderColor = copyColor(CONTROL_BORDER)
    picker:addChild(selectedArea)
    addLabel(picker, px(24), px(82), "ACTIVE CHOICES", ROSE)
    if kind == "firearm" then
        addButton(picker, px(24), picker.height - px(126), railW, "ATTACHMENTS", function()
            selectData(combo, authoredPoolValue())
            if window.currentProfile and window.currentProfile.weapons then
                window.currentProfile.weapons[slot] = selectedData(combo) or "none"
            end
            if window.syncLoadoutTiles then window.syncLoadoutTiles() end
            openWeaponAttachmentPicker(window)
        end, true)
    end
    local areaX = railW + px(38)
    local area = ISPanel:new(areaX, px(112), picker.width - areaX - px(24), picker.height - px(190))
    area:initialise()
    area.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    area.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    picker:addChild(area)
    local pageLabel = addLabel(picker, areaX + px(58), picker.height - px(60), "PAGE 1 / 1", MUTED)
    local selectionLabel = addLabel(picker, px(24), picker.height - px(60),
        "SELECTED 0 / 4", ROSE)

    local function conflictFor(item)
        if kind ~= "clothing" or item.id == "none" or not item.bodyLocation then return nil end
        local outfit = currentOutfit(window) or {}
        for otherSlot, pool in pairs(outfit) do
            if otherSlot ~= slot then
                for fullType in string.gmatch(tostring(pool or "") .. "|", "(.-)|") do
                    if fullType ~= "" and fullType ~= "none"
                            and locationsCollide(item.bodyLocation, itemBodyLocation(fullType)) then
                        return otherSlot
                    end
                end
            end
        end
        return nil
    end

    local function refreshSelectionLabel()
        local count = 0
        for id in pairs(selection) do count = count + 1 end
        selectionLabel:setName("SELECTED " .. tostring(count) .. " / 4")
    end
    local rebuild, pickItem
    rebuild = function()
        for _, card in ipairs(cards) do
            card:setVisible(false)
            pcall(function() area:removeChild(card) end)
        end
        cards = {}
        for _, card in ipairs(selectedCards) do
            card:setVisible(false)
            pcall(function() selectedArea:removeChild(card) end)
        end
        selectedCards = {}
        local selectedIndex = 0
        local compactCards = picker.width < px(760) or picker.height < px(520)
        local selectedGap = compactCards and px(4) or px(8)
        local selectedCardH = compactCards
            and math.max(px(30), math.floor((selectedArea.height - px(16) - selectedGap * 3) / 4))
            or px(68)
        for _, item in ipairs(all) do
            if selection[item.id] then
                selectedIndex = selectedIndex + 1
                local conflict = conflictFor(item)
                local selectedCard = ISPanel:new(px(8),
                    px(8) + (selectedIndex - 1) * (selectedCardH + selectedGap),
                    selectedArea.width - px(16), selectedCardH)
                selectedCard:initialise()
                selectedCard.item, selectedCard.conflict = item, conflict
                selectedCard.prerender = function(self)
                    ISPanel.prerender(self)
                    self:drawRect(0, 0, self.width, self.height, 0.96,
                        self.conflict and 0.28 or ROSE_DARK.r,
                        self.conflict and 0.035 or ROSE_DARK.g,
                        self.conflict and 0.035 or ROSE_DARK.b)
                    self:drawRectBorder(0, 0, self.width, self.height, 0.95,
                        self.conflict and 0.95 or ROSE.r,
                        self.conflict and 0.12 or ROSE.g,
                        self.conflict and 0.12 or ROSE.b)
                    local iconSize = compactCards and math.max(px(16), self.height - px(14)) or px(48)
                    local textX = compactCards and iconSize + px(13) or px(61)
                    if not Creator.drawMakeupSwatch(self, self.item.id, px(7), px(7), iconSize)
                            and self.item.texture then
                        pcall(function()
                            self:drawTextureScaledAspect2(self.item.texture, px(7), px(7),
                                iconSize, iconSize, 1, 1, 1, 1)
                        end)
                    end
                    self:drawText(fitText(self.item.label, UIFont.Small,
                        self.width - textX - px(28)), textX, compactCards and px(3) or px(12),
                        TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
                    self:drawText(self.conflict and fitText("COLLIDES WITH "
                            .. string.upper(tostring(self.conflict)), UIFont.Small,
                            self.width - textX - px(28)) or "ACTIVE",
                        textX, compactCards and self.height - px(16) or px(36),
                        self.conflict and 1 or ROSE.r,
                        self.conflict and 0.25 or ROSE.g,
                        self.conflict and 0.25 or ROSE.b, 1, UIFont.Small)
                end
                selectedArea:addChild(selectedCard)
                selectedCards[#selectedCards + 1] = selectedCard
                local chosenId = item.id
                addButton(selectedCard, selectedCard.width - px(28), px(6), px(22), "X", function()
                    selection[chosenId] = nil
                    if not tableHasAny(selection) then selection.none = true end
                    previewChoice(firstPoolChoice(authoredPoolValue()))
                    rebuild()
                end, true):bringToTop()
            end
        end
        if selectedIndex == 0 then
            local empty = ISPanel:new(px(8), px(8), selectedArea.width - px(16), px(52))
            empty:initialise()
            empty.prerender = function(self)
                ISPanel.prerender(self)
                self:drawTextCentre("SLOT EMPTY", self.width / 2, px(17),
                    MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            end
            selectedArea:addChild(empty)
            selectedCards[#selectedCards + 1] = empty
        end
        local query, filtered = tostring(search:getText() or ""):lower(), {}
        if advice then
            filtered = advice:filter(query)
        else
            for _, item in ipairs(all) do
                if query == "" or tostring(item.label):lower():find(query, 1, true)
                        or tostring(item.id):lower():find(query, 1, true) then
                    filtered[#filtered + 1] = item
                end
            end
        end

        local rows, gap = 4, px(6)
        local columns = math.max(4, math.floor((area.width + gap) / px(135)))
        local cardW = math.floor((area.width - gap * (columns - 1)) / columns)
        local cardH = math.floor((area.height - gap * (rows - 1)) / rows)
        local capacity = columns * rows
        local pages = math.max(1, math.ceil(#filtered / capacity))
        local placed = {}
        if advice then
            local plan = advice:layout(filtered, page, columns, area.width, area.height, cardW, cardH, gap)
            pages, page, placed = plan.pages, plan.page, plan.items
            advice:headings(area, plan, cards)
        else
            page = math.max(1, math.min(page, pages))
            local first = (page - 1) * capacity + 1
            for index = first, math.min(#filtered, first + capacity - 1) do
                local slotIndex = index - first
                placed[#placed + 1] = { item = filtered[index], x = (slotIndex % columns) * (cardW + gap),
                    y = math.floor(slotIndex / columns) * (cardH + gap), w = cardW, h = cardH }
            end
        end
        pageLabel:setName("PAGE " .. tostring(page) .. " / " .. tostring(pages))
        for _, cell in ipairs(placed) do
            local item = cell.item
            local card = ISPanel:new(cell.x, cell.y, cell.w, cell.h)
            card:initialise()
            card.item, card.selection = item, selection
            card.prerender = function(self)
                ISPanel.prerender(self)
                local picked = self.selection[self.item.id] == true
                local conflict = picked and conflictFor(self.item) or nil
                self:drawRect(0, 0, self.width, self.height, 0.98,
                    conflict and 0.28 or (picked and ROSE_DARK.r or CARD_BG.r),
                    conflict and 0.035 or (picked and ROSE_DARK.g or CARD_BG.g),
                    conflict and 0.035 or (picked and ROSE_DARK.b or CARD_BG.b))
                self:drawRectBorder(0, 0, self.width, self.height, 0.9,
                    conflict and 0.95 or (picked and ROSE.r or 0.28),
                    conflict and 0.12 or (picked and ROSE.g or 0.29),
                    conflict and 0.12 or (picked and ROSE.b or 0.32))
                local swatch = math.max(px(12), math.min(self.width - px(24), self.height - px(50) - (self.stripH or 0)))
                if Creator.drawMakeupSwatch(self, self.item.id,
                        math.floor((self.width - swatch) / 2), px(8), swatch) then

                elseif self.item.texture then
                    pcall(function()
                        self:drawTextureScaledAspect2(self.item.texture, px(12), px(8),
                            self.width - px(24), self.height - px(50) - (self.stripH or 0), 1, 1, 1, 1)
                    end)
                else
                    self:drawTextCentre(self.item.id == "remove" and "x" or (self.item.id == "none" and "-" or "NO ICON"),
                        self.width / 2, math.floor(self.height * 0.38),
                        MUTED.r, MUTED.g, MUTED.b, 1,
                        (self.item.id == "none" or self.item.id == "remove") and UIFont.Large or UIFont.Small)
                end
                self:drawTextCentre(fitText(self.item.label, UIFont.Small, self.width - px(12)),
                    self.width / 2, self.height - px(40), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
                self:drawTextCentre(fitText(self.item.id, UIFont.Small, self.width - px(12)),
                    self.width / 2, self.height - px(22), MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
                if conflict then
                    self:drawTextCentre(fitText("COLLIDES WITH " .. string.upper(tostring(conflict)),
                        UIFont.Small, self.width - px(8)), self.width / 2, px(5),
                        1, 0.22, 0.22, 1, UIFont.Small)
                end
                if advice then advice:paint(self) end
            end
            area:addChild(card)
            cards[#cards + 1] = card
            local chosenCard = card
            local choose = ISButton:new(0, 0, card.width, card.height, "", card, function()
                local chosenItem = chosenCard.item
                if advice and advice:guard(chosenItem, selection[chosenItem.id] == true,
                        function() pickItem(chosenItem) end) then
                    return
                end
                pickItem(chosenItem)
            end)
            choose:initialise()
            choose:instantiate()
            choose.displayBackground = false
            choose.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
            choose.borderColor = { r = 0, g = 0, b = 0, a = 0 }
            card:addChild(choose)
            choose:bringToTop()
            if advice then advice:decorate(card, choose) end
        end
        picker.pickerPageCount = pages
        refreshSelectionLabel()
    end
    pickItem = function(chosenItem)
        Creator.choosePoolItem(selection, chosenItem.id, multiple)
        previewChoice(selection[chosenItem.id] and chosenItem.id
            or firstPoolChoice(authoredPoolValue()))
        rebuild()
    end
    if advice then advice:bind(function() page = 1; rebuild() end) end
    addButton(picker, areaX, picker.height - px(64), px(48), "<", function()
        page = math.max(1, page - 1); rebuild()
    end)
    local nextX = math.max(areaX + px(54),
        math.min(areaX + px(150), picker.width - px(318)))
    addButton(picker, nextX, picker.height - px(64), px(48), ">", function()
        page = math.min(picker.pickerPageCount or 1, page + 1); rebuild()
    end)
    addButton(picker, picker.width - px(258), picker.height - px(64), px(108), "CANCEL",
        function() closeItemPicker(window) end)
    addButton(picker, picker.width - px(140), picker.height - px(64), px(116), "APPLY", function()
        if not window.currentProfile then
            closeItemPicker(window)
            return
        end
        selectData(combo, authoredPoolValue())
        if kind == "clothing" then
            storeOutfitControls(window)
            if lastChosen then
                Creator.currentOutfitTints(window)[slot] = nil
            end
            window.currentProfile.clothing = deepCopy(currentOutfit(window))
            refreshAvatar(window)
        elseif window.currentProfile and window.currentProfile.weapons then
            window.currentProfile.weapons[slot] = selectedData(combo) or "none"
            refreshAvatar(window)
        end
        window.previewChoice = lastChosen and { kind = kind, slot = slot, id = lastChosen,
            profileId = window.currentProfile.id, outfitId = window.activeOutfit or "A" } or nil
        if window.syncLoadoutTiles then window.syncLoadoutTiles() end
        closeItemPicker(window)
    end, true)
    picker.update = function(self)
        ISPanel.update(self)
        local value = tostring(search:getText() or "")
        if value ~= applied then applied, page = value, 1; rebuild() end
    end
    rebuild()
end

function Creator.choosePoolItem(selection, id, multiple)
    if id == "remove" then
        for key in pairs(selection) do selection[key] = nil end
        selection.none = true
        return selection
    end
    if not multiple then
        for key in pairs(selection) do selection[key] = nil end
        selection[id] = true
    elseif selection[id] then
        selection[id] = nil
    else
        local count = 0
        for _ in pairs(selection) do count = count + 1 end
        if count < 4 then selection[id] = true end
    end
    if not tableHasAny(selection) then selection.none = true end
    return selection
end

function Creator.itemPreview(profile, kind, slot, id, outfitId)
    local draft = deepCopy(profile)
    if kind == "clothing" then
        draft.outfits = draft.outfits or {}
        draft.outfits[outfitId] = draft.outfits[outfitId] or deepCopy(draft.clothing or {})
        draft.outfits[outfitId][slot] = id
        draft.outfitSets = draft.outfits
        draft.outfitEnabled = draft.outfitEnabled or {}
        draft.outfitEnabled[outfitId] = true
        draft.outfitTints = draft.outfitTints or {}
        draft.outfitTints[outfitId] = draft.outfitTints[outfitId] or {}
        draft.outfitTints[outfitId][slot] = nil
    else
        draft.weapons = draft.weapons or {}
        draft.weapons[slot] = id
    end
    return draft
end
Creator.openItemPicker = openItemPicker
Creator.closeItemPicker = closeItemPicker

local function previewVoiceProfile(window)
    local id = selectedData(window.profileVoice) or ""
    if id == "" and ProjectALife.VoiceAssignment then
        return ProjectALife.VoiceAssignment.assign("", window.currentFaction and window.currentFaction.id,
            window.profileFemaleValue == true, tostring(window.currentProfile and window.currentProfile.id) .. ":preview")
    end
    return id
end

local function refreshVoiceEvents(window, preferred)
    local combo, catalog = window.profileVoiceEvent, ProjectALife.VoiceCatalog
    if not combo or not catalog then return end
    local profileId = previewVoiceProfile(window)
    local profile = catalog.profiles and catalog.profiles[profileId]
    combo:clear()
    local ids = catalog.eventIds and catalog.eventIds() or {}
    for _, id in ipairs(ids) do
        local entries = catalog.entries(profileId, id)
        if #entries > 0 then
            local clips = 0
            for _, entry in ipairs(entries) do if entry.sound then clips = clips + 1 end end
            local label = id:gsub("_", " "):lower():gsub("^%l", string.upper)
            label = label .. (clips > 0 and (" - " .. clips .. " audio") or " - text only")
            combo:addOptionWithData(label, id)
        end
    end
    selectData(combo, preferred or "CONTACT_HOSTILE")
    if window.voicePreviewStatus then
        window.voicePreviewStatus:setName(selectedData(window.profileVoice) == "" and
            ("Faction voice sample: " .. tostring(profile and profile.label or "text only"))
            or profile and profile.captionOnly == true and "Text-only personality."
            or tostring(profile and profile.readyClips or 0) .. " recordings + contextual text. Preview a reaction below.")
    end
    window.voiceEventsForProfile = selectedData(window.profileVoice) or ""
end
Creator.refreshVoiceEvents = refreshVoiceEvents

local function refreshBehaviorSummary(window)
    if not window.behaviorSummaryLabel then return end
    local id = selectedData(window.profileBehaviorProfile) or "seek_destroy"
    if id == window.behaviorSummaryForProfile then return end
    window.behaviorSummaryForProfile = id
    local definition = ProjectALife.BehaviorProfiles.get(id)
    window.behaviorSummaryLabel:setName(definition and definition.summary
        or "Unknown profile - the runtime will use the roaming hostile fallback.")
end
Creator.refreshBehaviorSummary = refreshBehaviorSummary

local function previewVoice(window)
    if not ProjectALife.AudioPolicy.allowsNPC() then
        if window.voicePreviewSound and type(getSoundManager) == "function" then
            pcall(function() getSoundManager():stopUISound(window.voicePreviewSound) end)
            window.voicePreviewSound = nil
        end
        window.voicePreviewStatus:setName("NPC audio disabled for voice review. Text dialogue remains enabled.")
        return
    end
    local profileId = previewVoiceProfile(window)
    local eventId = selectedData(window.profileVoiceEvent) or "CONTACT_HOSTILE"
    local catalog = ProjectALife.VoiceCatalog
    if not catalog then return end
    local entries = catalog.entries(profileId, eventId)
    if #entries == 0 then
        window.voicePreviewStatus:setName("No lines for this reaction.")
        return
    end
    window.voicePreviewCursor = window.voicePreviewCursor or {}
    local key = profileId .. ":" .. eventId
    local index = (window.voicePreviewCursor[key] or 0) % #entries + 1
    window.voicePreviewCursor[key] = index
    local entry = entries[index]
    local caption = catalog.captionFor(profileId, eventId, entry) or ""
    local played = false
    if type(getSoundManager) == "function" then
        pcall(function()
            local manager = getSoundManager()
            if window.voicePreviewSound then manager:stopUISound(window.voicePreviewSound) end
            window.voicePreviewSound = nil
            if entry.sound then

                local sound = entry.sound
                if sound:sub(1, 5) == "PALV_" or sound:sub(1, 5) == "PALL_" then sound = "PALUI_" .. sound end
                window.voicePreviewSound = manager:playUISound(sound)
                played = window.voicePreviewSound ~= nil and window.voicePreviewSound ~= 0
            end
        end)
    end
    local status = played and "AUDIO " or entry.sound and "AUDIO UNAVAILABLE " or "TEXT "
    window.voicePreviewStatus:setName(fitText(status .. index .. "/" .. #entries
        .. ": " .. caption, UIFont.Small, window.voicePreviewWidth or 540))
end
Creator.previewVoice = previewVoice

local function fillFaction(window)
    local faction = window.currentFaction
    if not faction then return end
    window.factionId:setName(fitText("ID: " .. faction.id ..
        (window.currentFactionCustom and " / Custom" or " / Built-in override"),
        UIFont.Small, window.factionEditor and window.factionEditor.width - 32 or 500))
    window.factionName:setText(safeText(faction.general.name))
    window.factionCategory:setText(safeText(faction.general.category))
    window.factionDescription:setText(safeText(faction.general.description))
    faction.relations = faction.relations or {}
    faction.memberModules = faction.memberModules or {}
    Creator.fillFactionRelations(window)
    Creator.fillFactionSupport(window, faction.support or {})
    local playerRelation = faction.relations.player
        or (faction.spawn.peaceable == true and "friendly" or "hostile")

    if playerRelation == "suspicious" then playerRelation = "careful" end
    selectData(window.factionPlayerRelation, playerRelation)
    selectData(window.factionUnknownRelation, faction.relations.unknown or "hostile")
    if window.factionPlayerRelation.alifeSync then window.factionPlayerRelation.alifeSync() end
    if window.factionUnknownRelation.alifeSync then window.factionUnknownRelation.alifeSync() end
    window.factionEnabled:setSelected(1, faction.spawn.enabled ~= false)
    selectData(window.factionBackupMode, faction.spawn.backupMode or "none")

    window.factionDayStart:setText(safeText(faction.spawn.firstDay))
    window.factionDayEnd:setText(safeText(faction.spawn.lastDay))
    window.factionChance:setText(tostring(ProjectALife.PartyPolicy.weight(faction.spawn.odds)))
    local party = ProjectALife.PartyPolicy.config(faction)
    selectData(window.factionPartyMode, party.mode)
    window.factionLoneMin:setText(tostring(party.loneMin))
    window.factionLoneMax:setText(tostring(party.loneMax))
    window.factionGroupMin:setText(tostring(party.groupMin))
    window.factionGroupMax:setText(tostring(party.groupMax))
    window.factionLoneWeight:setText(safeText(faction.spawn.loneWeight))
    window.factionPartyGroupWeight:setText(safeText(faction.spawn.groupWeight))
    window.factionLoneWeight:setPlaceholderText("World: " .. tostring(party.loneWeight))
    window.factionPartyGroupWeight:setPlaceholderText("World: " .. tostring(party.groupWeight))

    Creator.fillSpawnHours(window, faction.spawn)
    selectData(window.factionLocationMode, faction.spawn.locationMode or "anywhere")
    if window.factionLocationMode.alifeSync then window.factionLocationMode.alifeSync() end
    window.factionIncludeWilderness:setSelected(1, faction.spawn.includeWilderness == true)
    local selectedEncounters = ProjectALife.FactionSpawnRules.encounters(faction.spawn)
    for index, spec in ipairs(SCENARIOS) do
        window.scenarioTicks:setSelected(index, selectedEncounters[spec[2]] == true)
    end

    local seatSet = poolSet(faction.spawn.seats)
    for index, spec in ipairs(Creator.outpostSeats) do
        window.scenarioTicks:setSelected(#SCENARIOS + index, seatSet[spec[2]] == true)
    end
    applyPool(window.programTicks, PROGRAMS,
        faction.spawn.programPool or faction.spawn.program or "patrol")
    applyPool(window.townTicks, ProjectALife.SpawnRegions.definitions,
        faction.spawn.towns ~= nil and faction.spawn.towns ~= "" and faction.spawn.towns or faction.spawn.townPool)
    window.factionAllTowns:setSelected(1, faction.spawn.allTowns == true)
    if window.syncAllTowns then window.syncAllTowns() end
    applyPool(window.specificPlaceTicks, SPECIFIC_PLACES,
        faction.spawn.specificPlacePool)
    Creator.refreshEffectiveRelation(window)
    for _, spec in ipairs(MEMBER_MODULES) do
        selectData(window.memberModuleCombos[spec[2]],
            faction.memberModules[spec[2]] or "inherit")
    end
    if Creator.refreshModuleRuleHints then Creator.refreshModuleRuleHints(window.memberModuleCombos) end
    faction.modules = faction.modules or {}
    for _, spec in ipairs(FACTION_MODULES) do
        local entry = window.factionModuleEntries and window.factionModuleEntries[spec[2]]
        if entry then entry:setText(safeText(faction.modules[spec[2]])) end
    end
    if window.factionVisitorOnly then
        window.factionVisitorOnly:setSelected(1, faction.spawn.visitorOnly == true)
        window.visitorOnlyShown = false
        Creator.syncVisitorOnly(window)
    end
    window.factionBaseline = signature(faction)
end

local function harvestFaction(window)
    local faction = window.currentFaction
    if not faction then return nil end
    faction.general, faction.spawn, faction.modules = faction.general or {},
        faction.spawn or {}, faction.modules or {}
    faction.relations, faction.memberModules = faction.relations or {},
        faction.memberModules or {}
    faction.general.name = safeText(window.factionName:getText())
    faction.general.category = safeText(window.factionCategory:getText())
    faction.general.description = safeText(window.factionDescription:getText())
    faction.relations.player = selectedData(window.factionPlayerRelation) or "hostile"
    faction.relations.unknown = selectedData(window.factionUnknownRelation) or "hostile"
    faction.spawn.peaceable = faction.relations.player == "friendly"
        or faction.relations.player == "allied"
    faction.spawn.enabled = window.factionEnabled:isSelected(1)
    if faction.spawn.enabled then faction.spawn.hiddenFromSpawn = nil end
    faction.spawn.backupMode = selectedData(window.factionBackupMode)
        or faction.spawn.backupMode or "none"
    faction.spawn.firstDay = Creator.entryNumber(window.factionDayStart, true)
    faction.spawn.lastDay = Creator.entryNumber(window.factionDayEnd, true)
    faction.spawn.odds = ProjectALife.PartyPolicy.weight(
        Creator.entryNumber(window.factionChance))
    faction.spawn.partyMode = selectedData(window.factionPartyMode) or "both"
    faction.spawn.loneMin = Creator.entryNumber(window.factionLoneMin, true)
    faction.spawn.loneMax = Creator.entryNumber(window.factionLoneMax, true)
    faction.spawn.partyGroupMin = Creator.entryNumber(window.factionGroupMin, true)
    faction.spawn.partyGroupMax = Creator.entryNumber(window.factionGroupMax, true)
    faction.spawn.loneWeight = Creator.entryNumber(window.factionLoneWeight)
    faction.spawn.groupWeight = Creator.entryNumber(window.factionPartyGroupWeight)

    local sized = ProjectALife.PartyPolicy.config(faction)
    faction.spawn.loneMin, faction.spawn.loneMax = sized.loneMin, sized.loneMax
    faction.spawn.partyGroupMin, faction.spawn.partyGroupMax = sized.groupMin, sized.groupMax
    faction.spawn.loneWeight = faction.spawn.loneWeight and sized.loneWeight or nil
    faction.spawn.groupWeight = faction.spawn.groupWeight and sized.groupWeight or nil
    local hours = selectedData(window.factionHours) or "0|24"
    local first, last = hours:match("^(%d+)|(%d+)$")
    faction.spawn.hourStart, faction.spawn.hourEnd = tonumber(first) or 0, tonumber(last) or 24
    faction.spawn.locationMode = selectedData(window.factionLocationMode) or "anywhere"
    faction.spawn.includeWilderness = window.factionIncludeWilderness:isSelected(1)
    local authoredPool = faction.spawn.encounterPool
    faction.spawn.encounterPool = selectedPool(window.scenarioTicks, SCENARIOS)
    faction.spawn.encounterPool = Creator.keepOpeningDays(faction.spawn.encounterPool, authoredPool)

    local seats = {}
    for index, spec in ipairs(Creator.outpostSeats) do
        if window.scenarioTicks:isSelected(#SCENARIOS + index) then
            seats[#seats + 1] = spec[2]
        end
    end
    faction.spawn.seats = table.concat(seats, "|")

    faction.spawn.towns = "" 
    faction.spawn.townPool = selectedPool(window.townTicks,
        ProjectALife.SpawnRegions.definitions, nil)
    faction.spawn.allTowns = window.factionAllTowns:isSelected(1)
    if window.specificPlaceTicks then
        faction.spawn.specificPlacePool = selectedPool(window.specificPlaceTicks,
            SPECIFIC_PLACES, nil)
    end
    if window.factionVisitorOnly then
        if window.factionVisitorOnly:isSelected(1) then
            ProjectALife.CustomFactions.forceVisitorSpawn(faction.spawn)
        else
            if faction.spawn.visitorOnly == true then faction.spawn.natural = nil end
            faction.spawn.visitorOnly = nil
        end
    end
    Creator.harvestRelationRows(window, faction.relations)
    for _, spec in ipairs(MEMBER_MODULES) do
        faction.memberModules[spec[2]] = selectedData(window.memberModuleCombos[spec[2]])
            or "inherit"
    end
    for _, spec in ipairs(FACTION_MODULES) do
        local entry = window.factionModuleEntries and window.factionModuleEntries[spec[2]]
        if entry then faction.modules[spec[2]] = safeText(entry:getText()) end
    end
    Creator.harvestFactionSupport(window, faction)
    if Creator.syncFactionWardrobe then Creator.syncFactionWardrobe(window) end
    return faction
end

local rebuildAppearanceStyleCombos, syncAppearanceControls
local setProfileGender, setProfileSkin, openAppearancePicker, openAppearanceColorPicker

local function profileVisualSignature(profile)
    local general = profile and profile.general or {}
    return signature({
        female = general.female, skin = general.skin,
        hairStyle = general.hairStyle, hairColor = general.hairColor,
        beardStyle = general.beardStyle, beardColor = general.beardColor,
        outfits = profile and profile.outfits or {},
        outfitTints = profile and profile.outfitTints or {},
        outfitEnabled = profile and profile.outfitEnabled or {},
        weapons = profile and profile.weapons or {},
    })
end

local function magazineCountFor(profile, slot)
    local general = profile and profile.general or {}
    local authored = tonumber(general[slot .. "Magazines"])
    if general.ammoMode == "magazines" and authored ~= nil then
        return math.max(0, math.floor(authored))
    end
    if authored ~= nil and authored > 0 then return math.max(0, math.floor(authored)) end
    local weapon = firstPoolChoice(profile and profile.weapons and profile.weapons[slot])
    local rounds = tonumber(profile and profile.ammo and profile.ammo[slot]) or 0
    local capacity = itemCapacity(weapon)
    if capacity <= 0 then return 0 end
    return math.max(0, math.ceil(rounds / capacity))
end

local function fillProfile(window)
    window.previewChoice, window.itemPreviewProfile = nil, nil
    local profile = window.currentProfile
    if not profile then return end
    profile.modules = profile.modules or {}
    profile.moduleOverrides = profile.moduleOverrides or {}
    profile.outfits = profile.outfits or { A = deepCopy(profile.clothing or {}) }
    profile.outfitTints = profile.outfitTints or {}
    profile.outfitEnabled = profile.outfitEnabled or {}
    profile.outfits.A = profile.outfits.A or deepCopy(profile.clothing or {})
    profile.outfitTints.A = profile.outfitTints.A or {}
    window.activeOutfit = "A"
    if window.profileHeader then
        window.profileHeader:setName(fitText(string.upper(safeText(profile.general.name or profile.id)),
            UIFont.Medium, window.profilePane and window.profilePane.width - 242 or 400))
    end
    if window.profileBreadcrumb then
        window.profileBreadcrumb:setName(safeText(
            window.currentFaction and window.currentFaction.general.name or profile.general.faction)
            .. "  /  NPC Preset")
    end
    window.profileId:setName(fitText("ID: " .. profile.id ..
        (window.currentProfileCustom and " / Custom" or " / Built-in override"), UIFont.Small,
        window.profilePane and window.profilePane.width - (window.compactWorkbench and 194 or 96) or 400))
    window.profileName:setText(safeText(profile.general.name))
    window.profileFaction:setName("Faction: " .. safeText(
        window.currentFaction and window.currentFaction.general.name or profile.general.faction))
    window.profileFemaleValue = profile.general.female == true
    selectData(window.profileGender, window.profileFemaleValue and "female" or "male")
    window.profileGenderApplied = selectedData(window.profileGender)
    if type(Creator.loadNameMode) == "function" then Creator.loadNameMode(window, profile) end
    if type(Creator.loadNpcClass) == "function" then Creator.loadNpcClass(window, profile) end
    window.profileSkin:setText(tostring(profile.general.skin or 0))
    rebuildAppearanceStyleCombos(window, profile.general.hairStyle or "",
        profile.general.beardStyle or "")
    selectData(window.profileHair, profile.general.hairStyle or "")
    selectData(window.profileBeard, profile.general.beardStyle or "")
    window.profileHairColorValue = encodeColor(profile.general.hairColor)

    local beardTint = profile.general.beardColor
    if beardTint == nil or beardTint == "" then beardTint = profile.general.hairColor end
    window.profileBeardColorValue = encodeColor(beardTint)
    local preferredVoiceEvent = selectedData(window.profileVoiceEvent)
    selectData(window.profileVoice, profile.general.voiceProfile or "")
    refreshVoiceEvents(window, preferredVoiceEvent)
    if Creator.loadMemberTags then Creator.loadMemberTags(window, profile.general.role or "Scout")
    else selectData(window.profileRole, profile.general.role or "Scout") end
    if window.profileRank then selectData(window.profileRank, profile.general.rank or "Regular") end
    if window.profileActivity then selectData(window.profileActivity, profile.general.defaultActivity or "patrol") end
    window.profileSpawnWeight:setText(tostring(profile.general.spawnWeight or 1.0))
    window.profileTags:setText(safeText(profile.general.tags))
    window.profileNotes:setText(safeText(profile.general.notes))
    selectData(window.profileBehaviorProfile,
        profile.general.behaviorProfile or "seek_destroy")
    Creator.refreshBehaviorSummary(window)
    selectData(window.profilePrimaryBehavior,
        profile.general.primaryBehavior or "none")
    selectData(window.profileCombatReady, profile.general.combatReady or "default")
    for _, slot in ipairs(CLOTHING_ORDER) do
        local combo = slot == "Faces" and window.faceCombo or window.clothingCombos[slot]
        if combo then
            selectData(combo, profile.outfits.A and profile.outfits.A[slot] or "none")
        end
    end
    syncOutfitButtons(window)
    selectData(window.primaryCombo, profile.weapons and profile.weapons.primary or "none")
    selectData(window.secondaryCombo, profile.weapons and profile.weapons.secondary or "none")
    selectData(window.meleeCombo, profile.weapons and profile.weapons.melee or "none")
    if window.primaryAmmo then
        window.primaryAmmo:setText(tostring(profile.ammo and profile.ammo.primary or 0))
    end
    if window.secondaryAmmo then
        window.secondaryAmmo:setText(tostring(profile.ammo and profile.ammo.secondary or 0))
    end
    if window.ammoMode then selectData(window.ammoMode, "magazines") end
    window.primaryMagazines:setText(tostring(magazineCountFor(profile, "primary")))
    window.secondaryMagazines:setText(tostring(magazineCountFor(profile, "secondary")))
    for _, key in ipairs(Creator.statKeys) do
        local entry = window.statEntries[key]
        if entry then entry:setText(tostring(Creator.statValue(profile.general, key))) end
    end
    window.infiniteAmmo:setSelected(1, profile.general.infiniteAmmo == true)
    Creator.fillProfileSupport(window, profile.general)
    window.dropAmmo:setSelected(1, profile.general.dropAmmo ~= false)
    selectData(window.dropWeaponChance, ProjectALife.DropPolicy.resolve(profile.general)[2])
    if window.magazineDropChance then
        window.magazineDropChance:setText(tostring(profile.general.magazineDropChance or 35))
    end
    if window.dropWeaponCondition then
        window.dropWeaponCondition:setText(tostring(profile.general.dropWeaponCondition or 5))
    end
    window.dropArmorChance:setText(tostring(profile.general.dropArmorChance or 20))
    if window.damageReduction then
        window.damageReduction:setText(tostring(profile.general.damageReduction or 0))
    end
    if window.damageOutput then
        window.damageOutput:setText(tostring(profile.general.damageOutput or 100))
    end
    if window.armorCondition then
        window.armorCondition:setText(tostring(profile.general.armorCondition or 5))
    end
    for _, spec in ipairs(PROFILE_MODULES) do
        local entry = window.profileModuleEntries and window.profileModuleEntries[spec[2]]
        if entry then entry:setText(safeText(profile.modules[spec[2]])) end
    end
    for _, spec in ipairs(MEMBER_MODULES) do
        selectData(window.profileModuleOverrides[spec[2]],
            profile.moduleOverrides[spec[2]] or "inherit")
    end
    if Creator.refreshModuleRuleHints then Creator.refreshModuleRuleHints(window.profileModuleOverrides) end
    if window.profileSummaryBehavior then
        window.profileSummaryBehavior:setName("BEHAVIOR  /  " ..
            string.upper(safeText(profile.general.behaviorProfile or "seek_destroy")))
        local weapon = firstPoolChoice(profile.weapons and profile.weapons.primary)
            or firstPoolChoice(profile.weapons and profile.weapons.secondary)
            or firstPoolChoice(profile.weapons and profile.weapons.melee)
        window.profileSummaryLoadout:setName("LOADOUT  /  " ..
            string.upper(shortItemName(weapon)))
        window.profileSummaryStats:setName("STATS  /  HP " ..
            tostring(Creator.worldHP(profile.general)) .. "   STR " ..
            tostring(Creator.statValue(profile.general, "strength")) .. "   AIM " ..
            tostring(Creator.statValue(profile.general, "aiming")))
    end
    window.currentProfile.clothing = deepCopy(profile.outfits.A)
    syncAppearanceControls(window)
    if window.syncLoadoutTiles then window.syncLoadoutTiles() end
    refreshAvatar(window)
    window.profilePortraitBaseline = profileVisualSignature(profile)
    window.profileBaseline = signature(profile)
end

local function harvestProfile(window)
    local profile = window.currentProfile
    if not profile then return nil end
    profile.general, profile.clothing = profile.general or {}, profile.clothing or {}
    profile.weapons, profile.ammo = profile.weapons or {}, profile.ammo or {}
    profile.weaponAttachments = profile.weaponAttachments or {}
    profile.modules = profile.modules or {}
    profile.moduleOverrides = profile.moduleOverrides or {}
    profile.outfits = profile.outfits or {}
    profile.outfitTints = profile.outfitTints or {}
    profile.outfitEnabled = profile.outfitEnabled or {}
    profile.general.faction = window.currentFaction and window.currentFaction.id or profile.general.faction
    profile.general.name = safeText(window.profileName:getText())
    profile.general.female = window.profileFemaleValue == true
    if type(Creator.saveNameMode) == "function" then Creator.saveNameMode(window, profile) end
    if type(Creator.saveNpcClass) == "function" then Creator.saveNpcClass(window, profile) end
    profile.general.skin = math.max(0, math.min(4,
        math.floor(tonumber(window.profileSkin:getText()) or 0)))
    profile.general.hairStyle = selectedData(window.profileHair) or ""
    profile.general.hairColor = encodeColor(window.profileHairColorValue)
    profile.general.beardStyle = profile.general.female and ""
        or (selectedData(window.profileBeard) or "")
    profile.general.beardColor = encodeColor(window.profileBeardColorValue)
    profile.general.voiceProfile = selectedData(window.profileVoice) or ""
    profile.general.role = selectedData(window.profileRole) or "Scout"

    profile.general.spawnWeight = math.max(0,
        tonumber(window.profileSpawnWeight:getText()) or 1.0)
    profile.general.tags = safeText(window.profileTags:getText())
    profile.general.notes = safeText(window.profileNotes:getText())
    profile.general.behaviorProfile = selectedData(window.profileBehaviorProfile)
        or "seek_destroy"
    profile.general.primaryBehavior = selectedData(window.profilePrimaryBehavior) or "none"
    profile.general.combatReady = selectedData(window.profileCombatReady) or "default"
    storeOutfitControls(window)
    profile.outfits.A = profile.outfits.A or deepCopy(profile.clothing or {})
    profile.outfitTints.A = profile.outfitTints.A or {}
    profile.clothing = deepCopy(profile.outfits.A or {})
    profile.weapons.primary = selectedData(window.primaryCombo) or "none"
    profile.weapons.secondary = selectedData(window.secondaryCombo) or "none"
    profile.weapons.melee = selectedData(window.meleeCombo) or "none"
    profile.general.ammoMode = "magazines"
    profile.general.primaryMagazines = math.max(0,
        math.floor(tonumber(window.primaryMagazines:getText()) or 0))
    profile.general.secondaryMagazines = math.max(0,
        math.floor(tonumber(window.secondaryMagazines:getText()) or 0))
    profile.ammo.primary = profile.general.primaryMagazines
        * itemCapacity(firstPoolChoice(profile.weapons.primary))
    profile.ammo.secondary = profile.general.secondaryMagazines
        * itemCapacity(firstPoolChoice(profile.weapons.secondary))
    for _, key in ipairs(Creator.statKeys) do
        local entry, range = window.statEntries[key], Creator.statRanges[key]
        if entry then
            local typed = tonumber(entry:getText()) or Creator.statValue(profile.general, key)
            profile.general[key] = math.max(range[1], math.min(range[2], typed))
        end
    end
    profile.general.infiniteAmmo = window.infiniteAmmo:isSelected(1)
    Creator.harvestProfileSupport(window, profile.general)
    profile.general.dropAmmo = window.dropAmmo:isSelected(1)
    profile.general.dropWeaponPreset = selectedData(window.dropWeaponChance) or "very_high"
    profile.general.dropWeapon = profile.general.dropWeaponPreset ~= "off"
    local dropPreset = ProjectALife.DropPolicy.resolve(profile.general)
    profile.general.dropWeaponChance = math.floor((dropPreset[3] + dropPreset[4]) / 2)
    if window.magazineDropChance then
        profile.general.magazineDropChance = math.max(0, math.min(100,
            tonumber(window.magazineDropChance:getText()) or 35))
    end
    profile.general.dropWeaponCondition = math.max(0, math.min(10,
        tonumber(window.dropWeaponCondition and window.dropWeaponCondition:getText())
            or profile.general.dropWeaponCondition or 5))
    profile.general.dropArmorChance = math.max(0, math.min(100,
        tonumber(window.dropArmorChance:getText()) or 20))
    profile.general.armorCondition = math.max(0, math.min(10,
        tonumber(window.armorCondition and window.armorCondition:getText())
            or profile.general.armorCondition or 5))
    profile.general.damageReduction = math.max(0, math.min(90,
        tonumber(window.damageReduction and window.damageReduction:getText())
            or profile.general.damageReduction or 0))
    profile.general.damageOutput = math.max(1, math.min(500,
        tonumber(window.damageOutput and window.damageOutput:getText())
            or profile.general.damageOutput or 100))
    for _, spec in ipairs(PROFILE_MODULES) do
        local entry = window.profileModuleEntries and window.profileModuleEntries[spec[2]]
        if entry then profile.modules[spec[2]] = safeText(entry:getText()) end
    end
    for _, spec in ipairs(MEMBER_MODULES) do
        profile.moduleOverrides[spec[2]] = selectedData(
            window.profileModuleOverrides[spec[2]]) or "inherit"
    end
    return profile
end

function Creator.clearClothingSlot(window, slot)
    if not window.currentProfile then return false end
    local combo = slot == "Faces" and window.faceCombo or window.clothingCombos and window.clothingCombos[slot]
    if not combo then return false end
    closeItemPicker(window)
    selectData(combo, "none")
    storeOutfitControls(window)
    local tints = currentOutfitTints(window)
    if tints then tints[slot] = nil end
    if window.syncLoadoutTiles then window.syncLoadoutTiles() end
    if window.faceTile then window.faceTile:syncValue() end
    refreshAvatar(window)
    return true
end

function Creator.clearLoadoutSlot(window, slot, combo)
    if not combo then return false end
    selectData(combo, "none")
    if window.currentProfile then
        window.currentProfile.weapons = window.currentProfile.weapons or {}
        window.currentProfile.weapons[slot] = "none"
    end
    harvestProfile(window)
    if window.syncLoadoutTiles then window.syncLoadoutTiles() end
    refreshAvatar(window)
    if window.statusLabel then window.statusLabel:setName(string.upper(slot) .. " CLEARED") end
    return true
end

local refreshFactions, refreshRoster, selectFaction, selectProfile
local rebuildFactionCards, rebuildProfileCards
local saveFaction, saveProfile
local setProfilePage

local function clearCardPanels(container, cards)
    for _, card in ipairs(cards or {}) do
        if card.portrait then card.portrait:setVisible(false) end
        card.descriptor = nil
        card:setVisible(false)
        pcall(function() container:removeChild(card) end)
    end
    return {}
end

local function queuePortrait(window, card, profile, headOnly, generation, scope)
    if not profile then return end
    window.portraitQueue = window.portraitQueue or {}

    for index = #window.portraitQueue, 1, -1 do
        if window.portraitQueue[index].card == card then table.remove(window.portraitQueue, index) end
    end
    window.portraitQueue[#window.portraitQueue + 1] = {
        card = card, profile = profile, headOnly = headOnly,
        generation = generation, scope = scope,
    }
end

local function discardPortraitScope(window, scope)
    local queue = window and window.portraitQueue
    if type(queue) ~= "table" then return end
    for index = #queue, 1, -1 do
        if queue[index] and queue[index].scope == scope then
            table.remove(queue, index)
        end
    end
end

local addCardButton

local function translatedStyleLabel(kind, id)
    if id == "" then return kind == "beard" and "Clean shaven" or "Bald / no hair" end
    local key = (kind == "beard" and "IGUI_Beard_" or "IGUI_Hair_") .. tostring(id)
    if type(getText) == "function" then
        local ok, label = pcall(getText, key)
        if ok and label and label ~= key then return tostring(label) end
    end
    return tostring(id):gsub("_", " ")
end

local function appearanceStyleOptions(kind, female)
    local result, seen = {}, {}
    local ok, styles = pcall(function()
        if kind == "beard" then return getAllBeardStyles() end
        return getAllHairStyles(female == true)
    end)
    if ok and styles and styles.size and styles.get then
        for index = 0, styles:size() - 1 do
            local id, choose = tostring(styles:get(index) or ""), true
            if kind == "hair" then
                pcall(function()
                    local registry = getHairStylesInstance()
                    local style = female and registry:FindFemaleStyle(id)
                        or registry:FindMaleStyle(id)
                    choose = style ~= nil and not style:isNoChoose()
                end)
            end
            if choose and not seen[id] then
                seen[id] = true
                result[#result + 1] = { id = id, label = translatedStyleLabel(kind, id) }
            end
        end
    end

    if not seen[""] then
        seen[""] = true
        result[#result + 1] = { id = "", label = translatedStyleLabel(kind, "") }
    end

    if #result <= 1 then
        for _, id in ipairs(kind == "beard" and BEARD or HAIR) do
            id = tostring(id or "")
            if not seen[id] then
                seen[id] = true
                result[#result + 1] = { id = id, label = translatedStyleLabel(kind, id) }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.id == "" then return true end
        if b.id == "" then return false end
        return string.lower(a.label) < string.lower(b.label)
    end)
    return result
end

local function repopulateStyleCombo(combo, options, wanted)
    if not combo then return end
    combo.options = {}
    local selected = 1
    for index, option in ipairs(options) do
        combo:addOptionWithData(option.label, option.id)
        if tostring(option.id) == tostring(wanted or "") then selected = index end
    end
    combo.selected = selected
end

rebuildAppearanceStyleCombos = function(window, hairWanted, beardWanted)
    local female = window.profileFemaleValue == true
    repopulateStyleCombo(window.profileHair,
        appearanceStyleOptions("hair", female), hairWanted)
    repopulateStyleCombo(window.profileBeard,
        female and { { id = "", label = "Not available for female body" } }
            or appearanceStyleOptions("beard", false), female and "" or beardWanted)
end

local function updateCurrentAppearance(window)
    local profile = window.currentProfile
    if not profile then return end
    profile.general = profile.general or {}
    profile.general.female = window.profileFemaleValue == true
    profile.general.skin = math.max(0, math.min(4,
        math.floor(tonumber(window.profileSkin:getText()) or 0)))
    profile.general.hairStyle = selectedData(window.profileHair) or ""
    profile.general.hairColor = encodeColor(window.profileHairColorValue)
    profile.general.beardStyle = profile.general.female and ""
        or (selectedData(window.profileBeard) or "")
    profile.general.beardColor = encodeColor(window.profileBeardColorValue)
    syncAppearanceControls(window)
    refreshAvatar(window)
end

syncAppearanceControls = function(window)
    if window.profileGender then
        local gender = window.profileFemaleValue and "female" or "male"
        selectData(window.profileGender, gender)
        window.profileGenderApplied = gender
    end
    if window.profileMaleButton then
        styleButton(window.profileMaleButton, window.profileFemaleValue ~= true)
        styleButton(window.profileFemaleButton, window.profileFemaleValue == true)
    end
    local skin = math.max(0, math.min(4,
        math.floor(tonumber(window.profileSkin and window.profileSkin:getText()) or 0)))
    for index, button in ipairs(window.profileSkinButtons or {}) do
        button.borderColor = copyColor(index - 1 == skin and ROSE or CONTROL_BORDER)
    end
    if window.profileHairValueLabel then
        window.profileHairValueLabel:setName(fitText(translatedStyleLabel(
            "hair", selectedData(window.profileHair) or ""), UIFont.Small,
            math.max(30, (window.profileHairBrowse and window.profileHairBrowse.x or 310) - 84)))
    end
    if window.profileBeardValueLabel then
        window.profileBeardValueLabel:setName(fitText(window.profileFemaleValue and
            "Not available" or translatedStyleLabel(
                "beard", selectedData(window.profileBeard) or ""), UIFont.Small,
            math.max(30, (window.profileBeardBrowse and window.profileBeardBrowse.x or 310) - 84)))
    end
    if window.profileHairColorButton then
        Creator.paintColorSwatch(window.profileHairColorButton,
            decodeColor(window.profileHairColorValue))
    end
    if window.profileBeardColorButton then

        pcall(function() window.profileBeardBrowse:setEnable(
            window.profileFemaleValue ~= true) end)
        pcall(function() window.profileBeardColorButton:setEnable(
            window.profileFemaleValue ~= true) end)
        if window.profileFemaleValue ~= true then
            Creator.paintColorSwatch(window.profileBeardColorButton,
                decodeColor(window.profileBeardColorValue))
        end
    end
    if window.outfitTintStatus and window.selectedClothingSlot then
        local slot = window.selectedClothingSlot
        local tints = currentOutfitTints(window)
        local tint = tints and tints[slot] or nil
        window.outfitTintStatus:setName(string.upper(slot) .. " COLOR: " ..
            (tint and "CUSTOM" or "NATIVE ITEM COLOR"))
    end
end

setProfileGender = function(window, female)
    if window.profileFemaleValue == (female == true) then return end
    local hair, beard = selectedData(window.profileHair), selectedData(window.profileBeard)
    window.profileFemaleValue = female == true
    rebuildAppearanceStyleCombos(window, hair, beard)
    updateCurrentAppearance(window)
end

setProfileSkin = function(window, index)
    window.profileSkin:setText(tostring(math.max(0, math.min(4, index or 0))))
    updateCurrentAppearance(window)
end

local function setAppearanceStyle(window, kind, id)
    selectData(kind == "beard" and window.profileBeard or window.profileHair, id)
    updateCurrentAppearance(window)
end

local function setAppearanceColor(window, kind, color)
    if kind == "beard" then
        window.profileBeardColorValue = encodeColor(color)
    else
        window.profileHairColorValue = encodeColor(color)
    end
    updateCurrentAppearance(window)
end

local function commonHairColors(window)
    local result, seen = {}, {}
    for _, group in ipairs({ Creator.hairPalette.natural, Creator.hairPalette.dyed }) do
        for _, color in ipairs(group) do
            local encoded = encodeColor(color)
            if not seen[encoded] then
                seen[encoded] = true
                result[#result + 1] = decodeColor(color)
            end
        end
    end
    return result
end

local function closeAppearancePicker(window)
    local picker = window.appearancePicker
    if not picker then return end
    window.appearancePortraitGeneration = (window.appearancePortraitGeneration or 0) + 1
    discardPortraitScope(window, "appearance")
    for _, card in ipairs(picker.cards or {}) do
        if card.portrait then card.portrait:setVisible(false) end
    end
    picker:setVisible(false)
    pcall(function() window:removeChild(picker) end)
    window.appearancePicker = nil
end

local function onAppearanceColorPicked(window, color, mouseUp, kind)
    if window and color then setAppearanceColor(window, kind, color) end
end

openAppearanceColorPicker = function(window, kind, button)
    if kind == "beard" and window.profileFemaleValue then return end
    local current = decodeColor(kind == "beard" and window.profileBeardColorValue
        or window.profileHairColorValue)
    local picker = ISColorPickerHSB:new(0, 0,
        ColorInfo.new(current.r, current.g, current.b, 1))
    picker:initialise()
    picker.keepOnScreen = true
    picker.pickedTarget = window
    picker:setPickedFunc(onAppearanceColorPicked, kind)
    picker:setInitialColor(ColorInfo.new(current.r, current.g, current.b, 1))
    picker:setX(math.max(0, math.min(getCore():getScreenWidth() - picker.width,
        button:getAbsoluteX())))
    picker:setY(math.max(0, math.min(getCore():getScreenHeight() - picker.height,
        button:getAbsoluteY() + button.height)))
    picker:addToUIManager()
    picker:setAlwaysOnTop(true)
    picker:bringToTop()
end

openAppearancePicker = function(window, kind)
    if not window.currentProfile or (kind == "beard" and window.profileFemaleValue) then return end
    closeAppearancePicker(window)
    closeItemPicker(window)
    local px = Creator.px
    local pickerW = math.min(px(1080), window.width - px(72))
    local pickerH = math.min(px(760), window.height - px(72))
    local picker = createFramedPanel(window,
        math.floor((window.width - pickerW) / 2),
        math.floor((window.height - pickerH) / 2), pickerW, pickerH)
    picker.backgroundColor = { r = 0.008, g = 0.010, b = 0.014, a = 0.998 }
    picker.borderColor = copyColor(ROSE)
    picker:bringToTop()
    picker.cards = {}
    window.appearancePicker = picker
    installDragHandle(picker, px(42))
    window.appearancePortraitGeneration = (window.appearancePortraitGeneration or 0) + 1
    local generation = window.appearancePortraitGeneration
    addLabel(picker, px(24), px(18), kind == "beard" and "BEARD CREATOR" or "HAIR CREATOR",
        ROSE, UIFont.Medium)
    addButton(picker, picker.width - px(48), px(10), px(30), "X",
        function() closeAppearancePicker(window) end)
    addLabel(picker, px(24), px(46),
        "Vanilla Build 42 styles plus loaded mod styles. Select a head to apply it.", MUTED)
    local compactPicker = picker.width < px(760) or picker.height < px(560)
    local customW = compactPicker and px(124) or px(170)
    local searchW = compactPicker and math.max(px(120), picker.width - customW - px(72))
        or math.min(px(440), picker.width - px(250))
    local search = addEntry(picker, px(24), px(76), searchW, "")
    search:setPlaceholderText("Search style name...")
    addLabel(picker, px(24), px(112), "COLOR PRESETS", ROSE)
    local colors = commonHairColors(window)
    local swatchSize = compactPicker and px(16) or px(27)
    local swatchGap = compactPicker and px(2) or px(4)
    local swatchWidth = picker.width - px(48)
        - (compactPicker and 0 or customW + px(22))
    local swatchesPerRow = math.max(8,
        math.floor(swatchWidth / (swatchSize + swatchGap)))
    for index, color in ipairs(colors) do
        local swatchColor = color
        local swatchIndex = index - 1
        local button = addButton(picker,
            px(24) + (swatchIndex % swatchesPerRow) * (swatchSize + swatchGap),
            px(136) + math.floor(swatchIndex / swatchesPerRow)
                * (swatchSize + swatchGap),
            swatchSize, "", function()
            setAppearanceColor(window, kind, swatchColor)
        end)
        button.backgroundColor = { r = color.r, g = color.g, b = color.b, a = 1 }
        button.borderColor = copyColor(CONTROL_BORDER)
    end
    addButton(picker, picker.width - customW - px(24),
        compactPicker and px(76) or px(136), customW,
        "CUSTOM COLOR", function(_, button)
        openAppearanceColorPicker(window, kind, button)
    end, true)
    local colorRows = math.max(1, math.ceil(#colors / swatchesPerRow))
    local areaY = px(136) + colorRows * (swatchSize + swatchGap) + px(12)
    local activeLabel = addLabel(picker,
        compactPicker and px(144) or picker.width - customW - px(24),
        compactPicker and px(112) or px(170),
        "ACTIVE: " .. string.upper(translatedStyleLabel(kind,
            selectedData(kind == "beard" and window.profileBeard or window.profileHair) or "")),
        TEXT)
    local area = ISPanel:new(px(24), areaY, picker.width - px(48),
        math.max(px(64), picker.height - areaY - px(78)))
    area:initialise()
    area.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    area.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    picker:addChild(area)
    local page, applied = 1, ""
    local styleOptions = appearanceStyleOptions(kind, window.profileFemaleValue)
    local pageLabel = addLabel(picker, px(82), picker.height - px(59), "PAGE 1 / 1", MUTED)
    local rebuild
    rebuild = function()
        discardPortraitScope(window, "appearance")
        for _, card in ipairs(picker.cards) do
            if card.portrait then card.portrait:setVisible(false) end
            card:setVisible(false)
            pcall(function() area:removeChild(card) end)
        end
        picker.cards = {}
        window.appearancePortraitGeneration = window.appearancePortraitGeneration + 1
        generation = window.appearancePortraitGeneration
        local query, filtered = string.lower(tostring(search:getText() or "")), {}
        for _, option in ipairs(styleOptions) do
            if query == "" or string.lower(option.label):find(query, 1, true)
                    or string.lower(option.id):find(query, 1, true) then
                filtered[#filtered + 1] = option
            end
        end
        local gap = compactPicker and px(5) or px(8)
        local columns = math.max(4, math.min(6,
            math.floor((area.width + gap) / (compactPicker and px(116) or px(148)))))
        local compactCards = area.height < px(180)
        local rows = compactCards and 2 or 3
        local cardW = math.floor((area.width - gap * (columns - 1)) / columns)
        local cardH = math.floor((area.height - gap * (rows - 1)) / rows)
        local capacity = columns * rows
        local pages = math.max(1, math.ceil(#filtered / capacity))
        page = math.max(1, math.min(page, pages))
        picker.pickerPageCount = pages
        pageLabel:setName("PAGE " .. tostring(page) .. " / " .. tostring(pages))
        local first = (page - 1) * capacity + 1
        for index = first, math.min(#filtered, first + capacity - 1) do
            local option, slotIndex = filtered[index], index - first
            local x = (slotIndex % columns) * (cardW + gap)
            local y = math.floor(slotIndex / columns) * (cardH + gap)
            local card = ISPanel:new(x, y, cardW, cardH)
            card:initialise()
            card.option, card.kind, card.window = option, kind, window
            card.compactAppearance = compactCards
            card.prerender = function(self)
                ISPanel.prerender(self)
                local selected = tostring(selectedData(self.kind == "beard" and
                    self.window.profileBeard or self.window.profileHair) or "") == self.option.id
                self:drawRect(0, 0, self.width, self.height, 0.98,
                    selected and ROSE_DARK.r or CARD_BG.r,
                    selected and ROSE_DARK.g or CARD_BG.g,
                    selected and ROSE_DARK.b or CARD_BG.b)
                self:drawRectBorder(0, 0, self.width, self.height, 0.9,
                    selected and ROSE.r or 0.28, selected and ROSE.g or 0.29,
                    selected and ROSE.b or 0.32)
                self:drawTextCentre(fitText(self.option.label, UIFont.Small, self.width - px(12)),
                    self.width / 2, self.height - (self.compactAppearance and px(18) or px(39)),
                    TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
                if not self.compactAppearance then
                    self:drawTextCentre(fitText(self.option.id == "" and "VANILLA NONE"
                        or self.option.id, UIFont.Small, self.width - px(12)),
                        self.width / 2, self.height - px(21),
                        MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
                end
            end
            area:addChild(card)
            picker.cards[#picker.cards + 1] = card
            local preview = deepCopy(window.currentProfile)
            preview.clothing = deepCopy(preview.clothing or {})
            preview.clothing.Hat, preview.clothing.Eyes, preview.clothing.Mask =
                "none", "none", "none"
            if kind == "beard" then
                preview.general.beardStyle = option.id
            else
                preview.general.hairStyle = option.id
            end
            queuePortrait(window, card, preview, true, generation, "appearance")
            local chosenCard = card
            local choose = addCardButton(card, function()
                setAppearanceStyle(window, kind, chosenCard.option.id)
                activeLabel:setName("ACTIVE: " .. string.upper(
                    translatedStyleLabel(kind, chosenCard.option.id)))
            end)
            choose:bringToTop()
        end
    end
    addButton(picker, px(24), picker.height - px(64), px(48), "<", function()
        page = math.max(1, page - 1); rebuild()
    end)
    addButton(picker, px(174), picker.height - px(64), px(48), ">", function()
        page = math.min(picker.pickerPageCount or 1, page + 1); rebuild()
    end)
    addButton(picker, picker.width - px(144), picker.height - px(64), px(120), "DONE",
        function() closeAppearancePicker(window) end, true)
    picker.update = function(self)
        ISPanel.update(self)
        local value = tostring(search:getText() or "")
        if value ~= applied then applied, page = value, 1; rebuild() end
    end
    rebuild()
end
Creator.setProfileSkin = setProfileSkin
Creator.openAppearanceColorPicker = openAppearanceColorPicker
Creator.openAppearancePicker = openAppearancePicker

addCardButton = function(card, callback)
    local button = ISButton:new(0, 0, card.width, card.height, "", card, callback)
    button:initialise()
    button:instantiate()
    button.displayBackground = false
    button.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    button.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    card:addChild(button)
    card.openButton = button
    return button
end

local function factionProfiles(window, factionId)

    local order = window.catalog and window.catalog.npcOrder or nil
    if order == nil then return {} end
    local cache = window.rosterCache
    if cache == nil or cache.order ~= order or cache.size ~= #order
            or cache.revision ~= (window.rosterRevision or 0) then
        cache = { order = order, size = #order, revision = window.rosterRevision or 0, byFaction = {} }
        for _, record in ipairs(order) do
            local homeId = record.general and record.general.faction
            if homeId ~= nil then
                local list = cache.byFaction[homeId]
                if list == nil then
                    list = {}
                    cache.byFaction[homeId] = list
                end
                list[#list + 1] = record
            end
        end
        window.rosterCache = cache
    end
    local list = cache.byFaction[factionId]
    local profiles = {}
    for index = 1, (list ~= nil and #list or 0) do profiles[index] = list[index] end
    return profiles
end

local function pageWindow(records, requestedPage, capacity)
    local pageCount = math.max(1, math.ceil(#records / math.max(1, capacity)))
    local page = math.max(1, math.min(requestedPage or 1, pageCount))
    local first = (page - 1) * capacity + 1
    return page, pageCount, first, math.min(#records, first + capacity - 1)
end

local function setPageControls(previous, nextButton, label, page, count)
    if previous then previous:setEnable(page > 1) end
    if nextButton then nextButton:setEnable(page < count) end
    if label then label:setName("PAGE " .. tostring(page) .. " / " .. tostring(count)) end
end

local function closeFolderDialog(window)
    local dialog = window and window.folderDialog or nil
    if not dialog then return end
    dialog:setVisible(false)
    pcall(function() window:removeChild(dialog) end)
    window.folderDialog = nil
end

function Creator.folderSaved(window, ok)
    if not ok and window.statusLabel then
        window.statusLabel:setName("FOLDER CHANGE FAILED - COULD NOT SAVE")
    end
    return ok
end

local function openFolderDialog(window, folderId)
    closeFolderDialog(window)
    local existing = folderId and ProjectALife.CreatorFolders.get(folderId) or nil
    local overlay = ISPanel:new(0, 0, window.width, window.height)
    overlay:initialise()
    overlay.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    overlay.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    overlay.prerender = function(self)
        self:drawRect(0, 0, self.width, self.height, 0.76, 0, 0, 0)
    end
    window:addChild(overlay)
    window.folderDialog = overlay

    local px = Creator.px
    local boxW = math.min(existing and px(720) or px(480), window.width - px(80))
    local boxH = existing and px(220) or px(184)
    local box = createFramedPanel(overlay, math.floor((window.width - boxW) / 2),
        math.floor((window.height - boxH) / 2), boxW, boxH)
    addLabel(box, px(18), px(16), existing and "FOLDER ACTIONS" or "CREATE FOLDER",
        ROSE, UIFont.Medium)
    addLabel(box, px(18), px(52), "Folder name", MUTED)
    local entry = addEntry(box, px(18), px(76), boxW - px(36), existing and existing.name or "")
    entry:setPlaceholderText("Example: Raiders, Story factions, Test groups...")
    if existing then
        addButton(box, px(18), boxH - px(44), px(112), "DELETE FOLDER", function()
            local id, name = existing.id, existing.name
            closeFolderDialog(window)
            local count = 0
            for _, included in pairs(existing.factions or {}) do
                if included == true then count = count + 1 end
            end
            local modal = ISModalDialog:new(0, 0, px(440), px(150),
                "Delete folder '" .. safeText(name) .. "' and everything in it?\n"
                    .. tostring(count) .. " factions and all their NPCs will be deleted.",
                true, { window = window, id = id }, function(subject, button)
                    if button.internal ~= "YES" then return end
                    Creator.deleteFolderWithFactions(subject.window, subject.id)
                end, nil)
            modal:initialise(); modal:addToUIManager()
            modal:setAlwaysOnTop(true); modal:bringToTop()
        end)
        addButton(box, px(138), boxH - px(44), px(150), "COPY NPC FOLDER", function()
            closeFolderDialog(window)
            Creator.copyFolder(window, existing.id)
        end)
        addButton(box, px(296), boxH - px(44), px(150), "SHARE CODE", function()
            closeFolderDialog(window)
            Creator.exportFolderCode(window, existing.id)
        end)
    end
    addButton(box, boxW - px(220), boxH - px(44), px(94), "CANCEL", function()
        closeFolderDialog(window)
    end)
    addButton(box, boxW - px(116), boxH - px(44), px(98),
        existing and "RENAME" or "CREATE", function()
            local name = entry:getText()
            local saved
            if existing then
                saved = ProjectALife.CreatorFolders.rename(existing.id, name)
            else
                saved = ProjectALife.CreatorFolders.create(name)
            end
            if not Creator.folderSaved(window, saved) then return end
            closeFolderDialog(window)
            window.factionPage = 1
            rebuildFactionCards(window)
        end, true)
    overlay:bringToTop()
    pcall(function() entry:focus() end)
end

function Creator.copyFolder(window, folderId)
    if not Creator.flushEdits(window) then return false end
    local plan = window.catalog
        and ProjectALife.CreatorFolders.copyPlan(folderId, window.catalog.factionOrder,
            function(id) return factionProfiles(window, id) end, uniqueId,
            factionFromRecord, profileFromRecord) or nil
    if plan == nil then return false end
    local saved, sent = ProjectALife.CustomFactions.saveMany(plan.factions)
    if not saved then
        if window.statusLabel then window.statusLabel:setName((sent or 0) > 0
            and "COPY PARTIAL - SOME FACTIONS SENT, CHECKING SERVER"
            or "FOLDER COPY FAILED - COULD NOT SAVE") end
        return false
    end
    if not ProjectALife.CustomProfiles.saveMany(plan.profiles) then
        refreshFactions(window)
        if window.statusLabel then window.statusLabel:setName("COPY PARTIAL - FACTIONS ADDED, NPC SAVE FAILED") end
        return false
    end
    local folder = ProjectALife.CreatorFolders.create(plan.name)
    if not folder then
        refreshFactions(window)
        if window.statusLabel then window.statusLabel:setName("COPY PARTIAL - NPCS ADDED, FOLDER SAVE FAILED") end
        return false
    end
    local previous = ProjectALife.CreatorFolders.serializeAll()
    for _, faction in ipairs(plan.factions) do folder.factions[faction.id] = true end
    if not ProjectALife.CreatorFolders.persist(previous)
            or not ProjectALife.CreatorFolders.moveFolder(folder.id, folderId, true) then
        refreshFactions(window)
        if window.statusLabel then window.statusLabel:setName("COPY PARTIAL - NPCS ADDED, FOLDER SAVE FAILED") end
        return false
    end
    refreshFactions(window, window.currentFaction and window.currentFaction.id or nil)
    if window.statusLabel then
        window.statusLabel:setName("FOLDER COPIED - FACTIONS: " .. tostring(#plan.factions)
            .. ", NPCS: " .. tostring(#plan.profiles))
    end
    return true
end

local function factionDropTarget(window)
    for _, header in ipairs(window.folderHeaders or {}) do
        local hovered = false
        pcall(function()
            hovered = header:isMouseOver()
                or (header.openButton and header.openButton:isMouseOver())
        end)
        if hovered then return header.folderId end
    end
    return nil
end

local function factionOrderDropTarget(window)
    for _, card in ipairs(window.factionCards or {}) do
        if card.record and card.record.id then
            local hovered = false
            pcall(function()
                hovered = card:isMouseOver()
                    or (card.openButton and card.openButton:isMouseOver())
            end)
            if hovered then
                local after = false
                pcall(function()
                    after = getMouseY() - card:getAbsoluteY() > card.height / 2
                end)
                return card.record.id, card.folderId, after
            end
        end
    end
    return nil
end

local function moveFactionToHoveredFolder(window)
    local drag = window.factionDrag
    if not drag or not drag.active then return false end
    local targetId, targetFolder, after = factionOrderDropTarget(window)
    if targetId and targetId ~= drag.factionId then
        local function finish()
            local saved = ProjectALife.CreatorFolders.assign(drag.factionId, targetFolder)
                and ProjectALife.CreatorFolders.move(drag.factionId, targetId, after)
            window.factionDrag = nil
            rebuildFactionCards(window)
            return Creator.folderSaved(window, saved)
        end
        if Creator.dragNeedsQuestion(window, drag.factionId, targetFolder, finish) then
            window.factionDrag = nil
            return true
        end
        return finish()
    end
    local folderId = factionDropTarget(window)
    if folderId then
        local function finishDrop()
            local saved = ProjectALife.CreatorFolders.assign(drag.factionId, folderId)
            window.factionDrag = nil
            rebuildFactionCards(window)
            return Creator.folderSaved(window, saved)
        end
        if Creator.dragNeedsQuestion(window, drag.factionId, folderId, finishDrop) then
            window.factionDrag = nil
            return true
        end
        return finishDrop()
    end
    window.factionDrag = nil
    return true
end

function Creator.folderOrderDropTarget(window)
    for _, header in ipairs(window.folderHeaders or {}) do
        if header.entry and header.entry.folder then
            local hovered = false
            pcall(function()
                hovered = header:isMouseOver()
                    or (header.openButton and header.openButton:isMouseOver())
            end)
            if hovered then
                local after = false
                pcall(function()
                    after = getMouseY() - header:getAbsoluteY() > header.height / 2
                end)
                return header.folderId, after
            end
        end
    end
    return nil
end

function Creator.finishFolderDrag(window)
    local drag = window.folderDrag
    if not drag or not drag.active then return false end
    local targetId, after = Creator.folderOrderDropTarget(window)
    if targetId and targetId ~= drag.folderId then
        local saved = ProjectALife.CreatorFolders.moveFolder(drag.folderId, targetId, after)
        window.folderDrag = nil
        window.factionPage = 1
        rebuildFactionCards(window)
        return Creator.folderSaved(window, saved)
    end
    window.folderDrag = nil
    return true
end

function Creator.placeFolderControls(header)
    local width, px = header.width, Creator.px
    if header.openButton then
        header.openButton:setWidth(math.max(1, header.renameButton and width - px(108) or width))
    end
    if header.moveUpButton then header.moveUpButton:setX(width - px(102)) end
    if header.moveDownButton then header.moveDownButton:setX(width - px(68)) end
    if header.renameButton then header.renameButton:setX(width - px(34)) end
end

function Creator.installFolderDrag(window, header, folderId)
    local button = header and header.openButton
    if not button then return end
    local baseMove, baseMoveOutside = button.onMouseMove, button.onMouseMoveOutside
    local baseUp, baseUpOutside = button.onMouseUp, button.onMouseUpOutside
    button.onmousedown = function(_, pressedButton)
        window.folderDrag = {
            folderId = folderId,
            folderName = safeText(header.entry and header.entry.name),
            button = pressedButton,
            distance = 0,
            active = false,
        }
    end
    local function noteFolderMovement(dx, dy)
        local drag = window.folderDrag
        if not drag or drag.button ~= button then return end
        drag.distance = drag.distance + math.abs(tonumber(dx) or 0)
            + math.abs(tonumber(dy) or 0)
        if drag.distance >= 7 then drag.active = true end
    end
    button.onMouseMove = function(self, dx, dy)
        if baseMove then baseMove(self, dx, dy) end
        noteFolderMovement(dx, dy)
    end
    button.onMouseMoveOutside = function(self, dx, dy)
        if baseMoveOutside then baseMoveOutside(self, dx, dy) end
        noteFolderMovement(dx, dy)
    end
    button.onMouseUp = function(self, x, y)
        if Creator.finishFolderDrag(window) then self.pressed = false; return true end
        window.folderDrag = nil
        return baseUp and baseUp(self, x, y) or false
    end
    button.onMouseUpOutside = function(self, x, y)
        if Creator.finishFolderDrag(window) then self.pressed = false; return true end
        window.folderDrag = nil
        return baseUpOutside and baseUpOutside(self, x, y) or false
    end
end

local function addFactionDragButton(window, card, factionId, callback)
    local button = addCardButton(card, callback)
    button.onRightMouseUp = function()
        if Creator.confirmDeleteFaction then
            Creator.confirmDeleteFaction(window, factionId)
        end
        return true
    end
    local baseMove = button.onMouseMove
    local baseMoveOutside = button.onMouseMoveOutside
    local baseUp = button.onMouseUp
    local baseUpOutside = button.onMouseUpOutside
    button.onmousedown = function(_, pressedButton)
        window.factionDrag = {
            factionId = factionId,
            factionName = safeText(card.record and card.record.general
                and card.record.general.name),
            factionCategory = safeText(card.record and card.record.general
                and card.record.general.category),
            button = pressedButton,
            distance = 0,
            active = false,
        }
    end
    local function noteMovement(dx, dy)
        local drag = window.factionDrag
        if not drag or drag.button ~= button then return end
        drag.distance = drag.distance + math.abs(tonumber(dx) or 0)
            + math.abs(tonumber(dy) or 0)
        if drag.distance >= 7 then drag.active = true end
    end
    button.onMouseMove = function(self, dx, dy)
        if baseMove then baseMove(self, dx, dy) end
        noteMovement(dx, dy)
    end
    button.onMouseMoveOutside = function(self, dx, dy)
        if baseMoveOutside then baseMoveOutside(self, dx, dy) end
        noteMovement(dx, dy)
    end
    button.onMouseUp = function(self, x, y)
        if moveFactionToHoveredFolder(window) then
            self.pressed = false
            return true
        end
        window.factionDrag = nil
        return baseUp and baseUp(self, x, y) or false
    end
    button.onMouseUpOutside = function(self, x, y)
        if moveFactionToHoveredFolder(window) then
            self.pressed = false
            return true
        end
        window.factionDrag = nil
        return baseUpOutside and baseUpOutside(self, x, y) or false
    end
    return button
end

local function factionTreeEntries(window, records, searching)
    local entries, assigned = {}, {}
    ProjectALife.CreatorFolders.ensureOrder(records)
    table.sort(records, function(a, b)
        return ProjectALife.CreatorFolders.rank(a.id)
            < ProjectALife.CreatorFolders.rank(b.id)
    end)
    for _, folder in ipairs(ProjectALife.CreatorFolders.folders or {}) do
        local children = {}
        for _, record in ipairs(records) do
            if folder.factions and folder.factions[record.id] == true then
                children[#children + 1] = record
                assigned[record.id] = true
            end
        end
        if not searching or #children > 0 then
            entries[#entries + 1] = {
                kind = "folder", folderId = folder.id, folder = folder,
                name = folder.name, count = #children,
            }
            if searching or not folder.collapsed then
                for _, record in ipairs(children) do
                    entries[#entries + 1] = {
                        kind = "faction", folderId = folder.id, record = record,
                    }
                end
            end
        end
    end
    local unfiled = {}
    for _, record in ipairs(records) do
        if not assigned[record.id] then unfiled[#unfiled + 1] = record end
    end
    if not searching or #unfiled > 0 then
        entries[#entries + 1] = {
            kind = "folder", folderId = ProjectALife.CreatorFolders.unfiledId,
            name = "Unfiled", count = #unfiled,
            collapsed = window.unfiledCollapsed == true,
        }
        if searching or not window.unfiledCollapsed then
            for _, record in ipairs(unfiled) do
                entries[#entries + 1] = {
                    kind = "faction", folderId = ProjectALife.CreatorFolders.unfiledId,
                    record = record,
                }
            end
        end
    end
    return entries
end

local function factionTreePages(entries, availableHeight)
    local folderH, cardH = Creator.px(34), Creator.px(72)
    local headers, cards = 0, 0
    for _, entry in ipairs(entries) do
        if entry.kind == "folder" then headers = headers + 1 else cards = cards + 1 end
    end
    local capacity = math.floor((availableHeight - headers * folderH) / cardH)
    local pages, page, used = {}, {}, 0
    if capacity >= 1 then
        for number = 1, math.max(1, math.ceil(cards / capacity)) do
            local first, last, index = (number - 1) * capacity + 1, number * capacity, 0
            page = {}
            for _, entry in ipairs(entries) do
                if entry.kind == "folder" then
                    page[#page + 1] = entry
                else
                    index = index + 1
                    if index >= first and index <= last then page[#page + 1] = entry end
                end
            end
            pages[number] = page
        end
        return pages
    end
    for _, entry in ipairs(entries) do
        local height = entry.kind == "folder" and folderH or cardH
        if #page > 0 and used + height > availableHeight then
            pages[#pages + 1], page, used = page, {}, 0
        end
        page[#page + 1] = entry
        used = used + height
    end
    pages[#pages + 1] = page
    return pages
end

rebuildFactionCards = function(window)
    local container = window.factionCardsArea
    if not container then return end
    discardPortraitScope(window, "faction")
    window.factionCards = clearCardPanels(container, window.factionCards)
    window.folderHeaders = {}
    window.factionDrag, window.folderDrag = nil, nil
    window.factionPortraitGeneration = (window.factionPortraitGeneration or 0) + 1
    local generation = window.factionPortraitGeneration
    if not window.catalog then return end
    local query = tostring(window.factionSearch and window.factionSearch:getText() or ""):lower()
    local records = {}
    for _, record in ipairs(window.catalog.factionOrder or {}) do
        local name = safeText(record.general and record.general.name):lower()
        local category = safeText(record.general and record.general.category):lower()
        if Creator.seasonalFactionVisible(window, record)
                and (query == "" or name:find(query, 1, true) or category:find(query, 1, true)) then
            records[#records + 1] = record
        end
    end
    local entries = factionTreeEntries(window, records, query ~= "")
    local packedPages = factionTreePages(entries, container.height)
    local pageCount = math.max(1, #packedPages)
    local page = math.max(1, math.min(window.factionPage or 1, pageCount))
    window.factionPage, window.factionPageCount = page, pageCount
    setPageControls(window.factionPrev, window.factionNext,
        window.factionPageLabel, page, pageCount)
    local y, px = 0, Creator.px
    for _, entry in ipairs(packedPages[page] or {}) do
        if entry.kind == "folder" then
            local folderRecord, folderId = entry.folder, entry.folderId
            local header = ISPanel:new(0, y, container.width, px(30))
            header:initialise()
            header.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
            header.borderColor = { r = 0, g = 0, b = 0, a = 0 }
            header.owner = window
            header.folderId = folderId
            header.entry = entry
            header.prerender = function(self)
                local factionDrag, folderDrag = self.owner.factionDrag, self.owner.folderDrag
                local drop = factionDrag and factionDrag.active
                    and factionDropTarget(self.owner) == self.folderId
                    or folderDrag and folderDrag.active
                    and Creator.folderOrderDropTarget(self.owner) == self.folderId
                local collapsed = self.entry.folder and self.entry.folder.collapsed
                    or self.entry.collapsed == true
                local currentId = self.owner.currentFaction and self.owner.currentFaction.id
                local currentFolder = currentId and
                    ProjectALife.CreatorFolders.folderForFaction(currentId) or nil
                local hidesCurrent = collapsed and currentId ~= nil and
                    ((self.entry.folder and currentFolder == self.entry.folder)
                        or (self.folderId == ProjectALife.CreatorFolders.unfiledId
                            and currentFolder == nil))
                self:drawRect(0, 0, self.width, self.height, drop and 0.98 or 0.92,
                    drop and ROSE_DARK.r or (hidesCurrent and 0.070 or CARD_BG.r),
                    drop and ROSE_DARK.g or (hidesCurrent and 0.095 or CARD_BG.g),
                    drop and ROSE_DARK.b or (hidesCurrent and 0.100 or CARD_BG.b))
                self:drawRectBorder(0, 0, self.width, self.height,
                    (drop or hidesCurrent) and 1 or 0.8,
                    (drop or hidesCurrent) and ROSE.r or 0.32,
                    (drop or hidesCurrent) and ROSE.g or 0.24,
                    (drop or hidesCurrent) and ROSE.b or 0.29)
                self:drawText(collapsed and ">" or "v", px(10), px(7),
                    ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
                local suffix = tostring(self.entry.count or 0)
                    .. (hidesCurrent and "  -  ACTIVE" or "")

                local suffixRight = self.width - (self.renameButton and px(108) or px(12))
                local suffixWidth = getTextManager():MeasureStringX(UIFont.Small, suffix) + px(10)
                self:drawText(fitText(string.upper(safeText(self.entry.name)), UIFont.Small,
                    math.max(px(24), suffixRight - suffixWidth - px(32))), px(28), px(7),
                    TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
                self:drawTextRight(suffix, suffixRight, px(7),
                    hidesCurrent and ROSE.r or MUTED.r,
                    hidesCurrent and ROSE.g or MUTED.g,
                    hidesCurrent and ROSE.b or MUTED.b, 1, UIFont.Small)
            end
            container:addChild(header)
            window.factionCards[#window.factionCards + 1] = header
            window.folderHeaders[#window.folderHeaders + 1] = header
            local collapseW = folderRecord and header.width - px(108) or header.width
            local openButton = ISButton:new(0, 0, collapseW, header.height, "", header,
                function()
                    if folderRecord then
                        Creator.folderSaved(window, ProjectALife.CreatorFolders.toggle(folderId) ~= nil)
                    else
                        window.unfiledCollapsed = not window.unfiledCollapsed
                    end
                    window.factionPage = 1
                    rebuildFactionCards(window)
                end)
            openButton:initialise()
            openButton:instantiate()
            openButton.displayBackground = false
            openButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
            openButton.borderColor = { r = 0, g = 0, b = 0, a = 0 }
            header:addChild(openButton)
            header.openButton = openButton
            if folderRecord then
                Creator.installFolderDrag(window, header, folderId)
                header.moveUpButton = addButton(header, header.width - px(102), 0, px(30),
                    "^", function()
                        if Creator.folderSaved(window, ProjectALife.CreatorFolders.stepFolder(folderId, -1)) then
                            window.factionPage = 1
                            rebuildFactionCards(window)
                        end
                    end)
                header.moveUpButton.tooltip = "Move this folder up"
                header.moveDownButton = addButton(header, header.width - px(68), 0, px(30),
                    "v", function()
                        if Creator.folderSaved(window, ProjectALife.CreatorFolders.stepFolder(folderId, 1)) then
                            window.factionPage = 1
                            rebuildFactionCards(window)
                        end
                    end)
                header.moveDownButton.tooltip = "Move this folder down"

                header.renameButton = addButton(header, header.width - px(34), 0, px(34),
                    "", function()
                        openFolderDialog(window, folderId)
                    end)
                header.renameButton.render = function(self)
                    ISButton.render(self)
                    self:drawTextCentre("...", self.width / 2,
                        math.floor((self.height - getTextManager():getFontHeight(UIFont.Small)) / 2),
                        MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
                end
                header.renameButton.tooltip = "Folder actions: rename, copy or delete"
            end
            y = y + px(34)
        else
            local record, cardH = entry.record, px(66)
            local card = ISPanel:new(px(16), y, container.width - px(16), cardH)
        card:initialise()
        card.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        card.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        card.record = record
        card.folderId = entry.folderId
        card.owner = window
        card.prerender = function(self)
            local selected = self.owner.currentFaction and
                self.owner.currentFaction.id == self.record.id
            local hover = self.openButton and self.openButton:isMouseOver()
            local dragging = self.owner.factionDrag and self.owner.factionDrag.active
                and self.owner.factionDrag.factionId == self.record.id
            local dropId = self.owner.factionDrag and self.owner.factionDrag.active
                and factionOrderDropTarget(self.owner) or nil
            local drop = dropId == self.record.id
            local bg = selected and ROSE_DARK
                or (hover and { r = 0.065, g = 0.071, b = 0.074, a = 0.99 } or CARD_BG)
            self:drawRect(0, 0, self.width, self.height, dragging and 0.52 or bg.a,
                bg.r, bg.g, bg.b)
            self:drawRectBorder(0, 0, self.width, self.height, selected and 1 or 0.72,
                (selected or drop) and ROSE.r or 0.25,
                (selected or drop) and ROSE.g or 0.26,
                (selected or drop) and ROSE.b or 0.29)
            self:drawRect(px(8), px(7), px(52), self.height - px(14), 0.75, 0.015, 0.018, 0.023)
            self:drawRectBorder(px(8), px(7), px(52), self.height - px(14), 0.7, 0.23, 0.24, 0.27)
            if not self.portrait then
                self:drawRect(px(25), px(15), px(18), px(18), 0.75, 0.43, 0.44, 0.47)
                self:drawRect(px(17), px(34), px(34), px(19), 0.75, 0.38, 0.39, 0.42)
            end
            local factionName = safeText(self.record.general and self.record.general.name)
            self:drawText(fitText(factionName, UIFont.Medium, self.width - px(166)),
                px(68), px(11), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Medium)
            Creator.drawFactionSeasonBadge(self)
            Creator.drawVisitorBadge(self)
            local count = #(self.profiles or {})
            local summary = safeText(self.record.general and self.record.general.category)
                .. "  -  " .. tostring(count) .. (count == 1 and " preset" or " presets")
            self:drawText(fitText(summary, UIFont.Small, self.width - px(78)),
                px(68), px(38), MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            if dragging then
                self:drawTextRight("MOVING", self.width - px(10), px(8),
                    ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            end
        end
        container:addChild(card)
        window.factionCards[#window.factionCards + 1] = card
        card.portraitWidth = px(50)
        card.profiles = factionProfiles(window, record.id)
        local chosen = card.profiles[1]
        if chosen then
            queuePortrait(window, card, profileFromRecord(chosen), true,
                generation, "faction")
        end
        local factionId = record.id
        addFactionDragButton(window, card, factionId,
            function()
                selectFaction(window, factionId)
                if window.setCompactPane then window.setCompactPane("members") end
            end):bringToTop()
            y = y + px(72)
        end
    end
end

local function memberColumns(width)
    local px = Creator.px
    local portrait = px(52)
    local nameX = portrait + px(16)
    local rest = math.max(px(120), width - nameX - px(10))

    local statusW = math.max(px(66), math.min(px(78), math.floor(rest * 0.14)))
    local weightW = math.max(px(34), math.min(px(48), math.floor(rest * 0.08)))
    local contentW = math.max(px(20), rest - statusW - weightW)
    local nameW = math.floor(contentW * 0.28)
    local behaviorW = math.floor(contentW * 0.22)
    local weaponW = math.floor(contentW * 0.24)
    local variantW = math.floor(contentW * 0.10)
    local ammoW = contentW - nameW - behaviorW - weaponW - variantW
    return portrait, nameX, nameW, behaviorW, weaponW, variantW, ammoW,
        weightW, statusW
end

local function memberOutfitCount(record)
    record = type(record) == "table" and record or {}
    local sets = record.outfits or record.outfitSets
    if type(sets) == "table" then
        local count = 0
        for id in pairs(sets) do
            if not record.outfitEnabled or record.outfitEnabled[id] ~= false then
                count = count + 1
            end
        end
        if count > 0 then return count end
    end

    local widest = 1
    for _, value in pairs(record.clothing or {}) do
        local choices = 0
        for _ in string.gmatch(tostring(value) .. "|", "(.-)|") do
            choices = choices + 1
        end
        if choices - 1 > widest then widest = choices - 1 end
    end
    return math.max(1, widest)
end

local function memberAmmoText(record)
    record = type(record) == "table" and record or {}
    local general = type(record.general) == "table" and record.general or {}
    if general.infiniteAmmo == true then return "INFINITE", "no limit" end
    local weapons = type(record.weapons) == "table" and record.weapons or {}
    local primary = firstPoolChoice(weapons.primary)
    if primary == nil or primary == "none" then return "-", "melee" end
    local magazines = magazineCountFor(record, "primary")
    if magazines <= 0 then return "0 MAGS", "dry" end
    local capacity = itemCapacity(primary)
    return tostring(magazines) .. (magazines == 1 and " MAG" or " MAGS"),
        capacity > 0 and (tostring(capacity) .. " each") or "capacity by weapon"
end

function Creator.memberStatus(record)
    record = type(record) == "table" and record or {}
    local weapons = type(record.weapons) == "table" and record.weapons or {}
    local general = type(record.general) == "table" and record.general or {}
    local primary = firstPoolChoice(weapons.primary)
    local melee = firstPoolChoice(weapons.melee)
    if (primary == nil or primary == "none") and (melee == nil or melee == "none") then
        return "UNARMED", 0.95, 0.62, 0.25
    end
    if primary ~= nil and primary ~= "none"
            and magazineCountFor(record, "primary") <= 0
            and general.infiniteAmmo ~= true then
        return "NO AMMO", 0.95, 0.45, 0.45
    end
    return "ACTIVE", 0.45, 0.85, 0.5
end

function Creator.profileMatchesRosterFilter(record, filter)
    record = type(record) == "table" and record or {}
    local weapons = type(record.weapons) == "table" and record.weapons or {}
    local hasRanged = firstPoolChoice(weapons.primary) ~= nil
    local hasMelee = firstPoolChoice(weapons.melee) ~= nil
    filter = filter or "all"
    return filter == "all"
        or (filter == "ranged" and hasRanged)
        or (filter == "melee" and hasMelee)
        or (filter == "issues" and Creator.memberStatus(record) ~= "ACTIVE")
end

rebuildProfileCards = function(window)
    local container = window.profileCardsArea
    if not container then return end
    discardPortraitScope(window, "profile")
    window.profileCards = clearCardPanels(container, window.profileCards)
    window.profilePortraitGeneration = (window.profilePortraitGeneration or 0) + 1
    local generation = window.profilePortraitGeneration
    window.profileFilteredCount, window.rosterIssueCount = 0, 0
    if not window.catalog or not window.currentFaction then return end
    local query = tostring(window.profileSearch and window.profileSearch:getText() or ""):lower()
    local records = {}
    local filter = window.rosterFilter or "all"
    for _, candidate in ipairs(factionProfiles(window, window.currentFaction.id)) do
        if type(candidate) == "table" then
            local record = candidate
            local general = type(record.general) == "table" and record.general or {}
            local name = safeText(general.name):lower()
            local role = safeText(general.role):lower()
            if Creator.memberStatus(record) ~= "ACTIVE" then
                window.rosterIssueCount = window.rosterIssueCount + 1
            end
            if Creator.profileMatchesRosterFilter(record, filter)
                    and (query == "" or name:find(query, 1, true)
                        or role:find(query, 1, true)) then
                records[#records + 1] = record
            end
        end
    end
    window.profileFilteredCount = #records
    local issuesButton = window.rosterFilterButtons and window.rosterFilterButtons.issues
    if issuesButton then
        issuesButton.fullTitle = "ISSUES  " .. tostring(window.rosterIssueCount)
        issuesButton:setTitle("ISSUES  " .. tostring(window.rosterIssueCount))
    end
    if window.rosterHeader then
        window.rosterHeader:setName("MEMBER PRESETS   " .. tostring(#records))
    end
    if window.rosterFaction then
        window.rosterFaction:setName(string.upper(safeText(window.currentFaction.general.name)))
    end

    local px = Creator.px
    local gap, rowH = px(4), px(58)
    local cardW = container.width
    local capacity = math.max(1, math.floor((container.height + gap) / (rowH + gap)))
    local page, pages, first, last = pageWindow(records, window.profilePageIndex, capacity)
    window.profilePageIndex, window.profilePageCount = page, pages
    setPageControls(window.profilePrev, window.profileNext,
        window.profilePageLabel, page, pages)
    for index = first, last do
        local record = records[index]
        local slot = index - first
        local card = ISPanel:new(0, slot * (rowH + gap), cardW, rowH)
        card:initialise()
        card.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        card.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        card.record, card.owner = record, window
        card.prerender = function(self)
            local selected = self.owner.currentProfile and
                self.owner.currentProfile.id == self.record.id
            local hover = self.openButton and self.openButton:isMouseOver()
            local bg = selected and ROSE_DARK
                or (hover and { r = 0.065, g = 0.071, b = 0.074, a = 0.99 } or CARD_BG)
            self:drawRect(0, 0, self.width, self.height, bg.a, bg.r, bg.g, bg.b)
            self:drawRectBorder(0, 0, self.width, self.height, selected and 1 or 0.72,
                selected and ROSE.r or 0.25, selected and ROSE.g or 0.26,
                selected and ROSE.b or 0.29)
            local portrait, nameX, nameW, behaviorW, weaponW,
                variantW, ammoW, weightW, statusW = memberColumns(self.width)
            self:drawRect(px(6), px(5), portrait, self.height - px(10), 0.78, 0.015, 0.018, 0.023)
            self:drawRectBorder(px(6), px(5), portrait, self.height - px(10), 0.7, 0.23, 0.24, 0.27)

            local general = self.record.general or {}
            local x = nameX
            self:drawText(fitText(safeText(general.name), UIFont.Medium, nameW - px(8)),
                x, px(8), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Medium)
            local role = safeText(general.role)
            if role ~= "" then
                local roleW = math.min(nameW - px(8), getTextManager()
                    :MeasureStringX(UIFont.Small, role) + px(12))
                local tint = Creator.memberTagColor and Creator.memberTagColor(self.owner.currentFaction, role) or ROSE
                self:drawRect(x, px(31), roleW, px(16), 0.35, tint.r, tint.g, tint.b)
                self:drawRectBorder(x, px(31), roleW, px(16), 0.7, tint.r, tint.g, tint.b)
                self:drawText(fitText(role, UIFont.Small, roleW - px(8)), x + px(6), px(32),
                    TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            end

            x = x + nameW
            local behavior = safeText(general.behaviorProfile or "seek_destroy")
            self:drawText(fitText(behavior, UIFont.Small, behaviorW - px(8)), x, px(12),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            local rank = safeText(general.rank)
            if rank ~= "" then
                self:drawText(fitText(rank, UIFont.Small, behaviorW - px(8)), x, px(31),
                    MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            end

            x = x + behaviorW
            local weapons = self.record.weapons or {}
            local weapon = firstPoolChoice(weapons.primary)
            local kind = "Primary"
            if weapon == nil or weapon == "none" then
                weapon, kind = firstPoolChoice(weapons.melee), "Melee"
            end
            self:drawText(fitText(shortItemName(weapon), UIFont.Small, weaponW - px(8)),
                x, px(12), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            self:drawText(kind, x, px(31), MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)

            x = x + weaponW
            self:drawText(tostring(memberOutfitCount(self.record)), x + px(6), px(20),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)

            x = x + variantW
            local ammoText, ammoNote = memberAmmoText(self.record)
            self:drawText(fitText(ammoText, UIFont.Small, ammoW - px(8)), x, px(12),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            self:drawText(fitText(ammoNote, UIFont.Small, ammoW - px(8)), x, px(31),
                MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)

            x = x + ammoW
            self:drawText(tostring(tonumber(general.spawnWeight) or 1), x + px(4), px(20),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)

            x = x + weightW
            local label, sr, sg, sb = Creator.memberStatus(self.record)
            local pillW = math.max(px(44), statusW - px(6))
            self:drawRect(x, px(20), pillW, px(17), 0.22, sr, sg, sb)
            self:drawRectBorder(x, px(20), pillW, px(17), 0.8, sr, sg, sb)
            self:drawText(fitText(label, UIFont.Small, pillW - px(10)), x + px(5), px(20),
                sr, sg, sb, 1, UIFont.Small)
        end
        container:addChild(card)
        window.profileCards[#window.profileCards + 1] = card
        queuePortrait(window, card, profileFromRecord(record), true,
            generation, "profile")
        local profileId = record.id
        local openButton = addCardButton(card, function()
            selectProfile(window, profileId)
            if window.setCompactPane then window.setCompactPane("editor") end
        end)
        openButton.onRightMouseUp = function()
            if Creator.confirmDeleteProfile then
                Creator.confirmDeleteProfile(window, profileId)
            end
            return true
        end
        openButton:bringToTop()
    end
end

function Creator.clearFactionSelection(window)
    closeItemPicker(window)
    closeAppearancePicker(window)
    window.currentFaction, window.currentProfile = nil, nil
    window.factionBaseline, window.profileBaseline = nil, nil
    window.factionDirtyAt, window.profileDirtyAt = nil, nil
    window.pendingFactionSignature, window.pendingProfileSignature = nil, nil
    if window.avatar then window.avatar:setVisible(false) end
    if window.profileHeader then window.profileHeader:setName("NO NPC PRESET") end
    if window.profileBreadcrumb then window.profileBreadcrumb:setName("Select or create a member") end
    if window.profileId then window.profileId:setName("ID: -") end
    if window.profilePages then setProfilePage(window, window.profilePage or "identity") end
end

refreshFactions = function(window, wanted)
    reloadCatalog(window)
    if not window.catalog then return end

    if window.currentFaction and not window.catalog.factions[window.currentFaction.id] then
        Creator.clearFactionSelection(window)
    end
    if wanted and not window.catalog.factions[wanted] then wanted = nil end
    rebuildFactionCards(window)
    if wanted then
        selectFaction(window, wanted)
    elseif not window.currentFaction then
        local first = window.catalog.factionOrder and window.catalog.factionOrder[1]
        if first then selectFaction(window, first.id) end
    end
    if not window.currentFaction then
        rebuildProfileCards(window)
        if window.factionEditor then Creator.setRootPage(window, "workbench") end
    end
end

refreshRoster = function(window, wanted)
    if not window.catalog or not window.currentFaction then return end
    rebuildProfileCards(window)
    local firstId = nil
    for _, record in ipairs(factionProfiles(window, window.currentFaction.id)) do
        if not firstId then firstId = record.id end
        if wanted and record.id == wanted then firstId = wanted break end
    end
    if firstId then
        selectProfile(window, firstId)
    else
        closeItemPicker(window)
        closeAppearancePicker(window)
        window.currentProfile = nil
        if window.avatar then window.avatar:setVisible(false) end
        if window.profileHeader then window.profileHeader:setName("NO NPC PRESET") end
        if window.profileBreadcrumb then window.profileBreadcrumb:setName("Select or create a member") end
        if window.profileId then window.profileId:setName("ID: -") end
        if window.profilePages then setProfilePage(window, window.profilePage or "identity") end
    end
end

selectFaction = function(window, id)
    if not window.catalog then return end
    if not Creator.flushLeave(window) then return false end
    local record = window.catalog.factions[id]
    if not record then return end
    window.currentFaction = factionFromRecord(record)
    window.currentFactionCustom = ProjectALife.CustomFactions.get(id) ~= nil
    window.currentProfile = nil
    window.profilePageIndex = 1
    if window.avatar then window.avatar:setVisible(false) end
    fillFaction(window)
    Creator.syncFactionWardrobe(window)
    window.factionBaseline = signature(harvestFaction(window))
    window.factionDirtyAt, window.pendingFactionSignature = nil, nil
    refreshRoster(window)
    return true
end

selectProfile = function(window, id)
    if not window.catalog then return end
    if not Creator.flushLeave(window) then return false end
    local record = window.catalog.npcs[id]
    if not record then return end
    window.currentProfile = profileFromRecord(record)
    window.currentProfileCustom = ProjectALife.CustomProfiles.get(id) ~= nil
    fillProfile(window)
    if window.profilePages then setProfilePage(window, window.profilePage or "identity") end
    window.profileBaseline = signature(harvestProfile(window))
    window.profileDirtyAt, window.pendingProfileSignature = nil, nil
    return true
end
Creator.selectFaction, Creator.selectProfile = selectFaction, selectProfile

function Creator.stepMember(window, direction)
    if not window.currentFaction then return false end
    local records = factionProfiles(window, window.currentFaction.id)
    if #records == 0 then return false end
    local current = 1
    for index, record in ipairs(records) do
        if window.currentProfile and record.id == window.currentProfile.id then current = index; break end
    end

    local index = current + (tonumber(direction) and direction < 0 and -1 or 1)
    if index < 1 then index = #records elseif index > #records then index = 1 end
    return selectProfile(window, records[index].id)
end

function Creator.entryNumber(entry, whole)
    if not entry then return nil end
    local value = tonumber(entry:getText())
    if value == nil or value ~= value then return nil end
    return whole and math.floor(value) or value
end

function Creator.checkNumberRule(window, rule)
    local values = {}
    for index, key in ipairs({ rule.low, rule.high }) do
        local entry = window[key]
        if not entry then return nil end
        local text = entry:getText() or ""
        if text:match("^%s*$") then
            if not rule.blankOk then return "enter a value." end
            values[index] = false
        else
            local value = tonumber(text)
            if value == nil or value ~= value or (rule.whole and value ~= math.floor(value))
                    or value < rule.floor or (rule.ceiling and value > rule.ceiling) then
                local span = rule.ceiling and (tostring(rule.floor) .. " to " .. tostring(rule.ceiling))
                    or ("from " .. tostring(rule.floor))
                return "use " .. (rule.whole and "whole numbers " or "") .. span .. "."
            end
            values[index] = value
        end
    end
    if values[1] and values[2] and values[2] < values[1] then
        return "maximum must be at least the minimum."
    end
    return nil
end

function Creator.validateFactionFields(window)
    if not window.currentFaction then return nil end
    local party = ProjectALife.PartyPolicy
    local bounds = party.bounds
    local rules = {
        { label = "Game day", low = "factionDayStart", high = "factionDayEnd",
            floor = 0, whole = true, blankOk = true },
        { label = "Lone size", low = "factionLoneMin", high = "factionLoneMax",
            floor = 1, ceiling = bounds.loneCeiling, whole = true },
        { label = "Group size", low = "factionGroupMin", high = "factionGroupMax",
            floor = party.groupFloor(), ceiling = party.groupCeiling(), whole = true },
        { label = "Support size", low = "factionSupportSize", floor = 1, ceiling = 8, whole = true },
        { label = "Support calls", low = "factionSupportCalls", floor = 0, ceiling = 10, whole = true },
        { label = "Spawn weight", low = "factionChance", floor = 0, ceiling = bounds.weightCeiling },
        { label = "Lone weight", low = "factionLoneWeight", floor = 0,
            ceiling = bounds.splitWeightCeiling, blankOk = true },
        { label = "Group weight", low = "factionPartyGroupWeight", floor = 0,
            ceiling = bounds.splitWeightCeiling, blankOk = true },
    }
    for _, rule in ipairs(rules) do
        local problem = Creator.checkNumberRule(window, rule)
        if problem then return rule.label .. ": " .. problem end
    end
    return nil
end

saveFaction = function(window)
    if Creator.seasonalJob then return false end
    local invalid = Creator.validateFactionFields(window)
    if invalid then
        Creator.paintSaveStatus(window.factionSaveStateLabel, invalid, "error")
        return false
    end
    local faction = harvestFaction(window)
    if not faction then return true end
    local updates = { faction }
    local saved, sent = ProjectALife.CustomFactions.saveMany(deepCopy(updates))
    if saved then
        window.currentFactionCustom = true
        if window.catalog then
            for _, update in ipairs(updates) do
                window.catalog.factions[update.id] = update
                for index, record in ipairs(window.catalog.factionOrder or {}) do
                    if record.id == update.id then
                        window.catalog.factionOrder[index] = update
                        break
                    end
                end
            end
        end
        for _, card in ipairs(window.factionCards or {}) do
            if card.record and card.record.id == faction.id then card.record = faction end
        end
        window.factionBaseline = signature(faction)
        window.factionDirtyAt, window.pendingFactionSignature = nil, nil
        if window.factionId then
            window.factionId:setName("ID: " .. faction.id .. "  /  CUSTOM")
        end
        Creator.paintSaveStatus(window.saveStateLabel, "SAVED", "saved")
        Creator.paintSaveStatus(window.factionSaveStateLabel, "SAVED", "saved")
        window.saveError = nil
        return true
    end
    window.saveError = "Could not save faction. Your edits are still open."
    if (sent or 0) > 0 then window.saveError = "Save incomplete. Some edits were sent; checking server." end
    Creator.paintSaveStatus(window.factionSaveStateLabel, window.saveError, "error")
    return false
end

local function cloneFaction(window)
    if not window.currentFaction then return end
    if not Creator.flushEdits(window) then return false end
    harvestFaction(window)
    local sourceId = window.currentFaction.id
    local copy = deepCopy(window.currentFaction)
    copy.id = uniqueId("custom_faction")
    copy.general.name = safeText(copy.general.name) .. " (Copy)"
    if not ProjectALife.CustomFactions.save(copy) then
        if window.statusLabel then window.statusLabel:setName("COPY FAILED - COULD NOT SAVE FACTION") end
        return false
    end
    local profiles = {}
    if window.catalog then
        for _, record in ipairs(window.catalog.npcOrder or {}) do
            if record.general and record.general.faction == sourceId then
                local profile = profileFromRecord(record)
                profile.id = uniqueId("custom_npc")
                profile.general.faction = copy.id
                profiles[#profiles + 1] = profile
            end
        end
    end
    if not ProjectALife.CustomProfiles.saveMany(profiles) then
        refreshFactions(window, copy.id)
        if window.statusLabel then window.statusLabel:setName("COPY PARTIAL - FACTION ADDED, NPC SAVE FAILED") end
        return false
    end
    refreshFactions(window, copy.id)
end

local function newFaction(window)
    if not Creator.flushEdits(window) then return false end

    local existing
    for _, candidate in ipairs(ProjectALife.CustomFactions.factions or {}) do
        if candidate.general and candidate.general.name == "New Faction"
                and candidate.general.deleted ~= true
                and #factionProfiles(window, candidate.id) == 0 then
            existing = candidate
            break
        end
    end
    local faction = existing or ProjectALife.CustomFactions.blank(uniqueId("custom_faction"))
    if existing == nil and not ProjectALife.CustomFactions.save(faction) then
        if window.statusLabel then window.statusLabel:setName("NEW FACTION FAILED - COULD NOT SAVE") end
        return false
    end
    refreshFactions(window, faction.id)
    if window.factionEditor then
        Creator.setRootPage(window, "faction")
    end
end

local function deleteFaction(window, id)
    id = id or (window.currentFaction and window.currentFaction.id)
    if not id or not window.catalog or not window.catalog.factions[id] then return false end

    if window.currentFaction and window.currentFaction.id ~= id
            and not Creator.flushEdits(window) then return false end
    if not ProjectALife.CustomFactions.delete(id) then
        if window.statusLabel then window.statusLabel:setName("FACTION DELETE FAILED - COULD NOT SAVE") end
        return false
    end

    ProjectALife.CreatorFolders.removeFromOrder(id)
    Creator.clearFactionSelection(window)
    if window.factionEditor then Creator.setRootPage(window, "workbench") end
    refreshFactions(window)
    if window.statusLabel then window.statusLabel:setName("FACTION AND ITS NPC PRESETS REMOVED") end
    return true
end

Creator.factionPackFile = "alife_faction_code.txt"
Creator.safeClipboardPackBytes = 32000

function Creator.writeFactionPackFile(text)
    if type(getFileWriter) ~= "function" then return false end
    local ok, written = pcall(function()
        local writer = getFileWriter(Creator.factionPackFile, true, false)
        if writer == nil then return false end
        for line in string.gmatch(text .. "\n", "(.-)\n") do
            writer:write(line)
            writer:write("\n")
        end
        writer:close()
        return true
    end)
    return ok and written == true
end

function Creator.readFactionPackFile()
    if type(getFileReader) ~= "function" then return nil end
    local ok, text = pcall(function()

        local reader = getFileReader(Creator.factionPackFile, false)
        if reader == nil then return nil end
        local lines, line = {}, reader:readLine()
        while line ~= nil do
            lines[#lines + 1] = line
            line = reader:readLine()
        end
        reader:close()
        return table.concat(lines, "\n")
    end)
    return ok and text or nil
end

function Creator.exportFactionPack(window)
    if not window or not window.currentFaction then
        if window and window.statusLabel then window.statusLabel:setName("SELECT A FACTION TO EXPORT") end
        return false
    end
    if not Creator.flushEdits(window) then return false end
    local faction = harvestFaction(window) or window.currentFaction
    local profiles = {}
    for _, record in ipairs(factionProfiles(window, faction.id)) do
        profiles[#profiles + 1] = profileFromRecord(record)
    end
    local text, reason = ProjectALife.FactionShare.encode(faction, profiles)
    if text == nil then
        if window.statusLabel then window.statusLabel:setName("EXPORT FAILED: " .. string.upper(tostring(reason))) end
        return false
    end
    local code, codeReason = ProjectALife.FactionShare.toCode(text)
    if code == nil then
        if window.statusLabel then window.statusLabel:setName("EXPORT FAILED: " .. string.upper(tostring(codeReason))) end
        return false
    end

    local copied = false
    if #code <= Creator.safeClipboardPackBytes and Clipboard ~= nil
            and type(Clipboard.setClipboard) == "function" then

        copied = pcall(Clipboard.setClipboard, code)
    end
    local saved = Creator.writeFactionPackFile(code)
    if window.statusLabel then
        local status
        if copied then
            status = "CODE COPIED - " .. tostring(#profiles) .. " NPCS - "
                .. tostring(math.ceil(#code / 1000)) .. " KB - PASTE IT ON DISCORD"
        elseif saved then
            status = "TOO LONG TO COPY - CODE SAVED TO ZOMBOID/LUA/ALIFE_FACTION_CODE.TXT"
        else
            status = "EXPORT FAILED: CODE COULD NOT BE COPIED OR SAVED"
        end
        window.statusLabel:setName(status)
    end
    return copied or saved
end

Creator.folderCodeHeader = "PALFOLDER1"

Creator.folderCodePatterns = { "ALIFEPACK1%-[%w%+/%-]+", "PALF2%-[%w%+/%-]+" }

function Creator.exportFolderCode(window, folderId)
    local folders = ProjectALife.CreatorFolders
    local folder = folders ~= nil and folders.get(folderId) or nil
    if folder == nil or not window or not window.catalog then return false end
    if not Creator.flushEdits(window) then return false end
    local title = string.gsub(tostring(folder.name or "Folder"), "[\r\n]", " ")
    local lines = { Creator.folderCodeHeader .. " " .. title }
    local factions, npcs = 0, 0
    for _, faction in ipairs(window.catalog.factionOrder or {}) do
        if type(faction) == "table" and folder.factions[faction.id] == true then
            local profiles = {}
            for _, record in ipairs(factionProfiles(window, faction.id)) do
                profiles[#profiles + 1] = profileFromRecord(record)
            end
            local text = ProjectALife.FactionShare.encode(faction, profiles)
            local code = text ~= nil and ProjectALife.FactionShare.toCode(text) or nil
            if code ~= nil then
                lines[#lines + 1] = code
                factions, npcs = factions + 1, npcs + #profiles
            end
        end
    end
    if factions == 0 then
        if window.statusLabel then window.statusLabel:setName("SHARE FAILED - THE FOLDER HAS NO FACTIONS") end
        return false
    end
    local code = table.concat(lines, "\n")
    local copied = false
    if #code <= Creator.safeClipboardPackBytes and Clipboard ~= nil
            and type(Clipboard.setClipboard) == "function" then
        copied = pcall(Clipboard.setClipboard, code)
    end
    local saved = Creator.writeFactionPackFile(code)
    if window.statusLabel then
        if copied then
            window.statusLabel:setName("FOLDER CODE COPIED - FACTIONS: " .. tostring(factions)
                .. ", NPCS: " .. tostring(npcs) .. " - PASTE IT ON DISCORD")
        elseif saved then
            window.statusLabel:setName("TOO LONG TO COPY - FOLDER CODE SAVED TO ZOMBOID/LUA/ALIFE_FACTION_CODE.TXT")
        else
            window.statusLabel:setName("SHARE FAILED: CODE COULD NOT BE COPIED OR SAVED")
        end
    end
    return copied or saved
end

function Creator.importFactionPack(window)
    local source = nil
    if Clipboard ~= nil and type(Clipboard.getClipboard) == "function" then
        local ok, value = pcall(Clipboard.getClipboard)

        if ok and type(value) == "string" and (string.find(value, "ALIFEPACK1-", 1, true)
                or string.find(value, "@alife-pack", 1, true)
                or string.find(value, "PALF2-", 1, true)
                or string.find(value, "PALF1", 1, true)) then
            source = value
        end
    end
    if source == nil then source = Creator.readFactionPackFile() end
    if source == nil or source == "" then
        if window and window.statusLabel then
            window.statusLabel:setName("NO CODE COPIED  -  COPY A SHARE CODE FIRST")
        end
        return false
    end
    if string.find(source, Creator.folderCodeHeader, 1, true) ~= nil then
        return Creator.importFolderCode(window, source)
    end
    local pack, reason = ProjectALife.FactionShare.decode(source)
    if pack == nil then
        if window and window.statusLabel then
            window.statusLabel:setName("IMPORT FAILED: " .. string.upper(tostring(reason)))
        end
        return false
    end

    local report = ProjectALife.FactionShare.missingFor(pack)
    if report == nil then return Creator.commitFactionImport(window, pack, nil) end
    for _, mod in ipairs(report.mods) do
        print("[ALIFE-SHARE] missing mod " .. tostring(mod.id) .. " (" .. tostring(mod.name)
            .. ", workshop " .. tostring(mod.workshop) .. "): " .. table.concat(mod.items, ", "))
    end
    if #report.items > 0 then
        print("[ALIFE-SHARE] unknown items: " .. table.concat(report.items, ", "))
    end
    local modal = ISModalDialog:new(0, 0, Creator.px(440), Creator.px(150),
        ProjectALife.FactionShare.describeMissing(report), true,
        { window = window, pack = pack, report = report },
        function(subject, button)
            if button.internal ~= "YES" then
                if subject.window and subject.window.statusLabel then
                    subject.window.statusLabel:setName("IMPORT CANCELLED")
                end
                return
            end
            Creator.commitFactionImport(subject.window, subject.pack, subject.report)
        end, nil)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    if window and window.statusLabel then
        window.statusLabel:setName("MISSING ITEMS - " .. tostring(report.count) .. " - FULL LIST IN CONSOLE.TXT")
    end
    return true
end

function Creator.commitFactionImport(window, pack, report)
    if not Creator.flushEdits(window) then return false end
    local faction, profiles = ProjectALife.FactionShare.adoptAsNew(pack, uniqueId)
    if faction == nil then
        if window and window.statusLabel then
            window.statusLabel:setName("IMPORT FAILED: " .. string.upper(tostring(profiles)))
        end
        return false
    end
    if not ProjectALife.CustomFactions.save(faction) then
        if window.statusLabel then window.statusLabel:setName("IMPORT FAILED: FACTION COULD NOT BE SAVED") end
        return false
    end
    if #profiles > 0 and not ProjectALife.CustomProfiles.saveMany(profiles) then
        refreshFactions(window, faction.id)
        if window.statusLabel then window.statusLabel:setName("IMPORT PARTIAL: FACTION ADDED, NPCS FAILED") end
        return false
    end
    reloadCatalog(window)
    refreshFactions(window, faction.id)
    if window.statusLabel then
        window.statusLabel:setName("FACTION PACK IMPORTED - " .. tostring(#profiles) .. " NPCS"
            .. (report ~= nil and (" - " .. tostring(report.count) .. " ITEMS MISSING") or ""))
    end
    return true
end

function Creator.importFolderCode(window, source)
    if not Creator.flushEdits(window) then return false end
    local folders = ProjectALife.CreatorFolders
    local name = string.match(source, Creator.folderCodeHeader .. " ([^\r\n]*)") or "Imported folder"
    local folder = folders ~= nil and folders.create(name) or nil
    if not Creator.folderSaved(window, folder) then return false end
    local factions, npcs, failed = 0, 0, 0
    for _, pattern in ipairs(Creator.folderCodePatterns) do
        for code in string.gmatch(source, pattern) do
            local pack = ProjectALife.FactionShare.decode(code)
            local faction, profiles = nil, nil
            if pack ~= nil then faction, profiles = ProjectALife.FactionShare.adoptAsNew(pack, uniqueId) end
            if faction ~= nil and type(profiles) == "table" and ProjectALife.CustomFactions.save(faction) then
                factions = factions + 1
                if #profiles == 0 or ProjectALife.CustomProfiles.saveMany(profiles) then
                    npcs = npcs + #profiles
                else
                    failed = failed + 1
                end
                if not folders.assign(faction.id, folder.id) then failed = failed + 1 end
            else
                failed = failed + 1
            end
        end
    end
    reloadCatalog(window)
    refreshFactions(window)
    if window and window.statusLabel then
        window.statusLabel:setName("FOLDER IMPORTED - FACTIONS: " .. tostring(factions)
            .. ", NPCS: " .. tostring(npcs) .. (failed > 0 and (" - " .. tostring(failed) .. " FAILED") or ""))
    end
    return factions > 0 and failed == 0
end

function Creator.deleteFolderWithFactions(window, folderId)
    local folders = ProjectALife.CreatorFolders
    local folder = folders ~= nil and folders.get(folderId) or nil
    if folder == nil then return false end
    if not Creator.flushEdits(window) then return false end
    local ids = {}
    for id, included in pairs(folder.factions or {}) do
        if included == true then ids[#ids + 1] = id end
    end
    local removed, failed = 0, 0
    for _, id in ipairs(ids) do
        if ProjectALife.CustomFactions.delete(id) then
            folders.removeFromOrder(id)
            removed = removed + 1
        else
            failed = failed + 1
        end
    end

    local gone = failed == 0 and folders.delete(folderId) == true
    Creator.clearFactionSelection(window)
    if window.factionEditor then Creator.setRootPage(window, "workbench") end
    window.factionPage = 1
    refreshFactions(window)
    if window.statusLabel then
        if gone then
            window.statusLabel:setName("FOLDER DELETED - FACTIONS DELETED: " .. tostring(removed))
        else
            window.statusLabel:setName("FOLDER DELETE FAILED - COULD NOT SAVE ("
                .. tostring(removed) .. " OF " .. tostring(#ids) .. " FACTIONS DELETED)")
        end
    end
    return gone
end

function Creator.refreshFactionFace(window, profile)
    local faction = window.currentFaction
    if not faction then return false end
    for _, card in ipairs(window.factionCards or {}) do
        if card.record and card.record.id == faction.id then
            card.profiles = factionProfiles(window, faction.id)
            if card.portrait then
                card.portrait:setVisible(false)
                pcall(function() card:removeChild(card.portrait) end)
                card.portrait = nil
            end
            queuePortrait(window, card, profile, true, window.factionPortraitGeneration or 0, "faction")
            return true
        end
    end
    return false
end

function Creator.profileSaveClock()
    if type(getTimestampMs) ~= "function" then return nil end
    return tonumber(getTimestampMs())
end

function Creator.measureProfileSave(window, phase, startedAt, result)
    local finishedAt = Creator.profileSaveClock()
    if startedAt == nil or finishedAt == nil then return end
    local elapsed = math.max(0, finishedAt - startedAt)
    local perf = window.profileSavePerf
    if perf == nil then
        perf = { prepareSteps = 0, maxPrepareMs = 0 }
        window.profileSavePerf = perf
    end
    if phase == "prepare" then
        perf.prepareSteps = perf.prepareSteps + 1
        perf.maxPrepareMs = math.max(perf.maxPrepareMs, elapsed)
    else
        perf.commitMs, perf.result = elapsed, result == true
        if type(print) == "function" then
            print("[ALIFE-PERF] creator_save prep_steps=" .. tostring(perf.prepareSteps)
                .. " max_prep_update_ms=" .. tostring(perf.maxPrepareMs)
                .. " sync_commit_ms=" .. tostring(elapsed) .. " ok=" .. tostring(perf.result))
        end
    end
end

function Creator.applyProfileRecord(window, profile)
    local portraitChanged = profileVisualSignature(profile) ~= window.profilePortraitBaseline
    window.currentProfileCustom = true
    if window.catalog then
        window.catalog.npcs[profile.id] = profile
        for index, record in ipairs(window.catalog.npcOrder or {}) do
            if record.id == profile.id then
                window.catalog.npcOrder[index] = profile
                window.rosterRevision = (window.rosterRevision or 0) + 1
                break
            end
        end
    end
    for _, card in ipairs(window.profileCards or {}) do
        if card.record and card.record.id == profile.id then
            card.record = profile
            if portraitChanged and card.portrait then
                card.portrait:setVisible(false)
                pcall(function() card:removeChild(card.portrait) end)
                card.portrait = nil
            end
            if portraitChanged then
                queuePortrait(window, card, profile, true,
                    window.profilePortraitGeneration or 0, "profile")
            end
            break
        end
    end

    if portraitChanged then
        local roster = factionProfiles(window, window.currentFaction.id)
        if roster[1] ~= nil and roster[1].id == profile.id then
            Creator.refreshFactionFace(window, profile)
        end
    end
    window.profilePortraitBaseline = profileVisualSignature(profile)
    window.profileBaseline = signature(profile)
    window.profileDirtyAt, window.pendingProfileSignature = nil, nil
    window.profilePreparationRequired = nil
    if window.profileId then
        window.profileId:setName(fitText("ID: " .. profile.id .. " / Custom", UIFont.Small,
            window.profilePane and window.profilePane.width - (window.compactWorkbench and 194 or 96) or 400))
    end
end

saveProfile = function(window)
    local profile = harvestProfile(window)
    if not profile or not window.currentFaction then return true end

    profile.general.faction = window.currentFaction.id
    local persisted
    local startedAt = Creator.profileSaveClock()
    if window.profileCommitPreparation then
        persisted = ProjectALife.CustomProfiles.savePrepared(profile, window.profileCommitPreparation)
    else
        persisted = ProjectALife.CustomProfiles.save(deepCopy(profile))
    end
    Creator.measureProfileSave(window, "commit", startedAt, persisted == true)
    if persisted then
        Creator.applyProfileRecord(window, profile)
        Creator.paintSaveStatus(window.saveStateLabel, "SAVED", "saved")
        Creator.paintSaveStatus(window.factionSaveStateLabel, "SAVED", "saved")
        window.saveError = nil
        return true
    end
    window.saveError = "Could not save NPC. Your edits are still open."
    Creator.paintSaveStatus(window.saveStateLabel, window.saveError, "error")
    return false
end

function Creator.beginProfileSave(window)
    if window.profileSavePreparation then return false end
    if type(isClient) == "function" and isClient() then return saveProfile(window) end
    local startedAt = Creator.profileSaveClock()
    local profile = harvestProfile(window)
    if not profile or not window.currentFaction then return true end
    profile.general.faction = window.currentFaction.id
    local handle = ProjectALife.CustomProfiles.prepareSave(profile)
    if handle == nil then
        window.saveError = "Could not save NPC. Your edits are still open."
        return false
    end
    window.profileSavePreparation = handle
    window.profileSaveCheckedAt = nil
    window.profileSavePerf = nil
    Creator.measureProfileSave(window, "prepare", startedAt)
    window.profileSaveRetryNotice = nil
    window.saveError = window.saveError ~= "Could not save NPC. Your edits are still open." and window.saveError or nil
    window.profilePreparationRequired = true
    window.profilePreparationSignature = signature(harvestProfile(window))
    Creator.paintSaveStatus(window.saveStateLabel, "SAVING", "dirty")
    return false
end

function Creator.clearSavedProfilePreparation(window)
    if not window.currentProfile or not window.profileBaseline
            or signature(harvestProfile(window)) ~= window.profileBaseline then return false end
    if window.profileSavePreparation then ProjectALife.CustomProfiles.cancelPrepared(window.profileSavePreparation) end
    window.profileSavePreparation, window.profilePreparationSignature, window.profilePreparationRequired = nil, nil, nil
    window.pendingProfileSignature, window.profileDirtyAt = nil, nil
    window.profileSaveCheckedAt = nil
    window.profileSaveRetryNotice = nil
    if window.saveError == "Could not save NPC. Your edits are still open." then window.saveError = nil end
    return true
end

function Creator.verifyPreparation(window)
    Creator.clearSavedProfilePreparation(window)
    local handle = window.profileSavePreparation
    if handle == nil then return false end
    if signature(harvestProfile(window)) ~= window.profilePreparationSignature
            or not ProjectALife.CustomProfiles.preparationCurrent(handle) then
        ProjectALife.CustomProfiles.cancelPrepared(handle)
        window.profileSavePreparation, window.profilePreparationSignature = nil, nil
        window.profileSaveCheckedAt = nil
        if signature(harvestProfile(window)) == window.profileBaseline then window.profilePreparationRequired = nil end
        return false
    end
    return true
end

function Creator.commitPreparedProfile(window, handle, ok, startedAt)
    if ok then
        window.profileCommitPreparation = handle
        saveProfile(window)
        window.profileCommitPreparation = nil
    else
        Creator.measureProfileSave(window, "commit", startedAt, false)
        window.saveError = "Could not save NPC. Your edits are still open."
        Creator.paintSaveStatus(window.saveStateLabel, window.saveError, "error")
    end
    ProjectALife.CustomProfiles.cancelPrepared(handle)
    window.profileSavePreparation, window.profilePreparationSignature = nil, nil
    window.profileSaveCheckedAt = nil
    window.profileSaveRetryNotice = nil
end

function Creator.stepProfileSave(window)
    local startedAt = Creator.profileSaveClock()
    local handle = window.profileSavePreparation
    if handle == nil then
        Creator.clearSavedProfilePreparation(window)
        return
    end
    local checked = window.profileSaveCheckedAt
    local recent = startedAt ~= nil and checked ~= nil and startedAt >= checked and startedAt - checked < 250
    if not recent then
        if not Creator.verifyPreparation(window) then return end
        window.profileSaveCheckedAt = startedAt or 0
        handle = window.profileSavePreparation
    elseif not ProjectALife.CustomProfiles.preparationCurrent(handle) then
        if not Creator.verifyPreparation(window) then return end
    end
    local ok, ready = ProjectALife.CustomProfiles.stepPrepared(handle)
    local steps = 1
    while ok and not ready and steps < 48 do
        local now = Creator.profileSaveClock()
        if now == nil or startedAt == nil or now - startedAt >= 5 then break end
        ok, ready = ProjectALife.CustomProfiles.stepPrepared(handle)
        steps = steps + 1
    end
    Creator.measureProfileSave(window, "prepare", startedAt)
    if ok and not ready then return end
    if ok and recent and not Creator.verifyPreparation(window) then return end
    Creator.commitPreparedProfile(window, handle, ok, startedAt)
end

function Creator.finishProfileSave(window)
    if window.profileSavePreparation == nil then return true end
    window.profileSaveCheckedAt = nil
    if not Creator.verifyPreparation(window) then return window.profileSavePreparation == nil end
    local handle = window.profileSavePreparation
    local startedAt = Creator.profileSaveClock()
    local ok, ready = true, false
    for _ = 1, 200000 do
        ok, ready = ProjectALife.CustomProfiles.stepPrepared(handle)
        if not ok or ready then break end
    end
    Creator.measureProfileSave(window, "prepare", startedAt)
    if ok and not ready then
        ProjectALife.CustomProfiles.cancelPrepared(handle)
        window.profileSavePreparation, window.profilePreparationSignature = nil, nil
        window.profileSaveCheckedAt = nil
        return false
    end
    Creator.commitPreparedProfile(window, handle, ok, startedAt)
    return window.profileSavePreparation == nil
end

function Creator.flushEdits(window)
    Creator.clearSavedProfilePreparation(window)
    if window.profileSavePreparation and window.profileSaveRetryNotice then Creator.finishProfileSave(window) end
    if window.profileSavePreparation then
        window.profileSaveRetryNotice = true
        Creator.paintSaveStatus(window.saveStateLabel, "SAVING - RETRY WHEN SAVED", "dirty")
        return false
    end
    if window.autosaveGuard then return true end
    local invalid = Creator.validateFactionFields(window)
    if invalid then
        Creator.paintSaveStatus(window.factionSaveStateLabel, invalid, "error")
        return false
    end
    if window.currentProfile and window.profileBaseline
            and signature(harvestProfile(window)) ~= window.profileBaseline then
        if not Creator.beginProfileSave(window) then
            if window.profileSavePreparation then
                window.profileSaveRetryNotice = true
                Creator.paintSaveStatus(window.saveStateLabel, "SAVING - RETRY WHEN SAVED", "dirty")
            end
            return false
        end
    end
    if window.currentFaction and window.factionBaseline
            and signature(harvestFaction(window)) ~= window.factionBaseline then
        if not saveFaction(window) then return false end
    end
    return true
end

function Creator.flushLeave(window)
    return Creator.flushEdits(window)
end

function Creator.saveLabel(window, invalidFaction, dirty)
    local failure = invalidFaction or window.saveError
    if failure then return failure, "error" end
    local queue = ProjectALife.CreatorSaveQueue
    if queue ~= nil and queue.busy() then
        if window.profileSaveRetryNotice then return "SAVING - RETRY WHEN SAVED", "saving" end
        return "SAVING", "saving"
    end
    if window.profileSavePreparation and window.profileSaveRetryNotice then
        return "SAVING - RETRY WHEN SAVED", dirty and "dirty" or "saved"
    end
    if dirty then return "UNSAVED  -  AUTOSAVING", "dirty" end
    return "SAVED", "saved"
end

function Creator.menuSubtitle()
    local queue = ProjectALife.CreatorSaveQueue
    if queue ~= nil then
        local text = queue.menuText()
        if text ~= nil then return text end
    end
    return "Factions & NPC settings"
end

function Creator.refreshRosterAndCards(window, wanted)
    rebuildFactionCards(window)
    refreshRoster(window, wanted)
end

local function cloneProfile(window)
    if not window.currentProfile then return end
    if not Creator.flushEdits(window) then return false end
    local profile = deepCopy(harvestProfile(window))
    profile.id = uniqueId("custom_npc")
    profile.general.name = safeText(profile.general.name) .. " (Copy)"
    profile.general.faction = window.currentFaction.id
    if not ProjectALife.CustomProfiles.save(profile) then
        if window.statusLabel then window.statusLabel:setName("NPC COPY FAILED - COULD NOT SAVE") end
        return false
    end
    reloadCatalog(window)
    Creator.refreshRosterAndCards(window, profile.id)
end

local function newProfile(window)
    if not window.currentFaction then return end
    if not Creator.flushEdits(window) then return false end
    local profile = ProjectALife.CustomProfiles.blank(uniqueId("custom_npc"))
    profile.general.faction = window.currentFaction.id

    profile.general.hairColor, profile.general.beardColor = Creator.newAppearanceColors()
    if not ProjectALife.CustomProfiles.save(profile) then
        if window.statusLabel then window.statusLabel:setName("NEW NPC FAILED - COULD NOT SAVE") end
        return false
    end
    reloadCatalog(window)
    Creator.refreshRosterAndCards(window, profile.id)
end

local function deleteProfile(window, id)
    id = id or (window.currentProfile and window.currentProfile.id)
    if not id or not ProjectALife.CustomProfiles.remove(id) then
        if window.statusLabel then window.statusLabel:setName("NPC DELETE FAILED - COULD NOT SAVE") end
        return false
    end
    closeItemPicker(window)
    closeAppearancePicker(window)
    if window.currentProfile and window.currentProfile.id == id then
        window.currentProfile = nil
    end
    reloadCatalog(window)
    Creator.refreshRosterAndCards(window)
    return true
end

local function openDeleteConfirmation(window, kind, id)
    local isProfile = kind == "profile"
    if not id then return false end
    local target = { window = window, id = id, kind = kind }
    local modal = ISModalDialog:new(0, 0, Creator.px(380), Creator.px(150),
        isProfile and "Delete this NPC?" or "Delete this faction and all its NPC presets?",
        true, target, function(subject, button)
            if button.internal ~= "YES" then return end
            if subject.kind == "profile" then
                deleteProfile(subject.window, subject.id)
            else
                deleteFaction(subject.window, subject.id)
            end
        end, nil)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    return true
end

Creator.confirmDeleteProfile = function(window, id)
    return openDeleteConfirmation(window, "profile", id)
end
Creator.confirmDeleteFaction = function(window, id)
    return openDeleteConfirmation(window, "faction", id)
end

function Creator.resetFactions(window)
    local shipped = ProjectALife.Catalog.shipped
    if shipped == nil or type(shipped.factions) ~= "table" then
        if window.statusLabel then window.statusLabel:setName("RESET FAILED - DEFAULT FACTIONS NOT LOADED") end
        return false
    end
    local wanted = window.currentFaction and window.currentFaction.id or nil

    if not Creator.flushEdits(window) then return false end
    local ok = ProjectALife.CustomFactions.resetToShipped(shipped.factions)
    if ok then
        Creator.clearFactionSelection(window)
        refreshFactions(window, wanted)
    end
    if window.statusLabel then
        window.statusLabel:setName(ok and "FACTIONS RESET TO DEFAULT" or "RESET FAILED - COULD NOT SAVE")
    end
    return ok
end

function Creator.confirmResetFactions(window)
    local modal = ISModalDialog:new(0, 0, Creator.px(440), Creator.px(150),
        "Are you sure?\nBuilt-in factions go back to default and deleted ones come back.\nFactions you made yourself stay.",
        true, { window = window }, function(subject, button)
            if button.internal == "YES" then Creator.resetFactions(subject.window) end
        end, nil)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    return true
end

function Creator.syncServer(window)
    if not Creator.flushEdits(window) then return false end
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if type(isClient) == "function" and isClient() and player
            and type(sendClientCommand) == "function" then
        local sent, reason = ProjectALife.CreatorTransfer.send(player, "replace",
            ProjectALife.CustomProfiles.serializeAll(), ProjectALife.CustomFactions.serializeAll())
        if not sent then
            if window.statusLabel then window.statusLabel:setName("SERVER SYNC FAILED: " .. tostring(reason)) end
            return false
        end
        if window.statusLabel then window.statusLabel:setName("SYNCING CREATOR TO SERVER...") end
        return true
    end

    if window.statusLabel then
        window.statusLabel:setName("SAVED LOCALLY -- APPLIES WHEN YOU START OR HOST A WORLD")
    end
    return true
end
local function applyProfileDomainToFaction(window, domain)
    local source = harvestProfile(window)
    if not source or not window.currentFaction or not window.catalog then return end
    local updates = {}
    local generalKeys = {}
    if domain == "appearance" then
        generalKeys = { "female", "skin", "hairStyle", "hairColor",
            "beardStyle", "beardColor" }
    elseif domain == "outfit" then
        generalKeys = {}
    elseif domain == "behavior" then
        generalKeys = { "behaviorProfile", "primaryBehavior", "combatReady" }
    elseif domain == "voice" then
        generalKeys = { "voiceProfile" }
    elseif domain == "stats" then
        generalKeys = { "healthHP", "strength", "endurance", "awareness", "aiming",
            "aimPlayerPercent", "aimZombiePercent",
            "supportCaller", "supportPolicy", "supportType", "supportHeli",
            "damageOutput", "damageReduction", "dropAmmo", "magazineDropMax",
            "magazineDropChance", "dropWeapon", "dropWeaponChance", "dropWeaponPreset",
            "dropWeaponCondition", "dropArmorChance", "armorCondition" }
    elseif domain == "loadout" then
        generalKeys = { "ammoMode", "primaryMagazines", "secondaryMagazines",
            "infiniteAmmo" }
    end
    for _, record in ipairs(factionProfiles(window, window.currentFaction.id)) do

        local target = record.id == source.id and deepCopy(source)
            or profileFromRecord(record)
        for _, key in ipairs(generalKeys) do
            target.general[key] = deepCopy(source.general[key])
        end
        if domain == "appearance" then

        elseif domain == "outfit" then
            target.clothing = deepCopy(source.clothing)
            target.outfits = deepCopy(source.outfits)
            target.outfitTints = deepCopy(source.outfitTints)
            target.outfitEnabled = deepCopy(source.outfitEnabled)
            target.outfitSeason = deepCopy(source.outfitSeason)
        elseif domain == "behavior" then
            target.modules = deepCopy(source.modules)
            target.moduleOverrides = deepCopy(source.moduleOverrides)
        elseif domain == "loadout" then
            target.weapons = deepCopy(source.weapons)
            target.weaponAttachments = deepCopy(source.weaponAttachments)
            target.ammo = deepCopy(source.ammo)
        end
        updates[#updates + 1] = target
    end
    local saved, sent = ProjectALife.CustomProfiles.saveMany(updates)
    if not saved then
        Creator.paintSaveStatus(window.saveStateLabel, (sent or 0) > 0
            and "APPLY INCOMPLETE - CHECKING SERVER" or "APPLY FAILED - EDITS STILL OPEN", "error")
        return false
    end
    for _, profile in ipairs(updates) do
        window.catalog.npcs[profile.id] = profile
        for index, record in ipairs(window.catalog.npcOrder or {}) do
            if record.id == profile.id then
                window.catalog.npcOrder[index] = profile
                window.rosterRevision = (window.rosterRevision or 0) + 1
                break
            end
        end
    end
    window.currentProfileCustom = true
    window.currentProfile = window.catalog.npcs[source.id] or source
    window.autosaveGuard = true
    rebuildProfileCards(window)
    selectProfile(window, source.id)
    window.autosaveGuard = false
    Creator.paintSaveStatus(window.saveStateLabel,
        "APPLIED " .. string.upper(domain) .. " TO ALL MEMBERS", "saved")
end

function Creator.applyModuleGroupToFaction(window, groupId)
    local source = harvestProfile(window)
    if not source or not window.currentFaction or not window.catalog then return end
    local memberIds = {}
    for _, spec in ipairs(MEMBER_MODULES) do
        if spec[3] == groupId then memberIds[#memberIds + 1] = spec[2] end
    end
    if #memberIds == 0 then return end
    local updates = {}
    for _, record in ipairs(factionProfiles(window, window.currentFaction.id)) do
        local target = record.id == source.id and deepCopy(source) or profileFromRecord(record)
        target.modules, target.moduleOverrides = target.modules or {}, target.moduleOverrides or {}
        for _, id in ipairs(memberIds) do
            target.modules[id] = deepCopy(source.modules[id])
            target.moduleOverrides[id] = deepCopy(source.moduleOverrides[id])
        end
        updates[#updates + 1] = target
    end
    local saved, sent = ProjectALife.CustomProfiles.saveMany(updates)
    if not saved then
        Creator.paintSaveStatus(window.saveStateLabel, (sent or 0) > 0
            and "APPLY INCOMPLETE - CHECKING SERVER" or "APPLY FAILED - EDITS STILL OPEN", "error")
        return false
    end
    for _, profile in ipairs(updates) do
        window.catalog.npcs[profile.id] = profile
        for index, record in ipairs(window.catalog.npcOrder or {}) do
            if record.id == profile.id then
                window.catalog.npcOrder[index] = profile
                window.rosterRevision = (window.rosterRevision or 0) + 1
                break
            end
        end
    end
    window.currentProfileCustom = true
    window.currentProfile = window.catalog.npcs[source.id] or source
    window.autosaveGuard = true
    rebuildProfileCards(window)
    selectProfile(window, source.id)
    window.autosaveGuard = false
    Creator.paintSaveStatus(window.saveStateLabel,
        "APPLIED " .. string.upper(groupId) .. " TO ALL MEMBERS", "saved")
end

setProfilePage = function(window, name)
    window.profilePage = name
    local available = window.currentProfile ~= nil
    for id, panel in pairs(window.profilePages) do
        panel:setVisible(available and id == name)
    end
    for id, button in pairs(window.profilePageButtons) do styleButton(button, id == name) end
    for _, button in pairs(window.profilePageButtons) do button:setEnable(available) end
    for _, button in ipairs({ window.duplicateProfileButton, window.deleteProfileButton,
            window.clonePresetButton, window.deletePresetButton,
            window.modelToggleButton }) do
        if button then button:setEnable(available) end
    end
    if window.profileEmptyTitle then window.profileEmptyTitle:setVisible(not available) end
    if window.profileEmptyHint then window.profileEmptyHint:setVisible(not available) end
    if window.emptyNewMemberButton then
        window.emptyNewMemberButton:setVisible(not available)
        window.emptyNewMemberButton:setEnable(window.currentFaction ~= nil)
    end
    if window.avatarPreviewPane then
        window.avatarPreviewPane:setVisible(available and not window.compactWorkbench)
    end
end

local function setRootPage(window, name)
    if not Creator.flushLeave(window) then return false end
    name = name == "faction" and "faction" or "workbench"
    window.rootPage = name
    for id, panel in pairs(window.rootPages or {}) do
        panel:setVisible(id == "workbench" and window.inspectorPaneCollapsed ~= true)
    end
    if window.factionEditor then
        window.factionEditor:setVisible(name == "faction")
        if name == "faction" then window.factionEditor:bringToTop() end
    end
    if window.compactWorkbench then
        window.setCompactPane(window.compactPane or "factions")
    elseif window.factionPane then
        window.factionPane:setVisible(name ~= "faction")
        window.rosterPane:setVisible(name ~= "faction")
        Creator.fitFactionEditor(window, name == "faction")
    end
    for id, button in pairs(window.rootButtons or {}) do styleButton(button, id == name) end
    return true
end
Creator.setRootPage = setRootPage

function Creator.fitFactionEditor(window, open)
    if window.compactWorkbench or not window.applyWorkbenchLayout then return end
    if window.leftPaneDivider then window.leftPaneDivider:setVisible(not open) end
    if window.rightPaneDivider then window.rightPaneDivider:setVisible(not open) end
    local built = window.factionEditorSplit
    if open and built and not window.draggedSplit then
        window.draggedSplit = { window.factionPane.width, window.rosterPane.width, Creator.rosterRatio }
        window.applyWorkbenchLayout(built[1], built[2])
        Creator.rosterRatio = window.draggedSplit[3]
    elseif not open and window.draggedSplit then
        local dragged = window.draggedSplit
        window.draggedSplit = nil
        window.applyWorkbenchLayout(dragged[1], dragged[2])
    end
end

function Creator.addTickOptions(ticks, specs, definitionStyle)
    for _, spec in ipairs(specs or {}) do
        ticks:addOption(definitionStyle and (spec.label or spec.id) or spec[1])
    end
end

function Creator.installPreviewLoadoutHitTargets(window, preview, previewW)

    local compact, px = window.compactWorkbench == true, Creator.px
    local gap, margin = px(4), px(10)
    local slotW = math.floor((previewW - margin * 2 - gap * 2) / 3)
    local stripY = preview.height - (compact and px(116) or px(142))
    local slotH = compact and px(58) or px(82)
    local slots = {
        { "firearm", "primary", window.primaryCombo, "Primary firearm" },
        { "firearm", "secondary", window.secondaryCombo, "Secondary firearm" },
        { "melee", "melee", window.meleeCombo, "Melee weapon" },
    }
    for index, spec in ipairs(slots) do
        local selected = spec
        local hit = ISButton:new(margin + (index - 1) * (slotW + gap), stripY,
            slotW, slotH, "", preview, function()
                harvestProfile(window)
                openItemPicker(window, selected[1], selected[2],
                    selected[3], selected[4])
            end)
        hit:initialise(); hit:instantiate()
        hit.displayBackground = false
        hit.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        hit.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        Creator.installRightClickClear(hit, function()
            return Creator.clearLoadoutSlot(window, selected[2], selected[3])
        end)
        Creator.addTooltip(hit, "Click to edit " .. string.lower(selected[4]) .. ". Right-click to clear.")
        preview:addChild(hit); hit:bringToTop()
    end
end

function Creator.scrollPage(page, height)
    page:setScrollChildren(true); page:addScrollBars()
    page:setScrollHeight(math.max(page.height, height or page.height))
    page.prerender = function(self)
        ISPanel.prerender(self)
        self:setStencilRect(0, 0, self.width, self.height)
    end
    page.render = function(self) self:clearStencilRect() end
    page.onMouseWheel = function(self, delta)
        self:setYScroll(self:getYScroll() - delta * Creator.px(48))
        return true
    end
end

function Creator.buildFactionWorkbench(window, page)
    local px = Creator.px
    local gap = px(8)
    local compact = page.width < px(1100) or page.height < px(430)
    local paneTop = compact and px(34) or 0
    local height = page.height - paneTop

    local settingsW = compact and page.width
        or math.max(px(240), math.floor(page.width * 0.23))
    local rosterW = compact and page.width
        or math.max(px(300), math.floor(page.width * (Creator.rosterRatio or 0.30)))
    if not compact then
        rosterW = math.min(rosterW, page.width - settingsW - gap * 2 - px(520))
    end
    local profileW = compact and page.width
        or page.width - settingsW - rosterW - gap * 2
    local settings = createFramedPanel(page, 0, paneTop, settingsW, height)
    local roster = createFramedPanel(page, compact and 0 or settingsW + gap,
        paneTop, rosterW, height)
    local profile = createFramedPanel(page,
        compact and 0 or settingsW + rosterW + gap * 2, paneTop, profileW, height)
    window.factionPane, window.rosterPane, window.profilePane = settings, roster, profile
    window.compactWorkbench = compact
    window.compactPaneButtons = {}
    window.setCompactPane = function(name)
        if not window.compactWorkbench then return end
        window.compactPane = name
        settings:setVisible(name == "factions")
        roster:setVisible(name == "members")
        profile:setVisible(name == "editor")
        for id, button in pairs(window.compactPaneButtons) do
            styleButton(button, id == name)
        end
    end
    if compact then
        local compactTabs = {
            { "factions", "FACTIONS" }, { "members", "MEMBERS" },
            { "editor", "EDITOR + MODEL" },
        }
        local compactTabW = math.floor((page.width - px(8)) / #compactTabs)
        for index, spec in ipairs(compactTabs) do
            local paneId = spec[1]
            window.compactPaneButtons[paneId] = addButton(page,
                (index - 1) * (compactTabW + px(4)), 0, compactTabW, spec[2],
                function() window.setCompactPane(paneId) end, index == 1)
        end
    end

    addLabel(settings, px(12), px(9), "FACTION LIST", ROSE)
    window.factionSearch = addEntry(settings, px(12), px(35), settingsW - px(126), "")
    window.factionSearch:setPlaceholderText("Search factions...")
    window.newFactionButton = addButton(settings, settingsW - px(106), px(34), px(94), "+ NEW", function()
        newFaction(window)
    end)
    window.factionCardsArea = ISPanel:new(px(12), px(70), settingsW - px(24), height - px(218))
    window.factionCardsArea:initialise()
    window.factionCardsArea.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    window.factionCardsArea.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    settings:addChild(window.factionCardsArea)
    window.factionCards = {}
    window.factionPrev = addButton(settings, px(12), height - px(138), px(30), "<", function()
        window.factionPage = math.max(1, (window.factionPage or 1) - 1)
        rebuildFactionCards(window)
    end)
    window.factionPageLabel = addLabel(settings, px(48), height - px(135), "PAGE 1 / 1", MUTED)

    window.newFactionPlusButton = addButton(settings, settingsW - px(78), height - px(138), px(30), "+", function()
        newFaction(window)
    end, true)
    Creator.addTooltip(window.newFactionPlusButton, "Create a new faction")
    window.factionNext = addButton(settings, settingsW - px(42), height - px(138), px(30), ">", function()
        window.factionPage = math.min(window.factionPageCount or 1,
            (window.factionPage or 1) + 1)
        rebuildFactionCards(window)
    end)
    window.newFolderButton = addButton(settings, px(12), height - px(104),
        math.floor((settingsW - px(28)) / 2), "NEW FOLDER", function()
        openFolderDialog(window)
    end)
    window.newFactionBottomButton = addButton(settings, px(16) + math.floor((settingsW - px(28)) / 2),
        height - px(104), math.floor((settingsW - px(28)) / 2), "+ NEW FACTION", function()
        newFaction(window)
    end, true)
    local factionActionWidth = settingsW - px(24)
    local editFactionWidth = math.floor(factionActionWidth * 0.48)
    local shareFactionWidth = math.floor((factionActionWidth - editFactionWidth - px(8)) / 2)
    window.editFactionButton = addButton(settings, px(12), height - px(66),
        editFactionWidth, "OPEN SETTINGS", function()
        if window.currentFaction then
            setRootPage(window, "faction")
        end
    end, true)
    window.exportFactionButton = addButton(settings, px(16) + editFactionWidth, height - px(66),
        shareFactionWidth, "COPY CODE", function() Creator.exportFactionPack(window) end)
    window.importFactionButton = addButton(settings,
        px(20) + editFactionWidth + shareFactionWidth, height - px(66),
        shareFactionWidth, "LOAD CODE", function() Creator.importFactionPack(window) end)
    Creator.addTooltip(window.exportFactionButton,
        "Copies this faction and all its NPCs as one share code. Paste it on Discord. Also saved to Zomboid/Lua/alife_faction_code.txt as a backup.")
    Creator.addTooltip(window.importFactionButton,
        "Copy a share code, then click: it is added as a new faction. With no code copied, loads Zomboid/Lua/alife_faction_code.txt.")
    local factionButtonW = math.floor((settingsW - px(28)) / 2)
    window.cloneFactionButton = addButton(settings, px(12),
        height - px(34), factionButtonW, "DUPLICATE FACTION",
        function() cloneFaction(window) end)
    window.deleteFactionButton = addButton(settings, px(16) + factionButtonW, height - px(34),
        factionButtonW, "DELETE", function()
            if window.currentFaction then
                Creator.confirmDeleteFaction(window, window.currentFaction.id)
            end
        end)

    window.groupSetup = ISPanel:new(px(12), px(30), rosterW - px(24), px(46))
    window.groupSetup:initialise()
    window.groupSetup.owner = window
    window.groupSetup.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    window.groupSetup.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    window.groupSetup.prerender = function(self)
        self:drawRect(0, 0, self.width, self.height, 0.9,
            CARD_BG.r, CARD_BG.g, CARD_BG.b)
        self:drawRectBorder(0, 0, self.width, self.height, 0.7, 0.25, 0.26, 0.29)
        local faction = self.owner.currentFaction
        if faction == nil then
            self:drawText("Select a faction", px(12), px(14),
                MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            return
        end
        local spawn = faction.spawn or {}
        local third = math.floor(self.width / 3)
        local modules, count = {}, 0
        for id, value in pairs(faction.memberModules or {}) do
            if value == "on" and count < 4 then
                count = count + 1
                modules[count] = id
            end
        end
        local inherited = count > 0 and table.concat(modules, ", ") or "none"
        self:drawText("INHERITED MODULES", px(12), px(6), ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        self:drawText(fitText(inherited, UIFont.Small, third - px(20)), px(12), px(24),
            TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        self:drawText("DEFAULT PROGRAM", third + px(12), px(6),
            ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        self:drawText(fitText(safeText(spawn.programPool or spawn.program or "patrol"),
            UIFont.Small, third - px(20)), third + px(12), px(24),
            TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        self:drawText("NATURAL PARTIES", third * 2 + px(12), px(6),
            ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        local party = ProjectALife.PartyPolicy.config(faction)
        local lone = party.loneMin .. "-" .. party.loneMax
        local description = party.mode == "lone" and ("Lone survivors: " .. lone)
            or (party.mode == "group" and ("Groups: " .. party.groupMin .. "-" .. party.groupMax))
            or ("Lone " .. lone .. " / Groups " .. party.groupMin .. "-" .. party.groupMax)
        self:drawText(fitText(description, UIFont.Small, third - px(20)),
            third * 2 + px(12), px(24), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
    end
    roster:addChild(window.groupSetup)

    window.rosterHeader = addLabel(roster, px(12), px(9), "MEMBER PRESETS   0", ROSE)
    window.rosterFaction = addLabel(roster, rosterW - px(240), px(9), "SELECT A FACTION", MUTED)
    window.profileSearch = addEntry(roster, px(12), px(84), rosterW - px(136), "")
    window.profileSearch:setPlaceholderText("Search members...")

    local newMemberW = math.max(px(104), Creator.textWidth("+ NEW MEMBER", UIFont.Small) + px(22))
    window.newMemberButton = addButton(roster, rosterW - px(12) - newMemberW, px(83), newMemberW, "+ NEW MEMBER",
        function() newProfile(window) end)

    window.rosterFilter = "all"
    window.rosterFilterButtons = {}
    local rosterFilters = {
        { "all", "ALL" }, { "ranged", "RANGED" },
        { "melee", "MELEE" }, { "issues", "ISSUES" },
    }
    local rosterFilterW = math.floor((rosterW - px(33)) / #rosterFilters)
    for index, spec in ipairs(rosterFilters) do
        local filterId = spec[1]
        window.rosterFilterButtons[filterId] = addButton(roster,
            px(12) + (index - 1) * (rosterFilterW + px(3)), px(112),
            rosterFilterW, spec[2], function()
                window.rosterFilter = filterId
                window.profilePageIndex = 1
                for id, button in pairs(window.rosterFilterButtons) do
                    styleButton(button, id == filterId)
                end
                rebuildProfileCards(window)
            end, filterId == "all")
    end

    window.rosterColumns = ISPanel:new(px(12), px(143), rosterW - px(24), px(20))
    window.rosterColumns:initialise()
    window.rosterColumns.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    window.rosterColumns.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    window.rosterColumns.prerender = function(self)
        local portrait, nameX, nameW, behaviorW, weaponW,
            variantW, ammoW, weightW, statusW = memberColumns(self.width)
        local x = nameX

        local function head(label, width)
            self:drawText(fitText(label, UIFont.Small, math.max(8, width - 4)),
                x, px(3), MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            x = x + width
        end
        head("MEMBER", nameW)
        head("BEHAVIOR", behaviorW)
        head("WEAPON", weaponW)
        head("VAR", variantW)
        head("AMMO", ammoW)
        head("WT", weightW)
        head("STATUS", statusW)
        self:drawRect(0, self.height - px(1), self.width, px(1), 0.5, 0.25, 0.26, 0.29)
    end
    roster:addChild(window.rosterColumns)

    window.profileCardsArea = ISPanel:new(px(12), px(167), rosterW - px(24), height - px(247))
    window.profileCardsArea:initialise()
    window.profileCardsArea.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    window.profileCardsArea.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    window.profileCardsArea.prerender = function(self)
        ISPanel.prerender(self)
        if (window.profileFilteredCount or 0) == 0 then
            local message = window.rosterFilter == "issues"
                and "NO LOADOUT ISSUES" or "NO MEMBERS MATCH THIS VIEW"
            self:drawTextCentre(message, self.width / 2,
                math.max(px(24), math.min(px(72), self.height / 3)),
                MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        end
    end
    roster:addChild(window.profileCardsArea)
    window.profileCards = {}
    window.profilePrev = addButton(roster, px(12), height - px(70), px(30), "<", function()
        window.profilePageIndex = math.max(1, (window.profilePageIndex or 1) - 1)
        rebuildProfileCards(window)
    end)
    window.profilePageLabel = addLabel(roster, px(48), height - px(67), "PAGE 1 / 1", MUTED)
    window.profileNext = addButton(roster, rosterW - px(42), height - px(70), px(30), ">", function()
        window.profilePageIndex = math.min(window.profilePageCount or 1,
            (window.profilePageIndex or 1) + 1)
        rebuildProfileCards(window)
    end)
    local function resizeRoster(delta)
        if window.compactWorkbench then
            window.setCompactPane(delta < 0 and "factions" or "editor")
            return
        end
        if window.applyWorkbenchLayout then
            local pixels = math.floor(page.width * delta)
            window.applyWorkbenchLayout(window.factionPane.width,
                window.rosterPane.width + pixels)
        end
    end
    window.rosterNarrowButton = addButton(roster,
        math.floor(rosterW / 2) - px(39), height - px(70), px(34), "<<",
        function() resizeRoster(-0.05) end)
    window.rosterWideButton = addButton(roster,
        math.floor(rosterW / 2) + px(5), height - px(70), px(34), ">>",
        function() resizeRoster(0.05) end)
    local rosterButtonW = math.floor((rosterW - px(28)) / 2)
    window.clonePresetButton = addButton(roster, px(12), height - px(34),
        rosterButtonW, "DUPLICATE NPC",
        function() cloneProfile(window) end)
    window.deletePresetButton = addButton(roster, px(16) + rosterButtonW,
        height - px(34), rosterButtonW, "DELETE",
        function()
            if window.currentProfile then
                Creator.confirmDeleteProfile(window, window.currentProfile.id)
            end
        end)

    window.profileHeader = addLabel(profile, px(12), px(8), "NO NPC PRESET", ROSE, UIFont.Medium)
    window.profileBreadcrumb = addLabel(profile, px(12), px(30), "Faction / NPC Preset", MUTED)
    window.profileId = addLabel(profile, px(12), px(49), "ID: -", MUTED)
    window.profileEmptyTitle = addLabel(profile, px(12), px(122), "NO MEMBER SELECTED", TEXT, UIFont.Medium)
    window.profileEmptyHint = addLabel(profile, px(12), px(150),
        "Choose a preset from the roster, or create a new member for this faction.", MUTED)
    window.emptyNewMemberButton = addButton(profile, px(12), px(180), px(172), "+ NEW MEMBER", function()
        newProfile(window)
    end, true)
    Creator.addTooltip(window.emptyNewMemberButton, "Create a member in the currently selected faction.")
    local memberButtonRight = compact and px(176) or px(78)
    window.previousMemberButton = addButton(profile, profileW - memberButtonRight, px(42), px(30), "<", function()
        Creator.stepMember(window, -1)
    end)
    window.nextMemberButton = addButton(profile, profileW - memberButtonRight + px(34), px(42), px(30), ">", function()
        Creator.stepMember(window, 1)
    end)
    addTooltip(window.previousMemberButton, "Previous member - saves pending edits first.")
    addTooltip(window.nextMemberButton, "Next member - keep faction settings open while previewing the roster.")

    local actionRight = profileW - px(12)
    local deleteW = math.max(px(94), Creator.textWidth("DELETE", UIFont.Small) + px(22))
    local duplicateW = math.max(px(112), Creator.textWidth("DUPLICATE NPC", UIFont.Small) + px(22))
    window.duplicateProfileButton = addButton(profile,
        actionRight - deleteW - px(8) - duplicateW, px(8), duplicateW, "DUPLICATE NPC",
        function() cloneProfile(window) end)
    window.deleteProfileButton = addButton(profile, actionRight - deleteW, px(8), deleteW, "DELETE",
        function()
            if window.currentProfile then
                Creator.confirmDeleteProfile(window, window.currentProfile.id)
            end
        end)
    local tabs = { "identity", "appearance", "faces", "loadout", "combat", "behavior", "modules" }
    window.profilePages, window.profilePageButtons = {}, {}
    local tabW = math.floor((profileW - px(28) - (#tabs - 1) * px(5)) / #tabs)
    for index, name in ipairs(tabs) do
        local pageId = name
        local button = addButton(profile, px(14) + (index - 1) * (tabW + px(5)), px(73),
            tabW, string.upper(pageId), function() setProfilePage(window, pageId) end)
        window.profilePageButtons[pageId] = button
        local sub = ISPanel:new(px(12), px(105), profileW - px(24), height - px(154))
        sub:initialise()
        sub.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        sub.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        profile:addChild(sub)
        window.profilePages[pageId] = sub
    end
    if compact then
        local scrollHeights = {
            identity = 650, appearance = 860, faces = 300, loadout = 650,
            combat = 410, behavior = 430, modules = 780,
        }
        for id, sub in pairs(window.profilePages) do
            sub:setScrollChildren(true)
            sub:addScrollBars()
            sub:setScrollHeight(math.max(sub.height, px(scrollHeights[id] or 440)))
        end
    end
    local previewW = compact and profileW
        or math.max(px(210), math.min(px(340), math.floor(profileW * 0.38)))
    local formW = compact and profileW - px(24)
        or math.max(px(220), profileW - previewW - px(34))
    Creator.buildIdentityPage(window, formW)

    Creator.buildAppearancePage(window, formW)

    Creator.buildFacesPage(window, formW)

    Creator.buildLoadoutPage(window, formW)

    Creator.buildCombatPage(window, formW, compact)

    Creator.buildBehaviorPage(window, formW)

    Creator.buildModulesPage(window, formW)

    local preview = createFramedPanel(profile, compact and 0 or profileW - previewW - px(12),
        compact and 0 or px(105), previewW, compact and height or height - px(154))
    window.avatarPreviewPane = preview
    preview.owner = window
    preview.prerender = function(self)
        ISPanel.prerender(self)
        self:drawTextCentre("LIVE CHARACTER", self.width / 2, px(10),
            ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        self:drawRect(px(14), px(34), self.width - px(28), px(1), 0.55,
            CONTROL_BORDER.r, CONTROL_BORDER.g, CONTROL_BORDER.b)
        self:drawTextCentre("ANIMATION", self.width / 2,
            self.height - (self.owner.compactWorkbench and px(198) or px(232)),
            MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        local entries = self.owner.avatarLoadout or {}
        local gap, margin = px(4), px(10)
        local slotW = math.floor((self.width - margin * 2 - gap * 2) / 3)
        local compactPreview = self.owner.compactWorkbench == true
        local stripY = self.height - (compactPreview and px(116) or px(142))
        local slotH = compactPreview and px(58) or px(82)
        for index = 1, 3 do
            local entry = entries[index] or {}
            local x = margin + (index - 1) * (slotW + gap)
            local active = entry.fullType and entry.fullType ~= "none"
            self:drawRect(x, stripY, slotW, slotH, 0.94,
                active and ROSE_DARK.r or CARD_BG.r,
                active and ROSE_DARK.g or CARD_BG.g,
                active and ROSE_DARK.b or CARD_BG.b)
            self:drawRectBorder(x, stripY, slotW, slotH, 0.82,
                active and ROSE.r or CONTROL_BORDER.r,
                active and ROSE.g or CONTROL_BORDER.g,
                active and ROSE.b or CONTROL_BORDER.b)
            if entry.texture then pcall(function()
                self:drawTextureScaledAspect2(entry.texture, x + px(6), stripY + px(6),
                    slotW - px(12), compactPreview and px(24) or px(42), 1, 1, 1, 1)
            end) end
            local additional = math.max(0, (tonumber(entry.poolCount) or 0) - 1)
            if additional > 0 then
                local badge = "+" .. tostring(additional)
                local badgeW = getTextManager():MeasureStringX(UIFont.Small, badge) + px(12)
                self:drawRect(x + slotW - badgeW - px(5), stripY + px(5),
                    badgeW, px(18), 0.96, ROSE_DARK.r, ROSE_DARK.g, ROSE_DARK.b)
                self:drawRectBorder(x + slotW - badgeW - px(5), stripY + px(5),
                    badgeW, px(18), 0.95, ROSE.r, ROSE.g, ROSE.b)
                self:drawTextCentre(badge, x + slotW - badgeW / 2 - px(5),
                    stripY + px(6), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            end
            local held = (self.owner.previewWeaponSlot or "primary") == entry.slot

            local slotLabel = Creator.previewSlotLabel(held, self.owner.previewWeaponStandIn == true, index, slotW - 8)
            self:drawTextCentre(slotLabel, x + slotW / 2,
                stripY + (compactPreview and px(30) or px(50)),
                active and ROSE.r or MUTED.r, active and ROSE.g or MUTED.g,
                active and ROSE.b or MUTED.b, 1, UIFont.Small)
            self:drawTextCentre(fitText(entry.label or "Empty", UIFont.Small, slotW - px(8)),
                x + slotW / 2, stripY + (compactPreview and px(43) or px(66)),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        end
    end
    window.avatar = ISUI3DModel:new(px(4), px(36), previewW - px(8),
        compact and math.max(px(52), preview.height - px(205))
            or math.max(px(160), preview.height - px(282)))
    window.avatar:initialise()
    window.avatar.prerender = liveAvatarPrerender
    window.avatar:setAnimateWhilePaused(true)
    preview:addChild(window.avatar)
    window.avatarAnimation = addCombo(preview, px(12),
        preview.height - (compact and px(180) or px(210)),
        previewW - px(24), {
            { "Idle", "idle" }, { "Walking", "walk" }, { "Running", "run" },
            { "Sprinting", "sprint" }, { "Aiming", "aim" },
            { "Crouching", "aim-sneak" }, { "Hands up", "hands_up" },
        })
    Creator.installPreviewLoadoutHitTargets(window, preview, previewW)
    if compact then
        window.modelToggleButton = addButton(profile, profileW - px(96), px(44), px(84),
            "MODEL", function()
                preview:setVisible(true)
                preview:bringToTop()
            end, true)
        addButton(preview, preview.width - px(88), px(8), px(76), "CLOSE", function()
            preview:setVisible(false)
            if window.returnToFactionEditor then
                window.returnToFactionEditor = nil
                window.factionEditor:setVisible(true)
                window.factionEditor:bringToTop()
            end
        end):bringToTop()
        preview:setVisible(false)
    end

    local initialProfileWidth = profileW
    local function setControlWidth(control, width)
        if control and control.setWidth then
            control:setWidth(math.max(1, width))
            Creator.fitButtonTitle(control)
        end
    end
    local function setControlX(control, x)
        if control and control.setX then

            if control.originalX ~= nil then control.originalX = x end
            control:setX(x)
        end
    end
    local function resizeVisibleRows(cards, container)
        if not container then return end
        for _, card in ipairs(cards or {}) do
            local left = tonumber(card.x) or 0
            local width = math.max(1, container.width - left)
            setControlWidth(card, width)
            if card.entry then
                Creator.placeFolderControls(card)
            elseif card.openButton then
                setControlWidth(card.openButton, width)
            end
        end
    end
    window.applyWorkbenchLayout = function(requestedFactionW, requestedRosterW)
        if window.compactWorkbench then return false end
        local minimumFaction, minimumRoster = px(220), px(300)

        local minimumProfile = initialProfileWidth
        local factionWidth = math.max(minimumFaction,
            math.min(requestedFactionW or settings.width,
                page.width - gap * 2 - minimumRoster - minimumProfile))
        local rosterWidth = math.max(minimumRoster,
            math.min(requestedRosterW or roster.width,
                page.width - gap * 2 - factionWidth - minimumProfile))
        local profileWidth = page.width - gap * 2 - factionWidth - rosterWidth

        settings:setWidth(factionWidth)
        roster:setX(factionWidth + gap)
        roster:setWidth(rosterWidth)
        profile:setX(factionWidth + rosterWidth + gap * 2)
        profile:setWidth(profileWidth)
        Creator.rosterRatio = rosterWidth / math.max(1, page.width)

        setControlWidth(window.factionSearch, factionWidth - px(126))
        setControlX(window.newFactionButton, factionWidth - px(106))
        setControlWidth(window.factionCardsArea, factionWidth - px(24))
        setControlX(window.factionNext, factionWidth - px(42))
        local factionActionWidth = factionWidth - px(24)
        local editFactionWidth = math.floor(factionActionWidth * 0.48)
        local shareFactionWidth = math.floor((factionActionWidth - editFactionWidth - px(8)) / 2)
        setControlWidth(window.editFactionButton, editFactionWidth)
        setControlX(window.exportFactionButton, px(16) + editFactionWidth)
        setControlWidth(window.exportFactionButton, shareFactionWidth)
        setControlX(window.importFactionButton, px(20) + editFactionWidth + shareFactionWidth)
        setControlWidth(window.importFactionButton, shareFactionWidth)
        local factionActionW = math.floor((factionWidth - px(28)) / 2)
        setControlX(window.cloneFactionButton, px(12))
        setControlWidth(window.cloneFactionButton, factionActionW)
        setControlX(window.deleteFactionButton, px(16) + factionActionW)
        setControlWidth(window.deleteFactionButton, factionActionW)
        setControlWidth(window.newFolderButton, factionActionW)
        setControlX(window.newFactionBottomButton, px(16) + factionActionW)
        setControlWidth(window.newFactionBottomButton, factionActionW)
        setControlX(window.newFactionPlusButton, factionWidth - px(78))

        setControlWidth(window.groupSetup, rosterWidth - px(24))
        setControlX(window.rosterFaction, rosterWidth - px(240))
        setControlWidth(window.profileSearch, rosterWidth - px(136))
        setControlX(window.newMemberButton, rosterWidth - px(12) - window.newMemberButton.width)
        local filterW = math.floor((rosterWidth - px(33)) / 4)
        for index, id in ipairs({ "all", "ranged", "melee", "issues" }) do
            local button = window.rosterFilterButtons[id]
            setControlX(button, px(12) + (index - 1) * (filterW + px(3)))
            setControlWidth(button, filterW)
        end
        setControlWidth(window.rosterColumns, rosterWidth - px(24))
        setControlWidth(window.profileCardsArea, rosterWidth - px(24))
        setControlX(window.profileNext, rosterWidth - px(42))
        setControlX(window.rosterNarrowButton, math.floor(rosterWidth / 2) - px(39))
        setControlX(window.rosterWideButton, math.floor(rosterWidth / 2) + px(5))
        local rosterActionW = math.floor((rosterWidth - px(28)) / 2)
        setControlWidth(window.clonePresetButton, rosterActionW)
        setControlX(window.deletePresetButton, px(16) + rosterActionW)
        setControlWidth(window.deletePresetButton, rosterActionW)

        setControlX(window.deleteProfileButton, profileWidth - px(12) - window.deleteProfileButton.width)
        setControlX(window.duplicateProfileButton,
            window.deleteProfileButton.x - px(8) - window.duplicateProfileButton.width)
        setControlX(window.previousMemberButton, profileWidth - px(78))
        setControlX(window.nextMemberButton, profileWidth - px(44))
        setControlX(window.saveNowButton, profileWidth - px(116))
        local liveTabW = math.floor((profileWidth - px(28) - (#tabs - 1) * px(5)) / #tabs)
        for index, name in ipairs(tabs) do
            local button = window.profilePageButtons[name]
            setControlX(button, px(14) + (index - 1) * (liveTabW + px(5)))
            setControlWidth(button, liveTabW)
            setControlWidth(window.profilePages[name], profileWidth - px(24))
        end
        setControlX(preview, profileWidth - preview.width - px(12))
        if window.leftPaneDivider then
            window.leftPaneDivider:setX(factionWidth + px(1))
        end
        if window.rightPaneDivider then
            window.rightPaneDivider:setX(factionWidth + rosterWidth + gap + px(1))
        end

        resizeVisibleRows(window.factionCards, window.factionCardsArea)
        resizeVisibleRows(window.profileCards, window.profileCardsArea)
        return true
    end

    local function addPaneDivider(kind, x)
        local divider = ISPanel:new(x, 0, gap - px(2), height)
        divider:initialise()
        divider.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        divider.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        divider.prerender = function(self)
            local active = self.dragging or self:isMouseOver()
            if active then
                self:drawRect(0, 0, self.width, self.height,
                    0.24, ROSE_DARK.r, ROSE_DARK.g, ROSE_DARK.b)
            end
            local centre = math.floor(self.width / 2)
            self:drawRect(centre - px(1), 0, px(2), self.height,
                active and 1 or 0.72, ROSE.r, ROSE.g, ROSE.b)
            local gripY = math.floor(self.height / 2) - px(20)
            self:drawRect(centre - px(2), gripY, px(4), px(40),
                active and 0.95 or 0.68, ROSE.r, ROSE.g, ROSE.b)
            self:drawTextCentre("<>", self.width / 2, gripY + px(12),
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        end
        divider.onMouseDown = function(self)
            self.dragging = true
            self:bringToTop()
            return true
        end
        divider.onMouseMove = function(self, dx)
            if not self.dragging then return end
            if kind == "left" then
                window.applyWorkbenchLayout(settings.width + dx, roster.width)
            else
                window.applyWorkbenchLayout(settings.width, roster.width + dx)
            end
        end
        divider.onMouseMoveOutside = divider.onMouseMove
        divider.onMouseUp = function(self) self.dragging = false; return true end
        divider.onMouseUpOutside = divider.onMouseUp
        page:addChild(divider)
        divider:bringToTop()
        return divider
    end
    if not compact then
        window.leftPaneDivider = addPaneDivider("left", settingsW + px(1))
        window.rightPaneDivider = addPaneDivider("right", settingsW + rosterW + gap + px(1))
    end
    window.saveStateLabel = addLabel(profile, px(12), height - px(33),
        "Saved", MUTED)
    window.saveNowButton = addButton(profile, profileW - px(116), height - px(38), px(104),
        "SAVE NOW", function()
            Creator.flushEdits(window)
        end, true)
    Creator.addTooltip(window.saveNowButton, "Save current faction and NPC edits now. Shortcut: Ctrl + S.")

    local editorW = compact and page.width or profile.x - gap
    local editor = createFramedPanel(page, 0, 0, editorW, page.height)
    editor.backgroundColor = copyColor(PANEL_BG)
    editor.borderColor = copyColor(ROSE)
    window.factionEditor = editor
    window.factionEditorSplit = { settingsW, rosterW }
    addLabel(editor, px(16), px(14), "FACTION SETTINGS", ROSE, UIFont.Medium)
    window.factionId = addLabel(editor, px(16), px(44), "ID: -", MUTED)
    addButton(editor, editor.width - px(114), px(14), px(98), "ROSTER", function()
        setRootPage(window, "workbench")
    end)
    if compact then
        addButton(editor, editor.width - px(212), px(14), px(90), "CHARACTER", function()
            if not window.currentProfile then return end
            window.returnToFactionEditor = true
            editor:setVisible(false)
            window.setCompactPane("editor")
            window.avatarPreviewPane:setVisible(true)
            window.avatarPreviewPane:bringToTop()
        end)
    end
    window.factionSaveStateLabel = addLabel(editor, px(22), editor.height - px(34),
        "Saved", MUTED)
    window.factionSaveNowButton = addButton(editor, editor.width - px(122), editor.height - px(38),
        px(104), "SAVE NOW", function()
            Creator.flushEdits(window)
        end, true)

    window.factionEditorPages, window.factionEditorButtons = {}, {}
    local factionTabs = {
        { "overview", "IDENTITY" }, { "relations", "RELATIONS" },
        { "spawning", "SPAWNING" },
        { "group_modules", "BEHAVIOR DEFAULTS" }, { "support", "SUPPORT" },
        { "wardrobe", "WARDROBE BY SEASON" },
    }
    local tabColumns = editor.width >= px(860) and 6 or 3
    local factionTabW = math.floor((editor.width - px(36) - (tabColumns - 1) * px(5)) / tabColumns)
    local pageY = px(72) + math.ceil(#factionTabs / tabColumns) * px(32)
    local function setFactionEditorPage(id)
        for pageId, panel in pairs(window.factionEditorPages) do
            panel:setVisible(pageId == id)
        end
        for pageId, button in pairs(window.factionEditorButtons) do
            styleButton(button, pageId == id)
        end
        if window.syncFactionSupport then window.syncFactionSupport() end
        window.factionEditorPage = id
    end
    for index, spec in ipairs(factionTabs) do
        local pageId = spec[1]
        window.factionEditorButtons[pageId] = addButton(editor,
            px(18) + ((index - 1) % tabColumns) * (factionTabW + px(5)),
            px(72) + math.floor((index - 1) / tabColumns) * px(32), factionTabW, spec[2],
            function() setFactionEditorPage(pageId) end)
        local sub = ISPanel:new(px(18), pageY, editor.width - px(36), editor.height - pageY - px(48))
        sub:initialise()
        sub.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        sub.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        editor:addChild(sub)
        window.factionEditorPages[pageId] = sub
    end
    Creator.buildFactionIdentityPage(window, setFactionEditorPage)

    Creator.buildFactionRelationsPage(window)

    Creator.buildFactionSpawnSettings(window, window.factionEditorPages.spawning)
    Creator.buildFactionSupportSettings(window, window.factionEditorPages.support)

    Creator.buildFactionModulesPage(window)
    Creator.buildFactionWardrobePage(window)
    setFactionEditorPage("overview")
    editor:setVisible(false)
    setProfilePage(window, "identity")
    if compact then window.setCompactPane("factions") end
end

function Creator.buildModuleLibrary(window, page)
    page:setScrollChildren(true)
    page:addScrollBars()
    page:setScrollHeight(math.max(page.height, 610))
    window.factionModuleEntries = {}
    window.factionModuleStatuses = {}
    addLabel(page, 28, 352, "EXTERNAL MODULE OVERRIDES", ROSE)
    addLabel(page, 28, 376,
        "Core AI stays active. Assign a loaded custom module ID only when a separate module provides one.",
        MUTED)
    local customGap = 18
    local customW = math.floor((page.width - 56 - customGap) / 2)
    for index, spec in ipairs(FACTION_MODULES) do
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        local x, y = 28 + column * (customW + customGap), 410 + row * 72
        addLabel(page, x, y, spec[1], MUTED)
        local entry = addEntry(page, x, y + 22, customW - 112, "")
        entry:setPlaceholderText("No custom override")
        window.factionModuleEntries[spec[2]] = entry
        window.factionModuleStatuses[spec[2]] = addLabel(page,
            x + customW - 100, y + 25, "NOT ASSIGNED", MUTED)
    end
    addLabel(page, 28, 564, "CHANGES SAVE AUTOMATICALLY", MUTED)
    page.prerender = function(self)
        ISPanel.prerender(self)
        local scrollY = self.getYScroll and self:getYScroll() or 0
        self:drawTextCentre("SYSTEMS & MODULES", self.width / 2, 16 + scrollY,
            TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Title or UIFont.Large)
        self:drawTextCentre("Built-in systems and optional integrations - not a live health report",
            self.width / 2, 54 + scrollY, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        local cards = {
            { "NPC BRAIN", "Decision tree / persistent task queue" },
            { "PERCEPTION", "Targets, memory, hearing and threat scoring" },
            { "MOVEMENT", "Pathing, vaulting, formation and recovery" },
            { "COMBAT", "Aiming, melee, suppression and retreat" },
            { "SCAVENGING", "World search, reservations and inventory" },
            { "VOICE", "Speech, combat barks and death sounds" },
            { "ENCOUNTER", "Group placement and encounter startup" },
            { "FULL RAID", "Raid waves, staging and persistence" },
        }
        local gap, columns = 10, 4
        local cardsLeft = 28
        local cardW = math.floor((self.width - cardsLeft * 2 - gap * (columns - 1)) / columns)
        local cardH = 112
        for index, card in ipairs(cards) do
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            local x, y = cardsLeft + column * (cardW + gap),
                88 + row * (cardH + gap) + scrollY
            self:drawRect(x, y, cardW, cardH, CARD_BG.a, CARD_BG.r, CARD_BG.g, CARD_BG.b)
            self:drawRectBorder(x, y, cardW, cardH, 0.7, CONTROL_BORDER.r, CONTROL_BORDER.g, CONTROL_BORDER.b)
            self:drawText(card[1], x + 14, y + 13, ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Medium)
            self:drawText(card[2], x + 14, y + 47, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            self:drawText("BUILT-IN", x + 14, y + 78,
                MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        end
    end
    page.update = function(self)
        ISPanel.update(self)
        for _, spec in ipairs(FACTION_MODULES) do
            local entry = window.factionModuleEntries[spec[2]]
            local active = entry and safeText(entry:getText()) ~= ""
            local status = window.factionModuleStatuses[spec[2]]
            if status then status:setName(active and "OVERRIDE SET" or "NOT ASSIGNED") end
        end
    end
end

function Creator.buildEncounterPage(window, page)
    local definitions = ProjectALife.Encounters and ProjectALife.Encounters.definitions or {}
    local onlyId = ProjectALife.Encounters and ProjectALife.Encounters.onlyId or nil
    local totalWeight = 0
    for _, definition in ipairs(definitions) do
        local weight = math.max(0, tonumber(definition.weight) or 0)
        if definition.trigger == nil and (onlyId == nil or definition.id == onlyId) then
            totalWeight = totalWeight + weight
        end
    end
    local function listText(values, fallback)
        local result = {}
        for _, value in ipairs(type(values) == "table" and values or {}) do
            result[#result + 1] = string.upper(tostring(value):gsub("_", " "))
        end
        return #result > 0 and table.concat(result, ", ") or fallback
    end
    local columns = page.width >= 980 and 2 or 1
    local gap, margin, cardH = 12, 24, 172
    local cardW = math.floor((page.width - margin * 2 - gap * (columns - 1)) / columns)
    page:setScrollChildren(true)
    page:addScrollBars()
    local rows = math.ceil(#definitions / columns)
    page:setScrollHeight(math.max(page.height, 94 + rows * (cardH + gap)))
    addLabel(page, margin, 12, "ENCOUNTER CATALOG", TEXT, UIFont.Large)
    addLabel(page, margin, 45,
        "Exact runtime rules: chance, squad size, location, time, placement, scene and AI profile.", MUTED)
    addLabel(page, page.width - 268, 18,
        tostring(#definitions) .. " TEMPLATES | " .. tostring(totalWeight) .. " RANDOM WEIGHT", ROSE)
    for index, definition in ipairs(definitions) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local card = ISPanel:new(margin + column * (cardW + gap),
            78 + row * (cardH + gap), cardW, cardH)
        card:initialise()
        card.definition = definition
        card.weight = math.max(0, tonumber(definition.weight) or 0)
        card.randomEligible = definition.trigger == nil and card.weight > 0 and
            (onlyId == nil or definition.id == onlyId)
        card.chance = card.randomEligible and totalWeight > 0 and
            (card.weight / totalWeight * 100) or 0
        card.prerender = function(self)
            ISPanel.prerender(self)
            local item = self.definition
            self:drawRect(0, 0, self.width, self.height,
                CARD_BG.a, CARD_BG.r, CARD_BG.g, CARD_BG.b)
            self:drawRectBorder(0, 0, self.width, self.height, 0.92,
                CONTROL_BORDER.r, CONTROL_BORDER.g, CONTROL_BORDER.b)
            self:drawRect(0, 0, 5, self.height, 0.95, ROSE.r, ROSE.g, ROSE.b)
            self:drawText(string.upper(tostring(item.label or item.id)), 16, 10,
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Medium)
            local chanceLabel
            if item.trigger then
                chanceLabel = "DIRECTOR: " .. string.upper(tostring(item.trigger):gsub("_", " "))
            elseif self.weight <= 0 then
                chanceLabel = "DISABLED"
            elseif not self.randomEligible then
                chanceLabel = "FILTERED BY DEBUG OVERRIDE"
            else
                chanceLabel = string.format("WEIGHT %d | %.1f%% OF RANDOM ROLLS", self.weight, self.chance)
            end
            self:drawTextRight(chanceLabel, self.width - 14, 13,
                ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            self:drawText(fitText(tostring(item.summary or ""), UIFont.Small, self.width - 32),
                16, 39, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            local leftW = math.floor((self.width - 40) / 2)
            self:drawText("SQUAD", 16, 67, ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            self:drawText(tostring(item.minCount or 1) .. "-" .. tostring(item.maxCount or 1) ..
                " NPCs | " .. string.upper(tostring(item.mode or "guard")),
                16, 85, TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            self:drawText("WHEN", 16, 109, ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            self:drawText(fitText(listText(item.timeOfDay, "ANY TIME"), UIFont.Small, leftW),
                16, 127, TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            local rightX = leftW + 28
            self:drawText("WHERE", rightX, 67, ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            self:drawText(fitText(listText(item.locations, "ANYWHERE"), UIFont.Small,
                self.width - rightX - 14), rightX, 85,
                TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            self:drawText("PLACEMENT & AI", rightX, 109,
                ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            local detail = string.upper(tostring(item.placement or "RING")) .. " | " ..
                string.upper(tostring(item.profile or "DEFAULT"))
            if item.scene then detail = detail .. " | SCENE " .. string.upper(tostring(item.scene)) end
            self:drawText(fitText(detail, UIFont.Small, self.width - rightX - 14),
                rightX, 127, TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
            local flags = {}
            if item.stance then flags[#flags + 1] = "STANCE " .. string.upper(tostring(item.stance)) end
            if item.persistent then flags[#flags + 1] = "PERSISTENT" end
            if item.awareness then flags[#flags + 1] = "AWARENESS " .. tostring(item.awareness) end
            self:drawText(#flags > 0 and table.concat(flags, " | ") or "STANDARD LIFECYCLE",
                16, 151, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        end
        page:addChild(card)
    end
end

function Creator.processPortraitQueue(window, budget)
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    if (window.avatarAssetsPending or (window.avatarSettleRetries or 0) > 0)
            and (window.avatarAssetRetries or 0) < 60
            and now >= (window.avatarAssetRetryAtMs or 0) then
        window.avatarAssetRetryAtMs = now + 500
        window.avatarAssetRetries = (window.avatarAssetRetries or 0) + 1
        window.avatarSettleRetries = math.max(0, (window.avatarSettleRetries or 0)-1)
        refreshAvatar(window, true)
    end
    for _ = 1, math.max(1, tonumber(budget) or 1) do
        local pending = table.remove(window.portraitQueue, 1)
        if not pending then return end
        if now < (pending.retryAtMs or 0) then
            window.portraitQueue[#window.portraitQueue + 1] = pending
            return
        end
        local expected = pending.scope == "faction" and
            window.factionPortraitGeneration or (pending.scope == "appearance" and
                window.appearancePortraitGeneration or window.profilePortraitGeneration)
        local attached = false
        pcall(function() attached = pending.card:getParent() ~= nil end)
        if attached and pending.generation == expected then

            window.previewTintCache = window.previewTintCache or {}
            local descriptor, pendingAssets = createPortraitDescriptor(pending.profile,
                pending.outfitId or "A", window.previewTintCache, 0)
            if pendingAssets then

                pending.retries = (pending.retries or 0) + 1
                pending.retryAtMs = now + 500
                if pending.retries < 60 then window.portraitQueue[#window.portraitQueue + 1] = pending end
                return
            elseif descriptor then
                pending.card.descriptor = descriptor
                local px = Creator.px
                if pending.scope == "faction" then
                    local portraitWidth = pending.card.portraitWidth or px(64)
                    pending.card.portrait = installPortrait(pending.card,
                        px(9), px(7), portraitWidth, pending.card.height - px(14), descriptor, true)
                elseif pending.scope == "appearance" then
                    local footer = pending.card.compactAppearance and px(22) or px(50)
                    pending.card.portrait = installPortrait(pending.card,
                        px(8), px(5), pending.card.width - px(16),
                        math.max(px(18), pending.card.height - footer), descriptor, true)
                elseif window.rootPages and window.rootPages.workbench then
                    pending.card.portrait = installPortrait(pending.card,
                        px(6), px(5), px(52), pending.card.height - px(10),
                        descriptor, pending.headOnly == true)
                else
                    pending.card.portrait = installPortrait(pending.card,
                        px(9), px(8), px(56), pending.card.height - px(16),
                        descriptor, pending.headOnly == true)
                end
                if pending.card.openButton then pending.card.openButton:bringToTop() end
            end
        end
    end
end

local function buildWindow()
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    Creator.uiScale = Creator.layoutScale(screenW, screenH)
    local px = Creator.px
    local width, height = math.max(px(1000), screenW - px(24)), math.max(px(680), screenH - px(24))
    width, height = math.min(width, screenW), math.min(height, screenH)
    local window = ISPanel:new((screenW - width) / 2, (screenH - height) / 2,
        width, height)
    window:initialise()
    window.backgroundColor = copyColor(PANEL_BG)
    window.borderColor = copyColor(ROSE)
    window.moveWithMouse = false
    window.prerender = function(self)
        ISPanel.prerender(self)
        self:drawTextCentre("PROJECT A-LIFE CREATOR", self.width / 2, px(10),
            TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Title or UIFont.Large)

        local faction = self.currentFaction ~= nil
            and safeText(self.currentFaction.name) or "no faction"
        local npc = self.currentProfile ~= nil
            and safeText(self.currentProfile.name) or "no NPC picked"
        self:drawTextRight(string.upper(faction) .. "   >   " .. string.upper(npc),
            self.width - px(18), px(16), ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
        self:drawRect(px(12), px(46), self.width - px(24), px(2), 0.9,
            ROSE.r, ROSE.g, ROSE.b)
        self:drawRect(px(12), self.height - px(42), self.width - px(24), px(1),
            0.55, ROSE.r, ROSE.g, ROSE.b)
    end

    window.render = function(self)
        ISPanel.render(self)
        local drag = self.factionDrag or self.folderDrag
        if not drag or not drag.active or type(getMouseX) ~= "function"
                or type(getMouseY) ~= "function" then return end
        local ghostW, ghostH = math.min(px(310), self.width - px(36)), px(64)
        local x = getMouseX() - self:getAbsoluteX() + px(18)
        local y = getMouseY() - self:getAbsoluteY() + px(18)
        x = math.max(px(12), math.min(x, self.width - ghostW - px(12)))
        y = math.max(px(12), math.min(y, self.height - ghostH - px(12)))
        local destination = "DROP ON A FOLDER"
        local folderId = drag.folderId and Creator.folderOrderDropTarget(self)
            or factionDropTarget(self)
        if folderId then
            destination = "MOVE TO UNFILED"
            for _, header in ipairs(self.folderHeaders or {}) do
                if header.folderId == folderId then
                    destination = "MOVE TO " .. string.upper(safeText(header.entry.name))
                    break
                end
            end
        end
        self:drawRect(x + px(5), y + px(5), ghostW, ghostH, 0.55, 0, 0, 0)
        self:drawRect(x, y, ghostW, ghostH, 0.97,
            ROSE_DARK.r, ROSE_DARK.g, ROSE_DARK.b)
        self:drawRectBorder(x, y, ghostW, ghostH, 1, ROSE.r, ROSE.g, ROSE.b)
        self:drawText("::", x + px(12), y + px(10), ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Medium)
        self:drawText(fitText(drag.folderName or drag.factionName, UIFont.Medium, ghostW - px(68)),
            x + px(42), y + px(8), TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Medium)
        self:drawText(fitText((drag.folderName and "REORDER FOLDER" or drag.factionCategory)
            .. "  /  " .. destination,
            UIFont.Small, ghostW - px(54)), x + px(42), y + px(36),
            MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
    end

    window.openedInGame = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) ~= nil
    window.rootPages, window.rootButtons = {}, {}
    window.previewTintCache, window.outfitPreviewVariation = {}, 0
    local rootTabs = {
        { "workbench", "NPC SETTINGS" },
        { "faction", "FACTION SETTINGS" },
    }
    local tabW = math.min(px(210), math.floor((width - px(42)) / #rootTabs))
    for index, spec in ipairs(rootTabs) do
        local pageId = spec[1]
        window.rootButtons[pageId] = addButton(window,
            px(14) + (index - 1) * (tabW + px(7)), px(52), tabW, spec[2],
            function() setRootPage(window, pageId) end)
        if pageId == "workbench" then
        local page = ISPanel:new(px(12), px(84), width - px(24), height - px(134))
        page:initialise()
        page.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        page.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        window:addChild(page)
        window.rootPages[pageId] = page
        end
    end

    window.statusLabel = addLabel(window, px(14), height - px(34),
        "CATALOG LOADING", MUTED)
    if window.openedInGame then
        addButton(window, width - px(292), height - px(38), px(168), "SYNC TO SERVER",
            function() Creator.syncServer(window) end, true)
    end
    addButton(window, width - px(114), height - px(38), px(100), "CLOSE",
        function() Creator.close() end)
    if Creator.buildHelpHeader then Creator.buildHelpHeader(window) end
    window.resetFactionsButton = addButton(window, width - px(254), px(52), px(240),
        "RESET FACTIONS TO DEFAULT", function() Creator.confirmResetFactions(window) end)
    Creator.addTooltip(window.resetFactionsButton,
        "Built-in factions go back to default. Factions you made yourself stay.")
    Creator.buildFactionWorkbench(window, window.rootPages.workbench)

    window.portraitQueue = {}
    window.factionPage, window.profilePageIndex = 1, 1
    window.factionSearchApplied, window.profileSearchApplied = "", ""
    window.update = function(self)
        ISPanel.update(self)
        local factionSearch = tostring(self.factionSearch and
            self.factionSearch:getText() or "")
        if factionSearch ~= self.factionSearchApplied then
            self.factionSearchApplied = factionSearch
            self.factionPage = 1
            rebuildFactionCards(self)
        end
        local profileSearch = tostring(self.profileSearch and
            self.profileSearch:getText() or "")
        if profileSearch ~= self.profileSearchApplied then
            self.profileSearchApplied = profileSearch
            self.profilePageIndex = 1
            rebuildProfileCards(self)
        end
        local activeVoiceProfile = selectedData(self.profileVoice) or ""
        local relationSearch = tostring(self.relationSearch and self.relationSearch:getText() or "")
        if relationSearch ~= self.relationSearchApplied then
            self.relationSearchApplied = relationSearch
            Creator.filterRelations(self)
        end
        if activeVoiceProfile ~= self.voiceEventsForProfile then
            refreshVoiceEvents(self)
        end
        Creator.refreshBehaviorSummary(self)
        Creator.refreshEffectiveRelation(self)
        local activeGender = selectedData(self.profileGender)
        if activeGender and activeGender ~= self.profileGenderApplied then
            self.profileGenderApplied = activeGender
            setProfileGender(self, activeGender == "female")
        end
        local activeAnimation = self.avatarAnimation and selectedData(self.avatarAnimation)
        if activeAnimation and activeAnimation ~= self.avatarAnimationApplied then
            Creator.setAvatarAnimation(self, activeAnimation)
        end

        local loadoutSignature = table.concat({
            tostring(selectedData(self.primaryCombo) or "none"),
            tostring(selectedData(self.secondaryCombo) or "none"),
            tostring(selectedData(self.meleeCombo) or "none"),
            tostring(self.primaryMagazines and self.primaryMagazines:getText() or "0"),
            tostring(self.secondaryMagazines and self.secondaryMagazines:getText() or "0"),
        }, "\31")
        if loadoutSignature ~= self.loadoutPreviewSignature then
            self.loadoutPreviewSignature = loadoutSignature
            if self.syncLoadoutTiles then self.syncLoadoutTiles() end
        end

        local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
        if not self.autosaveGuard and not self.itemPicker and not self.appearancePicker
                and not self.seasonalPreview and not self.factionWardrobeEditor and not Creator.seasonalJob
                and now >= (self.nextAutosaveScan or 0) then
            self.nextAutosaveScan = now + 220
            local invalidFaction = Creator.validateFactionFields(self)
            local profileChanged, factionChanged = false, false
            if self.currentProfile then
                local current = signature(harvestProfile(self))
                profileChanged = current ~= self.profileBaseline
                if profileChanged and current ~= self.pendingProfileSignature then
                    self.pendingProfileSignature, self.profileDirtyAt = current, now
                elseif not profileChanged then
                    self.pendingProfileSignature, self.profileDirtyAt = nil, nil
                end
            end
            if self.currentFaction then
                local current = signature(harvestFaction(self))
                factionChanged = current ~= self.factionBaseline
                if factionChanged and current ~= self.pendingFactionSignature then
                    self.pendingFactionSignature, self.factionDirtyAt = current, now
                elseif not factionChanged then
                    self.pendingFactionSignature, self.factionDirtyAt = nil, nil
                end
            end
            local dirty = profileChanged or factionChanged
            local labelText, labelTone = Creator.saveLabel(self, invalidFaction, dirty)
            Creator.paintSaveStatus(self.saveStateLabel, labelText, labelTone)
            Creator.paintSaveStatus(self.factionSaveStateLabel, labelText, labelTone)
            if profileChanged and now - (self.profileDirtyAt or now) >= 650 then
                Creator.beginProfileSave(self)
            elseif factionChanged and not invalidFaction and now - (self.factionDirtyAt or now) >= 650 then
                saveFaction(self)
            end
        end

        Creator.stepProfileSave(self)
        Creator.processPortraitQueue(self, 1)
    end
    setRootPage(window, "workbench")
    return window
end

function Creator.onFactionsSynced(revision)
    local window = Creator.window
    if window == nil then return false end
    local wanted = window.currentFaction and window.currentFaction.id or nil
    pcall(refreshFactions, window, wanted)
    return true
end

function Creator.open()

    if not Creator.adminAllowed(0) then return false end
    if Creator.window and not Creator.close() then return false end
    if ISPanel == nil or ISComboBox == nil then
        print("[ProjectALife] Creator unavailable: base UI classes are not loaded")
        return false
    end
    Creator.window = buildWindow()
    local mainScreen = MainScreen and MainScreen.instance or nil
    Creator.window.mainScreen = mainScreen
    Creator.window.mainScreenWasVisible = mainScreen and mainScreen:getIsVisible() == true
    if mainScreen and Creator.window.mainScreenWasVisible then

        mainScreen:setVisible(false)
        if mainScreen.alifePanel then mainScreen.alifePanel:setVisible(false) end
        if mainScreen.alifeAliveMark then mainScreen.alifeAliveMark:setVisible(false) end
    end
    Creator.window:addToUIManager()
    Creator.window:setAlwaysOnTop(true)
    Creator.window:bringToTop()
    buildAvatar(Creator.window)
    local wantedFaction, wantedProfile = Creator.pendingFactionId, Creator.pendingProfileId
    Creator.pendingFactionId, Creator.pendingProfileId = nil, nil
    refreshFactions(Creator.window, wantedFaction)
    if wantedProfile then selectProfile(Creator.window, wantedProfile) end
    if Creator.offerHelp then pcall(Creator.offerHelp, Creator.window) end
    return true
end

function Creator.close()
    if not Creator.window then return true end
    if not Creator.flushLeave(Creator.window) then return false end
    local mainScreen = Creator.window.mainScreen
    local restoreMainScreen = Creator.window.mainScreenWasVisible == true
    disposeAvatar(Creator.window)
    pcall(function() Creator.window:removeFromUIManager() end)
    Creator.window = nil
    if mainScreen and restoreMainScreen then
        mainScreen:setVisible(true)
        Creator.syncMainMenuBrand()
    end
    return true
end

function Creator.onKeyPressed(key)
    local window = Creator.window
    if window == nil or window:getIsVisible() == false then return end
    if Creator.helpKey and Creator.helpKey(window, key) then return end
    if key == Keyboard.KEY_ESCAPE then
        Creator.close()
        return
    end
    if key ~= Keyboard.KEY_S or type(isKeyDown) ~= "function" then return end
    if isKeyDown(Keyboard.KEY_LCONTROL) or isKeyDown(Keyboard.KEY_RCONTROL) then
        Creator.playUiSound("SAVE NOW")
        Creator.flushEdits(window)
    end
end

function Creator.onCreatorServerCommand(module, command, args)
    if module ~= "ProjectALife" or command ~= "debugSyncCreatorResult"
            or not Creator.window or not Creator.window.statusLabel then return end
    args = type(args) == "table" and args or {}
    Creator.window.statusLabel:setName(args.ok == true and
        "SERVER SYNC COMPLETE" or ("SERVER SYNC FAILED: " .. tostring(args.reason or "unknown")))
end

function Creator.adminAllowed(playerNum)
    if type(isClient) ~= "function" then return false end
    local okClient, client = pcall(isClient)
    if not okClient then return false end
    if client ~= true then return true end
    if type(isAdmin) == "function" then
        local okAdmin, admin = pcall(isAdmin)
        if okAdmin and admin == true then return true end
    end
    if type(getSpecificPlayer) ~= "function" then return false end
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil or type(player.getAccessLevel) ~= "function" then return false end
    local okLevel, level = pcall(player.getAccessLevel, player)
    return okLevel and string.lower(tostring(level or "")) == "admin"
end

function Creator.onCreatorWorldContext(playerNum, context, worldObjects, test)
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.rightClickOn) ~= "function" or not prefs.rightClickOn() then return end
    if test or not Creator.adminAllowed(playerNum) then return end

    if prefs ~= nil and type(prefs.diagnostics) == "function" and not prefs.diagnostics() then return end
    context:addOption("Project A-Life Creator", nil, function() Creator.open() end)
end

function Creator.menuEntryBounds(width, height)
    width, height = math.max(1, width), math.max(1, height)
    local margin = math.min(24, math.max(8, math.floor(math.min(width, height) * 0.025)))
    local w = math.max(1, math.min(width - margin * 2, math.max(300, math.min(440, width * 0.32))))
    local textManager = getTextManager()
    local titleFont = w < 360 and UIFont.Medium or UIFont.Large
    local textHeight = textManager:getFontHeight(titleFont) + textManager:getFontHeight(UIFont.Small) + 30
    local h = math.max(1, math.min(height - margin * 2, math.max(72, textHeight, math.min(94, height * 0.09))))
    return math.floor(math.max(0, width - w - margin)), math.floor(math.max(0, math.min(height - h - margin, height * 0.54))), math.floor(w), math.floor(h)
end

function Creator.resizeMenuEntry(panel, width, height)
    local x, y, w, h = Creator.menuEntryBounds(width, height)
    if panel.viewportW == width and panel.viewportH == height and panel.width == w and panel.height == h then return end
    panel.viewportW, panel.viewportH = width, height
    panel:setX(x); panel:setY(y); panel:setWidth(w); panel:setHeight(h)
    if panel.openButton then panel.openButton:setWidth(w); panel.openButton:setHeight(h) end
end

function Creator.resizeAliveMark(panel, mainScreen)
    local screenWidth = getCore():getScreenWidth()
    local logo = mainScreen and mainScreen.logoTexture or nil
    if not logo then return end
    local logoHeight = logo:getHeight()
    local scale = math.min(mainScreen:calcLogoHeight() / logoHeight, screenWidth / 1920)
    local logoX, logoY = 50 * (screenWidth / 1920), 50 * (screenWidth / 1920)
    local logoWidth = logo:getWidth() * scale
    local markWidth = math.max(76 * (screenWidth / 1920), logoWidth * 0.31)
    local markHeight = markWidth * (panel.texture:getHeight() / panel.texture:getWidth())
    panel:setX(math.floor(logoX + logoWidth * 0.61))
    panel:setY(math.floor(logoY + logoHeight * scale * 0.84))
    panel:setWidth(math.floor(markWidth))
    panel:setHeight(math.floor(markHeight))
end

function Creator.shouldShowMainMenuBrand(mainScreen)
    if not mainScreen or mainScreen.inGame == true or Creator.window ~= nil then return false end
    if type(mainScreen.getIsVisible) == "function" and mainScreen:getIsVisible() ~= true then return false end
    local bottom = mainScreen.bottomPanel
    return bottom ~= nil and type(bottom.getIsVisible) == "function"
        and bottom:getIsVisible() == true
end

function Creator.syncMainMenuBrand()
    local mainScreen = MainScreen and MainScreen.instance or nil
    if not mainScreen then return end
    local visible = Creator.shouldShowMainMenuBrand(mainScreen)
    if mainScreen.alifePanel and mainScreen.alifePanel:getIsVisible() ~= visible then
        mainScreen.alifePanel:setVisible(visible)
    end
    if mainScreen.alifeAliveMark and mainScreen.alifeAliveMark:getIsVisible() ~= visible then
        mainScreen.alifeAliveMark:setVisible(visible)
    end
end

function Creator.onMainMenuEnter()
    local mainScreen = MainScreen and MainScreen.instance or nil
    if not mainScreen or not ISPanel then return end

    if mainScreen.inGame == true then return end
    if mainScreen.alifePanel then
        Creator.syncMainMenuBrand()
        return
    end
    pcall(function()
        if not mainScreen.alifeAliveMark then
            local aliveTexture = type(getTexture) == "function"
                and getTexture("media/textures/ProjectALifeAlive.png") or nil
            if aliveTexture then
                local aliveMark = ISPanel:new(0, 0, 1, 1)
                aliveMark:initialise()
                aliveMark.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
                aliveMark.borderColor = { r = 0, g = 0, b = 0, a = 0 }
                aliveMark.texture = aliveTexture
                aliveMark.prerender = function(self)
                    Creator.resizeAliveMark(self, mainScreen)
                    ISPanel.prerender(self)
                    self:drawTextureScaled(self.texture, 0, 0, self.width, self.height,
                        0.94, 1, 1, 1)
                end
                mainScreen:addChild(aliveMark)
                mainScreen.alifeAliveMark = aliveMark
            end
        end
        local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
        local panelX, panelY, panelW, panelH = Creator.menuEntryBounds(screenW, screenH)
        local panel = ISPanel:new(panelX, panelY, panelW, panelH)
        panel:initialise()
        panel.backgroundColor = { r = 0.015, g = 0.017, b = 0.018, a = 0.90 }
        panel.borderColor = copyColor(CONTROL_BORDER)
        local icon = type(getTexture) == "function"
            and getTexture("media/textures/ProjectALifeMark.png") or nil
        panel.prerender = function(self)
            Creator.resizeMenuEntry(self, math.min(mainScreen.width or getCore():getScreenWidth(), getCore():getScreenWidth()),
                math.min(mainScreen.height or getCore():getScreenHeight(), getCore():getScreenHeight()))
            ISPanel.prerender(self)
            local hovered = self.openButton and self.openButton:isMouseOver()
            self:drawRect(0, 0, self.width, self.height, hovered and 0.98 or 0.92,
                hovered and 0.065 or CARD_BG.r, hovered and 0.072 or CARD_BG.g,
                hovered and 0.074 or CARD_BG.b)
            self:drawRectBorder(0, 0, self.width, self.height, 1,
                hovered and ROSE.r or CONTROL_BORDER.r,
                hovered and ROSE.g or CONTROL_BORDER.g,
                hovered and ROSE.b or CONTROL_BORDER.b)
            local iconSize = math.max(0, math.min(66, self.height - 16, self.width * 0.20))
            if icon then
                self:drawTextureScaledAspect2(icon, 10, math.floor((self.height - iconSize) / 2),
                    iconSize, iconSize, 0.96, 1, 1, 1)
            end
            local textX = iconSize + 24
            local titleFont = self.width < 360 and UIFont.Medium or UIFont.Large
            local titleHeight = getTextManager():getFontHeight(titleFont)
            local subtitleHeight = getTextManager():getFontHeight(UIFont.Small)
            local textY = math.max(8, math.floor((self.height - titleHeight - subtitleHeight - 6) / 2))
            if textX + 34 < self.width and textY + titleHeight <= self.height - 8 then
                self:drawText(fitText("PROJECT A-LIFE", titleFont, self.width - textX - 34), textX, textY,
                    TEXT.r, TEXT.g, TEXT.b, 1, titleFont)
                if textY + titleHeight + 6 + subtitleHeight <= self.height - 8 then
                    self:drawText(fitText(Creator.menuSubtitle(), UIFont.Small, self.width - textX - 34),
                        textX, textY + titleHeight + 6, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
                end
            end
            local arrowHeight = getTextManager():getFontHeight(UIFont.Large)
            if self.width >= 48 and self.height >= arrowHeight then
                self:drawText(">", self.width - 32, math.floor((self.height - arrowHeight) / 2),
                    hovered and ROSE.r or TEXT.r, hovered and ROSE.g or TEXT.g,
                    hovered and ROSE.b or TEXT.b, 1, UIFont.Large)
            end
        end
        local openButton = ISButton:new(0, 0, panel.width, panel.height, "", panel,
            function()
                Creator.playUiSound("MAIN MENU")
                local opened, result = pcall(Creator.open)
                if not opened then
                    print("[ProjectALife] Creator open failed: " .. tostring(result))
                    error(result)
                end
            end)
        openButton:initialise()
        openButton:instantiate()
        openButton.displayBackground = false
        openButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        openButton.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        panel:addChild(openButton)
        panel.openButton = openButton
        mainScreen:addChild(panel)
        mainScreen.alifePanel = panel
        Creator.syncMainMenuBrand()
    end)
end

Creator.addButton = addButton
Creator.addLabel = addLabel
Creator.addCenteredLabel = addCenteredLabel
Creator.addEntry = addEntry
Creator.addCombo = addCombo
Creator.addTick = addTick
Creator.addNumberChoices = addNumberChoices
Creator.addChoiceGrid = addChoiceGrid
Creator.selectedData = selectedData
Creator.selectData = selectData
Creator.styleButton = styleButton
Creator.fitText = fitText
Creator.createFramedPanel = createFramedPanel
Creator.firstPoolChoice = firstPoolChoice
Creator.poolVisual = poolVisual
Creator.showOutfit = showOutfit
Creator.harvestProfile = harvestProfile
Creator.signature = signature
Creator.deepCopy = deepCopy
Creator.harvestFaction = harvestFaction
Creator.saveFaction = saveFaction
Creator.profileFromRecord = profileFromRecord
Creator.factionFromRecord = factionFromRecord
Creator.createPortraitDescriptor = createPortraitDescriptor
Creator.installPortrait = installPortrait
Creator.rebuildFactionCards = rebuildFactionCards
Creator.refreshFactions = refreshFactions
Creator.setProfilePage = setProfilePage
function Creator.removeMemberTag(window, name)
    if not Creator.memberTagColor(window.currentFaction, name) or not Creator.flushEdits(window) then return false end
    local updates = {}
    for _, record in ipairs(factionProfiles(window, window.currentFaction.id)) do
        if record.general and record.general.role == name then
            local profile = profileFromRecord(record)
            profile.general.role = "Scout"
            updates[#updates + 1] = profile
        end
    end
    if #updates > 0 and not ProjectALife.CustomProfiles.saveMany(updates) then
        Creator.paintSaveStatus(window.saveStateLabel, "TAG DELETE FAILED - RETRY", "error")
        return false
    end
    for _, profile in ipairs(updates) do
        window.catalog.npcs[profile.id] = profile
        for index, record in ipairs(window.catalog.npcOrder or {}) do
            if record.id == profile.id then window.catalog.npcOrder[index] = profile end
        end
        if window.currentProfile and window.currentProfile.id == profile.id then
            window.currentProfile.general.role = "Scout"
            selectData(window.profileRole, "Scout")
            window.profileBaseline = signature(window.currentProfile)
            window.profileDirtyAt, window.pendingProfileSignature = nil, nil
        end
    end
    window.rosterRevision = (window.rosterRevision or 0) + 1
    local previous = window.currentFaction.general.memberTags
    local tags = Creator.memberTags(window.currentFaction)
    tags[name] = nil
    window.currentFaction.general.memberTags = Creator.encodeMemberTags(tags)
    if not saveFaction(window) then
        window.currentFaction.general.memberTags = previous
        Creator.loadMemberTags(window, selectedData(window.profileRole) or "Scout")
        rebuildProfileCards(window)
        Creator.paintSaveStatus(window.saveStateLabel, "MEMBERS RESET - TAG DELETE NOT SAVED; RETRY", "error")
        return false
    end
    Creator.loadMemberTags(window, selectedData(window.profileRole) or "Scout")
    rebuildProfileCards(window)
    return true
end
Creator.openWeaponAttachmentPicker = openWeaponAttachmentPicker
Creator.applyProfileDomainToFaction = applyProfileDomainToFaction
Creator.safeText = safeText
Creator.roleChoices = ROLES
Creator.hairChoices = HAIR
Creator.beardChoices = BEARD
Creator.scenarioChoices = SCENARIOS
Creator.specificPlaceChoices = SPECIFIC_PLACES
Creator.relationChoices = RELATIONS
Creator.locationsCollide = locationsCollide
Creator.itemBodyLocation = itemBodyLocation
Creator.currentOutfit = currentOutfit
Creator.clothingLocations = CLOTHING_LOCATIONS
Creator.palette = { MUTED = MUTED, ROSE = ROSE, TEXT = TEXT, CONTROL_BORDER = CONTROL_BORDER, CARD_BG = CARD_BG }

return Creator
