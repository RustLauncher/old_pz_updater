ProjectALife = ProjectALife or {}

local Library = {
    groups = {
        combat = {
            "UNDER_FIRE", "SUPPRESSED", "NEAR_MISS", "TAKING_COVER",
            "LEAVING_COVER", "CLOSE_CONTACT", "DISTANT_CONTACT",
            "MULTIPLE_CONTACTS", "MELEE_ENGAGE", "KNOCKED_DOWN",
            "GETTING_UP", "WEAPON_SWITCH", "LOW_AMMO", "COVER_ME",
            "FRIENDLY_FIRE", "COMBAT_END",
        },
        infected = {
            "HORDE_SPOTTED", "HORDE_INCOMING", "ZOMBIE_CLOSE",
            "CRAWLER_SPOTTED", "HOUSE_INFESTED", "GRABBED",
            "BITE_AVOIDED", "CORPSE_FOUND", "AREA_OVERRUN", "INFECTED_DOWN",
        },
        tactics = {
            "ADVANCE", "FALL_BACK", "HOLD_POSITION", "REGROUP", "MOVE_OUT",
            "SPREAD_OUT", "STACK_UP", "FLANK_START", "FLANK_COMPLETE",
            "AMBUSH_READY", "PATROL_START", "PATROL_CHECKPOINT",
            "RAID_START", "RAID_RETREAT",
        },
        awareness = {
            "HEARD_GUNSHOT", "HEARD_GLASS", "HEARD_DOOR", "HEARD_VOICE",
            "HEARD_FOOTSTEPS", "HEARD_ALARM", "FOUND_BLOOD", "FOUND_TRACKS",
            "FOUND_BODY", "AREA_CLEAR", "SEARCH_SPLIT", "SEARCH_COMPLETE",
        },
        navigation = {
            "DOOR_LOCKED", "DOOR_OPENING", "GATE_OPENING", "GATE_STUCK",
            "WINDOW_ENTRY", "WINDOW_BREAK", "VAULT_START", "VAULT_FAILED",
            "ENTER_BUILDING", "EXIT_BUILDING", "ROOM_CLEAR", "BREACH_FAILED",
            "BARRICADE_START", "BARRICADE_DONE", "BUILDING_SECURED",
        },
        scavenge = {
            "SCAVENGE_START", "CONTAINER_SEARCH", "FOUND_FOOD", "FOUND_WATER",
            "FOUND_AMMO", "FOUND_WEAPON", "FOUND_MEDICINE", "INVENTORY_FULL",
            "LOOT_EMPTY", "RETURN_WITH_LOOT",
        },
        needs = {
            "THIRSTY", "HUNGRY", "TIRED", "EXHAUSTED", "COLD", "HOT",
            "WET", "INJURED", "NEED_MEDICINE", "NEED_SMOKE", "DRINK_START",
            "DRINK_END", "EAT_START", "EAT_END", "SMOKE_START", "SMOKE_END",
            "REST_START", "REST_END", "SQUAD_REST_CALLED", "SQUAD_REST_READY",
        },
        social = {
            "CHECK_IN", "STATUS_OK", "ASK_AMMO", "GIVE_AMMO", "ASK_MEDICAL",
            "MEDIC_HELP", "LEADER_ORDER", "MEMBER_ACK", "MEMBER_MISSING",
            "ALLY_FOUND", "LEADER_DOWN", "MORALE_HIGH", "MORALE_LOW", "JOKE",
        },
        ambient = {
            "WEATHER_RAIN", "WEATHER_STORM", "WEATHER_FOG", "NIGHTFALL",
            "DAWN", "SAFE_MOMENT", "TENSE_SILENCE", "HOME_MEMORY",
            "FOOD_MEMORY", "LOCATION_COMMENT", "LONG_WALK", "AFTER_FIGHT",
        },
    },
    defaults = {
        combat = { priority = 76, chance = 62, cooldownMs = 14000,
            groupCooldownMs = 2400, actorLockMs = 1300 },
        infected = { priority = 72, chance = 58, cooldownMs = 15000,
            groupCooldownMs = 2600, actorLockMs = 1300 },
        tactics = { priority = 63, chance = 55, cooldownMs = 18000,
            groupCooldownMs = 2600, actorLockMs = 1400 },
        awareness = { priority = 54, chance = 48, cooldownMs = 18000,
            groupCooldownMs = 2800, actorLockMs = 1300 },
        navigation = { priority = 48, chance = 38, cooldownMs = 20000,
            groupCooldownMs = 2800, actorLockMs = 1200 },
        scavenge = { priority = 36, chance = 38, cooldownMs = 24000,
            groupCooldownMs = 3200, actorLockMs = 1200 },
        needs = { priority = 32, chance = 52, cooldownMs = 30000,
            groupCooldownMs = 4000, actorLockMs = 1300 },
        social = { priority = 24, chance = 34, cooldownMs = 36000,
            groupCooldownMs = 7000, actorLockMs = 1500 },
        ambient = { priority = 12, chance = 26, cooldownMs = 45000,
            groupCooldownMs = 8500, actorLockMs = 1500 },
    },
    ambientPools = {
        idle = { "SAFE_MOMENT", "TENSE_SILENCE", "HOME_MEMORY", "FOOD_MEMORY",
            "LOCATION_COMMENT", "JOKE", "CHECK_IN", "STATUS_OK" },
        patrol = { "LONG_WALK", "PATROL_CHECKPOINT", "LOCATION_COMMENT",
            "CHECK_IN", "TENSE_SILENCE" },
        after_combat = { "AFTER_FIGHT", "CHECK_IN", "STATUS_OK", "MORALE_LOW" },
        indoors = { "SAFE_MOMENT", "LOCATION_COMMENT", "CHECK_IN", "JOKE" },
    },

    actionContracts = {
        drink = { begin = "DRINK_START", complete = "DRINK_END" },
        eat = { begin = "EAT_START", complete = "EAT_END" },
        smoke = { begin = "SMOKE_START", complete = "SMOKE_END" },
        rest = { begin = "REST_START", complete = "REST_END" },
        barricade = { begin = "BARRICADE_START", complete = "BARRICADE_DONE" },
    },
    styles = { calm = {}, aggressive = {} },
}

