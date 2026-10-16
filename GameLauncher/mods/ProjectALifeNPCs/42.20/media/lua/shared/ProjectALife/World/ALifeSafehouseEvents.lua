ProjectALife = ProjectALife or {}

local Events = {
    tiers = { "h_hunted", "h_disliked", "h_unknown", "h_known", "h_trusted" },
    lanes = { "quiet", "visit", "lethal" },
    letterItem = "Base.SheetPaper2",
    lockedBy = "alife_letter",
}
ProjectALife.SafehouseEvents = Events

Events.mix = {
    h_hunted = { quiet = 35, visit = 15, lethal = 50 },
    h_disliked = { quiet = 50, visit = 25, lethal = 25 },
    h_unknown = { quiet = 60, visit = 30, lethal = 10 },
    h_known = { quiet = 65, visit = 32, lethal = 3 },
    h_trusted = { quiet = 70, visit = 30, lethal = 0 },
}

Events.rows = {
    { id = "beggar", lane = "visit", weight = 12, tiers = { "h_unknown", "h_known", "h_trusted" },
      tierWeight = { h_known = 1.5, h_trusted = 2 }, blocs = { "civilian", "family" }, hours = { 8, 18 }, region = "any", density = "low", count = { 1, 1 },
      cooldownDays = 4, outcomes = { plain = 100 }, deeds = { "gave_food" }, counters = { "talk_through_door", "do_not_answer" } },
    { id = "trader", lane = "visit", weight = 12, tiers = { "h_unknown", "h_known", "h_trusted" },
      tierWeight = { h_hunted = 0.3, h_disliked = 0.5, h_known = 1.5, h_trusted = 2 }, blocs = { "civilian", "family" }, hours = { 9, 17 }, region = "any", density = "low", count = { 1, 1 },
      cooldownDays = 4, outcomes = { plain = 100 }, deeds = { "fair_trade" }, tells = { "pay_first", "search_refused" },
      counters = { "search", "talk_through_door", "do_not_answer" } },
    { id = "law_stay_inside", lane = "visit", weight = 6, tiers = { "h_unknown", "h_known", "h_trusted" }, at = "window",
      blocs = { "law", "military" }, hours = { 8, 18 }, density = "low", count = { 1, 1 }, maxDay = 12,
      untilCollapse = true, needs = { "stationNear" }, cooldownDays = 4, outcomes = { plain = 100 },
      counters = { "talk_through_door", "do_not_answer" } },
    { id = "law_census", lane = "visit", weight = 6, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "law", "military" }, hours = { 8, 18 }, density = "low", count = { 1, 1 }, maxDay = 12,
      untilCollapse = true, needs = { "stationNear" }, cooldownDays = 4, outcomes = { plain = 100 }, deeds = { "census_answer" },
      counters = { "talk_through_door", "do_not_answer" } },
    { id = "sleep_one_night", lane = "visit", weight = 10, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 18, 21 }, region = "any", density = "low", count = { 1, 1 },
      needs = { "entryAllowed" }, cooldownDays = 5, outcomes = { reward = 30, betrayal = 10, trouble = 15, plain = 45 },
      guest = { untilHour = 7, turnHours = { 2, 4 }, squatHours = 48 }, effects = { "spawnsHostile" },
      tells = { "keeps_weapon", "asks_where_you_sleep" },
      deeds = { "let_sleep" }, counters = { "search", "weapons_down", "guest_leave", "lock_bedroom", "talk_through_door",
        "do_not_answer" } },
    { id = "chased", lane = "visit", weight = 8, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, region = "any", density = "low", count = { 1, 1 }, needs = { "entryAllowed" },
      cooldownDays = 6, outcomes = { reward = 60, trouble = 40 }, guest = { hours = 1, outcome = "sheltered_chased" },
      chasers = { 4, 6 }, decideSeconds = 20, effects = { "spawnsHostile" }, tells = { "zombies_behind" },
      counters = { "close_the_door", "guest_leave", "do_not_answer" }, deeds = { "sheltered_chased" } },
    { id = "wounded", lane = "visit", weight = 8, tiers = { "h_unknown", "h_known", "h_trusted" }, at = "window",
      blocs = { "civilian", "family", "law", "military" }, hours = { 6, 22 }, density = "low", count = { 1, 1 },
      cooldownDays = 5, asks = "ASK_MEDS", outcomes = { reward = 70, betrayal = 15, trouble = 15 },
      guest = { hours = 1, outcome = "rested" }, effects = { "spawnsHostile" }, tells = { "hides_wound", "no_blood_trail" },
      counters = { "search", "do_not_answer", "talk_through_door" }, deeds = { "treated_wounded" } },
    { id = "racket", lane = "visit", weight = 6, tiers = { "h_hunted", "h_disliked", "h_unknown" }, hostileOk = true,
      tierWeight = { h_hunted = 0.4, h_disliked = 0.7, h_known = 1.6, h_trusted = 2.2 }, blocs = { "crime", "club", "gang", "raider", "prison" }, hours = { 10, 16 }, density = "low", count = { 1, 1 },
      cooldownDays = 7, racket = { items = 3, paidDays = 7 }, outcomes = { plain = 100 }, effects = { "takesItems", "damages" },
      tells = { "polite_daylight" }, counters = { "pay_racket", "call_bluff", "prepare" } },
    { id = "neighbour", lane = "visit", weight = 6, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 9, 18 }, density = "low", count = { 1, 1 }, cooldownDays = 6,
      needs = { "grudgeNear" }, outcomes = { reward = 100 }, deeds = { "neighbour_watch" },
      counters = { "talk_through_door", "do_not_answer" } },
    { id = "returning_things", lane = "visit", weight = 4, tiers = { "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 9, 18 }, density = "low", count = { 1, 1 }, cooldownDays = 10,
      outcomes = { reward = 100 }, counters = { "talk_through_door", "do_not_answer" } },
    { id = "radio_rumour", lane = "visit", weight = 4, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 9, 19 }, density = "low", count = { 1, 1 }, cooldownDays = 8,
      needs = { "radioOn" }, outcomes = { plain = 100 }, deeds = { "kind_word" },
      counters = { "talk_through_door", "do_not_answer" } },
    { id = "drunk", lane = "visit", weight = 4, tiers = { "h_disliked", "h_unknown", "h_known" }, at = "window",
      blocs = { "civilian", "family" }, hours = { 20, 2 }, density = "low", count = { 1, 1 }, cooldownDays = 6,
      outcomes = { trouble = 100 }, lureMinutes = 30, lure = { 1, 3 }, effects = { "spawnsHostile" },
      tells = { "drunk_shouting" }, counters = { "send_away", "do_not_answer" } },
    { id = "preacher", lane = "visit", weight = 4, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 9, 18 }, density = "low", count = { 1, 1 }, cooldownDays = 7,
      outcomes = { plain = 100 }, counters = { "talk_through_door", "do_not_answer" } },
    { id = "medic_rounds", lane = "visit", weight = 4, tiers = { "h_known", "h_trusted" }, blocs = { "civilian", "family" },
      hours = { 9, 17 }, density = "low", count = { 1, 1 }, cooldownDays = 8, outcomes = { reward = 100 },
      counters = { "talk_through_door", "do_not_answer" } },
    { id = "messenger", lane = "visit", weight = 4, tiers = { "h_unknown", "h_known", "h_trusted" }, blocs = { "civilian", "family" },
      at = "window", hours = { 9, 17 }, density = "low", count = { 1, 1 }, cooldownDays = 8, needs = { "poiNear" }, outcomes = { reward = 100 },
      deeds = { "finished_job" }, job = { kind = "deliver", days = 5 }, counters = { "talk_through_door", "do_not_answer" } },
    { id = "neighbour_borrow", lane = "visit", weight = 4, tiers = { "h_unknown", "h_known", "h_trusted" }, blocs = { "civilian", "family" },
      tierWeight = { h_known = 1.5, h_trusted = 2 }, hours = { 9, 18 }, density = "low", count = { 1, 1 }, cooldownDays = 8, outcomes = { reward = 100 },
      counters = { "talk_through_door", "do_not_answer" } },
    { id = "law_guns", lane = "visit", weight = 3, tiers = { "h_unknown", "h_known", "h_trusted" }, blocs = { "law", "military" },
      hours = { 8, 18 }, density = "low", count = { 1, 1 }, maxDay = 14, untilCollapse = true, needs = { "stationNear" },
      cooldownDays = 8, outcomes = { plain = 100 }, effects = { "takesItems" }, tells = { "asks_for_weapons" },
      counters = { "stash_guns_locked", "talk_through_door", "do_not_answer" } },
    { id = "asks_help", lane = "visit", weight = 5, tiers = { "h_unknown", "h_known", "h_trusted" }, blocs = { "civilian", "family" },
      tierWeight = { h_known = 1.5, h_trusted = 2 }, at = "window", hours = { 8, 20 }, density = "low", count = { 1, 1 }, cooldownDays = 6, needs = { "poiNear" },
      outcomes = { reward = 60, betrayal = 30, trouble = 10 }, effects = { "spawnsHostile" }, deeds = { "answered_call" },
      job = { kind = "help", days = 3 }, tells = { "story_changes", "wants_gun_left" },
      counters = { "go_armed", "stop_and_look", "do_not_go" } },
    { id = "law_fake", lane = "visit", weight = 4, tiers = { "h_hunted", "h_disliked", "h_unknown" }, hostileOk = true,
      blocs = { "crime", "club", "gang", "raider", "prison" }, hours = { 8, 18 }, density = "low", count = { 1, 1 },
      maxDay = 20, cooldownDays = 7, outcomes = { betrayal = 100 }, effects = { "spawnsHostile" },
      tells = { "wrong_callsign" }, counters = { "ask_callsign", "close_the_door", "do_not_answer" } },
    { id = "family_in_need", lane = "visit", weight = 6, persons = true, tiers = { "h_unknown", "h_known", "h_trusted" },
      tierWeight = { h_known = 1.4, h_trusted = 1.8 }, blocs = { "civilian", "family" }, hours = { 8, 19 }, region = "any", density = "low", count = { 2, 3 },
      needs = { "entryAllowed" }, cooldownDays = 5, outcomes = { reward = 40, plain = 60 },
      guest = { hours = 1, outcome = "let_sleep", person = true, cap = 6 }, deeds = { "let_sleep" },
      counters = { "search", "weapons_down", "guest_leave", "talk_through_door", "do_not_answer" } },
    { id = "returning_guest", lane = "visit", weight = 5, persons = true, tiers = { "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 9, 19 }, region = "any", density = "low", count = { 1, 1 },
      needs = { "entryAllowed", "returningPerson" }, cooldownDays = 6, outcomes = { reward = 60, plain = 40 },
      guest = { hours = 1, outcome = "let_sleep", person = true, cap = 4 }, deeds = { "let_sleep" },
      counters = { "guest_leave", "talk_through_door", "do_not_answer" } },
    { id = "lodger_request", lane = "visit", weight = 4, persons = true, tiers = { "h_known", "h_trusted" },
      tierWeight = { h_trusted = 1.5 }, blocs = { "civilian", "family" }, hours = { 17, 21 }, region = "any", density = "low", count = { 1, 2 },
      needs = { "entryAllowed" }, cooldownDays = 8, outcomes = { reward = 30, plain = 70 },
      guest = { hours = 1, outcome = "let_sleep", person = true, cap = 24 }, deeds = { "let_sleep" },
      counters = { "search", "weapons_down", "guest_leave", "lock_bedroom", "talk_through_door", "do_not_answer" } },
    { id = "panic_knock", lane = "visit", weight = 5, persons = true, tiers = { "h_disliked", "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, region = "any", density = "low", count = { 1, 2 }, needs = { "entryAllowed" },
      cooldownDays = 7, outcomes = { reward = 60, trouble = 40 }, guest = { hours = 1, outcome = "sheltered_chased" },
      chasers = { 3, 5 }, decideSeconds = 20, effects = { "spawnsHostile" }, tells = { "zombies_behind" },
      counters = { "close_the_door", "guest_leave", "do_not_answer" }, deeds = { "sheltered_chased" } },
    { id = "weather_shelter", lane = "visit", weight = 5, persons = true, tiers = { "h_unknown", "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, region = "any", density = "low", count = { 1, 2 },
      needs = { "entryAllowed", "badWeather" }, cooldownDays = 4, outcomes = { reward = 40, plain = 60 },
      guest = { hours = 2, outcome = "let_sleep", person = true, cap = 6 }, deeds = { "let_sleep" },
      counters = { "search", "weapons_down", "guest_leave", "talk_through_door", "do_not_answer" } },
    { id = "medical_visit", lane = "visit", weight = 4, persons = true, tiers = { "h_known", "h_trusted" },
      blocs = { "civilian", "family" }, hours = { 7, 21 }, region = "any", density = "low", count = { 1, 2 },
      cooldownDays = 8, asks = "ASK_MEDS", outcomes = { reward = 100 }, guest = { hours = 1, outcome = "treated_wounded" },
      deeds = { "treated_wounded" }, counters = { "search", "guest_leave", "talk_through_door", "do_not_answer" } },
    { id = "letter_thanks", lane = "quiet", weight = 30, tiers = { "h_unknown", "h_known", "h_trusted" },
      needs = { "deed48h" }, cooldownDays = 2, outcomes = { reward = 25, plain = 75 }, letter = "letter_thanks" },
    { id = "letter_warning", lane = "quiet", weight = 15, tiers = { "h_known", "h_trusted" },
      needs = { "grudgeNear" }, cooldownDays = 4, outcomes = { plain = 100 }, letter = "letter_warning" },
    { id = "letter_threat", lane = "quiet", weight = 20, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge" }, ladder = 1, cooldownDays = 3, outcomes = { plain = 100 },
      tells = { "threat_text" }, counters = { "prepare", "move_stash", "gift_two_items" }, letter = "letter_threat" },
    { id = "letter_demand", lane = "quiet", weight = 12, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge" }, cooldownDays = 5, outcomes = { plain = 100 }, effects = { "takesItems" },
      demand = { min = 2, max = 3, cap = 5, days = 3 },
      tells = { "demand_text", "demand_deadline" }, counters = { "lock_containers", "move_stash", "pay_demand" },
      letter = "letter_demand" },
    { id = "letter_trade", lane = "quiet", weight = 15, tiers = { "h_unknown", "h_known", "h_trusted" },
      cooldownDays = 4, outcomes = { plain = 100 }, letter = "letter_trade" },
    { id = "map_honest", lane = "quiet", weight = 10, tiers = { "h_unknown", "h_known", "h_trusted" },
      needs = { "poiNear" }, cooldownDays = 6, outcomes = { plain = 100 }, letter = "map_honest" },
    { id = "letter_apology", lane = "quiet", weight = 10, tiers = { "h_disliked", "h_unknown" },
      needs = { "grudgeSoft" }, cooldownDays = 7, outcomes = { plain = 100 }, letter = "letter_apology" },
    { id = "missing_person", lane = "quiet", weight = 12, tiers = { "h_disliked", "h_unknown", "h_known", "h_trusted" },
      cooldownDays = 5, outcomes = { plain = 100 }, letter = "missing_person" },
    { id = "territory_notice", lane = "quiet", weight = 12, tiers = { "h_disliked", "h_unknown" }, hostileOk = true,
      cooldownDays = 5, outcomes = { plain = 100 }, letter = "territory_notice" },
    { id = "last_letter", lane = "quiet", weight = 6, cooldownDays = 7, outcomes = { plain = 100 }, letter = "last_letter" },
    { id = "gift", lane = "quiet", weight = 15, tiers = { "h_known", "h_trusted" },
      cooldownDays = 4, outcomes = { reward = 100 }, letter = "gift" },
    { id = "mark_paint_x", lane = "quiet", weight = 15, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge" }, ladder = 2, cooldownDays = 2, outcomes = { plain = 100 }, mark = "paint_x",
      tells = { "paint_near_door", "ladder_steps" }, counters = { "wash_off", "move_stash" } },
    { id = "sabotage", lane = "lethal", weight = 20, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge" }, ladder = 3, cooldownDays = 2, outcomes = { plain = 100 }, sabotage = { planks = 3, windows = 1 },
      effects = { "damages" }, tells = { "paint_near_door", "ladder_steps" }, counters = { "barricade_inside", "lock_containers" },
      notice = "Planks pried off the windows and glass on the ground. Someone worked on the house while you were out." },
    { id = "raid_night", lane = "lethal", weight = 20, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge" }, ladder = 4, hours = { 1, 4 }, cooldownDays = 7, outcomes = { plain = 100 }, raid = { waves = 2 },
      effects = { "spawnsHostile" }, tells = { "ladder_steps", "paint_near_door" },
      counters = { "locked_bedroom", "barricade_inside", "be_awake" } },
    { id = "raid_lure", lane = "lethal", weight = 15, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge" }, ladder = 4, hours = { 10, 20 }, cooldownDays = 7, outcomes = { plain = 100 },
      raid = { waves = 1, lureMinutes = 2 }, effects = { "spawnsHostile", "damages" }, tells = { "ladder_steps" },
      counters = { "kill_the_noise", "barricade_inside" } },
    { id = "raid_power", lane = "lethal", weight = 15, tiers = { "h_hunted", "h_disliked" }, hostileOk = true,
      needs = { "grudge", "generatorHome" }, ladder = 4, cooldownDays = 7, outcomes = { plain = 100 },
      raid = { waves = 2, powerCut = true }, effects = { "spawnsHostile", "damages" }, tells = { "ladder_steps" },
      counters = { "generator_indoors", "barricade_inside" } },
    { id = "raid_siege", lane = "lethal", weight = 10, tiers = { "h_hunted" }, hostileOk = true,
      needs = { "grudge" }, ladder = 4, cooldownDays = 10, outcomes = { plain = 100 }, raid = { waves = 3, waveDelayMinutes = 20 },
      effects = { "spawnsHostile" }, tells = { "ladder_steps" }, counters = { "second_exit", "barricade_inside" } },
    { id = "gas_siphoned", lane = "quiet", weight = 8, tiers = { "h_hunted", "h_disliked", "h_unknown" }, hostileOk = true,
      tierWeight = { h_hunted = 0.5, h_known = 1.5, h_trusted = 2 }, needs = { "tracesRecent" }, cooldownDays = 6, outcomes = { plain = 100 }, siphon = 25, effects = { "takesItems" },
      tells = { "camp_traces" }, counters = { "park_in_garage", "lock_gate" },
      notice = "The fuel tank is lower than you left it. Someone has been at it." },
    { id = "garden_raided", lane = "quiet", weight = 8, tiers = { "h_hunted", "h_disliked", "h_unknown" }, hostileOk = true,
      tierWeight = { h_hunted = 0.5, h_known = 1.5, h_trusted = 2 }, needs = { "tracesRecent" }, cooldownDays = 6, outcomes = { plain = 100 }, garden = 30, effects = { "takesItems" },
      tells = { "camp_traces" }, counters = { "fence_garden", "pick_ripe" },
      notice = "Your garden has been picked over. Someone took the ripe crops." },
    { id = "flashlight_window", lane = "quiet", weight = 6, cooldownDays = 4, outcomes = { plain = 100 }, hours = { 22, 4 },
      home = true, light = true, notice = "A flashlight beam sweeps your windows from outside, then goes out." },
    { id = "camp_traces", lane = "quiet", weight = 10, tiers = { "h_disliked", "h_unknown", "h_known" }, cooldownDays = 5,
      outcomes = { plain = 100 }, camp = { nights = { 1, 3 }, base = 4, perNight = 2, cap = 10, ring = 4, fireFrom = 2 },
      notice = "Empty cans and litter by the house. Someone watched this place for a night." },
    { id = "door_left_open", lane = "quiet", weight = 6, tiers = { "h_disliked", "h_unknown" }, cooldownDays = 6,
      outcomes = { plain = 100 }, opens = true, notice = "The front door stands open. You left it shut.",
      counters = { "lock_up" } },
    { id = "chalk_mark", lane = "quiet", weight = 8, tiers = { "h_unknown", "h_known", "h_trusted" }, cooldownDays = 7,
      outcomes = { plain = 100 }, mark = "chalk", counters = { "wash_off" } },
    { id = "tally_marks", lane = "quiet", weight = 6, tiers = { "h_hunted", "h_disliked" }, hostileOk = true, cooldownDays = 7,
      outcomes = { plain = 100 }, mark = "tally", counters = { "wash_off", "lights_in_rooms" } },
    { id = "faction_flag", lane = "quiet", weight = 4, tiers = { "h_disliked", "h_known", "h_trusted" }, hostileOk = true,
      cooldownDays = 10, outcomes = { plain = 100 }, mark = "flag", counters = { "wash_off" } },
    { id = "knock_nobody", lane = "quiet", weight = 6, cooldownDays = 3, outcomes = { plain = 100 }, hours = { 22, 4 },
      home = true, fx = "sound", sound = { names = { "ZombieThumpWood" }, cue = "knock_soft", count = 3, gapMs = 850, where = "door" },
      notice = "Three knocks at the door. When you look, nobody is there." },
    { id = "radio_chatter", lane = "quiet", weight = 6, tiers = { "h_disliked", "h_unknown", "h_known" }, cooldownDays = 6,
      outcomes = { plain = 100 }, needs = { "generatorHome" }, home = true, fx = "radio",
      notice = "On the radio someone talks about a house with a running generator. It sounds like yours.",
      counters = { "generator_indoors" } },
    { id = "distant_gunshot", lane = "quiet", weight = 5, cooldownDays = 3, outcomes = { plain = 100 }, home = true,
      scripted = true, fx = "sound",
      sound = { names = { "MetaPistol1", "MetaPistol2", "MetaPistol3" }, count = { 2, 4 }, gapMs = 1300, far = { 35, 70 } },
      notice = "Shots, far off. A few of them, then nothing." },
    { id = "dog_barking", lane = "quiet", weight = 5, cooldownDays = 3, outcomes = { plain = 100 }, hours = { 20, 6 },
      home = true, scripted = true, fx = "sound",
      sound = { names = { "MetaDogBark" }, count = { 3, 5 }, gapMs = 1800, far = { 20, 45 } },
      notice = "A dog barks somewhere out in the dark. It goes on for a while." },
    { id = "glass_breaks_near", lane = "quiet", weight = 3, cooldownDays = 5, outcomes = { plain = 100 }, hours = { 21, 5 },
      home = true, scripted = true, fx = "sound",
      sound = { names = { "SmashWindow" }, count = 1, far = { 8, 20 } },
      notice = "Glass breaks somewhere close. Then it is quiet again." },
    { id = "blood_smear", lane = "quiet", weight = 4, tiers = { "h_hunted", "h_disliked" }, hostileOk = true, scripted = true,
      needs = { "grudge" }, cooldownDays = 6, outcomes = { plain = 100 }, mark = "blood", counters = { "wash_off" } },
}

Events.mechanisms = {
    threat_text = { built = true, where = "letters.letter_threat: the letter itself" },
    demand_text = { built = true, where = "letters.letter_demand: the letter itself" },
    demand_deadline = { built = true, where = "letters.letter_demand: names the days to pay" },
    prepare = { built = true, where = "vanilla: barricade windows, lock doors" },
    move_stash = { built = true, where = "vanilla: move items to another container" },
    lock_containers = { built = true, where = "vanilla: locked doors and rooms (theft never touches locks)" },
    gift_two_items = { built = false, phase = "P2", where = "Director ladder: a gift steps the ladder down" },
    pay_demand = { built = false, phase = "P2", where = "Director.paid: items left at the drop point" },
    paint_near_door = { built = true, where = "SafehouseDirector mark paint_x: a notice and the door menu by the front door" },
    ladder_steps = { built = true, where = "house.ladder: threat letter, then the X, then sabotage, then the raid" },
    barricade_inside = { built = true, where = "vanilla: barricade from inside; sabotage only pries boards outside" },
    be_awake = { built = true, where = "vanilla: stay awake; the night raid comes at 01-04" },
    locked_bedroom = { built = true, where = "vanilla: a locked door a raider must break" },
    kill_the_noise = { built = true, where = "vanilla: the lure is loud for two minutes; leave by the quiet side or fence the yard" },
    second_exit = { built = true, where = "vanilla: a second way out; the siege watches the front" },
    asks_headcount = { built = false, phase = "P3", where = "VISIT_TELL_HEADCOUNT line pool" },
    looks_past_you = { built = false, phase = "P3", where = "door bark pool" },
    talk_through_door = { built = true, where = "SafehouseVisit.doorPeer" },
    do_not_answer = { built = true, where = "visit state at_door -> ignored" },
    search = { built = true, where = "SafehouseVisit.search open adjacent counter" },
    weapons_down = { built = true, where = "SafehouseVisit DOOR_WEAPONS_DOWN protected lease" },
    pay_first = { built = true, where = "SafehouseVisit.tradeQuote pay-first tell before any quote" },
    search_refused = { built = true, where = "SafehouseVisit.search refused inspection observation" },
    guest_leave = { built = true, where = "SafehouseVisit GUEST_LEAVE ends the guest lease; the guest walks out" },
    keeps_weapon = { built = true, where = "SafehouseVisit DOOR_WEAPONS_DOWN: a betrayer keeps his weapon in hand" },
    asks_where_you_sleep = { built = true, where = "SafehouseVisit DOOR_WHO: a betrayer asks which room you sleep in" },
    zombies_behind = { built = true, where = "SafehouseVisit.arrived: the chasers spawn behind the visitor at the door" },
    close_the_door = { built = true, where = "vanilla: a shut door; the visitor runs on when nobody lets him in" },
    hides_wound = { built = true, where = "SafehouseVisit.search: a bitten visitor refuses to show the wound" },
    no_blood_trail = { built = true, where = "SafehouseVisit.search: a fake wound shows no blood on the way he came" },
    polite_daylight = { built = true, where = "racket row hours 10-16 and the DOOR_WHO line" },
    pay_racket = { built = true, where = "SafehouseVisit DOOR_PAY: three real items buy seven quiet days" },
    call_bluff = { built = true, where = "SafehouseVisit DOOR_BLUFF: two residents at the door or a gun in hand" },
    drunk_shouting = { built = true, where = "SafehouseVisit DOOR_WHO and the arrival line: loud, slurring" },
    send_away = { built = true, where = "SafehouseVisit DOOR_LEAVE: the drunk staggers off before the noise draws the dead" },
    wrong_callsign = { built = true, where = "SafehouseVisit DOOR_CALLSIGN: a fake officer fumbles the callsign" },
    ask_callsign = { built = true, where = "SafehouseVisit DOOR_CALLSIGN through the closed door" },
    lock_up = { built = true, where = "vanilla: walk the house, shut and lock the doors" },
    wash_off = { built = true, where = "SafehouseClient door menu: wash the mark off (SafehouseDirector.wash), delays the ladder" },
    lights_in_rooms = { built = true, where = "vanilla: lights in more than one room" },
    generator_indoors = { built = true, where = "vanilla: move the generator indoors" },
    asks_for_weapons = { built = true, where = "SafehouseVisit DOOR_WHO: the officers say they are collecting weapons before you open" },
    stash_guns_locked = { built = true, where = "vanilla: nothing in your hands to hand over; guns in a locked room" },
    story_changes = { built = true, where = "SafehouseVisit DOOR_WHO asked twice: a false story is told differently the second time" },
    wants_gun_left = { built = true, where = "SafehouseVisit DOOR_WHO second answer: leave your gun behind" },
    go_armed = { built = true, where = "vanilla: go armed and in company" },
    stop_and_look = { built = true, where = "the ambushers wait at the place, in the open, and are seen from the approach" },
    do_not_go = { built = true, where = "SafehouseVisit: refusing the job costs nothing" },
    camp_traces = { built = true, where = "SafehouseDirector camp_traces: litter and the ashes of a small fire scattered round the front a few days before" },
    park_in_garage = { built = true, where = "vanilla: a car in a garage cannot be siphoned" },
    lock_gate = { built = true, where = "vanilla: a locked gate or a car out of the yard" },
    fence_garden = { built = true, where = "vanilla: fence the garden" },
    pick_ripe = { built = true, where = "vanilla: harvest ripe crops yourself, on time" },
    lock_bedroom = { built = true, where = "vanilla: a locked door; a guest never unlocks one and a hostile must break it" },
    scouts_seen = { built = false, phase = "P5", where = "RaidDirector.sendScouts" },
}

Events.letters = {
    letter_thanks = {
        title = "A note from {faction}",
        neutral = {
            "To {player}. You stood with our people when the dead came through. We will not forget it. - {faction}",
            "{player}, you did not have to help us out there. You did. Thank you. - {faction}",
            "Whoever lives here: {player} fought beside us. That counts for something with {faction}.",
        },
        good = {
            "{player}, friend. Our people told us what you did. Leave a light on and we will look in on you. - {faction}",
            "We owe you, {player}. If you ever need a hand, ask for {faction}.",
            "Thank you, {player}. We left this for you. Not much, but it is honest. - {faction}",
        },
    },
    letter_warning = {
        title = "A warning",
        neutral = {
            "{player}, {hostile} have been asking about this house. Keep your doors shut at night. - {faction}",
            "Heads up. {hostile} know where you sleep. We thought you should know. - {faction}",
            "We saw {hostile} on the road near here twice this week. Be careful, {player}. - {faction}",
        },
        good = {
            "{player}, a friend's warning: {hostile} are looking for you. Do not travel alone for a while. - {faction}",
            "{hostile} are talking about you. We would lock up and keep a bag packed. - {faction}",
            "Watch the road, {player}. {hostile} are close and they are not forgiving. - {faction}",
        },
    },
    letter_threat = {
        title = "Read this",
        bad = {
            "{player}. We know what you did to our people. We know this house. - {faction}",
            "You hurt one of ours, {player}. Think about that when you hear something outside. - {faction}",
            "This is the only letter you get, {player}. - {faction}",
        },
    },
    letter_demand = {
        title = "Terms",
        bad = {
            "{player}. {n} cans of food. Leave them by the door within {days} days and we forget your name. - {faction}",
            "{faction} want {n} cans of food for what you did, {player}. You have {days} days.",
            "Pay {n} cans of food, {player}, and this ends. {days} days. - {faction}",
        },
    },
    letter_trade = {
        title = "Trade",
        neutral = {
            "{faction} trade fair. Find our people on the roads around here and bring what you can spare.",
            "We have medicine and batteries. We want food and ammunition. Look for {faction}.",
            "No tricks, no ambush. {faction} trade with anyone who keeps the peace.",
        },
        good = {
            "{player}, {faction} will give you a good rate. Look for our people on the road.",
            "Friend, if you need anything, {faction} trade. You know where to find us.",
            "We kept something back for you, {player}. Come and trade. - {faction}",
        },
    },
    map_honest = {
        title = "Directions",
        neutral = {
            "About {dist} tiles {dir} of here there is a {place} nobody has cleared. We could not carry it all. - {faction}",
            "{place}, {dist} tiles {dir}. Mind the dead inside. - {faction}",
            "If you are short on supplies: {place}, {dist} tiles to the {dir}. Honest. - {faction}",
        },
    },
    letter_apology = {
        title = "About the trouble",
        neutral = {
            "{player}, what happened between your people and ours was a mistake. It will not happen again. - {faction}",
            "We are sorry for the trouble, {player}. Nobody wants another fight. - {faction}",
            "{faction} want peace with this house. That is all this letter says.",
        },
    },
    missing_person = {
        title = "Missing",
        neutral = {
            "MISSING: {name}. Last seen near {town}. If you see them, tell {faction}.",
            "Have you seen {name}? Brown coat, walks with a limp. Went toward {town} and never came back. - {faction}",
            "We are looking for {name}. If you find them, alive or not, we want to know. - {faction}",
        },
    },
    territory_notice = {
        title = "Notice",
        neutral = {
            "The roads around {town} belong to {faction}. Stay off them after dark.",
            "NOTICE: {faction} hold this area. Keep to your house and we keep to ours.",
            "This side of {town} is ours. Do not cross us. - {faction}",
        },
        bad = {
            "{faction} hold these roads. You are allowed here because we say so.",
            "This area belongs to {faction}. We are watching this house.",
            "Stay inside after dark. {faction} do not ask twice.",
        },
    },
    last_letter = {
        title = "A letter",
        neutral = {
            "To whoever finds this: tell {name} I made it as far as {town}. I tried.",
            "{name}, if this reaches you, I kept my promise until I could not. Do not wait for me.",
            "I left the car near {town}. The keys are under the seat. Someone should have it. - {name}",
        },
    },
    gift = {
        title = "For you",
        good = {
            "{player}, a small thing from {faction}. Stay safe.",
            "We had extra. You looked like you could use it. - {faction}",
            "For the house. From your friends at {faction}.",
        },
    },
}

Events.gifts = { "Base.TinnedBeans", "Base.TinnedSoup", "Base.CannedCorn", "Base.CannedPeas",
    "Base.Crackers", "Base.Bandage", "Base.PillsVitamins", "Base.Matches", "Base.Candle", "Base.Battery" }
Events.names = { "Anna Price", "Tom Walsh", "Rosie Hale", "Martin Doyle", "Beth Carver", "Luis Ortega",
    "June Barker", "Eddie Moss", "Clara Finch", "Ray Dalton" }

Events.traceGroups = { civilian = "civilian", family = "civilian", worker = "civilian", law = "law", military = "military",
    elite = "military", rescue = "rescue", crime = "rough", gang = "rough", raider = "rough", club = "rough", prison = "rough" }

Events.traceKinds = {
    civilian = { { "Base.TinCanEmpty", 4, 3 }, { "Base.PopEmpty", 3, 2 }, { "Base.Pop2Empty", 2, 2 }, { "Base.PaperBag", 2, 1 },
        { "Base.AnimalBone", 3, 3 }, { "Base.Matchbox", 1, 1 }, { "Base.Newspaper", 1, 1 }, { "Base.CigaretteSingle", 2, 3 },
        { "Base.Socks_Ankle", 1, 1 } },
    law = { { "Base.TinCanEmpty", 3, 2 }, { "Base.WaterRationCanEmpty", 3, 2 }, { "Base.PopEmpty", 2, 2 }, { "Base.Matchbox", 2, 1 },
        { "Base.CigaretteSingle", 3, 3 }, { "Base.Receipt", 2, 2 }, { "Base.Paperclip", 1, 1 }, { "Base.Pen", 1, 1 } },
    military = { { "Base.WaterRationCanEmpty", 4, 3 }, { "Base.TinCanEmpty", 3, 3 }, { "Base.Matchbox", 2, 1 },
        { "Base.CigaretteSingle", 3, 3 }, { "Base.BandageDirty", 2, 1 }, { "Base.CardDeck", 1, 1 } },
    rescue = { { "Base.BandageDirty", 4, 3 }, { "Base.RippedSheetsDirty", 2, 1 }, { "Base.TinCanEmpty", 3, 2 },
        { "Base.PopEmpty", 2, 2 }, { "Base.Plasticbag", 2, 1 }, { "Base.Matchbox", 1, 1 } },
    rough = { { "Base.BeerCanEmpty", 5, 4 }, { "Base.BeerEmpty", 4, 3 }, { "Base.CigaretteSingle", 4, 4 },
        { "Base.TinCanEmpty", 3, 2 }, { "Base.Dice", 1, 1 }, { "Base.CardDeck", 1, 1 }, { "Base.Matchbox", 1, 1 },
        { "Base.BandageDirty", 1, 1 } },
}

Events.traceFire = { "Base.Charcoal", "Base.Charcoal", "Base.Stone2", "Base.Charcoal", "Base.Stone2" }

function Events.traceGroup(bloc)
    return Events.traceGroups[tostring(bloc)] or "civilian"
end

function Events.tierWeight(row, tier)
    local weights = type(row) == "table" and row.tierWeight or nil
    local value = type(weights) == "table" and tonumber(weights[tier]) or nil
    if value == nil or value < 0 then return 1 end
    return value
end

function Events.row(id)
    for index = 1, #Events.rows do
        if Events.rows[index].id == id then return Events.rows[index] end
    end
    return nil
end

function Events.contains(list, value)
    if type(list) ~= "table" then return false end
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

function Events.hurts(row)
    if type(row) ~= "table" then return false end
    local outcomes = type(row.outcomes) == "table" and row.outcomes or {}
    if (tonumber(outcomes.betrayal) or 0) > 0 then return true end
    if type(row.effects) == "table" and #row.effects > 0 then return true end
    if row.lane == "lethal" or row.ladder ~= nil then return true end
    if type(row.troubles) == "table" then
        for index = 1, #row.troubles do
            local effects = type(row.troubles[index]) == "table" and row.troubles[index].effects or nil
            if type(effects) == "table" and #effects > 0 then return true end
        end
    end
    return false
end

function Events.shipCheck(rows, mechanisms)
    rows = rows or Events.rows
    mechanisms = mechanisms or Events.mechanisms
    local problems = {}
    for index = 1, #rows do
        local row = rows[index]
        local id = tostring(row and row.id)
        for _, field in ipairs({ "tells", "counters" }) do
            local ids = type(row[field]) == "table" and row[field] or {}
            for position = 1, #ids do
                if type(mechanisms[ids[position]]) ~= "table" then
                    problems[#problems + 1] = id .. ": " .. field .. " id '" .. tostring(ids[position]) .. "' has no mechanism"
                end
            end
        end
        if Events.hurts(row) then
            for _, field in ipairs({ "tells", "counters" }) do
                local ids = type(row[field]) == "table" and row[field] or {}
                local built = 0
                for position = 1, #ids do
                    local mechanism = mechanisms[ids[position]]
                    if type(mechanism) == "table" and mechanism.built == true then built = built + 1 end
                end
                if #ids == 0 then
                    problems[#problems + 1] = id .. ": can hurt the player and names no " .. field
                elseif built == 0 and (tonumber(row.weight) or 0) > 0 then
                    problems[#problems + 1] = id .. ": weight " .. tostring(row.weight) .. " with no built " .. field
                end
            end
        end
    end
    return #problems == 0, problems
end

function Events.shippable()
    local result = {}
    for index = 1, #Events.rows do
        local row = Events.rows[index]
        local ok = Events.shipCheck({ row })
        if ok then result[#result + 1] = row end
    end
    return result
end

return Events
