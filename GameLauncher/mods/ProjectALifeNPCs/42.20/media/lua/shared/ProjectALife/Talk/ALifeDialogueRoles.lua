ProjectALife = ProjectALife or {}

local Roles = {}
ProjectALife.DialogueRoles = Roles

Roles.definitions = {
    family_man = { label = "Family - Man", register = "family", temperament = "fresh", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    family_woman = { label = "Family - Woman", register = "family", temperament = "fresh", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    family_elder = { label = "Family - Elder", register = "family", temperament = "seasoned", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    family_youth = { label = "Family - Young Adult", register = "family", temperament = "fresh", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    civilian_man = { label = "Civilian - Survivor", register = "civilian", temperament = "fresh", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    civilian_woman = { label = "Civilian - Survivor Woman", register = "civilian", temperament = "fresh", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    civilian_loner = { label = "Civilian - Loner", register = "civilian", temperament = "seasoned", male = "pal_experienced", female = "pal_foreign_female_survivor" },
    worker = { label = "Worker", register = "worker", temperament = "seasoned", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    rescue_firefighter = { label = "Rescue - Firefighter", register = "rescue", temperament = "seasoned", male = "pal_experienced", female = "pal_american_female_survivor" },
    rescue_medical = { label = "Rescue - Medical", register = "rescue", temperament = "seasoned", male = "pal_scientist", female = "pal_american_female_survivor" },
    rescue_clergy = { label = "Rescue - Clergy", register = "rescue", temperament = "seasoned", male = "pal_american_survivor", female = "pal_american_female_survivor" },
    law_deputy = { label = "Law Enforcement - Deputy Sheriff", register = "law", temperament = "seasoned", male = "pal_law_enforcement_operator", female = "pal_american_female_survivor" },
    law_sheriff = { label = "Law Enforcement - Sheriff", register = "law", temperament = "veteran", male = "pal_law_enforcement_team_lead", female = "pal_american_female_survivor" },
    law_officer = { label = "Law Enforcement - Police Officer", register = "law", temperament = "seasoned", male = "pal_law_enforcement_operator", female = "pal_american_female_survivor" },
    law_sergeant = { label = "Law Enforcement - Sergeant", register = "law", temperament = "veteran", male = "pal_law_enforcement_team_lead", female = "pal_american_female_survivor" },
    law_trooper = { label = "Law Enforcement - State Trooper", register = "law", temperament = "veteran", male = "pal_law_enforcement_operator", female = "pal_american_female_survivor" },
    law_corrections = { label = "Law Enforcement - Corrections Officer", register = "law", temperament = "seasoned", male = "pal_law_enforcement_operator", female = "pal_american_female_survivor" },
    swat_lead = { label = "Law Enforcement - SWAT Team Leader", register = "swat", temperament = "veteran", male = "pal_law_enforcement_team_lead", female = "pal_american_female_survivor" },
    swat_operator = { label = "Law Enforcement - SWAT Operator", register = "swat", temperament = "veteran", male = "pal_law_enforcement_operator", female = "pal_american_female_survivor" },
    soldier = { label = "Military - Soldier", register = "military", temperament = "seasoned", male = "pal_military", female = "pal_american_female_survivor" },
    soldier_nco = { label = "Military - Sergeant", register = "military", temperament = "veteran", male = "pal_military", female = "pal_american_female_survivor" },
    soldier_green = { label = "Military - Trainee", register = "military", temperament = "fresh", male = "pal_military", female = "pal_american_female_survivor" },
    deserter = { label = "Military - Deserter", register = "outlaw", temperament = "seasoned", male = "pal_paramilitary", female = "pal_american_female_survivor" },
    militia = { label = "Militia - Rifleman", register = "civilian", temperament = "seasoned", male = "pal_paramilitary", female = "pal_american_female_survivor" },
    elite_operator = { label = "Special Forces - Operator", register = "elite", temperament = "veteran", male = "pal_mercenary", female = "pal_foreign_female_survivor" },
    elite_delta = { label = "Delta - Operator", register = "elite", temperament = "veteran", male = "pal_mercenary", female = "pal_foreign_female_survivor" },
    outlaw = { label = "Outlaw", register = "outlaw", temperament = "seasoned", male = "pal_outlaw", female = "pal_raider_female" },
    raider = { label = "Raider", register = "raider", temperament = "predator", male = "pal_raider", female = "pal_raider_female" },
    raider_boss = { label = "Raider - Boss", register = "raider", temperament = "predator", male = "pal_outlaw", female = "pal_raider_female" },
    gang_member = { label = "Gang - Soldier", register = "gang", temperament = "predator", male = "pal_anarchist", female = "pal_raider_female" },
    gang_boss = { label = "Gang - Shot Caller", register = "gang", temperament = "predator", male = "pal_outlaw", female = "pal_raider_female" },
    biker = { label = "Motorcycle Club - Member", register = "club", temperament = "predator", male = "pal_outlaw", female = "pal_raider_female" },
    biker_boss = { label = "Motorcycle Club - President", register = "club", temperament = "veteran", male = "pal_outlaw", female = "pal_raider_female" },
    crime_member = { label = "Crime - Associate", register = "crime", temperament = "seasoned", male = "pal_russian_survivor", female = "pal_foreign_female_survivor" },
    prisoner = { label = "Prison - Escapee", register = "prison", temperament = "predator", male = "pal_outlaw", female = "pal_raider_female" },
    mercenary = { label = "Mercenary", register = "elite", temperament = "veteran", male = "pal_mercenary", female = "pal_foreign_female_survivor" },
}

Roles.titles = {
    ["*"] = {
        husband = "family_man", wife = "family_woman", brother = "family_man", sister = "family_woman",
        son = "family_youth", daughter = "family_youth", nephew = "family_youth", cousin = "family_youth",
        ["kid brother"] = "family_youth", patriarch = "family_elder", ["head of the house"] = "family_man",
        spouse = "family_woman", ["retired neighbour"] = "family_elder", survivor = "civilian_man",
        traveller = "civilian_man", walker = "civilian_man", angler = "civilian_loner", hunter = "civilian_loner",
        prepper = "civilian_loner", ["camp boss"] = "civilian_loner", mechanic = "worker", apprentice = "worker",
        ["roadside mechanic"] = "worker", foreman = "worker", worker = "worker", ["co-worker"] = "worker",
        deckhand = "worker", skipper = "worker", runner = "worker", lineman = "worker", postmaster = "worker",
        carrier = "worker", clerk = "worker", ["county clerk"] = "worker", pastor = "rescue_clergy",
        deacon = "rescue_clergy", congregant = "rescue_clergy", doctor = "rescue_medical", nurse = "rescue_medical",
        ["night-shift nurse"] = "rescue_medical", paramedic = "rescue_medical", emt = "rescue_medical",
        pharmacist = "rescue_medical", technician = "rescue_medical", veterinarian = "rescue_medical",
        firefighter = "rescue_firefighter", ["fire officer"] = "rescue_firefighter",
        president = "biker_boss", prospect = "biker", ["road captain"] = "biker", enforcer = "biker",
        ["sergeant-at-arms"] = "biker", ["shot caller"] = "gang_boss", prisoner = "prisoner",
        ["old timer"] = "prisoner", ["kitchen worker"] = "prisoner", escapee = "prisoner", runaway = "prisoner",
        assaulter = "elite_delta", ["troop leader"] = "elite_delta", ["weapons sergeant"] = "elite_operator",
        ["medical sergeant"] = "elite_operator", deputy = "law_deputy", sheriff = "law_sheriff",
        trooper = "law_trooper", ["corrections officer"] = "law_corrections", ["shift officer"] = "law_corrections",
        breacher = "swat_operator", trainee = "soldier_green", ["drill sergeant"] = "soldier_nco",
        ["platoon sergeant"] = "soldier_nco", ["squad leader"] = "soldier_nco", ["desk sergeant"] = "soldier_nco",
        corporal = "soldier_nco", captain = "soldier_nco", ["convoy commander"] = "soldier_nco",
        ["medical officer"] = "soldier_nco", rifleman = "soldier", grenadier = "soldier",
        ["military policeman"] = "soldier", engineer = "soldier", private = "soldier", waitress = "civilian_woman",
        teacher = "civilian_man", principal = "civilian_man", coach = "civilian_man",
    },
    law = { sergeant = "law_sergeant", officer = "law_officer", ["senior officer"] = "law_officer",
        inspector = "law_officer", ["team leader"] = "swat_lead", operator = "swat_operator",
        marksman = "swat_operator", clerk = "worker", leader = "law_sergeant" },
    military = { ["team leader"] = "soldier_nco", marksman = "soldier", medic = "soldier", driver = "soldier",
        orderly = "soldier", sergeant = "soldier_nco", leader = "soldier_nco" },
    elite = { ["team leader"] = "elite_operator", sniper = "elite_operator", operator = "elite_operator", leader = "elite_operator" },
    rescue = { driver = "rescue_firefighter", volunteer = "rescue_firefighter", orderly = "rescue_medical",
        coordinator = "worker", ["volunteer lead"] = "worker", cashier = "worker" },
    raider = { ["crew leader"] = "raider_boss", ringmaster = "raider_boss", ["toll boss"] = "raider_boss",
        ["yard boss"] = "raider_boss", ["collector boss"] = "raider_boss", chieftain = "raider_boss",
        ["checkpoint boss"] = "raider_boss", warlord = "raider_boss", guard = "raider", gunner = "raider",
        marksman = "raider", lookout = "raider", bruiser = "raider", fighter = "raider", bookie = "raider",
        collector = "raider", predator = "raider", stalker = "raider", leader = "raider_boss" },
    gang = { soldier = "gang_member", lookout = "gang_member", leader = "gang_boss" },
    club = { leader = "biker_boss" },
    crime = { boss = "crime_member", ["made man"] = "crime_member", associate = "crime_member", leader = "crime_member" },
    family = { hand = "family_youth", kin = "family_woman", ["stable hand"] = "worker", picker = "worker",
        ["forklift driver"] = "worker", ["shift lead"] = "worker", ["floor captain"] = "worker",
        auctioneer = "worker", ["orchard owner"] = "family_man", grower = "family_man", owner = "family_man",
        chief = "rescue_firefighter", volunteer = "rescue_firefighter", ["range officer"] = "militia",
        member = "militia", neighbour = "family_man", assistant = "rescue_medical", driver = "worker",
        ["station manager"] = "worker", dj = "worker", engineer = "worker" },
    worker = { owner = "worker", leader = "worker" },
    civilian = { leader = "civilian_loner" },
    prison = { leader = "prisoner" },
}

Roles.blocDefaults = {
    law = { "law_officer", "law_officer" }, military = { "soldier", "soldier" },
    elite = { "elite_operator", "elite_operator" }, rescue = { "rescue_medical", "rescue_medical" },
    family = { "family_man", "family_woman" }, worker = { "worker", "worker" },
    civilian = { "civilian_man", "civilian_woman" }, crime = { "crime_member", "crime_member" },
    club = { "biker", "biker" }, gang = { "gang_member", "gang_member" },
    raider = { "raider", "raider" }, prison = { "prisoner", "prisoner" },
}

Roles.stockFactions = {
    alife_police = "law_officer", alife_fire = "rescue_firefighter", alife_guard = "soldier",
    alife_cordon = "soldier", alife_riverside = "civilian_man",
    alife_drifters = "outlaw", alife_blacktop = "raider", alife_ashguard = "mercenary",
    alife_kettle = "worker",
}

Roles.archetypes = { deserter = "deserter", militia = "militia", elite_sf = "elite_operator",
    elite_delta = "elite_delta", escapee = "prisoner", jail_raider = "prisoner", inmate = "prisoner" }

Roles.femaleOf = { family_man = "family_woman", civilian_man = "civilian_woman" }

function Roles.get(id)
    return Roles.definitions[tostring(id or "")]
end

local function trim(value)
    return (string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

function Roles.titleOf(name)
    name = trim(name)
    local after = string.match(name, "%s%-%s(.+)$")
    return string.lower(trim(after or name))
end

function Roles.archetypeOf(tags)
    local index = 0
    for tag in string.gmatch(tostring(tags or ""), "[^,]+") do
        index = index + 1
        if index == 2 then return string.lower(trim(tag)) end
    end
    return nil
end

function Roles.pick(facts)
    facts = type(facts) == "table" and facts or {}
    local female = facts.female == true
    local explicit = trim(facts.explicit)
    if explicit ~= "" and Roles.definitions[explicit] ~= nil then return explicit, Roles.definitions[explicit], "explicit" end
    local arch = Roles.archetypeOf(facts.tags)
    local chosen = arch and Roles.archetypes[arch] or nil
    local source = chosen ~= nil and "archetype" or nil
    local bloc = facts.bloc and string.lower(trim(facts.bloc)) or nil
    if chosen == nil then
        for _, from in ipairs({ facts.name, facts.role }) do
            local title = Roles.titleOf(from)
            if title ~= "" then
                local byBloc = bloc and Roles.titles[bloc] or nil
                chosen = byBloc and byBloc[title] or Roles.titles["*"][title]
                if chosen ~= nil then source = "title"; break end
            end
        end
    end
    if chosen == nil and facts.factionId ~= nil then
        chosen = Roles.stockFactions[tostring(facts.factionId)]
        if chosen ~= nil then source = "stock" end
    end
    if chosen == nil and bloc ~= nil and Roles.blocDefaults[bloc] ~= nil then
        chosen = Roles.blocDefaults[bloc][female and 2 or 1]
        source = "bloc"
    end

    if chosen == nil then chosen, source = facts.friendly == false and "outlaw" or "civilian_man", "fallback" end
    if female and Roles.femaleOf[chosen] ~= nil then chosen = Roles.femaleOf[chosen] end
    return chosen, Roles.definitions[chosen], source
end

Roles.seasonedTitles = { veteran = true }

function Roles.seasonedTitle(facts)
    if type(facts) ~= "table" then return false end
    for _, from in ipairs({ facts.name, facts.role }) do
        if Roles.seasonedTitles[Roles.titleOf(from)] == true then return true end
    end
    return false
end

Roles.seasonedAfterDay = 30
function Roles.temperamentFor(roleId, rank, day, seasonedTitle)
    local definition = Roles.definitions[tostring(roleId or "")]
    local temperament = definition and definition.temperament or "fresh"
    if temperament == "fresh" and string.lower(tostring(rank or "")) == "veteran" then temperament = "seasoned" end
    if temperament == "fresh" and seasonedTitle == true then temperament = "seasoned" end
    if temperament == "fresh" and (tonumber(day) or 0) >= Roles.seasonedAfterDay then temperament = "seasoned" end
    return temperament
end

function Roles.factsFor(record)
    local facts = {}
    if type(record) ~= "table" then return facts end
    local memory = type(record.memory) == "table" and record.memory or {}
    facts.factionId = record.factionId
    local catalog = ProjectALife.Catalog
    local profile = catalog ~= nil and type(catalog.npc) == "function" and catalog.npc(record.profileId) or nil
    local general = type(profile) == "table" and type(profile.general) == "table" and profile.general or {}
    facts.explicit = general.dialogueRole
    facts.name = general.name
    facts.role = general.role
    facts.tags = general.tags
    facts.rank = general.rank
    facts.female = general.female == true or general.female == "true" or memory.female == true
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(record.factionId) or nil
    if type(faction) == "table" then
        facts.bloc = type(faction.relations) == "table" and faction.relations.bloc or nil
        facts.friendly = type(faction.spawn) == "table" and faction.spawn.peaceable == true or nil
    end
    return facts
end

Roles.trainedRegisters = { law = true, swat = true, military = true, elite = true }
Roles.trainedRoles = { deserter = true, militia = true }
Roles.roughRegisters = { outlaw = true, raider = true, gang = true, club = true, crime = true, prison = true }

function Roles.callStyle(record, day)
    if type(record) ~= "table" then return "plain" end
    local ok, who = pcall(Roles.describe, record, day)
    if not ok or type(who) ~= "table" then return "plain" end
    if Roles.trainedRegisters[who.register] == true or Roles.trainedRoles[who.role] == true then return "trained" end
    if Roles.roughRegisters[who.register] == true then return "rough" end
    return "plain"
end

function Roles.describe(record, day)
    local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or {}
    local facts = Roles.factsFor(record)
    local roleId = memory.dialogueRole
    local source = "memory"
    if Roles.definitions[tostring(roleId or "")] == nil then roleId, _, source = Roles.pick(facts) end
    local definition = Roles.definitions[roleId]
    return {
        source = source,
        role = roleId,
        register = definition.register,
        temperament = Roles.temperamentFor(roleId, facts.rank, day, Roles.seasonedTitle(facts)),
        sex = facts.female and "f" or "m",
        label = definition.label,
        voice = facts.female and definition.female or definition.male,
    }
end

return Roles