local calm = Library.styles.calm
local aggressive = Library.styles.aggressive

calm.UNDER_FIRE = { "We're taking fire!", "Shots incoming!" }
aggressive.UNDER_FIRE = { "They're firing on us!", "Fire back!" }
calm.SUPPRESSED = { "Keep your head down.", "Pinned here." }
aggressive.SUPPRESSED = { "They've got us pinned!", "Get me out of this fire!" }
calm.NEAR_MISS = { "That was close.", "Round went right past me." }
aggressive.NEAR_MISS = { "Too damn close!", "Nearly had me!" }
calm.TAKING_COVER = { "Moving to cover.", "Covering up." }
aggressive.TAKING_COVER = { "Get behind something!", "Taking cover!" }
calm.LEAVING_COVER = { "Moving out of cover.", "I'm moving." }
aggressive.LEAVING_COVER = { "Going now!", "I'm pushing out!" }
calm.CLOSE_CONTACT = { "Contact, close!", "They're right here!" }
aggressive.CLOSE_CONTACT = { "Right on us!", "They're in our face!" }
calm.DISTANT_CONTACT = { "Contact at distance.", "Movement, far side." }
aggressive.DISTANT_CONTACT = { "I see them out there!", "Long-range contact!" }
calm.MULTIPLE_CONTACTS = { "Multiple contacts.", "More than one target." }
aggressive.MULTIPLE_CONTACTS = { "There's a whole group!", "Targets everywhere!" }
calm.MELEE_ENGAGE = { "Going hand to hand.", "Closing in." }
aggressive.MELEE_ENGAGE = { "I'm going in!", "Come here!" }
calm.KNOCKED_DOWN = { "I'm down!", "Lost my footing!" }
aggressive.KNOCKED_DOWN = { "Get them off me!", "I'm on the ground!" }
calm.GETTING_UP = { "Getting back up.", "I'm still in this." }
aggressive.GETTING_UP = { "Not done yet!", "Back on my feet!" }
calm.WEAPON_SWITCH = { "Changing weapon.", "Switching over." }
aggressive.WEAPON_SWITCH = { "Switching!", "Changing weapons!" }
calm.LOW_AMMO = { "Running low.", "Not many rounds left." }
aggressive.LOW_AMMO = { "Almost empty!", "I'm low on ammo!" }
calm.COVER_ME = { "Cover me.", "Watch my side." }
aggressive.COVER_ME = { "Cover me now!", "Keep them off me!" }
calm.FRIENDLY_FIRE = { "Watch your fire!", "That was too close to me." }
aggressive.FRIENDLY_FIRE = { "Check your damn fire!", "You nearly hit me!" }
calm.COMBAT_END = { "Looks clear.", "That should be the last of them." }
aggressive.COMBAT_END = { "That's all of them.", "We're done here." }

