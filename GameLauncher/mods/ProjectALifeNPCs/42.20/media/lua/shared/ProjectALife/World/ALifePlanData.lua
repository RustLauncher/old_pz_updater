ProjectALife = ProjectALife or {}

local Data = {}
ProjectALife.PlanData = Data

Data.kinds = {
    "loot_building", "find_radio", "reach_safe_zone", "supply_run",
    "find_shelter", "check_on", "rest_at_shelter",
}

Data.goalKinds = {
    "loot_building", "find_radio", "reach_safe_zone", "supply_run", "find_shelter", "check_on",
}

Data.isKind = {}
for _, kind in ipairs(Data.kinds) do Data.isKind[kind] = true end

Data.lootKinds = { loot_building = true, find_radio = true, supply_run = true }
Data.stopKinds = { find_shelter = true, rest_at_shelter = true, reach_safe_zone = true }
Data.followUp = { loot_building = true, find_radio = true, supply_run = true, reach_safe_zone = false }

Data.modes = { roam = true, patrol = true, assault = true }

Data.stayFields = { "adminMode", "behavior", "encounter" }
Data.stayModes = {
    guard = true, camp = true, blockade = true, outpost = true, hold = true, assault_hold = true,
    poi_defenders = true, rooftop_snipers = true, checkpoint = true, car_crash = true, highway_ambush = true,
}

Data.steps = {
    loot_building = { "talk", "go", "work" },
    find_radio = { "talk", "go", "work" },
    reach_safe_zone = { "talk", "go", "stop" },
    supply_run = { "talk", "go", "work" },
    find_shelter = { "talk", "go", "stop" },
    check_on = { "talk", "go", "work" },
    rest_at_shelter = { "talk", "go", "stop" },
}

Data.defaults = {
    radius = 100, minRadius = 40, maxRadius = 200,
    lifespanHours = 6, minLifespan = 1, maxLifespan = 48,
    shelterLifespanHours = 12, restLifespanHours = 1.5,
    safeZoneLifespanFactor = 1.5,
    attempts = 2, offlineShare = 0.6,
    stopMinMinutes = 8, stopMaxMinutes = 22, stopMaxShare = 0.3,
    dangerFights = 2, injuryRatio = 0.45, timeoutsLimit = 2,
    duskHour = 19, nightStart = 22, nightEnd = 6,
}

Data.windows = {
    loot_building = { min = 20, max = 1.0 },
    find_radio = { min = 20, max = 1.0 },
    supply_run = { min = 20, max = 1.0 },
    reach_safe_zone = { min = 30, max = 1.0 },
    find_shelter = { min = 6, max = 0.6 },
    check_on = { min = 25, max = 1.0 },
    rest_at_shelter = { min = 3, max = 0.35 },
}

Data.timing = {
    agreeMs = 3200, commitMs = 6200, goMs = 8200, talkCapMs = 20000,
    soloGoMs = 2500, quietGoMs = 1500,
    legTiles = 28, legMs = 30000, progressMs = 25000, progressTiles = 3,
    arriveTiles = 7, arriveShelterTiles = 3, nearTiles = 30,
    workStallMs = 45000, workCapMs = 300000, observeMs = 18000,
    waitCapMs = 12000, waitRetryMs = 4000, workWaitCapMs = 20000,
    keptMs = 60000, scanTtlMs = 300000, scanCell = 64, rosterMs = 2000,
    fightGapMs = 15000, gapHours = 0.05, backoffMs = 20000, nightBackoffMs = 300000, claimMs = 600000, triedHours = 48,
    barkGapMs = 2000, sweepMs = 60000, staleMs = 300000, takeoverMs = 6000,
    laneSpacing = 1.6, ringRadius = 1.4, scanRoomCap = 900, scanCandidateCap = 160,
    fanDegrees = { 0, 25, -25, 50, -50 },
}

Data.classOfBloc = {
    family = "civilian", civilian = "civilian", rescue = "rescue", law = "law",
    military = "military", elite = "military", worker = "worker",
    raider = "raider", gang = "raider", club = "raider", crime = "raider", prison = "raider",
}

