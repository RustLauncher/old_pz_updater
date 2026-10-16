require "ProjectALife/World/ALifeSpawnRegions"
require "ProjectALife/Records/ALifeRosterBalance"
require "ProjectALife/Records/ALifeFunnel"

ProjectALife = ProjectALife or {}
local Rules = {}
ProjectALife.FactionSpawnRules = Rules

Rules.poolCache = {}
Rules.poolCacheSize = 0
Rules.poolCacheLimit = 2048

function Rules.resetCache()
    Rules.poolCache = {}
    Rules.poolCacheSize = 0
end

function Rules.encounters(spawn, day)
    if type(spawn) ~= "table" then return Rules.parseEncounters(spawn, day) end
    local pool = spawn.encounterPool
    if type(pool) == "table" then return Rules.parseEncounters(spawn, day) end
    local number = tonumber(day)
    local key = number ~= nil and math.floor(number) or nil
    if key ~= nil and key ~= key then return Rules.parseEncounters(spawn, day) end
    local entry = Rules.poolCache[spawn]
    if entry == nil or entry.pool ~= pool then
        if entry == nil then
            if Rules.poolCacheSize >= Rules.poolCacheLimit then Rules.resetCache() end
            Rules.poolCacheSize = Rules.poolCacheSize + 1
        end
        entry = { pool = pool, byDay = {} }
        Rules.poolCache[spawn] = entry
    end
    local result
    if key == nil then result = entry.all else result = entry.byDay[key] end
    if result == nil then
        result = Rules.parseEncounters(spawn, day)
        if key == nil then
            entry.all = result
        else
            entry.days = (entry.days or 0) + 1
            if entry.days > 16 then entry.byDay, entry.days = {}, 1 end
            entry.byDay[key] = result
        end
    end
    return result
end