calm.HORDE_SPOTTED = { "Horde in sight.", "That's a large group of infected." }
aggressive.HORDE_SPOTTED = { "Horde!", "That's a lot of dead!" }
calm.HORDE_INCOMING = { "The horde is moving this way.", "They're coming toward us." }
aggressive.HORDE_INCOMING = { "Horde incoming!", "They're all coming!" }
calm.ZOMBIE_CLOSE = { "Infected, close.", "One's almost on us." }
aggressive.ZOMBIE_CLOSE = { "Deadhead, close!", "Get it off us!" }
calm.CRAWLER_SPOTTED = { "Crawler on the ground.", "Watch your feet, crawler." }
aggressive.CRAWLER_SPOTTED = { "Crawler!", "Watch the ground!" }
calm.HOUSE_INFESTED = { "This building is occupied.", "Infected inside." }
aggressive.HOUSE_INFESTED = { "Place is full of them.", "Dead inside!" }
calm.GRABBED = { "I've been grabbed!", "Get this thing off me!" }
aggressive.GRABBED = { "Get it off!", "It's got me!" }
calm.BITE_AVOIDED = { "That nearly bit me.", "Too close to its teeth." }
aggressive.BITE_AVOIDED = { "Almost got bitten!", "Damn thing nearly had me!" }
calm.CORPSE_FOUND = { "Body here.", "Found a corpse." }
aggressive.CORPSE_FOUND = { "Another body.", "Corpse over here." }
calm.AREA_OVERRUN = { "We can't hold this area.", "Too many infected here." }
aggressive.AREA_OVERRUN = { "We're overrun!", "There's too many!" }
calm.INFECTED_DOWN = { "Infected down.", "That one's finished." }
aggressive.INFECTED_DOWN = { "Deadhead down.", "Put it down." }