Data.classOfRegister = {
    family = "civilian", civilian = "civilian", rescue = "rescue", law = "law", swat = "law",
    military = "military", elite = "military", worker = "worker", outlaw = "raider",
    raider = "raider", gang = "raider", club = "raider", crime = "raider", prison = "raider",
}

Data.armedClass = { law = true, military = true, raider = true }

function Data.classOf(bloc, register)
    local key = string.lower(tostring(bloc or ""))
    if Data.classOfBloc[key] ~= nil then return Data.classOfBloc[key] end
    key = string.lower(tostring(register or ""))
    if Data.classOfRegister[key] ~= nil then return Data.classOfRegister[key] end
    return "civilian"
end

Data.classWeights = {
    civilian = { loot_building = 2.0, find_radio = 1.2, reach_safe_zone = 2.0, supply_run = 2.5, find_shelter = 1.5, check_on = 0.4 },
    rescue = { loot_building = 1.5, find_radio = 1.0, reach_safe_zone = 1.2, supply_run = 2.5, find_shelter = 1.0, check_on = 1.6 },
    law = { loot_building = 0.8, find_radio = 2.0, reach_safe_zone = 1.5, supply_run = 1.2, find_shelter = 0.8, check_on = 2.5 },
    military = { loot_building = 0.8, find_radio = 1.2, reach_safe_zone = 1.0, supply_run = 1.5, find_shelter = 0.6, check_on = 2.0 },
    raider = { loot_building = 3.5, find_radio = 0.4, reach_safe_zone = 0.0, supply_run = 3.0, find_shelter = 1.0, check_on = 1.0 },
    worker = { loot_building = 2.5, find_radio = 0.8, reach_safe_zone = 0.8, supply_run = 3.0, find_shelter = 1.0, check_on = 0.5 },
}

Data.tagBias = {
    civilian = { house = 1.3, grocery = 1.2, medical = 1.2 },
    rescue = { medical = 1.8, fire = 1.2, church = 1.2 },
    law = { police = 1.5, guns = 1.1, radio = 1.2 },
    military = { military = 1.6, guns = 1.3, police = 1.1 },
    raider = { guns = 1.6, military = 1.4, medical = 1.2, store = 1.2, police = 0.8 },
    worker = { hardware = 1.8, gas = 1.5, warehouse = 1.4 },
}

Data.lootValue = {
    medical = 8, grocery = 8, gas = 6, hardware = 7, guns = 9, military = 9, police = 7,
    store = 5, warehouse = 6, school = 4, church = 3, restaurant = 5, radio = 4,
    electronics = 5, house = 3, fire = 4, motel = 4,
}

Data.radioValue = {
    radio = 10, electronics = 7, police = 6, military = 6, school = 2, store = 2,
    house = 1.5, church = 1, warehouse = 1.5,
}

Data.radioChance = {
    radio = 0.85, electronics = 0.6, police = 0.55, military = 0.55, school = 0.2,
    store = 0.2, house = 0.12, church = 0.1, warehouse = 0.12,
}

Data.shelterValue = {
    house = 6, church = 5, police = 7, school = 3, warehouse = 4, motel = 4, fire = 4,
    grocery = 2, store = 1.5, restaurant = 2, medical = 3, military = 5, hardware = 3, gas = 2,
}

Data.safeValue = { medical = 8, police = 7, military = 9, fire = 6, church = 5, school = 3 }

Data.wantValue = {
    food = { grocery = 10, restaurant = 7, store = 4, house = 3, church = 2, school = 3 },
    water = { grocery = 8, restaurant = 6, gas = 6, house = 3, store = 4 },
    fuel = { gas = 10, hardware = 5, warehouse = 4, store = 1 },
    meds = { medical = 10, fire = 4, police = 3, house = 2, school = 2, store = 2 },
    ammo = { guns = 10, military = 9, police = 8, house = 1 },
    tools = { hardware = 10, warehouse = 6, gas = 4, house = 1.5 },
}