function Rules.parseEncounters(spawn, day)
    local result = {}
    local pool = spawn and spawn.encounterPool
    if pool == nil then pool = "roamer" end
    day = tonumber(day)
    local function add(id)
        id = string.match(tostring(id), "^%s*(.-)%s*$")
        local opens = string.match(id, "@(%d+)$")
        if opens ~= nil then
            id = string.sub(id, 1, -(#opens + 2))
            if day ~= nil and math.floor(day) < tonumber(opens) then return end
        end
        if id ~= "" then result[id] = true end
    end
    if type(pool) == "table" then
        for _, id in ipairs(pool) do add(id) end
    else
        for id in string.gmatch(tostring(pool) .. "|", "(.-)|") do add(id) end
    end
    return Rules.withParties(result)
end

Rules.partyOwners = {
    roamer = { "fishing_party", "hunting_party" },
    scavenger_crew = { "foraging_party", "firewood_camp", "camp_builders", "scavenging_trip", "water_run" },
}

function Rules.withParties(result)
    for _, list in pairs(Rules.partyOwners) do
        for _, id in ipairs(list) do
            if result[id] then return result end
        end
    end
    for owner, list in pairs(Rules.partyOwners) do
        if result[owner] then
            for _, id in ipairs(list) do result[id] = true end
        end
    end
    return result
end

function Rules.activeAtHour(spawn, hour)
    local first = math.max(0, math.min(23, tonumber(spawn.hourStart) or 0))
    local last = math.max(0, math.min(24, tonumber(spawn.hourEnd) or 24))
    hour = (tonumber(hour) or 0) % 24
    if first == last or (first == 0 and last == 24) then return true end
    if first < last then return hour >= first and hour < last end
    return hour >= first or hour < last
end

function Rules.roamingEncounters(spawn)
    local selected, result = Rules.encounters(spawn), {}
    for _, id in ipairs({ "roamer", "patrol", "town_patrol", "scavenger_crew" }) do
        if selected[id] then result[#result + 1] = id end
    end
    return result
end

Rules.stateLastDay = 3
Rules.collapseExempt = { alife_cordon = true }
function Rules.collapsed(faction, day)
    local settings = ProjectALife.Settings
    local current = settings ~= nil and settings.current or nil
    if type(current) ~= "table" or current.realisticOutbreak ~= true then return false end
    if type(faction) ~= "table" or Rules.collapseExempt[tostring(faction.id)] then return false end
    if Rules.stateBlocs == nil or not Rules.stateBlocs[tostring(Rules.blocOf(faction))] then return false end
    local spawn = type(faction.spawn) == "table" and faction.spawn or {}
    if (tonumber(spawn.firstDay) or 0) > Rules.stateLastDay then return false end
    return math.floor(tonumber(day) or 0) > Rules.stateLastDay
end

function Rules.hostileAllowed()
    local settings = ProjectALife.Settings
    local current = settings ~= nil and settings.current or nil
    return type(current) ~= "table" or current.hostileEnabled ~= false
end

function Rules.withinDays(spawn, day)
    local today = math.floor(tonumber(day) or 0)
    local first, last = tonumber(spawn.firstDay), tonumber(spawn.lastDay)
    return (first == nil or today >= first) and (last == nil or today <= last)
end

function Rules.windowDay(faction, day)
    local funnel = ProjectALife.Funnel
    if day == nil or type(funnel) ~= "table" or type(funnel.classOf) ~= "function"
            or type(funnel.day) ~= "function" or funnel.classOf(faction) == nil then
        return day
    end
    return funnel.day(day)
end

function Rules.funnelOpen(faction, day)
    local funnel = ProjectALife.Funnel
    if type(funnel) ~= "table" or type(funnel.allows) ~= "function" then return true end
    return funnel.allows(faction, day) == true
end

function Rules.funnelWeight(faction, day)
    local funnel = ProjectALife.Funnel
    if type(funnel) ~= "table" or type(funnel.weight) ~= "function" then return 1 end
    return tonumber(funnel.weight(faction, day)) or 1
end

function Rules.inSeason(faction, day)
    if type(faction) ~= "table" then return false end
    if day == nil then day = Rules.clock() end
    return Rules.withinDays(type(faction.spawn) == "table" and faction.spawn or {}, Rules.windowDay(faction, day))
        and Rules.funnelOpen(faction, day)
end

function Rules.visitorOnly(faction)
    if type(faction) ~= "table" then return false end
    local spawn = faction.spawn
    return type(spawn) == "table" and spawn.visitorOnly == true
end

function Rules.available(faction, day, hour, position, encounter)
    if Rules.visitorOnly(faction) then return false end
    if Rules.collapsed(faction, day) then return false end
    if not Rules.hostileAllowed() and (Rules.hostile(faction)
            or type(faction) == "table" and faction.id == "alife_the_tithe") then return false end
    local spawn = faction and faction.spawn

    if type(spawn) ~= "table" or spawn.enabled == false or spawn.natural == false
            or spawn.hiddenFromSpawn == true
            or (tonumber(spawn.odds) or 0) <= 0
            or Rules.earlyLooterScale(faction, day) <= 0
            or not Rules.withinDays(spawn, Rules.windowDay(faction, day))
            or not Rules.funnelOpen(faction, day)
            or not Rules.activeAtHour(spawn, hour) then return false end
    local selected = Rules.encounters(spawn, day)
    if encounter and not selected[encounter] then return false end
    for _ in pairs(selected) do
        return position == nil or ProjectALife.SpawnRegions.allows(position, spawn)
    end
    return false
end

function Rules.hostile(faction)
    local relation = faction and faction.relations and faction.relations.player
    if relation ~= nil then return relation == "hostile" end
    return not (faction and faction.spawn and faction.spawn.peaceable == true)
end

local outlawBlocs = { crime = true, club = true, gang = true, raider = true, prison = true }

function Rules.outlaw(faction)
    return outlawBlocs[tostring(Rules.blocOf(faction))] == true
end

Rules.survivorHolders = {
    alife_survivor_commune = true, alife_first_responders = true, alife_vittitoe = true,
    alife_kessinger = true, alife_schoolhouse = true, alife_truckstop = true, alife_road_militia = true,
    alife_commonwealth_knox = true, alife_ridge_militia_league = true, alife_valley_caravan_league = true,
    alife_ekron_farm_cooperative = true, alife_riverside_ferry_union = true, alife_mount_hope_fellowship = true,
    alife_foundry_works = true, alife_hollow_compact = true, alife_clinic_circle = true,
}

Rules.federationHolders = {
    alife_valley_caravan_league = true, alife_riverside_ferry_union = true, alife_foundry_works = true,
}

function Rules.survivorOutposts()
    local settings = ProjectALife.Settings
    local current = settings ~= nil and settings.current or nil
    if type(current) == "table" and current.survivorOutposts ~= nil then return current.survivorOutposts == true end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table"
            and SandboxVars.ALife.Outposts_SurvivorHolds ~= nil then
        return SandboxVars.ALife.Outposts_SurvivorHolds == true
    end
    return true
end

function Rules.holdsGround(faction, preset)
    if Rules.hostile(faction) or type(faction) == "table" and faction.id == "alife_the_tithe" and Rules.outlaw(faction) then
        return outlawBlocs[tostring(Rules.blocOf(faction))] == true
    end
    if type(preset) ~= "table" or preset.hostileToPlayers == true then return false end
    local relation = type(faction) == "table" and type(faction.relations) == "table" and faction.relations.player or nil
    return (relation == "careful" or relation == "friendly"
        or relation == "neutral" and Rules.federationHolders[tostring(faction.id)] == true)
        and Rules.survivorHolders[tostring(faction.id)] == true
        and Rules.survivorOutposts()
end

function Rules.huntsPlayers(factionId)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(factionId) or nil
    if faction == nil then return true end
    return Rules.hostile(faction)
end

function Rules.clock()
    local day, hour = 0, 12
    pcall(function()
        local time = getGameTime()
        day, hour = time:getWorldAgeHours() / 24, time:getTimeOfDay()
    end)
    return day, hour
end

function Rules.seatAllows(faction, presetId)
    local seats = faction and faction.spawn and faction.spawn.seats
    if seats == nil or tostring(seats) == "" then return true end
    for id in string.gmatch(tostring(seats) .. "|", "(.-)|") do
        if string.match(id, "^%s*(.-)%s*$") == tostring(presetId) then return true end
    end
    return false
end

Rules.stockBlocs = {
    alife_police = "law", alife_guard = "military", alife_cordon = "military",
    alife_fire = "rescue", alife_riverside = "civilian", alife_kettle = "worker",
}
function Rules.blocOf(faction)
    if type(faction) ~= "table" then return nil end
    local bloc = type(faction.relations) == "table" and faction.relations.bloc or nil
    if bloc ~= nil and bloc ~= "" then return tostring(bloc) end
    return Rules.stockBlocs[tostring(faction.id)]
end

Rules.lawShare = 0.6
Rules.stateBlocs = { law = true, military = true, elite = true }

Rules.stanceMood = ProjectALife.RosterBalance.mood
Rules.professionRolls = true
Rules.professionContext = nil

function Rules.moodFor(faction, day)
    day = tonumber(day)
    local rows = Rules.stanceMood
    if ProjectALife.RosterBalance.legacy() then rows = ProjectALife.RosterBalance.moodLegacy end
    if day == nil or type(rows) ~= "table" or #rows == 0 then return 1 end
    local stance = type(faction) == "table" and type(faction.relations) == "table"
        and faction.relations.player or nil
    local layers = ProjectALife.RelationLayers
    if Rules.professionContext ~= nil and Rules.professionRolls == true and type(faction) == "table" and layers ~= nil
            and type(layers.towardPlayer) == "function" then
        local ok, word = pcall(layers.towardPlayer, faction, Rules.professionContext)
        if ok and type(word) == "string" then stance = word end
    end
    if stance == nil then stance = Rules.hostile(faction) and "hostile" or "neutral" end
    if stance == "allied" then stance = "friendly" end
    local low, high = rows[1], rows[#rows]
    for _, row in ipairs(rows) do
        if row.day <= day then low = row end
        if row.day >= day then high = row; break end
    end
    local a, b = tonumber(low[stance]), tonumber(high[stance])
    if a == nil or b == nil then return 1 end
    if high.day == low.day then return a end
    return a + (b - a) * (day - low.day) / (high.day - low.day)
end

function Rules.weightFor(faction, day, raw)
    if Rules.visitorOnly(faction) then return 0 end
    local weight = math.max(0, tonumber(faction.spawn and faction.spawn.odds) or 0)
    local bloc = tostring(Rules.blocOf(faction) or "")
    if bloc == "law" then weight = weight * (tonumber(Rules.lawShare) or 1) end
    weight = weight * ProjectALife.RosterBalance.keptScale(faction)
    local settings = ProjectALife.Settings
    if not Rules.stateBlocs[bloc] and settings ~= nil and type(settings.factionWeightScale) == "function" then
        weight = weight * (tonumber(settings.factionWeightScale(faction, day)) or 1)
    end
    if raw ~= true then weight = weight * Rules.censusStrength(faction) end
    return weight * Rules.moodFor(faction, day) * Rules.earlyLooterScale(faction, day)
        * Rules.funnelWeight(faction, day)
end

Rules.referenceWeight = 1
function Rules.presence(total, reference)
    total = tonumber(total) or 0
    if total <= 0 then return 1 end
    reference = tonumber(reference) or tonumber(Rules.referenceWeight) or 1
    return math.min(1, total / math.max(0.0001, reference))
end

function Rules.censusStrength(faction)
    local census = ProjectALife.WorldPressure
    if type(census) ~= "table" or type(census.censusStrength) ~= "function" then return 1 end
    return tonumber(census.censusStrength(faction)) or 1
end

Rules.earlyLooters = { alife_roadside_pickers = true }
Rules.earlyLooterBoost = 2
Rules.earlyLooterFade = { full = 14, gone = 28 }
function Rules.earlyLooterScale(faction, day)
    if type(faction) ~= "table" or Rules.earlyLooters[tostring(faction.id)] ~= true then return 1 end
    local percent = 100
    local settings = ProjectALife.Settings
    local current = type(settings) == "table" and settings.current or nil
    if type(current) == "table" and tonumber(current.earlyLootersPercent) ~= nil then
        percent = tonumber(current.earlyLootersPercent)
    elseif type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table"
            and tonumber(SandboxVars.ALife.Encounters_EarlyLooters) ~= nil then
        percent = tonumber(SandboxVars.ALife.Encounters_EarlyLooters)
    end
    local scale = math.max(0, percent) / 100 * (tonumber(Rules.earlyLooterBoost) or 1)
    day = tonumber(day)
    local fade = Rules.earlyLooterFade
    if day == nil or day <= fade.full then return scale end
    if day >= fade.gone then return 0 end
    return scale * (fade.gone - day) / (fade.gone - fade.full)
end

function Rules.pick(catalog, position, encounter, unit, hostileOnly, day, hour, requiredEncounter, filter)
    return Rules.pickAt(Rules.pickList(catalog, encounter, hostileOnly, day, hour, requiredEncounter, filter),
        position, unit)
end

function Rules.pickList(catalog, encounter, hostileOnly, day, hour, requiredEncounter, filter)
    if day == nil then day, hour = Rules.clock() end
    local populated, rows = {}, {}
    for _, profile in ipairs(catalog and catalog.npcOrder or {}) do
        if profile.general then populated[profile.general.faction] = true end
    end
    for _, faction in ipairs(catalog and catalog.factionOrder or {}) do
        if populated[faction.id] and Rules.available(faction, day, hour, nil, encounter)
                and (not hostileOnly or Rules.hostile(faction))
                and (requiredEncounter == nil or Rules.encounters(faction.spawn, day)[requiredEncounter])
                and (filter == nil or filter(faction) == true) then
            rows[#rows + 1] = { faction = faction, weight = Rules.weightFor(faction, day) }
        end
    end
    return rows
end

function Rules.pickAt(rows, position, unit)
    local choices, total = {}, 0
    for _, row in ipairs(rows or {}) do
        if position == nil or ProjectALife.SpawnRegions.allows(position, row.faction.spawn) then
            total = total + row.weight
            choices[#choices + 1] = { faction = row.faction, ceiling = total }
        end
    end
    if total <= 0 then return nil end
    local needle = math.max(0, math.min(0.999999, tonumber(unit) or 0)) * total
    for _, choice in ipairs(choices) do
        if needle < choice.ceiling then return choice.faction end
    end
end

function Rules.reference(encounterId, day, hour, hostile)
    local cap = tonumber(Rules.referenceWeight) or 1
    local catalog = ProjectALife.Catalog
    local shipped = type(catalog) == "table" and catalog.shipped or nil
    if type(shipped) ~= "table" or encounterId == nil then return cap end
    local owners = Rules.encounterOwners(shipped, day, hour, true)
    local stock = owners.any[encounterId] or 0
    if hostile == true then stock = owners.hostile[encounterId] or 0 end
    if stock <= 0 then return cap end
    return math.min(cap, stock)
end

function Rules.encounterOwners(catalog, day, hour, raw)
    if day == nil then day, hour = Rules.clock() end
    local owners = { any = {}, hostile = {} }
    local populated = {}
    for _, profile in ipairs(catalog and catalog.npcOrder or {}) do
        if profile.general then populated[profile.general.faction] = true end
    end
    for _, faction in ipairs(catalog and catalog.factionOrder or {}) do
        if populated[faction.id] and Rules.available(faction, day, hour) then
            local weight = Rules.weightFor(faction, day, raw)
            local hostile = Rules.hostile(faction)
            for id in pairs(Rules.encounters(faction.spawn, day)) do
                owners.any[id] = (owners.any[id] or 0) + weight
                if hostile then owners.hostile[id] = (owners.hostile[id] or 0) + weight end
            end
        end
    end
    return owners
end

return Rules