calm.ADVANCE = { "Advance carefully.", "Moving forward." }
aggressive.ADVANCE = { "Push up!", "Forward, now!" }
calm.FALL_BACK = { "Fall back in order.", "Give up some ground." }
aggressive.FALL_BACK = { "Back! Move!", "Fall back!" }
calm.HOLD_POSITION = { "Hold here.", "Keep this position." }
aggressive.HOLD_POSITION = { "Nobody moves!", "Hold this ground!" }
calm.REGROUP = { "Regroup on the others.", "Coming back to the group." }
aggressive.REGROUP = { "Group up!", "Get back together!" }
calm.MOVE_OUT = { "Let's move.", "Moving out." }
aggressive.MOVE_OUT = { "Move it!", "We're going!" }
calm.SPREAD_OUT = { "Give each other room.", "Spread the line." }
aggressive.SPREAD_OUT = { "Spread out!", "Stop bunching up!" }
calm.STACK_UP = { "Stack at the entrance.", "Form up on the door." }
aggressive.STACK_UP = { "Stack up!", "Get on that door!" }
calm.FLANK_START = { "Moving around their side.", "Starting a flank." }
aggressive.FLANK_START = { "Going around them!", "I'll hit their side!" }
calm.FLANK_COMPLETE = { "I'm on their flank.", "Side angle ready." }
aggressive.FLANK_COMPLETE = { "I've got their side!", "Flank is open!" }
calm.AMBUSH_READY = { "In position. Wait for it.", "Ambush is set." }
aggressive.AMBUSH_READY = { "Ready to spring it.", "Let them walk in." }
calm.PATROL_START = { "Starting the patrol.", "We'll check the area." }
aggressive.PATROL_START = { "Let's sweep the area.", "Patrol moving." }
calm.PATROL_CHECKPOINT = { "Checkpoint clear.", "Nothing at this stop." }
aggressive.PATROL_CHECKPOINT = { "This point is clear.", "Nothing here. Keep moving." }
calm.RAID_START = { "Raid begins now.", "Moving on the objective." }
aggressive.RAID_START = { "Hit them now!", "Raid starts here!" }
calm.RAID_RETREAT = { "Break off the raid.", "We're leaving the objective." }
aggressive.RAID_RETREAT = { "Abort it! Get out!", "Raid's over, move!" }

calm.HEARD_GUNSHOT = { "Gunshot nearby.", "I heard a weapon discharge." }
aggressive.HEARD_GUNSHOT = { "Shot nearby!", "Someone's shooting!" }
calm.HEARD_GLASS = { "Glass just broke.", "I heard a window." }
aggressive.HEARD_GLASS = { "Broken glass!", "Someone hit a window!" }
calm.HEARD_DOOR = { "Door movement nearby.", "I heard a door." }
aggressive.HEARD_DOOR = { "That door moved!", "Someone's at a door!" }
calm.HEARD_VOICE = { "I heard a voice.", "Someone spoke nearby." }
aggressive.HEARD_VOICE = { "I heard someone!", "There's a voice out there!" }
calm.HEARD_FOOTSTEPS = { "Footsteps.", "Someone is moving nearby." }
aggressive.HEARD_FOOTSTEPS = { "I hear footsteps!", "Someone's moving!" }
calm.HEARD_ALARM = { "Alarm sounding.", "That alarm will draw attention." }
aggressive.HEARD_ALARM = { "Alarm!", "That noise will bring everything!" }
calm.FOUND_BLOOD = { "Blood trail here.", "Fresh blood on the ground." }
aggressive.FOUND_BLOOD = { "Blood. They came this way.", "Found their blood." }
calm.FOUND_TRACKS = { "Tracks continue this way.", "Someone passed through." }
aggressive.FOUND_TRACKS = { "Tracks! Follow them.", "They went this way." }
calm.FOUND_BODY = { "Found a body.", "Body at this location." }
aggressive.FOUND_BODY = { "Body here!", "Someone died here." }
calm.AREA_CLEAR = { "Area appears clear.", "Nothing moving here." }
aggressive.AREA_CLEAR = { "Clear here.", "No targets." }
calm.SEARCH_SPLIT = { "Split the search sectors.", "Check separate angles." }
aggressive.SEARCH_SPLIT = { "Spread out and find them!", "Take different sides!" }
calm.SEARCH_COMPLETE = { "Search complete.", "No contact found." }
aggressive.SEARCH_COMPLETE = { "Nothing. Search is done.", "They're not here." }