Data.scavengeWanted = {
    food = "food", water = "water", fuel = "tools", meds = "medical", ammo = "ammo", tools = "tools",
}

Data.exactTags = {
    bar = "restaurant", barstorage = "restaurant", barkitchen = "restaurant", barcountertwiggy = "restaurant",
    kitchen = "house", bathroom = "house", bedroom = "house", livingroom = "house", kidsbedroom = "house",
}

Data.prefixTags = {
    { "fire", "fire" },
}

Data.roomTags = {
    { "pharmac", "medical" }, { "hospital", "medical" }, { "medical", "medical" }, { "dentist", "medical" },
    { "clinic", "medical" }, { "laborator", "medical" }, { "morgue", "medical" },
    { "gunstore", "guns" }, { "hunting", "guns" }, { "hunterstorage", "guns" },
    { "armystorage", "military" }, { "armysurplus", "military" }, { "armytent", "military" },
    { "oldarmy", "military" }, { "swatlocker", "military" },
    { "police", "police" }, { "prison", "police" }, { "evidence", "police" }, { "interrogation", "police" },
    { "detective", "police" }, { "captainoffice", "police" }, { "ranger", "police" }, { "sherrif", "police" },
    { "radio", "radio" }, { "studio", "radio" }, { "controlroom", "radio" },
    { "electronic", "electronics" }, { "camerastore", "electronics" }, { "cybercafe", "electronics" },
    { "grocery", "grocery" }, { "gigamart", "grocery" }, { "conveniencestore", "grocery" },
    { "cornerstore", "grocery" }, { "generalstore", "grocery" }, { "bakery", "grocery" },
    { "butcher", "grocery" }, { "produce", "grocery" }, { "candystore", "grocery" }, { "liquorstore", "grocery" },
    { "restaurant", "restaurant" }, { "diner", "restaurant" }, { "cafe", "restaurant" },
    { "pizza", "restaurant" }, { "burger", "restaurant" }, { "spiffo", "restaurant" },
    { "donut", "restaurant" }, { "icecream", "restaurant" }, { "jayschicken", "restaurant" },
    { "catfish", "restaurant" }, { "sushi", "restaurant" }, { "chinese", "restaurant" },
    { "mexican", "restaurant" }, { "italian", "restaurant" }, { "fishchips", "restaurant" },
    { "gasstore", "gas" }, { "gasstorage", "gas" }, { "gas2go", "gas" }, { "fossoil", "gas" },
    { "zippee", "gas" }, { "mechanic", "gas" }, { "carsupply", "gas" },
    { "toolstore", "hardware" }, { "hardware", "hardware" }, { "construction", "hardware" },
    { "carpentry", "hardware" }, { "welding", "hardware" }, { "metalshop", "hardware" },
    { "metalfab", "hardware" }, { "outdoorsupply", "hardware" }, { "camping", "hardware" },
    { "blacksmith", "hardware" },
    { "classroom", "school" }, { "school", "school" }, { "library", "school" }, { "daycare", "school" },
    { "cafeteria", "school" },
    { "church", "church" },
    { "motelroom", "motel" },
    { "warehouse", "warehouse" }, { "storageunit", "warehouse" }, { "factory", "warehouse" },
    { "clothes", "store" }, { "clothing", "store" }, { "bookstore", "store" }, { "giftstore", "store" },
    { "sportstore", "store" }, { "departmentstore", "store" }, { "pawnshop", "store" },
    { "toystore", "store" }, { "jewelry", "store" }, { "florist", "store" }, { "petstore", "store" },
    { "musicstore", "store" }, { "furniturestore", "store" },
}

