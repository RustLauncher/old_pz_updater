require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorRule"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorLedger"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Rule = ProjectALife.VisitorRule
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Ledger = ProjectALife.VisitorLedger
local Visitors = {
    adapters = {},
    deferred = {},
    deferredCount = 0,
    arcAt = {},
    bad = {},
    noReturn = {},
    made = 0,
    nextSweepMs = 0,
    sweepMs = 30000,
    arcMs = 5000,
    farTiles = 60,
    returnBond = 41,
    returnGapHours = 72,
    castLog = 5,
    metrics = { casts = 0, castFailed = 0, instantiated = 0, instantiateFailed = 0, admitted = 0, released = 0,
        retired = 0, deferred = 0, swept = 0, ledgerWrites = 0, returning = 0, seeded = 0, lastWhy = "-" },
}
ProjectALife.VisitorDirector = Visitors

Visitors.outcomeBond = { gave_food = 4, let_sleep = 8, treated_wounded = 8, sheltered_chased = 10, fair_trade = 3,
    neighbour_watch = 3, census_answer = 0, left = 3, asked_to_leave = 1, rested = 6, host_gone = 0, refused = -1,
    ignored = -1, rude_no = -6, guest_turned = -15, turned_inside = -10, squatter_left = -2, refused_chased = -2 }
Visitors.outcomeName = { asked_to_leave = "left", squatter_left = "left", rested = "left", host_gone = "left",
    refused = "turned_away", refused_chased = "turned_away" }
Visitors.hostile = { guest_turned = true, turned_inside = true }

function Visitors.director()
    return ProjectALife.SafehouseDirector
end

function Visitors.visit()
    return ProjectALife.SafehouseVisit
end

function Visitors.fail(why)
    Visitors.metrics.lastWhy = tostring(why)
    return nil, why
end

function Visitors.hours()
    local director = Visitors.director()
    if director ~= nil and type(director.hours) == "function" then return director.hours() end
    return 0
end

function Visitors.rand(n)
    local director = Visitors.director()
    if director ~= nil and type(director.rand) == "function" then return director.rand(n) end
    n = math.floor(tonumber(n) or 0)
    if n <= 1 or type(ZombRand) ~= "function" then return 0 end
    return math.floor(tonumber(ZombRand(n)) or 0)
end

function Visitors.nowMs()
    if type(Visitors.adapters.nowMs) == "function" then return Visitors.adapters.nowMs() end
    local visit = Visitors.visit()
    if visit ~= nil and type(visit.millis) == "function" then return visit.millis() end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) end
    return nil
end

function Visitors.hourOfDay()
    if type(Visitors.adapters.hour) == "function" then return Visitors.adapters.hour() end
    local director = Visitors.director()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    if director == nil or time == nil then return nil end
    return tonumber(director.ask(time, "getTimeOfDay"))
end

function Visitors.options()
    if type(Visitors.adapters.options) == "function" then return Visitors.adapters.options() end
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.visitors) == "function" then return settings.visitors() end
    return Schema.options(nil)
end

function Visitors.visitorOnly(factionId)
    local rules = ProjectALife.FactionSpawnRules
    local catalog = ProjectALife.Catalog
    if rules == nil or type(rules.visitorOnly) ~= "function" or catalog == nil or factionId == nil then return false end
    local faction = catalog.faction(factionId)
    return faction ~= nil and rules.visitorOnly(faction) == true
end

function Visitors.activeSet(house)
    local set = {}
    local director = Visitors.director()
    if director ~= nil and type(director.store) == "function" then
        for _, other in pairs(director.store().houses) do
            for _, pending in ipairs(type(other.pending) == "table" and other.pending or {}) do
                if pending.lane == "visit" and pending.resolved ~= true and type(pending.person) == "table" then
                    for _, id in ipairs(type(pending.person.ids) == "table" and pending.person.ids or {}) do set[id] = true end
                end
            end
        end
    end
    for _, row in pairs(Visitors.deferred) do
        if type(row) == "table" and row.person ~= nil then set[row.person] = true end
    end
    return set