calm.DOOR_LOCKED = { "Door is locked.", "This entrance won't open." }
aggressive.DOOR_LOCKED = { "Locked door!", "This thing is locked." }
calm.DOOR_OPENING = { "Opening the door.", "Going through this entrance." }
aggressive.DOOR_OPENING = { "Door opening!", "Going in!" }
calm.GATE_OPENING = { "Opening the gate.", "Gate is moving." }
aggressive.GATE_OPENING = { "Get the gate open!", "Opening this gate!" }
calm.GATE_STUCK = { "Gate is stuck.", "This gate isn't moving." }
aggressive.GATE_STUCK = { "Gate's jammed!", "This gate won't move!" }
calm.WINDOW_ENTRY = { "Entering through the window.", "Using the window." }
aggressive.WINDOW_ENTRY = { "Going through the window!", "Window entry!" }
calm.WINDOW_BREAK = { "Breaking the window.", "Glass coming down." }
aggressive.WINDOW_BREAK = { "Smashing it!", "Window coming in!" }
calm.VAULT_START = { "Going over.", "Crossing the obstacle." }
aggressive.VAULT_START = { "Over the top!", "Going over!" }
calm.VAULT_FAILED = { "Couldn't clear it.", "That crossing failed." }
aggressive.VAULT_FAILED = { "Didn't make it!", "Can't get over this!" }
calm.ENTER_BUILDING = { "Entering the building.", "Moving inside." }
aggressive.ENTER_BUILDING = { "Going inside!", "Entering now!" }
calm.EXIT_BUILDING = { "Leaving the building.", "Moving back outside." }
aggressive.EXIT_BUILDING = { "Coming out!", "Exiting!" }
calm.ROOM_CLEAR = { "Room clear.", "Nothing in this room." }
aggressive.ROOM_CLEAR = { "All clear in here!", "Room is empty!" }
calm.BREACH_FAILED = { "Breach failed.", "That opening held." }
aggressive.BREACH_FAILED = { "Didn't break!", "Breach failed!" }
calm.BARRICADE_START = { "Barricading this opening.", "Securing the entrance." }
aggressive.BARRICADE_START = { "Board this up!", "Barricading now!" }
calm.BARRICADE_DONE = { "Barricade is set.", "This opening is secured." }
aggressive.BARRICADE_DONE = { "Barricade done.", "That's sealed up." }
calm.BUILDING_SECURED = { "Building secured.", "We can hold here for now." }
aggressive.BUILDING_SECURED = { "Place is secure.", "This building is ours." }

calm.SCAVENGE_START = { "Searching for supplies.", "Starting a supply sweep." }
aggressive.SCAVENGE_START = { "Let's find something useful.", "Loot sweep starts now." }
calm.CONTAINER_SEARCH = { "Checking this container.", "Looking through here." }
aggressive.CONTAINER_SEARCH = { "Search this.", "Let's see what's inside." }
calm.FOUND_FOOD = { "Found food.", "Something edible here." }
aggressive.FOUND_FOOD = { "Food here.", "Found something to eat." }
calm.FOUND_WATER = { "Found water.", "Clean water here." }
aggressive.FOUND_WATER = { "Water.", "Got something to drink." }
calm.FOUND_AMMO = { "Ammunition found.", "Rounds here." }
aggressive.FOUND_AMMO = { "Ammo!", "Found rounds." }
calm.FOUND_WEAPON = { "Weapon found.", "This may be useful." }
aggressive.FOUND_WEAPON = { "Found a weapon.", "This will do." }
calm.FOUND_MEDICINE = { "Medical supplies.", "Found medicine." }
aggressive.FOUND_MEDICINE = { "Meds here.", "Found medical gear." }
calm.INVENTORY_FULL = { "I can't carry more.", "My load is full." }
aggressive.INVENTORY_FULL = { "I'm full up.", "Can't carry anything else." }
calm.LOOT_EMPTY = { "Nothing useful here.", "This place is empty." }
aggressive.LOOT_EMPTY = { "Picked clean.", "Nothing here." }
calm.RETURN_WITH_LOOT = { "Bringing supplies back.", "Returning with what I found." }
aggressive.RETURN_WITH_LOOT = { "Got supplies. Heading back.", "Bringing the haul in." }