function Data.tagOfRoom(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lowered = string.lower(name)
    local exact = Data.exactTags[lowered]
    if exact ~= nil then return exact end
    for index = 1, #Data.prefixTags do
        local row = Data.prefixTags[index]
        if string.sub(lowered, 1, #row[1]) == row[1] then return row[2] end
    end
    for index = 1, #Data.roomTags do
        local row = Data.roomTags[index]
        if string.find(lowered, row[1], 1, true) ~= nil then return row[2] end
    end
    return nil
end

Data.tagLabels = {
    medical = "the clinic", guns = "the gun store", military = "that army post", police = "the police station",
    fire = "the fire station", radio = "the radio station", electronics = "the electronics store",
    grocery = "the grocery", restaurant = "the diner", gas = "the gas station", hardware = "the hardware store",
    school = "the school", church = "the church", motel = "the motel", warehouse = "the warehouse",
    store = "that store", house = "that house",
}

Data.labelWords = {
    { "pharmac", "the pharmacy" }, { "hospital", "the hospital" }, { "dentist", "the dentist's office" },
    { "gunstore", "the gun store" }, { "armysurplus", "the army surplus" },
    { "prison", "the jail" }, { "police", "the police station" }, { "sherrif", "the sheriff's office" },
    { "studio", "the radio station" }, { "controlroom", "the radio station" }, { "radiofactory", "the radio factory" },
    { "electronic", "the electronics store" }, { "gigamart", "the Gigamart" },
    { "conveniencestore", "the convenience store" }, { "cornerstore", "the corner store" },
    { "generalstore", "the general store" }, { "bakery", "the bakery" }, { "butcher", "the butcher's" },
    { "liquorstore", "the liquor store" }, { "grocery", "the grocery" },
    { "restaurant", "the restaurant" },
    { "pizza", "the pizza place" }, { "burger", "the burger joint" }, { "spiffo", "the Spiffo's" },
    { "donut", "the donut shop" }, { "cafe", "the cafe" }, { "diner", "the diner" },
    { "gas2go", "the Gas2Go" }, { "fossoil", "the Fossoil" }, { "zippee", "the Zippee Mart" },
    { "gasstore", "the gas station" }, { "mechanic", "the garage" },
    { "toolstore", "the hardware store" }, { "hardware", "the hardware store" },
    { "construction", "the construction yard" }, { "library", "the library" },
    { "classroom", "the school" }, { "school", "the school" }, { "church", "the church" },
    { "motelroom", "the motel" }, { "storageunit", "the storage units" },
}

function Data.labelFor(tag, names)
    if type(names) == "table" then
        for index = 1, #Data.labelWords do
            local row = Data.labelWords[index]
            for name in pairs(names) do
                if string.find(name, row[1], 1, true) ~= nil then
                    if Data.tagOfRoom(name) == tag or tag == nil then return row[2] end
                end
            end
        end
    end
    return Data.tagLabels[tag] or "that place"
end

function Data.capital(text)
    text = tostring(text or "")
    if text == "" then return text end
    return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

function Data.render(line, vars)
    line = tostring(line or "")
    vars = type(vars) == "table" and vars or {}
    local target = tostring(vars.target or "somewhere")
    line = string.gsub(line, "{Target}", function() return Data.capital(target) end)
    line = string.gsub(line, "{target}", function() return target end)
    return line
end

function Data.urgency(value)
    local x = tonumber(value)
    if x == nil or x >= 40 then return 0 end
    local share = (40 - math.max(0, x)) / 40
    return share * share
end

Data.needOrder = { "food", "water", "ammo", "meds" }

function Data.lowestNeed(needs)
    local best, value = nil, math.huge
    if type(needs) ~= "table" then return nil, 100 end
    for _, need in ipairs(Data.needOrder) do
        local x = tonumber(needs[need])
        if x ~= nil and x < value then best, value = need, x end
    end
    return best, value
end

function Data.dayFactor(kind, class, day)
    day = tonumber(day) or 0
    local civil = class == "civilian" or class == "rescue" or class == "worker"
    if kind == "reach_safe_zone" then
        if not civil and class ~= "law" then return 1 end
        if day <= 2 then return 2.0 end
        if day <= 7 then return 1.5 end
        if day <= 20 then return 1.0 end
        return 0.35
    elseif kind == "find_radio" then
        if day <= 6 then return 1.5 end
        if day <= 30 then return 1.0 end
        return 0.6
    elseif kind == "loot_building" then
        if day <= 2 then return 0.8 end
        if day >= 15 then return 1.3 end
        return 1.0
    elseif kind == "supply_run" then
        if day <= 2 then return 0.7 end
        if day >= 20 then return 1.5 end
        return 1.0
    elseif kind == "find_shelter" then
        if day <= 3 then return 1.5 end
        return 1.0
    end
    return 1.0
end

function Data.needFactor(kind, facts)
    local needs = type(facts.needs) == "table" and facts.needs or {}
    local health = tonumber(facts.health) or 1
    if kind == "supply_run" then
        local worst = math.max(Data.urgency(needs.food), Data.urgency(needs.water))
        if Data.armedClass[facts.class] == true then worst = math.max(worst, Data.urgency(needs.ammo)) end
        return 1 + 3 * worst
    elseif kind == "loot_building" then
        return 1 + 2 * Data.urgency(needs.meds)
    elseif kind == "find_shelter" then
        if health < 0.6 then return 1 + 2 * (0.6 - health) / 0.6 end
        return 1
    end
    return 1
end

function Data.hourFactor(kind, hour)
    hour = tonumber(hour) or 12
    if kind == "find_shelter" then
        if hour >= Data.defaults.duskHour and hour < Data.defaults.nightStart then
            return 1 + (hour - Data.defaults.duskHour + 1) * 0.9
        end
        return 1
    end
    if hour >= Data.defaults.duskHour and hour < Data.defaults.nightStart then return 0.6 end
    return 1
end

function Data.isNightHour(hour)
    hour = tonumber(hour) or 12
    return hour >= Data.defaults.nightStart or hour < Data.defaults.nightEnd
end

function Data.weights(facts, blocked)
    facts = type(facts) == "table" and facts or {}
    blocked = type(blocked) == "table" and blocked or {}
    local row = Data.classWeights[facts.class] or Data.classWeights.civilian
    local list, total = {}, 0
    if facts.night == true or Data.isNightHour(facts.hour) then
        if blocked.find_shelter ~= true then list[1] = { kind = "find_shelter", weight = 1 }; total = 1 end
        return list, total
    end
    for _, kind in ipairs(Data.goalKinds) do
        if blocked[kind] ~= true then
            local weight = (row[kind] or 0) * Data.dayFactor(kind, facts.class, facts.day)
                * Data.needFactor(kind, facts) * Data.hourFactor(kind, facts.hour)
            if weight > 0 then
                list[#list + 1] = { kind = kind, weight = weight }
                total = total + weight
            end
        end
    end
    return list, total
end

function Data.pickKind(facts, blocked, roll)
    local list, total = Data.weights(facts, blocked)
    if total <= 0 then return nil end
    local point = (tonumber(roll) or 0) * total
    local cursor = 0
    for index = 1, #list do
        cursor = cursor + list[index].weight
        if point < cursor then return list[index].kind end
    end
    return list[#list].kind
end

function Data.wantFor(kind, facts)
    local needs = type(facts) == "table" and facts.needs or nil
    if kind == "supply_run" then
        local need = Data.lowestNeed(needs)
        if Data.armedClass[facts.class] ~= true and need == "ammo" then
            need = Data.lowestNeed({ food = needs.food, water = needs.water, meds = needs.meds })
        end
        local value = type(needs) == "table" and tonumber(needs[need]) or 100
        if facts.class == "worker" and Data.urgency(value) < 0.15 then return "fuel" end
        return need or "food"
    elseif kind == "loot_building" then
        if type(needs) == "table" and Data.urgency(needs.meds) > 0.25 then return "meds" end
    end
    return nil
end

function Data.valuesFor(kind, want)
    if kind == "find_radio" then return Data.radioValue end
    if kind == "find_shelter" or kind == "rest_at_shelter" then return Data.shelterValue end
    if kind == "reach_safe_zone" then return Data.safeValue end
    if (kind == "supply_run" or kind == "loot_building") and want ~= nil and Data.wantValue[want] ~= nil then
        return Data.wantValue[want]
    end
    return Data.lootValue
end

function Data.windowFor(kind, radius)
    local window = Data.windows[kind] or Data.windows.loot_building
    return window.min, math.max(window.min + 5, math.floor(radius * window.max))
end

function Data.scoreCandidate(kind, class, want, candidate, distance, radius)
    local values = Data.valuesFor(kind, want)
    local bias = Data.tagBias[class] or {}
    local best, bestTag = 0, nil
    for tag in pairs(candidate.tags or {}) do
        local value = values[tag]
        if value ~= nil then
            value = value * (bias[tag] or 1)
            if value > best then best, bestTag = value, tag end
        end
    end
    if bestTag == nil then return nil, nil end
    local rooms = tonumber(candidate.rooms) or 1
    local shelter = kind == "find_shelter" or kind == "rest_at_shelter"
    if shelter then
        if rooms > 12 then best = best - (rooms - 12) * 0.2 end
    elseif kind ~= "reach_safe_zone" then
        best = best + math.min(2, (rooms - 1) * 0.15)
        if candidate.visited == true then best = best - 1.5 end
    end
    local _, maximum = Data.windowFor(kind, radius)
    best = best - (tonumber(distance) or 0) / maximum * 3
    return best, bestTag
end

function Data.rankCandidates(list)
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

function Data.pickRanked(list, roll)
    local count = math.min(3, #list)
    if count == 0 then return nil end
    local weights = { 3, 2, 1 }
    local total = 0
    for index = 1, count do total = total + weights[index] end
    local point = (tonumber(roll) or 0) * total
    local cursor = 0
    for index = 1, count do
        cursor = cursor + weights[index]
        if point < cursor then return list[index], index end
    end
    return list[count], count
end

function Data.stopMinutes(activeMinutes, roll)
    local d = Data.defaults
    local base = d.stopMinMinutes + (d.stopMaxMinutes - d.stopMinMinutes) * (tonumber(roll) or 0)
    local share = d.stopMaxShare
    local cap = (tonumber(activeMinutes) or 0) * share / (1 - share)
    return math.max(d.stopMinMinutes * 0.5, math.min(base, math.max(cap, d.stopMinMinutes * 0.5)))
end

function Data.lifespanFor(kind, base)
    local d = Data.defaults
    base = tonumber(base) or d.lifespanHours
    if kind == "find_shelter" then return math.max(base, d.shelterLifespanHours) end
    if kind == "rest_at_shelter" then return d.restLifespanHours end
    if kind == "reach_safe_zone" then return base * d.safeZoneLifespanFactor end
    return base
end

Data.lines = {
    loot_building = {
        propose = { "{Target} first, then we move", "Bet nobody's been through {target} yet",
            "I'd rather look in {target} than stand around wishing we'd tried" },
        agree = { "Yeah, that works", "Fine by me, I'm sick of walking in circles" },
        commit = { "Right, {target}, and keep it quiet", "Come on, we're doing {target}, nobody wanders off" },
        arrive = { "This is it, try the doors before you go in", "Quiet now, I'll take the front" },
        done = { "That's as long as I'm willing to keep looking", "We've spent enough time here, let's not hang around" },
    },
    find_radio = {
        propose = { "Maybe we can find a radio somewhere around here", "Somebody's gotta be broadcasting, we need a radio",
            "{Target} might have a radio, worth a look" },
        agree = { "Anything beats not knowing what's going on", "Yeah, I wanna hear somebody else's voice for once" },
        commit = { "Let's go, {target}, and watch for anything with an antenna", "Move out, we're checking {target} for a radio" },
        arrive = { "Have a proper look before you decide there's nothing useful", "Look for a dial or a cord, anything" },
        found = { "Might be worth another look before we give up", "Let's check carefully. I want something we can actually rely on" },
        empty = { "I don't have an answer I trust yet, damn it", "Not ready to call that a success" },
        done = { "Okay, that's enough of that", "We looked, that's all we can do" },
    },
    reach_safe_zone = {
        propose = { "We can't just sit here, they said {target} is still holding", "{Target}, that's where everybody says to go",
            "I heard they're taking people in at {target}" },
        agree = { "Better than waiting for the dead to find us", "Hell, I'll go, I ain't staying put" },
        commit = { "Pack up, we're heading for {target}", "We go now, before it gets dark" },
        arrive = { "Well, we made it, now we see who's here", "Stay together, nobody shoots first" },
        done = { "Let's take a moment and think about what comes next", "We'll see if anybody's actually in charge here" },
    },
    supply_run = {
        propose = { "I'd like to look in {target}, see whether there's anything useful", "Gotta find food, anything, maybe {target}",
            "I'd rather think about supper. What about trying {target}?" },
        agree = { "Yeah, I'm tired of talking about food instead of finding it", "Good, I could eat a horse" },
        commit = { "Let's hit {target}, take what we can carry", "{Target}, then straight back out, no sightseeing" },
        arrive = { "Grab what's useful, leave the junk", "Be quick about it" },
        done = { "Let's not make our next plan on a guess", "Whatever we do next, I'd rather we stick together" },
    },
    find_shelter = {
        propose = { "It's getting late, we need a roof, {target} maybe", "I don't wanna be outside when it gets dark",
            "Let's have a look at {target}, see whether we could stay there" },
        agree = { "Yeah, one with a lock", "Fine, but I'm checking every room first" },
        commit = { "Come on, {target}, before the light's gone", "We board up {target} and sit tight till morning" },
        arrive = { "Check the place before anybody settles down", "Don't rush just because you want to stop" },
        done = { "We're staying put till morning", "Somebody take first watch" },
    },
    check_on = {
        propose = { "I wonder who's still around. Could we check {target}?", "I'd like to look toward {target}, see what's there",
            "Let's go see what that was" },
        agree = { "Slowly, though", "Could be trouble, could be people, I wanna know" },
        commit = { "Stay behind me, we're just looking", "Just looking, nobody touches anything" },
        arrive = { "Keep low and watch the road", "Nobody say a word" },
        done = { "Nothing we can do about it, let's go", "Alright, I've seen enough" },
    },
    rest_at_shelter = {
        propose = { "My feet are killing me, let's sit down a minute", "Let's find somewhere to take a break",
            "Can we stop somewhere, I'm done" },
        agree = { "God, yes", "Finally, I thought you'd never ask" },
        commit = { "{Target}, ten minutes, then we move", "We rest in {target} and then we go" },
        arrive = { "Sit down and shut up for a minute", "Somebody keep a lookout" },
        done = { "Okay, break's over", "Up, let's go" },
    },
    abandon = {
        blocked = { "Forget it, we can't get to {target}", "This isn't working, we try something else" },
        danger = { "Screw this, not now", "Too hot, we'll come back to it" },
        injury = { "We need to stop and see how everyone's doing first", "Hold up, I want a moment before we go any farther" },
        looted = { "I'd rather look somewhere we haven't tried", "We've given this place enough time" },
        target_gone = { "That plan isn't working. We need another way" },
        expired = { "We've been at this too long, new plan" },
        protected = { "That place belongs to somebody, leave it" },
    },
}

function Data.line(kind, phase, index)
    local row = Data.lines[kind]
    local list = row ~= nil and row[phase] or nil
    if type(list) ~= "table" or #list == 0 then return nil end
    local at = (math.floor(tonumber(index) or 0) % #list) + 1
    return list[at]
end

function Data.abandonLine(reason, index)
    local list = Data.lines.abandon[reason]
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[(math.floor(tonumber(index) or 0) % #list) + 1]
end

Data.farPlaces = {
    { id = "louisville", name = "Louisville", x = 12600, y = 1800, safe = true },
}

return Data