end

function Visitors.active(personId)
    if type(personId) ~= "string" then return false end
    return Visitors.activeSet(nil)[personId] == true
end

function Visitors.countRange(row)
    local low, high = 1, 1
    if type(row.count) == "table" then
        low = math.floor(tonumber(row.count[1]) or 1)
        high = math.floor(tonumber(row.count[2]) or low)
    end
    return low, math.max(low, high)
end

function Visitors.leadOf(index, entry)
    if entry.party == nil then return entry.id end
    local party = index.parties[entry.party]
    if party == nil then return nil end
    for position = 1, #party.ids do
        local member = index.people[party.ids[position]]
        if member ~= nil and member.adult then return member.id end
    end
    return nil
end

function Visitors.memberOk(entry, active, day, hour)
    if active[entry.id] or Visitors.bad[entry.id] or not Ledger.alive(entry.id) then return false end
    if day < entry.dayMin or day > entry.dayMax then return false end
    if entry.hourMin ~= nil and entry.hourMax ~= nil and not Rule.inHours(hour, entry.hourMin, entry.hourMax) then return false end
    return true
end

function Visitors.membersOf(index, entry)
    if entry.party == nil then return { entry.id } end
    local party = index.parties[entry.party]
    local ids = {}
    for position = 1, #party.ids do ids[#ids + 1] = party.ids[position] end
    return ids
end

function Visitors.fits(index, entry, state)
    if entry.teen or Visitors.leadOf(index, entry) ~= entry.id then return false end
    local members = Visitors.membersOf(index, entry)
    if #members < state.low or #members > state.high then return false end
    if entry.party ~= nil then
        local party = index.parties[entry.party]
        if state.options.parties ~= true then return false end
    end
    for position = 1, #members do
        local member = index.people[members[position]]
        if member == nil or not Visitors.memberOk(member, state.active, state.day, state.hour) then return false end
    end
    return true
end

function Visitors.weightOf(house, entry, base)
    local map = Ledger.map()
    local row = map ~= nil and map[entry.id] or nil
    local met = type(row) == "table" and tonumber(row.n) or 0
    local weight = base / (1 + met * 2)
    local log = type(house) == "table" and type(house.castArch) == "table" and house.castArch or nil
    if log ~= nil and entry.arch ~= nil then
        for position = 1, #log do
            if log[position] == entry.arch then weight = weight * 0.5; break end
        end
    end
    if type(Visitors.adapters.fit) == "function" then weight = weight * (tonumber(Visitors.adapters.fit(entry, house)) or 1) end
    return weight
end