calm.THIRSTY = { "I need some water.", "Getting thirsty." }
aggressive.THIRSTY = { "I need a drink.", "Running dry here." }
calm.HUNGRY = { "I should eat soon.", "Getting hungry." }
aggressive.HUNGRY = { "I need food.", "I'm starving here." }
calm.TIRED = { "I could use a rest.", "Starting to feel tired." }
aggressive.TIRED = { "I need a break.", "I'm getting tired." }
calm.EXHAUSTED = { "I need to stop and recover.", "I'm exhausted." }
aggressive.EXHAUSTED = { "I can't keep this pace!", "I'm spent!" }
calm.COLD = { "It's getting cold.", "I need somewhere warmer." }
aggressive.COLD = { "Freezing out here.", "I need some heat." }
calm.HOT = { "I'm overheating.", "Need to cool down." }
aggressive.HOT = { "It's too damn hot.", "I need to cool off." }
calm.WET = { "My clothes are soaked.", "I need to dry off." }
aggressive.WET = { "I'm soaked through.", "Need somewhere dry." }
calm.INJURED = { "This wound needs attention.", "I'm hurt." }
aggressive.INJURED = { "I'm messed up.", "This injury needs fixing." }
calm.NEED_MEDICINE = { "I need medical supplies.", "I should treat this." }
aggressive.NEED_MEDICINE = { "I need meds.", "Patch me up." }
calm.NEED_SMOKE = { "I could use a smoke.", "Might take a smoke when it's safe." }
aggressive.NEED_SMOKE = { "I need a cigarette.", "Could really use a smoke." }
calm.DRINK_START = { "Taking a drink.", "Stopping for water." }
aggressive.DRINK_START = { "Drinking now.", "I need this water." }
calm.DRINK_END = { "That's better.", "Water helped." }
aggressive.DRINK_END = { "Much better.", "Good. Moving on." }
calm.EAT_START = { "Eating something.", "Taking a moment to eat." }
aggressive.EAT_START = { "I'm eating.", "Food break." }
calm.EAT_END = { "Finished eating.", "That should keep me going." }
aggressive.EAT_END = { "Done eating.", "Good enough." }
calm.SMOKE_START = { "Taking a smoke.", "One minute for a cigarette." }
aggressive.SMOKE_START = { "Smoke break.", "I'm lighting one." }
calm.SMOKE_END = { "Smoke's done.", "All right, moving again." }
aggressive.SMOKE_END = { "That's enough.", "Back to it." }
calm.REST_START = { "Resting for a while.", "Taking time to recover." }
aggressive.REST_START = { "We're stopping here.", "I need this break." }
calm.REST_END = { "Rest is over.", "Ready to move again." }
aggressive.REST_END = { "Break's over.", "Back on our feet." }
calm.SQUAD_REST_CALLED = { "We'll rest once the building is secure.", "Find a safe room to recover in." }
aggressive.SQUAD_REST_CALLED = { "Secure a room. We're resting.", "Find us somewhere to stop." }
calm.SQUAD_REST_READY = { "The squad can rest here.", "This location is safe enough." }
aggressive.SQUAD_REST_READY = { "This place will do.", "We're resting here." }

calm.CHECK_IN = { "Everyone still with us?", "Status check." }
aggressive.CHECK_IN = { "Everyone alive?", "Sound off." }
calm.STATUS_OK = { "I'm all right.", "Still good here." }
aggressive.STATUS_OK = { "I'm good.", "Still standing." }
calm.ASK_AMMO = { "Does anyone have spare ammunition?", "I could use some rounds." }
aggressive.ASK_AMMO = { "Anyone got ammo?", "I need rounds." }
calm.GIVE_AMMO = { "I've got ammunition for you.", "Take these rounds." }
aggressive.GIVE_AMMO = { "Here, take this ammo.", "Rounds coming over." }
calm.ASK_MEDICAL = { "I need medical help.", "Can someone check this wound?" }
aggressive.ASK_MEDICAL = { "I need a medic!", "Someone patch me up!" }
calm.MEDIC_HELP = { "I'll treat you.", "Hold still, I'm helping." }
aggressive.MEDIC_HELP = { "Stay still.", "I'll fix it." }
calm.LEADER_ORDER = { "Listen for the next order.", "Follow the plan." }
aggressive.LEADER_ORDER = { "Do what I say.", "On me. I'll take the lead." }
calm.MEMBER_ACK = { "Understood.", "I hear you." }
aggressive.MEMBER_ACK = { "Got it.", "Yeah, I heard." }
calm.MEMBER_MISSING = { "We're missing someone.", "One member isn't here." }
aggressive.MEMBER_MISSING = { "Someone's missing.", "Where did they go?" }
calm.ALLY_FOUND = { "There you are.", "Found our missing member." }
aggressive.ALLY_FOUND = { "There you are!", "Finally caught up." }
calm.LEADER_DOWN = { "The leader is down.", "We need someone to take command." }
aggressive.LEADER_DOWN = { "Leader's down!", "Someone take charge!" }
calm.MORALE_HIGH = { "We're holding together.", "We can manage this." }
aggressive.MORALE_HIGH = { "We've got this.", "Keep the pressure on." }
calm.MORALE_LOW = { "We need to be careful.", "This is going badly." }
aggressive.MORALE_LOW = { "This is falling apart.", "We're in bad shape." }
calm.JOKE = { "At least the traffic is gone.", "Not exactly the life I planned." }
aggressive.JOKE = { "Great vacation spot.", "Could be worse. Probably will be." }

calm.WEATHER_RAIN = { "Rain's settling in.", "This weather will hide some noise." }
aggressive.WEATHER_RAIN = { "Here comes the rain.", "Great. More rain." }
calm.WEATHER_STORM = { "Storm is getting worse.", "We should find shelter." }
aggressive.WEATHER_STORM = { "This storm's ugly.", "Get us under a roof." }
calm.WEATHER_FOG = { "Visibility is poor.", "Fog is closing in." }
aggressive.WEATHER_FOG = { "Can't see a thing in this fog.", "Stay close in this soup." }
calm.NIGHTFALL = { "It'll be dark soon.", "Night is coming." }
aggressive.NIGHTFALL = { "Dark's coming fast.", "I hate moving at night." }
calm.DAWN = { "Morning's here.", "We made it to daylight." }
aggressive.DAWN = { "Finally, daylight.", "Morning already." }
calm.SAFE_MOMENT = { "Quiet for the moment.", "We have a little breathing room." }
aggressive.SAFE_MOMENT = { "Quiet. For now.", "Enjoy the silence while it lasts." }
calm.TENSE_SILENCE = { "It's too quiet.", "Keep listening." }
aggressive.TENSE_SILENCE = { "I don't like this silence.", "Something feels wrong." }
calm.HOME_MEMORY = { "I wonder if my old place is still standing.", "Feels like home was years ago." }
aggressive.HOME_MEMORY = { "I barely remember home now.", "Home feels like another life." }
calm.FOOD_MEMORY = { "I'd like a proper meal again.", "I miss fresh food." }
aggressive.FOOD_MEMORY = { "I'd kill for hot food.", "I'm sick of canned meals." }
calm.LOCATION_COMMENT = { "Let's remember this place.", "This area may be useful later." }
aggressive.LOCATION_COMMENT = { "Keep this place in mind.", "Could use this spot later." }
calm.LONG_WALK = { "We've covered a lot of ground.", "Still a long way to go." }
aggressive.LONG_WALK = { "Feels like we've walked all day.", "How much farther?" }
calm.AFTER_FIGHT = { "Take a breath and check yourself.", "Everyone count wounds and ammunition." }
aggressive.AFTER_FIGHT = { "Catch your breath.", "Check ammo before more show up." }

ProjectALife.ReactionLibrary = Library
return Library