function Visitors.pool(house, row, now)
    local options = Visitors.options()
    if options.persons ~= true then return nil, "persons_off" end
    People.warm()
    local index, why = People.index()
    if index == nil then return nil, tostring(why or "index_unavailable") end
    if index.count == 0 then return nil, "no_people" end
    local low, high = Visitors.countRange(row)
    local state = { options = options, active = Visitors.activeSet(house), day = math.floor(now / 24),
        hour = Visitors.hourOfDay(), low = low, high = high }
    local list = {}
    for position = 1, #index.order do
        local entry = index.people[index.order[position]]
        local base = entry.arrivals[row.id]
        if base ~= nil and Visitors.fits(index, entry, state) then
            list[#list + 1] = { id = entry.id, entry = entry, weight = Visitors.weightOf(house, entry, base) }
        end
    end
    return list, nil, index
end

function Visitors.residentKeys(house)
    local keys = {}
    for key in pairs(type(house) == "table" and type(house.residents) == "table" and house.residents or {}) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return keys
end

function Visitors.returning(house, now, row)
    local list = {}
    local map = Ledger.map()
    if map == nil or type(house) ~= "table" then return list end
    local index = People.index()
    if index == nil then return list end
    local active = Visitors.activeSet(house)
    local keys = Visitors.residentKeys(house)
    local day = math.floor(now / 24)
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids)
    for position = 1, #ids do
        local id, record = ids[position], map[ids[position]]
        local entry = index.people[id]
        if entry ~= nil and type(record) == "table" and record.d ~= 1 and not entry.teen and not active[id]
                and not Visitors.noReturn[id] and not Visitors.bad[id]
                and now - (tonumber(record.l) or now) >= Visitors.returnGapHours
                and day >= entry.dayMin and day <= entry.dayMax
                and (row == nil or row.id == "returning_guest" or entry.arrivals[row.id] ~= nil) then
            local best = 0
            for slot = 1, #keys do best = math.max(best, Ledger.bond(id, keys[slot])) end
            if best >= Visitors.returnBond then list[#list + 1] = { id = id, entry = entry, weight = best, returning = true } end
        end
    end
    return list
end

function Visitors.ready(house, row, now)
    if type(row) ~= "table" then return false, "row_invalid" end
    if Visitors.options().persons ~= true then return false, "persons_off" end
    if row.id == "returning_guest" then
        local list = Visitors.returning(house, now, row)
        if #list == 0 then return false, "no_returning_person" end
        return true
    end
    local list, why = Visitors.pool(house, row, now)
    if list == nil then return false, why end
    if #list == 0 then return false, "no_candidates" end
    return true
end

function Visitors.leads(house, row, now)
    if row.id == "returning_guest" then
        local back = Visitors.returning(house, now, row)
        if #back == 0 then return nil, "no_returning_person" end
        return back
    end
    local options = Visitors.options()
    local chance = math.floor(tonumber(options.returningChance) or 0)
    if chance > 0 then
        local back = Visitors.returning(house, now, row)
        if #back > 0 and Visitors.rand(100) < chance then return back end
    end
    local list, why = Visitors.pool(house, row, now)
    if list == nil then return nil, why end
    if #list == 0 then return nil, "no_candidates" end
    return list
end

function Visitors.choose(list)
    local warm = Visitors.warmPick
    if warm ~= nil then
        for position = 1, #list do
            if list[position].id == warm then return list[position] end
        end
    end
    local director = Visitors.director()
    return director.pickWeighted(list, function(item) return item.weight end)
end

function Visitors.profileSex(profile)
    local general = type(profile) == "table" and profile.general or nil
    if type(general) ~= "table" then return nil end
    if general.female == true or general.female == "true" or general.nameMode == "female" then return "f" end
    if general.female == false or general.female == "false" or general.nameMode == "male" then return "m" end
    return nil
end

function Visitors.poolOf(factionId)
    local catalog = ProjectALife.Catalog
    local current = catalog ~= nil and (catalog.current or catalog.load()) or nil
    if type(current) ~= "table" then return {} end
    local cache = Visitors.poolCache
    if cache == nil or cache.current ~= current then
        cache = { current = current, byFaction = {} }
        Visitors.poolCache = cache
    end
    local list = cache.byFaction[factionId]
    if list == nil then
        list = {}
        for _, profile in ipairs(type(current.npcOrder) == "table" and current.npcOrder or {}) do
            local general = profile.general
            if type(general) == "table" and tostring(general.faction) == factionId
                    and (tonumber(general.spawnWeight) or 1) > 0 then
                list[#list + 1] = profile
            end
        end
        cache.byFaction[factionId] = list
    end
    return list
end

function Visitors.pickFrom(factionId, card)
    local pool = Visitors.poolOf(factionId)
    local same = {}
    for position = 1, #pool do
        local sex = Visitors.profileSex(pool[position])
        if sex == nil or sex == card.sex then same[#same + 1] = pool[position] end
    end
    if #same == 0 then same = pool end
    if #same == 0 then return nil end
    return same[(math.floor(tonumber(card.seed) or 0) % #same) + 1].id
end

function Visitors.profileOk(profileId, factionId)
    local catalog = ProjectALife.Catalog
    local profile = type(profileId) == "string" and catalog ~= nil and catalog.npc(profileId) or nil
    if profile == nil or type(profile.general) ~= "table" or catalog.faction(profile.general.faction) == nil then return nil end
    if factionId ~= nil and tostring(profile.general.faction) ~= factionId then return nil end
    return profile
end

function Visitors.carrier(card, index, factionId)
    local profileId = nil
    local factions = ProjectALife.VisitorFactions
    if factions ~= nil and type(factions.carrierFor) == "function" then profileId = factions.carrierFor(card) end
    if profileId == nil then
        local arch = card.arch ~= nil and index.archetypes[card.arch] or nil
        if arch ~= nil and arch.carrier ~= nil then profileId = arch.carrier end
        if profileId == nil and arch ~= nil and arch.carrierPool ~= nil and factionId == nil then
            profileId = Visitors.pickFrom(arch.carrierPool, card)
        end
    end
    local profile = Visitors.profileOk(profileId, factionId)
    if profile == nil and factionId ~= nil then profile = Visitors.profileOk(Visitors.pickFrom(factionId, card), factionId) end
    if profile == nil then return nil, "no_carrier" end
    return profile.id, tostring(profile.general.faction)
end

function Visitors.dialogueReady(id)
    for _, key in ipairs({ "VQ_TALK_NAME", "VQ_TALK_HOWARE" }) do
        local found, why = People.nodes(id, key)
        if found == nil and why == "loading" then return false, "loading" end
        local node = found ~= nil and found.node or nil
        local lines = node ~= nil and node.lines or nil
        if node == nil or node.gateOk ~= true or type(lines) ~= "table"
                or #lines.any + #lines.lo + #lines.mid + #lines.hi == 0 then
            return false, "dialogue_unavailable:" .. key
        end
    end
    return true
end

function Visitors.cards(ids)
    local cards = {}
    for position = 1, #ids do
        local card, why = People.card(ids[position])
        if card == nil then return nil, why, ids[position] end
        local ready, dialogueWhy = Visitors.dialogueReady(ids[position])
        if not ready then return nil, dialogueWhy, ids[position] end
        cards[position] = card
    end
    return cards
end

function Visitors.cast(house, row, pick, now)
    local metrics = Visitors.metrics
    metrics.casts = metrics.casts + 1
    if type(house) ~= "table" or type(row) ~= "table" then return Visitors.fail("arguments_invalid") end
    now = tonumber(now) or Visitors.hours()
    local list, why = Visitors.leads(house, row, now)
    if list == nil then
        metrics.castFailed = metrics.castFailed + 1
        return Visitors.fail(why)
    end
    local chosen = Visitors.choose(list)
    if chosen == nil then
        metrics.castFailed = metrics.castFailed + 1
        return Visitors.fail("no_candidates")
    end
    local index = People.index()
    if index == nil then
        metrics.castFailed = metrics.castFailed + 1
        return Visitors.fail("index_unavailable")
    end
    local ids = chosen.returning and { chosen.id } or Visitors.membersOf(index, chosen.entry)
    local cards, cardWhy, cardId = Visitors.cards(ids)
    if cards == nil then
        metrics.castFailed = metrics.castFailed + 1
        if cardWhy == "loading" then
            Visitors.warmPick = chosen.id
            return Visitors.fail("loading")
        end
        Visitors.bad[cardId or chosen.id] = true
        return Visitors.fail("card_unavailable:" .. tostring(cardWhy))
    end
    if chosen.returning and cards[1].arc.returns == false then
        Visitors.noReturn[chosen.id] = true
        metrics.castFailed = metrics.castFailed + 1
        return Visitors.fail("returning_disallowed")
    end
    local carriers, factionId = {}, nil
    for position = 1, #cards do
        local profileId, faction = Visitors.carrier(cards[position], index, factionId)
        if profileId == nil then
            metrics.castFailed = metrics.castFailed + 1
            return Visitors.fail(faction or "no_carrier")
        end
        carriers[position] = profileId
        if factionId == nil then factionId = faction end
    end
    Visitors.warmPick = nil
    if chosen.returning then metrics.returning = metrics.returning + 1 end
    return { personIds = ids, partyId = (not chosen.returning) and chosen.entry.party or nil, carrierProfileIds = carriers,
        factionId = factionId, via = row.id, returning = chosen.returning == true }
end

function Visitors.names(card)
    local name = type(card.name) == "table" and card.name or {}
    local first, last = name.first, name.last
    local names = ProjectALife.Names
    local full = nil
    if names ~= nil and type(names.compose) == "function" then full = names.compose(first, last, name.nick) end
    if full == nil then full = last ~= nil and (first .. " " .. last) or first end
    return { first = first, last = last, name = full }
end

function Visitors.instantiate(cast, index, context)
    context = type(context) == "table" and context or {}
    local ids = type(cast) == "table" and (cast.ids or cast.personIds) or nil
    local id = type(ids) == "table" and ids[index] or nil
    if id == nil then
        Visitors.metrics.instantiateFailed = Visitors.metrics.instantiateFailed + 1
        return Visitors.fail("person_index")
    end
    local with = {}
    for position = 1, #ids do
        if ids[position] ~= id then with[#with + 1] = ids[position] end
    end
    local person, why = Instance.create(id, { now = context.now or Visitors.hours(), via = cast.via,
        seed = context.seed or index, rand = Visitors.rand, with = with, mood = context.mood })
    if person == nil then
        Visitors.metrics.instantiateFailed = Visitors.metrics.instantiateFailed + 1
        return Visitors.fail(why)
    end
    Visitors.metrics.instantiated = Visitors.metrics.instantiated + 1
    Visitors.made = Visitors.made + 1
    local card = People.card(id)
    return person, card ~= nil and Visitors.names(card) or nil
end

function Visitors.playerKeyOf(pending, extra)
    local by = type(extra) == "table" and extra.by or nil
    return by or pending.invitedBy or pending.by or pending.target
end

function Visitors.playerFor(key)
    local director = Visitors.director()
    if director == nil or key == nil then return nil end
    for _, player in ipairs(director.players()) do
        if director.playerKey(player) == key then return player end
    end
    return nil
end

function Visitors.admitted(house, pending, uids, now)
    local person = pending.person
    if type(person) ~= "table" then return 0 end
    person.admitted, person.byUid = true, {}
    local registry = ProjectALife.ActorRegistry
    local director = Visitors.director()
    local seeded = 0
    for _, uid in ipairs(uids) do
        local actor = registry.read(uid)
        local mine = Instance.of(actor)
        if mine ~= nil then
            person.byUid[uid] = mine.id
            for _, key in ipairs(Visitors.residentKeys(house)) do
                local who = Ledger.who(mine.id, key)
                if who ~= nil and who.bond > 0 then
                    seeded = seeded + Visitors.seed(actor, mine.id, key, who)
                end
            end
        end
    end
    if type(person.ids) == "table" and #person.ids > 0 then
        local entry = People.index()
        local arch = entry ~= nil and entry.people[person.ids[1]] ~= nil and entry.people[person.ids[1]].arch or nil
        if arch ~= nil then
            house.castArch = type(house.castArch) == "table" and house.castArch or {}
            house.castArch[#house.castArch + 1] = arch
            while #house.castArch > Visitors.castLog do table.remove(house.castArch, 1) end
        end
    end
    Visitors.metrics.admitted = Visitors.metrics.admitted + 1
    Visitors.metrics.seeded = Visitors.metrics.seeded + seeded
    if director ~= nil then director.dirty() end
    return seeded
end

function Visitors.seed(actor, personId, key, who)
    local opinion = ProjectALife.NpcOpinion
    local player = Visitors.playerFor(key)
    local count = 0
    if opinion ~= nil and player ~= nil and type(opinion.adjust) == "function" then
        if opinion.adjust(actor, player, who.bond * 0.6, "You have met before") then count = 1 end
    end
    local facts, flags = table.concat(who.facts, ","), table.concat(who.flags, ",")
    if facts ~= "" or flags ~= "" then
        Instance.write(actor.uid, function(memory)
            local row = Instance.vt(memory.person, key, true)
            if row ~= nil then
                if facts ~= "" then row.k = facts end
                if flags ~= "" then row.f = flags end
            end
        end)
    end
    return count
end

function Visitors.opinionOf(actor, key)
    local opinion = ProjectALife.NpcOpinion
    local player = Visitors.playerFor(key)
    if opinion == nil or player == nil or type(opinion.valueOf) ~= "function" then return nil end
    local value = opinion.valueOf(actor, player)
    return tonumber(value)
end

function Visitors.ledgerPatch(pending, outcome, actor, key, now)
    local name = Visitors.outcomeName[outcome] or outcome
    local patch = { hours = now, visit = true, outcome = name, bondDelta = Visitors.outcomeBond[outcome] or 0 }
    local mine = Instance.of(actor)
    if actor ~= nil and actor.lifecycle == "dead" then patch.dead = true end
    if key ~= nil and mine ~= nil then
        local trust = Visitors.opinionOf(actor, key)
        if trust ~= nil then
            patch.bond = math.max(0, math.floor(trust / 0.6 + 0.5))
        end
        local row = Instance.vt(mine, key, false)
        if row ~= nil then
            if row.k ~= "" then patch.facts = row.k end
            if row.f ~= "" then patch.flags = row.f end
        end
    end
    return patch
end

function Visitors.retire(uid)
    local service = ProjectALife.SpawnService
    if service == nil or type(service.retire) ~= "function" then return false, "spawn_service_unavailable" end
    local done, why = service.retire(uid, "visitor_done")
    if done == false then return false, why end
    Visitors.metrics.retired = Visitors.metrics.retired + 1
    Visitors.deferred[uid] = nil
    return true
end

function Visitors.angry(actor, house)
    local relations = ProjectALife.Relations
    local director = Visitors.director()
    if relations == nil or type(relations.playerStance) ~= "function" or director == nil or type(house) ~= "table" then return false end
    for _, resident in ipairs(director.onlineResidents(house)) do
        local ok, stance = pcall(relations.playerStance, actor, resident)
        if ok and stance == "hostile" then return true end
    end
    return false
end

function Visitors.defer(uid, personId, now)
    if Visitors.deferred[uid] == nil then Visitors.deferredCount = Visitors.deferredCount + 1 end
    Visitors.deferred[uid] = { at = now, person = personId }
    Visitors.metrics.deferred = Visitors.metrics.deferred + 1
end

function Visitors.owns(pending)
    if type(pending) ~= "table" then return false end
    if type(pending.person) == "table" then return true end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return false end
    local read = type(registry.peek) == "function" and registry.peek or registry.read
    for _, uid in ipairs(type(pending.uids) == "table" and pending.uids or {}) do
        local actor = read(uid)
        if actor ~= nil and Visitors.visitorOnly(actor.factionId) then return true end
    end
    return false
end

function Visitors.release(pending, outcome, uids, extra)
    local person = type(pending) == "table" and pending.person or nil
    local persons = type(person) == "table"
    if type(pending) ~= "table" or (persons and person.released == true) then return 0 end
    if persons then person.released = true else person = {} end
    extra = type(extra) == "table" and extra or {}
    local registry = ProjectALife.ActorRegistry
    local now = tonumber(extra.now) or Visitors.hours()
    local key = Visitors.playerKeyOf(pending, extra)
    local byUid = type(person.byUid) == "table" and person.byUid or {}
    local written = 0
    local seen = {}
    for _, uid in ipairs(type(uids) == "table" and uids or {}) do
        local actor = registry ~= nil and registry.read(uid) or nil
        local mine = Instance.of(actor)
        local id = byUid[uid] or (mine ~= nil and mine.id) or nil
        if id ~= nil and person.admitted == true and not seen[id] then
            seen[id] = true
            local ok = Ledger.note(id, key, Visitors.ledgerPatch(pending, outcome, actor, key, now))
            if ok then written = written + 1 end
        end
        if actor ~= nil and (mine ~= nil or Visitors.visitorOnly(actor.factionId)) then
            if Visitors.hostile[outcome] == true or Visitors.angry(actor, extra.house) then
                Visitors.defer(uid, id, now)
            else
                local done = Visitors.retire(uid)
                if not done then Visitors.defer(uid, id, now) end
            end
        end
    end
    Visitors.metrics.released = Visitors.metrics.released + 1
    Visitors.metrics.ledgerWrites = Visitors.metrics.ledgerWrites + written
    return written
end

function Visitors.stayUntil(pending, untilHours, now)
    local person = pending.person
    local events = ProjectALife.SafehouseEvents
    local row = events ~= nil and events.row(pending.event) or nil
    local rule = row ~= nil and type(row.guest) == "table" and row.guest or nil
    if type(person) ~= "table" or rule == nil or rule.person ~= true then return untilHours end
    local options = Visitors.options()
    local longest = 0
    for _, id in ipairs(type(person.ids) == "table" and person.ids or {}) do
        local card = People.card(id)
        if card ~= nil then longest = math.max(longest, tonumber(card.arc.stayMax) or 1) end
    end
    local extra = math.min(longest, tonumber(options.stayHours) or 1, tonumber(rule.cap) or 48)
    return math.max(untilHours, now + extra)
end

function Visitors.leaveSet(card)
    local set = {}
    for _, reason in ipairs(card.arc.leave) do set[reason] = true end
    return set
end

function Visitors.needsMet(person)
    for _, name in ipairs({ "hunger", "thirst", "cold", "fatigue", "sick", "pain" }) do
        if Instance.need(person, name) > 1 then return false end
    end
    return true
end

function Visitors.trustLow(uid, actor, mine, pending, now)
    local value = Visitors.opinionOf(actor, pending.invitedBy)
    if value == nil then return false end
    if value >= -16 then
        if mine.tl ~= nil then Instance.write(uid, function(memory) if type(memory.person) == "table" then memory.person.tl = nil end end) end
        return false
    end
    if mine.tl == nil then
        Instance.write(uid, function(memory) if type(memory.person) == "table" then memory.person.tl = Instance.hours(now) end end)
        return false
    end
    return now - mine.tl >= 2
end

function Visitors.arc(uid, now)
    local visit = Visitors.visit()
    if visit == nil or type(visit.live) ~= "function" then return "stay", "visit_unavailable" end
    local millis = Visitors.nowMs()
    local due = Visitors.arcAt[uid]
    if due ~= nil and millis ~= nil and millis < due then return "stay", "rate" end
    if millis ~= nil then Visitors.arcAt[uid] = millis + Visitors.arcMs end
    local pending, house, actor = visit.live(uid)
    if pending == nil then return "leave_now", "no_visit" end
    local mine = Instance.of(actor)
    if mine == nil then return "stay", "no_person" end
    local card = People.card(mine.id)
    if card == nil then return "stay", "card_unavailable" end
    now = tonumber(now) or Visitors.hours()
    if pending.state == "inside" and now >= (tonumber(pending.untilHours) or math.huge) then return "leave_now", "stay_cap" end
    local leave = Visitors.leaveSet(card)
    if pending.invitedBy ~= nil and Visitors.trustLow(uid, actor, mine, pending, now) then return "leave_now", "trust_low" end
    local inside = now - (tonumber(pending.insideAt) or now)
    if leave.need_met and inside >= 1 / 3 and (card.traits.pride or 0) >= 4 and Visitors.needsMet(mine) then
        return "leave_soon", "need_met"
    end
    if leave.partner_recovered and #(mine.with or {}) > 0 and Instance.need(mine, "sick") <= 1 and Instance.need(mine, "pain") <= 1
            and ((card.need0.sick or 0) >= 3 or (card.need0.pain or 0) >= 3) then
        return "leave_soon", "partner_recovered"
    end
    if leave.danger_gone and inside >= 1 / 6 and (pending.event == "chased" or pending.event == "panic_knock") then
        local director = Visitors.director()
        if director.densityBand(house, now) == "low" then return "leave_soon", "danger_gone" end
    end
    if leave.morning then
        local events = ProjectALife.SafehouseEvents
        local row = events ~= nil and events.row(pending.event) or nil
        local hour = Visitors.hourOfDay()
        local wake = row ~= nil and type(row.guest) == "table" and tonumber(row.guest.untilHour) or nil
        if wake ~= nil and hour ~= nil and hour >= wake and hour < wake + 3 then return "leave_soon", "morning" end
    end
    return "stay", "ok"
end

function Visitors.farFromPlayers(uid)
    local visit = Visitors.visit()
    local director = Visitors.director()
    local shell = visit ~= nil and visit.shell(uid) or nil
    if shell == nil then return true end
    local point = visit.position(shell)
    if point == nil then return true end
    local limit = Visitors.farTiles * Visitors.farTiles
    for _, player in ipairs(director.players()) do
        local at = visit.position(player)
        if at ~= nil and (at.x - point.x) ^ 2 + (at.y - point.y) ^ 2 < limit then return false end
    end
    return true
end

function Visitors.sweep()
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    local strays = {}
    registry.each(function(record)
        if Instance.of(record) ~= nil and record.lifecycle ~= "dead" and type(record.memory.visit) ~= "table" then
            strays[#strays + 1] = record.uid
        end
    end)
    local gone = 0
    for _, uid in ipairs(strays) do
        local held = Visitors.deferred[uid]
        if held == nil or Visitors.farFromPlayers(uid) then
            if Visitors.retire(uid) then gone = gone + 1 end
        end
    end
    local drop = {}
    for uid in pairs(Visitors.deferred) do
        if registry.read(uid) == nil then drop[#drop + 1] = uid end
    end
    for _, uid in ipairs(drop) do
        Visitors.deferred[uid] = nil
        Visitors.arcAt[uid] = nil
    end
    local count = 0
    for _ in pairs(Visitors.deferred) do count = count + 1 end
    Visitors.deferredCount = count
    Visitors.metrics.swept = Visitors.metrics.swept + gone
    return #strays
end

function Visitors.tick(nowMs)
    if Visitors.made <= 0 then return 0 end
    nowMs = tonumber(nowMs) or Visitors.nowMs()
    if nowMs == nil or nowMs < Visitors.nextSweepMs then return 0 end
    Visitors.nextSweepMs = nowMs + Visitors.sweepMs
    return Visitors.sweep()
end

function Visitors.reset()
    Visitors.deferred, Visitors.deferredCount, Visitors.arcAt = {}, 0, {}
    Visitors.bad, Visitors.noReturn, Visitors.warmPick, Visitors.poolCache = {}, {}, nil, nil
    Visitors.made, Visitors.nextSweepMs = 0, 0
    Visitors.metrics = { casts = 0, castFailed = 0, instantiated = 0, instantiateFailed = 0, admitted = 0, released = 0,
        retired = 0, deferred = 0, swept = 0, ledgerWrites = 0, returning = 0, seeded = 0, lastWhy = "-" }
end

function Visitors.qaLine()
    local m = Visitors.metrics
    return "[ALIFE-QA] VisitorDirector casts=" .. tostring(m.casts) .. " failed=" .. tostring(m.castFailed)
        .. " made=" .. tostring(m.instantiated) .. "/" .. tostring(m.instantiateFailed) .. " admitted=" .. tostring(m.admitted)
        .. " released=" .. tostring(m.released) .. " retired=" .. tostring(m.retired) .. " deferred=" .. tostring(Visitors.deferredCount)
        .. " swept=" .. tostring(m.swept) .. " ledger=" .. tostring(m.ledgerWrites) .. " returning=" .. tostring(m.returning)
        .. " seeded=" .. tostring(m.seeded) .. " why=" .. tostring(m.lastWhy)
end

return Visitors
